--!strict
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Marketplace = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local Config = require(RS.Shared.Config.Phase13Commerce)
local Rules = require(RS.Shared.Utility.Phase13CommerceRules)
local Capacity = require(RS.Shared.Utility.Phase13CommerceCapacity)
local PhaseRules = require(RS.Shared.Utility.Phase13Rules)
local Profiles = require(script.Parent.PlayerDataService)
local Transactions = require(script.Parent.Phase13Service)
local Analytics = require(script.Parent.Phase13AnalyticsService)
local Http = game:GetService("HttpService")
local CampFlags = require(RS.Shared.Config.CampReworkFlags)
-- Camp Rework pass rows carry requiresGate; they are invisible while their gate is off.
local function gateCatalogue(config)
	local open = {
		CampReworkV1Enabled = CampFlags.CampRework(),
		TrainingV1Enabled = CampFlags.Training(),
	}
	local passes = {}
	for _, row in config.Passes do
		if row.requiresGate == nil or open[row.requiresGate] == true then
			table.insert(passes, row)
		end
	end
	local copy = table.clone(config)
	copy.Passes = passes
	return copy
end
local DefaultCatalogue = gateCatalogue(Config)
local Service = {}
local offerSessions = {}
local grantSeen = {}
local activeCatalogue = DefaultCatalogue
local promptPending = {}
local nextOwnershipCheck = 0
local deps: any = { Profile = Profiles, Transactions = Transactions, Marketplace = Marketplace }
local verified = {}
local prices = {}
local cache = {}
local refreshing = {}
local started = false
local confirmedConnection = nil
local recoveryByUserId = {}
local recoveryUsers = 0
local recoveryFullWarnAt = -math.huge
local recoveryCursor = 1
local MAX_RECOVERY_USERS, MAX_RECOVERY_RECEIPTS = 128, 32
local function timestamp()
	return os.time()
end
local function publish(player)
	local data = deps.Profile:GetReadableData(player)
	if not data or not data.Commerce then
		return
	end
	for key, value in data.Commerce.Entitlements do
		player:SetAttribute("Entitlement_" .. key, value)
	end
end
local function configured(row)
	return type(row.platformId) == "number"
		and row.platformId > 0
		and row.platformId % 1 == 0
		and row.verifiedUniverseId == (deps.UniverseId or game.GameId)
		and (deps.UniverseId or game.GameId) == activeCatalogue.UniverseId
end
local function find(id)
	for _, group in { activeCatalogue.Passes, activeCatalogue.Products } do
		for _, row in group do
			if row.id == id then
				return row, group == activeCatalogue.Passes
			end
		end
	end
	return nil, nil
end
local function telemetry(method, ...)
	local adapter = deps.Telemetry or Analytics
	local callback = adapter[method]
	if callback then
		pcall(callback, adapter, ...)
	end
end
local recoveryCategories = {
	PROFILE_STORAGE_HEADROOM = "PaidReceiptStorageFull",
	PAID_LEDGER_FULL = "PaidReceiptLedgerFull",
	PAID_LEDGER_REQUIRES_ARCHIVAL = "PaidReceiptLedgerFull",
	BALANCE_LIMIT = "PaidReceiptBalanceFull",
	AWAITING_COVERING_SAVE = "PaidReceiptAwaitingSave",
	BUSY = "PaidReceiptBusy",
	PROFILE_NOT_READY = "PaidReceiptUnready",
	RECEIPT_ID_MISMATCH = "PaidReceiptIdentityMismatch",
	UNKNOWN_PRODUCT = "PaidReceiptUnknownProduct",
	RECOVERY_QUEUE_FULL = "PaidReceiptQueueFull",
	ENVELOPE_MEASUREMENT_UNAVAILABLE = "PaidReceiptMeasurementUnavailable",
	PROFILE_ENCODING_FAILED = "PaidReceiptMeasurementUnavailable",
}
local function recoveryState(userId)
	local state = recoveryByUserId[userId]
	if not state and recoveryUsers < MAX_RECOVERY_USERS then
		state = { receipts = {}, order = {}, cursor = 1, count = 0, since = os.clock(), reason = "PROFILE_NOT_READY" }
		recoveryByUserId[userId] = state
		recoveryUsers += 1
	end
	return state
