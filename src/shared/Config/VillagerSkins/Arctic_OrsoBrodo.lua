--!strict
-- Orso Brodo (VIL_ARCTIC_BRODO): a Arctic guard in the Arctic hooded parka dress.
-- Beard grey hair, skin tone 3, Amber eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Arctic_OrsoBrodo",
	villagerId = "VIL_ARCTIC_BRODO",
	name = "Orso Brodo",
	uniform = require(script.Parent.Uniform_Arctic),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#9A9AA2",
	style = "Beard",
	eyes = "Amber",
	activities = {},
})
