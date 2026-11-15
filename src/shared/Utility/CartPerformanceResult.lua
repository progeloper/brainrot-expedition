--!strict

local CartPerformanceTest = require(script.Parent.Parent.Config.CartPerformanceTest)
local CartPerformanceSnapshot = require(script.Parent.CartPerformanceSnapshot)

type Snapshot = CartPerformanceSnapshot.Snapshot

export type Status = "Passed" | "Failed" | "Blocked"
export type Severity = "S0" | "S1" | "S2" | "S3"
export type Metrics = CartPerformanceSnapshot.Metrics

export type Request = {
	ScenarioId: string,
	LoadCount: number,
	Status: Status,
	Severity: Severity?,
	StartedAt: number,
	CompletedAt: number,
	Summary: Metrics?,
	Snapshots: { Snapshot }?,
	FailureCode: string?,
	Notes: string?,
}

export type Result = {
	ScenarioId: string,
	LoadCount: number,
	Status: Status,
	Passed: boolean,
	Severity: Severity?,
	StartedAt: number,
	CompletedAt: number,
	Duration: number,
	Summary: Metrics,
	Snapshots: { Snapshot },
	SnapshotCount: number,
	FailureCode: string?,
	Notes: string?,
}

local CartPerformanceResult = {}

local VALID_STATUSES: { [string]: boolean } = table.freeze({
	Passed = true,
	Failed = true,
	Blocked = true,
})

local VALID_SEVERITIES: { [string]: boolean } = table.freeze({
	S0 = true,
	S1 = true,
	S2 = true,
	S3 = true,
})

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

local function cloneSnapshots(
	value: unknown,
	scenarioId: string,
	loadCount: number,
	startedAt: number,
	completedAt: number
): { Snapshot }
	if value == nil then
		return table.freeze({}) :: { Snapshot }
	end

	assert(type(value) == "table", "Snapshots must be a table")

	local source = value :: { [any]: any }
	local count = #source

	assert(
		count <= CartPerformanceTest.Development.SnapshotCapacity,
		"Snapshots exceeds the configured bounded capacity"
	)

	for key in source do
		assert(
			type(key) == "number" and key % 1 == 0 and key >= 1 and key <= count,
			"Snapshots must be a contiguous array"
		)
	end

	local snapshots: { Snapshot } = {}
	local previousRecordedAt = startedAt

	for index = 1, count do
		local sourceSnapshot = source[index]

		assert(type(sourceSnapshot) == "table", "Snapshots entries must be tables")

		local snapshot = CartPerformanceSnapshot.Create({
			ScenarioId = sourceSnapshot.ScenarioId,
			LoadCount = sourceSnapshot.LoadCount,
			Stage = sourceSnapshot.Stage,
			RecordedAt = sourceSnapshot.RecordedAt,
			Metrics = sourceSnapshot.Metrics,
		})

		assert(snapshot.ScenarioId == scenarioId, "snapshot scenario must match result")
		assert(snapshot.LoadCount == loadCount, "snapshot load count must match result")
		assert(
			snapshot.RecordedAt >= startedAt and snapshot.RecordedAt <= completedAt,
			"snapshot time must be within the result window"
		)
		assert(snapshot.RecordedAt >= previousRecordedAt, "snapshots must be chronological")

		previousRecordedAt = snapshot.RecordedAt
		table.insert(snapshots, snapshot)
	end

	return table.freeze(snapshots)
end

function CartPerformanceResult.Create(request: Request): Result
	assert(type(request) == "table", "performance result request must be a table")
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
	assert(VALID_STATUSES[request.Status] == true, "Status is unsupported")
	assert(
		isFiniteNumber(request.StartedAt) and request.StartedAt >= 0,
		"StartedAt must be finite and nonnegative"
	)
	assert(
		isFiniteNumber(request.CompletedAt) and request.CompletedAt >= request.StartedAt,
		"CompletedAt must be finite and not precede StartedAt"
	)

	if request.Severity ~= nil then
		assert(VALID_SEVERITIES[request.Severity] == true, "Severity is unsupported")
	end

	if request.FailureCode ~= nil then
		assert(
			type(request.FailureCode) == "string" and request.FailureCode ~= "",
			"FailureCode must be non-empty"
		)
	end

	if request.Status == "Passed" then
		assert(request.Severity == nil, "Passed results cannot include a failure severity")
		assert(request.FailureCode == nil, "Passed results cannot include a failure code")
	end

	if request.Notes ~= nil then
		assert(type(request.Notes) == "string", "Notes must be a string")
	end

	local snapshots = cloneSnapshots(
		request.Snapshots,
		request.ScenarioId,
		request.LoadCount,
		request.StartedAt,
		request.CompletedAt
	)

	assert(request.Status == "Blocked" or #snapshots > 0, "completed results require evidence")

	return table.freeze({
		ScenarioId = request.ScenarioId,
		LoadCount = request.LoadCount,
		Status = request.Status,
		Passed = request.Status == "Passed",
		Severity = request.Severity,
		StartedAt = request.StartedAt,
		CompletedAt = request.CompletedAt,
		Duration = request.CompletedAt - request.StartedAt,
		Summary = CartPerformanceSnapshot.CloneMetrics(
			request.Summary,
			CartPerformanceTest.Development.MaximumSummaryMetrics
		),
		Snapshots = snapshots,
		SnapshotCount = #snapshots,
		FailureCode = request.FailureCode,
		Notes = request.Notes,
	})
end

return table.freeze(CartPerformanceResult)
