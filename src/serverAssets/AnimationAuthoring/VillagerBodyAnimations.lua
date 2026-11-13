--!strict
-- Authored animation set for the one villager body (rig + animation brief v5, C.4).
-- Edit-time authoring data: never required by the running game. AnimationBaker samples each
-- `pose(t)` into a KeyframeSequence under ServerStorage.AnimationSources.VillagerBody.
--
-- Joint convention (bind pose faces -Z, left is -X, C1 = identity):
--   +rx: arm/leg swings forward, torso/head leans BACK (lean forward is -rx)
--   +ry: turns left          +rz: right arm lifts outward (left arm lifts with -rz)
-- All motion is original work authored for Brainrot Expedition.
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
-- Progress 0..1 through the window [a, b], smoothed.
local function seg(t: number, a: number, b: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1)
	return x * x * (3 - 2 * x)
end
-- Overshooting ease-out for snappy cartoon hits.
local function snap(t: number, a: number, b: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1) - 1
	return 1 + 2.7 * x * x * x + 1.7 * x * x
end
-- 0 -> 1 -> 0 across [a, b].
local function bump(t: number, a: number, b: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1)
	return math.sin(x * math.pi)
end

type Poses = { [string]: CFrame }

-- Shared stepping cycle. legs/arms are swing amplitudes in degrees, bounce in studs.
local function gait(t: number, period: number, legs: number, arms: number, bounce: number): Poses
	local s = wave(t, period)
	local lift = math.abs(wave(t, period, 0.25))
	return {
		Hips = T(0, bounce * lift - bounce * 0.4, 0),
		LegL = R(legs * s),
		LegR = R(-legs * s),
		FootL = R(-legs * s * 0.6 + math.max(0, -s) * 18),
		FootR = R(legs * s * 0.6 + math.max(0, s) * 18),
		UpperArmL = R(-arms * s),
		UpperArmR = R(arms * s),
		HandL = R(math.max(0, -s) * arms * 0.4),
		HandR = R(math.max(0, s) * arms * 0.4),
	}
end

local function with(base: Poses, extra: Poses): Poses
	for bone, cf in extra do
		base[bone] = cf
	end
	return base
end

local set = {}
local function add(definition: any)
	table.insert(set, table.freeze(definition))
end

-- 1. Idle: breathe, look around, adjust hat.
add({
	name = "Idle",
	length = 3.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.8)
		local adjust = bump(t, 2.3, 3.3)
		return {
			Hips = T(0, 0.02 * breathe, 0, 0, 0, 1.5 * wave(t, 3.6)),
			Torso = R(1.5 * breathe, 4 * wave(t, 3.6)),
			Head = R(-4 * adjust, 22 * wave(t, 3.6, 0.1) * (1 - adjust), 3 * wave(t, 1.8, 0.3)),
			UpperArmL = R(3 * breathe, 0, -3 - 2 * breathe),
			UpperArmR = R(3 * breathe + 4 * adjust, 0, 3 + 2 * breathe),
			HandL = R(0, 0, 0),
			Hat = T(0, 0.05 * adjust, 0, -5 * adjust * wave(t, 0.25), 0, 0),
			LegL = R(0, 0, -1.5 * wave(t, 3.6)),
			LegR = R(0, 0, -1.5 * wave(t, 3.6)),
		}
	end,
})

-- 2. Walk: relaxed village stroll (authored for IdleWalkSpeed 3).
add({
	name = "Walk",
	length = 0.8,
	loop = true,
	priority = "Movement",
	speed = 3,
	pose = function(t: number): Poses
		local s = wave(t, 0.8)
		return with(gait(t, 0.8, 22, 24, 0.07), {
			Torso = R(-2, 6 * s, 2.5 * wave(t, 0.8, 0.25)),
			Head = R(2, -5 * s, -2 * wave(t, 0.8, 0.25)),
		})
	end,
})

