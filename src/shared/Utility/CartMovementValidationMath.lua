--!strict

local CartMovementValidationMath = {}

export type Severity = "Invalid" | "Valid" | "Observation" | "Corrective" | "Severe"

export type EffectiveMovementProfile = {
	MaxTravelSpeed: number,
	RecoveryBackupSpeed: number,
	ForwardAcceleration: number,
	CoastDeceleration: number,
	Braking: number,
	RecoveryBackupAcceleration: number,
	RecoveryBackupDeceleration: number,
	MaxAngularSpeed: number,
}

export type DevelopmentPolicy = {
	ForwardSpeedMultiplier: number,
	ForwardSpeedAdditive: number,
	ReverseSpeedMultiplier: number,
	ReverseSpeedAdditive: number,
	LateralSpeedMultiplier: number,
	LateralSpeedAdditive: number,
	OverallSpeedMultiplier: number,
	OverallSpeedAdditive: number,
	CorrectiveHorizontalSpeedMultiplier: number,
	CorrectiveHorizontalSpeedAdditive: number,
	SevereHorizontalSpeedMultiplier: number,
	SevereHorizontalSpeedAdditive: number,
	DisplacementMultiplier: number,
	DisplacementAdditive: number,
	CorrectiveDisplacementMultiplier: number,
	CorrectiveDisplacementAdditive: number,
	SevereDisplacementMultiplier: number,
	SevereDisplacementAdditive: number,
	AccelerationMultiplier: number,
	AccelerationAdditive: number,
	UpwardSpeedObservation: number,
	DownwardSpeedObservation: number,
	VerticalDisplacementAdditive: number,
	AngularSpeedMultiplier: number,
	AngularSpeedAdditiveDegrees: number,
}

export type SystemSafetyPolicy = {
	MaximumHorizontalSpeed: number,
	MaximumUpwardSpeed: number,
	MaximumDownwardSpeed: number,
	MaximumAngularSpeedDegrees: number,
	MaximumVerticalDisplacementAdditive: number,
}

export type Policy = {
	Development: DevelopmentPolicy,
	SystemSafety: SystemSafetyPolicy,
}

export type Thresholds = {
	ForwardObservation: number,
	ReverseObservation: number,
	LateralObservation: number,
	OverallObservation: number,
	HorizontalCorrective: number,
	HorizontalSevere: number,
	AccelerationObservation: number,
	UpwardSpeedObservation: number,
	DownwardSpeedObservation: number,
	UpwardSpeedSevere: number,
	DownwardSpeedSevere: number,
	AngularSpeedObservationDegrees: number,
	AngularSpeedSevereDegrees: number,
}

export type VelocityComponents = {
	ForwardSpeed: number,
	ReverseSpeed: number,
	SignedForwardSpeed: number,
	LateralSpeed: number,
	HorizontalSpeed: number,
}

export type Sample = {
	RootCFrame: CFrame,
	LinearVelocity: Vector3,
	AngularVelocity: Vector3,
	PreviousPosition: Vector3?,
	PreviousHorizontalSpeed: number?,
	ElapsedTime: number,
	TrustedDisplacement: boolean?,
}

export type Result = {
	Severity: Severity,
	Reasons: { string },
	HasFinitePhysicalState: boolean,
	ElapsedTimeValid: boolean,
	CanCorrect: boolean,
	ForwardSpeed: number,
	ReverseSpeed: number,
	SignedForwardSpeed: number,
	LateralSpeed: number,
	HorizontalSpeed: number,
	VerticalSpeed: number,
	AngularSpeedDegrees: number,
	HorizontalDisplacement: number,
	VerticalDisplacement: number,
	ObservedHorizontalSpeed: number,
	HorizontalAcceleration: number,
}

local EPSILON = 1e-6

local SEVERITY_RANK: { [Severity]: number } = {
	Invalid = -1,
	Valid = 0,
	Observation = 1,
	Corrective = 2,
	Severe = 3,
}

local function freezeReasons(reasons: { string }): { string }
	return table.freeze(reasons)
end

local function appendReason(
	reasons: { string },
	currentSeverity: Severity,
	reason: string,
	severity: Severity
): Severity
	table.insert(reasons, reason)

	if SEVERITY_RANK[severity] > SEVERITY_RANK[currentSeverity] then
		return severity
	end

	return currentSeverity
