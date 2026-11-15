--!strict

-- Phase 1S Development-only route metadata. These identifiers are stable test
-- references; they are never player-facing gameplay identifiers.
local CartGreyboxSectionIds = {
	FlatAcceleration = "GBOX_FLAT_ACCEL",
	FlatBraking = "GBOX_FLAT_BRAKE",
	Reverse = "GBOX_REVERSE",
	SteeringLowSpeed = "GBOX_STEER_LOW",
	SteeringModerateSpeed = "GBOX_STEER_MODERATE",
	SteeringRapidChange = "GBOX_STEER_RAPID",
	GentleUphill = "GBOX_SLOPE_UP",
	GentleDownhill = "GBOX_SLOPE_DOWN",
	SideSlope = "GBOX_SIDE_SLOPE",
	HillCrest = "GBOX_CREST",
	SmallBumps = "GBOX_BUMPS",
	NarrowPath = "GBOX_NARROW_PATH",
	CameraWall = "GBOX_CAMERA_WALL",
	CameraCorner = "GBOX_CAMERA_CORNER",
	ControlledCollision = "GBOX_COLLISION",
	TiltRecovery = "GBOX_TILT_RECOVERY",
	ControlledStuck = "GBOX_STUCK",
	CartReset = "GBOX_RESET",
	CartLifecycle = "GBOX_LIFECYCLE",
	MultiplayerOpenArea = "GBOX_MULTIPLAYER",
}

return table.freeze(CartGreyboxSectionIds)
