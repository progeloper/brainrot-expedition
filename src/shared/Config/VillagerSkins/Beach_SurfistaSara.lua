--!strict
-- Surfista Sara (VIL_BEACH_SARA) on the one villager body.
-- Beach set: southern Italian fisherman's work dress, docs/villagers/Beach_outfit_reference.md.
-- Today Surfista Sara is the same Sprinter Lifeguard kit as Bagnino Bruno with her own
-- palette, so her skin is Bruno's boxes unchanged: knitted fisherman's cap with the single
-- Beach glow band, work blouse with a collar and placket, whistle on a lanyard, waist sash,
-- canvas knee breeches, bare shins, boots and the rescue tube. What tells them apart is
-- colour, from her palette row.
local Bruno = require(script.Parent.Beach_BagninoBruno) :: any

return table.freeze({
	id = "Beach_SurfistaSara",
	villagerId = "VIL_BEACH_SARA",
	name = "Surfista Sara",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "knit cap", "whistle", "waist sash", "rescue tube" }),
	activities = table.freeze({ "Lookout", "Sweep" }),
	boxes = Bruno.boxes,
})
