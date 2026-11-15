--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsEvents = require(ReplicatedStorage.Shared.Constants.AnalyticsEvents)
local CartResetRequestProtocol = require(ReplicatedStorage.Shared.Utility.CartResetRequestProtocol)

export type PlatformCategory = "KeyboardMouse" | "Touch" | "Gamepad" | "Unknown"
export type MovementDirection = "Forward" | "Reverse"

export type EventRequest = {
	Name: string,
	ServerTimestamp: number,
	PlayerUserId: number,
	RuntimeCartId: string?,
	Fields: { [string]: any },
}

export type CartRegistration = {
	Key: any,
	OwnerUserId: number,
	CartId: string,
	SpawnId: string,
	SpawnedAt: number,
}

export type ResetOutcome = {
	PlayerUserId: number,
	CartKey: any?,
	Approved: boolean,
	Reason: string,
	RequestedAt: number,
	CompletedAt: number,
	ResetStartedAt: number?,
	ResetCompletedAt: number?,
}

export type Correction = {
	CartKey: any,
	Revision: number,
	Category: string,
	Severity: string,
	Reason: string,
	ServerTimestamp: number,
}

type DriverSession = {
	SessionId: string,
	PlayerUserId: number,
	EnteredAt: number,
	MovementStartedAt: number?,
	Platform: PlatformCategory,
}

type CartRecord = {
	OwnerUserId: number,
	CartId: string,
	SpawnId: string,
	RuntimeCartId: string,
	SpawnedAt: number,
	CurrentDriver: DriverSession?,
	NextDriverSequence: number,
	HadDriver: boolean,
	HadMeaningfulMovement: boolean,
	CompletedResetCount: number,
	MovementCorrectionCount: number,
	LastCorrectionRevision: number,
}

export type Snapshot = {
	RuntimeCartId: string,
	CurrentDriverSessionId: string?,
	CurrentDriverUserId: number?,
	HadDriver: boolean,
	HadMeaningfulMovement: boolean,
	CompletedResetCount: number,
	MovementCorrectionCount: number,
}

export type Runtime = {
	RegisterCart: (self: Runtime, registration: CartRegistration, now: number) -> { EventRequest },
	DriverChanged: (
		self: Runtime,
		cartKey: any,
		previousDriverUserId: number?,
		nextDriverUserId: number?,
		reason: string,
		now: number,
		platform: PlatformCategory?
	) -> { EventRequest },
	MovementStarted: (
		self: Runtime,
		cartKey: any,
		driverUserId: number,
		direction: MovementDirection,
		now: number
	) -> { EventRequest },
	RecordResetOutcome: (self: Runtime, outcome: ResetOutcome) -> { EventRequest },
	RecordCorrection: (self: Runtime, correction: Correction) -> { EventRequest },
	DespawnCart: (
		self: Runtime,
		cartKey: any,
		despawnReason: string,
		driverExitReason: string,
		now: number
	) -> { EventRequest },
	Stop: (self: Runtime, now: number) -> { EventRequest },
	RemovePlayer: (self: Runtime, playerUserId: number) -> (),
	DiscardCart: (self: Runtime, cartKey: any) -> (),
	GetRegisteredKeys: (self: Runtime) -> { any },
	GetSnapshot: (self: Runtime, cartKey: any) -> Snapshot?,
	GetRecordCount: (self: Runtime) -> number,
}

type RuntimePrivate = Runtime & {
	_records: { [any]: CartRecord },
	_nextCartSequence: number,
	_resetNoiseThrottle: number,
	_lastResetNoiseByUserId: { [number]: number },
}

local CartAnalyticsRuntime = {}
local RuntimeMethods = {}
RuntimeMethods.__index = RuntimeMethods

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function safeDuration(startedAt: number, completedAt: number): number
	if not isFiniteNumber(startedAt) or not isFiniteNumber(completedAt) then
		return 0
	end

	return math.max(0, completedAt - startedAt)
end

local function normalizePlatform(platform: PlatformCategory?): PlatformCategory
	if platform == "KeyboardMouse" or platform == "Touch" or platform == "Gamepad" then
		return platform
	end

	return "Unknown"
end

local function eventRequest(
	name: string,
	serverTimestamp: number,
	playerUserId: number,
	runtimeCartId: string?,
	fields: { [string]: any }
): EventRequest
	return table.freeze({
		Name = name,
		ServerTimestamp = serverTimestamp,
		PlayerUserId = playerUserId,
		RuntimeCartId = runtimeCartId,
		Fields = table.freeze(fields),
	})