end
local function pendingReceipt(player, receipt, reason)
	local state = recoveryState(receipt.PlayerId)
	if not state then
		if os.clock() - recoveryFullWarnAt >= 60 then
			recoveryFullWarnAt = os.clock()
			warn("[Phase13Commerce] Paid recovery cache full; unresolved platform receipt remains unacknowledged")
		end
		return
	end
	if not state.receipts[receipt.PurchaseId] then
		if state.count < MAX_RECOVERY_RECEIPTS then
			state.receipts[receipt.PurchaseId] = table.freeze({
				PlayerId = receipt.PlayerId,
				ProductId = receipt.ProductId,
				PurchaseId = receipt.PurchaseId,
			})
			table.insert(state.order, receipt.PurchaseId)
			state.count += 1
		else
			reason = "RECOVERY_QUEUE_FULL"
			state.untracked = true
		end
	end
	local changed = state.reason ~= reason
	state.reason = reason
	state.nextAttemptAt = os.clock()
		+ (
			if reason == "PROFILE_STORAGE_HEADROOM"
					or reason == "PAID_LEDGER_FULL"
					or reason == "BALANCE_LIMIT"
				then 60
				else 5
		)
	if changed or not state.reportedAt or os.clock() - state.reportedAt >= 60 then
		state.reportedAt = os.clock()
		warn(
			string.format(
				"[Phase13Commerce] Unresolved paid delivery UserId=%d reason=%s; no purchase acknowledged",
				receipt.PlayerId,
				reason
			)
		)
		if player then
			telemetry("Record", player, "TransactionRecovery", 1, {
				category = recoveryCategories[reason] or "PaidReceiptUnready",
				result = "Pending",
			})
		end
	end
	if player and player.SetAttribute then
		player:SetAttribute("CommerceRecoveryReason", reason)
		player:SetAttribute("CommerceRecoveryPending", state.count)
	end
end
local function resolvedReceipt(player, purchaseId)
	local state = recoveryByUserId[player.UserId]
	if not state or not state.receipts[purchaseId] then
		return
	end
	state.receipts[purchaseId] = nil
	local index = table.find(state.order, purchaseId)
	if index then
		table.remove(state.order, index)
	end
	state.count -= 1
	telemetry("Record", player, "TransactionRecovery", 1, { category = "PaidReceiptRecovered", result = "Success" })
	if state.count == 0 and not state.untracked then
		recoveryByUserId[player.UserId] = nil
		recoveryUsers -= 1
	end
	if player.SetAttribute then
		player:SetAttribute("CommerceRecoveryPending", state.count)
		player:SetAttribute(
			"CommerceRecoveryReason",
			if state.count == 0 and not state.untracked then nil else state.reason
		)
	end
end
function Service:GetRecoveryStatus(userId)
	local state = recoveryByUserId[userId]
	return if state
		then {
			pendingCount = state.count,
			untrackedPlatformRetries = state.untracked == true,
			reason = state.reason,
			ageSeconds = math.max(0, os.clock() - state.since),
		}
		else { pendingCount = 0, reason = "NONE", ageSeconds = 0, untrackedPlatformRetries = false }
end
-- A projection executes only pure transitions on a private copy. It includes the
-- permanent row, predicted revision, actual journal append and retained envelope.
function Service:CheckHeadroom(player, row, isPass, prompting, receipt)
	local data = deps.Profile:GetReadableData(player)
	if not data then
		return { ok = false, code = "PROFILE_NOT_READY" }
	end
	if not isPass then
		local ledger = Capacity.CheckLedger(data, prompting == true)
		if not ledger.ok then
			return ledger
		end
	end
	if not deps.Profile.GetSaveEnvelope then
		return { ok = false, code = "ENVELOPE_MEASUREMENT_UNAVAILABLE" }
	end
	local projected = Capacity.Copy(data)
	local saved = if deps.Profile.GetSavedRevision then deps.Profile:GetSavedRevision(player) or 0 else 0
	Rules.CompactPaidDiagnostics(projected, saved)
	local revision = (deps.Profile:GetCurrentRevision(player) or 0) + 1
	local id = if isPass then "pass:" .. row.id else (receipt and receipt.PurchaseId or string.rep('"', 200))
	local operationId = if isPass then id else "paid:" .. id
	local at = if prompting then 9007199254740991 else timestamp()
	local ok, result
	if isPass then
		ok, result = Rules.GrantPass(projected, row.id, at)
	else
		ok, result = Rules.GrantReceipt(projected, id, row.platformId, row.amount, at, activeCatalogue.Version, row.currency)
		if ok then
			projected.Commerce.ProcessedReceipts[id].CommitRevision = revision
		end
	end
	if not ok then
		return { ok = false, code = result.code }
	end
	PhaseRules.AppendOperation(projected, operationId, if isPass then "PassGrant" else "PaidCash", revision, at, result)
	local envelope = deps.Profile:GetSaveEnvelope(player, projected, revision)
	return Capacity.MeasureEnvelope(
		envelope,
		if prompting then Capacity.PromptMarginBytes else Capacity.DeliveryMarginBytes
	)
