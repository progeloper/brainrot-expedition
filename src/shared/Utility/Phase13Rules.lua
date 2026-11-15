--!strict
-- Pure profile transitions. No services, Instances, yielding, persistence or presentation.
local Config = require(script.Parent.Parent.Config.Phase13)
local Catalog = require(script.Parent.Parent.Config.BrainrotCatalog)
local Weapons = require(script.Parent.Parent.Config.Weapons)
local Training = require(script.Parent.Parent.Config.Training)
local CampFlags = require(script.Parent.Parent.Config.CampReworkFlags)
local Legs = require(script.Parent.Parent.Config.LegsTraining)
local LegsFlags = require(script.Parent.Parent.Config.LegsTrainingFlags)
local Money = require(script.Parent.CurrencyDenomination)
local Values = require(script.Parent.Phase12Rules)
local Commerce = require(script.Parent.Phase13CommerceRules)
local Retention = require(script.Parent.RetentionRules)
local GemRules = require(script.Parent.GemRules)
local Economy = require(script.Parent.Parent.Config.Economy)
local Rules = {}
local rarityRank =
	{ Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Celestial = 7, Astral = 7, Secret = 8 }
local function integer(v, lo, hi)
	return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end
local function map(v)
	return type(v) == "table"
end
local function reject(code)
	return { ok = false, code = code }
end
function Rules.GetCapacity(data)
	local p = data and data.Phase13
	return 12 + 6 * (if p and integer(p.ExpansionLevel, 0, 6) then p.ExpansionLevel else 0)
end
function Rules.FindReward(id)
	for _, r in Config.ExpansionRows do
		if r.id == id then
			return r, "Expansion"
		end
	end
	for _, r in Config.DesignRows do
		if r.id == id and not r.starter then
			return r, "Design"
		end
	end
	return nil, nil
end
-- P15: the repeatable Prestige rebirth exists only once all expansions are owned.
function Rules.FindRewardFor(data, id)
	if id == Economy.Prestige.Id then
		local p = data and data.Phase13
		local price = if p and p.ExpansionLevel == 6 then GemRules.PrestigePrice(data) else nil
		if not price then
			return nil, nil
		end
		return {
			id = Economy.Prestige.Id,
			displayName = Economy.Prestige.DisplayName,
			price = price,
			minimumRarity = "Legendary",
			required = 4,
		},
			"Prestige"
	end
	return Rules.FindReward(id)
end
function Rules.Cart(id)
	for _, r in Config.CartRows do
		if r.id == id then
			return r
		end
	end
	return nil
end
function Rules.Default()
	return {
		Version = 1,
		ConfigurationVersion = Config.ConfigurationVersion,
		ExpansionLevel = 0,
		RebirthCount = 0,
		OwnedBaseDesigns = { [Config.InitialDesignId] = true },
		SelectedBaseDesignId = Config.InitialDesignId,
		OwnedWeaponIds = { [Config.InitialWeaponId] = true },
		SelectedWeaponId = Config.InitialWeaponId,
		OwnedCartIds = { [Config.InitialCartId] = true },
		SelectedCartId = Config.InitialCartId,
		SpeedLevel = 0,
		CargoLevel = 0,
		EligibilityRevision = 0,
		OperationSequence = 0,
		Operations = {},
		OperationOrder = {},
		LastPrunedSequence = 0,
		AcknowledgedOperationSequence = 0,
		NewcomerProtectionEnded = false,
	}
end
-- Camp Rework Training (TrainingV1Enabled): SpeedLevel n -> TrainingLevel 5n, never lowering anyone's
-- speed. Idempotent and versioned (TrainingVersion). SpeedLevel is kept for migration only.
function Rules.MigrateTraining(data, force)
	if not force and not CampFlags.Training() then
		return false
	end
	local p = data.Phase13
	if type(p) ~= "table" then
		return false
	end
	local speed = if type(p.SpeedLevel) == "number" then p.SpeedLevel else 0
	local current = if type(p.TrainingLevel) == "number" then p.TrainingLevel else nil
	local target = math.max(current or 0, Training.LevelForOldSpeed(speed))
	local changed = p.TrainingVersion ~= Training.Version or current ~= target
	p.TrainingLevel = target
	if type(p.TrainingXp) ~= "number" or p.TrainingXp ~= p.TrainingXp or p.TrainingXp < 0 then
		p.TrainingXp = 0
		changed = true
	end
	if type(p.OwnedRollers) ~= "table" then
		p.OwnedRollers = {}
		changed = true
	end
	if p.OwnedRollers.Wooden ~= true then
		p.OwnedRollers.Wooden = true
		changed = true
	end
	if type(p.SelectedRoller) ~= "string" or p.OwnedRollers[p.SelectedRoller] ~= true then
		p.SelectedRoller = "Wooden"
		changed = true
	end
	p.TrainingVersion = Training.Version
	return changed
