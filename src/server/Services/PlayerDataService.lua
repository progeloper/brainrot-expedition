--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Config = require(script.Parent.Parent.Config.PlayerDataConfig)
local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
local ProfileKey = require(script.Parent.Parent.Utility.PlayerProfileKey)
local ProfileStore = require(script.Parent.Parent.Data.PlayerProfileStore)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local VFXSettings = require(ReplicatedStorage.Shared.Utility.VFXSettingsProtocol)
local Phase13Rules = require(ReplicatedStorage.Shared.Utility.Phase13Rules)

local log = Logger.new("PlayerDataService")

local PlayerDataService = {}

local started = false
local shuttingDown = false
local backend: any = nil
local dependencies: any = nil
local sessions: { [Player]: any } = {}
local currentByUserId: { [number]: any } = {}
local generationsByUserId: { [number]: number } = {}
local readyListeners: { [any]: (Player) -> () } = {}
local saveConfirmedListeners: { [any]: (Player, number, number) -> () } = {}
local diagnosticListeners: { [any]: (Player, any) -> () } = {}
local closeFinalizers: { [any]: (Player) -> () } = {}
local closeRequestedListeners: { [any]: (Player, string) -> () } = {}
local sessionRecoveredListeners: { [any]: (Player, Player, any, any) -> boolean? } = {}
local recoveryAcquisitions: { [number]: any } = {}
local departurePreparers: { [any]: (Player, string) -> (boolean?, string?) } = {}
local snapshotPreparers: { [any]: (Player, number) -> (boolean?, string?) } = {}
local connections: { any } = {}
local schedulerAccumulator = 0
local settingsRemote: RemoteFunction? = nil
local settingsHandler: any = nil

local function monotonicNow(): number
	return if dependencies and dependencies.MonotonicNow then dependencies.MonotonicNow() else os.clock()
end

local function unixNow(): number
	return if dependencies and dependencies.UnixNow
		then dependencies.UnixNow()
		else DateTime.now().UnixTimestampMillis / 1000
end

local function waitSeconds(seconds: number)
	if dependencies and dependencies.Wait then
		dependencies.Wait(seconds)
	else
		task.wait(seconds)
	end
end

local function operationId(prefix: string): string
	if dependencies and dependencies.GenerateOperationId then
		return dependencies.GenerateOperationId(prefix)
	end
	return prefix .. ":" .. game.JobId .. ":" .. HttpService:GenerateGUID(false)
end

