--!strict
-- Arctic outfit set: plain everyday hooded parka dress (Inuit Arctic reference).
-- Reference card: docs/villagers/Arctic_outfit_reference.md. Every outfit colour must come from `palette` below (cleaned
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

-- Penguins (Sprinter / Penguin): hood + ruff, parka open over the white belly, kamiks, mittens.
local sprinter = {
	name = "Arctic hooded parka dress",
	hide = {
		"Beanie",
		"Pompom",
		"Scarf",
		"ScarfTail",
		"Blade_L",
		"Blade_R",
		"BuckleGlow",
		"ShoeStripe_L",
		"ShoeStripe_R",
		"Leg_L",
		"Leg_R",
	},
	add = joined(
		tagged(
			"headwear",
			joined(
				{
					B(
						"Hood",
						-1.1,
						4.6,
						-0.8,
						1.1,
						5.55,
						1.1,
						"hat",
						{ relief = true, group = "Hat" }
					),
					B(
						"RuffTop",
						-1.18,
						5.35,
						-1.02,
						1.18,
						5.65,
						-0.85,
						"hat2",
						{ relief = true, group = "Hat" }
					),
				},
				mirrored({
					B(
						"RuffSide_L",
						-1.2,
						4.0,
						-1.02,
						-1.02,
						5.65,
						-0.85,
						"hat2",
						{ relief = true, group = "Hat" }
					),
				})
			)
		),
		tagged(
			"top",
			joined(
				{ B("Parka", -1.08, 1.6, -0.62, 1.08, 3.95, 0.62, "top", { relief = true }) },
				mirrored({
					B(
						"ParkaSleeve_L",
						-1.55,
						2.2,
						-0.35,
						-0.98,
						3.8,
						0.35,
						"top",
						{ relief = true }
					),
				}),
				{ B("ParkaHemTrim", -1.12, 1.6, -0.66, 1.12, 1.7, 0.66, "glow") }
			)
		),
		tagged(
			"bottom",
			mirrored({
				B("Trouser_L", -0.8, 0.4, -0.33, -0.2, 1.65, 0.33, "bottom", { relief = true }),
			})
		),
		tagged(
			"footwear",
			mirrored({ B("Kamik_L", -0.86, 0, -0.78, -0.14, 0.75, 0.42, "shoe", { relief = true }) })
		),
		tagged(
			"accessory",
			mirrored({
				B("Mitten_L", -1.58, 1.85, -0.38, -0.95, 2.4, 0.38, "acc", { relief = true }),
			})
		),
		mirrored({ B("SkateBlade_L", -0.6, 0, -0.95, -0.4, 0.12, 0.55, "glow", { group = "Prop" }) })
	),
	outfitRoles = { "hat", "hat2", "top", "bottom", "shoe", "acc" },
}

-- Polar bears (Plodder / PolarBear): hood with the ears poking out, long parka, trousers.
local plodder = {
	name = "Arctic hooded parka dress (bear)",
	hide = { "Skirt", "SkirtHem", "Apron", "ApronPocketGlow", "Shawl", "Shoe_L", "Shoe_R" },
	add = joined(
		tagged(
			"headwear",
			joined(
				{
					B(
						"Hood",
						-1.12,
						4.6,
						-0.75,
						1.12,
						5.3,
						1.12,
						"hat",
						{ relief = true, group = "Hat" }
					),
					B(
						"RuffTop",
						-1.2,
						4.95,
						-0.95,
						1.2,
						5.3,
						-0.8,
						"hat2",
						{ relief = true, group = "Hat" }
					),
				},
				mirrored({
					B(
						"RuffSide_L",
						-1.22,
						3.8,
						-0.95,
						-1.05,
						5.3,
						-0.8,
						"hat2",
						{ relief = true, group = "Hat" }
					),
				})
			)
		),
		tagged(
			"top",
			joined(
				{ B("Parka", -1.3, 1.2, -0.8, 1.3, 3.62, 0.8, "top", { relief = true }) },
				mirrored({
					B("ParkaSleeve_L", -1.8, 2.15, -0.4, -1.2, 3.6, 0.4, "top", { relief = true }),
				}),
				{ B("ParkaHemTrim", -1.32, 1.2, -0.82, 1.32, 1.3, 0.82, "glow") }
			)
		),
		tagged(
			"bottom",
			mirrored({
				B("Trouser_L", -1.15, 0.3, -0.6, -0.1, 1.25, 0.6, "bottom", { relief = true }),
			})
		),
		tagged(
			"footwear",
			mirrored({ B("Kamik_L", -0.98, 0, -0.82, -0.17, 0.55, 0.4, "shoe", { relief = true }) })
		),
		tagged(
			"accessory",
			mirrored({
				B("Mitten_L", -1.82, 1.75, -0.42, -1.18, 2.2, 0.42, "acc", { relief = true }),
			})
		)
	),
	outfitRoles = { "hat", "hat2", "top", "bottom", "shoe", "acc" },
}

-- Seal (Shouter / Seal): pointed hood with ruff, parka, mittens on the flippers.
local shouter = {
	name = "Arctic hooded parka dress (seal)",
	hide = { "CaptainHat", "CaptainTop", "HatBadge", "BadgeGlow", "Leg_L", "Leg_R" },
	add = joined(
		tagged(
			"headwear",
			joined(
				{
					B(
						"Hood",
						-1.36,
						3.9,
						-0.9,
						1.36,
						4.75,
						1.06,
						"hat",
						{ relief = true, group = "Hat" }
					),
					B(
						"HoodPeak",
						-0.5,
						4.75,
						-0.4,
						0.5,
						5.35,
						0.5,
						"hat",
						{ relief = true, group = "Hat" }
					),
					B(
						"RuffTop",
						-1.3,
						4.1,
						-1.12,
						1.3,
						4.4,
						-1.04,
						"hat2",
						{ relief = true, group = "Hat" }
					),
				},
				mirrored({
					B(
						"RuffSide_L",
						-1.42,
						2.6,
						-1.1,
						-1.16,
						4.4,
						-0.95,
						"hat2",
						{ relief = true, group = "Hat" }
					),
				})
			)
		),
		tagged("top", {
			B("Parka", -1.34, 1.0, -1.04, 1.34, 2.5, 1.04, "top", { relief = true }),
			B("ParkaHemTrim", -1.36, 1.0, -1.06, 1.36, 1.1, 1.06, "glow"),
		}),
		tagged("bottom", { B("Trousers", -0.85, 0.3, -0.4, 0.85, 0.85, 0.4, "bottom") }),
		tagged(
			"footwear",
			mirrored({ B("Kamik_L", -0.88, 0, -0.88, -0.22, 0.45, 0.33, "shoe", { relief = true }) })
		),
		tagged(
			"accessory",
			mirrored({
				B("Mitten_L", -1.8, 1.15, -0.35, -1.36, 1.65, 0.45, "acc", { relief = true }),
			})
		)
	),
	outfitRoles = { "hat", "hat2", "top", "bottom", "shoe", "acc" },
}

return table.freeze({
	set = "Arctic",
	regionId = "REGION_ARCTIC",
	reference = "docs/villagers/Arctic_outfit_reference.md",
	palette = table.freeze({
		CaribouBrown = "#9A7650",
		SealGrey = "#7E7A70",
		DuffleWhite = "#F7F5FC",
		WoolBlue = "#2C3E78",
		RuffWolverine = "#5A4434",
		RuffWolf = "#BDB5AC",
		KamikPale = "#D8C49A",
	}),
	glow = "#7FE8FF",
	outfits = table.freeze({
		["Sprinter"] = sprinter,
		["Plodder"] = plodder,
		["Shouter"] = shouter,
	}),
})
