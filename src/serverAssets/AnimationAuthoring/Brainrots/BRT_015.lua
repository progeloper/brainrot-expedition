--!strict
-- Strawberelli Flamingelli (BRT_015): authored animation set. Archetype: Wader (a biped
-- with knees, a two-joint neck, wings and a tail).
-- Bones: RigTorso (the strawberry), RigNeckBase > RigNeck > RigHead (the S-shaped neck: the
-- base carries the first two bends, the neck the last stretch), RigRightWing, RigLeftWing,
-- RigTail (the plumes), RigRightLeg > RigRightLowerLeg, RigLeftLeg > RigLeftLowerLeg.
-- The meme: a strawberry that is also a flamingo, and very pleased about both. Elegant and
-- a bit vain: the neck is always moving, and at any excuse it goes up on one leg. Written
-- for it.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body, neck or head up and back
-- and swings a thigh forward; a knee bends with -rx on the lower leg; +ry turns left;
-- Q.Tail(up, side) lifts the plumes.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

-- Thigh swing and knee bend (degrees, bend is positive) for each side.
local function legs(rt: number, rk: number, lt: number, lk: number, into: Poses): Poses
	into.RigRightLeg = R(rt)
	into.RigRightLowerLeg = R(-rk)
	into.RigLeftLeg = R(lt)
	into.RigLeftLowerLeg = R(-lk)
	return into
end
-- The neck's three joints, pitch only: base, upper neck, head.
local function neck(base: number, upper: number, head: number, into: Poses): Poses
	into.RigNeckBase = R(base)
	into.RigNeck = R(upper)
	into.RigHead = R(head)
	return into
end
-- Wings flared out from the flanks: 0 is folded, 1 is fully out. Each moves outward a
-- little as it opens so its lower edge does not cut into the strawberry.
local function wings(right: number, left: number, into: Poses): Poses
	into.RigRightWing = T(0.12 * right, 0.08 * right, 0, 0, 0, 32 * right)
	into.RigLeftWing = T(-0.12 * left, 0.08 * left, 0, 0, 0, -32 * left)
	return into
end
-- The one-leg stand: weight over the right leg, the left leg folded up. `on` is 0 to 1.
local function oneLeg(on: number, into: Poses): Poses
	return legs(0, 0, 40 * on, 112 * on, into)
end

local set: { [string]: any } = {}

