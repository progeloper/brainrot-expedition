--!nocheck
-- "Stud Pop Plate" builders (owner-approved 12 Nov 2026) for MenusV2: stall shops, the HUD
-- Brainrots/Inventory windows and dialogs. Visual spec: design_reference/menus_v2/Menu_Concepts
-- (captures, source CSS, tokens_plate.json). Sizes are at the 844x390 baseline via Theme.px.
--
-- Rules carried from Stud Pop: one colour = one meaning; one breathing primary per window; ✕ top-right;
-- text >= 14 px with an ink stroke; taps >= 48 px; numbers come from config/server only.
--
-- Every ambient loop a window starts goes into its Bag and is cancelled on close (0 loops while closed).
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Juice = require(script.Parent.Juice)
local BarGuard = require(script.Parent.BarGuard)

local P = Theme.Plate
local px = Theme.px

local Plate = {}

------------------------------------------------------------------ cleanup bag
export type Bag = { add: (any) -> any, clean: () -> () }

function Plate.Bag(): Bag
	local items = {}
	local bag = {}
	function bag.add(x)
		table.insert(items, x)
		return x
	end
	function bag.clean()
		for i = #items, 1, -1 do
			local x = items[i]
			if typeof(x) == "Instance" then
				if x:IsA("Tween") then
					x:Cancel()
				else
					x:Destroy()
				end
			elseif typeof(x) == "RBXScriptConnection" then
				x:Disconnect()
			elseif type(x) == "function" then
				x()
			end
		end
		table.clear(items)
	end
	return bag
end

-- Low quality graphics or Reduced Motion: body particles and window sweeps are skipped.
function Plate.lowFx(): boolean
	if Juice.reduced() then
		return true
	end
	local ok, level = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel.Value
	end)
	return ok and level >= 1 and level <= 3
end

-- An endless tween (RepeatCount -1) registered on `bag`.
local function loop(bag: Bag?, inst: Instance, seconds: number, goal, reverses: boolean?, delay: number?, style: Enum.EasingStyle?)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, reverses ~= false, delay or 0),
		goal
	)
	t:Play()
	if bag then
		bag.add(t)
	end
	return t
end
Plate.loop = loop

------------------------------------------------------------------ primitives
local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px(r))
	c.Parent = inst
	return c
end

