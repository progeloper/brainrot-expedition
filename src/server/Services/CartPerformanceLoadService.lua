--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialPolicy = require(ReplicatedStorage.Shared.Utility.EnvironmentStudMaterialPolicy)
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local CartGreybox = require(ReplicatedStorage.Shared.Config.CartGreybox)
local CartPerformanceTest = require(ReplicatedStorage.Shared.Config.CartPerformanceTest)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local CartGreyboxPerformanceIds =
	require(ReplicatedStorage.Shared.Constants.CartGreyboxPerformanceIds)
local CartGreyboxViolationIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxViolationIds)
local AnalyticsEvents = require(ReplicatedStorage.Shared.Constants.AnalyticsEvents)
local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartPerformanceScenarioIds)
local CartPerformanceResult = require(ReplicatedStorage.Shared.Utility.CartPerformanceResult)
local CartPerformanceGatePolicy =
	require(ReplicatedStorage.Shared.Utility.CartPerformanceGatePolicy)
local CartPerformanceSnapshot = require(ReplicatedStorage.Shared.Utility.CartPerformanceSnapshot)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local CartPerformanceConfigValidator =
	require(ReplicatedStorage.Shared.Validation.CartPerformanceConfigValidator)

local CartPerformanceLoadRuntime = require(script.Parent.Parent.Utility.CartPerformanceLoadRuntime)
local CartPerformanceMotionSimulator =
	require(script.Parent.Parent.Utility.CartPerformanceMotionSimulator)
local CartModelUtility = require(script.Parent.Parent.Utility.CartModelUtility)
local CartGreyboxAnalyticsSink = require(script.Parent.Parent.Utility.CartGreyboxAnalyticsSink)
local CartAnalyticsService = require(script.Parent.CartAnalyticsService)
local CartAssemblyValidationService = require(script.Parent.CartAssemblyValidationService)
local CartLongitudinalStateService = require(script.Parent.CartLongitudinalStateService)
local CartMovementValidationService = require(script.Parent.CartMovementValidationService)
local CartOccupantService = require(script.Parent.CartOccupantService)
local CartResetRequestService = require(script.Parent.CartResetRequestService)
local CartResetService = require(script.Parent.CartResetService)
local CartService = require(script.Parent.CartService)
local CartStabilityService = require(script.Parent.CartStabilityService)
local CartTerrainService = require(script.Parent.CartTerrainService)
local CartGreyboxRouteSystem = require(script.Parent.Parent.Systems.CartGreyboxRouteSystem)

type LoadRuntime = CartPerformanceLoadRuntime.Runtime
type MotionSimulator = CartPerformanceMotionSimulator.Simulator
type Result = CartPerformanceResult.Result
type Snapshot = CartPerformanceSnapshot.Snapshot
type SnapshotBuffer = CartPerformanceSnapshot.Buffer
type SnapshotStage = CartPerformanceSnapshot.Stage

type Inventory = {
	Descendants: number,
	Parts: number,
	Constraints: number,
	Attachments: number,
}

type ActiveRun = {
	ScenarioId: string,
	LoadCount: number,
	StartedAt: number,
	Stage: SnapshotStage,
	StageStartedAt: number,
	Runtime: LoadRuntime,
	ModelsByIndex: { [number]: Model },
	OwnerUserIdsByIndex: { [number]: number },
	AllLoadModels: { [Model]: boolean },
	LoadOwnerUserIds: { [number]: boolean },
	LoadAnalyticsRuntimeIds: { [string]: boolean },
	ResetAnalyticsBaselines: { [string]: { [string]: number } },
	CorrectionAnalyticsBaselines: { [string]: number },
	ResetSecurityTestUserIds: { [number]: boolean },
	CollisionFixtureParts: { BasePart },
	CollisionFixtureConnections: { RBXScriptConnection },
	CollisionContactModels: { [Model]: boolean },
	CollisionContactCount: number,
	SpawnIds: { string },
	InventoryByIndex: { [number]: Inventory },
	BaselineMetrics: { [string]: number },
	Snapshots: SnapshotBuffer,
	MotionSimulator: MotionSimulator?,
	MeasurementConnection: RBXScriptConnection?,
	MeasurementAccumulator: number,
	HeartbeatCount: number,
	HeartbeatTotalDelta: number,
	HeartbeatMaximumDelta: number,
	SteadyStateMeasuredSeconds: number,
	SteadyStatePeriodicSnapshotCount: number,
	PostActionMeasuredSeconds: number,
	AnalyticsEventBaseline: number,
	CaptureErrorCount: number,
	LastCaptureError: string?,
	LifecycleErrorCount: number,
	LastLifecycleError: string?,
	MotionErrorCount: number,
	MotionElapsedSeconds: number,
	MotionPeakRecordCount: number,
	MotionAppliedRecordCount: number,
	MotionStepCount: number,
	MotionLinearImpulseCount: number,
	MotionAngularImpulseCount: number,
	MotionSkippedRecordCount: number,
	ScenarioActionCount: number,
	CollisionActionCount: number,
	MovementViolationActionCount: number,
	ResetActionCount: number,
	ReplacementActionCount: number,
	DestructionActionCount: number,
	EnduranceCycleCount: number,
}

local log = Logger.new("CartPerformanceLoadService")
local CartPerformanceLoadService = {}

local started = false
local activeRun: ActiveRun? = nil
local lastResult: Result? = nil

local VALID_RESULT_STATUSES = table.freeze({
	Passed = true,
	Failed = true,
	Blocked = true,
})

local VALID_RESULT_SEVERITIES = table.freeze({
	S0 = true,
	S1 = true,
	S2 = true,
	S3 = true,
})

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isFiniteVector(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function isFiniteCFrame(value: CFrame): boolean
	for _, component in { value:GetComponents() } do
		if not isFiniteNumber(component) then
			return false
		end
	end

	return true
end

local function countInventory(cart: Model): Inventory
	local inventory: Inventory = {
		Descendants = 0,
		Parts = 0,
		Constraints = 0,
		Attachments = 0,
	}

	-- This lifecycle-only inventory pass is cached. It never runs from the
	-- measurement Heartbeat or a gameplay scheduler.
	for _, descendant in cart:GetDescendants() do
		inventory.Descendants += 1

		if descendant:IsA("BasePart") then
			inventory.Parts += 1
		elseif descendant:IsA("Constraint") then
			inventory.Constraints += 1
		elseif descendant:IsA("Attachment") then
			inventory.Attachments += 1
		end
	end

	return inventory
end

local function getMemoryUsageMb(): number?
	local succeeded, value = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)

	return if succeeded and isFiniteNumber(value) and value >= 0 then value else nil
end

local function getInstanceCount(): number?
	local succeeded, value = pcall(function()
		return Stats.InstanceCount
	end)

	return if succeeded and isFiniteNumber(value) and value >= 0 then value else nil
end

local function countTable(values: { [any]: any }): number
	local count = 0

	for _ in values do
		count += 1
	end

	return count
end

local function isSupportedLoadCount(loadCount: number): boolean
	if not isFiniteNumber(loadCount) or loadCount % 1 ~= 0 then
		return false
	end

	for _, supported in CartPerformanceTest.LoadCounts do
		if loadCount == supported then
			return true
		end
	end

	return false
end

local function trackLoadCart(run: ActiveRun, ownerUserId: number, cart: Model)
	run.AllLoadModels[cart] = true
	run.LoadOwnerUserIds[ownerUserId] = true

	local analyticsSnapshot = CartAnalyticsService:GetSnapshot(cart)

	assert(analyticsSnapshot ~= nil, "load cart analytics record is unavailable")
	assert(analyticsSnapshot.RuntimeCartId ~= "", "load cart analytics runtime ID is empty")
	run.LoadAnalyticsRuntimeIds[analyticsSnapshot.RuntimeCartId] = true
end

