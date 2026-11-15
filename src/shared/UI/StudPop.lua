--!strict
-- Stud Pop v2 (LOUD) component builders for Brainrot Expedition.
-- Every builder returns plain Roblox instances sized in Scale + constraints, so they
-- work on phones first. UI renders state; it never computes game state.
--
-- Usage:
--   local StudPop = require(path.UI.StudPop)
--   local gui = StudPop.ScreenGui("Shop")
--   local shop = StudPop.Window(gui, { title = "SHOP", color = "alert" })
--   StudPop.Ribbon(shop.Body, { text = "COINS", variant = "info" })
--   StudPop.Button(shop.Body, { variant = "go", text = "CLAIM", big = true, onClick = claim })
--   shop.open()

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local Juice = require(script.Parent.Juice)
local BarGuard = require(script.Parent.BarGuard)

local StudPop = {}

------------------------------------------------------------------ primitives
local function corner(parent: Instance, r: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = parent
end

local function stroke(parent: Instance, px: number, mode: Enum.ApplyStrokeMode?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = Theme.Color.Ink
	s.Thickness = Theme.px(px)
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function ramp(parent: Instance, r: Theme.Ramp)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, r.hi),
		ColorSequenceKeypoint.new(0.55, r.base),
		ColorSequenceKeypoint.new(1, r.lo),
	})
	g.Parent = parent
end

local function text(parent: Instance, str: string, opts: {
	display: boolean?,
	color: Color3?,
	maxPx: number?,
	size: UDim2?,
	align: Enum.TextXAlignment?,
	order: number?,
}?): TextLabel
	local o = opts or {}
	local t = Instance.new("TextLabel")
	t.Name = "Label"
	t.BackgroundTransparency = 1
	t.Text = str
	t.FontFace = if o.display then Theme.Font.Display else Theme.Font.Body
	t.TextColor3 = o.color or Theme.Color.Text
	t.TextScaled = true
	t.TextXAlignment = o.align or Enum.TextXAlignment.Center
	t.Size = o.size or UDim2.fromScale(1, 1)
	t.LayoutOrder = o.order or 0
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = Theme.px(Theme.Size.MinText)
	c.MaxTextSize = Theme.px(o.maxPx or 28)
	c.Parent = t
	stroke(t, Theme.Size.TextStroke, Enum.ApplyStrokeMode.Contextual)
	t.Parent = parent
	return t
end
StudPop.Text = text

local function icon(parent: Instance, image: string, order: number?): ImageLabel?
	if image == "" then
		return nil
	end
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = image
	i.Size = UDim2.fromScale(1, 0.8)
	i.LayoutOrder = order or -1
	i.ScaleType = Enum.ScaleType.Fit
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.Parent = i
	i.Parent = parent
	return i
end

-- The surface recipe: 3-stop gradient + gloss + studs + ink outline. (Lip is added by the caller.)
-- Uses a CanvasGroup so gloss/shine/studs clip to the rounded corners.
function StudPop.Surface(parent: Instance, variant: string, radius: UDim?): CanvasGroup
	local f = Instance.new("CanvasGroup")
	f.Name = "Face"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	corner(f, radius or Theme.Radius.Md)
	stroke(f, Theme.Size.Stroke)
	-- The colour ramp lives on an inner Fill: a UIGradient on the CanvasGroup itself would tint
	-- every child (white labels turned the variant colour in Sibling ZIndex mode).
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 0
	ramp(fill, Theme.ramp(variant))
	fill.Parent = f

	-- gloss dome: white over the top 45%, fading 28% -> 12%, hard bottom edge
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BorderSizePixel = 0
	gloss.Size = UDim2.fromScale(1, 0.45)
	gloss.ZIndex = 2
	local gg = Instance.new("UIGradient")
	gg.Rotation = 90
	gg.Transparency = NumberSequence.new(0.72, 0.88)
	gg.Parent = gloss
	gloss.Parent = f

	-- white plastic rim just inside the ink outline
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.BackgroundTransparency = 1
	rim.Size = UDim2.fromScale(1, 1)
	rim.ZIndex = 3
	corner(rim, radius or Theme.Radius.Md)
	local rs = Instance.new("UIStroke")
	rs.Color = Color3.new(1, 1, 1)
	rs.Transparency = 0.45
	rs.Thickness = Theme.px(Theme.Size.Rim)
	rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rs.Parent = rim
	local rp = Instance.new("UIPadding")
	rp.Parent = rim
	rim.Parent = f

	-- bottom shade
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.78
	shade.BorderSizePixel = 0
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0.14)
	shade.ZIndex = 2
	shade.Parent = f

	if Theme.StudTexture ~= "" then
		local studs = Instance.new("ImageLabel")
		studs.Name = "Studs"
		studs.BackgroundTransparency = 1
		studs.Image = Theme.StudTexture
		studs.ImageTransparency = Theme.StudTransparency
		studs.ScaleType = Enum.ScaleType.Tile
		studs.TileSize = UDim2.fromOffset(Theme.px(Theme.StudTilePx), Theme.px(Theme.StudTilePx))
		studs.Size = UDim2.fromScale(1, 1)
		studs.ZIndex = 1
		studs.Parent = f
	end
	f.Parent = parent
	return f
end

-- Holder + ink Lip + Face. Pressing drops Face onto the Lip.
local function brick(parent: Instance, variant: string, radius: UDim?): (Frame, Frame, CanvasGroup)
	local holder = Instance.new("Frame")
	holder.Name = "Brick"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)

	local lipPx = Theme.px(Theme.Size.Lip)
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BackgroundColor3 = Theme.Color.Ink
	lip.BorderSizePixel = 0
	lip.Position = UDim2.fromOffset(0, lipPx)
	lip.Size = UDim2.new(1, 0, 1, -lipPx)
	corner(lip, radius or Theme.Radius.Md)
	lip.Parent = holder

	local face = StudPop.Surface(holder, variant, radius)
	face.Size = UDim2.new(1, 0, 1, -lipPx)
	face.ZIndex = 2
	holder.Parent = parent
	return holder, lip, face
