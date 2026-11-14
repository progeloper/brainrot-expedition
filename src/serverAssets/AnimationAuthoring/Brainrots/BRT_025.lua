--!strict
-- Salamino Penguino (BRT_025): authored animation set. Archetype: Biped (a penguin on two
-- short legs, with flippers), on the high-energy biped base set (Archetypes/BipedHype.lua).
-- Bones: RigTorso (the white-bellied body), RigHead (the salami head and back of the neck,
-- with the beak, price tag and twine), RigRightArm / RigLeftArm (the flippers), RigRightLeg
-- / RigLeftLeg (each short leg with its orange sneaker), RigTail.
-- The meme: a grumpy salami penguin. Short legs, big waddle, flippers that never stop.
-- Reused: IdleWild, IdleWild2, Alert, Hit, Carried, Sleep and Celebrate are the high-energy
-- base clips, the flippers taking the arm swings and the stub tail half-size moves. His own:
-- IdleDisplay (the grump), Walk and Run (the waddle and the flipper sprint) and the
-- Signature (the belly slide).
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head back and swings a leg or
-- flipper forward; +ry turns left; the right flipper flares out with +rz, the left with -rz;
-- Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Biped = require(script.Parent.Parent.Archetypes.Biped)
local Hype = require(script.Parent.Parent.Archetypes.BipedHype)
local R, T, wave, seg, bump = Q.R, Q.T, Q.wave, Q.seg, Q.bump

type Poses = { [string]: CFrame }

local shape: Biped.Shape = {
	legLength = 0.52,
	toeReach = 0.82,
	heelReach = 0.33,
	footHalfWidth = 0.28,
	walkSpeed = 6.6, -- Rare: same as the Uncommons
	runSpeed = 11,
	jump = 1.2,
}

-- his tail is a stub under the body and his flippers sit close to his big head: half-size tail
-- moves and head turns, and smaller flipper raises, keep them all clear
local set = Hype.Build(shape, { tail = 0.5, out = 10, raise = 0.4, head = 0.5 })

-- Banked: the grump. Arms folded as far as flippers fold, he taps one foot, huffs with a
-- flipper flick, and turns his beak away.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local tap = math.max(0, wave(t, 0.5)) * (1 - seg(t, 1.8, 2.0))
		local huff = bump(t, 2.0, 2.5)
		local turn = seg(t, 2.3, 2.6) * (1 - seg(t, 2.8, 3.0))
		return Q.With(Biped.Stance(shape, -12 * tap, 0, 0, -3 * huff, 0, 0.12 * huff - 0.02, 0), {
			RigHead = R(-6 + 12 * huff, -30 * turn, 0),
			RigTail = Q.Tail(10 * tap + 30 * huff, 0),
			RigRightArm = R(0, 0, 6 + 40 * huff),
			RigLeftArm = R(0, 0, -6 - 40 * huff),
		})
	end,
}

-- The waddle: short stiff steps with the whole body rocking from foot to foot and the
-- flippers held out for balance.
set.Walk = {
	name = "Walk",
	length = 0.6,
	loop = true,
	priority = "Movement",
	speed = shape.walkSpeed,
	pose = function(t: number): Poses
		local s = wave(t, 0.6)
		local bob = math.abs(s)
		return Q.With(
			Biped.Stance(shape, 16 * s, -16 * s, 0, -3, 12 * s, 0.06 * bob - 0.02, 6 * s),
			{
				RigHead = R(4, -5 * s, -6 * s),
				RigTail = Q.Tail(10, -26 * s),
				RigRightArm = R(0, 0, 24 + 10 * s),
				RigLeftArm = R(0, 0, -24 + 10 * s),
			}
		)
	end,
}

-- The sprint: leaning right in, little legs a blur, flippers flapping hard.
set.Run = {
	name = "Run",
	length = 0.3,
	loop = true,
	priority = "Movement",
	speed = shape.runSpeed,
	pose = function(t: number): Poses
		local s = wave(t, 0.3)
		local flap = wave(t, 0.15)
		return Q.With(
			Biped.Stance(shape, 16 * s, -16 * s, 0, -6, 8 * s, 0.1 * math.abs(s) - 0.08, 5 * s),
			{
				RigHead = R(5, -3 * s, 0),
				RigTail = Q.Tail(14, -16 * s),
				RigRightArm = R(-20, 0, 50 + 30 * flap),
				RigLeftArm = R(-20, 0, -50 - 30 * flap),
			}
		)
	end,
}

-- Signature: the belly slide. He winds up with the flippers back, flops forward onto his white
-- belly and toboggans forward with his feet kicking, then hops back up onto his feet (and
-- back to his spot, since his position never moves) and throws both flippers out: ta-da.
set.Signature = {
	name = "Signature",
	length = 2.0,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local wind = seg(t, 0, 0.25) * (1 - seg(t, 0.25, 0.35))
		local down = seg(t, 0.3, 0.5) * (1 - seg(t, 1.35, 1.6))
		local slide = seg(t, 0.45, 1.35)
		local kick = wave(t, 0.2) * down
		local tada = bump(t, 1.55, 2.0)
		local hop = bump(t, 1.45, 1.7)
		return {
			RigTorso = T(
				0,
				0.3 * hop - 2 * down,
				-1.2 * slide * (1 - seg(t, 1.45, 1.75)),
				-84 * down + 6 * wind,
				0,
				6 * tada * wave(t, 0.25)
			),
			RigHead = R(-10 * wind + 26 * down - 6 * tada, 0, 0),
			RigTail = Q.Tail(10 * down + 14 * tada, 14 * kick),
			RigRightLeg = R(-20 * down + 20 * kick),
			RigLeftLeg = R(-20 * down - 20 * kick),
			RigRightArm = R(-60 * wind - 70 * down, 0, 10 + 20 * down + 80 * tada),
			RigLeftArm = R(-60 * wind - 70 * down, 0, -10 - 20 * down - 80 * tada),
		}
	end,
}

return Q.Finish(set)