local function trackResetAnalyticsBaseline(run: ActiveRun, cart: Model)
	local analyticsSnapshot = CartAnalyticsService:GetSnapshot(cart)

	assert(analyticsSnapshot ~= nil, "reset cart analytics record is unavailable")

	local runtimeCartId = analyticsSnapshot.RuntimeCartId

	if run.ResetAnalyticsBaselines[runtimeCartId] ~= nil then
		return
	end

	run.ResetAnalyticsBaselines[runtimeCartId] = {
		[AnalyticsEvents.CartResetRequested] = CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(
			runtimeCartId,
			AnalyticsEvents.CartResetRequested
		),
		[AnalyticsEvents.CartResetApproved] = CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(
			runtimeCartId,
			AnalyticsEvents.CartResetApproved
		),
		[AnalyticsEvents.CartResetCompleted] = CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(
			runtimeCartId,
			AnalyticsEvents.CartResetCompleted
		),
	}
end

local function countLoadAnalyticsEvents(run: ActiveRun, eventName: string): number
	local count = 0

	for runtimeCartId in run.LoadAnalyticsRuntimeIds do
		count += CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(runtimeCartId, eventName)
	end

	return count
end

local function countResetAnalyticsEvents(run: ActiveRun, eventName: string): number
	local count = 0

	for runtimeCartId, baselines in run.ResetAnalyticsBaselines do
		count += math.max(
			0,
			CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(runtimeCartId, eventName)
				- (baselines[eventName] or 0)
		)
	end

	return count
end

local function trackCorrectionAnalyticsBaseline(
	run: ActiveRun,
	cart: Model
): (string, number?)
	local analyticsSnapshot = CartAnalyticsService:GetSnapshot(cart)

	assert(analyticsSnapshot ~= nil, "correction cart analytics record is unavailable")

	local runtimeCartId = analyticsSnapshot.RuntimeCartId
	local previousBaseline = run.CorrectionAnalyticsBaselines[runtimeCartId]

	run.CorrectionAnalyticsBaselines[runtimeCartId] =
		CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(
			runtimeCartId,
			AnalyticsEvents.CartMovementCorrected
		)

	return runtimeCartId, previousBaseline
end

local function countCorrectionAnalyticsEvents(run: ActiveRun): number
	local count = 0

	for runtimeCartId, baseline in run.CorrectionAnalyticsBaselines do
		count += math.max(
			0,
			CartGreyboxAnalyticsSink.GetRuntimeCartEventCount(
				runtimeCartId,
				AnalyticsEvents.CartMovementCorrected
			) - baseline
		)
	end

	return count
end

local function recordScenarioAction(run: ActiveRun)
	run.ScenarioActionCount += 1
	run.PostActionMeasuredSeconds = 0
end

