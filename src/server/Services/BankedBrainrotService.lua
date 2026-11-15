--!strict

local PlayerDataService = require(script.Parent.PlayerDataService)
local CurrencySystem = require(script.Parent.Parent.Systems.CurrencySystem)
local Logger = require(game:GetService("ReplicatedStorage").Shared.Utility.Logger)

local Phase10 = require(game:GetService("ReplicatedStorage").Shared.Config.Phase10)
local Phase12Rules = require(game:GetService("ReplicatedStorage").Shared.Utility.Phase12Rules)
local Phase12Progress = require(script.Parent.Parent.Data.Phase12Progress)
local HttpService = game:GetService("HttpService")

local BankedBrainrotService = {}
local log = Logger.new("BankedBrainrotService")
local profileOwner: any = PlayerDataService
local currency: any = CurrencySystem
local pendingBanks: { [number]: { [string]: any } } = {}
local Phase13Rules = require(game.ReplicatedStorage.Shared.Utility.Phase13Rules)
local pendingReleases: { [Player]: { [string]: any } } = {}
local connections: { any } = {}
local started = false
local expeditions: { [Player]: any } = setmetatable({}, { __mode = "k" })
local bankListeners: { [any]: any } = {}
local upgradeService: any? = nil
local campClassifier: any? = nil
local injectedFixtureQuotes = false
-- A rejoin decision is applied only before this exact loaded session first
-- binds its base. Later carried/cargo individuals must never be auto-returned.
-- Values contain no Player reference; existing close diagnostics also clear it.
local initialLocationsReconciled: { [Player]: any } = setmetatable({}, { __mode = "k" })

local function ownedMap(data: any): any?
	return if type(data) == "table"
			and type(data.Collection) == "table"
			and type(data.Collection.BrainrotInstances) == "table"
		then data.Collection.BrainrotInstances
		else nil
end

local function slots(data: any): any?
	return if type(data) == "table"
			and type(data.Base) == "table"
			and type(data.Base.Slots) == "table"
		then data.Base.Slots
		else nil
end

local function assignedSlot(data: any, individualId: string): string?
	local records = slots(data)
	if not records then
		return nil
	end
	for slotId, slot in records do
		if type(slot) == "table" and slot.brainrotId == individualId then
			return slotId
		end
	end
	return nil
end

local function identity(record: any): (string?, string?)
	local individualId = if type(record) == "table" then record.ItemId or record.individualId else nil
	local speciesId = if type(record) == "table" then record.BrainrotId or record.speciesId else nil
	return if type(individualId) == "string" and individualId ~= "" then individualId else nil,
		if type(speciesId) == "string" and speciesId ~= "" then speciesId else nil
end

local function clearSlotReferences(data: any, individualId: string)
	for _, slot in slots(data) or {} do
		if type(slot) == "table" and slot.brainrotId == individualId then
			slot.brainrotId = nil
			-- Platform cash is retained independently of its occupant.
		end
	end
end

local function currentPending(player: Player, individualId: string): any?
	local byId = pendingReleases[player]
	return if byId then byId[individualId] else nil
end

local function removePending(player: Player, individualId: string, expected: any?)
	local byId = pendingReleases[player]
	if byId and (expected == nil or byId[individualId] == expected) then
		byId[individualId] = nil
		if next(byId) == nil then
			pendingReleases[player] = nil
		end
	end
end

local function attemptConfirmedPublication(operation: any): boolean
	if operation.Status ~= "Confirmed" then
		return false
	end
	local ok, published, reason = pcall(operation.OnConfirmed, operation)
	if ok and published == true then
		removePending(operation.Player, operation.IndividualId, operation)
		return true
	end
	operation.PublicationError = tostring(if ok then reason or "NOT_PUBLISHED" else published)
	return false
end

local processPendingBanks
local function onSaveConfirmed(player: Player, savedRevision: number, _currentRevision: number)
	processPendingBanks(player, savedRevision)
	local byId = pendingReleases[player]
	if byId == nil then
		return
	end
	for individualId, operation in table.clone(byId) do
		if
			operation.Status == "Pending"
			and savedRevision >= operation.Revision
			and profileOwner:IsCurrentSessionHandle(operation.Session)
		then
			operation.Status = "Confirmed"
			operation.ConfirmedRevision = savedRevision
			log:Info(
				"BankedReleaseConfirmed userId=%d individualId=%s revision=%d savedRevision=%d",
				player.UserId,
				individualId,
				operation.Revision,
				savedRevision
			)
			if not attemptConfirmedPublication(operation) then
				log:Warn(
					"Banked release publication callback failed userId=%d individualId=%s: %s",
					player.UserId,
					individualId,
					tostring(operation.PublicationError)
				)
			end
		end
	end
end

local function onProfileDiagnostic(player: Player, receipt: any)
	if
		type(receipt) == "table"
		and (receipt.kind == "CloseCompleted" or receipt.kind == "CloseUnconfirmed" or receipt.kind == "SessionLost")
	then
		initialLocationsReconciled[player] = nil
		expeditions[player] = nil
	end
	if
		type(receipt) ~= "table"
		or (receipt.kind ~= "SessionLost" and receipt.kind ~= "CloseUnconfirmed" and receipt.kind ~= "LoadRejected")
	then
		return
	end
	local byId = pendingReleases[player]
	if byId == nil then
		return
	end
	for individualId, operation in table.clone(byId) do
		if operation.Status == "Confirmed" then
			continue
		end
		operation.Status = "Unconfirmed"
		operation.FailureCode = receipt.code or receipt.kind
		removePending(player, individualId, operation)
		if type(operation.OnUnconfirmed) == "function" then
			pcall(operation.OnUnconfirmed, operation)
		end
		log:Warn(
			"Banked release not published userId=%d individualId=%s code=%s",
			player.UserId,
			individualId,
			tostring(operation.FailureCode)
		)
	end
