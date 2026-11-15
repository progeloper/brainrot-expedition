--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LoadCounts = require(ReplicatedStorage.Shared.Constants.CartPerformanceLoadCounts)
local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartPerformanceScenarioIds)

export type State = "Idle" | "Setup" | "Running" | "Cleanup"

export type Adapter = {
	Spawn: (ownerUserId: number, loadIndex: number, scenarioId: string) -> any,
	Cleanup: (handle: any, ownerUserId: number, loadIndex: number) -> (),
}

export type Snapshot = {
	State: State,
	ScenarioId: string?,
	LoadCount: number,
	ActiveCount: number,
	OwnerUserIds: { number },
	StopRequested: boolean,
}

export type Runtime = {
	Start: (self: Runtime, scenarioId: string, loadCount: number) -> Snapshot,
	Stop: (self: Runtime) -> boolean,
	GetState: (self: Runtime) -> State,
	GetActiveCount: (self: Runtime) -> number,
	GetOwnerUserIds: (self: Runtime) -> { number },
	GetSnapshot: (self: Runtime) -> Snapshot,
}

type ActiveRecord = {
	Handle: any,
	OwnerUserId: number,
	LoadIndex: number,
}

type RuntimePrivate = Runtime & {
	_adapter: Adapter,
	_state: State,
	_scenarioId: string?,
	_loadCount: number,
	_records: { ActiveRecord },
	_stopRequested: boolean,
}

local RuntimeMethods = {}
RuntimeMethods.__index = RuntimeMethods

local CartPerformanceLoadRuntime = {}

-- These IDs are reserved for Development-only Phase 1T carts. They are far
-- outside the small negative IDs Studio may assign to local test players and
-- can never collide with a Production Roblox UserId.
local SYNTHETIC_OWNER_USER_IDS: { number } = {}

for loadIndex = 1, LoadCounts.Target do
	table.insert(SYNTHETIC_OWNER_USER_IDS, -1_910_000_000 - loadIndex)
end

table.freeze(SYNTHETIC_OWNER_USER_IDS)

local VALID_LOAD_COUNTS: { [number]: boolean } = {}

for _, loadCount in LoadCounts.Ordered do
	VALID_LOAD_COUNTS[loadCount] = true
end

table.freeze(VALID_LOAD_COUNTS)

local VALID_SCENARIO_IDS: { [string]: boolean } = {}

for _, scenarioId in ScenarioIds.All do
	VALID_SCENARIO_IDS[scenarioId] = true
end

table.freeze(VALID_SCENARIO_IDS)

function CartPerformanceLoadRuntime.IsAvailable(
	environmentName: string,
	debugToolsEnabled: boolean,
	isStudio: boolean,
	configuredEnabled: boolean
): boolean
	return environmentName == "Development"
		and debugToolsEnabled == true
		and isStudio == true
		and configuredEnabled == true
end

local function cloneOwnerUserIds(records: { ActiveRecord }): { number }
	local result: { number } = {}

	for _, record in records do
		table.insert(result, record.OwnerUserId)
	end

	return table.freeze(result)
end

local function clearRunContext(self: RuntimePrivate)
	self._scenarioId = nil
	self._loadCount = 0
	self._stopRequested = false
	self._state = "Idle"
end

local function cleanupRecords(self: RuntimePrivate): (boolean, string?)
	self._state = "Cleanup"
	local errors: { string } = {}

	for recordIndex = #self._records, 1, -1 do
		local record = self._records[recordIndex]
		local succeeded, cleanupError =
			pcall(self._adapter.Cleanup, record.Handle, record.OwnerUserId, record.LoadIndex)

		-- Release the opaque handle even when its adapter cleanup reports an
		-- error. All remaining records are still attempted in reverse order.
		table.remove(self._records, recordIndex)

		if not succeeded then
			table.insert(
				errors,
				string.format("load index %d: %s", record.LoadIndex, tostring(cleanupError))
			)
		end
	end

	clearRunContext(self)

	if #errors > 0 then
		return false, table.concat(errors, "; ")
	end

	return true, nil
end

