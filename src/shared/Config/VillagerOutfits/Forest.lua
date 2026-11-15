--!strict
-- Forest outfit set: Italian Alpine everyday/work dress (Trentino, South Tyrol, Ladin Dolomites).
-- Reference card: docs/villagers/Forest_outfit_reference.md. Every outfit colour must come
-- from `palette` below (cleaned reference colours). The region glow sits on ONE trim line.
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

-- Alpine loden work dress (men) on the Sprinter kit.
local sprinter = {
	name = "Alpine loden work dress (men)",
	hide = {
		"Cap",
		"CapBand",
		"CapBrim",
		"BuckleGlow",
		"ShoeStripe_L",
		"ShoeStripe_R",
		"Leg_L",
		"Leg_R",
	},
	add = joined(
		tagged("headwear", {
			B("FeltHatBrim", -1.25, 5.3, -1.25, 1.25, 5.4, 1.2, "hat", { group = "Hat" }),
			B(
				"FeltHatCrown",
				-0.85,
				5.4,
				-0.75,
				0.85,
				5.9,
				0.75,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("FeltHatBand", -0.87, 5.4, -0.77, 0.87, 5.5, 0.77, "glow", { group = "Hat" }),
		}),
		tagged("top", {
			B("JacketCollar", -1.02, 3.75, -0.6, 1.02, 3.92, 0.6, "cloth", { relief = true }),
			B("Waistcoat", -0.45, 2.35, -0.62, 0.45, 3.2, -0.56, "top", { relief = true }),
		}),
		tagged("bottom", {
			B("Breeches_L", -0.78, 1.3, -0.33, -0.22, 2.12, 0.33, "bottom", { relief = true }),
			B("Breeches_R", 0.22, 1.3, -0.33, 0.78, 2.12, 0.33, "bottom", { relief = true }),
			B("KneeSock_L", -0.76, 0.4, -0.31, -0.24, 1.3, 0.31, "sock", { relief = true }),
			B("KneeSock_R", 0.24, 0.4, -0.31, 0.76, 1.3, 0.31, "sock", { relief = true }),
		}),
		tagged("footwear", {
			B("BootCuff_L", -0.86, 0.4, -0.62, -0.14, 0.55, 0.42, "shoe"),
			B("BootCuff_R", 0.14, 0.4, -0.62, 0.86, 0.55, 0.42, "shoe"),
		}),
		tagged("accessory", {
			B("Neckerchief", -0.42, 3.72, -0.67, 0.42, 3.92, -0.58, "acc"),
			B("NeckerchiefKnot", -0.15, 3.5, -0.69, 0.15, 3.72, -0.62, "acc"),
		})
	),
	-- Palette roles that are clothing on this kit (checked against the card by V15).
	outfitRoles = {
		"hat",
		"cloth",
		"cloth2",
		"cloth3",
		"top",
		"bottom",
		"sock",
		"shoe",
		"acc",
		"trim",
	},
}

-- Alpine farm dress (women) on the Plodder kit.
local plodder = {
	name = "Alpine farm dress (women)",
	hide = { "Bun", "BunPin", "Hair", "HairBack", "ApronPocketGlow", "Skirt", "Apron" },
	add = joined(
		tagged("headwear", {
			B(
				"Headscarf",
				-1.12,
				4.9,
				-0.92,
				1.12,
				5.35,
				1.0,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B(
				"HeadscarfBack",
				-1.12,
				3.95,
				0.9,
				1.12,
				5.35,
				1.12,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("HeadscarfKnot", -0.25, 3.7, 1.05, 0.25, 4.0, 1.25, "hat", { group = "Hat" }),
		}),
		tagged("top", {
			B("BodiceLacing", -0.08, 2.0, -0.79, 0.08, 3.2, -0.75, "trim"),
			B("PuffSleeve_L", -1.8, 3.1, -0.4, -1.2, 3.6, 0.4, "cloth2", { relief = true }),
			B("PuffSleeve_R", 1.2, 3.1, -0.4, 1.8, 3.6, 0.4, "cloth2", { relief = true }),
		}),
		tagged("bottom", {
			B("WoolSkirt", -1.35, 0.35, -0.95, 1.35, 1.9, 0.95, "bottom", { relief = true }),
		}),
		tagged("footwear", {
			B("ShoeTop_L", -0.92, 0.3, -0.82, -0.23, 0.4, 0.37, "shoe"),
			B("ShoeTop_R", 0.23, 0.3, -0.82, 0.92, 0.4, 0.37, "shoe"),
		}),
		tagged("accessory", {
			B("WorkApron", -0.8, 0.6, -1.02, 0.8, 2.9, -0.95, "acc", { relief = true }),
			B("ApronBand", -0.85, 2.9, -1.04, 0.85, 3.0, -0.97, "glow"),
		})
	),
	outfitRoles = { "hat", "cloth", "cloth2", "trim", "bottom", "shoe", "acc" },
}

-- Alpine loden work dress on the animal (Shouter) kit. The animal head and feathers stay
-- readable above the collar; only the clothing roles come from the card.
local shouter = {
	name = "Alpine loden work dress (animal villagers)",
	hide = { "Hat1", "Hat2", "Hat3", "HatTip", "BadgeGlow", "Leg_L", "Leg_R" },
	add = joined(
		tagged("headwear", {
			B("FeltHatBrim", -1.2, 4.2, -1.1, 1.2, 4.3, 1.1, "hat", { group = "Hat" }),
			B(
				"FeltHatCrown",
				-0.8,
				4.3,
				-0.7,
				0.8,
				5.35,
				0.7,
				"hat",
				{ relief = true, group = "Hat" }
			),
			B("FeltHatBand", -0.82, 4.3, -0.72, 0.82, 4.42, 0.72, "glow", { group = "Hat" }),
		}),
		tagged("top", {
			B("Waistcoat", -1.34, 1.0, -1.04, 1.34, 2.5, 1.04, "top", { relief = true }),
		}),
		tagged("bottom", {
			B("Breeches", -0.85, 0.45, -0.4, 0.85, 0.85, 0.4, "bottom", { relief = true }),
			B("Sock_L", -0.72, 0.25, -0.22, -0.38, 0.45, 0.22, "sock"),
			B("Sock_R", 0.38, 0.25, -0.22, 0.72, 0.45, 0.22, "sock"),
		}),
		tagged("footwear", {
			B("BootCuff_L", -0.87, 0.25, -0.5, -0.23, 0.33, 0.32, "shoe"),
			B("BootCuff_R", 0.23, 0.25, -0.5, 0.87, 0.33, 0.32, "shoe"),
		}),
		tagged("accessory", {
			B("ShoulderScarf", -1.36, 2.5, -0.2, 1.36, 2.75, 1.06, "acc", { relief = true }),
			B("ScarfTail", 0.9, 1.9, 1.04, 1.2, 2.5, 1.12, "acc"),
		}),
		{
			-- Gufo's gag moves from the hat to his hand: a gelato cone (a prop, not clothing).
			B("GelatoCone", 1.45, 1.6, -0.6, 1.75, 2.3, -0.3, "prop", { group = "Prop" }),
			B("GelatoScoop", 1.38, 2.3, -0.67, 1.82, 2.65, -0.23, "prop2", { group = "Prop" }),
		}
	),
	outfitRoles = { "hat", "top", "bottom", "sock", "shoe", "acc" },
}

return table.freeze({
	set = "Forest",
	regionId = "REGION_FOREST",
	reference = "docs/villagers/Forest_outfit_reference.md",
	-- Cleaned reference colours (card table). Outfit roles may only use these.
	palette = table.freeze({
		LodenGreen = "#4E7A3E",
		LodenGrey = "#8E928C",
		LodenBrown = "#7A5536",
		LeatherBrown = "#7B5733",
		LeatherDark = "#1D2133",
		LinenWhite = "#F7F5FC",
		WoolCream = "#F2EAD8",
		VestRed = "#C7362F",
		SkirtNavy = "#3A4166",
		ApronBlue = "#2F5FB0",
		HatGreen = "#4A5C3C",
	}),
	glow = "#8DFF3A",
	outfits = table.freeze({
		Sprinter = sprinter,
		Plodder = plodder,
		Shouter = shouter,
	}),
})
