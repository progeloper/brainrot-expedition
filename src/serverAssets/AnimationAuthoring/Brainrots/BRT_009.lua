--!strict
-- Chimpanzini Bananini (BRT_009): authored animation set. Archetype: Biped with elbows and
-- knees (owner asked for them at review, 13 Nov 2026).
-- Bones: RigTorso, RigHead, RigRightArm > RigRightForearm (the long arm that hangs to the
-- floor; the forearm carries the hand and the banana bunch), RigLeftArm > RigLeftForearm (the
-- raised arm; the forearm stands up from the elbow and carries the peeled banana),
-- RigRightLeg > RigRightLowerLeg, RigLeftLeg > RigLeftLowerLeg.
-- The meme: a cheeky green chimp who is all banana. Bouncy, rocking, never still; he
-- waves the peeled banana about like a trophy and takes bites of it. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx leans the body or head back and swings a
-- hanging thigh, arm or forearm forward; a knee bends with -rx on the lower leg; +ry turns
-- left; the right arm lifts outward with +rz. The left forearm points up, so -rx tips it
-- forward and -rz tips it in towards the head.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

-- Legs: thigh swing and knee bend (degrees, bend is positive) for each side.
local function legs(
	rightThigh: number,
	rightKnee: number,
	leftThigh: number,
	leftKnee: number
): Poses
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

-- The bite: upper arm and forearm angles that put the banana tip just in front of the mouth
-- (found by search against the model, see the review notes).
local BITE_ARM = { -20, -20, 0 }
local BITE_FOREARM = { -60, 0, -20 }

local set: { [string]: any } = {}