end
-- Playtest Fixes 2 Part G (LegsTrainingV1Enabled): Legs fields default to zero / empty. Idempotent
-- and versioned (LegsVersion); also grants any free trail the saved level already earned. Profiles
-- are never touched while the flag is off.
function Rules.MigrateLegs(data, force)
	if not force and not LegsFlags.Enabled() then
		return false
	end
	local p = data.Phase13
	if type(p) ~= "table" then
		return false
	end
	local changed = p.LegsVersion ~= Legs.Version
	if not integer(p.LegsLevel, 0, Legs.MaxLevel) then
		p.LegsLevel = 0
		changed = true
	end
	if type(p.LegsXP) ~= "number" or p.LegsXP ~= p.LegsXP or p.LegsXP < 0 then
		p.LegsXP = 0
		changed = true
	end
	if type(p.OwnedTrails) ~= "table" then
		p.OwnedTrails = {}
		changed = true
	end
	for _, id in Legs.FreeTrailsAt(p.LegsLevel) do
		if p.OwnedTrails[id] ~= true then
			p.OwnedTrails[id] = true
			changed = true
		end
	end
	if type(p.EquippedTrail) ~= "string" or (p.EquippedTrail ~= "" and p.OwnedTrails[p.EquippedTrail] ~= true) then
		p.EquippedTrail = ""
		changed = true
	end
	p.LegsVersion = Legs.Version
	return changed
end
-- One Legs tick: add XP, level up (possibly several levels), grant free trails. Returns the levels
-- gained and the trail ids newly unlocked.
function Rules.ApplyLegsTick(data, xp)
	local p = data.Phase13
	if type(p) ~= "table" or type(p.LegsLevel) ~= "number" or type(p.OwnedTrails) ~= "table" then
		return false, reject("LEGS_NOT_READY")
	end
	if type(xp) ~= "number" or xp ~= xp or xp <= 0 or xp > 10_000 then
		return false, reject("INVALID_XP")
	end
	if p.LegsLevel >= Legs.MaxLevel then
		p.LegsXP = 0
		return true, { levels = 0, level = p.LegsLevel, xp = 0, unlocked = {} }
	end
	p.LegsXP += xp
	local gained = 0
	while p.LegsLevel < Legs.MaxLevel and p.LegsXP >= Legs.XpToNext(p.LegsLevel) do
		p.LegsXP -= Legs.XpToNext(p.LegsLevel)
		p.LegsLevel += 1
		gained += 1
	end
	if p.LegsLevel >= Legs.MaxLevel then
		p.LegsXP = 0
	end
	local unlocked = {}
	for _, id in Legs.FreeTrailsAt(p.LegsLevel) do
		if p.OwnedTrails[id] ~= true then
			p.OwnedTrails[id] = true
			table.insert(unlocked, id)
		end
	end
	return true, { levels = gained, level = p.LegsLevel, xp = p.LegsXP, unlocked = unlocked }
end
-- Equip an owned trail ("" unequips). One trail at a time.
function Rules.ApplyTrailEquip(data, trailId)
	local p = data.Phase13
	if type(p) ~= "table" or type(p.OwnedTrails) ~= "table" then
		return false, reject("LEGS_NOT_READY")
	end
	if trailId ~= "" and (type(trailId) ~= "string" or Legs.TrailsById[trailId] == nil) then
		return false, reject("UNKNOWN_TRAIL")
	end
	if trailId ~= "" and p.OwnedTrails[trailId] ~= true then
		return false, reject("NOT_OWNED")
	end
	p.EquippedTrail = trailId
	return true, { equipped = trailId }
end
-- Best (highest multiplier) owned roller id.
function Rules.BestRoller(p)
	local best, multiplier = "Wooden", 1
	for _, roller in Training.Rollers do
		if type(p.OwnedRollers) == "table" and p.OwnedRollers[roller.id] == true and roller.multiplier > multiplier then
			best, multiplier = roller.id, roller.multiplier
		end
	end
	return best
