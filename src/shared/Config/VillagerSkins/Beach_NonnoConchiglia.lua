--!strict
-- Nonno Conchiglia (VIL_BEACH_CONCHIGLIA) on the one villager body.
-- Beach set: southern Italian fisherman's work dress (older men),
-- docs/villagers/Beach_outfit_reference.md.
-- Today Nonno Conchiglia is the same Plodder Umbrella kit as Zio Sabbia with his own
-- palette, so his skin is Zio Sabbia's boxes unchanged: wide straw hat with the Beach glow
-- band, beard, loose shirt with a contrasting collar, waist sash, wide canvas trousers,
-- boots, and the beach umbrella in his right hand, kept upright by the same rule. What
-- tells them apart is colour, from his palette row.
local Sabbia = require(script.Parent.Beach_ZioSabbia) :: any

return table.freeze({
	id = "Beach_NonnoConchiglia",
	villagerId = "VIL_BEACH_CONCHIGLIA",
	name = "Nonno Conchiglia",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "straw hat", "white beard", "waist sash", "beach umbrella" }),
	activities = table.freeze({ "Lookout" }),
	-- the umbrella stands vertical whatever the hand does (Utility/VillagerUprightProp)
	uprightProp = true,
	boxes = Sabbia.boxes,
})
