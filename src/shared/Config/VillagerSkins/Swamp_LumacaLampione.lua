--!strict
-- Lumaca Lampione (VIL_SWAMP_LUMACA) on the one villager body.
-- Swamp set: Mekong Delta áo bà ba work clothes (snail), docs/villagers/Swamp_outfit_reference.md.
-- Identity hooks kept: a pale mint snail face framed in green, big green eyes, two eye stalks
-- poking up through the palm-leaf nón lá (its band is the Swamp glow line), a checked khăn rằn
-- scarf with a tail, the brown áo bà ba shirt open over a pale belly, black trousers rolled to
-- the calf, mint feet on sandals, and the big rust snail shell on his back with a glowing
-- lantern window in each spiral and a little lamp cap on top.
-- The body's own head and hands (palette role "skin") are the mint snail skin, its torso and
-- arms ("top") the brown shirt, its hips and legs ("bottom") the trousers, and its feet ("shoe")
-- the sandal soles.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Swamp_LumacaLampione",
	villagerId = "VIL_SWAMP_LUMACA",
	name = "Lumaca Lampione",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "snail shell lantern", "eye stalks", "nón lá", "khăn rằn scarf" }),
	activities = table.freeze({ "Lookout" }),
	boxes = table.freeze(S.Join(S.Eyes(4.42, -0.9, 0.5, 0.8, 0.86, "Lime"), {
		-- face: the head's front stays pale mint; green round the sides, back and top
		B(
			"Head",
			"face",
			"Mouth",
			-0.4,
			3.78,
			-0.94,
			0.4,
			3.94,
			-0.9,
			"Protected",
			{ color = "#3A0F12" }
		),
		B(
			"Head",
			"face",
			"Tongue",
			-0.2,
			3.78,
			-0.95,
			0.2,
			3.85,
			-0.94,
			"Protected",
			{ color = "#FF6F7D" }
		),
		B(
			"Head",
			"face",
			"HeadSide_L",
			-1.12,
			3.65,
			-0.62,
			-1.05,
			5.05,
			0.95,
			"cloth",
			{ relief = true }
		),
		B(
			"Head",
			"face",
			"HeadSide_R",
			1.05,
			3.65,
			-0.62,
			1.12,
			5.05,
			0.95,
			"cloth",
			{ relief = true }
		),
		B(
			"Head",
			"face",
			"HeadBack",
			-1.12,
			3.65,
			0.9,
			1.12,
			5.05,
			1.0,
			"cloth",
			{ relief = true }
		),
		B("Head", "face", "HeadTop", -1.1, 5.0, -0.92, 1.1, 5.05, 0.98, "cloth"),
		-- eye stalks: up through the hat, a green ball on each tip
		B("Head", "face", "Stalk_L", -0.66, 5.0, -0.44, -0.48, 5.95, -0.26, "skin"),
		B("Head", "face", "Stalk_R", 0.48, 5.0, -0.44, 0.66, 5.95, -0.26, "skin"),
		B(
			"Head",
			"face",
			"StalkTip_L",
			-0.76,
			5.95,
			-0.54,
			-0.38,
			6.3,
			-0.16,
			"skin2",
			{ relief = true }
		),
		B(
			"Head",
			"face",
			"StalkTip_R",
			0.38,
			5.95,
			-0.54,
			0.76,
			6.3,
			-0.16,
			"skin2",
			{ relief = true }
		),
		-- headwear: the nón lá. Everything on the Hat bone sits at or above the head top.
		B(
			"Hat",
			"headwear",
			"NonLaBrim",
			-1.3,
			5.05,
			-1.25,
			1.3,
			5.15,
			1.25,
			"hat",
			{ relief = true }
		),
		B(
			"Hat",
			"headwear",
			"NonLa2",
			-0.95,
			5.15,
			-0.9,
			0.95,
			5.35,
			0.9,
			"hat",
			{ relief = true }
		),
		B("Hat", "headwear", "NonLaBand", -0.97, 5.15, -0.92, 0.97, 5.21, 0.92, "glow"),
		B("Hat", "headwear", "NonLa3", -0.6, 5.35, -0.55, 0.6, 5.55, 0.55, "hat"),
		B("Hat", "headwear", "NonLaTip", -0.25, 5.55, -0.22, 0.25, 5.75, 0.22, "hat"),
		-- top: the áo bà ba open at the front over his pale belly, hanging over the hips
		B("Torso", "top", "Belly", -0.5, 2.0, -0.65, 0.5, 3.4, -0.6, "cloth3", { relief = true }),
		B("Torso", "top", "BellyBand", -0.5, 2.55, -0.68, 0.5, 2.68, -0.64, "trim"),
		B(
			"UpperArmL",
			"top",
			"AoSleeve_L",
			-1.6,
			2.22,
			-0.35,
			-1.02,
			3.5,
			0.35,
			"top",
			{ relief = true }
		),
		B(
			"UpperArmR",
			"top",
			"AoSleeve_R",
			1.02,
			2.22,
			-0.35,
			1.6,
			3.5,
			0.35,
			"top",
			{ relief = true }
		),
		B("Hips", "top", "AoFront", -1.0, 1.55, -0.62, 1.0, 2.02, -0.5, "top", { relief = true }),
		B("Hips", "top", "AoBack", -1.0, 1.55, 0.5, 1.0, 2.02, 0.62, "top", { relief = true }),
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
		B("Torso", "accessory", "ScarfTail", 0.56, 2.92, -0.74, 0.82, 3.42, -0.67, "acc"),
		B("Torso", "accessory", "ScarfTailCheck", 0.56, 2.92, -0.77, 0.82, 3.1, -0.74, "acc2"),
		-- bottom: trousers rolled to the calf over mint shins
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
		-- footwear: mint feet on the body's brown sandal soles, with a strap across
		B("FootL", "bottom", "Foot_L", -0.92, 0.1, -0.87, -0.08, 0.36, 0.37, "skin"),
		B("FootR", "bottom", "Foot_R", 0.08, 0.1, -0.87, 0.92, 0.36, 0.37, "skin"),
		B("FootL", "footwear", "SandalStrap_L", -0.94, 0.32, -0.58, -0.06, 0.4, -0.46, "shoe"),
		B("FootR", "footwear", "SandalStrap_R", 0.06, 0.32, -0.58, 0.94, 0.4, -0.46, "shoe"),
		-- back: the snail shell, its upper part set back behind his head, a spiral on each
		-- side with the glowing lantern window at its centre, and the lamp cap on top
		B("Back", "back", "Shell", -0.92, 1.7, 0.62, 0.92, 3.4, 2.0, "cloth2", { relief = true }),
		B(
			"Back",
			"back",
			"ShellTop",
			-0.92,
			3.4,
			1.28,
			0.92,
			4.2,
			2.0,
			"cloth2",
			{ relief = true }
		),
		B("Back", "back", "SpiralRing_L", -0.96, 2.1, 0.9, -0.92, 3.4, 1.9, "trim"),
		B("Back", "back", "SpiralRing_R", 0.92, 2.1, 0.9, 0.96, 3.4, 1.9, "trim"),
		B("Back", "back", "SpiralInner_L", -0.99, 2.35, 1.12, -0.96, 3.15, 1.68, "cloth2"),
		B("Back", "back", "SpiralInner_R", 0.96, 2.35, 1.12, 0.99, 3.15, 1.68, "cloth2"),
		B("Back", "back", "LanternWindow", -1.02, 2.55, 1.22, 1.02, 2.95, 1.58, "glow"),
		B("Back", "back", "LampCap", -0.3, 4.2, 1.4, 0.3, 4.5, 1.9, "prop"),
		B("Back", "back", "LampTop", -0.14, 4.5, 1.55, 0.14, 4.62, 1.75, "prop2"),
	})),
})
