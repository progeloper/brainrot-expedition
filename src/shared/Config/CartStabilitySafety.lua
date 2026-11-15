--!strict

-- Hard physics-safety envelopes. These are not Scrap Chariot tuning values.
-- Cart-specific Development tuning belongs in Carts.lua and must remain inside
-- these limits.
local CartStabilitySafety = {
	MinimumOrientationErrorDeadZoneDegrees = 0.1,
	MaximumOrientationErrorDeadZoneDegrees = 10,
	MinimumFreeAngleDegrees = 0.25,
	MaximumFreeAngleDegrees = 30,
	MinimumModerateAngleDegrees = 1,
	MaximumModerateAngleDegrees = 90,
	MinimumStrongAngleDegrees = 2,
	MaximumStrongAngleDegrees = 175,

	MinimumUprightStrength = 0.05,
	MaximumUprightStrength = 4,
	MinimumAxisCorrectionStrength = 0.05,
	MaximumAxisCorrectionStrength = 4,
	MinimumAxisAngularDamping = 0.01,
	MaximumAngularDamping = 5,

	MinimumCorrectiveTorque = 1,
	MaximumCorrectiveTorque = 10000000,
	MinimumCorrectiveAngularResponseDegreesPerSecond = 1,
	MaximumCorrectiveAngularResponseDegreesPerSecond = 300,
	MinimumResponseSpeed = 1,
	MaximumResponseSpeed = 200,

	MinimumAssistanceMultiplier = 0.05,
	MaximumAssistanceMultiplier = 3,
	MinimumSevereTiltRecoveryMultiplier = 1,
	MaximumSevereTiltRecoveryMultiplier = 4,

	MinimumExtremeYawDamping = 0,
	MaximumExtremeYawDamping = 5,
	MinimumExtremeYawThresholdDegreesPerSecond = 30,
	MaximumExtremeYawThresholdDegreesPerSecond = 720,
}

return table.freeze(CartStabilitySafety)
