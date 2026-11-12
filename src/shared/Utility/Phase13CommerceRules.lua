--!strict
-- Paid receipt identities are permanent; the bounded operation journal is separate.
local Rules = {}
local Money = require(script.Parent.CurrencyDenomination)
local AttachmentCosmetics = require(script.Parent.Phase14CosmeticRules)
local GemRules = require(script.Parent.GemRules)
local Economy = require(script.Parent.Parent.Config.Economy)
-- Paid receipt currencies. Absent means Cash (every pre-P15 receipt).
local receiptCurrencies = { Cash = true, Gems = true, MutationStorm = true }
local keys = { INCOME_2X = true, AUTO_COLLECT = true, VIP = true, STARTER_PACK = true }
-- Camp Rework passes (IDs pending; delivery disabled): a special weapon and 2x Training. Optional in
-- saved profiles (absent = not owned), so existing profiles stay valid without a migration.
local optionalPassKeys = { WPN_SP_RIFTBLASTER = true, TRAINING_2X = true }
-- Passes that grant permanent weapon ownership in the Phase13 profile.
local weaponPasses = { WPN_SP_RIFTBLASTER = "WPN_SP_RIFTBLASTER" }
-- Optional ownership uses the existing durable entitlement dictionary. Absent means unowned.
-- GrantPass accepts only the real pass keys above; palettes never grant ownership.
local cosmeticKeys = { FIN_PRISM = true, FIN_GLACIER = true, FIN_AURORA = true, FIN_SINGULARITY = true,
	P14_FLAG_CAMP = true, P14_BASE_EXPEDITION = true, P14_FLAG_FOREST = true,
	P14_BASE_FOREST = true, P14_FLAG_RIFT = true, P14_BASE_RIFT = true }
-- Client presentation only. Server grants never trust this displayed price.
function Rules.DisplayPrice(offer: any, info: any): number?
	if
		type(offer) ~= "table"
		or offer.enabled ~= true
		or type(offer.platformId) ~= "number"
		or offer.platformId <= 0
		or offer.platformId % 1 ~= 0
		or type(info) ~= "table"
		or info.IsForSale == false
	then
		return nil
	end
	local returned = if offer.platformKind == "Product"
		then info.ProductId
		elseif offer.platformKind == "GamePass" then info.AssetId
		else nil
	local price = info.PriceInRobux
	if
		returned ~= offer.platformId
		or type(price) ~= "number"
		or price ~= price
		or price < 0
		or price == math.huge
		or price % 1 ~= 0
	then
		return nil
	end
	return price
end
function Rules.Migrate(data: any): (boolean, string?)
	if data.Commerce ~= nil then
		return Rules.Validate(data)
	end
	data.Commerce = {
		Version = 1,
		Entitlements = { INCOME_2X = false, AUTO_COLLECT = false, VIP = false, STARTER_PACK = false },
		ConfirmedAt = {},
		StarterPackClaimed = false,
		ProcessedReceipts = {},
		ReceiptCount = 0,
		Appearance = {},
	}
	return true, nil
end
function Rules.Validate(data: any): (boolean, string?)
	local c = data.Commerce
	if type(c) ~= "table" or c.Version ~= 1 then
		return false, "UNSUPPORTED_COMMERCE_VERSION"
	end
	if
		type(c.Entitlements) ~= "table"
		or type(c.ConfirmedAt) ~= "table"
		or type(c.ProcessedReceipts) ~= "table"
		or type(c.StarterPackClaimed) ~= "boolean"
	then
		return false, "INVALID_COMMERCE"
	end
	for key, value in c.Entitlements do
		if (not keys[key] and not cosmeticKeys[key] and not optionalPassKeys[key]) or type(value) ~= "boolean" then
			return false, "INVALID_ENTITLEMENT"
		end
	end
	for key in keys do
		if type(c.Entitlements[key]) ~= "boolean" then
			return false, "MISSING_ENTITLEMENT"
		end
	end
	if type(c.Appearance) ~= "table" then
		return false, "INVALID_APPEARANCE"
	end
	local validAttachments, attachmentReason = AttachmentCosmetics.ValidateAppearance(data)
	if not validAttachments then return false, attachmentReason end
	local count = 0
	for id, r in c.ProcessedReceipts do
		if
			type(id) ~= "string"
			or #id < 1
			or #id > 200
			or id:find("%c")
			or type(r) ~= "table"
			or type(r.ProductId) ~= "number"
			or r.ProductId % 1 ~= 0
			or r.ProductId <= 0
			or not Money.Validate(r.Amount)
			or r.Amount <= 0
			or r.Amount % 1 ~= 0
			or type(r.GrantedAt) ~= "number"
			or r.GrantedAt ~= r.GrantedAt
			or math.abs(r.GrantedAt) == math.huge
			or type(r.ConfigVersion) ~= "string"
			or (r.Currency ~= nil and not receiptCurrencies[r.Currency])
		then
			return false, "INVALID_PAID_RECEIPT"
		end
		count += 1
	end
	if c.ReceiptCount ~= count or count > 10000 then
		return false, "PAID_LEDGER_REQUIRES_ARCHIVAL"
	end
	return true, nil
end
function Rules.HasEntitlement(data: any, key: string): boolean
	return type(data) == "table" and type(data.Commerce) == "table" and data.Commerce.Entitlements[key] == true
