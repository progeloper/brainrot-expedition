--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CartAnalytics = require(ReplicatedStorage.Shared.Config.CartAnalytics)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local CartMovementValidation = require(ReplicatedStorage.Shared.Config.CartMovementValidation)
local CartGreyboxViolationIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxViolationIds)
local CartMovementTypes = require(ReplicatedStorage.Shared.Types.CartMovementTypes)
local CartResetLifecycle = require(ReplicatedStorage.Shared.Utility.CartResetLifecycle)
local CartAnalyticsMovementTracker =
	require(ReplicatedStorage.Shared.Utility.CartAnalyticsMovementTracker)
local CartMovementValidationMath =
	require(ReplicatedStorage.Shared.Utility.CartMovementValidationMath)
local CartMovementValidationState =
	require(ReplicatedStorage.Shared.Utility.CartMovementValidationState)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local CartMovementValidationConfigValidator =
	require(ReplicatedStorage.Shared.Validation.CartMovementValidationConfigValidator)

local CartModelUtility = require(script.Parent.Parent.Utility.CartModelUtility)
local CartAssemblyValidationService = require(script.Parent.CartAssemblyValidationService)
local CartOccupantService = require(script.Parent.CartOccupantService)
local CartResetService = require(script.Parent.CartResetService)
local CartService = require(script.Parent.CartService)

type EffectiveMovementProfile = CartMovementTypes.EffectiveMovementProfile
type MathResult = CartMovementValidationMath.Result
type Thresholds = CartMovementValidationMath.Thresholds
type ValidationState = CartMovementValidationState.State
type Decision = CartMovementValidationState.Decision

type RuntimeRecord = {
	CartRecord: CartService.SpawnedCartRecord,
	Cart: Model,
	Root: BasePart,
	Profile: EffectiveMovementProfile,
	Thresholds: Thresholds,
	State: ValidationState,
	Revision: number,
	LastDriver: Player?,
	OwnershipGraceUntil: number,
	OwnershipMismatchCount: number,
	CorrectionActive: boolean,
	PositionCorrectionPending: boolean,
	CorrectionRevision: number,
	MovementDriver: Player?,
	MovementCandidateStartedAt: number?,
	MeaningfulMovementEmitted: boolean,
	LastResetMarker: unknown,
	LastMovementUpdateMarker: unknown,
	ViolationTimes: { number },
	LastRepeatedWarningTime: number?,
	LastCorrectionLogKey: string?,
	LastCorrectionLogTime: number?,
	LastInternalError: string?,
	LastInternalErrorTime: number?,
	LastAnalyticsError: string?,
	LastAnalyticsErrorTime: number?,
	Connections: { RBXScriptConnection },
}

export type Snapshot = {
	CartId: string,
	Revision: number,
	LastSampleTime: number,
	LastValidSampleTime: number,
	LastValidCFrame: CFrame,
	LastHorizontalSpeed: number,
	ViolationScore: number,
	ConsecutiveViolations: number,
	OwnershipMismatchCount: number,
	CorrectionActive: boolean,
	PositionCorrectionPending: boolean,
}

local log = Logger.new("CartMovementValidationService")
local CartMovementValidationService = {}
local correctionAppliedEvent = Instance.new("BindableEvent")
local meaningfulMovementStartedEvent = Instance.new("BindableEvent")

-- A low-frequency domain transition, fired only after Phase 1Q has actually
-- applied a correction. The validator remains the correction-policy owner.
CartMovementValidationService.CorrectionApplied = correctionAppliedEvent.Event
CartMovementValidationService.MeaningfulMovementStarted = meaningfulMovementStartedEvent.Event

local recordsByCart: { [Model]: RuntimeRecord } = {}
local rejectedReasonsByCart: { [Model]: string } = {}
local activeModelsScratch: { [Model]: boolean } = {}
local recordsScratch: { RuntimeRecord } = {}
local staleRecordsScratch: { RuntimeRecord } = {}
local heartbeatConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local driverChangedConnection: RBXScriptConnection? = nil
local performanceChangedConnection: RBXScriptConnection? = nil
local accumulator = 0
local started = false
local nextRevision = 0
local lastSchedulerError: string? = nil
local lastSchedulerErrorTime: number? = nil
local sampleCycleCount = 0
local processedRecordCount = 0
local correctionAppliedCount = 0
local DEVELOPMENT_EXTREME_HORIZONTAL_SPEED_MULTIPLIER = 2

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function resetMeaningfulMovement(record: RuntimeRecord, driver: Player?)
	record.MovementDriver = driver
	record.MovementCandidateStartedAt = nil
	record.MeaningfulMovementEmitted = false
end

local function observeMeaningfulMovement(
	record: RuntimeRecord,
	driver: Player?,
	authorisedDriver: boolean,
	result: MathResult,
	decision: Decision,
	now: number
)
	if driver == nil or driver ~= record.MovementDriver then
		resetMeaningfulMovement(record, driver)
	end

	local eligible = driver ~= nil
		and authorisedDriver
		and result.HasFinitePhysicalState
		and result.ElapsedTimeValid
		and (result.Severity == "Valid" or result.Severity == "Observation")
		and decision.RequestedAction ~= "Correct"
		and decision.RequestedAction ~= "SevereCorrect"
		and not record.PositionCorrectionPending

	local candidateStartedAt, emitted, shouldEmit = CartAnalyticsMovementTracker.Advance(
		record.MovementCandidateStartedAt,
		record.MeaningfulMovementEmitted,
		result.HorizontalSpeed,
		now,
		eligible,
		CartAnalytics.Development
	)

	record.MovementCandidateStartedAt = candidateStartedAt
	record.MeaningfulMovementEmitted = emitted

	if not shouldEmit then
		return
	end

	meaningfulMovementStartedEvent:Fire(
		record.Cart,
		driver,
		if result.SignedForwardSpeed < 0 then "Reverse" else "Forward",
		now,
		record.Revision
	)
