--!strict

-- Phase 1Q Development safety tuning. None of these values are locked design
-- values or cart-balance targets; Studio validation may adjust them without
-- changing the approved Phase 1D movement profile.
local Development = table.freeze({
	SampleInterval = 0.15,

	ForwardSpeedMultiplier = 1.35,
	ForwardSpeedAdditive = 10,
	ReverseSpeedMultiplier = 2.5,
	ReverseSpeedAdditive = 12,
	LateralSpeedMultiplier = 1.5,
	LateralSpeedAdditive = 14,
	OverallSpeedMultiplier = 1.75,
	OverallSpeedAdditive = 18,
	CorrectiveHorizontalSpeedMultiplier = 2.25,
	CorrectiveHorizontalSpeedAdditive = 24,
	SevereHorizontalSpeedMultiplier = 3,
	SevereHorizontalSpeedAdditive = 30,

	DisplacementMultiplier = 1.75,
	DisplacementAdditive = 8,
	CorrectiveDisplacementMultiplier = 2.75,
	CorrectiveDisplacementAdditive = 18,
	SevereDisplacementMultiplier = 4,
	SevereDisplacementAdditive = 30,

	AccelerationMultiplier = 4,
	AccelerationAdditive = 40,
	UpwardSpeedObservation = 90,
	DownwardSpeedObservation = 240,
	VerticalDisplacementAdditive = 8,
	AngularSpeedMultiplier = 2.5,
	AngularSpeedAdditiveDegrees = 120,

	OwnershipTransitionGrace = 0.35,
	NoDriverAccelerationTolerance = 100,

	ObservationScoreIncrement = 1,
	CorrectiveScoreIncrement = 2,
	SevereScoreIncrement = 8,
	ValidSampleDecay = 1,
	CorrectiveScoreThreshold = 4,
	SevereScoreThreshold = 8,
	MaximumViolationScore = 12,
	CorrectionCooldown = 1.5,
	RepeatedWarningThreshold = 3,
	WarningWindow = 30,

	DiagnosticsEnabled = false,
})

-- Hard system-safety ceilings. These are deliberately above every currently
-- approved Phase 1D movement value and are not normal handling limits.
local SystemSafety = table.freeze({
	MaximumHorizontalSpeed = 220,
	MaximumUpwardSpeed = 180,
	MaximumDownwardSpeed = 350,
	MaximumAngularSpeedDegrees = 1080,
	MaximumVerticalDisplacementAdditive = 25,
})

local CartMovementValidation = {
	-- System-level service activation; this is not a gameplay balance value.
	Enabled = true,
	Development = Development,
	SystemSafety = SystemSafety,
}

return table.freeze(CartMovementValidation)