end
-- P15: base × (1 + rebirths + VIP) × 2× pass × Cash Boost. GemRules owns the formula.
function Rules.ProductionMultiplier(data: any, at: number?): number
	return GemRules.IncomeMultiplier(data, at)
end
function Rules.GrantPass(data: any, key: string, at: number): (boolean, any)
	if not keys[key] and not optionalPassKeys[key] then
		return false, { code = "UNKNOWN_PASS" }
	end
	local c = data.Commerce
	if not c then
		return false, { code = "PROFILE_NOT_READY" }
	end
	local cash = 0
	if key == "STARTER_PACK" and not c.StarterPackClaimed then
		cash = Economy.StarterPack.Cash
	end
	if not Money.Validate(data.Economy.Balance) or data.Economy.Balance > Money.MAX_AMOUNT - cash then
		return false, { code = "BALANCE_LIMIT" }
	end
	if type(at) ~= "number" or at ~= at or math.abs(at) == math.huge then
		return false, { code = "INVALID_TIME" }
	end
	c.Entitlements[key] = true
	c.ConfirmedAt[key] = at
	local weaponId = weaponPasses[key]
	if weaponId and type(data.Phase13) == "table" and type(data.Phase13.OwnedWeaponIds) == "table" then
		data.Phase13.OwnedWeaponIds[weaponId] = true
	end
	local gems = 0
	if key == "STARTER_PACK" and not c.StarterPackClaimed then
		cash = Economy.StarterPack.Cash
		c.StarterPackClaimed = true
		data.Economy.Balance += cash
		gems = GemRules.Grant(data, Economy.StarterPack.Gems, false)
	end
	return true, { key = key, amount = cash, gems = gems, balance = data.Economy.Balance }
end
-- Only a backend-confirmed, acknowledged paid operation may lose this redundant
-- diagnostic. Identity, amount, cutover, sequence and permanent paid ledger survive.
function Rules.CompactPaidDiagnostics(data: any, savedRevision: number): number
	local phase = data.Phase13
	if type(phase) ~= "table" or type(phase.Operations) ~= "table" then
		return 0
	end
	local count = 0
	for _, operation in phase.Operations do
		if
			operation.Kind == "PaidCash"
			and type(operation.Sequence) == "number"
			and operation.Sequence <= (phase.AcknowledgedOperationSequence or 0)
			and type(operation.CommitRevision) == "number"
			and operation.CommitRevision <= savedRevision
			and type(operation.Result) == "table"
			and operation.Result.balance ~= nil
		then
			operation.Result.balance = nil
			count += 1
		end
	end
	return count
end
function Rules.GrantReceipt(
	data: any,
	purchaseId: string,
	productId: number,
	amount: number,
	at: number,
	version: string,
	currency: string?
): (boolean, any)
	local kind = currency or "Cash"
	if not receiptCurrencies[kind] then
		return false, { code = "UNKNOWN_PRODUCT" }
	end
	local c = data.Commerce
	if not c then
		return false, { code = "PROFILE_NOT_READY" }
	end
	local prior = c.ProcessedReceipts[purchaseId]
	if prior then
		if prior.ProductId ~= productId or prior.Amount ~= amount or (prior.Currency or "Cash") ~= kind then
			return false, { code = "RECEIPT_ID_MISMATCH" }
		end
		return false, { code = "ALREADY_GRANTED" }
	end
	if c.ReceiptCount >= 10000 then
		return false, { code = "PAID_LEDGER_REQUIRES_ARCHIVAL" }
	end
	if
		not Money.Validate(amount)
		or amount <= 0
		or amount % 1 ~= 0
		or (kind == "Cash" and (not Money.Validate(data.Economy.Balance) or data.Economy.Balance > Money.MAX_AMOUNT - amount))
		or (kind == "Gems" and GemRules.Balance(data) > Economy.MaxGems - amount)
	then
		return false, { code = "BALANCE_LIMIT" }
	end
	if
		type(purchaseId) ~= "string"
		or #purchaseId < 1
		or #purchaseId > 200
		or purchaseId:find("%c")
		or type(productId) ~= "number"
		or productId <= 0
		or productId % 1 ~= 0
		or type(at) ~= "number"
		or at ~= at
		or math.abs(at) == math.huge
		or type(version) ~= "string"
		or #version > 64
	then
		return false, { code = "INVALID_RECEIPT" }
	end
	-- The server dispatcher measures the complete projected Transport3 envelope before this transition.
	c.ProcessedReceipts[purchaseId] = {
		ProductId = productId,
		Amount = amount,
		GrantedAt = at,
		ConfigVersion = version,
		Currency = if kind == "Cash" then nil else kind,
	}
	c.ReceiptCount += 1
	if kind == "Cash" then
		data.Economy.Balance += amount
	elseif kind == "Gems" then
		GemRules.Grant(data, amount, false)
	end
	-- MutationStorm: the durable receipt is the whole profile change; the server
	-- applies the shared effect once this receipt's covering save confirms.
	data.Phase13.EligibilityRevision += 1
	return true,
		{
			productId = productId,
			amount = amount,
			currency = kind,
			balance = data.Economy.Balance,
			gems = GemRules.Balance(data),
		}
end
return table.freeze(Rules)
