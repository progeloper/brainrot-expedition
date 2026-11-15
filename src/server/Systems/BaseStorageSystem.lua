--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local SlotPresentation = require(ReplicatedStorage.Shared.Utility.BaseSlotPresentation)
local BaseStorage = require(script.Parent.Parent.Classes.BaseStorage)
local PlayerBaseSystem = require(script.Parent.PlayerBaseSystem)
local CartService = require(script.Parent.Parent.Services.CartService)
local CartCargoService = require(script.Parent.Parent.Services.CartCargoService)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local BrainrotDisplayMetadata = require(ReplicatedStorage.Shared.Utility.BrainrotDisplayMetadata)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local Phase12Progress = require(script.Parent.Parent.Data.Phase12Progress)
local PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)
local BankedBrainrotService = require(script.Parent.Parent.Services.BankedBrainrotService)
local World = require(script.Parent.DevelopmentBrainrotSpawner)

local EXPECTED_SLOT_COUNT = 48
local PLACEMENT_GAP = require(game:GetService("ReplicatedStorage").Shared.Config.PlaytestExact).BodyGroundClearanceStuds
local log = Logger.new("BaseStorageSystem")
local Trace = require(script.Parent.Parent.Utility.BrainrotDiagnostics)
local BaseStorageSystem = {}
local started = false
local lifecycleConnection: any = nil
local profileReadyConnection: any = nil
local profileOwner: any? = PlayerDataService
local bankClock = function(): number
	return DateTime.now().UnixTimestampMillis / 1000
end
local registered: { [Model]: any } = {}
local assignments: { [Model]: any } = {}
local busyCarts: { [Model]: boolean } = {}
local busyStorage: { [any]: boolean } = {}
local observers: { [any]: any } = {}
local notifying = false
local PLATFORM_TAG = "BrainrotStoragePlatform"
local platformSlots: { [BasePart]: any } = {}
local preparedPlacements: { [any]: any } = {}
local restoreAssignment: (any, number?) -> ()

local function publishOccupancy(current: any)
	for _, slot in registered[current.Storage.Base] or {} do
		local record = current.Storage:GetPlatformRecord(slot.Index)
		slot.Platform:SetAttribute("LockedSlot", slot.Index > current.Storage:GetSlotCapacity())
		slot.Platform:SetAttribute("StorageOccupied", record ~= nil)
		slot.Platform:SetAttribute("StorageItemId", if record then record.ItemId else nil)
		slot.Platform:SetAttribute("StorageBrainrotId", if record then record.BrainrotId else nil)
	end
end

-- Domain-specific, synchronous read-only observers. Never yield or mutate inventory.
function BaseStorageSystem:ObserveStorage(observer: any): () -> ()
	local key = {}
	observers[key] = observer
	Trace.Emit("BOOT", "storage_observer_registered", function()
		return {
			observer = Trace.Id(key),
			onBound = observer.OnBound ~= nil,
			onChanging = observer.OnChanging ~= nil,
			onCommitted = observer.OnCommitted ~= nil,
			onReleasing = observer.OnReleasing ~= nil,
		}
	end)
	return function()
		observers[key] = nil
		Trace.Forget(key)
	end
end

local function notify(kind: string, current: any, revision: number?, snapshot: any?)
	-- Presentation mirrors never decide ownership or slot availability.
	local mirrored, mirrorError = pcall(publishOccupancy, current)
	if not mirrored then
		log:Warn("Storage occupancy mirror failed: %s", tostring(mirrorError))
	end
	Trace.Emit("5C", "notification_enter", function()
		local f = Trace.Fields(current.Player, nil, current.Storage)
		f.kind, f.snapshotCount, f.notificationAtMs =
			kind, snapshot and #snapshot or "none", math.floor(os.clock() * 1000)
		f.changeTimestampSource = "income_callback_samples_existing_nowMs"
		return f
	end)
	local wasNotifying = notifying
	notifying = true
	for _, observer in observers do
		local callback = observer[kind]
		if callback then
			Trace.Emit("5C", "observer_enter", function()
				return {
					kind = kind,
					storage = Trace.Id(current.Storage),
					storageRevision = revision or "none",
				}
			end)
			local ok, failure = pcall(callback, current.Player, current.Storage, revision, snapshot)
			Trace.Emit("5C", "observer_exit", {
				kind = kind,
				result = if ok then "returned" else "exception",
				error = if ok then "none" else tostring(failure),
			}, not ok)
			if not ok then
				log:Warn("Storage %s observer failed BaseId=%s: %s", kind, current.Storage.BaseId, tostring(failure))
			end
		end
	end
	notifying = wasNotifying
	Trace.Emit("5C", "notification_exit", { kind = kind, result = "dispatch_complete", notifying = notifying })
end

local function freezeSnapshot(value: any): any
	for _, child in value do
		if type(child) == "table" then
			freezeSnapshot(child)
		end
	end
	return table.freeze(value)
end

local function validSlot(base: Model, slot: BaseStorage.SlotDescriptor): boolean
	return base:IsDescendantOf(Workspace)
		and slot.Platform.Parent == base
		and slot.Marker.Parent == slot.Platform
		and slot.Marker.Name == "BrainrotPlacement"
		and (slot.Platform:GetAttribute("SlotIndex") or tonumber(slot.Platform.Name:match("^Slot_(%d+)$"))) == slot.Index
		and (slot.Marker:IsA("Attachment") or slot.Marker:IsA("BasePart"))
end

local function collectSlots(base: Model): (any?, string?)
	local descriptors = {}
	for _, platform in base:GetChildren() do
		local namedIndex = tonumber(platform.Name:match("^Slot_(%d+)$"))
		local attributeIndex = platform:GetAttribute("SlotIndex")
		local index = attributeIndex or namedIndex
		if index == nil then
			continue
		end
		local path = platform:GetFullName()
		if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > EXPECTED_SLOT_COUNT then
			return nil, string.format("%s invalid slot index %s", path, tostring(index))
		end
		if namedIndex and namedIndex ~= index then
			return nil, string.format("%s conflicting slot index %s", path, tostring(index))
		end
		if descriptors[index] ~= nil or not platform:IsA("BasePart") then
			return nil, string.format("%s duplicate/unsupported slot %d", path, index)
		end
		local marker = platform:FindFirstChild("BrainrotPlacement")
		if marker == nil or not (marker:IsA("Attachment") or marker:IsA("BasePart")) then
			return nil, string.format("%s slot %d needs BrainrotPlacement Attachment/Part", path, index)
		end
		local slot = { Index = index, Platform = platform, Marker = marker }
		if not validSlot(base, slot) then
			return nil, string.format("%s slot %d marker belongs to another base/platform", path, index)
		end
		descriptors[index] = table.freeze(slot)
	end
	for index = 1, EXPECTED_SLOT_COUNT do
		if descriptors[index] == nil then
			return nil, string.format("%s missing slot %d", base:GetFullName(), index)
		end
	end
	return table.freeze(descriptors), nil
