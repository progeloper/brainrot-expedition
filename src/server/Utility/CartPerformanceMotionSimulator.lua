--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CartPerformanceTest = require(ReplicatedStorage.Shared.Config.CartPerformanceTest)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local CartMovementTypes = require(ReplicatedStorage.Shared.Types.CartMovementTypes)
local CartMovementMath = require(ReplicatedStorage.Shared.Utility.CartMovementMath)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

type EffectiveMovementProfile = CartMovementTypes.EffectiveMovementProfile

export type MotionPhase = "Forward" | "Coast" | "Brake" | "Stopped" | "Reverse"

export type RuntimeCartRecord = {
	Model: Model,
	MovementProfile: EffectiveMovementProfile,
}

export type MotionPlan = {
	IsValid: boolean,
	CycleTime: number,
	Phase: MotionPhase,
	TargetForwardSpeed: number,
	PlannedForwardSpeed: number,
	DeltaForwardSpeed: number,
	Response: number,
	TargetYawRate: number,
	PlannedYawRate: number,
	DeltaYawRate: number,
	EffectiveDeltaTime: number,
}

export type Diagnostics = {
	Started: boolean,
	RecordCount: number,
	SchedulerCount: number,
	StepCount: number,
	AppliedRecordCount: number,
	LinearImpulseCount: number,
	AngularImpulseCount: number,
	SkippedRecordCount: number,
	ErrorCount: number,
	ElapsedSeconds: number,
	CycleDuration: number,
}

export type Dependencies = {
	IsAllowed: (() -> boolean)?,
	Clock: (() -> number)?,
	ConnectHeartbeat: (((number) -> ()) -> any)?,
	ResolveRoot: ((Model) -> BasePart)?,
	IsRecordLive: ((Model, BasePart) -> boolean)?,
	ReadPhysicalState: ((BasePart) -> (Vector3, Vector3, Vector3, number, boolean))?,
	ApplyLinearImpulse: ((BasePart, Vector3) -> ())?,
	ApplyAngularImpulse: ((BasePart, Vector3) -> ())?,
	SetAttribute: ((Model, string, any) -> ())?,
	Warn: ((string) -> ())?,
}

export type Simulator = {
	Start: (self: Simulator, records: { RuntimeCartRecord }) -> boolean,
	Stop: (self: Simulator) -> boolean,
	GetDiagnostics: (self: Simulator) -> Diagnostics,
}

type InternalRecord = {
	Model: Model,
	Root: BasePart,
	MovementProfile: EffectiveMovementProfile,
	LastPhase: MotionPhase,
}

type SimulatorPrivate = Simulator & {
	_isAllowed: () -> boolean,
	_clock: (() -> number)?,
	_connectHeartbeat: ((number) -> ()) -> any,
	_resolveRoot: (Model) -> BasePart,
	_isRecordLive: (Model, BasePart) -> boolean,
	_readPhysicalState: (BasePart) -> (Vector3, Vector3, Vector3, number, boolean),
	_applyLinearImpulse: (BasePart, Vector3) -> (),
	_applyAngularImpulse: (BasePart, Vector3) -> (),
	_setAttribute: (Model, string, any) -> (),
	_warn: (string) -> (),
	_records: { InternalRecord },
	_connection: any?,
	_started: boolean,
	_elapsedSeconds: number,
	_lastClock: number?,
	_stepCount: number,
	_appliedModels: { [Model]: boolean },
	_appliedRecordCount: number,
	_linearImpulseCount: number,
	_angularImpulseCount: number,
	_skippedRecordCount: number,
	_errorCount: number,
}

local CYCLE_DURATION = 27
local MAXIMUM_EFFECTIVE_DELTA_TIME = 0.25
local MINIMUM_HORIZONTAL_DIRECTION_MAGNITUDE = 1e-5
local ANGULAR_TARGET_FRACTION = 0.04
local STEERING_ALTERNATION_DURATION = 1.5
local FORWARD_TARGET_CAP = 6
local FORWARD_HUNTING_SPEED_FRACTION = 0.3

