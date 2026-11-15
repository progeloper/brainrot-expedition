--!strict

-- Mounted hunting view only. Cruise driving keeps CartCamera's locked tuning.
return table.freeze({
	Distance = 11,
	ShoulderOffset = 2.25,
	HeightOffset = 2.5,
	MinimumPitch = math.rad(-35),
	MaximumPitch = math.rad(65),
	MouseRadiansPerPixel = 0.0024,
	GamepadRadiansPerSecond = 1.8,
	PositionResponsiveness = 20,
	RotationResponsiveness = 24,
	FocusDistance = 128,
})
