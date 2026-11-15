--!strict
-- Core Loop V2 L4.5 Star tag (`WorldTag` builder; board 3 "Star tags & world markers"). Presentation only:
-- reads the director's Star attributes. One pooled BillboardGui per Star, at most CoreLoop.Fx MaxStarTags.
-- Lines top to bottom (board 3 order): grade sticker · name (mutation prefix after the reveal) ·
-- "MUTATED! ?" while unrevealed · rarity (or "GOLDEN · RARE" after the reveal) · income ·
-- chip row (odds, GUARDED, YOURS / NOT YOURS YET 0:14) · LEAVING 0:12 chip with an orange clock ring.
-- Size: 1.0 at <= 40 studs -> 0.6 at 120; beyond 120 only the sticker, to 200 / 300 (Star / Super),
-- Jackpot always. AlwaysOnTop only within 60 studs. Built from Stud Pop builders (Starburst, Text).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CoreLoop = require(Shared.Config.CoreLoop)
local BrainrotCatalog = require(Shared.Config.BrainrotCatalog)
local Phase12Rules = require(Shared.Utility.Phase12Rules)
local Theme = require(Shared.UI.Theme)
local StudPop = require(Shared.UI.StudPop)
local Kit = require(script.Parent.FxKit)

local WorldTag = {}

local MAX_TAGS = 6
local FULL_AT, SMALL_AT = 40, 120
local ON_TOP_WITHIN = 60
local STICKER_ONLY_REACH = { Star = 200, Super = 300 }
local STICKER_PX = { Star = 46, Super = 52, Jackpot = 58 }
local LOCK = utf8.char(0x1F512)
local SPARKLE = utf8.char(0x2726)

type Tag = {
	Gui: BillboardGui,
	Scale: UIScale,
	Grade: string,
	Sticker: Frame,
	Ring: Frame,
	SetRing: (number) -> (),
	Rays: ImageLabel?,
	Details: Frame,
	Name: TextLabel,
	Mystery: Frame,
	Rarity: TextLabel,
	Income: TextLabel,
	Odds: Frame,
	OddsLabel: TextLabel,
	Guarded: Frame,
	Yours: Frame,
	NotYours: Frame,
	NotYoursLabel: TextLabel,
	Leaving: Frame,
	LeavingLabel: TextLabel,
}

local tags: { [Model]: Tag } = {}
local localPlayer = Players.LocalPlayer

local function playerGui(): Instance?
	return localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
end

local function label(
	parent: Instance,
	text: string,
	px: number,
	colour: Color3?,
	display: boolean?
): TextLabel
	local t = StudPop.Text(parent, text, {
		display = display == true,
		maxPx = px,
		size = UDim2.new(1, 0, 0, Theme.px(px) * 1.25),
		color = colour,
	})
	return t
end

-- A small rounded chip (board 3 `.chip`: 2 px ink border, radius 8, white Fredoka with a 2 px stroke).
local function chip(
	parent: Instance,
	text: string,
	colour: Color3,
	order: number
): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = "Chip"
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(0, Theme.px(22))
	frame.BackgroundColor3 = colour
	frame.LayoutOrder = order
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.px(8))
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Ink
	stroke.Thickness = Theme.px(2)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.px(6))
	pad.PaddingRight = UDim.new(0, Theme.px(6))
	pad.Parent = frame
	local t = StudPop.Text(frame, text, { maxPx = 14, size = UDim2.fromScale(0, 1) })
	t.AutomaticSize = Enum.AutomaticSize.X
	t.TextScaled = false
	t.TextSize = Theme.px(14)
	frame.Parent = parent
	return frame, t
end