-- 3. WalkGrumble: slumped walk home (ReturnWalkSpeed 10).
add({
	name = "WalkGrumble",
	length = 0.5,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local s = wave(t, 0.5)
		return with(gait(t, 0.5, 30, 9, 0.05), {
			Torso = R(-17, 3 * s, 3 * wave(t, 0.5, 0.25)),
			Neck = R(-8),
			Head = R(-14, 7 * wave(t, 0.25), 0),
			UpperArmL = R(8 - 8 * s, 0, 4),
			UpperArmR = R(8 + 8 * s, 0, -4),
		})
	end,
})

-- 4. Curious: cautious tiptoe toward the noise, hand to the brow, head scanning.
add({
	name = "Curious",
	length = 1.2,
	loop = true,
	priority = "Movement",
	speed = 13,
	pose = function(t: number): Poses
		local step = gait(t, 0.6, 27, 0, 0.05)
		step.Hips = step.Hips * CFrame.new(0, 0.08, 0)
		return with(step, {
			Torso = R(-15, 10 * wave(t, 1.2), 0),
			Head = R(6, 26 * wave(t, 1.2, 0.05), 5 * wave(t, 0.6)),
			UpperArmL = R(128, 0, 28),
			HandL = R(-35, 0, 0),
			UpperArmR = R(-18 + 6 * wave(t, 0.6), 0, 8),
		})
	end,
})

-- 5. Shout: exactly the 0.75 s wind-up. Inhale crouch -> arms up shout -> hop, prop raised.
add({
	name = "Shout",
	length = 0.75,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local crouch = seg(t, 0, 0.2) * (1 - seg(t, 0.2, 0.32))
		local up = snap(t, 0.2, 0.42)
		local hop = bump(t, 0.44, 0.7)
		local land = seg(t, 0.68, 0.75)
		local splay = 24 * crouch + 8 * land
		return {
			Hips = T(0, -0.09 * crouch + 0.62 * hop - 0.01 * land, 0),
			Torso = R(mix(-22 * crouch, 12, up) - 14 * land, 0, 0),
			Head = R(mix(-10 * crouch, 20, up) - 12 * land, 0, 0),
			UpperArmL = R(mix(-45 * crouch, 172, up), 0, mix(0, -22, up)),
			UpperArmR = R(mix(-45 * crouch, 168, up), 0, mix(0, 14, up)),
			HandR = R(180 * up, 0, 0),
			HandL = R(-25 * up, 0, 0),
			LegL = R(22 * hop, 0, -splay),
			LegR = R(-14 * hop, 0, splay),
			FootL = R(-10 * hop, 0, splay),
			FootR = R(20 * hop, 0, -splay),
		}
	end,
})

-- 6. RunSprint: all-out sprint, pumping arms (Sprinter chase).
add({
	name = "RunSprint",
	length = 0.28,
	loop = true,
	priority = "Movement",
	speed = 30,
	pose = function(t: number): Poses
		local s = wave(t, 0.28)
		return with(gait(t, 0.28, 52, 72, 0.16), {
			Torso = R(-26, 9 * s, 0),
			Head = R(20, -6 * s, 0),
			HandL = R(35, 0, 0),
			HandR = R(35, 0, 0),
		})
	end,
})

-- 7. Tired: the Sprinter after its burst. Slumped stagger, floppy arms, lolling head.
add({
	name = "Tired",
	length = 1.12,
	loop = true,
	priority = "Movement",
	speed = 24,
	pose = function(t: number): Poses
		local s = wave(t, 0.56)
		local sway = wave(t, 1.12)
		local step = gait(t, 0.56, 32, 0, 0.09)
		step.Hips = step.Hips * T(0.12 * sway, 0, 0, 0, 0, 5 * sway)
		return with(step, {
			Torso = R(-38 + 4 * math.abs(s), 0, 7 * sway),
			Neck = R(-6),
			Head = R(-8 + 6 * wave(t, 0.28), 0, 13 * wave(t, 1.12, 0.2)),
			UpperArmL = R(28 + 14 * s, 0, -6),
			UpperArmR = R(28 - 14 * s, 0, 6),
			HandL = R(20 * math.abs(s)),
			HandR = R(20 * math.abs(s)),
		})
	end,
})

