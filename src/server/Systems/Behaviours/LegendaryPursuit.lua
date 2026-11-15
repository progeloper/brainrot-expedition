--!strict

local ReactiveRunner = require(script.Parent.ReactiveRunner)
local Sprinter = require(script.Parent.Sprinter)
local Zigzag = require(script.Parent.Zigzag)

export type ThreatCandidate = ReactiveRunner.ThreatCandidate
export type SprinterConfig = Sprinter.Config
export type ZigzagConfig = Zigzag.Config

export type Config = {
	AwarenessRadius: number,
	DisengageRadius: number,
	DisengageGraceSeconds: number,
	SenseIntervalSeconds: number,
	OpeningDurationSeconds: number,
	ZigzagCycleCount: number,
	RepeatCooldownSeconds: number,
	BlockedRetrySeconds: number,
	MaxActiveEncounters: number,
	MaxUpdateGapSeconds: number,
}

export type Stage =
	"Idle"
	| "Phase1Burst"
	| "Opening1Enter"
	| "Opening1"
	| "Phase2Enter"
	| "Phase2Zigzag"
	| "Opening2Enter"
	| "Opening2"
	| "Cooldown"

export type Plan = {
	BaseSpeed: number,
	OpeningSpeed: number,
	MotionProfile: Sprinter.MotionProfile,
	ZigzagPlan: Zigzag.CyclePlan,
	BurstDuration: number,
	OpeningTransitionDuration: number,
	OpeningDuration: number,
	Phase2EntryDuration: number,
	Phase2Duration: number,
	Phase1BurstStartsAt: number,
	Opening1EnterStartsAt: number,
	Opening1StartsAt: number,
	Phase2EnterStartsAt: number,
	Phase2StartsAt: number,
	Opening2EnterStartsAt: number,
	Opening2StartsAt: number,
	SequenceEndsAt: number,
	EarliestRestartAt: number,
}

export type State = {
	Stage: Stage,
	active: boolean,
	revision: number,
	lockedThreatUserId: number?,
	lockedThreatCharacter: any?,
	lockedThreatPosition: Vector3?,
	lostThreatSince: number?,
	lostThreatReason: string?,
	disengageAfterOpening: boolean,
	plan: Plan?,
	sequenceStartedAt: number?,
	plannedEndAt: number?,
	stageStartedAt: number?,
	stageEndsAt: number?,
	committedDirection: Vector3?,
	phase2Forward: Vector3?,
	phase2Right: Vector3?,
	openingBlocked: boolean,
	nextAllowedAt: number,
	nextBlockedRetryAt: number,
	reservationOwned: boolean,
	runtimeId: string?,
}

export type Context = {
	Authorized: boolean,
	LifecycleEligible: boolean,
	RuntimeId: string,
	Position: Vector3,
	Forward: Vector3,
	ResolvedSpeed: number,
	Candidates: { ThreatCandidate },
	Sensing: boolean,
	CanSeeCandidate: (ThreatCandidate) -> boolean,
	ResolveBurstCourse: (
		position: Vector3,
		threatPosition: Vector3,
		preferredDirection: Vector3,
		desiredDistance: number,
		minimumDistance: number
	) -> Vector3?,
	ResolveZigzagCourse: (
		position: Vector3,
		threatPosition: Vector3,
		preferredDirection: Vector3,
		desiredDistance: number
	) -> Vector3?,
}

export type Decision = {
	Kind: "Roam" | "Escape" | "Hold" | "Stop",
	Stage: Stage,
	Direction: Vector3?,
	RequestedSpeed: number?,
	PatternPhase: Zigzag.PatternPhase?,
	Started: boolean?,
	StageChanged: boolean?,
	PreviousStage: Stage?,
	AcquiredUserId: number?,
	EndedReason: string?,
	ReleaseReason: string?,
	RouteBlocked: boolean?,
}

local LegendaryPursuit = {}
local DIRECTION_EPSILON = 1e-5
local activeOwner: State? = nil

local function finiteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function horizontalUnit(value: Vector3): Vector3?
	local horizontal = Vector3.new(value.X, 0, value.Z)
	return if horizontal.X == horizontal.X
			and horizontal.Z == horizontal.Z
			and horizontal.Magnitude > DIRECTION_EPSILON
		then horizontal.Unit
		else nil
end

