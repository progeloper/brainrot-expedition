--!strict

export type GroundState = "Grounded" | "Partial" | "Airborne"

export type TerrainSnapshot = {
	State: GroundState,
	Grounded: boolean,
	FullyGrounded: boolean,
	Driveable: boolean,
	RawNormal: Vector3,
	DesiredUp: Vector3,
	HitCount: number,
	GroundDistance: number,
	SlopeAngleDegrees: number,
	Confidence: number,
	TerrainResponseStrength: number,
	StabilityMultiplier: number,
	SampledAt: number,
	Revision: number,
	SampleCount: number,
}

export type BaseTerrainProfile = {
	Enabled: boolean,

	ProbeOriginHeight: number,
	GroundDetectionDistance: number,
	MaximumSupportGap: number,
	MaximumSupportPenetration: number,
	LateralProbeFraction: number,
	ForwardProbeFraction: number,
	FullGroundedHitCount: number,

	GroundedReacquireDelay: number,
	AirborneDelay: number,
	NormalResponseSpeed: number,
	MaximumNormalChangeDegreesPerSecond: number,
	AirborneWorldUpResponseSpeed: number,
	NormalOutlierAngleDegrees: number,

	SlopeEffectStartDegrees: number,
	FullSlopeEffectDegrees: number,
	MaximumClimbAngleDegrees: number,
	MaximumGroundAngleDegrees: number,
	MaximumUphillAccelerationReduction: number,
	MaximumDownhillAcceleration: number,
	MaximumDownhillCoastReduction: number,

	PartialSupportStabilityMultiplier: number,
	AirborneStabilityMultiplier: number,

	DrivenSampleRate: number,
	ServerMovingSampleRate: number,
	ServerSettledSampleRate: number,
	ServerSettledSpeedThreshold: number,
}

export type EffectiveTerrainProfile = {
	CartId: string,
	Enabled: boolean,

	ProbeOriginHeight: number,
	GroundDetectionDistance: number,
	MaximumSupportGap: number,
	MaximumSupportPenetration: number,
	LateralProbeFraction: number,
	ForwardProbeFraction: number,
	FullGroundedHitCount: number,

	GroundedReacquireDelay: number,
	AirborneDelay: number,
	NormalResponseSpeed: number,
	MaximumNormalChangeDegreesPerSecond: number,
	AirborneWorldUpResponseSpeed: number,
	NormalOutlierAngleDegrees: number,

	SlopeEffectStartDegrees: number,
	FullSlopeEffectDegrees: number,
	MaximumClimbAngleDegrees: number,
	MaximumGroundAngleDegrees: number,
	MaximumUphillAccelerationReduction: number,
	MaximumDownhillAcceleration: number,
	MaximumDownhillCoastReduction: number,

	PartialSupportStabilityMultiplier: number,
	AirborneStabilityMultiplier: number,

	DrivenSampleRate: number,
	ServerMovingSampleRate: number,
	ServerSettledSampleRate: number,
	ServerSettledSpeedThreshold: number,
}

return nil
