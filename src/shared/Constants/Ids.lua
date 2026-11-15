--!strict

local Ids = {
	Brainrots = {
		BingusBaguette = "BRT_001",
		TralaleroToad = "BRT_002",
		CappuccinoCapybara = "BRT_003",
	},

	Carts = {
		ScrapChariot = "CRT_001",
		ReinforcedWagon = "CRT_002",
		RaiderBuggy = "CRT_003",
		TurboChariot = "CRT_004",
		RiftRunner = "CRT_005",
	},

	Harpoons = {
		Basic = "HRP_001",
		Longshot = "HRP_002",
		Net = "HRP_003",
		Reinforced = "HRP_004",
	},

	Gadgets = {
		SludgeBomb = "GDT_001",
	},

	Regions = {
		Beach = "REGION_BEACH",
		Forest = "REGION_FOREST",
		Swamp = "REGION_SWAMP",
		Jungle = "REGION_JUNGLE",
		Arctic = "REGION_ARCTIC",
		Volcano = "REGION_VOLCANO",
		Glitch = "REGION_GLITCH",
		Camp = "REGION_CAMP",
	},

	CartSpawns = {
		Development = "CSP_001",
		DevelopmentTwo = "CSP_002",
		DevelopmentThree = "CSP_003",
	},
}

return table.freeze(Ids)
