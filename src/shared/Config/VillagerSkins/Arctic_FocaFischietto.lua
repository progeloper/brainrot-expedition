--!strict
-- Foca Fischietto (VIL_ARCTIC_FOCA): a Arctic guard in the Arctic hooded parka dress.
-- Short black hair, skin tone 4, Lime eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Arctic_FocaFischietto",
	villagerId = "VIL_ARCTIC_FOCA",
	name = "Foca Fischietto",
	uniform = require(script.Parent.Uniform_Arctic),
	skin = "#A86B45",
	skin2 = "#8A5233",
	hair = "#2A1E18",
	style = "Short",
	eyes = "Lime",
	activities = {},
})
