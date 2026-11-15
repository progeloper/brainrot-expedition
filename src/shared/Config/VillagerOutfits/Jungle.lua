--!strict
-- Jungle outfit set: Guatemalan highland Maya everyday dress (garment shapes only).
-- Reference card: docs/villagers/Jungle_outfit_reference.md. Every outfit colour must come from `palette` below (cleaned
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

-- Plain original stripe rows only; no community pattern, motif or colour code is copied.
local function sash(x: number, y0: number, y1: number, z: number, tail: boolean): { any }
	local out = {
		B("Faja", -x, y0, -z, x, y1, z, "acc", { relief = true }),
		B("FajaStripe1", -x - 0.01, y0 + 0.1, -z - 0.01, x + 0.01, y0 + 0.15, z + 0.01, "acc2"),
		B("FajaStripe2", -x - 0.01, y1 - 0.15, -z - 0.01, x + 0.01, y1 - 0.1, z + 0.01, "acc3"),
	}
	if tail then
		table.insert(
			out,
			B("FajaTail", x * 0.55, y0 - 0.55, -z - 0.04, x * 0.55 + 0.25, y0, -z + 0.02, "acc")
		)
	end
	return out
end
local function bands(x: number, top: number, z: number): { any }
	return {
		B("HuipilBand1", -x, top - 0.1, z - 0.03, x, top, z, "acc2"),
		B("HuipilBand2", -x, top - 0.3, z - 0.03, x, top - 0.2, z, "acc3"),
		B("HuipilBand3", -x, top - 0.5, z - 0.03, x, top - 0.4, z, "top2"),
	}
end
local SPRINTER_HIDE = {
	"BuckleGlow",
	"ShoeStripe_L",
	"ShoeStripe_R",
	"Leg_L",
	"Leg_R",
	"Belt",
	"Shoe_L",
	"Shoe_R",
	"Shirt",
}
local function sprinterSandals(): { any }
	return joined(
		mirrored({ B("Foot_L", -0.8, 0.1, -0.75, -0.2, 0.35, 0.4, "skin") }),
		tagged(
			"footwear",
			mirrored({
				B("Sandal_L", -0.86, 0, -0.8, -0.14, 0.1, 0.45, "shoe"),
				B("SandalStrap_L", -0.82, 0.1, -0.5, -0.18, 0.22, -0.4, "shoe"),
			})
		)
	)
end

-- Men on the Sprinter / Monkey body.
local sprinterMen = {
	name = "Guatemalan highland men's everyday dress",
	hide = SPRINTER_HIDE,
	add = joined(
		tagged("headwear", {
			B("StrawBrim", -1.3, 5.35, -1.3, 1.3, 5.45, 1.25, "hat", { group = "Hat" }),
			B(
				"StrawCrown",
				-0.8,
				5.45,
				-0.75,
				0.8,
				5.9,
				0.75,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("StrawBand", -0.82, 5.45, -0.77, 0.82, 5.55, 0.77, "glow", { group = "Hat" }),
		}),
		tagged("top", {
			B("ShirtCollar", -0.6, 3.75, -0.62, 0.6, 3.92, -0.56, "top"),
			B("ShirtPlacket", -0.08, 2.4, -0.61, 0.08, 3.75, -0.56, "top"),
		}),
		tagged(
			"bottom",
			mirrored({
				B("Trouser_L", -0.78, 0.35, -0.33, -0.22, 2.12, 0.33, "bottom", { relief = true }),
			})
		),
		sprinterSandals(),
		tagged("accessory", sash(1.05, 2.05, 2.4, 0.6, true))
	),
	outfitRoles = { "hat", "cloth", "top", "bottom", "shoe", "acc", "acc2", "acc3" },
}

-- Women on the Sprinter / Monkey body: cinta, huipil with plain bands, corte, faja.
local sprinterWomen = {
	name = "Guatemalan highland women's everyday dress",
	hide = SPRINTER_HIDE,
	add = joined(
		tagged("headwear", {
			B("CintaBand", -1.06, 5.35, -0.5, 1.06, 5.5, 1.0, "hat", { group = "Hat" }),
			B(
				"CintaCoil",
				-0.5,
				5.5,
				-0.2,
				0.5,
				5.75,
				0.6,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("CintaEdge", -1.07, 5.38, -0.52, 1.07, 5.44, 1.02, "glow", { group = "Hat" }),
		}),
		tagged(
			"top",
			joined(
				{ B("Huipil", -1.04, 2.4, -0.6, 1.04, 3.92, 0.6, "top", { relief = true }) },
				bands(0.9, 3.55, -0.6)
			)
		),
		tagged(
			"bottom",
			{ B("Corte", -1.05, 0.6, -0.65, 1.05, 2.4, 0.65, "bottom", { relief = true }) }
		),
		mirrored({ B("Shin_L", -0.72, 0.35, -0.28, -0.28, 0.6, 0.28, "skin") }),
		sprinterSandals(),
		tagged("accessory", sash(1.08, 2.3, 2.55, 0.68, false))
	),
	outfitRoles = { "hat", "top", "top2", "bottom", "shoe", "acc", "acc2", "acc3" },
}

local PLODDER_HIDE = {
	"BeakStripe",
	"ApronPocketGlow",
	"Skirt",
	"SkirtHem",
	"Apron",
	"Shawl",
	"Shoe_L",
	"Shoe_R",
	"Crest",
}
local function plodderSandals(): { any }
	return joined(
		mirrored({ B("FootSkin_L", -0.9, 0.1, -0.75, -0.25, 0.35, 0.3, "skin") }),
		tagged(
			"footwear",
			mirrored({
				B("Sandal_L", -0.95, 0, -0.8, -0.2, 0.1, 0.35, "shoe"),
				B("SandalStrap_L", -0.9, 0.1, -0.5, -0.25, 0.18, -0.4, "shoe"),
			})
		)
	)
end

-- Men on the Plodder / Toucan body (trousers replace the skirt; mango sack stays a prop).
local plodderMen = {
	name = "Guatemalan highland men's everyday dress",
	hide = PLODDER_HIDE,
	add = joined(
		tagged("headwear", {
			B("StrawBrim", -1.45, 5.0, -1.35, 1.45, 5.1, 1.35, "hat", { group = "Hat" }),
			B(
				"StrawCrown",
				-0.8,
				5.1,
				-0.7,
				0.8,
				5.6,
				0.75,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("StrawBand", -0.82, 5.1, -0.72, 0.82, 5.2, 0.77, "glow", { group = "Hat" }),
		}),
		tagged("top", { B("ShirtCollar", -0.6, 3.45, -0.8, 0.6, 3.62, -0.75, "top") }),
		tagged(
			"bottom",
			mirrored({
				B("Trouser_L", -1.2, 0.35, -0.6, -0.1, 1.95, 0.6, "bottom", { relief = true }),
			})
		),
		plodderSandals(),
		tagged("accessory", sash(1.3, 1.85, 2.15, 0.8, true))
	),
	outfitRoles = { "hat", "cloth", "cloth2", "top", "bottom", "shoe", "acc", "acc2", "acc3" },
}

-- Women on the Plodder / Toucan body.
local plodderWomen = {
	name = "Guatemalan highland women's everyday dress",
	hide = PLODDER_HIDE,
	add = joined(
		tagged("headwear", {
			B("CintaBand", -1.07, 4.85, -0.4, 1.07, 5.0, 1.0, "hat", { group = "Hat" }),
			B(
				"CintaCoil",
				-0.5,
				5.0,
				-0.1,
				0.5,
				5.35,
				0.7,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("CintaEdge", -1.08, 4.85, -0.42, 1.08, 4.9, 1.02, "glow", { group = "Hat" }),
		}),
		tagged(
			"top",
			joined(
				{ B("Huipil", -1.27, 1.9, -0.77, 1.27, 3.62, 0.77, "top", { relief = true }) },
				bands(1.1, 3.3, -0.77)
			)
		),
		tagged(
			"bottom",
			{ B("Corte", -1.35, 0.35, -0.95, 1.35, 1.95, 0.95, "bottom", { relief = true }) }
		),
		plodderSandals(),
		tagged("accessory", sash(1.37, 1.8, 2.05, 0.97, false))
	),
	outfitRoles = { "hat", "cloth2", "top", "top2", "bottom", "shoe", "acc", "acc2", "acc3" },
}

-- Parrot (Shouter / Parrot): straw hat over the crest (crest recoloured as feathers).
local shouter = {
	name = "Guatemalan highland men's everyday dress (parrot)",
	hide = {
		"Crest1",
		"Crest2",
		"Crest3",
		"TailTip",
		"BadgeGlow",
		"Leg_L",
		"Leg_R",
		"Foot_L",
		"Foot_R",
	},
	add = joined(
		{
			B("FeatherCrestA", -0.15, 4.2, -0.35, 0.15, 5.1, -0.05, "hair"),
			B("FeatherCrestB", -0.15, 4.2, -0.05, 0.15, 5.6, 0.25, "hair"),
		},
		tagged("headwear", {
			B("StrawBrim", -1.25, 4.2, -1.15, 1.25, 4.3, 1.15, "hat", { group = "Hat" }),
			B(
				"StrawCrown",
				-0.75,
				4.3,
				-0.65,
				0.75,
				4.85,
				0.65,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("StrawBand", -0.77, 4.3, -0.67, 0.77, 4.4, 0.67, "glow", { group = "Hat" }),
		}),
		tagged("top", { B("Shirt", -1.34, 1.0, -1.04, 1.34, 2.5, 1.04, "top", { relief = true }) }),
		tagged("bottom", { B("Trousers", -0.85, 0.12, -0.4, 0.85, 0.85, 0.4, "bottom") }),
		tagged(
			"footwear",
			mirrored({
				B("Sandal_L", -0.85, 0, -0.85, -0.25, 0.1, 0.3, "shoe"),
				B("SandalStrap_L", -0.8, 0.1, -0.55, -0.3, 0.18, -0.45, "shoe"),
			})
		),
		tagged("accessory", {
			B("Faja", -1.36, 2.3, -1.06, 1.36, 2.5, 1.06, "acc"),
			B("FajaStripe", -1.37, 2.37, -1.07, 1.37, 2.42, 1.07, "acc2"),
			B("FajaTail", 0.9, 1.7, -1.14, 1.15, 2.3, -1.09, "acc"),
		})
	),
	outfitRoles = { "hat", "top", "bottom", "shoe", "acc", "acc2" },
}

return table.freeze({
	set = "Jungle",
	regionId = "REGION_JUNGLE",
	reference = "docs/villagers/Jungle_outfit_reference.md",
	palette = table.freeze({
		CottonWhite = "#F7F5FC",
		WeaveRed = "#D0304A",
		WeaveBlue = "#2E66B0",
		WeavePurple = "#6E3A9E",
		WeaveYellow = "#F0C040",
		CorteIndigo = "#2C3C70",
		StrawHat = "#E6C474",
		SandalBrown = "#7A5530",
	}),
	glow = "#FFD447",
	outfits = table.freeze({
		["Sprinter"] = sprinterMen,
		["Sprinter.Women"] = sprinterWomen,
		["Plodder"] = plodderMen,
		["Plodder.Women"] = plodderWomen,
		["Shouter"] = shouter,
	}),
})
