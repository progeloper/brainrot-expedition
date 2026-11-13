--!strict
-- Bisonte Giuppitere (BRT_020): authored animation set. Archetype: Hoverer (a planet on
-- sneakers; no legs, arms or tail).
-- Bones: RigTorso (the planet Jupiter), RigHead (the bison head on its front; the whole
-- face, mane, beard and horns are one rigid group), RigMoonIo and RigMoonEuropa (signature
-- props: each moon on its own bone at the planet's centre, so it orbits), RigRightLeg and
-- RigLeftLeg (the two high-top sneakers the planet hovers over).
-- The meme: a giant, tough bison-planet with an aura. Heavy and unhurried; the moons never
-- stop circling, and when he means it he paws the ground and drops his horns. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the planet or head back; +ry turns
-- left. A sneaker steps forward with -Z. Io is furthest forward at 150 degrees of orbit and
-- is lifted over the head there so it clears the horns. Europa only swings (the beard and snout
-- block a full orbit at its height).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

-- Io's orbit: `degrees` round the planet, lifted as it passes over the head.
local function io(degrees: number): CFrame
	-- full lift within 60 degrees of straight ahead, none beyond 100: it arcs over the horns
	local ahead = math.cos(math.rad(degrees - 150))
	local x = math.clamp((ahead + 0.174) / 0.674, 0, 1)
	return T(0, 1.15 * x * x * (3 - 2 * x), 0, 0, degrees, 0)
end
-- Europa's swing: degrees either side of its rest place, kept inside +-50.
local function europa(degrees: number): CFrame
	return R(0, math.clamp(degrees, -50, 50), 0)
end
-- One sneaker: how far forward (studs), how high, and toe-up pitch.
local function shoe(forward: number, lift: number, pitch: number?): CFrame
	return T(0, lift, -forward, pitch or 0, 0, 0)
end

local set: { [string]: any } = {}

-- Banked: holding court. He hovers, chin up, Io makes one full orbit a loop, and near the
-- end he snorts with a short toss of the head.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local snort = bump(t, 2.1, 2.5)
		return {
			RigTorso = T(0, 0.08 + 0.06 * wave(t, 1.5), 0, 3, 5 * wave(t, 3.0), 0),
			RigHead = R(3 + 6 * snort, 5 * wave(t, 3.0, 0.1), 0),
			RigMoonIo = io(360 * t / 3.0),
			RigMoonEuropa = europa(40 * wave(t, 1.5)),
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
			RigTorso = T(0, 0.05 + 0.04 * breathe, 0, 1, 0, 1.2 * wave(t, 3.6)),
			RigHead = R(2 * breathe, 7 * wave(t, 3.6, 0.05), 0),
			RigMoonIo = io(360 * t / 3.6),
			RigMoonEuropa = europa(30 * wave(t, 3.6, 0.2)),
		}
	end,
}
-- Rare variant: drops his horns and paws the ground twice with the right sneaker.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local down = seg(t, 0.05, 0.4) * (1 - seg(t, 1.55, 1.95))
		local paw = down * (bump(t, 0.45, 0.9) + bump(t, 1.0, 1.45))
		local reach = down
			* (seg(t, 0.4, 0.55) - seg(t, 0.75, 0.9) + seg(t, 0.95, 1.1) - seg(t, 1.3, 1.45))
		return {
			RigTorso = T(0, 0.04 * down, 0, -7 * down, 0, 0),
			RigHead = R(-7 * down, 0, 0),
			RigMoonIo = io(40 * down),
			RigMoonEuropa = europa(-30 * down),
			RigRightLeg = shoe(0.3 * reach - 0.25 * paw, 0.1 * math.abs(reach), 0),
		}
	end,
}
-- The march: the sneakers stride under the hovering planet, which rolls a little with each
-- step. The moons sway behind.
set.Walk = {
	name = "Walk",
	length = 0.9,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local s = wave(t, 0.9)
		local c = wave(t, 0.9, 0.25)
		return {
			RigTorso = T(0, 0.14 + 0.05 * math.abs(c), 0, -3, 3 * s, 3 * s),
			RigHead = R(2 + 2 * wave(t, 0.45), -3 * s, 0),
			RigMoonIo = io(-18 + 14 * wave(t, 0.9, 0.15)),
			RigMoonEuropa = europa(-14 + 16 * wave(t, 0.9, 0.3)),
			RigRightLeg = shoe(0.42 * s, 0.2 * math.max(0, c), 5 * c),
			RigLeftLeg = shoe(-0.42 * s, 0.2 * math.max(0, -c), -5 * c),
		}
	end,
}
-- The charge: horns down, the planet pitched forward, the sneakers pounding.
set.Run = {
	name = "Run",
	length = 0.4,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.4)
		local c = wave(t, 0.4, 0.25)
		return {
			RigTorso = T(0, 0.26 + 0.08 * math.abs(c), 0, -11, 3 * s, 3 * s),
			RigHead = R(-6 + 2 * wave(t, 0.2), 0, 0),
			RigMoonIo = io(-34 + 10 * wave(t, 0.4, 0.2)),
			RigMoonEuropa = europa(-34 + 10 * wave(t, 0.4, 0.4)),
			RigRightLeg = shoe(0.62 * s, 0.3 * math.max(0, c), 9 * c),
			RigLeftLeg = shoe(-0.62 * s, 0.3 * math.max(0, -c), -9 * c),
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
			RigTorso = T(0, 0.3 * air, 0, 6 * up, 0, 0),
			RigHead = R(8 * up, 0, 0),
			RigMoonIo = io(70 * air),
			RigMoonEuropa = europa(-45 * air),
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
			RigTorso = T(0, 0.04 * hit, 0.16 * hit, 8 * hit, 0, 6 * hit),
			RigHead = R(-8 * hit, 6 * hit, 0),
			RigMoonIo = io(-50 * hit),
			RigMoonEuropa = europa(40 * hit),
			RigLeftLeg = shoe(-0.2 * hit, 0.06 * hit, 0),
		}
	end,
}
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local s = wave(t, 0.25)
		local c = wave(t, 0.25, 0.25)
		return {
			RigTorso = R(3 * wave(t, 0.5), 6 * wave(t, 1.0), 4 * wave(t, 1.0, 0.25)),
			RigHead = R(5 * wave(t, 0.5), 7 * wave(t, 1.0, 0.1), 0),
			RigMoonIo = io(360 * t / 1.0),
			RigMoonEuropa = europa(45 * wave(t, 0.5)),
			RigRightLeg = shoe(0.3 * s, 0.1 + 0.1 * c, 8 * c),
			RigLeftLeg = shoe(-0.3 * s, 0.1 - 0.1 * c, -8 * c),
		}
	end,
}
-- Asleep on his feet: the planet tips forward until his beard hangs over his toes, the
-- sneakers turn out, and the moons slow right down.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		return {
			RigTorso = T(0, 0.02 * breathe, 0, -9 + breathe, 0, 2),
			RigHead = R(-7 + breathe, 0, 3),
			RigMoonIo = io(360 * t / 4.0),
			RigMoonEuropa = europa(20 * wave(t, 4.0, 0.3)),
			RigRightLeg = R(0, -14, 0),
			RigLeftLeg = R(0, 14, 0),
		}
	end,
}
-- A hop and a full spin, sneakers and all, with Io whipping round twice.
set.Celebrate = {
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.22, 0.88)
		return {
			RigTorso = T(0, 1.1 * air, 0, 4 * air, 360 * spin, 0),
			RigHead = R(8 * air, 0, 0),
			RigMoonIo = io(720 * seg(t, 0.1, 1.1)),
			RigMoonEuropa = europa(45 * wave(t, 0.4) * air),
			RigRightLeg = shoe(0, 0.12 * air, 14 * air),
			RigLeftLeg = shoe(0, 0.12 * air, 14 * air),
		}
	end,
}
-- Signature: the storm. He drops his horns and paws the ground twice, then rears up with
-- his head thrown back while Io whirls three times round him, and slams back down.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local low = seg(t, 0, 0.15) * (1 - seg(t, 0.6, 0.72))
		local paw = low * (bump(t, 0.12, 0.34) + bump(t, 0.36, 0.58))
		local reach = low
			* (seg(t, 0.1, 0.18) - seg(t, 0.28, 0.36) + seg(t, 0.36, 0.42) - seg(t, 0.52, 0.6))
		local rear = seg(t, 0.62, 0.8) * (1 - snap(t, 1.2, 1.32))
		local slam = bump(t, 1.26, 1.5)
		return {
			RigTorso = T(
				0,
				0.45 * rear + 0.04 * low - 0.05 * slam,
				0,
				-8 * low + 11 * rear - 4 * slam,
				0,
				0
			),
			RigHead = R(-7 * low + 8 * rear - 5 * slam, 0, 0),
			RigMoonIo = io(1080 * seg(t, 0.5, 1.5)),
			RigMoonEuropa = europa(-30 * low + 48 * rear * wave(t, 0.3)),
			RigRightLeg = shoe(0.3 * reach - 0.25 * paw, 0.1 * math.abs(reach), 0),
			RigLeftLeg = shoe(0, 0, 0),
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
