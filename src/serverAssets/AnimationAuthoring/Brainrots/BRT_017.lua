--!strict
-- Orangutini Ananassini (BRT_017): authored animation set. Archetype: Upright biped with long
-- arms, knees and a swinging skirt.
-- Bones: RigTorso (the pineapple barrel, with the lei and the shoulder caps), RigHead (with
-- the leaf crown), two upper arms and forearms (each forearm carries the big hand), two
-- thighs and lower legs, and RigSkirt (the grass skirt and its glowing waistband, hinged at
-- the waist).
-- The meme: a pineapple orangutan at a tiki party. His arms are so long his knuckles brush
-- the ground, his grin never fades, and at any excuse he breaks into a hula. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head up and back and swings
-- a hanging limb forward; +ry turns left; the right arm lifts out sideways with +rz; the
-- skirt rolls to his left with +rz. Arm poses are written for the right arm as
-- { rx, ry, rz, elbow } and mirrored for the left.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }
type Arm = { number }

local HIP = 0.89 -- torso pivot down to the hips
local THIGH = 0.45 -- hip to knee
local HALF = 0.38 -- centre line out to each hip

local REST: Arm = { 0, 0, 0, 0 }
-- Found by search against the model: the right hand on the side of his head, under the crown.
local SCRATCH: Arm = { 45, 30, 150, 60 }

local function mix(a: Arm, b: Arm, k: number): Arm
	return {
		a[1] + (b[1] - a[1]) * k,
		a[2] + (b[2] - a[2]) * k,
		a[3] + (b[3] - a[3]) * k,
		a[4] + (b[4] - a[4]) * k,
	}
end

type Options = {
	pitch: number?, -- body tips back (+) or forward (-)
	roll: number?,
	yaw: number?,
	lift: number?,
	swingR: number?, -- thigh angles; the foot stays flat unless `dangle` is set
	swingL: number?,
	liftR: number?,
	liftL: number?,
	dangle: number?,
	head: CFrame?,
	armR: Arm?,
	armL: Arm?,
	skirt: CFrame?,
}

-- One whole-body pose. The legs counter the body's pitch and roll so they stay upright, each
-- foot stays flat, and the body is lowered by what the bent legs take up.
local function pose(o: Options): Poses
	local pitch, roll = o.pitch or 0, o.roll or 0
	local swingR, swingL = o.swingR or 0, o.swingL or 0
	local shorter = THIGH * (1 - math.cos(math.rad(math.min(math.abs(swingR), math.abs(swingL)))))
	local y = (o.lift or 0)
		+ HALF * math.sin(math.rad(math.abs(roll)))
		- HIP * (1 - math.cos(math.rad(pitch)))
		- shorter
	local armR, armL = o.armR or REST, o.armL or REST
	local kneeR = if o.dangle then -o.dangle else -swingR
	local kneeL = if o.dangle then -o.dangle else -swingL
	return {
		RigTorso = T(0, y, 0, pitch, o.yaw or 0, roll),
		RigHead = o.head or R(),
		RigRightLeg = T(0, o.liftR or 0, 0, swingR - pitch, 0, -roll),
		RigLeftLeg = T(0, o.liftL or 0, 0, swingL - pitch, 0, -roll),
		RigRightLowerLeg = R(kneeR),
		RigLeftLowerLeg = R(kneeL),
		RigRightArm = R(armR[1], armR[2], armR[3]),
		RigLeftArm = R(armL[1], -armL[2], -armL[3]),
		RigRightForearm = R(armR[4]),
		RigLeftForearm = R(armL[4]),
		RigSkirt = o.skirt or R(),
	}
end

-- The hula: the hips (the skirt) swing to one side while the body leans the other way, and
-- both arms ride out to the side the hips are swinging from, hands rippling.
local function hula(t: number, period: number, size: number): Options
	local w = wave(t, period)
	local ripple = wave(t, period / 2, 0.15)
	return {
		roll = -3 * size * w,
		swingR = 6 * size,
		swingL = 6 * size,
		head = R(2 * size * math.abs(w), 0, 5 * size * w),
		armR = { 0, 0, 40 * size - 22 * size * w, 18 + 14 * ripple },
		armL = { 0, 0, 40 * size + 22 * size * w, 18 - 14 * ripple },
		skirt = T(-0.05 * size * w, 0, 0) * R(0, 6 * size * wave(t, period, 0.25), 9 * size * w),
	}
end

local set: { [string]: any } = {}