end

local function observeMeaningfulMovementSafely(
	record: RuntimeRecord,
	driver: Player?,
	authorisedDriver: boolean,
	result: MathResult,
	decision: Decision,
	now: number
)
	local succeeded, errorMessage = pcall(function()
		observeMeaningfulMovement(record, driver, authorisedDriver, result, decision, now)
	end)

	if succeeded then
		return
	end

	local resolvedError = tostring(errorMessage)
	local warningDue = record.LastAnalyticsError ~= resolvedError
		or record.LastAnalyticsErrorTime == nil
		or now - (record.LastAnalyticsErrorTime :: number)
			>= CartMovementValidation.Development.WarningWindow

	if warningDue then
		record.LastAnalyticsError = resolvedError
		record.LastAnalyticsErrorTime = now
		log:Warn(
			"Meaningful-movement observer isolated failure Cart=%s CartId=%s Error=%s",
			record.Cart.Name,
			record.CartRecord.CartId,
			resolvedError
		)
	end
end

local function getRoot(cart: Model): BasePart?
	local succeeded, resolvedRoot = pcall(function()
		return CartModelUtility.GetRoot(cart)
	end)

	if not succeeded then
		return nil
	end

	local root = resolvedRoot :: BasePart

	if root.Parent ~= cart then
		return nil
	end

	return root
end

local function getCurrentRegistryRecord(record: RuntimeRecord): CartService.SpawnedCartRecord?
	local currentRecord = CartService:GetCartRecordByOwnerUserId(record.CartRecord.OwnerUserId)

	if currentRecord ~= record.CartRecord or currentRecord.Model ~= record.Cart then
		return nil
	end

	return currentRecord
end

local function isRuntimeContextCurrent(record: RuntimeRecord): boolean
	return recordsByCart[record.Cart] == record
		and record.Cart.Parent ~= nil
		and record.Cart:GetAttribute("RuntimeCart") == true
		and record.Root.Parent == record.Cart
		and getCurrentRegistryRecord(record) ~= nil
end

local function isResetActive(cart: Model, driver: Player?): boolean
	if cart:GetAttribute(CartResetLifecycle.Attributes.Active) == true then
		return true
	end

	return driver ~= nil and CartResetService:IsResetActive(driver, cart)
end

local function resetBaseline(record: RuntimeRecord, now: number, clearViolations: boolean): boolean
	local rootCFrame = record.Root.CFrame
	local linearVelocity = record.Root.AssemblyLinearVelocity
	local angularVelocity = record.Root.AssemblyAngularVelocity

	if
		not CartMovementValidationMath.IsFiniteCFrame(rootCFrame)
		or not CartMovementValidationMath.IsFiniteVector3(linearVelocity)
		or not CartMovementValidationMath.IsFiniteVector3(angularVelocity)
	then
		return false
	end

	record.State = CartMovementValidationState.ResetBaseline(
		record.State,
		rootCFrame,
		linearVelocity,
		now,
		record.Revision,
		clearViolations
	)

	return true
end

local function containsReason(reasons: { string }, target: string): boolean
	for _, reason in reasons do
		if reason == target then
			return true
		end
	end

	return false
end

local function hasMovementReason(reasons: { string }): boolean
	for _, reason in reasons do
		if reason ~= "NetworkOwnerMismatch" then
			return true
		end
	end

	return false
end

local function needsPositionCorrection(reasons: { string }): boolean
	return containsReason(reasons, "PositionCorrectionPending")
		or containsReason(reasons, "NonFiniteCFrame")
		or containsReason(reasons, "SevereHorizontalDisplacement")
		or containsReason(reasons, "SevereUpwardDisplacement")
		or containsReason(reasons, "SevereDownwardDisplacement")
end

local function formatReasons(reasons: { string }): string
	if #reasons == 0 then
		return "none"
	end

	return table.concat(reasons, ",")
end