local function stroke(inst: GuiObject, thickness: number, color: Color3?, mode: Enum.ApplyStrokeMode?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or P.Color.Ink
	s.Thickness = math.max(1, thickness)
	s.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Transparency = transparency or 0
	s.Parent = inst
	return s
end

-- Vertical (rotation 90) or horizontal (0) gradient through 2–7 colours; 3-stop ramps put the middle at 60% (CSS).
local function gradient(inst: GuiObject, colors: { Color3 }, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	local keys = {}
	if #colors == 1 then
		keys = { ColorSequenceKeypoint.new(0, colors[1]), ColorSequenceKeypoint.new(1, colors[1]) }
	elseif #colors == 3 and (rotation == nil or rotation == 90) then
		keys = {
			ColorSequenceKeypoint.new(0, colors[1]),
			ColorSequenceKeypoint.new(0.6, colors[2]),
			ColorSequenceKeypoint.new(1, colors[3]),
		}
	else
		for i, c in colors do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
		end
	end
	g.Color = ColorSequence.new(keys)
	g.Parent = inst
	return g
end
Plate.gradient = gradient

local function frame(parent: Instance?, name: string, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	for k, v in props or {} do
		f[k] = v
	end
	f.Parent = parent
	return f
end
Plate.frame = frame

-- Tiled stud texture over a surface (rounded with the surface's radius).
local function tile(parent: GuiObject, image: string, tilePx: number, transparency: number, radius: number, z: number?)
	if image == "" then
		return nil
	end
	local t = Instance.new("ImageLabel")
	t.Name = "Studs"
	t.BackgroundTransparency = 1
	t.Image = image
	t.ImageTransparency = transparency
	t.ScaleType = Enum.ScaleType.Tile
	t.TileSize = UDim2.fromOffset(px(tilePx), px(tilePx))
	t.Size = UDim2.fromScale(1, 1)
	t.ZIndex = z or 1
	t.Active = false
	corner(t, radius)
	t.Parent = parent
	return t
end

-- 2 px inner white rim (~40%).
local function rim(parent: GuiObject, radius: number, z: number?)
	local r = frame(parent, "Rim", {
		Position = UDim2.fromOffset(px(2), px(2)),
		Size = UDim2.new(1, -px(4), 1, -px(4)),
		ZIndex = z or 2,
	})
	corner(r, math.max(1, radius - 1))
	stroke(r, px(2), Color3.new(1, 1, 1), nil, 0.6)
	return r
end

-- Text with the Plate stroke. `size` is the baseline px height; text scales down to `min` (>= 14).
function Plate.Label(parent: Instance, text: string, opts: {
	size: number?,
	min: number?,
	font: Font?,
	color: Color3?,
	strokePx: number?,
	align: Enum.TextXAlignment?,
	valign: Enum.TextYAlignment?,
	frameSize: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	z: number?,
	wrap: boolean?,
	order: number?,
	name: string?,
}?): TextLabel
	local o = opts or {}
	local t = Instance.new("TextLabel")
	t.Name = o.name or "Label"
	t.BackgroundTransparency = 1
	t.Text = text
	t.FontFace = o.font or P.Font.Label
	t.TextColor3 = o.color or P.Color.White
	t.TextScaled = true
	t.TextWrapped = o.wrap == true
	t.TextXAlignment = o.align or Enum.TextXAlignment.Center
	t.TextYAlignment = o.valign or Enum.TextYAlignment.Center
	t.Size = o.frameSize or UDim2.fromScale(1, 1)
	t.Position = o.position or UDim2.new()
	t.AnchorPoint = o.anchor or Vector2.zero
	t.ZIndex = o.z or 5
	t.LayoutOrder = o.order or 0
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = px(o.size or 18)
	c.MinTextSize = math.min(px(o.min or Theme.Size.MinText), c.MaxTextSize)
	c.Parent = t
	if (o.strokePx or P.Stroke.LabelText) > 0 then
		stroke(t, px(o.strokePx or P.Stroke.LabelText), P.Color.Ink, Enum.ApplyStrokeMode.Contextual)
	end
	t.Parent = parent
	return t
end

-- Heavy title with a 3 px ink drop under it (a second label offset down).
function Plate.Title(parent: Instance, text: string, opts: { size: number?, frameSize: UDim2?, align: Enum.TextXAlignment?, z: number?, order: number? }?): Frame
	local o = opts or {}
	local holder = frame(parent, "Title", { Size = o.frameSize or UDim2.fromScale(1, 1), LayoutOrder = o.order or 0, ZIndex = o.z or 6 })
	local drop = Plate.Label(holder, text, {
		size = o.size or 34,
		font = P.Font.Title,
		color = P.Color.Ink,
		strokePx = P.Stroke.TitleText,
		align = o.align,
		position = UDim2.fromOffset(0, px(3)),
		z = (o.z or 6),
		name = "Drop",
	})
	local fill = Plate.Label(holder, text, {
		size = o.size or 34,
		font = P.Font.Title,
		strokePx = P.Stroke.TitleText,
		align = o.align,
		z = (o.z or 6) + 1,
		name = "Fill",
	})
	holder:SetAttribute("Text", text)
	-- Instances can't hold custom functions: the setter is the second return value
	return holder, function(s: string)
		drop.Text, fill.Text = s, s
	end
end

local function icon(parent: Instance, image: string, size: UDim2, z: number?, order: number?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = image
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = size
	i.ZIndex = z or 5
	i.LayoutOrder = order or 0
	local a = Instance.new("UIAspectRatioConstraint")
	a.Parent = i
	i.Parent = parent
	return i
end
Plate.Icon = icon

-- Diagonal white bar that sweeps across a clipped surface every `every` seconds.
local function sweep(parent: GuiObject, bag: Bag?, every: number, strength: number?, z: number?, delay: number?)
	local bar = frame(parent, "Shine", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.4, 0.5),
		Size = UDim2.fromScale(0.22, 3),
		Rotation = 25,
		ZIndex = z or 4,
	})
	local g = Instance.new("UIGradient")
	g.Rotation = 0
	local peak = 1 - (strength or 0.45)
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = bar
	if Juice.reduced() then
		bar.Visible = false
		return bar
	end
	local travel = math.min(0.9, every * 0.35)
	local t = TweenService:Create(
		bar,
		TweenInfo.new(travel, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, false, math.max(0, every - travel)),
		{ Position = UDim2.fromScale(1.4, 0.5) }
	)
	if delay and delay > 0 then
		task.delay(delay, function()
			if bar.Parent then
				t:Play()
			end
		end)
	else
		t:Play()
	end
	if bag then
		bag.add(t)
	end
	return bar
end
Plate.sweep = sweep

-- A 4-point twinkle that grows/turns in place (ambient sparkle on cards and headers).
local function twinkle(parent: GuiObject, bag: Bag?, pos: UDim2, sizePx: number, delay: number, color: Color3?)
	if Theme.Images.Sparkle == "" or Juice.reduced() then
		return nil
	end
	local s = Instance.new("ImageLabel")
	s.Name = "Twinkle"
	s.BackgroundTransparency = 1
	s.Image = Theme.Images.Sparkle
	s.ImageColor3 = color or Color3.new(1, 1, 1)
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = pos
	s.Size = UDim2.fromOffset(px(sizePx), px(sizePx))
	s.ZIndex = 8
	s.Parent = parent
	local sc = Instance.new("UIScale")
	sc.Scale = 0.1
	sc.Parent = s
	loop(bag, sc, 1.1, { Scale = 1 }, true, delay)
	loop(bag, s, 2.2, { Rotation = 90 }, true, delay)
	return s
end
Plate.twinkle = twinkle

------------------------------------------------------------------ Button
export type ButtonProps = {
	variant: string, -- go | gem | robux | stop | info | alert | locked | tabOff
	text: string?,
	icon: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	order: number?,
	primary: boolean?, -- the ONE breathing button per window
	lockedReason: string?, -- shown with a lock when variant == "locked"
	textSize: number?,
	onClick: (() -> ())?,
	bag: Bag?,
	name: string?,
}
export type Button = {
	Root: TextButton,
	Face: Frame,
	Label: TextLabel?,
	setText: (string) -> (),
	setVariant: (string, string?) -> (),
	destroy: () -> (),
}

function Plate.Button(parent: Instance, props: ButtonProps): Button
	local lipPx = px(P.ButtonLip)
	local radius = P.Radius.Button
	local bag = props.bag or Plate.Bag()
	local root = Instance.new("TextButton")
	root.Name = props.name or ("Btn_" .. (props.text or props.variant))
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.Size = props.size
	root.Position = props.position or UDim2.new()
	root.AnchorPoint = props.anchor or Vector2.zero
	root.LayoutOrder = props.order or 0
	root.ZIndex = 5
	local minSize = Instance.new("UISizeConstraint")
	minSize.MinSize = Vector2.new(px(Theme.Size.TouchMin), px(Theme.Size.TouchMin) * 0.8)
	minSize.Parent = root

	local variant = props.variant
	local glow: ImageLabel? = nil
	if props.primary and Theme.Images.Glow ~= "" then
		glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.BackgroundTransparency = 1
		glow.Image = Theme.Images.Glow
		glow.ImageTransparency = 0.35
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.55)
		glow.Size = UDim2.fromScale(1.35, 2.1)
		glow.ZIndex = 4
		glow.Parent = root
	end
	local lip = frame(root, "Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Ink,
		Position = UDim2.fromOffset(0, lipPx),
		Size = UDim2.new(1, 0, 1, -lipPx),
		ZIndex = 5,
	})
	corner(lip, radius)
	local face = frame(root, "Face", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 1, -lipPx),
		ZIndex = 6,
		ClipsDescendants = true,
	})
	corner(face, radius)
	stroke(face, px(P.Stroke.Outline))
	local grad = gradient(face, P.Button[variant] or P.Button.info)
	tile(face, P.Tiles.Surface, 12, 0.55, radius, 6)
	rim(face, radius, 7)
	local shade = frame(face, "Shade", {
		BackgroundTransparency = 0.8,
		BackgroundColor3 = Color3.new(0, 0, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, px(3)),
		ZIndex = 6,
	})
	shade.Name = "Shade"
	if variant == "go" or variant == "robux" or variant == "gem" or variant == "info" or props.primary then
		sweep(face, bag, if props.primary then 2.6 else P.Motion.ButtonShine, if props.primary then 0.6 else 0.45, 7)
	end

	local row = frame(face, "Row", { Size = UDim2.fromScale(1, 1), ZIndex = 8 })
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, px(5))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(6))
	pad.PaddingRight = UDim.new(0, px(6))
	pad.PaddingTop = UDim.new(0, px(4))
	pad.PaddingBottom = UDim.new(0, px(4))
	pad.Parent = row

	local iconLabel: ImageLabel? = nil
	local label: TextLabel? = nil
	local function build()
		if iconLabel then
			iconLabel:Destroy()
			iconLabel = nil
		end
		local img = if variant == "locked" then Theme.Icons.Lock else props.icon
		if img and img ~= "" then
			iconLabel = icon(row, img, UDim2.fromScale(1, 0.95), 9, 1)
		end
		local text = if variant == "locked" and props.lockedReason then props.lockedReason else props.text
		if text and text ~= "" then
			if not label then
				label = Plate.Label(row, text, {
					size = props.textSize or 20,
					frameSize = UDim2.fromScale(if iconLabel then 0.68 else 0.96, 1),
					z = 9,
					order = 2,
				})
			else
				label.Text = text
				label.Size = UDim2.fromScale(if iconLabel then 0.68 else 0.96, 1)
			end
		elseif label then
			label:Destroy()
			label = nil
		end
	end
	build()

	-- press: the face drops onto the lip
	local function down()
		if variant == "locked" then
			return
		end
		face.Position = UDim2.fromOffset(0, lipPx)
		lip.Visible = false
	end
	local function up()
		face.Position = UDim2.new()
		lip.Visible = true
	end
	bag.add(root.MouseButton1Down:Connect(down))
	bag.add(root.MouseButton1Up:Connect(up))
	bag.add(root.MouseLeave:Connect(up))
	bag.add(Juice.bindHover(root))
	bag.add(root.Activated:Connect(function()
		if variant == "locked" then
			Juice.shake(root, 3, 0.18)
			Juice.sound("Error", 0)
			return
		end
		Juice.sound("Click")
		if iconLabel then
			Juice.iconBounce(iconLabel)
		end
		if (variant == "go" or variant == "robux" or variant == "gem") and not Juice.reduced() then
			Juice.sparkles(root, 2)
		end
		if props.onClick then
			props.onClick()
		end
	end))
	if props.primary and not Juice.reduced() then
		local sc = Juice.scaleOf(root)
		loop(bag, sc, P.Motion.PrimaryBreathe / 2, { Scale = 1.04 }, true)
	end

	root.Parent = parent
	local self: Button
	self = {
		Root = root,
		Face = face,
		Label = label,
		setText = function(s: string)
			props.text = s
			build()
		end,
		setVariant = function(v: string, reason: string?)
			variant = v
			props.lockedReason = reason or props.lockedReason
			grad:Destroy()
			grad = gradient(face, P.Button[v] or P.Button.info)
			build()
		end,
		destroy = function()
			if not props.bag then
				bag.clean()
			end
			root:Destroy()
		end,
	}
	return self
