--!strict
-- Non-authoritative adapter: failures are contained and never enter gameplay mutations.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Analytics = game:GetService("AnalyticsService")
local Config = require(RS.Shared.Config.Phase13Analytics)
local Service = {}
local deps = {}
local queue = {}
local recorder = {}
local states = {}
local started = false
local clock = os.clock
local provider = nil
local function state(player)
	if not states[player] then
		states[player] = {
			window = clock(),
			count = 0,
			active = 0,
			ready = false,
			seen = {},
			funnels = {},
			checkpoints = {},
			affordability = {},
			acquisitions = { Hunt = 0, Theft = 0, OwnedMove = 0 },
			secured = {},
			session = Http:GenerateGUID(false),
		}
	end
	return states[player]
end
local function fields(category, result)
	return {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = Config.Version,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = category,
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = result,
	}
end
local function enqueue(player, event)
	local s = state(player)
	local at = clock()
	if at - s.window >= 60 then
		s.window = at
		s.count = 0
	end
	if s.count >= Config.PerPlayerPerMinute or #queue >= Config.QueueLimit then
		return false
	end
	s.count += 1
	event.player = player
	table.insert(queue, event)
	return true
end
function Service:Record(player, name, value, values)
	if not Config.Events[name] or type(value) ~= "number" or value ~= value or math.abs(value) > 9e15 or not player then
		return false
	end
	values = values or {}
	local category = values.category or "Session"
	local result = values.result or "Recorded"
	if not Config.Categories[category] or not Config.Results[result] then
		return false
	end
	return enqueue(player, { kind = "Custom", name = name, value = value, fields = fields(category, result) })
end
function Service:Economy(player, flow, amount, balance, category, sku)
	if flow ~= "Source" and flow ~= "Sink" then
		return false
	end
	if
		type(amount) ~= "number"
		or amount <= 0
		or amount ~= amount
		or amount > 9e15
		or type(balance) ~= "number"
		or balance < 0
		or balance ~= balance
		or balance > 9e15
		or not Config.Categories[category]
	then
		return false
	end
	if type(sku) ~= "string" or not sku:match("^[A-Z0-9_]+$") or #sku > 40 then
		return false
	end
	return enqueue(player, {
		kind = "Economy",
		flow = flow,
		amount = amount,
		balance = balance,
		category = category,
		sku = sku,
		fields = fields(category, "Success"),
	})
end
function Service:Funnel(player, name, step, sessionId)
	local definition = Config.Funnels[name]
	if not definition or type(step) ~= "number" or not definition[step] then
		return false
	end
	local s = state(player)
	local id = sessionId or s.session
	if type(id) ~= "string" or #id > 128 then
		return false
	end
	local key = name .. ":" .. id
	local previous = s.funnels[key] or 0
	if s.funnels[key] == nil then
		local count = 0
		for _ in s.funnels do
			count += 1
		end
		if count >= 128 then
			return false
		end
	end
	-- Never imply an earlier action from a later branch event.
	if step ~= previous + 1 then
		return false
	end
	if
		enqueue(player, {
			kind = "Funnel",
			name = name,
			step = step,
			stepName = definition[step],
			sessionId = id,
			fields = fields("Session", "Success"),
		})
	then
		s.funnels[key] = step
		return true
	end
	return false
