--!strict
-- Pure local cosmetic policy. Caller owns the ONE existing frame scheduler,
-- focus subscriptions, supported Stats reads and preference persistence.
-- This module writes no Instance, graphics setting, remote or DataStore.
local Policy = {}
local TIERS = { Low = 1, Medium = 2, High = 3 }
local NAMES = { "Low", "Medium", "High" }
local WINDOW_SECONDS = 5
local MAX_SAMPLES = 2048
local MAX_TRANSITIONS = 32

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function positive(value: any): number?
	return if finite(value) and value > 0 then value else nil
end
local function mode(value: any): string
	return if value == "Low" or value == "Medium" or value == "High" then value else "Auto"
end
local function graphics(value: any): number?
	-- Automatic.Value==0 is a preference, never a weak-hardware benchmark.
	return if finite(value) and value % 1 == 0 and value >= 1 and value <= 10 then value else nil
end
local function percentile(values: { number }, proportion: number): number?
	if #values == 0 then
		return nil
	end
	table.sort(values)
	return values[math.max(1, math.ceil(#values * proportion))]
end

function Policy.new(options: any?)
	options = if type(options) == "table" then options else {}
	-- Current build's verified ~67 ms baseline requires conservative Low.
	-- A caller with separately validated evidence may explicitly choose Medium.
	local initial = if TIERS[options.initialAutoTier] then options.initialAutoTier else "Low"
	local state: any = {
		autoTier = TIERS[initial],
		selectedMode = "Auto",
		savedQuality = nil,
		ready = false,
		focused = nil,
		readyAt = nil,
		settleUntil = math.huge,
		samples = table.create(MAX_SAMPLES),
		head = 1,
		count = 0,
		lastRecordedAt = nil,
		lastStepAt = nil,
		lastEvaluationAt = nil,
		lastValidEvaluationAt = nil,
		degradeEvaluations = 0,
		severeEvaluations = 0,
		recoverySeconds = 0,
		validSinceDowngrade = 20,
		validEvaluationSeconds = 0,
		transitions = {},
		invalidSamples = 0,
		evaluations = 0,
		status = "LOADING",
		p90Ms = nil,
		pacingClass = "Unavailable",
		cpuMs = nil,
		gpuMs = nil,
		memoryMb = nil,
		memoryDeltaMb = nil,
		memoryStartMb = nil,
		graphicsCeiling = "High",
		busySamples = {},
		busyP90Ms = nil,
		measurementsAt = nil,
	}
	local api = {}
	local function effective(): string
		return if state.selectedMode ~= "Auto" then state.selectedMode else NAMES[state.autoTier]
	end
	local function clearWindow()
		table.clear(state.samples)
		state.head, state.count, state.lastRecordedAt = 1, 0, nil
		state.degradeEvaluations, state.severeEvaluations, state.recoverySeconds = 0, 0, 0
		state.p90Ms, state.pacingClass = nil, "Unavailable"
		state.lastValidEvaluationAt = nil
		table.clear(state.busySamples)
		state.busyP90Ms = nil
	end
	local function transition(nextTier: number, at: number, reason: string)
		if nextTier == state.autoTier then
			return
		end
		local previous = state.autoTier
		state.autoTier = nextTier
		if nextTier < previous then
			state.validSinceDowngrade = 0
		end
		table.insert(state.transitions, {
			at = at,
			from = NAMES[previous],
			to = NAMES[nextTier],
			reason = reason,
			p90Ms = state.p90Ms,
			cpuMs = state.cpuMs,
			gpuMs = state.gpuMs,
			pacingClass = state.pacingClass,
		})
		if #state.transitions > MAX_TRANSITIONS then
			table.remove(state.transitions, 1)
		end
		state.degradeEvaluations, state.severeEvaluations, state.recoverySeconds = 0, 0, 0
	end
	local function eligible(at: number): boolean
		return state.ready
			and state.focused == true
			and state.readyAt ~= nil
			and at >= state.readyAt + 10
			and at >= state.settleUntil
	end
	local function prune(at: number)
		while state.count > 0 do
			local sample = state.samples[state.head]
			if sample.at > at - WINDOW_SECONDS then
				break
			end
			state.samples[state.head] = nil
			state.head = state.head % MAX_SAMPLES + 1
			state.count -= 1
		end
	end
	function api.RecordFrame(at: number, deltaSeconds: number): boolean
		if not finite(at) or not positive(deltaSeconds) or deltaSeconds > 10 then
			state.invalidSamples += 1
			clearWindow()
			state.status = "FRAME_WINDOW_UNAVAILABLE"
			return false
		end
		if not eligible(at) then
			return false
		end
		if state.lastRecordedAt and at <= state.lastRecordedAt then
			return false
		end
		-- Bounded sampling at <=240 Hz; each retained value is actual frame pacing.
		if state.lastRecordedAt and at - state.lastRecordedAt < 1 / 240 then
			return false
		end
		if state.lastRecordedAt and at - state.lastRecordedAt > math.max(0.25, deltaSeconds * 1.5) then
			clearWindow() -- Missing callbacks never manufacture valid recovery seconds.
		end
		prune(at)
		if state.count == MAX_SAMPLES then
			state.samples[state.head] = nil
			state.head = state.head % MAX_SAMPLES + 1
			state.count -= 1
		end
		local index = (state.head + state.count - 1) % MAX_SAMPLES + 1
		state.samples[index] = { at = at, seconds = deltaSeconds, ms = deltaSeconds * 1000 }
		state.count += 1
		state.lastRecordedAt = at
		return true
	end
	function api.Step(at: number, input: any): string
		if not finite(at) or type(input) ~= "table" then
			return effective()
		end
		if state.lastStepAt and at < state.lastStepAt then
			clearWindow()
			state.readyAt = if state.ready then at else nil
			state.settleUntil = at + 3
			state.lastEvaluationAt = nil
		end
		state.lastStepAt = at
		local nextReady = input.ready == true
		if nextReady ~= state.ready then
			state.ready = nextReady
			state.readyAt = if nextReady then at else nil
			clearWindow()
		end
		local nextFocus = if input.focused == true then true elseif input.focused == false then false else nil
		if nextFocus ~= state.focused then
			state.focused = nextFocus
			state.settleUntil = at + 3
			clearWindow()
		end
		local nextMode, nextGraphics = mode(input.mode), graphics(input.savedQuality)
		if nextMode ~= state.selectedMode or nextGraphics ~= state.savedQuality then
			state.selectedMode, state.savedQuality = nextMode, nextGraphics
			state.settleUntil = at + 3
			clearWindow()
		end
		state.graphicsCeiling = if nextGraphics and nextGraphics <= 3 then "Low" else "High"
		if nextMode == "Auto" and state.graphicsCeiling == "Low" then
			transition(1, at, "EXPLICIT_LOW_GRAPHICS_CEILING")
		end
		if not state.ready then
			state.status = "LOADING"
			return effective()
		end
		if state.focused ~= true then
			state.status = if state.focused == false then "UNFOCUSED" else "FOCUS_UNAVAILABLE"
			return effective()
		end
		if not eligible(at) then
			state.status = "WARMUP_OR_SETTLE"
			return effective()
		end
		if nextMode ~= "Auto" then
			state.status = "MANUAL"
			return effective()
		end
		if state.lastEvaluationAt and at - state.lastEvaluationAt < 1 then
			return effective()
		end
		state.lastEvaluationAt = at
		state.evaluations += 1
		prune(at)
		local oldest = state.samples[state.head]
		if
			state.count < 5
			or not oldest
			or not state.lastRecordedAt
			or at - state.lastRecordedAt > 0.25
			or oldest.at - oldest.seconds > at - 4.95
		then
			state.status = "FRAME_WINDOW_UNAVAILABLE"
			state.degradeEvaluations, state.severeEvaluations, state.recoverySeconds = 0, 0, 0
			state.p90Ms, state.pacingClass = nil, "Unavailable"
			state.lastValidEvaluationAt = nil
			return effective()
		end
		local durations = table.create(state.count)
		for offset = 0, state.count - 1 do
			table.insert(durations, state.samples[(state.head + offset - 1) % MAX_SAMPLES + 1].ms)
		end
		state.p90Ms = percentile(durations, 0.9)
		state.cpuMs, state.gpuMs, state.memoryMb =
			positive(input.cpuMs), positive(input.gpuMs), positive(input.memoryMb)
		state.measurementsAt = at
		if state.memoryMb then
			state.memoryStartMb = state.memoryStartMb or state.memoryMb
			state.memoryDeltaMb = state.memoryMb - state.memoryStartMb
		else
			state.memoryDeltaMb = nil
		end
		local p90 = state.p90Ms
		for index = #state.busySamples, 1, -1 do
			if state.busySamples[index].at <= at - WINDOW_SECONDS then
				table.remove(state.busySamples, index)
			end
		end
		local busyAvailable = state.cpuMs ~= nil and state.gpuMs ~= nil
		table.insert(
			state.busySamples,
			{ at = at, ms = if busyAvailable then math.max(state.cpuMs, state.gpuMs) else nil }
		)
		local busyDurations = {}
		local allRecentBusyAvailable = busyAvailable and #state.busySamples >= 3
		for _, sample in state.busySamples do
			if sample.ms then
				table.insert(busyDurations, sample.ms)
			else
				allRecentBusyAvailable = false
			end
		end
		state.busyP90Ms = percentile(busyDurations, 0.9)
		local cap30 = math.abs(p90 - 1000 / 30) <= 1.5
		local cap60 = math.abs(p90 - 1000 / 60) <= 0.8
		local waitLikely = allRecentBusyAvailable and state.busyP90Ms <= p90 * 0.6 and (cap30 or cap60)
		state.pacingClass = if waitLikely
			then "CapOrWaitLikely"
			elseif busyAvailable then "BusyTimingsObserved"
			else "BusyTimingsUnavailable"
		state.status = "VALID"
		-- A first valid snapshot establishes the clock; it cannot manufacture a
		-- preceding second when the previous observation window was unavailable.
		local validDelta = if state.lastValidEvaluationAt then math.min(1, at - state.lastValidEvaluationAt) else 0
		state.lastValidEvaluationAt = at
		state.validEvaluationSeconds += validDelta
		state.validSinceDowngrade = math.min(20, state.validSinceDowngrade + validDelta)
		state.severeEvaluations = if p90 > 66.7 then state.severeEvaluations + 1 else 0
		local threshold = if state.autoTier == 3 then 22.2 else 36.7
		state.degradeEvaluations = if state.autoTier > 1
				and p90 > threshold
				and not waitLikely
			then state.degradeEvaluations + 1
			else 0
		if state.autoTier > 1 and state.severeEvaluations >= 2 then
			transition(1, at, "SUSTAINED_SEVERE_FRAME_PACING")
		elseif state.autoTier > 1 and state.degradeEvaluations >= 3 then
			transition(state.autoTier - 1, at, "SUSTAINED_P90_OVER_TIER_THRESHOLD")
		else
			local recoveryLimit = if state.autoTier == 1 then 30 else 18
			state.recoverySeconds = if state.autoTier < 3 and p90 <= recoveryLimit
				then state.recoverySeconds + validDelta
				else 0
			if
				state.autoTier < 3
				and state.recoverySeconds >= 20
				and state.validSinceDowngrade >= 20
				and state.graphicsCeiling ~= "Low"
			then
				transition(state.autoTier + 1, at, "TWENTY_VALID_SECONDS_STABLE_RECOVERY")
			end
		end
		return effective()
	end
	function api.GetTier(): string
		return effective()
	end
	function api.GetDiagnostics(): any
		local transitions = {}
		for _, item in state.transitions do
			table.insert(transitions, table.clone(item))
		end
		return {
			mode = state.selectedMode,
			effectiveTier = effective(),
			autoTier = NAMES[state.autoTier],
			graphicsCeiling = state.graphicsCeiling,
			savedQuality = state.savedQuality,
			status = state.status,
			p90Ms = state.p90Ms,
			pacingClass = state.pacingClass,
			cpuMs = state.cpuMs,
			gpuMs = state.gpuMs,
			memoryMb = state.memoryMb,
			memoryDeltaMb = state.memoryDeltaMb,
			busyP90Ms = state.busyP90Ms,
			busySampleCount = #state.busySamples,
			measurementsAt = state.measurementsAt,
			sampleCount = state.count,
			maxSamples = MAX_SAMPLES,
			invalidSamples = state.invalidSamples,
			evaluations = state.evaluations,
			validEvaluationSeconds = state.validEvaluationSeconds,
			recoverySeconds = state.recoverySeconds,
			validSinceDowngrade = state.validSinceDowngrade,
			degradeEvaluations = state.degradeEvaluations,
			severeEvaluations = state.severeEvaluations,
			transitions = transitions,
			maxTransitions = MAX_TRANSITIONS,
		}
	end
	return api
end

return table.freeze(Policy)
