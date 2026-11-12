--!strict

-- Phase 7B-1 is catalogue and read-only evaluation only. Definitions in this
-- module cannot deduct currency, grant ownership or alter live cart statistics.

export type ReleaseStatus = "Released" | "PendingDecision" | "Deferred" | "Deprecated"
export type DefinitionStatus = "Complete" | "PendingDecision"
export type OwnershipScopeKind = "PlayerWide" | "ParticularOwnedCart" | "EquipmentOwnership" | "PendingDecision"

export type ApplicabilityKind =
	"AllOwnedCarts"
	| "ParticularOwnedCart"
	| "CartModel"
	| "EquippedEquipment"
	| "PendingDecision"

export type UpgradeDefinition = {
	id: string,
	displayName: string,
	category: string,
	price: number,
	currencyId: string,
	grant: any,
	ownershipScope: any,
	applicability: any,
	requirements: any,
	effect: any,
	displayOrder: number,
	definitionStatus: DefinitionStatus,
	releaseStatus: ReleaseStatus,
	effectStatus: string,
	openDecisionCodes: { string },
}

-- P15 final Cash prices (re-anchored to final brainrot revenue).
-- Rows contain final denomination2 prices.
local IDS = table.freeze({
	CartSpeed1 = "CART_SPEED_1",
	CartSpeed2 = "CART_SPEED_2",
	Cargo1 = "CARGO_1",
	Cargo2 = "CARGO_2",
	Offroad1 = "OFFROAD_1",
})

local function deepFreeze(value: any, seen: { [any]: boolean }?): any
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		return value
	end
	visited[value] = true
	for _, nested in value do
		deepFreeze(nested, visited)
	end
	return table.freeze(value)
end

