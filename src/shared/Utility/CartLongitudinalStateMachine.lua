--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartMovementTypes = require(ReplicatedStorage.Shared.Types.CartMovementTypes)

type EffectiveMovementProfile = CartMovementTypes.EffectiveMovementProfile
type LongitudinalControlAction = CartMovementTypes.LongitudinalControlAction
type LongitudinalIntent = CartMovementTypes.LongitudinalIntent
type LongitudinalState = CartMovementTypes.LongitudinalState
type LongitudinalTransition = CartMovementTypes.LongitudinalTransition
type LongitudinalSnapshot = CartMovementTypes.LongitudinalSnapshot

export type StepResult = {
	Snapshot: LongitudinalSnapshot,
	Intent: LongitudinalIntent,
	RequestedState: LongitudinalState,
	StateChanged: boolean,
	RecoveredFromInvalidState: boolean,
}

local CartLongitudinalStateMachine = {}

local TIME_BOUNDARY_EPSILON = 1e-9

CartLongitudinalStateMachine.Attributes = table.freeze({
	State = "LongitudinalState",
	PreviousState = "LongitudinalPreviousState",
	RequestedState = "LongitudinalRequestedState",
	StateEnteredAt = "LongitudinalStateEnteredAt",
	TransitionStartedAt = "LongitudinalTransitionStartedAt",
	Revision = "LongitudinalStateRevision",
	AuthorityEpoch = "LongitudinalAuthorityEpoch",
})

local VALID_STATES: { [string]: boolean } = table.freeze({
	Idle = true,
	Accelerating = true,
	Cruising = true,
	Coasting = true,
	Braking = true,
	Stopped = true,
	Reverse = true,
})

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function CartLongitudinalStateMachine.IsValidState(value: unknown): boolean
	return type(value) == "string" and VALID_STATES[value] == true
end

function CartLongitudinalStateMachine.ResolveIntent(
	throttle: number,
	inputDeadzone: number
): LongitudinalIntent
	if throttle > inputDeadzone then
		return "Forward"
	elseif throttle < -inputDeadzone then
		return "Reverse"
	end

	return "None"
end

function CartLongitudinalStateMachine.RequiresReverseEpisodeRestart(
	previousIntent: LongitudinalIntent,
	nextIntent: LongitudinalIntent,
	previousEpisode: number,
	nextEpisode: number
): boolean
	return previousIntent == "Reverse" and nextIntent == "Reverse" and nextEpisode > previousEpisode
end

local function freezeTransition(
	targetState: LongitudinalState,
	startedAt: number
): LongitudinalTransition
	return table.freeze({
		TargetState = targetState,
		StartedAt = startedAt,
	})
end

local function freezeSnapshot(
	currentState: LongitudinalState,
	previousState: LongitudinalState,
	currentTransition: LongitudinalTransition?,
	stateEnteredAt: number
): LongitudinalSnapshot
	return table.freeze({
		CurrentState = currentState,
		PreviousState = previousState,
		CurrentTransition = currentTransition,
		StateEnteredAt = stateEnteredAt,
	})
end

function CartLongitudinalStateMachine.Create(now: number): LongitudinalSnapshot
	local createdAt = if isFiniteNumber(now) then now else 0

	return freezeSnapshot("Idle", "Idle", nil, createdAt)
end

local function snapshotIsValid(snapshot: unknown): boolean
	if type(snapshot) ~= "table" then
		return false
	end

	local candidate = snapshot :: any

	if
		not CartLongitudinalStateMachine.IsValidState(candidate.CurrentState)
		or not CartLongitudinalStateMachine.IsValidState(candidate.PreviousState)
		or not isFiniteNumber(candidate.StateEnteredAt)
	then
		return false
	end

	local transition = candidate.CurrentTransition

	return transition == nil
		or (
			type(transition) == "table"
			and CartLongitudinalStateMachine.IsValidState(transition.TargetState)
			and isFiniteNumber(transition.StartedAt)
		)
end

local function getRequestedState(
	currentState: LongitudinalState,
	intent: LongitudinalIntent,
	forwardSpeed: number,
	throttle: number,
	profile: EffectiveMovementProfile
): LongitudinalState
	local stopped = math.abs(forwardSpeed) <= profile.NearZeroSpeedThreshold

	if intent == "None" then
		return if stopped then "Idle" else "Coasting"
	elseif intent == "Reverse" then
		return "Reverse"
	end

	if forwardSpeed < -profile.NearZeroSpeedThreshold or currentState == "Reverse" then
		return "Accelerating"
	end

	local targetSpeed = math.max(throttle, 0) * profile.MaxTravelSpeed

	if currentState == "Cruising" then
		if forwardSpeed > targetSpeed + profile.NearZeroSpeedThreshold then
			return "Coasting"
		elseif forwardSpeed < targetSpeed - profile.NearZeroSpeedThreshold then
			return "Accelerating"
		end

		return "Cruising"
	end

	if forwardSpeed > targetSpeed + profile.NearZeroSpeedThreshold then
		return "Coasting"
	elseif math.abs(targetSpeed - forwardSpeed) <= profile.NearZeroSpeedThreshold then
		return "Cruising"
	end

	return "Accelerating"
end

