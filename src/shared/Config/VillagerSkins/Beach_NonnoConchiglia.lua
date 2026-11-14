--!strict
-- Nonno Conchiglia (VIL_BEACH_CONCHIGLIA): a Beach guard in the southern Italian fisherman's work dress.
-- Beard white hair, skin tone 4, Lime eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Beach_NonnoConchiglia",
	villagerId = "VIL_BEACH_CONCHIGLIA",
	name = "Nonno Conchiglia",
	uniform = require(script.Parent.Uniform_Beach),
	skin = "#A86B45",
	skin2 = "#8A5233",
	hair = "#E8E8EE",
	style = "Beard",
	eyes = "Lime",
	activities = {},
})
