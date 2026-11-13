--!strict
-- Cacto Hipopotamo (BRT_021): authored animation set. Archetype: Column (a tall rigid body
-- on two feet; no arms, tail or neck).
-- Bones: RigTorso (the cactus column), RigHead (the hippo face on its front; it can only
-- move a little, because it is mounted flat on the column), RigRightLeg and RigLeftLeg
-- (each a stub leg and one giant slipper).
-- The meme: a deadpan cactus with a hippo's face, standing in huge yellow slippers. He
-- cannot bend, so everything he does is a sway, a hop or a slap of a slipper. Written
-- for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the column or face back and lifts a
-- slipper's toe; +ry turns left; +rz leans the column to his left.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

-- One slipper: how far forward (studs), extra height, and toe-up pitch in degrees. The
-- slipper turns about its hip, 0.7 studs up, so a pitch is lifted by just enough to keep
-- the heel (toe up) or the toe (toe down) off the floor.
local function slipper(forward: number, lift: number, pitch: number): CFrame
	local a = math.rad(math.abs(pitch))
	local reach = if pitch >= 0 then 0.5 else 1.16
	local clear = math.max(0, reach * math.sin(a) - 0.7 * (1 - math.cos(a)))
	return T(0, lift + clear, -forward, pitch, 0, 0)
end

local set: { [string]: any } = {}

-- Banked: the metronome. The whole column ticks from side to side while the right slipper
-- taps time.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local tick = wave(t, 1.5)
		local tap = math.max(0, wave(t, 0.75))
		return {
			RigTorso = T(0, 0.03, 0, 1, 5 * wave(t, 3.0), 5 * tick),
			RigHead = R(2 * tap, 0, 0),
			RigRightLeg = slipper(0.1, 0, 20 * tap) * R(0, 0, -5 * tick),
			RigLeftLeg = R(0, 0, -5 * tick),
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
		local lean = 2 * wave(t, 3.6)
		return {
			RigTorso = T(0, 0.02 + 0.02 * breathe, 0, 1, 0, lean),
			RigHead = R(1.5 * breathe, 5 * wave(t, 3.6, 0.05), 0),
			RigRightLeg = slipper(0, 0, 5 * math.max(0, wave(t, 1.8, 0.2))) * R(0, 0, -lean),
			RigLeftLeg = R(0, 0, -lean),
		}
	end,
}
-- Rare variant: a shimmy. He twists hard left and right four times, like shaking off sand.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local on = seg(t, 0.1, 0.3) * (1 - seg(t, 1.5, 1.8))
		local twist = on * wave(t - 0.3, 0.3)
		return {
			RigTorso = T(0, 0.05 * on, 0, 0, 24 * twist, 0),
			RigHead = R(0, 4 * twist, 0),
			RigRightLeg = R(0, -24 * twist, 0),
			RigLeftLeg = R(0, -24 * twist, 0),
		}
	end,
}
-- The shuffle: he rocks from slipper to slipper, each one sliding forward flat and landing
-- with a little flap.
set.Walk = {
	name = "Walk",
	length = 0.8,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.8)
		local c = wave(t, 0.8, 0.25)
		local rock = 6 * c
		return {
			RigTorso = T(0, 0.05 + 0.04 * math.abs(c), 0, -2, 3 * s, rock),
			RigHead = R(2 * wave(t, 0.4), 0, 0),
			RigRightLeg = slipper(0.34 * s, 0.14 * math.max(0, c), 10 * c) * R(0, 0, -rock),
			RigLeftLeg = slipper(-0.34 * s, 0.14 * math.max(0, -c), -10 * c) * R(0, 0, -rock),
		}
	end,
}
-- The flip-flop sprint: leaning in, slippers slapping fast and high.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		local c = wave(t, 0.4, 0.25)
		local rock = 5 * c
		return {
			RigTorso = T(0, 0.1 + 0.1 * math.abs(c), 0, -9, 3 * s, rock),
			RigHead = R(3, 0, 0),
			RigRightLeg = slipper(0.5 * s, 0.26 * math.max(0, c), 22 * c) * R(9, 0, -rock),
			RigLeftLeg = slipper(-0.5 * s, 0.26 * math.max(0, -c), -22 * c) * R(9, 0, -rock),
		}
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
		return {
			RigTorso = T(0, 0.3 * air, 0, 4 * up, 0, 0),
			RigHead = R(5 * up, 0, 0),
			RigRightLeg = slipper(0, 0, 14 * air) * R(-4 * up, 0, 8 * air),
			RigLeftLeg = slipper(0, 0, 14 * air) * R(-4 * up, 0, -8 * air),
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
			RigTorso = T(0, 0.02 * hit, 0.1 * hit, 9 * hit, 0, 6 * hit),
			RigHead = R(-5 * hit, 0, 0),
			RigRightLeg = R(-9 * hit, 0, -6 * hit),
			RigLeftLeg = slipper(-0.15 * hit, 0.05 * hit, 0) * R(-9 * hit, 0, -6 * hit),
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
			RigTorso = R(3 * wave(t, 0.5), 6 * wave(t, 1.0), 4 * wave(t, 1.0, 0.25)),
			RigHead = R(3 * wave(t, 0.5), 5 * wave(t, 1.0, 0.1), 0),
			RigRightLeg = T(0, 0.08, 0, 26 * k, 0, 6),
			RigLeftLeg = T(0, 0.08, 0, -26 * k, 0, -6),
		}
	end,
}
-- Asleep standing, as a cactus does: slippers turned out, the column leaning a little and
-- swaying very slowly.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		local lean = 4 + 1.5 * breathe
		return {
			RigTorso = T(0, 0.02 + 0.01 * breathe, 0, -2, 0, lean),
			RigHead = R(-5 + breathe, 0, 0),
			RigRightLeg = R(2, -16, -lean),
			RigLeftLeg = R(2, 16, -lean),
		}
	end,
}
-- A hop and a full spin, slippers kicked out to the sides.
set.Celebrate = {
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.22, 0.88)
		return {
			RigTorso = T(0, 1.2 * air, 0, 3 * air, 360 * spin, 0),
			RigHead = R(5 * air, 0, 0),
			RigRightLeg = T(0, 0.05 * air, 0, 12 * air, 0, 22 * air),
			RigLeftLeg = T(0, 0.05 * air, 0, 12 * air, 0, -22 * air),
		}
	end,
}
-- Signature: the slipper slap. Two slaps of the right slipper, two of the left, then a
-- hop with both toes up and a flat two-footed landing.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local right = bump(t, 0.05, 0.25) + bump(t, 0.27, 0.47)
		local left = bump(t, 0.52, 0.72) + bump(t, 0.74, 0.94)
		local air = bump(t, 1.0, 1.4)
		local land = bump(t, 1.38, 1.6)
		local lean = 4 * (left - right)
		return {
			RigTorso = T(0, 0.55 * air - 0.03 * land, 0, 2 * air, 0, lean),
			RigHead = R(3 * (right + left) + 5 * air - 3 * land, 0, 0),
			RigRightLeg = slipper(0.12 * right, 0, 30 * right + 24 * air) * R(0, 0, -lean),
			RigLeftLeg = slipper(0.12 * left, 0, 30 * left + 24 * air) * R(0, 0, -lean),
		}
	end,
}

local ORDER = {
	"IdleDisplay",
	"IdleWild",
	"IdleWild2",
	"Walk",
	"Run",
	"Alert",
	"Hit",
	"Carried",
	"Sleep",
	"Celebrate",
	"Signature",
}
local out = {}
for _, name in ORDER do
	table.insert(out, table.freeze(set[name]))
end
return table.freeze(out)
