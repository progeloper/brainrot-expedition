--!strict

local CartPerformanceTest = require(script.Parent.Parent.Config.CartPerformanceTest)
local ScenarioIds = require(script.Parent.Parent.Constants.CartPerformanceScenarioIds)
local CartPerformanceSnapshot = require(script.Parent.CartPerformanceSnapshot)

type Stage = CartPerformanceSnapshot.Stage

export type PassEvidence = {
	ScenarioId: string,
	Stage: Stage,
	LoadCount: number,
	LiveLoadCartCount: number,
	ValidAssemblyCount: number,
	FiniteRootCount: number,
	PhysicalRootCount: number,
	ServerOwnedRootCount: number,
	LoadAssemblyRecordCount: number,
	LoadOccupantRecordCount: number,
	LoadTerrainRecordCount: number,
	LoadStabilityRecordCount: number,
	LoadLongitudinalRecordCount: number,
	LoadValidatorRecordCount: number,
	LoadAnalyticsRecordCount: number,
	SteadyStateMeasuredSeconds: number,
	SteadyStatePeriodicSnapshotCount: number,
	PostActionMeasuredSeconds: number,
	CollisionActionCount: number,
	CollisionContactCount: number,
	MovementViolationActionCount: number,
	ResetActionCount: number,
	ReplacementActionCount: number,
	DestructionActionCount: number,
	EnduranceCycleCount: number,
	CaptureErrorCount: number,
	LifecycleErrorCount: number,
	MotionErrorCount: number,
	MotionElapsedSeconds: number,
	MotionPeakRecordCount: number,
	MotionAppliedRecordCount: number,
	MotionStepCount: number,
	MotionLinearImpulseCount: number,
	MotionSkippedRecordCount: number,
	LoadAnalyticsRuntimeIdentityCount: number,
	LoadAnalyticsSpawnEventCount: number,
	LoadAnalyticsCorrectionEventCount: number,
	ResetAnalyticsRequestedEventCount: number,
	ResetAnalyticsApprovedEventCount: number,
	ResetAnalyticsCompletedEventCount: number,
}

export type CleanupEvidence = {
	ScenarioId: string,
	LoadCount: number,
	LoadCartCount: number,
	HarnessSchedulerCount: number,
	MotionSchedulerCount: number,
	CaptureErrorCount: number,
	LifecycleErrorCount: number,
	MotionErrorCount: number,
	LoadAnalyticsRuntimeIdentityCount: number,
	LoadAnalyticsSpawnEventCount: number,
	LoadAnalyticsDespawnEventCount: number,
	BaselineMetrics: { [string]: number },
	FinalMetrics: { [string]: number },
}

export type EnduranceCleanupEvidence = {
	LoadCount: number,
	RuntimeActiveCount: number,
	LoadCartCount: number,
	MotionSchedulerCount: number,
	LoadAnalyticsRuntimeIdentityCount: number,
	LoadAnalyticsSpawnEventCount: number,
	LoadAnalyticsDespawnEventCount: number,
	Metrics: { [string]: number },
}

export type EnduranceReloadEvidence = {
	LoadCount: number,
	RuntimeActiveCount: number,
	LiveLoadCartCount: number,
	ValidAssemblyCount: number,
	FiniteRootCount: number,
	PhysicalRootCount: number,
	ServerOwnedRootCount: number,
	LoadAssemblyRecordCount: number,
	LoadOccupantRecordCount: number,
	LoadTerrainRecordCount: number,
	LoadStabilityRecordCount: number,
	LoadLongitudinalRecordCount: number,
	LoadValidatorRecordCount: number,
	LoadAnalyticsRecordCount: number,
	LoadAnalyticsRuntimeIdentityCount: number,
	LoadAnalyticsSpawnEventCount: number,
}

local CartPerformanceGatePolicy = {}

