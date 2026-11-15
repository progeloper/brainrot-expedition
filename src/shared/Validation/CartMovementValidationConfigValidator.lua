--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartMovementSafety = require(ReplicatedStorage.Shared.Config.CartMovementSafety)

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

type NumberRule = {
	Field: string,
	Minimum: number,
	Maximum: number,
	MinimumInclusive: boolean,
	Integer: boolean,
}

type AnyTable = { [any]: any }

local MAXIMUM_INTERVAL = 5
local MAXIMUM_MULTIPLIER = 20
local MAXIMUM_ADDITIVE = 1000
local MAXIMUM_SPEED = 10000
local MAXIMUM_GRACE = 10
local MAXIMUM_SCORE = 1000
local MAXIMUM_COOLDOWN = 60
local MAXIMUM_WARNING_WINDOW = 3600

local CartMovementValidationConfigValidator = {}

local function numberRule(
	field: string,
	minimum: number,
	maximum: number,
	minimumInclusive: boolean?,
	integer: boolean?
): NumberRule
	return {
		Field = field,
		Minimum = minimum,
		Maximum = maximum,
		MinimumInclusive = minimumInclusive ~= false,
		Integer = integer == true,
	}
end

local DEVELOPMENT_RULES: { NumberRule } = {
	numberRule("SampleInterval", 0, MAXIMUM_INTERVAL, false),

	numberRule("ForwardSpeedMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("ForwardSpeedAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("ReverseSpeedMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("ReverseSpeedAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("LateralSpeedMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("LateralSpeedAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("OverallSpeedMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("OverallSpeedAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("CorrectiveHorizontalSpeedMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("CorrectiveHorizontalSpeedAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("SevereHorizontalSpeedMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("SevereHorizontalSpeedAdditive", 0, MAXIMUM_ADDITIVE),

	numberRule("DisplacementMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("DisplacementAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("CorrectiveDisplacementMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("CorrectiveDisplacementAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("SevereDisplacementMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("SevereDisplacementAdditive", 0, MAXIMUM_ADDITIVE),

	numberRule("AccelerationMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("AccelerationAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("UpwardSpeedObservation", 0, MAXIMUM_SPEED, false),
	numberRule("DownwardSpeedObservation", 0, MAXIMUM_SPEED, false),
	numberRule("VerticalDisplacementAdditive", 0, MAXIMUM_ADDITIVE),
	numberRule("AngularSpeedMultiplier", 1, MAXIMUM_MULTIPLIER),
	numberRule("AngularSpeedAdditiveDegrees", 0, MAXIMUM_ADDITIVE),

	numberRule("OwnershipTransitionGrace", 0, MAXIMUM_GRACE),
	numberRule("NoDriverAccelerationTolerance", 0, MAXIMUM_SPEED),

	numberRule("ObservationScoreIncrement", 0, MAXIMUM_SCORE, false, true),
	numberRule("CorrectiveScoreIncrement", 0, MAXIMUM_SCORE, false, true),
	numberRule("SevereScoreIncrement", 0, MAXIMUM_SCORE, false, true),
	numberRule("ValidSampleDecay", 0, MAXIMUM_SCORE, true, true),
	numberRule("CorrectiveScoreThreshold", 0, MAXIMUM_SCORE, false, true),
	numberRule("SevereScoreThreshold", 0, MAXIMUM_SCORE, false, true),
	numberRule("MaximumViolationScore", 0, MAXIMUM_SCORE, false, true),
	numberRule("CorrectionCooldown", 0, MAXIMUM_COOLDOWN),
	numberRule("RepeatedWarningThreshold", 0, MAXIMUM_SCORE, false, true),
	numberRule("WarningWindow", 0, MAXIMUM_WARNING_WINDOW, false),
}

local SYSTEM_SAFETY_RULES: { NumberRule } = {
	numberRule("MaximumHorizontalSpeed", 0, MAXIMUM_SPEED, false),
	numberRule("MaximumUpwardSpeed", 0, MAXIMUM_SPEED, false),
	numberRule("MaximumDownwardSpeed", 0, MAXIMUM_SPEED, false),
	numberRule("MaximumAngularSpeedDegrees", 0, MAXIMUM_SPEED, false),
	numberRule("MaximumVerticalDisplacementAdditive", 0, MAXIMUM_ADDITIVE),
}

table.freeze(DEVELOPMENT_RULES)
table.freeze(SYSTEM_SAFETY_RULES)

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function addError(errors: { string }, message: string)
	table.insert(errors, message)
end

local function validateRules(
	container: AnyTable,
	prefix: string,
	rules: { NumberRule },
	errors: { string }
)
	for _, rule in rules do
		local value = container[rule.Field]
		local path = string.format("%s.%s", prefix, rule.Field)

		if not isFiniteNumber(value) then
			addError(errors, string.format("%s must be a finite number", path))
			continue
		end

		local numberValue = value :: number
		local belowMinimum = if rule.MinimumInclusive
			then numberValue < rule.Minimum
			else numberValue <= rule.Minimum

		if belowMinimum or numberValue > rule.Maximum then
			addError(
				errors,
				string.format(
					"%s must be %s %g and at most %g",
					path,
					if rule.MinimumInclusive then "at least" else "greater than",
					rule.Minimum,
					rule.Maximum
				)
			)
		elseif rule.Integer and numberValue % 1 ~= 0 then
			addError(errors, string.format("%s must be an integer", path))
		end
	end
end

local function validateOrderedPair(
	container: AnyTable,
	prefix: string,
	firstField: string,
	secondField: string,
	errors: { string }
)
	local first = container[firstField]
	local second = container[secondField]

	if isFiniteNumber(first) and isFiniteNumber(second) and first > second then
		addError(
			errors,
			string.format(
				"%s.%s must be less than or equal to %s.%s",
				prefix,
				firstField,
				prefix,
				secondField
			)
		)
	end
end

local function validateDevelopmentRelationships(development: AnyTable, errors: { string })
	validateOrderedPair(
		development,
		"Development",
		"OverallSpeedMultiplier",
		"CorrectiveHorizontalSpeedMultiplier",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"CorrectiveHorizontalSpeedMultiplier",
		"SevereHorizontalSpeedMultiplier",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"OverallSpeedAdditive",
		"CorrectiveHorizontalSpeedAdditive",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"CorrectiveHorizontalSpeedAdditive",
		"SevereHorizontalSpeedAdditive",
		errors
	)

	validateOrderedPair(
		development,
		"Development",
		"DisplacementMultiplier",
		"CorrectiveDisplacementMultiplier",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"CorrectiveDisplacementMultiplier",
		"SevereDisplacementMultiplier",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"DisplacementAdditive",
		"CorrectiveDisplacementAdditive",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"CorrectiveDisplacementAdditive",
		"SevereDisplacementAdditive",
		errors
	)

	validateOrderedPair(
		development,
		"Development",
		"ObservationScoreIncrement",
		"CorrectiveScoreIncrement",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"CorrectiveScoreIncrement",
		"SevereScoreIncrement",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"CorrectiveScoreThreshold",
		"SevereScoreThreshold",
		errors
	)
	validateOrderedPair(
		development,
		"Development",
		"SevereScoreThreshold",
		"MaximumViolationScore",
		errors
	)

	for _, field in
		{
			"ObservationScoreIncrement",
			"CorrectiveScoreIncrement",
			"SevereScoreIncrement",
			"ValidSampleDecay",
		}
	do
		validateOrderedPair(development, "Development", field, "MaximumViolationScore", errors)
	end
end

local function validateCrossSectionRelationships(
	development: AnyTable,
	systemSafety: AnyTable,
	errors: { string }
)
	if
		isFiniteNumber(systemSafety.MaximumHorizontalSpeed)
		and systemSafety.MaximumHorizontalSpeed < CartMovementSafety.MaximumTravelSpeed
	then
		addError(
			errors,
			string.format(
				"SystemSafety.MaximumHorizontalSpeed must be at least the Phase 1D hard MaximumTravelSpeed of %g",
				CartMovementSafety.MaximumTravelSpeed
			)
		)
	end

	if
		isFiniteNumber(systemSafety.MaximumAngularSpeedDegrees)
		and systemSafety.MaximumAngularSpeedDegrees < CartMovementSafety.MaximumAngularSpeed
	then
		addError(
			errors,
			string.format(
				"SystemSafety.MaximumAngularSpeedDegrees must be at least the Phase 1D hard MaximumAngularSpeed of %g",
				CartMovementSafety.MaximumAngularSpeed
			)
		)
	end

	for _, relationship in
		{
			{
				DevelopmentField = "UpwardSpeedObservation",
				SystemField = "MaximumUpwardSpeed",
			},
			{
				DevelopmentField = "DownwardSpeedObservation",
				SystemField = "MaximumDownwardSpeed",
			},
			{
				DevelopmentField = "VerticalDisplacementAdditive",
				SystemField = "MaximumVerticalDisplacementAdditive",
			},
		}
	do
		local developmentValue = development[relationship.DevelopmentField]
		local systemValue = systemSafety[relationship.SystemField]

		if
			isFiniteNumber(developmentValue)
			and isFiniteNumber(systemValue)
			and developmentValue > systemValue
		then
			addError(
				errors,
				string.format(
					"Development.%s must not exceed SystemSafety.%s",
					relationship.DevelopmentField,
					relationship.SystemField
				)
			)
		end
	end

	if
		isFiniteNumber(development.AngularSpeedMultiplier)
		and isFiniteNumber(development.AngularSpeedAdditiveDegrees)
		and isFiniteNumber(systemSafety.MaximumAngularSpeedDegrees)
		and CartMovementSafety.MaximumAngularSpeed * development.AngularSpeedMultiplier
				+ development.AngularSpeedAdditiveDegrees
			> systemSafety.MaximumAngularSpeedDegrees
	then
		addError(
			errors,
			"the maximum approved angular observation envelope must not exceed SystemSafety.MaximumAngularSpeedDegrees"
		)
	end
end

function CartMovementValidationConfigValidator.Validate(config: unknown): ValidationResult
	local errors: { string } = {}

	if type(config) ~= "table" then
		return {
			IsValid = false,
			Errors = { "movement-validation configuration must be a table" },
		}
	end

	local values = config :: AnyTable

	if type(values.Enabled) ~= "boolean" then
		addError(errors, "Enabled must be a boolean")
	end

	local developmentValue = values.Development
	local systemSafetyValue = values.SystemSafety
	local development: AnyTable? = nil
	local systemSafety: AnyTable? = nil

	if type(developmentValue) ~= "table" then
		addError(errors, "Development must be a table")
	else
		development = developmentValue :: AnyTable
		validateRules(development, "Development", DEVELOPMENT_RULES, errors)

		if type(development.DiagnosticsEnabled) ~= "boolean" then
			addError(errors, "Development.DiagnosticsEnabled must be a boolean")
		end

		validateDevelopmentRelationships(development, errors)
	end

	if type(systemSafetyValue) ~= "table" then
		addError(errors, "SystemSafety must be a table")
	else
		systemSafety = systemSafetyValue :: AnyTable
		validateRules(systemSafety, "SystemSafety", SYSTEM_SAFETY_RULES, errors)
	end

	if development ~= nil and systemSafety ~= nil then
		validateCrossSectionRelationships(development, systemSafety, errors)
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

return table.freeze(CartMovementValidationConfigValidator)
