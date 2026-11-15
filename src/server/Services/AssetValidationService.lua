--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

local Carts = require(ReplicatedStorage.Shared.Config.Carts)

local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)
local CartAssemblyValidator = require(ReplicatedStorage.Shared.Validation.CartAssemblyValidator)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("AssetValidationService")

local AssetValidationService = {}

local DEPENDENCY_WAIT_TIMEOUT_SECONDS = 10

local function getCartAssetFolder(): Folder
	local studioAssets =
		ReplicatedStorage:WaitForChild("StudioAssets", DEPENDENCY_WAIT_TIMEOUT_SECONDS)

	assert(studioAssets ~= nil, "Timed out waiting for ReplicatedStorage.StudioAssets")

	local carts = studioAssets:WaitForChild("Carts", DEPENDENCY_WAIT_TIMEOUT_SECONDS)

	assert(carts ~= nil, "Timed out waiting for ReplicatedStorage.StudioAssets.Carts")
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
		local assemblyResult = CartAssemblyValidator.AssertValid(asset, {
			Stage = "Static",
		})

		for _, issue in assemblyResult.Warnings do
			log:Warn(
				"Assembly warning Cart=%s CartId=%s Code=%s Path=%s Message=%s Expected=%s Actual=%s Remediation=%s",
				assemblyResult.ModelName,
				assemblyResult.CartId,
				issue.Code,
				issue.InstancePath or "none",
				issue.Message,
				issue.Expected or "none",
				issue.Actual or "none",
				issue.Remediation or "none"
			)
		end

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
