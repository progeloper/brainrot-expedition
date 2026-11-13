--!strict
-- Picchio Pepe (VIL_FOREST_PEPE) on the one villager body.
-- Forest set: Alpine loden work dress (animal villagers), docs/villagers/Forest_outfit_reference.md.
-- Today Picchio Pepe is the same Shouter kit as Gufo Gelato with his own palette, so his
-- skin is Gufo's boxes unchanged: bird face with a beak, head tufts past the felt hat with
-- the single Forest glow cord band, wing-arms, belly panel, loden waistcoat, shoulder
-- scarf, tail feathers and the gelato cone. What tells them apart is colour, from his
-- palette row: blue feathers, white face, yellow beak, red belly band and wingtips, grey
-- waistcoat, brown hat and green scarf.
local Gufo = require(script.Parent.Forest_GufoGelato) :: any

return table.freeze({
	id = "Forest_PicchioPepe",
	villagerId = "VIL_FOREST_PEPE",
	name = "Picchio Pepe",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({
		"blue feathers",
		"yellow beak",
		"red wingtips",
		"felt hat",
		"gelato cone",
	}),
	activities = table.freeze({ "Lookout" }),
	boxes = Gufo.boxes,
})
