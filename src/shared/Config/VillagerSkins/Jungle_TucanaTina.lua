--!strict
-- Tucana Tina (VIL_JUNGLE_TINA): a Jungle guard in the Guatemalan highland everyday dress.
-- Bun dark hair, skin tone 5, Ruby eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Jungle_TucanaTina",
	villagerId = "VIL_JUNGLE_TINA",
	name = "Tucana Tina",
	uniform = require(script.Parent.Uniform_Jungle),
	skin = "#7A4A2E",
	skin2 = "#5E3620",
	hair = "#3A2418",
	style = "Bun",
	eyes = "Ruby",
	activities = {},
})
