--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SlotPresentation = require(ReplicatedStorage.Shared.Utility.BaseSlotPresentation)
local Workspace = game:GetService("Workspace")
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local CommerceRules = require(ReplicatedStorage.Shared.Utility.Phase13CommerceRules)
local Phase12Progress = require(script.Parent.Parent.Data.Phase12Progress)
local BaseStorageSystem = require(script.Parent.BaseStorageSystem)
local PlayerBaseSystem = require(script.Parent.PlayerBaseSystem)
local CurrencySystem = require(script.Parent.CurrencySystem)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local log = Logger.new("BrainrotIncomeSystem")
local Trace = require(script.Parent.Parent.Utility.BrainrotDiagnostics)
local MAX_SAFE_INTEGER = 9007199254740991
local INCOME_UNITS_PER_CASH = 10000
local PAYOUT_INTERVAL = 1.0
local Income = {}
local states: { [Player]: any } = {}
local connections: { any } = {}
local unsubscribe: (() -> ())? = nil
local started = false
local storageSystem: any = BaseStorageSystem
local baseSystem: any = PlayerBaseSystem
local wallet: any = CurrencySystem
local finalised: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local accumulator = 0
local platformContexts: { [string]: any } = {}
local playerPlatformContexts: { [Player]: any } = {}
local claimsInFlight: { [string]: { [number]: boolean } } = {}
local warnedPlatformKeys: { [string]: boolean } = {}
local warnedPlatformKeyCount = 0
local warningCacheSaturated = false
local MAX_WARNING_KEYS = 128
local platformLastAccrualTime: number? = nil
local initialDependencies: any? = nil
local profileOwner: any? = nil
local committedListeners: { [any]: (Player, any) -> () } = {}
local committedSequence = 0
local platformClock: any
local analytics: any = nil
local analyticsBuckets: { [Player]: any } = {}
local function aggregateAnalytics(player: Player, field: string, amount: number, at: number?)
	if not analytics or amount <= 0 then
		return
	end
	local bucket = analyticsBuckets[player]
	if not bucket then
		bucket = { StartedAt = at or platformClock(), Produced = 0, Collected = 0 }
		analyticsBuckets[player] = bucket
	end
	bucket[field] += amount
end
platformClock = function(): number
	return Workspace:GetServerTimeNow()
end
local platformRateResolver = function(brainrotId: any): (number?, string?)
	return Catalog.GetCashPerSecond(brainrotId)
end
local nowMs = function(): number
	return math.floor(os.clock() * 1000)
end

local function notifyCommitted(player: Player, receipt: any)
	committedSequence += 1
	local session = if profileOwner and profileOwner.GetSessionHandle
		then profileOwner:GetSessionHandle(player)
		else nil
	receipt.sessionGeneration = if session then session.Generation else nil
	receipt.stream = "Income"
	receipt.operationSequence = committedSequence
	local immutable = table.freeze(receipt)
	for _, callback in committedListeners do
		local ok, failure = pcall(callback, player, immutable)
		if not ok then
			log:Warn("Committed income observer failed: %s", tostring(failure))
		end
	end
end

local function traceIncome(state: any, stage: string, fields: any?, warning: boolean?)
	Trace.Emit("5D", stage, function()
		local result = Trace.Fields(state.Player, nil, state.Storage)
		result.storageRevision = state.Revision or "none"
		result.rateTenths, result.cashPerSecond = state.RateTenths, state.RateTenths / 10
		result.pendingUnits, result.unitsPerCash = state.PendingUnits, INCOME_UNITS_PER_CASH
		result.lastAccruedMs, result.changedAtMs = state.LastAccruedMs or "none", state.ChangedAtMs
		result.activated, result.closing = state.Activated, state.Closing
		for key, value in fields or {} do
			result[key] = value
		end
		return result
	end, warning)
end

local function incomeSample(state: any, channel: string, reason: string?): boolean
	if not Trace.Enabled() then
		return false
	end
	return Trace.Due(
		state.Player,
		channel,
		Trace.Id(state.Storage) .. "|" .. tostring(state.Revision) .. "|" .. (reason or "processing")
	)
end

