--!strict

-- Phase 7G-1 integration owner. It observes existing authoritative receipts and
-- keeps bounded, session-local reports. It does not settle income, mutate a
-- profile, request a save, or call a gameplay transaction.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local ProgressionMetrics = require(script.Parent.Parent.Analytics.ProgressionMetrics)
local PlayerDataConfig = require(script.Parent.Parent.Config.PlayerDataConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerWorldLifecycle = require(script.Parent.PlayerWorldLifecycle)
local CartService = require(script.Parent.CartService)
local UpgradeService = require(script.Parent.UpgradeService)
local BaseStorageSystem = require(script.Parent.Parent.Systems.BaseStorageSystem)
local BrainrotIncomeSystem = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
local BrainrotInteractionSystem = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
local BrainrotSaleSystem = require(script.Parent.Parent.Systems.BrainrotSaleSystem)
local CurrencySystem = require(script.Parent.Parent.Systems.CurrencySystem)
local RegionSpawnCatalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldProgression)

local REPORT_INTERVAL_SECONDS = 60
local COMPLETED_REPORT_LIMIT = 20
local REGION_SAMPLE_SECONDS = 0.5
local REGION_STABLE_SECONDS = 1
local DETACHED_CLOSE_SECONDS = PlayerDataConfig.FinalCloseDeadlineSeconds + 10

local log = Logger.new("ProgressionMetricsService")
local ProgressionMetricsService = {}

local started = false
local dependencies: any = nil
local active: { [Player]: any } = {}
local joinedAt: { [Player]: number } = {}
local loadDetails: { [Player]: any } = {}
local connections: { any } = {}
local completedReports: { any } = {}
local reportAccumulator = 0
local sampleAccumulator = 0
local detached: { [string]: any } = {}
local detachedOrder: { string } = {}
local appendCompleted: (any) -> ()

local function defaultDependencies(): any
	return {
		Players = Players,
		Profile = PlayerDataService,
		Upgrade = UpgradeService,
		Currency = CurrencySystem,
		Income = BrainrotIncomeSystem,
		Storage = BaseStorageSystem,
		Interaction = BrainrotInteractionSystem,
		Sale = BrainrotSaleSystem,
		Catalog = BrainrotCatalog,
		WorldLifecycle = PlayerWorldLifecycle,
		Regions = RegionSpawnCatalog,
		ConnectScheduler = true,
		LogReports = true,
		ReadLocation = function(player: Player): any
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local cart = CartService:GetCart(player)
			return {
				character = character,
				position = if root and root:IsA("BasePart") then root.Position else nil,
				alive = humanoid ~= nil and humanoid.Health > 0,
				cartResetting = cart ~= nil and cart:GetAttribute("ResetActive") == true,
			}
		end,
		Environment = Environment,
		Now = function(): number
			return Workspace:GetServerTimeNow()
		end,
		GenerateObservationId = function(): string
			return HttpService:GenerateGUID(false)
		end,
	}
end

local function deps(): any
	assert(dependencies ~= nil, "ProgressionMetricsService is not initialized")
	return dependencies
end

local function disconnect(connection: any)
	if type(connection) == "function" then
		connection()
	elseif connection and connection.Disconnect then
		connection:Disconnect()
	end
end

local function copyReceipt(receipt: any, at: number): any
	local result = table.clone(receipt or {})
	result.sourceAt = result.at
	result.receivedAt = at
	-- Producers include process clocks and server-aligned clocks. Their monetary
	-- facts are immutable; compare only this shared server-receipt time basis.
	result.at = at
	return result
end

local function profileSlots(data: any): any
	return if type(data) == "table"
			and type(data.Base) == "table"
			and type(data.Base.Slots) == "table"
		then data.Base.Slots
		else {}
end

local function ownedIndividuals(data: any): any
	return if type(data) == "table"
			and type(data.Collection) == "table"
			and type(data.Collection.BrainrotInstances) == "table"
		then data.Collection.BrainrotInstances
		else {}
end

local function startingProgression(data: any): any
	local result = {}
	local progression = if type(data) == "table" then data.Progression else nil
	if type(progression) ~= "table" then
		return result
	end
	for _, field in { "Upgrades", "OwnedOffers", "UpgradeLevels", "OwnedWeapons" } do
		local source = progression[field]
		if type(source) == "table" then
			for id, value in source do
				if
					type(id) == "string"
					and (
						type(value) == "boolean"
						or type(value) == "number"
						or type(value) == "string"
					)
				then
					result[field .. ":" .. id] = value
				end
			end
		end
	end
	return result
