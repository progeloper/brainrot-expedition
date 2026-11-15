--!strict
-- Appearance only. Never changes geometry, CSG colour membership or physics.
local MS = game:GetService("MaterialService")
local C = require(script.Parent.Parent.Config.AfternoonRepair)
local Policy = {}
local covered = setmetatable({}, { __mode = "k" })
local counts = { applies = 0, missingVariants = 0, authoredUV = 0 }
function Policy.Apply(part: BasePart, _legacy: Enum.Material?, family: string?): boolean
	if part.Transparency >= 1 or part:GetAttribute("BrainrotVisualHelper") == true then
		return false
	end
	-- Voxel V4: the builder already bound the saved creature stud variant to Relief
	-- parts. Eyes, mouth, glass, Neon and other non-relief faces never get studs.
	if part:GetAttribute("VoxelV4") == true then
		if part:GetAttribute("Relief") ~= true or part.Material ~= Enum.Material.SmoothPlastic then
			return false
		end
		local stud = MS:FindFirstChild("AF2_Creature_SmoothPlastic")
		if stud and stud:IsA("MaterialVariant") and stud.BaseMaterial == Enum.Material.SmoothPlastic then
			part.MaterialVariant = stud.Name
			part:SetAttribute("StudCoverage", "Creature")
			part:SetAttribute("StudsPerTile", stud.StudsPerTile)
			return true
		end
		counts.missingVariants += 1
		return false
	end
	family = family or "Prop"
	if C.Studs.PropPrototypes[part:GetAttribute("PrototypeId")] then
		family = "Prop"
	end
	if game:GetService("CollectionService"):HasTag(part, "BrainrotIncomePlaque") then
		family = "Prop"
	end
	if part:FindFirstAncestorWhichIsA("Tool") then
		family = "Creature"
	end
	local key = C.Version .. ":" .. family
	if covered[part] == key then
		return true
	end
	if
		part:IsA("MeshPart")
		and (part.TextureID ~= "" or part:FindFirstChildOfClass("SurfaceAppearance"))
	then
		counts.authoredUV += 1
		part:SetAttribute("StudCoverage", "AUTHORED_UV_BAKE_REQUIRED")
		return false
	end
	-- Mutation presets already carry the shared motif and preserve their authored
	-- roughness/metalness/emission. The mutation owner remains authoritative.
	if part.MaterialVariant:match("^P12_") then
		covered[part] = key
		return true
	end
	local name = "AF2_" .. family .. "_" .. part.Material.Name
	local variant = MS:FindFirstChild(name)
	if
		not variant
		or not variant:IsA("MaterialVariant")
		or variant.BaseMaterial ~= part.Material
	then
		counts.missingVariants += 1
		part:SetAttribute("StudCoverage", "MISSING_VARIANT:" .. name)
		return false
	end
	local physical = part.CurrentPhysicalProperties
	part.MaterialVariant = name
	local after = part.CurrentPhysicalProperties
	if
		not part.CustomPhysicalProperties
		and (
			physical.Density ~= after.Density
			or physical.Friction ~= after.Friction
			or physical.Elasticity ~= after.Elasticity
			or physical.FrictionWeight ~= after.FrictionWeight
			or physical.ElasticityWeight ~= after.ElasticityWeight
		)
	then
		part.CustomPhysicalProperties = physical
	end
	part:SetAttribute("StudCoverage", family)
	part:SetAttribute("StudsPerTile", variant.StudsPerTile)
	part:SetAttribute("StudSurfaceRevision", C.Version)
	covered[part] = key
	counts.applies += 1
	return true
end
function Policy.ApplyModel(model: Instance, family: string)
	if model:IsA("BasePart") then
		Policy.Apply(model, nil, family)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			Policy.Apply(part, nil, family)
		end
	end
end
function Policy.GetDiagnostics()
	return table.clone(counts)
end
return table.freeze(Policy)
