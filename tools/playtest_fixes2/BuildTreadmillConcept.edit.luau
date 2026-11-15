--!nocheck
-- Playtest Fixes 2, Part G1 (14 Nov 2026): CONCEPT ONLY, for owner approval (CP-B). Builds a runner
-- treadmill beside the cart rollers at the Training stall, in the stall's own art family (wood-plank
-- frame, dark metal, black belt, yellow hazard trim, blue console). Run in Studio EDIT mode. It is
-- parked in ServerStorage._ConceptBooth.LegsTreadmill_Concept after the captures, so the live world
-- is unchanged until the owner approves the look. Non-colliding belt deck (players stand on a thin
-- collidable floor plate), no scripts.
local Workspace = game:GetService("Workspace")

local stall = Workspace.MapBlockout.MapArt.Services:FindFirstChild("Kiosk_TrainingStall")
assert(stall, "Kiosk_TrainingStall missing")
local pivot = stall:GetPivot()
-- beside the roller pit, on the stall's open side (local -X), belt running along local Z like the rollers
local origin = pivot * CFrame.new(-13.2, 0, 1.2)

local C = {
	wood = Color3.fromHex("7a5530"),
	woodDark = Color3.fromHex("3a2416"),
	metal = Color3.fromHex("4a4f56"),
	belt = Color3.fromHex("222222"),
	black = Color3.fromHex("1e1e1e"),
	hazard = Color3.fromHex("ffd21f"),
	blue = Color3.fromHex("3c6fd1"),
	white = Color3.fromHex("f4f4f4"),
}

local model = Instance.new("Model")
model.Name = "LegsTreadmill"
model:SetAttribute("PlaytestFixes2", "LegsTreadmillConcept")

local count = 0
local function part(name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = origin * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = model
	count += 1
	return p
end

local L, W = 9, 4.4 -- belt length (local Z) and deck width (local X)
-- frame + deck
part("Base", Vector3.new(W + 0.8, 0.7, L + 1.2), CFrame.new(0, 0.35, 0), C.wood, Enum.Material.WoodPlanks)
part("SkirtL", Vector3.new(0.3, 0.6, L + 1.2), CFrame.new(-(W / 2 + 0.25), 0.75, 0), C.woodDark)
part("SkirtR", Vector3.new(0.3, 0.6, L + 1.2), CFrame.new(W / 2 + 0.25, 0.75, 0), C.woodDark)
-- the belt: what the player stands on (the only collidable piece; CanQuery for the server poll)
part("Belt", Vector3.new(W - 0.4, 0.25, L), CFrame.new(0, 0.82, 0), C.belt, Enum.Material.Rubber, {
	CanCollide = true,
	CanQuery = true,
})
for i, z in { -L / 2, L / 2 } do
	-- a Cylinder's axis is its X: no rotation, it already spans the deck width
	part("EndRoller" .. i, Vector3.new(W - 0.2, 0.9, 0.9), CFrame.new(0, 0.7, z), C.metal, Enum.Material.Metal, {
		Shape = Enum.PartType.Cylinder,
	})
end
-- belt slats (read as motion; the runtime scrolls a texture, these are the static concept)
for i = 1, 5 do
	part("Slat" .. i, Vector3.new(W - 0.5, 0.06, 0.18), CFrame.new(0, 0.97, -L / 2 + i * L / 6), C.black)
end
-- hazard trim along both edges
for i = 1, 4 do
	local z = -L / 2 + (i - 0.5) * L / 4
	part("HazardL" .. i, Vector3.new(0.35, 0.08, L / 8), CFrame.new(-(W / 2 + 0.05), 1.0, z), C.hazard)
	part("HazardR" .. i, Vector3.new(0.35, 0.08, L / 8), CFrame.new(W / 2 + 0.05, 1.0, z), C.hazard)
end
-- side rails and the front handlebar (front = local -Z, the end facing the stall's front)
for _, x in { -(W / 2 + 0.25), W / 2 + 0.25 } do
	part("Post", Vector3.new(0.35, 3.4, 0.35), CFrame.new(x, 2.4, -L / 2 + 0.4), C.metal, Enum.Material.Metal)
	part("SideRail", Vector3.new(0.25, 0.25, 3.4), CFrame.new(x, 3.9, -L / 2 + 2.1), C.metal, Enum.Material.Metal)
end
part("HandleBar", Vector3.new(W + 0.85, 0.3, 0.3), CFrame.new(0, 4.1, -L / 2 + 0.4), C.black, Enum.Material.Metal)
-- console: blue face, "LEGS" sign and a small speed dial (matches the stall's gauge)
local console = part("Console", Vector3.new(2.6, 1.5, 0.45), CFrame.new(0, 4.6, -L / 2 + 0.25) * CFrame.Angles(math.rad(-20), 0, 0), C.blue)
local dial = part("Dial", Vector3.new(0.1, 0.75, 0.75), CFrame.new(-0.85, 4.62, -L / 2 + 0.02) * CFrame.Angles(math.rad(-20), math.rad(90), 0), C.white, nil, {
	Shape = Enum.PartType.Cylinder,
})
part("DialNeedle", Vector3.new(0.06, 0.4, 0.06), CFrame.new(-0.85, 4.75, -L / 2 - 0.02) * CFrame.Angles(math.rad(-20), 0, math.rad(-35)), Color3.fromHex("e3173e"))
local gui = Instance.new("SurfaceGui")
gui.Face = Enum.NormalId.Front
gui.CanvasSize = Vector2.new(260, 150)
gui.LightInfluence = 0
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Size = UDim2.fromScale(0.56, 1)
label.Position = UDim2.fromScale(0.04, 0)
label.Text = "LEGS"
label.TextScaled = true
label.Font = Enum.Font.FredokaOne
label.TextColor3 = C.hazard
local stroke = Instance.new("UIStroke")
stroke.Thickness = 4
stroke.Color = C.black
stroke.Parent = label
label.Parent = gui
gui.Parent = console
-- sign board on a post at the back, like the stall's own sign
part("SignPost", Vector3.new(0.35, 5.4, 0.35), CFrame.new(-(W / 2 + 0.25), 2.7, L / 2 + 0.2), C.woodDark, Enum.Material.WoodPlanks)
local board = part("SignBoard", Vector3.new(3.6, 1.6, 0.25), CFrame.new(-(W / 2 + 0.25) + 1.4, 5.2, L / 2 + 0.2), C.wood, Enum.Material.WoodPlanks)
local sgui = gui:Clone()
sgui.Face = Enum.NormalId.Front -- faces the customers (local -Z)
local sl = sgui:FindFirstChildOfClass("TextLabel")
sl.Size = UDim2.fromScale(0.92, 1)
sl.Text = "RUN!"
sgui.Parent = board
local _ = dial

model.PrimaryPart = model:FindFirstChild("Base")
model.Parent = stall.Parent
return string.format("built %d parts at %s", count, tostring(model:GetPivot().Position))
