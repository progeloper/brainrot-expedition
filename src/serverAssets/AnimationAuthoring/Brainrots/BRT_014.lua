--!strict
-- Bandito Bobritto (BRT_014): authored animation set. Archetype: Biped with knees.
-- Bones: RigTorso, RigHead (fedora and shades included), RigRightArm, RigLeftArm, RigGun
-- (signature prop: the drum-gun both paws hold; its bone sits on the line through the
-- shoulders, so giving the arms and the gun the same swing keeps the paws on it),
-- RigRightLeg > RigRightLowerLeg, RigLeftLeg > RigLeftLowerLeg, RigTail (the paddle tail,
-- which rests on the ground behind him).
-- The meme: a beaver mob boss. All swagger: he rolls his hips when he walks, never lets go
-- of the gun, and thumps his tail on the ground when he wants your attention. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx leans the body or head back, swings a thigh
-- forward and raises the arms and gun; a knee bends with -rx on the lower leg; +ry turns
-- left; Q.Tail(up, side) lifts the tail.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

-- Both arms and the gun swing together, `raise` degrees up from the rest pose. Keep it
-- under about 20: his arms are shorter than his muzzle is long, so a higher gun goes into
-- his face.
local function hold(raise: number, into: Poses): Poses
	into.RigRightArm = R(raise)
	into.RigLeftArm = R(raise)
	into.RigGun = R(raise)
	return into
end
-- Thigh swing and knee bend (degrees, bend is positive) for each side.
local function legs(rt: number, rk: number, lt: number, lk: number, into: Poses): Poses
	into.RigRightLeg = R(rt)
	into.RigRightLowerLeg = R(-rk)
	into.RigLeftLeg = R(lt)
	into.RigLeftLowerLeg = R(-lk)
	return into
end

local set: { [string]: any } = {}

