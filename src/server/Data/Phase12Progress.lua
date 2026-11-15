--!strict
-- Pure profile extension. It neither owns inventory nor performs currency grants.
local Rules = require(game.ReplicatedStorage.Shared.Utility.Phase12Rules)
local RetentionRules = require(game.ReplicatedStorage.Shared.Utility.RetentionRules)
local Progress = {}
local MUTATIONS = {
	None = true,
	Normal = true,
	Shiny = true,
	Golden = true,
	Glitched = true,
	Radioactive = true,
	Astral = true,
	Celestial = true,
}
local METRICS = { "haulCount", "cashPerSecond", "sellValue" }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

function Progress.MutationId(record: any): string
	local metadata = if type(record) == "table" then record.Metadata or record.metadata else nil
	local legacy = if type(metadata) == "table" then metadata.Mutation else nil
	return Rules.NormalizeMutation(
		if type(record) == "table"
			then record.MutationId or record.mutationId or (if type(metadata) == "table"
				then metadata.MutationId
				else nil) or (if type(legacy) == "table" then legacy.Id or legacy.MutationId else nil)
			else nil
	)
end

function Progress.DisplayMutation(id: any): string
	local normalized = Rules.NormalizeMutation(id)
	return if normalized == "None" then "Normal" else normalized
end

function Progress.Validate(data: any): (boolean, string?)
	local collection = data.Collection
	for _, key in { "Species", "Mutations", "SpeciesMutations" } do
		if collection[key] ~= nil and type(collection[key]) ~= "table" then
			return false, "INVALID_DISCOVERY_" .. string.upper(key)
		end
	end
	for _, mutationMap in collection.SpeciesMutations or {} do
		if type(mutationMap) ~= "table" then
			return false, "INVALID_SPECIES_MUTATIONS"
		end
	end
	for _, record in collection.BrainrotInstances do
		local metadata = record.metadata
		local metadataId = if type(metadata) == "table" then metadata.MutationId else nil
		local legacy = if type(metadata) == "table" then metadata.Mutation else nil
		local normalized: string? = nil
		for _, id in
			{
				record.mutationId,
				record.MutationId,
				metadataId,
				if type(legacy) == "table" then legacy.Id else nil,
				if type(legacy) == "table" then legacy.MutationId else nil,
			}
		do
			if type(id) ~= "string" or MUTATIONS[id] ~= true then
				return false, "INVALID_OWNED_MUTATION"
			end
			local current = Rules.NormalizeMutation(id)
			if normalized ~= nil and current ~= normalized then
				return false, "OWNED_MUTATION_CONFLICT"
			end
			normalized = current
		end
		if record.firstBankCompleted ~= nil and type(record.firstBankCompleted) ~= "boolean" then
			return false, "INVALID_FIRST_BANK_MARKER"
		end
		if record.firstBankedAt ~= nil and not finite(record.firstBankedAt) then
			return false, "INVALID_FIRST_BANK_TIMESTAMP"
		end
	end
	local progression = data.Progression
	if type(progression) == "table" and progression.ExpeditionBest ~= nil then
		local best = progression.ExpeditionBest
		if type(best) ~= "table" then
			return false, "INVALID_EXPEDITION_BEST"
		end
		for _, key in METRICS do
			if not finite(best[key]) or (key == "haulCount" and best[key] % 1 ~= 0) then
				return false, "INVALID_EXPEDITION_BEST"
			end
		end
	end
	if
		type(progression) == "table"
		and progression.TrackedUpgradeId ~= nil
		and type(progression.TrackedUpgradeId) ~= "string"
	then
		return false, "INVALID_TRACKED_UPGRADE"
	end
	return true, nil
end

