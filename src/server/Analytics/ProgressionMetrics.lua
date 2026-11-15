--!strict

-- Phase 7G-1's bounded, in-memory observation record. This module has no
-- gameplay dependencies: callers pass immutable receipts only after the owning
-- domain has committed. It never settles income, edits a profile, or retries an
-- operation.

local RECENT_DETAIL_LIMIT = 128
local RECENT_OUTING_LIMIT = 10
local RECENT_COMPARABLE_LIMIT = 3
local EPSILON = 1e-6

local ProgressionMetrics = {}
ProgressionMetrics.__index = ProgressionMetrics

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function finiteNonNegative(value: any): boolean
	return finite(value) and value >= 0
end

local function copyMap(source: any): any
	local result = {}
	if type(source) == "table" then
		for key, value in source do
			result[key] = value
		end
	end
	return result
end

local function copyArray(source: any): { any }
	return if type(source) == "table" then table.clone(source) else {}
end

local function offerKey(offerId: string, targetKey: string, termsVersion: string): string
	return offerId .. "|" .. targetKey .. "|" .. termsVersion
end

local function relative(worldReadyAt: number?, at: number?): number?
	if not finite(worldReadyAt) or not finite(at) then
		return nil
	end
	return (at :: number) - (worldReadyAt :: number)