-- Banked: showing off. He bounces on bent knees and waggles the peeled banana overhead.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local bounce = math.abs(wave(t, 1.0))
		local dip = 1 - bounce
		return with(legs(10 * dip, 20 * dip, 10 * dip, 20 * dip), {
			RigTorso = T(0, 0.14 * bounce - 0.06, 0, 3, 8 * wave(t, 3.0), 0),
			RigHead = R(6 * bounce, 12 * wave(t, 3.0, 0.08), 0),
			RigLeftArm = R(0, 0, -14 - 6 * wave(t, 0.5)),
			RigLeftForearm = R(0, 0, -6 - 18 * wave(t, 0.5, 0.1)),
			RigRightArm = R(8 * wave(t, 1.5), 0, 7),
			RigRightForearm = R(10 + 8 * wave(t, 1.5, 0.15)),
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
			RigTorso = T(0, 0.03 + 0.03 * breathe, 0, 1, 0, 1.5 * wave(t, 3.6)),
			RigHead = R(2 * breathe, 20 * wave(t, 3.6, 0.05), 0),
			RigLeftArm = R(0, 0, 3 * breathe),
			RigLeftForearm = R(0, 0, 5 * wave(t, 1.8, 0.15)),
			RigRightArm = R(4 * wave(t, 3.6, 0.2), 0, 4),
			RigRightForearm = R(6 + 4 * wave(t, 3.6, 0.3)),
		}
	end,
}
-- Rare variant: bends the elbow to bring the peeled banana to his mouth, and takes two bites.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local up = seg(t, 0.05, 0.45) * (1 - seg(t, 1.5, 1.95))
		local chew = up * math.max(0, wave(t - 0.5, 0.45))
		return {
			RigTorso = T(0, 0, 0, -2 * up, 6 * up, 0),
			RigHead = R(-8 * up - 7 * chew, 18 * up, 0),
			RigLeftArm = R(BITE_ARM[1] * up, BITE_ARM[2] * up, BITE_ARM[3] * up),
			RigLeftForearm = R(
				BITE_FOREARM[1] * up,
				BITE_FOREARM[2] * up,
				BITE_FOREARM[3] * up + 5 * chew
			),
			RigRightArm = R(0, 0, 4 * up),
		}
	end,
}
-- The ape lope: rocking side to side on bending knees, the long arm swinging low.
set.Walk = {
	name = "Walk",
	length = 0.8,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.8)
		local lift = wave(t, 0.8, -0.15)
		return with(legs(23 * s, 34 * math.max(0, lift), -23 * s, 34 * math.max(0, -lift)), {
			RigTorso = T(0, 0.04 + 0.06 * math.abs(s), 0, -5, 4 * s, 6 * s),
			RigHead = R(4 + 2 * wave(t, 0.4), -3 * s, -5 * s),
			RigRightArm = R(-18 * s, 0, 5),
			RigRightForearm = R(12 - 12 * s),
			RigLeftArm = R(9 * s, 0, 0),
			RigLeftForearm = R(0, 0, 8 * wave(t, 0.4)),
		})
	end,
}
-- The scamper: bent right over, bounding, knees high, the long arm pumping.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		local lift = wave(t, 0.4, -0.15)
		return with(legs(40 * s, 62 * math.max(0, lift), -40 * s, 62 * math.max(0, -lift)), {
			RigTorso = T(0, 0.12 + 0.16 * math.abs(s), 0, -15, 5 * s, 5 * s),
			RigHead = R(11, 0, -4 * s),
			RigRightArm = R(-40 * s, 0, 8),
			RigRightForearm = R(34 - 26 * s),
			RigLeftArm = R(20 * s, 0, 12),
			RigLeftForearm = R(-18 * s, 0, 10),
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
		return with(legs(14 * air, 30 * air, 14 * air, 30 * air), {
			RigTorso = T(0, 0.3 * air, 0, 6 * up, 0, 0),
			RigHead = R(10 * up, 0, 0),
			RigRightArm = R(10 * up, 0, 34 * up),
			RigRightForearm = R(46 * up),
			RigLeftArm = R(0, 0, -18 * up),
			RigLeftForearm = R(0, 0, 14 * up),
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
		return with(legs(0, 0, -12 * hit, 16 * hit), {
			RigTorso = T(0, 0, 0.14 * hit, 9 * hit, 0, 7 * hit),
			RigHead = R(-12 * hit, 10 * hit, 10 * hit),
			RigRightArm = R(10 * hit, 0, 26 * hit),
			RigRightForearm = R(30 * hit),
			RigLeftArm = R(0, 0, 14 * hit),
			RigLeftForearm = R(0, 0, 22 * hit),
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
		return with(legs(24 * k, 34 + 26 * k, -24 * k, 34 - 26 * k), {
			RigTorso = R(3 * wave(t, 0.5), 6 * wave(t, 1.0), 4 * wave(t, 1.0, 0.25)),
			RigHead = R(6 * wave(t, 0.5), 14 * wave(t, 1.0, 0.1), 0),
			RigRightArm = R(24 + 20 * wave(t, 0.5), 0, 16),
			RigRightForearm = R(40 + 30 * wave(t, 0.5, 0.2)),
			RigLeftArm = R(14 * wave(t, 0.5, 0.25), 0, 8 * wave(t, 0.5)),
			RigLeftForearm = R(0, 0, 24 * wave(t, 0.5, 0.4)),
		})
	end,
}
-- Asleep sitting down: knees up a little, the banana bunch in his lap, chin on his chest,
-- the other arm drooped at his side.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		-- over-lowered on purpose: the floor clamp raises it until he just sits on the floor
		return with(legs(96, 48, 96, 48), {
			RigTorso = T(0, -1.7 + 0.02 * breathe, 0, 5 + breathe, 0, 0),
			RigHead = R(-22 + 2 * breathe, 0, 6),
			RigRightArm = R(26, 0, 4),
			RigRightForearm = R(58 + 2 * breathe),
			RigLeftArm = R(0, 0, 34),
			RigLeftForearm = R(0, 0, 86),
		})
	end,
}
-- A backflip, knees and elbow tucked.
set.Celebrate = {
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.24, 0.86)
		local crouch = bump(t, 0, 0.3) + bump(t, 0.9, 1.2)
		local tuck = math.max(air, 0.45 * crouch)
		return with(legs(62 * tuck, 84 * tuck, 62 * tuck, 84 * tuck), {
			RigTorso = T(0, 2.5 * air - 0.5 * crouch, 0, 360 * spin, 0, 0),
			RigHead = R(8 * air, 0, 0),
			RigRightArm = R(40 * air, 0, 8 * air),
			RigRightForearm = R(86 * air),
			RigLeftArm = R(0, 0, -14 * air),
			RigLeftForearm = R(0, 0, -16 * air),
		})
	end,
}
-- Signature: the monkey dance. Three hops from foot to foot, the free knee kicking up, the
-- banana bunch pumping overhead, hooting at the sky, then he holds both bananas high.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local k = seg(t, 0.04, 0.2) * (1 - seg(t, 1.4, 1.6))
		local s = math.sin(math.clamp((t - 0.15) / 1.05, 0, 1) * math.pi * 6)
		local hop = math.abs(s)
		local right, left = math.max(0, s) * k, math.max(0, -s) * k
		return with(legs(46 * right, 70 * right, 46 * left, 70 * left), {
			RigTorso = T(0, 0.4 * hop * k, 0, 5 * k, 0, 10 * s * k),
			RigHead = R(15 * k, 0, -8 * s * k),
			RigRightArm = R(0, 0, (118 + 10 * s) * k),
			RigRightForearm = R(0, 0, (24 + 30 * hop) * k),
			RigLeftArm = R(0, 0, (-20 + 8 * s) * k),
			RigLeftForearm = R(0, 0, (-10 - 22 * hop) * k),
		})
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
