--!strict
-- Giraffa Celeste (BRT_023): authored animation set. Archetype: Biped with knees (a round
-- half-watermelon on two short booted legs), on the high-energy biped base set
-- (Archetypes/BipedHype.lua).
-- Bones: RigTorso (the watermelon, cut face forward, with its stars), RigHead (the giraffe
-- head in its big chrome astronaut helmet, antenna and lamp), RigRightLeg >
-- RigRightLowerLeg, RigLeftLeg > RigLeftLowerLeg (each lower leg carries the tall work
-- boot).
-- The meme: a giraffe astronaut who lives in a watermelon. Everything floats a little.
-- Reused: IdleWild, IdleWild2, Walk, Run, Alert, Hit, Carried, Sleep and Celebrate are the
-- high-energy base clips, with half-size head turns so the helmet stays in the melon. Her
-- own: IdleDisplay (stargazing) and the Signature (the zero-gravity space walk).
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head back and swings a leg
-- forward; a knee bends with -rx on the lower leg; +ry turns left.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Biped = require(script.Parent.Parent.Archetypes.Biped)
local Hype = require(script.Parent.Parent.Archetypes.BipedHype)
local R, T, wave, seg, bump = Q.R, Q.T, Q.wave, Q.seg, Q.bump

type Poses = { [string]: CFrame }

local shape: Biped.Shape = {
	legLength = 0.92,
	toeReach = 0.52,
	heelReach = 0.25,
	footHalfWidth = 0.23,
	walkSpeed = 6.6, -- Rare: same as the Uncommons
	runSpeed = 11,
	jump = 1.3,
}

-- the helmet sits down inside the melon: half-size head turns keep it there
local set = Hype.Build(shape, { head = 0.5 })

-- Banked: stargazing. She bobs on her boots and tips the helmet up to look at the sky, side to
-- side, then gives a little excited double bounce.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local look = wave(t, 3.0)
		local bounce = bump(t, 2.1, 2.4) + bump(t, 2.4, 2.7)
		local bob = math.abs(wave(t, 1.0))
		local knee = 24 * bounce + 8 * (1 - bob)
		return Q.With(
			Biped.Stance(
				shape,
				0,
				0,
				0,
				4 + 4 * bob,
				3 * look,
				0.35 * bounce + 0.08 * bob - 0.1 * (1 - bob) - 0.05,
				8 * look
			),
			{
				RigHead = R(4 + 3 * bob, 10 * look, -3 * look),
				RigRightLowerLeg = R(-knee),
				RigLeftLowerLeg = R(-knee),
			}
		)
	end,
}

-- Signature: the space walk. Three slow, floaty moon-hops, higher each time, legs paddling in
-- the air; at the top of the last one she does a slow-motion somersault, lands with a deep
-- knee bend and pops up with the helmet tipped back.
set.Signature = {
	name = "Signature",
	length = 2.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local h1 = bump(t, 0.05, 0.55)
		local h2 = bump(t, 0.55, 1.1)
		local h3 = bump(t, 1.1, 2.0)
		local air = math.max(h1, h2, h3)
		local flip = seg(t, 1.3, 1.85)
		local land = bump(t, 1.95, 2.3)
		local paddle = wave(t, 0.4) * air
		local lift = 0.7 * h1 + 1.1 * h2 + 2.6 * h3 - 0.1 * land
		local knee = 30 * air + 50 * land
		return {
			RigTorso = T(0, lift, 0, -360 * flip, 6 * paddle, 4 * paddle),
			RigHead = R(10 * air - 8 * land + 18 * seg(t, 2.1, 2.3), 10 * paddle, 0),
			RigRightLeg = R(20 * paddle + 20 * land),
			RigLeftLeg = R(-20 * paddle + 20 * land),
			RigRightLowerLeg = R(-knee - 20 * math.max(0, paddle)),
			RigLeftLowerLeg = R(-knee - 20 * math.max(0, -paddle)),
		}
	end,
}

return Q.Finish(set)
