--!strict

local Development = table.freeze({
	-- Development tuning: the workbook does not lock these values.
	MinimumPitch = math.rad(-20),
	MaximumPitch = math.rad(35),
	DefaultPitch = 0,
	PositionResponsiveness = 10,
	RotationResponsiveness = 12,
	MouseRadiansPerPixel = 0.003,
	ManualInputThreshold = 0.001,
})

local Obstruction = table.freeze({
	Enabled = true,

	-- Phase 1N Development tuning: the workbook does not lock these values.
	QueryRadius = 0.5,
	SurfaceBuffer = 0.25,
	MinimumDistance = 6,
	OutwardRecoverySpeed = 1/0.15,
	DistanceTolerance = 0.05,
})

local CartCamera = {
	-- Locked workbook values.
	Distance = 28,
	HeightOffset = 9,
	AutoRecenterDelay = 1.25,
	AutoRecenterSpeed = 3.5,
	PCSensitivity = 0.8,
	GamepadSensitivity = 0.65,

	Development = Development,
	Obstruction = Obstruction,

	-- Existing later-platform values remain unused by Phase 1P.
	MobileDistance = 30,
	MobileAutoRecenterDelay = 1,
	MobileAutoRecenterSpeed = 4,
	TouchSensitivity = 0.006,
}

return table.freeze(CartCamera)
