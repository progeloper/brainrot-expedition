--!nocheck
-- MANUAL, TEST-ONLY; not mapped by Rojo. Install only in a disposable Studio
-- Development Play server with the ORIGINAL Server.Bootstrap disabled.
-- Install Phase7G1GameplayObserver beside Bootstrap first and wait for its
-- ObserverReady attribute. This script then initializes the existing singleton
-- profile owner and enables the unchanged Bootstrap. It never clones a Player
-- or gameplay service, seeds data, resets a profile, or starts another owner.
--
-- Required attributes on THIS Script (and matching observer):
--   RunOptIn = true
--   RunId = a unique bounded diagnostic label (never saved in the profile)
--   Cohort = "Fresh", "PartialReturning", or "DevelopedReturning"
--   Stage = "INITIAL" or "REJOIN"
-- INITIAL requires the exact approved starting shape and authoritative origin.
-- REJOIN requires an existing record but accepts progress earned in earlier play.
-- Switch cohorts only after normal confirmed close and a NEW Play server.
-- The mapping is immutable for this server lifetime. Remove both temporary
-- scripts after testing; never save/publish them into the experience.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local runId = script:GetAttribute("RunId")
local cohort = script:GetAttribute("Cohort")
local stage = script:GetAttribute("Stage")
local fixtureIds = table.freeze({
	Fresh = -70070052001,
	PartialReturning = -70070051002,
	DevelopedReturning = -70070051003,
})

assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio server required"
)
assert(
	game.PlaceId == 91958083796436 and game.GameId == 10548905405,
	"Exact Development place required"
)
assert(script:GetAttribute("RunOptIn") == true, "Explicit one-shot opt-in required")
assert(
	type(runId) == "string" and #runId > 0 and #runId <= 64 and runId:match("^[%w_%-]+$"),
	"Invalid run label"
)
assert(fixtureIds[cohort] ~= nil, "Unsupported cohort")
assert(stage == "INITIAL" or stage == "REJOIN", "Explicit INITIAL or REJOIN stage required")

local server = assert(ServerScriptService:FindFirstChild("Server"), "Server source missing")
local bootstrap = assert(server:FindFirstChild("Bootstrap"), "Original Bootstrap missing")
assert(
	bootstrap:IsA("Script") and bootstrap.Enabled == false,
	"Bootstrap must be disabled BEFORE Play"
)
local observer =
	assert(server:FindFirstChild("Phase7G1GameplayObserver"), "Install read-only observer first")
assert(observer:IsA("Script") and observer.Enabled, "Observer must be enabled")
assert(
	observer:GetAttribute("ObserverReady") == true,
	"Observer must be installed before profile loading"
)
assert(
	observer:GetAttribute("RunId") == runId and observer:GetAttribute("Cohort") == cohort,
	"Observer run mismatch"
)
assert(observer:GetAttribute("Stage") == stage, "Observer stage mismatch")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Config = require(server.Config.PlayerDataConfig)
local Store = require(server.Data.PlayerProfileStore)
local Profile = require(server.Services.PlayerDataService)
local Schema = require(server.Data.PlayerProfileSchema)
local Source = require(server.Tests.Support.PlayerProfileFixtures)
local Cohorts = require(server.Tests.Support.ProgressionProfileFixtures)

assert(Environment.Name == "Development" and not Environment.IsProduction, "Development only")
assert(
	Environment.EnableDataSaving == true and Environment.DataStorePrefix == "dev_v2",
	"Development saving required"
)
assert(
	Config.StoreName == "dev_v2_player_profiles_v1" and Config.StoreScope == nil,
	"Unexpected store identity"
)
assert(
	Config.KeyPrefix == "player_" and Config.SchemaVersion == 2 and Config.TransportVersion == 1,
	"Unexpected schema/key contract"
)

local backend = Store.new() -- the same production adapter and configured store
assert(backend:IsAvailable(), "Actual Development backend unavailable; no fallback")
local fixtureKey = backend:KeyForUserId(fixtureIds[cohort])
assert(fixtureKey == "player_" .. tostring(fixtureIds[cohort]), "Unexpected disposable key")
assert(
	Players:GetPlayerByUserId(fixtureIds[cohort]) == nil,
	"Disposable key identifies a connected player"
)

