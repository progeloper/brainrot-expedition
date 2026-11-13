--!strict
-- Pescatore Pozzo (VIL_SWAMP_POZZO) on the one villager body.
-- Swamp set: Mekong Delta áo bà ba work clothes (fisherman),
-- docs/villagers/Swamp_outfit_reference.md.
-- Identity hooks kept: grey hair, full cheeks and a broad nose, the palm-leaf nón lá on his head
-- (its band is the Swamp glow line; it flies off in his hat-throw tantrum), a checked khăn rằn
-- scarf with a tail, the brown áo bà ba shirt hanging over the hips, wide brown trousers rolled
-- to the calf, bare shins, sandals, and his fishing net on a pole in the right hand with a
-- glowing float on the hoop.
-- The body's own torso and arms (palette role "top") and hips and legs ("bottom") are the brown
-- shirt and trousers; its feet ("shoe") are the sandal soles.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Swamp_PescatorePozzo",
	villagerId = "VIL_SWAMP_POZZO",
	name = "Pescatore Pozzo",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "nón lá", "grey hair", "khăn rằn scarf", "fishing net" }),
	activities = table.freeze({ "Fish", "Lookout" }),
	-- the net's pole stands vertical whatever the hand does (Utility/VillagerUprightProp)
	uprightProp = true,
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
		B("Head", "face", "Cheek_L", -1.12, 3.95, -0.7, -1.05, 4.45, 0.4, "skin2"),
		B("Head", "face", "Cheek_R", 1.05, 3.95, -0.7, 1.12, 4.45, 0.4, "skin2"),
		-- hair: grey at the back and sides, and a top that shows once the hat is thrown
		B(
			"Head",
			"headwear",
			"HairBack",
			-1.1,
			3.95,
			0.9,
			1.1,
			5.02,
			1.05,
			"hair",
			{ relief = true }
		),
		B("Head", "headwear", "HairSide_L", -1.12, 4.45, 0.4, -1.05, 5.02, 0.95, "hair"),
		B("Head", "headwear", "HairSide_R", 1.05, 4.45, 0.4, 1.12, 5.02, 0.95, "hair"),
		B("Head", "headwear", "HairTop", -1.08, 5.0, -0.9, 1.08, 5.05, 0.98, "hair"),
		-- headwear: the nón lá, a wide brim and stepped rings up to the tip. Everything on the
		-- Hat bone sits at or above the head top (y 5.05) so it lands flat when thrown.
		B(
			"Hat",
			"headwear",
			"NonLaBrim",
			-1.35,
			5.05,
			-1.3,
			1.35,
			5.15,
			1.3,
			"hat",
			{ relief = true }
		),
		B(
			"Hat",
			"headwear",
			"NonLa2",
			-1.0,
			5.15,
			-0.95,
			1.0,
			5.35,
			0.95,
			"hat",
			{ relief = true }
		),
		B("Hat", "headwear", "NonLaBand", -1.02, 5.15, -0.97, 1.02, 5.21, 0.97, "glow"),
		B("Hat", "headwear", "NonLa3", -0.65, 5.35, -0.6, 0.65, 5.55, 0.6, "hat"),
		B("Hat", "headwear", "NonLaTip", -0.3, 5.55, -0.28, 0.3, 5.75, 0.28, "hat"),
		-- top: the áo bà ba, roomy over the chest and arms, hanging over the hips split at the
		-- sides, with three small buttons
		B("Torso", "top", "Ao", -1.09, 2.0, -0.64, 1.09, 3.52, 0.64, "top", { relief = true }),
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
		B("Hips", "top", "AoFront", -1.04, 1.55, -0.64, 1.04, 2.02, -0.5, "top", { relief = true }),
		B("Hips", "top", "AoBack", -1.04, 1.55, 0.5, 1.04, 2.02, 0.64, "top", { relief = true }),
		B("Torso", "top", "Button1", -0.06, 2.35, -0.68, 0.06, 2.45, -0.64, "acc"),
		B("Torso", "top", "Button2", -0.06, 2.62, -0.68, 0.06, 2.72, -0.64, "acc"),
		B("Torso", "top", "Button3", -0.06, 2.89, -0.68, 0.06, 2.99, -0.64, "acc"),
		-- accessory: khăn rằn checked scarf at the neck, with a tail down the front
		B(
			"Torso",
			"accessory",
			"Scarf",
			-0.62,
			3.42,
			-0.68,
			0.62,
			3.64,
			0.68,
			"acc",
			{ relief = true }
		),
		B("Torso", "accessory", "ScarfCheck1", -0.62, 3.42, -0.72, -0.32, 3.53, -0.68, "acc2"),
		B("Torso", "accessory", "ScarfCheck2", -0.32, 3.53, -0.72, -0.02, 3.64, -0.68, "acc2"),
		B("Torso", "accessory", "ScarfCheck3", -0.02, 3.42, -0.72, 0.28, 3.53, -0.68, "acc2"),
		B("Torso", "accessory", "ScarfCheck4", 0.28, 3.53, -0.72, 0.58, 3.64, -0.68, "acc2"),
		B("Torso", "accessory", "ScarfTail", 0.28, 2.92, -0.76, 0.54, 3.42, -0.69, "acc"),
		B("Torso", "accessory", "ScarfTailCheck", 0.28, 2.92, -0.79, 0.54, 3.1, -0.76, "acc2"),
		-- bottom: wide trousers rolled to the calf, over bare shins
		B(
			"LegL",
			"bottom",
			"Trouser_L",
			-0.98,
			0.9,
			-0.46,
			-0.04,
			1.5,
			0.46,
			"bottom",
			{ relief = true }
		),
		B(
			"LegR",
			"bottom",
			"Trouser_R",
			0.04,
			0.9,
			-0.46,
			0.98,
			1.5,
			0.46,
			"bottom",
			{ relief = true }
		),
		B(
			"LegL",
			"bottom",
			"TrouserCuff_L",
			-1.0,
			0.8,
			-0.48,
			-0.02,
			0.92,
			0.48,
			"bottom",
			{ relief = true }
		),
		B(
			"LegR",
			"bottom",
			"TrouserCuff_R",
			0.02,
			0.8,
			-0.48,
			1.0,
			0.92,
			0.48,
			"bottom",
			{ relief = true }
		),
		B("LegL", "bottom", "Shin_L", -0.82, 0.4, -0.32, -0.18, 0.8, 0.32, "skin"),
		B("LegR", "bottom", "Shin_R", 0.18, 0.4, -0.32, 0.82, 0.8, 0.32, "skin"),
		-- footwear: bare feet on the body's brown sandal soles, with a strap across
		B("FootL", "bottom", "Foot_L", -0.92, 0.1, -0.87, -0.08, 0.36, 0.37, "skin"),
		B("FootR", "bottom", "Foot_R", 0.08, 0.1, -0.87, 0.92, 0.36, 0.37, "skin"),
		B("FootL", "footwear", "SandalStrap_L", -0.94, 0.32, -0.58, -0.06, 0.4, -0.46, "shoe"),
		B("FootR", "footwear", "SandalStrap_R", 0.06, 0.32, -0.58, 0.94, 0.4, -0.46, "shoe"),
		-- props: the fishing net on its pole in the right hand, the hoop beside his head and the
		-- net hanging in it, a glowing float on the hoop. `uprightProp` keeps it vertical.
		B("Prop", "props", "NetPole", 1.62, 1.5, -0.08, 1.78, 4.62, 0.08, "prop2"),
		B("Prop", "props", "NetHoopTop", 1.58, 4.62, -0.8, 1.82, 4.74, 0.8, "prop2"),
		B("Prop", "props", "NetHoopFront", 1.6, 3.7, -0.8, 1.8, 4.62, -0.68, "prop2"),
		B("Prop", "props", "NetHoopBack", 1.6, 3.7, 0.68, 1.8, 4.62, 0.8, "prop2"),
		B("Prop", "props", "NetBag", 1.6, 3.4, -0.68, 1.8, 4.62, 0.68, "prop", { relief = true }),
		B("Prop", "props", "NetFloat", 1.56, 4.25, -0.96, 1.84, 4.5, -0.8, "glow"),
	})),
})
