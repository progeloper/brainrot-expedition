--!nocheck
-- Isolated domain integration only. Real profile/coordinator/rules with a synthetic
-- backend/player are not C02/C03, real input, native transport or DataStore proof.
return function()
	local RS, Players = game:GetService("ReplicatedStorage"), game:GetService("Players")
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local Coordinator = require(script.Parent.Parent.Services.Phase13Service)
	local Retention = require(script.Parent.Parent.Services.RetentionService)
	local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
	local Storage = require(script.Parent.Parent.Classes.BaseStorage)
	local Progress = require(script.Parent.Parent.Data.Phase12Progress)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Rules = require(RS.Shared.Utility.RetentionRules)
	local View = require(RS.Shared.Utility.RetentionPresentation)
	local CosmeticRules = require(RS.Shared.Utility.Phase14CosmeticRules)
	local Presentation = require(RS.Shared.Utility.BaseSlotPresentation)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)
	local function awaitCondition(predicate, label, timeout)
		local deadline = os.clock() + (timeout or 3)
		repeat
			if predicate() then
				return
			end
			task.wait()
		until os.clock() >= deadline
		error("Bounded domain fixture timeout: " .. label)
	end
	local function recordBank(data, id, species, at, mutation)
		local receipt = Progress.RecordFirstBank(data, {
			ItemId = id,
			BrainrotId = species or "BRT_001",
			Metadata = {
				MutationId = mutation or "None",
				AcquisitionKind = "Hunt",
			},
		}, nil, at)
		if receipt then
			data.Collection.BrainrotInstances[id] = {
				speciesId = receipt.speciesId,
				mutationId = receipt.mutationId,
				firstBankCompleted = true,
				firstBankedAt = receipt.firstBankedAt,
				metadata = { MutationId = receipt.mutationId, FirstBankCompleted = true },
			}
		end
		return receipt
	end
	local function fixture(callback, options)
		options = options or {}
		Retention:Stop()
		Coordinator:_ResetForTests()
		Income:Stop()
		Profile:_ResetForTests()
		local clock = { Unix = 86410, Mono = 1000, Persistence = 86410 }
		local backend = FakeBackend.new({
			Now = function()
				return clock.Persistence
			end,
		})
		local sequence = 0
		Profile:Init({
			Backend = backend,
			UnixNow = function()
				return clock.Persistence
			end,
			MonotonicNow = function()
				return clock.Mono
			end,
			Wait = function(seconds)
				clock.Mono += math.max(seconds, 0.001)
				clock.Persistence += math.max(seconds, 0.001)
			end,
			Random = function()
				return 0
			end,
			GenerateOperationId = function(prefix)
				sequence += 1
				return prefix .. ":domain:" .. sequence
			end,
			KickOnFailure = false,
		})
		local function player()
			if options.ActorFactory then
				return options.ActorFactory()
			end
			local p = {
				Name = "Phase14DomainSynthetic",
				UserId = options.UserId or 814141,
				Parent = Players,
				Attributes = {},
			}
			function p:SetAttribute(k, v)
				self.Attributes[k] = v
			end
			function p:GetAttribute(k)
				return self.Attributes[k]
			end
			function p:Kick(message)
				self.Kicked = message
			end
			return p
		end
		local f = {
			Player = player(),
			Clock = clock,
			Backend = backend,
			Gates = {},
			Owned = {},
			Restores = {},
			NextRequestAt = 0,
		}
		assert(Profile:LoadPlayerAsync(f.Player).ok, "synthetic load")
		Currency:_ResetForTests(Profile, {
			Now = function()
				return clock.Unix
			end,
		})
		Banked:_ResetForTests({ Profile = Profile, Currency = Currency })
		Banked:Start()
		local cutover = {}
		function cutover:BeginCriticalCutover(_, at)
			return { At = at }
		end
		function cutover:EndCriticalCutover()
			return true
		end
		local function start()
			assert(Coordinator:Start({
				Profile = Profile,
				Income = cutover,
				Currency = Currency,
				Now = function()
					return clock.Unix
				end,
				ValidateContext = function()
					return true
				end,
			}))
			assert(Retention:Start({
				Profile = Profile,
				Transactions = Coordinator,
				Banks = Banked,
				Currency = Currency,
				Clock = function()
					if f.ClockPlan and #f.ClockPlan > 0 then
						clock.Unix = table.remove(f.ClockPlan, 1)
					end
					return clock.Unix
				end,
				Replication = false,
			}))
		end
		start()
		function f:Data()
			return assert(Profile:GetReadableData(self.Player))
		end
		function f:Mutate(fn)
			local r = Profile:CommitMutation(self.Player, function(data)
				fn(data)
				return true, { code = "DOMAIN_SETUP" }
			end)
			assert(r.ok, r.code)
			return r
		end
		function f:Seed(count)
			self:Mutate(function(data)
				data.Economy.Balance = 0.375
				for i = 1, count or 1 do
					recordBank(data, "domain:seed:" .. i, string.format("BRT_%03d", i), clock.Unix, options.Mutation)
				end
			end)
			assert(Profile:SaveNowAsync(self.Player, "DomainBaseline").ok, "baseline covering save")
			assert(Retention:Publish(self.Player).status == "Ready", "baseline Ready publication")
		end
		function f:Action(payload)
			-- Respect the shipping request throttle; condition waits below observe saves.
			while os.clock() < self.NextRequestAt do
				task.wait()
			end
			self.NextRequestAt = os.clock() + 0.26
			return Retention:Handle(self.Player, payload)
		end
		function f:Confirmed(id)
			awaitCondition(function()
				Coordinator:Step()
				return Coordinator:GetOperation(self.Player, id).state == "Confirmed"
					and Profile:IsWritable(self.Player)
			end, "covering confirmation " .. id)
			return Coordinator:GetOperation(self.Player, id)
		end
		function f:Hold(operationId, mode, afterReturn)
			local gate = { Released = false, Entered = false, Exited = false }
			table.insert(self.Gates, gate)
			local oldSave = backend.Save
			if mode == "LostAck" then
				backend.CommitThenFailSaveCount = 1
			end
			if mode == "BeforeCommit" then
				backend.FailBeforeSaveCount = 1
			end
			backend.Save = function(backendSelf, key, token, saveId, revision, snapshot, lease)
				local response = oldSave(backendSelf, key, token, saveId, revision, snapshot, lease)
				if not gate.Entered and snapshot.Phase13.Operations[operationId] then
					gate.Entered, gate.Response, gate.Thread = true, response, coroutine.running()
					gate.BackendData = Fixtures.Clone(backendSelf:GetRecord(key).Data)
					awaitCondition(function()
						return gate.Released
					end, "release owned save gate", 4)
					if afterReturn then
						afterReturn()
					end
					gate.Exited = true
				end
				return response
			end
			return gate
		end
		function f:RestartPresentation()
			Retention:Stop()
			assert(Retention:Start({
				Profile = Profile,
				Transactions = Coordinator,
				Banks = Banked,
				Currency = Currency,
				Clock = function()
					return clock.Unix
				end,
				Replication = false,
			}))
		end
		function f:Rejoin(subscribeBeforeAcquire)
			Retention:Stop()
			Coordinator:_ResetForTests()
			assert(Profile:ClosePlayerAsync(self.Player, "SyntheticDomainRejoin").ok, "synthetic close")
			self.Player.Parent = nil
			self.Player = player()
			if subscribeBeforeAcquire then
				start()
				assert(Profile:LoadPlayerAsync(self.Player).ok, "synthetic reacquisition after subscriptions")
			else
				assert(Profile:LoadPlayerAsync(self.Player).ok, "synthetic reacquisition")
				start()
			end
			Retention:Publish(self.Player)
			self.NextRequestAt = 0
		end
		local ok, failure = xpcall(function()
			callback(f)
		end, debug.traceback)
		for _, gate in f.Gates do
			gate.Released = true
		end
		for _, gate in f.Gates do
			if gate.Entered and not gate.Exited then
				local drained = pcall(awaitCondition, function()
					return gate.Exited
				end, "owned save cleanup", 1)
				if not drained and gate.Thread and coroutine.status(gate.Thread) ~= "dead" then
					pcall(task.cancel, gate.Thread)
				end
			end
		end
		for i = #f.Restores, 1, -1 do
			f.Restores[i]()
		end
		Retention:Stop()
		Coordinator:_ResetForTests()
		Income:Stop()
		Banked:_ResetForTests()
		Currency:_ResetForTests()
		Profile:_ResetForTests()
		for i = #f.Owned, 1, -1 do
			f.Owned[i]:Destroy()
		end
		assert(ok, failure)
	end
	describe("Phase14 actual handler through existing coordinator and profile writer", function()
		it(
			"holds supply behind actual critical fence then confirms and replays once across synthetic reacquisition",
			function()
				fixture(function(f)
					f:Seed(1)
					local baseline = Fixtures.Clone(Retention:Snapshot(f.Player))
					local operation = "retention:supply-date:1"
					local gate = f:Hold(operation, "Normal")
					local result = f:Action({ action = "ClaimSupply" })
					awaitCondition(function()
						return gate.Entered
					end, "save entered")
					expect(result.state).to.equal("Saving")
					expect(Profile:IsWritable(f.Player)).to.equal(false)
					expect(Profile:HasCriticalOperation(f.Player)).to.equal(true)
					local pending = Retention:Snapshot(f.Player)
					expect(pending.status).to.equal("Saving")
					expect(pending.supplies.lifetimeClaims).to.equal(baseline.supplies.lifetimeClaims)
					expect(pending.supplies.lastPaid).to.equal(baseline.supplies.lastPaid)
					expect(pending.supplies.claimable).to.equal(false)
					expect(pending.completedCount).to.equal(baseline.completedCount)
					expect(View.Supply(pending, false).state).to.equal("Saving")
					Fixtures.AssertDeepEqual(pending.collection, baseline.collection)
					gate.Released = true
					f:Confirmed(operation)
					local ready = Retention:Snapshot(f.Player)
					expect(ready.status).to.equal("Ready")
					expect(ready.supplies.lifetimeClaims).to.equal(1)
					expect(ready.supplies.lastAmountCash).to.equal(250000000)
					expect(f:Data().Economy.Balance).to.equal(250000000.375)
					local revision = Profile:GetCurrentRevision(f.Player)
					expect(f:Action({ action = "ClaimSupply" }).state).to.equal("Confirmed")
					expect(Profile:GetCurrentRevision(f.Player)).to.equal(revision)
					f:Rejoin()
					expect(f:Action({ action = "ClaimSupply" }).state).to.equal("Confirmed")
					expect(f:Data().Economy.Balance).to.equal(250000000.375)
					expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(1)
					expect(f:Data().Commerce.StarterPackClaimed).to.equal(false)
				end)
			end
		)
		it("fails closed without a Ready baseline while the actual profile is fenced", function()
			fixture(function(f)
				f:Seed(1)
				f:RestartPresentation()
				local gate = f:Hold("retention:supply-date:1", "Normal")
				f:Action({ action = "ClaimSupply" })
				awaitCondition(function()
					return gate.Entered
				end, "first use fenced")
				local pending = Retention:Snapshot(f.Player)
				expect(pending.status).to.equal("Saving")
				expect(pending.available).to.equal(false)
				expect(pending.supplies).to.equal(nil)
				expect(pending.collection).to.equal(nil)
				expect(next(pending.daily)).to.equal(nil)
				gate.Released = true
				f:Confirmed("retention:supply-date:1")
				expect(Retention:Snapshot(f.Player).status).to.equal("Ready")
			end)
		end)
		it("invalidates the confirmed cache on changed generation or real non-Ready status", function()
			fixture(function(f)
				f:Seed(1)
				local original = Profile.GetDiagnostics
				local alteredGeneration, status
				Profile.GetDiagnostics = function(self, p)
					local d = original(self, p)
					if d then
						d = Fixtures.Clone(d)
						if alteredGeneration then
							d.generation = alteredGeneration
						end
						if status then
							d.status = status
						end
					end
					return d
				end
				table.insert(f.Restores, function()
					Profile.GetDiagnostics = original
				end)
				local generation = original(Profile, f.Player).generation
				local gate = f:Hold("retention:supply-date:1", "Normal")
				f:Action({ action = "ClaimSupply" })
				awaitCondition(function()
					return gate.Entered
				end, "cache session fence")
				alteredGeneration = generation + 1
				local changed = Retention:Snapshot(f.Player)
				expect(changed.status).to.equal("Saving")
				expect(changed.available).to.equal(false)
				expect(changed.collection).to.equal(nil)
				status = "Recovering"
				expect(Retention:Snapshot(f.Player).status).to.equal("TemporarilyUnavailable")
				status = "Failed"
				expect(Retention:Snapshot(f.Player).status).to.equal("TemporarilyUnavailable")
				status, alteredGeneration = nil, nil
				expect(Retention:Snapshot(f.Player).available).to.equal(false)
				gate.Released = true
				f:Confirmed("retention:supply-date:1")
			end)
		end)
		it("persists pin, owned feature, milestone and None without Cash or optimistic selection", function()
			fixture(function(f)
				f:Seed(5)
				local cash = f:Data().Economy.Balance
				local pin = f:Action({ action = "PinGoal", goalId = "Cargo:1" })
				f:Confirmed(pin.operationId)
				local feature = f:Action({ action = "FeatureDiscovery", speciesId = "BRT_001" })
				f:Confirmed(feature.operationId)
				local prior = Retention:Snapshot(f.Player)
				local oldSave = f.Backend.Save
				local gate = { Released = false, Entered = false, Exited = false }
				table.insert(f.Gates, gate)
				f.Backend.Save = function(self, key, token, id, revision, snapshot, lease)
					local response = oldSave(self, key, token, id, revision, snapshot, lease)
					if not gate.Entered and snapshot.Retention.SelectedTitle == "P14_TITLE_COLLECTOR" then
						gate.Entered, gate.Thread = true, coroutine.running()
						awaitCondition(function()
							return gate.Released
						end, "equip gate", 4)
						gate.Exited = true
					end
					return response
				end
				local equip = f:Action({ action = "EquipMilestone", slot = "Title", value = "P14_TITLE_COLLECTOR" })
				awaitCondition(function()
					return gate.Entered
				end, "equip entered")
				expect(Retention:Snapshot(f.Player).collection.selectedTitle).to.equal(prior.collection.selectedTitle)
				local pending = Retention:Snapshot(f.Player)
				expect(pending.completedCount).to.equal(prior.completedCount)
				expect(pending.daily.bring_them_home.paid).to.equal(true)
				expect(pending.daily.field_research.paid).to.equal(true)
				gate.Released = true
				f:Confirmed(equip.operationId)
				f:Rejoin()
				expect(f:Data().Progression.TrackedUpgradeId).to.equal("Cargo:1")
				expect(f:Data().Retention.FeaturedSpeciesId).to.equal("BRT_001")
				expect(f:Data().Retention.SelectedTitle).to.equal("P14_TITLE_COLLECTOR")
				expect(Retention:Publish(f.Player).collection.title).to.equal("Collector")
				for _, payload in
					{
						{ action = "FeatureDiscovery", speciesId = "BRT_032" },
						{ action = "EquipMilestone", slot = "Title", value = "P14_TITLE_EXPEDITION_EXPERT" },
					}
				do
					local before = Fixtures.Clone(f:Data())
					expect(f:Action(payload).committed == true).to.equal(false)
					Fixtures.AssertDeepEqual(f:Data(), before)
					expect(Profile:HasCriticalOperation(f.Player)).to.equal(false)
				end
				for _, payload in
					{
						{ action = "PinGoal", goalId = "None" },
						{ action = "FeatureDiscovery", speciesId = "None" },
						{ action = "EquipMilestone", slot = "Title", value = "None" },
					}
				do
					local r = f:Action(payload)
					f:Confirmed(r.operationId)
				end
				f:Rejoin()
				expect(f:Data().Progression.TrackedUpgradeId).to.equal(nil)
				expect(f:Data().Retention.FeaturedSpeciesId).to.equal(nil)
				expect(f:Data().Retention.SelectedTitle).to.equal("None")
				Retention:Publish(f.Player)
				expect(f.Player.Attributes.RetentionTitleLabel).to.equal("")
				expect(f:Data().Economy.Balance).to.equal(cash)
			end)
		end)
		for _, mode in { "BeforeCommit", "LostAck" } do
			it("recovers " .. mode .. " supply across UTC rollover at old frozen U without a duplicate", function()
				fixture(function(f)
					f:Seed(1)
					local milestone = if mode == "LostAck" then 7 else 1
					if milestone == 7 then
						f:Mutate(function(data)
							for day = 1, 6 do
								assert(Rules.ClaimSupply(data, day * 86400 + 20))
							end
						end)
					end
					f.Clock.Unix = milestone * 86400 + 86399
					f:Mutate(function(data)
						recordBank(data, "domain:freeze:" .. mode, "BRT_001", f.Clock.Unix)
						data.WorldProgression.PersonalUnlocks.Beach = { source = "purchase" }
					end)
					assert(Profile:SaveNowAsync(f.Player, "PreRollover").ok, "pre-rollover covering save")
					local before = Fixtures.Clone(f:Data())
					Retention:Publish(f.Player)
					local operation = "retention:supply-date:" .. milestone
					local gate = f:Hold(operation, mode, function()
						f.Clock.Unix = (milestone + 1) * 86400 + 5
					end)
					local result = f:Action({ action = "ClaimSupply" })
					awaitCondition(function()
						return gate.Entered
					end, "fault entered")
					expect(result.state).to.equal("Saving")
					expect(gate.Response.ok).to.equal(false)
					expect(gate.BackendData.Retention.Supplies.lifetimeClaims).to.equal(
						if mode == "BeforeCommit" then before.Retention.Supplies.lifetimeClaims else milestone
					)
					local pending = Retention:Snapshot(f.Player)
					expect(pending.status).to.equal("Saving")
					expect(pending.supplies.lifetimeClaims).to.equal(before.Retention.Supplies.lifetimeClaims)
					if milestone == 7 then
						expect(pending.supplies.checkpoints[1].owned).to.equal(false)
					end
					-- During old-date save, a new-date read may not display old daily credit.
					f.Clock.Unix = (milestone + 1) * 86400 + 1
					local rolled = Retention:Snapshot(f.Player)
					expect(rolled.completedCount).to.equal(0)
					for _, row in rolled.daily do
						expect(row.count).to.equal(0)
						expect(row.paid).to.equal(false)
					end
					gate.Released = true
					local confirmed = f:Confirmed(operation)
					local oldAmount = if milestone == 7 then 500000000 else 250000000
					expect(confirmed.result.amountCash).to.equal(oldAmount)
					expect(f:Data().Economy.Balance - before.Economy.Balance).to.equal(oldAmount)
					f:Rejoin()
					expect(Coordinator:GetOperation(f.Player, operation).state).to.equal("Confirmed")
					expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(milestone)
					if milestone == 7 then
						expect(f:Data().Commerce.Entitlements.P14_FLAG_CAMP).to.equal(true)
						expect(f:Data().Commerce.Appearance.Flag).to.equal(before.Commerce.Appearance.Flag)
						expect(CosmeticRules.Selected(f:Data(), "Flag")).to.equal("None")
					end
					local nextResult = f:Action({ action = "ClaimSupply" })
					f:Confirmed(nextResult.operationId)
					expect(nextResult.operationId).to.equal("retention:supply-date:" .. (milestone + 1))
					expect(f:Data().Economy.Balance - before.Economy.Balance).to.equal(oldAmount + 2500000000)
					expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(milestone + 1)
					expect(f:Data().Retention.Day.unitCash).to.equal(2500000000)
				end)
			end)
		end
		it("rejects request-day rollover before mutation and then accepts the new date once", function()
			fixture(function(f)
				f:Seed(1)
				local before = Fixtures.Clone(f:Data())
				f.ClockPlan = { 172799, 172800 }
				expect(f:Action({ action = "ClaimSupply" }).code).to.equal("DAY_CHANGED")
				Fixtures.AssertDeepEqual(f:Data(), before)
				expect(Profile:HasCriticalOperation(f.Player)).to.equal(false)
				expect(f:Data().Phase13.Operations["retention:supply-date:1"]).to.equal(nil)
				local accepted = f:Action({ action = "ClaimSupply" })
				f:Confirmed(accepted.operationId)
				expect(accepted.operationId).to.equal("retention:supply-date:2")
				expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(1)
				expect(f:Data().Economy.Balance - before.Economy.Balance).to.equal(250000000)
			end)
		end)
		it("uses accepted fresh swap time for firstbank and outgoing Payday across midnight replay", function()
			fixture(function(f)
				f.Clock.Unix = 86390
				f:Seed(1)
				f.Clock.Unix = 86399
				f:Mutate(function(data)
					data.Base.Slots["1"].brainrotId = "domain:seed:1"
					data.Base.Slots["1"].accumulatedCash = 10.25
				end)
				local cash = f:Data().Economy.Balance
				local r = {
					action = "Swap",
					slotIndex = 1,
					outgoingId = "domain:seed:1",
					incomingFresh = true,
					ownerUserId = f.Player.UserId,
					operationId = "domain:midnight:freshswap",
					previewRevision = f:Data().Phase13.EligibilityRevision,
					incomingRecord = {
						ItemId = "domain:fresh:swap",
						BrainrotId = "BRT_002",
						Metadata = { MutationId = "Golden", AcquisitionKind = "Hunt" },
					},
				}
				expect(Coordinator:CommitPlatformSwap(f.Player, r).ok).to.equal(true)
				f:Confirmed(r.operationId)
				local data = f:Data()
				expect(data.Collection.BrainrotInstances["domain:fresh:swap"].firstBankedAt).to.equal(86399)
				expect(data.Retention.Day.dayKey).to.equal(0)
				expect(data.Retention.Day.bring_them_home.count).to.equal(2)
				expect(data.Retention.Day.field_research.count).to.equal(2)
				expect(data.Retention.Day.camp_payday.paid).to.equal(true)
				expect(data.Economy.Balance - cash).to.equal(750000010.25)
				expect(data.Collection.SpeciesMutations.BRT_002.Golden).to.equal(86399)
				expect(data.Collection.SpeciesMutations.BRT_002.Normal).to.equal(nil)
				expect(Coordinator:GetOperation(f.Player, r.operationId).result.firstBankReceipt.firstBankedAt).to.equal(
					86399
				)
				f.Clock.Unix = 86401
				local before = Fixtures.Clone(data)
				expect(Coordinator:CommitPlatformSwap(f.Player, r).state).to.equal("Confirmed")
				Fixtures.AssertDeepEqual(f:Data(), before)
				expect(Banked:HasPendingBank(f.Player)).to.equal(false)
			end)
		end)
	end)
	local function incomeFixture(autoCollect, callback)
		fixture(function(f)
			f:Seed(1)
			f:Mutate(function(data)
				data.Base.Slots["1"].brainrotId = "domain:seed:1"
				data.Base.Slots["1"].accumulatedCash = 10.25
				if autoCollect then
					data.Commerce.Entitlements.AUTO_COLLECT = true
				end
			end)
			local base = Instance.new("Model")
			table.insert(f.Owned, base)
			base:SetAttribute("BaseId", "P14DomainBase")
			base:SetAttribute("OwnerUserId", f.Player.UserId)
			base:SetAttribute("BaseOwnershipRevision", 1)
			local slots = {}
			for i = 1, 12 do
				local pad = Instance.new("Part")
				pad.Name = string.format("Slot_%02d", i)
				pad.Parent = base
				local marker = Instance.new("Attachment")
				marker.Name = "BrainrotPlacement"
				marker.Parent = pad
				slots[i] = { Index = i, Platform = pad, Marker = marker }
			end
			local token = assert(
				Presentation.Begin(
					base,
					12,
					{ OwnerUserId = f.Player.UserId, AssignmentRevision = 1, ProfileReady = true }
				)
			)
			for i, slot in slots do
				Presentation.BindSlot(slot.Platform, base, i, token)
			end
			Presentation.Publish(base, token, 12)
			local storage = Storage.new(base, f.Player.UserId, slots, f:Data())
			assert(
				storage:BindRestoredRecord(
					1,
					{ ItemId = "domain:seed:1", BrainrotId = "BRT_001", Metadata = {} },
					Instance.new("Model")
				)
			)
			local observer
			local store = {}
			function store:GetStorageForPlayer(p)
				return if p == f.Player then storage else nil
			end
			function store:ObserveStorage(value)
				observer = value
				return function()
					observer = nil
				end
			end
			local bases = {}
			function bases:GetBase(p)
				return if p == f.Player then base else nil
			end
			function bases:IsOwner(p, b)
				return p == f.Player and b == base
			end
			function bases:GetAssignment(p)
				return if p == f.Player then { Generation = 1, Base = base, Player = p } else nil
			end
			function bases:SubscribeSessionClosing()
				return { Disconnect = function() end }
			end
			local scheduler = { Connections = 0 }
			function scheduler:Connect()
				self.Connections += 1
				return {
					Disconnect = function()
						self.Connections -= 1
					end,
				}
			end
			assert(Income:Init({
				Now = function()
					return f.Clock.Unix
				end,
				Storage = store,
				Base = bases,
				Wallet = Currency,
				Profile = Profile,
				Heartbeat = scheduler,
				Analytics = false,
				ResolvePlatformRate = function()
					return 0
				end,
			}))
			assert(Income:Start())
			observer.OnBound(f.Player, storage)
			local ok, why = xpcall(function()
				callback(f, storage, base)
			end, debug.traceback)
			Income:Stop()
			storage:Destroy()
			expect(scheduler.Connections).to.equal(0)
			assert(ok, why)
		end, { UserId = -2 })
	end
	-- This adapter binds the actual just-banked profile record, accrues at the real
	-- configured producer rate, then settles through the real Income/Currency owners.
	-- No direct wallet credit or artificial earnings amount is used by the cycle.
	local function settleProducedIncome(f)
		local data = f:Data()
		local itemId = assert(data.Base.Slots["1"].brainrotId, "cycle producer slot")
		local owned = assert(data.Collection.BrainrotInstances[itemId], "cycle durable producer")
		local base = Instance.new("Model")
		table.insert(f.Owned, base)
		base:SetAttribute("BaseId", "P14CycleBase")
		base:SetAttribute("OwnerUserId", f.Player.UserId)
		base:SetAttribute("BaseOwnershipRevision", 1)
		local slots = {}
		for index = 1, 12 do
			local pad = Instance.new("Part")
			pad.Name, pad.Parent = string.format("Slot_%02d", index), base
			local marker = Instance.new("Attachment")
			marker.Name, marker.Parent = "BrainrotPlacement", pad
			slots[index] = { Index = index, Platform = pad, Marker = marker }
		end
		local token = assert(
			Presentation.Begin(base, 12, {
				OwnerUserId = f.Player.UserId,
				AssignmentRevision = 1,
				ProfileReady = true,
			}),
			"cycle presentation token"
		)
		for index, slot in slots do
			Presentation.BindSlot(slot.Platform, base, index, token)
		end
		Presentation.Publish(base, token, 12)
		local storage = Storage.new(base, f.Player.UserId, slots, data)
		assert(
			storage:BindRestoredRecord(1, {
				ItemId = itemId,
				BrainrotId = owned.speciesId,
				Metadata = { MutationId = owned.mutationId or "None" },
			}, Instance.new("Model")),
			"cycle restored producer"
		)
		local observer
		local store = {}
		function store:GetStorageForPlayer(subject)
			return if subject == f.Player then storage else nil
		end
		function store:ObserveStorage(value)
			observer = value
			return function()
				observer = nil
			end
		end
		local bases = {}
		function bases:GetBase(subject)
			return if subject == f.Player then base else nil
		end
		function bases:IsOwner(subject, candidate)
			return subject == f.Player and candidate == base
		end
		function bases:GetAssignment(subject)
			return if subject == f.Player then { Generation = 1, Base = base, Player = subject } else nil
		end
		local scheduler = { Connections = 0 }
		function scheduler:Connect()
			self.Connections += 1
			return {
				Disconnect = function()
					self.Connections -= 1
				end,
			}
		end
		assert(
			Income:Init({
				Now = function()
					return f.Clock.Unix
				end,
				Storage = store,
				Base = bases,
				Wallet = Currency,
				Profile = Profile,
				Heartbeat = scheduler,
				Analytics = false,
				-- No ResolvePlatformRate override: exercise the actual installed catalogue.
			}),
			"cycle income initialization"
		)
		local earnings
		local ran, failure = xpcall(function()
			assert(Income:Start(), "cycle income start")
			observer.OnBound(f.Player, storage)
			local rate = Income:GetIncomeRate(f.Player)
			assert(rate > 0, "banked cycle producer must have a positive configured rate")
			f.Clock.Unix += 1
			assert(Income:Step(), "cycle production accrual")
			earnings = storage:GetUnclaimedCashExact(1)
			assert(earnings > 0, "cycle ordinary E must be produced")
			expect(earnings).to.equal(rate)
			local before = f:Data().Economy.Balance
			local settlement = Income:TryClaimPlatform(f.Player, "P14CycleBase", 1)
			assert(settlement.ok, "cycle actual own-platform settlement")
			expect(settlement.paid).to.equal(earnings)
			expect(f:Data().Economy.Balance - before).to.equal(earnings + 250000000)
			expect(storage:GetUnclaimedCashExact(1)).to.equal(0)
			expect(f:Data().Retention.Day.camp_payday.paid).to.equal(true)
		end, debug.traceback)
		Income:Stop()
		storage:Destroy()
		base:Destroy()
		expect(scheduler.Connections).to.equal(0)
		assert(ran, failure)
		assert(Profile:SaveNowAsync(f.Player, "CyclePaydayCoveringSave").ok, "cycle Payday covering save")
		expect(Retention:Publish(f.Player).status).to.equal("Ready")
		return earnings
	end
	describe("Phase14 actual-handler multi-date cycles with synthetic backend reacquisition", function()
		it(
			"runs14 AAB bank/produced-earnings/claim dates for25Bretention, separates E and reacquires6→7/13→14",
			function()
				fixture(function(f)
					f:Seed(1) -- onboard on date1; the14 measured eligible dates are2–15
					f:Mutate(function(data)
						data.Base.Slots["1"].brainrotId = "domain:seed:1"
						data.Base.Slots["1"].accumulatedCash = 0
					end)
					assert(Profile:SaveNowAsync(f.Player, "FullCycleBaseline").ok, "cycle baseline save")
					local baseline = f:Data().Economy.Balance
					local appearance = Fixtures.Clone(f:Data().Commerce.Appearance)
					local ordinaryE, expectedRetention = 0, 0
					local supplyUnits = { 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2 }
					for claim = 1, 14 do
						local day = claim + 1
						f.Clock.Unix = day * 86400 + 10
						for index, species in { "BRT_001", "BRT_001", "BRT_002" } do
							local before = f:Data().Economy.Balance
							local request = {
								action = "Swap",
								slotIndex = 1,
								outgoingId = f:Data().Base.Slots["1"].brainrotId,
								incomingFresh = true,
								ownerUserId = f.Player.UserId,
								operationId = "domain:cycle:bank:" .. claim .. ":" .. index,
								previewRevision = f:Data().Phase13.EligibilityRevision,
								incomingRecord = {
									ItemId = "domain:cycle:fresh:" .. claim .. ":" .. index,
									BrainrotId = species,
									Metadata = { MutationId = "None", AcquisitionKind = "Hunt" },
								},
							}
							local result = Coordinator:CommitPlatformSwap(f.Player, request)
							assert(result.ok, "actual cycle first-bank coordinator")
							local confirmed = f:Confirmed(request.operationId)
							expect(confirmed.result.firstBankReceipt.individualId).to.equal(
								request.incomingRecord.ItemId
							)
							expect(confirmed.result.firstBankReceipt.firstBankedAt).to.equal(f.Clock.Unix)
							expect(f:Data().Retention.Day.bring_them_home.count).to.equal(index)
							expect(f:Data().Retention.Day.field_research.count).to.equal(if index == 3 then 2 else 1)
							expect(f:Data().Economy.Balance - before).to.equal(if index == 3 then 1250000000 else 0)
						end
						expect(Banked:HasPendingBank(f.Player)).to.equal(false)
						ordinaryE += settleProducedIncome(f)
						local supply = f:Action({ action = "ClaimSupply" })
						assert(supply.ok, "actual cycle supply handler")
						local saved = f:Confirmed(supply.operationId)
						expect(saved.result.amountCash).to.equal(250000000 * supplyUnits[claim])
						expect(supply.operationId).to.equal("retention:supply-date:" .. day)
						expectedRetention += 1500000000 + 250000000 * supplyUnits[claim]
						local data = f:Data()
						expect(data.Economy.Balance - baseline - ordinaryE).to.equal(expectedRetention)
						expect(data.Retention.Supplies.lifetimeClaims).to.equal(claim)
						expect(data.Retention.Day.dayKey).to.equal(day)
						for _, id in { "bring_them_home", "field_research", "camp_payday" } do
							expect(data.Retention.Day[id].paid).to.equal(true)
							expect(data.Retention.Day[id].grantId).to.equal("retention:" .. day .. ":" .. id)
						end
						expect(data.Retention.Supplies.lastGrantId).to.equal("retention:supply:" .. claim)
						expect(data.Commerce.Entitlements.P14_FLAG_CAMP == true).to.equal(claim >= 7)
						expect(data.Commerce.Entitlements.P14_BASE_EXPEDITION == true).to.equal(claim >= 14)
						Fixtures.AssertDeepEqual(data.Commerce.Appearance, appearance)
						-- Each date ends the Income session; reacquire a new Player before its next date.
						-- Preserve the real finalised-player guard instead of restarting a closed identity.
						do
							local wallet, ids = data.Economy.Balance, Fixtures.Clone(data.Collection.BrainrotInstances)
							f:Rejoin()
							expect(f:Data().Economy.Balance).to.equal(wallet)
							expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(claim)
							Fixtures.AssertDeepEqual(f:Data().Collection.BrainrotInstances, ids)
							Fixtures.AssertDeepEqual(f:Data().Commerce.Appearance, appearance)
							local revision = Profile:GetCurrentRevision(f.Player)
							expect(f:Action({ action = "ClaimSupply" }).state).to.equal("Confirmed")
							expect(Profile:GetCurrentRevision(f.Player)).to.equal(revision)
							expect(f:Data().Economy.Balance).to.equal(wallet)
						end
					end
					expect(expectedRetention).to.equal(25000000000)
					expect(f:Data().Economy.Balance - baseline - ordinaryE).to.equal(25000000000)
					expect(ordinaryE > 0).to.equal(true)
					expect(f:Data().Commerce.Entitlements.P14_FLAG_CAMP).to.equal(true)
					expect(f:Data().Commerce.Entitlements.P14_BASE_EXPEDITION).to.equal(true)
					expect(CosmeticRules.Selected(f:Data(), "Flag")).to.equal("None")
					expect(CosmeticRules.Selected(f:Data(), "BaseBanner")).to.equal("None")
					expect(f:Data().Commerce.StarterPackClaimed).to.equal(false)
				end)
			end
		)
		it("runs28 supply-only handler claims with gaps,4B at14 and no repeat cosmetics at21/28", function()
			fixture(function(f)
				f:Seed(1) -- bank history only; no quest is completed on the measured dates
				local baseline = f:Data().Economy.Balance
				local appearance = Fixtures.Clone(f:Data().Commerce.Appearance)
				local expected, previousDay = 0, 1
				local firstFlag, firstBanner
				for claim = 1, 28 do
					-- Gaps affect the calendar date, never the lifetime7-position schedule.
					local day = claim + 1 + (if claim >= 5 then 3 else 0) + (if claim >= 12 then 4 else 0)
					if day > previousDay + 1 then
						local before = Fixtures.Clone(f:Data())
						for skipped = previousDay + 1, day - 1 do
							f.Clock.Unix = skipped * 86400 + 60
							Retention:Snapshot(f.Player)
							expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(claim - 1)
							expect(f:Data().Economy.Balance).to.equal(before.Economy.Balance)
							Fixtures.AssertDeepEqual(f:Data().Retention.Day, before.Retention.Day)
						end
					end
					-- Alternating late/early times prove UTC dates rather than24h cooldown.
					f.Clock.Unix = day * 86400 + (if claim % 2 == 0 then 5 else 86390)
					local result = f:Action({ action = "ClaimSupply" })
					assert(result.ok, "actual supply-only handler")
					local saved = f:Confirmed(result.operationId)
					local amount = if claim % 7 == 0 then 500000000 else 250000000
					expect(saved.result.amountCash).to.equal(amount)
					expected += amount
					local data = f:Data()
					expect(data.Economy.Balance - baseline).to.equal(expected)
					expect(data.Retention.Supplies.lifetimeClaims).to.equal(claim)
					for _, id in { "bring_them_home", "field_research", "camp_payday" } do
						expect(data.Retention.Day[id].count).to.equal(0)
						expect(data.Retention.Day[id].paid).to.equal(false)
					end
					if claim == 7 then
						firstFlag = data.Commerce.Entitlements.P14_FLAG_CAMP
					end
					if claim == 14 then
						firstBanner = data.Commerce.Entitlements.P14_BASE_EXPEDITION
						expect(data.Economy.Balance - baseline).to.equal(4000000000)
					end
					if claim == 21 or claim == 28 then
						expect(data.Commerce.Entitlements.P14_FLAG_CAMP).to.equal(firstFlag)
						expect(data.Commerce.Entitlements.P14_BASE_EXPEDITION).to.equal(firstBanner)
						local count = 0
						for id, owned in data.Commerce.Entitlements do
							if owned == true and id:match("^P14_") then
								count += 1
							end
						end
						expect(count).to.equal(2)
					end
					Fixtures.AssertDeepEqual(data.Commerce.Appearance, appearance)
					if claim == 6 or claim == 7 or claim == 13 or claim == 14 or claim == 21 or claim == 28 then
						local wallet = data.Economy.Balance
						f:Rejoin()
						expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(claim)
						expect(f:Data().Economy.Balance).to.equal(wallet)
						expect(f:Action({ action = "ClaimSupply" }).state).to.equal("Confirmed")
						expect(f:Data().Economy.Balance).to.equal(wallet)
					end
					previousDay = day
				end
				expect(expected).to.equal(8000000000)
				expect(f:Data().Economy.Balance - baseline).to.equal(8000000000)
				expect(firstFlag).to.equal(true)
				expect(firstBanner).to.equal(true)
				expect(CosmeticRules.Selected(f:Data(), "Flag")).to.equal("None")
				expect(CosmeticRules.Selected(f:Data(), "BaseBanner")).to.equal("None")
				expect(f:Data().Commerce.StarterPackClaimed).to.equal(false)
			end)
		end)
	end)
	describe("Phase14 actual Income source into Currency", function()
		for _, autoCollect in { false, true } do
			it(
				(if autoCollect then "AutoCollect Step" else "manual TryClaimPlatform")
					.. " settles E plus one U for a trusted negative Studio identity",
				function()
					incomeFixture(autoCollect, function(f, storage, base)
						local cash = f:Data().Economy.Balance
						if autoCollect then
							assert(Income:Step())
						else
							assert(
								Income:TryClaimPlatform(f.Player, base:GetAttribute("BaseId"), 1).ok,
								"manual E settlement"
							)
						end
						expect(f:Data().Economy.Balance - cash).to.equal(250000010.25)
						expect(storage:GetUnclaimedCashExact(1)).to.equal(0)
						expect(f:Data().Retention.Day.camp_payday.paid).to.equal(true)
						if autoCollect then
							assert(Income:Step())
						else
							expect(Income:TryClaimPlatform(f.Player, base:GetAttribute("BaseId"), 1).code).to.equal(
								"NothingToCollect"
							)
						end
						expect(f:Data().Economy.Balance - cash).to.equal(250000010.25)
						expect(Schema.ValidateLoaded(f:Data())).to.equal(true)
					end)
				end
			)
		end
	end)
	do
		-- These are explicit synthetic-backend integration cases, not normal DEV
		-- profile, real-input, world-reservation or physical transport proof.
		describe("Revision3 quest covering-save and nonqualifying-source acceptance", function()
			for _, mode in { "BeforeCommit", "LostAck" } do
				it("keeps a two-quest bank " .. mode .. " behind confirmation and reconciles original day once", function()
					fixture(function(f)
						f:Seed(1)
						f:Mutate(function(data)
							data.Base.Slots["1"].brainrotId = "domain:seed:1"
						end)
						local function request(id, species)
							return {
								action = "Swap",
								slotIndex = 1,
								outgoingId = f:Data().Base.Slots["1"].brainrotId,
								incomingFresh = true,
								ownerUserId = f.Player.UserId,
								operationId = "rev3:quest-fault:" .. mode .. ":" .. id,
								previewRevision = f:Data().Phase13.EligibilityRevision,
								incomingRecord = {
									ItemId = "rev3:" .. mode .. ":" .. id,
									BrainrotId = species,
									Metadata = { MutationId = "None", AcquisitionKind = "Hunt" },
								},
							}
						end
						local second = request("A2", "BRT_001")
						assert(Coordinator:CommitPlatformSwap(f.Player, second).ok, "actual coordinator second A")
						f:Confirmed(second.operationId)
						f:Mutate(function(data)
							data.WorldProgression.PersonalUnlocks.Beach = { source = "purchase" }
						end)
						assert(Profile:SaveNowAsync(f.Player, "Rev3PreQuestFault").ok, "pre-fault covering save")
						local before = Fixtures.Clone(f:Data())
						local baseline = Retention:Publish(f.Player)
						expect(baseline.daily.bring_them_home.count).to.equal(2)
						expect(baseline.daily.field_research.count).to.equal(1)
						f.Clock.Unix = 172799
						local third = request("B3", "BRT_002")
						local gate = f:Hold(third.operationId, mode)
						local response = Coordinator:CommitPlatformSwap(f.Player, third)
						assert(response.ok and response.state == "Saving", "actual held critical operation")
						awaitCondition(function()
							return gate.Entered
						end, "quest save fault entered")
						expect(gate.Response.ok).to.equal(false)
						expect(Profile:IsWritable(f.Player)).to.equal(false)
						local pending = Retention:Snapshot(f.Player)
						expect(pending.status).to.equal("Saving")
						expect(pending.daily.bring_them_home.count).to.equal(2)
						expect(pending.daily.bring_them_home.paid).to.equal(false)
						expect(pending.daily.field_research.paid).to.equal(false)
						local stored = gate.BackendData
						expect(stored.Collection.BrainrotInstances[third.incomingRecord.ItemId] ~= nil).to.equal(
							mode == "LostAck"
						)
						expect(stored.Retention.Day.bring_them_home.paid).to.equal(mode == "LostAck")
						f.Clock.Unix = 172801
						local rolled = Retention:Snapshot(f.Player)
						expect(rolled.dayKey).to.equal(2)
						expect(rolled.completedCount).to.equal(0)
						gate.Released = true
						f:Confirmed(third.operationId)
						local current = f:Data()
						expect(current.Economy.Balance - before.Economy.Balance).to.equal(1250000000)
						expect(current.Retention.Day.dayKey).to.equal(1)
						expect(current.Retention.Day.unitCash).to.equal(250000000)
						expect(current.Retention.Day.bring_them_home.grantId).to.equal("retention:1:bring_them_home")
						expect(current.Retention.Day.field_research.grantId).to.equal("retention:1:field_research")
						expect(current.Collection.BrainrotInstances[third.incomingRecord.ItemId].firstBankedAt).to.equal(
							172799
						)
						f:Rejoin()
						local reacquired = Fixtures.Clone(f:Data())
						expect(Coordinator:CommitPlatformSwap(f.Player, third).state).to.equal("Confirmed")
						Fixtures.AssertDeepEqual(f:Data(), reacquired)
						local confirmed = Retention:Snapshot(f.Player)
						expect(confirmed.status).to.equal("Ready")
						expect(confirmed.completedCount).to.equal(0)
						expect(confirmed.unitCash).to.equal(2500000000)
						expect(confirmed.estimated).to.equal(true)
						expect(f:Data().Commerce.StarterPackClaimed).to.equal(false)
					end)
				end)
			end
			for _, autoCollect in { false, true } do
				it(
					(if autoCollect then "AutoCollect" else "manual")
						.. " excludes ordinary wallet reasons and pays one fixed Payday",
					function()
						incomeFixture(autoCollect, function(f, storage, base)
							local before = Fixtures.Clone(f:Data())
							local reasons = {
								"BrainrotSale",
								"Refund",
								"StarterPack",
								"RetentionReward",
								"SupplyClaim",
								"Admin",
								"PlatformIncomeClaim",
							}
							for _, reason in reasons do
								assert(Currency:TryCredit(f.Player, 1.25, reason).ok, "fixture ordinary credit")
								expect(f:Data().Retention.Day.camp_payday.count).to.equal(0)
								expect(f:Data().Retention.Day.camp_payday.paid).to.equal(false)
							end
							Fixtures.AssertDeepEqual(f:Data().Retention, before.Retention)
							if autoCollect then
								assert(Income:Step(), "actual AutoCollect scheduler")
							else
								assert(
									Income:TryClaimPlatform(f.Player, base:GetAttribute("BaseId"), 1).ok,
									"manual positive own settlement"
								)
							end
							expect(f:Data().Economy.Balance - before.Economy.Balance).to.equal(
								250000010.25 + #reasons * 1.25
							)
							expect(f:Data().Retention.Day.camp_payday.paidCash).to.equal(250000000)
							expect(storage:GetUnclaimedCashExact(1)).to.equal(0)
							local paid = Fixtures.Clone(f:Data().Retention)
							assert(
								Currency:TryCredit(f.Player, 200.5, "RetentionReward").ok,
								"unrelated later reward credit"
							)
							if autoCollect then
								assert(Income:Step())
							else
								expect(Income:TryClaimPlatform(f.Player, base:GetAttribute("BaseId"), 1).code).to.equal(
									"NothingToCollect"
								)
							end
							Fixtures.AssertDeepEqual(f:Data().Retention, paid)
							expect(f:Data().Commerce.StarterPackClaimed).to.equal(false)
							expect(Schema.ValidateLoaded(f:Data())).to.equal(true)
						end)
					end
				)
			end
		end)
	end
	do
		local CommerceRules = require(RS.Shared.Utility.Phase13CommerceRules)
		local Phase13Rules = require(RS.Shared.Utility.Phase13Rules)
		describe("Revision3 fixture progression, multiplier and return integration", function()
			it(
				"keeps VIP double-production and Golden income separate from fixed retention and once-only Starter",
				function()
					fixture(function(f)
						f:Seed(1)
						f:Mutate(function(data)
							data.Base.Slots["1"].brainrotId = "domain:seed:1"
						end)
						local baseline = f:Data().Economy.Balance
						for _, key in { "VIP", "INCOME_2X", "STARTER_PACK" } do
							local id = "rev3:represented-pass:" .. key
							assert(
								Coordinator:CommitCritical(f.Player, id, "IsolatedEligibilityFixture", function(data, at)
									return CommerceRules.GrantPass(data, key, at)
								end).ok,
								"represented fixture eligibility"
							)
							f:Confirmed(id)
						end
						expect(f:Data().Economy.Balance - baseline).to.equal(3000000000)
						expect(f:Data().Retention.Day.camp_payday.count).to.equal(0)
						expect(f:Data().Commerce.StarterPackClaimed).to.equal(true)
						local ordinaryE = settleProducedIncome(f)
						local baseRate = require(RS.Shared.Config.BrainrotCatalog).GetCashPerSecond("BRT_001")
						local mutation = require(RS.Shared.Utility.Phase12Rules).MutationMultiplier("Golden")
						-- P15 economy: VIP adds its permanent income bonus; the 2x pass doubles it.
					local income = require(RS.Shared.Config.Economy).Income
					expect(ordinaryE).to.equal(baseRate * mutation * (1 + income.VipBonus) * income.Income2xPass)
						local supply = f:Action({ action = "ClaimSupply" })
						f:Confirmed(supply.operationId)
						expect(f:Data().Retention.Day.camp_payday.paidCash).to.equal(250000000)
						expect(f:Data().Retention.Supplies.lastAmountCash).to.equal(250000000)
						expect(f:Data().Economy.Balance - baseline).to.equal(3000000000 + ordinaryE + 500000000)
						local beforeReplay = f:Data().Economy.Balance
						assert(
							Coordinator:CommitCritical(
								f.Player,
								"rev3:starter-reconcile",
								"IsolatedEligibilityFixture",
								function(data, at)
									return CommerceRules.GrantPass(data, "STARTER_PACK", at)
								end
							).ok,
							"existing Starter reconciliation"
						)
						f:Confirmed("rev3:starter-reconcile")
						expect(f:Data().Economy.Balance).to.equal(beforeReplay)
						f:Rejoin()
						expect(f:Data().Economy.Balance).to.equal(beforeReplay)
						expect(f:Data().Commerce.StarterPackClaimed).to.equal(true)
					end, { Mutation = "Golden" })
				end
			)
			it(
				"crosses exact milestone thresholds through covering first-bank writes and equips each owned expression",
				function()
					fixture(function(f)
						f:Seed(4)
						local cash = f:Data().Economy.Balance
						local thresholds = {
							[5] = { "P14_TITLE_COLLECTOR", "Title" },
							[10] = { "P14_NAMEPLATE_FIELD_RESEARCH", "Nameplate" },
							[20] = { "P14_TITLE_EXPEDITION_EXPERT", "Title" },
							[30] = { "P14_PLAQUE_MASTER_COLLECTOR", "Plaque" },
						}
						for count = 5, 30 do
							local previous = thresholds[count + 1]
							if previous then
								expect(f:Data().Retention.Milestones[previous[1]]).to.equal(nil)
							end
							local operation = "rev3:discovery:" .. count
							assert(
								Coordinator:CommitCritical(
									f.Player,
									operation,
									"IsolatedAcceptedBankFixture",
									function(data, at)
										local receipt = recordBank(data, operation, string.format("BRT_%03d", count), at)
										return receipt ~= nil, { firstBankReceipt = receipt }
									end
								).ok,
								"covering discovery write"
							)
							f:Confirmed(operation)
							expect(Rules.DiscoveryCount(f:Data())).to.equal(count)
							for threshold, definition in thresholds do
								expect(f:Data().Retention.Milestones[definition[1]] ~= nil).to.equal(count >= threshold)
							end
							local milestone = thresholds[count]
							if milestone then
								expect(f:Data().Retention.Milestones[milestone[1]].earned).to.equal(true)
								local result =
									f:Action({ action = "EquipMilestone", slot = milestone[2], value = milestone[1] })
								f:Confirmed(result.operationId)
							end
							expect(f:Data().Economy.Balance).to.equal(cash)
						end
						expect(f:Data().Retention.Milestones.P14_BADGE_ANOMALY_FOUND).to.equal(nil)
						assert(
							Coordinator:CommitCritical(
								f.Player,
								"rev3:actual-variant-proof",
								"IsolatedAcceptedBankFixture",
								function(data, at)
									local receipt = recordBank(data, "rev3:variant:golden", "BRT_001", at, "Golden")
									return receipt ~= nil, { firstBankReceipt = receipt }
								end
							).ok,
							"actual variant fixture write"
						)
						f:Confirmed("rev3:actual-variant-proof")
						local equip =
							f:Action({ action = "EquipMilestone", slot = "Badge", value = "P14_BADGE_ANOMALY_FOUND" })
						f:Confirmed(equip.operationId)
						local owned = Fixtures.Clone(f:Data().Retention.Milestones)
						local beforeSale = Fixtures.Clone(f:Data().Retention)
						local saleRecord = {
							ItemId = "rev3:variant:golden",
							BrainrotId = "BRT_001",
							Metadata = { MutationId = "Golden", DurableOwnerUserId = f.Player.UserId },
						}
						local saleValues = require(RS.Shared.Utility.Phase12Rules).EffectiveValues("BRT_001", "Golden")
						assert(saleValues and saleValues.sellValue > 0, "actual configured Golden sale quote")
						local sale = Banked:TryCommitSale(f.Player, saleRecord, saleValues.sellValue, true)
						assert(sale.ok, "actual owned-individual sale: " .. tostring(sale.code))
						expect(f:Data().Collection.BrainrotInstances[saleRecord.ItemId]).to.equal(nil)
						Fixtures.AssertDeepEqual(f:Data().Retention, beforeSale)
						expect(#Rules.ReconcileMilestones(f:Data())).to.equal(0)
						expect(f:Data().Economy.Balance).to.equal(cash + saleValues.sellValue)
						assert(Profile:SaveNowAsync(f.Player, "Rev3MilestoneSale").ok, "covering milestone-sale save")
						f:Rejoin()
						Fixtures.AssertDeepEqual(f:Data().Retention.Milestones, owned)
						expect(#Rules.ReconcileMilestones(f:Data())).to.equal(0)
						expect(f:Data().Economy.Balance).to.equal(cash + saleValues.sellValue)
						expect(Rules.DiscoveryCount(f:Data())).to.equal(30)
						expect(f:Data().Retention.SelectedTitle).to.equal("P14_TITLE_EXPEDITION_EXPERT")
						expect(f:Data().Retention.SelectedNameplate).to.equal("P14_NAMEPLATE_FIELD_RESEARCH")
						expect(f:Data().Retention.SelectedPlaque).to.equal("P14_PLAQUE_MASTER_COLLECTOR")
						expect(f:Data().Retention.SelectedBadge).to.equal("P14_BADGE_ANOMALY_FOUND")
						expect(f:Data().Phase13.SpeedLevel).to.equal(0)
						expect(f:Data().Phase13.ExpansionLevel).to.equal(0)
					end)
				end
			)
			it("refreshes one pinned goal through actual earn spend purchase and both rebirth quote semantics", function()
				fixture(function(f)
					f:Seed(1)
					local target, cart = "Cart:CRT_006", Phase13Rules.Cart("CRT_006")
					local pin = f:Action({ action = "PinGoal", goalId = target })
					f:Confirmed(pin.operationId)
					local initial = Retention:Snapshot(f.Player).goal
					expect(initial.price).to.equal(cart.price)
					expect(initial.shortfall).to.equal(cart.price - f:Data().Economy.Balance)
					assert(
						Currency:TryCredit(f.Player, cart.price, "IsolatedGoalEarningsFixture").ok,
						"fixture earned credit"
					)
					expect(Retention:Snapshot(f.Player).goal.shortfall).to.equal(0)
					expect(f:Data().Phase13.OwnedCartIds.CRT_006).to.equal(nil)
					assert(Currency:TrySpend(f.Player, cart.price / 2, "IsolatedGoalSpendFixture").ok, "fixture spend")
					expect(Retention:Snapshot(f.Player).goal.shortfall).to.equal(cart.price / 2 - 0.375)
					assert(
						Currency:TryCredit(f.Player, cart.price / 2, "IsolatedGoalEarningsFixture").ok,
						"fixture remaining earnings"
					)
					local request = {
						category = "Cart",
						id = "CRT_006",
						operationId = "rev3:goal:cart",
						sequence = f:Data().Phase13.OperationSequence + 1,
						previewRevision = f:Data().Phase13.EligibilityRevision,
					}
					local purchase = Coordinator:Purchase(f.Player, request)
					assert(purchase.ok, "actual existing catalogue purchase: " .. tostring(purchase.code))
					f:Confirmed(request.operationId)
					expect(Retention:Snapshot(f.Player).goal.completed).to.equal(true)
					expect(f:Data().Progression.TrackedUpgradeId).to.equal(target)
					expect(f:Data().Phase13.SelectedCartId).to.equal("CRT_001")
					f:Mutate(function(data)
						data.Base.Slots["1"].brainrotId = "domain:seed:1"
						data.Base.Slots["1"].accumulatedCash = 10.25
					end)
					local cashGoal = f:Action({ action = "PinGoal", goalId = "Rebirth:EXP_018:Cash" })
					f:Confirmed(cashGoal.operationId)
					local shown = Retention:Snapshot(f.Player).goal
					expect(shown.balance).to.equal(10.625)
					expect(shown.cashSacrificeAll).to.equal(true)
					expect(shown.warning:find("ALL CASH", 1, true) ~= nil).to.equal(true)
					local collection = f:Action({ action = "PinGoal", goalId = "Rebirth:EXP_018:Collection" })
					f:Confirmed(collection.operationId)
					shown = Retention:Snapshot(f.Player).goal
					-- BRT_001 is Common and does not meet this route's configured rarity.
					expect(shown.balance).to.equal(0)
					expect(shown.prerequisites.ownedCount).to.equal(1)
					f:Mutate(function(data)
						local receipt = recordBank(data, "rev3:goal:quality", "BRT_019", f.Clock.Unix)
						assert(receipt, "accepted qualifying fixture bank")
						data.Base.Slots["2"].brainrotId = "rev3:goal:quality"
					end)
					assert(Profile:SaveNowAsync(f.Player, "Rev3QualifyingGoalInventory").ok, "covering qualifying inventory save")
					shown = Retention:Snapshot(f.Player).goal
					expect(shown.balance).to.equal(1)
					expect(shown.prerequisites.ownedCount).to.equal(2)
					expect(shown.warning:find("ALL owned brainrots", 1, true) ~= nil).to.equal(true)
					expect(f:Data().Phase13.ExpansionLevel).to.equal(0)
					expect(f:Data().Base.Slots["1"].accumulatedCash).to.equal(10.25)
					f:Rejoin()
					expect(f:Data().Progression.TrackedUpgradeId).to.equal("Rebirth:EXP_018:Collection")
					expect(f:Data().Phase13.ExpansionLevel).to.equal(0)
				end)
			end)
			for _, hours in { 167.999, 168 } do
				it("publishes at most three truthful return rows after " .. hours .. " hours without a payout", function()
					fixture(function(f)
						f:Seed(1)
						f:Mutate(function(data)
							data.Retention.LastSeenAt = f.Clock.Unix
						end)
						assert(Profile:SaveNowAsync(f.Player, "Rev3BeforeAbsence").ok, "absence baseline")
						local cash, count = f:Data().Economy.Balance, f:Data().Retention.Supplies.lifetimeClaims
						f.Clock.Unix += hours * 3600
						f:Rejoin(true)
						local first, refreshers = Retention:Snapshot(f.Player), 0
						for _, row in first.returnRows do
							if row.kind == "Refresher" then
								refreshers += 1
								expect(row.text:find("Shoot to sleep", 1, true) ~= nil).to.equal(true)
							end
						end
						expect(refreshers).to.equal(if hours >= 168 then 1 else 0)
						expect(#first.returnRows <= 3).to.equal(true)
						Fixtures.AssertDeepEqual(Retention:Snapshot(f.Player).returnRows, first.returnRows)
						expect(f:Data().Economy.Balance).to.equal(cash)
						expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(count)
					end)
				end)
			end
		end)
	end
	do
		local RebirthRules = require(RS.Shared.Utility.Phase13Rules)
		describe("Revision3 actual coordinator reward and rebirth ordering", function()
			local function request(quote, id)
				return {
					operationId = id,
					sequence = quote.nextSequence,
					previewRevision = quote.previewRevision,
					inventorySignature = quote.inventorySignature,
					rewardId = quote.rewardId,
					route = quote.route,
				}
			end
			it(
				"refreshes a stale cash quote after a quest and preserves only rewards serialized after all-Cash sacrifice",
				function()
					fixture(function(f)
						f:Seed(2)
						local offer = RebirthRules.FindReward("EXP_018")
						assert(
							Currency:TryCredit(f.Player, offer.price, "IsolatedRebirthThresholdFixture").ok,
							"represented ordinary fixture funds"
						)
						f:Mutate(function(data)
							data.Base.Slots["1"].brainrotId = "domain:seed:1"
							data.Base.Slots["1"].accumulatedCash = 10.25
						end)
						local stale = RebirthRules.QuoteRebirth(f:Data(), "EXP_018", "Cash")
						expect(stale.ok).to.equal(true)
						local beforeReward = f:Data().Economy.Balance
						local bankId = "rev3:cash:third-bank"
						assert(
							Coordinator:CommitCritical(f.Player, bankId, "IsolatedAcceptedBankFixture", function(data, at)
								local receipt = recordBank(data, bankId, "BRT_001", at)
								return receipt ~= nil, { firstBankReceipt = receipt }
							end).ok,
							"accepted third-bank fixture through actual coordinator"
						)
						f:Confirmed(bankId)
						expect(f:Data().Economy.Balance - beforeReward).to.equal(750000000)
						local beforeReject = Fixtures.Clone(f:Data())
						local rejected = Coordinator:Rebirth(f.Player, request(stale, "rev3:cash:stale"))
						expect(rejected.code).to.equal("STALE_PREVIEW")
						Fixtures.AssertDeepEqual(f:Data(), beforeReject)
						local quote = RebirthRules.QuoteRebirth(f:Data(), "EXP_018", "Cash")
						expect(quote.totalCash).to.equal(offer.price + 1250000000 + 10.625)
						local permanent = Fixtures.Clone(f:Data().Retention)
						local owned = Fixtures.Clone(f:Data().Collection.BrainrotInstances)
						local operation = request(quote, "rev3:cash:confirmed")
						assert(Coordinator:Rebirth(f.Player, operation).ok, "actual coordinator Cash rebirth")
						local receipt = f:Confirmed(operation.operationId)
						expect(receipt.result.sacrificedCash).to.equal(quote.totalCash)
						expect(RebirthRules.Cash(f:Data())).to.equal(0)
						Fixtures.AssertDeepEqual(f:Data().Retention, permanent)
						Fixtures.AssertDeepEqual(f:Data().Collection.BrainrotInstances, owned)
						f:Rejoin()
						expect(RebirthRules.Cash(f:Data())).to.equal(0)
						local supply = f:Action({ action = "ClaimSupply" })
						f:Confirmed(supply.operationId)
						expect(f:Data().Economy.Balance).to.equal(250000000)
						local afterSupply = Fixtures.Clone(f:Data().Retention)
						assert(Coordinator:Rebirth(f.Player, operation).ok, "old committed rebirth replay")
						expect(f:Data().Economy.Balance).to.equal(250000000)
						Fixtures.AssertDeepEqual(f:Data().Retention, afterSupply)
						f:Rejoin()
						expect(f:Data().Economy.Balance).to.equal(250000000)
						Fixtures.AssertDeepEqual(f:Data().Retention, afterSupply)
						expect(f:Data().Phase13.ExpansionLevel).to.equal(1)
						expect(f:Data().Phase13.RebirthCount).to.equal(1)
					end)
				end
			)
			it(
				"Collection rebirth settles Cash and consumes every owned ID while permanent paid state survives reacquisition",
				function()
					fixture(function(f)
						f:Seed(12)
						f:Mutate(function(data)
							for i = 1, 12 do
								data.Base.Slots[tostring(i)].brainrotId = "domain:seed:" .. i
							end
							for i = 1, 4 do
								local id = "rev3:collection:quality:" .. i
								assert(recordBank(data, id, "BRT_019", f.Clock.Unix), "accepted quality bank fixture")
								data.Base.Slots[tostring(i)].brainrotId = id
							end
							data.Base.Slots["1"].accumulatedCash = 10.25
						end)
						assert(
							Profile:SaveNowAsync(f.Player, "Rev3CollectionRebirthBaseline").ok,
							"covering inventory fixture save"
						)
						local quote = RebirthRules.QuoteRebirth(f:Data(), "BDS_002", "Collection")
						assert(quote.ok, "actual configured Collection eligibility: " .. tostring(quote.code))
						expect(quote.ownedCount).to.equal(16)
						local permanent = Fixtures.Clone(f:Data().Retention)
						local discoveries = Fixtures.Clone(f:Data().Collection.Species)
						local variants = Fixtures.Clone(f:Data().Collection.SpeciesMutations)
						local operation = request(quote, "rev3:collection:confirmed")
						assert(Coordinator:Rebirth(f.Player, operation).ok, "actual coordinator Collection rebirth")
						local receipt = f:Confirmed(operation.operationId)
						expect(receipt.result.sacrificedIndividuals).to.equal(16)
						expect(f:Data().Economy.Balance).to.equal(quote.totalCash)
						expect(next(f:Data().Collection.BrainrotInstances)).to.equal(nil)
						for _, slot in f:Data().Base.Slots do
							expect(slot.brainrotId).to.equal(nil)
							expect(slot.accumulatedCash).to.equal(0)
						end
						Fixtures.AssertDeepEqual(f:Data().Retention, permanent)
						Fixtures.AssertDeepEqual(f:Data().Collection.Species, discoveries)
						Fixtures.AssertDeepEqual(f:Data().Collection.SpeciesMutations, variants)
						f:Rejoin()
						expect(f:Data().Economy.Balance).to.equal(quote.totalCash)
						expect(next(f:Data().Collection.BrainrotInstances)).to.equal(nil)
						Fixtures.AssertDeepEqual(f:Data().Retention, permanent)
						Fixtures.AssertDeepEqual(f:Data().Collection.Species, discoveries)
						expect(f:Data().Phase13.OwnedBaseDesigns.BDS_002).to.equal(true)
						expect(f:Data().Phase13.RebirthCount).to.equal(1)
					end)
				end
			)
		end)
	end
	do
		describe("Revision3 concurrent claim and delayed acquisition boundaries", function()
			it(
				"coalesces rapid supply delivery behind one critical write and rejects same-user and stale-session mutation",
				function()
					fixture(function(f)
						f:Seed(1)
						local initial = f:Data().Economy.Balance
						local gate = f:Hold("retention:supply-date:1", "Normal")
						assert(f:Action({ action = "ClaimSupply" }).ok, "accepted first request")
						awaitCondition(function()
							return gate.Entered
						end, "held supply save")
						for _ = 1, 10 do
							local duplicate = Retention:Handle(f.Player, { action = "ClaimSupply" })
							expect(duplicate.ok).to.equal(false)
							expect(duplicate.code == "RATE_LIMITED" or duplicate.code == "PROFILE_NOT_WRITABLE").to.equal(true)
						end
						task.wait(0.26) -- Past the last actual delivery, including a slow save-gate arrival.
						expect(f:Action({ action = "ClaimSupply" }).code).to.equal("PROFILE_NOT_WRITABLE")
						local other = {
							UserId = f.Player.UserId,
							Name = "SyntheticConcurrentSameUser",
							Parent = Players,
							Attributes = {},
						}
						function other:SetAttribute(k, v)
							self.Attributes[k] = v
						end
						function other:GetAttribute(k)
							return self.Attributes[k]
						end
						function other:Kick(message)
							self.Kicked = message
						end
						local rejected = Profile:LoadPlayerAsync(other)
						expect(rejected.ok).to.equal(false)
						expect(Profile:GetReadableData(other)).to.equal(nil)
						expect(Retention:Handle(other, { action = "ClaimSupply" }).ok).to.equal(false)
						other.Parent = nil
						gate.Released = true
						f:Confirmed("retention:supply-date:1")
						expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(1)
						expect(f:Data().Economy.Balance - initial).to.equal(250000000)
						local revision, old = Profile:GetCurrentRevision(f.Player), f.Player
						assert(f:Action({ action = "ClaimSupply" }).ok, "confirmed operation replay")
						expect(Profile:GetCurrentRevision(f.Player)).to.equal(revision)
						f:Rejoin()
						expect(Retention:Handle(old, { action = "ClaimSupply" }).ok).to.equal(false)
						expect(f:Data().Economy.Balance - initial).to.equal(250000000)
						expect(f:Data().Retention.Supplies.lifetimeClaims).to.equal(1)
					end)
				end
			)
			it(
				"exposes unavailable while actual acquisition is delayed and binds one unchanged confirmed profile afterward",
				function()
					fixture(function(f)
						f:Seed(1)
						f:Mutate(function(data)
							data.Retention.LastSeenAt = f.Clock.Unix
						end)
						assert(Profile:SaveNowAsync(f.Player, "Rev3DelayedAcquisitionBaseline").ok, "covering visit baseline")
						local initial = Fixtures.Clone(f:Data())
						local gate = { Released = false, Entered = false, Exited = false }
						table.insert(f.Gates, gate)
						f.Backend.BeforeAcquireReturn = function()
							gate.Entered, gate.Thread = true, coroutine.running()
							awaitCondition(function()
								return gate.Released
							end, "delayed acquire released", 4)
							gate.Exited = true
						end
						local finished, rejoinError = false, nil
						task.spawn(function()
							local ok, failure = pcall(function()
								f:Rejoin(true)
							end)
							finished, rejoinError = true, not ok and failure or nil
						end)
						awaitCondition(function()
							return gate.Entered
						end, "delayed supported acquisition entered")
						expect(Profile:IsWritable(f.Player)).to.equal(false)
						expect(Profile:GetReadableData(f.Player)).to.equal(nil)
						local delayed = Retention:Snapshot(f.Player)
						expect(delayed.available).to.equal(false)
						expect(delayed.collection).to.equal(nil)
						expect(delayed.supplies).to.equal(nil)
						expect(Retention:Handle(f.Player, { action = "ClaimSupply" }).ok).to.equal(false)
						gate.Released = true
						awaitCondition(function()
							return finished
						end, "acquisition finished")
						assert(not rejoinError, tostring(rejoinError))
						f.Backend.BeforeAcquireReturn = nil
						expect(Retention:Snapshot(f.Player).status).to.equal("Ready")
						expect(f:Data().Economy.Balance).to.equal(initial.Economy.Balance)
						Fixtures.AssertDeepEqual(f:Data().Retention, initial.Retention)
						Fixtures.AssertDeepEqual(
							f:Data().Collection.BrainrotInstances,
							initial.Collection.BrainrotInstances
						)
					end)
				end
			)
		end)
	end
	describe("Revision3 actual world custody and retention composition", function()
		local Native = require(script.Parent.Support.Phase12NativeFixture)
		local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
		local Carry = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
		local Cargo = require(script.Parent.Parent.Services.CartCargoService)
		local function nativeDomain(callback)
			Native(function(n)
				local actors = 0
				fixture(function(f)
					callback(f, n)
				end, {
					ActorFactory = function()
						actors += 1
						if actors == 1 then
							return n.p
						end
						local actor = table.clone(n.p)
						local attributes = {}
						function actor:GetAttribute(key) return attributes[key] end
						function actor:SetAttribute(key, value) attributes[key] = value end
						function actor:Kick(message) self.Kicked = message end
						actor.Parent = Players
						return actor
					end,
				})
			end)
		end
		local function swapRequest(f, record, operation, fresh, slot)
			local index = slot or 1
			return {
				action = "Swap", slotIndex = index,
				outgoingId = f:Data().Base.Slots["1"].brainrotId,
				incomingFresh = fresh, ownerUserId = f.Player.UserId,
				operationId = operation, previewRevision = f:Data().Phase13.EligibilityRevision,
				incomingRecord = record,
			}
		end
		local function retireCommittedSource(player, record, operation)
			return Carry.ReconcilePendingBankSource(player, record, operation)
				and Cargo:ReconcilePendingBankSource(player, record, operation)
		end
		it("nonbank custody and failed deposit give no credit; a stolen fresh ID credits only its first banker", function()
			nativeDomain(function(f, n)
				f:Seed(1)
				f:Mutate(function(data) data.Base.Slots["1"].brainrotId = "domain:seed:1" end)
				assert(Profile:SaveNowAsync(f.Player, "T04BankerBaseline").ok, "banker baseline save")
				local first = table.clone(n.p)
				first.Name, first.UserId = "EarlierCarrierFixture", n.p.UserId - 100000
				first.Character = n.p.Character:Clone()
				first.Character.Name, first.Character.Parent = "EarlierCarrierCharacter", n.root
				first.Character:PivotTo(CFrame.new(n.origin + Vector3.new(8, 0, 5)))
				local attributes = {}
				function first:GetAttribute(key) return attributes[key] end
				function first:SetAttribute(key, value) attributes[key] = value end
				assert(Profile:LoadPlayerAsync(first).ok, "second isolated actual profile")
				table.insert(f.Restores, function()
					if Profile:GetSessionHandle(first) then
						assert(Profile:ClosePlayerAsync(first, "T04ActorCleanup").ok, "earlier actor cleanup")
					end
					first.Parent = nil
				end)
				local earlier = Fixtures.Clone(Profile:GetReadableData(first))
				local before = Fixtures.Clone(f:Data().Retention)
				local model, record = n.spawn(false, "BRT_001", { MutationId = "None" })
				assert(Carry.TryPickupWorld(first, model, record.ItemId), "earlier actor real pickup")
				Fixtures.AssertDeepEqual(Profile:GetReadableData(first).Retention, earlier.Retention)
				Fixtures.AssertDeepEqual(f:Data().Retention, before)
				expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
				local failed = Coordinator:CommitPlatformSwap(f.Player, swapRequest(f, record, "t04:locked", true, 48))
				expect(failed.ok).to.equal(false)
				expect(failed.code).to.equal("LOCKED_SLOT")
				Fixtures.AssertDeepEqual(f:Data().Retention, before)
				expect(f:Data().Collection.BrainrotInstances[record.ItemId]).to.equal(nil)
				local dropped, dropReason = Carry.TryDropCarried(first, record.ItemId)
				assert(dropped, "earlier actor real drop: " .. tostring(dropReason))
				local loose = assert(World.GetWorldModelById(record.ItemId), "same dropped individual")
				local _, looseState = World.GetWorldRecord(loose)
				if looseState ~= "WorldSleeping" then
					assert(World.TrySleep(loose), "current sleep boundary for released individual")
				end
				assert(Carry.TryPickupWorld(f.Player, loose, record.ItemId), "different actor real fresh pickup")
				expect(World.GetPhase12State(record).AcquisitionKind).to.equal("Theft")
				Fixtures.AssertDeepEqual(Profile:GetReadableData(first).Retention, earlier.Retention)
				Fixtures.AssertDeepEqual(f:Data().Retention, before)
				local request = swapRequest(f, record, "t04:stolen:first-bank", true)
				local response = Coordinator:CommitPlatformSwap(f.Player, request, {
					onCommitted = function() return retireCommittedSource(f.Player, record, "Bank:" .. record.ItemId) end,
				})
				assert(response.ok, "actual stolen first bank: " .. tostring(response.code))
				local confirmed = f:Confirmed(request.operationId)
				expect(confirmed.result.firstBankReceipt.acquisitionKind).to.equal("Theft")
				expect(f:Data().Retention.Day.bring_them_home.count).to.equal(2)
				expect(f:Data().Retention.Day.field_research.count).to.equal(1)
				expect(f:Data().Economy.Balance).to.equal(0.375)
				expect(Profile:GetReadableData(first).Collection.BrainrotInstances[record.ItemId]).to.equal(nil)
				Fixtures.AssertDeepEqual(Profile:GetReadableData(first).Retention, earlier.Retention)
				local paidState = Fixtures.Clone(f:Data().Retention)
				local old = { ItemId = "domain:seed:1", BrainrotId = "BRT_001", Metadata = { MutationId = "None" } }
				local out = swapRequest(f, old, "t04:owned:out", false)
				assert(Coordinator:CommitPlatformSwap(f.Player, out).ok, "existing owned move out")
				f:Confirmed(out.operationId)
				local back = swapRequest(f, record, "t04:owned:back", false)
				assert(Coordinator:CommitPlatformSwap(f.Player, back).ok, "existing owned rebank")
				f:Confirmed(back.operationId)
				Fixtures.AssertDeepEqual(f:Data().Retention, paidState)
				local lost = n.carry("BRT_001", { MutationId = "None" })
				Carry.HandleCharacterRemoving(f.Player, f.Player.Character)
				Fixtures.AssertDeepEqual(f:Data().Retention, paidState)
				expect(f:Data().Collection.BrainrotInstances[lost.ItemId]).to.equal(nil)
			end)
		end)
		it("real held and cargo reservations persist through covering save and release once alongside retention across replay", function()
			for _, cargoSource in { false, true } do
				nativeDomain(function(f, n)
					f.Clock.Unix = 86380
					f:Seed(1)
					f:Mutate(function(data)
						assert(recordBank(data, "t05:second-a", "BRT_001", f.Clock.Unix), "second accepted baseline bank")
						data.Base.Slots["1"].brainrotId = "domain:seed:1"
					end)
					assert(Profile:SaveNowAsync(f.Player, "T05Baseline").ok, "baseline save")
					Retention:Publish(f.Player)
					local ordinaryBefore = World.GetPopulationSnapshot().Effective
					local record = n.carry("BRT_002", { MutationId = "None" })
					if cargoSource then
						n.near("Slot1")
						assert(Carry.TryPlaceInCargo(f.Player, n.cart, "Slot1", record.ItemId), "real cargo source")
					end
					local transit = World.GetPopulationSnapshot()
					expect(transit.Target).to.equal(42)
					expect(transit.Effective).to.equal(ordinaryBefore + 1)
					expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
					local releaseCount = 0
					local listener = World.PopulationChanged:Connect(function(kind, event)
						if kind == "WildMembershipRemoved" and event.RuntimeId == record.ItemId and event.Reason == "FirstBank" then releaseCount += 1 end
					end)
					table.insert(f.Restores, function() listener:Disconnect() end)
					f.Clock.Unix = 86399
					local request = swapRequest(f, record, "t05:bank:" .. tostring(cargoSource), true)
					local gate = f:Hold(request.operationId, "Normal")
					local response = Coordinator:CommitPlatformSwap(f.Player, request, {
						onCommitted = function() return retireCommittedSource(f.Player, record, "Bank:" .. record.ItemId) end,
					})
					assert(response.ok and response.state == "Saving", "real covering operation pending")
					awaitCondition(function() return gate.Entered end, "covering bank save entered")
					expect(World.IsPendingBank(record.ItemId)).to.equal(true)
					expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
					expect(World.GetPopulationSnapshot().Effective).to.equal(ordinaryBefore + 1)
					expect(releaseCount).to.equal(0)
					local saving = Retention:Snapshot(f.Player)
					expect(saving.status).to.equal("Saving")
					expect(saving.daily.bring_them_home.count).to.equal(2)
					expect(saving.daily.bring_them_home.paid).to.equal(false)
					expect(Coordinator:CommitPlatformSwap(f.Player, request).state).to.equal("Saving")
					gate.Released = true
					local confirmed = f:Confirmed(request.operationId)
					awaitCondition(function() return releaseCount == 1 end, "one actual first-bank reservation release")
					expect(confirmed.result.firstBankReceipt.firstBankedAt).to.equal(86399)
					expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(false)
					expect(World.GetPopulationSnapshot().Effective).to.equal(ordinaryBefore)
					expect(f:Data().Retention.Day.bring_them_home.count).to.equal(3)
					expect(f:Data().Retention.Day.field_research.count).to.equal(2)
					expect(f:Data().Economy.Balance).to.equal(1250000000.375)
					local beforeReplay = Fixtures.Clone(f:Data())
					expect(Coordinator:CommitPlatformSwap(f.Player, request).state).to.equal("Confirmed")
					Fixtures.AssertDeepEqual(f:Data(), beforeReplay)
					f.Clock.Unix = 86401
					f:Rejoin()
					local afterJoin = Fixtures.Clone(f:Data())
					expect(Coordinator:CommitPlatformSwap(f.Player, request).state).to.equal("Confirmed")
					Fixtures.AssertDeepEqual(f:Data(), afterJoin)
					expect(f:Data().Collection.BrainrotInstances[record.ItemId].firstBankedAt).to.equal(86399)
					expect(f:Data().Economy.Balance).to.equal(1250000000.375)
					expect(releaseCount).to.equal(1)
					expect(World.GetPopulationSnapshot().Effective).to.equal(ordinaryBefore)
				end)
			end
		end)
	end)

	describe("Phase14 saved presentation ordering", function()
		it("accepts covering Ready once and rejects older revisions or delayed same-revision Saving", function()
			local ready = {
				revision = 4,
				retentionRevision = 3,
				snapshotSequence = 12,
				serverTime = 86401,
				status = "Ready",
				dayKey = 1,
			}
			expect(View.AcceptSnapshot(ready, { revision = 3, retentionRevision = 4, snapshotSequence = 13 })).to.equal(
				false
			)
			expect(View.AcceptSnapshot(ready, { revision = 4, retentionRevision = 2, snapshotSequence = 13 })).to.equal(
				false
			)
			expect(
				View.AcceptSnapshot(
					ready,
					{ revision = 4, retentionRevision = 3, snapshotSequence = 11, status = "Saving", dayKey = 0 }
				)
			).to.equal(false)
			expect(
				View.AcceptSnapshot(
					ready,
					{ revision = 4, retentionRevision = 3, snapshotSequence = 13, status = "Ready", dayKey = 1 }
				)
			).to.equal(true)
		end)
		it("retains prior confirmed same-day paid rows but never carries them into tomorrow", function()
			local row = { id = "bring_them_home", count = 3, target = 3, paid = true, state = "Completed" }
			local prior = { available = true, status = "Ready", dayKey = 1, daily = { bring_them_home = row } }
			local pending = { available = true, status = "Saving", dayKey = 1 }
			expect(
				View.Row(
					pending,
					{ id = "bring_them_home", count = 3, target = 3, paid = false, state = "Saving" },
					prior
				).paid
			).to.equal(true)
			pending.dayKey = 2
			expect(
				View.Row(
					pending,
					{ id = "bring_them_home", count = 0, target = 3, paid = false, state = "Saving" },
					prior
				).paid
			).to.equal(false)
		end)
	end)
end