local function collectMetrics(run: ActiveRun): { [string]: number }
	local metrics: { [string]: number } = {}
	local allCartRecords = CartService:GetCartRecords()
	local liveLoadCartCount = 0
	local validAssemblyCount = 0
	local finiteRootCount = 0
	local physicalRootCount = 0
	local serverOwnedRootCount = 0
	local loadAssemblyRecordCount = 0
	local loadOccupantRecordCount = 0
	local loadTerrainRecordCount = 0
	local loadStabilityRecordCount = 0
	local loadLongitudinalRecordCount = 0
	local loadValidatorRecordCount = 0
	local loadAnalyticsRecordCount = 0
	local ownedLoadCartRecordCount = 0
	local ownedLoadParentedModelCount = 0
	local ownedLoadAssemblyRecordCount = 0
	local ownedLoadOccupantRecordCount = 0
	local ownedLoadTerrainRecordCount = 0
	local ownedLoadStabilityRecordCount = 0
	local ownedLoadLongitudinalRecordCount = 0
	local ownedLoadValidatorRecordCount = 0
	local ownedLoadAnalyticsRecordCount = 0
	local inventoryParts = 0
	local inventoryConstraints = 0
	local inventoryAttachments = 0
	local inventoryDescendants = 0

	for index, cart in run.ModelsByIndex do
		if CartAssemblyValidationService:GetState(cart) ~= nil then
			loadAssemblyRecordCount += 1
		end

		if CartOccupantService:IsCartRegistered(cart) then
			loadOccupantRecordCount += 1
		end

		if CartTerrainService:IsCartRegistered(cart) then
			loadTerrainRecordCount += 1
		end

		if CartStabilityService:IsCartRegistered(cart) then
			loadStabilityRecordCount += 1
		end

		if CartLongitudinalStateService:IsCartRegistered(cart) then
			loadLongitudinalRecordCount += 1
		end

		if CartMovementValidationService:GetSnapshot(cart) ~= nil then
			loadValidatorRecordCount += 1
		end

		if CartAnalyticsService:GetSnapshot(cart) ~= nil then
			loadAnalyticsRecordCount += 1
		end

		if cart.Parent ~= nil and cart:GetAttribute("DevelopmentLoadCart") == true then
			liveLoadCartCount += 1

			if CartAssemblyValidationService:IsCartValid(cart) then
				validAssemblyCount += 1
			end

			local rootSucceeded, rootOrError = pcall(CartModelUtility.GetRoot, cart)

			if rootSucceeded then
				local root = rootOrError :: BasePart

				if
					isFiniteCFrame(root.CFrame)
					and isFiniteVector(root.AssemblyLinearVelocity)
					and isFiniteVector(root.AssemblyAngularVelocity)
				then
					finiteRootCount += 1
				end

				if not root.Anchored then
					physicalRootCount += 1
				end

				local ownerSucceeded, owner = pcall(function()
					return root:GetNetworkOwner()
				end)

				if ownerSucceeded and owner == nil then
					serverOwnedRootCount += 1
				end
			end
		end

		local inventory = run.InventoryByIndex[index]

		if inventory ~= nil then
			inventoryParts += inventory.Parts
			inventoryConstraints += inventory.Constraints
			inventoryAttachments += inventory.Attachments
			inventoryDescendants += inventory.Descendants
		end
	end

	for ownerUserId in run.LoadOwnerUserIds do
		if CartService:GetCartRecordByOwnerUserId(ownerUserId) ~= nil then
			ownedLoadCartRecordCount += 1
		end
	end

	-- Weak historical keys do not retain cleaned carts. Any key that remains here
	-- is either still parented or retained by another load-owned runtime record.
	for cart in run.AllLoadModels do
		if cart.Parent ~= nil then
			ownedLoadParentedModelCount += 1
		end

		if CartAssemblyValidationService:GetState(cart) ~= nil then
			ownedLoadAssemblyRecordCount += 1
		end

		if CartOccupantService:IsCartRegistered(cart) then
			ownedLoadOccupantRecordCount += 1
		end

		if CartTerrainService:IsCartRegistered(cart) then
			ownedLoadTerrainRecordCount += 1
		end

		if CartStabilityService:IsCartRegistered(cart) then
			ownedLoadStabilityRecordCount += 1
		end

		if CartLongitudinalStateService:IsCartRegistered(cart) then
			ownedLoadLongitudinalRecordCount += 1
		end

		if CartMovementValidationService:GetSnapshot(cart) ~= nil then
			ownedLoadValidatorRecordCount += 1
		end

		if CartAnalyticsService:GetSnapshot(cart) ~= nil then
			ownedLoadAnalyticsRecordCount += 1
		end
	end

	local assembly = CartAssemblyValidationService:GetDiagnostics()
	local occupants = CartOccupantService:GetDiagnostics()
	local terrain = CartTerrainService:GetDiagnostics()
	local stability = CartStabilityService:GetDiagnostics()
	local longitudinal = CartLongitudinalStateService:GetDiagnostics()
	local validator = CartMovementValidationService:GetDiagnostics()
	local analytics = CartAnalyticsService:GetDiagnostics()
	local resets = CartResetService:GetDiagnostics()
	local resetSecurity = CartResetRequestService:GetDiagnostics()
	local motion = if run.MotionSimulator ~= nil
		then (run.MotionSimulator :: MotionSimulator):GetDiagnostics()
		else nil

	metrics.CartRecords = #allCartRecords
	metrics.LoadCartRecords = liveLoadCartCount
	metrics.ValidLoadAssemblies = validAssemblyCount
	metrics.FiniteLoadRoots = finiteRootCount
	metrics.PhysicalLoadRoots = physicalRootCount
	metrics.ServerOwnedLoadRoots = serverOwnedRootCount
	metrics.LoadAssemblyRecords = loadAssemblyRecordCount
	metrics.LoadOccupantRecords = loadOccupantRecordCount
	metrics.LoadTerrainRecords = loadTerrainRecordCount
	metrics.LoadStabilityRecords = loadStabilityRecordCount
	metrics.LoadLongitudinalRecords = loadLongitudinalRecordCount
	metrics.LoadValidatorRecords = loadValidatorRecordCount
	metrics.LoadAnalyticsRecords = loadAnalyticsRecordCount
	metrics.OwnedLoadCartRecords = ownedLoadCartRecordCount
	metrics.OwnedLoadParentedModels = ownedLoadParentedModelCount
	metrics.OwnedLoadAssemblyRecords = ownedLoadAssemblyRecordCount
	metrics.OwnedLoadOccupantRecords = ownedLoadOccupantRecordCount
	metrics.OwnedLoadTerrainRecords = ownedLoadTerrainRecordCount
	metrics.OwnedLoadStabilityRecords = ownedLoadStabilityRecordCount
	metrics.OwnedLoadLongitudinalRecords = ownedLoadLongitudinalRecordCount
	metrics.OwnedLoadValidatorRecords = ownedLoadValidatorRecordCount
	metrics.OwnedLoadAnalyticsRecords = ownedLoadAnalyticsRecordCount
	metrics.AssemblyRecords = assembly.RecordCount
	metrics.AssemblyRecordConnections = assembly.RecordConnectionCount
	metrics.AssemblyRetainedConnectionObjects = assembly.RetainedConnectionObjectCount
	metrics.AssemblyObservedInstances = assembly.ObservedInstanceCount
	metrics.AssemblyRetainedObservedInstances = assembly.RetainedObservedInstanceCount
	metrics.OccupantRecords = occupants.RecordCount
	metrics.OccupantRecordConnections = occupants.CartConnectionCount
		+ occupants.DriverConnectionCount
	metrics.TerrainRecords = terrain.RecordCount
	metrics.TerrainRecordConnections = terrain.RecordConnectionCount
	metrics.TerrainSharedConnections = terrain.SharedConnectionCount
	metrics.TerrainSchedulers = terrain.SchedulerCount
	metrics.TerrainSamples = terrain.TotalSampleCount
	metrics.StabilityRecords = stability.RecordCount
	metrics.StabilityRecordConnections = stability.RecordConnectionCount
	metrics.StabilityRetainedConnectionObjects = stability.RetainedConnectionObjectCount
	metrics.StabilitySharedConnections = stability.SharedConnectionCount
	metrics.StabilitySchedulers = stability.SchedulerCount
	metrics.StabilityManagedTorques = stability.ManagedTorqueCount
	metrics.LongitudinalRecords = longitudinal.RecordCount
	metrics.LongitudinalDriverRecords = longitudinal.DriverRecordCount
	metrics.LongitudinalRecordConnections = longitudinal.RecordConnectionCount
	metrics.LongitudinalSharedConnections = longitudinal.SharedConnectionCount
	metrics.ValidatorRecords = validator.RecordCount
	metrics.ValidatorRecordConnections = validator.RecordConnectionCount
	metrics.ValidatorSharedConnections = validator.SharedConnectionCount
	metrics.ValidatorSchedulers = validator.SchedulerCount
	metrics.ValidatorSampleCycles = validator.SampleCycleCount
	metrics.ValidatorProcessedRecords = validator.ProcessedRecordCount
	metrics.ValidatorCorrections = validator.CorrectionAppliedCount
	metrics.AnalyticsRecords = analytics.RecordCount
	metrics.AnalyticsSharedConnections = analytics.SharedConnectionCount
	metrics.AnalyticsEventDelta =
		math.max(0, CartGreyboxAnalyticsSink.GetTotalEmittedCount() - run.AnalyticsEventBaseline)
	metrics.LoadAnalyticsRuntimeIdentities = countTable(run.LoadAnalyticsRuntimeIds)
	metrics.LoadAnalyticsSpawnEvents = countLoadAnalyticsEvents(run, AnalyticsEvents.CartSpawned)
	metrics.LoadAnalyticsDespawnEvents =
		countLoadAnalyticsEvents(run, AnalyticsEvents.CartDespawned)
	metrics.LoadAnalyticsCorrectionEvents = countCorrectionAnalyticsEvents(run)
	metrics.ResetAnalyticsRequestedEvents =
		countResetAnalyticsEvents(run, AnalyticsEvents.CartResetRequested)
	metrics.ResetAnalyticsApprovedEvents =
		countResetAnalyticsEvents(run, AnalyticsEvents.CartResetApproved)
	metrics.ResetAnalyticsCompletedEvents =
		countResetAnalyticsEvents(run, AnalyticsEvents.CartResetCompleted)
	metrics.ResetPlayerRecords = resets.PlayerRecordCount
	metrics.ResetCartRecords = resets.CartRecordCount
	metrics.ResetActiveConnections = resets.ActiveCartConnectionCount
	metrics.ResetSecurityRecords = resetSecurity.SecurityRecordCount
	metrics.ResetSecurityConnections = resetSecurity.SharedConnectionCount
	metrics.ResetDevelopmentReservations = resetSecurity.DevelopmentReservationCount
	metrics.InventoryParts = inventoryParts
	metrics.InventoryConstraints = inventoryConstraints
	metrics.InventoryAttachments = inventoryAttachments
	metrics.InventoryDescendants = inventoryDescendants
	metrics.MeasurementHeartbeatCount = run.HeartbeatCount
	metrics.MeasurementHeartbeatAverageSeconds = if run.HeartbeatCount > 0
		then run.HeartbeatTotalDelta / run.HeartbeatCount
		else 0
	metrics.MeasurementHeartbeatMaximumSeconds = run.HeartbeatMaximumDelta
	metrics.MeasurementCaptureErrors = run.CaptureErrorCount
	metrics.LifecycleErrors = run.LifecycleErrorCount
	metrics.CollisionContacts = run.CollisionContactCount
	metrics.CollisionFixtureParts = #run.CollisionFixtureParts
	metrics.CollisionFixtureConnections = #run.CollisionFixtureConnections
	metrics.ScenarioActionCount = run.ScenarioActionCount
	metrics.CollisionActionCount = run.CollisionActionCount
	metrics.MovementViolationActionCount = run.MovementViolationActionCount
	metrics.ResetActionCount = run.ResetActionCount
	metrics.ReplacementActionCount = run.ReplacementActionCount
	metrics.DestructionActionCount = run.DestructionActionCount
	metrics.EnduranceCycleCount = run.EnduranceCycleCount
	metrics.SteadyStateMeasuredSeconds = run.SteadyStateMeasuredSeconds
	metrics.SteadyStatePeriodicSnapshots = run.SteadyStatePeriodicSnapshotCount
	metrics.PostActionMeasuredSeconds = run.PostActionMeasuredSeconds
	metrics.MotionRecords =
		math.max(run.MotionPeakRecordCount, if motion ~= nil then motion.RecordCount else 0)
	metrics.MotionAppliedRecords = math.max(
		run.MotionAppliedRecordCount,
		if motion ~= nil then motion.AppliedRecordCount else 0
	)
	metrics.MotionSchedulers = if motion ~= nil then motion.SchedulerCount else 0
	metrics.MotionElapsedSeconds = run.MotionElapsedSeconds
		+ if motion ~= nil then motion.ElapsedSeconds else 0
	metrics.MotionSteps = run.MotionStepCount + if motion ~= nil then motion.StepCount else 0
	metrics.MotionLinearImpulses = run.MotionLinearImpulseCount
		+ if motion ~= nil then motion.LinearImpulseCount else 0
	metrics.MotionAngularImpulses = run.MotionAngularImpulseCount
		+ if motion ~= nil then motion.AngularImpulseCount else 0
	metrics.MotionSkippedRecords = run.MotionSkippedRecordCount
		+ if motion ~= nil then motion.SkippedRecordCount else 0
	metrics.MotionErrors = run.MotionErrorCount + if motion ~= nil then motion.ErrorCount else 0
	metrics.HarnessSchedulers = (if run.MeasurementConnection ~= nil then 1 else 0)
		+ (if motion ~= nil then motion.SchedulerCount else 0)

	local memoryUsage = getMemoryUsageMb()

	if memoryUsage ~= nil then
		metrics.TotalMemoryMb = memoryUsage
	end

	local instanceCount = getInstanceCount()

	if instanceCount ~= nil then
		metrics.DataModelInstances = instanceCount
	end

	return metrics