local function retryDelay(attempt: number): number
	local base = Config.RetryDelaysSeconds[math.min(attempt, #Config.RetryDelaysSeconds)] or 0
	local jitter = 0
	if Config.RetryJitterSeconds > 0 then
		local randomValue = if dependencies and dependencies.Random then dependencies.Random() else math.random()
		jitter = randomValue * Config.RetryJitterSeconds
	end
	return base + jitter
end

local function setAttribute(player: Player, name: string, value: any)
	pcall(function()
		player:SetAttribute(name, value)
	end)
end

local function publishVFXSettings(player: Player, data: any)
	local settings = VFXSettings.Read(data.Settings)
	setAttribute(player, "VFXQuality", settings.VFXQuality)
	setAttribute(player, "ReducedMotion", settings.ReducedMotion)
end

local function exactSession(player: Player): any?
	local session = sessions[player]
	return if session
			and session.Player == player
			and currentByUserId[session.UserId] == session
			and generationsByUserId[session.UserId] == session.Generation
		then session
		else nil
end

local function publishStatus(session: any, status: string)
	session.Status = status
	setAttribute(session.Player, "PlayerDataStatus", status)
end

local function ownerStillSafe(session: any): boolean
	return type(session.LeaseExpiresAt) == "number"
		and unixNow() < session.LeaseExpiresAt - Config.LeaseSafetyMarginSeconds
end

-- Profile-domain owners keep stable references to parts of the loaded profile
-- (for example Base.Slots). Roll a failed synchronous mutation back in place so
-- those bindings remain current instead of swapping the profile root/table.
local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, nested in value do
		copy[key] = cloneTable(nested)
	end
	return copy
end

local function restoreTableInPlace(target: any, snapshot: any)
	for key in target do
		if snapshot[key] == nil then
			target[key] = nil
		end
	end
	for key, savedValue in snapshot do
		local currentValue = target[key]
		if type(savedValue) == "table" and type(currentValue) == "table" then
			restoreTableInPlace(currentValue, savedValue)
		else
			target[key] = cloneTable(savedValue)
		end
	end
end

local function writableSession(player: Player): (any?, string?)
	local session = exactSession(player)
	if not session or session.Status ~= "Ready" or session.Closing then
		return nil, "PROFILE_NOT_READY"
	end
	if session.CriticalOperation and not session.CriticalMutationOwner then
		return nil, "CRITICAL_TRANSACTION_PENDING"
	end
	if session.MutationInProgress then
		return nil, "MUTATION_IN_PROGRESS"
	end
	-- PlayerRemoving may detach the Player before the close callback's authorized
	-- departure preparers run. CloseInProgress scopes this exception to the exact
	-- current session and only to the bounded pre-snapshot departure transition;
	-- ordinary mutations from a disconnected player remain rejected.
	if player.Parent ~= Players and not session.CloseInProgress then
		return nil, "PLAYER_NOT_CONNECTED"
	end
	if not ownerStillSafe(session) then
		return nil, "SESSION_OWNERSHIP_UNSAFE"
	end
	return session, nil
end

local function notifyReady(player: Player)
	for _, callback in readyListeners do
		local ok, failure = pcall(callback, player)
		if not ok then
			log:Warn("Profile-ready listener failed for UserId=%d: %s", player.UserId, tostring(failure))
		end
	end
end

local function notifyDiagnostic(session: any, kind: string, fields: any?)
	local receipt = {
		kind = kind,
		at = monotonicNow(),
		generation = session.Generation,
		currentRevision = session.Revision,
		savedRevision = session.SavedRevision,
	}
	for key, value in fields or {} do
		receipt[key] = value
	end
	table.freeze(receipt)
	for _, callback in diagnosticListeners do
		local ok, failure = pcall(callback, session.Player, receipt)
		if not ok then
			log:Warn("Profile diagnostic listener failed for UserId=%d: %s", session.UserId, tostring(failure))
		end
	end
end

local function notifySaveConfirmed(session: any)
	notifyDiagnostic(session, "SaveConfirmed", {
		eventId = string.format("%d:%d:confirmed:%d", session.Generation, session.SavedRevision, session.Revision),
		revision = session.SavedRevision,
	})
	for _, callback in saveConfirmedListeners do
		local ok, failure = pcall(callback, session.Player, session.SavedRevision, session.Revision)
		if not ok then
			log:Warn("Profile save-confirmed listener failed for UserId=%d: %s", session.UserId, tostring(failure))
		end
	end
end

local function failSession(session: any, code: string, playerMessage: string?)
	if exactSession(session.Player) ~= session then
		return
	end
	session.Closing = true
	session.FailureCode = code
	publishStatus(session, "Failed")
	setAttribute(session.Player, "PlayerDataWritable", false)
	log:Warn(
		"ProfileLoadRejected environment=%s userId=%d generation=%d code=%s",
		Environment.Name,
		session.UserId,
		session.Generation,
		code
	)
	notifyDiagnostic(session, "LoadRejected", {
		eventId = string.format("%d:load-rejected:%s", session.Generation, code),
		code = code,
	})
	if playerMessage and (not dependencies or dependencies.KickOnFailure ~= false) then
		pcall(function()
			session.Player:Kick(playerMessage)
		end)
	end
end

local function abandonAcquiredSession(session: any, acquisition: any)
	if not acquisition or acquisition.ok ~= true then
		return
	end
	local snapshot = acquisition.data
	if not snapshot then
		return
	end
	local release = backend:Release(
		session.Key,
		session.OwnerToken,
		operationId("abandoned-load"),
		acquisition.lastRevision or 0,
		snapshot
	)
	if not release.ok then
		log:Warn(
			"ProfileCloseUnconfirmed environment=%s userId=%d generation=%d code=%s",
			Environment.Name,
			session.UserId,
			session.Generation,
			tostring(release.code)
		)
	end
end

function PlayerDataService:Init(options: any?): boolean
	if started then
		return false
	end
	dependencies = options or {}
	backend = dependencies.Backend or ProfileStore.new(dependencies.StoreOptions)
	return true
end

local function publishReadySession(session: any, acquisition: any): any
	local player = session.Player
	publishVFXSettings(player, session.Data)
	publishStatus(session, "Ready")
	setAttribute(player, "PlayerDataWritable", true)
	setAttribute(player, "Cash", session.Data.Economy.Balance)
	log:Info(
		"ProfileReady environment=%s userId=%d generation=%d revision=%d isNew=%s",
		Environment.Name,
		session.UserId,
		session.Generation,
		session.Revision,
		tostring(acquisition.isNew == true)
	)
	notifyDiagnostic(session, "LoadCompleted", {
		eventId = string.format("%d:load-completed", session.Generation),
		isNew = acquisition.isNew == true,
		profileOrigin = session.ProfileOrigin,
		migrated = acquisition.migrated == true,
	})
	local transition = table.clone(acquisition.migrationSummary or {})
	transition.currencyVersion = session.Data.CurrencyVersion
	transition.currencyTo = session.Data.CurrencyVersion
	transition.monetaryFieldCount = transition.monetaryFieldCount or 0
	notifyDiagnostic(session, "CurrencyMigrationConfirmed", transition)
	if transition.legacyRegions and transition.legacyRegions ~= "" then
		notifyDiagnostic(session, "LegacyGrantCompleted", {
			legacyRegions = transition.legacyRegions,
			legacyGrantVersion = session.Data.WorldProgression.LegacyGrantVersion,
		})
	end
	if player.Parent == Players then
		notifyReady(player)
	end
	return { ok = true, code = "READY", isNew = acquisition.isNew == true, migrated = acquisition.migrated == true }
end

local function frozenSnapshot(data: any): any
	local copy = cloneTable(data)
	local function freeze(value: any)
		if type(value) == "table" then
			for _, nested in value do
				freeze(nested)
			end
			table.freeze(value)
		end
	end
	freeze(copy)
	return copy
end

local function reconcileRecoveredSession(session: any): boolean
	local recovery = session.Recovery
	if not recovery or recovery.InProgress or exactSession(session.Player) ~= session then
		return false
	end
	recovery.InProgress = true
	if not recovery.FinalizedPrevious then
		-- Finish exact old-player runtime observers before any domain rebinds
		-- canonical survivors to the new Player. Departure mutators are excluded.
		for _, displaced in recovery.Participants do
			displaced.RecoveryFinalizersDone = displaced.RecoveryFinalizersDone or {}
			for key, callback in closeFinalizers do
				if not displaced.RecoveryFinalizersDone[key] then
					local ok, failure = pcall(callback, displaced.Player)
					if not ok then
						recovery.InProgress = false
						log:Warn("Recovered session finalizer failed: %s", tostring(failure))
						return false
					end
					displaced.RecoveryFinalizersDone[key] = true
				end
			end
		end
		recovery.FinalizedPrevious = true
	end
	local allReconciled = true
	for key, callback in sessionRecoveredListeners do
		recovery.Completed[key] = recovery.Completed[key] or {}
		for _, displaced in recovery.Participants do
			if not recovery.Completed[key][displaced.Player] then
				local ok, result =
					pcall(callback, displaced.Player, session.Player, recovery.Canonical, recovery.PreviousData)
				if not ok or result == false then
					-- Other observers may resolve this one's dependency (for example
					-- PendingBank before old-cart disposal). Never starve them based
					-- on hash-table listener iteration order.
					allReconciled = false
				else
					recovery.Completed[key][displaced.Player] = true
				end
			end
		end
	end
	if not allReconciled then
		recovery.InProgress = false
		return false
	end
	-- Never save the old uncertain snapshot or run its departure mutators
	-- against the newly acquired canonical profile.
	for _, displaced in recovery.Participants do
		sessions[displaced.Player] = nil
		displaced.CriticalOperation = nil
		publishStatus(displaced, "Closed")
		setAttribute(displaced.Player, "Cash", nil)
	end
	recoveryAcquisitions[session.UserId] = nil
	session.Recovery = nil
	notifyDiagnostic(session, "SessionRecovered", {
		eventId = string.format("%d:session-recovered", session.Generation),
		outcome = "CanonicalReconciled",
	})
	publishReadySession(session, recovery.Acquisition)
	if session.Player.Parent ~= Players then
		session.DeferredCloseReason = session.DeferredCloseReason or "RecoveredDeparture"
	end
	return true
end

function PlayerDataService:RecoverFailedSessionAsync(player: Player, previous: any): any
	if
		currentByUserId[player.UserId] ~= previous
		or previous.Player.Parent == Players
		or previous.Status ~= "Failed"
		or (not previous.CriticalOperation and not previous.Recovery)
		or (
			previous.FailureCode ~= "LEASE_SAFETY_DEADLINE"
			and previous.FailureCode ~= "OWNER_MISMATCH"
			and previous.FailureCode ~= "STALE_REVISION"
		)
	then
		return { ok = false, code = "DUPLICATE_USER_SESSION" }
	end
	local recovery = recoveryAcquisitions[player.UserId]
	if recovery and recovery.InFlight then
		return { ok = false, code = "RECOVERY_ACQUIRE_BUSY" }
	end
	if not recovery or recovery.Previous ~= previous then
		recovery = { Previous = previous, OwnerToken = operationId("recovery-owner") }
		recoveryAcquisitions[player.UserId] = recovery
	end
	recovery.InFlight = true
	local beganAt, acquisition = monotonicNow(), nil
	for attempt = 1, Config.AttemptsPerBatch do
		acquisition = backend:Acquire(previous.Key, recovery.OwnerToken, Config.LeaseDurationSeconds)
		if type(acquisition) == "table" and acquisition.ok == true then
			break
		end
		local code = if type(acquisition) == "table" then acquisition.code else "ACQUIRE_FAILED"
		if code ~= "ACQUIRE_FAILED" or attempt == Config.AttemptsPerBatch then
			break
		end
		if player.Parent ~= Players or shuttingDown or currentByUserId[player.UserId] ~= previous then
			break
		end
		local remaining = Config.LoadDeadlineSeconds - (monotonicNow() - beganAt)
		if remaining <= 0 then
			break
		end
		waitSeconds(math.min(retryDelay(attempt), remaining))
	end
	recovery.InFlight = false
	if type(acquisition) ~= "table" or not acquisition.ok then
		return { ok = false, code = if type(acquisition) == "table" then acquisition.code else "ACQUIRE_FAILED" }
	end
	local generation = (generationsByUserId[player.UserId] or 0) + 1
	local session = {
		Player = player,
		UserId = player.UserId,
		Generation = generation,
		Key = previous.Key,
		OwnerToken = recovery.OwnerToken,
		Status = "Recovering",
		Closing = false,
		Revision = acquisition.lastRevision or 0,
		SavedRevision = acquisition.lastRevision or 0,
		SaveInFlight = false,
		SaveRequested = false,
		SaveWarning = false,
		Data = acquisition.data,
		SaveEnvelope = acquisition.saveEnvelope,
		LeaseExpiresAt = acquisition.leaseExpiresAt,
		NextSaveAt = unixNow() + Config.AutosaveIntervalSeconds,
		ProfileOrigin = "Existing",
	}
	local valid, reason = Schema.ValidateLoaded(session.Data)
	if
		not valid
		or player.Parent ~= Players
		or shuttingDown
		or currentByUserId[player.UserId] ~= previous
		or monotonicNow() - beganAt > Config.LoadDeadlineSeconds
	then
		abandonAcquiredSession(session, acquisition)
		return { ok = false, code = reason or "LOAD_CANCELLED" }
	end
	-- The previous session remains authoritative/fenced until this successful
	-- Acquire. All old generation handles become stale before source cleanup.
	generationsByUserId[player.UserId] = generation
	currentByUserId[player.UserId] = session
	sessions[player] = session
	local original = if previous.Recovery then previous.Recovery.Previous else previous
	local beforeCritical = original.CriticalOperation and original.CriticalOperation.Before
	local participants = if previous.Recovery then table.clone(previous.Recovery.Participants) else {}
	table.insert(participants, previous)
	session.Recovery = {
		Previous = original,
		Participants = participants,
		Canonical = frozenSnapshot(session.Data),
		PreviousData = frozenSnapshot(beforeCritical or original.Data),
		Completed = {},
		Acquisition = acquisition,
	}
	publishStatus(session, "Recovering")
	setAttribute(player, "PlayerDataWritable", false)
	setAttribute(player, "Cash", nil)
	if reconcileRecoveredSession(session) then
		return { ok = true, code = "READY", recovered = true }
	end
	return { ok = false, code = "RECOVERY_RECONCILIATION_PENDING" }
end

function PlayerDataService:LoadPlayerAsync(player: Player): any
	local existing = exactSession(player)
	if existing then
		return { ok = existing.Status == "Ready", code = existing.Status }
	end
	if shuttingDown or player.Parent ~= Players then
		return { ok = false, code = "LOAD_CANCELLED" }
	end
	local userId = player.UserId
	local profileKey, keyError = ProfileKey.Resolve(
		userId,
		Config.KeyPrefix,
		ProfileKey.StudioNamespace(
			game:GetService("ServerStorage"):GetAttribute("Phase8TestProfileNamespace"),
			RunService:IsStudio() and Environment.IsProduction
		),
		RunService:IsStudio(),
		Environment.IsProduction,
		Environment.MainGameplayEnabled
	)
	if not profileKey then
		return { ok = false, code = keyError }
	end
	if currentByUserId[userId] ~= nil then
		return self:RecoverFailedSessionAsync(player, currentByUserId[userId])
	end
	local generation = (generationsByUserId[userId] or 0) + 1
	generationsByUserId[userId] = generation
	local session = {
		Player = player,
		UserId = userId,
		Generation = generation,
		Key = profileKey,
		OwnerToken = operationId("owner"),
		Status = "Loading",
		Closing = false,
		Revision = 0,
		SavedRevision = 0,
		SaveInFlight = false,
		SaveRequested = false,
		SaveWarning = false,
		Data = nil,
		LeaseExpiresAt = 0,
		NextSaveAt = 0,
		CloseResult = nil,
		ProfileOrigin = "UnknownOrigin",
	}
	sessions[player] = session
	currentByUserId[userId] = session
	publishStatus(session, "Loading")
	setAttribute(player, "PlayerDataWritable", false)
	setAttribute(player, "Cash", nil)
	log:Info("ProfileLoadStarted environment=%s userId=%d generation=%d", Environment.Name, userId, generation)
	notifyDiagnostic(session, "LoadStarted", {
		eventId = string.format("%d:load-started", generation),
	})
	notifyDiagnostic(session, "CurrencyMigrationStarted", { currencyTo = 2 })

	local beganAt = monotonicNow()
	local acquisition = nil
	for attempt = 1, Config.AttemptsPerBatch do
		acquisition = backend:Acquire(session.Key, session.OwnerToken, Config.LeaseDurationSeconds)
		if type(acquisition) == "table" and acquisition.ok == true then
			break
		end
		local code = if type(acquisition) == "table" then acquisition.code else nil
		if code ~= "ACQUIRE_FAILED" or attempt >= Config.AttemptsPerBatch then
			break
		end
		if exactSession(player) ~= session or session.Closing or shuttingDown or player.Parent ~= Players then
			break
		end
		local remaining = Config.LoadDeadlineSeconds - (monotonicNow() - beganAt)
		if remaining <= 0 then
			break
		end
		log:Warn(
			"ProfileLoadRetry environment=%s userId=%d generation=%d attempt=%d code=%s",
			Environment.Name,
			userId,
			generation,
			attempt,
			tostring(code)
		)
		notifyDiagnostic(session, "LoadRetry", {
			eventId = string.format("%d:load-retry:%d", generation, attempt),
			attempt = attempt,
			code = code,
		})
		waitSeconds(math.min(retryDelay(attempt), remaining))
	end
	local current = exactSession(player)
	if
		current ~= session
		or session.Closing
		or shuttingDown
		or player.Parent ~= Players
		or monotonicNow() - beganAt > Config.LoadDeadlineSeconds
	then
		abandonAcquiredSession(session, acquisition)
		if current == session then
			sessions[player] = nil
			currentByUserId[userId] = nil
		end
		return { ok = false, code = "LOAD_CANCELLED" }
	end
	if type(acquisition) ~= "table" or acquisition.ok ~= true then
		local code = if type(acquisition) == "table" then acquisition.code else "ACQUIRE_FAILED"
		notifyDiagnostic(session, "CurrencyMigrationFailed", { code = code, currencyTo = 2 })
		failSession(session, tostring(code), "Your data could not be loaded safely. Please rejoin.")
		return { ok = false, code = code }
	end
	local valid, reason = Schema.ValidateLoaded(acquisition.data)
	if not valid then
		abandonAcquiredSession(session, acquisition)
		failSession(session, reason or "INVALID_PROFILE", "Your data could not be loaded safely. Please rejoin.")
		return { ok = false, code = reason or "INVALID_PROFILE" }
	end
	session.Data = acquisition.data
	session.SaveEnvelope = acquisition.saveEnvelope
	session.ProfileOrigin = if acquisition.isNew == true then "ConfirmedNew" else "Existing"
	session.Revision = acquisition.lastRevision or 0
	session.SavedRevision = session.Revision
	session.LeaseExpiresAt = acquisition.leaseExpiresAt
	session.NextSaveAt = unixNow()
		+ Config.AutosaveIntervalSeconds
		+ (userId % 1000) / 1000 * Config.AutosaveStaggerSeconds
	return publishReadySession(session, acquisition)
end

function PlayerDataService:GetStatus(player: Player): string
	local session = exactSession(player)
	return if session then session.Status else "Closed"
end

-- Compact server-only identity used by reconstruction callbacks. It contains no
-- profile data or backend token and cannot be used to acquire ownership.
function PlayerDataService:GetSessionHandle(player: Player): any?
	local session = exactSession(player)
	if not session then
		return nil
	end
	return table.freeze({
		Player = player,
		UserId = session.UserId,
		Generation = session.Generation,
	})
end

function PlayerDataService:IsCurrentSessionHandle(handle: any): boolean
	if type(handle) ~= "table" then
		return false
	end
	local player = handle.Player
	local session = if player ~= nil then exactSession(player) else nil
	return session ~= nil and session.UserId == handle.UserId and session.Generation == handle.Generation
end

function PlayerDataService:IsWritable(player: Player): boolean
	return writableSession(player) ~= nil
end

function PlayerDataService:GetReadableData(player: Player): (any?, string?)
	local session = exactSession(player)
	if
		not session or (session.Status ~= "Ready" and session.Status ~= "Closing" and session.Status ~= "Recovering")
	then
		return nil, "PROFILE_NOT_READY"
	end
	return session.Data, nil
end

-- Trusted server-only read. The exact acquired envelope extensions are retained;
-- generated save-id/time growth is separately reserved by commerce admission.
function PlayerDataService:GetSaveEnvelope(player: Player, snapshot: any, revision: number): any?
	local session = exactSession(player)
	if not session or not session.SaveEnvelope then
		return nil
	end
	return ProfileStore.ProjectSaveEnvelope(
		session.SaveEnvelope,
		snapshot,
		session.OwnerToken,
		"save:projection",
		revision,
		unixNow() + Config.LeaseDurationSeconds
	)
end

function PlayerDataService:GetWritableData(player: Player): (any?, string?)
	local session, reason = writableSession(player)
	return if session then session.Data else nil, reason
end

-- One narrow owner-scoped cosmetic settings protocol. Requests never accept a
-- player/profile key or gameplay field, and never wait for profile readiness.
function PlayerDataService:HandleVFXSettingsRequest(player: Player, payload: any, ...: any): any
	if select("#", ...) > 0 then
		return { ok = false, code = "INVALID_REQUEST" }
	end
	local request, requestReason = VFXSettings.ValidateRequest(payload)
	if not request then
		return { ok = false, code = requestReason or "INVALID_REQUEST" }
	end
	local session, reason = writableSession(player)
	if not session then
		return { ok = false, code = reason or "PROFILE_NOT_READY" }
	end
	local previous = VFXSettings.Read(session.Data.Settings)
	local function response(ok: boolean, code: string, revision: number?): any
		local value = VFXSettings.Read(session.Data.Settings)
		return {
			ok = ok,
			code = code,
			VFXQuality = value.VFXQuality,
			ReducedMotion = value.ReducedMotion,
			revision = revision,
			-- A session commit is not backend confirmation. The existing profile
			-- autosave/close owner remains the only persistence scheduler.
			persistence = "ProfileAutosave",
		}
	end
	if request.action == "Get" then
		return response(true, "Ready", session.Revision)
	end
	if session.Data.Settings ~= nil and type(session.Data.Settings) ~= "table" then
		return response(false, "PREFERENCES_UNAVAILABLE", nil)
	end
	local changed = (request.VFXQuality ~= nil and request.VFXQuality ~= previous.VFXQuality)
		or (request.ReducedMotion ~= nil and request.ReducedMotion ~= previous.ReducedMotion)
	if not changed then
		return response(true, "Unchanged", session.Revision)
	end
	local now = monotonicNow()
	if session.VFXSettingsLastRequestAt and now - session.VFXSettingsLastRequestAt < 0.2 then
		local limited = response(false, "RATE_LIMITED", nil)
		limited.retryAfterSeconds = math.max(0, 0.2 - (now - session.VFXSettingsLastRequestAt))
		return limited
	end
	session.VFXSettingsLastRequestAt = now
	local outcome = self:CommitMutation(player, function(data)
		local applied, applyReason = VFXSettings.Apply(data, request)
		return applied, { ok = applied, code = applyReason or "Applied" }
	end)
	if outcome.ok then
		publishVFXSettings(player, session.Data)
	end
	return response(outcome.ok == true, outcome.code or "SETTINGS_UNAVAILABLE", outcome.revision)
end

function PlayerDataService:MarkDirty(player: Player): (number?, string?)
	local session, reason = writableSession(player)
	if not session then
		return nil, reason
	end
	if session.Revision >= Config.MaxBalance then
		return nil, "REVISION_OVERFLOW"
	end
	session.Revision += 1
	return session.Revision, nil
end

-- Trusted server-only boundary for one synchronous profile-domain change. The
-- callback must not yield and must mutate only the supplied current profile.
local TeamRules = require(game.ReplicatedStorage.Shared.Utility.ChariotTeamRules)
local mutationListeners = {}
function PlayerDataService:SubscribeMutations(callback)
	local key = {}
	mutationListeners[key] = callback
	return {
		Disconnect = function()
			mutationListeners[key] = nil
		end,
	}
end

-- Both inputs have passed schema validation: no cyclic/Instance values.
local function sameSavedValue(left: any, right: any): boolean
	if type(left) ~= "table" or type(right) ~= "table" then
		return left == right
	end
	for key, value in left do
		if not sameSavedValue(value, right[key]) then return false end
	end
	for key in right do
		if left[key] == nil then return false end
	end
	return true
end
local function preservesUnavailableSlots(before: any, after: any): boolean
	for index = Phase13Rules.GetCapacity(before) + 1, 48 do
		local key = tostring(index)
		local prior, current = before.Base.Slots[key], after.Base.Slots[key]
		if not sameSavedValue(prior, current) then return false end
		local id = prior.brainrotId
		if id ~= nil and not sameSavedValue(before.Collection.BrainrotInstances[id], after.Collection.BrainrotInstances[id]) then
			return false
		end
	end
	return true
end

function PlayerDataService:CommitMutation(player: Player, callback: (any) -> (boolean, any)): any
	local session, reason = writableSession(player)
	if not session then
		return { ok = false, code = reason or "PROFILE_NOT_READY" }
	end
	if session.Revision >= Config.MaxBalance then
		return { ok = false, code = "REVISION_OVERFLOW" }
	end
	local beforeMutation, snapshotReason = Schema.CreateSaveSnapshot(session.Data)
	if not beforeMutation then
		return { ok = false, code = snapshotReason or "INVALID_PROFILE" }
	end
	session.MutationInProgress = true
	local function finishMutation(outcome: any): any
		session.MutationInProgress = false
		return outcome
	end
	local called, committed, result = pcall(callback, session.Data)
	if not called then
		restoreTableInPlace(session.Data, beforeMutation)
		return finishMutation({ ok = false, code = "MUTATION_ERROR", error = tostring(committed) })
	end
	if committed ~= true then
		restoreTableInPlace(session.Data, beforeMutation)
		return finishMutation(if type(result) == "table" then result else { ok = false, code = result or "REJECTED" })
	end
	if exactSession(player) ~= session or session.Status ~= "Ready" or session.Closing then
		restoreTableInPlace(session.Data, beforeMutation)
		return finishMutation({ ok = false, code = "SESSION_CHANGED" })
	end
	if Phase13Rules.ShouldInvalidate(beforeMutation, session.Data) then
		session.Data.Phase13.EligibilityRevision += 1
	end
	-- Clear references inside the successful ownership/location transaction.
	TeamRules.ClearRemoved(session.Data, beforeMutation)
	local valid, validationReason = Schema.ValidateLoaded(session.Data)
	if session.Data.CurrencyVersion ~= 2 or session.Data.CurrencyVersion ~= beforeMutation.CurrencyVersion then
		valid, validationReason = false, "UNSUPPORTED_WRITE_CURRENCY"
	end
	if valid and not preservesUnavailableSlots(beforeMutation, session.Data) then
		valid, validationReason = false, "UNAVAILABLE_SLOT_MUTATION"
	end
	if not valid then
		restoreTableInPlace(session.Data, beforeMutation)
		return finishMutation({
			ok = false,
			code = "INVALID_PROFILE_MUTATION",
			reason = validationReason or "INVALID_PROFILE",
		})
	end
	session.Revision += 1
	if not session.CriticalOperation then
		session.OrdinarySaveAt = session.OrdinarySaveAt or (unixNow() + 5)
	end
	if type(result) ~= "table" then
		result = { ok = true, code = "Applied" }
	end
	result.ok = true
	result.committed = true
	result.revision = session.Revision
	local discarded = 0
	for key, priorSlot in beforeMutation.Base.Slots do
		local nextSlot = session.Data.Base.Slots[key]
		if priorSlot.brainrotId ~= nil and priorSlot.brainrotId ~= nextSlot.brainrotId then
			discarded += math.max(0, priorSlot.accumulatedCash - nextSlot.accumulatedCash)
		end
	end
	-- Occupant changes can settle accrued cash into the wallet. Observe only a
	-- proven net loss, rather than reporting that internal transfer as a sink.
	if discarded > 0 then
		local cashBefore = Phase13Rules.Cash(beforeMutation)
		local cashAfter = Phase13Rules.Cash(session.Data)
		if cashBefore and cashAfter then
			local cashLoss = math.max(0, cashBefore - cashAfter)
			discarded = math.min(discarded, cashLoss)
			local critical = session.CriticalOperation
			local receipt = critical and session.Data.Phase13.Operations[critical.OperationId]
			if
				receipt
				and receipt.Kind == "Rebirth"
				and receipt.CommitRevision == result.revision
				and receipt.Result.route == "Cash"
				and receipt.Result.sacrificedCash == cashLoss
			then
				-- Its exact durable receipt owns the cash-rebirth sink once confirmed.
				discarded = 0
			end
		end
	end
	finishMutation(result)
	for _, observer in mutationListeners do
		local ok, failure = pcall(observer, player, beforeMutation, session.Data)
		if not ok then
			warn("[Phase9] Mutation observer failed: " .. tostring(failure))
		end
	end
	if discarded > 0 then
		-- Observe the already-committed boundary, outside the mutation guard. This
		-- is a platform loss, never a wallet credit or newly generated income.
		notifyDiagnostic(session, "PlatformCashDiscarded", {
			amount = discarded,
			signedAmount = -discarded,
			revision = result.revision,
			eventId = "platform-discard:" .. tostring(result.revision),
			source = "OccupantRemoved",
		})
	end
	return result
end

function PlayerDataService:BeginClosing(player: Player): boolean
	local session = exactSession(player)
	if not session or session.Closing then
		return session ~= nil
	end
	session.Closing = true
	publishStatus(session, "Closing")
	setAttribute(player, "PlayerDataWritable", false)
	return true
end

local function applyOwnershipFailure(session: any, code: string)
	if exactSession(session.Player) ~= session then
		return
	end
	session.Closing = true
	session.FailureCode = code
	publishStatus(session, "Failed")
	setAttribute(session.Player, "PlayerDataWritable", false)
	log:Warn(
		"ProfileSessionLost environment=%s userId=%d generation=%d code=%s revision=%d savedRevision=%d",
		Environment.Name,
		session.UserId,
		session.Generation,
		code,
		session.Revision,
		session.SavedRevision
	)
	notifyDiagnostic(session, "SessionLost", {
		eventId = string.format("%d:session-lost:%s", session.Generation, code),
		code = code,
	})
	if not dependencies or dependencies.KickOnFailure ~= false then
		pcall(function()
			session.Player:Kick("This data session has ended. Please rejoin.")
		end)
	end
end

local function prepareSnapshot(session: any, at: number): (boolean, string?)
	for _, callback in snapshotPreparers do
		local called, changed, reason = pcall(callback, session.Player, at)
		if not called then
			return false, "SNAPSHOT_PREPARER_ERROR"
		end
		if changed == nil and reason ~= nil then
			return false, reason
		end
		if changed == true then
			if session.Revision >= Config.MaxBalance then
				return false, "REVISION_OVERFLOW"
			end
			session.Revision += 1
		end
	end
	return true, nil
end

local function saveSnapshot(session: any, reason: string): any
	local prepared, prepareReason = prepareSnapshot(session, unixNow())
	if not prepared then
		log:Warn(
			"ProfileSnapshotPreparationFailed environment=%s userId=%d generation=%d code=%s",
			Environment.Name,
			session.UserId,
			session.Generation,
			tostring(prepareReason or "SNAPSHOT_PREPARATION_FAILED")
		)
		return { ok = false, code = prepareReason or "SNAPSHOT_PREPARATION_FAILED" }
	end
	local snapshot, snapshotReason = Schema.CreateSaveSnapshot(session.Data)
	if not snapshot then
		applyOwnershipFailure(session, snapshotReason or "INVALID_PROFILE")
		return { ok = false, code = snapshotReason or "INVALID_PROFILE" }
	end
	local revision = session.Revision
	local saveOperationId = operationId("save")
	log:Debug(
		"ProfileSaveStarted environment=%s userId=%d generation=%d revision=%d reason=%s",
		Environment.Name,
		session.UserId,
		session.Generation,
		revision,
		reason
	)
	notifyDiagnostic(session, "SaveStarted", {
		eventId = saveOperationId,
		revision = revision,
		reason = reason,
	})
	local lastResult = nil
	for attempt = 1, Config.AttemptsPerBatch do
		if exactSession(session.Player) ~= session or session.Status == "Closed" then
			return { ok = false, code = "SESSION_CHANGED" }
		end
		if not ownerStillSafe(session) then
			applyOwnershipFailure(session, "LEASE_SAFETY_DEADLINE")
			return { ok = false, code = "LEASE_SAFETY_DEADLINE" }
		end
		lastResult = backend:Save(
			session.Key,
			session.OwnerToken,
			saveOperationId,
			revision,
			snapshot,
			Config.LeaseDurationSeconds
		)
		-- Passive accounting includes the terminal failed attempt, which has no
		-- SaveRetry event. The scalar sequence deduplicates observer replay per generation.
		session.SaveAttemptSequence = (session.SaveAttemptSequence or 0) + 1
		notifyDiagnostic(session, "SaveAttemptCompleted", {
			eventId = saveOperationId .. ":attempt:" .. tostring(attempt),
			attemptSequence = session.SaveAttemptSequence,
			attempt = attempt,
			revision = revision,
			ok = lastResult.ok == true,
			uncertain = lastResult.uncertain == true or lastResult.code == "SAVE_UNCERTAIN",
			code = lastResult.code,
		})
		if exactSession(session.Player) ~= session then
			return { ok = false, code = "SESSION_CHANGED" }
		end
		if lastResult.ok then
			session.SavedRevision = math.max(session.SavedRevision, revision)
			session.LeaseExpiresAt = lastResult.leaseExpiresAt or session.LeaseExpiresAt
			session.SaveWarning = false
			setAttribute(session.Player, "PlayerDataSaveWarning", false)
			log:Debug(
				"ProfileSaveConfirmed environment=%s userId=%d generation=%d revision=%d currentRevision=%d",
				Environment.Name,
				session.UserId,
				session.Generation,
				revision,
				session.Revision
			)
			notifySaveConfirmed(session)
			log:Debug(
				"ProfileSaveListenersCompleted environment=%s userId=%d generation=%d revision=%d",
				Environment.Name,
				session.UserId,
				session.Generation,
				revision
			)
			return lastResult
		end
		if lastResult.code == "OWNER_MISMATCH" or lastResult.code == "STALE_REVISION" then
			applyOwnershipFailure(session, lastResult.code)
			return lastResult
		end
		if attempt < Config.AttemptsPerBatch then
			log:Warn(
				"ProfileSaveRetry environment=%s userId=%d generation=%d revision=%d attempt=%d code=%s",
				Environment.Name,
				session.UserId,
				session.Generation,
				revision,
				attempt,
				tostring(lastResult.code)
			)
			notifyDiagnostic(session, "SaveRetry", {
				eventId = saveOperationId .. ":retry:" .. tostring(attempt),
				revision = revision,
				attempt = attempt,
				code = lastResult.code,
			})
			waitSeconds(retryDelay(attempt))
		end
	end
	session.SaveWarning = true
	setAttribute(session.Player, "PlayerDataSaveWarning", true)
	return lastResult or { ok = false, code = "SAVE_FAILED" }
end

local function drainSave(session: any, reason: string, drainNewerMutations: boolean?): any
	if session.SaveInFlight then
		session.SaveRequested = true
		return { ok = true, code = "COALESCED" }
	end
	session.SaveInFlight = true
	local lastResult = nil
	local incidentalCatchupUsed = false
	repeat
		session.SaveRequested = false
		lastResult = saveSnapshot(session, reason)
		-- Preparation may settle income into this very snapshot. Only successful
		-- confirmation with genuinely newer live work needs an automatic follow-up;
		-- exhausted retries do not create another batch merely because preparation dirtied it.
		if
			drainNewerMutations == true
			and lastResult.ok
			and session.Revision > session.SavedRevision
			and not session.SaveRequested
			and not incidentalCatchupUsed
		then
			-- Income can legitimately advance during every backend call. Allow one
			-- incidental catch-up, then leave newer work dirty for the next request
			-- or autosave. Explicit coalesced requests still drain, including releases.
			incidentalCatchupUsed = true
			session.SaveRequested = true
		end
	until not session.SaveRequested or exactSession(session.Player) ~= session or session.Status ~= "Ready"
	session.SaveInFlight = false
	log:Debug(
		"ProfileSaveDrainCompleted environment=%s userId=%d generation=%d requested=%s code=%s ok=%s",
		Environment.Name,
		session.UserId,
		session.Generation,
		tostring(session.SaveRequested),
		tostring(if lastResult then lastResult.code else "SAVE_FAILED"),
		tostring(lastResult ~= nil and lastResult.ok == true)
	)
	return lastResult or { ok = false, code = "SAVE_FAILED" }
end

-- Ordinary user mutations share one five-second write deadline. Income-only
-- MarkDirty retains the existing60-second autosave/lease schedule.
function PlayerDataService:RequestDebouncedSave(player: Player, _reason: string): any
	local session = exactSession(player)
	if not session or session.Status ~= "Ready" or session.Closing then
		return { ok = false, code = "PROFILE_NOT_READY" }
	end
	session.OrdinarySaveAt = session.OrdinarySaveAt or (unixNow() + 5)
	return { ok = true, code = "DEBOUNCED" }
end

function PlayerDataService:RequestSave(player: Player, reason: string): any
	local session = exactSession(player)
	if not session or session.Status ~= "Ready" or session.Closing then
		return { ok = false, code = "PROFILE_NOT_READY" }
	end
	if session.SaveInFlight then
		session.SaveRequested = true
		log:Debug(
			"ProfileSaveCoalesced environment=%s userId=%d generation=%d reason=%s",
			Environment.Name,
			session.UserId,
			session.Generation,
			reason
		)
		return { ok = true, code = "COALESCED" }
	end
	task.spawn(drainSave, session, reason, true)
	return { ok = true, code = "SCHEDULED" }
end

function PlayerDataService:SaveNowAsync(player: Player, reason: string): any
	local session = exactSession(player)
	if not session or session.Status ~= "Ready" or session.Closing then
		return { ok = false, code = "PROFILE_NOT_READY" }
	end
	if session.SaveInFlight then
		session.SaveRequested = true
		while session.SaveInFlight and exactSession(player) == session do
			waitSeconds(0)
		end
		return {
			ok = session.SavedRevision >= session.Revision,
			code = if session.SavedRevision >= session.Revision then "SAVED" else "STILL_DIRTY",
		}
	end
	-- A direct save confirms the snapshot it started with. It only drains a
	-- newer revision when another caller explicitly requested that save while
	-- this one was in flight; incidental later gameplay otherwise stays dirty.
	return drainSave(session, reason, false)
end

function PlayerDataService:RegisterCloseFinalizer(callback: (Player) -> ())
	local connection = {}
	closeFinalizers[connection] = callback
	function connection.Disconnect()
		closeFinalizers[connection] = nil
	end
	return connection
end

-- Departure owners run while the exact profile session is still writable and
-- before the final snapshot is prepared. A preparer must finish its bounded,
-- synchronous source-state transition here; presentation cleanup belongs to
-- the normal close finalizers and world lifecycle.
function PlayerDataService:RegisterDeparturePreparer(callback: (Player, string) -> (boolean?, string?))
	local connection = {}
	departurePreparers[connection] = callback
	function connection.Disconnect()
		departurePreparers[connection] = nil
	end
	return connection
end

function PlayerDataService:RegisterSnapshotPreparer(callback: (Player, number) -> (boolean?, string?))
	local connection = {}
	snapshotPreparers[connection] = callback
	function connection.Disconnect()
		snapshotPreparers[connection] = nil
	end
	return connection
end

function PlayerDataService:SubscribeReady(callback: (Player) -> ())
	local connection = {}
	readyListeners[connection] = callback
	function connection.Disconnect()
		readyListeners[connection] = nil
	end
	return connection
end

-- Server-only observation boundary for systems that need to distinguish a
-- committed profile mutation from a backend-confirmed snapshot. Callbacks are
-- scoped again by exact Player/session inside their consumers.
function PlayerDataService:SubscribeSaveConfirmed(callback: (Player, number, number) -> ())
	local connection = {}
	saveConfirmedListeners[connection] = callback
	function connection.Disconnect()
		saveConfirmedListeners[connection] = nil
	end
	return connection
end

-- Read-only, server-local lifecycle receipts for diagnostics and measurement.
-- They contain no profile tables, backend tokens, or authority to mutate data.
function PlayerDataService:SubscribeDiagnostics(callback: (Player, any) -> ())
	local connection = {}
	diagnosticListeners[connection] = callback
	function connection.Disconnect()
		diagnosticListeners[connection] = nil
	end
	return connection
end

-- Capture each domain's departure timestamp before a yielding critical save.
-- This observation cannot clear ownership or release a source reservation.
function PlayerDataService:SubscribeCloseRequested(callback: (Player, string) -> ())
	local connection = {}
	closeRequestedListeners[connection] = callback
	function connection.Disconnect()
		closeRequestedListeners[connection] = nil
	end
	return connection
end

-- The fresh Acquire has succeeded and old generation handles are stale. The
-- snapshots are immutable; observers only reconcile local physical state.
function PlayerDataService:SubscribeSessionRecovered(callback: (Player, Player, any, any) -> boolean?)
	local connection = {}
	sessionRecoveredListeners[connection] = callback
	function connection.Disconnect()
		sessionRecoveredListeners[connection] = nil
	end
	return connection
end

function PlayerDataService:ClosePlayerAsync(player: Player, reason: string, deadline: number?): any
	local session = exactSession(player)
	if not session then
		return { ok = true, code = "ALREADY_CLOSED" }
	end
	if session.CloseInProgress then
		while session.CloseInProgress and exactSession(player) == session do
			waitSeconds(0)
		end
		return session.CloseResult or { ok = false, code = "CLOSE_UNCONFIRMED" }
	end
	session.CloseInProgress = true
	if not session.CloseRequested then
		session.CloseRequested = true
		for _, callback in closeRequestedListeners do
			local ok, failure = pcall(callback, player, reason)
			if not ok then
				log:Warn("Profile close observation failed for UserId=%d: %s", session.UserId, tostring(failure))
			end
		end
	end
	if session.Recovery then
		session.DeferredCloseReason = reason
		session.CloseInProgress = false
		return { ok = false, code = "RECOVERY_CLOSE_PENDING" }
	end
	if session.CriticalOperation then
		session.DeferredCloseReason = reason
		-- Confirm the same frozen critical snapshot before departure handlers change ownership.
		local result = self:SaveNowAsync(player, "CriticalDeparture")
		if not result.ok or session.CriticalOperation then
			session.CloseInProgress = false
			return { ok = false, code = "CRITICAL_CLOSE_PENDING" }
		end
	end
	for _, callback in departurePreparers do
		local called, prepared, failure = pcall(callback, player, reason)
		if not called or prepared == false then
			local code = if called then failure else prepared
			log:Warn(
				"Profile departure preparation failed for UserId=%d: %s",
				session.UserId,
				tostring(code or "DEPARTURE_PREPARATION_FAILED")
			)
			session.CloseInProgress = false
			session.CloseResult = {
				ok = false,
				code = "DEPARTURE_PREPARATION_FAILED",
				reason = tostring(code or "UNKNOWN"),
			}
			return session.CloseResult
		end
	end
	session.Closing = true
	publishStatus(session, "Closing")
	setAttribute(player, "PlayerDataWritable", false)
	log:Info(
		"ProfileCloseStarted environment=%s userId=%d generation=%d revision=%d reason=%s",
		Environment.Name,
		session.UserId,
		session.Generation,
		session.Revision,
		reason
	)
	notifyDiagnostic(session, "CloseStarted", {
		eventId = string.format("%d:close-started", session.Generation),
		revision = session.Revision,
		reason = reason,
	})

	if session.Data == nil then
		-- A late acquisition checks this generation and releases only its own token.
		generationsByUserId[session.UserId] += 1
		currentByUserId[session.UserId] = nil
		sessions[player] = nil
		session.CloseInProgress = false
		session.CloseResult = { ok = true, code = "LOAD_CANCELLED" }
		return session.CloseResult
	end

	local closeCutoff = unixNow()
	local prepared, prepareReason = prepareSnapshot(session, closeCutoff)
	if not prepared then
		session.CloseInProgress = false
		session.CloseResult = {
			ok = false,
			code = prepareReason or "SNAPSHOT_PREPARATION_FAILED",
		}
		return session.CloseResult
	end

	for _, callback in closeFinalizers do
		local ok, failure = pcall(callback, player)
		if not ok then
			log:Warn("Profile close finalizer failed for UserId=%d: %s", session.UserId, tostring(failure))
		end
	end

	local closeDeadline = deadline or (monotonicNow() + Config.FinalCloseDeadlineSeconds)
	while session.SaveInFlight and monotonicNow() < closeDeadline do
		waitSeconds(0)
	end
	local snapshot, snapshotReason = Schema.CreateSaveSnapshot(session.Data)
	local closeResult: any = { ok = false, code = snapshotReason or "INVALID_PROFILE" }
	if snapshot then
		local releaseOperationId = operationId("close")
		for attempt = 1, Config.AttemptsPerBatch do
			if monotonicNow() >= closeDeadline then
				closeResult = { ok = false, code = "CLOSE_DEADLINE" }
				break
			end
			closeResult =
				backend:Release(session.Key, session.OwnerToken, releaseOperationId, session.Revision, snapshot)
			if closeResult.ok or closeResult.code == "OWNER_MISMATCH" then
				break
			end
			if attempt < Config.AttemptsPerBatch then
				waitSeconds(math.min(retryDelay(attempt), math.max(0, closeDeadline - monotonicNow())))
			end
		end
	end
	if closeResult.ok then
		session.SavedRevision = session.Revision
		notifySaveConfirmed(session)
		publishStatus(session, "Closed")
		log:Info(
			"ProfileCloseCompleted environment=%s userId=%d generation=%d revision=%d",
			Environment.Name,
			session.UserId,
			session.Generation,
			session.Revision
		)
		notifyDiagnostic(session, "CloseCompleted", {
			eventId = string.format("%d:close-completed", session.Generation),
			revision = session.Revision,
		})
	else
		publishStatus(session, "Failed")
		log:Warn(
			"ProfileCloseUnconfirmed environment=%s userId=%d generation=%d revision=%d code=%s",
			Environment.Name,
			session.UserId,
			session.Generation,
			session.Revision,
			tostring(closeResult.code)
		)
		notifyDiagnostic(session, "CloseUnconfirmed", {
			eventId = string.format("%d:close-unconfirmed", session.Generation),
			revision = session.Revision,
			code = closeResult.code,
		})
	end
	setAttribute(player, "Cash", nil)
	session.CloseResult = closeResult
	session.CloseInProgress = false
	if exactSession(player) == session then
		currentByUserId[session.UserId] = nil
		sessions[player] = nil
	end
	return closeResult
end

function PlayerDataService:Step()
	local currentTime = unixNow()
	for _, session in sessions do
		if session.Status == "Recovering" and exactSession(session.Player) == session and not session.Closing then
			if ownerStillSafe(session) then
				reconcileRecoveredSession(session)
			else
				applyOwnershipFailure(session, "LEASE_SAFETY_DEADLINE")
			end
		elseif session.Status == "Ready" and not session.Closing then
			if not ownerStillSafe(session) then
				applyOwnershipFailure(session, "LEASE_SAFETY_DEADLINE")
			elseif session.DeferredCloseReason and not session.CriticalOperation and not session.CloseInProgress then
				-- PlayerRemoving runs once. Resume that exact close only after the
				-- covering-save observer has reconciled the critical source/reward.
				self:ClosePlayerAsync(session.Player, session.DeferredCloseReason)
			elseif session.OrdinarySaveAt and currentTime >= session.OrdinarySaveAt then
				session.OrdinarySaveAt = nil
				self:RequestSave(session.Player, "DirtyDebounce")
			elseif currentTime >= session.NextSaveAt then
				session.NextSaveAt = currentTime + Config.AutosaveIntervalSeconds
				self:RequestSave(
					session.Player,
					if session.Revision > session.SavedRevision then "Autosave" else "LeaseRenewal"
				)
			end
		end
	end
end

function PlayerDataService:GetDiagnostics(player: Player): any?
	local session = exactSession(player)
	if not session then
		return nil
	end
	return {
		status = session.Status,
		generation = session.Generation,
		currentRevision = session.Revision,
		lastConfirmedSavedRevision = session.SavedRevision,
		dirty = session.Revision > session.SavedRevision,
		saveInFlight = session.SaveInFlight,
		writable = writableSession(player) ~= nil,
		closing = session.Closing,
		failureCode = session.FailureCode,
		profileOrigin = session.ProfileOrigin,
		isolatedTestProfile = session.Key:sub(1, 12) == "phase8_test_",
	}
end

function PlayerDataService:ShutdownAsync(deadline: number?): any
	if shuttingDown then
		return { ok = true, code = "ALREADY_SHUTTING_DOWN" }
	end
	shuttingDown = true
	local sharedDeadline = deadline or (monotonicNow() + Config.ShutdownBudgetSeconds)
	local pendingPlayers = {}
	for player in sessions do
		table.insert(pendingPlayers, player)
	end
	local remaining = #pendingPlayers
	local nextIndex = 1
	local unresolved = {}
	local workerCount = math.min(Config.ShutdownConcurrency, remaining)
	for _ = 1, workerCount do
		task.spawn(function()
			while monotonicNow() < sharedDeadline do
				local index = nextIndex
				nextIndex += 1
				local player = pendingPlayers[index]
				if player == nil then
					return
				end
				local closeResult = self:ClosePlayerAsync(player, "Shutdown", sharedDeadline)
				if closeResult.ok ~= true then
					table.insert(unresolved, {
						userId = player.UserId,
						code = closeResult.code or "CLOSE_UNCONFIRMED",
					})
				end
				remaining -= 1
			end
		end)
	end
	while remaining > 0 and monotonicNow() < sharedDeadline do
		waitSeconds(0)
	end
	table.sort(unresolved, function(a, b)
		return a.userId < b.userId
	end)
	return {
		ok = remaining == 0 and #unresolved == 0,
		code = if remaining > 0 then "DEADLINE" elseif #unresolved > 0 then "CLOSE_UNCONFIRMED" else "CLOSED",
		remaining = remaining,
		unresolved = unresolved,
	}
end

local function bindVFXSettingsRemote()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	local existing = folder:FindFirstChild(RemoteNames.VFXSettingsRequest)
	if existing and not existing:IsA("RemoteFunction") then
		log:Warn("VFX settings remote type conflict; cosmetic settings remain unavailable")
		return
	end
	settingsRemote = (existing or Instance.new("RemoteFunction")) :: RemoteFunction
	settingsRemote.Name = RemoteNames.VFXSettingsRequest
	settingsHandler = function(player: Player, ...: any)
		local called, result = pcall(PlayerDataService.HandleVFXSettingsRequest, PlayerDataService, player, ...)
		return if called then result else { ok = false, code = "SETTINGS_UNAVAILABLE" }
	end
	settingsRemote.OnServerInvoke = settingsHandler
	settingsRemote.Parent = folder
end

function PlayerDataService:Start(options: any?): boolean
	if started then
		return true
	end
	if options or backend == nil then
		self:Init(options)
	end
	started = true
	-- Cosmetic settings must not stall profile loading or gameplay on a bad
	-- optional remote binding. The normal session lifecycle remains unchanged.
	local bound, bindFailure = pcall(bindVFXSettingsRemote)
	if not bound then
		log:Warn("VFX settings unavailable: %s", tostring(bindFailure))
	end
	if not backend:IsAvailable() then
		log:Warn("Player profile persistence unavailable in %s; writable defaults are disabled", Environment.Name)
	end
	table.insert(
		connections,
		Players.PlayerAdded:Connect(function(player)
			task.spawn(function()
				self:LoadPlayerAsync(player)
			end)
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			self:ClosePlayerAsync(player, "PlayerRemoving")
		end)
	)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(deltaTime)
			schedulerAccumulator += deltaTime
			if schedulerAccumulator >= 1 then
				schedulerAccumulator %= 1
				self:Step()
			end
		end)
	)
	game:BindToClose(function()
		self:ShutdownAsync()
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:LoadPlayerAsync(player)
		end)
	end
	return true
