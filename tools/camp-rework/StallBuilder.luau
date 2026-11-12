--!nocheck
-- Camp Rework, Part B (owner-approved 11–12 Nov 2026). Studio Edit-mode builder ONLY.
-- Prepares the four approved stalls from ServerStorage._ConceptBooth.Stalls for the camp:
--   strip concept-only parts, pivot at ground level under the counter/deck with LookVector = the
--   customer-facing front, set part properties, normalise SurfaceGui text plates, mark the
--   runtime slots (weapon racks, back wall, medal pedestals, turntable, Training bay, speedometer),
--   group animated assemblies, and cut to ≤ 600 BaseParts.
-- Output: unparented Models named Kiosk_WeaponHarpoonStall / Kiosk_BuyCartStall / Kiosk_SellStall /
-- Kiosk_TrainingStall. Part C places them from Config/CampLayout.
local SS = game:GetService("ServerStorage")

local B = {}
B.Budget = 600
B.Target = 560 -- leave headroom for client-side props (rack weapons, featured cart)
B.GroundY = 600 -- concept booth ground top

B.Stalls = {
	Weapons = { source = "WeaponsStall", name = "Kiosk_WeaponHarpoonStall", category = "Weapon", object = "WEAPONS" },
	Carts = { source = "CartsStall", name = "Kiosk_BuyCartStall", category = "Cart", object = "CARTS" },
	Sell = { source = "SellStallV3", name = "Kiosk_SellStall", category = "Sell", object = "SELL" },
	Training = { source = "TrainStallV1", name = "Kiosk_TrainingStall", category = "Training", object = "TRAINING" },
}

-- Concept-only screenshot parts (prompt §1) plus rejected/no-sticker pieces.
local STRIP_EXACT = { Grass = true, Path = true, Yard = true, NewPlank = true, NewNail = true,
	-- decoration scattered on the concept's screenshot yard/path slabs (the camp floor replaces them)
	GrassTuft = true, PathStone = true,
	-- the rope fence around the concept's screenshot yard
	YardPost = true, YardPostCap = true, YardRope = true }

-- Dense repeats thinned first (keep every other member, never below 3), in this order, so every
-- approved element of the stall survives with lighter detail instead of whole elements disappearing.
local THIN_ORDER = {
	Carts = { "GearTooth", "PinionTooth", "SpareSpoke", "Rivet", "FestoonWire", "FestoonCap", "FestoonBulb",
		"RoofMoss", "Moss", "Rust", "CrateSlat", "Roller", "Batten", "HayTwine", "CrankSpoke", "HeldSpoke",
		"LevelNotch", "LoftHay", "MillBrace", "PatchPlank", "CargoRope" },
}
local STRIP_PREFIX = { "Plaza", "Pad" }

-- CanCollide=true only on posts/frames, counters, the Training deck + ramp, barn walls + roof.
local COLLIDE = {
	Weapons = { "Post", "WallBeam", "RackPost", "RackFoot", "CounterTop", "CounterPlank", "CounterBase" },
	Carts = { "BarnBoard", "Batten", "Trim", "Gable", "RoofSlab", "Shingle", "RoofRidge", "DoorBoard", "DoorTrim",
		"DoorX", "LoftDoor", "LoftTrim", "LeanPost", "FencePost", "YardPost", "LampPost", "MillLeg", "BarnFloor" },
	Sell = { "Skid", "Leg", "Brace", "TopBeam", "Counter", "CounterTop", "CounterTrim", "SignPost" },
	Training = { "DeckL", "DeckR", "DeckMid", "DeckEdge", "DeckBack", "Ramp", "Pit", "PitSide", "PitRail", "Roller",
		"Brace", "TopRail", "CrossBeam", "SignPost", "GaugePost" },
}

-- Never removed while cutting parts.
local PROTECT = { "Sign", "Counter", "Gauge", "Needle", "Roller", "Ramp", "Deck", "Pit", "Turn", "Mill", "Post",
	"Barn", "Canopy", "Awning", "Boiler", "Chimney", "FXHolder", "Hitched", "Medal", "Pedestal", "Slot",
	-- structure: decimating these opens holes in roofs and walls
	"Shingle", "Roof", "Gable", "Batten", "Trim", "Door", "Loft", "Wall", "Valance", "Rack", "Lantern", "Pallet" }

