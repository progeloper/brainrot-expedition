--!strict
-- Shared covering-save coordinator; all domain mutations use the existing profile writer.
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Rules = require(RS.Shared.Utility.Phase13Rules)
local Config = require(RS.Shared.Config.Phase13)
local Profile = require(script.Parent.PlayerDataService)
local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
local Progress = require(script.Parent.Parent.Data.Phase12Progress)
local WorldRules = require(RS.Shared.Utility.WorldProgressionRules)
local Banked = require(script.Parent.BankedBrainrotService)
local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
local Service = {}
local deps: any = { Profile = Profile, Income = Income, Currency = Currency }
local pending: { [Player]: any } = {}
local listeners = {}
local started = false
local subscriptions = {}
local function now()
	return if deps.Now then deps.Now() else Workspace:GetServerTimeNow()
end
local function fail(code)
	return { ok = false, state = "Rejected", code = code }
end
local function validId(id)
	return type(id) == "string" and #id > 0 and #id <= 240 and not id:find("%c")
end
local function publish(player)
	local data = deps.Profile:GetReadableData(player)
	if data and data.Phase13 then
		local p = data.Phase13
		player:SetAttribute("SelectedWeaponId", p.SelectedWeaponId)
		player:SetAttribute("SelectedCartId", p.SelectedCartId)
		player:SetAttribute("BaseCapacity", Rules.GetCapacity(data))
		player:SetAttribute("SelectedBaseDesignId", p.SelectedBaseDesignId)
		player:SetAttribute("RebirthCount", p.RebirthCount)
		player:SetAttribute("Phase13EligibilityRevision", p.EligibilityRevision)
		player:SetAttribute("Phase13ConfigurationVersion", Config.ConfigurationVersion)
	end
end
local function confirmed(player, revision)
	local operation = pending[player]
	if not operation or revision < operation.Revision or not deps.Profile:IsCurrentSessionHandle(operation.Session) then
		return
	end
	if operation.Finalizing or not operation.CommittedHookReady then
		return
	end
	operation.Finalizing = true
	-- Geometry/effects are rebuilt from committed ownership. A failure never repeats the mutation.
	local ok, result = pcall(function()
		local detached = player.Parent ~= Players
		if operation.Options.onConfirmed then
			return operation.Options.onConfirmed(operation.Receipt.Result, detached)
		end
		if deps.ReconcileOwned then
			local receipt = table.clone(operation.Receipt)
			receipt.Detached = detached
			return deps.ReconcileOwned(player, receipt)
		end
		return true
	end)
	if not ok or result == false then
		operation.Finalizing = false
		operation.ReconcilePending = true
		return
	end
	deps.Profile:ReleaseCritical(player, operation.Handle)
	if operation.IncomeToken then
		deps.Income:EndCriticalCutover(player, operation.IncomeToken, now())
	end
	pending[player] = nil
	publish(player)
	-- The covering save and owned-source reconciliation are complete. Read the
	-- current wallet so later legitimate credits survive this display refresh;
	-- a quote/receipt snapshot must never overwrite the Cash attribute.
	pcall(deps.Currency.SyncBalance, deps.Currency, player)
	local response = {
		ok = true,
		state = "Confirmed",
		code = "SAVED",
		operationId = operation.Id,
		revision = operation.Revision,
		kind = operation.Receipt.Kind,
		result = operation.Receipt.Result,
		receipt = operation.Receipt,
	}
	for _, callback in listeners do
		pcall(callback, player, response)
	end
	if deps.Telemetry then
		pcall(deps.Telemetry.Receipt, deps.Telemetry, player, operation.Receipt.Kind, response)
	end
end
local function recovered(oldPlayer, newPlayer, canonicalData, previousData)
	local operation = pending[oldPlayer]
	if operation then
		local receipt = canonicalData.Phase13.Operations[operation.Id]
		local saved = receipt ~= nil
			and receipt.Kind == operation.Receipt.Kind
			and receipt.Sequence == operation.Receipt.Sequence
		local paidId = if operation.Receipt.Kind == "PaidCash" then operation.Id:match("^paid:(.+)$") else nil
		if paidId and canonicalData.Commerce.ProcessedReceipts[paidId] then
			saved = true
		end
		local outcome = if saved then "Saved" else "CanonicalAbsent"
		if not saved and canonicalData.Phase13.LastPrunedSequence >= operation.Receipt.Sequence then
			outcome = "AcknowledgementPruned"
		end
		if operation.Options.onRecovered and not operation.RecoveryHookReady then
			local ok, result = pcall(operation.Options.onRecovered, operation.Receipt.Result, canonicalData, outcome)
			if not ok or result == false then
				return false
			end
			operation.RecoveryHookReady = true
		end
		if operation.Receipt.Kind == "PlatformSwap" and not operation.Options.onRecovered then
			return false -- staged visuals require their explicit discard adapter
		end
	end
	if deps.ReconcileRecovery then
		local ok, result = pcall(deps.ReconcileRecovery, oldPlayer, newPlayer, canonicalData, previousData)
		if not ok or result == false then
			return false
		end
	elseif operation and operation.Receipt.Kind == "Rebirth" and operation.Receipt.Result.route == "Collection" then
		return false
	end
	-- Canonical data already came from Acquire. No mutator, refund, old save,
	-- cinematic, receipt grant, or queued old-session income is replayed.
	pending[oldPlayer] = nil
	return true
