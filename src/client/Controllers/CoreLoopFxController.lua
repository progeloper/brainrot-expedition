--!strict
-- Core Loop V2 world FX + juice (Parts B3, D2, F, K2, L3). Presentation only: reads server attributes on
-- director-owned brainrots and CoreLoopEvent payloads; decides nothing. Review gate (L6): groups render
-- their full look only when approved in CoreLoopFx.Approved or inside the review pen; otherwise the plain
-- fallback (shape + colour + text + sound).
--   Group2_StarKit   pillars, sky beam, guarded ring, other-player transparency, LEAVING, Dive
--   Group3_Arrivals  herd pop, beam drop, meteor, rift
--   Group4_Mutations shimmer, reveal, upgrade-to-Jackpot
--   Group5_Behaviour "!", "?", bolt dust, exhausted, groggy, taunt, stagger, scatter, SNEAK SHOT, NOT YOURS, Saved, magnet
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage.Shared
local CoreLoop = require(Shared.Config.CoreLoop)
local CoreLoopFlags = require(Shared.Config.CoreLoopFlags)
local Fx = require(Shared.Config.CoreLoopFx)
local Theme = require(Shared.UI.Theme)
local StudPop = require(Shared.UI.StudPop)
local BrainrotCatalog = require(Shared.Config.BrainrotCatalog)
local Kit = require(script.Parent.Parent.CoreLoop.FxKit)
local WorldTag = require(script.Parent.Parent.CoreLoop.WorldTag)

local Controller = {}

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

------------------------------------------------------------------ helpers

local function tierOf(model: Model): string
	return BrainrotCatalog.GetRarity(model:GetAttribute("BrainrotId")) or "Common"
end

local function bodyOf(model: Model): BasePart?
	local body = model:FindFirstChild("Body", true)
	if body and body:IsA("BasePart") then
		return body
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function groundColour(position: Vector3): Color3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances =
		{ Kit.Root(), Workspace:FindFirstChild("Runtime") :: Instance }
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), params)
	if hit then
		if hit.Instance:IsA("Terrain") then
			local ok, colour = pcall(function()
				return Workspace.Terrain:GetMaterialColor(hit.Material)
			end)
			if ok then
				return colour
			end
		elseif hit.Instance:IsA("BasePart") then
			return hit.Instance.Color
		end
	end
	return Color3.fromRGB(110, 170, 80)
end

local function feet(model: Model): Vector3
	local cframe, size = model:GetBoundingBox()
	return cframe.Position - Vector3.new(0, size.Y * 0.5, 0)
end

-- Target-only freeze: pause the model's playing animation tracks (never the camera or world).
local function freeze(model: Model, seconds: number)
	local animator = model:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		return
	end
	local tracks = (animator :: Animator):GetPlayingAnimationTracks()
	for _, track in tracks do
		track:AdjustSpeed(0)
	end
	task.delay(seconds, function()
		for _, track in tracks do
			if track.IsPlaying then
				track:AdjustSpeed(1)
			end
		end
	end)
end

------------------------------------------------------------------ camera juice (D2)

local shakeTrauma, shakeUntil, shakeStarted = 0, 0, 0
local fovKick, fovUntil, fovStarted = 0, 0, 0
local baseFov, lastWrittenFov = camera.FieldOfView, -1 -- FOV kick bookkeeping (see CoreLoopJuice)
local function shake(trauma: number, seconds: number)
	if Kit.ReducedMotion() then
		trauma *= 0.5
	end
	shakeTrauma, shakeStarted, shakeUntil = trauma, os.clock(), os.clock() + seconds
end
local function kickFov(degrees: number, seconds: number)
	if Kit.ReducedMotion() then
		degrees *= 0.5
	end
	fovKick, fovStarted, fovUntil = degrees, os.clock(), os.clock() + seconds
end
RunService:BindToRenderStep("CoreLoopJuice", Enum.RenderPriority.Camera.Value + 2, function()
	local t = os.clock()
	if t < shakeUntil then
		local fade = 1 - (t - shakeStarted) / math.max(0.01, shakeUntil - shakeStarted)
		local amount = shakeTrauma * fade * fade * 0.6
		camera.CFrame *= CFrame.Angles(
			math.rad((math.noise(t * 25, 1) * 2) * amount * 4),
			math.rad((math.noise(t * 25, 2) * 2) * amount * 4),
			0
		)
	end
	-- FOV kick on top of the camera script's own FOV. If the script rewrote FieldOfView since our last
	-- write, that value is the new base; otherwise the base is unchanged. Kicks never accumulate, whether
	-- or not the camera script resets FOV each frame (Scriptable / default camera / cart camera).
	local offset = 0
	if t < fovUntil then
		local alpha = (t - fovStarted) / math.max(0.01, fovUntil - fovStarted)
		offset = fovKick * math.sin(math.pi * alpha)
	end
	local current = camera.FieldOfView
	if current ~= lastWrittenFov then
		baseFov = current
	end
	local wanted = math.clamp(baseFov + offset, 1, 120)
	if wanted ~= current then
		camera.FieldOfView = wanted
	end
	lastWrittenFov = camera.FieldOfView
end)

------------------------------------------------------------------ pillars (B3, L3.2, L3.3)

type Pillar = {
	Model: Model,
	Part: Part,
	Beams: { Beam },
	Top: Attachment,
	Bottom: Attachment,
	Rings: { Kit.Ring },
	Guard: Kit.Ring?,
	Emitter: ParticleEmitter?,
	Crown: { BillboardGui },
	Rays: Part?,
	Light: PointLight?,
	Grade: string,
	Height: number,
	BornAt: number,
	DropUntil: number,
	Full: boolean,
}
local pillars: { [Model]: Pillar } = {}

local function gradeOf(model: Model): string
	return model:GetAttribute("TrueGrade") or model:GetAttribute("VisibleGrade") or "Star"
end

local function destroyPillar(model: Model)
	local pillar = pillars[model]
	if not pillar then
		return
	end
	for _, ring in pillar.Rings do
		ring.Destroy()
	end
	if pillar.Guard then
		pillar.Guard.Destroy()
	end
	pillar.Part:Destroy()
	if pillar.Rays then
		pillar.Rays:Destroy()
	end
	pillars[model] = nil
end

