--!strict
-- Playtest Fixes Part B: pure pose maths for weapon displays on the Weapons stall.
--
-- Slot frame (authored on each RackSlot_/WallSlot_/MedalSlot_ part):
--   LookVector  along the rail, toward the customer's LEFT (as seen standing in front of the stall)
--   UpVector    the rack plane's up (wall slots lean back by one shared angle)
--   RightVector = Look x Up, which points INTO the stall; the customer looks at -RightVector.
-- (A frame with Up = up, Look = customer's left and Right = toward the customer would be mirrored, so the
-- customer-facing check uses -RightVector.)
--
-- Display pose: the model's `along` axis lies on the rail with its negative end (muzzle / prod / point,
-- model -Z for guns and crossbows) toward Look; its `face` axis points at the customer; the remaining
-- axis is up. Crossbows then lean back around the rail so the prod reads from the front.
local Config = require(script.Parent.Parent.Config.PlaytestFixes).StallPoses

local Pose = {}

export type AxisName = "X" | "Y" | "Z"
export type Axes = {
	along: AxisName,
	face: AxisName,
	up: AxisName,
	alongSign: number,
	upSign: number,
	tilt: number,
}

local UNIT: { [AxisName]: Vector3 } = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }

local function component(v: Vector3, axis: AxisName): number
	return if axis == "X" then v.X elseif axis == "Y" then v.Y else v.Z
end

-- Axes sorted largest -> smallest (ties keep X, Y, Z order).
function Pose.Ranked(size: Vector3): { AxisName }
	local list: { AxisName } = { "X", "Y", "Z" }
	table.sort(list, function(a, b)
		local ca, cb = component(size, a), component(size, b)
		if math.abs(ca - cb) < 1e-4 then
			return a < b
		end
		return ca > cb
	end)
	return list
end

function Pose.Family(weaponId: string, displayFamily: string?): string
	local override = (Config.FamilyOverrides :: any)[weaponId]
	if override then
		return override
	end
	return if displayFamily and (Config.Families :: any)[displayFamily]
		then displayFamily
		else "Gun"
end

-- Which model axis goes where, from the measured bounding box (+ config overrides).
function Pose.Axes(size: Vector3, family: string, weaponId: string?): Axes
	local rule = (Config.Families :: any)[family] or Config.Families.Gun
	local override = if weaponId then (Config.AxisOverrides :: any)[weaponId] else nil
	local ranked = Pose.Ranked(size)
	local function pick(spec: string): AxisName
		if spec == "largest" then
			return ranked[1]
		elseif spec == "smallest" then
			return ranked[3]
		end
		return spec :: AxisName
	end
	local along = pick((override and override.along) or rule.along)
	local face = pick((override and override.face) or rule.face)
	if face == along then
		face = if along == ranked[3] then ranked[2] else ranked[3]
	end
	local up: AxisName = "X"
	for _, a in { "X", "Y", "Z" } :: { AxisName } do
		if a ~= along and a ~= face then
			up = a
		end
	end
	return {
		along = along,
		face = face,
		up = up,
		alongSign = (override and override.alongSign) or rule.alongSign or 1,
		upSign = (override and override.upSign) or rule.upSign or 1, -- -1 turns the up axis over
		tilt = (override and override.tilt) or rule.tilt or 0,
	}
end

-- Rotation, in slot space, that maps the model's own frame onto the pose.
-- Slot space targets: along+ -> slot +Z (so model -along -> slot Look = -Z), face -> slot -X
-- (toward the customer), up -> slot +Y.
function Pose.Rotation(axes: Axes): CFrame
	local a = UNIT[axes.along] * axes.alongSign -- maps to +Z
	local f = UNIT[axes.face] -- maps to -X
	local u = UNIT[axes.up] * (if axes.upSign == -1 then -1 else 1) -- maps to +Y
	-- Target basis (-X, +Y, +Z) has determinant -1; the source (f, u, a) must match. Keep the up
	-- (guns stay upright) and show the other side of the weapon instead.
	if f:Cross(u):Dot(a) > 0 then
		f = -f
	end
	local function map(e: Vector3): Vector3
		return Vector3.new(-f:Dot(e), u:Dot(e), a:Dot(e))
	end
	local rotation =
		CFrame.fromMatrix(Vector3.zero, map(Vector3.xAxis), map(Vector3.yAxis), map(Vector3.zAxis))
	-- Lean back around the rail (slot Z): the weapon's top tips toward the board (+X).
	local tilt = CFrame.Angles(0, 0, -math.rad(axes.tilt))
	return tilt * rotation
