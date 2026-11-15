--!strict

local ReactiveRunner = require(script.Parent.ReactiveRunner)

export type ThreatCandidate = ReactiveRunner.ThreatCandidate

export type Config = {
	AwarenessRadius: number,
	DisengageRadius: number,
	DisengageGraceSeconds: number,
	SenseIntervalSeconds: number,
	SweepDurationSeconds: number,
	StraightDurationSeconds: number,
	SweepTurnSeconds: number,
	MaxSweepAngleDegrees: number,
	MaxLateralOffsetStuds: number,
	InitialSide: number,
	CourseRefreshThresholdDegrees: number,
	MaxCourseChangeDegrees: number,
	CourseReorientSeconds: number,
	BlockedRetrySeconds: number,
}

export type PatternPhase = "SweepA" | "StraightA" | "SweepB" | "StraightB"
export type Mode = "Inactive" | "Reorienting" | "Pattern" | "Blocked"

export type CyclePlan = {
	BaseSpeed: number,
	EffectiveAngleRadians: number,
	InitialSide: number,
	SweepDurationSeconds: number,
	StraightDurationSeconds: number,
	SweepTurnSeconds: number,
	CycleDurationSeconds: number,
}

export type State = {
	Mode: Mode,
	lockedThreatUserId: number?,
	lockedThreatCharacter: any?,
	lockedThreatPosition: Vector3?,
	lostThreatSince: number?,
	lostThreatReason: string?,
	courseForward: Vector3?,
	courseRight: Vector3?,
	courseReferencePosition: Vector3?,
	cycleStartAt: number?,
	cycleIndex: number,
	cyclePlan: CyclePlan?,
	initialSide: number,
	reorientFrom: Vector3?,
	reorientTo: Vector3?,
	reorientStartedAt: number?,
	reorientEndsAt: number?,
	nextBlockedRetryAt: number,
}

export type Decision = {
	Kind: "Roam" | "Escape" | "Hold" | "Stop",
	Direction: Vector3?,
	RequestedSpeed: number?,
	Phase: PatternPhase?,
	StraightWindow: boolean?,
	AcquiredUserId: number?,
	ReleaseReason: string?,
	Engaged: boolean?,
	CourseChanged: boolean?,
	CourseChangeReason: string?,
	RouteBlocked: boolean?,
}

export type Context = {
	Authorized: boolean,
	LifecycleEligible: boolean,
	Position: Vector3,
	Forward: Vector3,
	ResolvedSpeed: number,
	Candidates: { ThreatCandidate },
	Sensing: boolean,
	CanSeeCandidate: (ThreatCandidate) -> boolean,
	ResolveSafeCourse: (
		position: Vector3,
		threatPosition: Vector3,
		preferredDirection: Vector3,
		desiredDistance: number
	) -> Vector3?,
	IsCourseSafe: (position: Vector3, direction: Vector3, desiredDistance: number) -> boolean,
}

local Zigzag = {}
local DIRECTION_EPSILON = 1e-5

local function finiteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function finiteVector(value: Vector3): boolean
	return finiteNumber(value.X) and finiteNumber(value.Y) and finiteNumber(value.Z)
end

local function horizontalUnit(value: Vector3): Vector3?
	local horizontal = Vector3.new(value.X, 0, value.Z)
	return if finiteVector(horizontal) and horizontal.Magnitude > DIRECTION_EPSILON
		then horizontal.Unit
		else nil
end

local function smoothstep01(value: number): number
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end

local function decision(kind: "Roam" | "Escape" | "Hold" | "Stop"): Decision
	return { Kind = kind }
end

local function clearThreat(state: State)
	state.lockedThreatUserId = nil
	state.lockedThreatCharacter = nil
	state.lockedThreatPosition = nil
	state.lostThreatSince = nil
	state.lostThreatReason = nil
end

