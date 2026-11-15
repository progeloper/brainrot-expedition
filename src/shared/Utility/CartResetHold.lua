--!strict

export type HoldState = "Idle" | "Holding" | "Complete"

export type Snapshot = {
	State: HoldState,
	Elapsed: number,
	Revision: number,
}

local CartResetHold = {}

local VALID_STATES: { [HoldState]: boolean } = {
	Idle = true,
	Holding = true,
	Complete = true,
}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function freezeSnapshot(state: HoldState, elapsed: number, revision: number): Snapshot
	return table.freeze({
		State = state,
		Elapsed = elapsed,
		Revision = revision,
	})
end

local function validateSnapshot(snapshot: Snapshot): string?
	if not VALID_STATES[snapshot.State] then
		return "reset hold state is invalid"
	end

	if not isFiniteNumber(snapshot.Elapsed) or snapshot.Elapsed < 0 then
		return "reset hold elapsed time must be finite and non-negative"
	end

	if
		not isFiniteNumber(snapshot.Revision)
		or snapshot.Revision < 0
		or snapshot.Revision % 1 ~= 0
	then
		return "reset hold revision must be a non-negative integer"
	end

	return nil
end

function CartResetHold.Create(): Snapshot
	return freezeSnapshot("Idle", 0, 0)
end

function CartResetHold.Begin(snapshot: Snapshot): (Snapshot?, string?)
	local validationError = validateSnapshot(snapshot)

	if validationError ~= nil then
		return nil, validationError
	end

	if snapshot.State ~= "Idle" then
		return nil, "reset hold can begin only from Idle"
	end

	return freezeSnapshot("Holding", 0, snapshot.Revision + 1), nil
end

function CartResetHold.Advance(
	snapshot: Snapshot,
	deltaTime: number,
	holdDuration: number
): (Snapshot?, boolean, string?)
	local validationError = validateSnapshot(snapshot)

	if validationError ~= nil then
		return nil, false, validationError
	end

	if
		not isFiniteNumber(deltaTime)
		or deltaTime < 0
		or not isFiniteNumber(holdDuration)
		or holdDuration <= 0
	then
		return nil, false, "reset hold timing values are invalid"
	end

	if snapshot.State ~= "Holding" then
		return snapshot, false, nil
	end

	local elapsed = math.min(snapshot.Elapsed + deltaTime, holdDuration)
	local completed = elapsed >= holdDuration

	return freezeSnapshot(
		if completed then "Complete" else "Holding",
		elapsed,
		snapshot.Revision + 1
	),
		completed,
		nil
end

function CartResetHold.Release(snapshot: Snapshot): (Snapshot?, boolean, string?)
	local validationError = validateSnapshot(snapshot)

	if validationError ~= nil then
		return nil, false, validationError
	end

	local cancelled = snapshot.State == "Holding"

	return freezeSnapshot("Idle", 0, snapshot.Revision + 1), cancelled, nil
end

return table.freeze(CartResetHold)
