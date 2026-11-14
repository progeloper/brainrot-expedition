--!strict
-- La Secret Combinasion (BRT_035, teased): authored animation set. Archetype: Biped (a
-- toilet on two legs, with arms and a phone-headed rider on top), on the high-energy biped
-- base set (Archetypes/BipedHype.lua).
-- Bones: RigTorso (the toilet, its face, tongue, bell and dragon-fruit shell), RigRightLeg /
-- RigLeftLeg (the wooden legs in sneakers), RigRightArm (the white glove), RigLeftArm (the
-- glove holding up the "9" sign), RigPhoneBody (the little wooden body rising out of the
-- tank) and RigPhoneHead (its phone head with the worried face).
-- The meme: every secret brainrot glued together, and it knows it is special.
-- Reused: IdleWild, IdleWild2, Walk, Run, Alert, Hit, Carried, Sleep and Celebrate are the
-- high-energy base clips; the base's neck and head motion drives the phone rider's body and
-- head. Its own: IdleDisplay (sign waving) and the Signature (the 9 reveal).
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body back and swings a leg forward;
-- +ry turns left. The arms stick straight out from shoulders set inside the toilet, so raising
-- or lowering them would bury them in it: they only turn about their own length (rx, which
-- tips the glove and the sign forward or back) and swing forward (+ry on the right).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Biped = require(script.Parent.Parent.Archetypes.Biped)
local Hype = require(script.Parent.Parent.Archetypes.BipedHype)
local Reuse = require(script.Parent.Parent.Archetypes.Reuse)
local R, wave, seg, bump = Q.R, Q.wave, Q.seg, Q.bump

type Poses = { [string]: CFrame }

local shape: Biped.Shape = {
	legLength = 1.9,
	toeReach = 0.98,
	heelReach = 0.65,
	footHalfWidth = 0.42,
	walkSpeed = 6, -- Secret: same route speed as the Epics
	runSpeed = 10,
	jump = 1.4,
}

-- The arms only twist (raising them would bury them in the toilet); the legs take a shorter
-- stride and the toilet tilts less over them, because its hips sit inside the wide bowl.
local set = Reuse.Adapt(
	Hype.Build(shape, {
		raise = 0,
		out = 0,
		walkStride = 0.45,
		runStride = 0.35,
		jumpLegs = 0.4,
		tilt = 0.4,
	}),
	{ rename = { RigNeck = "RigPhoneBody", RigHead = "RigPhoneHead" } }
)

-- Banked: showing off the sign. The "9" sign sways overhead from side to side, the phone rider
-- bops along, and the toilet bounces on its wooden legs.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local side = wave(t, 1.5)
		local beat = math.abs(wave(t, 0.75))
		return Q.With(
			Biped.Stance(shape, 0, 0, 0, 2 * beat, 5 * side, 0.15 * beat - 0.05, 8 * side),
			{
				RigPhoneBody = R(4 * beat, 10 * side, 6 * side),
				RigPhoneHead = R(-6 + 8 * beat, 14 * side, -6 * side),
				RigLeftArm = R(14 * side, 0, -2 * beat),
				RigRightArm = R(16 * wave(t, 0.75), 0, 2 * beat),
			}
		)
	end,
}

-- Signature: the 9 reveal. It crouches, then jumps with the "9" sign thrust up high and pumps
-- it three times while the phone rider spins its head right round; it lands with the free
-- glove pointing at you.
set.Signature = {
	name = "Signature",
	length = 2.0,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local crouch = seg(t, 0, 0.18) * (1 - seg(t, 0.18, 0.28))
		local air = bump(t, 0.24, 0.9)
		local up = seg(t, 0.2, 0.4) * (1 - seg(t, 1.5, 1.9))
		local pump = up * math.max(0, wave(t - 0.4, 0.3))
		local spin = seg(t, 0.45, 1.1)
		local point = seg(t, 1.0, 1.2) * (1 - seg(t, 1.7, 1.95))
		local land = bump(t, 0.88, 1.15)
		return Q.With(
			Biped.Stance(
				shape,
				20 * air,
				-10 * air,
				6 * crouch,
				-4 * crouch + 4 * air,
				0,
				1.2 * air - 0.1 * crouch - 0.02,
				0
			),
			{
				RigPhoneBody = R(-8 * crouch + 6 * pump, 0, 0),
				RigPhoneHead = R(8 * air - 6 * land, 360 * spin, 0),
				RigLeftArm = R(-10 * up + 30 * pump, 0, -4 * up),
				RigRightArm = R(20 * air * (1 - point), 30 * point, 3),
			}
		)
	end,
}

return Q.Finish(set)