end
function Service:RecoverPending(player, scheduled)
	local state = recoveryByUserId[player.UserId]
	if
		not state
		or not deps.Profile:GetReadableData(player)
		or (scheduled == true and state.nextAttemptAt and os.clock() < state.nextAttemptAt)
	then
		return false
	end
	local work = {}
	for _ = 1, math.min(2, #state.order) do
		if state.cursor > #state.order then
			state.cursor = 1
		end
		local receipt = state.receipts[state.order[state.cursor]]
		state.cursor += 1
		if receipt then
			table.insert(work, receipt)
		end
	end
	for _, receipt in work do
		self:ProcessReceipt(receipt)
	end
	return #work > 0
end
function Service:ObserveOffers(player, group)
	if group ~= "Passes" and group ~= "Cash" then
		return { ok = false, code = "INVALID_OFFER_GROUP" }
	end
	if not deps.Profile:GetReadableData(player) then
		return { ok = false, code = "NOT_READY" }
	end
	offerSessions[player] = offerSessions[player] or {}
	local prior = offerSessions[player][group]
	if prior and os.clock() - prior.at < 60 then
		return { ok = true, code = "ALREADY_OBSERVED" }
	end
	local session = { id = Http:GenerateGUID(false), at = os.clock(), prompted = false }
	offerSessions[player][group] = session
	telemetry(
		"Record",
		player,
		"OfferViewed",
		1,
		{ category = if group == "Passes" then "Pass" else "Cash", result = "Untrusted" }
	)
	telemetry("Funnel", player, "Commerce", 1, session.id)
	return { ok = true, code = "OBSERVED" }
end
local function durableGrant(player, group, identity, offerId)
	grantSeen[player] = grantSeen[player] or {}
	if grantSeen[player][identity] then
		return
	end
	local count = 0
	for _ in grantSeen[player] do
		count += 1
	end
	if count >= 512 then
		return
	end
	grantSeen[player][identity] = true
	local session = offerSessions[player] and offerSessions[player][group]
	if session and session.prompted and session.offerId == offerId then
		telemetry("Funnel", player, "Commerce", 3, session.id)
	end
end
-- A new covering-save confirmation can arrive before the platform retries its
-- receipt callback. Observe it independently; an already-durable replay is only
-- acknowledged and cannot complete a later offer's funnel.
local function observeConfirmedCashGrant(player, response)
	if
		type(response) ~= "table"
		or response.kind ~= "PaidCash"
		or response.state ~= "Confirmed"
		or type(response.result) ~= "table"
		or type(response.operationId) ~= "string"
	then
		return
	end
	for _, row in activeCatalogue.Products do
		if configured(row) and row.platformId == response.result.productId then
			durableGrant(player, "Cash", response.operationId, row.id)
			local purchaseId = response.operationId:match("^paid:(.+)$")
			local data = deps.Profile:GetReadableData(player)
			local exact = purchaseId and data and data.Commerce.ProcessedReceipts[purchaseId]
			if
				exact
				and exact.ProductId == row.platformId
				and exact.Amount == row.amount
				and deps.Profile:IsRevisionConfirmed(player, exact.CommitRevision or math.huge)
			then
				resolvedReceipt(player, purchaseId)
			end
			return
		end
	end
end
local function bindConfirmedObserver()
	if confirmedConnection then
		confirmedConnection.Disconnect()
		confirmedConnection = nil
	end
	if deps.Transactions.SubscribeConfirmed then
		confirmedConnection = deps.Transactions:SubscribeConfirmed(observeConfirmedCashGrant)
	end
end

function Service:GetCatalogue(player)
	local data = deps.Profile:GetReadableData(player)
	local result = {
		Passes = {},
		Cash = {},
		Cosmetics = activeCatalogue.Cosmetics,
		disclosure = activeCatalogue.CashDisclosure,
		stormDisclosure = activeCatalogue.StormDisclosure,
		readiness = if activeCatalogue.PaidCapacityRecoveryReady == true then "Configured" else "Blocked",
		readinessReason = if activeCatalogue.PaidCapacityRecoveryReady ~= true
			then (activeCatalogue.ReadinessReason or "PAID_CAPACITY_RECOVERY_BLOCKED")
			else nil,
	}
	for _, group in { activeCatalogue.Passes, activeCatalogue.Products } do
		for _, row in group do
			local price = prices[row.id]
			local capacity = if data and configured(row)
				then self:CheckHeadroom(player, row, group == activeCatalogue.Passes, true)
				else nil
			local ready = activeCatalogue.ProductionDeliveryEnabled == true
				and activeCatalogue.PaidCapacityRecoveryReady == true
				and capacity
				and capacity.ok
				and configured(row)
				and verified[row.id] == true
				and price
				and timestamp() - price.at < activeCatalogue.PriceCacheSeconds
			table.insert(if group == activeCatalogue.Passes then result.Passes else result.Cash, {
				id = row.id,
				name = row.name,
				description = row.description,
				amount = row.amount,
				currency = row.currency,
				bonusPercent = row.bonusPercent,
				bestValue = row.bestValue,
				targetPrice = row.targetPrice,
				price = if ready then price.value else nil,
				-- Public identity enables client-local regional/managed price lookup.
				platformId = if ready then row.platformId else nil,
				platformKind = if group == activeCatalogue.Passes then "GamePass" else "Product",
				enabled = ready == true,
				owned = group == activeCatalogue.Passes and data ~= nil and Rules.HasEntitlement(data, row.id),
				reasonCode = if not configured(row)
					then "PRODUCT_SETUP_REQUIRED"
					elseif capacity and not capacity.ok then capacity.code
					elseif activeCatalogue.PaidCapacityRecoveryReady ~= true then "PAID_CAPACITY_RECOVERY_BLOCKED"
					else nil,
				reason = if not configured(row)
					then "Purchases are temporarily unavailable. Product setup is required."
					elseif
						capacity and not capacity.ok
					then "Purchases temporarily unavailable while your saved data is full or recovering."
					elseif
						activeCatalogue.PaidCapacityRecoveryReady ~= true
					then "Purchases temporarily unavailable pending safe receipt-capacity recovery."
					elseif not configured(row) then "Product setup required"
					elseif not ready then "Price unavailable"
					else nil,
			})
		end
	end
	return result
end
function Service:RefreshPrices()
	for _, group in { activeCatalogue.Passes, activeCatalogue.Products } do
		for _, row in group do
			verified[row.id] = false
			if configured(row) then
				local ok, info = pcall(
					deps.Marketplace.GetProductInfoAsync,
					deps.Marketplace,
					row.platformId,
					if group == activeCatalogue.Passes then Enum.InfoType.GamePass else Enum.InfoType.Product
				)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" and info.IsForSale ~= false then
					-- IDs are also explicitly bound to the current universe in the owner setup manifest.
					local returned = if group == activeCatalogue.Products then info.ProductId else info.AssetId
					if returned == row.platformId then
						prices[row.id] = { value = info.PriceInRobux, at = timestamp() }
						verified[row.id] = true
					end
				end
			end
		end
	end
end
function Service:RefreshOwnership(player)
	if refreshing[player] then
		return
	end
	refreshing[player] = true
	for _, row in activeCatalogue.Passes do
		if not configured(row) then
			continue
		end
		local key = tostring(player.UserId) .. ":" .. row.id
		if cache[key] and timestamp() - cache[key] < activeCatalogue.OwnershipCacheSeconds then
			continue
		end
		local owned = false
		local confirmed = false
		for attempt = 1, 3 do
			local reservation = math.max(os.clock(), nextOwnershipCheck)
			nextOwnershipCheck = reservation + 0.25
			if reservation > os.clock() then
				task.wait(reservation - os.clock())
			end
			local ok, value =
				pcall(deps.Marketplace.UserOwnsGamePassAsync, deps.Marketplace, player.UserId, row.platformId)
			if ok then
				owned = value == true
				confirmed = true
				break
			end
			task.wait(math.min(attempt, 3))
			if player.Parent ~= Players then
				break
			end
		end
		if confirmed then
			cache[key] = timestamp()
			local data = deps.Profile:GetReadableData(player)
			if
				owned
				and data
				and (
					not Rules.HasEntitlement(data, row.id)
					or row.id == "STARTER_PACK" and not data.Commerce.StarterPackClaimed
				)
			then
				local result = deps.Transactions:CommitCritical(
					player,
					"pass:" .. row.id,
					"PassGrant",
					function(current, at)
						local admission = self:CheckHeadroom(player, row, true, false)
						if not admission.ok then
							return false, admission
						end
						return Rules.GrantPass(current, row.id, at)
					end,
					{
						onConfirmed = function()
							publish(player)
							durableGrant(player, "Passes", "pass:" .. row.id, row.id)
							return true
						end,
					}
				)
				if not result.ok then
					cache[key] = nil
				end
			end
			-- False/temporary errors never revoke a previously confirmed durable entitlement.
		end
	end
	refreshing[player] = nil
	publish(player)
end
function Service:ProcessReceipt(receipt)
	local retry = Enum.ProductPurchaseDecision.NotProcessedYet
	if
		type(receipt) ~= "table"
		or type(receipt.PlayerId) ~= "number"
		or receipt.PlayerId <= 0
		or receipt.PlayerId % 1 ~= 0
		or receipt.PlayerId > 9007199254740991
		or type(receipt.ProductId) ~= "number"
		or type(receipt.PurchaseId) ~= "string"
		or #receipt.PurchaseId < 1
		or #receipt.PurchaseId > 200
		or receipt.PurchaseId:find("%c")
	then
		return retry
	end
	local player = if deps.ResolvePlayer
		then deps.ResolvePlayer(receipt.PlayerId)
		else Players:GetPlayerByUserId(receipt.PlayerId)
	local row = nil
	for _, candidate in activeCatalogue.Products do
		if configured(candidate) and candidate.platformId == receipt.ProductId then
			row = candidate
			break
		end
	end
	if not row then
		if player then
			pendingReceipt(player, receipt, "UNKNOWN_PRODUCT")
		end
		return retry
	end
	if not player then
		pendingReceipt(nil, receipt, "PROFILE_NOT_READY")
		return retry
	end
	local data = deps.Profile:GetReadableData(player)
	if not data or not data.Commerce then
		pendingReceipt(player, receipt, "PROFILE_NOT_READY")
		return retry
	end
	local prior = data.Commerce.ProcessedReceipts[receipt.PurchaseId]
	if prior then
		if prior.ProductId ~= receipt.ProductId or prior.Amount ~= row.amount then
			pendingReceipt(player, receipt, "RECEIPT_ID_MISMATCH")
			return retry
		end
		if deps.Profile:IsRevisionConfirmed(player, prior.CommitRevision or math.huge) then
			resolvedReceipt(player, receipt.PurchaseId)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		pendingReceipt(player, receipt, "AWAITING_COVERING_SAVE")
		return retry
	end
	local lookupEpoch = data.Commerce.PaidArchiveEpoch or 0
	if data.Commerce.PaidArchiveEpoch ~= nil then
		local lookup = if deps.Profile.LookupPaidReceipt then deps.Profile:LookupPaidReceipt(player, receipt.PurchaseId)
			else { ok = false, code = "PAID_ARCHIVE_LOOKUP_UNAVAILABLE" }
		if not lookup.ok then pendingReceipt(player, receipt, lookup.code); return retry end
		lookupEpoch = lookup.epoch
		if lookup.receipt then
			if lookup.receipt.ProductId ~= receipt.ProductId or lookup.receipt.Amount ~= row.amount then
				pendingReceipt(player, receipt, "RECEIPT_ID_MISMATCH"); return retry
			end
			resolvedReceipt(player, receipt.PurchaseId)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	local capacity = self:CheckHeadroom(player, row, false, false, receipt)
	if not capacity.ok and (capacity.code == "PAID_LEDGER_FULL" or capacity.code == "PROFILE_STORAGE_HEADROOM")
		and deps.Profile.RecoverPaidReceiptCapacity then
		local recovery = deps.Profile:RecoverPaidReceiptCapacity(player)
		pendingReceipt(player, receipt, if recovery.ok then "AWAITING_COVERING_SAVE" else recovery.code)
		return retry -- Next bounded worker/platform callback obtains a fresh archive epoch.
	end
	local result = deps.Transactions:CommitCritical(
		player,
		"paid:" .. receipt.PurchaseId,
		"PaidCash",
		function(current, at)
			-- An overlapping callback may have granted and archived this ID after
			-- our lookup yielded. A changed epoch requires another exact lookup.
			if (current.Commerce.PaidArchiveEpoch or 0) ~= lookupEpoch then
				return false, { code = "PAID_ARCHIVE_LOOKUP_RETRY" }
			end
			-- Income cutover may increment revision before the coordinator owns this mutation.
			local revision = (deps.Profile:GetCurrentRevision(player) or 0) + 1
			local admission = self:CheckHeadroom(player, row, false, false, receipt)
			if not admission.ok then
				return false, admission
			end
			local saved = if deps.Profile.GetSavedRevision then deps.Profile:GetSavedRevision(player) or 0 else 0
			Rules.CompactPaidDiagnostics(current, saved)
			local ok, value = Rules.GrantReceipt(
				current,
				receipt.PurchaseId,
				receipt.ProductId,
				row.amount,
				at,
				activeCatalogue.Version,
				row.currency
			)
			if ok then
				current.Commerce.ProcessedReceipts[receipt.PurchaseId].CommitRevision = revision
			end
			return ok, value
		end
	)
	if result.ok and result.state == "Confirmed" then
		local current = deps.Profile:GetReadableData(player)
		local exact = current and current.Commerce and current.Commerce.ProcessedReceipts[receipt.PurchaseId]
		if
			exact
			and exact.ProductId == receipt.ProductId
			and exact.Amount == row.amount
			and deps.Profile:IsRevisionConfirmed(player, exact.CommitRevision or math.huge)
		then
			durableGrant(player, "Cash", "paid:" .. receipt.PurchaseId, row.id)
			resolvedReceipt(player, receipt.PurchaseId)
			if row.currency == "MutationStorm" and deps.OnMutationStorm then
				pcall(deps.OnMutationStorm, player, row.amount, "Robux")
			end
			if deps.Currency then
				pcall(deps.Currency.SyncBalance, deps.Currency, player)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	pendingReceipt(
		player,
		receipt,
		if result.ok
			then "AWAITING_COVERING_SAVE"
			else (result.code or (result.result and result.result.code) or "BUSY")
	)
	return retry
end
function Service:Prompt(player, id)
	if promptPending[player] and os.clock() - promptPending[player] < 60 then
		return { ok = false, code = "BUSY" }
	end
	if deps.Transactions:IsBusy(player) or not deps.Profile:IsWritable(player) then
		return { ok = false, code = "BUSY" }
	end
	local row, isPass = find(id)
	if not row then
		return { ok = false, code = "UNKNOWN_OFFER" }
	end
	local catalogue = self:GetCatalogue(player)
	local offer = nil
	for _, entry in if isPass then catalogue.Passes else catalogue.Cash do
		if entry.id == id then
			offer = entry
			break
		end
	end
	if not offer or not offer.enabled or offer.owned then
		return { ok = false, code = offer and offer.reasonCode or "UNAVAILABLE" }
	end
	local admission = self:CheckHeadroom(player, row, isPass, true)
	if not admission.ok then
		return admission
	end
	-- Prompts are only called in response to the explicitly selected, server-catalogued offer.
	promptPending[player] = os.clock()
	local session = offerSessions[player] and offerSessions[player][if isPass then "Passes" else "Cash"]
	if session then
		session.prompted = true
		session.offerId = row.id
		telemetry("Funnel", player, "Commerce", 2, session.id)
	end
	local ok = pcall(function()
		if isPass then
			deps.Marketplace:PromptGamePassPurchase(player, row.platformId)
		else
			deps.Marketplace:PromptProductPurchase(player, row.platformId)
		end
	end)
	if not ok then
		promptPending[player] = nil
	end
	telemetry(
		"Record",
		player,
		"PurchasePromptOutcome",
		1,
		{ category = if isPass then "Pass" else "Cash", result = if ok then "Started" else "Unavailable" }
	)
	return { ok = ok, code = if ok then "PROMPTED" else "UNAVAILABLE" }
end
function Service:Start(options)
	if started then
		return false
	end
	started = true
	for k, v in options or {} do
		deps[k] = v
	end
	bindConfirmedObserver()
	Marketplace.ProcessReceipt = function(receipt)
		return self:ProcessReceipt(receipt)
	end
	local function readyPlayer(player)
		publish(player)
		self:RecoverPending(player)
		task.spawn(function()
			self:RefreshOwnership(player)
		end)
	end
	deps.Profile:SubscribeReady(readyPlayer)
	for _, player in Players:GetPlayers() do
		if deps.Profile:GetReadableData(player) then
			readyPlayer(player)
		end
	end
	Marketplace.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		promptPending[player] = nil
		telemetry(
			"Record",
			player,
			"PurchasePromptOutcome",
			1,
			{ category = "Pass", result = if purchased then "Success" else "Cancelled" }
		)
		if purchased then
			for _, row in activeCatalogue.Passes do
				if row.platformId == passId then
					cache[tostring(player.UserId) .. ":" .. row.id] = nil
					task.spawn(function()
						self:RefreshOwnership(player)
					end)
					break
				end
			end
		end
	end)
	Marketplace.PromptProductPurchaseFinished:Connect(function(userId, _productId, purchased)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			telemetry(
				"Record",
				player,
				"PurchasePromptOutcome",
				1,
				{ category = "Cash", result = if purchased then "Success" else "Cancelled" }
			)
			promptPending[player] = nil
		end
	end)
	local elapsed = 0
	local priceElapsed = 0
	local recoveryElapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		priceElapsed += dt
		recoveryElapsed += dt
		if recoveryElapsed >= 5 then
			recoveryElapsed = 0
			local count = 0
			local players = Players:GetPlayers()
			for _ = 1, #players do
				if count >= 8 then
					break
				end
				if recoveryCursor > #players then
					recoveryCursor = 1
				end
				local player = players[recoveryCursor]
				recoveryCursor += 1
				if recoveryByUserId[player.UserId] and self:RecoverPending(player, true) then
					count += 1
				end
			end
		end
		if elapsed >= 60 then
			elapsed = 0
			for _, player in Players:GetPlayers() do
				if deps.Profile:GetReadableData(player) then
					task.spawn(function()
						self:RefreshOwnership(player)
					end)
				end
			end
		end
		if priceElapsed >= 240 then
			priceElapsed = 0
			task.spawn(function()
				self:RefreshPrices()
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		offerSessions[player] = nil
		grantSeen[player] = nil
		promptPending[player] = nil
		refreshing[player] = nil
		for _, row in activeCatalogue.Passes do
			cache[tostring(player.UserId) .. ":" .. row.id] = nil
		end
	end)
	task.spawn(function()
		self:RefreshPrices()
	end)
	return true
