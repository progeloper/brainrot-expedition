--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safety = require(ReplicatedStorage.Shared.Config.CartStabilitySafety)

local CartStabilityProfileValidator = {}

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

type NumberRule = {
	Field: string,
	Minimum: number,
	Maximum: number,
	Expected: string,
}

type StabilityCandidate = { [string]: any }

local BASE_COMPONENT = "CartStabilityProfileValidator.Base"
local EFFECTIVE_COMPONENT = "CartStabilityProfileValidator.Effective"

local function numberRule(field: string, minimum: number, maximum: number): NumberRule
	return {
		Field = field,
		Minimum = minimum,
		Maximum = maximum,
		Expected = string.format("finite number in [%g, %g]", minimum, maximum),
	}
end

local RULES: { NumberRule } = {
	numberRule(
		"OrientationErrorDeadZoneDegrees",
		Safety.MinimumOrientationErrorDeadZoneDegrees,
		Safety.MaximumOrientationErrorDeadZoneDegrees
	),
	numberRule(
		"FreeRollAngleDegrees",
		Safety.MinimumFreeAngleDegrees,
		Safety.MaximumFreeAngleDegrees
	),
	numberRule(
		"FreePitchAngleDegrees",
		Safety.MinimumFreeAngleDegrees,
		Safety.MaximumFreeAngleDegrees
	),
	numberRule(
		"ModerateRollAngleDegrees",
		Safety.MinimumModerateAngleDegrees,
		Safety.MaximumModerateAngleDegrees
	),
	numberRule(
		"ModeratePitchAngleDegrees",
		Safety.MinimumModerateAngleDegrees,
		Safety.MaximumModerateAngleDegrees
	),
	numberRule(
		"StrongRollAngleDegrees",
		Safety.MinimumStrongAngleDegrees,
		Safety.MaximumStrongAngleDegrees
	),
	numberRule(
		"StrongPitchAngleDegrees",
		Safety.MinimumStrongAngleDegrees,
		Safety.MaximumStrongAngleDegrees
	),
	numberRule("UprightStrength", Safety.MinimumUprightStrength, Safety.MaximumUprightStrength),
	numberRule(
		"RollCorrectionStrength",
		Safety.MinimumAxisCorrectionStrength,
		Safety.MaximumAxisCorrectionStrength
	),
	numberRule(
		"PitchCorrectionStrength",
		Safety.MinimumAxisCorrectionStrength,
		Safety.MaximumAxisCorrectionStrength
	),
	numberRule("RollDamping", Safety.MinimumAxisAngularDamping, Safety.MaximumAngularDamping),
	numberRule("PitchDamping", Safety.MinimumAxisAngularDamping, Safety.MaximumAngularDamping),
	numberRule(
		"MaxCorrectiveTorque",
		Safety.MinimumCorrectiveTorque,
		Safety.MaximumCorrectiveTorque
	),
	numberRule(
		"MaxCorrectiveAngularResponseDegreesPerSecond",
		Safety.MinimumCorrectiveAngularResponseDegreesPerSecond,
		Safety.MaximumCorrectiveAngularResponseDegreesPerSecond
	),
	numberRule("ResponseSpeed", Safety.MinimumResponseSpeed, Safety.MaximumResponseSpeed),
	numberRule(
		"StationaryAssistanceMultiplier",
		Safety.MinimumAssistanceMultiplier,
		Safety.MaximumAssistanceMultiplier
	),
	numberRule(
		"DrivingAssistanceMultiplier",
		Safety.MinimumAssistanceMultiplier,
		Safety.MaximumAssistanceMultiplier
	),
	numberRule(
		"SevereTiltRecoveryMultiplier",
		Safety.MinimumSevereTiltRecoveryMultiplier,
		Safety.MaximumSevereTiltRecoveryMultiplier
	),
	numberRule(
		"ExtremeYawDamping",
		Safety.MinimumExtremeYawDamping,
		Safety.MaximumExtremeYawDamping
	),
	numberRule(
		"ExtremeYawThresholdDegreesPerSecond",
		Safety.MinimumExtremeYawThresholdDegreesPerSecond,
		Safety.MaximumExtremeYawThresholdDegreesPerSecond
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
): ({ string }, StabilityCandidate?)
	local errors: { string } = {}

	if type(candidate) ~= "table" then
		addError(errors, component, cartId, "<profile>", candidate, "table")
		return errors, nil
	end

	local data = candidate :: StabilityCandidate

	if type(data.Enabled) ~= "boolean" then
		addError(errors, component, cartId, "Enabled", data.Enabled, "boolean")
	end

	for _, rule in RULES do
		local value = data[rule.Field]

		if not isFiniteNumber(value) or value < rule.Minimum or value > rule.Maximum then
			addError(errors, component, cartId, rule.Field, value, rule.Expected)
		end
	end

	return errors, data
end

local function validateOrderedAngles(
	component: string,
	cartId: any,
	data: StabilityCandidate,
	errors: { string },
	axisName: string
)
	local freeField = string.format("Free%sAngleDegrees", axisName)
	local moderateField = string.format("Moderate%sAngleDegrees", axisName)
	local strongField = string.format("Strong%sAngleDegrees", axisName)
	local freeAngle = data[freeField]
	local moderateAngle = data[moderateField]
	local strongAngle = data[strongField]

	if
		isFiniteNumber(freeAngle)
		and isFiniteNumber(moderateAngle)
		and freeAngle >= moderateAngle
	then
		addError(
			errors,
			component,
			cartId,
			freeField,
			freeAngle,
			string.format("strictly less than %s", moderateField)
		)
	end

	if
		isFiniteNumber(moderateAngle)
		and isFiniteNumber(strongAngle)
		and moderateAngle >= strongAngle
	then
		addError(
			errors,
			component,
			cartId,
			moderateField,
			moderateAngle,
			string.format("strictly less than %s", strongField)
		)
	end
end

local function validateRelationships(
	component: string,
	cartId: any,
	data: StabilityCandidate,
	errors: { string }
)
	local deadZone = data.OrientationErrorDeadZoneDegrees

	for _, freeField in { "FreeRollAngleDegrees", "FreePitchAngleDegrees" } do
		local freeAngle = data[freeField]

		if isFiniteNumber(deadZone) and isFiniteNumber(freeAngle) and deadZone > freeAngle then
			addError(
				errors,
				component,
				cartId,
				"OrientationErrorDeadZoneDegrees",
				deadZone,
				string.format("less than or equal to %s", freeField)
			)
		end
	end

	validateOrderedAngles(component, cartId, data, errors, "Roll")
	validateOrderedAngles(component, cartId, data, errors, "Pitch")

	if
		isFiniteNumber(data.ExtremeYawDamping)
		and data.ExtremeYawDamping > 0
		and isFiniteNumber(data.ExtremeYawThresholdDegreesPerSecond)
		and isFiniteNumber(data.MaxCorrectiveAngularResponseDegreesPerSecond)
		and data.ExtremeYawThresholdDegreesPerSecond
			<= data.MaxCorrectiveAngularResponseDegreesPerSecond
	then
		addError(
			errors,
			component,
			cartId,
			"ExtremeYawThresholdDegreesPerSecond",
			data.ExtremeYawThresholdDegreesPerSecond,
			"strictly greater than MaxCorrectiveAngularResponseDegreesPerSecond when extreme-yaw damping is enabled"
		)
	end
end

function CartStabilityProfileValidator.ValidateBase(cartId: any, candidate: any): ValidationResult
	local errors, data = validateFields(BASE_COMPONENT, cartId, candidate)

	if data ~= nil then
		validateRelationships(BASE_COMPONENT, cartId, data, errors)
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

function CartStabilityProfileValidator.ValidateEffective(
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

function CartStabilityProfileValidator.AssertValidBase(cartId: any, candidate: any)
	local result = CartStabilityProfileValidator.ValidateBase(cartId, candidate)

	if not result.IsValid then
		error(table.concat(result.Errors, "\n"), 2)
	end
end

function CartStabilityProfileValidator.AssertValidEffective(cartId: any, candidate: any)
	local result = CartStabilityProfileValidator.ValidateEffective(cartId, candidate)

	if not result.IsValid then
		error(table.concat(result.Errors, "\n"), 2)
	end
end

return CartStabilityProfileValidator
