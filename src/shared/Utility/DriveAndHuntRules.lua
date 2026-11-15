--!strict
-- Drive-and-Hunt pure rules: no Roblox service calls, so every decision is unit-testable.
-- The server feeds these with authoritative state; the client uses SwitchState for the label only.
local Rules = {}

--------------------------------------------------------------------------------
-- Camp footprint (axis-aligned rectangle taken from RegionFootprints.Camp)
--------------------------------------------------------------------------------

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }

function Rules.BoundsOf(points: { Vector2 }): Bounds
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, point in points do
		minX, maxX = math.min(minX, point.X), math.max(maxX, point.X)
		minZ, maxZ = math.min(minZ, point.Y), math.max(maxZ, point.Y)
	end
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

-- Signed distance to the rectangle edge: negative inside, positive outside.
function Rules.EdgeDistance(bounds: Bounds, x: number, z: number): number
	local dx = math.max(bounds.minX - x, x - bounds.maxX)
	local dz = math.max(bounds.minZ - z, z - bounds.maxZ)
	if dx <= 0 and dz <= 0 then
		return math.max(dx, dz)
	end
	return math.sqrt(math.max(dx, 0) ^ 2 + math.max(dz, 0) ^ 2)
end

--------------------------------------------------------------------------------
-- Gate launch trigger (Part A2)
--------------------------------------------------------------------------------

export type GateState = {
	inside: boolean?, -- nil until the first sample
	seated: boolean,
	lastSeatExitAt: number,
	lastMoveAt: number, -- last launch or call
}

export type GateInput = {
	edgeDistance: number, -- signed, from EdgeDistance
	seated: boolean, -- in any seat
	alive: boolean,
	canAct: boolean, -- not dazed, not saving
	busy: boolean, -- cinematic or dialog
	carrying: boolean,
}

export type GateConfig = {
	MaxCrossingDistance: number,
	SeatExitQuietSeconds: number,
	RepeatQuietSeconds: number,
}

function Rules.NewGateState(): GateState
	return { inside = nil, seated = false, lastSeatExitAt = -math.huge, lastMoveAt = -math.huge }
end

function Rules.NoteMoved(state: GateState, now: number)
	state.lastMoveAt = now
end

-- Advances the state by one sample. Returns true when the player just walked out of camp
-- and should be launched, plus the reason when a crossing was seen but refused.
function Rules.GateStep(
	state: GateState,
	input: GateInput,
	config: GateConfig,
	now: number
): (boolean, string?)
	if state.seated and not input.seated then
		state.lastSeatExitAt = now
	end
	state.seated = input.seated

	local wasInside = state.inside
	local inside = input.edgeDistance <= 0
	state.inside = inside
	if wasInside ~= true or inside then
		return false, nil
	end
	-- The player crossed the camp edge on this sample.
	if input.seated then
		return false, "Seated"
	end
	if not input.alive then
		return false, "Dead"
	end
	if not input.canAct then
		return false, "CannotAct"
	end
	if input.busy then
		-- A menu, dialog or cinematic is open: never move the player now. The crossing is
		-- kept, so the launch fires on the first sample after it closes (if still near).
		state.inside = true
		return false, "Busy"
	end
	if input.carrying then
		return false, "Carrying"
	end
	if input.edgeDistance > config.MaxCrossingDistance then
		return false, "Teleported"
	end
	if now - state.lastSeatExitAt < config.SeatExitQuietSeconds then
		return false, "JustLeftSeat"
	end
	if now - state.lastMoveAt < config.RepeatQuietSeconds then
		return false, "JustMoved"
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Placement candidates (Parts A3 and B4)
--------------------------------------------------------------------------------

export type Candidate = { offset: Vector3, heading: Vector3 }

local function flat(vector: Vector3): Vector3
	local planar = Vector3.new(vector.X, 0, vector.Z)
	return if planar.Magnitude > 1e-4 then planar.Unit else Vector3.new(0, 0, -1)
end

-- Call-cart candidates: `directions` evenly spaced bearings at each distance, the bearing
-- nearest the player's facing first, then alternating outwards; nearer distances first.
-- The cart is parked side-on so it never points at the player.
function Rules.CallCandidates(
	facing: Vector3,
	directions: number,
	distances: { number }
): { Candidate }
	local forward = flat(facing)
	local baseAngle = math.atan2(forward.X, forward.Z)
	local order = { 0 }
	for step = 1, directions // 2 do
		table.insert(order, step)
		if step ~= directions - step then
			table.insert(order, -step)
		end
	end
	local candidates: { Candidate } = {}
	for _, distance in distances do
		for _, step in order do
			local angle = baseAngle + step * (2 * math.pi / directions)
			local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
			table.insert(candidates, { offset = direction * distance, heading = forward })
		end
	end
	return candidates
end

export type Lane = { exit: string, region: string, normal: Vector3, points: { Vector3 } }