end
-- One Training tick: add XP and level up (possibly several levels). Returns levels gained.
function Rules.ApplyTrainingTick(data, xp)
	local p = data.Phase13
	if type(p) ~= "table" or type(p.TrainingLevel) ~= "number" then
		return false, reject("TRAINING_NOT_READY")
	end
	if type(xp) ~= "number" or xp ~= xp or xp <= 0 or xp > 10_000 then
		return false, reject("INVALID_XP")
	end
	if p.TrainingLevel >= Training.MaxLevel then
		p.TrainingXp = 0
		return true, { levels = 0, level = p.TrainingLevel, xp = 0 }
	end
	p.TrainingXp += xp
	local gained = 0
	while p.TrainingLevel < Training.MaxLevel and p.TrainingXp >= Training.XpToNext(p.TrainingLevel) do
		p.TrainingXp -= Training.XpToNext(p.TrainingLevel)
		p.TrainingLevel += 1
		gained += 1
	end
	if p.TrainingLevel >= Training.MaxLevel then
		p.TrainingXp = 0
	end
	return true, { levels = gained, level = p.TrainingLevel, xp = p.TrainingXp }
end
-- Permanent roller purchase (Cash). Selecting a roller you own is free.
function Rules.ApplyRollerPurchase(data, rollerId)
	local p = data.Phase13
	local roller = Training.RollersById[rollerId]
	if not roller or type(p.OwnedRollers) ~= "table" then
		return false, reject("UNKNOWN_OFFER")
	end
	if p.OwnedRollers[rollerId] == true then
		p.SelectedRoller = rollerId
		return true, { code = "APPLIED", category = "Roller", id = rollerId, price = 0, selected = true }
	end
	if data.Economy.Balance < roller.price then
		return false, reject("INSUFFICIENT_CASH")
	end
	data.Economy.Balance -= roller.price
	p.OwnedRollers[rollerId] = true
	p.SelectedRoller = Rules.BestRoller(p)
	return true, { code = "APPLIED", category = "Roller", id = rollerId, price = roller.price }
end
function Rules.Migrate(data)
	if data.Phase13 ~= nil then
		local changed = Rules.MigrateTraining(data)
		changed = Rules.MigrateLegs(data) or changed
		local ok, reason = Rules.Validate(data)
		return ok, reason, changed
	end
	local p = Rules.Default()
	local old = data.Progression and data.Progression.Upgrades or {}
	if old.CART_SPEED_1 == true then
		p.SpeedLevel = 1
	end
	if old.CARGO_1 == true then
		p.CargoLevel = 1
	end
	data.Phase13 = p
	Rules.MigrateTraining(data)
	Rules.MigrateLegs(data)
	for i = 1, 48 do
		if data.Base.Slots[tostring(i)] == nil then
			data.Base.Slots[tostring(i)] = { accumulatedCash = 0 }
		end
	end
	return true, nil, true