-- 8. RunTrot: heavy determined trot, prop waving overhead (Plodder chase).
add({
	name = "RunTrot",
	length = 0.42,
	loop = true,
	priority = "Movement",
	speed = 24,
	pose = function(t: number): Poses
		local s = wave(t, 0.42)
		return with(gait(t, 0.42, 34, 30, 0.22), {
			Torso = R(-11, 5 * s, 5 * wave(t, 0.42, 0.25)),
			Head = R(8, 0, -4 * wave(t, 0.42, 0.25)),
			UpperArmR = R(160 + 8 * s, 0, 14 + 20 * wave(t, 0.42, 0.25)),
			HandR = R(180 + 22 * wave(t, 0.21), 0, 0),
		})
	end,
})

-- 9. Alarm: the Shouter jumps on the spot, prop up, pointing at the thief.
add({
	name = "Alarm",
	length = 0.5,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local jump = math.max(0, wave(t, 0.5)) ^ 0.7
		local ground = 1 - math.min(1, jump * 3)
		return {
			Hips = T(0, 0.5 * jump - 0.04 * ground, 0),
			Torso = R(6 - 10 * ground, 0, 0),
			Head = R(10 - 8 * ground, 0, 0),
			UpperArmR = R(170, 0, 12 + 16 * wave(t, 0.125)),
			HandR = R(180, 0, 14 * wave(t, 0.125)),
			UpperArmL = R(92 + 6 * wave(t, 0.25), 0, 6),
			HandL = R(-8),
			LegL = R(16 * jump, 0, -4 - 14 * ground),
			LegR = R(16 * jump, 0, 4 + 14 * ground),
			FootL = R(24 * jump, 0, 4 + 14 * ground),
			FootR = R(24 * jump, 0, -4 - 14 * ground),
		}
	end,
})

-- 10. Reach: right arm only, layered over a run when within 8 studs of the cart.
add({
	name = "Reach",
	length = 0.4,
	loop = true,
	priority = "Action",
	upperBodyOnly = true,
	pose = function(t: number): Poses
		local poke = wave(t, 0.4)
		return {
			UpperArmR = R(88 + 7 * poke, 0, -6),
			HandR = R(-158 + 16 * poke, 0, 0),
		}
	end,
})

-- 11. Tag: the BONK. Wind up, whack forward, wobble.
add({
	name = "Tag",
	length = 0.35,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local windup = seg(t, 0, 0.1)
		local strike = snap(t, 0.1, 0.2)
		local wobble = math.sin(seg(t, 0.2, 0.35) * TAU * 1.5) * (1 - seg(t, 0.2, 0.35))
		return {
			Hips = T(0, -0.02 * strike, -0.15 * strike),
			Torso = R(mix(10 * windup, -24, strike), mix(-14 * windup, 12, strike), 7 * wobble),
			Head = R(mix(6 * windup, 10, strike), 0, -9 * wobble),
			UpperArmR = R(mix(155 * windup, 62, strike), 0, 8),
			HandR = R(mix(-60 * windup, -176, strike), 0, 0),
			UpperArmL = R(mix(0, -30, strike), 0, -14),
			LegL = R(-10 * strike),
			LegR = R(16 * strike),
			FootL = R(10 * strike),
			FootR = R(-16 * strike),
		}
	end,
})