local function clearCourse(state: State)
	state.courseForward = nil
	state.courseRight = nil
	state.courseReferencePosition = nil
	state.cycleStartAt = nil
	state.cycleIndex = 0
	state.cyclePlan = nil
	state.reorientFrom = nil
	state.reorientTo = nil
	state.reorientStartedAt = nil
	state.reorientEndsAt = nil
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

local function signedHorizontalAngle(from: Vector3, to: Vector3): number
	local dot = math.clamp(from:Dot(to), -1, 1)
	local magnitude = math.acos(dot)
	local crossY = from:Cross(to).Y
	return if crossY < 0 then magnitude else -magnitude
end

local function rotateHorizontal(forward: Vector3, angle: number): Vector3
	local right = forward:Cross(Vector3.yAxis)
	local direction = forward * math.cos(angle) + right * math.sin(angle)
	return horizontalUnit(direction) or forward
end

local function startReorientation(
	state: State,
	fromDirection: Vector3,
	toDirection: Vector3,
	position: Vector3,
	now: number,
	config: Config
)
	local from = horizontalUnit(fromDirection) or toDirection
	local to = horizontalUnit(toDirection) or from
	state.Mode = "Reorienting"
	state.courseForward = to
	state.courseRight = to:Cross(Vector3.yAxis).Unit
	state.courseReferencePosition = position
	state.reorientFrom = from
	state.reorientTo = to
	state.reorientStartedAt = now
	state.reorientEndsAt = now + config.CourseReorientSeconds
	state.cycleStartAt = nil
	state.cycleIndex = 0
end

function Zigzag.CreateState(_now: number): State
	return {
		Mode = "Inactive",
		lockedThreatUserId = nil,
		lockedThreatCharacter = nil,
		lockedThreatPosition = nil,
		lostThreatSince = nil,
		lostThreatReason = nil,
		courseForward = nil,
		courseRight = nil,
		courseReferencePosition = nil,
		cycleStartAt = nil,
		cycleIndex = 0,
		cyclePlan = nil,
		initialSide = 1,
		reorientFrom = nil,
		reorientTo = nil,
		reorientStartedAt = nil,
		reorientEndsAt = nil,
		nextBlockedRetryAt = 0,
	}
end

function Zigzag.ComputeCourse(
	position: Vector3,
	threatPosition: Vector3,
	fallbackForward: Vector3
): (Vector3, Vector3)
	local forward = ReactiveRunner.ComputeEscapeDirection(position, threatPosition, fallbackForward)
	local right = forward:Cross(Vector3.yAxis)
	if not finiteVector(right) or right.Magnitude <= DIRECTION_EPSILON then
		forward = Vector3.xAxis
		right = forward:Cross(Vector3.yAxis)
	end
	return forward.Unit, right.Unit
end

function Zigzag.BuildCyclePlan(baseSpeed: number, initialSide: number, config: Config): CyclePlan?
	if
		not finiteNumber(baseSpeed)
		or baseSpeed <= 0
		or (initialSide ~= 1 and initialSide ~= -1)
		or not finiteNumber(config.SweepDurationSeconds)
		or config.SweepDurationSeconds <= 0
	then
		return nil
	end
	local ratio =
		math.clamp(config.MaxLateralOffsetStuds / (baseSpeed * config.SweepDurationSeconds), 0, 1)
	local effectiveAngle = math.min(math.rad(config.MaxSweepAngleDegrees), math.asin(ratio))
	return table.freeze({
		BaseSpeed = baseSpeed,
		EffectiveAngleRadians = effectiveAngle,
		InitialSide = initialSide,
		SweepDurationSeconds = config.SweepDurationSeconds,
		StraightDurationSeconds = config.StraightDurationSeconds,
		SweepTurnSeconds = config.SweepTurnSeconds,
		CycleDurationSeconds = 2 * (config.SweepDurationSeconds + config.StraightDurationSeconds),
	})
end

local function sweepStrength(timeInSweep: number, plan: CyclePlan): number
	local duration, turn = plan.SweepDurationSeconds, plan.SweepTurnSeconds
	if timeInSweep < turn then
		return smoothstep01(timeInSweep / turn)
	elseif timeInSweep < duration - turn then
		return 1
	end
	return smoothstep01((duration - timeInSweep) / turn)
