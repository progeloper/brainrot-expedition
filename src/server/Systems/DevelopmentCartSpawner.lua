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
local playerAddedConnection: RBXScriptConnection? = nil
local pendingRevisionByUserId: { [number]: number } = {}
local nextRevision = 0
local started = false

local function spawnForPlayer(player: Player)
	nextRevision += 1

	local revision = nextRevision

	pendingRevisionByUserId[player.UserId] = revision

	task.delay(2, function()
		if not started or pendingRevisionByUserId[player.UserId] ~= revision then
			return
		end

		pendingRevisionByUserId[player.UserId] = nil

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
	if started then
		return
	end

	if not FeatureFlags.CartEnabled then
		return
	end

	if not Environment.EnableDebugTools then
		return
	end

	started = true

	for _, player in Players:GetPlayers() do
		spawnForPlayer(player)
	end

	playerAddedConnection = Players.PlayerAdded:Connect(spawnForPlayer)

	log:Info("Automatic development cart spawning enabled")
end

function DevelopmentCartSpawner:CancelPendingSpawn(player: Player)
	pendingRevisionByUserId[player.UserId] = nil
end

function DevelopmentCartSpawner:Stop()
	if not started then
		return
	end

	started = false

	if playerAddedConnection ~= nil then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end

	table.clear(pendingRevisionByUserId)
	log:Info("Automatic development cart spawning stopped")
end

return DevelopmentCartSpawner
