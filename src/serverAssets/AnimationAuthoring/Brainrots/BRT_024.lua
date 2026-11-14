--!strict
-- Nooo My Hotspot (BRT_024): authored animation set. Archetype: Biped with elbows and knees
-- and the face on the body, on the high-energy biped base set (Archetypes/BipedHype.lua).
-- Bones: RigTorso (the burrito, its sad face, filling and floating Wi-Fi arcs), RigRightArm
-- > RigRightForearm (the forearm also carries the phone), RigLeftArm > RigLeftForearm,
-- RigRightLeg > RigRightLowerLeg, RigLeftLeg > RigLeftLowerLeg.
-- The meme: a sad burrito holding out a phone with no signal. Always searching, never
-- finding. Both hands hold the phone, so both arms always turn by the same angle about the
-- shoulder: the phone goes up and down but never leaves either hand.
-- Reused: IdleWild, IdleWild2, Walk, Run, Alert, Hit, Carried, Sleep and Celebrate are the
-- high-energy base clips, with the phone lifted to suit each one. His own: IdleDisplay
-- (searching for signal) and the Signature (the NOOO).
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body back and swings a leg or arm
-- forward (raising the phone); a knee bends with -rx on the lower leg; +ry turns left.
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Biped = require(script.Parent.Parent.Archetypes.Biped)
local Hype = require(script.Parent.Parent.Archetypes.BipedHype)
local Reuse = require(script.Parent.Parent.Archetypes.Reuse)
local R, T, wave, seg, bump = Q.R, Q.T, Q.wave, Q.seg, Q.bump

type Poses = { [string]: CFrame }

local shape: Biped.Shape = {
	legLength = 1.04,
	toeReach = 0.4,
	heelReach = 0.2,
	footHalfWidth = 0.17,
	walkSpeed = 6.6, -- Rare: same as the Uncommons
	runSpeed = 11,
	jump = 1.2,
}

-- Both arms by the same angle, so the phone stays in both hands.
local function phone(angle: number): Poses
	return { RigRightArm = R(angle), RigLeftArm = R(angle) }
end

-- How high the phone is held in each base clip.
local function held(name: string, t: number): number
	if name == "Walk" then
		return 8 + 6 * wave(t, 0.3)
	elseif name == "Run" then
		return 70 + 10 * wave(t, 0.17) -- holding it up to catch a signal on the move
	elseif name == "Alert" then
		return 60 * bump(t, 0.1, 0.38) -- thrown up in fright
	elseif name == "Hit" then
		return 15 * bump(t, 0, 0.3) -- the phone jerks up
	elseif name == "Carried" then
		return 90 + 30 * wave(t, 0.4)
	elseif name == "Sleep" then
		return -6
	elseif name == "Celebrate" then
		return 140 * bump(t, 0.12, 0.8) + 90 * bump(t, 0.9, 1.25) -- got signal!
	elseif name == "IdleWild2" then
		return 60 * (bump(t, 0.15, 0.5) + bump(t, 1.05, 1.4))
	end
	return 6 + 6 * math.abs(wave(t, 1.5))
end

local set = Reuse.Adapt(Hype.Build(shape), {
	extra = function(name: string, t: number, poses: Poses)
		Q.With(poses, phone(held(name, t)))
	end,
})

-- Banked: searching for signal. He lifts the phone high and turns one way and the other,
-- shaking it, brings it down to check the screen, slumps with a sigh, and tries again.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local up = seg(t, 0.1, 0.4) * (1 - seg(t, 1.6, 1.9))
		local turn = up * wave(t - 0.4, 1.2)
		local shake = up * wave(t, 0.1)
		local sigh = bump(t, 1.9, 2.8)
		return Q.With(
			Biped.Stance(shape, 0, 0, 0, 4 * up - 8 * sigh, 2 * shake, 0.05 * up, 30 * turn),
			Q.With(phone(100 * up + 5 * shake + 10 * (1 - up)), {
				RigRightLowerLeg = R(-14 * sigh),
				RigLeftLowerLeg = R(-14 * sigh),
			})
		)
	end,
}

-- Signature: the NOOO. Phone held high, he spins round searching; the bars drop; he falls to
-- his knees clutching the phone, sobbing in shudders, then throws his head back and wails.
set.Signature = {
	name = "Signature",
	length = 2.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local up = seg(t, 0, 0.2) * (1 - seg(t, 0.85, 1.0))
		local search = seg(t, 0.15, 0.85)
		local kneel = seg(t, 0.95, 1.2) * (1 - seg(t, 2.1, 2.4))
		local sob = kneel * (1 - seg(t, 1.6, 1.7)) * math.abs(wave(t, 0.16))
		local wail = bump(t, 1.65, 2.2)
		return Q.With(phone(110 * up + 30 * kneel - 20 * wail), {
			RigTorso = T(
				0,
				0.08 * up - 0.9 * kneel + 0.05 * sob,
				0,
				-10 * kneel + 26 * wail + 6 * sob,
				360 * search,
				3 * sob
			),
			RigRightLeg = R(20 * kneel),
			RigLeftLeg = R(20 * kneel),
			RigRightLowerLeg = R(-100 * kneel),
			RigLeftLowerLeg = R(-100 * kneel),
		})
	end,
}

return Q.Finish(set)