-- Banked: the neck dance. The S-curve pumps open and shut, the head sways, and the wings
-- shimmy one after the other.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local pump = wave(t, 1.0)
		local sway = wave(t, 3.0)
		local r, l = math.max(0, wave(t, 1.5)), math.max(0, -wave(t, 1.5))
		return wings(
			0.7 * r,
			0.7 * l,
			neck(10 * pump, -16 * pump, 6 * pump, {
				RigTorso = T(0, 0.05 + 0.04 * math.abs(pump), 0, 2, 6 * sway, 3 * sway),
				RigTail = Q.Tail(10 + 8 * pump, 14 * sway),
			})
		)
	end,
}
set.IdleWild = {
	name = "IdleWild",
	length = 3.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.8)
		local poses = neck(4 * breathe, -6 * breathe, 2 * breathe, {
			RigTorso = T(0, 0.03 + 0.02 * breathe, 0, 1, 0, 1.2 * wave(t, 3.6)),
			RigTail = Q.Tail(4, 8 * wave(t, 1.8)),
		})
		poses.RigHead = R(2 * breathe, 24 * wave(t, 3.6, 0.05), 0)
		return wings(0, 0, poses)
	end,
}
-- Rare variant: head-flagging, the flamingo display. The neck stretches up tall and the
-- head flicks from side to side four times.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local tall = seg(t, 0.05, 0.4) * (1 - seg(t, 1.55, 1.95))
		local flick = tall * wave(t - 0.4, 0.28) * seg(t, 0.4, 0.5) * (1 - seg(t, 1.45, 1.55))
		local poses = neck(14 * tall, -22 * tall, 6 * tall, {
			RigTorso = T(0, 0.05 * tall, 0, 3 * tall, 0, 0),
			RigTail = Q.Tail(18 * tall, 10 * flick),
		})
		poses.RigHead = R(6 * tall, 38 * flick, 0)
		return wings(0.25 * tall, 0.25 * tall, poses)
	end,
}
-- The wade: slow, high-stepping, each knee folding right up, the head bobbing forward and
-- back with every step.
set.Walk = {
	name = "Walk",
	length = 0.9,
	loop = true,
	priority = "Movement",
	speed = 6.6,
	pose = function(t: number): Poses
		local s = wave(t, 0.9)
		local lift = wave(t, 0.9, 0.15)
		local rk, lk = 62 * math.max(0, lift), 62 * math.max(0, -lift)
		local bob = wave(t, 0.45, 0.1)
		return legs(
			22 * s,
			rk,
			-22 * s,
			lk,
			wings(
				0,
				0,
				neck(8 * bob, -10 * bob, 3 * bob, {
					RigTorso = T(0, 0.04 + 0.04 * math.abs(s), 0, -2, 3 * s, 2 * s),
					RigTail = Q.Tail(6, 16 * s),
				})
			)
		)
	end,
}
-- The dash: neck stretched out low in front, wings half open and beating, legs flying.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 11,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		local lift = wave(t, 0.4, 0.15)
		local rk, lk = 76 * math.max(0, lift), 76 * math.max(0, -lift)
		local beat = 0.55 + 0.3 * wave(t, 0.2)
		return legs(
			40 * s,
			rk,
			-40 * s,
			lk,
			wings(
				beat,
				beat,
				neck(-34, 22 + 4 * s, 14, {
					RigTorso = T(0, 0.08 + 0.1 * math.abs(s), 0, -12, 4 * s, 3 * s),
					RigTail = Q.Tail(24, 10 * s),
				})
			)
		)
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
		return legs(
			10 * air,
			30 * air,
			10 * air,
			30 * air,
			wings(
				up,
				up,
				neck(16 * up, -22 * up, 8 * up, {
					RigTorso = T(0, 0.3 * air, 0, 5 * up, 0, 0),
					RigTail = Q.Tail(30 * up, 0),
				})
			)
		)
	end,
}
set.Hit = {
	name = "Hit",
	length = 0.25,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
		return legs(
			0,
			0,
			-12 * hit,
			20 * hit,
			wings(
				0.6 * hit,
				0.3 * hit,
				neck(22 * hit, 10 * hit, -16 * hit, {
					RigTorso = T(0, 0, 0.12 * hit, 8 * hit, 0, 7 * hit),
					RigTail = Q.Tail(24 * hit, -16 * hit),
				})
			)
		)
	end,
}
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local k = wave(t, 0.25)
		local flap = 0.5 + 0.4 * wave(t, 0.25, 0.2)
		local n = wave(t, 0.5)
		return legs(
			24 * k,
			40 + 30 * k,
			-24 * k,
			40 - 30 * k,
			wings(
				flap,
				flap,
				neck(12 * n, -14 * n, 6 * n, {
					RigTorso = R(3 * wave(t, 0.5), 6 * wave(t, 1.0), 4 * wave(t, 1.0, 0.25)),
					RigTail = Q.Tail(14 + 14 * n, 12 * wave(t, 1.0)),
				})
			)
		)
	end,
}
-- Asleep the flamingo way: up on one leg, the other folded, the neck laid back and twisted
-- round so the head rests on its back facing behind.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		local poses = oneLeg(
			1,
			wings(0, 0, {
				RigTorso = T(-0.2, 0.02 * breathe, 0, 1 + breathe, 0, -2),
				RigTail = Q.Tail(0, 6 * breathe),
			})
		)
		poses.RigNeckBase = R(60 - breathe)
		poses.RigNeck = R(0, 180, 0)
		poses.RigHead = R(30 + breathe)
		return poses
	end,
}
-- A hop and a full spin with the wings thrown wide and the neck straight up.
set.Celebrate = {
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.22, 0.88)
		return legs(
			30 * air,
			70 * air,
			30 * air,
			70 * air,
			wings(
				air,
				air,
				neck(18 * air, -26 * air, 10 * air, {
					RigTorso = T(0, 1.3 * air, 0, 4 * air, 360 * spin, 0),
					RigTail = Q.Tail(40 * air, 20 * wave(t, 0.2) * air),
				})
			)
		)
	end,
}
-- Signature: the flamingo pose. It snaps up onto one leg, flares both wings, draws its
-- neck into a tall proud curve and holds, with a slow turn of the head to be admired.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local on = snap(t, 0.08, 0.34) * (1 - seg(t, 1.3, 1.56))
		local flare = on * (0.75 + 0.25 * wave(t, 0.3))
		local turn = on * wave(t - 0.34, 1.0)
		local poses = oneLeg(
			on,
			wings(
				flare,
				flare,
				neck(14 * on, -22 * on, 8 * on, {
					RigTorso = T(-0.2 * on, 0.06 * on, 0, 4 * on, 0, -2 * on),
					RigTail = Q.Tail(34 * on, 0),
				})
			)
		)
		poses.RigHead = R(8 * on, 30 * turn, 0)
		return poses
	end,
}

local ORDER = {
	"IdleDisplay",
	"IdleWild",
	"IdleWild2",
	"Walk",
	"Run",
	"Alert",
	"Hit",
	"Carried",
	"Sleep",
	"Celebrate",
	"Signature",
}
local out = {}
for _, name in ORDER do
	table.insert(out, table.freeze(set[name]))
end
return table.freeze(out)
