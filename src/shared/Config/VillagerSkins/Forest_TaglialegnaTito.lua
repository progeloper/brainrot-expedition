--!strict
-- Taglialegna Tito (VIL_FOREST_TITO) on the one villager body.
-- Forest set: Alpine loden work dress (men), docs/villagers/Forest_outfit_reference.md.
-- Identity hooks kept: felt hat with the single Forest glow cord band, brown hair, green
-- loden jacket open over a brown waistcoat and white shirt, red neckerchief, leather knee
-- breeches with cream knee socks, dark boots, breadstick axe in the right hand.
-- The body's own torso (palette role "top", LodenBrown) shows between the jacket fronts as
-- the waistcoat, and its hips and thighs (role "bottom", LeatherBrown) are the breeches.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Forest_TaglialegnaTito",
	villagerId = "VIL_FOREST_TITO",
	name = "Taglialegna Tito",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "felt hat", "loden jacket", "neckerchief", "breadstick axe" }),
	activities = table.freeze({ "Chop", "Sweep" }),
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
		-- hair: fringe under the brim, sides and back; the top shows once the hat is thrown
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
			4.1,
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
			4.1,
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
			4.1,
			0.9,
			1.1,
			5.02,
			1.03,
			"hair",
			{ relief = true }
		),
		-- headwear: felt hat. Everything on the Hat bone sits at or above the head top (y 5.05)
		-- so it lands flat when thrown.
		B("Hat", "headwear", "FeltHatBrim", -1.3, 5.05, -1.3, 1.3, 5.15, 1.25, "hat"),
		B(
			"Hat",
			"headwear",
			"FeltHatCrown",
			-0.9,
			5.15,
			-0.8,
			0.9,
			5.68,
			0.8,
			"hat",
			{ relief = true }
		),
		B("Hat", "headwear", "FeltHatBand", -0.92, 5.15, -0.82, 0.92, 5.27, 0.82, "glow"),
		-- top: open loden jacket (fronts, sides, back, collar, sleeves) and the shirt front
		B(
			"Torso",
			"top",
			"JacketFront_L",
			-1.1,
			2.0,
			-0.66,
			-0.48,
			3.42,
			-0.6,
			"cloth",
			{ relief = true }
		),
		B(
			"Torso",
			"top",
			"JacketFront_R",
			0.48,
			2.0,
			-0.66,
			1.1,
			3.42,
			-0.6,
			"cloth",
			{ relief = true }
		),
		B("Torso", "top", "JacketSide_L", -1.11, 2.0, -0.6, -1.05, 3.42, 0.6, "cloth"),
		B("Torso", "top", "JacketSide_R", 1.05, 2.0, -0.6, 1.11, 3.42, 0.6, "cloth"),
		B(
			"Torso",
			"top",
			"JacketBack",
			-1.1,
			2.0,
			0.6,
			1.1,
			3.42,
			0.66,
			"cloth",
			{ relief = true }
		),
		B(
			"Torso",
			"top",
			"JacketCollar",
			-1.1,
			3.42,
			-0.66,
			1.1,
			3.54,
			0.66,
			"cloth",
			{ relief = true }
		),
		B("Torso", "top", "ShirtFront", -0.32, 2.95, -0.63, 0.32, 3.42, -0.6, "cloth3"),
		B(
			"UpperArmL",
			"top",
			"JacketSleeve_L",
			-1.6,
			2.25,
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
			"JacketSleeve_R",
			1.02,
			2.25,
			-0.35,
			1.6,
			3.5,
			0.35,
			"cloth",
			{ relief = true }
		),
		-- bottom: breeches cuffs at the knee, cream knee socks below
		B("LegL", "bottom", "BreechesCuff_L", -0.84, 0.98, -0.34, -0.16, 1.1, 0.34, "trim"),
		B("LegR", "bottom", "BreechesCuff_R", 0.16, 0.98, -0.34, 0.84, 1.1, 0.34, "trim"),
		B(
			"LegL",
			"bottom",
			"KneeSock_L",
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
			"KneeSock_R",
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
		-- accessory: red wool neckerchief
		B("Torso", "accessory", "Neckerchief", -0.44, 3.3, -0.72, 0.44, 3.52, -0.63, "acc"),
		B("Torso", "accessory", "NeckerchiefKnot", -0.15, 3.06, -0.74, 0.15, 3.3, -0.66, "acc"),
		-- props: breadstick axe held upright in front of the right fist, blade forward
		B("Prop", "props", "AxeHandle", 1.2, 1.4, -0.7, 1.4, 3.6, -0.5, "prop", { relief = true }),
		B(
			"Prop",
			"props",
			"AxeHead",
			1.12,
			2.95,
			-1.3,
			1.48,
			3.55,
			-0.7,
			"prop2",
			{ relief = true }
		),
		B("Prop", "props", "AxeEdge", 1.15, 3.0, -1.42, 1.45, 3.5, -1.3, "prop"),
	})),
})
