--!strict
-- Pinguino Pattino (VIL_ARCTIC_PATTINO): a Arctic guard in the Arctic hooded parka dress.
-- Short black hair, skin tone 2, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Arctic_PinguinoPattino",
	villagerId = "VIL_ARCTIC_PATTINO",
	name = "Pinguino Pattino",
	uniform = require(script.Parent.Uniform_Arctic),
	skin = "#E8B48F",
	skin2 = "#C98A66",
	hair = "#2A1E18",
	style = "Short",
	eyes = "Ocean",
	activities = { "Sweep" },
})
