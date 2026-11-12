--!strict
-- Additive, pure retention state. All calls run inside the existing profile writer.
-- No publication, saves, analytics, entitlement APIs or client clock in a transform.
local Config = require(script.Parent.Parent.Config.RetentionConfig)
local World = require(script.Parent.Parent.Config.WorldProgression)
local Catalog = require(script.Parent.Parent.Config.BrainrotCatalog)
local Money = require(script.Parent.CurrencyDenomination)
local ProgressionConfig = require(script.Parent.Parent.Config.Phase13)
local Weapons = require(script.Parent.Parent.Config.Weapons)
local GemRules = require(script.Parent.GemRules)
local Rules = {}
local questOrder = { "bring_them_home", "field_research", "camp_payday" }
local function integer(value, minimum)
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= (minimum or 0)
		and value <= Money.MAX_AMOUNT
		and value % 1 == 0
end
local function shortString(value, maximum)
	return type(value) == "string" and #value > 0 and #value <= (maximum or 128)
end
function Rules.ValidateConfig(config)
	config = if config == nil then Config else config
	if type(config) ~= "table" then
		return false, "INVALID_RETENTION_CONFIG"
	end
	if
		config.SchemaVersion ~= 1
		or config.ResetPeriodSeconds ~= 86400
		or not shortString(config.RewardConfigVersion)
	then
		return false, "INVALID_RETENTION_CONFIG"
	end
	-- P15: units re-anchored to the final revenue curve (about a quarter of the next gate).
	local expected = {
		Forest = 250000000,
		Beach = 2500000000,
		Swamp = 10000000000,
		Jungle = 50000000000,
		Arctic = 100000000000,
		Volcano = 250000000000,
		Glitch = 500000000000,
	}
	local order = { "Forest", "Beach", "Swamp", "Jungle", "Arctic", "Volcano", "Glitch" }
	if type(config.RegionBandOrder) ~= "table" or #config.RegionBandOrder ~= 7 then
		return false, "INVALID_RETENTION_BANDS"
	end
	for index, band in order do
		if config.RegionBandOrder[index] ~= band then
			return false, "INVALID_RETENTION_BANDS"
		end
		if type(config.UnitCashByRegionBand) ~= "table" or config.UnitCashByRegionBand[band] ~= expected[band] then
			return false, "INVALID_RETENTION_UNIT:" .. band
		end
	end
	if type(config.RegionIdToBand) ~= "table" then
		return false, "INVALID_RETENTION_CONFIG"
	end
	for _, definition in World.Ordered do
		local band = config.RegionIdToBand[definition.regionId]
		if not band or not expected[band] then
			return false, "MISSING_RETENTION_REGION:" .. definition.regionId
		end
	end
	if type(config.QuestDefinitions) ~= "table" then
		return false, "INVALID_RETENTION_QUEST_COUNT"
	end
	local count = 0
	for id, row in config.QuestDefinitions do
		if type(row) ~= "table" then
			return false, "INVALID_RETENTION_QUEST"
		end
		count += 1
		local target = ({ bring_them_home = 3, field_research = 2, camp_payday = 1 })[id]
		if not target or row.Target ~= target or row.RewardUnits ~= target then
			return false, "INVALID_RETENTION_QUEST"
		end
	end
	if count ~= 3 then
		return false, "INVALID_RETENTION_QUEST_COUNT"
	end
	if type(config.SupplyRewardUnitsByCycleClaim) ~= "table" then
		return false, "INVALID_SUPPLY_CYCLE"
	end
	for index = 1, 7 do
		if config.SupplyRewardUnitsByCycleClaim[index] ~= (if index == 7 then 2 else 1) then
			return false, "INVALID_SUPPLY_CYCLE"
		end
	end
	return true, nil
end
function Rules.Default()
	return {
		SchemaVersion = 1,
		Revision = 0,
		Eligible = false,
		PendingRewards = {},
		Supplies = { lifetimeClaims = 0 },
		Milestones = {},
	}