local function decision(kind: "Roam" | "Escape" | "Hold" | "Stop", stage: Stage): Decision
	return { Kind = kind, Stage = stage }
end

local function isOpeningStage(stage: Stage): boolean
	return stage == "Opening1Enter"
		or stage == "Opening1"
		or stage == "Opening2Enter"
		or stage == "Opening2"
end

local function clearThreat(state: State)
	state.lockedThreatUserId = nil
	state.lockedThreatCharacter = nil
	state.lockedThreatPosition = nil
	state.lostThreatSince = nil
	state.lostThreatReason = nil
end

local function clearMotion(state: State)
	state.plan = nil
	state.sequenceStartedAt = nil
	state.plannedEndAt = nil
	state.stageStartedAt = nil
	state.stageEndsAt = nil
	state.committedDirection = nil
	state.phase2Forward = nil
	state.phase2Right = nil
	state.openingBlocked = false
	state.disengageAfterOpening = false
end

local function releaseReservation(state: State)
	if not state.reservationOwned then
		return
	end
	state.reservationOwned = false
	if activeOwner == state then
		activeOwner = nil
	end
end

local function reserve(state: State, config: Config): boolean
	if config.MaxActiveEncounters < 1 then
		return false
	end
	if activeOwner ~= nil and not activeOwner.active then
		activeOwner = nil
	end
	if activeOwner ~= nil and activeOwner ~= state then
		return false
	end
	activeOwner = state
	state.reservationOwned = true
	return true
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

function LegendaryPursuit.BuildPlan(
	legendaryConfig: Config,
	sprinterConfig: SprinterConfig,
	zigzagConfig: ZigzagConfig,
	baseSpeed: number
): Plan?
	local motionProfile = Sprinter.BuildMotionProfile(baseSpeed, sprinterConfig)
	local zigzagPlan = Zigzag.BuildCyclePlan(baseSpeed, zigzagConfig.InitialSide, zigzagConfig)
	if motionProfile == nil or zigzagPlan == nil then
		return nil
	end

	local opening1Enter = sprinterConfig.BurstDurationSeconds
	local opening1 = opening1Enter + sprinterConfig.RecoveryDecelerationSeconds
	local phase2Enter = opening1 + legendaryConfig.OpeningDurationSeconds
	local phase2 = phase2Enter + zigzagConfig.CourseReorientSeconds
	local opening2Enter = phase2
		+ zigzagPlan.CycleDurationSeconds * legendaryConfig.ZigzagCycleCount
	local opening2 = opening2Enter + sprinterConfig.RecoveryDecelerationSeconds
	local sequenceEnd = opening2 + legendaryConfig.OpeningDurationSeconds

	return table.freeze({
		BaseSpeed = baseSpeed,
		OpeningSpeed = motionProfile.RecoverySpeed,
		MotionProfile = motionProfile,
		ZigzagPlan = zigzagPlan,
		BurstDuration = sprinterConfig.BurstDurationSeconds,
		OpeningTransitionDuration = sprinterConfig.RecoveryDecelerationSeconds,
		OpeningDuration = legendaryConfig.OpeningDurationSeconds,
		Phase2EntryDuration = zigzagConfig.CourseReorientSeconds,
		Phase2Duration = zigzagPlan.CycleDurationSeconds * legendaryConfig.ZigzagCycleCount,
		Phase1BurstStartsAt = 0,
		Opening1EnterStartsAt = opening1Enter,
		Opening1StartsAt = opening1,
		Phase2EnterStartsAt = phase2Enter,
		Phase2StartsAt = phase2,
		Opening2EnterStartsAt = opening2Enter,
		Opening2StartsAt = opening2,
		SequenceEndsAt = sequenceEnd,
		EarliestRestartAt = sequenceEnd + legendaryConfig.RepeatCooldownSeconds,
	})
end

function LegendaryPursuit.SampleStage(plan: Plan, elapsed: number): (Stage, number)
	local time = math.max(0, elapsed)
	if time < plan.Opening1EnterStartsAt then
		return "Phase1Burst", time
	elseif time < plan.Opening1StartsAt then
		return "Opening1Enter", time - plan.Opening1EnterStartsAt
	elseif time < plan.Phase2EnterStartsAt then
		return "Opening1", time - plan.Opening1StartsAt
	elseif time < plan.Phase2StartsAt then
		return "Phase2Enter", time - plan.Phase2EnterStartsAt
	elseif time < plan.Opening2EnterStartsAt then
		return "Phase2Zigzag", time - plan.Phase2StartsAt
	elseif time < plan.Opening2StartsAt then
		return "Opening2Enter", time - plan.Opening2EnterStartsAt
	elseif time < plan.SequenceEndsAt then
		return "Opening2", time - plan.Opening2StartsAt
	end
	return "Cooldown", time - plan.SequenceEndsAt
