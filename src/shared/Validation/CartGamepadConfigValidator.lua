--!strict

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

local CartGamepadConfigValidator = {}

local MAXIMUM_CAMERA_RADIANS_PER_SECOND = math.pi * 8

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function addError(errors: { string }, message: string)
	table.insert(errors, message)
end

local function requireDeadzone(container: { [any]: any }, field: string, errors: { string })
	local value = container[field]
	local path = string.format("Development.%s", field)

	if not isFiniteNumber(value) then
		addError(errors, string.format("%s must be a finite number", path))
		return
	end

	if value < 0 or value >= 1 then
		addError(errors, string.format("%s must be at least 0 and less than 1", path))
	end
end

function CartGamepadConfigValidator.Validate(config: unknown): ValidationResult
	local errors: { string } = {}

	if type(config) ~= "table" then
		return {
			IsValid = false,
			Errors = { "gamepad configuration must be a table" },
		}
	end

	local developmentValue = (config :: { [any]: any }).Development

	if type(developmentValue) ~= "table" then
		return {
			IsValid = false,
			Errors = { "Development must be a table" },
		}
	end

	local development = developmentValue :: { [any]: any }

	requireDeadzone(development, "MovementStickDeadzone", errors)
	requireDeadzone(development, "CameraStickDeadzone", errors)
	requireDeadzone(development, "TriggerDeadzone", errors)

	local cameraRadiansPerSecond = development.CameraRadiansPerSecond

	if not isFiniteNumber(cameraRadiansPerSecond) then
		addError(errors, "Development.CameraRadiansPerSecond must be a finite number")
	elseif
		cameraRadiansPerSecond <= 0
		or cameraRadiansPerSecond > MAXIMUM_CAMERA_RADIANS_PER_SECOND
	then
		addError(
			errors,
			string.format(
				"Development.CameraRadiansPerSecond must be greater than 0 and at most %.4f",
				MAXIMUM_CAMERA_RADIANS_PER_SECOND
			)
		)
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

return table.freeze(CartGamepadConfigValidator)