end

local function registerBase(base: Model)
	if registered[base] ~= nil then
		return
	end
	local slots, reason = collectSlots(base)
	registered[base] = slots or false
	Trace.Emit("BOOT", "slots_registered", function()
		return {
			base = base,
			baseId = base:GetAttribute("BaseId"),
			slotCount = slots and #slots or 0,
			reason = reason or "ready",
		}
	end, slots == nil)
	if slots then
		for index, slot in slots do
			platformSlots[slot.Platform] = { Base = base, Slot = slot }
			CollectionService:AddTag(slot.Platform, PLATFORM_TAG)
			slot.Platform:SetAttribute("StorageOccupied", false)
			Trace.Emit("BOOT", "slot_inventory", function()
				return {
					baseId = base:GetAttribute("BaseId"),
					slot = index,
					platform = slot.Platform,
					marker = slot.Marker,
					valid = validSlot(base, slot),
					occupancy = "unbound",
				}
			end)
		end
	end
	if not slots then
		log:Warn(
			"Storage disabled for BaseId=%s: %s",
			tostring(base:GetAttribute("BaseId")),
			reason or "invalid platforms"
		)
	end
end

local function sameAssignment(left: any, right: any): boolean
	return left ~= nil
		and right ~= nil
		and left.Player == right.Player
		and left.Base == right.Base
		and left.Generation == right.Generation
end

local function releaseAssignment(player: Player, base: Model, handle: any?)
	local current = assignments[base]
	Trace.Emit("5C", "storage_release_enter", function()
		return {
			userId = player.UserId,
			base = base,
			assignmentMatches = current ~= nil and current.Player == player,
		}
	end)
	if
		current == nil
		or current.Player ~= player
		or (handle ~= nil and not sameAssignment(current.Assignment, handle))
	then
		return
	end
	notify("OnReleasing", current)
	-- Invalidate lookup and storage before ownership can offer this physical base again.
	assignments[base] = nil
	current.Storage:Destroy()
	publishOccupancy(current)
	if current.CreatedContainer and current.Container and #current.Container:GetChildren() == 0 then
		current.Container:Destroy()
	end
end

local function bindAssignment(player: Player, base: Model, suppliedHandle: any?)
	if not PlayerBaseSystem:IsOwner(player, base) then
		return
	end
	local handle = suppliedHandle or PlayerBaseSystem:GetAssignment(player)
	if handle == nil or not PlayerBaseSystem:IsCurrentAssignment(handle) then
		return
	end
	local slots = registered[base]
	if not slots then
		return
	end
	local current = assignments[base]
	if
		current
		and current.Player == player
		and current.Storage:IsActive()
		and sameAssignment(current.Assignment, handle)
	then
		return
	end
	if current then
		releaseAssignment(current.Player, base)
	end
	local profileData = if profileOwner then profileOwner:GetWritableData(player) else nil
	if profileOwner and profileData == nil then
		return
	end
	-- Both ProfileReady and assignment callbacks can reach this binder before
	-- PlayerWorldLifecycle. Resolve crash-retained ownership before any display
	-- or income source is exposed, once per exact profile session. Legacy isolated
	-- non-session fixture adapters have no persistent acquisition to reconcile.
	if profileOwner and profileOwner.GetSessionHandle and profileOwner.IsCurrentSessionHandle then
		local result = BankedBrainrotService:ReconcileInitialOwnedLocations(player, profileOwner)
		if result.ok ~= true then
			log:Warn(
				"Initial owned-location reconciliation blocked userId=%d code=%s",
				player.UserId,
				tostring(result.code)
			)
			return
		end
	end
	assignments[base] = {
		Player = player,
		Assignment = handle,
		Storage = BaseStorage.new(base, player.UserId, slots, profileData),
		Ready = false,
	}
	restoreAssignment(assignments[base])
	if assignments[base] == nil or not sameAssignment(assignments[base].Assignment, handle) then
		return
	end
	assignments[base].Ready = true
	Trace.Emit("5C", "storage_bound", function()
		return Trace.Fields(player, nil, assignments[base].Storage)
	end)
	notify("OnBound", assignments[base])
end

function BaseStorageSystem:GetStorageForPlayer(player: Player): any?
	local base = PlayerBaseSystem:GetBase(player)
	local current = if base then assignments[base] else nil
	if
		current
		and current.Player == player
		and current.Storage:IsActive()
		and current.Ready == true
		and PlayerBaseSystem:IsCurrentAssignment(current.Assignment)
		and PlayerBaseSystem:IsOwner(player, base :: Model)
	then
		return current.Storage
	end
	return nil
end

function BaseStorageSystem:GetBindingHandle(player: Player): any?
	local base = PlayerBaseSystem:GetBase(player)
	local current = if base then assignments[base] else nil
	if
		current == nil
		or current.Player ~= player
		or current.Ready ~= true
		or not current.Storage:IsActive()
		or not PlayerBaseSystem:IsCurrentAssignment(current.Assignment)
	then
		return nil
	end
	return current.Assignment
end

function BaseStorageSystem:EnsureBound(player: Player, base: Model, assignmentHandle: any): (boolean, string?)
	if
		assignmentHandle == nil
		or assignmentHandle.Player ~= player
		or assignmentHandle.Base ~= base
		or not PlayerBaseSystem:IsCurrentAssignment(assignmentHandle)
	then
		return false, "STALE_ASSIGNMENT"
	end
	bindAssignment(player, base, assignmentHandle)
	local current = assignments[base]
	if
		current ~= nil
		and current.Player == player
		and current.Ready == true
		and sameAssignment(current.Assignment, assignmentHandle)
	then
		return true, nil
	end
	return false,
		if profileOwner and profileOwner:GetWritableData(player) == nil then "PROFILE_NOT_READY" else "BIND_FAILED"
end

-- Server-only read access for physical presentation owners. The descriptors and
-- their contained slot records are frozen during registration; inventory authority
-- remains in BaseStorage.
function BaseStorageSystem:GetRegisteredPlatforms(base: Model): any?
	local slots = registered[base]
	return if type(slots) == "table" then slots else nil
end

