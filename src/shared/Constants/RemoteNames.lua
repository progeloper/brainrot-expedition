--!strict

local RemoteNames = {
	VFXSettingsRequest = "VFXSettingsRequest",
	WorldProgressionRequest = "WorldProgressionRequest",
	WorldProgressionUpdate = "WorldProgressionUpdate",
	SleepRequest = "SleepRequest",
	DropCarriedRequest = "DropCarriedRequest",
	PlaceCarriedRequest = "PlaceCarriedRequest",
	LoadCarriedRequest = "LoadCarriedRequest",
	PickupCargoRequest = "PickupCargoRequest",
	ReplaceCargoRequest = "ReplaceCargoRequest",
	OpenBrainrotSaleDialog = "OpenBrainrotSaleDialog",
	ConfirmBrainrotSale = "ConfirmBrainrotSale",
	CancelBrainrotSale = "CancelBrainrotSale",
	GadgetRequest = "GadgetRequest",
	BankRequest = "BankRequest",
	KeeperDecision = "KeeperDecision",
	TeamEquipRequest = "TeamEquipRequest",
	CartResetRequest = "CartResetRequest",
	CartDriveIntent = "CartDriveIntent",
	CartLongitudinalIntentRequest = "CartLongitudinalIntentRequest",
	PurchasePromptRequest = "PurchasePromptRequest",
	OpenCartUpgradeShop = "OpenCartUpgradeShop",
	CartUpgradeShopRequest = "CartUpgradeShopRequest",
	CloseCartUpgradeShop = "CloseCartUpgradeShop",
	CartUpgradeShopUpdate = "CartUpgradeShopUpdate",
	TheftRequest = "TheftRequest",
	Phase12Event = "Phase12Event",
	Phase12ProgressRequest = "Phase12ProgressRequest",
	-- TerrainRedesign Storm (server -> client): push hint and world unlock announcements.
	StormPush = "StormPush",
	WorldAnnouncement = "WorldAnnouncement",
	-- Villager guards (server -> chased player + passengers): chase/ring/escape events.
	VillagerGuardEvent = "VillagerGuardEvent",
	-- Game audio (server -> all clients): presentation-only cues, e.g. a Legendary+ chase starting.
	AudioCue = "AudioCue",
	-- Drive-and-Hunt: one switch request (client -> server) and one effects event (server -> client).
	DriveAndHuntRequest = "DriveAndHuntRequest",
	DriveAndHuntFx = "DriveAndHuntFx",

	ClientEvent = "ClientEvent",
	StateSync = "StateSync",
}

return table.freeze(RemoteNames)
