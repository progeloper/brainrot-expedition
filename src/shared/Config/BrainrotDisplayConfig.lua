--!strict

local BrainrotDisplayConfig = {
	CollectionTag = "BrainrotDisplay",
	Attributes = table.freeze({
		BrainrotId = "BrainrotId",
		DisplayState = "BrainrotDisplayState",
		CarrierUserId = "CarrierUserId",
		MutationId = "BrainrotMutationId",
		CamouflageSnapshot = "BrainrotCamouflageSnapshot",
		DecoySplitSnapshot = "BrainrotDecoySplitSnapshot",
	}),
	States = table.freeze({
		Awake = "Awake",
		Sleeping = "Sleeping",
		Carried = "Carried",
		Cart = "Cart",
		Deposited = "Deposited",
	}),
	Presentation = table.freeze({
		Awake = table.freeze({ Size = UDim2.fromScale(4.2, 1.55), MaxDistance = 55 }),
		Sleeping = table.freeze({ Size = UDim2.fromScale(4.2, 1.82), MaxDistance = 55 }),
		Carried = table.freeze({ Size = UDim2.fromScale(3.6, 0.95), MaxDistance = 20 }),
		Cart = table.freeze({ Size = UDim2.fromScale(3.8, 1.35), MaxDistance = 26 }),
		Deposited = table.freeze({
			Size = UDim2.fromScale(4.2 * 0.7, 1.55 * 0.7),
			MaxDistance = 35,
		}),
	}),
	Billboard = table.freeze({
		VerticalOffset = 1.25,
	}),
	Layout = table.freeze({
		BadgeHeightScale = 0.20,
		NameHeightScale = 0.40,
		RankHeightScale = 0.25,
		IncomeHeightScale = 0.35,
		LinePaddingPixels = 2,
		BadgePaddingPixels = 6,
		CarriedNameHeightScale = 0.60,
		CarriedRankHeightScale = 0.40,
	}),
	Typography = table.freeze({
		Font = Enum.Font.FredokaOne,
		NameMinTextSize = 22,
		NameMaxTextSize = 38,
		RankMinTextSize = 16,
		RankMaxTextSize = 26,
		IncomeMinTextSize = 20,
		IncomeMaxTextSize = 34,
		NameStrokeThickness = 3,
		RankStrokeThickness = 2.5,
		IncomeStrokeThickness = 3,
	}),
	Colors = table.freeze({
		Name = Color3.fromRGB(255, 255, 255),
		Income = Color3.fromRGB(110, 255, 84),
		TextStroke = Color3.fromRGB(8, 8, 10),
		Rank = table.freeze({
			common = Color3.fromRGB(242, 242, 242),
			uncommon = Color3.fromRGB(92, 220, 122),
			rare = Color3.fromRGB(77, 163, 255),
			epic = Color3.fromRGB(182, 92, 255),
			legendary = Color3.fromRGB(255, 216, 77),
			mythic = Color3.fromRGB(255, 106, 61),
			secret = Color3.fromRGB(255, 51, 79),
		}),
	}),
	Scale = table.freeze({
		Normal = 1,
		Focused = 1.06,
	}),
	FocusTween = table.freeze({
		InDuration = 0.14,
		OutDuration = 0.10,
		StrokeIncrease = 0.5,
	}),
	SleepBadge = table.freeze({
		Text = "ASLEEP",
		Fill = Color3.fromRGB(54, 200, 255),
		TextColor = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		HeightPixels = 28,
		HorizontalPaddingPixels = 8,
		VerticalPaddingPixels = 3,
		CornerRadiusPixels = 6,
		StrokeThickness = 2,
		StrokeColor = Color3.fromRGB(0, 0, 0),
	}),
	SleepPop = table.freeze({
		PeakScale = 1.08,
		OutDuration = 0.16,
		ReturnDuration = 0.12,
	}),
	MutationBadges = table.freeze({}),
}

return table.freeze(BrainrotDisplayConfig)
