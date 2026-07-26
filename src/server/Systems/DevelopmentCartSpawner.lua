--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)

local Ids = require(ReplicatedStorage.Shared.Constants.Ids)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CartService = require(script.Parent.Parent.Services.CartService)

local log = Logger.new("DevelopmentCartSpawner")

local DevelopmentCartSpawner = {}

local function spawnForPlayer(player: Player)
	task.delay(2, function()
		if player.Parent ~= Players then
			return
		end

		local success, result = pcall(function()
			return CartService:SpawnCart(player, Ids.Carts.ScrapChariot, Ids.CartSpawns.Development)
		end)

		if not success then
			log:Warn("Failed to spawn development cart for %s: %s", player.Name, tostring(result))
		end
	end)
end

function DevelopmentCartSpawner:Start()
	if not FeatureFlags.CartEnabled then
		return
	end

	if not Environment.EnableDebugTools then
		return
	end

	for _, player in Players:GetPlayers() do
		spawnForPlayer(player)
	end

	Players.PlayerAdded:Connect(spawnForPlayer)

	log:Info("Automatic development cart spawning enabled")
end

return DevelopmentCartSpawner