end
function Service:Receipt(player, kind, response)
	if type(response) ~= "table" or response.state ~= "Confirmed" then
		return false
	end
	local s = state(player)
	local id = response.operationId
	if not id or s.seen[id] then
		return false
	end
	local count = 0
	for _ in s.seen do
		count += 1
	end
	if count >= 512 then
		return false
	end
	s.seen[id] = true
	local result = response.result or {}
	if kind == "Rebirth" then
		s.cinematic = { operationId = response.operationId, route = result.route, at = clock() }
		self:BeginRecovery(player, result)
		local funnel = s.rebirthFunnel
		if funnel and funnel.rewardId == result.rewardId and funnel.route == result.route then
			self:Funnel(player, "RebirthTransaction", 4, funnel.session)
			s.rebirthFunnel = nil
		end
		if result.rewardKind == "Expansion" and type(result.capacity) == "number" then
			self:Funnel(player, "ExpansionProgression", (result.capacity - 12) / 6)
		end
	elseif kind == "PlatformSwap" and type(result.saleCash) == "number" then
		self:ObserveEarnedCash(player, result.saleCash)
	end
	local snapshot = nil
	if provider then
		local ok, value = pcall(provider, player)
		if ok then
			snapshot = value
		end
	end
	local name = "PurchaseOutcome"
	local category = "Cash"
	if kind == "Rebirth" then
		name = "RebirthOutcome"
		category = "Rebirth"
	elseif kind == "PlatformSwap" then
		name = "SwapOutcome"
		category = "Swap"
	elseif kind == "PaidCash" or kind == "PassGrant" then
		name = "PaidGrantOutcome"
		category = if kind == "PaidCash" then "Cash" else "Pass"
	elseif kind == "ProtectionOptOut" then
		name = "ProtectionOptOut"
		category = "Theft"
	elseif kind == "Appearance" then
		name = "CosmeticSelected"
		category = "Cosmetic"
	elseif kind == "CataloguePurchase" or kind == "OwnedSelection" then
		category = if Config.Categories[result.category] then result.category else "Cash"
	end
	self:Record(player, name, 1, { category = category, result = "Success" })
	if type(result.amount) == "number" and result.amount > 0 and type(result.balance) == "number" then
		self:Economy(
			player,
			"Source",
			result.amount,
			result.balance,
			category,
			if kind == "PaidCash" then "PAID_CASH" else "PASS_GRANT"
		)
	end
	if type(result.sacrificedCash) == "number" and result.sacrificedCash > 0 then
		self:Economy(player, "Sink", result.sacrificedCash, 0, "Rebirth", "CASH_REBIRTH")
	end
	if
		kind == "CataloguePurchase"
		and type(result.price) == "number"
		and result.price > 0
		and snapshot
		and type(snapshot.balance) == "number"
	then
		self:Economy(player, "Sink", result.price, snapshot.balance, category, "CATALOGUE_PURCHASE")
		self:Funnel(player, "EarlyJourney", 5)
	end
	return true
end
-- All durations below use active world-ready seconds, never loading or offline time.
local recoveryCategories = { "RecoveryCps25", "RecoveryCps50", "RecoveryCps100" }
local cashRecoveryCategories = { "RecoveryCash25", "RecoveryCash50", "RecoveryCash100" }
local function interruptRecovery(self, player, s)
	local recovery = s.recovery
	if not recovery then
		return
	end
	local remaining = (if recovery.firstEarner then 0 else 1)
	if recovery.target > 0 then
		for i = 1, 3 do
			if not recovery.done[i] then
				remaining += 1
			end
		end
	end
	if remaining > 0 then
		-- This is a censored outcome count, not a fabricated completed duration.
		self:Record(player, "RebirthOutcome", remaining, {
			category = if recovery.route == "Collection" then "RecoveryCollection" else "RecoveryCash",
			result = "Incomplete",
		})
	end
	s.recovery = nil
end
function Service:BeginRecovery(player, result)
	if type(result) ~= "table" or (result.route ~= "Cash" and result.route ~= "Collection") then
		return false
	end
	local s = state(player)
	interruptRecovery(self, player, s)
	local target = if result.route == "Collection" then result.baseCpsBefore else result.sacrificedCash
	if type(target) ~= "number" or target ~= target or target < 0 or target > 9e15 then
		return false
	end
	s.recovery = {
		route = result.route,
		target = target,
		started = s.active,
		earned = 0,
		done = {},
		firstEarner = result.route == "Cash",
		firstBank = false,
		session = Http:GenerateGUID(false),
	}
	if result.route == "Collection" then
		self:Record(
			player,
			"RebirthOutcome",
			result.sacrificedIndividuals or 0,
			{ category = "SacrificeCount", result = "Success" }
		)
		self:Record(player, "RebirthOutcome", target, { category = "LostBaseCps", result = "Success" })
		self:Funnel(player, "CollectionRecovery", 1, s.recovery.session)
	end
	return true
end
function Service:ObserveEarnedCash(player, amount)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > 9e15 then
		return false
	end
	local r = state(player).recovery
	if r and r.route == "Cash" then
		r.earned = math.min(9e15, r.earned + amount)
	end
	return true
