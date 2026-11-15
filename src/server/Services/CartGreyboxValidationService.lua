--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CartGreybox = require(ReplicatedStorage.Shared.Config.CartGreybox)
local CartGreyboxScenarios = require(ReplicatedStorage.Shared.Config.CartGreyboxScenarios)
local CartGreyboxScenarioIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxScenarioIds)
local CartGreyboxSectionIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxSectionIds)
local CartGreyboxViolationIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxViolationIds)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local CartGreyboxValidationResult =
	require(ReplicatedStorage.Shared.Utility.CartGreyboxValidationResult)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CartGreyboxRouteSystem = require(script.Parent.Parent.Systems.CartGreyboxRouteSystem)
local DevelopmentCartSpawner = require(script.Parent.Parent.Systems.DevelopmentCartSpawner)
local CartGreyboxValidationRuntime =
	require(script.Parent.Parent.Utility.CartGreyboxValidationRuntime)
local CartGreyboxAnalyticsSink = require(script.Parent.Parent.Utility.CartGreyboxAnalyticsSink)
local CartAnalyticsService = require(script.Parent.CartAnalyticsService)
local CartMovementValidationService = require(script.Parent.CartMovementValidationService)
local CartService = require(script.Parent.CartService)
local CartSpawnRegistry = require(script.Parent.CartSpawnRegistry)

type Result = CartGreyboxValidationResult.Result
type Status = CartGreyboxValidationResult.Status
type Severity = CartGreyboxValidationResult.Severity
type Fields = CartGreyboxValidationResult.Fields
type ActiveScenario = CartGreyboxValidationRuntime.ActiveScenario
type SpawnedCartRecord = CartService.SpawnedCartRecord
type AnalyticsEvent = CartGreyboxAnalyticsSink.Event

export type Diagnostics = {
	Started: boolean,
	ActiveScenarioCount: number,
	ResultCount: number,
	RuntimeCartCount: number,
	MovementValidationRecordCount: number,
	AnalyticsRecordCount: number,
	AnalyticsSinkEventCount: number,
}

local log = Logger.new("CartGreyboxValidationService")
local CartGreyboxValidationService = {}

local harnessRuntime = CartGreyboxValidationRuntime.new()
local connections: { RBXScriptConnection } = {}
local started = false

local function isAvailable(): boolean
	return Environment.Name == "Development"
		and Environment.EnableDebugTools
		and RunService:IsStudio()
end

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function clearForCart(record: SpawnedCartRecord)
	harnessRuntime:ClearForCart(record.OwnerUserId, record.Model)
end

local function recordResult(
	scenarioId: string,
	status: Status,
	observed: Fields?,
	expected: Fields?,
	failureCode: string?,
	severity: Severity?,
	notes: string?
): (Result?, string?)
	local succeeded, resultOrError = pcall(function()
		return CartGreyboxValidationResult.Create({
			ScenarioId = scenarioId,
			Status = status,
			Severity = severity,
			Observed = observed,
			Expected = expected,
			FailureCode = failureCode,
			Notes = notes,
			RecordedAt = Workspace:GetServerTimeNow(),
		})
	end)

	if not succeeded then
		return nil, tostring(resultOrError)
	end

	local result = resultOrError :: Result

	harnessRuntime:AddResult(result)

	return result, nil
end

local function recordSetupBlocked(scenarioId: string, failureCode: string, notes: string)
	if CartGreyboxScenarios.ById[scenarioId] == nil then
		return
	end

	local result, resultError = recordResult(
		scenarioId,
		"Blocked",
		{ SetupCompleted = false },
		{ SetupCompleted = true },
		failureCode,
		nil,
		notes
	)

	if result == nil then
		log:Warn(
			"Greybox setup failure could not be recorded Scenario=%s Error=%s",
			scenarioId,
			resultError or "unknown error"
		)
	end
end