end

-- Convenience: price/action button with a currency icon.
function Plate.PriceButton(parent: Instance, variant: string, iconImage: string?, label: string, props: { [string]: any }): Button
	local p = table.clone(props)
	p.variant, p.icon, p.text = variant, iconImage, label
	return Plate.Button(parent, p)
end

function Plate.LockedButton(parent: Instance, reason: string, props: { [string]: any }): Button
	local p = table.clone(props)
	p.variant, p.lockedReason, p.text = "locked", reason, reason
	return Plate.Button(parent, p)
end

------------------------------------------------------------------ state well ("Equipped", "Driving", "Using", "Owned")
function Plate.StateWell(parent: Instance, text: string, props: { size: UDim2, position: UDim2?, anchor: Vector2?, order: number?, bag: Bag?, textSize: number? }): Frame
	local well = frame(parent, "Well_" .. text, {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Well,
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		LayoutOrder = props.order or 0,
		ZIndex = 5,
	})
	corner(well, P.Radius.Button)
	stroke(well, px(P.Stroke.Outline))
	local inner = frame(well, "PulseRim", { Position = UDim2.fromOffset(px(3), px(3)), Size = UDim2.new(1, -px(6), 1, -px(6)), ZIndex = 6 })
	corner(inner, 2)
	local glow = stroke(inner, px(3), P.Color.WellRim, nil, 0.1)
	if not Juice.reduced() then
		loop(props.bag, glow, P.Motion.InUsePulse / 2, { Transparency = 0.65 }, true)
	end
	local row = frame(well, "Row", { Size = UDim2.fromScale(1, 1), ZIndex = 7 })
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, px(4))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	icon(row, Theme.Icons.Check, UDim2.fromScale(0.7, 0.62), 8, 1)
	Plate.Label(row, text, { size = props.textSize or 18, frameSize = UDim2.fromScale(0.68, 0.9), z = 8, order = 2 })
	return well
end

------------------------------------------------------------------ gold stat pill
function Plate.StatPill(parent: Instance, text: string, props: { bag: Bag?, order: number?, height: number? }?): (Frame, TextLabel)
	local o = props or {}
	local h = px(o.height or 24)
	local pill = frame(parent, "StatPill", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(px(110), h),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = o.order or 0,
		ZIndex = 6,
		ClipsDescendants = true,
	})
	corner(pill, P.Radius.Pill)
	stroke(pill, px(P.Stroke.Outline))
	gradient(pill, P.StatPill)
	rim(pill, P.Radius.Pill, 7)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(9))
	pad.PaddingRight = UDim.new(0, px(9))
	pad.Parent = pill
	local label = Plate.Label(pill, text, { size = 16, frameSize = UDim2.fromScale(1, 1), z = 8 })
	label.TextScaled = false
	label.TextSize = px(16)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	sweep(pill, o.bag, P.Motion.StatPillShine, 0.5, 9)
	return pill, label
end

------------------------------------------------------------------ NEW! sticker and 2× starburst
function Plate.NewSticker(parent: GuiObject, bag: Bag?, text: string?): Frame
	local s = frame(parent, "NewSticker", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, px(10), 0, 0),
		Size = UDim2.fromOffset(px(40), px(18)),
		Rotation = -9,
		ZIndex = 20,
	})
	corner(s, 3)
	stroke(s, px(2))
	gradient(s, { Color3.fromHex("#FF4A4A"), Color3.fromHex("#E01E1E") })
	Plate.Label(s, text or "NEW!", { size = 14, min = 10, z = 21, strokePx = 2 })
	if not Juice.reduced() then
		local sc = Juice.scaleOf(s)
		loop(bag, s, P.Motion.Sticker / 2, { Rotation = 9 }, true)
		loop(bag, sc, P.Motion.Sticker / 2, { Scale = 1.1 }, true)
	end
	return s
end