local function buildPillar(model: Model, grade: string, dropFromSky: boolean): Pillar
	local full = Kit.Approved("Group2_StarKit")
	local low = Kit.Tier() == "Low"
	local tier = tierOf(model)
	local isSky = grade == "Jackpot"
	local spec: any = if isSky
		then Fx.L3_3_SkyBeam
		elseif grade == "Super" then Fx.L3_2_Pillar.Super
		else Fx.L3_2_Pillar.Star
	local colour = if isSky then Theme.CoreLoop.Jackpot else Kit.GlowColour(tier)
	local part = Kit.Anchor(model:GetPivot().Position)
	part.Name = "StarPillar"
	local bottom = Instance.new("Attachment")
	bottom.Parent = part
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, spec.Height, 0)
	top.Parent = part
	local beams = {}
	local function beam(
		width: number,
		texture: string?,
		scroll: number?,
		transparency: number?
	): Beam
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = bottom, top
		b.Width0, b.Width1 = width, width
		b.FaceCamera = true
		b.LightEmission = 1
		b.Segments = 1
		b.Color = ColorSequence.new(colour)
		b.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, transparency or 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		if texture then
			b.Texture = texture
			b.TextureMode = Enum.TextureMode.Wrap
			b.TextureLength = 6
			b.TextureSpeed = scroll or 0
		end
		b.Parent = part
		table.insert(beams, b)
		return b
	end
	beam(spec.Width, nil, nil, if isSky then 0.2 else spec.Transparency)
	local pillar: Pillar = {
		Model = model,
		Part = part,
		Beams = beams,
		Top = top,
		Bottom = bottom,
		Rings = {},
		Guard = nil,
		Emitter = nil,
		Crown = {},
		Rays = nil,
		Light = nil,
		Grade = grade,
		Height = spec.Height,
		BornAt = os.clock(),
		DropUntil = if dropFromSky then os.clock() + Fx.L3_2_Pillar.DropSeconds else 0,
		Full = full,
	}
	if full and not low then
		if grade == "Super" then
			beam(spec.Width * 1.4, Kit.Textures.Sparkle, spec.ScrollTilesPerSecond * 6, 0.5)
		elseif isSky then
			beam(spec.OuterWidth, Kit.Textures.Sparkle, 4, spec.OuterTransparency)
		end
		local attachment = Instance.new("Attachment")
		attachment.Parent = part
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = Kit.Textures.Star4
		emitter.Color = ColorSequence.new(colour)
		emitter.Rate = if grade == "Star" then 4 else 10
		emitter.Speed = NumberRange.new(8)
		emitter.Lifetime = NumberRange.new(2)
		emitter.Size = NumberSequence.new(if grade == "Star" then 0.6 else 0.9, 0)
		emitter.LightEmission = 1
		emitter.SpreadAngle = Vector2.new(15, 15)
		emitter.Parent = attachment
		pillar.Emitter = emitter
	end
	local ringCount = if full and grade ~= "Star" and not low then 2 else 1
	for _ = 1, ringCount do
		table.insert(
			pillar.Rings,
			Kit.Ring(
				CFrame.new(part.Position + Vector3.new(0, 0.2, 0)),
				Kit.RarityColour(tier),
				if low then 10 else 16
			)
		)
	end
	if isSky and full then
		for i = 1, spec.CrownStars do
			local crown = Instance.new("BillboardGui")
			crown.Size = UDim2.fromScale(spec.CrownSize, spec.CrownSize)
			crown.LightInfluence = 0
			crown.AlwaysOnTop = false
			crown.MaxDistance = 2000
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.Size = UDim2.fromScale(1, 1)
			image.Image = Kit.Textures.Star4
			image.ImageColor3 = Theme.CoreLoop.JackpotRays
			image.Parent = crown
			local a = Instance.new("Attachment")
			a.Name = "Crown" .. i
			a.Parent = part
			crown.Adornee = a
			crown.Parent = part
			table.insert(pillar.Crown, crown)
		end
		local rays = Instance.new("Part")
		rays.Anchored, rays.CanCollide, rays.CanQuery, rays.CanTouch = true, false, false, false
		rays.Transparency = 1
		rays.Size = Vector3.new(spec.BaseRingRadius * 2.4, 0.1, spec.BaseRingRadius * 2.4)
		rays.CFrame = CFrame.new(part.Position + Vector3.new(0, 0.1, 0))
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top
		decal.Texture = Theme.Images.Rays
		decal.Color3 = Theme.CoreLoop.JackpotRays
		decal.Transparency = 0.3
		decal.Parent = rays
		rays.Parent = Kit.Root()
		pillar.Rays = rays
		if Kit.Tier() ~= "Low" then
			local light = Instance.new("PointLight")
			light.Color = Theme.CoreLoop.Jackpot
			light.Brightness = spec.LightBrightness
			light.Range = spec.LightRange
			light.Parent = part
			pillar.Light = light
		end
	end
	if model:GetAttribute("Guarded") == true then
		local guard = Kit.Ring(
			CFrame.new(part.Position + Vector3.new(0, 0.25, 0)),
			Theme.CoreLoop.Guarded,
			12,
			0.6
		)
		guard.Set(Fx.L3_2_Pillar.GuardedRingRadius, 0) -- L3.2: radius 7 (the ring is built at radius 1)
		for i, segment in guard.Model:GetChildren() do
			if (segment :: BasePart):IsA("BasePart") then
				local ringPart = segment :: BasePart
				ringPart.Color = if i % 2 == 0 then Color3.new(1, 1, 1) else Theme.CoreLoop.Guarded
				-- Neon shifts #FF8A2A towards yellow; the hazard ring must read as the Guarded token.
				ringPart.Material = Enum.Material.SmoothPlastic
			end
		end
		pillar.Guard = guard
	end
	if dropFromSky then
		Kit.Sound("CL_STAR_DROP", { position = part.Position })
	end
	pillars[model] = pillar
	return pillar
end

local function updatePillar(pillar: Pillar, t: number, serverNow: number, mine: boolean)
	local model = pillar.Model
	local position = model:GetPivot().Position
	local ground = feet(model)
	pillar.Part.CFrame = CFrame.new(Vector3.new(position.X, ground.Y, position.Z))
	-- Beam drop (F2): the pillar grows down from 120 studs to the ground in 0.5 s (Quad-in).
	local bottomY = 0
	if t < pillar.DropUntil then
		local alpha = 1 - (pillar.DropUntil - t) / Fx.L3_2_Pillar.DropSeconds
		local eased = alpha * alpha
		local from = Fx.L3_2_Pillar.DropFromHeight
		bottomY = from * (1 - eased)
		pillar.Top.Position = Vector3.new(0, math.max(pillar.Height, from), 0)
	elseif pillar.DropUntil > 0 then
		pillar.DropUntil = 0
		pillar.Top.Position = Vector3.new(0, pillar.Height, 0)
		Kit.Flash(model, Color3.new(1, 1, 1), 0.12, 0.2)
		if pillar.Full and pillar.Grade ~= "Star" then
			Kit.RingBurst(ground, Color3.new(1, 1, 1), 1, 7, 0.2)
		end
	end
	pillar.Bottom.Position = Vector3.new(0, bottomY, 0)
	-- LEAVING (L3.6): ring turns orange and drains like a clock; the pillar flickers in the last 5 s.
	local leavingUntil = model:GetAttribute("StarLeavingUntil")
	local leftFraction = 1
	local flicker = false
	if type(leavingUntil) == "number" then
		local left = leavingUntil - serverNow
		leftFraction = math.clamp(left / CoreLoop.Star.LeavingWarnSeconds, 0, 1)
		flicker = left <= 5 and math.floor(left * 2) % 2 == 0
	end
	local base = Fx.L3_2_Pillar.Star.Transparency
		+ (if mine then 0 else Fx.L3_2_Pillar.OtherPlayersExtraTransparency)
	for index, beam in pillar.Beams do
		local transparency = if flicker
			then 0.6
			elseif index == 1 then (if pillar.Grade == "Jackpot" then 0.2 else base)
			else 0.5
		if not mine then
			transparency = math.min(0.95, transparency + 0.2)
		end
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	if pillar.Emitter then
		pillar.Emitter.Enabled = mine
	end
	local pulse = 1
		+ 0.15 * (0.5 + 0.5 * math.sin(t / Fx.L3_2_Pillar.Star.PulseSeconds * 2 * math.pi))
	local ringRadius = if pillar.Grade == "Jackpot"
		then Fx.L3_3_SkyBeam.BaseRingRadius
		else (Fx.L3_2_Pillar.BaseRingRadius :: any)[pillar.Grade] or 4
	for i, ring in pillar.Rings do
		local scale = if not pillar.Full or Kit.Tier() == "Low"
			then 1
			elseif i == 1 then pulse
			else 2.15 - pulse
		ring.Model:PivotTo(CFrame.new(pillar.Part.Position + Vector3.new(0, 0.2, 0)))
		ring.Set(ringRadius * scale, if mine then 0.1 else 0.55)
		-- Drain: hide the segments past the remaining fraction (clockwise from 12).
		local segments = ring.Model:GetChildren()
		for s, segment in segments do
			local visible = (s - 0.5) / #segments <= leftFraction
			local part = segment :: BasePart
			if leftFraction < 1 then
				part.Color = Theme.CoreLoop.Leaving
			end
			if not visible then
				part.Transparency = 1
			end
		end
	end
	if pillar.Guard then
		local yaw = if pillar.Full and Kit.Tier() ~= "Low"
			then math.rad(Fx.L3_2_Pillar.GuardedRingDegPerSecond * t)
			else 0
		pillar.Guard.Model:PivotTo(
			CFrame.new(pillar.Part.Position + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, yaw, 0)
		)
	end
	if #pillar.Crown > 0 then
		for i, crown in pillar.Crown do
			local a = crown.Adornee :: Attachment
			local angle = math.rad(Fx.L3_3_SkyBeam.CrownDegPerSecond * t)
				+ i * 2 * math.pi / #pillar.Crown
			a.Position = Vector3.new(math.cos(angle) * 6, pillar.Height - 6, math.sin(angle) * 6)
		end
	end
	if pillar.Rays then
		pillar.Rays.CFrame = CFrame.new(pillar.Part.Position + Vector3.new(0, 0.1, 0))
			* CFrame.Angles(0, t * 0.3, 0)
	end
end

------------------------------------------------------------------ pop / arrivals (F1-F3, L3.1, L3.4, L3.5)

local popsRunning = 0
local popQueue: { () -> () } = {}

