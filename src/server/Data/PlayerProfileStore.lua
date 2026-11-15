--!strict

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Config = require(script.Parent.Parent.Config.PlayerDataConfig)
local Schema = require(script.Parent.PlayerProfileSchema)
local ProfileKey = require(script.Parent.Parent.Utility.PlayerProfileKey)

-- Transport4 is used only after explicitly enabled paid-history archival.
-- Pre-archive profiles keep Transport3; old writers reject4 before touching Data.
local ARCHIVE_TRANSPORT = 4
local Http = game:GetService("HttpService")
local Encoding = game:GetService("EncodingService")
local Store = {}
Store.__index = Store

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, nested in value do
		copy[key] = clone(nested)
	end
	return copy
end

local function validTransport(value: any, allowLegacy: boolean?): boolean
	return type(value) == "table"
		and (value.Version == Config.TransportVersion or value.Version == ARCHIVE_TRANSPORT or allowLegacy == true and Config.LegacyTransportVersions[value.Version] == true)
		and (value.OwnerToken == nil or type(value.OwnerToken) == "string" and value.OwnerToken ~= "")
		and type(value.LeaseExpiresAt) == "number"
		and value.LeaseExpiresAt == value.LeaseExpiresAt
		and math.abs(value.LeaseExpiresAt) < math.huge
		and type(value.LastRevision) == "number"
		and value.LastRevision >= 0
		and value.LastRevision % 1 == 0
		and (value.LastOperationId == nil or type(value.LastOperationId) == "string")
end

local function envelopeStatus(value: any, allowLegacy: boolean?): string?
	if type(value) ~= "table" or not validTransport(value.Transport, allowLegacy) then
		return "UNSUPPORTED_ENVELOPE"
	end
	if value.Transport.Version == ARCHIVE_TRANSPORT then
		local header = value.Transport.PaidArchive
		if header == nil and type(value.Data) == "table" and type(value.Data.Commerce) == "table"
			and value.Data.Commerce.PaidArchiveEpoch ~= nil then return "INVALID_PAID_ARCHIVE_HEADER" end
		if header ~= nil and (type(header) ~= "table" or type(header.Epoch) ~= "number"
			or header.Epoch < 1 or header.Epoch % 1 ~= 0 or header.Epoch > Config.MaxBalance
			or type(header.Count) ~= "number" or header.Count < 1 or header.Count % 1 ~= 0
			or header.Count > Config.MaxBalance or type(value.Data) ~= "table"
			or type(value.Data.Commerce) ~= "table" or value.Data.Commerce.PaidArchiveEpoch ~= header.Epoch) then
			return "INVALID_PAID_ARCHIVE_HEADER"
		end
	end
	local _, reason = Schema.Migrate(value.Data)
	return reason
end

local function result(ok: boolean, code: string, fields: any?): any
	local value = fields or {}
	value.ok = ok
	value.code = code
	return value
end

local function preserveKeyInfo(value: any, keyInfo: any)
	if keyInfo == nil then
		return value
	end
	return value, keyInfo:GetUserIds(), keyInfo:GetMetadata()
end

function Store.new(options: any?): any
	local opts = options or {}
	local dataStore = opts.DataStore
	local available = opts.Available
	if available == nil then
		local studioProduction = RunService:IsStudio() and Environment.IsProduction
		local namespace = ProfileKey.StudioNamespace(
			game:GetService("ServerStorage"):GetAttribute("Phase8TestProfileNamespace"), studioProduction)
		local isolatedKey = if studioProduction and Environment.MainGameplayEnabled and type(namespace) == "string"
			then ProfileKey.Resolve(0, Config.KeyPrefix, namespace, true, true, true)
			else nil
		-- Studio Main may use ONLY an isolated test key (the attribute, else the default
		-- "studio" namespace), never a live player key; published servers keep normal keys.
		available = Environment.EnableDataSaving and (not studioProduction or isolatedKey ~= nil)
	end
	available = available == true and Config.Phase8MigrationReady
	if dataStore == nil and available then
		dataStore = DataStoreService:GetDataStore(Config.StoreName, Config.StoreScope)
	end
	return setmetatable({
		_dataStore = dataStore,
		-- Recovery of an already-issued receipt is independent of new-prompt
		-- readiness. It runs only on explicit capacity recovery, never at normal boot.
		_archiveEnabled = opts.EnablePaidReceiptArchive ~= false,
		_archiveBudget = opts.ArchiveBudget,
		_archiveRows = math.clamp(opts.ArchiveRows or 8, 1, 8),
		_available = available == true and dataStore ~= nil,
		_unixNow = opts.UnixNow or function()
			return DateTime.now().UnixTimestampMillis / 1000
		end,
	}, Store)