local rows: { UpgradeDefinition } = {
	{
		id = "CART_SPEED_1",
		displayName = "Speed 1",
		category = "CartPerformance",
		price = 500000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "CartSpeed", level = 1 },
		ownershipScope = { kind = "PlayerWide" },
		applicability = { kind = "AllOwnedCarts" },
		requirements = {},
		effect = {
			statId = "CartBaseSpeed",
			operation = "AddBaseRelativeFraction",
			value = 0.10,
			unit = "Fraction",
			summary = "+10% cart speed",
		},
		displayOrder = 10,
		definitionStatus = "Complete",
		releaseStatus = "Released",
		effectStatus = "Ready",
		openDecisionCodes = {},
	},
	{
		id = "CART_SPEED_2",
		displayName = "Speed 2",
		category = "CartPerformance",
		price = 2500000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "CartSpeed", level = 2 },
		ownershipScope = { kind = "PlayerWide" },
		applicability = { kind = "AllOwnedCarts" },
		requirements = { priorOfferId = "CART_SPEED_1" },
		effect = {
			statId = "CartBaseSpeed",
			operation = "AddBaseRelativeFraction",
			value = 0.10,
			unit = "Fraction",
			summary = "+10% cart speed",
		},
		displayOrder = 20,
		definitionStatus = "Complete",
		releaseStatus = "Released",
		effectStatus = "Ready",
		openDecisionCodes = {},
	},
	{
		id = "CART_SPEED_3",
		displayName = "Speed 3",
		category = "CartPerformance",
		price = 15000000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "CartSpeed", level = 3 },
		ownershipScope = { kind = "PlayerWide" },
		applicability = { kind = "AllOwnedCarts" },
		requirements = { priorOfferId = "CART_SPEED_2" },
		effect = {
			statId = "CartBaseSpeed",
			operation = "AddBaseRelativeFraction",
			value = 0.10,
			unit = "Fraction",
			summary = "+10% cart speed",
		},
		displayOrder = 30,
		definitionStatus = "Complete",
		releaseStatus = "Released",
		effectStatus = "Ready",
		openDecisionCodes = {},
	},
	{
		id = "CART_SPEED_4",
		displayName = "Speed 4",
		category = "CartPerformance",
		price = 75000000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "CartSpeed", level = 4 },
		ownershipScope = { kind = "PlayerWide" },
		applicability = { kind = "AllOwnedCarts" },
		requirements = { priorOfferId = "CART_SPEED_3" },
		effect = {
			statId = "CartBaseSpeed",
			operation = "AddBaseRelativeFraction",
			value = 0.10,
			unit = "Fraction",
			summary = "+10% cart speed",
		},
		displayOrder = 40,
		definitionStatus = "Complete",
		releaseStatus = "Released",
		effectStatus = "Ready",
		openDecisionCodes = {},
	},
	{
		id = "CART_SPEED_5",
		displayName = "Speed 5",
		category = "CartPerformance",
		price = 300000000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "CartSpeed", level = 5 },
		ownershipScope = { kind = "PlayerWide" },
		applicability = { kind = "AllOwnedCarts" },
		requirements = { priorOfferId = "CART_SPEED_4" },
		effect = {
			statId = "CartBaseSpeed",
			operation = "AddBaseRelativeFraction",
			value = 0.10,
			unit = "Fraction",
			summary = "+10% cart speed",
		},
		displayOrder = 50,
		definitionStatus = "Complete",
		releaseStatus = "Released",
		effectStatus = "Ready",
		openDecisionCodes = {},
	},
	{
		id = "CARGO_1",
		displayName = "Cargo 4",
		category = "Cargo",
		price = 1500000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "Cargo", level = 1 },
		ownershipScope = { kind = "PlayerWide" },
		applicability = { kind = "AllOwnedCarts" },
		requirements = {},
		effect = {
			statId = "CargoCapacity",
			operation = "AddSlots",
			value = 1,
			unit = "Slots",
			summary = "+1 cargo slot",
		},
		displayOrder = 110,
		definitionStatus = "Complete",
		releaseStatus = "Released",
		effectStatus = "Ready",
		openDecisionCodes = {},
	},
	{
		id = "CARGO_2",
		displayName = "Cargo 5",
		category = "Cargo",
		price = 12500000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "Cargo", level = 2 },
		ownershipScope = { kind = "PlayerWide" },
		applicability = { kind = "AllOwnedCarts" },
		requirements = { priorOfferId = "CARGO_1" },
		effect = {
			statId = "CargoCapacity",
			operation = "AddSlots",
			value = 1,
			unit = "Slots",
			summary = "+1 cargo slot",
		},
		displayOrder = 120,
		definitionStatus = "Complete",
		releaseStatus = "Released",
		effectStatus = "Ready",
		openDecisionCodes = {},
	},
	{
		id = "CARGO_3",
		displayName = "Cargo 6",
		category = "Cargo",
		price = 100000000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "Cargo", level = 3 },
		ownershipScope = { kind = "PlayerWide" },
		applicability = { kind = "AllOwnedCarts" },
		requirements = { priorOfferId = "CARGO_2" },
		effect = {
			statId = "CargoCapacity",
			operation = "AddSlots",
			value = 1,
			unit = "Slots",
			summary = "+1 cargo slot",
		},
		displayOrder = 130,
		definitionStatus = "Complete",
		releaseStatus = "Released",
		effectStatus = "Ready",
		openDecisionCodes = {},
	},
	{
		id = "OFFROAD_1",
		displayName = "Offroad I",
		category = "CartPerformance",
		price = 12000000,
		currencyId = "Cash",
		grant = { kind = "UpgradeTrackLevel", trackId = "Offroad", level = 1 },
		ownershipScope = { kind = "PendingDecision" },
		applicability = { kind = "PendingDecision" },
		requirements = { cartQualification = { mode = "PendingDecision", minimumTier = 3 } },
		effect = {
			statId = "CartHandling",
			operation = "AddBaseRelativeFraction",
			value = 0.10,
			unit = "Fraction",
			summary = "+10% cart handling",
		},
		displayOrder = 200,
		definitionStatus = "PendingDecision",
		releaseStatus = "Deferred",
		effectStatus = "MissingHandlingBoundary",
		openDecisionCodes = { "DEFERRED_BY_PHASE13" },
	},
}

local ordered: { UpgradeDefinition } = {}
local byId: { [string]: UpgradeDefinition } = {}
for _, definition in rows do
	-- Prices are final denomination 2; never FromLegacy here.
	deepFreeze(definition)
	assert(byId[definition.id] == nil, "Duplicate upgrade ID " .. definition.id)
	byId[definition.id] = definition
	table.insert(ordered, definition)
end
table.sort(ordered, function(left, right)
	if left.displayOrder ~= right.displayOrder then
		return left.displayOrder < right.displayOrder
	end
	return left.id < right.id
end)
table.freeze(ordered)
table.freeze(byId)

local Upgrades: { [string]: any } = {
	Ids = IDS,
	Definitions = byId,
	Aliases = table.freeze({}),
}

function Upgrades.Get(offerId: any): UpgradeDefinition?
	return if type(offerId) == "string" then byId[offerId] else nil
end

function Upgrades.GetAll(): { UpgradeDefinition }
	return table.clone(ordered)
end

