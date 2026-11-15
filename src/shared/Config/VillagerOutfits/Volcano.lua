--!strict
-- Volcano outfit set: Andean highland everyday dress (Peru/Ecuador reference).
-- Reference card: docs/villagers/Volcano_outfit_reference.md. Every outfit colour must come from `palette` below (cleaned
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

local function ojotas(x0: number, x1: number, z0: number, z1: number): { any }
	return joined(
		mirrored({ B("Foot_L", x0 + 0.05, 0.1, z0 + 0.05, x1 - 0.05, 0.3, z1 - 0.05, "skin") }),
		tagged(
			"footwear",
			mirrored({
				B("Ojota_L", x0, 0, z0, x1, 0.1, z1, "shoe"),
				B("OjotaStrap_L", x0 + 0.05, 0.1, z0 + 0.3, x1 - 0.05, 0.2, z0 + 0.4, "shoe"),
			})
		)
	)
end

-- Miners (Sprinter / Miner): chullo under the helmet (helmet + lamp are work gear), poncho.
local sprinter = {
	name = "Andean highland work dress (men)",
	hide = {
		"BuckleGlow",
		"ShoeStripe_L",
		"ShoeStripe_R",
		"Leg_L",
		"Leg_R",
		"Shoe_L",
		"Shoe_R",
		"Belt",
		"Shirt",
	},
	add = joined(
		tagged(
			"headwear",
			joined(
				{
					B(
						"ChulloBand",
						-1.06,
						5.1,
						-0.5,
						1.06,
						5.35,
						1.0,
						"chullo",
						{ relief = true, group = "Hat" }
					),
				},
				mirrored({
					B("Earflap_L", -1.12, 4.3, -0.4, -1.02, 5.35, 0.4, "chullo", { group = "Hat" }),
					B(
						"EarTassel_L",
						-1.1,
						3.95,
						-0.1,
						-1.04,
						4.3,
						0.1,
						"chullo2",
						{ group = "Hat" }
					),
				})
			)
		),
		tagged("top", {
			B("Poncho", -1.25, 2.2, -0.75, 1.25, 3.92, 0.75, "top", { relief = true }),
			B("PonchoStripe1", -1.26, 2.6, -0.77, 1.26, 2.7, 0.77, "top2"),
			B("PonchoStripe2", -1.26, 3.0, -0.77, 1.26, 3.1, 0.77, "top3"),
		}),
		tagged(
			"bottom",
			mirrored({
				B("Trouser_L", -0.78, 0.3, -0.33, -0.22, 2.2, 0.33, "bottom", { relief = true }),
			})
		),
		ojotas(-0.86, -0.14, -0.8, 0.45),
		tagged("accessory", {
			B("CarryCloth", -0.7, 2.4, 0.75, 0.7, 3.5, 1.25, "acc", { relief = true }),
			B("CarryKnot", -0.2, 3.7, -0.81, 0.2, 3.9, -0.76, "acc"),
		})
	),
	-- The helmet is safety gear (hat/hat2), not clothing; the chullo is.
	outfitRoles = { "chullo", "chullo2", "cloth", "top", "top2", "top3", "bottom", "shoe", "acc" },
}

-- Women (Plodder / Rock): felt hat, jobona, two-layer pollera (the lava crack glows on it).
local plodder = {
	name = "Andean highland women's dress",
	hide = {
		"Lump1",
		"Lump2",
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
			B("FeltBrim", -1.3, 5.0, -1.2, 1.3, 5.1, 1.2, "hat", { group = "Hat" }),
			B(
				"FeltCrown",
				-0.75,
				5.1,
				-0.65,
				0.75,
				5.45,
				0.7,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("FeltBand", -0.77, 5.1, -0.67, 0.77, 5.18, 0.72, "hat2", { group = "Hat" }),
		}),
		tagged("top", { B("JobonaHem", -1.27, 1.9, -0.77, 1.27, 2.05, 0.77, "cloth") }),
		tagged("bottom", {
			B("Pollera1", -1.35, 0.35, -0.95, 1.35, 1.15, 0.95, "bottom", { relief = true }),
			B("Pollera2", -1.3, 1.15, -0.9, 1.3, 1.9, 0.9, "bottom2", { relief = true }),
		}),
		ojotas(-0.95, -0.2, -0.8, 0.35),
		tagged("accessory", {
			B("Lliclla", -1.32, 3.2, -0.82, 1.32, 3.65, 0.82, "acc", { relief = true }),
			B("LlicllaPin", -0.12, 3.25, -0.86, 0.12, 3.45, -0.82, "acc2"),
			B("Chumpi", -1.33, 1.8, -0.84, 1.33, 1.9, 0.84, "acc2"),
		})
	),
	outfitRoles = { "hat", "hat2", "cloth", "cloth2", "bottom", "bottom2", "shoe", "acc", "acc2" },
}