-- Gold 20-point burst (rotated squares; no image) with a dark label, wobbling.
function Plate.Starburst(parent: GuiObject, text: string, bag: Bag?, props: { size: number?, position: UDim2? }?): Frame
	local o = props or {}
	local holder = frame(parent, "Starburst", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = o.position or UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(px(o.size or 30), px(o.size or 30)),
		ZIndex = 20,
	})
	for i = 0, 4 do
		local sq = frame(holder, "Ray" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = if i % 2 == 0 then Color3.fromHex("#FFE14A") else Color3.fromHex("#FF9A1F"),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.72, 0.72),
			Rotation = i * 18,
			ZIndex = 20,
		})
		stroke(sq, 1)
	end
	Plate.Label(holder, text, { size = 15, min = 12, color = P.Color.Ink, strokePx = 0, z = 22, font = P.Font.Title })
	if not Juice.reduced() then
		local sc = Juice.scaleOf(holder)
		loop(bag, holder, P.Motion.Sticker / 2, { Rotation = 9 }, true)
		loop(bag, sc, P.Motion.Sticker / 2, { Scale = 1.1 }, true)
		holder.Rotation = -9
	end
	return holder
end

------------------------------------------------------------------ striped progress bar
function Plate.StripedProgress(parent: Instance, props: { frac: number, text: string?, size: UDim2, position: UDim2?, order: number?, bag: Bag?, colors: { Color3 }? }): { Root: Frame, set: (number, string?) -> () }
	local track = frame(parent, "Progress", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Ink,
		Size = props.size,
		Position = props.position or UDim2.new(),
		LayoutOrder = props.order or 0,
		ZIndex = 5,
	})
	corner(track, 3)
	stroke(track, px(2))
	local fill = frame(track, "Fill", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(math.clamp(props.frac, 0, 1), 1),
		ZIndex = 6,
		ClipsDescendants = true,
	})
	corner(fill, 3)
	gradient(fill, props.colors or { Color3.fromHex("#7CC8FF"), Color3.fromHex("#3A9DFF"), Color3.fromHex("#1E6BFF") })
	if P.Tiles.Stripes ~= "" then
		local stripes = Instance.new("ImageLabel")
		stripes.Name = "Stripes"
		stripes.BackgroundTransparency = 1
		stripes.Image = P.Tiles.Stripes
		stripes.ImageTransparency = 0.6
		stripes.ScaleType = Enum.ScaleType.Tile
		stripes.TileSize = UDim2.fromOffset(px(29), px(29))
		stripes.Size = UDim2.new(1, px(29), 1, 0)
		stripes.Position = UDim2.fromOffset(-px(29), 0)
		stripes.ZIndex = 7
		stripes.Parent = fill
		if not Juice.reduced() then
			if BarGuard.Enabled() then
				-- Playtest Fixes 2 F: screens rebuild their bars on every update; start the scroll at
				-- the clock's phase so a rebuilt bar continues instead of jumping back.
				local phase = BarGuard.Phase(os.clock(), 0.9)
				stripes.Position = UDim2.fromOffset(-px(29) * (1 - phase), 0)
				local first = TweenService:Create(
					stripes,
					TweenInfo.new(0.9 * (1 - phase), Enum.EasingStyle.Linear),
					{ Position = UDim2.new() }
				)
				first.Completed:Once(function(state)
					if state == Enum.PlaybackState.Completed and stripes.Parent then
						stripes.Position = UDim2.fromOffset(-px(29), 0)
						loop(props.bag, stripes, 0.9, { Position = UDim2.new() }, false, 0, Enum.EasingStyle.Linear)
					end
				end)
				first:Play()
				if props.bag then
					props.bag.add(first)
				end
			else
				loop(props.bag, stripes, 0.9, { Position = UDim2.new() }, false, 0, Enum.EasingStyle.Linear)
			end
		end
	end
	local label = Plate.Label(track, props.text or "", { size = 15, z = 8 })
	local stable = BarGuard.Enabled()
	local shown = math.clamp(props.frac, 0, 1)
	local shownText = props.text
	if stable then
		fill.Visible = BarGuard.FillVisible(shown)
	end
	return {
		Root = track,
		set = function(f: number, text: string?)
			local c = math.clamp(f, 0, 1)
			if stable then
				if not BarGuard.ShouldUpdate(shown, c, shownText, text) then
					return
				end
				shown, shownText = c, text or shownText
				fill.Visible = BarGuard.FillVisible(c)
			end
			TweenService:Create(fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(c, 1) }):Play()
			if text then
				label.Text = text
			end
		end,
	}
end

------------------------------------------------------------------ power pips plaque ("Power ▮▮▯▯…")
function Plate.Pips(parent: Instance, labelText: string, lit: number, total: number, props: { size: UDim2, order: number?, litColor: Color3?, offColor: Color3? }): Frame
	local plaque = frame(parent, "Plaque", {
		BackgroundTransparency = 0.15,
		BackgroundColor3 = P.Color.Ink,
		Size = props.size,
		LayoutOrder = props.order or 0,
		ZIndex = 6,
	})
	corner(plaque, 3)
	stroke(plaque, px(2), Color3.fromHex("#3A3D50"))
	local row = frame(plaque, "Row", { Size = UDim2.fromScale(1, 1), ZIndex = 7 })
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, px(2))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	Plate.Label(row, labelText, { size = 15, min = 14, frameSize = UDim2.fromScale(0.36, 0.9), z = 8, order = 0, align = Enum.TextXAlignment.Left })
	for i = 1, total do
		local pip = frame(row, "Pip" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = if i <= lit then (props.litColor or Color3.fromHex("#FFE14A")) else (props.offColor or Color3.fromHex("#3B2F8F")),
			Size = UDim2.new(0, px(5), 0.52, 0),
			LayoutOrder = i,
			ZIndex = 8,
		})
		corner(pip, 2)
		stroke(pip, 1)
	end
	return plaque
end

------------------------------------------------------------------ item card
export type CardProps = {
	name: string,
	sub: string?,
	image: string?, -- display shot (rbxassetid) or "" for a labelled placeholder
	background: { Color3 }, -- Theme.Plate.Tier.* colours
	rainbow: boolean?, -- T8: diagonal multi-stop
	radial: boolean?, -- T7: dark centre falloff
	rays: boolean?, -- rotating rays behind the item (T3+ / Legendary+)
	ring: Color3?, -- rarity ring (brainrot cards)
	size: UDim2,
	index: number?, -- stagger order for the pop-in
	order: number?,
	bag: Bag,
	imageHeight: number?, -- fraction of card height for the item image
	compact: boolean?, -- small grid card (sell/brainrots): name under image
	onClick: (() -> ())?,
	pop: boolean?, -- false: no pop-in (refreshes); default pops in, staggered by index
}
export type Card = { Root: Frame, Inner: Frame, Footer: Frame, Image: ImageLabel? }

