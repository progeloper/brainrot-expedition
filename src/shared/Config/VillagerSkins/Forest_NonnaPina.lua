--!strict
-- Nonna Pina (VIL_FOREST_PINA) on the one villager body.
-- Forest set: Alpine farm dress (women), docs/villagers/Forest_outfit_reference.md.
-- Identity hooks kept: red headscarf (thrown in her tantrum), white fringe, blue work apron
-- with the single Forest glow band, wool skirt, shawl, rolling pin in the right hand.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Forest_NonnaPina",
	villagerId = "VIL_FOREST_PINA",
	name = "Nonna Pina",
	approved = false,
	hooks = table.freeze({ "headscarf", "white fringe", "work apron", "rolling pin" }),
	activities = table.freeze({ "Knead", "Sweep" }),
	boxes = table.freeze(S.Join(S.Eyes(4.45, -0.9, 0.5, 0.76, 0.84, "Ocean"), {
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
		B("Head", "face", "Nose", -0.17, 4.02, -1.12, 0.17, 4.28, -0.9, "skin2"),
		B("Head", "face", "Cheek_L", -1.12, 3.95, -0.7, -1.05, 4.4, 0.3, "skin2"),
		B("Head", "face", "Cheek_R", 1.05, 3.95, -0.7, 1.12, 4.4, 0.3, "skin2"),
		B(
			"Head",
			"headwear",
			"HairFringe",
			-0.95,
			4.82,
			-0.97,
			0.95,
			5.0,
			-0.9,
			"hair",
			{ relief = true }
		),
		-- headwear: everything on the Hat bone sits at or above the head top (y 5.05) so it
		-- lands flat when thrown
		B(
			"Hat",
			"headwear",
			"Headscarf",
			-1.12,
			4.95,
			-0.98,
			1.12,
			5.35,
			0.98,
			"hat",
			{ relief = true }
		),
		B("Hat", "headwear", "HeadscarfKnot", -0.3, 5.05, 0.75, 0.3, 5.5, 1.2, "hat"),
		-- white hair shows at the back, and on top once the scarf is thrown
		B(
			"Head",
			"headwear",
			"HairBack",
			-1.1,
			3.95,
			0.9,
			1.1,
			5.0,
			1.05,
			"hair",
			{ relief = true }
		),
		-- top
		B("Torso", "top", "Shawl", -1.12, 3.1, -0.66, 1.12, 3.5, 0.66, "trim", { relief = true }),
		B("Torso", "top", "BodiceLacing", -0.08, 2.1, -0.64, 0.08, 3.1, -0.6, "trim"),
		B(
			"UpperArmL",
			"top",
			"PuffSleeve_L",
			-1.68,
			2.95,
			-0.4,
			-1.02,
			3.5,
			0.4,
			"cloth2",
			{ relief = true }
		),
		B(
			"UpperArmR",
			"top",
			"PuffSleeve_R",
			1.02,
			2.95,
			-0.4,
			1.68,
			3.5,
			0.4,
			"cloth2",
			{ relief = true }
		),
		-- bottom: wool skirt, split per bone so it moves with the legs
		B(
			"Hips",
			"bottom",
			"WoolSkirt",
			-1.25,
			1.25,
			-0.8,
			1.25,
			2.0,
			0.8,
			"bottom",
			{ relief = true }
		),
		B(
			"LegL",
			"bottom",
			"SkirtPanel_L",
			-1.2,
			0.55,
			-0.75,
			-0.02,
			1.25,
			0.75,
			"bottom",
			{ relief = true }
		),
		B(
			"LegR",
			"bottom",
			"SkirtPanel_R",
			0.02,
			0.55,
			-0.75,
			1.2,
			1.25,
			0.75,
			"bottom",
			{ relief = true }
		),
		-- footwear
		B("FootL", "footwear", "ShoeTop_L", -0.92, 0.32, -0.87, -0.08, 0.42, 0.37, "sock"),
		B("FootR", "footwear", "ShoeTop_R", 0.08, 0.32, -0.87, 0.92, 0.42, 0.37, "sock"),
		-- accessory: work apron, split at the waist and per leg
		B(
			"Torso",
			"accessory",
			"WorkApron",
			-0.75,
			2.0,
			-0.68,
			0.75,
			2.9,
			-0.62,
			"acc",
			{ relief = true }
		),
		B("Torso", "accessory", "ApronBand", -0.8, 2.9, -0.7, 0.8, 3.0, -0.63, "glow"),
		B(
			"Hips",
			"accessory",
			"ApronLap",
			-0.75,
			1.25,
			-0.88,
			0.75,
			2.0,
			-0.82,
			"acc",
			{ relief = true }
		),
		B(
			"LegL",
			"accessory",
			"ApronFlap_L",
			-0.75,
			0.7,
			-0.83,
			-0.02,
			1.25,
			-0.77,
			"acc",
			{ relief = true }
		),
		B(
			"LegR",
			"accessory",
			"ApronFlap_R",
			0.02,
			0.7,
			-0.83,
			0.75,
			1.25,
			-0.77,
			"acc",
			{ relief = true }
		),
		-- props: rolling pin held upright in front of the right fist
		B("Prop", "props", "PinHandle", 1.18, 1.5, -0.72, 1.42, 2.3, -0.48, "prop2"),
		B(
			"Prop",
			"props",
			"PinBody",
			1.02,
			2.3,
			-0.88,
			1.58,
			3.7,
			-0.32,
			"prop",
			{ relief = true }
		),
		B("Prop", "props", "PinTip", 1.18, 3.7, -0.72, 1.42, 4.05, -0.48, "prop2"),
	})),
})