end
function Rules.Validate(data)
	local p = data.Phase13
	if not map(p) or p.Version ~= 1 then
		return false, "PHASE13_VERSION_UNSUPPORTED"
	end
	if type(p.ConfigurationVersion) ~= "string" or #p.ConfigurationVersion < 1 or #p.ConfigurationVersion > 64 then
		return false, "PHASE13_INVALID_CONFIGURATION"
	end
	for _, s in
		{
			{ "ExpansionLevel", 0, 6 },
			{ "RebirthCount", 0, 9007199254740991 },
			{ "SpeedLevel", 0, 5 },
			{ "CargoLevel", 0, 3 },
			{ "EligibilityRevision", 0, 9007199254740991 },
			{ "OperationSequence", 0, 9007199254740991 },
			{ "LastPrunedSequence", 0, 9007199254740991 },
			{ "AcknowledgedOperationSequence", 0, 9007199254740991 },
		}
	do
		if not integer(p[s[1]], s[2], s[3]) then
			return false, "PHASE13_INVALID_" .. s[1]
		end
	end
	for _, field in { "OwnedBaseDesigns", "OwnedWeaponIds", "OwnedCartIds", "Operations", "OperationOrder" } do
		if not map(p[field]) then
			return false, "PHASE13_INVALID_" .. field
		end
	end
	for _, pair in
		{
			{ "OwnedBaseDesigns", "SelectedBaseDesignId" },
			{ "OwnedWeaponIds", "SelectedWeaponId" },
			{ "OwnedCartIds", "SelectedCartId" },
		}
	do
		if type(p[pair[2]]) ~= "string" or p[pair[1]][p[pair[2]]] ~= true then
			return false, "PHASE13_SELECTION_NOT_OWNED"
		end
		for id, owned in p[pair[1]] do
			if type(id) ~= "string" or owned ~= true then
				return false, "PHASE13_INVALID_OWNERSHIP"
			end
		end
	end
	if
		p.OwnedWeaponIds[Config.InitialWeaponId] ~= true
		or p.OwnedCartIds[Config.InitialCartId] ~= true
		or p.OwnedBaseDesigns[Config.InitialDesignId] ~= true
	then
		return false, "PHASE13_STARTER_ENTITLEMENT_MISSING"
	end
	if
		p.LastPrunedSequence > p.AcknowledgedOperationSequence
		or p.AcknowledgedOperationSequence > p.OperationSequence
	then
		return false, "PHASE13_INVALID_JOURNAL_BOUNDARY"
	end
	if type(p.NewcomerProtectionEnded) ~= "boolean" then
		return false, "PHASE13_INVALID_PROTECTION"
	end
	-- Camp Rework (optional; absent on older profiles).
	if p.CleanEscapes ~= nil and not integer(p.CleanEscapes, 0, 1000000) then
		return false, "PHASE13_INVALID_CleanEscapes"
	end
	if p.TrainingLevel ~= nil then
		if not integer(p.TrainingLevel, 0, Training.MaxLevel) then
			return false, "PHASE13_INVALID_TrainingLevel"
		end
		if type(p.TrainingXp) ~= "number" or p.TrainingXp ~= p.TrainingXp or p.TrainingXp < 0 or p.TrainingXp > 1e12 then
			return false, "PHASE13_INVALID_TrainingXp"
		end
		if not map(p.OwnedRollers) or p.OwnedRollers.Wooden ~= true then
			return false, "PHASE13_INVALID_OwnedRollers"
		end
		for id, owned in p.OwnedRollers do
			if Training.RollersById[id] == nil or owned ~= true then
				return false, "PHASE13_INVALID_OwnedRollers"
			end
		end
		if type(p.SelectedRoller) ~= "string" or p.OwnedRollers[p.SelectedRoller] ~= true then
			return false, "PHASE13_INVALID_SelectedRoller"
		end
	end
	-- Legs training (optional; absent while LegsTrainingV1Enabled has never been on).
	if p.LegsLevel ~= nil then
		if not integer(p.LegsLevel, 0, Legs.MaxLevel) then
			return false, "PHASE13_INVALID_LegsLevel"
		end
		if type(p.LegsXP) ~= "number" or p.LegsXP ~= p.LegsXP or p.LegsXP < 0 or p.LegsXP > 1e12 then
			return false, "PHASE13_INVALID_LegsXP"
		end
		if not map(p.OwnedTrails) then
			return false, "PHASE13_INVALID_OwnedTrails"
		end
		for id, owned in p.OwnedTrails do
			if Legs.TrailsById[id] == nil or owned ~= true then
				return false, "PHASE13_INVALID_OwnedTrails"
			end
		end
		if type(p.EquippedTrail) ~= "string" or (p.EquippedTrail ~= "" and p.OwnedTrails[p.EquippedTrail] ~= true) then
			return false, "PHASE13_INVALID_EquippedTrail"
		end
	end
	if #p.OperationOrder > Config.OperationJournalLimit then
		return false, "PHASE13_JOURNAL_OVERFLOW"
	end
	local seen = {}
	local previousSequence = p.LastPrunedSequence
	for _, id in p.OperationOrder do
		local receipt = p.Operations[id]
		if
			type(id) ~= "string"
			or #id < 1
			or #id > 240
			or id:find("%c")
			or seen[id]
			or not map(receipt)
			or not integer(receipt.Sequence, 1, p.OperationSequence)
			or receipt.OperationId ~= id
			or receipt.Sequence <= previousSequence
			or not map(receipt.Result)
			or not integer(receipt.CommitRevision, 0, 9007199254740991)
			or type(receipt.Kind) ~= "string"
			or #receipt.Kind < 1
			or #receipt.Kind > 240
			or not Money.Validate(receipt.Cutover)
		then
			return false, "PHASE13_INVALID_OPERATION"
		end
		seen[id] = true
		previousSequence = receipt.Sequence
	end
	for id in p.Operations do
		if not seen[id] then
			return false, "PHASE13_UNINDEXED_OPERATION"
		end
	end
	return true, nil
end
function Rules.Cash(data)
	local total = data.Economy.Balance
	if not Money.Validate(total) then
		return nil, "INVALID_BALANCE"
	end
	local capacity = Rules.GetCapacity(data)
	for key, slot in data.Base.Slots do
		if not Money.Validate(slot.accumulatedCash) then
			return nil, "MONETARY_OVERFLOW"
		end
		local index = tonumber(key)
		if index and index <= capacity then
			if total > Money.MAX_AMOUNT - slot.accumulatedCash then
				return nil, "MONETARY_OVERFLOW"
			end
			total += slot.accumulatedCash
		end
	end
	return total, nil