local function integer(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= MAX_SAFE_INTEGER and value % 1 == 0
end

local function finiteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= MAX_SAFE_INTEGER
end

local function validPlatformTime(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and math.abs(value) < math.huge
end

local function warnPlatformOnce(key: string, message: string)
	if warnedPlatformKeys[key] then
		return
	end
	if warnedPlatformKeyCount >= MAX_WARNING_KEYS then
		if not warningCacheSaturated then
			warningCacheSaturated = true
			log:Warn("Additional malformed platform-income warnings suppressed")
		end
		return
	end
	warnedPlatformKeys[key] = true
	warnedPlatformKeyCount += 1
	log:Warn("%s", message)
end

local function resolveRatePerSecond(occupant: any, player: Player?): number
	if occupant == nil then
		return 0
	end
	if
		type(occupant) ~= "table"
		or type(occupant.ItemId) ~= "string"
		or occupant.ItemId == ""
		or type(occupant.BrainrotId) ~= "string"
		or occupant.BrainrotId == ""
	then
		local id = if type(occupant) == "table" then occupant.BrainrotId else "invalid"
		warnPlatformOnce(
			"catalogue:" .. tostring(id),
			"Income disabled for invalid deposited occupant " .. tostring(id)
		)
		return 0
	end
	local rate, reason = platformRateResolver(occupant.BrainrotId)
	if finiteNonNegative(rate) then
		rate *= Phase12Rules.MutationMultiplier(Phase12Progress.MutationId(occupant))
		local data = if player
				and profileOwner
				and profileOwner.GetReadableData
			then profileOwner:GetReadableData(player)
			else nil
		if data then
			rate *= CommerceRules.ProductionMultiplier(data)
		end
	end
	if not finiteNonNegative(rate) then
		warnPlatformOnce(
			"catalogue:" .. occupant.BrainrotId,
			string.format(
				"Income disabled for catalogue id %s: %s",
				occupant.BrainrotId,
				tostring(reason or "invalid cash-per-second value")
			)
		)
		return 0
	end
	return rate
end

local function roundedSnapshot(value: number): number
	local precision = 1000
	if value > MAX_SAFE_INTEGER / precision then
		return math.floor(value)
	end
	return math.floor(value * precision + 0.5) / precision
end

local function platformContextCurrent(context: any): boolean
	return context ~= nil
		and platformContexts[context.BaseId] == context
		and context.Storage:IsActive()
		and context.Storage.OwnerUserId == context.OwnerUserId
		and context.Player.UserId == context.OwnerUserId
		and storageSystem:GetStorageForPlayer(context.Player) == context.Storage
		and baseSystem:GetBase(context.Player) == context.Base
		and baseSystem:IsOwner(context.Player, context.Base)
end

local function syncOnePlatform(context: any, platformId: number, at: number, forceRevision: boolean?): any?
	if not context.Storage:IsValidPlatformId(platformId) then
		return nil
	end
	local occupant = context.Storage:GetPlatformRecord(platformId)
	local exact = context.Storage:GetUnclaimedCashExact(platformId)
	if not finiteNonNegative(exact) then
		return nil
	end
	local rate = resolveRatePerSecond(occupant, context.Player)
	local occupied = occupant ~= nil
	local individualId = if occupant then occupant.ItemId else nil
	local catalogueId = if occupant then occupant.BrainrotId else nil
	local previous = context.Snapshots[platformId]
	local changed = previous == nil
		or previous.Occupied ~= occupied
		or previous.IndividualId ~= individualId
		or previous.CatalogueId ~= catalogueId
		or previous.RatePerSecond ~= rate
	if not changed and not forceRevision then
		return previous
	end
	local snapshot = table.freeze({
		Occupied = occupied,
		IndividualId = individualId,
		CatalogueId = catalogueId,
		RatePerSecond = if occupied then rate else 0,
		UnclaimedCashSnapshot = roundedSnapshot(exact),
		SnapshotServerTime = at,
		Revision = (if previous then previous.Revision else 0) + 1,
	})
	context.Snapshots[platformId] = snapshot
	return snapshot
end

local function syncPlatformContext(context: any, at: number, forceRevision: boolean?)
	for _, platformId in context.Storage:GetPlatformIds() do
		syncOnePlatform(context, platformId, at, forceRevision)
	end
end

local function clearPlatformContext(context: any)
	if platformContexts[context.BaseId] == context then
		platformContexts[context.BaseId] = nil
	end
	if playerPlatformContexts[context.Player] == context then
		playerPlatformContexts[context.Player] = nil
	end
end

local function persistPlatformContext(context: any): boolean
	if profileOwner == nil or not platformContextCurrent(context) then
		return profileOwner == nil
	end
	local saved, reason = profileOwner:MarkDirty(context.Player, context.Storage:GetPersistentData())
	if not saved then
		warnPlatformOnce(
			"profile:" .. context.BaseId .. ":" .. tostring(reason),
			string.format("Platform income profile snapshot failed for %s: %s", context.BaseId, tostring(reason))
		)
	end
	return saved
end

function Income.CalculateStorageRate(snapshot: any): (number, { any })
	local total, diagnostics, seen = 0, {}, {}
	local function problem(code, item, species)
		table.insert(diagnostics, { Code = code, ItemId = item, BrainrotId = species })
		Trace.Emit(
			"5D",
			"catalogue_exclusion",
			{ itemId = item or "none", species = species or "none", reason = code },
			true
		)
	end
	if type(snapshot) ~= "table" then
		problem("INVALID_SNAPSHOT", nil, nil)
		return 0, diagnostics
	end
	for _, entry in snapshot do
		if type(entry) ~= "table" or type(entry.ItemId) ~= "string" or entry.ItemId == "" then
			problem("INVALID_ITEM_ID", nil, if type(entry) == "table" then entry.BrainrotId else nil)
			continue
		end
		if seen[entry.ItemId] then
			problem("DUPLICATE_ITEM_ID", entry.ItemId, entry.BrainrotId)
			continue
		end
		seen[entry.ItemId] = true
		local rate = Catalog.GetCashPerSecond(entry.BrainrotId)
		Trace.Emit("5D", "catalogue_rate", function()
			return {
				itemId = entry.ItemId,
				species = entry.BrainrotId,
				canonicalKey = Catalog.ResolveId(entry.BrainrotId) or "none",
				configuredCashPerSecond = rate or "none",
				result = if rate == nil then "excluded" else "resolved",
			}
		end)
		if rate == nil then
			problem("UNKNOWN_SPECIES", entry.ItemId, entry.BrainrotId)
			continue
		end
		local tenths = rate * Phase12Rules.MutationMultiplier(Phase12Progress.MutationId(entry)) * 10
		-- Canonical legacy decimal rates can carry a few binary ULPs after scaling.
		-- Snap only numerical noise near an integer; retain actual fractional rates.
		local nearest = math.round(tenths)
		if math.abs(tenths - nearest) <= math.max(1, math.abs(tenths)) * 1.7763568394002505e-15 then
			tenths = nearest
		end
		if not finiteNonNegative(tenths) or total > MAX_SAFE_INTEGER - tenths then
			problem("RATE_OVERFLOW", entry.ItemId, entry.BrainrotId)
			continue
		end
		total += tenths
	end
	return total, diagnostics
end

function Income:AccruePlatformsTo(at: number): (boolean, string?)
	if not started or not validPlatformTime(at) then
		return false, "INVALID_TIME"
	end
	if platformLastAccrualTime == nil then
		platformLastAccrualTime = at
		return true, nil
	end
	local stableContexts = {}
	for _, context in platformContexts do
		table.insert(stableContexts, context)
	end
	for _, context in stableContexts do
		if platformContextCurrent(context) and not context.AccrualStopped then
			local last = context.LastAccrualTime or at
			local through = if context.DepartureAt then math.min(at, context.DepartureAt) else at
			local dt = through - last
			if dt < 0 then
				return false, "CLOCK_ORDER"
			end
			local changed = false
			local produced = 0
			local byIndividual: { [string]: number } = {}
			for _, platformId in if dt > 0 then context.Storage:GetPlatformIds() else {} do
				local occupant = context.Storage:GetPlatformRecord(platformId)
				local rate = resolveRatePerSecond(occupant, context.Player)
				if rate > 0 then
					local generated = rate * dt
					local ok, reason = context.Storage:AddUnclaimedCashExact(platformId, generated)
					if not ok then
						warnPlatformOnce(
							context.BaseId .. ":" .. tostring(platformId) .. ":" .. tostring(reason),
							string.format(
								"Income accrual suspended for %s platform %d: %s",
								context.BaseId,
								platformId,
								tostring(reason)
							)
						)
					else
						changed = true
						produced += generated
						local individualId = if type(occupant) == "table" then occupant.ItemId else nil
						if type(individualId) == "string" then
							byIndividual[individualId] = (byIndividual[individualId] or 0) + generated
						end
					end
				end
			end
			if changed then
				persistPlatformContext(context)
				aggregateAnalytics(context.Player, "Produced", produced, through)
				notifyCommitted(context.Player, {
					kind = "PlatformIncomeProduced",
					eventId = context.BaseId .. ":" .. tostring(through),
					at = through,
					amount = produced,
					byIndividual = table.freeze(byIndividual),
					baseId = context.BaseId,
				})
			end
			context.LastAccrualTime = through
		end
	end
	platformLastAccrualTime = at
	return true, nil
end

function Income:SubscribeCommitted(callback: (Player, any) -> ()): any
	local connection = {}
	committedListeners[connection] = callback
	function connection.Disconnect()
		committedListeners[connection] = nil
	end
	return connection
end

local function bindPlatformStorage(player: Player, storage: any, at: number): boolean
	if
		storage == nil
		or not storage:IsActive()
		or storage.OwnerUserId ~= player.UserId
		or storageSystem:GetStorageForPlayer(player) ~= storage
		or baseSystem:GetBase(player) ~= storage.Base
		or not baseSystem:IsOwner(player, storage.Base)
	then
		return false
	end
	local baseId = storage.BaseId
	if type(baseId) ~= "string" or baseId == "" then
		return false
	end
	local current = platformContexts[baseId]
	if current and current.Player == player and current.Storage == storage then
		return true
	end
	if current then
		clearPlatformContext(current)
	end
	local oldPlayerContext = playerPlatformContexts[player]
	if oldPlayerContext then
		clearPlatformContext(oldPlayerContext)
	end
	local context = {
		BaseId = baseId,
		Base = storage.Base,
		Storage = storage,
		Player = player,
		OwnerUserId = player.UserId,
		Snapshots = {},
		LastAccrualTime = at,
	}
	platformContexts[baseId], playerPlatformContexts[player] = context, context
	syncPlatformContext(context, at, true)
	return true
end

function Income:BindPlatformStorage(player: Player, storage: any): boolean
	if not started then
		return false
	end
	return bindPlatformStorage(player, storage, platformClock())
end

function Income:GetPlatformIncomeSnapshot(baseId: string, platformId: number): any?
	local context = platformContexts[baseId]
	if not platformContextCurrent(context) or not context.Storage:IsValidPlatformId(platformId) then
		return nil
	end
	return context.Snapshots[platformId]
end

function Income:SyncPlatformSnapshots(requests: { { BaseId: string, PlatformId: number } }): { [number]: any }
	local snapshots = {}
	if #requests == 0 then
		return snapshots
	end
	-- One ledger accrual and one profile copy per owner for the entire refresh.
	-- All plaque samples share that exact authoritative timestamp.
	local at = platformClock()
	if not self:AccruePlatformsTo(at) then
		return snapshots
	end
	for index, request in requests do
		local context = platformContexts[request.BaseId]
		if platformContextCurrent(context) and context.Storage:IsValidPlatformId(request.PlatformId) then
			snapshots[index] = syncOnePlatform(context, request.PlatformId, at, true)
		end
	end
	return snapshots
end

function Income:SyncPlatformSnapshot(baseId: string, platformId: number): any?
	return self:SyncPlatformSnapshots({ { BaseId = baseId, PlatformId = platformId } })[1]
end

function Income:TryClaimPlatform(player: Player, baseId: string, platformId: number): any
	-- Keep this validation order stable for the later plaque touch owner.
	if player.Parent ~= Players or not wallet:IsReady(player) then
		return { ok = false, code = "ProfileNotReady" }
	end
	local base = baseSystem:GetBase(player)
	local context = platformContexts[baseId]
	if
		base == nil
		or type(baseId) ~= "string"
		or base:GetAttribute("BaseId") ~= baseId
		or not baseSystem:IsOwner(player, base)
		or not platformContextCurrent(context)
		or context.Base ~= base
		or context.OwnerUserId ~= player.UserId
	then
		return { ok = false, code = "NotOwner" }
	end
	if not context.Storage:IsValidPlatformId(platformId) then
		return { ok = false, code = "InvalidPlatform" }
	end
	local assignment = if baseSystem.GetAssignment then baseSystem:GetAssignment(player) else nil
	if
		base:GetAttribute("BasePresentationManaged") == true
		and (
			assignment == nil or not SlotPresentation.CanUseSlot(base, platformId, player.UserId, assignment.Generation)
		)
	then
		return { ok = false, code = "InvalidPlatform" }
	end
	local occupant = context.Storage:GetPlatformRecord(platformId)
	local banked = require(script.Parent.Parent.Services.BankedBrainrotService)
	if occupant and banked:IsBankPending(player, occupant.ItemId) then
		return { ok = false, code = "Saving" }
	end
	local baseClaims = claimsInFlight[baseId]
	if baseClaims and baseClaims[platformId] then
		return { ok = false, code = "Busy" }
	end
	local mutationToken = context.Storage:TryBeginPlatformMutation(platformId)
	if not mutationToken then
		return { ok = false, code = "Busy" }
	end
	if baseClaims == nil then
		baseClaims = {}
		claimsInFlight[baseId] = baseClaims
	end
	baseClaims[platformId] = true

	local result: any = { ok = false, code = "AwardFailed" }
	local ok, failure = xpcall(function()
		local accrued, accrualReason = self:AccruePlatformsTo(platformClock())
		if not accrued then
			result = { ok = false, code = "AwardFailed", reason = accrualReason }
			return
		end
		local exact = context.Storage:GetUnclaimedCashExact(platformId)
		if not finiteNonNegative(exact) then
			return
		end
		local payout = exact
		if payout <= 0 then
			result = {
				ok = false,
				code = "NothingToCollect",
				paid = 0,
				remainingExact = exact,
			}
			return
		end
		if wallet.CanCredit then
			local checked, canCredit = pcall(wallet.CanCredit, wallet, player, payout)
			if not checked or canCredit ~= true then
				result = { ok = false, code = "AwardFailed", paid = 0, remainingExact = exact }
				return
			end
		end
		local currentExact = context.Storage:GetUnclaimedCashExact(platformId)
		if not finiteNonNegative(currentExact) or currentExact < payout then
			result = { ok = false, code = "AwardFailed", paid = 0, remainingExact = exact }
			return
		end
		local remaining = 0
		local called, award
		if wallet.TryCreditWithSource then
			called, award = pcall(wallet.TryCreditWithSource, wallet, player, payout, "PlatformIncomeClaim", function()
				local latest = context.Storage:GetUnclaimedCashExact(platformId)
				if latest ~= currentExact then
					return false, "SOURCE_CHANGED"
				end
				return context.Storage:SetUnclaimedCashExact(platformId, 0)
			end, {
				source = "OwnPlatformIncome",
				ownerUserId = player.UserId,
				earnings = payout,
				at = platformClock(),
				operationId = "Platform:" .. baseId .. ":" .. tostring(platformId) .. ":" .. tostring(platformClock()),
			})
		else
			local stored = context.Storage:SetUnclaimedCashExact(platformId, remaining)
			if not stored then
				result = { ok = false, code = "AwardFailed", paid = 0, remainingExact = exact }
				return
			end
			called, award = pcall(wallet.AddCash, wallet, player, payout, "PlatformIncomeClaim")
		end
		if not called or type(award) ~= "table" or award.committed ~= true then
			if not wallet.TryCreditWithSource then
				context.Storage:SetUnclaimedCashExact(platformId, currentExact)
			end
			result = {
				ok = false,
				code = "AwardFailed",
				paid = 0,
				remainingExact = currentExact,
			}
			return
		end
		syncOnePlatform(context, platformId, platformClock(), true)
		if wallet.SyncBalance then
			pcall(wallet.SyncBalance, wallet, player)
		end
		result = {
			ok = true,
			code = "Collected",
			paid = payout,
			remainingExact = remaining,
		}
	end, debug.traceback)

	baseClaims[platformId] = nil
	if next(baseClaims) == nil then
		claimsInFlight[baseId] = nil
	end
	context.Storage:EndPlatformMutation(platformId, mutationToken)
	if not ok then
		log:Warn("Platform claim failed for %s/%s: %s", baseId, tostring(platformId), tostring(failure))
		return { ok = false, code = "AwardFailed" }
	end
	if result.ok and (result.paid or 0) > 0 then
		aggregateAnalytics(player, "Collected", result.paid)
		notifyCommitted(player, {
			kind = "PlatformIncomeCollected",
			eventId = baseId .. ":" .. platformId .. ":" .. tostring(platformClock()),
			at = platformClock(),
			amount = result.paid,
			baseId = baseId,
			platformId = platformId,
		})
		if analytics then
			pcall(analytics.Funnel, analytics, player, "EarlyJourney", 4)
		end
	end
	return result
end

local function diagnose(state: any, key: string, message: string, storageContext: any?)
	if state.Diagnostics[key] then
		return
	end
	state.Diagnostics[key] = true
	traceIncome(state, "income_diagnostic", { reason = key, error = message }, true)
	log:Warn(
		"Owner=%s BaseId=%s %s",
		state.Player.Name,
		tostring((storageContext or state.Storage) and (storageContext or state.Storage).BaseId),
		message
	)
end

local function calculate(state: any, snapshot: any, storageContext: any?): number
	local traceScope = if Trace.Enabled()
		then Trace.Scope({
			userId = state.UserId,
			baseId = (storageContext or state.Storage) and (storageContext or state.Storage).BaseId or "none",
			storage = Trace.Id(storageContext or state.Storage),
		})
		else nil
	local rate, diagnostics = Income.CalculateStorageRate(snapshot)
	Trace.Close(traceScope)
	for _, d in diagnostics do
		local detail = d.Code .. " item=" .. tostring(d.ItemId) .. " species=" .. tostring(d.BrainrotId)
		diagnose(state, detail, detail, storageContext)
	end
	return rate
end

local function currentStorage(player: Player, storage: any): boolean
	return player.Parent == Players
		and storage ~= nil
		and storage:IsActive()
		and storage.OwnerUserId == player.UserId
		and baseSystem:GetBase(player) == storage.Base
		and baseSystem:IsOwner(player, storage.Base)
		and storageSystem:GetStorageForPlayer(player) == storage
end

local function activate(state: any, at: number): boolean
	if state.Activated then
		return true
	end
	if not integer(at) or not wallet:IsReady(state.Player) then
		return false
	end
	state.Activated, state.LastAccruedMs = true, at
	traceIncome(state, "income_activated", { accrualAtMs = at, walletReady = true })
	return true
end

function Income:TrackPlayer(player: Player): any?
	if not started or player.Parent ~= Players or finalised[player] then
		return nil
	end
	if states[player] then
		return states[player]
	end
	if wallet == CurrencySystem then
		if not wallet:OpenAccount(player) then
			return nil
		end
	end
	if profileOwner then
		if profileOwner.Load then
			local loaded = profileOwner:Load(player)
			if not loaded then
				return nil
			end
		elseif profileOwner.GetReadableData and profileOwner:GetReadableData(player) == nil then
			return nil
		end
	end
	local at = nowMs()
	if not integer(at) then
		return nil
	end
	local state = {
		Player = player,
		UserId = player.UserId,
		Storage = nil,
		Revision = nil,
		RateTenths = 0,
		ChangedAtMs = at,
		Diagnostics = {},
		Activated = false,
		LastAccruedMs = nil,
		PendingUnits = 0,
		Flushing = false,
		Closing = false,
		Finalised = false,
		AccrualFault = false,
		CreditUncertain = false,
	}
	states[player] = state
	activate(state, at)
	traceIncome(state, "player_tracked", {
		walletReady = state.Activated,
		result = if state.Activated then "ready" else "activation_pending",
	})
	return state
end

function Income:AccrueTo(state: any, at: number, allowClosing: boolean?): (boolean, string?)
	local traced = incomeSample(state, "accrual")
	if traced then
		traceIncome(state, "accrual_enter", {
			currentAtMs = at,
			previousAtMs = state.LastAccruedMs or "none",
			pendingBefore = state.PendingUnits,
		})
	end
	local function traceReject(reason: string)
		if traced or incomeSample(state, "accrual_rejection", reason) then
			traceIncome(
				state,
				"accrual_exit",
				{ result = reason, currentAtMs = at, pendingRetained = state.PendingUnits },
				true
			)
		end
	end
	if
		states[state.Player] ~= state
		or state.Finalised
		or not state.Activated
		or (state.Closing and not allowClosing)
	then
		traceReject("INACTIVE_SESSION")
		return false, "INACTIVE_SESSION"
	end
	if not integer(at) or not integer(state.LastAccruedMs) or at < state.LastAccruedMs then
		diagnose(state, "CLOCK_ORDER", "Invalid/backwards income timestamp")
		traceReject("CLOCK_ORDER")
		return false, "CLOCK_ORDER"
	end
	if state.AccrualFault then
		traceReject("ACCRUAL_FAULT")
		return false, "ACCRUAL_FAULT"
	end
	if not finiteNonNegative(state.RateTenths) or not finiteNonNegative(state.PendingUnits) then
		state.AccrualFault = true
		diagnose(state, "NUMERIC_STATE", "Invalid income counters; accrual suspended")
		traceReject("NUMERIC_STATE")
		return false, "NUMERIC_STATE"
	end
	local elapsed = at - state.LastAccruedMs
	if state.RateTenths > 0 and elapsed > math.floor((MAX_SAFE_INTEGER - state.PendingUnits) / state.RateTenths) then
		state.AccrualFault = true
		diagnose(
			state,
			"EARNINGS_OVERFLOW",
			"Income exceeds exact integer range; pending earnings retained, accrual suspended"
		)
		traceReject("EARNINGS_OVERFLOW")
		return false, "EARNINGS_OVERFLOW"
	end
	state.PendingUnits += state.RateTenths * elapsed
	state.LastAccruedMs = at -- zero-rate time is accounted too
	if traced then
		traceIncome(state, "accrual_exit", {
			result = "accrued",
			elapsedMs = elapsed,
			currentAtMs = at,
			wholeCashDue = math.floor(state.PendingUnits / INCOME_UNITS_PER_CASH),
		})
	end
	return true, nil
end

-- A missing/late transition leaves an unknowable interval. Preserve accounted units,
-- discard no pending earnings, and start the validated current rate at a NEW boundary.
-- This is a diagnosed recovery, not retrospective payment or a historical journal.
local function resynchronise(state: any, at: number, reason: string)
	diagnose(state, "HISTORY_" .. reason, "Income history incomplete: " .. reason .. "; uncertain interval is not paid")
	if not integer(at) or (state.LastAccruedMs and at < state.LastAccruedMs) then
		state.RateTenths = 0
		return
	end
	local storage = storageSystem:GetStorageForPlayer(state.Player)
	if currentStorage(state.Player, storage) then
		local revision = storage:GetRevision()
		if integer(revision) then
			state.Storage, state.Revision = storage, revision
			state.RateTenths = calculate(state, storage:GetSnapshot())
		else
			state.Storage, state.Revision, state.RateTenths = nil, nil, 0
		end
	else
		state.Storage, state.Revision, state.RateTenths = nil, nil, 0
	end
	state.ChangedAtMs = at
	if state.Activated then
		state.LastAccruedMs = at
	end
end

function Income:BindStorage(player: Player, storage: any): boolean
	Trace.Emit("5D", "bind_enter", function()
		local f = Trace.Fields(player, nil, storage)
		f.currentRevision = states[player] and states[player].Revision or "none"
		f.currentStorage = Trace.Id(states[player] and states[player].Storage)
		return f
	end)
	if not currentStorage(player, storage) then
		Trace.Emit("5D", "bind_reject", { userId = player.UserId, reason = "not_current_authoritative_storage" }, true)
		return false
	end
	local state = self:TrackPlayer(player)
	if state == nil or state.Closing then
		Trace.Emit(
			"5D",
			"bind_reject",
			{ userId = player.UserId, reason = if state then "closing" else "session_not_tracked" },
			true
		)
		return false
	end
	if profileOwner and storage.RestorePersistentData then
		local persistentData = if profileOwner.GetReadableData
			then profileOwner:GetReadableData(player)
			else profileOwner:Get(player)
		if persistentData == nil then
			return false
		end
		local restored = storage:RestorePersistentData(persistentData)
		if not restored then
			return false
		end
	end
	if not bindPlatformStorage(player, storage, platformClock()) then
		return false
	end
	local revision = storage:GetRevision()
	if state.Storage == storage and state.Revision == revision then
		traceIncome(state, "bind_exit", { result = "already_bound" })
		return true
	end
	local at = nowMs()
	if not integer(at) or not integer(revision) then
		traceIncome(
			state,
			"bind_reject",
			{ reason = "invalid_time_or_revision", incomingRevision = revision, atMs = at },
			true
		)
		return false
	end
	if state.Storage == storage then
		resynchronise(state, at, "revision changed without notification")
		return false
	end
	state.Diagnostics = {}
	local newRate = calculate(state, storage:GetSnapshot(), storage)
	if state.Activated then
		local accrued = self:AccrueTo(state, at)
		if not accrued then
			resynchronise(state, at, "binding clock")
			return false
		end
	else
		activate(state, at)
	end
	state.Storage = storage
	state.RateTenths = newRate
	state.Revision, state.ChangedAtMs = revision, at
	traceIncome(state, "bind_exit", { result = "bound" })
	return true
end

function Income:ApplyCommittedSnapshot(
	player: Player,
	storage: any,
	revision: number,
	snapshot: any,
	changedAtMs: number
): boolean
	local state = states[player]
	Trace.Emit("5D", "income_observer_enter", function()
		local f = Trace.Fields(player, nil, storage)
		f.changedAtMs, f.incomingRevision = changedAtMs, revision
		f.oldRevision, f.oldRateTenths = state and state.Revision or "none", state and state.RateTenths or 0
		f.snapshotCount = if type(snapshot) == "table" then #snapshot else "invalid"
		f.identityMatches = state ~= nil and state.Storage == storage
		f.ownerMatches = storage ~= nil and storage.OwnerUserId == player.UserId
		return f
	end)
	if
		state == nil
		or state.Closing
		or state.UserId ~= player.UserId
		or state.Storage ~= storage
		or not currentStorage(player, storage)
		or not integer(revision)
	then
		Trace.Emit("5D", "income_observer_exit", {
			userId = player.UserId,
			result = "rejected",
			reason = if state == nil
				then "state_missing"
				elseif state.Closing then "closing"
				elseif state.UserId ~= player.UserId then "user_mismatch"
				elseif state.Storage ~= storage then "storage_identity_mismatch"
				elseif not integer(revision) then "invalid_revision"
				else "authority_or_storage_inactive",
		}, true)
		return false
	end
	if revision <= state.Revision then
		traceIncome(
			state,
			"income_observer_exit",
			{ result = "skipped", reason = "duplicate_or_stale", incomingRevision = revision }
		)
		return false
	end
	if
		revision ~= state.Revision + 1
		or revision ~= storage:GetRevision()
		or not integer(changedAtMs)
		or changedAtMs < state.ChangedAtMs
		or (state.LastAccruedMs and changedAtMs < state.LastAccruedMs)
	then
		traceIncome(state, "income_observer_exit", {
			result = "rejected",
			reason = "out_of_order_change",
			incomingRevision = revision,
			actualRevision = storage:GetRevision(),
			changeAtMs = changedAtMs,
		}, true)
		resynchronise(state, nowMs(), "out-of-order committed change")
		return false
	end
	local rate = calculate(state, snapshot)
	if state.Activated then
		local accrued = self:AccrueTo(state, changedAtMs)
		if not accrued then
			traceIncome(state, "income_observer_exit", { result = "rejected", reason = "commit_accrual_failed" }, true)
			resynchronise(state, nowMs(), "commit clock")
			return false
		end
	else
		activate(state, changedAtMs)
	end
	traceIncome(state, "rate_apply", {
		oldRevision = state.Revision,
		newRevision = revision,
		oldRateTenths = state.RateTenths,
		newRateTenths = rate,
		changeAtMs = changedAtMs,
	})
	state.RateTenths = rate
	state.Revision, state.ChangedAtMs = revision, changedAtMs
	traceIncome(state, "income_observer_exit", { result = "applied" })
	return true
end

function Income:GetIncomeRate(player: Player): number
	local context = playerPlatformContexts[player]
	if not platformContextCurrent(context) then
		return 0
	end
	local total = 0
	for _, platformId in context.Storage:GetPlatformIds() do
		total += resolveRatePerSecond(context.Storage:GetPlatformRecord(platformId), player)
	end
	return total
end

function Income:OnStorageReleasing(player: Player, storage: any, releasedAtMs: number)
	local state = states[player]
	if state == nil or state.Closing or state.Storage ~= storage or storage.OwnerUserId ~= state.UserId then
		return
	end
	if state.Activated then
		if not integer(releasedAtMs) or releasedAtMs < state.LastAccruedMs then
			resynchronise(state, nowMs(), "invalid release timestamp")
		elseif storage:GetRevision() ~= state.Revision then
			resynchronise(state, releasedAtMs, "missed revision before release")
		else
			self:AccrueTo(state, releasedAtMs)
		end
	end
	state.Storage, state.Revision, state.RateTenths = nil, nil, 0
	if integer(releasedAtMs) and releasedAtMs >= state.ChangedAtMs then
		state.ChangedAtMs = releasedAtMs
	end
end

function Income:FlushCash(player: Player, state: any, allowClosing: boolean?): any
	local traced = incomeSample(
		state,
		"credit",
		if type(state.PendingUnits) == "number" and state.PendingUnits >= INCOME_UNITS_PER_CASH
			then "due"
			else "no_whole_cash"
	)
	if traced then
		traceIncome(state, "flush_enter", { pendingBefore = state.PendingUnits })
	end
	local function traceSkip(reason: string)
		if traced or incomeSample(state, "credit_rejection", reason) then
			traceIncome(
				state,
				"flush_exit",
				{ result = reason, creditCalled = false, pendingRetained = state.PendingUnits },
				reason ~= "BUSY"
			)
		end
	end
	if
		states[player] ~= state
		or state.Player ~= player
		or state.UserId ~= player.UserId
		or state.Finalised
		or not state.Activated
		or (state.Closing and not allowClosing)
		or (not state.Closing and player.Parent ~= Players)
	then
		traceSkip("INACTIVE_SESSION")
		return { committed = false, code = "INACTIVE_SESSION" }
	end
	if state.Flushing then
		traceSkip("BUSY")
		return { committed = false, code = "BUSY" }
	end
	if state.CreditUncertain then
		traceSkip("CREDIT_OUTCOME_UNKNOWN")
		return { committed = false, code = "CREDIT_OUTCOME_UNKNOWN" }
	end
	if not finiteNonNegative(state.PendingUnits) then
		traceSkip("INVALID_PENDING")
		return { committed = false, code = "INVALID_PENDING" }
	end
	state.Flushing = true
	local result: any = { committed = false, code = "NO_WHOLE_CASH", amount = 0 }
	local ok, failure = xpcall(function()
		local due = math.floor(state.PendingUnits / INCOME_UNITS_PER_CASH)
		if due == 0 then
			if traced then
				traceIncome(
					state,
					"credit_skipped",
					{ reason = "NO_WHOLE_CASH", wholeCashDue = due, creditCalled = false }
				)
			end
			return
		end
		if not wallet:IsReady(player) then
			result.code = "ACCOUNT_UNAVAILABLE"
			if traced or incomeSample(state, "credit_failure", result.code) then
				traceIncome(state, "credit_skipped", {
					reason = result.code,
					walletReady = false,
					creditCalled = false,
					wholeCashDue = due,
				}, true)
			end
			return
		end
		-- The actual wallet has a synchronous, unambiguous commit contract. An unexpected
		-- throw is UNKNOWN, not a rejected credit: quarantine it rather than blindly retry.
		if traced then
			Trace.Emit("5D", "credit_enter", function()
				local f = Trace.Fields(player, nil, state.Storage)
				f.storageRevision, f.rateTenths = state.Revision or "none", state.RateTenths
				f.pendingUnits, f.wholeCashDue, f.unitsPerCash = state.PendingUnits, due, INCOME_UNITS_PER_CASH
				f.walletReady, f.creditCalled = true, true
				f.balanceBefore = if wallet.GetBalance then wallet:GetBalance(player) else "unavailable"
				return f
			end)
		end
		local called, credit = pcall(wallet.AddCash, wallet, player, due, "BasePassiveIncome")
		if
			traced
			or (not called or type(credit) ~= "table" or not credit.committed)
				and incomeSample(
					state,
					"credit_failure",
					if type(credit) == "table" then tostring(credit.code) else tostring(credit)
				)
		then
			Trace.Emit("5D", "credit_result", function()
				local f = Trace.Fields(player, nil, state.Storage)
				f.called, f.wholeCashDue, f.unitsPerCash = called, due, INCOME_UNITS_PER_CASH
				f.creditCommitted = type(credit) == "table" and credit.committed or false
				f.result = if type(credit) == "table" then credit.code else "CREDIT_OUTCOME_UNKNOWN"
				f.error = if called then "none" else tostring(credit)
				f.balanceAfter = if wallet.GetBalance then wallet:GetBalance(player) else "unavailable"
				f.pendingBeforeAccounting = state.PendingUnits
				return f
			end, not called or type(credit) ~= "table" or not credit.committed)
		end
		if not called or type(credit) ~= "table" or type(credit.committed) ~= "boolean" then
			state.CreditUncertain = true
			result.code, result.error = "CREDIT_OUTCOME_UNKNOWN", tostring(credit)
			return
		end
		if not credit.committed then
			result.code = credit.code or "CREDIT_REJECTED"
			return
		end
		state.PendingUnits -= due * INCOME_UNITS_PER_CASH
		result = { committed = true, code = "CREDITED", amount = due }
		if traced then
			traceIncome(
				state,
				"credit_accounted",
				{ wholeCashDue = due, creditCommitted = true, pendingAfter = state.PendingUnits }
			)
		end
	end, debug.traceback)
	state.Flushing = false
	if not ok then
		result.code, result.error = "FLUSH_ERROR", tostring(failure)
	end
	if result.code ~= "CREDITED" and result.code ~= "NO_WHOLE_CASH" then
		diagnose(
			state,
			"CREDIT_" .. result.code,
			"Cash not settled: " .. result.code .. " " .. tostring(result.error or "")
		)
	end
	-- Presentation happens AFTER pending accounting. A failed mirror cannot restore cash.
	if wallet.SyncBalance then
		if traced then
			traceIncome(state, "wallet_mirror_enter", { creditCommitted = result.committed })
		end
		local called, mirrored, mirrorError = pcall(wallet.SyncBalance, wallet, player)
		if traced or (not called or not mirrored) and incomeSample(state, "mirror_failure") then
			traceIncome(state, "wallet_mirror_exit", {
				creditCommitted = result.committed,
				mirrorCalled = called,
				mirrored = mirrored,
				error = if called then mirrorError or "none" else tostring(mirrored),
				pendingAfter = state.PendingUnits,
			}, not called or not mirrored)
		end
		if not called or not mirrored then
			diagnose(
				state,
				"CASH_MIRROR",
				"Cash mirror unavailable: " .. tostring(if called then mirrorError else mirrored)
			)
		end
	end
	if traced then
		traceIncome(state, "flush_exit", {
			result = result.code,
			creditCommitted = result.committed,
			pendingAfter = state.PendingUnits,
			error = result.error or "none",
		}, result.error ~= nil)
	end
	return result
end

-- Called by PlayerDataService immediately before one coherent profile snapshot.
-- The supplied server-time cutoff is not persisted, so reconnecting never earns
-- the elapsed offline interval.
function Income:PrepareForSave(player: Player, at: number?): (boolean?, string?)
	local cutoff = at
	if cutoff == nil then
		cutoff = platformClock()
	end
	if not started or not validPlatformTime(cutoff) then
		return nil, "INVALID_TIME"
	end
	local context = playerPlatformContexts[player]
	if not platformContextCurrent(context) then
		return false, nil
	end
	local before = 0
	for _, platformId in context.Storage:GetPlatformIds() do
		before += context.Storage:GetUnclaimedCashExact(platformId) or 0
	end
	local accrued, reason = self:AccruePlatformsTo(cutoff)
	if not accrued then
		return nil, reason
	end
	local after = 0
	for _, platformId in context.Storage:GetPlatformIds() do
		after += context.Storage:GetUnclaimedCashExact(platformId) or 0
	end
	syncPlatformContext(context, cutoff, false)
	local changed = after ~= before
	local coordinatedProfile = profileOwner and profileOwner.GetReadableData ~= nil
	if coordinatedProfile and profileOwner.IsWritable and not profileOwner:IsWritable(player) then
		-- This is the profile owner's close-cutoff pass. No subsequent teardown or
		-- release callback may advance the live-session clock beyond this instant.
		context.AccrualStopped = true
		context.LastAccrualTime = cutoff
	end
	-- A normal Ready accrual already marked the profile dirty. During Closing,
	-- MarkDirty is intentionally unavailable, so ask the snapshot owner to
	-- advance the revision for this authorized final settlement.
	if changed and profileOwner and profileOwner.IsWritable and profileOwner:IsWritable(player) then
		return false, nil
	end
	return changed, nil
end

-- One per-player aggregate per minute; internal transfers are not a second cash source.
function Income:FlushAnalytics(at: number, force: boolean?, onlyPlayer: Player?)
	for player, bucket in analyticsBuckets do
		if (not onlyPlayer or player == onlyPlayer) and (force or at - bucket.StartedAt >= 60) then
			local data = if profileOwner and profileOwner.GetReadableData
				then profileOwner:GetReadableData(player)
				else nil
			if bucket.Produced > 0 then
				if data then
					local total = require(ReplicatedStorage.Shared.Utility.Phase13Rules).Cash(data)
					if total then
						pcall(
							analytics.Economy,
							analytics,
							player,
							"Source",
							bucket.Produced,
							total,
							"Cash",
							"PLATFORM_PRODUCTION"
						)
					end
				end
				pcall(
					analytics.Record,
					analytics,
					player,
					"ProductionSummary",
					bucket.Produced,
					{ category = "Cash", result = "Recorded" }
				)
			end
			if bucket.Collected > 0 then
				pcall(
					analytics.Record,
					analytics,
					player,
					"CollectionSummary",
					bucket.Collected,
					{ category = "Collection", result = "Recorded" }
				)
			end
			analyticsBuckets[player] = nil
		end
	end
end

function Income:FinalizePlayerSession(player: Player, closingAtMs: number): any
	local state = states[player]
	if state == nil then
		return { ok = true, code = "ALREADY_FINALISED" }
	end
	if not integer(closingAtMs) then
		return { ok = false, code = "INVALID_TIME" }
	end
	-- Session close accrues and snapshots platform ledgers, but never converts them into cash.
	local context = playerPlatformContexts[player]
	if not (context and context.AccrualStopped) then
		self:AccruePlatformsTo(platformClock())
	end
	local unclaimedExact = 0
	if platformContextCurrent(context) then
		syncPlatformContext(context, platformClock(), false)
		persistPlatformContext(context)
		for _, platformId in context.Storage:GetPlatformIds() do
			unclaimedExact += context.Storage:GetUnclaimedCashExact(platformId) or 0
		end
	end
	self:FlushAnalytics(platformClock(), true, player)
	state.Closing, state.ClosingAtMs = true, closingAtMs
	state.Storage, state.Revision, state.RateTenths = nil, nil, 0
	local coordinatedProfile = profileOwner and profileOwner.GetReadableData ~= nil
	if not coordinatedProfile and wallet.BeginClosing then
		wallet:BeginClosing(player)
	end
	if profileOwner and profileOwner.Release then
		profileOwner:Release(player)
	end
	state.Finalised, finalised[player], states[player] = true, true, nil
	if wallet.ReleaseAccount then
		wallet:ReleaseAccount(player)
	end
	if context then
		clearPlatformContext(context)
	end
	traceIncome(state, "session_finalised", { unclaimedCashExact = unclaimedExact })
	Trace.Forget(player)
	return { ok = true, code = "FINALISED", unclaimedCashExact = unclaimedExact }
end

function Income:UntrackPlayer(player: Player): any
	return self:FinalizePlayerSession(player, nowMs())
end

function Income:GetStateSnapshot(player: Player): any?
	local state = states[player]
	if not state then
		return nil
	end
	local context = playerPlatformContexts[player]
	local exact, revision = 0, 0
	if platformContextCurrent(context) then
		for _, platformId in context.Storage:GetPlatformIds() do
			exact += context.Storage:GetUnclaimedCashExact(platformId) or 0
			local snapshot = context.Snapshots[platformId]
			revision += if snapshot then snapshot.Revision else 0
		end
	end
	local rate = self:GetIncomeRate(player)
	local accruedMs = if platformLastAccrualTime then math.floor(platformLastAccrualTime * 1000) else nil
	return table.freeze({
		UserId = state.UserId,
		BaseId = context and context.BaseId or nil,
		Revision = revision,
		RateTenths = math.round(rate * 10),
		RatePerSecond = rate,
		ChangedAtMs = accruedMs,
		Activated = state.Activated,
		LastAccruedMs = accruedMs,
		PendingUnits = math.round(exact * INCOME_UNITS_PER_CASH),
		UnclaimedCashExact = exact,
		Closing = state.Closing,
		AccrualFault = state.AccrualFault,
		CreditUncertain = state.CreditUncertain,
	})
end

function Income:Step(): (boolean, string?)
	if not started then
		return false, "NOT_STARTED"
	end
	local at = platformClock()
	local accrued, reason = self:AccruePlatformsTo(at)
	for player, context in playerPlatformContexts do
		local data = if profileOwner and profileOwner.GetReadableData then profileOwner:GetReadableData(player) else nil
		if data and CommerceRules.HasEntitlement(data, "AUTO_COLLECT") and not context.AccrualStopped then
			for _, id in context.Storage:GetPlatformIds() do
				self:TryClaimPlatform(player, context.BaseId, id)
			end
		end
	end
	self:FlushAnalytics(at, false)
	if profileOwner and profileOwner.Autosave then
		profileOwner:Autosave(at)
	end
	return accrued, reason
end

function Income:Init(dependencies: any?): boolean
	if started then
		return false
	end
	initialDependencies = dependencies or {}
	return true
end

function Income:Start(dependencies: any?): boolean
	Trace.Emit("BOOT", "income_start", {
		module = script,
		alreadyStarted = started,
		intervalSeconds = PAYOUT_INTERVAL,
		unitsPerCash = INCOME_UNITS_PER_CASH,
	})
	if started then
		return false
	end
	local deps = dependencies or initialDependencies or {}
	analytics = if deps.Analytics == false
		then nil
		else deps.Analytics or require(script.Parent.Parent.Services.Phase13AnalyticsService)
	storageSystem, baseSystem = deps.Storage or BaseStorageSystem, deps.Base or PlayerBaseSystem
	wallet = deps.Wallet or CurrencySystem
	profileOwner = if deps.Profile == false then nil elseif deps.Profile ~= nil then deps.Profile else nil
	if profileOwner and profileOwner.Start and profileOwner.GetReadableData == nil then
		profileOwner:Start(deps.ProfileDependencies)
	end
	if deps.Now then
		platformClock = deps.Now
	elseif deps.NowMs then
		platformClock = function(): number
			return deps.NowMs() / 1000
		end
	else
		platformClock = function(): number
			return Workspace:GetServerTimeNow()
		end
	end
	platformRateResolver = deps.ResolvePlatformRate
		or function(brainrotId: any): (number?, string?)
			return Catalog.GetCashPerSecond(brainrotId)
		end
	nowMs = function(): number
		return math.floor(platformClock() * 1000)
	end
	platformLastAccrualTime = platformClock()
	started = true
	Trace.Emit("BOOT", "income_subscribe_enter", { module = script.Parent.BaseStorageSystem })
	unsubscribe = storageSystem:ObserveStorage({
		OnBound = function(player, storage)
			self:TrackPlayer(player)
			self:BindStorage(player, storage)
		end,
		OnChanging = function()
			self:AccruePlatformsTo(platformClock())
		end,
		OnCommitted = function(player, storage, revision, snapshot)
			local at = platformClock()
			self:AccruePlatformsTo(at)
			local context = playerPlatformContexts[player]
			if context == nil or context.Storage ~= storage then
				bindPlatformStorage(player, storage, at)
				context = playerPlatformContexts[player]
			end
			if platformContextCurrent(context) then
				syncPlatformContext(context, at, false)
			end
			-- Keep the pre-5D diagnostic state coherent for existing server tests and
			-- telemetry. Only platform ledgers are scheduled; this path never pays cash.
			self:ApplyCommittedSnapshot(player, storage, revision, snapshot, nowMs())
		end,
		OnReleasing = function(player, storage)
			local at = platformClock()
			self:AccruePlatformsTo(at)
			self:OnStorageReleasing(player, storage, nowMs())
			local context = playerPlatformContexts[player]
			if context and context.Storage == storage then
				syncPlatformContext(context, at, false)
				persistPlatformContext(context)
				clearPlatformContext(context)
			end
		end,
	})
	Trace.Emit("BOOT", "income_subscribe_exit", { registered = unsubscribe ~= nil })
	local function track(player)
		self:TrackPlayer(player)
		local storage = storageSystem:GetStorageForPlayer(player)
		if storage then
			self:BindStorage(player, storage)
		end
	end
	table.insert(connections, Players.PlayerAdded:Connect(track))
	if deps.ProfileReadySignal then
		table.insert(connections, deps.ProfileReadySignal(track))
	end
	if profileOwner and profileOwner.SubscribeCloseRequested then
		table.insert(
			connections,
			profileOwner:SubscribeCloseRequested(function(player)
				self:MarkDepartureCutoff(player, platformClock())
			end)
		)
	end
	-- A coordinated player profile owns close ordering. Its snapshot preparer
	-- captures the income cutoff and its finalizer unbinds runtime state. The
	-- legacy platform store keeps the older base-session closing subscription.
	if not (profileOwner and profileOwner.GetReadableData ~= nil) then
		table.insert(
			connections,
			baseSystem:SubscribeSessionClosing(function(player)
				self:FinalizePlayerSession(player, nowMs())
			end)
		)
	end
	for _, player in Players:GetPlayers() do
		track(player)
	end
	if deps.ConnectScheduler ~= false then
		local heartbeat = deps.Heartbeat or RunService.Heartbeat
		table.insert(
			connections,
			heartbeat:Connect(function(deltaTime)
				accumulator += deltaTime
				if accumulator >= PAYOUT_INTERVAL then
					accumulator %= PAYOUT_INTERVAL
					self:Step()
				end
			end)
		)
	end
	Trace.Emit("BOOT", "income_ready", {
		started = started,
		observerRegistered = unsubscribe ~= nil,
		payoutProcessingStarted = false,
		connections = #connections,
	})
	return true
end

function Income:Stop(): boolean
	if not started then
		return true
	end
	local tracked = {}
	for player in states do
		table.insert(tracked, player)
	end
	for _, player in tracked do
		self:FinalizePlayerSession(player, nowMs())
	end
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(analyticsBuckets)
	analytics = nil
	table.clear(platformContexts)
	table.clear(playerPlatformContexts)
	table.clear(claimsInFlight)
	table.clear(warnedPlatformKeys)
	warnedPlatformKeyCount = 0
	warningCacheSaturated = false
	accumulator = 0
	platformLastAccrualTime = nil
	initialDependencies = nil
	started = false
	if profileOwner and profileOwner.Stop and profileOwner.GetReadableData == nil then
		profileOwner:Stop()
	end
	profileOwner = nil
	storageSystem, baseSystem, wallet = BaseStorageSystem, PlayerBaseSystem, CurrencySystem
	platformClock = function(): number
		return Workspace:GetServerTimeNow()
	end
	platformRateResolver = function(brainrotId: any): (number?, string?)
		return Catalog.GetCashPerSecond(brainrotId)
	end
	nowMs = function(): number
		return math.floor(os.clock() * 1000)
	end
	return true
end

function Income:Destroy(): boolean
	return self:Stop()
end

-- Freeze settlement, not elapsed time. The coordinator resumes from the cutover after durable confirmation.
function Income:MarkDepartureCutoff(player: Player, at: number): boolean
	if not validPlatformTime(at) then
		return false
	end
	local context = playerPlatformContexts[player]
	if not context or context.DepartureAt then
		return true
	end
	context.DepartureAt = at
	if started then
		self:AccruePlatformsTo(at)
	end
	if not context.CriticalToken then
		context.AccrualStopped = true
	end
	return true
end
function Income:BeginCriticalCutover(player: Player, at: number): (any?, string?)
	local context = playerPlatformContexts[player]
	if context and context.CriticalToken then
		return nil, "INCOME_BUSY"
	end
	if started then
		local ok, reason = self:AccruePlatformsTo(at)
		if not ok then
			return nil, reason
		end
	end
	local token = { Player = player, Cutover = at, Context = context }
	if context then
		context.CriticalToken = token
		context.AccrualStopped = true
		context.LastAccrualTime = at
	end
	return token, nil
end
function Income:EndCriticalCutover(player: Player, token: any, at: number): boolean
	local context = playerPlatformContexts[player]
	if context and context.CriticalToken ~= token then
		return false
	end
	if context then
		context.CriticalToken = nil
		context.LastAccrualTime = token.Cutover
		context.AccrualStopped = false
		syncPlatformContext(context, token.Cutover, true)
	end
	if started then
		self:AccruePlatformsTo(at)
	end
	if context and context.DepartureAt then
		context.AccrualStopped = true
	end
	return true
end

return Income