-- Camp Rework: with TrainingV1Enabled, cart speed comes only from Training, so CART_SPEED_1…5 leave
-- the cart upgrade shop (rows stay defined for SpeedLevel migration and legacy receipts). Cargo stays.
function Upgrades.IsRetiredByTraining(offer: any): boolean
	return type(offer) == "table"
		and type(offer.grant) == "table"
		and offer.grant.trackId == "CartSpeed"
		and require(script.Parent.CampReworkFlags).Training()
end

function Upgrades.GetReleased(): { UpgradeDefinition }
	local result = {}
	for _, offer in ordered do
		if offer.definitionStatus == "Complete" and offer.releaseStatus == "Released"
			and not Upgrades.IsRetiredByTraining(offer) then
			table.insert(result, offer)
		end
	end
	return result
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local validCategories = { CartPerformance = true, Cargo = true, Equipment = true }
local validReleases = { Released = true, PendingDecision = true, Deferred = true, Deprecated = true }
local validDefinitions = { Complete = true, PendingDecision = true }
local validScopes = {
	PlayerWide = true,
	ParticularOwnedCart = true,
	EquipmentOwnership = true,
	PendingDecision = true,
}
local validApplicability = {
	AllOwnedCarts = true,
	ParticularOwnedCart = true,
	CartModel = true,
	EquippedEquipment = true,
	PendingDecision = true,
}
local validTracks = { CartSpeed = true, Cargo = true, Offroad = true }

local function expectedEffectSummary(effect: any): string?
	if
		effect.operation == "AddSlots"
		and effect.statId == "CargoCapacity"
		and finite(effect.value)
		and effect.value > 0
		and effect.value % 1 == 0
	then
		return string.format("+%d cargo slot%s", effect.value, if effect.value == 1 then "" else "s")
	elseif
		effect.operation == "AddBaseRelativeFraction"
		and (effect.statId == "CartBaseSpeed" or effect.statId == "CartHandling")
		and finite(effect.value)
		and effect.value > 0
	then
		local percent = effect.value * 100
		local amount = if percent % 1 == 0
			then string.format("%.0f", percent)
			else string.format("%.2f", percent):gsub("0+$", ""):gsub("%.$", "")
		local label = if effect.statId == "CartBaseSpeed" then "cart speed" else "cart handling"
		return string.format("+%s%% %s", amount, label)
	end
	return nil
end

