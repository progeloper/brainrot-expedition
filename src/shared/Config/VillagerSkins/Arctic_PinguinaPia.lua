--!strict
-- Pinguina Pia (VIL_ARCTIC_PIA): a Arctic guard in the Arctic hooded parka dress.
-- Long brown hair, skin tone 1, Violet eyes. Built by Guard.Make (owner, 14 Nov 2026:
-- guards are ordinary people with V4 anime eyes in their region's uniform).
local Guard = require(script.Parent.Guard)

return Guard.Make({
	id = "Arctic_PinguinaPia",
	villagerId = "VIL_ARCTIC_PIA",
	name = "Pinguina Pia",
	uniform = require(script.Parent.Uniform_Arctic),
	skin = "#F5D6BE",
	skin2 = "#E0A98A",
	hair = "#5A2E12",
	style = "Long",
	eyes = "Violet",
	activities = { "Sweep" },
})
