--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartStabilityTypes = require(ReplicatedStorage.Shared.Types.CartStabilityTypes)

type AngularComponents = CartStabilityTypes.AngularComponents
type EffectiveStabilityProfile = CartStabilityTypes.EffectiveStabilityProfile
type OrientationError = CartStabilityTypes.OrientationError
type StabilityMode = CartStabilityTypes.StabilityMode
type StabilityStepInput = CartStabilityTypes.StabilityStepInput
type StabilityStepResult = CartStabilityTypes.StabilityStepResult

local VECTOR_EPSILON = 1e-6

local CartStabilityMath = {}

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function resolveUnit(value: Vector3, fallback: Vector3): Vector3
	if isFiniteVector3(value) and value.Magnitude > VECTOR_EPSILON then
		return value.Unit
	end

	if isFiniteVector3(fallback) and fallback.Magnitude > VECTOR_EPSILON then
		return fallback.Unit
	end

	return Vector3.yAxis
end

local function projectOntoPlane(value: Vector3, normal: Vector3): Vector3
	return value - normal * value:Dot(normal)
end

local function getDeterministicPerpendicular(unitNormal: Vector3): Vector3
	local preferred = if math.abs(unitNormal:Dot(-Vector3.zAxis)) < 0.95
		then -Vector3.zAxis
		else Vector3.xAxis
	local projected = projectOntoPlane(preferred, unitNormal)

	if projected.Magnitude <= VECTOR_EPSILON then
		projected = projectOntoPlane(Vector3.yAxis, unitNormal)
	end

	return resolveUnit(projected, Vector3.xAxis)
end

local function clampMagnitude(value: Vector3, maximumMagnitude: number): Vector3
	if
		not isFiniteVector3(value)
		or not isFiniteNumber(maximumMagnitude)
		or maximumMagnitude <= 0
	then
		return Vector3.zero
	end

	local magnitude = value.Magnitude

	if magnitude <= maximumMagnitude then
		return value
	end

	return value.Unit * maximumMagnitude
end

local function smoothStep(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)

	return clamped * clamped * (3 - 2 * clamped)
end

function CartStabilityMath.BuildHeadingFrame(
	intendedHeading: Vector3,
	referenceUp: Vector3,
	fallbackHeading: Vector3?
): (CFrame, Vector3)
	local up = resolveUnit(referenceUp, Vector3.yAxis)
	local projectedHeading = if isFiniteVector3(intendedHeading)
		then projectOntoPlane(intendedHeading, up)
		else Vector3.zero

	if projectedHeading.Magnitude <= VECTOR_EPSILON and fallbackHeading ~= nil then
		projectedHeading = if isFiniteVector3(fallbackHeading)
			then projectOntoPlane(fallbackHeading, up)
			else Vector3.zero
	end

	local heading = if projectedHeading.Magnitude > VECTOR_EPSILON
		then projectedHeading.Unit
		else getDeterministicPerpendicular(up)
	local right = resolveUnit(heading:Cross(up), Vector3.xAxis)

	heading = resolveUnit(up:Cross(right), heading)

	return CFrame.fromMatrix(Vector3.zero, right, up, -heading), heading
end

CartStabilityMath.GetHeadingFrame = CartStabilityMath.BuildHeadingFrame

function CartStabilityMath.ApplyHeadingPreservingTilt(
	currentCFrame: CFrame,
	intendedHeading: Vector3,
	desiredUp: Vector3,
	fallbackHeading: Vector3?
): (CFrame, Vector3)
	local currentHeadingFrame =
		CartStabilityMath.BuildHeadingFrame(currentCFrame.LookVector, desiredUp, fallbackHeading)
	local desiredHeadingFrame, resolvedHeading =
		CartStabilityMath.BuildHeadingFrame(intendedHeading, desiredUp, fallbackHeading)
	local currentRotation = CFrame.fromMatrix(
		Vector3.zero,
		currentCFrame.RightVector,
		currentCFrame.UpVector,
		-currentCFrame.LookVector
	)
	local currentTilt = currentHeadingFrame:ToObjectSpace(currentRotation)
	local targetRotation = desiredHeadingFrame * currentTilt

	return CFrame.new(currentCFrame.Position) * targetRotation, resolvedHeading
end

