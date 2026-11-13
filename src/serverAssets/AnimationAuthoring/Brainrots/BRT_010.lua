--!strict
-- Talpa Di Fero (BRT_010): authored animation set. Archetype: Biped (squat) with elbows
-- (owner asked for them at review, 13 Nov 2026); no knees.
-- Bones: RigTorso, RigHead, RigDrill (signature prop: the drill snout, under the head, on
-- the drill's own axis), RigRightArm > RigRightForearm, RigLeftArm > RigLeftForearm (short
-- arms reaching forward; each forearm carries a big shovel hand), RigRightLeg, RigLeftLeg,
-- RigTail.
-- The meme: an iron mole with a drill for a nose. Squat, waddling, short-sighted behind big
-- goggles; everything he does ends in drilling. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx leans the body or head back, swings a leg
-- forward and lifts the forward-reaching arms and forearms; +ry turns left; the drill spins with rz
-- (its axis points forward); Q.Tail(up, side) lifts the tail.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local set: { [string]: any } = {}

-- Banked: revving. Twice a loop the drill spins up for a full turn and a half while he
-- puffs his chest and lifts his shovel hands.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local rev = bump(t, 0.2, 1.3) + bump(t, 1.7, 2.8)
		local turns = seg(t, 0.2, 1.3) + seg(t, 1.7, 2.8)
		return {
			RigTorso = T(0, 0.06 * rev, 0, 4 * rev, 7 * wave(t, 3.0), 0),
			RigHead = R(5 * rev, 9 * wave(t, 3.0, 0.08), 0),
			RigDrill = R(0, 0, 540 * turns),
			RigRightArm = R(16 * rev, 0, 5 * rev),
			RigLeftArm = R(16 * rev, 0, -5 * rev),
			RigRightForearm = R(22 * rev),
			RigLeftForearm = R(22 * rev),
			RigTail = Q.Tail(14 * rev, 10 * wave(t, 0.75)),
		}
	end,
}
-- Sniffing the air: the drill twitches a quarter turn each way like a nose.
set.IdleWild = {
	name = "IdleWild",
	length = 3.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.8)
		return {
			RigTorso = T(0, 0.02 + 0.02 * breathe, 0, 1, 0, 1.2 * wave(t, 3.6)),
			RigHead = R(3 * wave(t, 0.9), 16 * wave(t, 3.6, 0.05), 0),
			RigDrill = R(0, 0, 40 * wave(t, 0.9, 0.1)),
			RigRightArm = R(3 * breathe),
			RigLeftArm = R(3 * breathe),
			RigRightForearm = R(5 * wave(t, 1.8, 0.2)),
			RigLeftForearm = R(5 * wave(t, 1.8, 0.2)),
			RigTail = Q.Tail(0, 8 * wave(t, 1.8)),
		}
	end,
}
-- Rare variant: bends down and scrabbles at the ground with both shovel hands.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local down = seg(t, 0.05, 0.4) * (1 - seg(t, 1.55, 1.95))
		local dig = down * wave(t, 0.3)
		return {
			RigTorso = T(0, 0, 0, -20 * down, 0, 2 * dig),
			RigHead = R(-10 * down, 0, 0),
			RigDrill = R(0, 0, 30 * dig),
			RigRightArm = R(-14 * down + 22 * dig),
			RigLeftArm = R(-14 * down - 22 * dig),
			RigRightForearm = R(-10 * down + 30 * down * wave(t, 0.3, 0.2)),
			RigLeftForearm = R(-10 * down - 30 * down * wave(t, 0.3, 0.2)),
			RigTail = Q.Tail(20 * down, 0),
		}
	end,
}
-- The waddle: short steps, a big roll from side to side, the tail wagging.
set.Walk = {
	name = "Walk",
	length = 0.7,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.7)
		return {
			RigTorso = T(0, 0.03 + 0.04 * math.abs(s), 0, -3, 5 * s, 8 * s),
			RigHead = R(2, -4 * s, -6 * s),
			RigDrill = R(0, 0, 12 * wave(t, 0.35)),
			RigRightLeg = R(24 * s),
			RigLeftLeg = R(-24 * s),
			RigRightArm = R(-9 * s),
			RigLeftArm = R(9 * s),
			RigRightForearm = R(-10 * wave(t, 0.7, -0.12)),
			RigLeftForearm = R(10 * wave(t, 0.7, -0.12)),
			RigTail = Q.Tail(4, 16 * s),
		}
	end,
}
-- The scurry: head down, drill spinning, the shovel hands paddling as if he were digging
-- through the air.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		return {
			RigTorso = T(0, 0.06 + 0.08 * math.abs(s), 0, -14, 4 * s, 5 * s),
			RigHead = R(6, 0, -3 * s),
			RigDrill = R(0, 0, 360 * t / 0.4),
			RigRightLeg = R(40 * s),
			RigLeftLeg = R(-40 * s),
			RigRightArm = R(-24 * s),
			RigLeftArm = R(24 * s),
			RigRightForearm = R(14 - 30 * wave(t, 0.4, -0.15)),
			RigLeftForearm = R(14 + 30 * wave(t, 0.4, -0.15)),
			RigTail = Q.Tail(24, 10 * s),
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
			RigTorso = T(0, 0.25 * air, 0, 6 * up, 0, 0),
			RigHead = R(12 * up, 0, 0),
			RigDrill = R(0, 0, 90 * up),
			RigRightArm = R(26 * up, 0, 10 * up),
			RigLeftArm = R(26 * up, 0, -10 * up),
			RigRightForearm = R(34 * up),
			RigLeftForearm = R(34 * up),
			RigTail = Q.Tail(34 * up, 0),
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
			RigTorso = T(0, 0, 0.12 * hit, 9 * hit, 0, 7 * hit),
			RigHead = R(-12 * hit, 10 * hit, 10 * hit),
			RigDrill = R(0, 0, -50 * hit),
			RigRightArm = R(20 * hit, 0, 14 * hit),
			RigLeftArm = R(12 * hit, 0, -8 * hit),
			RigRightForearm = R(24 * hit),
			RigLeftForearm = R(10 * hit),
			RigLeftLeg = R(-12 * hit),
			RigTail = Q.Tail(20 * hit, -14 * hit),
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
			RigHead = R(6 * wave(t, 0.5), 14 * wave(t, 1.0, 0.1), 0),
			RigDrill = R(0, 0, 60 * wave(t, 0.5)),
			RigRightLeg = R(26 * k),
			RigLeftLeg = R(-26 * k),
			RigRightArm = R(24 * wave(t, 0.25, 0.1)),
			RigLeftArm = R(-24 * wave(t, 0.25, 0.1)),
			RigRightForearm = R(20 + 30 * wave(t, 0.25, 0.3)),
			RigLeftForearm = R(20 - 30 * wave(t, 0.25, 0.3)),
			RigTail = Q.Tail(10, 22 * wave(t, 0.5)),
		}
	end,
}
-- Asleep sitting on his round bottom: legs out in front, head dropped so the drill rests
-- on his belly plate, shovel hands in his lap.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		-- over-lowered on purpose: the floor clamp raises it until he just sits on the floor
		return {
			RigTorso = T(0, -1.0 + 0.02 * breathe, 0, 6 + breathe, 0, 0),
			RigHead = R(-20 + 2 * breathe, 0, 5),
			RigDrill = R(0, 0, 4 * breathe),
			RigRightLeg = R(80, 0, 6),
			RigLeftLeg = R(80, 0, -6),
			RigRightArm = R(-10 + breathe),
			RigLeftArm = R(-10 + breathe),
			RigRightForearm = R(-16, 0, -8),
			RigLeftForearm = R(-16, 0, 8),
			RigTail = Q.Tail(72, 0),
		}
	end,
}
-- A hop and a full spin with the drill whirring and both shovel hands up.
set.Celebrate = {
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.22, 0.88)
		return {
			RigTorso = T(0, 1.2 * air, 0, 4 * air, 360 * spin, 0),
			RigHead = R(10 * air, 0, 0),
			RigDrill = R(0, 0, 720 * seg(t, 0.1, 1.1)),
			RigRightLeg = R(0, 0, 12 * air),
			RigLeftLeg = R(0, 0, -12 * air),
			RigRightArm = R(44 * air, 0, 14 * air),
			RigLeftArm = R(44 * air, 0, -14 * air),
			RigRightForearm = R(40 * air),
			RigLeftForearm = R(40 * air),
			RigTail = Q.Tail(30 * air, 0),
		}
	end,
}
-- Signature: the drill dive. He rears back while the drill winds up, then lunges forward
-- nose-first at the ground with the drill at full speed and both hands digging, and pops
-- back upright.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local rear = seg(t, 0, 0.3) * (1 - seg(t, 0.4, 0.52))
		local dive = seg(t, 0.4, 0.56) * (1 - seg(t, 1.3, 1.52))
		local dig = dive * wave(t, 0.2)
		-- winds up slowly, then runs flat out: 4 full turns in all
		local turns = 0.5 * seg(t, 0, 0.4) + 3.5 * seg(t, 0.4, 1.45)
		return {
			RigTorso = T(0, 0, -0.2 * dive, 12 * rear - 42 * dive, 0, 2 * dig),
			RigHead = R(10 * rear - 16 * dive, 0, 0),
			RigDrill = R(0, 0, 360 * turns),
			RigRightArm = R(24 * rear - 6 * dive + 22 * dig, 0, 8 * rear),
			RigLeftArm = R(24 * rear - 6 * dive - 22 * dig, 0, -8 * rear),
			RigRightForearm = R(20 * rear + 36 * dive * wave(t, 0.2, 0.2)),
			RigLeftForearm = R(20 * rear - 36 * dive * wave(t, 0.2, 0.2)),
			RigRightLeg = R(-12 * rear + 26 * dive),
			RigLeftLeg = R(-12 * rear + 26 * dive),
			RigTail = Q.Tail(40 * dive, 18 * dig),
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