-- Lanes ordered by distance from the crossing point to each lane's first point.
function Rules.NearestLanes(lanes: { Lane }, crossing: Vector3, count: number): { Lane }
	local ranked = table.clone(lanes)
	local function distance(lane: Lane): number
		local point = lane.points[1]
		return (point.X - crossing.X) ^ 2 + (point.Z - crossing.Z) ^ 2
	end
	table.sort(ranked, function(a, b)
		local da, db = distance(a), distance(b)
		if da ~= db then
			return da < db
		end
		return a.exit < b.exit
	end)
	local result = {}
	for index = 1, math.min(count, #ranked) do
		result[index] = ranked[index]
	end
	return result
end

-- Lane sample positions along the four camp edges (measured once into Config/CampExits).
function Rules.LaneSeeds(
	bounds: Bounds,
	spacing: number,
	inset: number,
	distances: { number }
): { { exit: string, normal: Vector3, points: { Vector3 } } }
	local seeds = {}
	local sides = {
		{
			name = "North",
			normal = Vector3.new(0, 0, -1),
			fixed = bounds.minZ,
			from = bounds.minX,
			to = bounds.maxX,
			alongX = true,
		},
		{
			name = "South",
			normal = Vector3.new(0, 0, 1),
			fixed = bounds.maxZ,
			from = bounds.minX,
			to = bounds.maxX,
			alongX = true,
		},
		{
			name = "West",
			normal = Vector3.new(-1, 0, 0),
			fixed = bounds.minX,
			from = bounds.minZ,
			to = bounds.maxZ,
			alongX = false,
		},
		{
			name = "East",
			normal = Vector3.new(1, 0, 0),
			fixed = bounds.maxX,
			from = bounds.minZ,
			to = bounds.maxZ,
			alongX = false,
		},
	}
	for _, side in sides do
		local length = side.to - side.from - inset * 2
		local count = math.max(1, math.floor(length / spacing) + 1)
		local step = if count > 1 then length / (count - 1) else 0
		for index = 1, count do
			local along = side.from + inset + step * (index - 1)
			local edge = if side.alongX
				then Vector3.new(along, 0, side.fixed)
				else Vector3.new(side.fixed, 0, along)
			local points = {}
			for _, distance in distances do
				table.insert(points, edge + side.normal * distance)
			end
			table.insert(seeds, {
				exit = string.format("%s_%02d", side.name, index),
				normal = side.normal,
				points = points,
			})
		end
	end
	return seeds
end

-- Hop-out sides in the order they are tried: the preferred side, the other side, then the back.
-- `targetLocal` is the locked target (or nil) in the cart's object space; the driver's side is -X.
function Rules.HopOutSides(targetLocalX: number?): { string }
	local first = if targetLocalX ~= nil and targetLocalX > 0 then "Right" else "Left"
	return { first, if first == "Left" then "Right" else "Left", "Back" }
end

--------------------------------------------------------------------------------
-- Switch button (Part B1)
--------------------------------------------------------------------------------

export type SwitchInput = {
	driving: boolean, -- seated in the driver seat of the player's own cart
	carrying: boolean,
	allowed: boolean, -- not dazed / cinematic / dialog / tag-slowed
	cooldownRemaining: number,
	hasCart: boolean,
}

export type SwitchState = {
	state: "HopOut" | "Cart" | "LoadAndGo" | "Disabled",
	action: "HopOut" | "CallCart" | "LoadAndGo" | nil,
	enabled: boolean,
	pulse: boolean,
	cooldown: number,
}

function Rules.SwitchState(input: SwitchInput): SwitchState
	if input.driving then
		return { state = "HopOut", action = "HopOut", enabled = true, pulse = false, cooldown = 0 }
	end
	local kind: "Cart" | "LoadAndGo" = if input.carrying then "LoadAndGo" else "Cart"
	local action: "CallCart" | "LoadAndGo" = if input.carrying then "LoadAndGo" else "CallCart"
	if not input.hasCart or not input.allowed then
		return { state = kind, action = nil, enabled = false, pulse = false, cooldown = 0 }
	end
	if input.cooldownRemaining > 0 then
		return {
			state = kind,
			action = nil,
			enabled = false,
			pulse = false,
			cooldown = input.cooldownRemaining,
		}
	end
	return { state = kind, action = action, enabled = true, pulse = input.carrying, cooldown = 0 }
end

--------------------------------------------------------------------------------
-- Scoop reach (Part D1): measured from the cart's edge, not its pivot
--------------------------------------------------------------------------------

export type ScoopShape = { HalfWidth: number, HalfLength: number, Reach: number, Lateral: number }

-- `bodySize` is the cart profile's BodySize (X = width, Z = length).
function Rules.ScoopShape(bodySize: Vector3, reach: number): ScoopShape
	local halfWidth, halfLength = bodySize.X * 0.5, bodySize.Z * 0.5
	return {
		HalfWidth = halfWidth,
		HalfLength = math.max(halfLength, halfWidth),
		Reach = reach,
		Lateral = halfWidth + reach, -- the effective reach beside the cart
	}
end

-- A capsule round the cart's centre line: `Lateral` to either side, and the same `Reach`
-- beyond the front and back edges. `localX` / `localZ` are in the cart's own frame.
function Rules.InScoopReach(shape: ScoopShape, localX: number, localZ: number): boolean
	local spine = shape.HalfLength - shape.HalfWidth
	local along = math.max(math.abs(localZ) - spine, 0)
	return localX * localX + along * along <= shape.Lateral * shape.Lateral
end

-- Playtest Fixes 2 Part B: may a Jump at `now` send HOP OUT? Ignored for `grace` seconds after
-- sitting down, and at most one request per `minInterval`.
function Rules.JumpHopAllowed(
	now: number,
	seatedSince: number,
	lastSent: number,
	grace: number,
	minInterval: number
): boolean
	return now - seatedSince >= grace and now - lastSent >= minInterval
end

return table.freeze(Rules)
