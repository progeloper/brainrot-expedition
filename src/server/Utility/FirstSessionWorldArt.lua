--!strict
-- Startup-only, idempotent presentation for the first-session visual checkpoint:
-- one skyline marker per hunting region and prop clusters on measured empty runs.
-- No collision is added by markers; clusters reuse authored prop prototypes as-is.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config.FirstSessionVisuals)

local WorldArt = {}

local function part(
	parent: Instance,
	name: string,
	shape: Enum.PartType?,
	size: Vector3,
	frame: CFrame,
	colour: Color3,
	material: Enum.Material?,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = frame
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Vertical cylinder from y0 to y1 at (x, z).
local function column(
	parent: Instance,
	name: string,
	x: number,
	z: number,
	y0: number,
	y1: number,
	diameter: number,
	colour: Color3,
	material: Enum.Material?
): Part
	local h = math.max(y1 - y0, 0.5)
	return part(
		parent,
		name,
		Enum.PartType.Cylinder,
		Vector3.new(h, diameter, diameter),
		CFrame.new(x, y0 + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		colour,
		material
	)
end

local function ball(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	z: number,
	d: number,
	colour: Color3,
	material: Enum.Material?,
	transparency: number?
): Part
	return part(
		parent,
		name,
		Enum.PartType.Ball,
		Vector3.new(d, d, d),
		CFrame.new(x, y, z),
		colour,
		material,
		transparency
	)
end

local function light(p: BasePart, colour: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
	l.Parent = p
end

local hex = Color3.fromHex
local builders: { [string]: (Model, number, number, number, number) -> () } = {
	CanopyTree = function(m, x, z, y0, top)
		column(m, "Trunk", x, z, y0, top - 26, 8, hex("7A4A26"))
		ball(m, "CanopyLow", x, top - 30, z, 40, hex("2F9E44"))
		ball(m, "CanopyMid", x + 6, top - 16, z - 4, 30, hex("49C05A"))
		ball(m, "CanopyTop", x - 3, top - 5, z + 3, 18, hex("8CE36B"))
	end,
	Lighthouse = function(m, x, z, y0, top)
		local bands = 6
		local span = (top - 14 - y0) / bands
		for i = 0, bands - 1 do
			column(
				m,
				"Band" .. i,
				x,
				z,
				y0 + i * span,
				y0 + (i + 1) * span,
				12 - i * 0.6,
				if i % 2 == 0 then hex("FFFFFF") else hex("E63946")
			)
		end
		local lamp = part(
			m,
			"Lamp",
			nil,
			Vector3.new(9, 8, 9),
			CFrame.new(x, top - 10, z),
			hex("FFE066"),
			Enum.Material.Neon
		)
		light(lamp, hex("FFE066"), 48, 2)
		column(m, "Roof", x, z, top - 6, top, 10, hex("E63946"))
	end,
	SwampLantern = function(m, x, z, y0, top)
		column(m, "Stalk", x, z, y0, top - 18, 6, hex("3B4A2A"))
		part(
			m,
			"Arm",
			nil,
			Vector3.new(18, 3, 3),
			CFrame.new(x + 6, top - 20, z) * CFrame.Angles(0, 0, math.rad(-18)),
			hex("3B4A2A")
		)
		local orb = ball(m, "Lantern", x, top - 8, z, 16, hex("B6FF3B"), Enum.Material.Neon)
		light(orb, hex("B6FF3B"), 44, 1.6)
		ball(m, "Moss", x - 4, top - 30, z + 3, 12, hex("5E8C4A"))
	end,
	JungleGiant = function(m, x, z, y0, top)
		column(m, "Trunk", x, z, y0, top - 24, 10, hex("6B4226"))
		ball(m, "CanopyWide", x, top - 26, z, 46, hex("18A88A"))
		ball(m, "CanopyHigh", x - 6, top - 9, z + 5, 28, hex("2ED3A0"))
		ball(m, "Bloom1", x + 14, top - 20, z - 10, 7, hex("FF7A1A"), Enum.Material.Neon)
		ball(m, "Bloom2", x - 16, top - 30, z + 8, 6, hex("FF3D8B"), Enum.Material.Neon)
	end,
	IceSpire = function(m, x, z, y0, top)
		local tiers = 5
		local span = (top - 10 - y0) / tiers
		for i = 0, tiers - 1 do
			local w = 18 - i * 3
			part(
				m,
				"Tier" .. i,
				nil,
				Vector3.new(w, span + 2, w),
				CFrame.new(x, y0 + i * span + span / 2, z)
					* CFrame.Angles(0, math.rad(45 * (i % 2)), 0),
				if i % 2 == 0 then hex("BDEFFF") else hex("7FD8FF"),
				Enum.Material.Ice
			)
		end
		local crystal = part(
			m,
			"Crystal",
			nil,
			Vector3.new(6, 12, 6),
			CFrame.new(x, top - 5, z) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			hex("F4FDFF"),
			Enum.Material.Neon
		)
		light(crystal, hex("BDEFFF"), 40, 1.4)
	end,
	VolcanoPlume = function(m, x, z, y0, top)
		local crater = ball(m, "Crater", x, y0 + 2, z, 18, hex("FF6A1A"), Enum.Material.Neon)
		light(crater, hex("FF6A1A"), 60, 2.2)
		local puffs = 5
		local span = (top - y0 - 8) / puffs
		for i = 1, puffs do
			ball(
				m,
				"Smoke" .. i,
				x + math.sin(i) * 4,
				y0 + i * span,
				z + math.cos(i) * 3,
				16 + i * 4,
				hex("4A4250"),
				nil,
				0.12
			)
		end
		ball(m, "Ember", x + 3, top - 4, z, 6, hex("FFB01F"), Enum.Material.Neon)
	end,
	GlitchPylon = function(m, x, z, y0, top)
		part(
			m,
			"Obelisk",
			nil,
			Vector3.new(7, top - 14 - y0, 7),
			CFrame.new(x, (y0 + top - 14) / 2, z),
			hex("1B1530")
		)
		local y = y0 + 10
		local i = 0
		while y < top - 18 do
			part(
				m,
				"Band" .. i,
				nil,
				Vector3.new(8, 1.6, 8),
				CFrame.new(x, y, z),
				if i % 2 == 0 then hex("A836FF") else hex("27EAFF"),
				Enum.Material.Neon
			)
			y += 14
			i += 1
		end
		local cube = part(
			m,
			"Core",
			nil,
			Vector3.new(9, 9, 9),
			CFrame.new(x, top - 6, z) * CFrame.Angles(math.rad(35), math.rad(45), 0),
			hex("27EAFF"),
			Enum.Material.Neon
		)
		light(cube, hex("A836FF"), 48, 1.8)
	end,
}

local function buildSkyline(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SkylineMarkers"
	for _, spec in ipairs(Config.Skyline.Markers) do
		local model = Instance.new("Model")
		model.Name = "Skyline_" .. spec.Region:gsub("%s", "")
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		model:SetAttribute("PresentationClass", "CriticalBoundary")
		model:SetAttribute("GlobalNavigationFacade", true)
		model:SetAttribute("FirstSessionRegion", spec.Region)
		local build = builders[spec.Style]
		assert(build, "Unknown skyline style " .. spec.Style)
		local top = Config.Skyline.TopHeight
		build(model, spec.X, spec.Z, spec.BaseY, top)
		-- The map Atmosphere washes geometry into the sky beyond ~500 studs, so each
		-- marker also carries a glowing crown and a region-name chip (GUI is not hazed).
		local colour = Config.Facade.CrestColours[spec.Region] or Config.Facade.NeutralCrest
		local crown = ball(model, "Crown", spec.X, top + 3, spec.Z, 8, colour, Enum.Material.Neon)
		light(crown, colour, 36, 1.2)
		local anchor = part(
			model,
			"LabelAnchor",
			nil,
			Vector3.new(1, 1, 1),
			CFrame.new(spec.X, top + 9, spec.Z),
			colour,
			nil,
			1
		)
		local chip = Instance.new("BillboardGui")
		chip.Name = "RegionChip"
		chip.Adornee = anchor
		chip.Size = UDim2.fromOffset(Config.Skyline.ChipWidth, Config.Skyline.ChipHeight)
		chip.MaxDistance = Config.Skyline.ChipMaxDistance
		chip.LightInfluence = 0
		chip.AlwaysOnTop = false
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromScale(1, 1)
		pill.BackgroundColor3 = Color3.fromRGB(18, 27, 43)
		pill.BackgroundTransparency = 0.2
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = pill
		local stroke = Instance.new("UIStroke")
		stroke.Color = colour
		stroke.Thickness = 2
		stroke.Parent = pill
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.FredokaOne
		text.TextSize = Config.Skyline.ChipText
		text.Text = string.upper(spec.Region)
		text.TextColor3 = colour
		text.TextStrokeTransparency = 0.3
		text.Parent = pill
		pill.Parent = chip
		chip.Parent = anchor
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d:SetAttribute("PresentationClass", "CriticalBoundary")
			end
		end
		model.Parent = folder
	end
	folder.Parent = root
	return #Config.Skyline.Markers
end

local function prototype(map: Instance, name: string): Model?
	local art = map:FindFirstChild("EnvironmentArt_V2")
	local source = art and art:FindFirstChild(name)
	return if source and source:IsA("Model") then source else nil
end

local function place(
	map: Instance,
	parent: Instance,
	name: string,
	at: Vector3,
	yaw: number,
	scale: number
): boolean
	local source = prototype(map, name)
	if not source then
		return false
	end
	local clone = source:Clone()
	clone:SetAttribute("PrototypeId", nil)
	clone:SetAttribute("FirstSessionClusterProp", name)
	if scale ~= 1 then
		clone:ScaleTo(clone:GetScale() * scale)
	end
	-- Keep the source's ground contact: move in x/z, rotate about y, then restore
	-- the authored bounding-box bottom (scaling happens about the pivot).
	local sourceFrame, sourceSize = source:GetBoundingBox()
	local sourceBottom = sourceFrame.Position.Y - sourceSize.Y / 2
	clone:PivotTo(CFrame.new(at.X, clone:GetPivot().Position.Y, at.Z) * CFrame.Angles(0, yaw, 0))
	local frame, size = clone:GetBoundingBox()
	clone:PivotTo(
		clone:GetPivot() + Vector3.new(0, sourceBottom - (frame.Position.Y - size.Y / 2), 0)
	)
	clone.Parent = parent
	return true
end

local function buildClusters(map: Instance, root: Instance): number
	local folder = Instance.new("Folder")
	folder.Name = "PropClusters"
	folder.Parent = root
	local names = Config.ClusterPrototypes
	local placed = 0
	for index, spec in ipairs(Config.Clusters) do
		local group = Instance.new("Model")
		group.Name = string.format("Cluster_%02d_%s", index, spec.Kind)
		group.Parent = folder
		local yaw = math.rad((index * 67) % 360)
		local p = spec.Position
		local rot = CFrame.Angles(0, yaw, 0)
		local function offset(dx: number, dz: number): Vector3
			return p + rot:VectorToWorldSpace(Vector3.new(dx, 0, dz))
		end
		if spec.Kind == "Forest" then
			local scale = 0.75 + (index % 3) * 0.12
			if place(map, group, names.Tree, p, yaw, scale) then
				placed += 1
			end
			if place(map, group, names.Rock, offset(9, 5), yaw + 1.1, 0.8) then
				placed += 1
			end
			if place(map, group, names.Shrub, offset(-8, 4), yaw + 2.3, 1) then
				placed += 1
			end
		else
			if place(map, group, names.Rock, p, yaw, 0.7) then
				placed += 1
			end
			if place(map, group, names.CampShrub, offset(7, -3), yaw + 0.8, 1) then
				placed += 1
			end
			if place(map, group, names.CampShrub, offset(-6, 5), yaw + 2.1, 0.8) then
				placed += 1
			end
		end
		if index % 6 == 0 then
			task.wait()
		end
	end
	return placed
end

function WorldArt.Apply(map: Instance): any
	local root = map:FindFirstChild("FirstSessionArt")
	if root and root:GetAttribute("Version") == Config.Version then
		return { skipped = true }
	end
	if root then
		root:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "FirstSessionArt"
	root:SetAttribute("Version", Config.Version)
	local markers = buildSkyline(root)
	local props = buildClusters(map, root)
	root.Parent = map
	return { skipped = false, markers = markers, props = props }
end

return WorldArt