end

local function snapshotStartingState(data: any): (any, any)
	local slots = profileSlots(data)
	local owned = ownedIndividuals(data)
	local platformCash = 0
	local occupied = 0
	local passiveRate = 0
	for _, slot in slots do
		if type(slot) == "table" then
			local cash = slot.accumulatedCash
			if type(cash) == "number" and cash == cash and cash >= 0 and cash < math.huge then
				platformCash += cash
			end
			local individualId = slot.brainrotId
			local record = if type(individualId) == "string" then owned[individualId] else nil
			if type(record) == "table" then
				occupied += 1
				local rate = deps().Catalog.GetCashPerSecond(record.speciesId)
				if type(rate) == "number" and rate == rate and rate >= 0 and rate < math.huge then
					passiveRate += rate
				end
			end
		end
	end
	local startingIds = {}
	local bankedCount = 0
	for individualId in owned do
		if type(individualId) == "string" then
			startingIds[individualId] = true
			bankedCount += 1
		end
	end
	local economy = if type(data) == "table" then data.Economy else nil
	local wallet = if type(economy) == "table" and type(economy.Balance) == "number"
		then economy.Balance
		else 0
	local progression = if type(data) == "table" then data.Progression else nil
	return {
		wallet = wallet,
		settledPlatformCash = platformCash,
		occupiedSlotCount = occupied,
		bankedIndividualCount = bankedCount,
		passiveIncomeRate = passiveRate,
		ownedProgression = startingProgression(data),
		selectedCartId = if type(progression) == "table" and progression.EquippedCartId
			then progression.EquippedCartId
			else Ids.Carts.ScrapChariot,
		selectedWeaponId = if type(progression) == "table"
			then progression.EquippedWeaponId or progression.SelectedWeaponId or Weapons.StarterWeaponId
			else Weapons.StarterWeaponId,
	},
		startingIds
end

local function currentEntry(player: Player, receipt: any?): any?
	local entry = active[player]
	if not entry or not deps().Profile:IsCurrentSessionHandle(entry.Session) then
		return nil
	end
	local generation = receipt and (receipt.sessionGeneration or receipt.generation)
	if generation ~= nil and generation ~= entry.Session.Generation then
		entry.Metrics.coverage.staleReceiptsRejected = (
			entry.Metrics.coverage.staleReceiptsRejected or 0
		) + 1
		return nil
	end
	if receipt and generation == nil then
		entry.Metrics.coverage.unstampedReceipts = (entry.Metrics.coverage.unstampedReceipts or 0)
			+ 1
	end
	return entry
end

local function metricsFor(player: Player, receipt: any?): any?
	local entry = currentEntry(player, receipt)
	return if entry then entry.Metrics else nil
end

local function refreshOffers(player: Player, at: number, baseline: boolean?)
	local entry = currentEntry(player)
	if not entry or entry.WorldReady ~= true then
		return
	end
	local ok, offers = pcall(deps().Upgrade.GetMeasurementOffers, deps().Upgrade, player)
	if not ok or type(offers) ~= "table" then
		entry.Metrics.coverage.offerEvaluation = "UNAVAILABLE"
		-- Keep historical milestones, but an unknown current evaluation cannot
		-- extend an affordability window or advertise a current reference goal.
		entry.Metrics:ReconcileOfferCandidates({}, at)
		return
	end
	entry.Metrics.coverage.offerEvaluation = "AVAILABLE"
	local keys = {}
	for _, offer in offers do
		table.insert(
			keys,
			offer.offerKey or (offer.offerId .. "|" .. offer.targetKey .. "|" .. offer.termsVersion)
		)
		entry.Metrics:ObserveOfferState({
			at = at,
			offerId = offer.offerId,
			targetKey = offer.targetKey,
			termsVersion = offer.termsVersion,
			price = offer.price,
			ownedAtStart = offer.owned,
			owned = offer.owned,
			fundsSufficient = offer.fundsSufficient,
			ready = offer.ready,
			prerequisitesSatisfied = offer.prerequisitesSatisfied,
			pathBlocked = offer.pathBlocked,
			primaryReason = offer.primaryReason,
			displayOrder = offer.displayOrder,
			isBaseline = baseline == true,
			baselineWallet = if baseline then entry.Metrics.currentWallet else nil,
		})
	end
	entry.Metrics:ReconcileOfferCandidates(keys, at)