end

function LegendaryPursuit.SampleSpeed(plan: Plan, elapsed: number): (Stage, number)
	local stage, localTime = LegendaryPursuit.SampleStage(plan, elapsed)
	if stage == "Phase1Burst" then
		return stage, Sprinter.SampleBurstProfile(plan.MotionProfile, localTime)
	elseif stage == "Opening1Enter" then
		return stage,
			Sprinter.SampleTransitionSpeed(
				plan.MotionProfile.PeakSpeed,
				plan.OpeningSpeed,
				localTime,
				plan.OpeningTransitionDuration
			)
	elseif stage == "Opening1" or stage == "Opening2" then
		return stage, plan.OpeningSpeed
	elseif stage == "Phase2Enter" then
		return stage,
			Sprinter.SampleTransitionSpeed(
				plan.OpeningSpeed,
				plan.BaseSpeed,
				localTime,
				plan.Phase2EntryDuration
			)
	elseif stage == "Phase2Zigzag" then
		return stage, plan.BaseSpeed
	elseif stage == "Opening2Enter" then
		return stage,
			Sprinter.SampleTransitionSpeed(
				plan.BaseSpeed,
				plan.OpeningSpeed,
				localTime,
				plan.OpeningTransitionDuration
			)
	end
	return stage, plan.BaseSpeed
end

function LegendaryPursuit.CreateState(now: number, preservedNextAllowedAt: number?): State
	local nextAllowedAt = if preservedNextAllowedAt ~= nil and preservedNextAllowedAt > now
		then preservedNextAllowedAt
		else now
	return {
		Stage = if nextAllowedAt > now then "Cooldown" else "Idle",
		active = false,
		revision = 0,
		lockedThreatUserId = nil,
		lockedThreatCharacter = nil,
		lockedThreatPosition = nil,
		lostThreatSince = nil,
		lostThreatReason = nil,
		disengageAfterOpening = false,
		plan = nil,
		sequenceStartedAt = nil,
		plannedEndAt = nil,
		stageStartedAt = nil,
		stageEndsAt = nil,
		committedDirection = nil,
		phase2Forward = nil,
		phase2Right = nil,
		openingBlocked = false,
		nextAllowedAt = nextAllowedAt,
		nextBlockedRetryAt = 0,
		reservationOwned = false,
		runtimeId = nil,
	}
end

local function enterStage(state: State, stage: Stage, transitionTime: number)
	local plan = state.plan
	if plan == nil then
		return
	end
	state.revision += 1
	state.Stage = stage
	state.stageStartedAt = transitionTime
	local continuingBlockedOpening = state.openingBlocked
		and (stage == "Opening1" or stage == "Opening2")
	state.openingBlocked = continuingBlockedOpening
	if stage == "Phase1Burst" then
		state.stageEndsAt = transitionTime + plan.BurstDuration
	elseif stage == "Opening1Enter" or stage == "Opening2Enter" then
		state.stageEndsAt = transitionTime + plan.OpeningTransitionDuration
	elseif stage == "Opening1" or stage == "Opening2" then
		state.stageEndsAt = transitionTime + plan.OpeningDuration
	elseif stage == "Phase2Enter" then
		state.stageEndsAt = transitionTime + plan.Phase2EntryDuration
	elseif stage == "Phase2Zigzag" then
		state.stageEndsAt = transitionTime + plan.Phase2Duration
	else
		state.stageEndsAt = nil
	end
end