local function hideModel(model: Model, hidden: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function playPop(model: Model, flashScale: number?)
	if model.Parent == nil then
		return
	end
	local full = Kit.Approved("Group3_Arrivals")
	local tier = tierOf(model)
	local foot = feet(model)
	hideModel(model, false)
	-- Client visual scale 0.2 -> 1.15 -> 1.0 over 0.35 s (Back-out). Local only; the hitbox is server-side.
	local original = model:GetScale()
	local ok = pcall(function()
		model:ScaleTo(original * Fx.L3_1_Pop.ScaleFrom)
	end)
	if ok then
		task.spawn(function()
			local started = os.clock()
			local seconds = Fx.L3_1_Pop.Seconds
			while model.Parent do
				local alpha = math.clamp((os.clock() - started) / seconds, 0, 1)
				-- Back-out style: overshoot to ScaleOver at ~70% then settle.
				local s = if alpha < 0.7
					then Fx.L3_1_Pop.ScaleFrom
						+ (Fx.L3_1_Pop.ScaleOver - Fx.L3_1_Pop.ScaleFrom) * (alpha / 0.7)
					else Fx.L3_1_Pop.ScaleOver + (1 - Fx.L3_1_Pop.ScaleOver) * ((alpha - 0.7) / 0.3)
				pcall(function()
					model:ScaleTo(original * s)
				end)
				if alpha >= 1 then
					break
				end
				task.wait()
			end
			pcall(function()
				model:ScaleTo(original)
			end)
		end)
	end
	Kit.RingBurst(
		foot,
		Kit.RarityColour(tier),
		1,
		Fx.L3_1_Pop.FlashRingTo * (flashScale or 1),
		Fx.L3_1_Pop.FlashRingSeconds
	)
	Kit.Sound("CL_POP", { position = foot, pitch = 0.9 + math.random() * 0.2 })
	if full then
		Kit.Burst(foot, {
			texture = Kit.Textures.Chunk,
			count = Kit.Count(Fx.L3_1_Pop.Chunks, Fx.L3_1_Pop.ChunksLow),
			color = groundColour(foot),
			speed = NumberRange.new(14, 22),
			size = NumberSequence.new(0.4, 0.2),
			lifetime = NumberRange.new(0.5, 0.8),
			spread = 30,
			gravity = -60,
			lightEmission = 0,
		})
		Kit.Burst(foot + Vector3.new(0, 0.5, 0), {
			texture = Kit.Textures.Dust,
			count = Kit.Count(Fx.L3_1_Pop.Dust, Fx.L3_1_Pop.DustLow),
			color = Color3.fromRGB(235, 225, 205),
			speed = NumberRange.new(6),
			size = NumberSequence.new(1.5, 3.5),
			lifetime = NumberRange.new(0.6),
			transparency = NumberSequence.new(0.2, 1),
			spread = 90,
			lightEmission = 0,
			direction = Enum.NormalId.Top,
		})
		Kit.Light(
			foot + Vector3.new(0, 2, 0),
			Kit.GlowColour(tier),
			Fx.L3_1_Pop.LightBrightness,
			Fx.L3_1_Pop.LightRange,
			0.3
		)
	end
end

local function queuePop(model: Model, flashScale: number?)
	-- F5: at most MaxPopsAtOnce animate at once per client; the queue drains within 0.6 s.
	if popsRunning < CoreLoop.Fx.MaxPopsAtOnce then
		popsRunning += 1
		if RunService:IsStudio() then
			-- QA (F-1): the most pops this client has animated at once (client-local attribute).
			local peak = ReplicatedStorage:GetAttribute("CoreLoopPopsPeak") or 0
			if popsRunning > peak then
				ReplicatedStorage:SetAttribute("CoreLoopPopsPeak", popsRunning)
			end
			ReplicatedStorage:SetAttribute(
				"CoreLoopPopsTotal",
				(ReplicatedStorage:GetAttribute("CoreLoopPopsTotal") or 0) + 1
			)
		end
		playPop(model, flashScale)
		task.delay(Fx.L3_1_Pop.Seconds, function()
			popsRunning -= 1
			local nextPop = table.remove(popQueue, 1)
			if nextPop then
				nextPop()
			end
		end)
	else
		table.insert(popQueue, function()
			queuePop(model, flashScale)
		end)
		task.delay(0.6, function()
			-- Never hold a brainrot invisible: anything still queued after 0.6 s pops plainly.
			hideModel(model, false)
		end)
	end
end

local function playMeteor(model: Model)
	local m = Fx.L3_4_Meteor
	local full = Kit.Approved("Group3_Arrivals")
	local target = feet(model)
	local tier = tierOf(model)
	hideModel(model, true)
	local yaw = math.random() * 2 * math.pi
	local horizontal = m.FromHeight / math.tan(math.rad(90 - m.AngleDeg))
	local start = target
		+ Vector3.new(math.cos(yaw) * horizontal, m.FromHeight, math.sin(yaw) * horizontal)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 4
	ball.Material = Enum.Material.Neon
	ball.Color = Kit.GlowColour(tier)
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
	ball.CFrame = CFrame.new(start)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.5, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.5, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.3
	trail.Color = ColorSequence.new(Theme.CoreLoop.Jackpot, Kit.GlowColour(tier))
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.LightEmission = 1
	trail.Parent = ball
	ball.Parent = Kit.Root()
	TweenService:Create(
		ball,
		TweenInfo.new(m.StreakSeconds, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(target) }
	):Play()
	task.delay(m.StreakSeconds, function()
		ball:Destroy()
		-- Impact: flash sphere 2 -> 14, shockwave ring 2 -> 12, chunks, dust, shake within 80 studs.
		local flash = Instance.new("Part")
		flash.Shape = Enum.PartType.Ball
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.new(1, 1, 1)
		flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch = true, false, false, false
		flash.Size = Vector3.one * 4
		flash.CFrame = CFrame.new(target)
		flash.Parent = Kit.Root()
		TweenService
			:Create(flash, TweenInfo.new(0.15), { Size = Vector3.one * 28, Transparency = 1 })
			:Play()
		Debris:AddItem(flash, 0.2)
		Kit.RingBurst(target, Color3.new(1, 1, 1), 2, m.ImpactRing, m.ImpactSeconds)
		Kit.Sound("CL_METEOR", { position = target })
		if full then
			Kit.Burst(target, {
				texture = Kit.Textures.Chunk,
				count = Kit.Count(m.Chunks, m.ChunksLow),
				color = groundColour(target),
				speed = NumberRange.new(18, 30),
				size = NumberSequence.new(0.6, 0.2),
				lifetime = NumberRange.new(0.6, 1),
				spread = 40,
				gravity = -60,
				lightEmission = 0,
			})
			Kit.Burst(target, {
				texture = Kit.Textures.Dust,
				count = Kit.Count(m.Dust, m.DustLow),
				color = Color3.fromRGB(220, 210, 190),
				speed = NumberRange.new(8),
				size = NumberSequence.new(2, 5),
				lifetime = NumberRange.new(0.8),
				transparency = NumberSequence.new(0.2, 1),
				spread = 90,
				lightEmission = 0,
			})
			-- Smoking crater until ~6 s.
			local smokeAnchor = Kit.Anchor(target, m.SmokeSeconds + 1)
			local attachment = Instance.new("Attachment")
			attachment.Parent = smokeAnchor
			local smoke = Instance.new("ParticleEmitter")
			smoke.Texture = Kit.Textures.Dust
			smoke.Color = ColorSequence.new(Theme.CoreLoop.NotYours)
			smoke.Rate = 3
			smoke.Speed = NumberRange.new(2, 3)
			smoke.Size = NumberSequence.new(1.5, 4)
			smoke.Transparency = NumberSequence.new(0.4, 1)
			smoke.Lifetime = NumberRange.new(2)
			smoke.LightEmission = 0
			smoke.Parent = attachment
			task.delay(m.SmokeSeconds, function()
				smoke.Enabled = false
			end)
		end
		if (camera.CFrame.Position - target).Magnitude <= m.ShakeRadius then
			shake(0.3, 0.2)
		end
		task.delay(0.05, function()
			queuePop(model, nil)
		end)
	end)
end

local function playRift(model: Model)
	local r = Fx.L3_5_Rift
	local full = Kit.Approved("Group3_Arrivals")
	local target = feet(model)
	local tier = tierOf(model)
	hideModel(model, true)
	local tearAt = target + Vector3.new(0, r.TearHeight, 0)
	-- Sky tear (CL_Spiral fallback: a rotating segment ring that grows 0 -> 30, rarity colour + gold).
	local tear = Kit.Ring(
		CFrame.new(tearAt) * CFrame.Angles(math.rad(90), 0, 0),
		Kit.RarityColour(tier),
		18,
		1.2
	)
	local started = os.clock()
	task.spawn(function()
		while os.clock() - started < r.TearSeconds do
			local alpha = (os.clock() - started) / r.TearSeconds
			local spin = if full and Kit.Tier() ~= "Low"
				then (os.clock() - started) * math.rad(120)
				else 0
			tear.Model:PivotTo(CFrame.new(tearAt) * CFrame.Angles(math.rad(90), spin, 0))
			tear.Set(math.max(0.5, r.TearSize * 0.5 * alpha), 0)
			if full and Kit.Tier() ~= "Low" and math.random() < 0.08 then
				Kit.Flash(tear.Model, Theme.CoreLoop.Jackpot, 0.08, 0)
			end
			task.wait()
		end
		tear.Destroy()
		-- Beam slam + flash + confetti, then the Star pops with a 1.4x flash ring.
		local beamPart = Kit.Anchor(target, 1)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 300, 0)
		a0.Parent = beamPart
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 300, 0)
		a1.Parent = beamPart
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Width0, beam.Width1 = 6, 6
		beam.Color = ColorSequence.new(Theme.CoreLoop.Jackpot)
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Parent = beamPart
		TweenService:Create(
			a1,
			TweenInfo.new(r.SlamSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = Vector3.zero }
		):Play()
		Kit.Sound("CL_RIFT", { position = target })
		task.delay(r.SlamSeconds, function()
			Kit.RingBurst(target, Theme.CoreLoop.Jackpot, 2, 14, 0.3)
			if full then
				Kit.Burst(target + Vector3.new(0, 3, 0), {
					texture = Kit.Textures.Confetti,
					count = Kit.Count(r.Confetti, r.ConfettiLow),
					color = Theme.CoreLoop.Jackpot,
					speed = NumberRange.new(20, 35),
					size = NumberSequence.new(0.5),
					lifetime = NumberRange.new(1, 1.6),
					spread = 70,
					gravity = -30,
				})
			end
			shake(0.35, 0.25)
			queuePop(model, 1.4)
		end)
	end)
