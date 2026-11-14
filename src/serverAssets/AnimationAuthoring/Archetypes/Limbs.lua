--!strict
-- Knees and arms for species that reuse the Biped base set (Archetypes/Biped.lua), which only
-- moves the torso, neck, head, thighs and tail. Call Limbs.Add(name, t, poses) from a
-- Reuse.Adapt `extra` to give every base clip knee bends and opposite-arm swing that follow
-- the legs the base clip already moves. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx swings a hanging thigh or arm forward; a
-- knee bends with -rx on the lower leg; the right arm lifts outward with +rz, the left with -rz.
local Q = require(script.Parent.Quadruped)
local R, wave, bump, seg = Q.R, Q.wave, Q.bump, Q.seg

local Limbs = {}

type Poses = { [string]: CFrame }

-- Forward swing of a pose, in degrees.
function Limbs.Swing(cf: CFrame?): number
	if not cf then
		return 0
	end
	local rx = cf:ToEulerAnglesXYZ()
	return math.deg(rx)
end

-- Knee bend per base clip: the leg that is swinging forward folds its knee, so the foot
-- clears the ground; Carried kicks; Celebrate tucks; Alert and Hit dip.
function Limbs.Knees(name: string, t: number): (number, number)
	if name == "Walk" then
		local c = math.cos(t / 0.7 * math.pi * 2)
		return 38 * math.max(0, c), 38 * math.max(0, -c)
	elseif name == "Run" then
		local c = math.cos(t / 0.36 * math.pi * 2)
		return 70 * math.max(0, c), 70 * math.max(0, -c)
	elseif name == "Carried" then
		local k = wave(t, 0.25)
		return 30 + 25 * k, 30 - 25 * k
	elseif name == "Celebrate" then
		local tuck = 55 * bump(t, 0.18, 0.92) + 25 * bump(t, 0.9, 1.2) + 20 * bump(t, 0, 0.24)
		return tuck, tuck
	elseif name == "Alert" then
		local duck = 24 * seg(t, 0, 0.12) * (1 - seg(t, 0.12, 0.2))
		return duck, duck
	elseif name == "IdleDisplay" then
		return 22 * math.max(0, wave(t, 0.75)), 0
	end
	return 0, 0
end

-- Adds knees (if the rig has them) and arms swinging against the opposite leg. `armSwing`
-- scales the swing; `armOut` holds the arms a little away from the body; `raiseScale` scales
-- how far the arms lift outward in Celebrate, Alert, Carried and Hit (0 for none).
function Limbs.Add(
	name: string,
	t: number,
	poses: Poses,
	armSwing: number?,
	armOut: number?,
	raiseScale: number?
)
	local kr, kl = Limbs.Knees(name, t)
	poses.RigRightLowerLeg = R(-kr)
	poses.RigLeftLowerLeg = R(-kl)
	local k = armSwing or 0.8
	local out = armOut or 4
	local right, left = Limbs.Swing(poses.RigLeftLeg), Limbs.Swing(poses.RigRightLeg)
	local raise = 0
	if name == "Celebrate" then
		raise = 120 * bump(t, 0.16, 0.95)
	elseif name == "Alert" then
		raise = 40 * seg(t, 0.14, 0.3) * (1 - seg(t, 0.3, 0.4))
	elseif name == "Carried" then
		raise = 60 + 20 * wave(t, 0.5)
	elseif name == "Hit" then
		raise = 30 * bump(t, 0, 0.25)
	end
	raise *= raiseScale or 1
	poses.RigRightArm = R(k * right, 0, out + raise)
	poses.RigLeftArm = R(k * left, 0, -out - raise)
end

return table.freeze(Limbs)
