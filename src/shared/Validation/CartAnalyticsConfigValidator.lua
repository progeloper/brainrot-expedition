--!strict

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

type AnyTable = { [any]: any }

local CartAnalyticsConfigValidator = {}

local EXPECTED_EVENT_VERSION = 1
local MAXIMUM_MOVEMENT_SPEED = 1000
local MAXIMUM_CONFIRMATION_DURATION = 60

local ROOT_FIELDS = table.freeze({
	Enabled = true,
	EventVersion = true,
	Development = true,
})

local DEVELOPMENT_FIELDS = table.freeze({
	MeaningfulMovementSpeed = true,
	MovementConfirmationDuration = true,
})

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function addError(errors: { string }, message: string)
	table.insert(errors, message)
end

local function rejectUnknownFields(
	container: AnyTable,
	allowedFields: { [string]: boolean },
	prefix: string,
	errors: { string }
)
	for field in container do
		if type(field) ~= "string" or allowedFields[field] ~= true then
			addError(errors, string.format("%s contains unknown field %s", prefix, tostring(field)))
		end
	end
end

function CartAnalyticsConfigValidator.Validate(config: unknown): ValidationResult
	local errors: { string } = {}

	if type(config) ~= "table" then
		return {
			IsValid = false,
			Errors = { "cart analytics configuration must be a table" },
		}
	end

	local values = config :: AnyTable

	rejectUnknownFields(values, ROOT_FIELDS, "configuration", errors)

	if type(values.Enabled) ~= "boolean" then
		addError(errors, "Enabled must be a boolean")
	end

	if not isFiniteNumber(values.EventVersion) then
		addError(errors, "EventVersion must be a finite number")
	elseif values.EventVersion % 1 ~= 0 or values.EventVersion ~= EXPECTED_EVENT_VERSION then
		addError(errors, string.format("EventVersion must equal %d", EXPECTED_EVENT_VERSION))
	end

	local developmentValue = values.Development

	if type(developmentValue) ~= "table" then
		addError(errors, "Development must be a table")
	else
		local development = developmentValue :: AnyTable

		rejectUnknownFields(development, DEVELOPMENT_FIELDS, "Development", errors)

		local meaningfulMovementSpeed = development.MeaningfulMovementSpeed

		if not isFiniteNumber(meaningfulMovementSpeed) then
			addError(errors, "Development.MeaningfulMovementSpeed must be a finite number")
		elseif meaningfulMovementSpeed <= 0 or meaningfulMovementSpeed > MAXIMUM_MOVEMENT_SPEED then
			addError(
				errors,
				string.format(
					"Development.MeaningfulMovementSpeed must be greater than 0 and at most %g",
					MAXIMUM_MOVEMENT_SPEED
				)
			)
		end

		local movementConfirmationDuration = development.MovementConfirmationDuration

		if not isFiniteNumber(movementConfirmationDuration) then
			addError(errors, "Development.MovementConfirmationDuration must be a finite number")
		elseif
			movementConfirmationDuration <= 0
			or movementConfirmationDuration > MAXIMUM_CONFIRMATION_DURATION
		then
			addError(
				errors,
				string.format(
					"Development.MovementConfirmationDuration must be greater than 0 and at most %g",
					MAXIMUM_CONFIRMATION_DURATION
				)
			)
		end
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

return table.freeze(CartAnalyticsConfigValidator)
