--!strict
-- Dragon Cannelloni (BRT_033, teased): authored animation set. Archetype: Biped with knees,
-- arms, wings and a tail, on the high-energy biped base set (Archetypes/BipedHype.lua).
-- Bones: RigTorso (the pasta chest and belt, with the gold fork worn on the back), RigHead
-- (head, horns, frill and jaw), RigRightArm / RigLeftArm (each armoured arm and fist),
-- RigRightWing / RigLeftWing, RigTail, RigRightLeg > RigRightLowerLeg, RigLeftLeg >
-- RigLeftLowerLeg.
-- The meme: a heroic golden pasta dragon with sauce in every joint and a legendary attitude.
-- Reused: IdleWild, IdleWild2, Walk, Run, Alert, Hit, Carried, Sleep and Celebrate are the
-- high-energy base clips with wing beats added. Its own: IdleDisplay (the hero stance) and
-- the Signature (the inferno roar).
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head back and swings a leg or
-- arm forward; a knee bends with -rx on the lower leg; +ry turns left; the right arm and right
-- wing lift with +rz, the left ones with -rz; a wing sweeps back with -ry (right) / +ry (left).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Biped = require(script.Parent.Parent.Archetypes.Biped)
local Hype = require(script.Parent.Parent.Archetypes.BipedHype)
local Reuse = require(script.Parent.Parent.Archetypes.Reuse)
local R, wave, seg, snap, bump = Q.R, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local shape: Biped.Shape = {
	legLength = 1.72,
	toeReach = 0.88,
	heelReach = 0.37,
	footHalfWidth = 0.34,
	walkSpeed = 6, -- Legendary: same route speed as the Epics
	runSpeed = 10,
	jump = 1.5,
}

local function wings(lift: number, sweep: number): Poses
	return {
		RigRightWing = R(0, -sweep, lift),
		RigLeftWing = R(0, sweep, -lift),
	}
end

-- Wing beat per base clip: (lift, sweep back) in degrees.
local function beat(name: string, t: number): (number, number)
	if name == "Walk" then
		return 10 * wave(t, 0.3), 4
	elseif name == "Run" then
		return 24 * wave(t, 0.17), 22
	elseif name == "Alert" then
		return 50 * bump(t, 0.1, 0.38), 0
	elseif name == "Hit" then
		return 25 * bump(t, 0, 0.3), 10 * bump(t, 0, 0.3)
	elseif name == "Carried" then
		return 30 * wave(t, 0.2), 0
	elseif name == "Sleep" then
		return -8 + 2 * wave(t, 4.0), 18
	elseif name == "Celebrate" then
		local air = bump(t, 0.12, 0.8) + bump(t, 0.9, 1.25)
		return 15 * air + 35 * air * wave(t, 0.3), 0
	elseif name == "IdleWild2" then
		return 45 * (bump(t, 0.15, 0.5) + bump(t, 1.05, 1.4)), 0
	end
	return 8 * wave(t, 1.5), 0
end

-- the armour is bulky: smaller arm raises, tail lifts, head drops and leg swings keep the arms,
-- tail, chin and thighs clear of it
local set = Reuse.Adapt(
	Hype.Build(shape, {
		raise = 0.5,
		tail = 0.6,
		head = 0.6,
		out = 2,
		walkStride = 0.7,
		runStride = 0.45,
		jumpLegs = 0.6,
		tilt = 0.6,
	}),
	{
		extra = function(name: string, t: number, poses: Poses)
			Q.With(poses, wings(beat(name, t)))
		end,
	}
)

-- Banked: the hero stance. Feet planted wide, chest out, fists flexing in turn, the wings
-- opening and closing slowly and the tail swishing; every few seconds a proud chin lift.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.5)
		local flexR = math.max(0, wave(t, 1.5))
		local flexL = math.max(0, -wave(t, 1.5))
		local chin = bump(t, 2.2, 2.9)
		return Q.With(
			Biped.Stance(
				shape,
				0,
				0,
				6,
				3 + 2 * breathe + 4 * chin,
				0,
				0.1 * math.abs(breathe) - 0.05,
				6 * wave(t, 3.0)
			),
			{
				RigHead = R(-2 + 14 * chin, 12 * wave(t, 3.0, 0.1), 0),
				RigRightArm = R(20 * flexR, 0, 8 + 16 * flexR),
				RigLeftArm = R(20 * flexL, 0, -8 - 16 * flexL),
				RigTail = Q.Tail(10 + 6 * breathe, 26 * wave(t, 1.5, 0.2)),
				RigRightWing = R(0, 0, 14 + 16 * breathe),
				RigLeftWing = R(0, 0, -14 - 16 * breathe),
			}
		)
	end,
}

-- Signature: the inferno roar. It crouches and draws back with the wings folded, then rears up
-- with the wings flung wide and high, thrusts its head forward in a huge roar with both fists
-- clenched out to the sides, holds it shaking, and slams down into a stomp.
set.Signature = {
	name = "Signature",
	length = 2.0,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local draw = seg(t, 0, 0.3) * (1 - seg(t, 0.35, 0.5))
		local rear = seg(t, 0.35, 0.6) * (1 - seg(t, 1.45, 1.7))
		local roar = snap(t, 0.6, 0.8) * (1 - seg(t, 1.35, 1.6))
		local shake = roar * wave(t, 0.08)
		local stomp = bump(t, 1.55, 1.85)
		local kr = 30 * draw + 40 * stomp
		return Q.With(
			Biped.Stance(
				shape,
				10 * draw + 14 * stomp,
				-8 * draw,
				8 * rear,
				-6 * draw + 12 * rear - 14 * roar,
				2 * shake,
				0.25 * rear - 0.1 * draw,
				0
			),
			{
				RigHead = R(-14 * draw + 18 * rear - 30 * roar, 4 * shake, 0),
				RigRightArm = R(-20 * draw + 20 * roar, 0, 6 + 60 * roar + 3 * shake),
				RigLeftArm = R(-20 * draw + 20 * roar, 0, -6 - 60 * roar - 3 * shake),
				RigRightWing = R(0, -20 * draw, -10 * draw + 60 * rear + 4 * shake),
				RigLeftWing = R(0, 20 * draw, 10 * draw - 60 * rear - 4 * shake),
				RigTail = Q.Tail(-10 * draw + 40 * rear + 30 * stomp, 30 * shake),
				RigRightLowerLeg = R(-kr),
				RigLeftLowerLeg = R(-30 * draw),
			}
		)
	end,
}

return Q.Finish(set)
