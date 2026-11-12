--!strict
local RS = game:GetService("ReplicatedStorage")
local C = require(RS.Shared.Config.PlaytestExact)
local M = require(RS.Shared.Config.PlaytestMeasurements)
local Policy = {}
local part
function part(x, colour)
	if x and (x:IsA("Model") or x:IsA("Folder")) then
		-- e.g. Path_Camp_1_1_CornerRoads (Camp Rework): colour every piece like a single surface
		for _, child in x:GetDescendants() do
			if child:IsA("BasePart") then
				part(child, colour)
			end
		end
		return
	end
	if not x or not x:IsA("BasePart") then
		return
	end
	-- No atlas/texture is silently replaced or claimed to have changed.
	if x:IsA("MeshPart") and (x.TextureID ~= "" or x:FindFirstChildOfClass("SurfaceAppearance")) then
		x:SetAttribute("ExactColourStatus", "TEXTURE_SOURCE_BLOCKED")
		return
	end
	x.Color = colour
	x.Reflectance = 0
	if x.Material == Enum.Material.Neon then
		x.Material = Enum.Material.SmoothPlastic
	end
	x:SetAttribute("ExactColourVersion", C.Version)
end
local function resolve(path)
	local cursor = game
	for name in path:gmatch("[^.]+") do
		cursor = cursor and cursor:FindFirstChild(name)
	end
	return cursor
end
function Policy.ApplyMap()
	for _, role in ipairs({ "CampGrass", "CampPath" }) do
		for _, path in ipairs(M.ColourRoles[role]) do
			part(resolve(path), C.Colours[role])
		end
	end
	local shells = resolve(M.ColourRoles.NeutralStructure[1])
	if shells then
		for _, model in ipairs(shells:GetChildren()) do
			local core = model:FindFirstChild("Core")
			part(core, C.Colours.NeutralStructure)
			if core and core:IsA("BasePart") then
				core.CastShadow = true
			end
		end
	end
end
function Policy.ApplyBase(base, designId, finish)
	if designId == "BDS_001" and finish == "Default" then
		for _, name in ipairs(M.ColourRoles.DefaultBase) do
			part(base:FindFirstChild(name), C.Colours.DefaultBase)
		end
	end
	for _, name in ipairs({ "Primary", "Support", "Foundation" }) do
		local x = base:FindFirstChild(name)
		if x and x:IsA("BasePart") then
			x.CastShadow = true
		end
	end
	require(RS.Shared.Utility.BaseInfillAdapter).Apply(base)
	-- Explicit source group membership: the five Accent solids are crown trim
	-- and sign framing, while Primary/Support/Foundation are structural.
	for _, name in require(RS.Shared.Config.BaseJoinMetadata).DecorativeNativeMembers do
		local member = base:FindFirstChild(name)
		if member and member:IsA("BasePart") then
			member.CastShadow = false
			member:SetAttribute("ExactShadowStatus", "DECORATIVE_SOURCE_MEMBERSHIP")
		end
	end
end
function Policy.ApplyCart(model)
	for _, x in ipairs(model:GetDescendants()) do
		if x:IsA("BasePart") then
			x.CastShadow = false
		end
	end
end
return table.freeze(Policy)