end

local function beginSession(player: Player, profileOrigin: string, partial: boolean)
	local existing = currentEntry(player)
	if existing then
		return existing
	end
	local previous = active[player]
	if previous then
		previous.Metrics.coverage.endingAuthorityUnavailable = true
		previous.Metrics.observationCompleteness = "PARTIAL_OBSERVATION"
		previous.Metrics:BeginDeparture(deps().Now())
		appendCompleted(previous.Metrics:BuildReport(deps().Now()))
		for _, connection in previous.Connections do
			disconnect(connection)
		end
		active[player] = nil
	end
	local session = deps().Profile:GetSessionHandle(player)
	if session == nil or not deps().Profile:IsCurrentSessionHandle(session) then
		return nil
	end
	local data = deps().Profile:GetReadableData(player)
	if data == nil then
		return nil
	end
	local at = deps().Now()
	local startingState, startingIds = snapshotStartingState(data)
	local diagnostics = deps().Profile:GetDiagnostics(player)
	local entry = {
		Session = session,
		Closing = false,
		Connections = {},
		Metrics = ProgressionMetrics.new({
			joinAt = joinedAt[player] or at,
			profileReadyAt = at,
			measurementStartedAt = at,
			observationId = deps().GenerateObservationId(),
			buildId = deps().Environment.BuildId,
			configurationId = deps().ConfigurationId or string.format(
				"%s:schema-%d:%s",
				deps().Environment.BuildId,
				PlayerDataConfig.SchemaVersion,
				deps().Environment.Name
			),
			environment = deps().Environment.Name,
			profileOrigin = profileOrigin,
			audioVariant = player:GetAttribute("AudioVariant"),
			partialObservation = partial,
			startingState = startingState,
			startingOwnedIndividuals = startingIds,
			coverage = {
				expeditionBoundaries = "SERVER_REGION_SAMPLE_0.5S_STABLE_1S",
				offerCardExposure = "MENU_RENDER_ONLY_UNLESS_EXPLICITLY_INSPECTED",
				profileGeneration = if diagnostics then diagnostics.generation else nil,
				accountingStartedAt = at,
				timestampBasis = "SERVER_RECEIPT_TIME",
				profileLoadRetries = if loadDetails[player] then loadDetails[player].Retries else 0,
				equipmentSource = "CURRENT_STARTER_DEFAULTS_UNLESS_SAVED_SELECTION_EXISTS",
			},
		}),
		WorldReady = false,
	}
	active[player] = entry
	loadDetails[player] = nil
	if player.CharacterRemoving then
		table.insert(
			entry.Connections,
			player.CharacterRemoving:Connect(function()
				if currentEntry(player) == entry then
					entry.Metrics:InterruptOuting("CharacterDeathReset", deps().Now())
					entry.RegionKey = nil
					entry.RegionCandidate = nil
				end
			end)
		)
	end
	return entry
end

local function markWorldReady(player: Player)
	local entry = currentEntry(player)
	if not entry then
		local diagnostics = deps().Profile:GetDiagnostics(player)
		entry = beginSession(
			player,
			if diagnostics and diagnostics.profileOrigin
				then diagnostics.profileOrigin
				else "UnknownOrigin",
			true
		)
	end
	if entry and entry.WorldReady ~= true and deps().WorldLifecycle:IsReady(player) then
		local at = deps().Now()
		entry.WorldReady = true
		entry.Metrics:SetWorldReady(at)
		refreshOffers(player, at, true)
	elseif entry and entry.WorldReady and not entry.Closing then
		refreshOffers(player, deps().Now())
	end
end

appendCompleted = function(report: any)
	table.insert(completedReports, report)
	if #completedReports > COMPLETED_REPORT_LIMIT then
		table.remove(completedReports, 1)
	end
end

local function logSummary(player: Player, report: any, final: boolean)
	if deps().LogReports == false then
		return
	end
	local economy = report.economy
	log:Info(
		"ProgressionSession%s userId=%d observationId=%s origin=%s wallet=%.2f platform=%.2f generated=%.2f collected=%.2f debits=%.2f reconciled=%s offers=%d audio=%s",
		if final then "Closed" else "Progress",
		player.UserId,
		report.session.observationId,
		report.session.profileOrigin,
		economy.endingWallet,
		economy.endingSettledPlatformCash,
		economy.platformIncomeGenerated,
		economy.platformCashCollected,
		economy.walletDebits,
		tostring(economy.reconciled),
		#report.offers,
		tostring(report.session.audioVariant)
	)
