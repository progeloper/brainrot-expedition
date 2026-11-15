--!nocheck
-- Synthetic, disposable profiles; real economic/profile/storage owners and serializer.
-- Only storage transport, base assignment, presentation assets, clock and the
-- synthetic offer's existing readiness/grant adapter are controlled boundaries.
return function()
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
	local Base = require(script.Parent.Parent.Systems.PlayerBaseSystem)
	local Storage = require(script.Parent.Parent.Systems.BaseStorageSystem)
	local Cargo = require(script.Parent.Parent.Services.CartCargoService)
	local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)
	local DeparturePolicy = require(script.Parent.Parent.Services.DeparturePolicy)
	local Upgrade = require(script.Parent.Parent.Services.UpgradeService)
	local Eligibility = require(RS.Shared.Utility.UpgradeEligibility)
	local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
	local Interaction = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
	local Metrics = require(script.Parent.Parent.Services.ProgressionMetricsService)
	local Sale = require(script.Parent.Parent.Systems.BrainrotSaleSystem)
	local Sleep = require(script.Parent.Parent.Systems.BrainrotSleepSystem)
	local Cohorts = require(script.Parent.Support.ProgressionProfileFixtures)
	local ProfileFixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local Catalog = require(RS.Shared.Config.BrainrotCatalog)

	-- TEST_COMMON is represented by BRT_999 because production serialization
	-- deliberately requires the stable BRT_### format. Never add it to the shop/catalogue.
	local SPECIES = "BRT_999"
	local PAYDAY_CASH = 25000000
	local function fixtureData()
		local data = Schema.CreateDefault()
		data.Economy.Balance = 1000.5
		data.Collection.BrainrotInstances.A =
			{ speciesId = SPECIES, metadata = { synthetic = true } }
		data.Collection.BrainrotInstances.B =
			{ speciesId = SPECIES, metadata = { synthetic = true } }
		data.Base.Slots["1"] = { brainrotId = "A", accumulatedCash = 120.25 }
		data.Base.Slots["2"] = { brainrotId = "B", accumulatedCash = 33.4 }
		data.Base.Slots["4"].accumulatedCash = 8.75
		data.Settings = { fixtureLabel = "7F_SYNTHETIC", volume = 0.25 }
		return data
	end

	local function same(actual, expected, path)
		path = path or "profile"
		assert(type(actual) == type(expected), path .. ": type differs")
		if type(expected) ~= "table" then
			assert(actual == expected, path .. ": value differs")
			return
		end
		for key, value in expected do
			same(actual[key], value, path .. "." .. tostring(key))
		end
		for key in actual do
			assert(expected[key] ~= nil, path .. ": unexpected " .. tostring(key))
		end
	end

	local function offer(id)
		return {
			id = id,
			displayName = id,
			category = "Cargo",
			price = 750,
			currencyId = "Cash",
			grant = { kind = "UpgradeTrackLevel", trackId = id, level = 1 },
			ownershipScope = { kind = "PlayerWide" },
			applicability = { kind = "AllOwnedCarts" },
			requirements = {},
			effect = {
				statId = "CargoCapacity",
				operation = "AddSlots",
				value = 1,
				unit = "Slots",
				summary = "+1 synthetic slot",
			},
			displayOrder = if id == "FIXTURE_CARGO_1" then 1 else 2,
			definitionStatus = "Complete",
			releaseStatus = "Released",
			effectStatus = "ReadyFixtureOnly",
			openDecisionCodes = {},
		}
	end

	local function run(callback, options)
		options = options or {}
		Metrics:Stop()
		Sale:Stop()
		Income:Stop()
		Storage:Destroy()
		Upgrade:Stop()
		Profile:_ResetForTests()
		local now, sequence, generation, randomDraws = options.StartTime or 1000, 0, 0, 0
		local assigned, released, current
		local allPlayers, replacements, connections, writes, currencyReceipts = {}, {}, {}, {}, {}
		local ownedTemplates, worldFixtureIds = {}, {}
		local function replace(object, key, value)
			table.insert(replacements, { object = object, key = key, original = object[key] })
			object[key] = value
		end
		local base = Instance.new("Model")
		base.Name, base.Parent = "SPEC_7F_INTEGRATION_BASE", workspace
		base:SetAttribute("BaseId", base.Name)
		for index = 1, 48 do
			local platform = Instance.new("Part")
			platform.Name, platform.Anchored = "Slot_" .. index, true
			platform.Position = Vector3.new(42000 + index * 10, 100, 42000)
			platform:SetAttribute("SlotIndex", index)
			platform.Parent = base
			local marker = Instance.new("Attachment")
			marker.Name, marker.Parent = "BrainrotPlacement", platform
		end
		local shop = Instance.new("Part")
		shop.Name, shop.Anchored, shop.Parent = "SPEC_7F_INTEGRATION_SHOP", true, workspace
		local backend = options.Backend
			or FakeBackend.new({
				Now = function()
					return now
				end,
				Records = {
					player_89701 = { Data = options.Data or fixtureData(), LastRevision = 0 },
				},
			})
		backend.Now = function()
			return now
		end
		local save = backend.Save
		function backend:Save(key, token, operationId, revision, snapshot, lease)
			-- Independently retained serialization output, not the live table.
			table.insert(
				writes,
				{ revision = revision, data = assert(Schema.CreateSaveSnapshot(snapshot)) }
			)
			return save(self, key, token, operationId, revision, snapshot, lease)
		end
		Profile:Init({
			Backend = backend,
			UnixNow = function()
				return now
			end,
			MonotonicNow = function()
				return now
			end,
			Wait = function(seconds)
				now += seconds
			end,
			Random = function()
				randomDraws += 1
				return 0
			end,
			GenerateOperationId = function(prefix)
				sequence += 1
				return prefix .. ":integration:" .. sequence
			end,
			KickOnFailure = false,
		})
		Currency:_ResetForTests(Profile, {
			Now = function()
				return now
			end,
		})
		table.insert(
			connections,
			Currency:SubscribeCommitted(function(_, receipt)
				table.insert(currencyReceipts, ProfileFixtures.Clone(receipt))
			end)
		)
		Banked:_ResetForTests({ Profile = Profile, Currency = Currency })
		Banked:Start()
		replace(Base, "GetRegisteredBases", function()
			return { base }
		end)
		replace(Base, "GetBase", function(_, player)
			return if current and current.Player == player then base else nil
		end)
		replace(Base, "IsOwner", function(_, player, candidate)
			return current ~= nil and current.Player == player and candidate == base
		end)
		replace(Base, "GetAssignment", function(_, player)
			return if current and current.Player == player then current else nil
		end)
		replace(Base, "IsCurrentAssignment", function(_, handle)
			return handle ~= nil and handle == current
		end)
		replace(Base, "SubscribeAssignments", function(_, onAssigned, onReleased)
			assigned, released = onAssigned, onReleased
			return {
				Disconnect = function()
					assigned, released = nil, nil
				end,
			}
		end)
		replace(Cargo, "CreateItemVisual", function(_, species)
			assert(
				species == SPECIES
					or species == "BRT_002"
					or (options.RealDefinitions and Catalog.GetDefinition(species)),
				"unexpected fixture species"
			)
			local model, body = Instance.new("Model"), Instance.new("Part")
			body.Name, body.Size, body.Parent = "Body", Vector3.new(2, 2, 2), model
			model.PrimaryPart = body
			return model
		end)
		Storage:Start({ Profile = Profile, BankNow = function() return now end })
		Income:Init({
			Now = function()
				return now
			end,
			Storage = Storage,
			Base = Base,
			Wallet = Currency,
			Profile = Profile,
			ConnectScheduler = false,
			ResolvePlatformRate = function(species)
				if options.RealDefinitions then
					return Catalog.GetCashPerSecond(species)
				end
				return if species == SPECIES then options.Rate or 0 else nil
			end,
		})
		assert(Income:Start())
		table.insert(
			connections,
			Profile:RegisterSnapshotPreparer(function(player)
				-- Matches Bootstrap: income owns its monotonic settlement clock.
				return Income:PrepareForSave(player)
			end)
		)
		table.insert(
			connections,
			Profile:RegisterCloseFinalizer(function(player)
				Income:FinalizePlayerSession(player, math.floor(now * 1000))
				if current and current.Player == player then
					local handle = current
					released(player, base, handle)
					current = nil
				end
			end)
		)
		local offers = { offer("FIXTURE_CARGO_1"), offer("FIXTURE_CARGO_2") }
		if options.Price then
			for _, definition in offers do
				definition.price = options.Price
			end
		end
		local catalogue = {
			Get = function(id)
				for _, entry in offers do
					if entry.id == id then
						return entry
					end
				end
				return nil
			end,
			GetAll = function()
				return offers
			end,
		}
		local f = { Backend = backend, Writes = writes, Base = base, Shop = shop, CurrencyReceipts = currencyReceipts }
		Upgrade:Init({
			Profile = Profile,
			Currency = Currency,
			Catalogue = catalogue,
			Eligibility = Eligibility,
			Readiness = {
				effectReadyByOfferId = { FIXTURE_CARGO_1 = true, FIXTURE_CARGO_2 = true },
				persistenceReadyByScope = { PlayerWide = true },
			},
			WorldReady = function(player)
				return current and current.Player == player
			end,
			WithinShopRange = function(_, target)
				return target == shop
			end,
			ResolveTarget = function()
				return nil, nil
			end,
			BuildPlayerSnapshot = function(player, data)
				return {
					status = "Ready",
					userId = player.UserId,
					balance = data.Economy.Balance,
					ownedOfferIds = data.Progression.Upgrades,
				}
			end,
			ApplyGrant = function(data, definition)
				if data.Progression.Upgrades[definition.id] then
					return false, "ALREADY_OWNED"
				end
				if f.BeforeGrant then
					f.BeforeGrant()
				end
				data.Progression.Upgrades[definition.id] = true
				return true
			end,
			Now = function()
				return now
			end,
			GenerateId = function()
				sequence += 1
				return "context:" .. sequence
			end,
		})
		local worldReadyCallback
		if options.Metrics then
			local inert = {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
			Metrics:Start({
				Players = {
					GetPlayers = function()
						return {}
					end,
					PlayerAdded = inert,
					PlayerRemoving = inert,
				},
				Profile = Profile,
				Currency = Currency,
				Income = Income,
				Storage = Storage,
				Upgrade = Upgrade,
				Sale = Sale,
				Interaction = Interaction,
				Sleep = Sleep,
				WorldLifecycle = {
					IsReady = function(_, player)
						return current and current.Player == player
					end,
					SubscribeReady = function(_, readyCallback)
						worldReadyCallback = readyCallback
						return {
							Disconnect = function()
								worldReadyCallback = nil
							end,
						}
					end,
				},
				Catalog = if options.RealDefinitions
					then Catalog
					else {
						GetCashPerSecond = function()
							return options.Rate or 0
						end,
					},
				Environment = { Name = "Development", BuildId = "7G1_SYNTHETIC_PRODUCTION_PATH" },
				ConnectScheduler = false,
				Regions = false,
				LogReports = false,
				ReadLocation = function()
					return nil
				end,
				Now = function()
					return now
				end,
				GenerateObservationId = function()
					return "7G1_exact_production_trace"
				end,
			})
		end
		function f.Now()
			return now
		end
		function f.RandomDraws()
			return randomDraws
		end
		function f.Load(userId)
			local player = { UserId = userId or 89701, Name = "Synthetic7F", Parent = Players }
			function player:SetAttribute() end
			function player:Kick() end
			table.insert(allPlayers, player)
			assert(Profile:LoadPlayerAsync(player).ok, "profile acquisition failed")
			if options.SetupSource then
				options.SetupSource(player, Profile)
			end
			generation += 1
			current = { Player = player, Base = base, BaseId = base.Name, Generation = generation }
			assigned(player, base, current)
			assert(Storage:GetStorageForPlayer(player))
			if worldReadyCallback then
				worldReadyCallback(player)
			end
			return player
		end
		function f.Close(player)
			assert(
				Profile:ClosePlayerAsync(player, "7FIntegration").ok,
				"profile close unconfirmed"
			)
			player.Parent = nil
			expect(Profile:GetDiagnostics(player)).to.equal(nil)
			expect(Income:GetStateSnapshot(player)).to.equal(nil)
			expect(Storage:GetStorageForPlayer(player)).to.equal(nil)
			expect(backend:GetRecord("player_" .. player.UserId).OwnerToken).to.equal(nil)
		end
		function f.Abandon(player)
			-- Abrupt-server-loss simulation: discard the profile owner before any
			-- runtime cleanup; do not run ClosePlayerAsync or registered finalizers.
			local before = backend:GetRecord("player_" .. player.UserId)
			Profile:_ResetForTests()
			player.Parent = nil
			Income:Stop()
			Storage:Destroy()
			current = nil
			same(backend:GetRecord("player_" .. player.UserId), before)
		end
		function f.Save(player)
			assert(Profile:SaveNowAsync(player, "7FBoundary").ok, "snapshot unconfirmed")
			local durable = backend:GetRecord("player_" .. player.UserId)
			same(durable.Data, assert(Schema.CreateSaveSnapshot(Profile:GetReadableData(player))))
			return durable.Data
		end
		function f.Open(player)
			return assert(Upgrade:OpenShop(player, shop).payload).contextId
		end
		function f.Buy(player, context, requestId, offerId)
			return Upgrade:Purchase(player, {
				contextId = context,
				requestId = requestId,
				offerId = offerId or "FIXTURE_CARGO_1",
			})
		end
		function f.Advance(seconds)
			now += seconds
		end
		function f.Rebind(player)
			local before = Storage:GetStorageForPlayer(player)
			assert(Storage:EnsureBound(player, base, current))
			expect(Storage:GetStorageForPlayer(player)).to.equal(before)
		end
		function f.Reassign(player)
			generation += 1
			current = { Player = player, Base = base, BaseId = base.Name, Generation = generation }
			assigned(player, base, current)
			return Storage:GetStorageForPlayer(player)
		end
		function f.StaleRelease(player, handle)
			released(player, base, handle)
		end
		function f.Handle()
			return current
		end
		function f.EnableCarry(player, platform)
			assert(Interaction.Stop(), "prior carry fixture leaked")
			local character, root, humanoid =
				Instance.new("Model"), Instance.new("Part"), Instance.new("Humanoid")
			character.Name, character.Parent = "SyntheticCharacter", base
			root.Name, root.Anchored, root.Parent = "HumanoidRootPart", true, character
			root.Position = platform.Position + Vector3.new(0, 3, 6)
			humanoid.RequiresNeck, humanoid.Parent = false, character
			character.PrimaryPart, player.Character = root, character
			local removing = Instance.new("BindableEvent")
			removing.Parent, player.CharacterRemoving = character, removing.Event
			local worldAdapter = setmetatable({
				CreateRestoredWorldRecord = function(record, pose)
					-- This existing death/profile fixture controls external presentation
					-- for synthetic BRT_999; the real factory is covered by the
					-- serializer-restored pickup regression in platform placement.
					local runtime = table.clone(record)
					runtime.World = {
						Name = "SyntheticRestored",
						Scale = 1,
						SpawnPosition = { X = pose.X, Y = pose.Y, Z = pose.Z },
					}
					return runtime
				end,
				PrepareWorldRepresentation = function()
					-- Asset preparation is external to the profile/death-return operation.
					return { Model = Instance.new("Model") }
				end,
				DiscardPreparedWorld = function(preparation)
					preparation.Model:Destroy()
				end,
				FindSafeReleasePose = function(_, pose)
					return pose
				end,
			}, { __index = World })
			Interaction.Start({
				World = worldAdapter,
				CreateItemVisual = function(id)
					return Cargo:CreateItemVisual(id)
				end,
				IsDriving = function()
					return false
				end,
				Banked = Banked,
				DeparturePolicy = DeparturePolicy,
			})
			f.CarryPlayer = player
		end
		function f.AcquireBankedForSale(player)
			f.EnableCarry(player, f.Base.Slot_1)
			-- The world owner intentionally rejects unknown BRT IDs. Use an actual
			-- supported species for this fresh acquisition; the isolated sale
			-- definition still fixes the trace payout at 120.
			local freshSpecies = "BRT_002"
			local assets = RS:FindFirstChild("StudioAssets")
			if not assets then
				assets = Instance.new("Folder")
				assets.Name = "StudioAssets"
				assets.Parent = RS
			end
			local templates = assets:FindFirstChild("Brainrots")
			if not templates then
				templates = Instance.new("Folder")
				templates.Name = "Brainrots"
				templates.Parent = assets
			end
			local template = templates:FindFirstChild(freshSpecies)
			local createdTemplate = template == nil
			if createdTemplate then
				template = Cargo:CreateItemVisual(SPECIES)
				template.Name = freshSpecies
				template.Body.Anchored = true
				for _, name in { "CaptureAttachment", "CargoAttachment" } do
					local attachment = Instance.new("Attachment")
					attachment.Name, attachment.Parent = name, template.Body
				end
				template.Parent = templates
				table.insert(ownedTemplates, template)
			end
			local point = player.Character.HumanoidRootPart.Position + Vector3.new(0, 0, -4)
			local record = {
				ItemId = "7G1-fresh-individual",
				BrainrotId = freshSpecies,
				Metadata = {},
				World = {
					Name = "7G1Fresh",
					Scale = 1,
					SpawnPosition = { X = point.X, Y = point.Y, Z = point.Z },
				},
			}
			local prepared, reason = World.PrepareWorldRepresentation(record, CFrame.new(point))
			assert(prepared, reason)
			table.insert(worldFixtureIds, record.ItemId)
			-- Exact private query shapes require the authored source for the active
			-- lifetime. Keep this TEST ONLY source until its exact world ID is gone.
			local model = assert(World.ActivatePreparedWorld(prepared))
			assert(World.TrySleep(model))
			local picked, pickupReason = Interaction.TryPickupWorld(player, model, record.ItemId)
			assert(picked, pickupReason)
			-- Phase 10 requires an explicit first bank. Deposit and immediate lift
			-- share the trace timestamp, so no extra income interval is introduced.
			assert(Interaction.TryPlaceOnPlatform(player, f.Base.Slot_1, record.ItemId))
			assert(Interaction.TryPickupPlatform(player, f.Base.Slot_1, record.ItemId))
			shop.CFrame = player.Character.HumanoidRootPart.CFrame
			Sale:Init({
				Carry = Interaction,
				Currency = Currency,
				Banked = Banked,
				Catalog = {
					GetDefinition = function(id)
						assert(id == freshSpecies, "unexpected synthetic sale species")
						return { displayName = "TEST_COMMON", tier = "Common", sellValue = 120 }
					end,
				},
				ResolveSalePoint = function()
					return shop
				end,
				Now = function()
					return now
				end,
				GenerateSessionId = function()
					return "7G1-fresh-sale"
				end,
			})
			return record
		end
		local ok, failure = xpcall(function()
			callback(f)
		end, debug.traceback)
		if f.CarryPlayer then
			Interaction.HandleCharacterRemoving(f.CarryPlayer, f.CarryPlayer.Character)
			assert(Interaction.Stop(), "integration carry cleanup incomplete")
		end
		-- Clean only this run's registered synthetic identities, including a failed
		-- activation/pickup, before removing their temporary source templates.
		for _, itemId in worldFixtureIds do
			World.DestroyWorldForTesting(itemId)
		end
		for _, template in ownedTemplates do
			template:Destroy()
		end
		Metrics:Stop()
		Sale:Stop()
		Upgrade:Stop()
		Income:Stop()
		Storage:Destroy()
		for _, connection in connections do
			connection:Disconnect()
		end
		Banked:_ResetForTests()
		Currency:_ResetForTests()
		Profile:_ResetForTests()
		backend.Save = save
		for index = #replacements, 1, -1 do
			local entry = replacements[index]
			entry.object[entry.key] = entry.original
		end
		for _, player in allPlayers do
			player.Parent = nil
		end
		base:Destroy()
		shop:Destroy()
		assert(ok, failure)
	end

	local function assertTrace(data, wallet, stage)
		expect(data.Economy.Balance).to.equal(wallet)
		expect(data.Base.Slots["1"].accumulatedCash).to.equal(if stage == 0 then 120.25 else 0)
		expect(data.Base.Slots["1"].brainrotId).to.equal(if stage < 2 then "A" else nil)
		expect(data.Collection.BrainrotInstances.A ~= nil).to.equal(stage < 3)
		expect(data.Collection.BrainrotInstances.B.speciesId).to.equal(SPECIES)
		expect(data.Base.Slots["2"].brainrotId).to.equal("B")
		expect(data.Base.Slots["2"].accumulatedCash).to.equal(33.4)
		expect(data.Base.Slots["4"].brainrotId).to.equal(nil)
		expect(data.Base.Slots["4"].accumulatedCash).to.equal(8.75)
		expect(data.Progression.Upgrades.FIXTURE_CARGO_1 == true).to.equal(stage == 4)
		expect(data.Settings.fixtureLabel).to.equal("7F_SYNTHETIC")
		local slots, occupants = 0, {}
		for _, slot in data.Base.Slots do
			slots += 1
			assert(
				slot.accumulatedCash == slot.accumulatedCash and slot.accumulatedCash >= 0,
				"invalid cash"
			)
			if slot.brainrotId then
				assert(not occupants[slot.brainrotId], "duplicate durable occupant")
				assert(
					data.Collection.BrainrotInstances[slot.brainrotId],
					"missing owned individual"
				)
				occupants[slot.brainrotId] = true
			end
		end
		expect(slots).to.equal(48)
	end

	local function assertOnePayday(data, receipts, ordinaryCash)
		local day = assert(data.Retention.Day, "Expected actual own-income settlement day")
		local quest = day.camp_payday
		expect(day.unitCash).to.equal(PAYDAY_CASH)
		expect(day.regionBand).to.equal("Forest")
		expect(quest.count).to.equal(1)
		expect(quest.paid).to.equal(true)
		expect(quest.paidCash).to.equal(PAYDAY_CASH)
		expect(quest.grantId).to.equal("retention:" .. tostring(day.dayKey) .. ":camp_payday")
		local grantCount, retentionCash, ordinary = 0, 0, 0
		for _, receipt in receipts do
			if receipt.kind == "WalletCredit" and receipt.source == "PlatformIncomeClaim" then
				ordinary += receipt.amount
				local reward = receipt.retention
				local paid = if reward then reward.amountCash or 0 else 0
				expect(receipt.balanceAfter - receipt.balanceBefore).to.equal(receipt.amount + paid)
				for _, transition in reward and reward.transitions or {} do
					if transition.amountCash > 0 then
						grantCount += 1
						retentionCash += transition.amountCash
						expect(transition.grantId).to.equal(quest.grantId)
						expect(transition.sourceOperation).to.equal(quest.sourceOperation)
					end
				end
			end
		end
		expect(grantCount).to.equal(1)
		expect(retentionCash).to.equal(PAYDAY_CASH)
		expect(ordinary).to.equal(ordinaryCash)
		expect(next(data.Retention.PendingRewards)).to.equal(nil)
	end

	describe("Phase 7F production-owner persistence integration", function()
		it(
			"saves occupant removal and retained cash together without paying the wallet",
			function()
				run(function(f)
					local player = f.Load()
					local before = Profile:GetReadableData(player).Economy.Balance
					local revision = Profile:GetDiagnostics(player).currentRevision
					assert(Storage:TryRemoveFromPlatform(player, f.Base.Slot_1, "A"))
					local data = Profile:GetReadableData(player)
					expect(data.Base.Slots["1"].brainrotId).to.equal(nil)
					expect(data.Base.Slots["1"].accumulatedCash).to.equal(120.25)
					expect(data.Economy.Balance).to.equal(before)
					expect(Profile:GetDiagnostics(player).currentRevision).to.equal(revision + 1)
					local report = Metrics:GetReport(player)
					expect(report.economy.platformAdjustments).to.equal(0)
					expect(report.economy.walletCredits).to.equal(0)
					expect(report.economy.reconciled).to.equal(true)
					local durable = f.Save(player)
					expect(durable.Base.Slots["1"].brainrotId).to.equal(nil)
					expect(durable.Base.Slots["1"].accumulatedCash).to.equal(120.25)
					expect(durable.Economy.Balance).to.equal(before)
					f.Close(player)
				end, { Metrics = true })
			end
		)
		it(
			"7G-1 restores the four declared cohort baselines from independently stored production snapshots",
			function()
				for _, cohort in
					{ "Fresh", "PartialReturning", "DevelopedReturning", "StartingCashStock" }
				do
					local expected = Cohorts.Create(cohort)
					local backend = FakeBackend.new()
					run(function(f)
						local player = f.Load()
						f.Save(player)
						f.Close(player)
					end, {
						Backend = backend,
						RealDefinitions = true,
						SetupSource = function(player, owner)
							assert(
								owner:CommitMutation(player, function(data)
									for key, value in expected do
										data[key] = value
									end
									return true
								end).ok,
								"cohort source mutation rejected"
							)
						end,
					})
					run(function(f)
						local player = f.Load()
						local source = Profile:GetReadableData(player)
						local normalized = ProfileFixtures.WithPhase12ExpectedFields(expected)
						-- Current retention migration reconciles supported durable owned /
						-- banked proof, never a fresh daily action or Cash payout.
						if cohort ~= "Fresh" then
							normalized.Retention.Eligible, normalized.Retention.Revision = true, 1
						end
						if cohort == "DevelopedReturning" then
							for _, id in { "P14_TITLE_COLLECTOR", "P14_NAMEPLATE_FIELD_RESEARCH" } do
								normalized.Retention.Milestones[id] =
									{ earned = true, source = "DurableBankedDiscovery" }
							end
						end
						same(source, normalized)
						expect(source.Economy.Balance).to.equal(expected.Economy.Balance)
						expect(source.Retention.Day).to.equal(nil)
						expect(#f.CurrencyReceipts).to.equal(0)
						expect(source == expected).to.equal(false)
						local report = Metrics:GetReport(player)
						expect(report.session.profileOrigin).to.equal("Existing")
						expect(report.startingState.occupiedSlotCount).to.equal(
							if cohort == "PartialReturning"
								then 4
								elseif cohort == "DevelopedReturning" then 12
								elseif cohort == "StartingCashStock" then 1
								else 0
						)
						expect(report.economy.platformIncomeGenerated).to.equal(0)
						expect(report.economy.reconciled).to.equal(true)
						print("[7G1_COHORT_RESTORE] " .. game:GetService("HttpService"):JSONEncode({
							cohort = cohort,
							startingState = report.startingState,
							evidence = "AUTOMATED_FAKE_BACKEND_REAL_SERIALIZER_RESTORE",
						}))
						f.Close(player)
					end, { Backend = backend, RealDefinitions = true, Metrics = true })
				end
			end
		)

		it(
			"retained-platform accounting uses real commits and is identical with measurement disabled",
			function()
				local function trace(enabled)
					local data = Schema.CreateDefault()
					-- Preserve a fixed previously earned species proof when comparing
					-- independent runs; first-bank wall-clock sampling is unrelated to
					-- measurement interference and individual banking still runs below.
					data.WorldProgression.BankedSpecies.BRT_002 = {
						rarityAtFirstBank = "Common",
						source = "deposit",
						firstBankedAt = 1200,
					}
					data.Economy.Balance = 400.5
					data.Collection.BrainrotInstances.A = { speciesId = SPECIES, metadata = {} }
					data.Base.Slots["1"].brainrotId = "A"
					data.Base.Slots["4"].accumulatedCash = 120.25
					local result
					run(function(f)
						local player = f.Load()
						local start = f.Now()
						f.Advance(30)
						assert(Income:AccruePlatformsTo(f.Now()))
						-- Remove the producer through its real transition at t=30. Its
						-- earned 60 remains on its platform; empty-slot cash is retained on load.
						assert(Storage:TryRemoveFromPlatform(player, f.Base.Slot_1, "A"))
						if enabled then
							local report = Metrics:GetReport(player)
							expect(report.economy.platformIncomeGenerated).to.equal(60)
							expect(report.economy.endingWallet).to.equal(400.5)
							expect(report.offers[1].firstFundsSufficientAt).to.equal(nil)
						end
						f.Advance(30)
						local context = f.Open(player)
						f.Advance(1)
						local rendered = Upgrade:HandleRequest(player, {
							operation = "Presentation",
							contextId = context,
							kind = "MenuRendered",
							inputCategory = "Touch",
						})
						assert(rendered.ok, rendered.code)
						f.Advance(29)
						f.AcquireBankedForSale(player)
						local preview, saleReason = Sale:CreatePreview(player)
						assert(preview, saleReason)
						expect(Sale:ConfirmSale(player, preview.SaleSessionId).ok).to.equal(true)
						expect(Currency:GetBalance(player)).to.equal(520.5)
						f.Advance(30)
						-- New context is necessary: the original context expires after 45s.
						context = f.Open(player)
						local bought = f.Buy(player, context, "7G1-purchase")
						expect(bought.outcome).to.equal("Accepted")
						expect(f.Buy(player, context, "7G1-purchase").duplicate).to.equal(true)
						f.Advance(30)
						expect(Income:TryClaimPlatform(player, f.Base.Name, 1).paid).to.equal(60)
						expect(Income:TryClaimPlatform(player, f.Base.Name, 4).paid).to.equal(
							120.25
						)
						assertOnePayday(Profile:GetReadableData(player), f.CurrencyReceipts, 180.25)
						f.Advance(30)
						local before =
							assert(Schema.CreateSaveSnapshot(Profile:GetReadableData(player)))
						local revision = Profile:GetDiagnostics(player).currentRevision
						local savedCalls = #f.Backend.Events
						if enabled then
							local report = Metrics:GetReport(player)
							Metrics:GetReport(player)
							expect(Profile:GetDiagnostics(player).currentRevision).to.equal(
								revision
							)
							expect(#f.Backend.Events).to.equal(savedCalls)
							same(Profile:GetReadableData(player), before)
							expect(report.economy.walletCredits).to.equal(PAYDAY_CASH + 300.25)
							expect(report.economy.otherWalletCredits).to.equal(PAYDAY_CASH)
							expect(report.economy.walletDebits).to.equal(500)
							expect(report.economy.platformIncomeGenerated).to.equal(60)
							expect(report.economy.platformCashCollected).to.equal(180.25)
							expect(report.economy.platformAdjustments).to.equal(0)
							expect(report.economy.salesCurrentSessionAssets).to.equal(120)
							expect(report.economy.endingWallet).to.equal(PAYDAY_CASH + 200.75)
							expect(report.economy.endingSettledPlatformCash).to.equal(0)
							expect(report.economy.reconciled).to.equal(true)
							local entry = report.offers[1]
							expect(entry.firstContextIssuedAt - start).to.equal(60)
							expect(entry.firstMenuRenderedAt - start).to.equal(61)
							expect(entry.firstEligibleAffordableAt - start).to.equal(90)
							expect(entry.purchaseCommittedAt - start).to.equal(120)
							print(
								"[7G1_PRODUCTION_TRACE] "
									.. game:GetService("HttpService"):JSONEncode({
										economy = report.economy,
										offer = entry,
										duration = 180,
										evidence = "AUTOMATED_PRODUCTION_PATH_SYNTHETIC_DEFINITIONS",
									})
							)
						end
						local durable = f.Save(player)
						local operationKinds = {}
						for _, event in f.Backend.Events do
							table.insert(operationKinds, event.kind)
						end
						result = {
							data = durable,
							revision = Profile:GetDiagnostics(player).currentRevision,
							randomDraws = f.RandomDraws(),
							operationKinds = operationKinds,
						}
						f.Close(player)
					end, { Data = data, Rate = 2, Price = 500, Metrics = enabled })
					return result
				end
				same(trace(true), trace(false), "instrumentation noninterference")
			end
		)

		it(
			"returns a banked death/reset carry to one live display and resumes income only after the return",
			function()
				run(function(f)
					local player = f.Load()
					f.EnableCarry(player, f.Base.Slot_1)
					local pickedUp, reason =
						Interaction.TryPickupPlatform(player, f.Base.Slot_1, "A")
					assert(pickedUp, reason)
					f.Advance(10)
					expect(Income:Step()).to.equal(true)
					expect(Profile:GetReadableData(player).Base.Slots["1"].accumulatedCash).to.equal(
						120.25
					)
					expect(Interaction.HandleCharacterRemoving(player, player.Character)).to.equal(
						true
					)
					expect(Interaction.IsCarrying(player)).to.equal(false)
					expect(Profile:GetReadableData(player).Base.Slots["1"].brainrotId).to.equal("A")
					local storage = Storage:GetStorageForPlayer(player)
					expect(storage:ContainsItem("A")).to.equal(true)
					expect(storage:GetPlatformDisplay(1) ~= nil).to.equal(true)
					expect(storage:GetOccupiedCount()).to.equal(2)
					expect(Interaction.HandleCharacterRemoving(player, player.Character)).to.equal(
						false
					)
					f.Advance(2)
					expect(Income:Step()).to.equal(true)
					expect(Profile:GetReadableData(player).Base.Slots["1"].accumulatedCash).to.equal(
						122.25
					)
					expect(Income:TryClaimPlatform(player, f.Base.Name, 1).paid).to.equal(122.25)
					f.Close(player)
				end, { Rate = 1 })
			end
		)

		it(
			"returns crash-retained unassigned ownership before fresh base binding without moving cash or metadata",
			function()
				local backend, confirmed
				run(function(f)
					local player = f.Load()
					local removed =
						assert(Storage:TryRemoveFromPlatform(player, f.Base.Slot_1, "A"))
					expect(removed.Metadata.DurableOwnerUserId).to.equal(player.UserId)
					confirmed = f.Save(player)
					expect(confirmed.Collection.BrainrotInstances.A.speciesId).to.equal(SPECIES)
					expect(confirmed.Base.Slots["1"].brainrotId).to.equal(nil)
					backend = f.Backend
					f.Abandon(player)
					expect(backend:GetRecord("player_89701").OwnerToken ~= nil).to.equal(true)
				end)
				-- Independent live tables and runtime registries; only the durable fake
				-- backend crosses this boundary. Advancing time uses the real lease gate.
				run(function(f)
					local returning = f.Load()
					local restored = Profile:GetReadableData(returning)
					local expected = assert(Schema.CreateSaveSnapshot(confirmed))
					expected.Base.Slots["1"].brainrotId = "A"
                    expected.Phase13.EligibilityRevision+=1
					same(restored, expected)
					expect(restored == confirmed).to.equal(false)
					local storage = Storage:GetStorageForPlayer(returning)
					expect(storage:ContainsItem("A")).to.equal(true)
					expect(storage:ContainsItem("B")).to.equal(true)
					expect(storage:GetAvailableSlotCount()).to.equal(10)
					expect(f.Base.StoredBrainrots:FindFirstChild("Stored_A") ~= nil).to.equal(true)
					expect(DeparturePolicy.Resolve("RejoinUnassigned", "Banked").action).to.equal(
						"ReturnToAvailableSlotOrRetainOwned"
					)
					local revision = Profile:GetDiagnostics(returning).currentRevision
					f.Rebind(returning)
					expect(Profile:GetDiagnostics(returning).currentRevision).to.equal(revision)
					same(f.Save(returning), expected)
					f.Close(returning)
				end, { Backend = backend, StartTime = 3000 })
			end
		)

		it(
			"applies the approved full-base crash outcome without payout, world publication or slot-cash changes",
			function()
				local data = fixtureData()
				data.Collection.BrainrotInstances = {}
				for index = 1, 12 do
					local id = "occupied-" .. index
					data.Collection.BrainrotInstances[id] =
						{ speciesId = SPECIES, metadata = { slot = index } }
					data.Base.Slots[tostring(index)] =
						{ brainrotId = id, accumulatedCash = index + 0.25 }
				end
				local backend, confirmed
				local wildBefore = World.GetWildCount()
				run(function(f)
					local player = f.Load()
					-- Synthetic pre-crash carried/cargo source state. There is no persisted
					-- held/cargo location field; only its durable ownership is serialized.
					expect(Profile:CommitMutation(player, function(currentData)
						currentData.Collection.BrainrotInstances.stranded =
							{ speciesId = SPECIES, metadata = { synthetic = true } }
						return true, { ok = true }
					end).ok).to.equal(true)
					confirmed, backend = f.Save(player), f.Backend
					f.Abandon(player)
				end, { Data = data })
				run(function(f)
					local player = f.Load()
					local expected = ProfileFixtures.WithPhase12ExpectedFields(assert(Schema.CreateSaveSnapshot(confirmed)))
					-- Full-base overflow remains durably owned and awaits a later free slot.
					same(Profile:GetReadableData(player), expected)
					expect(Storage:GetStorageForPlayer(player):GetOccupiedCount()).to.equal(12)
					expect(World.GetWildCount()).to.equal(wildBefore)
					same(f.Save(player), expected)
					f.Close(player)
				end, { Backend = backend, StartTime = 3000 })
			end
		)

		it(
			"does not auto-return a current-session carried individual on repeated or reassigned base reconstruction",
			function()
				run(function(f)
					local player = f.Load()
					local removed =
						assert(Storage:TryRemoveFromPlatform(player, f.Base.Slot_1, "A"))
					local revision = Profile:GetDiagnostics(player).currentRevision
					local before =
						assert(Schema.CreateSaveSnapshot(Profile:GetReadableData(player)))
					f.Rebind(player)
					expect(Profile:GetDiagnostics(player).currentRevision).to.equal(revision)
					local storage = f.Reassign(player)
					expect(storage:ContainsItem(removed.ItemId)).to.equal(false)
					expect(Profile:GetReadableData(player).Collection.BrainrotInstances.A.speciesId).to.equal(
						SPECIES
					)
					expect(Profile:GetReadableData(player).Base.Slots["1"].brainrotId).to.equal(nil)
					-- Existing income teardown marks the profile dirty once even with
					-- frozen time. Compare exact source data, not that unrelated revision.
					same(Profile:GetReadableData(player), before)
					local afterReassignment = Profile:GetDiagnostics(player).currentRevision
					expect(Banked:ReconcileInitialOwnedLocations(player, Profile).code).to.equal(
						"INITIAL_LOCATIONS_ALREADY_RECONCILED"
					)
					expect(Profile:GetDiagnostics(player).currentRevision).to.equal(
						afterReassignment
					)
					f.Close(player)
				end)
			end
		)

		it(
			"saves every exact trace boundary using actual collection, removal, sale and purchase owners",
			function()
				run(function(f)
					local wildBefore = World.GetWildCount()
					local player = f.Load()
					local original = Profile:GetReadableData(player)
					local allowed, stage, wallet = {}, 0, 1000.5
					local function boundary()
						local saved = f.Save(player)
						assertTrace(saved, wallet, stage)
						table.insert(allowed, saved)
					end
					boundary()
					local collection = Income:TryClaimPlatform(player, f.Base.Name, 1)
					expect(collection.ok).to.equal(true)
					expect(collection.paid).to.equal(120.25)
					stage, wallet = 1, PAYDAY_CASH + 1120.75
					assertOnePayday(Profile:GetReadableData(player), f.CurrencyReceipts, 120.25)
					boundary()
					local removed =
						assert(Storage:TryRemoveFromPlatform(player, f.Base.Slot_1, "A"))
					expect(removed.ItemId).to.equal("A")
					expect(removed.Metadata.DurableOwnerUserId).to.equal(player.UserId)
					stage = 2
					boundary()
					expect(Banked:TryCommitSale(player, removed, 120).ok).to.equal(true)
					stage, wallet = 3, PAYDAY_CASH + 1240.75
					boundary()
					local context = f.Open(player)
					expect(f.Buy(player, context, "trace-purchase").outcome).to.equal("Accepted")
					stage, wallet = 4, PAYDAY_CASH + 490.75
					boundary()
					expect(f.Buy(player, context, "trace-purchase").duplicate).to.equal(true)
					expect(f.Buy(player, context, "trace-second-request").code).to.equal(
						"ALREADY_OWNED"
					)
					for _, write in f.Writes do
						local matches = false
						for _, state in allowed do
							local equal = pcall(same, write.data, state)
							if equal then
								matches = true
								break
							end
						end
						expect(matches).to.equal(true)
					end
					f.Close(player)
					local returning = f.Load()
					local restored = Profile:GetReadableData(returning)
					expect(restored == original).to.equal(false)
					expect(restored.Base.Slots == original.Base.Slots).to.equal(false)
					assertTrace(restored, PAYDAY_CASH + 490.75, 4)
					assertOnePayday(restored, f.CurrencyReceipts, 120.25)
					f.Rebind(returning)
					expect(Storage:GetStorageForPlayer(returning):GetOccupiedCount()).to.equal(1)
					expect(World.GetWildCount()).to.equal(wildBefore)
					f.Close(returning)
				end)
			end
		)

		it(
			"prevents reentrant collection and sale while allowing a valid collection-then-purchase ordering",
			function()
				run(function(f)
					local player = f.Load()
					local context, duplicateCollection, purchase = f.Open(player)
					local connection = Currency:SubscribeCommitted(function(subject, receipt)
						if receipt.source == "PlatformIncomeClaim" then
							duplicateCollection = Income:TryClaimPlatform(subject, f.Base.Name, 1)
							purchase = f.Buy(subject, context, "collection-observer-purchase")
						end
					end)
					expect(Income:TryClaimPlatform(player, f.Base.Name, 1).paid).to.equal(120.25)
					connection:Disconnect()
					expect(duplicateCollection.code).to.equal("Busy")
					expect(purchase.outcome).to.equal("Accepted")
					expect(Currency:GetBalance(player)).to.equal(PAYDAY_CASH + 370.75)
					assertOnePayday(Profile:GetReadableData(player), f.CurrencyReceipts, 120.25)
					local removed =
						assert(Storage:TryRemoveFromPlatform(player, f.Base.Slot_1, "A"))
					local duplicateSale
					connection = Currency:SubscribeCommitted(function(subject, receipt)
						if receipt.source == "BrainrotSale" then
							duplicateSale = Banked:TryCommitSale(subject, removed, 120)
						end
					end)
					expect(Banked:TryCommitSale(player, removed, 120).ok).to.equal(true)
					connection:Disconnect()
					expect(duplicateSale.code).to.equal("OWNERSHIP_INCONSISTENT")
					assertTrace(f.Save(player), PAYDAY_CASH + 490.75, 4)
					f.Close(player)
				end)
			end
		)

		it("serializes two competing purchases against the actual profile balance", function()
			run(function(f)
				local player = f.Load()
				local context, competitor = f.Open(player)
				f.BeforeGrant = function()
					f.BeforeGrant = nil
					competitor = f.Buy(player, context, "competing-request", "FIXTURE_CARGO_2")
				end
				local winner = f.Buy(player, context, "first-request")
				expect(winner.outcome).to.equal("Accepted")
				expect(competitor.ok).to.equal(false)
				-- Nested mutation rejection invalidates the old request context.
				-- A later legitimate attempt obtains a fresh server-owned context.
				context = f.Open(player)
				expect(f.Buy(player, context, "later-request", "FIXTURE_CARGO_2").code).to.equal(
					"INSUFFICIENT_FUNDS"
				)
				local saved = f.Save(player)
				expect(saved.Economy.Balance).to.equal(250.5)
				expect(saved.Progression.Upgrades.FIXTURE_CARGO_1).to.equal(true)
				expect(saved.Progression.Upgrades.FIXTURE_CARGO_2).to.equal(nil)
				f.Close(player)
			end)
		end)

		it(
			"repeats 100 real load-bind-income-collect-close-unbind cycles without retained base state",
			function()
				local data = fixtureData()
				data.Economy.Balance = 0
				for _, slot in data.Base.Slots do
					slot.accumulatedCash = 0
				end
				run(function(f)
					local priorPlayer, priorHandle
					for iteration = 1, 100 do
						local player = f.Load()
						local storage = Storage:GetStorageForPlayer(player)
						f.Rebind(player)
						expect(storage:GetOccupiedCount()).to.equal(2)
						expect(#f.Base.StoredBrainrots:GetChildren()).to.equal(2)
						if priorPlayer then
							f.StaleRelease(priorPlayer, priorHandle)
							expect(Storage:GetStorageForPlayer(player)).to.equal(storage)
						end
						f.Advance(1)
						expect(Income:TryClaimPlatform(player, f.Base.Name, 1).paid).to.equal(1)
						expect(Currency:GetBalance(player)).to.equal(PAYDAY_CASH + iteration)
						assertOnePayday(
							Profile:GetReadableData(player),
							f.CurrencyReceipts,
							iteration
						)
						priorPlayer, priorHandle = player, f.Handle()
						f.Close(player)
						expect(storage:IsActive()).to.equal(false)
						expect(f.Base:FindFirstChild("StoredBrainrots")).to.equal(nil)
						local durable = f.Backend:GetRecord("player_89701").Data
						expect(durable.Economy.Balance).to.equal(PAYDAY_CASH + iteration)
						expect(durable.Base.Slots["1"].accumulatedCash).to.equal(0)
						expect(durable.Base.Slots["2"].accumulatedCash).to.equal(iteration)
					end
				end, { Data = data, Rate = 1 })
			end
		)
	end)
end
