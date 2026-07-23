--!strict

local RemoteNames = {
	CaptureRequest = "CaptureRequest",
	GadgetRequest = "GadgetRequest",
	BankRequest = "BankRequest",
	KeeperDecision = "KeeperDecision",
	TeamEquipRequest = "TeamEquipRequest",
	CartResetRequest = "CartResetRequest",
	PurchasePromptRequest = "PurchasePromptRequest",
	TheftRequest = "TheftRequest",

	ClientEvent = "ClientEvent",
	StateSync = "StateSync",
}

return table.freeze(RemoteNames)
