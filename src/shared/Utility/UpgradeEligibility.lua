--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)

local Eligibility = {}

local function finiteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and math.abs(value) < math.huge
end

local function reason(code: string, message: string, kind: string): any
	return table.freeze({ code = code, message = message, kind = kind })
end

local function result(outcome: string, reasons: { any }, extra: any?): any
	local value = extra or {}
	value.outcome = outcome
	value.reasons = table.freeze(reasons)
	value.primaryReason = reasons[1]
	value.canPurchase = outcome == "Available"
	return table.freeze(value)
end

function Eligibility.ResolveOwnership(offer: any, playerSnapshot: any, targetContext: any?): any
	if type(offer) ~= "table" or type(playerSnapshot) ~= "table" then
		return table.freeze({ ok = false, owned = false, code = "INVALID_OWNERSHIP_INPUT" })
	end
	local scope = offer.ownershipScope
	local kind = if type(scope) == "table" then scope.kind else nil
	if kind == "PendingDecision" then
		return table.freeze({ ok = false, owned = false, code = "OWNERSHIP_SCOPE_PENDING" })
	elseif kind == "PlayerWide" then
		local owned = type(playerSnapshot.ownedOfferIds) == "table" and playerSnapshot.ownedOfferIds[offer.id] == true
		local track = offer.grant and offer.grant.trackId
		local p = playerSnapshot.phase13
		local level = if type(p) == "table"
			then (if track == "CartSpeed" then p.SpeedLevel elseif track == "Cargo" then p.CargoLevel else nil)
			else nil
		if type(level) == "number" and type(offer.grant.level) == "number" then
			owned = level >= offer.grant.level
		end
		return table.freeze({
			ok = true,
			owned = owned,
			code = if owned then "OWNED" else "NOT_OWNED",
		})
	elseif kind == "ParticularOwnedCart" then
		local durableCartId = if type(targetContext) == "table" then targetContext.durableCartId else nil
		if type(durableCartId) ~= "string" or durableCartId == "" then
			return table.freeze({ ok = false, owned = false, code = "TARGET_CART_REQUIRED" })
		end
		if
			type(targetContext) == "table"
			and targetContext.ownerUserId ~= nil
			and targetContext.ownerUserId ~= playerSnapshot.userId
		then
			return table.freeze({ ok = false, owned = false, code = "FOREIGN_CART" })
		end
		local cart = if type(playerSnapshot.ownedCarts) == "table"
			then playerSnapshot.ownedCarts[durableCartId]
			else nil
		if type(cart) ~= "table" then
			return table.freeze({ ok = false, owned = false, code = "CART_NOT_OWNED" })
		end
		local owned = type(cart.ownedOfferIds) == "table" and cart.ownedOfferIds[offer.id] == true
		return table.freeze({
			ok = true,
			owned = owned,
			code = if owned then "OWNED" else "NOT_OWNED",
		})
	elseif kind == "EquipmentOwnership" then
		local equipmentId = if type(offer.grant) == "table" then offer.grant.equipmentId else nil
		if type(equipmentId) ~= "string" or equipmentId == "" then
			return table.freeze({ ok = false, owned = false, code = "EQUIPMENT_ID_REQUIRED" })
		end
		local owned = type(playerSnapshot.ownedEquipment) == "table"
			and playerSnapshot.ownedEquipment[equipmentId] == true
		return table.freeze({
			ok = true,
			owned = owned,
			code = if owned then "OWNED" else "NOT_OWNED",
		})
	end
	return table.freeze({ ok = false, owned = false, code = "UNSUPPORTED_OWNERSHIP_SCOPE" })
end

local function hasOwnedCartAtLeastTier(snapshot: any, minimumTier: number): boolean
	if type(snapshot.ownedCarts) ~= "table" then
		return false
	end
	for _, cart in snapshot.ownedCarts do
		if type(cart) == "table" and type(cart.tier) == "number" and cart.tier >= minimumTier then
			return true
		end
	end
	return false
end