local CLEANUP_BOUNDED_METRICS = table.freeze({
	"CartRecords",
	"AssemblyRecords",
	"AssemblyRecordConnections",
	"AssemblyRetainedConnectionObjects",
	"AssemblyObservedInstances",
	"AssemblyRetainedObservedInstances",
	"OccupantRecords",
	"OccupantRecordConnections",
	"TerrainRecords",
	"TerrainRecordConnections",
	"StabilityRecords",
	"StabilityRecordConnections",
	"StabilityRetainedConnectionObjects",
	"LongitudinalRecords",
	"LongitudinalRecordConnections",
	"ValidatorRecords",
	"ValidatorRecordConnections",
	"AnalyticsRecords",
	"ResetPlayerRecords",
	"ResetCartRecords",
	"ResetActiveConnections",
	"ResetSecurityRecords",
	"ResetDevelopmentReservations",
})

local CLEANUP_STABLE_SHARED_METRICS = table.freeze({
	"TerrainSharedConnections",
	"StabilitySharedConnections",
	"LongitudinalSharedConnections",
	"ValidatorSharedConnections",
	"AnalyticsSharedConnections",
	"ResetSecurityConnections",
})

local LOAD_OWNED_CLEANUP_METRICS = table.freeze({
	"OwnedLoadCartRecords",
	"OwnedLoadParentedModels",
	"OwnedLoadAssemblyRecords",
	"OwnedLoadOccupantRecords",
	"OwnedLoadTerrainRecords",
	"OwnedLoadStabilityRecords",
	"OwnedLoadLongitudinalRecords",
	"OwnedLoadValidatorRecords",
	"OwnedLoadAnalyticsRecords",
	"CollisionFixtureParts",
	"CollisionFixtureConnections",
})

local function isFiniteNonnegativeInteger(value: number): boolean
	return value == value and math.abs(value) < math.huge and value >= 0 and value % 1 == 0
end

local function isFiniteNonnegativeNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge and value >= 0
end

local function isSupportedLoadCount(value: number): boolean
	if not isFiniteNonnegativeInteger(value) then
		return false
	end

	for _, supported in CartPerformanceTest.LoadCounts do
		if value == supported then
			return true
		end
	end

	return false
end

function CartPerformanceGatePolicy.CanTransition(
	currentStage: Stage,
	nextStage: Stage,
	stageElapsed: number
): (boolean, string?)
	if
		type(stageElapsed) ~= "number"
		or stageElapsed ~= stageElapsed
		or math.abs(stageElapsed) == math.huge
		or stageElapsed < 0
	then
		return false, "stage elapsed time must be finite and nonnegative"
	end

	if
		currentStage == CartPerformanceSnapshot.Stages.Warmup
		and nextStage == CartPerformanceSnapshot.Stages.SteadyState
	then
		if stageElapsed < CartPerformanceTest.Development.WarmupDuration then
			return false, "configured warm-up duration has not completed"
		end

		return true, nil
	end

	if
		currentStage == CartPerformanceSnapshot.Stages.SteadyState
		and nextStage == CartPerformanceSnapshot.Stages.LifecycleStress
	then
		if stageElapsed < CartPerformanceTest.Development.SteadyStateDuration then
			return false, "configured steady-state duration has not completed"
		end

		return true, nil
	end

	return false, "performance stages must advance Warmup -> SteadyState -> LifecycleStress"
end