end
function Service:ObserveLegalTheftAttempt(player)
	state(player).legalTheftObserved = true
	self:Funnel(player, "TheftBranch", 1)
	self:Funnel(player, "TheftBranch", 2)
end
function Service:ObserveFirstBank(player, receipt)
	local s = state(player)
	local secured = type(receipt) == "table" and s.secured[receipt.individualId]
	if secured and not secured.banked and (secured.kind == "Hunt" or secured.kind == "Theft") then
		secured.banked = true
		self:Record(
			player,
			"CaptureToBankDuration",
			math.max(0, clock() - secured.at),
			{ category = secured.kind, result = "Success" }
		)
	end
	self:ObserveRecoveryBank(player)
end
function Service:ObserveCinematicOutcome(player, report)
	if type(report) ~= "table" then
		return false
	end
	local expected = states[player] and states[player].cinematic
	if not expected or expected.operationId ~= report.operationId then
		return false
	end
	local reasons = {
		Completed = "Completed",
		Skipped = "Skipped",
		Interrupted = "Interrupted",
		Superseded = "Interrupted",
		Death = "Interrupted",
		Respawn = "Interrupted",
		PlotRemoved = "Interrupted",
		Reset = "Interrupted",
		Stopped = "Interrupted",
	}
	local result = reasons[report.reason]
	local elapsed = report.elapsed
	if
		not result
		or type(elapsed) ~= "number"
		or elapsed ~= elapsed
		or elapsed < 0
		or elapsed > 10
		or clock() - expected.at > 30
	then
		return false
	end
	for key in report do
		if key ~= "kind" and key ~= "operationId" and key ~= "reason" and key ~= "elapsed" then
			return false
		end
	end
	if report.reason == "Skipped" and elapsed < 1 then
		return false
	end
	if report.reason == "Completed" and elapsed < 7 then
		return false
	end
	states[player].cinematic = nil -- Once-only diagnostic; never changes ownership or rewards.
	return self:Record(player, "CinematicOutcome", elapsed, {
		category = if expected.route == "Collection" then "CinematicCollection" else "CinematicCash",
		result = result,
	})
end
function Service:RecordHuntSummary(player, counters, outcome, elapsed)
	if type(counters) ~= "table" or type(elapsed) ~= "number" or elapsed ~= elapsed or elapsed < 0 then
		return false
	end
	local categories = {
		Shots = "HuntAcceptedShots",
		Hits = "HuntHits",
		Sleeps = "HuntSleeps",
		FailedPickups = "HuntPickupFailures",
		Departed = "HuntDeparted",
		Reset = "HuntReset",
	}
	for key in categories do
		local value = counters[key] or 0
		if type(value) ~= "number" or value ~= value or value < 0 or value % 1 ~= 0 or value > 1000000 then
			return false
		end
	end
	if not Config.Results[outcome] then
		return false
	end
	self:Record(player, "HuntOutcome", 1, { category = "Hunt", result = outcome })
	self:Record(player, "HuntDuration", elapsed, { category = "Hunt", result = outcome })
	for key, category in categories do
		self:Record(player, "HuntOutcome", counters[key] or 0, { category = category, result = outcome })
	end
	return true
end
function Service:ObserveRecoveryBank(player)
	local r = state(player).recovery
	if r and r.route == "Collection" and not r.firstBank then
		r.firstBank = true
		self:Funnel(player, "CollectionRecovery", 2, r.session)
	end
end
function Service:ObserveSecuredAcquisition(player, kind, identity)
	local s = state(player)
	if s.acquisitions[kind] == nil or type(identity) ~= "string" then
		return false
	end
	local key = if kind == "OwnedMove" then "OwnedMove:" .. identity else identity
	if s.secured[key] then
		return false
	end
	local n = 0
	for _ in s.secured do
		n += 1
	end
	if n >= 512 then
		return false
	end
	s.secured[key] = { at = clock(), kind = kind } -- Internal dedupe; never custom fields.
	s.acquisitions[kind] += 1
	return true
