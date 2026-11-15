--!nonstrict
-- Bakes Visual.Flair (neon kit + disabled VFX) into the cart templates at server boot.
-- The templates live in a binary .rbxm, so the flair layer is generated here instead
-- of being hand-authored. Contract kept so every existing validator still passes:
--  * plain Parts only (no MeshPart/Union, so no asset/provenance checks apply)
--  * Massless, CanCollide/CanTouch/CanQuery false, unanchored, one
--    CartGeometryWeld to Root each (GeometrySwap re-welds the same way)
--  * no seats, no constraints, no names used by Body/Wheel/collider lookups
--  * every VFX instance ships disabled; CartFlairController enables it locally
-- Geometry is placed from each cart's fitted profile (CoreBodyBounds, Floor, wheel
-- hubs), so it scales with all nine templates. BakeTemplates validates every cart
-- after baking and removes the flair again if anything fails.
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Geometry = require(RS.Shared.Utility.CartGeometry)
local Styles = require(RS.Shared.Config.CartFlairStyles)
local CartAssetValidator = require(RS.Shared.Validation.CartAssetValidator)
local CartAssemblyValidator = require(RS.Shared.Validation.CartAssemblyValidator)

local Builder = {}
local C = Color3.fromRGB
local STUD_VARIANT = "Bingus_Saved_Studs_13719188279"
local TEX = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Spark = "rbxasset://textures/particles/fire_sparks_main.dds",
}
local RESERVED = {
	Body = true, Wheel_L = true, Wheel_R = true, Floor = true, RearDeck = true,
	WheelContact_L = true, WheelContact_R = true, Chassis = true, ArcadeHull = true,
}

local function seq(colors)
	if typeof(colors) == "Color3" then return ColorSequence.new(colors) end
	if #colors == 1 then return ColorSequence.new(colors[1]) end
	local kps = {}
	for i, c in colors do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(kps)
