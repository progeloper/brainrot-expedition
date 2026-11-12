--!strict
-- Read-only domain observers. Covering saves gate transaction telemetry too.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Analytics = require(script.Parent.Phase13AnalyticsService)
local Profiles = require(script.Parent.PlayerDataService)
local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
local Upgrade = require(script.Parent.UpgradeService)
local Banked = require(script.Parent.BankedBrainrotService)
local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
local Interest = require(script.Parent.Phase13InterestService)
local Roaming = require(script.Parent.Parent.Systems.DevelopmentBrainrotRoaming)
local Rules = require(RS.Shared.Utility.Phase13Rules)
local Catalog = require(RS.Shared.Config.BrainrotCatalog)
local Values = require(RS.Shared.Utility.Phase12Rules)
local Config = require(RS.Shared.Config.Phase13)
local Weapons = require(RS.Shared.Config.Weapons)
local saveHealth = {}
local function observeSaveDiagnostic(player, receipt)
	if type(receipt) ~= "table" or type(receipt.at) ~= "number" then
		return
	end
	local h = saveHealth[player]
	if not h and typeof(player) == "Instance" and player.Parent ~= Players then
		return
	end
	if
		h
		and type(h.generation) == "number"
		and type(receipt.generation) == "number"
		and receipt.generation < h.generation
	then
		return
	end
	if not h or h.generation ~= receipt.generation then
		h = {
			generation = receipt.generation,
			attempts = 0,
			failures = 0,
			uncertainties = 0,
			lastAttemptSequence = 0,
			confirmations = 0,
			latency = 0,
		}
		saveHealth[player] = h
	end
	if receipt.kind == "SaveStarted" then
		h.batchStarted = receipt.at
		h.pendingSince = h.pendingSince or receipt.at
	elseif receipt.kind == "SaveAttemptCompleted" then
		local sequence = receipt.attemptSequence
		if
			type(sequence) ~= "number"
			or sequence % 1 ~= 0
			or sequence <= h.lastAttemptSequence
			or sequence > 9007199254740991
		then
			return
		end
		if type(receipt.ok) ~= "boolean" or type(receipt.uncertain) ~= "boolean" then
			return
		end
		h.lastAttemptSequence = sequence
		h.attempts += 1
		if not receipt.ok then
			h.failures += 1
		end
		if receipt.uncertain then
			h.uncertainties += 1
		end
	elseif receipt.kind == "SaveConfirmed" then
		if h.batchStarted then
			h.confirmations += 1
			h.latency += math.max(0, receipt.at - h.batchStarted)
			h.batchStarted = nil
		end
		if receipt.savedRevision >= receipt.currentRevision then
			if h.pendingSince then
				h.pendingCompleted = (h.pendingCompleted or 0) + math.max(0, receipt.at - h.pendingSince)
			end
			h.pendingSince = nil
		end
	end
end
local function flushSaveHealth(player, at)
	local h = saveHealth[player]
	if not h then
		return
	end
	local metrics = {
		SaveAttempts = h.attempts,
		SaveFailures = h.failures,
		SaveUncertainAttempts = h.uncertainties,
		SaveConfirmations = h.confirmations,
	}
	-- Omit unknown latency, rather than inventing a zero-second completed save.
	if h.confirmations > 0 then
		metrics.SaveLatencySeconds = h.latency / h.confirmations
	end
	if h.pendingSince or h.pendingCompleted then
		metrics.SavePendingSeconds = (h.pendingCompleted or 0)
			+ (if h.pendingSince then math.max(0, at - h.pendingSince) else 0)
	end
	for category, value in metrics do
		Analytics:Record(player, "SaveHealth", value, { category = category, result = "Recorded" })
	end
	h.attempts, h.failures, h.uncertainties, h.confirmations, h.latency = 0, 0, 0, 0, 0
	h.pendingCompleted = nil
	if h.pendingSince then
		h.pendingSince = at
	end
