--!strict
-- Plodder kit: stocky, wide-skirted elder with a bun hat and a raised prop.
-- Shared by every region (palette-swapped). Boxes only, faces -Z, ground y = 0, height ~5.6.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local K = require(ReplicatedStorage.Shared.Utility.VillagerKitBuilder)
local B = K.Box

local left = {
	B("Shoe_L", -0.95, 0, -0.8, -0.2, 0.35, 0.35, "shoe", { relief = true }),
	B("Arm_L", -1.75, 2.2, -0.35, -1.25, 3.55, 0.35, "cloth2", { relief = true, group = "ArmL" }),
	B("Hand_L", -1.75, 1.85, -0.35, -1.25, 2.2, 0.35, "skin", { group = "ArmL" }),
	B("Cheek_L", -1.2, 4.0, -0.7, -1.05, 4.5, 0.4, "skin2"),
}

local boxes = {
	B("Skirt", -1.35, 0.35, -0.95, 1.35, 1.9, 0.95, "cloth", { relief = true }),
	B("SkirtHem", -1.4, 0.35, -1.0, 1.4, 0.55, 1.0, "trim", { relief = true }),
	B("Body", -1.25, 1.9, -0.75, 1.25, 3.6, 0.75, "cloth", { relief = true }),
	B("Apron", -0.8, 0.6, -1.02, 0.8, 2.9, -0.95, "cloth3", { relief = true }),
	B("ApronPocketGlow", -0.35, 1.3, -1.06, 0.35, 1.6, -1.02, "glow"),
	B("Shawl", -1.3, 3.2, -0.8, 1.3, 3.6, 0.8, "trim", { relief = true }),
	B("Neck", -0.3, 3.6, -0.3, 0.3, 3.75, 0.3, "skin"),
	B("Head", -1.05, 3.75, -0.85, 1.05, 5.0, 0.9, "skin"),
	B("Nose", -0.17, 4.02, -1.1, 0.17, 4.3, -0.85, "skin2"),
	B("Mouth", -0.45, 3.78, -0.89, 0.45, 4.0, -0.85, "Protected", { color = "#3A0F12" }),
	B("Tongue", -0.22, 3.78, -0.9, 0.22, 3.87, -0.89, "Protected", { color = "#FF6F7D" }),
	B("Hair", -1.1, 4.95, -0.9, 1.1, 5.2, 0.95, "hair", { relief = true }),
	B("HairBack", -1.1, 3.9, 0.9, 1.1, 5.2, 1.05, "hair", { relief = true }),
	-- Bun hat / headscarf (thrown in the tantrum).
	B("Bun", -0.5, 5.2, -0.3, 0.5, 5.65, 0.6, "hat", { relief = true, group = "Hat" }),
	B("BunPin", -0.6, 5.35, 0.05, 0.6, 5.45, 0.15, "glow", { group = "Hat" }),
	-- Raised prop (regional; Forest = rolling pin), right hand.
	B("PropHandle", 1.35, 1.9, -0.12, 1.65, 2.6, 0.12, "prop2", { group = "Prop" }),
	B("PropBody", 1.2, 2.6, -0.3, 1.8, 4.2, 0.3, "prop", { relief = true, group = "Prop" }),
	B("PropTip", 1.35, 4.2, -0.12, 1.65, 4.6, 0.12, "prop2", { group = "Prop" }),
}
for _, item in left do
	table.insert(boxes, item)
end
for _, item in K.Mirror(left) do
	table.insert(boxes, item)
end
for _, cx in { -0.5, 0.5 } do
	for _, item in K.Eye(cx, 4.5, -0.85, 0.76, 0.84, "Ocean") do
		table.insert(boxes, item)
	end
end

-- Regional variants (CP-B). Each hides the Forest bun/rolling pin and adds its own details.
local FOREST_PROPS = { "Bun", "BunPin", "PropHandle", "PropBody", "PropTip" }