end
function Service:Start(options: any?): boolean
	if started then
		return false
	end
	for k, v in options or {} do
		deps[k] = v
	end
	table.insert(
		subscriptions,
		deps.Profile:SubscribeSaveConfirmed(function(player, saved)
			confirmed(player, saved)
		end)
	)
	table.insert(subscriptions, deps.Profile:SubscribeReady(publish))
	if deps.Profile.SubscribeSessionRecovered then
		table.insert(subscriptions, deps.Profile:SubscribeSessionRecovered(recovered))
	end
	for _, player in Players:GetPlayers() do
		if deps.Profile:GetReadableData(player) then
			publish(player)
		end
	end
	-- Pending durable operations survive a closed UI or player departure until the save owner resolves them.
	started = true
	return true
end
function Service:SubscribeConfirmed(callback)
	local key = {}
	listeners[key] = callback
	return {
		Disconnect = function()
			listeners[key] = nil
		end,
	}
end
function Service:GetOperation(player, id)
	local operation = pending[player]
	if operation and operation.Id == id then
		return {
			ok = true,
			state = "Saving",
			code = "PENDING",
			operationId = id,
			revision = operation.Revision,
			result = operation.Receipt.Result,
		}
	end
	local data = deps.Profile:GetReadableData(player)
	local receipt = data and data.Phase13 and data.Phase13.Operations[id]
	if receipt then
		return {
			ok = true,
			state = if deps.Profile:IsRevisionConfirmed(player, receipt.CommitRevision) then "Confirmed" else "Saving",
			code = "REPLAY",
			operationId = id,
			revision = receipt.CommitRevision,
			result = receipt.Result,
			receipt = receipt,
		}
	end
	return fail("UNKNOWN_OPERATION")
end
function Service:CommitCritical(player, operationId, kind, mutator, options)
	if not started then
		self:Start()
	end
	options = options or {}
	if not validId(operationId) or not validId(kind) or type(mutator) ~= "function" then
		return fail("INVALID_REQUEST")
	end
	local data = deps.Profile:GetReadableData(player)
	if not data or not data.Phase13 then
		return fail("PROFILE_NOT_READY")
	end
	local prior = data.Phase13.Operations[operationId]
	if prior then
		if prior.Kind ~= kind then
			return fail("OPERATION_ID_MISMATCH")
		end
		return self:GetOperation(player, operationId)
	end
	if pending[player] then
		return fail("BUSY")
	end
	if options.previewRevision ~= nil and options.previewRevision ~= data.Phase13.EligibilityRevision then
		return fail("STALE_PREVIEW")
	end
	if options.sequence ~= nil and options.sequence ~= data.Phase13.OperationSequence + 1 then
		return fail("STALE_OPERATION")
	end
	local cutover = now()
	local incomeToken, reason = deps.Income:BeginCriticalCutover(player, cutover)
	if not incomeToken then
		return fail(reason or "INCOME_BUSY")
	end
	local handle
	handle, reason = deps.Profile:AcquireCritical(player, operationId)
	if not handle then
		deps.Income:EndCriticalCutover(player, incomeToken, now())
		return fail(reason or "BUSY")
	end
	local revision = (deps.Profile:GetCurrentRevision(player) or 0) + 1
	local receipt
	local committed = deps.Profile:CommitCriticalMutation(player, handle, function(current)
		if options.validate then
			local allowed, why = options.validate(current)
			if not allowed then
				return false, fail(why or "CONTEXT_CHANGED")
			end
		end
		local ok, result = mutator(current, cutover)
		if ok ~= true then
			return false, result
		end
		receipt = Rules.AppendOperation(current, operationId, kind, revision, cutover, result or {})
		return true, { code = "PENDING", result = result }
	end)
	if not committed.ok then
		deps.Profile:ReleaseCritical(player, handle)
		deps.Income:EndCriticalCutover(player, incomeToken, now())
		return committed
	end
	pending[player] = {
		Id = operationId,
		Handle = handle,
		Session = deps.Profile:GetSessionHandle(player),
		Revision = committed.revision,
		Receipt = receipt,
		Options = options,
		IncomeToken = incomeToken,
		CommittedHookReady = options.onCommitted == nil,
	}
	if options.onCommitted then
		local ok, result = pcall(options.onCommitted, receipt.Result, committed.revision)
		local current = pending[player]
		if current then
			current.CommittedHookReady = ok and result ~= false
			current.ReconcilePending = not current.CommittedHookReady
		end
	end
	local request = deps.Profile:RequestSave(player, "Phase13:" .. kind)
	-- A synchronous injected backend can have already confirmed the operation.
	if not pending[player] then
		return self:GetOperation(player, operationId)
	end
	return {
		ok = true,
		state = "Saving",
		code = if request and request.ok then "PENDING" else "RETRY_PENDING",
		operationId = operationId,
		revision = committed.revision,
		result = receipt.Result,
	}
