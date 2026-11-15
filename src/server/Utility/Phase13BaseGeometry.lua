--!strict
-- Native geometry is derived from each plot's own Foundation frame, including rotated plots.
local Geometry = { Version = "P13_BASE_2" }
local AppearanceRules = require(game:GetService("ReplicatedStorage").Shared.Utility.Phase13AppearanceRules)
local SlotPresentation = require(game:GetService("ReplicatedStorage").Shared.Utility.BaseSlotPresentation)
local palettes = {
	BDS_001 = { Color3.fromRGB(113, 82, 59), Color3.fromRGB(222, 195, 136) },
	BDS_002 = { Color3.fromRGB(48, 91, 57), Color3.fromRGB(190, 139, 77) },
	BDS_003 = { Color3.fromRGB(26, 91, 120), Color3.fromRGB(122, 224, 231) },
	BDS_004 = { Color3.fromRGB(62, 58, 85), Color3.fromRGB(160, 215, 94) },
	BDS_005 = { Color3.fromRGB(34, 94, 58), Color3.fromRGB(239, 185, 65) },
	BDS_006 = { Color3.fromRGB(111, 176, 207), Color3.fromRGB(226, 250, 255) },
	BDS_007 = { Color3.fromRGB(49, 43, 49), Color3.fromRGB(255, 113, 31) },
	BDS_008 = { Color3.fromRGB(52, 35, 92), Color3.fromRGB(97, 214, 255) },
}
local function firstColor(base, index)
	local p = base:FindFirstChild(string.format("Slot_%02d", index)) or base:FindFirstChild("Slot_" .. index)
	if p then
		local c = p:GetAttribute("Phase13OriginalColor")
		if typeof(c) == "Color3" then
			return c
		end
		p:SetAttribute("Phase13OriginalColor", p.Color)
		return p.Color
	end
	return Color3.fromRGB(157, 118, 71)
end
local function part(parent, name, size, cf, color, floor, role)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.Glacier
	p.MaterialVariant = "Environment_Saved_Studs_13719188279"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Phase13Floor", floor)
	p:SetAttribute("Phase13Role", role)
	p:SetAttribute("Phase13GeometryVersion", Geometry.Version)
	p.CanTouch = false
	SlotPresentation.CaptureGroup(p)
	SlotPresentation.ApplyGroup(p, false)
	p.Parent = parent
	return p
end
local function smoothStairs(base, architecture, foundation)
	local angle = math.atan2(12, 20)
	local length = math.sqrt(20 * 20 + 12 * 12)
	local thickness = 0.5
	local normalOffset = thickness / (2 * math.cos(angle))
	for floor = 1, 3 do
		local bottom = (floor - 1) * 24 + 0.5
		for _, flight in { "A", "B" } do
			local name = string.format("StairRamp_%d_%s", floor, flight)
			local ramp = architecture:FindFirstChild(name)
			if not ramp then
				local y = bottom + (if flight == "A" then 6 else 18) + 0.375 - normalOffset
				local x = if flight == "A" then -2.75 else 2.75
				ramp = part(
					architecture,
					name,
					Vector3.new(4.5, thickness, length),
					foundation.CFrame
						* CFrame.new(x, y, 23)
						* CFrame.Angles(if flight == "A" then -angle else angle, 0, 0),
					foundation.Color,
					floor,
					"StairRamp"
				)
			end
			SlotPresentation.Capture(ramp, { Transparency = 1, CanCollide = true, CanQuery = true, CanTouch = false })
			ramp.Transparency = 1
			ramp.CanCollide = true
			ramp.CanQuery = true
			ramp.CanTouch = false
			for i = 1, 16 do
				local tread = architecture:FindFirstChild(string.format("Stair_%d_%s_%02d", floor, flight, i))
				if tread then
					tread:SetAttribute("Phase13Role", "Tread")
					SlotPresentation.Capture(
						tread,
						{ Transparency = 0, CanCollide = false, CanQuery = false, CanTouch = false }
					)
					tread.CanCollide = false
					tread.CanQuery = false
					tread.CanTouch = false
				end
			end
		end
	end
	base:SetAttribute("Phase13GeometryVersion", Geometry.Version)
	base:SetAttribute("Phase13SmoothStairCollision", true)
end
-- Shared Primary/Support mesh exteriors were coplanar at +/-23.23 X and
-- +/-39.63125 Z. Inset the panel span .12 per face; support, entrance and
-- gameplay anchors stay in their accepted frames. The authored size prevents drift.
function Geometry.RepairPanelJoin(base: Model)
	return require(game:GetService("ReplicatedStorage").Shared.Utility.BaseInfillAdapter).Apply(base)
