--!strict
local OrdinarySpawnCeilings = {}

-- Cap the actual tier × species probabilities after temporary exclusions.
-- Released probability is shared proportionally by species without a ceiling;
-- their relative odds stay unchanged. A pool consisting solely of capped
-- species cannot represent a full ordinary draw and is blocked instead.
function OrdinarySpawnCeilings.Apply(tiers: any, totalTierWeight: number, ceilings: any): any
	local rows = {}
	local redistributed, recipientWeight = 0, 0
	local adjustments = {}
	for _, tier in tiers do
		for _, entry in tier.species do
			local probability = tier.configuredWeight / totalTierWeight * entry.weight / tier.totalSpeciesWeight
			local ceiling = ceilings[entry.speciesId]
			local applied = if ceiling ~= nil then math.min(probability, ceiling) else probability
			redistributed += probability - applied
			if ceiling == nil then recipientWeight += probability end
			table.insert(rows, { Entry = entry, Tier = tier, Probability = applied, AuthoredProbability = probability, Ceiling = ceiling })
			if applied < probability then
				table.insert(adjustments, table.freeze({
					speciesId = entry.speciesId,
					tier = tier.tier,
					beforeProbability = probability,
					afterProbability = applied,
					ceiling = ceiling,
				}))
			end
		end
	end
	if redistributed <= 0 then
		return { Status = "Ready", Tiers = tiers, TotalTierWeight = totalTierWeight, Adjustments = table.freeze(adjustments) }
	end
	if recipientWeight <= 0 then
		return { Status = "ORDINARY_SPAWN_CEILING_NO_RECIPIENT", Tiers = {}, TotalTierWeight = 0, Adjustments = table.freeze(adjustments) }
	end
	local byTier, result = {}, {}
	for _, row in rows do
		local probability = row.Probability
		if row.Ceiling == nil then probability += redistributed * row.AuthoredProbability / recipientWeight end
		if probability <= 0 then continue end
		local tier = byTier[row.Tier.tier]
		if not tier then
			tier = { tier = row.Tier.tier, configuredWeight = 0, weight = 0, cumulativeEnd = 0, species = {}, totalSpeciesWeight = 0 }
			byTier[row.Tier.tier] = tier
			table.insert(result, tier)
		end
		tier.totalSpeciesWeight += probability
		table.insert(tier.species, {
			speciesId = row.Entry.speciesId,
			tier = row.Entry.tier,
			weightSource = row.Entry.weightSource,
			weight = probability,
			cumulativeEnd = tier.totalSpeciesWeight,
		})
	end
	local total = 0
	for _, tier in result do
		tier.configuredWeight = tier.totalSpeciesWeight
		tier.weight = tier.totalSpeciesWeight
		total += tier.weight
		tier.cumulativeEnd = total
	end
	return { Status = "Ready", Tiers = result, TotalTierWeight = total, Adjustments = table.freeze(adjustments) }
end

return table.freeze(OrdinarySpawnCeilings)
