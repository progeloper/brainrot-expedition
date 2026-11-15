--!strict
-- Swamp outfit set: Mekong Delta áo bà ba work clothes.
-- Reference card: docs/villagers/Swamp_outfit_reference.md. Every outfit colour must come from `palette` below (cleaned
-- reference colours). The region glow sits on ONE trim line; prop glows are allowed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local K = require(ReplicatedStorage.Shared.Utility.VillagerKitBuilder)
local B = K.Box

local function tagged(slot: string, list: { any }): { any }
	for _, item in list do
		item.outfit = slot
	end
	return list
end
local function joined(...): { any }
	local out = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end
local function mirrored(list: { any }): { any }
	return joined(list, K.Mirror(list))
end

-- Khăn rằn checkered scarf at a given neck height (white ground, black checks).
local function scarf(y0: number, y1: number, half: number, front: number): { any }
	return {
		B("Scarf", -half, y0, front, half, y1, -front, "acc"),
		B("ScarfCheck1", -half, y0, front - 0.04, -half + 0.3, y1, front, "acc2"),
		B("ScarfCheck2", -0.05, y0, front - 0.04, 0.25, y1, front, "acc2"),
		B("ScarfTail", 0.3, y0 - 0.5, front - 0.04, 0.55, y0, front + 0.02, "acc"),
		B("ScarfTailCheck", 0.3, y0 - 0.5, front - 0.07, 0.55, y0 - 0.3, front - 0.04, "acc2"),
	}
end

-- Frogs (Sprinter / Frog): nón lá worn on the back so the eye bumps stay readable.
local sprinter = {
	name = "Mekong Delta áo bà ba work clothes",
	hide = {
		"EyeBumpRing_L",
		"EyeBumpRing_R",
		"BuckleGlow",
		"ShoeStripe_L",
		"ShoeStripe_R",
		"Belly",
		"Shirt",
		"Belt",
		"SneakerSole_L",
		"SneakerSole_R",
		"Leg_L",
		"Leg_R",
		"Shoe_L",
		"Shoe_R",
	},
	add = joined(
		tagged("headwear", {
			B("NonLa1", -1.25, 2.5, 0.6, 1.25, 4.6, 0.72, "hat", { relief = true, group = "Hat" }),
			B("NonLa2", -0.95, 2.8, 0.72, 0.95, 4.3, 0.86, "hat", { relief = true, group = "Hat" }),
			B("NonLa3", -0.62, 3.1, 0.86, 0.62, 4.0, 1.0, "hat", { group = "Hat" }),
			B("NonLaTip", -0.28, 3.4, 1.0, 0.28, 3.7, 1.12, "hat", { group = "Hat" }),
			B("NonLaStrap", -0.55, 3.88, -0.42, 0.55, 3.98, 0.62, "glow", { group = "Hat" }),
		}),
		tagged("top", {
			B("AoHem", -1.04, 1.95, -0.59, 1.04, 2.15, 0.59, "top"),
			B("AoPlacket", -0.08, 2.15, -0.6, 0.08, 3.85, -0.56, "top"),
		}),
		tagged(
			"bottom",
			mirrored({
				B("Trouser_L", -0.78, 0.75, -0.33, -0.22, 2.0, 0.33, "bottom", { relief = true }),
			})
		),
		mirrored({
			B("Shin_L", -0.72, 0.12, -0.28, -0.28, 0.75, 0.28, "skin"),
			B("Foot_L", -0.8, 0.1, -0.75, -0.2, 0.25, 0.4, "skin"),
		}),
		tagged(
			"footwear",
			mirrored({
				B("Sandal_L", -0.86, 0, -0.8, -0.14, 0.1, 0.45, "shoe"),
				B("SandalStrap_L", -0.82, 0.1, -0.5, -0.18, 0.2, -0.4, "shoe"),
			})
		),
		tagged("accessory", scarf(3.82, 4.02, 0.6, -0.62))
	),
	outfitRoles = { "hat", "cloth", "top", "bottom", "shoe", "acc", "acc2" },
}

