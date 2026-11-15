--!strict
-- Beach villagers (REGION_BEACH). Homes sit off the beach paths, the Forest gate (-507,-384) and the gate strip.
-- v1.1 outfits: clothing colours come only from VillagerOutfits/Beach (docs/villagers/Beach_outfit_reference.md);
-- non-clothing colours use the V4 library; each villager carries the Beach glow accent (#2EE9FF).
local GLOW = "#2EE9FF"

return table.freeze({
	regionId = "REGION_BEACH",
	villagers = table.freeze({
		{
			id = "VIL_BEACH_BRUNO",
			name = "Bagnino Bruno",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Lifeguard",
			outfit = "Beach",
			home = { -690, -150 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "FWEEEET! NO RUNNING!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#E8A274",
				skin2 = "#C9744A",
				hair = "#FFE14A",
				cloth = "#D23A30", -- CapRed
				cloth2 = "#F0283C",
				cloth3 = "#F7F5FC",
				trim = "#F7F5FC", -- LinenWhite
				hat = "#D23A30", -- CapRed
				hat2 = "#F0283C",
				top = "#F7F5FC", -- LinenWhite
				bottom = "#D8C08E", -- CanvasTan
				shoe = "#1D2133", -- BootDark
				acc = "#3460A8", -- SailorBlue
				prop = "#F0283C",
				prop2 = "#F7F5FC",
				glow = GLOW,
			},
		},
		{
			id = "VIL_BEACH_SABBIA",
			name = "Zio Sabbia",
			type = "Plodder",
			kit = "Plodder",
			variant = "Umbrella",
			outfit = "Beach",
			home = { -580, 60 },
			idleRadius = 6,
			idle = "Knit",
			shout = "OI! THAT'S MY SPOT!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#E8B48F",
				skin2 = "#C98A66",
				hair = "#F2C46B",
				cloth = "#F7F5FC", -- LinenWhite
				cloth2 = "#F7F5FC", -- LinenWhite
				cloth3 = "#FFE7A8",
				trim = "#F2C46B",
				hat = "#E8C46A", -- StrawGold
				hat2 = "#E8C46A", -- StrawGold
				top = "#3460A8", -- SailorBlue
				bottom = "#D8C08E", -- CanvasTan
				shoe = "#1D2133", -- BootDark
				acc = "#D23A30", -- CapRed
				prop = "#FF3D9E",
				prop2 = "#F7F5FC",
				glow = GLOW,
			},
		},
		{
			id = "VIL_BEACH_GRANCHIO",
			name = "Granchio Megafono",
			type = "Shouter",
			kit = "Shouter",
			variant = "Crab",
			outfit = "Beach",
			home = { -700, 120 },
			idleRadius = 4,
			idle = "Bob",
			shout = "ATTENZIONE! THIEF ON THE BEACH!",
			tantrum = "Squawk",
			palette = {
				skin = "#F7F5FC",
				skin2 = "#F0283C",
				hair = "#D9301E",
				cloth = "#FF4F3A",
				cloth2 = "#D9301E",
				cloth3 = "#FFB08A",
				trim = "#8A1E14",
				hat = "#3460A8", -- SailorBlue
				hat2 = "#3460A8", -- SailorBlue
				top = "#F7F5FC", -- LinenWhite
				bottom = "#D8C08E", -- CanvasTan
				shoe = "#1D2133", -- BootDark
				acc = "#3460A8", -- SailorBlue
				prop = "#FFD447",
				prop2 = "#F7F5FC",
				glow = GLOW,
			},
		},
		{
			id = "VIL_BEACH_SARA",
			name = "Surfista Sara",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Lifeguard",
			outfit = "Beach",
			home = { -600, -560 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "HANG ON, DUDE!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#C98A66",
				skin2 = "#A8643F",
				hair = "#3B2414",
				cloth = "#3460A8", -- SailorBlue
				cloth2 = "#1E6BFF",
				cloth3 = "#FFE14A",
				trim = "#F7F5FC", -- LinenWhite
				hat = "#D23A30", -- CapRed
				hat2 = "#14C79F",
				top = "#F7F5FC", -- LinenWhite
				bottom = "#D8C08E", -- CanvasTan
				shoe = "#6E4528", -- BootBrown
				acc = "#D23A30", -- CapRed
				prop = "#FF8A2A",
				prop2 = "#F7F5FC",
				glow = GLOW,
			},
		},
		{
			id = "VIL_BEACH_CONCHIGLIA",
			name = "Nonno Conchiglia",
			type = "Plodder",
			kit = "Plodder",
			variant = "Umbrella",
			outfit = "Beach",
			home = { -420, -600 },
			idleRadius = 6,
			idle = "Knit",
			shout = "MY SANDCASTLE!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#F2B79A",
				skin2 = "#E08A6A",
				hair = "#E6E6EE",
				cloth = "#3460A8", -- SailorBlue
				cloth2 = "#3460A8", -- SailorBlue
				cloth3 = "#F7F5FC",
				trim = "#FFD447",
				hat = "#E8C46A", -- StrawGold
				hat2 = "#E8C46A", -- StrawGold
				top = "#F7F5FC", -- LinenWhite
				bottom = "#D8C08E", -- CanvasTan
				shoe = "#6E4528", -- BootBrown
				acc = "#D23A30", -- CapRed
				prop = "#2EE9FF",
				prop2 = "#F7F5FC",
				glow = GLOW,
			},
		},
	}),
})
