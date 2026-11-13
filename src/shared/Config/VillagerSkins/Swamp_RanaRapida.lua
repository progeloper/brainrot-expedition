--!strict
-- Rana Rapida (VIL_SWAMP_RANA) on the one villager body.
-- Swamp set: Mekong Delta áo bà ba work clothes (frog), docs/villagers/Swamp_outfit_reference.md.
-- Identity hooks kept: green frog skin, a wide frog mouth with a dark lip line and a pale
-- throat, two eye bumps on top of the head, big amber eyes, the palm-leaf nón lá hung on his
-- back by its strap (the strap is the Swamp glow line), a checked khăn rằn scarf with a tail,
-- the black áo bà ba shirt hanging over the hips, black trousers rolled to the calf with
-- green shins, webbed green hands, and webbed green feet on brown sandals.
-- The body's own head and hands (palette role "skin") are the frog's green skin, its torso and
-- arms (role "top") are the shirt and its sleeves, its hips and legs (role "bottom") are the
-- trousers, and its feet (role "shoe") are the sandal soles.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Swamp_RanaRapida",
	villagerId = "VIL_SWAMP_RANA",
	name = "Rana Rapida",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({
		"frog eye bumps",
		"nón lá on the back",
		"khăn rằn scarf",
		"áo bà ba",
	}),
	activities = table.freeze({ "Lookout", "Sweep" }),
	boxes = table.freeze(S.Join(S.Eyes(4.45, -0.9, 0.5, 0.8, 0.86, "Amber"), {
		-- face: a wide frog mouth, the dark lip line under it and a pale throat
		B(
			"Head",
			"face",
			"Mouth",
			-0.62,
			3.84,
			-0.94,
			0.62,
			3.98,
			-0.9,
			"Protected",
			{ color = "#3A0F12" }
		),
		B(
			"Head",
			"face",
			"Tongue",
			-0.22,
			3.84,
			-0.95,
			0.22,
			3.9,
			-0.94,
			"Protected",
			{ color = "#FF6F7D" }
		),
		B("Head", "face", "Lip", -1.0, 3.79, -0.93, 1.0, 3.84, -0.9, "skin2"),
		B("Head", "face", "Throat", -0.72, 3.65, -0.93, 0.72, 3.79, -0.9, "cloth3"),
		-- two eye bumps on top of the head, and two dark spots behind them
		B(
			"Head",
			"face",
			"EyeBump_L",
			-0.98,
			5.0,
			-0.9,
			-0.22,
			5.45,
			0.05,
			"skin",
			{ relief = true }
		),
		B(
			"Head",
			"face",
			"EyeBump_R",
			0.22,
			5.0,
			-0.9,
			0.98,
			5.45,
			0.05,
			"skin",
			{ relief = true }
		),
		B("Head", "face", "Spot_L", -0.62, 5.05, 0.25, -0.22, 5.08, 0.62, "skin2"),
		B("Head", "face", "Spot_R", 0.18, 5.05, 0.4, 0.5, 5.08, 0.72, "skin2"),
		-- back: the nón lá hung on his back by its strap, seen as stepped rings of palm leaf
		B("Back", "back", "NonLa1", -1.0, 1.95, 0.62, 1.0, 3.55, 0.74, "hat", { relief = true }),
		B("Back", "back", "NonLa2", -0.84, 2.15, 0.74, 0.84, 3.35, 0.88, "hat", { relief = true }),
		B("Back", "back", "NonLa3", -0.55, 2.4, 0.88, 0.55, 3.1, 1.02, "hat"),
		B("Back", "back", "NonLaTip", -0.24, 2.6, 1.02, 0.24, 2.9, 1.14, "hat"),
		-- the hat's chin strap: over both shoulders and round the front of the neck (glow line)
		B("Torso", "back", "Strap_L", -0.72, 3.5, -0.66, -0.64, 3.56, 0.68, "glow"),
		B("Torso", "back", "Strap_R", 0.64, 3.5, -0.66, 0.72, 3.56, 0.68, "glow"),
		B("Torso", "back", "StrapFront_L", -0.72, 3.34, -0.665, -0.64, 3.5, -0.6, "glow"),
		B("Torso", "back", "StrapFront_R", 0.64, 3.34, -0.665, 0.72, 3.5, -0.6, "glow"),
		B("Torso", "back", "StrapLoop", -0.72, 3.34, -0.665, 0.72, 3.4, -0.6, "glow"),
		-- top: the áo bà ba hangs over the hips, split at the sides; three small buttons
		B("Hips", "top", "AoFront", -0.98, 1.62, -0.62, 0.98, 2.02, -0.5, "top", { relief = true }),
		B("Hips", "top", "AoBack", -0.98, 1.62, 0.5, 0.98, 2.02, 0.62, "top", { relief = true }),
		B("Torso", "top", "Button1", -0.06, 2.35, -0.64, 0.06, 2.45, -0.6, "acc"),
		B("Torso", "top", "Button2", -0.06, 2.62, -0.64, 0.06, 2.72, -0.6, "acc"),
		B("Torso", "top", "Button3", -0.06, 2.89, -0.64, 0.06, 2.99, -0.6, "acc"),
		-- accessory: khăn rằn checked scarf at the neck, with a tail down the front
		B(
			"Torso",
			"accessory",
			"Scarf",
			-0.62,
			3.42,
			-0.66,
			0.62,
			3.64,
			0.66,
			"acc",
			{ relief = true }
		),
		B("Torso", "accessory", "ScarfCheck1", -0.62, 3.42, -0.7, -0.32, 3.53, -0.66, "acc2"),
		B("Torso", "accessory", "ScarfCheck2", -0.32, 3.53, -0.7, -0.02, 3.64, -0.66, "acc2"),
		B("Torso", "accessory", "ScarfCheck3", -0.02, 3.42, -0.7, 0.28, 3.53, -0.66, "acc2"),
		B("Torso", "accessory", "ScarfCheck4", 0.28, 3.53, -0.7, 0.58, 3.64, -0.66, "acc2"),
		B("Torso", "accessory", "ScarfTail", 0.28, 2.92, -0.74, 0.54, 3.42, -0.67, "acc"),
		B("Torso", "accessory", "ScarfTailCheck", 0.28, 2.92, -0.77, 0.54, 3.1, -0.74, "acc2"),
		-- hands: webbing under each green hand
		B("HandL", "bottom", "Webbing_L", -1.69, 1.5, -0.4, -0.91, 1.56, 0.4, "skin2"),
		B("HandR", "bottom", "Webbing_R", 0.91, 1.5, -0.4, 1.69, 1.56, 0.4, "skin2"),
		-- bottom: trousers rolled to the calf over bare green shins
		B(
			"LegL",
			"bottom",
			"TrouserCuff_L",
			-0.84,
			0.88,
			-0.34,
			-0.16,
			1.02,
			0.34,
			"bottom",
			{ relief = true }
		),
		B(
			"LegR",
			"bottom",
			"TrouserCuff_R",
			0.16,
			0.88,
			-0.34,
			0.84,
			1.02,
			0.34,
			"bottom",
			{ relief = true }
		),
		B("LegL", "bottom", "Shin_L", -0.82, 0.4, -0.32, -0.18, 0.88, 0.32, "skin"),
		B("LegR", "bottom", "Shin_R", 0.18, 0.4, -0.32, 0.82, 0.88, 0.32, "skin"),
		-- footwear: webbed green feet on the body's brown sandal soles, with a strap across
		B("FootL", "bottom", "FrogFoot_L", -0.92, 0.1, -0.95, -0.08, 0.42, 0.37, "skin"),
		B("FootR", "bottom", "FrogFoot_R", 0.08, 0.1, -0.95, 0.92, 0.42, 0.37, "skin"),
		B("FootL", "bottom", "Toes_L", -0.9, 0.1, -1.05, -0.1, 0.18, -0.95, "skin2"),
		B("FootR", "bottom", "Toes_R", 0.1, 0.1, -1.05, 0.9, 0.18, -0.95, "skin2"),
		B("FootL", "footwear", "SandalStrap_L", -0.94, 0.38, -0.58, -0.06, 0.46, -0.46, "shoe"),
		B("FootR", "footwear", "SandalStrap_R", 0.06, 0.38, -0.58, 0.94, 0.46, -0.46, "shoe"),
	})),
})