end

local function content(face: Instance, padX: number?): Frame
	local row = Instance.new("Frame")
	row.Name = "Content"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = 3
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, Theme.px(6))
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = row
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(padX or 0.08, 0)
	p.PaddingRight = UDim.new(padX or 0.08, 0)
	p.PaddingTop = UDim.new(0.12, 0)
	p.PaddingBottom = UDim.new(0.14, 0)
	p.Parent = row
	row.Parent = face
	return row
end

------------------------------------------------------------------ ScreenGui
function StudPop.ScreenGui(name: string, displayOrder: number?): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = displayOrder or 0
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return g
end

------------------------------------------------------------------ Button
export type ButtonProps = {
	variant: string, -- go | stop | info | robux | alert | locked
	text: string, -- 1–2 words, caps
	icon: string?,
	big: boolean?, -- the ONE primary action per screen (adds shine)
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	order: number?,
	onClick: (() -> ())?,
	lockedReason: string?, -- shown instead of text when variant == "locked"
}
export type Button = {
	Root: TextButton,
	Label: TextLabel,
	setText: (string) -> (),
	setVariant: (string) -> (),
	destroy: () -> (),
}

function StudPop.Button(parent: Instance, props: ButtonProps): Button
	local root = Instance.new("TextButton")
	root.Name = "Button_" .. props.text
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.Size = props.size or (if props.big then UDim2.fromScale(0.42, 0.16) else UDim2.fromScale(0.28, 0.12))
	root.Position = props.position or UDim2.new()
	root.AnchorPoint = props.anchor or Vector2.zero
	root.LayoutOrder = props.order or 0
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = if props.big then 3.6 else 3
	aspect.Parent = root
	local minH = Instance.new("UISizeConstraint")
	minH.MinSize = Vector2.new(0, Theme.px(Theme.Size.TouchMin))
	minH.Parent = root

	local variant = props.variant
	local _, _, face = brick(root, variant, if props.big then UDim.new(0, Theme.px(18)) else Theme.Radius.Md)
	local row = content(face)
	local buttonIcon = icon(row, props.icon or "")
	local label = text(row, if variant == "locked" and props.lockedReason then props.lockedReason else props.text, {
		display = true,
		maxPx = if props.big then 38 else 28,
		size = UDim2.fromScale(0.7, 1),
	})
	label.AutomaticSize = Enum.AutomaticSize.None

	local lipPx = Theme.px(Theme.Size.Lip)
	local cleanups: { () -> () } = {}
	table.insert(cleanups, Juice.bindPress(root, face, UDim2.new(), UDim2.fromOffset(0, lipPx), {
		sound = if variant == "robux" or variant == "go" then "Click" else nil,
		locked = function()
			return variant == "locked"
		end,
	}))
	table.insert(cleanups, Juice.bindHover(root))
	do
		-- tap reward: the icon bounces; actions that "do it" also throw a few sparkles
		local c = root.Activated:Connect(function()
			if variant == "locked" then
				return
			end
			if buttonIcon then
				Juice.iconBounce(buttonIcon)
			end
			if (variant == "go" or variant == "robux" or variant == "gem") and not Juice.reduced() then
				Juice.sparkles(root, if props.big then 4 else 2)
			end
		end)
		table.insert(cleanups, function()
			c:Disconnect()
		end)
	end
	if props.big then
		-- the ONE thing on screen that asks to be tapped
		table.insert(cleanups, Juice.shine(face))
		table.insert(cleanups, Juice.breathe(root))
		table.insert(cleanups, Juice.twinkleLoop(root, 1.2))
	elseif variant == "gem" then
		table.insert(cleanups, Juice.twinkleLoop(root, 3, Theme.Color.GemGlint))
	end
	if props.onClick then
		local cb = props.onClick
		local c = root.Activated:Connect(function()
			if variant ~= "locked" then
				cb()
			end
		end)
		table.insert(cleanups, function()
			c:Disconnect()
		end)
	end
	root.Parent = parent

	local self: Button
	self = {
		Root = root,
		Label = label,
		setText = function(s: string)
			label.Text = s
		end,
		setVariant = function(v: string)
			variant = v
			local fill = face:FindFirstChild("Fill")
			local g = fill and fill:FindFirstChildOfClass("UIGradient")
			if g then
				local r = Theme.ramp(v)
				g.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, r.hi),
					ColorSequenceKeypoint.new(0.55, r.base),
					ColorSequenceKeypoint.new(1, r.lo),
				})
			end
		end,
		destroy = function()
			for _, f in cleanups do
				f()
			end
			root:Destroy()
		end,
	}
	return self
end

------------------------------------------------------------------ Badge (red dot / sticker)
function StudPop.Dot(parent: GuiObject, count: number): TextLabel
	local d = Instance.new("TextLabel")
	d.Name = "Dot"
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale(0.88, 0.12)
	d.Size = UDim2.fromScale(0.36, 0.36)
	d.BackgroundColor3 = Theme.Color.Notify
	d.FontFace = Theme.Font.Body
	d.TextColor3 = Theme.Color.Text
	d.TextScaled = true
	d.Text = if count > 9 then "9+" else tostring(count)
	d.Visible = count > 0
	d.ZIndex = 20
	corner(d, Theme.Radius.Pill)
	stroke(d, Theme.Size.Stroke)
	local a = Instance.new("UIAspectRatioConstraint")
	a.Parent = d
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0.15, 0)
	p.PaddingBottom = UDim.new(0.15, 0)
	p.Parent = d
	d.Parent = parent
	return d
end

function StudPop.Sticker(parent: GuiObject, label: string, variant: string): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Sticker"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.85, 0.05)
	holder.Size = UDim2.fromScale(0.5, 0.18)
	holder.Rotation = -6
	holder.ZIndex = 20
	local _, _, face = brick(holder, variant, Theme.Radius.Sm)
	text(face, label, { display = true, maxPx = 20 }).ZIndex = 4
	holder.Parent = parent
	Juice.float(holder)
	return holder
