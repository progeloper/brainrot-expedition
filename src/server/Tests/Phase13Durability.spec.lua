--!nocheck
-- Synthetic coordinator/backend fixtures; no real users, receipts or storage.
return function()
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local Service = require(script.Parent.Parent.Services.Phase13Service)
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Rules = require(RS.Shared.Utility.Phase13Rules)
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local function player(id)
		local p = { Name = "Phase13Synthetic", UserId = id or 831301, Parent = Players, Attributes = {} }
		function p:SetAttribute(key, value)
			self.Attributes[key] = value
		end
		return p
	end
	local function run(callback, options)
		Service:_ResetForTests()
		local p = player()
		local data = Schema.CreateDefault()
		data.Economy.Balance = 1000000000
		local f = {
			Data = data,
			Revision = 0,
			Saved = 0,
			Session = {},
			Fence = nil,
			SaveListeners = {},
			Confirmed = 0,
			Mutations = 0,
			Thaws = 0,
		}
		function f:GetReadableData()
			return self.Data
		end
		function f:GetCurrentRevision()
			return self.Revision
		end
		function f:GetSessionHandle()
			return self.Session
		end
		function f:IsCurrentSessionHandle(s)
			return self.Session == s
		end
		function f:IsRevisionConfirmed(_, r)
			return self.Saved >= r
		end
		function f:AcquireCritical(_, id)
			if self.Fence then
				return nil, "BUSY"
			end
			self.Fence = { Id = id }
			return self.Fence
		end
		function f:ReleaseCritical(_, h)
			if self.Fence ~= h then
				return false
			end
			self.Fence = nil
			return true
		end
		function f:HasCriticalOperation()
			return self.Fence ~= nil
		end
		function f:SubscribeReady()
			return { Disconnect = function() end }
		end
		function f:SubscribeSaveConfirmed(cb)
			table.insert(self.SaveListeners, cb)
			return { Disconnect = function() end }
		end
		function f:SubscribeSessionRecovered(cb)
			self.Recovered = cb
			return { Disconnect = function() end }
		end
		function f:CommitCriticalMutation(_, h, mutator)
			if self.Fence ~= h then
				return { ok = false, code = "STALE" }
			end
			local before = Fixtures.Clone(self.Data)
			local ok, result = mutator(self.Data)
			if not ok then
				self.Data = before
				return { ok = false, code = result.code }
			end
			local valid, reason = Schema.ValidateLoaded(self.Data)
			assert(valid, reason)
			self.Revision += 1
			self.Mutations += 1
			return { ok = true, revision = self.Revision, result = result }
		end
		function f:Confirm(revision)
			self.Snapshot = assert(Schema.CreateSaveSnapshot(self.Data))
			self.Saved = revision or self.Revision
			for _, cb in self.SaveListeners do
				cb(p, self.Saved)
			end
		end
		function f:RequestSave()
			if options and options.Synchronous then
				self:Confirm()
			end
			return { ok = not (options and options.Uncertain) }
		end
		local income = {}
		function income:BeginCriticalCutover(_, at)
			return { Cutover = at }
		end
		function income:EndCriticalCutover()
			f.Thaws += 1
			if f.AfterCutover then
				f.AfterCutover()
			end
			return true
		end
		local currency
		if options and options.ObserveCashPublication then
			f.CashPublications = {}
			currency = {
				SyncBalance = function(_, subject)
					assert(subject == p, "Exact synthetic wallet owner required")
					table.insert(
						f.CashPublications,
						{ balance = f.Data.Economy.Balance, saved = f.Saved, fence = f.Fence }
					)
					if options.CashPublicationError then
						error("CONTROLLED_CASH_MIRROR_FAILURE")
					end
					p:SetAttribute("Cash", f.Data.Economy.Balance)
					return true
				end,
			}
		end
		Service:Start({
			Profile = f,
			Income = income,
			Currency = currency,
			Now = function()
				return 1000
			end,
			ValidateContext = function()
				return true
			end,
		})
		Service:SubscribeConfirmed(function()
			f.Confirmed += 1
		end)
		local ok, why = xpcall(function()
			callback(p, f)
		end, debug.traceback)
		Service:_ResetForTests()
		assert(ok, why)
	end
	describe("Phase13 covering-save coordinator", function()
		it("holds uncertain debit+reward under one immutable ID and never reapplies on retry", function()
			run(function(p, f)
				local calls = 0
				local function mutate(d)
					calls += 1
					d.Economy.Balance -= 250000000
					d.Phase13.OwnedCartIds.CRT_008 = true
					return true, { id = "CRT_008" }
				end
				expect(Service:CommitCritical(p, "op:uncertain", "CartPurchase", mutate, { sequence = 1 }).state).to.equal(
					"Saving"
				)
				expect(f.Fence ~= nil).to.equal(true)
				expect(f.Confirmed).to.equal(0)
				expect(Service:CommitCritical(p, "op:uncertain", "CartPurchase", mutate, { sequence = 1 }).state).to.equal(
					"Saving"
				)
				expect(Service:CommitCritical(p, "op:other", "CartPurchase", mutate, { sequence = 2 }).code).to.equal(
					"BUSY"
				)
				expect(calls).to.equal(1)
				expect(f.Data.Economy.Balance).to.equal(750000000)
				f:Confirm(0)
				expect(f.Confirmed).to.equal(0)
				expect(Service:IsBusy(p)).to.equal(true)
				f:Confirm(1)
				expect(f.Confirmed).to.equal(1)
				expect(f.Thaws).to.equal(1)
				expect(f.Fence).to.equal(nil)
				expect(Service:CommitCritical(p, "op:uncertain", "CartPurchase", mutate, { sequence = 1 }).state).to.equal(
					"Confirmed"
				)
				expect(calls).to.equal(1)
				expect(f.Snapshot.Phase13.OwnedCartIds.CRT_008).to.equal(true)
				expect(f.Snapshot.Economy.Balance).to.equal(750000000)
			end, { Uncertain = true })
		end)
		it("publishes after source handoff with synchronous injected save confirmation", function()
			run(function(p, f)
				local retired = false
				local visible = false
				local result = Service:CommitCritical(p, "op:sync", "Swap", function()
					return true, {}
				end, {
					onCommitted = function()
						retired = true
						return true
					end,
					onConfirmed = function()
						assert(retired, "Reward before source handoff")
						visible = true
						return true
					end,
				})
				expect(result.state).to.equal("Confirmed")
				expect(visible).to.equal(true)
				expect(f.Confirmed).to.equal(1)
			end, { Synchronous = true })
		end)
		it("retries source publication and confirmed reconciliation without repeating mutation", function()
			run(function(p, f)
				local sourceCalls, visualCalls = 0, 0
				Service:CommitCritical(p, "op:retry", "Rebirth", function(d)
					d.Economy.Balance = 0
					return true, {}
				end, {
					onCommitted = function()
						sourceCalls += 1
						return sourceCalls > 1
					end,
					onConfirmed = function()
						visualCalls += 1
						return visualCalls > 1
					end,
				})
				f:Confirm()
				expect(f.Confirmed).to.equal(0)
				expect(visualCalls).to.equal(0)
				Service:Step()
				expect(f.Confirmed).to.equal(0)
				expect(visualCalls).to.equal(1)
				Service:Step()
				expect(f.Confirmed).to.equal(1)
				expect(f.Mutations).to.equal(1)
				expect(f.Data.Economy.Balance).to.equal(0)
				expect(f.Thaws).to.equal(1)
			end)
		end)
		it("retains the complete200-character paid receipt identity without truncation or collision", function()
			run(function(p, f)
				local id = "paid:" .. string.rep("r", 200)
				local result = Service:CommitCritical(p, id, "PaidReceipt", function()
					return true, { amount = 1 }
				end)
				expect(result.ok).to.equal(true)
				expect(result.operationId).to.equal(id)
				expect(f.Data.Phase13.Operations[id].OperationId).to.equal(id)
				expect(Rules.Validate(f.Data)).to.equal(true)
			end)
		end)
		it(
			"uses the permanent paid ledger after the acknowledgement receipt was pruned during canonical recovery",
			function()
				run(function(p, f)
					local commerce = require(RS.Shared.Utility.Phase13CommerceRules)
					local before = Fixtures.Clone(f.Data)
					local recovered, grants = 0, 0
					local result = Service:CommitCritical(p, "paid:permanent-proof", "PaidCash", function(data)
						grants += 1
						return commerce.GrantReceipt(data, "permanent-proof", 919191, 500000000, 1000, "synthetic")
					end, {
						onRecovered = function(_, canonical, outcome)
							recovered += 1
							expect(outcome).to.equal("Saved")
							expect(canonical.Commerce.ReceiptCount).to.equal(1)
							return true
						end,
					})
					expect(result.state).to.equal("Saving")
					local canonical = assert(Schema.CreateSaveSnapshot(f.Data), "Synthetic paid snapshot invalid")
					canonical.Phase13.Operations, canonical.Phase13.OperationOrder = {}, {}
					canonical.Phase13.LastPrunedSequence, canonical.Phase13.AcknowledgedOperationSequence = 1, 1
					expect(Rules.Validate(canonical)).to.equal(true)
					f.Session = {}
					expect(f.Recovered(p, player(831301), canonical, before)).to.equal(true)
					Service:Step()
					expect(recovered).to.equal(1)
					expect(grants).to.equal(1)
					expect(canonical.Economy.Balance).to.equal(1500000000)
					expect(f.Thaws).to.equal(0)
					expect(f.Confirmed).to.equal(0)
				end)
			end
		)
		it("rejects rebirth preview and commit while any first bank is unconfirmed", function()
			run(function(p, f)
				local banked = require(script.Parent.Parent.Services.BankedBrainrotService)
				local original = banked.HasPendingBank
				banked.HasPendingBank = function(_, subject)
					return subject == p
				end
				local ok, why = xpcall(function()
					expect(Service:QuoteRebirth(p, "EXP_018", "Cash").code).to.equal("BANK_SAVE_PENDING")
					expect(
						Service:Rebirth(
							p,
							{ operationId = "blocked:bank", sequence = 1, rewardId = "EXP_018", route = "Cash" }
						).code
					).to.equal("BANK_SAVE_PENDING")
					expect(f.Mutations).to.equal(0)
				end, debug.traceback)
				banked.HasPendingBank = original
				assert(ok, why)
			end)
		end)
		it("rolls back a failed transition and thaws without a save", function()
			run(function(p, f)
				local result = Service:CommitCritical(p, "op:reject", "Rebirth", function(d)
					d.Economy.Balance = 0
					return false, { code = "CONTROLLED" }
				end)
				expect(result.ok).to.equal(false)
				expect(result.code).to.equal("CONTROLLED")
				expect(f.Data.Economy.Balance).to.equal(1000000000)
				expect(f.Fence).to.equal(nil)
				expect(f.Thaws).to.equal(1)
				expect(f.Revision).to.equal(0)
			end)
		end)
		it("bounds acknowledged receipts and rejects stale sequences after old entries prune", function()
			run(function(p, f)
				for i = 1, 70 do
					Rules.AppendOperation(f.Data, "old:" .. i, "CataloguePurchase", i, 1000, {})
				end
				f.Revision = 70
				f.Saved = 70
				expect(#f.Data.Phase13.OperationOrder).to.equal(64)
				expect(f.Data.Phase13.LastPrunedSequence).to.equal(6)
				local before = Fixtures.Clone(f.Data)
				local result = Service:Purchase(
					p,
					{ operationId = "old:1", sequence = 1, previewRevision = 0, category = "Cart", id = "CRT_008" }
				)
				expect(result.code).to.equal("STALE_OPERATION")
				Fixtures.AssertDeepEqual(f.Data, before)
			end)
		end)
		it("runs durable owned cleanup on departure before releasing the fence", function()
			run(function(p, f)
				local cleanups = 0
				local ownedOriginal = true
				local freshCatch = true
				Service:CommitCritical(p, "op:left", "Rebirth", function(d)
					d.Economy.Balance = 0
					return true, {}
				end, {
					onConfirmed = function(_, detached)
						expect(detached).to.equal(true)
						expect(f.Fence ~= nil).to.equal(true)
						cleanups += 1
						ownedOriginal = false
						return true
					end,
				})
				p.Parent = nil
				f:Confirm()
				expect(cleanups).to.equal(1)
				expect(ownedOriginal).to.equal(false)
				expect(freshCatch).to.equal(true)
				expect(f.Fence).to.equal(nil)
				expect(f.Confirmed).to.equal(1)
				expect(f.Snapshot.Economy.Balance).to.equal(0)
			end)
		end)
	end)
	describe("Phase13 durable wallet display publication", function()
		it(
			"keeps an uncertain collection settlement hidden until a covering save then publishes before confirmation",
			function()
				run(function(p, f)
					p:SetAttribute("Cash", 17)
					local callbackCash
					Service:SubscribeConfirmed(function()
						callbackCash = p.Attributes.Cash
					end)
					local result = Service:CommitCritical(p, "display:collection", "Rebirth", function(data)
						-- ApplyRebirth settles already-earned platform cash into the wallet.
						data.Economy.Balance = 4565902317.738533
						return true, { route = "Collection" }
					end)
					expect(result.state).to.equal("Saving")
					expect(p.Attributes.Cash).to.equal(17)
					expect(#f.CashPublications).to.equal(0)
					f:Confirm(0)
					expect(#f.CashPublications).to.equal(0)
					expect(f.Confirmed).to.equal(0)
					f:Confirm(result.revision)
					expect(p.Attributes.Cash).to.equal(f.Data.Economy.Balance)
					expect(callbackCash).to.equal(f.Data.Economy.Balance)
					expect(#f.CashPublications).to.equal(1)
					expect(f.CashPublications[1].saved >= result.revision).to.equal(true)
					expect(f.CashPublications[1].fence).to.equal(nil)
				end, { ObserveCashPublication = true, Uncertain = true })
			end
		)
		it("publishes an exact zero after cash rebirth without changing the durable receipt", function()
			run(function(p, f)
				p:SetAttribute("Cash", f.Data.Economy.Balance)
				local result = Service:CommitCritical(p, "display:cash", "Rebirth", function(data)
					data.Economy.Balance = 0
					return true, { route = "Cash", sacrificedCash = 1000000000 }
				end)
				f:Confirm()
				expect(p.Attributes.Cash).to.equal(0)
				expect(f.Data.Phase13.Operations[result.operationId].Result.sacrificedCash).to.equal(1000000000)
				expect(f.Mutations).to.equal(1)
			end, { ObserveCashPublication = true })
		end)
		it("reads a current post-boundary paid credit instead of restoring the old sacrifice value", function()
			run(function(p, f)
				f.AfterCutover = function()
					-- A newer canonical credit is present after the sacrifice fence releases.
					expect(f.Fence).to.equal(nil)
					f.Data.Economy.Balance = 500000000
				end
				Service:CommitCritical(p, "display:late-paid", "Rebirth", function(data)
					data.Economy.Balance = 0
					return true, { route = "Cash", sacrificedCash = 1000000000 }
				end)
				f:Confirm()
				expect(p.Attributes.Cash).to.equal(500000000)
				expect(f.Data.Phase13.Operations["display:late-paid"].Result.sacrificedCash).to.equal(1000000000)
				expect(f.Mutations).to.equal(1)
			end, { ObserveCashPublication = true })
		end)
		it("waits for owned reconciliation before refreshing and does not republish on receipt replay", function()
			run(function(p, f)
				local attempts = 0
				Service:CommitCritical(p, "display:reconcile", "Rebirth", function(data)
					data.Economy.Balance = 345.25
					return true, { route = "Collection" }
				end, {
					onConfirmed = function()
						attempts += 1
						return attempts > 1
					end,
				})
				f:Confirm()
				expect(#f.CashPublications).to.equal(0)
				expect(f.Confirmed).to.equal(0)
				Service:Step()
				expect(p.Attributes.Cash).to.equal(345.25)
				expect(#f.CashPublications).to.equal(1)
				f:Confirm()
				Service:Step()
				expect(Service:GetOperation(p, "display:reconcile").state).to.equal("Confirmed")
				expect(#f.CashPublications).to.equal(1)
				expect(f.Mutations).to.equal(1)
				expect(f.Confirmed).to.equal(1)
			end, { ObserveCashPublication = true })
		end)
		it("does not replay a saved grant when the display adapter fails", function()
			run(function(p, f)
				Service:CommitCritical(p, "display:failure", "Rebirth", function(data)
					data.Economy.Balance = 678.5
					return true, { route = "Collection" }
				end)
				f:Confirm()
				Service:Step()
				expect(f.Confirmed).to.equal(1)
				expect(f.Mutations).to.equal(1)
				expect(f.Data.Economy.Balance).to.equal(678.5)
				expect(f.Fence).to.equal(nil)
				expect(#f.CashPublications).to.equal(1)
			end, { ObserveCashPublication = true, CashPublicationError = true })
		end)
	end)
	describe("Phase13 deferred critical departure", function()
		it("finishes the remembered close after save recovery and admits a new same-server session", function()
			Profile:_ResetForTests()
			local t = 1000
			local backend = FakeBackend.new({
				Now = function()
					return t
				end,
				FailBeforeSaveCount = 100,
			})
			Profile:Init({
				Backend = backend,
				UnixNow = function()
					return t
				end,
				MonotonicNow = function()
					return t
				end,
				Wait = function(seconds)
					t += math.max(seconds, 0.001)
				end,
				Random = function()
					return 0
				end,
				KickOnFailure = false,
			})
			local p = player(831303)
			local ok, why = xpcall(function()
				expect(Profile:LoadPlayerAsync(p).ok).to.equal(true)
				local closeRequests = 0
				Profile:SubscribeCloseRequested(function(subject)
					expect(subject).to.equal(p)
					closeRequests += 1
				end)
				local handle = assert(Profile:AcquireCritical(p, "departure:recover"), "Critical fence unavailable")
				local mutation = Profile:CommitCriticalMutation(p, handle, function(d)
					d.Economy.Balance = 750000000
					d.Phase13.OwnedCartIds.CRT_008 = true
					return true, {}
				end)
				expect(mutation.ok).to.equal(true)
				local cleanups = 0
				Profile:SubscribeSaveConfirmed(function(subject, saved)
					if subject == p and saved >= mutation.revision and Profile:HasCriticalOperation(p) then
						cleanups += 1
						expect(Profile:ReleaseCritical(p, handle)).to.equal(true)
					end
				end)
				p.Parent = nil
				expect(Profile:ClosePlayerAsync(p, "PlayerRemoving").code).to.equal("CRITICAL_CLOSE_PENDING")
				expect(Profile:GetDiagnostics(p).closing).to.equal(false)
				expect(cleanups).to.equal(0)
				backend.FailBeforeSaveCount = 0
				expect(Profile:SaveNowAsync(p, "SyntheticBackendRecovery").ok).to.equal(true)
				expect(cleanups).to.equal(1)
				Profile:Step()
				expect(Profile:GetReadableData(p)).to.equal(nil)
				local rejoined = player(p.UserId)
				expect(Profile:LoadPlayerAsync(rejoined).ok).to.equal(true)
				expect(Profile:GetReadableData(rejoined).Economy.Balance).to.equal(750000000)
				expect(Profile:GetReadableData(rejoined).Phase13.OwnedCartIds.CRT_008).to.equal(true)
				expect(cleanups).to.equal(1)
				expect(closeRequests).to.equal(1)
			end, debug.traceback)
			Profile:_ResetForTests()
			assert(ok, why)
		end)
	end)
	describe("Phase13 post-lease critical canonical recovery", function()
		it("runs every independent recovery observer before retrying pending dependencies", function()
			Profile:_ResetForTests()
			local t = 1000
			local backend = FakeBackend.new({
				Now = function()
					return t
				end,
			})
			Profile:Init({
				Backend = backend,
				UnixNow = function()
					return t
				end,
				MonotonicNow = function()
					return t
				end,
				KickOnFailure = false,
			})
			local oldPlayer, newPlayer = player(831321), player(831321)
			local ok, why = xpcall(function()
				expect(Profile:LoadPlayerAsync(oldPlayer).ok).to.equal(true)
				assert(Profile:AcquireCritical(oldPlayer, "observer:dependency"), "Critical source fence required")
				oldPlayer.Parent = nil
				t = 2000
				Profile:Step()
				local calls, ready = { 0, 0, 0 }, 0
				for i = 1, 2 do
					Profile:SubscribeSessionRecovered(function()
						calls[i] += 1
						return calls[i] > 1
					end)
				end
				Profile:SubscribeSessionRecovered(function()
					calls[3] += 1
					return true
				end)
				Profile:SubscribeReady(function(p)
					if p == newPlayer then
						ready += 1
					end
				end)
				expect(Profile:LoadPlayerAsync(newPlayer).code).to.equal("RECOVERY_RECONCILIATION_PENDING")
				-- Hash iteration order cannot prevent either pending observer or its
				-- independently successful source dependency from running.
				expect(calls[1]).to.equal(1)
				expect(calls[2]).to.equal(1)
				expect(calls[3]).to.equal(1)
				expect(ready).to.equal(0)
				Profile:Step()
				expect(calls[1]).to.equal(2)
				expect(calls[2]).to.equal(2)
				expect(calls[3]).to.equal(1)
				expect(ready).to.equal(1)
			end, debug.traceback)
			Profile:_ResetForTests()
			assert(ok, why)
		end)
		for _, persisted in { false, true } do
			it(
				"reacquires expired "
					.. (if persisted then "lost-response saved" else "prewrite failed")
					.. " sacrifice without replay",
				function()
					Service:_ResetForTests()
					Profile:_ResetForTests()
					local t = 1000
					local backend = FakeBackend.new({
						Now = function()
							return t
						end,
					})
					Profile:Init({
						Backend = backend,
						UnixNow = function()
							return t
						end,
						MonotonicNow = function()
							return t
						end,
						Wait = function(seconds)
							t += math.max(seconds, 0.001)
						end,
						Random = function()
							return 0
						end,
						KickOnFailure = false,
					})
					local oldPlayer, newPlayer = player(831320), player(831320)
					local intermediate
					local ok, why = xpcall(function()
						expect(Profile:LoadPlayerAsync(oldPlayer).ok).to.equal(true)
						expect(Profile:CommitMutation(oldPlayer, function(data)
							data.Economy.Balance = 1000.25
							for i = 1, 12 do
								local id = "recover:owned:" .. i
								data.Collection.BrainrotInstances[id] =
									{ speciesId = "BRT_019", mutationId = "None", firstBankCompleted = true }
								data.Base.Slots[tostring(i)] = { brainrotId = id, accumulatedCash = i + 0.25 }
							end
							return true, {}
						end).ok).to.equal(true)
						expect(Profile:SaveNowAsync(oldPlayer, "SyntheticSeed").ok).to.equal(true)
						local previousHandle = Profile:GetSessionHandle(oldPlayer)
						local originalSave = backend.Save
						function backend:Save(...)
							if persisted then
								originalSave(self, ...)
							end
							return { ok = false, code = "SAVE_UNCERTAIN", uncertain = true }
						end
						local originalPresent, freshCargoPresent = true, true
						local mutationCalls, confirmedCalls, recoveredCalls, cleanupCalls, readyCalls = 0, 0, 0, 0, 0
						local oldFinalized = false
						Profile:RegisterCloseFinalizer(function(subject)
							if subject == oldPlayer then
								oldFinalized = true
							end
						end)
						Profile:SubscribeReady(function(subject)
							if subject == newPlayer then
								readyCalls += 1
							end
						end)
						local income = {}
						function income:BeginCriticalCutover()
							return {}
						end
						function income:EndCriticalCutover()
							error("Do not thaw a recovered departed session")
						end
						Service:Start({
							Profile = Profile,
							Income = income,
							Now = function()
								return t
							end,
							ReconcileRecovery = function(subject, replacement, canonical, previous)
								expect(subject == oldPlayer or subject == intermediate).to.equal(true)
								expect(replacement).to.equal(newPlayer)
								expect(oldFinalized).to.equal(true)
								expect(Profile:GetStatus(newPlayer)).to.equal("Recovering")
								expect(Profile:IsWritable(newPlayer)).to.equal(false)
								expect(Profile:IsCurrentSessionHandle(previousHandle)).to.equal(false)
								expect(table.isfrozen(canonical.Collection.BrainrotInstances)).to.equal(true)
								expect(previous.Collection.BrainrotInstances["recover:owned:1"] ~= nil).to.equal(true)
								cleanupCalls += 1
								if persisted and cleanupCalls == 1 then
									return false
								end
								originalPresent = canonical.Collection.BrainrotInstances["recover:owned:1"] ~= nil
								return true
							end,
						})
						local data = Profile:GetReadableData(oldPlayer)
						local quote = Rules.QuoteRebirth(data, "EXP_018", "Collection")
						expect(quote.ok).to.equal(true)
						local result = Service:CommitCritical(
							oldPlayer,
							"recovery:collection",
							"Rebirth",
							function(current, at)
								mutationCalls += 1
								return Rules.ApplyRebirth(current, {
									rewardId = "EXP_018",
									route = "Collection",
									previewRevision = quote.previewRevision,
									inventorySignature = quote.inventorySignature,
								}, at)
							end,
							{
								onConfirmed = function()
									confirmedCalls += 1
									return true
								end,
								onRecovered = function(_, canonical, outcome)
									recoveredCalls += 1
									expect(outcome).to.equal(if persisted then "Saved" else "CanonicalAbsent")
									expect(canonical.Phase13.RebirthCount).to.equal(if persisted then 1 else 0)
									return true
								end,
							}
						)
						expect(result.state).to.equal("Saving")
						oldPlayer.Parent = nil
						expect(Profile:ClosePlayerAsync(oldPlayer, "PlayerRemoving").code).to.equal(
							"CRITICAL_CLOSE_PENDING"
						)
						t = 2000
						Profile:Step()
						expect(Profile:GetStatus(oldPlayer)).to.equal("Failed")
						backend.AcquireFailure = "ACQUIRE_FAILED"
						expect(Profile:LoadPlayerAsync(newPlayer).ok).to.equal(false)
						expect(Profile:IsCurrentSessionHandle(previousHandle)).to.equal(true)
						expect(recoveredCalls).to.equal(0)
						expect(oldFinalized).to.equal(false)
						backend.AcquireFailure = nil
						backend.Save = originalSave
						local acquired = Profile:LoadPlayerAsync(newPlayer)
						if persisted then
							expect(acquired.code).to.equal("RECOVERY_RECONCILIATION_PENDING")
							expect(readyCalls).to.equal(0)
							-- Cleanup itself may outlast a new lease. A later acquisition
							-- must reconcile both displaced actors before publishing Ready.
							intermediate = newPlayer
							intermediate.Parent = nil
							t = 4000
							Profile:Step()
							expect(Profile:GetStatus(intermediate)).to.equal("Failed")
							newPlayer = player(oldPlayer.UserId)
							expect(Profile:LoadPlayerAsync(newPlayer).ok).to.equal(true)
						else
							expect(acquired.ok).to.equal(true)
						end
						expect(Profile:GetStatus(newPlayer)).to.equal("Ready")
						expect(Profile:IsWritable(newPlayer)).to.equal(true)
						expect(readyCalls).to.equal(1)
						expect(mutationCalls).to.equal(1)
						expect(confirmedCalls).to.equal(0)
						expect(recoveredCalls).to.equal(1)
						expect(originalPresent).to.equal(not persisted)
						expect(freshCargoPresent).to.equal(true)
						expect(Rules.GetCapacity(Profile:GetReadableData(newPlayer))).to.equal(
							if persisted then 18 else 12
						)
						expect(Rules.Cash(Profile:GetReadableData(newPlayer))).to.equal(1081.25)
						expect(Service:IsBusy(oldPlayer)).to.equal(false)
						expect(Profile:RequestSave(oldPlayer, "StaleCallback").ok).to.equal(false)
						Service:Step()
						expect(confirmedCalls).to.equal(0)
					end, debug.traceback)
					Service:_ResetForTests()
					Profile:_ResetForTests()
					assert(ok, why)
				end
			)
		end
	end)
	describe("Phase13 authoritative acquire resolves old pending banks", function()
		for _, saved in { false, true } do
			it(
				"resolves only after new acquisition proves "
					.. (if saved then "saved ownership" else "absent ownership"),
				function()
					local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)
					local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
					Service:_ResetForTests()
					Banked:_ResetForTests({ Profile = Profile })
					Profile:_ResetForTests()
					local t = 1000
					local backend = FakeBackend.new({
						Now = function()
							return t
						end,
					})
					local originalSave = backend.Save
					function backend:Save(...)
						if saved then
							originalSave(self, ...)
						end
						return { ok = false, code = "SAVE_UNCERTAIN", uncertain = true }
					end
					local function init()
						Profile:Init({
							Backend = backend,
							UnixNow = function()
								return t
							end,
							MonotonicNow = function()
								return t
							end,
							Wait = function(seconds)
								t += math.max(0.001, seconds)
							end,
							Random = function()
								return 0
							end,
							KickOnFailure = false,
						})
					end
					init()
					Banked:Start()
					local oldPlayer = player(831311)
					local fresh =
						{ ItemId = "pending:canonical", BrainrotId = "BRT_007", MutationId = "None", Metadata = {} }
					local confirms, releases, oldPublications = 0, 0, 0
					local previousConfirm, previousAbort, previousCanAbort =
						World.ConfirmPendingBank,
						World.AbortPendingBankToFreshRelease,
						World.CanAbortPendingBankToFreshRelease
					World.ConfirmPendingBank = function(record, id)
						assert(
							record == fresh and id == "Bank:" .. fresh.ItemId,
							"Recovered pending-bank identity changed"
						)
						confirms += 1
						return true
					end
					World.CanAbortPendingBankToFreshRelease = function()
						return true
					end
					World.AbortPendingBankToFreshRelease = function(record, id, pose)
						assert(
							record == fresh and id == "Bank:" .. fresh.ItemId,
							"Recovered pending-bank identity changed"
						)
						assert(pose == CFrame.new(19, 7, 23), "Exact captured departure pose changed")
						releases += 1
						return true
					end
					local ok, why = xpcall(function()
						assert(Profile:LoadPlayerAsync(oldPlayer).ok, "Synthetic old owner failed acquisition")
						local write = Profile:CommitMutation(oldPlayer, function(d)
							d.Collection.BrainrotInstances[fresh.ItemId] =
								{ speciesId = "BRT_007", mutationId = "None", firstBankCompleted = true }
							d.Base.Slots["1"].brainrotId = fresh.ItemId
							return true, {}
						end)
						local requestSave = Profile.RequestSave
						Profile.RequestSave = function()
							return { ok = true }
						end
						Banked:RegisterPendingBank(oldPlayer, fresh, write.revision, function()
							oldPublications += 1
							return true
						end, CFrame.new(19, 7, 23))
						Profile.RequestSave = requestSave
						expect(Banked:HasPendingBank(oldPlayer)).to.equal(true)
						expect(Profile:SaveNowAsync(oldPlayer, "SyntheticAmbiguousBank").ok).to.equal(false)
						expect(oldPublications).to.equal(0)
						expect(confirms + releases).to.equal(0)
						local nextPlayer = player(oldPlayer.UserId)
						expect(Banked:ReconcilePendingBanksOnAcquire(nextPlayer).ok).to.equal(false)
						expect(confirms + releases).to.equal(0)
						-- Simulate the expired old process/session owner while retaining this
						-- server's counted pending record; no read/profile rewrite shortcut.
						oldPlayer.Parent = nil
						Profile:_ResetForTests()
						t += 200
						init()
						assert(Profile:LoadPlayerAsync(nextPlayer).ok, "Synthetic new owner failed acquisition")
						local acquired = Profile:GetReadableData(nextPlayer)
						expect(acquired.Collection.BrainrotInstances[fresh.ItemId] ~= nil).to.equal(saved)
						local recovered = Banked:ReconcilePendingBanksOnAcquire(nextPlayer)
						expect(recovered.ok).to.equal(true)
						expect(confirms).to.equal(if saved then 1 else 0)
						expect(releases).to.equal(if saved then 0 else 1)
						expect(oldPublications).to.equal(0)
						expect(Banked:IsBankPending(nextPlayer, fresh.ItemId)).to.equal(false)
						Banked:ReconcilePendingBanksOnAcquire(nextPlayer)
						expect(confirms + releases).to.equal(1)
					end, debug.traceback)
					World.ConfirmPendingBank, World.AbortPendingBankToFreshRelease, World.CanAbortPendingBankToFreshRelease =
						previousConfirm, previousAbort, previousCanAbort
					Banked:_ResetForTests()
					Profile:_ResetForTests()
					assert(ok, why)
				end
			)
		end
	end)
	describe("Phase13 actual profile-writer fence", function()
		it("blocks ordinary mutations and saves debit+ownership together after an uncertain response", function()
			Service:_ResetForTests()
			Profile:_ResetForTests()
			local t = 1000
			local backend = FakeBackend.new({
				Now = function()
					return t
				end,
				CommitThenFailSaveCount = 1,
			})
			Profile:Init({
				Backend = backend,
				UnixNow = function()
					return t
				end,
				MonotonicNow = function()
					return t
				end,
				Wait = function(seconds)
					t += math.max(seconds, 0.001)
				end,
				Random = function()
					return 0
				end,
				KickOnFailure = false,
			})
			local p = player(831302)
			local ok, why = xpcall(function()
				expect(Profile:LoadPlayerAsync(p).ok).to.equal(true)
				expect(Profile:CommitMutation(p, function(d)
					d.Economy.Balance = 1000000000
					return true, {}
				end).ok).to.equal(true)
				local handle = assert(Profile:AcquireCritical(p, "writer:1"))
				local mutation = Profile:CommitCriticalMutation(p, handle, function(d)
					d.Economy.Balance -= 250000000
					d.Phase13.OwnedCartIds.CRT_008 = true
					return true, {}
				end)
				expect(mutation.ok).to.equal(true)
				expect(Profile:CommitMutation(p, function(d)
					d.Economy.Balance += 1
					return true, {}
				end).ok).to.equal(false)
				expect(Profile:GetReadableData(p).Economy.Balance).to.equal(750000000)
				expect(Profile:SaveNowAsync(p, "SyntheticCritical").ok).to.equal(true)
				expect(Profile:IsRevisionConfirmed(p, mutation.revision)).to.equal(true)
				local stored
				for _, record in backend.Records do
					stored = record.Data
				end
				expect(stored.Economy.Balance).to.equal(750000000)
				expect(stored.Phase13.OwnedCartIds.CRT_008).to.equal(true)
				expect(Profile:HasCriticalOperation(p)).to.equal(true)
				expect(Profile:ReleaseCritical(p, handle)).to.equal(true)
			end, debug.traceback)
			Profile:_ResetForTests()
			assert(ok, why)
		end)
	end)
end