end

local function captureSnapshot(run: ActiveRun, stage: SnapshotStage): Snapshot
	return CartPerformanceSnapshot.Add(run.Snapshots, {
		ScenarioId = run.ScenarioId,
		LoadCount = run.LoadCount,
		Stage = stage,
		RecordedAt = Workspace:GetServerTimeNow(),
		Metrics = collectMetrics(run),
	})
end

local function recordCaptureFailure(run: ActiveRun, context: string, errorMessage: any): string
	run.CaptureErrorCount += 1

	local resolvedError = string.format("%s: %s", context, tostring(errorMessage))

	if run.LastCaptureError ~= resolvedError then
		run.LastCaptureError = resolvedError
		log:Warn("Performance snapshot failed once: %s", resolvedError)
	end

	return resolvedError
end

local function tryCaptureSnapshot(
	run: ActiveRun,
	stage: SnapshotStage,
	context: string
): (Snapshot?, string?)
	local succeeded, snapshotOrError = pcall(captureSnapshot, run, stage)

	if not succeeded then
		return nil, recordCaptureFailure(run, context, snapshotOrError)
	end

	return snapshotOrError :: Snapshot, nil
end

local function recordLifecycleFailure(run: ActiveRun, context: string, errorMessage: any): string
	run.LifecycleErrorCount += 1

	local resolvedError = string.format("%s: %s", context, tostring(errorMessage))

	if run.LastLifecycleError ~= resolvedError then
		run.LastLifecycleError = resolvedError
		log:Warn("Performance lifecycle failed once: %s", resolvedError)
	end

	return resolvedError
end

local function stopMotion(run: ActiveRun)
	if run.MotionSimulator ~= nil then
		local simulator = run.MotionSimulator :: MotionSimulator
		local diagnosticsSucceeded, diagnostics = pcall(function()
			return simulator:GetDiagnostics()
		end)

		if diagnosticsSucceeded then
			run.MotionErrorCount += diagnostics.ErrorCount
			run.MotionElapsedSeconds += diagnostics.ElapsedSeconds
			run.MotionPeakRecordCount = math.max(run.MotionPeakRecordCount, diagnostics.RecordCount)
			run.MotionAppliedRecordCount =
				math.max(run.MotionAppliedRecordCount, diagnostics.AppliedRecordCount)
			run.MotionStepCount += diagnostics.StepCount
			run.MotionLinearImpulseCount += diagnostics.LinearImpulseCount
			run.MotionAngularImpulseCount += diagnostics.AngularImpulseCount
			run.MotionSkippedRecordCount += diagnostics.SkippedRecordCount
		else
			run.MotionErrorCount += 1
			log:Warn("Performance motion diagnostics failed during stop: %s", tostring(diagnostics))
		end

		local stopped, stopError = pcall(function()
			simulator:Stop()
		end)

		if not stopped then
			run.MotionErrorCount += 1
			log:Warn("Performance motion stop failed: %s", tostring(stopError))
		end

		run.MotionSimulator = nil
	end
end

local function stopMeasurement(run: ActiveRun)
	if run.MeasurementConnection ~= nil then
		run.MeasurementConnection:Disconnect()
		run.MeasurementConnection = nil
	end

	stopMotion(run)
end

local function startMeasurement(run: ActiveRun)
	run.MeasurementConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if activeRun ~= run then
			return
		end

		if isFiniteNumber(deltaTime) and deltaTime >= 0 then
			run.HeartbeatCount += 1
			run.HeartbeatTotalDelta += deltaTime
			run.HeartbeatMaximumDelta = math.max(run.HeartbeatMaximumDelta, deltaTime)
			run.MeasurementAccumulator += deltaTime

			if run.Stage == CartPerformanceSnapshot.Stages.SteadyState then
				run.SteadyStateMeasuredSeconds += deltaTime
			elseif
				run.Stage == CartPerformanceSnapshot.Stages.LifecycleStress
				and run.ScenarioActionCount > 0
			then
				run.PostActionMeasuredSeconds += deltaTime
			end
		end

		if run.MeasurementAccumulator < CartPerformanceTest.Development.SnapshotInterval then
			return
		end

		run.MeasurementAccumulator %= CartPerformanceTest.Development.SnapshotInterval

		local snapshot = tryCaptureSnapshot(run, run.Stage, "periodic measurement")

		if snapshot ~= nil and run.Stage == CartPerformanceSnapshot.Stages.SteadyState then
			run.SteadyStatePeriodicSnapshotCount += 1
		end
	end)
end

local function buildMotionRecords(
	run: ActiveRun
): { CartPerformanceMotionSimulator.RuntimeCartRecord }
	local records: { CartPerformanceMotionSimulator.RuntimeCartRecord } = {}
	local maximum = run.LoadCount

	if run.ScenarioId == ScenarioIds.MixedLifecycle then
		maximum = math.max(1, math.floor(run.LoadCount / 2))
	elseif run.ScenarioId == ScenarioIds.ControlledCollision then
		maximum = math.min(4, run.LoadCount)
	end

	for index = 1, maximum do
		local cart = run.ModelsByIndex[index]
		local ownerUserId = run.OwnerUserIdsByIndex[index]
		local record = if ownerUserId ~= nil
			then CartService:GetCartRecordByOwnerUserId(ownerUserId)
			else nil

		if cart ~= nil and record ~= nil and record.Model == cart then
			table.insert(records, {
				Model = cart,
				MovementProfile = record.MovementProfile,
			})
		end
	end

	return records
end

local function scenarioUsesExternalMotion(scenarioId: string): boolean
	return scenarioId == ScenarioIds.MovingLoad
		or scenarioId == ScenarioIds.MixedLifecycle
		or scenarioId == ScenarioIds.ControlledCollision
end

