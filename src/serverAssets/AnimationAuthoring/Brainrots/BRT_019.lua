--!strict
-- Trenostruzzo Turbo 3000 (BRT_019): authored animation set (rig + animation brief v5, B.3).
-- Archetype: Vehicle-hybrid. Bones (Config/VoxelCreatures/BRT_019 rig): RigTorso (chassis),
-- RigNeck, RigHead, RigRightLeg, RigLeftLeg, RigToiletLid (signature prop).
-- Edit-time authoring data: never required by the running game. Translations are in the
-- model's design units (the model is 8.6 units tall before gameplay scaling).
--
-- Convention (the model faces -Z): +rx tips the nose/neck/head UP and back, -rx leans
-- forward; +rx lifts a foot's toes (the feet hinge at the heel, so they only ever lift);
-- +rx opens the toilet lid; +ry turns left.
-- The meme: a bullet train that is also a nervous ostrich. The chassis stays stiff and
-- train-like; the neck and head do the ostrich acting.
local TAU = math.pi * 2

local function R(rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end
local function T(px: number, py: number, pz: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(px, py, pz) * R(rx, ry, rz)
end
local function wave(t: number, period: number, phase: number?): number
	return math.sin((t / period + (phase or 0)) * TAU)
end
local function mix(a: number, b: number, x: number): number
	return a + (b - a) * x
end
local function seg(t: number, a: number, b: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1)
	return x * x * (3 - 2 * x)
end
local function snap(t: number, a: number, b: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1) - 1
	return 1 + 2.7 * x * x * x + 1.7 * x * x
end
local function bump(t: number, a: number, b: number): number
	return math.sin(math.clamp((t - a) / (b - a), 0, 1) * math.pi)
end

type Poses = { [string]: CFrame }

-- The chassis pivots at the middle of the train body, and its lowest points (toes in front,
-- the last bogie behind) already sit on the ground. Any pitch or roll would push one end
-- under the floor, so the chassis is lifted by exactly what that end would sink.
local NOSE_REACH, TAIL_REACH, HALF_WIDTH = 8.6, 3.2, 1.7
local function chassis(
	pitch: number,
	roll: number,
	lift: number,
	yaw: number?,
	back: number?
): CFrame
	local clearance = NOSE_REACH * math.sin(math.rad(math.max(0, -pitch)))
		+ TAIL_REACH * math.sin(math.rad(math.max(0, pitch)))
		+ HALF_WIDTH * math.sin(math.rad(math.abs(roll)))
	return T(0, lift + clearance, back or 0, pitch, yaw, roll)
end

local set = {}
local function add(definition: any)
	table.insert(set, table.freeze(definition))
end

-- 1. IdleDisplay: banked on a base platform. Proud, showy, readable at 40 studs.
add({
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local bounce = math.abs(wave(t, 1.5))
		local honk = bump(t, 2.1, 2.6)
		return {
			RigTorso = chassis(3 + 2 * bounce, 2 * wave(t, 3.0), 0.14 * bounce),
			RigNeck = R(8 - 10 * bounce + 14 * honk, 0, 9 * wave(t, 1.5)),
			RigHead = R(-6 + 12 * bounce - 16 * honk, 14 * wave(t, 3.0), -7 * wave(t, 1.5)),
			RigRightLeg = R(14 * math.max(0, wave(t, 0.75))),
			RigLeftLeg = R(14 * math.max(0, -wave(t, 0.75))),
			RigToiletLid = R(8 * bounce + 55 * honk),
		}
	end,
})

-- 2. IdleWild: paused in the wild. Breathe, shift weight, look left and right.
add({
	name = "IdleWild",
	length = 3.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.8)
		local look = wave(t, 3.6)
		return {
			RigTorso = chassis(0.6 * breathe, 1.2 * look, 0.04 + 0.04 * breathe),
			RigNeck = R(3 * breathe, 12 * look, 0),
			RigHead = R(-2 * breathe, 26 * wave(t, 3.6, 0.06), 4 * wave(t, 1.8, 0.2)),
			RigToiletLid = R(3 * math.max(0, breathe)),
		}
	end,
})

-- 3. IdleWild2: rare variant. Stretch tall, then dip to sniff the ground twice.
add({
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local stretch = seg(t, 0, 0.35) * (1 - seg(t, 0.45, 0.7))
		local dip = seg(t, 0.55, 0.9) * (1 - seg(t, 1.55, 1.95))
		local sniff = dip * wave(t, 0.35)
		return {
			RigTorso = chassis(2 * stretch - 3 * dip, 0, 0.05 * stretch),
			RigNeck = T(0, 0.25 * stretch, 0, 12 * stretch - 46 * dip + 5 * sniff, 0, 0),
			RigHead = R(-10 * stretch + 20 * dip - 8 * sniff, 0, 6 * sniff),
			RigToiletLid = R(20 * stretch),
		}
	end,
})

-- 4. Walk: a train that trots. Stiff chassis bob, paddling feet, ostrich head-bob.
add({
	name = "Walk",
	length = 0.6,
	loop = true,
	priority = "Movement",
	speed = 7.26,
	pose = function(t: number): Poses
		local s = wave(t, 0.6)
		local thrust = wave(t, 0.3, 0.1)
		return {
			RigTorso = chassis(1.2 * wave(t, 0.3), 1.5 * s, 0.06 + 0.06 * math.abs(s)),
			RigNeck = R(-9 + 9 * thrust, 0, -3 * s),
			RigHead = R(8 - 8 * thrust, 0, 3 * s),
			RigRightLeg = R(34 * math.max(0, s)),
			RigLeftLeg = R(34 * math.max(0, -s)),
			RigToiletLid = R(4 * math.max(0, wave(t, 0.3))),
		}
	end,
})

-- 5. Run: fleeing. Nose down, neck stretched flat like an express train, lid flapping.
add({
	name = "Run",
	length = 0.36,
	loop = true,
	priority = "Movement",
	speed = 13,
	pose = function(t: number): Poses
		local s = wave(t, 0.36)
		return {
			RigTorso = chassis(-4 + 1.5 * wave(t, 0.18), 2 * s, 0.1 + 0.12 * math.abs(s)),
			RigNeck = R(-34 + 5 * wave(t, 0.18), 0, -4 * s),
			RigHead = R(30 - 4 * wave(t, 0.18), 0, 4 * s),
			RigRightLeg = R(55 * math.max(0, s)),
			RigLeftLeg = R(55 * math.max(0, -s)),
			RigToiletLid = R(22 + 16 * wave(t, 0.18)),
		}
	end,
})

-- 6. Alert: the "!" before fleeing. Duck, then snap up tall.
add({
	name = "Alert",
	length = 0.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local duck = seg(t, 0, 0.12) * (1 - seg(t, 0.12, 0.2))
		local up = snap(t, 0.14, 0.32)
		return {
			RigTorso = chassis(-2 * duck + 3 * up, 0, 0.12 * up),
			RigNeck = T(0, 0.3 * up, 0, mix(-26 * duck, 10, up), 0, 0),
			RigHead = R(mix(14 * duck, -8, up), 0, 0),
			RigRightLeg = R(12 * up),
			RigLeftLeg = R(12 * up),
			RigToiletLid = R(70 * up),
		}
	end,
})

-- 7. Hit: flinch and squash (joint dips only, no rescaling).
add({
	name = "Hit",
	length = 0.25,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
		return {
			RigTorso = chassis(3 * hit, 6 * hit, 0, 0, 0.12 * hit),
			RigNeck = R(24 * hit, 0, -10 * hit),
			RigHead = R(-18 * hit, 0, 12 * hit),
			RigRightLeg = R(20 * hit),
			RigLeftLeg = R(20 * hit),
			RigToiletLid = R(45 * hit),
		}
	end,
})

-- 8. Carried: carried or riding in the cart. Feet pedal the air, neck flails.
add({
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local kick = wave(t, 0.25)
		return {
			RigTorso = chassis(1.5 * wave(t, 0.5), 3 * wave(t, 1.0), 0),
			RigNeck = R(-6 + 10 * wave(t, 0.5), 14 * wave(t, 1.0), 16 * wave(t, 0.5, 0.25)),
			RigHead = R(8 * wave(t, 0.5, 0.3), -18 * wave(t, 1.0, 0.1), -10 * wave(t, 0.5, 0.25)),
			RigRightLeg = R(24 + 24 * kick),
			RigLeftLeg = R(24 - 24 * kick),
			RigToiletLid = R(12 + 10 * wave(t, 0.5)),
		}
	end,
})

-- 9. Sleep: head laid forward on the nose, slow breathing, the lid lifts with each snore.
add({
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		local snore = bump(t, 1.6, 2.6)
		return {
			RigTorso = chassis(-1.5, 0, 0.03 + 0.03 * breathe),
			RigNeck = R(-58 + 3 * breathe, 0, 6),
			RigHead = R(30 - 2 * breathe, 0, 12),
			RigToiletLid = R(10 * snore),
		}
	end,
})

-- 10. Celebrate: catch reveal and bank moment. Jump and spin, lid wide open.
add({
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local crouch = seg(t, 0, 0.14) * (1 - seg(t, 0.14, 0.24))
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.22, 0.88)
		local land = bump(t, 0.9, 1.2)
		return {
			RigTorso = chassis(6 * air + 2 * crouch, 0, 1.5 * air, 360 * spin),
			RigNeck = T(0, 0.25 * air, 0, mix(-14 * crouch, 12, air), 0, 0),
			RigHead = R(mix(8 * crouch, -10, air) + 10 * land, 0, 0),
			RigRightLeg = R(40 * air),
			RigLeftLeg = R(40 * air),
			RigToiletLid = R(80 * air + 25 * land),
		}
	end,
})

-- 11. Signature: rapid ostrich head-pecks at the track, the lid clacking on each one.
add({
	name = "Signature",
	length = 1.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local active = seg(t, 0, 0.12) * (1 - seg(t, 1.15, 1.4))
		local peck = (0.5 - 0.5 * math.cos(math.clamp((t - 0.12) / 1.0, 0, 1) * TAU * 4)) * active
		return {
			RigTorso = chassis(-1.5 * active - 1.5 * peck, 0, 0),
			RigNeck = R(-12 * active - 40 * peck, 0, 0),
			RigHead = R(6 * active + 16 * peck, 0, 0),
			RigRightLeg = R(10 * peck),
			RigLeftLeg = R(10 * math.max(0, active - peck)),
			RigToiletLid = R(30 * peck),
		}
	end,
})

return table.freeze(set)
