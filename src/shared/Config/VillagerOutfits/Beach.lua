--!strict
-- Beach outfit set: southern Italian fishing-village work dress.
-- Reference card: docs/villagers/Beach_outfit_reference.md. Every outfit colour must come from `palette` below (cleaned
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

-- Fisherman's work dress on the Sprinter / Lifeguard body.
local sprinter = {
	name = "Southern Italian fisherman's work dress",
	hide = {
		"VisorBand",
		"VisorBrim",
		"Whistle",
		"BuckleGlow",
		"ShoeStripe_L",
		"ShoeStripe_R",
		"Leg_L",
		"Leg_R",
		"Shirt",
		"Belt",
	},
	add = joined(
		tagged("headwear", {
			B(
				"KnitCap",
				-1.06,
				5.32,
				-0.98,
				1.06,
				5.62,
				1.0,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("KnitCapTop", -0.7, 5.62, -0.6, 0.7, 5.85, 0.6, "hat", { group = "Hat" }),
			B("KnitCapBand", -1.08, 5.32, -1.0, 1.08, 5.42, 1.02, "glow", { group = "Hat" }),
		}),
		tagged("top", {
			B("BlouseCollar", -0.6, 3.75, -0.62, 0.6, 3.92, -0.56, "top"),
			B("BlousePlacket", -0.1, 2.4, -0.61, 0.1, 3.75, -0.56, "top"),
		}),
		tagged(
			"bottom",
			mirrored({
				B("Breeches_L", -0.78, 1.0, -0.33, -0.22, 2.12, 0.33, "bottom", { relief = true }),
			})
		),
		mirrored({ B("Shin_L", -0.72, 0.4, -0.28, -0.28, 1.0, 0.28, "skin") }),
		tagged(
			"footwear",
			mirrored({
				B("BootLeg_L", -0.8, 0.4, -0.36, -0.2, 0.85, 0.36, "shoe"),
			})
		),
		tagged("accessory", {
			B("WaistSash", -1.05, 2.05, -0.6, 1.05, 2.4, 0.6, "acc", { relief = true }),
			B("WaistSashTail", 0.55, 1.5, -0.64, 0.8, 2.05, -0.58, "acc"),
		}),
		{ B("WhistleProp", -0.25, 3.0, -0.78, 0.25, 3.32, -0.6, "prop", { group = "Prop" }) }
	),
	outfitRoles = { "hat", "cloth", "top", "bottom", "shoe", "acc", "trim" },
}

-- Older fishermen on the Plodder / Umbrella body (trousers replace the skirt).
local plodder = {
	name = "Southern Italian fisherman's work dress (older men)",
	hide = {
		"Skirt",
		"SkirtHem",
		"Apron",
		"ApronPocketGlow",
		"Shawl",
		"HatBrim",
		"HatCrown",
		"HatBandGlow",
	},
	add = joined(
		tagged("headwear", {
			B("StrawBrim", -1.45, 5.2, -1.35, 1.45, 5.3, 1.35, "hat", { group = "Hat" }),
			B(
				"StrawCrown",
				-0.8,
				5.3,
				-0.7,
				0.8,
				5.75,
				0.75,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("StrawBand", -0.82, 5.3, -0.72, 0.82, 5.4, 0.77, "glow", { group = "Hat" }),
		}),
		tagged("top", {
			B("ShirtCollar", -0.6, 3.45, -0.8, 0.6, 3.62, -0.75, "top"),
			B("ShirtHem", -1.28, 1.75, -0.78, 1.28, 1.95, 0.78, "cloth"),
		}),
		tagged(
			"bottom",
			mirrored({
				B("Trouser_L", -1.2, 0.35, -0.65, -0.1, 1.85, 0.65, "bottom", { relief = true }),
			})
		),
		tagged(
			"footwear",
			mirrored({
				B("BootTop_L", -0.92, 0.3, -0.82, -0.23, 0.45, 0.37, "shoe"),
			})
		),
		tagged("accessory", {
			B("WaistSash", -1.3, 1.85, -0.8, 1.3, 2.15, 0.8, "acc", { relief = true }),
			B("WaistSashTail", 0.7, 1.3, -0.84, 0.95, 1.85, -0.78, "acc"),
		})
	),
	outfitRoles = { "hat", "cloth", "cloth2", "top", "bottom", "shoe", "acc" },
}

-- Crab (Shouter / Crab): cap between the eye stalks, vest, shorts, boots, sash.
local shouter = {
	name = "Southern Italian fisherman's work dress (crab)",
	hide = { "BadgeGlow", "Leg_L", "Leg_R" },
	add = joined(
		tagged("headwear", {
			B("KnitCap", -0.45, 4.2, -0.4, 0.45, 4.5, 0.4, "hat", { relief = true, group = "Hat" }),
			B("KnitCapTop", -0.3, 4.5, -0.28, 0.3, 4.7, 0.28, "hat", { group = "Hat" }),
			B("KnitCapBand", -0.47, 4.2, -0.42, 0.47, 4.28, 0.42, "glow", { group = "Hat" }),
		}),
		tagged(
			"top",
			{ B("WorkVest", -1.34, 1.0, -1.04, 1.34, 2.5, 1.04, "top", { relief = true }) }
		),
		tagged("bottom", { B("Shorts", -0.85, 0.45, -0.4, 0.85, 0.85, 0.4, "bottom") }),
		tagged(
			"footwear",
			mirrored({ B("BootTop_L", -0.75, 0.25, -0.25, -0.35, 0.45, 0.25, "shoe") })
		),
		tagged("accessory", {
			B("WaistSash", -1.36, 2.3, -1.06, 1.36, 2.5, 1.06, "acc"),
			B("WaistSashTail", 0.9, 1.7, -1.14, 1.15, 2.3, -1.09, "acc"),
		})
	),
	outfitRoles = { "hat", "top", "bottom", "shoe", "acc" },
}

return table.freeze({
	set = "Beach",
	regionId = "REGION_BEACH",
	reference = "docs/villagers/Beach_outfit_reference.md",
	palette = table.freeze({
		CapRed = "#D23A30",
		LinenWhite = "#F7F5FC",
		CanvasTan = "#D8C08E",
		SailorBlue = "#3460A8",
		StrawGold = "#E8C46A",
		BootDark = "#1D2133",
		BootBrown = "#6E4528",
	}),
	glow = "#2EE9FF",
	outfits = table.freeze({
		["Sprinter"] = sprinter,
		["Plodder"] = plodder,
		["Shouter"] = shouter,
	}),
})
