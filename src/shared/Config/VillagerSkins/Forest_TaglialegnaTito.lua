--!strict
-- Taglialegna Tito (VIL_FOREST_TITO): a Forest guard in the Alpine loden work dress.
-- Beard brown hair, skin tone 2, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Forest_TaglialegnaTito",
	villagerId = "VIL_FOREST_TITO",
	name = "Taglialegna Tito",
	uniform = require(script.Parent.Uniform_Forest),
	skin = "#E8B48F",
	skin2 = "#C98A66",
	hair = "#5A2E12",
	style = "Beard",
	eyes = "Ocean",
	activities = { "Sweep" },
})
