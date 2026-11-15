--!strict
-- Regions with villagers. CP-A: Forest. CP-B: Beach, Swamp, Jungle. CP-C: Arctic, Volcano, Glitch Zone.
local Villagers = script.Parent.Villagers

return table.freeze({
	require(Villagers.Forest),
	require(Villagers.Beach),
	require(Villagers.Swamp),
	require(Villagers.Jungle),
	require(Villagers.Arctic),
	require(Villagers.Volcano),
	require(Villagers.GlitchZone),
})