end

local function endingSnapshot(player: Player, entry: any, at: number, final: boolean): boolean
	local data = deps().Profile:GetReadableData(player)
	if data == nil or not deps().Profile:IsCurrentSessionHandle(entry.Session) then
		entry.Metrics.coverage.endingAuthorityUnavailable = true
		return false
	end
	local snapshot = snapshotStartingState(data)
	local collectible = nil
	local storage = if deps().Storage.GetStorageForPlayer
		then deps().Storage:GetStorageForPlayer(player)
		else nil
	local income = if deps().Income.GetStateSnapshot
		then deps().Income:GetStateSnapshot(player)
		else nil
	if
		storage
		and storage:IsActive()
		and storage.OwnerUserId == player.UserId
		and storage:IsBoundToProfile(data)
		and income
		and income.Activated
		and (not deps().Profile.IsWritable or deps().Profile:IsWritable(player))
	then
		collectible = 0
		for _, slot in storage:GetPlatformIds() do
			collectible += storage:GetUnclaimedCashExact(slot) or 0
		end
	end
	entry.Metrics.coverage.endingAuthorityUnavailable = nil
	entry.Metrics.coverage.authoritativeBalanceObservedAt = at
	entry.Metrics:SetEndingState(
		snapshot.wallet,
		snapshot.settledPlatformCash,
		at,
		collectible,
		final
	)
	return true
end

local function detachKey(userId: number, generation: number): string
	return tostring(userId) .. ":" .. tostring(generation)
end

local function clearEntry(player: Player, entry: any)
	for _, connection in entry.Connections do
		disconnect(connection)
	end
	active[player] = nil
	joinedAt[player] = nil
	loadDetails[player] = nil
end

local function detachSummary(player: Player, at: number, reason: string)
	local entry = currentEntry(player)
	if not entry then
		return
	end
	entry.Closing = true
	entry.Metrics:BeginDeparture(at)
	endingSnapshot(player, entry, at, true)
	local report = entry.Metrics:BuildReport(at)
	report.persistence.closeStatus = reason
	report.session.clocks.reportClosedAt = nil
	report.session.clocks.gameplaySummaryAt = at
	local key = detachKey(player.UserId, entry.Session.Generation)
	detached[key] = { Report = report, Deadline = at + DETACHED_CLOSE_SECONDS }
	table.insert(detachedOrder, key)
	while #detachedOrder > COMPLETED_REPORT_LIMIT do
		local evicted = table.remove(detachedOrder, 1)
		local pending = detached[evicted]
		if pending then
			pending.Report.persistence.closeStatus = "UnconfirmedDiagnosticRetentionLimit"
			appendCompleted(pending.Report)
			detached[evicted] = nil
		end
	end
	logSummary(player, report, true)
	clearEntry(player, entry)
end

local function pendingFor(player: Player, receipt: any): (any?, string?)
	local generation = receipt.sessionGeneration or receipt.generation
	if type(generation) ~= "number" then
		return nil, nil
	end
	local key = detachKey(player.UserId, generation)
	return detached[key], key
end

local function observeDetached(player: Player, receipt: any, at: number): boolean
	local pending, key = pendingFor(player, receipt)
	if not pending then
		return false
	end
	local report = pending.Report
	if receipt.kind == "SaveConfirmed" or receipt.kind == "PurchaseSaveConfirmed" then
		local covered = receipt.revision or receipt.commitRevision
		if type(covered) == "number" then
			report.persistence.lastConfirmedRevision =
				math.max(report.persistence.lastConfirmedRevision or 0, covered)
			for _, offer in report.offers do
				if
					type(offer.purchaseCommitRevision) == "number"
					and offer.purchaseCommitRevision <= covered
					and offer.persistence ~= "Confirmed"
				then
					offer.persistence = "Confirmed"
					offer.purchaseSavedAt = at
					offer.purchaseConfirmationLatency = if type(offer.purchaseCommittedAt)
								== "number"
							and at >= offer.purchaseCommittedAt
						then at - offer.purchaseCommittedAt
						else nil
					report.persistence.pendingPurchaseCount =
						math.max(0, report.persistence.pendingPurchaseCount - 1)
				end
			end
		end
	elseif receipt.kind == "CloseCompleted" or receipt.kind == "CloseUnconfirmed" then
		report.persistence.closeStatus = if receipt.kind == "CloseCompleted"
			then "Confirmed"
			else "Unconfirmed"
		report.persistence.closeCode = receipt.code
		report.session.clocks.reportClosedAt = at
		appendCompleted(report)
		detached[key] = nil
		local index = table.find(detachedOrder, key)
		if index then
			table.remove(detachedOrder, index)
		end
	end
	return true