end
function Rules.InventorySignature(data)
	local a = {}
	for id, r in data.Collection.BrainrotInstances do
		table.insert(a, id .. ":" .. tostring(r.speciesId) .. ":" .. tostring(r.mutationId))
	end
	table.sort(a)
	for i = 1, 48 do
		local s = data.Base.Slots[tostring(i)]
		table.insert(a, tostring(i) .. "=" .. tostring(s and s.brainrotId))
	end
	if data.ChariotTeam then
		for i = 1, 6 do
			table.insert(a, "E" .. i .. "=" .. tostring(data.ChariotTeam.Assignments[tostring(i)]))
		end
	end
	return table.concat(a, "|")
end
function Rules.ShouldInvalidate(before, data)
	if not before.Phase13 or not data.Phase13 then
		return false
	end
	local b, a = Rules.Cash(before), Rules.Cash(data)
	-- Transfer of already accrued cash is neutral. Ordinary accrual does not call CommitMutation.
	if a and b and a ~= b then
		return true
	end
	if Rules.InventorySignature(before) ~= Rules.InventorySignature(data) then
		return true
	end
	local x, y = before.Phase13, data.Phase13
	for _, k in
		{
			"ExpansionLevel",
			"RebirthCount",
			"SelectedBaseDesignId",
			"SelectedWeaponId",
			"SelectedCartId",
			"SpeedLevel",
			"CargoLevel",
		}
	do
		if x[k] ~= y[k] then
			return true
		end
	end
	return false
end
-- Seconds of post-rebirth income (permanent multipliers incl. the new +10%; no temporary boosts)
-- needed to earn back `lost` Cash. nil when nothing is lost or there is no income.
function Rules.PaybackSeconds(data, lost, baseCps)
	if type(lost) ~= "number" or lost <= 0 or type(baseCps) ~= "number" or baseCps <= 0 then
		return nil
	end
	local b = GemRules.IncomeBreakdown(data)
	local after = (1 + b.rebirthBonus + Economy.Income.RebirthBonusPerRebirth + b.vipBonus) * b.pass
	return lost / (baseCps * after)
end
-- The next rebirth reward: the next expansion, or Prestige once every expansion is owned.
function Rules.NextRebirthRewardId(data)
	local p = data.Phase13
	local row = Config.ExpansionRows[p.ExpansionLevel + 1]
	return if row then row.id else "PRESTIGE"
end
-- READY when either route could rebirth into the next reward right now.
function Rules.RebirthReady(data)
	local id = Rules.NextRebirthRewardId(data)
	for _, route in { "Cash", "Collection" } do
		local ok, q = pcall(Rules.QuoteRebirth, data, id, route)
		if ok and type(q) == "table" and q.ok == true then
			return true, route
		end
	end
	return false, nil
