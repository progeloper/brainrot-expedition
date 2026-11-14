--!strict
-- Bagnino Bruno (VIL_BEACH_BRUNO): a Beach guard in the southern Italian fisherman's work dress.
-- Short black hair, skin tone 3, Ocean eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Beach_BagninoBruno",
	villagerId = "VIL_BEACH_BRUNO",
	name = "Bagnino Bruno",
	uniform = require(script.Parent.Uniform_Beach),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#2A1E18",
	style = "Short",
	eyes = "Ocean",
	activities = { "Sweep" },
})