-- Two-half-mask radial wipe (the CL_Ring drain without an uploaded image).
local function radial(parent: Frame, colour: Color3): (number) -> ()
	local gradients = {}
	for _, side in { "Right", "Left" } do
		local holder = Instance.new("Frame")
		holder.Name = "Half" .. side
		holder.BackgroundTransparency = 1
		holder.ClipsDescendants = true
		holder.Size = UDim2.fromScale(0.5, 1)
		holder.Position = UDim2.fromScale(if side == "Right" then 0.5 else 0, 0)
		local disc = Instance.new("Frame")
		disc.BackgroundColor3 = colour
		disc.BorderSizePixel = 0
		disc.Size = UDim2.fromScale(2, 1)
		disc.Position = UDim2.fromScale(if side == "Right" then -1 else 0, 0)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = disc
		disc.Parent = holder
		holder.Parent = parent
		gradients[side] = gradient
	end
	return function(fraction: number)
		local angle = math.clamp(fraction, 0, 1) * 360
		gradients.Right.Rotation = math.clamp(angle, 0, 180)
		gradients.Left.Rotation = math.clamp(angle, 180, 360)
	end
end

local function stickerColours(grade: string, tier: string): (Color3, string)
	if grade == "Jackpot" then
		return Theme.CoreLoop.Jackpot, "JACKPOT"
	end
	return (Theme.Rarity :: any)[tier] or Theme.Rarity.Common,
		if grade == "Super" then "SUPER STAR" else "STAR"
end

local function build(model: Model, grade: string, tier: string): Tag
	local gui = Instance.new("BillboardGui")
	gui.Name = "CoreLoopStarTag"
	gui.Size = UDim2.fromOffset(Theme.px(260), Theme.px(200))
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y * 0.5 + 2, 0)
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false
	gui.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local scale = Instance.new("UIScale")
	scale.Parent = gui

	local column = Instance.new("Frame")
	column.Name = "Column"
	column.BackgroundTransparency = 1
	column.Size = UDim2.fromScale(1, 1)
	column.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Theme.px(2))
	list.Parent = column

	-- 1. Grade sticker (+ LEAVING clock ring behind it; rays behind a Jackpot).
	local px = STICKER_PX[grade] or 46
	local stickerHolder = Instance.new("Frame")
	stickerHolder.Name = "StickerHolder"
	stickerHolder.BackgroundTransparency = 1
	stickerHolder.Size = UDim2.fromOffset(Theme.px(px) * 1.6, Theme.px(px))
	stickerHolder.LayoutOrder = 1
	stickerHolder.Parent = column
	local ring = Instance.new("Frame")
	ring.Name = "LeavingRing"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(Theme.px(px) * 1.7, Theme.px(px) * 1.15) -- board 3: an oval clock behind the burst
	ring.Visible = false
	ring.Parent = stickerHolder
	local backing = Instance.new("Frame")
	backing.Name = "Track"
	backing.BackgroundColor3 = Theme.Color.White
	backing.BackgroundTransparency = 0.87
	backing.Size = UDim2.fromScale(1, 1)
	local backingCorner = Instance.new("UICorner")
	backingCorner.CornerRadius = UDim.new(0.5, 0)
	backingCorner.Parent = backing
	backing.Parent = ring
	local setRing = radial(ring, Theme.CoreLoop.Leaving)
	local rays: ImageLabel? = nil
	if grade == "Jackpot" then
		local image = Instance.new("ImageLabel")
		image.Name = "Rays"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromOffset(Theme.px(px) * 2.4, Theme.px(px) * 2.4)
		image.Image = Theme.Images.Rays
		image.ImageColor3 = Theme.CoreLoop.JackpotRays
		image.ImageTransparency = 0.45
		image.ZIndex = 0
		image.Parent = stickerHolder
		rays = image
	end
	local colour, word = stickerColours(grade, tier)
	local sticker = StudPop.Starburst(stickerHolder, word, nil, {
		size = UDim2.fromOffset(Theme.px(px) * 1.25, Theme.px(px) * 1.25),
		position = UDim2.fromScale(0.5, 0.5),
	})
	for _, child in sticker:GetChildren() do
		if child:IsA("Frame") and child.ZIndex == 31 then
			child.BackgroundColor3 = colour
		end
	end

	-- 2–5. Name, mystery line, rarity, income (hidden beyond SMALL_AT).
	local details = Instance.new("Frame")
	details.Name = "Details"
	details.BackgroundTransparency = 1
	details.AutomaticSize = Enum.AutomaticSize.Y
	details.Size = UDim2.fromScale(1, 0)
	details.LayoutOrder = 2
	details.Parent = column
	local detailList = Instance.new("UIListLayout")
	detailList.FillDirection = Enum.FillDirection.Vertical
	detailList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	detailList.SortOrder = Enum.SortOrder.LayoutOrder
	detailList.Padding = UDim.new(0, Theme.px(1))
	detailList.Parent = details
	local name = label(details, "", 18, Theme.Color.Text)
	name.LayoutOrder = 1
	local mystery = Instance.new("Frame")
	mystery.Name = "Mystery"
	mystery.BackgroundTransparency = 1
	mystery.Size = UDim2.new(1, 0, 0, Theme.px(15) * 1.25)
	mystery.LayoutOrder = 2
	mystery.Visible = false
	mystery.Parent = details
	local mysteryLabel = label(mystery, SPARKLE .. " MUTATED! ?", 15, Theme.CoreLoop.Shimmer)
	mysteryLabel.Size = UDim2.fromScale(1, 1)
	local rarity = label(details, "", 14)
	rarity.LayoutOrder = 3
	local income = label(details, "", 14, Theme.Color.Cash)
	income.LayoutOrder = 4

	-- 6. Chip row.
	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, 0, 0, Theme.px(24))
	chips.LayoutOrder = 3
	chips.Parent = column
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, Theme.px(4))
	row.Parent = chips
	local odds, oddsLabel = chip(chips, "", Theme.Color.Panel, 1)
	local guarded = chip(chips, "GUARDED", Theme.CoreLoop.Guarded, 2)
	local yours = chip(chips, "YOURS", Theme.Variant.go.base, 3)
	local notYours, notYoursLabel = chip(chips, "", Theme.CoreLoop.NotYours, 4)

	-- 7. LEAVING chip.
	local leavingRow = Instance.new("Frame")
	leavingRow.Name = "LeavingRow"
	leavingRow.BackgroundTransparency = 1
	leavingRow.Size = UDim2.new(1, 0, 0, Theme.px(24))
	leavingRow.LayoutOrder = 4
	leavingRow.Visible = false
	leavingRow.Parent = column
	local leavingList = Instance.new("UIListLayout")
	leavingList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	leavingList.Parent = leavingRow
	local _, leavingLabel = chip(leavingRow, "", Theme.CoreLoop.Leaving, 1)

	gui.Parent = playerGui()
	return {
		Gui = gui,
		Scale = scale,
		Grade = grade,
		Sticker = sticker,
		Ring = ring,
		SetRing = setRing,
		Rays = rays,
		Details = details,
		Name = name,
		Mystery = mystery,
		Rarity = rarity,
		Income = income,
		Odds = odds,
		OddsLabel = oddsLabel,
		Guarded = guarded,
		Yours = yours,
		NotYours = notYours,
		NotYoursLabel = notYoursLabel,
		Leaving = leavingRow,
		LeavingLabel = leavingLabel,
	}
