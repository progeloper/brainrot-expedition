--!strict
-- Zio Sabbia (VIL_BEACH_SABBIA) on the one villager body.
-- Beach set: southern Italian fisherman's work dress (older men),
-- docs/villagers/Beach_outfit_reference.md.
-- Identity hooks kept: wide straw hat with the Beach glow band, sandy beard and hair, loose
-- shirt with a contrasting collar, red waist sash, wide canvas trousers, dark boots, and the
-- raised beach umbrella with its glowing stripe in the right hand (owner, 13 Nov 2026: keep
-- it in his hand; it is held upright by the uprightProp rule).
-- The body's own hips and thighs (palette role "bottom", CanvasTan) are under the trousers;
-- the shirt and sleeves cover its torso and arms.
local S = require(script.Parent.Support)
local B = S.Box

return table.freeze({
	id = "Beach_ZioSabbia",
	villagerId = "VIL_BEACH_SABBIA",
	name = "Zio Sabbia",
	approved = true, -- owner, 13 Nov 2026 (review round 2)
	hooks = table.freeze({ "straw hat", "sandy beard", "waist sash", "beach umbrella" }),
	activities = table.freeze({ "Lookout" }),
	-- the umbrella stands vertical whatever the hand does (Utility/VillagerUprightProp)
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
		B("Head", "face", "Cheek_L", -1.12, 3.95, -0.7, -1.05, 4.4, 0.3, "skin2"),
		B("Head", "face", "Cheek_R", 1.05, 3.95, -0.7, 1.12, 4.4, 0.3, "skin2"),
		B("Head", "face", "Beard", -0.8, 3.32, -0.99, 0.8, 3.76, -0.82, "hair", { relief = true }),
		-- hair: back, and a top that shows once the hat is thrown
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
		B("Head", "headwear", "HairTop", -1.08, 5.0, -0.9, 1.08, 5.05, 0.98, "hair"),
		-- headwear: wide straw hat. Everything on the Hat bone sits at or above the head top.
		B(
			"Hat",
			"headwear",
			"StrawBrim",
			-1.45,
			5.05,
			-1.35,
			1.45,
			5.17,
			1.35,
			"hat",
			{ relief = true }
		),
		B(
			"Hat",
			"headwear",
			"StrawCrown",
			-0.8,
			5.17,
			-0.7,
			0.8,
			5.6,
			0.75,
			"hat2",
			{ relief = true }
		),
		B("Hat", "headwear", "StrawBand", -0.82, 5.17, -0.72, 0.82, 5.27, 0.77, "glow"),
		-- top: loose shirt over the torso and arms, collar in the contrast colour
		B("Torso", "top", "Shirt", -1.09, 2.0, -0.64, 1.09, 3.52, 0.64, "cloth", { relief = true }),
		B("Torso", "top", "ShirtCollar", -0.6, 3.38, -0.68, 0.6, 3.55, -0.62, "top"),
		B(
			"UpperArmL",
			"top",
			"ShirtSleeve_L",
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
			"ShirtSleeve_R",
			1.02,
			2.22,
			-0.35,
			1.6,
			3.5,
			0.35,
			"cloth2",
			{ relief = true }
		),
		-- bottom: wide canvas trousers, split at the hips and per leg
		B(
			"Hips",
			"bottom",
			"TrouserSeat",
			-1.1,
			1.45,
			-0.62,
			1.1,
			2.0,
			0.62,
			"bottom",
			{ relief = true }
		),
		B(
			"LegL",
			"bottom",
			"Trouser_L",
			-0.98,
			0.5,
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
			0.5,
			-0.46,
			0.98,
			1.5,
			0.46,
			"bottom",
			{ relief = true }
		),
		-- footwear: boot tops under the trouser hems
		B("LegL", "footwear", "BootTop_L", -0.88, 0.4, -0.5, -0.12, 0.5, 0.37, "shoe"),
		B("LegR", "footwear", "BootTop_R", 0.12, 0.4, -0.5, 0.88, 0.5, 0.37, "shoe"),
		-- accessory: red waist sash with a tail
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
		-- props: the beach umbrella in his right hand, pole just outside the hat brim, canopy
		-- overhead. `uprightProp` above keeps it vertical while the hand moves.
		B("Prop", "props", "UmbrellaPole", 1.62, 1.5, -0.08, 1.78, 6.2, 0.08, "prop2"),
		B(
			"Prop",
			"props",
			"UmbrellaCanopy",
			0.15,
			6.2,
			-1.6,
			3.25,
			6.5,
			1.6,
			"prop",
			{ relief = true }
		),
		B("Prop", "props", "UmbrellaStripe", 0.15, 6.22, -0.4, 3.25, 6.52, 0.4, "glow"),
		B("Prop", "props", "UmbrellaTop", 1.53, 6.5, -0.17, 1.87, 6.7, 0.17, "prop2"),
	})),
})
