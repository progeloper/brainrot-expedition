--!strict
-- Pure route arithmetic/state. No services, clock reads, Instances or random side effects.
local Rules = {}
local ranks = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Celestial = 7,
	Astral = 7,
	Secret = 8,
}
function Rules.Speed(rarity: string): number
	assert(ranks[rarity], "Unknown route rarity")
	return 6 * 1.1 ^ (ranks[rarity] - 1)
end
function Rules.Length(points: { Vector3 }): number
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
	end
	return length
end
function Rules.Sample(points: { Vector3 }, progress: number): (Vector3, Vector3, number)
	assert(#points >= 2, "Route needs two points")
	local remaining = math.max(0, progress)
	for i = 2, #points do
		local delta = points[i] - points[i - 1]
		local length = delta.Magnitude
		if length > 1e-6 then
			if remaining <= length or i == #points then
				return points[i - 1] + delta * math.clamp(remaining / length, 0, 1), delta.Unit, i
			end
			remaining -= length
		end
	end
	return points[#points], Vector3.zAxis, #points
end
function Rules.Project(points: { Vector3 }, position: Vector3, minimumProgress: number?): any
	local minimum = math.max(0, minimumProgress or 0)
	local traversed = 0
	local selected = nil
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local delta = b - a
		local length = delta.Magnitude
		if length > 1e-6 and traversed + length >= minimum then
			local low = math.clamp((minimum - traversed) / length, 0, 1)
			local t = math.clamp((position - a):Dot(delta) / (length * length), low, 1)
			local point = a + delta * t
			local distance = (position - point).Magnitude
			local progress = traversed + t * length
			if
				not selected
				or distance < selected.Distance - 1e-6
				or (math.abs(distance - selected.Distance) < 1e-6 and progress < selected.Progress)
			then
				selected = { Point = point, Distance = distance, Progress = progress, Segment = i }
			end
		end
		traversed += length
	end
	return selected
end
function Rules.NewJourney(route: any): any
	return {
		EntranceBurrowId = route.EntranceId,
		DestinationBurrowId = route.DestinationId,
		RouteId = route.Id,
		RouteVersion = route.Version,
		RegionId = route.RegionId,
		Progress = 0,
		Generation = 1,
		ArrivalChecked = false,
		GraceUsed = false,
		GraceUntil = nil,
		EntryStartedAt = nil,
	}
end
function Rules.Arrival(previous: any, at: number, lastAcceptedDamageTime: number?): any
	local nextState = table.clone(previous)
	if not nextState.ArrivalChecked then
		nextState.ArrivalChecked = true
		local engaged = type(lastAcceptedDamageTime) == "number"
			and lastAcceptedDamageTime <= at
			and at - lastAcceptedDamageTime <= 3
		if engaged and not nextState.GraceUsed then
			nextState.GraceUsed = true
			nextState.GraceUntil = at + 6
		end
	end
	if nextState.GraceUntil and at < nextState.GraceUntil then
		return nextState, "Grace"
	end
	if not nextState.EntryStartedAt then
		nextState.EntryStartedAt = at
	end
	return nextState, if at >= nextState.EntryStartedAt + 0.6 then "Depart" else "Entering"
end
function Rules.PauseForSleep(previous: any): any
	local nextState = table.clone(previous)
	nextState.EntryStartedAt = nil -- Wake starts a normal entry, never grants fresh grace.
	return nextState
end
function Rules.PickJourney(
	mouthIds: { string },
	routes: { [string]: any },
	draw: (number, number) -> number
): (any?, string?)
	if #mouthIds == 0 then
		return nil, "REGION_HAS_NO_VALIDATED_MOUTHS"
	end
	local entrance = mouthIds[draw(1, #mouthIds)]
	local alternatives = {}
	for _, id in mouthIds do
		if id ~= entrance and routes[entrance .. ">" .. id] then
			table.insert(alternatives, id)
		end
	end
	if #alternatives == 0 then
		local selfRoute = routes[entrance .. ">" .. entrance]
		return selfRoute, if selfRoute then nil else "NO_CONNECTED_BURROW_ROUTE"
	end
	return routes[entrance .. ">" .. alternatives[draw(1, #alternatives)]], nil
end
return table.freeze(Rules)
