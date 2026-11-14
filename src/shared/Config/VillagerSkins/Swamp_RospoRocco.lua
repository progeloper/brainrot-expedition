--!strict
-- Rospo Rocco (VIL_SWAMP_ROCCO): a Swamp guard in the Mekong Delta áo bà ba work clothes.
-- Short black hair, skin tone 5, Candy eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Swamp_RospoRocco",
	villagerId = "VIL_SWAMP_ROCCO",
	name = "Rospo Rocco",
	uniform = require(script.Parent.Uniform_Swamp),
	skin = "#7A4A2E",
	skin2 = "#5E3620",
	hair = "#2A1E18",
	style = "Short",
	eyes = "Candy",
	activities = { "Sweep" },
})
