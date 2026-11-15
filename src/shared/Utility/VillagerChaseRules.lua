--!strict
-- Pure rules for villager guards. No instances, no clocks: everything is passed in.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.VillagerGuards)

local Rules = {}

export type ChaseResult = "Escaped" | "Timeout" | "ReachedSafeZone"

-- Villager chase speed in studs/s for a type, elapsed chase time and the chased cart's top speed.
function Rules.ChaseSpeed(
	villagerType: string,
	elapsed: number,
	cartTopSpeed: number,
	assisted: boolean
): number
	local tuning = Config.Types[villagerType]
	if not tuning or not tuning.chases then
		return 0
	end
	local factor = if elapsed < tuning.burstSeconds then tuning.burstFactor else tuning.tiredFactor
	local assist = if assisted then Config.Assist.SpeedMultiplier else 1
	return math.max(cartTopSpeed, 1) * factor * assist
end

-- Time-based give-up (ring-edge give-up is spatial and handled by the caller).
function Rules.GivesUpByTime(villagerType: string, elapsed: number): boolean
	local tuning = Config.Types[villagerType]
	return tuning ~= nil and tuning.chases and elapsed >= tuning.giveUpSeconds
end

function Rules.RingRadius(rarity: string?, assisted: boolean): number
	local radius = Config.radiusForRarity(rarity)
	return if assisted then radius * Config.Assist.RingRadiusMultiplier else radius
end

function Rules.IsAssisted(taggedStreak: number): boolean
	return taggedStreak >= Config.Assist.TaggedChasesInRow
end

-- Tagged chases in a row. A clean escape resets; a tagged chase increments;
-- a chase that was neither (e.g. cancelled) leaves it unchanged.
function Rules.NextTaggedStreak(streak: number, tagged: boolean, clean: boolean): number
	if tagged then
		return streak + 1
	elseif clean then
		return 0
	end
	return streak
end

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end
Rules.FlatDistance = flat

function Rules.OutsideRing(position: Vector3, center: Vector3, radius: number): boolean
	return flat(position, center) >= radius
end

-- Decide how a live chase ends this tick, or nil to continue.
function Rules.ChaseOutcome(
	cartPosition: Vector3,
	center: Vector3,
	radius: number,
	elapsed: number,
	inSafeZone: boolean
): ChaseResult?
	if inSafeZone then
		return "ReachedSafeZone"
	elseif Rules.OutsideRing(cartPosition, center, radius) then
		return "Escaped"
	elseif elapsed >= Config.MaxChaseSeconds then
		return "Timeout"
	end
	return nil
end

function Rules.OnCooldown(cooldownUntil: number?, now: number): boolean
	return cooldownUntil ~= nil and now < cooldownUntil
end

-- A tag lands when the villager's flat gap to the cart root is inside reach.
function Rules.CanTag(gap: number, alreadyTagged: boolean): boolean
	return not alreadyTagged and gap <= Config.Tag.Reach
end

-- "Close call": got within CloseCallDistance of tag reach without tagging.
function Rules.IsCloseCall(minimumGap: number, tags: number): boolean
	return tags == 0 and minimumGap <= Config.Tag.Reach + Config.CloseCallDistance
end

-- Step a flat position toward a target by at most speed*dt, stopping short by `standoff`.
function Rules.StepToward(
	position: Vector3,
	target: Vector3,
	speed: number,
	dt: number,
	standoff: number
): Vector3
	local delta = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
	local distance = delta.Magnitude
	local travel = math.min(speed * dt, math.max(distance - standoff, 0))
	if travel <= 1e-4 or distance <= 1e-4 then
		return position
	end
	return position + delta.Unit * travel
end

-- Crossing time of a straight run from rest (used by checks and the report).
function Rules.CrossingSeconds(radius: number, topSpeed: number, acceleration: number): number
	local rampTime = topSpeed / acceleration
	local rampDistance = 0.5 * acceleration * rampTime * rampTime
	if radius <= rampDistance then
		return math.sqrt(2 * radius / acceleration)
	end
	return rampTime + (radius - rampDistance) / topSpeed
end

return table.freeze(Rules)