function Upgrades.ValidateDefinitions(definitions: { any }, aliases: any?): any
	local errors = {}
	local warnings = {}
	local blockers = {}
	local seen: { [string]: boolean } = {}
	local orders: { [number]: boolean } = {}
	local function add(target: { any }, code: string, offerId: any, message: string)
		table.insert(target, { code = code, offerId = offerId, message = message })
	end
	for index, offer in definitions do
		if type(offer) ~= "table" then
			add(errors, "INVALID_DEFINITION", nil, string.format("definition %d is not a table", index))
			continue
		end
		local id = offer.id
		if type(id) ~= "string" or id:match("^[A-Z][A-Z0-9_]*$") == nil then
			add(errors, "INVALID_ID", id, "id must be a stable canonical identifier")
		elseif seen[id] then
			add(errors, "DUPLICATE_ID", id, "id appears more than once")
		else
			seen[id] = true
		end
		if type(offer.displayName) ~= "string" or offer.displayName:match("%S") == nil then
			add(errors, "MISSING_DISPLAY_NAME", id, "displayName is required")
		end
		if not validCategories[offer.category] then
			add(errors, "INVALID_CATEGORY", id, "category is unsupported")
		end
		if not finite(offer.price) or offer.price < 0 or offer.price % 1 ~= 0 then
			add(errors, "INVALID_PRICE", id, "price must be a finite nonnegative integer")
		end
		if offer.currencyId ~= "Cash" then
			add(errors, "UNKNOWN_CURRENCY", id, "currencyId must reference the current Cash wallet")
		end
		if type(offer.grant) ~= "table" or type(offer.grant.kind) ~= "string" then
			add(errors, "INVALID_GRANT", id, "grant must be explicit")
		elseif offer.grant.kind == "UpgradeTrackLevel" then
			if not validTracks[offer.grant.trackId] then
				add(errors, "INVALID_UPGRADE_TRACK", id, "upgrade track is unsupported")
			end
			if not finite(offer.grant.level) or offer.grant.level <= 0 or offer.grant.level % 1 ~= 0 then
				add(errors, "INVALID_UPGRADE_LEVEL", id, "upgrade level must be a positive integer")
			end
		else
			add(errors, "INVALID_GRANT", id, "grant kind is unsupported")
		end
		local scope = if type(offer.ownershipScope) == "table" then offer.ownershipScope.kind else nil
		if not validScopes[scope] then
			add(errors, "INVALID_OWNERSHIP_SCOPE", id, "ownershipScope is unsupported")
		elseif scope == "PendingDecision" then
			add(blockers, "OWNERSHIP_SCOPE_PENDING", id, "ownership scope requires approval")
		end
		local applicability = if type(offer.applicability) == "table" then offer.applicability.kind else nil
		if not validApplicability[applicability] then
			add(errors, "INVALID_APPLICABILITY", id, "applicability is unsupported")
		elseif applicability == "PendingDecision" then
			add(blockers, "APPLICABILITY_PENDING", id, "effect applicability requires approval")
		elseif applicability == "CartModel" then
			local cartIds = offer.applicability.cartIds
			local compatibleCount = 0
			if type(cartIds) ~= "table" then
				add(errors, "INVALID_COMPATIBLE_CARTS", id, "CartModel applicability requires cartIds")
			else
				for cartId, compatible in cartIds do
					if type(cartId) ~= "string" or cartId:match("^CRT_%d%d%d$") == nil or compatible ~= true then
						add(
							errors,
							"INVALID_COMPATIBLE_CART",
							id,
							"compatible cart IDs must be canonical true-valued entries"
						)
					else
						compatibleCount += 1
					end
				end
				if compatibleCount == 0 then
					add(errors, "EMPTY_COMPATIBLE_CARTS", id, "at least one compatible cart is required")
				end
			end
		end
		if not validDefinitions[offer.definitionStatus] then
			add(errors, "INVALID_DEFINITION_STATUS", id, "definitionStatus is unsupported")
		end
		if not validReleases[offer.releaseStatus] then
			add(errors, "INVALID_RELEASE_STATUS", id, "releaseStatus is unsupported")
		elseif
			offer.releaseStatus == "Released"
			and (offer.definitionStatus ~= "Complete" or scope == "PendingDecision")
		then
			add(errors, "RELEASED_INCOMPLETE_OFFER", id, "an incomplete offer cannot be released")
		end
		if type(offer.displayOrder) ~= "number" or offer.displayOrder % 1 ~= 0 then
			add(errors, "INVALID_DISPLAY_ORDER", id, "displayOrder must be an integer")
		elseif orders[offer.displayOrder] then
			add(errors, "DUPLICATE_DISPLAY_ORDER", id, "displayOrder must be unique")
		else
			orders[offer.displayOrder] = true
		end
		local effect = offer.effect
		if type(effect) ~= "table" or type(effect.summary) ~= "string" then
			add(errors, "INVALID_EFFECT", id, "effect and summary are required")
		elseif effect.operation == "AddSlots" then
			if effect.statId ~= "CargoCapacity" then
				add(errors, "INVALID_EFFECT_STAT", id, "AddSlots must target CargoCapacity")
			end
			if not finite(effect.value) or effect.value <= 0 or effect.value % 1 ~= 0 then
				add(errors, "INVALID_SLOT_INCREMENT", id, "slot increment must be a positive integer")
			end
			if effect.unit ~= "Slots" then
				add(errors, "INVALID_EFFECT_UNIT", id, "AddSlots requires Slots units")
			end
		elseif effect.operation == "AddBaseRelativeFraction" then
			if effect.statId ~= "CartBaseSpeed" and effect.statId ~= "CartHandling" then
				add(errors, "INVALID_EFFECT_STAT", id, "relative fraction targets an unsupported stat")
			end
			if not finite(effect.value) or effect.value <= 0 then
				add(errors, "INVALID_FRACTION", id, "relative fraction must be finite and positive")
			end
			if effect.unit ~= "Fraction" then
				add(errors, "INVALID_EFFECT_UNIT", id, "relative effects require Fraction units")
			end
		else
			add(errors, "INVALID_EFFECT_OPERATION", id, "effect operation is unsupported")
		end
		if type(effect) == "table" then
			local expectedSummary = expectedEffectSummary(effect)
			if expectedSummary ~= nil and effect.summary ~= expectedSummary then
				add(errors, "EFFECT_SUMMARY_MISMATCH", id, "effect summary does not match its typed value")
			end
		end
		local requirements = offer.requirements
		if type(requirements) ~= "table" then
			add(errors, "INVALID_REQUIREMENTS", id, "requirements must be a table")
		else
			local prior = requirements.priorOfferId
			if prior ~= nil and type(prior) ~= "string" then
				add(errors, "INVALID_PREDECESSOR", id, "priorOfferId must be a stable ID")
			end
			local priorDecision = requirements.priorOfferDecision
			if priorDecision ~= nil then
				if type(priorDecision) ~= "table" or type(priorDecision.proposedOfferId) ~= "string" then
					add(
						errors,
						"INVALID_PREDECESSOR_DECISION",
						id,
						"pending predecessor decision must name a proposed offer"
					)
				else
					add(blockers, "PREDECESSOR_DECISION_PENDING", id, "level sequence requires approval")
				end
			end
			local requiredRank = requirements.requiredRank
			if requiredRank ~= nil and (not finite(requiredRank) or requiredRank <= 0 or requiredRank % 1 ~= 0) then
				add(errors, "INVALID_REQUIRED_RANK", id, "requiredRank must be a positive integer")
			end
			local cart = requirements.cartQualification
			if cart ~= nil then
				if type(cart) ~= "table" or type(cart.mode) ~= "string" then
					add(errors, "INVALID_CART_REQUIREMENT", id, "cart qualification is malformed")
				elseif
					cart.mode ~= "OwnsAtLeastTier"
					and cart.mode ~= "EquippedOwnedCartAtLeastTier"
					and cart.mode ~= "PendingDecision"
				then
					add(errors, "INVALID_CART_REQUIREMENT", id, "cart qualification mode is unsupported")
				elseif not finite(cart.minimumTier) or cart.minimumTier <= 0 or cart.minimumTier % 1 ~= 0 then
					add(errors, "INVALID_CART_TIER", id, "minimumTier must be a positive integer")
				elseif cart.mode == "PendingDecision" then
					add(blockers, "CART_TIER_SEMANTICS_PENDING", id, "own-versus-equip semantics require approval")
				end
			end
		end
		if type(offer.openDecisionCodes) ~= "table" then
			add(errors, "INVALID_DECISION_CODES", id, "openDecisionCodes must be an array")
		end
		if offer.effectStatus == "MissingHandlingBoundary" then
			add(blockers, "EFFECT_BOUNDARY_MISSING", id, "handling has no approved gameplay resolver boundary")
		end
	end
	for alias, canonical in aliases or {} do
		if type(alias) ~= "string" or type(canonical) ~= "string" then
			add(errors, "INVALID_ALIAS", nil, "aliases must map strings to canonical IDs")
		elseif seen[alias] or not seen[canonical] then
			add(errors, "ALIAS_COLLISION", canonical, "alias collides or references an unknown ID")
		end
	end
	for _, offer in definitions do
		if type(offer) == "table" and type(offer.requirements) == "table" then
			local prior = offer.requirements.priorOfferId
			if type(prior) == "string" and not seen[prior] then
				add(errors, "UNKNOWN_PREDECESSOR", offer.id, "priorOfferId is not in the catalogue")
			end
			local priorDecision = offer.requirements.priorOfferDecision
			local proposed = if type(priorDecision) == "table" then priorDecision.proposedOfferId else nil
			if type(proposed) == "string" and not seen[proposed] then
				add(errors, "UNKNOWN_PROPOSED_PREDECESSOR", offer.id, "proposed predecessor is not in the catalogue")
			end
		end
	end
	return {
		IsValid = #errors == 0,
		Errors = errors,
		Warnings = warnings,
		Blockers = blockers,
	}