local function startMotionIfRequired(run: ActiveRun)
	if not scenarioUsesExternalMotion(run.ScenarioId) then
		return
	end

	local records = buildMotionRecords(run)

	assert(#records > 0, "performance motion scenario has no live physical carts")

	local simulator = CartPerformanceMotionSimulator.new()

	assert(simulator:Start(records), "performance motion simulator did not start")
	run.MotionSimulator = simulator
end

local function clearCollisionFixtures(run: ActiveRun)
	for _, connection in run.CollisionFixtureConnections do
		connection:Disconnect()
	end

	for _, part in run.CollisionFixtureParts do
		if part.Parent ~= nil then
			part:Destroy()
		end
	end

	table.clear(run.CollisionFixtureConnections)
	table.clear(run.CollisionFixtureParts)
	table.clear(run.CollisionContactModels)
end

local function cleanupRun(run: ActiveRun, preserveMeasurement: boolean?): (boolean, string?)
	stopMotion(run)
	clearCollisionFixtures(run)
	run.CollisionContactCount = 0

	if preserveMeasurement ~= true then
		stopMeasurement(run)
	end

	local succeeded, stoppedOrError = pcall(function()
		return run.Runtime:Stop()
	end)
	local errors: { string } = {}

	if not succeeded then
		table.insert(errors, tostring(stoppedOrError))
	end

	for userId in run.ResetSecurityTestUserIds do
		local cleared, clearError = CartResetRequestService:ClearDevelopmentRequestState(userId)

		if not cleared then
			table.insert(
				errors,
				clearError or "Development reset-request state cleanup failed"
			)
		end
	end

	table.clear(run.ResetSecurityTestUserIds)

	return #errors == 0, if #errors > 0 then table.concat(errors, "; ") else nil
end

local function createBlockedResult(run: ActiveRun, failureCode: string, notes: string): Result
	local completedAt = Workspace:GetServerTimeNow()

	return CartPerformanceResult.Create({
		ScenarioId = run.ScenarioId,
		LoadCount = run.LoadCount,
		Status = "Blocked",
		Severity = "S1",
		StartedAt = run.StartedAt,
		CompletedAt = completedAt,
		Snapshots = CartPerformanceSnapshot.Read(run.Snapshots),
		FailureCode = failureCode,
		Notes = notes,
	})
end

function CartPerformanceLoadService:Start(): (boolean, string?)
	if started then
		return true, nil
	end

	if
		not CartPerformanceLoadRuntime.IsAvailable(
			Environment.Name,
			Environment.EnableDebugTools,
			RunService:IsStudio(),
			CartPerformanceTest.Enabled
		)
	then
		return false, "Phase 1T performance harness is Development Studio only"
	end

	local validation = CartPerformanceConfigValidator.Validate(CartPerformanceTest)

	if not validation.IsValid then
		return false, table.concat(validation.Errors, "; ")
	end

	started = true
	log:Info("Phase 1T performance harness ready; no load starts automatically")

	return true, nil
end

function CartPerformanceLoadService:BeginRun(
	scenarioId: string,
	loadCount: number
): (boolean, string?)
	if not started then
		return false, "performance harness is not started"
	end

	if activeRun ~= nil then
		return false, "a performance load is already active"
	end

	if CartPerformanceTest.ByScenarioId[scenarioId] == nil then
		return false, "scenario ID is not a controlled Phase 1T scenario"
	end

	if not isSupportedLoadCount(loadCount) then
		return false, "load count must be 1, 4, 8, or 12"
	end

	local spawnIds =
		CartGreyboxRouteSystem:GetSectionSpawnIds(CartGreyboxPerformanceIds.TwelveCartLoadZone)

	if #spawnIds < loadCount then
		return false, "the source-owned twelve-cart performance zone is unavailable"
	end

	local run: ActiveRun
	local runtime = CartPerformanceLoadRuntime.new({
		Spawn = function(ownerUserId: number, loadIndex: number, _scenarioId: string): Model
			local cart = CartService:SpawnDevelopmentLoadCart(
				ownerUserId,
				CartGreybox.CartId,
				spawnIds[loadIndex]
			)
			local prepared, preparationError = pcall(function()
				local cartRecord = CartService:GetCartRecordByOwnerUserId(ownerUserId)

				assert(
					cartRecord ~= nil and cartRecord.Model == cart,
					"runtime cart registry mismatch"
				)

				local registered, registrationError =
					CartMovementValidationService:RegisterCart(cartRecord)

				assert(
					registered or CartMovementValidationService:GetSnapshot(cart) ~= nil,
					registrationError or "movement validator registration failed"
				)

				run.ModelsByIndex[loadIndex] = cart
				run.OwnerUserIdsByIndex[loadIndex] = ownerUserId
				run.InventoryByIndex[loadIndex] = countInventory(cart)
				trackLoadCart(run, ownerUserId, cart)
			end)

			if not prepared then
				run.ModelsByIndex[loadIndex] = nil
				run.OwnerUserIdsByIndex[loadIndex] = nil
				run.InventoryByIndex[loadIndex] = nil

				local cleanupCallSucceeded, cleanupResult = pcall(function()
					return CartService:DespawnDevelopmentLoadCart(ownerUserId)
				end)
				local resolvedError = tostring(preparationError)

				if not cleanupCallSucceeded or cleanupResult ~= true then
					resolvedError ..= string.format(
						"; newest-cart cleanup failed: %s",
						tostring(cleanupResult)
					)
				end

				error(resolvedError, 2)
			end

			return cart
		end,
		Cleanup = function(_handle: any, ownerUserId: number, loadIndex: number)
			CartService:DespawnDevelopmentLoadCart(ownerUserId)
			run.ModelsByIndex[loadIndex] = nil
			run.OwnerUserIdsByIndex[loadIndex] = nil
			run.InventoryByIndex[loadIndex] = nil
		end,
	})
	local startedAt = Workspace:GetServerTimeNow()

	run = {
		ScenarioId = scenarioId,
		LoadCount = loadCount,
		StartedAt = startedAt,
		Stage = CartPerformanceSnapshot.Stages.ColdSetup,
		StageStartedAt = startedAt,
		Runtime = runtime,
		ModelsByIndex = {},
		OwnerUserIdsByIndex = {},
		AllLoadModels = setmetatable({}, { __mode = "k" }) :: any,
		LoadOwnerUserIds = {},
		LoadAnalyticsRuntimeIds = {},
		ResetAnalyticsBaselines = {},
		CorrectionAnalyticsBaselines = {},
		ResetSecurityTestUserIds = {},
		CollisionFixtureParts = {},
		CollisionFixtureConnections = {},
		CollisionContactModels = {},
		CollisionContactCount = 0,
		SpawnIds = spawnIds,
		InventoryByIndex = {},
		BaselineMetrics = {},
		Snapshots = CartPerformanceSnapshot.CreateBuffer(),
		MotionSimulator = nil,
		MeasurementConnection = nil,
		MeasurementAccumulator = 0,
		HeartbeatCount = 0,
		HeartbeatTotalDelta = 0,
		HeartbeatMaximumDelta = 0,
		SteadyStateMeasuredSeconds = 0,
		SteadyStatePeriodicSnapshotCount = 0,
		PostActionMeasuredSeconds = 0,
		AnalyticsEventBaseline = CartGreyboxAnalyticsSink.GetTotalEmittedCount(),
		CaptureErrorCount = 0,
		LastCaptureError = nil,
		LifecycleErrorCount = 0,
		LastLifecycleError = nil,
		MotionErrorCount = 0,
		MotionElapsedSeconds = 0,
		MotionPeakRecordCount = 0,
		MotionAppliedRecordCount = 0,
		MotionStepCount = 0,
		MotionLinearImpulseCount = 0,
		MotionAngularImpulseCount = 0,
		MotionSkippedRecordCount = 0,
		ScenarioActionCount = 0,
		CollisionActionCount = 0,
		MovementViolationActionCount = 0,
		ResetActionCount = 0,
		ReplacementActionCount = 0,
		DestructionActionCount = 0,
		EnduranceCycleCount = 0,
	}
	activeRun = run

	local setupSucceeded, setupError = pcall(function()
		local baselineSnapshot = captureSnapshot(run, CartPerformanceSnapshot.Stages.ColdSetup)

		run.BaselineMetrics = table.clone(baselineSnapshot.Metrics)
		runtime:Start(scenarioId, loadCount)
		assert(countTable(run.ModelsByIndex) == loadCount, "load model count is incomplete")
		captureSnapshot(run, CartPerformanceSnapshot.Stages.LoadCreation)
		startMotionIfRequired(run)
		startMeasurement(run)
	end)

	if not setupSucceeded then
		local cleanupSucceeded, cleanupError = cleanupRun(run)
		local resolvedError = tostring(setupError)

		if not cleanupSucceeded then
			resolvedError ..= string.format("; cleanup failed: %s", cleanupError or "unknown")
		end

		lastResult = createBlockedResult(run, "PERF_SETUP_FAILED", resolvedError)
		activeRun = nil
		log:Warn("Performance load setup failed: %s", resolvedError)

		return false, resolvedError
	end

	run.Stage = CartPerformanceSnapshot.Stages.Warmup
	run.StageStartedAt = Workspace:GetServerTimeNow()
	log:Info("Performance load started Scenario=%s Carts=%d", scenarioId, loadCount)

	return true, nil
end

function CartPerformanceLoadService:SetStage(stage: SnapshotStage): (boolean, string?)
	local run = activeRun

	if run == nil then
		return false, "no performance load is active"
	end

	local now = Workspace:GetServerTimeNow()
	local allowed, policyError =
		CartPerformanceGatePolicy.CanTransition(run.Stage, stage, now - run.StageStartedAt)

	if not allowed then
		return false, policyError
	end

	local snapshot, captureError = tryCaptureSnapshot(run, stage, "stage transition")

	if snapshot == nil then
		return false, captureError
	end

	run.Stage = stage
	run.StageStartedAt = now
	run.MeasurementAccumulator = 0

	return true, nil
end

function CartPerformanceLoadService:Capture(): (Snapshot?, string?)
	local run = activeRun

	if run == nil then
		return nil, "no performance load is active"
	end

	return tryCaptureSnapshot(run, run.Stage, "manual capture")
end

local function isLifecycleStressActive(run: ActiveRun): boolean
	return run.Stage == CartPerformanceSnapshot.Stages.LifecycleStress
end

function CartPerformanceLoadService:TriggerControlledCollision(): (boolean, string?)
	local run = activeRun

	if run == nil or run.ScenarioId ~= ScenarioIds.ControlledCollision then
		return false, "the controlled-collision scenario is not active"
	end

	if not isLifecycleStressActive(run) then
		return false, "controlled actions run only during lifecycle stress"
	end

	if run.CollisionActionCount > 0 then
		return false, "the controlled collision has already been armed"
	end

	stopMotion(run)
	clearCollisionFixtures(run)

	local targetCount = math.min(4, run.LoadCount)
	local armed = 0
	local armedSuccessfully, armError = pcall(function()
		local routeFolder = CartGreyboxRouteSystem:GetRouteFolder()

		assert(routeFolder ~= nil, "greybox route is unavailable for collision fixtures")

		for index = 1, targetCount do
			local ownerUserId = run.OwnerUserIdsByIndex[index]
			local cartRecord = if ownerUserId ~= nil
				then CartService:GetCartRecordByOwnerUserId(ownerUserId)
				else nil

			assert(
				cartRecord ~= nil and cartRecord.Model.Parent ~= nil,
				"collision cart is not live"
			)

			local cart = cartRecord.Model
			local root = CartModelUtility.GetRoot(cart)
			local horizontalForward =
				Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)

			assert(horizontalForward.Magnitude > 1e-5, "collision cart forward is degenerate")

			local forward = horizontalForward.Unit
			local boundsCFrame, boundsSize = cart:GetBoundingBox()
			local forwardExtent = math.abs(forward:Dot(boundsCFrame.RightVector))
					* boundsSize.X
					* 0.5
				+ math.abs(forward:Dot(boundsCFrame.UpVector)) * boundsSize.Y * 0.5
				+ math.abs(forward:Dot(boundsCFrame.LookVector)) * boundsSize.Z * 0.5
			local barrierPosition = boundsCFrame.Position + forward * (forwardExtent + 3)
			local barrier = Instance.new("Part")

			barrier.Name = string.format("Phase1TCollisionBarrier_%02d", index)
			barrier.Size = Vector3.new(20, 8, 2)
			barrier.CFrame = CFrame.lookAt(barrierPosition, barrierPosition + forward)
			barrier.Anchored = true
			barrier.CanCollide = true
			barrier.CanQuery = false
			barrier.CanTouch = true
			barrier.Transparency = 0.35
			barrier.Color = Color3.fromRGB(220, 80, 65)
			barrier:SetAttribute("DevelopmentPerformanceCollisionFixture", true)
			MaterialPolicy.Apply(barrier, Enum.Material.Plastic)
			barrier.Parent = routeFolder

			table.insert(run.CollisionFixtureParts, barrier)
			table.insert(
				run.CollisionFixtureConnections,
				barrier.Touched:Connect(function(otherPart)
					if
						activeRun == run
						and otherPart:IsDescendantOf(cart)
						and run.CollisionContactModels[cart] ~= true
					then
						run.CollisionContactModels[cart] = true
						run.CollisionContactCount += 1
					end
				end)
			)

			local currentForwardSpeed = root.AssemblyLinearVelocity:Dot(forward)
			local targetSpeed = cartRecord.MovementProfile.HuntingSpeed
			local speedDelta = math.max(0, targetSpeed - currentForwardSpeed)

			if speedDelta > 0 then
				root:ApplyImpulse(forward * (root.AssemblyMass * speedDelta))
			end

			armed += 1
		end
	end)

	if not armedSuccessfully or armed ~= targetCount then
		clearCollisionFixtures(run)
		run.CollisionContactCount = 0
		return false, tostring(armError or "not every controlled collision was armed")
	end

	recordScenarioAction(run)
	run.CollisionActionCount += 1

	return true, nil