-- Fishermen (Plodder / Fisher): nón lá on the head, net kept as a prop.
local plodder = {
	name = "Mekong Delta áo bà ba work clothes (fisherman)",
	hide = {
		"Bucket",
		"BucketBrim",
		"Lure",
		"Skirt",
		"SkirtHem",
		"Apron",
		"ApronPocketGlow",
		"Shawl",
		"Shoe_L",
		"Shoe_R",
	},
	add = joined(
		tagged("headwear", {
			B(
				"NonLaBrim",
				-1.35,
				5.0,
				-1.3,
				1.35,
				5.1,
				1.3,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("NonLa2", -1.0, 5.1, -0.95, 1.0, 5.3, 0.95, "hat", { relief = true, group = "Hat" }),
			B("NonLa3", -0.65, 5.3, -0.6, 0.65, 5.5, 0.6, "hat", { group = "Hat" }),
			B("NonLaTip", -0.3, 5.5, -0.28, 0.3, 5.7, 0.28, "hat", { group = "Hat" }),
			B("NonLaStrap", -1.07, 3.72, -0.6, 1.07, 3.8, 0.6, "glow", { group = "Hat" }),
		}),
		tagged("top", {
			B("AoPlacket", -0.08, 2.0, -0.79, 0.08, 3.55, -0.75, "top"),
			B("AoHem", -1.28, 1.75, -0.78, 1.28, 1.95, 0.78, "top"),
		}),
		tagged(
			"bottom",
			mirrored({
				B("Trouser_L", -1.2, 0.45, -0.6, -0.1, 1.85, 0.6, "bottom", { relief = true }),
			})
		),
		mirrored({ B("Shin_L", -0.9, 0.1, -0.3, -0.3, 0.45, 0.3, "skin") }),
		tagged(
			"footwear",
			mirrored({
				B("Sandal_L", -0.95, 0, -0.8, -0.2, 0.1, 0.35, "shoe"),
				B("SandalStrap_L", -0.9, 0.1, -0.5, -0.25, 0.18, -0.4, "shoe"),
			})
		),
		tagged("accessory", scarf(3.55, 3.75, 0.55, -0.6))
	),
	outfitRoles = { "hat", "cloth", "cloth2", "top", "bottom", "shoe", "acc", "acc2" },
}

-- Snail (Shouter / Snail): nón lá on the head with stalks poking out; lantern stays a prop.
local shouter = {
	name = "Mekong Delta áo bà ba work clothes (snail)",
	hide = { "LanternGlow", "BadgeGlow", "Leg_L", "Leg_R", "Foot_L", "Foot_R" },
	add = joined(
		tagged("headwear", {
			B(
				"NonLaBrim",
				-1.3,
				4.2,
				-1.25,
				1.3,
				4.3,
				1.25,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("NonLa2", -0.95, 4.3, -0.9, 0.95, 4.5, 0.9, "hat", { relief = true, group = "Hat" }),
			B("NonLa3", -0.6, 4.5, -0.55, 0.6, 4.7, 0.55, "hat", { group = "Hat" }),
			B("NonLaTip", -0.25, 4.7, -0.22, 0.25, 4.9, 0.22, "hat", { group = "Hat" }),
			B("NonLaStrap", -1.32, 4.14, -1.27, 1.32, 4.2, 1.27, "glow", { group = "Hat" }),
		}),
		{ B("LanternGlowProp", -1.28, 2.7, 1.55, 1.28, 3.3, 1.95, "glow", { group = "Prop" }) },
		tagged("top", { B("AoBody", -1.34, 1.0, -1.04, 1.34, 2.5, 1.04, "top", { relief = true }) }),
		tagged("bottom", { B("Trousers", -0.85, 0.3, -0.4, 0.85, 0.85, 0.4, "bottom") }),
		mirrored({ B("FootSkin_L", -0.8, 0.1, -0.75, -0.3, 0.3, 0.25, "skin") }),
		tagged("footwear", mirrored({ B("Sandal_L", -0.85, 0, -0.85, -0.25, 0.1, 0.3, "shoe") })),
		tagged("accessory", {
			B("Scarf", -1.0, 2.4, -1.13, 1.0, 2.5, -1.08, "acc"),
			B("ScarfCheck1", -0.5, 2.4, -1.15, -0.2, 2.5, -1.13, "acc2"),
			B("ScarfCheck2", 0.2, 2.4, -1.15, 0.5, 2.5, -1.13, "acc2"),
			B("ScarfTail", 0.6, 1.9, -1.15, 0.85, 2.4, -1.1, "acc"),
		})
	),
	outfitRoles = { "hat", "top", "bottom", "shoe", "acc", "acc2" },
}

return table.freeze({
	set = "Swamp",
	regionId = "REGION_SWAMP",
	reference = "docs/villagers/Swamp_outfit_reference.md",
	palette = table.freeze({
		AoBlack = "#1D2133",
		AoBrown = "#6B4630",
		PalmStraw = "#E6D49E",
		ScarfWhite = "#F7F5FC",
		ScarfBlack = "#1D2133",
		SandalBrown = "#7A5530",
	}),
	glow = "#14C79F",
	outfits = table.freeze({
		["Sprinter"] = sprinter,
		["Plodder"] = plodder,
		["Shouter"] = shouter,
	}),
})
