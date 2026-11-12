--!strict
-- P15 final Robux catalogue (10 November 2026). Prices are the Robux prices to set
-- on the platform; the shop always displays the live platform price.
-- IDs stay nil until created and verified against this universe. Never substitute
-- placeholder numbers. Paid activation stays closed until the owner enables it.
return table.freeze({
	Version = "P15_ECONOMY_20261110_R1",
	UniverseId = 10548905405,
	ProductionDeliveryEnabled = false,
	-- Paid activation remains closed pending native receipt-recovery validation and platform setup.
	PaidCapacityRecoveryReady = false,
	ReadinessReason = "PAID_CAPACITY_RECOVERY_BLOCKED",
	-- Game passes: permanent, account-wide.
	Passes = {
		{
			id = "STARTER_PACK",
			name = "Starter Pack",
			targetPrice = 99,
			description = "3B Cash, 150 Gems and Trailblazer cart + weapon finishes. One time.",
		},
		{
			id = "INCOME_2X",
			name = "2× Cash",
			targetPrice = 299,
			description = "Double all Cash your brainrots earn. Forever.",
		},
		{
			id = "VIP",
			name = "VIP",
			targetPrice = 399,
			description = "+15% Cash, +25% free Gems, +10 Gems daily, VIP title and Riftgold finishes.",
		},
		{
			id = "AUTO_COLLECT",
			name = "Auto-Collect",
			targetPrice = 199,
			description = "Your base Cash collects itself.",
		},
		-- Camp Rework (12 Nov 2026). platformId stays nil until the owner creates the pass and it is
		-- verified against this universe; delivery stays disabled (ProductionDeliveryEnabled = false).
		{
			id = "WPN_SP_RIFTBLASTER",
			name = "Rift Blaster",
			targetPrice = 499,
			weaponId = "WPN_SP_RIFTBLASTER",
			requiresGate = "CampReworkV1Enabled",
			description = "Tier 5 power from day one. Black and gold. Never sellable.",
		},
		{
			id = "TRAINING_2X",
			name = "2× Training",
			targetPrice = 199, -- placeholder price: the owner confirms it when creating the pass
			requiresGate = "TrainingV1Enabled",
			description = "Double Training XP on every roller. Forever.",
		},
	},
	-- Developer products. `currency` decides what the receipt grants.
	Products = {
		{ id = "GEMS_40", name = "Gem Handful", targetPrice = 49, amount = 40, currency = "Gems", description = "40 Gems" },
		{ id = "GEMS_130", name = "Gem Pouch", targetPrice = 149, amount = 130, currency = "Gems", bonusPercent = 7, description = "130 Gems" },
		{ id = "GEMS_385", name = "Gem Sack", targetPrice = 399, amount = 385, currency = "Gems", bonusPercent = 18, description = "385 Gems" },
		{ id = "GEMS_830", name = "Gem Chest", targetPrice = 799, amount = 830, currency = "Gems", bonusPercent = 27, description = "830 Gems" },
		{ id = "GEMS_1970", name = "Gem Vault", targetPrice = 1699, amount = 1970, currency = "Gems", bonusPercent = 42, bestValue = true, description = "1,970 Gems" },
		{
			id = "MUTATION_STORM_15",
			name = "Mutation Storm",
			targetPrice = 99,
			amount = 900, -- seconds
			currency = "MutationStorm",
			description = "3× mutation chance for everyone in this server for 15 minutes.",
		},
	},
	-- Optional finishes are sold for Gems (Economy.GemCosmetics) once their renders are approved.
	Cosmetics = {
		{ id = "FIN_PRISM", name = "Prism weapon finish", priceGems = 150, enabled = false, reason = "Rendered approval required" },
		{ id = "FIN_GLACIER", name = "Glacier cart finish", priceGems = 250, enabled = false, reason = "Rendered approval required" },
		{ id = "FIN_AURORA", name = "Aurora base finish", priceGems = 350, enabled = false, reason = "Rendered approval required" },
		{ id = "FIN_SINGULARITY", name = "Singularity rift finish", priceGems = 350, enabled = false, reason = "Rendered approval required" },
	},
	CashDisclosure = "Cash is spent normally and is lost if you choose a cash rebirth.",
	StormDisclosure = "Mutation Storm affects new spawns in this server only and ends if the server closes.",
	ReceiptLimit = 10000,
	OwnershipCacheSeconds = 300,
	PriceCacheSeconds = 300,
})
