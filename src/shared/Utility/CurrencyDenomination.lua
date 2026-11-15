--!strict
-- All consumers use final units. Only source tables and supported legacy saves convert.
local Currency = {
	LEGACY_CURRENCY_VERSION = 1,
	SCALED_CURRENCY_VERSION = 2,
	CURRENCY_SCALE_FACTOR = 1500,
	MAX_AMOUNT = 9007199254740991,
}

function Currency.Validate(value: any): (boolean, string?)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge or value < 0 then
		return false, "INVALID_MONETARY_VALUE"
	end
	if value > Currency.MAX_AMOUNT then return false, "MONETARY_OVERFLOW" end
	return true, nil
end

function Currency.Convert(value: any, version: any): (number?, string?)
	if version ~= 1 and version ~= 2 then return nil, "UNSUPPORTED_CURRENCY_VERSION" end
	local valid, reason = Currency.Validate(value)
	if not valid then return nil, reason end
	if version == 2 then return value, nil end
	if value > Currency.MAX_AMOUNT / 1500 then return nil, "MONETARY_OVERFLOW" end
	local converted = value * 1500
	if not Currency.Validate(converted) then return nil, "MONETARY_OVERFLOW" end
	-- Large products have a wider representable spacing. Check the exact fractional
	-- product against that spacing rather than silently dropping saved fractions.
	if converted >= 2 ^ 46 then
		local _, exponent = math.frexp(converted)
		local spacing = 2 ^ (exponent - 53)
		if ((value % 1) * 1500) % spacing ~= 0 then
			return nil, "MONETARY_PRECISION_UNSUPPORTED"
		end
	end
	return converted, nil
end

function Currency.FromLegacy(value: number): number
	local converted, reason = Currency.Convert(value, 1)
	assert(converted ~= nil, reason)
	return converted :: number
end

-- Mutates only a private normalized working record, never a live profile.
-- The caller persists amounts and marker together under the profile lease.
function Currency.MigrateRecord(data: any): (boolean, string?, boolean?)
	local version = data.CurrencyVersion
	if version == nil then
		if data.SchemaVersion ~= 2 then return false, "UNSUPPORTED_LEGACY_SCHEMA", nil end
		version = 1
	end
	if version ~= 1 and version ~= 2 then return false, "UNSUPPORTED_CURRENCY_VERSION", nil end
	local changes = {}
	local function plan(container, key): string?
		local amount, reason = Currency.Convert(container[key], version)
		if amount == nil then return reason end
		table.insert(changes, { container, key, amount })
		return nil
	end
	local reason = plan(data.Economy, "Balance")
	if reason then return false, reason, nil end
	for _, slot in data.Base.Slots do
		reason = plan(slot, "accumulatedCash")
		if reason then return false, reason, nil end
	end
	-- No durable replayable cash receipt is present in the current schema.
	-- Transport operation IDs/revisions and audit receipts remain unchanged.
	for _, change in changes do change[1][change[2]] = change[3] end
	data.CurrencyVersion = 2
	return true, nil, version == 1
end

return table.freeze(Currency)