end

function BankedBrainrotService:Init(options: any?): boolean
	local deps = options or {}
	profileOwner = deps.Profile or PlayerDataService
	currency = deps.Currency or CurrencySystem
	upgradeService = deps.Upgrades
	injectedFixtureQuotes = false
	return true
end

function BankedBrainrotService:Start(): boolean
	if started then
		return false
	end
	started = true
	if type(profileOwner.SubscribeSaveConfirmed) == "function" then
		table.insert(connections, profileOwner:SubscribeSaveConfirmed(onSaveConfirmed))
	end
	if type(profileOwner.SubscribeDiagnostics) == "function" then
		table.insert(connections, profileOwner:SubscribeDiagnostics(onProfileDiagnostic))
	end
	if type(profileOwner.SubscribeReady) == "function" then
		table.insert(
			connections,
			profileOwner:SubscribeReady(function(player)
				self:ReconcilePendingBanksOnAcquire(player)
			end)
		)
	end
	if type(profileOwner.SubscribeSessionRecovered) == "function" then
		table.insert(
			connections,
			profileOwner:SubscribeSessionRecovered(function(_oldPlayer, newPlayer)
				local result = self:ReconcilePendingBanksOnAcquire(newPlayer)
				return result.ok and not self:HasPendingBank(newPlayer)
			end)
		)
	end
	return true
end

function BankedBrainrotService:GetOwnedIndividual(player: Player, individualId: string): any?
	local data = profileOwner:GetReadableData(player)
	local owned = ownedMap(data)
	return if owned then owned[individualId] else nil
end

-- DurableOwnerUserId comes from the trusted storage/profile adapter, never a
-- client model attribute. Existing valid owned entries remain banked without a
-- new migration field, even when their logical platform is currently empty.
function BankedBrainrotService:IsBankedRecord(record: any): boolean
	local metadata = if type(record) == "table" then record.Metadata else nil
	return type(metadata) == "table"
		and type(metadata.DurableOwnerUserId) == "number"
		and metadata.DurableOwnerUserId == metadata.DurableOwnerUserId
		and math.abs(metadata.DurableOwnerUserId) < math.huge
end

function BankedBrainrotService:ClassifyRecord(player: Player, record: any): string
	local id, species = identity(record)
	if not id or not species then
		return "Uncertain"
	end
	local data = profileOwner:GetReadableData(player)
	if data == nil then
		return "Uncertain"
	end
	local owned = ownedMap(data)
	if owned == nil then
		return "Uncertain"
	end
	local saved = owned[id]
	if saved ~= nil then
		return if type(saved) == "table" and saved.speciesId == species then "Banked" else "Uncertain"
	end
	if self:IsBankedRecord(record) then
		return "Banked"
	end
	if type(record.Metadata) == "table" and record.Metadata.DurableOwnerUserId ~= nil then
		return "Uncertain"
	end
	return "FreshUnbanked"
end

function BankedBrainrotService:ValidateSaleRecord(player: Player, record: any): (boolean, string?)
	local individualId, speciesId = identity(record)
	if not individualId or not speciesId then
		return false, "INVALID_IDENTITY"
	end
	local data = profileOwner:GetReadableData(player)
	if not data then
		return false, "PROFILE_NOT_READY"
	end
	local owned = ownedMap(data)
	local saved = if owned then owned[individualId] else nil
	if saved == nil then
		return false, "BANK_FIRST"
	end
	if type(saved) ~= "table" or saved.speciesId ~= speciesId then
		return false, "OWNERSHIP_INCONSISTENT"
	end
	if Phase12Progress.MutationId(saved) ~= Phase12Progress.MutationId(record) then
		return false, "MUTATION_CHANGED"
	end
	if saved.favourite == true then
		return false, "FAVOURITE"
	end
	if currentPending(player, individualId) then
		return false, "RELEASE_PENDING"
	end
	if assignedSlot(data, individualId) ~= nil then
		return false, "STILL_BANKED"
	end
	return true, nil
end

-- Favourite lock: a flag the player sets on an owned individual. It blocks every sale (carried and
-- bulk) until the player clears it; nothing else reads it. Stored as `favourite = true` or absent.
function BankedBrainrotService:IsFavourite(player: Player, individualId: any): boolean
	local owned = ownedMap(profileOwner:GetReadableData(player))
	local saved = if owned and type(individualId) == "string" then owned[individualId] else nil
	return type(saved) == "table" and saved.favourite == true
end

function BankedBrainrotService:GetFavourites(player: Player): { [string]: boolean }
	local favourites = {}
	for individualId, saved in ownedMap(profileOwner:GetReadableData(player)) or {} do
		if type(saved) == "table" and saved.favourite == true then
			favourites[individualId] = true
		end
	end
	return favourites
end

function BankedBrainrotService:SetFavourite(player: Player, individualId: any, value: any): any
	if type(individualId) ~= "string" or individualId == "" or #individualId > 128 or type(value) ~= "boolean" then
		return { ok = false, committed = false, code = "INVALID_REQUEST" }
	end
	return profileOwner:CommitMutation(player, function(data)
		local owned = ownedMap(data)
		local saved = if owned then owned[individualId] else nil
		if type(saved) ~= "table" then
			return false, { ok = false, committed = false, code = "NOT_OWNED" }
		end
		if (saved.favourite == true) == value then
			return false, { ok = true, committed = false, code = "UNCHANGED", favourite = value }
		end
		saved.favourite = if value then true else nil
		return true, { ok = true, committed = true, code = "FAVOURITE_SET", favourite = value }
	end)
end