end

function CartPerformanceLoadService:InjectMovementViolation(loadIndex: number): (boolean, string?)
	local run = activeRun

	if run == nil then
		return false, "no performance load is active"
	end

	if not isLifecycleStressActive(run) then
		return false, "controlled actions run only during lifecycle stress"
	end

	if loadIndex % 1 ~= 0 or loadIndex < 1 or loadIndex > run.LoadCount then
		return false, "load index is outside the controlled cart set"
	end

	local cart = run.ModelsByIndex[loadIndex]

	if cart == nil then
		return false, "load cart is not live"
	end

	local baselineSucceeded, runtimeCartIdOrError, previousBaseline =
		pcall(trackCorrectionAnalyticsBaseline, run, cart)

	if not baselineSucceeded then
		return false, tostring(runtimeCartIdOrError)
	end

	local runtimeCartId = runtimeCartIdOrError :: string

	local injected, injectionError = CartMovementValidationService:InjectDevelopmentViolation(
		cart,
		CartGreyboxViolationIds.ExtremeHorizontalVelocity
	)

	if injected then
		recordScenarioAction(run)
		run.MovementViolationActionCount += 1
	else
		run.CorrectionAnalyticsBaselines[runtimeCartId] = previousBaseline
	end

	return injected, injectionError
end

function CartPerformanceLoadService:ReplaceCart(loadIndex: number): (boolean, string?)
	local run = activeRun

	if
		run == nil
		or (
			run.ScenarioId ~= ScenarioIds.ReplacementDespawn
			and run.ScenarioId ~= ScenarioIds.MixedLifecycle
		)
	then
		return false, "the replacement/despawn scenario is not active"
	end

	if not isLifecycleStressActive(run) then
		return false, "controlled actions run only during lifecycle stress"
	end

	if run.ScenarioId == ScenarioIds.MixedLifecycle then
		-- The formal moving window has already completed. Stop and retain its
		-- evidence before replacing a tracked cart so lifecycle work cannot turn a
		-- valid movement record into a skipped stale reference.
		stopMotion(run)
	end

	local ownerUserId = run.OwnerUserIdsByIndex[loadIndex]

	if ownerUserId == nil then
		return false, "load index is outside the controlled cart set"
	end

	local succeeded, cartOrError = pcall(function()
		local cart = CartService:SpawnDevelopmentLoadCart(
			ownerUserId,
			CartGreybox.CartId,
			run.SpawnIds[loadIndex]
		)
		local record = CartService:GetCartRecordByOwnerUserId(ownerUserId)

		assert(record ~= nil and record.Model == cart, "replacement cart registry mismatch")

		local registered, registrationError = CartMovementValidationService:RegisterCart(record)

		assert(
			registered or CartMovementValidationService:GetSnapshot(cart) ~= nil,
			registrationError or "replacement movement validator registration failed"
		)

		run.ModelsByIndex[loadIndex] = cart
		run.InventoryByIndex[loadIndex] = countInventory(cart)
		trackLoadCart(run, ownerUserId, cart)

		return cart
	end)

	if not succeeded then
		run.ModelsByIndex[loadIndex] = nil
		run.InventoryByIndex[loadIndex] = nil
		pcall(function()
			CartService:DespawnDevelopmentLoadCart(ownerUserId)
		end)

		return false, tostring(cartOrError)
	end

	recordScenarioAction(run)
	run.ReplacementActionCount += 1

	return true, nil
end

function CartPerformanceLoadService:DestroyCart(loadIndex: number): (boolean, string?)
	local run = activeRun

	if
		run == nil
		or (
			run.ScenarioId ~= ScenarioIds.ReplacementDespawn
			and run.ScenarioId ~= ScenarioIds.MixedLifecycle
		)
	then
		return false, "the replacement/despawn scenario is not active"
	end

	if not isLifecycleStressActive(run) then
		return false, "controlled actions run only during lifecycle stress"
	end

	if run.ScenarioId == ScenarioIds.MixedLifecycle then
		stopMotion(run)
	end

	local cart = run.ModelsByIndex[loadIndex]

	if cart == nil then
		return false, "load index is outside the controlled cart set"
	end

	run.ModelsByIndex[loadIndex] = nil
	run.InventoryByIndex[loadIndex] = nil
	cart:Destroy()
	recordScenarioAction(run)
	run.DestructionActionCount += 1

	return true, nil
end