-- Preserve Bootstrap's existing startup contract while waiting for a real client.
-- No character/world readiness is fabricated by this helper.
Players.CharacterAutoLoads = false
script:SetAttribute("RunOptIn", false)
script:SetAttribute("Status", "WaitingForActualPlayer")
local connected = Players:GetPlayers()
assert(#connected <= 1, "Exactly one actual Studio client is supported")
local player = connected[1] or Players.PlayerAdded:Wait()
assert(
	typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players,
	"Actual connected Player required"
)
assert(#Players:GetPlayers() == 1, "Multiple clients are not supported by this cohort helper")
assert(Profile:GetStatus(player) == "Closed", "Refusing an already loaded normal profile")
local actualUserId = player.UserId
local sourceKey = backend:KeyForUserId(actualUserId)
assert(sourceKey ~= fixtureKey, "Actual account must not be the synthetic fixture identity")
observer:SetAttribute("ExpectedUserId", actualUserId)

local expected = if stage == "INITIAL" then Cohorts.Create(cohort) else nil
local admitted = false
local rejected = false
local initialVerified = false
local wrapped = {}
local transportCalls = { Acquire = 0, Save = 0, Renew = 0, Release = 0 }
for method in transportCalls do
	script:SetAttribute("Backend" .. method .. "Calls", 0)
end
script:SetAttribute("BackendNormalAccountForwarded", 0)

local function countTransport(method)
	transportCalls[method] += 1
	script:SetAttribute("Backend" .. method .. "Calls", transportCalls[method])
end

local function refusal(code)
	return { ok = false, code = code }
end

local function permits(key)
	return key == sourceKey and not rejected
end

local function announce(status, fields)
	script:SetAttribute("Status", status)
	local message = fields or {}
	message.status = status
	message.runId = runId
	message.cohort = cohort
	message.stage = stage
	message.fixtureKey = fixtureKey
	print("[PHASE7G1_GAMEPLAY_COHORT] " .. HttpService:JSONEncode(message))
end

function wrapped:IsAvailable()
	return backend:IsAvailable()
end

function wrapped:KeyForUserId(userId)
	assert(userId == actualUserId, "Unmapped actual player")
	return fixtureKey
end

function wrapped:Acquire(key, ownerToken, leaseDuration)
	if not permits(key) then
		return refusal("COHORT_UNMAPPED_PLAYER")
	end
	countTransport("Acquire")
	local result = backend:Acquire(fixtureKey, ownerToken, leaseDuration)
	if not result.ok then
		return result -- preserve actual backend uncertainty/retry semantics
	end
	if not initialVerified then
		local originMatches = if stage == "INITIAL" and cohort == "Fresh"
			then result.isNew == true
			else result.isNew == false
		local shapeMatches = Schema.ValidateLoaded(result.data)
		if expected then
			shapeMatches = shapeMatches and pcall(Source.AssertDeepEqual, result.data, expected)
		end
		if not originMatches or not shapeMatches then
			rejected = true
			-- Release exactly what was acquired; never overwrite with the fixture,
			-- erase an existing profile, or expose mismatched data as PlayerDataReady.
			countTransport("Release")
			local released = backend:Release(
				fixtureKey,
				ownerToken,
				"cohort-refused:" .. HttpService:GenerateGUID(false),
				result.lastRevision or 0,
				result.data
			)
			announce("RefusedBeforeReady", {
				code = if not originMatches
					then "COHORT_ORIGIN_MISMATCH"
					else "COHORT_SOURCE_MISMATCH",
				releaseConfirmed = released.ok == true,
			})
			return refusal(
				if not originMatches then "COHORT_ORIGIN_MISMATCH" else "COHORT_SOURCE_MISMATCH"
			)
		end
		initialVerified = true
	end
	admitted = true
	announce("ActualProfileAcquired", {
		profileOrigin = if result.isNew then "ConfirmedNew" else "Existing",
		loadedRevision = result.lastRevision,
	})
	return result
end

function wrapped:Save(key, ownerToken, operationId, revision, snapshot, leaseDuration)
	if not permits(key) or not admitted then
		return refusal("COHORT_UNMAPPED_PLAYER")
	end
	countTransport("Save")
	return backend:Save(fixtureKey, ownerToken, operationId, revision, snapshot, leaseDuration)
end

function wrapped:Renew(key, ownerToken, operationId, leaseDuration)
	if not permits(key) or not admitted then
		return refusal("COHORT_UNMAPPED_PLAYER")
	end
	countTransport("Renew")
	return backend:Renew(fixtureKey, ownerToken, operationId, leaseDuration)
end

function wrapped:Release(key, ownerToken, operationId, revision, snapshot)
	if not permits(key) or not admitted then
		return refusal("COHORT_UNMAPPED_PLAYER")
	end
	countTransport("Release")
	return backend:Release(fixtureKey, ownerToken, operationId, revision, snapshot)
end

-- Init returns false if normal startup has already happened. Never reset it.
assert(
	Profile:Init({ Backend = table.freeze(wrapped) }),
	"Profile owner already started; refusing reroute"
)
announce("AdapterInstalled", { evidence = "ACTUAL_PLAYER_DISPOSABLE_DEVELOPMENT_GAMEPLAY" })
-- Normal Bootstrap owns all loading, gameplay, saving and cleanup from here.
-- Other players' keys are rejected; none are forwarded to the real backend.
bootstrap.Enabled = true
