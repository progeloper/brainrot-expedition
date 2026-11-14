--!strict
-- Granchio Megafono (VIL_BEACH_GRANCHIO): a Beach guard in the southern Italian fisherman's work dress.
-- Short auburn hair, skin tone 1, Ruby eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Beach_GranchioMegafono",
	villagerId = "VIL_BEACH_GRANCHIO",
	name = "Granchio Megafono",
	uniform = require(script.Parent.Uniform_Beach),
	skin = "#F5D6BE",
	skin2 = "#E0A98A",
	hair = "#8A3A1E",
	style = "Short",
	eyes = "Ruby",
	activities = {},
})