-- Banked: a gentle hula, swaying his skirt and rippling his long arms, grinning.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		return pose(hula(t, 1.5, 1))
	end,
}
set.IdleWild = {
	name = "IdleWild",
	length = 3.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.8)
		local look = wave(t, 3.6, 0.05)
		return pose({
			pitch = 0.8 * breathe,
			roll = 1.2 * wave(t, 3.6),
			lift = 0.02 * breathe,
			head = R(2 * breathe, 24 * look, 3 * wave(t, 1.8, 0.2)),
			armR = { 5 * wave(t, 3.6, 0.3), 0, 3, 6 + 3 * breathe },
			armL = { -5 * wave(t, 3.6, 0.3), 0, 3, 6 + 3 * breathe },
			skirt = R(0, 0, 2 * wave(t, 3.6, 0.2)),
		})
	end,
}
-- Rare variant: the ape scratch. One long arm reaches up and scratches the side of his head
-- under the crown, his head tilting into it, puzzled; then the arm swings back down.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local up = seg(t, 0.1, 0.45) * (1 - seg(t, 1.5, 1.9))
		local rub = up * wave(t, 0.18)
		local arm = mix(REST, SCRATCH, up)
		arm[4] += 10 * rub
		arm[3] += 4 * rub
		return pose({
			roll = 2 * up,
			head = R(-3 * up, -10 * up, -12 * up),
			armR = arm,
			armL = { 0, 0, 4 * up, 8 },
			skirt = R(0, 0, -3 * up),
		})
	end,
}
-- The walk: a rolling ape amble. The long arms swing wide, knuckles skimming the ground, the
-- body rolls over each step and the skirt swishes a beat behind the hips.
set.Walk = {
	name = "Walk",
	length = 0.8,
	loop = true,
	priority = "Movement",
	speed = 6.6,
	pose = function(t: number): Poses
		local s = wave(t, 0.8)
		local c = wave(t, 0.8, 0.25) -- positive while the right foot comes forward
		local right, left = math.max(0, c), math.max(0, -c)
		return pose({
			pitch = -2,
			roll = 5 * c,
			yaw = 7 * s,
			swingR = 24 * s,
			swingL = -24 * s,
			liftR = 0.12 * right,
			liftL = 0.12 * left,
			head = R(2 * wave(t, 0.4), -6 * s, -3 * c),
			armR = { -30 * s, 0, 6, 22 },
			armL = { 30 * s, 0, 6, 22 },
			skirt = R(0, 8 * wave(t, 0.8, 0.1), -6 * wave(t, 0.8, 0.35)),
		})
	end,
}
-- The scamper: leaning in, long arms pumping high, the skirt flying.
set.Run = {
	name = "Run",
	length = 0.5,
	loop = true,
	priority = "Movement",
	speed = 11,
	pose = function(t: number): Poses
		local s = wave(t, 0.5)
		local c = wave(t, 0.5, 0.25)
		local right, left = math.max(0, c), math.max(0, -c)
		return pose({
			pitch = -10,
			roll = 3 * c,
			yaw = 6 * s,
			lift = 0.04 * math.abs(s),
			swingR = 34 * s,
			swingL = -34 * s,
			liftR = 0.2 * right,
			liftL = 0.2 * left,
			head = R(8, -4 * s, 0),
			armR = { -48 * s, 0, 10, 50 },
			armL = { 48 * s, 0, 10, 50 },
			skirt = R(-6, 10 * wave(t, 0.5, 0.1), -8 * wave(t, 0.5, 0.35)),
		})
	end,
}
-- Startled: a hop with both long arms flung up and the skirt jumping.
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
			lift = 0.22 * air,
			head = R(10 * up, 0, 0),
			armR = { 10 * air, 0, 120 * air, 20 * air },
			armL = { 10 * air, 0, 120 * air, 20 * air },
			skirt = T(0, -0.04 * air, 0) * R(-4 * air, 0, 0),
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
			pitch = 9 * hit,
			roll = 5 * hit,
			head = R(-10 * hit, 10 * hit, 8 * hit),
			armR = { 24 * hit, 0, 30 * hit, 20 * hit },
			armL = { 24 * hit, 0, 16 * hit, 20 * hit },
			skirt = R(-8 * hit, 0, 6 * hit),
		})
	end,
}
-- Carried: long arms flailing, legs kicking and the skirt swinging about.
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
			swingR = 26 * k,
			swingL = -26 * k,
			dangle = 24,
			head = R(4 * flap, 14 * wave(t, 1.0, 0.1), 6 * wave(t, 0.5, 0.25)),
			armR = { 30 * k, 0, 50 + 25 * flap, 40 },
			armL = { -30 * k, 0, 50 - 25 * flap, 40 },
			skirt = R(6 * k, 0, 10 * flap),
		})
	end,
}
-- Asleep on his feet: knees bent, slumped forward, head hanging, the long arms dangling with
-- the knuckles resting on the ground, breathing slowly.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		return pose({
			pitch = -8 + 1.2 * breathe,
			lift = -0.05,
			swingR = 22,
			swingL = 22,
			head = R(-22 + 2 * breathe, 0, 9),
			armR = { 8, 0, 4, 22 },
			armL = { 8, 0, 4, 22 },
			skirt = R(5, 0, 0),
		})
	end,
}
-- A jump and a full spin with both arms waving overhead and the skirt flaring up.
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
		local bend = 30 * crouch + 20 * air + 18 * land
		local waveArm = 18 * wave(t, 0.3) * air
		return pose({
			pitch = 4 * air,
			yaw = 360 * spin,
			lift = 0.9 * air,
			swingR = bend,
			swingL = bend,
			head = R(10 * air - 5 * land, 0, 0),
			armR = { 0, 0, 140 * air + 10 * land + waveArm, 20 * air },
			armL = { 0, 0, 140 * air + 10 * land - waveArm, 20 * air },
			skirt = R(-6 * air, 0, 0),
		})
	end,
}
-- Signature: the big hula. Three wide, slow hip swings with his arms flowing from side to
-- side, then a full turn on the spot and a hop to finish with both arms up: aloha.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local dance = seg(t, 0.0, 0.15) * (1 - seg(t, 0.85, 1.0))
		local o = hula(t, 0.6, 1.6 * dance)
		local turn = seg(t, 0.85, 1.25)
		local aloha = seg(t, 1.15, 1.35)
		local hop = bump(t, 1.2, 1.5)
		o.yaw = 360 * turn
		o.lift = 0.3 * hop
		local up: Arm = { 0, 0, 150, 15 }
		o.armR = mix(o.armR :: Arm, up, aloha)
		o.armL = mix(o.armL :: Arm, up, aloha)
		o.head = (o.head :: CFrame) * R(8 * aloha, 0, 0)
		return pose(o)
	end,
}

return Q.Finish(set)
