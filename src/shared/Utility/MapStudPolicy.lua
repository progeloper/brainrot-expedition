--!strict
-- Playtest Fixes Part A: the saved environment studs on V5 world props (Workspace.World /
-- ServerStorage.TerrainRedesign.World). Edit-mode authoring only; never runs per frame.
--   Apply   SmoothPlastic/Plastic/Glacier -> Glacier + Environment_Saved_Studs variant, colour kept,
--           physics pinned to the pre-change CurrentPhysicalProperties, the old 0.8-transparent stud
--           Texture overlays removed. The original look is stored in StudMigrationOriginal* attributes.
--   Revert  restores Material, MaterialVariant, CustomPhysicalProperties and the Textures exactly.
-- Never call this on bases, stalls, creatures, carts or MapBlockout.
local HttpService = game:GetService("HttpService")
local Config = require(script.Parent.Parent.Config.PlaytestFixes).MapStuds

local Policy = {}

local PREFIX = Config.BackupAttributePrefix
local allowed: { [string]: boolean } = {}
for _, name in Config.Materials do
	allowed[name] = true
end
local excludedKits: { [string]: boolean } = {}
for _, name in Config.ExcludedKits do
	excludedKits[name] = true
end

local function isLegacyStud(d: Instance): boolean
	return d:IsA("Texture") and d.Texture == Config.LegacyTextureAsset
end

-- Pure size rule: trim smaller than MinReadableAxis on two or more axes keeps its look.
function Policy.IsTrim(size: Vector3): boolean
	local small = 0
	for _, axis in { size.X, size.Y, size.Z } do
		if axis < Config.MinReadableAxis then
			small += 1
		end
	end
	return small >= 2
end

-- Why a part is skipped (nil = eligible). Also true for parts already migrated.
function Policy.SkipReason(part: BasePart): string?
	if part:GetAttribute(PREFIX .. "Material") ~= nil then
		return "AlreadyMigrated"
	end
	if not allowed[part.Material.Name] then
		return "Material:" .. part.Material.Name
	end
	if part.Transparency > Config.MaxTransparency then
		return "Transparent"
	end
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceGui") or (child:IsA("Decal") and not isLegacyStud(child)) then
			return "TextOrDecal"
		end
	end
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if excludedKits[tostring(model:GetAttribute("Kit"))] then
			return "GlowKit"
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	if Policy.IsTrim(part.Size) then
		return "Trim"
	end
	return nil
end

local function physicsToString(p: PhysicalProperties?): string
	if not p then
		return ""
	end
	return string.format(
		"%.6g,%.6g,%.6g,%.6g,%.6g",
		p.Density,
		p.Friction,
		p.Elasticity,
		p.FrictionWeight,
		p.ElasticityWeight
	)
end

local function physicsFromString(s: string): PhysicalProperties?
	if s == "" then
		return nil
	end
	local v = string.split(s, ",")
	return PhysicalProperties.new(
		tonumber(v[1]) :: number,
		tonumber(v[2]) :: number,
		tonumber(v[3]) :: number,
		tonumber(v[4]) :: number,
		tonumber(v[5]) :: number
	)
end

local function textureRecord(t: Texture): { [string]: any }
	return {
		Name = t.Name,
		Texture = t.Texture,
		Face = t.Face.Name,
		U = t.StudsPerTileU,
		V = t.StudsPerTileV,
		Transparency = t.Transparency,
		OffsetU = t.OffsetStudsU,
		OffsetV = t.OffsetStudsV,
		Color = t.Color3:ToHex(),
		ZIndex = t.ZIndex,
	}
end

-- Returns true when the part changed and the number of Texture instances removed.
function Policy.Apply(part: BasePart): (boolean, number)
	if Policy.SkipReason(part) ~= nil then
		return false, 0
	end
	local textures = {}
	local removed: { Instance } = {}
	for _, child in part:GetChildren() do
		if isLegacyStud(child) then
			table.insert(textures, textureRecord(child :: Texture))
			table.insert(removed, child)
		end
	end
	local physical = part.CurrentPhysicalProperties
	part:SetAttribute(PREFIX .. "Material", part.Material.Name)
	part:SetAttribute(PREFIX .. "MaterialVariant", part.MaterialVariant)
	part:SetAttribute(PREFIX .. "Physics", physicsToString(part.CustomPhysicalProperties))
	part:SetAttribute(PREFIX .. "Textures", HttpService:JSONEncode(textures))
	part:SetAttribute(PREFIX .. "Color", part.Color:ToHex())
	-- Pin the walking/driving feel before the slippery Glacier base material takes over.
	part.CustomPhysicalProperties = PhysicalProperties.new(
		physical.Density,
		physical.Friction,
		physical.Elasticity,
		physical.FrictionWeight,
		physical.ElasticityWeight
	)
	local colour = part.Color
	part.Material = (Enum.Material :: any)[Config.VariantBaseMaterial]
	part.MaterialVariant = Config.Variant
	part.Color = colour
	for _, t in removed do
		t:Destroy()
	end
	return true, #removed
end

function Policy.Revert(part: BasePart): boolean
	local material = part:GetAttribute(PREFIX .. "Material")
	if type(material) ~= "string" then
		return false
	end
	part.Material = (Enum.Material :: any)[material]
	part.MaterialVariant = tostring(part:GetAttribute(PREFIX .. "MaterialVariant") or "")
	part.CustomPhysicalProperties =
		physicsFromString(tostring(part:GetAttribute(PREFIX .. "Physics") or ""))
	local colour = part:GetAttribute(PREFIX .. "Color")
	if type(colour) == "string" then
		part.Color = Color3.fromHex(colour)
	end
	local ok, list = pcall(
		HttpService.JSONDecode,
		HttpService,
		tostring(part:GetAttribute(PREFIX .. "Textures") or "[]")
	)
	for _, r in if ok then list else {} do
		local t = Instance.new("Texture")
		t.Name = r.Name
		t.Texture = r.Texture
		t.Face = (Enum.NormalId :: any)[r.Face]
		t.StudsPerTileU, t.StudsPerTileV = r.U, r.V
		t.OffsetStudsU, t.OffsetStudsV = r.OffsetU, r.OffsetV
		t.Transparency = r.Transparency
		t.Color3 = Color3.fromHex(r.Color)
		t.ZIndex = r.ZIndex
		t.Parent = part
	end
	for _, key in { "Material", "MaterialVariant", "Physics", "Textures", "Color" } do
		part:SetAttribute(PREFIX .. key, nil)
	end
	return true
end

export type Summary = { changed: number, texturesRemoved: number, skipped: { [string]: number } }

-- Whole tree, yielding every `yieldEvery` parts (Edit mode).
function Policy.ApplyTree(root: Instance, yieldEvery: number?): Summary
	local summary: Summary = { changed = 0, texturesRemoved = 0, skipped = {} }
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local reason = Policy.SkipReason(d)
			if reason then
				summary.skipped[reason] = (summary.skipped[reason] or 0) + 1
			else
				local changed, removed = Policy.Apply(d)
				if changed then
					summary.changed += 1
					summary.texturesRemoved += removed
				end
			end
			n += 1
			if yieldEvery and n % yieldEvery == 0 then
				task.wait()
			end
		end
	end
	return summary
end

function Policy.RevertTree(root: Instance, yieldEvery: number?): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and Policy.Revert(d) then
			n += 1
			if yieldEvery and n % yieldEvery == 0 then
				task.wait()
			end
		end
	end
	return n
end

return table.freeze(Policy)