function CartPerformanceGatePolicy.CanRestartEnduranceCycle(
	evidence: EnduranceCleanupEvidence
): (boolean, string?)
	if not isSupportedLoadCount(evidence.LoadCount) then
		return false, "LoadCount is not a central performance load count"
	end

	for fieldName, value in
		{
			RuntimeActiveCount = evidence.RuntimeActiveCount,
			LoadCartCount = evidence.LoadCartCount,
			MotionSchedulerCount = evidence.MotionSchedulerCount,
			LoadAnalyticsRuntimeIdentityCount = evidence.LoadAnalyticsRuntimeIdentityCount,
			LoadAnalyticsSpawnEventCount = evidence.LoadAnalyticsSpawnEventCount,
			LoadAnalyticsDespawnEventCount = evidence.LoadAnalyticsDespawnEventCount,
		}
	do
		if not isFiniteNonnegativeInteger(value) then
			return false, string.format("%s must be a finite nonnegative integer", fieldName)
		end
	end

	if evidence.RuntimeActiveCount ~= 0 or evidence.LoadCartCount ~= 0 then
		return false, "endurance cleanup retained active load carts"
	end

	if evidence.MotionSchedulerCount ~= 0 then
		return false, "endurance cleanup retained the motion scheduler"
	end

	for _, metricName in LOAD_OWNED_CLEANUP_METRICS do
		local value = evidence.Metrics[metricName]

		if type(value) ~= "number" or not isFiniteNonnegativeNumber(value) then
			return false,
				string.format("load-owned endurance metric %s is missing or invalid", metricName)
		end

		if value ~= 0 then
			return false,
				string.format("load-owned endurance metric %s retained harness state", metricName)
		end
	end

	if evidence.LoadAnalyticsRuntimeIdentityCount < evidence.LoadCount then
		return false, "endurance analytics runtime identity evidence is incomplete"
	end

	if
		evidence.LoadAnalyticsSpawnEventCount ~= evidence.LoadAnalyticsRuntimeIdentityCount
		or evidence.LoadAnalyticsDespawnEventCount ~= evidence.LoadAnalyticsRuntimeIdentityCount
	then
		return false, "endurance cleanup analytics evidence is incomplete or duplicated"
	end

	return true, nil
end

function CartPerformanceGatePolicy.CanContinueEnduranceCycle(
	evidence: EnduranceReloadEvidence
): (boolean, string?)
	if not isSupportedLoadCount(evidence.LoadCount) then
		return false, "LoadCount is not a central performance load count"
	end

	for fieldName, value in
		{
			RuntimeActiveCount = evidence.RuntimeActiveCount,
			LiveLoadCartCount = evidence.LiveLoadCartCount,
			ValidAssemblyCount = evidence.ValidAssemblyCount,
			FiniteRootCount = evidence.FiniteRootCount,
			PhysicalRootCount = evidence.PhysicalRootCount,
			ServerOwnedRootCount = evidence.ServerOwnedRootCount,
			LoadAssemblyRecordCount = evidence.LoadAssemblyRecordCount,
			LoadOccupantRecordCount = evidence.LoadOccupantRecordCount,
			LoadTerrainRecordCount = evidence.LoadTerrainRecordCount,
			LoadStabilityRecordCount = evidence.LoadStabilityRecordCount,
			LoadLongitudinalRecordCount = evidence.LoadLongitudinalRecordCount,
			LoadValidatorRecordCount = evidence.LoadValidatorRecordCount,
			LoadAnalyticsRecordCount = evidence.LoadAnalyticsRecordCount,
			LoadAnalyticsRuntimeIdentityCount = evidence.LoadAnalyticsRuntimeIdentityCount,
			LoadAnalyticsSpawnEventCount = evidence.LoadAnalyticsSpawnEventCount,
		}
	do
		if not isFiniteNonnegativeInteger(value) then
			return false, string.format("%s must be a finite nonnegative integer", fieldName)
		end
	end

	for fieldName, value in
		{
			RuntimeActiveCount = evidence.RuntimeActiveCount,
			LiveLoadCartCount = evidence.LiveLoadCartCount,
			ValidAssemblyCount = evidence.ValidAssemblyCount,
			FiniteRootCount = evidence.FiniteRootCount,
			PhysicalRootCount = evidence.PhysicalRootCount,
			ServerOwnedRootCount = evidence.ServerOwnedRootCount,
			LoadAssemblyRecordCount = evidence.LoadAssemblyRecordCount,
			LoadOccupantRecordCount = evidence.LoadOccupantRecordCount,
			LoadTerrainRecordCount = evidence.LoadTerrainRecordCount,
			LoadStabilityRecordCount = evidence.LoadStabilityRecordCount,
			LoadLongitudinalRecordCount = evidence.LoadLongitudinalRecordCount,
			LoadValidatorRecordCount = evidence.LoadValidatorRecordCount,
			LoadAnalyticsRecordCount = evidence.LoadAnalyticsRecordCount,
		}
	do
		if value ~= evidence.LoadCount then
			return false,
				string.format("%s must equal the configured endurance load count", fieldName)
		end
	end

	if evidence.LoadAnalyticsRuntimeIdentityCount < evidence.LoadCount then
		return false, "endurance reload analytics runtime identity evidence is incomplete"
	end

	if evidence.LoadAnalyticsSpawnEventCount ~= evidence.LoadAnalyticsRuntimeIdentityCount then
		return false, "endurance reload analytics spawn evidence is incomplete or duplicated"
	end

	return true, nil
