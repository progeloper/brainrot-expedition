--!strict
-- Odin Din Din Dun (BRT_031): authored animation set. Archetype: Biped with elbows and knees
-- and the face on the body, on the high-energy biped base set (Archetypes/BipedHype.lua).
-- Bones: RigTorso (the orange, its face, crown, leaf, champion belt and posing trunks),
-- RigRightArm > RigRightForearm, RigLeftArm > RigLeftForearm (the huge bodybuilder arms; at
-- rest they are already up in a double-biceps flex: upper arms out to the sides, forearms
-- straight up), RigRightLeg > RigRightLowerLeg, RigLeftLeg > RigLeftLowerLeg (in high-tops).
-- The meme: a bodybuilder orange who never stops posing.
-- Reused: IdleWild, IdleWild2, Walk, Run, Alert, Hit, Carried, Sleep and Celebrate are the
-- high-energy base clips, with the flexing arms set for each one. His own: IdleDisplay (the
-- pump) and the Signature (the posing routine).
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body back and swings a leg forward;
-- a knee bends with -rx on the lower leg; +ry turns left. Arms (flexed at rest): an upper arm
-- rises with +rz on the right, -rz on the left; rx turns it about its own length, tipping the
-- forearm forward; a forearm curls in towards the head with +rz on the right, -rz on the left.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Biped = require(script.Parent.Parent.Archetypes.Biped)
local Hype = require(script.Parent.Parent.Archetypes.BipedHype)
local Reuse = require(script.Parent.Parent.Archetypes.Reuse)
local R, wave, seg, snap, bump, mix = Q.R, Q.wave, Q.seg, Q.snap, Q.bump, Q.mix

type Poses = { [string]: CFrame }
type Arm = { number } -- { raise, forward, curl }

local shape: Biped.Shape = {
	legLength = 1.74,
	toeReach = 0.57,
	heelReach = 0.32,
	footHalfWidth = 0.27,
	walkSpeed = 6, -- Legendary route speed
	runSpeed = 10.8, -- Sprinter burst, as BRT_001 and BRT_007
	jump = 1.3,
}

local function arms(right: Arm, left: Arm): Poses
	return {
		RigRightArm = R(right[2], 0, right[1]),
		RigRightForearm = R(0, 0, right[3]),
		RigLeftArm = R(left[2], 0, -left[1]),
		RigLeftForearm = R(0, 0, -left[3]),
	}
end
local function blend(a: Arm, b: Arm, x: number): Arm
	return { mix(a[1], b[1], x), mix(a[2], b[2], x), mix(a[3], b[3], x) }
end

local REST: Arm = { 0, 0, 0 }
local LOW: Arm = { -30, 0, -20 } -- arms eased down for walking
local FRONT: Arm = { 8, 0, 34 } -- front double biceps, squeezed
local SIDE: Arm = { -20, 60, 50 } -- side chest: arms forward, fists together
local CRAB: Arm = { -25, 50, 60 } -- most muscular: arms low in front, curled in

-- Arms per base clip.
local function flex(name: string, t: number): Poses
	if name == "Walk" then
		local s = wave(t, 0.6)
		return arms({ LOW[1], -14 * s, LOW[3] }, { LOW[1], 14 * s, LOW[3] })
	elseif name == "Run" then
		local s = wave(t, 0.34)
		return arms({ -35, -34 * s, 30 }, { -35, 34 * s, 30 })
	elseif name == "Alert" then
		local up = bump(t, 0.1, 0.38)
		return arms(blend(REST, FRONT, up), blend(REST, FRONT, up))
	elseif name == "Hit" then
		local hit = bump(t, 0, 0.3)
		return arms({ -20 * hit, 0, -20 * hit }, { -20 * hit, 0, -20 * hit })
	elseif name == "Carried" then
		local k = wave(t, 0.4)
		return arms({ 10 + 15 * k, 0, 20 + 25 * k }, { 10 - 15 * k, 0, 20 - 25 * k })
	elseif name == "Sleep" then
		return arms({ -30, 0, -35 }, { -30, 0, -35 })
	elseif name == "Celebrate" then
		local air = math.max(bump(t, 0.12, 0.8), bump(t, 0.9, 1.25))
		return arms(blend(REST, FRONT, air), blend(REST, FRONT, air))
	elseif name == "IdleWild2" then
		local h = bump(t, 0.15, 0.5) + bump(t, 1.05, 1.4)
		return arms(blend(REST, FRONT, h), blend(REST, FRONT, h))
	end
	local squeeze = math.abs(wave(t, 1.5))
	return arms({ 0, 0, 14 * squeeze }, { 0, 0, 14 * squeeze })
end

local set = Reuse.Adapt(Hype.Build(shape), {
	extra = function(name: string, t: number, poses: Poses)
		Q.With(poses, flex(name, t))
	end,
})

-- Banked: the pump. He bounces on the beat, squeezing the biceps on every bounce, then
-- alternates arms, one fist kissing the sky.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local beat = math.max(0, wave(t, 0.5))
		local both = 1 - seg(t, 1.4, 1.6) * (1 - seg(t, 2.8, 3.0))
		local alt = wave(t, 1.0) * (1 - both)
		local right = blend(REST, FRONT, both * beat + math.max(0, alt))
		local left = blend(REST, FRONT, both * beat + math.max(0, -alt))
		right[1] += 20 * math.max(0, alt)
		left[1] += 20 * math.max(0, -alt)
		return Q.With(
			Biped.Stance(shape, 0, 0, 4, 3 * beat, 4 * alt, 0.13 * beat - 0.05, 8 * alt),
			Q.With(arms(right, left), {
				RigRightLowerLeg = R(-10 * (1 - beat)),
				RigLeftLowerLeg = R(-10 * (1 - beat)),
			})
		)
	end,
}

-- Signature: the posing routine. Three poses, each snapped into with a shudder of effort:
-- front double biceps, a quarter turn into a side chest, then a most-muscular crunch facing
-- you with a stamp; he jumps back to his rest flex.
set.Signature = {
	name = "Signature",
	length = 2.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local p1 = snap(t, 0.05, 0.25) * (1 - seg(t, 0.7, 0.85))
		local p2 = snap(t, 0.75, 0.95) * (1 - seg(t, 1.4, 1.55))
		local p3 = snap(t, 1.45, 1.65) * (1 - seg(t, 2.1, 2.3))
		local hold = math.max(p1, p2, p3)
		local shudder = hold * wave(t, 0.07)
		local hop = bump(t, 2.05, 2.35)
		local arm = blend(blend(blend(REST, FRONT, p1), SIDE, p2), CRAB, p3)
		local right = { arm[1] + 2 * shudder, arm[2], arm[3] + 3 * shudder }
		local left = { arm[1] - 2 * shudder, arm[2], arm[3] + 3 * shudder }
		local knee = 18 * p3 + 20 * hop
		return Q.With(
			Biped.Stance(
				shape,
				10 * p3,
				-6 * p3,
				8 * p3,
				4 * p1 - 12 * p3,
				1.5 * shudder,
				0.6 * hop,
				40 * p2
			),
			Q.With(arms(right, left), {
				RigRightLowerLeg = R(-knee),
				RigLeftLowerLeg = R(-knee),
			})
		)
	end,
}

return Q.Finish(set)