end
local function observeSnapshot(self, player, s, snapshot)
	local r = s.recovery
	if r then
		local value = if r.route == "Collection" then snapshot.baseCps else r.earned
		local elapsed = math.max(0, s.active - r.started)
		if type(value) == "number" and value > 0 then
			if r.route == "Collection" and not r.firstEarner then
				r.firstEarner = true
				self:Record(
					player,
					"RebirthRecoveryDuration",
					elapsed,
					{ category = "RecoveryFirstEarner", result = "Success" }
				)
			end
			if r.target > 0 then
				for i, ratio in { 0.25, 0.5, 1 } do
					if not r.done[i] and value >= r.target * ratio then
						r.done[i] = true
						local category = if r.route == "Collection"
							then recoveryCategories[i]
							else cashRecoveryCategories[i]
						self:Record(
							player,
							"RebirthRecoveryDuration",
							elapsed,
							{ category = category, result = "Success" }
						)
						if r.route == "Collection" and r.firstBank then
							self:Funnel(player, "CollectionRecovery", 3, r.session)
						end
					end
				end
			end
		end
	end
	for _, offer in snapshot.affordableOffers or {} do
		if
			type(offer.key) == "string"
			and not s.affordability[offer.key]
			and Config.AffordabilityContexts[offer.key]
			and type(offer.price) == "number"
			and offer.price > 0
		then
			s.affordability[offer.key] = true
			self:Record(player, "AffordabilityReached", s.active, { category = offer.key, result = "Success" })
		end
	end
	for _, minute in { 15, 30, 60, 120 } do
		if not s.checkpoints[minute] and s.active >= minute * 60 then
			s.checkpoints[minute] = true
			local result = "Checkpoint" .. minute
			local measurements = {
				UnlockedRegions = snapshot.unlockedRegions,
				Capacity = snapshot.capacity,
				Occupancy = snapshot.occupancy,
				IncomeBand = snapshot.incomeBand,
				RebirthCount = snapshot.rebirthCount,
				HuntAcquisitions = s.acquisitions.Hunt,
				TheftAcquisitions = s.acquisitions.Theft,
				OwnedMoves = s.acquisitions.OwnedMove,
				PaidCohort = snapshot.paidCohort,
			}
			for category, value in measurements do
				if type(value) == "number" then
					self:Record(player, "SessionCheckpoint", value, { category = category, result = result })
				end
			end
		end
	end
end
function Service:ObserveDeparture(player)
	local s = states[player]
	if not s then
		return
	end
	interruptRecovery(self, player, s)
	self:Record(player, "WorldReadyDuration", s.active, { category = "Session", result = "Incomplete" })
end
function Service:_ObserveSnapshotForTests(player, delta, snapshot)
	assert(RunService:IsStudio() and not started, "Inactive Studio fixture only")
	local s = state(player)
	s.active += delta
	observeSnapshot(self, player, s, snapshot)
end
function Service:ObserveRebirthQuote(player, quote)
	if
		type(quote) ~= "table"
		or type(quote.rewardId) ~= "string"
		or (quote.route ~= "Cash" and quote.route ~= "Collection")
	then
		return false
	end
	local s = state(player)
	local f = {
		rewardId = quote.rewardId,
		route = quote.route,
		revision = quote.previewRevision,
		session = Http:GenerateGUID(false),
		valid = quote.ok == true,
	}
	s.rebirthFunnel = f
	self:Funnel(player, "RebirthTransaction", 1, f.session)
	if f.valid then
		self:Funnel(player, "RebirthTransaction", 2, f.session)
	end
	return true
end
function Service:ObserveRebirthConfirm(player, request)
	local f = state(player).rebirthFunnel
	if
		not f
		or not f.valid
		or f.rewardId ~= request.rewardId
		or f.route ~= request.route
		or f.revision ~= request.previewRevision
	then
		return false
	end
	return self:Funnel(player, "RebirthTransaction", 3, f.session)
end
function Service:ObserveWorldReady(player)
	local s = state(player)
	s.ready = true
	if s.everReady then
		return
	end
	s.everReady = true
	self:Record(player, "WorldReadyDuration", 0, { category = "Session", result = "Success" })
	self:Record(player, "ConfigurationLoaded", 1, { category = "Configuration", result = "Success" })
	self:Funnel(player, "EarlyJourney", 1)
	if provider then
		local ok, snapshot = pcall(provider, player)
		if ok and type(snapshot) == "table" and snapshot.forestUnlocked == true then
			self:Funnel(player, "RegionProgression", 1)
		end
	end
