--!strict

local VECTOR_EPSILON = 1e-6
local ANGLE_EPSILON = 1e-7

local CartTerrainMath = {}

export type GroundState = "Grounded" | "Partial" | "Airborne"

export type SlopeProfile = {
	SlopeEffectStartDegrees: number,
	FullSlopeEffectDegrees: number,
	MaximumUphillAccelerationReduction: number,
	MaximumDownhillAcceleration: number,
	MaximumDownhillCoastReduction: number,
}

export type SlopeInfluence = {
	ResponseStrength: number,
	AccelerationMultiplier: number,
	DownhillAcceleration: number,
	CoastMultiplier: number,
}

local FLAT_SLOPE_INFLUENCE: SlopeInfluence = table.freeze({
	ResponseStrength = 0,
	AccelerationMultiplier = 1,
	DownhillAcceleration = 0,
	CoastMultiplier = 1,
})

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function resolveUnit(value: Vector3, fallback: Vector3): Vector3
	if isFiniteVector3(value) and value.Magnitude > VECTOR_EPSILON then
		return value.Unit
	end

	if isFiniteVector3(fallback) and fallback.Magnitude > VECTOR_EPSILON then
		return fallback.Unit
	end

	return Vector3.yAxis
end

local function getDeterministicPerpendicular(unitNormal: Vector3): Vector3
	local preferred = if math.abs(unitNormal:Dot(-Vector3.zAxis)) < 0.95
		then -Vector3.zAxis
		else Vector3.xAxis
	local projected = CartTerrainMath.ProjectOntoPlane(preferred, unitNormal)

	if projected.Magnitude <= VECTOR_EPSILON then
		projected = CartTerrainMath.ProjectOntoPlane(Vector3.yAxis, unitNormal)
	end

	return resolveUnit(projected, Vector3.xAxis)
end

local function getAngleRadians(first: Vector3, second: Vector3): number
	return math.acos(math.clamp(first:Dot(second), -1, 1))
end

local function rotateUnitAroundAxis(
	value: Vector3,
	unitAxis: Vector3,
	angleRadians: number
): Vector3
	local cosine = math.cos(angleRadians)
	local sine = math.sin(angleRadians)
	local rotated = value * cosine
		+ unitAxis:Cross(value) * sine
		+ unitAxis * unitAxis:Dot(value) * (1 - cosine)

	return resolveUnit(rotated, value)
end

local function smoothStep(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)

	return clamped * clamped * (3 - 2 * clamped)
end

local function normalizedGroundState(state: GroundState): GroundState
	if state == "Grounded" or state == "Partial" or state == "Airborne" then
		return state
	end

	return "Airborne"
end

local function normalizedElapsed(value: number): number
	return if isFiniteNumber(value) then math.max(value, 0) else 0
end

function CartTerrainMath.ProjectOntoPlane(value: Vector3, normal: Vector3): Vector3
	if not isFiniteVector3(value) or not isFiniteVector3(normal) then
		return Vector3.zero
	end

	local normalMagnitude = normal.Magnitude

	if normalMagnitude <= VECTOR_EPSILON then
		return Vector3.zero
	end

	local unitNormal = normal / normalMagnitude
	local projected = value - unitNormal * value:Dot(unitNormal)

	return if isFiniteVector3(projected) then projected else Vector3.zero
end

function CartTerrainMath.BuildTangentFrame(
	forward: Vector3,
	desiredUp: Vector3,
	fallback: Vector3?
): (Vector3, Vector3)
	local up = resolveUnit(desiredUp, Vector3.yAxis)
	local tangentForward = CartTerrainMath.ProjectOntoPlane(forward, up)

	if tangentForward.Magnitude <= VECTOR_EPSILON and fallback ~= nil then
		tangentForward = CartTerrainMath.ProjectOntoPlane(fallback, up)
	end

	if tangentForward.Magnitude <= VECTOR_EPSILON then
		tangentForward = getDeterministicPerpendicular(up)
	else
		tangentForward = tangentForward.Unit
	end

	local tangentRight = resolveUnit(tangentForward:Cross(up), Vector3.xAxis)

	tangentForward = resolveUnit(up:Cross(tangentRight), tangentForward)

	return tangentForward, tangentRight
end

