--!strict
-- Forest villagers (REGION_FOREST). Homes sit off the Camp exit path, gates and cart spawns.
-- v1.1 outfits: everyone wears the Forest set (Italian Alpine everyday/work dress).
-- Clothing colours come only from VillagerOutfits/Forest palette (docs/villagers/Forest_outfit_reference.md);
-- the Forest glow accent (#8DFF3A) sits on one trim line. Animal body colours are not clothing.
local GLOW = "#8DFF3A"

return table.freeze({
	regionId = "REGION_FOREST",
	villagers = table.freeze({
		{
			id = "VIL_FOREST_TITO",
			name = "Taglialegna Tito",
			type = "Sprinter",
			kit = "Sprinter",
			outfit = "Forest",
			home = { -445, -150 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "TIMBER-THIEF!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#F7B58C",
				skin2 = "#E8875E",
				hair = "#5A2E12",
				cloth = "#4E7A3E", -- LodenGreen
				cloth2 = "#7B5733", -- LeatherBrown
				cloth3 = "#F7F5FC", -- LinenWhite
				trim = "#7B5733", -- LeatherBrown
				hat = "#4A5C3C", -- HatGreen
				hat2 = "#4A5C3C", -- HatGreen
				top = "#7A5536", -- LodenBrown
				bottom = "#7B5733", -- LeatherBrown
				sock = "#F2EAD8", -- WoolCream
				shoe = "#1D2133", -- LeatherDark
				acc = "#C7362F", -- VestRed
				prop = "#E8B866",
				prop2 = "#C9894A",
				glow = GLOW,
			},
		},
		{
			id = "VIL_FOREST_PINA",
			name = "Nonna Pina",
			type = "Plodder",
			kit = "Plodder",
			outfit = "Forest",
			home = { -330, -40 },
			idleRadius = 6,
			idle = "Knit",
			shout = "MAMMA MIA, COME BACK!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#F2B79A",
				skin2 = "#E08A6A",
				hair = "#E6E6EE",
				cloth = "#4E7A3E", -- LodenGreen
				cloth2 = "#F7F5FC", -- LinenWhite
				cloth3 = "#F7F5FC", -- LinenWhite
				trim = "#7A5536", -- LodenBrown
				hat = "#C7362F", -- VestRed
				hat2 = "#C7362F", -- VestRed
				top = "#4E7A3E", -- LodenGreen
				bottom = "#3A4166", -- SkirtNavy
				sock = "#F2EAD8", -- WoolCream
				shoe = "#1D2133", -- LeatherDark
				acc = "#2F5FB0", -- ApronBlue
				prop = "#C9894A",
				prop2 = "#8A5528",
				glow = GLOW,
			},
		},
		{
			id = "VIL_FOREST_GUFO",
			name = "Gufo Gelato",
			type = "Shouter",
			kit = "Shouter",
			outfit = "Forest",
			home = { -455, 70 },
			idleRadius = 4,
			idle = "Bob",
			shout = "HOO-HOO! THIEF!",
			tantrum = "Squawk",
			palette = {
				skin = "#FFE7C2",
				skin2 = "#FF8A2A",
				hair = "#5A3418",
				cloth = "#8A5528",
				cloth2 = "#5A3418",
				cloth3 = "#F2C46B",
				trim = "#3B2414",
				hat = "#4A5C3C", -- HatGreen
				hat2 = "#4A5C3C", -- HatGreen
				top = "#4E7A3E", -- LodenGreen
				bottom = "#7B5733", -- LeatherBrown
				sock = "#F2EAD8", -- WoolCream
				shoe = "#1D2133", -- LeatherDark
				acc = "#C7362F", -- VestRed
				prop = "#E8B866",
				prop2 = "#FF87C8",
				glow = GLOW,
			},
		},
		{
			id = "VIL_FOREST_FRANCO",
			name = "Funghetto Franco",
			type = "Sprinter",
			kit = "Sprinter",
			outfit = "Forest",
			home = { -110, -600 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "OI! MY MUSHROOMS!",
			tantrum = "WhistleFlail",
			palette = {
				skin = "#F7B58C",
				skin2 = "#E8875E",
				hair = "#8A5528",
				cloth = "#8E928C", -- LodenGrey
				cloth2 = "#7B5733", -- LeatherBrown
				cloth3 = "#F7F5FC", -- LinenWhite
				trim = "#7B5733", -- LeatherBrown
				hat = "#7A5536", -- LodenBrown
				hat2 = "#7A5536", -- LodenBrown
				top = "#C7362F", -- VestRed
				bottom = "#7B5733", -- LeatherBrown
				sock = "#F2EAD8", -- WoolCream
				shoe = "#1D2133", -- LeatherDark
				acc = "#4E7A3E", -- LodenGreen
				prop = "#E8B866",
				prop2 = "#C9894A",
				glow = GLOW,
			},
		},
		{
			id = "VIL_FOREST_CASTAGNA",
			name = "Zia Castagna",
			type = "Plodder",
			kit = "Plodder",
			outfit = "Forest",
			home = { 110, -610 },
			idleRadius = 6,
			idle = "Knit",
			shout = "STOP RIGHT THERE!",
			tantrum = "StompHatThrow",
			palette = {
				skin = "#E8B48F",
				skin2 = "#D08A66",
				hair = "#5A3418",
				cloth = "#C7362F", -- VestRed
				cloth2 = "#F7F5FC", -- LinenWhite
				cloth3 = "#F7F5FC", -- LinenWhite
				trim = "#3A4166", -- SkirtNavy
				hat = "#4E7A3E", -- LodenGreen
				hat2 = "#4E7A3E", -- LodenGreen
				top = "#C7362F", -- VestRed
				bottom = "#7A5536", -- LodenBrown
				sock = "#F2EAD8", -- WoolCream
				shoe = "#1D2133", -- LeatherDark
				acc = "#2F5FB0", -- ApronBlue
				prop = "#8A5528",
				prop2 = "#3B2414",
				glow = GLOW,
			},
		},
		{
			id = "VIL_FOREST_PEPE",
			name = "Picchio Pepe",
			type = "Shouter",
			kit = "Shouter",
			outfit = "Forest",
			home = { -150, -625 },
			idleRadius = 4,
			idle = "Bob",
			shout = "TOK-TOK-TOK! ALARM!",
			tantrum = "Squawk",
			palette = {
				skin = "#F7F5FC",
				skin2 = "#FFD447",
				hair = "#F0283C",
				cloth = "#1E6BFF",
				cloth2 = "#0B2E6B",
				cloth3 = "#F7F5FC",
				trim = "#F0283C",
				hat = "#7A5536", -- LodenBrown
				hat2 = "#7A5536", -- LodenBrown
				top = "#8E928C", -- LodenGrey
				bottom = "#7B5733", -- LeatherBrown
				sock = "#F2EAD8", -- WoolCream
				shoe = "#1D2133", -- LeatherDark
				acc = "#4E7A3E", -- LodenGreen
				prop = "#E8B866",
				prop2 = "#FFD447",
				glow = GLOW,
			},
		},
	}),
})