function Plate.ItemCard(parent: Instance, props: CardProps): Card
	local bag = props.bag
	-- layout slot (stays still) + inner card (animates)
	local slot = frame(parent, "Card_" .. props.name, { Size = props.size, LayoutOrder = props.order or props.index or 0, ZIndex = 5 })
	local outer = frame(slot, "Outer", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.CardFrame,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})
	corner(outer, P.Radius.Card)
	stroke(outer, px(P.Stroke.Outline), props.ring or P.Color.Ink)
	local inner = frame(outer, "Inner", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(px(3), px(3)),
		Size = UDim2.new(1, -px(6), 1, -px(6)),
		ZIndex = 5,
		ClipsDescendants = true,
	})
	corner(inner, P.Radius.Card - 1)
	if props.rainbow then
		gradient(inner, props.background, 35)
	else
		gradient(inner, props.background)
	end
	if props.radial then
		local vignette = frame(inner, "Vignette", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5 })
		if Theme.Images.Glow ~= "" then
			local g = Instance.new("ImageLabel")
			g.BackgroundTransparency = 1
			g.Image = Theme.Images.Glow
			g.ImageColor3 = Color3.fromHex("#DBD6E7")
			g.ImageTransparency = 0.25
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Position = UDim2.fromScale(0.5, 0.45)
			g.Size = UDim2.fromScale(1.4, 1.1)
			g.ZIndex = 5
			g.Parent = vignette
		end
	end
	tile(inner, P.Tiles.Surface, P.Tiles.SurfaceTile, 0.6, P.Radius.Card - 1, 5)

	local header: Frame
	local imageArea: Frame
	local footer: Frame
	if props.compact then
		imageArea = frame(inner, "ImageArea", { Size = UDim2.fromScale(1, props.imageHeight or 0.55), ZIndex = 6 })
		header = frame(inner, "Header", { Position = UDim2.fromScale(0, props.imageHeight or 0.55), Size = UDim2.fromScale(1, 0.25), ZIndex = 9 })
		footer = frame(inner, "Footer", { Position = UDim2.fromScale(0, 0.8), Size = UDim2.fromScale(1, 0.2), ZIndex = 9 })
		Plate.Label(header, props.name, { size = 15, min = 14, wrap = true, frameSize = UDim2.new(1, -px(6), 1, 0), position = UDim2.fromOffset(px(3), 0), z = 9 })
	else
		header = frame(inner, "Header", { Size = UDim2.fromScale(1, 0.2), ZIndex = 9 })
		Plate.Label(header, props.name, { size = 20, frameSize = UDim2.new(1, -px(6), 0.62, 0), position = UDim2.fromOffset(px(3), px(2)), z = 9, font = P.Font.Title })
		if props.sub then
			Plate.Label(header, props.sub, { size = 15, min = 14, frameSize = UDim2.new(1, -px(6), 0.38, 0), position = UDim2.new(0, px(3), 0.62, 0), z = 9 })
		end
		local ih = props.imageHeight or 0.48
		imageArea = frame(inner, "ImageArea", { Position = UDim2.fromScale(0, 0.2), Size = UDim2.fromScale(1, ih), ZIndex = 6 })
		footer = frame(inner, "Footer", { Position = UDim2.fromScale(0, 0.2 + ih), Size = UDim2.fromScale(1, 1 - 0.2 - ih), ZIndex = 9 })
	end
	local fl = Instance.new("UIListLayout")
	fl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	fl.VerticalAlignment = Enum.VerticalAlignment.Center
	fl.SortOrder = Enum.SortOrder.LayoutOrder
	fl.Padding = UDim.new(0, px(4))
	fl.Parent = footer

	if props.rays and Theme.Images.Rays ~= "" then
		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.BackgroundTransparency = 1
		rays.Image = Theme.Images.Rays
		rays.ImageTransparency = 0.55
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromScale(1.6, 1.6)
		rays.ZIndex = 6
		local ra = Instance.new("UIAspectRatioConstraint")
		ra.Parent = rays
		rays.Parent = imageArea
		if not Juice.reduced() then
			loop(bag, rays, P.Motion.Rays, { Rotation = 360 }, false, 0, Enum.EasingStyle.Linear)
		end
	end
	local img: ImageLabel? = nil
	if props.image and props.image ~= "" then
		img = Instance.new("ImageLabel")
		img.Name = "Shot"
		img.BackgroundTransparency = 1
		img.Image = props.image
		img.ScaleType = Enum.ScaleType.Fit
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(0.92, 0.92)
		img.ZIndex = 7
		img.Parent = imageArea
		if not Juice.reduced() then
			local d = ((props.index or 0) % 5) * 0.3
			loop(bag, img, P.Motion.ItemBob / 2, { Position = UDim2.new(0.5, 0, 0.5, -px(P.Motion.ItemBobPx)), Rotation = 3 }, true, d)
			img.Rotation = -3
		end
	else
		Plate.Label(imageArea, "TODO SHOT", { size = 14, color = Color3.fromHex("#FFD447"), z = 7 })
	end

	-- glint + twinkles
	sweep(inner, bag, P.Motion.CardGlint, 0.5, 10, ((props.index or 0) % 4) * 0.5)
	twinkle(inner, bag, UDim2.fromScale(0.82, if props.compact then 0.12 else 0.3), 12, ((props.index or 0) % 3) * 0.4)
	twinkle(inner, bag, UDim2.fromScale(0.18, if props.compact then 0.45 else 0.62), 9, 0.9 + ((props.index or 0) % 3) * 0.3)

	if props.onClick then
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 12
		hit.Parent = outer
		bag.add(hit.Activated:Connect(function()
			Juice.sound("Click")
			Juice.pop(outer, 1.06)
			props.onClick()
		end))
	end

	-- staggered pop-in: scale 0.6 -> 1 and rise 12 px, Back
	if props.pop ~= false and not Juice.reduced() then
		local sc = Juice.scaleOf(outer)
		sc.Scale = 0.6
		outer.Position = UDim2.fromOffset(0, px(P.Motion.CardRisePx))
		local delayS = (props.index or 0) * P.Motion.CardStagger
		task.delay(delayS, function()
			if outer.Parent then
				TweenService:Create(sc, P.Motion.CardPop, { Scale = 1 }):Play()
				TweenService:Create(outer, P.Motion.CardPop, { Position = UDim2.new() }):Play()
			end
		end)
	end
	return { Root = slot, Inner = inner, Footer = footer, Image = img, Outer = outer, Header = header, ImageArea = imageArea }
