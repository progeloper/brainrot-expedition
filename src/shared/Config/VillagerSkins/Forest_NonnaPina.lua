--!strict
-- Nonna Pina (VIL_FOREST_PINA): a Forest guard in the Alpine loden work dress.
-- Bun white hair, skin tone 1, Amber eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Forest_NonnaPina",
	villagerId = "VIL_FOREST_PINA",
	name = "Nonna Pina",
	uniform = require(script.Parent.Uniform_Forest),
	skin = "#F5D6BE",
	skin2 = "#E0A98A",
	hair = "#E8E8EE",
	style = "Bun",
	eyes = "Amber",
	activities = {},
})
