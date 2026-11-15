--!strict
-- §4 lifecycle as a pure transition table. The server systems drive these events; this module only
-- answers "is this transition legal, and where does it go". Anything not listed is illegal.
export type LState =
	"Ordered"
	| "Pop"
	| "Calm"
	| "Flee"
	| "Rest"
	| "Exhausted"
	| "Stagger"
	| "Asleep"
	| "Groggy"
	| "Saved"
	| "Cargo"
	| "Banked"
	| "Escaped"
	| "Leaving"
	| "Dive"
	| "Ambient"
	| "Retired"

local T: { [string]: { [string]: LState } } = {
	Ordered = { Placed = "Pop", PlacementFailed = "Retired" },
	Pop = { PopDone = "Calm", KO = "Asleep" },
	Calm = {
		Spotted = "Flee",
		Hit = "Stagger",
		KO = "Asleep",
		StarExpiring = "Leaving",
		OwnerGone = "Ambient",
		RetireUnseen = "Retired",
	},
	Flee = { Rest = "Rest", Exhaust = "Exhausted", Hit = "Stagger", KO = "Asleep", Lost = "Calm" },
	Rest = {
		Spotted = "Flee",
		Exhaust = "Exhausted",
		Hit = "Stagger",
		KO = "Asleep",
		EncounterReset = "Calm",
	},
	Exhausted = { Recovered = "Calm", Hit = "Stagger", KO = "Asleep" },
	Stagger = { Recovered = "Flee", KO = "Asleep" },
	Asleep = { Wake = "Groggy", Scooped = "Cargo", OverflowNearFullCart = "Saved" },
	Saved = { Scooped = "Cargo", Wake = "Groggy" },
	Groggy = { Recovered = "Calm", Hit = "Stagger", KO = "Asleep" },
	Cargo = { Bank = "Banked", Escape = "Escaped" },
	Escaped = { Landed = "Calm" },
	Leaving = { DiveStart = "Dive", Hit = "Stagger", KO = "Asleep" },
	Dive = { DiveDone = "Retired" },
	Ambient = {
		RetireUnseen = "Retired",
		Spotted = "Flee",
		Hit = "Stagger",
		KO = "Asleep",
		StarExpiring = "Leaving",
	},
	Banked = {},
	Retired = {},
}

local Rules = {}

Rules.Table = T

function Rules.Next(state: LState, event: string): LState?
	local row = T[state]
	return if row then row[event] else nil
end

function Rules.IsTerminal(state: LState): boolean
	return state == "Banked" or state == "Retired"
end

-- States in which retirement is forbidden by A7 rule zero.
function Rules.IsProtected(state: LState): boolean
	return state == "Asleep" or state == "Saved" or state == "Cargo" or state == "Dive"
end

return table.freeze(Rules)
