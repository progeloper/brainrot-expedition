--!strict
-- Static navigation visibility is distinct from current-region creature detail.
-- This policy never grants access, changes collision or loads a missing asset.
local Policy = {}
Policy.ReleaseMarginStuds = 32
Policy.ReleaseGraceSeconds = 1
local mandatoryRoles =
	{ Floor = true, Road = true, Ramp = true, Stairs = true, Stair = true, Platform = true, Gate = true, Wall = true, Boundary = true, BoundaryWall = true, WallFacade = true }

function Policy.DistanceToBounds(position: Vector3, frame: CFrame, size: Vector3): number
	local point = frame:PointToObjectSpace(position)
	local half = size / 2
	return Vector3.new(
		math.max(math.abs(point.X) - half.X, 0),
		math.max(math.abs(point.Y) - half.Y, 0),
		math.max(math.abs(point.Z) - half.Z, 0)
	).Magnitude
end

function Policy.ProtectedRadius(captureRange: number, travelSpeed: number, stoppingDistance: number): number
	local function nonnegative(value)
		return if type(value) == "number"
				and value == value
				and math.abs(value) < math.huge
			then math.max(value, 0)
			else 0
	end
	return math.max(
		nonnegative(captureRange) + 32,
		nonnegative(travelSpeed) * 2 + nonnegative(stoppingDistance) + 32,
		128
	)
end

function Policy.Classify(instance: Instance): (boolean, boolean, string?)
	local part = if instance:IsA("BasePart") then instance else instance:FindFirstAncestorWhichIsA("BasePart")
	local cursor: Instance? = instance
	local mandatory = false
	local classification: string? = nil
	local inMap = false
	while cursor and cursor ~= workspace do
		local role = cursor:GetAttribute("LayoutRole")
		classification=classification or cursor:GetAttribute("PresentationClass")
		mandatory = mandatory
			or mandatoryRoles[role] == true
			or cursor:GetAttribute("PresentationClass") == "MandatoryGameplay"
		if cursor.Name == "MapBlockout" then
			inMap = true
			break
		end
		cursor = cursor.Parent
	end
	-- Existing map construction already separates noninteractive art from solid
	-- authored traversal geometry. Locked regions are checked by the caller.
	mandatory = mandatory or (inMap and part ~= nil and part.Anchored and part.CanCollide)
	if classification=="CriticalBoundary"or classification=="CriticalRoute"then mandatory=true
	elseif classification=="RegionDetail"then mandatory=false end
	return inMap, inMap and mandatory, classification
end

function Policy.StaticVisible(
	regionId: string?,
	current: string?,
	unlocked: { [string]: boolean },
	mandatory: boolean,
	distance: number,
	radius: number,
	classification: string?
): boolean
	if classification=="CriticalBoundary"or classification=="CriticalRoute"then return true end
	if regionId == nil then
		return true
	end
	if unlocked[regionId] ~= true then
		return mandatory and distance <= radius
	end
	return mandatory or regionId == current or distance <= radius
end

-- Only the caller's already-authorized optional scenery uses this local state.
-- Region/owner/capacity invalidation bypasses it and fails closed immediately.
function Policy.OptionalVisible(
	visible: boolean,
	releaseAt: number?,
	distance: number,
	radius: number,
	now: number
): (boolean, number?)
	if distance <= radius then
		return true, nil
	end
	if not visible then
		return false, nil
	end
	if distance <= radius + math.max(Policy.ReleaseMarginStuds,radius*0.25) then
		return true, nil
	end
	if releaseAt == nil then
		return true, now + Policy.ReleaseGraceSeconds
	end
	if now < releaseAt then
		return true, releaseAt
	end
	return false, nil
end
return table.freeze(Policy)
