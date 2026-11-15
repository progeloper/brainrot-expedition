--!nocheck
-- Actual service lifecycle/snapshot code, injected existing profile/bank signal seams.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local Service = require(script.Parent.Parent.Services.RetentionService)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Progress = require(script.Parent.Parent.Data.Phase12Progress)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local View = require(RS.Shared.Utility.RetentionPresentation)
	local function run(callback)
		Service:Stop()
		local f = {
			Data = Schema.CreateDefault(),
			Revision = 0,
			Saved = 0,
			Writable = true,
			listeners = {},
			mirrors = 0,
		}
		local p = { UserId = 814002, Parent = Players, Attributes = {} }
		function p:SetAttribute(k, v)
			self.Attributes[k] = v
		end
		function f:GetReadableData()
			return self.Data
		end
		function f:IsWritable()
			return self.Writable
		end
		function f:GetCurrentRevision()
			return self.Revision
		end
		function f:IsRevisionConfirmed(_, r)
			return self.Saved >= r
		end
		function f:GetDiagnostics()
			return { currentRevision = self.Revision, lastConfirmedSavedRevision = self.Saved }
		end
		for _, name in
			{
				"SubscribeMutations",
				"SubscribeReady",
				"SubscribeSaveConfirmed",
				"SubscribeDiagnostics",
				"SubscribeBankCommitted",
			}
		do
			f[name] = function(self, fn)
				self.listeners[name] = fn
				return {
					Disconnect = function()
						self.listeners[name] = nil
					end,
				}
			end
		end
		function f:Bank(id)
			local before = Fixtures.Clone(self.Data)
			local item = { ItemId = id, BrainrotId = "BRT_001", Metadata = { MutationId = "None" } }
			local receipt = Progress.RecordFirstBank(self.Data, item, nil, 86410)
			if receipt then
				self.Data.Collection.BrainrotInstances[id] =
					{ speciesId = "BRT_001", mutationId = "None", firstBankCompleted = true }
			end
			assert(Schema.ValidateLoaded(self.Data))
			self.Revision += 1
			self.listeners.SubscribeMutations(p, before, self.Data)
			return receipt
		end
		function f:Confirm()
			self.Saved = self.Revision
			self.listeners.SubscribeSaveConfirmed(p, self.Saved, self.Revision)
		end
		local transactions = {}
		function transactions:SubscribeConfirmed(onConfirmed)
			f.listeners.SubscribeTransactionConfirmed = onConfirmed
			return {
				Disconnect = function()
					f.listeners.SubscribeTransactionConfirmed = nil
				end,
			}
		end
		local currency = {
			SyncBalance = function()
				f.mirrors += 1
				p:SetAttribute("Cash", f.Data.Economy.Balance)
			end,
		}
		assert(Service:Start({
			Profile = f,
			Banks = f,
			Transactions = transactions,
			Currency = currency,
			Clock = function()
				return 86410
			end,
			Replication = false,
		}))
		local ok, why = xpcall(function()
			callback(f, p)
		end, debug.traceback)
		Service:Stop()
		for _ in f.listeners do
			error("Retention listener survived Stop")
		end
		assert(ok, why)
	end
	describe("Phase14 CP1 installed service seams and authoritative snapshots", function()
		it("starts idempotently and snapshot requests never freeze an unbanked day", function()
			run(function(f, p)
				expect(Service:Start()).to.equal(false)
				local snapshot = Service:Snapshot(p)
				expect(snapshot.available).to.equal(true)
				expect(snapshot.eligible).to.equal(false)
				expect(snapshot.estimated).to.equal(true)
				expect(f.Data.Retention.Day).to.equal(nil)
				expect(f.Revision).to.equal(0)
			end)
		end)
		it("keeps the first introduction and third-bank paid checkmark behind covering save", function()
			run(function(f, p)
				f:Bank("service:1")
				local pending = Service:Snapshot(p)
				expect(pending.status).to.equal("Saving")
				expect(pending.eligible).to.equal(false)
				f:Confirm()
				expect(Service:Snapshot(p).eligible).to.equal(true)
				f:Bank("service:2")
				f:Confirm()
				local mirrorsBefore = f.mirrors
				f:Bank("service:3")
				pending = Service:Snapshot(p)
				expect(pending.status).to.equal("Saving")
				expect(pending.daily.bring_them_home.paid).to.equal(false)
				expect(pending.completedCount).to.equal(0)
				expect(f.mirrors).to.equal(mirrorsBefore)
				f:Confirm()
				local ready = Service:Snapshot(p)
				expect(ready.daily.bring_them_home.paid).to.equal(true)
				expect(ready.daily.bring_them_home.paidCash).to.equal(750000000)
				expect(ready.completedCount).to.equal(1)
				expect(p.Attributes.Cash).to.equal(750000000)
			end)
		end)
		it("publishes Ready after coordinator release when save observers ran while fenced", function()
			run(function(f, p)
				f:Bank("ordered-confirm:1")
				f.Writable = false
				f:Confirm()
				expect(Service:Snapshot(p).status).to.equal("TemporarilyUnavailable")
				f.Writable = true
				local mirrors = f.mirrors
				f.listeners.SubscribeTransactionConfirmed(p, { state = "Confirmed" })
				expect(Service:Snapshot(p).status).to.equal("Ready")
				expect(f.mirrors).to.equal(mirrors + 1)
				expect(p.Attributes.RetentionCollectionCount).to.equal(1)
			end)
		end)
		it("lock loss preserves ordering and last progress while disabling paid presentation", function()
			run(function(f, p)
				for i = 1, 3 do
					f:Bank("lock:" .. i)
					f:Confirm()
				end
				local before = Service:Snapshot(p)
				f.Writable = false
				local unavailable = Service:Snapshot(p)
				expect(unavailable.revision).to.equal(before.revision)
				expect(unavailable.retentionRevision).to.equal(before.retentionRevision)
				expect(unavailable.eligible).to.equal(true)
				expect(unavailable.available).to.equal(false)
				expect(unavailable.status).to.equal("TemporarilyUnavailable")
				expect(unavailable.daily.bring_them_home.count).to.equal(3)
				expect(View.AcceptSnapshot(before, unavailable)).to.equal(true)
				expect(View.Row(unavailable, unavailable.daily.bring_them_home).paid).to.equal(false)
			end)
		end)
		it("invalid or future action requests cannot mutate any player field", function()
			run(function(f, p)
				local before = Fixtures.Clone(f.Data)
				for _, payload in
					{
						{ action = "Snapshot", amount = 750000000 },
						{ action = "SetProgress" },
						{ action = "ClaimSupplies" },
						{},
					}
				do
					expect(Service:Handle(p, payload).ok).to.equal(false)
				end
				Fixtures.AssertDeepEqual(f.Data, before)
				expect(f.Revision).to.equal(0)
			end)
		end)
		it("wallet debit schedules one bounded pending recovery attempt without polling", function()
			run(function(f, p)
				local original = Service.Recover
				local attempts = 0
				Service.Recover = function(_, subject)
					assert(subject == p, "Retention recovery targeted a different fixture player")
					attempts += 1
				end
				local ok, why = pcall(function()
					local before = Fixtures.Clone(f.Data)
					before.Economy.Balance = 100
					f.Data.Retention.PendingRewards.synthetic = { status = "Pending" }
					f.listeners.SubscribeMutations(p, before, f.Data)
					task.wait()
					expect(attempts).to.equal(1)
				end)
				Service.Recover = original
				assert(ok, why)
			end)
		end)
	end)
end
