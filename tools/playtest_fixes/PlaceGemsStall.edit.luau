-- Playtest Fixes F4, Studio EDIT mode only. Places the approved Gems stall concept on the camp main street
-- (Config.PlaytestFixes.GemsStall.Placement), following Camp_Stalls_Weapons_Layout Part B steps 1-5:
--   1 pivot      stall root on the camp floor (y 0.05), customer front = pivot LookVector
--   2 parts      anchored; decoration (< 1 stud) CanQuery/CastShadow off; collidable counter and legs kept
--   3 text       GEMS SurfaceGui keeps LightInfluence 0, PixelsPerStud as authored, nothing in front
--   4 attributes CampCategory "Gems", CampReworkStall "Gems", concept marker removed
--   5 parent     MapBlockout.MapArt.Services (the place owns MapBlockout; it is not Rojo-mapped)
-- The stall is hidden at runtime while PlaytestFixesV1 / GemsStall is off (Systems/PlaytestCampStalls).
-- Rerunnable: replaces a previous placement. Undo: delete MapArt.Services.Kiosk_GemsStall.
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local probe = RS.Shared.Config.PlaytestFixes:Clone()
probe.Parent = SS
local Config = require(probe).GemsStall
probe:Destroy()
local concept = SS._ConceptBooth.Stalls:FindFirstChild("Kiosk_GemsStall")
assert(concept, "Gems stall concept missing")
local services = workspace.MapBlockout.MapArt.Services
local old = services:FindFirstChild(Config.ModelName)
if old then
	old:Destroy()
end
local stall = concept:Clone()
stall.Name = Config.ModelName
stall:SetAttribute("PlaytestFixesConcept", nil)
stall:SetAttribute("PlaytestFixesPlaced", true)
local p = Config.Placement
stall:PivotTo(CFrame.new(p.x, 0.05, p.z) * CFrame.Angles(0, math.rad(p.yawDegrees), 0))
local parts, decor = 0, 0
for _, d in stall:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
		d.Anchored = true
		if math.max(d.Size.X, d.Size.Y, d.Size.Z) < 1 then
			d.CanQuery, d.CastShadow = false, false
			decor += 1
		end
	elseif d:IsA("SurfaceGui") then
		d.LightInfluence = 0
	end
end
stall.Parent = services
return string.format("placed %s at %s yaw %d: parts=%d decoration=%d", stall.Name, tostring(stall:GetPivot().Position), p.yawDegrees, parts, decor)