local function trackSuspiciousResult(
	record: RuntimeRecord,
	result: MathResult,
	decision: Decision,
	now: number,
	driver: Player?,
	networkOwner: Player?
)
	if result.Severity == "Valid" or result.Severity == "Invalid" then
		return
	end

	local development = CartMovementValidation.Development
	local cutoff = now - development.WarningWindow
	local writeIndex = 1

	for _, timestamp in record.ViolationTimes do
		if timestamp >= cutoff then
			record.ViolationTimes[writeIndex] = timestamp
			writeIndex += 1
		end
	end

	for index = #record.ViolationTimes, writeIndex, -1 do
		record.ViolationTimes[index] = nil
	end

	table.insert(record.ViolationTimes, now)

	while #record.ViolationTimes > development.RepeatedWarningThreshold do
		table.remove(record.ViolationTimes, 1)
	end

	local repeated = #record.ViolationTimes >= development.RepeatedWarningThreshold
	local warningDue = record.LastRepeatedWarningTime == nil
		or now - (record.LastRepeatedWarningTime :: number) >= development.WarningWindow

	if repeated and warningDue then
		record.LastRepeatedWarningTime = now
		log:Warn(
			"Repeated suspicious cart movement Cart=%s CartId=%s OwnerUserId=%d DriverUserId=%s NetworkOwnerUserId=%s Severity=%s Score=%d Reasons=%s HorizontalSpeed=%.2f ForwardSpeed=%.2f ReverseSpeed=%.2f LateralSpeed=%.2f VerticalSpeed=%.2f AngularSpeedDegrees=%.2f SampleInterval=%.3f RequestedAction=%s",
			record.Cart.Name,
			record.CartRecord.CartId,
			record.CartRecord.OwnerUserId,
			if driver ~= nil then tostring(driver.UserId) else "server",
			if networkOwner ~= nil then tostring(networkOwner.UserId) else "server",
			result.Severity,
			decision.ViolationScore,
			formatReasons(result.Reasons),
			result.HorizontalSpeed,
			result.ForwardSpeed,
			result.ReverseSpeed,
			result.LateralSpeed,
			result.VerticalSpeed,
			result.AngularSpeedDegrees,
			CartMovementValidation.Development.SampleInterval,
			decision.RequestedAction
		)
	elseif development.DiagnosticsEnabled then
		log:Debug(
			"Observed cart movement Cart=%s CartId=%s Severity=%s Score=%d Reasons=%s",
			record.Cart.Name,
			record.CartRecord.CartId,
			result.Severity,
			decision.ViolationScore,
			formatReasons(result.Reasons)
		)
	end
end

local function unregisterRecord(record: RuntimeRecord, reason: string)
	if recordsByCart[record.Cart] ~= record then
		return
	end

	record.Revision += 1
	record.CorrectionActive = false
	disconnectAll(record.Connections)
	recordsByCart[record.Cart] = nil

	if CartMovementValidation.Development.DiagnosticsEnabled then
		log:Debug(
			"Validator unregistered Cart=%s CartId=%s Reason=%s",
			record.Cart.Name,
			record.CartRecord.CartId,
			reason
		)
	end
end

local function registerRecord(
	cartRecord: CartService.SpawnedCartRecord,
	now: number
): (boolean, string?)
	local cart = cartRecord.Model
	local existing = recordsByCart[cart]

	if existing ~= nil then
		if existing.CartRecord == cartRecord then
			return true, nil
		end

		return false, "cart already has a different validation record"
	end

	if cart.Parent == nil or cart:GetAttribute("RuntimeCart") ~= true then
		return false, "cart is not a live runtime cart"
	end

	if CartService:GetCartRecordByOwnerUserId(cartRecord.OwnerUserId) ~= cartRecord then
		return false, "cart registry record is stale"
	end

	if cart:GetAttribute("CartId") ~= cartRecord.CartId then
		return false, "runtime CartId does not match registry"
	end

	if cart:GetAttribute("OwnerUserId") ~= cartRecord.OwnerUserId then
		return false, "runtime OwnerUserId does not match registry"
	end

	if not CartAssemblyValidationService:IsCartValid(cart) then
		return false, "cart assembly is not valid"
	end

	local root = getRoot(cart)

	if root == nil then
		return false, "cart Root is missing or stale"
	end

	local profile = cartRecord.MovementProfile

	if profile.CartId ~= cartRecord.CartId then
		return false, "effective movement profile does not match CartId"
	end

	-- Registration begins from the server-owned runtime placement, never from a
	-- transform that a newly assigned physics owner may already have changed.
	local baselineCFrame = cartRecord.SpawnCFrame
	local baselineVelocity = Vector3.zero

	if not CartMovementValidationMath.IsFiniteCFrame(baselineCFrame) then
		return false, "cart has no finite server-owned baseline CFrame"
	end

	local baselineTime = if CartMovementValidationMath.IsFiniteNumber(cartRecord.CreatedAt)
			and cartRecord.CreatedAt <= now
		then cartRecord.CreatedAt
		else now

	nextRevision += 1
	local driver = CartOccupantService:GetDriver(cart)
	local runtimeRecord: RuntimeRecord = {
		CartRecord = cartRecord,
		Cart = cart,
		Root = root,
		Profile = profile,
		Thresholds = CartMovementValidationMath.BuildThresholds(profile, CartMovementValidation),
		State = CartMovementValidationState.Create(
			baselineCFrame,
			baselineVelocity,
			baselineTime,
			nextRevision
		),
		Revision = nextRevision,
		LastDriver = driver,
		OwnershipGraceUntil = now + CartMovementValidation.Development.OwnershipTransitionGrace,
		OwnershipMismatchCount = 0,
		CorrectionActive = false,
		PositionCorrectionPending = false,
		CorrectionRevision = 0,
		MovementDriver = driver,
		MovementCandidateStartedAt = nil,
		MeaningfulMovementEmitted = false,
		LastResetMarker = cart:GetAttribute("LastServerReset"),
		LastMovementUpdateMarker = cart:GetAttribute("LastServerMovementUpdate"),
		ViolationTimes = {},
		LastRepeatedWarningTime = nil,
		LastCorrectionLogKey = nil,
		LastCorrectionLogTime = nil,
		LastInternalError = nil,
		LastInternalErrorTime = nil,
		LastAnalyticsError = nil,
		LastAnalyticsErrorTime = nil,
		Connections = {},
	}

	recordsByCart[cart] = runtimeRecord
	rejectedReasonsByCart[cart] = nil

	table.insert(
		runtimeRecord.Connections,
		cart.Destroying:Connect(function()
			unregisterRecord(runtimeRecord, "cart destroying")
		end)
	)
	table.insert(
		runtimeRecord.Connections,
		cart.AncestryChanged:Connect(function()
			if cart.Parent == nil then
				unregisterRecord(runtimeRecord, "cart removed")
			end
		end)
	)
	table.insert(
		runtimeRecord.Connections,
		root.Destroying:Connect(function()
			unregisterRecord(runtimeRecord, "Root destroying")
		end)
	)
	table.insert(
		runtimeRecord.Connections,
		root.AncestryChanged:Connect(function()
			if root.Parent ~= cart then
				unregisterRecord(runtimeRecord, "Root removed or replaced")
			end
		end)
	)

	if CartMovementValidation.Development.DiagnosticsEnabled then
		log:Debug(
			"Validator registered Cart=%s CartId=%s OwnerUserId=%d SampleInterval=%.3f ForwardObservation=%.2f ReverseObservation=%.2f HorizontalSevere=%.2f",
			cart.Name,
			cartRecord.CartId,
			cartRecord.OwnerUserId,
			CartMovementValidation.Development.SampleInterval,
			runtimeRecord.Thresholds.ForwardObservation,
			runtimeRecord.Thresholds.ReverseObservation,
			runtimeRecord.Thresholds.HorizontalSevere
		)
	end

	return true, nil
