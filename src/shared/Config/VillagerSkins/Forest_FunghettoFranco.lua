--!strict
-- Funghetto Franco (VIL_FOREST_FRANCO) on the one villager body.
-- Forest set: Alpine loden work dress (men), docs/villagers/Forest_outfit_reference.md.
-- Today Franco is the same Sprinter kit as Taglialegna Tito with his own palette, so his
-- skin is Tito's boxes unchanged: felt hat with the single Forest glow cord band, loden
-- jacket open over a waistcoat and white shirt, neckerchief, knee breeches, knee socks,
-- boots and the breadstick axe. What tells them apart is colour, from his palette row:
-- grey jacket, red waistcoat, brown hat, green neckerchief and lighter hair.
local Tito = require(script.Parent.Forest_TaglialegnaTito) :: any

return table.freeze({
	id = "Forest_FunghettoFranco",
	villagerId = "VIL_FOREST_FRANCO",
	name = "Funghetto Franco",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "felt hat", "grey loden jacket", "red waistcoat", "breadstick axe" }),
	activities = table.freeze({ "Sweep", "Chop" }),
	boxes = Tito.boxes,
})
