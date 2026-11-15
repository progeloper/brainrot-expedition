--!strict
-- Read-only view over WorldProgression.Pools (the operative region pools) and species CPS from
-- BrainrotCatalog. Never Phase12.RegionFallbackWeights.
local WorldProgression = require(script.Parent.Parent.Config.WorldProgression)
local BrainrotCatalog = require(script.Parent.Parent.Config.BrainrotCatalog)

local PoolData = {}

PoolData.TierOrder = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" })
local RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7 }

function PoolData.Rank(tier: string): number
	return RANK[tier] or 0
end

function PoolData.Pool(regionId: string): any
	return WorldProgression.Pools[regionId]
end

function PoolData.TierWeight(regionId: string, tier: string): number
	local pool = WorldProgression.Pools[regionId]
	if not pool then
		return 0
	end
	local species = pool.species[tier]
	if not species or #species == 0 then
		return 0
	end
	return pool.tierWeights[tier] or 0
end

-- { {id, share} } summing to 1 within the tier (uniform unless speciesWeightOverrides applies).
local rowCache: { [string]: { { id: string, share: number } } } = {}
function PoolData.SpeciesRows(regionId: string, tier: string): { { id: string, share: number } }
	local key = regionId .. "|" .. tier
	local cached = rowCache[key]
	if cached then
		return cached
	end
	local pool = WorldProgression.Pools[regionId]
	local rows = {}
	if pool and pool.species[tier] then
		local total = 0
		for _, id in pool.species[tier] do
			local weight = pool.speciesWeightOverrides[id] or 1
			table.insert(rows, { id = id, share = weight })
			total += weight
		end
		for _, row in rows do
			row.share /= total
		end
	end
	rowCache[key] = rows
	return rows
end

function PoolData.Cps(speciesId: string): number
	local definition = BrainrotCatalog.Get(speciesId)
	return if definition then definition.originalCashPerSecond else 0
end

function PoolData.Tier(speciesId: string): string?
	local definition = BrainrotCatalog.Get(speciesId)
	return if definition then definition.tier else nil
end

function PoolData.DisplayName(speciesId: string): string
	local definition = BrainrotCatalog.Get(speciesId)
	return if definition then definition.displayName else speciesId
end

-- Highest non-empty tier in the region (pity / Lucky fallbacks).
function PoolData.TopTier(regionId: string): string?
	local top = nil
	for _, tier in PoolData.TierOrder do
		if PoolData.TierWeight(regionId, tier) > 0 then
			top = tier
		end
	end
	return top
end

return table.freeze(PoolData)
