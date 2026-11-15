--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local ContentProvider = game:GetService("ContentProvider")
local CartGeometry = require(ReplicatedStorage.Shared.Utility.CartGeometry)

local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)
local CartAssemblyValidator = require(ReplicatedStorage.Shared.Validation.CartAssemblyValidator)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("CartAssetService")

local DEPENDENCY_WAIT_TIMEOUT_SECONDS = 10
local validatedSourceAssets: { [Model]: boolean } = {}

export type CartAssetService = {
	GetAsset: (self: CartAssetService, cartId: string) -> Model,

	CloneAsset: (self: CartAssetService, cartId: string) -> Model,
}

local CartAssetService: CartAssetService = {} :: CartAssetService

local function getCartAssetFolder(): Folder
	local studioAssets =
		ReplicatedStorage:WaitForChild("StudioAssets", DEPENDENCY_WAIT_TIMEOUT_SECONDS)

	assert(studioAssets ~= nil, "Timed out waiting for ReplicatedStorage.StudioAssets")

	local carts = studioAssets:WaitForChild("Carts", DEPENDENCY_WAIT_TIMEOUT_SECONDS)

	assert(carts ~= nil, "Timed out waiting for ReplicatedStorage.StudioAssets.Carts")
	assert(carts:IsA("Folder"), "ReplicatedStorage.StudioAssets.Carts must be a Folder")

	return carts
end

function CartAssetService:GetAsset(cartId: string): Model
	local definition = Carts[cartId]

	assert(definition ~= nil, string.format("Unknown CartId %s", cartId))

	local asset = getCartAssetFolder():FindFirstChild(definition.AssetName)

	local function ready(candidate: any): (boolean, string?)
		if not candidate or not candidate:IsA("Model") then return false,"Missing complete vehicle model" end
		if validatedSourceAssets[candidate] then return true, nil end
		local ok, failure = pcall(function()
			CartAssetValidator.AssertValid(candidate)
			CartAssemblyValidator.AssertValid(candidate, {Stage="Static"})
			local geometryValid, geometryReason = CartGeometry.ValidateTemplate(candidate)
			assert(geometryValid, geometryReason)
			local profile = CartGeometry.Get(candidate)
			if profile then
				local contents = {}
				local function importedPart(name: string)
					local part=candidate.Visual:FindFirstChild(name,true)
					assert(part and (part:IsA("MeshPart") or part:IsA("UnionOperation")),"Fitted art must be persisted native CSG or an imported mesh: "..name)
				end
				if profile.BodyMesh then importedPart("Body") end
				for _,wheel in profile.Wheels do importedPart(wheel.Name) end
				for _, part in candidate.Visual:GetDescendants() do
					if part:IsA("MeshPart") then
						assert(part.MeshId:match("^rbxassetid://[1-9]%d*$"), "Replacement mesh has no genuine asset ID")
						table.insert(contents, part.MeshId)
						local surface=part:FindFirstChildWhichIsA("SurfaceAppearance")
						assert(surface, "Replacement mesh is missing its material maps")
						for _, map in {surface.ColorMap,surface.NormalMap,surface.RoughnessMap} do
							assert(map:match("^rbxassetid://[1-9]%d*$"), "Replacement map has no genuine asset ID")
							table.insert(contents,map)
						end
					elseif part:IsA("UnionOperation") then
						local sha=part:GetAttribute("SourceArtSHA")
						assert(part:GetAttribute("NativeCSG")==true and part:GetAttribute("NativeVehicleConstruction")=="CSG" and part:GetAttribute("CartGeometryId")==profile.Id and part:GetAttribute("CartFitRevision")==profile.Revision and type(sha)=="string" and #sha==64 and sha:match("^%x+$"),"Native CSG is missing its fitted source provenance")
					end
				end
				local failed = false
				ContentProvider:PreloadAsync(contents,function(_content,status)
					if status ~= Enum.AssetFetchStatus.Success then failed=true end
				end)
				assert(not failed,"Replacement content failed to load")
			end
		end)
		if not ok then return false,tostring(failure) end
		validatedSourceAssets[candidate]=true
		return true,nil
	end
	local readyNow, failure = ready(asset)
	if not readyNow then
		-- Full previous template, not a new visual on old collision dimensions.
		local studioAssets=ReplicatedStorage:FindFirstChild("StudioAssets")
		local fallbacks=studioAssets and studioAssets:FindFirstChild("CartGeometryFallbacks")
		local fallback=fallbacks and fallbacks:FindFirstChild(definition.AssetName)
		local fallbackReady = fallback and fallback:IsA("Model") and ready(fallback)
		if fallbackReady then
			log:Warn("Using complete last-working vehicle %s: %s",cartId,tostring(failure))
			return fallback :: Model
		end
		error(string.format("Cart %s unavailable and no compatible fallback is ready: %s",cartId,tostring(failure)),2)
	end

	return asset :: Model
end

function CartAssetService:CloneAsset(cartId: string): Model
	local source: Model = self:GetAsset(cartId)

	-- Clone() is typed as returning Instance, so narrow it explicitly.
	local clonedInstance: Instance = source:Clone()

	assert(clonedInstance:IsA("Model"), "Cloned cart asset must remain a Model")

	local clone: Model = clonedInstance

	CartAssetValidator.AssertValid(clone)
	CartAssemblyValidator.AssertValid(clone, {
		Stage = "Static",
	})

	local geometryValid,geometryReason=CartGeometry.ValidateTemplate(clone)
	assert(geometryValid,geometryReason)

	log:Debug("Cloned cart asset %s", cartId)

	return clone
end

return CartAssetService