local function finish(
	state: State,
	now: number,
	reason: string,
	config: Config,
	extendLateCooldown: boolean
): Decision
	local wasActive = state.active
	local plannedEndAt = state.plannedEndAt
	local releaseReason = state.lostThreatReason
	state.active = false
	state.revision += 1
	if extendLateCooldown and plannedEndAt ~= nil and now > plannedEndAt then
		state.nextAllowedAt = math.max(state.nextAllowedAt, now + config.RepeatCooldownSeconds)
	end
	releaseReservation(state)
	clearThreat(state)
	clearMotion(state)
	state.Stage = if now < state.nextAllowedAt then "Cooldown" else "Idle"
	local result = decision("Roam", state.Stage)
	if wasActive then
		result.EndedReason = reason
		result.ReleaseReason = if reason == "Disengaged" then releaseReason or reason else nil
	end
	return result
end

function LegendaryPursuit.Interrupt(
	state: State,
	now: number,
	_reason: string,
	_config: Config
): boolean
	local hadWork = state.active or state.reservationOwned
	state.active = false
	state.revision += 1
	releaseReservation(state)
	clearThreat(state)
	clearMotion(state)
	state.Stage = if now < state.nextAllowedAt then "Cooldown" else "Idle"
	return hadWork
end

function LegendaryPursuit.TryStart(
	state: State,
	context: Context,
	now: number,
	config: Config,
	sprinterConfig: SprinterConfig,
	zigzagConfig: ZigzagConfig
): (boolean, number?)
	if
		state.active
		or not context.Authorized
		or not context.LifecycleEligible
		or not context.Sensing
		or now < state.nextAllowedAt
		or now < state.nextBlockedRetryAt
		or not finiteNumber(context.ResolvedSpeed)
		or context.ResolvedSpeed <= 0
	then
		return false, nil
	end
	local selected = ReactiveRunner.SelectThreat(
		context.Position,
		context.Candidates,
		context.CanSeeCandidate,
		{ AwarenessRadius = config.AwarenessRadius }
	)
	if selected == nil then
		return false, nil
	end
	local plan =
		LegendaryPursuit.BuildPlan(config, sprinterConfig, zigzagConfig, context.ResolvedSpeed)
	if plan == nil then
		return false, nil
	end
	local preferred =
		ReactiveRunner.ComputeEscapeDirection(context.Position, selected.Position, context.Forward)
	local desiredDistance = math.max(
		sprinterConfig.MinimumBurstClearanceStuds,
		plan.MotionProfile.PeakSpeed * plan.BurstDuration
	)
	local safeCourse = context.ResolveBurstCourse(
		context.Position,
		selected.Position,
		preferred,
		desiredDistance,
		sprinterConfig.MinimumBurstClearanceStuds
	)
	if safeCourse == nil then
		state.nextBlockedRetryAt = now + config.BlockedRetrySeconds
		return false, nil
	end
	local direction = horizontalUnit(safeCourse)
	if direction == nil then
		state.nextBlockedRetryAt = now + config.BlockedRetrySeconds
		return false, nil
	end
	if not reserve(state, config) then
		return false, nil
	end

	state.active = true
	state.runtimeId = context.RuntimeId
	state.plan = plan
	state.sequenceStartedAt = now
	state.plannedEndAt = now + plan.SequenceEndsAt
	state.nextAllowedAt = now + plan.EarliestRestartAt
	state.nextBlockedRetryAt = now
	state.lockedThreatUserId = selected.UserId
	state.lockedThreatCharacter = selected.Character
	state.lockedThreatPosition = selected.Position
	state.lostThreatSince = nil
	state.lostThreatReason = nil
	state.disengageAfterOpening = false
	state.committedDirection = direction
	state.phase2Forward = nil
	state.phase2Right = nil
	enterStage(state, "Phase1Burst", now)
	return true, selected.UserId
end

local function markDisengaged(state: State, now: number, reason: string, config: Config): Decision?
	state.lockedThreatUserId = nil
	state.lockedThreatCharacter = nil
	state.lockedThreatPosition = nil
	state.lostThreatSince = nil
	state.lostThreatReason = reason
	if isOpeningStage(state.Stage) then
		state.disengageAfterOpening = true
		return nil
	end
	return finish(state, now, "Disengaged", config, false)
end