local function resolveScenarioSpawnId(player: Player, sectionId: string): (string?, string?)
	if sectionId ~= CartGreyboxSectionIds.MultiplayerOpenArea then
		local spawnId = CartGreyboxRouteSystem:GetSectionSpawnId(sectionId)

		return spawnId,
			if spawnId == nil
				then string.format("section %s has no registered route spawn", sectionId)
				else nil
	end

	local laneSpawnIds = CartGreyboxRouteSystem:GetSectionSpawnIds(sectionId)
	local replaceableCart = CartService:GetCart(player)
	local spawnId = CartGreyboxValidationRuntime.SelectFirstAvailableSpawnId(
		laneSpawnIds,
		function(candidateSpawnId)
			if CartSpawnRegistry:GetById(candidateSpawnId) == nil then
				return true
			end

			return CartSpawnRegistry:IsOccupied(candidateSpawnId, replaceableCart)
		end
	)

	return spawnId,
		if spawnId == nil then "multiplayer greybox spawn lanes are all occupied" else nil
end

function CartGreyboxValidationService:Start(): (boolean, string?)
	if started then
		return true, nil
	end

	if not isAvailable() then
		return false, "greybox validation harness is available only in Development Studio"
	end

	if CartGreyboxRouteSystem:GetRouteFolder() == nil then
		return false, "greybox route must be started before the validation harness"
	end

	CartGreyboxAnalyticsSink.Clear()
	started = true
	table.insert(
		connections,
		CartService.CartDespawned:Connect(function(record)
			clearForCart(record)
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			harnessRuntime:RemovePlayer(player.UserId)
		end)
	)

	log:Info("Phase 1S greybox validation harness ready Scenarios=%d", #CartGreyboxScenarios.All)

	return true, nil
end

function CartGreyboxValidationService:RunScenario(
	player: Player,
	scenarioId: string,
	requestedSectionId: string?
): (boolean, string?)
	if not started then
		return false, "greybox validation harness is not started"
	end

	if player.Parent ~= Players then
		recordSetupBlocked(scenarioId, "GBOX_SETUP_PLAYER", "player is not active")
		return false, "player is not active"
	end

	local sectionId, sectionError =
		CartGreyboxScenarios.ResolveSectionId(scenarioId, requestedSectionId)

	if sectionId == nil then
		recordSetupBlocked(
			scenarioId,
			"GBOX_SETUP_SECTION",
			sectionError or "scenario section could not be resolved"
		)
		return false, sectionError
	end

	local spawnId, spawnError = resolveScenarioSpawnId(player, sectionId)

	if spawnId == nil then
		recordSetupBlocked(
			scenarioId,
			"GBOX_SETUP_SPAWN",
			spawnError or "scenario spawn could not be resolved"
		)
		return false, spawnError
	end

	DevelopmentCartSpawner:CancelPendingSpawn(player)
	harnessRuntime:RemovePlayer(player.UserId)

	local succeeded, cartOrError = pcall(function()
		return CartService:SpawnCart(player, CartGreybox.CartId, spawnId)
	end)

	if not succeeded then
		log:Warn(
			"Greybox scenario setup failed Scenario=%s UserId=%d Error=%s",
			scenarioId,
			player.UserId,
			tostring(cartOrError)
		)
		recordSetupBlocked(scenarioId, "GBOX_SETUP_CART", tostring(cartOrError))

		return false, tostring(cartOrError)
	end

	local cart = cartOrError :: Model

	harnessRuntime:SetActive(player.UserId, {
		ScenarioId = scenarioId,
		SectionId = sectionId,
		SpawnId = spawnId,
		StartedAt = Workspace:GetServerTimeNow(),
		Cart = cart,
	})

	log:Info(
		"Greybox scenario started Scenario=%s Section=%s UserId=%d",
		scenarioId,
		sectionId,
		player.UserId
	)

	return true, nil
end

function CartGreyboxValidationService:ResetScenario(player: Player): (boolean, string?)
	local current = harnessRuntime:GetActive(player.UserId)

	if current == nil then
		return false, "player has no active greybox scenario"
	end

	return self:RunScenario(player, current.ScenarioId, current.SectionId)
end

function CartGreyboxValidationService:CompleteScenario(
	player: Player,
	status: Status,
	observed: Fields?,
	expected: Fields?,
	failureCode: string?,
	severity: Severity?,
	notes: string?
): (Result?, string?)
	local current = harnessRuntime:GetActive(player.UserId)

	if current == nil then
		return nil, "player has no active greybox scenario"
	end

	local result, resultError =
		recordResult(current.ScenarioId, status, observed, expected, failureCode, severity, notes)

	if result == nil then
		return nil, resultError
	end

	harnessRuntime:RemovePlayer(player.UserId)

	log:Info(
		"Greybox scenario completed Scenario=%s Status=%s Severity=%s UserId=%d",
		result.ScenarioId,
		result.Status,
		result.Severity or "none",
		player.UserId
	)

	return result, nil
end

function CartGreyboxValidationService:RecordBlockedScenario(
	scenarioId: string,
	failureCode: string,
	notes: string?,
	expected: Fields?
): (Result?, string?)
	if not started then
		return nil, "greybox validation harness is not started"
	end

	return recordResult(
		scenarioId,
		"Blocked",
		{ SetupCompleted = false },
		expected or { SetupCompleted = true },
		failureCode,
		nil,
		notes
	)
end

function CartGreyboxValidationService:InjectMovementViolation(
	player: Player,
	violationId: string
): (boolean, string?)
	if not started then
		return false, "greybox validation harness is not started"
	end

	if violationId ~= CartGreyboxViolationIds.ExtremeHorizontalVelocity then
		return false, "unsupported greybox movement violation identifier"
	end

	local current = harnessRuntime:GetActive(player.UserId)

	if current == nil or current.ScenarioId ~= CartGreyboxScenarioIds.MovementValidation then
		return false, "movement violation injection requires the active validation scenario"
	end

	local cartRecord = CartService:GetCartRecord(player)

	if cartRecord == nil or cartRecord.Model ~= current.Cart then
		return false, "active scenario cart is stale"
	end

	return CartMovementValidationService:InjectDevelopmentViolation(current.Cart, violationId)
end

function CartGreyboxValidationService:GetAnalyticsEvents(): { AnalyticsEvent }
	return CartGreyboxAnalyticsSink.GetEvents()
end

function CartGreyboxValidationService:ClearAnalyticsEvents()
	CartGreyboxAnalyticsSink.Clear()
end

function CartGreyboxValidationService:GetActiveScenario(player: Player): ActiveScenario?
	return harnessRuntime:GetActive(player.UserId)
end

function CartGreyboxValidationService:GetResults(): { Result }
	return harnessRuntime:GetResults()
end

function CartGreyboxValidationService:ClearResults()
	harnessRuntime:ClearResults()
end

function CartGreyboxValidationService:GetDiagnostics(): Diagnostics
	local diagnostics = harnessRuntime:GetDiagnostics()

	return {
		Started = started,
		ActiveScenarioCount = diagnostics.ActiveScenarioCount,
		ResultCount = diagnostics.ResultCount,
		RuntimeCartCount = #CartService:GetCartRecords(),
		MovementValidationRecordCount = CartMovementValidationService:GetRecordCount(),
		AnalyticsRecordCount = CartAnalyticsService:GetRecordCount(),
		AnalyticsSinkEventCount = CartGreyboxAnalyticsSink.GetEventCount(),
	}
end

function CartGreyboxValidationService:Stop()
	if not started then
		return
	end

	started = false
	disconnectAll()
	harnessRuntime:Reset()
	CartGreyboxAnalyticsSink.Clear()
	log:Info("Phase 1S greybox validation harness stopped")
end

return CartGreyboxValidationService