end

function CartMovementValidationMath.IsFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

function CartMovementValidationMath.IsFiniteVector3(value: Vector3): boolean
	return CartMovementValidationMath.IsFiniteNumber(value.X)
		and CartMovementValidationMath.IsFiniteNumber(value.Y)
		and CartMovementValidationMath.IsFiniteNumber(value.Z)
end

function CartMovementValidationMath.IsFiniteCFrame(value: CFrame): boolean
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	return CartMovementValidationMath.IsFiniteNumber(x)
		and CartMovementValidationMath.IsFiniteNumber(y)
		and CartMovementValidationMath.IsFiniteNumber(z)
		and CartMovementValidationMath.IsFiniteNumber(r00)
		and CartMovementValidationMath.IsFiniteNumber(r01)
		and CartMovementValidationMath.IsFiniteNumber(r02)
		and CartMovementValidationMath.IsFiniteNumber(r10)
		and CartMovementValidationMath.IsFiniteNumber(r11)
		and CartMovementValidationMath.IsFiniteNumber(r12)
		and CartMovementValidationMath.IsFiniteNumber(r20)
		and CartMovementValidationMath.IsFiniteNumber(r21)
		and CartMovementValidationMath.IsFiniteNumber(r22)
end

local function resolveHorizontalFrame(rootCFrame: CFrame): (Vector3?, Vector3?)
	if not CartMovementValidationMath.IsFiniteCFrame(rootCFrame) then
		return nil
	end

	local look = rootCFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)

	if forward.Magnitude <= EPSILON then
		local rootRight = rootCFrame.RightVector
		local horizontalRight = Vector3.new(rootRight.X, 0, rootRight.Z)

		if horizontalRight.Magnitude <= EPSILON then
			return nil
		end

		forward = Vector3.new(0, 1, 0):Cross(horizontalRight.Unit)
	end

	forward = forward.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)

	return forward, right
end

function CartMovementValidationMath.DecomposeHorizontalVelocity(
	rootCFrame: CFrame,
	linearVelocity: Vector3
): VelocityComponents?
	if not CartMovementValidationMath.IsFiniteVector3(linearVelocity) then
		return nil
	end

	local forward, right = resolveHorizontalFrame(rootCFrame)

	if forward == nil or right == nil then
		return nil
	end

	local horizontalVelocity = Vector3.new(linearVelocity.X, 0, linearVelocity.Z)
	local signedForwardSpeed = horizontalVelocity:Dot(forward)

	return table.freeze({
		ForwardSpeed = math.max(signedForwardSpeed, 0),
		ReverseSpeed = math.max(-signedForwardSpeed, 0),
		SignedForwardSpeed = signedForwardSpeed,
		LateralSpeed = math.abs(horizontalVelocity:Dot(right)),
		HorizontalSpeed = horizontalVelocity.Magnitude,
	})
end

function CartMovementValidationMath.BuildThresholds(
	profile: EffectiveMovementProfile,
	policy: Policy
): Thresholds
	local development = policy.Development
	local safety = policy.SystemSafety
	local maximumApprovedAcceleration = math.max(
		profile.ForwardAcceleration,
		profile.CoastDeceleration,
		profile.Braking,
		profile.RecoveryBackupAcceleration,
		profile.RecoveryBackupDeceleration
	)

	return table.freeze({
		ForwardObservation = profile.MaxTravelSpeed * development.ForwardSpeedMultiplier
			+ development.ForwardSpeedAdditive,
		ReverseObservation = profile.MaxTravelSpeed * development.ForwardSpeedMultiplier
			+ development.ReverseSpeedAdditive,
		LateralObservation = profile.MaxTravelSpeed * development.LateralSpeedMultiplier
			+ development.LateralSpeedAdditive,
		OverallObservation = profile.MaxTravelSpeed * development.OverallSpeedMultiplier
			+ development.OverallSpeedAdditive,
		HorizontalCorrective = profile.MaxTravelSpeed
				* development.CorrectiveHorizontalSpeedMultiplier
			+ development.CorrectiveHorizontalSpeedAdditive,
		HorizontalSevere = math.min(
			safety.MaximumHorizontalSpeed,
			profile.MaxTravelSpeed * development.SevereHorizontalSpeedMultiplier
				+ development.SevereHorizontalSpeedAdditive
		),
		AccelerationObservation = maximumApprovedAcceleration * development.AccelerationMultiplier
			+ development.AccelerationAdditive,
		UpwardSpeedObservation = development.UpwardSpeedObservation,
		DownwardSpeedObservation = development.DownwardSpeedObservation,
		UpwardSpeedSevere = safety.MaximumUpwardSpeed,
		DownwardSpeedSevere = safety.MaximumDownwardSpeed,
		AngularSpeedObservationDegrees = profile.MaxAngularSpeed
				* development.AngularSpeedMultiplier
			+ development.AngularSpeedAdditiveDegrees,
		AngularSpeedSevereDegrees = safety.MaximumAngularSpeedDegrees,
	})
