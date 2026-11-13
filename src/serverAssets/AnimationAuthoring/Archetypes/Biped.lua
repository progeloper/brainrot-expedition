--!strict
-- Biped base set (rig + animation brief v5, B.1/B.3). Bones: RigTorso, RigNeck, RigHead,
-- RigRightLeg, RigLeftLeg, RigTail. A species file calls Build(shape) and then replaces or
-- tunes individual clips, so each species still gets its own review. Edit-time data only.
--
-- Convention (model faces -Z, right is +X): +rx swings a leg forward and tips the body,
-- neck or head UP and back; +ry turns left. Use Tail(up, side) for the tail.
local Q = require(script.Parent.Quadruped)
local R, T, wave, mix, seg, snap, bump = Q.R, Q.T, Q.wave, Q.mix, Q.seg, Q.snap, Q.bump

local Biped = {}

export type Shape = {
	legLength: number, -- hip to ground, design units
	toeReach: number, -- how far the foot extends in front of the hip
	heelReach: number, -- how far it extends behind
	footHalfWidth: number, -- half the width of the foot box
	walkSpeed: number,
	runSpeed: number,
	jump: number,
}

type Poses = { [string]: CFrame }

-- Torso + leg poses. The torso is lifted by exactly what the deeper foot would sink.
-- right/left: forward swing in degrees; splay: outward angle for both legs.
function Biped.Stance(
	shape: Shape,
	right: number,
	left: number,
	splay: number,
	pitch: number,
	roll: number,
	lift: number,
	yaw: number?
): Poses
	local need = 0
	for _, angle in { right, left } do
		-- legs counter-rotate the body pitch, so `right`/`left` are the angles they end at
		local a = math.rad(math.abs(angle))
		-- swinging forward tips the heel down; swinging back tips the toe down
		local reach = if angle >= 0 then shape.heelReach else shape.toeReach
		need = math.max(need, reach * math.sin(a) - shape.legLength * (1 - math.cos(a)))
	end
	need += 0.5 * math.sin(math.rad(math.abs(roll))) + shape.footHalfWidth * math.sin(
		math.rad(math.abs(splay))
	) + 0.02
	return {
		RigTorso = T(0, lift + need, 0, pitch, yaw, roll),
		RigRightLeg = R(right - pitch, 0, splay - roll),
		RigLeftLeg = R(left - pitch, 0, -splay - roll),
	}
end

local with = Q.With

