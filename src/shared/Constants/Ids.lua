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

	Zones = {
		HuntersCamp = "ZON_000",
		MemeMeadows = "ZON_001",
		BrainrotBadlands = "ZON_002",
		Glitchwood = "ZON_003",
		TheRift = "ZON_004",
	},
}

return table.freeze(Ids)
