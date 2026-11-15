--!strict
-- Core Loop V2 client FX primitives (Part L3). Pooled, cheap, tier-aware. Every primitive uses the L2
-- fallback until the CL_* texture ids are uploaded into CoreLoopFx.L2_Assets:
--   CL_Ring -> Neon segment ring, CL_StudChunk -> creature stud texture, CL_Star4 -> engine sparkles sprite,
--   CL_Dust -> engine smoke sprite, CL_Crack -> skipped, CL_Zzz -> text "Z", CL_Bolt -> Neon zig-zag.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserSettings = UserSettings
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.UI.Theme)
local Fx = require(Shared.Config.CoreLoopFx)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)

local Kit = {}

local folder: Folder? = nil
local function root(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "CoreLoopFx"
	f.Parent = Workspace
	folder = f
	return f
end
Kit.Root = root

local assets = (Fx :: any).L2_Assets or {}
local function asset(name: string, fallback: string): string
	local id = assets[name]
	return if type(id) == "string" and id ~= "" then id else fallback
end
Kit.Textures = {
	-- Theme.Images.Sparkle is not loadable as a particle/beam texture; use the engine sprite (V4 interim).
	Star4 = asset("CL_Star4", "rbxasset://textures/particles/sparkles_main.dds"),
	Dust = asset("CL_Dust", "rbxasset://textures/particles/smoke_main.dds"),
	Chunk = asset("CL_StudChunk", Theme.StudTexture),
	Confetti = asset("CL_Confetti", Theme.StudTexture),
	Sparkle = asset("CL_BeamSparkle", "rbxasset://textures/particles/sparkles_main.dds"),
}

------------------------------------------------------------------ tier / motion

-- VFX tier: QA override (ReplicatedStorage.CoreLoopFxTier), else the engine quality level.
-- Studio capture mode: screen_capture skips AlwaysOnTop billboards, so QA captures turn it off
-- (ReplicatedStorage.CoreLoopCaptureMode = true, Studio only). Live play always uses AlwaysOnTop.
function Kit.OnTop(): boolean
	return not (
		game:GetService("RunService"):IsStudio()
		and game:GetService("ReplicatedStorage"):GetAttribute("CoreLoopCaptureMode") == true
	)
end

function Kit.Tier(): "High" | "Medium" | "Low"
	local override = ReplicatedStorage:GetAttribute("CoreLoopFxTier")
	if override == "High" or override == "Medium" or override == "Low" then
		return override
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	local value = if ok and type(level) == "number" then level else 0
	if value == 0 or value >= 8 then
		return "High"
	elseif value >= 4 then
		return "Medium"
	end
	return "Low"
end

-- Particle count for a High number with an explicit Low value (Medium = 60%).
function Kit.Count(high: number, low: number): number
	local tier = Kit.Tier()
	return if tier == "High"
		then high
		elseif tier == "Medium" then math.max(low, math.floor(high * 0.6))
		else low
end

function Kit.ReducedMotion(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("ReducedMotion") == true
end

-- Review gate (L6): a group renders its full look only when approved, or inside the review pen.
local penActive = false
function Kit.SetPen(active: boolean)
	penActive = active
end
function Kit.Approved(group: string): boolean
	return penActive or (Fx.Approved :: any)[group] == true
end

------------------------------------------------------------------ anchors

-- An invisible anchored part to hang attachments / emitters / billboards on.
function Kit.Anchor(position: Vector3, lifetime: number?): Part
	local part = Instance.new("Part")
	part.Name = "FxAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = CFrame.new(position)
	part.Parent = root()
	if lifetime then
		Debris:AddItem(part, lifetime)
	end
	return part
end

------------------------------------------------------------------ bursts

export type BurstSpec = {
	texture: string,
	count: number,
	color: Color3,
	speed: NumberRange,
	size: NumberSequence,
	lifetime: NumberRange,
	transparency: NumberSequence?,
	spread: number?, -- degrees
	gravity: number?,
	lightEmission: number?,
	direction: Enum.NormalId?,
	rotSpeed: NumberRange?,
	shape: Enum.ParticleEmitterShape?,
}

function Kit.Burst(position: Vector3, spec: BurstSpec)
	if spec.count <= 0 then
		return
	end
	local anchor = Kit.Anchor(position, 3)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = spec.texture
	emitter.Color = ColorSequence.new(spec.color)
	emitter.Speed = spec.speed
	emitter.Size = spec.size
	emitter.Lifetime = spec.lifetime
	emitter.Transparency = spec.transparency or NumberSequence.new(0, 1)
	emitter.SpreadAngle = Vector2.new(spec.spread or 60, spec.spread or 60)
	emitter.Acceleration = Vector3.new(0, spec.gravity or 0, 0)
	emitter.LightEmission = spec.lightEmission or 1
	emitter.EmissionDirection = spec.direction or Enum.NormalId.Top
	emitter.RotSpeed = spec.rotSpeed or NumberRange.new(-90, 90)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(spec.count)
end

------------------------------------------------------------------ rings (CL_Ring fallback)

-- A flat ring of Neon segments. Returns the model and a setter for radius/transparency.
export type Ring = { Model: Model, Set: (number, number) -> (), Destroy: () -> () }
function Kit.Ring(centre: CFrame, color: Color3, segments: number, thickness: number?): Ring
	local model = Instance.new("Model")
	model.Name = "FxRing"
	local parts = {}
	for i = 1, segments do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.CastShadow = false
		part.Parent = model
		parts[i] = part
	end
	model.Parent = root()
	local t = thickness or 0.35
	local function set(radius: number, transparency: number)
		local chord = 2 * radius * math.sin(math.pi / segments) + 0.05
		for i, part in parts do
			local angle = (i - 0.5) / segments * 2 * math.pi
			part.Size = Vector3.new(math.max(0.05, chord), 0.12, t)
			part.CFrame = centre * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -radius)
			part.Transparency = transparency
		end
	end
	set(1, 0)
	return {
		Model = model,
		Set = set,
		Destroy = function()
			model:Destroy()
		end,
	}
end

-- Ring that grows r0 -> r1 and fades over seconds (flash rings, shockwaves).
function Kit.RingBurst(position: Vector3, color: Color3, r0: number, r1: number, seconds: number)
	local ring = Kit.Ring(
		CFrame.new(position + Vector3.new(0, 0.15, 0)),
		color,
		if Kit.Tier() == "Low" then 10 else 16
	)
	local started = os.clock()
	task.spawn(function()
		while true do
			local alpha = math.clamp((os.clock() - started) / seconds, 0, 1)
			ring.Set(r0 + (r1 - r0) * alpha, alpha)
			if alpha >= 1 then
				break
			end
			task.wait()
		end
		ring.Destroy()
	end)
end

------------------------------------------------------------------ light flash

function Kit.Light(
	position: Vector3,
	color: Color3,
	brightness: number,
	range: number,
	seconds: number
)
	if Kit.Tier() == "Low" then
		return
	end
	local anchor = Kit.Anchor(position, seconds + 0.2)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(seconds), { Brightness = 0 }):Play()
