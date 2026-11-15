--!strict
local Boundary = {}
local cachedSurfaces: { [Model]: any } = setmetatable({}, { __mode = "k" })

local function finitePosition(position: any): boolean
	return typeof(position) == "Vector3" and position.X == position.X and position.Y == position.Y and position.Z == position.Z
		and math.abs(position.X) < math.huge and math.abs(position.Y) < math.huge and math.abs(position.Z) < math.huge
end

function Boundary.Contains(zone: any, position: any): boolean
	if typeof(zone) ~= "Instance" or not zone:IsA("BasePart") or not zone.Anchored or typeof(position) ~= "Vector3" then return false end
	if not finitePosition(position) then return false end
	local point = zone.CFrame:PointToObjectSpace(position)
	return math.abs(point.X) <= zone.Size.X / 2 and math.abs(point.Y) <= zone.Size.Y / 2 and math.abs(point.Z) <= zone.Size.Z / 2
end

function Boundary.Qualifies(base: Model, baseId: string, ownerPosition: Vector3, cartPosition: Vector3): boolean
	local zone = Boundary.FindZone(base, baseId)
	if not zone or not Boundary.Contains(zone, cartPosition) or not finitePosition(ownerPosition) then return false end
	if Boundary.Contains(zone, ownerPosition) then return true end
	-- PlayerSpawn stands on the existing CartRamp outside the cart-return zone.
	-- Reuse the four explicit native plot surfaces, not the house/art bounds or
	-- generic Camp. Only their X/Z footprints expand the owner boundary; the
	-- existing return zone still owns its vertical interval and cart boundary.
	local zonePoint = zone.CFrame:PointToObjectSpace(ownerPosition)
	if math.abs(zonePoint.Y) > zone.Size.Y / 2 then return false end
	local surfaces = cachedSurfaces[base]
	if not surfaces then
		surfaces = {}
		for _, name in { "Foundation", "CartDisplay", "CartRamp", "HouseRamp" } do
			local part = base:FindFirstChild(name)
			if part and part:IsA("BasePart") and part.Anchored then table.insert(surfaces, part) end
		end
		cachedSurfaces[base] = surfaces
	end
	for _, part in surfaces do
		if part.Parent ~= base or not part.Anchored then continue end
		local point = part.CFrame:PointToObjectSpace(ownerPosition)
		if math.abs(point.X) <= part.Size.X / 2 and math.abs(point.Z) <= part.Size.Z / 2 then return true end
	end
	return false
end

function Boundary.FindZone(base: Model, baseId: string): BasePart?
	-- Reuse the installed cart-return descriptor. Native foundation/art bounds
	-- omit the cart pad and do not own the gameplay refill boundary.
	local zone = base:FindFirstChild("DepositReturnZone")
	return if zone and zone:IsA("BasePart") and zone.Anchored and zone:GetAttribute("BaseId") == baseId then zone else nil
end

return table.freeze(Boundary)
