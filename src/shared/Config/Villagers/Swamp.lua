--!strict
-- Swamp villagers (REGION_SWAMP). Homes sit off the swamp paths and the Swamp gate (-387,202).
-- v1.1 outfits: clothing colours come only from VillagerOutfits/Swamp (docs/villagers/Swamp_outfit_reference.md);
-- non-clothing colours use the V4 library; each villager carries the Swamp glow accent (#14C79F).
local GLOW = "#14C79F"

return table.freeze({
	regionId = "REGION_SWAMP",
	villagers = table.freeze({
		{
			id = "VIL_SWAMP_RANA",
			name = "Rana Rapida",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Frog",
			outfit = "Swamp",
			home = { -650, 250 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "RIBBIT! GET BACK HERE!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#45D11E",
				skin2 = "#1F8A12",
				hair = "#1F8A12",
				cloth = "#1D2133", -- AoBlack
				cloth2 = "#2E3B6B",
				cloth3 = "#FFF3C2",
				trim = "#1F4A0B",
				hat = "#E6D49E", -- PalmStraw
				hat2 = "#E6D49E", -- PalmStraw
				top = "#1D2133", -- AoBlack
				bottom = "#1D2133", -- AoBlack
				shoe = "#7A5530", -- SandalBrown
				acc = "#F7F5FC", -- ScarfWhite
				acc2 = "#1D2133", -- ScarfBlack
				prop = "#45D11E",
				prop2 = "#1F8A12",
				glow = GLOW,
			},
		},
		{
			id = "VIL_SWAMP_POZZO",
			name = "Pescatore Pozzo",
			type = "Plodder",
			kit = "Plodder",
			variant = "Fisher",
			outfit = "Swamp",
			home = { -320, 328 },
			idleRadius = 6,
			idle = "Knit",
			shout = "THAT ONE WAS MINE!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#E8B48F",
				skin2 = "#C98A66",
				hair = "#8A8A92",
				cloth = "#6B4630", -- AoBrown
				cloth2 = "#6B4630", -- AoBrown
				cloth3 = "#5D6788",
				trim = "#3B4A2A",
				hat = "#E6D49E", -- PalmStraw
				hat2 = "#E6D49E", -- PalmStraw
				top = "#6B4630", -- AoBrown
				bottom = "#6B4630", -- AoBrown
				shoe = "#7A5530", -- SandalBrown
				acc = "#F7F5FC", -- ScarfWhite
				acc2 = "#1D2133", -- ScarfBlack
				prop = "#C9B48A",
				prop2 = "#8A5528",
				glow = GLOW,
			},
		},
		{
			id = "VIL_SWAMP_LUMACA",
			name = "Lumaca Lampione",
			type = "Shouter",
			kit = "Shouter",
			variant = "Snail",
			outfit = "Swamp",
			home = { -620, 470 },
			idleRadius = 4,
			idle = "Bob",
			shout = "SLOW... DOWN... THIEF!",
			tantrum = "Squawk",
			palette = {
				skin = "#B6E07A",
				skin2 = "#7FB33A",
				hair = "#7FB33A",
				cloth = "#9ACD5A",
				cloth2 = "#8A5528",
				cloth3 = "#D8F2A8",
				trim = "#5A3418",
				hat = "#E6D49E", -- PalmStraw
				hat2 = "#E6D49E", -- PalmStraw
				top = "#6B4630", -- AoBrown
				bottom = "#1D2133", -- AoBlack
				shoe = "#7A5530", -- SandalBrown
				acc = "#F7F5FC", -- ScarfWhite
				acc2 = "#1D2133", -- ScarfBlack
				prop = "#C9894A",
				prop2 = "#8A5528",
				glow = GLOW,
			},
		},
		{
			id = "VIL_SWAMP_ROCCO",
			name = "Rospo Rocco",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Frog",
			outfit = "Swamp",
			home = { -700, 506 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "CROAK! STOP!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#8A6B2E",
				skin2 = "#5A4418",
				hair = "#5A4418",
				cloth = "#6B4630", -- AoBrown
				cloth2 = "#2E0F6B",
				cloth3 = "#FFE7A8",
				trim = "#2E1A08",
				hat = "#E6D49E", -- PalmStraw
				hat2 = "#E6D49E", -- PalmStraw
				top = "#6B4630", -- AoBrown
				bottom = "#1D2133", -- AoBlack
				shoe = "#7A5530", -- SandalBrown
				acc = "#F7F5FC", -- ScarfWhite
				acc2 = "#1D2133", -- ScarfBlack
				prop = "#8A6B2E",
				prop2 = "#5A4418",
				glow = GLOW,
			},
		},
		{
			id = "VIL_SWAMP_PALUDE",
			name = "Zia Palude",
			type = "Plodder",
			kit = "Plodder",
			variant = "Fisher",
			outfit = "Swamp",
			home = { -442, 281 },
			idleRadius = 6,
			idle = "Knit",
			shout = "OUT OF MY BOG!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#D9A383",
				skin2 = "#B97A5A",
				hair = "#3B2414",
				cloth = "#1D2133", -- AoBlack
				cloth2 = "#1D2133", -- AoBlack
				cloth3 = "#FFE7A8",
				trim = "#5A3418",
				hat = "#E6D49E", -- PalmStraw
				hat2 = "#E6D49E", -- PalmStraw
				top = "#1D2133", -- AoBlack
				bottom = "#1D2133", -- AoBlack
				shoe = "#7A5530", -- SandalBrown
				acc = "#F7F5FC", -- ScarfWhite
				acc2 = "#1D2133", -- ScarfBlack
				prop = "#C9B48A",
				prop2 = "#5A3418",
				glow = GLOW,
			},
		},
	}),
})
