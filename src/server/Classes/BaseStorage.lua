--!strict

export type SlotDescriptor = {
	Index: number,
	Platform: BasePart,
	Marker: Attachment | BasePart,
}
export type ItemData = {
	ItemId: string,
	BrainrotId: string,
	Metadata: { [string]: any },
	World: { [string]: any }?,
}

local Trace = require(script.Parent.Parent.Utility.BrainrotDiagnostics)
local WorldRules = require(game.ReplicatedStorage.Shared.Utility.WorldProgressionRules)
local Phase12Progress = require(script.Parent.Parent.Data.Phase12Progress)
local BaseStorage = {}
BaseStorage.__index = BaseStorage
local Phase13Rules = require(game.ReplicatedStorage.Shared.Utility.Phase13Rules)
local MAX_SAFE_INTEGER = 9007199254740991

local function finiteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= MAX_SAFE_INTEGER
end

local function savedPlatformBalance(savedData: any, index: number): number
	if type(savedData) == "table" and type(savedData.Base) == "table" and type(savedData.Base.Slots) == "table" then
		local slot = savedData.Base.Slots[tostring(index)]
		local amount = if type(slot) == "table" then slot.accumulatedCash else nil
		return if finiteNonNegative(amount) then amount else 0
	end
	if type(savedData) ~= "table" or type(savedData.PlatformIncome) ~= "table" then
		return 0
	end
	local source = savedData.PlatformIncome[index] or savedData.PlatformIncome[tostring(index)]
	local value = if type(source) == "table" then source.UnclaimedCashExact else nil
	return if finiteNonNegative(value) then value else 0
end

-- Only item metadata is copied; Instances, functions and container bindings never enter snapshots.
local function copyMetadata(source: { [any]: any }): { [any]: any }
	local result = {}
	for key, value in source do
		if type(key) == "string" or type(key) == "number" then
			local kind = typeof(value)
			if kind == "table" then
				result[key] = copyMetadata(value)
			elseif kind == "string" or kind == "number" or kind == "boolean" then
				result[key] = value
			end
		end
	end
	return result
end

function BaseStorage.new(base: Model, ownerUserId: number, slotDescriptors: { SlotDescriptor }, savedData: any?)
	local slots, platformIncome, profileSlots = {}, {}, nil
	if
		type(savedData) == "table"
		and type(savedData.Collection) == "table"
		and type(savedData.Collection.BrainrotInstances) == "table"
		and type(savedData.Base) == "table"
		and type(savedData.Base.Slots) == "table"
	then
		profileSlots = savedData.Base.Slots
	end
	for index, descriptor in slotDescriptors do
		assert(descriptor.Index == index, "Storage requires validated dense slot descriptors")
		slots[index] = table.freeze(table.clone(descriptor))
		-- The ledger belongs to the stable platform, not to its current occupant.
		-- Old saves and malformed values reconcile to a safe zero balance.
		platformIncome[index] = { UnclaimedCashExact = savedPlatformBalance(savedData, index) }
	end
	return setmetatable({
		Base = base,
		BaseId = base:GetAttribute("BaseId"),
		OwnerUserId = ownerUserId,
		_slots = table.freeze(slots),
		_entries = {},
		_items = {},
		_reservations = {},
		_reservedItems = {},
		_bankReceipts = {},
		_platformMutations = {},
		_platformIncome = platformIncome,
		_profileData = if profileSlots then savedData else nil,
		_profileSlots = profileSlots,
		_persistentDataLoaded = savedData ~= nil,
		_count = 0,
		_revision = 0,
		_active = true,
	}, BaseStorage)
end

-- Profile data is applied once, before this storage is exposed to the income
-- scheduler. Rebinding presentation or observers must never rewind live earnings.
function BaseStorage:RestorePersistentData(savedData: any): (boolean, string?)
	if not self._active then
		return false, "INACTIVE"
	end
	if self._persistentDataLoaded then
		return true, nil
	end
	for index in self._slots do
		self._platformIncome[index].UnclaimedCashExact = savedPlatformBalance(savedData, index)
	end
	self._persistentDataLoaded = true
	return true, nil
end

function BaseStorage:IsValidPlatformId(platformId: any): boolean
	return self._active
		and type(platformId) == "number"
		and platformId % 1 == 0
		and self._slots[platformId] ~= nil
		and platformId <= self:GetSlotCapacity()