end

local function recordUnreadyEnd(player: Player, at: number, reason: string)
	local joined = joinedAt[player]
	if joined == nil then
		return
	end
	appendCompleted({
		session = {
			observationId = deps().GenerateObservationId(),
			buildId = deps().Environment.BuildId,
			environment = deps().Environment.Name,
			profileOrigin = "UnknownOrigin",
			audioVariant = tostring(player:GetAttribute("AudioVariant") or "Unknown"),
			observationCompleteness = "PROFILE_NOT_READY",
			clocks = { joinAt = joined, reportClosedAt = at },
		},
		startingState = { status = "NOT_OBSERVED" },
		economy = { status = "NOT_OBSERVED", reconciled = false },
		offers = {},
		persistence = {
			loadFailure = reason,
			closeStatus = "NotLoaded",
			loadRetries = if loadDetails[player] then loadDetails[player].Retries else 0,
		},
	})
	joinedAt[player] = nil
	loadDetails[player] = nil
end

local function observeIntroducedAcquisition(player: Player,entry: any,receipt: any)
	if receipt.kind~="WildAcquired" or type(receipt.individualId)~="string"
		or type(receipt.speciesId)~="string" or deps().Regions==false then return end
	local location=deps().ReadLocation(player)
	local region=location and location.position and deps().Regions.GetRegionAtPosition(location.position)
	local definition=region and WorldConfig.ById[region.id]
	local pool=definition and WorldConfig.Pools[definition.regionId]
	if not definition or definition.index<=1 or not pool then return end
	local present=false
	for _,ids in pool.species do if table.find(ids,receipt.speciesId) then present=true break end end
	if not present then return end
	for _,earlier in WorldConfig.Ordered do
		if earlier.index>=definition.index then break end
		local previous=WorldConfig.Pools[earlier.regionId]
		if previous then
			for _,ids in previous.species do if table.find(ids,receipt.speciesId) then return end end
		end
	end
	entry.Metrics:_boundedSet("phase8IntroducedIndividuals",receipt.individualId,{key=definition.key,speciesId=receipt.speciesId})
	entry.Metrics:ObserveWorldProgression({kind="FirstIntroducedRegionCatch",key=definition.key,
		speciesId=receipt.speciesId,individualId=receipt.individualId,at=deps().Now(),eventId=receipt.eventId})
end

