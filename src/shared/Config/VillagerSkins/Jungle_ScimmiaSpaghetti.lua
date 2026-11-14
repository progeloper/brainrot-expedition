--!strict
-- Scimmia Spaghetti (VIL_JUNGLE_SCIMMIA): a Jungle guard in the Guatemalan highland everyday dress.
-- Short black hair, skin tone 4, Amber eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Jungle_ScimmiaSpaghetti",
	villagerId = "VIL_JUNGLE_SCIMMIA",
	name = "Scimmia Spaghetti",
	uniform = require(script.Parent.Uniform_Jungle),
	skin = "#A86B45",
	skin2 = "#8A5233",
	hair = "#2A1E18",
	style = "Short",
	eyes = "Amber",
	activities = { "Sweep" },
})
