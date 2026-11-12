--!strict

-- Pure Phase 7D performance derivation. This module reads an already-loaded
-- ownership snapshot and immutable cart/offer definitions. It never loads or
-- mutates profiles, carts, motors, currency, or purchase state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local Training = require(script.Parent.Parent.Config.Training)
local CampFlags = require(script.Parent.Parent.Config.CampReworkFlags)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local UpgradeEligibility = require(ReplicatedStorage.Shared.Utility.UpgradeEligibility)

local CartPerformanceResolver = {}

local function finitePositive(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and math.abs(value) < math.huge
end

local function cartDefinition(descriptor: any, definitionsByCartId: any): any?
	if type(descriptor) ~= "table" or type(descriptor.cartId) ~= "string" then
		return nil
	end
	return definitionsByCartId[descriptor.cartId]
end

local function isApprovedSpeedEffect(offer: any): boolean
	local effect = if type(offer) == "table" then offer.effect else nil
	return type(offer) == "table"
		and offer.category == "CartPerformance"
		and offer.definitionStatus == "Complete"
		and offer.effectStatus == "Ready"
		and type(offer.ownershipScope) == "table"
		and offer.ownershipScope.kind ~= "PendingDecision"
		and type(offer.applicability) == "table"
		and offer.applicability.kind ~= "PendingDecision"
		and type(effect) == "table"
		and effect.statId == "CartBaseSpeed"
		and effect.operation == "AddBaseRelativeFraction"
		and finitePositive(effect.value)
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

local function finish(status: string, baseSpeed: number?, extra: any?): any
	local value = extra or {}
	value.status = status
	value.baseSpeed = baseSpeed
	value.controlReferenceSpeed = baseSpeed
	value.purchasedSpeedContribution = value.purchasedSpeedContribution or 0
	value.appliedOfferIds = table.freeze(value.appliedOfferIds or {})
	value.blockedOfferIds = table.freeze(value.blockedOfferIds or {})
	value.handlingSupported = false
	value.handlingCode = "HANDLING_EFFECT_UNDEFINED"
	return table.freeze(value)
end

function CartPerformanceResolver.Resolve(ownerState: any?, descriptor: any, options: any?): any
	local definitions = if type(options) == "table" and options.cartDefinitions then options.cartDefinitions else Carts
	local definition = cartDefinition(descriptor, definitions)
	local baseSpeed = if type(definition) == "table" then definition.MaxTravelSpeed else nil
	if not finitePositive(baseSpeed) then
		return finish("InvalidCart", nil, { code = "INVALID_BASE_SPEED" })
	end

	local phase13 = type(ownerState) == "table" and ownerState.phase13
	if type(phase13) == "table" then
		if ownerState.status ~= "Ready" then
			return finish("NotReady", baseSpeed, { code = "OWNER_STATE_NOT_READY" })
		end
		if type(descriptor.ownerUserId) ~= "number" or ownerState.userId ~= descriptor.ownerUserId then
			return finish("InvalidOwner", baseSpeed, { code = "CART_OWNER_MISMATCH" })
		end
		-- Camp Rework: with Training on, cart speed comes only from TrainingLevel (0–25; level 5n is old
		-- Speed n, geometric in between). SpeedLevel is kept for migration only.
		local trainingLevel = phase13.TrainingLevel
		if CampFlags.Training() and type(trainingLevel) == "number" then
			if trainingLevel % 1 ~= 0 or trainingLevel < 0 or trainingLevel > Training.MaxLevel then
				return finish("NotReady", baseSpeed, { code = "INVALID_TRAINING_LEVEL" })
			end
			local multiplier = Training.SpeedMultiplier(trainingLevel)
			return finish("Ready", baseSpeed, {
				code = "TRAINING_LEVEL",
				resolvedSpeed = baseSpeed * multiplier,
				purchasedSpeedContribution = multiplier - 1,
			})
		end
		local level = phase13.SpeedLevel
		if type(level) ~= "number" or level % 1 ~= 0 or level < 0 or level > 5 then
			return finish("NotReady", baseSpeed, { code = "INVALID_SPEED_LEVEL" })
		end
		return finish(
			"Ready",
			baseSpeed,
			{ code = "PHASE13_LEVEL", resolvedSpeed = baseSpeed * (1 + 0.10 * level), purchasedSpeedContribution = 0.10
				* level }
		)
	end

	local speedOffers = {}
	local blockedOfferIds = {}
	local seenOfferIds = {}
	for _, offer in allOffers(options) do
		local effect = if type(offer) == "table" then offer.effect else nil
		if
			type(offer) == "table"
			and offer.category == "CartPerformance"
			and type(effect) == "table"
			and (effect.statId == "CartBaseSpeed" or effect.statId == "CartHandling")
		then
			local id = tostring(offer.id)
			if seenOfferIds[id] then
				return finish("InvalidConfiguration", baseSpeed, {
					code = "DUPLICATE_OFFER_ID",
					blockedOfferIds = blockedOfferIds,
				})
			end
			seenOfferIds[id] = true
			if isApprovedSpeedEffect(offer) then
				table.insert(speedOffers, offer)
			else
				table.insert(blockedOfferIds, id)
			end
		end
	end
	table.sort(blockedOfferIds)

	-- No approved performance entitlement exists in the current production
	-- catalogue. Preserve the established baseline without inventing a writable
	-- default ownership snapshot.
	if #speedOffers == 0 then
		return finish("Ready", baseSpeed, {
			code = "BASE_PERFORMANCE_ONLY",
			resolvedSpeed = baseSpeed,
			blockedOfferIds = blockedOfferIds,
		})
	end
	if type(ownerState) ~= "table" or ownerState.status ~= "Ready" then
		return finish("NotReady", baseSpeed, {
			code = "OWNER_STATE_NOT_READY",
			blockedOfferIds = blockedOfferIds,
		})
	end
	if type(descriptor.ownerUserId) ~= "number" or ownerState.userId ~= descriptor.ownerUserId then
		return finish("InvalidOwner", baseSpeed, {
			code = "CART_OWNER_MISMATCH",
			blockedOfferIds = blockedOfferIds,
		})
	end

	table.sort(speedOffers, function(left, right)
		return tostring(left.id) < tostring(right.id)
	end)
	local contribution = 0
	local applied = {}
	for _, offer in speedOffers do
		local applies, applicabilityReason = appliesToCart(offer, descriptor)
		if applies then
			local ownership = UpgradeEligibility.ResolveOwnership(offer, ownerState, descriptor)
			if ownership.ok and ownership.owned then
				contribution += offer.effect.value
				table.insert(applied, offer.id)
			elseif not ownership.ok and ownership.code ~= "NOT_OWNED" then
				return finish("NotReady", baseSpeed, {
					code = ownership.code,
					blockedOfferIds = blockedOfferIds,
				})
			end
		elseif applicabilityReason == "DURABLE_CART_ID_REQUIRED" then
			return finish("NotReady", baseSpeed, {
				code = applicabilityReason,
				blockedOfferIds = blockedOfferIds,
			})
		end
	end

	local resolvedSpeed = (baseSpeed :: number) * (1 + contribution)
	if not finitePositive(resolvedSpeed) then
		return finish("InvalidPerformance", baseSpeed, {
			code = "INVALID_RESOLVED_SPEED",
			purchasedSpeedContribution = contribution,
			appliedOfferIds = applied,
			blockedOfferIds = blockedOfferIds,
		})
	end
	return finish("Ready", baseSpeed, {
		code = "PERFORMANCE_RESOLVED",
		purchasedSpeedContribution = contribution,
		resolvedSpeed = resolvedSpeed,
		appliedOfferIds = applied,
		blockedOfferIds = blockedOfferIds,
	})
end

return CartPerformanceResolver
