--!strict

export type ReasonCode =
	"Approved"
	| "RateLimited"
	| "NoActiveCart"
	| "CartUnavailable"
	| "NotDriver"
	| "ResetAlreadyActive"
	| "CooldownActive"
	| "InvalidRequest"
	| "ResetUnavailable"
	| "InternalFailure"

export type Result = {
	Approved: boolean,
	Reason: ReasonCode,
	RetryAfterSeconds: number,
	ServerTimestamp: number,
	SafeToResume: boolean,
}

local CartResetRequestProtocol = {}

CartResetRequestProtocol.ReasonCodes = table.freeze({
	Approved = "Approved",
	RateLimited = "RateLimited",
	NoActiveCart = "NoActiveCart",
	CartUnavailable = "CartUnavailable",
	NotDriver = "NotDriver",
	ResetAlreadyActive = "ResetAlreadyActive",
	CooldownActive = "CooldownActive",
	InvalidRequest = "InvalidRequest",
	ResetUnavailable = "ResetUnavailable",
	InternalFailure = "InternalFailure",
})

local VALID_REASON_CODES: { [ReasonCode]: boolean } = table.freeze({
	Approved = true,
	RateLimited = true,
	NoActiveCart = true,
	CartUnavailable = true,
	NotDriver = true,
	ResetAlreadyActive = true,
	CooldownActive = true,
	InvalidRequest = true,
	ResetUnavailable = true,
	InternalFailure = true,
})

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function CartResetRequestProtocol.IsReasonCode(value: unknown): boolean
	return type(value) == "string" and VALID_REASON_CODES[value :: ReasonCode] == true
end

function CartResetRequestProtocol.CreateResult(
	approved: boolean,
	reason: ReasonCode,
	retryAfterSeconds: number,
	serverTimestamp: number,
	safeToResume: boolean
): Result
	assert(CartResetRequestProtocol.IsReasonCode(reason), "reset result reason code is invalid")
	assert(
		approved == (reason == CartResetRequestProtocol.ReasonCodes.Approved),
		"reset approval must match its reason code"
	)
	assert(
		isFiniteNumber(retryAfterSeconds) and retryAfterSeconds >= 0,
		"reset retry duration must be finite and non-negative"
	)
	assert(isFiniteNumber(serverTimestamp), "reset server timestamp must be finite")

	return table.freeze({
		Approved = approved,
		Reason = reason,
		RetryAfterSeconds = retryAfterSeconds,
		ServerTimestamp = serverTimestamp,
		SafeToResume = safeToResume,
	})
end

function CartResetRequestProtocol.IsResult(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end

	local candidate = value :: any

	return type(candidate.Approved) == "boolean"
		and CartResetRequestProtocol.IsReasonCode(candidate.Reason)
		and candidate.Approved == (candidate.Reason == CartResetRequestProtocol.ReasonCodes.Approved)
		and isFiniteNumber(candidate.RetryAfterSeconds)
		and candidate.RetryAfterSeconds >= 0
		and isFiniteNumber(candidate.ServerTimestamp)
		and type(candidate.SafeToResume) == "boolean"
end

return table.freeze(CartResetRequestProtocol)