end

function Store:IsAvailable(): boolean
	return self._available
end

function Store:KeyForUserId(userId: number): string
	return Config.KeyPrefix .. tostring(userId)
end

function Store:Acquire(key: string, ownerToken: string, leaseDuration: number): any
	if not Config.Phase8MigrationReady then
		return result(false, "CURRENCY_TRANSITION_UNAVAILABLE")
	end
	if not self._available then
		return result(false, "PERSISTENCE_UNAVAILABLE")
	end
	local currentTime = self._unixNow()
	local createdByOperationId = "acquire:" .. ownerToken
	local migrationSummary = nil
	local migratedDuringAcquire = false
	local called, stored = pcall(function()
		return self._dataStore:UpdateAsync(key, function(raw, keyInfo)
			if raw == nil then
				return preserveKeyInfo({
					Transport = {
						Version = Config.TransportVersion,
						OwnerToken = ownerToken,
						LeaseExpiresAt = currentTime + leaseDuration,
						LastOperationId = createdByOperationId,
						LastRevision = 0,
						CreatedByOperationId = createdByOperationId,
					},
					Data = Schema.CreateDefault(),
				}, keyInfo)
			end
			if envelopeStatus(raw, true) then
				return preserveKeyInfo(raw, keyInfo)
			end
			local transport = raw.Transport
			if
				transport.OwnerToken ~= nil
				and transport.OwnerToken ~= ownerToken
				and transport.LeaseExpiresAt > currentTime
			then
				return preserveKeyInfo(raw, keyInfo)
			end
			local migrated, migrationReason, changed = Schema.Migrate(raw.Data)
			assert(migrated, migrationReason)
			migratedDuringAcquire = changed == true or (transport.Version ~= Config.TransportVersion and transport.Version ~= ARCHIVE_TRANSPORT)
			local legacyRegions = {}
			local previousWorld = raw.Data.WorldProgression
			for regionKey, grant in migrated.WorldProgression.PersonalUnlocks do
				if
					grant.source == "legacy_progress"
					and not (
						previousWorld
						and type(previousWorld.PersonalUnlocks) == "table"
						and previousWorld.PersonalUnlocks[regionKey]
					)
				then
					table.insert(legacyRegions, regionKey)
				end
			end
			table.sort(legacyRegions)
			migrationSummary = {
				transportFrom = transport.Version,
				transportTo = if transport.Version == ARCHIVE_TRANSPORT then ARCHIVE_TRANSPORT else Config.TransportVersion,
				currencyFrom = raw.Data.CurrencyVersion or 1,
				currencyTo = migrated.CurrencyVersion,
				monetaryFieldCount = if raw.Data.CurrencyVersion == 2 then 0 else 13,
				legacyRegions = table.concat(legacyRegions, ","),
				legacyGrantVersion = migrated.WorldProgression.LegacyGrantVersion,
			}
			local nextValue = clone(raw)
			nextValue.Data = migrated
			nextValue.Transport.Version = if transport.Version == ARCHIVE_TRANSPORT then ARCHIVE_TRANSPORT else Config.TransportVersion
			nextValue.Transport.OwnerToken = ownerToken
			nextValue.Transport.LeaseExpiresAt = currentTime + leaseDuration
			nextValue.Transport.LastOperationId = createdByOperationId
			return preserveKeyInfo(nextValue, keyInfo)
		end)
	end)
	if not called then
		return result(false, "ACQUIRE_FAILED", { error = tostring(stored), uncertain = true })
	end
	local status = envelopeStatus(stored, true)
	if status then
		return result(false, status)
	end
	if stored.Transport.OwnerToken ~= ownerToken then
		return result(false, "SESSION_LOCKED", {
			leaseExpiresAt = stored.Transport.LeaseExpiresAt,
		})
	end
	if (stored.Transport.Version ~= Config.TransportVersion and stored.Transport.Version ~= ARCHIVE_TRANSPORT) or stored.Data.CurrencyVersion ~= 2 then
		return result(false, "CURRENCY_NOT_CONFIRMED")
	end
	-- A crash after the same-size writer fence leaves every inline receipt intact.
	-- Complete that recoverable fence before exposing a writable profile.
	if stored.Transport.Version == ARCHIVE_TRANSPORT and not stored.Transport.PaidArchive then
		local recovery = self:ArchivePaidReceipts(key, ownerToken, "archive-resume:" .. ownerToken, stored.Transport.LastRevision)
		if not recovery.ok then return recovery end
		stored = recovery.envelope
	end
	local data, reason, migrated = Schema.Migrate(stored.Data)
	if not data then
		return result(false, reason or "INVALID_PROFILE")
	end
	local saveEnvelope = clone(stored)
	saveEnvelope.Data = nil
	return result(true, "ACQUIRED", {
		saveEnvelope = saveEnvelope,
		data = data,
		isNew = stored.Transport.CreatedByOperationId == createdByOperationId,
		migrated = migrated == true or migratedDuringAcquire,
		migrationSummary = migrationSummary,
		leaseExpiresAt = stored.Transport.LeaseExpiresAt,
		lastRevision = stored.Transport.LastRevision,
	})
