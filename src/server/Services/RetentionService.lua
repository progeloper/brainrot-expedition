--!strict
-- Existing profile owner / critical coordinator adapter. Money is written only
-- inside the originating domain mutation, never by a publication callback.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Config = require(RS.Shared.Config.RetentionConfig)
local Environment = require(RS.Shared.Config.Environment)
local AttachmentCosmetics = require(RS.Shared.Utility.Phase14CosmeticRules)
local Catalog = require(RS.Shared.Config.BrainrotCatalog)
local Rules = require(RS.Shared.Utility.RetentionRules)
local Goals = require(RS.Shared.Utility.RetentionGoals)
local Profiles = require(script.Parent.PlayerDataService)
local Logger = require(RS.Shared.Utility.Logger)
local log = Logger.new("Retention")
local Service = {}
local started, connections = false, {}
local boundaries = setmetatable({}, { __mode = "k" })
local requestTimes = setmetatable({}, { __mode = "k" })
local rejectTimes = setmetatable({}, { __mode = "k" })
local snapshotSequences = setmetatable({}, { __mode = "k" })
local published = setmetatable({}, { __mode = "k" })
-- One bounded confirmed view per player, tagged to the actual acquired generation.
local confirmedSnapshots = setmetatable({}, { __mode = "k" })
local mirrored = setmetatable({}, { __mode = "k" })
local events = setmetatable({}, { __mode = "k" })
local returning = setmetatable({}, { __mode = "k" })
local sessionIds = setmetatable({}, { __mode = "k" })
local currency = require(script.Parent.Parent.Systems.CurrencySystem)
local profile, unixNow, transactions = Profiles, os.time, nil
local update, request
local questOrder = { "bring_them_home", "field_research", "camp_payday" }
local function connection(signal)
	table.insert(connections, signal)
end
local function diagnostic(player, kind, fields)
	sessionIds[player] = sessionIds[player] or Http:GenerateGUID(false)
	fields.sessionId, fields.environment = sessionIds[player], Environment.Name
	fields.build = tostring(game.PlaceVersion) .. ":" .. Config.RewardConfigVersion
	fields.serverUTC = unixNow()
	local ok, encoded = pcall(Http.JSONEncode, Http, fields)
	if ok then
		log:Info("%s %s", kind, encoded)
	end
end
local function reject(player, code)
	local at = os.clock()
	if at - (rejectTimes[player] or -math.huge) >= 5 then
		rejectTimes[player] = at
		diagnostic(player, "retention_request_rejected", { code = code })
	end
	return { ok = false, code = code }
end
local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, nested in value do
		result[key] = copy(nested)
	end
	return result
end
local function label(data, field)
	local state = data.Retention
	local id = state[field]
	local definition = id and Config.MilestoneById[id]
	return if definition
			and state.Milestones
			and state.Milestones[id]
		then definition.Label
		else nil
end
local function collectionSnapshot(data, saving)
	local state, count, rows, entries = data.Retention, Rules.DiscoveryCount(data), {}, {}
	local nextMilestone
	for _, definition in Config.Milestones do
		local owned = state.Milestones and state.Milestones[definition.Id] ~= nil
		local row = {
			id = definition.Id,
			label = definition.Label,
			slot = definition.Slot,
			required = definition.Species,
			anomaly = definition.Anomaly == true,
			owned = owned and not saving,
			state = if owned and saving then "Saving" elseif owned then "Owned" else "Locked",
		}
		table.insert(rows, row)
		if not owned and definition.Species and not nextMilestone then
			nextMilestone = row
		end
	end
	for _, definition in Catalog.GetAll() do
		if definition.launchStatus == "Live" then
			local discovered = Rules.IsDiscovered(data, definition.id)
			local variants = if discovered then Rules.DiscoveryVariants(data, definition.id) else {}
			table.insert(entries, {
				id = definition.id,
				discovered = discovered,
				name = if definition.tier == "Secret" and not discovered
					then "???"
					else definition.displayName,
				tier = if definition.tier == "Secret" and not discovered
					then "???"
					else definition.tier,
				modelRef = if discovered then definition.modelRef else nil,
				variants = variants,
				canFeature = discovered,
				hidden = definition.tier == "Secret" and not discovered,
			})
		end
	end
	local title, titleId = Rules.ResolveTitle(data)
	return {
		count = count,
		riftPatronOwned = data.Commerce.Entitlements.VIP == true,
		totalLive = 32,
		pageSize = 12,
		entries = entries,
		milestones = rows,
		nextMilestone = nextMilestone,
		selectedTitle = titleId,
		title = title,
		selectedNameplate = state.SelectedNameplate or "None",
		nameplate = label(data, "SelectedNameplate"),
		selectedPlaque = state.SelectedPlaque or "None",
		plaque = label(data, "SelectedPlaque"),
		selectedBadge = state.SelectedBadge or "None",
		badge = label(data, "SelectedBadge"),
		featuredSpeciesId = state.FeaturedSpeciesId,
	}