end

function PlayerDataService:_ResetForTests()
	if settingsRemote and settingsRemote.OnServerInvoke == settingsHandler then
		settingsRemote.OnServerInvoke = nil
	end
	settingsRemote, settingsHandler = nil, nil
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(sessions)
	table.clear(currentByUserId)
	table.clear(generationsByUserId)
	table.clear(readyListeners)
	table.clear(saveConfirmedListeners)
	table.clear(diagnosticListeners)
	table.clear(closeFinalizers)
	table.clear(closeRequestedListeners)
	table.clear(sessionRecoveredListeners)
	table.clear(recoveryAcquisitions)
	table.clear(departurePreparers)
	table.clear(snapshotPreparers)
	started = false
	shuttingDown = false
	backend = nil
	dependencies = nil
	schedulerAccumulator = 0
end

-- One coordinated write fence. Critical service callbacks may mutate through this exact handle.
function PlayerDataService:GetCurrentRevision(player: Player): number?
	local s = exactSession(player)
	return if s then s.Revision else nil
end
function PlayerDataService:GetSavedRevision(player: Player): number?
	local s = exactSession(player)
	return if s then s.SavedRevision else nil
end
function PlayerDataService:IsRevisionConfirmed(player: Player, revision: number): boolean
	local s = exactSession(player)
	return s ~= nil and s.SavedRevision >= revision
