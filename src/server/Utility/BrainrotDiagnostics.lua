--!strict
-- Temporary, server-only observability. No gameplay state, events, waits or retries.
local RunService = game:GetService("RunService")
local Environment = require(game:GetService("ReplicatedStorage").Shared.Config.Environment)
local Trace = {}
local enabled = RunService:IsServer()
	and RunService:IsStudio()
	and Environment.Name == "Development"
	and Environment.BrainrotDepositDiagnosticsEnabled
	and game:GetAttribute("BrainrotTestDiagnosticsDisabled") ~= true
local identities: any = setmetatable({}, { __mode = "k" })
local samples: any = setmetatable({}, { __mode = "k" })
local batches: any = setmetatable({}, { __mode = "k" })
local contexts: any = setmetatable({}, { __mode = "k" })
local sequence, identitySequence = 0, 0

function Trace.Enabled(): boolean
	return enabled
end

function Trace.Id(value: any): string
	if value == nil then
		return "none"
	end
	if not enabled then
		return "disabled"
	end
	if not identities[value] then
		identitySequence += 1
		identities[value] = "D" .. identitySequence
	end
	return identities[value]
end

local function scalar(value: any): string
	if value == nil then
		return "none"
	end
	if typeof(value) == "Instance" then
		local ok, path = pcall(value.GetFullName, value)
		value = if ok then path else "destroyed"
	elseif type(value) == "table" then
		value = Trace.Id(value)
	end
	local text = tostring(value):gsub("\r", "\\r"):gsub("\n", "\\n")
	return if text == ""
			or text:find("%s")
			or text:find('"')
		then string.format("%q", text)
		else text
end

-- Lazy details and formatting are protected independently of the gameplay operation.
function Trace.Emit(phase: string, stage: string, details: any?, warning: boolean?)
	if not enabled then
		return
	end
	local ok, failure = pcall(function()
		local scope = contexts[coroutine.running()]
		local fields: any = { attempt = "none", userId = "none", baseId = "none", cartId = "none" }
		if scope then
			for key, value in scope.Fields do
				fields[key] = value
			end
		end
		local supplied = if type(details) == "function" then details() else details
		for key, value in supplied or {} do
			fields[key] = value
		end
		fields.phase, fields.stage, fields.tMs = phase, stage, math.floor(os.clock() * 1000)
		local parts, keys = { "[BRAINROT_TRACE]" }, {}
		for _, key in { "phase", "stage", "attempt", "userId", "baseId", "cartId" } do
			table.insert(parts, key .. "=" .. scalar(fields[key]))
			fields[key] = nil
		end
		for key in fields do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			table.insert(parts, key .. "=" .. scalar(fields[key]))
		end
		local line = table.concat(parts, " ")
		local batch = scope and scope.Batch
		-- Retain the FIRST precise failed gate, not just an eventual generic BUSY code.
		if batch and batch.Gate == nil and supplied then
			local result = supplied.result
			if
				stage == "item_reject"
				or stage == "item_context_reject"
				or stage == "commit_reject"
				or (
					(stage == "reserve_result" or stage == "detach_exit" or stage == "item_end")
					and result ~= "reserved"
					and result ~= "detached"
					and result ~= "DEPOSITED"
				)
			then
				batch.Gate = stage .. ":" .. tostring(supplied.reason or result)
			end
		end
		if batch and not batch.Full then
			-- Keep the complete small bounded transaction, so a changed failure can be replayed.
			if #batch.Lines < 512 then
				table.insert(batch.Lines, { line, warning })
			end
		else
			(if warning then warn else print)(line)
		end
	end)
	if not ok then
		warn(
			"[BRAINROT_TRACE] phase=BOOT stage=diagnostic_error attempt=none userId=none baseId=none cartId=none tMs="
				.. tostring(math.floor(os.clock() * 1000))
				.. " reason="
				.. scalar(failure)
		)
	end
end

function Trace.Scope(fields: any): any
	if not enabled then
		return nil
	end
	local thread = coroutine.running()
	local previous = contexts[thread]
	local scope = {
		Previous = previous,
		Fields = if previous then table.clone(previous.Fields) else {},
		Batch = previous and previous.Batch,
	}
	for key, value in fields do
		scope.Fields[key] = value
	end
	contexts[thread] = scope
	return scope
end