local function updateThreat(state: State, context: Context, now: number, config: Config): Decision?
	if not context.Sensing or state.lockedThreatUserId == nil then
		return nil
	end
	local candidate = findLockedCandidate(state, context.Candidates)
	if candidate == nil then
		return markDisengaged(state, now, "InvalidThreat", config)
	end
	state.lockedThreatPosition = candidate.Position
	local inRange = (candidate.Position - context.Position).Magnitude <= config.DisengageRadius
	local visible = inRange and context.CanSeeCandidate(candidate)
	if inRange and visible then
		state.lostThreatSince = nil
		state.lostThreatReason = nil
		return nil
	end
	state.lostThreatSince = state.lostThreatSince or now
	state.lostThreatReason = if inRange then "Occluded" else "OutOfRange"
	if now - (state.lostThreatSince :: number) >= config.DisengageGraceSeconds then
		return markDisengaged(state, now, state.lostThreatReason :: string, config)
	end
	return nil
end

local function preparePhase2(
	state: State,
	context: Context,
	transitionTime: number,
	zigzagConfig: ZigzagConfig
): boolean
	local threat = state.lockedThreatPosition
	local plan = state.plan
	if threat == nil or plan == nil then
		return false
	end
	local current = state.committedDirection or context.Forward
	local preferred = select(1, Zigzag.ComputeCourse(context.Position, threat, current))
	local desiredDistance = plan.BaseSpeed
		* (zigzagConfig.SweepDurationSeconds + zigzagConfig.StraightDurationSeconds)
	local safe = context.ResolveZigzagCourse(context.Position, threat, preferred, desiredDistance)
	local forward = if safe then horizontalUnit(safe) else nil
	if forward == nil then
		return false
	end
	state.phase2Forward = forward
	state.phase2Right = forward:Cross(Vector3.yAxis).Unit
	enterStage(state, "Phase2Enter", transitionTime)
	return true
end

local function advanceStage(
	state: State,
	context: Context,
	now: number,
	config: Config,
	zigzagConfig: ZigzagConfig
): Decision?
	local changed = false
	local previousStage = state.Stage
	for _ = 1, 8 do
		local transitionTime = state.stageEndsAt
		if transitionTime == nil or now + DIRECTION_EPSILON < transitionTime then
			break
		end
		changed = true
		if state.Stage == "Phase1Burst" then
			enterStage(state, "Opening1Enter", transitionTime)
		elseif state.Stage == "Opening1Enter" then
			enterStage(state, "Opening1", transitionTime)
		elseif state.Stage == "Opening1" then
			if state.disengageAfterOpening then
				local result = finish(state, transitionTime, "Disengaged", config, false)
				result.StageChanged = true
				result.PreviousStage = previousStage
				return result
			elseif not preparePhase2(state, context, transitionTime, zigzagConfig) then
				enterStage(state, "Opening2Enter", transitionTime)
			end
		elseif state.Stage == "Phase2Enter" then
			state.committedDirection = state.phase2Forward or state.committedDirection
			enterStage(state, "Phase2Zigzag", transitionTime)
		elseif state.Stage == "Phase2Zigzag" then
			state.committedDirection = state.phase2Forward or state.committedDirection
			enterStage(state, "Opening2Enter", transitionTime)
		elseif state.Stage == "Opening2Enter" then
			enterStage(state, "Opening2", transitionTime)
		elseif state.Stage == "Opening2" then
			local result = finish(
				state,
				now,
				if state.disengageAfterOpening then "Disengaged" else "Completed",
				config,
				true
			)
			result.StageChanged = true
			result.PreviousStage = previousStage
			return result
		else
			break
		end
	end
	if changed then
		local result = decision("Hold", state.Stage)
		result.StageChanged = true
		result.PreviousStage = previousStage
		return result
	end
	return nil
end

function LegendaryPursuit.OnMovementBlocked(state: State, now: number, _config: Config): boolean
	if not state.active then
		return false
	end
	if state.Stage == "Phase1Burst" then
		enterStage(state, "Opening1Enter", now)
	elseif state.Stage == "Phase2Enter" or state.Stage == "Phase2Zigzag" then
		state.committedDirection = state.phase2Forward or state.committedDirection
		enterStage(state, "Opening2Enter", now)
	elseif isOpeningStage(state.Stage) then
		state.openingBlocked = true
		state.revision += 1
	else
		return false
	end
	return true
end