local ACTIVE_ATTRIBUTE = "Phase1TPerformanceMotionActive"
local PHASE_ATTRIBUTE = "Phase1TPerformanceMotionPhase"

local log = Logger.new("CartPerformanceMotionSimulator")
local SimulatorMethods = {}
SimulatorMethods.__index = SimulatorMethods

local CartPerformanceMotionSimulator = {}

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isFiniteVector(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function defaultIsAllowed(): boolean
	return CartPerformanceTest.Enabled
		and Environment.Name == "Development"
		and Environment.EnableDebugTools
		and RunService:IsStudio()
end

local function defaultConnectHeartbeat(callback: (number) -> ()): RBXScriptConnection
	return RunService.Heartbeat:Connect(callback)
end

local function defaultResolveRoot(cart: Model): BasePart
	local root = cart:FindFirstChild("Root")

	assert(root ~= nil and root:IsA("BasePart"), "performance cart requires Root BasePart")

	return root
end

local function defaultIsRecordLive(cart: Model, root: BasePart): boolean
	return cart.Parent ~= nil
		and root.Parent ~= nil
		and root:IsDescendantOf(cart)
		and not root.Anchored
end

local function defaultReadPhysicalState(
	root: BasePart
): (Vector3, Vector3, Vector3, number, boolean)
	return root.CFrame.LookVector,
		root.AssemblyLinearVelocity,
		root.AssemblyAngularVelocity,
		root.AssemblyMass,
		root.Anchored
end

local function defaultApplyLinearImpulse(root: BasePart, impulse: Vector3)
	root:ApplyImpulse(impulse)
end

local function defaultApplyAngularImpulse(root: BasePart, impulse: Vector3)
	root:ApplyAngularImpulse(impulse)
end

local function defaultSetAttribute(cart: Model, attributeName: string, value: any)
	cart:SetAttribute(attributeName, value)
end

local function defaultWarn(message: string)
	log:Warn("%s", message)
end

local function assertPositiveFinite(value: number, field: string)
	assert(
		type(value) == "number" and isFiniteNumber(value) and value > 0,
		string.format("MovementProfile.%s must be a positive finite number", field)
	)
end

local function assertProfile(profile: EffectiveMovementProfile)
	assert(type(profile) == "table", "MovementProfile must be a table")
	assertPositiveFinite(profile.HuntingSpeed, "HuntingSpeed")
	assertPositiveFinite(profile.MaxTravelSpeed, "MaxTravelSpeed")
	assertPositiveFinite(profile.ControlReferenceSpeed, "ControlReferenceSpeed")
	assert(
		profile.HuntingSpeed < profile.MaxTravelSpeed,
		"MovementProfile.HuntingSpeed must be below MaxTravelSpeed"
	)
	assertPositiveFinite(profile.ForwardAcceleration, "ForwardAcceleration")
	assertPositiveFinite(profile.HighSpeedAccelerationMultiplier, "HighSpeedAccelerationMultiplier")
	assertPositiveFinite(profile.AccelerationCurveExponent, "AccelerationCurveExponent")
	assertPositiveFinite(profile.CoastDeceleration, "CoastDeceleration")
	assertPositiveFinite(
		profile.HighSpeedCoastDecelerationMultiplier,
		"HighSpeedCoastDecelerationMultiplier"
	)
	assertPositiveFinite(profile.Braking, "Braking")
	assertPositiveFinite(profile.HighSpeedBrakingMultiplier, "HighSpeedBrakingMultiplier")
	assertPositiveFinite(profile.RecoveryBackupSpeed, "RecoveryBackupSpeed")
	assertPositiveFinite(profile.RecoveryBackupAcceleration, "RecoveryBackupAcceleration")
	assertPositiveFinite(profile.RecoveryBackupDeceleration, "RecoveryBackupDeceleration")
	assertPositiveFinite(profile.TurnRate, "TurnRate")
	assertPositiveFinite(profile.MaxAngularSpeed, "MaxAngularSpeed")
	assertPositiveFinite(profile.DriveForceLimit, "DriveForceLimit")
end

local function getCycleTime(elapsedSeconds: number): number
	if not isFiniteNumber(elapsedSeconds) then
		return 0
	end

	return elapsedSeconds % CYCLE_DURATION
end

local function getPhase(cycleTime: number): MotionPhase
	-- This bounded oscillation is performance instrumentation, not an alternate
	-- driver, Phase 1C controller, or top-speed certification. Short low-speed
	-- travel keeps each physical cart near its lane spawn during long captures.
	if cycleTime < 4.5 then
		return "Forward"
	elseif cycleTime < 4.75 then
		return "Coast"
	elseif cycleTime < 6 then
		return "Brake"
	elseif cycleTime < 9 then
		return "Stopped"
	elseif cycleTime < 17 then
		return "Reverse"
	elseif cycleTime < 17.15 then
		return "Coast"
	elseif cycleTime < 18.5 then
		return "Brake"
	else
		return "Stopped"
	end
end

local function getResponse(
	phase: MotionPhase,
	currentForwardSpeed: number,
	profile: EffectiveMovementProfile
): number
	local controlSpeed = math.abs(currentForwardSpeed)

	if phase == "Forward" then
		local multiplier = CartMovementMath.InterpolateBySpeed(
			controlSpeed,
			profile.HuntingSpeed,
			profile.ControlReferenceSpeed,
			1,
			profile.HighSpeedAccelerationMultiplier,
			profile.AccelerationCurveExponent
		)

		return profile.ForwardAcceleration * multiplier
	elseif phase == "Coast" and currentForwardSpeed >= 0 then
		local multiplier = CartMovementMath.InterpolateBySpeed(
			controlSpeed,
			profile.HuntingSpeed,
			profile.ControlReferenceSpeed,
			1,
			profile.HighSpeedCoastDecelerationMultiplier,
			1
		)

		return profile.CoastDeceleration * multiplier
	elseif phase == "Brake" and currentForwardSpeed >= 0 then
		local multiplier = CartMovementMath.InterpolateBySpeed(
			controlSpeed,
			profile.HuntingSpeed,
			profile.ControlReferenceSpeed,
			1,
			profile.HighSpeedBrakingMultiplier,
			1
		)

		return profile.Braking * multiplier
	elseif phase == "Reverse" then
		return profile.RecoveryBackupAcceleration
	end

	return if currentForwardSpeed < 0 then profile.RecoveryBackupDeceleration else profile.Braking
end

local function computePlanValues(
	elapsedSeconds: number,
	currentForwardSpeed: number,
	currentYawRate: number,
	deltaTime: number,
	profile: EffectiveMovementProfile
): (
	boolean,
	number,
	MotionPhase,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number
)
	local cycleTime = getCycleTime(elapsedSeconds)
	local phase = getPhase(cycleTime)
	local effectiveDeltaTime = if isFiniteNumber(deltaTime)
		then math.clamp(deltaTime, 0, MAXIMUM_EFFECTIVE_DELTA_TIME)
		else 0

	if not isFiniteNumber(currentForwardSpeed) or not isFiniteNumber(currentYawRate) then
		return false, cycleTime, phase, 0, 0, 0, 0, 0, 0, 0, effectiveDeltaTime
	end

	local targetForwardSpeed = if phase == "Forward"
		then math.min(
			FORWARD_TARGET_CAP,
			profile.HuntingSpeed * FORWARD_HUNTING_SPEED_FRACTION,
			profile.MaxTravelSpeed
		)
		elseif phase == "Reverse" then -profile.RecoveryBackupSpeed
		else 0
	local response =
		math.min(getResponse(phase, currentForwardSpeed, profile), profile.DriveForceLimit)
	local plannedForwardSpeed = CartMovementMath.ApproachSpeed(
		currentForwardSpeed,
		targetForwardSpeed,
		response,
		effectiveDeltaTime
	)
	local targetYawRate = 0

	if phase == "Forward" or phase == "Reverse" then
		local direction = if math.floor(cycleTime / STEERING_ALTERNATION_DURATION) % 2 == 0
			then 1
			else -1
		local maximumYawRate = math.rad(math.min(profile.TurnRate, profile.MaxAngularSpeed))

		targetYawRate = direction * maximumYawRate * ANGULAR_TARGET_FRACTION
	end

	local yawResponse = math.rad(profile.MaxAngularSpeed) * ANGULAR_TARGET_FRACTION
	local plannedYawRate = CartMovementMath.ApproachSpeed(
		currentYawRate,
		targetYawRate,
		yawResponse,
		effectiveDeltaTime
	)

	return true,
		cycleTime,
		phase,
		targetForwardSpeed,
		plannedForwardSpeed,
		plannedForwardSpeed - currentForwardSpeed,
		response,
		targetYawRate,
		plannedYawRate,
		plannedYawRate - currentYawRate,
		effectiveDeltaTime
end

function CartPerformanceMotionSimulator.ComputePlan(
	elapsedSeconds: number,
	currentForwardSpeed: number,
	currentYawRate: number,
	deltaTime: number,
	profile: EffectiveMovementProfile
): MotionPlan
	assertProfile(profile)

	local isValid, cycleTime, phase, targetForwardSpeed, plannedForwardSpeed, deltaForwardSpeed, response, targetYawRate, plannedYawRate, deltaYawRate, effectiveDeltaTime =
		computePlanValues(elapsedSeconds, currentForwardSpeed, currentYawRate, deltaTime, profile)

	return table.freeze({
		IsValid = isValid,
		CycleTime = cycleTime,
		Phase = phase,
		TargetForwardSpeed = targetForwardSpeed,
		PlannedForwardSpeed = plannedForwardSpeed,
		DeltaForwardSpeed = deltaForwardSpeed,
		Response = response,
		TargetYawRate = targetYawRate,
		PlannedYawRate = plannedYawRate,
		DeltaYawRate = deltaYawRate,
		EffectiveDeltaTime = effectiveDeltaTime,
	})
end

function CartPerformanceMotionSimulator.GetPhaseAtTime(elapsedSeconds: number): MotionPhase
	return getPhase(getCycleTime(elapsedSeconds))
end

local function clearOwnedAttributes(self: SimulatorPrivate)
	for _, record in self._records do
		pcall(self._setAttribute, record.Model, ACTIVE_ATTRIBUTE, nil)
		pcall(self._setAttribute, record.Model, PHASE_ATTRIBUTE, nil)
	end
end

local function normalizeHorizontalDirection(direction: Vector3): Vector3?
	if not isFiniteVector(direction) then
		return nil
	end

	local horizontal = Vector3.new(direction.X, 0, direction.Z)

	if horizontal.Magnitude <= MINIMUM_HORIZONTAL_DIRECTION_MAGNITUDE then
		return nil
	end

	return horizontal.Unit
end

local function stepRecord(self: SimulatorPrivate, record: InternalRecord, deltaTime: number)
	if not self._isRecordLive(record.Model, record.Root) then
		self._skippedRecordCount += 1
		return
	end

	local forward, linearVelocity, angularVelocity, assemblyMass, anchored =
		self._readPhysicalState(record.Root)
	local horizontalForward = normalizeHorizontalDirection(forward)

	if
		horizontalForward == nil
		or not isFiniteVector(linearVelocity)
		or not isFiniteVector(angularVelocity)
		or not isFiniteNumber(assemblyMass)
		or assemblyMass <= 0
		or anchored
	then
		self._skippedRecordCount += 1
		return
	end

	local currentForwardSpeed = linearVelocity:Dot(horizontalForward)
	local currentYawRate = angularVelocity.Y
	local isValid, _cycleTime, phase, _targetForwardSpeed, _plannedForwardSpeed, deltaForwardSpeed, _response, _targetYawRate, _plannedYawRate, deltaYawRate =
		computePlanValues(
			self._elapsedSeconds,
			currentForwardSpeed,
			currentYawRate,
			deltaTime,
			record.MovementProfile
		)

	if not isValid then
		self._skippedRecordCount += 1
		return
	end

	if phase ~= record.LastPhase then
		record.LastPhase = phase
		self._setAttribute(record.Model, PHASE_ATTRIBUTE, phase)
	end

	if math.abs(deltaForwardSpeed) > 0 then
		local linearImpulse = horizontalForward * (deltaForwardSpeed * assemblyMass)

		if isFiniteVector(linearImpulse) then
			self._applyLinearImpulse(record.Root, linearImpulse)
			self._linearImpulseCount += 1

			if not self._appliedModels[record.Model] then
				self._appliedModels[record.Model] = true
				self._appliedRecordCount += 1
			end
		end
	end

	if math.abs(deltaYawRate) > 0 then
		local angularImpulse = Vector3.yAxis * (deltaYawRate * assemblyMass)

		if isFiniteVector(angularImpulse) then
			self._applyAngularImpulse(record.Root, angularImpulse)
			self._angularImpulseCount += 1
		end
	end
end

local function stepAll(self: SimulatorPrivate, heartbeatDeltaTime: number)
	local deltaTime = heartbeatDeltaTime
	local clock = self._clock

	if clock ~= nil then
		local now = clock()
		local lastClock = self._lastClock

		if not isFiniteNumber(now) or lastClock == nil or now < lastClock then
			self._skippedRecordCount += #self._records
			return
		end

		deltaTime = now - lastClock
		self._lastClock = now
	end

	if not isFiniteNumber(deltaTime) or deltaTime < 0 then
		self._skippedRecordCount += #self._records
		return
	end

	self._elapsedSeconds += deltaTime
	self._stepCount += 1

	for _, record in self._records do
		stepRecord(self, record, deltaTime)
	end
end

function CartPerformanceMotionSimulator.new(dependencies: Dependencies?): Simulator
	local resolved = dependencies or {}

	return setmetatable({
		_isAllowed = resolved.IsAllowed or defaultIsAllowed,
		_clock = resolved.Clock,
		_connectHeartbeat = resolved.ConnectHeartbeat or defaultConnectHeartbeat,
		_resolveRoot = resolved.ResolveRoot or defaultResolveRoot,
		_isRecordLive = resolved.IsRecordLive or defaultIsRecordLive,
		_readPhysicalState = resolved.ReadPhysicalState or defaultReadPhysicalState,
		_applyLinearImpulse = resolved.ApplyLinearImpulse or defaultApplyLinearImpulse,
		_applyAngularImpulse = resolved.ApplyAngularImpulse or defaultApplyAngularImpulse,
		_setAttribute = resolved.SetAttribute or defaultSetAttribute,
		_warn = resolved.Warn or defaultWarn,
		_records = {},
		_connection = nil,
		_started = false,
		_elapsedSeconds = 0,
		_lastClock = nil,
		_stepCount = 0,
		_appliedModels = {},
		_appliedRecordCount = 0,
		_linearImpulseCount = 0,
		_angularImpulseCount = 0,
		_skippedRecordCount = 0,
		_errorCount = 0,
	}, SimulatorMethods) :: any
end

function SimulatorMethods.Start(self: SimulatorPrivate, records: { RuntimeCartRecord }): boolean
	if self._started then
		return false
	end

	assert(self._isAllowed(), "Phase 1T motion simulator is Development Studio only")
	assert(type(records) == "table" and #records > 0, "motion records must be nonempty")

	local seenModels: { [Model]: boolean } = {}
	local prepared: { InternalRecord } = {}

	for recordIndex, sourceRecord in records do
		assert(
			type(recordIndex) == "number"
				and recordIndex % 1 == 0
				and recordIndex >= 1
				and recordIndex <= #records,
			"motion records must be an array"
		)
		assert(type(sourceRecord) == "table", "motion record must be a table")
		assert(
			typeof(sourceRecord.Model) == "Instance" and sourceRecord.Model:IsA("Model"),
			"motion record Model must be a Model"
		)
		assert(not seenModels[sourceRecord.Model], "motion records cannot duplicate a cart")
		assertProfile(sourceRecord.MovementProfile)

		seenModels[sourceRecord.Model] = true
		table.insert(prepared, {
			Model = sourceRecord.Model,
			Root = self._resolveRoot(sourceRecord.Model),
			MovementProfile = sourceRecord.MovementProfile,
			LastPhase = "Forward",
		})
	end

	self._records = prepared
	self._elapsedSeconds = 0
	self._stepCount = 0
	table.clear(self._appliedModels)
	self._appliedRecordCount = 0
	self._linearImpulseCount = 0
	self._angularImpulseCount = 0
	self._skippedRecordCount = 0
	self._errorCount = 0
	self._lastClock = if self._clock ~= nil then self._clock() else nil

	if self._lastClock ~= nil and not isFiniteNumber(self._lastClock) then
		table.clear(self._records)
		self._lastClock = nil
		error("Phase 1T motion clock must return a finite number", 2)
	end

	local attributesSucceeded, attributeError = pcall(function()
		for _, record in self._records do
			self._setAttribute(record.Model, ACTIVE_ATTRIBUTE, true)
			self._setAttribute(record.Model, PHASE_ATTRIBUTE, record.LastPhase)
		end
	end)

	if not attributesSucceeded then
		clearOwnedAttributes(self)
		table.clear(self._records)
		self._lastClock = nil
		error(
			string.format("Phase 1T motion attributes could not initialize: %s", attributeError),
			2
		)
	end

	local connectionSucceeded, connectionOrError = pcall(
		self._connectHeartbeat,
		function(heartbeatDeltaTime: number)
			local succeeded, stepError = pcall(stepAll, self, heartbeatDeltaTime)

			if not succeeded then
				self._errorCount += 1
				self._warn(
					string.format(
						"Performance motion scheduler stopped after error: %s",
						tostring(stepError)
					)
				)
				self:Stop()
			end
		end
	)

	if not connectionSucceeded or connectionOrError == nil then
		clearOwnedAttributes(self)
		table.clear(self._records)
		self._lastClock = nil
		error(
			string.format(
				"Phase 1T motion scheduler could not start: %s",
				tostring(connectionOrError)
			),
			2
		)
	end

	self._connection = connectionOrError
	self._started = true

	return true
end

function SimulatorMethods.Stop(self: SimulatorPrivate): boolean
	if not self._started and self._connection == nil and #self._records == 0 then
		return false
	end

	self._started = false

	local connection = self._connection

	self._connection = nil

	if connection ~= nil then
		pcall(function()
			connection:Disconnect()
		end)
	end

	clearOwnedAttributes(self)
	table.clear(self._records)
	table.clear(self._appliedModels)
	self._lastClock = nil

	return true
end

function SimulatorMethods.GetDiagnostics(self: SimulatorPrivate): Diagnostics
	return table.freeze({
		Started = self._started,
		RecordCount = #self._records,
		SchedulerCount = if self._connection ~= nil then 1 else 0,
		StepCount = self._stepCount,
		AppliedRecordCount = self._appliedRecordCount,
		LinearImpulseCount = self._linearImpulseCount,
		AngularImpulseCount = self._angularImpulseCount,
		SkippedRecordCount = self._skippedRecordCount,
		ErrorCount = self._errorCount,
		ElapsedSeconds = self._elapsedSeconds,
		CycleDuration = CYCLE_DURATION,
	})
end

CartPerformanceMotionSimulator.Attributes = table.freeze({
	Active = ACTIVE_ATTRIBUTE,
	Phase = PHASE_ATTRIBUTE,
})
CartPerformanceMotionSimulator.CycleDuration = CYCLE_DURATION

return table.freeze(CartPerformanceMotionSimulator)