end

function BaseStorage:GetPlatformIds(): { number }
	local result = {}
	if self._active then
		for index in self._slots do
			if index <= self:GetSlotCapacity() then
				table.insert(result, index)
			end
		end
	end
	return result
end

function BaseStorage:GetUnclaimedCashExact(platformId: any): (number?, string?)
	if not self:IsValidPlatformId(platformId) then
		return nil, "INVALID_PLATFORM"
	end
	local profileSlot = self._profileSlots and self._profileSlots[tostring(platformId)]
	return if profileSlot then profileSlot.accumulatedCash else self._platformIncome[platformId].UnclaimedCashExact, nil
end

function BaseStorage:SetUnclaimedCashExact(platformId: any, value: any): (boolean, string?)
	if not self:IsValidPlatformId(platformId) then
		return false, "INVALID_PLATFORM"
	end
	if not finiteNonNegative(value) then
		return false, "INVALID_BALANCE"
	end
	local profileSlot = self._profileSlots and self._profileSlots[tostring(platformId)]
	if profileSlot then
		profileSlot.accumulatedCash = value
	else
		self._platformIncome[platformId].UnclaimedCashExact = value
	end
	return true, nil
end

-- Shared, slot-scoped transaction token. Income claims can yield in the wallet
-- adapter, so deposit/removal and claim must not mutate the same platform while
-- that exact credit is unresolved. Other platforms remain independent.
function BaseStorage:TryBeginPlatformMutation(platformId: any): (any?, string?)
	if not self:IsValidPlatformId(platformId) then
		return nil, "INVALID_PLATFORM"
	end
	if self._platformMutations[platformId] ~= nil then
		return nil, "BUSY"
	end
	local token = table.freeze({})
	self._platformMutations[platformId] = token
	return token, nil
end

function BaseStorage:EndPlatformMutation(platformId: any, token: any): boolean
	if not self:IsValidPlatformId(platformId) or self._platformMutations[platformId] ~= token then
		return false
	end
	self._platformMutations[platformId] = nil
	return true
end

function BaseStorage:AddUnclaimedCashExact(platformId: any, amount: any): (boolean, string?)
	if not self:IsValidPlatformId(platformId) then
		return false, "INVALID_PLATFORM"
	end
	if not finiteNonNegative(amount) then
		return false, "INVALID_AMOUNT"
	end
	local current = self:GetUnclaimedCashExact(platformId)
	if current == nil or current > MAX_SAFE_INTEGER - amount then
		return false, "BALANCE_OVERFLOW"
	end
	return self:SetUnclaimedCashExact(platformId, current + amount)
end

-- Instance-free data consumed by the server profile owner. Stable string platform
-- IDs prevent physical plaque balances from being compacted or remapped on reload.
function BaseStorage:GetPersistentData(): any
	local platformIncome = {}
	for index in self._slots do
		platformIncome[tostring(index)] = {
			UnclaimedCashExact = self:GetUnclaimedCashExact(index),
		}
	end
	return { PlatformIncome = platformIncome }
end

function BaseStorage:IsProfileBacked(): boolean
	return self._profileData ~= nil
end

function BaseStorage:IsBoundToProfile(data: any): boolean
	return self._profileData == data
end

function BaseStorage:IsActive(): boolean
	return self._active
end

function BaseStorage:GetOccupiedCount(): number
	return self._count
end

