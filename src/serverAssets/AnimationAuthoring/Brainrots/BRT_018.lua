--!strict
-- Zibra Zubra Zibralini (BRT_018): authored animation set. Archetype: Quadruped with a neck and
-- knees.
-- Bones: RigTorso (the watermelon), RigNeck (the striped neck and its neon-tipped mane, rising
-- from the cut melon), RigHead, four thighs (RigFrontRightLeg ...), four lower legs
-- (RigFrontRightLowerLeg ...; each carries a cowboy boot) and RigTail.
-- The meme: a zebra bursting out of a watermelon, dressed as a desert cowboy in boots and
-- glowing spurs. A proud horse at heart: it struts, paws the ground, gallops, and when it wants
-- attention it rears up on its hind legs. Written for it: Walk, Run, IdleDisplay, IdleWild2,
-- Sleep and Signature are its own; the quadruped base supplies the other clips, and each is
-- then given neck and knee motion.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the neck or head up and back and swings a
-- thigh forward; a knee bends with -rx on the lower leg; +ry turns left.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, wave, seg, snap, bump = Q.R, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local shape: Q.Shape = {
	legLength = 1.98,
	footReach = 0.38,
	footInner = 0.17,
	frontReach = 0.66,
	backReach = 0.78,
	belly = 1.9,
	walkSpeed = 6.6, -- Uncommon route speed
	runSpeed = 11,
	jump = 1.2,
}

local set = Q.Build(shape)

-- Knee bends in degrees, in the order front right, front left, back right, back left.
local function knees(fr: number, fl: number, br: number, bl: number): Poses
	return {
		RigFrontRightLowerLeg = R(-fr),
		RigFrontLeftLowerLeg = R(-fl),
		RigBackRightLowerLeg = R(-br),
		RigBackLeftLowerLeg = R(-bl),
	}
end

