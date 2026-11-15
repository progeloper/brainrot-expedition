--!strict

-- Phase 1T Development-only performance-zone metadata. The section identifier
-- is stable so load scenarios can resolve predefined spawn lanes without
-- accepting arbitrary world positions.
local CartGreyboxPerformanceIds = {
	TwelveCartLoadZone = "GBOX_PERF_12_CART",
}

return table.freeze(CartGreyboxPerformanceIds)
