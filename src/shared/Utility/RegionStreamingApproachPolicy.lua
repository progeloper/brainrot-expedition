--!strict
-- A near-use hint does not grant access, reveal detail or certify loaded collision.
local Policy = {}
Policy.ApproachRadius = 64
Policy.DestinationOffset = 24
Policy.RequestTimeout = 5
Policy.RetrySeconds = 2
Policy.MaximumAttempts = 2

-- One request plus one error-conditioned retry for an actual approach episode.
-- Keep pending across an episode/character change: an older engine request
-- still counts toward the one-outstanding-per-player limit until it returns.
function Policy.TryRequest(state: any, key: string?, now: number): (boolean, number?)
	if state.key ~= key then
		state.key = key
		state.generation = (state.generation or 0) + 1
		state.attempts = 0
		state.result = nil
	end
	if not key or state.pending or state.result == "Returned" or (state.attempts or 0) >= Policy.MaximumAttempts then
		return false, nil
	end
	if now - (state.lastRequestAt or -math.huge) < Policy.RetrySeconds then
		return false, nil
	end
	state.pending = true
	state.attempts = (state.attempts or 0) + 1
	state.lastRequestAt = now
	return true, state.generation
end

function Policy.CompleteRequest(state: any, generation: number, ok: boolean): boolean
	state.pending = false
	if generation ~= state.generation then
		return false
	end
	state.result = if ok then "Returned" else "Failed"
	return true
end

local function finiteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

function Policy.Select(position: Vector3, current: string?, unlocked: { [string]: boolean }, gates: { any }): any?
	if not finiteVector(position) or not current or unlocked[current] ~= true then
		return nil
	end
	local nearest, nearestDistance = nil, math.huge
	for _, gate in gates do
		if
			not finiteVector(gate.position)
			or not finiteVector(gate.normal)
			or math.abs(gate.normal.Magnitude - 1) > 0.0001
			or math.abs(gate.normal.Y) > 0.0001
		then
			continue
		end
		local destination, direction
		if current == gate.exteriorRegion then
			destination, direction = gate.regionId, 1
		elseif current == gate.regionId then
			destination, direction = gate.exteriorRegion, -1
		else
			continue
		end
		if unlocked[destination] ~= true then
			continue
		end
		local delta = position - gate.position
		local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
		-- The opening is24studs wide. A12stud shoulder admits ordinary cart
		-- approaches without requesting a gate approached through a nearby wall.
		local lateral = math.abs(delta:Dot(Vector3.new(-gate.normal.Z, 0, gate.normal.X)))
		if
			distance <= Policy.ApproachRadius
			and lateral <= 24
			and math.abs(delta.Y) <= 24
			and distance < nearestDistance
		then
			nearestDistance = distance
			nearest = {
				key = gate.key .. ":" .. destination,
				gateKey = gate.key,
				destinationRegion = destination,
				position = gate.position + gate.normal * direction * Policy.DestinationOffset,
				approachDistance = distance,
			}
		end
	end
	return nearest
end

return table.freeze(Policy)
