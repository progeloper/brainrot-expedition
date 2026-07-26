--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local Ids = require(ReplicatedStorage.Shared.Constants.Ids)

local ConfigValidator = require(ReplicatedStorage.Shared.Validation.ConfigValidator)

local AssetValidationService = require(script.Parent.Services.AssetValidationService)

local CollisionService = require(script.Parent.Services.CollisionService)

local CartSpawnRegistry = require(script.Parent.Services.CartSpawnRegistry)

local CartService = require(script.Parent.Services.CartService)

local DevelopmentCartSpawner = require(script.Parent.Systems.DevelopmentCartSpawner)

local log = Logger.new("ServerBootstrap")

local function validateEnvironment()
	assert(
		Environment.Name == "Development"
			or Environment.Name == "Sandbox"
			or Environment.Name == "Production",
		"Invalid environment name."
	)

	if Environment.IsProduction then
		assert(Environment.EnableDebugTools == false, "Debug tools must be disabled in production.")
	end

	ConfigValidator.AssertUniqueIds("Brainrots", Ids.Brainrots)

	ConfigValidator.AssertUniqueIds("Carts", Ids.Carts)

	ConfigValidator.AssertUniqueIds("Harpoons", Ids.Harpoons)

	ConfigValidator.AssertUniqueIds("Gadgets", Ids.Gadgets)

	ConfigValidator.AssertUniqueIds("Zones", Ids.Zones)

	ConfigValidator.AssertUniqueIds("CartSpawns", Ids.CartSpawns)
end

local function start()
	validateEnvironment()

	log:Info("Starting server in %s. PlaceId=%d", Environment.Name, game.PlaceId)

	log:Debug(
		"Feature flags loaded: Cart=%s Capture=%s",
		tostring(FeatureFlags.CartEnabled),
		tostring(FeatureFlags.CaptureEnabled)
	)

	AssetValidationService:Start()

	CollisionService:Start()
	CartSpawnRegistry:Start()
	CartService:Start()
	DevelopmentCartSpawner:Start()
	log:Info("Server bootstrap complete")
end

start()