end

------------------------------------------------------------------ highlight flash

function Kit.Flash(model: Instance, color: Color3, seconds: number, fill: number?)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = fill or 0.3
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = root()
	Debris:AddItem(highlight, seconds)
end

------------------------------------------------------------------ world shout (L4.7) / bubbles

-- Billboard text that rises ~3 studs and fades over seconds. Title style (gradient) when shout=true.
function Kit.Shout(
	adornee: Instance,
	text: string,
	color: Color3?,
	seconds: number?,
	px: number?,
	gradient: boolean?
)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FxShout"
	billboard.Size = UDim2.fromOffset(Theme.px(260), Theme.px(px or 28) * 1.6)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = Kit.OnTop()
	billboard.MaxDistance = 150
	billboard.LightInfluence = 0
	billboard.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.FontFace = Theme.Font.Display
	label.TextScaled = true
	label.TextColor3 = color or Theme.Color.Text
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Ink
	stroke.Thickness = Theme.px(if gradient then 5 else 3)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	if gradient then
		label.TextColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Theme.Color.Burst, Theme.Color.BurstLo)
		g.Parent = label
	end
	label.Parent = billboard
	billboard.Parent = root()
	local duration = seconds or 1.2
	TweenService
		:Create(
			billboard,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				StudsOffsetWorldSpace = Vector3.new(0, 9, 0),
			}
		)
		:Play()
	TweenService:Create(
		label,
		TweenInfo.new(
			duration * 0.4,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In,
			0,
			false,
			duration * 0.6
		),
		{
			TextTransparency = 1,
		}
	):Play()
	TweenService:Create(
		stroke,
		TweenInfo.new(
			duration * 0.4,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In,
			0,
			false,
			duration * 0.6
		),
		{
			Transparency = 1,
		}
	):Play()
	Debris:AddItem(billboard, duration + 0.1)
	return billboard
end

-- A coloured speech bubble ("!", "?", "NYAH!") with ink outline, popping 0 -> 1.3 -> 1.
function Kit.Bubble(
	adornee: Instance,
	text: string,
	fill: Color3,
	seconds: number,
	textColor: Color3?
)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FxBubble"
	-- Width follows the text (board 6: "!" is a round bubble, "NYAH!" / "NOT YOURS YET" are pills).
	local chars = utf8.len(text) or #text
	billboard.Size =
		UDim2.fromOffset(Theme.px(if chars > 2 then chars * 11 + 24 else 40), Theme.px(46))
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	billboard.AlwaysOnTop = Kit.OnTop()
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	billboard.Adornee = adornee
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = fill
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Ink
	stroke.Thickness = Theme.px(3)
	stroke.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.FontFace = Theme.Font.Display
	label.TextScaled = true
	label.TextColor3 = textColor or Theme.Color.Text
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Theme.Color.Ink
	textStroke.Thickness = Theme.px(3)
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = label
	label.Parent = frame
	frame.Parent = billboard
	billboard.Parent = root()
	TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = 1.3 }):Play()
	task.delay(0.1, function()
		TweenService:Create(scale, TweenInfo.new(0.05), { Scale = 1 }):Play()
	end)
	Debris:AddItem(billboard, seconds)
	return billboard
end

------------------------------------------------------------------ sound (L5 fallbacks)

function Kit.Sound(cue: string, options: { pitch: number?, position: Vector3? }?)
	local cues = (Fx :: any).L5_Cues or {}
	local id = cues[cue] or cue
	if id ~= "" then
		AudioCue.Play(id, options)
	end
end

------------------------------------------------------------------ colours

function Kit.RarityColour(tier: string?): Color3
	return (Theme.Rarity :: any)[tier or "Common"] or Theme.Rarity.Common
end
function Kit.GlowColour(tier: string?): Color3
	return (Theme.CoreLoop.Glow :: any)[tier or "Common"] or Color3.new(1, 1, 1)
end

return Kit
