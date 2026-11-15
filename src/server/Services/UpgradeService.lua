--!strict

-- Owns the upgrade-shop context and the one coherent purchase commit. Real
-- catalogue offers remain fail-closed until their 7B-1 scope, persistence and
-- effect gates are approved. Tests may inject a private ready offer and
-- ownership adapter without exposing it through the production catalogue.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local UpgradeEligibility = require(ReplicatedStorage.Shared.Utility.UpgradeEligibility)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local PlayerDataService = require(script.Parent.PlayerDataService)
local CurrencySystem = require(script.Parent.Parent.Systems.CurrencySystem)

local CONTEXT_LIFETIME_SECONDS = 120
local MAX_IDENTIFIER_LENGTH = 128
local REQUEST_CACHE_LIMIT = 64
local REQUEST_CACHE_LIFETIME_SECONDS = 180
local RATE_BURST = 6
local RATE_REFILL_PER_SECOND = 3

local UpgradeService = {}
local log = Logger.new("UpgradeService")
local started = false
local dependencies: any = nil
local contexts: { [Player]: any } = {}
local requestCaches: { [Player]: any } = {}
local rateStates: { [Player]: any } = {}
local connections: { any } = {}
local openRemote: RemoteEvent? = nil
local requestRemote: RemoteFunction? = nil
local closeRemote: RemoteEvent? = nil
local updateRemote: RemoteEvent? = nil
local requestHandler: ((Player, any) -> any)? = nil
local purchaseCommittedEvent = Instance.new("BindableEvent")
local observationListeners: { [any]: (Player, any) -> () } = {}
local observationOperationSequence = 0

local function notifyObservation(player: Player, receipt: any)
	local immutable = table.freeze(receipt)
	for _, callback in observationListeners do
		local ok, failureMessage = pcall(callback, player, immutable)
		if not ok then
			log:Warn("Upgrade observation listener failed userId=%d: %s", player.UserId, tostring(failureMessage))
		end
	end
end

local function defaultDependencies(): any
	return {
		Profile = PlayerDataService,
		Currency = CurrencySystem,
		Catalogue = Upgrades,
		Eligibility = UpgradeEligibility,
		Readiness = {
			effectReadyByOfferId = {},
			persistenceReadyByScope = {},
			cartAcquisitionByTier = {},
			rankProviderOperational = false,
		},
		WorldReady = function(_player: Player): boolean
			return false
		end,
		ResolveTarget = function(_player: Player, _offer: any): (any?, string?)
			return nil, nil
		end,
		BuildPlayerSnapshot = function(player: Player, data: any, _target: any): any
			return {
				status = "Ready",
				userId = player.UserId,
				balance = if type(data.Economy) == "table" then data.Economy.Balance else nil,
			}
		end,
		ApplyGrant = function(_data: any, _offer: any, _target: any): (boolean, string?)
			return false, "OWNERSHIP_PERSISTENCE_UNAVAILABLE"
		end,
		Now = function(): number
			return Workspace:GetServerTimeNow()
		end,
		GenerateId = function(): string
			return HttpService:GenerateGUID(false)
		end,
	}
end

local function deps(): any
	if dependencies then
		return dependencies
	end
	dependencies = defaultDependencies()
	return dependencies
end

local function failure(code: string, requestId: string?): any
	return {
		ok = false,
		outcome = "Rejected",
		code = code,
		requestId = requestId,
	}
end