-- Bell-ringer (Shouter / Bell): chullo with earflaps and tassels, poncho, carrying cloth.
local shouter = {
	name = "Andean highland work dress (bell-ringer)",
	hide = { "Hood", "HoodPoint", "EmberBand", "BadgeGlow", "Leg_L", "Leg_R", "Foot_L", "Foot_R" },
	add = joined(
		tagged(
			"headwear",
			joined(
				{
					B(
						"Chullo",
						-0.95,
						4.2,
						-0.85,
						0.95,
						4.9,
						0.85,
						"hat",
						{ relief = true, group = "Hat" }
					),
					B("ChulloTop", -0.5, 4.9, -0.45, 0.5, 5.35, 0.45, "hat", { group = "Hat" }),
					B("ChulloBand", -0.97, 4.2, -0.87, 0.97, 4.3, 0.87, "glow", { group = "Hat" }),
				},
				mirrored({
					B("Earflap_L", -1.42, 3.4, -0.4, -1.3, 4.25, 0.4, "hat", { group = "Hat" }),
					B("EarTassel_L", -1.4, 3.0, -0.08, -1.32, 3.4, 0.08, "hat2", { group = "Hat" }),
				})
			)
		),
		tagged("top", {
			B("Poncho", -1.4, 1.4, -1.1, 1.4, 2.48, 1.1, "top", { relief = true }),
			B("PonchoStripe", -1.41, 1.8, -1.12, 1.41, 1.9, 1.12, "top2"),
		}),
		tagged("bottom", { B("Trousers", -0.85, 0.12, -0.4, 0.85, 0.85, 0.4, "bottom") }),
		mirrored({ B("FootSkin_L", -0.8, 0.1, -0.75, -0.3, 0.25, 0.25, "skin") }),
		tagged("footwear", mirrored({ B("Ojota_L", -0.85, 0, -0.85, -0.25, 0.1, 0.3, "shoe") })),
		tagged("accessory", {
			B("CarryCloth", -0.8, 1.6, 1.0, 0.8, 2.6, 1.4, "acc", { relief = true }),
			B("CarryKnot", -0.2, 2.35, -1.16, 0.2, 2.48, -1.11, "acc"),
		})
	),
	outfitRoles = { "hat", "hat2", "top", "top2", "bottom", "shoe", "acc" },
}

return table.freeze({
	set = "Volcano",
	regionId = "REGION_VOLCANO",
	reference = "docs/villagers/Volcano_outfit_reference.md",
	palette = table.freeze({
		PonchoRed = "#C8323A",
		CochinealPink = "#C8306A",
		AlpacaBrown = "#8A6648",
		AlpacaCream = "#F2E8D2",
		StripeYellow = "#F0B830",
		PolleraBlue = "#2E3E86",
		WoolBlack = "#1D2133",
		FeltHatBrown = "#4A3A32",
		OjotaDark = "#1D2133",
	}),
	glow = "#FF8A2A",
	outfits = table.freeze({
		["Sprinter"] = sprinter,
		["Plodder"] = plodder,
		["Shouter"] = shouter,
	}),
})