-- 12. TantrumStomp (Plodder): stomp, tear the hat off and throw it down.
-- The hat is posed in head space, so its landing spot is solved against the body's own
-- motion: it comes to rest flat on the ground in front of the feet and stays there.
-- Bind offsets below are Config/VillagerBody joint heights (Hips 1.75, Torso +0.25,
-- Neck +1.5, Head +0.15, Hat +1.4).
add({
	name = "TantrumStomp",
	length = 1.5,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local stomp = wave(t, 0.3)
		local grab = seg(t, 0.25, 0.5)
		local throw = snap(t, 0.55, 0.75)
		local fall = seg(t, 0.6, 0.98)
		local drop = fall * fall -- gravity: slow off the hand, fast to the ground
		local spin = seg(t, 0.56, 0.84) -- the tumble finishes before it lands
		local settle = seg(t, 1.3, 1.5)
		local rage = 1 - settle
		local poses: Poses = {
			Hips = T(0, 0.1 * math.abs(stomp) * rage, 0, 0, 0, 5 * stomp * rage),
			Torso = R(mix(4, -20, throw) * rage, 0, -6 * stomp * rage),
			Head = R(mix(8, -12, throw) * rage, 9 * wave(t, 0.15) * rage, 0),
			LegL = R(math.max(0, stomp) * 46 * rage),
			LegR = R(math.max(0, -stomp) * 46 * rage),
			FootL = R(math.max(0, stomp) * -20 * rage),
			FootR = R(math.max(0, -stomp) * -20 * rage),
			UpperArmL = R(
				mix(mix(0, 165, grab), 35, throw) * rage,
				0,
				mix(0, 24, grab) * (1 - throw)
			),
			HandL = R(mix(0, -40, grab) * (1 - throw)),
			UpperArmR = R(mix(118, 166, math.abs(stomp)) * rage, 0, 10 * rage),
			HandR = R(180 * rage, 0, 0),
		}
		local head = CFrame.new(0, 1.75, 0)
			* poses.Hips
			* CFrame.new(0, 0.25, 0)
			* poses.Torso
			* CFrame.new(0, 1.65, 0)
			* poses.Head
		local onHead = head * CFrame.new(0, 1.4 + 0.3 * grab * (1 - fall), 0)
		local landed = CFrame.new(0, 0.12, -2.9)
		local position = onHead.Position:Lerp(landed.Position, drop)
			+ Vector3.new(0, 1.2 * bump(t, 0.55, 0.9), 0)
		local rotation = onHead.Rotation:Lerp(CFrame.identity, fall) * R(-360 * spin)
		poses.Hat = (head * CFrame.new(0, 1.4, 0)):ToObjectSpace(CFrame.new(position) * rotation)
		return poses
	end,
})

-- 13. TantrumFlail (Sprinter): whistle, then windmill arms and hop from foot to foot.
add({
	name = "TantrumFlail",
	length = 1.5,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local whistle = seg(t, 0, 0.15) * (1 - seg(t, 0.4, 0.5))
		local flail = seg(t, 0.42, 0.55) * (1 - seg(t, 1.3, 1.5))
		local spin = (t - 0.45) * 720
		local hop = wave(t, 0.26)
		return {
			Hips = T(0, 0.16 * math.abs(hop) * flail, 0, 0, 0, 9 * hop * flail),
			Torso = R(10 * whistle - 6 * flail, 0, -11 * hop * flail),
			Head = R(14 * whistle, 12 * wave(t, 0.2) * flail, 8 * hop * flail),
			UpperArmL = R(mix(118 * whistle, spin, flail), 0, mix(34 * whistle, -16, flail)),
			HandL = R(-30 * whistle),
			UpperArmR = R(mix(-10 * whistle, spin + 180, flail), 0, 16 * flail),
			LegL = R(math.max(0, hop) * 38 * flail, 0, -6 * flail),
			LegR = R(math.max(0, -hop) * 38 * flail, 0, 6 * flail),
		}
	end,
})

-- 14. TantrumSquawk (Shouter): angry jumps, prop shaken overhead, fist shaking.
add({
	name = "TantrumSquawk",
	length = 1.5,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local rage = seg(t, 0, 0.12) * (1 - seg(t, 1.32, 1.5))
		local jump = math.max(0, wave(t, 0.44)) * rage
		local ground = (1 - math.min(1, jump * 3)) * rage
		return {
			Hips = T(0, 0.5 * jump - 0.04 * ground, 0),
			Torso = R(-12 * rage + 10 * jump, 0, 0),
			Head = R(-10 * rage + 14 * jump, 8 * wave(t, 0.11) * rage, 0),
			UpperArmR = R(170 * rage, 0, (10 + 22 * wave(t, 0.11)) * rage),
			HandR = R(180 * rage, 0, 16 * wave(t, 0.11) * rage),
			UpperArmL = R((98 + 16 * wave(t, 0.15)) * rage, 0, -8 * rage),
			HandL = R(-30 * rage),
			LegL = R(14 * jump, 0, -16 * ground),
			LegR = R(14 * jump, 0, 16 * ground),
			FootL = R(0, 0, 16 * ground),
			FootR = R(0, 0, -16 * ground),
		}
	end,
})

