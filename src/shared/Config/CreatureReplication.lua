--!strict
-- The legacy switch is Studio-only and read by the server for controlled A/B QA.
return table.freeze({
	Enabled = true,
	ProtocolVersion = 1,
	PoseIntervalSeconds = 0.1,
	MaxEntities = 1024,
	MaxPacketEntities = 128,
	MaxCachedTemplates = 64,
	MaxTombstones = 2048,
	MaxSupplyTemplates = 12,
	SupplyLifetimeSeconds = 15,
	TemplateRequestIntervalSeconds = 0.1,
	ContextRequestIntervalSeconds = 1,
	InterpolationSeconds = 0.1,
	SupplyName = "Phase13CreatureSupply",
	RemoteName = "Phase13Creatures",
})
