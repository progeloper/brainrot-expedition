--!nocheck
-- Camp Rework, Part A (owner-approved 11–12 Nov 2026). Studio Edit-mode builder ONLY.
-- Converts the approved concept weapons in ServerStorage._ConceptBooth into held Tool templates
-- (ReplicatedStorage.CodeAssets.Weapons.<ID>) and anchored 1.5x rack displays
-- (ReplicatedStorage.CodeAssets.WeaponDisplays.<ID>). Never required at runtime; the concept
-- booth/kits stay in ServerStorage as reference.
--
-- Pipeline per weapon:
--   1. clone the concept model and strip screenshot staging (backdrop, floor, pedestal, floor ring,
--      shard fan, lightning, sky beam, embers/ash/aurora/snow orbit, medal stands, confetti, star
--      holders) + outliers. Tier 7 keeps its stars, eclipse and orbit rocks (no smoke/mist).
--   2. build the weapon frame (grip centre, forward = barrel/arrow, up) and map it onto the Handle:
--      forward -> Handle -Z, up -> +Y, grip -> Tool.Grip point (0, -0.3, 0.5).
--   3. scale so the longest core axis = Bow 4.6 / Crossbow 5.0 / Blaster 4.2 (+10% for T8 + specials).
--   4. cut parts: drop specks/hairlines, merge same-colour coplanar boxes, halve long repeated
--      chains (stretching the survivors to close gaps), then drop the least visible parts. ≤150.
--   5. rig SPINS/MOVES groups onto one invisible rotor per group (one Weld motor each) so the
--      client scheduler animates one C0 per group.
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")

local M = {}
M.Budget = 150
M.HardCap = 220
M.GripPoint = Vector3.new(0, -0.3, 0.5)
M.Target = { Bow = 4.6, Crossbow = 5.0, Gun = 4.2 }
M.DisplayScale = 1.5

-- id, concept path, family, tier, special?
M.Map = {
	{ "HRP_001", "Tier1/TrailwoodBow", "Bow", 1 },
	{ "WPN_B02", "Tier2/CopperstringBow", "Bow", 2 },
	{ "WPN_B03", "Tier3/HorizonBow", "Bow", 3 },
	{ "WPN_B04", "Tier4/ThorncrestBow", "Bow", 4 },
	{ "WPN_B05", "Tier5/PrismstringBow", "Bow", 5 },
	{ "WPN_B06", "Tier6/FrostbranchBow", "Bow", 6 },
	{ "WPN_B07", "Tier7/SolarhornBow", "Bow", 7 },
	{ "WPN_B08", "Tier8/RiftcrownBow", "Bow", 8 },
	{ "WPN_C02", "Tier2/TwinrailCrossbow", "Crossbow", 2 },
	{ "WPN_C03", "Tier3/FarwatchCrossbow", "Crossbow", 3 },
	{ "WPN_C04", "Tier4/IronbloomCrossbow", "Crossbow", 4 },
	{ "WPN_C05", "Tier5/VoltspineCrossbow", "Crossbow", 5 },
	{ "WPN_C06", "Tier6/GlacierlockCrossbow", "Crossbow", 6 },
	{ "WPN_C07", "Tier7/SunforgeCrossbow", "Crossbow", 7 },
	{ "WPN_C08", "Tier8/VoidcrestCrossbow", "Crossbow", 8 },
	{ "WPN_G02", "Tier2/ZipfireBlaster", "Gun", 2 },
	{ "WPN_G03", "Tier3/LonglineBlaster", "Gun", 3 },
	{ "WPN_G04", "Tier4/NeonpulseBlaster", "Gun", 4 },
	{ "WPN_G05", "Tier5/SparkstormBlaster", "Gun", 5 },
	{ "WPN_G06", "Tier6/FrostlineBlaster", "Gun", 6 },
	{ "WPN_G07", "Tier7/SunburstBlaster", "Gun", 7 },
	{ "WPN_G08", "Tier8/RiftflareBlaster", "Gun", 8 },
	{ "WPN_SP_RIFTBLASTER", "Premium/RiftBlaster", "Gun", 5, "Rift Blaster" },
	{ "WPN_SP_PRISMREPEATER", "Premium/PrismRepeater", "Crossbow", 4, "Prism Repeater" },
	{ "WPN_SP_CRYSTALLANCE", "Premium/CrystalLance", "Crossbow", 6, "Crystal Lance" },
	{ "WPN_SP_COLLECTORSBOW", "Won/CollectorsBow", "Bow", 3, "Collector's Bow" },
	{ "WPN_SP_GETAWAY", "Won/GetawayCrossbow", "Crossbow", 5, "Getaway Crossbow" },
	{ "WPN_SP_SECRETHUNTER", "Won/SecretHunterBlaster", "Gun", 7, "Secret Hunter Blaster" },
}

