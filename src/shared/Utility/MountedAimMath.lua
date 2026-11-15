--!strict

local MountedAimMath = {}
local TAU = math.pi * 2

local function wrap(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

-- Positive pitch looks up. No cart heading, velocity or recenter timer is an
-- input: a held view remains fixed in world direction while the cart turns.
function MountedAimMath.FromLookVector(look: Vector3, minimumPitch: number, maximumPitch: number): (number, number)
	local direction = if look.Magnitude > 1e-6 then look.Unit else -Vector3.zAxis
	return math.atan2(-direction.X, -direction.Z),
		math.clamp(math.asin(math.clamp(direction.Y, -1, 1)), minimumPitch, maximumPitch)
end

function MountedAimMath.ApplyLook(
	yaw: number,
	pitch: number,
	pointerDelta: Vector2,
	stick: Vector2,
	deltaTime: number,
	pointerScale: number,
	stickRate: number,
	minimumPitch: number,
	maximumPitch: number
): (number, number)
	local scale = stickRate * math.max(deltaTime, 0)
	return wrap(yaw - pointerDelta.X * pointerScale - stick.X * scale),
		math.clamp(pitch - pointerDelta.Y * pointerScale + stick.Y * scale, minimumPitch, maximumPitch)
end

function MountedAimMath.GetDesiredCFrame(
	cartFocus: Vector3,
	yaw: number,
	pitch: number,
	distance: number,
	shoulderOffset: number,
	heightOffset: number
): (CFrame, Vector3)
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local anchor = cartFocus + Vector3.yAxis * heightOffset
	local position = anchor + rotation:VectorToWorldSpace(Vector3.new(shoulderOffset, 0, distance))
	-- Facing outward rather than looking back at the cart keeps the cart below
	-- the central intent ray. World up supplies a stable horizon on slopes.
	return CFrame.new(position) * rotation, anchor
end

return table.freeze(MountedAimMath)
