--!strict
-- Minatore Mimmo (VIL_VOLCANO_MIMMO): a Volcano guard in the Andean highland work dress.
-- Beard black hair, skin tone 3, Lime eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Volcano_MinatoreMimmo",
	villagerId = "VIL_VOLCANO_MIMMO",
	name = "Minatore Mimmo",
	uniform = require(script.Parent.Uniform_Volcano),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#2A1E18",
	style = "Beard",
	eyes = "Lime",
	activities = { "Sweep" },
})