end

------------------------------------------------------------------ HUD button (round)
function StudPop.HudButton(parent: Instance, props: { variant: string, icon: string, text: string, badge: number?, order: number?, onClick: (() -> ())? }): (TextButton, TextLabel)
	local root = Instance.new("TextButton")
	root.Name = "Hud_" .. props.text
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 0.13) -- inside a vertical rail; height drives size
	root.LayoutOrder = props.order or 0
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 0.85
	a.Parent = root

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.BackgroundTransparency = 1
	disc.Size = UDim2.fromScale(1, 0.82)
	local da = Instance.new("UIAspectRatioConstraint")
	da.Parent = disc
	disc.Parent = root
	local _, _, face = brick(disc, props.variant, Theme.Radius.Pill)
	local ic = icon(face, props.icon)
	if ic then
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.48)
		ic.Size = UDim2.fromScale(0.78, 0.78) -- flashy icons are drawn to break out of the disc a little
		ic.ZIndex = 3
		Juice.bob(ic, ((props.order or 0) % 5) * 0.22)
	end
	text(root, props.text:upper(), { size = UDim2.new(1.3, 0, 0.26, 0), maxPx = 16 }).Position = UDim2.fromScale(-0.15, 0.78)
	local dot = StudPop.Dot(disc, props.badge or 0)
	Juice.bindPress(root, face, UDim2.new(), UDim2.fromOffset(0, Theme.px(Theme.Size.Lip)))
	Juice.bindHover(root)
	-- tap reward: the whole disc twirls once (the icon keeps its idle bob), with a sparkle pop
	root.Activated:Connect(function()
		Juice.iconBounce(face, true, disc)
		if not Juice.reduced() then
			Juice.sparkles(disc, 3)
		end
	end)
	if props.onClick then
		root.Activated:Connect(props.onClick)
	end
	root.Parent = parent
	return root, dot
end

------------------------------------------------------------------ Gradient title (loud frame text: titles, shouts)
function StudPop.GradientTitle(parent: Instance, str: string, opts: { top: Color3?, bottom: Color3?, maxPx: number?, size: UDim2? }?): TextLabel
	local o = opts or {}
	local t = text(parent, str:upper(), { display = true, maxPx = o.maxPx or 48, size = o.size })
	t.TextColor3 = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#FFF6B0")),
		ColorSequenceKeypoint.new(0.4, o.top or Theme.Color.Burst),
		ColorSequenceKeypoint.new(1, o.bottom or Theme.Color.BurstLo),
	})
	g.Parent = t
	local st = t:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = Theme.px(5)
	end
	return t
end

------------------------------------------------------------------ Starburst sticker (BEST VALUE, +42% GEMS, x2)
-- Built from rotated squares (no image needed): an ink star with a coloured star inside.
function StudPop.Starburst(parent: GuiObject, label: string, variant: string?, opts: { size: UDim2?, position: UDim2? }?): Frame
	local o = opts or {}
	local r = Theme.ramp(variant or "burst")
	local holder = Instance.new("Frame")
	holder.Name = "Starburst"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = o.size or UDim2.fromScale(0.55, 0.55)
	holder.Position = o.position or UDim2.fromScale(0.9, 0.05)
	holder.ZIndex = 30
	local a = Instance.new("UIAspectRatioConstraint")
	a.Parent = holder
	local function star(scale: number, color: Color3, z: number)
		for i = 0, 2 do
			local sq = Instance.new("Frame")
			sq.BorderSizePixel = 0
			sq.AnchorPoint = Vector2.new(0.5, 0.5)
			sq.Position = UDim2.fromScale(0.5, 0.5)
			sq.Size = UDim2.fromScale(scale * 0.74, scale * 0.74)
			sq.Rotation = i * 30
			sq.BackgroundColor3 = color
			sq.ZIndex = z
			sq.Parent = holder
		end
	end
	star(1, Theme.Color.Ink, 30)
	star(0.86, r.base, 31)
	local lbl = text(holder, label:upper(), { display = true, maxPx = 18, size = UDim2.fromScale(0.7, 0.5) })
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(0.5, 0.5)
	lbl.Rotation = -8
	lbl.ZIndex = 32
	holder.Parent = parent
	local s = Juice.scaleOf(holder)
	Juice.play(holder, "wobble", TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 10 })
	Juice.play(s, "wobble", TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 })
	holder.Rotation = -6
	return holder
end

------------------------------------------------------------------ Window
export type Window = {
	Root: CanvasGroup,
	Body: ScrollingFrame,
	Scrim: TextButton,
	open: () -> (),
	close: () -> (),
	onClosed: BindableEvent,
}