end

local function classifyHorizontalSpeed(
	components: VelocityComponents,
	thresholds: Thresholds,
	reasons: { string },
	severity: Severity
): Severity
	if components.HorizontalSpeed > thresholds.HorizontalSevere then
		return appendReason(reasons, severity, "SevereHorizontalSpeed", "Severe")
	end

	if components.HorizontalSpeed > thresholds.HorizontalCorrective then
		severity = appendReason(reasons, severity, "CorrectiveHorizontalSpeed", "Corrective")
	end

	if components.ForwardSpeed > thresholds.ForwardObservation then
		severity = appendReason(reasons, severity, "ForwardSpeedExceeded", "Observation")
	end

	if components.ReverseSpeed > thresholds.ReverseObservation then
		severity = appendReason(reasons, severity, "ReverseSpeedExceeded", "Observation")
	end

	if components.LateralSpeed > thresholds.LateralObservation then
		severity = appendReason(reasons, severity, "LateralSpeedExceeded", "Observation")
	end

	if components.HorizontalSpeed > thresholds.OverallObservation then
		severity = appendReason(reasons, severity, "OverallHorizontalSpeedExceeded", "Observation")
	end

	return severity
end

local function classifyVerticalSpeed(
	verticalSpeed: number,
	thresholds: Thresholds,
	reasons: { string },
	severity: Severity
): Severity
	if verticalSpeed > thresholds.UpwardSpeedSevere then
		return appendReason(reasons, severity, "SevereUpwardSpeed", "Severe")
	elseif -verticalSpeed > thresholds.DownwardSpeedSevere then
		return appendReason(reasons, severity, "SevereDownwardSpeed", "Severe")
	elseif verticalSpeed > thresholds.UpwardSpeedObservation then
		return appendReason(reasons, severity, "UpwardSpeedExceeded", "Observation")
	elseif -verticalSpeed > thresholds.DownwardSpeedObservation then
		return appendReason(reasons, severity, "DownwardSpeedExceeded", "Observation")
	end

	return severity
end

local function classifyAngularSpeed(
	angularSpeedDegrees: number,
	thresholds: Thresholds,
	reasons: { string },
	severity: Severity
): Severity
	if angularSpeedDegrees > thresholds.AngularSpeedSevereDegrees then
		return appendReason(reasons, severity, "SevereAngularSpeed", "Severe")
	elseif angularSpeedDegrees > thresholds.AngularSpeedObservationDegrees then
		return appendReason(reasons, severity, "AngularSpeedExceeded", "Observation")
	end

	return severity
end

