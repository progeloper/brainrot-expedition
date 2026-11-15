--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartAnalytics = require(ReplicatedStorage.Shared.Config.CartAnalytics)
local AnalyticsEvents = require(ReplicatedStorage.Shared.Constants.AnalyticsEvents)
local CartResetRequestProtocol = require(ReplicatedStorage.Shared.Utility.CartResetRequestProtocol)

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

type AnyTable = { [any]: any }
type ValueValidator = (value: unknown) -> string?
type FieldValidators = { [string]: ValueValidator }
type EventSchema = {
	Required: FieldValidators,
	Optional: FieldValidators,
}

local CartAnalyticsEventValidator = {}

local EVENT_VERSION = CartAnalytics.EventVersion

local PLATFORMS = table.freeze({
	KeyboardMouse = true,
	Touch = true,
	Gamepad = true,
	Unknown = true,
})

local DIRECTIONS = table.freeze({
	Forward = true,
	Reverse = true,
})

local DRIVER_EXIT_REASONS = table.freeze({
	SeatExited = true,
	DriverReplaced = true,
	CartDestroyed = true,
	CartReplaced = true,
	PlayerLeaving = true,
	CharacterInvalidated = true,
	ServiceShutdown = true,
	Unknown = true,
})

local CART_DESPAWN_REASONS = table.freeze({
	PlayerLeaving = true,
	Replacement = true,
	ExplicitDespawn = true,
	ModelDestroyed = true,
	ServiceShutdown = true,
	Unknown = true,
})

local CORRECTION_CATEGORIES = table.freeze({
	NetworkOwnershipRestored = true,
	VelocityCleared = true,
	CorrectiveReset = true,
	InvalidStateRecovered = true,
})

local CORRECTION_SEVERITIES = table.freeze({
	Corrective = true,
	Severe = true,
})

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function validateString(value: unknown): string?
	if type(value) ~= "string" or value == "" then
		return "must be a non-empty string"
	end

	return nil
end

local function validateBoolean(value: unknown): string?
	if type(value) ~= "boolean" then
		return "must be a boolean"
	end

	return nil
end

local function validateFiniteNumber(value: unknown): string?
	if not isFiniteNumber(value) then
		return "must be a finite number"
	end

	return nil
end

local function validateNonNegativeNumber(value: unknown): string?
	local finiteError = validateFiniteNumber(value)

	if finiteError ~= nil then
		return finiteError
	end

	if (value :: number) < 0 then
		return "must be non-negative"
	end

	return nil
end

local function validateInteger(value: unknown): string?
	local finiteError = validateFiniteNumber(value)

	if finiteError ~= nil then
		return finiteError
	end

	if (value :: number) % 1 ~= 0 then
		return "must be an integer"
	end

	return nil
end

local function validateNonNegativeInteger(value: unknown): string?
	local integerError = validateInteger(value)

	if integerError ~= nil then
		return integerError
	end

	if (value :: number) < 0 then
		return "must be a non-negative integer"
	end

	return nil
end

local function validateEventVersion(value: unknown): string?
	local integerError = validateInteger(value)

	if integerError ~= nil then
		return integerError
	end

	if value ~= EVENT_VERSION then
		return string.format("must equal %d", EVENT_VERSION)
	end

	return nil
end

local function enumValidator(values: { [string]: boolean }): ValueValidator
	return function(value: unknown): string?
		if type(value) ~= "string" or values[value] ~= true then
			return "contains an unsupported enum value"
		end

		return nil
	end
end

local function validateResetRejectionReason(value: unknown): string?
	if
		not CartResetRequestProtocol.IsReasonCode(value)
		or value == CartResetRequestProtocol.ReasonCodes.Approved
	then
		return "must be a Phase 1K rejection reason code"
	end

	return nil
end

local COMMON_REQUIRED: FieldValidators = table.freeze({
	EventVersion = validateEventVersion,
	BuildId = validateString,
	Environment = enumValidator({
		Development = true,
		Sandbox = true,
		Production = true,
	}),
	ServerTimestamp = validateNonNegativeNumber,
	PlayerUserId = validateInteger,
})

local function makeSchema(
	requiredFields: FieldValidators,
	optionalFields: FieldValidators?
): EventSchema
	local required = table.clone(COMMON_REQUIRED)

	for field, validator in requiredFields do
		required[field] = validator
	end

	return table.freeze({
		Required = table.freeze(required),
		Optional = table.freeze(optionalFields or {}),
	})
end