local function checkRequirements(offer: any, snapshot: any, readiness: any, reasons: { any }): (boolean, boolean)
	local locked = false
	local unavailable = false
	local requirements = offer.requirements or {}
	local priorOfferId = requirements.priorOfferId
	if type(priorOfferId) == "string" then
		if not Eligibility.ResolveOwnership(Upgrades.Get(priorOfferId), snapshot, nil).owned then
			table.insert(reasons, reason("PRIOR_OFFER_REQUIRED", "Own the previous upgrade first.", "Player"))
			locked = true
		end
	end
	local requiredRank = requirements.requiredRank
	if requiredRank ~= nil then
		if readiness.rankProviderOperational ~= true then
			table.insert(
				reasons,
				reason("RANK_PROVIDER_UNAVAILABLE", "Rank progression is not implemented.", "Configuration")
			)
			unavailable = true
		elseif type(snapshot.rank) ~= "number" or snapshot.rank < requiredRank then
			table.insert(reasons, reason("RANK_REQUIRED", string.format("Reach Rank %d.", requiredRank), "Player"))
			locked = true
		end
	end
	local cartRequirement = requirements.cartQualification
	if cartRequirement ~= nil then
		local minimumTier = cartRequirement.minimumTier
		local providerReady = type(readiness.cartAcquisitionByTier) == "table"
			and readiness.cartAcquisitionByTier[minimumTier] == true
		if cartRequirement.mode == "PendingDecision" then
			table.insert(
				reasons,
				reason(
					"CART_TIER_SEMANTICS_PENDING",
					"Cart-tier ownership versus equipped-cart requirements await approval.",
					"Configuration"
				)
			)
			unavailable = true
		elseif not providerReady then
			table.insert(
				reasons,
				reason(
					"CART_ACQUISITION_UNAVAILABLE",
					string.format("A normal Tier %d cart acquisition path is unavailable.", minimumTier),
					"Configuration"
				)
			)
			unavailable = true
		elseif cartRequirement.mode == "OwnsAtLeastTier" then
			if not hasOwnedCartAtLeastTier(snapshot, minimumTier) then
				table.insert(
					reasons,
					reason(
						"OWNED_CART_TIER_REQUIRED",
						string.format("Own a Tier %d or higher cart.", minimumTier),
						"Player"
					)
				)
				locked = true
			end
		elseif cartRequirement.mode == "EquippedOwnedCartAtLeastTier" then
			local equippedId = snapshot.equippedCartDurableId
			local equipped = if type(snapshot.ownedCarts) == "table" then snapshot.ownedCarts[equippedId] else nil
			if type(equipped) ~= "table" or type(equipped.tier) ~= "number" or equipped.tier < minimumTier then
				table.insert(
					reasons,
					reason(
						"EQUIPPED_CART_TIER_REQUIRED",
						string.format("Equip your Tier %d or higher cart.", minimumTier),
						"Player"
					)
				)
				locked = true
			end
		else
			table.insert(reasons, reason("INVALID_CART_REQUIREMENT", "Cart requirement is invalid.", "Configuration"))
			unavailable = true
		end
	end
	return locked, unavailable
end

function Eligibility.EvaluateOffer(offer: any, playerSnapshot: any, targetContext: any?, readiness: any?): any
	if type(offer) ~= "table" or type(offer.id) ~= "string" then
		return result("Invalid", { reason("INVALID_OFFER", "This offer is invalid.", "Configuration") })
	end
	if type(playerSnapshot) ~= "table" or playerSnapshot.status ~= "Ready" then
		return result("Loading", { reason("PROFILE_LOADING", "Player data is still loading.", "Temporary") })
	end
	local ownership = Eligibility.ResolveOwnership(offer, playerSnapshot, targetContext)
	if ownership.owned then
		return result("Owned", {}, { owned = true, ownershipCode = ownership.code })
	end
	if not ownership.ok then
		local outcome = if ownership.code == "TARGET_CART_REQUIRED"
				or ownership.code == "FOREIGN_CART"
				or ownership.code == "CART_NOT_OWNED"
			then "Invalid"
			else "Unavailable"
		return result(outcome, {
			reason(
				ownership.code,
				if ownership.code == "OWNERSHIP_SCOPE_PENDING"
					then "Ownership scope awaits approval."
					else "The required ownership context is unavailable.",
				"Configuration"
			),
		}, { owned = false, ownershipCode = ownership.code })
	end
	local suppliedReadiness = readiness or {}
	local reasons = {}
	if offer.definitionStatus ~= "Complete" then
		table.insert(reasons, reason("DEFINITION_INCOMPLETE", "Offer definition awaits approval.", "Configuration"))
	end
	if offer.releaseStatus ~= "Released" then
		table.insert(reasons, reason("OFFER_NOT_RELEASED", "This offer is not released for purchase.", "Configuration"))
	end
	local effectReadiness = if type(suppliedReadiness.effectReadyByOfferId) == "table"
		then suppliedReadiness.effectReadyByOfferId[offer.id]
		else nil
	local effectReady = effectReadiness == true
	if type(effectReadiness) == "function" then
		local ok, ready = pcall(effectReadiness, offer, playerSnapshot, targetContext)
		effectReady = ok and ready == true
	end
	if not effectReady then
		table.insert(reasons, reason("EFFECT_NOT_READY", "The gameplay effect is not ready.", "Configuration"))
	end
	local scopeKind = offer.ownershipScope and offer.ownershipScope.kind
	if
		type(suppliedReadiness.persistenceReadyByScope) ~= "table"
		or suppliedReadiness.persistenceReadyByScope[scopeKind] ~= true
	then
		table.insert(
			reasons,
			reason("PERSISTENCE_NOT_READY", "Ownership persistence for this scope is not ready.", "Configuration")
		)
	end
	if #reasons > 0 then
		return result("Unavailable", reasons, { owned = false, ownershipCode = ownership.code })
	end
	local locked, unavailable = checkRequirements(offer, playerSnapshot, suppliedReadiness, reasons)
	if unavailable then
		return result("Unavailable", reasons, { owned = false, ownershipCode = ownership.code })
	end
	if locked then
		return result("Locked", reasons, { owned = false, ownershipCode = ownership.code })
	end
	if not finiteNonNegative(playerSnapshot.balance) then
		return result(
			"Invalid",
			{ reason("INVALID_BALANCE", "Wallet data is unavailable.", "Configuration") },
			{ owned = false }
		)
	end
	if playerSnapshot.balance < offer.price then
		local shortfall = offer.price - playerSnapshot.balance
		return result("InsufficientFunds", {
			reason("INSUFFICIENT_FUNDS", "Need " .. CurrencyFormatter.FormatExactCash(shortfall) .. " more.", "Player"),
		}, { owned = false, shortfall = shortfall })
	end
	return result("Available", {}, { owned = false, shortfall = 0 })
