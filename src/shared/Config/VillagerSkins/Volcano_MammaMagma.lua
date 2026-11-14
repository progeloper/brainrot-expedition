--!strict
-- Mamma Magma (VIL_VOLCANO_MAGMA): a Volcano guard in the Andean highland work dress.
-- Long black hair, skin tone 4, Ruby eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Volcano_MammaMagma",
	villagerId = "VIL_VOLCANO_MAGMA",
	name = "Mamma Magma",
	uniform = require(script.Parent.Uniform_Volcano),
	skin = "#A86B45",
	skin2 = "#8A5233",
	hair = "#2A1E18",
	style = "Long",
	eyes = "Ruby",
	activities = {},
})
