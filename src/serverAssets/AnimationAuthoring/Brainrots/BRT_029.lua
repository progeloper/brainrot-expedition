--!strict
-- Cocofanto Elefanto (BRT_029): authored animation set. Archetype: Quadruped, reusing the
-- approved Quadruped base set (Archetypes/Quadruped.lua).
-- Bones: RigTorso (the coconut husk, with the cocktail umbrella and bendy straw on top),
-- RigHead (the elephant face in the cut coconut: ears, trunk, tusks, crown and hibiscus),
-- four legs (each stout leg with its pink sneaker), RigTail.
-- The meme: a baby elephant living in a tropical-drink coconut. Holiday mood at all times.
-- Reused: Sleep is the approved Quadruped base clip (belly down, legs splayed). Written for him
-- in the high-energy style: IdleWild, IdleWild2, Walk, Run, Alert, Hit, Carried, Celebrate,
-- IdleDisplay (the holiday sway) and the Signature (the trumpet stomp).
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head up at the front and
-- swings a leg forward; +ry turns left; Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Reuse = require(script.Parent.Parent.Archetypes.Reuse)
local R, wave, seg, snap, bump = Q.R, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local shape: Q.Shape = {
	legLength = 0.94,
	footReach = 0.41,
	footInner = 0.27,
	frontReach = 0.46,
	backReach = 0.5,
	belly = 0.84, -- the coconut's underside; Sleep folds the legs out to lower it
	walkSpeed = 6, -- Epic route speed
	runSpeed = 10,
	jump = 1.2,
}

-- Sleep is the approved Quadruped base clip; the rest are written below for him.
local set = Reuse.Adapt(Q.Build(shape), {
	extra = function(_name: string, _t: number, poses: Poses)
		-- the face sits low inside the cut coconut: smaller head turns keep it there
		poses.RigHead = Reuse.Damp(poses.RigHead, 0.6)
	end,
})

-- One whole-body pose. Every clip sits the body 0.05 low so the floor clamp sets the feet
-- exactly on the ground; head turns are kept at 60 % so the face stays in its coconut.
local function pose(
	swing: { number },
	splay: number,
	pitch: number,
	roll: number,
	lift: number,
	yaw: number,
	head: CFrame,
	tail: CFrame
): Poses
	return Q.With(Q.Stance(shape, swing, splay, pitch, roll, lift - 0.05, yaw), {
		RigHead = Reuse.Damp(head, 0.6),
		RigTail = tail,
	})
end
local function trot(s: number, amount: number): { number }
	return { amount * s, -amount * s, -amount * s, amount * s }
end