end

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local middle = math.floor((#sorted + 1) / 2)
	if #sorted % 2 == 1 then
		return sorted[middle]
	end
	return (sorted[middle] + sorted[middle + 1]) / 2
end

local function closeAffordableWindow(state: any, at: number)
	if state.affordableWindowStartedAt == nil then
		return
	end
	state.cumulativeEligibleAffordableDuration += math.max(0, at - state.affordableWindowStartedAt)
	state.affordableWindowStartedAt = nil
end

local function detailsCopy(details: { any }): { any }
	local result = {}
	for index, detail in details do
		result[index] = copyMap(detail)
		for key, value in detail do
			if type(value) == "table" then
				result[index][key] = copyMap(value)
			end
		end
	end
	return result
end

function ProgressionMetrics.new(options: any): any
	assert(type(options) == "table", "ProgressionMetrics options required")
	assert(finite(options.joinAt), "joinAt must be finite")
	local starting = options.startingState or {}
	local startingProgression = {}
	local progressionCount, progressionDrops = 0, 0
	for key, value in starting.ownedProgression or {} do
		if progressionCount < RECENT_DETAIL_LIMIT then
			startingProgression[key] = value
			progressionCount += 1
		else
			progressionDrops += 1
		end
	end
	assert(finiteNonNegative(starting.wallet or 0), "starting wallet must be finite")
	assert(
		finiteNonNegative(starting.settledPlatformCash or 0),
		"starting platform cash must be finite"
	)
	local self = setmetatable({
		measurementVersion = "7G1-v2",
		observationId = tostring(options.observationId or "unknown"),
		buildId = tostring(options.buildId or "unknown"),
		configurationId = tostring(options.configurationId or "unknown"),
		environment = tostring(options.environment or "unknown"),
		profileOrigin = tostring(options.profileOrigin or "UnknownOrigin"),
		-- Trend audio A/B test: "Trend" / "Current" (AudioVariantService); a label only.
		audioVariant = tostring(options.audioVariant or "Unknown"),
		inputCategory = "Unknown",
		observationCompleteness = if options.partialObservation == true
			then "PARTIAL_OBSERVATION"
			else "COMPLETE_FROM_JOIN",
		coverage = copyMap(options.coverage),
		clocks = {
			joinAt = options.joinAt,
			profileReadyAt = options.profileReadyAt,
			worldReadyAt = options.worldReadyAt,
			measurementStartedAt = options.measurementStartedAt,
			departureCutoffAt = nil,
			reportClosedAt = nil,
		},
		startingState = {
			wallet = starting.wallet or 0,
			settledPlatformCash = starting.settledPlatformCash or 0,
			occupiedSlotCount = starting.occupiedSlotCount or 0,
			bankedIndividualCount = starting.bankedIndividualCount or 0,
			passiveIncomeRate = starting.passiveIncomeRate or 0,
			ownedProgression = startingProgression,
			selectedCartId = starting.selectedCartId,
			selectedWeaponId = starting.selectedWeaponId,
		},
		startingOwnedIndividuals = {},
		currentSessionAcquired = {},
		phase8IntroducedIndividuals = {},
		currentWallet = starting.wallet or 0,
		currentPlatformCash = starting.settledPlatformCash or 0,
		collectiblePlatformCash = nil,
		economy = {
			platformIncomeGenerated = 0,
			platformIncomeFromStartingAssets = 0,
			platformIncomeFromCurrentSessionAssets = 0,
			platformIncomeUnresolvedSource = 0,
			platformCashCollected = 0,
			salesCurrentSessionAssets = 0,
			salesStartingAssets = 0,
			salesUnknownProvenance = 0,
			otherWalletCredits = 0,
			walletDebits = 0,
			walletAdjustments = 0,
			platformAdjustments = 0,
			ordinaryOtherWalletCredits = 0,
			prePlayablePlatformProduction = 0,
			prePlayableWalletCredits = 0,
			prePlayableWalletDebits = 0,
			prePlayableNonTransferCredits = 0,
		},
		saleCreditsByRevision = {},
		offers = {},
		offerOrder = {},
		contexts = {},
		purchasesByRequest = {},
		milestones = {},
		worldProgression = {cohort=if options.profileOrigin=="ConfirmedNew" then "FreshSolo" else "Returning",
			gates={}, events={}, counts={}, eventDrops=0, firstBankAt=nil,
			previousUnlockAt=options.profileReadyAt, durationBasis="IN_SESSION_SINCE_UNLOCK_OR_PROFILE_READY"},
		counts = {
			acquisitionOperations = 0,
			cargoPlacements = 0,
			bankedPlacements = 0,
			platformCollections = 0,
			sales = 0,
		},
		uniqueAcquiredIndividuals = {},
		uniqueAcquiredSpecies = {},
		persistence = {
			logicalSaveOperations = 0,
			transportRetries = 0,
			confirmedRevisions = {},
			lastConfirmedRevision = nil,
			pendingPurchaseCount = 0,
			loadFailure = nil,
			restorationBlocker = nil,
			closeStatus = "Open",
		},
		outings = {},
		outingTotals = { completed = 0, interrupted = 0, nonHunting = 0 },
		outingDetailDrops = 0,
		bankToBankCount = 0,
		bankToBankDurationTotal = 0,
		lastOutingBank = nil,
		campServiceOuting = nil,
		activeOuting = nil,
		recentComparableCurrency = {},
		recentDetails = {},
		detailDrops = 0,
		dedup = {},
		dedupOrder = {},
		dedupEvictions = 0,
		sequenceWatermarks = {},
		mapOrders = {},
		mapEvictions = {},
		earlyPurchaseConfirmations = {},
	}, ProgressionMetrics)
	if progressionDrops > 0 then
		self.coverage.startingProgressionDetailDrops = progressionDrops
	end
	for individualId, value in options.startingOwnedIndividuals or {} do
		self:_boundedSet("startingOwnedIndividuals", individualId, value)
	end
	return self
end

-- Phase 8 uses the existing bounded observation owner; no profile, money,
-- population or gameplay mutation is performed by this receipt path.
function ProgressionMetrics:ObserveWorldProgression(event: any): boolean
	local allowed={ProgressionProfileReady=true,BankingProofAdded=true,BankingRequirementEligible=true,
		CashRequirementEligible=true,GatePanelOpened=true,GatePurchaseSubmitted=true,
		GatePurchaseCommitted=true,GatePurchasePending=true,GatePurchaseConfirmed=true,
		GatePurchaseRejected=true,
		UnauthorizedRegionEntry=true,UnauthorizedWildAction=true,CurrencyMigrationStarted=true,
		CurrencyMigrationConfirmed=true,CurrencyMigrationFailed=true,LegacyGrantCompleted=true,
		FirstIntroducedRegionCatch=true,FirstIntroducedRegionBank=true,
		StormPushed=true} -- TerrainRedesign Storm response {regionKey, fallbackUsed}
	if type(event)~="table" or not allowed[event.kind] or not finite(event.at)
		or self.clocks.departureCutoffAt~=nil then return false end
	if not self:_remember("WorldProgression:"..event.kind,event.eventId,event) then return false end
	local world=self.worldProgression
	local receipt={kind=event.kind,at=event.at}
	for _,key in {"key","regionId","speciesId","individualId","rarity","code","transactionId",
		"price","wallet","revision","currencyVersion","currencyFrom","currencyTo",
		"monetaryFieldCount","bankedSpeciesCount","legacyGrantVersion","legacyRegions","fixture",
		"regionKey","fallbackUsed"} do
		local value=event[key]
		if (type(value)=="number" and finite(value)) or (type(value)=="string" and #value<=128)
			or type(value)=="boolean" then receipt[key]=value end
	end
	world.counts[event.kind]=(world.counts[event.kind] or 0)+1
	table.insert(world.events,receipt)
	if #world.events>RECENT_DETAIL_LIMIT then table.remove(world.events,1) world.eventDrops+=1 end
	if event.kind=="ProgressionProfileReady" and type(receipt.legacyRegions)=="string" and receipt.legacyRegions~="" then
		world.cohort="LegacyGranted"
	elseif event.kind=="BankingProofAdded" then world.firstBankAt=world.firstBankAt or event.at end
	if event.kind=="ProgressionProfileReady" and receipt.fixture==true then world.seededFixture=true end
	local key=receipt.key or receipt.regionId
	if type(key)=="string" and #key<=32 then
		local gate=world.gates[key]
		if not gate then
			local count=0 for _ in world.gates do count+=1 end
			if count>=16 then return true end
			gate={} world.gates[key]=gate
		end
		local fields={BankingRequirementEligible="bankingEligibleAt",CashRequirementEligible="cashEligibleAt",
			GatePanelOpened="firstPanelAt",GatePurchaseSubmitted="firstSubmissionAt",
			GatePurchaseConfirmed="confirmedUnlockAt",FirstIntroducedRegionCatch="introducedCatchAt",
			FirstIntroducedRegionBank="introducedBankAt"}
		local field=fields[event.kind]
		if field and gate[field]==nil then
			gate[field]=event.at
			if event.kind=="GatePurchaseConfirmed" then
				gate.sincePreviousUnlockSeconds=if finite(world.previousUnlockAt)
					then math.max(0,event.at-world.previousUnlockAt) else nil
				gate.cohort=world.cohort world.previousUnlockAt=event.at
			end
		end
	end
	if event.kind=="GatePurchaseCommitted" and finiteNonNegative(event.price)
		and type(event.transactionId)=="string" then
		self:ObserveEconomic({kind="WalletDebit",at=event.at,eventId="region:"..event.transactionId,
			amount=event.price,balanceAfter=event.wallet,revision=event.revision,source="WorldUnlock"})
	end
	return true
end

function ProgressionMetrics:_boundedSet(name: string, key: any, value: any)
	local map = self[name]
	local order = self.mapOrders[name]
	if not order then
		order = {}
		self.mapOrders[name] = order
	end
	if map[key] == nil then
		local previousIndex = table.find(order, key)
		if previousIndex then
			table.remove(order, previousIndex)
		end
		table.insert(order, key)
		if #order > RECENT_DETAIL_LIMIT then
			local old = table.remove(order, 1)
			if map[old] ~= nil then
				map[old] = nil
				self.mapEvictions[name] = (self.mapEvictions[name] or 0) + 1
			end
		end
	end
	map[key] = value
end

function ProgressionMetrics:_remember(kind: string, eventId: any, event: any?): boolean
	local sequence = if event then event.operationSequence else nil
	if finiteNonNegative(sequence) and sequence % 1 == 0 then
		local stream = kind .. "|" .. tostring(event.sourceStream or event.stream or kind)
		local prior = self.sequenceWatermarks[stream]
		if prior ~= nil and sequence <= prior then
			return false
		end
		self:_boundedSet("sequenceWatermarks", stream, sequence)
	elseif self.dedupEvictions > 0 and (kind:match("^Economic:") or kind == "PurchaseResult") then
		self.coverage.unsequencedReplayWindowExceeded = true
	end
	if eventId == nil then
		return true
	end
	local key = kind .. "|" .. tostring(eventId)
	if self.dedup[key] then
		return false
	end
	self.dedup[key] = true
	table.insert(self.dedupOrder, key)
	if #self.dedupOrder > RECENT_DETAIL_LIMIT then
		local evicted = table.remove(self.dedupOrder, 1)
		self.dedup[evicted] = nil
		self.dedupEvictions += 1
	end
	return true
end

function ProgressionMetrics:_detail(kind: string, at: number, fields: any?)
	local detail = { kind = kind, at = at }
	for key, value in fields or {} do
		detail[key] = value
	end
	table.insert(self.recentDetails, detail)
	if #self.recentDetails > RECENT_DETAIL_LIMIT then
		table.remove(self.recentDetails, 1)
		self.detailDrops += 1
	end
end

function ProgressionMetrics:SetProfileReady(at: number, profileOrigin: string)
	if not finite(at) then
		return false
	end
	self.clocks.profileReadyAt = self.clocks.profileReadyAt or at
	self.profileOrigin = profileOrigin
	self:_detail("ProfileReady", at, { profileOrigin = profileOrigin })
	return true
end

function ProgressionMetrics:SetWorldReady(at: number)
	if not finite(at) then
		return false
	end
	if self.clocks.worldReadyAt == nil then
		self.clocks.worldReadyAt = at
		self.clocks.measurementStartedAt = self.clocks.measurementStartedAt or at
		self:_detail("WorldReady", at)
	end
	return true
end

function ProgressionMetrics:ObserveDiagnostic(event: any): boolean
	if type(event) ~= "table" or type(event.kind) ~= "string" or not finite(event.at) then
		return false
	end
	if not self:_remember("Diagnostic:" .. event.kind, event.eventId, event) then
		return false
	end
	if event.kind == "SaveStarted" then
		self.persistence.logicalSaveOperations += 1
	elseif event.kind == "SaveRetry" then
		self.persistence.transportRetries += 1
	elseif event.kind == "SaveConfirmed" and finiteNonNegative(event.revision) then
		self.persistence.lastConfirmedRevision =
			math.max(self.persistence.lastConfirmedRevision or 0, event.revision)
	elseif event.kind == "LoadRejected" then
		self.persistence.loadFailure = event.code or "UNKNOWN"
	elseif event.kind == "WorldRestoreBlocked" then
		self.persistence.restorationBlocker = event.code or "UNKNOWN"
	elseif event.kind == "SessionLost" then
		self.persistence.closeStatus = "SessionLost"
	elseif event.kind == "CloseCompleted" then
		self.persistence.closeStatus = "Confirmed"
	elseif event.kind == "CloseUnconfirmed" then
		self.persistence.closeStatus = "Unconfirmed"
	end
	self:_detail(event.kind, event.at, {
		code = event.code,
		revision = event.revision,
		attempt = event.attempt,
	})
	return true
end

function ProgressionMetrics:ObserveEconomic(event: any): boolean
	if
		type(event) ~= "table"
		or type(event.kind) ~= "string"
		or not finite(event.at)
		or not finiteNonNegative(event.amount)
	then
		return false
	end
	if not self:_remember("Economic:" .. event.kind, event.eventId, event) then
		return false
	end
	local amount = event.amount
	local prePlayable = self.clocks.worldReadyAt == nil or event.at < self.clocks.worldReadyAt
	if event.kind == "PlatformIncomeProduced" then
		if prePlayable then
			self.economy.prePlayablePlatformProduction += amount
		end
		self.economy.platformIncomeGenerated += amount
		self.currentPlatformCash += amount
		local classified = 0
		for individualId, generated in event.byIndividual or {} do
			if finiteNonNegative(generated) then
				classified += generated
				if self.startingOwnedIndividuals[individualId] then
					self.economy.platformIncomeFromStartingAssets += generated
				elseif self.currentSessionAcquired[individualId] then
					self.economy.platformIncomeFromCurrentSessionAssets += generated
				else
					self.economy.platformIncomeUnresolvedSource += generated
				end
			end
		end
		if classified < amount then
			self.economy.platformIncomeUnresolvedSource += amount - classified
		elseif classified > amount + EPSILON then
			self.coverage.incomeProvenanceMismatch = true
		end
	elseif event.kind == "PlatformCollection" then
		if prePlayable then
			self.economy.prePlayableWalletCredits += amount
		end
		self.economy.platformCashCollected += amount
		self.currentPlatformCash = math.max(0, self.currentPlatformCash - amount)
		self.currentWallet = if finiteNonNegative(event.balanceAfter)
			then event.balanceAfter
			else self.currentWallet + amount
		self.counts.platformCollections += 1
		self.milestones.firstPlatformCollectionAt = self.milestones.firstPlatformCollectionAt
			or event.at
	elseif event.kind == "WalletCredit" then
		if prePlayable then
			self.economy.prePlayableWalletCredits += amount
			self.economy.prePlayableNonTransferCredits += amount
		end
		local source = tostring(event.source or "Unknown")
		self.currentWallet = if finiteNonNegative(event.balanceAfter)
			then event.balanceAfter
			else self.currentWallet + amount
		if source == "BrainrotSale" then
			if self.campServiceOuting then
				self.campServiceOuting.firstSaleAfterReturnAt = self.campServiceOuting.firstSaleAfterReturnAt
					or event.at
			end
			self.economy.salesUnknownProvenance += amount
			if finiteNonNegative(event.revision) then
				self:_boundedSet("saleCreditsByRevision", event.revision, amount)
			end
			self.counts.sales += 1
			self.milestones.firstSaleAt = self.milestones.firstSaleAt or event.at
		else
			self.economy.otherWalletCredits += amount
			if event.ordinaryCredit == true then
				self.economy.ordinaryOtherWalletCredits += amount
			end
		end
	elseif event.kind == "WalletDebit" then
		if prePlayable then
			self.economy.prePlayableWalletDebits += amount
		end
		self.economy.walletDebits += amount
		self.currentWallet = if finiteNonNegative(event.balanceAfter)
			then event.balanceAfter
			else math.max(0, self.currentWallet - amount)
	elseif event.kind == "WalletAdjustment" then
		self.economy.walletAdjustments += event.signedAmount or amount
		self.currentWallet = if finiteNonNegative(event.balanceAfter)
			then event.balanceAfter
			else self.currentWallet + (event.signedAmount or amount)
	elseif event.kind == "PlatformAdjustment" then
		self.economy.platformAdjustments += event.signedAmount or amount
		self.currentPlatformCash += event.signedAmount or amount
	else
		return false
	end
	self:_detail(event.kind, event.at, {
		amount = amount,
		source = event.source,
		revision = event.revision,
	})
	return true
end

function ProgressionMetrics:ObserveSaleProvenance(event: any): boolean
	if
		type(event) ~= "table"
		or not finite(event.at)
		or type(event.individualId) ~= "string"
		or not finiteNonNegative(event.revision)
	then
		return false
	end
	local amount = self.saleCreditsByRevision[event.revision]
	if not finiteNonNegative(amount) then
		return false
	end
	if not self:_remember("SaleProvenance", event.eventId or event.revision, event) then
		return false
	end
	self.economy.salesUnknownProvenance = math.max(0, self.economy.salesUnknownProvenance - amount)
	if self.startingOwnedIndividuals[event.individualId] then
		self.economy.salesStartingAssets += amount
	elseif self.currentSessionAcquired[event.individualId] then
		self.economy.salesCurrentSessionAssets += amount
	else
		self.economy.salesUnknownProvenance += amount
	end
	self.saleCreditsByRevision[event.revision] = nil
	self:_detail("SaleProvenance", event.at, {
		individualId = event.individualId,
		revision = event.revision,
	})
	return true
end

function ProgressionMetrics:ObserveMilestone(event: any): boolean
	if type(event) ~= "table" or type(event.kind) ~= "string" or not finite(event.at) then
		return false
	end
	if self.clocks.departureCutoffAt ~= nil then
		return false
	end
	if not self:_remember("Milestone:" .. event.kind, event.eventId, event) then
		return false
	end
	if event.kind == "ValidSleepHit" then
		self.milestones.firstValidSleepHitAt = self.milestones.firstValidSleepHitAt or event.at
		if self.activeOuting then
			self.activeOuting.firstSleepAt = self.activeOuting.firstSleepAt or event.at
		end
	elseif event.kind == "WildAcquired" then
		self.counts.acquisitionOperations += 1
		self.milestones.firstWildAcquisitionAt = self.milestones.firstWildAcquisitionAt or event.at
		if self.activeOuting then
			self.activeOuting.firstAcquisitionAt = self.activeOuting.firstAcquisitionAt or event.at
		end
		if type(event.individualId) == "string" then
			self:_boundedSet("uniqueAcquiredIndividuals", event.individualId, true)
			self:_boundedSet("currentSessionAcquired", event.individualId, true)
		end
		if type(event.speciesId) == "string" then
			self:_boundedSet("uniqueAcquiredSpecies", event.speciesId, true)
		end
	elseif event.kind == "CargoPlaced" then
		self.counts.cargoPlacements += 1
		self.milestones.firstCargoPlacementAt = self.milestones.firstCargoPlacementAt or event.at
	elseif event.kind == "BankedPlaced" then
		self.counts.bankedPlacements += 1
		self.milestones.firstBankedPlacementAt = self.milestones.firstBankedPlacementAt or event.at
		local outing = self.campServiceOuting
		if outing and not outing.firstBankAfterReturnAt then
			outing.firstBankAfterReturnAt = event.at
			local previous = self.lastOutingBank
			if
				previous
				and previous.configurationId == outing.configurationId
				and event.at >= previous.at
			then
				outing.bankToBankDuration = event.at - previous.at
				self.bankToBankCount += 1
				self.bankToBankDurationTotal += outing.bankToBankDuration
			end
			self.lastOutingBank = { at = event.at, configurationId = outing.configurationId }
		end
	else
		return false
	end
	self:_detail(event.kind, event.at, {
		individualId = event.individualId,
		speciesId = event.speciesId,
	})
	return true
end

function ProgressionMetrics:ObserveOfferState(event: any): boolean
	if
		type(event) ~= "table"
		or type(event.offerId) ~= "string"
		or not finiteNonNegative(event.price)
		or not finite(event.at)
	then
		return false
	end
	if self.clocks.departureCutoffAt ~= nil then
		return false
	end
	local targetKey = tostring(event.targetKey or "none")
	local termsVersion = tostring(event.termsVersion or "unknown")
	local key = offerKey(event.offerId, targetKey, termsVersion)
	local state = self.offers[key]
	if state == nil then
		for _, previous in self.offers do
			if previous.offerId == event.offerId and previous.targetKey == targetKey then
				previous.active = false
				previous.currentAffordable = false
				previous.supersededAt = event.at
				closeAffordableWindow(previous, event.at)
			end
		end
		local isBaseline = event.isBaseline == true
			or (
				event.isBaseline == nil
				and event.at == (self.clocks.worldReadyAt or self.clocks.measurementStartedAt)
			)
		local baselineWallet = if finiteNonNegative(event.baselineWallet)
			then event.baselineWallet
			else self.startingState.wallet
		state = {
			key = key,
			offerId = event.offerId,
			targetKey = targetKey,
			termsVersion = termsVersion,
			price = event.price,
			ownedAtStart = isBaseline and event.ownedAtStart == true,
			fundsSufficientAtStart = isBaseline and baselineWallet >= event.price,
			prerequisitesSatisfiedAtStart = isBaseline and event.prerequisitesSatisfied == true,
			readyAtStart = isBaseline and event.ready == true,
			baselineObserved = isBaseline,
			observationStartedAt = event.at,
			active = true,
			displayOrder = event.displayOrder or 0,
			firstFundsSufficientAt = nil,
			firstPrerequisiteSatisfiedAt = nil,
			firstEligibleAffordableAt = nil,
			currentAffordable = false,
			affordableWindowEntries = 0,
			cumulativeEligibleAffordableDuration = 0,
			affordableWindowStartedAt = nil,
			firstContextIssuedAt = nil,
			firstMenuRenderedAt = nil,
			firstOfferInspectedAt = nil,
			attempts = 0,
			rejections = {},
			purchaseCommittedAt = nil,
			purchaseRequestId = nil,
			persistence = "NotPurchased",
			ready = false,
			prerequisitesSatisfied = false,
			owned = false,
			pathBlocked = false,
			primaryReason = nil,
		}
		self:_boundedSet("offers", key, state)
		table.insert(self.offerOrder, key)
		for index = #self.offerOrder, 1, -1 do
			if self.offers[self.offerOrder[index]] == nil then
				table.remove(self.offerOrder, index)
			end
		end
	end
	if state.price ~= event.price then
		return false
	end
	if
		(state.lastObservedAt and event.at < state.lastObservedAt)
		or (state.supersededAt and event.at < state.supersededAt)
	then
		return false
	end
	for previousKey, previous in self.offers do
		if
			previousKey ~= key
			and previous.offerId == event.offerId
			and previous.targetKey == targetKey
			and previous.active
		then
			previous.active = false
			previous.currentAffordable = false
			previous.supersededAt = event.at
			closeAffordableWindow(previous, event.at)
		end
	end
	state.lastObservedAt = event.at
	state.active = true
	state.ready = event.ready == true
	state.prerequisitesSatisfied = event.prerequisitesSatisfied == true
	state.owned = event.owned == true
	state.pathBlocked = event.pathBlocked == true
	state.primaryReason = event.primaryReason
	local funds = event.fundsSufficient == true
	if funds and state.firstFundsSufficientAt == nil then
		state.firstFundsSufficientAt = event.at
	end
	if state.prerequisitesSatisfied and state.firstPrerequisiteSatisfiedAt == nil then
		state.firstPrerequisiteSatisfiedAt = event.at
	end
	local available = state.ready and state.prerequisitesSatisfied and funds and not state.owned
	if available and not state.currentAffordable then
		state.currentAffordable = true
		state.affordableWindowEntries += 1
		state.affordableWindowStartedAt = event.at
		state.firstEligibleAffordableAt = state.firstEligibleAffordableAt or event.at
	elseif not available and state.currentAffordable then
		state.currentAffordable = false
		closeAffordableWindow(state, event.at)
	end
	return true
end

function ProgressionMetrics:ReconcileOfferCandidates(keys: { string }, at: number)
	if not finite(at) then
		return false
	end
	local present = {}
	for _, key in keys do
		present[key] = true
	end
	for key, state in self.offers do
		if not present[key] then
			state.active = false
			state.currentAffordable = false
			closeAffordableWindow(state, at)
		end
	end
	return true
end

function ProgressionMetrics:ObserveShop(event: any): boolean
	if type(event) ~= "table" or type(event.kind) ~= "string" or not finite(event.at) then
		return false
	end
	if self.clocks.departureCutoffAt ~= nil then
		return false
	end
	if not self:_remember("Shop:" .. event.kind, event.eventId, event) then
		return false
	end
	if event.kind == "ContextIssued" then
		if type(event.contextId) ~= "string" then
			return false
		end
		self:_boundedSet("contexts", event.contextId, {
			issuedAt = event.at,
			offerKeys = copyArray(event.offerKeys),
			menuRenderedAt = nil,
		})
		for _, key in event.offerKeys or {} do
			local state = self.offers[key]
			if state then
				state.firstContextIssuedAt = state.firstContextIssuedAt or event.at
			end
		end
	elseif event.kind == "MenuRendered" then
		local context = self.contexts[event.contextId]
		if context == nil then
			return false
		end
		context.menuRenderedAt = context.menuRenderedAt or event.at
		self.inputCategory = tostring(event.inputCategory or self.inputCategory)
		for _, key in context.offerKeys do
			local state = self.offers[key]
			if state then
				state.firstMenuRenderedAt = state.firstMenuRenderedAt or event.at
			end
		end
	elseif event.kind == "OfferInspected" then
		local context = self.contexts[event.contextId]
		if context == nil or type(event.offerKey) ~= "string" then
			return false
		end
		local included = false
		for _, key in context.offerKeys do
			included = included or key == event.offerKey
		end
		if not included then
			return false
		end
		local state = self.offers[event.offerKey]
		if state then
			state.firstOfferInspectedAt = state.firstOfferInspectedAt or event.at
		end
	else
		return false
	end
	self:_detail("Shop" .. event.kind, event.at, {
		contextId = event.contextId,
		offerId = event.offerId,
	})
	return true
end

function ProgressionMetrics:ObservePurchase(event: any): boolean
	if
		type(event) ~= "table"
		or type(event.kind) ~= "string"
		or type(event.requestId) ~= "string"
		or type(event.offerKey) ~= "string"
		or not finite(event.at)
	then
		return false
	end
	local state = self.offers[event.offerKey]
	if state == nil then
		return false
	end
	if event.kind == "Attempt" then
		if self.clocks.departureCutoffAt ~= nil then
			return false
		end
		if not self:_remember("PurchaseAttempt", event.requestId, event) then
			return false
		end
		state.attempts += 1
		self:_boundedSet("purchasesByRequest", event.requestId, event.offerKey)
	elseif event.kind == "Result" then
		if
			event.accepted == true
			and (
				not finiteNonNegative(event.chargedAmount)
				or state.purchaseRequestId == event.requestId
			)
		then
			return false
		end
		if not self:_remember("PurchaseResult", event.requestId, event) then
			return false
		end
		if event.accepted == true then
			local charged = event.chargedAmount
			if not finiteNonNegative(charged) then
				return false
			end
			state.purchaseCommittedAt = event.at
			state.purchaseRequestId = event.requestId
			state.purchaseCommitRevision = event.commitRevision
			state.owned = true
			local early = self.earlyPurchaseConfirmations[event.requestId]
			local confirmed = (early ~= nil and early.offerKey == event.offerKey)
				or event.persistence == "Confirmed"
			state.persistence = if confirmed
				then "Confirmed"
				else tostring(event.persistence or "Pending")
			state.purchaseSavedAt = if early and early.offerKey == event.offerKey
				then early.at
				else nil
			state.purchasePending = not confirmed
			local before = event.balanceBefore
			if finiteNonNegative(before) and before >= state.price then
				state.firstFundsSufficientAt = state.firstFundsSufficientAt or event.at
				if event.prerequisitesSatisfied == true or event.prerequisitesBefore == true then
					state.firstPrerequisiteSatisfiedAt = state.firstPrerequisiteSatisfiedAt
						or event.at
					if event.ready == true or event.readyBefore == true then
						state.firstEligibleAffordableAt = state.firstEligibleAffordableAt
							or event.at
					end
				end
			end
			if state.currentAffordable then
				state.currentAffordable = false
				closeAffordableWindow(state, event.at)
			end
			-- UpgradeService owns this coherent debit-and-grant mutation and does
			-- not route it through CurrencySystem's committed observer.
			self:ObserveEconomic({
				kind = "WalletDebit",
				eventId = "purchase:" .. event.requestId,
				at = event.at,
				amount = charged,
				balanceAfter = event.balanceAfter,
				source = "UpgradePurchase",
				operationSequence = event.operationSequence,
				sourceStream = event.sourceStream or event.stream or "UpgradePurchase",
			})
			if not confirmed then
				self.persistence.pendingPurchaseCount += 1
			end
		else
			local code = tostring(event.code or "UNKNOWN")
			state.rejections[code] = (state.rejections[code] or 0) + 1
		end
	elseif event.kind == "SaveConfirmed" then
		if not self:_remember("PurchaseSaveConfirmed", event.requestId, event) then
			return false
		end
		if state.purchaseRequestId == event.requestId then
			state.persistence = "Confirmed"
			state.purchaseSavedAt = state.purchaseSavedAt or event.at
			if state.purchasePending then
				self.persistence.pendingPurchaseCount =
					math.max(0, self.persistence.pendingPurchaseCount - 1)
				state.purchasePending = false
			end
		else
			self:_boundedSet(
				"earlyPurchaseConfirmations",
				event.requestId,
				{ offerKey = event.offerKey, at = event.at }
			)
		end
	else
		return false
	end
	self:_detail("Purchase" .. event.kind, event.at, {
		offerId = state.offerId,
		requestId = event.requestId,
		code = event.code,
	})
	return true
end

local function newOuting(metrics: any, event: any, partial: boolean): any
	local economy = metrics.economy
	return {
		departureAt = event.at,
		firstHuntingRegionAt = if partial then event.at else nil,
		regionsVisited = {},
		partial = partial,
		configurationId = event.configurationId or metrics.configurationId,
		startingWalletReceipts = economy.platformCashCollected
			+ economy.salesCurrentSessionAssets
			+ economy.salesStartingAssets
			+ economy.salesUnknownProvenance
			+ economy.otherWalletCredits,
		startingNonTransferCredits = economy.salesCurrentSessionAssets
			+ economy.salesStartingAssets
			+ economy.salesUnknownProvenance
			+ economy.otherWalletCredits,
		startingProduction = economy.platformIncomeGenerated,
		startingPlatformCash = metrics.currentPlatformCash,
		startingCurrentSales = economy.salesCurrentSessionAssets,
		startingAssetSales = economy.salesStartingAssets,
		startingUnknownSales = economy.salesUnknownProvenance,
		startingOrdinaryCredits = economy.ordinaryOtherWalletCredits,
		startingDebits = economy.walletDebits,
		startingAcquisitionOperations = metrics.counts.acquisitionOperations,
	}
end

function ProgressionMetrics:ObserveRegion(event: any): boolean
	if type(event) ~= "table" or type(event.state) ~= "string" or not finite(event.at) then
		return false
	end
	if self.clocks.departureCutoffAt ~= nil then
		return false
	end
	if event.state == "OutsideCamp" then
		if self.activeOuting == nil then
			self:_finishCampService(
				event.at,
				"NextDeparture",
				event.configurationId or self.configurationId
			)
			self.activeOuting = newOuting(self, event, false)
		end
	elseif event.state == "InHuntingRegion" then
		if self.activeOuting == nil then
			self:_finishCampService(
				event.at,
				"RegionLocationUnresolved",
				event.configurationId or self.configurationId
			)
			self.activeOuting = newOuting(self, event, true)
		end
		self.activeOuting.firstHuntingRegionAt = self.activeOuting.firstHuntingRegionAt or event.at
		if type(event.regionId) == "string" then
			self.activeOuting.regionsVisited[event.regionId] = true
		end
	elseif event.state == "AtCamp" and self.activeOuting then
		local outing = self.activeOuting
		self.activeOuting = nil
		outing.returnAt = event.at
		outing.terminationReason = if outing.partial
			then "TrackingStartedMidOuting"
			elseif
				outing.configurationId ~= (event.configurationId or self.configurationId)
			then "ConfigurationChanged"
			elseif outing.firstHuntingRegionAt then "NormalReturn"
			else "NonHuntingOuting"
		outing.outingDuration = event.at - outing.departureAt
		outing.initialTransitDuration = if outing.firstHuntingRegionAt
			then outing.firstHuntingRegionAt - outing.departureAt
			else nil
		outing.fieldDuration = if outing.firstHuntingRegionAt
			then event.at - outing.firstHuntingRegionAt
			else nil
		local receipts = self.economy.platformCashCollected
			+ self.economy.salesCurrentSessionAssets
			+ self.economy.salesStartingAssets
			+ self.economy.salesUnknownProvenance
			+ self.economy.otherWalletCredits
		outing.walletReceipts = receipts - outing.startingWalletReceipts
		outing.platformProduction = self.economy.platformIncomeGenerated - outing.startingProduction
		local nonTransferCredits = self.economy.salesCurrentSessionAssets
			+ self.economy.salesStartingAssets
			+ self.economy.salesUnknownProvenance
			+ self.economy.otherWalletCredits
		outing.nonTransferWalletCredits = nonTransferCredits - outing.startingNonTransferCredits
		-- Platform collection is a transfer, so it remains visible in walletReceipts
		-- but is not counted again beside the production that created it.
		outing.ordinaryCurrency = outing.platformProduction
			+ math.max(0, self.economy.salesCurrentSessionAssets - outing.startingCurrentSales)
			+ math.max(0, self.economy.ordinaryOtherWalletCredits - outing.startingOrdinaryCredits)
		self:_closeOuting(outing)
	elseif event.state == "Interrupted" then
		self:InterruptOuting(event.reason or "Interrupted", event.at)
	else
		return false
	end
	return true
end

function ProgressionMetrics:_closeOuting(outing: any)
	outing.acquisitionOperations = self.counts.acquisitionOperations
		- outing.startingAcquisitionOperations
	outing.noAcquisitionObserved = outing.acquisitionOperations == 0
	outing.endingPlatformCash = self.currentPlatformCash
	outing.salesCurrentSessionAssets = self.economy.salesCurrentSessionAssets
		- outing.startingCurrentSales
	outing.salesStartingAssets = self.economy.salesStartingAssets - outing.startingAssetSales
	outing.salesUnknownProvenance = self.economy.salesUnknownProvenance
		- outing.startingUnknownSales
	outing.walletDebits = self.economy.walletDebits - outing.startingDebits
	outing.comparable = outing.terminationReason == "NormalReturn"
		and outing.configurationId == self.configurationId
	if outing.terminationReason == "NormalReturn" then
		self.outingTotals.completed += 1
		outing.campServiceObserved = "Open"
		outing.campBaseline = newOuting(
			self,
			{ at = outing.returnAt, configurationId = outing.configurationId },
			false
		)
		self.campServiceOuting = outing
	elseif outing.terminationReason == "NonHuntingOuting" then
		self.outingTotals.nonHunting += 1
	else
		self.outingTotals.interrupted += 1
		self.lastOutingBank = nil
	end
	table.insert(self.outings, outing)
	if #self.outings > RECENT_OUTING_LIMIT then
		table.remove(self.outings, 1)
		self.outingDetailDrops += 1
	end
end

function ProgressionMetrics:_finishCampService(at: number, reason: string, configurationId: string?)
	local outing = self.campServiceOuting
	if not outing then
		return
	end
	self.campServiceOuting = nil
	local baseline = outing.campBaseline
	outing.campBaseline = nil
	outing.campServiceObserved = if reason == "NextDeparture" then "Complete" else "Interrupted"
	outing.campServiceTerminationReason = reason
	outing.nextDepartureAt = if reason == "NextDeparture" then at else nil
	outing.campServiceCutoffAt = at
	outing.campServiceDuration = math.max(0, at - outing.returnAt)
	outing.campServicePlatformProduction = self.economy.platformIncomeGenerated
		- baseline.startingProduction
	outing.campServiceSalesCurrentSessionAssets = self.economy.salesCurrentSessionAssets
		- baseline.startingCurrentSales
	outing.campServiceSalesStartingAssets = self.economy.salesStartingAssets
		- baseline.startingAssetSales
	outing.campServiceSalesUnknownProvenance = self.economy.salesUnknownProvenance
		- baseline.startingUnknownSales
	outing.campServiceWalletDebits = self.economy.walletDebits - baseline.startingDebits
	outing.campServiceStartingPlatformCash = baseline.startingPlatformCash
	outing.campServiceEndingPlatformCash = self.currentPlatformCash
	local receipts = self.economy.platformCashCollected
		+ self.economy.salesCurrentSessionAssets
		+ self.economy.salesStartingAssets
		+ self.economy.salesUnknownProvenance
		+ self.economy.otherWalletCredits
	outing.campServiceWalletReceipts = receipts - baseline.startingWalletReceipts
	outing.ordinaryCycleCurrency = outing.ordinaryCurrency
		+ outing.campServicePlatformProduction
		+ math.max(0, outing.campServiceSalesCurrentSessionAssets)
		+ math.max(0, self.economy.ordinaryOtherWalletCredits - baseline.startingOrdinaryCredits)
	outing.comparable = outing.comparable
		and reason == "NextDeparture"
		and at >= outing.returnAt
		and outing.configurationId == (configurationId or self.configurationId)
	if outing.comparable and finiteNonNegative(outing.ordinaryCycleCurrency) then
		table.insert(self.recentComparableCurrency, outing.ordinaryCycleCurrency)
		if #self.recentComparableCurrency > RECENT_COMPARABLE_LIMIT then
			table.remove(self.recentComparableCurrency, 1)
		end
	end
end

function ProgressionMetrics:InterruptOuting(reason: string, at: number): boolean
	if not finite(at) then
		return false
	end
	self.lastOutingBank = nil
	if self.activeOuting == nil then
		local hadService = self.campServiceOuting ~= nil
		self:_finishCampService(at, reason, self.configurationId)
		return hadService
	end
	local outing = self.activeOuting
	self.activeOuting = nil
	outing.returnAt = nil
	outing.terminationReason = reason
	outing.observedDuration = math.max(0, at - outing.departureAt)
	self:_closeOuting(outing)
	return true
end

function ProgressionMetrics:SetEndingState(
	wallet: number,
	platformCash: number,
	at: number,
	collectiblePlatformCash: number?,
	final: boolean?
): boolean
	if not finiteNonNegative(wallet) or not finiteNonNegative(platformCash) or not finite(at) then
		return false
	end
	self.currentWallet = wallet
	self.currentPlatformCash = platformCash
	self.collectiblePlatformCash = if finiteNonNegative(collectiblePlatformCash)
			and (collectiblePlatformCash :: number) <= platformCash
		then collectiblePlatformCash
		else nil
	self.latestAuthoritativeStateAt = at
	if final ~= false then
		self.clocks.reportClosedAt = at
	end
	return true
end

function ProgressionMetrics:BeginDeparture(at: number, reason: string?)
	if finite(at) then
		self.clocks.departureCutoffAt = self.clocks.departureCutoffAt or at
		self:InterruptOuting(reason or "Disconnect", at)
		for _, state in self.offers do
			closeAffordableWindow(state, self.clocks.departureCutoffAt)
			state.currentAffordable = false
		end
	end
end

local function countKeys(values: any): number
	local count = 0
	for _ in values do
		count += 1
	end
	return count
end

function ProgressionMetrics:BuildReport(at: number?): any
	local cutoff = if finite(at) then at else self.clocks.reportClosedAt
	local gameplayCutoff = if self.clocks.departureCutoffAt and finite(cutoff)
		then math.min(cutoff :: number, self.clocks.departureCutoffAt)
		else cutoff
	local economy = self.economy
	local walletCredits = economy.platformCashCollected
		+ economy.salesCurrentSessionAssets
		+ economy.salesStartingAssets
		+ economy.salesUnknownProvenance
		+ economy.otherWalletCredits
	local playableDuration = relative(self.clocks.worldReadyAt, gameplayCutoff)
	local nonTransferCashIn = economy.platformIncomeGenerated
		+ economy.salesCurrentSessionAssets
		+ economy.salesStartingAssets
		+ economy.salesUnknownProvenance
		+ economy.otherWalletCredits
	local measuredPlayableCashIn = nonTransferCashIn
		- economy.prePlayablePlatformProduction
		- economy.prePlayableNonTransferCredits
	local expectedWallet = self.startingState.wallet
		+ economy.platformCashCollected
		+ economy.salesCurrentSessionAssets
		+ economy.salesStartingAssets
		+ economy.salesUnknownProvenance
		+ economy.otherWalletCredits
		- economy.walletDebits
		+ economy.walletAdjustments
	local expectedPlatform = self.startingState.settledPlatformCash
		+ economy.platformIncomeGenerated
		- economy.platformCashCollected
		+ economy.platformAdjustments
	local walletResidual = self.currentWallet - expectedWallet
	local platformResidual = self.currentPlatformCash - expectedPlatform
	local offers = {}
	local reference: any = nil
	for _, key in self.offerOrder do
		local state = self.offers[key]
		local cumulative = state.cumulativeEligibleAffordableDuration
		if state.affordableWindowStartedAt and finite(gameplayCutoff) then
			cumulative += math.max(0, (gameplayCutoff :: number) - state.affordableWindowStartedAt)
		end
		local shortfall = math.max(0, state.price - self.currentWallet)
		local view = {
			offerKey = key,
			offerId = state.offerId,
			targetKey = state.targetKey,
			termsVersion = state.termsVersion,
			price = state.price,
			active = state.active,
			supersededAt = state.supersededAt,
			displayOrder = state.displayOrder,
			baselineObserved = state.baselineObserved,
			ownedAtStart = state.ownedAtStart,
			fundsSufficientAtStart = state.fundsSufficientAtStart,
			prerequisitesSatisfiedAtStart = state.prerequisitesSatisfiedAtStart,
			readyAtStart = state.readyAtStart,
			ready = state.ready,
			prerequisitesSatisfied = state.prerequisitesSatisfied,
			owned = state.owned,
			pathBlocked = state.pathBlocked,
			primaryReason = state.primaryReason,
			firstFundsSufficientAt = state.firstFundsSufficientAt,
			firstFundsSufficientSinceWorldReady = relative(
				self.clocks.worldReadyAt,
				state.firstFundsSufficientAt
			),
			firstPrerequisiteSatisfiedAt = state.firstPrerequisiteSatisfiedAt,
			firstEligibleAffordableAt = state.firstEligibleAffordableAt,
			firstEligibleAffordableSinceWorldReady = relative(
				self.clocks.worldReadyAt,
				state.firstEligibleAffordableAt
			),
			currentAffordable = state.currentAffordable,
			affordableWindowEntries = state.affordableWindowEntries,
			cumulativeEligibleAffordableDuration = cumulative,
			firstContextIssuedAt = state.firstContextIssuedAt,
			firstMenuRenderedAt = state.firstMenuRenderedAt,
			firstOfferInspectedAt = state.firstOfferInspectedAt,
			attempts = state.attempts,
			rejections = copyMap(state.rejections),
			purchaseCommittedAt = state.purchaseCommittedAt,
			purchaseRequestId = state.purchaseRequestId,
			purchaseCommitRevision = state.purchaseCommitRevision,
			purchaseSavedAt = state.purchaseSavedAt,
			purchaseConfirmationLatency = if state.purchaseSavedAt
					and state.purchaseCommittedAt
					and state.purchaseSavedAt >= state.purchaseCommittedAt
				then state.purchaseSavedAt - state.purchaseCommittedAt
				else nil,
			purchaseOutcome = if state.purchaseCommittedAt
				then "Purchased"
				elseif state.ownedAtStart then "AlreadyOwned"
				elseif state.pathBlocked then "PathBlocked"
				else "NotObservedCensored",
			observedDuration = if finite(gameplayCutoff)
				then math.max(0, (gameplayCutoff :: number) - state.observationStartedAt)
				else nil,
			persistence = state.persistence,
			walletShortfall = shortfall,
			shortfallAfterCollectingAvailablePlatformCash = if self.collectiblePlatformCash
					~= nil
				then math.max(0, shortfall - self.collectiblePlatformCash)
				else nil,
		}
		if
			not state.owned
			and state.active
			and not state.pathBlocked
			and state.ready
			and state.prerequisitesSatisfied
			and (
				reference == nil
				or state.price < reference.price
				or (
					state.price == reference.price
					and (
						state.displayOrder < reference.displayOrder
						or (
							state.displayOrder == reference.displayOrder
							and key < reference.offerKey
						)
					)
				)
			)
		then
			reference = view
		end
		table.insert(offers, view)
	end
	table.sort(offers, function(left, right)
		return left.offerKey < right.offerKey
	end)
	local similarEstimate: any = { status = "INSUFFICIENT_DATA", sampleCount = 0 }
	if reference and #self.recentComparableCurrency >= 2 and reference.walletShortfall > 0 then
		local representative = median(self.recentComparableCurrency)
		if representative and representative > 0 then
			similarEstimate = {
				status = "AVAILABLE",
				sampleCount = #self.recentComparableCurrency,
				representativeOrdinaryCurrencyPerCycle = representative,
				estimatedSimilarCycles = math.ceil(reference.walletShortfall / representative),
				earningsDefinition = "complete outing plus camp-service cycle: platform production, current-session asset sales and explicitly ordinary credits; saved-asset liquidation, unknown sales, grants and collection transfers excluded",
			}
		end
	end
	return {
		session = {
			buildId = self.buildId,
			configurationId = self.configurationId,
			environment = self.environment,
			measurementVersion = self.measurementVersion,
			observationId = self.observationId,
			profileOrigin = self.profileOrigin,
			audioVariant = self.audioVariant,
			inputCategory = self.inputCategory,
			observationCompleteness = self.observationCompleteness,
			coverage = copyMap(self.coverage),
			clocks = table.clone(self.clocks),
			profileLoadDuration = relative(self.clocks.joinAt, self.clocks.profileReadyAt),
			worldReconstructionDuration = relative(
				self.clocks.profileReadyAt,
				self.clocks.worldReadyAt
			),
			joinToGameplayReady = relative(self.clocks.joinAt, self.clocks.worldReadyAt),
			playableDuration = playableDuration,
			connectedDuration = relative(self.clocks.joinAt, cutoff),
		},
		startingState = detailsCopy({ self.startingState })[1],
		economy = {
			startingWallet = self.startingState.wallet,
			endingWallet = self.currentWallet,
			startingSettledPlatformCash = self.startingState.settledPlatformCash,
			endingSettledPlatformCash = self.currentPlatformCash,
			platformIncomeGenerated = economy.platformIncomeGenerated,
			platformIncomeFromStartingAssets = economy.platformIncomeFromStartingAssets,
			platformIncomeFromCurrentSessionAssets = economy.platformIncomeFromCurrentSessionAssets,
			platformIncomeUnresolvedSource = economy.platformIncomeUnresolvedSource,
			platformCashCollected = economy.platformCashCollected,
			walletCredits = walletCredits,
			currencyUnit = "Cash",
			salesCurrentSessionAssets = economy.salesCurrentSessionAssets,
			salesStartingAssets = economy.salesStartingAssets,
			salesUnknownProvenance = economy.salesUnknownProvenance,
			otherWalletCredits = economy.otherWalletCredits,
			walletDebits = economy.walletDebits,
			walletAdjustments = economy.walletAdjustments,
			platformAdjustments = economy.platformAdjustments,
			prePlayablePlatformProduction = economy.prePlayablePlatformProduction,
			prePlayableWalletCredits = economy.prePlayableWalletCredits,
			prePlayableWalletDebits = economy.prePlayableWalletDebits,
			latestAuthoritativeStateAt = self.latestAuthoritativeStateAt,
			endingStateEvidence = if self.latestAuthoritativeStateAt
				then "AUTHORITATIVE_SETTLED_STATE"
				else "RECEIPTS_ONLY",
			accountingCoverage = if self.coverage.endingAuthorityUnavailable
					or self.coverage.unsequencedReplayWindowExceeded
					or self.coverage.incomeProvenanceMismatch
					or self.mapEvictions.sequenceWatermarks ~= nil
				then "INCOMPLETE_COVERAGE"
				else "OBSERVED_RECEIPTS",
			expectedEndingWallet = expectedWallet,
			expectedEndingPlatformCash = expectedPlatform,
			walletResidual = walletResidual,
			platformResidual = platformResidual,
			combinedResidual = walletResidual + platformResidual,
			reconciled = math.abs(walletResidual) <= EPSILON
				and math.abs(platformResidual) <= EPSILON
				and not self.coverage.endingAuthorityUnavailable
				and not self.coverage.unsequencedReplayWindowExceeded
				and not self.coverage.incomeProvenanceMismatch
				and self.mapEvictions.sequenceWatermarks == nil,
			sequenceCoverage = if self.mapEvictions.sequenceWatermarks
				then "INCOMPLETE"
				else "RETAINED_SOURCE_STREAMS",
		},
		rates = {
			window = "OBSERVED_PLAYABLE_INTERVAL",
			observedSeconds = playableDuration,
			shortWindow = not finite(playableDuration) or (playableDuration :: number) < 600,
			firstTenMinuteCoverage = if not finite(playableDuration)
					or (playableDuration :: number) < 600
				then "INCOMPLETE"
				else "NOT_SEPARATELY_AGGREGATED",
			nonTransferCashInPerPlayableMinute = if finite(playableDuration)
					and (playableDuration :: number) > 0
				then measuredPlayableCashIn * 60 / (playableDuration :: number)
				else nil,
			walletReceiptsPerPlayableMinute = if finite(playableDuration)
					and (playableDuration :: number) > 0
				then (walletCredits - economy.prePlayableWalletCredits) * 60 / playableDuration :: number
				else nil,
			interpretation = "Observed rates only; wallet receipts include collection transfers; non-transfer cash includes explicitly reported asset liquidation and is not a sustainable hunting-rate claim.",
		},
		offers = offers,
		worldProgression = {cohort=self.worldProgression.cohort,durationBasis=self.worldProgression.durationBasis,
			seededFixture=self.worldProgression.seededFixture==true,
			gates=detailsCopy({self.worldProgression.gates})[1],events=detailsCopy(self.worldProgression.events),
			counts=copyMap(self.worldProgression.counts),eventDrops=self.worldProgression.eventDrops,
			firstBankAt=self.worldProgression.firstBankAt},
		referenceNextAffordablePurchase = reference,
		similarExpeditionsRemaining = similarEstimate,
		milestones = {
			firstValidSleepHitAt = self.milestones.firstValidSleepHitAt,
			firstWildAcquisitionAt = self.milestones.firstWildAcquisitionAt,
			firstBankedPlacementAt = self.milestones.firstBankedPlacementAt,
			firstCargoPlacementAt = self.milestones.firstCargoPlacementAt,
			firstPlatformCollectionAt = self.milestones.firstPlatformCollectionAt,
			firstSaleAt = self.milestones.firstSaleAt,
			firstWildAcquisitionSinceWorldReady = relative(
				self.clocks.worldReadyAt,
				self.milestones.firstWildAcquisitionAt
			),
			firstBankedPlacementSinceWorldReady = relative(
				self.clocks.worldReadyAt,
				self.milestones.firstBankedPlacementAt
			),
		},
		activity = {
			counts = table.clone(self.counts),
			uniqueIndividualAcquisitions = if self.mapEvictions.uniqueAcquiredIndividuals
				then nil
				else countKeys(self.uniqueAcquiredIndividuals),
			uniqueSpeciesAcquired = if self.mapEvictions.uniqueAcquiredSpecies
				then nil
				else countKeys(self.uniqueAcquiredSpecies),
			completedOutings = self.outingTotals.completed,
			interruptedOutings = self.outingTotals.interrupted,
			nonHuntingOutings = self.outingTotals.nonHunting,
			bankToBankCount = self.bankToBankCount,
			bankToBankDurationTotal = self.bankToBankDurationTotal,
			outings = detailsCopy(self.outings),
			activeOuting = if self.activeOuting then detailsCopy({ self.activeOuting })[1] else nil,
		},
		persistence = {
			logicalSaveOperations = self.persistence.logicalSaveOperations,
			transportRetries = self.persistence.transportRetries,
			lastConfirmedRevision = self.persistence.lastConfirmedRevision,
			pendingPurchaseCount = self.persistence.pendingPurchaseCount,
			loadFailure = self.persistence.loadFailure,
			restorationBlocker = self.persistence.restorationBlocker,
			closeStatus = self.persistence.closeStatus,
		},
		coverage = {
			recentDetails = detailsCopy(self.recentDetails),
			detailDrops = self.detailDrops,
			dedupEvictions = self.dedupEvictions,
			mapEvictions = copyMap(self.mapEvictions),
			outingDetailDrops = self.outingDetailDrops,
			uniqueIndividualCountExact = self.mapEvictions.uniqueAcquiredIndividuals == nil,
			uniqueSpeciesCountExact = self.mapEvictions.uniqueAcquiredSpecies == nil,
			unsequencedReplayWindowExceeded = self.coverage.unsequencedReplayWindowExceeded == true,
		},
	}
end

return ProgressionMetrics