end
function PlayerDataService:AcquireCritical(player: Player, id: string): (any?, string?)
	local s, reason = writableSession(player)
	if not s then
		return nil, reason
	end
	local handle = { Player = player, Session = s, OperationId = id, Before = cloneTable(s.Data) }
	s.CriticalOperation = handle
	return handle, nil
end
function PlayerDataService:CommitCriticalMutation(player: Player, handle: any, callback: any): any
	local s = exactSession(player)
	if not s or s.CriticalOperation ~= handle or handle.Session ~= s then
		return { ok = false, code = "CRITICAL_HANDLE_CHANGED" }
	end
	s.CriticalMutationOwner = true
	local ok, result = pcall(self.CommitMutation, self, player, callback)
	s.CriticalMutationOwner = false
	if not ok then
		return { ok = false, code = "CRITICAL_MUTATION_ERROR", error = tostring(result) }
	end
	return result
end
function PlayerDataService:ReleaseCritical(player: Player, handle: any): boolean
	local s = exactSession(player)
	if not s or s.CriticalOperation ~= handle then
		return false
	end
	s.CriticalOperation = nil
	return true
end
function PlayerDataService:HasCriticalOperation(player: Player): boolean
	local s = exactSession(player)
	return s ~= nil and s.CriticalOperation ~= nil