end
local function suppliesSnapshot(data, dayKey, frozen, saving)
	local supply = data.Retention.Supplies or { lifetimeClaims = 0 }
	local n = supply.lifetimeClaims + 1
	local position = ((n - 1) % 7) + 1
	local claimed = supply.lastClaimDay == dayKey
	local tiles = {}
	for i = 1, 7 do
		table.insert(tiles, {
			position = i,
			units = Config.SupplyRewardUnitsByCycleClaim[i],
			rewardCash = Rules.RewardAmount(frozen, Config.SupplyRewardUnitsByCycleClaim[i]),
			claimed = i < position,
			next = i == position,
		})
	end
	local checkpoints = {}
	for _, claim in { 7, 14 } do
		local id = Config.SupplyCosmeticByLifetimeClaim[claim]
		table.insert(checkpoints, {
			lifetimeClaim = claim,
			cosmeticId = id,
			owned = (data.Commerce.Entitlements[id] == true) and not saving,
			label = if claim == 7 then "Camp Regular Flag" else "Expedition Crest Banner",
		})
	end
	return {
		lifetimeClaims = supply.lifetimeClaims,
		nextLifetimeClaim = n,
		cyclePosition = position,
		claimedToday = claimed,
		claimable = data.Retention.Eligible and not claimed and not saving,
		lastPaid = supply.lastPaid == true and not saving,
		lastAmountCash = if supply.lastPaid == true and not saving
			then supply.lastAmountCash or 0
			else 0,
		lastGrantId = supply.lastGrantId,
		state = if saving or (claimed and supply.lastPaid ~= true)
			then "Saving"
			elseif claimed then "Claimed"
			else "Available",
		rewardCash = Rules.RewardAmount(frozen, Config.SupplyRewardUnitsByCycleClaim[position]),
		tiles = tiles,
		checkpoints = checkpoints,
	}