-- Banked: the boss at ease. He rocks on his heels with the gun resting up, and twice a
-- loop he thumps his tail.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local rock = wave(t, 1.5)
		local thump = bump(t, 0.3, 0.7) + bump(t, 1.8, 2.2)
		return hold(12 + 5 * rock, {
			RigTorso = T(0, 0.05 + 0.03 * rock, 0, 2, 7 * wave(t, 3.0), 0),
			RigHead = R(3 * rock, 10 * wave(t, 3.0, 0.1), 4 * wave(t, 3.0)),
			RigTail = Q.Tail(8 + 24 * thump, 0),
		})
	end,
}
-- Shifty: his eyes go left and right over the shades and the gun follows a little.
set.IdleWild = {
	name = "IdleWild",
	length = 3.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.8)
		return hold(2 * breathe, {
			RigTorso = T(0, 0.03 + 0.02 * breathe, 0, 1, 6 * wave(t, 3.6), 0),
			RigHead = R(2 * breathe, 22 * wave(t, 3.6, 0.06), 0),
			RigTail = Q.Tail(3, 6 * wave(t, 1.8)),
		})
	end,
}
-- Rare variant: one hard warning slap of the tail, with a look back over his shoulder.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local look = seg(t, 0.05, 0.4) * (1 - seg(t, 1.5, 1.95))
		local lift = seg(t, 0.3, 0.75) * (1 - snap(t, 0.82, 0.92))
		local jolt = bump(t, 0.86, 1.1)
		return hold(4 * look - 6 * jolt, {
			RigTorso = T(0, 0.04 * look + 0.05 * jolt, 0, 2 * look, 10 * look, 0),
			RigHead = R(-3 * jolt, 34 * look, 0),
			RigTail = Q.Tail(4 * look + 44 * lift, 0),
		})
	end,
}
-- The swagger: hips rolling, knees lifting, the gun bobbing, the tail dragging behind.
set.Walk = {
	name = "Walk",
	length = 0.8,
	loop = true,
	priority = "Movement",
	speed = 6.6,
	pose = function(t: number): Poses
		local s = wave(t, 0.8)
		local lift = wave(t, 0.8, 0.15)
		local rk, lk = 32 * math.max(0, lift), 32 * math.max(0, -lift)
		return legs(
			24 * s,
			rk,
			-24 * s,
			lk,
			hold(4 + 4 * wave(t, 0.4), {
				RigTorso = T(0, 0.05 + 0.05 * math.abs(s), 0, -2, 7 * s, 5 * s),
				RigHead = R(3, -5 * s, -4 * s),
				RigTail = Q.Tail(9, 14 * s),
			})
		)
	end,
}
-- The getaway: leaning in, knees high, gun up across his chest, tail streaming.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 11,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		local lift = wave(t, 0.4, 0.15)
		local rk, lk = 56 * math.max(0, lift), 56 * math.max(0, -lift)
		return legs(
			42 * s,
			rk,
			-42 * s,
			lk,
			hold(12 + 4 * wave(t, 0.2), {
				RigTorso = T(0, 0.1 + 0.12 * math.abs(s), 0, -12, 5 * s, 3 * s),
				RigHead = R(8, 0, -3 * s),
				RigTail = Q.Tail(34, 10 * s),
			})
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
			12 * air,
			26 * air,
			12 * air,
			26 * air,
			hold(18 * up, {
				RigTorso = T(0, 0.28 * air, 0, 5 * up, 0, 0),
				RigHead = R(10 * up, 0, 0),
				RigTail = Q.Tail(5 * up + 30 * air, 0),
			})
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
			16 * hit,
			hold(-10 * hit, {
				RigTorso = T(0, 0, 0.12 * hit, 8 * hit, 0, 7 * hit),
				RigHead = R(-12 * hit, 10 * hit, 10 * hit),
				RigTail = Q.Tail(26 * hit, -16 * hit),
			})
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
		return legs(
			24 * k,
			34 + 24 * k,
			-24 * k,
			34 - 24 * k,
			hold(14 * wave(t, 0.5), {
				RigTorso = R(3 * wave(t, 0.5), 6 * wave(t, 1.0), 4 * wave(t, 1.0, 0.25)),
				RigHead = R(6 * wave(t, 0.5), 14 * wave(t, 1.0, 0.1), 0),
				RigTail = Q.Tail(20 + 22 * wave(t, 0.5, 0.2), 12 * wave(t, 1.0)),
			})
		)
	end,
}
-- Asleep sitting back on his tail: legs out in front with the knees turned out, hat
-- tipped down over his eyes, the gun resting across his lap.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		-- over-lowered on purpose: the floor clamp raises it until he just sits on the floor
		local poses = legs(
			82,
			24,
			82,
			24,
			hold(4 + breathe, {
				RigTorso = T(0, -0.9 + 0.02 * breathe, 0, 7 + breathe, 0, 0),
				RigHead = R(-16 + 2 * breathe, 0, 5),
				RigTail = Q.Tail(48, 0),
			})
		)
		-- knees turned out so the shins pass either side of the gun's drum
		poses.RigRightLeg = R(82, 0, 16)
		poses.RigLeftLeg = R(82, 0, -16)
		return poses
	end,
}
-- A hop and a full spin with the gun hefted.
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
			60 * air,
			30 * air,
			60 * air,
			hold(18 * air, {
				RigTorso = T(0, 1.3 * air, 0, 4 * air, 360 * spin, 0),
				RigHead = R(8 * air, 0, 0),
				RigTail = Q.Tail(40 * air, 20 * wave(t, 0.2) * air),
			})
		)
	end,
}
-- Signature: the boss makes an entrance. Two hard tail thumps, then he hefts the gun,
-- cocks a hip and gives one slow nod.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local thump = bump(t, 0.04, 0.3) + bump(t, 0.32, 0.58)
		local pose = snap(t, 0.6, 0.82) * (1 - seg(t, 1.36, 1.58))
		local nod = pose * bump(t, 0.9, 1.3)
		return legs(
			10 * pose,
			14 * pose,
			-6 * pose,
			0,
			hold(14 * pose - 5 * thump, {
				RigTorso = T(0, 0.04 * thump, 0, 3 * pose, -9 * pose, 5 * pose),
				RigHead = R(4 * pose - 9 * nod, 12 * pose, -6 * pose),
				RigTail = Q.Tail(38 * thump + 6 * pose, 0),
			})
		)
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