end

local function addAll(target: { EventRequest }, source: { EventRequest })
	for _, request in source do
		table.insert(target, request)
	end
end

local function closeDriver(record: CartRecord, reason: string, now: number): EventRequest?
	local session = record.CurrentDriver

	if session == nil then
		return nil
	end

	record.CurrentDriver = nil

	return eventRequest(
		AnalyticsEvents.CartDriverExited,
		now,
		session.PlayerUserId,
		record.RuntimeCartId,
		{
			CartId = record.CartId,
			DriverSessionId = session.SessionId,
			DriverSessionDuration = safeDuration(session.EnteredAt, now),
			MeaningfulMovementBegan = session.MovementStartedAt ~= nil,
			ExitReason = reason,
			Platform = session.Platform,
		}
	)
end

function CartAnalyticsRuntime.new(resetNoiseThrottle: number): Runtime
	assert(
		isFiniteNumber(resetNoiseThrottle) and resetNoiseThrottle > 0,
		"analytics reset-noise throttle must be positive"
	)

	local records: { [any]: CartRecord } = setmetatable({}, { __mode = "k" }) :: any
	local self: RuntimePrivate = setmetatable({
		-- Runtime cart keys are weak and CartRecord stores no Instance. This keeps
		-- restart correlation without retaining destroyed Models while stopped.
		_records = records,
		_nextCartSequence = 0,
		_resetNoiseThrottle = resetNoiseThrottle,
		_lastResetNoiseByUserId = {},
	}, RuntimeMethods) :: any

	return self
end

function RuntimeMethods:RegisterCart(registration: CartRegistration, now: number): { EventRequest }
	local implementation = self :: RuntimePrivate

	if implementation._records[registration.Key] ~= nil then
		return {}
	end

	implementation._nextCartSequence += 1
	local runtimeCartId = string.format("cart-%d", implementation._nextCartSequence)
	local spawnedAt = if isFiniteNumber(registration.SpawnedAt) then registration.SpawnedAt else now

	implementation._records[registration.Key] = {
		OwnerUserId = registration.OwnerUserId,
		CartId = registration.CartId,
		SpawnId = registration.SpawnId,
		RuntimeCartId = runtimeCartId,
		SpawnedAt = spawnedAt,
		CurrentDriver = nil,
		NextDriverSequence = 0,
		HadDriver = false,
		HadMeaningfulMovement = false,
		CompletedResetCount = 0,
		MovementCorrectionCount = 0,
		LastCorrectionRevision = 0,
	}

	return {
		eventRequest(AnalyticsEvents.CartSpawned, now, registration.OwnerUserId, runtimeCartId, {
			CartId = registration.CartId,
			SpawnId = registration.SpawnId,
		}),
	}
end

function RuntimeMethods:DriverChanged(
	cartKey: any,
	previousDriverUserId: number?,
	nextDriverUserId: number?,
	reason: string,
	now: number,
	platform: PlatformCategory?
): { EventRequest }
	local implementation = self :: RuntimePrivate
	local record = implementation._records[cartKey]

	if record == nil then
		return {}
	end

	local events: { EventRequest } = {}
	local current = record.CurrentDriver
	local resolvedExitReason = if previousDriverUserId ~= nil
			and nextDriverUserId ~= nil
			and previousDriverUserId ~= nextDriverUserId
		then "DriverReplaced"
		else reason

	if current ~= nil and current.PlayerUserId ~= nextDriverUserId then
		local exitEvent = closeDriver(record, resolvedExitReason, now)

		if exitEvent ~= nil then
			table.insert(events, exitEvent)
		end
	end

	if nextDriverUserId == nil then
		return events
	end

	current = record.CurrentDriver

	if current ~= nil and current.PlayerUserId == nextDriverUserId then
		return events
	end

	record.NextDriverSequence += 1
	local session: DriverSession = {
		SessionId = string.format("%s-driver-%d", record.RuntimeCartId, record.NextDriverSequence),
		PlayerUserId = nextDriverUserId,
		EnteredAt = now,
		MovementStartedAt = nil,
		Platform = normalizePlatform(platform),
	}

	record.CurrentDriver = session
	record.HadDriver = true
	table.insert(
		events,
		eventRequest(
			AnalyticsEvents.CartDriverEntered,
			now,
			nextDriverUserId,
			record.RuntimeCartId,
			{
				CartId = record.CartId,
				DriverSessionId = session.SessionId,
				TimeSinceCartSpawn = safeDuration(record.SpawnedAt, now),
				Platform = session.Platform,
			}
		)
	)

	return events
