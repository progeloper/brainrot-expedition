--!strict
-- Whole charges and a single owner reserve. No cargo count, driver state,
-- income, equipment mutation or Burst clock belongs to this state machine.
local Runtime = {}
local WINDOW_SECONDS = 5

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Runtime.Create(at: number, lifecycleId: string): any
	assert(finite(at) and type(lifecycleId) == "string" and lifecycleId ~= "", "Shield lifecycle/time required")
	return { Capacity = 0, Remaining = 0, ProtectionExpiresAt = 0, Revision = 0,
		LifecycleId = lifecycleId, LastUpdatedAt = at, Enabled = true, BaseOccupancyKey = nil }
end

function Runtime.Advance(state: any, at: number): number
	assert(finite(at), "Shield time must be finite")
	at = math.max(at, state.LastUpdatedAt)
	state.LastUpdatedAt = at
	if state.ProtectionExpiresAt > 0 and at >= state.ProtectionExpiresAt then
		state.ProtectionExpiresAt = 0
		state.Revision += 1
	end
	return at
end

function Runtime.Reconcile(state: any, at: number, capacity: number, enabled: boolean, ownBaseOccupancyKey: string?): any
	Runtime.Advance(state, at)
	assert(finite(capacity) and capacity % 1 == 0 and capacity >= 0 and capacity <= 3, "Shield capacity must be integer 0..3")
	local before = state.Remaining
	local capacityChanged = capacity ~= state.Capacity
	local enabledChanged = enabled ~= state.Enabled
	if not enabled then
		-- Explicit disable clears earned protection, but preserves the expedition's
		-- spent reserve. An unavailable derived reader must not erase it here.
		if state.Enabled or state.ProtectionExpiresAt > 0 then
			state.Enabled = false
			state.ProtectionExpiresAt = 0
			state.Revision += 1
		end
		state.BaseOccupancyKey = nil
		return { refilled = false, increasedBy = 0 }
	end
	state.Enabled = true
	state.Capacity = capacity
	state.Remaining = math.min(state.Remaining, capacity)
	if ownBaseOccupancyKey and (state.BaseOccupancyKey ~= ownBaseOccupancyKey or capacityChanged or enabledChanged) then
		state.Remaining = capacity
	end
	state.BaseOccupancyKey = ownBaseOccupancyKey
	if enabledChanged or capacityChanged or before ~= state.Remaining then state.Revision += 1 end
	return { refilled = state.Remaining > before, increasedBy = math.max(0, state.Remaining - before) }
end

-- Only called after the service has accepted and deduplicated a valid cargo
-- attack. At exactly the deadline the old window has ended.
function Runtime.ResolveAttack(state: any, at: number): any
	at = Runtime.Advance(state, at)
	if not state.Enabled then return { accepted = false, code = "DISABLED", protected = false, allowKnockoff = false, consumed = false } end
	if at < state.ProtectionExpiresAt then
		return { accepted = true, code = "PROTECTED", protected = true, allowKnockoff = false, consumed = false }
	end
	if state.Capacity > 0 and state.Remaining > 0 then
		state.Remaining -= 1
		state.ProtectionExpiresAt = at + WINDOW_SECONDS
		state.Revision += 1
		return { accepted = true, code = "BLOCKED", protected = true, allowKnockoff = false, consumed = true }
	end
	return { accepted = true, code = "ALLOW_KNOCKOFF", protected = false, allowKnockoff = true, consumed = false }
end

return table.freeze(Runtime)
