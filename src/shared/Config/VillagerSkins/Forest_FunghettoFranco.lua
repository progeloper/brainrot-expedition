--!strict
-- Funghetto Franco (VIL_FOREST_FRANCO): a Forest guard in the Alpine loden work dress.
-- Short blond hair, skin tone 1, Lime eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Forest_FunghettoFranco",
	villagerId = "VIL_FOREST_FRANCO",
	name = "Funghetto Franco",
	uniform = require(script.Parent.Uniform_Forest),
	skin = "#F5D6BE",
	skin2 = "#E0A98A",
	hair = "#E8C46A",
	style = "Short",
	eyes = "Lime",
	activities = { "Sweep" },
})