function CartStabilityMath.GetOrientationError(
	currentUp: Vector3,
	desiredUp: Vector3,
	headingForward: Vector3
): OrientationError
	local up = resolveUnit(desiredUp, Vector3.yAxis)
	local current = resolveUnit(currentUp, up)
	local _, heading = CartStabilityMath.BuildHeadingFrame(headingForward, up, nil)
	local right = resolveUnit(heading:Cross(up), Vector3.xAxis)
	local dot = math.clamp(current:Dot(up), -1, 1)
	local tiltAngle = math.acos(dot)
	local cross = current:Cross(up)
	local correctionAxis: Vector3

	if cross.Magnitude > VECTOR_EPSILON then
		correctionAxis = cross.Unit
	elseif dot < 0 then
		-- An inverted up vector has infinitely many mathematically valid
		-- recovery axes. The resolved heading is deterministic and preserves
		-- the caller's intended yaw.
		correctionAxis = heading
	else
		correctionAxis = Vector3.zero
	end

	local errorVector = correctionAxis * tiltAngle

	return {
		CorrectionAxis = correctionAxis,
		TiltAngle = tiltAngle,
		RollAngle = errorVector:Dot(heading),
		PitchAngle = errorVector:Dot(right),
	}
end

function CartStabilityMath.DecomposeAngularVelocity(
	angularVelocity: Vector3,
	headingForward: Vector3,
	desiredUp: Vector3
): AngularComponents
	local up = resolveUnit(desiredUp, Vector3.yAxis)
	local _, heading = CartStabilityMath.BuildHeadingFrame(headingForward, up, nil)
	local right = resolveUnit(heading:Cross(up), Vector3.xAxis)
	local velocity = if isFiniteVector3(angularVelocity) then angularVelocity else Vector3.zero

	return {
		Roll = velocity:Dot(heading),
		Pitch = velocity:Dot(right),
		Yaw = velocity:Dot(up),
	}
end

function CartStabilityMath.GetProgressiveCorrection(
	angleRadians: number,
	freeAngleRadians: number,
	moderateAngleRadians: number,
	strongAngleRadians: number
): number
	local magnitude = math.abs(angleRadians)

	if magnitude <= freeAngleRadians then
		return 0
	elseif magnitude < moderateAngleRadians then
		local alpha = (magnitude - freeAngleRadians) / (moderateAngleRadians - freeAngleRadians)

		return 0.5 * smoothStep(alpha)
	elseif magnitude < strongAngleRadians then
		local alpha = (magnitude - moderateAngleRadians)
			/ (strongAngleRadians - moderateAngleRadians)

		return 0.5 + 0.5 * smoothStep(alpha)
	end

	return 1
end

function CartStabilityMath.GetExponentialAlpha(responseSpeed: number, deltaTime: number): number
	if
		not isFiniteNumber(responseSpeed)
		or not isFiniteNumber(deltaTime)
		or responseSpeed <= 0
		or deltaTime <= 0
	then
		return 0
	end

	return 1 - math.exp(-responseSpeed * deltaTime)
end

local function enforceCorrectiveAngularResponse(
	command: number,
	angle: number,
	correctionStrength: number,
	angularVelocity: number,
	maximumAngularResponse: number,
	damping: number
): number
	if correctionStrength <= 0 or angle == 0 or maximumAngularResponse <= 0 then
		return command
	end

	local correctionDirection = math.sign(angle)
	local directedAngularVelocity = angularVelocity * correctionDirection

	if directedAngularVelocity < maximumAngularResponse then
		return command
	end

	-- Once an axis is already correcting at the approved response ceiling,
	-- permit only neutral or opposing torque on that axis. External impacts may
	-- exceed the ceiling, so progressively apply the configured damping rather
	-- than trying to snap the measured velocity to a limit.
	local excessAlpha = math.clamp(
		(directedAngularVelocity - maximumAngularResponse) / maximumAngularResponse,
		0,
		1
	)
	local maximumCommandAlongCorrection = -excessAlpha * damping
	local commandAlongCorrection = command * correctionDirection

	return math.min(commandAlongCorrection, maximumCommandAlongCorrection) * correctionDirection
end

