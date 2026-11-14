--!strict
-- Scimmietta Sofia (VIL_JUNGLE_SOFIA): a Jungle guard in the Guatemalan highland everyday dress.
-- Long black hair, skin tone 3, Candy eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Jungle_ScimmiettaSofia",
	villagerId = "VIL_JUNGLE_SOFIA",
	name = "Scimmietta Sofia",
	uniform = require(script.Parent.Uniform_Jungle),
	skin = "#C98A5E",
	skin2 = "#A86B45",
	hair = "#2A1E18",
	style = "Long",
	eyes = "Candy",
	activities = { "Sweep" },
})