end

local function destroy(model: Model)
	local tag = tags[model]
	if tag then
		tag.Gui:Destroy()
		tags[model] = nil
	end
end

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function refresh(tag: Tag, model: Model, distance: number, serverNow: number)
	local definition = BrainrotCatalog.Get(model:GetAttribute("BrainrotId") or model.Name)
	local tier = if definition then definition.tier else "Common"
	local mutationRaw = model:GetAttribute("BrainrotMutationId") or model:GetAttribute("MutationId")
	local mutation = Phase12Rules.NormalizeMutation(mutationRaw) or "None"
	local shimmer = model:GetAttribute("CoreLoopShimmer") == true
	local revealed = mutation ~= "None" and not shimmer
	local baseName = if definition then definition.displayName else model.Name
	tag.Name.Text = if revealed then string.upper(mutation) .. " " .. baseName else baseName
	tag.Mystery.Visible = shimmer
	local tierColour = (Theme.Rarity :: any)[tier] or Theme.Rarity.Common
	if revealed then
		tag.Rarity.Text = string.upper(mutation) .. " · " .. string.upper(tier)
		tag.Rarity.TextColor3 = (Theme.Mutation :: any)[mutation] or tierColour
	else
		tag.Rarity.Text = string.upper(tier)
		tag.Rarity.TextColor3 = tierColour
	end
	local cps = if definition
		then definition.cashPerSecond * Phase12Rules.MutationMultiplier(
			if revealed then mutation else "None"
		)
		else 0
	tag.Income.Text = "+$" .. Theme.abbreviate(cps) .. "/s"
	local odds = model:GetAttribute("StarOdds")
	tag.Odds.Visible = type(odds) == "string" and odds ~= ""
	tag.OddsLabel.Text = if type(odds) == "string" then odds else ""
	tag.Guarded.Visible = model:GetAttribute("Guarded") == true
	local owner = model:GetAttribute("StarOwnerUserId")
	local exclusiveUntil = model:GetAttribute("StarExclusiveUntil")
	local exclusive = type(exclusiveUntil) == "number" and exclusiveUntil > serverNow
	local mine = owner == localPlayer.UserId
	tag.Yours.Visible = exclusive and mine
	tag.NotYours.Visible = exclusive and not mine
	if exclusive and not mine then
		tag.NotYoursLabel.Text = LOCK
			.. " NOT YOURS YET "
			.. clock((exclusiveUntil :: number) - serverNow)
	end
	-- Other players' Stars: the sticker sits at half strength (board 3 cell 5).
	local fade = if owner ~= nil and not mine then 0.4 else 0
	for _, child in tag.Sticker:GetDescendants() do
		if child:IsA("Frame") then
			child.BackgroundTransparency = fade
		elseif child:IsA("TextLabel") then
			child.TextTransparency = fade
		end
	end
	local leavingUntil = model:GetAttribute("StarLeavingUntil")
	local leaving = type(leavingUntil) == "number" and leavingUntil > serverNow
	tag.Leaving.Visible = leaving
	tag.Ring.Visible = leaving
	if leaving then
		local left = (leavingUntil :: number) - serverNow
		tag.LeavingLabel.Text = "LEAVING " .. clock(left)
		tag.SetRing(left / CoreLoop.Star.LeavingWarnSeconds)
	end
	-- Distance: 1.0 at <= 40 -> 0.6 at 120; beyond 120 only the sticker.
	local k = math.clamp((distance - FULL_AT) / (SMALL_AT - FULL_AT), 0, 1)
	tag.Scale.Scale = 1 - 0.4 * k
	local far = distance > SMALL_AT
	tag.Details.Visible = not far
	tag.Odds.Parent.Visible = not far -- chip row
	if far then
		tag.Leaving.Visible = false
	end
	tag.Gui.AlwaysOnTop = distance <= ON_TOP_WITHIN and Kit.OnTop()
	if tag.Rays then
		tag.Rays.Rotation = (os.clock() * 20) % 360
	end