function StudPop.Window(gui: ScreenGui, props: { title: string, color: string?, aspect: number? }): Window
	local scrim = Instance.new("TextButton")
	scrim.Name = props.title .. "_Scrim"
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.BackgroundColor3 = Theme.Color.Scrim
	scrim.BackgroundTransparency = 1
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Visible = false
	scrim.ZIndex = 10
	scrim.Parent = gui

	local win = Instance.new("CanvasGroup")
	win.Name = props.title .. "_Window"
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Position = UDim2.fromScale(0.5, 0.54)
	win.Size = UDim2.fromScale(0.88, 0.8)
	win.BackgroundTransparency = 1
	win.Visible = false
	win.ZIndex = 11
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = props.aspect or 1.35
	ar.Parent = win
	win.Parent = gui

	-- body (lip + panel). Inset from the top so the title brick can straddle the edge.
	local lipPx = Theme.px(8)
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BackgroundColor3 = Theme.Color.Ink
	lip.Position = UDim2.new(0.02, 0, 0.08, lipPx)
	lip.Size = UDim2.new(0.96, 0, 0.9, -lipPx)
	corner(lip, Theme.Radius.Lg)
	lip.Parent = win

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.Position = UDim2.fromScale(0.02, 0.08)
	panel.Size = UDim2.new(0.96, 0, 0.9, -lipPx)
	corner(panel, Theme.Radius.Lg)
	stroke(panel, Theme.Size.Stroke)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Theme.Color.PanelHi, Theme.Color.Panel)
	g.Parent = panel
	panel.Parent = win

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromScale(0, 0.1)
	body.Size = UDim2.fromScale(1, 0.9)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = Theme.px(6)
	body.ScrollBarImageColor3 = Theme.Color.TextMuted
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.03, 0)
	pad.PaddingRight = UDim.new(0.03, 0)
	pad.PaddingTop = UDim.new(0.02, 0)
	pad.PaddingBottom = UDim.new(0.04, 0)
	pad.Parent = body
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Theme.px(10))
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = body
	body.Parent = panel

	-- title brick straddling the top edge
	local title = Instance.new("Frame")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0)
	title.Size = UDim2.fromScale(0.34, 0.15)
	title.ZIndex = 5
	title.Parent = win
	if Theme.Images.Rays ~= "" then
		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.BackgroundTransparency = 1
		rays.Image = Theme.Images.Rays
		rays.ImageColor3 = Theme.Color.Burst
		rays.ImageTransparency = 0.45
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.45)
		rays.Size = UDim2.fromScale(1.6, 3.2)
		rays.ZIndex = 1
		rays.Parent = title
		Juice.play(rays, "spin", TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	end
	local _, _, tface = brick(title, props.color or "alert", Theme.Radius.Md)
	local tl = StudPop.GradientTitle(tface, props.title, { maxPx = 48 })
	tl.ZIndex = 4

	local onClosed = Instance.new("BindableEvent")
	local self: Window
	local function close()
		Juice.close(win, scrim)
		onClosed:Fire()
	end

	-- red X on the corner (the only icon-only button)
	local x = StudPop.Button(win, {
		variant = "stop",
		text = "X",
		icon = Theme.Icons.Close,
		size = UDim2.fromScale(0.1, 0.14),
		position = UDim2.fromScale(1, 0.02),
		anchor = Vector2.new(0.75, 0),
		onClick = close,
	})
	x.Root.ZIndex = 6
	local xa = x.Root:FindFirstChildOfClass("UIAspectRatioConstraint")
	if xa then
		xa.AspectRatio = 1
	end
	if Theme.Icons.Close ~= "" then
		x.Label.Visible = false
	end
	scrim.Activated:Connect(close)

	self = {
		Root = win,
		Body = body,
		Scrim = scrim,
		open = function()
			Juice.open(win, scrim)
		end,
		close = close,
		onClosed = onClosed,
	}
	return self
end

------------------------------------------------------------------ Ribbon (section header)
function StudPop.Ribbon(parent: Instance, props: { text: string, variant: string, order: number? }): Frame
	local h = Instance.new("Frame")
	h.Name = "Ribbon_" .. props.text
	h.BackgroundTransparency = 1
	h.Size = UDim2.fromScale(1, 0.1)
	h.LayoutOrder = props.order or 0
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 10
	a.Parent = h
	local _, _, face = brick(h, props.variant, Theme.Radius.Sm)
	text(face, props.text:upper(), { display = true, maxPx = 28 }).ZIndex = 4
	h.Parent = parent
	return h
end

------------------------------------------------------------------ Grid (3 cols phone / 4 tablet / 5 desktop)
function StudPop.Grid(parent: Instance, order: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Grid"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order or 0
	local g = Instance.new("UIGridLayout")
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center
	g.CellPadding = UDim2.fromOffset(Theme.px(8), Theme.px(10))
	g.Parent = f
	local function cols()
		local cam = workspace.CurrentCamera
		local w = if cam then cam.ViewportSize.X else 844
		local n = if w < 900 then 3 elseif w < 1300 then 4 else 5
		g.CellSize = UDim2.new(1 / n, -Theme.px(8), 0, 0)
		local ar = g:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 0.72
		ar.Parent = g
	end
	cols()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(cols)
	end
	f.Parent = parent
	return f
end

------------------------------------------------------------------ ItemCard
export type ItemCardProps = {
	name: string,
	rarity: string, -- Theme.Rarity key
	mutation: string?, -- Theme.Mutation key
	income: number?, -- $/s from the server
	image: string?, -- static thumbnail captured from the Studio template
	discovered: boolean?, -- false => lock + "CATCH IT!"
	button: ButtonProps?,
	order: number?,
}

function StudPop.ItemCard(parent: Instance, props: ItemCardProps): Frame
	local rc = Theme.Rarity[props.rarity] or Theme.Rarity.Common
	local card = Instance.new("Frame")
	card.Name = "Card_" .. props.name
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.LayoutOrder = props.order or 0
	corner(card, Theme.Radius.Md)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Theme.Color.PanelHi, Theme.Color.Ink2)
	g.Parent = card
	local frame = stroke(card, Theme.Size.Stroke + 1)
	frame.Color = rc

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0.02, 0)
	list.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.05, 0)
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.Parent = card

	local thumb = Instance.new("ImageLabel")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.fromScale(1, 0.5)
	thumb.BackgroundColor3 = if props.discovered == false then Theme.Color.Ink2 else rc
	thumb.Image = if props.discovered == false then Theme.Icons.Lock else (props.image or "")
	thumb.ScaleType = Enum.ScaleType.Fit
	thumb.LayoutOrder = 1
	corner(thumb, UDim.new(0, Theme.px(10)))
	stroke(thumb, Theme.Size.Stroke)
	local ta = Instance.new("UIAspectRatioConstraint")
	ta.Parent = thumb
	thumb.Parent = card

	local line = 0.11
	text(card, if props.discovered == false then "???" else props.name, { size = UDim2.fromScale(1, line), maxPx = 18, order = 2 })
	if props.mutation and Theme.Mutation[props.mutation] then
		text(card, props.mutation:upper(), { size = UDim2.fromScale(1, line * 0.85), color = Theme.Mutation[props.mutation], maxPx = 16, order = 3 })
	end
	text(card, if props.discovered == false then "CATCH IT!" else props.rarity:upper(), {
		size = UDim2.fromScale(1, line * 0.85),
		color = if props.discovered == false then Theme.Color.TextMuted else rc,
		maxPx = 16,
		order = 4,
	})
	if props.income and props.discovered ~= false then
		text(card, "+$" .. Theme.abbreviate(props.income) .. "/s", { size = UDim2.fromScale(1, line * 0.85), color = Theme.Color.Cash, maxPx = 16, order = 5 })
	end
	if props.button then
		local b = table.clone(props.button)
		b.size = UDim2.fromScale(1, 0.16)
		b.order = 6
		local btn = StudPop.Button(card, b)
		local ba = btn.Root:FindFirstChildOfClass("UIAspectRatioConstraint")
		if ba then
			ba:Destroy()
		end
	end

	-- rarity effects (cheap tweens only)
	if props.discovered ~= false then
		if props.rarity == "Legendary" then
			-- shine needs clipping: wrap thumb, not the whole card, to keep text crisp
			thumb.ClipsDescendants = true
			Juice.shine(thumb)
		elseif props.rarity == "Mythic" or props.rarity == "Celestial" then
			Juice.pulse(frame, Theme.px(Theme.Size.Stroke + 1), Theme.px(Theme.Size.Stroke + 3))
		elseif props.rarity == "Secret" then
			local rg = Instance.new("UIGradient")
			rg.Parent = frame
			Juice.rainbow(rg)
		end
	end
	card.Parent = parent
	return card