end

------------------------------------------------------------------ Dive (L3.6)

local function playDive(model: Model)
	local d = Fx.L3_6_Dive
	local full = Kit.Approved("Group2_StarKit")
	local pivot = model:GetPivot()
	local original = model:GetScale()
	local foot = feet(model)
	Kit.Sound("CL_DIVE", { position = foot })
	task.spawn(function()
		local function scaleTo(s: number)
			pcall(function()
				model:ScaleTo(original * s)
			end)
		end
		scaleTo(d.Squash)
		task.wait(0.15)
		scaleTo(1)
		local hopStart = os.clock()
		while os.clock() - hopStart < d.HopSeconds and model.Parent do
			local alpha = (os.clock() - hopStart) / d.HopSeconds
			model:PivotTo(pivot + Vector3.new(0, d.Hop * math.sin(alpha * math.pi * 0.5), 0))
			task.wait()
		end
		local sinkStart = os.clock()
		local high = pivot + Vector3.new(0, d.Hop, 0)
		while os.clock() - sinkStart < d.SinkSeconds and model.Parent do
			local alpha = (os.clock() - sinkStart) / d.SinkSeconds
			scaleTo(1 - 0.4 * alpha)
			model:PivotTo(high - Vector3.new(0, (d.Hop + 4) * alpha, 0))
			task.wait()
		end
		Kit.Burst(foot, {
			texture = Kit.Textures.Dust,
			count = Kit.Count(d.Dust, d.DustLow),
			color = Color3.fromRGB(220, 205, 180),
			speed = NumberRange.new(6),
			size = NumberSequence.new(1.2, 3),
			lifetime = NumberRange.new(0.6),
			transparency = NumberSequence.new(0.2, 1),
			spread = 90,
			lightEmission = 0,
		})
		if full then
			Kit.Burst(foot, {
				texture = Kit.Textures.Chunk,
				count = Kit.Count(d.Dust, d.DustLow),
				color = groundColour(foot),
				speed = NumberRange.new(10, 16),
				size = NumberSequence.new(0.4, 0.2),
				lifetime = NumberRange.new(0.5),
				spread = 30,
				gravity = -60,
				lightEmission = 0,
			})
		end
		hideModel(model, true)
	end)
	local pillar = pillars[model]
	if pillar then
		-- The pillar shrinks upward and vanishes over 0.3 s.
		TweenService
			:Create(
				pillar.Bottom,
				TweenInfo.new(0.3),
				{ Position = Vector3.new(0, pillar.Height, 0) }
			)
			:Play()
		task.delay(0.3, function()
			destroyPillar(model)
		end)
	end
end

------------------------------------------------------------------ shimmer (K2, L3.8) and reveal (L3.9)

type Shimmer = { Emitter: ParticleEmitter, Highlight: Highlight }
local shimmers: { [Model]: Shimmer } = {}

local function setShimmer(model: Model, on: boolean)
	local current = shimmers[model]
	if on and not current then
		local body = bodyOf(model)
		if not body then
			return
		end
		local full = Kit.Approved("Group4_Mutations")
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = Kit.Textures.Star4
		emitter.Color = ColorSequence.new(Theme.CoreLoop.Shimmer, Theme.CoreLoop.ShimmerB)
		emitter.Rate = if Kit.Tier() == "Low" or not full
			then Fx.L3_8_Shimmer.RateLow
			else Fx.L3_8_Shimmer.Rate
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.5, 0.9),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Lifetime = NumberRange.new(0.8)
		emitter.Speed = NumberRange.new(0.5)
		emitter.LightEmission = 1
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.Parent = body
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = Fx.L3_8_Shimmer.Outline
		highlight.Adornee = model
		highlight.Parent = Kit.Root()
		shimmers[model] = { Emitter = emitter, Highlight = highlight }
	elseif not on and current then
		current.Emitter:Destroy()
		current.Highlight:Destroy()
		shimmers[model] = nil
	end
end

local MUTATION_JINGLE =
	{ Shiny = "J5a", Golden = "J5b", Glitched = "J5c", Radioactive = "J5d", Astral = "J5e" }

local function revealBurst(model: Model, mutationId: string, scale: number?)
	local r = Fx.L3_9_Reveal
	local k = scale or 1
	local full = Kit.Approved("Group4_Mutations")
	local colour = (Theme.Mutation :: any)[mutationId] or Theme.Color.Burst
	local centre = model:GetPivot().Position
	freeze(model, r.Freeze)
	Kit.Flash(model, Color3.new(1, 1, 1), r.Freeze, 0.1)
	task.delay(r.Freeze, function()
		Kit.RingBurst(feet(model), colour, 2, r.RingTo * k, 0.4)
		Kit.Sound(MUTATION_JINGLE[mutationId] or "J5a", { position = centre })
		if full then
			Kit.Burst(centre, {
				texture = Kit.Textures.Star4,
				count = math.max(1, math.floor(Kit.Count(r.Burst, r.BurstLow) * k)),
				color = colour,
				speed = NumberRange.new(10, 18),
				size = NumberSequence.new(0.9, 0),
				lifetime = NumberRange.new(0.6, 1),
				spread = 180,
			})
			local rays = Instance.new("BillboardGui")
			rays.Size = UDim2.fromScale(14 * k, 14 * k)
			rays.LightInfluence = 0
			rays.Adornee = model
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.Size = UDim2.fromScale(1, 1)
			image.Image = Theme.Images.Rays
			image.ImageColor3 = colour
			image.ImageTransparency = 0.25
			image.Parent = rays
			rays.Parent = Kit.Root()
			TweenService:Create(image, TweenInfo.new(r.RaysSeconds, Enum.EasingStyle.Linear), {
				Rotation = 60 * r.RaysSeconds,
				ImageTransparency = 1,
			}):Play()
			Debris:AddItem(rays, r.RaysSeconds)
		end
	end)
end

------------------------------------------------------------------ Mutation Rain strike (L3.12, K4)

-- A jagged Neon bolt (CL_Bolt fallback): mutation-colour shell with a white core. Returns its parts.
local function boltParts(from: Vector3, to: Vector3, width: number, colour: Color3): { BasePart }
	local points = { from }
	local steps = 6
	for i = 1, steps - 1 do
		local jitter = Vector3.new(math.random(-20, 20) / 10, 0, math.random(-20, 20) / 10)
		table.insert(points, from:Lerp(to, i / steps) + jitter)
	end
	table.insert(points, to)
	local parts = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		for _, layer in { { width, colour, 0.1 }, { width * 0.4, Color3.new(1, 1, 1), 0 } } do
			local segment = Instance.new("Part")
			segment.Material = Enum.Material.Neon
			segment.Anchored, segment.CanCollide, segment.CanQuery, segment.CanTouch =
				true, false, false, false
			segment.CastShadow = false
			segment.Size = Vector3.new(layer[1], layer[1], (b - a).Magnitude + layer[1] * 0.5)
			segment.CFrame = CFrame.lookAt((a + b) / 2, b)
			segment.Color = layer[2]
			segment.Transparency = layer[3]
			segment.Parent = Kit.Root()
			table.insert(parts, segment)
		end
	end
	return parts
end

