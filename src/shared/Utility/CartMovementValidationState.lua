--!strict

local CartMovementValidationMath = require(script.Parent.CartMovementValidationMath)

type ValidationResult = CartMovementValidationMath.Result
type Severity = CartMovementValidationMath.Severity

local CartMovementValidationState = {}

export type DevelopmentPolicy = {
	ObservationScoreIncrement: number,
	CorrectiveScoreIncrement: number,
	SevereScoreIncrement: number,
	ValidSampleDecay: number,
	CorrectiveScoreThreshold: number,
	SevereScoreThreshold: number,
	MaximumViolationScore: number,
	CorrectionCooldown: number,
}

export type Policy = {
	Development: DevelopmentPolicy,
}

export type State = {
	Revision: number,
	LastSampleTime: number,
	LastPosition: Vector3,
	LastLinearVelocity: Vector3,
	LastHorizontalSpeed: number,
	LastValidCFrame: CFrame,
	LastValidSampleTime: number,
	ViolationScore: number,
	ConsecutiveViolations: number,
	LastViolationTime: number?,
	LastCorrectionTime: number?,
}

export type Action = "None" | "Observe" | "Correct" | "SevereCorrect"

export type Decision = {
	Action: Action,
	RequestedAction: Action,
	CorrectionAllowed: boolean,
	CorrectionSuppressed: boolean,
	ViolationScore: number,
}

local function horizontalSpeed(linearVelocity: Vector3): number
	return Vector3.new(linearVelocity.X, 0, linearVelocity.Z).Magnitude
end

local function assertFiniteBaseline(rootCFrame: CFrame, linearVelocity: Vector3, now: number)
	assert(
		CartMovementValidationMath.IsFiniteCFrame(rootCFrame),
		"Movement validation baseline CFrame must be finite"
	)
	assert(
		CartMovementValidationMath.IsFiniteVector3(linearVelocity),
		"Movement validation baseline velocity must be finite"
	)
	assert(
		CartMovementValidationMath.IsFiniteNumber(now),
		"Movement validation baseline time must be finite"
	)
end

local function copyState(state: State): State
	return {
		Revision = state.Revision,
		LastSampleTime = state.LastSampleTime,
		LastPosition = state.LastPosition,
		LastLinearVelocity = state.LastLinearVelocity,
		LastHorizontalSpeed = state.LastHorizontalSpeed,
		LastValidCFrame = state.LastValidCFrame,
		LastValidSampleTime = state.LastValidSampleTime,
		ViolationScore = state.ViolationScore,
		ConsecutiveViolations = state.ConsecutiveViolations,
		LastViolationTime = state.LastViolationTime,
		LastCorrectionTime = state.LastCorrectionTime,
	}
end

local function freezeState(state: State): State
	return table.freeze(state)
end

function CartMovementValidationState.Create(
	rootCFrame: CFrame,
	linearVelocity: Vector3,
	now: number,
	revision: number?
): State
	assertFiniteBaseline(rootCFrame, linearVelocity, now)

	return freezeState({
		Revision = revision or 1,
		LastSampleTime = now,
		LastPosition = rootCFrame.Position,
		LastLinearVelocity = linearVelocity,
		LastHorizontalSpeed = horizontalSpeed(linearVelocity),
		LastValidCFrame = rootCFrame,
		LastValidSampleTime = now,
		ViolationScore = 0,
		ConsecutiveViolations = 0,
		LastViolationTime = nil,
		LastCorrectionTime = nil,
	})
end

function CartMovementValidationState.ResetBaseline(
	state: State,
	rootCFrame: CFrame,
	linearVelocity: Vector3,
	now: number,
	revision: number?,
	clearViolations: boolean?
): State
	assertFiniteBaseline(rootCFrame, linearVelocity, now)

	local nextState = copyState(state)

	nextState.Revision = revision or state.Revision
	nextState.LastSampleTime = now
	nextState.LastPosition = rootCFrame.Position
	nextState.LastLinearVelocity = linearVelocity
	nextState.LastHorizontalSpeed = horizontalSpeed(linearVelocity)
	nextState.LastValidCFrame = rootCFrame
	nextState.LastValidSampleTime = now

	if clearViolations ~= false then
		nextState.ViolationScore = 0
		nextState.ConsecutiveViolations = 0
		nextState.LastViolationTime = nil
	end

	return freezeState(nextState)