end

function Zigzag.SamplePattern(elapsed: number, plan: CyclePlan): (PatternPhase, number, boolean)
	local cycleTime = math.max(0, elapsed) % plan.CycleDurationSeconds
	local sweep, straight = plan.SweepDurationSeconds, plan.StraightDurationSeconds
	if cycleTime < sweep then
		return "SweepA",
			plan.InitialSide * plan.EffectiveAngleRadians * sweepStrength(cycleTime, plan),
			false
	elseif cycleTime < sweep + straight then
		return "StraightA", 0, true
	elseif cycleTime < 2 * sweep + straight then
		local timeInSweep = cycleTime - sweep - straight
		return "SweepB",
			-plan.InitialSide * plan.EffectiveAngleRadians * sweepStrength(timeInSweep, plan),
			false
	end
	return "StraightB", 0, true
end

function Zigzag.DirectionForYaw(forward: Vector3, right: Vector3, yaw: number): Vector3
	local direction = forward * math.cos(yaw) + right * math.sin(yaw)
	return horizontalUnit(direction) or forward
end

function Zigzag.BlendCourseDirection(
	fromDirection: Vector3,
	toDirection: Vector3,
	alpha: number
): Vector3
	local from = horizontalUnit(fromDirection) or horizontalUnit(toDirection) or Vector3.xAxis
	local to = horizontalUnit(toDirection) or from
	return rotateHorizontal(from, signedHorizontalAngle(from, to) * smoothstep01(alpha))
end

function Zigzag.SampleDirection(state: State, now: number): (Vector3?, PatternPhase?, boolean?)
	if state.Mode == "Reorienting" then
		local from = state.reorientFrom
		local to = state.reorientTo
		local startedAt = state.reorientStartedAt
		local endsAt = state.reorientEndsAt
		if from == nil or to == nil or startedAt == nil or endsAt == nil then
			return state.courseForward, nil, nil
		end
		local duration = math.max(DIRECTION_EPSILON, endsAt - startedAt)
		return Zigzag.BlendCourseDirection(from, to, (now - startedAt) / duration), nil, nil
	elseif state.Mode == "Pattern" then
		local startedAt, plan = state.cycleStartAt, state.cyclePlan
		local forward, right = state.courseForward, state.courseRight
		if startedAt == nil or plan == nil or forward == nil or right == nil then
			return nil, nil, nil
		end
		local phase, yaw, straight = Zigzag.SamplePattern(now - startedAt, plan)
		return Zigzag.DirectionForYaw(forward, right, yaw), phase, straight
	end
	return nil, nil, nil
end

function Zigzag.NextMovementBoundary(state: State, now: number): number?
	if state.Mode == "Reorienting" then
		return state.reorientEndsAt
	elseif state.Mode ~= "Pattern" or state.cycleStartAt == nil or state.cyclePlan == nil then
		return nil
	end
	local plan = state.cyclePlan
	local elapsed = math.max(0, now - state.cycleStartAt)
	local cycleIndex = math.floor(elapsed / plan.CycleDurationSeconds)
	local cycleStart = state.cycleStartAt + cycleIndex * plan.CycleDurationSeconds
	local boundaries = {
		cycleStart + plan.SweepDurationSeconds,
		cycleStart + plan.SweepDurationSeconds + plan.StraightDurationSeconds,
		cycleStart + 2 * plan.SweepDurationSeconds + plan.StraightDurationSeconds,
		cycleStart + plan.CycleDurationSeconds,
	}
	for _, boundary in boundaries do
		if boundary > now + DIRECTION_EPSILON then
			return boundary
		end
	end
	return cycleStart + plan.CycleDurationSeconds
end

function Zigzag.Interrupt(state: State, _now: number, _reason: string)
	clearThreat(state)
	clearCourse(state)
	state.Mode = "Inactive"
	state.nextBlockedRetryAt = 0
