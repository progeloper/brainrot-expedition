--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ids = require(ReplicatedStorage.Shared.Constants.Ids)

local Carts = {
	[Ids.Carts.ScrapChariot] = {
		Id = Ids.Carts.ScrapChariot,
		DisplayName = "Scrap Chariot",
		AssetName = "ScrapChariot",

		TeamSlots = 1,
		CargoSlots = 3,

		BaseSpeed = 42,
		Acceleration = 32,
		Braking = 44,
		TurnRate = 95,
		ReverseSpeedMultiplier = 0.45,

		TeamSpeedCap = 0.04,
		TeamUtilityCap = 0.08,
	},
}

return table.freeze(Carts)