end
function Rules.QuoteRebirth(data, rewardId, route)
	if route ~= "Cash" and route ~= "Collection" then
		return reject("INVALID_ROUTE")
	end
	local r, kind = Rules.FindRewardFor(data, rewardId)
	if not r then
		return reject("UNKNOWN_REWARD")
	end
	if kind == "Prestige" and route ~= "Cash" then
		return reject("PRESTIGE_CASH_ONLY")
	end
	local p = data.Phase13
	if kind == "Expansion" and r.level ~= p.ExpansionLevel + 1 then
		return reject(if r.level <= p.ExpansionLevel then "ALREADY_OWNED" else "SEQUENTIAL_REWARD_REQUIRED")
	end
	if kind == "Design" and p.OwnedBaseDesigns[r.id] then
		return reject("ALREADY_OWNED")
	end
	local total, reason = Rules.Cash(data)
	if not total then
		return reject(reason)
	end
	local capacity = Rules.GetCapacity(data)
	if route == "Collection" then
		for key, slot in data.Base.Slots do
			local index = tonumber(key)
			if index and index > capacity and (slot.brainrotId ~= nil or slot.accumulatedCash ~= 0) then
				-- Collection consumes all owned individuals. Never turn an unavailable
				-- legacy record into a partial sacrifice, wallet credit or silent loss.
				return reject("UNAVAILABLE_SAVED_SLOT")
			end
		end
	end
	local full = true
	local seen = {}
	local quality = 0
	local ownedCount = 0
	local baseCps = 0
	for _ in data.Collection.BrainrotInstances do
		ownedCount += 1
	end
	for i = 1, capacity do
		local id = data.Base.Slots[tostring(i)].brainrotId
		local record = id and data.Collection.BrainrotInstances[id]
		if not record or seen[id] then
			full = false
		else
			seen[id] = true
			local def = Catalog.Get(record.speciesId)
			if def then
				baseCps += def.cashPerSecond * Values.MutationMultiplier(record.mutationId or "None")
			end
			if def and (rarityRank[def.tier] or 0) >= (rarityRank[r.minimumRarity] or 99) then
				quality += 1
			end
		end
	end
	local ok = if route == "Cash" then total >= r.price else full and quality >= r.required
	return {
		ok = ok,
		code = if ok
			then "READY"
			elseif route == "Cash" then "INSUFFICIENT_CASH"
			elseif not full then "BASE_NOT_FULL"
			else "MISSING_QUALITY",
		rewardId = r.id,
		rewardKind = kind,
		route = route,
		price = r.price,
		totalCash = total,
		capacity = capacity,
		ownedCount = ownedCount,
		qualifyingIndividuals = quality,
		requiredIndividuals = r.required,
		minimumRarity = r.minimumRarity,
		full = full,
		previewRevision = p.EligibilityRevision,
		nextSequence = p.OperationSequence + 1,
		inventorySignature = Rules.InventorySignature(data),
		baseCps = baseCps,
		productionCps = baseCps * Commerce.ProductionMultiplier(data),
		-- P15: what this rebirth adds.
		gemReward = if kind == "Prestige" then Economy.GemSources.Prestige else Economy.GemSources.Rebirth,
		incomeBonusBefore = GemRules.RebirthCount(data) * Economy.Income.RebirthBonusPerRebirth,
		incomeBonusAfter = (GemRules.RebirthCount(data) + 1) * Economy.Income.RebirthBonusPerRebirth,
		-- Rebirth UI v2: what is lost, and how long the new (permanent) income takes to earn it back.
		lostCash = if route == "Cash" then total else 0,
		lostIndividuals = if route == "Collection" then ownedCount else 0,
		paybackSeconds = Rules.PaybackSeconds(data, if route == "Cash" then total else 0, baseCps),
		prestigeCount = GemRules.PrestigeCount(data),
	}
end
function Rules.ApplyRebirth(data, request, at)
	if request.previewRevision ~= data.Phase13.EligibilityRevision then
		return false, reject("STALE_PREVIEW")
	end
	local q = Rules.QuoteRebirth(data, request.rewardId, request.route)
	if not q.ok then
		return false, q
	end
	if request.route == "Collection" and request.inventorySignature ~= q.inventorySignature then
		return false, reject("STALE_INVENTORY")
	end
	if request.route == "Cash" then
		data.Economy.Balance = 0
	else
		data.Economy.Balance = q.totalCash
		table.clear(data.Collection.BrainrotInstances)
		for _, slot in data.Base.Slots do
			slot.brainrotId = nil
		end
		for i = 1, 6 do
			data.ChariotTeam.Assignments[tostring(i)] = false
		end
	end
	-- q.capacity is the committed capacity before this reward unlocks new slots.
	-- Unavailable legacy money is preserved, even when this expansion unlocks it.
	for index = 1, q.capacity do
		data.Base.Slots[tostring(index)].accumulatedCash = 0
	end
	local r, kind = Rules.FindRewardFor(data, request.rewardId)
	if kind == "Expansion" then
		data.Phase13.ExpansionLevel = r.level
	elseif kind == "Design" then
		data.Phase13.OwnedBaseDesigns[r.id] = true
	end
	data.Phase13.RebirthCount += 1
	local gems = GemRules.OnRebirth(data, kind == "Prestige")
	return true,
		{
			code = "APPLIED",
			rewardId = r.id,
			rewardKind = kind,
			route = request.route,
			cutover = at,
			sacrificedCash = if request.route == "Cash" then q.totalCash else 0,
			sacrificedIndividuals = if request.route == "Collection" then q.ownedCount else 0,
			baseCpsBefore = q.baseCps,
			productionCpsBefore = q.productionCps,
			capacity = Rules.GetCapacity(data),
			gems = gems,
			incomeBonus = GemRules.RebirthCount(data) * Economy.Income.RebirthBonusPerRebirth,
		}
