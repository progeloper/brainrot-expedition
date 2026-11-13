--!strict
-- Glorbo Fruttodrillo (BRT_011): authored animation set. Archetype: Quadruped.
-- Bones: RigTorso, RigHead, RigFrontRightLeg, RigFrontLeftLeg, RigBackRightLeg,
-- RigBackLeftLeg, RigTail (Config/VoxelCreatures/BRT_011 rig, unchanged).
-- The meme: a smug watermelon crocodile. Low swagger, a lot of tail, a mean grin held high.
-- Edit-time authoring data only.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)

local shape: Q.Shape = {
	legLength = 0.985,
	footReach = 0.45,
	footInner = 0.3,
	frontReach = 1.3,
	backReach = 1.0,
	belly = 0.35,
	walkSpeed = 6.6, -- Uncommon route speed
	runSpeed = 11,
	jump = 1.3,
}

local set = Q.Build(shape)

-- Signature: the crocodile death roll. A hop, one full barrel roll, then two smug chomps.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): { [string]: CFrame }
		local air = Q.bump(t, 0.08, 0.78)
		local roll = Q.seg(t, 0.14, 0.72)
		local chomp = Q.seg(t, 0.85, 0.95) * (1 - Q.seg(t, 1.4, 1.6))
		local nod = chomp * math.abs(Q.wave(t - 0.9, 0.5))
		-- The roll is applied to the torso directly; legs stay rigid with the body.
		return {
			RigTorso = Q.T(0, 1.9 * air, 0, 4 * air, 0, 360 * roll),
			RigFrontRightLeg = Q.R(24 * air),
			RigFrontLeftLeg = Q.R(24 * air),
			RigBackRightLeg = Q.R(-24 * air),
			RigBackLeftLeg = Q.R(-24 * air),
			RigHead = Q.R(10 * air + 22 * nod, 0, 0),
			RigTail = Q.Tail(
				20 * air + 12 * nod,
				40 * Q.wave(t, 0.2) * air + 26 * Q.wave(t, 0.25) * chomp,
				0
			),
		}
	end,
}

return Q.Finish(set)
