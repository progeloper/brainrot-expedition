--!strict
-- Zia Castagna (VIL_FOREST_CASTAGNA): a Forest guard in the Alpine loden work dress.
-- Long brown hair, skin tone 2, Ruby eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Forest_ZiaCastagna",
	villagerId = "VIL_FOREST_CASTAGNA",
	name = "Zia Castagna",
	uniform = require(script.Parent.Uniform_Forest),
	skin = "#E8B48F",
	skin2 = "#C98A66",
	hair = "#5A2E12",
	style = "Long",
	eyes = "Ruby",
	activities = {},
})