end

local function restoreExpectedOwnership(record: RuntimeRecord, reason: string): boolean
	return CartOccupantService:RestoreNetworkOwnership(record.Cart, reason)
end

local function clearInvalidMotion(record: RuntimeRecord, now: number)
	CartModelUtility.ZeroVelocities(record.Cart)
	record.Cart:SetAttribute("LastServerMovementUpdate", now)
	record.LastMovementUpdateMarker = now
end

local function canCorrectCurrentRecord(record: RuntimeRecord, now: number): boolean
	if
		not isRuntimeContextCurrent(record)
		or record.CorrectionActive
		or CartAssemblyValidationService:GetState(record.Cart) ~= "Valid"
		or not CartAssemblyValidationService:IsCartValid(record.Cart)
	then
		return false
	end

	local driver = CartOccupantService:GetDriver(record.Cart)

	if isResetActive(record.Cart, driver) then
		return false
	end

	return CartMovementValidationState.IsCorrectionAllowed(
		record.State,
		now,
		CartMovementValidation
	)
end

local function applyCorrection(
	record: RuntimeRecord,
	result: MathResult,
	decision: Decision,
	now: number,
	networkOwner: Player?,
	sampleElapsed: number
)
	if not canCorrectCurrentRecord(record, now) then
		return
	end

	local currentDriver = CartOccupantService:GetDriver(record.Cart)
	local authorisedDriver = currentDriver ~= nil
		and CartOccupantService:CanPlayerControlCart(currentDriver, record.Cart)
	local currentOwner = record.Root:GetNetworkOwner()
	local expectedOwner = if authorisedDriver then currentDriver else nil
	local ownershipMismatch = currentOwner ~= expectedOwner
	local movementViolation = hasMovementReason(result.Reasons)
	local severeMovement = movementViolation and decision.Action == "SevereCorrect"
	local positionCorrectionRequired = needsPositionCorrection(result.Reasons)
	local reason = formatReasons(result.Reasons)

	record.CorrectionActive = true
	local reportedFailure: string? = nil
	local motionCleared = false

	local callSucceeded, correctionSucceeded, ownershipRestored, trustedResetAttempted, trustedResetSucceeded, correctionName = pcall(
		function(): (boolean, boolean, boolean, boolean, string)
			local ownershipWasRestored = true

			if ownershipMismatch then
				ownershipWasRestored =
					restoreExpectedOwnership(record, "Phase 1Q movement validation correction")
			end

			if severeMovement and authorisedDriver and currentDriver ~= nil then
				local resetSucceeded, resetReason =
					CartResetService:BeginReset(currentDriver, record.Cart)

				if resetSucceeded then
					return true, ownershipWasRestored, true, true, "TrustedReset"
				end

				reportedFailure = resetReason or "trusted reset was rejected"

				if isRuntimeContextCurrent(record) then
					clearInvalidMotion(record, Workspace:GetServerTimeNow())
					motionCleared = true
				end

				return false, ownershipWasRestored, true, false, "TrustedResetFailedClearMotion"
			elseif movementViolation then
				clearInvalidMotion(record, now)
				motionCleared = true

				if positionCorrectionRequired then
					return false,
						ownershipWasRestored,
						false,
						false,
						"ClearMotionAwaitingTrustedPositionCorrection"
				end

				return ownershipWasRestored, ownershipWasRestored, false, false, "ClearMotion"
			end

			return ownershipWasRestored, ownershipWasRestored, false, false, "RestoreOwnership"
		end
	)

	local completedAt = Workspace:GetServerTimeNow()
	local actionError = if callSucceeded then reportedFailure else tostring(correctionSucceeded)
	local resolvedCorrectionSucceeded = callSucceeded and correctionSucceeded == true
	local resolvedOwnershipRestored = callSucceeded and ownershipRestored == true
	local resolvedTrustedResetAttempted = callSucceeded and trustedResetAttempted == true
	local resolvedTrustedResetSucceeded = callSucceeded and trustedResetSucceeded == true
	local resolvedCorrectionName = if callSucceeded
		then tostring(correctionName)
		else "InternalCorrectionFailure"
	local appliedCategory: string? = nil

	if callSucceeded then
		if resolvedTrustedResetSucceeded then
			appliedCategory = "CorrectiveReset"
		elseif motionCleared then
			appliedCategory = "VelocityCleared"
		elseif ownershipMismatch and resolvedOwnershipRestored then
			appliedCategory = "NetworkOwnershipRestored"
		end
	end

	if recordsByCart[record.Cart] == record then
		record.CorrectionActive = false

		-- A completed owner API/reset API/velocity-helper attempt receives the
		-- short internal cooldown even when that owner reports failure. A Lua
		-- callback error receives no cooldown, so an internal failure is not
		-- misrepresented as a server correction.
		if callSucceeded then
			record.State = CartMovementValidationState.MarkCorrection(record.State, completedAt)
		end

		record.PositionCorrectionPending = (
			record.PositionCorrectionPending or positionCorrectionRequired
		) and not resolvedTrustedResetSucceeded

		if resolvedCorrectionSucceeded then
			resetBaseline(record, completedAt, resolvedTrustedResetSucceeded)
		end
	end

	if appliedCategory ~= nil then
		record.CorrectionRevision += 1
		correctionAppliedCount += 1
		correctionAppliedEvent:Fire(
			record.Cart,
			currentDriver,
			appliedCategory,
			if decision.Action == "SevereCorrect" then "Severe" else "Corrective",
			result.Reasons[1] or "Unknown",
			record.CorrectionRevision,
			completedAt
		)
	end

	local correctionLogKey =
		string.format("%s|%s|%s", resolvedCorrectionName, result.Severity, reason)
	local correctionLogDue = correctionLogKey ~= record.LastCorrectionLogKey
		or record.LastCorrectionLogTime == nil
		or completedAt - (record.LastCorrectionLogTime :: number)
			>= CartMovementValidation.Development.WarningWindow

	if correctionLogDue then
		record.LastCorrectionLogKey = correctionLogKey
		record.LastCorrectionLogTime = completedAt
		log:Warn(
			"Cart movement correction attempted Cart=%s CartId=%s OwnerUserId=%d DriverUserId=%s PriorNetworkOwnerUserId=%s Severity=%s Score=%d Action=%s Reasons=%s CorrectionSucceeded=%s OwnershipRestored=%s TrustedResetAttempted=%s TrustedResetSucceeded=%s HorizontalSpeed=%.2f VerticalSpeed=%.2f AngularSpeedDegrees=%.2f SampleElapsed=%.3f Error=%s",
			record.Cart.Name,
			record.CartRecord.CartId,
			record.CartRecord.OwnerUserId,
			if currentDriver ~= nil then tostring(currentDriver.UserId) else "server",
			if networkOwner ~= nil then tostring(networkOwner.UserId) else "server",
			result.Severity,
			decision.ViolationScore,
			resolvedCorrectionName,
			reason,
			tostring(resolvedCorrectionSucceeded),
			tostring(resolvedOwnershipRestored),
			tostring(resolvedTrustedResetAttempted),
			tostring(resolvedTrustedResetSucceeded),
			result.HorizontalSpeed,
			result.VerticalSpeed,
			result.AngularSpeedDegrees,
			math.max(0, sampleElapsed),
			actionError or "none"
		)
	end
