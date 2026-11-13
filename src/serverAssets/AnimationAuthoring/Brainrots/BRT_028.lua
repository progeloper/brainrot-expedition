--!strict
-- Tartaragno (BRT_028): authored animation set. Archetype: Six-legged crawler.
-- Bones: RigTorso (the shell), RigHead (the turtle head; it can pull back inside the shell),
-- RigTail, and six legs in three pairs (Front, Middle, Back; Right and Left), each a hip
-- joint under the shell rim (Rig...Leg) and a knee (Rig...LowerLeg, which carries the
-- sneaker).
-- The meme: a turtle that is also a spider. It scuttles on six legs like a spider and hides
-- in its shell like a turtle, and when it wants to look frightening it rears up and waves
-- its front legs. Written for it.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only. Several poses lower
-- the shell further than the legs allow on purpose: the floor clamp raises it until the
-- lowest part rests.
--
-- Convention (model faces -Z, right is +X): +rx tips the shell or head up at the front; +ry
-- turns left; a leg's `sweep` moves its foot forward, `raise` lifts it and `knee` swings the
-- lower leg outward; Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local LEGS = { "FrontRight", "MiddleRight", "BackRight", "FrontLeft", "MiddleLeft", "BackLeft" }
-- The two tripods of a six-legged walk: +1 legs move together, -1 legs move together.
local TRIPOD = {
	FrontRight = 1,
	MiddleLeft = 1,
	BackRight = 1,
	FrontLeft = -1,
	MiddleRight = -1,
	BackLeft = -1,
}

-- All six legs from one rule: plan(name, tripod) returns sweep, raise and knee in degrees.
local function legs(plan: (name: string, tripod: number) -> (number, number, number?)): Poses
	local out: Poses = {}
	for _, name in LEGS do
		local side = if string.sub(name, -5) == "Right" then 1 else -1
		local sweep, raise, knee = plan(name, TRIPOD[name])
		out["Rig" .. name .. "Leg"] = R(0, side * sweep, side * raise)
		out["Rig" .. name .. "LowerLeg"] = R(0, 0, side * (knee or 0))
	end
	return out
end
-- In the moving clips the front legs reach a little forward and the back legs a little back,
-- so neighbouring feet have room to pass.
local function fan(name: string): number
	local group = string.sub(name, 1, 4)
	return if group == "Fron" then 18 elseif group == "Back" then -18 else 0
end
-- The head: pulled back into the shell by `retract` studs, then turned.
local function head(retract: number, rx: number, ry: number, rz: number): CFrame
	return T(0, 0, retract, rx, ry, rz)
end
local function all(...: Poses): Poses
	local out: Poses = {}
	for _, poses in { ... } do
		for bone, cf in poses do
			out[bone] = cf
		end
	end
	return out
end

local set: { [string]: any } = {}