end

function Zigzag.OnMovementBlocked(state: State, now: number, config: Config)
	clearCourse(state)
	state.Mode = "Blocked"
	state.nextBlockedRetryAt = now + config.BlockedRetrySeconds
end

local function updateThreat(
	state: State,
	context: Context,
	now: number,
	config: Config
): (number?, string?)
	if not context.Sensing then
		return nil, nil
	end
	if state.lockedThreatUserId ~= nil then
		local current = findLockedCandidate(state, context.Candidates)
		if current == nil then
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
				return nil, reason
			end
		end
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

local function beginCourse(
	state: State,
	context: Context,
	now: number,
	preferredDirection: Vector3,
	desiredDistance: number,
	config: Config
): boolean
	local threatPosition = state.lockedThreatPosition
	if threatPosition == nil then
		return false
	end
	local safeDirection = context.ResolveSafeCourse(
		context.Position,
		threatPosition,
		preferredDirection,
		desiredDistance
	)
	if safeDirection == nil then
		Zigzag.OnMovementBlocked(state, now, config)
		return false
	end
	local plan = Zigzag.BuildCyclePlan(context.ResolvedSpeed, state.initialSide, config)
	if plan == nil then
		return false
	end
	state.cyclePlan = plan
	startReorientation(state, context.Forward, safeDirection, context.Position, now, config)
	return true
end

function Zigzag.TryEngage(state: State, context: Context, now: number, config: Config): boolean
	if
		not context.Authorized
		or not context.LifecycleEligible
		or state.lockedThreatUserId == nil
		or state.lockedThreatPosition == nil
		or not finiteNumber(context.ResolvedSpeed)
		or context.ResolvedSpeed <= 0
	then
		return false
	end
	local forward = select(
		1,
		Zigzag.ComputeCourse(context.Position, state.lockedThreatPosition, context.Forward)
	)
	local desiredDistance = context.ResolvedSpeed
		* (config.SweepDurationSeconds + config.StraightDurationSeconds)
	return beginCourse(state, context, now, forward, desiredDistance, config)
end

local function finishReorientation(state: State, context: Context, now: number)
	local course = state.reorientTo or state.courseForward
	if course == nil then
		state.Mode = "Inactive"
		return
	end
	state.courseForward = course
	state.courseRight = course:Cross(Vector3.yAxis).Unit
	state.courseReferencePosition = context.Position
	state.reorientFrom = nil
	state.reorientTo = nil
	state.reorientStartedAt = nil
	state.reorientEndsAt = nil
	state.cycleStartAt = now
	state.cycleIndex = 0
	state.Mode = "Pattern"
end

local function capCourseChange(current: Vector3, desired: Vector3, maxDegrees: number): Vector3
	local signed = signedHorizontalAngle(current, desired)
	local limited = math.clamp(signed, -math.rad(maxDegrees), math.rad(maxDegrees))
	return rotateHorizontal(current, limited)
end

local function maybeRefreshCourse(
	state: State,
	context: Context,
	now: number,
	config: Config
): (boolean, boolean)
	local startedAt, plan = state.cycleStartAt, state.cyclePlan
	local current = state.courseForward
	local threat = state.lockedThreatPosition
	if startedAt == nil or plan == nil or current == nil or threat == nil then
		return false, false
	end
	local completedCycles = math.floor(math.max(0, now - startedAt) / plan.CycleDurationSeconds)
	if completedCycles <= state.cycleIndex then
		return false, false
	end
	state.cycleIndex = completedCycles
	state.courseReferencePosition = context.Position
	local desired = select(1, Zigzag.ComputeCourse(context.Position, threat, current))
	local difference = math.deg(math.abs(signedHorizontalAngle(current, desired)))
	if difference < config.CourseRefreshThresholdDegrees then
		return false, false
	end
	local proposed = capCourseChange(current, desired, config.MaxCourseChangeDegrees)
	local distance = context.ResolvedSpeed
		* (config.SweepDurationSeconds + config.StraightDurationSeconds)
	if not context.IsCourseSafe(context.Position, proposed, distance) then
		Zigzag.OnMovementBlocked(state, now, config)
		return false, true
	end
	startReorientation(state, current, proposed, context.Position, now, config)
	return true, false
