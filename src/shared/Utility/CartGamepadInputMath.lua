--!strict

export type MovementIntent = {
	LongitudinalIntent: number,
	SteeringIntent: number,
}

local CartGamepadInputMath = {}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isFiniteVector2(value: Vector2): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y)
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function validateDeadzone(deadzone: number): string?
	if not isFiniteNumber(deadzone) or deadzone < 0 or deadzone >= 1 then
		return "deadzone must be finite, at least 0, and less than 1"
	end

	return nil
end

function CartGamepadInputMath.ApplyRadialDeadzone(
	value: Vector2,
	deadzone: number
): (Vector2?, string?)
	if not isFiniteVector2(value) then
		return nil, "stick input must be finite"
	end

	local deadzoneError = validateDeadzone(deadzone)

	if deadzoneError ~= nil then
		return nil, deadzoneError
	end

	local magnitude = value.Magnitude

	if not isFiniteNumber(magnitude) then
		return nil, "stick magnitude must be finite"
	end

	if magnitude <= deadzone or magnitude == 0 then
		return Vector2.zero, nil
	end

	local clampedMagnitude = math.min(magnitude, 1)
	local remappedMagnitude = (clampedMagnitude - deadzone) / (1 - deadzone)

	return value / magnitude * remappedMagnitude, nil
end

function CartGamepadInputMath.ReadMovementStick(position: Vector3): (Vector2?, string?)
	if not isFiniteVector3(position) then
		return nil, "movement-stick position must be finite"
	end

	return Vector2.new(position.X, position.Y), nil
end

function CartGamepadInputMath.ReadCameraStick(position: Vector3): (Vector2?, string?)
	if not isFiniteVector3(position) then
		return nil, "camera-stick position must be finite"
	end

	-- Roblox thumbstick Y is positive upward; Phase 1M consumes mouse-style pitch delta.
	return Vector2.new(position.X, -position.Y), nil
end

function CartGamepadInputMath.ReadLeftTrigger(position: Vector3): (number?, string?)
	if not isFiniteVector3(position) then
		return nil, "left-trigger position must be finite"
	end

	return position.Z, nil
end

function CartGamepadInputMath.ApplyTriggerDeadzone(
	value: number,
	deadzone: number
): (number?, string?)
	if not isFiniteNumber(value) then
		return nil, "trigger input must be finite"
	end

	local deadzoneError = validateDeadzone(deadzone)

	if deadzoneError ~= nil then
		return nil, deadzoneError
	end

	local clampedValue = math.clamp(value, 0, 1)

	if clampedValue <= deadzone then
		return 0, nil
	end

	return (clampedValue - deadzone) / (1 - deadzone), nil
end

function CartGamepadInputMath.ResolveMovement(
	leftStick: Vector2,
	leftTrigger: number,
	movementDeadzone: number,
	triggerDeadzone: number
): (MovementIntent?, string?)
	local stick, stickError = CartGamepadInputMath.ApplyRadialDeadzone(leftStick, movementDeadzone)

	if stick == nil then
		return nil, stickError
	end

	local trigger, triggerError =
		CartGamepadInputMath.ApplyTriggerDeadzone(leftTrigger, triggerDeadzone)

	if trigger == nil then
		return nil, triggerError
	end

	local longitudinalIntent = if trigger > 0 then -trigger else stick.Y

	return table.freeze({
		LongitudinalIntent = math.clamp(longitudinalIntent, -1, 1),
		SteeringIntent = math.clamp(stick.X, -1, 1),
	}),
		nil
end

function CartGamepadInputMath.ResolveCamera(
	rightStick: Vector2,
	cameraDeadzone: number
): (Vector2?, string?)
	return CartGamepadInputMath.ApplyRadialDeadzone(rightStick, cameraDeadzone)
end

return table.freeze(CartGamepadInputMath)
