--!nocheck
-- MANUAL, TEST-ONLY; deliberately not mapped by Rojo.
-- Actual Development backend + independently required profile owners, using
-- four dedicated disposable negative keys. This is synthetic storage/cohort
-- baseline evidence, NOT live-world restoration, client pacing, or a playtest.
-- Run only after deterministic checks pass; this script never enables API access.
-- Explicit DataModel attributes required for EACH invocation:
--   Phase7G1RealCohortRun = true
--   Phase7G1RealCohortStage = "CREATE" or "VERIFY"
--   Phase7G1RealCohortRunId = a bounded synthetic run label (not saved)
-- CREATE refuses any existing record and seeds through CommitMutation only.
-- VERIFY independently acquires all four records, compares every source field,
-- and observes the loaded baseline through a fresh actual MetricsService.
-- No profile diagnostics/markers, direct DataStore calls, deletion, fallback,
-- gameplay grants, world construction, forced readiness, or production reset.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local EXPECTED_PLACE_ID = 91958083796436
local EXPECTED_UNIVERSE_ID = 10548905405
local COHORTS = {
	{ Name = "Fresh", UserId = -70070051001 },
	{ Name = "PartialReturning", UserId = -70070051002 },
	{ Name = "DevelopedReturning", UserId = -70070051003 },
	{ Name = "StartingCashStock", UserId = -70070051004 },
}
local stage = game:GetAttribute("Phase7G1RealCohortStage")
local runId = game:GetAttribute("Phase7G1RealCohortRunId")

assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio Play server required"
)
assert(
	game.PlaceId == EXPECTED_PLACE_ID and game.GameId == EXPECTED_UNIVERSE_ID,
	"Exact published Development place required"
)
assert(game:GetAttribute("Phase7G1RealCohortRun") == true, "Explicit one-shot opt-in required")
assert(stage == "CREATE" or stage == "VERIFY", "Explicit CREATE or VERIFY stage required")
assert(
	type(runId) == "string" and #runId > 0 and #runId <= 128 and runId:match("^[%w_%-]+$"),
	"Explicit synthetic run label required"
)

local server = assert(ServerScriptService:FindFirstChild("Server"), "Server source missing")
local services = assert(server:FindFirstChild("Services"), "Service source missing")
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Config = require(server.Config.PlayerDataConfig)
local Store = require(server.Data.PlayerProfileStore)
local Schema = require(server.Data.PlayerProfileSchema)
local Source = require(server.Tests.Support.PlayerProfileFixtures)
local CohortFixtures = require(server.Tests.Support.ProgressionProfileFixtures)

assert(
	Environment.Name == "Development" and not Environment.IsProduction,
	"Development environment required"
)
assert(
	Environment.EnableDataSaving == true and Environment.DataStorePrefix == "dev_v2",
	"Development saving must already be enabled"
)
assert(
	Config.StoreName == "dev_v2_player_profiles_v1" and Config.StoreScope == nil,
	"Unexpected DataStore name/scope"
)
assert(
	Config.KeyPrefix == "player_" and Config.SchemaVersion == 2 and Config.TransportVersion == 1,
	"Unexpected persistence contract"
)

local backend = Store.new()
assert(backend:IsAvailable(), "Actual backend unavailable; no fallback allowed")
for _, cohort in COHORTS do
	assert(
		Players:GetPlayerByUserId(cohort.UserId) == nil,
		"Fixture key identifies a connected player"
	)
	assert(
		backend:KeyForUserId(cohort.UserId) == "player_" .. tostring(cohort.UserId),
		"Unexpected dedicated fixture key"
	)
end
game:SetAttribute("Phase7G1RealCohortRun", false) -- consume only this explicit test opt-in

local function inertSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end

local function inertMethodObserver()
	return {
		SubscribeCommitted = function()
			return { Disconnect = function() end }
		end,
	}
end

local function cloneService(name, cohort)
	local source = assert(services:FindFirstChild(name), name .. " source missing")
	local cloned = assert(source:Clone(), "Could not clone " .. name)
	cloned.Name = "Phase7G1CohortProbe_" .. cohort .. "_" .. name
	cloned.Parent = services
	return cloned
end