end
function Service:Snapshot(player)
	local now = unixNow()
	local dayKey = math.floor(now / Config.ResetPeriodSeconds)
	snapshotSequences[player] = (snapshotSequences[player] or 0) + 1
	sessionIds[player] = sessionIds[player] or Http:GenerateGUID(false)
	local snapshot = published[player] and copy(published[player])
		or {
			available = false,
			eligible = false,
			status = "TemporarilyUnavailable",
			revision = 0,
			retentionRevision = 0,
			daily = {},
			completedCount = 0,
		}
	snapshot.available, snapshot.status, snapshot.serverTime = false, "TemporarilyUnavailable", now
	snapshot.dayKey, snapshot.resetAt = dayKey, (dayKey + 1) * Config.ResetPeriodSeconds
	snapshot.snapshotSequence, snapshot.sessionId = snapshotSequences[player], sessionIds[player]
	snapshot.capabilities = { dailies = 3, supplies = true, collection = true, goals = true }
	local diag, data = profile:GetDiagnostics(player), profile:GetReadableData(player)
	if diag then
		snapshot.revision = math.max(snapshot.revision, diag.currentRevision)
	end
	if data and data.Retention then
		snapshot.retentionRevision = math.max(snapshot.retentionRevision, data.Retention.Revision)
	end
	local writable = profile:IsWritable(player)
	local confirmed = confirmedSnapshots[player]
	if
		confirmed
		and (
			not diag
			or confirmed.generation ~= diag.generation
			or diag.status ~= "Ready"
			or diag.closing == true
			or player.Parent ~= Players
		)
	then
		confirmedSnapshots[player], confirmed = nil, nil
	end
	local criticalSaving = not writable
		and Config.Enabled
		and diag ~= nil
		and diag.status == "Ready"
		and diag.closing ~= true
		and player.Parent == Players
		and profile.HasCriticalOperation ~= nil
		and profile:HasCriticalOperation(player)
	if criticalSaving then
		-- The write fence is not an ownership failure. Return only a same-session
		-- Ready baseline, never working counts, ownership, goal or selected items.
		local sequence, sessionId = snapshot.snapshotSequence, snapshot.sessionId
		snapshot = if confirmed
			then copy(confirmed.snapshot)
			else {
				available = false,
				eligible = false,
				daily = {},
				completedCount = 0,
				retentionRevision = 0,
			}
		snapshot.available, snapshot.status = confirmed ~= nil, "Saving"
		snapshot.revision = diag.currentRevision
		snapshot.serverTime, snapshot.snapshotSequence, snapshot.sessionId =
			now, sequence, sessionId
		snapshot.capabilities = { dailies = 3, supplies = true, collection = true, goals = true }
		if snapshot.dayKey ~= dayKey then
			-- Yesterday's confirmed paid rows must not become today's progress.
			for _, row in snapshot.daily do
				row.count, row.paid, row.paidCash, row.state = 0, false, 0, "Saving"
			end
			snapshot.completedCount, snapshot.estimated = 0, true
			if snapshot.supplies then
				snapshot.supplies.claimedToday = false
			end
		end
		snapshot.dayKey, snapshot.resetAt = dayKey, (dayKey + 1) * Config.ResetPeriodSeconds
		if snapshot.supplies then
			snapshot.supplies.claimable, snapshot.supplies.state = false, "Saving"
		end
		return snapshot
	end
	if not Config.Enabled or not writable then
		return snapshot
	end
	local valid, reason = Rules.ValidateConfig()
	if not valid then
		snapshot.reason = reason
		return snapshot
	end
	if not data or not data.Retention or not diag then
		return snapshot
	end
	local state, boundary = data.Retention, boundaries[player]
	local saving = boundary ~= nil and diag.lastConfirmedSavedRevision < boundary.profileRevision
	local day = state.Day
	local currentDay = day ~= nil and day.dayKey == dayKey
	local band = if currentDay then day.regionBand else nil
	if not band then
		band, reason = Rules.ResolveBand(data)
	end
	if not band then
		snapshot.reason = reason
		return snapshot
	end
	local unit = if currentDay then day.unitCash else Config.UnitCashByRegionBand[band]
	local frozen = if currentDay then day else { unitCash = unit }
	snapshot.available, snapshot.status = true, if saving then "Saving" else "Ready"
	snapshot.eligible = if saving and boundary then boundary.previouslyEligible else state.Eligible
	snapshot.revision, snapshot.retentionRevision = diag.currentRevision, state.Revision
	snapshot.band, snapshot.unitCash, snapshot.estimated = band, unit, not currentDay
	snapshot.rewardConfigVersion = if currentDay
		then day.rewardConfigVersion
		else Config.RewardConfigVersion
	snapshot.daily, snapshot.completedCount = {}, 0
	for _, id in questOrder do
		local definition = Config.QuestDefinitions[id]
		local quest = if currentDay then day[id] else nil
		local paid = quest ~= nil and quest.paid and not saving
		snapshot.daily[id] = {
			id = id,
			label = definition.Label,
			instruction = definition.Instruction,
			count = if quest then quest.count else 0,
			target = definition.Target,
			rewardCash = Rules.RewardAmount(
				frozen,
				if currentDay then day.rewardUnits[id] else definition.RewardUnits
			),
			paid = paid == true,
			paidCash = if paid then quest.paidCash else 0,
			state = if saving
				then "Saving"
				elseif paid then "Completed"
				elseif quest and quest.count == definition.Target then "Saving"
				else "InProgress",
		}
		if paid then
			snapshot.completedCount += 1
		end
	end
	snapshot.supplies = suppliesSnapshot(data, dayKey, frozen, saving)
	snapshot.collection = collectionSnapshot(data, saving)
	snapshot.goal = Goals.Resolve(data, data.Progression.TrackedUpgradeId)
	snapshot.goalOptions = Goals.Options(data)
	snapshot.returnRows = {}
	if snapshot.goal then
		table.insert(snapshot.returnRows, { kind = "Goal", goal = snapshot.goal })
	end
	if state.Eligible then
		table.insert(snapshot.returnRows, { kind = "Supply", supplies = snapshot.supplies })
	end
	if returning[player] then
		table.insert(snapshot.returnRows, {
			kind = "Refresher",
			text = "Shoot to sleep → pick up → bank → collect platform earnings.",
		})
	elseif snapshot.collection.nextMilestone then
		table.insert(snapshot.returnRows, {
			kind = "Milestone",
			milestone = snapshot.collection.nextMilestone,
			count = snapshot.collection.count,
		})
	end
	while #snapshot.returnRows > 3 do
		table.remove(snapshot.returnRows)
	end
	published[player] = copy(snapshot)
	if snapshot.status == "Ready" then
		confirmedSnapshots[player] = { generation = diag.generation, snapshot = copy(snapshot) }
	end
	return snapshot
