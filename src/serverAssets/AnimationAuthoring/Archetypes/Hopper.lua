--!strict
-- Hopper base set (rig + animation brief v5, B.1/B.3): squat creatures that travel by
-- hopping. Bones: RigTorso, RigHead, RigRightLeg, RigLeftLeg (hind legs), RigRightArm,
-- RigLeftArm (front limbs). A species file calls Build(shape) and replaces or tunes clips.
-- Bake hoppers through AnimationBaker.GroundedSet: the belly sits on the ground, so the
-- floor clamp supplies whatever lift a pose needs. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head UP at the front and
-- lifts an arm forward; -rx kicks a hind leg back; +ry turns left.
local Q = require(script.Parent.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

local Hopper = {}

export type Shape = {
	walkSpeed: number,
	runSpeed: number,
	hop: number, -- height of a travelling hop, design units
	leap: number, -- height of a fleeing leap
	jump: number, -- Celebrate jump height
}

type Poses = { [string]: CFrame }

-- One hop: `air` is 0 on the ground and 1 at the top; `rise` is +1 going up, -1 coming down.
local function hopPose(
	height: number,
	air: number,
	rise: number,
	kick: number,
	reach: number
): Poses
	return {
		RigTorso = T(0, height * air, 0, 9 * rise * air, 0, 0),
		RigHead = R(-5 * rise * air, 0, 0),
		RigRightLeg = R(-kick * air),
		RigLeftLeg = R(-kick * air),
		RigRightArm = R(reach * air),
		RigLeftArm = R(reach * air),
	}
end

function Hopper.Build(shape: Shape): { [string]: any }
	local set: { [string]: any } = {}
	local function cycle(t: number, period: number): (number, number)
		-- 30% of each hop is spent on the ground, the rest in the air
		local phase = (t / period) % 1
		local x = math.clamp((phase - 0.3) / 0.7, 0, 1)
		return math.sin(x * math.pi), math.cos(x * math.pi)
	end

	set.IdleDisplay = {
		name = "IdleDisplay",
		length = 3.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local air = bump(t % 1.5, 0.9, 1.4)
			local pat = wave(t, 0.5)
			return {
				RigTorso = T(0, 0.55 * air, 0, 5 + 3 * air, 0, 2 * wave(t, 3.0)),
				RigHead = R(6 + 6 * air, 12 * wave(t, 3.0), 0),
				RigRightLeg = R(-18 * air),
				RigLeftLeg = R(-18 * air),
				RigRightArm = R(26 * math.max(0, pat) + 20 * air),
				RigLeftArm = R(26 * math.max(0, -pat) + 20 * air),
			}
		end,
	}
	set.IdleWild = {
		name = "IdleWild",
		length = 3.6,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 1.8)
			return {
				RigTorso = T(0, 0.03 + 0.03 * breathe, 0, 1 + breathe, 0, 0),
				RigHead = R(2 * breathe, 16 * wave(t, 3.6, 0.05), 3 * wave(t, 1.8, 0.2)),
				RigRightArm = R(3 * math.max(0, breathe)),
				RigLeftArm = R(3 * math.max(0, breathe)),
			}
		end,
	}
	-- Rare variant: a sudden lunge at a passing fly, then a satisfied settle.
	set.IdleWild2 = {
		name = "IdleWild2",
		length = 2.0,
		loop = false,
		priority = "Idle",
		pose = function(t: number): Poses
			local watch = seg(t, 0, 0.5) * (1 - seg(t, 0.6, 0.7))
			local lunge = snap(t, 0.62, 0.78) * (1 - seg(t, 0.95, 1.3))
			local chew = seg(t, 1.2, 1.35) * (1 - seg(t, 1.8, 2.0))
			return {
				RigTorso = T(0, 0.25 * lunge, -0.7 * lunge, 6 * lunge - 2 * watch, 0, 0),
				RigHead = R(10 * watch + 16 * lunge + 4 * chew * wave(t, 0.22), 14 * watch, 0),
				RigRightLeg = R(-14 * lunge),
				RigLeftLeg = R(-14 * lunge),
				RigRightArm = R(18 * lunge),
				RigLeftArm = R(18 * lunge),
			}
		end,
	}
	set.Walk = {
		name = "Walk",
		length = 0.62,
		loop = true,
		priority = "Movement",
		speed = shape.walkSpeed,
		pose = function(t: number): Poses
			local air, rise = cycle(t, 0.62)
			return hopPose(shape.hop, air, rise, 32, 28)
		end,
	}
	set.Run = {
		name = "Run",
		length = 0.44,
		loop = true,
		priority = "Movement",
		speed = shape.runSpeed,
		pose = function(t: number): Poses
			local air, rise = cycle(t, 0.44)
			local poses = hopPose(shape.leap, air, rise, 52, 46)
			poses.RigTorso = poses.RigTorso * R(4 * rise * air)
			return poses
		end,
	}
	set.Alert = {
		name = "Alert",
		length = 0.4,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local air = bump(t, 0.06, 0.36)
			local up = snap(t, 0.06, 0.24)
			return {
				RigTorso = T(0, 0.5 * air, 0, 8 * up, 0, 0),
				RigHead = R(14 * up, 0, 0),
				RigRightLeg = R(-16 * air),
				RigLeftLeg = R(-16 * air),
				RigRightArm = R(34 * up),
				RigLeftArm = R(34 * up),
			}
		end,
	}
	set.Hit = {
		name = "Hit",
		length = 0.25,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
			return {
				RigTorso = T(0, 0.2 * hit, 0.15 * hit, 4 * hit, 0, 9 * hit),
				RigHead = R(-10 * hit, 8 * hit, 10 * hit),
				RigRightArm = R(30 * hit),
				RigLeftArm = R(12 * hit),
			}
		end,
	}
	set.Carried = {
		name = "Carried",
		length = 1.0,
		loop = true,
		priority = "Movement",
		pose = function(t: number): Poses
			local k = wave(t, 0.25)
			return {
				RigTorso = R(2 * wave(t, 0.5), 5 * wave(t, 0.5), 4 * wave(t, 1.0)),
				RigHead = R(6 * wave(t, 0.5), 12 * wave(t, 1.0, 0.1), 0),
				RigRightLeg = R(-22 - 22 * k),
				RigLeftLeg = R(-22 + 22 * k),
				RigRightArm = R(30 + 26 * k),
				RigLeftArm = R(30 - 26 * k),
			}
		end,
	}
	set.Sleep = {
		name = "Sleep",
		length = 4.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 4.0)
			return {
				RigTorso = T(0, 0.03 + 0.03 * breathe, 0, 0.8 * breathe, 0, 0),
				RigHead = R(-5 + breathe, 0, 4),
				RigRightArm = R(0, 0, 10),
				RigLeftArm = R(0, 0, -10),
			}
		end,
	}
	set.Celebrate = {
		name = "Celebrate",
		length = 1.2,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local air = bump(t, 0.18, 0.92)
			local spin = seg(t, 0.22, 0.88)
			local land = bump(t, 0.9, 1.2)
			return {
				RigTorso = T(0, shape.jump * air, 0, 6 * air, 360 * spin, 0),
				RigHead = R(14 * air - 6 * land, 0, 0),
				RigRightLeg = R(-40 * air),
				RigLeftLeg = R(-40 * air),
				RigRightArm = R(60 * air + 14 * land),
				RigLeftArm = R(60 * air + 14 * land),
			}
		end,
	}
	return set
end

Hopper.Finish = Q.Finish

return table.freeze(Hopper)