end
function Rules.GrantUpgrade(data, offer)
	local p = data.Phase13
	local track = offer.grant and offer.grant.trackId
	local level = offer.grant and offer.grant.level
	if track == "CartSpeed" and CampFlags.Training() then
		return false, "SPEED_RETIRED_USE_TRAINING"
	end
	local field = if track == "CartSpeed" then "SpeedLevel" elseif track == "Cargo" then "CargoLevel" else nil
	if not field or not integer(level, 1, if field == "SpeedLevel" then 5 else 3) then
		return false, "UNSUPPORTED_UPGRADE"
	end
	if level <= p[field] then
		return false, "ALREADY_OWNED"
	end
	if level ~= p[field] + 1 then
		return false, "PREDECESSOR_REQUIRED"
	end
	p[field] = level
	return true, nil
end
function Rules.ApplyPurchase(data, category, id)
	local p = data.Phase13
	local definition, owned, field
	if category == "Weapon" then
		definition = Weapons.Get(id)
		owned = p.OwnedWeaponIds
		field = "SelectedWeaponId"
	elseif category == "Cart" then
		definition = Rules.Cart(id)
		owned = p.OwnedCartIds
		field = "SelectedCartId"
	else
		return false, reject("INVALID_CATEGORY")
	end
	if not definition then
		return false, reject("UNKNOWN_OFFER")
	end
	-- Specials are granted only by their own server paths (Gems, Robux pass, milestones).
	if definition.special ~= nil then
		return false, reject("NOT_FOR_SALE")
	end
	if owned[id] then
		return false, reject("ALREADY_OWNED")
	end
	local price = definition.price
	if not Money.Validate(price) then
		return false, reject("INVALID_PRICE")
	end
	if data.Economy.Balance < price then
		return false, reject("INSUFFICIENT_CASH")
	end
	data.Economy.Balance -= price
	owned[id] = true
	return true, { code = "APPLIED", id = id, category = category, price = price, selectionField = field }
end
-- Camp Rework sell-back (CampReworkV1Enabled): Cash-bought ladder weapons and carts return 25% of
-- their Cash price. Never the starter, a special (Robux/Gem/Won), anything unowned, or the item in use
-- (switch first, so the live tool/cart never loses its definition mid-session).
Rules.SellBackRate = 0.25
function Rules.SellBackValue(category, id)
	local price
	if category == "Weapon" then
		if not Weapons.IsSellable(id) then
			return nil
		end
		price = Weapons.Get(id).price
	elseif category == "Cart" then
		local row = Rules.Cart(id)
		if not row or row.starter or type(row.price) ~= "number" or row.price <= 0 then
			return nil
		end
		price = row.price
	else
		return nil
	end
	return math.floor(price * Rules.SellBackRate)
end
function Rules.ApplySellBack(data, category, id)
	local p = data.Phase13
	local value = Rules.SellBackValue(category, id)
	if value == nil then
		return false, reject("NOT_SELLABLE")
	end
	local owned = if category == "Weapon" then p.OwnedWeaponIds else p.OwnedCartIds
	local selected = if category == "Weapon" then p.SelectedWeaponId else p.SelectedCartId
	if owned[id] ~= true then
		return false, reject("NOT_OWNED")
	end
	if selected == id then
		return false, reject("EQUIPPED")
	end
	if not Money.Validate(data.Economy.Balance) or data.Economy.Balance > Money.MAX_AMOUNT - value then
		return false, reject("BALANCE_LIMIT")
	end
	owned[id] = nil
	data.Economy.Balance += value
	return true, { code = "APPLIED", category = category, id = id, refund = value, kind = "SellBack" }
end
function Rules.Select(data, category, id)
	local p = data.Phase13
	local owned, field
	if category == "Weapon" then
		owned = p.OwnedWeaponIds
		field = "SelectedWeaponId"
	elseif category == "Cart" then
		owned = p.OwnedCartIds
		field = "SelectedCartId"
	elseif category == "Design" then
		owned = p.OwnedBaseDesigns
		field = "SelectedBaseDesignId"
	else
		return false, reject("INVALID_CATEGORY")
	end
	if not owned[id] then
		return false, reject("NOT_OWNED")
	end
	p[field] = id
	return true, { code = "APPLIED", id = id, category = category }
