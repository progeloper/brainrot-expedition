--!strict
-- Playtest Fixes Part C: the ONE weapon effects library (presentation only; no stats, no remotes).
--   Pure      Tier / Style / Counts: tier, colours and per-shot particle counts by graphics quality.
--   Recipes   NewEmitter(kind): every emitter this feature uses, built in code from engine textures.
--   Authoring Author(art, weaponId): idle/signature effects on a weapon's existing V4 parts (server for
--             held art via Phase13RuntimeService.applyWeapon; client for stall displays).
--   Pool      client only: muzzle / bolt / impact / sleep-puff rigs cloned once from templates kept in
--             ReplicatedStorage.CodeAssets.Effects, then reused round-robin. :Emit(n) only; nothing is
--             created per shot after warm-up.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Parent.Config.PlaytestFixes).WeaponFx
local WeaponTiersV2 = require(script.Parent.Parent.Config.WeaponTiersV2)

local Lib = {}
Lib.IdleTag = "PlaytestIdleFx"

local T = Config.Textures

-- Pure ---------------------------------------------------------------------------------------------

function Lib.Tier(weaponId: string?): number
	if type(weaponId) ~= "string" then
		return 1
	end
	local tier = WeaponTiersV2.TierFromWeaponId(weaponId)
	if tier then
		return math.clamp(tier, 1, 8)
	end
	local special = (WeaponTiersV2.Specials :: any)[weaponId]
	if special then
		return math.clamp(special.powerTier, 1, 8)
	end
	if weaponId == "HRP_001" then
		return 1
	end
	return 1
end

local function rainbowSequence(): ColorSequence
	local keys = {}
	local n = #Config.Rainbow
	for i, hex in Config.Rainbow do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (n - 1), Color3.fromHex(hex)))
	end
	return ColorSequence.new(keys)
end

export type Style = {
	tier: number,
	ladder: any,
	colour: Color3,
	sequence: ColorSequence,
	halo: Color3?,
	rainbow: boolean,
}

function Lib.Style(weaponId: string?): Style
	local tier = Lib.Tier(weaponId)
	local ladder = Config.Tiers[tier]
	local colour = Color3.fromHex(Config.TierColours[tier])
	local rainbow = ladder.rainbow == true
	return {
		tier = tier,
		ladder = ladder,
		colour = colour,
		sequence = if rainbow then rainbowSequence() else ColorSequence.new(colour),
		halo = if ladder.dark then Color3.fromHex(Config.HaloColour) else nil,
		rainbow = rainbow,
	}
end

export type Counts = {
	flash: number,
	muzzle: number,
	ring: number,
	shock: number,
	impact: number,
	ground: number,
	crack: number,
	puff: number,
	total: number,
}

-- Per-shot particle counts. Low halves the bursts and drops the secondary shockwave/crack/ring, but
-- every beat (flash, hit, ground ring, one Z) stays.
function Lib.Counts(tier: number, quality: string): Counts
	local l = Config.Tiers[math.clamp(tier, 1, 8)] :: any
	local low = quality == "Low"
	local c = {
		flash = l.flash or 0,
		muzzle = if low then math.floor((l.muzzle or 0) / 2) else (l.muzzle or 0),
		ring = if low then 0 else (l.ring or 0),
		shock = if low then 0 else (l.shock or 0),
		impact = if low then math.floor((l.impact or 0) / 2) else (l.impact or 0),
		ground = l.ground or 0,
		crack = if low then 0 else (l.crack or 0),
		puff = if low then math.min(1, l.puff or 0) else (l.puff or 0),
		total = 0,
	}
	c.total = c.flash + c.muzzle + c.ring + c.shock + c.impact + c.ground + c.crack + c.puff
	return c
end

-- Recipes ------------------------------------------------------------------------------------------

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

