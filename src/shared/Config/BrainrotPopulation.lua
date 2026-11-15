--!strict

local Phase10 = require(script.Parent.Phase10)

-- Phase 6E-2 owns ordinary wild-population admission only. These values do not
-- trim existing individuals and are independent of behaviour encounter/effect
-- budgets (for example an active Legendary pursuit reservation).
local profileAdmissionCaps = table.freeze({
	-- The initial Forest pool has only Wanderer, ReactiveRunner and Sprinter.
	-- Development needs 22 + 12 + 8 admissions to reach the existing target 42.
	Wanderer = if Phase10.Enabled then 22 else 20,
	ReactiveRunner = 12,
	Sprinter = 8,
	Zigzag = 4,
	Camouflage = 2,
	DecoySplit = 2,
	LegendaryPursuit = 1,
	MythicEvent = 1,
})

local BrainrotPopulation = {
	TargetWildPopulation = 42,
	ReplenishDelaySeconds = 2.0,
	RetryDelaySeconds = 2.0,
	MaxSpawnReservationsPerPass = 3,
	ProfileAdmissionCaps = profileAdmissionCaps,

	-- This is only the feature permit. The production scheduler additionally
	-- requires the live map, assignments, distributions and every regional pool
	-- to pass SpawnSelection.EvaluateConfiguredWorldReadiness before it starts.
	NaturalReplenishmentEnabled = true,
}

return table.freeze(BrainrotPopulation)