end
function Rules.ApplySwap(data, request, at)
	if request.previewRevision ~= data.Phase13.EligibilityRevision then
		return false, reject("STALE_PREVIEW")
	end
	local i = request.slotIndex
	if not integer(i, 1, Rules.GetCapacity(data)) then
		return false, reject("LOCKED_SLOT")
	end
	if request.action ~= "Swap" and request.action ~= "SellAndReplace" then
		return false, reject("INVALID_ACTION")
	end
	local slot = data.Base.Slots[tostring(i)]
	if slot.brainrotId ~= request.outgoingId then
		return false, reject("STALE_SLOT")
	end
	local outgoing = data.Collection.BrainrotInstances[request.outgoingId]
	local incoming = request.incomingRecord
	if not outgoing or type(incoming) ~= "table" or incoming.ItemId == request.outgoingId then
		return false, reject("INVALID_INDIVIDUAL")
	end
	for key, s in data.Base.Slots do
		if key ~= tostring(i) and s.brainrotId == incoming.ItemId then
			return false, reject("INCOMING_ALREADY_ASSIGNED")
		end
	end
	local existing = data.Collection.BrainrotInstances[incoming.ItemId]
	if request.incomingFresh and existing then
		return false, reject("OWNERSHIP_CHANGED")
	end
	if not request.incomingFresh and (not existing or existing.speciesId ~= incoming.BrainrotId) then
		return false, reject("OWNERSHIP_CHANGED")
	end
	local mutation = Values.RecordMutation(incoming)
	if not mutation then
		return false, reject("INVALID_MUTATION")
	end
	if existing and Values.NormalizeMutation(existing.mutationId or "None") ~= mutation then
		return false, reject("MUTATION_CHANGED")
	end
	local incomingDefinition = Catalog.Get(incoming.BrainrotId)
	if request.incomingFresh and (not incomingDefinition or incomingDefinition.launchStatus ~= "Live") then
		return false, reject("SPECIES_NOT_RELEASED")
	end
	local sale = Values.EffectiveValues(outgoing.speciesId, outgoing.mutationId or "None")
	if not sale then
		return false, reject("UNKNOWN_SPECIES")
	end
	local platformEarnings = slot.accumulatedCash
	local credit = platformEarnings + (if request.action == "SellAndReplace" then sale.sellValue else 0)
	if not Money.Validate(credit) or data.Economy.Balance > Money.MAX_AMOUNT - credit then
		return false, reject("MONETARY_OVERFLOW")
	end
	data.Economy.Balance += credit
	slot.accumulatedCash = 0
	-- A swap settles the outgoing platform's earnings; sale proceeds remain separate.
	local retention
	if platformEarnings > 0 then
		retention = Retention.RecordPlatformSettlement(data, {
			source = "OwnPlatformIncome",
			ownerUserId = request.ownerUserId,
			earnings = platformEarnings,
			at = at,
			operationId = request.operationId,
		})
	end
	if request.action == "SellAndReplace" then
		data.Collection.BrainrotInstances[request.outgoingId] = nil
	end
	if request.incomingFresh then
		data.Collection.BrainrotInstances[incoming.ItemId] = {
			speciesId = incoming.BrainrotId,
			mutationId = mutation,
			firstBankCompleted = true,
			firstBankedAt = at,
			metadata = { MutationId = mutation, FirstBankCompleted = true, DurableOwnerUserId = request.ownerUserId },
		}
	end
	slot.brainrotId = incoming.ItemId
	for e = 1, 6 do
		if data.ChariotTeam.Assignments[tostring(e)] == request.outgoingId then
			data.ChariotTeam.Assignments[tostring(e)] = false
		end
	end
	return true,
		{
			code = "APPLIED",
			action = request.action,
			outgoingId = request.outgoingId,
			incomingId = incoming.ItemId,
			settledCash = credit,
			retention = retention,
			saleCash = if request.action == "SellAndReplace" then sale.sellValue else 0,
			firstBank = request.incomingFresh,
			slotIndex = i,
		}
end
function Rules.AppendOperation(data, id, kind, revision, cutover, result)
	local p = data.Phase13
	-- The coordinator admits a new operation only after previous critical work is durably confirmed.
	p.AcknowledgedOperationSequence = p.OperationSequence
	p.OperationSequence += 1
	local receipt = {
		OperationId = id,
		Kind = kind,
		Sequence = p.OperationSequence,
		CommitRevision = revision,
		Cutover = cutover,
		Result = result,
	}
	p.Operations[id] = receipt
	table.insert(p.OperationOrder, id)
	while #p.OperationOrder > Config.OperationJournalLimit do
		local old = table.remove(p.OperationOrder, 1)
		local previous = p.Operations[old]
		assert(previous.Sequence <= p.AcknowledgedOperationSequence, "Cannot prune unacknowledged operation")
		p.LastPrunedSequence = math.max(p.LastPrunedSequence, previous.Sequence)
		p.Operations[old] = nil
	end
	return receipt
end
return table.freeze(Rules)