function CartTerrainMath.RotateHeading(
	heading: Vector3,
	desiredUp: Vector3,
	angleRadians: number,
	fallback: Vector3?
): Vector3
	local up = resolveUnit(desiredUp, Vector3.yAxis)
	local tangentHeading = CartTerrainMath.BuildTangentFrame(heading, up, fallback)

	if not isFiniteNumber(angleRadians) or math.abs(angleRadians) <= ANGLE_EPSILON then
		return tangentHeading
	end

	return rotateUnitAroundAxis(tangentHeading, up, angleRadians)
end

function CartTerrainMath.CombineGroundNormals(
	normals: { Vector3 },
	worldUp: Vector3,
	maxGroundAngleDegrees: number,
	outlierAngleDegrees: number
): (Vector3?, number)
	if
		not isFiniteNumber(maxGroundAngleDegrees)
		or not isFiniteNumber(outlierAngleDegrees)
		or maxGroundAngleDegrees < 0
		or outlierAngleDegrees < 0
	then
		return nil, 0
	end

	local up = resolveUnit(worldUp, Vector3.yAxis)
	local maximumGroundAngle = math.rad(math.min(maxGroundAngleDegrees, 180))
	local maximumOutlierAngle = math.rad(math.min(outlierAngleDegrees, 180))
	local candidates: { Vector3 } = {}

	for _, normal in normals do
		if isFiniteVector3(normal) and normal.Magnitude > VECTOR_EPSILON then
			local unitNormal = normal.Unit

			if getAngleRadians(unitNormal, up) <= maximumGroundAngle + ANGLE_EPSILON then
				table.insert(candidates, unitNormal)
			end
		end
	end

	if #candidates == 0 then
		return nil, 0
	end

	table.sort(candidates, function(first: Vector3, second: Vector3): boolean
		if first.X ~= second.X then
			return first.X < second.X
		elseif first.Y ~= second.Y then
			return first.Y < second.Y
		end

		return first.Z < second.Z
	end)

	local bestCluster: { Vector3 } = {}
	local bestAlignment = -math.huge

	for _, seed in candidates do
		local cluster: { Vector3 } = {}
		local alignment = 0

		for _, candidate in candidates do
			if getAngleRadians(seed, candidate) <= maximumOutlierAngle + ANGLE_EPSILON then
				table.insert(cluster, candidate)
				alignment += candidate:Dot(up)
			end
		end

		if #cluster > #bestCluster or (#cluster == #bestCluster and alignment > bestAlignment) then
			bestCluster = cluster
			bestAlignment = alignment
		end
	end

	local clusterSum = Vector3.zero

	for _, candidate in bestCluster do
		clusterSum += candidate
	end

	local clusterAverage = resolveUnit(clusterSum, bestCluster[1])
	local accepted: { Vector3 } = {}

	for _, candidate in bestCluster do
		if getAngleRadians(candidate, clusterAverage) <= maximumOutlierAngle + ANGLE_EPSILON then
			table.insert(accepted, candidate)
		end
	end

	if #accepted == 0 then
		return nil, 0
	end

	local acceptedSum = Vector3.zero

	for _, candidate in accepted do
		acceptedSum += candidate
	end

	return resolveUnit(acceptedSum, accepted[1]), #accepted
end

function CartTerrainMath.GetSlopeAngleDegrees(surfaceNormal: Vector3, worldUp: Vector3?): number
	if not isFiniteVector3(surfaceNormal) or surfaceNormal.Magnitude <= VECTOR_EPSILON then
		return 0
	end

	local up = resolveUnit(worldUp or Vector3.yAxis, Vector3.yAxis)

	return math.deg(getAngleRadians(surfaceNormal.Unit, up))
end

function CartTerrainMath.SmoothDesiredUp(
	previous: Vector3,
	target: Vector3,
	responseSpeed: number,
	maxDegreesPerSecond: number,
	deltaTime: number
): Vector3
	local previousUp = resolveUnit(previous, Vector3.yAxis)

	if
		not isFiniteVector3(target)
		or target.Magnitude <= VECTOR_EPSILON
		or not isFiniteNumber(responseSpeed)
		or not isFiniteNumber(maxDegreesPerSecond)
		or not isFiniteNumber(deltaTime)
		or responseSpeed <= 0
		or maxDegreesPerSecond <= 0
		or deltaTime <= 0
	then
		return previousUp
	end

	local targetUp = target.Unit
	local angle = getAngleRadians(previousUp, targetUp)

	if angle <= ANGLE_EPSILON then
		return targetUp
	end

	local responseAlpha = 1 - math.exp(-responseSpeed * deltaTime)
	local responseStep = angle * responseAlpha
	local rateStep = math.rad(maxDegreesPerSecond) * deltaTime
	local step = math.min(angle, responseStep, rateStep)
	local cross = previousUp:Cross(targetUp)
	local axis = if cross.Magnitude > VECTOR_EPSILON
		then cross.Unit
		else getDeterministicPerpendicular(previousUp)

	return rotateUnitAroundAxis(previousUp, axis, step)