end
function Service:_ConfigureForTests(options)
	assert(RunService:IsStudio(), "Studio fixture only")
	assert(not started, "Cannot replace an active receipt dispatcher")
	activeCatalogue = options.Catalogue or DefaultCatalogue
	deps = options
	bindConfirmedObserver()
	table.clear(offerSessions)
	table.clear(grantSeen)
	table.clear(promptPending)
	table.clear(verified)
	table.clear(prices)
	table.clear(cache)
	table.clear(refreshing)
	table.clear(recoveryByUserId)
	recoveryUsers = 0
	recoveryFullWarnAt = -math.huge
	recoveryCursor = 1
end
function Service:_ResetFixture()
	assert(not started, "Cannot reset an active dispatcher")
	if confirmedConnection then
		confirmedConnection.Disconnect()
		confirmedConnection = nil
	end
	activeCatalogue = DefaultCatalogue
	deps = { Profile = Profiles, Transactions = Transactions, Marketplace = Marketplace }
	table.clear(offerSessions)
	table.clear(grantSeen)
	table.clear(promptPending)
	table.clear(verified)
	table.clear(prices)
	table.clear(cache)
	table.clear(refreshing)
	table.clear(recoveryByUserId)
	recoveryUsers = 0
	recoveryFullWarnAt = -math.huge
	recoveryCursor = 1
end
return Service
