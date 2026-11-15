--!strict
-- Jungle villagers (REGION_JUNGLE). Homes sit off the jungle paths, the Jungle gate (-244,202) and the Glitch gate (229,292).
-- v1.1 outfits: clothing colours come only from VillagerOutfits/Jungle (docs/villagers/Jungle_outfit_reference.md);
-- non-clothing colours use the V4 library; each villager carries the Jungle glow accent (#FFD447).
local GLOW = "#FFD447"

return table.freeze({
	regionId = "REGION_JUNGLE",
	villagers = table.freeze({
		{
			id = "VIL_JUNGLE_SCIMMIA",
			name = "Scimmia Spaghetti",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Monkey",
			outfit = "Jungle",
			home = { -150, 450 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "OOH-OOH! MY SPAGHETTI!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#F2C49A",
				skin2 = "#C98A5A",
				hair = "#5A3418",
				cloth = "#F7F5FC", -- CottonWhite
				cloth2 = "#5A3418",
				cloth3 = "#F2C49A",
				trim = "#3B2414",
				hat = "#E6C474", -- StrawHat
				hat2 = "#E6C474", -- StrawHat
				top = "#F7F5FC", -- CottonWhite
				bottom = "#F7F5FC", -- CottonWhite
				shoe = "#7A5530", -- SandalBrown
				acc = "#D0304A", -- WeaveRed
				acc2 = "#F0C040", -- WeaveYellow
				acc3 = "#2E66B0", -- WeaveBlue
				prop = "#FFE14A",
				prop2 = "#F0283C",
				glow = GLOW,
			},
		},
		{
			id = "VIL_JUNGLE_TOTO",
			name = "Tucano Totò",
			type = "Plodder",
			kit = "Plodder",
			variant = "Toucan",
			outfit = "Jungle",
			home = { 91, 502 },
			idleRadius = 6,
			idle = "Knit",
			shout = "MY MANGOES! MY CATCH!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#F7F5FC",
				skin2 = "#FF8A2A",
				hair = "#1A1A22",
				cloth = "#F7F5FC", -- CottonWhite
				cloth2 = "#F7F5FC", -- CottonWhite
				cloth3 = "#FFE14A",
				trim = "#1A1A22",
				hat = "#E6C474", -- StrawHat
				hat2 = "#E6C474", -- StrawHat
				top = "#2E66B0", -- WeaveBlue
				bottom = "#F7F5FC", -- CottonWhite
				shoe = "#7A5530", -- SandalBrown
				acc = "#D0304A", -- WeaveRed
				acc2 = "#F0C040", -- WeaveYellow
				acc3 = "#2E66B0", -- WeaveBlue
				prop = "#C9894A",
				prop2 = "#8A5528",
				glow = GLOW,
			},
		},
		{
			id = "VIL_JUNGLE_PAZZO",
			name = "Pappagallo Pazzo",
			type = "Shouter",
			kit = "Shouter",
			variant = "Parrot",
			outfit = "Jungle",
			home = { -420, 500 },
			idleRadius = 4,
			idle = "Bob",
			shout = "{name}! {name}! SQUAWK!",
			tantrum = "Squawk",
			palette = {
				skin = "#FFE14A",
				skin2 = "#F7F5FC",
				hair = "#F0283C",
				cloth = "#F0283C",
				cloth2 = "#1E6BFF",
				cloth3 = "#FFD447",
				trim = "#1A1A22",
				hat = "#E6C474", -- StrawHat
				hat2 = "#E6C474", -- StrawHat
				top = "#F7F5FC", -- CottonWhite
				bottom = "#F7F5FC", -- CottonWhite
				shoe = "#7A5530", -- SandalBrown
				acc = "#D0304A", -- WeaveRed
				acc2 = "#F0C040", -- WeaveYellow
				prop = "#FFD447",
				prop2 = "#FFD447",
				glow = GLOW,
			},
		},
		{
			id = "VIL_JUNGLE_SOFIA",
			name = "Scimmietta Sofia",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Monkey",
			outfit = "Jungle",
			outfitStyle = "Women",
			home = { 144, 370 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "HEY! BANANA THIEF!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#FFD0B0",
				skin2 = "#E89A72",
				hair = "#8A4618",
				cloth = "#F7F5FC", -- CottonWhite
				cloth2 = "#8A4618",
				cloth3 = "#FFD0B0",
				trim = "#5A2E12",
				hat = "#D0304A", -- WeaveRed
				hat2 = "#D0304A", -- WeaveRed
				top = "#F7F5FC", -- CottonWhite
				top2 = "#F0C040", -- WeaveYellow
				bottom = "#2C3C70", -- CorteIndigo
				shoe = "#7A5530", -- SandalBrown
				acc = "#D0304A", -- WeaveRed
				acc2 = "#6E3A9E", -- WeavePurple
				acc3 = "#2E66B0", -- WeaveBlue
				prop = "#FFE14A",
				prop2 = "#45D11E",
				glow = GLOW,
			},
		},
		{
			id = "VIL_JUNGLE_TINA",
			name = "Tucana Tina",
			type = "Plodder",
			kit = "Plodder",
			variant = "Toucan",
			outfit = "Jungle",
			outfitStyle = "Women",
			home = { -100, 240 },
			idleRadius = 6,
			idle = "Knit",
			shout = "COME BACK WITH THAT!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#FFE7C2",
				skin2 = "#45D11E",
				hair = "#0B2E6B",
				cloth = "#F7F5FC", -- CottonWhite
				cloth2 = "#F7F5FC", -- CottonWhite
				cloth3 = "#FF87C8",
				trim = "#0B2E6B",
				hat = "#2E66B0", -- WeaveBlue
				hat2 = "#2E66B0", -- WeaveBlue
				top = "#F7F5FC", -- CottonWhite
				top2 = "#F0C040", -- WeaveYellow
				bottom = "#2C3C70", -- CorteIndigo
				shoe = "#7A5530", -- SandalBrown
				acc = "#6E3A9E", -- WeavePurple
				acc2 = "#D0304A", -- WeaveRed
				acc3 = "#2E66B0", -- WeaveBlue
				prop = "#C9894A",
				prop2 = "#8A5528",
				glow = GLOW,
			},
		},
	}),
})