local variants = {
	-- Orso Brodo: polar bear snout and ears, a steaming soup pot (CP-C).
	PolarBear = {
		hide = {
			"Bun",
			"BunPin",
			"Nose",
			"Hair",
			"Cheek_L",
			"Cheek_R",
			"PropHandle",
			"PropBody",
			"PropTip",
		},
		add = {
			B("Snout", -0.3, 3.98, -1.2, 0.3, 4.22, -0.85, "skin2"),
			B("SnoutNose", -0.14, 4.1, -1.27, 0.14, 4.24, -1.2, "trim"),
			B("Ear_L", -1.0, 4.95, -0.2, -0.6, 5.4, 0.2, "skin", { relief = true }),
			B("Ear_R", 0.6, 4.95, -0.2, 1.0, 5.4, 0.2, "skin", { relief = true }),
			B("Pot", 1.15, 1.6, -0.7, 2.15, 2.6, 0.6, "prop", { relief = true, group = "Prop" }),
			B("PotRim", 1.1, 2.6, -0.75, 2.2, 2.68, 0.65, "prop2", { group = "Prop" }),
			B("Soup", 1.25, 2.68, -0.6, 2.05, 2.74, 0.5, "glow", { group = "Prop" }),
			B("Ladle", 1.5, 2.7, -0.1, 1.6, 3.6, 0.0, "trim", { group = "Prop" }),
		},
	},
	-- Mamma Magma: rock-lump bun, glowing lava crack, ladle (CP-C).
	Rock = {
		hide = FOREST_PROPS,
		add = {
			B("Lump1", -0.9, 5.0, -0.6, 0.0, 5.5, 0.5, "hat", { relief = true, group = "Hat" }),
			B("Lump2", 0.0, 5.0, -0.3, 0.7, 5.7, 0.6, "hat2", { relief = true, group = "Hat" }),
			B("LavaCrack", -1.36, 0.9, -0.97, 1.36, 1.0, 0.97, "glow"),
			B("RockShoulder_L", -1.45, 3.4, -0.6, -0.9, 3.8, 0.6, "trim", { relief = true }),
			B("RockShoulder_R", 0.9, 3.4, -0.6, 1.45, 3.8, 0.6, "trim", { relief = true }),
			B("LadleHandle", 1.4, 1.9, -0.08, 1.6, 4.4, 0.08, "prop2", { group = "Prop" }),
			B("LadleBowl", 1.25, 4.4, -0.45, 1.75, 4.7, 0.2, "prop", { group = "Prop" }),
			B("LavaDrop", 1.38, 4.7, -0.35, 1.62, 4.78, 0.1, "glow", { group = "Prop" }),
		},
	},
	-- Errore 404: a walking cardboard box with an error panel (CP-C).
	Box = {
		hide = {
			"Skirt",
			"SkirtHem",
			"Body",
			"Apron",
			"ApronPocketGlow",
			"Shawl",
			"Neck",
			"Head",
			"Nose",
			"Hair",
			"HairBack",
			"Cheek_L",
			"Cheek_R",
			"Bun",
			"BunPin",
			"PropHandle",
			"PropBody",
			"PropTip",
		},
		add = {
			B("BoxBody", -1.3, 0.6, -0.84, 1.3, 4.95, 0.9, "cloth", { relief = true }),
			B("Tape", -0.18, 0.6, -0.86, 0.18, 4.95, -0.84, "cloth3"),
			B("Flap_L", -1.5, 4.95, -0.84, -1.3, 5.6, 0.9, "cloth2", { group = "Hat" }),
			B("Flap_R", 1.3, 4.95, -0.84, 1.5, 5.6, 0.9, "cloth2", { group = "Hat" }),
			B("ErrorPanel", -0.75, 1.3, -0.9, 0.75, 2.5, -0.85, "glow"),
			B("Glyph4a", -0.6, 1.5, -0.93, -0.38, 2.3, -0.9, "Protected", { color = "#1A0B06" }),
			B("Glyph0", -0.11, 1.5, -0.93, 0.11, 2.3, -0.9, "Protected", { color = "#1A0B06" }),
			B("Glyph4b", 0.38, 1.5, -0.93, 0.6, 2.3, -0.9, "Protected", { color = "#1A0B06" }),
			B("Leg_L", -0.85, 0.35, -0.25, -0.35, 0.6, 0.25, "shoe"),
			B("Leg_R", 0.35, 0.35, -0.25, 0.85, 0.6, 0.25, "shoe"),
		},
	},

	-- Zio Sabbia: sun hat, sandy beard, raised beach umbrella.
	Umbrella = {
		hide = FOREST_PROPS,
		add = {
			B(
				"HatBrim",
				-1.45,
				5.2,
				-1.35,
				1.45,
				5.32,
				1.35,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B(
				"HatCrown",
				-0.8,
				5.32,
				-0.7,
				0.8,
				5.75,
				0.75,
				"hat2",
				{ relief = true, group = "Hat" }
			),
			B("HatBandGlow", -0.82, 5.32, -0.72, 0.82, 5.42, 0.77, "glow", { group = "Hat" }),
			B("Beard", -0.8, 3.3, -0.96, 0.8, 3.77, -0.86, "hair", { relief = true }),
			B("Pole", 1.45, 1.9, -0.08, 1.6, 6.4, 0.08, "prop2", { group = "Prop" }),
			B("Canopy", 0.0, 6.4, -1.6, 3.1, 6.7, 1.6, "prop", { relief = true, group = "Prop" }),
			B("CanopyStripe", 0.0, 6.42, -0.4, 3.1, 6.72, 0.4, "glow", { group = "Prop" }),
			B("CanopyTop", 1.35, 6.7, -0.15, 1.7, 6.9, 0.15, "prop2", { group = "Prop" }),
		},
	},
	-- Pescatore Pozzo: bucket hat, dragging a fishing net.
	Fisher = {
		hide = FOREST_PROPS,
		add = {
			B("Bucket", -1.15, 5.0, -1.0, 1.15, 5.5, 1.0, "hat", { relief = true, group = "Hat" }),
			B(
				"BucketBrim",
				-1.35,
				5.0,
				-1.2,
				1.35,
				5.1,
				1.2,
				"hat2",
				{ relief = true, group = "Hat" }
			),
			B("Lure", 0.7, 5.15, -1.22, 0.95, 5.4, -1.15, "glow", { group = "Hat" }),
			B("NetPole", 1.4, 1.9, -0.1, 1.6, 4.8, 0.1, "prop2", { group = "Prop" }),
			B("NetHoop", 1.3, 4.8, -0.8, 1.7, 4.95, 0.8, "prop", { group = "Prop" }),
			B("NetBag", 1.35, 3.9, -0.7, 1.65, 4.8, 0.7, "prop", { relief = true, group = "Prop" }),
			B("NetFloat", 1.3, 4.5, -0.95, 1.7, 4.75, -0.8, "glow", { group = "Prop" }),
		},
	},
	-- Tucano Toto: big toucan beak, crest, tail feathers, a sack of mangoes.
	Toucan = {
		hide = { "Bun", "BunPin", "Nose", "Hair", "PropHandle", "PropBody", "PropTip" },
		add = {
			B("Beak", -0.32, 4.0, -2.2, 0.32, 4.5, -0.85, "skin2", { relief = true }),
			B("BeakStripe", -0.33, 4.3, -2.2, 0.33, 4.4, -0.85, "glow"),
			B("BeakTip", -0.32, 4.0, -2.4, 0.32, 4.32, -2.2, "trim"),
			B("Crest", -0.2, 5.0, -0.4, 0.2, 5.45, 0.5, "hair", { relief = true, group = "Hat" }),
			B("TailFeathers", -0.45, 1.0, 0.95, 0.45, 2.4, 1.35, "cloth2", { relief = true }),
			B("Sack", 1.25, 1.2, -0.6, 2.05, 2.4, 0.5, "prop", { relief = true, group = "Prop" }),
			B("SackTie", 1.45, 2.4, -0.2, 1.85, 2.6, 0.1, "prop2", { group = "Prop" }),
			B(
				"Mango1",
				1.4,
				2.55,
				-0.4,
				1.8,
				2.95,
				0.0,
				"Protected",
				{ color = "#FF9F1C", group = "Prop" }
			),
			B(
				"Mango2",
				1.62,
				2.5,
				0.0,
				1.98,
				2.86,
				0.36,
				"Protected",
				{ color = "#FFD447", group = "Prop" }
			),
		},
	},
}

return table.freeze({
	id = "Plodder",
	version = 2,
	boxes = table.freeze(boxes),
	variants = table.freeze(variants),
	tantrum = "StompHatThrow",
})