end

function Upgrades.Validate(): any
	return Upgrades.ValidateDefinitions(Upgrades.GetAll(), Upgrades.Aliases)
end

function Upgrades.PreviewDeclaredResult(statId: string, baseValue: any, offerIds: { string }): (number?, string?)
	if not finite(baseValue) or baseValue < 0 then
		return nil, "INVALID_BASE_VALUE"
	end
	if type(offerIds) ~= "table" then
		return nil, "INVALID_OFFER_IDS"
	end
	local contribution = 0
	local operation: string? = nil
	local seen: { [string]: boolean } = {}
	for _, offerId in offerIds do
		if not seen[offerId] then
			seen[offerId] = true
			local offer = Upgrades.Get(offerId)
			if offer == nil then
				return nil, "UNKNOWN_OFFER"
			end
			if offer.effect.statId == statId then
				if operation ~= nil and operation ~= offer.effect.operation then
					return nil, "INCONSISTENT_EFFECT_OPERATIONS"
				end
				operation = offer.effect.operation
				contribution += offer.effect.value
			end
		end
	end
	if operation == nil then
		return baseValue, nil
	end
	if operation == "AddBaseRelativeFraction" then
		return baseValue * (1 + contribution), nil
	elseif operation == "AddSlots" then
		return baseValue + contribution, nil
	end
	return nil, "UNSUPPORTED_OPERATION"
end

return table.freeze(Upgrades)
