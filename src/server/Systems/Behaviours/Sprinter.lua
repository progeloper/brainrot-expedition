--!strict

local ReactiveRunner = require(script.Parent.ReactiveRunner)

export type ThreatCandidate = ReactiveRunner.ThreatCandidate

export type Config = {
	AwarenessRadius: number,
	DisengageRadius: number,
	DisengageGraceSeconds: number,
	SenseIntervalSeconds: number,
	BurstDurationSeconds: number,
	AccelerationSeconds: number,
	BurstSpeedMultiplier: number,
	RecoveryDurationSeconds: number,
	RecoveryDecelerationSeconds: number,
	RecoverySpeedMultiplier: number,
	RecoveryMaxSpeedStudsPerSecond: number,
	CooldownDurationSeconds: number,
	ReturnToNormalSeconds: number,
	NormalEscapeReplanSeconds: number,
	MinimumBurstClearanceStuds: number,
	BlockedRetrySeconds: number,
}

export type Phase = "Ready" | "Burst" | "Recovery" | "Cooldown"

export type MotionProfile = {
	BaseSpeed: number,
	PeakSpeed: number,
	RecoverySpeed: number,
	AccelerationSeconds: number,
	RecoveryDecelerationSeconds: number,
}

export type State = {
	Phase: Phase,
	lockedThreatUserId: number?,
	lockedThreatCharacter: any?,
	lockedThreatPosition: Vector3?,
	lostThreatSince: number?,
	lostThreatReason: string?,
	escapeGoal: Vector3?,
	committedDirection: Vector3?,
	nextReplanAt: number,
	nextBlockedRetryAt: number,
	burstStartedAt: number?,
	burstEndsAt: number?,
	recoveryEndsAt: number?,
	nextBurstAt: number,
	cycleBaseSpeed: number?,
	recoveryEntrySpeed: number?,
}

export type Decision = {
	Kind: "Roam" | "Escape" | "Hold" | "Stop",
	Phase: Phase,
	Goal: Vector3?,
	RequestedSpeed: number?,
	AcquiredUserId: number?,
	ReleaseReason: string?,
	BurstStarted: boolean?,
	RecoveryStarted: boolean?,
	RecoveryReason: string?,
	CooldownStarted: boolean?,
	RouteBlocked: boolean?,
}

export type Context = {
	LifecycleEligible: boolean,
	Position: Vector3,
	Forward: Vector3,
	ResolvedSpeed: number,
	Candidates: { ThreatCandidate },
	Sensing: boolean,
	CanSeeCandidate: (ThreatCandidate) -> boolean,
	ResolveEscapeGoal: (
		position: Vector3,
		threatPosition: Vector3,
		preferredDirection: Vector3,
		desiredDistance: number,
		minimumDistance: number
	) -> Vector3?,
}

local Sprinter = {}
local GOAL_REACHED_DISTANCE = 2

local function finiteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function lerp(startValue: number, endValue: number, alpha: number): number
	return startValue + (endValue - startValue) * math.clamp(alpha, 0, 1)
end

function Sprinter.BuildMotionProfile(baseSpeed: number, config: Config): MotionProfile?
	if not finiteNumber(baseSpeed) or baseSpeed <= 0 then
		return nil
	end
	return table.freeze({
		BaseSpeed = baseSpeed,
		PeakSpeed = baseSpeed * config.BurstSpeedMultiplier,
		RecoverySpeed = math.min(
			baseSpeed * config.RecoverySpeedMultiplier,
			config.RecoveryMaxSpeedStudsPerSecond
		),
		AccelerationSeconds = config.AccelerationSeconds,
		RecoveryDecelerationSeconds = config.RecoveryDecelerationSeconds,
	})
end

function Sprinter.SampleTransitionSpeed(
	startSpeed: number,
	endSpeed: number,
	elapsed: number,
	duration: number
): number
	if duration <= 0 then
		return endSpeed
	end
	return lerp(startSpeed, endSpeed, elapsed / duration)
