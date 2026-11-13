--!strict
-- Granchio Megafono (VIL_BEACH_GRANCHIO) on the one villager body.
-- Beach set: southern Italian fisherman's work dress (crab),
-- docs/villagers/Beach_outfit_reference.md.
-- Identity hooks kept: red crab shell, white face with big lime eyes, two eye stalks with a
-- small knitted fisherman's cap between them (the cap band is the Beach glow line), one big
-- claw, peach belly panel, white work vest, blue waist sash, canvas shorts, dark boots, a
-- stub crab leg on each hip, and the megaphone with its glowing rim.
-- The body's own torso (palette role "top", LinenWhite) is the vest and its hips (role
-- "bottom", CanvasTan) are the shorts; shell boxes cover the rest of the bare body. The
-- megaphone stands upright in the right claw: Shout turns the hand so that "up out of the
-- fist" points forward and upward, which aims the megaphone the way he is shouting.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Beach_GranchioMegafono",
	villagerId = "VIL_BEACH_GRANCHIO",
	name = "Granchio Megafono",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "crab shell", "eye stalks", "big claw", "knit cap", "megaphone" }),
	activities = table.freeze({ "Lookout" }),
	boxes = table.freeze(S.Join(S.Eyes(4.42, -0.9, 0.52, 0.86, 0.9, "Lime"), {
		-- face: the head's front stays white
		B(
			"Head",
			"face",
			"Mouth",
			-0.4,
			3.76,
			-0.94,
			0.4,
			3.92,
			-0.9,
			"Protected",
			{ color = "#3A0F12" }
		),
		B(
			"Head",
			"face",
			"Tongue",
			-0.2,
			3.76,
			-0.95,
			0.2,
			3.83,
			-0.94,
			"Protected",
			{ color = "#FF6F7D" }
		),
		-- shell round the face: brow, sides, back and crown
		B(
			"Head",
			"headwear",
			"ShellBrow",
			-1.08,
			4.9,
			-0.97,
			1.08,
			5.05,
			-0.9,
			"cloth",
			{ relief = true }
		),
		B(
			"Head",
			"headwear",
			"ShellSide_L",
			-1.12,
			3.65,
			-0.72,
			-1.05,
			5.05,
			0.95,
			"cloth",
			{ relief = true }
		),
		B(
			"Head",
			"headwear",
			"ShellSide_R",
			1.05,
			3.65,
			-0.72,
			1.12,
			5.05,
			0.95,
			"cloth",
			{ relief = true }
		),
		B(
			"Head",
			"headwear",
			"ShellBack",
			-1.12,
			3.65,
			0.9,
			1.12,
			5.05,
			1.0,
			"cloth",
			{ relief = true }
		),
		B("Head", "headwear", "ShellCrown", -1.1, 5.0, -0.95, 1.1, 5.05, 0.98, "cloth"),
		-- eye stalks stay on the head, either side of the cap
		B("Head", "headwear", "Stalk_L", -0.74, 5.0, -0.25, -0.52, 5.5, -0.03, "skin2"),
		B("Head", "headwear", "Stalk_R", 0.52, 5.0, -0.25, 0.74, 5.5, -0.03, "skin2"),
		B("Head", "headwear", "StalkBall_L", -0.9, 5.5, -0.4, -0.36, 6.0, 0.12, "skin"),
		B("Head", "headwear", "StalkBall_R", 0.36, 5.5, -0.4, 0.9, 6.0, 0.12, "skin"),
		-- headwear: small knitted cap between the stalks. Everything on the Hat bone sits at
		-- or above the head top (y 5.05).
		B(
			"Hat",
			"headwear",
			"KnitCap",
			-0.45,
			5.05,
			-0.4,
			0.45,
			5.35,
			0.4,
			"hat",
			{ relief = true }
		),
		B("Hat", "headwear", "KnitCapTop", -0.3, 5.35, -0.28, 0.3, 5.55, 0.28, "hat"),
		B("Hat", "headwear", "KnitCapBand", -0.47, 5.05, -0.42, 0.47, 5.13, 0.42, "glow"),
		-- body: shell over the neck and upper chest, peach belly panel with its dark band
		B("Neck", "top", "NeckShell", -0.34, 3.48, -0.34, 0.34, 3.67, 0.34, "cloth"),
		B(
			"Torso",
			"top",
			"ChestShell",
			-1.09,
			3.05,
			-0.64,
			1.09,
			3.52,
			0.64,
			"cloth",
			{ relief = true }
		),
		B(
			"Torso",
			"top",
			"Belly",
			-0.72,
			2.3,
			-0.67,
			0.72,
			2.92,
			-0.6,
			"cloth3",
			{ relief = true }
		),
		B("Torso", "top", "BellyBand", -0.72, 2.92, -0.69, 0.72, 3.05, -0.6, "trim"),
		-- arms: shell over both arms, the big claw on the left hand, a small one on the right
		B(
			"UpperArmL",
			"top",
			"ArmShell_L",
			-1.6,
			2.22,
			-0.35,
			-1.02,
			3.5,
			0.35,
			"cloth2",
			{ relief = true }
		),
		B(
			"UpperArmR",
			"top",
			"ArmShell_R",
			1.02,
			2.22,
			-0.35,
			1.6,
			3.5,
			0.35,
			"cloth2",
			{ relief = true }
		),
		B(
			"HandL",
			"top",
			"Claw_L",
			-1.95,
			1.35,
			-0.6,
			-0.9,
			2.3,
			0.45,
			"cloth2",
			{ relief = true }
		),
		B("HandL", "top", "ClawPincer_L", -1.95, 1.0, -0.6, -1.5, 1.35, 0.1, "cloth2"),
		B("HandR", "top", "Claw_R", 0.9, 1.5, -0.4, 1.7, 2.28, 0.45, "trim"),
		-- bottom: shell on the lower legs below the shorts, and a stub crab leg behind each hip
		B("LegL", "bottom", "LegShell_L", -0.82, 0.55, -0.32, -0.18, 1.1, 0.32, "cloth2"),
		B("LegR", "bottom", "LegShell_R", 0.18, 0.55, -0.32, 0.82, 1.1, 0.32, "cloth2"),
		B("Hips", "bottom", "SideLeg_L", -1.2, 1.2, 0.5, -0.75, 1.85, 0.85, "shoe"),
		B("Hips", "bottom", "SideLeg_R", 0.75, 1.2, 0.5, 1.2, 1.85, 0.85, "shoe"),
		-- footwear: boot tops above the body's dark feet
		B("LegL", "footwear", "BootTop_L", -0.88, 0.4, -0.5, -0.12, 0.55, 0.37, "shoe"),
		B("LegR", "footwear", "BootTop_R", 0.12, 0.4, -0.5, 0.88, 0.55, 0.37, "shoe"),
		-- accessory: blue waist sash with a tail
		B(
			"Torso",
			"accessory",
			"WaistSash",
			-1.12,
			2.0,
			-0.67,
			1.12,
			2.3,
			0.67,
			"acc",
			{ relief = true }
		),
		B("Hips", "accessory", "WaistSashTail", 0.6, 1.4, -0.7, 0.85, 2.0, -0.63, "acc"),
		-- props: the megaphone, held upright in front of the right claw with its mouth up
		B("Prop", "props", "MegaphoneGrip", 1.35, 1.72, -0.62, 1.55, 1.9, -0.4, "trim"),
		B("Prop", "props", "MegaphoneHandle", 1.35, 1.6, -0.82, 1.55, 1.9, -0.62, "trim"),
		B(
			"Prop",
			"props",
			"Megaphone",
			1.25,
			1.9,
			-0.97,
			1.65,
			2.6,
			-0.47,
			"prop",
			{ relief = true }
		),
		B("Prop", "props", "MegaphoneBell", 1.15, 2.6, -1.07, 1.75, 2.9, -0.37, "prop2"),
		B("Prop", "props", "MegaphoneRim", 1.13, 2.9, -1.09, 1.77, 2.95, -0.35, "glow"),
	})),
})
