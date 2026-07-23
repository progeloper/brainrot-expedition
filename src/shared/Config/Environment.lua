--!strict

export type EnvironmentName = "Development" | "Sandbox" | "Production"

export type EnvironmentConfig = {
	Name: EnvironmentName,
	BuildId: string,
	IsProduction: boolean,
	EnableDataSaving: boolean,
	DataStorePrefix: string,
	EnableDebugTools: boolean,
	EnableVerboseLogging: boolean,
}

local PLACE_ENVIRONMENTS: { [number]: EnvironmentName } = {
	-- Replace these with your real place IDs.
	[91958083796436] = "Development",
	[118579708727733] = "Sandbox",
	[101897217391241] = "Production",
}

local function isEnvironmentName(value: unknown): boolean
	return value == "Development" or value == "Sandbox" or value == "Production"
end

local function getEnvironmentName(placeId: number): EnvironmentName
	local value = PLACE_ENVIRONMENTS[placeId]

	if value == nil then
		warn(string.format("Unknown PlaceId %d; defaulting to Development", placeId))

		return "Development"
	end

	assert(isEnvironmentName(value), "Invalid environment name configured")

	return value :: EnvironmentName
end

local function buildConfig(environmentName: EnvironmentName): EnvironmentConfig
	if environmentName == "Production" then
		return {
			Name = "Production",
			BuildId = "2026.07.23.1",
			IsProduction = true,
			EnableDataSaving = true,
			DataStorePrefix = "prod_v2",
			EnableDebugTools = false,
			EnableVerboseLogging = false,
		}
	elseif environmentName == "Sandbox" then
		return {
			Name = "Sandbox",
			BuildId = "2026.07.23.1",
			IsProduction = false,
			EnableDataSaving = true,
			DataStorePrefix = "sandbox_v2",
			EnableDebugTools = true,
			EnableVerboseLogging = true,
		}
	else
		return {
			Name = "Development",
			BuildId = "2026.07.23.1",
			IsProduction = false,
			EnableDataSaving = false,
			DataStorePrefix = "dev_v2",
			EnableDebugTools = true,
			EnableVerboseLogging = true,
		}
	end
end

local environmentName: EnvironmentName = getEnvironmentName(game.PlaceId)
local Environment: EnvironmentConfig = buildConfig(environmentName)

return table.freeze(Environment)
