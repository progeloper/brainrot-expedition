--!strict
-- D1 combo. Pure. A KO within WindowSeconds of the same player's previous KO raises the combo (cap x6);
-- after WindowSeconds without one it resets. Meter-only: no Cash or Gems.
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)

export type State = { n: number, expiresAt: number }

local ComboState = {}

function ComboState.New(): State
	return { n = 0, expiresAt = -math.huge }
end

-- Register a KO at time t. Returns the new combo count.
function ComboState.OnKO(state: State, t: number): number
	if t <= state.expiresAt and state.n > 0 then
		state.n = math.min(CoreLoop.Combo.Cap, state.n + 1)
	else
		state.n = 1
	end
	state.expiresAt = t + CoreLoop.Combo.WindowSeconds
	return state.n
end

-- Advance to time t. If the window lapsed, resets and returns the combo that just ended (else nil).
function ComboState.Step(state: State, t: number): number?
	if state.n > 0 and t > state.expiresAt then
		local ended = state.n
		state.n = 0
		return ended
	end
	return nil
end

function ComboState.Current(state: State, t: number): number
	return if t <= state.expiresAt then state.n else 0
end

function ComboState.MagnetActive(state: State, t: number): boolean
	return ComboState.Current(state, t) >= CoreLoop.Combo.MagnetAt
end

-- "COMBO xN!" end sting only for combos of x3 or more.
function ComboState.ShowsEnd(ended: number?): boolean
	return ended ~= nil and ended >= 3
end

return table.freeze(ComboState)