end

-- Reporting only: reuse the authoritative checks independently. The private
-- sufficient-funds/unowned projection bypasses the Owned presentation shortcut,
-- not purchase authorization. It is never written back or used by a purchase.
function Eligibility.DecomposeOffer(offer: any, playerSnapshot: any, targetContext: any?, readiness: any?): any
	local current = Eligibility.EvaluateOffer(offer, playerSnapshot, targetContext, readiness)
	local snapshot = if type(playerSnapshot) == "table" then table.clone(playerSnapshot) else {}
	local price = if type(offer) == "table" then offer.price else nil
	local balance = snapshot.balance
	local fundsSufficient = finiteNonNegative(balance) and finiteNonNegative(price) and balance >= price
	if finiteNonNegative(price) then
		snapshot.balance = math.max(if finiteNonNegative(balance) then balance else 0, price)
	end
	if current.owned then
		local scopeKind = offer.ownershipScope.kind
		if scopeKind == "PlayerWide" then
			snapshot.ownedOfferIds = table.clone(snapshot.ownedOfferIds)
			snapshot.ownedOfferIds[offer.id] = nil
		elseif scopeKind == "EquipmentOwnership" then
			snapshot.ownedEquipment = table.clone(snapshot.ownedEquipment)
			snapshot.ownedEquipment[offer.grant.equipmentId] = nil
		elseif scopeKind == "ParticularOwnedCart" then
			local cartId = targetContext.durableCartId
			snapshot.ownedCarts = table.clone(snapshot.ownedCarts)
			local cart = table.clone(snapshot.ownedCarts[cartId])
			cart.ownedOfferIds = table.clone(cart.ownedOfferIds)
			cart.ownedOfferIds[offer.id] = nil
			snapshot.ownedCarts[cartId] = cart
		end
	end
	local probeReadiness = readiness
	local configuredEffect = if type(readiness) == "table"
			and type(readiness.effectReadyByOfferId) == "table"
			and type(offer) == "table"
		then readiness.effectReadyByOfferId[offer.id]
		else nil
	if type(configuredEffect) == "function" then
		probeReadiness = table.clone(readiness)
		probeReadiness.effectReadyByOfferId = table.clone(readiness.effectReadyByOfferId)
		probeReadiness.effectReadyByOfferId[offer.id] = function()
			return configuredEffect(offer, playerSnapshot, targetContext)
		end
	end
	local nonPrice = Eligibility.EvaluateOffer(offer, snapshot, targetContext, probeReadiness)
	local ready = nonPrice.outcome == "Available" or nonPrice.outcome == "Locked"
	local validOffer = type(offer) == "table" and type(offer.id) == "string"
	local prerequisitesSatisfied = false
	local effectReady = false
	if validOffer and snapshot.status == "Ready" then
		local locked, unavailable = checkRequirements(offer, playerSnapshot, readiness or {}, {})
		prerequisitesSatisfied = not locked and not unavailable
		-- A valid unowned context reaches EvaluateOffer's readiness checks, which
		-- report every unavailable implementation before checking prerequisites.
		local ownership = Eligibility.ResolveOwnership(offer, snapshot, targetContext)
		if ownership.ok then
			effectReady = true
			for _, unavailableReason in nonPrice.reasons do
				if unavailableReason.code == "EFFECT_NOT_READY" then
					effectReady = false
				end
			end
		end
	end
	local owned = current.owned == true
	local eligible = ready
		and prerequisitesSatisfied
		and not owned
		and (current.outcome == "Available" or current.outcome == "InsufficientFunds")
	return table.freeze({
		outcome = current.outcome,
		owned = owned,
		alreadyOwned = owned,
		fundsSufficient = fundsSufficient,
		definitionReady = validOffer and offer.definitionStatus == "Complete",
		effectReady = effectReady,
		pathReady = ready,
		ready = ready,
		prerequisitesSatisfied = prerequisitesSatisfied,
		eligible = eligible,
		eligibleAffordable = eligible and fundsSufficient,
		pathBlocked = not ready,
		primaryReason = if current.primaryReason then current.primaryReason.code else nil,
		nonPriceOutcome = nonPrice.outcome,
		nonPricePrimaryReason = if nonPrice.primaryReason then nonPrice.primaryReason.code else nil,
	})
