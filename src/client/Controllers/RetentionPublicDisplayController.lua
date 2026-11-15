--!strict
-- Retired public collection box. Personal Expedition/Collection remains owned by RetentionController.
return table.freeze({
	Start = function()
		return false
	end,
	Stop = function() end,
	GetDiagnostics = function()
		return {
			started = false,
			displays = 0,
			connections = 0,
			schedulerHz = 0,
			inspectOpen = false,
		}
	end,
})
