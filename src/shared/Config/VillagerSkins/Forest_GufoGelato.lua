--!strict
-- Gufo Gelato (VIL_FOREST_GUFO): a Forest guard in the Alpine loden work dress.
-- Short auburn hair, skin tone 3, Amber eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Forest_GufoGelato",
	villagerId = "VIL_FOREST_GUFO",
	name = "Gufo Gelato",
	uniform = require(script.Parent.Uniform_Forest),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#8A3A1E",
	style = "Short",
	eyes = "Amber",
	activities = {},
})
