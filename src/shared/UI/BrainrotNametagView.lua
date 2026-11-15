--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local AppearanceCatalog = require(ReplicatedStorage.Shared.Config.BrainrotAppearanceCatalog)
local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

export type DisplayData = {
	displayName: string,
	rarity: string,
	cashPerSecond: number,
	effectiveCashPerSecond: number?,
}

export type MutationDisplayData = {
	displayName: string,
	backgroundColor: Color3,
	textColor: Color3?,
}

export type View = {
	Gui: BillboardGui,
	Root: Frame,
	Scale: UIScale,
	BadgeRow: Frame,
	MutationBadge: Frame,
	MutationLabel: TextLabel,
	StateBadge: Frame,
	StateLabel: TextLabel,
	MainStack: Frame,
	NameLabel: TextLabel,
	RankLabel: TextLabel,
	IncomeLabel: TextLabel,
	DisplayState: string,
	CarrierUserId: number?,
	PopGeneration: number,
	Focused: boolean,
	HealthArea: Frame,
	HealthBar: Frame,
	HealthFill: Frame,
	HealthLabel: TextLabel,
	HealthTween: Tween?,
	HealthTarget: number?,
	FocusTween: Tween?,
}

local Exact = require(ReplicatedStorage.Shared.Config.PlaytestExact).Hud
local BrainrotNametagView = {}
local log = Logger.new("BrainrotNametagView")
local warnedUnknownRanks: { [string]: boolean } = {}