function ProgressionMetricsService:Start(options: any?): boolean
	if started then
		return false
	end
	dependencies = defaultDependencies()
	for key, value in options or {} do
		dependencies[key] = value
	end
	started = true

	for _, player in deps().Players:GetPlayers() do
		joinedAt[player] = deps().Now()
		local diagnostics = deps().Profile:GetDiagnostics(player)
		if diagnostics and diagnostics.status == "Ready" then
			beginSession(player, diagnostics.profileOrigin or "UnknownOrigin", true)
		end
	end
	table.insert(
		connections,
		deps().Players.PlayerAdded:Connect(function(player)
			joinedAt[player] = deps().Now()
		end)
	)
	table.insert(
		connections,
		deps().Players.PlayerRemoving:Connect(function(player)
			local entry = currentEntry(player)
			if entry then
				entry.Closing = true
				entry.CloseDeadline = deps().Now() + DETACHED_CLOSE_SECONDS
				entry.Metrics:BeginDeparture(deps().Now())
			else
				recordUnreadyEnd(player, deps().Now(), "DisconnectedBeforeProfileReady")
			end
		end)
	)

	table.insert(
		connections,
		deps().Profile:SubscribeDiagnostics(function(player, receipt)
			local at = deps().Now()
			if observeDetached(player, receipt, at) then
				return
			end
			local currentSession = deps().Profile:GetSessionHandle(player)
			if
				currentSession
				and receipt.generation ~= nil
				and receipt.generation ~= currentSession.Generation
			then
				return
			end
			if receipt.kind == "LoadStarted" then
				joinedAt[player] = joinedAt[player] or at
				loadDetails[player] = { Retries = 0 }
			elseif receipt.kind == "LoadRetry" then
				local details = loadDetails[player]
				if details then
					details.Retries += 1
				end
			elseif receipt.kind == "LoadCompleted" then
				beginSession(player, receipt.profileOrigin or "UnknownOrigin", false)
			end
			local metrics = metricsFor(player, receipt)
			if metrics then
				if receipt.kind == "PlatformCashDiscarded" then
					local observed = copyReceipt(receipt, at)
					observed.kind = "PlatformAdjustment"
					metrics:ObserveEconomic(observed)
				end
				metrics:ObserveDiagnostic(copyReceipt(receipt, at))
				if receipt.kind == "CloseStarted" then
					metrics:BeginDeparture(at, receipt.reason or "Disconnect")
					local entry = currentEntry(player, receipt)
					entry.Closing = true
					entry.CloseDeadline = at + DETACHED_CLOSE_SECONDS
				elseif receipt.kind == "SessionLost" then
					detachSummary(player, at, "SessionLostUnconfirmed")
				end
			elseif
				active[player] == nil
				and (receipt.kind == "LoadRejected" or receipt.kind == "CloseStarted")
			then
				recordUnreadyEnd(player, at, receipt.code or "LoadCancelled")
			end
		end)
	)

	-- Base binding is not gameplay readiness: the existing lifecycle additionally
	-- verifies the current cart and restoration generation. Reassignment is not a departure.
	table.insert(connections, deps().WorldLifecycle:SubscribeReady(markWorldReady))
	if deps().WorldLifecycle.SubscribeDiagnostics then
		table.insert(
			connections,
			deps().WorldLifecycle:SubscribeDiagnostics(function(player, receipt)
				local metrics = metricsFor(player, receipt)
				if metrics then
					metrics:ObserveDiagnostic(copyReceipt(receipt, deps().Now()))
				end
			end)
		)
	end
	-- The profile coordinator has already performed its authorized final settlement
	-- before invoking this existing finalizer seam. We only read, summarize and detach.
	table.insert(
		connections,
		deps().Profile:RegisterCloseFinalizer(function(player)
			detachSummary(player, deps().Now(), "Pending")
		end)
	)

	table.insert(
		connections,
		deps().Currency:SubscribeCommitted(function(player, receipt)
			local metrics = metricsFor(player, receipt)
			if not metrics then
				return
			end
			local observed = copyReceipt(receipt, deps().Now())
			if observed.kind == "WalletCredit" and observed.source == "PlatformIncomeClaim" then
				observed.kind = "PlatformCollection"
			end
			metrics:ObserveEconomic(observed)
			-- The wallet owner may commit ordinary platform earnings and one daily
			-- reward together. Keep production/collection equal to ordinary E;
			-- account only the producer's positive paid grant receipt separately.
			local retention = receipt.retention
			for _, reward in if type(retention) == "table" then retention.transitions or {} else {} do
				if
					type(reward.grantId) == "string"
					and type(reward.amountCash) == "number"
					and reward.amountCash > 0
				then
					local paid = table.clone(observed)
					paid.kind, paid.source, paid.sourceStream =
						"WalletCredit", "RetentionReward", "RetentionReward"
					paid.eventId, paid.amount =
						"retention-grant:" .. reward.grantId, reward.amountCash
					paid.retention, paid.ordinaryCredit = nil, false
					metrics:ObserveEconomic(paid)
				end
			end
			refreshOffers(player, observed.at)
		end)
	)

	table.insert(
		connections,
		deps().Income:SubscribeCommitted(function(player, receipt)
			local metrics = metricsFor(player, receipt)
			if metrics then
				metrics:ObserveEconomic(copyReceipt(receipt, deps().Now()))
			end
		end)
	)

	table.insert(
		connections,
		deps().Upgrade:SubscribeObservations(function(player, receipt)
			if observeDetached(player, receipt, deps().Now()) then
				return
			end
			local entry = currentEntry(player, receipt)
			local metrics = if entry then entry.Metrics else nil
			if not metrics then
				return
			end
			if entry.Closing and receipt.kind ~= "PurchaseSaveConfirmed" then
				return
			end
			local observed = copyReceipt(receipt, deps().Now())
			if
				observed.kind == "ContextIssued"
				or observed.kind == "MenuRendered"
				or observed.kind == "OfferInspected"
			then
				if observed.kind == "ContextIssued" then
					refreshOffers(player, observed.at)
				end
				metrics:ObserveShop(observed)
			elseif observed.kind == "PurchaseAttempt" then
				observed.kind = "Attempt"
				metrics:ObservePurchase(observed)
			elseif observed.kind == "PurchaseCommitted" then
				-- The commit may use a newer target/terms than the last observation.
				-- Its immutable pre-debit facts establish that exact candidate without
				-- re-evaluating the already-deducted wallet as purchase eligibility.
				if metrics.offers[observed.offerKey] == nil then
					metrics:ObserveOfferState({
						at = observed.at,
						offerId = observed.offerId,
						targetKey = observed.targetKey,
						termsVersion = observed.termsVersion,
						price = observed.price or observed.chargedAmount,
						owned = false,
						ownedAtStart = false,
						isBaseline = false,
						ready = observed.ready,
						prerequisitesSatisfied = observed.prerequisitesSatisfied,
						fundsSufficient = observed.fundsSufficient,
					})
				end
				observed.kind = "Result"
				observed.accepted = true
				metrics:ObservePurchase(observed)
				refreshOffers(player, observed.at)
			elseif observed.kind == "PurchaseResult" and observed.accepted ~= true then
				observed.kind = "Result"
				metrics:ObservePurchase(observed)
				refreshOffers(player, observed.at)
			elseif observed.kind == "PurchaseSaveConfirmed" then
				observed.kind = "SaveConfirmed"
				metrics:ObservePurchase(observed)
			end
		end)
	)

	table.insert(
		connections,
		deps().Interaction.SubscribeCommitted(function(player, receipt)
			local entry = currentEntry(player, receipt)
			if entry and not entry.Closing then
				entry.Metrics:ObserveMilestone(copyReceipt(receipt, deps().Now()))
				observeIntroducedAcquisition(player,entry,receipt)
			end
		end)
	)
	table.insert(
		connections,
		deps().Sale.SubscribeCommitted(function(player, receipt)
			local metrics = metricsFor(player, receipt)
			if metrics then
				metrics:ObserveSaleProvenance(copyReceipt(receipt, deps().Now()))
			end
		end)
	)

	if deps().ConnectScheduler ~= false then
		table.insert(
			connections,
			RunService.Heartbeat:Connect(function(deltaTime)
				self:Step(deltaTime)
			end)
		)
	end
	for _, player in deps().Players:GetPlayers() do
		if deps().WorldLifecycle:IsReady(player) then
			markWorldReady(player)
		end
	end
	return true