local function getMode(
	rollAngle: number,
	pitchAngle: number,
	profile: EffectiveStabilityProfile
): (StabilityMode, boolean)
	local rollMagnitude = math.abs(rollAngle)
	local pitchMagnitude = math.abs(pitchAngle)
	local freeRoll = math.rad(profile.FreeRollAngleDegrees)
	local freePitch = math.rad(profile.FreePitchAngleDegrees)
	local moderateRoll = math.rad(profile.ModerateRollAngleDegrees)
	local moderatePitch = math.rad(profile.ModeratePitchAngleDegrees)
	local strongRoll = math.rad(profile.StrongRollAngleDegrees)
	local strongPitch = math.rad(profile.StrongPitchAngleDegrees)

	if rollMagnitude >= strongRoll or pitchMagnitude >= strongPitch then
		return "Severe", true
	elseif rollMagnitude >= moderateRoll or pitchMagnitude >= moderatePitch then
		return "Strong", false
	elseif rollMagnitude > freeRoll or pitchMagnitude > freePitch then
		return "Moderate", false
	end

	return "Free", false
end

local function emptyStepResult(
	heading: Vector3,
	orientationError: OrientationError,
	angularComponents: AngularComponents,
	mode: StabilityMode,
	severeTilt: boolean
): StabilityStepResult
	return {
		Torque = Vector3.zero,
		Heading = heading,
		RollAngle = orientationError.RollAngle,
		PitchAngle = orientationError.PitchAngle,
		TiltAngle = orientationError.TiltAngle,
		RollAngularVelocity = angularComponents.Roll,
		PitchAngularVelocity = angularComponents.Pitch,
		YawAngularVelocity = angularComponents.Yaw,
		CorrectionStrength = 0,
		SevereTilt = severeTilt,
		Mode = mode,
	}
end