-- Resolve only registered physical brainrot slots, never a slab/cart platform,
-- colour, arbitrary descendant name or a client-supplied base identity.
function BaseStorageSystem:ResolvePlatform(player: Player, platform: any): (any?, any?, string?)
	if typeof(platform) ~= "Instance" or not platform:IsA("BasePart") then
		return nil, nil, "INVALID_PLATFORM"
	end
	local registeredSlot = platformSlots[platform]
	local storage = self:GetStorageForPlayer(player)
	if not registeredSlot then
		return nil, nil, "INVALID_PLATFORM"
	end
	if not storage or storage.Base ~= registeredSlot.Base then
		return nil, nil, "NOT_OWNER"
	end
	if storage:IsProfileBacked() and not profileOwner:IsWritable(player) then
		return nil, nil, "PROFILE_NOT_READY"
	end
	if not storage:IsValidPlatformId(registeredSlot.Slot.Index) then
		return nil, nil, "LOCKED_SLOT"
	end
	local assignment = self:GetBindingHandle(player)
	if
		assignment == nil
		or not SlotPresentation.CanUseSlot(
			storage.Base,
			registeredSlot.Slot.Index,
			player.UserId,
			assignment.Generation
		)
	then
		return nil, nil, "LOCKED_SLOT"
	end
	if not validSlot(storage.Base, registeredSlot.Slot) then
		return nil, nil, "INVALID_PLATFORM"
	end
	return registeredSlot.Slot, storage, nil
end

function BaseStorageSystem:GetPlatformRecord(base: Model, platform: BasePart): any?
	local binding, current = platformSlots[platform], assignments[base]
	if not binding or binding.Base ~= base or not current then
		return nil
	end
	return current.Storage:GetPlatformRecord(binding.Slot.Index)
end

-- Server-only exact-slot transfer used by the existing carry interaction. The
-- pre-change notification settles the outgoing occupant at this boundary; the
-- platform ledger itself is never cleared or moved with the individual.
function BaseStorageSystem:TryRemoveFromPlatform(player: Player, platform: any, expectedItemId: any): (any?, string?)
	if notifying then
		return nil, "BUSY"
	end
	local slot, storage, reason = self:ResolvePlatform(player, platform)
	if not slot or not storage then
		return nil, reason
	end
	if BankedBrainrotService:IsBankPending(player, expectedItemId) then
		return nil, "BANK_SAVE_PENDING"
	end
	if busyStorage[storage] then
		return nil, "BUSY"
	end
	local mutationToken
	mutationToken, reason = storage:TryBeginPlatformMutation(slot.Index)
	if not mutationToken then
		return nil, reason
	end
	local current = assignments[storage.Base]
	local before = storage:GetPlatformRecord(slot.Index)
	if
		current == nil
		or current.Player ~= player
		or before == nil
		or type(expectedItemId) ~= "string"
		or before.ItemId ~= expectedItemId
	then
		storage:EndPlatformMutation(slot.Index, mutationToken)
		return nil, if before == nil then "EMPTY" else "STALE_ID"
	end

	busyStorage[storage] = true
	local removed: any? = nil
	local ok, failure = xpcall(function()
		-- Income observes the still-occupied slot here and settles through the
		-- current server-time boundary before the occupant is cleared.
		notify("OnChanging", current)
		local display
		if storage:IsProfileBacked() then
			local mutation = profileOwner:CommitMutation(player, function(data)
				if not storage:IsBoundToProfile(data) then
					return false, { ok = false, code = "PROFILE_SOURCE_CHANGED" }
				end
				local record, currentDisplay, removeReason = storage:RemovePlatformRecord(slot.Index, expectedItemId)
				if not record then
					return false, { ok = false, code = removeReason or "SOURCE_CHANGED" }
				end
				return true, { ok = true, record = record, display = currentDisplay }
			end)
			if mutation.ok then
				removed, display = mutation.record, mutation.display
			else
				reason = mutation.code
			end
		else
			removed, display, reason = storage:RemovePlatformRecord(slot.Index, expectedItemId)
		end
		if removed == nil then
			return
		end
		require(ReplicatedStorage.Shared.Utility.BaseDisplayPlacement).ReleaseSupport(slot)
		notify("OnCommitted", current, storage:GetRevision(), freezeSnapshot(storage:GetSnapshot()))
		if display and display.Parent then
			local destroyed, destroyError = pcall(function()
				display:Destroy()
			end)
			if not destroyed then
				log:Warn(
					"Committed platform display cleanup %s failed: %s",
					tostring(expectedItemId),
					tostring(destroyError)
				)
			end
		end
	end, debug.traceback)
	busyStorage[storage] = nil
	storage:EndPlatformMutation(slot.Index, mutationToken)
	if not ok then
		log:Warn("Platform removal %s failed: %s", tostring(expectedItemId), tostring(failure))
		return nil, "INTERNAL_ERROR"
	end
	return removed, if removed then nil else reason
end

local function context(player: Player, cart: Model, expected: any): (any?, string?)
	if player.Parent ~= Players or cart.Parent == nil or CartService:GetCart(player) ~= cart then
		Trace.Emit("5C", "item_context_reject", function()
			return {
				reason = "player_or_cart_changed",
				playerPresent = player.Parent == Players,
				cartLive = cart.Parent ~= nil,
				currentCartMatches = CartService:GetCart(player) == cart,
			}
		end, true)
		return nil, "INVALID_CONTEXT"
	end
	local record = CartService:GetCartRecordByOwnerUserId(player.UserId)
	if record == nil or record.Model ~= cart or record.OwnerUserId ~= player.UserId then
		Trace.Emit("5C", "item_context_reject", {
			reason = "cart_record_or_owner",
			recordMatches = record ~= nil and record.Model == cart,
			cartOwner = record and record.OwnerUserId or "none",
		}, true)
		return nil, "INVALID_CONTEXT"
	end
	local base = PlayerBaseSystem:GetBase(player)
	if base == nil or not PlayerBaseSystem:IsOwner(player, base) then
		Trace.Emit("5C", "item_context_reject", { reason = "base_missing_or_not_owned", base = base or "none" }, true)
		return nil, "INVALID_CONTEXT"
	end
	if registered[base] == false then
		Trace.Emit("5C", "item_context_reject", { reason = "platform_registration_failed", base = base }, true)
		return nil, "INVALID_PLATFORM"
	end
	local current = assignments[base]
	if
		current == nil
		or current.Player ~= player
		or current.Storage ~= expected
		or not current.Storage:IsActive()
		or current.Storage.OwnerUserId ~= player.UserId
		or current.Storage.BaseId ~= base:GetAttribute("BaseId")
	then
		Trace.Emit("5C", "item_context_reject", function()
			return {
				reason = "storage_assignment_changed",
				assignmentPresent = current ~= nil,
				playerMatches = current ~= nil and current.Player == player,
				storageMatches = current ~= nil and current.Storage == expected,
				active = current ~= nil and current.Storage:IsActive(),
				owner = current and current.Storage.OwnerUserId or "none",
				expectedStorage = Trace.Id(expected),
				actualStorage = Trace.Id(current and current.Storage),
				baseId = base:GetAttribute("BaseId"),
				storedBaseId = current and current.Storage.BaseId or "none",
			}
		end, true)
		return nil, "INVALID_CONTEXT"
	end
	if current.Storage:IsProfileBacked() and not profileOwner:IsWritable(player) then
		return nil, "PROFILE_NOT_READY"
	end
	return current, nil
