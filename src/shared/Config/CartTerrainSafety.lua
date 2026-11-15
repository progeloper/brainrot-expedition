--!strict

-- Hard physics and performance safety envelopes. These are not Scrap Chariot
-- tuning values. Cart-specific Development tuning belongs in Carts.lua and
-- must remain inside these limits.
local CartTerrainSafety = {
	MinimumProbeOriginHeight = 0,
	MaximumProbeOriginHeight = 10,
	MinimumGroundDetectionDistance = 1,
	MaximumGroundDetectionDistance = 30,
	MinimumSupportGap = 0,
	MaximumSupportGap = 5,
	MinimumSupportPenetration = 0,
	MaximumSupportPenetration = 2,
	MinimumProbeFraction = 0,
	MaximumProbeFraction = 1,
	MinimumFullGroundedHitCount = 1,
	MaximumFullGroundedHitCount = 3,

	MinimumGroundedTransitionDelay = 0,
	MaximumGroundedTransitionDelay = 1,
	MinimumNormalResponseSpeed = 1,
	MaximumNormalResponseSpeed = 50,
	MinimumNormalChangeDegreesPerSecond = 15,
	MaximumNormalChangeDegreesPerSecond = 360,
	MinimumAirborneWorldUpResponseSpeed = 0.1,
	MaximumAirborneWorldUpResponseSpeed = 20,
	MinimumNormalOutlierAngleDegrees = 5,
	MaximumNormalOutlierAngleDegrees = 90,

	MinimumSlopeEffectStartDegrees = 0,
	MaximumSlopeEffectStartDegrees = 15,
	MinimumFullSlopeEffectDegrees = 5,
	MaximumFullSlopeEffectDegrees = 60,
	MinimumClimbAngleDegrees = 10,
	MaximumClimbAngleDegrees = 60,
	MinimumGroundAngleDegrees = 15,
	MaximumGroundAngleDegrees = 80,
	MinimumUphillAccelerationReduction = 0,
	MaximumUphillAccelerationReduction = 0.5,
	MinimumDownhillAcceleration = 0,
	MaximumDownhillAcceleration = 8,
	MinimumDownhillCoastReduction = 0,
	MaximumDownhillCoastReduction = 0.5,

	MinimumStabilityMultiplier = 0,
	MaximumStabilityMultiplier = 1,

	MinimumSampleRate = 2,
	MaximumSampleRate = 30,
	MinimumSettledSpeedThreshold = 0,
	MaximumSettledSpeedThreshold = 10,
}

return table.freeze(CartTerrainSafety)