end

local function evaluateFiniteOnly(record: RuntimeRecord, now: number): MathResult
	return CartMovementValidationMath.EvaluateSample({
		RootCFrame = record.Root.CFrame,
		LinearVelocity = record.Root.AssemblyLinearVelocity,
		AngularVelocity = record.Root.AssemblyAngularVelocity,
		PreviousPosition = nil,
		PreviousHorizontalSpeed = nil,
		ElapsedTime = now - record.State.LastSampleTime,
		TrustedDisplacement = true,
	}, record.Profile, CartMovementValidation, record.Thresholds)
end

local function processExemptFrame(
	record: RuntimeRecord,
	now: number,
	driver: Player?,
	clearViolations: boolean
)
	local finiteResult = evaluateFiniteOnly(record, now)

	if finiteResult.HasFinitePhysicalState then
		resetBaseline(record, now, clearViolations)
		return
	end

	local nextState, decision = CartMovementValidationState.ApplyResult(
		record.State,
		finiteResult,
		record.Root.CFrame,
		record.Root.AssemblyLinearVelocity,
		now,
		CartMovementValidation
	)

	record.State = nextState
	trackSuspiciousResult(record, finiteResult, decision, now, driver, nil)

	-- Trusted reset and assembly-transition owners are already mutating this cart.
	-- Phase 1Q still records the non-finite state, but never starts a competing
	-- correction until that lifecycle state has completed.
end

