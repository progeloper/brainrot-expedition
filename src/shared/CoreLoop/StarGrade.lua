--!strict
-- §3 grades. Value = originalCashPerSecond(species) x mutation multiplier (workbook units).
-- RegionMean = expected Normal value of one spawn from WorldProgression.Pools (uniform within a tier,
-- honouring speciesWeightOverrides such as Glitch BRT_031 : BRT_032 = 2999 : 1).
-- Pure apart from reading frozen config tables.
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)
local MutationRoller = require(script.Parent.MutationRoller)
local PoolData = require(script.Parent.PoolData)

export type Grade = "Star" | "Super" | "Jackpot"

local StarGrade = {}

local meanCache: { [string]: number } = {}

function StarGrade.RegionMean(regionId: string): number
	local cached = meanCache[regionId]
	if cached then
		return cached
	end
	local mean = 0
	for _, tier in PoolData.TierOrder do
		local p = PoolData.TierWeight(regionId, tier)
		if p > 0 then
			for _, row in PoolData.SpeciesRows(regionId, tier) do
				mean += p * row.share * PoolData.Cps(row.id)
			end
		end
	end
	meanCache[regionId] = mean
	return mean
end

function StarGrade.Value(speciesId: string, mutationId: string?): number
	return PoolData.Cps(speciesId) * MutationRoller.Multiplier(mutationId)
end

function StarGrade.FromValue(value: number, mean: number): Grade
	local ratio = if mean > 0 then value / mean else 0
	if ratio >= CoreLoop.Star.JackpotMultiple then
		return "Jackpot"
	elseif ratio >= CoreLoop.Star.SuperMultiple then
		return "Super"
	end
	return "Star"
end

-- Visible grade ignores the mutation (Normal value); true grade includes it (revealed on KO).
function StarGrade.Visible(regionId: string, speciesId: string): Grade
	return StarGrade.FromValue(StarGrade.Value(speciesId, "None"), StarGrade.RegionMean(regionId))
end

function StarGrade.True(regionId: string, speciesId: string, mutationId: string?): Grade
	return StarGrade.FromValue(
		StarGrade.Value(speciesId, mutationId),
		StarGrade.RegionMean(regionId)
	)
end

local RANK = { Star = 1, Super = 2, Jackpot = 3 }
function StarGrade.Rank(grade: Grade): number
	return RANK[grade]
end

function StarGrade.Thresholds(regionId: string): (number, number, number)
	local mean = StarGrade.RegionMean(regionId)
	return mean, mean * CoreLoop.Star.SuperMultiple, mean * CoreLoop.Star.JackpotMultiple
end

return table.freeze(StarGrade)