end

local function containerFor(current: any): Folder
	if current.Container then
		assert(current.Container.Parent == current.Storage.Base, "Storage display container moved")
		return current.Container
	end
	local existing = current.Storage.Base:FindFirstChild("StoredBrainrots")
	if existing then
		assert(existing:IsA("Folder"), "StoredBrainrots must be a Folder")
		current.Container = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = "StoredBrainrots"
		folder.Parent = current.Storage.Base
		current.Container = folder
		current.CreatedContainer = true
	end
	return current.Container
end

local function placeDisplayAtSlot(display: Model, slot: BaseStorage.SlotDescriptor): (any, any)
	return require(ReplicatedStorage.Shared.Utility.BaseDisplayPlacement).Place(display, slot)
end

local function prepareDisplay(item: any, slot: BaseStorage.SlotDescriptor): Model?
	Trace.Emit(
		"5C",
		"display_prepare_enter",
		{ itemId = item.ItemId, species = item.BrainrotId, slot = slot.Index, marker = slot.Marker }
	)
	local display = CartCargoService:CreateItemVisual(item.BrainrotId)
	if display == nil then
		return nil
	end
	local ok, failure = pcall(function()
		display.Name = "Stored_" .. item.ItemId
		display:SetAttribute("ItemId", item.ItemId)
		display:SetAttribute("BrainrotId", item.BrainrotId)
		display:SetAttribute("SlotIndex", slot.Index)
		BrainrotDisplayMetadata.SetIdentity(display, item)
		for _, part in display:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
		local placement, size = placeDisplayAtSlot(display, slot)
		Trace.Emit("5C", "display_prepare_exit", function()
			return {
				display = display,
				markerTransform = placement,
				boundsSize = size,
				calculatedPivot = display:GetPivot(),
				actualPivot = display:GetPivot(),
				anchored = true,
				canCollide = false,
				result = "prepared",
			}
		end)
	end)
	if not ok then
		Trace.Emit("5C", "display_prepare_error", { error = tostring(failure), committed = false }, true)
		display:Destroy()
		log:Warn("Display preparation failed for %s: %s", item.ItemId, tostring(failure))
		return nil
	end
	return display
end

restoreAssignment = function(current: any, onlySlotIndex: number?)
	local storage = current.Storage
	if not profileOwner then
		return
	end
	local profileData = profileOwner:GetReadableData(current.Player)
	if
		not storage:IsProfileBacked()
		or not storage:IsBoundToProfile(profileData)
		or type(profileData.Collection) ~= "table"
		or type(profileData.Collection.BrainrotInstances) ~= "table"
	then
		return
	end
	local owned = profileData.Collection.BrainrotInstances
	for _, slot in registered[storage.Base] do
		if onlySlotIndex ~= nil and slot.Index ~= onlySlotIndex then
			continue
		end
		if assignments[storage.Base] ~= current or not PlayerBaseSystem:IsCurrentAssignment(current.Assignment) then
			return
		end
		local slotData = profileData.Base.Slots[tostring(slot.Index)]
		local individualId = slotData and slotData.brainrotId
		if type(individualId) ~= "string" then
			continue
		end
		if not storage:IsValidPlatformId(slot.Index) then
			-- Keep legacy profile and exact earnings untouched; an unavailable slot is not inventory.
			log:Warn(
				"Saved individual %s retained in unavailable slot %d; capacity=%d",
				individualId,
				slot.Index,
				storage:GetSlotCapacity()
			)
			continue
		end
		local saved = owned[individualId]
		if type(saved) ~= "table" or type(saved.speciesId) ~= "string" then
			continue
		end
		local item = {
			mutationId = Phase12Progress.MutationId(saved),
			ItemId = individualId,
			BrainrotId = saved.speciesId,
			Metadata = if type(saved.metadata) == "table" then saved.metadata else {},
		}
		local display = prepareDisplay(item, slot)
		if assignments[storage.Base] ~= current or not PlayerBaseSystem:IsCurrentAssignment(current.Assignment) then
			if display then
				display:Destroy()
			end
			return
		end
		if display then
			display.Parent = containerFor(current)
		end
		local bound, reason = storage:BindRestoredRecord(slot.Index, item, display, onlySlotIndex ~= nil)
		if not bound then
			if display then
				display:Destroy()
			end
			log:Warn("Saved slot %d restoration rejected: %s", slot.Index, tostring(reason))
		elseif display then
			require(ReplicatedStorage.Shared.Utility.BaseDisplayPlacement).CommitSupport(display, slot)
			BrainrotDisplayMetadata.Apply(display, item, BrainrotDisplayConfig.States.Deposited, nil)
		else
			log:Warn("Saved individual %s (%s) retained without a display asset", individualId, saved.speciesId)
		end
	end
end