local function processRecord(record: RuntimeRecord, now: number)
	if not isRuntimeContextCurrent(record) then
		unregisterRecord(record, "registry or Instance context became stale")
		return
	end

	local assemblyState = CartAssemblyValidationService:GetState(record.Cart)

	if assemblyState == "Invalid" or assemblyState == "Destroying" or assemblyState == nil then
		unregisterRecord(record, "cart assembly is no longer valid")
		return
	end

	local driver = CartOccupantService:GetDriver(record.Cart)

	if driver ~= record.LastDriver then
		record.LastDriver = driver
		resetMeaningfulMovement(record, driver)
		record.OwnershipGraceUntil = now
			+ CartMovementValidation.Development.OwnershipTransitionGrace
		record.OwnershipMismatchCount = 0
	end

	local resetMarker = record.Cart:GetAttribute("LastServerReset")
	local movementUpdateMarker = record.Cart:GetAttribute("LastServerMovementUpdate")
	local resetCompleted = resetMarker ~= record.LastResetMarker
	local movementUpdated = movementUpdateMarker ~= record.LastMovementUpdateMarker

	if resetCompleted or movementUpdated then
		record.LastResetMarker = resetMarker
		record.LastMovementUpdateMarker = movementUpdateMarker
		record.OwnershipMismatchCount = 0
		record.MovementCandidateStartedAt = nil

		-- LastServerReset is the trusted committed-reposition marker. A movement
		-- update alone may only mean reset suspension or velocity clearing, so it
		-- must not erase a still-pending position correction.
		if resetCompleted and resetBaseline(record, now, true) then
			record.PositionCorrectionPending = false
			return
		elseif
			movementUpdated
			and not record.PositionCorrectionPending
			and resetBaseline(record, now, true)
		then
			return
		end
	end

	if isResetActive(record.Cart, driver) then
		record.OwnershipMismatchCount = 0
		record.MovementCandidateStartedAt = nil
		processExemptFrame(record, now, driver, true)
		return
	end

	if assemblyState == "Preparing" then
		record.OwnershipMismatchCount = 0
		record.MovementCandidateStartedAt = nil
		processExemptFrame(record, now, driver, false)
		return
	end

	if not CartAssemblyValidationService:IsCartValid(record.Cart) then
		unregisterRecord(record, "cart assembly failed revalidation")
		return
	end

	local elapsedTime = now - record.State.LastSampleTime
	local result = CartMovementValidationMath.EvaluateSample({
		RootCFrame = record.Root.CFrame,
		LinearVelocity = record.Root.AssemblyLinearVelocity,
		AngularVelocity = record.Root.AssemblyAngularVelocity,
		PreviousPosition = record.State.LastPosition,
		PreviousHorizontalSpeed = record.State.LastHorizontalSpeed,
		ElapsedTime = elapsedTime,
		TrustedDisplacement = false,
	}, record.Profile, CartMovementValidation, record.Thresholds)

	local authorisedDriver = driver ~= nil
		and CartOccupantService:CanPlayerControlCart(driver, record.Cart)
	local expectedOwner = if authorisedDriver then driver else nil
	local networkOwner = record.Root:GetNetworkOwner()
	local ownershipMismatch = networkOwner ~= expectedOwner

	if ownershipMismatch and now >= record.OwnershipGraceUntil then
		record.OwnershipMismatchCount = math.min(
			record.OwnershipMismatchCount + 1,
			CartMovementValidation.Development.MaximumViolationScore
		)
		result = CartMovementValidationMath.PromoteResult(
			result,
			if record.OwnershipMismatchCount >= 2 then "Corrective" else "Observation",
			"NetworkOwnerMismatch"
		)
	elseif not ownershipMismatch then
		record.OwnershipMismatchCount = 0
	end

	if
		result.ElapsedTimeValid
		and not authorisedDriver
		and result.HorizontalSpeed > record.State.LastHorizontalSpeed
		and (result.HorizontalSpeed - record.State.LastHorizontalSpeed) / elapsedTime
			> CartMovementValidation.Development.NoDriverAccelerationTolerance
	then
		result = CartMovementValidationMath.PromoteResult(
			result,
			"Observation",
			"NoAuthorityAcceleration"
		)
	end

	if needsPositionCorrection(result.Reasons) then
		record.PositionCorrectionPending = true
	end

	if record.PositionCorrectionPending then
		result =
			CartMovementValidationMath.PromoteResult(result, "Severe", "PositionCorrectionPending")
	end

	local nextState, decision = CartMovementValidationState.ApplyResult(
		record.State,
		result,
		record.Root.CFrame,
		record.Root.AssemblyLinearVelocity,
		now,
		CartMovementValidation
	)

	record.State = nextState
	trackSuspiciousResult(record, result, decision, now, driver, networkOwner)
	observeMeaningfulMovementSafely(record, driver, authorisedDriver, result, decision, now)

	if decision.Action == "Correct" or decision.Action == "SevereCorrect" then
		applyCorrection(record, result, decision, now, networkOwner, elapsedTime)
	end
end

local function logRecordFailure(record: RuntimeRecord, errorMessage: string, now: number)
	local warningDue = record.LastInternalError ~= errorMessage
		or record.LastInternalErrorTime == nil
		or now - (record.LastInternalErrorTime :: number)
			>= CartMovementValidation.Development.WarningWindow

	if warningDue then
		record.LastInternalError = errorMessage
		record.LastInternalErrorTime = now
		log:Warn(
			"Movement validation isolated internal failure Cart=%s CartId=%s OwnerUserId=%d Error=%s",
			record.Cart.Name,
			record.CartRecord.CartId,
			record.CartRecord.OwnerUserId,
			errorMessage
		)
	end

	if record.Cart.Parent == nil or record.Root.Parent ~= record.Cart then
		unregisterRecord(record, "references corrupted after internal failure")
	end
end

