-- Frozen Transport3 writer fixture, captured 2026-10-22 before archival changes.
--!strict

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Config = require(game:GetService("ServerScriptService").Server.Config.PlayerDataConfig)
local Schema = require(game:GetService("ServerScriptService").Server.Data.PlayerProfileSchema)

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
		and (value.Version == Config.TransportVersion or allowLegacy == true and Config.LegacyTransportVersions[value.Version] == true)
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
		available = Environment.EnableDataSaving and not (RunService:IsStudio() and Environment.IsProduction)
	end
	available = available == true and Config.Phase8MigrationReady
	if dataStore == nil and available then
		dataStore = DataStoreService:GetDataStore(Config.StoreName, Config.StoreScope)
	end
	return setmetatable({
		_dataStore = dataStore,
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
			migratedDuringAcquire = changed == true or transport.Version ~= Config.TransportVersion
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
				transportTo = Config.TransportVersion,
				currencyFrom = raw.Data.CurrencyVersion or 1,
				currencyTo = migrated.CurrencyVersion,
				monetaryFieldCount = if raw.Data.CurrencyVersion == 2 then 0 else 13,
				legacyRegions = table.concat(legacyRegions, ","),
				legacyGrantVersion = migrated.WorldProgression.LegacyGrantVersion,
			}
			local nextValue = clone(raw)
			nextValue.Data = migrated
			nextValue.Transport.Version = Config.TransportVersion
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
	if stored.Transport.Version ~= Config.TransportVersion or stored.Data.CurrencyVersion ~= 2 then
		return result(false, "CURRENCY_NOT_CONFIRMED")
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
		or template.Transport.Version ~= Config.TransportVersion
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

return Store