end

------------------------------------------------------------------ tabs
export type Tab = { id: string, text: string, variant: string?, new: boolean?, icon: string? }
function Plate.Tabs(parent: Instance, props: { tabs: { Tab }, active: string, onSelect: (string) -> (), bag: Bag, hint: string?, tabWidth: number? }): { Root: Frame, setActive: (string) -> (), setHint: (string) -> () }
	local root = frame(parent, "Tabs", { Size = UDim2.new(1, 0, 0, px(36)), ZIndex = 6 })
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, px(8))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = root
	local buttons = {}
	local active = props.active
	local function variantFor(t: Tab): string
		if t.id == active then
			return t.variant or "info"
		end
		return if t.variant == "alert" then "alert" else "tabOff"
	end
	for i, t in props.tabs do
		local b = Plate.Button(root, {
			variant = variantFor(t),
			text = t.text,
			icon = t.icon,
			size = UDim2.fromOffset(px(props.tabWidth or 104), px(36)),
			order = i,
			textSize = 18,
			bag = props.bag,
			name = "Tab_" .. t.id,
			onClick = function()
				props.onSelect(t.id)
			end,
		})
		if t.new then
			Plate.NewSticker(b.Root, props.bag)
		end
		buttons[t.id] = { button = b, tab = t }
	end
	local hint = Plate.Label(root, props.hint or "", {
		size = 15,
		min = 14,
		color = P.Color.Hint,
		align = Enum.TextXAlignment.Right,
		frameSize = UDim2.new(1, -(#props.tabs * (px(props.tabWidth or 104) + px(8))), 1, 0),
		order = 99,
		z = 6,
	})
	return {
		Root = root,
		setActive = function(id: string)
			active = id
			for _, e in buttons do
				e.button.setVariant(variantFor(e.tab))
			end
		end,
		setHint = function(s: string)
			hint.Text = s
		end,
	}
end

------------------------------------------------------------------ window
export type WindowProps = {
	key: string, -- Theme.Plate.Header key
	title: string,
	icon: string?,
	stat: string?,
	aspect: number?,
	widthScale: number?,
	heightScale: number?,
	maxSize: Vector2?, -- baseline px
	particles: string?, -- "bills" | "streaks"
	onClose: (() -> ())?,
	closeOnScrim: boolean?,
	zIndex: number?, -- base ZIndex (dialogs over windows use a higher one)
	destroyOnClose: boolean?, -- one-shot dialogs remove themselves after the close animation
}
export type Window = {
	Root: Frame,
	Content: Frame,
	Header: Frame,
	bag: Bag, -- content loops (cleared by clearContent and close)
	setStat: (string?) -> (),
	setTitle: (string) -> (),
	clearContent: () -> (),
	contentSize: () -> Vector2,
	open: () -> (),
	close: (boolean?) -> (),
	isOpen: () -> boolean,
	destroy: () -> (),
}

function Plate.Window(gui: ScreenGui, props: WindowProps): Window
	local winBag = Plate.Bag() -- window-level ambient loops (header, body FX)
	local contentBag = Plate.Bag() -- cards/buttons built by the screen
	local isOpen = false

	local scrim = Instance.new("TextButton")
	scrim.Name = props.key .. "_Scrim"
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.BackgroundColor3 = Theme.Color.Scrim
	scrim.BackgroundTransparency = 1
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Visible = false
	scrim.ZIndex = props.zIndex or 1
	scrim.Parent = gui

	local holder = frame(gui, props.key .. "_Window", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(props.widthScale or 0.88, props.heightScale or 0.86),
		Visible = false,
		ZIndex = (props.zIndex or 1) + 1,
	})
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = props.aspect or 2.2
	ar.Parent = holder
	local max = props.maxSize or Vector2.new(742, 337)
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(px(max.X), px(max.Y))
	cap.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Name = "OpenScale"
	scale.Parent = holder

	-- frame: bottom lip, ink 3 -> grey 3 -> ink 3 -> body
	local L = px(P.FrameLayers)
	local lip = frame(holder, "BottomLip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Ink,
		Position = UDim2.fromOffset(0, px(P.BottomLip)),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})
	corner(lip, P.Radius.Window)
	local outer = frame(holder, "Outer", { BackgroundTransparency = 0, BackgroundColor3 = P.Color.Ink, Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	corner(outer, P.Radius.Window)
	local grey = frame(outer, "Grey", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.FrameGrey,
		Position = UDim2.fromOffset(L, L),
		Size = UDim2.new(1, -2 * L, 1, -2 * L),
		ZIndex = 2,
	})
	corner(grey, P.Radius.Window - 1)
	local ink2 = frame(grey, "Ink", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Ink,
		Position = UDim2.fromOffset(L, L),
		Size = UDim2.new(1, -2 * L, 1, -2 * L),
		ZIndex = 2,
	})
	corner(ink2, P.Radius.Window - 1)
	local body = frame(ink2, "Body", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.WindowBody,
		Position = UDim2.fromOffset(L, L),
		Size = UDim2.new(1, -2 * L, 1, -2 * L),
		ZIndex = 2,
		ClipsDescendants = true,
	})
	corner(body, P.Radius.Window - 2)
	tile(body, P.Tiles.Body, P.Tiles.BodyTile, 0.35, P.Radius.Window - 2, 2)

	-- body FX layer (behind content)
	local fx = frame(body, "BodyFx", { Size = UDim2.fromScale(1, 1), ZIndex = 3 })

	-- header bar
	local headerH = px(46)
	local header = frame(body, "Header", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, headerH),
		ZIndex = 10,
		ClipsDescendants = true,
	})
	gradient(header, P.Header[props.key] or P.Header.Dialog, 0)
	tile(header, P.Tiles.Surface, P.Tiles.SurfaceTile, 0.45, 0, 10)
	local headerLine = frame(header, "Line", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Ink,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, px(3)),
		ZIndex = 11,
	})
	headerLine.Name = "Line"
	local left = frame(header, "Left", { Position = UDim2.fromOffset(px(10), 0), Size = UDim2.new(1, -px(70), 1, -px(3)), ZIndex = 12 })
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.VerticalAlignment = Enum.VerticalAlignment.Center
	ll.Padding = UDim.new(0, px(8))
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = left
	local iconHolder = frame(left, "IconHolder", { Size = UDim2.fromOffset(px(34), px(34)), LayoutOrder = 1, ZIndex = 12 })
	local headerIcon: ImageLabel? = nil
	if props.icon and props.icon ~= "" then
		headerIcon = icon(iconHolder, props.icon, UDim2.fromScale(1, 1), 13)
		headerIcon.AnchorPoint = Vector2.new(0.5, 1)
		headerIcon.Position = UDim2.fromScale(0.5, 1)
		local a = headerIcon:FindFirstChildOfClass("UIAspectRatioConstraint")
		if a then
			a:Destroy() -- squash/stretch changes the aspect
		end
	end
	local titleSlot = frame(left, "TitleSlot", { Size = UDim2.fromOffset(px(10), px(40)), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 12 })
	local title, setTitleText = Plate.Title(titleSlot, props.title, { size = 32, z = 13, align = Enum.TextXAlignment.Left })
	title.Size = UDim2.fromScale(0, 1)
	title.AutomaticSize = Enum.AutomaticSize.X
	for _, l in title:GetChildren() do
		if l:IsA("TextLabel") then
			l.TextScaled = false
			l.TextSize = px(32)
			l.AutomaticSize = Enum.AutomaticSize.X
			l.Size = UDim2.fromScale(0, 1)
		end
	end
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title
	local statPill, statLabel = Plate.StatPill(left, props.stat or "", { bag = winBag, order = 3 })
	statPill.Visible = props.stat ~= nil and props.stat ~= ""

	local closeBtn = Plate.Button(header, {
		variant = "stop",
		icon = Theme.Icons.Close,
		size = UDim2.fromOffset(px(40), px(36)),
		position = UDim2.new(1, -px(8), 0.5, -px(2)),
		anchor = Vector2.new(1, 0.5),
		name = "Close",
		onClick = function()
			if props.onClose then
				props.onClose()
			end
		end,
	})
	closeBtn.Root.ZIndex = 14

	local content = frame(body, "Content", {
		Position = UDim2.fromOffset(px(10), headerH + px(8)),
		Size = UDim2.new(1, -px(20), 1, -(headerH + px(14))),
		ZIndex = 5,
	})

	if props.closeOnScrim ~= false then
		scrim.Activated:Connect(function()
			if props.onClose then
				props.onClose()
			end
		end)
	end

	local function startAmbient()
		local low = Plate.lowFx()
		-- header: icon hop, title idle, shine + twinkles
		if headerIcon and not Juice.reduced() then
			loop(winBag, headerIcon, P.Motion.HeaderIconHop / 2, {
				Size = UDim2.fromScale(0.87, 1.15),
				Position = UDim2.new(0.5, 0, 1, -px(7)),
			}, true)
		end
		if not Juice.reduced() then
			loop(winBag, titleScale, P.Motion.TitleIdle / 2, { Scale = 1.05 }, true)
			loop(winBag, title, P.Motion.TitleIdle / 2, { Rotation = -1.5 }, true)
		end
		winBag.add(sweep(header, winBag, P.Motion.HeaderShine, 0.42, 11))
		for i = 1, 3 do
			local tw = twinkle(header, winBag, UDim2.fromScale(0.35 + i * 0.16, 0.25 + (i % 2) * 0.45), 10, i * 0.6)
			if tw then
				winBag.add(tw)
			end
		end
		-- body: sunburst + drifting sparkles/bricks + falling bills/streaks + sweep
		if Theme.Images.Rays ~= "" then
			local burst = Instance.new("ImageLabel")
			burst.Name = "Sunburst"
			burst.BackgroundTransparency = 1
			burst.Image = Theme.Images.Rays
			burst.ImageTransparency = 0.9
			burst.AnchorPoint = Vector2.new(0.5, 0.5)
			burst.Position = UDim2.fromScale(0.5, 0.55)
			burst.Size = UDim2.fromScale(1.3, 1.3)
			burst.ZIndex = 3
			local a = Instance.new("UIAspectRatioConstraint")
			a.Parent = burst
			burst.Parent = fx
			winBag.add(burst)
			if not Juice.reduced() then
				loop(winBag, burst, P.Motion.BodySunburst, { Rotation = 360 }, false, 0, Enum.EasingStyle.Linear)
			end
		end
		if low then
			return
		end
		local rng = Random.new()
		for i = 1, P.Motion.BodyParticles do
			local kind = i % 3
			local p: GuiObject
			if kind == 0 and Theme.Images.Sparkle ~= "" then
				local s = Instance.new("ImageLabel")
				s.BackgroundTransparency = 1
				s.Image = Theme.Images.Sparkle
				s.ImageTransparency = 0.3
				p = s
			else
				p = frame(nil, "Bit", {
					BackgroundTransparency = 0.3,
					BackgroundColor3 = ({ Color3.fromHex("#FFE14A"), Color3.fromHex("#6DF6FF"), Color3.fromHex("#FF7AD0"), Color3.fromHex("#8DFF3A") })[(i % 4) + 1],
					Rotation = rng:NextInteger(0, 45),
				})
				if kind == 2 then
					corner(p :: GuiObject, 6)
				end
			end
			local sz = px(rng:NextInteger(5, 10))
			p.Name = "Particle"
			p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.Position = UDim2.fromScale(rng:NextNumber(0.04, 0.96), rng:NextNumber(0.25, 0.95))
			p.Size = UDim2.fromOffset(sz, sz)
			p.ZIndex = 3
			p.Parent = fx
			winBag.add(p)
			loop(winBag, p, rng:NextNumber(5, 12) / 2, {
				Position = p.Position - UDim2.fromOffset(0, px(19)),
				Rotation = p.Rotation + 30,
			}, true, rng:NextNumber(0, 2))
		end
		if props.particles == "bills" or props.particles == "streaks" then
			for i = 1, 8 do
				local b: GuiObject
				if props.particles == "bills" and Theme.Icons.Cash ~= "" then
					local im = Instance.new("ImageLabel")
					im.BackgroundTransparency = 1
					im.Image = Theme.Icons.Cash
					im.ImageTransparency = 0.25
					im.Size = UDim2.fromOffset(px(18), px(18))
					b = im
				else
					b = frame(nil, "Streak", {
						BackgroundTransparency = 0.55,
						BackgroundColor3 = Color3.new(1, 1, 1),
						Size = UDim2.fromOffset(px(rng:NextInteger(40, 90)), px(2)),
					})
				end
				b.Name = "Fall"
				b.ZIndex = 3
				b.Parent = fx
				winBag.add(b)
				local dur = rng:NextNumber(3.5, 7)
				if props.particles == "bills" then
					local x = rng:NextNumber(0.05, 0.95)
					b.Position = UDim2.new(x, 0, 0, -px(30))
					loop(winBag, b, dur, { Position = UDim2.new(x, 0, 1, px(30)), Rotation = 220 }, false, i * 0.6, Enum.EasingStyle.Linear)
				else
					local y = rng:NextNumber(0.15, 0.95)
					b.Position = UDim2.new(1, px(20), y, 0)
					loop(winBag, b, dur * 0.4, { Position = UDim2.new(0, -px(100), y, 0) }, false, i * 0.5, Enum.EasingStyle.Linear)
				end
			end
		end
		winBag.add(sweep(body, winBag, P.Motion.BodySweep, 0.16, 4))
	end

	local self: Window
	self = {
		Root = holder,
		Content = content,
		Header = header,
		bag = contentBag,
		setStat = function(s: string?)
			statPill.Visible = s ~= nil and s ~= ""
			statLabel.Text = s or ""
		end,
		setTitle = function(s: string)
			setTitleText(s)
		end,
		-- Content size without the open/close scale (screens size cards while the window pops in).
		contentSize = function(): Vector2
			local k = if scale.Scale > 0.05 then scale.Scale else 1
			return content.AbsoluteSize / k
		end,
		clearContent = function()
			contentBag.clean()
			content:ClearAllChildren()
		end,
		isOpen = function()
			return isOpen
		end,
		open = function()
			if isOpen then
				return
			end
			isOpen = true
			scrim.Visible, holder.Visible = true, true
			scrim.BackgroundTransparency = 1
			TweenService:Create(scrim, TweenInfo.new(0.2), { BackgroundTransparency = Theme.ScrimTransparency }):Play()
			if Juice.reduced() then
				scale.Scale = 1
			else
				scale.Scale = 0.8
				TweenService:Create(scale, P.Motion.WindowOpen, { Scale = 1 }):Play()
				titleSlot.Position = UDim2.fromOffset(0, -px(P.Motion.TitleDropPx))
				title.Position = UDim2.fromOffset(0, -px(P.Motion.TitleDropPx))
				TweenService:Create(title, P.Motion.TitleDrop, { Position = UDim2.new() }):Play()
			end
			Juice.sound("Click")
			startAmbient()
		end,
		close = function(instant: boolean?)
			if not isOpen then
				return
			end
			isOpen = false
			local function finish()
				if isOpen then
					return
				end
				holder.Visible, scrim.Visible = false, false
				winBag.clean()
				contentBag.clean()
				content:ClearAllChildren()
				if props.destroyOnClose then
					holder:Destroy()
					scrim:Destroy()
				end
			end
			if instant or Juice.reduced() then
				finish()
				return
			end
			TweenService:Create(scrim, P.Motion.WindowClose, { BackgroundTransparency = 1 }):Play()
			local t = TweenService:Create(scale, P.Motion.WindowClose, { Scale = 0.8 })
			t.Completed:Once(finish)
			t:Play()
		end,
		destroy = function()
			winBag.clean()
			contentBag.clean()
			holder:Destroy()
			scrim:Destroy()
		end,
	}
	return self