end

-- Upgrade metadata in place; never replace accepted slot anchors or regenerate native bases.
function Geometry.Prepare(base: Model)
	Geometry.RepairPanelJoin(base)
	local ground = {}
	for _, child in base:GetChildren() do
		local index = child:GetAttribute("SlotIndex")
		if child:IsA("BasePart") and type(index) == "number" and index >= 1 and index <= 12 then
			SlotPresentation.CaptureGroup(child)
			ground[index] = child
		end
	end
	for _, child in base:GetChildren() do
		local index = child:GetAttribute("SlotIndex")
		if child:IsA("BasePart") and type(index) == "number" then
			-- P13_BASE_2 hid upper roots before metadata existed. Their ground source retains
			-- the canonical defaults; descendants were never altered by that writer.
			local source = ground[(index - 1) % 12 + 1]
			if source and child:GetAttribute("BaseAuthored_Transparency") == nil then
				local authored = {}
				for _, property in { "Transparency", "CanCollide", "CanTouch", "CanQuery", "LocalTransparencyModifier" } do
					authored[property] = SlotPresentation.GetAuthoredProperty(source, property)
				end
				SlotPresentation.Capture(child, authored)
			end
			SlotPresentation.CaptureGroup(child)
			child:SetAttribute("BaseSlotIndex", index)
			child:SetAttribute("BaseRequiredStage", child:GetAttribute("Phase13Floor") or math.floor((index - 1) / 12))
		end
	end
	local architecture = base:FindFirstChild("Phase13Architecture")
	if architecture then
		for _, child in architecture:GetDescendants() do
			if child:IsA("BasePart") then
				if child:GetAttribute("BaseAuthored_Transparency") == nil then
					local role = child:GetAttribute("Phase13Role")
					SlotPresentation.Capture(child, {
						Transparency = if role == "StairRamp" then 1 else 0,
						CanCollide = role ~= "Tread",
						CanQuery = role ~= "Tread",
						CanTouch = false,
					})
				end
				SlotPresentation.CaptureGroup(child)
				child:SetAttribute("BaseRequiredStage", child:GetAttribute("Phase13Floor") or 0)
			end
		end
	end
	-- Saved cash pads predate the shared semantic metadata and live outside slots.
	local plaques = base:FindFirstChild("IncomePlaques")
	if plaques then
		for _, plaque in plaques:GetChildren() do
			local index = plaque:GetAttribute("PlatformId") or tonumber(plaque.Name:match("^IncomePlaque_(%d+)$"))
			if plaque:IsA("BasePart") and type(index) == "number" and index >= 1 and index <= 48 then
				if plaque:GetAttribute("BaseAuthored_Transparency") == nil then
					SlotPresentation.Capture(
						plaque,
						{ Transparency = 0, CanCollide = false, CanTouch = false, CanQuery = true }
					)
				end
				local sensor = plaque:FindFirstChild("TouchSensor")
				if sensor and sensor:IsA("BasePart") and sensor:GetAttribute("BaseAuthored_Transparency") == nil then
					SlotPresentation.Capture(
						sensor,
						{ Transparency = 1, CanCollide = false, CanTouch = true, CanQuery = false }
					)
				end
				for _, gui in plaque:GetDescendants() do
					if gui:IsA("SurfaceGui") or gui:IsA("BillboardGui") then
						SlotPresentation.Capture(gui, { Enabled = true })
						SlotPresentation.SetContentEnabled(
							gui,
							plaque:GetAttribute("PendingBank") == true
								or (
									plaque:GetAttribute("IncomeSnapshotReady") == true
									and plaque:GetAttribute("IncomeOccupied") == true
								)
						)
					end
				end
				SlotPresentation.CaptureGroup(plaque)
				plaque:SetAttribute("BaseSlotIndex", index)
				plaque:SetAttribute("BaseRequiredStage", math.floor((index - 1) / 12))
			end
		end
	end
end

