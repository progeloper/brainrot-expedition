--!strict
-- La Vaca Saturno Saturnita (BRT_032): authored animation set. Archetype: Biped (a planet on
-- two human legs), on the high-energy biped base set (Archetypes/BipedHype.lua).
-- Bones: RigTorso (the banded planet with its ring, moon, star and cowbell), RigHead (the
-- cow head peeking out of the top front), RigRightLeg / RigLeftLeg (each human leg with its
-- huge bare foot and five toes), RigTail.
-- The meme: Saturn as a cow, padding about on two enormous bare feet with pedicured toes.
-- Reused: IdleWild, IdleWild2, Walk, Run, Alert, Hit, Carried, Sleep and Celebrate are the
-- high-energy base clips (she has no knees or arms, so those parts of them drop out). Her
-- own: IdleDisplay (the toe-tap strut) and the Signature (the cosmic stomp).
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the planet or head back and swings a leg
-- forward; +ry turns left; Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Biped = require(script.Parent.Parent.Archetypes.Biped)
local Hype = require(script.Parent.Parent.Archetypes.BipedHype)
local R, wave, seg, bump = Q.R, Q.wave, Q.seg, Q.bump

type Poses = { [string]: CFrame }

local shape: Biped.Shape = {
	legLength = 1.04,
	toeReach = 1.17,
	heelReach = 0.42,
	footHalfWidth = 0.36,
	walkSpeed = 6, -- Legendary: same route speed as the Epics
	runSpeed = 10,
	jump = 1.4,
}

local set = Hype.Build(shape)

-- Banked: the strut. She sways the planet from foot to foot, tapping the big toes of each
-- foot in turn, the ring tilting with her and the head bobbing to the beat.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local side = wave(t, 1.5)
		local beat = math.abs(wave(t, 0.75))
		local tapR = math.max(0, wave(t, 0.75)) * math.max(0, side)
		local tapL = math.max(0, -wave(t, 0.75)) * math.max(0, -side)
		return Q.With(
			Biped.Stance(
				shape,
				-10 * tapR,
				-10 * tapL,
				0,
				3 * beat,
				8 * side,
				0.14 * beat - 0.05,
				10 * side
			),
			{
				RigHead = R(6 * beat, 14 * side, -6 * side),
				RigTail = Q.Tail(10 + 10 * beat, 30 * wave(t, 0.75)),
			}
		)
	end,
}

-- Signature: the cosmic stomp. Three big stomps, right, left, right, the planet jolting and
-- the cowbell head nodding on each; then she spins the whole planet round on the spot and
-- throws her head back in a MOO.
set.Signature = {
	name = "Signature",
	length = 1.8,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local stomps = seg(t, 0, 0.06) * (1 - seg(t, 0.84, 0.9))
		local beat = t % 0.28
		local n = math.floor(t / 0.28)
		local raise = stomps * bump(beat, 0, 0.2)
		local jolt = stomps * bump(beat, 0.18, 0.28)
		local right = if n % 2 == 0 then raise else 0
		local left = if n % 2 == 1 then raise else 0
		local spin = seg(t, 0.9, 1.35)
		local hop = bump(t, 0.9, 1.35)
		local moo = bump(t, 1.35, 1.8)
		return Q.With(
			Biped.Stance(
				shape,
				30 * right + 10 * hop,
				30 * left + 10 * hop,
				6 * hop,
				-4 * jolt - 6 * moo,
				8 * (right - left),
				0.35 * raise - 0.05 * jolt + 0.5 * hop,
				360 * spin
			),
			{
				RigHead = R(-12 * jolt + 26 * moo, 0, 0),
				RigTail = Q.Tail(20 * stomps + 50 * hop + 30 * moo, 30 * wave(t, 0.28) * stomps),
			}
		)
	end,
}

return Q.Finish(set)
