--!strict

export type StabilityMode = "Free" | "Moderate" | "Strong" | "Severe"

export type BaseStabilityProfile = {
	Enabled: boolean,

	OrientationErrorDeadZoneDegrees: number,
	FreeRollAngleDegrees: number,
	FreePitchAngleDegrees: number,
	ModerateRollAngleDegrees: number,
	ModeratePitchAngleDegrees: number,
	StrongRollAngleDegrees: number,
	StrongPitchAngleDegrees: number,

	UprightStrength: number,
	RollCorrectionStrength: number,
	PitchCorrectionStrength: number,
	RollDamping: number,
	PitchDamping: number,
	MaxCorrectiveTorque: number,
	MaxCorrectiveAngularResponseDegreesPerSecond: number,
	ResponseSpeed: number,

	StationaryAssistanceMultiplier: number,
	DrivingAssistanceMultiplier: number,
	SevereTiltRecoveryMultiplier: number,

	ExtremeYawDamping: number,
	ExtremeYawThresholdDegreesPerSecond: number,
}

export type EffectiveStabilityProfile = {
	CartId: string,
	Enabled: boolean,

	OrientationErrorDeadZoneDegrees: number,
	FreeRollAngleDegrees: number,
	FreePitchAngleDegrees: number,
	ModerateRollAngleDegrees: number,
	ModeratePitchAngleDegrees: number,
	StrongRollAngleDegrees: number,
	StrongPitchAngleDegrees: number,

	UprightStrength: number,
	RollCorrectionStrength: number,
	PitchCorrectionStrength: number,
	RollDamping: number,
	PitchDamping: number,
	MaxCorrectiveTorque: number,
	MaxCorrectiveAngularResponseDegreesPerSecond: number,
	ResponseSpeed: number,

	StationaryAssistanceMultiplier: number,
	DrivingAssistanceMultiplier: number,
	SevereTiltRecoveryMultiplier: number,

	ExtremeYawDamping: number,
	ExtremeYawThresholdDegreesPerSecond: number,
}

export type OrientationError = {
	CorrectionAxis: Vector3,
	TiltAngle: number,
	RollAngle: number,
	PitchAngle: number,
}

export type AngularComponents = {
	Roll: number,
	Pitch: number,
	Yaw: number,
}

export type StabilityStepInput = {
	RootCFrame: CFrame,
	AngularVelocity: Vector3,
	AssemblyMass: number,
	DesiredUp: Vector3,
	IntendedHeading: Vector3,
	PreviousTorque: Vector3,
	PreviousHeading: Vector3?,
	AssistanceMultiplier: number,
	DeltaTime: number,
	Profile: EffectiveStabilityProfile,
}

export type StabilityStepResult = {
	Torque: Vector3,
	Heading: Vector3,
	RollAngle: number,
	PitchAngle: number,
	TiltAngle: number,
	RollAngularVelocity: number,
	PitchAngularVelocity: number,
	YawAngularVelocity: number,
	CorrectionStrength: number,
	SevereTilt: boolean,
	Mode: StabilityMode,
}

return nil