-- Death/reset has already committed this exact owned individual to a logical
-- slot. Bind that source once through the existing display/income boundary;
-- this is not another deposit, ownership grant, or profile mutation.
function BaseStorageSystem:BindReturnedOwnedIndividual(
	player: Player,
	slotId: string,
	individualId: string
): (boolean, string?)
	local storage = self:GetStorageForPlayer(player)
	local slotIndex = tonumber(slotId)
	if not storage or not storage:IsValidPlatformId(slotIndex) then
		return false, "STORAGE_NOT_READY"
	end
	local current = assignments[storage.Base]
	if not current or not PlayerBaseSystem:IsCurrentAssignment(current.Assignment) then
		return false, "STALE_ASSIGNMENT"
	end
	local existing = storage:GetPlatformRecord(slotIndex)
	if existing then
		return existing.ItemId == individualId,
			if existing.ItemId == individualId then "ALREADY_BOUND" else "SOURCE_CHANGED"
	end
	local data = profileOwner and profileOwner:GetReadableData(player)
	if not storage:IsBoundToProfile(data) or data.Base.Slots[slotId].brainrotId ~= individualId then
		return false, "PROFILE_SOURCE_CHANGED"
	end
	if notifying or busyStorage[storage] then
		return false, "BUSY"
	end
	local token, reason = storage:TryBeginPlatformMutation(slotIndex)
	if not token then
		return false, reason
	end
	busyStorage[storage] = true
	local bound = false
	local ok, failure = xpcall(function()
		notify("OnChanging", current)
		restoreAssignment(current, slotIndex)
		local record = storage:GetPlatformRecord(slotIndex)
		bound = record ~= nil and record.ItemId == individualId
		if bound then
			notify("OnCommitted", current, storage:GetRevision(), freezeSnapshot(storage:GetSnapshot()))
		end
	end, debug.traceback)
	busyStorage[storage] = nil
	storage:EndPlatformMutation(slotIndex, token)
	if not ok then
		log:Warn("Committed owned return binding failed individualId=%s: %s", individualId, tostring(failure))
		return false, "RESTORE_FAILED"
	end
	return bound, if bound then nil else "SOURCE_CHANGED"
end

-- A hot layout rebuild may move an anchored platform. Re-seat only known stored
-- displays at their canonical markers; their established visual scale is unchanged.
function BaseStorageSystem:RefreshPlatformDisplays(base: Model): boolean
	local current = assignments[base]
	local slots = registered[base]
	if not current or type(slots) ~= "table" or not current.Storage:IsActive() then
		return false
	end
	local container = base:FindFirstChild("StoredBrainrots")
	if not container or not container:IsA("Folder") then
		return true
	end
	for platformId, slot in slots do
		local record = current.Storage:GetPlatformRecord(platformId)
		if record then
			local display = container:FindFirstChild("Stored_" .. record.ItemId)
			if display and display:IsA("Model") then
				local ok, failure = pcall(function()
					placeDisplayAtSlot(display, slot)
					require(ReplicatedStorage.Shared.Utility.BaseDisplayPlacement).CommitSupport(display, slot)
					BrainrotDisplayMetadata.Apply(display, record, BrainrotDisplayConfig.States.Deposited, nil)
				end)
				if not ok then
					log:Warn(
						"Could not re-seat stored display %s after layout rebuild: %s",
						record.ItemId,
						tostring(failure)
					)
				end
			end
		end
	end
	return true
end

-- Internal two-stage handoff for a carried individual. Preparation may fail or
-- yield; Commit does not notify. The caller clears its source before Finish
-- publishes the existing storage revision to income observers.
function BaseStorageSystem:PrepareStoreAtPlatform(player: Player, platform: any, item: any): (any?, string?)
	local slot, storage, reason = self:ResolvePlatform(player, platform)
	if not slot or not storage then
		return nil, reason
	end
	if notifying or busyStorage[storage] then
		return nil, "BUSY"
	end
	local mutationToken
	mutationToken, reason = storage:TryBeginPlatformMutation(slot.Index)
	if not mutationToken then
		return nil, reason
	end
	local reservation
	reservation, reason = storage:TryReserveSlot(item.ItemId, slot.Index)
	if not reservation then
		storage:EndPlatformMutation(slot.Index, mutationToken)
		return nil, reason
	end
	busyStorage[storage] = true
	local token = table.freeze({})
	local stage = {
		Player = player,
		Platform = platform,
		Slot = slot,
		Storage = storage,
		Current = assignments[storage.Base],
		Item = item,
		Reservation = reservation,
		MutationToken = mutationToken,
		Committed = false,
	}
	preparedPlacements[token] = stage
	local ok, failure = pcall(function()
		stage.Display = prepareDisplay(item, slot)
		assert(stage.Display, "Platform display unavailable")
		stage.Container = containerFor(stage.Current)
	end)
	if not ok then
		self:FinishPlatformPlacement(token)
		log:Warn("Platform preparation failed for %s: %s", item.ItemId, tostring(failure))
		return nil, "PREPARATION_FAILED"
	end
	return token, nil
end

local function queueFirstBank(player, item, revision, storage, slot)
	local receipt = storage:TakeBankReceipt(item.ItemId)
	if not receipt then
		return
	end -- Previously banked moves cannot create another first-bank reward.
	local state = World.GetPhase12State and World.GetPhase12State(item)
	if state and (state.AcquisitionKind == "Hunt" or state.AcquisitionKind == "Theft") then
		receipt.acquisitionKind = state.AcquisitionKind
	end
	local operationId = "Bank:" .. item.ItemId
	local begun, why = World.BeginPendingBank(item, operationId, revision)
	-- A failed publication must not undo an already-committed ownership write or
	-- leave it movable. Keep Saving and retry this same identity after durability.
	if not begun and why ~= "ALREADY_BANKED_OR_NONORDINARY" then
		log:Warn("PendingBank publication retained for %s: %s", item.ItemId, tostring(why))
	end
	slot.Platform:SetAttribute("PendingBank", true)
	local display = storage:GetPlatformDisplay(slot.Index)
	if display then
		display:SetAttribute("PendingBank", true)
	end
	BankedBrainrotService:RegisterPendingBank(player, item, revision, function()
		if not begun then
			begun, why = World.BeginPendingBank(item, operationId, revision)
			if not begun and why ~= "ALREADY_BANKED_OR_NONORDINARY" then
				return false
			end
		end
		local released, reason = World.ConfirmPendingBank(item, operationId)
		if not released and reason ~= "ALREADY_BANKED_OR_NONORDINARY" and reason ~= "ALREADY_CONFIRMED" then
			return false
		end
		slot.Platform:SetAttribute("PendingBank", false)
		if display and display.Parent then
			display:SetAttribute("PendingBank", false)
		end
		-- Publish transaction identity only after the covering save and ledger confirmation.
		receipt.operationId, receipt.commitRevision = operationId, revision
		receipt.ownerUserId = player.UserId
		receipt.populationReleased = released == true
		receipt.populationReleaseCode = reason or "CONFIRMED"
		receipt.platformId, receipt.baseId = slot.Index, storage.BaseId
		receipt.position = slot.Platform.Position
		BankedBrainrotService:OnBankCommitted(player, receipt)
		return true
	end)
end

