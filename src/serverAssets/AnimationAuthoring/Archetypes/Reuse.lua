--!strict
-- Reuse an approved species' animation set on another brainrot with the same body shape
-- (owner, 14 Nov 2026: "reuse animations where the body shape is similar").
-- Adapt(source, options) takes a finished set (a list) or a base set still keyed by name
-- (Biped.Build, which has no Signature yet) and returns the clips keyed by name, each with a
-- pose that:
--   1. renames source bones to the target's (`rename`); bones the target lacks are ignored by
--      the baker, so props such as a bat or a meatball simply drop out;
--   2. scales every translation by `scale` (target size / source size), so lifts, hops and
--      steps fit the new body; angles are kept;
--   3. lets `extra(name, t, poses, source)` add or replace poses for the target's own joints
--      (a phone that bops, wings that flap), reading the untouched source poses if needed;
--   4. lowers the body by `sink[name]` studs in that clip, for a base clip that would hover
--      over a shorter-legged body: the floor clamp then sets it back on the ground.
-- The species file can then replace whole clips (a Signature of its own) and calls
-- Quadruped.Finish. Bake through AnimationBaker.GroundedSet: the floor clamp still lifts any
-- foot that would sink. Edit-time authoring data only.
local Reuse = {}

type Poses = { [string]: CFrame }

export type Options = {
	scale: number?,
	rename: { [string]: string }?,
	extra: ((name: string, t: number, poses: Poses, source: Poses) -> ())?,
	sink: { [string]: number }?,
	walkSpeed: number?,
	runSpeed: number?,
}

local function scaled(cf: CFrame, k: number): CFrame
	if k == 1 then
		return cf
	end
	return (cf - cf.Position) + cf.Position * k
end
Reuse.Scaled = scaled

-- A smaller version of the same turn: k = 0.5 is half the angle (and half the move).
function Reuse.Damp(cf: CFrame?, k: number): CFrame
	local identity = CFrame.new()
	return identity:Lerp(cf or identity, k)
end

-- The same pose on the other side of the body: x moves and yaw/roll swap sign.
function Reuse.Mirrored(cf: CFrame): CFrame
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	local p = cf.Position
	return CFrame.new(-p.X, p.Y, p.Z) * CFrame.fromEulerAnglesXYZ(rx, -ry, -rz)
end

function Reuse.Adapt(source: { [any]: any }, options: Options): { [string]: any }
	local k = options.scale or 1
	local rename = options.rename or {}
	local set: { [string]: any } = {}
	for _, definition in source do
		local copy = table.clone(definition)
		local name = definition.name
		copy.pose = function(t: number): Poses
			local from: Poses = definition.pose(t)
			local out: Poses = {}
			for bone, cf in from do
				out[rename[bone] or bone] = scaled(cf, k)
			end
			if options.extra then
				options.extra(name, t, out, from)
			end
			local sink = options.sink and options.sink[name]
			if sink and out.RigTorso then
				out.RigTorso = CFrame.new(0, -sink, 0) * out.RigTorso
			end
			return out
		end
		if copy.speed then
			copy.speed = if name == "Run"
				then options.runSpeed or copy.speed
				else options.walkSpeed or copy.speed
		end
		set[name] = copy
	end
	return set
end

return table.freeze(Reuse)