function Geometry.Build(base: Model)
	local foundation = base:FindFirstChild("Foundation")
	assert(foundation and foundation:IsA("BasePart"), "Base Foundation missing")
	local first = {}
	for i = 1, 12 do
		local p = base:FindFirstChild(string.format("Slot_%02d", i)) or base:FindFirstChild("Slot_" .. i)
		if not p then
			for _, candidate in base:GetChildren() do
				if candidate:GetAttribute("SlotIndex") == i then
					p = candidate
					break
				end
			end
		end
		assert(p and p:IsA("BasePart"), "Native ground slot missing " .. i)
		first[i] = p
		p:SetAttribute("SlotIndex", i)
		SlotPresentation.CaptureGroup(p)
	end
	local existing = base:FindFirstChild("Phase13Architecture")
	if existing and base:GetAttribute("Phase13GeometryVersion") == Geometry.Version then
		Geometry.Prepare(base)
		return true
	end
	if existing and base:GetAttribute("Phase13GeometryVersion") == "P13_BASE_1" then
		smoothStairs(base, existing, foundation)
		Geometry.Prepare(base)
		return true
	end
	assert(not existing, "Unexpected base geometry version; preserve before migration")
	local architecture = Instance.new("Model")
	architecture.Name = "Phase13Architecture"
	local frame = foundation.CFrame
	local width = foundation.Size.X
	local length = foundation.Size.Z
	assert(width >= 46 and length >= 79, "Plot dimensions differ from measured geometry")
	-- The measured central aisle is 11.62 studs. Ten studs contains both flights.
	for floor = 1, 3 do
		local y = floor * 24
		local slabY = y
		part(
			architecture,
			"FloorLeft_" .. floor,
			Vector3.new((width - 10) / 2, 1, length),
			frame * CFrame.new(-(width + 10) / 4, slabY, 0),
			foundation.Color,
			floor,
			"Slab"
		)
		part(
			architecture,
			"FloorRight_" .. floor,
			Vector3.new((width - 10) / 2, 1, length),
			frame * CFrame.new((width + 10) / 4, slabY, 0),
			foundation.Color,
			floor,
			"Slab"
		)
		local frontLength = length / 2 + 13
		part(
			architecture,
			"FloorFront_" .. floor,
			Vector3.new(10, 1, frontLength),
			frame * CFrame.new(0, slabY, -length / 2 + frontLength / 2),
			foundation.Color,
			floor,
			"Slab"
		)
		part(
			architecture,
			"FloorRear_" .. floor,
			Vector3.new(10, 1, length / 2 - 37),
			frame * CFrame.new(0, slabY, (length / 2 + 37) / 2),
			foundation.Color,
			floor,
			"Slab"
		)
		for i = 1, 12 do
			local index = floor * 12 + i
			assert(
				not base:FindFirstChild(string.format("Slot_%02d", index)),
				"Existing upper slot must not be overwritten"
			)
			local slot = first[i]:Clone()
			slot.Name = string.format("Slot_%02d", index)
			slot.CFrame = first[i].CFrame + Vector3.yAxis * y
			slot:SetAttribute("SlotIndex", index)
			slot:SetAttribute("Phase13Floor", floor)
			slot:SetAttribute("Phase13Role", "Slot")
			slot:SetAttribute("Phase13GeometryVersion", Geometry.Version)
			for _, child in slot:GetChildren() do
				if child:IsA("BillboardGui") or child:IsA("SurfaceGui") or child:IsA("ProximityPrompt") then
					child:Destroy()
				end
			end
			SlotPresentation.CaptureGroup(slot)
			SlotPresentation.BindSlot(slot, base, index)
			slot.Parent = base
		end
		local bottom = (floor - 1) * 24 + 0.5
		for i = 1, 16 do
			local rise = i * 0.75
			part(
				architecture,
				string.format("Stair_%d_A_%02d", floor, i),
				Vector3.new(4.5, 0.75, 1.25),
				frame * CFrame.new(-2.75, bottom + rise - 0.375, 13 + (i - 0.5) * 1.25),
				Color3.fromRGB(173, 145, 103),
				floor,
				"Stair"
			)
			part(
				architecture,
				string.format("Stair_%d_B_%02d", floor, i),
				Vector3.new(4.5, 0.75, 1.25),
				frame * CFrame.new(2.75, bottom + 12 + rise - 0.375, 33 - (i - 0.5) * 1.25),
				Color3.fromRGB(173, 145, 103),
				floor,
				"Stair"
			)
		end
		part(
			architecture,
			"HalfLanding_" .. floor,
			Vector3.new(10, 0.75, 4),
			frame * CFrame.new(0, bottom + 12 - 0.375, 35),
			Color3.fromRGB(173, 145, 103),
			floor,
			"Stair"
		)
		-- Side rails follow the two flights without blocking the clear 4.5-stud walking width.
		for _, x in { -5.35, 5.35 } do
			for i = 0, 4 do
				local z = 13 + i * 5
				local h = if x < 0 then i * 3 else 24 - i * 3
				part(
					architecture,
					string.format("StairRail_%d_%s_%d", floor, if x < 0 then "L" else "R", i),
					Vector3.new(0.3, 3, 0.3),
					frame * CFrame.new(x, bottom + h + 1.5, z),
					Color3.fromRGB(68, 54, 42),
					floor,
					"Rail"
				)
			end
		end
		for _, x in { -width / 2 + 1, width / 2 - 1 } do
			for _, z in { -length / 2 + 1, length / 2 - 1 } do
				part(
					architecture,
					"Pillar_" .. floor,
					Vector3.new(1.5, 23, 1.5),
					frame * CFrame.new(x, y - 11.5, z),
					Color3.fromRGB(113, 82, 59),
					floor,
					"ThemePrimary"
				)
			end
		end
		part(
			architecture,
			"FrontCornice_" .. floor,
			Vector3.new(width, 1.5, 1.5),
			frame * CFrame.new(0, y + 2, -length / 2 + 1),
			Color3.fromRGB(222, 195, 136),
			floor,
			"ThemeAccent"
		)
	end
	-- A themed ground portal adds identity while preserving all accepted native sculpture/slot instances.
	for _, x in { -9, 9 } do
		part(
			architecture,
			"EntryPillar",
			Vector3.new(1.2, 9, 1.2),
			frame * CFrame.new(x, 5, -length / 2 + 2),
			Color3.fromRGB(113, 82, 59),
			0,
			"ThemePrimary"
		)
	end
	part(
		architecture,
		"EntryCrown",
		Vector3.new(20, 1.5, 2),
		frame * CFrame.new(0, 10, -length / 2 + 2),
		Color3.fromRGB(222, 195, 136),
		0,
		"ThemeAccent"
	)
	smoothStairs(base, architecture, foundation)
	for _, child in architecture:GetDescendants() do
		if child:IsA("BasePart") then
			SlotPresentation.ApplyGroup(child, false)
		end
	end
	architecture.Parent = base
	base:SetAttribute("Phase13GeometryVersion", Geometry.Version)
	base:SetAttribute("Phase13StairWidth", 10)
	base:SetAttribute("Phase13StairRun", 20)
	base:SetAttribute("Phase13StairRise", 24)
	Geometry.Apply(base, 12, "BDS_001", false)
	return true