function Progress.Migrate(data: any): boolean
	local changed = false
	local collection = data.Collection
	for _, key in { "Species", "Mutations", "SpeciesMutations" } do
		if collection[key] == nil then
			collection[key] = {}
			changed = true
		end
	end
	if collection.Mutations.Celestial ~= nil then
		if collection.Mutations.Astral == nil then
			collection.Mutations.Astral = collection.Mutations.Celestial
		end
		collection.Mutations.Celestial = nil
		changed = true
	end
	for _, mutationMap in collection.SpeciesMutations do
		if type(mutationMap) == "table" and mutationMap.Celestial ~= nil then
			if mutationMap.Astral == nil then
				mutationMap.Astral = mutationMap.Celestial
			end
			mutationMap.Celestial = nil
			changed = true
		end
	end
	for _, record in collection.BrainrotInstances do
		local normalized = Progress.MutationId(record)
		if record.mutationId ~= normalized then
			record.mutationId = normalized
			changed = true
		end
		if record.metadata == nil then
			record.metadata = {}
			changed = true
		end
		if record.metadata.MutationId ~= normalized then
			record.metadata.MutationId = normalized
			changed = true
		end
		if record.MutationId ~= nil and record.MutationId ~= normalized then
			record.MutationId = normalized
			changed = true
		end
		local legacy = record.metadata.Mutation
		if type(legacy) == "table" then
			for _, key in { "Id", "MutationId" } do
				if legacy[key] ~= nil and legacy[key] ~= normalized then
					legacy[key] = normalized
					changed = true
				end
			end
		end
		-- Legacy owned entries are already banked. Backfill historical discovery,
		-- but never fabricate an expedition or a new-bank presentation receipt.
		if record.firstBankCompleted ~= true then
			record.firstBankCompleted = true
			changed = true
		end
		if record.metadata.FirstBankCompleted ~= true then
			record.metadata.FirstBankCompleted = true
			changed = true
		end
		local species = record.speciesId
		if collection.Species[species] == nil then
			collection.Species[species] = true
			changed = true
		end
		local displayId = Progress.DisplayMutation(normalized)
		if collection.Mutations[displayId] == nil then
			collection.Mutations[displayId] = true
			changed = true
		end
		if collection.SpeciesMutations[species] == nil then
			collection.SpeciesMutations[species] = {}
			changed = true
		end
		if collection.SpeciesMutations[species][displayId] == nil then
			collection.SpeciesMutations[species][displayId] = true
			changed = true
		end
	end
	if data.Progression == nil then
		data.Progression = { Upgrades = {} }
		changed = true
	end
	if data.Progression.ExpeditionBest == nil then
		data.Progression.ExpeditionBest = { haulCount = 0, cashPerSecond = 0, sellValue = 0 }
		changed = true
	end
	return changed
end

-- Called inside the existing bank profile mutation, before it can be saved.
function Progress.RecordFirstBank(data: any, item: any, expedition: any?, at: number): any?
	local metadata = item.Metadata or {}
	local existing = data.Collection.BrainrotInstances[item.ItemId]
	if existing ~= nil or metadata.FirstBankCompleted == true or type(metadata.DurableOwnerUserId) == "number" then
		return nil
	end
	local mutation = Progress.MutationId(item)
	local values = Rules.EffectiveValues(item.BrainrotId, mutation)
	-- Existing trusted native asset fixtures may have no economic catalogue row.
	-- They retain their storage behavior and receive no invented progress/value.
	if values == nil then
		return nil
	end
	local collection = data.Collection
	collection.Species = collection.Species or {}
	collection.Mutations = collection.Mutations or {}
	collection.SpeciesMutations = collection.SpeciesMutations or {}
	local displayId = Progress.DisplayMutation(mutation)
	local firstSpecies = collection.Species[item.BrainrotId] == nil
	local speciesMutations = collection.SpeciesMutations[item.BrainrotId] or {}
	local firstSpeciesMutation = speciesMutations[displayId] == nil
	collection.Species[item.BrainrotId] = collection.Species[item.BrainrotId] or at
	collection.Mutations[displayId] = collection.Mutations[displayId] or at
	speciesMutations[displayId] = speciesMutations[displayId] or at
	collection.SpeciesMutations[item.BrainrotId] = speciesMutations
	local receipt = {
		individualId = item.ItemId,
		speciesId = item.BrainrotId,
		mutationId = mutation,
		cashPerSecond = values.cashPerSecond,
		sellValue = values.sellValue,
		firstSpecies = firstSpecies,
		firstSpeciesMutation = firstSpeciesMutation,
		firstBankedAt = at,
		acquisitionKind = if metadata.AcquisitionKind == "Hunt" or metadata.AcquisitionKind == "Theft"
			then metadata.AcquisitionKind
			else nil,
		recordImprovements = {},
	}
	if type(expedition) == "table" and type(expedition.id) == "string" and expedition.returned == true then
		local haul = {
			id = expedition.id,
			haulCount = (expedition.haulCount or 0) + 1,
			cashPerSecond = (expedition.cashPerSecond or 0) + values.cashPerSecond,
			sellValue = (expedition.sellValue or 0) + values.sellValue,
		}
		data.Progression = data.Progression or { Upgrades = {} }
		local best = data.Progression.ExpeditionBest or { haulCount = 0, cashPerSecond = 0, sellValue = 0 }
		for _, key in METRICS do
			if haul[key] > best[key] then
				best[key] = haul[key]
				receipt.recordImprovements[key] = true
			end
		end
		data.Progression.ExpeditionBest = best
		receipt.expedition = haul
	end
	-- Atomic Phase14 extension: ownership, daily progress, Cash and paid marker
	-- share this existing first-bank mutation and its covering save.
	receipt.retention = RetentionRules.RecordFirstBank(data, receipt)
	-- P15: free Gem sources (discovery, index milestone, first mutation, first-of-day tier).
	receipt.gems = require(game:GetService("ReplicatedStorage").Shared.Utility.GemRules).OnFirstBank(data, receipt)
	return receipt
end

return table.freeze(Progress)
