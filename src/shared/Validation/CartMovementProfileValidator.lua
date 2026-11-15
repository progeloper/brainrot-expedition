--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safety = require(ReplicatedStorage.Shared.Config.CartMovementSafety)

local CartMovementProfileValidator = {}

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

type NumberRule = {
	Field: string,
	Minimum: number,
	Maximum: number,
	MinimumInclusive: boolean,
	Expected: string,
}

type MovementCandidate = { [string]: any }

local BASE_COMPONENT = "CartMovementProfileValidator.Base"
local EFFECTIVE_COMPONENT = "CartMovementProfileValidator.Effective"

local function numberRule(field: string, minimum: number, maximum: number, minimumInclusive: boolean?): NumberRule
	local inclusive = minimumInclusive ~= false

	return {
		Field = field,
		Minimum = minimum,
		Maximum = maximum,
		MinimumInclusive = inclusive,
		Expected = string.format(
			if inclusive then "finite number in [%g, %g]" else "finite number in (%g, %g]",
			minimum,
			maximum
		),
	}
end

local BASE_RULES: { NumberRule } = {
	numberRule("HuntingSpeed", Safety.MinimumHuntingSpeed, Safety.MaximumHuntingSpeed),
	numberRule("MaxTravelSpeed", Safety.MinimumTravelSpeed, Safety.MaximumTravelSpeed),
	numberRule("ForwardAcceleration", Safety.MinimumAcceleration, Safety.MaximumAcceleration),
	numberRule(
		"HighSpeedAccelerationMultiplier",
		Safety.MinimumAccelerationMultiplier,
		Safety.MaximumAccelerationMultiplier
	),
	numberRule("AccelerationCurveExponent", Safety.MinimumCurveExponent, Safety.MaximumCurveExponent),
	numberRule("CoastDeceleration", Safety.MinimumCoastDeceleration, Safety.MaximumCoastDeceleration),
	numberRule(
		"HighSpeedCoastDecelerationMultiplier",
		Safety.MinimumDecelerationMultiplier,
		Safety.MaximumDecelerationMultiplier
	),
	numberRule("Braking", Safety.MinimumBraking, Safety.MaximumBraking),
	numberRule("HighSpeedBrakingMultiplier", Safety.MinimumBrakingMultiplier, Safety.MaximumBrakingMultiplier),
	numberRule("RecoveryBackupSpeed", Safety.MinimumRecoveryBackupSpeed, Safety.MaximumRecoveryBackupSpeed),
	numberRule(
		"RecoveryBackupAcceleration",
		Safety.MinimumRecoveryBackupAcceleration,
		Safety.MaximumRecoveryBackupAcceleration
	),
	numberRule(
		"RecoveryBackupDeceleration",
		Safety.MinimumRecoveryBackupDeceleration,
		Safety.MaximumRecoveryBackupDeceleration
	),
	numberRule("RecoveryInputDelay", Safety.MinimumRecoveryInputDelay, Safety.MaximumRecoveryInputDelay),
	numberRule("NearZeroSpeedThreshold", Safety.MinimumNearZeroSpeedThreshold, Safety.MaximumNearZeroSpeedThreshold),
	numberRule(
		"LongitudinalInputDeadzone",
		Safety.MinimumLongitudinalInputDeadzone,
		Safety.MaximumLongitudinalInputDeadzone
	),
	numberRule(
		"LongitudinalTransitionRetryInterval",
		Safety.MinimumLongitudinalTransitionRetryInterval,
		Safety.MaximumLongitudinalTransitionRetryInterval
	),
	numberRule(
		"LongitudinalTransitionMaximumRetryInterval",
		Safety.MinimumLongitudinalTransitionMaximumRetryInterval,
		Safety.MaximumLongitudinalTransitionMaximumRetryInterval
	),
	numberRule("TurnRate", Safety.MinimumTurnRate, Safety.MaximumTurnRate),
	numberRule(
		"StationarySteeringThreshold",
		Safety.MinimumSteeringSpeedThreshold,
		Safety.MaximumSteeringSpeedThreshold
	),
	numberRule("LowSpeedSteeringMultiplier", Safety.MinimumSteeringMultiplier, Safety.MaximumSteeringMultiplier),
	numberRule("HighSpeedSteeringMultiplier", Safety.MinimumSteeringMultiplier, Safety.MaximumSteeringMultiplier),
	numberRule(
		"SteeringInterpolationExponent",
		Safety.MinimumSteeringInterpolationExponent,
		Safety.MaximumSteeringInterpolationExponent
	),
	numberRule("LateralGrip", Safety.MinimumLateralGrip, Safety.MaximumLateralGrip),
	numberRule(
		"HighSpeedLateralGripMultiplier",
		Safety.MinimumLateralGripMultiplier,
		Safety.MaximumLateralGripMultiplier
	),
	numberRule("DriveForceLimit", Safety.MinimumDriveForceLimit, Safety.MaximumDriveForceLimit),
	numberRule("UprightResponsiveness", Safety.MinimumUprightResponsiveness, Safety.MaximumUprightResponsiveness),
	numberRule("UprightTorque", Safety.MinimumUprightTorque, Safety.MaximumUprightTorque),
	numberRule("MaxAngularSpeed", Safety.MinimumAngularSpeed, Safety.MaximumAngularSpeed),
	numberRule("GroundFriction", Safety.MinimumGroundFriction, Safety.MaximumGroundFriction),
	numberRule("GroundFrictionWeight", Safety.MinimumGroundFrictionWeight, Safety.MaximumGroundFrictionWeight),
}

