--!strict

local LoadCounts = require(script.Parent.Parent.Constants.CartPerformanceLoadCounts)
local ScenarioIds = require(script.Parent.Parent.Constants.CartPerformanceScenarioIds)

export type ScenarioDefinition = {
	Id: string,
	Label: string,
}

local function scenario(id: string, label: string): ScenarioDefinition
	return table.freeze({
		Id = id,
		Label = label,
	})
end

local Scenarios: { ScenarioDefinition } = {
	scenario(ScenarioIds.StationaryLoad, "Stationary active carts"),
	scenario(ScenarioIds.MovingLoad, "Moving carts"),
	scenario(ScenarioIds.MixedLifecycle, "Mixed lifecycle load"),
	scenario(ScenarioIds.ControlledCollision, "Controlled collision load"),
	scenario(ScenarioIds.RepeatedReset, "Repeated reset load"),
	scenario(ScenarioIds.ReplacementDespawn, "Replacement and despawn load"),
	scenario(ScenarioIds.AnalyticsLifecycle, "Analytics lifecycle load"),
	scenario(ScenarioIds.LifecycleEndurance, "Lifecycle endurance"),
}

table.freeze(Scenarios)

local ByScenarioId: { [string]: ScenarioDefinition } = {}

for _, definition in Scenarios do
	ByScenarioId[definition.Id] = definition
end

table.freeze(ByScenarioId)

-- Phase 1T Development test-process tuning. These values control evidence
-- collection only and are not gameplay values or Production performance
-- budgets. Five minutes and ten lifecycle cycles follow the prompt's minimum
-- formal Development measurement programme.
local Development = table.freeze({
	WarmupDuration = 10,
	SteadyStateDuration = 300,
	SnapshotInterval = 1,
	CleanupObservationDuration = 10,
	ActionObservationDuration = 2,
	EnduranceCycleCount = 10,
	MinimumSteadyStateCoverageRatio = 0.95,
	SnapshotCapacity = 512,
	MaximumMetricsPerSnapshot = 128,
	MaximumSummaryMetrics = 128,
})

local CartPerformanceTest = {
	-- This switch does not replace the required Environment/debug/Studio gates.
	Enabled = true,
	LoadCounts = LoadCounts.Ordered,
	Scenarios = Scenarios,
	ByScenarioId = ByScenarioId,
	Development = Development,
}

return table.freeze(CartPerformanceTest)