end

function Sprinter.SampleBurstProfile(profile: MotionProfile, elapsed: number): number
	if elapsed < profile.AccelerationSeconds then
		return Sprinter.SampleTransitionSpeed(
			profile.BaseSpeed,
			profile.PeakSpeed,
			math.max(0, elapsed),
			profile.AccelerationSeconds
		)
	end
	return profile.PeakSpeed
end

local function decision(kind: "Roam" | "Escape" | "Hold" | "Stop", phase: Phase): Decision
	return { Kind = kind, Phase = phase }
end

local function clearThreat(state: State)
	state.lockedThreatUserId = nil
	state.lockedThreatCharacter = nil
	state.lockedThreatPosition = nil
	state.lostThreatSince = nil
	state.lostThreatReason = nil
end

local function findLockedCandidate(state: State, candidates: { ThreatCandidate }): ThreatCandidate?
	for _, candidate in candidates do
		if
			candidate.UserId == state.lockedThreatUserId
			and candidate.Character == state.lockedThreatCharacter
		then
			return candidate
		end
	end
	return nil
end

function Sprinter.CreateState(now: number, preservedNextBurstAt: number?): State
	local nextBurstAt = if preservedNextBurstAt ~= nil and preservedNextBurstAt > now
		then preservedNextBurstAt
		else now
	return {
		Phase = if nextBurstAt > now then "Cooldown" else "Ready",
		lockedThreatUserId = nil,
		lockedThreatCharacter = nil,
		lockedThreatPosition = nil,
		lostThreatSince = nil,
		lostThreatReason = nil,
		escapeGoal = nil,
		committedDirection = nil,
		nextReplanAt = 0,
		nextBlockedRetryAt = 0,
		burstStartedAt = nil,
		burstEndsAt = nil,
		recoveryEndsAt = nil,
		nextBurstAt = nextBurstAt,
		cycleBaseSpeed = nil,
		recoveryEntrySpeed = nil,
	}
end

function Sprinter.SampleMotion(state: State, now: number, config: Config): (Phase, number)
	local baseSpeed = state.cycleBaseSpeed or 0
	local burstStartedAt = state.burstStartedAt
	local burstEndsAt = state.burstEndsAt
	local recoveryEndsAt = state.recoveryEndsAt
	if burstStartedAt == nil or burstEndsAt == nil or recoveryEndsAt == nil then
		return if now < state.nextBurstAt then "Cooldown" else "Ready", baseSpeed
	end

	local profile = Sprinter.BuildMotionProfile(baseSpeed, config)
	if profile == nil then
		return if now < state.nextBurstAt then "Cooldown" else "Ready", 0
	end
	local peakSpeed = profile.PeakSpeed
	local recoverySpeed = profile.RecoverySpeed
	if now < burstEndsAt then
		local elapsed = math.max(0, now - burstStartedAt)
		return "Burst", Sprinter.SampleBurstProfile(profile, elapsed)
	elseif now < recoveryEndsAt then
		local elapsed = math.max(0, now - burstEndsAt)
		local entrySpeed = state.recoveryEntrySpeed or peakSpeed
		return "Recovery",
			if elapsed < config.RecoveryDecelerationSeconds
				then Sprinter.SampleTransitionSpeed(
					entrySpeed,
					recoverySpeed,
					elapsed,
					config.RecoveryDecelerationSeconds
				)
				else recoverySpeed
	elseif now < state.nextBurstAt then
		local elapsed = math.max(0, now - recoveryEndsAt)
		return "Cooldown",
			if elapsed < config.ReturnToNormalSeconds
				then Sprinter.SampleTransitionSpeed(
					recoverySpeed,
					baseSpeed,
					elapsed,
					config.ReturnToNormalSeconds
				)
				else baseSpeed
	end
	return "Ready", baseSpeed
