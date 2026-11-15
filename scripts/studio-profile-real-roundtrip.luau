--!nocheck
-- MANUAL, TEST-ONLY real Development storage probe; not mapped by Rojo.
-- This exercises production profile/schema/store paths with a synthetic Player
-- and an isolated freshly required service module. It is NOT a real client,
-- gameplay, reconstruction, disconnect/rejoin, or fresh-server test.
--
-- Only run after deterministic regressions pass, in the server of a Studio Play
-- session for Development place 91958083796436. Do not enable API access here.
-- Set these DataModel attributes explicitly before each invocation:
--   Phase7FRealStorageStage = "CREATE" (first run) or "VERIFY" (later run)
--   Phase7FRealStorageFixtureUserId = -70060051004
--   Phase7FRealStorageRunId = a new, nonempty synthetic run label
-- Use the same fixture user ID/run label for VERIFY. Each invocation clones and
-- requires PlayerDataService afresh and instantiates the actual ProfileStore.
-- CREATE refuses an existing record; it never resets an old record. VERIFY must
-- independently acquire an existing saved fixture. No direct DataStore read,
-- write, deletion, fake backend, clock override, or production singleton reset.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local EXPECTED_PLACE_ID = 91958083796436
local EXPECTED_UNIVERSE_ID = 10548905405
local FIXTURE_USER_ID = -70060051004
local stage = game:GetAttribute("Phase7FRealStorageStage")
local runId = game:GetAttribute("Phase7FRealStorageRunId")

assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio Play server required"
)
assert(
	game.PlaceId == EXPECTED_PLACE_ID and game.GameId == EXPECTED_UNIVERSE_ID,
	"Exact published Development place required"
)
assert(stage == "CREATE" or stage == "VERIFY", "Explicit CREATE or VERIFY stage required")
assert(
	game:GetAttribute("Phase7FRealStorageFixtureUserId") == FIXTURE_USER_ID,
	"Explicit dedicated negative fixture key required"
)
assert(
	type(runId) == "string" and #runId > 0 and #runId <= 128 and runId:match("^[%w_%-]+$"),
	"Explicit synthetic run label required"
)
assert(
	Players:GetPlayerByUserId(FIXTURE_USER_ID) == nil,
	"Fixture key must not identify a connected player"
)

local server = assert(ServerScriptService:FindFirstChild("Server"), "Server source missing")
local services = assert(server:FindFirstChild("Services"), "Service source missing")
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Config = require(server.Config.PlayerDataConfig)
local Store = require(server.Data.PlayerProfileStore)
local Schema = require(server.Data.PlayerProfileSchema)
local Fixtures = require(server.Tests.Support.PlayerProfileFixtures)

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
assert(backend:KeyForUserId(FIXTURE_USER_ID) == "player_-70060051004", "Unexpected fixture key")

local source =
	assert(services:FindFirstChild("PlayerDataService"), "Profile service source missing")
local isolatedModule = source:Clone()
assert(isolatedModule, "Could not clone profile service")
isolatedModule.Name = "Phase7FRealStorageProbe_" .. stage
isolatedModule.Parent = services

local profile
local savedConnection
local currentCloseResult
local confirmedRevision
local attributes = {}
local subject =
	{ UserId = FIXTURE_USER_ID, Name = "Phase7FSyntheticStorageProbe", Parent = Players }
function subject:SetAttribute(name, value)
	attributes[name] = value
end
function subject:Kick()
	error("Synthetic probe cannot be kicked")
end

