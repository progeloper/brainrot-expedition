--!strict
-- Nonna Brace (VIL_VOLCANO_BRACE): a Volcano guard in the Andean highland work dress.
-- Bun grey hair, skin tone 4, Candy eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Volcano_NonnaBrace",
	villagerId = "VIL_VOLCANO_BRACE",
	name = "Nonna Brace",
	uniform = require(script.Parent.Uniform_Volcano),
	skin = "#A86B45",
	skin2 = "#8A5233",
	hair = "#9A9AA2",
	style = "Bun",
	eyes = "Candy",
	activities = {},
})
