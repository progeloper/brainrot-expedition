--!strict
-- Bingus Baguette (BRT_001): authored animation set. Archetype: Quadruped.
-- Bones: RigTorso (the loaf), RigHead, four legs, RigTail (Config/VoxelCreatures/BRT_001
-- rig, unchanged).
-- The meme: Bingus, the hairless sphynx cat, who is also a baguette. Long, low and
-- unbothered; an upright tail that sways; cat things done with a loaf for a body.
-- Edit-time authoring data only.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)

local shape: Q.Shape = {
	legLength = 1.04,
	footReach = 0.42,
	footInner = 0.29,
	frontReach = 1.9,
	backReach = 2.0,
	belly = 0.96,
	walkSpeed = 6, -- Common route speed
	runSpeed = 10.8, -- Sprinter burst
	jump = 1.3,
	tailUpright = true,
}

local set = Q.Build(shape)

-- Signature: making biscuits. Six kneading presses with the front paws, a happy wiggle,
-- then the long cat stretch: chest down, rump up, head lifted.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): { [string]: CFrame }
		local knead = Q.seg(t, 0, 0.1) * (1 - Q.seg(t, 0.9, 1.0))
		local press = Q.wave(t, 0.3)
		local stretch = Q.seg(t, 1.0, 1.2) * (1 - Q.seg(t, 1.45, 1.6))
		local right = 26 * math.max(0, press) * knead
		local left = 26 * math.max(0, -press) * knead
		return Q.With(
			Q.Stance(shape, { right, left, 0, 0 }, 0, -6 * stretch, 2.5 * press * knead, 0),
			{
				RigHead = Q.R(
					-6 * knead + 6 * math.abs(press) * knead + 22 * stretch,
					0,
					5 * press * knead
				),
				RigTail = Q.R(
					8 * stretch,
					0,
					-(16 * press * knead + 10 * Q.wave(t, 0.2) * stretch)
				),
			}
		)
	end,
}

return Q.Finish(set)
