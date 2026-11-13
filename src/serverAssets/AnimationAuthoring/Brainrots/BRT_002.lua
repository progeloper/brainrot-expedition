--!strict
-- Tralalero Toad (BRT_002): authored animation set. Archetype: Hopper.
-- Bones: RigTorso, RigHead, RigRightLeg, RigLeftLeg (hind legs), RigRightArm, RigLeftArm
-- (Config/VoxelCreatures/BRT_002 rig, unchanged).
-- The meme: a squat, grinning toad who cannot stop singing. He travels in hops and
-- performs whenever he stops. Bake through AnimationBaker.GroundedSet.
-- Edit-time authoring data only.
local Archetypes = script.Parent.Parent.Archetypes
local H = require(Archetypes.Hopper)
local Q = require(Archetypes.Quadruped)

local shape: H.Shape = {
	walkSpeed = 6, -- Common route speed
	runSpeed = 10,
	hop = 0.7,
	leap = 1.25,
	jump = 1.5,
}

local set = H.Build(shape)

-- Signature: the tra-la-le-ro. Four croaks on the beat, rocking side to side with the head
-- thrown back and the front feet conducting, then one big finishing hop.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): { [string]: CFrame }
		local sing = Q.seg(t, 0, 0.08) * (1 - Q.seg(t, 1.0, 1.1))
		local beat = Q.wave(t, 0.5)
		local croak = math.abs(Q.wave(t, 0.5)) * sing
		local finish = Q.bump(t, 1.1, 1.55)
		return {
			RigTorso = Q.T(
				0,
				0.12 * croak + 0.9 * finish,
				0,
				6 * croak + 8 * finish,
				0,
				9 * beat * sing
			),
			RigHead = Q.R(18 * croak + 12 * finish, 0, -6 * beat * sing),
			RigRightLeg = Q.R(-30 * finish),
			RigLeftLeg = Q.R(-30 * finish),
			RigRightArm = Q.R(64 * math.max(0, beat) * sing + 50 * finish),
			RigLeftArm = Q.R(64 * math.max(0, -beat) * sing + 50 * finish),
		}
	end,
}

return H.Finish(set)
