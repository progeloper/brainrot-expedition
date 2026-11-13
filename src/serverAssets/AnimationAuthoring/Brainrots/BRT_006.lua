--!strict
-- Spaghetti Crocodilo (BRT_006): authored animation set. Archetype: Quadruped.
-- Bones: RigTorso, RigHead, four legs, RigTail, RigMeatball (the meatball on top of the
-- spaghetti heap, signature prop).
-- The meme: a low, sly crocodile carrying dinner on its back. It moves like a crocodile;
-- the meatball has its own opinions and bounces a beat behind everything the body does.
-- Bake through AnimationBaker.GroundedSet (the belly is almost on the ground).
-- Edit-time authoring data only.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)

local shape: Q.Shape = {
	legLength = 1.02,
	footReach = 0.56,
	footInner = 0.295,
	frontReach = 0.825,
	backReach = 0.875,
	belly = 0.05,
	walkSpeed = 6, -- Common route speed
	runSpeed = 10,
	jump = 1.2,
}

local set = Q.Build(shape)

-- Signature: the sneeze. The head rears back, snaps forward, and the meatball is launched
-- off the heap, tumbles once in the air and lands back with two small bounces.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	meatball = function(t: number): CFrame
		local flight = Q.bump(t, 0.42, 1.05)
		local spin = Q.seg(t, 0.42, 1.05)
		local settle = Q.seg(t, 1.05, 1.1) * (1 - Q.seg(t, 1.1, 1.5))
		return Q.T(
			0,
			1.7 * flight + 0.16 * math.abs(Q.wave(t - 1.05, 0.3)) * settle,
			0,
			-360 * spin,
			0,
			0
		)
	end,
	pose = function(t: number): { [string]: CFrame }
		local rear = Q.seg(t, 0, 0.3) * (1 - Q.seg(t, 0.32, 0.42))
		local sneeze = Q.snap(t, 0.34, 0.46) * (1 - Q.seg(t, 0.7, 1.0))
		return Q.With(Q.Stance(shape, { 0, 0, 0, 0 }, 8 * sneeze, 3 * rear - 3 * sneeze, 0, 0), {
			RigHead = Q.R(22 * rear - 16 * sneeze, 0, 0),
			RigTail = Q.Tail(10 * rear + 26 * sneeze, 24 * Q.wave(t, 0.18) * sneeze, 0),
		})
	end,
}

-- Per-clip meatball bounce: { height, period } in design units and seconds.
local BOUNCE: { [string]: { number } } = {
	IdleDisplay = { 0.22, 1.5 },
	IdleWild = { 0.03, 1.8 },
	IdleWild2 = { 0.1, 0.5 },
	Walk = { 0.09, 0.35 },
	Run = { 0.28, 0.17 },
	Carried = { 0.2, 0.25 },
	Sleep = { 0.02, 2.0 },
}

local function withMeatball(definition: any): any
	local copy = table.clone(definition)
	local bounce = BOUNCE[definition.name]
	copy.pose = function(t: number): { [string]: CFrame }
		local poses = definition.pose(t)
		if definition.meatball then
			poses.RigMeatball = definition.meatball(t)
		elseif bounce then
			-- a beat behind the body, with a slight roll
			local hop = math.abs(Q.wave(t, bounce[2] * 2, 0.12))
			poses.RigMeatball = Q.T(0, bounce[1] * hop, 0, 0, 0, 5 * Q.wave(t, bounce[2] * 2, 0.12))
		else
			-- one-shots: it pops up once and drops back
			local pop = Q.bump(t, 0.1 * definition.length, 0.75 * definition.length)
			poses.RigMeatball = Q.T(0, 0.45 * pop, 0, 0, 0, 8 * pop)
		end
		return poses
	end
	return copy
end

for name, definition in set do
	set[name] = withMeatball(definition)
end

return Q.Finish(set)
