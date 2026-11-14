--!strict
-- Zio Sabbia (VIL_BEACH_SABBIA): a Beach guard in the southern Italian fisherman's work dress.
-- Beard grey hair, skin tone 2, Amber eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Beach_ZioSabbia",
	villagerId = "VIL_BEACH_SABBIA",
	name = "Zio Sabbia",
	uniform = require(script.Parent.Uniform_Beach),
	skin = "#E8B48F",
	skin2 = "#C98A66",
	hair = "#9A9AA2",
	style = "Beard",
	eyes = "Amber",
	activities = {},
})
