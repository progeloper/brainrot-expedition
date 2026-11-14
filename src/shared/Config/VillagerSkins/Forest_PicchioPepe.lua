--!strict
-- Picchio Pepe (VIL_FOREST_PEPE): a Forest guard in the Alpine loden work dress.
-- Short black hair, skin tone 4, Candy eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Forest_PicchioPepe",
	villagerId = "VIL_FOREST_PEPE",
	name = "Picchio Pepe",
	uniform = require(script.Parent.Uniform_Forest),
	skin = "#A86B45",
	skin2 = "#8A5233",
	hair = "#2A1E18",
	style = "Short",
	eyes = "Candy",
	activities = {},
})