function CartLongitudinalStateMachine.ResolveControlAction(
	approvedState: unknown,
	intent: LongitudinalIntent,
	forwardSpeed: number,
	commandedSpeed: number,
	stopThreshold: number,
	reverseApprovalCurrent: boolean
): LongitudinalControlAction
	if
		not CartLongitudinalStateMachine.IsValidState(approvedState)
		or (intent ~= "None" and intent ~= "Forward" and intent ~= "Reverse")
		or not isFiniteNumber(forwardSpeed)
		or not isFiniteNumber(commandedSpeed)
		or not isFiniteNumber(stopThreshold)
		or stopThreshold < 0
		or type(reverseApprovalCurrent) ~= "boolean"
	then
		return "Coast"
	end

	if intent == "None" then
		return "Coast"
	end

	local movingForward = forwardSpeed > stopThreshold or commandedSpeed > stopThreshold
	local movingBackward = forwardSpeed < -stopThreshold or commandedSpeed < -stopThreshold

	if intent == "Forward" then
		if approvedState == "Reverse" or movingBackward then
			return "Brake"
		end

		return "ForwardPropulsion"
	end

	if approvedState == "Reverse" then
		if movingForward then
			return "Brake"
		end

		return if reverseApprovalCurrent then "ReversePropulsion" else "Coast"
	elseif movingForward or approvedState == "Braking" then
		return "Brake"
	end

	return "Coast"
end

local function getNextState(
	snapshot: LongitudinalSnapshot,
	intent: LongitudinalIntent,
	requestedState: LongitudinalState,
	forwardSpeed: number,
	now: number,
	profile: EffectiveMovementProfile
): LongitudinalState
	local currentState = snapshot.CurrentState
	local stopped = math.abs(forwardSpeed) <= profile.NearZeroSpeedThreshold

	if intent == "None" then
		if not stopped then
			return "Coasting"
		end

		return if currentState == "Idle" or currentState == "Stopped" then "Idle" else "Stopped"
	elseif intent == "Reverse" then
		if currentState == "Reverse" then
			return if forwardSpeed > profile.NearZeroSpeedThreshold then "Braking" else "Reverse"
		end

		if forwardSpeed > profile.NearZeroSpeedThreshold then
			return "Braking"
		elseif forwardSpeed < -profile.NearZeroSpeedThreshold then
			return "Coasting"
		end

		if currentState ~= "Stopped" then
			return "Stopped"
		end

		local transition = snapshot.CurrentTransition

		if
			transition ~= nil
			and transition.TargetState == "Reverse"
			and now - transition.StartedAt + TIME_BOUNDARY_EPSILON >= profile.RecoveryInputDelay
		then
			return "Reverse"
		end

		return "Stopped"
	end

	if forwardSpeed < -profile.NearZeroSpeedThreshold or currentState == "Reverse" then
		return "Braking"
	end

	if currentState == "Braking" then
		return if stopped then "Stopped" else requestedState
	elseif currentState == "Coasting" then
		return if requestedState == "Coasting" then "Coasting" else "Accelerating"
	end

	return requestedState
end

local function buildTransition(
	previousSnapshot: LongitudinalSnapshot,
	nextState: LongitudinalState,
	requestedState: LongitudinalState,
	now: number
): LongitudinalTransition?
	if nextState == requestedState then
		return nil
	end

	local previousTransition = previousSnapshot.CurrentTransition
	local stateChanged = previousSnapshot.CurrentState ~= nextState
	local mustRestartAtStopGate = stateChanged and nextState == "Stopped"
	local startedAt = if not mustRestartAtStopGate
			and previousTransition ~= nil
			and previousTransition.TargetState == requestedState
		then previousTransition.StartedAt
		else now

	return freezeTransition(requestedState, startedAt)
end

function CartLongitudinalStateMachine.Step(
	snapshot: unknown,
	throttle: number,
	forwardSpeed: number,
	now: number,
	profile: EffectiveMovementProfile
): StepResult
	local validInput = isFiniteNumber(throttle)
		and isFiniteNumber(forwardSpeed)
		and isFiniteNumber(now)
	local validSnapshot = snapshotIsValid(snapshot)

	if not validInput or not validSnapshot then
		local recoveredStateChanged = if validSnapshot
			then (snapshot :: LongitudinalSnapshot).CurrentState ~= "Idle"
			else true

		return {
			Snapshot = CartLongitudinalStateMachine.Create(if isFiniteNumber(now) then now else 0),
			Intent = "None",
			RequestedState = "Idle",
			StateChanged = recoveredStateChanged,
			RecoveredFromInvalidState = true,
		}
	end

	local currentSnapshot = snapshot :: LongitudinalSnapshot
	local clampedThrottle = math.clamp(throttle, -1, 1)
	local intent = CartLongitudinalStateMachine.ResolveIntent(
		clampedThrottle,
		profile.LongitudinalInputDeadzone
	)
	local requestedState = getRequestedState(
		currentSnapshot.CurrentState,
		intent,
		forwardSpeed,
		clampedThrottle,
		profile
	)
	local nextState =
		getNextState(currentSnapshot, intent, requestedState, forwardSpeed, now, profile)
	local stateChanged = nextState ~= currentSnapshot.CurrentState
	local transition = buildTransition(currentSnapshot, nextState, requestedState, now)
	local nextSnapshot = freezeSnapshot(
		nextState,
		if stateChanged then currentSnapshot.CurrentState else currentSnapshot.PreviousState,
		transition,
		if stateChanged then now else currentSnapshot.StateEnteredAt
	)

	return {
		Snapshot = nextSnapshot,
		Intent = intent,
		RequestedState = requestedState,
		StateChanged = stateChanged,
		RecoveredFromInvalidState = false,
	}
end

return CartLongitudinalStateMachine
