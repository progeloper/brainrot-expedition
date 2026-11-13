--!strict
-- Trulimero Trulicina (BRT_022): authored animation set. Archetype: Quadruped with knees
-- and fins.
-- Bones: RigTorso (the goldfish), RigHead (the cat head; the front legs sit under it, so it
-- turns and nods only a little), four thighs (RigFrontRightLeg ...), four lower legs
-- (RigFrontRightLowerLeg ...; each carries a bare foot), RigTail (the fan tail),
-- RigRightFin and RigLeftFin (the side fins, hinged along their top edge) and RigDorsalFin.
-- The meme: a deadpan cat's head on a goldfish that walks on four human legs. The cat half
-- stays unimpressed while the fish half never stops swimming: the body wiggles, the tail
-- fans and the fins paddle, even on dry land. Written for it.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head up at the front and
-- swings a thigh forward; a knee bends with -rx on the lower leg; +ry turns left; a side fin
-- opens outward with a positive angle; Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local shape: Q.Shape = {
	legLength = 1.05,
	footReach = 0.42,
	footInner = 0.2,
	frontReach = 1.025,
	backReach = 0.425,
	belly = 0.97,
	walkSpeed = 6,
	runSpeed = 10,
	jump = 1.0,
}

-- Knee bends in degrees, in the order front right, front left, back right, back left.
local function knees(fr: number, fl: number, br: number, bl: number): Poses
	return {
		RigFrontRightLowerLeg = R(-fr),
		RigFrontLeftLowerLeg = R(-fl),
		RigBackRightLowerLeg = R(-br),
		RigBackLeftLowerLeg = R(-bl),
	}
end
-- Side fins opened outward by `right` and `left` degrees, and the dorsal fin leaning `lean`.
local function fins(right: number, left: number, lean: number): Poses
	return {
		RigRightFin = R(0, 0, right),
		RigLeftFin = R(0, 0, -left),
		RigDorsalFin = R(0, 0, lean),
	}
end
local function all(...: Poses): Poses
	local out: Poses = {}
	for _, poses in { ... } do
		for bone, cf in poses do
			out[bone] = cf
		end
	end
	return out
end

local set: { [string]: any } = {}