end

------------------------------------------------------------------ toast ("+$1.2B!", "Sold 3!")
function Plate.Toast(gui: ScreenGui, text: string, props: { color: Color3?, icon: string?, top: number?, seconds: number? }?)
	local o = props or {}
	local pill = frame(gui, "PlateToast", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.WindowBody,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, o.top or px(70)),
		Size = UDim2.fromOffset(px(220), px(40)),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 80,
	})
	corner(pill, P.Radius.Button)
	stroke(pill, px(3))
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(12))
	pad.PaddingRight = UDim.new(0, px(12))
	pad.Parent = pill
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0, px(6))
	row.Parent = pill
	if o.icon and o.icon ~= "" then
		icon(pill, o.icon, UDim2.fromOffset(px(28), px(28)), 81)
	end
	local l = Plate.Label(pill, text, { size = 24, font = P.Font.Title, color = o.color or P.Color.Cash, z = 81, strokePx = 3 })
	l.TextScaled = false
	l.TextSize = px(24)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, px(36))
	local sc = Juice.scaleOf(pill)
	sc.Scale = 0.4
	TweenService:Create(sc, P.Motion.CardPop, { Scale = 1 }):Play()
	if not Juice.reduced() then
		Juice.sparkles(pill, 3)
	end
	-- long sentences shrink to fit the screen instead of running off it
	task.defer(function()
		if pill.Parent and gui.AbsoluteSize.X > 0 and pill.AbsoluteSize.X > gui.AbsoluteSize.X * 0.92 then
			l.TextSize = math.max(px(Theme.Size.MinText), math.floor(l.TextSize * gui.AbsoluteSize.X * 0.92 / pill.AbsoluteSize.X))
		end
	end)
	task.delay(o.seconds or 1.6, function()
		if not pill.Parent then
			return
		end
		local t = TweenService:Create(sc, P.Motion.WindowClose, { Scale = 0.6 })
		t.Completed:Once(function()
			pill:Destroy()
		end)
		t:Play()
	end)
	return pill