function BaseStorageSystem:CommitPlatformPlacement(token: any): (boolean, string?)
	local stage = preparedPlacements[token]
	if not stage or stage.Committed then
		return false, "INVALID_CONTEXT"
	end
	local slot, storage, reason = self:ResolvePlatform(stage.Player, stage.Platform)
	if slot ~= stage.Slot or storage ~= stage.Storage or assignments[storage.Base] ~= stage.Current then
		return false, reason or "INVALID_CONTEXT"
	end
	local reservedSlot = storage:GetReservedSlot(stage.Reservation, stage.Item.ItemId)
	-- BaseStorage deliberately copies descriptors; compare the authoritative
	-- index and Instances rather than table identity across the registry boundary.
	if
		not reservedSlot
		or reservedSlot.Index ~= slot.Index
		or reservedSlot.Platform ~= slot.Platform
		or reservedSlot.Marker ~= slot.Marker
	then
		return false, "INVALID_PLATFORM"
	end
	notify("OnChanging", stage.Current)
	local ok, accepted, failure = pcall(function()
		assert(stage.Container.Parent == storage.Base, "Destination container moved")
		stage.Display.Parent = stage.Container
		assert(stage.Display:IsDescendantOf(storage.Base), "Destination display moved")
		if storage:IsProfileBacked() then
			local mutation = profileOwner:CommitMutation(stage.Player, function(data)
				if not storage:IsBoundToProfile(data) then
					return false, { ok = false, code = "PROFILE_SOURCE_CHANGED" }
				end
				local committed, commitReason = storage:CommitReservation(
					stage.Reservation,
					stage.Item,
					stage.Display,
					BankedBrainrotService:GetBankContext(stage.Player),
					bankClock()
				)
				return committed, { ok = committed, code = commitReason }
			end)
			stage.CoveringRevision = mutation.revision
			return mutation.ok == true, mutation.code
		end
		return storage:CommitReservation(
			stage.Reservation,
			stage.Item,
			stage.Display,
			BankedBrainrotService:GetBankContext(stage.Player),
			bankClock()
		)
	end)
	-- A post-commit exception is not a failed transfer. Never retain a second
	-- carried owner or retry into another slot after durable in-session commit.
	local stored = storage:GetPlatformRecord(slot.Index)
	stage.Committed = stored ~= nil and stored.ItemId == stage.Item.ItemId
	if stage.Committed then
		queueFirstBank(stage.Player, stage.Item, stage.CoveringRevision or 0, storage, slot)
	end
	if not ok then
		log:Warn(
			"Platform commit %s committed=%s: %s",
			stage.Item.ItemId,
			tostring(stage.Committed),
			tostring(accepted)
		)
	end
	return stage.Committed, if stage.Committed then nil else (if ok then failure else "COMMIT_FAILED")
end

function BaseStorageSystem:FinishPlatformPlacement(token: any)
	local stage = preparedPlacements[token]
	if not stage then
		return
	end
	preparedPlacements[token] = nil -- Exactly one finalisation/notification.
	local ok, failure = pcall(function()
		if stage.Committed then
			require(ReplicatedStorage.Shared.Utility.BaseDisplayPlacement).CommitSupport(stage.Display, stage.Slot)
			BrainrotDisplayMetadata.Apply(stage.Display, stage.Item, BrainrotDisplayConfig.States.Deposited, nil)
			notify(
				"OnCommitted",
				stage.Current,
				stage.Storage:GetRevision(),
				freezeSnapshot(stage.Storage:GetSnapshot())
			)
		elseif stage.Display then
			stage.Display:Destroy()
		end
	end)
	stage.Storage:CancelReservation(stage.Reservation)
	stage.Storage:EndPlatformMutation(stage.Slot.Index, stage.MutationToken)
	busyStorage[stage.Storage] = nil
	if not ok then
		-- Existing income Step reconciles a missed storage revision. Do not turn
		-- a notification/presentation error into a second inventory transfer.
		log:Warn(
			"Platform finalisation %s committed=%s: %s",
			stage.Item.ItemId,
			tostring(stage.Committed),
			tostring(failure)
		)
	end
end

