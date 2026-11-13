--!strict
-- Rhino Toasterino (BRT_026): authored animation set. Archetype: Upright biped with elbows,
-- knees and working parts.
-- Bones: RigTorso (the toaster), RigHead (the rhino head on its front), two upper arms and
-- two forearms, two thighs and two lower legs (each lower leg is a sneaker), RigLeftToast
-- (the slice in the slot, with its butter and steam), RigRightToast (the slice that has
-- popped out and hangs in the air), RigLeverKnob (the red knob on his right side) and
-- RigTail (the power cord and plug).
-- The meme: a cheerful rhino who is also a toaster. He is always making toast: one slice
-- hovers and turns above him, the other jumps in its slot, and when he gets excited he
-- lowers his horn and charges. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head up and back and swings
-- a hanging limb forward; +ry turns left; an arm lifts out sideways with a positive `out`;
-- Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local HIP = 1.52 -- torso pivot down to the hips
local THIGH = 0.395 -- hip to knee
local HALF = 0.46 -- centre line out to each hip

type Options = {
	pitch: number?, -- body tips back (+) or forward (-)
	roll: number?, -- right side up (+)
	yaw: number?,
	lift: number?, -- extra height
	forward: number?, -- the whole body slides forward
	swingR: number?, -- thigh angles; the sneaker stays flat unless `dangle` is set
	swingL: number?,
	liftR: number?, -- a foot picked straight up
	liftL: number?,
	toeR: number?, -- toe-up pitch of a sneaker
	toeL: number?,
	dangle: number?, -- knees simply bent by this much (carried)
	head: CFrame?,
	armR: { number }?, -- { swing, out, elbow }
	armL: { number }?,
	toastL: CFrame?,
	toastR: CFrame?,
	knob: number?, -- how far the lever knob is pressed down
	tail: CFrame?,
}

-- One whole-body pose. The legs counter the body's pitch and roll so they stay upright, each
-- sneaker stays flat on the ground, and the body is lowered or raised by what that takes.
local function pose(o: Options): Poses
	local pitch, roll = o.pitch or 0, o.roll or 0
	local swingR, swingL = o.swingR or 0, o.swingL or 0
	local shorter = THIGH * (1 - math.cos(math.rad(math.min(math.abs(swingR), math.abs(swingL)))))
	local y = (o.lift or 0)
		+ HALF * math.sin(math.rad(math.abs(roll)))
		- HIP * (1 - math.cos(math.rad(pitch)))
		- shorter
	local armR, armL = o.armR or { 0, 0, 0 }, o.armL or { 0, 0, 0 }
	local kneeR = if o.dangle then -o.dangle else -swingR + (o.toeR or 0)
	local kneeL = if o.dangle then -o.dangle else -swingL + (o.toeL or 0)
	return {
		RigTorso = T(0, y, -(o.forward or 0), pitch, o.yaw or 0, roll),
		RigHead = o.head or R(),
		RigRightLeg = T(0, o.liftR or 0, 0, swingR - pitch, 0, -roll),
		RigLeftLeg = T(0, o.liftL or 0, 0, swingL - pitch, 0, -roll),
		RigRightLowerLeg = R(kneeR),
		RigLeftLowerLeg = R(kneeL),
		RigRightArm = R(armR[1], 0, armR[2]),
		RigLeftArm = R(armL[1], 0, -armL[2]),
		RigRightForearm = R(armR[3]),
		RigLeftForearm = R(armL[3]),
		RigLeftToast = o.toastL or R(),
		RigRightToast = o.toastR or R(),
		RigLeverKnob = T(0, -(o.knob or 0), 0),
		RigTail = o.tail or R(),
	}
end

local set: { [string]: any } = {}