end
local function publishAttributes(player, snapshot)
	if snapshot.status ~= "Ready" or not snapshot.collection then
		return
	end
	local c = snapshot.collection
	player:SetAttribute("RetentionTitleLabel", c.title or "")
	player:SetAttribute("RetentionNameplateLabel", c.nameplate or "")
	player:SetAttribute("RetentionPlaqueLabel", c.plaque or "")
	player:SetAttribute("RetentionBadgeLabel", c.badge or "")
	player:SetAttribute("RetentionCollectionCount", c.count)
	player:SetAttribute("RetentionFeaturedSpeciesId", c.featuredSpeciesId)
	local definition = c.featuredSpeciesId and Catalog.Get(c.featuredSpeciesId)
	player:SetAttribute(
		"RetentionFeaturedSpeciesName",
		definition and definition.displayName or nil
	)
	player:SetAttribute("RetentionPublicRevision", snapshot.revision)
end
function Service:Publish(player)
	local snapshot = self:Snapshot(player)
	if snapshot.status == "Ready" then
		publishAttributes(player, snapshot)
		if boundaries[player] and (mirrored[player] or -1) < snapshot.retentionRevision then
			mirrored[player] = snapshot.retentionRevision
			currency:SyncBalance(player)
		end
	end
	if update and player.Parent == Players then
		update:FireClient(player, snapshot)
	end
	return snapshot
end
function Service:Recover(player)
	local data = profile:GetReadableData(player)
	local pending = data and data.Retention and data.Retention.PendingRewards
	if not pending or next(pending) == nil or not profile:IsWritable(player) then
		return
	end
	local ids = {}
	for id in pending do
		table.insert(ids, id)
	end
	table.sort(ids)
	local owner = transactions or require(script.Parent.Phase13Service)
	if owner:IsBusy(player) then
		return
	end
	owner:CommitCritical(player, ids[1], "RetentionRecovery", function(current)
		return Rules.RecoverPending(current, ids[1])
	end)
