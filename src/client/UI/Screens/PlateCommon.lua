--!nocheck
-- Shared helpers for MenusV2 Plate screens: money text, tier card colours, scroll rows/grids,
-- the one-action footer ("Equipped" well / Equip / price / locked) and toasts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Plate = require(ReplicatedStorage.Shared.UI.Plate)
local Shots = require(ReplicatedStorage.Shared.Config.UIDisplayShots)

local P = Theme.Plate
local px = Theme.px

local Common = {}

Common.Shots = Shots
Common.Plate = Plate
Common.Theme = Theme

function Common.money(n: number?): string
	return "$" .. Theme.abbreviate(n or 0)
end

-- Card background for a weapon/cart tier (1..8).
function Common.tierStyle(tier: number?): { background: { Color3 }, rainbow: boolean?, radial: boolean?, rays: boolean? }
	local t = math.clamp(tier or 1, 1, 8)
	return {
		background = P.Tier["T" .. t],
		rainbow = t == 8,
		radial = t == 7,
		rays = t >= 3,
	}
end

-- Horizontal scrolling row of cards (weapons/carts/rollers).
function Common.CardRow(parent: Instance, props: { position: UDim2, size: UDim2, gap: number? }): ScrollingFrame
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "CardRow"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Position = props.position
	sf.Size = props.size
	sf.ScrollingDirection = Enum.ScrollingDirection.X
	sf.AutomaticCanvasSize = Enum.AutomaticSize.X
	sf.CanvasSize = UDim2.new()
	sf.ScrollBarThickness = px(6)
	sf.ScrollBarImageColor3 = Color3.fromHex("#9A9CAB")
	sf.ElasticBehavior = Enum.ElasticBehavior.Always
	sf.ZIndex = 5
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	l.Padding = UDim.new(0, px(props.gap or 8))
	l.Parent = sf
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(4))
	pad.PaddingRight = UDim.new(0, px(4))
	pad.PaddingTop = UDim.new(0, px(4))
	pad.PaddingBottom = UDim.new(0, px(8))
	pad.Parent = sf
	sf.Parent = parent
	return sf
end

-- Vertical scrolling grid (sell/brainrots/index).
function Common.CardGrid(parent: Instance, props: { position: UDim2, size: UDim2, cell: Vector2, gap: number? }): ScrollingFrame
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "CardGrid"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Position = props.position
	sf.Size = props.size
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.CanvasSize = UDim2.new()
	sf.ScrollBarThickness = px(6)
	sf.ScrollBarImageColor3 = Color3.fromHex("#9A9CAB")
	sf.ZIndex = 5
	local g = Instance.new("UIGridLayout")
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.CellSize = UDim2.fromOffset(px(props.cell.X), px(props.cell.Y))
	g.CellPadding = UDim2.fromOffset(px(props.gap or 8), px(props.gap or 8))
	g.Parent = sf
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(4))
	pad.PaddingTop = UDim.new(0, px(4))
	pad.PaddingRight = UDim.new(0, px(8))
	pad.PaddingBottom = UDim.new(0, px(6))
	pad.Parent = sf
	sf.Parent = parent
	return sf
end

-- Scroll a row so `slot` is visible (equipped item into view).
function Common.scrollTo(sf: ScrollingFrame, slot: GuiObject?)
	if not slot then
		return
	end
	task.defer(function()
		if not slot.Parent then
			return
		end
		local x = slot.AbsolutePosition.X - sf.AbsolutePosition.X + sf.CanvasPosition.X
		sf.CanvasPosition = Vector2.new(math.max(0, x - px(8)), 0)
	end)
end

-- The one action at the bottom of a card. kind: "well" | "info" | "go" | "gem" | "robux" | "locked" | "stop"
function Common.Action(card, props: {
	kind: string,
	text: string,
	icon: string?,
	primary: boolean?,
	onClick: (() -> ())?,
	bag: any,
	height: number?,
})
	local h = px(props.height or 34)
	if props.kind == "well" then
		return Plate.StateWell(card.Footer, props.text, { size = UDim2.new(0.9, 0, 0, h), order = 5, bag = props.bag, textSize = 17 })
	end
	local b = Plate.Button(card.Footer, {
		variant = props.kind,
		text = props.text,
		lockedReason = if props.kind == "locked" then props.text else nil,
		icon = props.icon,
		primary = props.primary,
		size = UDim2.new(0.9, 0, 0, h),
		order = 5,
		textSize = 18,
		bag = props.bag,
		onClick = props.onClick,
	})
	return b
end

-- Favourite star (a starred brainrot can't be sold): the gold icon when on, the slate one when off.
Common.StarGold = Color3.fromHex("#FFD447")
function Common.Star(parent: Instance, on: boolean, props: { size: number?, position: UDim2?, anchor: Vector2?, z: number? }?): ImageLabel
	local o = props or {}
	local size = Theme.px(o.size or 22)
	local star = Instance.new("ImageLabel")
	star.Name = "Star"
	star.BackgroundTransparency = 1
	star.Image = if on then Theme.Icons.Star else Theme.Icons.StarOff
	star.ScaleType = Enum.ScaleType.Fit
	star.Size = UDim2.fromOffset(size, size)
	star.AnchorPoint = o.anchor or Vector2.zero
	star.Position = o.position or UDim2.new()
	star.ZIndex = o.z or 12
	star.Parent = parent
	return star
end

-- Toast for a rejected/accepted action (messages come from the controller's message()).
function Common.notify(gui: ScreenGui, result, text: string?)
	if type(result) ~= "table" then
		return
	end
	if result.ok == false and text and text ~= "" then
		Plate.Toast(gui, text, { color = Color3.fromHex("#FF6B7A") })
	end
end

return Common
