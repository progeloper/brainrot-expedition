--!strict
-- Pixel Pino (VIL_GLITCH_PINO): a GlitchZone guard in the Glitch-remixed Alpine loden dress.
-- Short blond hair, skin tone 1, Violet eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "GlitchZone_PixelPino",
	villagerId = "VIL_GLITCH_PINO",
	name = "Pixel Pino",
	uniform = require(script.Parent.Uniform_GlitchZone),
	skin = "#F5D6BE",
	skin2 = "#E0A98A",
	hair = "#E8C46A",
	style = "Short",
	eyes = "Violet",
	activities = { "Sweep" },
})
