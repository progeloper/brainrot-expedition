--!strict
-- Flyer base set (rig + animation brief v5, B.1/B.3): winged creatures that strut on the
-- ground and take to the air to flee. Bones: RigTorso, RigHead, RigRightWing, RigLeftWing,
-- RigTail, RigRightLeg, RigLeftLeg. A species file calls Build(shape) and replaces or tunes
-- clips. Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head UP at the front and
-- swings a leg forward; +ry turns left. Wings: `flap` degrees lifts both tips (positive up).
local Q = require(script.Parent.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

local Flyer = {}

export type Shape = {
	walkSpeed: number,
	flySpeed: number,
	restWings: number, -- how far the wings hang below the spread bind pose when calm, degrees
	flight: number, -- cruising height when fleeing, design units
	jump: number,
}

type Poses = { [string]: CFrame }

-- Both wings: positive `flap` lifts the tips, `sweep` swings them forward.
local function wings(flap: number, sweep: number?): Poses
	return {
		RigRightWing = R(0, -(sweep or 0), flap),
		RigLeftWing = R(0, sweep or 0, -flap),
	}
end
Flyer.Wings = wings
local with = Q.With

function Flyer.Build(shape: Shape): { [string]: any }
	local set: { [string]: any } = {}
	local rest = -shape.restWings

	set.IdleDisplay = {
		name = "IdleDisplay",
		length = 3.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local puff = math.abs(wave(t, 1.5))
			return with(wings(8 + 14 * wave(t, 0.75)), {
				RigTorso = T(0, 0.1 * puff, 0, 7 + 3 * puff, 0, 2 * wave(t, 3.0)),
				RigHead = R(-4 + 6 * puff, 18 * wave(t, 3.0), 0),
				RigTail = Q.Tail(14 + 8 * puff, 12 * wave(t, 0.75), 0),
			})
		end,
	}
	set.IdleWild = {
		name = "IdleWild",
		length = 3.6,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 1.8)
			-- quick bird head turns: hold, then snap to the other side
			local look = if (t / 3.6) % 1 < 0.5
				then seg(t % 1.8, 0, 0.18)
				else 1 - seg(t % 1.8, 0, 0.18)
			return with(wings(rest + 2 * breathe), {
				RigTorso = T(0, 0.02 + 0.02 * breathe, 0, 1, 0, 0),
				RigHead = R(2 * breathe, -26 + 52 * look, 0),
				RigTail = Q.Tail(4, 6 * wave(t, 1.8, 0.3), 0),
			})
		end,
	}
	-- Rare variant: preening under one wing.
	set.IdleWild2 = {
		name = "IdleWild2",
		length = 2.0,
		loop = false,
		priority = "Idle",
		pose = function(t: number): Poses
			local on = seg(t, 0.05, 0.4) * (1 - seg(t, 1.55, 1.95))
			local nibble = on * wave(t, 0.22)
			local poses = wings(rest * (1 - on))
			poses.RigRightWing = R(0, 0, rest * (1 - on) + 26 * on)
			return with(poses, {
				RigTorso = T(0, 0, 0, 0, 0, -5 * on),
				RigHead = R(-12 * on + 4 * nibble, -68 * on, -14 * on),
				RigTail = Q.Tail(6 * on, -10 * on, 0),
			})
		end,
	}
	-- The strut: chest out, head bobbing forward and back with each step.
	set.Walk = {
		name = "Walk",
		length = 0.56,
		loop = true,
		priority = "Movement",
		speed = shape.walkSpeed,
		pose = function(t: number): Poses
			local s = wave(t, 0.56)
			local bob = wave(t, 0.28, 0.15)
			return with(wings(rest + 3 * wave(t, 0.28)), {
				RigTorso = T(0, 0.03 + 0.04 * math.abs(s), 0, 3, 4 * s, 2 * s),
				RigHead = T(0, 0, -0.22 * bob, 3 * bob, -4 * s, 0),
				RigTail = Q.Tail(8, -10 * s, 0),
				RigRightLeg = R(30 * s),
				RigLeftLeg = R(-30 * s),
			})
		end,
	}
	-- Fleeing: airborne, body pitched forward, wings beating, legs tucked back.
	set.Run = {
		name = "Run",
		length = 0.3,
		loop = true,
		priority = "Movement",
		speed = shape.flySpeed,
		pose = function(t: number): Poses
			local beat = wave(t, 0.3)
			return with(wings(34 * beat, 6), {
				RigTorso = T(0, shape.flight - 0.16 * beat, 0, -14, 0, 0),
				RigHead = R(12, 0, 0),
				RigTail = Q.Tail(-6 + 8 * beat, 0, 0),
				RigRightLeg = R(-38),
				RigLeftLeg = R(-38),
			})
		end,
	}
	set.Alert = {
		name = "Alert",
		length = 0.4,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local up = snap(t, 0.06, 0.24)
			local air = bump(t, 0.06, 0.36)
			return with(wings(rest * (1 - up) + 30 * up), {
				RigTorso = T(0, 0.4 * air, 0, 6 * up, 0, 0),
				RigHead = R(10 * up, 0, 0),
				RigTail = Q.Tail(30 * up, 0, 0),
			})
		end,
	}
	set.Hit = {
		name = "Hit",
		length = 0.25,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
			return with(wings(rest * (1 - hit) + 24 * hit), {
				RigTorso = T(0, 0.1 * hit, 0.12 * hit, 8 * hit, 0, 9 * hit),
				RigHead = R(-14 * hit, 10 * hit, 10 * hit),
				RigTail = Q.Tail(24 * hit, -16 * hit, 0),
			})
		end,
	}
	set.Carried = {
		name = "Carried",
		length = 1.0,
		loop = true,
		priority = "Movement",
		pose = function(t: number): Poses
			local k = wave(t, 0.25)
			return with(wings(30 * wave(t, 0.2)), {
				RigTorso = R(3 * wave(t, 0.5), 6 * wave(t, 1.0), 5 * wave(t, 1.0, 0.25)),
				RigHead = R(6 * wave(t, 0.5), 20 * wave(t, 1.0, 0.1), 0),
				RigTail = Q.Tail(10, 20 * wave(t, 0.5), 0),
				RigRightLeg = R(28 * k),
				RigLeftLeg = R(-28 * k),
			})
		end,
	}
	-- Roosting: wings hanging, head tucked to one side.
	set.Sleep = {
		name = "Sleep",
		length = 4.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 4.0)
			return with(wings(rest - 12 + 2 * breathe), {
				RigTorso = T(0, 0.02 + 0.02 * breathe, 0, -3, 0, 2),
				RigHead = R(-14 + breathe, 34, 10),
				RigTail = Q.Tail(-4, 0, 0),
			})
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
			return with(wings(rest * (1 - air) + 30 * wave(t, 0.2) * air), {
				RigTorso = T(0, shape.jump * air, 0, 5 * air, 360 * spin, 0),
				RigHead = R(12 * air, 0, 0),
				RigTail = Q.Tail(30 * air, 0, 0),
				RigRightLeg = R(-24 * air),
				RigLeftLeg = R(-24 * air),
			})
		end,
	}
	return set
end

Flyer.Finish = Q.Finish

return table.freeze(Flyer)