end

-- Explicit stable transitions are also accepted by deterministic integration fixtures.
function ProgressionMetricsService:ObserveRegion(
	player: Player,
	state: string,
	regionId: string?,
	reason: string?
): boolean
	local entry = currentEntry(player)
	if not entry or entry.Closing then
		return false
	end
	return entry.Metrics:ObserveRegion({
		at = deps().Now(),
		state = state,
		regionId = regionId,
		reason = reason,
		configurationId = entry.Metrics.configurationId,
	})
end

local function sampleRegion(player: Player, entry: any, at: number)
	if entry.Closing or not entry.WorldReady or deps().Regions == false then
		return
	end
	local observed = deps().ReadLocation(player)
	if type(observed) ~= "table" then
		return
	end
	if
		observed.alive == false
		or observed.cartResetting == true
		or (entry.Character ~= nil and observed.character ~= entry.Character)
	then
		entry.Metrics:InterruptOuting(
			if observed.cartResetting then "CartResetTeleport" else "CharacterDeathReset",
			at
		)
		entry.RegionKey, entry.RegionCandidate = nil, nil
	end
	entry.Character = observed.character
	if observed.alive == false or observed.cartResetting == true or observed.position == nil then
		return
	end
	local region = deps().Regions.GetRegionAtPosition(observed.position)
	local key = if region then region.id else "OUTSIDE_REGISTERED_REGIONS"
	if key ~= entry.RegionCandidate then
		entry.RegionCandidate, entry.RegionCandidateAt = key, at
		return
	end
	if at - entry.RegionCandidateAt < REGION_STABLE_SECONDS or key == entry.RegionKey then
		return
	end
	local previous = entry.RegionKey
	entry.RegionKey = key
	if key == Regions.CampId then
		ProgressionMetricsService:ObserveRegion(player, "AtCamp", key)
	elseif region then
		if previous == Regions.CampId then
			ProgressionMetricsService:ObserveRegion(player, "OutsideCamp", key)
		end
		ProgressionMetricsService:ObserveRegion(player, "InHuntingRegion", key)
	elseif previous ~= nil then
		ProgressionMetricsService:ObserveRegion(
			player,
			"OutsideCamp",
			nil,
			"OutsideRegisteredRegions"
		)
	else
		entry.Metrics.coverage.initialRegion = "UNRESOLVED"
	end
