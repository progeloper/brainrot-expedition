--!strict
-- H1 BRAINROT RUSH clock. Pure function of (now, clockStart). Each 300 s cycle ends with a RUSH
-- (60 s); every 3rd cycle ends with a MEGA RUSH (90 s). Warning covers the 60 s before a rush starts.
-- This clock has no cycle id and never touches Phase12CycleId (J2).
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)

export type State = "Idle" | "Warning" | "Rush" | "Mega"
export type Snapshot = {
	state: State,
	cycle: number, -- 1-based cycle index
	mega: boolean, -- the rush of this cycle is a MEGA RUSH
	rushStartsAt: number,
	rushEndsAt: number,
	megaIndex: number?, -- 1-based MEGA count for this cycle's rush (K4 idempotency key)
}

local RushClock = {}

function RushClock.At(now: number, clockStart: number): Snapshot
	local cfg = CoreLoop.Rush
	local elapsed = math.max(0, now - clockStart)
	local index = math.floor(elapsed / cfg.CycleSeconds) -- 0-based
	local cycleEnd = clockStart + (index + 1) * cfg.CycleSeconds
	local mega = (index + 1) % cfg.MegaEvery == 0
	local length = if mega then cfg.MegaSeconds else cfg.RushSeconds
	local rushStartsAt = cycleEnd - length
	local state: State = "Idle"
	if now >= rushStartsAt then
		state = if mega then "Mega" else "Rush"
	elseif now >= rushStartsAt - cfg.WarnSeconds then
		state = "Warning"
	end
	return {
		state = state,
		cycle = index + 1,
		mega = mega,
		rushStartsAt = rushStartsAt,
		rushEndsAt = cycleEnd,
		megaIndex = if mega then (index + 1) // cfg.MegaEvery else nil,
	}
end

-- The rush kind that gameplay modifiers use ("Idle" outside an active rush).
function RushClock.ActiveKind(snapshot: Snapshot): "Idle" | "Rush" | "Mega"
	return if snapshot.state == "Rush" or snapshot.state == "Mega" then snapshot.state else "Idle"
end

return table.freeze(RushClock)