local function rainStrike(payload: any)
	local x = Fx.L3_12_Rain
	local model: Model? = if typeof(payload.model) == "Instance" and payload.model:IsA("Model")
		then payload.model
		else nil
	local position: Vector3? = if model
		then model:GetPivot().Position
		elseif typeof(payload.position) == "Vector3" then payload.position
		else nil
	if not position then
		return
	end
	if (camera.CFrame.Position - position).Magnitude > x.VisibleStuds then
		return
	end
	local mutationId = if type(payload.mutation) == "string" then payload.mutation else "Shiny"
	local colour = (Theme.Mutation :: any)[mutationId] or Theme.Color.Burst
	local full = Kit.Approved("Group4_Mutations")
	local low = Kit.Tier() == "Low"
	local ground = if model then feet(model) else position
	local cloudAt = ground + Vector3.new(0, x.CloudHeight, 0)
	-- 0–0.5 s: a dark cloud gathers above the slot.
	if full and not low then
		Kit.Burst(cloudAt, {
			texture = Kit.Textures.Dust,
			count = 14,
			color = Theme.CoreLoop.RainCloud,
			speed = NumberRange.new(1, 3),
			size = NumberSequence.new(x.CloudSize * 0.4, x.CloudSize),
			lifetime = NumberRange.new(1.2, 1.6),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
			spread = 180,
			lightEmission = 0,
		})
	end
	task.delay(x.GatherSeconds, function()
		-- 0.5–0.6 s: the strike. Beams stacked, flicker 3x in 0.1 s; ground flash ring 0 -> 10.
		local beams = if full and not low then x.BoltBeams else x.BoltBeamsLow
		local parts = {}
		for i = 1, beams do
			local offset = Vector3.new((i - 1) * 0.6 - (beams - 1) * 0.3, 0, 0)
			for _, part in boltParts(cloudAt + offset, ground + offset, x.BoltWidth, colour) do
				table.insert(parts, part)
			end
		end
		task.spawn(function()
			local each = x.BoltSeconds / (x.BoltFlickers * 2)
			for _ = 1, x.BoltFlickers do
				for _, part in parts do
					part.LocalTransparencyModifier = 1
				end
				task.wait(each)
				for _, part in parts do
					part.LocalTransparencyModifier = 0
				end
				task.wait(each)
			end
			for _, part in parts do
				part:Destroy()
			end
		end)
		Kit.RingBurst(ground, colour, 0.5, x.FlashRingTo, 0.25)
		Kit.Sound("CL_RAIN_STRIKE", { position = ground })
		task.delay(x.BoltSeconds, function()
			-- 0.6 s: recolour burst (L3.9 at 70%) and the "+GOLDEN!" shout over the slot.
			if model and model.Parent then
				revealBurst(model, mutationId, x.BurstScale)
				Kit.Shout(model, "+" .. string.upper(mutationId) .. "!", colour, 1.6, 36) -- mutation colour, not the gold gradient
			end
			-- 0.6–3.0 s: lingering sparkles in the mutation colour.
			if full and not low then
				local anchor = Kit.Anchor(position, x.SparkleSeconds + 1.5)
				local attachment = Instance.new("Attachment")
				attachment.Parent = anchor
				local sparkles = Instance.new("ParticleEmitter")
				sparkles.Texture = Kit.Textures.Star4
				sparkles.Color = ColorSequence.new(colour)
				sparkles.Rate = x.SparkleRate
				sparkles.Speed = NumberRange.new(1, 2)
				sparkles.Size = NumberSequence.new(0.8, 0)
				sparkles.Lifetime = NumberRange.new(1, 1.4)
				sparkles.SpreadAngle = Vector2.new(180, 180)
				sparkles.LightEmission = 1
				sparkles.Shape = Enum.ParticleEmitterShape.Sphere
				sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
				sparkles.Parent = attachment
				anchor.Size = Vector3.new(4, 4, 4)
				task.delay(x.SparkleSeconds, function()
					sparkles.Enabled = false
				end)
			end
		end)
	end)
end

------------------------------------------------------------------ behaviour reads (L3.10, L3.11)

type Watch = {
	Model: Model,
	Connections: { RBXScriptConnection },
	RunDust: ParticleEmitter?,
	Zzz: BillboardGui?,
	SavedRing: Kit.Ring?,
	Groggy: BillboardGui?,
	Sweat: ParticleEmitter?,
}
local watches: { [Model]: Watch } = {}
local lastScatterBubble: { [string]: number } = {}

local function read(model: Model, name: string, fn: (any) -> ())
	local watch = watches[model]
	if not watch then
		return
	end
	table.insert(
		watch.Connections,
		model:GetAttributeChangedSignal(name):Connect(function()
			local ok, err = pcall(fn, model:GetAttribute(name))
			if not ok then
				warn("[CoreLoopFx] " .. name .. ": " .. tostring(err))
			end
		end)
	)
end

local function setRunDust(watch: Watch, running: boolean)
	local full = Kit.Approved("Group5_Behaviour")
	if running and not watch.RunDust then
		local body = bodyOf(watch.Model)
		if not body then
			return
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "CoreLoopRunDust"
		attachment.Position = Vector3.new(0, -body.Size.Y * 0.5, 0)
		attachment.Parent = body
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = Kit.Textures.Dust
		emitter.Color =
			ColorSequence.new(groundColour(feet(watch.Model)):Lerp(Color3.new(1, 1, 1), 0.4))
		emitter.Rate = if Kit.Tier() == "Low" or not full then 3 else 8
		emitter.Speed = NumberRange.new(1, 3)
		emitter.Size = NumberSequence.new(0.8, 2)
		emitter.Transparency = NumberSequence.new(0.3, 1)
		emitter.Lifetime = NumberRange.new(0.5)
		emitter.LightEmission = 0
		emitter.Parent = attachment
		watch.RunDust = emitter
	elseif not running and watch.RunDust then
		local attachment = watch.RunDust.Parent
		watch.RunDust:Destroy()
		if attachment then
			attachment:Destroy()
		end
		watch.RunDust = nil
	end
end

local function setZzz(watch: Watch, sleeping: boolean, saved: boolean)
	if sleeping and not watch.Zzz then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "CoreLoopZzz"
		billboard.Size = UDim2.fromOffset(Theme.px(60), Theme.px(70))
		billboard.StudsOffsetWorldSpace = Vector3.new(1.5, 4.5, 0)
		billboard.LightInfluence = 0
		billboard.MaxDistance = 90
		billboard.Adornee = watch.Model
		local count = if Kit.Tier() == "Low" then 1 else 3
		for i = 1, count do
			local z = Instance.new("TextLabel")
			z.Name = "Z" .. i
			z.BackgroundTransparency = 1
			z.Text = if i == 1 then "Z" else "z"
			z.FontFace = Theme.Font.Display
			z.TextScaled = true
			z.TextColor3 = if saved then Theme.CoreLoop.Saved else Color3.new(1, 1, 1)
			z.Size = UDim2.fromScale(0.5 - (i - 1) * 0.1, 0.4 - (i - 1) * 0.08)
			z.Position = UDim2.fromScale(0.1 + (i - 1) * 0.2, 0.6 - (i - 1) * 0.28)
			z.Rotation = -12
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.Color.Ink
			stroke.Thickness = Theme.px(2)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			stroke.Parent = z
			z.Parent = billboard
		end
		billboard.Parent = Kit.Root()
		watch.Zzz = billboard
	elseif sleeping and watch.Zzz then
		for _, z in watch.Zzz:GetChildren() do
			if z:IsA("TextLabel") then
				z.TextColor3 = if saved then Theme.CoreLoop.Saved else Color3.new(1, 1, 1)
			end
		end
	elseif not sleeping and watch.Zzz then
		watch.Zzz:Destroy()
		watch.Zzz = nil
	end
end

