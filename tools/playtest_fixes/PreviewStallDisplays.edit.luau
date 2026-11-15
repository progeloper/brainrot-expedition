-- Playtest Fixes Part B capture aid, Studio EDIT mode only. CampStallController only runs on a Play
-- client, so this places WeaponDisplays clones on the Weapons stall slots with the SAME pose maths
-- (Shared.Utility.StallDisplayPose) into Workspace._PlaytestPreview. Set CLEAR = true to remove it.
-- Never save the place with the preview folder in it.
local CLEAR = false
local PICKS = {
	RackSlot_1 = "WPN_B08", RackSlot_2 = "WPN_G08", RackSlot_3 = "WPN_C08", -- right board: tier 8
	RackSlot_4 = "WPN_C02", RackSlot_5 = "WPN_G02", RackSlot_6 = "HRP_001", -- left board: tiers 1-2
	WallSlot_1 = "WPN_SP_PRISMREPEATER", WallSlot_2 = "WPN_SP_RIFTBLASTER", WallSlot_3 = "WPN_SP_CRYSTALLANCE",
	MedalSlot_1 = "WPN_SP_COLLECTORSBOW", MedalSlot_2 = "WPN_SP_GETAWAY", MedalSlot_3 = "WPN_SP_SECRETHUNTER",
}
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local RS = game:GetService("ReplicatedStorage")
local Pose = require(RS.Shared.Utility.StallDisplayPose)
local Config = require(RS.Shared.Config.PlaytestFixes).StallPoses
local old = workspace:FindFirstChild("_PlaytestPreview")
if old then
	old:Destroy()
end
if CLEAR then
	return "cleared"
end
local folder = Instance.new("Folder")
folder.Name = "_PlaytestPreview"
folder.Archivable = false
local stall = workspace.MapBlockout.MapArt.Services.Kiosk_WeaponHarpoonStall
local out = {}
for slotName, id in PICKS do
	local slot = stall.CampSlots:FindFirstChild(slotName)
	local source = RS.CodeAssets.WeaponDisplays:FindFirstChild(id)
	if slot and source then
		local model = source:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
			elseif d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		local group = tostring(slot:GetAttribute("CampSlot"))
		local _, size = model:GetBoundingBox()
		local family = Pose.Family(id, model:GetAttribute("Family"))
		local axes = Pose.Axes(size, family, id)
		local along = (size :: any)[axes.along]
		local rail = tonumber(slot:GetAttribute("SlotLength")) or 3
		local fit = if group == "Medal" then { scale = rail / along, multiplier = 1.5 * rail / along, fits = true } else Pose.Scale(along, rail)
		model:ScaleTo(model:GetScale() * fit.scale)
		local boxCF, scaled = model:GetBoundingBox()
		local rel = model:GetPivot():ToObjectSpace(boxCF)
		model:PivotTo(slot.CFrame * Pose.BoxInSlot(scaled, axes, (Config.BoardClearance :: any)[group] or 0) * rel:Inverse())
		model.Name = "Preview_" .. slotName .. "_" .. id
		model.Parent = folder
		table.insert(out, string.format("%s %s fam=%s along=%s face=%s x%.2f fits=%s len=%.2f rail=%.2f", slotName, id, family, axes.along, axes.face, fit.multiplier, tostring(fit.fits), along * fit.scale, rail))
	end
end
folder.Parent = workspace
table.sort(out)
return table.concat(out, "\n")
