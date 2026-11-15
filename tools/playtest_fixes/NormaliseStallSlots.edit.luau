-- Playtest Fixes Part B1, Studio EDIT mode only. Rewrites the Weapons stall's RackSlot_/WallSlot_ frames
-- (position kept): Look along the rail to the customer's left, Up = rack up (wall slots share one 12 deg
-- lean back), customer at -Right. SlotLength becomes the usable rail length. The former frame and length
-- stay in LegacySlotCFrame / LegacySlotLength, which the flag-off display path still reads.
-- Medal slots are already consistent and are left alone.
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local RS = game:GetService("ReplicatedStorage")
local Pose = require(RS.Shared.Utility.StallDisplayPose)
local Config = require(RS.Shared.Config.PlaytestFixes).StallPoses
local stall = workspace.MapBlockout.MapArt.Services.Kiosk_WeaponHarpoonStall
local customer = stall:GetPivot().LookVector
local report = {}
for _, slot in stall.CampSlots:GetChildren() do
	local group = slot:GetAttribute("CampSlot")
	if slot:IsA("BasePart") and (group == "Rack" or group == "Wall") then
		if slot:GetAttribute("LegacySlotCFrame") == nil then
			slot:SetAttribute("LegacySlotCFrame", slot.CFrame)
			slot:SetAttribute("LegacySlotLength", slot:GetAttribute("SlotLength"))
		end
		local lean = if group == "Wall" then Config.WallLeanDegrees else 0
		-- Two per board (owner 13 Nov): active rack slots move to their row height; x/z kept.
		local row = (Config.RackRows :: any)[slot.Name]
		local legacy = slot:GetAttribute("LegacySlotCFrame") :: CFrame
		local position = if row then Vector3.new(legacy.X, stall:GetPivot().Y + row, legacy.Z) else legacy.Position
		-- Two on the wall (owner 13 Nov): split the pegboard; height and depth kept.
		local along = (Config.WallSlots :: any)[slot.Name]
		if along then
			local left = Vector3.new(customer.X, 0, customer.Z).Unit:Cross(Vector3.yAxis)
			local centre = stall:GetPivot().Position + left * along
			position = Vector3.new(
				if math.abs(left.X) > 0.5 then centre.X else legacy.X,
				legacy.Y,
				if math.abs(left.Z) > 0.5 then centre.Z else legacy.Z
			)
		end
		row = row or along
		slot.CFrame = Pose.SlotFrame(position, customer, lean)
		slot:SetAttribute("SlotLength", (Config.RailLength :: any)[group])
		slot:SetAttribute("PlaytestFixesSlot", true)
		slot:SetAttribute("PlaytestFixesActive", row ~= nil)
		table.insert(report, string.format("%s lean=%.1f check=%s", slot.Name, Pose.LeanDegrees(slot.CFrame, customer), tostring(Pose.CheckSlot(slot.CFrame, customer, lean) or "ok")))
	end
end
table.sort(report)
return table.concat(report, "\n")