local function addGlyphStroke(label: TextLabel, thickness: number, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "UIStroke"
	stroke.Color = color or BrainrotDisplayConfig.Colors.TextStroke
	stroke.Thickness = thickness
	stroke.Transparency = 0
	stroke.Parent = label
end

local function addSizeConstraint(label: TextLabel, minimum: number, maximum: number)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.Name = "UITextSizeConstraint"
	constraint.MinTextSize = minimum
	constraint.MaxTextSize = maximum
	constraint.Parent = label
end

local function createLabel(
	name: string,
	heightScale: number,
	color: Color3,
	minimumSize: number,
	maximumSize: number,
	strokeThickness: number,
	wrapped: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromScale(1, heightScale)
	label.BackgroundTransparency = 1
	label.Font = BrainrotDisplayConfig.Typography.Font
	label.RichText = false
	label.Text = ""
	label.TextColor3 = color
	label.TextWrapped = wrapped
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	addSizeConstraint(label, minimumSize, maximumSize)
	addGlyphStroke(label, strokeThickness)
	return label
end

local function createBadge(name: string, parent: Frame): (Frame, TextLabel)
	local badge = Instance.new("Frame")
	badge.Name = name
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.Size = UDim2.fromOffset(0, BrainrotDisplayConfig.SleepBadge.HeightPixels)
	badge.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
	badge.BackgroundTransparency = 0.15
	badge.Visible = false
	badge.Parent = parent

	local corner = Instance.new("UICorner")
	corner.Name = "UICorner"
	corner.CornerRadius = UDim.new(0, BrainrotDisplayConfig.SleepBadge.CornerRadiusPixels)
	corner.Parent = badge

	local border = Instance.new("UIStroke")
	border.Name = "UIStroke"
	border.Color = BrainrotDisplayConfig.SleepBadge.StrokeColor
	border.Thickness = BrainrotDisplayConfig.SleepBadge.StrokeThickness
	border.Transparency = 0
	border.Parent = badge

	local padding = Instance.new("UIPadding")
	padding.Name = "UIPadding"
	padding.PaddingLeft = UDim.new(0, BrainrotDisplayConfig.SleepBadge.HorizontalPaddingPixels)
	padding.PaddingRight = UDim.new(0, BrainrotDisplayConfig.SleepBadge.HorizontalPaddingPixels)
	padding.PaddingTop = UDim.new(0, BrainrotDisplayConfig.SleepBadge.VerticalPaddingPixels)
	padding.PaddingBottom = UDim.new(0, BrainrotDisplayConfig.SleepBadge.VerticalPaddingPixels)
	padding.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.BackgroundTransparency = 1
	label.Font = BrainrotDisplayConfig.Typography.Font
	label.RichText = false
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = false
	label.TextSize = BrainrotDisplayConfig.SleepBadge.TextSize
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = badge
	addGlyphStroke(
		label,
		BrainrotDisplayConfig.SleepBadge.StrokeThickness,
		BrainrotDisplayConfig.SleepBadge.StrokeColor
	)

	return badge, label
end

local function plateUnit()
	local player = game:GetService("Players").LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("PlaytestExactHud")
	local safe = hud and hud:FindFirstChild("SafeArea")
	if not safe then
		return nil
	end
	return math.clamp(
		math.min(safe.AbsoluteSize.X / Exact.ReferenceWidth, safe.AbsoluteSize.Y / Exact.ReferenceHeight),
		Exact.MinimumScale,
		Exact.MaximumScale
	)
end
local function playSleepPop(view: View)
	view.Scale.Scale = 1
end
local function updateBadgeLayout(view: View)
	local u = plateUnit()
	if not u then
		view.Gui.Enabled = false
		return
	end
	view.Gui.Size = UDim2.fromOffset(Exact.NameWidth * u, Exact.NameHeight * u)
	view.Gui.AlwaysOnTop = false
	view.Scale.Scale = 1
	view.BadgeRow.Visible = false
	view.MutationBadge.Visible = false
	view.StateBadge.Visible = false
	view.IncomeLabel.Visible = false
	view.MainStack.Position = UDim2.fromScale(0, 0)
	view.MainStack.Size = UDim2.fromScale(1, 1)
	local layout = view.MainStack:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout:Destroy()
	end
	for _, label in ipairs({ view.NameLabel, view.RankLabel }) do
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			limit:Destroy()
		end
		label.TextScaled = false
		label.RichText = false
		label.TextStrokeTransparency = 1
		for _, stroke in label:GetChildren() do
			if stroke:IsA("UIStroke") then
				stroke:Destroy()
			end
		end
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextColor3 = if label == view.NameLabel then Exact.Text else label.TextColor3
		label.Size = UDim2.fromScale(1, 0.5)
	end
	view.NameLabel.Position = UDim2.fromScale(0, 0)
	view.NameLabel.TextSize = Exact.NameText * u
	view.RankLabel.Position = UDim2.fromScale(0, 0.5)
	view.RankLabel.TextSize = Exact.RarityText * u
	view.HealthArea.Parent = view.Root
	view.HealthArea.Position = UDim2.fromScale(0, 0.5)
	view.HealthArea.Size = UDim2.fromScale(1, 0.5)
	view.HealthLabel.TextSize = Exact.RarityText * u
	view.HealthLabel.TextScaled = false
	view.HealthLabel.Size = UDim2.fromScale(1, 1)
	view.HealthLabel.TextTruncate = Enum.TextTruncate.AtEnd
	view.RankLabel.Visible = not view.HealthArea.Visible
end

function BrainrotNametagView.create(
	playerGui: PlayerGui,
	model: Model,
	displayPart: BasePart,
	displayData: DisplayData,
	displayState: string
): View
	local gui = Instance.new("BillboardGui")
	gui.Name = "BrainrotNametag"
	gui.Adornee = displayPart
	local presentation = BrainrotDisplayConfig.Presentation[displayState] or BrainrotDisplayConfig.Presentation.Awake
	gui.Size = presentation.Size
	local measurements = require(ReplicatedStorage.Shared.Config.PlaytestMeasurements)
	local metadata = require(game:GetService("ReplicatedStorage").Shared.Utility.VoxelCreatureRegistry).ModelMeasurement(model, measurements.Species[model:GetAttribute("BrainrotId")])
	if metadata then
		local worldTop = model:GetPivot():PointToWorldSpace(metadata.normalizedTop)
		gui.StudsOffsetWorldSpace = worldTop - displayPart.Position + Vector3.yAxis * Exact.NameTop
		gui:SetAttribute("BodyTopMeasurementStatus", "AUTHORED_NEUTRAL_BODY")
	end

	gui.MaxDistance = presentation.MaxDistance
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.ClipsDescendants = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ClipsDescendants = false
	root.Parent = gui

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "UIScale"
	uiScale.Scale = BrainrotDisplayConfig.Scale.Normal
	uiScale.Parent = root

	local badgeRow = Instance.new("Frame")
	badgeRow.Name = "BadgeRow"
	badgeRow.Size = UDim2.fromScale(1, 0)
	badgeRow.BackgroundTransparency = 1
	badgeRow.Visible = false
	badgeRow.Parent = root

	local badgeLayout = Instance.new("UIListLayout")
	badgeLayout.Name = "UIListLayout"
	badgeLayout.FillDirection = Enum.FillDirection.Horizontal
	badgeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	badgeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	badgeLayout.Padding = UDim.new(0, BrainrotDisplayConfig.Layout.BadgePaddingPixels)
	badgeLayout.Parent = badgeRow

	local mutationBadge, mutationLabel = createBadge("MutationBadge", badgeRow)
	mutationBadge.LayoutOrder = 1
	local stateBadge, stateLabel = createBadge("StateBadge", badgeRow)
	stateBadge.LayoutOrder = 2

	local mainStack = Instance.new("Frame")
	mainStack.Name = "MainStack"
	mainStack.Position = UDim2.fromScale(0, 0)
	mainStack.Size = UDim2.fromScale(1, 1)
	mainStack.BackgroundTransparency = 1
	mainStack.Parent = root

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.Name = "UIListLayout"
	stackLayout.FillDirection = Enum.FillDirection.Vertical
	stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	stackLayout.Padding = UDim.new(0, BrainrotDisplayConfig.Layout.LinePaddingPixels)
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Parent = mainStack

	local nameLabel = createLabel(
		"NameLabel",
		BrainrotDisplayConfig.Layout.NameHeightScale,
		BrainrotDisplayConfig.Colors.Name,
		BrainrotDisplayConfig.Typography.NameMinTextSize,
		BrainrotDisplayConfig.Typography.NameMaxTextSize,
		BrainrotDisplayConfig.Typography.NameStrokeThickness,
		true
	)
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = mainStack

	local rankLabel = createLabel(
		"RankLabel",
		BrainrotDisplayConfig.Layout.RankHeightScale,
		Color3.fromRGB(255, 255, 255),
		BrainrotDisplayConfig.Typography.RankMinTextSize,
		BrainrotDisplayConfig.Typography.RankMaxTextSize,
		BrainrotDisplayConfig.Typography.RankStrokeThickness,
		false
	)
	rankLabel.LayoutOrder = 2
	rankLabel.Parent = mainStack

	local incomeLabel = createLabel(
		"IncomeLabel",
		BrainrotDisplayConfig.Layout.IncomeHeightScale,
		BrainrotDisplayConfig.Colors.Income,
		BrainrotDisplayConfig.Typography.IncomeMinTextSize,
		BrainrotDisplayConfig.Typography.IncomeMaxTextSize,
		BrainrotDisplayConfig.Typography.IncomeStrokeThickness,
		false
	)
	incomeLabel.LayoutOrder = 4
	incomeLabel.Parent = mainStack

	local healthArea = Instance.new("Frame")
	healthArea.Name = "CombatHealth"
	healthArea.Size = UDim2.fromOffset(92, 30)
	healthArea.BackgroundTransparency = 1
	healthArea.LayoutOrder = 3
	healthArea.Visible = false
	healthArea.Parent = mainStack
	local healthBar = Instance.new("Frame")
	healthBar.Name = "HP"
	healthBar.AnchorPoint = Vector2.new(0.5, 0)
	healthBar.Position = UDim2.fromScale(0.5, 0)
	healthBar.Size = UDim2.fromOffset(Phase12.HpUi.WidthPixels, Phase12.HpUi.HeightPixels)
	healthBar.BorderSizePixel = Phase12.HpUi.BorderPixels
	healthBar.BorderColor3 = Color3.fromRGB(12, 12, 18)
	healthBar.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	healthBar.ClipsDescendants = true
	healthBar.Parent = healthArea
	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BorderSizePixel = 0
	healthFill.BackgroundColor3 = Color3.fromRGB(90, 235, 100)
	healthFill.Parent = healthBar
	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "HealthText"
	healthLabel.Position = UDim2.fromOffset(0, 8)
	healthLabel.Size = UDim2.new(1, 0, 0, 20)
	healthLabel.BackgroundTransparency = 1
	healthLabel.Font = BrainrotDisplayConfig.Typography.Font
	healthLabel.TextSize = 14
	healthLabel.TextColor3 = Color3.new(1, 1, 1)
	healthLabel.Text = ""
	healthLabel.Parent = healthArea
	addGlyphStroke(healthLabel, 1)
	local view: View = {
		Gui = gui,
		HealthArea = healthArea,
		HealthBar = healthBar,
		HealthFill = healthFill,
		HealthLabel = healthLabel,
		HealthTween = nil,
		HealthTarget = nil,
		Root = root,
		Scale = uiScale,
		BadgeRow = badgeRow,
		MutationBadge = mutationBadge,
		MutationLabel = mutationLabel,
		StateBadge = stateBadge,
		StateLabel = stateLabel,
		MainStack = mainStack,
		NameLabel = nameLabel,
		RankLabel = rankLabel,
		IncomeLabel = incomeLabel,
		DisplayState = displayState,
		CarrierUserId = nil,
		PopGeneration = 0,
		Focused = false,
		FocusTween = nil,
	}

	BrainrotNametagView.updateData(view, displayData)
	BrainrotNametagView.updateState(view, displayState, nil)
	BrainrotNametagView.setMutation(view, nil)
	gui.Parent = playerGui
	return view
end

function BrainrotNametagView.updateData(view: View, displayData: DisplayData)
	view.NameLabel.Text = displayData.displayName
	view.RankLabel.Text = string.upper(displayData.rarity)
	local displayedRate = displayData.effectiveCashPerSecond or displayData.cashPerSecond
	view.IncomeLabel.Text = CurrencyFormatter.FormatCompactCash(displayedRate) .. "/s"

	local rankKey = string.lower(displayData.rarity)
	local rankColor = BrainrotDisplayConfig.Colors.Rank[rankKey]
	if AppearanceCatalog.Rarities[displayData.rarity] then
		rankColor = AppearanceCatalog.Rarities[displayData.rarity].primary
	end
	if rankColor == nil then
		rankColor = Color3.fromRGB(255, 255, 255)
		if not warnedUnknownRanks[rankKey] then
			warnedUnknownRanks[rankKey] = true
			log:Warn("Unknown brainrot rank color key: %s", displayData.rarity)
		end
	end
	view.RankLabel.TextColor3 = rankColor
	local rankStroke = view.RankLabel:FindFirstChildOfClass("UIStroke")
	if rankStroke then
		rankStroke.Color = if displayData.rarity == "Secret"
			then Color3.fromHex("F6F3FF")
			else BrainrotDisplayConfig.Colors.TextStroke
	end
end

function BrainrotNametagView.updateState(view: View, displayState: string, carrierUserId: number?)
	local previousState = view.DisplayState
	local stateChanged = previousState ~= displayState
	view.DisplayState = displayState
	view.CarrierUserId = carrierUserId
	-- Wild HP and sleep deadlines have no meaning for carried, cargo or banked views.
	-- Clear them here because those states no longer belong to the health refresh set.
	if displayState ~= BrainrotDisplayConfig.States.Awake and displayState ~= BrainrotDisplayConfig.States.Sleeping then
		BrainrotNametagView.updateCombat(view, nil, false)
	end
	if stateChanged then
		view.PopGeneration += 1
	end
	if displayState ~= BrainrotDisplayConfig.States.Awake and view.Focused then
		BrainrotNametagView.setFocused(view, false)
	end

	local presentation = BrainrotDisplayConfig.Presentation[displayState] or BrainrotDisplayConfig.Presentation.Awake
	view.Gui.Size = presentation.Size
	view.Gui.MaxDistance = presentation.MaxDistance
	view.NameLabel.Size = UDim2.fromScale(1, BrainrotDisplayConfig.Layout.NameHeightScale)
	view.RankLabel.Size = UDim2.fromScale(1, BrainrotDisplayConfig.Layout.RankHeightScale)
	view.IncomeLabel.Size = UDim2.fromScale(1, BrainrotDisplayConfig.Layout.IncomeHeightScale)
	view.IncomeLabel.Visible = true
	view.StateBadge.Visible = false
	view.StateLabel.Text = ""

	if displayState == BrainrotDisplayConfig.States.Sleeping then
		view.StateBadge.BackgroundColor3 = BrainrotDisplayConfig.SleepBadge.Fill
		view.StateBadge.BackgroundTransparency = 0
		view.StateLabel.Text = BrainrotDisplayConfig.SleepBadge.Text
		view.StateLabel.TextColor3 = BrainrotDisplayConfig.SleepBadge.TextColor
		view.StateBadge.Visible = true
	elseif displayState == BrainrotDisplayConfig.States.Carried then
		view.NameLabel.Size = UDim2.fromScale(1, BrainrotDisplayConfig.Layout.CarriedNameHeightScale)
		view.RankLabel.Size = UDim2.fromScale(1, BrainrotDisplayConfig.Layout.CarriedRankHeightScale)
		view.IncomeLabel.Visible = false
	end
	updateBadgeLayout(view)

	if
		displayState == BrainrotDisplayConfig.States.Sleeping
		and previousState ~= BrainrotDisplayConfig.States.Sleeping
		and (
			game:GetService("Players").LocalPlayer == nil
			or game:GetService("Players").LocalPlayer:GetAttribute("ReducedMotion") ~= true
		)
	then
		playSleepPop(view)
	elseif stateChanged and not view.Focused then
		view.Scale.Scale = BrainrotDisplayConfig.Scale.Normal
	end
end

function BrainrotNametagView.setSaving(view: View, saving: boolean)
	if saving then
		view.StateLabel.Text = "SAVING…"
		view.StateBadge.BackgroundColor3 = Color3.fromRGB(48, 78, 110)
		view.StateBadge.Visible = true
	end
	updateBadgeLayout(view)
end

function BrainrotNametagView.updateCombat(view: View, sample: any?, showText: boolean, reducedMotion: boolean?)
	updateBadgeLayout(view)
	if not sample then
		view.HealthArea.Visible = false
		view.RankLabel.Visible = true
		if view.HealthTween then
			view.HealthTween:Cancel()
			view.HealthTween = nil
		end
		view.HealthTarget = nil
		return
	end
	view.HealthArea.Visible = true
	view.RankLabel.Visible = false
	view.HealthBar.Visible = not sample.sleeping
	view.HealthLabel.Visible = sample.sleeping or showText
	if sample.sleeping then
		view.StateBadge.Visible = false
		view.HealthLabel.Position = UDim2.fromOffset(0, 0)
		view.HealthLabel.Text = sample.countdown
		view.HealthLabel.TextColor3 = if sample.waking
			then Color3.fromRGB(255, 208, 74)
			else Color3.fromRGB(205, 245, 255)
	-- Deadline text and colour carry the warning without requiring motion.
	else
		view.HealthLabel.Position = UDim2.fromScale(0, 0)
		view.HealthLabel.Text = sample.text
		view.HealthLabel.TextColor3 = Color3.new(1, 1, 1)
		view.HealthFill.BackgroundColor3 = if sample.color == "Green"
			then Color3.fromRGB(90, 235, 100)
			elseif sample.color == "Amber" then Color3.fromRGB(255, 190, 60)
			else Color3.fromRGB(255, 72, 78)
		if view.HealthTarget ~= sample.fraction then
			if view.HealthTween then
				view.HealthTween:Cancel()
			end
			local target = UDim2.fromScale(sample.fraction, 1)
			if view.HealthTarget == nil or reducedMotion then
				view.HealthFill.Size = target
				view.HealthTween = nil
			else
				view.HealthTween =
					TweenService:Create(view.HealthFill, TweenInfo.new(Phase12.HpUi.TweenSeconds), { Size = target })
				view.HealthTween:Play()
			end
			view.HealthTarget = sample.fraction
		end
	end
end

function BrainrotNametagView.setFocused(view: View, isFocused: boolean)
	view.Focused = isFocused
	if view.FocusTween then
		view.FocusTween:Cancel()
		view.FocusTween = nil
	end
	updateBadgeLayout(view)
end

function BrainrotNametagView.setMutation(view: View, mutationDisplayData: MutationDisplayData?)
	if mutationDisplayData == nil then
		view.MutationBadge.Visible = false
		view.MutationLabel.Text = ""
	else
		view.MutationLabel.Text = string.upper(mutationDisplayData.displayName)
		view.MutationLabel.TextColor3 = mutationDisplayData.textColor or Color3.fromRGB(255, 255, 255)
		view.MutationBadge.BackgroundColor3 = mutationDisplayData.backgroundColor
		view.MutationBadge.BackgroundTransparency = 0
		view.MutationBadge.Visible = true
	end
	updateBadgeLayout(view)
end

function BrainrotNametagView.destroy(view: View)
	view.PopGeneration += 1
	if view.HealthTween then
		view.HealthTween:Cancel()
		view.HealthTween = nil
	end
	if view.FocusTween then
		view.FocusTween:Cancel()
		view.FocusTween = nil
	end
	view.Gui:Destroy()
end

function BrainrotNametagView.compact(view)
	updateBadgeLayout(view)
end
return table.freeze(BrainrotNametagView)
