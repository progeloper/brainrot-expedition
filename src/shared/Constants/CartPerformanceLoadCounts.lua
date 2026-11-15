--!strict

-- Stable Phase 1T load counts. These are Development test-process values,
-- not Production cart limits or gameplay configuration.
local Ordered = table.freeze({ 1, 4, 8, 12 })

local CartPerformanceLoadCounts = {
	Baseline = 1,
	IntermediateFour = 4,
	IntermediateEight = 8,
	Target = 12,
	Ordered = Ordered,
}

return table.freeze(CartPerformanceLoadCounts)