end

function RuntimeMethods:MovementStarted(
	cartKey: any,
	driverUserId: number,
	direction: MovementDirection,
	now: number
): { EventRequest }
	local implementation = self :: RuntimePrivate
	local record = implementation._records[cartKey]
	local session = if record ~= nil then record.CurrentDriver else nil

	if
		record == nil
		or session == nil
		or session.PlayerUserId ~= driverUserId
		or session.MovementStartedAt ~= nil
		or (direction ~= "Forward" and direction ~= "Reverse")
	then
		return {}
	end

	session.MovementStartedAt = now
	record.HadMeaningfulMovement = true

	return {
		eventRequest(
			AnalyticsEvents.CartMovementStarted,
			now,
			driverUserId,
			record.RuntimeCartId,
			{
				CartId = record.CartId,
				DriverSessionId = session.SessionId,
				TimeSinceDriverEntered = safeDuration(session.EnteredAt, now),
				Platform = session.Platform,
				Direction = direction,
			}
		),
	}
end

function RuntimeMethods:RecordResetOutcome(outcome: ResetOutcome): { EventRequest }
	local implementation = self :: RuntimePrivate
	local noisyRejection = outcome.Reason == CartResetRequestProtocol.ReasonCodes.RateLimited
		or outcome.Reason == CartResetRequestProtocol.ReasonCodes.InvalidRequest

	if noisyRejection then
		local lastEmittedAt = implementation._lastResetNoiseByUserId[outcome.PlayerUserId]

		if
			lastEmittedAt ~= nil
			and outcome.RequestedAt - lastEmittedAt < implementation._resetNoiseThrottle
		then
			return {}
		end

		implementation._lastResetNoiseByUserId[outcome.PlayerUserId] = outcome.RequestedAt
	end

	local record = if outcome.CartKey ~= nil then implementation._records[outcome.CartKey] else nil
	local session = if record ~= nil then record.CurrentDriver else nil
	local sessionMatches = session ~= nil and session.PlayerUserId == outcome.PlayerUserId
	local runtimeCartId = if record ~= nil then record.RuntimeCartId else nil
	local driverSessionId = if sessionMatches then (session :: DriverSession).SessionId else nil
	local platform = if sessionMatches then (session :: DriverSession).Platform else "Unknown"
	local events: { EventRequest } = {
		eventRequest(
			AnalyticsEvents.CartResetRequested,
			outcome.RequestedAt,
			outcome.PlayerUserId,
			runtimeCartId,
			{
				CartId = if record ~= nil then record.CartId else nil,
				DriverSessionId = driverSessionId,
				Platform = platform,
			}
		),
	}

	if not outcome.Approved then
		table.insert(
			events,
			eventRequest(
				AnalyticsEvents.CartResetRejected,
				outcome.CompletedAt,
				outcome.PlayerUserId,
				runtimeCartId,
				{
					CartId = if record ~= nil then record.CartId else nil,
					DriverSessionId = driverSessionId,
					Reason = outcome.Reason,
					Platform = platform,
				}
			)
		)
		return events
	end

	if record == nil or not sessionMatches then
		return events
	end

	local resolvedSession = session :: DriverSession
	local resetStartedAt = outcome.ResetStartedAt or outcome.RequestedAt
	local resetCompletedAt = outcome.ResetCompletedAt or outcome.CompletedAt

	record.CompletedResetCount += 1
	table.insert(
		events,
		eventRequest(
			AnalyticsEvents.CartResetApproved,
			resetStartedAt,
			outcome.PlayerUserId,
			record.RuntimeCartId,
			{
				CartId = record.CartId,
				DriverSessionId = resolvedSession.SessionId,
				TimeSinceDriverEntered = safeDuration(resolvedSession.EnteredAt, resetStartedAt),
				Platform = resolvedSession.Platform,
			}
		)
	)
	table.insert(
		events,
		eventRequest(
			AnalyticsEvents.CartResetCompleted,
			resetCompletedAt,
			outcome.PlayerUserId,
			record.RuntimeCartId,
			{
				CartId = record.CartId,
				DriverSessionId = resolvedSession.SessionId,
				ResetDuration = safeDuration(resetStartedAt, resetCompletedAt),
				Platform = resolvedSession.Platform,
				DriverRetained = record.CurrentDriver == resolvedSession,
			}
		)
	)

	return events