-- Trusted server-only, single-item operation. Physical arrival belongs to Phase 5C-2.
-- All dependencies are already loaded; the complete transfer is synchronous/non-yielding.
function BaseStorageSystem:TryDepositItem(player: Player, cart: Model, itemId: string, expectedStorage: any): any
	local traceScope = if Trace.Enabled()
		then Trace.Scope({
			userId = player.UserId,
			cartId = cart:GetAttribute("CartId") or "none",
			baseId = expectedStorage and expectedStorage.BaseId or "none",
			storage = Trace.Id(expectedStorage),
			itemId = itemId,
		})
		else nil
	local function traceEnd(result: any, committed: boolean?)
		Trace.Emit("5C", "item_end", function()
			local fields = Trace.Fields(player, cart, expectedStorage)
			fields.itemId, fields.result, fields.committed = itemId, result.code, committed == true
			fields.error = result.presentationError or "none"
			fields.cartGuard, fields.storageGuard = Trace.Id(busyCarts), Trace.Id(busyStorage)
			fields.cartGuardHeld, fields.storageGuardHeld =
				busyCarts[cart] ~= nil, expectedStorage ~= nil and busyStorage[expectedStorage] ~= nil
			return fields
		end, result.code == "INTERNAL_ERROR" or result.presentationError ~= nil)
		Trace.Close(traceScope)
	end
	Trace.Emit("5C", "item_enter", { notifying = notifying })
	if notifying then
		Trace.Emit("5C", "item_reject", { result = "BUSY", reason = "storage_notification_in_progress" })
		traceEnd({ code = "BUSY" })
		return { ok = false, code = "BUSY", itemId = itemId }
	end
	local current, reason = context(player, cart, expectedStorage)
	if current == nil then
		traceEnd({ code = reason })
		return { ok = false, code = reason, itemId = itemId }
	end
	local storage = current.Storage
	Trace.Emit("5C", "item_guard_check", function()
		return {
			cartGuard = Trace.Id(busyCarts),
			cartKey = Trace.Id(cart),
			cartHeld = busyCarts[cart] ~= nil,
			storageGuard = Trace.Id(busyStorage),
			storageKey = Trace.Id(storage),
			storageHeld = busyStorage[storage] ~= nil,
			acquiredBy = if busyCarts[cart] or busyStorage[storage] then "TryDepositItem" else "none",
		}
	end)
	if busyCarts[cart] or busyStorage[storage] then
		Trace.Emit("5C", "item_reject", { result = "BUSY", reason = "transfer_guard_held" })
		traceEnd({ code = "BUSY" })
		return { ok = false, code = "BUSY", itemId = itemId }
	end
	busyCarts[cart] = true
	busyStorage[storage] = true
	Trace.Emit("5C", "item_guard_acquired", function()
		return {
			cartGuard = Trace.Id(busyCarts),
			cartKey = Trace.Id(cart),
			storageGuard = Trace.Id(busyStorage),
			storageKey = Trace.Id(storage),
			acquiredBy = "TryDepositItem",
		}
	end)

	local reservation, detached, display, slot, item
	local committed = false
	local result = { ok = false, code = "INTERNAL_ERROR", itemId = itemId }
	local ok, failure = xpcall(function()
		Trace.Emit("5C", "resolve_item_enter", { itemId = itemId })
		item = CartCargoService:GetCargoItem(cart, itemId)
		Trace.Emit("5C", "resolve_item_exit", function()
			return {
				itemId = itemId,
				belongsToCart = item ~= nil,
				species = item and item.BrainrotId or "none",
				attachment = item and item.AttachmentIndex or "none",
				alreadyStored = storage:ContainsItem(itemId),
			}
		end)
		if item == nil then
			result.code = if storage:ContainsItem(itemId) then "ALREADY_STORED" else "NOT_IN_CARGO"
			return
		end
		reservation, reason = storage:TryReserveSlot(itemId)
		Trace.Emit("5C", "reserve_result", function()
			local f = Trace.Fields(player, cart, storage)
			f.itemId, f.token, f.result = itemId, Trace.Id(reservation), reason or "reserved"
			return f
		end)
		if reservation == nil then
			result.code = reason
			return
		end
		slot = storage:GetReservedSlot(reservation, itemId)
		Trace.Emit("5C", "reserved_platform", function()
			return {
				slot = slot and slot.Index or "none",
				marker = slot and slot.Marker or "none",
				valid = slot ~= nil and validSlot(storage.Base, slot),
			}
		end)
		if slot == nil or not validSlot(storage.Base, slot) then
			result.code = "INVALID_PLATFORM"
			return
		end
		display = prepareDisplay(item, slot)
		if display == nil then
			result.code = "INVALID_ASSET"
			return
		end
		Trace.Emit("5C", "container_enter", { base = storage.Base })
		local container = containerFor(current)
		Trace.Emit("5C", "container_exit", { container = container })
		local stillCurrent = context(player, cart, storage)
		Trace.Emit("5C", "revalidate", function()
			return {
				contextMatches = stillCurrent == current,
				itemMatches = CartCargoService:GetCargoItem(cart, itemId) == item,
				markerValid = validSlot(storage.Base, slot),
				reservationMatches = storage:GetReservedSlot(reservation, itemId) == slot,
			}
		end)
		if stillCurrent ~= current or CartCargoService:GetCargoItem(cart, itemId) ~= item then
			result.code = "INVALID_CONTEXT"
			return
		end
		if not validSlot(storage.Base, slot) or storage:GetReservedSlot(reservation, itemId) ~= slot then
			result.code = "INVALID_PLATFORM"
			return
		end
		Trace.Emit("5C", "detach_enter", { itemId = itemId, attachment = item.AttachmentIndex })
		detached, reason = CartCargoService:DetachForTransfer(cart, itemId)
		Trace.Emit("5C", "detach_exit", function()
			return {
				token = Trace.Id(detached),
				result = reason or "detached",
				cargoRevision = CartCargoService:GetCargoRevision(cart),
				cargoRemaining = CartCargoService:GetCargoCount(cart),
				visualRemoval = "deferred_until_finalize",
			}
		end)
		if detached == nil then
			result.code = reason
			return
		end
		Trace.Emit("5C", "display_parent_enter", { container = container })
		display.Parent = container
		Trace.Emit("5C", "display_parent_exit", function()
			return { display = display, parent = display.Parent, pivot = display:GetPivot() }
		end)
		assert(
			container.Parent == storage.Base and display:IsDescendantOf(storage.Base),
			"Destination display container is no longer live"
		)
		notify("OnChanging", current)
		local accepted, commitReason
		if storage:IsProfileBacked() then
			local mutation = profileOwner:CommitMutation(player, function(data)
				if not storage:IsBoundToProfile(data) then
					return false, { ok = false, code = "PROFILE_SOURCE_CHANGED" }
				end
				local committedNow, reasonNow = storage:CommitReservation(
					reservation,
					item,
					display,
					BankedBrainrotService:GetBankContext(player),
					bankClock()
				)
				return committedNow, { ok = committedNow, code = reasonNow }
			end)
			accepted, commitReason = mutation.ok == true, mutation.code
			result.commitRevision = mutation.revision
		else
			accepted, commitReason = storage:CommitReservation(
				reservation,
				item,
				display,
				BankedBrainrotService:GetBankContext(player),
				bankClock()
			)
		end
		Trace.Emit("5C", "commit_result", { result = commitReason or "accepted", accepted = accepted })
		if not accepted then
			result.code = commitReason or "INTERNAL_ERROR"
			return
		end
		committed = true
		result = {
			ok = true,
			code = "DEPOSITED",
			itemId = itemId,
			slotIndex = slot.Index,
			commitRevision = result.commitRevision,
		}
	end, debug.traceback)

	-- Guaranteed cleanup is independent of the protected body. Never roll back committed truth.
	if committed then
		queueFirstBank(player, item, result.commitRevision or 0, storage, slot)
		local notified = false
		local function committedSnapshot()
			if notified then
				return
			end
			notified = true
			notify("OnCommitted", current, storage:GetRevision(), freezeSnapshot(storage:GetSnapshot()))
		end
		Trace.Emit("5C", "finalize_enter", { committed = committed })
		local finalized, accepted, presentationError = pcall(function()
			return CartCargoService:FinalizeTransfer(cart, detached, committedSnapshot)
		end)
		Trace.Emit("5C", "finalize_exit", {
			committed = committed,
			called = finalized,
			accepted = accepted,
			error = presentationError or (if not finalized then tostring(accepted) else "none"),
		}, not finalized or not accepted or presentationError ~= nil)
		-- Preserve notification even if an unexpected finalisation/presentation exception
		-- escaped after inventory commit. The income revision guard detects missed history.
		committedSnapshot()
		local displayed, displayError = pcall(function()
			require(ReplicatedStorage.Shared.Utility.BaseDisplayPlacement).CommitSupport(display, slot)
			BrainrotDisplayMetadata.Apply(display, item, BrainrotDisplayConfig.States.Deposited, nil)
		end)
		if not displayed then
			log:Warn("Committed deposit %s nametag error: %s", itemId, tostring(displayError))
		end
		if not finalized or not accepted or presentationError then
			local problem = if not finalized
				then tostring(accepted)
				else tostring(presentationError or "token finalisation rejected")
			log:Warn("Committed deposit %s presentation/finalisation error: %s", itemId, problem)
			result.presentationError = problem
		end
	else
		if detached ~= nil then
			Trace.Emit("5C", "restore_enter", { committed = committed })
			local restored, restoreResult = pcall(function()
				return CartCargoService:RestoreTransfer(cart, detached)
			end)
			Trace.Emit(
				"5C",
				"restore_exit",
				{ called = restored, result = restoreResult },
				not restored or not restoreResult
			)
			if not restored or not restoreResult then
				log:Warn("Cargo rollback invariant failed for %s: %s", itemId, tostring(restoreResult))
			end
		end
		if display ~= nil then
			Trace.Emit("5C", "display_cleanup_enter", { committed = committed, display = display })
			local cleaned, cleanupError = pcall(function()
				display:Destroy()
			end)
			Trace.Emit("5C", "display_cleanup_exit", { result = cleaned, error = cleanupError or "none" }, not cleaned)
			if not cleaned then
				log:Warn("Temporary display cleanup failed for %s: %s", itemId, tostring(cleanupError))
			end
		end
	end
	if reservation ~= nil then
		local cancelled, cancelError = pcall(function()
			storage:CancelReservation(reservation)
		end)
		Trace.Emit(
			"5C",
			"reservation_cleanup_exit",
			{ result = cancelled, error = cancelError or "none", committed = committed },
			not cancelled
		)
		if not cancelled then
			log:Warn("Reservation cleanup failed for %s: %s", itemId, tostring(cancelError))
		end
	end
	Trace.Emit("5C", "item_guard_release_enter", { committed = committed })
	busyCarts[cart] = nil
	busyStorage[storage] = nil
	Trace.Emit("5C", "item_cleanup_check", function()
		local inCargo, inStorage = CartCargoService:GetCargoItem(cart, itemId) ~= nil, storage:ContainsItem(itemId)
		local reservationHeld = reservation ~= nil and storage:GetReservedSlot(reservation, itemId) ~= nil
		local displayLive = display ~= nil and display:IsDescendantOf(storage.Base)
		local mismatch = (inCargo and inStorage)
			or (inStorage and not displayLive)
			or reservationHeld
			or busyCarts[cart] ~= nil
			or busyStorage[storage] ~= nil
		if mismatch then
			Trace.Emit("5C", "invariant_disagreement", {
				itemId = itemId,
				inCargo = inCargo,
				inStorage = inStorage,
				displayLive = displayLive,
				reservationHeld = reservationHeld,
				committed = committed,
			}, true)
		end
		return {
			inCargo = inCargo,
			inStorage = inStorage,
			displayLive = displayLive,
			reservationHeld = reservationHeld,
			committed = committed,
			result = if mismatch then "mismatch" else "consistent",
			error = if ok then "none" else tostring(failure),
		}
	end, not ok)
	if not ok then
		log:Warn("Deposit %s failed before commit: %s", itemId, tostring(failure))
	end
	traceEnd(result, committed)
	return result
