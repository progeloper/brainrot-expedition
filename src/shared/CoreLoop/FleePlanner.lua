--!strict
-- Part E temperaments: assignment, awareness, flee speeds, bolt plans and the E6 clamps. Pure.
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)

export type Temperament =
	"Docile"
	| "Curious"
	| "Sprinter"
	| "Zigzag"
	| "Camouflage"
	| "DecoySplit"
	| "Showoff"
export type AwarenessContext = {
	hunterCartSpeed: number?, -- studs/s of the nearest hunter's cart (nil = on foot)
	hunterFootSpeed: number?, -- studs/s on foot
	behind: boolean?, -- hunter outside this brainrot's front FrontConeDeg cone
	wary: boolean?, -- within WarySeconds of waking
	star: boolean?,
	mutated: boolean?,
}
export type Bolt = {
	speed: number,
	seconds: number,
	studs: number,
	rest: number,
	burst: number?,
	burstSeconds: number?,
}

local B = CoreLoop.Behaviour

local FleePlanner = {}

local FROM_PROFILE: { [string]: Temperament } = {
	ReactiveRunner = "Curious",
	Sprinter = "Sprinter",
	Zigzag = "Zigzag",
	Camouflage = "Camouflage",
	DecoySplit = "DecoySplit",
	LegendaryPursuit = "Showoff",
	MythicEvent = "Showoff",
}

-- E1: the species' behaviourAssignments decide; unassigned (Wanderer) species use the tier fallback.
function FleePlanner.Temperament(behaviourId: string?, tier: string?): Temperament
	local assigned = if behaviourId then FROM_PROFILE[behaviourId] else nil
	if assigned then
		return assigned
	end
	local fallback = (B.TierFallback :: any)[tier or "Common"] or "Docile"
	return (FROM_PROFILE[fallback] or fallback) :: Temperament
end

local BASE_AWARENESS: { [Temperament]: number } = {
	Docile = 0,
	Curious = 24,
	Sprinter = 30,
	Zigzag = 38,
	Camouflage = 42,
	DecoySplit = 40,
	Showoff = 50,
}

-- E3 awareness radius in studs (0 = never notices: Docile).
function FleePlanner.Awareness(temperament: Temperament, ctx: AwarenessContext): number
	local radius = BASE_AWARENESS[temperament] or 0
	if radius <= 0 then
		return 0
	end
	if ctx.hunterCartSpeed and ctx.hunterCartSpeed > B.CartLoudSpeed then
		radius *= B.CartLoudFactor
	elseif not ctx.hunterCartSpeed and (ctx.hunterFootSpeed or 0) < B.SlowFootSpeed then
		radius *= B.SlowFootFactor
	end
	if ctx.behind then
		radius *= B.BehindFactor
	end
	if ctx.wary then
		radius *= B.WaryFactor
	end
	if ctx.star then
		radius *= B.StarAwarenessFactor
	end
	if ctx.mutated then
		radius *= B.MutatedAwarenessFactor
	end
	return radius
end

-- Notice beat at NoticeFactor x awareness (head turn), skipped from behind.
function FleePlanner.NoticeRadius(awareness: number, behind: boolean): number
	return if behind then 0 else awareness * B.NoticeFactor
end

-- Is the hunter behind? (outside the front cone)
function FleePlanner.IsBehind(facing: Vector3, toHunter: Vector3): boolean
	local f = Vector3.new(facing.X, 0, facing.Z)
	local h = Vector3.new(toHunter.X, 0, toHunter.Z)
	if f.Magnitude < 1e-3 or h.Magnitude < 1e-3 then
		return false
	end
	return f.Unit:Dot(h.Unit) < math.cos(math.rad(B.FrontConeDeg / 2))
end

-- E6: flee speed never exceeds FleeClampOfHunter x the pursuing hunter's current top speed.
function FleePlanner.ClampSpeed(speed: number, hunterTopSpeed: number): number
	return math.min(speed, B.FleeClampOfHunter * hunterTopSpeed)
end

function FleePlanner.MaxBoltStuds(temperament: Temperament): number
	return if temperament == "Showoff" then B.ShowoffBoltStuds else B.MaxBoltStuds
