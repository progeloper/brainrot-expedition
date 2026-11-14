--!strict
-- Lumaca Lampione (VIL_SWAMP_LUMACA): a Swamp guard in the Mekong Delta áo bà ba work clothes.
-- Short brown hair, skin tone 4, Amber eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Swamp_LumacaLampione",
	villagerId = "VIL_SWAMP_LUMACA",
	name = "Lumaca Lampione",
	uniform = require(script.Parent.Uniform_Swamp),
	skin = "#A86B45",
	skin2 = "#8A5233",
	hair = "#5A2E12",
	style = "Short",
	eyes = "Amber",
	activities = {},
})
