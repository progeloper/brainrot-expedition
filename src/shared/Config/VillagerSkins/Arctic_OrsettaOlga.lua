--!strict
-- Orsetta Olga (VIL_ARCTIC_OLGA): a Arctic guard in the Arctic hooded parka dress.
-- Long blond hair, skin tone 1, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Arctic_OrsettaOlga",
	villagerId = "VIL_ARCTIC_OLGA",
	name = "Orsetta Olga",
	uniform = require(script.Parent.Uniform_Arctic),
	skin = "#F5D6BE",
	skin2 = "#E0A98A",
	hair = "#E8C46A",
	style = "Long",
	eyes = "Ocean",
	activities = {},
})
