--!strict

local AnalyticsEvents = {
	SessionStarted = "session_started",

	CartSpawned = "cart_spawned",
	CartReset = "cart_reset",
	CartDespawned = "cart_despawned",
	CartEntered = "cart_entered",
	CartExited = "cart_exited",

	CaptureAttempted = "capture_attempted",
	CaptureCompleted = "capture_completed",
	BrainrotBanked = "brainrot_banked",
	KeeperSaved = "keeper_saved",
}

return table.freeze(AnalyticsEvents)