end
local function nseq(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(kps)
end
local rad = math.rad

function Builder.Measure(cart)
	local p, why = Geometry.Get(cart)
	assert(p, "No geometry profile: " .. tostring(why))
	local B = p.CoreBodyBounds
	local floor
	for _, c in p.Colliders do
		if c.Name == "Floor" then floor = c end
	end
	assert(floor, "No Floor collider")
	local w = p.Wheels[1]
	assert(w, "No wheel profile")
	local d = {}
	d.hx = B.Size.X / 2
	d.cz = B.Frame.Position.Z
	d.cy = B.Frame.Position.Y
	d.sy = B.Size.Y
	d.y0 = B.Frame.Position.Y - B.Size.Y / 2
	d.y1 = B.Frame.Position.Y + B.Size.Y / 2
	d.zF = d.cz - B.Size.Z / 2
	d.zR = d.cz + B.Size.Z / 2
	d.len = B.Size.Z
	d.floorTop = floor.Frame.Position.Y + floor.Size.Y / 2
	d.floorBot = floor.Frame.Position.Y - floor.Size.Y / 2
	d.wx = math.abs(w.Hub.Position.X)
	d.wy = w.Hub.Position.Y
	d.wz = w.Hub.Position.Z
	d.r = w.Radius
	d.t = w.Thickness
	d.ground = p.Ground.BottomY
	d.k = B.Size.X / 7.32 -- Scrap Chariot = 1
	return d, p
end

local Ctx = {}
Ctx.__index = Ctx
function Ctx:part(name, size, cf, color, kind, extra)
	assert(not RESERVED[name], "reserved name " .. name)
	extra = extra or {}
	local p = Instance.new("Part")
	p.Name = name
	if extra.Shape then p.Shape = extra.Shape end
	p.Size = size
	p.CFrame = self.rootCF * cf
	p.Color = color
	if kind == "Neon" then
		p.Material = Enum.Material.Neon
		p.CastShadow = false
	elseif kind == "Stud" then
		p.Material = Enum.Material.Glacier
		p.MaterialVariant = STUD_VARIANT
	elseif kind == "Chrome" then
		p.Material = Enum.Material.Foil
	elseif kind == "Ghost" then
		p.Transparency = 1
		p.CastShadow = false
	else
		p.Material = Enum.Material.SmoothPlastic
	end
	if extra.Transparency then p.Transparency = extra.Transparency end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	if extra.Cycle then
		p:SetAttribute("FlairCycle", true)
		p:SetAttribute("FlairBaseColor", color)
		p:SetAttribute("FlairPhase", extra.Phase or 0)
	end
	if extra.Detail then p:SetAttribute("FlairDetail", true) end
	p.Parent = self.model
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CartGeometryWeld"
	weld.Part0 = self.root
	weld.Part1 = p
	weld.Parent = p
	self.parts += 1
	return p
end
function Ctx:attachment(part, name, localCF)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = part
	a.WorldCFrame = self.rootCF * localCF
	return a
end
local function tagFx(inst, mode, quality, rate)
	inst:SetAttribute("FlairMode", mode)
	inst:SetAttribute("FlairQuality", quality)
	if rate then inst:SetAttribute("FlairRate", rate) end
end
function Ctx:emitter(parent, name, props, mode, quality)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	for k, v in props do
		e[k] = v
	end
	tagFx(e, mode, quality, e.Rate)
	e.Enabled = false
	e.Parent = parent
	self.fx += 1
	return e
end
function Ctx:trail(parent, name, a0, a1, colors, lifetime, mode)
	local t = Instance.new("Trail")
	t.Name = name
	t.Attachment0, t.Attachment1 = a0, a1
	t.Color = seq(colors)
	t.Transparency = nseq({ { 0, 0.05 }, { 0.55, 0.45 }, { 1, 1 } })
	t.WidthScale = nseq({ { 0, 1 }, { 1, 0.15 } })
	t.Lifetime = lifetime
	t.MinLength = 0.1
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = true
	t.Enabled = false
	tagFx(t, mode or "Moving", "Low")
	t.Parent = parent
	self.fx += 1
	return t
end
function Ctx:light(parent, className, props, mode, quality)
	local l = Instance.new(className)
	for k, v in props do
		l[k] = v
	end
	l.Shadows = false
	l.Enabled = false
	tagFx(l, mode, quality, l.Brightness)
	l.Parent = parent
	self.fx += 1
	return l
end

-- Side runs split around the wheel so nothing passes through it.
local function segments(d)
	local out = {}
	local a0, a1 = d.zF + 0.35, d.wz - d.r - 0.15
	local b0, b1 = d.wz + d.r + 0.15, d.zR - 0.35
	if a1 - a0 > 0.4 then table.insert(out, { a0, a1 }) end
	if b1 - b0 > 0.4 then table.insert(out, { b0, b1 }) end
	return out
end

-- Tier 0 ----------------------------------------------------------------
local function stripes(ctx, d, s)
	local cycle = s.Cycle ~= nil
	for _, side in { -1, 1 } do
		for i, seg in segments(d) do
			local len = seg[2] - seg[1]
			local z = (seg[1] + seg[2]) / 2
			ctx:part("Fx_Stripe" .. side .. "_" .. i, Vector3.new(0.3, 0.48, len),
				CFrame.new(side * (d.hx - 0.05), d.floorTop + 0.4, z), s.Primary, "Neon",
				{ Cycle = cycle, Phase = (i - 1) * 0.25 })
			if s.Tier >= 1 then
				ctx:part("Fx_UnderTube" .. side .. "_" .. i, Vector3.new(0.22, 0.18, len),
					CFrame.new(side * (d.hx - 0.12), d.floorBot - 0.06, z), s.Secondary, "Neon",
					{ Cycle = cycle, Phase = 0.5 + (i - 1) * 0.25 })
			end
		end
	end
end

local function headTail(ctx, d, s)
	for _, side in { -1, 1 } do
		ctx:part("Fx_Head" .. side, Vector3.new(0.85 * d.k, 0.55, 0.2),
			CFrame.new(side * d.hx * 0.52, d.y1 - 0.8, d.zF - 0.08), s.Head, "Neon")
		ctx:part("Fx_Tail" .. side, Vector3.new(0.95 * d.k, 0.3, 0.16),
			CFrame.new(side * (d.hx - 0.7), d.floorTop - 0.05, d.zR + 0.07), s.Tail, "Neon")
	end
	if s.Tier >= 1 then
		local beam = ctx:part("Fx_HeadBeam", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, d.y1 - 0.8, d.zF - 0.25), s.Head, "Ghost")
		ctx:light(beam, "SpotLight", {
			Face = Enum.NormalId.Front, Range = 20 + s.Tier * 2, Angle = 70,
			Brightness = 3, Color = s.Head,
		}, "Driving", "Medium")
	end
end

