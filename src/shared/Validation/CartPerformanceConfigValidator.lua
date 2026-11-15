--!strict

local LoadCounts = require(script.Parent.Parent.Constants.CartPerformanceLoadCounts)
local ScenarioIds = require(script.Parent.Parent.Constants.CartPerformanceScenarioIds)

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
}

type AnyTable = { [any]: any }

local CartPerformanceConfigValidator = {}

-- Structural guards for Development evidence storage. They are not frame,
-- memory, or gameplay certification budgets.
local MAXIMUM_DURATION = 3600
local MAXIMUM_ENDURANCE_CYCLES = 1000
local MAXIMUM_SNAPSHOT_CAPACITY = 10000
local MAXIMUM_METRIC_FIELDS = 256

local ROOT_FIELDS = table.freeze({
	Enabled = true,
	LoadCounts = true,
	Scenarios = true,
	ByScenarioId = true,
	Development = true,
})

local SCENARIO_FIELDS = table.freeze({
	Id = true,
	Label = true,
})

local DEVELOPMENT_FIELDS = table.freeze({
	WarmupDuration = true,
	SteadyStateDuration = true,
	SnapshotInterval = true,
	CleanupObservationDuration = true,
	ActionObservationDuration = true,
	EnduranceCycleCount = true,
	MinimumSteadyStateCoverageRatio = true,
	SnapshotCapacity = true,
	MaximumMetricsPerSnapshot = true,
	MaximumSummaryMetrics = true,
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

local function validateExactArrayKeys(
	values: AnyTable,
	expectedLength: number,
	prefix: string,
	errors: { string }
)
	for key in values do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > expectedLength then
			addError(errors, string.format("%s contains unsupported key %s", prefix, tostring(key)))
		end
	end

	for index = 1, expectedLength do
		if values[index] == nil then
			addError(errors, string.format("%s[%d] is required", prefix, index))
		end
	end
end

local function validateLoadCounts(value: unknown, errors: { string })
	if type(value) ~= "table" then
		addError(errors, "LoadCounts must be a table")
		return
	end

	local values = value :: AnyTable

	validateExactArrayKeys(values, #LoadCounts.Ordered, "LoadCounts", errors)

	for index, expectedCount in LoadCounts.Ordered do
		local count = values[index]

		if not isFiniteNumber(count) or count % 1 ~= 0 or count <= 0 then
			addError(errors, string.format("LoadCounts[%d] must be a positive integer", index))
		elseif count ~= expectedCount then
			addError(
				errors,
				string.format(
					"LoadCounts[%d] must equal the central value %d",
					index,
					expectedCount
				)
			)
		end
	end
end

local function expectedScenarioIds(): { [string]: boolean }
	local result: { [string]: boolean } = {}

	for _, scenarioId in ScenarioIds.All do
		result[scenarioId] = true
	end

	return result
end

local function validateScenarios(
	value: unknown,
	expectedIds: { [string]: boolean },
	errors: { string }
): { [string]: string }
	local seenLabels: { [string]: string } = {}

	if type(value) ~= "table" then
		addError(errors, "Scenarios must be a table")
		return seenLabels
	end

	local values = value :: AnyTable

	validateExactArrayKeys(values, #ScenarioIds.All, "Scenarios", errors)

	for index = 1, #ScenarioIds.All do
		local scenarioValue = values[index]
		local path = string.format("Scenarios[%d]", index)

		if type(scenarioValue) ~= "table" then
			addError(errors, string.format("%s must be a table", path))
			continue
		end

		local scenario = scenarioValue :: AnyTable

		rejectUnknownFields(scenario, SCENARIO_FIELDS, path, errors)

		if type(scenario.Id) ~= "string" or scenario.Id == "" then
			addError(errors, string.format("%s.Id must be a non-empty string", path))
		elseif expectedIds[scenario.Id] ~= true then
			addError(errors, string.format("%s.Id is not a central performance scenario ID", path))
		elseif seenLabels[scenario.Id] then
			addError(errors, string.format("%s.Id duplicates %s", path, scenario.Id))
		else
			seenLabels[scenario.Id] = if type(scenario.Label) == "string"
				then scenario.Label
				else ""
		end

		if type(scenario.Label) ~= "string" or scenario.Label == "" then
			addError(errors, string.format("%s.Label must be a non-empty string", path))
		end
	end

	for expectedId in expectedIds do
		if seenLabels[expectedId] == nil then
			addError(errors, string.format("Scenarios is missing %s", expectedId))
		end
	end

	return seenLabels
end

local function validateScenarioLookup(
	value: unknown,
	expectedIds: { [string]: boolean },
	seenLabels: { [string]: string },
	errors: { string }
)
	if type(value) ~= "table" then
		addError(errors, "ByScenarioId must be a table")
		return
	end

	local lookup = value :: AnyTable

	for key, definitionValue in lookup do
		if type(key) ~= "string" or expectedIds[key] ~= true then
			addError(
				errors,
				string.format("ByScenarioId contains unsupported key %s", tostring(key))
			)
			continue
		end

		if type(definitionValue) ~= "table" then
			addError(errors, string.format("ByScenarioId.%s must be a scenario definition", key))
			continue
		end

		local definition = definitionValue :: AnyTable

		rejectUnknownFields(
			definition,
			SCENARIO_FIELDS,
			string.format("ByScenarioId.%s", key),
			errors
		)

		if definition.Id ~= key or definition.Label ~= seenLabels[key] then
			addError(
				errors,
				string.format("ByScenarioId.%s must match its scenario definition", key)
			)
		end
	end

	for expectedId in expectedIds do
		if lookup[expectedId] == nil or seenLabels[expectedId] == nil then
			addError(errors, string.format("ByScenarioId is missing %s", expectedId))
		end
	end
end

local function validateDuration(
	development: AnyTable,
	field: string,
	allowZero: boolean,
	errors: { string }
)
	local value = development[field]

	if not isFiniteNumber(value) then
		addError(errors, string.format("Development.%s must be a finite number", field))
	elseif
		(allowZero and value < 0)
		or (not allowZero and value <= 0)
		or value > MAXIMUM_DURATION
	then
		addError(
			errors,
			string.format(
				"Development.%s must be %s and at most %d",
				field,
				if allowZero then "nonnegative" else "positive",
				MAXIMUM_DURATION
			)
		)
	end
end

local function validatePositiveInteger(
	development: AnyTable,
	field: string,
	maximum: number,
	errors: { string }
)
	local value = development[field]

	if not isFiniteNumber(value) or value <= 0 or value % 1 ~= 0 or value > maximum then
		addError(
			errors,
			string.format("Development.%s must be a positive integer at most %d", field, maximum)
		)
	end
end

local function validateDevelopment(value: unknown, errors: { string })
	if type(value) ~= "table" then
		addError(errors, "Development must be a table")
		return
	end

	local development = value :: AnyTable

	rejectUnknownFields(development, DEVELOPMENT_FIELDS, "Development", errors)
	validateDuration(development, "WarmupDuration", true, errors)
	validateDuration(development, "SteadyStateDuration", false, errors)
	validateDuration(development, "SnapshotInterval", false, errors)
	validateDuration(development, "CleanupObservationDuration", true, errors)
	validateDuration(development, "ActionObservationDuration", false, errors)
	validatePositiveInteger(development, "EnduranceCycleCount", MAXIMUM_ENDURANCE_CYCLES, errors)

	local coverageRatio = development.MinimumSteadyStateCoverageRatio

	if not isFiniteNumber(coverageRatio) or coverageRatio <= 0 or coverageRatio > 1 then
		addError(
			errors,
			"Development.MinimumSteadyStateCoverageRatio must be finite and within (0, 1]"
		)
	end

	validatePositiveInteger(development, "SnapshotCapacity", MAXIMUM_SNAPSHOT_CAPACITY, errors)
	validatePositiveInteger(development, "MaximumMetricsPerSnapshot", MAXIMUM_METRIC_FIELDS, errors)
	validatePositiveInteger(development, "MaximumSummaryMetrics", MAXIMUM_METRIC_FIELDS, errors)

	local steadyStateDuration = development.SteadyStateDuration
	local snapshotInterval = development.SnapshotInterval
	local snapshotCapacity = development.SnapshotCapacity

	if
		isFiniteNumber(steadyStateDuration)
		and isFiniteNumber(snapshotInterval)
		and snapshotInterval > 0
		and steadyStateDuration < snapshotInterval
	then
		addError(errors, "Development.SnapshotInterval must not exceed SteadyStateDuration")
	end

	if
		isFiniteNumber(steadyStateDuration)
		and isFiniteNumber(snapshotInterval)
		and snapshotInterval > 0
		and isFiniteNumber(snapshotCapacity)
		and snapshotCapacity % 1 == 0
		and math.ceil(steadyStateDuration / snapshotInterval) > snapshotCapacity
	then
		addError(
			errors,
			"Development.SnapshotCapacity must hold one complete steady-state measurement window"
		)
	end
end

function CartPerformanceConfigValidator.Validate(config: unknown): ValidationResult
	local errors: { string } = {}

	if type(config) ~= "table" then
		return {
			IsValid = false,
			Errors = { "cart performance configuration must be a table" },
		}
	end

	local values = config :: AnyTable

	rejectUnknownFields(values, ROOT_FIELDS, "configuration", errors)

	if type(values.Enabled) ~= "boolean" then
		addError(errors, "Enabled must be a boolean")
	end

	validateLoadCounts(values.LoadCounts, errors)

	local expectedIds = expectedScenarioIds()
	local seenLabels = validateScenarios(values.Scenarios, expectedIds, errors)

	validateScenarioLookup(values.ByScenarioId, expectedIds, seenLabels, errors)
	validateDevelopment(values.Development, errors)

	return {
		IsValid = #errors == 0,
		Errors = errors,
	}
end

return table.freeze(CartPerformanceConfigValidator)
