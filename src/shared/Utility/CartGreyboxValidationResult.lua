--!strict

local CartGreyboxScenarios = require(script.Parent.Parent.Config.CartGreyboxScenarios)

export type Status = "Passed" | "Failed" | "Blocked" | "NotApplicable" | "ManualReviewRequired"
export type Severity = "S0" | "S1" | "S2" | "S3"
export type Scalar = string | number | boolean
export type Fields = { [string]: Scalar }

export type Result = {
	ScenarioId: string,
	Status: Status,
	Passed: boolean,
	Severity: Severity?,
	Observed: Fields,
	Expected: Fields,
	FailureCode: string?,
	Notes: string?,
	RecordedAt: number,
}

export type Request = {
	ScenarioId: string,
	Status: Status,
	Severity: Severity?,
	Observed: Fields?,
	Expected: Fields?,
	FailureCode: string?,
	Notes: string?,
	RecordedAt: number,
}

local CartGreyboxValidationResult = {}

local VALID_STATUSES: { [string]: boolean } = table.freeze({
	Passed = true,
	Failed = true,
	Blocked = true,
	NotApplicable = true,
	ManualReviewRequired = true,
})

local VALID_SEVERITIES: { [string]: boolean } = table.freeze({
	S0 = true,
	S1 = true,
	S2 = true,
	S3 = true,
})

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function cloneFields(value: unknown, fieldName: string): Fields
	if value == nil then
		return table.freeze({}) :: Fields
	end

	assert(type(value) == "table", string.format("%s must be a table", fieldName))

	local result: Fields = {}

	for key, fieldValue in value :: { [any]: any } do
		assert(
			type(key) == "string" and key ~= "",
			string.format("%s keys must be strings", fieldName)
		)
		assert(
			type(fieldValue) == "string"
				or type(fieldValue) == "boolean"
				or (type(fieldValue) == "number" and isFiniteNumber(fieldValue)),
			string.format("%s.%s must be a finite scalar", fieldName, key)
		)

		result[key] = fieldValue :: Scalar
	end

	return table.freeze(result)
end

function CartGreyboxValidationResult.Create(request: Request): Result
	assert(CartGreyboxScenarios.ById[request.ScenarioId] ~= nil, "ScenarioId is not registered")
	assert(VALID_STATUSES[request.Status] == true, "Status is unsupported")
	assert(
		isFiniteNumber(request.RecordedAt) and request.RecordedAt >= 0,
		"RecordedAt must be finite and nonnegative"
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

	if request.Notes ~= nil then
		assert(type(request.Notes) == "string", "Notes must be a string")
	end

	local result: Result = {
		ScenarioId = request.ScenarioId,
		Status = request.Status,
		Passed = request.Status == "Passed",
		Severity = request.Severity,
		Observed = cloneFields(request.Observed, "Observed"),
		Expected = cloneFields(request.Expected, "Expected"),
		FailureCode = request.FailureCode,
		Notes = request.Notes,
		RecordedAt = request.RecordedAt,
	}

	return table.freeze(result)
end

return table.freeze(CartGreyboxValidationResult)
