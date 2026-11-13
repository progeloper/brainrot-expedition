--!strict
-- Tung Tung Tung Sahur (BRT_007): authored animation set. Archetype: Biped with the face on
-- the body (no head or neck joint).
-- Bones: RigTorso (the log, face included), RigRightLeg, RigLeftLeg, RigRightArm, RigLeftArm
-- (the arm that holds the bat), RigBat (signature prop, under RigLeftArm).
-- The meme: a scowling wooden slit-drum on long legs who comes for you with a bat, beating
-- out "tung, tung, tung". Stiff as a log above the hips, all menace in the stride and the bat.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx leans the body back / swings a leg or arm
-- forward; +ry turns left; the bat arm (on the -X side) lifts outward with -rz, and the bat
-- itself swings up and out with -rz.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local set: { [string]: any } = {}

-- Banked: the slow drumbeat. The bat lifts and drops three times a bar.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local beat = math.max(0, wave(t, 0.5)) * (if t % 3.0 < 1.5 then 1 else 0)
		return {
			RigTorso = T(0, 0.05 * beat, 0, 2, 9 * wave(t, 3.0), 1.5 * wave(t, 1.5)),
			RigLeftArm = R(6 * beat, 0, -6 * beat),
			RigBat = R(0, 0, -20 * beat),
			RigRightArm = R(-4 * wave(t, 1.5), 0, 3),
		}
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
			RigTorso = T(0, 0.03 + 0.03 * breathe, 0, 0.5, 12 * wave(t, 3.6), 0),
			RigLeftArm = R(2 * breathe, 0, 0),
			RigBat = R(0, 0, -3 * math.max(0, breathe)),
			RigRightArm = R(-2 * breathe, 0, 2),
		}
	end,
}
-- Rare variant: lifts the bat, looks it over, lowers it again.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local up = seg(t, 0.05, 0.5) * (1 - seg(t, 1.4, 1.9))
		return {
			RigTorso = T(0, 0, 0, 1.5 * up, 8 * up, 0),
			RigLeftArm = R(38 * up, 0, -8 * up),
			RigBat = R(0, 0, -62 * up + 8 * up * wave(t, 0.4)),
		}
	end,
}
-- The stalk: long slow strides, leaning in, the bat swinging with the arm.
set.Walk = {
	name = "Walk",
	length = 0.9,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.9)
		return {
			RigTorso = T(0, 0.05 + 0.06 * math.abs(s), 0, -4, 3 * s, 2 * s),
			RigRightLeg = R(24 * s),
			RigLeftLeg = R(-24 * s),
			RigRightArm = R(-13 * s, 0, 2),
			RigLeftArm = R(13 * s, 0, 0),
			RigBat = R(0, 0, -6 * wave(t, 0.9, 0.12)),
		}
	end,
}
-- The sprint: he is a Sprinter. Leaning hard, bat cocked back and up.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 10.8,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		return {
			RigTorso = T(0, 0.12 + 0.14 * math.abs(s), 0, -13, 4 * s, 2 * s),
			RigRightLeg = R(46 * s),
			RigLeftLeg = R(-46 * s),
			RigRightArm = R(-44 * s, 0, 4),
			RigLeftArm = R(-34 + 6 * s, 0, -12),
			RigBat = R(0, 0, -52 + 8 * wave(t, 0.2)),
		}
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
			RigLeftArm = R(40 * up, 0, -10 * up),
			RigBat = R(0, 0, -72 * up),
			RigRightArm = R(0, 0, 14 * up),
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
		return {
			RigTorso = T(0, 0, 0.14 * hit, 8 * hit, 0, 7 * hit),
			RigLeftArm = R(-10 * hit, 0, -20 * hit),
			RigBat = R(0, 0, -30 * hit),
			RigRightArm = R(0, 0, 24 * hit),
			RigLeftLeg = R(-12 * hit),
		}
	end,
}
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local k = wave(t, 0.25)
		return {
			RigTorso = R(3 * wave(t, 0.5), 6 * wave(t, 1.0), 4 * wave(t, 1.0, 0.25)),
			RigRightLeg = R(24 * k),
			RigLeftLeg = R(-24 * k),
			RigRightArm = R(20 * wave(t, 0.5), 0, 12),
			RigLeftArm = R(24 + 20 * wave(t, 0.5, 0.25), 0, -14),
			RigBat = R(0, 0, -40 + 26 * wave(t, 0.5)),
		}
	end,
}
-- Asleep standing: he is a log, so he sleeps like one. Arms limp, a slight lean.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		return {
			RigTorso = T(0, 0.02 + 0.02 * breathe, 0, -2, 0, 3 + breathe),
			RigRightArm = R(3, 0, -2),
			RigLeftArm = R(3, 0, 2),
			RigBat = R(0, 0, 4),
		}
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
		return {
			RigTorso = T(0, 1.6 * air, 0, 4 * air, 360 * spin, 0),
			RigRightLeg = R(0, 0, 14 * air),
			RigLeftLeg = R(0, 0, -14 * air),
			RigRightArm = R(0, 0, 60 * air),
			RigLeftArm = R(0, 0, -70 * air),
			RigBat = R(0, 0, -60 * air),
		}
	end,
}
-- Signature: TUNG, TUNG, TUNG. The bat comes up and beats down three times, the whole log
-- jolting on each one, then he levels it straight at you and holds.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local ready = seg(t, 0, 0.12) * (1 - seg(t, 1.42, 1.6))
		local drumming = seg(t, 0.1, 0.16) * (1 - seg(t, 0.88, 0.94))
		local beat = (0.5 - 0.5 * math.cos(math.clamp((t - 0.13) / 0.75, 0, 1) * math.pi * 6))
			* drumming
		local point = seg(t, 0.94, 1.08) * (1 - seg(t, 1.42, 1.6))
		return {
			RigTorso = T(0, 0.05 * beat, 0, -3 * beat + 3 * point, 10 * point, 0),
			RigLeftArm = R((70 - 34 * beat) * ready * (1 - point) + 86 * point, 0, -10 * ready),
			RigBat = R(0, 0, (-74 + 30 * beat) * ready * (1 - point) - 46 * point),
			RigRightArm = R(-10 * ready, 0, 10 * ready),
			RigRightLeg = R(8 * point),
			RigLeftLeg = R(-8 * point),
		}
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
