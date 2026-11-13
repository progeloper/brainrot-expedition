--!strict
-- Rospo Rocco (VIL_SWAMP_ROCCO) on the one villager body.
-- Swamp set: Mekong Delta áo bà ba work clothes (frog), docs/villagers/Swamp_outfit_reference.md.
-- Today Rospo Rocco is the same Sprinter Frog kit as Rana Rapida with his own palette, so his
-- skin is Rana's boxes unchanged: eye bumps, a wide mouth with a dark lip line and a pale
-- throat, the nón lá hung on his back by its glowing strap, the checked khăn rằn scarf, the
-- áo bà ba shirt over the hips, trousers rolled to the calf, webbed hands, and webbed feet on
-- sandals. What tells them apart is colour, from his palette row: a brown toad in a brown
-- shirt, where Rana is a green frog in black.
local Rana = require(script.Parent.Swamp_RanaRapida) :: any

return table.freeze({
	id = "Swamp_RospoRocco",
	villagerId = "VIL_SWAMP_ROCCO",
	name = "Rospo Rocco",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({
		"toad eye bumps",
		"nón lá on the back",
		"khăn rằn scarf",
		"áo bà ba",
	}),
	activities = table.freeze({ "Lookout", "Sweep" }),
	boxes = Rana.boxes,
})