local function reconcileRecords(now: number)
	table.clear(activeModelsScratch)

	for _, cartRecord in CartService:GetCartRecords() do
		local cart = cartRecord.Model
		activeModelsScratch[cart] = true

		local current = recordsByCart[cart]

		if current ~= nil and current.CartRecord ~= cartRecord then
			unregisterRecord(current, "registry record replaced")
			current = nil
		end

		if current == nil then
			local callSucceeded, registered, rejectionReason = pcall(function()
				return registerRecord(cartRecord, now)
			end)
			local resolvedReason = if callSucceeded then rejectionReason else tostring(registered)

			if not callSucceeded or registered ~= true then
				resolvedReason = resolvedReason or "registration rejected"

				if rejectedReasonsByCart[cart] ~= resolvedReason then
					rejectedReasonsByCart[cart] = resolvedReason
					log:Warn(
						"Movement validator did not register Cart=%s CartId=%s Reason=%s",
						cart.Name,
						cartRecord.CartId,
						resolvedReason
					)
				end
			end
		end
	end

	table.clear(staleRecordsScratch)

	for cart, record in recordsByCart do
		if not activeModelsScratch[cart] then
			table.insert(staleRecordsScratch, record)
		end
	end

	for _, record in staleRecordsScratch do
		unregisterRecord(record, "cart removed from runtime registry")
	end

	for cart in rejectedReasonsByCart do
		if not activeModelsScratch[cart] then
			rejectedReasonsByCart[cart] = nil
		end
	end
end

local function runSampleCycle()
	local now = Workspace:GetServerTimeNow()
	sampleCycleCount += 1

	reconcileRecords(now)
	table.clear(recordsScratch)

	for _, record in recordsByCart do
		table.insert(recordsScratch, record)
	end

	for _, record in recordsScratch do
		if recordsByCart[record.Cart] ~= record then
			continue
		end

		local callSucceeded, errorMessage = pcall(function()
			processedRecordCount += 1
			processRecord(record, now)
		end)

		if not callSucceeded then
			logRecordFailure(record, tostring(errorMessage), now)
		end
	end
end

function CartMovementValidationService:RegisterCart(
	cartRecord: CartService.SpawnedCartRecord
): (boolean, string?)
	if not started or not CartMovementValidation.Enabled then
		return false, "movement validation service is not active"
	end

	return registerRecord(cartRecord, Workspace:GetServerTimeNow())
end

function CartMovementValidationService:UpdateProfile(
	cartRecord: CartService.SpawnedCartRecord
): (boolean, string?)
	local record = recordsByCart[cartRecord.Model]
	if record == nil or record.CartRecord ~= cartRecord then
		return false, "cart validation record is absent or stale"
	end
	local profile = cartRecord.MovementProfile
	if profile.CartId ~= cartRecord.CartId then
		return false, "effective movement profile does not match CartId"
	end

	-- Preserve the current physical baseline and violation history. Only future
	-- evaluations use thresholds derived from the new authoritative ceiling.
	record.Profile = profile
	record.Thresholds = CartMovementValidationMath.BuildThresholds(profile, CartMovementValidation)
	return true, nil
end

function CartMovementValidationService:UnregisterCart(cart: Model, reason: string?): boolean
	local record = recordsByCart[cart]

	if record == nil then
		return false
	end

	unregisterRecord(record, reason or "explicit unregister")
	return true
end

function CartMovementValidationService:ResetBaseline(cart: Model, reason: string?): boolean
	local record = recordsByCart[cart]

	if record == nil then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	local reset = resetBaseline(record, now, true)

	if reset then
		record.PositionCorrectionPending = false
	end

	if reset and CartMovementValidation.Development.DiagnosticsEnabled then
		log:Debug(
			"Validator baseline reset Cart=%s CartId=%s Reason=%s",
			cart.Name,
			record.CartRecord.CartId,
			reason or "explicit baseline reset"
		)
	end

	return reset
end

function CartMovementValidationService:GetSnapshot(cart: Model): Snapshot?
	local record = recordsByCart[cart]

	if record == nil then
		return nil
	end

	return table.freeze({
		CartId = record.CartRecord.CartId,
		Revision = record.Revision,
		LastSampleTime = record.State.LastSampleTime,
		LastValidSampleTime = record.State.LastValidSampleTime,
		LastValidCFrame = record.State.LastValidCFrame,
		LastHorizontalSpeed = record.State.LastHorizontalSpeed,
		ViolationScore = record.State.ViolationScore,
		ConsecutiveViolations = record.State.ConsecutiveViolations,
		OwnershipMismatchCount = record.OwnershipMismatchCount,
		CorrectionActive = record.CorrectionActive,
		PositionCorrectionPending = record.PositionCorrectionPending,
	})
end

function CartMovementValidationService:GetRecordCount(): number
	local count = 0

	for _ in recordsByCart do
		count += 1
	end

	return count
end

function CartMovementValidationService:GetDiagnostics()
	local recordConnectionCount = 0

	for _, record in recordsByCart do
		recordConnectionCount += #record.Connections
	end

	return table.freeze({
		Started = started,
		RecordCount = self:GetRecordCount(),
		RecordConnectionCount = recordConnectionCount,
		SharedConnectionCount = (if heartbeatConnection ~= nil then 1 else 0)
			+ (if playerRemovingConnection ~= nil then 1 else 0)
			+ (if driverChangedConnection ~= nil then 1 else 0)
			+ (if performanceChangedConnection ~= nil then 1 else 0),
		SchedulerCount = if heartbeatConnection ~= nil then 1 else 0,
		SampleCycleCount = sampleCycleCount,
		ProcessedRecordCount = processedRecordCount,
		CorrectionAppliedCount = correctionAppliedCount,
	})
end

