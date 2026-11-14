--!strict
-- Village life tuning and points of interest (rig + animation brief v5, C.6). Presentation of
-- the Idle state only: nothing here touches noticing, chasing or any VillagerGuards value.
-- Pois are generated and validated in Studio against the map (never on a path, burrow, gate,
-- aperture closure or base patch; inside the guard's region, outside Camp, flat, unobstructed
-- and reachable in a straight line from home). See docs/animation/2026-11/village_life.md.
local Pois = require(script.Parent.VillagerLifePois)

return table.freeze({
	WorkMin = 6,
	WorkMax = 15,
	RestMin = 2,
	RestMax = 4,
	-- Plodders and Shouters stay at work longer and pick work spots more often.
	StayFactor = table.freeze({ Sprinter = 0.7, Plodder = 1.4, Shouter = 1.4 }),
	WorkWeight = 3,
	ChatDistance = 6,
	ChatChance = 0.3,
	ChatMin = 4,
	ChatMax = 8,
	WaveDistance = 15,
	WaveQuietSeconds = 20, -- no wave for a player who hit a brainrot this recently
	WaveRepeatSeconds = 60, -- once per player per guard per minute
	WaveSeconds = 1,
	SkateRadius = 1.6,
	SkateSpeed = 3,
	ArriveDistance = 0.6,
	TurnRateDegrees = 180,
	ResyncSeconds = 3, -- a gap longer than this (asleep) resumes from a seeded point
	Pois = Pois,
})
