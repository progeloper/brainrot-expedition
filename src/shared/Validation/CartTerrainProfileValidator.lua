--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safety = require(ReplicatedStorage.Shared.Config.CartTerrainSafety)

local CartTerrainProfileValidator = {}

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

type NumberRule = {
	Field: string,
	Minimum: number,
	Maximum: number,
	Expected: string,
	Integer: boolean?,
}

type TerrainCandidate = { [string]: any }

local BASE_COMPONENT = "CartTerrainProfileValidator.Base"
local EFFECTIVE_COMPONENT = "CartTerrainProfileValidator.Effective"

local function numberRule(
	field: string,
	minimum: number,
	maximum: number,
	integer: boolean?
): NumberRule
	local valueKind = if integer then "integer" else "finite number"

	return {
		Field = field,
		Minimum = minimum,
		Maximum = maximum,
		Expected = string.format("%s in [%g, %g]", valueKind, minimum, maximum),
		Integer = integer,
	}
end

local RULES: { NumberRule } = {
	numberRule(
		"ProbeOriginHeight",
		Safety.MinimumProbeOriginHeight,
		Safety.MaximumProbeOriginHeight
	),
	numberRule(
		"GroundDetectionDistance",
		Safety.MinimumGroundDetectionDistance,
		Safety.MaximumGroundDetectionDistance
	),
	numberRule("MaximumSupportGap", Safety.MinimumSupportGap, Safety.MaximumSupportGap),
	numberRule(
		"MaximumSupportPenetration",
		Safety.MinimumSupportPenetration,
		Safety.MaximumSupportPenetration
	),
	numberRule("LateralProbeFraction", Safety.MinimumProbeFraction, Safety.MaximumProbeFraction),
	numberRule("ForwardProbeFraction", Safety.MinimumProbeFraction, Safety.MaximumProbeFraction),
	numberRule(
		"FullGroundedHitCount",
		Safety.MinimumFullGroundedHitCount,
		Safety.MaximumFullGroundedHitCount,
		true
	),
	numberRule(
		"GroundedReacquireDelay",
		Safety.MinimumGroundedTransitionDelay,
		Safety.MaximumGroundedTransitionDelay
	),
	numberRule(
		"AirborneDelay",
		Safety.MinimumGroundedTransitionDelay,
		Safety.MaximumGroundedTransitionDelay
	),
	numberRule(
		"NormalResponseSpeed",
		Safety.MinimumNormalResponseSpeed,
		Safety.MaximumNormalResponseSpeed
	),
	numberRule(
		"MaximumNormalChangeDegreesPerSecond",
		Safety.MinimumNormalChangeDegreesPerSecond,
		Safety.MaximumNormalChangeDegreesPerSecond
	),
	numberRule(
		"AirborneWorldUpResponseSpeed",
		Safety.MinimumAirborneWorldUpResponseSpeed,
		Safety.MaximumAirborneWorldUpResponseSpeed
	),
	numberRule(
		"NormalOutlierAngleDegrees",
		Safety.MinimumNormalOutlierAngleDegrees,
		Safety.MaximumNormalOutlierAngleDegrees
	),
	numberRule(
		"SlopeEffectStartDegrees",
		Safety.MinimumSlopeEffectStartDegrees,
		Safety.MaximumSlopeEffectStartDegrees
	),
	numberRule(
		"FullSlopeEffectDegrees",
		Safety.MinimumFullSlopeEffectDegrees,
		Safety.MaximumFullSlopeEffectDegrees
	),
	numberRule(
		"MaximumClimbAngleDegrees",
		Safety.MinimumClimbAngleDegrees,
		Safety.MaximumClimbAngleDegrees
	),
	numberRule(
		"MaximumGroundAngleDegrees",
		Safety.MinimumGroundAngleDegrees,
		Safety.MaximumGroundAngleDegrees
	),
	numberRule(
		"MaximumUphillAccelerationReduction",
		Safety.MinimumUphillAccelerationReduction,
		Safety.MaximumUphillAccelerationReduction
	),
	numberRule(
		"MaximumDownhillAcceleration",
		Safety.MinimumDownhillAcceleration,
		Safety.MaximumDownhillAcceleration
	),
	numberRule(
		"MaximumDownhillCoastReduction",
		Safety.MinimumDownhillCoastReduction,
		Safety.MaximumDownhillCoastReduction
	),
	numberRule(
		"PartialSupportStabilityMultiplier",
		Safety.MinimumStabilityMultiplier,
		Safety.MaximumStabilityMultiplier
	),
	numberRule(
		"AirborneStabilityMultiplier",
		Safety.MinimumStabilityMultiplier,
		Safety.MaximumStabilityMultiplier
	),
	numberRule("DrivenSampleRate", Safety.MinimumSampleRate, Safety.MaximumSampleRate),
	numberRule("ServerMovingSampleRate", Safety.MinimumSampleRate, Safety.MaximumSampleRate),
	numberRule("ServerSettledSampleRate", Safety.MinimumSampleRate, Safety.MaximumSampleRate),
	numberRule(
		"ServerSettledSpeedThreshold",
		Safety.MinimumSettledSpeedThreshold,
		Safety.MaximumSettledSpeedThreshold
	),
}