-- Every emitter starts disabled at Rate 0 unless it is an idle recipe.
function Lib.NewEmitter(kind: string, colour: ColorSequence?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "PTF_" .. kind
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = colour or ColorSequence.new(Color3.new(1, 1, 1))
	e.Enabled = true
	if kind == "Flash" then
		e.Texture, e.Lifetime, e.Speed = T.Flash, NumberRange.new(0.08, 0.12), NumberRange.new(0)
		e.Size, e.Transparency = seq(1.6, 0), seq(0, 1)
		e.ZOffset = 0.5
	elseif kind == "Spark" then
		e.Texture, e.Lifetime, e.Speed =
			T.Spark, NumberRange.new(0.2, 0.35), NumberRange.new(10, 18)
		e.SpreadAngle, e.Drag = Vector2.new(35, 35), 4
		e.Size, e.Transparency = seq(0.35, 0), seq(0, 1)
	elseif kind == "Ring" or kind == "Ground" then
		e.Texture, e.Speed = T.Ring, NumberRange.new(0.01)
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		e.EmissionDirection = if kind == "Ground" then Enum.NormalId.Top else Enum.NormalId.Front
		e.Lifetime = NumberRange.new(if kind == "Ground" then 0.45 else 0.25)
		e.Size = if kind == "Ground" then seq(0.5, 4) else seq(0.3, 2.5)
		e.Transparency = seq(0.2, 1)
	elseif kind == "Shock" then
		e.Texture, e.Lifetime, e.Speed = T.Ring, NumberRange.new(0.2), NumberRange.new(0)
		e.Size, e.Transparency = seq(0.5, 3.5), seq(0.3, 1)
	elseif kind == "Crack" then
		e.Texture, e.Lifetime, e.Speed = T.Implode, NumberRange.new(0.4), NumberRange.new(0)
		e.Size, e.Transparency = seq(3, 1), seq(0.1, 1)
		e.Rotation = NumberRange.new(0, 360)
	-- Authored idle / signature recipes.
	elseif kind == "FrostMist" then
		e.Texture, e.Rate, e.Lifetime = T.Smoke, 4, NumberRange.new(1.2, 1.8)
		e.Speed, e.SpreadAngle = NumberRange.new(0.2, 0.5), Vector2.new(180, 180)
		e.Size, e.Transparency = seq(0.3, 1), seq(0.55, 1)
		e.Color, e.LightEmission, e.LightInfluence =
			ColorSequence.new(Color3.fromHex("#D8FBFF")), 0.3, 0.3
	elseif
		kind == "CyanSparkle"
		or kind == "VioletSparks"
		or kind == "GoldSparkle"
		or kind == "TierAura"
	then
		local hex = if kind == "CyanSparkle"
			then "#6DEBFF"
			elseif kind == "VioletSparks" then "#9B4DFF"
			elseif kind == "GoldSparkle" then "#FFD447"
			else nil
		e.Texture, e.Lifetime = T.Spark, NumberRange.new(0.6, 1.0)
		e.Rate = if kind == "CyanSparkle" then 2 elseif kind == "VioletSparks" then 4 else 3
		e.Speed, e.SpreadAngle = NumberRange.new(0.4, 0.8), Vector2.new(180, 180)
		e.Size, e.Transparency = seq(0.28, 0), seq(0, 1)
		if hex then
			e.Color = ColorSequence.new(Color3.fromHex(hex))
		end
	elseif kind == "RiftTear" then
		e.Texture, e.Rate, e.Lifetime = T.Implode, 3, NumberRange.new(0.5)
		e.Speed, e.RotSpeed = NumberRange.new(0), NumberRange.new(120)
		e.Size, e.Transparency = seq(1.2, 0.2), seq(0.2, 1)
		e.Color = ColorSequence.new(Color3.fromHex("#9B4DFF"), Color3.fromHex("#2A0A4A"))
	elseif kind == "SpectrumSplit" then
		e.Texture, e.Lifetime = T.Spark, NumberRange.new(0.35)
		e.Speed, e.SpreadAngle = NumberRange.new(8, 12), Vector2.new(40, 40)
		e.Size, e.Transparency = seq(0.4, 0), seq(0, 1)
		e.Color = rainbowSequence()
		e:SetAttribute("EmitOnFire", 6) -- WeaponArtController bursts it on every drum snap
	end
	return e
end

-- Authoring ----------------------------------------------------------------------------------------

local function firstPart(root: Instance, name: string): BasePart?
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			return d
		end
	end
	return nil
end

local function largestPart(root: Instance): BasePart?
	local best, volume = nil, -1
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > volume then
				best, volume = d, v
			end
		end
	end
	return best
end

local function idle(e: ParticleEmitter)
	e:SetAttribute("PlaytestIdleFx", true)
	CollectionService:AddTag(e, Lib.IdleTag)
end

local function attach(part: BasePart, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = part
	return a
end

-- Four small shards on a rotor around `part`. Held art (handle given): the rotor rides an ArtMotor weld
-- tagged CampAnimRotor, so WeaponArtController spins it on the shared <=10 Hz scheduler.
local function orbitShards(art: Instance, part: BasePart, handle: BasePart?)
	local o = Config.OrbitShards
	local frame = CFrame.new(part.Position)
		* (if handle then handle.CFrame.Rotation else part.CFrame.Rotation)
	local rotor = Instance.new("Part")
	rotor.Name = "AnimRotor_PTF"
	rotor.Size = Vector3.new(0.1, 0.1, 0.1)
	rotor.Transparency = 1
	rotor.CFrame = frame
	rotor.CanCollide, rotor.CanQuery, rotor.CanTouch, rotor.CastShadow = false, false, false, false
	rotor.Massless = true
	rotor.Anchored = handle == nil
	rotor:SetAttribute("CampAnim", "Spin")
	rotor:SetAttribute("CampAnimRate", o.SpinDegreesPerSecond)
	rotor.Parent = art
	for i = 1, o.Count do
		local angle = (i - 1) / o.Count * math.pi * 2
		local shard = Instance.new("WedgePart")
		shard.Name = "OrbitShard"
		shard.Size = Vector3.new(0.18, 0.5, 0.3)
		shard.Material = Enum.Material.Neon
		shard.Color = Color3.fromHex("#9FF4FF")
		shard.CFrame = frame * CFrame.Angles(0, 0, angle) * CFrame.new(o.Radius, 0, 0)
		shard.CanCollide, shard.CanQuery, shard.CanTouch, shard.CastShadow =
			false, false, false, false
		shard.Massless = true
		shard.Anchored = handle == nil
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = rotor, shard
		weld.Parent = shard
		shard.Parent = art
	end
	if handle then
		local motor = Instance.new("Weld")
		motor.Name = "ArtMotor"
		motor.Part0 = handle
		motor.Part1 = rotor
		motor.C0 = handle.CFrame:ToObjectSpace(rotor.CFrame)
		motor.Parent = rotor
		CollectionService:AddTag(rotor, "CampAnimRotor")
	end
end

local function frostTrail(part: BasePart)
	local a0 = attach(part, "PTF_TrailA")
	local a1 = attach(part, "PTF_TrailB")
	a0.Position, a1.Position = Vector3.new(0, 0.25, 0), Vector3.new(0, -0.25, 0)
	local trail = Instance.new("Trail")
	trail.Name = "PTF_FrostTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.3
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromHex("#9FF4FF"), Color3.fromHex("#FFFFFF"))
	trail.Transparency = seq(0.2, 1)
	trail.Parent = part
end

local function hasIdleEmitter(art: Instance): boolean
	for _, d in art:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Enabled and d.Rate > 0 then
			return true
		end
	end
	return false
end

-- Adds the configured effects once (idempotent via an attribute). `handle` = the held tool's Handle,
-- nil for anchored stall displays. Returns how many effect instances were added.
function Lib.Author(art: Instance, weaponId: string, handle: BasePart?): number
	if art:GetAttribute("PlaytestFxAuthored") then
		return 0
	end
	art:SetAttribute("PlaytestFxAuthored", true)
	local added = 0
	for _, spec in (Config.Authored :: any)[weaponId] or {} do
		local part = firstPart(art, spec.part)
		if part then
			if spec.kind == "OrbitShards" then
				orbitShards(art, part, handle)
			elseif spec.kind == "FrostTrail" then
				frostTrail(part)
			else
				local e = Lib.NewEmitter(spec.kind)
				if e.Rate > 0 then
					idle(e)
				end
				e.Parent = attach(part, "PTF_" .. spec.kind)
			end
			added += 1
		end
	end
	local tier = Lib.Tier(weaponId)
	if
		Config.AuraTiers[tier]
		and not (WeaponTiersV2.Specials :: any)[weaponId]
		and not hasIdleEmitter(art)
	then
		local anchor = handle or largestPart(art)
		if anchor then
			local e = Lib.NewEmitter("TierAura", Lib.Style(weaponId).sequence)
			idle(e)
			e.Parent = attach(anchor, "PTF_TierAura")
			added += 1
		end
	end
	return added
end

-- Held-weapon budget numbers for the report: enabled emitters and their total Rate.
function Lib.Budget(art: Instance): (number, number)
	local emitters, rate = 0, 0
	for _, d in art:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Enabled then
			emitters += 1
			rate += d.Rate
		end
	end
	return emitters, rate
end

function Lib.BudgetFor(weaponId: string): any
	local tier = Lib.Tier(weaponId)
	if (WeaponTiersV2.Specials :: any)[weaponId] or tier == 8 then
		return Config.Budgets.Top
	elseif tier >= 5 and tier <= 6 then
		return Config.Budgets.Mid
	elseif tier == 7 then
		return nil -- as authored
	end
	return Config.Budgets.Low
end

-- Pool (client) ------------------------------------------------------------------------------------

local pool: any = nil
local created = 0

local function templates(): Folder
	local assets = ReplicatedStorage:FindFirstChild("CodeAssets")
	local effects = assets and assets:FindFirstChild("Effects")
	if not effects then
		effects = Instance.new("Folder")
		effects.Name = "Effects"
		effects.Parent = assets or ReplicatedStorage
	end
	local folder = effects :: Folder
	if folder:FindFirstChild("MuzzleFlash") then
		return folder
	end
	local function rig(name: string, kinds: { string }): Attachment
		local a = Instance.new("Attachment")
		a.Name = name
		for _, kind in kinds do
			local e = Lib.NewEmitter(kind)
			e.Enabled = false -- burst-only: :Emit(n)
			e.Parent = a
		end
		a.Parent = folder
		return a
	end
	rig("MuzzleFlash", { "Flash", "Spark", "Ring", "Shock" })
	rig("ImpactBurst", { "Spark", "Ground", "Crack", "Flash" })
	-- BoltTrail: two attachments + Trail; BoltCore: two attachments + Beam (+2 afterimage ghosts).
	local bolt = Instance.new("Folder")
	bolt.Name = "BoltTrail"
	for _, n in { "A0", "A1", "C0", "C1", "G0", "G1", "H0", "H1" } do
		local a = Instance.new("Attachment")
		a.Name = n
		a.Parent = bolt
	end
	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.MinLength = 0.05
	trail.Transparency = seq(0, 1)
	trail.Enabled = false
	trail.Parent = bolt
	local sparkle = Lib.NewEmitter("Spark")
	sparkle.Name = "TrailSparkle"
	sparkle.Enabled = false
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.Lifetime = NumberRange.new(0.25, 0.4)
	sparkle.Parent = bolt
	for _, n in { "Core", "Ghost1", "Ghost2" } do
		local beam = Instance.new("Beam")
		beam.Name = n
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Segments = 1
		beam.Enabled = false
		beam.Parent = bolt
	end
	bolt.Parent = folder
	local puff = Instance.new("BillboardGui")
	puff.Name = "SleepPuff"
	puff.Size = UDim2.fromScale(1.6, 1.6)
	puff.AlwaysOnTop = false
	puff.LightInfluence = 0
	puff.MaxDistance = 120
	puff.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Z"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "Z"
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = puff
	puff.Parent = folder
	return folder
end

local function host(): Instance
	return Workspace.Terrain -- world-space Attachments
end

local function initPool()
	if pool then
		return pool
	end
	local folder = templates()
	pool = {
		muzzle = {},
		impact = {},
		bolt = {},
		puff = {},
		next = { muzzle = 1, impact = 1, bolt = 1, puff = 1 },
	}
	for i = 1, Config.PoolSize do
		local m = folder.MuzzleFlash:Clone()
		m.Name = "PTF_Muzzle" .. i
		m.Parent = host()
		table.insert(pool.muzzle, m)
		local h = folder.ImpactBurst:Clone()
		h.Name = "PTF_Impact" .. i
		h.Parent = host()
		table.insert(pool.impact, h)
		local b = {}
		for _, child in folder.BoltTrail:GetChildren() do
			local c = child:Clone()
			c.Name = "PTF_Bolt" .. i .. "_" .. child.Name
			c.Parent = host()
			b[child.Name] = c
		end
		b.Trail.Attachment0, b.Trail.Attachment1 = b.A0, b.A1
		b.TrailSparkle.Parent = b.A0
		b.Core.Attachment0, b.Core.Attachment1 = b.C0, b.C1
		b.Ghost1.Attachment0, b.Ghost1.Attachment1 = b.G0, b.G1
		b.Ghost2.Attachment0, b.Ghost2.Attachment1 = b.H0, b.H1
		b.freeAt = 0
		table.insert(pool.bolt, b)
		for _ = 1, 3 do
			local anchor = Instance.new("Attachment")
			anchor.Name = "PTF_PuffAnchor"
			anchor.Parent = host()
			local gui = folder.SleepPuff:Clone()
			gui.Adornee = anchor
			gui.Parent = anchor
			table.insert(pool.puff, { anchor = anchor, gui = gui, label = gui.Z })
		end
	end
	created = 0
	for _, list in { pool.muzzle, pool.impact } do
		created += #list
	end
	return pool
end

local function take(kind: string): any
	local p = initPool()
	local list = p[kind]
	local i = p.next[kind]
	p.next[kind] = i % #list + 1
	return list[i]
end

local function emit(rig: Instance, name: string, n: number, colour: ColorSequence)
	if n <= 0 then
		return
	end
	local e = rig:FindFirstChild("PTF_" .. name)
	if e and e:IsA("ParticleEmitter") then
		e.Color = colour
		e:Emit(n)
	end
end

function Lib.Muzzle(origin: Vector3, direction: Vector3, weaponId: string?, quality: string)
	local style = Lib.Style(weaponId)
	local c = Lib.Counts(style.tier, quality)
	local rig = take("muzzle")
	rig.WorldCFrame = CFrame.lookAt(origin, origin + direction)
	emit(rig, "Flash", c.flash, style.sequence)
	emit(rig, "Spark", c.muzzle, style.sequence)
	emit(rig, "Ring", c.ring, style.sequence)
	emit(
		rig,
		"Shock",
		c.shock,
		if style.halo then ColorSequence.new(style.halo) else style.sequence
	)
end

function Lib.Impact(
	at: Vector3,
	direction: Vector3,
	weaponId: string?,
	quality: string,
	slept: boolean
)
	local style = Lib.Style(weaponId)
	local c = Lib.Counts(style.tier, quality)
	local rig = take("impact")
	rig.WorldCFrame = CFrame.lookAt(at, at - direction)
	emit(rig, "Flash", c.flash, style.sequence)
	emit(rig, "Spark", c.impact, style.sequence)
	emit(
		rig,
		"Ground",
		c.ground,
		if style.halo then ColorSequence.new(Color3.new(0, 0, 0)) else style.sequence
	)
	emit(rig, "Crack", c.crack, style.sequence)
	if slept and c.puff > 0 then
		for i = 1, c.puff do
			local puff = take("puff")
			puff.anchor.WorldPosition = at + Vector3.new((i - 1) * 0.6, 1.5 + (i - 1) * 0.5, 0)
			puff.gui.StudsOffsetWorldSpace = Vector3.zero
			puff.gui.Size = UDim2.fromScale(1.2 + 0.4 * i, 1.2 + 0.4 * i)
			puff.label.TextTransparency = 0
			puff.label.TextStrokeTransparency = 0
			puff.label.TextStrokeColor3 = style.colour
			puff.gui.Enabled = true
			local info = TweenInfo.new(
				0.9,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out,
				0,
				false,
				(i - 1) * 0.12
			)
			TweenService:Create(puff.gui, info, { StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0) })
				:Play()
			local fade = TweenService:Create(
				puff.label,
				info,
				{ TextTransparency = 1, TextStrokeTransparency = 1 }
			)
			fade.Completed:Once(function()
				puff.gui.Enabled = false
			end)
			fade:Play()
		end
	end
