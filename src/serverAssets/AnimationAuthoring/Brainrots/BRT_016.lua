--!strict
-- Gorillo Subwoofero (BRT_016): authored animation set. Archetype: Upright biped with elbows,
-- knees and speakers.
-- Bones: RigTorso (the chest, with the deltoids as fixed shoulder caps), RigHead, two upper
-- arms and forearms (each forearm carries the fist), two thighs and lower legs (each lower leg
-- carries the foot), and RigRightWoofer and RigLeftWoofer: the cone and dust cap of each chest
-- speaker, which pump in and out.
-- The meme: the "bass drop" gorilla, a bodybuilder whose pecs are subwoofers. He beats his
-- chest like any gorilla, and every hit makes the speakers boom. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head up and back and swings
-- a hanging limb forward; +ry turns left; the right arm lifts out sideways with +rz. Arm
-- poses are written for the right arm as { rx, ry, rz, elbow } and mirrored for the left.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }
type Arm = { number }

local HIP = 0.975 -- torso pivot down to the hips
local THIGH = 0.3 -- hip to knee
local HALF = 0.38 -- centre line out to each hip

-- Arm poses found by search against the model: the fist held in front of its own chest
-- woofer, and the fist on the woofer (the hit). The upper arm turns inward (ry) so the
-- deltoid stays out of the chest.
local REST: Arm = { 0, 0, 0, 0 }
local READY: Arm = { 40, 60, 10, 60 }
local HIT: Arm = { 30, 40, -10, 90 }
-- Double-biceps flex: upper arms out level, forearms straight up.
local FLEX: Arm = { 0, 0, 85, 0 }

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
	liftR: number?, -- a foot picked straight up
	liftL: number?,
	dangle: number?, -- knees simply bent by this much
	head: CFrame?,
	armR: Arm?,
	armL: Arm?,
	flexR: number?, -- forearm raised straight up for the flex (degrees about the arm's side axis)
	flexL: number?,
	pumpR: number?, -- a woofer cone pushed out by this many studs
	pumpL: number?,
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
		RigRightForearm = R(armR[4], 0, o.flexR or 0),
		RigLeftForearm = R(armL[4], 0, -(o.flexL or 0)),
		RigRightWoofer = T(0, 0, -(o.pumpR or 0)),
		RigLeftWoofer = T(0, 0, -(o.pumpL or 0)),
	}
end

-- A sharp punch of the cone that decays: 1 at the moment of a hit, 0 by `decay` seconds.
local function boom(since: number, decay: number): number
	if since < 0 or since > decay then
		return 0
	end
	return (1 - since / decay) ^ 2
end

local set: { [string]: any } = {}