local function assertStartRequest(scenarioId: string, loadCount: number)
	assert(
		type(scenarioId) == "string" and VALID_SCENARIO_IDS[scenarioId] == true,
		"scenarioId must be a central Phase 1T scenario ID"
	)
	assert(
		type(loadCount) == "number"
			and loadCount == loadCount
			and math.abs(loadCount) < math.huge
			and loadCount % 1 == 0
			and VALID_LOAD_COUNTS[loadCount] == true,
		"loadCount must be one of the central Phase 1T load counts"
	)
end

function CartPerformanceLoadRuntime.new(adapter: Adapter): Runtime
	assert(type(adapter) == "table", "performance load adapter must be a table")
	assert(type(adapter.Spawn) == "function", "performance load adapter Spawn is required")
	assert(type(adapter.Cleanup) == "function", "performance load adapter Cleanup is required")

	return setmetatable({
		_adapter = adapter,
		_state = "Idle",
		_scenarioId = nil,
		_loadCount = 0,
		_records = {},
		_stopRequested = false,
	}, RuntimeMethods) :: any
end

function RuntimeMethods.Start(self: RuntimePrivate, scenarioId: string, loadCount: number): Snapshot
	assert(self._state == "Idle", "performance load runtime is already active")
	assertStartRequest(scenarioId, loadCount)

	self._state = "Setup"
	self._scenarioId = scenarioId
	self._loadCount = loadCount
	self._stopRequested = false

	for loadIndex = 1, loadCount do
		local ownerUserId = SYNTHETIC_OWNER_USER_IDS[loadIndex]
		local spawnSucceeded, handleOrError =
			pcall(self._adapter.Spawn, ownerUserId, loadIndex, scenarioId)

		if not spawnSucceeded or handleOrError == nil then
			local setupError = if spawnSucceeded
				then string.format("load index %d returned no handle", loadIndex)
				else string.format("load index %d: %s", loadIndex, tostring(handleOrError))
			local cleanupSucceeded, cleanupError = cleanupRecords(self)
			local message = string.format("performance load setup failed: %s", setupError)

			if not cleanupSucceeded then
				message ..= string.format("; cleanup failed: %s", tostring(cleanupError))
			end

			error(message, 2)
		end

		table.insert(self._records, {
			Handle = handleOrError,
			OwnerUserId = ownerUserId,
			LoadIndex = loadIndex,
		})

		-- Stop can be requested while an injected Spawn callback yields or from
		-- inside that callback. The returned handle is captured first so partial
		-- setup is still cleaned deterministically.
		if self._stopRequested then
			local cleanupSucceeded, cleanupError = cleanupRecords(self)
			local message = "performance load setup was stopped"

			if not cleanupSucceeded then
				message ..= string.format("; cleanup failed: %s", tostring(cleanupError))
			end

			error(message, 2)
		end
	end

	self._state = "Running"

	return self:GetSnapshot()
end

function RuntimeMethods.Stop(self: RuntimePrivate): boolean
	if self._state == "Idle" or self._state == "Cleanup" then
		return false
	end

	if self._state == "Setup" then
		self._stopRequested = true
		return true
	end

	local cleanupSucceeded, cleanupError = cleanupRecords(self)

	if not cleanupSucceeded then
		error(string.format("performance load cleanup failed: %s", tostring(cleanupError)), 2)
	end

	return true
end

function RuntimeMethods.GetState(self: RuntimePrivate): State
	return self._state
end

function RuntimeMethods.GetActiveCount(self: RuntimePrivate): number
	return #self._records
end

function RuntimeMethods.GetOwnerUserIds(self: RuntimePrivate): { number }
	return cloneOwnerUserIds(self._records)
end

function RuntimeMethods.GetSnapshot(self: RuntimePrivate): Snapshot
	return table.freeze({
		State = self._state,
		ScenarioId = self._scenarioId,
		LoadCount = self._loadCount,
		ActiveCount = #self._records,
		OwnerUserIds = cloneOwnerUserIds(self._records),
		StopRequested = self._stopRequested,
	})
end

CartPerformanceLoadRuntime.SyntheticOwnerUserIds = SYNTHETIC_OWNER_USER_IDS

return table.freeze(CartPerformanceLoadRuntime)
