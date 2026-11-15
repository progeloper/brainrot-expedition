--!nocheck
-- MANUAL, UNMAPPED, READ-ONLY gameplay observer. Install as the server Script
-- ServerScriptService.Server.Phase7G1GameplayObserver BEFORE enabling Bootstrap.
-- Script attributes: RunOptIn=true, RunId (<=64 alphanumeric/_/-), Cohort
-- (Fresh/PartialReturning/DevelopedReturning), Stage (INITIAL/REJOIN), optional
-- ExpectedUserId (the real Players identity, NOT a backend fixture alias).
-- The cohort adapter waits for ObserverReady=true before enabling Bootstrap.
-- No cloned services, synthetic Players/receipts, settlement, mutation or save.
-- Exports ONLY sanitized evidence through Workspace attributes:
-- Phase7G1Obs_<RunId>_<Loaded|Ready|Cutoff|FinalSource|Closed>_{Count,Bytes,Complete,1..N}.
-- Read Complete, Count, then concatenate numbered chunks before JSON decoding.
-- Increment Workspace.Phase7G1SnapshotRequest for an on-demand Snapshot export
-- (maximum64 requests). FinalSource/Closed also mirror bounded JSON to Output.
-- Workspace exports belong to this Play DataModel; collect before Studio stops.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio Play server required"
)
assert(
	game.PlaceId == 91958083796436 and game.GameId == 10548905405,
	"Exact Development place required"
)
assert(script:GetAttribute("RunOptIn") == true, "Explicit observer opt-in required")
local runId = script:GetAttribute("RunId")
local cohort = script:GetAttribute("Cohort")
local stage = script:GetAttribute("Stage")
assert(
	type(runId) == "string" and #runId > 0 and #runId <= 64 and runId:match("^[%w_%-]+$"),
	"Invalid run label"
)
assert(
	cohort == "Fresh" or cohort == "PartialReturning" or cohort == "DevelopedReturning",
	"Invalid cohort"
)
assert(stage == "INITIAL" or stage == "REJOIN", "Explicit INITIAL or REJOIN stage required")
local server = assert(ServerScriptService:FindFirstChild("Server"), "Server source missing")
local bootstrap = assert(server:FindFirstChild("Bootstrap"), "Bootstrap missing")
assert(
	bootstrap:IsA("Script") and not bootstrap.Enabled,
	"Install observer before Bootstrap starts"
)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Config = require(server.Config.PlayerDataConfig)
assert(Environment.Name == "Development" and not Environment.IsProduction, "Development only")
assert(
	Environment.EnableDataSaving == true and Environment.DataStorePrefix == "dev_v2",
	"Development saving must already be enabled"
)
assert(
	Config.StoreName == "dev_v2_player_profiles_v1"
		and Config.StoreScope == nil
		and Config.KeyPrefix == "player_",
	"Unexpected persistence identity"
)

local Profile = require(server.Services.PlayerDataService)
local Metrics = require(server.Services.ProgressionMetricsService)
local World = require(server.Services.PlayerWorldLifecycle)
local Income = require(server.Systems.BrainrotIncomeSystem)
local prefix = "Phase7G1Obs_" .. runId
assert(Workspace:GetAttribute(prefix .. "_Loaded_Count") == nil, "Run label already exported")
script:SetAttribute("RunOptIn", false)
local CHUNK_BYTES, MAX_CHUNKS, MAX_IDENTITIES = 6000, 64, 128
local connections, tasks = {}, {}
local target, session, observationId
local stopped, closing, ready, cutoffCaptured = false, false, false, false
local installedAt = Workspace:GetServerTimeNow()
local diagnostics, diagnosticDrops = {}, 0
local loadedAt, worldReadyAt, cutoffTargetAt
local snapshotRequests, lastSnapshotRequest = 0, 0
for _, player in Players:GetPlayers() do
	assert(
		Profile:GetSessionHandle(player) == nil,
		"Observer cannot backfill an already-loaded session"
	)