local function attach(model: Model)
	if watches[model] or not model:IsA("Model") then
		return
	end
	if model:GetAttribute("CoreLoopRole") == nil and model:GetAttribute("CoreLoopPen") == nil then
		return
	end
	local watch: Watch = { Model = model, Connections = {} }
	watches[model] = watch
	-- Arrivals: Stars arrive by meteor / rift / beam drop; everyone else pops.
	local isStar = model:GetAttribute("CoreLoopStar") == true
	local arrival = model:GetAttribute("Arrival")
	local age = Workspace:GetServerTimeNow() - (model:GetAttribute("Phase12EmergenceReadyAt") or 0)
	local fresh = age < 1.5 or model:GetAttribute("CoreLoopPen") ~= nil
	if fresh then
		if isStar and arrival == "Meteor" then
			playMeteor(model)
		elseif isStar and arrival == "Rift" then
			playRift(model)
		else
			queuePop(model, nil)
		end
	end
	if model:GetAttribute("CoreLoopShimmer") == true then
		setShimmer(model, true)
	end
	read(model, "CoreLoopShimmer", function(value)
		setShimmer(model, value == true)
	end)
	read(model, "BrainrotMutationId", function(value)
		if
			type(value) == "string"
			and value ~= "None"
			and model:GetAttribute("CoreLoopShimmer") ~= true
		then
			revealBurst(model, value)
		end
	end)
	read(model, "StarDiving", function(value)
		if value then
			playDive(model)
		end
	end)
	read(model, "StarLeavingUntil", function()
		-- The pillar's ring handles the drain; tick in the last 5 s.
		task.spawn(function()
			local untilAt = model:GetAttribute("StarLeavingUntil")
			while model.Parent and type(untilAt) == "number" do
				local left = untilAt - Workspace:GetServerTimeNow()
				if left <= 0 then
					break
				end
				if left <= 5 then
					Kit.Sound("CL_LEAVING_TICK", { position = model:GetPivot().Position })
				end
				task.wait(1)
			end
		end)
	end)
	read(model, "CoreLoopNoticeAt", function()
		Kit.Bubble(model, "?", Color3.new(1, 1, 1), 0.4, Theme.Color.Ink)
	end)
	read(model, "CoreLoopAlertAt", function()
		Kit.Bubble(model, "!", Theme.CoreLoop.Alert, CoreLoop.Behaviour.TelegraphSeconds)
		Kit.Sound("CL_ALERT", { position = model:GetPivot().Position })
	end)
	read(model, "CoreLoopTauntAt", function()
		Kit.Bubble(model, "NYAH!", Color3.new(1, 1, 1), 0.8) -- board 6: white pill, white text + ink stroke
		Kit.Sound("CL_TAUNT", { position = model:GetPivot().Position })
	end)
	read(model, "CoreLoopStaggerUntil", function()
		Kit.Flash(model, Color3.new(1, 1, 1), 0.08, 0.3)
	end)
	read(model, "CoreLoopScatterAt", function()
		local watchNow = watches[model]
		if watchNow then
			setRunDust(watchNow, true)
			task.delay(CoreLoop.Behaviour.Herd.ScatterSeconds, function()
				if watches[model] then
					setRunDust(watches[model], model:GetAttribute("Motion") == "Run")
				end
			end)
		end
		local herdId = tostring(model:GetAttribute("CoreLoopHerdId"))
		if os.clock() - (lastScatterBubble[herdId] or 0) > 1 then
			lastScatterBubble[herdId] = os.clock() -- one "!" per herd, not one per member
			Kit.Bubble(model, "!", Theme.CoreLoop.Alert, 0.6)
		end
	end)
	read(model, "CoreLoopExhaustedUntil", function(value)
		local watchNow = watches[model]
		if not watchNow or type(value) ~= "number" then
			return
		end
		local body = bodyOf(model)
		if body and not watchNow.Sweat then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(Color3.fromRGB(154, 210, 255))
			emitter.Rate = 1 / 0.6 * 2
			emitter.Speed = NumberRange.new(4, 6)
			emitter.Acceleration = Vector3.new(0, -20, 0)
			emitter.Size = NumberSequence.new(0.5, 0.2)
			emitter.Lifetime = NumberRange.new(0.6)
			emitter.SpreadAngle = Vector2.new(40, 40)
			emitter.Parent = body
			watchNow.Sweat = emitter
			task.delay(value - Workspace:GetServerTimeNow(), function()
				emitter:Destroy()
				if watches[model] then
					watches[model].Sweat = nil
				end
			end)
		end
	end)
	read(model, "CoreLoopGroggyUntil", function(value)
		if type(value) ~= "number" then
			return
		end
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(Theme.px(70), Theme.px(30))
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		billboard.LightInfluence = 0
		billboard.Adornee = model
		local stars = if Kit.Tier() == "Low" then 1 else 3
		local labels = {}
		for i = 1, stars do
			local star = Instance.new("TextLabel")
			star.BackgroundTransparency = 1
			star.Size = UDim2.fromScale(0.3, 0.8)
			star.Text = "★"
			star.TextScaled = true
			star.TextColor3 = Theme.Color.Burst
			star.Parent = billboard
			labels[i] = star
		end
		billboard.Parent = Kit.Root()
		local started = os.clock()
		local seconds = math.max(0.2, value - Workspace:GetServerTimeNow())
		task.spawn(function()
			while os.clock() - started < seconds do
				local base = math.rad(300) * (os.clock() - started)
				for i, star in labels do
					local angle = base + i * 2 * math.pi / #labels
					star.Position =
						UDim2.fromScale(0.35 + math.cos(angle) * 0.35, 0.1 + math.sin(angle) * 0.2)
				end
				task.wait()
			end
			billboard:Destroy()
		end)
	end)
	read(model, "Motion", function(value)
		local watchNow = watches[model]
		if watchNow then
			setRunDust(watchNow, value == "Run")
		end
	end)
	local function sleepState()
		local watchNow = watches[model]
		if not watchNow then
			return
		end
		local sleeping = model:GetAttribute("Captured") == true
			and model:GetAttribute("BrainrotDisplayState") == "Sleeping"
		local saved = model:GetAttribute("SavedOwnerUserId") ~= nil
		setZzz(watchNow, sleeping, saved)
		if saved and sleeping and not watchNow.SavedRing then
			watchNow.SavedRing = Kit.Ring(
				CFrame.new(feet(model) + Vector3.new(0, 0.2, 0)),
				Theme.CoreLoop.Saved,
				12,
				0.3
			)
		elseif not (saved and sleeping) and watchNow.SavedRing then
			watchNow.SavedRing.Destroy()
			watchNow.SavedRing = nil
		end
	end
	read(model, "Captured", sleepState)
	read(model, "BrainrotDisplayState", sleepState)
	read(model, "SavedOwnerUserId", sleepState)
	sleepState()
	table.insert(
		watch.Connections,
		model.AncestryChanged:Connect(function()
			if model.Parent == nil then
				local w = watches[model]
				if w then
					for _, c in w.Connections do
						c:Disconnect()
					end
					if w.Zzz then
						w.Zzz:Destroy()
					end
					if w.SavedRing then
						w.SavedRing.Destroy()
					end
				end
				watches[model] = nil
				setShimmer(model, false)
				destroyPillar(model)
			end
		end)
	)
end

------------------------------------------------------------------ KO juice + HUD texts (D2, L3.7, L4.6)

local gui: ScreenGui? = nil
local comboFrame: Frame? = nil
local comboLabel: TextLabel? = nil
local comboRing: any = nil

local function hudGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	gui = StudPop.ScreenGui("CoreLoopFxHud", 6)
	return gui :: ScreenGui
end

local function centreShout(
	text: string,
	colour: Color3,
	px: number,
	yScale: number,
	seconds: number,
	strokeColour: Color3?
)
	local label = StudPop.Text(hudGui(), text, { display = true, maxPx = px, color = colour })
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, yScale)
	label.Size = UDim2.new(0.8, 0, 0, Theme.px(px) * 1.3)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = Theme.px(5)
		if strokeColour then
			stroke.Color = strokeColour
		end
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Debris:AddItem(label, seconds)
	return label
end

local COMBO_COLOURS = { "#FFFFFF", "#FFFFFF", "#FFE14A", "#FF8A2A", "#FF3D9E" }