-- Screenshot staging (top-level children of the concept model).
local STAGE_EXACT = {
	Backdrop = true, Floor = true, Pedestal = true, PedTop = true, Ring = true, Shard = true, Bit = true,
	Part = true, Bolt = true, Ember = true, SkyBeam = true, AshSpiral = true, Ash = true, Aurora = true,
	SnowSpiral = true, StageGeo = true, Grass = true, Path = true, Yard = true, CoronaRay = true,
	EclipseDisc = true, EclipseRim = true, EclipseRimGlow = true, OrbitRock = true, OrbitRockSeam = true,
}
local STAGE_PREFIX = { "Ped", "Medal", "OrbitFlake", "Plaza", "Pad" }
-- Tier 7 keeps its stars (emitter holders), eclipse and orbit rocks.
local T7_KEEP = { Part = "Star", EclipseDisc = "Eclipse", EclipseRim = "Eclipse", EclipseRimGlow = "Eclipse",
	CoronaRay = "Eclipse", OrbitRock = "Orbit", OrbitRockSeam = "Orbit" }
-- Floating details stay only when they hover close to the weapon body.
local FLOAT_PREFIX = { "Float", "Floater", "Firefly", "Cloud" }
-- Never cut these while reducing.
local PROTECT_PREFIX = { "Grip", "GripCore", "Handle", "Shaft", "ArrowShaft", "BoltShaft", "RailBed", "Barrel",
	"BodyUp", "Body", "Stock", "Riser", "String", "Lance", "Hull", "Canopy", "Screen", "MuzzleOrb", "VoidCore",
	"DrumAxle", "Trigger" }

-- SPINS / MOVES from the approved sheets. kind: Spin (continuous), Pump (continuous piston),
-- FirePump (on each shot), FireStep (Prism Repeater: one 60 degree slot per shot).
-- axis: "auto" (ring normal) | "X" | "Y" | "Z" (Handle space). clusters: split by position.
M.Anim = {
	WPN_B04 = { { kind = "Spin", names = { "TurbBlade", "TurbHub", "TurbRim" }, clusters = 2, rate = 220 },
		{ kind = "Spin", names = { "Gyro" }, axis = "Y", rate = 90 } },
	WPN_C04 = { { kind = "Spin", names = { "DrumCore", "DrumBolt", "DrumHead", "DrumRing" }, axis = "Z", rate = 120 },
		{ kind = "FirePump", names = { "Petal", "PetalEdge" }, distance = 0.08 } },
	WPN_G04 = { { kind = "Spin", names = { "Barrel", "BarrelBore" }, axis = "Z", rate = 240 },
		{ kind = "Spin", names = { "IntakeBlade", "IntakeHub" }, rate = 300 },
		{ kind = "Spin", names = { "Gear1", "Gear1T", "Gear1C" }, rate = 120 },
		{ kind = "Spin", names = { "Gear2", "Gear2T", "Gear2C" }, rate = -150 },
		{ kind = "Spin", names = { "Gear3", "Gear3T", "Gear3C" }, rate = 180 },
		{ kind = "FirePump", names = { "PistonRod", "PistonCap" }, axis = "Z", distance = 0.1 } },
	WPN_B05 = { { kind = "Spin", names = { "TipSun", "TipSunRay", "TipSunGem", "TipSunGemHi" }, clusters = 2, rate = 90 } },
	WPN_B06 = { { kind = "Spin", names = { "GyroRing", "GyroRing2" }, axis = "Y", rate = 80 },
		{ kind = "Spin", names = { "TipRotor", "TipRotorHub" }, clusters = 2, rate = 240 } },
	WPN_C06 = { { kind = "Spin", names = { "DialArc", "DialFace", "DialGem", "DialHandle", "DialRing", "DialTick" }, clusters = 2, rate = 60 } },
	WPN_G06 = { { kind = "Spin", names = { "TurbineBlade", "TurbineHub", "TurbineArc" }, axis = "Z", rate = 260 } },
	WPN_B07 = { { kind = "Spin", names = { "TipArc", "TipHalo", "TipDisc" }, clusters = 2, rate = 90 },
		{ kind = "Spin", names = { "OrbitRock", "OrbitRockSeam" }, axis = "Y", rate = 30 } },
	WPN_C07 = { { kind = "Pump", names = { "HammerFace", "HammerHead", "HammerRod" }, clusters = 2, axis = "Y", distance = 0.12, rate = 1.6 },
		{ kind = "Spin", names = { "OrbitRock", "OrbitRockSeam" }, axis = "Z", rate = 30 } },
	WPN_G07 = { { kind = "Spin", names = { "RearArc", "RearHalo", "RearHub" }, axis = "Z", rate = 90 },
		{ kind = "Spin", names = { "OrbitRock", "OrbitRockSeam" }, axis = "Z", rate = 30 } },
	WPN_B08 = { { kind = "Spin", names = { "TipDisc", "TipGem" }, clusters = 2, rate = 200 } },
	WPN_C08 = { { kind = "Pump", names = { "PistonHead", "PistonFace", "PistonRod", "PistonRodCap" }, axis = "Z", distance = 0.1, rate = 1.6 } },
	WPN_G08 = { { kind = "Spin", names = { "TurbineBlade", "TurbineHub", "TurbineFace" }, axis = "Z", rate = 260 } },
	WPN_SP_RIFTBLASTER = { { kind = "Spin", names = { "PortalArc", "PortalGlow", "PortalRing", "PortalVoid", "PortalSpark" }, axis = "Z", rate = 120 },
		{ kind = "Spin", names = { "CoinArc", "CoinFace", "CoinRim", "CoinStar" }, rate = 90 } },
	WPN_SP_PRISMREPEATER = { { kind = "FireStep", names = { "DrumArc", "DrumBand", "DrumPrism", "DrumPrismCore", "DrumPrismTip", "DrumSlot", "DrumAxle" }, axis = "Z", step = 60 } },
	WPN_SP_CRYSTALLANCE = { { kind = "Spin", names = { "HaloArc", "HaloGem" }, axis = "Z", rate = 70 } },
	WPN_SP_COLLECTORSBOW = { { kind = "Spin", names = { "CompassNeedle" }, rate = 120 } },
	WPN_SP_GETAWAY = { { kind = "Spin", names = { "Tyre", "TyreWall", "Rim", "Hub", "Spoke" }, clusters = 2, rate = 300 } },
	WPN_SP_SECRETHUNTER = { { kind = "Spin", names = { "Dish", "DishEmitter", "DishArm" }, axis = "Y", rate = 90 },
		{ kind = "Spin", names = { "TrophyStar", "TrophyBack", "TrophyRim" }, axis = "Y", rate = 60 },
		{ kind = "Spin", names = { "RadarSweep" }, rate = 180 } },
}

