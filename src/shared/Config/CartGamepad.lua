--!strict

local Development = table.freeze({
	-- Existing repository tuning, centralised for the Phase 1P adapter.
	MovementStickDeadzone = 0.14,
	CameraStickDeadzone = 0.14,

	-- Phase 1P Development tuning: the workbook does not lock these values.
	TriggerDeadzone = 0.05,
	CameraRadiansPerSecond = math.pi,
})

local CartGamepad = {
	Development = Development,
}

return table.freeze(CartGamepad)