-- Banked: showing off the fins. They fan open one after the other while the tail swishes
-- and the cat head tilts from side to side, unimpressed.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local bounce = math.abs(wave(t, 1.5))
		local fan = wave(t, 0.75)
		return all(
			Q.Stance(shape, { 0, 0, 0, 0 }, 0, 2 * bounce, 2 * wave(t, 3.0), 0.04 * bounce),
			knees(0, 0, 0, 0),
			fins(34 + 24 * fan, 34 - 24 * fan, 10 * wave(t, 0.75, 0.25)),
			{
				RigHead = R(3 + 3 * bounce, 10 * wave(t, 3.0), 6 * wave(t, 1.5)),
				RigTail = Q.Tail(8, 30 * fan),
			}
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
		return all(
			Q.Stance(
				shape,
				{ 0, 0, 0, 0 },
				0,
				0.5 * breathe,
				1.2 * wave(t, 3.6),
				0.03 + 0.02 * breathe
			),
			knees(0, 0, 0, 0),
			fins(10 + 7 * breathe, 10 + 7 * breathe, 4 * wave(t, 3.6)),
			{
				RigHead = R(2 * breathe, 12 * wave(t, 3.6, 0.05), 3 * wave(t, 1.8, 0.2)),
				RigTail = Q.Tail(2 * breathe, 16 * wave(t, 3.6, 0.3)),
			}
		)
	end,
}
-- Rare variant: the cat stretch. The front legs slide out forward, the chest drops, the
-- back end and tail stay up, and it holds there before standing again.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local on = seg(t, 0.05, 0.45) * (1 - seg(t, 1.45, 1.9))
		local reach = math.rad(58 * on)
		-- how far the front hips drop when the front legs lean forward by `reach`; the body
		-- pitches about its back hips by just that much
		local drop = shape.legLength * (1 - math.cos(reach)) - 0.18 * math.sin(reach)
		local pitch = math.deg(math.asin(math.clamp(drop / 1.45, 0, 1)))
		local settle = -shape.backReach * math.sin(math.rad(pitch))
		local quiver = on * wave(t, 0.12)
		return all({
			RigTorso = T(0, settle + 0.01, 0, -pitch, 0, 0),
			RigFrontRightLeg = R(58 * on + pitch),
			RigFrontLeftLeg = R(58 * on + pitch),
			RigBackRightLeg = R(pitch),
			RigBackLeftLeg = R(pitch),
			RigHead = R(pitch + 5 * on, 0, 0),
			RigTail = Q.Tail(30 * on, 6 * quiver),
		}, knees(0, 0, 0, 0), fins(22 * on + 5 * quiver, 22 * on - 5 * quiver, 0))
	end,
}
-- The walk: a brisk human-legged trot under a body that swims. The fish wiggles from side
-- to side with every stride, the tail sweeps the other way and the fins paddle.
set.Walk = {
	name = "Walk",
	length = 0.7,
	loop = true,
	priority = "Movement",
	speed = shape.walkSpeed,
	pose = function(t: number): Poses
		local s = wave(t, 0.7)
		local lift = wave(t, 0.7, 0.2) -- positive while front right and back left swing forward
		local a, b = math.max(0, lift), math.max(0, -lift)
		return all(
			Q.Stance(
				shape,
				{ 26 * s, -26 * s, -26 * s, 26 * s },
				0,
				1.2 * wave(t, 0.35),
				2 * s,
				0.03,
				7 * s
			),
			knees(46 * a, 46 * b, 46 * b, 46 * a),
			fins(18 + 14 * s, 18 - 14 * s, -8 * s),
			{
				RigHead = R(2 + 2 * wave(t, 0.35), -6 * s, 0),
				RigTail = Q.Tail(4, -30 * s),
			}
		)
	end,
}
-- The dash: legs flying, the whole fish thrashing as if it were swimming flat out.
set.Run = {
	name = "Run",
	length = 0.34,
	loop = true,
	priority = "Movement",
	speed = shape.runSpeed,
	pose = function(t: number): Poses
		local s = wave(t, 0.34)
		local lift = wave(t, 0.34, 0.2)
		local a, b = math.max(0, lift), math.max(0, -lift)
		return all(
			Q.Stance(
				shape,
				{ 40 * s, -40 * s, -40 * s, 40 * s },
				0,
				-3 + 2 * wave(t, 0.17),
				3 * s,
				0.08 + 0.08 * math.abs(s),
				9 * s
			),
			knees(62 * a, 62 * b, 62 * b, 62 * a),
			fins(40 + 12 * s, 40 - 12 * s, -12 * s),
			{
				RigHead = R(5 + 2 * wave(t, 0.17), -8 * s, 0),
				RigTail = Q.Tail(8, -44 * s),
			}
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
		return all(
			Q.Stance(shape, { 0, 0, 0, 0 }, 6 * air, 3 * up, 0, 0.14 * air),
			knees(0, 0, 0, 0),
			fins(62 * air, 62 * air, 0),
			{
				RigHead = R(8 * up, 0, 0),
				RigTail = Q.Tail(40 * up, 0),
			}
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
		return all(
			Q.Stance(shape, { 0, 0, 0, 0 }, 10 * hit, 3 * hit, 7 * hit, 0),
			knees(0, 0, 14 * hit, 0),
			fins(44 * hit, 20 * hit, 14 * hit),
			{
				RigHead = R(-8 * hit, 8 * hit, 8 * hit),
				RigTail = Q.Tail(15 * hit, -30 * hit),
			}
		)
	end,
}
-- Carried: a landed fish. The tail flaps hard, the fins beat and the legs pedal.
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local k = wave(t, 0.25)
		local flap = wave(t, 0.5)
		return all(
			Q.Stance(
				shape,
				{ 30 * k, -30 * k, -30 * k, 30 * k },
				8,
				2 * flap,
				4 * wave(t, 1.0),
				0,
				6 * flap
			),
			knees(32 + 20 * k, 32 - 20 * k, 32 - 20 * k, 32 + 20 * k),
			fins(34 + 26 * k, 34 - 26 * k, 8 * flap),
			{
				RigHead = R(4 * flap, 10 * wave(t, 1.0, 0.1), 6 * wave(t, 0.5, 0.25)),
				RigTail = Q.Tail(6, 42 * flap),
			}
		)
	end,
}
-- Asleep as a cat loaf: all four legs folded under the fish, the head settled low, the tail
-- curled round to one side and the dorsal fin laid over.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		-- over-lowered on purpose: the floor clamp raises it until the folded legs rest
		return all({
			RigTorso = T(0, -0.9 + 0.015 * breathe, 0, 0, 0, 0),
			RigFrontRightLeg = R(56),
			RigFrontLeftLeg = R(56),
			RigBackRightLeg = R(56),
			RigBackLeftLeg = R(56),
			RigHead = R(-4 + breathe, 0, 5),
			RigTail = Q.Tail(0, 52 + 2 * breathe),
		}, knees(142, 142, 142, 142), fins(6 + 3 * breathe, 6 + 3 * breathe, 22))
	end,
}
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
		local tuck = 26 * air
		return all(
			Q.Stance(
				shape,
				{ tuck, tuck, -tuck, -tuck },
				14 * crouch + 8 * land,
				5 * air,
				0,
				shape.jump * air,
				360 * spin
			),
			knees(50 * air, 50 * air, 50 * air, 50 * air),
			fins(80 * air + 14 * land, 80 * air + 14 * land, 0),
			{
				RigHead = R(8 * air - 4 * land, 0, 0),
				RigTail = Q.Tail(30 * air + 8 * land, 34 * wave(t, 0.2) * air),
			}
		)
	end,
}
-- Signature: the swim. It forgets it has legs: the fish swims on the spot, body snaking,
-- tail beating and fins paddling while the feet patter underneath and the cat head stays
-- dead level; then a small hop with both fins flung out.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local on = seg(t, 0.05, 0.25) * (1 - seg(t, 1.12, 1.3))
		local swim = on * wave(t - 0.25, 0.3)
		local patter = on * wave(t - 0.25, 0.15)
		local air = bump(t, 1.26, 1.56)
		local a, b = math.max(0, patter), math.max(0, -patter)
		return all(
			Q.Stance(
				shape,
				{ 12 * patter, -12 * patter, -12 * patter, 12 * patter },
				4 * air,
				2 * on + 3 * air,
				3 * swim,
				0.04 * on + 0.34 * air,
				13 * swim
			),
			knees(30 * a + 20 * air, 30 * b + 20 * air, 30 * b + 20 * air, 30 * a + 20 * air),
			fins(38 * on + 26 * patter + 70 * air, 38 * on - 26 * patter + 70 * air, -14 * swim),
			{
				RigHead = R(3 * on + 5 * air, -13 * swim, -3 * swim),
				RigTail = Q.Tail(10 * on + 24 * air, -50 * swim),
			}
		)
	end,
}

return Q.Finish(set)