function Biped.Build(shape: Shape): { [string]: any }
	local set: { [string]: any } = {}
	set.IdleDisplay = {
		name = "IdleDisplay",
		length = 3.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local bounce = math.abs(wave(t, 1.5))
			local tap = math.max(0, wave(t, 0.75))
			return with(
				Biped.Stance(shape, 16 * tap, 0, 0, 4 + 2 * bounce, 2 * wave(t, 3.0), 0.08 * bounce),
				{
					RigNeck = R(8 + 4 * bounce, 0, 4 * wave(t, 1.5)),
					RigHead = R(-4 + 6 * bounce, 20 * wave(t, 3.0), -4 * wave(t, 1.5)),
					RigTail = Q.Tail(14 + 10 * bounce, 22 * wave(t, 0.75), 0),
				}
			)
		end,
	}
	set.IdleWild = {
		name = "IdleWild",
		length = 3.6,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 1.8)
			return with(
				Biped.Stance(
					shape,
					0,
					0,
					0,
					0.6 * breathe,
					1.2 * wave(t, 3.6),
					0.03 + 0.03 * breathe
				),
				{
					RigNeck = R(2 * breathe, 10 * wave(t, 3.6), 0),
					RigHead = R(-2 * breathe, 22 * wave(t, 3.6, 0.06), 3 * wave(t, 1.8, 0.2)),
					RigTail = Q.Tail(4, 12 * wave(t, 1.8, 0.3), 0),
				}
			)
		end,
	}
	-- Rare variant: a slow stretch, neck long and low, then a shake of the head.
	set.IdleWild2 = {
		name = "IdleWild2",
		length = 2.0,
		loop = false,
		priority = "Idle",
		pose = function(t: number): Poses
			local stretch = seg(t, 0, 0.5) * (1 - seg(t, 0.9, 1.2))
			local shake = seg(t, 1.1, 1.25) * (1 - seg(t, 1.7, 2.0))
			return with(Biped.Stance(shape, 0, -14 * stretch, 0, -3 * stretch, 0, 0), {
				RigNeck = R(-28 * stretch, 0, 0),
				RigHead = R(12 * stretch, 26 * shake * wave(t, 0.2), 0),
				RigTail = Q.Tail(20 * stretch, 18 * shake * wave(t, 0.2), 0),
			})
		end,
	}
	set.Walk = {
		name = "Walk",
		length = 0.7,
		loop = true,
		priority = "Movement",
		speed = shape.walkSpeed,
		pose = function(t: number): Poses
			local s = wave(t, 0.7)
			local bob = wave(t, 0.35, 0.1)
			return with(Biped.Stance(shape, 26 * s, -26 * s, 0, -2 + bob, 3 * s, 0.03, 6 * s), {
				RigNeck = R(-4 + 5 * bob, -4 * s, 0),
				RigHead = R(4 - 5 * bob, -4 * s, -3 * s),
				RigTail = Q.Tail(8, -18 * s, 0),
			})
		end,
	}
	set.Run = {
		name = "Run",
		length = 0.36,
		loop = true,
		priority = "Movement",
		speed = shape.runSpeed,
		pose = function(t: number): Poses
			local s = wave(t, 0.36)
			return with(
				Biped.Stance(
					shape,
					46 * s,
					-46 * s,
					0,
					-9 + 2 * wave(t, 0.18),
					3 * s,
					0.1 + 0.12 * math.abs(s),
					7 * s
				),
				{
					RigNeck = R(-18 + 4 * wave(t, 0.18), 0, 0),
					RigHead = R(14 - 3 * wave(t, 0.18), 0, 0),
					RigTail = Q.Tail(52 + 8 * wave(t, 0.18), -14 * s, 0),
				}
			)
		end,
	}
	set.Alert = {
		name = "Alert",
		length = 0.4,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local duck = seg(t, 0, 0.12) * (1 - seg(t, 0.12, 0.2))
			local up = snap(t, 0.14, 0.32)
			return with(Biped.Stance(shape, 0, 0, 10 * duck, mix(-6 * duck, 8, up), 0, 0.1 * up), {
				RigNeck = R(mix(-20 * duck, 14, up), 0, 0),
				RigHead = R(mix(10 * duck, -6, up), 0, 0),
				RigTail = Q.Tail(mix(0, 55, up), 0, 0),
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
			return with(Biped.Stance(shape, 0, -12 * hit, 6 * hit, 6 * hit, 7 * hit, 0), {
				RigNeck = R(18 * hit, 0, -10 * hit),
				RigHead = R(-14 * hit, 12 * hit, 10 * hit),
				RigTail = Q.Tail(30 * hit, -24 * hit, 0),
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
			return with(
				Biped.Stance(
					shape,
					20 + 30 * k,
					20 - 30 * k,
					6,
					2 * wave(t, 0.5),
					4 * wave(t, 1.0),
					0,
					5 * wave(t, 0.5)
				),
				{
					RigNeck = R(-4 + 8 * wave(t, 0.5), 12 * wave(t, 1.0), 12 * wave(t, 0.5, 0.25)),
					RigHead = R(
						6 * wave(t, 0.5, 0.3),
						-16 * wave(t, 1.0, 0.1),
						-8 * wave(t, 0.5, 0.25)
					),
					RigTail = Q.Tail(20, 34 * wave(t, 0.5), 0),
				}
			)
		end,
	}
	-- Asleep on its feet: neck and head hang, slow breathing, a slight sway.
	set.Sleep = {
		name = "Sleep",
		length = 4.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 4.0)
			return with(Biped.Stance(shape, 0, 0, 4, -2, 1.5 * breathe, 0.02 + 0.02 * breathe), {
				RigNeck = R(-34 + 3 * breathe, 0, 5),
				RigHead = R(-16 + 2 * breathe, 0, 8),
				RigTail = Q.Tail(0, 4 * breathe, 0),
			})
		end,
	}
	set.Celebrate = {
		name = "Celebrate",
		length = 1.2,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local crouch = seg(t, 0, 0.14) * (1 - seg(t, 0.14, 0.24))
			local air = bump(t, 0.18, 0.92)
			local spin = seg(t, 0.22, 0.88)
			local land = bump(t, 0.9, 1.2)
			return with(
				Biped.Stance(
					shape,
					34 * air,
					-20 * air,
					10 * crouch + 8 * land,
					6 * air - 5 * crouch,
					0,
					shape.jump * air,
					360 * spin
				),
				{
					RigNeck = R(mix(-12 * crouch, 14, air), 0, 0),
					RigHead = R(mix(6 * crouch, -8, air) + 8 * land, 0, 0),
					RigTail = Q.Tail(50 * air + 10 * land, 30 * wave(t, 0.2) * air, 0),
				}
			)
		end,
	}
	return set
end

function Biped.Finish(set: { [string]: any }): { any }
	return Q.Finish(set)
end

return table.freeze(Biped)