function CartPerformanceLoadService:RunTrustedPlayerReset(player: Player): (boolean, string?)
	local run = activeRun

	if
		run == nil
		or (
			run.ScenarioId ~= ScenarioIds.RepeatedReset
			and run.ScenarioId ~= ScenarioIds.MixedLifecycle
			and run.ScenarioId ~= ScenarioIds.AnalyticsLifecycle
		)
	then
		return false, "the repeated-reset scenario is not active"
	end

	if not isLifecycleStressActive(run) then
		return false, "controlled actions run only during lifecycle stress"
	end

	local cart = CartService:GetCart(player)

	if cart == nil then
		return false, "player has no active cart"
	end

	local succeeded = false
	local resetError: string? = nil

	if run.ScenarioId == ScenarioIds.AnalyticsLifecycle then
		if run.ResetSecurityTestUserIds[player.UserId] ~= true then
			local reserved, reservationError =
				CartResetRequestService:ReserveDevelopmentRequestState(player.UserId)

			if not reserved then
				return false, reservationError
			end

			run.ResetSecurityTestUserIds[player.UserId] = true
		end

		local baselineSucceeded, baselineError = pcall(trackResetAnalyticsBaseline, run, cart)

		if not baselineSucceeded then
			return false, tostring(baselineError)
		end

		local result, processError = CartResetRequestService:ProcessDevelopmentRequest(player)

		if result == nil then
			return false, processError
		end

		succeeded = result.Approved
		resetError = if result.Approved then nil else result.Reason
	else
		succeeded, resetError = CartResetService:BeginReset(player, cart)
	end

	if succeeded then
		recordScenarioAction(run)
		run.ResetActionCount += 1
	end

	return succeeded, resetError
end

function CartPerformanceLoadService:CycleEnduranceLoad(): (boolean, string?)
	local run = activeRun

	if run == nil or run.ScenarioId ~= ScenarioIds.LifecycleEndurance then
		return false, "the lifecycle-endurance scenario is not active"
	end

	if run.Stage ~= CartPerformanceSnapshot.Stages.LifecycleStress then
		return false, "endurance cycles begin only after the formal steady-state stage"
	end

	stopMotion(run)

	local stopSucceeded, stoppedOrError = pcall(function()
		return run.Runtime:Stop()
	end)

	if not stopSucceeded or stoppedOrError ~= true then
		return false, recordLifecycleFailure(run, "endurance cleanup", stoppedOrError)
	end

	task.wait(CartPerformanceTest.Development.CleanupObservationDuration)

	local cleanupSnapshot, cleanupCaptureError =
		tryCaptureSnapshot(run, CartPerformanceSnapshot.Stages.LifecycleStress, "endurance cleanup")

	if cleanupSnapshot == nil then
		return false, cleanupCaptureError
	end

	local cleanupMetrics = cleanupSnapshot.Metrics
	local cleanupAllowed, cleanupPolicyError = CartPerformanceGatePolicy.CanRestartEnduranceCycle({
		LoadCount = run.LoadCount,
		RuntimeActiveCount = run.Runtime:GetActiveCount(),
		LoadCartCount = cleanupMetrics.LoadCartRecords,
		MotionSchedulerCount = cleanupMetrics.MotionSchedulers,
		LoadAnalyticsRuntimeIdentityCount = cleanupMetrics.LoadAnalyticsRuntimeIdentities,
		LoadAnalyticsSpawnEventCount = cleanupMetrics.LoadAnalyticsSpawnEvents,
		LoadAnalyticsDespawnEventCount = cleanupMetrics.LoadAnalyticsDespawnEvents,
		Metrics = cleanupMetrics,
	})

	if not cleanupAllowed then
		return false,
			recordLifecycleFailure(
				run,
				"endurance cleanup evidence",
				cleanupPolicyError or "cleanup evidence did not pass"
			)
	end

	local restartSucceeded, restartError = pcall(function()
		run.Runtime:Start(run.ScenarioId, run.LoadCount)
		assert(
			countTable(run.ModelsByIndex) == run.LoadCount,
			"endurance reload model count is incomplete"
		)
	end)

	if not restartSucceeded then
		return false, recordLifecycleFailure(run, "endurance reload", restartError)
	end

	local reloadSnapshot, reloadCaptureError =
		tryCaptureSnapshot(run, CartPerformanceSnapshot.Stages.LifecycleStress, "endurance reload")

	if reloadSnapshot == nil then
		return false, reloadCaptureError
	end

	local reloadMetrics = reloadSnapshot.Metrics
	local reloadAllowed, reloadPolicyError = CartPerformanceGatePolicy.CanContinueEnduranceCycle({
		LoadCount = run.LoadCount,
		RuntimeActiveCount = run.Runtime:GetActiveCount(),
		LiveLoadCartCount = reloadMetrics.LoadCartRecords,
		ValidAssemblyCount = reloadMetrics.ValidLoadAssemblies,
		FiniteRootCount = reloadMetrics.FiniteLoadRoots,
		PhysicalRootCount = reloadMetrics.PhysicalLoadRoots,
		ServerOwnedRootCount = reloadMetrics.ServerOwnedLoadRoots,
		LoadAssemblyRecordCount = reloadMetrics.LoadAssemblyRecords,
		LoadOccupantRecordCount = reloadMetrics.LoadOccupantRecords,
		LoadTerrainRecordCount = reloadMetrics.LoadTerrainRecords,
		LoadStabilityRecordCount = reloadMetrics.LoadStabilityRecords,
		LoadLongitudinalRecordCount = reloadMetrics.LoadLongitudinalRecords,
		LoadValidatorRecordCount = reloadMetrics.LoadValidatorRecords,
		LoadAnalyticsRecordCount = reloadMetrics.LoadAnalyticsRecords,
		LoadAnalyticsRuntimeIdentityCount = reloadMetrics.LoadAnalyticsRuntimeIdentities,
		LoadAnalyticsSpawnEventCount = reloadMetrics.LoadAnalyticsSpawnEvents,
	})

	if not reloadAllowed then
		return false,
			recordLifecycleFailure(
				run,
				"endurance reload evidence",
				reloadPolicyError or "reload evidence did not pass"
			)
	end

	recordScenarioAction(run)
	run.EnduranceCycleCount += 1

	return true, nil
end

