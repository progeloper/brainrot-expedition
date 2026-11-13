--!strict
-- Lirili Larila (BRT_008): authored animation set. Archetype: Biped with knees.
-- Bones: RigTorso, RigHead, RigTrunk (signature prop, under the head), RigRightArm,
-- RigLeftArm (rigid saguaro arms, bent up), RigRightLeg, RigRightLowerLeg, RigLeftLeg,
-- RigLeftLowerLeg.
-- The meme: a brash cactus-bodied elephant in huge sandals. Heavy, stompy and full of
-- himself; the trunk does the talking. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx leans the body or head back and swings a
-- thigh, arm or the trunk forward; a knee bends with -rx on the lower leg; +ry turns left;
-- the right arm lifts with +rz and the left arm with -rz.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

-- Legs: thigh swing and knee bend (degrees, bend is positive) for each side.
local function legs(rightThigh: number, rightKnee: number, leftThigh: number, leftKnee: number): Poses
	return {
		RigRightLeg = R(rightThigh),
		RigRightLowerLeg = R(-rightKnee),
		RigLeftLeg = R(leftThigh),
		RigLeftLowerLeg = R(-leftKnee),
	}
end
local function with(base: Poses, extra: Poses): Poses
	for bone, cf in extra do
		base[bone] = cf
	end
	return base
end

local set: { [string]: any } = {}