end

function BaseStorageSystem:Start(options: any?)
	Trace.Emit("BOOT", "storage_start", { module = script, alreadyStarted = started })
	if started then
		return
	end
	profileOwner = if options and options.Profile ~= nil then options.Profile else PlayerDataService
	bankClock = if options and options.BankNow
		then options.BankNow
		else function(): number
			return DateTime.now().UnixTimestampMillis / 1000
		end
	started = true
	for _, base in PlayerBaseSystem:GetRegisteredBases() do
		registerBase(base)
	end
	lifecycleConnection = PlayerBaseSystem:SubscribeAssignments(bindAssignment, releaseAssignment)
	if profileOwner and profileOwner.SubscribeReady then
		profileReadyConnection = profileOwner:SubscribeReady(function(player)
			local base = PlayerBaseSystem:GetBase(player)
			if base then
				bindAssignment(player, base, PlayerBaseSystem:GetAssignment(player))
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		local base = PlayerBaseSystem:GetBase(player)
		if base then
			bindAssignment(player, base, PlayerBaseSystem:GetAssignment(player))
		end
	end
	Trace.Emit("BOOT", "storage_ready", { started = started, lifecycleSubscribed = lifecycleConnection ~= nil })
end

function BaseStorageSystem:Destroy()
	if lifecycleConnection then
		lifecycleConnection:Disconnect()
		lifecycleConnection = nil
	end
	if profileReadyConnection then
		profileReadyConnection:Disconnect()
		profileReadyConnection = nil
	end
	for base, current in assignments do
		releaseAssignment(current.Player, base)
	end
	for token in preparedPlacements do
		self:FinishPlatformPlacement(token)
	end
	for platform in platformSlots do
		CollectionService:RemoveTag(platform, PLATFORM_TAG)
		platform:SetAttribute("StorageOccupied", nil)
		platform:SetAttribute("StorageItemId", nil)
		platform:SetAttribute("StorageBrainrotId", nil)
	end
	table.clear(platformSlots)
	table.clear(registered)
	table.clear(busyCarts)
	table.clear(busyStorage)
	profileOwner = PlayerDataService
	bankClock = function(): number
		return DateTime.now().UnixTimestampMillis / 1000
	end
	started = false
end

-- Core Loop V2 (K4): after AdoptCommittedMutation, publish the new revision to income/occupancy observers and
-- re-apply display metadata so the mutation look shows on the base.
function BaseStorageSystem:NotifyRecordChanged(player: Player): boolean
	local storage = self:GetStorageForPlayer(player)
	if not storage then
		return false
	end
	local current = assignments[storage.Base]
	if not current then
		return false
	end
	notify("OnCommitted", current, storage:GetRevision(), freezeSnapshot(storage:GetSnapshot()))
	publishOccupancy(current)
	self:RefreshPlatformDisplays(storage.Base)
	return true
end

function BaseStorageSystem:ReconcilePlayerFromProfile(player: Player): boolean
	local storage = self:GetStorageForPlayer(player)
	if not storage then
		return false
	end
	local current = assignments[storage.Base]
	if not current then
		return false
	end
	storage:DiscardStaleRuntimeEntries()
	for index = 1, storage:GetSlotCapacity() do
		if not storage:GetPlatformRecord(index) then
			restoreAssignment(current, index)
		end
	end
	notify("OnCommitted", current, storage:GetRevision(), freezeSnapshot(storage:GetSnapshot()))
	publishOccupancy(current)
	return true
end

return BaseStorageSystem