end

export type BoltRig = {
	move: (tail: Vector3, front: Vector3, direction: Vector3) -> (),
	release: () -> (),
}

-- A pooled trail (+ core beam / ghosts by tier) that follows one bolt.
function Lib.Bolt(weaponId: string?, quality: string): BoltRig
	local style = Lib.Style(weaponId)
	local ladder = style.ladder
	local p = initPool()
	-- prefer a rig whose trail has faded
	local now = os.clock()
	local b = take("bolt")
	for _ = 1, #p.bolt do
		if b.freeAt <= now then
			break
		end
		b = take("bolt")
	end
	local width = ladder.trailWidth
	b.Trail.Lifetime = ladder.trailLife
	b.Trail.Color = if ladder.dark
		then ColorSequence.new(Color3.new(0.05, 0.03, 0.08))
		else style.sequence
	b.Trail:Clear()
	b.Trail.Enabled = true
	b.TrailSparkle.Color = style.sequence
	b.TrailSparkle.Rate = if ladder.sparkle and quality ~= "Low" then 30 else 0
	b.TrailSparkle.Enabled = ladder.sparkle == true and quality ~= "Low"
	local core = ladder.core == true
	b.Core.Enabled = core
	b.Core.Color = if style.halo then ColorSequence.new(style.halo) else style.sequence
	b.Core.Width0, b.Core.Width1 = width * 1.6, width * 0.6
	b.Core.Transparency = seq(if ladder.dark then 0.45 else 0.15, 0.6)
	local ghosts = if quality == "Low" then 0 else (ladder.ghosts or 0)
	b.Ghost1.Enabled, b.Ghost2.Enabled = ghosts >= 1, ghosts >= 2
	for _, g in { b.Ghost1, b.Ghost2 } do
		g.Color = style.sequence
		g.Width0, g.Width1 = width, width * 0.4
		g.Transparency = seq(0.55, 0.9)
	end
	local function move(tail: Vector3, front: Vector3, direction: Vector3)
		local side = direction:Cross(Vector3.yAxis)
		side = if side.Magnitude < 1e-3 then Vector3.xAxis else side.Unit
		b.A0.WorldPosition = front + side * (width / 2)
		b.A1.WorldPosition = front - side * (width / 2)
		b.C0.WorldPosition, b.C1.WorldPosition = tail, front
		b.G0.WorldPosition, b.G1.WorldPosition = tail - direction * 1.2, front - direction * 1.2
		b.H0.WorldPosition, b.H1.WorldPosition = tail - direction * 2.4, front - direction * 2.4
	end
	local function release()
		b.Trail.Enabled = false
		b.TrailSparkle.Enabled = false
		b.Core.Enabled, b.Ghost1.Enabled, b.Ghost2.Enabled = false, false, false
		b.freeAt = os.clock() + ladder.trailLife
	end
	return { move = move, release = release }
end

-- Diagnostics: instances the pool owns (fixed after warm-up).
function Lib.PoolStats(): { rigs: number, instances: number }
	if not pool then
		return { rigs = 0, instances = 0 }
	end
	local n = 0
	for _, list in { pool.muzzle, pool.impact } do
		for _, rig in list do
			n += 1 + #rig:GetDescendants()
		end
	end
	for _, b in pool.bolt do
		for key, inst in b do
			if typeof(inst) == "Instance" and key ~= "freeAt" then
				n += 1
			end
		end
	end
	for _, puff in pool.puff do
		n += 1 + #puff.anchor:GetDescendants()
	end
	return { rigs = created, instances = n }
end

return Lib