end

-- Archive only a fully saved, exact owned session. The existing critical fence
-- excludes ordinary mutations throughout yielding storage work. Prompt readiness
-- never blocks recovery of an already-issued verified receipt. Normal boot does
-- not initiate archival; callers must explicitly request capacity recovery.
function PlayerDataService:RecoverPaidReceiptCapacity(player: Player): any
	local s, why = writableSession(player)
	if not s then return { ok = false, code = why } end
	if not backend.CanArchivePaidReceipts or not backend:CanArchivePaidReceipts() then
		return { ok = false, code = "PAID_ARCHIVE_DISABLED" }
	end
	if s.SaveInFlight or s.Revision ~= s.SavedRevision then return { ok = false, code = "AWAITING_COVERING_SAVE" } end
	local handle, reason = self:AcquireCritical(player, operationId("paid-archive"))
	if not handle then return { ok = false, code = reason } end
	s.SaveInFlight = true
	local ok, outcome = pcall(backend.ArchivePaidReceipts, backend, s.Key, s.OwnerToken, handle.OperationId, s.Revision)
	s.SaveInFlight = false
	if exactSession(player) ~= s or s.CriticalOperation ~= handle then return { ok = false, code = "SESSION_CHANGED" } end
	if ok and outcome.ok then
		restoreTableInPlace(s.Data, outcome.envelope.Data)
		s.SaveEnvelope = cloneTable(outcome.envelope)
		s.SaveEnvelope.Data = nil
		s.Revision = outcome.envelope.Transport.LastRevision
		s.SavedRevision = s.Revision
		s.CriticalOperation = nil
		notifySaveConfirmed(s)
		return { ok = true, code = outcome.code, moved = outcome.moved }
	end
	-- Once a storage attempt can have fenced/published, this session must not
	-- resume a stale snapshot. Existing canonical reacquisition owns recovery.
	local untouched = ok and (outcome.code == "PAID_ARCHIVE_BUDGET" or outcome.code == "PAID_ARCHIVE_DISABLED"
		or outcome.code == "PAID_ARCHIVE_NO_CONFIRMED_ROWS" or outcome.code == "PERSISTENCE_UNAVAILABLE")
	if not untouched then
		applyOwnershipFailure(s, if ok then outcome.code else "PAID_ARCHIVE_UNCERTAIN")
	else
		s.CriticalOperation = nil
	end
	return if ok then outcome else { ok = false, code = "PAID_ARCHIVE_UNCERTAIN", uncertain = true }
end
function PlayerDataService:LookupPaidReceipt(player: Player, purchaseId: string): any
	local s, why = writableSession(player)
	if not s then return { ok = false, code = why } end
	if not backend.LookupPaidReceipt then return { ok = false, code = "PAID_ARCHIVE_LOOKUP_UNAVAILABLE" } end
	local outcome = backend:LookupPaidReceipt(s.Key, s.OwnerToken, purchaseId)
	if exactSession(player) ~= s or not writableSession(player) then return { ok = false, code = "SESSION_CHANGED" } end
	if outcome.ok and outcome.epoch ~= (s.Data.Commerce.PaidArchiveEpoch or 0) then
		return { ok = false, code = "PAID_ARCHIVE_LOOKUP_RETRY" }
	end
	return outcome
end

return PlayerDataService