local EFFECTIVE_RULES: { NumberRule } = table.clone(BASE_RULES)
table.insert(EFFECTIVE_RULES, numberRule("ControlReferenceSpeed", Safety.MinimumTravelSpeed, Safety.MaximumTravelSpeed))

table.freeze(BASE_RULES)
table.freeze(EFFECTIVE_RULES)

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

local function addError(errors: { string }, component: string, cartId: any, field: string, value: any, expected: string)
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

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function validateNumberRules(
	component: string,
	cartId: any,
	candidate: any,
	rules: { NumberRule }
): ({ string }, MovementCandidate?)
	local errors: { string } = {}

	if type(candidate) ~= "table" then
		addError(errors, component, cartId, "<profile>", candidate, "table")
		return errors, nil
	end

	local data = candidate :: MovementCandidate

	for _, rule in rules do
		local value = data[rule.Field]

		if not isFiniteNumber(value) then
			addError(errors, component, cartId, rule.Field, value, rule.Expected)
			continue
		end

		local belowMinimum = if rule.MinimumInclusive then value < rule.Minimum else value <= rule.Minimum

		if belowMinimum or value > rule.Maximum then
			addError(errors, component, cartId, rule.Field, value, rule.Expected)
		end
	end

	return errors, data
end

local function validateRelationships(component: string, cartId: any, data: MovementCandidate, errors: { string })
	if
		isFiniteNumber(data.HuntingSpeed)
		and isFiniteNumber(data.MaxTravelSpeed)
		and data.HuntingSpeed >= data.MaxTravelSpeed
	then
		addError(errors, component, cartId, "HuntingSpeed", data.HuntingSpeed, "strictly less than MaxTravelSpeed")
	end

	if
		isFiniteNumber(data.HuntingSpeed)
		and isFiniteNumber(data.ControlReferenceSpeed)
		and data.HuntingSpeed >= data.ControlReferenceSpeed
	then
		addError(
			errors,
			component,
			cartId,
			"ControlReferenceSpeed",
			data.ControlReferenceSpeed,
			"strictly greater than HuntingSpeed"
		)
	end

	-- The Phase 13 response reference remains36 even for Reinforced's32.4
	-- travel baseline. The two positive, safety-bounded values are independent;
	-- a class or purchase ceiling must not rescale the controller's curves.

	if
		isFiniteNumber(data.RecoveryBackupSpeed)
		and isFiniteNumber(data.HuntingSpeed)
		and data.RecoveryBackupSpeed > data.HuntingSpeed * Safety.MaximumRecoveryToHuntingSpeedRatio
	then
		addError(
			errors,
			component,
			cartId,
			"RecoveryBackupSpeed",
			data.RecoveryBackupSpeed,
			string.format(
				"less than or equal to %.0f%% of HuntingSpeed",
				Safety.MaximumRecoveryToHuntingSpeedRatio * 100
			)
		)
	end

	if
		isFiniteNumber(data.LongitudinalTransitionMaximumRetryInterval)
		and isFiniteNumber(data.LongitudinalTransitionRetryInterval)
		and data.LongitudinalTransitionMaximumRetryInterval < data.LongitudinalTransitionRetryInterval
	then
		addError(
			errors,
			component,
			cartId,
			"LongitudinalTransitionMaximumRetryInterval",
			data.LongitudinalTransitionMaximumRetryInterval,
			"greater than or equal to LongitudinalTransitionRetryInterval"
		)
	end

	if isFiniteNumber(data.HighSpeedAccelerationMultiplier) and data.HighSpeedAccelerationMultiplier > 1 then
		addError(
			errors,
			component,
			cartId,
			"HighSpeedAccelerationMultiplier",
			data.HighSpeedAccelerationMultiplier,
			"at most 1; arcade acceleration does not decay above hunting pace"
		)
	end

	if
		isFiniteNumber(data.RecoveryBackupAcceleration)
		and isFiniteNumber(data.ForwardAcceleration)
		and data.RecoveryBackupAcceleration > data.ForwardAcceleration
	then
		addError(
			errors,
			component,
			cartId,
			"RecoveryBackupAcceleration",
			data.RecoveryBackupAcceleration,
			"less than or equal to ForwardAcceleration"
		)
	end

	if
		isFiniteNumber(data.RecoveryBackupDeceleration)
		and isFiniteNumber(data.RecoveryBackupAcceleration)
		and data.RecoveryBackupDeceleration < data.RecoveryBackupAcceleration
	then
		addError(
			errors,
			component,
			cartId,
			"RecoveryBackupDeceleration",
			data.RecoveryBackupDeceleration,
			"greater than or equal to RecoveryBackupAcceleration"
		)
	end

	if
		isFiniteNumber(data.Braking)
		and isFiniteNumber(data.ForwardAcceleration)
		and data.Braking < data.ForwardAcceleration
	then
		addError(errors, component, cartId, "Braking", data.Braking, "greater than or equal to ForwardAcceleration")
	end

	if
		isFiniteNumber(data.Braking)
		and isFiniteNumber(data.CoastDeceleration)
		and data.Braking < data.CoastDeceleration
	then
		addError(
			errors,
			component,
			cartId,
			"Braking",
			data.Braking,
			"greater than or equal to CoastDeceleration"
		)
	end

	if
		isFiniteNumber(data.ForwardAcceleration)
		and isFiniteNumber(data.HighSpeedAccelerationMultiplier)
		and isFiniteNumber(data.CoastDeceleration)
		and isFiniteNumber(data.HighSpeedCoastDecelerationMultiplier)
		and isFiniteNumber(data.Braking)
		and isFiniteNumber(data.HighSpeedBrakingMultiplier)
	then
		local highSpeedAcceleration = data.ForwardAcceleration * data.HighSpeedAccelerationMultiplier
		local highSpeedCoastDeceleration = data.CoastDeceleration * data.HighSpeedCoastDecelerationMultiplier
		local highSpeedBraking = data.Braking * data.HighSpeedBrakingMultiplier

		if highSpeedBraking < highSpeedAcceleration then
			addError(
				errors,
				component,
				cartId,
				"HighSpeedBrakingMultiplier",
				data.HighSpeedBrakingMultiplier,
				"produce high-speed braking greater than or equal to high-speed acceleration"
			)
		end

		if highSpeedBraking < highSpeedCoastDeceleration then
			addError(
				errors,
				component,
				cartId,
				"HighSpeedBrakingMultiplier",
				data.HighSpeedBrakingMultiplier,
				"produce high-speed braking greater than or equal to high-speed coast deceleration"
			)
		end
	end

	if
		isFiniteNumber(data.NearZeroSpeedThreshold)
		and isFiniteNumber(data.RecoveryBackupSpeed)
		and data.NearZeroSpeedThreshold >= data.RecoveryBackupSpeed
	then
		addError(
			errors,
			component,
			cartId,
			"NearZeroSpeedThreshold",
			data.NearZeroSpeedThreshold,
			"strictly less than RecoveryBackupSpeed"
		)
	end

	if
		isFiniteNumber(data.StationarySteeringThreshold)
		and isFiniteNumber(data.RecoveryBackupSpeed)
		and data.StationarySteeringThreshold > data.RecoveryBackupSpeed
	then
		addError(
			errors,
			component,
			cartId,
			"StationarySteeringThreshold",
			data.StationarySteeringThreshold,
			"less than or equal to RecoveryBackupSpeed"
		)
	end

	if
		isFiniteNumber(data.StationarySteeringThreshold)
		and isFiniteNumber(data.HuntingSpeed)
		and data.StationarySteeringThreshold >= data.HuntingSpeed
	then
		addError(
			errors,
			component,
			cartId,
			"StationarySteeringThreshold",
			data.StationarySteeringThreshold,
			"strictly less than HuntingSpeed"
		)
	end

	if
		isFiniteNumber(data.HighSpeedSteeringMultiplier)
		and isFiniteNumber(data.LowSpeedSteeringMultiplier)
		and data.HighSpeedSteeringMultiplier > data.LowSpeedSteeringMultiplier
	then
		addError(
			errors,
			component,
			cartId,
			"HighSpeedSteeringMultiplier",
			data.HighSpeedSteeringMultiplier,
			"less than or equal to LowSpeedSteeringMultiplier"
		)
	end

	if
		isFiniteNumber(data.MaxAngularSpeed)
		and isFiniteNumber(data.TurnRate)
		and isFiniteNumber(data.LowSpeedSteeringMultiplier)
		and isFiniteNumber(data.HighSpeedSteeringMultiplier)
		and data.MaxAngularSpeed
			< data.TurnRate * math.max(data.LowSpeedSteeringMultiplier, data.HighSpeedSteeringMultiplier)
	then
		addError(
			errors,
			component,
			cartId,
			"MaxAngularSpeed",
			data.MaxAngularSpeed,
			"greater than or equal to TurnRate multiplied by the maximum steering multiplier"
		)
	end
end

function CartMovementProfileValidator.ValidateBase(cartId: any, definition: any): ValidationResult
	local errors, data = validateNumberRules(BASE_COMPONENT, cartId, definition, BASE_RULES)

	if data ~= nil then
		validateRelationships(BASE_COMPONENT, cartId, data, errors)
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

function CartMovementProfileValidator.ValidateEffective(cartId: any, profile: any): ValidationResult
	local errors, data = validateNumberRules(EFFECTIVE_COMPONENT, cartId, profile, EFFECTIVE_RULES)

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

function CartMovementProfileValidator.AssertValidBase(cartId: any, definition: any)
	local result = CartMovementProfileValidator.ValidateBase(cartId, definition)

	if not result.IsValid then
		error(table.concat(result.Errors, "\n"), 2)
	end
end

function CartMovementProfileValidator.AssertValidEffective(cartId: any, profile: any)
	local result = CartMovementProfileValidator.ValidateEffective(cartId, profile)

	if not result.IsValid then
		error(table.concat(result.Errors, "\n"), 2)
	end
end

return CartMovementProfileValidator
