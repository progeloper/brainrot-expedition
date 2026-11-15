--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartPerformanceTest = require(ReplicatedStorage.Shared.Config.CartPerformanceTest)
	local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartPerformanceScenarioIds)
	local CartPerformanceGatePolicy =
		require(ReplicatedStorage.Shared.Utility.CartPerformanceGatePolicy)
	local CartPerformanceSnapshot =
		require(ReplicatedStorage.Shared.Utility.CartPerformanceSnapshot)

	local CLEANUP_BOUNDED_METRICS = {
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
	}
	local CLEANUP_SHARED_METRICS = {
		"TerrainSharedConnections",
		"StabilitySharedConnections",
		"LongitudinalSharedConnections",
		"ValidatorSharedConnections",
		"AnalyticsSharedConnections",
		"ResetSecurityConnections",
	}
	local LOAD_OWNED_CLEANUP_METRICS = {
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
	}

	local function evidence(scenarioId: string)
		local replacementActionCount = if scenarioId == ScenarioIds.ReplacementDespawn
				or scenarioId == ScenarioIds.MixedLifecycle
			then 1
			else 0
		local enduranceCycleCount = if scenarioId == ScenarioIds.LifecycleEndurance
			then CartPerformanceTest.Development.EnduranceCycleCount
			else 0
		local motionRecordCount = if scenarioId == ScenarioIds.MovingLoad
			then 12
			elseif scenarioId == ScenarioIds.MixedLifecycle then 6
			elseif scenarioId == ScenarioIds.ControlledCollision then 4
			else 0
		local runtimeIdentityCount = 12 + replacementActionCount + enduranceCycleCount * 12

		return {
			ScenarioId = scenarioId,
			Stage = CartPerformanceSnapshot.Stages.LifecycleStress,
			LoadCount = 12,
			LiveLoadCartCount = 12,
			ValidAssemblyCount = 12,
			FiniteRootCount = 12,
			PhysicalRootCount = 12,
			ServerOwnedRootCount = 12,
			LoadAssemblyRecordCount = 12,
			LoadOccupantRecordCount = 12,
			LoadTerrainRecordCount = 12,
			LoadStabilityRecordCount = 12,
			LoadLongitudinalRecordCount = 12,
			LoadValidatorRecordCount = 12,
			LoadAnalyticsRecordCount = 12,
			SteadyStateMeasuredSeconds = CartPerformanceTest.Development.SteadyStateDuration,
			SteadyStatePeriodicSnapshotCount = math.floor(
				CartPerformanceTest.Development.SteadyStateDuration
					/ CartPerformanceTest.Development.SnapshotInterval
			),
			PostActionMeasuredSeconds = CartPerformanceTest.Development.ActionObservationDuration,
			CollisionActionCount = 1,
			CollisionContactCount = if scenarioId == ScenarioIds.ControlledCollision then 4 else 0,
			MovementViolationActionCount = 1,
			ResetActionCount = 2,
			ReplacementActionCount = replacementActionCount,
			DestructionActionCount = 1,
			EnduranceCycleCount = enduranceCycleCount,
			CaptureErrorCount = 0,
			LifecycleErrorCount = 0,
			MotionErrorCount = 0,
			MotionElapsedSeconds = if motionRecordCount > 0
				then CartPerformanceTest.Development.SteadyStateDuration
				else 0,
			MotionPeakRecordCount = motionRecordCount,
			MotionAppliedRecordCount = motionRecordCount,
			MotionStepCount = if motionRecordCount > 0
				then math.floor(
					CartPerformanceTest.Development.SteadyStateDuration
						/ CartPerformanceTest.Development.SnapshotInterval
				)
				else 0,
			MotionLinearImpulseCount = motionRecordCount,
			MotionSkippedRecordCount = 0,
			LoadAnalyticsRuntimeIdentityCount = runtimeIdentityCount,
			LoadAnalyticsSpawnEventCount = runtimeIdentityCount,
			LoadAnalyticsCorrectionEventCount = 1,
			ResetAnalyticsRequestedEventCount = 1,
			ResetAnalyticsApprovedEventCount = 1,
			ResetAnalyticsCompletedEventCount = 1,
		}
	end

	local function cleanupEvidence(scenarioId: string)
		local baselineMetrics = {}
		local finalMetrics = {}

		for _, metricName in CLEANUP_BOUNDED_METRICS do
			baselineMetrics[metricName] = 3
			finalMetrics[metricName] = 3
		end

		for _, metricName in CLEANUP_SHARED_METRICS do
			baselineMetrics[metricName] = 1
			finalMetrics[metricName] = 1
		end

		for _, metricName in LOAD_OWNED_CLEANUP_METRICS do
			finalMetrics[metricName] = 0
		end

		return {
			ScenarioId = scenarioId,
			LoadCount = 12,
			LoadCartCount = 0,
			HarnessSchedulerCount = 0,
			MotionSchedulerCount = 0,
			CaptureErrorCount = 0,
			LifecycleErrorCount = 0,
			MotionErrorCount = 0,
			LoadAnalyticsRuntimeIdentityCount = 12,
			LoadAnalyticsSpawnEventCount = 12,
			LoadAnalyticsDespawnEventCount = 12,
			BaselineMetrics = baselineMetrics,
			FinalMetrics = finalMetrics,
		}
	end

	describe("CartPerformanceGatePolicy", function()
		it("enforces configured warm-up and steady-state durations", function()
			local warmupEarly = CartPerformanceGatePolicy.CanTransition(
				CartPerformanceSnapshot.Stages.Warmup,
				CartPerformanceSnapshot.Stages.SteadyState,
				CartPerformanceTest.Development.WarmupDuration - 0.001
			)
			local warmupReady = CartPerformanceGatePolicy.CanTransition(
				CartPerformanceSnapshot.Stages.Warmup,
				CartPerformanceSnapshot.Stages.SteadyState,
				CartPerformanceTest.Development.WarmupDuration
			)
			local steadyEarly = CartPerformanceGatePolicy.CanTransition(
				CartPerformanceSnapshot.Stages.SteadyState,
				CartPerformanceSnapshot.Stages.LifecycleStress,
				CartPerformanceTest.Development.SteadyStateDuration - 0.001
			)
			local steadyReady = CartPerformanceGatePolicy.CanTransition(
				CartPerformanceSnapshot.Stages.SteadyState,
				CartPerformanceSnapshot.Stages.LifecycleStress,
				CartPerformanceTest.Development.SteadyStateDuration
			)

			expect(warmupEarly).to.equal(false)
			expect(warmupReady).to.equal(true)
			expect(steadyEarly).to.equal(false)
			expect(steadyReady).to.equal(true)
		end)

		it("rejects skipped, reversed, and non-finite stage transitions", function()
			local skipped = CartPerformanceGatePolicy.CanTransition(
				CartPerformanceSnapshot.Stages.Warmup,
				CartPerformanceSnapshot.Stages.LifecycleStress,
				999
			)
			local reversed = CartPerformanceGatePolicy.CanTransition(
				CartPerformanceSnapshot.Stages.SteadyState,
				CartPerformanceSnapshot.Stages.Warmup,
				999
			)
			local invalid = CartPerformanceGatePolicy.CanTransition(
				CartPerformanceSnapshot.Stages.Warmup,
				CartPerformanceSnapshot.Stages.SteadyState,
				0 / 0
			)

			expect(skipped).to.equal(false)
			expect(reversed).to.equal(false)
			expect(invalid).to.equal(false)
		end)

		it("permits complete stationary pass evidence", function()
			local allowed = CartPerformanceGatePolicy.CanPass(evidence(ScenarioIds.StationaryLoad))

			expect(allowed).to.equal(true)
		end)

		it("requires measured steady-state heartbeat and snapshot coverage", function()
			local missingTime = evidence(ScenarioIds.StationaryLoad)
			missingTime.SteadyStateMeasuredSeconds = 0
			local missingSnapshots = evidence(ScenarioIds.StationaryLoad)
			missingSnapshots.SteadyStatePeriodicSnapshotCount = 0

			expect(CartPerformanceGatePolicy.CanPass(missingTime)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(missingSnapshots)).to.equal(false)
		end)

		it("evaluates every endurance cleanup before permitting a restart", function()
			local complete = cleanupEvidence(ScenarioIds.LifecycleEndurance)
			local cleanup = {
				LoadCount = complete.LoadCount,
				RuntimeActiveCount = 0,
				LoadCartCount = 0,
				MotionSchedulerCount = 0,
				LoadAnalyticsRuntimeIdentityCount = complete.LoadAnalyticsRuntimeIdentityCount,
				LoadAnalyticsSpawnEventCount = complete.LoadAnalyticsSpawnEventCount,
				LoadAnalyticsDespawnEventCount = complete.LoadAnalyticsDespawnEventCount,
				Metrics = complete.FinalMetrics,
			}

			expect(CartPerformanceGatePolicy.CanRestartEnduranceCycle(cleanup)).to.equal(true)

			cleanup.Metrics.OwnedLoadValidatorRecords = 1

			expect(CartPerformanceGatePolicy.CanRestartEnduranceCycle(cleanup)).to.equal(false)
		end)

		it("requires every endurance reload to restore the complete active load", function()
			local complete = evidence(ScenarioIds.LifecycleEndurance)
			local reload = {
				LoadCount = complete.LoadCount,
				RuntimeActiveCount = complete.LoadCount,
				LiveLoadCartCount = complete.LiveLoadCartCount,
				ValidAssemblyCount = complete.ValidAssemblyCount,
				FiniteRootCount = complete.FiniteRootCount,
				PhysicalRootCount = complete.PhysicalRootCount,
				ServerOwnedRootCount = complete.ServerOwnedRootCount,
				LoadAssemblyRecordCount = complete.LoadAssemblyRecordCount,
				LoadOccupantRecordCount = complete.LoadOccupantRecordCount,
				LoadTerrainRecordCount = complete.LoadTerrainRecordCount,
				LoadStabilityRecordCount = complete.LoadStabilityRecordCount,
				LoadLongitudinalRecordCount = complete.LoadLongitudinalRecordCount,
				LoadValidatorRecordCount = complete.LoadValidatorRecordCount,
				LoadAnalyticsRecordCount = complete.LoadAnalyticsRecordCount,
				LoadAnalyticsRuntimeIdentityCount = complete.LoadAnalyticsRuntimeIdentityCount,
				LoadAnalyticsSpawnEventCount = complete.LoadAnalyticsSpawnEventCount,
			}

			expect(CartPerformanceGatePolicy.CanContinueEnduranceCycle(reload)).to.equal(true)

			reload.LoadTerrainRecordCount -= 1

			expect(CartPerformanceGatePolicy.CanContinueEnduranceCycle(reload)).to.equal(false)
		end)

		it("requires the correct controlled action for each scenario", function()
			local collision = evidence(ScenarioIds.ControlledCollision)
			collision.CollisionActionCount = 0
			local reset = evidence(ScenarioIds.RepeatedReset)
			reset.ResetActionCount = 1
			local replacement = evidence(ScenarioIds.ReplacementDespawn)
			replacement.DestructionActionCount = 0
			local mixed = evidence(ScenarioIds.MixedLifecycle)
			mixed.ResetActionCount = 0

			expect(CartPerformanceGatePolicy.CanPass(collision)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(reset)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(replacement)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(mixed)).to.equal(false)
		end)

		it("requires analytics actions and cart-attributed event evidence", function()
			local missingAction = evidence(ScenarioIds.AnalyticsLifecycle)
			missingAction.MovementViolationActionCount = 0
			local missingCorrection = evidence(ScenarioIds.AnalyticsLifecycle)
			missingCorrection.LoadAnalyticsCorrectionEventCount = 0
			local missingReset = evidence(ScenarioIds.AnalyticsLifecycle)
			missingReset.ResetAnalyticsCompletedEventCount = 0

			expect(CartPerformanceGatePolicy.CanPass(missingAction)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(missingCorrection)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(missingReset)).to.equal(false)
		end)

		it("requires all configured endurance cycles", function()
			local request = evidence(ScenarioIds.LifecycleEndurance)
			request.EnduranceCycleCount = CartPerformanceTest.Development.EnduranceCycleCount - 1

			local early = CartPerformanceGatePolicy.CanPass(request)
			request.EnduranceCycleCount = CartPerformanceTest.Development.EnduranceCycleCount
			local complete = CartPerformanceGatePolicy.CanPass(request)

			expect(early).to.equal(false)
			expect(complete).to.equal(true)
		end)

		it("requires every load cart and per-cart service record", function()
			local missingCart = evidence(ScenarioIds.StationaryLoad)
			missingCart.LiveLoadCartCount = 11
			local missingValidator = evidence(ScenarioIds.StationaryLoad)
			missingValidator.LoadValidatorRecordCount = 11

			expect(CartPerformanceGatePolicy.CanPass(missingCart)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(missingValidator)).to.equal(false)
		end)

		it("requires lifecycle-correlated analytics identities without duplicates", function()
			local missingIdentity = evidence(ScenarioIds.ReplacementDespawn)

			missingIdentity.LoadAnalyticsRuntimeIdentityCount -= 1
			missingIdentity.LoadAnalyticsSpawnEventCount -= 1
			local duplicateSpawn = evidence(ScenarioIds.StationaryLoad)

			duplicateSpawn.LoadAnalyticsSpawnEventCount += 1

			expect(CartPerformanceGatePolicy.CanPass(missingIdentity)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(duplicateSpawn)).to.equal(false)
		end)

		it("requires real motion application and post-action observation", function()
			local inactive = evidence(ScenarioIds.MovingLoad)

			inactive.MotionAppliedRecordCount = 0
			local skipped = evidence(ScenarioIds.MovingLoad)

			skipped.MotionSkippedRecordCount = 1
			local shortLived = evidence(ScenarioIds.MovingLoad)

			shortLived.MotionElapsedSeconds = 1
			local unobserved = evidence(ScenarioIds.ControlledCollision)

			unobserved.PostActionMeasuredSeconds = 0
			local noContact = evidence(ScenarioIds.ControlledCollision)

			noContact.CollisionContactCount = 0

			expect(CartPerformanceGatePolicy.CanPass(inactive)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(skipped)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(shortLived)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(unobserved)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(noContact)).to.equal(false)
		end)

		it("rejects capture, lifecycle, or motion errors and malformed counters", function()
			local captureRequest = evidence(ScenarioIds.MovingLoad)
			captureRequest.CaptureErrorCount = 1
			local lifecycleRequest = evidence(ScenarioIds.MovingLoad)
			lifecycleRequest.LifecycleErrorCount = 1
			local motionRequest = evidence(ScenarioIds.MovingLoad)
			motionRequest.MotionErrorCount = 1
			local malformedRequest = evidence(ScenarioIds.MovingLoad)
			malformedRequest.CollisionActionCount = math.huge

			expect(CartPerformanceGatePolicy.CanPass(captureRequest)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(lifecycleRequest)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(motionRequest)).to.equal(false)
			expect(CartPerformanceGatePolicy.CanPass(malformedRequest)).to.equal(false)
		end)

		it("accepts bounded post-cleanup state with complete lifecycle events", function()
			local allowed = CartPerformanceGatePolicy.CanFinalizeCleanup(
				cleanupEvidence(ScenarioIds.StationaryLoad)
			)

			expect(allowed).to.equal(true)
		end)

		it(
			"rejects retained owned state, schedulers, capture errors, and missing events",
			function()
				local retained = cleanupEvidence(ScenarioIds.StationaryLoad)
				retained.FinalMetrics.ValidatorRecords = 2
				retained.FinalMetrics.OwnedLoadValidatorRecords = 1
				local scheduler = cleanupEvidence(ScenarioIds.StationaryLoad)
				scheduler.HarnessSchedulerCount = 1
				local capture = cleanupEvidence(ScenarioIds.StationaryLoad)
				capture.CaptureErrorCount = 1
				local events = cleanupEvidence(ScenarioIds.StationaryLoad)
				events.LoadAnalyticsDespawnEventCount = 11

				expect(CartPerformanceGatePolicy.CanFinalizeCleanup(retained)).to.equal(false)
				expect(CartPerformanceGatePolicy.CanFinalizeCleanup(scheduler)).to.equal(false)
				expect(CartPerformanceGatePolicy.CanFinalizeCleanup(capture)).to.equal(false)
				expect(CartPerformanceGatePolicy.CanFinalizeCleanup(events)).to.equal(false)
			end
		)
	end)
end
