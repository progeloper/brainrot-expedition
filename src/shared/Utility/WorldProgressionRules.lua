--!strict
local Config = require(script.Parent.Parent.Config.WorldProgression)
local Catalog = require(script.Parent.Parent.Config.BrainrotCatalog)
local Money = require(script.Parent.CurrencyDenomination)
local Rules = {}
-- Version0's historical grant qualification is immutable. New gate prices only
-- govern new purchases; returning legacy profiles retain the original migration.
local LEGACY_GRANT_PRICES = {
	Beach = 25000000,
	Swamp = 200000000,
	Jungle = 750000000,
	Arctic = 2000000000,
	Volcano = 4000000000,
	GlitchZone = 10000000000,
}

function Rules.CreateDefault(): any
	return { Version = 1, PersonalUnlocks = { Forest = { source = "starter" } }, BankedSpecies = {}, LegacyGrantVersion = 1 }
end

function Rules.Count(data: any): any
	local counts = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
	local seen = {}
	local proof = data.WorldProgression and data.WorldProgression.BankedSpecies or {}
	for speciesId, record in proof do
		local canonical = Catalog.NormalizeId(speciesId)
		local rank = type(record) == "table" and Config.OrdinaryRarity[record.rarityAtFirstBank]
		-- Prefer the canonical historical record if a legacy alias also exists.
		local canonicalRecord = canonical and proof[canonical]
		if canonical and rank and not seen[canonical] and (speciesId == canonical or canonicalRecord == nil) then
			seen[canonical] = true
			for rarity, minimum in Config.OrdinaryRarity do
				if rank >= minimum then
					counts[rarity] += 1
				end
			end
		end
	end
	return counts
end

function Rules.Banking(data: any, definition: any, cachedCounts: any?): any
	local counts = cachedCounts or Rules.Count(data)
	local function branch(spec)
		return if spec
			then { rarity = spec[1], required = spec[2], count = counts[spec[1]], passed = counts[spec[1]] >= spec[2] }
			else nil
	end
	local a, b = branch(definition.branchA), branch(definition.branchB)
	return { branchA = a, branchB = b, passed = definition.index <= 1 or (a and a.passed) or (b and b.passed) or false }
end

function Rules.Evaluate(data: any, key: any, context: any, cachedCounts: any?): any
	local definition = type(key) == "string" and Config.ByKey[key]
	if not definition then
		return { code = "UnknownRegion", eligible = false }
	end
	local result = { key = key, price = definition.price, eligible = false }
	if not context.ready then
		result.code = "ProfileNotReady"
		return result
	end
	if not context.writable then
		result.code = "ProfileNotWritable"
		return result
	end
	if data.CurrencyVersion ~= 2 or context.currencyConfirmed ~= true then
		result.code = "CurrencyNotReady"
		return result
	end
	local balance = data.Economy.Balance
	if not Money.Validate(balance) then
		result.code = "CurrencyNotReady"
		return result
	end
	result.wallet = balance
	result.shortfall = math.max(0, definition.price - balance)
	local banking = Rules.Banking(data, definition, cachedCounts)
	result.branchA, result.branchB, result.bankingSatisfied = banking.branchA, banking.branchB, banking.passed
	local unlocks = data.WorldProgression.PersonalUnlocks
	result.alreadyPersonallyUnlocked = definition.index <= 1 or unlocks[key] ~= nil
	if context.operational ~= true then
		result.code = "RegionUnavailable"
		return result
	end
	if result.alreadyPersonallyUnlocked then
		result.code = if definition.index <= 1 then "FreeStarterRegion" else "AlreadyUnlocked"
		return result
	end
	if definition.predecessor and unlocks[definition.predecessor] == nil then
		result.code = "PreviousRegionRequired"
		return result
	end
	if not banking.passed then
		result.code = "BankedRequirementMissing"
		return result
	end
	if balance < definition.price then
		result.code = "InsufficientCash"
		return result
	end
	result.code, result.eligible = "Eligible", true
	return result
end

function Rules.AddBankedProof(data: any, rawId: any, source: string, timestamp: number?): boolean
	local definition = Catalog.Get(rawId)
	if not definition then
		return false
	end
	local proof = data.WorldProgression.BankedSpecies
	if proof[definition.id] ~= nil then
		return false
	end
	local legacyAlias = definition.id:gsub("_", "-")
	if proof[legacyAlias] ~= nil then
		-- Keep historical rarity/time rather than reclassifying this earned proof.
		proof[definition.id] = proof[legacyAlias]
		proof[legacyAlias] = nil
		return true
	end
	proof[definition.id] = { rarityAtFirstBank = definition.tier, source = source, firstBankedAt = timestamp }
	return true
end

-- Called on the normalized private record inside existing profile migration.
function Rules.Migrate(data: any): (boolean, string?, boolean?)
	local world = data.WorldProgression
	local changed = false
	if world == nil then
		world = Rules.CreateDefault()
		world.LegacyGrantVersion = 0
		data.WorldProgression = world
		changed = true
	end
	if
		type(world) ~= "table"
		or world.Version ~= 1
		or type(world.PersonalUnlocks) ~= "table"
		or type(world.BankedSpecies) ~= "table"
		or (world.LegacyGrantVersion ~= 0 and world.LegacyGrantVersion ~= 1)
	then
		return false, "INVALID_WORLD_PROGRESSION", nil
	end
	for key, grant in world.PersonalUnlocks do
		if
			not Config.ByKey[key]
			or type(grant) ~= "table"
			or (grant.source ~= "starter" and grant.source ~= "purchase" and grant.source ~= "legacy_progress")
		then
			return false, "INVALID_PERSONAL_UNLOCK", nil
		end
	end
	if world.PersonalUnlocks.Forest == nil then
		world.PersonalUnlocks.Forest = { source = "starter" }
		changed = true
	end
	-- Normalize the already-trusted species proof at the existing catalogue boundary.
	-- Canonical records win if both spellings were saved; unknown records remain
	-- diagnostic data and cannot acquire a rarity from a guessed species.
	local normalized = {}
	for id, record in world.BankedSpecies do
		local canonical = Catalog.NormalizeId(id)
		local key = canonical or id
		if normalized[key] == nil then
			normalized[key] = world.BankedSpecies[key] or record
		end
		if key ~= id then
			changed = true
		end
	end
	if changed then
		world.BankedSpecies = normalized
	end
	-- Collection.BrainrotInstances is durable BANKED ownership, not discovery or fresh cargo.
	for _, record in data.Collection.BrainrotInstances do
		if Rules.AddBankedProof(data, record.speciesId, "legacy_bank_record", nil) then
			changed = true
		end
	end
	if world.LegacyGrantVersion == 0 then
		local balance = data.Economy.Balance -- one wallet snapshot; never consume for legacy grants
		for _, definition in Config.Ordered do
			if definition.index <= 1 then
				continue
			end
			if world.PersonalUnlocks[definition.key] then
				continue
			end
			if
				not world.PersonalUnlocks[definition.predecessor]
				or balance < (LEGACY_GRANT_PRICES[definition.key] or definition.price)
				or not Rules.Banking(data, definition).passed
			then
				break
			end
			world.PersonalUnlocks[definition.key] = { source = "legacy_progress" }
		end
		world.LegacyGrantVersion = 1
		changed = true
	end
	return true, nil, changed
end

function Rules.Highest(data: any): number
	local highest = 1
	for key, grant in data.WorldProgression.PersonalUnlocks do
		local definition = Config.ByKey[key]
		if definition and type(grant) == "table" then
			highest = math.max(highest, definition.index)
		end
	end
	return highest
end

return table.freeze(Rules)