-- Banked: showing off. It does slow push-ups on its six legs so the gem on its shell rises
-- and falls, and waves its front sneakers one after the other.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local pump = wave(t, 1.5)
		local hello = wave(t, 3.0)
		return all(
			legs(function(name: string): (number, number, number?)
				if name == "FrontRight" then
					return 16 * math.max(0, hello), 6 * pump + 34 * math.max(0, hello), 0
				elseif name == "FrontLeft" then
					return 16 * math.max(0, -hello), 6 * pump + 34 * math.max(0, -hello), 0
				end
				return 0, 6 * pump, 0
			end),
			{
				RigTorso = T(0, -0.2, 0, 2 * pump, 6 * hello, 0),
				RigHead = head(0, 4 + 3 * pump, 10 * hello, 5 * wave(t, 1.5, 0.25)),
				RigTail = Q.Tail(6, 30 * wave(t, 0.75)),
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
		return all(
			legs(function(name: string, tripod: number): (number, number, number?)
				-- the middle legs tap now and then
				local tap = if string.sub(name, 1, 6) == "Middle"
					then 9 * math.max(0, wave(t, 0.9, if tripod > 0 then 0 else 0.5)) * math.max(
						0,
						wave(t, 3.6)
					)
					else 0
				return 0, 2 + 2 * breathe + tap, 0
			end),
			{
				RigTorso = T(0, -0.2, 0, 0.5 * breathe, 2 * wave(t, 3.6), 0),
				RigHead = head(0, 2 * breathe, 15 * wave(t, 3.6, 0.05), 3 * wave(t, 1.8, 0.2)),
				RigTail = Q.Tail(2 * breathe, 16 * wave(t, 3.6, 0.3)),
			}
		)
	end,
}
-- Rare variant: the turtle hides. The head snaps back into the shell and the body drops;
-- after a moment it peeks half out, looks left and right, and comes out again.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local hide = snap(t, 0.12, 0.3) * (1 - seg(t, 1.55, 1.9))
		local peek = seg(t, 0.85, 1.1) * (1 - seg(t, 1.55, 1.9))
		local look = peek * wave(t - 1.0, 0.5)
		return all(
			legs(function(): (number, number, number?)
				return 0, 16 * hide - 6 * peek, 0
			end),
			{
				RigTorso = T(0, -0.4, 0, 0, 0, 0),
				RigHead = head(0.85 * hide - 0.4 * peek, 4 * hide, 14 * look, 0),
				RigTail = T(0, 0, -0.3 * hide) * Q.Tail(0, 0),
			}
		)
	end,
}
-- The walk: a six-legged tripod gait. Three legs step while the other three push, the shell
-- swaying a little and the head leading.
set.Walk = {
	name = "Walk",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		local c = wave(t, 0.4, 0.25) -- positive while the +1 tripod steps forward
		return all(
			legs(function(name: string, tripod: number): (number, number, number?)
				local step = math.max(0, c * tripod)
				return fan(name) + 14 * s * tripod, 15 * step, 6 * step
			end),
			{
				RigTorso = T(0, -0.2, 0, 0, 3 * s, 1.5 * c),
				RigHead = head(0, 2 + 2 * wave(t, 0.2), -5 * s, 0),
				RigTail = Q.Tail(4, 24 * s),
			}
		)
	end,
}
-- The scuttle: low to the ground, legs a blur, head stretched forward.
set.Run = {
	name = "Run",
	length = 0.24,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.24)
		local c = wave(t, 0.24, 0.25)
		return all(
			legs(function(name: string, tripod: number): (number, number, number?)
				local step = math.max(0, c * tripod)
				return fan(name) + 20 * s * tripod, 9 + 18 * step, 8 * step
			end),
			{
				RigTorso = T(0, -0.5, 0, -3, 4 * s, 2 * c),
				RigHead = head(-0.1, 6, -6 * s, 0),
				RigTail = Q.Tail(24, 20 * s),
			}
		)
	end,
}
-- Startled: it pops up tall on its back four legs and throws its front legs up.
set.Alert = {
	name = "Alert",
	length = 0.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local up = snap(t, 0.06, 0.24)
		local air = bump(t, 0.06, 0.36)
		return all(
			legs(function(name: string): (number, number, number?)
				if string.sub(name, 1, 5) == "Front" then
					return 14 * air, 38 * air, 0
				end
				return 0, -12 * up, 0
			end),
			{
				RigTorso = T(0, -0.2, 0, 5 * up, 0, 0),
				RigHead = head(0, 9 * up, 0, 0),
				RigTail = Q.Tail(40 * up, 0),
			}
		)
	end,
}
set.Hit = {
	name = "Hit",
	length = 0.25,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
		return all(
			legs(function(): (number, number, number?)
				return 0, 13 * hit, 0
			end),
			{
				RigTorso = T(0, -0.4, 0, 3 * hit, 0, 6 * hit),
				RigHead = head(0.5 * hit, -4 * hit, 8 * hit, 0),
				RigTail = Q.Tail(10 * hit, -30 * hit),
			}
		)
	end,
}
-- Carried: all six legs paddling in the air, one after another.
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local flap = wave(t, 0.5)
		local index = 0
		return all(
			legs(function(): (number, number, number?)
				index += 1
				local phase = index / 6
				return 24 * wave(t, 0.5, phase), 22 + 14 * wave(t, 0.5, phase + 0.25), 10
			end),
			{
				RigTorso = R(3 * flap, 5 * wave(t, 1.0), 4 * wave(t, 1.0, 0.25)),
				RigHead = head(0.1, 4 * flap, 12 * wave(t, 1.0, 0.1), 0),
				RigTail = Q.Tail(8, 40 * flap),
			}
		)
	end,
}
-- Asleep as a turtle: the shell down on the ground, head pulled inside, tail tucked in and
-- the six legs splayed out with their knees up.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		return all(
			legs(function(): (number, number, number?)
				return 0, 46 + breathe, 0
			end),
			{
				RigTorso = T(0, -0.8, 0, 0, 0, 0),
				RigHead = head(0.85, 18, 0, 0),
				RigTail = T(0, 0, -0.3) * Q.Tail(0, 0),
			}
		)
	end,
}
-- A jump and a full spin with all six legs flung out.
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
		return all(
			legs(function(): (number, number, number?)
				return 0, 14 * crouch + 30 * air + 12 * land, 14 * air
			end),
			{
				RigTorso = T(0, -0.4 + 1.4 * air, 0, 4 * air, 360 * spin, 0),
				RigHead = head(0, 9 * air - 4 * land, 0, 0),
				RigTail = Q.Tail(40 * air, 30 * wave(t, 0.2) * air),
			}
		)
	end,
}
-- Signature: the spider threat. It rears up on its back legs, fangs forward, and waves its
-- front legs in the air four times; then it drops back down with a thump.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local rear = seg(t, 0.08, 0.36) * (1 - seg(t, 1.18, 1.42))
		local flick = rear * wave(t - 0.36, 0.2)
		local land = bump(t, 1.36, 1.6)
		return all(
			legs(function(name: string): (number, number, number?)
				local group = string.sub(name, 1, 5)
				local side = if string.sub(name, -5) == "Right" then 1 else -1
				if group == "Front" then
					return 12 * rear + 16 * flick * side,
						48 * rear + 14 * flick * side + 10 * land,
						20 * rear
				elseif group == "Middl" then
					return 0, -12 * rear + 10 * land, 0
				end
				return 0, 10 * land, 0
			end),
			{
				RigTorso = T(0, -0.4, 0, 22 * rear, 0, 0),
				RigHead = head(0, -12 * rear + 5 * land, 0, 0),
				RigTail = Q.Tail(10 * rear, 30 * flick),
			}
		)
	end,
}

return Q.Finish(set)
