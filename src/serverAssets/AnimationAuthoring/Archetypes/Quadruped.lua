--!strict
-- Quadruped base set (rig + animation brief v5, B.1/B.3). Bones: RigTorso, RigHead,
-- RigFrontRightLeg, RigFrontLeftLeg, RigBackRightLeg, RigBackLeftLeg, RigTail.
-- A species file calls Build(shape) and then replaces or tunes individual clips, so each
-- species still gets its own review. Edit-time authoring data only.
--
-- Convention (model faces -Z, right is +X): +rx swings a leg forward and tips the body or
-- head UP at the front (use Tail(up, side) for the tail); +ry turns left; a right leg splays out with +rz, a left
-- leg with -rz.
local TAU = math.pi * 2

local Quadruped = {}

export type Shape = {
	legLength: number, -- hip to ground, design units
	footReach: number, -- how far the foot box extends in front of / behind the hip
	footInner: number, -- how far the foot box extends inward from the hip
	frontReach: number, -- torso pivot to the front hips
	backReach: number, -- torso pivot to the back hips
	belly: number, -- clearance under the body
	walkSpeed: number,
	runSpeed: number,
	jump: number, -- Celebrate jump height
	tailUpright: boolean?, -- the tail points up at rest instead of back
}

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
local function seg(t: number, a: number, b: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1)
	return x * x * (3 - 2 * x)
end
local function snap(t: number, a: number, b: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1) - 1
	return 1 + 2.7 * x * x * x + 1.7 * x * x
end
local function bump(t: number, a: number, b: number): number
	return math.sin(math.clamp((t - a) / (b - a), 0, 1) * math.pi)
end
-- The tail points backward, so lifting its tip is a negative rx. `up` and `side` in degrees.
local function tail(up: number, side: number, _unused: number?): CFrame
	return R(-up, side, 0)
end
Quadruped.Tail = tail
Quadruped.R, Quadruped.T, Quadruped.wave, Quadruped.mix = R, T, wave, mix
Quadruped.seg, Quadruped.snap, Quadruped.bump = seg, snap, bump

type Poses = { [string]: CFrame }

-- Leg poses plus the torso lift that keeps every foot box on or above the ground.
-- swing: forward angle per leg {FR, FL, BR, BL}; splay: outward angle for all four;
-- pitch: body pitch (nose up positive). Legs counter-rotate the pitch so they stay upright.
function Quadruped.Stance(
	shape: Shape,
	swing: { number },
	splay: number,
	pitch: number,
	roll: number,
	lift: number,
	yaw: number?
): Poses
	local need = 0
	for _, angle in swing do
		local a = math.rad(math.abs(angle))
		need = math.max(need, shape.footReach * math.sin(a) - shape.legLength * (1 - math.cos(a)))
	end
	local s = math.rad(math.abs(splay))
	need += math.max(0, shape.footInner * math.sin(s) - shape.legLength * (1 - math.cos(s)))
	need += shape.backReach * math.sin(math.rad(math.max(0, pitch))) + shape.frontReach * math.sin(
		math.rad(math.max(0, -pitch))
	) + 0.9 * math.sin(math.rad(math.abs(roll)))
	return {
		RigTorso = T(0, lift + need, 0, pitch, yaw, roll),
		RigFrontRightLeg = R(swing[1] - pitch, 0, splay - roll),
		RigFrontLeftLeg = R(swing[2] - pitch, 0, -splay - roll),
		RigBackRightLeg = R(swing[3] - pitch, 0, splay - roll),
		RigBackLeftLeg = R(swing[4] - pitch, 0, -splay - roll),
	}
end

local function with(base: Poses, extra: Poses): Poses
	for bone, cf in extra do
		base[bone] = cf
	end
	return base
end
Quadruped.With = with

