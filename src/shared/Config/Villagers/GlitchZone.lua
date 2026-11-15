--!strict
-- Glitch Zone villagers (REGION_GLITCH). Homes sit off the Glitch gate (229,292) path strip.
-- v1.1 outfits: clothing colours come only from VillagerOutfits/Glitch (docs/villagers/GlitchZone_outfit_reference.md);
-- non-clothing colours use the V4 library; each villager carries the region glow accent (#FF49E1).
local GLOW = "#FF49E1"

return table.freeze({
	regionId = "REGION_GLITCH",
	villagers = table.freeze({
		{
			id = "VIL_GLITCH_PINO",
			name = "Pixel Pino",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Glitch",
			outfit = "Glitch",
			home = { 300, 450 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "ERR-ERR-ERROR! STOP!",
			tantrum = "WhistleFlail",
			flicker = true,
			palette = {
				skin = "#7FE8FF",
				skin2 = "#2EE9FF",
				hair = "#1A1428",
				cloth = "#FF49E1", -- GlitchMagenta
				cloth2 = "#2B0F52", -- GlitchViolet
				cloth3 = "#F7F5FC", -- GlitchWhite
				trim = "#2B0F52", -- GlitchViolet
				hat = "#2B0F52", -- GlitchViolet
				hat2 = "#FF49E1",
				top = "#2B0F52", -- GlitchViolet
				top2 = "#3EFFF0", -- GlitchCyan
				bottom = "#2B0F52", -- GlitchViolet
				sock = "#3EFFF0", -- GlitchCyan
				shoe = "#1D2133", -- GlitchDark
				acc = "#3EFFF0", -- GlitchCyan
				prop = "#F7F5FC",
				prop2 = "#1A1428",
				glow = GLOW,
			},
		},
		{
			id = "VIL_GLITCH_404",
			name = "Errore 404",
			type = "Plodder",
			kit = "Plodder",
			variant = "Box",
			outfit = "Glitch",
			home = { 500, 500 },
			idleRadius = 6,
			idle = "Knit",
			shout = "404: CATCH NOT FOUND!",
			tantrum = "StompHatThrow",
			flicker = true,
			palette = {
				skin = "#C9894A",
				skin2 = "#A86A2E",
				hair = "#5A3418",
				cloth = "#C9894A",
				cloth2 = "#A86A2E",
				cloth3 = "#E8C48A",
				trim = "#5A3418",
				hat = "#2B0F52", -- GlitchViolet
				hat2 = "#8A5528",
				top = "#FF49E1", -- GlitchMagenta
				top2 = "#3EFFF0", -- GlitchCyan
				bottom = "#2B0F52", -- GlitchViolet
				shoe = "#1D2133", -- GlitchDark
				acc = "#3EFFF0", -- GlitchCyan
				prop = "#C9894A",
				prop2 = "#8A5528",
				glow = GLOW,
			},
		},
		{
			id = "VIL_GLITCH_BIPBOP",
			name = "Bip Bop",
			type = "Shouter",
			kit = "Shouter",
			variant = "Speaker",
			outfit = "Glitch",
			home = { 650, 388 },
			idleRadius = 4,
			idle = "Bob",
			shout = "BIP! BOP! INTRUDER!",
			tantrum = "Squawk",
			flicker = true,
			palette = {
				skin = "#2A2A36",
				skin2 = "#3B3B48",
				hair = "#1A1A22",
				cloth = "#2A2A36",
				cloth2 = "#1A1A22",
				cloth3 = "#3B3B48",
				trim = "#1A1A22",
				hat = "#FF49E1", -- GlitchMagenta
				hat2 = "#1A1A22",
				top = "#2B0F52", -- GlitchViolet
				top2 = "#3EFFF0", -- GlitchCyan
				bottom = "#2B0F52", -- GlitchViolet
				shoe = "#1D2133", -- GlitchDark
				acc = "#3EFFF0", -- GlitchCyan
				prop = "#9AA6C8",
				prop2 = "#5D6788",
				glow = GLOW,
			},
		},
		{
			id = "VIL_GLITCH_PINA",
			name = "Pixel Pina",
			type = "Sprinter",
			kit = "Sprinter",
			variant = "Glitch",
			outfit = "Glitch",
			outfitStyle = "Beach",
			home = { 450, 380 },
			idleRadius = 8,
			idle = "Sweep",
			shout = "RE-RE-REBOOT AND CHASE!",
			tantrum = "WhistleFlail",
			flicker = true,
			palette = {
				skin = "#FFB3E0",
				skin2 = "#FF3DA8",
				hair = "#1A1428",
				cloth = "#FF49E1", -- GlitchMagenta
				cloth2 = "#1A1428",
				cloth3 = "#7FE8FF",
				trim = "#F7F5FC", -- GlitchWhite
				hat = "#FF49E1", -- GlitchMagenta
				hat2 = "#7FE8FF",
				top = "#F7F5FC", -- GlitchWhite
				top2 = "#3EFFF0", -- GlitchCyan
				bottom = "#2B0F52", -- GlitchViolet
				shoe = "#1D2133", -- GlitchDark
				acc = "#3EFFF0", -- GlitchCyan
				prop = "#F7F5FC",
				prop2 = "#1A1428",
				glow = GLOW,
			},
		},
		{
			id = "VIL_GLITCH_500",
			name = "Errore 500",
			type = "Plodder",
			kit = "Plodder",
			variant = "Box",
			outfit = "Glitch",
			home = { 611, 504 },
			idleRadius = 6,
			idle = "Knit",
			shout = "500: SERVER IS ANGRY!",
			tantrum = "StompHatThrow",
			flicker = true,
			palette = {
				skin = "#9AA6C8",
				skin2 = "#7A86A8",
				hair = "#2E3B6B",
				cloth = "#9AA6C8",
				cloth2 = "#7A86A8",
				cloth3 = "#C8D2EA",
				trim = "#2E3B6B",
				hat = "#FF49E1", -- GlitchMagenta
				hat2 = "#5D6788",
				top = "#2B0F52", -- GlitchViolet
				top2 = "#3EFFF0", -- GlitchCyan
				bottom = "#2B0F52", -- GlitchViolet
				shoe = "#1D2133", -- GlitchDark
				acc = "#FF49E1", -- GlitchMagenta
				prop = "#9AA6C8",
				prop2 = "#5D6788",
				glow = GLOW,
			},
		},
	}),
})
