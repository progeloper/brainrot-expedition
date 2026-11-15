--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

local PlayerDataConfig = {
	SchemaVersion = 2,
	-- Owner confirmed production has never been tested; read-only inspection
	-- found no production records. No historical ledger import is required.
	-- Deployment remains controlled separately from profile migration safety.
	Phase8MigrationReady = true,
	-- The approved banked departure/release matrix and confirmed relinquishment
	-- handoff are implemented. Keep the complete path in Development and Sandbox
	-- until the required save, mobile and populated-session gates are observed;
	-- production promotion remains a separate explicit release action.
	EnableBankedBasePersistence = Environment.MainGameplayEnabled or not Environment.IsProduction,
	-- Writer protocol3 fences pre-Phase13 writers (which accept only1/2).
	-- This is independent of SchemaVersion and CurrencyVersion.
	TransportVersion = 3,
	LegacyTransportVersions = table.freeze({ [1] = true, [2] = true }),
	LegacyTransportVersion = 1,
	StoreName = Environment.DataStorePrefix .. "_player_profiles_v1",
	StoreScope = nil,
	KeyPrefix = "player_",
	StartingBalance = 0,
	MaxBalance = 9007199254740991,
	LoadDeadlineSeconds = 30,
	AutosaveIntervalSeconds = 60,
	AutosaveStaggerSeconds = 10,
	LeaseDurationSeconds = 180,
	LeaseSafetyMarginSeconds = 15,
	RetryDelaysSeconds = { 1, 2, 4, 8 },
	AttemptsPerBatch = 5,
	RetryJitterSeconds = 0.25,
	FinalCloseDeadlineSeconds = 20,
	ShutdownBudgetSeconds = 25,
	ShutdownConcurrency = 8,
}

return table.freeze(PlayerDataConfig)