end

local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, nested in value do
		result[key] = clone(nested)
	end
	return result
end

local function equal(left, right)
	if type(left) ~= type(right) then
		return false
	end
	if type(left) ~= "table" then
		return left == right
	end
	for key, value in left do
		if not equal(value, right[key]) then
			return false
		end
	end
	for key in right do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local function publish(name, evidence, replace)
	local encoded = HttpService:JSONEncode(evidence)
	assert(#encoded <= CHUNK_BYTES * MAX_CHUNKS, "Observer export exceeds bounded capacity")
	local chunks, first = {}, 1
	while first <= #encoded do
		local last = math.min(first + CHUNK_BYTES - 1, #encoded)
		while
			last < #encoded
			and string.byte(encoded, last + 1) >= 128
			and string.byte(encoded, last + 1) < 192
		do
			last -= 1 -- do not split a UTF-8 codepoint across attribute values
		end
		table.insert(chunks, string.sub(encoded, first, last))
		first = last + 1
	end
	assert(#chunks <= MAX_CHUNKS, "Observer export chunk limit exceeded")
	local key = prefix .. "_" .. name
	assert(
		replace == true or Workspace:GetAttribute(key .. "_Complete") == nil,
		"Refusing to overwrite an existing run export"
	)
	local previousCount = Workspace:GetAttribute(key .. "_Count") or 0
	Workspace:SetAttribute(key .. "_Complete", false)
	for index, chunk in chunks do
		Workspace:SetAttribute(key .. "_" .. index, chunk)
	end
	Workspace:SetAttribute(key .. "_Bytes", #encoded)
	Workspace:SetAttribute(key .. "_Count", #chunks)
	Workspace:SetAttribute(key .. "_Complete", true)
	for index = #chunks + 1, math.min(previousCount, MAX_CHUNKS) do
		Workspace:SetAttribute(key .. "_" .. index, nil)
	end
	if name == "FinalSource" or name == "Closed" then
		-- Studio's on-disk CreatorOutput clips long messages rather than wrapping
		-- them. Keep this independent from the larger Workspace attribute chunks.
		local consoleChunks, cursor = {}, 1
		while cursor <= #encoded do
			local last = math.min(cursor + 699, #encoded)
			while
				last < #encoded
				and string.byte(encoded, last + 1) >= 128
				and string.byte(encoded, last + 1) < 192
			do
				last -= 1
			end
			table.insert(consoleChunks, string.sub(encoded, cursor, last))
			cursor = last + 1
		end
		for index, chunk in consoleChunks do
			print(
				string.format(
					"[PHASE7G1_OBSERVER_FINAL] run=%s stage=%s chunk=%d/%d %s",
					runId,
					name,
					index,
					#consoleChunks,
					chunk
				)
			)
		end
	end
end

local function guarded(label, callback)
	local ok, failure = pcall(callback)
	if not ok then
		Workspace:SetAttribute(
			prefix .. "_Error",
			label .. ": " .. string.sub(tostring(failure), 1, 400)
		)
		script:SetAttribute("ObserverStatus", "ERROR")
	end
	return ok
end

local function sourceProjection(data)
	local result = {
		schemaVersion = data.SchemaVersion,
		wallet = data.Economy.Balance,
		slots = {},
		individuals = {},
		upgrades = {},
		complete = true,
		settledPlatformCash = 0,
	}
	for index = 1, 12 do
		local slot = assert(data.Base.Slots[tostring(index)], "Missing canonical slot")
		table.insert(
			result.slots,
			{ slot = index, individualId = slot.brainrotId, accumulatedCash = slot.accumulatedCash }
		)
		result.settledPlatformCash += slot.accumulatedCash
	end
	local ids = {}
	for id in data.Collection.BrainrotInstances do
		table.insert(ids, id)
	end
	table.sort(ids)
	result.individualCount = #ids
	result.individualDetailDrops = math.max(0, #ids - MAX_IDENTITIES)
	for index = 1, math.min(#ids, MAX_IDENTITIES) do
		local id = ids[index]
		table.insert(
			result.individuals,
			{ individualId = id, speciesId = data.Collection.BrainrotInstances[id].speciesId }
		)
	end
	local progression = data.Progression or {}
	local upgradeCount = 0
	for id, owned in progression.Upgrades or {} do
		upgradeCount += 1
		if
			upgradeCount <= MAX_IDENTITIES
			and (type(owned) == "boolean" or type(owned) == "number" or type(owned) == "string")
		then
			result.upgrades[id] = owned
		else
			result.complete = false
		end
	end
	result.complete = result.complete and result.individualDetailDrops == 0
	result.equippedCartId = progression.EquippedCartId
	result.equippedWeaponId = progression.EquippedWeaponId or progression.SelectedWeaponId
	return result
end

local function sanitizedReport(report)
	if not report then
		return nil
	end
	local result = clone(report)
	if result.coverage then
		result.coverage.exportedRecentDetailCount = #(result.coverage.recentDetails or {})
		result.coverage.recentDetails = nil -- exclude request/context identifiers
	end
	for _, offer in result.offers or {} do
		offer.purchaseRequestId = nil
	end
	if result.referenceNextAffordablePurchase then
		result.referenceNextAffordablePurchase.purchaseRequestId = nil
	end
	return result
end

local function envelope(name)
	return {
		evidence = "REAL_STUDIO_PLAYER_GAMEPLAY_OBSERVER",
		runId = runId,
		cohort = cohort,
		stage = stage,
		capture = name,
		capturedAt = Workspace:GetServerTimeNow(),
		installedAt = installedAt,
		loadedAt = loadedAt,
		worldReadyAt = worldReadyAt,
		cutoffTargetAt = cutoffTargetAt,
		observationId = observationId,
		generation = session and session.Generation,
		buildId = Environment.BuildId,
		measurementOperations = "READ_ONLY_NO_SETTLEMENT_SAVE_OR_GAMEPLAY_REQUESTS",
	}
end

local function current(player)
	return not stopped and target == player and session and Profile:IsCurrentSessionHandle(session)
end

local function backendCounters()
	local adapter = server:FindFirstChild("Phase7G1GameplayCohort")
	if not adapter then
		return nil
	end
	local result = {}
	for _, key in
		{
			"BackendAcquireCalls",
			"BackendSaveCalls",
			"BackendRenewCalls",
			"BackendReleaseCalls",
			"BackendNormalAccountForwarded",
		}
	do
		result[key] = adapter:GetAttribute(key)
	end
	return result
end

local function captureReport(name, requestSequence)
	assert(current(target), "Original live session is unavailable")
	-- No yields in this block. Full source clones are temporary equality inputs,
	-- never stored in attributes, retained between captures, or exported.
	local data = assert(Profile:GetReadableData(target), "Readable source unavailable")
	local before = clone(data)
	local beforeDiagnostic = Profile:GetDiagnostics(target)
	local beforeIncome = clone(Income:GetStateSnapshot(target))
	local beforeBackend = backendCounters()
	local first = assert(Metrics:GetReport(target), "Actual metrics report unavailable")
	local second = assert(Metrics:GetReport(target), "Repeated metrics report unavailable")
	local afterDiagnostic = Profile:GetDiagnostics(target)
	local afterIncome = clone(Income:GetStateSnapshot(target))
	local afterBackend = backendCounters()
	local unchanged = {
		fullSourceUnchanged = equal(before, Profile:GetReadableData(target)),
		profileRevisionUnchanged = beforeDiagnostic.currentRevision
			== afterDiagnostic.currentRevision,
		incomeSnapshotUnchanged = equal(beforeIncome, afterIncome),
		monetaryTotalsUnchanged = equal(first.economy, second.economy),
		backendCountersObserved = beforeBackend ~= nil and beforeBackend.BackendAcquireCalls ~= nil,
		backendCallsUnchanged = equal(beforeBackend, afterBackend),
	}
	-- latestAuthoritativeStateAt is observation metadata, so do not compare it as
	-- an economic mutation (the two calls can observe distinct server timestamps).
	local firstEconomy, secondEconomy = clone(first.economy), clone(second.economy)
	firstEconomy.latestAuthoritativeStateAt, secondEconomy.latestAuthoritativeStateAt = nil, nil
	unchanged.monetaryTotalsUnchanged = equal(firstEconomy, secondEconomy)
	unchanged.passed = unchanged.fullSourceUnchanged
		and unchanged.profileRevisionUnchanged
		and unchanged.incomeSnapshotUnchanged
		and unchanged.monetaryTotalsUnchanged
		and unchanged.backendCallsUnchanged
	observationId = second.session.observationId
	local evidence = envelope(name)
	evidence.playableElapsed = evidence.capturedAt
		- assert(second.session.clocks.worldReadyAt, "World-ready clock unavailable")
	evidence.source = sourceProjection(data)
	evidence.profileDiagnostics = afterDiagnostic
	evidence.income = afterIncome
	evidence.nonMutation = unchanged
	evidence.backendCounters = afterBackend
	evidence.requestSequence = requestSequence
	evidence.metrics = sanitizedReport(second)
	if evidence.income then
		evidence.income.UserId = nil
	end
	publish(name, evidence, name == "Snapshot")
	assert(unchanged.passed, "Report non-mutation comparison failed; evidence exported")
end

local function cleanup()
	if stopped then
		return
	end
	stopped = true
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, thread in tasks do
		if thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
	end
	table.clear(tasks)
	target, session = nil, nil
	script:SetAttribute("ObserverReady", false)
end

local function finish(receipt)
	if stopped then
		return
	end
	guarded("Closed", function()
		local evidence = envelope("Closed")
		evidence.terminal = receipt
		evidence.cutoffCaptured = cutoffCaptured
		evidence.diagnostics = diagnostics
		evidence.diagnosticDrops = diagnosticDrops
		for _, report in Metrics:GetCompletedReports() do
			if report.session.observationId == observationId then
				evidence.metrics = sanitizedReport(report)
				break
			end
		end
		evidence.completedMetricsObserved = evidence.metrics ~= nil
		publish("Closed", evidence)
		script:SetAttribute("ObserverStatus", "CLOSED")
	end)
	cleanup()
end

table.insert(
	connections,
	Profile:SubscribeDiagnostics(function(player, receipt)
		guarded("ProfileDiagnostic", function()
			local expected = script:GetAttribute("ExpectedUserId") -- adapter may bind it before Bootstrap
			if stopped or (expected ~= nil and player.UserId ~= expected) then
				return
			end
			if receipt.kind == "LoadCompleted" and target == nil then
				assert(
					player:IsA("Player")
						and player.Parent == Players
						and Players:GetPlayerByUserId(player.UserId) == player,
					"Genuine connected Player required"
				)
				target, session = player, assert(Profile:GetSessionHandle(player))
				loadedAt = Workspace:GetServerTimeNow()
				local evidence = envelope("Loaded")
				evidence.origin = receipt.profileOrigin
				evidence.isNew = receipt.isNew
				evidence.source = sourceProjection(assert(Profile:GetReadableData(player)))
				evidence.profileDiagnostics = Profile:GetDiagnostics(player)
				evidence.beforeProfileReadyListeners = true
				publish("Loaded", evidence)
				script:SetAttribute("ObserverStatus", "LOADED")
			end
			if not current(player) or receipt.generation ~= session.Generation then
				return
			end
			table.insert(diagnostics, {
				kind = receipt.kind,
				at = Workspace:GetServerTimeNow(),
				revision = receipt.revision,
				code = receipt.code,
				reason = receipt.reason,
			})
			if #diagnostics > 32 then
				table.remove(diagnostics, 1)
				diagnosticDrops += 1
			end
			if receipt.kind == "CloseStarted" then
				closing = true
				table.insert(
					tasks,
					task.delay(35, function()
						finish({ kind = "TERMINAL_NOT_OBSERVED_WITHIN_35_SECONDS" })
					end)
				)
			elseif receipt.kind == "CloseCompleted" or receipt.kind == "CloseUnconfirmed" then
				local terminal = {
					kind = receipt.kind,
					at = Workspace:GetServerTimeNow(),
					revision = receipt.revision,
					code = receipt.code,
				}
				print(
					"[PHASE7G1_OBSERVER_TERMINAL] run="
						.. runId
						.. " "
						.. HttpService:JSONEncode(terminal)
				)
				-- Metrics' diagnostic subscriber may run before OR after this callback.
				task.defer(function()
					finish(terminal)
				end)
			end
		end)
	end)
)

table.insert(
	connections,
	World:SubscribeReady(function(player)
		if not current(player) or ready or closing then
			return
		end
		task.defer(function()
			guarded("Ready", function()
				if not current(player) or ready or closing then
					return
				end
				local report = assert(Metrics:GetReport(player), "World-ready metrics unavailable")
				worldReadyAt =
					assert(report.session.clocks.worldReadyAt, "World readiness was not observed")
				observationId = report.session.observationId
				cutoffTargetAt = worldReadyAt + 600
				ready = true
				captureReport("Ready")
				script:SetAttribute("ObserverStatus", "OBSERVING")
				table.insert(
					tasks,
					task.delay(
						math.max(0, cutoffTargetAt - Workspace:GetServerTimeNow()),
						function()
							if not stopped and not closing then
								cutoffCaptured = guarded("Cutoff", function()
									captureReport("Cutoff")
								end)
								script:SetAttribute(
									"ObserverStatus",
									if cutoffCaptured then "CUTOFF_CAPTURED" else "ERROR"
								)
							end
						end
					)
				)
			end)
		end)
	end)
)

table.insert(
	connections,
	Workspace:GetAttributeChangedSignal("Phase7G1SnapshotRequest"):Connect(function()
		local sequence = Workspace:GetAttribute("Phase7G1SnapshotRequest")
		if
			stopped
			or not ready
			or closing
			or type(sequence) ~= "number"
			or sequence ~= sequence
			or sequence >= math.huge
			or sequence % 1 ~= 0
			or sequence <= lastSnapshotRequest
		then
			return
		end
		lastSnapshotRequest = sequence
		guarded("Snapshot", function()
			assert(snapshotRequests < 64, "On-demand snapshot request limit reached")
			snapshotRequests += 1
			captureReport("Snapshot", sequence)
		end)
	end)
)

table.insert(
	connections,
	Profile:RegisterCloseFinalizer(function(player)
		if not current(player) then
			return
		end
		guarded("FinalSource", function()
			-- Existing coordinator has already run its authorized final settlement.
			-- Metrics may already be detached; never depend on finalizer ordering.
			local evidence = envelope("FinalSource")
			evidence.source = sourceProjection(assert(Profile:GetReadableData(player)))
			evidence.profileDiagnostics = Profile:GetDiagnostics(player)
			evidence.afterAuthorizedSettlement = true
			publish("FinalSource", evidence)
		end)
	end)
)

table.insert(connections, script.Destroying:Connect(cleanup))
table.insert(
	tasks,
	task.delay(1200, function()
		finish({ kind = "OBSERVER_LIFETIME_LIMIT_1200_SECONDS" })
	end)
)
script:SetAttribute("ObserverStatus", "ARMED_BEFORE_LOAD")
script:SetAttribute("ObserverReady", true)
