--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Carts = require(ReplicatedStorage.Shared.Config.Carts)

local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("CartAssetService")

export type CartAssetService = {
	GetAsset: (self: CartAssetService, cartId: string) -> Model,

	CloneAsset: (self: CartAssetService, cartId: string) -> Model,
}

local CartAssetService: CartAssetService = {} :: CartAssetService

local function getCartAssetFolder(): Folder
	local studioAssets = ReplicatedStorage:WaitForChild("StudioAssets")

	local carts = studioAssets:WaitForChild("Carts")

	assert(carts:IsA("Folder"), "ReplicatedStorage.StudioAssets.Carts must be a Folder")

	return carts
end

function CartAssetService:GetAsset(cartId: string): Model
	local definition = Carts[cartId]

	assert(definition ~= nil, string.format("Unknown CartId %s", cartId))

	local asset = getCartAssetFolder():FindFirstChild(definition.AssetName)

	assert(
		asset ~= nil,
		string.format("Missing cart asset %s for %s", definition.AssetName, cartId)
	)

	assert(
		asset:IsA("Model"),
		string.format(
			"Cart asset %s must be a Model, got %s",
			definition.AssetName,
			asset.ClassName
		)
	)

	CartAssetValidator.AssertValid(asset)

	return asset
end

function CartAssetService:CloneAsset(cartId: string): Model
	local source: Model = self:GetAsset(cartId)

	-- Clone() is typed as returning Instance, so narrow it explicitly.
	local clonedInstance: Instance = source:Clone()

	assert(clonedInstance:IsA("Model"), "Cloned cart asset must remain a Model")

	local clone: Model = clonedInstance

	CartAssetValidator.AssertValid(clone)

	log:Debug("Cloned cart asset %s", cartId)

	return clone
end

return CartAssetService