end

------------------------------------------------------------------ CurrencyPill
export type Pill = { Root: Frame, Icon: ImageLabel?, set: (number) -> (), value: () -> number }

function StudPop.CurrencyPill(parent: Instance, props: { icon: string, value: number, plusVariant: string?, onPlus: (() -> ())?, order: number?, amountColor: Color3?, glow: Color3? }): Pill
	local root = Instance.new("Frame")
	root.Name = "Pill"
	root.BackgroundColor3 = Color3.new(1, 1, 1)
	root.Size = UDim2.fromScale(0.2, 0.1)
	root.LayoutOrder = props.order or 0
	corner(root, Theme.Radius.Pill)
	stroke(root, Theme.Size.Stroke)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromHex("#3A3F5C"), Theme.Color.Ink)
	g.Parent = root
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 3.6
	a.Parent = root
	local row = content(root, 0.03)
	local ic = icon(row, props.icon, 0)
	if ic then
		ic.Size = UDim2.fromScale(1, 1.25)
	end
	local current = props.value
	local amt = text(row, Theme.abbreviate(current), { display = true, color = props.amountColor, size = UDim2.fromScale(0.52, 1), maxPx = 30, order = 1 })
	if props.glow then
		-- soft coloured halo + occasional twinkle so the rare currency always feels valuable
		local haloF = Instance.new("Frame")
		haloF.Name = "Halo"
		haloF.BackgroundTransparency = 1
		haloF.Size = UDim2.fromScale(1, 1)
		haloF.ZIndex = 0
		corner(haloF, Theme.Radius.Pill)
		local halo = stroke(haloF, Theme.Size.Stroke + 5)
		halo.Color = props.glow
		halo.Transparency = 0.55
		haloF.Parent = root
		Juice.twinkleLoop(root, 2.5, Theme.Color.GemGlint)
	end
	if props.onPlus then
		local plus = StudPop.Button(row, { variant = props.plusVariant or "go", text = "+", icon = Theme.Icons.Plus, size = UDim2.fromScale(0.26, 1.1), order = 2, onClick = props.onPlus })
		local pa = plus.Root:FindFirstChildOfClass("UIAspectRatioConstraint")
		if pa then
			pa.AspectRatio = 1
		end
	end
	root.Parent = parent
	return {
		Root = root,
		Icon = ic,
		set = function(v: number)
			if v ~= current then
				Juice.countUp(amt, current, v)
				if v > current then
					Juice.pop(root, 1.1)
				end
				current = v
			end
		end,
		value = function()
			return current
		end,
	}
end

function StudPop.CashPill(parent: Instance, value: number, onPlus: (() -> ())?, order: number?): Pill
	return StudPop.CurrencyPill(parent, { icon = Theme.Icons.Cash, value = value, plusVariant = "go", onPlus = onPlus, order = order, amountColor = Theme.Color.Cash })
end

function StudPop.GemPill(parent: Instance, value: number, onPlus: (() -> ())?, order: number?): Pill
	return StudPop.CurrencyPill(parent, { icon = Theme.Icons.Gem, value = value, plusVariant = "gem", onPlus = onPlus, order = order, amountColor = Theme.Color.GemHi, glow = Theme.Color.Gem })
end

------------------------------------------------------------------ GemPack (Robux -> Gems ladder card)
-- `pack` is an entry of Theme.GemPacks; `tier` 1..#packs grows the pile, sparkle and glow.
function StudPop.GemPack(parent: Instance, pack: { robux: number, gems: number, bonus: number, tag: string? }, tier: number, onBuy: () -> ()): Frame
	local card = Instance.new("Frame")
	card.Name = "GemPack_" .. pack.gems
	card.BackgroundTransparency = 1
	card.LayoutOrder = tier
	local _, _, face = brick(card, "gem", Theme.Radius.Md)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0.02, 0)
	list.Parent = face
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.06, 0)
	pad.PaddingLeft = UDim.new(0.07, 0)
	pad.PaddingRight = UDim.new(0.07, 0)
	pad.Parent = face

	local pile = Instance.new("ImageLabel")
	pile.Name = "Pile"
	pile.BackgroundTransparency = 1
	pile.Image = Theme.Icons.Gem
	pile.ScaleType = Enum.ScaleType.Fit
	pile.Size = UDim2.fromScale(0.5 + 0.08 * tier, 0.34)
	pile.LayoutOrder = 1
	pile.ZIndex = 4
	pile.Parent = face

	text(face, Theme.abbreviate(pack.gems), { display = true, size = UDim2.fromScale(1, 0.16), maxPx = 30, order = 2 }).ZIndex = 4
	text(face, if pack.bonus > 0 then ("+" .. pack.bonus .. "% GEMS") else " ", { color = Theme.Color.Burst, size = UDim2.fromScale(1, 0.1), maxPx = 16, order = 3 }).ZIndex = 4
	local b = StudPop.Button(face, { variant = "robux", text = tostring(pack.robux), icon = Theme.Icons.Robux, size = UDim2.fromScale(1, 0.2), order = 4, onClick = onBuy })
	local ba = b.Root:FindFirstChildOfClass("UIAspectRatioConstraint")
	if ba then
		ba:Destroy()
	end
	if pack.tag then
		StudPop.Starburst(card, pack.tag, "burst", { size = UDim2.fromScale(0.62, 0.62), position = UDim2.fromScale(0.92, 0.02) })
	end
	if pack.tag == "BEST VALUE" then
		local halo = stroke(card, Theme.Size.Stroke + 4)
		halo.Color = Theme.Color.Gem
		halo.Transparency = 0.5
		Juice.twinkleLoop(face, 0.9, Theme.Color.GemGlint)
	end
	card.Parent = parent
	return card