end
function Service:IsBusy(player)
	return pending[player] ~= nil or deps.Profile:HasCriticalOperation(player)
end
function Service:Step()
	for player, operation in pending do
		if not deps.Profile:IsCurrentSessionHandle(operation.Session) then
			continue
		end
		if deps.Profile.GetStatus and deps.Profile:GetStatus(player) == "Failed" then
			continue
		end
		if not operation.CommittedHookReady and operation.Options.onCommitted then
			local ok, result = pcall(operation.Options.onCommitted, operation.Receipt.Result, operation.Revision)
			operation.CommittedHookReady = ok and result ~= false
		end
		if deps.Profile:IsRevisionConfirmed(player, operation.Revision) then
			confirmed(player, operation.Revision)
		end
	end
end
local function context(player, category, insideMutation)
	if not deps.ValidateContext then
		return false, "SERVICE_CONTEXT_UNAVAILABLE"
	end
	return deps.ValidateContext(player, category, insideMutation == true)
end
function Service:QuoteRebirth(player, rewardId, route)
	if Banked:HasPendingBank(player) then
		return fail("BANK_SAVE_PENDING")
	end
	local ok, why = context(player, "Rebirth")
	if not ok then
		return fail(why or "CONTEXT_LOST")
	end
	if self:IsBusy(player) then
		return fail("BUSY")
	end
	deps.Income:AccruePlatformsTo(now())
	local data = deps.Profile:GetReadableData(player)
	if not data then
		return fail("NOT_READY")
	end
	return Rules.QuoteRebirth(data, rewardId, route)
end
function Service:Rebirth(player, request)
	if Banked:HasPendingBank(player) then
		return fail("BANK_SAVE_PENDING")
	end
	if type(request) ~= "table" or type(request.sequence) ~= "number" then
		return fail("INVALID_REQUEST")
	end
	local ok, why = context(player, "Rebirth")
	if not ok then
		return fail(why or "CONTEXT_LOST")
	end
	local preflight
	if deps.PreflightOwned then
		preflight, why = deps.PreflightOwned(player, request)
		if not preflight then
			return fail(why or "BUSY")
		end
	end
	return self:CommitCritical(player, request.operationId, "Rebirth", function(data, at)
		return Rules.ApplyRebirth(data, request, at)
	end, {
		previewRevision = request.previewRevision,
		sequence = request.sequence,
		validate = function()
			if Banked:HasPendingBank(player) then
				return false, "BANK_SAVE_PENDING"
			end
			return context(player, "Rebirth", true)
		end,
		onConfirmed = function(result, detached)
			if deps.ReconcileOwned then
				return deps.ReconcileOwned(
					player,
					{ Kind = "Rebirth", Result = result, Preflight = preflight, Detached = detached }
				)
			end
			return true
		end,
	})
end
function Service:Purchase(player, request)
	if type(request) ~= "table" or type(request.sequence) ~= "number" then
		return fail("INVALID_REQUEST")
	end
	local ok, why = context(player, request.category)
	if not ok then
		return fail(why or "CONTEXT_LOST")
	end
	return self:CommitCritical(player, request.operationId, "CataloguePurchase", function(data)
		return Rules.ApplyPurchase(data, request.category, request.id)
	end, {
		previewRevision = request.previewRevision,
		sequence = request.sequence,
		validate = function()
			return context(player, request.category, true)
		end,
	})
