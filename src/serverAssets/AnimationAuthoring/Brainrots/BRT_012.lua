--!strict
-- Frigo Camelo (BRT_012): authored animation set. Archetype: Quadruped with a neck, knees
-- and a signature prop.
-- Bones: RigTorso (the fridge), RigNeck, RigHead, four thighs (RigFrontRightLeg ...), four
-- lower legs (RigFrontRightLowerLeg ...; each carries a boot), RigTail and RigFridgeDoor (the
-- front door on his right flank, hinged on its rear edge; the glowing seal behind it shows
-- as the light inside).
-- The meme: a camel who is also a fridge. Lofty and unbothered, with a long swaying neck;
-- now and then the door swings open and he has to deal with it. Written for him: Walk (a
-- camel's pace), Sleep and Signature are his own; the quadruped base supplies the other
-- clips, and each is then given neck, knee and door motion.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the neck or head up and back and swings
-- a thigh forward; a knee bends with -rx on the lower leg; +ry turns left; the door opens
-- outward with -ry.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, wave, seg, snap, bump = Q.R, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local shape: Q.Shape = {
	legLength = 1.608,
	footReach = 0.48,
	footInner = 0.24,
	frontReach = 0.927,
	backReach = 0.913,
	belly = 1.55,
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
local function door(open: number): CFrame
	return R(0, -open, 0)
end

-- Asleep kneeling, the way camels rest: all four legs folded under the fridge, the neck
-- laid forward and the head low.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		-- over-lowered on purpose: the floor clamp raises it until the folded legs rest
		return Q.With({
			RigTorso = Q.T(0, -1.2 + 0.02 * breathe, 0, 0, 0, 0),
			RigFrontRightLeg = R(56),
			RigFrontLeftLeg = R(56),
			RigBackRightLeg = R(56),
			RigBackLeftLeg = R(56),
			RigNeck = R(-34 + 1.5 * breathe, 0, 0),
			RigHead = R(8 - breathe, 0, 6),
			RigTail = Q.Tail(0, 20, 0),
			RigFridgeDoor = door(0),
		}, knees(142, 142, 142, 142))
	end,
}

-- Signature: the door. It swings wide open on its own; he stops, cranes his neck round to
-- stare at it, shivers at the cold, then bumps it shut with a hop of his back end.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local open = snap(t, 0.05, 0.3) * (1 - snap(t, 1.18, 1.3))
		local look = seg(t, 0.25, 0.5) * (1 - seg(t, 1.25, 1.5))
		local shiver = look * (1 - seg(t, 1.0, 1.15)) * wave(t, 0.09)
		local kick = bump(t, 1.1, 1.36)
		return Q.With(
			Q.With(
				Q.Stance(shape, { 0, 0, 18 * kick, 18 * kick }, 0, -5 * kick, 2 * shiver, 0.02),
				{
					RigNeck = R(6 * look, -22 * look, 0),
					RigHead = R(-4 * look + 3 * shiver, -42 * look, 0),
					RigTail = Q.Tail(20 * look + 30 * kick, 26 * shiver, 0),
					RigFridgeDoor = door(104 * open),
				}
			),
			knees(0, 0, 40 * kick, 40 * kick)
		)
	end,
}

-- The camel walk: a slow pace, not a trot. Both legs on one side swing forward together, the
-- fridge leans over the two legs still on the ground, and the neck pumps twice a stride.
set.Walk = {
	name = "Walk",
	length = 0.95,
	loop = true,
	priority = "Movement",
	speed = shape.walkSpeed,
	pose = function(t: number): Poses
		local s = wave(t, 0.95)
		local lift = wave(t, 0.95, 0.15) -- positive while the right pair is in the air
		local right, left = math.max(0, lift), math.max(0, -lift)
		local pump = wave(t, 0.475, 0.1)
		return Q.With(
			Q.With(
				Q.Stance(shape, { 27 * s, -27 * s, 27 * s, -27 * s }, 0, 1.5 * pump, 4 * lift, 0.03),
				{
					RigNeck = R(7 * pump, -3 * lift, 0),
					RigHead = R(-5 * pump, -3 * lift, -3 * lift),
					RigTail = Q.Tail(4, -24 * s, 0),
					RigFridgeDoor = door(3 * right),
				}
			),
			knees(52 * right, 52 * left, 46 * right, 46 * left)
		)
	end,
}

-- Neck, knee and door motion added on top of each base clip.
local function extras(name: string, length: number, t: number): Poses
	local out: Poses
	if name == "IdleDisplay" then
		-- on show: the door opens once a loop like a showroom fridge
		local open = seg(t, 0.5, 0.95) * (1 - seg(t, 2.0, 2.45))
		out = knees(0, 0, 0, 0)
		out.RigNeck = R(5 * wave(t, 1.5), 8 * wave(t, 3.0), 0)
		out.RigFridgeDoor = door(78 * open)
	elseif name == "IdleWild" then
		out = knees(0, 0, 0, 0)
		out.RigNeck = R(3 * wave(t, 1.8, 0.1), 9 * wave(t, 3.6, 0.05), 0)
		out.RigFridgeDoor = door(0)
	elseif name == "IdleWild2" then
		out = knees(0, 0, 0, 0)
		out.RigNeck = R(-10 * bump(t, 0.2, 1.8), 0, 0)
		out.RigFridgeDoor = door(6 * math.max(0, wave(t, 0.5)) * bump(t, 0.2, 1.8))
	elseif name == "Run" then
		local lift = wave(t, length, 0.15)
		out = knees(
			52 * math.max(0, lift),
			52 * math.max(0, -lift),
			52 * math.max(0, -lift),
			52 * math.max(0, lift)
		)
		out.RigNeck = R(-16 + 5 * wave(t, length / 2), 0, 0)
		-- the door rattles as he gallops
		out.RigFridgeDoor = door(10 * math.max(0, wave(t, length / 2, 0.2)))
	elseif name == "Alert" then
		local up = snap(t, 0.06, 0.24)
		out = knees(0, 0, 0, 0)
		out.RigNeck = R(12 * up, 0, 0)
		out.RigFridgeDoor = door(18 * bump(t, 0.06, 0.36))
	elseif name == "Hit" then
		local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
		out = knees(0, 0, 14 * hit, 0)
		out.RigNeck = R(-10 * hit, 8 * hit, 0)
		out.RigFridgeDoor = door(30 * hit)
	elseif name == "Carried" then
		local k = wave(t, 0.25)
		out = knees(30 + 22 * k, 30 - 22 * k, 30 - 22 * k, 30 + 22 * k)
		out.RigNeck = R(8 * wave(t, 0.5), 7 * wave(t, 1.0), 0)
		out.RigFridgeDoor = door(22 + 18 * wave(t, 0.5, 0.2))
	else -- Celebrate
		local air = bump(t, 0.18, 0.92)
		out = knees(55 * air, 55 * air, 55 * air, 55 * air)
		out.RigNeck = R(10 * air, 0, 0)
		out.RigFridgeDoor = door(60 * air)
	end
	return out
end

for name, definition in set do
	if name ~= "Sleep" and name ~= "Signature" and name ~= "Walk" then
		local copy = table.clone(definition)
		copy.pose = function(t: number): Poses
			return Q.With(definition.pose(t), extras(name, definition.length, t))
		end
		set[name] = copy
	end
end

return Q.Finish(set)
