--!strict
-- B4 "1 in X". Natural odds only: P(tier) x P(species | tier) x P(mutation). A Normal individual uses
-- P(tier) x P(species) (no x0.96 Normal factor, so a Forest Rare reads "1 in 17"). Boosted odds are
-- never shown as natural. Formatting keeps two significant figures: 56, 100, 1.7K, 34K, 1.2M.
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)
local MutationCatalog = require(script.Parent.Parent.Config.MutationCatalog)
local PoolData = require(script.Parent.PoolData)

local OddsText = {}

local function twoSig(value: number): number
	if value <= 0 then
		return 0
	end
	local digits = math.floor(math.log10(value)) + 1
	local scale = 10 ^ (digits - 2)
	return math.floor(value / scale + 0.5) * scale
end

local function trim(value: number): string
	local text = string.format("%.1f", value)
	return (string.gsub(text, "%.0$", ""))
end

function OddsText.FormatOneIn(x: number): string
	if x ~= x or x == math.huge or x <= 0 then
		return "1 in ?"
	end
	x = math.max(1, x)
	local rounded = if x < 10 then math.floor(x + 0.5) else twoSig(x)
	if rounded >= 1e6 then
		return "1 in " .. trim(rounded / 1e6) .. "M"
	elseif rounded >= 1e3 then
		return "1 in " .. trim(rounded / 1e3) .. "K"
	end
	return "1 in " .. tostring(math.floor(rounded))
end

-- Natural probability of seeing this exact individual as one spawn in the region.
function OddsText.Probability(regionId: string, speciesId: string, mutationId: string?): number
	local tier = PoolData.Tier(speciesId)
	if not tier then
		return 0
	end
	local p = PoolData.TierWeight(regionId, tier)
	local share = 0
	for _, row in PoolData.SpeciesRows(regionId, tier) do
		if row.id == speciesId then
			share = row.share
		end
	end
	p *= share
	if mutationId and mutationId ~= "None" then
		local entry = MutationCatalog.ById[mutationId]
		p *= CoreLoop.Mutation.Base * (if entry then entry.share else 0)
	end
	return p
end

function OddsText.ForIndividual(regionId: string, speciesId: string, mutationId: string?): string
	local p = OddsText.Probability(regionId, speciesId, mutationId)
	return OddsText.FormatOneIn(if p > 0 then 1 / p else math.huge)
end

-- Mutation-only odds for the reveal chip ("GOLDEN! 1 in 100").
function OddsText.ForMutation(mutationId: string): string
	local entry = MutationCatalog.ById[mutationId]
	local p = CoreLoop.Mutation.Base * (if entry then entry.share else 0)
	return OddsText.FormatOneIn(if p > 0 then 1 / p else math.huge)
end

return table.freeze(OddsText)