local function startsWithAny(name, list)
	for _, p in list do
		if string.sub(name, 1, #p) == p then
			return true
		end
	end
	return false
end

local function parts(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function hasFx(p)
	for _, c in p:GetDescendants() do
		if c:IsA("ParticleEmitter") or c:IsA("SurfaceGui") or c:IsA("Light") or c:IsA("Beam") or c:IsA("Attachment") then
			return true
		end
	end
	return false
end

local function marker(parent, name, cf, size, attrs)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.one * 0.4
	p.CFrame = cf
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	for k, v in attrs or {} do
		p:SetAttribute(k, v)
	end
	p.Parent = parent
	return p
end

-- Slot frame for a removed display weapon: Z = longest axis, X = the axis facing the front.
local function slotFrame(model)
	local cf, size = model:GetBoundingBox()
	local axes = { { cf.RightVector, size.X }, { cf.UpVector, size.Y }, { cf.LookVector, size.Z } }
	table.sort(axes, function(a, b)
		return a[2] > b[2]
	end)
	local long = axes[1][1]
	local front = Vector3.zAxis
	local side = if math.abs(axes[2][1]:Dot(front)) > math.abs(axes[3][1]:Dot(front)) then axes[2] else axes[3]
	local other = if side == axes[2] then axes[3] else axes[2]
	local x = if side[1]:Dot(front) < 0 then -side[1] else side[1]
	local z = long
	local y = z:Cross(x)
	if y.Y < 0 then
		y, z = -y, -z
	end
	return CFrame.fromMatrix(cf.Position, x, y, -z), axes[1][2], other[2]
end

-- Collapse a bevelled plank (2 boxes + 4 chamfer wedges with one name, consecutive) into one box of
-- the group's bounding size: same silhouette at camp distances, 5 fewer parts.
local function collapseBevels(root, budgetLeft)
	local saved = 0
	local children = root:GetChildren()
	local i = 1
	while i <= #children - 5 and saved < budgetLeft do
		local a = children[i]
		local run = { a }
		if a:IsA("Part") and not hasFx(a) and not startsWithAny(a.Name, { "Sign" }) then
			for j = i + 1, i + 5 do
				local c = children[j]
				if c and c.Name == a.Name and c:IsA("BasePart") and not hasFx(c) then
					table.insert(run, c)
				else
					break
				end
			end
		end
		local wedges = 0
		for _, c in run do
			if c:IsA("WedgePart") then
				wedges += 1
			end
		end
		if #run == 6 and wedges == 4 then
			-- bounding box in the first part's frame
			local frame = a.CFrame
			local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
			for _, c in run do
				local l = frame:ToObjectSpace(c.CFrame)
				local h = c.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local p = l * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
							mn = mn:Min(p)
							mx = mx:Max(p)
						end
					end
				end
			end
			-- colour of the largest box wins
			table.sort(run, function(x, y)
				return x.Size.Magnitude > y.Size.Magnitude
			end)
			local keep = run[1]
			if keep:IsA("Part") then
				keep.Size = mx - mn
				keep.CFrame = frame * CFrame.new((mn + mx) / 2)
				for k = 2, #run do
					run[k]:Destroy()
				end
				saved += 5
				i += 6
				continue
			end
		end
		i += 1
	end
	return saved
end

-- Merge pairs of same-look boxes (direct children) that share a full face along one axis.
local function mergeBoxes(root)
	local list = {}
	for _, p in root:GetChildren() do
		if p.ClassName == "Part" and p.Shape == Enum.PartType.Block and not hasFx(p) and #p:GetChildren() == 0
			and not startsWithAny(p.Name, { "Sign", "Roller", "Needle", "Gauge" }) then
			table.insert(list, p)
		end
	end
	local alive = {}
	for _, p in list do
		alive[p] = true
	end
	local merged = 0
	local eps = 0.02
	for i = 1, #list do
		local a = list[i]
		for j = i + 1, #list do
			local b = list[j]
			if alive[a] and alive[b] and a.Color == b.Color and a.Material == b.Material
				and a.MaterialVariant == b.MaterialVariant and math.abs(a.Transparency - b.Transparency) < 1e-3 then
				local r = a.CFrame.Rotation:ToObjectSpace(b.CFrame.Rotation)
				local rx, ry, rz = r:ToEulerAnglesXYZ()
				if math.abs(rx) < 1e-3 and math.abs(ry) < 1e-3 and math.abs(rz) < 1e-3 then
					local d = a.CFrame:PointToObjectSpace(b.Position)
					local ds, as, bs = { d.X, d.Y, d.Z }, { a.Size.X, a.Size.Y, a.Size.Z }, { b.Size.X, b.Size.Y, b.Size.Z }
					for k = 1, 3 do
						local ok = true
						for m = 1, 3 do
							if m ~= k and (math.abs(ds[m]) > eps or math.abs(as[m] - bs[m]) > eps) then
								ok = false
							end
						end
						if ok and math.abs(ds[k]) <= (as[k] + bs[k]) / 2 + eps then
							local lo = math.min(-as[k] / 2, ds[k] - bs[k] / 2)
							local hi = math.max(as[k] / 2, ds[k] + bs[k] / 2)
							local size = { as[1], as[2], as[3] }
							size[k] = hi - lo
							local c = { 0, 0, 0 }
							c[k] = (lo + hi) / 2
							a.Size = Vector3.new(size[1], size[2], size[3])
							a.CFrame = a.CFrame * CFrame.new(c[1], c[2], c[3])
							alive[b] = false
							b:Destroy()
							merged += 1
							break
						end
					end
				end
			end
		end
	end
	return merged
end

-- Halve the largest repeated decorative groups (same name), keeping every other member.
-- Decorative repeats that may be thinned on a given stall even though their name prefix is protected
-- elsewhere (e.g. Carts conveyor "Roller"s are decor; the Training "Roller"s are the bay).
local THIN_OK = {
	Carts = { Roller = true, RoofMoss = true, Batten = true, LoftHay = true, MillBrace = true },
}
local function halveGroups(root, target, key)
	local allow = THIN_OK[key] or {}
	local guard = 0
	while #parts(root) > target and guard < 60 do
		guard += 1
		local groups = {}
		for _, p in parts(root) do
			if p.Parent == root and (allow[p.Name] or not startsWithAny(p.Name, PROTECT)) and not hasFx(p) then
				groups[p.Name] = groups[p.Name] or {}
				table.insert(groups[p.Name], p)
			end
		end
		local best, n = nil, 5
		for _, g in groups do
			if #g > n then
				best, n = g, #g
			end
		end
		if not best then
			break
		end
		for i = 2, #best, 2 do
			best[i]:Destroy()
		end
	end
end

local function dropSmallest(root, target)
	local list = {}
	for _, p in parts(root) do
		if not startsWithAny(p.Name, PROTECT) and not hasFx(p) and p.Parent == root then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.Size.Magnitude < b.Size.Magnitude
	end)
	local count = #parts(root)
	for _, p in list do
		if count <= target then
			break
		end
		p:Destroy()
		count -= 1
	end
end

-- Frozen screenshot emitters become live ones (Lifetime 0.6–1.5, a real Rate; EmitOnEvent bursts).
local function liveEmitters(root)
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local burst = d:GetAttribute("Burst")
			d:SetAttribute("Burst", nil)
			d.Lifetime = NumberRange.new(0.6, 1.5)
			d.Rate = if burst then 4 else 3
			if burst then
				d:SetAttribute("EmitOnEvent", 10)
			end
		elseif d:IsA("Highlight") then
			d:Destroy() -- Highlight budget (≤31 active) belongs to gameplay, not stall art
		end
	end
end

-- SurfaceGui text plates: PixelsPerStud ~40, ≥0.12 thick, LightInfluence 0.
local function textPlates(root)
	for _, g in root:GetDescendants() do
		if g:IsA("SurfaceGui") then
			local p = g.Parent
			g.LightInfluence = 0
			g.MaxDistance = 400 -- 0 hid the text beyond ~15 studs
			local scaled = true
			for _, l in g:GetDescendants() do
				if l:IsA("GuiObject") and (l.Size.X.Offset ~= 0 or l.Size.Y.Offset ~= 0) and l.Parent == g then
					scaled = false
				end
			end
			if scaled then
				g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				g.PixelsPerStud = 40
			end
			if p:IsA("BasePart") and p.Size.Z < 0.12 and (g.Face == Enum.NormalId.Back or g.Face == Enum.NormalId.Front) then
				-- thicken toward the back so the text face stays where it was
				local grow = 0.12 - p.Size.Z
				-- Back = +Z face: shift the centre -Z so the +Z (text) face stays; Front = -Z face: shift +Z.
				local dir = if g.Face == Enum.NormalId.Back then -1 else 1
				p.Size = Vector3.new(p.Size.X, p.Size.Y, 0.12)
				p.CFrame = p.CFrame * CFrame.new(0, 0, dir * grow / 2)
			end
		end
	end
end

local function finishProperties(root, key)
	local collide = COLLIDE[key]
	for _, p in parts(root) do
		p.Anchored = true
		p.CanTouch = false
		local structural = startsWithAny(p.Name, collide) and p.Transparency < 1
		if p:GetAttribute("CampSlot") or p:GetAttribute("CampAnchor") then
			structural = false
		end
		p.CanCollide = structural
		p.CanQuery = structural
		if math.max(p.Size.X, p.Size.Y, p.Size.Z) < 1 then
			p.CastShadow = false
		end
	end
end

-- Group parts into an animated assembly Model with a PrimaryPart pivot.
local function assembly(root, name, filter, pivotCF, attrs)
	local m = Instance.new("Model")
	m.Name = name
	local hub = Instance.new("Part")
	hub.Name = "Pivot"
	hub.Size = Vector3.one * 0.2
	hub.Transparency = 1
	hub.Anchored = true
	hub.CanCollide, hub.CanQuery, hub.CanTouch, hub.CastShadow = false, false, false, false
	hub.CFrame = pivotCF
	hub.Parent = m
	m.PrimaryPart = hub
	for _, p in root:GetChildren() do
		if p:IsA("BasePart") and filter(p) then
			p.Parent = m
		end
	end
	for k, v in attrs do
		m:SetAttribute(k, v)
	end
	m.Parent = root
	return m
end

local function centroid(list)
	local s = Vector3.zero
	for _, p in list do
		s += p.Position
	end
	return s / math.max(1, #list)
end

local function named(root, prefixes)
	local out = {}
	for _, p in root:GetChildren() do
		if p:IsA("BasePart") and startsWithAny(p.Name, prefixes) then
			table.insert(out, p)
		end
	end
	return out
end

local function weaponsSlots(m)
	local slots = Instance.new("Folder")
	slots.Name = "CampSlots"
	slots.Parent = m
	local rack, wall = 0, 0
	for _, c in m:GetChildren() do
		if c:IsA("Model") and (c.Name == "RackWeapon" or c.Name == "Display") then
			local frame, length, thickness = slotFrame(c)
			local kind = if c.Name == "RackWeapon" then "Rack" else "Wall"
			local index
			if kind == "Rack" then
				rack += 1
				index = rack
			else
				wall += 1
				index = wall
			end
			marker(slots, kind .. "Slot_" .. index, frame, Vector3.new(0.2, 0.2, length),
				{ CampSlot = kind, SlotIndex = index, SlotLength = length, SlotThickness = thickness })
			c:Destroy()
		end
	end
	-- rack slots read left-to-right from the front (x ascending)
	local function order(kind)
		local list = {}
		for _, s in slots:GetChildren() do
			if s:GetAttribute("CampSlot") == kind then
				table.insert(list, s)
			end
		end
		table.sort(list, function(a, b)
			return a.Position.X < b.Position.X
		end)
		for i, s in list do
			s.Name = kind .. "Slot_" .. i
			s:SetAttribute("SlotIndex", i)
		end
	end
	order("Rack")
	order("Wall")
	-- Medal pedestals for the Won specials (bronze / silver / gold), inside the stall front corner.
	-- Boxes only, no text. Greyed until earned (client).
	local counter = centroid(named(m, { "CounterTop" }))
	local medals = { { "Bronze", Color3.fromRGB(176, 112, 58) }, { "Silver", Color3.fromRGB(196, 204, 214) }, { "Gold", Color3.fromRGB(240, 192, 64) } }
	local pedestals = Instance.new("Model")
	pedestals.Name = "MedalPedestals"
	pedestals.Parent = m
	for i, row in medals do
		local x = counter.X - 7 + (i - 1) * 2.4
		local base = Instance.new("Part")
		base.Name = "PedestalBase"
		base.Size = Vector3.new(1.9, 1.1 + (i - 1) * 0.35, 1.9)
		base.CFrame = CFrame.new(x, B.GroundY + base.Size.Y / 2, counter.Z - 2.6)
		base.Color = Color3.fromRGB(92, 62, 40)
		base.Material = Enum.Material.WoodPlanks
		base.Parent = pedestals
		local top = Instance.new("Part")
		top.Name = "PedestalMedal" .. row[1]
		top.Size = Vector3.new(2.1, 0.22, 2.1)
		top.CFrame = base.CFrame * CFrame.new(0, base.Size.Y / 2 + 0.11, 0)
		top.Color = row[2]
		top.Material = Enum.Material.Metal
		top:SetAttribute("MedalColor", row[2])
		top.Parent = pedestals
		local trim = Instance.new("Part")
		trim.Name = "PedestalTrim"
		trim.Size = Vector3.new(2.0, 0.16, 2.0)
		trim.CFrame = base.CFrame * CFrame.new(0, -base.Size.Y / 2 + 0.08, 0)
		trim.Color = row[2]
		trim.Material = Enum.Material.Metal
		trim.Parent = pedestals
		marker(slots, "MedalSlot_" .. i, CFrame.new(top.Position + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-20), 0, 0),
			Vector3.new(0.2, 0.2, 2.6), { CampSlot = "Medal", SlotIndex = i, Medal = row[1], SlotLength = 2.6 })
	end
end

local function cartsRig(m)
	-- Windmill sails spin; turntable carries the client-side featured cart; boiler steams.
	local hub = nil
	for _, p in m:GetChildren() do
		if p.Name == "MillHub" then
			hub = p
		end
	end
	if hub then
		local thin = if hub.Size.X <= hub.Size.Y and hub.Size.X <= hub.Size.Z then hub.CFrame.RightVector
			elseif hub.Size.Y <= hub.Size.Z then hub.CFrame.UpVector
			else hub.CFrame.LookVector
		local pivot = CFrame.lookAt(hub.Position, hub.Position + thin)
		assembly(m, "WindmillRotor", function(p)
			return p == hub or startsWithAny(p.Name, { "MillArm", "MillSail", "MillLattice" })
		end, pivot, { CampAnim = "Spin", CampAnimRate = 45 })
	end
	local deck = m:FindFirstChild("TurnDeck")
	local featured
	for _, c in m:GetChildren() do
		if c:IsA("Model") and c.Name == "DisplayCart" and deck then
			local cf = c:GetBoundingBox()
			if not featured or (cf.Position - deck.Position).Magnitude < (featured:GetBoundingBox().Position - deck.Position).Magnitude then
				featured = c
			end
		end
	end
	if deck then
		local slots = Instance.new("Folder")
		slots.Name = "CampSlots"
		slots.Parent = m
		-- the deck is a cylinder: its thickness is its smallest axis, not Size.Y
		local thickness = math.min(deck.Size.X, deck.Size.Y, deck.Size.Z)
		local turnPivot = CFrame.new(deck.Position.X, deck.Position.Y + thickness / 2, deck.Position.Z)
		local featuredCF = if featured then featured:GetPivot() else turnPivot
		marker(slots, "TurntableSlot", turnPivot, nil, { CampSlot = "Turntable",
			CartOffset = turnPivot:ToObjectSpace(featuredCF), CartScale = 0.65 })
		-- The Carts prompt sits at the front of the barn (turntable centre), reachable from the path.
		marker(slots, "CartsPromptAnchor", turnPivot + Vector3.new(0, 2.5, 0), nil, { CampAnchor = "Cart" })
		assembly(m, "TurntableRotor", function(p)
			return startsWithAny(p.Name, { "TurnDeck", "TurnPlankLine", "TurnBolt" })
		end, CFrame.lookAt(turnPivot.Position, turnPivot.Position + Vector3.yAxis, Vector3.zAxis),
			{ CampAnim = "Spin", CampAnimRate = 20 })
		if featured then
			featured:Destroy() -- the featured cart is the player's next affordable cart, client-side
		end
	end
	for _, c in m:GetChildren() do
		if c:IsA("Model") and c.Name == "DisplayCart" then
			for _, d in c:GetDescendants() do
				if d:IsA("Seat") or d:IsA("VehicleSeat") or d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then
					d:Destroy()
				end
			end
		end
	end
	-- Hitched brainrots belong to the per-player featured cart (team slot): client props, not stall parts.
	local props = Instance.new("Folder")
	props.Name = "HitchedBrainrots"
	local slotsFolder = m:FindFirstChild("CampSlots")
	local i = 0
	for _, c in m:GetChildren() do
		if c:IsA("Model") and c.Name == "HitchedBrainrot" then
			i += 1
			if slotsFolder then
				marker(slotsFolder, "HitchSlot_" .. i, c:GetPivot(), nil, { CampSlot = "Hitch", SlotIndex = i })
			end
			c.Name = "HitchedBrainrot_" .. i
			c.Parent = props
		end
	end
	B.LastProps = props
	-- Cart upgrade point (Cargo; Speed is retired by Training): the CartUpgradePointSystem needs exactly
	-- one BasePart tagged CartUpgradeStall. It used to be the BuyCartStall pad; now the anvil workbench.
	local anvil = m:FindFirstChild("Anvil") or m:FindFirstChild("Bench")
	if anvil then
		local a = marker(m:FindFirstChild("CampSlots") or m, "CartUpgradeAnchor",
			CFrame.new(anvil.Position.X, B.GroundY + 2.5, anvil.Position.Z), Vector3.one, { CampUpgradeAnchor = true })
		game:GetService("CollectionService"):AddTag(a, "CartUpgradeStall")
	end
	-- boiler steam: emitters closest to the chimney top
	local chimney = m:FindFirstChild("Chimney")
	if chimney then
		for _, p in m:GetDescendants() do
			if p.Name == "FXHolder" and p:IsA("BasePart") and (p.Position - chimney.Position).Magnitude < 6 then
				p:SetAttribute("CampSteam", true)
			end
		end
	end
end

local function trainingRig(m)
	for _, c in m:GetChildren() do
		if c:IsA("Model") and c.Name == "DisplayCart" then
			c:Destroy() -- screenshot prop: the bay is for the player's own cart
		end
	end
	local slots = Instance.new("Folder")
	slots.Name = "CampSlots"
	slots.Parent = m
	local pit = m:FindFirstChild("Pit")
	local rollers = named(m, { "Roller" })
	local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in rollers do
		mn = mn:Min(p.Position - p.Size / 2)
		mx = mx:Max(p.Position + p.Size / 2)
	end
	if pit then
		mn = mn:Min(pit.Position - pit.Size / 2)
		mx = mx:Max(pit.Position + pit.Size / 2)
	end
	-- Roller trigger box: covers the pit footprint, from the roller tops up to wheel height.
	local size = Vector3.new(mx.X - mn.X + 1, 4, mx.Z - mn.Z + 1)
	marker(slots, "RollerTrigger", CFrame.new((mn.X + mx.X) / 2, mx.Y + 1.6, (mn.Z + mx.Z) / 2), size,
		{ CampSlot = "RollerTrigger" })
	for i, r in rollers do
		r:SetAttribute("CampRoller", true)
		local axis = if r.Size.X >= r.Size.Y and r.Size.X >= r.Size.Z then r.CFrame.RightVector
			elseif r.Size.Y >= r.Size.Z then r.CFrame.UpVector else r.CFrame.LookVector
		r:SetAttribute("CampRollerAxis", axis)
	end
	for _, b in named(m, { "RollerBand" }) do
		b:SetAttribute("CampRoller", true)
	end
	-- Speedometer: needle pivots about the hub along the face normal; 225° − 270° × (level/25).
	local hub = m:FindFirstChild("NeedleHub")
	local face = m:FindFirstChild("GaugeFace")
	if hub and face then
		local needle = assembly(m, "SpeedNeedle", function(p)
			return p.Name == "Needle" or p.Name == "NeedleCap"
		end, CFrame.lookAt(hub.Position, hub.Position + Vector3.zAxis, Vector3.yAxis), { CampAnim = "Needle" })
		needle:SetAttribute("NeedleRestDegrees", 225)
	end
	local lamp = m:FindFirstChild("GaugeLamp")
	if lamp then
		lamp:SetAttribute("CampLamp", true)
	end
	local post = m:FindFirstChild("GaugePost")
	if post then
		marker(slots, "TrainingPromptAnchor", CFrame.new(post.Position + Vector3.new(0, 0, 0.6)), nil, { CampAnchor = "Training" })
	end
end

local function sellRig(m)
	local slots = Instance.new("Folder")
	slots.Name = "CampSlots"
	slots.Parent = m
	local counter = m:FindFirstChild("Counter")
	if counter then
		marker(slots, "CoinBurst", CFrame.new(counter.Position + Vector3.new(0, counter.Size.Y / 2 + 0.6, 0)), nil, { CampSlot = "CoinBurst" })
	end
end

-- Build one stall. Returns the prepared Model (unparented) and a report.
function B.Build(key)
	local spec = B.Stalls[key]
	local source = SS._ConceptBooth.Stalls[spec.source]
	local before = #parts(source)
	local m = source:Clone()
	m.Name = spec.name
	for _, c in m:GetChildren() do
		if STRIP_EXACT[c.Name] or startsWithAny(c.Name, STRIP_PREFIX) then
			c:Destroy()
		end
	end
	liveEmitters(m)
	if key == "Weapons" then
		weaponsSlots(m)
	elseif key == "Carts" then
		cartsRig(m)
	elseif key == "Training" then
		trainingRig(m)
	elseif key == "Sell" then
		sellRig(m)
	end
	textPlates(m)
	-- part budget
	local count = #parts(m)
	if count > B.Target then
		collapseBevels(m, count - B.Target)
	end
	if #parts(m) > B.Target then
		for _ = 1, 3 do
			if mergeBoxes(m) == 0 or #parts(m) <= B.Target then
				break
			end
		end
	end
	for _ = 1, 4 do
		if #parts(m) <= B.Target then
			break
		end
		for _, name in THIN_ORDER[key] or {} do
			if #parts(m) <= B.Target then
				break
			end
			local members = {}
			for _, p in m:GetChildren() do
				if p:IsA("BasePart") and p.Name == name and not hasFx(p) then
					table.insert(members, p)
				end
			end
			if #members > 3 then
				for i = 2, #members, 2 do
					members[i]:Destroy()
				end
			end
		end
	end
	if #parts(m) > B.Target then
		halveGroups(m, B.Target, key)
	end
	if #parts(m) > B.Target then
		dropSmallest(m, B.Target)
	end
	finishProperties(m, key)
	-- pivot: ground level, centred under the counter/deck, LookVector = customer-facing front (+Z)
	local centreParts = if key == "Weapons" then named(m, { "CounterTop" })
		elseif key == "Carts" then named(m, { "BarnFloor" })
		elseif key == "Sell" then named(m, { "Counter" })
		else named(m, { "DeckMid" })
	local c = centroid(centreParts)
	local root = Instance.new("Part")
	root.Name = "StallRoot"
	root.Size = Vector3.new(1, 0.2, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide, root.CanQuery, root.CanTouch, root.CastShadow = false, false, false, false
	root.CFrame = CFrame.lookAt(Vector3.new(c.X, B.GroundY, c.Z), Vector3.new(c.X, B.GroundY, c.Z + 1))
	root.Parent = m
	m.PrimaryPart = root
	-- Stream the whole stall at once so client bindings (gauge, racks, turntable) see every part.
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m:SetAttribute("CampReworkStall", key)
	m:SetAttribute("CampCategory", spec.category)
	m:SetAttribute("CampObjectText", spec.object)
	-- footprint (local, for spawn exclusion and layout spacing)
	local cf, size = m:GetBoundingBox()
	m:SetAttribute("FootprintSize", Vector3.new(size.X, 0, size.Z))
	m:SetAttribute("FootprintOffset", root.CFrame:PointToObjectSpace(cf.Position) * Vector3.new(1, 0, 1))
	return m, { key = key, before = before, after = #parts(m) }
end

return B
