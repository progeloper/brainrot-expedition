--!strict

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

local CartCameraConfigValidator = {}

local MAXIMUM_DISTANCE = 200
local MAXIMUM_HEIGHT_OFFSET = 100
local MAXIMUM_SENSITIVITY = 10
local MAXIMUM_RECENTER_DELAY = 30
local MAXIMUM_RESPONSE = 100
local MAXIMUM_MOUSE_RADIANS_PER_PIXEL = 0.1
local MAXIMUM_ABSOLUTE_PITCH = math.rad(80)
local MAXIMUM_QUERY_RADIUS = 8
local MAXIMUM_SURFACE_BUFFER = 8
local MAXIMUM_DISTANCE_TOLERANCE = 2

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function addError(errors: { string }, message: string)
	table.insert(errors, message)
end

local function requireRange(
	container: { [any]: any },
	field: string,
	minimum: number,
	maximum: number,
	minimumInclusive: boolean,
	errors: { string }
)
	local value = container[field]

	if not isFiniteNumber(value) then
		addError(errors, string.format("%s must be a finite number", field))
		return
	end

	local numericValue = value :: number
	local belowMinimum = if minimumInclusive
		then numericValue < minimum
		else numericValue <= minimum

	if belowMinimum or numericValue > maximum then
		addError(
			errors,
			string.format(
				"%s must be %s %.4f and at most %.4f",
				field,
				if minimumInclusive then "at least" else "greater than",
				minimum,
				maximum
			)
		)
	end
end

function CartCameraConfigValidator.Validate(config: unknown): ValidationResult
	local errors: { string } = {}

	if type(config) ~= "table" then
		return {
			IsValid = false,
			Errors = { "camera configuration must be a table" },
		}
	end

	local values = config :: { [any]: any }

	requireRange(values, "Distance", 0, MAXIMUM_DISTANCE, false, errors)
	requireRange(values, "HeightOffset", 0, MAXIMUM_HEIGHT_OFFSET, false, errors)
	requireRange(values, "PCSensitivity", 0, MAXIMUM_SENSITIVITY, false, errors)
	requireRange(values, "GamepadSensitivity", 0, MAXIMUM_SENSITIVITY, false, errors)
	requireRange(values, "AutoRecenterDelay", 0, MAXIMUM_RECENTER_DELAY, true, errors)
	requireRange(values, "AutoRecenterSpeed", 0, MAXIMUM_RESPONSE, false, errors)

	local developmentValue = values.Development

	if type(developmentValue) ~= "table" then
		addError(errors, "Development must be a table")
		return {
			IsValid = false,
			Errors = errors,
		}
	end

	local development = developmentValue :: { [any]: any }

	requireRange(
		development,
		"MouseRadiansPerPixel",
		0,
		MAXIMUM_MOUSE_RADIANS_PER_PIXEL,
		false,
		errors
	)
	requireRange(development, "ManualInputThreshold", 0, 1, false, errors)
	requireRange(development, "PositionResponsiveness", 0, MAXIMUM_RESPONSE, false, errors)
	requireRange(development, "RotationResponsiveness", 0, MAXIMUM_RESPONSE, false, errors)
	requireRange(
		development,
		"MinimumPitch",
		-MAXIMUM_ABSOLUTE_PITCH,
		MAXIMUM_ABSOLUTE_PITCH,
		true,
		errors
	)
	requireRange(
		development,
		"MaximumPitch",
		-MAXIMUM_ABSOLUTE_PITCH,
		MAXIMUM_ABSOLUTE_PITCH,
		true,
		errors
	)
	requireRange(
		development,
		"DefaultPitch",
		-MAXIMUM_ABSOLUTE_PITCH,
		MAXIMUM_ABSOLUTE_PITCH,
		true,
		errors
	)

	if
		isFiniteNumber(development.MinimumPitch)
		and isFiniteNumber(development.MaximumPitch)
		and development.MinimumPitch >= development.MaximumPitch
	then
		addError(errors, "MinimumPitch must be less than MaximumPitch")
	end

	if
		isFiniteNumber(development.MinimumPitch)
		and isFiniteNumber(development.MaximumPitch)
		and isFiniteNumber(development.DefaultPitch)
		and (
			development.DefaultPitch < development.MinimumPitch
			or development.DefaultPitch > development.MaximumPitch
		)
	then
		addError(errors, "DefaultPitch must be within the configured pitch bounds")
	end

	local obstructionValue = values.Obstruction

	if type(obstructionValue) ~= "table" then
		addError(errors, "Obstruction must be a table")
		return {
			IsValid = false,
			Errors = errors,
		}
	end

	local obstruction = obstructionValue :: { [any]: any }

	if type(obstruction.Enabled) ~= "boolean" then
		addError(errors, "Obstruction.Enabled must be a boolean")
	end

	requireRange(obstruction, "QueryRadius", 0, MAXIMUM_QUERY_RADIUS, false, errors)
	requireRange(obstruction, "SurfaceBuffer", 0, MAXIMUM_SURFACE_BUFFER, true, errors)
	requireRange(obstruction, "MinimumDistance", 0, MAXIMUM_DISTANCE, false, errors)
	requireRange(obstruction, "OutwardRecoverySpeed", 0, MAXIMUM_RESPONSE, false, errors)
	requireRange(obstruction, "DistanceTolerance", 0, MAXIMUM_DISTANCE_TOLERANCE, true, errors)

	if
		isFiniteNumber(obstruction.MinimumDistance)
		and isFiniteNumber(values.Distance)
		and obstruction.MinimumDistance > values.Distance
	then
		addError(errors, "Obstruction.MinimumDistance must not exceed Distance")
	end

	if
		isFiniteNumber(obstruction.MinimumDistance)
		and isFiniteNumber(obstruction.QueryRadius)
		and obstruction.MinimumDistance <= obstruction.QueryRadius
	then
		addError(errors, "Obstruction.MinimumDistance must be greater than QueryRadius")
	end

	if
		isFiniteNumber(obstruction.DistanceTolerance)
		and isFiniteNumber(obstruction.MinimumDistance)
		and obstruction.DistanceTolerance >= obstruction.MinimumDistance
	then
		addError(errors, "Obstruction.DistanceTolerance must be less than MinimumDistance")
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

return table.freeze(CartCameraConfigValidator)
