--!strict
-- Client adapters install a selective cache. No full template collection fallback
-- is used once the server has selected the interest protocol.
local RS = game:GetService("ReplicatedStorage")
local Provider = {}
local resolver = nil
local version = 0
function Provider.SetResolver(callback)
	resolver = callback
end
function Provider.NotifyChanged()
	version += 1
end
function Provider.GetVersion(): number
	return version
end
function Provider.Get(species: string, lod: string?): Model?
	if resolver then
		return resolver(species, lod or "Detailed")
	end
	if RS:GetAttribute("Phase13CreatureProtocolEnabled") == true then
		return nil
	end
	local voxel = require(RS.Shared.Utility.VoxelCreatureRegistry).GetActiveTemplate(species)
	if voxel then
		return voxel
	end
	local assets = RS:FindFirstChild("StudioAssets")
	local folder = assets and assets:FindFirstChild(if lod and lod ~= "Full" then "ChariotFormation" else "Brainrots")
	local source = folder and folder:FindFirstChild(species)
	if source and lod and lod ~= "Full" then
		source = source:FindFirstChild(lod)
	end
	return if source and source:IsA("Model") then source else nil
end
return table.freeze(Provider)
