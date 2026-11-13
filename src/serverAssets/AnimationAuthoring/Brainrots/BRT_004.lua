--!strict
-- Ballerina Banana (BRT_004): authored animation set. Archetype: Biped with the face on
-- the body (no head or neck joint).
-- Bones: RigTorso (the banana, face included), RigRightLeg, RigLeftLeg, RigRightArm,
-- RigLeftArm (raised stick arms), RigTutu (signature prop).
-- The meme: a banana who is, entirely seriously, a prima ballerina. Everything is done on
-- pointe, with the arms held up, and the tutu trails every turn.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx leans the body back / swings a leg forward;
-- +ry turns left; the right arm lifts with +rz and the left arm with -rz.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

-- Arms: `lift` raises both, `open` spreads them, in degrees.
local function arms(lift: number, sway: number): Poses
	return {
		RigRightArm = R(0, 0, lift + sway),
		RigLeftArm = R(0, 0, -lift + sway),
	}
end
local function with(base: Poses, extra: Poses): Poses
	for bone, cf in extra do
		base[bone] = cf
	end
	return base
end

local set: { [string]: any } = {}

set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local rise = math.abs(wave(t, 1.5))
		return with(arms(10 * rise, 8 * wave(t, 3.0)), {
			RigTorso = T(0, 0.14 * rise, 0, 3, 14 * wave(t, 3.0), 3 * wave(t, 1.5)),
			RigTutu = R(0, -10 * wave(t, 3.0, 0.08), -3 * wave(t, 1.5, 0.1)),
			RigRightLeg = R(0, 0, 4 * rise),
			RigLeftLeg = R(0, 0, -4 * rise),
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
		return with(arms(3 * breathe, 4 * wave(t, 3.6)), {
			RigTorso = T(
				0,
				0.03 + 0.03 * breathe,
				0,
				1,
				10 * wave(t, 3.6),
				1.5 * wave(t, 3.6, 0.25)
			),
			RigTutu = R(0, -6 * wave(t, 3.6, 0.1), 0),
		})
	end,
}
-- Rare variant: a deep curtsy.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local down = seg(t, 0.1, 0.6) * (1 - seg(t, 1.3, 1.85))
		return with(arms(-34 * down, 0), {
			RigTorso = T(0, 0, 0, -12 * down, 0, 0),
			RigTutu = R(8 * down, 0, 0),
			RigRightLeg = R(12 * down, 0, 0),
			RigLeftLeg = R(-34 * down, 0, 0),
		})
	end,
}
-- Bourrée: tiny quick steps on pointe, the body gliding.
set.Walk = {
	name = "Walk",
	length = 0.8, -- two steps, so the slower arm and tutu sway closes
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		return with(arms(4 * wave(t, 0.8), 3 * wave(t, 0.8, 0.25)), {
			RigTorso = T(0, 0.05 + 0.03 * math.abs(s), 0, -2, 0, 2 * wave(t, 0.8)),
			RigTutu = R(0, 4 * wave(t, 0.8), -2 * wave(t, 0.8, 0.2)),
			RigRightLeg = R(13 * s),
			RigLeftLeg = R(-13 * s),
		})
	end,
}
-- Grand jetés: leap, legs split, arms wide.
set.Run = {
	name = "Run",
	length = 0.56,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local phase = (t / 0.56) % 1
		local air = math.sin(math.clamp((phase - 0.2) / 0.8, 0, 1) * math.pi)
		local side = if (t / 0.56) % 2 < 1 then 1 else -1
		return with(arms(16 * air, 0), {
			RigTorso = T(0, 1.1 * air, 0, -7 * air, 0, 0),
			RigTutu = R(6 * air, 0, 0),
			RigRightLeg = R(52 * air * side),
			RigLeftLeg = R(-52 * air * side),
		})
	end,
}
set.Run.length = 1.12 -- two leaps, leading with each leg in turn
set.Alert = {
	name = "Alert",
	length = 0.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local up = snap(t, 0.06, 0.24)
		local air = bump(t, 0.06, 0.36)
		return with(arms(22 * up, 0), {
			RigTorso = T(0, 0.35 * air, 0, 5 * up, 0, 0),
			RigTutu = R(-8 * air, 0, 0),
			RigRightLeg = R(0, 0, 8 * air),
			RigLeftLeg = R(0, 0, -8 * air),
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
		return with(arms(-20 * hit, 14 * hit), {
			RigTorso = T(0, 0, 0.12 * hit, 9 * hit, 0, 8 * hit),
			RigTutu = R(-10 * hit, 0, -8 * hit),
			RigLeftLeg = R(-14 * hit),
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
		return with(arms(-10 + 14 * wave(t, 0.5), 10 * wave(t, 0.5, 0.25)), {
			RigTorso = R(3 * wave(t, 0.5), 8 * wave(t, 1.0), 5 * wave(t, 1.0, 0.25)),
			RigTutu = R(6 * wave(t, 0.5, 0.2), -8 * wave(t, 1.0, 0.1), 0),
			RigRightLeg = R(26 * k),
			RigLeftLeg = R(-26 * k),
		})
	end,
}
-- Asleep on her feet: drooping forward, arms lowered.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		return with(arms(-58 + 3 * breathe, 0), {
			RigTorso = T(0, 0.02 + 0.02 * breathe, 0, -9 + breathe, 0, 3),
			RigTutu = R(5, 0, -2),
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
		local land = bump(t, 0.9, 1.2)
		return with(arms(20 * air - 10 * land, 0), {
			RigTorso = T(0, 1.4 * air, 0, 4 * air, 360 * spin, 0),
			RigTutu = R(-10 * air + 8 * land, -40 * bump(t, 0.22, 0.95), 0),
			RigRightLeg = R(0, 0, 22 * air),
			RigLeftLeg = R(0, 0, -22 * air),
		})
	end,
}
-- Signature: the pirouette. Up on one pointe, the other leg lifted out, two full turns
-- with the tutu trailing, then an arabesque held for a beat.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local up = seg(t, 0, 0.15) * (1 - seg(t, 0.95, 1.05))
		local turn = seg(t, 0.12, 0.98)
		local hold = seg(t, 1.0, 1.12) * (1 - seg(t, 1.42, 1.6))
		return with(arms(18 * up - 30 * hold, 0), {
			RigTorso = T(0, 0.16 * up, 0, -12 * hold, 720 * turn, 0),
			RigTutu = R(-6 * up + 8 * hold, -55 * bump(t, 0.12, 1.05), 0),
			RigLeftLeg = R(-48 * hold, 0, -42 * up),
			RigRightLeg = R(10 * hold, 0, 0),
		})
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
