--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

local Carts = require(ReplicatedStorage.Shared.Config.Carts)

local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("AssetValidationService")

local AssetValidationService = {}

local function getCartAssetFolder(): Folder
	local studioAssets = ReplicatedStorage:WaitForChild("StudioAssets")

	local carts = studioAssets:WaitForChild("Carts")

	assert(carts:IsA("Folder"), "StudioAssets.Carts must be a Folder")

	return carts
end

function AssetValidationService:ValidateCarts()
	local cartAssetFolder = getCartAssetFolder()

	for cartId, definition in Carts do
		local asset = cartAssetFolder:FindFirstChild(definition.AssetName)

		assert(
			asset ~= nil,
			string.format("Missing cart asset %s for %s", definition.AssetName, cartId)
		)

		assert(
			asset:IsA("Model"),
			string.format("Cart asset %s must be a Model", definition.AssetName)
		)

		local assetCartId = asset:GetAttribute("CartId")

		assert(
			assetCartId == cartId,
			string.format(
				"Cart asset %s has CartId %s; expected %s",
				definition.AssetName,
				tostring(assetCartId),
				cartId
			)
		)

		CartAssetValidator.AssertValid(asset)

		log:Info("Validated cart asset %s (%s)", definition.AssetName, cartId)
	end
end

function AssetValidationService:Start()
	if Environment.IsProduction then
		log:Info("Skipping verbose production asset validation")
		return
	end

	self:ValidateCarts()
end

return AssetValidationService