function Quadruped.Build(shape: Shape): { [string]: any }
	local set: { [string]: any } = {}
	-- A tail that stands upright (a cat's) sways sideways and leans back instead of lifting.
	local tailPose = if shape.tailUpright
		then function(up: number, side: number, _unused: number?): CFrame
			return R(up * 0.25, 0, -side)
		end
		else Quadruped.Tail
	local function trot(t: number, period: number, amount: number): { number }
		local s = wave(t, period) * amount
		return { s, -s, -s, s } -- diagonal pairs move together
	end

	set.IdleDisplay = {
		name = "IdleDisplay",
		length = 3.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local bounce = math.abs(wave(t, 1.5))
			return with(
				Quadruped.Stance(
					shape,
					{ 0, 0, 0, 0 },
					4 * bounce,
					5 + 4 * bounce,
					2 * wave(t, 3.0),
					0.1 * bounce
				),
				{
					RigHead = R(8 + 6 * bounce, 16 * wave(t, 3.0), 6 * wave(t, 1.5)),
					RigTail = tailPose(18 + 8 * bounce, 34 * wave(t, 0.75), 0),
				}
			)
		end,
	}
	set.IdleWild = {
		name = "IdleWild",
		length = 3.6,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 1.8)
			return with(
				Quadruped.Stance(
					shape,
					{ 0, 0, 0, 0 },
					0,
					0.5 * breathe,
					1.2 * wave(t, 3.6),
					0.03 + 0.03 * breathe
				),
				{
					RigHead = R(3 * breathe, 28 * wave(t, 3.6, 0.05), 4 * wave(t, 1.8, 0.2)),
					RigTail = tailPose(2 * breathe, 14 * wave(t, 3.6, 0.3), 0),
				}
			)
		end,
	}
	-- Rare variant: sit back and scratch with a hind leg.
	set.IdleWild2 = {
		name = "IdleWild2",
		length = 2.0,
		loop = false,
		priority = "Idle",
		pose = function(t: number): Poses
			local on = seg(t, 0, 0.3) * (1 - seg(t, 1.6, 2.0))
			local scratch = on * (58 + 14 * wave(t, 0.14))
			return with(Quadruped.Stance(shape, { 0, 0, scratch, 0 }, 0, 4 * on, -7 * on, 0), {
				RigHead = R(8 * on, -16 * on, -14 * on),
				RigTail = tailPose(6 * on, 24 * on, 0),
			})
		end,
	}
	set.Walk = {
		name = "Walk",
		length = 0.7,
		loop = true,
		priority = "Movement",
		speed = shape.walkSpeed,
		pose = function(t: number): Poses
			local s = wave(t, 0.7)
			return with(
				Quadruped.Stance(
					shape,
					trot(t, 0.7, 26),
					0,
					1.2 * wave(t, 0.35),
					2 * s,
					0.03,
					5 * s
				),
				{
					RigHead = R(2 + 3 * wave(t, 0.35), -8 * s, -2 * s),
					RigTail = tailPose(4, -22 * s, 0),
				}
			)
		end,
	}
	set.Run = {
		name = "Run",
		length = 0.34,
		loop = true,
		priority = "Movement",
		speed = shape.runSpeed,
		pose = function(t: number): Poses
			local s = wave(t, 0.34)
			return with(
				Quadruped.Stance(
					shape,
					trot(t, 0.34, 44),
					0,
					-4 + 2 * wave(t, 0.17),
					3 * s,
					0.1 + 0.1 * math.abs(s),
					7 * s
				),
				{
					RigHead = R(8 + 3 * wave(t, 0.17), -9 * s, 0),
					RigTail = tailPose(16, -30 * s, 0),
				}
			)
		end,
	}
	set.Alert = {
		name = "Alert",
		length = 0.4,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local duck = seg(t, 0, 0.12) * (1 - seg(t, 0.12, 0.2))
			local up = snap(t, 0.14, 0.32)
			return with(
				Quadruped.Stance(shape, { 0, 0, 0, 0 }, 22 * duck, 7 * up - 3 * duck, 0, 0.06 * up),
				{
					RigHead = R(mix(-12 * duck, 26, up), 0, 0),
					RigTail = tailPose(mix(-8 * duck, 48, up), 0, 0),
				}
			)
		end,
	}
	set.Hit = {
		name = "Hit",
		length = 0.25,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
			return with(Quadruped.Stance(shape, { 0, 0, 0, 0 }, 16 * hit, 3 * hit, 8 * hit, 0), {
				RigHead = R(-14 * hit, 10 * hit, 14 * hit),
				RigTail = tailPose(20 * hit, -30 * hit, 0),
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
			return with(
				Quadruped.Stance(
					shape,
					{ 40 * k, -40 * k, -40 * k, 40 * k },
					10,
					2 * wave(t, 0.5),
					4 * wave(t, 1.0),
					0,
					6 * wave(t, 0.5)
				),
				{
					RigHead = R(6 * wave(t, 0.5), 18 * wave(t, 1.0, 0.1), 10 * wave(t, 0.5, 0.25)),
					RigTail = tailPose(8, 38 * wave(t, 0.5), 0),
				}
			)
		end,
	}
	-- Belly down, legs splayed, slow breathing.
	set.Sleep = {
		name = "Sleep",
		length = 4.0,
		loop = true,
		priority = "Idle",
		pose = function(t: number): Poses
			local breathe = wave(t, 4.0)
			local splay = 68
			local s = math.rad(splay)
			local settle = math.min(
				shape.belly - 0.03,
				shape.legLength * (1 - math.cos(s)) - shape.footInner * math.sin(s)
			)
			return with(
				Quadruped.Stance(
					shape,
					{ 0, 0, 0, 0 },
					splay,
					0,
					0,
					-math.max(0, settle) + 0.02 * breathe + 0.02
				),
				{
					RigHead = R(-10 + 1.5 * breathe, 14, 8),
					RigTail = tailPose(0, 34, 0),
				}
			)
		end,
	}
	set.Celebrate = {
		name = "Celebrate",
		length = 1.2,
		loop = false,
		priority = "Action",
		pose = function(t: number): Poses
			local crouch = seg(t, 0, 0.14) * (1 - seg(t, 0.14, 0.24))
			local air = bump(t, 0.18, 0.92)
			local spin = seg(t, 0.22, 0.88)
			local land = bump(t, 0.9, 1.2)
			local tuck = 30 * air
			return with(
				Quadruped.Stance(
					shape,
					{ tuck, tuck, -tuck, -tuck },
					20 * crouch + 12 * land,
					6 * air,
					0,
					shape.jump * air,
					360 * spin
				),
				{
					RigHead = R(mix(-8 * crouch, 20, air) - 8 * land, 0, 0),
					RigTail = tailPose(40 * air + 10 * land, 30 * wave(t, 0.2) * air, 0),
				}
			)
		end,
	}
	return set
end

Quadruped.Order = table.freeze({
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
})

-- Final ordered, frozen list for the baker.
function Quadruped.Finish(set: { [string]: any }): { any }
	local out = {}
	for _, name in Quadruped.Order do
		table.insert(out, table.freeze(assert(set[name], "missing animation " .. name)))
	end
	return table.freeze(out)
end

return table.freeze(Quadruped)