end

function Eligibility.Evaluate(offerId: any, playerSnapshot: any, targetContext: any?, readiness: any?): any
	local offer = Upgrades.Get(offerId)
	if offer == nil then
		return result("Invalid", { reason("UNKNOWN_OFFER", "Unknown upgrade offer.", "Configuration") })
	end
	if Upgrades.IsRetiredByTraining(offer) then
		-- Camp Rework: cart speed now comes from Training levels, not Speed upgrades.
		return result("Invalid", { reason("SPEED_RETIRED_USE_TRAINING", "Cart speed now comes from Training.", "Configuration") })
	end
	return Eligibility.EvaluateOffer(offer, playerSnapshot, targetContext, readiness)
end

local function requirementText(requirements: any): { string }
	local values = {}
	if type(requirements) ~= "table" then
		return values
	end
	if type(requirements.priorOfferId) == "string" then
		local prior = Upgrades.Get(requirements.priorOfferId)
		local priorLabel = if prior then prior.displayName else requirements.priorOfferId
		table.insert(values, "Own " .. priorLabel)
	elseif type(requirements.priorOfferDecision) == "table" then
		table.insert(values, "Previous-level requirement awaiting approval")
	end
	if type(requirements.requiredRank) == "number" then
		table.insert(values, string.format("Reach Rank %d", requirements.requiredRank))
	end
	local cart = requirements.cartQualification
	if type(cart) == "table" then
		if cart.mode == "OwnsAtLeastTier" then
			table.insert(values, string.format("Own a Tier %d or higher cart", cart.minimumTier))
		elseif cart.mode == "EquippedOwnedCartAtLeastTier" then
			table.insert(values, string.format("Equip your Tier %d or higher cart", cart.minimumTier))
		else
			table.insert(values, string.format("Tier %d cart rule awaiting approval", cart.minimumTier))
		end
	end
	if #values == 0 then
		table.insert(values, "No progression prerequisite")
	end
	return values
end

local function scopeText(offer: any, previewData: any?): string
	local scope = offer.ownershipScope and offer.ownershipScope.kind
	if scope == "PlayerWide" then
		return "Applies to all your compatible carts"
	elseif scope == "ParticularOwnedCart" then
		local name = if type(previewData) == "table" then previewData.targetCartDisplayName else nil
		return if type(name) == "string" and name ~= ""
			then "Applies to your selected " .. name
			else "Select one of your carts"
	elseif scope == "EquipmentOwnership" then
		return "Own the equipment; equip it to use its effect"
	end
	return "Ownership scope awaiting approval"
end

function Eligibility.DescribeOffer(offer: any, evaluation: any, previewData: any?): any
	local outcome = if type(evaluation) == "table" then evaluation.outcome else "Invalid"
	local actionByOutcome = {
		Loading = "Loading…",
		Unavailable = "Unavailable",
		Locked = "Locked",
		Owned = "Owned",
		Maxed = "Maxed",
		InsufficientFunds = "Need more Cash",
		Available = "Buy",
		Invalid = "Unavailable",
	}
	return table.freeze({
		offerId = offer.id,
		title = offer.displayName,
		effectSummary = offer.effect.summary,
		ownershipSummary = scopeText(offer, previewData),
		price = offer.price,
		priceText = CurrencyFormatter.FormatExactCash(offer.price),
		currencyId = offer.currencyId,
		requirementLines = table.freeze(requirementText(offer.requirements)),
		state = outcome,
		primaryExplanation = if evaluation and evaluation.primaryReason then evaluation.primaryReason.message else nil,
		actionLabel = actionByOutcome[outcome] or "Unavailable",
		canActivate = outcome == "Available",
	})