-- Banked: the chest drum. He raises his fists and beats the two woofers in turn, each hit
-- booming that speaker, then drops his arms and nods to the beat.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local drum = seg(t, 0, 0.25) * (1 - seg(t, 2.05, 2.4))
		local phase = t % 0.5
		local hitR = drum * bump(phase, 0, 0.25)
		local hitL = drum * bump(phase, 0.25, 0.5)
		local nod = math.abs(wave(t, 0.5))
		return pose({
			pitch = 2 * nod,
			roll = 3 * (hitR - hitL),
			swingR = 8 * nod,
			swingL = 8 * nod,
			head = R(-4 * nod + 3, 0, 4 * (hitL - hitR)),
			armR = mix(mix(REST, READY, drum), HIT, hitR),
			armL = mix(mix(REST, READY, drum), HIT, hitL),
			pumpR = 0.07 * drum * boom(phase - 0.12, 0.2) + 0.015 * nod,
			pumpL = 0.07 * drum * boom(phase - 0.37, 0.2) + 0.015 * nod,
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
			pitch = 0.8 * breathe,
			roll = 1.2 * wave(t, 3.6),
			lift = 0.02 * breathe,
			head = R(2 * breathe, 22 * wave(t, 3.6, 0.05), 3 * wave(t, 1.8, 0.2)),
			armR = { 3 * breathe, 0, 3, 6 },
			armL = { -3 * breathe, 0, 3, 6 },
			pumpR = 0.012 * (1 + breathe),
			pumpL = 0.012 * (1 + breathe),
		})
	end,
}
-- Rare variant: the double-biceps flex. Arms up, fists up, chest out, and the speakers throb
-- three times while he turns his head to admire each arm in turn.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local on = snap(t, 0.08, 0.32) * (1 - seg(t, 1.55, 1.9))
		local throb = on * math.max(0, wave(t - 0.35, 0.4))
		local look = on * wave(t - 0.35, 1.2)
		return pose({
			pitch = 4 * on,
			swingR = 10 * on,
			swingL = 10 * on,
			head = R(3 * on, 30 * look, 0),
			armR = mix(REST, FLEX, on),
			armL = mix(REST, FLEX, on),
			flexR = 95 * on,
			flexL = 95 * on,
			pumpR = 0.06 * throb,
			pumpL = 0.06 * throb,
		})
	end,
}
-- The swagger: heavy steps, shoulders rolling, long arms swinging, the speakers bumping on
-- every footfall.
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
		local step = boom(t % 0.4 - 0.1, 0.25)
		return pose({
			pitch = -3,
			roll = 4 * c,
			yaw = 8 * s,
			lift = 0.02,
			swingR = 24 * s,
			swingL = -24 * s,
			liftR = 0.12 * right,
			liftL = 0.12 * left,
			head = R(2 * wave(t, 0.4), -6 * s, 0),
			armR = { -26 * s, 0, 6, 16 + 10 * math.max(0, -s) },
			armL = { 26 * s, 0, 6, 16 + 10 * math.max(0, s) },
			pumpR = 0.035 * step,
			pumpL = 0.035 * step,
		})
	end,
}
-- The charge: leaning in, fists pumping hard, the speakers pounding on every stride.
set.Run = {
	name = "Run",
	length = 0.5,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.5)
		local c = wave(t, 0.5, 0.25)
		local right, left = math.max(0, c), math.max(0, -c)
		local step = boom(t % 0.25 - 0.06, 0.18)
		return pose({
			pitch = -14,
			roll = 3 * c,
			yaw = 6 * s,
			lift = -0.05 + 0.04 * math.abs(s),
			swingR = 36 * s,
			swingL = -36 * s,
			liftR = 0.2 * right,
			liftL = 0.2 * left,
			head = R(10, -4 * s, 0),
			armR = { -42 * s, 0, 8, 60 },
			armL = { 42 * s, 0, 8, 60 },
			pumpR = 0.05 * step,
			pumpL = 0.05 * step,
		})
	end,
}
-- Startled: he rears up and slams both fists on his chest once, and both speakers boom.
set.Alert = {
	name = "Alert",
	length = 0.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local up = snap(t, 0.04, 0.2)
		local hit = bump(t, 0.12, 0.34)
		local b = boom(t - 0.2, 0.18)
		return pose({
			pitch = 5 * up,
			lift = 0.12 * bump(t, 0.04, 0.36),
			head = R(10 * up, 0, 0),
			armR = mix(mix(REST, READY, up), HIT, hit),
			armL = mix(mix(REST, READY, up), HIT, hit),
			pumpR = 0.09 * b,
			pumpL = 0.09 * b,
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
			armR = { 20 * hit, 0, 26 * hit, 20 * hit },
			armL = { 20 * hit, 0, 14 * hit, 20 * hit },
			pumpR = -0.03 * hit,
			pumpL = -0.03 * hit,
		})
	end,
}
-- Carried: legs kicking, arms flailing, the speakers rattling.
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
			swingR = 28 * k,
			swingL = -28 * k,
			dangle = 24,
			head = R(4 * flap, 14 * wave(t, 1.0, 0.1), 6 * wave(t, 0.5, 0.25)),
			armR = { 30 * k, 0, 40 + 20 * flap, 40 },
			armL = { -30 * k, 0, 40 - 20 * flap, 40 },
			pumpR = 0.03 * math.abs(k),
			pumpL = 0.03 * math.abs(-k),
		})
	end,
}
-- Asleep sitting down: legs stretched out in front, slumped forward, head on his chest,
-- arms resting on his legs, and the speakers pulsing slowly with each breath: a bass snore.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		local snore = math.max(0, breathe) ^ 2
		-- over-lowered on purpose: the floor clamp raises him until he sits on the ground
		local out = pose({
			pitch = -12 + 1.5 * breathe,
			head = R(-20 + 2 * breathe, 0, 8),
			armR = { 34, 0, 8, 20 },
			armL = { 34, 0, 8, 20 },
			pumpR = 0.04 * snore,
			pumpL = 0.04 * snore,
		})
		out.RigTorso = T(0, -1.2 + 0.015 * breathe, 0, -12 + 1.5 * breathe, 0, 0)
		out.RigRightLeg = R(90 + 12 - 1.5 * breathe, 0, 6)
		out.RigLeftLeg = R(90 + 12 - 1.5 * breathe, 0, -6)
		out.RigRightLowerLeg = R(-8)
		out.RigLeftLowerLeg = R(-8)
		return out
	end,
}
-- A jump and a full spin with both arms thrown up and the speakers blasting.
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
		return pose({
			pitch = 4 * air,
			yaw = 360 * spin,
			lift = 0.9 * air,
			swingR = bend,
			swingL = bend,
			head = R(10 * air - 5 * land, 0, 0),
			armR = { 0, 0, 140 * air + 12 * land, 20 * air },
			armL = { 0, 0, 140 * air + 12 * land, 20 * air },
			pumpR = 0.06 * air * math.abs(wave(t, 0.15)) + 0.08 * boom(t - 0.92, 0.25),
			pumpL = 0.06 * air * math.abs(wave(t, 0.15, 0.5)) + 0.08 * boom(t - 0.92, 0.25),
		})
	end,
}
-- Signature: the bass drop. A drum roll on his chest that speeds up, eight hits with each
-- speaker booming; then he lifts both fists high, holds, and drops them onto both woofers
-- at once: the biggest boom, a deep knee dip, and his head thrown back.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local ready = seg(t, 0.0, 0.12) * (1 - seg(t, 0.82, 0.95))
		-- the roll speeds up: phase runs from 0 to 4 cycles over 0.12 to 0.84 s
		local x = math.clamp((t - 0.12) / 0.72, 0, 1)
		local cycles = 4 * x ^ 1.4
		local p = cycles % 1
		local hitR = ready * bump(p, 0, 0.5)
		local hitL = ready * bump(p, 0.5, 1)
		local raise = seg(t, 0.84, 1.02) * (1 - snap(t, 1.06, 1.14))
		local blast = boom(t - 1.13, 0.4)
		local dip = bump(t, 1.08, 1.5)
		local up: Arm = { 150, 0, 20, 30 }
		local roll = 0.08 * ready * math.max(boom(p - 0.25, 0.2), boom(p - 0.75, 0.2))
		return pose({
			pitch = 5 * raise - 4 * dip,
			roll = 3 * (hitR - hitL),
			swingR = 36 * dip,
			swingL = 36 * dip,
			head = R(-3 * ready + 8 * raise + 18 * blast, 0, 0),
			armR = mix(mix(mix(REST, READY, ready), HIT, hitR), up, raise),
			armL = mix(mix(mix(REST, READY, ready), HIT, hitL), up, raise),
			pumpR = if p < 0.5 then roll else 0.0,
			pumpL = if p >= 0.5 then roll else 0.0,
		})
	end,
}

-- The drop: both fists come down from overhead onto the woofers. Written as a second pass so
-- the arm blend above stays readable.
do
	local base = set.Signature.pose
	set.Signature.pose = function(t: number): Poses
		local out = base(t)
		local drop = snap(t, 1.06, 1.14) * (1 - seg(t, 1.3, 1.6))
		local blast = boom(t - 1.13, 0.4)
		if drop > 0 then
			out.RigRightArm = R(HIT[1], HIT[2], HIT[3]):Lerp(out.RigRightArm, 1 - drop)
			out.RigLeftArm = R(HIT[1], -HIT[2], -HIT[3]):Lerp(out.RigLeftArm, 1 - drop)
			out.RigRightForearm = R(HIT[4]):Lerp(out.RigRightForearm, 1 - drop)
			out.RigLeftForearm = R(HIT[4]):Lerp(out.RigLeftForearm, 1 - drop)
		end
		out.RigRightWoofer = out.RigRightWoofer * T(0, 0, -0.12 * blast)
		out.RigLeftWoofer = out.RigLeftWoofer * T(0, 0, -0.12 * blast)
		return out
	end
end

return Q.Finish(set)
