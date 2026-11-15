--!strict
-- Sprinter kit: lanky runner in a work cap. Shared by every region (palette-swapped).
-- Boxes only, studs, y up, faces -Z, ground y = 0. Height ~5.7 (1.1x the 5.16 reference avatar).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local K = require(ReplicatedStorage.Shared.Utility.VillagerKitBuilder)
local B = K.Box

local left = {
	B("Shoe_L", -0.85, 0, -0.75, -0.15, 0.4, 0.4, "shoe", { relief = true }),
	B("ShoeStripe_L", -0.87, 0.12, -0.77, -0.13, 0.22, 0.2, "glow"),
	B("Leg_L", -0.75, 0.4, -0.3, -0.25, 2.1, 0.3, "cloth2", { relief = true }),
	B("Arm_L", -1.5, 2.35, -0.3, -1.0, 3.75, 0.3, "cloth", { relief = true, group = "ArmL" }),
	B("Hand_L", -1.5, 1.95, -0.3, -1.0, 2.35, 0.3, "skin", { group = "ArmL" }),
	B("Hair_L", -1.15, 4.35, -0.4, -1.02, 5.35, 0.95, "hair", { relief = true }),
}

local boxes = {
	B("Body", -1.0, 2.1, -0.55, 1.0, 3.9, 0.55, "cloth", { relief = true }),
	B("Belt", -1.04, 2.1, -0.59, 1.04, 2.35, 0.59, "trim", { relief = true }),
	B("BuckleGlow", -0.2, 2.13, -0.64, 0.2, 2.32, -0.58, "glow"),
	B("Shirt", -0.45, 2.9, -0.6, 0.45, 3.9, -0.55, "cloth3", { relief = true }),
	B("Neck", -0.3, 3.9, -0.3, 0.3, 4.05, 0.3, "skin"),
	B("Head", -1.02, 4.05, -0.95, 1.02, 5.35, 0.95, "skin"),
	B("Nose", -0.15, 4.36, -1.18, 0.15, 4.62, -0.95, "skin2"),
	B("Mouth", -0.42, 4.08, -0.99, 0.42, 4.32, -0.95, "Protected", { color = "#3A0F12" }),
	B("Tongue", -0.22, 4.08, -1.0, 0.22, 4.17, -0.99, "Protected", { color = "#FF6F7D" }),
	B("HairBack", -1.05, 4.6, 0.95, 1.05, 5.35, 1.08, "hair", { relief = true }),
	-- Cap (thrown in the tantrum).
	B("Cap", -1.08, 5.35, -0.98, 1.08, 5.75, 1.0, "hat", { relief = true, group = "Hat" }),
	B("CapBand", -1.1, 5.35, -1.0, 1.1, 5.47, 1.02, "glow", { group = "Hat" }),
	B("CapBrim", -0.95, 5.35, -1.5, 0.95, 5.45, -0.98, "hat2", { relief = true, group = "Hat" }),
	-- Held prop (regional; Forest = breadstick axe), right hand.
	B("PropHandle", 1.1, 1.3, -0.16, 1.4, 3.1, 0.16, "prop", { relief = true, group = "Prop" }),
	B("PropHead", 1.05, 2.75, -0.95, 1.45, 3.35, -0.16, "prop2", { relief = true, group = "Prop" }),
	B("PropEdge", 1.08, 2.8, -1.08, 1.42, 3.3, -0.95, "glow", { group = "Prop" }),
}
for _, item in left do
	table.insert(boxes, item)
end
for _, item in K.Mirror(left) do
	table.insert(boxes, item)
end
for _, cx in { -0.5, 0.5 } do
	for _, item in K.Eye(cx, 4.87, -0.95, 0.78, 0.86, "Amber") do
		table.insert(boxes, item)
	end
end

-- Regional variants (CP-B). Each hides the Forest cap/axe and adds its own details.
local function withMirror(list)
	local out = table.clone(list)
	for _, item in K.Mirror(list) do
		table.insert(out, item)
	end
	return out
end
local FOREST_PROPS = { "Cap", "CapBand", "CapBrim", "PropHandle", "PropHead", "PropEdge" }

local lifeguardAdd = {
	B("HairTop", -1.04, 5.47, -0.9, 1.04, 5.65, 0.95, "hair", { relief = true }),
	B("VisorBand", -1.08, 5.32, -1.0, 1.08, 5.47, 1.0, "hat", { group = "Hat" }),
	B("VisorBrim", -0.9, 5.32, -1.6, 0.9, 5.42, -1.0, "hat2", { relief = true, group = "Hat" }),
	B("Lanyard_L", -0.5, 3.3, -0.64, -0.4, 3.9, -0.58, "trim"),
	B("Lanyard_R", 0.4, 3.3, -0.64, 0.5, 3.9, -0.58, "trim"),
	B("Whistle", -0.25, 3.0, -0.78, 0.25, 3.32, -0.6, "glow"),
	B("RescueTube", 1.1, 1.4, -0.75, 1.5, 3.0, 0.75, "prop", { relief = true, group = "Prop" }),
	B("RescueTubeBand", 1.08, 2.05, -0.77, 1.52, 2.35, 0.77, "prop2", { group = "Prop" }),
}

local frogAdd = withMirror({
	B("EyeBump_L", -0.95, 5.35, -0.75, -0.25, 5.85, 0.1, "skin", { relief = true }),
	B("EyeBumpRing_L", -0.97, 5.6, -0.77, -0.23, 5.68, 0.12, "glow"),
	B("SneakerSole_L", -0.88, 0, -0.82, -0.12, 0.12, 0.45, "cloth3"),
	B("Webbing_L", -1.52, 1.85, -0.42, -0.98, 1.95, 0.42, "skin2"),
})
table.insert(frogAdd, B("Lip", -0.9, 4.04, -0.99, 0.9, 4.08, -0.96, "skin2"))
table.insert(frogAdd, B("Belly", -0.6, 2.4, -0.62, 0.6, 3.3, -0.58, "cloth3", { relief = true }))