end

------------------------------------------------------------------ ProgressBar
function StudPop.ProgressBar(parent: Instance, props: { variant: string, label: string?, frac: number, order: number? }): { Root: Frame, set: (number, string?) -> () }
	local root = Instance.new("Frame")
	root.Name = "Progress"
	root.BackgroundColor3 = Theme.Color.Ink2
	root.Size = UDim2.fromScale(0.9, 0.08)
	root.LayoutOrder = props.order or 0
	root.ClipsDescendants = true
	corner(root, Theme.Radius.Pill)
	stroke(root, Theme.Size.Stroke)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 10
	a.Parent = root
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = UDim2.fromScale(math.clamp(props.frac, 0, 1), 1)
	corner(fill, Theme.Radius.Pill)
	ramp(fill, Theme.ramp(props.variant))
	fill.Parent = root
	local lbl = text(root, props.label or "", { maxPx = 20 })
	lbl.ZIndex = 3
	root.Parent = parent
	-- Playtest Fixes 2 Part F (StableBars): move only on a real change, pop only on reaching full,
	-- hide fills too small to read.
	local stable = BarGuard.Enabled()
	local shown = math.clamp(props.frac, 0, 1)
	local shownLabel = props.label
	if stable then
		fill.Visible = BarGuard.FillVisible(shown)
	end
	return {
		Root = root,
		set = function(f: number, label: string?)
			local c = math.clamp(f, 0, 1)
			if stable then
				if not BarGuard.ShouldUpdate(shown, c, shownLabel, label) then
					return
				end
				local crossed = BarGuard.CrossedFull(shown, c)
				shown, shownLabel = c, label or shownLabel
				fill.Visible = BarGuard.FillVisible(c)
				Juice.play(fill, "fill", Theme.Motion.Fill, { Size = UDim2.fromScale(c, 1) })
				if label then
					lbl.Text = label
				end
				if crossed then
					Juice.pop(root, 1.08)
				end
				return
			end
			Juice.play(fill, "fill", Theme.Motion.Fill, { Size = UDim2.fromScale(c, 1) })
			if label then
				lbl.Text = label
			end
			if c >= 1 then
				Juice.pop(root, 1.08)
			end
		end,
	}
end