end

function RuntimeMethods:RecordCorrection(correction: Correction): { EventRequest }
	local implementation = self :: RuntimePrivate
	local record = implementation._records[correction.CartKey]

	if record == nil or correction.Revision <= record.LastCorrectionRevision then
		return {}
	end

	record.LastCorrectionRevision = correction.Revision
	record.MovementCorrectionCount += 1
	local session = record.CurrentDriver
	local playerUserId = if session ~= nil then session.PlayerUserId else record.OwnerUserId

	return {
		eventRequest(
			AnalyticsEvents.CartMovementCorrected,
			correction.ServerTimestamp,
			playerUserId,
			record.RuntimeCartId,
			{
				CartId = record.CartId,
				DriverSessionId = if session ~= nil then session.SessionId else nil,
				Category = correction.Category,
				Severity = correction.Severity,
				Reason = correction.Reason,
				CorrectionCount = record.MovementCorrectionCount,
			}
		),
	}
end

function RuntimeMethods:DespawnCart(
	cartKey: any,
	despawnReason: string,
	driverExitReason: string,
	now: number
): { EventRequest }
	local implementation = self :: RuntimePrivate
	local record = implementation._records[cartKey]

	if record == nil then
		return {}
	end

	local events: { EventRequest } = {}
	local activeDriverPresent = record.CurrentDriver ~= nil
	local exitEvent = closeDriver(record, driverExitReason, now)

	if exitEvent ~= nil then
		table.insert(events, exitEvent)
	end

	table.insert(
		events,
		eventRequest(AnalyticsEvents.CartDespawned, now, record.OwnerUserId, record.RuntimeCartId, {
			CartId = record.CartId,
			SpawnId = record.SpawnId,
			CartLifetime = safeDuration(record.SpawnedAt, now),
			HadDriver = record.HadDriver,
			HadMeaningfulMovement = record.HadMeaningfulMovement,
			DespawnReason = despawnReason,
			ActiveDriverPresent = activeDriverPresent,
			CompletedResetCount = record.CompletedResetCount,
			MovementCorrectionCount = record.MovementCorrectionCount,
		})
	)

	implementation._records[cartKey] = nil
	return events
end

function RuntimeMethods:Stop(now: number): { EventRequest }
	local implementation = self :: RuntimePrivate
	local events: { EventRequest } = {}
	local keys: { any } = {}

	for key in implementation._records do
		table.insert(keys, key)
	end

	for _, key in keys do
		addAll(events, self:DespawnCart(key, "ServiceShutdown", "ServiceShutdown", now))
	end

	table.clear(implementation._lastResetNoiseByUserId)
	return events
end

function RuntimeMethods:RemovePlayer(playerUserId: number)
	local implementation = self :: RuntimePrivate

	implementation._lastResetNoiseByUserId[playerUserId] = nil
end

function RuntimeMethods:DiscardCart(cartKey: any)
	local implementation = self :: RuntimePrivate

	implementation._records[cartKey] = nil
end

function RuntimeMethods:GetRegisteredKeys(): { any }
	local implementation = self :: RuntimePrivate
	local keys: { any } = {}

	for key in implementation._records do
		table.insert(keys, key)
	end

	return keys
end

function RuntimeMethods:GetSnapshot(cartKey: any): Snapshot?
	local implementation = self :: RuntimePrivate
	local record = implementation._records[cartKey]

	if record == nil then
		return nil
	end

	local session = record.CurrentDriver

	return table.freeze({
		RuntimeCartId = record.RuntimeCartId,
		CurrentDriverSessionId = if session ~= nil then session.SessionId else nil,
		CurrentDriverUserId = if session ~= nil then session.PlayerUserId else nil,
		HadDriver = record.HadDriver,
		HadMeaningfulMovement = record.HadMeaningfulMovement,
		CompletedResetCount = record.CompletedResetCount,
		MovementCorrectionCount = record.MovementCorrectionCount,
	})
end

function RuntimeMethods:GetRecordCount(): number
	local implementation = self :: RuntimePrivate
	local count = 0

	for _ in implementation._records do
		count += 1
	end

	return count
end

return CartAnalyticsRuntime
