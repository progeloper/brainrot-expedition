--!strict
-- Zia Palude (VIL_SWAMP_PALUDE) on the one villager body.
-- Swamp set: Mekong Delta áo bà ba work clothes (fisherman),
-- docs/villagers/Swamp_outfit_reference.md.
-- Today Zia Palude is the same Plodder Fisher kit as Pescatore Pozzo with her own palette, so
-- her skin is Pozzo's boxes unchanged: the nón lá with its glowing band (thrown in her
-- tantrum), the checked khăn rằn scarf, the áo bà ba over the hips, wide trousers rolled to the
-- calf, sandals, and the fishing net with its glowing float held upright in the right hand.
-- What tells them apart is colour, from her palette row: dark brown hair and a black áo bà ba,
-- where Pozzo has grey hair and brown.
local Pozzo = require(script.Parent.Swamp_PescatorePozzo) :: any

return table.freeze({
	id = "Swamp_ZiaPalude",
	villagerId = "VIL_SWAMP_PALUDE",
	name = "Zia Palude",
	approved = true, -- owner, 13 Nov 2026 (review round 1)
	hooks = table.freeze({ "nón lá", "dark hair", "khăn rằn scarf", "fishing net" }),
	activities = table.freeze({ "Fish", "Lookout" }),
	-- the net's pole stands vertical whatever the hand does (Utility/VillagerUprightProp)
	uprightProp = true,
	boxes = Pozzo.boxes,
})
