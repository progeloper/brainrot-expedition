--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartGreyboxValidationResult =
	require(ReplicatedStorage.Shared.Utility.CartGreyboxValidationResult)

type Result = CartGreyboxValidationResult.Result

export type ActiveScenario = {
	ScenarioId: string,
	SectionId: string,
	SpawnId: string,
	StartedAt: number,
	Cart: Model,
}

export type Diagnostics = {
	ActiveScenarioCount: number,
	ResultCount: number,
}

export type Runtime = {
	SetActive: (self: Runtime, userId: number, active: ActiveScenario) -> (),
	GetActive: (self: Runtime, userId: number) -> ActiveScenario?,
	ClearForCart: (self: Runtime, userId: number, cart: Model) -> boolean,
	RemovePlayer: (self: Runtime, userId: number) -> (),
	AddResult: (self: Runtime, result: Result) -> (),
	GetResults: (self: Runtime) -> { Result },
	ClearResults: (self: Runtime) -> (),
	GetDiagnostics: (self: Runtime) -> Diagnostics,
	Reset: (self: Runtime) -> (),
}

type RuntimePrivate = Runtime & {
	_activeByUserId: { [number]: ActiveScenario },
	_results: { Result },
}

local RuntimeMethods = {}
RuntimeMethods.__index = RuntimeMethods

local CartGreyboxValidationRuntime = {}

function CartGreyboxValidationRuntime.SelectFirstAvailableSpawnId(
	spawnIds: { string },
	isOccupied: (string) -> boolean
): string?
	for _, spawnId in spawnIds do
		if not isOccupied(spawnId) then
			return spawnId
		end
	end

	return nil
end

local function activeScenarioCount(activeByUserId: { [number]: ActiveScenario }): number
	local count = 0

	for _ in activeByUserId do
		count += 1
	end

	return count
end

function CartGreyboxValidationRuntime.new(): Runtime
	return setmetatable({
		_activeByUserId = {},
		_results = {},
	}, RuntimeMethods) :: any
end

function RuntimeMethods.SetActive(self: RuntimePrivate, userId: number, active: ActiveScenario)
	self._activeByUserId[userId] = active
end

function RuntimeMethods.GetActive(self: RuntimePrivate, userId: number): ActiveScenario?
	return self._activeByUserId[userId]
end

function RuntimeMethods.ClearForCart(self: RuntimePrivate, userId: number, cart: Model): boolean
	local current = self._activeByUserId[userId]

	if current == nil or current.Cart ~= cart then
		return false
	end

	self._activeByUserId[userId] = nil

	return true
end

function RuntimeMethods.RemovePlayer(self: RuntimePrivate, userId: number)
	self._activeByUserId[userId] = nil
end

function RuntimeMethods.AddResult(self: RuntimePrivate, result: Result)
	table.insert(self._results, result)
end

function RuntimeMethods.GetResults(self: RuntimePrivate): { Result }
	return table.clone(self._results)
end

function RuntimeMethods.ClearResults(self: RuntimePrivate)
	table.clear(self._results)
end

function RuntimeMethods.GetDiagnostics(self: RuntimePrivate): Diagnostics
	return {
		ActiveScenarioCount = activeScenarioCount(self._activeByUserId),
		ResultCount = #self._results,
	}
end

function RuntimeMethods.Reset(self: RuntimePrivate)
	table.clear(self._activeByUserId)
	table.clear(self._results)
end

return table.freeze(CartGreyboxValidationRuntime)