local function showCombo(n: number)
	local c = Fx.L4_2_Combo
	if not comboFrame then
		local frame = Instance.new("Frame")
		frame.Name = "Combo"
		frame.BackgroundTransparency = 1
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromOffset(Theme.px(c.Ring), Theme.px(c.Ring))
		frame.Position =
			UDim2.new(0.5, Theme.px(c.OffsetFromReticle.X), 0.5, Theme.px(c.OffsetFromReticle.Y))
		local disc = Instance.new("Frame")
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromScale(c.Disc / c.Ring, c.Disc / c.Ring)
		disc.BackgroundColor3 = Theme.Color.Ink
		disc.BackgroundTransparency = 0.2
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = Color3.new(1, 1, 1)
		ringStroke.Thickness = Theme.px(6)
		ringStroke.Parent = disc
		disc.Parent = frame
		local label = StudPop.Text(disc, "", { display = true, maxPx = c.Px })
		label.TextScaled = false
		label.TextSize = Theme.px(c.Px * 0.75)
		local scale = Instance.new("UIScale")
		scale.Parent = frame
		frame.Parent = hudGui()
		comboFrame, comboLabel, comboRing = frame, label, ringStroke
	end
	local frame = comboFrame :: Frame
	local label = comboLabel :: TextLabel
	frame.Visible = true
	label.Text = "×" .. n
	label.TextSize = Theme.px((if n >= 6 then c.Px6 else c.Px) * 0.75)
	label.TextColor3 = if n >= 6
		then Color3.fromHSV((os.clock() % 1), 0.8, 1)
		else Color3.fromHex(COMBO_COLOURS[math.clamp(n, 1, 5)])
	local scale = frame:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.6
	frame.Rotation = (math.random() - 0.5) * 12
	TweenService:Create(scale, TweenInfo.new(c.PopSeconds, Enum.EasingStyle.Back), { Scale = 1 })
		:Play()
	TweenService:Create(frame, TweenInfo.new(c.PopSeconds), { Rotation = 0 }):Play()
	if comboRing then
		comboRing.Transparency = 0
		TweenService:Create(
			comboRing,
			TweenInfo.new(CoreLoop.Combo.WindowSeconds, Enum.EasingStyle.Linear),
			{ Transparency = 1 }
		):Play()
	end
	if n >= 4 and not Kit.ReducedMotion() then
		-- one-time screen-edge glow in the step colour
		local edge = Instance.new("Frame")
		edge.BackgroundTransparency = 1
		edge.Size = UDim2.fromScale(1, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Color = label.TextColor3
		stroke.Thickness = Theme.px(6)
		stroke.Parent = edge
		edge.Parent = hudGui()
		TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		Debris:AddItem(edge, 0.3)
	end
end

local function comboEnd(n: number)
	if comboFrame then
		local ribbon = centreShout(
			"COMBO ×" .. n .. "!",
			Color3.new(1, 1, 1),
			28,
			0.5,
			Fx.L4_2_Combo.EndSeconds
		)
		ribbon.Position = UDim2.new(0.5, Theme.px(90), 0.5, Theme.px(-10))
		task.delay(Fx.L4_2_Combo.EndSeconds, function()
			if comboFrame then
				comboFrame.Visible = false
			end
		end)
	end
	Kit.Sound("CL_COMBO_END", { pitch = 1 + math.min(n, 6) * 0.05 })
end

local function onKO(payload: any)
	local model = payload.model
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local j = CoreLoop.Juice
	local ko = Fx.L3_7_Ko
	local tier = tierOf(model)
	local grade = payload.grade
	local centre = model:GetPivot().Position
	if grade == "Jackpot" then
		-- 600 ms ceremony: freeze, gold flash, then BOOM + shake.
		freeze(model, j.JackpotCeremony)
		Kit.Flash(model, Theme.CoreLoop.Jackpot, 0.2, 0.1)
		task.delay(j.JackpotCeremony, function()
			Kit.Sound("BOOM_X", { position = centre })
			Kit.Sound("J4")
			shake(j.JackpotShake, 0.3)
			kickFov(j.JackpotFov, 0.3)
			centreShout("JACKPOT!", Theme.CoreLoop.Jackpot, 48, 0.3, 1.6)
			if payload.odds then
				centreShout(tostring(payload.odds), Color3.new(1, 1, 1), 16, 0.4, 1.6)
			end
			Kit.RingBurst(feet(model), Theme.CoreLoop.Jackpot, 2, 14, 0.4)
		end)
	elseif grade == "Super" or grade == "Star" then
		local isSuper = grade == "Super"
		freeze(model, if isSuper then j.SuperFreeze else j.StarFreeze)
		Kit.Flash(
			model,
			Kit.RarityColour(tier),
			if isSuper then ko.SuperFlash else ko.StarFlash,
			0.15
		)
		Kit.RingBurst(feet(model), Kit.RarityColour(tier), 2, ko.StarRingTo, 0.35)
		Kit.Burst(centre, {
			texture = Kit.Textures.Star4,
			count = Kit.Count(if isSuper then ko.SuperSparks else ko.StarSparks, ko.StarSparksLow),
			color = Kit.GlowColour(tier),
			speed = NumberRange.new(10, 16),
			size = NumberSequence.new(0.8, 0),
			lifetime = NumberRange.new(0.5, 0.8),
			spread = 180,
		})
		shake(if isSuper then j.SuperShake else j.StarShake, if isSuper then 0.15 else 0.12)
		kickFov(if isSuper then j.SuperFov else j.StarFov, 0.15)
		Kit.Shout(model, if isSuper then "SUPER STAR!" else "STAR!", nil, j.TextSeconds, 28, true)
		Kit.Sound(if isSuper then "J3" else "J2")
	else
		-- Snack KO: white flash, poof, "+zZz". No camera shake on snacks (D2).
		freeze(model, j.KoFreeze)
		Kit.Flash(model, Color3.new(1, 1, 1), ko.KoFlash, 0.2)
		Kit.Burst(centre, {
			texture = Kit.Textures.Dust,
			count = Kit.Count(ko.KoDust, ko.KoDustLow),
			color = Kit.RarityColour(tier),
			speed = NumberRange.new(4, 7),
			size = NumberSequence.new(1, 2.5),
			lifetime = NumberRange.new(0.5),
			transparency = NumberSequence.new(0.2, 1),
			spread = 180,
			lightEmission = 0,
		})
		Kit.Shout(model, "+zZz", nil, j.TextSeconds, 24)
		Kit.Sound("S3", { pitch = 2 ^ (math.max(0, (payload.combo or 1) - 1) / 12) })
	end
	if payload.sneak then
		Kit.Shout(model, "SNEAK SHOT!", Color3.fromRGB(201, 168, 255), 1.2, 28)
		Kit.Sound("CL_SNEAK")
	end
	if CoreLoopFlags.Part("Combo") and (payload.combo or 0) >= 2 then
		showCombo(payload.combo)
	end
end

local function onHit(payload: any)
	local model = payload.model
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	freeze(model, CoreLoop.Juice.HitFreeze)
	Kit.Flash(model, Color3.new(1, 1, 1), Fx.L3_7_Ko.HitFlash, 0.3)
	Kit.Burst(model:GetPivot().Position, {
		texture = Kit.Textures.Star4,
		count = Kit.Count(Fx.L3_7_Ko.HitSparks, Fx.L3_7_Ko.HitSparksLow),
		color = Color3.new(1, 1, 1),
		speed = NumberRange.new(8, 12),
		size = NumberSequence.new(0.6, 0),
		lifetime = NumberRange.new(0.3),
		spread = 180,
	})
	Kit.Sound("S1", { pitch = 1 })
	if payload.sneak then
		Kit.Shout(model, "SNEAK SHOT!", Color3.fromRGB(201, 168, 255), 1.2, 28)
		Kit.Sound("CL_SNEAK")
	end
end

-- A Stud Pop card for the board 2 reveal: surface (or flat colour) + ink lip, pops in, removes itself.
local function revealCard(
	size: Vector2,
	position: UDim2,
	variant: string?,
	flat: Color3?,
	radius: UDim,
	rotation: number,
	seconds: number
): Frame
	local holder = Instance.new("Frame")
	holder.Name = "RevealCard"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = position
	holder.Size = UDim2.fromOffset(Theme.px(size.X), Theme.px(size.Y))
	holder.Rotation = rotation
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BackgroundColor3 = Theme.Color.Ink
	lip.BorderSizePixel = 0
	lip.Position = UDim2.fromOffset(0, Theme.px(Theme.Size.Lip))
	lip.Size = UDim2.fromScale(1, 1)
	local lipCorner = Instance.new("UICorner")
	lipCorner.CornerRadius = radius
	lipCorner.Parent = lip
	lip.Parent = holder
	if variant then
		StudPop.Surface(holder, variant, radius)
	else
		local face = Instance.new("Frame")
		face.Name = "Face"
		face.BackgroundColor3 = flat or Theme.Color.Panel
		face.Size = UDim2.fromScale(1, 1)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = radius
		corner.Parent = face
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Color.Ink
		stroke.Thickness = Theme.px(Theme.Size.Stroke)
		stroke.Parent = face
		face.Parent = holder
	end
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 10
	content.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = holder
	holder.Parent = hudGui()
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Debris:AddItem(holder, seconds)
	return content
end

-- L4.6 reveal texts, laid out as board 2 (Reveal.dc.html, 844x390): the mutation shout at the top,
-- the "1 in N" pill under it, the NEW MUTATION gem sticker right of centre (+0.2 s) and the gold
-- UPGRADED ribbon at the bottom (+0.3 s, only when the grade rises). Total on screen <= 2.2 s.
local function onReveal(payload: any)
	local r = Fx.L3_9_Reveal
	local colour = (Theme.Mutation :: any)[payload.mutationId] or Theme.Color.Burst
	local seconds = CoreLoop.Juice.RevealTextSeconds
	task.delay(r.Freeze, function()
		centreShout(
			string.upper(payload.mutationId) .. "!",
			colour,
			r.ShoutPx,
			52 / 390,
			seconds,
			Theme.Color.Ink
		)
		if payload.odds then
			local pill = revealCard(
				Vector2.new(110, 28),
				UDim2.fromScale(0.5, 112 / 390),
				nil,
				Theme.Color.Panel,
				Theme.Radius.Pill,
				0,
				seconds
			)
			StudPop.Text(pill, tostring(payload.odds), { maxPx = 16 })
		end
		if payload.gems then
			task.delay(r.GemStickerDelay, function()
				local sticker = revealCard(
					Vector2.new(172, 62),
					UDim2.new(0.5, Theme.px(220), 162 / 390, 0),
					"gem",
					nil,
					Theme.Radius.Md,
					6,
					seconds - r.GemStickerDelay
				)
				local title = StudPop.Text(
					sticker,
					"NEW MUTATION!",
					{ display = true, maxPx = 16, size = UDim2.fromScale(1, 0.5) }
				)
				title.Position = UDim2.fromScale(0, 0.05)
				local row = Instance.new("Frame")
				row.BackgroundTransparency = 1
				row.Position = UDim2.fromScale(0, 0.5)
				row.Size = UDim2.fromScale(1, 0.42)
				row.Parent = sticker
				local list = Instance.new("UIListLayout")
				list.FillDirection = Enum.FillDirection.Horizontal
				list.HorizontalAlignment = Enum.HorizontalAlignment.Center
				list.VerticalAlignment = Enum.VerticalAlignment.Center
				list.Padding = UDim.new(0, Theme.px(5))
				list.SortOrder = Enum.SortOrder.LayoutOrder
				list.Parent = row
				local icon = Instance.new("ImageLabel")
				icon.BackgroundTransparency = 1
				icon.Image = Theme.Icons.Gem
				icon.Size = UDim2.fromOffset(Theme.px(18), Theme.px(18))
				icon.LayoutOrder = 1
				icon.Parent = row
				local amount = StudPop.Text(
					row,
					"+" .. tostring(payload.gems) .. " GEMS on bank",
					{ maxPx = 14, size = UDim2.fromScale(0.75, 1) }
				)
				amount.LayoutOrder = 2
			end)
		end
		if payload.upgradedTo then
			task.delay(r.UpgradeDelay, function()
				local word = if payload.upgradedTo == "Super"
					then "SUPER STAR"
					else string.upper(payload.upgradedTo)
				local ribbon = revealCard(
					Vector2.new(340, 48),
					UDim2.fromScale(0.5, 325 / 390),
					"burst",
					nil,
					Theme.Radius.Sm,
					0,
					seconds - r.UpgradeDelay
				)
				StudPop.Text(
					ribbon,
					utf8.char(0x1F451) .. " UPGRADED → " .. word .. "!",
					{ display = true, maxPx = 24, size = UDim2.fromScale(0.94, 0.8) }
				).Position =
					UDim2.fromScale(0.03, 0.1)
				if payload.upgradedTo == "Jackpot" then
					shake(CoreLoop.Juice.JackpotShake, 0.3)
					kickFov(CoreLoop.Juice.JackpotFov, 0.3)
					Kit.Sound("BOOM_L")
				end
			end)
		end
	end)
end

------------------------------------------------------------------ pillar scheduling

local function stepPillars()
	local t = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	local cameraPosition = camera.CFrame.Position
	local rows = {}
	local tagRows = {}
	for model in watches do
		if
			model:GetAttribute("CoreLoopStar") == true
			and not model:GetAttribute("StarDiving")
			and model.Parent
		then
			local grade = gradeOf(model)
			local distance = (model:GetPivot().Position - cameraPosition).Magnitude
			table.insert(tagRows, { Model = model, Grade = grade, Distance = distance })
			local low = Kit.Tier() == "Low"
			local reach = if grade == "Jackpot"
				then math.huge
				elseif grade == "Super" then (if low
					then Fx.L3_2_Pillar.Super.DrawDistanceLow
					else Fx.L3_2_Pillar.Super.DrawDistance)
				else (if low
					then Fx.L3_2_Pillar.Star.DrawDistanceLow
					else Fx.L3_2_Pillar.Star.DrawDistance)
			if distance <= reach then
				table.insert(rows, { Model = model, Grade = grade, Distance = distance })
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.Distance < b.Distance
	end)
	table.sort(tagRows, function(a, b)
		return a.Distance < b.Distance
	end)
	WorldTag.Step(tagRows) -- L4.5 Star tags (max 6, nearest first)
	local keep: { [Model]: boolean } = {}
	local starCount, skyCount = 0, 0
	for _, row in rows do
		local isSky = row.Grade == "Jackpot"
		if
			(isSky and skyCount >= CoreLoop.Star.MaxSkyBeams)
			or (not isSky and starCount >= CoreLoop.Star.MaxPillars)
		then
			continue
		end
		if isSky then
			skyCount += 1
		else
			starCount += 1
		end
		keep[row.Model] = true
		local pillar = pillars[row.Model]
		if pillar and pillar.Grade ~= row.Grade then
			-- Upgrade (K2): the pillar grows into the new grade's beam over 0.5 s.
			destroyPillar(row.Model)
			pillar = nil
		end
		if not pillar then
			local arrival = row.Model:GetAttribute("Arrival")
			local young = Workspace:GetServerTimeNow()
					- (row.Model:GetAttribute("Phase12EmergenceReadyAt") or 0)
				< 1
			pillar =
				buildPillar(row.Model, row.Grade, young and (arrival == nil or arrival == "Beam"))
		end
		updatePillar(
			pillar :: Pillar,
			t,
			serverNow,
			row.Model:GetAttribute("StarOwnerUserId") == localPlayer.UserId
		)
	end
	for model in table.clone(pillars) do
		if not keep[model] then
			destroyPillar(model)
		end
	end
	-- Shimmer outline pulse.
	for _, shimmer in shimmers do
		local s = Fx.L3_8_Shimmer
		local pulse = 0.5 + 0.5 * math.sin(t / s.PulseSeconds * 2 * math.pi)
		shimmer.Highlight.OutlineTransparency = s.Outline + (s.OutlinePulse - s.Outline) * pulse
	end