-- Banked: the boot-scoot. It shifts its weight from side to side and taps its front right
-- boot twice, spur flashing, then tosses its head so the mane flicks.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local sway = wave(t, 1.5)
		local tap = bump(t, 0.2, 0.5) + bump(t, 0.6, 0.9)
		local toss = bump(t, 1.6, 2.3)
		return Q.With(
			Q.With(Q.Stance(shape, { 18 * tap, 0, 0, 0 }, 0, 2, 2.5 * sway, 0, 4 * sway), {
				RigNeck = R(8 * toss - 3 + 2 * math.abs(sway), 6 * sway, 10 * toss * wave(t, 0.35)),
				RigHead = R(-6 * toss + 3, 0, 0),
				RigTail = Q.Tail(10, 30 * wave(t, 0.75)),
			}),
			knees(40 * tap, 0, 0, 0)
		)
	end,
}
-- Rare variant: pawing the ground. The front right boot scrapes back three times, the head
-- low and the tail swishing, like a horse impatient to go.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local on = seg(t, 0.05, 0.3) * (1 - seg(t, 1.6, 1.95))
		local paw = on * math.max(0, wave(t - 0.3, 0.42))
		local swingFR = on * (30 * paw - 8)
		return Q.With(
			Q.With(Q.Stance(shape, { swingFR, 0, 0, 0 }, 0, -2 * on, 0, 0), {
				RigNeck = R(-16 * on, 0, 0),
				RigHead = R(6 * on, 10 * on, 0),
				RigTail = Q.Tail(6, 26 * on * wave(t, 0.5)),
			}),
			knees(on * (70 * paw + 10), 0, 0, 0)
		)
	end,
}
-- The walk: a proud four-beat horse walk (back right, front right, back left, front left),
-- the neck nodding twice a stride.
set.Walk = {
	name = "Walk",
	length = 1.0,
	loop = true,
	priority = "Movement",
	speed = shape.walkSpeed,
	pose = function(t: number): Poses
		local function leg(phase: number): (number, number)
			local s = wave(t, 1.0, phase)
			return 24 * s, math.max(0, wave(t, 1.0, phase + 0.25))
		end
		local fr, frUp = leg(0.25)
		local fl, flUp = leg(0.75)
		local br, brUp = leg(0)
		local bl, blUp = leg(0.5)
		local nod = wave(t, 0.5, 0.1)
		return Q.With(
			Q.With(
				Q.Stance(
					shape,
					{ fr, fl, br, bl },
					0,
					1 * nod,
					2 * wave(t, 1.0),
					0,
					3 * wave(t, 1.0)
				),
				{
					RigNeck = R(4 * nod, -4 * wave(t, 1.0), 0),
					RigHead = R(-3 * nod, 0, 0),
					RigTail = Q.Tail(6, 20 * wave(t, 1.0)),
				}
			),
			knees(60 * frUp, 60 * flUp, 50 * brUp, 50 * blUp)
		)
	end,
}
-- The gallop: hind pair then front pair hit the ground, the body rocking front to back, the
-- neck reaching out low and the tail streaming.
set.Run = {
	name = "Run",
	length = 0.45,
	loop = true,
	priority = "Movement",
	speed = shape.runSpeed,
	pose = function(t: number): Poses
		local s = wave(t, 0.45)
		local rock = wave(t, 0.45, 0.25)
		local front = 38 * wave(t, 0.45, 0.12)
		local back = 38 * wave(t, 0.45, -0.12)
		return Q.With(
			Q.With(
				Q.Stance(
					shape,
					{ front, front * 0.85, back, back * 0.85 },
					0,
					5 * rock,
					0,
					0.08 * math.abs(s)
				),
				{
					RigNeck = R(-22 - 6 * rock, 0, 0),
					RigHead = R(10 + 4 * rock, 0, 0),
					RigTail = Q.Tail(30, 10 * s),
				}
			),
			knees(
				70 * math.max(0, wave(t, 0.45, 0.37)),
				70 * math.max(0, wave(t, 0.45, 0.4)),
				60 * math.max(0, wave(t, 0.45, 0.13)),
				60 * math.max(0, wave(t, 0.45, 0.16))
			)
		)
	end,
}
-- Asleep lying down: all four legs folded under the melon, the neck laid forward and the head
-- resting low, the tail curled round.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		-- over-lowered on purpose: the floor clamp raises it until the folded legs rest
		return Q.With({
			RigTorso = Q.T(0, -2.2 + 0.02 * breathe, 0, 0, 0, 0),
			RigFrontRightLeg = R(56),
			RigFrontLeftLeg = R(56),
			RigBackRightLeg = R(56),
			RigBackLeftLeg = R(56),
			RigNeck = R(-40 + 1.5 * breathe, 0, 0),
			RigHead = R(10 - breathe, 0, 8),
			RigTail = Q.Tail(0, 30, 0),
		}, knees(140, 140, 140, 140))
	end,
}
-- Signature: the rodeo rear. It rears up on its hind legs, front boots pawing the air twice
-- with the spurs flashing, head thrown back; then it drops down and stamps.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local rear = seg(t, 0.1, 0.4) * (1 - seg(t, 1.1, 1.35))
		local paw = rear * wave(t - 0.4, 0.34)
		local stamp = bump(t, 1.3, 1.6)
		return Q.With(
			Q.With(
				Q.Stance(
					shape,
					{ 60 * rear + 20 * paw, 60 * rear - 20 * paw, -10 * rear, -10 * rear },
					0,
					34 * rear,
					0,
					0
				),
				{
					RigNeck = R(14 * rear - 10 * stamp, 0, 0),
					RigHead = R(10 * rear + 4 * paw, 0, 0),
					RigTail = Q.Tail(-10 * rear + 20 * stamp, 20 * paw),
				}
			),
			knees(
				80 * rear + 30 * paw,
				80 * rear - 30 * paw,
				10 * rear + 30 * stamp,
				10 * rear + 30 * stamp
			)
		)
	end,
}

-- Neck and knee motion added on top of the remaining base clips.
local function extras(name: string, t: number): Poses
	local out: Poses
	if name == "IdleWild" then
		out = knees(0, 0, 0, 0)
		out.RigNeck = R(3 * wave(t, 1.8, 0.1), 12 * wave(t, 3.6, 0.05), 0)
	elseif name == "Alert" then
		local up = snap(t, 0.14, 0.32)
		out = knees(0, 0, 0, 0)
		out.RigNeck = R(14 * up, 0, 0)
	elseif name == "Hit" then
		local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
		out = knees(0, 0, 18 * hit, 0)
		out.RigNeck = R(-10 * hit, 10 * hit, 0)
	elseif name == "Carried" then
		local k = wave(t, 0.25)
		out = knees(30 + 22 * k, 30 - 22 * k, 30 - 22 * k, 30 + 22 * k)
		out.RigNeck = R(8 * wave(t, 0.5), 10 * wave(t, 1.0), 0)
	else -- Celebrate
		local air = bump(t, 0.18, 0.92)
		out = knees(60 * air, 60 * air, 50 * air, 50 * air)
		out.RigNeck = R(12 * air, 0, 0)
	end
	return out
end

for _, name in { "IdleWild", "Alert", "Hit", "Carried", "Celebrate" } do
	local definition = set[name]
	local copy = table.clone(definition)
	copy.pose = function(t: number): Poses
		return Q.With(definition.pose(t), extras(name, t))
	end
	set[name] = copy
end

return Q.Finish(set)