end
local allowed = {
	Snapshot = { action = true },
	ClaimSupply = { action = true },
	PinGoal = { action = true, goalId = true },
	FeatureDiscovery = { action = true, speciesId = true },
	EquipMilestone = { action = true, slot = true, value = true },
}
function Service:Handle(player, payload, ...)
	if select("#", ...) ~= 0 or type(payload) ~= "table" or not allowed[payload.action] then
		return reject(player, "INVALID_REQUEST")
	end
	for key in payload do
		if not allowed[payload.action][key] then
			return reject(player, "INVALID_REQUEST")
		end
	end
	for key in allowed[payload.action] do
		if
			key ~= "action"
			and (
				type(payload[key]) ~= "string"
				or #payload[key] < 1
				or #payload[key] > 128
				or payload[key]:find("%c")
			)
		then
			return reject(player, "INVALID_REQUEST")
		end
	end
	local at = os.clock()
	if at - (requestTimes[player] or -math.huge) < 0.25 then
		return reject(player, "RATE_LIMITED")
	end
	requestTimes[player] = at
	if payload.action == "Snapshot" then
		return self:Snapshot(player)
	end
	if not Config.Enabled or not profile:IsWritable(player) then
		return reject(player, "PROFILE_NOT_WRITABLE")
	end
	local data = profile:GetReadableData(player)
	if not data or not data.Retention then
		return reject(player, "NOT_READY")
	end
	local owner = transactions or require(script.Parent.Phase13Service)
	local requestedDay = math.floor(unixNow() / Config.ResetPeriodSeconds)
	local operationId = if payload.action == "ClaimSupply"
		then "retention:supply-date:" .. tostring(requestedDay)
		else "retention:" .. Http:GenerateGUID(false)
	local result = owner:CommitCritical(
		player,
		operationId,
		"Retention" .. payload.action,
		function(current)
			if payload.action == "ClaimSupply" then
				local now = unixNow()
				if math.floor(now / Config.ResetPeriodSeconds) ~= requestedDay then
					return false, { code = "DAY_CHANGED" }
				end
				return Rules.ClaimSupply(current, now)
			elseif payload.action == "PinGoal" then
				return Goals.Pin(current, payload.goalId)
			elseif payload.action == "FeatureDiscovery" then
				return Rules.FeatureDiscovery(current, payload.speciesId)
			else
				return Rules.EquipMilestone(current, payload.slot, payload.value)
			end
		end
	)
	local response = copy(result)
	response.snapshot = self:Snapshot(player)
	return response
end
local function queue(player, revision, kind, fields)
	events[player] = events[player] or {}
	-- Bounded server-local diagnostics. Financial receipts remain durable in profile state.
	if #events[player] < 64 then
		table.insert(events[player], { revision = revision, kind = kind, fields = fields })
	end
end
local function observeMutation(player, before, current)
	local old, state = before.Retention, current.Retention
	if not state then
		return
	end
	if old and old.Revision == state.Revision then
		if
			next(state.PendingRewards) ~= nil
			and current.Economy.Balance < before.Economy.Balance
		then
			task.defer(function()
				if started then
					Service:Recover(player)
				end
			end)
		end
		return
	end
	local revision, prior = profile:GetCurrentRevision(player), boundaries[player]
	boundaries[player] = {
		profileRevision = revision,
		previouslyEligible = if prior
				and not profile:IsRevisionConfirmed(player, prior.profileRevision)
			then prior.previouslyEligible
			else old and old.Eligible == true,
	}
	local day, oldDay = state.Day, old and old.Day
	if day and (not oldDay or oldDay.dayKey ~= day.dayKey) then
		queue(player, revision, "retention_day_initialized", {
			dayKey = day.dayKey,
			band = day.regionBand,
			unitCash = day.unitCash,
			rewardConfigVersion = day.rewardConfigVersion,
		})
	end
	if day then
		for _, id in questOrder do
			local quest = day[id]
			local priorQuest = oldDay and oldDay.dayKey == day.dayKey and oldDay[id]
			if quest and quest.count > (if priorQuest then priorQuest.count else 0) then
				queue(player, revision, "retention_progress_committed", {
					dayKey = day.dayKey,
					questId = id,
					before = if priorQuest then priorQuest.count else 0,
					after = quest.count,
					band = day.regionBand,
					unitCash = day.unitCash,
					rewardConfigVersion = day.rewardConfigVersion,
					sourceOperation = quest.sourceOperation,
					amountCash = if quest.paid then quest.paidCash else 0,
					grantId = quest.grantId,
				})
			end
			if quest and quest.paid and (not priorQuest or not priorQuest.paid) then
				queue(player, revision, "retention_reward_committed", {
					dayKey = day.dayKey,
					questId = id,
					amountCash = quest.paidCash,
					grantId = quest.grantId,
					band = day.regionBand,
					unitCash = day.unitCash,
					rewardConfigVersion = day.rewardConfigVersion,
					sourceOperation = quest.sourceOperation,
				})
			end
		end
	end
	local oldSupply = old and old.Supplies
	if
		state.Supplies
		and state.Supplies.lifetimeClaims > (if oldSupply then oldSupply.lifetimeClaims else 0)
	then
		queue(player, revision, "retention_supply_claimed", {
			dayKey = state.Supplies.lastClaimDay,
			lifetimeClaim = state.Supplies.lifetimeClaims,
			amountCash = state.Supplies.lastAmountCash,
			grantId = state.Supplies.lastGrantId,
			paid = state.Supplies.lastPaid,
			band = day and day.regionBand,
			unitCash = day and day.unitCash,
			rewardConfigVersion = day and day.rewardConfigVersion,
		})
	end
	for species in current.Collection.Species do
		if not (before.Collection.Species or {})[species] then
			queue(player, revision, "collection_discovery_added", { speciesId = species })
		end
	end
	for id in state.Milestones or {} do
		if not old or not old.Milestones or not old.Milestones[id] then
			queue(player, revision, "collection_milestone_awarded", { milestoneId = id })
		end
	end
	for id, reward in old and old.PendingRewards or {} do
		if state.PendingRewards[id] == nil then
			queue(player, revision, "retention_recovery_completed", {
				grantId = id,
				amountCash = reward.amountCash,
				dayKey = reward.dayKey,
				unitCash = reward.unitCash,
				band = reward.regionBand,
				rewardConfigVersion = reward.rewardConfigVersion,
				sourceOperation = reward.sourceOperation,
			})
		end
	end
	for _, field in { "SelectedTitle", "SelectedNameplate", "SelectedPlaque", "SelectedBadge" } do
		if state[field] ~= (old and old[field]) then
			queue(
				player,
				revision,
				"cosmetic_equipped",
				{ slot = field, value = state[field] or "None" }
			)
		end
	end
	if current.Progression.TrackedUpgradeId ~= before.Progression.TrackedUpgradeId then
		queue(
			player,
			revision,
			"progression_goal_changed",
			{ goalId = current.Progression.TrackedUpgradeId or "None" }
		)
	end
	Service:Publish(player)