local function classifyDisplacement(
	profile: EffectiveMovementProfile,
	policy: Policy,
	horizontalDisplacement: number,
	verticalDisplacement: number,
	elapsedTime: number,
	reasons: { string },
	severity: Severity
): Severity
	local development = policy.Development
	local safety = policy.SystemSafety
	local observationDistance = profile.MaxTravelSpeed
			* elapsedTime
			* development.DisplacementMultiplier
		+ development.DisplacementAdditive
	local correctiveDistance = profile.MaxTravelSpeed
			* elapsedTime
			* development.CorrectiveDisplacementMultiplier
		+ development.CorrectiveDisplacementAdditive
	local severeDistance = profile.MaxTravelSpeed
			* elapsedTime
			* development.SevereDisplacementMultiplier
		+ development.SevereDisplacementAdditive

	if horizontalDisplacement > severeDistance then
		severity = appendReason(reasons, severity, "SevereHorizontalDisplacement", "Severe")
	elseif horizontalDisplacement > correctiveDistance then
		severity = appendReason(reasons, severity, "CorrectiveHorizontalDisplacement", "Corrective")
	elseif horizontalDisplacement > observationDistance then
		severity = appendReason(reasons, severity, "HorizontalDisplacementExceeded", "Observation")
	end

	local upwardDisplacement = math.max(verticalDisplacement, 0)
	local downwardDisplacement = math.max(-verticalDisplacement, 0)
	local upwardObservation = development.UpwardSpeedObservation * elapsedTime
		+ development.VerticalDisplacementAdditive
	local downwardObservation = development.DownwardSpeedObservation * elapsedTime
		+ development.VerticalDisplacementAdditive
	local upwardSevere = safety.MaximumUpwardSpeed * elapsedTime
		+ safety.MaximumVerticalDisplacementAdditive
	local downwardSevere = safety.MaximumDownwardSpeed * elapsedTime
		+ safety.MaximumVerticalDisplacementAdditive

	if upwardDisplacement > upwardSevere then
		severity = appendReason(reasons, severity, "SevereUpwardDisplacement", "Severe")
	elseif upwardDisplacement > upwardObservation then
		severity = appendReason(reasons, severity, "UpwardDisplacementExceeded", "Observation")
	end

	if downwardDisplacement > downwardSevere then
		severity = appendReason(reasons, severity, "SevereDownwardDisplacement", "Severe")
	elseif downwardDisplacement > downwardObservation then
		severity = appendReason(reasons, severity, "DownwardDisplacementExceeded", "Observation")
	end

	return severity
end

function CartMovementValidationMath.EvaluateSample(
	sample: Sample,
	profile: EffectiveMovementProfile,
	policy: Policy,
	cachedThresholds: Thresholds?
): Result
	local reasons: { string } = {}
	local severity: Severity = "Valid"
	local cFrameFinite = CartMovementValidationMath.IsFiniteCFrame(sample.RootCFrame)
	local linearFinite = CartMovementValidationMath.IsFiniteVector3(sample.LinearVelocity)
	local angularFinite = CartMovementValidationMath.IsFiniteVector3(sample.AngularVelocity)

	if not cFrameFinite then
		severity = appendReason(reasons, severity, "NonFiniteCFrame", "Severe")
	end

	if not linearFinite then
		severity = appendReason(reasons, severity, "NonFiniteLinearVelocity", "Severe")
	end

	if not angularFinite then
		severity = appendReason(reasons, severity, "NonFiniteAngularVelocity", "Severe")
	end

	local previousPositionFinite = sample.PreviousPosition == nil
		or CartMovementValidationMath.IsFiniteVector3(sample.PreviousPosition)
	local previousSpeedFinite = sample.PreviousHorizontalSpeed == nil
		or CartMovementValidationMath.IsFiniteNumber(sample.PreviousHorizontalSpeed)

	if not previousPositionFinite then
		severity = appendReason(reasons, severity, "NonFinitePreviousPosition", "Severe")
	end

	if not previousSpeedFinite then
		severity = appendReason(reasons, severity, "NonFinitePreviousSpeed", "Severe")
	end

	local elapsedFinite = CartMovementValidationMath.IsFiniteNumber(sample.ElapsedTime)
	local elapsedTimeValid = elapsedFinite and sample.ElapsedTime > 0

	if not elapsedFinite then
		table.insert(reasons, "NonFiniteElapsedTime")
	elseif sample.ElapsedTime <= 0 then
		table.insert(reasons, "NonPositiveElapsedTime")
	end

	local hasFinitePhysicalState = cFrameFinite and linearFinite and angularFinite
	local components: VelocityComponents? = nil
	local verticalSpeed = 0
	local angularSpeedDegrees = 0
	local horizontalDisplacement = 0
	local verticalDisplacement = 0
	local observedHorizontalSpeed = 0
	local horizontalAcceleration = 0

	if hasFinitePhysicalState then
		components = CartMovementValidationMath.DecomposeHorizontalVelocity(
			sample.RootCFrame,
			sample.LinearVelocity
		)

		if components == nil then
			severity = appendReason(reasons, severity, "InvalidStructuralHeading", "Observation")
		else
			local thresholds = cachedThresholds
				or CartMovementValidationMath.BuildThresholds(profile, policy)

			severity = classifyHorizontalSpeed(components, thresholds, reasons, severity)
			verticalSpeed = sample.LinearVelocity.Y
			severity = classifyVerticalSpeed(verticalSpeed, thresholds, reasons, severity)
			angularSpeedDegrees = math.deg(sample.AngularVelocity.Magnitude)
			severity = classifyAngularSpeed(angularSpeedDegrees, thresholds, reasons, severity)

			if elapsedTimeValid then
				if sample.PreviousPosition ~= nil and previousPositionFinite then
					local displacement = sample.RootCFrame.Position - sample.PreviousPosition

					horizontalDisplacement =
						Vector3.new(displacement.X, 0, displacement.Z).Magnitude
					verticalDisplacement = displacement.Y
					observedHorizontalSpeed = horizontalDisplacement / sample.ElapsedTime

					if sample.TrustedDisplacement ~= true then
						severity = classifyDisplacement(
							profile,
							policy,
							horizontalDisplacement,
							verticalDisplacement,
							sample.ElapsedTime,
							reasons,
							severity
						)
					end
				end

				if sample.PreviousHorizontalSpeed ~= nil and previousSpeedFinite then
					horizontalAcceleration = math.abs(
						components.HorizontalSpeed - sample.PreviousHorizontalSpeed
					) / sample.ElapsedTime

					if horizontalAcceleration > thresholds.AccelerationObservation then
						severity = appendReason(
							reasons,
							severity,
							"HorizontalAccelerationExceeded",
							"Observation"
						)
					end
				end
			end
		end
	end

	local resolvedComponents = components
		or {
			ForwardSpeed = 0,
			ReverseSpeed = 0,
			SignedForwardSpeed = 0,
			LateralSpeed = 0,
			HorizontalSpeed = 0,
		}
	local canCorrect = hasFinitePhysicalState == false or elapsedTimeValid

	if not elapsedTimeValid and hasFinitePhysicalState then
		severity = "Invalid"
	end

	return table.freeze({
		Severity = severity,
		Reasons = freezeReasons(reasons),
		HasFinitePhysicalState = hasFinitePhysicalState,
		ElapsedTimeValid = elapsedTimeValid,
		CanCorrect = canCorrect,
		ForwardSpeed = resolvedComponents.ForwardSpeed,
		ReverseSpeed = resolvedComponents.ReverseSpeed,
		SignedForwardSpeed = resolvedComponents.SignedForwardSpeed,
		LateralSpeed = resolvedComponents.LateralSpeed,
		HorizontalSpeed = resolvedComponents.HorizontalSpeed,
		VerticalSpeed = verticalSpeed,
		AngularSpeedDegrees = angularSpeedDegrees,
		HorizontalDisplacement = horizontalDisplacement,
		VerticalDisplacement = verticalDisplacement,
		ObservedHorizontalSpeed = observedHorizontalSpeed,
		HorizontalAcceleration = horizontalAcceleration,
	})
