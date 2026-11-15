--!strict
-- C1 Lucky Meter + C3 hard pity. Pure: callers pass time/hunting seconds; no service calls.
-- The meter is session-only. Gains are once per individual per hunter; combo >= x3 doubles KO gains,
-- RUSH/MEGA x1.5, first session x2. At Max the caller orders a Lucky Star and the meter resets.
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)

export type Event =
	"SnackKO"
	| "StarKO"
	| "SuperKO"
	| "JackpotKO"
	| "SneakShot"
	| "Sneaky"
	| "CleanEscape"
export type Context = { combo: number?, rush: boolean?, firstSession: boolean? }
export type State = {
	value: number,
	credited: { [string]: { [string]: boolean } }, -- event -> individual id -> true
	-- Pity, in hunting seconds since the last qualifying SPAWN for this hunter.
	sinceSuper: number,
	sinceJackpot: number,
	sinceMutation: number,
	firstSession: boolean,
}

local LuckState = {}

local BASE: { [Event]: number } = {
	SnackKO = CoreLoop.Meter.Snack,
	StarKO = CoreLoop.Meter.Star,
	SuperKO = CoreLoop.Meter.Super,
	JackpotKO = CoreLoop.Meter.Jackpot,
	SneakShot = CoreLoop.Meter.SneakShot,
	Sneaky = CoreLoop.Meter.Sneaky,
	CleanEscape = CoreLoop.Meter.CleanEscape,
}
local KO_EVENTS = { SnackKO = true, StarKO = true, SuperKO = true, JackpotKO = true }

function LuckState.New(firstSession: boolean?): State
	return {
		value = 0,
		credited = {},
		sinceSuper = 0,
		sinceJackpot = 0,
		sinceMutation = 0,
		firstSession = firstSession == true,
	}
end

-- The meter gain this event would give (before the once-per-individual rule).
function LuckState.GainFor(event: Event, ctx: Context?): number
	local c = ctx or {} :: Context
	local gain = BASE[event] or 0
	if KO_EVENTS[event] and (c.combo or 0) >= CoreLoop.Meter.ComboDoubleAt then
		gain *= 2
	end
	if c.rush then
		gain *= CoreLoop.Meter.RushMult
	end
	if c.firstSession then
		gain *= CoreLoop.Meter.FirstSessionMult
	end
	return gain
end

-- Apply an event. individualId makes it once per individual (nil = always credited, e.g. CleanEscape).
-- Returns (gained, becameFull).
function LuckState.Apply(
	state: State,
	event: Event,
	individualId: string?,
	ctx: Context?
): (number, boolean)
	if individualId then
		local seen = state.credited[event]
		if not seen then
			seen = {}
			state.credited[event] = seen
		end
		if seen[individualId] then
			return 0, false
		end
		seen[individualId] = true
	end
	local c = table.clone(ctx or {}) :: Context
	c.firstSession = c.firstSession or state.firstSession
	local gain = LuckState.GainFor(event, c)
	if gain <= 0 then
		return 0, false
	end
	local before = state.value
	state.value = math.min(CoreLoop.Meter.Max, state.value + gain)
	return state.value - before, before < CoreLoop.Meter.Max and state.value >= CoreLoop.Meter.Max
end

function LuckState.IsFull(state: State): boolean
	return state.value >= CoreLoop.Meter.Max
end

function LuckState.Reset(state: State)
	state.value = 0
end

-- Displayed percent (integer). Fills under 4% are hidden by the HUD (14 Nov progress-bar rule).
function LuckState.Percent(state: State): number
	return math.floor(state.value / CoreLoop.Meter.Max * 100)
end

------------------------------------------------------------------ pity (C3)
local function pityLimits(state: State): (number, number, number)
	local p, f = CoreLoop.Pity, CoreLoop.FirstSession
	if state.firstSession then
		return f.SuperPity, f.JackpotPity, f.MutationPity
	end
	return p.SuperSeconds, p.JackpotSeconds, p.MutationSeconds
end

function LuckState.AddHunting(state: State, seconds: number)
	state.sinceSuper += seconds
	state.sinceJackpot += seconds
	state.sinceMutation += seconds
end

-- A spawn for this hunter: resets the matching timers ("since a Super+ Star last SPAWNED").
function LuckState.OnSpawn(state: State, trueGrade: string?, mutated: boolean)
	if trueGrade == "Jackpot" then
		state.sinceJackpot = 0
		state.sinceSuper = 0
	elseif trueGrade == "Super" then
		state.sinceSuper = 0
	end
	if mutated then
		state.sinceMutation = 0
	end
end

-- The forced Star the next herd needs, if any: "Jackpot" beats "Super". Mutation pity is separate.
function LuckState.DueStar(state: State): ("Super" | "Jackpot")?
	local superLimit, jackpotLimit = pityLimits(state)
	if state.sinceJackpot >= jackpotLimit then
		return "Jackpot"
	elseif state.sinceSuper >= superLimit then
		return "Super"
	end
	return nil
end

function LuckState.DueMutation(state: State): boolean
	local _, _, mutationLimit = pityLimits(state)
	return state.sinceMutation >= mutationLimit
end

function LuckState.EndFirstSession(state: State)
	state.firstSession = false
end

return table.freeze(LuckState)