end

-- Integrates the timestamp-driven curve without replaying missed phase callbacks.
-- The movement owner supplies a bounded interval and uses the resulting average
-- for its one authoritative transform update.
function Sprinter.AverageSpeed(state: State, startAt: number, endAt: number, config: Config): number
	if endAt <= startAt then
		return select(2, Sprinter.SampleMotion(state, endAt, config))
	end
	local boundaries = {
		state.burstStartedAt,
		if state.burstStartedAt then state.burstStartedAt + config.AccelerationSeconds else nil,
		state.burstEndsAt,
		if state.burstEndsAt then state.burstEndsAt + config.RecoveryDecelerationSeconds else nil,
		state.recoveryEndsAt,
		if state.recoveryEndsAt then state.recoveryEndsAt + config.ReturnToNormalSeconds else nil,
		state.nextBurstAt,
	}
	local points = { startAt, endAt }
	for _, boundary in boundaries do
		if boundary ~= nil and boundary > startAt and boundary < endAt then
			table.insert(points, boundary)
		end
	end
	table.sort(points)
	local distance = 0
	for index = 1, #points - 1 do
		local left, right = points[index], points[index + 1]
		local leftSpeed = select(2, Sprinter.SampleMotion(state, left, config))
		local rightSpeed = select(2, Sprinter.SampleMotion(state, right, config))
		distance += (leftSpeed + rightSpeed) * 0.5 * (right - left)
	end
	return distance / (endAt - startAt)
end

function Sprinter.TryStartBurst(
	state: State,
	context: Context,
	now: number,
	config: Config
): boolean
	if
		state.Phase ~= "Ready"
		or now < state.nextBurstAt
		or now < state.nextBlockedRetryAt
		or not context.LifecycleEligible
		or not context.Sensing
		or not finiteNumber(context.ResolvedSpeed)
		or context.ResolvedSpeed <= 0
	then
		return false
	end
	local threat = findLockedCandidate(state, context.Candidates)
	if
		threat == nil
		or (threat.Position - context.Position).Magnitude > config.AwarenessRadius
		or not context.CanSeeCandidate(threat)
	then
		return false
	end
	local preferredDirection =
		ReactiveRunner.ComputeEscapeDirection(context.Position, threat.Position, context.Forward)
	local peakSpeed = context.ResolvedSpeed * config.BurstSpeedMultiplier
	local desiredDistance =
		math.max(config.MinimumBurstClearanceStuds, peakSpeed * config.BurstDurationSeconds)
	local goal = context.ResolveEscapeGoal(
		context.Position,
		threat.Position,
		preferredDirection,
		desiredDistance,
		config.MinimumBurstClearanceStuds
	)
	if goal == nil then
		state.nextBlockedRetryAt = now + config.BlockedRetrySeconds
		return false
	end

	state.Phase = "Burst"
	state.burstStartedAt = now
	state.burstEndsAt = now + config.BurstDurationSeconds
	state.recoveryEndsAt = state.burstEndsAt + config.RecoveryDurationSeconds
	state.nextBurstAt = state.recoveryEndsAt + config.CooldownDurationSeconds
	state.cycleBaseSpeed = context.ResolvedSpeed
	state.recoveryEntrySpeed = peakSpeed
	state.committedDirection = preferredDirection
	state.escapeGoal = goal
	state.nextReplanAt = state.recoveryEndsAt
	state.nextBlockedRetryAt = now
	return true
end

function Sprinter.EnterRecovery(
	state: State,
	transitionTime: number,
	entrySpeed: number,
	_reason: string,
	config: Config
): boolean
	if state.Phase ~= "Burst" then
		return false
	end
	local baseSpeed = state.cycleBaseSpeed or 0
	state.Phase = "Recovery"
	state.burstEndsAt = transitionTime
	state.recoveryEndsAt = transitionTime + config.RecoveryDurationSeconds
	state.nextBurstAt = state.recoveryEndsAt + config.CooldownDurationSeconds
	state.recoveryEntrySpeed = if finiteNumber(entrySpeed) and entrySpeed >= 0
		then entrySpeed
		else baseSpeed
	state.escapeGoal = nil
	state.nextBlockedRetryAt = transitionTime + config.BlockedRetrySeconds
	return true