local ok, result = xpcall(function()
	profile = require(isolatedModule)
	assert(
		profile:Init({ Backend = backend, KickOnFailure = false }),
		"Fresh profile owner initialization failed"
	)
	savedConnection = profile:SubscribeSaveConfirmed(function(player, savedRevision)
		assert(player == subject, "Unexpected profile received save acknowledgement")
		assert(
			confirmedRevision == nil or savedRevision >= confirmedRevision,
			"Confirmed revision regressed"
		)
		confirmedRevision = savedRevision
	end)
	local loaded = profile:LoadPlayerAsync(subject)
	assert(loaded.ok == true, "LOAD_UNCONFIRMED:" .. tostring(loaded.code))
	local loadedRevision = assert(profile:GetDiagnostics(subject)).currentRevision

	local expected = Fixtures.FullProfile()
	expected.SyntheticStorageProbe = {
		kind = "Phase7F_ActualStorage_SyntheticServiceSession",
		fixtureVersion = 1,
		fixtureUserId = FIXTURE_USER_ID,
		runId = runId,
	}
	if stage == "CREATE" then
		assert(loaded.isNew == true, "CREATE_REFUSED_EXISTING_RECORD: source will not be reset")
		local committed = profile:CommitMutation(subject, function(data)
			-- The record was confirmed new by the actual acquisition operation.
			-- Seed only this dedicated disposable fixture through the real boundary.
			for field, value in expected do
				data[field] = Fixtures.Clone(value)
			end
			return true
		end)
		assert(committed.ok == true and committed.committed == true, "FIXTURE_MUTATION_REJECTED")
		assert(
			loadedRevision == 0 and committed.revision == 1,
			"New fixture revision did not advance exactly once"
		)
	else
		assert(loaded.isNew == false, "VERIFY_REFUSED_MISSING_FIXTURE")
	end
	local data = assert(profile:GetReadableData(subject))
	Fixtures.AssertDeepEqual(data, expected)
	assert(Schema.ValidateLoaded(data), "Restored fixture is invalid")
	local diagnostic = assert(profile:GetDiagnostics(subject))
	assert(diagnostic.currentRevision >= 1, "Fixture revision was not restored")
	assert(diagnostic.currentRevision >= loadedRevision, "Profile revision regressed after load")
	if stage == "VERIFY" then
		assert(
			diagnostic.lastConfirmedSavedRevision == diagnostic.currentRevision
				and not diagnostic.dirty,
			"Restored snapshot is not confirmed clean"
		)
	end
	currentCloseResult = profile:ClosePlayerAsync(subject, "Phase7FRealStorage" .. stage)
	assert(currentCloseResult.ok == true, "CLOSE_UNCONFIRMED:" .. tostring(currentCloseResult.code))
	assert(
		confirmedRevision == diagnostic.currentRevision,
		"Final revision was not confirmed by the actual backend"
	)
	assert(
		profile:GetDiagnostics(subject) == nil and profile:GetStatus(subject) == "Closed",
		"Synthetic session retained after close"
	)
	return {
		result = "PASS",
		stage = stage,
		evidence = "actual-storage-synthetic-service-session-only",
		placeId = game.PlaceId,
		universeId = game.GameId,
		environment = Environment.Name,
		buildId = Environment.BuildId,
		store = Config.StoreName,
		scope = "default",
		key = backend:KeyForUserId(FIXTURE_USER_ID),
		schemaVersion = Config.SchemaVersion,
		transportVersion = Config.TransportVersion,
		isNew = loaded.isNew,
		loadedRevision = loadedRevision,
		finalRevision = diagnostic.currentRevision,
		confirmedRevision = confirmedRevision,
		logicalSlotCount = 12,
		ownedIndividualCount = 4,
		allSourceFieldsCompared = true,
		closeCode = currentCloseResult.code,
	}
end, debug.traceback)

-- Release only this isolated probe's already-loaded source if an assertion
-- failed. In particular, CREATE refusal does not clear or replace that source.
if profile and profile:GetStatus(subject) == "Ready" then
	currentCloseResult = profile:ClosePlayerAsync(subject, "Phase7FRealStorageProbeCleanup")
	if not currentCloseResult.ok then
		warn(
			"[PHASE7F_REAL_STORAGE] probe cleanup release unconfirmed: "
				.. tostring(currentCloseResult.code)
		)
	end
end
if savedConnection then
	savedConnection:Disconnect()
end
isolatedModule:Destroy()

if not ok then
	error("[PHASE7F_REAL_STORAGE] FAIL: " .. tostring(result))
end
print("[PHASE7F_REAL_STORAGE] " .. HttpService:JSONEncode(result))
return result
