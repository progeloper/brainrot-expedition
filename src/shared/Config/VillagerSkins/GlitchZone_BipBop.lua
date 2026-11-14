--!strict
-- Bip Bop (VIL_GLITCH_BIPBOP): a GlitchZone guard in the Glitch-remixed Alpine loden dress.
-- Short auburn hair, skin tone 5, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "GlitchZone_BipBop",
	villagerId = "VIL_GLITCH_BIPBOP",
	name = "Bip Bop",
	uniform = require(script.Parent.Uniform_GlitchZone),
	skin = "#7A4A2E",
	skin2 = "#5E3620",
	hair = "#8A3A1E",
	style = "Short",
	eyes = "Ocean",
	activities = {},
})
