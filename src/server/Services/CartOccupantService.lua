--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CartModelUtility = require(game.ServerScriptService.Server.Utility.CartModelUtility)

local log = Logger.new("CartOccupantService")

local CartOccupantService = {}

local monitoredCarts: {
	[Model]: RBXScriptConnection?,
} = {}

local function getPlayerFromHumanoid(humanoid: Humanoid): Player?
	local character = humanoid.Parent

	if character == nil or not character:IsA("Model") then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function updateOwnership(cartModel: Model)
	local seat = CartModelUtility.GetDriverSeat(cartModel)

	local root = CartModelUtility.GetRoot(cartModel)

	local humanoid = seat.Occupant

	if humanoid == nil then
		local success, errorMessage = pcall(function()
			root:SetNetworkOwner(nil)
		end)

		if not success then
			log:Warn("Failed to return cart ownership to server: %s", tostring(errorMessage))
		end

		return
	end

	local player = getPlayerFromHumanoid(humanoid)

	if player == nil then
		return
	end

	local ownerUserId = cartModel:GetAttribute("OwnerUserId")

	if ownerUserId ~= player.UserId then
		humanoid.Sit = false

		log:Warn("Rejected non-owner %s from cart owned by %s", player.Name, tostring(ownerUserId))

		return
	end

	local canSet, reason = root:CanSetNetworkOwnership()

	if not canSet then
		log:Warn("Cannot set cart ownership: %s", tostring(reason))

		return
	end

	root:SetNetworkOwner(player)
end

function CartOccupantService:MonitorCart(cartModel: Model)
	if monitoredCarts[cartModel] ~= nil then
		return
	end

	local seat = CartModelUtility.GetDriverSeat(cartModel)

	local connection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		updateOwnership(cartModel)
	end)

	monitoredCarts[cartModel] = connection

	cartModel.Destroying:Connect(function()
		local existing = monitoredCarts[cartModel]

		if existing then
			existing:Disconnect()
			monitoredCarts[cartModel] = nil
		end
	end)

	updateOwnership(cartModel)
end

return CartOccupantService
