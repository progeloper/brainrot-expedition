--!strict

export type Key = "W" | "A" | "S" | "D" | "R"

export type ActivationContext = {
	ControllerStarted: boolean,
	PlayerActive: boolean,
	CharacterValid: boolean,
	CartAvailable: boolean,
	CartReady: boolean,
	AuthorizedDriver: boolean,
	ResetSuspended: boolean,
	KeyboardEnabled: boolean,
	InputSuppressed: boolean,
}

export type Snapshot = {
	Active: boolean,
	ContextRevision: number,
	Revision: number,
	ForwardHeld: boolean,
	BackwardHeld: boolean,
	LeftHeld: boolean,
	RightHeld: boolean,
	ResetHeld: boolean,
	LongitudinalIntent: number,
	SteeringIntent: number,
}

local CartPCInputState = {}

local function freezeSnapshot(
	active: boolean,
	contextRevision: number,
	revision: number,
	forwardHeld: boolean,
	backwardHeld: boolean,
	leftHeld: boolean,
	rightHeld: boolean,
	resetHeld: boolean
): Snapshot
	return table.freeze({
		Active = active,
		ContextRevision = contextRevision,
		Revision = revision,
		ForwardHeld = forwardHeld,
		BackwardHeld = backwardHeld,
		LeftHeld = leftHeld,
		RightHeld = rightHeld,
		ResetHeld = resetHeld,
		LongitudinalIntent = (if forwardHeld then 1 else 0) - (if backwardHeld then 1 else 0),
		SteeringIntent = (if rightHeld then 1 else 0) - (if leftHeld then 1 else 0),
	})
end

local function isClear(snapshot: Snapshot): boolean
	return not snapshot.ForwardHeld
		and not snapshot.BackwardHeld
		and not snapshot.LeftHeld
		and not snapshot.RightHeld
		and not snapshot.ResetHeld
end

function CartPCInputState.Create(): Snapshot
	return freezeSnapshot(false, 0, 0, false, false, false, false, false)
end

function CartPCInputState.CanActivate(context: ActivationContext): boolean
	return context.ControllerStarted == true
		and context.PlayerActive == true
		and context.CharacterValid == true
		and context.CartAvailable == true
		and context.CartReady == true
		and context.AuthorizedDriver == true
		and context.ResetSuspended == false
		and context.KeyboardEnabled == true
		and context.InputSuppressed == false
end

function CartPCInputState.CanProcessInput(
	snapshot: Snapshot,
	gameProcessedEvent: boolean,
	inputSuppressed: boolean
): boolean
	return snapshot.Active and not gameProcessedEvent and not inputSuppressed
end

function CartPCInputState.Activate(snapshot: Snapshot): Snapshot
	return freezeSnapshot(
		true,
		snapshot.ContextRevision + 1,
		snapshot.Revision + 1,
		false,
		false,
		false,
		false,
		false
	)
end

function CartPCInputState.Deactivate(snapshot: Snapshot): Snapshot
	return freezeSnapshot(
		false,
		snapshot.ContextRevision + 1,
		snapshot.Revision + 1,
		false,
		false,
		false,
		false,
		false
	)
end

function CartPCInputState.Clear(snapshot: Snapshot): (Snapshot, boolean)
	if isClear(snapshot) then
		return snapshot, false
	end

	return freezeSnapshot(
		snapshot.Active,
		snapshot.ContextRevision,
		snapshot.Revision + 1,
		false,
		false,
		false,
		false,
		false
	),
		true
end

function CartPCInputState.SetKey(
	snapshot: Snapshot,
	key: Key,
	held: boolean,
	expectedContextRevision: number
): (Snapshot, boolean)
	if not snapshot.Active or snapshot.ContextRevision ~= expectedContextRevision then
		return snapshot, false
	end

	local forwardHeld = snapshot.ForwardHeld
	local backwardHeld = snapshot.BackwardHeld
	local leftHeld = snapshot.LeftHeld
	local rightHeld = snapshot.RightHeld
	local resetHeld = snapshot.ResetHeld

	if key == "W" then
		if forwardHeld == held then
			return snapshot, false
		end

		forwardHeld = held
	elseif key == "S" then
		if backwardHeld == held then
			return snapshot, false
		end

		backwardHeld = held
	elseif key == "A" then
		if leftHeld == held then
			return snapshot, false
		end

		leftHeld = held
	elseif key == "D" then
		if rightHeld == held then
			return snapshot, false
		end

		rightHeld = held
	elseif key == "R" then
		if resetHeld == held then
			return snapshot, false
		end

		resetHeld = held
	else
		return snapshot, false
	end

	return freezeSnapshot(
		true,
		snapshot.ContextRevision,
		snapshot.Revision + 1,
		forwardHeld,
		backwardHeld,
		leftHeld,
		rightHeld,
		resetHeld
	),
		true
end

return table.freeze(CartPCInputState)