local monkeyAdd = withMirror({
	B("Ear_L", -1.45, 4.4, -0.2, -1.02, 5.0, 0.3, "skin2"),
})
for _, item in
	{
		B("Tuft", -0.3, 5.35, -0.3, 0.3, 5.7, 0.3, "hair", { relief = true }),
		B("Tail1", -0.15, 2.2, 0.55, 0.15, 2.5, 1.6, "hair"),
		B("Tail2", -0.15, 2.5, 1.35, 0.15, 3.6, 1.65, "hair"),
		B("Tail3", -0.15, 3.35, 0.95, 0.15, 3.65, 1.4, "hair"),
		B("Noodle1", 1.15, 0.6, -0.1, 1.35, 2.3, 0.1, "prop", { group = "Prop" }),
		B("Noodle2", 1.15, 0.5, -0.7, 1.35, 0.7, 0.1, "prop", { group = "Prop" }),
		B("Noodle3", 1.15, 0.5, -0.9, 1.35, 1.2, -0.7, "prop", { group = "Prop" }),
		B("Meatball", 1.05, 1.15, -1.05, 1.45, 1.5, -0.65, "prop2", { group = "Prop" }),
		B("NoodleGlow", 1.12, 2.2, -0.15, 1.38, 2.4, 0.15, "glow", { group = "Prop" }),
	}
do
	table.insert(monkeyAdd, item)
end

local variants = {
	-- Pinguino Pattino: beak, white belly, scarf, beanie, skate blades (CP-C).
	Penguin = {
		hide = {
			"Cap",
			"CapBand",
			"CapBrim",
			"Nose",
			"HairBack",
			"Hair_L",
			"Hair_R",
			"PropHandle",
			"PropHead",
			"PropEdge",
		},
		add = withMirror({
			B("Blade_L", -0.6, 0, -0.95, -0.4, 0.12, 0.55, "glow"),
		}),
	},
	-- Lavoratore Lava: miner's helmet with a glowing lamp, pickaxe (CP-C).
	Miner = {
		hide = FOREST_PROPS,
		add = {
			B(
				"HelmetDome",
				-1.1,
				5.35,
				-1.0,
				1.1,
				5.75,
				1.0,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("HelmetBrim", -1.2, 5.32, -1.25, 1.2, 5.4, 1.15, "hat2", { group = "Hat" }),
			B("Lamp", -0.3, 5.42, -1.22, 0.3, 5.7, -1.0, "glow", { group = "Hat" }),
			B("PickHandle", 1.1, 1.3, -0.16, 1.4, 3.2, 0.16, "prop2", { group = "Prop" }),
			B(
				"PickHead",
				1.05,
				3.2,
				-1.1,
				1.45,
				3.45,
				0.7,
				"prop",
				{ relief = true, group = "Prop" }
			),
			B("PickTip", 1.08, 3.15, -1.25, 1.42, 3.5, -1.1, "glow", { group = "Prop" }),
		},
	},
	-- Pixel Pino: glitch shards and a pixel headband; the client flickers him (CP-C).
	Glitch = {
		hide = FOREST_PROPS,
		add = {
			B("PixelBand", -1.06, 5.32, -0.99, 1.06, 5.47, 1.0, "hat", { group = "Hat" }),
			B("PixelSpike1", -0.8, 5.47, -0.3, -0.4, 5.75, 0.1, "hat2", { group = "Hat" }),
			B("PixelSpike2", 0.1, 5.47, -0.1, 0.5, 5.85, 0.3, "glow", { group = "Hat" }),
			B("Shard1", -1.35, 3.0, -0.45, -1.05, 3.3, -0.15, "glow"),
			B("Shard2", 1.05, 4.6, -0.55, 1.3, 4.85, -0.25, "glow"),
			B("Shard3", 0.55, 1.0, -0.5, 0.85, 1.3, -0.2, "glow"),
			B("Cursor", 1.1, 2.0, -0.2, 1.5, 2.7, 0.2, "prop", { group = "Prop" }),
		},
	},

	Lifeguard = { hide = FOREST_PROPS, add = lifeguardAdd },
	Frog = {
		hide = {
			"Cap",
			"CapBand",
			"CapBrim",
			"Nose",
			"HairBack",
			"Hair_L",
			"Hair_R",
			"PropHandle",
			"PropHead",
			"PropEdge",
		},
		add = frogAdd,
	},
	Monkey = { hide = FOREST_PROPS, add = monkeyAdd },
}

for _, item in
	{
		B("Beak", -0.25, 4.3, -1.4, 0.25, 4.55, -0.95, "skin2"),
		B("BellyWhite", -0.7, 2.35, -0.63, 0.7, 3.85, -0.56, "cloth3", { relief = true }),
		B("Scarf", -1.05, 3.85, -0.62, 1.05, 4.08, 0.62, "prop", { relief = true }),
		B("ScarfTail", 0.45, 3.1, -0.68, 0.8, 3.85, -0.6, "prop"),
		B("Beanie", -1.05, 5.35, -0.95, 1.05, 5.65, 0.95, "hat", { relief = true, group = "Hat" }),
		B("Pompom", -0.2, 5.65, -0.2, 0.2, 5.9, 0.2, "glow", { group = "Hat" }),
	}
do
	table.insert(variants.Penguin.add, item)
end

return table.freeze({
	id = "Sprinter",
	version = 2,
	boxes = table.freeze(boxes),
	variants = table.freeze(variants),
	tantrum = "WhistleFlail",
})