end

function CartPerformanceGatePolicy.CanPass(evidence: PassEvidence): (boolean, string?)
	if CartPerformanceTest.ByScenarioId[evidence.ScenarioId] == nil then
		return false, "scenario ID is not registered"
	end

	if not isSupportedLoadCount(evidence.LoadCount) then
		return false, "LoadCount is not a central performance load count"
	end

	for fieldName, value in
		{
			LoadCount = evidence.LoadCount,
			LiveLoadCartCount = evidence.LiveLoadCartCount,
			ValidAssemblyCount = evidence.ValidAssemblyCount,
			FiniteRootCount = evidence.FiniteRootCount,
			PhysicalRootCount = evidence.PhysicalRootCount,
			ServerOwnedRootCount = evidence.ServerOwnedRootCount,
			LoadAssemblyRecordCount = evidence.LoadAssemblyRecordCount,
			LoadOccupantRecordCount = evidence.LoadOccupantRecordCount,
			LoadTerrainRecordCount = evidence.LoadTerrainRecordCount,
			LoadStabilityRecordCount = evidence.LoadStabilityRecordCount,
			LoadLongitudinalRecordCount = evidence.LoadLongitudinalRecordCount,
			LoadValidatorRecordCount = evidence.LoadValidatorRecordCount,
			LoadAnalyticsRecordCount = evidence.LoadAnalyticsRecordCount,
			SteadyStatePeriodicSnapshotCount = evidence.SteadyStatePeriodicSnapshotCount,
			CollisionActionCount = evidence.CollisionActionCount,
			CollisionContactCount = evidence.CollisionContactCount,
			MovementViolationActionCount = evidence.MovementViolationActionCount,
			ResetActionCount = evidence.ResetActionCount,
			ReplacementActionCount = evidence.ReplacementActionCount,
			DestructionActionCount = evidence.DestructionActionCount,
			EnduranceCycleCount = evidence.EnduranceCycleCount,
			CaptureErrorCount = evidence.CaptureErrorCount,
			LifecycleErrorCount = evidence.LifecycleErrorCount,
			MotionErrorCount = evidence.MotionErrorCount,
			MotionPeakRecordCount = evidence.MotionPeakRecordCount,
			MotionAppliedRecordCount = evidence.MotionAppliedRecordCount,
			MotionStepCount = evidence.MotionStepCount,
			MotionLinearImpulseCount = evidence.MotionLinearImpulseCount,
			MotionSkippedRecordCount = evidence.MotionSkippedRecordCount,
			LoadAnalyticsRuntimeIdentityCount = evidence.LoadAnalyticsRuntimeIdentityCount,
			LoadAnalyticsSpawnEventCount = evidence.LoadAnalyticsSpawnEventCount,
			LoadAnalyticsCorrectionEventCount = evidence.LoadAnalyticsCorrectionEventCount,
			ResetAnalyticsRequestedEventCount = evidence.ResetAnalyticsRequestedEventCount,
			ResetAnalyticsApprovedEventCount = evidence.ResetAnalyticsApprovedEventCount,
			ResetAnalyticsCompletedEventCount = evidence.ResetAnalyticsCompletedEventCount,
		}
	do
		if not isFiniteNonnegativeInteger(value) then
			return false, string.format("%s must be a finite nonnegative integer", fieldName)
		end
	end

	if not isFiniteNonnegativeNumber(evidence.SteadyStateMeasuredSeconds) then
		return false, "SteadyStateMeasuredSeconds must be finite and nonnegative"
	end

	if not isFiniteNonnegativeNumber(evidence.PostActionMeasuredSeconds) then
		return false, "PostActionMeasuredSeconds must be finite and nonnegative"
	end

	if not isFiniteNonnegativeNumber(evidence.MotionElapsedSeconds) then
		return false, "MotionElapsedSeconds must be finite and nonnegative"
	end

	if evidence.Stage ~= CartPerformanceSnapshot.Stages.LifecycleStress then
		return false, "formal pass requires completed warm-up and steady-state stages"
	end

	if evidence.CaptureErrorCount > 0 then
		return false, "measurement capture errors remain"
	end

	if evidence.LifecycleErrorCount > 0 then
		return false, "performance lifecycle errors remain"
	end

	if evidence.MotionErrorCount > 0 then
		return false, "motion simulator errors remain"
	end

	local minimumCoverage = CartPerformanceTest.Development.MinimumSteadyStateCoverageRatio
	local minimumMeasuredSeconds = CartPerformanceTest.Development.SteadyStateDuration
		* minimumCoverage
	local minimumPeriodicSnapshots = math.floor(
		(
			CartPerformanceTest.Development.SteadyStateDuration
			/ CartPerformanceTest.Development.SnapshotInterval
		) * minimumCoverage
	)

	if evidence.SteadyStateMeasuredSeconds < minimumMeasuredSeconds then
		return false, "steady-state Heartbeat measurement coverage is incomplete"
	end

	if evidence.SteadyStatePeriodicSnapshotCount < minimumPeriodicSnapshots then
		return false, "steady-state periodic snapshot coverage is incomplete"
	end

	for fieldName, value in
		{
			LiveLoadCartCount = evidence.LiveLoadCartCount,
			ValidAssemblyCount = evidence.ValidAssemblyCount,
			FiniteRootCount = evidence.FiniteRootCount,
			PhysicalRootCount = evidence.PhysicalRootCount,
			ServerOwnedRootCount = evidence.ServerOwnedRootCount,
			LoadAssemblyRecordCount = evidence.LoadAssemblyRecordCount,
			LoadOccupantRecordCount = evidence.LoadOccupantRecordCount,
			LoadTerrainRecordCount = evidence.LoadTerrainRecordCount,
			LoadStabilityRecordCount = evidence.LoadStabilityRecordCount,
			LoadLongitudinalRecordCount = evidence.LoadLongitudinalRecordCount,
			LoadValidatorRecordCount = evidence.LoadValidatorRecordCount,
			LoadAnalyticsRecordCount = evidence.LoadAnalyticsRecordCount,
		}
	do
		if value ~= evidence.LoadCount then
			return false,
				string.format("%s must equal the configured load count before pass", fieldName)
		end
	end

	local expectedRuntimeIdentityCount = evidence.LoadCount
		+ evidence.ReplacementActionCount
		+ evidence.EnduranceCycleCount * evidence.LoadCount

	if evidence.LoadAnalyticsRuntimeIdentityCount ~= expectedRuntimeIdentityCount then
		return false, "load analytics runtime identity evidence does not match lifecycle actions"
	end

	if evidence.LoadAnalyticsSpawnEventCount ~= evidence.LoadAnalyticsRuntimeIdentityCount then
		return false, "load analytics spawn evidence is incomplete or duplicated"
	end

	local requiredMotionRecordCount = if evidence.ScenarioId == ScenarioIds.MovingLoad
		then evidence.LoadCount
		elseif evidence.ScenarioId == ScenarioIds.MixedLifecycle then math.max(
			1,
			math.floor(evidence.LoadCount / 2)
		)
		elseif evidence.ScenarioId == ScenarioIds.ControlledCollision then math.min(
			4,
			evidence.LoadCount
		)
		else 0

	if requiredMotionRecordCount > 0 then
		if evidence.MotionPeakRecordCount ~= requiredMotionRecordCount then
			return false, "motion simulator record evidence does not match the scenario"
		end

		if
			evidence.MotionAppliedRecordCount ~= requiredMotionRecordCount
			or evidence.MotionElapsedSeconds < minimumMeasuredSeconds
			or evidence.MotionStepCount < 1
			or evidence.MotionLinearImpulseCount < requiredMotionRecordCount
			or evidence.MotionSkippedRecordCount > 0
		then
			return false, "motion simulator did not sustain representative movement for every cart"
		end
	end

	local requiresActionObservation = false

	if evidence.ScenarioId == ScenarioIds.MixedLifecycle then
		if
			evidence.ResetActionCount < 1
			or evidence.ReplacementActionCount < 1
			or evidence.DestructionActionCount < 1
		then
			return false, "mixed lifecycle requires reset, replacement, and destruction actions"
		end
		requiresActionObservation = true
	elseif
		evidence.ScenarioId == ScenarioIds.ControlledCollision
		and evidence.CollisionActionCount < 1
	then
		return false, "controlled collision has not been executed"
	elseif evidence.ScenarioId == ScenarioIds.RepeatedReset and evidence.ResetActionCount < 2 then
		return false, "repeated reset requires at least two trusted reset actions"
	elseif evidence.ScenarioId == ScenarioIds.ReplacementDespawn then
		if evidence.ReplacementActionCount < 1 or evidence.DestructionActionCount < 1 then
			return false, "replacement/despawn requires both controlled actions"
		end
		requiresActionObservation = true
	elseif evidence.ScenarioId == ScenarioIds.AnalyticsLifecycle then
		if evidence.ResetActionCount < 1 or evidence.MovementViolationActionCount < 1 then
			return false, "analytics lifecycle requires reset and correction actions"
		end

		if evidence.LoadAnalyticsCorrectionEventCount < 1 then
			return false, "load-cart correction analytics evidence is missing"
		end

		if
			evidence.ResetAnalyticsRequestedEventCount < 1
			or evidence.ResetAnalyticsApprovedEventCount < 1
			or evidence.ResetAnalyticsCompletedEventCount < 1
		then
			return false, "authoritative reset analytics sequence is incomplete"
		end
		requiresActionObservation = true
	end

	if
		evidence.ScenarioId == ScenarioIds.ControlledCollision
		or evidence.ScenarioId == ScenarioIds.RepeatedReset
	then
		requiresActionObservation = true
	end

	if
		evidence.ScenarioId == ScenarioIds.ControlledCollision
		and evidence.CollisionContactCount ~= math.min(4, evidence.LoadCount)
	then
		return false, "controlled collision contact evidence is incomplete"
	end

	if
		evidence.ScenarioId == ScenarioIds.LifecycleEndurance
		and evidence.EnduranceCycleCount < CartPerformanceTest.Development.EnduranceCycleCount
	then
		return false, "the configured endurance cycle count has not completed"
	end

	if evidence.ScenarioId == ScenarioIds.LifecycleEndurance then
		requiresActionObservation = true
	end

	if
		requiresActionObservation
		and evidence.PostActionMeasuredSeconds
			< CartPerformanceTest.Development.ActionObservationDuration
	then
		return false, "the configured post-action observation window has not completed"
	end

	return true, nil