end

function Sprinter.Interrupt(state: State, now: number, _reason: string)
	clearThreat(state)
	state.escapeGoal = nil
	state.committedDirection = nil
	state.nextReplanAt = 0
	state.nextBlockedRetryAt = 0
	state.burstStartedAt = nil
	state.burstEndsAt = nil
	state.recoveryEndsAt = nil
	state.recoveryEntrySpeed = nil
	state.Phase = if now < state.nextBurstAt then "Cooldown" else "Ready"
end

local function updateThreat(
	state: State,
	context: Context,
	now: number,
	allowAcquire: boolean,
	config: Config
): (number?, string?)
	if not context.Sensing then
		return nil, nil
	end
	if state.lockedThreatUserId ~= nil then
		local current = findLockedCandidate(state, context.Candidates)
		if current == nil then
			clearThreat(state)
			return nil, "InvalidThreat"
		end
		state.lockedThreatPosition = current.Position
		local inRange = (current.Position - context.Position).Magnitude <= config.DisengageRadius
		local visible = inRange and context.CanSeeCandidate(current)
		if inRange and visible then
			state.lostThreatSince = nil
			state.lostThreatReason = nil
		else
			local reason = if inRange then "Occluded" else "OutOfRange"
			state.lostThreatSince = state.lostThreatSince or now
			state.lostThreatReason = reason
			if now - (state.lostThreatSince :: number) >= config.DisengageGraceSeconds then
				clearThreat(state)
				return nil, reason
			end
		end
		return nil, nil
	end
	if not allowAcquire then
		return nil, nil
	end
	local selected = ReactiveRunner.SelectThreat(
		context.Position,
		context.Candidates,
		context.CanSeeCandidate,
		{ AwarenessRadius = config.AwarenessRadius }
	)
	if selected == nil then
		return nil, nil
	end
	state.lockedThreatUserId = selected.UserId
	state.lockedThreatCharacter = selected.Character
	state.lockedThreatPosition = selected.Position
	state.lostThreatSince = nil
	state.lostThreatReason = nil
	return selected.UserId, nil
end

local function ensureCommittedGoal(
	state: State,
	context: Context,
	now: number,
	config: Config
): (Vector3?, boolean)
	local goal = state.escapeGoal
	if goal ~= nil and (goal - context.Position).Magnitude > GOAL_REACHED_DISTANCE then
		return goal, false
	end
	if now < state.nextBlockedRetryAt then
		return nil, false
	end
	local direction = state.committedDirection
	local threatPosition = state.lockedThreatPosition or context.Position - context.Forward
	if direction == nil then
		direction =
			ReactiveRunner.ComputeEscapeDirection(context.Position, threatPosition, context.Forward)
	end
	local baseSpeed = state.cycleBaseSpeed or context.ResolvedSpeed
	local desiredDistance = math.max(
		config.MinimumBurstClearanceStuds,
		baseSpeed * config.BurstSpeedMultiplier * config.BurstDurationSeconds
	)
	goal = context.ResolveEscapeGoal(
		context.Position,
		threatPosition,
		direction,
		desiredDistance,
		config.MinimumBurstClearanceStuds
	)
	if goal == nil then
		state.escapeGoal = nil
		state.nextBlockedRetryAt = now + config.BlockedRetrySeconds
		return nil, true
	end
	state.escapeGoal = goal
	return goal, false
end