function CartMovementValidationService:InjectDevelopmentViolation(
	cart: Model,
	violationId: string
): (boolean, string?)
	if
		Environment.Name ~= "Development"
		or not Environment.EnableDebugTools
		or not RunService:IsStudio()
	then
		return false, "movement failure injection is available only in Development Studio"
	end

	if not started or not CartMovementValidation.Enabled then
		return false, "movement validation service is not active"
	end

	if violationId ~= CartGreyboxViolationIds.ExtremeHorizontalVelocity then
		return false, "unsupported movement failure-injection identifier"
	end

	local record = recordsByCart[cart]

	if record == nil or not isRuntimeContextCurrent(record) then
		return false, "cart is not registered with movement validation"
	end

	if
		record.CorrectionActive
		or CartAssemblyValidationService:GetState(cart) ~= "Valid"
		or not CartAssemblyValidationService:IsCartValid(cart)
	then
		return false, "cart is not in a valid injectable lifecycle state"
	end

	local driver = CartOccupantService:GetDriver(cart)

	if isResetActive(cart, driver) then
		return false, "cart reset is active"
	end

	local root = record.Root
	local rootCFrame = root.CFrame

	if root.Anchored or not CartMovementValidationMath.IsFiniteCFrame(rootCFrame) then
		return false, "cart Root is not physically injectable"
	end

	local look = rootCFrame.LookVector
	local horizontalForward = Vector3.new(look.X, 0, look.Z)

	if horizontalForward.Magnitude <= 1e-6 then
		return false, "cart Root has no finite horizontal forward direction"
	end

	local injectedSpeed = CartMovementValidation.SystemSafety.MaximumHorizontalSpeed
		* DEVELOPMENT_EXTREME_HORIZONTAL_SPEED_MULTIPLIER

	root.AssemblyLinearVelocity = horizontalForward.Unit * injectedSpeed

	log:Warn(
		"Injected Development movement violation Cart=%s CartId=%s ViolationId=%s HorizontalSpeed=%.2f SafetyCeiling=%.2f",
		cart.Name,
		record.CartRecord.CartId,
		violationId,
		injectedSpeed,
		CartMovementValidation.SystemSafety.MaximumHorizontalSpeed
	)

	return true, nil
end

function CartMovementValidationService:Start()
	if started then
		return
	end

	local validation = CartMovementValidationConfigValidator.Validate(CartMovementValidation)

	if not validation.IsValid then
		for _, validationError in validation.Errors do
			log:Warn("Invalid movement validation configuration: %s", validationError)
		end

		return
	end

	started = true
	accumulator = 0
	sampleCycleCount = 0
	processedRecordCount = 0
	correctionAppliedCount = 0

	if not CartMovementValidation.Enabled then
		log:Info("Cart movement validation disabled by configuration")
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime

		if accumulator < CartMovementValidation.Development.SampleInterval then
			return
		end

		accumulator %= CartMovementValidation.Development.SampleInterval

		local callSucceeded, errorMessage = pcall(runSampleCycle)

		if not callSucceeded then
			local now = Workspace:GetServerTimeNow()
			local resolvedError = tostring(errorMessage)
			local warningDue = lastSchedulerError ~= resolvedError
				or lastSchedulerErrorTime == nil
				or now - (lastSchedulerErrorTime :: number)
					>= CartMovementValidation.Development.WarningWindow

			if warningDue then
				lastSchedulerError = resolvedError
				lastSchedulerErrorTime = now
				log:Warn("Movement validation scheduler recovered from error: %s", resolvedError)
			end
		end
	end)
	driverChangedConnection = CartOccupantService.DriverChanged:Connect(
		function(cart: Model, _previousDriver: Player?, nextDriver: Player?)
			local record = recordsByCart[cart]

			if record ~= nil then
				resetMeaningfulMovement(record, nextDriver)
			end
		end
	)
	performanceChangedConnection = CartService.PerformanceChanged:Connect(function(cartRecord)
		local updated, updateError = self:UpdateProfile(cartRecord)
		if not updated and recordsByCart[cartRecord.Model] ~= nil then
			log:Warn(
				"Cart performance validation refresh rejected Cart=%s Error=%s",
				cartRecord.Model.Name,
				tostring(updateError)
			)
		end
	end)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		table.clear(staleRecordsScratch)

		for _, record in recordsByCart do
			if record.CartRecord.OwnerUserId == player.UserId then
				table.insert(staleRecordsScratch, record)
			end
		end

		for _, record in staleRecordsScratch do
			unregisterRecord(record, "owning Player removing")
		end
	end)

	log:Info(
		"Cart movement validation ready SampleInterval=%.3f SamplesPerSecond=%.2f",
		CartMovementValidation.Development.SampleInterval,
		1 / CartMovementValidation.Development.SampleInterval
	)
end

function CartMovementValidationService:Stop()
	if not started then
		return
	end

	started = false

	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	if playerRemovingConnection ~= nil then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	if driverChangedConnection ~= nil then
		driverChangedConnection:Disconnect()
		driverChangedConnection = nil
	end

	if performanceChangedConnection ~= nil then
		performanceChangedConnection:Disconnect()
		performanceChangedConnection = nil
	end

	table.clear(recordsScratch)

	for _, record in recordsByCart do
		table.insert(recordsScratch, record)
	end

	for _, record in recordsScratch do
		unregisterRecord(record, "service stopping")
	end

	table.clear(recordsScratch)
	table.clear(staleRecordsScratch)
	table.clear(rejectedReasonsByCart)
	table.clear(activeModelsScratch)
	accumulator = 0
	lastSchedulerError = nil
	lastSchedulerErrorTime = nil
	sampleCycleCount = 0
	processedRecordCount = 0
	correctionAppliedCount = 0

	log:Info("Cart movement validation stopped")
end

return CartMovementValidationService
