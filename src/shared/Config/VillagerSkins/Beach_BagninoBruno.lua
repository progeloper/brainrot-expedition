--!strict
-- Bagnino Bruno (VIL_BEACH_BRUNO) on the one villager body.
-- Beach set: southern Italian fisherman's work dress, docs/villagers/Beach_outfit_reference.md.
-- Identity hooks kept: red knitted fisherman's cap with the single Beach glow band, blond
-- hair, red work blouse with a white collar and placket, whistle on a white lanyard, blue
-- waist sash, canvas knee breeches, bare shins, dark boots, and the lifeguard's red rescue
-- tube with its white band in the right hand.
-- The body's own hips and thighs (palette role "bottom", CanvasTan) are the breeches; the
-- blouse and sleeves cover its torso and arms, which would otherwise be white.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Beach_BagninoBruno",
	villagerId = "VIL_BEACH_BRUNO",
	name = "Bagnino Bruno",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "red knit cap", "whistle", "waist sash", "rescue tube" }),
	activities = table.freeze({ "Lookout", "Sweep" }),
	boxes = table.freeze(S.Join(S.Eyes(4.45, -0.9, 0.5, 0.76, 0.84, "Amber"), {
		-- face
		B(
			"Head",
			"face",
			"Mouth",
			-0.45,
			3.8,
			-0.94,
			0.45,
			4.0,
			-0.9,
			"Protected",
			{ color = "#3A0F12" }
		),
		B(
			"Head",
			"face",
			"Tongue",
			-0.22,
			3.8,
			-0.95,
			0.22,
			3.88,
			-0.94,
			"Protected",
			{ color = "#FF6F7D" }
		),
		B("Head", "face", "Nose", -0.17, 4.02, -1.14, 0.17, 4.28, -0.9, "skin2"),
		-- hair: fringe under the cap, sides, back, and a top that shows once the cap is thrown
		B(
			"Head",
			"headwear",
			"HairFringe",
			-0.95,
			4.86,
			-0.97,
			0.95,
			5.02,
			-0.9,
			"hair",
			{ relief = true }
		),
		B(
			"Head",
			"headwear",
			"HairSide_L",
			-1.12,
			4.3,
			-0.3,
			-1.05,
			5.02,
			0.95,
			"hair",
			{ relief = true }
		),
		B(
			"Head",
			"headwear",
			"HairSide_R",
			1.05,
			4.3,
			-0.3,
			1.12,
			5.02,
			0.95,
			"hair",
			{ relief = true }
		),
		B(
			"Head",
			"headwear",
			"HairBack",
			-1.1,
			4.3,
			0.9,
			1.1,
			5.02,
			1.03,
			"hair",
			{ relief = true }
		),
		B("Head", "headwear", "HairTop", -1.05, 5.0, -0.9, 1.05, 5.05, 0.98, "hair"),
		-- headwear: knitted fisherman's cap. Everything on the Hat bone sits at or above the
		-- head top (y 5.05) so it lands flat when thrown.
		B(
			"Hat",
			"headwear",
			"KnitCap",
			-1.1,
			5.05,
			-0.98,
			1.1,
			5.36,
			1.0,
			"hat",
			{ relief = true }
		),
		B("Hat", "headwear", "KnitCapTop", -0.7, 5.36, -0.6, 0.7, 5.58, 0.6, "hat"),
		B("Hat", "headwear", "KnitCapBand", -1.12, 5.05, -1.0, 1.12, 5.15, 1.02, "glow"),
		-- top: red work blouse over the torso and arms, white collar and placket
		B(
			"Torso",
			"top",
			"Blouse",
			-1.09,
			2.0,
			-0.64,
			1.09,
			3.52,
			0.64,
			"cloth",
			{ relief = true }
		),
		B("Torso", "top", "BlouseCollar", -0.6, 3.4, -0.68, 0.6, 3.55, -0.62, "top"),
		B("Torso", "top", "BlousePlacket", -0.1, 2.3, -0.67, 0.1, 3.4, -0.63, "top"),
		B(
			"UpperArmL",
			"top",
			"BlouseSleeve_L",
			-1.6,
			2.22,
			-0.35,
			-1.02,
			3.5,
			0.35,
			"cloth",
			{ relief = true }
		),
		B(
			"UpperArmR",
			"top",
			"BlouseSleeve_R",
			1.02,
			2.22,
			-0.35,
			1.6,
			3.5,
			0.35,
			"cloth",
			{ relief = true }
		),
		-- bottom: bare shins below the breeches
		B("LegL", "bottom", "Shin_L", -0.82, 0.62, -0.32, -0.18, 1.0, 0.32, "skin"),
		B("LegR", "bottom", "Shin_R", 0.18, 0.62, -0.32, 0.82, 1.0, 0.32, "skin"),
		-- footwear: boot legs above the body's dark feet
		B("LegL", "footwear", "BootLeg_L", -0.88, 0.4, -0.5, -0.12, 0.62, 0.37, "shoe"),
		B("LegR", "footwear", "BootLeg_R", 0.12, 0.4, -0.5, 0.88, 0.62, 0.37, "shoe"),
		-- accessory: blue waist sash with a tail, and the whistle on its lanyard
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
		B("Hips", "accessory", "WaistSashTail", 0.55, 1.5, -0.63, 0.8, 2.0, -0.56, "acc"),
		B("Torso", "accessory", "Lanyard_L", -0.5, 3.0, -0.69, -0.4, 3.5, -0.64, "trim"),
		B("Torso", "accessory", "Lanyard_R", 0.4, 3.0, -0.69, 0.5, 3.5, -0.64, "trim"),
		B("Torso", "accessory", "Whistle", -0.25, 2.72, -0.82, 0.25, 3.02, -0.64, "prop"),
		-- props: the rescue tube held upright in front of the right fist
		B(
			"Prop",
			"props",
			"RescueTube",
			1.15,
			1.35,
			-1.2,
			1.55,
			2.95,
			-0.45,
			"prop",
			{ relief = true }
		),
		B("Prop", "props", "RescueTubeBand", 1.13, 2.0, -1.22, 1.57, 2.3, -0.43, "prop2"),
	})),
})