end
function Service:SetWorldReady(player, ready)
	if ready then
		self:ObserveWorldReady(player)
	else
		state(player).ready = false
	end
end
function Service:SetSnapshotProvider(fn)
	provider = fn
end
function Service:GetRecorder()
	return table.clone(recorder)
end
local sentWindow = 0
local windowStarted = clock()
local function deliver(event)
	if deps.Sink then
		pcall(deps.Sink, event)
		return
	end
	if RunService:IsStudio() or not Config.ProductionEnabled or game.PlaceId == 0 then
		if #recorder >= Config.RecorderLimit then
			table.remove(recorder, 1)
		end
		-- No raw profile, chat, receipt ID or arbitrary player-provided fields enter the recorder.
		table.insert(recorder, event)
		return
	end
	pcall(function()
		if event.kind == "Custom" then
			Analytics:LogCustomEvent(event.player, event.name, event.value, event.fields)
		elseif event.kind == "Economy" then
			Analytics:LogEconomyEvent(
				event.player,
				if event.flow == "Source"
					then Enum.AnalyticsEconomyFlowType.Source
					else Enum.AnalyticsEconomyFlowType.Sink,
				"Cash",
				event.amount,
				event.balance,
				if event.sku == "PAID_CASH" or event.sku == "PASS_GRANT"
					then Enum.AnalyticsEconomyTransactionType.IAP.Name
					else Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
				event.sku,
				event.fields
			)
		elseif event.kind == "Funnel" then
			Analytics:LogFunnelStepEvent(
				event.player,
				event.name,
				event.sessionId,
				event.step,
				event.stepName,
				event.fields
			)
		end
	end)
end
function Service:Step(delta)
	for player, s in states do
		local ready = s.ready and player.Parent == Players and player:GetAttribute("PlayerDataStatus") == "Ready"
		if ready then
			s.active += math.max(0, math.min(delta, 1))
			if provider then
				local ok, snapshot = pcall(provider, player)
				if ok and type(snapshot) == "table" then
					observeSnapshot(self, player, s, snapshot)
					if snapshot.huntable == false then
						s.noTarget = (s.noTarget or 0) + math.max(0, math.min(delta, 1))
					end
					if s.active - (s.lastSummary or 0) >= 60 then
						s.lastSummary = s.active
						self:Record(
							player,
							"AvailabilitySummary",
							s.noTarget or 0,
							{ category = snapshot.regionCategory or "Session", result = "Recorded" }
						)
						if s.legalTheftObserved then
							self:Record(
								player,
								"AvailabilitySummary",
								1,
								{ category = "LegalTheftObserved", result = "Recorded" }
							)
							s.legalTheftObserved = nil
						end
						s.noTarget = 0
					end
				end
			end
		end
	end
	for _ = 1, 4 do
		if #queue == 0 then
			break
		end
		if not RunService:IsStudio() and Config.ProductionEnabled and game.PlaceId ~= 0 then
			local at = clock()
			if at - windowStarted >= 60 then
				windowStarted = at
				sentWindow = 0
			end
			-- Leave 20% of the documented 120+20*CCU budget for existing platform calls.
			local budget = math.floor((120 + 20 * #Players:GetPlayers()) * 0.8)
			if sentWindow >= budget then
				break
			end
			sentWindow += 1
		end
		deliver(table.remove(queue, 1))
	end
end

function Service:Start(options)
	if started then
		return false
	end
	started = true
	deps = options or {}
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.5 then
			local d = elapsed
			elapsed = 0
			self:Step(d)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:ObserveDeparture(player)
		for i = #queue, 1, -1 do
			if queue[i].player == player then
				deliver(table.remove(queue, i))
			end
		end
		states[player] = nil
	end)
	return true
end
function Service:_ResetForTests(sink)
	assert(RunService:IsStudio() and not started, "Inactive Studio fixture only")
	table.clear(queue)
	sentWindow = 0
	windowStarted = clock()
	table.clear(recorder)
	table.clear(states)
	deps = { Sink = sink }
	provider = nil
end
return Service
