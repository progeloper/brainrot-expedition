--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local CartAnalyticsEventValidator =
	require(ReplicatedStorage.Shared.Validation.CartAnalyticsEventValidator)

export type Payload = { [string]: any }

export type Provider = {
	Emit: (self: Provider, eventName: string, payload: Payload) -> (),
}

export type Options = {
	Enabled: boolean?,
	Provider: Provider?,
	Warn: ((message: string) -> ())?,
}

export type Adapter = {
	Emit: (self: Adapter, eventName: unknown, payload: unknown) -> (boolean, string?),
	IsEnabled: (self: Adapter) -> boolean,
}

type AdapterImplementation = Adapter & {
	_enabled: boolean,
	_provider: Provider,
	_warn: (message: string) -> (),
}

local log = Logger.new("CartAnalyticsAdapter")

local CartAnalyticsAdapter = {}
local AdapterMethods = {}
AdapterMethods.__index = AdapterMethods

local NOOP_PROVIDER: Provider = table.freeze({
	Emit = function(_self: Provider, _eventName: string, _payload: Payload) end,
}) :: any

local function defaultWarn(message: string)
	log:Warn("%s", message)
end

local function formatValidationErrors(validationResult: any): string
	if type(validationResult) ~= "table" then
		return "validator returned an invalid result"
	end

	local errors = validationResult.Errors

	if type(errors) ~= "table" or #errors == 0 then
		return "event payload did not satisfy its schema"
	end

	local formatted: { string } = {}

	for _, validationError in errors do
		table.insert(formatted, tostring(validationError))
	end

	return table.concat(formatted, "; ")
end

function AdapterMethods:IsEnabled(): boolean
	return (self :: AdapterImplementation)._enabled
end

function AdapterMethods:Emit(eventName: unknown, payload: unknown): (boolean, string?)
	local implementation = self :: AdapterImplementation

	if not implementation._enabled then
		return false, "Disabled"
	end

	local validationSucceeded, validationResult = pcall(function()
		return CartAnalyticsEventValidator.Validate(eventName, payload)
	end)

	if not validationSucceeded then
		implementation._warn(
			string.format(
				"Analytics event validation failed Event=%s Error=%s",
				tostring(eventName),
				tostring(validationResult)
			)
		)
		return false, "ValidationFailure"
	end

	if type(validationResult) ~= "table" or validationResult.IsValid ~= true then
		implementation._warn(
			string.format(
				"Dropped invalid analytics event Event=%s Reason=%s",
				tostring(eventName),
				formatValidationErrors(validationResult)
			)
		)
		return false, "InvalidPayload"
	end

	local providerSucceeded, providerError = pcall(function()
		implementation._provider:Emit(eventName :: string, payload :: Payload)
	end)

	if not providerSucceeded then
		implementation._warn(
			string.format(
				"Analytics provider rejected event Event=%s Error=%s",
				tostring(eventName),
				tostring(providerError)
			)
		)
		return false, "ProviderFailure"
	end

	return true, nil
end

function CartAnalyticsAdapter.CreateNoopProvider(): Provider
	return NOOP_PROVIDER
end

function CartAnalyticsAdapter.new(options: Options?): Adapter
	local resolvedOptions = options or {}
	local enabled = resolvedOptions.Enabled

	if enabled == nil then
		enabled = true
	end

	assert(type(enabled) == "boolean", "analytics adapter Enabled must be a boolean")

	local provider = resolvedOptions.Provider or NOOP_PROVIDER

	assert(type(provider) == "table", "analytics adapter Provider must be a table")
	assert(type(provider.Emit) == "function", "analytics adapter Provider requires Emit")

	local warn = resolvedOptions.Warn or defaultWarn

	assert(type(warn) == "function", "analytics adapter Warn must be a function")

	return setmetatable({
		_enabled = enabled,
		_provider = provider,
		_warn = warn,
	}, AdapterMethods) :: any
end

return table.freeze(CartAnalyticsAdapter)
