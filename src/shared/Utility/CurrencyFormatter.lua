--!strict

local CurrencyFormatter = {}

local function finiteNonNegative(value: any): number
	return if type(value) == "number"
			and value == value
			and value > -math.huge
			and value < math.huge
			and value >= 0
		then value
		else 0
end

local function oneDecimalWithoutZero(value: number): string
	return (string.format("%.1f", value):gsub("%.0$", ""))
end

local function withThousands(digits: string): string
	while true do
		local nextDigits, replacements = string.gsub(digits, "^(%d+)(%d%d%d)", "%1,%2")
		digits = nextDigits
		if replacements == 0 then
			return digits
		end
	end
end

function CurrencyFormatter.FormatWholeCash(value: any): string
	local safeValue = finiteNonNegative(value)
	return "$" .. withThousands(string.format("%.0f", math.floor(safeValue)))
end

-- Upgrade cards must not display a positive fractional shortfall as zero. This
-- formatter is presentation-only and never changes the authoritative wallet.
function CurrencyFormatter.FormatExactCash(value: any): string
	local safeValue = finiteNonNegative(value)
	-- Find a short decimal that round-trips to the actual number. Six fixed
	-- decimals can round an underfunded wallet up to an exact gate price.
	local formatted = string.format("%.17g", safeValue)
	for precision = 1, 17 do
		local candidate = string.format("%." .. tostring(precision) .. "g", safeValue)
		if tonumber(candidate) == safeValue then
			formatted = candidate
			break
		end
	end
	local mantissa, exponent = string.match(formatted, "^([%d%.]+)[eE]([%+%-]?%d+)$")
	if mantissa and exponent then
		local dot = string.find(mantissa, ".", 1, true)
		local digits = mantissa:gsub("%.", "")
		local decimalAt = (if dot then dot - 1 else #digits) + tonumber(exponent)
		if decimalAt <= 0 then
			formatted = "0." .. string.rep("0", -decimalAt) .. digits
		elseif decimalAt >= #digits then
			formatted = digits .. string.rep("0", decimalAt - #digits)
		else
			formatted = digits:sub(1, decimalAt) .. "." .. digits:sub(decimalAt + 1)
		end
	end
	local whole, fraction = string.match(formatted, "^(%d+)%.(%d+)$")
	if whole ~= nil and fraction ~= nil then
		return "$" .. withThousands(whole) .. "." .. fraction
	end
	return "$" .. withThousands(formatted)
end

function CurrencyFormatter.FormatCompactCash(value: any): string
	local safeValue = finiteNonNegative(value)
	local divisor = 1
	local suffix = ""
	if safeValue >= 1_000_000_000_000 then
		divisor = 1_000_000_000_000
		suffix = "T"
	elseif safeValue >= 1_000_000_000 then
		divisor = 1_000_000_000
		suffix = "B"
	elseif safeValue >= 1_000_000 then
		divisor = 1_000_000
		suffix = "M"
	elseif safeValue >= 1_000 then
		divisor = 1_000
		suffix = "K"
	end

	return "$" .. oneDecimalWithoutZero(safeValue / divisor) .. suffix
end

return CurrencyFormatter
