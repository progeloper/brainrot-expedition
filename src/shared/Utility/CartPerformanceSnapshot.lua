--!strict

local CartPerformanceTest = require(script.Parent.Parent.Config.CartPerformanceTest)

export type Stage =
	"ColdSetup"
	| "LoadCreation"
	| "Warmup"
	| "SteadyState"
	| "LifecycleStress"
	| "Cleanup"

export type Metrics = { [string]: number }

export type Request = {
	ScenarioId: string,
	LoadCount: number,
	Stage: Stage,
	RecordedAt: number,
	Metrics: Metrics?,
}

export type Snapshot = {
	ScenarioId: string,
	LoadCount: number,
	Stage: Stage,
	RecordedAt: number,
	Metrics: Metrics,
}

export type Buffer = {
	Capacity: number,
	Count: number,
	NextIndex: number,
	Values: { Snapshot? },
}

local CartPerformanceSnapshot = {}

local Stages = table.freeze({
	ColdSetup = "ColdSetup",
	LoadCreation = "LoadCreation",
	Warmup = "Warmup",
	SteadyState = "SteadyState",
	LifecycleStress = "LifecycleStress",
	Cleanup = "Cleanup",
})

local VALID_STAGES: { [string]: boolean } = {}

for _, stage in Stages do
	VALID_STAGES[stage] = true
end

table.freeze(VALID_STAGES)

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isSupportedLoadCount(loadCount: number): boolean
	for _, supportedCount in CartPerformanceTest.LoadCounts do
		if supportedCount == loadCount then
			return true
		end
	end

	return false
end

local function validateArrayKeys(values: { [any]: any }, length: number, fieldName: string)
	for key in values do
		assert(
			type(key) == "number" and key % 1 == 0 and key >= 1 and key <= length,
			string.format("%s must be a contiguous array", fieldName)
		)
	end
end

function CartPerformanceSnapshot.CloneMetrics(value: unknown, maximumCount: number?): Metrics
	if value == nil then
		return table.freeze({}) :: Metrics
	end

	assert(type(value) == "table", "Metrics must be a table")

	local defaultMaximum = CartPerformanceTest.Development.MaximumMetricsPerSnapshot
	local configuredMaximum =
		math.max(defaultMaximum, CartPerformanceTest.Development.MaximumSummaryMetrics)
	local limit = maximumCount or defaultMaximum

	assert(
		type(limit) == "number"
			and limit == limit
			and math.abs(limit) < math.huge
			and limit > 0
			and limit % 1 == 0
			and limit <= configuredMaximum,
		"maximum metric count must be a supported positive integer"
	)

	local result: Metrics = {}
	local count = 0

	for key, metricValue in value :: { [any]: any } do
		assert(type(key) == "string" and key ~= "", "metric keys must be non-empty strings")
		assert(isFiniteNumber(metricValue), string.format("metric %s must be a finite number", key))

		count += 1
		assert(count <= limit, string.format("metrics must contain at most %d values", limit))
		result[key] = metricValue :: number
	end

	return table.freeze(result)
end

function CartPerformanceSnapshot.Create(request: Request): Snapshot
	assert(type(request) == "table", "performance snapshot request must be a table")
	assert(
		CartPerformanceTest.ByScenarioId[request.ScenarioId] ~= nil,
		"ScenarioId is not registered"
	)
	assert(
		isFiniteNumber(request.LoadCount)
			and request.LoadCount % 1 == 0
			and isSupportedLoadCount(request.LoadCount),
		"LoadCount is not supported"
	)
	assert(VALID_STAGES[request.Stage] == true, "Stage is unsupported")
	assert(
		isFiniteNumber(request.RecordedAt) and request.RecordedAt >= 0,
		"RecordedAt must be finite and nonnegative"
	)

	return table.freeze({
		ScenarioId = request.ScenarioId,
		LoadCount = request.LoadCount,
		Stage = request.Stage,
		RecordedAt = request.RecordedAt,
		Metrics = CartPerformanceSnapshot.CloneMetrics(request.Metrics),
	})
end

function CartPerformanceSnapshot.CreateBuffer(capacity: number?): Buffer
	local resolvedCapacity = capacity or CartPerformanceTest.Development.SnapshotCapacity

	assert(
		isFiniteNumber(resolvedCapacity)
			and resolvedCapacity > 0
			and resolvedCapacity % 1 == 0
			and resolvedCapacity <= CartPerformanceTest.Development.SnapshotCapacity,
		"snapshot buffer capacity must be a supported positive integer"
	)

	return {
		Capacity = resolvedCapacity,
		Count = 0,
		NextIndex = 1,
		Values = {},
	}
end

function CartPerformanceSnapshot.Add(buffer: Buffer, request: Request): Snapshot
	local snapshot = CartPerformanceSnapshot.Create(request)

	buffer.Values[buffer.NextIndex] = snapshot
	buffer.NextIndex = if buffer.NextIndex == buffer.Capacity then 1 else buffer.NextIndex + 1
	buffer.Count = math.min(buffer.Count + 1, buffer.Capacity)

	return snapshot
end

function CartPerformanceSnapshot.Read(buffer: Buffer): { Snapshot }
	local result: { Snapshot } = {}
	local firstIndex = if buffer.Count < buffer.Capacity then 1 else buffer.NextIndex

	for offset = 0, buffer.Count - 1 do
		local index = ((firstIndex + offset - 1) % buffer.Capacity) + 1
		local snapshot = buffer.Values[index]

		assert(snapshot ~= nil, "snapshot buffer contains a missing value")
		table.insert(result, snapshot)
	end

	validateArrayKeys(result, #result, "snapshots")

	return table.freeze(result)
end

function CartPerformanceSnapshot.Clear(buffer: Buffer)
	table.clear(buffer.Values)
	buffer.Count = 0
	buffer.NextIndex = 1
end

function CartPerformanceSnapshot.GetCount(buffer: Buffer): number
	return buffer.Count
end

CartPerformanceSnapshot.Stages = Stages

return table.freeze(CartPerformanceSnapshot)