end
local function flush(player, saved)
	local pending = events[player] or {}
	for i = #pending, 1, -1 do
		local event = pending[i]
		if event.revision <= saved then
			event.fields.profileRevision = event.revision
			diagnostic(player, event.kind, event.fields)
			table.remove(pending, i)
		end
	end
end
-- Existing shop onConfirmed adapters call this only after a covering save.
-- It is diagnostic-only: no wallet, ownership, equip or profile write occurs here.
function Service:ObserveCosmeticConfirmed(player, result, operationId)
	if
		not started
		or type(result) ~= "table"
		or type(operationId) ~= "string"
		or #operationId > 240
	then
		return false
	end
	local data, diag = profile:GetReadableData(player), profile:GetDiagnostics(player)
	if not data or not diag or diag.lastConfirmedSavedRevision < diag.currentRevision then
		return false
	end
	local kind, fields
	if result.id then
		local definition = AttachmentCosmetics.Get(result.id)
		if
			not definition
			or definition.acquisition ~= "Cash"
			or result.priceCash ~= definition.priceCash
			or not AttachmentCosmetics.Owns(data, result.id)
		then
			return false
		end
		kind, fields =
			"cosmetic_purchased",
			{ cosmeticId = result.id, amountCash = -result.priceCash, operationId = operationId }
	elseif result.key and result.value then
		if
			not AttachmentCosmetics.IsSlot(result.key)
			or data.Commerce.Appearance[result.key] ~= result.value
		then
			return false
		end
		kind, fields =
			"cosmetic_equipped",
			{ slot = result.key, value = result.value, operationId = operationId }
	else
		return false
	end
	queue(player, diag.currentRevision, kind, fields)
	flush(player, diag.lastConfirmedSavedRevision)
	return true
end
local function touchLastSeen(player)
	if not Config.Enabled or not profile.CommitMutation or not profile:IsWritable(player) then
		return
	end
	profile:CommitMutation(player, function(data)
		local valid, reason = Rules.Migrate(data)
		if not valid then
			return false, { code = reason }
		end
		data.Retention.LastSeenAt = unixNow()
		return true, { ok = true, code = "VISIT_RECORDED" }
	end)
end
local function ready(player)
	local data = profile:GetReadableData(player)
	if returning[player] == nil then
		local last = data and data.Retention and data.Retention.LastSeenAt
		returning[player] = type(last) == "number" and unixNow() - last >= 168 * 3600
	end
	touchLastSeen(player)
	Service:Publish(player)
	Service:Recover(player)