function CartStabilityMath.ComputeStep(input: StabilityStepInput): StabilityStepResult
	local profile = input.Profile
	local fallbackHeading = input.PreviousHeading or input.RootCFrame.LookVector
	local _, heading =
		CartStabilityMath.BuildHeadingFrame(input.IntendedHeading, input.DesiredUp, fallbackHeading)
	local orientationError =
		CartStabilityMath.GetOrientationError(input.RootCFrame.UpVector, input.DesiredUp, heading)
	local angularComponents =
		CartStabilityMath.DecomposeAngularVelocity(input.AngularVelocity, heading, input.DesiredUp)
	local mode, severeTilt =
		getMode(orientationError.RollAngle, orientationError.PitchAngle, profile)

	if not profile.Enabled or not isFiniteNumber(input.AssemblyMass) or input.AssemblyMass <= 0 then
		return emptyStepResult(heading, orientationError, angularComponents, mode, severeTilt)
	end

	local deadZone = math.rad(profile.OrientationErrorDeadZoneDegrees)
	local rollAngle = if math.abs(orientationError.RollAngle) <= deadZone
		then 0
		else orientationError.RollAngle
	local pitchAngle = if math.abs(orientationError.PitchAngle) <= deadZone
		then 0
		else orientationError.PitchAngle
	local rollCorrection = CartStabilityMath.GetProgressiveCorrection(
		rollAngle,
		math.rad(profile.FreeRollAngleDegrees),
		math.rad(profile.ModerateRollAngleDegrees),
		math.rad(profile.StrongRollAngleDegrees)
	)
	local pitchCorrection = CartStabilityMath.GetProgressiveCorrection(
		pitchAngle,
		math.rad(profile.FreePitchAngleDegrees),
		math.rad(profile.ModeratePitchAngleDegrees),
		math.rad(profile.StrongPitchAngleDegrees)
	)
	local maximumAngularResponse = math.rad(profile.MaxCorrectiveAngularResponseDegreesPerSecond)
	local normalizedRollVelocity =
		math.clamp(angularComponents.Roll / maximumAngularResponse, -1, 1)
	local normalizedPitchVelocity =
		math.clamp(angularComponents.Pitch / maximumAngularResponse, -1, 1)
	local rollCommand = math.sign(rollAngle)
			* rollCorrection
			* profile.UprightStrength
			* profile.RollCorrectionStrength
		- normalizedRollVelocity * profile.RollDamping
	local pitchCommand = math.sign(pitchAngle)
			* pitchCorrection
			* profile.UprightStrength
			* profile.PitchCorrectionStrength
		- normalizedPitchVelocity * profile.PitchDamping

	rollCommand = enforceCorrectiveAngularResponse(
		rollCommand,
		rollAngle,
		rollCorrection,
		angularComponents.Roll,
		maximumAngularResponse,
		profile.RollDamping
	)
	pitchCommand = enforceCorrectiveAngularResponse(
		pitchCommand,
		pitchAngle,
		pitchCorrection,
		angularComponents.Pitch,
		maximumAngularResponse,
		profile.PitchDamping
	)

	local up = resolveUnit(input.DesiredUp, Vector3.yAxis)
	local right = resolveUnit(heading:Cross(up), Vector3.xAxis)
	local yawCommand = 0

	if profile.ExtremeYawDamping > 0 then
		local yawThreshold = math.rad(profile.ExtremeYawThresholdDegreesPerSecond)
		local yawExcess = math.max(math.abs(angularComponents.Yaw) - yawThreshold, 0)

		if yawExcess > 0 then
			yawCommand = -math.sign(angularComponents.Yaw)
				* math.clamp(yawExcess / maximumAngularResponse, 0, 1)
				* profile.ExtremeYawDamping
		end
	end

	local assistanceMultiplier = if isFiniteNumber(input.AssistanceMultiplier)
		then math.max(input.AssistanceMultiplier, 0)
		else 0
	local recoveryMultiplier = if severeTilt then profile.SevereTiltRecoveryMultiplier else 1
	local targetTorque = (heading * rollCommand + right * pitchCommand + up * yawCommand)
		* profile.MaxCorrectiveTorque
		* assistanceMultiplier
		* recoveryMultiplier

	targetTorque = clampMagnitude(targetTorque, profile.MaxCorrectiveTorque)

	local previousTorque = if isFiniteVector3(input.PreviousTorque)
		then clampMagnitude(input.PreviousTorque, profile.MaxCorrectiveTorque)
		else Vector3.zero
	local boundedPreviousRoll = enforceCorrectiveAngularResponse(
		previousTorque:Dot(heading),
		rollAngle,
		rollCorrection,
		angularComponents.Roll,
		maximumAngularResponse,
		0
	)
	local boundedPreviousPitch = enforceCorrectiveAngularResponse(
		previousTorque:Dot(right),
		pitchAngle,
		pitchCorrection,
		angularComponents.Pitch,
		maximumAngularResponse,
		0
	)
	local boundedPreviousTorque = heading * boundedPreviousRoll
		+ right * boundedPreviousPitch
		+ up * previousTorque:Dot(up)
	local responseAlpha =
		CartStabilityMath.GetExponentialAlpha(profile.ResponseSpeed, input.DeltaTime)
	local smoothedTorque = clampMagnitude(
		boundedPreviousTorque:Lerp(targetTorque, responseAlpha),
		profile.MaxCorrectiveTorque
	)

	return {
		Torque = smoothedTorque,
		Heading = heading,
		RollAngle = orientationError.RollAngle,
		PitchAngle = orientationError.PitchAngle,
		TiltAngle = orientationError.TiltAngle,
		RollAngularVelocity = angularComponents.Roll,
		PitchAngularVelocity = angularComponents.Pitch,
		YawAngularVelocity = angularComponents.Yaw,
		CorrectionStrength = math.max(rollCorrection, pitchCorrection),
		SevereTilt = severeTilt,
		Mode = mode,
	}
end

function CartStabilityMath.ComputeTorque(
	rootCFrame: CFrame,
	angularVelocity: Vector3,
	profile: EffectiveStabilityProfile,
	previousTorque: Vector3,
	desiredUp: Vector3,
	intendedHeading: Vector3,
	fallbackHeading: Vector3?,
	deltaTime: number,
	assistanceMultiplier: number?
): StabilityStepResult
	return CartStabilityMath.ComputeStep({
		RootCFrame = rootCFrame,
		AngularVelocity = angularVelocity,
		AssemblyMass = 1,
		DesiredUp = desiredUp,
		IntendedHeading = intendedHeading,
		PreviousTorque = previousTorque,
		PreviousHeading = fallbackHeading,
		AssistanceMultiplier = assistanceMultiplier or 1,
		DeltaTime = deltaTime,
		Profile = profile,
	})
end

return CartStabilityMath