-- Banked: showing off. Arms pump, chest bounces, the trunk lifts and trumpets.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local pump = math.abs(wave(t, 1.5))
		local trumpet = bump(t, 1.9, 2.7)
		return with(legs(0, 0, 0, 0), {
			RigTorso = T(0, 0.1 * pump, 0, 4 + 3 * trumpet, 6 * wave(t, 3.0), 0),
			RigHead = R(4 * pump + 12 * trumpet, 10 * wave(t, 3.0), 0),
			RigTrunk = R(14 * pump + 96 * trumpet, 0, 6 * wave(t, 0.75)),
			RigRightArm = R(0, 0, 16 * pump),
			RigLeftArm = R(0, 0, -16 * pump),
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
		return {
			RigTorso = T(0, 0.02 + 0.02 * breathe, 0, 1, 0, 1.2 * wave(t, 3.6)),
			RigHead = R(2 * breathe, 18 * wave(t, 3.6, 0.05), 0),
			RigTrunk = R(6 * wave(t, 1.8, 0.2), 0, 9 * wave(t, 3.6, 0.15)),
			RigRightArm = R(0, 0, 2 * breathe),
			RigLeftArm = R(0, 0, -2 * breathe),
		}
	end,
}
-- Rare variant: curls the trunk up to scratch the top of his head.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local up = seg(t, 0.05, 0.45) * (1 - seg(t, 1.5, 1.95))
		return {
			RigTorso = T(0, 0, 0, 0, 0, 3 * up),
			RigHead = R(-8 * up, 0, 8 * up),
			RigTrunk = R(118 * up + 10 * up * wave(t, 0.2), 0, 0),
		}
	end,
}
-- The stomp: heavy strides, knees lifting, the trunk swinging like a pendulum.
set.Walk = {
	name = "Walk",
	length = 0.8,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.8)
		return with(legs(24 * s, 36 * math.max(0, wave(t, 0.8, -0.15)), -24 * s, 36 * math.max(0, -wave(t, 0.8, -0.15))), {
			RigTorso = T(0, 0.03 + 0.05 * math.abs(s), 0, -3, 4 * s, 4 * s),
			RigHead = R(2 + 3 * wave(t, 0.4), -4 * s, -3 * s),
			RigTrunk = R(-16 * wave(t, 0.8, 0.12), 0, 5 * s),
			RigRightArm = R(-12 * s),
			RigLeftArm = R(12 * s),
		})
	end,
}
-- The charge: head down, knees high, the trunk streaming back.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		return with(legs(42 * s, 58 * math.max(0, wave(t, 0.4, -0.15)), -42 * s, 58 * math.max(0, -wave(t, 0.4, -0.15))), {
			RigTorso = T(0, 0.1 + 0.12 * math.abs(s), 0, -11, 4 * s, 3 * s),
			RigHead = R(-6, 0, 0),
			RigTrunk = R(-34 + 8 * wave(t, 0.2), 0, 0),
			RigRightArm = R(-26 * s),
			RigLeftArm = R(26 * s),
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
		return {
			RigTorso = T(0, 0.25 * air, 0, 5 * up, 0, 0),
			RigHead = R(10 * up, 0, 0),
			RigTrunk = R(92 * up, 0, 0),
			RigRightArm = R(0, 0, 14 * up),
			RigLeftArm = R(0, 0, -14 * up),
		}
	end,
}
set.Hit = {
	name = "Hit",
	length = 0.25,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
		return with(legs(0, 0, -10 * hit, 14 * hit), {
			RigTorso = T(0, 0, 0.12 * hit, 8 * hit, 0, 7 * hit),
			RigHead = R(-12 * hit, 10 * hit, 10 * hit),
			RigTrunk = R(40 * hit, 0, -20 * hit),
			RigRightArm = R(0, 0, 18 * hit),
		})
	end,
}
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local k = wave(t, 0.25)
		return with(legs(22 * k, 30 + 24 * k, -22 * k, 30 - 24 * k), {
			RigTorso = R(3 * wave(t, 0.5), 6 * wave(t, 1.0), 4 * wave(t, 1.0, 0.25)),
			RigHead = R(6 * wave(t, 0.5), 14 * wave(t, 1.0, 0.1), 0),
			RigTrunk = R(30 + 40 * wave(t, 0.5), 0, 24 * wave(t, 0.5, 0.25)),
			RigRightArm = R(16 * wave(t, 0.5), 0, 8),
			RigLeftArm = R(-16 * wave(t, 0.5), 0, -8),
		})
	end,
}
-- Asleep on his feet: knees soft, head hanging, the trunk swaying slowly.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		-- over-lowered on purpose: the floor clamp raises it until the sandals just touch
		return with(legs(14, 28, 14, 28), {
			RigTorso = T(0, -0.4 + 0.02 * breathe, 0, -5, 0, 2),
			RigHead = R(-12 + breathe, 0, 5),
			RigTrunk = R(4 * breathe, 0, 6 * wave(t, 4.0, 0.2)),
		})
	end,
}
set.Celebrate = {
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.22, 0.88)
		return with(legs(20 * air, 50 * air, 20 * air, 50 * air), {
			RigTorso = T(0, 1.4 * air, 0, 4 * air, 360 * spin, 0),
			RigHead = R(10 * air, 0, 0),
			RigTrunk = R(100 * air, 0, 0),
			RigRightArm = R(0, 0, 30 * air),
			RigLeftArm = R(0, 0, -30 * air),
		})
	end,
}
-- Signature: the trumpet and stomp. He rears back with the trunk straight up, then slams
-- one sandal down and then the other, the trunk whipping forward on each.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local trumpet = seg(t, 0, 0.2) * (1 - seg(t, 0.62, 0.74))
		local right = bump(t, 0.66, 1.0)
		local left = bump(t, 1.0, 1.34)
		local slam = snap(t, 0.86, 0.98) * (1 - seg(t, 0.98, 1.1)) + snap(t, 1.2, 1.32) * (1 - seg(t, 1.32, 1.5))
		return with(legs(44 * right, 60 * right, 44 * left, 60 * left), {
			RigTorso = T(0, 0, 0, 8 * trumpet - 5 * slam, 0, 3 * (left - right)),
			RigHead = R(16 * trumpet - 8 * slam, 0, 0),
			RigTrunk = R(124 * trumpet + 8 * trumpet * wave(t, 0.12) + 30 * slam, 0, 0),
			RigRightArm = R(0, 0, 20 * trumpet),
			RigLeftArm = R(0, 0, -20 * trumpet),
		})
	end,
}

local ORDER = { "IdleDisplay", "IdleWild", "IdleWild2", "Walk", "Run", "Alert", "Hit", "Carried", "Sleep", "Celebrate", "Signature" }
local out = {}
for _, name in ORDER do
	table.insert(out, table.freeze(set[name]))
end
return table.freeze(out)
