--!strict
-- Surfista Sara (VIL_BEACH_SARA): a Beach guard in the southern Italian fisherman's work dress.
-- Long blond hair, skin tone 3, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Beach_SurfistaSara",
	villagerId = "VIL_BEACH_SARA",
	name = "Surfista Sara",
	uniform = require(script.Parent.Uniform_Beach),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#E8C46A",
	style = "Long",
	eyes = "Ocean",
	activities = { "Sweep" },
})
