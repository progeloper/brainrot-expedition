--!strict

export type ThreatCandidate = {
	UserId: number,
	Character: any,
	Position: Vector3,
}

export type Config = {
	AwarenessRadius: number,
	DisengageRadius: number,
	DisengageGraceSeconds: number,
	ReplanIntervalSeconds: number,
	GoalReachedDistance: number,
	MinimumEscapeDistance: number,
	EscapeLookAheadSeconds: number,
	BlockedRetrySeconds: number,
}

export type AwarenessConfig = {
	AwarenessRadius: number,
}

export type State = {
	lockedThreatUserId: number?,
	lockedThreatCharacter: any?,
	lockedThreatPosition: Vector3?,
	lostThreatSince: number?,
	lostThreatReason: string?,
	escapeGoal: Vector3?,
	nextReplanAt: number,
	nextBlockedRetryAt: number,
}

export type Decision = {
	Kind: "UseRoaming" | "Escape" | "Hold" | "Stop",
	Goal: Vector3?,
	AcquiredUserId: number?,
	ReleaseReason: string?,
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
		desiredDistance: number
	) -> Vector3?,
}

local ReactiveRunner = {}
local DIRECTION_EPSILON = 1e-5
local ESCAPE_ANGLES = table.freeze({ 0, 45, -45, 75, -75 })
local ESCAPE_DISTANCE_SCALES = table.freeze({ 1, 0.5 })

local function finiteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function finiteVector(value: Vector3): boolean
	return finiteNumber(value.X) and finiteNumber(value.Y) and finiteNumber(value.Z)
end

local function decision(kind: "UseRoaming" | "Escape" | "Hold" | "Stop"): Decision
	return { Kind = kind }
end

function ReactiveRunner.CreateState(_now: number): State
	return {
		lockedThreatUserId = nil,
		lockedThreatCharacter = nil,
		lockedThreatPosition = nil,
		lostThreatSince = nil,
		lostThreatReason = nil,
		escapeGoal = nil,
		nextReplanAt = 0,
		nextBlockedRetryAt = 0,
	}
end

function ReactiveRunner.Reset(state: State)
	state.lockedThreatUserId = nil
	state.lockedThreatCharacter = nil
	state.lockedThreatPosition = nil
	state.lostThreatSince = nil
	state.lostThreatReason = nil
	state.escapeGoal = nil
	state.nextReplanAt = 0
	state.nextBlockedRetryAt = 0
end

function ReactiveRunner.SelectThreat(
	brainrotPosition: Vector3,
	candidates: { ThreatCandidate },
	canSeeCandidate: (ThreatCandidate) -> boolean,
	config: AwarenessConfig
): ThreatCandidate?
	local ranked = {}
	for _, candidate in candidates do
		if finiteVector(candidate.Position) then
			local distance = (candidate.Position - brainrotPosition).Magnitude
			if distance <= config.AwarenessRadius then
				table.insert(ranked, { Candidate = candidate, Distance = distance })
			end
		end
	end
	table.sort(ranked, function(left, right)
		if math.abs(left.Distance - right.Distance) <= DIRECTION_EPSILON then
			return left.Candidate.UserId < right.Candidate.UserId
		end
		return left.Distance < right.Distance
	end)
	for _, entry in ranked do
		if canSeeCandidate(entry.Candidate) then
			return entry.Candidate
		end
	end
	return nil
end

function ReactiveRunner.ComputeEscapeDirection(
	brainrotPosition: Vector3,
	threatPosition: Vector3,
	fallbackForward: Vector3
): Vector3
	local delta = brainrotPosition - threatPosition
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	if finiteVector(horizontal) and horizontal.Magnitude > DIRECTION_EPSILON then
		return horizontal.Unit
	end
	local fallback = Vector3.new(fallbackForward.X, 0, fallbackForward.Z)
	if finiteVector(fallback) and fallback.Magnitude > DIRECTION_EPSILON then
		return fallback.Unit
	end
	return Vector3.xAxis
end

