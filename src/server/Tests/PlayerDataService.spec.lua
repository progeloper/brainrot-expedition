--!nocheck

return function()
	local Players = game:GetService("Players")
	local Service = require(script.Parent.Parent.Services.PlayerDataService)
	local BankedBrainrotService = require(script.Parent.Parent.Services.BankedBrainrotService)
	local UpgradeService = require(script.Parent.Parent.Services.UpgradeService)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
	local BaseStorage = require(script.Parent.Parent.Classes.BaseStorage)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)
	local Eligibility =
		require(game:GetService("ReplicatedStorage").Shared.Utility.UpgradeEligibility)

	local nextUserId = 7000
	local function newPlayer(userId)
		nextUserId += 1
		local player = {
			Name = "ProfileFixture",
			UserId = userId or nextUserId,
			Parent = Players,
			Attributes = {},
			Kicked = nil,
		}
		function player:SetAttribute(name, value)
			self.Attributes[name] = value
		end
		function player:Kick(message)
			self.Kicked = message
		end
		return player
	end

	local function harness(options)
		local now = 1000
		local operation = 0
		local trackedInstances = {}
		local cleanupCallbacks = {}
		local backend = options and options.Backend
			or FakeBackend.new({
				Now = function()
					return now
				end,
			})
		Service:_ResetForTests()
		Service:Init({
			Backend = backend,
			UnixNow = function()
				return now
			end,
			MonotonicNow = function()
				return now
			end,
			Wait = function(seconds)
				now += seconds
				if options and options.YieldWait then
					task.wait()
				end
			end,
			Random = function()
				return 0
			end,
			GenerateOperationId = function(prefix)
				operation += 1
				return prefix .. ":" .. tostring(operation)
			end,
			KickOnFailure = false,
		})
		Currency:_ResetForTests(Service)
		return {
			Backend = backend,
			Now = function()
				return now
			end,
			Advance = function(seconds)
				now += seconds
			end,
			Track = function(instance)
				table.insert(trackedInstances, instance)
				return instance
			end,
			OnCleanup = function(callback)
				table.insert(cleanupCallbacks, callback)
			end,
			Cleanup = function()
				for index = #cleanupCallbacks, 1, -1 do
					cleanupCallbacks[index]()
				end
				UpgradeService:Stop()
				BankedBrainrotService:_ResetForTests()
				Service:_ResetForTests()
				Currency:_ResetForTests()
				for _, instance in trackedInstances do
					instance:Destroy()
				end
			end,
		}
	end

	local function run(callback, options)
		local fixture = harness(options)
		local ok, failure = xpcall(function()
			callback(fixture)
		end, debug.traceback)
		fixture.Cleanup()
		assert(ok, failure)
	end

	-- Real income settlement and storage bindings; only time and assignment are
	-- synthetic. No heartbeat is needed to demonstrate snapshot-time accrual.
	local function bindIncomeFixture(f, player)
		assert(
			Service:CommitMutation(player, function(data)
				data.Collection.BrainrotInstances["income-fixture"] = { speciesId = "BRT_007" }
				data.Base.Slots["1"].brainrotId = "income-fixture"
				return true, { ok = true }
			end).ok,
			"income fixture profile seed rejected"
		)
		local base = f.Track(Instance.new("Model"))
		base:SetAttribute("BaseId", "ProfileSaveIncomeFixture")
		local descriptors = {}
		for index = 1, 12 do
			local platform = Instance.new("Part")
			platform.Parent = base
			local marker = Instance.new("Attachment")
			marker.Parent = platform
			descriptors[index] = { Index = index, Platform = platform, Marker = marker }
		end
		local storage =
			BaseStorage.new(base, player.UserId, descriptors, Service:GetReadableData(player))
		assert(storage:BindRestoredRecord(1, {
			ItemId = "income-fixture",
			BrainrotId = "BRT_007",
			Metadata = {},
		}, nil))
		local storageApi = {}
		function storageApi:GetStorageForPlayer(subject)
			return if subject == player then storage else nil
		end
		function storageApi:ObserveStorage()
			return function() end
		end
		local baseApi = {}
		function baseApi:GetBase(subject)
			return if subject == player then base else nil
		end
		function baseApi:IsOwner(subject, candidate)
			return subject == player and candidate == base
		end
		f.OnCleanup(function()
			Income:Stop()
			storage:Destroy()
		end)
		assert(Income:Start({
			Storage = storageApi,
			Base = baseApi,
			Wallet = Currency,
			Profile = Service,
			Now = f.Now,
			ConnectScheduler = false,
			ResolvePlatformRate = function(speciesId)
				return if speciesId == "BRT_007" then 2 else nil
			end,
		}))
		assert(Income:BindPlatformStorage(player, storage))
		Service:RegisterSnapshotPreparer(function(subject, at)
			return Income:PrepareForSave(subject, at)
		end)
		return storage
	end

	local function saveEventCount(backend)
		local count = 0
		for _, event in backend.Events do
			if event.kind == "Save" then
				count += 1
			end
		end
		return count
	end

	local function awaitSaveDrain(player, backend)
		local deadline = os.clock() + 2
		repeat
			if saveEventCount(backend) > 0 and not Service:GetDiagnostics(player).saveInFlight then
				return
			end
			task.wait()
		until os.clock() >= deadline
		error("coordinated save did not finish within bounded test deadline")
	end

	describe("Phase 7A-1 profile lifecycle", function()
		it("rejects reentrant mutations without locking another player's session", function()
			run(function()
				local player, other = newPlayer(), newPlayer()
				assert(Service:LoadPlayerAsync(player).ok, "primary fixture load failed")
				assert(Service:LoadPlayerAsync(other).ok, "other fixture load failed")
				local nestedCalled = false
				local result = Service:CommitMutation(player, function(data)
					local nested = Service:CommitMutation(player, function()
						nestedCalled = true
						return true
					end)
					expect(nested.ok).to.equal(false)
					expect(nested.code).to.equal("MUTATION_IN_PROGRESS")
					local writable, writableReason = Service:GetWritableData(player)
					expect(writable).to.equal(nil)
					expect(writableReason).to.equal("MUTATION_IN_PROGRESS")
					local dirtyRevision, dirtyReason = Service:MarkDirty(player)
					expect(dirtyRevision).to.equal(nil)
					expect(dirtyReason).to.equal("MUTATION_IN_PROGRESS")
					expect(Currency:TryCredit(player, 50, "NestedCredit").code).to.equal(
						"MUTATION_IN_PROGRESS"
					)
					expect(Currency:TryCredit(other, 2.5, "IndependentSession").ok).to.equal(true)
					data.Economy.Balance = 1.25
					return true
				end)
				expect(result.ok).to.equal(true)
				expect(result.revision).to.equal(1)
				expect(nestedCalled).to.equal(false)
				expect(Currency:GetBalance(player)).to.equal(1.25)
				expect(Currency:GetBalance(other)).to.equal(2.5)
				expect(Currency:TryCredit(player, 0.25, "AfterCommit").ok).to.equal(true)
			end)
		end)

		it("releases the mutation guard after rejected throwing and invalid callbacks", function()
			for _, mode in { "Rejected", "Throwing", "Invalid" } do
				run(function()
					local player = newPlayer()
					assert(Service:LoadPlayerAsync(player).ok, "mutation fixture load failed")
					local result = Service:CommitMutation(player, function(data)
						expect(Currency:TryCredit(player, 50, "NestedRejected").code).to.equal(
							"MUTATION_IN_PROGRESS"
						)
						data.Economy.Balance = 7.5
						if mode == "Throwing" then
							error("synthetic callback failure")
						elseif mode == "Invalid" then
							data.Economy.Balance = -1
							return true
						end
						return false, { ok = false, code = "REJECTED" }
					end)
					expect(result.ok).to.equal(false)
					expect(Currency:GetBalance(player)).to.equal(0)
					expect(Service:GetDiagnostics(player).currentRevision).to.equal(0)
					expect(Currency:TryCredit(player, 1.25, "AfterRollback").ok).to.equal(true)
					expect(Service:GetDiagnostics(player).currentRevision).to.equal(1)
				end)
			end
		end)

		it("bounds incidental catch-up while income continues settling during each save", function()
			run(function(f)
				local player = newPlayer()
				assert(Service:LoadPlayerAsync(player).ok, "income fixture load failed")
				local storage = bindIncomeFixture(f, player)
				f.Advance(1)
				local acknowledgements = 0
				f.Backend.BeforeSaveReturn = function()
					acknowledgements += 1
					-- Bound the old implementation to five saves instead of hanging;
					-- settlement here models the ordinary income heartbeat during IO.
					if acknowledgements < 5 then
						f.Advance(1)
						Income:AccruePlatformsTo(f.Now())
					end
				end
				expect(Service:RequestSave(player, "ContinuousLiveIncome").ok).to.equal(true)
				awaitSaveDrain(player, f.Backend)
				expect(saveEventCount(f.Backend)).to.equal(2)
				expect(storage:GetUnclaimedCashExact(1)).to.equal(6)
				expect(
					f.Backend:GetRecord("player_" .. player.UserId).Data.Base.Slots["1"].accumulatedCash
				).to.equal(4)
				expect(Service:GetDiagnostics(player).dirty).to.equal(true)
			end)
		end)

		it("drains an explicit request after incidental catch-up is spent", function()
			run(function(f)
				local player = newPlayer()
				assert(Service:LoadPlayerAsync(player).ok, "income fixture load failed")
				local storage = bindIncomeFixture(f, player)
				f.Advance(1)
				local acknowledgements = 0
				f.Backend.BeforeSaveReturn = function()
					acknowledgements += 1
					if acknowledgements < 5 then
						f.Advance(1)
						Income:AccruePlatformsTo(f.Now())
					end
					if acknowledgements == 2 then
						expect(Currency:TryCredit(player, 0.25, "ExplicitNewerMutation").ok).to.equal(
							true
						)
						expect(Service:RequestSave(player, "ExplicitCoveringRevision").code).to.equal(
							"COALESCED"
						)
					end
				end
				expect(Service:RequestSave(player, "IncomeWithPriorityRequest").ok).to.equal(true)
				awaitSaveDrain(player, f.Backend)
				expect(saveEventCount(f.Backend)).to.equal(3)
				local durable = f.Backend:GetRecord("player_" .. player.UserId)
				expect(durable.Data.Economy.Balance).to.equal(0.25)
				expect(durable.Data.Base.Slots["1"].accumulatedCash).to.equal(6)
				expect(storage:GetUnclaimedCashExact(1)).to.equal(8)
				expect(Service:GetDiagnostics(player).dirty).to.equal(true)
				f.Backend.BeforeSaveReturn = nil
				expect(Service:SaveNowAsync(player, "NextCoveringSnapshot").ok).to.equal(true)
				expect(saveEventCount(f.Backend)).to.equal(4)
				expect(Service:GetDiagnostics(player).dirty).to.equal(false)
			end)
		end)

		it("does not resave income already included in the requested snapshot", function()
			run(function(f)
				local player = newPlayer()
				assert(Service:LoadPlayerAsync(player).ok, "income fixture load failed")
				local storage = bindIncomeFixture(f, player)
				f.Advance(1)
				local acknowledgements = 0
				f.Backend.BeforeSaveReturn = function()
					acknowledgements += 1
					-- Stop clock advancement after two acknowledgements so the old
					-- self-triggered drain is reproduced without an unbounded loop.
					if acknowledgements < 3 then
						f.Advance(1)
					end
				end
				expect(Service:RequestSave(player, "IncomeSnapshotOnly").ok).to.equal(true)
				awaitSaveDrain(player, f.Backend)
				expect(saveEventCount(f.Backend)).to.equal(1)
				expect(storage:GetUnclaimedCashExact(1)).to.equal(2)
				expect(
					f.Backend:GetRecord("player_" .. player.UserId).Data.Base.Slots["1"].accumulatedCash
				).to.equal(2)
				expect(Service:GetDiagnostics(player).dirty).to.equal(false)
			end)
		end)

		it(
			"drains a genuine post-snapshot mutation without resaving its included settlement",
			function()
				run(function(f)
					local player = newPlayer()
					assert(Service:LoadPlayerAsync(player).ok, "income fixture load failed")
					bindIncomeFixture(f, player)
					f.Advance(1)
					local changed = false
					f.Backend.BeforeSaveReturn = function()
						if not changed then
							changed = true
							assert(
								Currency:TryCredit(player, 5.25, "PostSnapshotFixture").ok,
								"post-snapshot mutation failed"
							)
							f.Advance(1)
						end
					end
					expect(Service:RequestSave(player, "IncomeWithNewerMutation").ok).to.equal(true)
					awaitSaveDrain(player, f.Backend)
					expect(saveEventCount(f.Backend)).to.equal(2)
					local durable = f.Backend:GetRecord("player_" .. player.UserId)
					expect(durable.Data.Economy.Balance).to.equal(5.25)
					expect(durable.Data.Base.Slots["1"].accumulatedCash).to.equal(4)
					expect(Service:GetDiagnostics(player).dirty).to.equal(false)
				end)
			end
		)

		it(
			"does not start another retry batch merely because failed snapshot settlement dirtied it",
			function()
				run(function(f)
					local player = newPlayer()
					assert(Service:LoadPlayerAsync(player).ok, "income fixture load failed")
					bindIncomeFixture(f, player)
					f.Advance(1)
					f.Backend.FailBeforeSaveCount = 5
					expect(Service:RequestSave(player, "IncomeSnapshotRejected").ok).to.equal(true)
					awaitSaveDrain(player, f.Backend)
					expect(saveEventCount(f.Backend)).to.equal(5)
					expect(f.Backend:GetRecord("player_" .. player.UserId).LastRevision).to.equal(0)
					expect(Service:GetDiagnostics(player).dirty).to.equal(true)
				end)
			end
		)

		it("round-trips a fractional authoritative wallet", function()
			run(function()
				local first = newPlayer(8101)
				local loaded = Service:LoadPlayerAsync(first)
				expect(loaded.ok).to.equal(true)
				expect(loaded.isNew).to.equal(true)
				expect(Currency:GetBalance(first)).to.equal(0)
				expect(Currency:TryCredit(first, 10.8, "Fixture").ok).to.equal(true)
				expect(Service:ClosePlayerAsync(first, "Test").ok).to.equal(true)

				first.Parent = nil
				local second = newPlayer(8101)
				expect(Service:LoadPlayerAsync(second).ok).to.equal(true)
				expect(math.abs(Currency:GetBalance(second) - 10.8) < 1e-9).to.equal(true)
			end)
		end)

		it("never turns a failed load into a writable default", function()
			local backend = FakeBackend.new({ AcquireFailure = "LOAD_FAILED" })
			run(function()
				local player = newPlayer()
				local loaded = Service:LoadPlayerAsync(player)
				expect(loaded.ok).to.equal(false)
				expect(Service:GetStatus(player)).to.equal("Failed")
				expect(Service:IsWritable(player)).to.equal(false)
				expect(Currency:TryCredit(player, 50, "Unsafe").ok).to.equal(false)
				expect(next(backend.Records)).to.equal(nil)
			end, { Backend = backend })
		end)

		it("recovers an acquisition whose committed response was lost", function()
			local backend = FakeBackend.new({ CommitThenFailAcquireCount = 1 })
			run(function()
				local player = newPlayer(8150)
				local loaded = Service:LoadPlayerAsync(player)
				expect(loaded.ok).to.equal(true)
				expect(Service:IsWritable(player)).to.equal(true)
				expect(Currency:GetBalance(player)).to.equal(0)
				expect(#backend.Events).to.equal(2)
				expect(backend.Events[1].token).to.equal(backend.Events[2].token)
			end, { Backend = backend })
		end)

		it("respects foreign leases and accepts an expired handoff", function()
			run(function(f)
				local key = "player_8201"
				f.Backend.Records[key] = {
					Data = Schema.CreateDefault(),
					OwnerToken = "foreign",
					LeaseExpiresAt = f.Now() + 20,
					LastRevision = 0,
				}
				local blocked = newPlayer(8201)
				expect(Service:LoadPlayerAsync(blocked).code).to.equal("SESSION_LOCKED")
				expect(Service:IsWritable(blocked)).to.equal(false)
				f.Advance(25)
				Service:_ResetForTests()

				local secondHarness = harness({ Backend = f.Backend })
				local accepted = newPlayer(8201)
				expect(Service:LoadPlayerAsync(accepted).ok).to.equal(true)
				expect(Service:IsWritable(accepted)).to.equal(true)
				secondHarness.Cleanup()
			end)
		end)

		it("keeps revision eleven dirty when revision ten finishes", function()
			run(function(f)
				local player = newPlayer()
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				for _ = 1, 10 do
					expect(Currency:TryCredit(player, 1, "BeforeSave").ok).to.equal(true)
				end
				local injected = false
				f.Backend.BeforeSaveReturn = function()
					if not injected then
						injected = true
						expect(Currency:TryCredit(player, 1, "DuringSave").ok).to.equal(true)
					end
				end
				expect(Service:SaveNowAsync(player, "Fixture").ok).to.equal(true)
				local diagnostics = Service:GetDiagnostics(player)
				expect(diagnostics.currentRevision).to.equal(11)
				expect(diagnostics.lastConfirmedSavedRevision).to.equal(10)
				expect(diagnostics.dirty).to.equal(true)
				expect(f.Backend:GetRecord("player_" .. player.UserId).LastRevision).to.equal(10)
			end)
		end)

		it("rolls back rejected, throwing and structurally invalid profile mutations", function()
			run(function()
				local player = newPlayer(8160)
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				local seeded = Service:CommitMutation(player, function(data)
					data.Economy.Balance = 1000.5
					data.Collection.BrainrotInstances.a = { speciesId = "BRT_007" }
					data.Base.Slots["1"].brainrotId = "a"
					data.Base.Slots["1"].accumulatedCash = 120.25
					return true, { ok = true }
				end)
				expect(seeded.ok).to.equal(true)
				local revision = Service:GetDiagnostics(player).currentRevision
				local boundBefore = assert(Service:GetReadableData(player))
				local ownedBefore = boundBefore.Collection.BrainrotInstances
				local slotsBefore = boundBefore.Base.Slots
				local slotOneBefore = slotsBefore["1"]

				local rejected = Service:CommitMutation(player, function(data)
					data.Economy.Balance = 0
					data.Collection.BrainrotInstances.a = nil
					data.Base.Slots["1"].brainrotId = nil
					return false, { ok = false, code = "INJECTED_REJECTION" }
				end)
				expect(rejected.ok).to.equal(false)
				expect(rejected.code).to.equal("INJECTED_REJECTION")

				local throwing = Service:CommitMutation(player, function(data)
					data.Economy.Balance = 2
					data.Base.Slots["1"].accumulatedCash = 0
					error("injected mutation failure")
				end)
				expect(throwing.ok).to.equal(false)
				expect(throwing.code).to.equal("MUTATION_ERROR")

				local invalid = Service:CommitMutation(player, function(data)
					data.Economy.Balance = -1
					return true, { ok = true }
				end)
				expect(invalid.ok).to.equal(false)
				expect(invalid.code).to.equal("INVALID_PROFILE_MUTATION")

				local live = assert(Service:GetReadableData(player))
				expect(live).to.equal(boundBefore)
				expect(live.Collection.BrainrotInstances).to.equal(ownedBefore)
				expect(live.Base.Slots).to.equal(slotsBefore)
				expect(live.Base.Slots["1"]).to.equal(slotOneBefore)
				expect(live.Economy.Balance).to.equal(1000.5)
				expect(live.Collection.BrainrotInstances.a.speciesId).to.equal("BRT_007")
				expect(live.Base.Slots["1"].brainrotId).to.equal("a")
				expect(live.Base.Slots["1"].accumulatedCash).to.equal(120.25)
				expect(Service:GetDiagnostics(player).currentRevision).to.equal(revision)
			end)
		end)

		it("drains a newer request coalesced behind a direct save", function()
			run(function(f)
				local player = newPlayer(8161)
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				expect(Currency:TryCredit(player, 10, "BeforeDirectSave").ok).to.equal(true)
				local entered, released = false, false
				f.Backend.BeforeSaveReturn = function()
					if entered then
						return
					end
					entered = true
					repeat
						task.wait()
					until released
				end
				local saveResult
				task.spawn(function()
					saveResult = Service:SaveNowAsync(player, "DirectWithOverlap")
				end)
				repeat
					task.wait()
				until entered
				expect(Currency:TryCredit(player, 5, "DuringDirectSave").ok).to.equal(true)
				expect(Service:RequestSave(player, "CoalescedNewerRevision").code).to.equal(
					"COALESCED"
				)
				released = true
				repeat
					task.wait()
				until saveResult ~= nil

				expect(saveResult.ok).to.equal(true)
				local stored = f.Backend:GetRecord("player_8161")
				expect(stored.LastRevision).to.equal(2)
				expect(stored.Data.Economy.Balance).to.equal(15)
				expect(Service:GetDiagnostics(player).dirty).to.equal(false)
			end)
		end)

		it(
			"round-trips the exact collection, sale and fixture-purchase trace coherently",
			function()
				run(function(f)
					local player = newPlayer(8162)
					expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
					local seeded = Service:CommitMutation(player, function(data)
						data.Economy.Balance = 1000.5
						data.Collection.BrainrotInstances.A = { speciesId = "BRT_007" }
						data.Collection.BrainrotInstances.B = { speciesId = "BRT_007" }
						data.Base.Slots["1"].brainrotId = "A"
						data.Base.Slots["1"].accumulatedCash = 120.25
						data.Base.Slots["2"].brainrotId = "B"
						data.Base.Slots["2"].accumulatedCash = 33.4
						data.Base.Slots["4"].accumulatedCash = 0
						data.Progression = { Upgrades = {} }
						return true, { ok = true }
					end)
					expect(seeded.ok).to.equal(true)

					local collected = Currency:TryCreditWithSource(
						player,
						120.25,
						"PlatformCollection",
						function(data)
							local slot = data.Base.Slots["1"]
							if slot.brainrotId ~= "A" or slot.accumulatedCash ~= 120.25 then
								return false, "SOURCE_CHANGED"
							end
							slot.accumulatedCash = 0
							return true
						end
					)
					expect(collected.ok).to.equal(true)
					expect(collected.balance).to.equal(1120.75)

					local removed = Service:CommitMutation(player, function(data)
						local slot = data.Base.Slots["1"]
						if slot.brainrotId ~= "A" then
							return false, { ok = false, code = "SOURCE_CHANGED" }
						end
						slot.brainrotId = nil
						return true, { ok = true }
					end)
					expect(removed.ok).to.equal(true)

					BankedBrainrotService:_ResetForTests({
						Profile = Service,
						Currency = Currency,
					})
					local sale = BankedBrainrotService:TryCommitSale(player, {
						ItemId = "A",
						BrainrotId = "BRT_007",
						Metadata = { DurableOwnerUserId = player.UserId },
					}, 120)
					expect(sale.ok).to.equal(true)
					expect(sale.balance).to.equal(1240.75)

					local fixtureOffer = {
						id = "FIXTURE_CARGO_1",
						displayName = "Fixture Cargo I",
						category = "Cargo",
						price = 750,
						currencyId = "Cash",
						grant = {
							kind = "UpgradeTrackLevel",
							trackId = "FIXTURE_CARGO",
							level = 1,
						},
						ownershipScope = { kind = "PlayerWide" },
						applicability = { kind = "AllOwnedCarts" },
						requirements = {},
						effect = {
							statId = "CargoCapacity",
							operation = "AddSlots",
							value = 1,
							unit = "Slots",
							summary = "+1 cargo slot",
						},
						displayOrder = 1,
						definitionStatus = "Complete",
						releaseStatus = "Released",
						effectStatus = "ReadyFixtureOnly",
						openDecisionCodes = {},
					}
					local catalogue = {}
					function catalogue.Get(id)
						return if id == fixtureOffer.id then fixtureOffer else nil
					end
					function catalogue.GetAll()
						return { fixtureOffer }
					end
					local stall = f.Track(Instance.new("Part"))
					stall.Name = "SPEC_7F_UPGRADE_STALL"
					stall.Anchored = true
					stall.Parent = workspace
					UpgradeService:Stop()
					UpgradeService:Init({
						Profile = Service,
						Currency = Currency,
						Catalogue = catalogue,
						Eligibility = Eligibility,
						Readiness = {
							effectReadyByOfferId = { FIXTURE_CARGO_1 = true },
							persistenceReadyByScope = { PlayerWide = true },
							cartAcquisitionByTier = {},
							rankProviderOperational = false,
						},
						WorldReady = function(subject)
							return subject == player
						end,
						WithinShopRange = function(subject, target)
							return subject == player and target == stall
						end,
						ResolveTarget = function()
							return nil, nil
						end,
						BuildPlayerSnapshot = function(subject, data)
							return {
								status = "Ready",
								userId = subject.UserId,
								balance = data.Economy.Balance,
								ownedOfferIds = data.Progression.Upgrades,
							}
						end,
						ApplyGrant = function(data, definition)
							if data.Progression.Upgrades[definition.id] then
								return false, "ALREADY_OWNED"
							end
							data.Progression.Upgrades[definition.id] = true
							return true, nil
						end,
						Now = f.Now,
						GenerateId = function()
							return "context-7f"
						end,
					})
					local opened = UpgradeService:OpenShop(player, stall)
					expect(opened.ok).to.equal(true)
					local payload = {
						contextId = opened.payload.contextId,
						requestId = "purchase-7f",
						offerId = fixtureOffer.id,
					}
					local purchased = UpgradeService:Purchase(player, payload)
					expect(purchased.outcome).to.equal("Accepted")
					expect(purchased.balance).to.equal(490.75)
					expect(UpgradeService:Purchase(player, payload).duplicate).to.equal(true)
					local freshDuplicate = UpgradeService:Purchase(player, {
						contextId = opened.payload.contextId,
						requestId = "purchase-7f-again",
						offerId = fixtureOffer.id,
					})
					expect(freshDuplicate.code).to.equal("ALREADY_OWNED")

					local live = assert(Service:GetReadableData(player))
					expect(live.Economy.Balance).to.equal(490.75)
					expect(live.Collection.BrainrotInstances.A).to.equal(nil)
					expect(live.Collection.BrainrotInstances.B.speciesId).to.equal("BRT_007")
					expect(live.Base.Slots["2"].brainrotId).to.equal("B")
					expect(live.Base.Slots["2"].accumulatedCash).to.equal(33.4)
					expect(live.Base.Slots["4"].brainrotId).to.equal(nil)
					expect(live.Base.Slots["4"].accumulatedCash).to.equal(0)
					expect(live.Progression.Upgrades.FIXTURE_CARGO_1).to.equal(true)

					task.wait()
					expect(Service:SaveNowAsync(player, "Phase7FFinalTrace").ok).to.equal(true)
					expect(Service:ClosePlayerAsync(player, "Phase7FTraceClose").ok).to.equal(true)
					player.Parent = nil
					UpgradeService:Stop()

					local restoredPlayer = newPlayer(8162)
					expect(Service:LoadPlayerAsync(restoredPlayer).ok).to.equal(true)
					local restored = assert(Service:GetReadableData(restoredPlayer))
					expect(restored.Economy.Balance).to.equal(490.75)
					expect(restored.Collection.BrainrotInstances.A).to.equal(nil)
					expect(restored.Collection.BrainrotInstances.B.speciesId).to.equal("BRT_007")
					expect(restored.Base.Slots["2"].brainrotId).to.equal("B")
					expect(restored.Base.Slots["2"].accumulatedCash).to.equal(33.4)
					expect(restored.Base.Slots["4"].brainrotId).to.equal(nil)
					expect(restored.Base.Slots["4"].accumulatedCash).to.equal(0)
					expect(restored.Progression.Upgrades.FIXTURE_CARGO_1).to.equal(true)
				end, { YieldWait = true })
			end
		)

		it("survives one hundred bounded save, close and fresh-load cycles", function()
			run(function(f)
				local userId = 8163
				for _ = 1, 100 do
					local player = newPlayer(userId)
					expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
					expect(Currency:TryCredit(player, 0.25, "LifecycleCycle").ok).to.equal(true)
					expect(Service:ClosePlayerAsync(player, "LifecycleCycle").ok).to.equal(true)
					expect(Service:GetDiagnostics(player)).to.equal(nil)
					player.Parent = nil
				end
				local durable = f.Backend:GetRecord("player_" .. tostring(userId))
				expect(durable.Data.Economy.Balance).to.equal(25)
				expect(durable.LastRevision).to.equal(100)
				expect(durable.OwnerToken).to.equal(nil)
			end)
		end)

		it("keeps a later payout and ownership removal together after an older save", function()
			run(function(f)
				local player = newPlayer()
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				local seeded = Service:CommitMutation(player, function(data)
					data.Economy.Balance = 100
					data.Collection.BrainrotInstances.a = { speciesId = "BRT_007" }
					return true, { ok = true }
				end)
				expect(seeded.ok).to.equal(true)
				local injected = false
				f.Backend.BeforeSaveReturn = function()
					if injected then
						return
					end
					injected = true
					local sale = Currency:TryCreditWithSource(
						player,
						120,
						"BankedSale",
						function(data)
							if data.Collection.BrainrotInstances.a == nil then
								return false, "SOURCE_CHANGED"
							end
							data.Collection.BrainrotInstances.a = nil
							return true
						end
					)
					expect(sale.ok).to.equal(true)
				end
				expect(Service:SaveNowAsync(player, "OlderSnapshot").ok).to.equal(true)

				local stored = f.Backend:GetRecord("player_" .. player.UserId)
				expect(stored.LastRevision).to.equal(1)
				expect(stored.Data.Economy.Balance).to.equal(100)
				expect(stored.Data.Collection.BrainrotInstances.a ~= nil).to.equal(true)
				local live = assert(Service:GetReadableData(player))
				expect(live.Economy.Balance).to.equal(220)
				expect(live.Collection.BrainrotInstances.a).to.equal(nil)
				expect(Service:GetDiagnostics(player).dirty).to.equal(true)
			end)
		end)

		it("retries one committed snapshot operation without repeating currency", function()
			local backend = FakeBackend.new({ CommitThenFailSaveCount = 1 })
			run(function()
				local player = newPlayer()
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				expect(Currency:TryCredit(player, 7.5, "Once").ok).to.equal(true)
				expect(Service:SaveNowAsync(player, "UncertainResponse").ok).to.equal(true)
				expect(Currency:GetBalance(player)).to.equal(7.5)
				local record = backend:GetRecord("player_" .. player.UserId)
				expect(record.Data.Economy.Balance).to.equal(7.5)
				expect(record.LastRevision).to.equal(1)
			end, { Backend = backend })
		end)

		it("keeps the latest wallet dirty when every save attempt fails before commit", function()
			local backend = FakeBackend.new({ FailBeforeSaveCount = 5 })
			run(function()
				local player = newPlayer()
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				expect(Currency:TryCredit(player, 6.25, "Unsaved").ok).to.equal(true)
				expect(Service:SaveNowAsync(player, "InjectedFailure").ok).to.equal(false)
				local diagnostics = Service:GetDiagnostics(player)
				expect(diagnostics.currentRevision).to.equal(1)
				expect(diagnostics.lastConfirmedSavedRevision).to.equal(0)
				expect(diagnostics.dirty).to.equal(true)
				expect(backend:GetRecord("player_" .. player.UserId).Data.Economy.Balance).to.equal(
					0
				)
			end, { Backend = backend })
		end)

		it("renews a clean profile through the coordinated scheduler", function()
			run(function(f)
				local player = newPlayer(8400)
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				local before = f.Backend:GetRecord("player_8400").LeaseExpiresAt
				-- UserId 8400 receives the deterministic four-second autosave stagger.
				f.Advance(65)
				Service:Step()
				for _ = 1, 10 do
					task.wait()
					if f.Backend:GetRecord("player_8400").LeaseExpiresAt > before then
						break
					end
				end
				local record = f.Backend:GetRecord("player_8400")
				expect(record.LeaseExpiresAt > before).to.equal(true)
				expect(record.LastRevision).to.equal(0)
				expect(Service:GetDiagnostics(player).dirty).to.equal(false)
			end)
		end)

		it("does not unlock the record after an unconfirmed final save", function()
			local backend = FakeBackend.new({ FinalSaveFailure = true })
			run(function()
				local player = newPlayer(8500)
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				expect(Currency:TryCredit(player, 3.5, "Final").ok).to.equal(true)
				local closed = Service:ClosePlayerAsync(player, "InjectedFinalFailure")
				expect(closed.ok).to.equal(false)
				local record = backend:GetRecord("player_8500")
				expect(record.OwnerToken ~= nil).to.equal(true)
				expect(record.Data.Economy.Balance).to.equal(0)
			end, { Backend = backend })
		end)

		it("releases an acquired token when the player leaves during loading", function()
			local player = newPlayer()
			local backend = FakeBackend.new()
			run(function()
				backend.BeforeAcquireReturn = function()
					player.Parent = nil
					Service:ClosePlayerAsync(player, "LeftDuringLoad")
				end
				local loaded = Service:LoadPlayerAsync(player)
				expect(loaded.ok).to.equal(false)
				expect(Service:GetStatus(player)).to.equal("Closed")
				local record = backend:GetRecord("player_" .. player.UserId)
				expect(record.OwnerToken).to.equal(nil)
				expect(player.Attributes.Cash).to.equal(nil)
			end, { Backend = backend })
		end)

		it("rejects an old owner after a new exact Player session acquires", function()
			run(function(f)
				local first = newPlayer(8301)
				expect(Service:LoadPlayerAsync(first).ok).to.equal(true)
				local firstHandle = Service:GetSessionHandle(first)
				expect(Service:IsCurrentSessionHandle(firstHandle)).to.equal(true)
				local oldToken = f.Backend.Events[1].token
				expect(Currency:TryCredit(first, 5, "First").ok).to.equal(true)
				expect(Service:ClosePlayerAsync(first, "Handoff").ok).to.equal(true)
				first.Parent = nil

				local second = newPlayer(8301)
				expect(Service:LoadPlayerAsync(second).ok).to.equal(true)
				local secondHandle = Service:GetSessionHandle(second)
				expect(Service:IsCurrentSessionHandle(firstHandle)).to.equal(false)
				expect(Service:IsCurrentSessionHandle(secondHandle)).to.equal(true)
				expect(Currency:TryCredit(second, 2, "Second").ok).to.equal(true)
				expect(Currency:TryCredit(first, 100, "StalePlayer").ok).to.equal(false)
				local stale = f.Backend:Save(
					"player_8301",
					oldToken,
					"stale-op",
					99,
					{ SchemaVersion = 1, Economy = { Balance = 999 } },
					180
				)
				expect(stale.code).to.equal("OWNER_MISMATCH")
				expect(Currency:GetBalance(second)).to.equal(7)
			end)
		end)

		it("freezes mutations at the conservative lease safety deadline", function()
			run(function(f)
				local player = newPlayer()
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				f.Advance(166)
				expect(Service:IsWritable(player)).to.equal(false)
				expect(Currency:TryCredit(player, 1, "TooLate").ok).to.equal(false)
			end)
		end)

		it("runs finalizers before the atomic save-and-release operation", function()
			run(function(f)
				local player = newPlayer()
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				Service:RegisterCloseFinalizer(function(subject)
					expect(subject).to.equal(player)
					table.insert(f.Backend.Events, { kind = "Finalizer" })
				end)
				expect(Service:ClosePlayerAsync(player, "Ordering").ok).to.equal(true)
				local finalizerIndex, releaseIndex
				for index, event in f.Backend.Events do
					if event.kind == "Finalizer" then
						finalizerIndex = index
					elseif event.kind == "Release" then
						releaseIndex = index
					end
				end
				expect(finalizerIndex < releaseIndex).to.equal(true)
				expect(Service:ClosePlayerAsync(player, "Duplicate").code).to.equal(
					"ALREADY_CLOSED"
				)
			end)
		end)

		it("commits departure preparation before closing and the final snapshot", function()
			run(function(f)
				local player = newPlayer(8599)
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				Service:RegisterDeparturePreparer(function(subject, reason)
					expect(subject).to.equal(player)
					expect(reason).to.equal("DepartureOrdering")
					expect(Service:IsWritable(subject)).to.equal(true)
					local result = Service:CommitMutation(subject, function(data)
						data.Economy.Balance = 17.25
						return true, { ok = true, code = "DEPARTURE_APPLIED" }
					end)
					return result.ok, result.code
				end)
				expect(Service:ClosePlayerAsync(player, "DepartureOrdering").ok).to.equal(true)
				local record = f.Backend:GetRecord("player_8599")
				expect(record.Data.Economy.Balance).to.equal(17.25)
				expect(record.LastRevision).to.equal(1)
			end)
		end)

		it("allows the exact close operation to finish after PlayerRemoving detaches", function()
			run(function(f)
				local player = newPlayer(8600)
				expect(Service:LoadPlayerAsync(player).ok).to.equal(true)
				player.Parent = nil
				expect(Service:IsWritable(player)).to.equal(false)
				Service:RegisterDeparturePreparer(function(subject)
					expect(subject).to.equal(player)
					expect(Service:IsWritable(subject)).to.equal(true)
					local result = Service:CommitMutation(subject, function(data)
						data.Economy.Balance = 23.75
						return true, { ok = true, code = "DETACHED_DEPARTURE_APPLIED" }
					end)
					return result.ok, result.code
				end)
				expect(Service:ClosePlayerAsync(player, "PlayerRemoving").ok).to.equal(true)
				local record = f.Backend:GetRecord("player_8600")
				expect(record.Data.Economy.Balance).to.equal(23.75)
				expect(record.LastRevision).to.equal(1)
			end)
		end)

		it("closes other profiles concurrently and reports one unconfirmed shutdown key", function()
			local backend = FakeBackend.new({ FinalSaveFailureKeys = { player_8601 = true } })
			run(function(f)
				local first = newPlayer(8601)
				local second = newPlayer(8602)
				expect(Service:LoadPlayerAsync(first).ok).to.equal(true)
				expect(Service:LoadPlayerAsync(second).ok).to.equal(true)
				expect(Currency:TryCredit(first, 1.5, "First").ok).to.equal(true)
				expect(Currency:TryCredit(second, 2.5, "Second").ok).to.equal(true)
				local shutdown = Service:ShutdownAsync(f.Now() + 25)
				expect(shutdown.ok).to.equal(false)
				expect(shutdown.code).to.equal("CLOSE_UNCONFIRMED")
				expect(#shutdown.unresolved).to.equal(1)
				expect(shutdown.unresolved[1].userId).to.equal(8601)
				expect(backend:GetRecord("player_8601").OwnerToken ~= nil).to.equal(true)
				expect(backend:GetRecord("player_8602").OwnerToken).to.equal(nil)
				expect(backend:GetRecord("player_8602").Data.Economy.Balance).to.equal(2.5)
			end, { Backend = backend, YieldWait = true })
		end)
	end)
end
