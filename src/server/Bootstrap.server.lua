--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("ServerBootstrap")

local function validateEnvironment()
	assert(
		Environment.Name == "Development"
			or Environment.Name == "Sandbox"
			or Environment.Name == "Production",
		"Invalid environment name"
	)

	if Environment.IsProduction then
		assert(not Environment.EnableDebugTools, "Debug tools must be disabled in Production")
	end
end

local function start()
	validateEnvironment()

	log:Info("Starting server in %s. PlaceId=%d", Environment.Name, game.PlaceId)

	log:Debug(
		"Feature flags loaded: Cart=%s Capture=%s",
		tostring(FeatureFlags.CartEnabled),
		tostring(FeatureFlags.CaptureEnabled)
	)

	log:Info("Server bootstrap complete")
end

start()
