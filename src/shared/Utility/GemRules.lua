--!strict
-- Pure Gem wallet and income-multiplier transitions (P15 economy).
-- No services, Instances, yielding, persistence or presentation. Every caller runs
-- these inside the existing profile writer, so a grant shares the covering save of
-- the action that earned it. Gems are server-authoritative; clients only read the
-- mirrored attributes and the snapshot.
local Economy = require(script.Parent.Parent.Config.Economy)
local Catalog = require(script.Parent.Parent.Config.BrainrotCatalog)
local MutationCatalog = require(script.Parent.Parent.Config.MutationCatalog)
local Money = require(script.Parent.CurrencyDenomination)
local CampFlags = require(script.Parent.Parent.Config.CampReworkFlags)

local Rules = {}
local DAY = 86400
local Sources = Economy.GemSources

local function integer(value: any, lo: number, hi: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= lo and value <= hi
end
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Rules.DefaultState(): any
	return {
		Version = 1,
		Lifetime = 0, -- every Gem ever received (free + paid), for analytics
		CashBoostUntil = 0,
		Day = { key = -1, tiers = {} },
		Mutations = {},
		IndexPaid = 0,
		Prestige = 0,
	}
end

-- Additive migration. Returns true when the profile changed.
function Rules.Migrate(data: any): boolean
	if type(data) ~= "table" or type(data.Economy) ~= "table" then
		return false
	end
	local changed = false
	if data.Economy.Gems == nil then
		data.Economy.Gems = 0
		changed = true
	end
	if data.Economy.GemState == nil then
		data.Economy.GemState = Rules.DefaultState()
		changed = true
	end
	return changed
end

-- Absent state is valid (pre-P15 profile awaiting migration); present state must be exact.
function Rules.Validate(data: any): (boolean, string?)
	local economy = data.Economy
	if economy.Gems == nil and economy.GemState == nil then
		return true, nil
	end
	if not integer(economy.Gems, 0, Economy.MaxGems) then
		return false, "INVALID_GEM_BALANCE"
	end
	local s = economy.GemState
	if type(s) ~= "table" or s.Version ~= 1 then
		return false, "INVALID_GEM_STATE"
	end
	if
		not integer(s.Lifetime, 0, Money.MAX_AMOUNT)
		or not finite(s.CashBoostUntil)
		or s.CashBoostUntil < 0
		or not integer(s.IndexPaid, 0, 1000)
		or not integer(s.Prestige, 0, Economy.Prestige.MaxCount)
		or type(s.Day) ~= "table"
		or not integer(s.Day.key, -1, Money.MAX_AMOUNT)
		or type(s.Day.tiers) ~= "table"
		or type(s.Mutations) ~= "table"
	then
		return false, "INVALID_GEM_STATE"
	end
	for key, value in s.Day.tiers do
		if type(key) ~= "string" or #key > 16 or value ~= true then
			return false, "INVALID_GEM_STATE"
		end
	end
	for key, value in s.Mutations do
		if type(key) ~= "string" or #key > 16 or value ~= true then
			return false, "INVALID_GEM_STATE"
		end
	end
	return true, nil
end

local function state(data: any): any
	Rules.Migrate(data)
	return data.Economy.GemState
end

function Rules.Balance(data: any): number
	local value = type(data) == "table" and type(data.Economy) == "table" and data.Economy.Gems
	return if type(value) == "number" then value else 0
end

local function entitled(data: any, key: string): boolean
	return type(data.Commerce) == "table"
		and type(data.Commerce.Entitlements) == "table"
		and data.Commerce.Entitlements[key] == true
end
Rules.HasEntitlement = entitled

-- Credits Gems. `free` grants receive the VIP bonus; paid packs never do.
function Rules.Grant(data: any, amount: number, free: boolean): number
	if not integer(amount, 0, Economy.MaxGems) or amount == 0 then
		return 0
	end
	local s = state(data)
	if free and entitled(data, "VIP") then
		amount += math.ceil(amount * Sources.VipBonusFraction)
	end
	local room = Economy.MaxGems - data.Economy.Gems
	local granted = math.min(amount, room)
	data.Economy.Gems += granted
	s.Lifetime = math.min(Money.MAX_AMOUNT, s.Lifetime + granted)
	return granted
end

function Rules.CanSpend(data: any, amount: number): (boolean, string?)
	if not integer(amount, 1, Economy.MaxGems) then
		return false, "INVALID_GEM_PRICE"
	end
	if Rules.Balance(data) < amount then
		return false, "INSUFFICIENT_GEMS"
	end
	return true, nil
end

function Rules.Spend(data: any, amount: number): (boolean, string?)
	local ok, reason = Rules.CanSpend(data, amount)
	if not ok then
		return false, reason
	end
	state(data)
	data.Economy.Gems -= amount
	return true, nil
end

-- Income -----------------------------------------------------------------

function Rules.RebirthCount(data: any): number
	local p = type(data) == "table" and data.Phase13
	local n = if type(p) == "table" then p.RebirthCount else 0
	return if integer(n, 0, Money.MAX_AMOUNT) then n else 0
end

-- Breakdown used by income, rebirth quotes and the HUD.
function Rules.IncomeBreakdown(data: any, at: number?): any
	local now = at or os.time()
	local rebirthBonus = Rules.RebirthCount(data) * Economy.Income.RebirthBonusPerRebirth
	local vipBonus = if entitled(data, "VIP") then Economy.Income.VipBonus else 0
	local pass = if entitled(data, "INCOME_2X") then Economy.Income.Income2xPass else 1
	local s = type(data) == "table" and type(data.Economy) == "table" and data.Economy.GemState
	local boostUntil = if type(s) == "table" and finite(s.CashBoostUntil) then s.CashBoostUntil else 0
	local boostActive = boostUntil > now
	local permanent = (1 + rebirthBonus + vipBonus) * pass
	return {
		rebirthBonus = rebirthBonus,
		vipBonus = vipBonus,
		pass = pass,
		boost = if boostActive then Economy.Income.CashBoost else 1,
		boostRemaining = if boostActive then boostUntil - now else 0,
		permanent = permanent,
		total = permanent * (if boostActive then Economy.Income.CashBoost else 1),
	}
end

function Rules.IncomeMultiplier(data: any, at: number?): number
	if type(data) ~= "table" then
		return 1
	end
	return Rules.IncomeBreakdown(data, at).total
end

local function mutationMultiplier(id: any): number
	if id == nil or id == "None" or id == "Normal" then
		return 1
	end
	if id == "Celestial" then
		id = "Astral"
	end
	local row = MutationCatalog.ById[id]
	return if row then row.multiplier else 1
end

-- Base (unmultiplied) production of the brainrots currently on usable platforms.
function Rules.BaseCps(data: any): number
	local p = data.Phase13
	local level = if type(p) == "table" and integer(p.ExpansionLevel, 0, 6) then p.ExpansionLevel else 0
	local capacity = 12 + 6 * level
	local owned = data.Collection and data.Collection.BrainrotInstances or {}
	local slots = data.Base and data.Base.Slots or {}
	local total = 0
	for index = 1, capacity do
		local slot = slots[tostring(index)]
		local record = slot and slot.brainrotId and owned[slot.brainrotId]
		local definition = record and Catalog.Get(record.speciesId)
		if definition then
			total += definition.cashPerSecond * mutationMultiplier(record.mutationId)
		end
	end
	return total
end

-- Free Gem sources --------------------------------------------------------

local function liveDiscoveries(data: any): number
	local count, seen = 0, {}
	for id, proof in (data.Collection or {}).Species or {} do
		local definition = Catalog.Get(id)
		if proof and definition and definition.launchStatus == "Live" and not seen[definition.id] then
			seen[definition.id] = true
			count += 1
		end
	end
	return count
end

local function normalizedMutation(id: any): string?
	if id == nil or id == "None" or id == "Normal" then
		return nil
	end
	return if id == "Celestial" then "Astral" else id
end

-- Called inside the first-bank mutation, after Collection.Species was recorded.
function Rules.OnFirstBank(data: any, receipt: any): any
	local definition = Catalog.Get(receipt.speciesId)
	if not definition or type(receipt.firstBankedAt) ~= "number" then
		return { total = 0, parts = {} }
	end
	local s = state(data)
	local parts = {}
	local total = 0
	local function add(source: string, amount: number?)
		if amount and amount > 0 then
			local granted = Rules.Grant(data, amount, true)
			if granted > 0 then
				total += granted
				table.insert(parts, { source = source, amount = granted })
			end
		end
	end
	if receipt.firstSpecies and definition.launchStatus == "Live" then
		add("Discovery", Sources.Discovery[definition.tier])
	end
	local milestones = math.floor(liveDiscoveries(data) / Sources.IndexMilestoneEvery)
	while s.IndexPaid < milestones do
		s.IndexPaid += 1
		add("IndexMilestone", Sources.IndexMilestone)
	end
	local mutation = normalizedMutation(receipt.mutationId)
	if mutation and Sources.FirstMutation[mutation] and not s.Mutations[mutation] then
		s.Mutations[mutation] = true
		add("FirstMutation", Sources.FirstMutation[mutation])
	end
	local dayKey = math.floor(receipt.firstBankedAt / DAY)
	if s.Day.key ~= dayKey then
		s.Day = { key = dayKey, tiers = {} }
	end
	local tierReward = Sources.DailyFirstTier[definition.tier]
	if tierReward and not s.Day.tiers[definition.tier] then
		s.Day.tiers[definition.tier] = true
		add("DailyFirstTier", tierReward)
	end
	return { total = total, parts = parts }
end

function Rules.OnQuestComplete(data: any): number
	return Rules.Grant(data, Sources.DailyQuest, true)
end

function Rules.OnDailyGift(data: any, cyclePosition: number): number
	local base = Sources.DailyGiftByCycleDay[cyclePosition] or Sources.DailyGiftByCycleDay[1]
	if entitled(data, "VIP") then
		base += Sources.VipDailyGiftBonus
	end
	return Rules.Grant(data, base, true)
end

function Rules.OnRebirth(data: any, prestige: boolean): number
	if prestige then
		local s = state(data)
		s.Prestige = math.min(Economy.Prestige.MaxCount, s.Prestige + 1)
	end
	return Rules.Grant(data, if prestige then Sources.Prestige else Sources.Rebirth, true)
end

-- Prestige -----------------------------------------------------------------

local function threeSignificant(value: number): number
	if value <= 0 then
		return 0
	end
	local scale = 10 ^ (math.floor(math.log10(value)) - 2)
	return math.floor(value / scale + 0.5) * scale
end

function Rules.PrestigeCount(data: any): number
	local s = type(data.Economy) == "table" and data.Economy.GemState
	return if type(s) == "table" and integer(s.Prestige, 0, Economy.Prestige.MaxCount) then s.Prestige else 0
end

function Rules.PrestigePrice(data: any): number?
	local count = Rules.PrestigeCount(data)
	if count >= Economy.Prestige.MaxCount then
		return nil
	end
	local price = threeSignificant(Economy.Prestige.BasePrice * Economy.Prestige.Growth ^ count)
	return if price <= Money.MAX_AMOUNT then price else nil
end

-- Gem shop -----------------------------------------------------------------

function Rules.CrateCash(data: any, item: any): number
	local perSecond = Rules.BaseCps(data) * Rules.IncomeBreakdown(data).permanent
	local amount = math.floor(perSecond * item.minutes * 60)
	return math.max(item.floorCash, math.min(amount, Money.MAX_AMOUNT))
end

function Rules.ApplyShopItem(data: any, itemId: any, at: number): (boolean, any)
	local item = type(itemId) == "string" and Economy.GemShopById[itemId]
	if not item then
		return false, { code = "UNKNOWN_ITEM" }
	end
	if not finite(at) then
		return false, { code = "INVALID_TIME" }
	end
	local canSpend, reason = Rules.CanSpend(data, item.priceGems)
	if not canSpend then
		return false, { code = reason }
	end
	local s = state(data)
	local result: any = { kind = item.kind, itemId = item.id, priceGems = item.priceGems }
	if item.kind == "CashBoost" then
		local start = math.max(s.CashBoostUntil, at)
		local limit = at + Economy.Income.CashBoostMaxSeconds
		if start + item.seconds > limit then
			return false, { code = "BOOST_FULL" }
		end
		s.CashBoostUntil = start + item.seconds
		result.boostUntil = s.CashBoostUntil
		result.seconds = item.seconds
	elseif item.kind == "CashCrate" then
		local cash = Rules.CrateCash(data, item)
		if not Money.Validate(data.Economy.Balance) or data.Economy.Balance > Money.MAX_AMOUNT - cash then
			return false, { code = "BALANCE_LIMIT" }
		end
		data.Economy.Balance += cash
		result.amountCash = cash
		result.balance = data.Economy.Balance
	elseif item.kind == "MutationStorm" then
		-- The server applies the shared effect after this purchase is durably saved.
		result.seconds = item.seconds
	elseif item.kind == "Weapon" then
		-- Premium special weapon (Camp Rework). Permanent ownership in the Phase13 profile.
		if not CampFlags.CampRework() then
			return false, { code = "UNAVAILABLE" }
		end
		local p = data.Phase13
		if type(p) ~= "table" or type(p.OwnedWeaponIds) ~= "table" then
			return false, { code = "PROFILE_NOT_READY" }
		end
		if p.OwnedWeaponIds[item.weaponId] == true then
			return false, { code = "ALREADY_OWNED" }
		end
		p.OwnedWeaponIds[item.weaponId] = true
		result.weaponId = item.weaponId
	else
		return false, { code = "UNKNOWN_ITEM" }
	end
	data.Economy.Gems -= item.priceGems
	result.gems = data.Economy.Gems
	return true, result
end

-- Server-wide Mutation Storm chance for new spawns.
function Rules.MutationChance(baseChance: number, stormUntil: any, at: number): number
	if type(stormUntil) == "number" and stormUntil > at then
		return math.min(Economy.MutationStorm.MaxChance, baseChance * Economy.MutationStorm.ChanceMultiplier)
	end
	return baseChance
end

-- Read-only client snapshot.
function Rules.Snapshot(data: any, at: number?): any
	local now = at or os.time()
	local breakdown = Rules.IncomeBreakdown(data, now)
	local shop = {}
	local campRework = CampFlags.CampRework()
	for _, item in Economy.GemShop do
		if item.kind == "Weapon" and not campRework then
			continue
		end
		local owned = item.kind == "Weapon"
			and type(data) == "table"
			and type(data.Phase13) == "table"
			and type(data.Phase13.OwnedWeaponIds) == "table"
			and data.Phase13.OwnedWeaponIds[item.weaponId] == true
		table.insert(shop, {
			id = item.id,
			kind = item.kind,
			name = item.name,
			description = item.description,
			priceGems = item.priceGems,
			seconds = item.seconds,
			cash = if item.kind == "CashCrate" then Rules.CrateCash(data, item) else nil,
			affordable = Rules.Balance(data) >= item.priceGems,
			order = item.order,
			weaponId = item.weaponId,
			owned = owned or nil,
		})
	end
	return {
		version = Economy.Version,
		gems = Rules.Balance(data),
		income = breakdown,
		baseCps = Rules.BaseCps(data),
		rebirths = Rules.RebirthCount(data),
		prestige = { count = Rules.PrestigeCount(data), price = Rules.PrestigePrice(data) },
		shop = shop,
		names = Economy.Currencies,
	}
end

return table.freeze(Rules)
