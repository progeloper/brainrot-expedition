--!strict
-- Exact Phase 14 reward contract. Values are frozen on the first eligible action.
local Environment = require(script.Parent.Environment)
local Config = {
	Enabled = Environment.MainGameplayEnabled or not Environment.IsProduction,
	SchemaVersion = 1,
	RewardConfigVersion = "P15_RETENTION_V3",
	ResetPeriodSeconds = 86400,
	DailyQuestStage = 3,
	RegionBandOrder = { "Forest", "Beach", "Swamp", "Jungle", "Arctic", "Volcano", "Glitch" },
	RegionIdToBand = {
		REGION_CAMP = "Forest",
		REGION_FOREST = "Forest",
		REGION_BEACH = "Beach",
		REGION_SWAMP = "Swamp",
		REGION_JUNGLE = "Jungle",
		REGION_ARCTIC = "Arctic",
		REGION_VOLCANO = "Volcano",
		REGION_GLITCH = "Glitch",
	},
	UnitCashByRegionBand = {
		-- P15 final revenue curve: one unit ≈ a quarter of the next region gate.
		Forest = 250000000,
		Beach = 2500000000,
		Swamp = 10000000000,
		Jungle = 50000000000,
		Arctic = 100000000000,
		Volcano = 250000000000,
		Glitch = 500000000000,
	},
	QuestDefinitions = {
		bring_them_home = {
			Target = 3,
			RewardUnits = 3,
			Label = "Bring Them Home",
			Instruction = "Bank 3 fresh brainrots.",
		},
		field_research = {
			Target = 2,
			RewardUnits = 2,
			Label = "Field Research",
			Instruction = "Bank 2 different species today.",
		},
		camp_payday = {
			Target = 1,
			RewardUnits = 1,
			Label = "Camp Payday",
			Instruction = "Collect earnings from your base once.",
		},
	},
	SupplyRewardUnitsByCycleClaim = { 1, 1, 1, 1, 1, 1, 2 },
	SupplyCosmeticByLifetimeClaim = { [7] = "P14_FLAG_CAMP", [14] = "P14_BASE_EXPEDITION" },
	Milestones = {
		{ Id = "P14_TITLE_COLLECTOR", Label = "Collector", Slot = "Title", Species = 5 },
		{ Id = "P14_NAMEPLATE_FIELD_RESEARCH", Label = "Field Research", Slot = "Nameplate", Species = 10 },
		{ Id = "P14_TITLE_EXPEDITION_EXPERT", Label = "Expedition Expert", Slot = "Title", Species = 20 },
		{ Id = "P14_PLAQUE_MASTER_COLLECTOR", Label = "Master Collector", Slot = "Plaque", Species = 30 },
		{ Id = "P14_BADGE_ANOMALY_FOUND", Label = "Anomaly Found", Slot = "Badge", Anomaly = true },
	},
	MilestoneById = {},
	PaidFlagEnabled = false,
	PaidBannerEnabled = false,
	Calibration = {
		Forest = { Target = 250000000, MeanCps = 3210000, Basket = 1, NextPrice = 4000000000 },
		Beach = { Target = 2500000000, MeanCps = 4940000, Basket = 3, NextPrice = 60000000000 },
		Swamp = { Target = 10000000000, MeanCps = 12560000, Basket = 3, NextPrice = 300000000000 },
		Jungle = { Target = 50000000000, MeanCps = 19930000, Basket = 3, NextPrice = 1500000000000 },
		Arctic = { Target = 100000000000, MeanCps = 31930000, Basket = 3, NextPrice = 4000000000000 },
		Volcano = { Target = 250000000000, MeanCps = 60520000, Basket = 3, NextPrice = 10000000000000 },
		Glitch = { Target = 500000000000, MeanCps = 95340000, Basket = 3, NextPrice = 100000000000000 },
	},
}
for _, milestone in Config.Milestones do
	Config.MilestoneById[milestone.Id] = milestone
end
local function freeze(value)
	if table.isfrozen(value) then
		return value
	end
	for _, nested in value do
		if type(nested) == "table" then
			freeze(nested)
		end
	end
	return table.freeze(value)
end
return freeze(Config)