end

-- Extent of a box of `size` (model frame) along slot X/Y/Z after `rotation`.
function Pose.Extents(size: Vector3, rotation: CFrame): Vector3
	local r, u, l = rotation.RightVector, rotation.UpVector, -rotation.LookVector
	-- Columns of the rotation are the images of model X, Y, Z.
	return Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	)
end

export type Fit = { scale: number, multiplier: number, fits: boolean, shrunk: boolean }

-- Display scale relative to the authored display (authored = AuthoredMultiplier x held size).
-- Target multiplier unless the weapon overruns the rail by more than the tolerance; then fit, but
-- never below MinMultiplier (fits = false means it still overruns at the floor; report it).
function Pose.Scale(alongLength: number, railLength: number): Fit
	local authored = Config.AuthoredMultiplier
	local target = Config.TargetMultiplier
	local floor = Config.MinMultiplier
	local atTarget = alongLength * target / authored
	if atTarget <= railLength * (1 + Config.OverrunTolerance) then
		return { scale = target / authored, multiplier = target, fits = true, shrunk = false }
	end
	local wanted = railLength / alongLength * authored
	local multiplier = math.max(floor, wanted)
	return {
		scale = multiplier / authored,
		multiplier = multiplier,
		fits = wanted >= floor,
		shrunk = true,
	}
end

-- Like Scale, but also keeps the posed profile height within `rowHeight` (rack rows). `size` is the
-- authored (unscaled) display box; extents are measured after the family rotation and tilt.
function Pose.Fit(size: Vector3, axes: Axes, railLength: number, rowHeight: number?): Fit
	local extents = Pose.Extents(size, Pose.Rotation(axes))
	local authored = Config.AuthoredMultiplier
	local target = Config.TargetMultiplier
	local limit = railLength / extents.Z * authored
	if rowHeight then
		limit = math.min(limit, rowHeight / extents.Y * authored)
	end
	if target <= limit * (1 + Config.OverrunTolerance) then
		return { scale = target / authored, multiplier = target, fits = true, shrunk = false }
	end
	local multiplier = math.max(Config.MinMultiplier, limit)
	return {
		scale = multiplier / authored,
		multiplier = multiplier,
		fits = limit >= Config.MinMultiplier,
		shrunk = true,
	}
end

-- Full pose of a display's bounding box in slot space (scale already applied to `size`).
-- The back of the weapon is kept `clearance` in front of the board behind the slot line.
function Pose.BoxInSlot(size: Vector3, axes: Axes, clearance: number): CFrame
	local rotation = Pose.Rotation(axes)
	local extents = Pose.Extents(size, rotation)
	local out = math.max(0, extents.X / 2 - clearance)
	return CFrame.new(-out, 0, 0) * rotation
end

-- Normalised slot frame. `customer` = horizontal direction from the stall toward its customers.
function Pose.SlotFrame(position: Vector3, customer: Vector3, leanDegrees: number): CFrame
	local c = Vector3.new(customer.X, 0, customer.Z).Unit
	local left = c:Cross(Vector3.yAxis) -- the customer's left (they face -c)
	local lean = math.rad(leanDegrees)
	local up = Vector3.yAxis * math.cos(lean) + -c * math.sin(lean) -- top leans away from the customer
	local look = left
	local right = look:Cross(up)
	return CFrame.fromMatrix(position, right, up, -look)
end

-- Lean (degrees) of a slot's up away from vertical, signed positive when it leans into the stall.
function Pose.LeanDegrees(slot: CFrame, customer: Vector3): number
	local c = Vector3.new(customer.X, 0, customer.Z).Unit
	local up = slot.UpVector
	return math.deg(math.atan2(up:Dot(-c), up.Y))
end

-- Dev check: nil when fine, else a reason.
function Pose.CheckSlot(slot: CFrame, customer: Vector3, groupLean: number?): string?
	local c = Vector3.new(customer.X, 0, customer.Z).Unit
	local facing = -slot.RightVector
	if Vector3.new(facing.X, 0, facing.Z).Unit:Dot(c) < Config.AssertDot then
		return "not facing the customer"
	end
	if
		groupLean
		and math.abs(Pose.LeanDegrees(slot, customer) - groupLean)
			> Config.AssertLeanToleranceDegrees
	then
		return "lean differs from its group"
	end
	if slot.LookVector:Dot(c:Cross(Vector3.yAxis)) < Config.AssertDot then
		return "rail does not run to the customer's left"
	end
	return nil
end

return table.freeze(Pose)
