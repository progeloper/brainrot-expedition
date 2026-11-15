--!strict
-- Volcano villagers (REGION_VOLCANO). Homes sit off the Volcano gate (229,-280) path strip.
-- v1.1 outfits: clothing colours come only from VillagerOutfits/Volcano (docs/villagers/Volcano_outfit_reference.md);
-- non-clothing colours use the V4 library; each villager carries the region glow accent (#FF8A2A).
local GLOW = "#FF8A2A"

return table.freeze({
	regionId = "REGION_VOLCANO",
	villagers = table.freeze({
		{
			id = "VIL_VOLCANO_LAVA",
			name = "Lavoratore Lava",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Miner",
			outfit = "Volcano",
			home = { 350, -150 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "HOT ON YOUR TRAIL!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#D9A383",
				skin2 = "#B97A5A",
				hair = "#3B2414",
				cloth = "#8A6648", -- AlpacaBrown
				cloth2 = "#3B3B48",
				cloth3 = "#FFD447",
				trim = "#1A1A22",
				hat = "#FFD447",
				hat2 = "#C9A227",
				chullo = "#F2E8D2", -- AlpacaCream
				chullo2 = "#C8323A", -- PonchoRed
				top = "#C8323A", -- PonchoRed
				top2 = "#F0B830", -- StripeYellow
				top3 = "#F2E8D2", -- AlpacaCream
				bottom = "#1D2133", -- WoolBlack
				shoe = "#1D2133", -- OjotaDark
				acc = "#C8306A", -- CochinealPink
				prop = "#5D6788",
				prop2 = "#8A5528",
				glow = GLOW,
			},
		},
		{
			id = "VIL_VOLCANO_MAGMA",
			name = "Mamma Magma",
			type = "Plodder",
			kit = "Plodder",
			variant = "Rock",
			outfit = "Volcano",
			home = { 550, 0 },
			idleRadius = 6,
			idle = "Knit",
			shout = "MAMMA'S GOING TO BLOW!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#8A7A70",
				skin2 = "#6A5A50",
				hair = "#2A2226",
				cloth = "#1D2133", -- WoolBlack
				cloth2 = "#1D2133", -- WoolBlack
				cloth3 = "#FF8A2A",
				trim = "#3B3036",
				hat = "#4A3A32", -- FeltHatBrown
				hat2 = "#1D2133", -- WoolBlack
				bottom = "#C8323A", -- PonchoRed
				bottom2 = "#2E3E86", -- PolleraBlue
				shoe = "#1D2133", -- OjotaDark
				acc = "#C8306A", -- CochinealPink
				acc2 = "#F0B830", -- StripeYellow
				prop = "#9AA6C8",
				prop2 = "#5D6788",
				glow = GLOW,
			},
		},
		{
			id = "VIL_VOLCANO_CAMPANA",
			name = "Campana Cenere",
			type = "Shouter",
			kit = "Shouter",
			variant = "Bell",
			outfit = "Volcano",
			home = { 400, 120 },
			idleRadius = 4,
			idle = "Bob",
			shout = "DONG! DONG! THIEF!",
			tantrum = "Squawk",
			palette = {
				skin = "#C8C0B8",
				skin2 = "#FF8A2A",
				hair = "#2E2A2E",
				cloth = "#4A4448",
				cloth2 = "#2E2A2E",
				cloth3 = "#8A8086",
				trim = "#1A1A22",
				hat = "#F2E8D2", -- AlpacaCream
				hat2 = "#C8323A", -- PonchoRed
				top = "#8A6648", -- AlpacaBrown
				top2 = "#F0B830", -- StripeYellow
				bottom = "#1D2133", -- WoolBlack
				shoe = "#1D2133", -- OjotaDark
				acc = "#C8306A", -- CochinealPink
				prop = "#FFD447",
				prop2 = "#C9A227",
				glow = GLOW,
			},
		},
		{
			id = "VIL_VOLCANO_MIMMO",
			name = "Minatore Mimmo",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Miner",
			outfit = "Volcano",
			home = { 600, -400 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "OI! THAT'S MY TUNNEL!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#C98A66",
				skin2 = "#A8643F",
				hair = "#1A1A22",
				cloth = "#1D2133", -- WoolBlack
				cloth2 = "#2E3B6B",
				cloth3 = "#F7F5FC",
				trim = "#1A1A22",
				hat = "#FF8A2A",
				hat2 = "#C96A2E",
				chullo = "#8A6648", -- AlpacaBrown
				chullo2 = "#F0B830", -- StripeYellow
				top = "#8A6648", -- AlpacaBrown
				top2 = "#C8323A", -- PonchoRed
				top3 = "#F2E8D2", -- AlpacaCream
				bottom = "#1D2133", -- WoolBlack
				shoe = "#1D2133", -- OjotaDark
				acc = "#2E3E86", -- PolleraBlue
				prop = "#9AA6C8",
				prop2 = "#5A3418",
				glow = GLOW,
			},
		},
		{
			id = "VIL_VOLCANO_BRACE",
			name = "Nonna Brace",
			type = "Plodder",
			kit = "Plodder",
			variant = "Rock",
			outfit = "Volcano",
			home = { 650, 150 },
			idleRadius = 6,
			idle = "Knit",
			shout = "BACK HERE, YOU LITTLE EMBER!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#9A8478",
				skin2 = "#7A6458",
				hair = "#2A1A18",
				cloth = "#2E3E86", -- PolleraBlue
				cloth2 = "#2E3E86", -- PolleraBlue
				cloth3 = "#FFB08A",
				trim = "#2A1A18",
				hat = "#4A3A32", -- FeltHatBrown
				hat2 = "#C8323A", -- PonchoRed
				bottom = "#C8306A", -- CochinealPink
				bottom2 = "#C8323A", -- PonchoRed
				shoe = "#1D2133", -- OjotaDark
				acc = "#F0B830", -- StripeYellow
				acc2 = "#C8323A", -- PonchoRed
				prop = "#9AA6C8",
				prop2 = "#5D6788",
				glow = GLOW,
			},
		},
	}),
})
