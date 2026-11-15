--!strict

-- Cosmetic free-aim prediction only. These are the current sleep server's
-- range-sphere, forward-plane and obstruction rules; this grants no hit/target
-- authority and never supplies a client muzzle or endpoint to SleepRequest.
local SURFACE_TOLERANCE = 0.01
local MIN_FORWARD_AIM_DOT = 0.5
local Preview = {}

local function finiteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X and math.abs(value.X) < math.huge
		and value.Y == value.Y and math.abs(value.Y) < math.huge
		and value.Z == value.Z and math.abs(value.Z) < math.huge
end

function Preview.Resolve(muzzle: Vector3, cameraRay: Ray, range: number, raycast: (Vector3, Vector3) -> any): (any?, string?)
	if not finiteVector(muzzle) or typeof(cameraRay) ~= "Ray"
		or not finiteVector(cameraRay.Origin) or not finiteVector(cameraRay.Direction)
		or type(range) ~= "number" or range ~= range or range <= 0 or range >= math.huge
	then
		return nil, "invalid aim"
	end
	local magnitude = cameraRay.Direction.Magnitude
	if math.abs(magnitude - 1) > 0.01 then
		return nil, "invalid camera direction"
	end
	local origin, direction = cameraRay.Origin, cameraRay.Direction / magnitude
	local cameraFromMuzzle = origin - muzzle
	local projection = cameraFromMuzzle:Dot(direction)
	local discriminant = projection * projection - (cameraFromMuzzle:Dot(cameraFromMuzzle) - range * range)
	if discriminant < 0 then
		return nil, "camera ray misses weapon range"
	end
	local depth = -projection + math.sqrt(discriminant)
	if depth <= SURFACE_TOLERANCE then
		return nil, "no forward aim in weapon range"
	end
	local cameraHit = raycast(origin, direction * depth)
	local point = if cameraHit then cameraHit.Position else origin + direction * depth
	local offset = point - muzzle
	local distance = offset.Magnitude
	local reason = if offset:Dot(direction) <= SURFACE_TOLERANCE then "camera obstruction behind muzzle"
		elseif distance > range + SURFACE_TOLERANCE then "camera obstruction outside weapon range"
		elseif offset.Unit:Dot(direction) < MIN_FORWARD_AIM_DOT then "aim point too close to muzzle plane"
		else nil
	if reason then
		return { Valid = false, Blocked = true, Reason = reason, AimPoint = point, Endpoint = point }, reason
	end
	local shotDirection = offset / distance
	local hit = raycast(muzzle, shotDirection * math.min(distance + SURFACE_TOLERANCE, range))
	local endpoint = if hit then hit.Position else point
	return {
		Valid = true,
		Blocked = hit ~= nil and (endpoint - point).Magnitude > SURFACE_TOLERANCE * 2,
		AimPoint = point,
		Endpoint = endpoint,
		Direction = shotDirection,
	}, nil
end

return table.freeze(Preview)
