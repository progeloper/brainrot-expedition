--!strict

-- Phase 1R Development analytics tuning. These values define the smallest
-- server-observed movement signal needed to reject idle physics jitter; they
-- are not locked gameplay or movement-balance values.
local Development = table.freeze({
	MeaningfulMovementSpeed = 2.5,
	MovementConfirmationDuration = 0.3,
})

local CartAnalytics = {
	-- Analytics is observational only. Disabling it must not affect gameplay.
	Enabled = true,
	EventVersion = 1,
	Development = Development,
}

return table.freeze(CartAnalytics)
