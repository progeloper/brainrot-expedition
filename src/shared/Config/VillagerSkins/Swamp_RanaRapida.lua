--!strict
-- Rana Rapida (VIL_SWAMP_RANA): a Swamp guard in the Mekong Delta áo bà ba work clothes.
-- Bun black hair, skin tone 2, Lime eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Swamp_RanaRapida",
	villagerId = "VIL_SWAMP_RANA",
	name = "Rana Rapida",
	uniform = require(script.Parent.Uniform_Swamp),
	skin = "#E8B48F",
	skin2 = "#C98A66",
	hair = "#2A1E18",
	style = "Bun",
	eyes = "Lime",
	activities = { "Sweep" },
})
