--!strict

local AnalyticsEvents = {
	SessionStarted = "session_started",

	CartSpawned = "cart_spawned",
	CartDriverEntered = "cart_driver_entered",
	CartMovementStarted = "cart_movement_started",
	CartDriverExited = "cart_driver_exited",
	CartResetRequested = "cart_reset_requested",
	CartResetApproved = "cart_reset_approved",
	CartResetRejected = "cart_reset_rejected",
	CartResetCompleted = "cart_reset_completed",
	CartDespawned = "cart_despawned",
	CartMovementCorrected = "cart_movement_corrected",

	BrainrotBanked = "brainrot_banked",
	KeeperSaved = "keeper_saved",
}

return table.freeze(AnalyticsEvents)
