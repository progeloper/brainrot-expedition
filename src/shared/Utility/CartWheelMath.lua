--!strict
-- Cosmetic rolling only. No movement force, wheel size or gameplay state is an input/output.
local WheelMath = {}
local TAU = math.pi * 2

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function finiteFrame(frame: CFrame): boolean
	for _, value in { frame:GetComponents() } do
		if not finite(value) then
			return false
		end
	end
	return true
end

function WheelMath.Wrap(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

-- The root frame is sampled before spinning the decorative joint. A turn gives
-- each hub its own path; the two wheels do not borrow a shared center speed.
-- SpinAxis is authored in hub-local coordinates. Its cross with up supplies
-- the corresponding signed rolling direction, including mirrored hub axes.
function WheelMath.Delta(
	previous: CFrame?,
	current: CFrame,
	hub: CFrame,
	spinAxis: Vector3,
	radius: number,
	deltaTime: number
): (number, boolean)
	if
		not previous
		or not finiteFrame(previous)
		or not finiteFrame(current)
		or not finiteFrame(hub)
		or not finite(radius)
		or radius <= 0
		or not finite(deltaTime)
		or deltaTime <= 0
		or deltaTime > 0.25
		or not finite(spinAxis.Magnitude)
		or spinAxis.Magnitude < 0.001
	then
		return 0, true
	end
	local rootTravel = (current.Position - previous.Position).Magnitude
	local relative = previous:ToObjectSpace(current)
	local _, turn = relative:ToAxisAngle()
	if rootTravel > math.max(3, 180 * deltaTime) or math.abs(turn) > math.rad(50) then
		return 0, true -- Teleport, reset, stream jump or a long sampling discontinuity.
	end
	local previousHub = previous * hub
	local currentHub = current * hub
	local axis = spinAxis.Unit
	local oldRolling = previousHub:VectorToWorldSpace(axis):Cross(previous.UpVector)
	local newRolling = currentHub:VectorToWorldSpace(axis):Cross(current.UpVector)
	local rolling = oldRolling + newRolling
	if rolling.Magnitude < 0.001 then
		return 0, true
	end
	-- The contact point is below this individual hub, rather than at the root.
	local oldContact = previousHub.Position - previous.UpVector * radius
	local newContact = currentHub.Position - current.UpVector * radius
	local travel = newContact - oldContact
	if travel.Magnitude > math.max(4, 140 * deltaTime) then
		return 0, true
	end
	local signed = travel:Dot(rolling.Unit)
	if math.abs(signed) < 0.0001 then
		return 0, false
	end
	return signed / radius, false
end

return table.freeze(WheelMath)
