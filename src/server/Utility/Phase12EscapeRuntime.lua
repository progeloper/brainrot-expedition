--!strict
-- Pure handling state transitions. The existing ordinary ledger owns this state.
local Runtime = {}
function Runtime.Pickup(state, config, now, roll)
	local nextState = table.clone(state)
	nextState.CapturedOnce = true
	nextState.EscapeMaxAttempts = config.MaxAttempts
	if nextState.ResetPausedGeneration ~= nil then
		return nextState
	end
	if nextState.EscapeAttemptsUsed >= config.MaxAttempts or config.MaxAttempts == 0 then
		nextState.EscapeDeadline = nil
		nextState.EscapeRemainingSeconds = nil
	elseif nextState.EscapeDeadline == nil then
		local remaining = nextState.EscapeRemainingSeconds
		if remaining == nil then
			local u = roll()
			assert(type(u) == "number" and u >= 0 and u <= 1, "Invalid escape RNG")
			remaining = config.MinDelay + (config.MaxDelay - config.MinDelay) * u
			nextState.EscapeGeneration = (nextState.EscapeGeneration or 0) + 1
			nextState.EscapeRolledDelay = remaining
		end
		nextState.EscapeDeadline = now + remaining
		nextState.EscapeRemainingSeconds = nil
	end
	return nextState
end
function Runtime.Pause(state, now)
	local nextState = table.clone(state)
	if nextState.EscapeDeadline ~= nil then
		nextState.EscapeRemainingSeconds = math.max(0, nextState.EscapeDeadline - now)
		nextState.EscapeDeadline = nil
	end
	return nextState
end
function Runtime.CommitJump(state, now, recaptureHp)
	if
		state.ResetPausedGeneration ~= nil
		or state.Retired
		or state.EscapeDeadline == nil
		or now < state.EscapeDeadline
		or state.EscapeAttemptsUsed >= state.EscapeMaxAttempts
	then
		return nil, "NOT_DUE"
	end
	local nextState = table.clone(state)
	nextState.EscapeAttemptsUsed += 1
	nextState.EscapeDeadline = nil
	nextState.EscapeRemainingSeconds = nil
	nextState.RemainingHp = state.MaxHp or recaptureHp
	nextState.WarningGeneration = 0
	nextState.EscapeGeneration = (nextState.EscapeGeneration or 0) + 1
	return nextState
end
function Runtime.PauseForReset(state, at, generation)
	if state.ResetPausedGeneration == generation then
		return table.clone(state)
	end
	local nextState = Runtime.Pause(state, at)
	nextState.ResetPausedGeneration = generation
	return nextState
end
function Runtime.ResumeAfterReset(state, at, generation)
	if state.ResetPausedGeneration ~= generation then
		return nil, "STALE_RESET_GENERATION"
	end
	local nextState = table.clone(state)
	nextState.ResetPausedGeneration = nil
	if nextState.EscapeRemainingSeconds ~= nil and nextState.EscapeAttemptsUsed < nextState.EscapeMaxAttempts then
		nextState.EscapeDeadline = at + nextState.EscapeRemainingSeconds
		nextState.EscapeRemainingSeconds = nil
	end
	return nextState
end
return table.freeze(Runtime)