end

function CartMovementValidationState.IsCorrectionAllowed(
	state: State,
	now: number,
	policy: Policy
): boolean
	if not CartMovementValidationMath.IsFiniteNumber(now) then
		return false
	end

	if state.LastCorrectionTime == nil then
		return true
	end

	return now >= state.LastCorrectionTime
		and now - state.LastCorrectionTime >= policy.Development.CorrectionCooldown
end

local function scoreIncrement(severity: Severity, policy: Policy): number
	local development = policy.Development

	if severity == "Observation" then
		return development.ObservationScoreIncrement
	elseif severity == "Corrective" then
		return development.CorrectiveScoreIncrement
	elseif severity == "Severe" then
		return development.SevereScoreIncrement
	end

	return 0
end

local function requestedAction(severity: Severity, violationScore: number, policy: Policy): Action
	local development = policy.Development

	if severity == "Invalid" or severity == "Valid" then
		return "None"
	elseif severity == "Severe" or violationScore >= development.SevereScoreThreshold then
		return "SevereCorrect"
	elseif violationScore >= development.CorrectiveScoreThreshold then
		return "Correct"
	end

	return "Observe"
end

function CartMovementValidationState.ApplyResult(
	state: State,
	result: ValidationResult,
	rootCFrame: CFrame,
	linearVelocity: Vector3,
	now: number,
	policy: Policy
): (State, Decision)
	local nextState = copyState(state)
	local development = policy.Development
	local severity = result.Severity

	if severity == "Valid" then
		nextState.ViolationScore = math.max(0, state.ViolationScore - development.ValidSampleDecay)
		nextState.ConsecutiveViolations = 0
	elseif severity ~= "Invalid" then
		nextState.ViolationScore = math.min(
			development.MaximumViolationScore,
			state.ViolationScore + scoreIncrement(severity, policy)
		)
		nextState.ConsecutiveViolations = state.ConsecutiveViolations + 1
		nextState.LastViolationTime = now
	end

	local request = requestedAction(severity, nextState.ViolationScore, policy)
	local requestsCorrection = request == "Correct" or request == "SevereCorrect"
	local sampleCanAdvance = not requestsCorrection
		and result.HasFinitePhysicalState
		and result.ElapsedTimeValid
		and CartMovementValidationMath.IsFiniteCFrame(rootCFrame)
		and CartMovementValidationMath.IsFiniteVector3(linearVelocity)
		and CartMovementValidationMath.IsFiniteNumber(now)
		and now > state.LastSampleTime

	if sampleCanAdvance then
		nextState.LastSampleTime = now
		nextState.LastPosition = rootCFrame.Position
		nextState.LastLinearVelocity = linearVelocity
		nextState.LastHorizontalSpeed = result.HorizontalSpeed

		if severity == "Valid" then
			nextState.LastValidCFrame = rootCFrame
			nextState.LastValidSampleTime = now
		end
	end

	local correctionAllowed = result.CanCorrect
		and requestsCorrection
		and CartMovementValidationState.IsCorrectionAllowed(state, now, policy)
	local action: Action = request

	if requestsCorrection and not correctionAllowed then
		action = "Observe"
	end

	return freezeState(nextState),
		table.freeze({
			Action = action,
			RequestedAction = request,
			CorrectionAllowed = correctionAllowed,
			CorrectionSuppressed = requestsCorrection and not correctionAllowed,
			ViolationScore = nextState.ViolationScore,
		})
end

function CartMovementValidationState.MarkCorrection(state: State, now: number): State
	assert(
		CartMovementValidationMath.IsFiniteNumber(now),
		"Movement validation correction time must be finite"
	)

	local nextState = copyState(state)

	nextState.LastCorrectionTime = now

	return freezeState(nextState)
end

return CartMovementValidationState
