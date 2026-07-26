--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)

local Ids = require(ReplicatedStorage.Shared.Constants.Ids)

local Carts = require(ReplicatedStorage.Shared.Config.Carts)

local CollisionGroups = require(ReplicatedStorage.Shared.Config.CollisionGroups)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local RuntimeFolders = require(script.Parent.Parent.Utility.RuntimeFolders)

local CartModelUtility = require(script.Parent.Parent.Utility.CartModelUtility)

local CartAssetService = require(script.Parent.CartAssetService)

local CartSpawnRegistry = require(script.Parent.CartSpawnRegistry)

type CartSpawnRecord = CartSpawnRegistry.CartSpawnRecord

local CollisionService = require(script.Parent.CollisionService)

local CartOccupantService = require(script.Parent:WaitForChild("CartOccupantService"))

local Workspace = game:GetService("Workspace")

local log = Logger.new("CartService")

export type SpawnedCartRecord = {
	OwnerUserId: number,
	CartId: string,
	SpawnId: string,
	Model: Model,
	SpawnCFrame: CFrame,
	CreatedAt: number,
}

export type CartService = {
	GetCart: (self: CartService, player: Player) -> Model?,

	DespawnCart: (self: CartService, player: Player, reason: string?) -> (),

	SpawnCart: (
		self: CartService,
		player: Player,
		cartId: string?,
		spawnId: string?
	) -> Model,

	ResetCart: (self: CartService, player: Player) -> boolean,

	Start: (self: CartService) -> (),
}

local CartService: CartService = {} :: CartService

local cartsByUserId: {
	[number]: SpawnedCartRecord,
} = {}

local function getCartRecord(player: Player): SpawnedCartRecord?
	return cartsByUserId[player.UserId]
end

local function clearNetworkOwnership(cartModel: Model)
	local root = CartModelUtility.GetRoot(cartModel)

	local success, errorMessage = pcall(function()
		CartModelUtility.SetRootAnchoredOnly(cartModel, false)

		CartOccupantService:MonitorCart(cartModel)
		root:SetNetworkOwner(nil)
	end)

	if not success then
		log:Warn("Failed to clear network owner: %s", tostring(errorMessage))
	end
end

local function setNetworkOwner(cartModel: Model, player: Player)
	local root = CartModelUtility.GetRoot(cartModel)

	local canSet, reason = root:CanSetNetworkOwnership()

	if not canSet then
		log:Warn("Cannot set network owner for %s: %s", cartModel.Name, tostring(reason))

		return
	end

	root:SetNetworkOwner(player)
end

local function prepareClone(cartModel: Model, player: Player, cartId: string, spawnId: string)
	cartModel.Name = string.format("Cart_%d", player.UserId)

	cartModel:SetAttribute("OwnerUserId", player.UserId)

	cartModel:SetAttribute("CartId", cartId)

	cartModel:SetAttribute("SpawnId", spawnId)

	cartModel:SetAttribute("SpawnedAt", Workspace:GetServerTimeNow())

	cartModel:SetAttribute("RuntimeCart", true)
end

function CartService:GetCart(player: Player): Model?
	local record = getCartRecord(player)

	if record == nil then
		return nil
	end

	if record.Model.Parent == nil then
		cartsByUserId[player.UserId] = nil
		return nil
	end

	return record.Model
end

function CartService:DespawnCart(player: Player, reason: string?)
	local record = getCartRecord(player)

	if record == nil then
		return
	end

	cartsByUserId[player.UserId] = nil

	if record.Model.Parent ~= nil then
		clearNetworkOwnership(record.Model)
		record.Model:Destroy()
	end

	log:Info("Despawned cart for %s. Reason=%s", player.Name, reason or "Unknown")
end

local function resolveSpawnRecord(cartId: string, spawnId: string?): CartSpawnRecord
	if spawnId ~= nil then
		local requestedSpawn: CartSpawnRecord? = CartSpawnRegistry:GetById(spawnId)

		if requestedSpawn == nil then
			error(string.format("Unknown cart SpawnId %s", spawnId), 2)
		end

		return requestedSpawn :: CartSpawnRecord
	end

	local defaultSpawn: CartSpawnRecord? = CartSpawnRegistry:GetDefaultForCart(cartId)

	if defaultSpawn == nil then
		error(string.format("No enabled spawn for CartId %s", cartId), 2)
	end

	return defaultSpawn :: CartSpawnRecord
end

function CartService:SpawnCart(player: Player, cartId: string?, spawnId: string?): Model
	assert(FeatureFlags.CartEnabled, "Cart feature is disabled")

	assert(player.Parent == Players, "Player is not active")

	if self:GetCart(player) ~= nil then
		self:DespawnCart(player, "Replacing existing cart")
	end

	local resolvedCartId = cartId or Ids.Carts.ScrapChariot

	local definition = Carts[resolvedCartId]

	assert(definition ~= nil, string.format("Unknown CartId %s", resolvedCartId))

	local spawnRecord: CartSpawnRecord = resolveSpawnRecord(resolvedCartId, spawnId)

	assert(spawnRecord.Enabled, string.format("Cart spawn %s is disabled", spawnRecord.Id))

	local cartModel = CartAssetService:CloneAsset(resolvedCartId)

	prepareClone(cartModel, player, resolvedCartId, spawnRecord.Id)

	CartModelUtility.SetAnchored(cartModel, true)

	cartModel.Parent = RuntimeFolders.GetCartsFolder()

	cartModel:PivotTo(spawnRecord.CFrame * CFrame.new(0, 4, 0))

	CollisionService:SetModelCollisionGroup(cartModel, CollisionGroups.Carts)

	CartModelUtility.ZeroVelocities(cartModel)

	CartModelUtility.SetRootAnchoredOnly(cartModel, false)

	setNetworkOwner(cartModel, player)

	local record: SpawnedCartRecord = {
		OwnerUserId = player.UserId,
		CartId = resolvedCartId,
		SpawnId = spawnRecord.Id,
		Model = cartModel,
		SpawnCFrame = spawnRecord.CFrame * CFrame.new(0, 4, 0),
		CreatedAt = Workspace:GetServerTimeNow(),
	}

	cartsByUserId[player.UserId] = record

	cartModel.Destroying:Connect(function()
		local current = cartsByUserId[player.UserId]

		if current and current.Model == cartModel then
			cartsByUserId[player.UserId] = nil
		end
	end)

	log:Info("Spawned %s for %s at %s", resolvedCartId, player.Name, spawnRecord.Id)

	return cartModel
end

function CartService:ResetCart(player: Player): boolean
	local record = getCartRecord(player)

	if record == nil then
		return false
	end

	local cartModel = record.Model

	if cartModel.Parent == nil then
		cartsByUserId[player.UserId] = nil
		return false
	end

	clearNetworkOwnership(cartModel)

	CartModelUtility.SetAnchored(cartModel, true)

	CartModelUtility.ZeroVelocities(cartModel)

	cartModel:PivotTo(record.SpawnCFrame)

	CartModelUtility.SetRootAnchoredOnly(cartModel, false)

	setNetworkOwner(cartModel, player)

	log:Info("Reset cart for %s", player.Name)

	return true
end

function CartService:Start()
	if not FeatureFlags.CartEnabled then
		log:Info("Cart feature disabled")
		return
	end

	Players.PlayerRemoving:Connect(function(player)
		self:DespawnCart(player, "Player leaving")
	end)

	log:Info("Cart service ready")
end

return CartService
