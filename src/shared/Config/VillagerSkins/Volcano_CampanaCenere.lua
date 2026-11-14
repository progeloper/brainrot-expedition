--!strict
-- Campana Cenere (VIL_VOLCANO_CAMPANA): a Volcano guard in the Andean highland work dress.
-- Short dark hair, skin tone 5, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Volcano_CampanaCenere",
	villagerId = "VIL_VOLCANO_CAMPANA",
	name = "Campana Cenere",
	uniform = require(script.Parent.Uniform_Volcano),
	skin = "#7A4A2E",
	skin2 = "#5E3620",
	hair = "#3A2418",
	style = "Short",
	eyes = "Ocean",
	activities = {},
})
