--!strict

local CartReset = {
	HoldDuration = 1,
	RequestAttemptInterval = 5,
	SuccessfulResetCooldown = 30,
	SuspiciousRejectionThreshold = 3,
	SuspiciousRejectionWindow = 30,
}

return table.freeze(CartReset)
