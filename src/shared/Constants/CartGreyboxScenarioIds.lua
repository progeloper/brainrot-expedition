--!strict

-- Stable Phase 1S validation scenario identifiers. These are Development-only
-- test metadata and are never used as player-facing gameplay identifiers.
local CartGreyboxScenarioIds = {
	SpawnReadiness = "GBOX_SCENARIO_SPAWN_READINESS",
	DriverAuthority = "GBOX_SCENARIO_DRIVER_AUTHORITY",
	FlatAcceleration = "GBOX_SCENARIO_FLAT_ACCELERATION",
	Coasting = "GBOX_SCENARIO_COASTING",
	BrakingStopping = "GBOX_SCENARIO_BRAKING_STOPPING",
	ReverseEngagement = "GBOX_SCENARIO_REVERSE_ENGAGEMENT",
	Steering = "GBOX_SCENARIO_STEERING",
	Stability = "GBOX_SCENARIO_STABILITY",
	Terrain = "GBOX_SCENARIO_TERRAIN",
	Collision = "GBOX_SCENARIO_COLLISION",
	CameraBase = "GBOX_SCENARIO_CAMERA_BASE",
	CameraObstruction = "GBOX_SCENARIO_CAMERA_OBSTRUCTION",
	PCInput = "GBOX_SCENARIO_PC_INPUT",
	TouchInput = "GBOX_SCENARIO_TOUCH_INPUT",
	GamepadInput = "GBOX_SCENARIO_GAMEPAD_INPUT",
	ResetSuccess = "GBOX_SCENARIO_RESET_SUCCESS",
	ResetSecurity = "GBOX_SCENARIO_RESET_SECURITY",
	MovementValidation = "GBOX_SCENARIO_MOVEMENT_VALIDATION",
	AnalyticsSequence = "GBOX_SCENARIO_ANALYTICS_SEQUENCE",
	CartReplacement = "GBOX_SCENARIO_CART_REPLACEMENT",
	CartDestruction = "GBOX_SCENARIO_CART_DESTRUCTION",
	CharacterLifecycle = "GBOX_SCENARIO_CHARACTER_LIFECYCLE",
	FocusInputContext = "GBOX_SCENARIO_FOCUS_INPUT_CONTEXT",
	MultiplayerIsolation = "GBOX_SCENARIO_MULTIPLAYER_ISOLATION",
	LifecycleEndurance = "GBOX_SCENARIO_LIFECYCLE_ENDURANCE",
}

return table.freeze(CartGreyboxScenarioIds)