function Trace.Close(scope: any)
	if scope and contexts[coroutine.running()] == scope then
		contexts[coroutine.running()] = scope.Previous
	end
end

-- Each owner has a fixed set of channels. Signatures replace, never accumulate.
function Trace.Due(owner: any, channel: string, signature: string, periodic: boolean?): boolean
	if not enabled or owner == nil then
		return false
	end
	local entries = samples[owner]
	if not entries then
		entries = {}
		samples[owner] = entries
	end
	local previous = entries[channel]
	local now = os.clock()
	if
		not previous
		or previous.Signature ~= signature
		or (periodic ~= false and now - previous.At >= 5)
	then
		entries[channel] = { Signature = signature, At = now }
		return true
	end
	return false
end

function Trace.BeginBatch(cart: Model, fields: any, signature: string): any
	if not enabled then
		return nil
	end
	sequence += 1
	-- Only identities belong in inherited context. Counts/revisions are point-in-time
	-- observations and must never reappear as stale truth after a commit/reservation.
	local identityFields = { attempt = string.format("U%03d", sequence) }
	for _, key in { "userId", "baseId", "cartId", "cart", "storage" } do
		identityFields[key] = fields[key]
	end
	local scope = Trace.Scope(identityFields)
	local previous = batches[cart]
	local batch = {
		Full = not previous or previous.Signature ~= signature,
		Lines = {},
		Previous = previous,
		Signature = signature,
		Cart = cart,
		At = os.clock(),
	}
	scope.Batch = batch
	return scope
end

function Trace.EndBatch(scope: any, reason: string, details: any)
	if not scope then
		return
	end
	-- A nested operation may have thrown before closing its diagnostic scope.
	contexts[coroutine.running()] = scope
	Trace.Emit("5C", "batch_end", details, reason == "internal_failure")
	local batch, previous = scope.Batch, scope.Batch.Previous
	local changed = not previous or previous.Reason ~= reason or previous.Gate ~= batch.Gate
	if not batch.Full and changed then
		for _, entry in batch.Lines do
			(if entry[2] then warn else print)(entry[1])
		end
	end
	local repeats = if changed or batch.Full then 0 else previous.Repeats + 1
	local lastAt = if changed or batch.Full then batch.At else previous.At
	if not batch.Full and not changed and batch.At - lastAt >= 5 then
		scope.Batch = nil
		Trace.Emit("5C", "batch_repeat", function()
			local fields = if type(details) == "function" then details() else table.clone(details)
			fields.repetitions, fields.reason = repeats, reason
			fields.gate = batch.Gate or reason
			return fields
		end, reason ~= "complete" and reason ~= "full")
		lastAt = batch.At
	end
	batches[batch.Cart] = {
		Signature = batch.Signature,
		Reason = reason,
		Gate = batch.Gate,
		Repeats = repeats,
		At = lastAt,
	}
	Trace.Close(scope)
end

function Trace.ResetBatch(cart: any)
	if cart then
		batches[cart] = nil
	end
end

function Trace.Forget(owner: any)
	if owner then
		samples[owner], batches[owner], identities[owner] = nil, nil, nil
	end
end

-- Read-only field builders; call inside Emit's protected lazy callback.
function Trace.Fields(player: Player?, cart: Model?, storage: any): any
	local result: any = {
		userId = if player then player.UserId else nil,
		cartId = if cart then cart:GetAttribute("CartId") or "none" else nil,
		cart = cart,
		storage = Trace.Id(storage),
		baseId = if storage then storage.BaseId else "none",
	}
	if storage then
		result.storageRevision = storage:GetRevision()
		result.storageCount = if storage.GetOccupiedCount
			then storage:GetOccupiedCount()
			else "unavailable"
		result.capacity = if storage.GetSlotCapacity
			then storage:GetSlotCapacity()
			else "unavailable"
		result.freeSlots = if storage.GetAvailableSlotCount
			then storage:GetAvailableSlotCount()
			else "unavailable"
		result.reserved = if type(result.capacity) == "number"
				and type(result.storageCount) == "number"
				and type(result.freeSlots) == "number"
			then result.capacity - result.storageCount - result.freeSlots
			else "unavailable"
		result.storageActive, result.storageOwner = storage:IsActive(), storage.OwnerUserId
	end
	return result
end

return Trace