end
local function affordableOffers(data)
	local result = {}
	local p, wallet = data.Phase13, data.Economy.Balance
	local function add(key, category, price, eligible, availableCash)
		if eligible and type(price) == "number" and price > 0 and (availableCash or wallet) >= price then
			table.insert(result, { key = key, category = category, price = price })
		end
	end
	for _, definition in Weapons.GetAll() do
		add("Weapon:" .. definition.id, "Weapon", definition.price, not p.OwnedWeaponIds[definition.id])
	end
	for _, definition in Config.CartRows do
		add("Cart:" .. definition.id, "Cart", definition.price, not p.OwnedCartIds[definition.id])
	end
	if require(RS.Shared.Config.CampReworkFlags).Training() then
		-- Camp Rework: Speed upgrades retired; the next Cash roller is the comparable offer.
		for _, roller in require(RS.Shared.Config.Training).Rollers do
			if roller.price > 0 and not (type(p.OwnedRollers) == "table" and p.OwnedRollers[roller.id]) then
				add("Roller:" .. roller.id, "Cart", roller.price, true)
				break
			end
		end
	else
		add("Speed:" .. (p.SpeedLevel + 1), "Cart", Config.SpeedPrices[p.SpeedLevel + 1], p.SpeedLevel < 5)
	end
	add("Cargo:" .. (p.CargoLevel + 1), "Cart", Config.CargoPrices[p.CargoLevel + 1], p.CargoLevel < 3)
	local equipped = data.ChariotTeam and (2 + data.ChariotTeam.PurchasedExtraSlots)
	if type(equipped) == "number" then
		add("Equipped:" .. (equipped + 1), "Cart", Config.EquippedPrices[equipped + 1], equipped < 6)
	end
	for _, list in { Config.ExpansionRows, Config.DesignRows } do
		for _, definition in list do
			if not definition.starter then
				local quote = Rules.QuoteRebirth(data, definition.id, "Cash")
				add("Rebirth:" .. definition.id, "Rebirth", definition.price, quote.ok, quote.totalCash)
			end
		end
	end
	return result
end
local Service = {}
local started = false
local pending = {}
local seen = {}
local rows = {}
local categories = {
	REGION_FOREST = "Forest",
	REGION_BEACH = "Beach",
	REGION_SWAMP = "Swamp",
	REGION_JUNGLE = "Jungle",
	REGION_ARCTIC = "Arctic",
	REGION_VOLCANO = "Volcano",
	REGION_GLITCH = "Glitch",
	REGION_CAMP = "Camp",
}
local function enqueue(player, key, revision, flow, amount, balance, category, sku)
	if type(revision) ~= "number" or type(amount) ~= "number" or amount <= 0 or type(balance) ~= "number" then
		return
	end
	seen[player] = seen[player] or {}
	if seen[player][key] then
		return
	end
	local n = 0
	for _ in seen[player] do
		n += 1
	end
	if n >= 512 then
		return
	end
	seen[player][key] = true
	pending[player] = pending[player] or {}
	if #pending[player] >= 64 then
		return
	end
	table.insert(
		pending[player],
		{ revision = revision, flow = flow, amount = amount, balance = balance, category = category, sku = sku }
	)
end
local function flush(player, saved)
	local events = pending[player]
	if not events then
		return
	end
	for i = #events, 1, -1 do
		local event = events[i]
		if event.revision <= saved then
			Analytics:Economy(player, event.flow, event.amount, event.balance, event.category, event.sku)
			if event.flow == "Sink" then
				Analytics:Funnel(player, "EarlyJourney", 5)
			end
			table.remove(events, i)
		end
	end
end
-- The optional fifth domain argument is the immutable committed receipt.
-- Reading the current profile here could observe a later transaction instead.
local function observeUpgradePurchase(player, offer, revision, receipt)
	if
		type(receipt) ~= "table"
		or receipt.kind ~= "PurchaseCommitted"
		or type(offer) ~= "table"
		or type(offer.id) ~= "string"
		or type(revision) ~= "number"
		or type(receipt.chargedAmount) ~= "number"
		or receipt.offerId ~= offer.id
		or receipt.commitRevision ~= revision
		or receipt.chargedAmount ~= offer.price
		or type(receipt.balanceAfter) ~= "number"
	then
		return false
	end
	enqueue(
		player,
		"upgrade:" .. offer.id .. ":" .. revision,
		revision,
		"Sink",
		receipt.chargedAmount,
		receipt.balanceAfter,
		"Cart",
		"CART_UPGRADE"
	)
	return true
end