-- Candidate ordering is pure and deterministic. The movement owner supplies the
-- world-aware route predicate, so this module never raycasts or moves a Model.
function ReactiveRunner.ResolveEscapeGoal(
	position: Vector3,
	preferredDirection: Vector3,
	desiredDistance: number,
	isSafeCandidate: (Vector3) -> boolean
): Vector3?
	for _, distanceScale in ESCAPE_DISTANCE_SCALES do
		for _, angleDegrees in ESCAPE_ANGLES do
			local angle = math.rad(angleDegrees)
			local cosine, sine = math.cos(angle), math.sin(angle)
			local direction = Vector3.new(
				preferredDirection.X * cosine - preferredDirection.Z * sine,
				0,
				preferredDirection.X * sine + preferredDirection.Z * cosine
			)
			local candidate = position + direction * desiredDistance * distanceScale
			if isSafeCandidate(candidate) then
				return candidate
			end
		end
	end
	return nil
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

local function release(state: State, reason: string): Decision
	ReactiveRunner.Reset(state)
	local result = decision("UseRoaming")
	result.ReleaseReason = reason
	return result
end

function ReactiveRunner.Step(state: State, context: Context, now: number, config: Config): Decision
	if not context.LifecycleEligible then
		ReactiveRunner.Reset(state)
		return decision("Stop")
	end

	local acquiredUserId: number? = nil
	if state.lockedThreatUserId == nil then
		if not context.Sensing then
			return decision("UseRoaming")
		end
		local selected = ReactiveRunner.SelectThreat(
			context.Position,
			context.Candidates,
			context.CanSeeCandidate,
			config
		)
		if selected == nil then
			return decision("UseRoaming")
		end
		state.lockedThreatUserId = selected.UserId
		state.lockedThreatCharacter = selected.Character
		state.lockedThreatPosition = selected.Position
		state.lostThreatSince = nil
		state.lostThreatReason = nil
		state.escapeGoal = nil
		state.nextReplanAt = now
		state.nextBlockedRetryAt = now
		acquiredUserId = selected.UserId
	elseif context.Sensing then
		local current = findLockedCandidate(state, context.Candidates)
		if current == nil then
			return release(state, "InvalidThreat")
		end
		state.lockedThreatPosition = current.Position
		local inRange = (current.Position - context.Position).Magnitude <= config.DisengageRadius
		local visible = inRange and context.CanSeeCandidate(current)
		if inRange and visible then
			state.lostThreatSince = nil
			state.lostThreatReason = nil
		else
			local reason = if inRange then "Occluded" else "OutOfRange"
			if state.lostThreatSince == nil then
				state.lostThreatSince = now
			end
			state.lostThreatReason = reason
			if now - state.lostThreatSince >= config.DisengageGraceSeconds then
				return release(state, reason)
			end
		end
	end

	local threatPosition = state.lockedThreatPosition
	if threatPosition == nil then
		return release(state, "InvalidThreat")
	end

	local goal = state.escapeGoal
	if goal ~= nil and (goal - context.Position).Magnitude <= config.GoalReachedDistance then
		state.escapeGoal = nil
		goal = nil
		state.nextReplanAt = now
	end
	if goal ~= nil and now < state.nextReplanAt then
		local result = decision("Escape")
		result.Goal = goal
		result.AcquiredUserId = acquiredUserId
		return result
	end
	if goal == nil and now < state.nextBlockedRetryAt then
		local result = decision("Hold")
		result.AcquiredUserId = acquiredUserId
		return result
	end

	local preferredDirection =
		ReactiveRunner.ComputeEscapeDirection(context.Position, threatPosition, context.Forward)
	local desiredDistance = math.max(
		config.MinimumEscapeDistance,
		context.ResolvedSpeed * config.EscapeLookAheadSeconds
	)
	goal = context.ResolveEscapeGoal(
		context.Position,
		threatPosition,
		preferredDirection,
		desiredDistance
	)
	if goal == nil then
		state.escapeGoal = nil
		state.nextBlockedRetryAt = now + config.BlockedRetrySeconds
		local result = decision("Hold")
		result.AcquiredUserId = acquiredUserId
		result.RouteBlocked = true
		return result
	end

	state.escapeGoal = goal
	state.nextReplanAt = now + config.ReplanIntervalSeconds
	state.nextBlockedRetryAt = now
	local result = decision("Escape")
	result.Goal = goal
	result.AcquiredUserId = acquiredUserId
	return result
end

return table.freeze(ReactiveRunner)