end
function Geometry.Apply(base: Model, capacity: number, designId: string, vip: any, context: any?)
	local finish = if type(vip) == "string" then vip elseif vip == true then "Riftgold" else "Default"
	local FinishRoles = require(game:GetService("ReplicatedStorage").Shared.Utility.Phase13FinishRoles)
	assert(capacity >= 12 and capacity <= 48 and (capacity - 12) % 6 == 0, "Invalid physical capacity")
	local palette = palettes[designId]
	assert(palette, "Unknown base design")
	local architecture = base:FindFirstChild("Phase13Architecture")
	if not architecture then
		return false
	end
	Geometry.Prepare(base)
	local token = SlotPresentation.Begin(base, capacity, context)
	if not token then
		return false
	end
	local style = architecture:FindFirstChild("SelectedDesign")
	if not style or style:GetAttribute("DesignId") ~= designId then
		if style then
			style:Destroy()
		end
		style = Instance.new("Model")
		style.Name = "SelectedDesign"
		style:SetAttribute("DesignId", designId)
		local f = base.Foundation.CFrame
		local w = base.Foundation.Size.X
		local z = -base.Foundation.Size.Z / 2 + 2
		for floor = 0, 3 do
			local y = floor * 24
			if designId == "BDS_002" then
				for _, x in { -10, 10 } do
					part(
						style,
						"LodgeEave",
						Vector3.new(22, 1.2, 5),
						f * CFrame.new(x / 2, y + 12, z) * CFrame.Angles(0, 0, math.rad(if x < 0 then 12 else -12)),
						palette[1],
						floor,
						"ThemePrimary"
					)
				end
			elseif designId == "BDS_003" then
				for _, x in { -19, -13, 13, 19 } do
					part(
						style,
						"TideglassBlade",
						Vector3.new(1, 13, 3),
						f * CFrame.new(x, y + 7, z),
						palette[2],
						floor,
						"ThemeAccent"
					)
				end
			elseif designId == "BDS_004" then
				for i = 1, 3 do
					part(
						style,
						"BoglightTerrace",
						Vector3.new(30 - i * 5, 1.6, 5 + i * 2),
						f * CFrame.new(0, y + 10 + i * 1.4, z),
						palette[1],
						floor,
						"ThemePrimary"
					)
				end
			elseif designId == "BDS_005" then
				for _, x in { -18, 18 } do
					part(
						style,
						"CanopyTower",
						Vector3.new(4, 16, 4),
						f * CFrame.new(x, y + 8, z),
						palette[1],
						floor,
						"ThemePrimary"
					)
					part(
						style,
						"CanopyCrown",
						Vector3.new(6, 2, 6),
						f * CFrame.new(x, y + 17, z),
						palette[2],
						floor,
						"ThemeAccent"
					)
				end
			elseif designId == "BDS_006" then
				for i = -3, 3 do
					part(
						style,
						"FrostBattlement",
						Vector3.new(3, 4, 3),
						f * CFrame.new(i * 5, y + 13, z),
						palette[2],
						floor,
						"ThemeAccent"
					)
				end
			elseif designId == "BDS_007" then
				for _, x in { -16, 16 } do
					part(
						style,
						"MagmaButtress",
						Vector3.new(5, 13, 5),
						f * CFrame.new(x, y + 7, z) * CFrame.Angles(0, 0, math.rad(if x < 0 then -12 else 12)),
						palette[1],
						floor,
						"ThemePrimary"
					)
				end
				part(
					style,
					"MagmaBand",
					Vector3.new(w - 4, 1, 2),
					f * CFrame.new(0, y + 11, z),
					palette[2],
					floor,
					"ThemeAccent"
				)
			elseif designId == "BDS_008" then
				for _, x in { -16, 16 } do
					part(
						style,
						"AstralSpire",
						Vector3.new(2, 17, 2),
						f * CFrame.new(x, y + 9, z),
						palette[1],
						floor,
						"ThemePrimary"
					)
					part(
						style,
						"AstralDiamond",
						Vector3.new(3, 3, 3),
						f * CFrame.new(x, y + 18, z) * CFrame.Angles(0, 0, math.pi / 4),
						palette[2],
						floor,
						"ThemeAccent"
					)
				end
			end
		end
		style.Parent = architecture
	end
	for _, p in architecture:GetDescendants() do
		if p:IsA("BasePart") then
			local floor = p:GetAttribute("Phase13Floor") or 0
			local role = p:GetAttribute("Phase13Role")
			SlotPresentation.BindStage(p, base, floor, token)
			local original = p:GetAttribute("Phase13StructuralColor")
			if typeof(original) ~= "Color3" then
				original = p.Color
				p:SetAttribute("Phase13StructuralColor", original)
			end
			local canonical = if role == "ThemePrimary"
				then palette[1]
				elseif role == "ThemeAccent" then palette[2]
				else original
			p.Color = AppearanceRules.Color(canonical, finish, p.Name, FinishRoles.Base(p))
		end
	end
	for _, p in base:GetChildren() do
		local index = p:GetAttribute("SlotIndex")
		if p:IsA("BasePart") and type(index) == "number" then
			p:SetAttribute("Phase13LockedSlot", index > capacity)
			SlotPresentation.BindSlot(p, base, index, token)
			local original = firstColor(base, index)
			p.Color = if index > capacity
				then Color3.fromRGB(75, 73, 81)
				else AppearanceRules.Color(original, finish, p.Name, FinishRoles.Base(p))
		elseif p:IsA("BasePart") and p.Transparency < 1 then
			-- The starter design has no themed accent or visible upper architecture.
			-- Its existing exterior must still show the purchased finish at capacity12.
			local original = p:GetAttribute("Phase13ExteriorColor")
			if typeof(original) ~= "Color3" then
				original = p.Color
				p:SetAttribute("Phase13ExteriorColor", original)
			end
			p.Color = AppearanceRules.Color(original, finish, p.Name, FinishRoles.Base(p))
		end
	end
	-- Cash plaques are semantic slot companions under IncomePlaques, outside each pad.
	for _, companion in base:GetDescendants() do
		local index = companion:GetAttribute("BaseSlotIndex")
		if type(index) == "number" and companion.Parent ~= base then
			SlotPresentation.BindSlot(companion, base, index, token)
		end
	end
	SlotPresentation.Publish(base, token, capacity)
	base:SetAttribute("Phase13Capacity", capacity)
	base:SetAttribute("SelectedBaseDesignId", designId)
	require(game:GetService("ReplicatedStorage").Shared.Utility.PlaytestSurfacePolicy).ApplyBase(base, designId, finish)
	return true
end
return Geometry