end

-- Called every presentation frame with the awake director Stars visible to this client.
function WorldTag.Step(rows: { { Model: Model, Grade: string, Distance: number } })
	local serverNow = Workspace:GetServerTimeNow()
	local keep: { [Model]: boolean } = {}
	local shown = 0
	for _, row in rows do
		if shown >= MAX_TAGS then
			break
		end
		local reach = if row.Grade == "Jackpot"
			then math.huge
			else (STICKER_ONLY_REACH[row.Grade] or 200)
		local sleeping = row.Model:GetAttribute("BrainrotDisplayState") == "Sleeping"
		if row.Distance > reach or sleeping then
			continue
		end
		shown += 1
		keep[row.Model] = true
		local tag = tags[row.Model]
		if tag and tag.Grade ~= row.Grade then
			destroy(row.Model) -- upgrade: rebuild with the new sticker
			tag = nil
		end
		if not tag then
			local definition =
				BrainrotCatalog.Get(row.Model:GetAttribute("BrainrotId") or row.Model.Name)
			tag = build(row.Model, row.Grade, if definition then definition.tier else "Common")
			tags[row.Model] = tag
		end
		refresh(tag :: Tag, row.Model, row.Distance, serverNow)
	end
	for model in table.clone(tags) do
		if not keep[model] or not model.Parent then
			destroy(model)
		end
	end
end

function WorldTag.Has(model: Model): boolean
	return tags[model] ~= nil
end

return WorldTag
