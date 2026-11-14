--!strict
-- Zia Palude (VIL_SWAMP_PALUDE): a Swamp guard in the Mekong Delta áo bà ba work clothes.
-- Long dark hair, skin tone 3, Violet eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Swamp_ZiaPalude",
	villagerId = "VIL_SWAMP_PALUDE",
	name = "Zia Palude",
	uniform = require(script.Parent.Uniform_Swamp),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#3A2418",
	style = "Long",
	eyes = "Violet",
	activities = {},
})