------------------------------------------------------------------ Toast (ESCAPED!, SNEAKY!)
local TOAST_COLOR = {
	go = Theme.Variant.go.hi,
	alert = Theme.Variant.alert.hi,
	stop = Theme.Variant.stop.hi,
	gem = Theme.Variant.gem.hi,
}
function StudPop.Toast(gui: ScreenGui, word: string, variant: string?)
	local t = Instance.new("TextLabel")
	t.Name = "Toast"
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.26)
	t.Size = UDim2.fromScale(0.7, 0.16)
	t.Rotation = -4
	t.Text = word:upper()
	t.FontFace = Theme.Font.Display
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.ZIndex = 90
	stroke(t, 5, Enum.ApplyStrokeMode.Contextual)
	local top = TOAST_COLOR[variant or "go"] or Theme.Color.Text
	local tg = Instance.new("UIGradient")
	tg.Rotation = 90
	tg.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(top, 0.35), top)
	tg.Parent = t
	Juice.sparkles(t, 3, if variant == "gem" then Theme.Color.GemGlint else nil)
	t.Parent = gui
	local s = Juice.scaleOf(t)
	s.Scale = 0.2
	Juice.play(s, "toast", TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	task.delay(1.1, function()
		local out = Juice.play(t, "toast", TweenInfo.new(0.3), { Position = UDim2.fromScale(0.5, 0.18), TextTransparency = 1 })
		local st = t:FindFirstChildOfClass("UIStroke")
		if st then
			Juice.play(st, "toast", TweenInfo.new(0.3), { Transparency = 1 })
		end
		out.Completed:Once(function()
			t:Destroy()
		end)
	end)
end

------------------------------------------------------------------ RewardReveal
-- anticipation -> flash -> rays -> creature pop -> text lines. Intensity by rarity.
-- Runs in its own thread; returns immediately.
function StudPop.RewardReveal(gui: ScreenGui, props: { name: string, rarity: string, mutation: string?, income: number?, image: string, rays: string? })
	task.spawn(StudPop._reveal, gui, props)
end

function StudPop._reveal(gui: ScreenGui, props: { name: string, rarity: string, mutation: string?, income: number?, image: string, rays: string? })
	local intensity = Theme.RarityIntensity[props.rarity] or 1
	local colour = (props.mutation and Theme.Mutation[props.mutation]) or Theme.Rarity[props.rarity] or Theme.Rarity.Common

	local root = Instance.new("Frame")
	root.Name = "Reveal"
	root.BackgroundColor3 = Theme.Color.Scrim
	root.BackgroundTransparency = Theme.ScrimTransparency
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 80
	root.Parent = gui

	local stage = Instance.new("Frame")
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.45)
	stage.Size = UDim2.fromScale(0.5, 0.5)
	local sa = Instance.new("UIAspectRatioConstraint")
	sa.Parent = stage
	stage.Parent = root

	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(0.2, 0.2)
	glow.BackgroundColor3 = colour
	glow.BackgroundTransparency = 0.3
	glow.ZIndex = 81
	corner(glow, Theme.Radius.Pill)
	glow.Parent = stage

	-- 1) anticipation
	Juice.shake(stage, 2 + intensity, 0.4)
	Juice.play(glow, "grow", TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(0.9, 0.9) })
	task.wait(0.4)

	-- 2) flash (Rare+)
	if intensity >= 2 then
		local flash = Instance.new("Frame")
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.Size = UDim2.fromScale(1, 1)
		flash.ZIndex = 95
		flash.Parent = root
		Juice.play(flash, "flash", TweenInfo.new(0.25), { BackgroundTransparency = 1 }).Completed:Once(function()
			flash:Destroy()
		end)
	end

	-- 3) rays (Epic+): supply a rays image (white, transparent bg) via props.rays
	if intensity >= 3 and props.rays and props.rays ~= "" then
		local rays = Instance.new("ImageLabel")
		rays.BackgroundTransparency = 1
		rays.Image = props.rays
		rays.ImageColor3 = colour
		rays.ImageTransparency = 0.4
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromScale(1.8, 1.8)
		rays.ZIndex = 81
		rays.Parent = stage
		Juice.play(rays, "spin", TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	end
	Juice.sound(if intensity >= 4 then "RewardBig" else "RewardSmall", 0)
	if intensity >= 4 then
		Juice.shake(root, 3, 0.15)
	end

	-- 4) creature pop
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Image = props.image
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.45)
	img.Size = UDim2.fromScale(0.8, 0.8)
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 85
	img.Parent = stage
	local s = Juice.scaleOf(img)
	s.Scale = 0
	Juice.play(s, "pop", TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })

	-- 5) text lines, in name-tag order
	local lines = Instance.new("Frame")
	lines.BackgroundTransparency = 1
	lines.AnchorPoint = Vector2.new(0.5, 0)
	lines.Position = UDim2.fromScale(0.5, 0.7)
	lines.Size = UDim2.fromScale(0.6, 0.26)
	lines.ZIndex = 86
	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ll.Parent = lines
	lines.Parent = root
	local spec: { { any } } = { { props.name:upper(), Theme.Color.Text, true } }
	if props.mutation then
		table.insert(spec, { props.mutation:upper(), colour, false })
	end
	table.insert(spec, { props.rarity:upper(), Theme.Rarity[props.rarity] or Theme.Color.Text, false })
	if props.income then
		table.insert(spec, { "+$" .. Theme.abbreviate(props.income) .. "/s", Theme.Color.Cash, false })
	end
	for i, l in spec do
		task.wait(0.06)
		local t = text(lines, l[1], { display = l[3], color = l[2], size = UDim2.fromScale(1, if l[3] then 0.34 else 0.22), maxPx = if l[3] then 44 else 26, order = i })
		t.ZIndex = 87
		Juice.pop(t, 1.15)
	end

	-- tap anywhere to dismiss (after 0.6 s)
	task.delay(0.6, function()
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 99
		hit.Parent = root
		hit.Activated:Once(function()
			root:Destroy()
		end)
	end)
end

------------------------------------------------------------------ Logo (original Brainrot Expedition wordmark)
-- Built only from UI instances. Line 1 "BRAINROT": gradient title fill, ink stroke, ink drop, -4 deg.
-- Line 2 "EXPEDITION": studded teal plate with a hot-pink stripe and ribbon tails. Accents: sparkles,
-- a compass star and (optional) a brainrot portrait peeking over the left corner.
-- Motion: twinkles + a slow 2 s breathe on the plate only; the letters never move.
export type Logo = { Root: Frame, destroy: () -> () }