function BankedBrainrotService:GetSlot(player: Player, slotIndex: number): any?
	local data = profileOwner:GetReadableData(player)
	local records = slots(data)
	return if records then records[tostring(slotIndex)] else nil
end

function BankedBrainrotService:IsReleasePending(player: Player, individualId: string): boolean
	return currentPending(player, individualId) ~= nil
end

-- Approved abrupt-server-loss policy: durable individuals with no saved slot
-- return to available logical slots on the next session; excess individuals
-- disappear when all twelve slots are occupied. No payout or world copy.
function BankedBrainrotService:ReconcileInitialOwnedLocations(player: Player, owner: any?): any
	local source = owner or profileOwner
	local session = source:GetSessionHandle(player)
	if session == nil or not source:IsCurrentSessionHandle(session) or not source:IsWritable(player) then
		return { ok = false, committed = false, code = "PROFILE_NOT_READY" }
	end
	local prior = initialLocationsReconciled[player]
	if
		prior
		and prior.Owner == source
		and prior.Generation == session.Generation
		and prior.UserId == session.UserId
	then
		return { ok = true, committed = false, code = "INITIAL_LOCATIONS_ALREADY_RECONCILED" }
	end
	local result = source:CommitMutation(player, function(data)
		local owned, records = ownedMap(data), slots(data)
		if owned == nil or records == nil then
			return false, { ok = false, code = "PROFILE_SHAPE_INVALID" }
		end
		local placed, available, unassigned = {}, {}, {}
		local capacity = Phase13Rules.GetCapacity(data)
		-- A legacy locked reference remains owned in that exact slot. It is not an
		-- unassigned individual to auto-return, overflow-delete, move or pay out.
		for slotId, slot in records do
			if type(slot) == "table" then
				local index = tonumber(slotId)
				if index and index > capacity and (type(slot.brainrotId) == "string" or slot.accumulatedCash > 0) then
					log:Warn("Retained unavailable saved slot userId=%d slot=%s individual=%s capacity=%d", player.UserId, tostring(slotId), tostring(slot.brainrotId), capacity)
				end
				if type(slot.brainrotId) == "string" then placed[slot.brainrotId] = true end
			end
		end
		for index = 1, capacity do
			local slotId = tostring(index)
			local slot = records[slotId]
			if type(slot) ~= "table" then
				return false, { ok = false, code = "PROFILE_SHAPE_INVALID" }
			end
			if slot.brainrotId ~= nil then
				placed[slot.brainrotId] = true
			else
				table.insert(available, slotId)
			end
		end
		for individualId in owned do
			if not placed[individualId] then
				table.insert(unassigned, individualId)
			end
		end
		table.sort(unassigned)
		for index, individualId in unassigned do
			local slotId = available[index]
			if slotId then
				-- Ownership metadata survives; a newly occupied slot starts at zero.
				records[slotId].brainrotId = individualId
				-- Platform cash is retained independently of its occupant.
			elseif not Phase10.Enabled then
				owned[individualId] = nil
			end
		end
		return math.min(#unassigned, #available) > 0 or (not Phase10.Enabled and #unassigned > 0),
			{
				ok = true,
				committed = math.min(#unassigned, #available) > 0 or (not Phase10.Enabled and #unassigned > 0),
				code = if #unassigned > 0 then "INITIAL_LOCATIONS_RECONCILED" else "NO_UNASSIGNED_OWNERSHIP",
				returnedCount = math.min(#unassigned, #available),
				destroyedCount = if Phase10.Enabled then 0 else math.max(0, #unassigned - #available),
				retainedUnassignedCount = if Phase10.Enabled then math.max(0, #unassigned - #available) else 0,
			}
	end)
	if result.ok then
		initialLocationsReconciled[player] =
			{ Owner = source, Generation = session.Generation, UserId = session.UserId }
		if result.committed then
			log:Info(
				"BankedRejoinReconciled userId=%d returned=%d disappeared=%d revision=%d",
				player.UserId,
				result.returnedCount,
				result.destroyedCount,
				result.revision
			)
		end
	end
	return result
end

function BankedBrainrotService:ReturnOwnedToAvailableSlot(player: Player, record: any): any
	local individualId, speciesId = identity(record)
	if individualId == nil or speciesId == nil then
		return { ok = false, committed = false, code = "INVALID_IDENTITY" }
	end
	if currentPending(player, individualId) ~= nil then
		return { ok = false, committed = false, code = "RELEASE_PENDING" }
	end
	return profileOwner:CommitMutation(player, function(data)
		local owned = ownedMap(data)
		local saved = if owned then owned[individualId] else nil
		if type(saved) ~= "table" or saved.speciesId ~= speciesId then
			return false, { ok = false, committed = false, code = "OWNERSHIP_INCONSISTENT" }
		end
		local priorSlot = assignedSlot(data, individualId)
		if priorSlot ~= nil then
			return false,
				{
					ok = true,
					committed = false,
					code = "ALREADY_STORED",
					slotId = priorSlot,
				}
		end
		local records = slots(data)
		for index = 1, Phase13Rules.GetCapacity(data) do
			local slotId = tostring(index)
			local slot = records and records[slotId]
			if type(slot) == "table" and slot.brainrotId == nil then
				-- A return starts a new stay; no money follows the individual.
				slot.brainrotId = individualId
				-- Platform cash is retained independently of its occupant.
				return true,
					{
						ok = true,
						committed = true,
						code = "RETURNED_TO_BASE",
						slotId = slotId,
					}
			end
		end
		return false, { ok = false, committed = false, code = "BASE_FULL" }
	end)
end

function BankedBrainrotService:DestroyOwned(player: Player, record: any): any
	local individualId, speciesId = identity(record)
	if individualId == nil or speciesId == nil then
		return { ok = false, committed = false, code = "INVALID_IDENTITY" }
	end
	if currentPending(player, individualId) ~= nil then
		return { ok = false, committed = false, code = "RELEASE_PENDING" }
	end
	return profileOwner:CommitMutation(player, function(data)
		local owned = ownedMap(data)
		local saved = if owned then owned[individualId] else nil
		if type(saved) ~= "table" or saved.speciesId ~= speciesId then
			return false, { ok = false, committed = false, code = "OWNERSHIP_INCONSISTENT" }
		end
		clearSlotReferences(data, individualId)
		owned[individualId] = nil
		return true, { ok = true, committed = true, code = "OWNERSHIP_DESTROYED" }
	end)
end

-- Applies every persistent ownership consequence of one logout in one profile
-- mutation. Runtime-only fresh items are intentionally absent from this
-- mutation and are returned in the outcome table for the world coordinator.
function BankedBrainrotService:ApplyLogoutOutcomes(player: Player, carriedRecord: any?, cargoRecords: { any }): any
	if type(cargoRecords) ~= "table" then
		return { ok = false, committed = false, code = "INVALID_CARGO" }
	end
	local seen: { [string]: boolean } = {}
	local carriedId, carriedSpecies = identity(carriedRecord)
	if carriedRecord ~= nil and (carriedId == nil or carriedSpecies == nil) then
		return { ok = false, committed = false, code = "INVALID_CARRIED_IDENTITY" }
	end
	if carriedId then
		seen[carriedId] = true
	end
	for _, record in cargoRecords do
		local individualId, speciesId = identity(record)
		if individualId == nil or speciesId == nil then
			return { ok = false, committed = false, code = "INVALID_CARGO_IDENTITY" }
		end
		if seen[individualId] then
			return { ok = false, committed = false, code = "DUPLICATE_DEPARTURE_SOURCE" }
		end
		seen[individualId] = true
	end

	return profileOwner:CommitMutation(player, function(data)
		local owned = ownedMap(data)
		local records = slots(data)
		if owned == nil or records == nil then
			return false, { ok = false, committed = false, code = "PROFILE_SHAPE_INVALID" }
		end
		local outcomes: { [string]: any } = {}
		local changed = false
		if carriedId and carriedSpecies then
			local saved = owned[carriedId]
			if saved == nil then
				outcomes[carriedId] = { action = "PublishExistingWorldDrop", durable = false }
			elseif type(saved) ~= "table" or saved.speciesId ~= carriedSpecies then
				return false, { ok = false, committed = false, code = "OWNERSHIP_INCONSISTENT" }
			else
				local destination = assignedSlot(data, carriedId)
				if destination == nil then
					for index = 1, Phase13Rules.GetCapacity(data) do
						local slotId = tostring(index)
						local slot = records[slotId]
						if type(slot) == "table" and slot.brainrotId == nil then
							slot.brainrotId = carriedId
							-- Platform cash is retained independently of its occupant.
							destination = slotId
							changed = true
							break
						end
					end
				end
				if destination then
					outcomes[carriedId] = {
						action = "ReturnToAvailableSlot",
						durable = true,
						slotId = destination,
					}
				elseif Phase10.Enabled then
					outcomes[carriedId] = { action = "PreserveOwnedUnassigned", durable = true }
				else
					clearSlotReferences(data, carriedId)
					owned[carriedId] = nil
					changed = true
					outcomes[carriedId] = { action = "DestroyOwned", durable = true }
				end
			end
		end

		for _, record in cargoRecords do
			local individualId, speciesId = identity(record)
			local saved = owned[individualId :: string]
			if saved == nil then
				outcomes[individualId :: string] = {
					action = "PublishExistingWorldDrop",
					durable = false,
				}
			elseif type(saved) ~= "table" or saved.speciesId ~= speciesId then
				return false, { ok = false, committed = false, code = "OWNERSHIP_INCONSISTENT" }
			elseif Phase10.Enabled then
				local destination = assignedSlot(data, individualId :: string)
				if not destination then
					for index = 1, Phase13Rules.GetCapacity(data) do
						local slot = records[tostring(index)]
						if type(slot) == "table" and slot.brainrotId == nil then
							slot.brainrotId = individualId
							destination = tostring(index)
							changed = true
							break
						end
					end
				end
				outcomes[individualId :: string] = {
					action = if destination then "ReturnToAvailableSlot" else "PreserveOwnedUnassigned",
					durable = true,
					slotId = destination,
				}
			else
				clearSlotReferences(data, individualId :: string)
				owned[individualId :: string] = nil
				changed = true
				outcomes[individualId :: string] = { action = "DestroyOwned", durable = true }
			end
		end

		if not changed then
			return false, { ok = true, committed = false, code = "NO_PERSISTENT_CHANGE", outcomes = outcomes }
		end
		return true, { ok = true, committed = true, code = "LOGOUT_OUTCOMES_APPLIED", outcomes = outcomes }
	end)
end

-- Timed-reset case G: protected dropped originals keep durable ownership but
-- must leave their displaced world pose. Reuse the existing ownership return
-- commit, exact world retirement and platform binding boundaries. Saved slots
-- also drive bind retries after a source was retired; no second return queue,
-- ownership grant, first-bank receipt or fresh-population operation is added.
function BankedBrainrotService:RestoreSecuredWorldForReset(player: Player, world: any): (boolean, string?, any)
	local summary = { worldSources = 0, returnedToSlots = 0, preservedUnassigned = 0, retired = 0 }
	if
		not Phase10.Enabled
		or type(world) ~= "table"
		or type(world.GetSecuredWorldRecords) ~= "function"
		or type(world.RetireSecuredWorld) ~= "function"
	then
		return false, "SECURED_RETURN_UNAVAILABLE", summary
	end
	local data, reason = profileOwner:GetWritableData(player)
	if data == nil then
		return false, reason or "PROFILE_NOT_READY", summary
	end
	local storageSystem = require(script.Parent.Parent.Systems.BaseStorageSystem)
	if storageSystem:GetStorageForPlayer(player) == nil then
		return false, "STORAGE_NOT_READY", summary
	end
	local secured = world.GetSecuredWorldRecords(player.UserId)
	if type(secured) ~= "table" then
		return false, "INVALID_SECURED_WORLD", summary
	end
	local seen = {}
	for _, record in secured do
		local id, species = identity(record)
		local saved = if id then (ownedMap(data) or {})[id] else nil
		if
			id == nil
			or species == nil
			or seen[id]
			or type(saved) ~= "table"
			or saved.speciesId ~= species
			or type(record.Metadata) ~= "table"
			or record.Metadata.DurableOwnerUserId ~= player.UserId
			or Phase12Progress.MutationId(saved) ~= Phase12Progress.MutationId(record)
			or currentPending(player, id) ~= nil
		then
			return false, "SECURED_OWNERSHIP_INCONSISTENT", summary
		end
		seen[id] = true
		summary.worldSources += 1
	end
	if #secured > 0 then
		local result = self:ApplyLogoutOutcomes(player, nil, secured)
		if type(result) ~= "table" or result.ok ~= true then
			return false, if type(result) == "table" then result.code else "SECURED_COMMIT_FAILED", summary
		end
		for _, record in secured do
			local outcome = result.outcomes and result.outcomes[record.ItemId]
			if
				type(outcome) ~= "table"
				or outcome.durable ~= true
				or (outcome.action ~= "ReturnToAvailableSlot" and outcome.action ~= "PreserveOwnedUnassigned")
			then
				return false, "SECURED_WORLD_OUTCOME_INVALID", summary
			end
			local retired, retireReason = world.RetireSecuredWorld(record.ItemId, player.UserId)
			if not retired then
				return false, retireReason or "SECURED_WORLD_RETIRE_PENDING", summary
			end
			summary.retired += 1
			if outcome.action == "ReturnToAvailableSlot" then
				summary.returnedToSlots += 1
			else
				summary.preservedUnassigned += 1
			end
		end
	end
	-- A previous successful profile commit may have retired its world source
	-- before a transient display-bind failure. Re-read durable assignments and
	-- use the idempotent existing binder to finish that exact presentation.
	data, reason = profileOwner:GetWritableData(player)
	if data == nil then
		return false, reason or "PROFILE_NOT_READY", summary
	end
	for index = 1, Phase13Rules.GetCapacity(data) do
		local slotId = tostring(index)
		local slot = (slots(data) or {})[slotId]
		local id = if type(slot) == "table" then slot.brainrotId else nil
		if type(id) == "string" then
			local bound, bindReason = storageSystem:BindReturnedOwnedIndividual(player, slotId, id)
			if not bound then
				return false, bindReason or "OWNED_BIND_PENDING", summary
			end
		end
	end
	return true, nil, summary
end

-- Removes ownership synchronously, then publishes only after an existing
-- profile save confirmation covers the exact relinquishment revision. The
-- operation never writes storage directly and naturally coalesces into an
-- already-running ordered save.
function BankedBrainrotService:BeginConfirmedRelease(
	player: Player,
	record: any,
	onConfirmed: (any) -> (boolean, string?),
	onUnconfirmed: ((any) -> ())?
): any
	local individualId, speciesId = identity(record)
	if individualId == nil or speciesId == nil or type(onConfirmed) ~= "function" then
		return { ok = false, committed = false, code = "INVALID_RELEASE" }
	end
	local existing = currentPending(player, individualId)
	if existing ~= nil then
		return {
			ok = true,
			committed = true,
			code = "RELEASE_ALREADY_PENDING",
			revision = existing.Revision,
		}
	end
	local session = profileOwner:GetSessionHandle(player)
	if session == nil then
		return { ok = false, committed = false, code = "PROFILE_NOT_READY" }
	end
	local commit = profileOwner:CommitMutation(player, function(data)
		local owned = ownedMap(data)
		local saved = if owned then owned[individualId] else nil
		if type(saved) ~= "table" or saved.speciesId ~= speciesId then
			return false, { ok = false, committed = false, code = "OWNERSHIP_INCONSISTENT" }
		end
		clearSlotReferences(data, individualId)
		owned[individualId] = nil
		return true, { ok = true, committed = true, code = "RELEASE_PENDING" }
	end)
	if type(commit) ~= "table" or commit.ok ~= true or commit.committed ~= true then
		return commit
	end
	local operation = {
		Player = player,
		IndividualId = individualId,
		SpeciesId = speciesId,
		Session = session,
		Revision = commit.revision,
		Status = "Pending",
		OnConfirmed = onConfirmed,
		OnUnconfirmed = onUnconfirmed,
	}
	local byId = pendingReleases[player]
	if byId == nil then
		byId = {}
		pendingReleases[player] = byId
	end
	byId[individualId] = operation
	log:Info("BankedReleasePending userId=%d individualId=%s revision=%d", player.UserId, individualId, commit.revision)
	local saveRequest = profileOwner:RequestSave(player, "PriorityBankedRelease:" .. individualId)
	local saveRequestCode = if type(saveRequest) == "table" then saveRequest.code else "SAVE_REQUEST_FAILED"
	if type(saveRequest) ~= "table" or saveRequest.ok ~= true then
		operation.SaveRequestCode = saveRequestCode
	end
	return {
		ok = true,
		committed = true,
		code = "RELEASE_PENDING",
		revision = commit.revision,
		saveRequestCode = operation.SaveRequestCode or saveRequestCode,
	}
end

-- Called from the existing shared lifecycle heartbeat. Confirmed releases are
-- retried as bounded publication work without issuing another save or changing
-- ownership again.
function BankedBrainrotService:ProcessConfirmedReleases()
	for _, byId in pendingBanks do
		for _, operation in byId do
			if operation.Status == "Confirmed" then
				processPendingBanks(operation.Player, operation.Revision)
			elseif operation.Status == "Recovering" and operation.RecoveryPlayer then
				self:ReconcilePendingBanksOnAcquire(operation.RecoveryPlayer)
			end
		end
	end
	for _, byId in pendingReleases do
		for _, operation in table.clone(byId) do
			if operation.Status == "Confirmed" then
				attemptConfirmedPublication(operation)
			end
		end
	end
end

function BankedBrainrotService:TryCommitSale(
	player: Player,
	record: any,
	amount: number,
	strictQuote: boolean?,
	quoteCatalog: any?
): any
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or math.abs(amount) == math.huge then
		return { ok = false, committed = false, code = "INVALID_AMOUNT" }
	end
	if self:IsBankPending(player, record and record.ItemId) then
		return { ok = false, code = "BANK_SAVE_PENDING" }
	end
	local data, reason = profileOwner:GetWritableData(player)
	if not data then
		return { ok = false, committed = false, code = reason or "PROFILE_NOT_READY" }
	end
	local individualId = record and record.ItemId
	local speciesId = record and record.BrainrotId
	if type(individualId) ~= "string" or type(speciesId) ~= "string" then
		return { ok = false, committed = false, code = "INVALID_IDENTITY" }
	end
	if currentPending(player, individualId) ~= nil then
		return { ok = false, committed = false, code = "RELEASE_PENDING" }
	end
	local owned = ownedMap(data)
	local saved = if owned then owned[individualId] else nil
	if saved == nil then
		local metadata = record.Metadata
		if type(metadata) == "table" and metadata.DurableOwnerUserId == player.UserId then
			return { ok = false, committed = false, code = "OWNERSHIP_INCONSISTENT" }
		end
		return { ok = false, committed = false, code = "BANK_FIRST" }
	end
	if type(saved) ~= "table" or saved.speciesId ~= speciesId then
		return { ok = false, committed = false, code = "OWNERSHIP_INCONSISTENT" }
	end
	local mutationId = Phase12Progress.MutationId(saved)
	if mutationId ~= Phase12Progress.MutationId(record) then
		return { ok = false, committed = false, code = "MUTATION_CHANGED" }
	end
	if saved.favourite == true then
		return { ok = false, committed = false, code = "FAVOURITE" }
	end
	-- Runtime profiles always validate canonical quotes. The optional strict
	-- flag also exercises that boundary under existing injected native fixtures;
	-- a false flag never bypasses the real profile owner.
	local effective = Phase12Rules.EffectiveValues(speciesId, mutationId)
	if quoteCatalog ~= nil then
		local definition = quoteCatalog.GetDefinition(speciesId)
		effective = if definition
			then { sellValue = definition.sellValue * Phase12Rules.MutationMultiplier(mutationId) }
			else nil
	end
	if (strictQuote == true or not injectedFixtureQuotes) and (effective == nil or effective.sellValue ~= amount) then
		return { ok = false, committed = false, code = "QUOTE_CHANGED" }
	end
	if assignedSlot(data, individualId) ~= nil then
		return { ok = false, committed = false, code = "STILL_BANKED" }
	end
	local function consumeOwned(currentData)
		local currentOwned = ownedMap(currentData)
		local current = if currentOwned then currentOwned[individualId] else nil
		if type(current) ~= "table" or current.speciesId ~= speciesId then
			return false, "OWNERSHIP_CHANGED"
		end
		if assignedSlot(currentData, individualId) ~= nil then
			return false, "STILL_BANKED"
		end
		if Phase12Progress.MutationId(current) ~= mutationId then
			return false, "MUTATION_CHANGED"
		end
		if current.favourite == true then
			return false, "FAVOURITE"
		end
		currentOwned[individualId] = nil
		return true, nil
	end
	if amount == 0 then
		return profileOwner:CommitMutation(player, function(currentData)
			local consumed, consumeReason = consumeOwned(currentData)
			return consumed,
				if consumed
					then { ok = true, committed = true, code = "Applied" }
					else { ok = false, committed = false, code = consumeReason }
		end)
	end
	local result = currency:TryCreditWithSource(player, amount, "BrainrotSale", consumeOwned)
	if result.committed then
		profileOwner:RequestSave(player, "BrainrotSale")
	end
	return result
end

-- The Phase 12 coordinator supplies authored Camp classification. This service
-- never guesses a base radius or creates a second region/ownership registry.
function BankedBrainrotService:ObserveCampState(player: Player, inCamp: boolean)
	if not profileOwner:IsWritable(player) then
		return
	end
	local handle = profileOwner:GetSessionHandle(player)
	if handle == nil then
		return
	end
	local state = expeditions[player]
	if state == nil or state.generation ~= handle.Generation then
		state = { generation = handle.Generation, inCamp = inCamp }
		expeditions[player] = state
		return
	end
	if state.inCamp == true and not inCamp then
		state.id = HttpService:GenerateGUID(false)
		state.returned = false
		state.haulCount, state.cashPerSecond, state.sellValue = 0, 0, 0
	elseif state.inCamp == false and inCamp and state.id ~= nil then
		state.returned = true
	end
	state.inCamp = inCamp
end

function BankedBrainrotService:SetCampClassifier(callback: any?)
	assert(callback == nil or type(callback) == "function", "Camp classifier must be a function")
	campClassifier = callback
end

function BankedBrainrotService:GetBankContext(player: Player): any?
	if campClassifier then
		local ok, inCamp = pcall(campClassifier, player)
		if ok and type(inCamp) == "boolean" then
			self:ObserveCampState(player, inCamp)
		end
	end
	local state = expeditions[player]
	if state and state.id and state.returned then
		return {
			id = state.id,
			returned = true,
			haulCount = state.haulCount,
			cashPerSecond = state.cashPerSecond,
			sellValue = state.sellValue,
		}
	end
	return nil
end

function BankedBrainrotService:SubscribeBankCommitted(callback: (Player, any) -> ()): any
	local key = {}
	bankListeners[key] = callback
	return {
		Disconnect = function()
			bankListeners[key] = nil
		end,
	}
end

-- Receipts are obtained from a successful BaseStorage commit once. Rejected
-- placements and stable restored/rebanked individuals have no such receipt.
function BankedBrainrotService:OnBankCommitted(player: Player, receipt: any?)
	if type(receipt) ~= "table" then
		return
	end
	local state = expeditions[player]
	local haul = receipt.expedition
	if state and type(haul) == "table" and state.id == haul.id then
		state.haulCount, state.cashPerSecond, state.sellValue = haul.haulCount, haul.cashPerSecond, haul.sellValue
	end
	local immutable = table.freeze(receipt)
	for _, callback in bankListeners do
		local ok, reason = pcall(callback, player, immutable)
		if not ok then
			log:Warn("First-bank presentation observer failed: %s", tostring(reason))
		end
	end
end

local function measurementOffers(player: Player): { any }
	if upgradeService == nil then
		upgradeService = require(script.Parent.UpgradeService)
	end
	return upgradeService:GetMeasurementOffers(player)
end

function BankedBrainrotService:GetProgressSnapshot(player: Player): any?
	local data = profileOwner:GetReadableData(player)
	if data == nil then
		return nil
	end
	local offers = measurementOffers(player)
	local chosenId = if type(data.Progression) == "table" then data.Progression.TrackedUpgradeId else nil
	local chosen, cheapest = nil, nil
	for _, offer in offers do
		if offer.offerId == chosenId then
			chosen = offer
		end
		if
			offer.ready
			and offer.prerequisitesSatisfied
			and not offer.owned
			and (
				cheapest == nil
				or offer.price < cheapest.price
				or (offer.price == cheapest.price and offer.offerId < cheapest.offerId)
			)
		then
			cheapest = offer
		end
	end
	chosen = chosen or cheapest
	local wallet = if type(data.Economy) == "table" then data.Economy.Balance else 0
	local context = self:GetBankContext(player)
	local chosenDefinition = if chosen
		then require(game.ReplicatedStorage.Shared.Config.Upgrades).Get(chosen.offerId)
		else nil
	return {
		species = table.clone(data.Collection.Species or {}),
		speciesMutations = table.clone(data.Collection.SpeciesMutations or {}),
		mutations = table.clone(data.Collection.Mutations or {}),
		personalBest = table.clone(data.Progression.ExpeditionBest or {}),
		expedition = context,
		trackedUpgrade = if chosen
			then {
				offerId = chosen.offerId,
				displayName = if chosenDefinition then chosenDefinition.displayName else chosen.offerId,
				price = chosen.price,
				wallet = wallet,
				shortfall = math.max(0, chosen.price - wallet),
				owned = chosen.owned,
				eligible = chosen.ready and chosen.prerequisitesSatisfied and not chosen.owned,
			}
			else nil,
	}
end

function BankedBrainrotService:TrackUpgrade(player: Player, offerId: any): any
	if type(offerId) ~= "string" then
		return { ok = false, code = "INVALID_OFFER" }
	end
	local Upgrades = require(game.ReplicatedStorage.Shared.Config.Upgrades)
	local offer = Upgrades.Get(offerId)
	if
		offer == nil
		or offer.currencyId ~= "Cash"
		or offer.releaseStatus ~= "Released"
		or offer.definitionStatus ~= "Complete"
	then
		return { ok = false, code = "UNAVAILABLE_OFFER" }
	end
	return profileOwner:CommitMutation(player, function(data)
		if data.Progression.TrackedUpgradeId == offer.id then
			return false, { ok = true, code = "UNCHANGED" }
		end
		data.Progression.TrackedUpgradeId = offer.id
		return true, { ok = true, code = "TRACKED", offerId = offer.id }
	end)
end

function BankedBrainrotService:_ResetForTests(options: any?)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(pendingReleases)
	table.clear(initialLocationsReconciled)
	table.clear(expeditions)
	table.clear(bankListeners)
	campClassifier = nil
	started = false
	self:Init(options)
	-- Existing native integration tests explicitly install trusted profile/catalog
	-- fixtures. No client endpoint accepts this switch or supplies a catalogue.
	injectedFixtureQuotes = options ~= nil
end

function BankedBrainrotService:_TestConfirmSave(player: Player, savedRevision: number, currentRevision: number?)
	onSaveConfirmed(player, savedRevision, currentRevision or savedRevision)
end

function BankedBrainrotService:_TestGetPending(player: Player, individualId: string): any?
	return currentPending(player, individualId)
end

processPendingBanks = function(player, savedRevision)
	local byId = pendingBanks[player.UserId]
	if not byId then
		return
	end
	for id, operation in table.clone(byId) do
		if savedRevision >= operation.Revision and profileOwner:IsCurrentSessionHandle(operation.Session) then
			operation.Status = "Confirmed"
			local ok, result = pcall(operation.OnConfirmed)
			if ok and result ~= false then
				byId[id] = nil
			end
		end
	end
	if next(byId) == nil then
		pendingBanks[player.UserId] = nil
	end
end
-- Server-only physical owners supply the exact local departure pose. Keep it
-- before a save yields or a successful deposit discards its source visual.
function BankedBrainrotService:CapturePendingBankSourcePose(
	player: Player,
	record: any,
	operationId: string
): (boolean, CFrame?)
	local carry = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
	local cargo = require(script.Parent.CartCargoService)
	local carryOk, carryPose = carry.GetPendingBankSourcePose(player, record, operationId)
	local cargoOk, cargoPose = cargo:GetPendingBankSourcePose(player, record, operationId)
	if not carryOk or not cargoOk or (carryPose ~= nil and cargoPose ~= nil) then
		return false, nil
	end
	local pose = cargoPose or carryPose
	if pose == nil then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			pose = root.CFrame
		end
	end
	return true, pose
end

-- A newly acquired lease supplies authoritative evidence for a previous
-- disconnected session's uncertain first bank. Never infer this from a failed
-- save response, and never replay an old plot/UI celebration in the new session.
function BankedBrainrotService:ReconcilePendingBanksOnAcquire(player: Player): any
	local byId = pendingBanks[player.UserId]
	if not byId then
		return { ok = true, confirmed = 0, released = 0 }
	end
	local data = profileOwner:GetReadableData(player)
	local session = profileOwner:GetSessionHandle(player)
	if not data or not session or not profileOwner:IsCurrentSessionHandle(session) then
		return { ok = false, code = "PROFILE_NOT_READY" }
	end
	local world = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
	local carry = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
	local cargo = require(script.Parent.CartCargoService)
	local confirmed, released = 0, 0
	for id, operation in table.clone(byId) do
		if operation.Player ~= player and not profileOwner:IsCurrentSessionHandle(operation.Session) then
			operation.Status = "Recovering"
			operation.RecoveryPlayer = player
			if operation.Player.Parent == game:GetService("Players") then
				continue
			end
			local saved = data.Collection.BrainrotInstances[id]
			local ok = false
			local savedMatches = saved
				and saved.speciesId == operation.Record.BrainrotId
				and Phase12Progress.MutationId(saved) == Phase12Progress.MutationId(operation.Record)
			if not savedMatches and saved ~= nil then
				continue
			end
			if saved == nil and operation.ReleasePose == nil then
				local valid, pose =
					self:CapturePendingBankSourcePose(operation.Player, operation.Record, operation.OperationId)
				if not valid or pose == nil then
					continue
				end
				operation.ReleasePose = pose
			end
			-- Its reservation remains counted while the known source is consumed.
			-- Acquired absence then moves the same identity to the ordinary local
			-- release queue; it never grants spawn credit or teleports to a fallback.
			if
				saved == nil
				and not world.CanAbortPendingBankToFreshRelease(
					operation.Record,
					operation.OperationId,
					operation.ReleasePose
				)
			then
				continue
			end
			if
				not carry.ReconcilePendingBankSource(operation.Player, operation.Record, operation.OperationId)
				or not cargo:ReconcilePendingBankSource(operation.Player, operation.Record, operation.OperationId)
			then
				continue
			end
			if savedMatches then
				ok = world.ConfirmPendingBank(operation.Record, operation.OperationId)
				if ok then
					confirmed += 1
				end
			elseif saved == nil then
				ok =
					world.AbortPendingBankToFreshRelease(operation.Record, operation.OperationId, operation.ReleasePose)
				if ok then
					released += 1
				end
			end
			if ok then
				byId[id] = nil
			end
		end
	end
	if next(byId) == nil then
		pendingBanks[player.UserId] = nil
	end
	return { ok = true, confirmed = confirmed, released = released }
end
function BankedBrainrotService:HasPendingBank(player: Player): boolean
	local byId = pendingBanks[player.UserId]
	if not byId then
		return false
	end
	for _, operation in byId do
		if operation then
			return true
		end
	end
	return false
end

function BankedBrainrotService:IsBankPending(playerOrId: any, id: any): boolean
	local userId = if type(playerOrId) == "number" then playerOrId elseif playerOrId then playerOrId.UserId else nil
	local byId = userId and pendingBanks[userId]
	return byId ~= nil and byId[id] ~= nil
end
function BankedBrainrotService:RegisterPendingBank(
	player: Player,
	record: any,
	revision: number,
	onConfirmed: any,
	releasePose: CFrame?
): any
	local session = profileOwner:GetSessionHandle(player)
	if
		not session
		or type(record) ~= "table"
		or type(record.ItemId) ~= "string"
		or type(revision) ~= "number"
		or type(onConfirmed) ~= "function"
	then
		return { ok = false, code = "INVALID_PENDING_BANK" }
	end
	local byId = pendingBanks[player.UserId] or {}
	pendingBanks[player.UserId] = byId
	local existing = byId[record.ItemId]
	if existing then
		return { ok = true, state = "Saving", operationId = existing.OperationId, revision = existing.Revision }
	end
	if releasePose == nil then
		local valid, pose = self:CapturePendingBankSourcePose(player, record, "Bank:" .. record.ItemId)
		if valid then
			releasePose = pose
		end
	end
	byId[record.ItemId] = {
		ReleasePose = releasePose,
		Player = player,
		Record = record,
		Revision = revision,
		Session = session,
		Status = "Pending",
		OperationId = "Bank:" .. record.ItemId,
		OnConfirmed = onConfirmed,
	}
	if profileOwner:IsRevisionConfirmed(player, revision) then
		processPendingBanks(player, revision)
	else
		profileOwner:RequestSave(player, "FirstBank:" .. record.ItemId)
	end
	return {
		ok = true,
		state = if self:IsBankPending(player, record.ItemId) then "Saving" else "Confirmed",
		operationId = "Bank:" .. record.ItemId,
		revision = revision,
	}
end

return BankedBrainrotService