table.freeze(RULES)

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function formatValue(value: any): string
	if type(value) == "number" then
		if value ~= value then
			return "NaN"
		elseif value == math.huge then
			return "+infinity"
		elseif value == -math.huge then
			return "-infinity"
		end
	end

	return string.format("%s (%s)", tostring(value), type(value))
end

local function addError(
	errors: { string },
	component: string,
	cartId: any,
	field: string,
	value: any,
	expected: string
)
	table.insert(
		errors,
		string.format(
			"[%s] CartId=%s Field=%s Value=%s Expected=%s",
			component,
			tostring(cartId),
			field,
			formatValue(value),
			expected
		)
	)
end

local function validateFields(
	component: string,
	cartId: any,
	candidate: any
): ({ string }, TerrainCandidate?)
	local errors: { string } = {}

	if type(candidate) ~= "table" then
		addError(errors, component, cartId, "<profile>", candidate, "table")
		return errors, nil
	end

	local data = candidate :: TerrainCandidate

	if type(data.Enabled) ~= "boolean" then
		addError(errors, component, cartId, "Enabled", data.Enabled, "boolean")
	end

	for _, rule in RULES do
		local value = data[rule.Field]
		local integerIsInvalid = rule.Integer == true and isFiniteNumber(value) and value % 1 ~= 0

		if
			not isFiniteNumber(value)
			or value < rule.Minimum
			or value > rule.Maximum
			or integerIsInvalid
		then
			addError(errors, component, cartId, rule.Field, value, rule.Expected)
		end
	end

	return errors, data
end

local function validateLessThan(
	component: string,
	cartId: any,
	data: TerrainCandidate,
	errors: { string },
	lowerField: string,
	upperField: string,
	allowEqual: boolean
)
	local lower = data[lowerField]
	local upper = data[upperField]

	if not isFiniteNumber(lower) or not isFiniteNumber(upper) then
		return
	end

	local isInvalid = if allowEqual then lower > upper else lower >= upper

	if isInvalid then
		local relationship = if allowEqual then "less than or equal to" else "strictly less than"

		addError(
			errors,
			component,
			cartId,
			lowerField,
			lower,
			string.format("%s %s", relationship, upperField)
		)
	end
end

local function validateRelationships(
	component: string,
	cartId: any,
	data: TerrainCandidate,
	errors: { string }
)
	validateLessThan(
		component,
		cartId,
		data,
		errors,
		"MaximumSupportGap",
		"GroundDetectionDistance",
		true
	)
	validateLessThan(
		component,
		cartId,
		data,
		errors,
		"MaximumSupportPenetration",
		"MaximumSupportGap",
		true
	)
	validateLessThan(
		component,
		cartId,
		data,
		errors,
		"SlopeEffectStartDegrees",
		"FullSlopeEffectDegrees",
		false
	)
	validateLessThan(
		component,
		cartId,
		data,
		errors,
		"FullSlopeEffectDegrees",
		"MaximumClimbAngleDegrees",
		true
	)
	validateLessThan(
		component,
		cartId,
		data,
		errors,
		"MaximumClimbAngleDegrees",
		"MaximumGroundAngleDegrees",
		false
	)
	validateLessThan(
		component,
		cartId,
		data,
		errors,
		"ServerSettledSampleRate",
		"ServerMovingSampleRate",
		true
	)
	validateLessThan(
		component,
		cartId,
		data,
		errors,
		"ServerMovingSampleRate",
		"DrivenSampleRate",
		true
	)
	validateLessThan(
		component,
		cartId,
		data,
		errors,
		"AirborneStabilityMultiplier",
		"PartialSupportStabilityMultiplier",
		true
	)
end

function CartTerrainProfileValidator.ValidateBase(cartId: any, candidate: any): ValidationResult
	local errors, data = validateFields(BASE_COMPONENT, cartId, candidate)

	if data ~= nil then
		validateRelationships(BASE_COMPONENT, cartId, data, errors)
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

function CartTerrainProfileValidator.ValidateEffective(
	cartId: any,
	candidate: any
): ValidationResult
	local errors, data = validateFields(EFFECTIVE_COMPONENT, cartId, candidate)

	if data ~= nil then
		if type(data.CartId) ~= "string" or data.CartId == "" or data.CartId ~= cartId then
			addError(
				errors,
				EFFECTIVE_COMPONENT,
				cartId,
				"CartId",
				data.CartId,
				"non-empty string matching the resolved CartId"
			)
		end

		validateRelationships(EFFECTIVE_COMPONENT, cartId, data, errors)
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

function CartTerrainProfileValidator.AssertValidBase(cartId: any, candidate: any)
	local result = CartTerrainProfileValidator.ValidateBase(cartId, candidate)

	if not result.IsValid then
		error(table.concat(result.Errors, "\n"), 2)
	end
end

function CartTerrainProfileValidator.AssertValidEffective(cartId: any, candidate: any)
	local result = CartTerrainProfileValidator.ValidateEffective(cartId, candidate)

	if not result.IsValid then
		error(table.concat(result.Errors, "\n"), 2)
	end
end

return CartTerrainProfileValidator