-- 15. Wave: big friendly greeting with the free (left) hand.
add({
	name = "Wave",
	length = 1.0,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local up = snap(t, 0, 0.22) * (1 - seg(t, 0.8, 1.0))
		local hop = bump(t, 0.02, 0.26)
		return {
			Hips = T(0, 0.14 * hop, 0, 0, 0, -3 * up),
			Torso = R(3 * up, -6 * up, -5 * up),
			Head = R(6 * up, -8 * up, -8 * up),
			UpperArmL = R(0, 0, (-152 + 20 * wave(t, 0.25)) * up),
			HandL = R(0, 0, -24 * wave(t, 0.25, 0.1) * up),
			UpperArmR = R(0, 0, 6 * up),
		}
	end,
})

-- 16. Chat: gesturing, nodding, a laugh.
add({
	name = "Chat",
	length = 2.4,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local laugh = bump(t, 1.5, 2.2)
		local talk = 1 - laugh
		return {
			Hips = T(0, 0.04 * wave(t, 0.15) * laugh, 0, 0, 0, 2 * wave(t, 2.4)),
			Torso = R(9 * laugh - 2 * talk, 5 * wave(t, 2.4), 0),
			Head = R(
				16 * laugh + 7 * wave(t, 0.48) * talk,
				6 * wave(t, 1.2),
				4 * wave(t, 2.4, 0.2)
			),
			UpperArmL = R(
				(58 + 18 * wave(t, 0.8)) * talk + 20 * laugh,
				0,
				(10 + 14 * wave(t, 0.8, 0.25)) * talk
			),
			HandL = R(-30 * talk, 0, 18 * wave(t, 0.4) * talk),
			UpperArmR = R(6 * wave(t, 1.2) + 14 * laugh, 0, 5),
		}
	end,
})

-- 17. Chop: two-handed overhead chop (axe / mallet comes from the skin).
add({
	name = "Chop",
	length = 1.2,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local raise = seg(t, 0, 0.45)
		local chop = snap(t, 0.5, 0.64)
		local recover = seg(t, 0.85, 1.2)
		local arm = mix(mix(20, 162, raise), 42, chop)
		arm = mix(arm, 20, recover)
		local lean = mix(mix(0, 13, raise), -26, chop) * (1 - recover)
		return {
			Hips = T(0, -0.06 * chop * (1 - recover), 0),
			Torso = R(lean, 0, 0),
			Head = R(-lean * 0.5, 0, 0),
			UpperArmR = R(arm, 0, -14),
			UpperArmL = R(arm, 0, 14),
			HandR = R(mix(mix(mix(-170, -110, raise), -168, chop), -170, recover), 0, 0),
			LegL = R(8, 0, -8),
			LegR = R(-8, 0, 8),
			FootL = R(-8, 0, 8),
			FootR = R(8, 0, -8),
		}
	end,
})

-- 18. Sweep: broom strokes side to side.
add({
	name = "Sweep",
	length = 1.4,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local s = wave(t, 1.4)
		return {
			Hips = T(0.1 * s, 0, 0, 0, 0, 2 * s),
			Torso = R(-14, 22 * s, 0),
			Head = R(-10, -10 * s, 0),
			UpperArmR = R(38 + 8 * s, 0, -10),
			HandR = R(-168, 0, 10 * s),
			UpperArmL = R(52 - 8 * s, 0, 24),
			LegL = R(6 * s, 0, -5),
			LegR = R(-6 * s, 0, 5),
			FootL = R(-6 * s, 0, 5),
			FootR = R(6 * s, 0, -5),
		}
	end,
})

-- 19. Fish: rod held out, slow bob, one tug.
add({
	name = "Fish",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local tug = bump(t, 2.2, 2.6)
		local bob = wave(t, 1.5)
		return {
			Hips = T(0, 0.015 * bob, 0),
			Torso = R(-4 + 10 * tug, -8, 0),
			Head = R(-6 + 8 * tug, 8, 0),
			UpperArmR = R(68 + 3 * bob + 34 * tug, 0, 0),
			HandR = R(-125 + 4 * bob - 20 * tug, 0, 0),
			UpperArmL = R(-10, 0, -32),
			HandL = R(0, 0, 30),
			LegL = R(0, 0, -6),
			LegR = R(-8 * tug, 0, 6),
			FootL = R(0, 0, 6),
			FootR = R(8 * tug, 0, -6),
		}
	end,
})

