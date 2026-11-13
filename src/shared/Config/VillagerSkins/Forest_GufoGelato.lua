--!strict
-- Gufo Gelato (VIL_FOREST_GUFO) on the one villager body.
-- Forest set: Alpine loden work dress (animal villagers), docs/villagers/Forest_outfit_reference.md.
-- Identity hooks kept: owl face disc with big lime eyes and an orange beak, ear tufts poking
-- out past the felt hat, dark wing-arms, cream belly, green loden waistcoat, red shoulder
-- scarf, and the gelato cone in the right hand. The hat band is the single Forest glow line.
-- The body's own torso (palette role "top", LodenGreen) is the waistcoat and its hips and
-- thighs (role "bottom", LeatherBrown) are the breeches; feather boxes cover the bare skin.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Forest_GufoGelato",
	villagerId = "VIL_FOREST_GUFO",
	name = "Gufo Gelato",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "owl face", "ear tufts", "felt hat", "shoulder scarf", "gelato cone" }),
	activities = table.freeze({ "Lookout" }),
	boxes = table.freeze(S.Join(S.Eyes(4.42, -0.9, 0.52, 0.86, 0.9, "Lime"), {
		-- face: the head's front stays cream as the face disc
		B("Head", "face", "Beak", -0.22, 3.92, -1.3, 0.22, 4.24, -0.9, "skin2"),
		B(
			"Head",
			"face",
			"Mouth",
			-0.36,
			3.74,
			-0.94,
			0.36,
			3.9,
			-0.9,
			"Protected",
			{ color = "#3A0F12" }
		),
		B(
			"Head",
			"face",
			"Tongue",
			-0.18,
			3.74,
			-0.95,
			0.18,
			3.81,
			-0.94,
			"Protected",
			{ color = "#FF6F7D" }
		),
		-- head feathers: brow, sides, back and crown around the face disc
		B(
			"Head",
			"headwear",
			"BrowFeathers",
			-1.08,
			4.88,
			-0.97,
			1.08,
			5.05,
			-0.9,
			"cloth",
			{ relief = true }
		),
		B("Head", "headwear", "BrowPeak", -0.2, 4.62, -0.96, 0.2, 4.88, -0.9, "cloth"),
		B(
			"Head",
			"headwear",
			"HeadFeathers_L",
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
			"HeadFeathers_R",
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
			"HeadFeathersBack",
			-1.12,
			3.65,
			0.9,
			1.12,
			5.05,
			1.0,
			"cloth",
			{ relief = true }
		),
		B("Head", "headwear", "CrownFeathers", -1.1, 5.0, -0.95, 1.1, 5.05, 0.98, "cloth"),
		-- ear tufts stay on the head, beside the hat crown, so they remain when the hat is thrown
		B(
			"Head",
			"headwear",
			"Tuft_L",
			-1.22,
			4.95,
			-0.2,
			-0.86,
			5.62,
			0.3,
			"cloth2",
			{ relief = true }
		),
		B(
			"Head",
			"headwear",
			"Tuft_R",
			0.86,
			4.95,
			-0.2,
			1.22,
			5.62,
			0.3,
			"cloth2",
			{ relief = true }
		),
		-- headwear: felt hat. Everything on the Hat bone sits at or above the head top (y 5.05).
		B("Hat", "headwear", "FeltHatBrim", -1.2, 5.05, -1.15, 1.2, 5.15, 1.15, "hat"),
		B(
			"Hat",
			"headwear",
			"FeltHatCrown",
			-0.8,
			5.15,
			-0.7,
			0.8,
			5.95,
			0.7,
			"hat",
			{ relief = true }
		),
		B("Hat", "headwear", "FeltHatBand", -0.82, 5.15, -0.72, 0.82, 5.27, 0.72, "glow"),
		-- body: neck and chest feathers, cream belly panel with its dark band
		B("Neck", "top", "NeckFeathers", -0.34, 3.48, -0.34, 0.34, 3.67, 0.34, "cloth"),
		B(
			"Torso",
			"top",
			"ChestFeathers",
			-1.08,
			3.05,
			-0.66,
			1.08,
			3.5,
			-0.6,
			"cloth",
			{ relief = true }
		),
		B("Torso", "top", "Belly", -0.72, 2.0, -0.67, 0.72, 2.9, -0.6, "cloth3", { relief = true }),
		B("Torso", "top", "BellyBand", -0.72, 2.9, -0.69, 0.72, 3.05, -0.6, "trim"),
		-- wing-arms: dark wings over the arms, darker tips over the hands
		B(
			"UpperArmL",
			"top",
			"Wing_L",
			-1.64,
			2.22,
			-0.45,
			-1.0,
			3.5,
			0.55,
			"cloth2",
			{ relief = true }
		),
		B(
			"UpperArmR",
			"top",
			"Wing_R",
			1.0,
			2.22,
			-0.45,
			1.64,
			3.5,
			0.55,
			"cloth2",
			{ relief = true }
		),
		B("HandL", "top", "WingTip_L", -1.7, 1.5, -0.4, -0.9, 2.28, 0.45, "trim"),
		B("HandR", "top", "WingTip_R", 0.9, 1.5, -0.4, 1.7, 2.28, 0.45, "trim"),
		-- bottom: breeches cuffs at the knee, cream wool socks below
		B("LegL", "bottom", "BreechesCuff_L", -0.84, 0.98, -0.34, -0.16, 1.1, 0.34, "trim"),
		B("LegR", "bottom", "BreechesCuff_R", 0.16, 0.98, -0.34, 0.84, 1.1, 0.34, "trim"),
		B(
			"LegL",
			"bottom",
			"Sock_L",
			-0.82,
			0.4,
			-0.32,
			-0.18,
			0.98,
			0.32,
			"sock",
			{ relief = true }
		),
		B(
			"LegR",
			"bottom",
			"Sock_R",
			0.18,
			0.4,
			-0.32,
			0.82,
			0.98,
			0.32,
			"sock",
			{ relief = true }
		),
		-- footwear: boot cuffs above the body's dark feet
		B("LegL", "footwear", "BootCuff_L", -0.88, 0.4, -0.5, -0.12, 0.56, 0.37, "shoe"),
		B("LegR", "footwear", "BootCuff_R", 0.12, 0.4, -0.5, 0.88, 0.56, 0.37, "shoe"),
		-- accessory: red wool scarf over the shoulders with a tail down the back
		B(
			"Torso",
			"accessory",
			"ShoulderScarf",
			-1.14,
			3.28,
			-0.2,
			1.14,
			3.54,
			0.7,
			"acc",
			{ relief = true }
		),
		B("Torso", "accessory", "ScarfTail", 0.5, 2.6, 0.62, 0.85, 3.28, 0.72, "acc"),
		-- tail: a short fan of tail feathers (new; the old round body had none)
		B(
			"Tail",
			"tail",
			"TailFeathers",
			-0.55,
			1.15,
			0.52,
			0.55,
			1.9,
			0.74,
			"cloth2",
			{ relief = true }
		),
		-- props: gelato cone held upright in front of the right wingtip
		B("Prop", "props", "GelatoCone", 1.15, 1.6, -0.76, 1.45, 2.5, -0.46, "prop"),
		B(
			"Prop",
			"props",
			"GelatoScoop",
			1.06,
			2.5,
			-0.85,
			1.54,
			2.95,
			-0.37,
			"prop2",
			{ relief = true }
		),
	})),
})