end

function Zigzag.Step(
	state: State,
	context: Context,
	now: number,
	dt: number,
	config: Config
): Decision
	if not context.Authorized or not context.LifecycleEligible then
		Zigzag.Interrupt(state, now, "Lifecycle")
		return decision("Stop")
	end

	local acquiredUserId, releaseReason = updateThreat(state, context, now, config)
	if releaseReason ~= nil then
		Zigzag.Interrupt(state, now, releaseReason)
		local result = decision("Roam")
		result.ReleaseReason = releaseReason
		return result
	end
	if state.lockedThreatUserId == nil then
		return decision("Roam")
	end

	if state.Mode == "Inactive" then
		local engaged = Zigzag.TryEngage(state, context, now, config)
		local result = decision(if engaged then "Escape" else "Hold")
		result.AcquiredUserId = acquiredUserId
		result.Engaged = engaged
		result.RouteBlocked = not engaged and state.Mode == "Blocked"
		result.RequestedSpeed = context.ResolvedSpeed
		result.Direction = select(1, Zigzag.SampleDirection(state, now))
		return result
	end

	if state.Mode == "Blocked" then
		if now < state.nextBlockedRetryAt then
			local result = decision("Hold")
			result.AcquiredUserId = acquiredUserId
			return result
		end
		local threat = state.lockedThreatPosition
		if threat == nil then
			Zigzag.Interrupt(state, now, "InvalidThreat")
			return decision("Roam")
		end
		local preferred = select(1, Zigzag.ComputeCourse(context.Position, threat, context.Forward))
		local distance = context.ResolvedSpeed
			* (config.SweepDurationSeconds + config.StraightDurationSeconds)
		local restarted = beginCourse(state, context, now, preferred, distance, config)
		local result = decision(if restarted then "Escape" else "Hold")
		result.CourseChanged = restarted
		result.CourseChangeReason = if restarted then "Obstacle" else nil
		result.RouteBlocked = not restarted
		result.RequestedSpeed = context.ResolvedSpeed
		result.Direction = select(1, Zigzag.SampleDirection(state, now))
		return result
	end

	-- A long movement gap is a discontinuity: preserve the threat and course but
	-- discard historical travel instead of replaying missed sweeps.
	if dt > 0.10 and state.courseForward ~= nil then
		startReorientation(
			state,
			context.Forward,
			state.courseForward,
			context.Position,
			now,
			config
		)
		local result = decision("Escape")
		result.CourseChanged = true
		result.CourseChangeReason = "Stall"
		result.RequestedSpeed = context.ResolvedSpeed
		result.Direction = select(1, Zigzag.SampleDirection(state, now))
		return result
	end

	if
		state.Mode == "Reorienting"
		and state.reorientEndsAt ~= nil
		and now >= state.reorientEndsAt
	then
		finishReorientation(state, context, now)
	end

	local courseChanged, blocked = false, false
	if state.Mode == "Pattern" then
		courseChanged, blocked = maybeRefreshCourse(state, context, now, config)
	end
	if blocked then
		local result = decision("Hold")
		result.RouteBlocked = true
		return result
	end

	local direction, phase, straight = Zigzag.SampleDirection(state, now)
	if direction == nil then
		return decision("Hold")
	end
	local result = decision("Escape")
	result.Direction = direction
	result.RequestedSpeed = context.ResolvedSpeed
	result.Phase = phase
	result.StraightWindow = straight
	result.AcquiredUserId = acquiredUserId
	result.CourseChanged = courseChanged
	result.CourseChangeReason = if courseChanged then "CycleBoundary" else nil
	return result
end

return table.freeze(Zigzag)