end

-- Read-only projection of the exact envelope shape; no DataStore call. Acquire
-- supplies the retained extensions so size admission cannot silently omit them.
function Store.ProjectSaveEnvelope(
	template: any,
	snapshot: any,
	ownerToken: string,
	operationId: string,
	revision: number,
	leaseExpiresAt: number
): any?
	if
		type(template) ~= "table"
		or type(template.Transport) ~= "table"
		or (template.Transport.Version ~= Config.TransportVersion and template.Transport.Version ~= ARCHIVE_TRANSPORT)
	then
		return nil
	end
	local projected = clone(template)
	projected.Data = clone(snapshot)
	projected.Transport.OwnerToken = ownerToken
	projected.Transport.LastOperationId = operationId
	projected.Transport.LastRevision = revision
	projected.Transport.LeaseExpiresAt = leaseExpiresAt
	return projected
end

function Store:Save(
	key: string,
	ownerToken: string,
	operationId: string,
	revision: number,
	snapshot: any,
	leaseDuration: number
): any
	if not self._available then
		return result(false, "PERSISTENCE_UNAVAILABLE")
	end
	local validSnapshot, snapshotReason = Schema.CreateSaveSnapshot(snapshot)
	if not validSnapshot then
		return result(false, snapshotReason or "INVALID_SNAPSHOT")
	end
	if validSnapshot.Phase13 == nil or validSnapshot.Commerce == nil then
		return result(false, "UNSUPPORTED_WRITE_PHASE13")
	end

	local currentTime = self._unixNow()
	local called, stored = pcall(function()
		return self._dataStore:UpdateAsync(key, function(raw, keyInfo)
			if envelopeStatus(raw) then
				return preserveKeyInfo(raw, keyInfo)
			end
			local transport = raw.Transport
			if transport.Version == ARCHIVE_TRANSPORT and (not transport.PaidArchive
				or validSnapshot.Commerce.PaidArchiveEpoch ~= raw.Data.Commerce.PaidArchiveEpoch) then
				return preserveKeyInfo(raw, keyInfo)
			end
			if transport.LastOperationId == operationId and transport.LastRevision == revision then
				return preserveKeyInfo(raw, keyInfo)
			end
			if transport.OwnerToken ~= ownerToken or revision < transport.LastRevision then
				return preserveKeyInfo(raw, keyInfo)
			end
			local nextValue = clone(raw)
			nextValue.Data = clone(snapshot)
			nextValue.Transport.LastOperationId = operationId
			nextValue.Transport.LastRevision = revision
			nextValue.Transport.LeaseExpiresAt = currentTime + leaseDuration
			return preserveKeyInfo(nextValue, keyInfo)
		end)
	end)
	if not called then
		return result(false, "SAVE_UNCERTAIN", { error = tostring(stored), uncertain = true })
	end
	local status = envelopeStatus(stored)
	if status then
		return result(false, status)
	end
	if
		stored.Transport.OwnerToken == ownerToken
		and stored.Transport.LastOperationId == operationId
		and stored.Transport.LastRevision == revision
	then
		return result(true, "SAVED", { leaseExpiresAt = stored.Transport.LeaseExpiresAt })
	end
	return result(false, if stored.Transport.OwnerToken ~= ownerToken then "OWNER_MISMATCH" else "STALE_REVISION")
