--!strict
-- Storage admission is preventive. It never acknowledges a receipt or replaces its permanent ledger.
local Http = game:GetService("HttpService")
local Capacity = {
	-- Roblox Creator Hub: Data store error codes and limits (verified 2026-10-19).
	EntryLimitBytes = 4194304,
	PromptMarginBytes = 524288,
	DeliveryMarginBytes = 16384,
	PromptReceiptReserve = 16,
	ReceiptLimit = 10000,
	-- Covers worst valid JSON escaping of all bounded receipt/operation strings,
	-- revision/time digit growth and the generated save operation identifier.
	ProjectionGrowthReserveBytes = 8192,
}
function Capacity.Copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, nested in value do
		copy[key] = Capacity.Copy(nested)
	end
	return copy
end
function Capacity.MeasureEnvelope(envelope: any, margin: number?): any
	if type(envelope) ~= "table" or type(envelope.Transport) ~= "table" or (envelope.Transport.Version ~= 3 and envelope.Transport.Version ~= 4) then
		return { ok = false, code = "ENVELOPE_MEASUREMENT_UNAVAILABLE" }
	end
	local ok, encoded = pcall(Http.JSONEncode, Http, envelope)
	if not ok then
		return { ok = false, code = "PROFILE_ENCODING_FAILED" }
	end
	local reserve = margin or Capacity.DeliveryMarginBytes
	local bytes = #encoded
	return {
		ok = bytes + reserve + Capacity.ProjectionGrowthReserveBytes <= Capacity.EntryLimitBytes,
		code = if bytes + reserve + Capacity.ProjectionGrowthReserveBytes <= Capacity.EntryLimitBytes
			then "HEADROOM_AVAILABLE"
			else "PROFILE_STORAGE_HEADROOM",
		encodedBytes = bytes,
		marginBytes = reserve,
		growthReserveBytes = Capacity.ProjectionGrowthReserveBytes,
		limitBytes = Capacity.EntryLimitBytes,
		headroomBytes = Capacity.EntryLimitBytes - bytes,
	}
end
function Capacity.CheckLedger(data: any, prompting: boolean): any
	local commerce = data and data.Commerce
	if not commerce or type(commerce.ReceiptCount) ~= "number" then
		return { ok = false, code = "PROFILE_NOT_READY" }
	end
	local reserve = if prompting then Capacity.PromptReceiptReserve else 1
	return {
		ok = commerce.ReceiptCount + reserve <= Capacity.ReceiptLimit,
		code = if commerce.ReceiptCount + reserve <= Capacity.ReceiptLimit
			then "HEADROOM_AVAILABLE"
			else "PAID_LEDGER_FULL",
	}
end
return table.freeze(Capacity)
