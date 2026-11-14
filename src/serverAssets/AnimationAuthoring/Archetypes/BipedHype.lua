--!strict
-- High-energy biped base set, the "dopamine" pass (owner, 14 Nov 2026: "use initiative, and
-- other games in the niche to tweak each of those brainrots to make them game ready, more
-- dopamine overall"). Written for the brainrot-collection look: never still, a bounce on every
-- beat, big silhouettes that read from across the map, an anticipation crouch before every
-- jump and a squash on every landing. Squash is a knee dip, never a part rescale.
-- Bones: RigTorso, RigNeck, RigHead, RigRightLeg > RigRightLowerLeg, RigLeftLeg >
-- RigLeftLowerLeg, RigRightArm, RigLeftArm, RigTail. A species without one of them simply
-- ignores it (the baker only keys bones the rig has). Every clip lowers the body a little on
-- purpose: bake through AnimationBaker.GroundedSet, whose floor clamp puts the feet back on
-- the ground, so a rig with knees sinks into them and one without stays upright.
-- Build(shape, look) returns the nine shared clips keyed by name; the species file adds its
-- own IdleDisplay and Signature (and may replace any clip). Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head back and swings a leg or
-- arm forward; a knee bends with -rx on the lower leg; +ry turns left; the right arm lifts
-- outward with +rz, the left with -rz; Q.Tail(up, side).
local Q = require(script.Parent.Quadruped)
local Biped = require(script.Parent.Biped)
local R, wave, seg, snap, bump = Q.R, Q.wave, Q.seg, Q.snap, Q.bump

local Hype = {}

type Poses = { [string]: CFrame }

-- Per-species limits, all scales default 1: smaller numbers keep a bulky part clear of the body.
export type Look = {
	head: number?, -- head and neck turns
	tail: number?, -- tail moves
	arms: number?, -- arm swing
	raise: number?, -- arm raises
	out: number?, -- degrees the arms are held away from the body (default 4)
	walkStride: number?,
	runStride: number?,
	jumpLegs: number?, -- leg moves in jumps, Hit and Carried
	hop: number?, -- height of bounces and jumps
	tilt: number?, -- body pitch and roll over the hips
}

type Spec = {
	right: number?,
	left: number?,
	kr: number?,
	kl: number?,
	pitch: number?,
	roll: number?,
	yaw: number?,
	lift: number?,
	drop: number?,
	splay: number?,
	head: CFrame?,
	neck: CFrame?,
	tail: CFrame?,
	armR: { number }?, -- { swing, raise }
	armL: { number }?,
}

local identity = CFrame.new()
local function damp(cf: CFrame?, k: number): CFrame
	return identity:Lerp(cf or identity, k)
end

function Hype.Build(shape: Biped.Shape, look: Look?): { [string]: any }
	local L: Look = look or {}
	local kHead, kTail, kArms, kRaise = L.head or 1, L.tail or 1, L.arms or 1, L.raise or 1
	local out, kWalk, kRun, kJump, kHop =
		L.out or 4, L.walkStride or 1, L.runStride or 1, L.jumpLegs or 1, L.hop or 1
	local kTilt = L.tilt or 1

	-- The torso always sits 0.05 low so the clamp sets the feet exactly on the ground.
	local function pose(o: Spec): Poses
		local p = Biped.Stance(
			shape,
			o.right or 0,
			o.left or 0,
			o.splay or 0,
			(o.pitch or 0) * kTilt,
			(o.roll or 0) * kTilt,
			(o.lift or 0) * kHop - (o.drop or 0) - 0.05,
			o.yaw
		)
		p.RigRightLowerLeg = R(-(o.kr or 0))
		p.RigLeftLowerLeg = R(-(o.kl or 0))
		p.RigHead = damp(o.head, kHead)
		p.RigNeck = damp(o.neck, kHead)
		p.RigTail = damp(o.tail, kTail)
		local ar, al = o.armR or { 0, 0 }, o.armL or { 0, 0 }
		p.RigRightArm = R(kArms * ar[1], 0, out + kRaise * ar[2])
		p.RigLeftArm = R(kArms * al[1], 0, -out - kRaise * al[2])
		return p
	end

	local set: { [string]: any } = {}

	-- Never still: a bop on every beat with a knee dip, the body swaying and turning, the head
	-- looking about, the tail wagging and the arms loose.
	local function groove(t: number): Poses
		local bop = math.abs(wave(t, 1.5))
		local dip = 1 - bop
		local sway = wave(t, 3.0)
		return pose({
			right = 8 * dip,
			left = 8 * dip,
			kr = 16 * dip,
			kl = 16 * dip,
			lift = 0.07 * bop,
			drop = 0.12 * dip,
			pitch = 3 * bop,
			roll = 4 * sway,
			yaw = 10 * wave(t, 3.0, 0.25),
			head = R(7 * bop - 2, 18 * wave(t, 3.0, 0.1), -6 * sway),
			neck = R(4 * bop, 8 * sway, 0),
			tail = Q.Tail(16 + 12 * bop, 36 * wave(t, 0.75)),
			armR = { 12 * wave(t, 1.5), 8 + 10 * bop },
			armL = { -12 * wave(t, 1.5), 8 + 10 * bop },
		})
	end
	set.IdleDisplay =
		{ name = "IdleDisplay", length = 3.0, loop = true, priority = "Idle", pose = groove }
	set.IdleWild =
		{ name = "IdleWild", length = 3.0, loop = true, priority = "Idle", pose = groove }

	-- Rare variant: excited look-around. Two little hops, a big glance left on the first and
	-- right on the second, arms flung up, then a happy wiggle.
	set.IdleWild2 = {
		name = "IdleWild2",
		length = 2.2,
		loop = false,
		priority = "Idle",
		pose = function(t: number): Poses
			local h = bump(t, 0.15, 0.5) + bump(t, 1.05, 1.4)
			local squash = bump(t, 0, 0.18)
				+ bump(t, 0.48, 0.66)
				+ bump(t, 0.9, 1.08)
				+ bump(t, 1.38, 1.58)
			local lookL = seg(t, 0.2, 0.45) * (1 - seg(t, 0.8, 1.0))
			local lookR = seg(t, 1.1, 1.35) * (1 - seg(t, 1.75, 2.05))
			local wiggle = wave(t, 0.25) * seg(t, 1.6, 1.7) * (1 - seg(t, 2.0, 2.2))
			return pose({
				right = 16 * squash + 12 * h * kJump,
				left = 16 * squash + 12 * h * kJump,
				kr = 32 * squash + 24 * h * kJump,
				kl = 32 * squash + 24 * h * kJump,
				lift = 0.45 * h,
				drop = 0.25 * squash,
				pitch = 5 * h - 5 * squash,
				roll = 6 * wiggle,
				yaw = 40 * lookL - 40 * lookR,
				head = R(10 * h - 6 * squash, 22 * lookL - 22 * lookR, 8 * wiggle),
				neck = R(4 * h, 10 * lookL - 10 * lookR, 0),
				tail = Q.Tail(40 * h, 34 * wave(t, 0.25) * (lookL + lookR) + 30 * wiggle),
				armR = { 10 * h, 70 * h + 20 * math.abs(wiggle) },
				armL = { 10 * h, 70 * h + 20 * math.abs(wiggle) },
			})
		end,
	}

	-- The bounce walk: a little hop on every step, the body rocking and swinging, the head
	-- bobbing against it, arms swinging wide against the legs, the tail wagging in time.
	set.Walk = {
		name = "Walk",
		length = 0.6,
		loop = true,
		priority = "Movement",
		speed = shape.walkSpeed,
		pose = function(t: number): Poses
			local s = wave(t, 0.6)
			local c = math.cos(t / 0.6 * math.pi * 2)
			local high = 1 - math.abs(s)
			return pose({
				right = 30 * kWalk * s,
				left = -30 * kWalk * s,
				kr = 45 * kWalk * math.max(0, c),
				kl = 45 * kWalk * math.max(0, -c),
				lift = 0.11 * high,
				pitch = -3 + 2 * high,
				roll = 7 * s,
				yaw = 9 * s,
				head = R(3 - 5 * high, -7 * s, -5 * s),
				neck = R(3 * high, -4 * s, 0),
				tail = Q.Tail(14, -32 * s),
				armR = { -34 * s, 6 },
				armL = { 34 * s, 6 },
			})
		end,
	}

	-- The sprint: leaning hard in, knees high, arms pumping, the body bounding off every step.
	set.Run = {
		name = "Run",
		length = 0.34,
		loop = true,
		priority = "Movement",
		speed = shape.runSpeed,
		pose = function(t: number): Poses
			local s = wave(t, 0.34)
			local c = math.cos(t / 0.34 * math.pi * 2)
			local high = 1 - math.abs(s)
			return pose({
				right = 50 * kRun * s,
				left = -50 * kRun * s,
				kr = 85 * kRun * math.max(0, c),
				kl = 85 * kRun * math.max(0, -c),
				lift = 0.2 * high - 0.12, -- feet down at full stride, airborne between
				pitch = -14 + 3 * high,
				roll = 4 * s,
				yaw = 7 * s,
				head = R(16 - 4 * high, -5 * s, 0),
				neck = R(-10, 0, 0),
				tail = Q.Tail(50 + 8 * high, -26 * s),
				armR = { -56 * s, 14 },
				armL = { 56 * s, 14 },
			})
		end,
	}

	-- Alert: a startled crouch, a jump straight up with arms and tail flung out, a squash.
	set.Alert = {
		name = "Alert",
		length = 0.5,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local crouch = bump(t, 0, 0.14)
			local air = bump(t, 0.1, 0.38)
			local land = bump(t, 0.34, 0.5)
			local squash = crouch + land
			return pose({
				right = 18 * squash + 10 * air * kJump,
				left = 18 * squash + 10 * air * kJump,
				kr = 40 * squash + 25 * air * kJump,
				kl = 40 * squash + 25 * air * kJump,
				lift = 0.55 * air,
				drop = 0.25 * squash,
				pitch = -6 * crouch + 10 * air - 4 * land,
				head = R(-8 * crouch + 20 * air, 0, 0),
				neck = R(12 * air, 0, 0),
				tail = Q.Tail(60 * air, 0),
				armR = { 20 * air, 80 * air },
				armL = { 20 * air, 80 * air },
			})
		end,
	}

	-- Hit: a hard recoil back and to one side, arms flung, a wobble as it recovers.
	set.Hit = {
		name = "Hit",
		length = 0.3,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local hit = snap(t, 0, 0.07) * (1 - seg(t, 0.12, 0.3))
			local wob = wave(t, 0.15) * bump(t, 0.1, 0.3)
			return pose({
				right = -14 * hit * kJump,
				left = 8 * hit * kJump,
				kr = 30 * hit,
				kl = 10 * hit,
				drop = 0.2 * hit,
				pitch = 16 * hit,
				roll = 12 * hit + 5 * wob,
				yaw = -12 * hit,
				head = R(-20 * hit, 16 * hit, 14 * hit + 8 * wob),
				neck = R(16 * hit, 0, -8 * hit),
				tail = Q.Tail(40 * hit, -30 * hit),
				armR = { -20 * hit, 50 * hit },
				armL = { -20 * hit, 50 * hit },
			})
		end,
	}

	-- Carried: a frantic tantrum, legs kicking, arms windmilling, body wriggling.
	set.Carried = {
		name = "Carried",
		length = 0.8,
		loop = true,
		priority = "Movement",
		pose = function(t: number): Poses
			local k = wave(t, 0.2)
			local wiggle = wave(t, 0.4)
			return pose({
				right = 15 + 35 * k * kJump,
				left = 15 - 35 * k * kJump,
				kr = 40 + 30 * k,
				kl = 40 - 30 * k,
				pitch = 4 * wave(t, 0.4, 0.25),
				roll = 12 * wiggle,
				yaw = 10 * wave(t, 0.8),
				head = R(8 * wave(t, 0.4, 0.1), 22 * wave(t, 0.8, 0.1), 12 * wiggle),
				neck = R(0, 10 * wave(t, 0.8), 0),
				tail = Q.Tail(30, 50 * wave(t, 0.4)),
				armR = { 30 * wave(t, 0.4), 90 + 40 * k },
				armL = { -30 * wave(t, 0.4), 90 - 40 * k },
			})
		end,
	}

	-- Sleep: dozing on its feet, slumped, breathing slowly; every two seconds the head droops
	-- lower and lower and jerks back up with a snore.
	set.Sleep = {
		name = "Sleep",
		length = 4.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 4.0)
			local u = t % 2.0
			local droop = seg(u, 0, 1.6) * (1 - snap(u, 1.6, 1.75))
			return pose({
				right = 6,
				left = 6,
				kr = 12,
				kl = 12,
				lift = 0.03 * breathe,
				drop = 0.15,
				pitch = -6 + 2 * breathe,
				roll = 2 * breathe,
				head = R(-18 - 14 * droop, 0, 8),
				neck = R(-20 - 10 * droop, 0, 4),
				tail = Q.Tail(-4 + 4 * breathe, 10),
				armR = { 4 * breathe, -2 },
				armL = { 4 * breathe, -2 },
			})
		end,
	}

	-- Celebrate: crouch, a big spinning jump with arms up and legs tucked, a squash, then a
	-- second little hop for joy.
	set.Celebrate = {
		name = "Celebrate",
		length = 1.5,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local crouch = bump(t, 0, 0.16)
			local air = bump(t, 0.12, 0.8)
			local spin = seg(t, 0.16, 0.78)
			local land = bump(t, 0.76, 0.95)
			local air2 = bump(t, 0.9, 1.25)
			local land2 = bump(t, 1.22, 1.5)
			local squash = crouch + land + land2
			local tuck = kJump * (40 * air + 20 * air2)
			return pose({
				right = 18 * squash + tuck,
				left = 18 * squash + tuck,
				kr = 45 * squash + 1.5 * tuck,
				kl = 45 * squash + 1.5 * tuck,
				lift = 1.2 * shape.jump * air + 0.4 * air2,
				drop = 0.25 * squash,
				pitch = 8 * air - 6 * crouch,
				yaw = 360 * spin,
				head = R(20 * air + 10 * air2 - 8 * land, 0, 0),
				neck = R(10 * air, 0, 0),
				tail = Q.Tail(60 * air + 40 * air2, 40 * wave(t, 0.2) * (air + air2)),
				armR = { 20 * wave(t, 0.2) * air, 150 * air + 100 * air2 + 40 * land },
				armL = { -20 * wave(t, 0.2) * air, 150 * air + 100 * air2 + 40 * land },
			})
		end,
	}

	return set
end

return table.freeze(Hype)
