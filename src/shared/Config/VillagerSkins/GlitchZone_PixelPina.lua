--!strict
-- Pixel Pina (VIL_GLITCH_PINA): a GlitchZone guard in the Glitch-remixed Alpine loden dress.
-- Long blond hair, skin tone 2, Candy eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "GlitchZone_PixelPina",
	villagerId = "VIL_GLITCH_PINA",
	name = "Pixel Pina",
	uniform = require(script.Parent.Uniform_GlitchZone),
	skin = "#E8B48F",
	skin2 = "#C98A66",
	hair = "#E8C46A",
	style = "Long",
	eyes = "Candy",
	activities = { "Sweep" },
})