local function startsWithAny(name, list)
	for _, p in list do
		if string.sub(name, 1, #p) == p then
			return true
		end
	end
	return false
end

local function longAxis(part)
	local s = part.Size
	if s.X >= s.Y and s.X >= s.Z then
		return part.CFrame.RightVector
	elseif s.Y >= s.Z then
		return part.CFrame.UpVector
	end
	return part.CFrame.LookVector
end

local function findPart(root, names)
	for _, n in names do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.Name == n then
				return d
			end
		end
	end
	return nil
end

-- Weapon frame: position = grip centre, LookVector = muzzle/arrow direction, UpVector = up.
function M.Frame(model, family)
	local root = model:FindFirstChild("Weapon") or model
	local G = model:GetAttribute("G") or model:GetAttribute("BodyFrame")
	local grip = findPart(root, { "GripCore", "Grip", "Handle", "Handgrip" })
	assert(grip, "no grip in " .. model.Name)
	local forward, up
	if typeof(G) == "CFrame" then
		forward = if family == "Bow" then G.RightVector else G.LookVector
		up = G.UpVector
	elseif family == "Bow" then
		local shaft = assert(findPart(root, { "Shaft", "ArrowShaft" }), "no arrow shaft")
		local head = assert(findPart(root, { "HeadBase", "Head1", "ArrowHead" }), "no arrow head")
		forward = longAxis(shaft)
		if forward:Dot(head.Position - shaft.Position) < 0 then
			forward = -forward
		end
		up = longAxis(grip)
		if up.Y < 0 then
			up = -up
		end
	else
		local body = assert(findPart(root, { "RailBed", "BarrelTop", "Barrel", "BodyUp" }), "no body axis")
		local tip = assert(findPart(root, { "BoltHead1", "BoltHead", "Nose", "HarpoonTip", "MuzzleRim", "Muzzle", "BarrelBore", "MuzzleOrb" }), "no tip")
		forward = longAxis(body)
		if forward:Dot(tip.Position - body.Position) < 0 then
			forward = -forward
		end
		up = Vector3.yAxis
	end
	forward = forward.Unit
	up = (up - forward * forward:Dot(up)).Unit
	return CFrame.lookAt(grip.Position, grip.Position + forward, up), grip
end

local function rotatedExtents(cf, size)
	-- AABB half-extents of a box in its parent frame.
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local h = size / 2
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
end

local function bboxOf(parts, frame)
	local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in parts do
		local cf = frame:ToObjectSpace(p.CFrame)
		local e = rotatedExtents(cf, p.Size)
		mn = mn:Min(cf.Position - e)
		mx = mx:Max(cf.Position + e)
	end
	return mn, mx
end

local function hasFx(part)
	for _, c in part:GetDescendants() do
		if c:IsA("ParticleEmitter") or c:IsA("Beam") or c:IsA("Light") or c:IsA("Trail") then
			return true
		end
		if c:IsA("Attachment") then
			return true -- may anchor a Beam elsewhere; keep the geometry relationship intact
		end
	end
	return false
end

local function scaleInstanceFx(inst, s)
	for _, d in inst:GetDescendants() do
		if d:IsA("Attachment") then
			d.CFrame = d.CFrame - d.CFrame.Position + d.CFrame.Position * s
		elseif d:IsA("Beam") then
			d.Width0 *= s
			d.Width1 *= s
			d.CurveSize0 *= s
			d.CurveSize1 *= s
		elseif d:IsA("ParticleEmitter") then
			local kp = {}
			for _, k in d.Size.Keypoints do
				table.insert(kp, NumberSequenceKeypoint.new(k.Time, k.Value * s, k.Envelope * s))
			end
			d.Size = NumberSequence.new(kp)
			d.Speed = NumberRange.new(d.Speed.Min * s, d.Speed.Max * s)
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Range = math.max(2, d.Range * s)
		elseif d:IsA("Texture") then
			d.StudsPerTileU *= s
			d.StudsPerTileV *= s
			d.OffsetStudsU *= s
			d.OffsetStudsV *= s
		elseif d:IsA("SpecialMesh") then
			if d.MeshType == Enum.MeshType.FileMesh then
				d.Scale *= s
			end
			d.Offset *= s
		elseif d:IsA("Highlight") then
			d:Destroy()
		end
	end
end

-- Screenshot emitters are frozen (Rate 0, Lifetime 600) or Burst-tagged. Make them live.
local function liveEmitters(inst)
	for _, d in inst:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local burst = d:GetAttribute("Burst")
			d:SetAttribute("Burst", nil)
			d.Lifetime = NumberRange.new(0.6, 1.5)
			d.Rate = if burst then 3 else 2
			d.Enabled = true
			d:SetAttribute("EmitOnFire", if burst then 6 else 3)
		end
	end
end

local function sameLook(a, b)
	return a.ClassName == "Part" and b.ClassName == "Part" and a.Shape == Enum.PartType.Block
		and b.Shape == Enum.PartType.Block and a.Color == b.Color and a.Material == b.Material
		and a.MaterialVariant == b.MaterialVariant and math.abs(a.Transparency - b.Transparency) < 1e-3
		and math.abs(a.Reflectance - b.Reflectance) < 1e-3
		and a:GetAttribute("CampAnimKey") == b:GetAttribute("CampAnimKey")
end

local function plain(p)
	for _, c in p:GetChildren() do
		if not c:IsA("Texture") then
			return false
		end
	end
	return true
end

local function sameRotation(a, b)
	local r = a.CFrame.Rotation:ToObjectSpace(b.CFrame.Rotation)
	local x, y, z = r:ToEulerAnglesXYZ()
	return math.abs(x) < 1e-3 and math.abs(y) < 1e-3 and math.abs(z) < 1e-3
end

-- Merge pairs of same-look boxes that share a full face (or overlap) along one axis.
local function mergePass(parts, eps)
	local merged = 0
	local alive = {}
	for _, p in parts do
		alive[p] = true
	end
	for i = 1, #parts do
		local a = parts[i]
		if alive[a] and plain(a) then
			for j = i + 1, #parts do
				local b = parts[j]
				if alive[b] and alive[a] and plain(b) and sameLook(a, b) and sameRotation(a, b) then
					local d = a.CFrame:PointToObjectSpace(b.Position)
					local sa, sb = a.Size, b.Size
					local ds = { d.X, d.Y, d.Z }
					local as = { sa.X, sa.Y, sa.Z }
					local bs = { sb.X, sb.Y, sb.Z }
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
							local newSize = { as[1], as[2], as[3] }
							newSize[k] = hi - lo
							local centre = { 0, 0, 0 }
							centre[k] = (lo + hi) / 2
							a.Size = Vector3.new(newSize[1], newSize[2], newSize[3])
							a.CFrame = a.CFrame * CFrame.new(centre[1], centre[2], centre[3])
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
	local out = {}
	for _, p in parts do
		if alive[p] then
			table.insert(out, p)
		end
	end
	return out, merged
end

-- Keep every other member of a long repeated group; stretch survivors toward the removed neighbour.
local function halveGroup(members)
	local removed = 0
	for i = 1, #members, 2 do
		local keep, gone = members[i], members[i + 1]
		if gone and gone.Parent then
			local d = keep.CFrame:PointToObjectSpace(gone.Position)
			local s = keep.Size
			local elongated = math.max(s.X, s.Y, s.Z) / math.max(1e-3, math.min(s.X, s.Y, s.Z)) >= 1.5
			if elongated and d.Magnitude < 3 * math.max(s.X, s.Y, s.Z) then
				local ax = { math.abs(d.X), math.abs(d.Y), math.abs(d.Z) }
				local k = if ax[1] >= ax[2] and ax[1] >= ax[3] then 1 elseif ax[2] >= ax[3] then 2 else 3
				local sz = { s.X, s.Y, s.Z }
				local longK = if sz[1] >= sz[2] and sz[1] >= sz[3] then 1 elseif sz[2] >= sz[3] then 2 else 3
				if k ~= longK then
					gone:Destroy() -- radial/fanned members: never widen a ray into a block
					removed += 1
					continue
				end
				local dv = { d.X, d.Y, d.Z }
				local lo = math.min(-sz[k] / 2, dv[k] - sz[k] / 2)
				local hi = math.max(sz[k] / 2, dv[k] + sz[k] / 2)
				sz[k] = hi - lo
				local c = { 0, 0, 0 }
				c[k] = (lo + hi) / 2
				keep.Size = Vector3.new(sz[1], sz[2], sz[3])
				keep.CFrame = keep.CFrame * CFrame.new(c[1], c[2], c[3])
			end
			gone:Destroy()
			removed += 1
		end
	end
	return removed
end

local function visibility(p)
	local s = p.Size
	local a = { s.X, s.Y, s.Z }
	table.sort(a)
	local score = a[3] * a[2]
	if p.Material == Enum.Material.Neon then
		score *= 1.4
	end
	return score
end

-- Ring-normal axis by testing candidate axes for the smallest positional spread.
local function ringAxis(parts, pivot, frame)
	local candidates = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	local p0 = parts[1]
	local r = frame:ToObjectSpace(p0.CFrame)
	for _, v in { r.RightVector, r.UpVector, r.LookVector } do
		table.insert(candidates, v)
	end
	local best, bestSpread = Vector3.zAxis, math.huge
	for _, axis in candidates do
		local spread = 0
		for _, p in parts do
			local lp = frame:PointToObjectSpace(p.Position) - pivot
			spread += math.abs(lp:Dot(axis))
		end
		if #parts == 1 then
			-- single part (needle/sweep): spin about its thinnest local axis
			local s = p0.Size
			local thin = if s.X <= s.Y and s.X <= s.Z then r.RightVector elseif s.Y <= s.Z then r.UpVector else r.LookVector
			return thin.Unit
		end
		if spread < bestSpread - 1e-4 then
			best, bestSpread = axis, spread
		end
	end
	return best.Unit
end

local function cluster(parts, k)
	if k <= 1 or #parts < k then
		return { parts }
	end
	-- 2-means on position (both-tip groups).
	local a, b = parts[1].Position, parts[1].Position
	local far = 0
	for _, p in parts do
		local d = (p.Position - a).Magnitude
		if d > far then
			far, b = d, p.Position
		end
	end
	for _ = 1, 6 do
		local ga, gb = {}, {}
		for _, p in parts do
			if (p.Position - a).Magnitude <= (p.Position - b).Magnitude then
				table.insert(ga, p)
			else
				table.insert(gb, p)
			end
		end
		local function mean(g)
			local s = Vector3.zero
			for _, p in g do
				s += p.Position
			end
			return if #g > 0 then s / #g else Vector3.zero
		end
		if #ga == 0 or #gb == 0 then
			return { parts }
		end
		a, b = mean(ga), mean(gb)
		if _ == 6 then
			return { ga, gb }
		end
	end
	return { parts }
end

-- Build one weapon. Returns the Phase13Appearance folder contents (parts in Handle space,
-- anchored, parented to `container`) plus report data.
function M.BuildArt(entry)
	local id, path, family, tier, specialName = entry[1], entry[2], entry[3], entry[4], entry[5]
	local folderName, modelName = string.match(path, "(.-)/(.*)")
	local source = SS._ConceptBooth[folderName][modelName]
	local frame = M.Frame(source, family)
	local work = source:Clone()
	local report = { id = id, source = path, before = 0, after = 0 }
	for _, d in source:GetDescendants() do
		if d:IsA("BasePart") then
			report.before += 1
		end
	end
	local isT7 = tier == 7 and not specialName
	local container = Instance.new("Folder")
	container.Name = "Phase13Appearance"
	local extras = {}
	local core = {}
	local floats = {}
	local function collect(top)
		local role = nil
		if top.Name == "Weapon" and top:IsA("Model") then
			for _, d in top:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(core, d)
				end
			end
			return
		end
		if isT7 and T7_KEEP[top.Name] then
			role = T7_KEEP[top.Name]
		elseif STAGE_EXACT[top.Name] or startsWithAny(top.Name, STAGE_PREFIX) then
			return
		end
		local list = {}
		if top:IsA("BasePart") then
			list = { top }
		end
		for _, d in top:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		for _, p in list do
			if role then
				p:SetAttribute("CampExtra", role)
				table.insert(extras, p)
			elseif startsWithAny(p.Name, FLOAT_PREFIX) then
				table.insert(floats, p)
			else
				table.insert(core, p)
			end
		end
	end
	for _, top in work:GetChildren() do
		collect(top)
	end
	-- Outliers (a stray part was 1300 studs away in one concept).
	local kept = {}
	for _, p in core do
		if (p.Position - frame.Position).Magnitude <= 9 then
			table.insert(kept, p)
		end
	end
	core = kept
	local mn, mx = bboxOf(core, frame)
	local pad = Vector3.one * 0.6
	for _, p in floats do
		local lp = frame:PointToObjectSpace(p.Position)
		if lp.X >= mn.X - pad.X and lp.X <= mx.X + pad.X and lp.Y >= mn.Y - pad.Y and lp.Y <= mx.Y + pad.Y
			and lp.Z >= mn.Z - pad.Z and lp.Z <= mx.Z + pad.Z then
			table.insert(core, p)
		end
	end
	mn, mx = bboxOf(core, frame)
	local extent = mx - mn
	local longest = math.max(extent.X, extent.Y, extent.Z)
	local target = M.Target[family] * (if tier == 8 or specialName then 1.1 else 1)
	local s = target / longest
	report.scale = s
	report.longestBefore = longest
	if isT7 then
		-- Tier 7 keeps its eclipse, but as a held weapon it becomes a smaller black sun facing the
		-- player's camera, just past the weapon's front, so the weapon reads against it as in the sheet.
		local eclipse = {}
		local disc
		for _, p in extras do
			if p:GetAttribute("CampExtra") == "Eclipse" then
				table.insert(eclipse, p)
				if p.Name == "EclipseDisc" and (not disc or p.Size.Magnitude > disc.Size.Magnitude) then
					disc = p
				end
			end
		end
		if #eclipse > 0 and disc then
			local ecMin, ecMax = bboxOf(eclipse, frame)
			local ecCentre = frame:PointToWorldSpace((ecMin + ecMax) / 2)
			local sz = disc.Size
			local normal = if sz.X <= sz.Y and sz.X <= sz.Z then disc.CFrame.RightVector
				elseif sz.Y <= sz.Z then disc.CFrame.UpVector
				else disc.CFrame.LookVector
			local fwd = frame.LookVector
			if normal:Dot(fwd) < 0 then
				normal = -normal
			end
			local axis = normal:Cross(fwd)
			local angle = math.acos(math.clamp(normal:Dot(fwd), -1, 1))
			local rot = if axis.Magnitude > 1e-4 then CFrame.fromAxisAngle(axis.Unit, angle) else CFrame.new()
			local coreCentre = (mn + mx) / 2
			local frontZ = mn.Z -- frame-space: forward is -Z
			local wanted = frame:PointToWorldSpace(Vector3.new(0, coreCentre.Y, frontZ + (mx.Z - mn.Z) * 0.18))
			local shrink = 0.6
			for _, p in eclipse do
				local rel = p.Position - ecCentre
				p.Size *= shrink
				p.CFrame = CFrame.new(wanted + rot * (rel * shrink)) * (rot * p.CFrame.Rotation)
			end
		end
		for _, p in extras do
			table.insert(core, p)
		end
	end
	-- Move every kept part into Handle space: Handle CFrame is identity here.
	local gripCF = CFrame.new(M.GripPoint)
	local parts = {}
	for _, p in core do
		local l = frame:ToObjectSpace(p.CFrame)
		local cf = gripCF * CFrame.new(l.Position * s) * l.Rotation
		for _, c in p:GetChildren() do
			if c:IsA("JointInstance") or c:IsA("WeldConstraint") or c:IsA("Highlight") then
				c:Destroy()
			end
		end
		p.Size *= s
		scaleInstanceFx(p, s)
		p.CFrame = cf
		p.Anchored = true
		p.Parent = container
		table.insert(parts, p)
	end
	work:Destroy() -- staging and anything not moved
	-- Tag animated groups before merging so a moving part never fuses with a static neighbour.
	for i, spec in M.Anim[id] or {} do
		for _, p in parts do
			for _, name in spec.names do
				if p.Name == name then
					p:SetAttribute("CampAnimKey", i)
				end
			end
		end
	end
	liveEmitters(container)
	for _, p in parts do
		if p:GetAttribute("CampExtra") == "Star" then
			p.Name = "StarFX"
			p.Transparency = 1
		end
	end
	-- 1) specks and hairlines
	local survivors = {}
	for _, p in parts do
		local sz = { p.Size.X, p.Size.Y, p.Size.Z }
		table.sort(sz)
		local protected = hasFx(p) or startsWithAny(p.Name, PROTECT_PREFIX)
		if not protected and (sz[3] < 0.06 or (sz[1] < 0.04 and sz[2] < 0.04)) then
			p:Destroy()
		else
			table.insert(survivors, p)
		end
	end
	parts = survivors
	-- 2) merge same-colour coplanar boxes
	local mergedTotal = 0
	for _ = 1, 4 do
		local merged
		parts, merged = mergePass(parts, 0.012)
		mergedTotal += merged
		if merged == 0 then
			break
		end
	end
	report.merged = mergedTotal
	-- 3) T7 eclipse rim pre-decimation (its 80 rim segments read as a ring at 1/4 density)
	local function groupsByName()
		local g = {}
		for _, p in parts do
			if p.Parent then
				local key = p.Name .. "|" .. p.ClassName .. "|" .. p.Color:ToHex() .. "|" .. p.Material.Name
				g[key] = g[key] or {}
				table.insert(g[key], p)
			end
		end
		return g
	end
	local function refresh()
		local out = {}
		for _, p in parts do
			if p.Parent then
				table.insert(out, p)
			end
		end
		parts = out
	end
	-- 4) halve the biggest repeated groups until within budget
	local guard = 0
	while #parts > M.Budget and guard < 40 do
		guard += 1
		local best, bestN = nil, 5
		for _, members in groupsByName() do
			local n = #members
			if n > bestN and not hasFx(members[1]) and not startsWithAny(members[1].Name, PROTECT_PREFIX) then
				best, bestN = members, n
			end
		end
		if not best then
			break
		end
		halveGroup(best)
		refresh()
	end
	-- 5) least-visible first
	if #parts > M.Budget then
		local ranked = {}
		for _, p in parts do
			if not hasFx(p) and not startsWithAny(p.Name, PROTECT_PREFIX) then
				table.insert(ranked, p)
			end
		end
		table.sort(ranked, function(a, b)
			return visibility(a) < visibility(b)
		end)
		local i = 1
		while #parts > M.Budget and ranked[i] do
			ranked[i]:Destroy()
			i += 1
			refresh()
		end
	end
	refresh()
	report.after = #parts
	return container, parts, report
