--!strict
local Phase10 = require(script.Parent.Phase10)

-- Server-owned Development recovery. Manual reset remains disabled in all environments.
return table.freeze({
	Enabled = Phase10.Enabled,
	SampleInterval = Phase10.SampleSeconds,
	BlockedIntentSeconds = Phase10.StuckSeconds,
	MeaningfulProgressStuds = Phase10.ProgressStuds,
	RetryInterval = Phase10.RetrySeconds,
	SafetySkin = Phase10.SafetySkin,
	GroundProbeDistance = 48,
	SupportContactGap = 0.45,
	MaximumSettleSeconds = 1.5,
	MaximumWorldQueriesPerSecond = 60,
	MaximumTerrainQueriesPerSecond = 60,
})
