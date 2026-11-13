--!strict
-- Zia Castagna (VIL_FOREST_CASTAGNA) on the one villager body.
-- Forest set: Alpine farm dress (women), docs/villagers/Forest_outfit_reference.md.
-- Today Zia Castagna is the same Plodder kit as Nonna Pina with her own palette, so her
-- skin is Pina's boxes unchanged: headscarf, hair fringe, shawl, laced bodice, puffed
-- sleeves, wool skirt, work apron with the single Forest glow band, and the rolling pin.
-- What tells them apart is colour, from her palette row: green headscarf, red bodice,
-- brown skirt, navy shawl and dark brown hair.
local Pina = require(script.Parent.Forest_NonnaPina) :: any

return table.freeze({
	id = "Forest_ZiaCastagna",
	villagerId = "VIL_FOREST_CASTAGNA",
	name = "Zia Castagna",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "green headscarf", "red bodice", "work apron", "rolling pin" }),
	activities = table.freeze({ "Sweep", "Knead" }),
	boxes = Pina.boxes,
})