end

function Store:Renew(key: string, ownerToken: string, operationId: string, leaseDuration: number): any
	if not self._available then
		return result(false, "PERSISTENCE_UNAVAILABLE")
	end
	local currentTime = self._unixNow()
	local called, stored = pcall(function()
		return self._dataStore:UpdateAsync(key, function(raw, keyInfo)
			if envelopeStatus(raw) or raw.Transport.OwnerToken ~= ownerToken then
				return preserveKeyInfo(raw, keyInfo)
			end
			local nextValue = clone(raw)
			nextValue.Transport.LeaseExpiresAt = currentTime + leaseDuration
			nextValue.Transport.LastOperationId = operationId
			return preserveKeyInfo(nextValue, keyInfo)
		end)
	end)
	if not called then
		return result(false, "RENEW_UNCERTAIN", { error = tostring(stored), uncertain = true })
	end
	if envelopeStatus(stored) then
		return result(false, envelopeStatus(stored) :: string)
	end
	if stored.Transport.OwnerToken ~= ownerToken then
		return result(false, "OWNER_MISMATCH")
	end
	return result(true, "RENEWED", { leaseExpiresAt = stored.Transport.LeaseExpiresAt })
end

function Store:Release(key: string, ownerToken: string, operationId: string, revision: number, snapshot: any): any
	if not self._available then
		return result(false, "PERSISTENCE_UNAVAILABLE")
	end
	local validSnapshot, snapshotReason = Schema.CreateSaveSnapshot(snapshot)
	if not validSnapshot then
		return result(false, snapshotReason or "INVALID_SNAPSHOT")
	end
	if validSnapshot.Phase13 == nil or validSnapshot.Commerce == nil then
		return result(false, "UNSUPPORTED_WRITE_PHASE13")
	end

	local called, stored = pcall(function()
		return self._dataStore:UpdateAsync(key, function(raw, keyInfo)
			if envelopeStatus(raw) then
				return preserveKeyInfo(raw, keyInfo)
			end
			local transport = raw.Transport
			if transport.Version == ARCHIVE_TRANSPORT and (not transport.PaidArchive
				or validSnapshot.Commerce.PaidArchiveEpoch ~= raw.Data.Commerce.PaidArchiveEpoch) then
				return preserveKeyInfo(raw, keyInfo)
			end
			if
				transport.OwnerToken == nil
				and transport.LastOperationId == operationId
				and transport.LastRevision == revision
			then
				return preserveKeyInfo(raw, keyInfo)
			end
			if transport.OwnerToken ~= ownerToken or revision < transport.LastRevision then
				return preserveKeyInfo(raw, keyInfo)
			end
			local nextValue = clone(raw)
			nextValue.Data = clone(snapshot)
			nextValue.Transport.OwnerToken = nil
			nextValue.Transport.LeaseExpiresAt = 0
			nextValue.Transport.LastOperationId = operationId
			nextValue.Transport.LastRevision = revision
			return preserveKeyInfo(nextValue, keyInfo)
		end)
	end)
	if not called then
		return result(false, "RELEASE_UNCERTAIN", { error = tostring(stored), uncertain = true })
	end
	if envelopeStatus(stored) then
		return result(false, envelopeStatus(stored) :: string)
	end
	if
		stored.Transport.OwnerToken == nil
		and stored.Transport.LastOperationId == operationId
		and stored.Transport.LastRevision == revision
	then
		return result(true, "RELEASED")
	end
	return result(false, "OWNER_MISMATCH")
end

-- Archive keys are routing only. Full owner/receipt/metadata equality is always
-- checked; a hash collision is a conflict, never a deduplication match.
local function paidKey(profileKey: string, purchaseId: string): string
	local digest = Encoding:ComputeStringHash(profileKey .. "\0" .. purchaseId, Enum.HashAlgorithm.Sha256)
	local encoded = buffer.tostring(Encoding:Base64Encode(buffer.fromstring(digest)))
	return "paid1_" .. encoded:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
