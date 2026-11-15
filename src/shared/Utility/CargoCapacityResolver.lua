--!strict

-- Pure Phase 7C capacity derivation. This module reads catalogue definitions and
-- an already-loaded ownership snapshot; it never loads data, grants ownership,
-- mutates a cart, or treats purchase availability as entitlement ownership.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local UpgradeEligibility = require(ReplicatedStorage.Shared.Utility.UpgradeEligibility)

local CargoCapacityResolver = {}

local MAX_CAPACITY = 6

local function positiveInteger(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge and value % 1 == 0
end

local function cartDefinition(descriptor: any, definitionsByCartId: any): any?
	if type(descriptor) ~= "table" or type(descriptor.cartId) ~= "string" then
		return nil
	end
	return definitionsByCartId[descriptor.cartId]
end

local function isCargoEffect(offer: any): boolean
	local effect = if type(offer) == "table" then offer.effect else nil
	return type(offer) == "table"
		and offer.category == "Cargo"
		and offer.definitionStatus == "Complete"
		and offer.effectStatus == "Ready"
		and type(offer.ownershipScope) == "table"
		and offer.ownershipScope.kind ~= "PendingDecision"
		and type(offer.applicability) == "table"
		and offer.applicability.kind ~= "PendingDecision"
		and type(effect) == "table"
		and effect.statId == "CargoCapacity"
		and effect.operation == "AddSlots"
		and positiveInteger(effect.value)
end

local function appliesToCart(offer: any, descriptor: any): (boolean, string?)
	local applicability = offer.applicability
	if applicability.kind == "AllOwnedCarts" then
		return true, nil
	elseif applicability.kind == "ParticularOwnedCart" then
		if type(descriptor.durableCartId) ~= "string" or descriptor.durableCartId == "" then
			return false, "DURABLE_CART_ID_REQUIRED"
		end
		return true, nil
	elseif applicability.kind == "CartModel" then
		local cartIds = applicability.cartIds
		return type(cartIds) == "table" and cartIds[descriptor.cartId] == true, "CART_MODEL_NOT_APPLICABLE"
	end
	return false, "UNSUPPORTED_APPLICABILITY"
end

local function allOffers(options: any): { any }
	if type(options) == "table" and type(options.offers) == "table" then
		return options.offers
	end
	return Upgrades.GetAll()
end

local function baseResult(status: string, baseCapacity: number?, extra: any?): any
	local value = extra or {}
	value.status = status
	value.baseCapacity = baseCapacity
	value.upgradeBonus = value.upgradeBonus or 0
	value.effectiveCapacity = value.effectiveCapacity
	value.appliedOfferIds = table.freeze(value.appliedOfferIds or {})
	value.blockedOfferIds = table.freeze(value.blockedOfferIds or {})
	return table.freeze(value)
end

function CargoCapacityResolver.Resolve(ownerState: any?, descriptor: any, options: any?): any
	local definitions = if type(options) == "table" and options.cartDefinitions then options.cartDefinitions else Carts
	local definition = cartDefinition(descriptor, definitions)
	local baseCapacity = if type(definition) == "table" then definition.CargoCapacity else nil
	if not positiveInteger(baseCapacity) or (baseCapacity :: number) > MAX_CAPACITY then
		return baseResult("InvalidCart", nil, { code = "INVALID_BASE_CAPACITY" })
	end

	local phase13 = type(ownerState) == "table" and ownerState.phase13
	if type(phase13) == "table" then
		if ownerState.status ~= "Ready" then
			return baseResult("NotReady", baseCapacity, { code = "OWNER_STATE_NOT_READY" })
		end
		if type(descriptor.ownerUserId) ~= "number" or ownerState.userId ~= descriptor.ownerUserId then
			return baseResult("InvalidOwner", baseCapacity, { code = "CART_OWNER_MISMATCH" })
		end
		local level = phase13.CargoLevel
		if type(level) ~= "number" or level % 1 ~= 0 or level < 0 or level > 3 then
			return baseResult("NotReady", baseCapacity, { code = "INVALID_CARGO_LEVEL" })
		end
		return baseResult(
			"Ready",
			baseCapacity,
			{ code = "PHASE13_LEVEL", effectiveCapacity = 3 + level, upgradeBonus = level }
		)
	end

	local applicableOffers = {}
	local blockedOfferIds = {}
	for _, offer in allOffers(options) do
		local effect = if type(offer) == "table" then offer.effect else nil
		if
			type(offer) == "table"
			and offer.category == "Cargo"
			and type(effect) == "table"
			and effect.statId == "CargoCapacity"
		then
			if isCargoEffect(offer) then
				table.insert(applicableOffers, offer)
			else
				table.insert(blockedOfferIds, tostring(offer.id))
			end
		end
	end
	table.sort(blockedOfferIds)

	-- With no approved cargo effects, the established cart baseline remains fully
	-- usable without inventing a fake profile/default entitlement.
	if #applicableOffers == 0 then
		return baseResult("Ready", baseCapacity, {
			code = "BASE_CAPACITY_ONLY",
			effectiveCapacity = baseCapacity,
			blockedOfferIds = blockedOfferIds,
		})
	end
	if type(ownerState) ~= "table" or ownerState.status ~= "Ready" then
		return baseResult("NotReady", baseCapacity, {
			code = "OWNER_STATE_NOT_READY",
			blockedOfferIds = blockedOfferIds,
		})
	end
	if type(descriptor.ownerUserId) ~= "number" or ownerState.userId ~= descriptor.ownerUserId then
		return baseResult("InvalidOwner", baseCapacity, {
			code = "CART_OWNER_MISMATCH",
			blockedOfferIds = blockedOfferIds,
		})
	end

	table.sort(applicableOffers, function(left, right)
		return tostring(left.id) < tostring(right.id)
	end)
	local bonus = 0
	local applied = {}
	for _, offer in applicableOffers do
		local applies, applicabilityReason = appliesToCart(offer, descriptor)
		if applies then
			local ownership = UpgradeEligibility.ResolveOwnership(offer, ownerState, descriptor)
			if ownership.ok and ownership.owned then
				bonus += offer.effect.value
				table.insert(applied, offer.id)
			elseif not ownership.ok and ownership.code ~= "NOT_OWNED" then
				return baseResult("NotReady", baseCapacity, {
					code = ownership.code,
					blockedOfferIds = blockedOfferIds,
				})
			end
		elseif applicabilityReason == "DURABLE_CART_ID_REQUIRED" then
			return baseResult("NotReady", baseCapacity, {
				code = applicabilityReason,
				blockedOfferIds = blockedOfferIds,
			})
		end
	end
	local effectiveCapacity = (baseCapacity :: number) + bonus
	if not positiveInteger(effectiveCapacity) or effectiveCapacity > MAX_CAPACITY then
		return baseResult("InvalidCapacity", baseCapacity, {
			code = "INVALID_EFFECTIVE_CAPACITY",
			upgradeBonus = bonus,
			appliedOfferIds = applied,
			blockedOfferIds = blockedOfferIds,
		})
	end
	return baseResult("Ready", baseCapacity, {
		code = "CAPACITY_RESOLVED",
		upgradeBonus = bonus,
		effectiveCapacity = effectiveCapacity,
		appliedOfferIds = applied,
		blockedOfferIds = blockedOfferIds,
	})
end

return CargoCapacityResolver
