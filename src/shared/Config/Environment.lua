--!strict

local RunService = game:GetService("RunService")
local Deployment = require(script.Parent.Deployment)
local isMain = game.PlaceId == Deployment.MainStartPlaceId and game.GameId == Deployment.MainUniverseId

export type EnvironmentName = "Development" | "Sandbox" | "Production"

export type EnvironmentConfig = {
	Name: EnvironmentName,
	BuildId: string,
	IsProduction: boolean,
	EnableDataSaving: boolean,
	DataStorePrefix: string,
	EnableDebugTools: boolean,
	EnableGreyboxValidation: boolean,
	EnableVerboseLogging: boolean,
	BrainrotDepositDiagnosticsEnabled: boolean,
	MainGameplayEnabled: boolean,
}

local PLACE_ENVIRONMENTS: { [number]: EnvironmentName } = {
	-- Legacy additional places retain their existing classification.
	-- The single active Main target is resolved from Deployment above.
	[118579708727733] = "Sandbox",
	[101897217391241] = "Production",
}

local function isEnvironmentName(value: unknown): boolean
	return value == "Development" or value == "Sandbox" or value == "Production"
end

local function getEnvironmentName(placeId: number): EnvironmentName
	if isMain then
		return "Production"
	end
	local value = PLACE_ENVIRONMENTS[placeId]

	if value == nil then
		if RunService:IsStudio() then
			warn(string.format("Unknown PlaceId %d in Studio; defaulting to Development", placeId))

			return "Development"
		end

		error(
			string.format(
				"Unknown PlaceId %d outside Studio; refusing to select an environment",
				placeId
			),
			2
		)
	end

	assert(isEnvironmentName(value), "Invalid environment name configured")

	return value :: EnvironmentName
end

local function buildConfig(environmentName: EnvironmentName): EnvironmentConfig
	if environmentName == "Production" then
		return {
			Name = "Production",
			MainGameplayEnabled = false,
			BuildId = "2026.07.23.1",
			IsProduction = true,
			EnableDataSaving = true,
			DataStorePrefix = "prod_v2",
			EnableDebugTools = false,
			EnableGreyboxValidation = false,
			EnableVerboseLogging = false,
			BrainrotDepositDiagnosticsEnabled = false,
		}
	elseif environmentName == "Sandbox" then
		return {
			Name = "Sandbox",
			MainGameplayEnabled = false,
			BuildId = "2026.07.23.1",
			IsProduction = false,
			EnableDataSaving = true,
			BrainrotDepositDiagnosticsEnabled = false,
			DataStorePrefix = "sandbox_v2",
			EnableDebugTools = true,
			EnableGreyboxValidation = false,
			EnableVerboseLogging = true,
		}
	else
		return {
			Name = "Development",
			MainGameplayEnabled = false,
			BuildId = "2026.07.23.1",
			IsProduction = false,
			-- Development uses its isolated dev_v2 store for the required real
			-- save/rejoin gates. Production remains a separate explicit promotion.
			EnableDataSaving = true,
			-- Temporary Phase 5C/5D trace; set false to disable. Never enabled outside Studio.
			BrainrotDepositDiagnosticsEnabled = false, -- hot transaction tracing disabled after baseline profiling
			DataStorePrefix = "dev_v2",
			EnableDebugTools = true,
			EnableGreyboxValidation = false,
			EnableVerboseLogging = true,
		}
	end
end

local environmentName: EnvironmentName = getEnvironmentName(game.PlaceId)
local Environment: EnvironmentConfig = buildConfig(environmentName)
Environment.MainGameplayEnabled = isMain and Deployment.Phase14Enabled
if isMain then
	Environment.BuildId = Deployment.ReleaseId
	Environment.DataStorePrefix = Deployment.MainDataStorePrefix
end

return table.freeze(Environment)
