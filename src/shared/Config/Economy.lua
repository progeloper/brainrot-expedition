--!strict
-- Brainrot Expedition economy contract (P15, 10 November 2026).
-- One owner for currency names, multipliers, the Gem economy and Robux-facing
-- values. Brainrot revenue (BrainrotCatalog cashPerSecond) is final and is not
-- changed here; every Cash price in the game is anchored to it (see
-- design/Brainrot_Economy.md for the curve and the simulation that set it).
-- Gem amounts are whole numbers. Cash amounts are final denomination 2.

local Economy = {
	Version = "P15_ECONOMY_20261110_R1",

	Currencies = {
		Cash = { id = "Cash", displayName = "Cash", shortName = "Cash", symbol = "$" },
		-- The jagged purple rock. "Rift Gems" in titles, "Gems" on pills and prices.
		Gems = { id = "Gems", displayName = "Rift Gems", shortName = "Gems", symbol = "" },
	},

	-- Income = base × (1 + rebirth bonus + VIP bonus) × 2× pass × Cash Boost.
	-- The permanent group is additive so stacking stays readable and bounded.
	Income = {
		RebirthBonusPerRebirth = 0.10, -- every rebirth (expansion, design or prestige)
		VipBonus = 0.15,
		Income2xPass = 2,
		CashBoost = 2,
		CashBoostMaxSeconds = 6 * 3600, -- stacked boost time is capped
	},

	-- Repeatable endgame rebirth, offered once all six base expansions are owned.
	-- Cash route only. Price grows faster than the +10% it grants, so it is a
	-- long, optional tail rather than a wall.
	Prestige = {
		Id = "PRESTIGE",
		DisplayName = "Prestige",
		BasePrice = 100_000_000_000_000, -- 100T
		Growth = 1.75,
		MaxCount = 60,
	},

	StarterPack = { Cash = 3_000_000_000, Gems = 150 },

	-- Free Gem sources. A free, active player earns roughly 35 Gems a day after
	-- the first week (plus ~600 one-off Gems while discovering the roster):
	-- enough to try a Cash Boost most days and a crate or cosmetic each week.
	GemSources = {
		VipBonusFraction = 0.25, -- VIP: +25% on every free grant (rounded up)
		VipDailyGiftBonus = 10,
		DailyGiftByCycleDay = { 5, 5, 10, 10, 15, 15, 40 },
		DailyQuest = 5, -- each of the three daily quests
		Discovery = { Common = 3, Uncommon = 5, Rare = 10, Epic = 20, Legendary = 40, Mythic = 80, Celestial = 120, Secret = 150 },
		IndexMilestoneEvery = 5,
		IndexMilestone = 25,
		FirstMutation = { Shiny = 10, Golden = 15, Glitched = 25, Radioactive = 40, Astral = 75 },
		-- First bank of the day at each tier (once per tier per day).
		DailyFirstTier = { Rare = 2, Epic = 4, Legendary = 8, Mythic = 15, Celestial = 20, Secret = 30 },
		Rebirth = 40,
		Prestige = 100,
	},

	-- Gem shop. Gem items never gate core progress; they speed it up or decorate.
	GemShop = {
		{
			id = "CASH_BOOST_15",
			kind = "CashBoost",
			name = "2× Cash · 15 min",
			description = "Double all base income for 15 minutes.",
			priceGems = 30,
			seconds = 15 * 60,
			order = 1,
		},
		{
			id = "CASH_BOOST_60",
			kind = "CashBoost",
			name = "2× Cash · 1 hour",
			description = "Double all base income for 1 hour.",
			priceGems = 100,
			seconds = 60 * 60,
			order = 2,
		},
		{
			id = "CASH_CRATE_S",
			kind = "CashCrate",
			name = "Cash Crate",
			description = "Instantly get 20 minutes of your income.",
			priceGems = 60,
			minutes = 20,
			floorCash = 1_000_000_000,
			order = 3,
		},
		{
			id = "CASH_CRATE_L",
			kind = "CashCrate",
			name = "Cash Vault",
			description = "Instantly get 2 hours of your income.",
			priceGems = 300,
			minutes = 120,
			floorCash = 6_000_000_000,
			order = 4,
		},
		{
			id = "MUTATION_STORM",
			kind = "MutationStorm",
			name = "Mutation Storm",
			description = "3× mutation chance for everyone in this server, 15 min.",
			priceGems = 120,
			seconds = 15 * 60,
			order = 5,
		},
		-- Camp Rework premium specials (CampReworkV1Enabled). Permanent; never sellable.
		{
			id = "WEAPON_PRISMREPEATER",
			kind = "Weapon",
			weaponId = "WPN_SP_PRISMREPEATER",
			name = "Prism Repeater",
			description = "Tier 4 power, 2x fire rate. Yours forever.",
			priceGems = 300,
			order = 6,
		},
		{
			id = "WEAPON_CRYSTALLANCE",
			kind = "Weapon",
			weaponId = "WPN_SP_CRYSTALLANCE",
			name = "Crystal Lance",
			description = "Tier 6 power, heavy single shots. Yours forever.",
			priceGems = 900,
			order = 7,
		},
		-- Playtest Fixes 2 Part G (LegsTrainingV1Enabled): player trails. Permanent; one equipped at a time
		-- (Inventory > Trails). trailId matches Config/LegsTraining.
		{
			id = "TRAIL_RAINBOW",
			kind = "Trail",
			trailId = "TRAIL_RAINBOW",
			name = "Rainbow Trail",
			description = "A rainbow streak behind you on foot. Yours forever.",
			priceGems = 150,
			order = 8,
		},
		{
			id = "TRAIL_GLITCH",
			kind = "Trail",
			trailId = "TRAIL_GLITCH",
			name = "Glitch Trail",
			description = "A flickering glitch streak behind you on foot. Yours forever.",
			priceGems = 300,
			order = 9,
		},
		{
			id = "TRAIL_FIRE",
			kind = "Trail",
			trailId = "TRAIL_FIRE",
			name = "Fire Trail",
			description = "A blazing streak behind you on foot. Yours forever.",
			priceGems = 600,
			order = 10,
		},
	},

	-- Server-wide mutation luck (bought with Gems or Robux). Applies to new spawns
	-- in this server only and ends with the server; the shop says so.
	MutationStorm = {
		ChanceMultiplier = 3,
		MaxChance = 0.30,
		MaxSeconds = 60 * 60,
		Attribute = "MutationStormUntil",
		BuyerAttribute = "MutationStormBuyer",
	},

	-- Gem-priced cosmetics (ids owned by Phase14CosmeticRules / Phase13 finishes).
	GemCosmetics = {
		P14_FLAG_RIFT = 120,
		P14_BASE_RIFT = 220,
		FIN_PRISM = 150,
		FIN_GLACIER = 250,
		FIN_AURORA = 350,
		FIN_SINGULARITY = 350,
	},

	-- Integrity bounds for saved Gem state.
	MaxGems = 100_000_000,
}

local function deepFreeze(value: any): any
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	for _, nested in value do
		deepFreeze(nested)
	end
	return table.freeze(value)
end

local byId = {}
for _, item in Economy.GemShop do
	assert(byId[item.id] == nil, "Duplicate gem shop id " .. item.id)
	assert(type(item.priceGems) == "number" and item.priceGems > 0 and item.priceGems % 1 == 0, "Bad gem price")
	byId[item.id] = item
end
;(Economy :: any).GemShopById = byId

return deepFreeze(Economy)