end
function Rules.HasBankHistory(data)
	local collection = data.Collection or {}
	return next(collection.Species or {}) ~= nil
		or next(collection.BrainrotInstances or {}) ~= nil
		or next((data.WorldProgression or {}).BankedSpecies or {}) ~= nil
end
function Rules.IsDiscovered(data, id)
	local expected = Catalog.Get(id)
	if not expected then
		return false
	end
	for rawId, proof in (data.Collection or {}).Species or {} do
		local definition = Catalog.Get(rawId)
		if proof and definition and definition.id == expected.id then
			return true
		end
	end
	return false
end
function Rules.DiscoveryVariants(data, id)
	local found, result = {}, {}
	for rawId, variants in (data.Collection or {}).SpeciesMutations or {} do
		local definition = Catalog.Get(rawId)
		if definition and definition.id == id and type(variants) == "table" then
			for mutation, proof in variants do
				if proof and not found[mutation] then
					found[mutation] = true
					table.insert(result, mutation)
				end
			end
		end
	end
	table.sort(result)
	return result
end
function Rules.DiscoveryCount(data)
	local count, seen = 0, {}
	for id, proof in (data.Collection or {}).Species or {} do
		local definition = Catalog.Get(id)
		if proof and definition and definition.launchStatus == "Live" and not seen[definition.id] then
			seen[definition.id], count = true, count + 1
		end
	end
	return count
end
function Rules.HasAnomaly(data)
	for speciesId, variants in (data.Collection or {}).SpeciesMutations or {} do
		local definition = Catalog.Get(speciesId)
		if definition and definition.launchStatus == "Live" and type(variants) == "table" then
			for mutation, proof in variants do
				if
					proof
					and ({
						Shiny = true,
						Golden = true,
						Glitched = true,
						Radioactive = true,
						Astral = true,
						Celestial = true,
					})[mutation]
				then
					return true
				end
			end
		end
	end
	return false
end
function Rules.ReconcileMilestones(data)
	local state = data.Retention
	local awarded, count, anomaly = {}, Rules.DiscoveryCount(data), Rules.HasAnomaly(data)
	for _, row in Config.Milestones do
		if
			state.Milestones[row.Id] == nil and ((row.Species and count >= row.Species) or (row.Anomaly and anomaly))
		then
			state.Milestones[row.Id] = { earned = true, source = "DurableBankedDiscovery" }
			table.insert(awarded, row.Id)
		end
	end
	return awarded
end
local function newQuest(id)
	local quest = { count = 0, paid = false, paidCash = 0 }
	if id == "field_research" then
		quest.species = {}
	end
	return quest
end
function Rules.Migrate(data)
	local ok, reason = Rules.Validate(data)
	if not ok then
		return false, reason, false
	end
	local changed = false
	if data.Retention == nil then
		data.Retention, changed = Rules.Default(), true
	end
	local state = data.Retention
	if not state.Supplies then
		state.Supplies, changed = { lifetimeClaims = 0 }, true
	end
	if not state.Milestones then
		state.Milestones, changed = {}, true
	end
	if not state.Eligible and Rules.HasBankHistory(data) then
		state.Eligible, changed = true, true
	end
	if state.Day then
		for _, id in questOrder do
			if not state.Day[id] then
				state.Day[id], changed = newQuest(id), true
			end
		end
	end
	if #Rules.ReconcileMilestones(data) > 0 then
		changed = true
	end
	if changed then
		state.Revision += 1
	end
	return true, nil, changed