local function exhausts(ctx, d, s)
	local sides = if (s.Exhausts or 1) == 1 then { 1 } else { -1, 1 }
	local dia = if s.Tier >= 2 then 0.62 else 0.5
	local len = if s.Tier >= 2 then 1.5 else 1.2
	local k = if s.Tier >= 2 then 1.25 else 1
	for _, side in sides do
		local x = side * (d.hx - 1.25 * d.k)
		local y = d.floorBot - 0.22
		local zc = d.zR + 0.25
		ctx:part("Fx_Pipe" .. side, Vector3.new(len, dia, dia), CFrame.new(x, y, zc) * CFrame.Angles(0, math.pi / 2, 0),
			C(200, 208, 224), "Chrome", { Shape = Enum.PartType.Cylinder })
		local zEnd = zc + len / 2
		local tip = ctx:part("Fx_PipeTip" .. side, Vector3.new(0.2, dia + 0.16, dia + 0.16),
			CFrame.new(x, y, zEnd) * CFrame.Angles(0, math.pi / 2, 0),
			s.Secondary,
			"Neon",
			{ Shape = Enum.PartType.Cylinder, Cycle = s.Cycle ~= nil, Phase = 0.3 })
		local out = ctx:attachment(tip, "Fx_ExhaustOut", CFrame.new(x, y, zEnd + 0.12) * CFrame.Angles(rad(78), 0, 0))
		ctx:emitter(out, "Fx_Smoke", {
			Texture = TEX.Smoke, Color = seq(s.Smoke),
			Size = nseq({ { 0, 0.35 * k }, { 0.4, 1.1 * k }, { 1, 2.1 * k } }),
			Transparency = nseq({ { 0, if s.Tier >= 1 then 0.25 else 0.45 }, { 0.7, 0.75 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(3, 5),
			SpreadAngle = Vector2.new(12, 12), Acceleration = Vector3.new(0, 3, 0), Drag = 1.6,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
			LightEmission = if s.Tier >= 1 then 0.4 else 0.05, LightInfluence = if s.Tier >= 1 then 0.5 else 1,
			Rate = if s.Tier == 0 then 7 else 14, EmissionDirection = Enum.NormalId.Top,
		}, "Moving", "Low")
		-- Idle puff so a parked cart still looks alive.
		ctx:emitter(out, "Fx_IdlePuff", {
			Texture = TEX.Smoke, Color = seq(s.Smoke),
			Size = nseq({ { 0, 0.3 }, { 1, 1.2 } }), Transparency = nseq({ { 0, 0.5 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(0.8, 1.5),
			SpreadAngle = Vector2.new(15, 15), Acceleration = Vector3.new(0, 2, 0),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
			LightEmission = 0.2, Rate = 2.5, EmissionDirection = Enum.NormalId.Top,
		}, "Always", "Low")
		if s.Tier >= 2 or s.FireExhaust then
			ctx:emitter(out, "Fx_Flame", {
				Texture = TEX.Fire, Color = seq(s.Flame),
				Size = nseq({ { 0, 0.6 * k }, { 1, 0.05 } }),
				Transparency = nseq({ { 0, 0.05 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.15, 0.28), Speed = NumberRange.new(9, 14),
				SpreadAngle = Vector2.new(6, 6), Drag = 2, LightEmission = 1, LightInfluence = 0,
				Rate = 45, EmissionDirection = Enum.NormalId.Top,
			}, if s.FireExhaust then "Moving" else "Boost", "Medium")
		end
		if s.FireExhaust then
			ctx:emitter(out, "Fx_Embers", {
				Texture = TEX.Spark, Color = seq(s.Flame),
				Size = nseq({ { 0, 0.2 }, { 1, 0 } }), Lifetime = NumberRange.new(0.5, 0.9),
				Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(30, 30),
				Acceleration = Vector3.new(0, 4, 0), LightEmission = 1, LightInfluence = 0,
				Rate = 10, EmissionDirection = Enum.NormalId.Top,
			}, "Moving", "Medium")
		end
	end
end

-- Tier 1 ----------------------------------------------------------------
local function underglow(ctx, d, s)
	local plate = ctx:part("Fx_Underglow", Vector3.new(2 * d.hx - 1.3, 0.12, d.len - 1.4),
		CFrame.new(0, d.floorBot - 0.1, d.cz), s.Primary, "Neon", { Cycle = s.Cycle ~= nil, Phase = 0.1 })
	if s.Tier < 1 then
		return -- the starter glows but does not light the ground; that stays a 500M perk
	end
	ctx:light(plate, "PointLight", {
		Range = 8 + s.Tier * 2.5, Brightness = 1.6 + s.Tier * 0.6, Color = s.Primary,
	}, "Always", "Medium")
end

local function ring(ctx, name, center, radius, n, color, extra)
	local seg = 2 * radius * math.tan(math.pi / n) * 1.05
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2 + math.pi / n
		local e = table.clone(extra or {})
		e.Phase = (e.Phase or 0) + i / n
		ctx:part(name .. i, Vector3.new(0.14, 0.2, seg), center * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius, 0), color, "Neon", e)
	end
end

local function wheelRings(ctx, d, s)
	local cycle = s.Cycle ~= nil
	for _, side in { -1, 1 } do
		local x = side * (d.wx + d.t / 2 + 0.08)
		local center = CFrame.new(x, d.wy, d.wz)
		ring(ctx, "Fx_Rim" .. side .. "_", center, d.r * 0.8, 8, s.Primary, { Cycle = cycle })
		if s.Tier >= 2 then
			local hub = ctx:part("Fx_Hub" .. side, Vector3.new(0.16, 0.62, 0.62), center * CFrame.Angles(math.pi / 4, 0, 0),
				s.Secondary, "Neon", { Cycle = cycle, Phase = 0.5 })
			local sparkOut = ctx:attachment(hub, "Fx_WheelSpark",
				CFrame.new(side * d.wx, d.wy - d.r + 0.15, d.wz + 0.3) * CFrame.Angles(rad(70), 0, 0))
			ctx:emitter(sparkOut, "Fx_Sparks", {
				Texture = TEX.Spark, Color = seq(s.Spark),
				Size = nseq({ { 0, 0.24 }, { 1, 0 } }), Lifetime = NumberRange.new(0.25, 0.45),
				Speed = NumberRange.new(8, 14), SpreadAngle = Vector2.new(22, 22),
				Acceleration = Vector3.new(0, -25, 0), Drag = 1, LightEmission = 1, LightInfluence = 0,
				Rate = 28, EmissionDirection = Enum.NormalId.Top,
			}, "Fast", "High")
		end
		if s.Tier >= 3 then
			ring(ctx, "Fx_RimIn" .. side .. "_", center, d.r * 0.46, 6, s.Secondary, { Cycle = cycle, Phase = 0.5, Detail = true })
		end
	end
end

local function tailTrails(ctx, d, s)
	for _, side in { -1, 1 } do
		local x, z = side * (d.hx - 0.4), d.zR + 0.1
		local holder = ctx:part("Fx_TrailMount" .. side, Vector3.new(0.2, 0.2, 0.2), CFrame.new(x, d.floorTop, z), s.Primary, "Ghost")
		local a0 = ctx:attachment(holder, "Fx_TrailA", CFrame.new(x, d.floorTop + 0.22, z))
		local a1 = ctx:attachment(holder, "Fx_TrailB", CFrame.new(x, d.floorTop - 0.22, z))
		ctx:trail(holder, "Fx_Trail", a0, a1, s.Trail, 0.35 + 0.1 * s.Tier)
	end
end

-- Tier 2 ----------------------------------------------------------------
local WINGS = {
	Fin = { lens = { 1.5, 2.0, 1.6 }, tilt = { -6, 10, 26 }, roll = { 14, 20, 26 }, width = 0.7 },
	Zig = { lens = { 1.4, 2.1, 1.7 }, tilt = { -4, 12, 28 }, roll = { 16, 22, 28 }, width = 0.55, zig = true },
	Shield = { lens = { 1.2, 1.6, 1.3 }, tilt = { -8, 8, 24 }, roll = { 12, 16, 20 }, width = 1.1, studPrimary = true },
	Angel = { lens = { 1.8, 2.5, 3.1, 2.7, 2.1 }, tilt = { -12, 0, 12, 24, 36 }, roll = { 16, 20, 24, 28, 32 }, width = 0.62 },
	Crystal = { lens = { 1.6, 2.4, 3.2, 2.6, 1.9 }, tilt = { -10, 2, 14, 26, 38 }, roll = { 14, 20, 26, 32, 38 }, width = 0.42, crystal = true },
	Bat = { lens = { 2.0, 2.8, 2.6, 1.9 }, tilt = { -14, 4, 20, 36 }, roll = { 22, 28, 32, 36 }, width = 0.32 },
}

local function wings(ctx, d, s)
	local spec = WINGS[s.Wing]
	if not spec then return end
	local cycle = s.Cycle ~= nil
	local k = math.clamp(d.k, 0.9, 1.15) * (if s.Tier >= 3 then 1.45 else 1.2)
	local rollScale = if s.Tier >= 3 then 0.8 else 1
	for _, side in { -1, 1 } do
		local origin = CFrame.new(side * (d.hx - 0.1), d.floorTop + 0.95, d.wz - 0.45)
		local best, bestLen = nil, -1
		local n = #spec.lens
		for i, L0 in spec.lens do
			local L = L0 * k
			-- Feathers root along the rim (front to back) so the set reads as a wing, not a fan.
			local spread = (i - (n + 1) / 2) * 0.34 * k
			local base = origin * CFrame.new(0, -math.abs(spread) * 0.15, spread)
				* CFrame.Angles(0, 0, -side * rad(spec.roll[i] * rollScale)) * CFrame.Angles(rad(spec.tilt[i]), 0, 0)
			local tag = "Fx_Wing" .. side .. "_" .. i
			if spec.crystal then
				ctx:part(tag, Vector3.new(spec.width, L, spec.width), base * CFrame.new(0, L / 2, 0) * CFrame.Angles(0, math.pi / 4, 0),
					if i % 2 == 0 then s.Secondary else s.Primary, "Neon", { Transparency = 0.12, Cycle = cycle and i % 2 == 1, Phase = i * 0.15 })
			else
				local bodyColor = if spec.studPrimary then s.Primary else s.Ink
				ctx:part(tag, Vector3.new(0.24, L, spec.width * k), base * CFrame.new(0, L / 2, 0), bodyColor, "Stud")
				ctx:part(tag .. "Edge", Vector3.new(0.28, L * 0.94, 0.16), base * CFrame.new(0, L * 0.47, -spec.width * k / 2 - 0.04),
					if spec.studPrimary then s.Secondary else s.Primary, "Neon", { Cycle = cycle, Phase = i * 0.15 })
				if spec.zig then
					ctx:part(tag .. "Bolt", Vector3.new(0.24, L * 0.32, spec.width * 0.8), base * CFrame.new(0, L * 0.55, spec.width * 0.45) * CFrame.Angles(rad(-25), 0, 0),
						s.Secondary, "Neon", { Detail = true })
				end
			end
			ctx:part(tag .. "Tip", Vector3.new(0.3, 0.3, 0.3) * (if s.Tier >= 3 then 1.25 else 1),
				base * CFrame.new(0, L + 0.08, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
				s.Secondary, "Neon", { Cycle = cycle, Phase = 0.5 + i * 0.15 })
			if L > bestLen then best, bestLen = base, L end
		end
		-- Wingtip light ribbons replace the rear-corner trails from tier 2.
		local tipCF = best * CFrame.new(0, bestLen - 0.1, 0)
		local holder = ctx:part("Fx_WingTrailMount" .. side, Vector3.new(0.2, 0.2, 0.2), tipCF, s.Primary, "Ghost")
		local w = 0.3 + 0.12 * s.Tier
		local a0 = ctx:attachment(holder, "Fx_TrailA", tipCF * CFrame.new(0, w / 2, 0))
		local a1 = ctx:attachment(holder, "Fx_TrailB", tipCF * CFrame.new(0, -w / 2, 0))
		ctx:trail(holder, "Fx_Trail", a0, a1, s.Trail, 0.35 + 0.17 * s.Tier)
	end
end

local function crestAt(ctx, d, s, side, pos)
	local cycle = s.Cycle ~= nil
	local big = if s.Tier >= 3 then 1.35 else 1
	local n = "Fx_Crest" .. side .. "_"
	if s.Crest == "Star" then
		ctx:part(n .. "Stalk", Vector3.new(0.3, 0.5, 0.3), pos * CFrame.new(0, 0.25, 0), s.Ink, "Stud")
		local c = pos * CFrame.new(0, 0.55 + 0.75 * big, 0)
		ctx:part(n .. "V", Vector3.new(0.24, 1.5 * big, 0.2), c, s.Primary, "Neon", { Cycle = cycle })
		ctx:part(n .. "H", Vector3.new(1.5 * big, 0.24, 0.2), c, s.Primary, "Neon", { Cycle = cycle })
		ctx:part(n .. "D1", Vector3.new(0.18, 0.95 * big, 0.16), c * CFrame.Angles(0, 0, math.pi / 4), s.Secondary, "Neon", { Detail = true })
		ctx:part(n .. "D2", Vector3.new(0.18, 0.95 * big, 0.16), c * CFrame.Angles(0, 0, -math.pi / 4), s.Secondary, "Neon", { Detail = true })
		ctx:part(n .. "Gem", Vector3.new(0.5, 0.5, 0.3) * big, c * CFrame.Angles(0, 0, math.pi / 4), s.Secondary, "Neon")
		return c
	elseif s.Crest == "Bolt" then
		-- Connected zig-zag lightning bolt in the forward-facing plane.
		local pts = { Vector2.new(0, 0.05), Vector2.new(0.38 * side, 0.85), Vector2.new(-0.22 * side, 1.25), Vector2.new(0.3 * side, 2.15) }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local mid, dir = (a + b) / 2, b - a
			local ang = math.atan2(dir.X, dir.Y)
			ctx:part(n .. "Bolt" .. i, Vector3.new(0.34, dir.Magnitude + 0.2, 0.3),
				pos * CFrame.new(mid.X, mid.Y, 0) * CFrame.Angles(0, 0, -ang), if i == 2 then s.Secondary else s.Primary, "Neon")
		end
		local tip = pos * CFrame.new(pts[4].X, pts[4].Y + 0.12, 0)
		ctx:part(n .. "Gem", Vector3.new(0.36, 0.36, 0.36), tip * CFrame.Angles(math.pi / 4, 0, math.pi / 4), s.Secondary, "Neon")
		return tip
	elseif s.Crest == "Crown" then
		ctx:part(n .. "Band", Vector3.new(1.05, 0.32, 0.6), pos * CFrame.new(0, 0.18, 0), s.Primary, "Stud")
		for i, x in { -0.36, 0, 0.36 } do
			local h = if x == 0 then 0.95 else 0.7
			ctx:part(n .. "Spike" .. i, Vector3.new(0.22, h, 0.22), pos * CFrame.new(x, 0.34 + h / 2, 0), s.Primary, "Neon")
			ctx:part(n .. "Jewel" .. i, Vector3.new(0.26, 0.26, 0.26), pos * CFrame.new(x, 0.42 + h, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), s.Secondary, "Neon")
		end
		return pos * CFrame.new(0, 1.3, 0)
	elseif s.Crest == "Comet" then
		local head = pos * CFrame.new(0, 1.2 * big, -0.1)
		ctx:part(n .. "Stalk", Vector3.new(0.28, 0.9 * big, 0.28), pos * CFrame.new(0, 0.45 * big, 0), s.Ink, "Stud")
		ctx:part(n .. "Head", Vector3.new(0.62, 0.62, 0.62), head * CFrame.Angles(math.pi / 4, 0, math.pi / 4), s.Secondary, "Neon")
		for i, sz in { 0.48, 0.38, 0.28, 0.2 } do
			ctx:part(n .. "Tail" .. i, Vector3.new(sz, sz, sz * 1.6), head * CFrame.new(0, 0.12 * i, 0.42 * i) * CFrame.Angles(math.pi / 4, 0, 0),
				s.Primary, "Neon", { Cycle = cycle, Phase = i * 0.2, Detail = i > 2 })
		end
		return head
	elseif s.Crest == "Horns" then
		-- Banded magma horn: obsidian and glowing segments alternate as it curls up and out.
		local c = pos
		for i, sz in { 0.84, 0.7, 0.56, 0.44, 0.32 } do
			c = c * CFrame.new(0, sz * 0.72, 0) * CFrame.Angles(rad(-12), 0, -side * rad(15))
			local glow = i % 2 == 0 or i == 5
			ctx:part(n .. "Horn" .. i, Vector3.new(sz, sz * 1.2, sz), c, if glow then (if i == 5 then s.Primary else s.Secondary) else s.Ink,
				if glow then "Neon" else "Stud", { Cycle = glow and cycle, Phase = 0.2 * i })
		end
		ctx:part(n .. "Band", Vector3.new(0.74, 0.16, 0.74), pos * CFrame.new(0, 0.2, 0), s.Secondary, "Neon", { Cycle = cycle, Phase = 0.7 })
		return c
	end
	return pos
end

local function crests(ctx, d, s)
	if not s.Crest then return end
	for _, side in { -1, 1 } do
		local pos = CFrame.new(side * (d.hx - 0.66 * d.k), d.y1 + 0.02, d.zF + 0.3)
		local top = crestAt(ctx, d, s, side, pos)
		if s.Tier >= 3 and top then
			-- Signature glint: slow big star sparkle on each crest.
			local g = ctx:part("Fx_CrestGlow" .. side, Vector3.new(0.2, 0.2, 0.2), top, s.Secondary, "Ghost")
			ctx:emitter(g, "Fx_Glint", {
				Texture = TEX.Sparkle, Color = seq({ s.Secondary, s.Primary }),
				Size = nseq({ { 0, 0 }, { 0.5, 1.4 }, { 1, 0 } }), Lifetime = NumberRange.new(0.6, 0.9),
				Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 90), RotSpeed = NumberRange.new(40, 90),
				LightEmission = 1, LightInfluence = 0, Rate = 1.6,
			}, "Always", "Medium")
		end
	end
end

local function chevrons(ctx, d, s)
	local count = if s.Tier >= 3 then 3 else 2
	local cycle = s.Cycle ~= nil
	for _, side in { -1, 1 } do
		for j = 1, count do
			local apexZ = d.zF + 0.7 + (j - 1) * 0.72
			if apexZ + 0.6 > d.wz - d.r - 0.1 then break end
			local y = d.floorTop + 0.82
			for _, v in { 1, -1 } do
				local armZ = apexZ + 0.27 * math.cos(rad(35))
				local armY = y + v * 0.27 * math.sin(rad(35))
				ctx:part("Fx_Chevron" .. side .. "_" .. j .. (if v > 0 then "U" else "D"), Vector3.new(0.2, 0.2, 0.62),
					CFrame.new(side * (d.hx + 0.02), armY, armZ) * CFrame.Angles(rad(-v * 35), 0, 0),
					if j % 2 == 1 then s.Secondary else s.Primary, "Neon", { Cycle = cycle, Phase = j * 0.25, Detail = true })
			end
		end
	end
end

local function shine(ctx, d, s)
	local vol = ctx:part("Fx_ShineVolume", Vector3.new(2 * d.hx, d.sy, d.len), CFrame.new(0, d.cy, d.cz), s.Secondary, "Ghost")
	ctx:emitter(vol, "Fx_Shine", {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Texture = TEX.Sparkle, Color = seq({ C(255, 255, 255), s.Secondary }),
		Size = nseq({ { 0, 0 }, { 0.5, 0.6 }, { 1, 0 } }), Lifetime = NumberRange.new(0.45, 0.7),
		Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 90),
		LightEmission = 1, LightInfluence = 0, Rate = if s.Tier >= 3 then 7 else 4,
	}, "Always", "Medium")
end

-- Tier 3 ----------------------------------------------------------------
local function aura(ctx, d, s)
	local vol = ctx:part("Fx_AuraVolume", Vector3.new(2 * d.hx + 0.8, 0.3, d.len + 1), CFrame.new(0, d.floorTop - 0.2, d.cz), s.Primary, "Ghost")
	ctx:emitter(vol, "Fx_AuraRise", {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Texture = TEX.Sparkle, Color = seq(s.Aura),
		Size = nseq({ { 0, 0 }, { 0.2, 0.45 }, { 1, 0 } }), Transparency = nseq({ { 0, 0 }, { 1, 0.4 } }),
		Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(2.5, 5),
		Acceleration = Vector3.new(0, 1.5, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		LightEmission = 1, LightInfluence = 0, Rate = 22, EmissionDirection = Enum.NormalId.Top,
	}, "Always", "Medium")
	ctx:emitter(vol, "Fx_AuraGlow", {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Texture = TEX.Smoke, Color = seq(s.Aura),
		Size = nseq({ { 0, 1.2 }, { 1, 2.8 } }), Transparency = nseq({ { 0, 0.85 }, { 0.35, 0.7 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.4, 2), Speed = NumberRange.new(1.5, 2.5),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20),
		LightEmission = 0.9, LightInfluence = 0, Rate = 5, EmissionDirection = Enum.NormalId.Top,
	}, "Always", "High")
	if s.Crest == "Horns" then
		ctx:emitter(vol, "Fx_AuraEmbers", {
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Texture = TEX.Spark, Color = seq({ C(255, 225, 74), s.Primary }),
			Size = nseq({ { 0, 0.22 }, { 1, 0 } }), Lifetime = NumberRange.new(0.9, 1.5), Speed = NumberRange.new(2, 4),
			Acceleration = Vector3.new(0, 3, 0), LightEmission = 1, LightInfluence = 0, Rate = 12,
			EmissionDirection = Enum.NormalId.Top,
		}, "Always", "Medium")
	end
end

local function halo(ctx, d, s)
	local center = CFrame.new(0, d.y1 + 2.1, d.zF + 1.0) * CFrame.Angles(0, 0, math.pi / 2)
	ring(ctx, "Fx_Halo", center, 1.15 * d.k, 10, s.Primary, { Cycle = true })
	local g = ctx:part("Fx_HaloGlow", Vector3.new(0.3, 2.4 * d.k, 2.4 * d.k), center, s.Primary, "Ghost")
	ctx:emitter(g, "Fx_HaloSparkle", {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Texture = TEX.Sparkle, Color = seq(s.Aura),
		Size = nseq({ { 0, 0 }, { 0.5, 0.5 }, { 1, 0 } }), Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(0.5, 1), LightEmission = 1, LightInfluence = 0, Rate = 6,
	}, "Always", "Medium")
end

function Builder.Build(cart: Model, styleName: string?)
	local name = styleName or cart.Name
	local s = Styles.Carts[name]
	assert(s, "No flair style for " .. name)
	local d = Builder.Measure(cart)
	local visual = cart:FindFirstChild("Visual")
	assert(visual and visual:IsA("Model"), "Missing Visual")
	local root = cart:FindFirstChild("Root")
	assert(root and root:IsA("BasePart"), "Missing Root")
	local old = visual:FindFirstChild("Flair")
	if old then old:Destroy() end
	local model = Instance.new("Model")
	model.Name = "Flair"
	local ctx = setmetatable({ model = model, root = root, rootCF = root.CFrame, parts = 0, fx = 0 }, Ctx)

	stripes(ctx, d, s)
	headTail(ctx, d, s)
	exhausts(ctx, d, s)
	underglow(ctx, d, s)
	wheelRings(ctx, d, s)
	if s.Tier == 1 then tailTrails(ctx, d, s) end
	if s.Tier >= 2 then
		wings(ctx, d, s)
		crests(ctx, d, s)
		chevrons(ctx, d, s)
		shine(ctx, d, s)
	end
	if s.Tier >= 3 then
		aura(ctx, d, s)
		if s.Halo then halo(ctx, d, s) end
	end

	model:SetAttribute("FlairStyle", name)
	model:SetAttribute("FlairTier", s.Tier)
	model:SetAttribute("FlairVersion", Styles.Version)
	if s.Cycle then model:SetAttribute("FlairCycle", s.Cycle) end
	CollectionService:AddTag(model, Styles.Tag)
	model.Parent = visual
	return { Parts = ctx.parts, Fx = ctx.fx }
end

function Builder.Remove(cart: Model)
	local visual = cart:FindFirstChild("Visual")
	local old = visual and visual:FindFirstChild("Flair")
	if old then old:Destroy() end
end

-- Server boot: bake every template that has a style, then prove it still passes the
-- same three checks CartAssetService runs. Any failure removes that cart's flair, so
-- the worst case is the plain cart, never a broken one.
function Builder.BakeTemplates(folder: Instance): { [string]: string }
	local report = {}
	for _, cart in folder:GetChildren() do
		if not cart:IsA("Model") or not Styles.Carts[cart.Name] then
			continue
		end
		local visual = cart:FindFirstChild("Visual")
		local existing = visual and visual:FindFirstChild("Flair")
		if existing and existing:GetAttribute("FlairVersion") == Styles.Version then
			report[cart.Name] = "AlreadyBaked"
			continue
		end
		local ok, result = pcall(Builder.Build, cart, cart.Name)
		if ok then
			local valid, why = pcall(function()
				local asset = CartAssetValidator.Validate(cart)
				assert(asset.IsValid, table.concat(asset.Errors, "; "))
				local assembly = CartAssemblyValidator.Validate(cart, { Stage = "Static" })
				assert(assembly.IsValid, "assembly invalid")
				local geometryOk, geometryWhy = Geometry.ValidateTemplate(cart)
				assert(geometryOk, geometryWhy)
			end)
			if valid then
				report[cart.Name] = string.format("Baked parts=%d fx=%d", result.Parts, result.Fx)
			else
				Builder.Remove(cart)
				report[cart.Name] = "RolledBack: " .. tostring(why)
			end
		else
			Builder.Remove(cart)
			report[cart.Name] = "BuildFailed: " .. tostring(result)
		end
	end
	return report
end

return Builder
