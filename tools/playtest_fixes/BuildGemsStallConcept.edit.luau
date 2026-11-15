-- Playtest Fixes F1, Studio EDIT mode only. Builds the Gems stall CONCEPT (not placed in camp):
-- ServerStorage._ConceptBooth.Stalls.Kiosk_GemsStall, in the Sell/Training stall family (box counter,
-- plank top, dark X-braced sides, sloping canopy with pointed flags, sign board), cloned from the live
-- Kiosk_SellStall and recoloured: purple #8A3DFF / cyan #2EE9FF canopy, "GEMS" sign, and a pile of
-- jagged gem rocks (V4 boxes and wedges, Neon cores) on the counter. One slow sparkle (Rate <= 4);
-- the cores carry GlowPulseHz for the client scheduler (wired when the stall is placed, CP-D).
-- No NPCs, no prices, no stickers. Rerunnable: replaces the previous concept.
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config.PlaytestFixes).GemsStall
local PURPLE, CYAN = Color3.fromHex(Config.Purple), Color3.fromHex(Config.Cyan)

local source = workspace.MapBlockout.MapArt.Services:FindFirstChild("Kiosk_SellStall")
assert(source, "Kiosk_SellStall missing")
local stalls = SS._ConceptBooth.Stalls
local old = stalls:FindFirstChild("Kiosk_GemsStall")
if old then
	old:Destroy()
end
local stall = source:Clone()
stall.Name = "Kiosk_GemsStall"
stall:SetAttribute("CampCategory", "Gems")
stall:SetAttribute("CampObjectText", Config.PromptObjectText)
stall:SetAttribute("CampReworkStall", "Gems")
stall:SetAttribute("PlaytestFixesConcept", true)
-- Next free concept slot in the booth row.
stall:PivotTo(CFrame.new(2160, 605.5, 304))
local pivot = stall:GetPivot()

local canopyIndex = 0
local byX = {}
for _, d in stall:GetDescendants() do
	if d:IsA("BasePart") and (d.Name == "Canopy" or d.Name == "FlagTop" or d.Name == "FlagTip") then
		local x = math.floor(pivot:PointToObjectSpace(d.Position).X / 2.73 + 0.5)
		byX[d] = x
	end
end
for part, x in byX do
	part.Color = if x % 2 == 0 then PURPLE else CYAN
	canopyIndex += 1
end
for _, d in stall:GetDescendants() do
	if d:IsA("TextLabel") and d.Text == "SELL" then
		d.Text = "GEMS"
	elseif d:IsA("BasePart") and (d.Name == "Counter") then
		d.Color = Color3.fromHex("#5B2A9E")
	elseif d:IsA("BasePart") and d.Name == "CounterTrim" then
		d.Color = CYAN
	elseif d:IsA("BasePart") and d.Name == "CoinBurst" then
		d.Name = "GemBurst"
	end
end

-- Gem pile: six faceted rocks in the HUD gem's jagged-rock shape. Each = tilted shell + a two-wedge
-- jagged ridge + a chipped side wedge + a slim Neon sliver in the same hue (no white). The customer
-- front of this family is the pivot's LookVector (local -Z: flags and sign text face that way).
local top = stall:FindFirstChild("CounterTop") :: BasePart
local topY = pivot:PointToObjectSpace(top.Position).Y + top.Size.Y / 2
local pile = Instance.new("Model")
pile.Name = "GemPile"
local ROCKS = { -- z < counter centre (0.72) = the customer half; the customer front is local -Z
	{ -2.7, 0.24, 1.5, 25, PURPLE },
	{ -1.0, 0.84, 1.9, -20, CYAN },
	{ 0.9, 0.44, 2.1, 40, PURPLE },
	{ 2.7, 0.74, 1.6, -35, CYAN },
	{ -0.1, -0.46, 1.4, 70, CYAN },
	{ 1.8, -0.56, 1.3, 15, PURPLE },
}
local function part(class: string, name: string, size: Vector3, cf: CFrame, colour: Color3, neon: boolean)
	local p = Instance.new(class) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
	p.CastShadow = math.max(size.X, size.Y, size.Z) >= 1
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = pile
	return p
end
for i, r in ROCKS do
	local x, z, s, yaw, colour = r[1], r[2], r[3], r[4], r[5]
	local dark = colour:Lerp(Color3.new(0, 0, 0), 0.35)
	local light = colour:Lerp(Color3.new(1, 1, 1), 0.25)
	local tilt = if i % 2 == 0 then 10 else -12
	local base = pivot * CFrame.new(x, topY + s * 0.3, z) * CFrame.Angles(0, math.rad(yaw), math.rad(tilt))
	part("Part", "GemShell", Vector3.new(s, s * 0.6, s * 0.85), base, dark, false)
	part("WedgePart", "GemRidge", Vector3.new(s * 0.95, s * 0.55, s * 0.42), base * CFrame.new(0, s * 0.57, s * 0.21), colour, false)
	part("WedgePart", "GemRidge", Vector3.new(s * 0.95, s * 0.45, s * 0.42), base * CFrame.new(0, s * 0.52, -s * 0.21) * CFrame.Angles(0, math.rad(180), 0), light, false)
	part("WedgePart", "GemChip", Vector3.new(s * 0.3, s * 0.4, s * 0.5), base * CFrame.new(s * 0.55, s * 0.05, 0) * CFrame.Angles(0, 0, math.rad(-90)), colour, false)
	local core = part("Part", "GemCore", Vector3.new(s * 0.14, s * 0.62, s * 0.14), base * CFrame.new(-s * 0.15, s * 0.55, -s * 0.05) * CFrame.Angles(0, 0, math.rad(15)), colour:Lerp(Color3.new(1, 1, 1), 0.15), true)
	core:SetAttribute("GlowPulseHz", Config.GlowPulseHz)
end
pile.Parent = stall
local sparkle = Instance.new("ParticleEmitter")
sparkle.Name = "GemSparkle"
sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
sparkle.Rate = Config.SparkleRate
sparkle.Lifetime = NumberRange.new(0.8, 1.2)
sparkle.Speed = NumberRange.new(0.5, 1)
sparkle.SpreadAngle = Vector2.new(60, 60)
sparkle.Size = NumberSequence.new(0.35, 0)
sparkle.Color = ColorSequence.new(PURPLE, CYAN)
sparkle.LightEmission = 1
sparkle.LightInfluence = 0
local holder = Instance.new("Attachment")
holder.Name = "GemSparkleHolder"
holder.WorldPosition = (pivot * CFrame.new(0, topY + 2.4, 0.2)).Position
holder.Parent = (stall:FindFirstChild("GemBurst") or top) :: Instance
holder.WorldPosition = (pivot * CFrame.new(0, topY + 2.4, 0.2)).Position
sparkle.Parent = holder
stall.Parent = stalls
local parts, emitters = 0, 0
for _, d in stall:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	elseif d:IsA("ParticleEmitter") then
		emitters += 1
	end
end
return string.format("Kiosk_GemsStall concept: parts=%d emitters=%d canopy=%d pivot=%s", parts, emitters, canopyIndex, tostring(stall:GetPivot().Position))
