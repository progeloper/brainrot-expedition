--!strict
-- Account cosmetics reuse the existing wallet, critical writer and permanent ownership.
-- Existing Commerce.Entitlements/Appearance and the Phase13 critical writer own persistence.
local Carts = require(script.Parent.Parent.Config.Phase13).CartRows
local Money = require(script.Parent.CurrencyDenomination)
local GemRules = require(script.Parent.GemRules)
local GemPrices = require(script.Parent.Parent.Config.Economy).GemCosmetics
local Rules = {}
Rules.Version = "P14_COSMETICS_V2"
Rules.Slots = table.freeze({ "Flag", "BaseBanner", "Trail" })
local slotSet = { Flag = true, BaseBanner = true, Trail = true }
local rows = {
	{
		id = "P14_FLAG_CAMP",
		name = "Camp Regular",
		slot = "Flag",
		acquisition = "Supply",
		lifetimeClaim = 7,
	},
	{
		id = "P14_BASE_EXPEDITION",
		name = "Expedition Crest",
		slot = "BaseBanner",
		acquisition = "Supply",
		lifetimeClaim = 14,
	},
	{
		id = "P14_FLAG_FOREST",
		name = "Forest Standard",
		slot = "Flag",
		acquisition = "Cash",
		priceCash = 500000000,
	},
	{
		id = "P14_BASE_FOREST",
		name = "Forest Hall",
		slot = "BaseBanner",
		acquisition = "Cash",
		priceCash = 2500000000,
	},
	{
		id = "P14_FLAG_RIFT",
		name = "Rift Pennant",
		slot = "Flag",
		acquisition = "Gems", -- P15: sold for Gems (Economy.GemCosmetics)
		priceGems = GemPrices.P14_FLAG_RIFT,
	},
	{
		id = "P14_BASE_RIFT",
		name = "Rift Twin Standard",
		slot = "BaseBanner",
		acquisition = "Gems", -- P15: sold for Gems (Economy.GemCosmetics)
		priceGems = GemPrices.P14_BASE_RIFT,
	},
	{
		id = "P14_TRAIL_STARFORGE",
		name = "Starforge Ribbon",
		slot = "Trail",
		acquisition = "Included",
		requiredCartId = "CRT_007",
		requiredCartName = "Starforge Chariot",
	},
	{
		id = "P14_TRAIL_COMET",
		name = "Comet Wake",
		slot = "Trail",
		acquisition = "Included",
		requiredCartId = "CRT_010",
		requiredCartName = "Comet Skimmer",
	},
	{
		id = "P14_TRAIL_OBSIDIAN",
		name = "Obsidian Ember",
		slot = "Trail",
		acquisition = "Included",
		requiredCartId = "CRT_013",
		requiredCartName = "Obsidian Fortress",
	},
}
local byId = {}
for _, row in rows do
	-- Exact approved native CSG assets and bounded mount adapters are source-mapped.
	row.presentationReady = true
	row.gameplayStats = false
	if row.requiredCartId then
		local count = 0
		for _, cart in Carts do
			if cart.id == row.requiredCartId and cart.displayName == row.requiredCartName then
				count += 1
			end
		end
		assert(count == 1, "Phase14 included trail requires an unambiguous current cart mapping")
	end
	byId[row.id] = table.freeze(row)
end
Rules.Catalog = table.freeze(rows)
function Rules.IsSlot(slot: any): boolean
	return slotSet[slot] == true
end
function Rules.Get(id: any): any?
	return if type(id) == "string" then byId[id] else nil
end
function Rules.Owns(data: any, id: any): boolean
	local row = Rules.Get(id)
	if not row or type(data) ~= "table" then
		return false
	end
	if row.acquisition == "Included" then
		return type(data.Phase13) == "table"
			and type(data.Phase13.OwnedCartIds) == "table"
			and data.Phase13.OwnedCartIds[row.requiredCartId] == true
	end
	return type(data.Commerce) == "table"
		and type(data.Commerce.Entitlements) == "table"
		and data.Commerce.Entitlements[row.id] == true
end
function Rules.ValidateAppearance(data: any): (boolean, string?)
	local appearance = data.Commerce and data.Commerce.Appearance
	if type(appearance) ~= "table" then
		return false, "INVALID_APPEARANCE"
	end
	for _, slot in Rules.Slots do
		local id = appearance[slot]
		local row = Rules.Get(id)
		if id ~= nil and id ~= "None" and (not row or row.slot ~= slot) then
			return false, "INVALID_ATTACHMENT_SELECTION"
		end
	end
	-- Never erase or reject a previously valid saved selection on an asset/API failure.
	-- Ownership is checked again for every new selection through the existing writer.
	return true, nil
