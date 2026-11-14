--!strict
-- Tralalero Tralala (BRT_027): authored animation set. Archetype: Three-legged walker.
-- Bones: RigTorso (the shark's body, with the dorsal fin and back stripes), RigHead (the head
-- and snout, with the face and grin), RigTail (the upper tail lobe), two fin-legs at the front
-- (RigRightLeg, RigLeftLeg) and the tail leg (RigCentreLeg), each with a knee
-- (Rig...LowerLeg) that carries its sneaker.
-- The meme: a grinning blue shark on three legs in blue sneakers. He walks like a person and
-- grooves like one too: the sneakers do all the work while the body sways like it is still
-- swimming. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only. The torso pivots far
-- forward, so a nose-up tilt pushes the tail leg into the ground; the floor clamp lifts him.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head up at the front and
-- swings a leg forward; a knee bends with -rx on the lower leg; +ry turns left; +rz rolls the
-- body to his left; Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

type Leg = { number } -- { swing, lift, knee, splay }

type Options = {
	pitch: number?,
	roll: number?,
	yaw: number?,
	lift: number?,
	forward: number?,
	right: Leg?,
	left: Leg?,
	centre: Leg?,
	head: CFrame?,
	tail: CFrame?,
}

local STILL: Leg = { 0, 0, 0, 0 }

-- One whole-body pose. Each leg turns against the body's pitch and roll so it stays upright;
-- a leg's knee keeps its sneaker level unless a knee bend is given.
local function pose(o: Options): Poses
	local pitch, roll = o.pitch or 0, o.roll or 0
	local function leg(l: Leg, side: number): (CFrame, CFrame)
		local swing, lift, knee, splay = l[1], l[2], l[3], l[4] or 0
		return T(0, lift, 0, swing - pitch, 0, side * splay - roll), R(-swing - knee)
	end
	local rh, rk = leg(o.right or STILL, 1)
	local lh, lk = leg(o.left or STILL, -1)
	local ch, ck = leg(o.centre or STILL, 0)
	return {
		RigTorso = T(0, o.lift or 0, -(o.forward or 0), pitch, o.yaw or 0, roll),
		RigHead = o.head or R(),
		RigTail = o.tail or R(),
		RigRightLeg = rh,
		RigRightLowerLeg = rk,
		RigLeftLeg = lh,
		RigLeftLowerLeg = lk,
		RigCentreLeg = ch,
		RigCentreLowerLeg = ck,
	}
end

local set: { [string]: any } = {}

