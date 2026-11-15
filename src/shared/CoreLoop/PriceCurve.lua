--!strict
-- Core Loop V2 C4 lever (b): one global Cash price factor (owner approved x4.33 on 14 Nov 2026, the
-- factor the economy sim solved for an 80 s nominal trip; to be revised once real trip times are
-- measured). Applies to region gates, cart Speed (and the Training rollers that replace it), Cargo and
-- base expansions only. CPS, sale values, odds, weapons, carts, designs and Robux prices are untouched.
-- With Core Loop V2 off the factor is exactly 1, so every price stays byte-identical (F-0).
-- Config modules apply it once at require time; CoreLoopFlags latches per session, so server and
-- client always agree.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PriceCurve = {}

local cached: number? = nil

function PriceCurve.Factor(): number
	if cached == nil then
		local Config = ReplicatedStorage.Shared.Config
		local enabled = require(Config.CoreLoopFlags).Enabled()
		local factor = (require(Config.CoreLoop) :: any).Economy.PriceCurveFactor
		cached = if enabled and type(factor) == "number" and factor > 0 then factor else 1
	end
	return cached :: number
end

-- Rounds to three significant figures so scaled prices read cleanly (2.17B, not 2,165,000,000).
function PriceCurve.Round(value: number): number
	if value <= 0 then
		return value
	end
	local magnitude = 10 ^ (math.floor(math.log10(value)) - 2)
	return math.floor(value / magnitude + 0.5) * magnitude
end

function PriceCurve.Apply(price: number, factor: number): number
	if factor == 1 or price <= 0 then
		return price
	end
	return PriceCurve.Round(price * factor)
end

function PriceCurve.Scale(price: number): number
	return PriceCurve.Apply(price, PriceCurve.Factor())
end

return PriceCurve
