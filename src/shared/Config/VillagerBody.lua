--!strict
-- The one villager body (rig + animation brief v5, C.1). Every villager uses these joints
-- and proportions; a skin (Config/VillagerSkins) only adds boxes on top.
-- Kit space: studs, y up, ground at y = 0, the villager faces -Z, left is -X.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local K = require(ReplicatedStorage.Shared.Utility.VillagerKitBuilder)

export type Bone = { name: string, parent: string, at: { number } }

local VillagerBody = {
	Version = 1,
	Height = 5.05, -- top of the head; headwear comes from the skin
	-- Motor6D chain, parent before child. `at` is the joint position in the bind pose.
	Bones = table.freeze({
		{ name = "Hips", parent = "Root", at = { 0, 1.75, 0 } },
		{ name = "Torso", parent = "Hips", at = { 0, 2.0, 0 } },
		{ name = "Neck", parent = "Torso", at = { 0, 3.5, 0 } },
		{ name = "Head", parent = "Neck", at = { 0, 3.65, 0 } },
		{ name = "UpperArmL", parent = "Torso", at = { -1.3, 3.3, 0 } },
		{ name = "HandL", parent = "UpperArmL", at = { -1.3, 2.25, 0 } },
		{ name = "UpperArmR", parent = "Torso", at = { 1.3, 3.3, 0 } },
		{ name = "HandR", parent = "UpperArmR", at = { 1.3, 2.25, 0 } },
		{ name = "LegL", parent = "Hips", at = { -0.5, 1.5, 0 } },
		{ name = "FootL", parent = "LegL", at = { -0.5, 0.4, 0 } },
		{ name = "LegR", parent = "Hips", at = { 0.5, 1.5, 0 } },
		{ name = "FootR", parent = "LegR", at = { 0.5, 0.4, 0 } },
		-- Attachment bones: empty unless a skin puts boxes on them.
		{ name = "Hat", parent = "Head", at = { 0, 5.05, 0 } },
		{ name = "Prop", parent = "HandR", at = { 1.3, 1.9, 0 } },
		{ name = "PropL", parent = "HandL", at = { -1.3, 1.9, 0 } },
		{ name = "Back", parent = "Torso", at = { 0, 2.9, 0.6 } },
		{ name = "Tail", parent = "Hips", at = { 0, 1.7, 0.55 } },
	}),
}

local function B(bone: string, slot: string, x0, y0, z0, x1, y1, z1, role: string): any
	local item: any = K.Box(slot, x0, y0, z0, x1, y1, z1, role, { relief = true })
	item.bone = bone
	return item
end

-- Plain, neutral body: chunky toy person, short sturdy legs, oversized hands and feet.
VillagerBody.Boxes = table.freeze({
	B("Hips", "BodyHips", -0.95, 1.5, -0.55, 0.95, 2.0, 0.55, "bottom"),
	B("Torso", "BodyTorso", -1.05, 2.0, -0.6, 1.05, 3.5, 0.6, "top"),
	B("Neck", "BodyNeck", -0.3, 3.5, -0.3, 0.3, 3.65, 0.3, "skin"),
	B("Head", "BodyHead", -1.05, 3.65, -0.9, 1.05, 5.05, 0.9, "skin"),
	B("UpperArmL", "BodyArm_L", -1.55, 2.25, -0.3, -1.05, 3.45, 0.3, "top"),
	B("HandL", "BodyHand_L", -1.65, 1.55, -0.35, -0.95, 2.25, 0.35, "skin"),
	B("UpperArmR", "BodyArm_R", 1.05, 2.25, -0.3, 1.55, 3.45, 0.3, "top"),
	B("HandR", "BodyHand_R", 0.95, 1.55, -0.35, 1.65, 2.25, 0.35, "skin"),
	B("LegL", "BodyLeg_L", -0.8, 0.4, -0.3, -0.2, 1.5, 0.3, "bottom"),
	B("FootL", "BodyFoot_L", -0.9, 0, -0.85, -0.1, 0.4, 0.35, "shoe"),
	B("LegR", "BodyLeg_R", 0.2, 0.4, -0.3, 0.8, 1.5, 0.3, "bottom"),
	B("FootR", "BodyFoot_R", 0.1, 0, -0.85, 0.9, 0.4, 0.35, "shoe"),
})

VillagerBody.MaxSkinBoxes = 80

return table.freeze(VillagerBody)
