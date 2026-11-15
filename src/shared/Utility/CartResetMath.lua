--!strict

local CartResetMath = {}

local HEADING_EPSILON = 1e-4

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function flattenHeading(direction: Vector3): Vector3?
	if not isFiniteVector3(direction) then
		return nil
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	local magnitude = flat.Magnitude

	if not isFiniteNumber(magnitude) or magnitude <= HEADING_EPSILON then
		return nil
	end

	local unit = flat / magnitude

	return if isFiniteVector3(unit) then unit else nil
end

CartResetMath.FlattenHeading = flattenHeading

function CartResetMath.ResolveSpawnCFrame(spawnCFrame: CFrame, currentCFrame: CFrame): CFrame
	local heading = flattenHeading(currentCFrame.LookVector)
		or flattenHeading(spawnCFrame.LookVector)
		or Vector3.new(0, 0, -1)
	local position = spawnCFrame.Position

	return CFrame.lookAt(position, position + heading, Vector3.yAxis)
end

return table.freeze(CartResetMath)
