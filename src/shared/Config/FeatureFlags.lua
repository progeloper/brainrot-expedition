--!strict

export type FeatureFlags = {
	CartEnabled: boolean,
	CaptureEnabled: boolean,
	BankingEnabled: boolean,
	KeepersEnabled: boolean,
	EquippedTeamsEnabled: boolean,
	MutationsEnabled: boolean,
	GadgetsEnabled: boolean,
	TheftEnabled: boolean,
	WorldEventsEnabled: boolean,
	MonetisationEnabled: boolean,
}

local FeatureFlags: FeatureFlags = {
	CartEnabled = false,
	CaptureEnabled = false,
	BankingEnabled = false,
	KeepersEnabled = false,
	EquippedTeamsEnabled = false,
	MutationsEnabled = false,
	GadgetsEnabled = false,
	TheftEnabled = false,
	WorldEventsEnabled = false,
	MonetisationEnabled = false,
}

return table.freeze(FeatureFlags)