local function baselineExpectation(data)
	local occupied, count, cash, rate = 0, 0, 0, 0
	for _ in data.Collection.BrainrotInstances do
		count += 1
	end
	for _, slot in data.Base.Slots do
		cash += slot.accumulatedCash
		if slot.brainrotId then
			occupied += 1
			local individual = assert(
				data.Collection.BrainrotInstances[slot.brainrotId],
				"Fixture slot references no owned individual"
			)
			rate += assert(Catalog.GetCashPerSecond(individual.speciesId))
		end
	end
	return {
		wallet = data.Economy.Balance,
		settledPlatformCash = cash,
		occupiedSlotCount = occupied,
		bankedIndividualCount = count,
		passiveIncomeRate = rate,
	}
end

local function runCohort(cohort)
	local profileModule = cloneService("PlayerDataService", cohort.Name)
	local metricsModule, profile, metrics, savedConnection
	local confirmedRevision, closeResult
	local attributes = {}
	local subject =
		{ UserId = cohort.UserId, Name = "Phase7G1Synthetic_" .. cohort.Name, Parent = Players }
	function subject:SetAttribute(name, value)
		attributes[name] = value
	end
	function subject:Kick()
		error("Synthetic probe cannot be kicked")
	end

	local ok, result = xpcall(function()
		profile = require(profileModule)
		assert(
			profile:Init({ Backend = backend, KickOnFailure = false }),
			"Fresh profile Init failed"
		)
		savedConnection = profile:SubscribeSaveConfirmed(function(player, revision)
			assert(player == subject, "Unexpected save acknowledgement subject")
			assert(
				confirmedRevision == nil or revision >= confirmedRevision,
				"Confirmation regressed"
			)
			confirmedRevision = revision
		end)
		if stage == "VERIFY" then
			metricsModule = cloneService("ProgressionMetricsService", cohort.Name)
			metrics = require(metricsModule)
			local playersBoundary = { PlayerAdded = inertSignal(), PlayerRemoving = inertSignal() }
			function playersBoundary:GetPlayers()
				return {}
			end
			local worldBoundary = {
				SubscribeReady = function()
					return { Disconnect = function() end }
				end,
				IsReady = function()
					return false
				end,
			}
			local upgradesBoundary = {
				SubscribeObservations = function()
					return { Disconnect = function() end }
				end,
				GetMeasurementOffers = function()
					return {}
				end,
			}
			local storageBoundary = {
				GetStorageForPlayer = function()
					return nil
				end,
			}
			assert(
				metrics:Start({
					Players = playersBoundary,
					Profile = profile,
					WorldLifecycle = worldBoundary,
					Upgrade = upgradesBoundary,
					Storage = storageBoundary,
					Catalog = Catalog,
					Currency = inertMethodObserver(),
					Income = inertMethodObserver(),
					Capture = inertMethodObserver(),
					Interaction = inertMethodObserver(),
					Sale = inertMethodObserver(),
					Environment = Environment,
					ConnectScheduler = false,
					Regions = false,
					LogReports = false,
					Now = function()
						return Workspace:GetServerTimeNow()
					end,
					GenerateObservationId = function()
						return runId .. ":" .. cohort.Name
					end,
				}),
				"Fresh metrics observer initialization failed"
			)
		end

		local expected = CohortFixtures.Create(cohort.Name)
		local loaded = profile:LoadPlayerAsync(subject)
		assert(loaded.ok == true, "LOAD_UNCONFIRMED:" .. tostring(loaded.code))
		local loadedRevision = assert(profile:GetDiagnostics(subject)).currentRevision
		if stage == "CREATE" then
			assert(
				loaded.isNew == true,
				"CREATE_REFUSED_EXISTING_RECORD: never reset an existing source"
			)
			local committed = profile:CommitMutation(subject, function(data)
				-- Confirmed-new dedicated key only. Copy valid source fields, not a
				-- diagnostic marker or synthetic history into the saved schema.
				for field, value in expected do
					data[field] = Source.Clone(value)
				end
				return true
			end)
			assert(committed.ok and committed.committed, "FIXTURE_MUTATION_REJECTED")
			assert(
				loadedRevision == 0 and committed.revision == 1,
				"Unexpected new-profile revision"
			)
		else
			assert(loaded.isNew == false, "VERIFY_REFUSED_MISSING_FIXTURE")
		end
		local data = assert(profile:GetReadableData(subject))
		Source.AssertDeepEqual(data, expected)
		assert(Schema.ValidateLoaded(data), "Invalid source fixture")
		local beforeReport = Source.Clone(data)
		local diagnostic = assert(profile:GetDiagnostics(subject))
		assert(diagnostic.currentRevision >= 1, "Seeded fixture revision was not restored")
		local measurement
		if metrics then
			assert(
				not diagnostic.dirty
					and diagnostic.lastConfirmedSavedRevision == diagnostic.currentRevision,
				"Fresh acquisition must be confirmed clean"
			)
			measurement = assert(metrics:GetReport(subject), "Loaded baseline was not observed")
			local baseline = baselineExpectation(expected)
			for field, value in baseline do
				assert(measurement.startingState[field] == value, "Baseline mismatch: " .. field)
			end
			assert(
				measurement.session.profileOrigin == "Existing",
				"Existing empty profile misclassified"
			)
			assert(
				measurement.session.clocks.worldReadyAt == nil,
				"Storage probe cannot claim world readiness"
			)
			assert(
				measurement.economy.platformIncomeGenerated == 0,
				"Restored stock counted as production"
			)
			assert(measurement.economy.platformCashCollected == 0, "No collection occurred")
			assert(
				measurement.economy.walletDebits == 0 and measurement.economy.reconciled,
				"Read-only baseline did not reconcile"
			)
			metrics:GetReport(subject)
			Source.AssertDeepEqual(profile:GetReadableData(subject), beforeReport)
			assert(
				profile:GetDiagnostics(subject).currentRevision == diagnostic.currentRevision,
				"Report changed profile revision"
			)
		end
		closeResult = profile:ClosePlayerAsync(subject, "Phase7G1RealCohort" .. stage)
		assert(closeResult.ok == true, "CLOSE_UNCONFIRMED:" .. tostring(closeResult.code))
		assert(confirmedRevision == diagnostic.currentRevision, "Final revision not confirmed")
		assert(profile:GetDiagnostics(subject) == nil, "Profile retained after release")
		if metrics then
			local completed = metrics:GetCompletedReports()
			assert(
				#completed == 1 and completed[1].persistence.closeStatus == "Confirmed",
				"Detached report missed final close acknowledgement"
			)
			assert(
				metrics:GetDiagnostics().active == 0 and metrics:GetDiagnostics().detached == 0,
				"Metrics retained the synthetic player"
			)
			measurement = completed[1]
		end
		return {
			result = "PASS",
			cohort = cohort.Name,
			stage = stage,
			fixtureKey = backend:KeyForUserId(cohort.UserId),
			evidence = "ACTUAL_DEVELOPMENT_STORAGE_SYNTHETIC_COHORT_BASELINE_ONLY",
			controlledFixture = true,
			profileOriginFromBackend = if loaded.isNew then "ConfirmedNew" else "Existing",
			loadedRevision = loadedRevision,
			finalRevision = diagnostic.currentRevision,
			confirmedRevision = confirmedRevision,
			allSourceFieldsCompared = true,
			baseline = baselineExpectation(expected),
			metricsReport = measurement,
			worldReady = false,
			playablePacingObserved = false,
			closeCode = closeResult.code,
		}
	end, debug.traceback)

	-- Never reset on refusal/failure. Release only this isolated owner's exact
	-- currently-loaded source; an unconfirmed result stays unconfirmed.
	if profile and profile:GetStatus(subject) == "Ready" then
		closeResult = profile:ClosePlayerAsync(subject, "Phase7G1CohortProbeCleanup")
		if not closeResult.ok then
			warn("[PHASE7G1_REAL_COHORT] cleanup unconfirmed: " .. tostring(closeResult.code))
		end
	end
	if savedConnection then
		savedConnection:Disconnect()
	end
	if metrics then
		metrics:Stop()
	end
	if metricsModule then
		metricsModule:Destroy()
	end
	profileModule:Destroy()
	assert(ok, "[PHASE7G1_REAL_COHORT] " .. cohort.Name .. " FAIL: " .. tostring(result))
	print("[PHASE7G1_REAL_COHORT] " .. HttpService:JSONEncode(result))
	return result
end

local results = {}
for _, cohort in COHORTS do
	table.insert(results, runCohort(cohort))
end
return {
	result = "PASS",
	stage = stage,
	runId = runId,
	cohorts = results,
	placeId = game.PlaceId,
	universeId = game.GameId,
	environment = Environment.Name,
	buildId = Environment.BuildId,
	store = Config.StoreName,
	scope = "default",
	schemaVersion = Config.SchemaVersion,
	transportVersion = Config.TransportVersion,
	evidence = "SYNTHETIC_STORAGE_COHORT_BASELINES_NOT_PLAYABLE_SESSION_PACING",
}
