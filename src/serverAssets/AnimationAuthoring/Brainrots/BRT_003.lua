--!strict
-- Cappuccino Capybara (BRT_003): authored animation set. Archetype: Quadruped (no tail).
-- Bones: RigTorso, RigHead, four legs, RigCup (the cappuccino on its head, signature prop).
-- The meme: the chillest animal alive, on its tenth cappuccino. Whatever the body does,
-- the cup stays level: it is being balanced, always, with a little caffeine tremble.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)

local shape: Q.Shape = {
	legLength = 1.04,
	footReach = 0.56,
	footInner = 0.36,
	frontReach = 1.575,
	backReach = 1.225,
	belly = 0.9,
	walkSpeed = 6, -- Common route speed
	runSpeed = 10,
	jump = 1.2,
}

local set = Q.Build(shape)

-- Signature: the near-spill. A big caffeinated shiver runs through it, the head dips and
-- the cup tips forward, almost over, then snaps back level, followed by a relieved wobble.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	spill = function(t: number): number
		return Q.snap(t, 0.5, 0.75) * (1 - Q.snap(t, 0.95, 1.1))
	end,
	pose = function(t: number): { [string]: CFrame }
		local shiver = Q.seg(t, 0, 0.1) * (1 - Q.seg(t, 0.4, 0.5))
		local dip = Q.snap(t, 0.5, 0.75) * (1 - Q.seg(t, 0.95, 1.15))
		local relief = Q.seg(t, 1.1, 1.2) * (1 - Q.seg(t, 1.45, 1.6))
		return Q.With(
			Q.Stance(shape, { 0, 0, 0, 0 }, 6 * dip, -2 * dip, 3 * shiver * Q.wave(t, 0.08), 0),
			{
				RigHead = Q.R(
					-20 * dip + 6 * relief,
					0,
					4 * shiver * Q.wave(t, 0.08) + 5 * relief * Q.wave(t, 0.2)
				),
			}
		)
	end,
}

-- The cup is balanced against the head and body in every clip: it takes most of their
-- tilt back out, lags a little, and trembles. In the Signature it is allowed to tip.
local function balanced(definition: any): any
	local copy = table.clone(definition)
	copy.pose = function(t: number): { [string]: CFrame }
		local poses = definition.pose(t)
		local hx, _, hz = (poses.RigHead or CFrame.identity):ToEulerAnglesXYZ()
		local tx, _, tz = (poses.RigTorso or CFrame.identity):ToEulerAnglesXYZ()
		local keep = 0.75
		local spill = if definition.spill then definition.spill(t) else 0
		local tremble = math.rad(1.6)
			* Q.wave(t, definition.length / math.max(1, math.round(definition.length / 0.2)))
		poses.RigCup = CFrame.Angles(
			-(hx + tx) * keep * (1 - spill) - math.rad(22) * spill,
			0,
			-(hz + tz) * keep + tremble
		)
		return poses
	end
	return copy
end

for name, definition in set do
	set[name] = balanced(definition)
end

return Q.Finish(set)