end

function FleePlanner.MaxBolts(temperament: Temperament): number
	if temperament == "Curious" then
		return B.Curious.MaxBolts
	elseif temperament == "Sprinter" then
		return B.Sprinter.MaxBolts
	elseif temperament == "Zigzag" then
		return B.Zigzag.MaxBolts
	elseif temperament == "Showoff" then
		return B.Showoff.MaxBolts
	elseif temperament == "Camouflage" or temperament == "DecoySplit" then
		return B.Camo.MaxBolts
	end
	return 0
end

-- E4 bolt plan for one bolt (bolt index is 1-based). Curious may approach instead (returns nil).
function FleePlanner.Bolt(temperament: Temperament, boltIndex: number, random: Random): Bolt?
	if temperament == "Docile" then
		return {
			speed = B.Herd.DocileScatterSpeed,
			seconds = B.Herd.ScatterSeconds,
			studs = B.Herd.ScatterStuds,
			rest = 0,
		}
	elseif temperament == "Curious" then
		if boltIndex == 1 and random:NextNumber() < B.Curious.ApproachChance then
			return nil -- hop toward the hunter + Signature instead
		end
		return {
			speed = B.Curious.Flee,
			seconds = B.Curious.BoltSeconds,
			studs = B.Curious.BoltStuds,
			rest = random:NextNumber(B.Curious.RestMin, B.Curious.RestMax),
		}
	elseif temperament == "Sprinter" then
		return {
			speed = B.Sprinter.Flee,
			seconds = B.Sprinter.BurstSeconds + B.Sprinter.RecoverySeconds,
			studs = B.MaxBoltStuds,
			rest = B.Sprinter.Cooldown,
			burst = B.Sprinter.Burst,
			burstSeconds = B.Sprinter.BurstSeconds,
		}
	elseif temperament == "Zigzag" then
		return { speed = B.Zigzag.Flee, seconds = 2.8, studs = B.MaxBoltStuds, rest = B.Zigzag.Rest }
	elseif temperament == "Showoff" then
		if boltIndex == 1 then
			return {
				speed = B.Showoff.Opening,
				seconds = B.Showoff.OpeningSeconds,
				studs = B.ShowoffBoltStuds,
				rest = 0,
			}
		end
		return {
			speed = B.Showoff.Opening,
			seconds = 2.8,
			studs = B.ShowoffBoltStuds,
			rest = B.Showoff.Rest,
			burst = B.Showoff.Burst,
			burstSeconds = B.Showoff.BurstSeconds,
		}
	end
	return { speed = B.Camo.Flee, seconds = 2, studs = B.MaxBoltStuds, rest = 1.5 }
end

-- Zigzag heading offset (degrees) at time s into a bolt: sweep +-SweepDeg every SweepSeconds,
-- separated by StraightSeconds straight runs.
function FleePlanner.ZigzagOffset(s: number): number
	local z = B.Zigzag
	local period = z.SweepSeconds + z.StraightSeconds
	local cycle = math.floor(s / period)
	local within = s - cycle * period
	if within > z.SweepSeconds then
		return 0
	end
	return if cycle % 2 == 0 then z.SweepDeg else -z.SweepDeg
end

-- Speed at time s into a bolt (Sprinter / Showoff bursts then recovery).
function FleePlanner.SpeedAt(temperament: Temperament, bolt: Bolt, s: number): number
	if temperament == "Sprinter" then
		if s <= B.Sprinter.BurstSeconds then
			return B.Sprinter.Burst
		end
		return B.Sprinter.Recovery
	end
	if bolt.burst and bolt.burstSeconds and s >= bolt.seconds - bolt.burstSeconds then
		return bolt.burst
	end
	return bolt.speed
end

-- Exhausted after max bolts or MaxFleeSecondsPerEncounter of total fleeing.
function FleePlanner.IsExhausted(
	temperament: Temperament,
	bolts: number,
	fleeSeconds: number
): boolean
	return bolts >= FleePlanner.MaxBolts(temperament) or fleeSeconds >= B.MaxFleeSecondsPerEncounter
end

return table.freeze(FleePlanner)