end

function Eligibility.ValidateReachability(definitions: { any }, providers: any?): any
	local supplied = providers or {}
	local byId: { [string]: any } = {}
	local errors = {}
	local blockers = {}
	local byOfferId: { [string]: any } = {}
	local function add(target: { any }, code: string, offerId: string?, message: string)
		table.insert(target, { code = code, offerId = offerId, message = message })
	end
	for _, offer in definitions do
		if type(offer) == "table" and type(offer.id) == "string" then
			if byId[offer.id] then
				add(errors, "DUPLICATE_ID", offer.id, "duplicate offer ID")
			else
				byId[offer.id] = offer
				byOfferId[offer.id] = {
					structurallyValid = true,
					operational = true,
					issues = {},
				}
			end
		end
	end
	local visit: { [string]: number } = {}
	local function mark(offerId: string, code: string, message: string, structural: boolean)
		local entry = byOfferId[offerId]
		if entry then
			if structural then
				entry.structurallyValid = false
			else
				entry.operational = false
			end
			table.insert(entry.issues, code)
		end
		add(if structural then errors else blockers, code, offerId, message)
	end
	local function walk(offerId: string)
		if visit[offerId] == 2 then
			return
		end
		if visit[offerId] == 1 then
			mark(offerId, "PREREQUISITE_CYCLE", "offer prerequisite cycle detected", true)
			return
		end
		visit[offerId] = 1
		local offer = byId[offerId]
		local requirements = if offer then offer.requirements else nil
		local prior = if type(requirements) == "table" then requirements.priorOfferId else nil
		if type(prior) == "string" then
			if prior == offerId then
				mark(offerId, "SELF_DEPENDENCY", "offer requires itself", true)
			elseif byId[prior] == nil then
				mark(offerId, "UNKNOWN_PREDECESSOR", "required predecessor is unknown", true)
			else
				walk(prior)
				if visit[prior] == 1 then
					mark(offerId, "PREREQUISITE_CYCLE", "offer prerequisite cycle detected", true)
				end
			end
		end
		visit[offerId] = 2
	end
	for offerId in byId do
		walk(offerId)
	end
	for offerId, offer in byId do
		local entry = byOfferId[offerId]
		local requirements = offer.requirements or {}
		if type(requirements.priorOfferDecision) == "table" then
			mark(offerId, "PREDECESSOR_DECISION_PENDING", "level sequence requires approval", true)
		end
		if requirements.requiredRank ~= nil and supplied.rankProviderOperational ~= true then
			mark(
				offerId,
				if supplied.rankProviderOperational == "DevelopmentOnly"
					then "DEVELOPMENT_ONLY_PROVIDER"
					else "RANK_PROVIDER_UNAVAILABLE",
				"rank has no normal operational gameplay provider",
				false
			)
		end
		local cart = requirements.cartQualification
		if type(cart) == "table" then
			if cart.mode == "PendingDecision" then
				mark(offerId, "CART_TIER_SEMANTICS_PENDING", "cart-tier requirement is ambiguous", true)
			end
			local cartProvider = if type(supplied.cartAcquisitionByTier) == "table"
				then supplied.cartAcquisitionByTier[cart.minimumTier]
				else nil
			if cartProvider ~= true then
				mark(
					offerId,
					if cartProvider == "DevelopmentOnly"
						then "DEVELOPMENT_ONLY_PROVIDER"
						else "CART_ACQUISITION_UNAVAILABLE",
					"required cart tier has no operational acquisition path",
					false
				)
			end
		end
		if offer.price > 0 and supplied.currencyEarningOperational ~= true then
			mark(
				offerId,
				if supplied.currencyEarningOperational == "DevelopmentOnly"
					then "DEVELOPMENT_ONLY_PROVIDER"
					else "CURRENCY_EARNING_UNAVAILABLE",
				"normal currency cannot be earned through released gameplay",
				false
			)
		end
		entry.operational = entry.operational and entry.structurallyValid
	end
	return {
		structurallyValid = #errors == 0,
		operational = #errors == 0 and #blockers == 0,
		errors = errors,
		blockers = blockers,
		byOfferId = byOfferId,
	}
end

return table.freeze(Eligibility)
