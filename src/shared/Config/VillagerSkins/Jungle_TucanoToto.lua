--!strict
-- Tucano Totò (VIL_JUNGLE_TOTO): a Jungle guard in the Guatemalan highland everyday dress.
-- Beard dark hair, skin tone 3, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Jungle_TucanoToto",
	villagerId = "VIL_JUNGLE_TOTO",
	name = "Tucano Totò",
	uniform = require(script.Parent.Uniform_Jungle),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#3A2418",
	style = "Beard",
	eyes = "Ocean",
	activities = {},
})
