--!strict
-- Elapsed-time accumulator shared by the actual server sampler and focused tests.
local Stuck = {}
export type State = { Reference: Vector3?, StartedAt: number?, NextRetryAt: number }

function Stuck.Create(): State
	return { Reference = nil, StartedAt = nil, NextRetryAt = 0 }
end

function Stuck.Clear(state: State)
	state.Reference, state.StartedAt, state.NextRetryAt = nil, nil, 0
end

function Stuck.Step(state: State, position: Vector3, eligible: boolean, now: number, config: any): boolean
	if
		not eligible
		or now ~= now
		or math.abs(now) == math.huge
		or position.X ~= position.X
		or position.Z ~= position.Z
		or math.abs(position.X) == math.huge
		or math.abs(position.Z) == math.huge
	then
		Stuck.Clear(state)
		return false
	end
	local horizontal = Vector3.new(position.X, 0, position.Z)
	if
		not state.Reference
		or not state.StartedAt
		or now < state.StartedAt
		or (horizontal - state.Reference).Magnitude >= config.MeaningfulProgressStuds
	then
		state.Reference, state.StartedAt, state.NextRetryAt = horizontal, now, 0
		return false
	end
	if now - state.StartedAt < config.BlockedIntentSeconds or now < state.NextRetryAt then
		return false
	end
	state.NextRetryAt = now + config.RetryInterval
	return true
end

return table.freeze(Stuck)