function CartPerformanceLoadService:CompleteRun(
	status: CartPerformanceResult.Status,
	severity: CartPerformanceResult.Severity?,
	failureCode: string?,
	notes: string?
): (Result?, string?)
	local run = activeRun

	if run == nil then
		return nil, "no performance load is active"
	end

	if VALID_RESULT_STATUSES[status] ~= true then
		return nil, "result status is unsupported"
	end

	if severity ~= nil and VALID_RESULT_SEVERITIES[severity] ~= true then
		return nil, "result severity is unsupported"
	end

	if failureCode ~= nil and failureCode == "" then
		return nil, "failure code must be non-empty when supplied"
	end

	if status == "Passed" and (severity ~= nil or failureCode ~= nil) then
		return nil, "passed results cannot include failure severity or failure code"
	end

	if status == "Passed" then
		local evidenceSnapshot, evidenceCaptureError = tryCaptureSnapshot(
			run,
			CartPerformanceSnapshot.Stages.LifecycleStress,
			"final pass evidence"
		)

		if evidenceSnapshot == nil then
			return nil, evidenceCaptureError
		end

		local evidenceMetrics = evidenceSnapshot.Metrics
		local passAllowed, passError = CartPerformanceGatePolicy.CanPass({
			ScenarioId = run.ScenarioId,
			Stage = run.Stage,
			LoadCount = run.LoadCount,
			LiveLoadCartCount = evidenceMetrics.LoadCartRecords,
			ValidAssemblyCount = evidenceMetrics.ValidLoadAssemblies,
			FiniteRootCount = evidenceMetrics.FiniteLoadRoots,
			PhysicalRootCount = evidenceMetrics.PhysicalLoadRoots,
			ServerOwnedRootCount = evidenceMetrics.ServerOwnedLoadRoots,
			LoadAssemblyRecordCount = evidenceMetrics.LoadAssemblyRecords,
			LoadOccupantRecordCount = evidenceMetrics.LoadOccupantRecords,
			LoadTerrainRecordCount = evidenceMetrics.LoadTerrainRecords,
			LoadStabilityRecordCount = evidenceMetrics.LoadStabilityRecords,
			LoadLongitudinalRecordCount = evidenceMetrics.LoadLongitudinalRecords,
			LoadValidatorRecordCount = evidenceMetrics.LoadValidatorRecords,
			LoadAnalyticsRecordCount = evidenceMetrics.LoadAnalyticsRecords,
			SteadyStateMeasuredSeconds = run.SteadyStateMeasuredSeconds,
			SteadyStatePeriodicSnapshotCount = run.SteadyStatePeriodicSnapshotCount,
			PostActionMeasuredSeconds = run.PostActionMeasuredSeconds,
			CollisionActionCount = run.CollisionActionCount,
			CollisionContactCount = evidenceMetrics.CollisionContacts,
			MovementViolationActionCount = run.MovementViolationActionCount,
			ResetActionCount = run.ResetActionCount,
			ReplacementActionCount = run.ReplacementActionCount,
			DestructionActionCount = run.DestructionActionCount,
			EnduranceCycleCount = run.EnduranceCycleCount,
			CaptureErrorCount = run.CaptureErrorCount,
			LifecycleErrorCount = run.LifecycleErrorCount,
			MotionErrorCount = evidenceMetrics.MotionErrors,
			MotionElapsedSeconds = evidenceMetrics.MotionElapsedSeconds,
			MotionPeakRecordCount = evidenceMetrics.MotionRecords,
			MotionAppliedRecordCount = evidenceMetrics.MotionAppliedRecords,
			MotionStepCount = evidenceMetrics.MotionSteps,
			MotionLinearImpulseCount = evidenceMetrics.MotionLinearImpulses,
			MotionSkippedRecordCount = evidenceMetrics.MotionSkippedRecords,
			LoadAnalyticsRuntimeIdentityCount = evidenceMetrics.LoadAnalyticsRuntimeIdentities,
			LoadAnalyticsSpawnEventCount = evidenceMetrics.LoadAnalyticsSpawnEvents,
			LoadAnalyticsCorrectionEventCount = evidenceMetrics.LoadAnalyticsCorrectionEvents,
			ResetAnalyticsRequestedEventCount = evidenceMetrics.ResetAnalyticsRequestedEvents,
			ResetAnalyticsApprovedEventCount = evidenceMetrics.ResetAnalyticsApprovedEvents,
			ResetAnalyticsCompletedEventCount = evidenceMetrics.ResetAnalyticsCompletedEvents,
		})

		if not passAllowed then
			return nil, passError
		end
	end

	tryCaptureSnapshot(run, CartPerformanceSnapshot.Stages.LifecycleStress, "pre-cleanup")
	run.Stage = CartPerformanceSnapshot.Stages.Cleanup
	run.StageStartedAt = Workspace:GetServerTimeNow()
	local cleanupSucceeded, cleanupError = cleanupRun(run, true)
	task.wait(CartPerformanceTest.Development.CleanupObservationDuration)
	stopMeasurement(run)
	local finalSnapshot, finalCaptureError =
		tryCaptureSnapshot(run, CartPerformanceSnapshot.Stages.Cleanup, "final cleanup")

	local completedAt = Workspace:GetServerTimeNow()
	local resolvedStatus = status
	local resolvedSeverity = severity
	local resolvedFailureCode = failureCode
	local resolvedNotes = notes

	if not cleanupSucceeded then
		resolvedStatus = "Failed"
		resolvedSeverity = "S1"
		resolvedFailureCode = "PERF_CLEANUP_FAILED"
		resolvedNotes = string.format(
			"%s%s",
			if notes ~= nil and notes ~= "" then notes .. "; " else "",
			cleanupError or "unknown cleanup failure"
		)
	elseif finalSnapshot == nil then
		resolvedStatus = "Failed"
		resolvedSeverity = "S1"
		resolvedFailureCode = "PERF_CLEANUP_CAPTURE_FAILED"
		resolvedNotes = string.format(
			"%s%s",
			if notes ~= nil and notes ~= "" then notes .. "; " else "",
			string.format("cleanup evidence capture failed: %s", tostring(finalCaptureError))
		)
	elseif resolvedStatus == "Passed" then
		local finalMetrics = finalSnapshot.Metrics
		local cleanupAllowed, cleanupPolicyError = CartPerformanceGatePolicy.CanFinalizeCleanup({
			ScenarioId = run.ScenarioId,
			LoadCount = run.LoadCount,
			LoadCartCount = finalMetrics.LoadCartRecords,
			HarnessSchedulerCount = finalMetrics.HarnessSchedulers,
			MotionSchedulerCount = finalMetrics.MotionSchedulers,
			CaptureErrorCount = run.CaptureErrorCount,
			LifecycleErrorCount = run.LifecycleErrorCount,
			MotionErrorCount = run.MotionErrorCount,
			LoadAnalyticsRuntimeIdentityCount = finalMetrics.LoadAnalyticsRuntimeIdentities,
			LoadAnalyticsSpawnEventCount = finalMetrics.LoadAnalyticsSpawnEvents,
			LoadAnalyticsDespawnEventCount = finalMetrics.LoadAnalyticsDespawnEvents,
			BaselineMetrics = run.BaselineMetrics,
			FinalMetrics = finalMetrics,
		})

		if not cleanupAllowed then
			resolvedStatus = "Failed"
			resolvedSeverity = "S1"
			resolvedFailureCode = "PERF_CLEANUP_POLICY_FAILED"
			resolvedNotes = string.format(
				"%s%s",
				if notes ~= nil and notes ~= "" then notes .. "; " else "",
				cleanupPolicyError or "cleanup evidence did not pass"
			)
		end
	end

	local snapshots = CartPerformanceSnapshot.Read(run.Snapshots)
	local summary = if #snapshots > 0 then table.clone(snapshots[#snapshots].Metrics) else {}

	summary.SnapshotCount = #snapshots

	local result = CartPerformanceResult.Create({
		ScenarioId = run.ScenarioId,
		LoadCount = run.LoadCount,
		Status = resolvedStatus,
		Severity = resolvedSeverity,
		StartedAt = run.StartedAt,
		CompletedAt = completedAt,
		Summary = summary,
		Snapshots = snapshots,
		FailureCode = resolvedFailureCode,
		Notes = resolvedNotes,
	})

	lastResult = result
	activeRun = nil
	log:Info(
		"Performance load completed Scenario=%s Carts=%d Status=%s Cleanup=%s",
		run.ScenarioId,
		run.LoadCount,
		resolvedStatus,
		tostring(cleanupSucceeded)
	)

	return result, nil
end

function CartPerformanceLoadService:GetLastResult(): Result?
	return lastResult
end

function CartPerformanceLoadService:GetDiagnostics()
	local run = activeRun
	local runtimeSnapshot = if run ~= nil then run.Runtime:GetSnapshot() else nil
	local motion = if run ~= nil and run.MotionSimulator ~= nil
		then (run.MotionSimulator :: MotionSimulator):GetDiagnostics()
		else nil

	return table.freeze({
		Started = started,
		Active = run ~= nil,
		ScenarioId = if run ~= nil then run.ScenarioId else nil,
		ConfiguredLoadCount = if run ~= nil then run.LoadCount else 0,
		RuntimeActiveCount = if runtimeSnapshot ~= nil then runtimeSnapshot.ActiveCount else 0,
		TrackedModelCount = if run ~= nil then countTable(run.ModelsByIndex) else 0,
		SnapshotCount = if run ~= nil then CartPerformanceSnapshot.GetCount(run.Snapshots) else 0,
		MeasurementSchedulerCount = if run ~= nil and run.MeasurementConnection ~= nil
			then 1
			else 0,
		MotionSchedulerCount = if motion ~= nil then motion.SchedulerCount else 0,
		ScenarioActionCount = if run ~= nil then run.ScenarioActionCount else 0,
		EnduranceCycleCount = if run ~= nil then run.EnduranceCycleCount else 0,
		HasLastResult = lastResult ~= nil,
	})
end

function CartPerformanceLoadService:Stop()
	local run = activeRun

	if run ~= nil then
		local cleanupSucceeded, cleanupError = cleanupRun(run)

		if not cleanupSucceeded then
			log:Warn("Performance harness stop cleanup failed: %s", cleanupError or "unknown")
		end

		activeRun = nil
	end

	started = false
	log:Info("Phase 1T performance harness stopped")
end

return CartPerformanceLoadService