-- Banked: the showroom toaster. The lever dips and the slice in the slot pops, twice a
-- loop, while the hovering slice turns a slow full circle and he holds his arms out.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local bounce = math.abs(wave(t, 1.5))
		local beat = t % 1.5
		local press = bump(beat, 0, 0.3)
		local pop = bump(beat, 0.22, 0.95)
		local arms = 22 + 8 * wave(t, 1.5)
		return pose({
			pitch = 2 * bounce,
			roll = 2 * wave(t, 3.0),
			lift = 0.03 * bounce,
			head = R(3 + 3 * bounce, 10 * wave(t, 3.0), 5 * wave(t, 1.5)),
			armR = { 6, arms, 18 },
			armL = { 6, arms, 18 },
			toastL = T(0, 0.42 * pop - 0.12 * press, 0),
			toastR = T(0, 0.08 * wave(t, 1.5), 0, 0, 360 * t / 3.0, 0),
			knob = 0.3 * press,
			tail = Q.Tail(6, 28 * wave(t, 0.75)),
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
			pitch = 0.5 * breathe,
			roll = 1.2 * wave(t, 3.6),
			lift = 0.02 + 0.02 * breathe,
			head = R(2 * breathe, 14 * wave(t, 3.6, 0.05), 3 * wave(t, 1.8, 0.2)),
			armR = { 3 * breathe, 4, 6 },
			armL = { -3 * breathe, 4, 6 },
			toastL = T(0, 0.03 + 0.03 * breathe, 0),
			toastR = T(0, 0.06 * wave(t, 1.8, 0.3), 0, 0, 18 * wave(t, 3.6), 0),
			tail = Q.Tail(2 * breathe, 16 * wave(t, 3.6, 0.3)),
		})
	end,
}
-- Rare variant: he makes toast. The lever goes down and the slice sinks into the slot; he
-- waits, head tilted and cord twitching; then the lever springs back, the slice shoots up
-- and he hops and looks up at it.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local press = seg(t, 0.12, 0.38) * (1 - snap(t, 1.16, 1.24))
		local pop = bump(t, 1.18, 1.8)
		local hop = bump(t, 1.18, 1.46)
		return pose({
			roll = 2 * press,
			lift = 0.1 * hop,
			head = R(11 * bump(t, 1.14, 1.9), 0, 7 * press),
			armR = { 44 * press, 20 * press + 24 * pop, 10 },
			armL = { 0, 24 * pop, 10 },
			toastL = T(0, -0.5 * press + 0.75 * pop, 0),
			toastR = T(0, 0.05 * wave(t, 1.0) + 0.12 * hop, 0),
			knob = 0.6 * press,
			tail = Q.Tail(5 + 20 * pop, 24 * wave(t, 0.3) * press),
		})
	end,
}
-- The walk: a stomping waddle. He rocks from sneaker to sneaker with his arms pumping, the
-- slotted slice jumping at every step and the cord wagging behind.
set.Walk = {
	name = "Walk",
	length = 0.8,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.8)
		local c = wave(t, 0.8, 0.25) -- positive while the right foot comes forward
		local right, left = math.max(0, c), math.max(0, -c)
		return pose({
			pitch = -2,
			roll = 4 * c,
			yaw = 4 * s,
			lift = 0.02,
			swingR = 22 * s,
			swingL = -22 * s,
			liftR = 0.13 * right,
			liftL = 0.13 * left,
			toeR = 10 * right,
			toeL = 10 * left,
			head = R(2 * wave(t, 0.4), -3 * s, 0),
			armR = { -28 * s, 5, 24 },
			armL = { 28 * s, 5, 24 },
			toastL = T(0, 0.08 * math.abs(wave(t, 0.8, 0.1)), 0),
			toastR = T(0, 0.08 * wave(t, 0.4, 0.3), 0, 0, 12 * s, 0),
			tail = Q.Tail(4, 22 * s),
		})
	end,
}
-- The charge: body pitched forward, horn levelled, arms tucked back, sneakers hammering,
-- the toast rattling and the cord streaming out behind.
set.Run = {
	name = "Run",
	length = 0.36,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.36)
		local c = wave(t, 0.36, 0.25)
		local right, left = math.max(0, c), math.max(0, -c)
		return pose({
			pitch = -12,
			roll = 3 * c,
			yaw = 3 * s,
			lift = 0.04 + 0.05 * math.abs(s),
			swingR = 34 * s,
			swingL = -34 * s,
			liftR = 0.2 * right,
			liftL = 0.2 * left,
			toeR = 14 * right,
			toeL = 14 * left,
			head = R(-5 + 2 * wave(t, 0.18), 0, 0),
			armR = { -34 - 10 * s, 6, 58 },
			armL = { -34 + 10 * s, 6, 58 },
			toastL = T(0, 0.12 * math.abs(wave(t, 0.36, 0.1)), 0),
			toastR = T(0, 0.1 * wave(t, 0.18, 0.3), 0.12),
			tail = Q.Tail(36, 22 * s),
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
			pitch = 3 * up,
			lift = 0.2 * air,
			toeR = 10 * air,
			toeL = 10 * air,
			head = R(8 * up, 0, 0),
			armR = { 0, 36 * air, 20 * air },
			armL = { 0, 36 * air, 20 * air },
			toastL = T(0, 0.36 * air, 0),
			toastR = T(0, 0.2 * air, 0),
			tail = Q.Tail(40 * up, 0),
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
			pitch = 8 * hit,
			roll = 5 * hit,
			head = R(-8 * hit, 8 * hit, 6 * hit),
			armR = { 20 * hit, 30 * hit, 10 },
			armL = { 20 * hit, 18 * hit, 10 },
			toastL = T(0, 0.26 * hit, 0),
			toastR = T(0, 0.15 * hit, 0, 0, 30 * hit, 0),
			tail = Q.Tail(10 * hit, -30 * hit),
		})
	end,
}
-- Carried: sneakers pedalling, arms flailing, the toast rattling in its slot and the cord
-- whipping about.
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local k = wave(t, 0.25)
		local flap = wave(t, 0.5)
		return pose({
			pitch = 3 * flap,
			roll = 4 * wave(t, 1.0, 0.25),
			yaw = 5 * wave(t, 1.0),
			swingR = 30 * k,
			swingL = -30 * k,
			dangle = 22,
			head = R(4 * flap, 10 * wave(t, 1.0, 0.1), 0),
			armR = { 40 * k, 32 + 14 * flap, 30 },
			armL = { -40 * k, 32 - 14 * flap, 30 },
			toastL = T(0, 0.14 * math.abs(k), 0),
			toastR = T(0, 0.08 * flap, 0, 0, 25 * flap, 0),
			tail = Q.Tail(10, 40 * flap),
		})
	end,
}
-- Asleep on standby: knees bent, body slumped forward, head hanging, arms loose. The slotted
-- slice has sunk half into the toaster and the other hovers low, barely moving.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		return pose({
			pitch = -6 + 0.8 * breathe,
			lift = 0.01 * breathe,
			swingR = 50,
			swingL = 50,
			head = R(-8 + breathe, 0, 6),
			armR = { 8, 2, 4 },
			armL = { 8, 2, 4 },
			toastL = T(0, -0.5 + 0.02 * breathe, 0),
			toastR = T(0, -0.25 + 0.04 * breathe, 0),
			tail = Q.Tail(0, 10),
		})
	end,
}
-- A jump and a full spin with both arms thrown up; the slotted slice flies out of its slot
-- and drops back in as he lands.
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
		local bend = 34 * crouch + 26 * air + 18 * land
		return pose({
			pitch = 4 * air,
			yaw = 360 * spin,
			lift = 1.0 * air,
			swingR = bend,
			swingL = bend,
			head = R(8 * air - 4 * land, 0, 0),
			armR = { 0, 112 * air + 16 * land, 14 },
			armL = { 0, 112 * air + 16 * land, 14 },
			toastL = T(0, 1.0 * air, 0),
			toastR = T(0, 0.5 * air, 0, 0, 180 * spin, 0),
			tail = Q.Tail(40 * air, 30 * wave(t, 0.2) * air),
		})
	end,
}
-- Signature: the charge. He drops his horn and paws the ground twice with his right
-- sneaker, lunges forward horn first, and the jolt launches both slices of toast.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local low = seg(t, 0.04, 0.26) * (1 - seg(t, 1.2, 1.46))
		local paw = bump(t, 0.12, 0.38) + bump(t, 0.42, 0.68)
		local lunge = bump(t, 0.78, 1.16)
		local fly = bump(t, 0.96, 1.52)
		local turn = seg(t, 0.96, 1.52)
		return pose({
			pitch = -10 * low,
			lift = 0.1 * lunge,
			forward = 0.7 * lunge,
			swingR = -26 * paw - 18 * lunge,
			swingL = 18 * lunge,
			liftR = 0.1 * paw,
			head = R(-8 * low + 6 * fly, 0, 0),
			armR = { -30 * low, 6, 50 * low },
			armL = { -30 * low, 6, 50 * low },
			toastL = T(0, 0.9 * fly, 0),
			toastR = T(0, 0.5 * fly, 0, 0, 360 * turn, 0),
			tail = Q.Tail(50 * low, 20 * wave(t, 0.2) * low),
		})
	end,
}

return Q.Finish(set)
