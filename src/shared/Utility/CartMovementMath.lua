--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartMovementTypes = require(ReplicatedStorage.Shared.Types.CartMovementTypes)

local CartMovementMath = {}

export type LocalVelocity = CartMovementTypes.LocalVelocity

function CartMovementMath.ApplyDeadzone(value: number, deadzone: number): number
	local magnitude = math.abs(value)

	if magnitude <= deadzone then
		return 0
	end

	return math.sign(value) * math.clamp((magnitude - deadzone) / (1 - deadzone), 0, 1)
end

function CartMovementMath.DecomposeVelocity(
	velocity: Vector3,
	forward: Vector3,
	right: Vector3,
	maximumSpeed: number
): LocalVelocity
	local forwardSpeed = velocity:Dot(forward)

	return {
		ForwardSpeed = forwardSpeed,
		LateralSpeed = velocity:Dot(right),
		AbsoluteSpeed = velocity.Magnitude,
		NormalizedForwardSpeed = if maximumSpeed > 0
			then math.clamp(math.abs(forwardSpeed) / maximumSpeed, 0, 1)
			else 0,
	}
end

function CartMovementMath.GetSpeedInterpolation(
	currentSpeed: number,
	huntingSpeed: number,
	maximumTravelSpeed: number,
	exponent: number
): number
	local travelRange = maximumTravelSpeed - huntingSpeed

	if travelRange <= 0 then
		return if math.abs(currentSpeed) >= maximumTravelSpeed then 1 else 0
	end

	local travelProgress = math.clamp((math.abs(currentSpeed) - huntingSpeed) / travelRange, 0, 1)

	return travelProgress ^ exponent
end

function CartMovementMath.InterpolateBySpeed(
	currentSpeed: number,
	huntingSpeed: number,
	maximumTravelSpeed: number,
	lowSpeedValue: number,
	highSpeedValue: number,
	exponent: number
): number
	local alpha = CartMovementMath.GetSpeedInterpolation(
		currentSpeed,
		huntingSpeed,
		maximumTravelSpeed,
		exponent
	)

	return lowSpeedValue + (highSpeedValue - lowSpeedValue) * alpha
end

function CartMovementMath.GetSteeringMultiplier(
	currentSpeed: number,
	huntingSpeed: number,
	maximumTravelSpeed: number,
	lowSpeedMultiplier: number,
	highSpeedMultiplier: number,
	interpolationExponent: number
): number
	return CartMovementMath.InterpolateBySpeed(
		currentSpeed,
		huntingSpeed,
		maximumTravelSpeed,
		lowSpeedMultiplier,
		highSpeedMultiplier,
		interpolationExponent
	)
end

function CartMovementMath.GetTravelDirection(
	forwardSpeed: number,
	stationarySteeringThreshold: number
): number
	return if forwardSpeed <= -stationarySteeringThreshold then -1 else 1
end

function CartMovementMath.ApproachSpeed(
	currentSpeed: number,
	targetSpeed: number,
	response: number,
	deltaTime: number
): number
	local maximumDelta = response * math.max(deltaTime, 0)
	local speedError = targetSpeed - currentSpeed

	if math.abs(speedError) <= maximumDelta then
		return targetSpeed
	end

	return currentSpeed + math.sign(speedError) * maximumDelta
end

function CartMovementMath.GetPlausibleTravelDistance(
	maximumSpeed: number,
	deltaTime: number,
	multiplier: number,
	additive: number
): number
	return maximumSpeed * math.max(deltaTime, 0) * multiplier + additive
end

function CartMovementMath.GetExponentialAlpha(responsiveness: number, deltaTime: number): number
	return 1 - math.exp(-responsiveness * math.max(deltaTime, 0))
end

return CartMovementMath