function Service:GetSnapshot(player)
	local data = Profiles:GetReadableData(player)
	if not data or not data.Phase13 then
		return nil
	end
	local capacity = Rules.GetCapacity(data)
	local baseCps = 0
	local occupancy = 0
	for i = 1, capacity do
		local slot = data.Base.Slots[tostring(i)]
		local record = slot and slot.brainrotId and data.Collection.BrainrotInstances[slot.brainrotId]
		if record then
			local definition = Catalog.Get(record.speciesId)
			if definition then
				baseCps += definition.cashPerSecond * Values.MutationMultiplier(record.mutationId or "None")
				occupancy += 1
			end
		end
	end
	local unlocked = 0
	for _ in (data.WorldProgression and data.WorldProgression.PersonalUnlocks) or {} do
		unlocked += 1
	end
	local paid = false
	if data.Commerce then
		paid = (data.Commerce.ReceiptCount or 0) > 0 or data.Commerce.StarterPackClaimed == true
		for _, owned in data.Commerce.Entitlements or {} do
			paid = paid or owned == true
		end
	end
	local region = Interest:GetRegion(player)
	local huntable = false
	for _, record in rows do
		if
			record.regionId == region
			and record.state ~= "Sleeping"
			and record.state ~= "Emerging"
			and (record.HP or 0) > 0
		then
			huntable = true
			break
		end
	end
	return {
		unlockedRegions = unlocked,
		forestUnlocked = data.WorldProgression and data.WorldProgression.PersonalUnlocks.Forest ~= nil,
		incomeBand = if baseCps <= 0
			then 0
			elseif baseCps < 10000000 then 1
			elseif baseCps < 100000000 then 2
			elseif baseCps < 1000000000 then 3
			else 4,
		paidCohort = if paid then 1 else 0,
		affordableOffers = affordableOffers(data),
		balance = data.Economy.Balance,
		capacity = capacity,
		occupancy = occupancy,
		baseCps = baseCps,
		productionCps = Income:GetIncomeRate(player),
		rebirthCount = data.Phase13.RebirthCount,
		huntable = huntable,
		regionCategory = categories[region] or "Session",
	}
end
function Service:Start()
	if started then
		return false
	end
	started = true
	Analytics:SetSnapshotProvider(function(player)
		return self:GetSnapshot(player)
	end)
	Currency:SubscribeCommitted(function(player, r)
		if r.kind == "WalletCredit" and r.source == "BrainrotSale" then
			Analytics:ObserveEarnedCash(player, r.amount)
			enqueue(player, r.eventId, r.revision, "Source", r.amount, r.balanceAfter, "Cash", "BRAINROT_SALE")
		elseif r.kind == "WalletDebit" and type(r.source) == "string" and r.source:match("^ChariotSlot%d$") then
			enqueue(player, r.eventId, r.revision, "Sink", r.amount, r.balanceAfter, "Cart", "EQUIPPED_SLOT")
		end
	end)
	Upgrade:SubscribePurchaseCommitted(function(player, offer, _target, revision, receipt)
		observeUpgradePurchase(player, offer, revision, receipt)
	end)
	Profiles:SubscribeDiagnostics(observeSaveDiagnostic)
	Income:SubscribeCommitted(function(player, receipt)
		if receipt.kind == "PlatformIncomeProduced" then
			Analytics:ObserveEarnedCash(player, receipt.amount)
		end
	end)
	Profiles:SubscribeSaveConfirmed(flush)
	Banked:SubscribeBankCommitted(function(player, r)
		Analytics:Funnel(player, "EarlyJourney", 3)
		if r.acquisitionKind == "Hunt" then
			Analytics:Funnel(player, "HuntBranch", 4)
		elseif r.acquisitionKind == "Theft" then
			Analytics:Funnel(player, "TheftBranch", 4)
		end
		Analytics:ObserveFirstBank(player, r)
	end)
	local elapsed = 0
	local healthElapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		rows = Roaming.GetPresentationSnapshot()
		healthElapsed += 0.5
		if healthElapsed >= 60 then
			healthElapsed = 0
			for player in saveHealth do
				flushSaveHealth(player, os.clock())
			end
		end
		for player in pending do
			local saved = Profiles:GetSavedRevision(player)
			if saved then
				flush(player, saved)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		flushSaveHealth(player, os.clock())
		saveHealth[player] = nil
		pending[player] = nil
		seen[player] = nil
	end)
	return true
end
function Service:_ObserveUpgradePurchaseForTests(player, offer, revision, receipt)
	assert(RunService:IsStudio() and not started, "Inactive Studio fixture only")
	return observeUpgradePurchase(player, offer, revision, receipt)
end
function Service:_FlushTransactionsForTests(player, savedRevision)
	assert(RunService:IsStudio() and not started, "Inactive Studio fixture only")
	flush(player, savedRevision)
end
function Service:_ObserveSaveDiagnosticForTests(player, receipt)
	assert(RunService:IsStudio() and not started, "Inactive Studio fixture only")
	observeSaveDiagnostic(player, receipt)
end
function Service:_FlushSaveHealthForTests(player, at)
	assert(RunService:IsStudio() and not started, "Inactive Studio fixture only")
	flushSaveHealth(player, at)
end
function Service:_AffordableOffersForTests(data)
	assert(RunService:IsStudio() and not started, "Inactive Studio fixture only")
	return affordableOffers(data)
end
return Service
