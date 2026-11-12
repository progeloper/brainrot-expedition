--!strict
-- References current progression definitions. No separate prices, purchase path or ETA.
local Config = require(script.Parent.Parent.Config.Phase13)
local World = require(script.Parent.Parent.Config.WorldProgression)
local Weapons = require(script.Parent.Parent.Config.Weapons)
local Progression = require(script.Parent.Phase13Rules)
local WorldRules = require(script.Parent.WorldProgressionRules)
local Training = require(script.Parent.Parent.Config.Training)
local CampFlags = require(script.Parent.Parent.Config.CampReworkFlags)
local Goals = {}
local legacy = {}
for level in Config.SpeedPrices do
	legacy["CART_SPEED_" .. tostring(level)] = "Speed:" .. tostring(level)
end
for level in Config.CargoPrices do
	legacy["CARGO_" .. tostring(level)] = "Cargo:" .. tostring(level)
end
function Goals.Resolve(data, rawId)
	if type(rawId) ~= "string" or #rawId > 128 then
		return nil
	end
	local id = legacy[rawId] or rawId
	local parts = string.split(id, ":")
	local kind, key, route = parts[1], parts[2], parts[3]
	local wallet, p = data.Economy.Balance, data.Phase13
	if not p then
		return nil
	end
	local row = { id = rawId, referenceId = id, kind = kind, balance = wallet, currency = "Cash", completed = false }
	if kind == "Region" and #parts == 2 then
		local definition = World.ByKey[key]
		if not definition or definition.index <= 1 then
			return nil
		end
		local result = WorldRules.Evaluate(
			data,
			key,
			{ ready = true, writable = true, currencyConfirmed = true, operational = true }
		)
		row.name, row.price = definition.displayName, definition.price
		row.completed = data.WorldProgression.PersonalUnlocks[key] ~= nil
		row.prerequisites = {
			previousRegion = definition.predecessor,
			banking = result.bankingSatisfied,
			branchA = result.branchA,
			branchB = result.branchB,
			code = result.code,
		}
	elseif (kind == "Speed" or kind == "Cargo" or kind == "Equipped") and #parts == 2 then
		local level = tonumber(key)
		if not level or level % 1 ~= 0 then
			return nil
		end
		local prices = if kind == "Speed"
			then Config.SpeedPrices
			elseif kind == "Cargo" then Config.CargoPrices
			else Config.EquippedPrices
		if not prices[level] then
			return nil
		end
		local current = if kind == "Speed"
			then p.SpeedLevel
			elseif kind == "Cargo" then p.CargoLevel
			else 2 + data.ChariotTeam.PurchasedExtraSlots
		row.name, row.price =
			(if kind == "Equipped" then "Equipped slots " else kind .. " ") .. tostring(level), prices[level]
		row.completed, row.prerequisites =
			current >= level, { previousLevel = level - 1, currentLevel = current, satisfied = current >= level - 1 }
	elseif kind == "Roller" and #parts == 2 then
		-- Camp Rework Training: rollers replace the Speed goals.
		local roller = Training.RollersById[key]
		if not roller or roller.price <= 0 then
			return nil
		end
		local owned = type(p.OwnedRollers) == "table" and p.OwnedRollers[key] == true
		row.name, row.price, row.completed = roller.name, roller.price, owned
		row.prerequisites = {}
	elseif kind == "Weapon" and #parts == 2 then
		local definition = Weapons.Get(key)
		if not definition then
			return nil
		end
		row.name, row.price, row.completed = definition.displayName, definition.price, p.OwnedWeaponIds[key] == true
		row.prerequisites = {}
	elseif kind == "Cart" and #parts == 2 then
		local definition = Progression.Cart(key)
		if not definition then
			return nil
		end
		row.name, row.price, row.completed = definition.displayName, definition.price, p.OwnedCartIds[key] == true
		row.prerequisites = {}
	elseif kind == "Rebirth" and (#parts == 2 or #parts == 3) then
		route = route or "Cash"
		if route ~= "Cash" and route ~= "Collection" then
			return nil
		end
		local definition, rewardKind = Progression.FindReward(key)
		if not definition then
			return nil
		end
		local quote = Progression.QuoteRebirth(data, key, route)
		row.name = if rewardKind == "Expansion"
			then tostring(definition.capacity) .. " base slots"
			else definition.displayName
		row.price, row.route = definition.price, route
		row.completed = if rewardKind == "Expansion"
			then p.ExpansionLevel >= definition.level
			else p.OwnedBaseDesigns[key] == true
		row.balance = Progression.Cash(data)
		row.cashSacrificeAll = route == "Cash"
		row.warning = if route == "Cash"
			then "Sacrifices ALL CASH: wallet and settled platform earnings."
			else "Sacrifices ALL owned brainrots. Cash is preserved."
		row.prerequisites = {
			code = quote.code,
			capacity = quote.capacity,
			full = quote.full,
			ownedCount = quote.ownedCount,
			qualifyingIndividuals = quote.qualifyingIndividuals,
			requiredIndividuals = quote.requiredIndividuals or definition.required,
			minimumRarity = quote.minimumRarity or definition.minimumRarity,
		}
		if route == "Collection" then
			row.currency, row.balance, row.price =
				"Owned qualifying brainrots", quote.qualifyingIndividuals or 0, definition.required
		end
	else
		return nil
	end
	row.shortfall = math.max(0, row.price - (row.balance or 0))
	return row
end
function Goals.Options(data)
	local ids, p = {}, data.Phase13
	for _, definition in World.Ordered do
		if definition.index > 1 and not data.WorldProgression.PersonalUnlocks[definition.key] then
			table.insert(ids, "Region:" .. definition.key)
			break
		end
	end
	if CampFlags.Training() then
		for _, roller in Training.Rollers do
			if roller.price > 0 and not (type(p.OwnedRollers) == "table" and p.OwnedRollers[roller.id] == true) then
				table.insert(ids, "Roller:" .. roller.id)
				break
			end
		end
	elseif p.SpeedLevel < Config.MaxSpeedLevel then
		table.insert(ids, "Speed:" .. tostring(p.SpeedLevel + 1))
	end
	if p.CargoLevel < Config.MaxCargoLevel then
		table.insert(ids, "Cargo:" .. tostring(p.CargoLevel + 1))
	end
	local equipped = 2 + data.ChariotTeam.PurchasedExtraSlots
	if equipped < 6 then
		table.insert(ids, "Equipped:" .. tostring(equipped + 1))
	end
	local expansion = Config.ExpansionRows[p.ExpansionLevel + 1]
	if expansion then
		table.insert(ids, "Rebirth:" .. expansion.id .. ":Cash")
		table.insert(ids, "Rebirth:" .. expansion.id .. ":Collection")
	end
	for _, definition in Config.CartRows do
		if not p.OwnedCartIds[definition.id] then
			table.insert(ids, "Cart:" .. definition.id)
		end
	end
	local rows = {}
	for _, id in ids do
		table.insert(rows, Goals.Resolve(data, id))
	end
	return rows
end
function Goals.Pin(data, value)
	if value ~= "None" and not Goals.Resolve(data, value) then
		return false, { code = "INVALID_GOAL" }
	end
	local id = if value == "None" then nil else value
	if data.Progression.TrackedUpgradeId == id then
		return false, { ok = true, code = "UNCHANGED" }
	end
	data.Progression.TrackedUpgradeId, data.Retention.Revision = id, data.Retention.Revision + 1
	return true, { ok = true, code = "GOAL_CHANGED", goalId = id or "None" }
end
return table.freeze(Goals)