local EVENT_SCHEMAS: { [string]: EventSchema } = table.freeze({
	[AnalyticsEvents.CartSpawned] = makeSchema({
		RuntimeCartId = validateString,
		CartId = validateString,
		SpawnId = validateString,
	}),
	[AnalyticsEvents.CartDriverEntered] = makeSchema({
		RuntimeCartId = validateString,
		CartId = validateString,
		DriverSessionId = validateString,
		TimeSinceCartSpawn = validateNonNegativeNumber,
		Platform = enumValidator(PLATFORMS),
	}),
	[AnalyticsEvents.CartMovementStarted] = makeSchema({
		RuntimeCartId = validateString,
		CartId = validateString,
		DriverSessionId = validateString,
		TimeSinceDriverEntered = validateNonNegativeNumber,
		Platform = enumValidator(PLATFORMS),
		Direction = enumValidator(DIRECTIONS),
	}),
	[AnalyticsEvents.CartDriverExited] = makeSchema({
		RuntimeCartId = validateString,
		CartId = validateString,
		DriverSessionId = validateString,
		DriverSessionDuration = validateNonNegativeNumber,
		MeaningfulMovementBegan = validateBoolean,
		ExitReason = enumValidator(DRIVER_EXIT_REASONS),
		Platform = enumValidator(PLATFORMS),
	}),
	[AnalyticsEvents.CartResetRequested] = makeSchema({
		Platform = enumValidator(PLATFORMS),
	}, {
		RuntimeCartId = validateString,
		CartId = validateString,
		DriverSessionId = validateString,
	}),
	[AnalyticsEvents.CartResetApproved] = makeSchema({
		RuntimeCartId = validateString,
		CartId = validateString,
		DriverSessionId = validateString,
		TimeSinceDriverEntered = validateNonNegativeNumber,
		Platform = enumValidator(PLATFORMS),
	}),
	[AnalyticsEvents.CartResetRejected] = makeSchema({
		Reason = validateResetRejectionReason,
		Platform = enumValidator(PLATFORMS),
	}, {
		RuntimeCartId = validateString,
		CartId = validateString,
		DriverSessionId = validateString,
	}),
	[AnalyticsEvents.CartResetCompleted] = makeSchema({
		RuntimeCartId = validateString,
		CartId = validateString,
		DriverSessionId = validateString,
		ResetDuration = validateNonNegativeNumber,
		Platform = enumValidator(PLATFORMS),
		DriverRetained = validateBoolean,
	}),
	[AnalyticsEvents.CartDespawned] = makeSchema({
		RuntimeCartId = validateString,
		CartId = validateString,
		SpawnId = validateString,
		CartLifetime = validateNonNegativeNumber,
		HadDriver = validateBoolean,
		HadMeaningfulMovement = validateBoolean,
		DespawnReason = enumValidator(CART_DESPAWN_REASONS),
		ActiveDriverPresent = validateBoolean,
		CompletedResetCount = validateNonNegativeInteger,
		MovementCorrectionCount = validateNonNegativeInteger,
	}),
	[AnalyticsEvents.CartMovementCorrected] = makeSchema({
		RuntimeCartId = validateString,
		CartId = validateString,
		Category = enumValidator(CORRECTION_CATEGORIES),
		Severity = enumValidator(CORRECTION_SEVERITIES),
		Reason = validateString,
		CorrectionCount = validateNonNegativeInteger,
	}, {
		DriverSessionId = validateString,
	}),
})

local function addError(errors: { string }, message: string)
	table.insert(errors, message)
end

function CartAnalyticsEventValidator.IsEventName(value: unknown): boolean
	return type(value) == "string" and EVENT_SCHEMAS[value] ~= nil
end

function CartAnalyticsEventValidator.GetEventVersion(eventName: unknown): number?
	if CartAnalyticsEventValidator.IsEventName(eventName) then
		return EVENT_VERSION
	end

	return nil
end

function CartAnalyticsEventValidator.Validate(
	eventName: unknown,
	payload: unknown
): ValidationResult
	if not CartAnalyticsEventValidator.IsEventName(eventName) then
		return {
			IsValid = false,
			Errors = { "event name is not part of the Phase 1R cart event catalogue" },
		}
	end

	if type(payload) ~= "table" then
		return {
			IsValid = false,
			Errors = { "event payload must be a table" },
		}
	end

	local schema = EVENT_SCHEMAS[eventName :: string]

	assert(schema ~= nil, "validated cart analytics event must have a schema")

	local values = payload :: AnyTable
	local errors: { string } = {}

	for field, value in values do
		if type(field) ~= "string" then
			addError(
				errors,
				string.format("payload contains unsupported field %s", tostring(field))
			)
			continue
		end

		local validator = schema.Required[field] or schema.Optional[field]

		if validator == nil then
			addError(errors, string.format("payload contains unknown field %s", field))
		else
			local validationError = validator(value)

			if validationError ~= nil then
				addError(errors, string.format("%s %s", field, validationError))
			end
		end
	end

	for field in schema.Required do
		if values[field] == nil then
			addError(errors, string.format("payload is missing required field %s", field))
		end
	end

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

CartAnalyticsEventValidator.Enums = table.freeze({
	Platforms = PLATFORMS,
	Directions = DIRECTIONS,
	DriverExitReasons = DRIVER_EXIT_REASONS,
	CartDespawnReasons = CART_DESPAWN_REASONS,
	CorrectionCategories = CORRECTION_CATEGORIES,
	CorrectionSeverities = CORRECTION_SEVERITIES,
})

return table.freeze(CartAnalyticsEventValidator)
