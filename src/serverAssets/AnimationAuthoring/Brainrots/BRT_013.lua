--!strict
-- Cavallo Virtuoso (BRT_013): authored animation set. Archetype: Biped.
-- Bones: RigTorso (the piano), RigNeck, RigHead, RigRightLeg, RigLeftLeg, RigTail.
-- The meme: a handsome, very pleased-with-himself horse wearing a grand piano and two giant
-- boots. He struts, he poses, he knows you are watching. Edit-time authoring data only.
local Archetypes = script.Parent.Parent.Archetypes
local B = require(Archetypes.Biped)
local Q = require(Archetypes.Quadruped)

local shape: B.Shape = {
	legLength = 1.652,
	toeReach = 0.82,
	heelReach = 0.38,
	footHalfWidth = 0.34,
	walkSpeed = 6.6, -- Uncommon route speed
	runSpeed = 11,
	jump = 1.4,
}

local set = B.Build(shape)

-- Signature: the virtuoso flourish. Two boot stomps in rhythm, then a slow, glorious hair flip.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): { [string]: CFrame }
		local stompR = Q.bump(t, 0.05, 0.3)
		local stompL = Q.bump(t, 0.3, 0.55)
		local flip = Q.seg(t, 0.6, 0.85) * (1 - Q.seg(t, 1.3, 1.6))
		local sweep = Q.seg(t, 0.7, 1.15)
		return Q.With(
			B.Stance(shape, 34 * stompR, 34 * stompL, 0, 3 * flip, 0, 0.06 * (stompR + stompL)),
			{
				RigNeck = Q.R(-6 * (stompR + stompL) + 20 * flip, 0, 0),
				RigHead = Q.R(-10 * flip, Q.mix(-38, 38, sweep) * flip, 10 * flip),
				RigTail = Q.Tail(10 + 40 * flip, 30 * Q.wave(t, 0.25) * flip, 0),
			}
		)
	end,
}

return B.Finish(set)
