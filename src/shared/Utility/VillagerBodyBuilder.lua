--!strict
-- Builds the one rigged villager body plus a skin (rig + animation brief v5, C.1/C.2).
-- Only Root is anchored; every other part hangs off Motor6D bones and WeldConstraints, so
-- an Animator can pose it. A skin never changes joints or proportions: it is a list of
-- boxes, each attached to one bone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Body = require(ReplicatedStorage.Shared.Config.VillagerBody)
local Palette = require(ReplicatedStorage.Shared.Config.VoxelCreaturePalette)

local Builder = {}

local function toColor(hex: string?): Color3
	if type(hex) ~= "string" then
		return Color3.new(1, 0, 1)
	end
	local ok, color = pcall(Color3.fromHex, hex)
	return if ok then color else Color3.new(1, 0, 1)
end

local function quiet(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function addBox(
	model: Model,
	bones: { [string]: BasePart },
	item: any,
	palette: any,
	index: number
)
	local bone = bones[item.bone]
	assert(
		bone,
		string.format("Villager box %s names unknown bone %s", item.slot, tostring(item.bone))
	)
	local size =
		Vector3.new(item.max[1] - item.min[1], item.max[2] - item.min[2], item.max[3] - item.min[3])
	local center = Vector3.new(
		item.max[1] + item.min[1],
		item.max[2] + item.min[2],
		item.max[3] + item.min[3]
	) / 2
	local part = Instance.new("Part")
	part.Name = item.slot
	part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	part.CFrame = CFrame.new(center)
	part.Anchored = false
	quiet(part)
	part.CastShadow = item.role ~= "Protected"
	local role = item.role
	part.Color = if role == "Protected"
		then toColor(item.color)
		else toColor(palette[role] or palette.cloth)
	if item.emissive or role == "glow" then
		part.Material = Enum.Material.Neon
	else
		part.Material = Enum.Material.SmoothPlastic
		if item.relief then
			part.MaterialVariant = Palette.Studs.MaterialVariant
		end
	end
	part:SetAttribute("Role", role)
	part:SetAttribute("Slot", item.slot)
	part:SetAttribute("Bone", item.bone)
	part:SetAttribute("VillagerIndex", index)
	if item.outfit then
		part:SetAttribute("OutfitSlot", item.outfit)
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bone
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
end

-- skin: { id: string, boxes: { Box with bone } } or nil for the bare body.
function Builder.Build(skin: any?, palette: { [string]: string }): Model
	local boxes = if skin then skin.boxes else {}
	assert(
		#boxes <= Body.MaxSkinBoxes,
		string.format(
			"Villager skin %s has %d boxes (max %d)",
			tostring(skin and skin.id),
			#boxes,
			Body.MaxSkinBoxes
		)
	)
	local model = Instance.new("Model")
	model.Name = "VillagerBody"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 0.2, 1)
	root.CFrame = CFrame.new(0, 0.1, 0)
	root.PivotOffset = CFrame.new(0, -0.1, 0) -- the model pivots at ground level
	root.Transparency = 1
	root.Anchored = true
	quiet(root)
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root
	local bones: { [string]: BasePart } = { Root = root }
	for _, bone in Body.Bones do
		local part = Instance.new("Part")
		part.Name = bone.name
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.CFrame = CFrame.new(bone.at[1], bone.at[2], bone.at[3])
		part.Transparency = 1
		part.Anchored = false
		quiet(part)
		part.CastShadow = false
		part:SetAttribute("IsBone", true)
		local parent = assert(bones[bone.parent], "Villager bone parent must come first")
		local motor = Instance.new("Motor6D")
		motor.Name = bone.name
		motor.Part0 = parent
		motor.Part1 = part
		motor.C0 = parent.CFrame:ToObjectSpace(part.CFrame)
		motor.C1 = CFrame.identity
		motor.Parent = parent
		part.Parent = model
		bones[bone.name] = part
	end
	local index = 0
	for _, item in Body.Boxes do
		index += 1
		addBox(model, bones, item, palette, index)
	end
	for _, item in boxes do
		index += 1
		addBox(model, bones, item, palette, index)
	end
	local controller = Instance.new("AnimationController")
	controller.Name = "AnimationController"
	local animator = Instance.new("Animator")
	animator.Parent = controller
	controller.Parent = model
	model.WorldPivot = CFrame.new(0, 0, 0)
	model:SetAttribute("RigArchetype", "VillagerBody")
	model:SetAttribute("RigVersion", Body.Version)
	model:SetAttribute("VillagerSkin", if skin then skin.id else nil)
	-- a held prop that must stay vertical (Utility/VillagerUprightProp); the client binds it
	model:SetAttribute("UprightProp", if skin and skin.uprightProp then true else nil)
	return model
end

-- Recolour an already-built body (template clone) with a villager palette.
function Builder.ApplyPalette(model: Model, palette: { [string]: string })
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("Role")
			if type(role) == "string" and role ~= "Protected" then
				part.Color = toColor(palette[role] or palette.cloth)
			end
		end
	end
end

-- Joint signature used by the R4 "same body" check: names, parents and C0/C1.
function Builder.JointSignature(model: Model): string
	local rows = {}
	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") then
			local p = motor.C0.Position
			table.insert(
				rows,
				string.format(
					"%s<%s:%.3f,%.3f,%.3f:%s",
					motor.Name,
					if motor.Part0 then motor.Part0.Name else "?",
					p.X,
					p.Y,
					p.Z,
					tostring(motor.C1 == CFrame.identity)
				)
			)
		end
	end
	table.sort(rows)
	return table.concat(rows, "|")
end

-- Character height including the skin's headwear (held props don't count).
function Builder.Height(skin: any?): number
	local top = Body.Height
	for _, item in if skin then skin.boxes else {} do
		if item.bone ~= "Prop" and item.bone ~= "PropL" then
			top = math.max(top, item.max[2])
		end
	end
	return top
end

return table.freeze(Builder)
