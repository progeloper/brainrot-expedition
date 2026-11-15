--!nocheck

local Schema = require(script.Parent.Parent.Parent.Data.PlayerProfileSchema)

local FakeBackend = {}
FakeBackend.__index = FakeBackend

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

function FakeBackend.new(options)
	local opts = options or {}
	return setmetatable({
		Available = opts.Available ~= false,
		Now = opts.Now or function()
			return 1000
		end,
		Records = clone(opts.Records or {}),
		Events = {},
		AcquireFailure = opts.AcquireFailure,
		CommitThenFailAcquireCount = opts.CommitThenFailAcquireCount or 0,
		BeforeAcquireReturn = opts.BeforeAcquireReturn,
		BeforeSaveReturn = opts.BeforeSaveReturn,
		CommitThenFailSaveCount = opts.CommitThenFailSaveCount or 0,
		FailBeforeSaveCount = opts.FailBeforeSaveCount or 0,
		FinalSaveFailure = opts.FinalSaveFailure,
		FinalSaveFailureKeys = clone(opts.FinalSaveFailureKeys or {}),
	}, FakeBackend)
end

function FakeBackend:IsAvailable()
	return self.Available
end

function FakeBackend:Acquire(key, token, leaseDuration)
	table.insert(self.Events, { kind = "Acquire", key = key, token = token })
	if self.AcquireFailure then
		return { ok = false, code = self.AcquireFailure }
	end
	local record = self.Records[key]
	local isNew = false
	if not record then
		isNew = true
		record = {
			Data = Schema.CreateDefault(),
			OwnerToken = nil,
			LeaseExpiresAt = 0,
			LastRevision = 0,
			LastOperationId = nil,
		}
		self.Records[key] = record
	end
	if
		record.OwnerToken ~= nil
		and record.OwnerToken ~= token
		and record.LeaseExpiresAt > self.Now()
	then
		return { ok = false, code = "SESSION_LOCKED", leaseExpiresAt = record.LeaseExpiresAt }
	end
	local migrated, reason, changed = Schema.Migrate(record.Data)
	if not migrated then
		return { ok = false, code = reason }
	end
	record.Data = clone(migrated)
	record.OwnerToken = token
	record.LeaseExpiresAt = self.Now() + leaseDuration
	local response = {
		ok = true,
		code = "ACQUIRED",
		data = clone(record.Data),
		isNew = isNew,
		migrated = changed == true,
		leaseExpiresAt = record.LeaseExpiresAt,
		lastRevision = record.LastRevision,
	}
	if self.BeforeAcquireReturn then
		self.BeforeAcquireReturn(self, key, response)
	end
	if self.CommitThenFailAcquireCount > 0 then
		self.CommitThenFailAcquireCount -= 1
		return { ok = false, code = "ACQUIRE_FAILED", uncertain = true }
	end
	return response
end

function FakeBackend:Save(key, token, operationId, revision, snapshot, leaseDuration)
	table.insert(self.Events, {
		kind = "Save",
		key = key,
		token = token,
		operationId = operationId,
		revision = revision,
	})
	local record = self.Records[key]
	if not record or record.OwnerToken ~= token then
		return { ok = false, code = "OWNER_MISMATCH" }
	end
	if record.LastOperationId == operationId and record.LastRevision == revision then
		return { ok = true, code = "SAVED", leaseExpiresAt = record.LeaseExpiresAt }
	end
	if self.FailBeforeSaveCount > 0 then
		self.FailBeforeSaveCount -= 1
		return { ok = false, code = "SAVE_UNCERTAIN", uncertain = true }
	end
	record.Data = clone(snapshot)
	record.LastRevision = revision
	record.LastOperationId = operationId
	record.LeaseExpiresAt = self.Now() + leaseDuration
	if self.BeforeSaveReturn then
		self.BeforeSaveReturn(self, key, revision)
	end
	if self.CommitThenFailSaveCount > 0 then
		self.CommitThenFailSaveCount -= 1
		return { ok = false, code = "SAVE_UNCERTAIN", uncertain = true }
	end
	return { ok = true, code = "SAVED", leaseExpiresAt = record.LeaseExpiresAt }
end

function FakeBackend:Renew(key, token, operationId, leaseDuration)
	local record = self.Records[key]
	if not record or record.OwnerToken ~= token then
		return { ok = false, code = "OWNER_MISMATCH" }
	end
	record.LastOperationId = operationId
	record.LeaseExpiresAt = self.Now() + leaseDuration
	return { ok = true, code = "RENEWED", leaseExpiresAt = record.LeaseExpiresAt }
end

function FakeBackend:Release(key, token, operationId, revision, snapshot)
	table.insert(self.Events, {
		kind = "Release",
		key = key,
		token = token,
		operationId = operationId,
		revision = revision,
	})
	local record = self.Records[key]
	if not record then
		return { ok = false, code = "OWNER_MISMATCH" }
	end
	if
		record.OwnerToken == nil
		and record.LastOperationId == operationId
		and record.LastRevision == revision
	then
		return { ok = true, code = "RELEASED" }
	end
	if record.OwnerToken ~= token then
		return { ok = false, code = "OWNER_MISMATCH" }
	end
	if self.FinalSaveFailure or self.FinalSaveFailureKeys[key] then
		return { ok = false, code = "RELEASE_UNCERTAIN", uncertain = true }
	end
	record.Data = clone(snapshot)
	record.LastRevision = revision
	record.LastOperationId = operationId
	record.OwnerToken = nil
	record.LeaseExpiresAt = 0
	return { ok = true, code = "RELEASED" }
end

function FakeBackend:ForceOwner(key, token, leaseExpiresAt)
	local record = self.Records[key]
	if not record then
		record = {
			Data = Schema.CreateDefault(),
			LastRevision = 0,
		}
		self.Records[key] = record
	end
	record.OwnerToken = token
	record.LeaseExpiresAt = leaseExpiresAt
end

function FakeBackend:GetRecord(key)
	return clone(self.Records[key])
end

return FakeBackend