function LegendaryPursuit.SampleCurrentMotion(
	state: State,
	now: number
): (Vector3?, number?, Zigzag.PatternPhase?)
	local plan = state.plan
	local startedAt = state.stageStartedAt
	local direction = state.committedDirection
	if plan == nil or startedAt == nil then
		return nil, nil, nil
	end
	local elapsed = math.max(0, now - startedAt)
	if state.Stage == "Phase1Burst" then
		return direction, Sprinter.SampleBurstProfile(plan.MotionProfile, elapsed), nil
	elseif state.Stage == "Opening1Enter" then
		return direction,
			Sprinter.SampleTransitionSpeed(
				plan.MotionProfile.PeakSpeed,
				plan.OpeningSpeed,
				elapsed,
				plan.OpeningTransitionDuration
			),
			nil
	elseif state.Stage == "Opening1" or state.Stage == "Opening2" then
		return direction, plan.OpeningSpeed, nil
	elseif state.Stage == "Phase2Enter" then
		local from = direction or state.phase2Forward
		local to = state.phase2Forward or from
		if from == nil or to == nil then
			return nil, nil, nil
		end
		return Zigzag.BlendCourseDirection(from, to, elapsed / plan.Phase2EntryDuration),
			Sprinter.SampleTransitionSpeed(
				plan.OpeningSpeed,
				plan.BaseSpeed,
				elapsed,
				plan.Phase2EntryDuration
			),
			nil
	elseif state.Stage == "Phase2Zigzag" then
		local forward, right = state.phase2Forward, state.phase2Right
		if forward == nil or right == nil then
			return nil, nil, nil
		end
		local phase, yaw = Zigzag.SamplePattern(elapsed, plan.ZigzagPlan)
		return Zigzag.DirectionForYaw(forward, right, yaw), plan.BaseSpeed, phase
	elseif state.Stage == "Opening2Enter" then
		return direction,
			Sprinter.SampleTransitionSpeed(
				plan.BaseSpeed,
				plan.OpeningSpeed,
				elapsed,
				plan.OpeningTransitionDuration
			),
			nil
	end
	return nil, nil, nil
end

function LegendaryPursuit.Step(
	state: State,
	context: Context,
	now: number,
	dt: number,
	config: Config,
	sprinterConfig: SprinterConfig,
	zigzagConfig: ZigzagConfig
): Decision
	if not context.Authorized or not context.LifecycleEligible then
		LegendaryPursuit.Interrupt(state, now, "Lifecycle", config)
		return decision("Stop", state.Stage)
	end
	if state.active and dt > config.MaxUpdateGapSeconds then
		return finish(state, now, "UpdateGap", config, false)
	end
	if not state.active then
		state.Stage = if now < state.nextAllowedAt then "Cooldown" else "Idle"
		local started, acquired =
			LegendaryPursuit.TryStart(state, context, now, config, sprinterConfig, zigzagConfig)
		if not started then
			return decision("Roam", state.Stage)
		end
		local result = decision("Escape", state.Stage)
		result.Started = true
		result.AcquiredUserId = acquired
		result.Direction, result.RequestedSpeed = LegendaryPursuit.SampleCurrentMotion(state, now)
		return result
	end

	local disengaged = updateThreat(state, context, now, config)
	if disengaged ~= nil then
		return disengaged
	end
	local advanced = advanceStage(state, context, now, config, zigzagConfig)
	if advanced ~= nil then
		if not state.active or advanced.EndedReason ~= nil then
			return advanced
		end
		local direction, speed, patternPhase = LegendaryPursuit.SampleCurrentMotion(state, now)
		advanced.Kind = if state.openingBlocked
				or direction == nil
				or speed == nil
			then "Hold"
			else "Escape"
		advanced.Direction = direction
		advanced.RequestedSpeed = speed
		advanced.PatternPhase = patternPhase
		advanced.Stage = state.Stage
		return advanced
	end
	if state.openingBlocked then
		return decision("Hold", state.Stage)
	end
	local direction, speed, patternPhase = LegendaryPursuit.SampleCurrentMotion(state, now)
	if direction == nil or speed == nil then
		return decision("Hold", state.Stage)
	end
	local result = decision("Escape", state.Stage)
	result.Direction = direction
	result.RequestedSpeed = speed
	result.PatternPhase = patternPhase
	return result
end

function LegendaryPursuit.GetDiagnostics()
	return table.freeze({
		ActiveEncounters = if activeOwner ~= nil and activeOwner.active then 1 else 0,
		ActiveRuntimeId = if activeOwner ~= nil and activeOwner.active
			then activeOwner.runtimeId
			else nil,
	})
end

return table.freeze(LegendaryPursuit)