end

function CartPerformanceGatePolicy.CanFinalizeCleanup(evidence: CleanupEvidence): (boolean, string?)
	if CartPerformanceTest.ByScenarioId[evidence.ScenarioId] == nil then
		return false, "scenario ID is not registered"
	end

	if not isSupportedLoadCount(evidence.LoadCount) then
		return false, "LoadCount is not a central performance load count"
	end

	for fieldName, value in
		{
			LoadCount = evidence.LoadCount,
			LoadCartCount = evidence.LoadCartCount,
			HarnessSchedulerCount = evidence.HarnessSchedulerCount,
			MotionSchedulerCount = evidence.MotionSchedulerCount,
			CaptureErrorCount = evidence.CaptureErrorCount,
			LifecycleErrorCount = evidence.LifecycleErrorCount,
			MotionErrorCount = evidence.MotionErrorCount,
			LoadAnalyticsRuntimeIdentityCount = evidence.LoadAnalyticsRuntimeIdentityCount,
			LoadAnalyticsSpawnEventCount = evidence.LoadAnalyticsSpawnEventCount,
			LoadAnalyticsDespawnEventCount = evidence.LoadAnalyticsDespawnEventCount,
		}
	do
		if not isFiniteNonnegativeInteger(value) then
			return false, string.format("%s must be a finite nonnegative integer", fieldName)
		end
	end

	if evidence.LoadCartCount ~= 0 then
		return false, "load carts remain after cleanup"
	end

	if evidence.HarnessSchedulerCount ~= 0 or evidence.MotionSchedulerCount ~= 0 then
		return false, "harness schedulers remain after cleanup"
	end

	if
		evidence.CaptureErrorCount > 0
		or evidence.LifecycleErrorCount > 0
		or evidence.MotionErrorCount > 0
	then
		return false, "measurement, lifecycle, or motion errors occurred during the run"
	end

	for _, metricName in LOAD_OWNED_CLEANUP_METRICS do
		local final = evidence.FinalMetrics[metricName]

		if type(final) ~= "number" or not isFiniteNonnegativeNumber(final) then
			return false,
				string.format("load-owned cleanup metric %s is missing or invalid", metricName)
		end

		if final ~= 0 then
			return false,
				string.format("load-owned cleanup metric %s retained harness state", metricName)
		end
	end

	for _, metricName in CLEANUP_BOUNDED_METRICS do
		local baseline = evidence.BaselineMetrics[metricName]
		local final = evidence.FinalMetrics[metricName]

		if
			type(baseline) ~= "number"
			or not isFiniteNonnegativeNumber(baseline)
			or type(final) ~= "number"
			or not isFiniteNonnegativeNumber(final)
		then
			return false, string.format("cleanup metric %s is missing or invalid", metricName)
		end

		if final > baseline then
			return false, string.format("cleanup metric %s did not return to baseline", metricName)
		end
	end

	for _, metricName in CLEANUP_STABLE_SHARED_METRICS do
		local baseline = evidence.BaselineMetrics[metricName]
		local final = evidence.FinalMetrics[metricName]

		if
			type(baseline) ~= "number"
			or not isFiniteNonnegativeNumber(baseline)
			or type(final) ~= "number"
			or not isFiniteNonnegativeNumber(final)
		then
			return false, string.format("shared metric %s is missing or invalid", metricName)
		end

		if baseline ~= final then
			return false, string.format("shared metric %s changed across the run", metricName)
		end
	end

	if evidence.LoadAnalyticsRuntimeIdentityCount < evidence.LoadCount then
		return false, "load analytics runtime identity evidence is incomplete"
	end

	if
		evidence.LoadAnalyticsSpawnEventCount ~= evidence.LoadAnalyticsRuntimeIdentityCount
		or evidence.LoadAnalyticsDespawnEventCount ~= evidence.LoadAnalyticsRuntimeIdentityCount
	then
		return false, "attributed spawn/despawn analytics evidence is incomplete or duplicated"
	end

	return true, nil
end

return table.freeze(CartPerformanceGatePolicy)
