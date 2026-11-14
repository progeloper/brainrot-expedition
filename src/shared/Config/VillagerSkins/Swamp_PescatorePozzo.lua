--!strict
-- Pescatore Pozzo (VIL_SWAMP_POZZO): a Swamp guard in the Mekong Delta áo bà ba work clothes.
-- Beard grey hair, skin tone 3, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Swamp_PescatorePozzo",
	villagerId = "VIL_SWAMP_POZZO",
	name = "Pescatore Pozzo",
	uniform = require(script.Parent.Uniform_Swamp),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#9A9AA2",
	style = "Beard",
	eyes = "Ocean",
	activities = {},
})