-- 20. Knead: leaning over the table, pushing dough forward and back.
add({
	name = "Knead",
	length = 0.9,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local s = wave(t, 0.9)
		return {
			Hips = T(0, 0, -0.07 * s),
			Torso = R(-22 - 4 * s, 0, 0),
			Head = R(-12, 0, 3 * wave(t, 1.8)),
			UpperArmL = R(56 + 13 * s, 0, 12),
			UpperArmR = R(56 + 13 * wave(t, 0.9, 0.12), 0, -12),
			HandL = R(-30),
			HandR = R(-150), -- the prop lies forward on the table, clear of the face
			LegL = R(4, 0, -5),
			LegR = R(-4, 0, 5),
			FootL = R(-4, 0, 5),
			FootR = R(4, 0, -5),
		}
	end,
})

-- 21. Stir: circling a ladle in a pot, free hand on the hip.
add({
	name = "Stir",
	length = 1.2,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		return {
			Hips = T(0, 0, 0, 0, 0, 2 * wave(t, 1.2)),
			Torso = R(-9, 6 * wave(t, 1.2), 0),
			Head = R(-12, 0, 4 * wave(t, 1.2, 0.25)),
			UpperArmR = R(60 + 12 * wave(t, 1.2, 0.25), 0, 13 * wave(t, 1.2)),
			HandR = R(-160, 0, 0),
			UpperArmL = R(-8, 0, -34),
			HandL = R(0, 0, 34),
		}
	end,
})

-- 22. Skate: push-and-glide in small circles (the client steers the circle).
add({
	name = "Skate",
	length = 1.6,
	loop = true,
	priority = "Movement",
	speed = 3,
	pose = function(t: number): Poses
		local s = wave(t, 1.6)
		local left, right = math.max(0, s), math.max(0, -s)
		return {
			Hips = T(0.16 * s, 0, 0, 0, 0, -7 * s),
			Torso = R(-16, 8 * s, 4 * s),
			Head = R(12, -6 * s, 0),
			LegL = R(-22 * left, 0, -26 * left),
			LegR = R(-22 * right, 0, 26 * right),
			FootL = R(22 * left, 0, 26 * left + 7 * s),
			FootR = R(22 * right, 0, -26 * right + 7 * s),
			UpperArmL = R(-20 * s, 0, -24 - 10 * left),
			UpperArmR = R(20 * s, 0, 24 + 10 * right),
		}
	end,
})

-- 23. Lookout: hand to the brow, scanning the hunting ground, up on tiptoe at the ends.
add({
	name = "Lookout",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local scan = wave(t, 3.0)
		local tiptoe = math.abs(scan) ^ 3
		return {
			Hips = T(0, 0.19 * tiptoe, 0),
			Torso = R(-5, 28 * scan, 0),
			Head = R(4, 16 * scan, 0),
			UpperArmL = R(128, 0, 28),
			HandL = R(-35),
			UpperArmR = R(-6, 0, 30),
			HandR = R(0, 0, -28),
			FootL = R(-12 * tiptoe),
			FootR = R(-12 * tiptoe),
		}
	end,
})

-- 24. Fiddle: tinkering with a device held in both hands.
add({
	name = "Fiddle",
	length = 1.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local puzzled = bump(t, 1.0, 1.5)
		return {
			Torso = R(-8, 0, 0),
			Head = R(-20 + 8 * puzzled, 0, 12 * puzzled),
			UpperArmL = R(58 + 4 * wave(t, 0.4), 0, 20),
			UpperArmR = R(58 + 4 * wave(t, 0.4, 0.5), 0, -20),
			HandL = R(-40, 30 * wave(t, 0.2), 0),
			HandR = R(-40, 30 * wave(t, 0.2, 0.5), 0),
			Hips = T(0, 0.02 * wave(t, 0.8), 0),
		}
	end,
})

return table.freeze(set)