end

function CartTerrainMath.AdvanceGroundState(
	previousState: GroundState,
	fullElapsed: number,
	unsupportedElapsed: number,
	hitCount: number,
	fullHitCount: number,
	reacquireDelay: number,
	airborneDelay: number,
	deltaTime: number
): (GroundState, number, number)
	local state = normalizedGroundState(previousState)
	local nextFullElapsed = normalizedElapsed(fullElapsed)
	local nextUnsupportedElapsed = normalizedElapsed(unsupportedElapsed)
	local safeDeltaTime = if isFiniteNumber(deltaTime) and deltaTime > 0 then deltaTime else 0
	local requiredFullHits = if isFiniteNumber(fullHitCount)
		then math.max(math.floor(fullHitCount), 1)
		else 1
	local safeHitCount = if isFiniteNumber(hitCount) then math.max(math.floor(hitCount), 0) else 0
	local safeReacquireDelay = normalizedElapsed(reacquireDelay)
	local safeAirborneDelay = normalizedElapsed(airborneDelay)

	if safeHitCount >= requiredFullHits then
		nextUnsupportedElapsed = 0

		if state == "Grounded" then
			return "Grounded", 0, nextUnsupportedElapsed
		end

		nextFullElapsed += safeDeltaTime

		if nextFullElapsed >= safeReacquireDelay then
			return "Grounded", nextFullElapsed, nextUnsupportedElapsed
		end

		return "Partial", nextFullElapsed, nextUnsupportedElapsed
	elseif safeHitCount > 0 then
		return "Partial", 0, 0
	end

	nextFullElapsed = 0
	nextUnsupportedElapsed += safeDeltaTime

	if state == "Airborne" or nextUnsupportedElapsed >= safeAirborneDelay then
		return "Airborne", nextFullElapsed, nextUnsupportedElapsed
	end

	return "Partial", nextFullElapsed, nextUnsupportedElapsed
end

function CartTerrainMath.GetSignedSlopeDegrees(tangentForward: Vector3): number
	if not isFiniteVector3(tangentForward) or tangentForward.Magnitude <= VECTOR_EPSILON then
		return 0
	end

	return math.deg(math.asin(math.clamp(tangentForward.Unit.Y, -1, 1)))
end

function CartTerrainMath.GetSlopeInfluence(
	signedSlopeDegrees: number,
	profile: SlopeProfile
): SlopeInfluence
	if
		not isFiniteNumber(signedSlopeDegrees)
		or not isFiniteNumber(profile.SlopeEffectStartDegrees)
		or not isFiniteNumber(profile.FullSlopeEffectDegrees)
		or not isFiniteNumber(profile.MaximumUphillAccelerationReduction)
		or not isFiniteNumber(profile.MaximumDownhillAcceleration)
		or not isFiniteNumber(profile.MaximumDownhillCoastReduction)
	then
		return FLAT_SLOPE_INFLUENCE
	end

	local startAngle = math.max(profile.SlopeEffectStartDegrees, 0)
	local fullAngle = profile.FullSlopeEffectDegrees
	local slopeMagnitude = math.abs(signedSlopeDegrees)

	if fullAngle <= startAngle or slopeMagnitude <= startAngle then
		return FLAT_SLOPE_INFLUENCE
	end

	local responseStrength = smoothStep((slopeMagnitude - startAngle) / (fullAngle - startAngle))

	if signedSlopeDegrees > 0 then
		return {
			ResponseStrength = responseStrength,
			AccelerationMultiplier = 1
				- math.clamp(profile.MaximumUphillAccelerationReduction, 0, 1)
					* responseStrength,
			DownhillAcceleration = 0,
			CoastMultiplier = 1,
		}
	end

	return {
		ResponseStrength = responseStrength,
		AccelerationMultiplier = 1,
		DownhillAcceleration = math.max(profile.MaximumDownhillAcceleration, 0) * responseStrength,
		CoastMultiplier = 1
			- math.clamp(profile.MaximumDownhillCoastReduction, 0, 1) * responseStrength,
	}
end

return CartTerrainMath
