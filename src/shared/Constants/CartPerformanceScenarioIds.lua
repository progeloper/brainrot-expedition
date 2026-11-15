--!strict

-- Stable Phase 1T scenario identifiers. They describe Development-only load
-- tests and are never gameplay or analytics event identifiers.
local All = table.freeze({
	"PERF_SCENARIO_STATIONARY_LOAD",
	"PERF_SCENARIO_MOVING_LOAD",
	"PERF_SCENARIO_MIXED_LIFECYCLE",
	"PERF_SCENARIO_CONTROLLED_COLLISION",
	"PERF_SCENARIO_REPEATED_RESET",
	"PERF_SCENARIO_REPLACEMENT_DESPAWN",
	"PERF_SCENARIO_ANALYTICS_LIFECYCLE",
	"PERF_SCENARIO_LIFECYCLE_ENDURANCE",
})

local CartPerformanceScenarioIds = {
	StationaryLoad = All[1],
	MovingLoad = All[2],
	MixedLifecycle = All[3],
	ControlledCollision = All[4],
	RepeatedReset = All[5],
	ReplacementDespawn = All[6],
	AnalyticsLifecycle = All[7],
	LifecycleEndurance = All[8],
	All = All,
}

return table.freeze(CartPerformanceScenarioIds)
