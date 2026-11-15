--!strict

local CartCameraMath = {}

local TAU = math.pi * 2
local DIRECTION_EPSILON = 1e-6

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

function CartCameraMath.IsFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

function CartCameraMath.IsFiniteCFrame(value: CFrame): boolean
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	return isFiniteNumber(x)
		and isFiniteNumber(y)
		and isFiniteNumber(z)
		and isFiniteNumber(r00)
		and isFiniteNumber(r01)
		and isFiniteNumber(r02)
		and isFiniteNumber(r10)
		and isFiniteNumber(r11)
		and isFiniteNumber(r12)
		and isFiniteNumber(r20)
		and isFiniteNumber(r21)
		and isFiniteNumber(r22)
end

function CartCameraMath.WrapAngle(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

function CartCameraMath.GetExponentialAlpha(responsiveness: number, deltaTime: number): number
	return 1 - math.exp(-responsiveness * math.max(deltaTime, 0))
end

function CartCameraMath.ApplyManualOrbit(
	yawOffset: number,
	pitch: number,
	mouseDelta: Vector2,
	sensitivity: number,
	radiansPerPixel: number,
	minimumPitch: number,
	maximumPitch: number
): (number, number)
	local scale = sensitivity * radiansPerPixel
	local nextYaw = CartCameraMath.WrapAngle(yawOffset - mouseDelta.X * scale)
	local nextPitch = math.clamp(pitch - mouseDelta.Y * scale, minimumPitch, maximumPitch)

	return nextYaw, nextPitch
end

function CartCameraMath.ApplyGamepadOrbit(
	yawOffset: number,
	pitch: number,
	stickIntent: Vector2,
	sensitivity: number,
	radiansPerSecond: number,
	deltaTime: number,
	minimumPitch: number,
	maximumPitch: number
): (number, number)
	local scale = sensitivity * radiansPerSecond * math.max(deltaTime, 0)
	local nextYaw = CartCameraMath.WrapAngle(yawOffset - stickIntent.X * scale)
	local nextPitch = math.clamp(pitch - stickIntent.Y * scale, minimumPitch, maximumPitch)

	return nextYaw, nextPitch
end

function CartCameraMath.RecenterYaw(yawOffset: number, speed: number, deltaTime: number): number
	local current = CartCameraMath.WrapAngle(yawOffset)
	local difference = CartCameraMath.WrapAngle(-current)
	local alpha = CartCameraMath.GetExponentialAlpha(speed, deltaTime)

	return CartCameraMath.WrapAngle(current + difference * alpha)
end

function CartCameraMath.ShouldRecenter(
	now: number,
	lastManualInputAt: number,
	delay: number,
	manualInputActive: boolean,
	resetSuspended: boolean
): boolean
	return not manualInputActive and not resetSuspended and now - lastManualInputAt >= delay
end

function CartCameraMath.GetStructuralYaw(rootCFrame: CFrame, fallbackYaw: number?): number
	local lookVector = rootCFrame.LookVector
	local flatForward = Vector3.new(lookVector.X, 0, lookVector.Z)

	if flatForward.Magnitude <= DIRECTION_EPSILON then
		return CartCameraMath.WrapAngle(fallbackYaw or 0)
	end

	flatForward = flatForward.Unit

	return math.atan2(-flatForward.X, -flatForward.Z)
end

function CartCameraMath.GetDesiredCFrame(
	targetCFrame: CFrame,
	rootCFrame: CFrame,
	yawOffset: number,
	pitch: number,
	distance: number,
	heightOffset: number,
	fallbackStructuralYaw: number?
): (CFrame, Vector3, number)
	local structuralYaw = CartCameraMath.GetStructuralYaw(rootCFrame, fallbackStructuralYaw)
	local orbitYaw = CartCameraMath.WrapAngle(structuralYaw + yawOffset)
	local orbitRotation = CFrame.Angles(0, orbitYaw, 0) * CFrame.Angles(-pitch, 0, 0)
	local focus = targetCFrame.Position
	local desiredPosition = focus
		+ orbitRotation:VectorToWorldSpace(Vector3.new(0, 0, distance))
		+ Vector3.yAxis * heightOffset
	local desiredCFrame = CFrame.lookAt(desiredPosition, focus, Vector3.yAxis)

	return desiredCFrame, focus, structuralYaw
end

function CartCameraMath.SmoothCFrame(
	current: CFrame,
	target: CFrame,
	positionResponsiveness: number,
	rotationResponsiveness: number,
	deltaTime: number
): CFrame
	local positionAlpha = CartCameraMath.GetExponentialAlpha(positionResponsiveness, deltaTime)
	local rotationAlpha = CartCameraMath.GetExponentialAlpha(rotationResponsiveness, deltaTime)
	local position = current.Position:Lerp(target.Position, positionAlpha)
	local rotation = current.Rotation:Lerp(target.Rotation, rotationAlpha)

	return CFrame.new(position) * rotation
end

return table.freeze(CartCameraMath)