end

-- Rig SPINS/MOVES groups: one invisible rotor per group, Weld motor to the Handle.
function M.Rig(id, container, parts)
	local specs = M.Anim[id]
	local rigs = {}
	if not specs then
		return rigs
	end
	local frame = CFrame.new()
	local n = 0
	for _, spec in specs do
		local members = {}
		for _, p in parts do
			if p.Parent and not p:GetAttribute("CampAnimRotor") then
				for _, name in spec.names do
					if p.Name == name then
						table.insert(members, p)
						break
					end
				end
			end
		end
		if #members > 0 then
			for _, group in cluster(members, spec.clusters or 1) do
				n += 1
				local pivot = Vector3.zero
				for _, p in group do
					pivot += p.Position
				end
				pivot /= #group
				local axis
				if spec.axis == "X" then
					axis = Vector3.xAxis
				elseif spec.axis == "Y" then
					axis = Vector3.yAxis
				elseif spec.axis == "Z" then
					axis = Vector3.zAxis
				else
					axis = ringAxis(group, pivot, frame)
				end
				local rotor = Instance.new("Part")
				rotor.Name = "AnimRotor_" .. n
				rotor.Size = Vector3.one * 0.05
				rotor.Transparency = 1
				rotor.Anchored = true
				rotor.CanCollide, rotor.CanQuery, rotor.CanTouch, rotor.CastShadow = false, false, false, false
				rotor.Massless = true
				-- rotor frame: its LookVector is the motion axis, so animation is CFrame.Angles(0,0,θ)
				-- or a translation along local Z.
				local ref = if math.abs(axis:Dot(Vector3.yAxis)) > 0.95 then Vector3.xAxis else Vector3.yAxis
				rotor.CFrame = CFrame.lookAt(pivot, pivot + axis, ref)
				rotor:SetAttribute("CampAnim", spec.kind)
				rotor:SetAttribute("CampAnimRate", spec.rate or 0)
				rotor:SetAttribute("CampAnimDistance", spec.distance or 0)
				rotor:SetAttribute("CampAnimStep", spec.step or 0)
				rotor:SetAttribute("CampAnimPhase", (n % 2) * 0.5)
				rotor.Parent = container
				for _, p in group do
					p:SetAttribute("CampAnimRotor", rotor.Name)
				end
				table.insert(rigs, { name = rotor.Name, kind = spec.kind, members = #group })
			end
		end
	end
	return rigs
end

local ROLE_RULES = {
	{ "Hardware", { "Grip", "Wrap", "Handle", "Trigger", "Guard", "Latch", "Rivet", "Bolt", "Pin", "Cap", "Mount", "String", "Serving", "Nock", "Axle", "Hub" } },
	{ "EdgeBand", { "Stripe", "Edge", "Band", "Trim", "Rim", "Ring", "Seam", "Line", "Collar" } },
	{ "Accent1", { "Gem", "Glow", "Core", "Orb", "Crystal", "Neon", "Glint", "Lens", "Halo" } },
	{ "Primary", { "Limb", "Body", "Stock", "Barrel", "Rail", "Shell", "Horn", "Riser", "Hull", "Prod", "Lance", "Plate", "Armor", "Receiver", "Tank" } },
}
function M.RoleFor(name)
	for _, rule in ROLE_RULES do
		for _, key in rule[2] do
			if string.find(name, key, 1, true) then
				return rule[1]
			end
		end
	end
	return "Secondary"
end

local function finishParts(container, handle, anchored)
	for _, p in container:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = anchored
			p.Massless = true
			p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
			local sz = p.Size
			if math.max(sz.X, sz.Y, sz.Z) < 0.5 then
				p.CastShadow = false
			end
		end
	end
	if anchored then
		return
	end
	for _, p in container:GetChildren() do
		if p:IsA("BasePart") then
			local rotorName = p:GetAttribute("CampAnimRotor")
			if string.sub(p.Name, 1, 10) == "AnimRotor_" then
				local motor = Instance.new("Weld")
				motor.Name = "ArtMotor"
				motor.Part0 = handle
				motor.Part1 = p
				motor.C0 = handle.CFrame:ToObjectSpace(p.CFrame)
				motor.C1 = CFrame.new()
				motor.Parent = p
			else
				local w = Instance.new("WeldConstraint")
				w.Name = "ArtWeld"
				w.Part0 = if rotorName then container:FindFirstChild(rotorName) else handle
				w.Part1 = p
				w.Parent = p
			end
		end
	end
end

local TIP_NAMES = {
	Bow = { "ArrowHeadTip", "ArrowHead", "ArrowHeadBrass", "Head3", "Head2", "Head1", "HeadBase" },
	Crossbow = { "BoltHeadTip", "BoltHead3", "BoltHead2", "BoltHead1", "BoltHead", "BoltHeadCore", "LanceTip", "NoseCap", "Nose" },
	Gun = { "MuzzleOrb", "MuzzleVoid", "MuzzleGlow", "MuzzleCap", "MuzzleCore", "MuzzleRim", "HarpoonTip", "Muzzle", "MuzzleRing", "MuzzleBrake", "BarrelBore", "Brake", "PortalVoid" },
}
local function muzzleFor(parts, family)
	for _, name in TIP_NAMES[family] or {} do
		local best, bestZ = nil, math.huge
		for _, p in parts do
			if p.Parent and p.Name == name then
				local e = rotatedExtents(p.CFrame, p.Size)
				if p.Position.Z - e.Z < bestZ then
					best, bestZ = p, p.Position.Z - e.Z
				end
			end
		end
		if best then
			return Vector3.new(0, best.Position.Y, bestZ), name
		end
	end
	local best, bestZ = nil, math.huge
	for _, p in parts do
		if p.Parent and math.abs(p.Position.X) < 0.4 and p.Transparency < 1 then
			local e = rotatedExtents(p.CFrame, p.Size)
			local front = p.Position.Z - e.Z
			if front < bestZ then
				best, bestZ = p, front
			end
		end
	end
	return Vector3.new(0, if best then best.Position.Y else 0, bestZ), "frontmost"
end

-- Install one weapon. Handle space is the template Handle's CFrame.
function M.Install(entry, opts)
	opts = opts or {}
	local id, family, tier, specialName = entry[1], entry[3], entry[4], entry[5]
	local weapons = RS.CodeAssets.Weapons
	local displays = RS.CodeAssets:FindFirstChild("WeaponDisplays")
	if not displays then
		displays = Instance.new("Folder")
		displays.Name = "WeaponDisplays"
		displays.Parent = RS.CodeAssets
	end
	local container, parts, report = M.BuildArt(entry)
	report.rigs = M.Rig(id, container, parts)
	local roles = {}
	for _, p in container:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			roles[p.Name] = M.RoleFor(p.Name)
		end
	end
	report.roles = roles
	-- Tool: clone the live tool (or the starter for new specials) to keep attributes, Handle, Grip.
	local existing = weapons:FindFirstChild(id)
	local base = existing or weapons.HRP_001
	local tool = base:Clone()
	tool.Name = id
	local handle = tool.Handle
	local old = tool:FindFirstChild("Phase13Appearance")
	if old then
		old:Destroy()
	end
	for _, c in tool:GetChildren() do
		if c:IsA("BasePart") and c ~= handle then
			c:Destroy()
		end
	end
	handle.CFrame = CFrame.new()
	handle.Transparency = 1
	if not existing then
		tool:SetAttribute("WeaponId", id)
		tool:SetAttribute("DisplayName", specialName)
		tool:SetAttribute("BrainrotSleepLauncher", true)
	end
	tool:SetAttribute("Phase13ArtVersion", 2)
	tool:SetAttribute("CampPartCount", report.after)
	-- muzzle / shot origin at the new front
	local muzzlePos, muzzleFrom = muzzleFor(parts, family)
	report.muzzleFrom = muzzleFrom
	local muzzle = handle:FindFirstChild("Muzzle")
	if not muzzle then
		muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Parent = handle
	end
	muzzle.CFrame = CFrame.new(muzzlePos)
	report.muzzle = muzzlePos
	-- display copy (anchored, 1.5x) before welding
	local display = Instance.new("Model")
	display.Name = id
	local droot = Instance.new("Part")
	droot.Name = "DisplayRoot"
	droot.Size = Vector3.one * 0.2
	droot.Transparency = 1
	droot.Anchored = true
	droot.CanCollide, droot.CanQuery, droot.CanTouch, droot.CastShadow = false, false, false, false
	local dc = container:Clone()
	dc.Name = "Art"
	local ds = M.DisplayScale
	local dmin, dmax = bboxOf(parts, CFrame.new())
	local centre = (dmin + dmax) / 2
	droot.CFrame = CFrame.new(centre * ds)
	for _, p in dc:GetDescendants() do
		if p:IsA("BasePart") then
			p.Size *= ds
			p.CFrame = CFrame.new(p.Position * ds) * p.CFrame.Rotation
			scaleInstanceFx(p, ds)
		end
	end
	for _, p in dc:GetDescendants() do
		if p:IsA("ParticleEmitter") then
			p.Enabled = false -- racks are static; no idle emitters on 30+ displays
		end
	end
	finishParts(dc, nil, true)
	dc.Parent = display
	droot.Parent = display
	display.PrimaryPart = droot
	display:SetAttribute("WeaponId", id)
	display:SetAttribute("Family", family)
	display:SetAttribute("Tier", tier)
	display:SetAttribute("Special", specialName ~= nil)
	-- weld and finish the held art
	finishParts(container, handle, false)
	container.Parent = tool
	if opts.dryRun then
		return tool, display, report
	end
	if existing then
		existing:Destroy()
	end
	tool.Parent = weapons
	local oldDisplay = displays:FindFirstChild(id)
	if oldDisplay then
		oldDisplay:Destroy()
	end
	display.Parent = displays
	return tool, display, report
end

return M