end
function Rules.ResolveBand(data)
	local ok, reason = Rules.ValidateConfig()
	if not ok then
		return nil, reason
	end
	local permanent = data.WorldProgression and data.WorldProgression.PersonalUnlocks
	if type(permanent) ~= "table" or permanent.Forest == nil then
		return nil, "INVALID_RETENTION_PERMANENT_ACCESS"
	end
	for key in permanent do
		if World.ByKey[key] == nil then
			return nil, "UNKNOWN_RETENTION_REGION:" .. tostring(key)
		end
	end
	local band = "Forest"
	for _, definition in World.Ordered do
		if permanent[definition.key] ~= nil then
			band = Config.RegionIdToBand[definition.regionId]
		end
	end
	return band, nil
end
function Rules.RewardAmount(day, rewardUnits)
	if
		type(day) ~= "table"
		or not integer(day.unitCash, 1)
		or not integer(rewardUnits, 1)
		or day.unitCash > Money.MAX_AMOUNT / rewardUnits
	then
		return nil, "INVALID_RETENTION_REWARD"
	end
	return day.unitCash * rewardUnits, nil
end
local function validGoalId(id)
	if id == nil then
		return true
	end
	if not shortString(id) or id:find("%c") then
		return false
	end
	local legacySpeed, legacyCargo = id:match("^CART_SPEED_(%d+)$"), id:match("^CARGO_(%d+)$")
	if legacySpeed then
		return ProgressionConfig.SpeedPrices[tonumber(legacySpeed)] ~= nil
	end
	if legacyCargo then
		return ProgressionConfig.CargoPrices[tonumber(legacyCargo)] ~= nil
	end
	local parts = string.split(id, ":")
	local kind, key, route = parts[1], parts[2], parts[3]
	if #parts == 2 then
		if kind == "Region" then
			return World.ByKey[key] ~= nil and World.ByKey[key].index > 1
		end
		if kind == "Weapon" then
			return Weapons.Get(key) ~= nil
		end
		if kind == "Roller" then
			-- Camp Rework Training roller goals (Cash rollers only)
			local roller = require(script.Parent.Parent.Config.Training).RollersById[key]
			return roller ~= nil and roller.price > 0
		end
		local prices = ({
			Speed = ProgressionConfig.SpeedPrices,
			Cargo = ProgressionConfig.CargoPrices,
			Equipped = ProgressionConfig.EquippedPrices,
		})[kind]
		if prices then
			local level = tonumber(key)
			return level ~= nil and level % 1 == 0 and prices[level] ~= nil
		end
		if kind == "Cart" then
			for _, row in ProgressionConfig.CartRows do
				if row.id == key then
					return true
				end
			end
		end
	end
	if
		kind == "Rebirth"
		and (#parts == 2 or #parts == 3)
		and (route == nil or route == "Cash" or route == "Collection")
	then
		for _, rows in { ProgressionConfig.ExpansionRows, ProgressionConfig.DesignRows } do
			for _, row in rows do
				if row.id == key and not row.starter then
					return true
				end
			end
		end
	end
	return false
end
function Rules.Validate(data)
	if not validGoalId((data.Progression or {}).TrackedUpgradeId) then
		return false, "INVALID_RETENTION_GOAL"
	end
	local state = data.Retention
	if state == nil then
		return true, nil
	end
	if
		type(state) ~= "table"
		or state.SchemaVersion ~= 1
		or not integer(state.Revision)
		or type(state.Eligible) ~= "boolean"
		or type(state.PendingRewards) ~= "table"
	then
		return false, "INVALID_RETENTION_STATE"
	end
	for id, reward in state.PendingRewards do
		if
			not shortString(id)
			or type(reward) ~= "table"
			or reward.grantId ~= id
			or not integer(reward.dayKey)
			or not integer(reward.amountCash, 1)
			or reward.status ~= "Pending"
			or not integer(reward.unitCash, 1)
			or not Config.UnitCashByRegionBand[reward.regionBand]
			or not shortString(reward.rewardConfigVersion)
			or not shortString(reward.sourceOperation, 240)
			or (reward.kind ~= nil and reward.kind ~= "Quest" and reward.kind ~= "Supply")
			or (reward.kind ~= "Supply" and not Config.QuestDefinitions[reward.questId])
		then
			return false, "INVALID_RETENTION_PENDING"
		end
		local expectedUnits = if reward.kind == "Supply" and integer(reward.lifetimeClaim, 1)
			then Config.SupplyRewardUnitsByCycleClaim[((reward.lifetimeClaim - 1) % 7) + 1]
			elseif Config.QuestDefinitions[reward.questId] then Config.QuestDefinitions[reward.questId].RewardUnits
			else nil
		if not expectedUnits or reward.amountCash ~= reward.unitCash * expectedUnits then
			return false, "INVALID_RETENTION_PENDING_AMOUNT"
		end
		if
			reward.kind == "Supply"
			and (
				not integer(reward.lifetimeClaim, 1)
				or Config.SupplyCosmeticByLifetimeClaim[reward.lifetimeClaim] ~= reward.cosmeticId
				or id ~= "retention:supply:" .. tostring(reward.lifetimeClaim)
			)
		then
			return false, "INVALID_RETENTION_PENDING_SUPPLY"
		end
		if reward.kind ~= "Supply" and id ~= "retention:" .. tostring(reward.dayKey) .. ":" .. reward.questId then
			return false, "INVALID_RETENTION_PENDING_GRANT"
		end
	end
	local day = state.Day
	if day then
		if
			type(day) ~= "table"
			or not integer(day.dayKey)
			or not Config.UnitCashByRegionBand[day.regionBand]
			or not integer(day.unitCash, 1)
			or not shortString(day.rewardConfigVersion)
			or type(day.rewardUnits) ~= "table"
			or type(day.bring_them_home) ~= "table"
		then
			return false, "INVALID_RETENTION_DAY"
		end
		for _, id in questOrder do
			if day.rewardUnits[id] ~= Config.QuestDefinitions[id].RewardUnits then
				return false, "INVALID_FROZEN_RETENTION_UNITS"
			end
			local quest = day[id]
			-- V1 days did not contain Research/Payday; migration adds empty state without inventing history.
			if quest then
				local target = Config.QuestDefinitions[id].Target
				if
					type(quest) ~= "table"
					or not integer(quest.count)
					or quest.count > target
					or type(quest.paid) ~= "boolean"
					or not integer(quest.paidCash)
					or (quest.paid and (quest.count ~= target or quest.paidCash ~= day.unitCash * day.rewardUnits[id] or quest.grantId ~= "retention:" .. tostring(
						day.dayKey
					) .. ":" .. id))
					or (not quest.paid and quest.paidCash ~= 0)
					or (quest.grantId ~= nil and quest.grantId ~= "retention:" .. tostring(day.dayKey) .. ":" .. id)
					or (quest.sourceOperation ~= nil and not shortString(quest.sourceOperation, 240))
				then
					return false, "INVALID_RETENTION_QUEST_STATE"
				end
				if id == "field_research" then
					if type(quest.species) ~= "table" or #quest.species > 2 or #quest.species ~= quest.count then
						return false, "INVALID_RESEARCH_SPECIES"
					end
					local seen, n = {}, 0
					for index, species in quest.species do
						n += 1
						if
							not integer(index, 1)
							or index > 2
							or n > 2
							or not shortString(species)
							or not Catalog.Get(species)
							or seen[species]
						then
							return false, "INVALID_RESEARCH_SPECIES"
						end
						seen[species] = true
					end
					if n ~= quest.count then
						return false, "INVALID_RESEARCH_SPECIES"
					end
				end
			end
		end
	end
	if state.LastSeenAt ~= nil and not integer(state.LastSeenAt) then
		return false, "INVALID_RETENTION_VISIT"
	end
	local supplies = state.Supplies
	if
		supplies
		and (
			type(supplies) ~= "table"
			or not integer(supplies.lifetimeClaims)
			or (supplies.lastClaimDay ~= nil and not integer(supplies.lastClaimDay))
			or (supplies.lifetimeClaims > 0 and supplies.lastClaimDay == nil)
			or (supplies.lastPaid ~= nil and type(supplies.lastPaid) ~= "boolean")
			or (supplies.lifetimeClaims == 0 and supplies.lastClaimDay ~= nil)
			or (
				supplies.lifetimeClaims > 0
				and (
					type(supplies.lastPaid) ~= "boolean"
					or not integer(supplies.lastAmountCash)
					or supplies.lastGrantId ~= "retention:supply:" .. tostring(supplies.lifetimeClaims)
					or (supplies.lastPaid and supplies.lastAmountCash <= 0)
					or (not supplies.lastPaid and supplies.lastAmountCash ~= 0)
				)
			)
		)
	then
		return false, "INVALID_SUPPLY_STATE"
	end
	if state.Milestones then
		if type(state.Milestones) ~= "table" then
			return false, "INVALID_MILESTONE_STATE"
		end
		for id, proof in state.Milestones do
			if
				not Config.MilestoneById[id]
				or type(proof) ~= "table"
				or proof.earned ~= true
				or not shortString(proof.source)
			then
				return false, "INVALID_MILESTONE_STATE"
			end
		end
	end
	for field, slot in
		{ SelectedTitle = "Title", SelectedNameplate = "Nameplate", SelectedPlaque = "Plaque", SelectedBadge = "Badge" }
	do
		local value = state[field]
		if value == "RiftPatron" and (((data.Commerce or {}).Entitlements or {}).VIP ~= true or slot ~= "Title") then
			return false, "INVALID_MILESTONE_SELECTION"
		end
		if value ~= nil and value ~= "None" and not (slot == "Title" and value == "RiftPatron") then
			local definition = Config.MilestoneById[value]
			if not definition or definition.Slot ~= slot or not state.Milestones or not state.Milestones[value] then
				return false, "INVALID_MILESTONE_SELECTION"
			end
		end
	end
	if state.FeaturedSpeciesId ~= nil then
		local definition = Catalog.Get(state.FeaturedSpeciesId)
		if
			not definition
			or definition.id ~= state.FeaturedSpeciesId
			or definition.launchStatus ~= "Live"
			or not Rules.IsDiscovered(data, definition.id)
		then
			return false, "INVALID_FEATURED_DISCOVERY"
		end
	end
	return true, nil
end
local function dayForAction(data, at)
	if type(at) ~= "number" or not integer(math.floor(at)) then
		return nil, "INVALID_RETENTION_TIMESTAMP"
	end
	local state, key = data.Retention, math.floor(at / Config.ResetPeriodSeconds)
	if state.Day and state.Day.dayKey == key then
		return state.Day, nil, false
	end
	if state.Day and state.Day.dayKey > key then
		return nil, "RETENTION_TIME_REVERSED"
	end
	local band, reason = Rules.ResolveBand(data)
	if not band then
		return nil, reason
	end
	local units = {}
	for id, row in Config.QuestDefinitions do
		units[id] = row.RewardUnits
	end
	-- Unpaid prior days remain in PendingRewards with their original frozen prices.
	-- Only the compact current counters roll over; no per-individual retention history.
	state.Day = {
		dayKey = key,
		regionBand = band,
		unitCash = Config.UnitCashByRegionBand[band],
		rewardConfigVersion = Config.RewardConfigVersion,
		rewardUnits = units,
	}
	for _, id in questOrder do
		state.Day[id] = newQuest(id)
	end
	return state.Day, nil, true
end
local function applyCosmetic(data, id)
	if id then
		assert(data.Commerce and type(data.Commerce.Entitlements) == "table", "COMMERCE_NOT_READY")
		data.Commerce.Entitlements[id] = true
	end
end
local function settle(data, day, reward)
	local state = data.Retention
	if Money.Validate(data.Economy.Balance + reward.amountCash) then
		data.Economy.Balance += reward.amountCash
		applyCosmetic(data, reward.cosmeticId)
		return true
	end
	reward.dayKey, reward.unitCash, reward.regionBand = day.dayKey, day.unitCash, day.regionBand
	reward.rewardConfigVersion, reward.status = day.rewardConfigVersion, "Pending"
	state.PendingRewards[reward.grantId] = reward
	return false
end
local function advance(data, day, id, count, source)
	local quest, target = day[id], Config.QuestDefinitions[id].Target
	local before = quest.count
	quest.count = math.min(target, count)
	if quest.count == before then
		return nil
	end
	quest.sourceOperation = source
	local event = {
		questId = id,
		before = before,
		after = quest.count,
		dayKey = day.dayKey,
		band = day.regionBand,
		unitCash = day.unitCash,
		rewardConfigVersion = day.rewardConfigVersion,
		sourceOperation = source,
		amountCash = 0,
		code = "PROGRESS_COMMITTED",
	}
	if quest.count == target and not quest.paid then
		-- P15: each completed daily quest also pays Gems (exactly once: count reaches target once a day).
		event.gems = GemRules.OnQuestComplete(data)
		local amount, reason = Rules.RewardAmount(day, day.rewardUnits[id])
		assert(amount, reason)
		local grantId = "retention:" .. tostring(day.dayKey) .. ":" .. id
		local paid = settle(
			data,
			day,
			{ kind = "Quest", questId = id, grantId = grantId, amountCash = amount, sourceOperation = source }
		)
		quest.paid, quest.paidCash, quest.grantId = paid, if paid then amount else 0, grantId
		event.amountCash, event.grantId = if paid then amount else 0, grantId
		if not paid then
			event.code = "REWARD_PENDING_OVERFLOW"
		end
	end
	return event
end
function Rules.RecordFirstBank(data, receipt)
	if not Config.Enabled then
		return nil
	end
	if
		type(receipt) ~= "table"
		or not shortString(receipt.individualId)
		or not shortString(receipt.speciesId)
		or type(receipt.firstBankedAt) ~= "number"
	then
		return { code = "INVALID_FIRST_BANK" }
	end
	if data.Collection.BrainrotInstances[receipt.individualId] ~= nil then
		return { code = "ALREADY_BANKED" }
	end
	local ok, reason = Rules.Migrate(data)
	if not ok then
		return { code = reason }
	end
	local day, initialized
	day, reason, initialized = dayForAction(data, receipt.firstBankedAt)
	if not day then
		return { code = reason }
	end
	local state, source = data.Retention, "Bank:" .. receipt.individualId
	local definition = Catalog.Get(receipt.speciesId)
	local baseSpeciesId = if definition then definition.id else receipt.speciesId
	state.Eligible = true
	local transitions = {}
	local home = advance(data, day, "bring_them_home", day.bring_them_home.count + 1, source)
	if home then
		table.insert(transitions, home)
	end
	local research = day.field_research
	if #research.species < 2 and not table.find(research.species, baseSpeciesId) then
		table.insert(research.species, baseSpeciesId)
		local event = advance(data, day, "field_research", #research.species, source)
		if event then
			table.insert(transitions, event)
		end
	end
	local milestones = Rules.ReconcileMilestones(data)
	if #transitions > 0 or #milestones > 0 or initialized or receipt.firstSpecies or receipt.firstSpeciesMutation then
		state.Revision += 1
	end
	local result = (home and table.clone(home))
		or { code = "DAILY_COMPLETE", dayKey = day.dayKey, sourceOperation = source, amountCash = 0 }
	result.transitions, result.initialized, result.milestones = transitions, initialized, milestones
	result.discovery = if receipt.firstSpecies then receipt.speciesId else nil
	return result
end
function Rules.RecordPlatformSettlement(data, proof)
	if not Config.Enabled then
		return nil
	end
	if
		type(proof) ~= "table"
		or proof.source ~= "OwnPlatformIncome"
		or not shortString(proof.operationId, 240)
		or not Money.Validate(proof.earnings)
		or proof.earnings <= 0
		or type(proof.ownerUserId) ~= "number"
		or not integer(math.abs(proof.ownerUserId), 1)
		or type(proof.at) ~= "number"
	then
		return { code = "INELIGIBLE_SETTLEMENT" }
	end
	local ok, reason = Rules.Migrate(data)
	if not ok then
		return { code = reason }
	end
	if not data.Retention.Eligible then
		return { code = "NOT_ELIGIBLE" }
	end
	local day, initialized
	day, reason, initialized = dayForAction(data, proof.at)
	if not day then
		return { code = reason }
	end
	local event = advance(data, day, "camp_payday", 1, proof.operationId)
	if event or initialized then
		data.Retention.Revision += 1
	end
	return {
		code = if event then event.code else "DAILY_COMPLETE",
		initialized = initialized,
		transitions = if event then { event } else {},
		sourceOperation = proof.operationId,
		amountCash = if event then event.amountCash else 0,
	}
end
function Rules.ClaimSupply(data, at)
	local ok, reason = Rules.Migrate(data)
	if not ok then
		return false, { code = reason }
	end
	if not Config.Enabled or not data.Retention.Eligible then
		return false, { code = "NOT_ELIGIBLE" }
	end
	if type(at) ~= "number" or not integer(math.floor(at)) then
		return false, { code = "INVALID_RETENTION_TIMESTAMP" }
	end
	local state, key = data.Retention, math.floor(at / Config.ResetPeriodSeconds)
	if state.Supplies.lastClaimDay and state.Supplies.lastClaimDay >= key then
		return false, { code = "SUPPLY_ALREADY_CLAIMED" }
	end
	local day, initialized
	day, reason, initialized = dayForAction(data, at)
	if not day then
		return false, { code = reason }
	end
	local supply, n = state.Supplies, state.Supplies.lifetimeClaims + 1
	local position = ((n - 1) % 7) + 1
	local amount, amountReason = Rules.RewardAmount(day, Config.SupplyRewardUnitsByCycleClaim[position])
	assert(amount, amountReason)
	local grantId = "retention:supply:" .. tostring(n)
	local cosmetic = Config.SupplyCosmeticByLifetimeClaim[n]
	local paid = settle(data, day, {
		kind = "Supply",
		lifetimeClaim = n,
		grantId = grantId,
		amountCash = amount,
		cosmeticId = cosmetic,
		sourceOperation = grantId,
	})
	local gems = GemRules.OnDailyGift(data, position)
	supply.lifetimeClaims, supply.lastClaimDay, supply.lastGrantId = n, key, grantId
	supply.lastPaid, supply.lastAmountCash = paid, if paid then amount else 0
	state.Revision += 1
	return true,
		{
			ok = true,
			code = if paid then "SUPPLY_CLAIMED" else "SUPPLY_PENDING",
			initialized = initialized,
			grantId = grantId,
			sourceOperation = grantId,
			dayKey = key,
			lifetimeClaim = n,
			cyclePosition = position,
			band = day.regionBand,
			unitCash = day.unitCash,
			rewardConfigVersion = day.rewardConfigVersion,
			amountCash = if paid then amount else 0,
			cosmeticId = if paid then cosmetic else nil,
			gems = gems,
		}
end
function Rules.RecoverPending(data, expectedId)
	local state = data.Retention
	if not state or next(state.PendingRewards) == nil then
		return false, { code = "NO_PENDING_REWARD" }
	end
	local ids = {}
	for id in state.PendingRewards do
		table.insert(ids, id)
	end
	table.sort(ids)
	local id = expectedId or ids[1]
	local reward = state.PendingRewards[id]
	if not reward then
		return false, { code = "NO_PENDING_REWARD" }
	end
	if not Money.Validate(data.Economy.Balance + reward.amountCash) then
		return false, { code = "MONETARY_OVERFLOW" }
	end
	data.Economy.Balance += reward.amountCash
	applyCosmetic(data, reward.cosmeticId)
	local day = state.Day
	if reward.kind == "Supply" then
		if state.Supplies.lastGrantId == id then
			state.Supplies.lastPaid, state.Supplies.lastAmountCash = true, reward.amountCash
		end
	elseif day and day.dayKey == reward.dayKey then
		local quest = day[reward.questId]
		quest.paid, quest.paidCash, quest.grantId = true, reward.amountCash, id
	end
	state.PendingRewards[id] = nil
	state.Revision += 1
	return true,
		{
			code = "RETENTION_RECOVERED",
			grantId = id,
			dayKey = reward.dayKey,
			amountCash = reward.amountCash,
			unitCash = reward.unitCash,
			band = reward.regionBand,
			rewardConfigVersion = reward.rewardConfigVersion,
			sourceOperation = reward.sourceOperation,
			cosmeticId = reward.cosmeticId,
		}
end
function Rules.ResolveTitle(data)
	local state = data.Retention or {}
	local selected = state.SelectedTitle
	if selected == nil then
		local commerce = data.Commerce or {}
		if (commerce.Entitlements or {}).VIP == true and (commerce.Appearance or {}).VIPTitle == "On" then
			return "Rift Patron", "RiftPatron"
		end
		return nil, "None"
	end
	if selected == "None" then
		return nil, "None"
	end
	if selected == "RiftPatron" then
		if ((data.Commerce or {}).Entitlements or {}).VIP == true then
			return "Rift Patron", selected
		end
		return nil, "None"
	end
	local definition = Config.MilestoneById[selected]
	if definition and state.Milestones and state.Milestones[selected] then
		return definition.Label, selected
	end
	return nil, "None"
end
function Rules.EquipMilestone(data, slot, value)
	local field = ({
		Title = "SelectedTitle",
		Nameplate = "SelectedNameplate",
		Plaque = "SelectedPlaque",
		Badge = "SelectedBadge",
	})[slot]
	if not field or not shortString(value) then
		return false, { code = "INVALID_SELECTION" }
	end
	local state = data.Retention
	if not state then
		return false, { code = "NOT_READY" }
	end
	if value == "RiftPatron" then
		if slot ~= "Title" or ((data.Commerce or {}).Entitlements or {}).VIP ~= true then
			return false, { code = "NOT_OWNED" }
		end
	elseif value ~= "None" then
		local definition = Config.MilestoneById[value]
		if not definition or definition.Slot ~= slot or not state.Milestones[value] then
			return false, { code = "NOT_OWNED" }
		end
	end
	if state[field] == value then
		return false, { ok = true, code = "UNCHANGED" }
	end
	state[field], state.Revision = value, state.Revision + 1
	return true, { ok = true, code = "EQUIPPED", slot = slot, value = value }
end
function Rules.FeatureDiscovery(data, value)
	if not shortString(value) then
		return false, { code = "INVALID_DISCOVERY" }
	end
	local id = if value == "None" then nil else value
	local definition = id and Catalog.Get(id)
	if
		id
		and (
			not definition
			or definition.id ~= id
			or definition.launchStatus ~= "Live"
			or not Rules.IsDiscovered(data, id)
		)
	then
		return false, { code = "NOT_DISCOVERED" }
	end
	if data.Retention.FeaturedSpeciesId == id then
		return false, { ok = true, code = "UNCHANGED" }
	end
	data.Retention.FeaturedSpeciesId, data.Retention.Revision = id, data.Retention.Revision + 1
	return true, { ok = true, code = "FEATURED", speciesId = id or "None" }
end
return table.freeze(Rules)
