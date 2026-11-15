--!strict
-- Arctic villagers (REGION_ARCTIC). Homes sit off the Arctic gate (229,-564) path strip and the Volcano path strip.
-- v1.1 outfits: clothing colours come only from VillagerOutfits/Arctic (docs/villagers/Arctic_outfit_reference.md);
-- non-clothing colours use the V4 library; each villager carries the region glow accent (#7FE8FF).
local GLOW = "#7FE8FF"

return table.freeze({
	regionId = "REGION_ARCTIC",
	villagers = table.freeze({
		{
			id = "VIL_ARCTIC_PATTINO",
			name = "Pinguino Pattino",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Penguin",
			outfit = "Arctic",
			home = { 412, -620 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "WADDLE WADDLE, STOP!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#1A1A2A",
				skin2 = "#FF8A2A",
				hair = "#1A1A2A",
				cloth = "#1A1A2A",
				cloth2 = "#1A1A2A",
				cloth3 = "#F7F5FC",
				trim = "#2E3B6B",
				hat = "#2C3E78", -- WoolBlue
				hat2 = "#5A4434", -- RuffWolverine
				top = "#2C3E78", -- WoolBlue
				bottom = "#7E7A70", -- SealGrey
				shoe = "#D8C49A", -- KamikPale
				acc = "#F7F5FC", -- DuffleWhite
				prop = "#F0283C",
				prop2 = "#F7F5FC",
				glow = GLOW,
			},
		},
		{
			id = "VIL_ARCTIC_PIA",
			name = "Pinguina Pia",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Penguin",
			outfit = "Arctic",
			home = { 650, -620 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "BRRR! COME BACK!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#2E3B6B",
				skin2 = "#FFD447",
				hair = "#2E3B6B",
				cloth = "#2E3B6B",
				cloth2 = "#2E3B6B",
				cloth3 = "#F7F5FC",
				trim = "#1A1A2A",
				hat = "#9A7650", -- CaribouBrown
				hat2 = "#BDB5AC", -- RuffWolf
				top = "#9A7650", -- CaribouBrown
				bottom = "#7E7A70", -- SealGrey
				shoe = "#D8C49A", -- KamikPale
				acc = "#F7F5FC", -- DuffleWhite
				prop = "#14C79F",
				prop2 = "#F7F5FC",
				glow = GLOW,
			},
		},
		{
			id = "VIL_ARCTIC_BRODO",
			name = "Orso Brodo",
			type = "Plodder",
			kit = "Plodder",
			variant = "PolarBear",
			outfit = "Arctic",
			home = { 600, -510 },
			idleRadius = 6,
			idle = "Knit",
			shout = "MY SOUP IS GETTING COLD!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#F7F5FC",
				skin2 = "#E6E6EE",
				hair = "#F7F5FC",
				cloth = "#F7F5FC",
				cloth2 = "#E6E6EE",
				cloth3 = "#46A7FF",
				trim = "#1A1A2A",
				hat = "#2C3E78", -- WoolBlue
				hat2 = "#5A4434", -- RuffWolverine
				top = "#2C3E78", -- WoolBlue
				bottom = "#7E7A70", -- SealGrey
				shoe = "#D8C49A", -- KamikPale
				acc = "#9A7650", -- CaribouBrown
				prop = "#9AA6C8",
				prop2 = "#5D6788",
				glow = GLOW,
			},
		},
		{
			id = "VIL_ARCTIC_OLGA",
			name = "Orsetta Olga",
			type = "Plodder",
			kit = "Plodder",
			variant = "PolarBear",
			outfit = "Arctic",
			home = { 420, -350 },
			idleRadius = 6,
			idle = "Knit",
			shout = "HEY! THAT'S NOT FAIR!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#F2EEE4",
				skin2 = "#E0D8C8",
				hair = "#F2EEE4",
				cloth = "#F2EEE4",
				cloth2 = "#E0D8C8",
				cloth3 = "#FF87C8",
				trim = "#3B2414",
				hat = "#9A7650", -- CaribouBrown
				hat2 = "#BDB5AC", -- RuffWolf
				top = "#9A7650", -- CaribouBrown
				bottom = "#7E7A70", -- SealGrey
				shoe = "#D8C49A", -- KamikPale
				acc = "#F7F5FC", -- DuffleWhite
				prop = "#FF3D9E",
				prop2 = "#8A1E5A",
				glow = GLOW,
			},
		},
		{
			id = "VIL_ARCTIC_FOCA",
			name = "Foca Fischietto",
			type = "Shouter",
			kit = "Shouter",
			variant = "Seal",
			outfit = "Arctic",
			home = { 306, -410 },
			idleRadius = 4,
			idle = "Bob",
			shout = "FWEEEEET! THIEF!",
			tantrum = "Squawk",
			palette = {
				skin = "#9AA6C8",
				skin2 = "#C8D2EA",
				hair = "#5D6788",
				cloth = "#7A86A8",
				cloth2 = "#5D6788",
				cloth3 = "#C8D2EA",
				trim = "#1A1A2A",
				hat = "#F7F5FC", -- DuffleWhite
				hat2 = "#5A4434", -- RuffWolverine
				top = "#F7F5FC", -- DuffleWhite
				bottom = "#2C3E78", -- WoolBlue
				shoe = "#D8C49A", -- KamikPale
				acc = "#9A7650", -- CaribouBrown
				prop = "#FFD447",
				prop2 = "#FFD447",
				glow = GLOW,
			},
		},
	}),
})