-- Never still: a bop on every beat, the coconut rocking and turning, ears and trunk swinging,
-- the tail wagging.
set.IdleWild = {
	name = "IdleWild",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local bop = math.abs(wave(t, 1.5))
		local sway = wave(t, 3.0)
		return pose(
			{ 0, 0, 0, 0 },
			4 * bop,
			3 * bop,
			5 * sway,
			0.08 * bop,
			8 * wave(t, 3.0, 0.25),
			R(6 * bop, 16 * wave(t, 3.0, 0.1), -6 * sway),
			Q.Tail(14 + 12 * bop, 40 * wave(t, 0.75))
		)
	end,
}
-- Rare variant: two happy hops, looking left on the first and right on the second, front
-- feet kicking up, then a wiggle.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.2,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local h = bump(t, 0.15, 0.5) + bump(t, 1.05, 1.4)
		local squash = bump(t, 0.48, 0.66) + bump(t, 1.38, 1.58)
		local lookL = seg(t, 0.2, 0.45) * (1 - seg(t, 0.8, 1.0))
		local lookR = seg(t, 1.1, 1.35) * (1 - seg(t, 1.75, 2.05))
		local wiggle = wave(t, 0.25) * seg(t, 1.6, 1.7) * (1 - seg(t, 2.0, 2.2))
		return pose(
			{ 24 * h, 24 * h, -12 * h, -12 * h },
			16 * squash,
			8 * h,
			6 * wiggle,
			0.4 * h,
			35 * lookL - 35 * lookR,
			R(14 * h, 20 * lookL - 20 * lookR, 8 * wiggle),
			Q.Tail(40 * h, 34 * wave(t, 0.25) * (lookL + lookR) + 30 * wiggle)
		)
	end,
}
-- The bounce trot: diagonal pairs stepping together, a little hop on every step, the coconut
-- rocking, trunk bobbing, tail wagging in time.
set.Walk = {
	name = "Walk",
	length = 0.6,
	loop = true,
	priority = "Movement",
	speed = shape.walkSpeed,
	pose = function(t: number): Poses
		local s = wave(t, 0.6)
		return pose(
			trot(s, 30),
			0,
			2 * wave(t, 0.3),
			5 * s,
			0.09 * (1 - math.abs(s)),
			7 * s,
			R(3 + 4 * wave(t, 0.3), -10 * s, -4 * s),
			Q.Tail(10, -34 * s)
		)
	end,
}
-- The sprint: a bounding trot, nose down, ears back, tail streaming.
set.Run = {
	name = "Run",
	length = 0.32,
	loop = true,
	priority = "Movement",
	speed = shape.runSpeed,
	pose = function(t: number): Poses
		local s = wave(t, 0.32)
		return pose(
			trot(s, 46),
			0,
			-6 + 3 * wave(t, 0.16),
			4 * s,
			0.03 + 0.16 * (1 - math.abs(s)),
			7 * s,
			R(12, -8 * s, 0),
			Q.Tail(40, -34 * s)
		)
	end,
}
-- Alert: a startled crouch, a hop straight up with the legs splayed and the trunk flung up,
-- and a squash.
set.Alert = {
	name = "Alert",
	length = 0.5,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local crouch = bump(t, 0, 0.14)
		local air = bump(t, 0.1, 0.38)
		local land = bump(t, 0.34, 0.5)
		return pose(
			{ 14 * air, 14 * air, -14 * air, -14 * air },
			18 * (crouch + land) + 14 * air,
			-4 * crouch + 10 * air - 4 * land,
			0,
			0.5 * air,
			0,
			R(-8 * crouch + 26 * air, 0, 0),
			Q.Tail(60 * air, 0)
		)
	end,
}
-- Hit: a hard recoil to one side with a wobble.
set.Hit = {
	name = "Hit",
	length = 0.3,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local hit = snap(t, 0, 0.07) * (1 - seg(t, 0.12, 0.3))
		local wob = wave(t, 0.15) * bump(t, 0.1, 0.3)
		return pose(
			{ 0, 0, 0, 0 },
			18 * hit,
			8 * hit,
			14 * hit + 5 * wob,
			0,
			-12 * hit,
			R(-16 * hit, 14 * hit, 16 * hit + 8 * wob),
			Q.Tail(30 * hit, -34 * hit)
		)
	end,
}
-- Carried: a paddling tantrum, all four sneakers kicking, the coconut wriggling.
set.Carried = {
	name = "Carried",
	length = 0.8,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local k = wave(t, 0.2)
		local wiggle = wave(t, 0.4)
		return pose(
			trot(k, 42),
			12,
			3 * wave(t, 0.4, 0.25),
			12 * wiggle,
			0,
			10 * wave(t, 0.8),
			R(8, 22 * wave(t, 0.8, 0.1), 14 * wiggle),
			Q.Tail(30, 50 * wave(t, 0.4))
		)
	end,
}
-- Celebrate: a crouch, a big spinning jump with all four legs tucked, a squash, and a second
-- little hop for joy.
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
		local tuck = 34 * air + 20 * air2
		return pose(
			{ tuck, tuck, -tuck, -tuck },
			20 * (crouch + land + land2),
			8 * air - 4 * crouch,
			0,
			1.3 * shape.jump * air + 0.4 * air2,
			360 * spin,
			R(24 * air + 12 * air2 - 8 * land, 0, 0),
			Q.Tail(60 * air + 40 * air2, 40 * wave(t, 0.2) * (air + air2))
		)
	end,
}

-- Banked: the holiday sway. He rocks side to side to a beach beat, ears flapping, trunk
-- swinging, with a happy little bounce on every other beat.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local side = wave(t, 1.5)
		local beat = math.abs(wave(t, 0.75))
		return Q.With(
			Q.Stance(
				shape,
				{ 0, 0, 0, 0 },
				6 * beat,
				4 + 4 * beat,
				9 * side,
				0.16 * beat - 0.05,
				10 * side
			),
			{
				RigHead = R(4 + 5 * beat, 10 * side, -5 * side),
				RigTail = Q.Tail(10 + 12 * beat, 40 * wave(t, 0.75)),
			}
		)
	end,
}

-- Signature: the trumpet stomp. He rears up on his back sneakers with his trunk thrown high in
-- a trumpet, drops onto his front feet with a stomp, stomps twice more, and shakes his head so
-- his ears flap.
set.Signature = {
	name = "Signature",
	length = 1.8,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local rear = seg(t, 0, 0.35) * (1 - snap(t, 0.7, 0.82))
		local trumpet = bump(t, 0.25, 0.75)
		local s1 = bump(t, 0.82, 1.0)
		local s2 = bump(t, 1.0, 1.18)
		local s3 = bump(t, 1.18, 1.36)
		local stomp = s1 + s2 + s3
		local shake = bump(t, 1.35, 1.8) * wave(t, 0.12)
		local frontR = 40 * rear + 30 * (s1 + s3)
		local frontL = 40 * rear + 30 * s2
		return Q.With(
			Q.Stance(
				shape,
				{ frontR, frontL, -10 * rear, -10 * rear },
				0,
				32 * rear,
				0,
				0.25 * stomp,
				0
			),
			{
				RigHead = R(16 * trumpet - 4 * stomp, 16 * shake, 8 * shake),
				RigTail = Q.Tail(40 * rear + 20 * stomp, 30 * wave(t, 0.2)),
			}
		)
	end,
}

return Q.Finish(set)
