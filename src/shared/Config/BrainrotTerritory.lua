--!strict

-- Phase 6F-2 placement and autonomous-goal limits. These values constrain only
-- naturally created, never-player-controlled wild individuals.
return table.freeze({
	MaxPlacementAttemptsPerSpawn = 8,
	BoundaryPaddingStuds = 2,
	MinWalkableNormalY = 0.65,
})
