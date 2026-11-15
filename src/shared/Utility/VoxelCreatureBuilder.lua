--!strict
-- The only code that creates Voxel V4 creature geometry. Input: a species data module
-- (src/shared/Config/VoxelCreatures/<ID>.lua, design units, y up, nose = +x).
-- Output: a presentation-only Model; it carries no gameplay authority.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Config.VoxelCreaturePalette)
local Measurements = require(Shared.Config.PlaytestMeasurements)

local Builder = {}

export type Box = {
	slot: string,
	min: { number },
	max: { number },
	role: string,
	relief: boolean,
	emissive: boolean,
	color: string?,
	bone: string?,
}

-- Motor6D rig (owner, 7 Nov 2026: "make them riggable"). Bone parts are invisible, uniquely named
-- "Rig<Bone>" parts at each joint pivot; Motor6Ds chain them from Root; every visible box is welded to
-- its bone. Animations key poses by these bone part names.
Builder.RigBonePrefix = "Rig"
local JOINT_SUFFIX = {
	{ "LowerLeg", "Knee" },
	{ "Forearm", "Elbow" },
	{ "Leg", "Hip" },
	{ "Arm", "Shoulder" },
	{ "Wing", "WingRoot" },
}

function Builder.JointName(bone: string): string
	if bone == "Torso" then
		return "RootJoint"
	elseif bone == "Head" then
		return "Neck"
	end
	for _, pair in JOINT_SUFFIX do
		local suffix, joint = pair[1], pair[2]
		if string.sub(bone, -#suffix) == suffix then
			return string.sub(bone, 1, #bone - #suffix) .. joint
		end
	end
	return bone .. "Joint"
end

local TARGET_HEIGHT = Measurements.ReferenceBodyHeight * Palette.TargetHeightMultiplier

local function color(hex: string): Color3
	return Color3.fromHex(hex)
end

-- design (x, y, z) relative to ground centre g -> model space (z, y, -x)
local function toModel(p: { number }, g: { number }): Vector3
	return Vector3.new(p[3] - g[3], p[2] - g[2], -(p[1] - g[1]))
end

-- Giant species (optional data.sizeMultiplier, e.g. 1.5) stand taller than the shared target height.
function Builder.SizeMultiplier(data: any?): number
	local m = if data then data.sizeMultiplier else nil
	return if type(m) == "number" and m > 0 then m else 1
end

function Builder.TargetHeight(data: any?): number
	return TARGET_HEIGHT * Builder.SizeMultiplier(data)
end

function Builder.GameplayScale(data: any): number
	return Builder.TargetHeight(data) / data.designHeight
end

function Builder.Bounds(data: any): (Vector3, Vector3)
	local lo = Vector3.one * math.huge
	local hi = -lo
	local g = data.anchors.CargoSeat
	for _, box in data.boxes do
		local a, b = toModel(box.min, g), toModel(box.max, g)
		lo = lo:Min(a:Min(b))
		hi = hi:Max(a:Max(b))
	end
	return lo, hi
end

-- Deterministic content signature (FNV-1a over the serialised boxes and palette).
function Builder.Signature(data: any): string
	local h = 2166136261
	local function feed(s: string)
		for i = 1, #s do
			h = bit32.bxor(h, string.byte(s, i))
			h = (h * 16777619) % 4294967296
		end
	end
	feed(data.id .. ":" .. tostring(data.version) .. ":" .. data.irisFamily)
	for _, role in Palette.Roles do
		feed(role .. "=" .. tostring(data.palette[role]))
	end
	for _, box in data.boxes do
		feed(
			string.format(
				"%s|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%s|%s|%s|%s",
				box.slot,
				box.min[1],
				box.min[2],
				box.min[3],
				box.max[1],
				box.max[2],
				box.max[3],
				box.role,
				tostring(box.relief),
				tostring(box.emissive),
				tostring(box.color)
			)
				.. "|"
				.. tostring(box.bone)
		)
	end
	for _, b in data.rig or {} do
		feed(
			string.format(
				"rig|%s|%s|%.4f,%.4f,%.4f",
				b.name,
				b.parent,
				b.pivot[1],
				b.pivot[2],
				b.pivot[3]
			)
		)
	end
	for _, fx in data.passiveFx or {} do
		feed(string.format("fx|%s|%s|%.3f", fx.name, fx.texture, fx.rate))
	end
	return string.format("%08x", h)
end

local function largestUpper(data: any): number?
	local best, volume = nil, -1
	for index, box in data.boxes do
		if box.role == "upper" then
			local v = (box.max[1] - box.min[1])
				* (box.max[2] - box.min[2])
				* (box.max[3] - box.min[3])
			if v > volume then
				best, volume = index, v
			end
		end
	end
	return best
end

local function newPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

function Builder.Build(data: any): Model
	assert(type(data) == "table" and data.version == 4, "VOXEL_V4_DATA_REQUIRED")
	local scale = Builder.GameplayScale(data)
	local g = data.anchors.CargoSeat
	local model = Instance.new("Model")
	model.Name = data.id .. "_V4"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("VoxelCreatureVersion", 4)
	model:SetAttribute("VoxelSpeciesId", data.id)
	model:SetAttribute("VoxelDesignHeight", data.designHeight)
	model:SetAttribute("VoxelIrisFamily", data.irisFamily)
	model:SetAttribute("VoxelSignature", Builder.Signature(data))

	local root = newPart("Root")
	root.Size = Vector3.new(0.4, 0.2, 0.4)
	root.CFrame = CFrame.identity
	root.Transparency = 1
	root.CastShadow = false
	root:SetAttribute("BrainrotVisualHelper", true)
	root.Parent = model
	model.PrimaryPart = root

	for name, position in data.anchors do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = toModel(position, g)
		attachment.Parent = root
	end

	-- rig bones (parent-first order), positioned at their joint pivots
	local bones: { [string]: BasePart } = { Root = root }
	if data.rig then
		local controller = Instance.new("AnimationController")
		controller.Name = "AnimationController"
		Instance.new("Animator").Parent = controller
		controller.Parent = model
		for _, b in data.rig do
			local parent = bones[b.parent]
			assert(parent ~= nil, "RIG_PARENT_MISSING:" .. data.id .. ":" .. b.name)
			local bonePart = newPart(Builder.RigBonePrefix .. b.name)
			bonePart.Size = Vector3.new(0.2, 0.2, 0.2)
			-- "+ Vector3.zero" folds -0 to 0 so templates and fresh builds compare equal
			bonePart.CFrame = CFrame.new(toModel(b.pivot, g) + Vector3.zero)
			bonePart.Material = Enum.Material.SmoothPlastic
			bonePart.Transparency = 1
			bonePart.CastShadow = false
			bonePart.Anchored = false
			bonePart:SetAttribute("BrainrotVisualHelper", true)
			bonePart:SetAttribute("RigBone", b.name)
			local motor = Instance.new("Motor6D")
			motor.Name = Builder.JointName(b.name)
			motor.Part0 = parent
			motor.Part1 = bonePart
			motor.C0 = parent.CFrame:Inverse() * bonePart.CFrame
			motor.C1 = CFrame.identity
			motor.Parent = bonePart
			bonePart.Parent = model
			bones[b.name] = bonePart
		end
		model:SetAttribute("VoxelRigged", true)
	end

	local bodyIndex = largestUpper(data)
	for index, box in data.boxes do
		local a, b = toModel(box.min, g), toModel(box.max, g)
		local lo, hi = a:Min(b), a:Max(b)
		local size = hi - lo
		local name = if index == bodyIndex
			then "Body"
			elseif box.slot == "BodySection" then box.slot .. "_" .. box.role
			else box.slot
		local part = newPart(name)
		part.Size = size
		part.CFrame = CFrame.new((lo + hi) / 2)
		local protected = box.role == "Protected"
		local hex = if protected then box.color else data.palette[box.role]
		assert(
			type(hex) == "string",
			"MISSING_COLOUR:" .. data.id .. ":" .. box.slot .. ":" .. box.role
		)
		part.Color = color(hex)
		if box.emissive then
			part.Material = Enum.Material.Neon
		else
			part.Material = Enum.Material.SmoothPlastic
			if box.relief then
				part.MaterialVariant = Palette.Studs.MaterialVariant
			end
		end
		local volume = size.X * size.Y * size.Z * scale * scale * scale
		part.CastShadow = volume > Palette.Fit.CastShadowMinVolume
		part:SetAttribute("Role", box.role)
		part:SetAttribute("Protected", protected)
		part:SetAttribute("Relief", box.relief and not box.emissive)
		part:SetAttribute("Emissive", box.emissive)
		part:SetAttribute("Slot", box.slot)
		part:SetAttribute("VoxelV4", true)
		part:SetAttribute("VoxelIndex", index)
		if data.rig then
			local bonePart = bones[box.bone or "Torso"]
			assert(bonePart ~= nil, "RIG_BONE_MISSING:" .. data.id .. ":" .. tostring(box.bone))
			part.Anchored = false
			part:SetAttribute("Bone", box.bone or "Torso")
			local weld = Instance.new("WeldConstraint")
			weld.Name = "RigWeld"
			weld.Part0 = bonePart
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = model
		if index == bodyIndex then
			local capture = Instance.new("Attachment")
			capture.Name = "CaptureAttachment"
			capture.Parent = part
			local cargo = Instance.new("Attachment")
			cargo.Name = "CargoAttachment"
			cargo.CFrame = part.CFrame:Inverse()
			cargo.Parent = part
		end
	end
	-- Passive species FX: small always-on emitters on root attachments (data.passiveFx)
	for _, fx in data.passiveFx or {} do
		local attachment = Instance.new("Attachment")
		attachment.Name = "V4_PassiveFx_" .. fx.name
		attachment.Position = toModel(fx.anchor, g)
		attachment.Parent = root
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "V4_Passive_" .. fx.name
		emitter.Texture = Palette.PassiveFx.Textures[fx.texture]
		emitter.Rate = fx.rate
		emitter.Lifetime = NumberRange.new(fx.lifetime[1], fx.lifetime[2])
		emitter.Size = NumberSequence.new(fx.size[1], fx.size[2])
		emitter.Transparency = NumberSequence.new(fx.transparency[1], fx.transparency[2])
		emitter.Color = ColorSequence.new(color(fx.colors[1]), color(fx.colors[2]))
		emitter.LightEmission = fx.lightEmission or 0
		emitter.Speed = NumberRange.new(fx.speed[1], fx.speed[2])
		emitter.SpreadAngle = Vector2.new(fx.spread, fx.spread)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Acceleration = Vector3.new(0, fx.rise or 0, 0)
		emitter.RotSpeed = NumberRange.new(-40, 40)
		emitter:SetAttribute("V4PassiveFx", true)
		emitter.Parent = attachment
	end
	model.WorldPivot = root.CFrame
	Builder.BuildMutationPresets(model, data)
	return model
end

-- Stores each mutation's role map (+ species overrides), overlay Texture and effect
-- configuration on the template as Configuration attributes.
function Builder.BuildMutationPresets(model: Model, data: any): Folder
	local old = model:FindFirstChild("Mutations")
	if old then
		old:Destroy()
	end
	local lo, hi = Builder.Bounds(data)
	local size = hi - lo
	local folder = Instance.new("Folder")
	folder.Name = "Mutations"
	for _, mutation in Palette.Mutations do
		local config = Instance.new("Configuration")
		config.Name = mutation
		local roles = Palette.MutationPalettes[mutation]
		local overrides = data.mutationOverrides[mutation] or {}
		for _, role in Palette.Roles do
			local hex = overrides[role] or roles[role]
			config:SetAttribute("Role_" .. role, color(hex))
			if overrides[role] then
				config:SetAttribute("Override_" .. role, true)
			end
		end
		local effect = Palette.MutationEffects[mutation]
		config:SetAttribute("Reflectance", effect.reflectance)
		config:SetAttribute("Overlay", effect.overlay or "")
		config:SetAttribute(
			"OverlayImage",
			if effect.overlay then Palette.OverlayImages[effect.overlay] else ""
		)
		config:SetAttribute("OverlayStudsPerTile", Palette.OverlayStudsPerTile)
		config:SetAttribute("EmitterRate", effect.emitter.rate)
		-- Design-unit sizes; multiplied by the clone's current scale when applied.
		config:SetAttribute("EmitterBox", size * 0.9)
		config:SetAttribute("AuraSize", size.Y * Palette.AuraHeightScale)
		config:SetAttribute("Glow", color(Palette.MutationGlow[mutation][1]))
		if effect.halo then
			config:SetAttribute("HaloRadius", math.max(size.X, size.Z) * effect.halo.radiusScale)
			config:SetAttribute("HaloTilt", effect.halo.tiltDegrees)
			config:SetAttribute("HaloHeight", hi.Y + 0.2)
		end
		config.Parent = folder
	end
	folder.Parent = model
	return folder
end

-- Measurement entry compatible with PlaytestMeasurements.Species, derived from the
-- V4 data alone (template stored at scale 1 = design units, Root at ground centre).
function Builder.Measure(data: any)
	local lo, hi = Builder.Bounds(data)
	local h0 = hi.Y - lo.Y
	local s = Builder.TargetHeight(data) / h0
	local size = (hi - lo) * s
	return table.freeze({
		verified = true,
		surfaceVerified = true,
		voxelV4 = true,
		status = "VOXEL_V4_DATA",
		source = "ReplicatedStorage.CodeAssets.CreaturesV4." .. data.id .. "_V4",
		revision = Builder.Signature(data),
		s0 = Builder.SizeMultiplier(data), -- ExactBodyPlacement.Normalize scales by s0 (giants > 1)
		sTarget = s,
		xmin = lo.X,
		xmax = hi.X,
		ymin = lo.Y,
		ymax = hi.Y,
		zmin = lo.Z,
		zmax = hi.Z,
		normalizedSize = size,
		groundPoint = Vector3.zero,
		normalizedTop = Vector3.new(0, size.Y, 0),
		G = CFrame.identity,
		members = { "Body" },
		forward = Palette.DesignForward,
		up = Vector3.yAxis,
	})
end

-- Effect geometry for the Astral halo: a stepped octagon ring of thin Neon boxes.
function Builder.BuildHalo(radius: number, thickness: number, hex: string): Model
	local halo = Instance.new("Model")
	halo.Name = "V4_AstralHalo"
	halo:SetAttribute("BrainrotVisualHelper", true)
	local side = 2 * radius * math.tan(math.pi / 8)
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local part = newPart("HaloSegment")
		part.Size = Vector3.new(side + thickness, thickness, thickness * 1.5)
		part.Material = Enum.Material.Neon
		part.Color = color(hex)
		part.CastShadow = false
		part:SetAttribute("BrainrotVisualHelper", true)
		part.CFrame = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, radius)
		part.Parent = halo
	end
	halo.WorldPivot = CFrame.identity
	return halo
end

-- Authoring helpers mirroring the reference JS (B, MZ and the stepped section).
function Builder.Authoring()
	local boxes: { Box } = {}
	local current = "Part"
	local api = {}
	function api.S(name: string)
		current = name
	end
	function api.B(
		x0,
		x1,
		y0,
		y1,
		z0,
		z1,
		role: string,
		relief: boolean?,
		emissive: boolean?,
		hex: string?
	)
		if z0 > z1 then
			z0, z1 = z1, z0
		end
		table.insert(boxes, {
			slot = current,
			min = { x0, y0, z0 },
			max = { x1, y1, z1 },
			role = role,
			relief = relief == true,
			emissive = emissive == true,
			color = hex,
		})
	end
	function api.MZ(
		x0,
		x1,
		y0,
		y1,
		z0,
		z1,
		role: string,
		relief: boolean?,
		emissive: boolean?,
		hex: string?
	)
		api.B(x0, x1, y0, y1, z0, z1, role, relief, emissive, hex)
		api.B(x0, x1, y0, y1, -z1, -z0, role, relief, emissive, hex)
	end
	-- Two-tone stepped section with a Neon separation line: {x0, x1, bottom, splitY, top, halfWidth}
	function api.Section(x0, x1, bottom, split, top, hw, relief: boolean?)
		api.B(x0, x1, bottom, split, -hw, hw, "lower", relief)
		api.B(x0, x1, split, split + 0.17, -hw - 0.02, hw + 0.02, "stripe", false, true)
		if top > split + 0.17 then
			api.B(x0, x1, split + 0.17, top, -hw, hw, "upper", relief)
		end
	end
	api.boxes = boxes
	return api
end

return table.freeze(Builder)