end
local function same(a: any, b: any): boolean
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in a do if not same(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end
local function ownerSafe(raw, token, at)
	return not envelopeStatus(raw) and raw.Transport.OwnerToken == token and raw.Transport.LeaseExpiresAt > at
end
local function noCache(store, key)
	local options = Instance.new("DataStoreGetOptions")
	options.UseCache = false
	return store:GetAsync(key, options)
end
function Store:_PaidBudget(required: number): boolean
	local ok, budget = pcall(function()
		return if self._archiveBudget then self._archiveBudget()
			else DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return ok and type(budget) == "number" and budget >= required
end
function Store:CanArchivePaidReceipts(): boolean
	return self._available and self._archiveEnabled
end
function Store:LookupPaidReceipt(key: string, ownerToken: string, purchaseId: string): any
	if not self._available then return result(false, "PERSISTENCE_UNAVAILABLE") end
	if not self:_PaidBudget(3) then return result(false, "PAID_ARCHIVE_BUDGET") end
	local called, value = pcall(function()
		local before = noCache(self._dataStore, key)
		if not ownerSafe(before, ownerToken, self._unixNow()) then return result(false, "OWNER_MISMATCH") end
		local epoch = before.Data.Commerce.PaidArchiveEpoch or 0
		local record = noCache(self._dataStore, paidKey(key, purchaseId))
		local after = noCache(self._dataStore, key)
		if not ownerSafe(after, ownerToken, self._unixNow()) then return result(false, "OWNER_MISMATCH") end
		if (after.Data.Commerce.PaidArchiveEpoch or 0) ~= epoch then return result(false, "PAID_ARCHIVE_LOOKUP_RETRY") end
		if record ~= nil and (type(record) ~= "table" or record.Version ~= 1
			or record.ProfileKey ~= key or record.PurchaseId ~= purchaseId or type(record.Receipt) ~= "table"
			or type(record.Receipt.ProductId) ~= "number" or record.Receipt.ProductId <= 0 or record.Receipt.ProductId % 1 ~= 0
			or type(record.Receipt.Amount) ~= "number" or record.Receipt.Amount <= 0 or record.Receipt.Amount > Config.MaxBalance
			or record.Receipt.Amount % 1 ~= 0 or type(record.Receipt.GrantedAt) ~= "number"
			or record.Receipt.GrantedAt ~= record.Receipt.GrantedAt or math.abs(record.Receipt.GrantedAt) == math.huge
			or type(record.Receipt.ConfigVersion) ~= "string" or type(record.Receipt.CommitRevision) ~= "number"
			or record.Receipt.CommitRevision < 0 or record.Receipt.CommitRevision % 1 ~= 0
			or record.Receipt.CommitRevision > after.Transport.LastRevision) then
			return result(false, "PAID_ARCHIVE_CONFLICT")
		end
		return result(true, "PAID_ARCHIVE_LOOKUP", { receipt = if record then clone(record.Receipt) else nil, epoch = epoch })
	end)
	return if called then value else result(false, "PAID_ARCHIVE_LOOKUP_UNAVAILABLE", { uncertain = true })
end
function Store:ArchivePaidReceipts(key: string, ownerToken: string, operationId: string, revision: number): any
	if not self._available then return result(false, "PERSISTENCE_UNAVAILABLE") end
	if not self:_PaidBudget(self._archiveRows * 2 + 3) then return result(false, "PAID_ARCHIVE_BUDGET") end
	local phase = "Read"
	local called, value = pcall(function()
		local raw = noCache(self._dataStore, key)
		if not ownerSafe(raw, ownerToken, self._unixNow()) then return result(false, "OWNER_MISMATCH") end
		if not self._archiveEnabled and raw.Transport.Version ~= ARCHIVE_TRANSPORT then return result(false, "PAID_ARCHIVE_DISABLED") end
		if raw.Transport.LastRevision ~= revision or revision >= Config.MaxBalance then return result(false, "STALE_REVISION") end
		local ids = {}
		for id, receipt in raw.Data.Commerce.ProcessedReceipts do
			if type(receipt.CommitRevision) == "number" and receipt.CommitRevision >= 0
				and receipt.CommitRevision % 1 == 0 and receipt.CommitRevision <= revision then table.insert(ids, id) end
		end
		table.sort(ids)
		while #ids > self._archiveRows do table.remove(ids) end
		if #ids == 0 then return result(false, "PAID_ARCHIVE_NO_CONFIRMED_ROWS") end
		local original = raw
		-- Same-size3->4 change: bootstrap still works at the valid entry-size ceiling.
		phase = "Fence"
		raw = self._dataStore:UpdateAsync(key, function(current, info)
			if not ownerSafe(current, ownerToken, self._unixNow()) or current.Transport.LastRevision ~= revision
				or not same(current.Data, original.Data) then return preserveKeyInfo(current, info) end
			local nextValue = clone(current)
			nextValue.Transport.Version = ARCHIVE_TRANSPORT
			return preserveKeyInfo(nextValue, info)
		end)
		if not ownerSafe(raw, ownerToken, self._unixNow()) or raw.Transport.Version ~= ARCHIVE_TRANSPORT
			or raw.Transport.LastRevision ~= revision or not same(raw.Data, original.Data) then return result(false, "OWNER_MISMATCH") end
		local epoch = raw.Data.Commerce.PaidArchiveEpoch or 0
		local previousCount = if raw.Transport.PaidArchive then raw.Transport.PaidArchive.Count else 0
		if epoch >= Config.MaxBalance or previousCount > Config.MaxBalance - #ids then return result(false, "PAID_ARCHIVE_LIMIT") end
		for _, id in ids do
			phase = "Copy"
			local receipt = raw.Data.Commerce.ProcessedReceipts[id]
			local record = { Version = 1, ProfileKey = key, PurchaseId = id, Receipt = clone(receipt) }
			local location = paidKey(key, id)
			if #location > 50 or #Http:JSONEncode(record) > 4194304 then
				return result(false, "PAID_ARCHIVE_RECORD_HEADROOM")
			end
			local copied = self._dataStore:UpdateAsync(location, function(existing, info)
				return preserveKeyInfo(if existing == nil then clone(record) else existing, info)
			end)
			if not same(copied, record) or not same(noCache(self._dataStore, location), record) then
				return result(false, "PAID_ARCHIVE_CONFLICT")
			end
		end
		phase = "Publish"
		local published = self._dataStore:UpdateAsync(key, function(current, info)
			if not ownerSafe(current, ownerToken, self._unixNow()) or current.Transport.LastRevision ~= revision
				or (current.Data.Commerce.PaidArchiveEpoch or 0) ~= epoch then return preserveKeyInfo(current, info) end
			for _, id in ids do if not same(current.Data.Commerce.ProcessedReceipts[id], raw.Data.Commerce.ProcessedReceipts[id]) then
				return preserveKeyInfo(current, info)
			end end
			local nextValue = clone(current)
			for _, id in ids do nextValue.Data.Commerce.ProcessedReceipts[id] = nil end
			nextValue.Data.Commerce.ReceiptCount -= #ids
			nextValue.Data.Commerce.PaidArchiveEpoch = epoch + 1
			nextValue.Transport.PaidArchive = { Epoch = epoch + 1, Count = previousCount + #ids }
			nextValue.Transport.LastRevision = revision + 1
			nextValue.Transport.LastOperationId = operationId
			-- Actual complete encoding, including retained ordinary fields/extensions.
			local bytes = #Http:JSONEncode(nextValue)
			if bytes > 4194304 or bytes >= #Http:JSONEncode(current) then return preserveKeyInfo(current, info) end
			return preserveKeyInfo(nextValue, info)
		end)
		if not ownerSafe(published, ownerToken, self._unixNow()) then return result(false, "OWNER_MISMATCH") end
		if published.Transport.LastOperationId ~= operationId or published.Transport.LastRevision ~= revision + 1 then
			return result(false, "PAID_ARCHIVE_PUBLICATION_PENDING")
		end
		return result(true, "PAID_ARCHIVE_PUBLISHED", { envelope = published, moved = #ids })
	end)
	return if called then value else result(false, "PAID_ARCHIVE_UNCERTAIN", { uncertain = true, phase = phase, error = tostring(value) })
end

return Store
