--!strict
-- Phase 13 contract values. Cash values are final denomination 2, never legacy-scaled.
local Config = {
	Version = 1,
	ConfigurationVersion = "P15_20261110_R1",
	MaxSlots = 48,
	InitialSlots = 12,
	ExpansionCapacities = { 12, 18, 24, 30, 36, 42, 48 },
	FloorPitchStuds = 24,
	SpeedPrices = { 500000000, 2500000000, 15000000000, 75000000000, 300000000000 },
	CargoPrices = { 1500000000, 12500000000, 100000000000 },
	EquippedPrices = { [3] = 500000000, [4] = 4000000000, [5] = 40000000000, [6] = 200000000000 },
	MaxSpeedLevel = 5,
	MaxCargoLevel = 3,
	OperationJournalLimit = 64,
	InitialWeaponId = "HRP_001",
	InitialCartId = "CRT_001",
	InitialDesignId = "BDS_001",
	ExpansionRows = {
		{ id = "EXP_018", capacity = 18, level = 1, price = 125000000000, minimumRarity = "Rare", required = 4 },
		{ id = "EXP_024", capacity = 24, level = 2, price = 500000000000, minimumRarity = "Rare", required = 4 },
		{ id = "EXP_030", capacity = 30, level = 3, price = 2000000000000, minimumRarity = "Epic", required = 4 },
		{ id = "EXP_036", capacity = 36, level = 4, price = 6000000000000, minimumRarity = "Epic", required = 4 },
		{ id = "EXP_042", capacity = 42, level = 5, price = 20000000000000, minimumRarity = "Legendary", required = 4 },
		{ id = "EXP_048", capacity = 48, level = 6, price = 50000000000000, minimumRarity = "Legendary", required = 4 },
	},
	DesignRows = {
		{ id = "BDS_001", displayName = "Camp Base", price = 0, starter = true },
		{ id = "BDS_002", displayName = "Forest Lodge", price = 500000000, minimumRarity = "Rare", required = 4 },
		{
			id = "BDS_003",
			displayName = "Tideglass Pavilion",
			price = 4000000000,
			minimumRarity = "Rare",
			required = 4,
		},
		{ id = "BDS_004", displayName = "Boglight Manor", price = 40000000000, minimumRarity = "Rare", required = 4 },
		{ id = "BDS_005", displayName = "Canopy Palace", price = 200000000000, minimumRarity = "Epic", required = 4 },
		{ id = "BDS_006", displayName = "Frostglass Keep", price = 1250000000000, minimumRarity = "Epic", required = 4 },
		{
			id = "BDS_007",
			displayName = "Magma Citadel",
			price = 6000000000000,
			minimumRarity = "Legendary",
			required = 4,
		},
		{
			id = "BDS_008",
			displayName = "Astral Outpost",
			price = 20000000000000,
			minimumRarity = "Legendary",
			required = 4,
		},
	},
	CartRows = {
		{
			id = "CRT_001",
			displayName = "Scrap Chariot",
			assetName = "ScrapChariot",
			classId = "Balanced",
			price = 0,
			starter = true,
		},
		{
			id = "CRT_006",
			displayName = "Neon Cruiser",
			assetName = "NeonCruiser",
			classId = "Balanced",
			price = 125000000000,
		},
		{
			id = "CRT_007",
			displayName = "Starforge Chariot",
			assetName = "StarforgeChariot",
			classId = "Balanced",
			price = 6000000000000,
		},
		{ id = "CRT_008", displayName = "Dune Runner", assetName = "DuneRunner", classId = "Scout", price = 500000000 },
		{
			id = "CRT_009",
			displayName = "Volt Dasher",
			assetName = "VoltDasher",
			classId = "Scout",
			price = 125000000000,
		},
		{
			id = "CRT_010",
			displayName = "Comet Skimmer",
			assetName = "CometSkimmer",
			classId = "Scout",
			price = 6000000000000,
		},
		{
			id = "CRT_011",
			displayName = "Iron Hauler",
			assetName = "IronHauler",
			classId = "Reinforced",
			price = 500000000,
		},
		{
			id = "CRT_012",
			displayName = "Bastion Wagon",
			assetName = "BastionWagon",
			classId = "Reinforced",
			price = 125000000000,
		},
		{
			id = "CRT_013",
			displayName = "Obsidian Fortress",
			assetName = "ObsidianFortress",
			classId = "Reinforced",
			price = 6000000000000,
		},
	},
	Classes = {
		Balanced = { speed = 1, acceleration = 1, braking = 1, steering = 1 },
		Scout = { speed = 1.10, acceleration = 1.25, braking = 0.90, steering = 0.85 },
		Reinforced = { speed = 0.90, acceleration = 0.90, braking = 1.25, steering = 1.15 },
	},
}
do
	-- Core Loop V2 lever (b): Speed, Cargo and expansion prices scale with the global price curve
	-- (factor 1 when Core Loop V2 is off). Equipped, design and cart prices are unchanged.
	local priceCurve = require(game:GetService("ReplicatedStorage").Shared.CoreLoop.PriceCurve)
	for _, list in { Config.SpeedPrices, Config.CargoPrices } do
		for index, price in list do
			list[index] = priceCurve.Scale(price)
		end
	end
	for _, row in Config.ExpansionRows do
		row.price = priceCurve.Scale(row.price)
	end
end
for _, rows in { Config.ExpansionRows, Config.DesignRows, Config.CartRows } do
	for _, row in rows do
		table.freeze(row)
	end
	table.freeze(rows)
end
return table.freeze(Config)
