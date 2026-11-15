--!strict

export type ResetState =
	"Idle"
	| "HoldStarted"
	| "HoldComplete"
	| "Validation"
	| "Suspension"
	| "Reposition"
	| "Recovery"
	| "Resume"
	| "Cancelled"
	| "Failed"

export type Snapshot = {
	CurrentState: ResetState,
	PreviousState: ResetState,
	StateEnteredAt: number,
	Revision: number,
}

local CartResetLifecycle = {}

CartResetLifecycle.Attributes = table.freeze({
	Active = "ResetActive",
	StartedAt = "ResetStartedAt",
	CompletedAt = "ResetCompletedAt",
})

local VALID_STATES: { [ResetState]: boolean } = {
	Idle = true,
	HoldStarted = true,
	HoldComplete = true,
	Validation = true,
	Suspension = true,
	Reposition = true,
	Recovery = true,
	Resume = true,
	Cancelled = true,
	Failed = true,
}

local ALLOWED_TRANSITIONS: { [ResetState]: { [ResetState]: boolean } } = {
	Idle = { HoldStarted = true },
	HoldStarted = { HoldComplete = true, Cancelled = true, Failed = true },
	HoldComplete = { Validation = true, Cancelled = true, Failed = true },
	Validation = { Suspension = true, Failed = true },
	Suspension = { Reposition = true, Failed = true },
	Reposition = { Recovery = true, Failed = true },
	Recovery = { Resume = true, Failed = true },
	Resume = { Idle = true, Failed = true },
	Cancelled = { Idle = true },
	Failed = { Idle = true },
}

local EXECUTION_STATES: { [ResetState]: boolean } = {
	Validation = true,
	Suspension = true,
	Reposition = true,
	Recovery = true,
	Resume = true,
}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function freezeSnapshot(
	currentState: ResetState,
	previousState: ResetState,
	stateEnteredAt: number,
	revision: number
): Snapshot
	return table.freeze({
		CurrentState = currentState,
		PreviousState = previousState,
		StateEnteredAt = stateEnteredAt,
		Revision = revision,
	})
end

function CartResetLifecycle.IsValidState(value: unknown): boolean
	return type(value) == "string" and VALID_STATES[value :: ResetState] == true
end

function CartResetLifecycle.IsExecutionActive(value: unknown): boolean
	return CartResetLifecycle.IsValidState(value) and EXECUTION_STATES[value :: ResetState] == true
end

function CartResetLifecycle.Create(now: number): Snapshot
	assert(isFiniteNumber(now), "reset lifecycle start time must be finite")

	return freezeSnapshot("Idle", "Idle", now, 0)
end

function CartResetLifecycle.CanTransition(fromState: unknown, toState: unknown): boolean
	if
		not CartResetLifecycle.IsValidState(fromState)
		or not CartResetLifecycle.IsValidState(toState)
	then
		return false
	end

	return ALLOWED_TRANSITIONS[fromState :: ResetState][toState :: ResetState] == true
end

function CartResetLifecycle.Transition(
	snapshot: Snapshot,
	targetState: ResetState,
	now: number
): (Snapshot?, string?)
	if not CartResetLifecycle.IsValidState(snapshot.CurrentState) then
		return nil, "current reset state is invalid"
	end

	if not CartResetLifecycle.IsValidState(snapshot.PreviousState) then
		return nil, "previous reset state is invalid"
	end

	if
		not isFiniteNumber(snapshot.Revision)
		or snapshot.Revision < 0
		or snapshot.Revision % 1 ~= 0
	then
		return nil, "reset revision must be a non-negative integer"
	end

	if not CartResetLifecycle.IsValidState(targetState) then
		return nil, string.format("unknown reset state %s", tostring(targetState))
	end

	if not isFiniteNumber(snapshot.StateEnteredAt) or not isFiniteNumber(now) then
		return nil, "reset transition time must be finite"
	end

	if now < snapshot.StateEnteredAt then
		return nil, "reset transition time cannot move backwards"
	end

	if not CartResetLifecycle.CanTransition(snapshot.CurrentState, targetState) then
		return nil,
			string.format("illegal reset transition %s -> %s", snapshot.CurrentState, targetState)
	end

	return freezeSnapshot(targetState, snapshot.CurrentState, now, snapshot.Revision + 1), nil
end

return table.freeze(CartResetLifecycle)
