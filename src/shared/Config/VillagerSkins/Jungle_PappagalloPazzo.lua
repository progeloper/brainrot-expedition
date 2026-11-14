--!strict
-- Pappagallo Pazzo (VIL_JUNGLE_PAZZO): a Jungle guard in the Guatemalan highland everyday dress.
-- Short auburn hair, skin tone 2, Lime eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Jungle_PappagalloPazzo",
	villagerId = "VIL_JUNGLE_PAZZO",
	name = "Pappagallo Pazzo",
	uniform = require(script.Parent.Uniform_Jungle),
	skin = "#E8B48F",
	skin2 = "#C98A66",
	hair = "#8A3A1E",
	style = "Short",
	eyes = "Lime",
	activities = {},
})