end
function Service:Select(player, request)
	if type(request) ~= "table" or type(request.sequence) ~= "number" then
		return fail("INVALID_REQUEST")
	end
	local ok, why = context(player, request.category)
	if not ok then
		return fail(why or "CONTEXT_LOST")
	end
	local prepare
	if request.category == "Cart" then
		if not deps.PrepareCartSelection then
			return fail("CART_SELECTION_UNAVAILABLE")
		end
		prepare, why = deps.PrepareCartSelection(player, request.id)
		if not prepare then
			return fail(why or "CART_BUSY")
		end
	end
	return self:CommitCritical(player, request.operationId, "OwnedSelection", function(data)
		return Rules.Select(data, request.category, request.id)
	end, {
		previewRevision = request.previewRevision,
		sequence = request.sequence,
		validate = function()
			local allowed, reason = context(player, request.category, true)
			if not allowed then
				return false, reason
			end
			if request.category == "Cart" and prepare.Validate then
				return prepare.Validate()
			end
			return true
		end,
		onConfirmed = function(result, detached)
			if request.category == "Cart" then
				if detached then
					return true
				end
				if not deps.CommitCartSelection then
					return false
				end
				return deps.CommitCartSelection(player, prepare, result.id)
			end
			if deps.ReconcileOwned then
				return deps.ReconcileOwned(player, { Kind = "OwnedSelection", Result = result, Detached = detached })
			end
			return true
		end,
	})
end
function Service:EndNewcomerProtection(player, operationId)
	return self:CommitCritical(player, operationId, "ProtectionOptOut", function(data)
		if data.Phase13.NewcomerProtectionEnded then
			return false, fail("ALREADY_ENDED")
		end
		data.Phase13.NewcomerProtectionEnded = true
		return true, { code = "APPLIED" }
	end)
end
function Service:IsNewcomerProtectionEnded(player)
	local operation = pending[player]
	if operation and operation.Receipt.Kind == "ProtectionOptOut" then
		return false
	end
	local data = deps.Profile:GetReadableData(player)
	return data ~= nil and data.Phase13 ~= nil and data.Phase13.NewcomerProtectionEnded == true
end
function Service:CommitPlatformSwap(player, request, options)
	options = options or {}
	local incoming = request.incomingRecord
	return self:CommitCritical(player, request.operationId, "PlatformSwap", function(data, at)
		local history
		if request.incomingFresh then
			history = Progress.RecordFirstBank(data, incoming, Banked:GetBankContext(player), at)
			local state = World.GetPhase12State and World.GetPhase12State(incoming)
			if history and state and (state.AcquisitionKind == "Hunt" or state.AcquisitionKind == "Theft") then
				history.acquisitionKind = state.AcquisitionKind
			end
		end
		local ok, result = Rules.ApplySwap(data, request, at)
		if not ok then
			return false, result
		end
		if request.incomingFresh then
			WorldRules.AddBankedProof(data, incoming.BrainrotId, "swap", at)
		end
		result.firstBankReceipt = history
		return true, result
	end, {
		previewRevision = request.previewRevision,
		sequence = request.sequence,
		validate = options.validate,
		onCommitted = function(result, revision)
			if request.incomingFresh then
				local op = "Bank:" .. incoming.ItemId
				local ok, reason = World.BeginPendingBank(incoming, op, revision)
				if not ok and reason ~= "ALREADY_BANKED_OR_NONORDINARY" then
					return false
				end
			end
			local releasePose
			if request.incomingFresh then
				local valid, pose = Banked:CapturePendingBankSourcePose(player, incoming, "Bank:" .. incoming.ItemId)
				if valid then
					releasePose = pose
				end
			end
			-- Retire the prepared carry representation before any save can confirm synchronously.
			if options.onCommitted and options.onCommitted(result, revision) == false then
				return false
			end
			if request.incomingFresh then
				local op = "Bank:" .. incoming.ItemId
				Banked:RegisterPendingBank(player, incoming, revision, function()
					local released = World.ConfirmPendingBank(incoming, op)
					if released and result.firstBankReceipt then
						Banked:OnBankCommitted(player, result.firstBankReceipt)
					end
					return released
				end, releasePose)
			end
			return true
		end,
		onConfirmed = options.onConfirmed,
		onRecovered = options.onRecovered,
	})
end
function Service:_ResetForTests()
	for _, connection in subscriptions do
		connection:Disconnect()
	end
	for player, operation in pending do
		deps.Profile:ReleaseCritical(player, operation.Handle)
		if operation.IncomeToken then
			deps.Income:EndCriticalCutover(player, operation.IncomeToken, now())
		end
	end
	table.clear(subscriptions)
	table.clear(pending)
	table.clear(listeners)
	deps = { Profile = Profile, Income = Income, Currency = Currency }
	started = false
end
return Service