local function ensureNormalEscapeGoal(
	state: State,
	context: Context,
	now: number,
	config: Config
): (Vector3?, boolean)
	local goal = state.escapeGoal
	if
		goal ~= nil
		and (goal - context.Position).Magnitude > GOAL_REACHED_DISTANCE
		and now < state.nextReplanAt
	then
		return goal, false
	end
	if now < state.nextBlockedRetryAt then
		return nil, false
	end
	local threatPosition = state.lockedThreatPosition
	if threatPosition == nil then
		state.escapeGoal = nil
		return nil, false
	end
	local direction =
		ReactiveRunner.ComputeEscapeDirection(context.Position, threatPosition, context.Forward)
	local desiredDistance = math.max(config.MinimumBurstClearanceStuds, context.ResolvedSpeed)
	goal = context.ResolveEscapeGoal(
		context.Position,
		threatPosition,
		direction,
		desiredDistance,
		config.MinimumBurstClearanceStuds
	)
	if goal == nil then
		state.escapeGoal = nil
		state.nextBlockedRetryAt = now + config.BlockedRetrySeconds
		return nil, true
	end
	state.escapeGoal = goal
	state.nextReplanAt = now + config.NormalEscapeReplanSeconds
	state.nextBlockedRetryAt = now
	return goal, false
end

function Sprinter.Step(state: State, context: Context, now: number, config: Config): Decision
	if not context.LifecycleEligible then
		Sprinter.Interrupt(state, now, "Lifecycle")
		return decision("Stop", state.Phase)
	end
	if state.cycleBaseSpeed == nil then
		state.cycleBaseSpeed = context.ResolvedSpeed
	end

	local sampledPhase, sampledSpeed = Sprinter.SampleMotion(state, now, config)
	local previousPhase = state.Phase
	state.Phase = sampledPhase
	local result = decision("Roam", sampledPhase)
	result.RequestedSpeed = if sampledSpeed > 0 then sampledSpeed else context.ResolvedSpeed
	if sampledPhase == "Recovery" and previousPhase == "Burst" then
		result.RecoveryStarted = true
		result.RecoveryReason = "CompletedBurst"
	elseif sampledPhase == "Cooldown" and previousPhase == "Recovery" then
		result.CooldownStarted = true
	end

	local committed = sampledPhase == "Burst" or sampledPhase == "Recovery"
	local acquiredUserId, releaseReason = updateThreat(state, context, now, not committed, config)
	result.AcquiredUserId = acquiredUserId
	result.ReleaseReason = releaseReason

	if
		sampledPhase == "Ready"
		and releaseReason == nil
		and Sprinter.TryStartBurst(state, context, now, config)
	then
		result.Phase = "Burst"
		result.BurstStarted = true
		result.Kind = "Escape"
		result.Goal = state.escapeGoal
		result.RequestedSpeed = select(2, Sprinter.SampleMotion(state, now, config))
		return result
	end

	if committed then
		local goal, blocked = ensureCommittedGoal(state, context, now, config)
		if blocked and sampledPhase == "Burst" then
			local entered =
				Sprinter.EnterRecovery(state, now, result.RequestedSpeed or 0, "Blocked", config)
			if entered then
				result.Phase = "Recovery"
				result.RecoveryStarted = true
				result.RecoveryReason = "Blocked"
			end
		end
		result.RouteBlocked = blocked
		if goal ~= nil then
			result.Kind = "Escape"
			result.Goal = goal
		else
			result.Kind = "Hold"
		end
		return result
	end

	if state.lockedThreatUserId ~= nil then
		local goal, blocked = ensureNormalEscapeGoal(state, context, now, config)
		result.RouteBlocked = blocked
		if goal ~= nil then
			result.Kind = "Escape"
			result.Goal = goal
		elseif now < state.nextBlockedRetryAt then
			result.Kind = "Hold"
		end
	else
		state.escapeGoal = nil
		state.committedDirection = nil
		result.Kind = "Roam"
	end
	return result
end

return table.freeze(Sprinter)