end

function CartMovementValidationMath.PromoteResult(
	result: Result,
	severity: Severity,
	reason: string
): Result
	assert(reason ~= "", "Movement validation promotion reason must not be empty")

	local reasons = table.clone(result.Reasons)

	table.insert(reasons, reason)

	local promotedSeverity = result.Severity

	if
		result.Severity ~= "Invalid"
		and SEVERITY_RANK[severity] > SEVERITY_RANK[result.Severity]
	then
		promotedSeverity = severity
	end

	return table.freeze({
		Severity = promotedSeverity,
		Reasons = freezeReasons(reasons),
		HasFinitePhysicalState = result.HasFinitePhysicalState,
		ElapsedTimeValid = result.ElapsedTimeValid,
		CanCorrect = result.CanCorrect and promotedSeverity ~= "Invalid",
		ForwardSpeed = result.ForwardSpeed,
		ReverseSpeed = result.ReverseSpeed,
		SignedForwardSpeed = result.SignedForwardSpeed,
		LateralSpeed = result.LateralSpeed,
		HorizontalSpeed = result.HorizontalSpeed,
		VerticalSpeed = result.VerticalSpeed,
		AngularSpeedDegrees = result.AngularSpeedDegrees,
		HorizontalDisplacement = result.HorizontalDisplacement,
		VerticalDisplacement = result.VerticalDisplacement,
		ObservedHorizontalSpeed = result.ObservedHorizontalSpeed,
		HorizontalAcceleration = result.HorizontalAcceleration,
	})
end

return CartMovementValidationMath
