--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.Phase12)
local Catalog = require(ReplicatedStorage.Shared.Config.MutationCatalog)
local Species = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local WeaponTiersV2 = require(ReplicatedStorage.Shared.Config.WeaponTiersV2)
local Rules = {}
function Rules.IsFinite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
function Rules.NormalizeMutation(value)
	if value == nil or value == "Normal" or value == "None" then
		return "None"
	end
	if value == "Celestial" then
		return "Astral"
	end
	return if type(value) == "string" and Catalog.ById[value] then value else nil
end
function Rules.MutationMultiplier(value)
	local id = Rules.NormalizeMutation(value)
	assert(id, "Unknown mutation ID")
	return Catalog.ById[id].multiplier
end
function Rules.RecordMutation(record)
	local metadata = record.Metadata or {}
	local legacy = metadata.Mutation
	return Rules.NormalizeMutation(
		record.MutationId
			or record.mutationId
			or metadata.MutationId
			or (type(legacy) == "table" and (legacy.Id or legacy.MutationId))
	)
end
function Rules.EffectiveValues(speciesId, mutationId)
	local definition = Species.Get(speciesId)
	if not definition then
		return nil
	end
	local id = Rules.NormalizeMutation(mutationId)
	if not id then
		return nil
	end
	local multiplier = Catalog.ById[id].multiplier
	return table.freeze({
		cashPerSecond = definition.cashPerSecond * multiplier,
		sellValue = definition.sellValue * multiplier,
		multiplier = multiplier,
	})
end
function Rules.HpForRarity(rarity)
	return Config.HpByRarity[rarity]
end
-- Max HP for an individual. regionId is its spawn/population region, fixed at spawn. With Weapon
-- Tiers V2 off (the default) regionId is ignored and this is exactly HpByRarity. v2Enabled is an
-- explicit override for pure tests; nil uses the session's latched FeatureFlags.WeaponTiersV2Enabled.
function Rules.HpForRarityInRegion(rarity, regionId, v2Enabled)
	local base = Rules.HpForRarity(rarity)
	if base == nil then
		return nil
	end
	local enabled = if v2Enabled == nil then WeaponTiersV2.Enabled() else v2Enabled == true
	return if enabled then base * WeaponTiersV2.HpMultiplierForRegion(regionId) else base
end
function Rules.HpForSpecies(speciesId, regionId, v2Enabled)
	local definition = Species.Get(speciesId)
	return if definition
		then Rules.HpForRarityInRegion(definition.tier, regionId, v2Enabled)
		else nil
end
function Rules.GroundSleepForRarity(rarity)
	return Config.GroundSleepByRarity[rarity]
end
function Rules.GroundSleepForSpecies(speciesId)
	local definition = Species.Get(speciesId)
	return if definition then Rules.GroundSleepForRarity(definition.tier) else nil
end
function Rules.Damage(remaining, maxHp, multiplier, baseDamage)
	local damage = if baseDamage == nil then Config.BaseDamage else baseDamage
	assert(
		Rules.IsFinite(remaining) and Rules.IsFinite(maxHp) and maxHp > 0 and remaining >= 0 and remaining <= maxHp,
		"Invalid HP"
	)
	assert(Rules.IsFinite(multiplier) and multiplier > 0 and Rules.IsFinite(damage) and damage > 0, "Invalid damage")
	return math.clamp(remaining - damage * multiplier, 0, maxHp)
end
local function unit(random)
	local value = if type(random) == "function" then random() else random:NextNumber()
	assert(Rules.IsFinite(value) and value >= 0 and value <= 1, "RNG must return [0,1]")
	return value
end
function Rules.SelectWeighted(entries, random)
	assert(type(entries) == "table", "Weight entries required")
	local positive, total, seen = {}, 0, {}
	for _, entry in entries do
		assert(
			type(entry) == "table" and type(entry.id) == "string" and not seen[entry.id],
			"Duplicate/invalid weighted ID"
		)
		seen[entry.id] = true
		assert(Rules.IsFinite(entry.weight) and entry.weight >= 0, "Invalid weight")
		if entry.eligible ~= false and entry.weight > 0 then
			total += entry.weight
			assert(Rules.IsFinite(total), "Invalid weight total")
			table.insert(positive, { entry = entry, cumulative = total })
		end
	end
	if total <= 0 then
		return table.freeze({ status = "Unavailable", code = "EMPTY_ELIGIBLE_POOL" })
	end
	local x = unit(random) * total
	for _, row in positive do
		if x < row.cumulative then
			return table.freeze({ status = "Ready", id = row.entry.id, entry = row.entry, totalWeight = total })
		end
	end
	local final = positive[#positive]
	return table.freeze({ status = "Ready", id = final.entry.id, entry = final.entry, totalWeight = total })
end
function Rules.MutationDistribution(totalChance, catalogue)
	local chance = if totalChance == nil then Config.MutationChance else totalChance
	assert(Rules.IsFinite(chance) and chance >= 0 and chance <= 1, "Invalid total mutation chance")
	local rows = catalogue or Catalog.Order
	local shares, seen = 0, {}
	local result = { { id = "None", weight = 1 - chance } }
	for _, row in rows do
		assert(type(row.id) == "string" and Catalog.ById[row.id] and not seen[row.id], "Unknown/duplicate mutation ID")
		seen[row.id] = true
		assert(Rules.IsFinite(row.share) and row.share >= 0, "Invalid mutation share")
		if row.id ~= "None" then
			shares += row.share
			table.insert(result, { id = row.id, weight = chance * row.share })
		end
	end
	assert(math.abs(shares - 1) < 1e-10, "Conditional shares must sum to one")
	return result
end
function Rules.RollMutation(random, totalChance)
	local rows = Rules.MutationDistribution(totalChance)
	if (totalChance or Config.MutationChance) == 0 then
		return "None"
	end
	return Rules.SelectWeighted(rows, random).id
end
local rarityRanks =
	{ Common = 0, Uncommon = 0, Rare = 1, Epic = 2, Legendary = 3, Mythic = 4, Celestial = 5, Astral = 5, Secret = 6 }
function Rules.SpectacleRank(rarity, mutation)
	local id = Rules.NormalizeMutation(mutation)
	return math.max(rarityRanks[rarity] or 0, if id then Catalog.ById[id].floor else 0)
end
function Rules.GlobalAnnouncement(rarity, mutation)
	local id = Rules.NormalizeMutation(mutation)
	return (rarityRanks[rarity] or 0) >= 2 or id == "Glitched" or id == "Radioactive" or id == "Astral"
end
return table.freeze(Rules)