end

------------------------------------------------------------------ confirm dialog (Dialog header)
function Plate.Confirm(gui: ScreenGui, props: {
	title: string,
	body: string,
	confirmText: string,
	confirmVariant: string?,
	confirmIcon: string?,
	cancelText: string?,
	onConfirm: () -> (),
	onCancel: (() -> ())?,
}): Window
	local win
	win = Plate.Window(gui, {
		key = "Dialog",
		title = props.title,
		aspect = 1.9,
		widthScale = 0.6,
		heightScale = 0.62,
		maxSize = Vector2.new(470, 250),
		zIndex = 20,
		destroyOnClose = true,
		onClose = function()
			win.close()
			if props.onCancel then
				props.onCancel()
			end
		end,
	})
	win.open()
	local c = win.Content
	Plate.Label(c, props.body, { size = 20, min = 14, wrap = true, frameSize = UDim2.fromScale(1, 0.55), z = 6 })
	local row = frame(c, "Buttons", { Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.38), ZIndex = 6 })
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, px(14))
	l.Parent = row
	Plate.Button(row, {
		variant = "tabOff",
		text = props.cancelText or "Cancel",
		size = UDim2.fromOffset(px(130), px(44)),
		bag = win.bag,
		order = 1,
		onClick = function()
			win.close()
			if props.onCancel then
				props.onCancel()
			end
		end,
	})
	Plate.Button(row, {
		variant = props.confirmVariant or "go",
		text = props.confirmText,
		icon = props.confirmIcon,
		primary = true,
		size = UDim2.fromOffset(px(170), px(44)),
		bag = win.bag,
		order = 2,
		onClick = function()
			win.close()
			props.onConfirm()
		end,
	})
	return win
end

return Plate