end
function Service:Start(options)
	if started then
		return false
	end
	options = options or {}
	profile = options.Profile or Profiles
	assert(options.Clock == nil or RunService:IsStudio(), "Retention test clock is Studio-only")
	assert(
		options.Replication ~= false or RunService:IsStudio(),
		"Retention isolated replication seam is Studio-only"
	)
	assert(
		options.Transactions == nil or RunService:IsStudio(),
		"Retention coordinator fixture is Studio-only"
	)
	currency, unixNow, transactions =
		options.Currency or require(script.Parent.Parent.Systems.CurrencySystem),
		options.Clock or os.time,
		options.Transactions
	started = true
	if options.Replication ~= false then
		local folder = RS:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name, folder.Parent = "Remotes", RS
		end
		request = folder:FindFirstChild("RetentionRequest")
		assert(request == nil or request:IsA("RemoteFunction"), "RetentionRequest type conflict")
		if not request then
			request = Instance.new("RemoteFunction")
			request.Name, request.Parent = "RetentionRequest", folder
		end
		update = folder:FindFirstChild("RetentionUpdate")
		assert(update == nil or update:IsA("RemoteEvent"), "RetentionUpdate type conflict")
		if not update then
			update = Instance.new("RemoteEvent")
			update.Name, update.Parent = "RetentionUpdate", folder
		end
		request.OnServerInvoke = function(player, ...)
			return self:Handle(player, ...)
		end
	end
	connection(profile:SubscribeMutations(observeMutation))
	connection(profile:SubscribeSaveConfirmed(function(player, saved)
		local diag = profile:GetDiagnostics(player)
		flush(player, saved or (diag and diag.lastConfirmedSavedRevision) or 0)
		self:Publish(player)
		task.defer(function()
			if started then
				self:Recover(player)
			end
		end)
	end))
	-- Save listener order is unspecified: profile readiness may still be fenced
	-- when our save observer runs. The existing coordinator publishes after release.
	local coordinator = transactions or require(script.Parent.Phase13Service)
	if coordinator.SubscribeConfirmed then
		connection(coordinator:SubscribeConfirmed(function(player)
			local diag = profile:GetDiagnostics(player)
			if diag then
				flush(player, diag.lastConfirmedSavedRevision)
			end
			self:Publish(player)
			task.defer(function()
				if started then
					self:Recover(player)
				end
			end)
		end))
	end
	connection(profile:SubscribeReady(ready))
	connection(profile:SubscribeDiagnostics(function(player, event)
		if
			event.kind == "SessionLost"
			or event.kind == "CloseUnconfirmed"
			or event.kind == "LoadRejected"
		then
			confirmedSnapshots[player] = nil
			self:Publish(player)
		end
	end))
	if profile.RegisterDeparturePreparer then
		connection(profile:RegisterDeparturePreparer(function(player)
			touchLastSeen(player)
			return true
		end))
	end
	local banks = options.Banks or require(script.Parent.BankedBrainrotService)
	connection(banks:SubscribeBankCommitted(function(player)
		self:Publish(player)
	end))
	connection(Players.PlayerRemoving:Connect(function(player)
		rejectTimes[player] = nil
		confirmedSnapshots[player] = nil
		boundaries[player], requestTimes[player], published[player], mirrored[player], events[player], returning[player], sessionIds[player] =
			nil, nil, nil, nil, nil, nil, nil
	end))
	for _, player in Players:GetPlayers() do
		if profile:IsWritable(player) then
			ready(player)
		end
	end
	return true
end
function Service:Stop()
	for _, item in connections do
		item:Disconnect()
	end
	table.clear(connections)
	if request then
		request.OnServerInvoke = nil
	end
	request, update, started = nil, nil, false
	for _, map in
		{
			boundaries,
			requestTimes,
			rejectTimes,
			snapshotSequences,
			published,
			confirmedSnapshots,
			mirrored,
			events,
			returning,
			sessionIds,
		}
	do
		table.clear(map)
	end
	profile, unixNow, transactions = Profiles, os.time, nil
end
return Service
