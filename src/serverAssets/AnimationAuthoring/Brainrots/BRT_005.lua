--!strict
-- Bombardiro Pigeon (BRT_005): authored animation set. Archetype: Flyer.
-- Bones: RigTorso, RigHead, RigRightWing, RigLeftWing, RigTail (with the afterburner),
-- RigRightLeg, RigLeftLeg (Config/VoxelCreatures/BRT_005 rig, unchanged).
-- The meme: a plump city pigeon in bomber-jet colours who believes he is military aviation.
-- He struts like a pigeon and flies like a sortie.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
local Archetypes = script.Parent.Parent.Archetypes
local F = require(Archetypes.Flyer)
local Q = require(Archetypes.Quadruped)

local shape: F.Shape = {
	walkSpeed = 6, -- Common route speed
	flySpeed = 10,
	restWings = 58,
	flight = 1.3,
	jump = 1.5,
}

local set = F.Build(shape)

-- Signature: the bombing run. Scramble into the air, bank hard one way and then the other
-- with the wings locked out like a jet, nose down into the dive, then pull up and land.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): { [string]: CFrame }
		local air = Q.bump(t, 0.05, 1.5)
		local sortie = Q.seg(t, 0.2, 0.35) * (1 - Q.seg(t, 1.2, 1.4))
		local bank = Q.wave(t - 0.2, 1.0) * sortie
		local dive = Q.bump(t, 0.7, 1.25)
		local scramble = (1 - sortie) * air
		local poses =
			F.Wings(-58 * (1 - air) + 30 * Q.wave(t, 0.16) * scramble + 6 * sortie, 10 * sortie)
		return Q.With(poses, {
			RigTorso = Q.T(0, 1.9 * air - 0.5 * dive, 0, -6 * sortie - 16 * dive, 0, 24 * bank),
			RigHead = Q.R(8 * sortie + 12 * dive, 0, -14 * bank),
			RigTail = Q.Tail(-8 * sortie + 14 * Q.wave(t, 0.12) * sortie, 0, 0),
			RigRightLeg = Q.R(-34 * air),
			RigLeftLeg = Q.R(-34 * air),
		})
	end,
}

return F.Finish(set)
