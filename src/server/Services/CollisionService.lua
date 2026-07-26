--!strict

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollisionGroups = require(ReplicatedStorage.Shared.Config.CollisionGroups)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("CollisionService")

local CollisionService = {}

local function registerGroup(groupName: string)
	local success, errorMessage = pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)

	if not success then
		local message = tostring(errorMessage)

		if not string.find(message, "already exists") then
			error(errorMessage)
		end
	end
end

local function assignCharacterPart(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end

	instance.CollisionGroup = CollisionGroups.Players
end

local function setupCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		assignCharacterPart(descendant)
	end

	character.DescendantAdded:Connect(assignCharacterPart)
end

function CollisionService:SetModelCollisionGroup(model: Model, groupName: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

function CollisionService:Start()
	registerGroup(CollisionGroups.Carts)
	registerGroup(CollisionGroups.Players)
	registerGroup(CollisionGroups.Brainrots)
	registerGroup(CollisionGroups.CargoVisuals)
	registerGroup(CollisionGroups.FormationVisuals)
	registerGroup(CollisionGroups.Projectiles)

	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.Carts, CollisionGroups.Players, true)

	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.Carts, CollisionGroups.Carts, true)

	PhysicsService:CollisionGroupSetCollidable(
		CollisionGroups.FormationVisuals,
		CollisionGroups.Carts,
		false
	)

	PhysicsService:CollisionGroupSetCollidable(
		CollisionGroups.FormationVisuals,
		CollisionGroups.Players,
		false
	)

	PhysicsService:CollisionGroupSetCollidable(
		CollisionGroups.CargoVisuals,
		CollisionGroups.Carts,
		false
	)

	PhysicsService:CollisionGroupSetCollidable(
		CollisionGroups.CargoVisuals,
		CollisionGroups.Players,
		false
	)

	for _, player in Players:GetPlayers() do
		if player.Character then
			setupCharacter(player.Character)
		end

		player.CharacterAdded:Connect(setupCharacter)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(setupCharacter)
	end)

	log:Info("Collision groups configured")
end

return CollisionService
