--!strict
-- Orcalero Orcala (BRT_034, teased): authored animation set. Archetype: Four-legged walker,
-- reusing Tralalero Tralala's approved set (BRT_027): the orca is the same torpedo body on the
-- same sneakers, with rear legs where the shark has its tail leg.
-- Bones: RigTorso (the body, with the dorsal fin), RigHead (head, face, grin and blowhole),
-- RigTail (the flukes), RigFrontRightLeg / RigFrontLeftLeg (the fin-legs), RigBackRightLeg /
-- RigBackLeftLeg, each with a knee (Rig...LowerLeg) that carries its sneaker.
-- What is reused: every clip of BRT_027. The front fin-legs take the shark's fin-legs; in
-- Walk and Run each rear leg steps with the opposite front leg (a trot), in Carried it pedals
-- with it, and elsewhere both rear legs do what the shark's tail leg does. Sleep spreads the
-- rear legs out to the sides like the front ones. Every hop and bounce goes half as high again
-- (the high-energy pass). The Signature is his own: the breach.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx tips the body or head up at the front and
-- swings a leg forward; a knee bends with -rx on the lower leg; +ry turns left; +rz rolls the
-- body to his left; Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local Reuse = require(script.Parent.Parent.Archetypes.Reuse)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

local set = Reuse.Adapt(require(script.Parent.BRT_027) :: any, {
	rename = {
		RigRightLeg = "RigFrontRightLeg",
		RigRightLowerLeg = "RigFrontRightLowerLeg",
		RigLeftLeg = "RigFrontLeftLeg",
		RigLeftLowerLeg = "RigFrontLeftLowerLeg",
	},
	extra = function(name: string, _t: number, poses: Poses, from: Poses)
		poses.RigCentreLeg, poses.RigCentreLowerLeg = nil, nil
		-- high-energy pass: every hop and bounce of the shark's set goes half as high again
		local body = poses.RigTorso
		if body and body.Y > 0 and name ~= "Sleep" then
			poses.RigTorso = CFrame.new(0, 0.5 * body.Y, 0) * body
		end
		if name == "Walk" or name == "Run" then
			-- trot: each rear leg with the opposite front leg (no splay in these clips). The rear
			-- legs take a smaller swing and no hip lift: their tops sit inside the body.
			poses.RigBackRightLeg = Reuse.Damp(from.RigLeftLeg.Rotation, 0.6)
			poses.RigBackRightLowerLeg = from.RigLeftLowerLeg
			poses.RigBackLeftLeg = Reuse.Damp(from.RigRightLeg.Rotation, 0.6)
			poses.RigBackLeftLowerLeg = from.RigRightLowerLeg
		elseif name == "Carried" then
			poses.RigBackRightLeg = Reuse.Mirrored(from.RigLeftLeg)
			poses.RigBackRightLowerLeg = from.RigLeftLowerLeg
			poses.RigBackLeftLeg = Reuse.Mirrored(from.RigRightLeg)
			poses.RigBackLeftLowerLeg = from.RigRightLowerLeg
		elseif name == "Sleep" then
			-- belly-down: the rear legs spread out to the sides as well
			poses.RigBackRightLeg = R(0, 0, 85)
			poses.RigBackLeftLeg = R(0, 0, -85)
		else
			poses.RigBackRightLeg = from.RigCentreLeg
			poses.RigBackRightLowerLeg = from.RigCentreLowerLeg
			poses.RigBackLeftLeg = from.RigCentreLeg
			poses.RigBackLeftLowerLeg = from.RigCentreLowerLeg
		end
	end,
})

-- One leg: forward swing, hip lift and knee bend, turned against the body's pitch and roll so
-- it stays upright; the knee keeps the sneaker level unless a bend is given.
local function leg(
	swing: number,
	knee: number,
	side: number,
	pitch: number,
	roll: number
): (CFrame, CFrame)
	return R(swing - pitch, 0, side * 6 - roll), R(-swing - knee)
end

-- Signature: the breach. He crouches on all four sneakers, launches nose-up into a full
-- barrel roll with the legs tucked, lands in a belly-bounce with a slap of the flukes, and
-- finishes with a proud flick of the head.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local crouch = seg(t, 0, 0.18) * (1 - seg(t, 0.18, 0.26))
		local air = bump(t, 0.22, 1.02)
		local rise = seg(t, 0.22, 0.55) * (1 - seg(t, 0.55, 1.0))
		local spin = seg(t, 0.32, 0.92)
		local land = bump(t, 1.0, 1.32)
		local slap = snap(t, 1.02, 1.14) * (1 - seg(t, 1.2, 1.45))
		local flick = bump(t, 1.3, 1.6)
		local pitch = 22 * rise - 10 * air * (1 - rise) - 4 * land
		local roll = 360 * spin
		local tuck = 70 * air
		local knee = 30 * crouch + tuck + 40 * land
		local fr, frk = leg(-10 * air, knee, 1, pitch, 0)
		local fl, flk = leg(-10 * air, knee, -1, pitch, 0)
		local br, brk = leg(10 * air, knee, 1, pitch, 0)
		local bl, blk = leg(10 * air, knee, -1, pitch, 0)
		return {
			RigTorso = T(0, 2.4 * air - 0.25 * crouch - 0.2 * land, 0, pitch, 0, roll),
			RigHead = R(6 * rise - 4 * land + 8 * flick, 0, -6 * flick),
			RigTail = Q.Tail(-20 * rise + 50 * slap + 16 * flick, 20 * wave(t, 0.3) * air),
			RigFrontRightLeg = fr,
			RigFrontRightLowerLeg = frk,
			RigFrontLeftLeg = fl,
			RigFrontLeftLowerLeg = flk,
			RigBackRightLeg = br,
			RigBackRightLowerLeg = brk,
			RigBackLeftLeg = bl,
			RigBackLeftLowerLeg = blk,
		}
	end,
}

return Q.Finish(set)