local function nonEmptyBoundedString(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_IDENTIFIER_LENGTH and value:match("%c") == nil
end

local function finiteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function sameSession(left: any, right: any): boolean
	return left ~= nil
		and right ~= nil
		and left.Player == right.Player
		and left.UserId == right.UserId
		and left.Generation == right.Generation
end

local function sessionIsCurrent(player: Player, handle: any): boolean
	local profile = deps().Profile
	return profile:IsCurrentSessionHandle(handle) and sameSession(profile:GetSessionHandle(player), handle)
end

local function finitePosition(position: Vector3): boolean
	return position.X == position.X
		and math.abs(position.X) < math.huge
		and position.Y == position.Y
		and math.abs(position.Y) < math.huge
		and position.Z == position.Z
		and math.abs(position.Z) < math.huge
end

local function playerRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if
		character == nil
		or not character:IsDescendantOf(Workspace)
		or humanoid == nil
		or humanoid.Health <= 0
		or root == nil
		or not root:IsA("BasePart")
		or not finitePosition(root.Position)
	then
		return nil
	end
	return root
end

local function withinShopRange(player: Player, shop: BasePart): boolean
	local custom = deps().WithinShopRange
	if custom then
		return custom(player, shop)
	end
	local root = playerRoot(player)
	if root == nil or not shop:IsDescendantOf(Workspace) then
		return false
	end
	local localPosition = shop.CFrame:PointToObjectSpace(root.Position)
	local halfSize = shop.Size * 0.5
	local closestLocal = Vector3.new(
		math.clamp(localPosition.X, -halfSize.X, halfSize.X),
		math.clamp(localPosition.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPosition.Z, -halfSize.Z, halfSize.Z)
	)
	local closest = shop.CFrame:PointToWorldSpace(closestLocal)
	return (root.Position - closest).Magnitude
		<= InteractionConfig.SELL_INTERACTION_DISTANCE + InteractionConfig.SELL_SERVER_DISTANCE_TOLERANCE
end

local function targetIdentity(target: any): string
	if type(target) ~= "table" then
		return "none"
	end
	return tostring(target.durableCartId or target.equipmentId or "none")
end

local function termSignature(offer: any, target: any): string
	local grant = if type(offer.grant) == "table" then offer.grant else {}
	local scope = if type(offer.ownershipScope) == "table" then offer.ownershipScope else {}
	return table.concat({
		tostring(offer.id),
		tostring(offer.price),
		tostring(offer.currencyId),
		tostring(grant.kind),
		tostring(grant.trackId or grant.equipmentId),
		tostring(grant.level),
		tostring(scope.kind),
		targetIdentity(target),
	}, "|")
end

-- Canonicalize only static catalogue terms. This is a measurement identity,
-- independent of the existing purchase-context validation contract.
local function orderedTerms(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
	local entries = {}
	for _, key in keys do
		table.insert(entries, { key, orderedTerms(value[key]) })
	end
	return entries
end

local function measurementTermsVersion(offer: any, target: any): string
	return HttpService:JSONEncode(orderedTerms({
		id = offer.id,
		price = offer.price,
		currencyId = offer.currencyId,
		grant = offer.grant,
		ownershipScope = offer.ownershipScope,
		applicability = offer.applicability,
		requirements = offer.requirements,
		effect = offer.effect,
		definitionStatus = offer.definitionStatus,
		releaseStatus = offer.releaseStatus,
		effectStatus = offer.effectStatus,
		targetKey = targetIdentity(target),
	}))
end

local function measurementKey(offer: any, target: any): string
	return tostring(offer.id) .. "|" .. targetIdentity(target) .. "|" .. measurementTermsVersion(offer, target)
end

local function requestSignature(contextId: string, offerId: string, _target: any): string
	-- The opaque context ID already binds the server-resolved scope target. This
	-- keeps an exact successful retry readable after its menu context closes.
	return contextId .. "|" .. offerId
end

local function pruneRequestCache(player: Player, currentTime: number)
	local cache = requestCaches[player]
	if cache == nil then
		return
	end
	while #cache.Order > 0 do
		local requestId = cache.Order[1]
		local entry = cache.ById[requestId]
		if
			entry ~= nil
			and currentTime - entry.CreatedAt <= REQUEST_CACHE_LIFETIME_SECONDS
			and #cache.Order <= REQUEST_CACHE_LIMIT
		then
			break
		end
		table.remove(cache.Order, 1)
		cache.ById[requestId] = nil
	end
end

local function requestCache(player: Player): any
	local cache = requestCaches[player]
	if cache == nil then
		cache = { ById = {}, Order = {} }
		requestCaches[player] = cache
	end
	pruneRequestCache(player, deps().Now())
	return cache
end

local function rememberResult(player: Player, requestId: string, signature: string, result: any, session: any)
	local cache = requestCache(player)
	if cache.ById[requestId] == nil then
		table.insert(cache.Order, requestId)
	end
	cache.ById[requestId] = {
		Signature = signature,
		Result = result,
		CreatedAt = deps().Now(),
		Session = session,
	}
	pruneRequestCache(player, deps().Now())
end

local function cachedResult(player: Player, requestId: string, signature: string): any?
	local entry = requestCache(player).ById[requestId]
	if entry == nil then
		return nil
	end
	if entry.Signature ~= signature then
		return failure("REQUEST_ID_MISMATCH", requestId)
	end
	local copy = table.clone(entry.Result)
	copy.duplicate = true
	return copy
end

local function consumeRateToken(player: Player): boolean
	local currentTime = deps().Now()
	local state = rateStates[player]
	if state == nil then
		state = { Tokens = RATE_BURST, LastAt = currentTime }
		rateStates[player] = state
	end
	local elapsed = math.max(0, currentTime - state.LastAt)
	state.LastAt = currentTime
	state.Tokens = math.min(RATE_BURST, state.Tokens + elapsed * RATE_REFILL_PER_SECOND)
	if state.Tokens < 1 then
		return false
	end
	state.Tokens -= 1
	return true
end

local function currentOffer(offerId: string): any?
	return deps().Catalogue.Get(offerId)
end

local function buildEvaluation(player: Player, data: any, offer: any, target: any): (any, any)
	local snapshot = deps().BuildPlayerSnapshot(player, data, target)
	local evaluation = deps().Eligibility.EvaluateOffer(offer, snapshot, target, deps().Readiness)
	return evaluation, snapshot
end

local function cardFor(player: Player, data: any, offer: any, target: any): any
	local evaluation = buildEvaluation(player, data, offer, target)
	local card = deps().Eligibility.DescribeOffer(offer, evaluation, target)
	return {
		offerId = card.offerId,
		title = card.title,
		effectSummary = card.effectSummary,
		ownershipSummary = card.ownershipSummary,
		price = card.price,
		priceText = card.priceText,
		currencyId = card.currencyId,
		requirementLines = table.clone(card.requirementLines),
		state = card.state,
		primaryExplanation = card.primaryExplanation,
		actionLabel = card.actionLabel,
		canActivate = card.canActivate,
	}
end

local function invalidateContext(player: Player, code: string)
	local context = contexts[player]
	if context == nil then
		return
	end
	contexts[player] = nil
	log:Debug("UpgradeContextInvalidated userId=%d contextId=%s code=%s", player.UserId, context.Id, code)
end

function UpgradeService:OpenShop(player: Player, shop: BasePart): any
	local d = deps()
	if player.Parent ~= Players or not d.Profile:IsWritable(player) then
		return failure("PROFILE_NOT_READY")
	end
	if d.WorldReady(player) ~= true then
		return failure("WORLD_NOT_READY")
	end
	if not shop:IsDescendantOf(Workspace) or not withinShopRange(player, shop) then
		return failure("TOO_FAR_AWAY")
	end
	local session = d.Profile:GetSessionHandle(player)
	local data = d.Profile:GetReadableData(player)
	if session == nil or data == nil then
		return failure("PROFILE_NOT_READY")
	end
	local contextId = d.GenerateId()
	local context = {
		Id = contextId,
		Player = player,
		Session = session,
		Shop = shop,
		ExpiresAt = d.Now() + CONTEXT_LIFETIME_SECONDS,
		Terms = {},
		PresentationEvents = {},
		PresentationCount = 0,
		PresentationTokens = RATE_BURST,
		PresentationLastAt = d.Now(),
	}
	local cards = {}
	for _, offer in d.Catalogue.GetAll() do
		local target, targetReason = d.ResolveTarget(player, offer)
		local card = cardFor(player, data, offer, target)
		if targetReason ~= nil and card.primaryExplanation == nil then
			card.primaryExplanation = targetReason
			card.state = "Unavailable"
			card.canActivate = false
			card.actionLabel = "Unavailable"
		end
		context.Terms[offer.id] = {
			Offer = offer,
			Target = target,
			Signature = termSignature(offer, target),
			MeasurementKey = measurementKey(offer, target),
		}
		table.insert(cards, card)
	end
	contexts[player] = context
	local balance = data.Economy and data.Economy.Balance
	local payload = {
		contextId = contextId,
		expiresAtServerTime = context.ExpiresAt,
		balance = if finiteNonNegative(balance) then balance else nil,
		offers = cards,
	}
	if openRemote then
		openRemote:FireClient(player, payload)
	end
	local offerKeys = {}
	for _, offer in d.Catalogue.GetAll() do
		local term = context.Terms[offer.id]
		if term then
			table.insert(offerKeys, term.MeasurementKey)
		end
	end
	notifyObservation(player, {
		kind = "ContextIssued",
		eventId = contextId,
		at = d.Now(),
		contextId = contextId,
		sessionGeneration = session.Generation,
		offerKeys = table.freeze(offerKeys),
	})
	log:Info("UpgradeShopOpened userId=%d contextId=%s offers=%d", player.UserId, contextId, #cards)
	return { ok = true, code = "OPENED", payload = payload }
end

function UpgradeService:GetMeasurementOffers(player: Player): { any }
	local d = deps()
	local data = d.Profile:GetReadableData(player)
	if data == nil then
		return {}
	end
	local result = {}
	for _, offer in d.Catalogue.GetAll() do
		local target, targetReason = d.ResolveTarget(player, offer)
		local snapshot = d.BuildPlayerSnapshot(player, data, target)
		local decomposition = d.Eligibility.DecomposeOffer(offer, snapshot, target, d.Readiness)
		table.insert(
			result,
			table.freeze({
				offerId = offer.id,
				targetKey = targetIdentity(target),
				termsVersion = measurementTermsVersion(offer, target),
				offerKey = measurementKey(offer, target),
				price = offer.price,
				owned = decomposition.owned,
				fundsSufficient = decomposition.fundsSufficient,
				ready = decomposition.ready and targetReason == nil,
				prerequisitesSatisfied = decomposition.prerequisitesSatisfied,
				pathBlocked = decomposition.pathBlocked or targetReason ~= nil,
				primaryReason = targetReason or decomposition.primaryReason,
			})
		)
	end
	return result
end

local function validateContext(player: Player, contextId: string): (any?, string?)
	local context = contexts[player]
	if context == nil or context.Id ~= contextId then
		return nil, "INVALID_CONTEXT"
	end
	if deps().Now() >= context.ExpiresAt then
		invalidateContext(player, "CONTEXT_EXPIRED")
		return nil, "CONTEXT_EXPIRED"
	end
	if not sessionIsCurrent(player, context.Session) or not deps().Profile:IsWritable(player) then
		invalidateContext(player, "SESSION_CHANGED")
		return nil, "SESSION_CHANGED"
	end
	if deps().WorldReady(player) ~= true then
		invalidateContext(player, "WORLD_NOT_READY")
		return nil, "WORLD_NOT_READY"
	end
	if not context.Shop:IsDescendantOf(Workspace) or not withinShopRange(player, context.Shop) then
		return nil, "TOO_FAR_AWAY"
	end
	return context, nil
end

local function rejectionFromEvaluation(evaluation: any): string
	if evaluation.outcome == "Owned" then
		return "ALREADY_OWNED"
	elseif evaluation.outcome == "InsufficientFunds" then
		return "INSUFFICIENT_FUNDS"
	elseif evaluation.primaryReason and evaluation.primaryReason.code then
		return evaluation.primaryReason.code
	end
	return string.upper(tostring(evaluation.outcome or "UNAVAILABLE"))
end

function UpgradeService:Purchase(player: Player, payload: any): any
	if type(payload) ~= "table" then
		return failure("INVALID_REQUEST")
	end
	local contextId = payload.contextId
	local requestId = payload.requestId
	local offerId = payload.offerId
	if
		not nonEmptyBoundedString(contextId)
		or not nonEmptyBoundedString(requestId)
		or not nonEmptyBoundedString(offerId)
	then
		return failure("INVALID_REQUEST", if type(requestId) == "string" then requestId else nil)
	end
	local contextForSignature = contexts[player]
	local target = if contextForSignature and contextForSignature.Terms[offerId]
		then contextForSignature.Terms[offerId].Target
		else nil
	local signature = requestSignature(contextId, offerId, target)
	local duplicate = cachedResult(player, requestId, signature)
	if duplicate then
		log:Debug("UpgradePurchaseDuplicate userId=%d offerId=%s requestId=%s", player.UserId, offerId, requestId)
		return duplicate
	end
	if not consumeRateToken(player) then
		local result = failure("RATE_LIMITED", requestId)
		rememberResult(player, requestId, signature, result, nil)
		return result
	end
	local context, contextReason = validateContext(player, contextId)
	if context == nil then
		local result = failure(contextReason or "INVALID_CONTEXT", requestId)
		rememberResult(player, requestId, signature, result, nil)
		return result
	end
	local presented = context.Terms[offerId]
	local offer = currentOffer(offerId)
	if presented == nil or offer == nil then
		local result = failure("UNKNOWN_OFFER", requestId)
		rememberResult(player, requestId, signature, result, context.Session)
		return result
	end
	if termSignature(offer, presented.Target) ~= presented.Signature then
		local result = failure("OFFER_CHANGED", requestId)
		rememberResult(player, requestId, signature, result, context.Session)
		return result
	end

	local d = deps()
	local data = d.Profile:GetWritableData(player)
	if data == nil then
		local result = failure("PROFILE_NOT_READY", requestId)
		rememberResult(player, requestId, signature, result, context.Session)
		return result
	end
	local evaluation = buildEvaluation(player, data, offer, presented.Target)
	if evaluation.outcome ~= "Available" then
		local result = failure(rejectionFromEvaluation(evaluation), requestId)
		rememberResult(player, requestId, signature, result, context.Session)
		log:Info(
			"UpgradePurchaseRejected userId=%d offerId=%s requestId=%s code=%s",
			player.UserId,
			offerId,
			requestId,
			result.code
		)
		return result
	end

	local balanceBefore: number? = nil
	local committedAt: number? = nil
	local commit = d.Profile:CommitMutation(player, function(currentData)
		local currentEvaluation = buildEvaluation(player, currentData, offer, presented.Target)
		if currentEvaluation.outcome ~= "Available" then
			return false, failure(rejectionFromEvaluation(currentEvaluation), requestId)
		end
		local prepared = d.Currency:PrepareSpend(currentData, offer.price)
		if prepared.ok ~= true then
			return false, failure(prepared.code or "INVALID_COST", requestId)
		end
		balanceBefore = currentData.Economy.Balance
		local granted, grantReason = d.ApplyGrant(currentData, offer, presented.Target)
		if granted ~= true then
			return false, failure(grantReason or "GRANT_REJECTED", requestId)
		end
		currentData.Economy.Balance = prepared.balance
		committedAt = d.Now()
		return true,
			{
				ok = true,
				outcome = "Accepted",
				code = "PURCHASE_ACCEPTED",
				requestId = requestId,
				offerId = offer.id,
				chargedAmount = offer.price,
				balance = prepared.balance,
				persistence = "Pending",
			}
	end)
	if type(commit) ~= "table" or commit.ok ~= true or commit.committed ~= true then
		local result = if type(commit) == "table" then commit else failure("MUTATION_FAILED", requestId)
		result.requestId = requestId
		result.outcome = result.outcome or "Rejected"
		rememberResult(player, requestId, signature, result, context.Session)
		return result
	end
	commit.commitRevision = commit.revision
	commit.persistence = "Pending"
	rememberResult(player, requestId, signature, commit, context.Session)
	observationOperationSequence += 1
	local committedMeasurementKey = measurementKey(offer, presented.Target)
	local remembered = requestCaches[player] and requestCaches[player].ById[requestId]
	if remembered then
		remembered.MeasurementKey = committedMeasurementKey
		remembered.CommittedAt = committedAt
		remembered.OperationSequence = observationOperationSequence
	end
	-- Capture committed values before any effect listener or save can run. Direct
	-- server purchases and client requests use this same canonical receipt.
	local committedReceipt = {
		kind = "PurchaseCommitted",
		eventId = requestId,
		at = committedAt,
		contextId = context.Id,
		requestId = requestId,
		offerId = offer.id,
		offerKey = committedMeasurementKey,
		targetKey = targetIdentity(presented.Target),
		termsVersion = measurementTermsVersion(offer, presented.Target),
		price = offer.price,
		currencyId = offer.currencyId,
		ownershipScope = offer.ownershipScope.kind,
		chargedAmount = commit.chargedAmount,
		balanceBefore = balanceBefore,
		balanceAfter = commit.balance,
		commitRevision = commit.revision,
		sessionGeneration = context.Session.Generation,
		operationSequence = observationOperationSequence,
		ready = true,
		prerequisitesSatisfied = true,
		fundsSufficient = true,
		accepted = true,
		persistence = "Pending",
	}
	notifyObservation(player, committedReceipt)
	pcall(d.Currency.SyncBalance, d.Currency, player)
	-- Effects rederive from committed ownership outside the profile mutation. A
	-- listener failure cannot repeat, roll back, or partially re-run the purchase.
	purchaseCommittedEvent:Fire(player, offer, presented.Target, commit.revision, committedReceipt)
	local saveRequest = if d.Profile.RequestDebouncedSave
		then d.Profile:RequestDebouncedSave(player, "UpgradePurchase:" .. offer.id)
		else d.Profile:RequestSave(player, "UpgradePurchase:" .. offer.id)
	if type(saveRequest) ~= "table" or saveRequest.ok ~= true then
		commit.persistence = "Delayed"
	end
	log:Info(
		"UpgradePurchaseCommitted userId=%d offerId=%s requestId=%s revision=%d",
		player.UserId,
		offer.id,
		requestId,
		commit.revision
	)
	return table.clone(commit)
end

function UpgradeService:GetRequestStatus(player: Player, payload: any): any
	if type(payload) ~= "table" then
		return failure("INVALID_REQUEST")
	end
	local contextId, requestId, offerId = payload.contextId, payload.requestId, payload.offerId
	if
		not nonEmptyBoundedString(contextId)
		or not nonEmptyBoundedString(requestId)
		or not nonEmptyBoundedString(offerId)
	then
		return failure("INVALID_REQUEST")
	end
	local context = contexts[player]
	local target = if context and context.Terms[offerId] then context.Terms[offerId].Target else nil
	local signature = requestSignature(contextId, offerId, target)
	local cached = cachedResult(player, requestId, signature)
	return cached or failure("REQUEST_STATUS_UNKNOWN", requestId)
end

function UpgradeService:SubscribePurchaseCommitted(
	callback: (Player, any, any, number, any?) -> ()
): RBXScriptConnection
	return purchaseCommittedEvent.Event:Connect(callback)
end

function UpgradeService:SubscribeObservations(callback: (Player, any) -> ()): any
	local connection = {}
	observationListeners[connection] = callback
	function connection.Disconnect()
		observationListeners[connection] = nil
	end
	return connection
end

function UpgradeService:ObservePresentation(player: Player, payload: any): any
	if type(payload) ~= "table" or not nonEmptyBoundedString(payload.contextId) then
		return failure("INVALID_REQUEST")
	end
	for key in payload do
		if
			key ~= "operation"
			and key ~= "contextId"
			and key ~= "kind"
			and key ~= "inputCategory"
			and key ~= "offerId"
		then
			return failure("INVALID_REQUEST")
		end
	end
	if payload.operation ~= nil and payload.operation ~= "Presentation" then
		return failure("INVALID_REQUEST")
	end
	local kind = payload.kind
	if kind ~= "MenuRendered" and kind ~= "OfferInspected" then
		return failure("INVALID_PRESENTATION_EVENT")
	end
	if
		(kind == "MenuRendered" and payload.offerId ~= nil)
		or (kind == "OfferInspected" and not nonEmptyBoundedString(payload.offerId))
	then
		return failure("INVALID_REQUEST")
	end
	local inputCategory = payload.inputCategory
	local validInput = inputCategory == "Desktop"
		or inputCategory == "Touch"
		or inputCategory == "Gamepad"
		or inputCategory == "Hybrid"
		or inputCategory == "Unknown"
	if not validInput then
		return failure("INVALID_INPUT_CATEGORY")
	end
	local context = contexts[player]
	if context == nil or context.Id ~= payload.contextId then
		return failure("INVALID_CONTEXT")
	end
	-- Presentation has its own bounded budget; an analytics burst cannot consume
	-- the player's gameplay purchase tokens. Duplicates still consume this budget.
	local currentTime = deps().Now()
	local elapsed = math.max(0, currentTime - context.PresentationLastAt)
	context.PresentationLastAt = currentTime
	context.PresentationTokens = math.min(RATE_BURST, context.PresentationTokens + elapsed * RATE_REFILL_PER_SECOND)
	if context.PresentationTokens < 1 or context.PresentationCount >= 64 then
		return failure("RATE_LIMITED")
	end
	context.PresentationTokens -= 1
	context.PresentationCount += 1
	local validatedContext, contextReason = validateContext(player, payload.contextId)
	if validatedContext == nil then
		return failure(contextReason or "INVALID_CONTEXT")
	end
	local term = nil
	if kind == "OfferInspected" then
		term = context.Terms[payload.offerId]
		if term == nil then
			return failure("UNKNOWN_OFFER")
		end
	end
	local dedupKey = kind .. ":" .. tostring(payload.offerId or "menu")
	if not context.PresentationEvents[dedupKey] then
		context.PresentationEvents[dedupKey] = true
		notifyObservation(player, {
			kind = kind,
			eventId = context.Id .. ":" .. dedupKey,
			at = deps().Now(),
			contextId = context.Id,
			sessionGeneration = context.Session.Generation,
			offerId = payload.offerId,
			offerKey = if term then term.MeasurementKey else nil,
			inputCategory = inputCategory,
		})
	end
	return { ok = true, code = "RECORDED" }
end

function UpgradeService:HandleRequest(player: Player, payload: any): any
	if type(payload) ~= "table" then
		return failure("INVALID_REQUEST")
	end
	if payload.operation == "Purchase" then
		local context = contexts[player]
		local validObservation = context ~= nil
			and context.Id == payload.contextId
			and nonEmptyBoundedString(payload.contextId)
			and nonEmptyBoundedString(payload.requestId)
			and nonEmptyBoundedString(payload.offerId)
			and sessionIsCurrent(player, context.Session)
		local term = if validObservation then context.Terms[payload.offerId] else nil
		local cache = requestCaches[player]
		local replayed = cache ~= nil and cache.ById[payload.requestId] ~= nil
		if term and not replayed then
			notifyObservation(player, {
				kind = "PurchaseAttempt",
				eventId = payload.requestId,
				at = deps().Now(),
				contextId = payload.contextId,
				requestId = payload.requestId,
				offerId = payload.offerId,
				offerKey = term.MeasurementKey,
				sessionGeneration = context.Session.Generation,
			})
		end
		local result = self:Purchase(player, payload)
		if term and not replayed and result.outcome ~= "Accepted" then
			notifyObservation(player, {
				kind = "PurchaseResult",
				eventId = payload.requestId,
				at = deps().Now(),
				contextId = payload.contextId,
				requestId = payload.requestId,
				offerId = payload.offerId,
				offerKey = term.MeasurementKey,
				accepted = false,
				code = result.code,
				sessionGeneration = context.Session.Generation,
			})
		end
		return result
	elseif payload.operation == "Status" then
		return self:GetRequestStatus(player, payload)
	elseif payload.operation == "Presentation" then
		return self:ObservePresentation(player, payload)
	end
	return failure("INVALID_OPERATION")
end

function UpgradeService:CloseShop(player: Player, contextId: any): boolean
	local context = contexts[player]
	if context == nil then
		return false
	end
	if contextId ~= nil and contextId ~= context.Id then
		return false
	end
	invalidateContext(player, "CLIENT_CLOSED")
	return true
end

local function ensureRemote(className: string, name: string): Instance
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = remotes
	end
	assert(remote.ClassName == className, name .. " must be a " .. className)
	return remote
end

local function onSaveConfirmed(player: Player, savedRevision: number, _currentRevision: number)
	local cache = requestCaches[player]
	if cache == nil then
		return
	end
	local currentSession = deps().Profile:GetSessionHandle(player)
	for _, entry in cache.ById do
		local result = entry.Result
		if
			sameSession(entry.Session, currentSession)
			and result.outcome == "Accepted"
			and type(result.commitRevision) == "number"
			and savedRevision >= result.commitRevision
			and result.persistence ~= "Confirmed"
		then
			result.persistence = "Confirmed"
			if updateRemote then
				updateRemote:FireClient(player, {
					kind = "PurchasePersistence",
					requestId = result.requestId,
					offerId = result.offerId,
					commitRevision = result.commitRevision,
					persistence = "Confirmed",
				})
			end
			log:Info(
				"UpgradePurchaseSaveConfirmed userId=%d offerId=%s requestId=%s revision=%d",
				player.UserId,
				result.offerId,
				result.requestId,
				result.commitRevision
			)
			if entry.MeasurementKey then
				-- Cache iteration is not purchase order. Sequence this observation at
				-- delivery so a covering save can confirm every committed purchase.
				observationOperationSequence += 1
				notifyObservation(player, {
					kind = "PurchaseSaveConfirmed",
					eventId = tostring(result.requestId) .. ":saved",
					at = deps().Now(),
					requestId = result.requestId,
					offerId = result.offerId,
					offerKey = entry.MeasurementKey,
					commitRevision = result.commitRevision,
					sessionGeneration = entry.Session.Generation,
					operationSequence = observationOperationSequence,
					purchaseOperationSequence = entry.OperationSequence,
					committedAt = entry.CommittedAt,
				})
			end
		end
	end
end

function UpgradeService:Init(options: any?)
	assert(not started, "Cannot replace UpgradeService dependencies after Start")
	local base = defaultDependencies()
	for key, value in options or {} do
		base[key] = value
	end
	dependencies = base
end

function UpgradeService:Start(options: any?): boolean
	if started then
		return false
	end
	if options or dependencies == nil then
		self:Init(options)
	end
	started = true
	openRemote = ensureRemote("RemoteEvent", RemoteNames.OpenCartUpgradeShop) :: RemoteEvent
	requestRemote = ensureRemote("RemoteFunction", RemoteNames.CartUpgradeShopRequest) :: RemoteFunction
	closeRemote = ensureRemote("RemoteEvent", RemoteNames.CloseCartUpgradeShop) :: RemoteEvent
	updateRemote = ensureRemote("RemoteEvent", RemoteNames.CartUpgradeShopUpdate) :: RemoteEvent
	requestHandler = function(player, payload)
		return UpgradeService:HandleRequest(player, payload)
	end
	requestRemote.OnServerInvoke = requestHandler
	table.insert(
		connections,
		(closeRemote :: RemoteEvent).OnServerEvent:Connect(function(player, contextId)
			UpgradeService:CloseShop(player, contextId)
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			invalidateContext(player, "PLAYER_REMOVING")
			requestCaches[player] = nil
			rateStates[player] = nil
		end)
	)
	local saveSignal = deps().Profile.SubscribeSaveConfirmed
	if saveSignal then
		table.insert(connections, deps().Profile:SubscribeSaveConfirmed(onSaveConfirmed))
	end
	return true
end

function UpgradeService:Stop()
	if requestRemote and requestRemote.OnServerInvoke == requestHandler then
		requestRemote.OnServerInvoke = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(contexts)
	table.clear(requestCaches)
	table.clear(rateStates)
	openRemote, requestRemote, closeRemote, updateRemote, requestHandler = nil, nil, nil, nil, nil
	dependencies = nil
	started = false
	observationOperationSequence = 0
end

function UpgradeService:_TestConfirmSave(player: Player, savedRevision: number)
	onSaveConfirmed(player, savedRevision, savedRevision)
end

function UpgradeService:_TestGetContext(player: Player): any?
	return contexts[player]
end

return UpgradeService