-- Banked: the sneaker groove. He bounces on the beat, stepping from one front sneaker to the
-- other with a heel tap, the body swaying and the grin bopping, the tail keeping time.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local beat = math.abs(wave(t, 1.0))
		local side = wave(t, 1.5)
		local r, l = math.max(0, side), math.max(0, -side)
		return pose({
			lift = 0.08 * beat,
			roll = 3 * side,
			yaw = 6 * side,
			right = { 14 * r, 0.18 * r, 0, 0 },
			left = { 14 * l, 0.18 * l, 0, 0 },
			centre = { 0, 0, 10 * beat, 0 },
			head = R(4 * beat, 8 * side, -4 * side),
			tail = Q.Tail(8 + 10 * beat, 30 * wave(t, 0.5)),
		})
	end,
}
set.IdleWild = {
	name = "IdleWild",
	length = 3.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.8)
		return pose({
			lift = 0.03 * breathe,
			yaw = 3 * wave(t, 3.6),
			head = R(2 * breathe, 7 * wave(t, 3.6, 0.05), 2 * wave(t, 1.8, 0.2)),
			tail = Q.Tail(2 * breathe, 18 * wave(t, 3.6, 0.3)),
		})
	end,
}
-- Rare variant: admiring his sneakers. He lifts his right front foot, turns his head down to
-- look at it, wiggles it left and right to show it off, and puts it back down.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local up = seg(t, 0.1, 0.4) * (1 - seg(t, 1.5, 1.85))
		local wiggle = up * wave(t - 0.4, 0.35)
		return pose({
			roll = -3 * up,
			right = { 18 * up, 0.12 * up, 50 * up, 6 * up + 8 * wiggle },
			head = R(-4 * up, -6 * up, 2 * up),
			tail = Q.Tail(6 * up, 20 * up * wave(t, 0.5)),
		})
	end,
}
-- The walk: a swaggering three-legged stroll. The front sneakers step in turn, the tail leg
-- takes a short step after each, and the body swings from side to side as if still swimming.
set.Walk = {
	name = "Walk",
	length = 0.8,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.8)
		local c = wave(t, 0.8, 0.25) -- positive while the right foot comes forward
		local r, l = math.max(0, c), math.max(0, -c)
		local cs = wave(t, 0.4, 0.5)
		return pose({
			lift = 0.04 * math.abs(c),
			roll = 3 * c,
			yaw = 7 * s,
			right = { 22 * s, 0.25 * r, 30 * r, 0 },
			left = { -22 * s, 0.25 * l, 30 * l, 0 },
			centre = {
				14 * cs,
				0.15 * math.max(0, wave(t, 0.4, 0.75)),
				20 * math.max(0, wave(t, 0.4, 0.75)),
				0,
			},
			head = R(2 * wave(t, 0.4), -5 * s, 0),
			tail = Q.Tail(4, -30 * s),
		})
	end,
}
-- The sprint: leaning in, sneakers pounding, the tail thrashing like a shark in a hurry.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		local c = wave(t, 0.4, 0.25)
		local r, l = math.max(0, c), math.max(0, -c)
		local cs = wave(t, 0.2, 0.5)
		return pose({
			pitch = -4,
			lift = 0.1 * math.abs(c) - 0.1,
			roll = 3 * c,
			yaw = 6 * s,
			right = { 30 * s, 0.2 * r, 60 * r, 0 },
			left = { -30 * s, 0.2 * l, 60 * l, 0 },
			centre = {
				20 * cs,
				0.2 * math.max(0, wave(t, 0.2, 0.75)),
				40 * math.max(0, wave(t, 0.2, 0.75)),
				0,
			},
			head = R(4, -4 * s, 0),
			tail = Q.Tail(14, -40 * s),
		})
	end,
}
set.Alert = {
	name = "Alert",
	length = 0.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local up = snap(t, 0.06, 0.24)
		local air = bump(t, 0.06, 0.36)
		return pose({
			lift = 0.35 * air,
			right = { 0, 0, 20 * air, 8 * air },
			left = { 0, 0, 20 * air, 8 * air },
			centre = { 0, 0, 20 * air, 0 },
			head = R(6 * up, 0, 0),
			tail = Q.Tail(30 * up, 0),
		})
	end,
}
set.Hit = {
	name = "Hit",
	length = 0.25,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
		return pose({
			roll = 6 * hit,
			yaw = -6 * hit,
			forward = -0.15 * hit,
			right = { 0, 0, 14 * hit, 0 },
			head = R(4 * hit, 6 * hit, 4 * hit),
			tail = Q.Tail(14 * hit, 36 * hit),
		})
	end,
}
-- Carried: all three sneakers pedalling, the tail thrashing, the head swinging.
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local k = wave(t, 0.25)
		local flap = wave(t, 0.5)
		return pose({
			roll = 4 * wave(t, 1.0, 0.25),
			yaw = 5 * wave(t, 1.0),
			right = { 30 * k, 0, 30 + 20 * k, 8 },
			left = { -30 * k, 0, 30 - 20 * k, 8 },
			centre = { 24 * wave(t, 0.25, 0.5), 0, 30, 0 },
			head = R(4 * flap, 7 * wave(t, 1.0, 0.1), 3 * wave(t, 0.5, 0.25)),
			tail = Q.Tail(10, 50 * flap),
		})
	end,
}
-- Asleep belly-down on the sand: the two fin-legs spread out to the sides like fins again
-- (raised at the hip so the sneakers lie flat), the tail leg stretched out behind with its
-- sneaker sole-up, the chin down and the tail drooping to one side, breathing slowly through
-- the head and tail.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		-- over-lowered on purpose: the floor clamp raises him until he rests
		local out = pose({
			lift = -3.0,
			right = { 0, 0.8, 0, 85 },
			left = { 0, 0.8, 0, 85 },
			centre = { -80, 0, 170, 0 },
			head = R(-2 + 0.6 * breathe, 0, 3),
			tail = Q.Tail(-14, 24),
		})
		return out
	end,
}
-- A hop and a full spin with all three sneakers kicked out and the tail flung up.
set.Celebrate = {
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local crouch = seg(t, 0, 0.14) * (1 - seg(t, 0.14, 0.24))
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.22, 0.88)
		local land = bump(t, 0.9, 1.2)
		local bend = 30 * crouch + 30 * air + 20 * land
		return pose({
			lift = 1.1 * air - 0.1 * crouch,
			yaw = 360 * spin,
			right = { 10 * air, 0, bend, 18 * air },
			left = { 10 * air, 0, bend, 18 * air },
			centre = { -10 * air, 0, bend, 0 },
			head = R(10 * air - 4 * land, 0, 0),
			tail = Q.Tail(40 * air, 30 * wave(t, 0.2) * air),
		})
	end,
}
-- Signature: the Tralala. Three bouncing hop-steps on the beat, kicking a front sneaker out on
-- each one, then a full spin, finishing with a flick of the head and a grin.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local hops = seg(t, 0.0, 0.08) * (1 - seg(t, 0.84, 0.92))
		local beat = t % 0.28
		local n = math.floor(t / 0.28)
		local hop = hops * bump(beat, 0.0, 0.28)
		local kickR = if n % 2 == 0 then hop else 0
		local kickL = if n % 2 == 1 then hop else 0
		local turn = seg(t, 0.88, 1.3)
		local flick = bump(t, 1.28, 1.6)
		return pose({
			lift = 0.3 * hop + 0.12 * bump(t, 0.88, 1.3),
			roll = 4 * (kickL - kickR),
			yaw = 360 * turn,
			right = { 30 * kickR, 0.3 * kickR, 10 * kickR + 14 * turn * (1 - turn), 8 * kickR },
			left = { 30 * kickL, 0.3 * kickL, 10 * kickL + 14 * turn * (1 - turn), 8 * kickL },
			centre = { 0, 0, 20 * hop, 0 },
			head = R(4 * hop + 8 * flick, 5 * (kickR - kickL), -6 * flick),
			tail = Q.Tail(10 * hops + 30 * flick, 34 * wave(t, 0.28) * hops),
		})
	end,
}

return Q.Finish(set)