end

function ProgressionMetricsService:Step(deltaTime: number?)
	if not started then
		return
	end
	local elapsed = deltaTime or REGION_SAMPLE_SECONDS
	if type(elapsed) ~= "number" or elapsed < 0 or elapsed ~= elapsed then
		return
	end
	reportAccumulator += elapsed
	sampleAccumulator += elapsed
	local sample = sampleAccumulator >= REGION_SAMPLE_SECONDS
	local reportDue = reportAccumulator >= REPORT_INTERVAL_SECONDS
	if sample then
		sampleAccumulator %= REGION_SAMPLE_SECONDS
	end
	if reportDue then
		reportAccumulator %= REPORT_INTERVAL_SECONDS
	end
	local at = deps().Now()
	for player, entry in active do
		if currentEntry(player) ~= entry then
			entry.Metrics.coverage.endingAuthorityUnavailable = true
			entry.Metrics.observationCompleteness = "PARTIAL_OBSERVATION"
			entry.Metrics:BeginDeparture(at)
			appendCompleted(entry.Metrics:BuildReport(at))
			clearEntry(player, entry)
		elseif entry.CloseDeadline and at >= entry.CloseDeadline then
			detachSummary(player, at, "CloseDeadlineUnconfirmed")
		elseif sample then
			sampleRegion(player, entry, at)
		end
		if reportDue and active[player] == entry then
			endingSnapshot(player, entry, at, false)
			logSummary(player, entry.Metrics:BuildReport(at), false)
		end
	end
	for key, pending in detached do
		if at >= pending.Deadline then
			pending.Report.persistence.closeStatus = "UnconfirmedCloseDeadline"
			pending.Report.session.clocks.reportClosedAt = at
			appendCompleted(pending.Report)
			detached[key] = nil
			local index = table.find(detachedOrder, key)
			if index then
				table.remove(detachedOrder, index)
			end
		end
	end
end

function ProgressionMetricsService:RefreshOffers(player: Player)
	refreshOffers(player, deps().Now())
end

function ProgressionMetricsService:ObserveWorldProgression(player: Player,name: string,fields: any): boolean
	local entry=currentEntry(player)
	if not entry or entry.Closing then return false end
	local observed=copyReceipt(fields,deps().Now())
	observed.kind=name
	observed.eventId=fields.transactionId or fields.eventId
	if name=="BankingProofAdded" then
		observed.eventId="bank-proof:"..tostring(fields.speciesId)
		local introduced=entry.Metrics.phase8IntroducedIndividuals[fields.individualId]
		if introduced then
			entry.Metrics:ObserveWorldProgression({kind="FirstIntroducedRegionBank",at=observed.at,
				key=introduced.key,speciesId=fields.speciesId,eventId="introduced-bank:"..tostring(fields.individualId)})
		end
	end
	return entry.Metrics:ObserveWorldProgression(observed)
end

function ProgressionMetricsService:GetReport(player: Player): any?
	local entry = currentEntry(player)
	if not entry then
		return nil
	end
	local at = deps().Now()
	endingSnapshot(player, entry, at, false)
	return entry.Metrics:BuildReport(at)
end

function ProgressionMetricsService:GetCompletedReports(): { any }
	return table.clone(completedReports)
end

function ProgressionMetricsService:GetDiagnostics(): any
	local counts = { active = 0, joining = 0, detached = 0, completed = #completedReports }
	for _ in active do
		counts.active += 1
	end
	for _ in joinedAt do
		counts.joining += 1
	end
	for _ in detached do
		counts.detached += 1
	end
	return counts
end

function ProgressionMetricsService:Stop()
	for _, connection in connections do
		disconnect(connection)
	end
	table.clear(connections)
	for player, entry in active do
		clearEntry(player, entry)
	end
	table.clear(active)
	table.clear(joinedAt)
	table.clear(loadDetails)
	table.clear(completedReports)
	reportAccumulator = 0
	sampleAccumulator = 0
	table.clear(detached)
	table.clear(detachedOrder)
	started = false
	dependencies = nil
end

return ProgressionMetricsService