end

------------------------------------------------------------------ start

local function watchFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		task.spawn(attach, child :: any)
	end
	folder.ChildAdded:Connect(function(child)
		-- Attributes arrive with the model; give replication one frame to settle.
		task.defer(attach, child :: any)
	end)
end

function Controller.Start()
	if not CoreLoopFlags.Enabled() then
		return
	end
	task.spawn(function()
		local runtime = Workspace:WaitForChild("Runtime", 30)
		local brainrots = runtime and runtime:WaitForChild("Brainrots", 30)
		if brainrots then
			watchFolder(brainrots)
		end
	end)
	task.spawn(function()
		local pen = Workspace:WaitForChild("CoreLoopPen", math.huge)
		watchFolder(pen)
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local remote = remotes and remotes:WaitForChild("CoreLoopEvent", 30)
	if remote and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end
			local ok, err = pcall(function()
				if payload.kind == "KO" then
					onKO(payload)
				elseif payload.kind == "Hit" then
					onHit(payload)
				elseif payload.kind == "Reveal" then
					onReveal(payload)
				elseif payload.kind == "ComboEnd" then
					comboEnd(payload.n)
				elseif payload.kind == "NotYours" and typeof(payload.model) == "Instance" then
					Kit.Bubble(payload.model, "🔒 NOT YOURS YET", Theme.CoreLoop.NotYours, 1) -- board 6 grey pill
					Kit.Sound("CL_NOT_YOURS")
				elseif payload.kind == "Magnet" and typeof(payload.model) == "Instance" then
					Kit.Shout(payload.model, "+1", Color3.fromRGB(82, 255, 106), 0.8, 24)
				elseif payload.kind == "LuckyFull" then
					Kit.Sound("CL_METER_FULL")
				elseif payload.kind == "Rain" then
					rainStrike(payload)
				end
			end)
			if not ok then
				warn("[CoreLoopFx] event " .. tostring(payload.kind) .. ": " .. tostring(err))
			end
		end)
	end
	local last = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - last < 1 / 30 then
			return
		end
		last = os.clock()
		local ok, err = pcall(stepPillars)
		if not ok then
			warn("[CoreLoopFx] pillars: " .. tostring(err))
		end
	end)
end

-- Review pen hook: render every group's full look while the pen is active.
function Controller.SetPen(active: boolean)
	Kit.SetPen(active)
end

-- QA / pen entry points (same code paths as live events).
Controller._KO = onKO
Controller._Reveal = onReveal
Controller._Combo = showCombo
Controller._ComboEnd = comboEnd
Controller._Hit = onHit
Controller._Rain = rainStrike

return Controller