function StudPop.Logo(parent: Instance, size: UDim2?, opts: { peekImage: string?, still: boolean? }?): Logo
	local o = opts or {}
	local root = Instance.new("Frame")
	root.Name = "StudPopLogo"
	root.BackgroundTransparency = 1
	root.Size = size or UDim2.fromScale(0.5, 0.3)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 2.15
	ar.Parent = root
	local cleanups: { () -> () } = {}

	-- optional portrait peeking over the top-left corner (behind the letters)
	if o.peekImage and o.peekImage ~= "" then
		local peek = Instance.new("ImageLabel")
		peek.Name = "Peek"
		peek.BackgroundTransparency = 1
		peek.Image = o.peekImage
		peek.ScaleType = Enum.ScaleType.Fit
		peek.AnchorPoint = Vector2.new(0.5, 0.5)
		peek.Position = UDim2.fromScale(0.15, 0.42)
		peek.Size = UDim2.fromScale(0.3, 0.66)
		peek.Rotation = -14
		peek.ZIndex = 1
		peek.Parent = root
	end

	-- line 1: BRAINROT (ink drop under a gradient-filled copy)
	local function word(z: number, offsetPx: number, fill: boolean): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = if fill then "Brainrot" else "BrainrotDrop"
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.new(0.5, 0, 0, offsetPx)
		t.Size = UDim2.fromScale(0.96, 0.56)
		t.Rotation = -4
		t.Text = "BRAINROT"
		t.FontFace = Theme.Font.Display
		t.TextScaled = true
		t.TextColor3 = if fill then Color3.new(1, 1, 1) else Theme.Color.Ink
		t.ZIndex = z
		local s = Instance.new("UIStroke")
		s.Color = Theme.Color.Ink
		s.Thickness = Theme.px(5)
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = t
		if fill then
			local g = Instance.new("UIGradient")
			g.Rotation = 90
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHex("#FFF6B0")),
				ColorSequenceKeypoint.new(0.45, Theme.Color.Burst),
				ColorSequenceKeypoint.new(1, Theme.Color.BurstLo),
			})
			g.Parent = t
		end
		t.Parent = root
		return t
	end
	word(3, Theme.px(6), false)
	word(4, 0, true)

	-- line 2: EXPEDITION plate with ribbon tails
	local plateHolder = Instance.new("Frame")
	plateHolder.Name = "PlateHolder"
	plateHolder.BackgroundTransparency = 1
	plateHolder.AnchorPoint = Vector2.new(0.5, 0)
	plateHolder.Position = UDim2.fromScale(0.5, 0.55)
	plateHolder.Size = UDim2.fromScale(0.78, 0.4)
	plateHolder.ZIndex = 5
	plateHolder.Parent = root

	for side = -1, 1, 2 do
		local tail = Instance.new("Frame")
		tail.Name = if side < 0 then "TailL" else "TailR"
		tail.BackgroundColor3 = Theme.Variant.brand.lo
		tail.BorderSizePixel = 0
		tail.AnchorPoint = Vector2.new(0.5, 0.5)
		tail.Position = UDim2.fromScale(0.5 + side * 0.55, 0.64)
		tail.Size = UDim2.fromScale(0.14, 0.62)
		tail.ZIndex = 1 -- behind the plate in Global and Sibling ZIndex modes
		corner(tail, Theme.Radius.Sm)
		stroke(tail, Theme.Size.Stroke)
		tail.Parent = plateHolder
		-- swallowtail notch
		local notch = Instance.new("Frame")
		notch.Name = "Notch"
		notch.BackgroundColor3 = Theme.Color.Ink
		notch.BorderSizePixel = 0
		notch.AnchorPoint = Vector2.new(0.5, 0.5)
		notch.Position = UDim2.fromScale(if side < 0 then 0 else 1, 0.5)
		notch.Size = UDim2.fromScale(0.42, 0.42)
		notch.Rotation = 45
		notch.ZIndex = 1
		notch.Parent = tail
	end

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundTransparency = 1
	plate.Size = UDim2.fromScale(1, 1)
	plate.ZIndex = 5
	plate.Parent = plateHolder
	local _, _, face = brick(plate, "brand", Theme.Radius.Md)
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.BackgroundColor3 = Theme.BrandStripe
	stripe.BorderSizePixel = 0
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.Position = UDim2.fromScale(0, 0.7)
	stripe.Size = UDim2.fromScale(1, 0.2)
	stripe.ZIndex = 2
	stripe.Parent = face
	local label = text(face, "EXPEDITION", { display = true, maxPx = 64, size = UDim2.fromScale(0.9, 0.78) })
	local floor = label:FindFirstChildOfClass("UITextSizeConstraint")
	if floor then
		floor:Destroy() -- logo lettering is art: always fit the plate
	end
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.48)
	label.ZIndex = 6
	local ls = label:FindFirstChildOfClass("UIStroke")
	if ls then
		ls.Thickness = Theme.px(4)
	end

	-- compass star on the plate's top-right corner
	local star = Instance.new("Frame")
	star.Name = "CompassStar"
	star.BackgroundTransparency = 1
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.fromScale(0.97, 0.06)
	star.Size = UDim2.fromScale(0.15, 0.15)
	star.ZIndex = 7
	local sa = Instance.new("UIAspectRatioConstraint")
	sa.Parent = star
	for i, spec in { { 1, Theme.Color.Ink }, { 0.78, Theme.Color.Burst } } do
		for k = 0, 3 do
			local arm = Instance.new("Frame")
			arm.BorderSizePixel = 0
			arm.AnchorPoint = Vector2.new(0.5, 0.5)
			arm.Position = UDim2.fromScale(0.5, 0.5)
			local long = k % 2 == 0
			arm.Size = UDim2.fromScale(0.28 * spec[1], (if long then 1 else 0.62) * spec[1])
			arm.Rotation = k * 45
			arm.BackgroundColor3 = spec[2]
			arm.ZIndex = 7 + i
			arm.Parent = star
		end
	end
	local starCore = Instance.new("Frame")
	starCore.BorderSizePixel = 0
	starCore.AnchorPoint = Vector2.new(0.5, 0.5)
	starCore.Position = UDim2.fromScale(0.5, 0.5)
	starCore.Size = UDim2.fromScale(0.34, 0.34)
	starCore.Rotation = 45
	starCore.BackgroundColor3 = Theme.Color.White
	starCore.ZIndex = 10
	stroke(starCore, 2)
	starCore.Parent = star
	star.Parent = root

	-- fixed sparkles (twinkle in place)
	local sparkleSpots = { { 0.03, 0.62, 0.09 }, { 0.95, 0.3, 0.07 }, { 0.62, 0.0, 0.06 } }
	local sparkles: { GuiObject } = {}
	for _, p in sparkleSpots do
		local sp: GuiObject
		if Theme.Images.Sparkle ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = Theme.Images.Sparkle
			sp = img
		else
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = Color3.new(1, 1, 1)
			f.Rotation = 45
			sp = f
		end
		sp.Name = "Sparkle"
		sp.AnchorPoint = Vector2.new(0.5, 0.5)
		sp.Position = UDim2.fromScale(p[1], p[2])
		sp.Size = UDim2.fromScale(p[3], p[3])
		sp.ZIndex = 12
		local spa = Instance.new("UIAspectRatioConstraint")
		spa.Parent = sp
		sp.Parent = root
		table.insert(sparkles, sp)
	end

	if not o.still then
		local plateScale = Juice.scaleOf(plateHolder)
		local breathe = Juice.play(plateScale, "breathe", TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.03 })
		table.insert(cleanups, function()
			breathe:Cancel()
		end)
		for i, sp in sparkles do
			local s = Juice.scaleOf(sp)
			local tw = Juice.play(s, "twinkle", TweenInfo.new(0.9 + i * 0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, i * 0.3), { Scale = 0.35 })
			table.insert(cleanups, function()
				tw:Cancel()
			end)
		end
	end

	root.Parent = parent
	return {
		Root = root,
		destroy = function()
			for _, f in cleanups do
				f()
			end
			root:Destroy()
		end,
	}
end

return StudPop
