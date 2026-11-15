-- Playtest Fixes Part B1 undo, Studio EDIT mode only: restores each slot's LegacySlotCFrame/Length.
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local stall = workspace.MapBlockout.MapArt.Services.Kiosk_WeaponHarpoonStall
local n = 0
for _, slot in stall.CampSlots:GetChildren() do
	local frame = slot:GetAttribute("LegacySlotCFrame")
	if slot:IsA("BasePart") and typeof(frame) == "CFrame" then
		slot.CFrame = frame
		slot:SetAttribute("SlotLength", slot:GetAttribute("LegacySlotLength"))
		for _, key in { "LegacySlotCFrame", "LegacySlotLength", "PlaytestFixesSlot", "PlaytestFixesActive" } do
			slot:SetAttribute(key, nil)
		end
		n += 1
	end
end
return n
