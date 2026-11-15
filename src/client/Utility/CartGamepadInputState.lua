--!strict

export type ActivationContext = {
	ControllerStarted: boolean,
	PlayerActive: boolean,
	CharacterValid: boolean,
	CartAvailable: boolean,
	CartReady: boolean,
	AuthorizedDriver: boolean,
	ResetSuspended: boolean,
	GamepadConnected: boolean,
	GamepadDeviceActive: boolean,
	InputSuppressed: boolean,
}

export type Snapshot = {
	Active: boolean,
	ContextRevision: number,
	Revision: number,
	LongitudinalIntent: number,
	SteeringIntent: number,
	CameraIntent: Vector2,
	ResetHeld: boolean,
}

local CartGamepadInputState = {}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isFiniteVector2(value: Vector2): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y)
end

local function freezeSnapshot(
	active: boolean,
	contextRevision: number,
	revision: number,
	longitudinalIntent: number,
	steeringIntent: number,
	cameraIntent: Vector2,
	resetHeld: boolean
): Snapshot
	return table.freeze({
		Active = active,
		ContextRevision = contextRevision,
		Revision = revision,
		LongitudinalIntent = longitudinalIntent,
		SteeringIntent = steeringIntent,
		CameraIntent = cameraIntent,
		ResetHeld = resetHeld,
	})
end

local function isNeutral(snapshot: Snapshot): boolean
	return snapshot.LongitudinalIntent == 0
		and snapshot.SteeringIntent == 0
		and snapshot.CameraIntent == Vector2.zero
		and not snapshot.ResetHeld
end

local function isCurrent(snapshot: Snapshot, expectedContextRevision: number): boolean
	return snapshot.Active and snapshot.ContextRevision == expectedContextRevision
end

function CartGamepadInputState.Create(): Snapshot
	return freezeSnapshot(false, 0, 0, 0, 0, Vector2.zero, false)
end

function CartGamepadInputState.CanActivate(context: ActivationContext): boolean
	return context.ControllerStarted == true
		and context.PlayerActive == true
		and context.CharacterValid == true
		and context.CartAvailable == true
		and context.CartReady == true
		and context.AuthorizedDriver == true
		and context.ResetSuspended == false
		and context.GamepadConnected == true
		and context.GamepadDeviceActive == true
		and context.InputSuppressed == false
end

function CartGamepadInputState.CanProcessInput(
	snapshot: Snapshot,
	gameProcessedEvent: boolean,
	inputSuppressed: boolean
): boolean
	return snapshot.Active and not gameProcessedEvent and not inputSuppressed
end

function CartGamepadInputState.Activate(snapshot: Snapshot): Snapshot
	return freezeSnapshot(
		true,
		snapshot.ContextRevision + 1,
		snapshot.Revision + 1,
		0,
		0,
		Vector2.zero,
		false
	)
end

function CartGamepadInputState.Deactivate(snapshot: Snapshot): Snapshot
	return freezeSnapshot(
		false,
		snapshot.ContextRevision + 1,
		snapshot.Revision + 1,
		0,
		0,
		Vector2.zero,
		false
	)
end

function CartGamepadInputState.Clear(snapshot: Snapshot): (Snapshot, boolean)
	if isNeutral(snapshot) then
		return snapshot, false
	end

	return freezeSnapshot(
		snapshot.Active,
		snapshot.ContextRevision,
		snapshot.Revision + 1,
		0,
		0,
		Vector2.zero,
		false
	),
		true
end

function CartGamepadInputState.SetMovementIntent(
	snapshot: Snapshot,
	longitudinalIntent: number,
	steeringIntent: number,
	expectedContextRevision: number
): (Snapshot, boolean, string?)
	if not isCurrent(snapshot, expectedContextRevision) then
		return snapshot, false, nil
	end

	if
		not isFiniteNumber(longitudinalIntent)
		or not isFiniteNumber(steeringIntent)
		or math.abs(longitudinalIntent) > 1
		or math.abs(steeringIntent) > 1
	then
		return snapshot, false, "movement intent must be finite and within -1 to 1"
	end

	if
		snapshot.LongitudinalIntent == longitudinalIntent
		and snapshot.SteeringIntent == steeringIntent
	then
		return snapshot, false, nil
	end

	return freezeSnapshot(
		true,
		snapshot.ContextRevision,
		snapshot.Revision + 1,
		longitudinalIntent,
		steeringIntent,
		snapshot.CameraIntent,
		snapshot.ResetHeld
	),
		true,
		nil
end

function CartGamepadInputState.SetCameraIntent(
	snapshot: Snapshot,
	cameraIntent: Vector2,
	expectedContextRevision: number
): (Snapshot, boolean, string?)
	if not isCurrent(snapshot, expectedContextRevision) then
		return snapshot, false, nil
	end

	if
		not isFiniteVector2(cameraIntent)
		or math.abs(cameraIntent.X) > 1
		or math.abs(cameraIntent.Y) > 1
	then
		return snapshot, false, "camera intent must be finite and within -1 to 1"
	end

	if snapshot.CameraIntent == cameraIntent then
		return snapshot, false, nil
	end

	return freezeSnapshot(
		true,
		snapshot.ContextRevision,
		snapshot.Revision + 1,
		snapshot.LongitudinalIntent,
		snapshot.SteeringIntent,
		cameraIntent,
		snapshot.ResetHeld
	),
		true,
		nil
end

function CartGamepadInputState.SetResetHeld(
	snapshot: Snapshot,
	resetHeld: boolean,
	expectedContextRevision: number
): (Snapshot, boolean)
	if not isCurrent(snapshot, expectedContextRevision) or snapshot.ResetHeld == resetHeld then
		return snapshot, false
	end

	return freezeSnapshot(
		true,
		snapshot.ContextRevision,
		snapshot.Revision + 1,
		snapshot.LongitudinalIntent,
		snapshot.SteeringIntent,
		snapshot.CameraIntent,
		resetHeld
	),
		true
end

return table.freeze(CartGamepadInputState)