end
function Rules.Selected(data: any, slot: any): string
	local appearance = type(data) == "table" and data.Commerce and data.Commerce.Appearance
	local id = type(appearance) == "table" and appearance[slot]
	local row = Rules.Get(id)
	return if row and row.slot == slot then id else "None"
end
function Rules.CanSelect(data: any, slot: any, id: any): (boolean, string?)
	if not Rules.IsSlot(slot) or type(id) ~= "string" then
		return false, "INVALID_SELECTION"
	end
	if type(data) ~= "table" or type(data.Commerce) ~= "table" then
		return false, "PROFILE_NOT_READY"
	end
	if id == "None" then
		return true, nil
	end
	local row = Rules.Get(id)
	if not row or row.slot ~= slot then
		return false, "INVALID_SELECTION"
	end
	if not Rules.Owns(data, id) then
		return false, "NOT_OWNED"
	end
	if row.presentationReady ~= true then
		return false, "PRESENTATION_UNAVAILABLE"
	end
	return true, nil
end
local function acquisitionText(row, owned)
	if row.acquisition == "Included" then
		return (if owned then "Included with " else "Own ") .. row.requiredCartName
	elseif row.acquisition == "Supply" then
		return "Lifetime supply claim " .. tostring(row.lifetimeClaim)
	elseif row.acquisition == "Cash" then
		return "Fixed Cash cosmetic · appearance only"
	elseif row.acquisition == "Gems" then
		return "Gem cosmetic · appearance only"
	end
	return "Unavailable"
end
function Rules.Snapshot(data: any): any
	local result = {
		version = Rules.Version,
		available = type(data) == "table" and type(data.Commerce) == "table",
		slots = {},
	}
	for _, slot in Rules.Slots do
		result.slots[slot] = { selected = Rules.Selected(data, slot), rows = {} }
	end
	for _, row in Rules.Catalog do
		local item = table.clone(row)
		item.owned = Rules.Owns(data, row.id)
		item.selected = result.slots[row.slot].selected == row.id
		item.availableForSelection = item.owned and row.presentationReady == true
		item.availabilityReason = if not item.owned then "NOT_OWNED" elseif not row.presentationReady then "PRESENTATION_UNAVAILABLE" else nil
		item.availableForPurchase = (row.acquisition == "Cash" or row.acquisition == "Gems")
			and not item.owned
			and row.presentationReady == true
		item.acquisitionText = acquisitionText(row, item.owned)
		table.insert(result.slots[row.slot].rows, item)
	end
	return result
end
-- Called only inside the existing Phase13 critical writer. Never equips on purchase.
function Rules.CanPurchase(data: any, id: any): (boolean, string?)
 local row = Rules.Get(id)
 if not row or (row.acquisition ~= "Cash" and row.acquisition ~= "Gems") then return false, "INVALID_COSMETIC_PURCHASE" end
 if not row.presentationReady then return false, "PRESENTATION_UNAVAILABLE" end
 if type(data) ~= "table" or type(data.Economy) ~= "table" or type(data.Commerce) ~= "table" or type(data.Commerce.Entitlements) ~= "table" then return false, "PROFILE_NOT_READY" end
 if Rules.Owns(data, id) then return false, "ALREADY_OWNED" end
 if row.acquisition == "Gems" then
  return GemRules.CanSpend(data, row.priceGems)
 end
 local cash = data.Economy.Balance
 if not Money.Validate(cash) then return false, "INVALID_CASH" end
 if cash < row.priceCash then return false, "INSUFFICIENT_CASH" end
 return true, nil
end
function Rules.ApplyPurchase(data: any, id: any): (boolean, any)
 local ok, reason = Rules.CanPurchase(data, id)
 if not ok then return false, {code=reason} end
 local row = byId[id]
 if row.acquisition == "Gems" then
  GemRules.Spend(data, row.priceGems)
 else
  data.Economy.Balance -= row.priceCash
 end
 data.Commerce.Entitlements[id] = true
 return true, {category="Cosmetic", id=id, priceCash=row.priceCash, priceGems=row.priceGems, slot=row.slot, selected=false}
end
return table.freeze(Rules)
