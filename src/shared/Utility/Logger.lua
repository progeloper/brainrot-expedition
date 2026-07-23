--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

export type Logger = {
	Info: (self: Logger, message: string, ...any) -> (),
	Warn: (self: Logger, message: string, ...any) -> (),
	Error: (self: Logger, message: string, ...any) -> (),
	Debug: (self: Logger, message: string, ...any) -> (),
}

local Logger = {}
Logger.__index = Logger

local function formatMessage(scope: string, level: string, message: string): string
	return string.format("[%s][%s][%s] %s", Environment.BuildId, scope, level, message)
end

function Logger.new(scope: string): Logger
	local self = setmetatable({
		_scope = scope,
	}, Logger)

	return self :: any
end

function Logger:Info(message: string, ...: any)
	print(formatMessage(self._scope, "INFO", string.format(message, ...)))
end

function Logger:Warn(message: string, ...: any)
	warn(formatMessage(self._scope, "WARN", string.format(message, ...)))
end

function Logger:Error(message: string, ...: any)
	error(formatMessage(self._scope, "ERROR", string.format(message, ...)), 2)
end

function Logger:Debug(message: string, ...: any)
	if not Environment.EnableVerboseLogging then
		return
	end

	print(formatMessage(self._scope, "DEBUG", string.format(message, ...)))
end

return Logger