function BaseStorage:GetSlotCapacity(): number
	return if self._profileData then Phase13Rules.GetCapacity(self._profileData) else math.min(#self._slots, 12)
end

function BaseStorage:GetAvailableSlotCount(): number
	if not self._active then
		return 0
	end
	local available = 0
	for index in self._slots do
		if index <= self:GetSlotCapacity() and self._entries[index] == nil and self._reservations[index] == nil then
			available += 1
		end
	end
	return available
end

function BaseStorage:GetRevision(): number
	return self._revision
end

function BaseStorage:ContainsItem(itemId: string): boolean
	return self._items[itemId] ~= nil
end

function BaseStorage:GetPlatformRecord(index: number): any?
	local entry = self._entries[index]
	if not entry then
		return nil
	end
	local record = {
		SlotIndex = index,
		ItemId = entry.Item.ItemId,
		BrainrotId = entry.Item.BrainrotId,
		Metadata = copyMetadata(entry.Item.Metadata),
	}
	if type(entry.Item.World) == "table" then
		record.World = copyMetadata(entry.Item.World)
	end
	return record
end

-- Core Loop V2 (K4 Mutation Rain): adopt a mutation that is ALREADY committed to this individual's profile
-- record (PlayerDataService:CommitCriticalMutation). Refuses unless the profile says the same, so the live
-- entry can never run ahead of the saved data.
function BaseStorage:AdoptCommittedMutation(platformId: number, itemId: string, mutationId: string): boolean
	local entry = self._entries[platformId]
	if not entry or entry.Item.ItemId ~= itemId then
		return false
	end
	local owned = self._profileData
		and self._profileData.Collection
		and self._profileData.Collection.BrainrotInstances[itemId]
	if type(owned) ~= "table" or Phase12Progress.MutationId(owned) ~= mutationId then
		return false
	end
	entry.Item.Metadata.MutationId = mutationId
	self._revision += 1
	return true
end

function BaseStorage:GetPlatformDisplay(index: number): Model?
	local entry = self._entries[index]
	return if entry then entry.Display else nil
end

-- Uncollected cash belongs to the logical platform. Removal stops future
-- accrual while retaining the ledger for normal collection.
function BaseStorage:RemovePlatformRecord(platformId: any, expectedItemId: any): (any?, Model?, string?)
	if not self:IsValidPlatformId(platformId) then
		return nil, nil, "INVALID_PLATFORM"
	end
	local entry = self._entries[platformId]
	if entry == nil then
		return nil, nil, "EMPTY"
	end
	if type(expectedItemId) ~= "string" or entry.Item.ItemId ~= expectedItemId then
		return nil, nil, "STALE_ID"
	end
	local record = {
		SlotIndex = platformId,
		ItemId = entry.Item.ItemId,
		BrainrotId = entry.Item.BrainrotId,
		Metadata = copyMetadata(entry.Item.Metadata),
	}
	if type(entry.Item.World) == "table" then
		record.World = copyMetadata(entry.Item.World)
	end
	local profileSlot = self._profileSlots and self._profileSlots[tostring(platformId)]
	if profileSlot then
		if profileSlot.brainrotId ~= entry.Item.ItemId then
			return nil, nil, "PROFILE_SOURCE_CHANGED"
		end
		profileSlot.brainrotId = nil
	end
	-- Retain accrued platform cash when the occupant leaves.
	self._entries[platformId] = nil
	self._items[entry.Item.ItemId] = nil
	self._count -= 1
	self._revision += 1
	return record, entry.Display, nil
end

function BaseStorage:TryReserveSlot(itemId: string, explicitIndex: number?): (any?, string?)
	Trace.Emit("5C", "reserve_enter", function()
		local f = Trace.Fields(nil, nil, self)
		f.itemId = itemId
		local inventory = {}
		for index, descriptor in self._slots do
			local entry, reservation = self._entries[index], self._reservations[index]
			table.insert(
				inventory,
				tostring(index)
					.. ":item="
					.. (entry and entry.Item.ItemId or "none")
					.. ":reserved="
					.. (reservation and reservation.ItemId or "none")
					.. ":markerValid="
					.. tostring(descriptor.Marker:IsDescendantOf(descriptor.Platform))
			)
		end
		f.slotInventory = table.concat(inventory, ",")
		return f
	end)
	if not self._active or itemId == "" then
		return nil, "INVALID_CONTEXT"
	end
	if self._items[itemId] ~= nil then
		return nil, "ALREADY_STORED"
	end
	if self._reservedItems[itemId] ~= nil then
		return nil, "BUSY"
	end
	if explicitIndex ~= nil then
		if not self:IsValidPlatformId(explicitIndex) then
			return nil, "INVALID_PLATFORM"
		end
		if self._entries[explicitIndex] ~= nil then
			return nil, "OCCUPIED"
		end
		if self._reservations[explicitIndex] ~= nil then
			return nil, "BUSY"
		end
	end
	for index in self._slots do
		if explicitIndex ~= nil and index ~= explicitIndex then
			continue
		end
		if index <= self:GetSlotCapacity() and self._entries[index] == nil and self._reservations[index] == nil then
			local token = table.freeze({})
			self._reservations[index] = { Token = token, ItemId = itemId }
			self._reservedItems[itemId] = index
			Trace.Emit("5C", "reserve_exit", function()
				return {
					storage = Trace.Id(self),
					itemId = itemId,
					slot = index,
					token = Trace.Id(token),
					result = "reserved",
					storageRevision = self._revision,
				}
			end)
			return token, nil
		end
	end
	return nil, if self._count == self:GetSlotCapacity() then "NO_SPACE" else "BUSY"
end

function BaseStorage:GetReservedSlot(token: any, itemId: string): SlotDescriptor?
	if not self._active then
		return nil
	end
	local index = self._reservedItems[itemId]
	local reservation = if index then self._reservations[index] else nil
	if reservation == nil or reservation.Token ~= token then
		return nil
	end
	return self._slots[index]
end

function BaseStorage:CommitReservation(
	token: any,
	itemData: ItemData,
	display: Model,
	bankContext: any?,
	bankTimestamp: number?
): (boolean, string?)
	Trace.Emit("5C", "commit_enter", function()
		local f = Trace.Fields(nil, nil, self)
		f.itemId, f.token = itemData.ItemId, Trace.Id(token)
		return f
	end)
	local slot = self:GetReservedSlot(token, itemData.ItemId)
	if slot == nil or self._entries[slot.Index] ~= nil or self._items[itemData.ItemId] ~= nil then
		Trace.Emit("5C", "commit_reject", function()
			return {
				result = "INVALID_CONTEXT",
				reservedSlot = slot and slot.Index or "none",
				alreadyStoredSlot = self._items[itemData.ItemId] or "none",
				active = self._active,
			}
		end, true)
		return false, "INVALID_CONTEXT"
	end
	-- All fallible preparation precedes the table-only commit below.
	local mutationId = Phase12Progress.MutationId(itemData)
	if mutationId == nil then
		return false, "INVALID_MUTATION"
	end
	local bankAt = bankTimestamp or DateTime.now().UnixTimestampMillis / 1000
	if not finiteNonNegative(bankAt) then
		return false, "INVALID_BANK_TIMESTAMP"
	end
	local data = {
		ItemId = itemData.ItemId,
		BrainrotId = itemData.BrainrotId,
		Metadata = copyMetadata(itemData.Metadata),
	}
	if type(itemData.World) == "table" then
		data.World = copyMetadata(itemData.World)
	end
	local profileSlot = self._profileSlots and self._profileSlots[tostring(slot.Index)]
	if profileSlot then
		if profileSlot.brainrotId ~= nil then
			return false, "OCCUPIED"
		end
		local owned = self._profileData.Collection.BrainrotInstances
		local existing = owned[data.ItemId]
		if existing ~= nil and existing.speciesId ~= data.BrainrotId then
			return false, "IDENTITY_CONFLICT"
		end
		if existing ~= nil and Phase12Progress.MutationId(existing) ~= Phase12Progress.MutationId(itemData) then
			return false, "MUTATION_CHANGED"
		end
		local receipt = Phase12Progress.RecordFirstBank(self._profileData, itemData, bankContext, bankAt)
		data.Metadata.MutationId = mutationId
		data.Metadata.FirstBankCompleted = true
		data.Metadata.DurableOwnerUserId = self.OwnerUserId
		if existing == nil then
			owned[data.ItemId] = {
				speciesId = data.BrainrotId,
				mutationId = data.Metadata.MutationId,
				firstBankCompleted = true,
				firstBankedAt = if receipt then receipt.firstBankedAt else nil,
				metadata = copyMetadata(data.Metadata),
			}
		end
		if receipt then
			self._bankReceipts[data.ItemId] = receipt
		end
		profileSlot.brainrotId = data.ItemId
		if self._profileData.WorldProgression then
			WorldRules.AddBankedProof(self._profileData, data.BrainrotId, "deposit", bankAt)
		end
	end
	-- A new occupant inherits the platform's retained ledger.
	self._entries[slot.Index] = { Item = data, Display = display }
	self._items[data.ItemId] = slot.Index
	self._reservations[slot.Index] = nil
	self._reservedItems[data.ItemId] = nil
	self._count += 1
	self._revision += 1
	Trace.Emit("5C", "storage_commit", function()
		return {
			committed = true,
			itemId = data.ItemId,
			species = data.BrainrotId,
			slot = slot.Index,
			storage = Trace.Id(self),
			storageCount = self._count,
			storageRevision = self._revision,
			display = display,
			result = "DEPOSITED",
		}
	end)
	return true, nil
end

function BaseStorage:TakeBankReceipt(itemId: string): any?
	local receipt = self._bankReceipts[itemId]
	self._bankReceipts[itemId] = nil
	return receipt
end

-- Restoration binds presentation/runtime lookup to already-authoritative saved
-- data. It does not create ownership, reset cash, or run a deposit transaction.
function BaseStorage:BindRestoredRecord(
	platformId: number,
	itemData: ItemData,
	display: Model?,
	advanceRuntimeRevision: boolean?
): (boolean, string?)
	if not self:IsValidPlatformId(platformId) or self._entries[platformId] ~= nil then
		return false, "INVALID_PLATFORM"
	end
	local profileSlot = self._profileSlots and self._profileSlots[tostring(platformId)]
	if not profileSlot or profileSlot.brainrotId ~= itemData.ItemId then
		return false, "PROFILE_SOURCE_CHANGED"
	end
	local owned = self._profileData.Collection.BrainrotInstances[itemData.ItemId]
	if type(owned) ~= "table" or owned.speciesId ~= itemData.BrainrotId then
		return false, "MISSING_OWNED_BRAINROT"
	end
	local data = {
		ItemId = itemData.ItemId,
		BrainrotId = itemData.BrainrotId,
		Metadata = copyMetadata(itemData.Metadata),
	}
	data.Metadata.MutationId = Phase12Progress.MutationId(owned)
	data.Metadata.FirstBankCompleted = true
	data.Metadata.DurableOwnerUserId = self.OwnerUserId
	self._entries[platformId] = { Item = data, Display = display }
	self._items[data.ItemId] = platformId
	self._count += 1
	if advanceRuntimeRevision then
		self._revision += 1
	end
	return true, nil
end

function BaseStorage:CancelReservation(token: any)
	Trace.Emit("5C", "cancel_enter", function()
		return { token = Trace.Id(token), storage = Trace.Id(self) }
	end)
	for index, reservation in self._reservations do
		if reservation.Token == token then
			self._reservedItems[reservation.ItemId] = nil
			self._reservations[index] = nil
			Trace.Emit("5C", "cancel_exit", { slot = index, itemId = reservation.ItemId, result = "cancelled" })
			return
		end
	end
	Trace.Emit("5C", "cancel_exit", { result = "no_held_reservation" })
end

function BaseStorage:GetSnapshot(): { any }
	local snapshot = {}
	for index in self._slots do
		local entry = self._entries[index]
		if entry ~= nil then
			local record = {
				SlotIndex = index,
				ItemId = entry.Item.ItemId,
				BrainrotId = entry.Item.BrainrotId,
				Metadata = copyMetadata(entry.Item.Metadata),
			}
			if type(entry.Item.World) == "table" then
				record.World = copyMetadata(entry.Item.World)
			end
			table.insert(snapshot, record)
		end
	end
	return snapshot
end

function BaseStorage:Destroy()
	if not self._active then
		return
	end
	Trace.Emit("5C", "storage_release", function()
		return Trace.Fields(nil, nil, self)
	end)
	Trace.Forget(self)
	self._active = false
	local entries = self._entries
	self._entries = {}
	table.clear(self._items)
	table.clear(self._reservations)
	table.clear(self._reservedItems)
	table.clear(self._bankReceipts)
	table.clear(self._platformMutations)
	self._count = 0
	for _, entry in entries do
		local ok, err = pcall(function()
			if entry.Display then
				entry.Display:Destroy()
			end
		end)
		if not ok then
			warn("[BaseStorage] Display cleanup failed: " .. tostring(err))
		end
	end
end

-- Rebuild runtime entries from durable ownership after a confirmed critical transition.
-- This must never mutate the saved slot/owned maps or consume a resource again.
function BaseStorage:DiscardStaleRuntimeEntries(): boolean
	for index, entry in table.clone(self._entries) do
		local slot = self._profileSlots and self._profileSlots[tostring(index)]
		if slot and slot.brainrotId == entry.Item.ItemId then
			continue
		end
		self._entries[index] = nil
		self._items[entry.Item.ItemId] = nil
		self._count -= 1
		self._revision += 1
		if entry.Display then
			pcall(function()
				entry.Display:Destroy()
			end)
		end
	end
	return true
end

return BaseStorage
