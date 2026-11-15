--!nocheck
-- MenusV2 "Team" window (the chariot team; legacy "Manage Team"). View only: it draws
-- ChariotTeamController.View() and calls the controller facade (ctx); the controller keeps every
-- remote call, the pending/stale handling and the open/close bookkeeping (MenusV2.setOpen/cleared).
--   tap a slot          -> ctx.selectSlot(i)
--   slot price button   -> ctx.buy(i)          = {operation="Buy", slot, configVersion, ...}
--   slot / panel Unequip-> ctx.unequip()       = {operation="Unequip", slot, expectedIndividualId, ...}
--   card Equip/Replace  -> ctx.equip(id)       = {operation="Equip"|"Replace", slot, individualId, expectedIndividualId, ...}
--   tap a roster card   -> ctx.inspect(id)     (details side panel; ctx.closeDetails() closes it)
--   ✕ / scrim           -> ctx.close()         = {operation="Close", session}
-- Layout: summary chips (team totals, wallet, cart) on top; left = the six slots, then the full
-- team stats and notes; right = roster grid for the selected slot (+ details side panel), or the
-- unlock offer when the selected slot is locked; status line at the bottom.
-- Static display shots only; every number and message comes from the controller's view model.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local ALERT = Theme.Variant.alert.hi
local STOP = Theme.Variant.stop.hi
local SELECTED_TINT = { Color3.fromHex("#4C5F94"), Color3.fromHex("#2B2D38") }

local Screen = {}

local ctx = nil
local window = nil
local isOpen = false
local renderBag = nil
local firstRender = true
local retryQueued = false
local lastSource = nil
local lastKey = nil
local lastDetailsId = nil
local statusLabel = nil
local scrollers = {} -- name -> ScrollingFrame of the current render
local scrollY = {} -- name -> CanvasPosition.Y carried across re-renders

------------------------------------------------------------------ small builders

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px(r))
	c.Parent = inst
	return c
end

local function stroke(inst: GuiObject, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = math.max(1, thickness)
	s.Color = color or P.Color.Ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end

local function studs(parent: GuiObject, radius: number)
	if P.Tiles.Surface == "" then
		return
	end
	local t = Instance.new("ImageLabel")
	t.Name = "Studs"
	t.BackgroundTransparency = 1
	t.Image = P.Tiles.Surface
	t.ImageTransparency = 0.6
	t.ScaleType = Enum.ScaleType.Tile
	t.TileSize = UDim2.fromOffset(px(P.Tiles.SurfaceTile), px(P.Tiles.SurfaceTile))
	t.Size = UDim2.fromScale(1, 1)
	t.ZIndex = 5
	corner(t, radius)
	t.Parent = parent
end

local function rarityColor(tier: string?): Color3
	return Theme.Rarity[tier or ""] or P.Color.Ink
end

local function tint(tier: string?): { Color3 }
	local c = Theme.Rarity[tier or ""]
	if not c then
		return P.Tier.Dark
	end
	return { c:Lerp(P.Color.WindowBody, 0.55), P.Color.WindowBody }
end

local function image(parent: Instance, id: string, props): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = props.name or "Shot"
	i.BackgroundTransparency = 1
	i.Image = id
	i.ScaleType = Enum.ScaleType.Fit
	i.AnchorPoint = props.anchor or Vector2.zero
	i.Position = props.position or UDim2.new()
	i.Size = props.size
	i.ImageTransparency = props.transparency or 0
	i.ZIndex = props.z or 7
	i.Parent = parent
	return i
end

-- Small pill: summary chips, slot numbers, rarity / platform / "Slot n" badges.
local function chip(parent: Instance, text: string, bg: Color3, textColor: Color3, props)
	local f = Instance.new("Frame")
	f.Name = "Chip_" .. text
	f.BackgroundColor3 = bg
	f.BorderSizePixel = 0
	f.AnchorPoint = props.anchor or Vector2.zero
	f.Position = props.position or UDim2.new()
	f.Size = UDim2.fromOffset(px(18), px(props.height or 18))
	f.AutomaticSize = Enum.AutomaticSize.X
	f.ZIndex = props.z or 8
	f.LayoutOrder = props.order or 0
	corner(f, P.Radius.Pill)
	stroke(f, px(2))
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(6))
	pad.PaddingRight = UDim.new(0, px(6))
	pad.Parent = f
	local l = Plate.Label(f, text, {
		size = 14,
		color = textColor,
		z = (props.z or 8) + 1,
		strokePx = if textColor == P.Color.Ink then 0 else 2,
	})
	l.TextScaled = false
	l.TextSize = px(14)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromScale(0, 1)
	f.Parent = parent
	return f
end

-- Wrapped paragraph that grows downwards (Plate.Label is single-box TextScaled).
local function bodyText(parent: Instance, text: string, props)
	local o = props or {}
	local t = Instance.new("TextLabel")
	t.Name = o.name or "Body"
	t.BackgroundTransparency = 1
	t.Text = text
	t.FontFace = o.font or P.Font.Body
	t.TextColor3 = o.color or P.Color.White
	t.TextSize = px(math.max(Theme.Size.MinText, o.size or 14))
	t.TextWrapped = true
	t.TextXAlignment = o.align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Size = UDim2.fromScale(1, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.LayoutOrder = o.order or 0
	t.ZIndex = o.z or 7
	local s = Instance.new("UIStroke")
	s.Thickness = px(2)
	s.Color = P.Color.Ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = parent
	return t
end

local function column(name: string, props): ScrollingFrame
	local sf = Instance.new("ScrollingFrame")
	sf.Name = name
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Position = props.position
	sf.Size = props.size
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.CanvasSize = UDim2.new()
	sf.ScrollBarThickness = px(5)
	sf.ScrollBarImageColor3 = Color3.fromHex("#9A9CAB")
	sf.ZIndex = props.z or 5
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(props.gap or 5))
	list.HorizontalAlignment = props.align or Enum.HorizontalAlignment.Left
	list.Parent = sf
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(props.padLeft or 4))
	pad.PaddingRight = UDim.new(0, px(props.padRight or 9))
	pad.PaddingTop = UDim.new(0, px(4))
	pad.PaddingBottom = UDim.new(0, px(6))
	pad.Parent = sf
	sf.Parent = props.parent
	return sf
end

-- Keep a scrolling frame where the player left it across a rebuild (the canvas sizes itself a
-- frame later, so the position is re-applied until it sticks or 0.4 s pass).
local function keepScroll(name: string, sf: ScrollingFrame)
	scrollers[name] = sf
	local y = scrollY[name] or 0
	if y <= 0 then
		return
	end
	local conn
	local function stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
	local function apply()
		sf.CanvasPosition = Vector2.new(0, y)
		if math.abs(sf.CanvasPosition.Y - y) < 1 then
			stop()
		end
	end
	conn = sf:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(apply)
	renderBag.add(stop)
	task.delay(0.4, stop)
	apply()
end

-- An action button; a request in flight greys it out and drops the click.
local function actionButton(parent: Instance, action, variant: string, props)
	local live = action.enabled ~= false
	local b = Plate.Button(parent, {
		variant = if live then variant else "tabOff",
		text = action.text,
		icon = props.icon,
		primary = live and props.primary == true,
		size = props.size,
		position = props.position,
		anchor = props.anchor,
		order = props.order,
		textSize = props.textSize or 18,
		bag = renderBag,
		name = props.name,
		onClick = if live then props.onClick else nil,
	})
	b.Root.ZIndex = props.z or 10
	return b
end

local function lockedButton(parent: Instance, reason: string, props)
	local b = Plate.LockedButton(parent, reason, {
		size = props.size,
		position = props.position,
		anchor = props.anchor,
		order = props.order,
		textSize = props.textSize or 16,
		bag = renderBag,
		name = props.name,
	})
	b.Root.ZIndex = props.z or 10
	return b
end

------------------------------------------------------------------ summary + status

local function buildSummary(area: Instance, v, height: number)
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "Summary"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Size = UDim2.new(1, 0, 0, height)
	sf.ScrollingDirection = Enum.ScrollingDirection.X
	sf.AutomaticCanvasSize = Enum.AutomaticSize.X
	sf.CanvasSize = UDim2.new()
	sf.ScrollBarThickness = 0
	sf.ZIndex = 6
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(6))
	list.Parent = sf
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(4))
	pad.PaddingRight = UDim.new(0, px(4))
	pad.Parent = sf
	for i, c in v.summary do
		if c.kind == "cash" then
			chip(sf, c.text, P.Color.Ink, P.Color.Cash, { order = i, height = 20 })
		elseif c.kind == "alert" then
			chip(sf, c.text, ALERT, P.Color.Ink, { order = i, height = 20 })
		elseif c.kind == "info" then
			chip(sf, c.text, P.Color.Well, P.Color.Hint, { order = i, height = 20 })
		else
			chip(sf, c.text, P.Color.Well, P.Color.White, { order = i, height = 20 })
		end
	end
	sf.Parent = area
end

------------------------------------------------------------------ left: slots, team stats, notes

local function slotCard(parent: Instance, s, width: number)
	local baseH = px(64)
	local actionH = px(42)
	local height = if s.action then baseH + actionH + px(4) else baseH
	local top = baseH - px(6)
	local root = Plate.frame(parent, "Slot" .. s.index, {
		Size = UDim2.fromOffset(width, height),
		LayoutOrder = s.index,
		ZIndex = 5,
	})
	local outer = Plate.frame(root, "Outer", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.CardFrame,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})
	corner(outer, P.Radius.Card)
	stroke(
		outer,
		px(P.Stroke.Outline),
		if s.selected then P.Color.White elseif s.state == "Equipped" then rarityColor(s.rarity) else P.Color.Ink
	)
	local inner = Plate.frame(outer, "Inner", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(px(3), px(3)),
		Size = UDim2.new(1, -px(6), 1, -px(6)),
		ZIndex = 5,
		ClipsDescendants = true,
	})
	corner(inner, P.Radius.Card - 1)
	Plate.gradient(
		inner,
		if s.state == "Equipped" then tint(s.rarity) elseif s.selected then SELECTED_TINT else P.Tier.Dark
	)
	studs(inner, P.Radius.Card - 1)

	-- picture: display shot / plus / lock
	local art = UDim2.fromOffset(px(44), px(44))
	local artPos = UDim2.fromOffset(px(8), top / 2)
	local shot = if s.state == "Equipped" then Shots.get(s.speciesId) else ""
	if shot ~= "" then
		image(inner, shot, { size = art, position = artPos, anchor = Vector2.new(0, 0.5) })
	else
		local icon = if s.state == "Locked" then Theme.Icons.Lock
			elseif s.state == "Empty" then Theme.Icons.Plus
			else ""
		if icon ~= "" then
			image(inner, icon, {
				name = "StateIcon",
				size = UDim2.fromOffset(px(30), px(30)),
				position = UDim2.fromOffset(px(15), top / 2),
				anchor = Vector2.new(0, 0.5),
				transparency = 0.1,
			})
		end
	end
	chip(inner, tostring(s.index), P.Color.Ink, P.Color.White, { position = UDim2.fromOffset(px(2), px(2)), z = 9, height = 17 })

	-- text
	local x = px(58)
	local textSize = UDim2.new(1, -(x + px(6)), 0, px(20))
	Plate.Label(inner, s.title, {
		size = 17,
		align = Enum.TextXAlignment.Left,
		frameSize = textSize,
		position = UDim2.fromOffset(x, px(2)),
		z = 7,
		name = "Title",
	})
	if s.line1 then
		Plate.Label(inner, s.line1, {
			size = 15,
			min = 14,
			color = if s.state == "Locked" then P.Color.Cash elseif s.state == "Empty" then P.Color.Hint else P.Color.White,
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(1, -(x + px(6)), 0, px(17)),
			position = UDim2.fromOffset(x, px(22)),
			z = 7,
			name = "Line1",
		})
	end
	if s.line2 then
		Plate.Label(inner, s.line2, {
			size = 14,
			min = 14,
			color = P.Color.Hint,
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(1, -(x + px(6)), 0, px(17)),
			position = UDim2.fromOffset(x, px(39)),
			z = 7,
			name = "Line2",
		})
	end

	-- tap anywhere on the card to select the slot (the action button sits above this)
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 8
	hit.Parent = inner
	renderBag.add(hit.Activated:Connect(function()
		if not s.selected then
			Juice.sound("Click")
		end
		ctx.selectSlot(s.index)
	end))

	local action = s.action
	if action then
		local props = {
			size = UDim2.new(1, -px(12), 0, actionH - px(2)),
			position = UDim2.fromOffset(px(6), top),
			name = "SlotAction",
		}
		if action.kind == "Unequip" then
			props.onClick = function()
				ctx.unequip()
			end
			actionButton(inner, action, "stop", props)
		elseif action.kind == "Buy" then
			props.icon = Theme.Icons.Cash
			props.onClick = function()
				ctx.buy(s.index)
			end
			actionButton(inner, action, "go", props)
		else
			-- locked + reason; the tap also selects the slot so the offer on the right explains it
			local b = lockedButton(inner, action.text, props)
			renderBag.add(b.Root.Activated:Connect(function()
				ctx.selectSlot(s.index)
			end))
		end
	end
	return root
end

local function buildLeft(area: Instance, v, y: number, width: number, height: number)
	local left = column("Slots", {
		parent = area,
		position = UDim2.fromOffset(0, y),
		size = UDim2.fromOffset(width, height),
		gap = 8,
	})
	local cardW = width - px(4) - px(9)
	for _, s in v.slots do
		slotCard(left, s, cardW)
	end
	-- the full team totals (the chips on top are their short form)
	local well = Plate.frame(left, "TeamStats", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Well,
		Size = UDim2.fromOffset(cardW, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 20,
		ZIndex = 6,
	})
	corner(well, P.Radius.Card)
	stroke(well, px(2))
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(7))
	pad.PaddingRight = UDim.new(0, px(7))
	pad.PaddingTop = UDim.new(0, px(5))
	pad.PaddingBottom = UDim.new(0, px(7))
	pad.Parent = well
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(3))
	list.Parent = well
	Plate.Label(well, "Team Stats", {
		size = 17,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 0, px(20)),
		order = 1,
		z = 7,
	})
	bodyText(well, v.totals, { order = 2, name = "Totals" })
	local notes = Plate.frame(left, "Notes", {
		Size = UDim2.fromOffset(cardW, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 21,
		ZIndex = 6,
	})
	local nl = Instance.new("UIListLayout")
	nl.SortOrder = Enum.SortOrder.LayoutOrder
	nl.Padding = UDim.new(0, px(5))
	nl.Parent = notes
	bodyText(notes, v.explanation, { order = 1, color = P.Color.Hint, name = "Explanation" })
	bodyText(notes, v.guidance, { order = 2, color = P.Color.Hint, name = "Guidance" })
	keepScroll("slots", left)
end

------------------------------------------------------------------ right: roster grid

local function rosterCard(grid: Instance, r, i: number, pop: boolean)
	local card = Plate.ItemCard(grid, {
		name = r.name,
		image = Shots.get(r.speciesId),
		background = tint(r.rarity),
		ring = if r.inspected then P.Color.White else rarityColor(r.rarity),
		rays = (Theme.RarityIntensity[r.rarity] or 1) >= 4,
		compact = true,
		size = UDim2.fromScale(1, 1),
		index = math.min(i, 14),
		order = i,
		bag = renderBag,
		pop = pop,
	})
	-- fixed rows from the bottom up: action, income + effect, name; the shot takes the rest
	local footH, infoH, nameH = px(44), px(36), px(32)
	card.ImageArea.Size = UDim2.new(1, 0, 1, -(footH + infoH + nameH))
	card.Header.Position = UDim2.new(0, 0, 1, -(footH + infoH + nameH))
	card.Header.Size = UDim2.new(1, 0, 0, nameH)
	card.Footer.Position = UDim2.new(0, 0, 1, -footH)
	card.Footer.Size = UDim2.new(1, 0, 0, footH)
	local info = Plate.frame(card.Inner, "Info", {
		Position = UDim2.new(0, 0, 1, -(footH + infoH)),
		Size = UDim2.new(1, 0, 0, infoH),
		ZIndex = 9,
	})
	Plate.Label(info, r.income, {
		size = 16,
		color = P.Color.Cash,
		frameSize = UDim2.new(1, -px(6), 0.5, 0),
		position = UDim2.fromOffset(px(3), 0),
		z = 9,
		name = "Income",
	})
	Plate.Label(info, r.effect, {
		size = 14,
		min = 14,
		frameSize = UDim2.new(1, -px(6), 0.5, 0),
		position = UDim2.new(0, px(3), 0.5, 0),
		z = 9,
		name = "Effect",
	})
	if r.equippedSlot then
		chip(card.Inner, "Slot " .. r.equippedSlot, P.Color.Ink, P.Color.White, {
			position = UDim2.fromOffset(px(3), px(3)),
			z = 11,
		})
	end
	-- tap the card (not its button) for the details panel
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 8
	hit.Parent = card.Inner
	renderBag.add(hit.Activated:Connect(function()
		Juice.sound("Click")
		Juice.pop(card.Outer, 1.06)
		ctx.inspect(r.individualId)
	end))

	local action = r.action
	if action.kind == "OnTeam" then
		Common.Action(card, { kind = "well", text = action.text, bag = renderBag, height = 36 })
	elseif action.kind == "Blocked" then
		Common.Action(card, { kind = "locked", text = action.text, bag = renderBag, height = 36 })
	else
		local live = action.enabled ~= false
		Common.Action(card, {
			kind = if live then "info" else "tabOff",
			text = action.text,
			bag = renderBag,
			height = 36,
			onClick = if live
				then function()
					ctx.equip(r.individualId)
				end
				else nil,
		})
	end
	return card
end

local function buildRoster(right: Instance, v, width: number, height: number, pop: boolean)
	local titleH = px(20)
	Plate.Label(right, v.rosterTitle, {
		size = 17,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.fromOffset(width - px(8), titleH),
		position = UDim2.fromOffset(px(4), 0),
		z = 6,
		name = "RosterTitle",
	})
	local gridH = height - titleH - px(2)
	if #v.rows == 0 then
		Plate.Label(right, v.rosterEmpty, {
			size = 18,
			wrap = true,
			color = P.Color.Hint,
			frameSize = UDim2.fromOffset(width - px(20), math.min(gridH, px(90))),
			position = UDim2.fromOffset(px(10), titleH + px(14)),
			z = 6,
			name = "RosterEmpty",
		})
		return
	end
	local gap = px(8)
	local usable = width - px(4) - px(8) - px(6) -- grid padding + scroll bar
	local cols = math.max(1, math.floor((usable + gap) / (px(110) + gap)))
	local cellW = math.min(px(136), math.floor((usable - (cols - 1) * gap) / cols))
	local cellH = math.clamp(gridH - px(12), px(172), px(212))
	local grid = Common.CardGrid(right, {
		position = UDim2.fromOffset(0, titleH + px(2)),
		size = UDim2.fromOffset(width, gridH),
		cell = Vector2.new(110, 180),
		gap = 8,
	})
	grid.Name = "RosterGrid"
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.CellSize = UDim2.fromOffset(cellW, cellH)
	end
	for i, r in v.rows do
		rosterCard(grid, r, i, pop)
	end
	keepScroll("roster", grid)
end

------------------------------------------------------------------ right: details side panel

local function buildDetails(right: Instance, d, x: number, width: number, height: number)
	local inset = px(P.Stroke.Outline)
	local panel = Plate.frame(right, "Details", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Well,
		Position = UDim2.fromOffset(x + inset, inset),
		Size = UDim2.fromOffset(width - 2 * inset, height - 2 * inset),
		ZIndex = 6,
	})
	corner(panel, P.Radius.Card)
	stroke(panel, inset, rarityColor(d.rarity))
	local footH = px(50)
	local body = column("DetailsBody", {
		parent = panel,
		position = UDim2.new(),
		size = UDim2.new(1, 0, 1, -footH),
		gap = 4,
		padLeft = 8,
		padRight = 10,
		align = Enum.HorizontalAlignment.Center,
		z = 6,
	})

	-- shot + panel close
	local top = Plate.frame(body, "Top", { Size = UDim2.new(1, 0, 0, px(58)), LayoutOrder = 1, ZIndex = 7 })
	local shot = Shots.get(d.speciesId)
	if shot ~= "" then
		image(top, shot, { size = UDim2.new(1, -px(48), 1, 0), z = 8 })
	end
	local closeBtn = Plate.Button(top, {
		variant = "stop",
		icon = Theme.Icons.Close,
		size = UDim2.fromOffset(px(40), px(36)),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		name = "PanelClose",
		bag = renderBag,
		onClick = function()
			ctx.closeDetails()
		end,
	})
	closeBtn.Root.ZIndex = 9

	bodyText(body, d.name, { order = 2, size = 18, font = P.Font.Title, align = Enum.TextXAlignment.Center, name = "Name" })
	local chips = Plate.frame(body, "Chips", { Size = UDim2.new(1, 0, 0, px(20)), LayoutOrder = 3, ZIndex = 7 })
	local cl = Instance.new("UIListLayout")
	cl.FillDirection = Enum.FillDirection.Horizontal
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cl.VerticalAlignment = Enum.VerticalAlignment.Center
	cl.Padding = UDim.new(0, px(4))
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Parent = chips
	chip(chips, tostring(d.rarity), rarityColor(d.rarity), P.Color.Ink, { order = 1, z = 8 })
	chip(chips, d.platform, P.Color.Ink, P.Color.White, { order = 2, z = 8 })
	bodyText(body, d.income, { order = 4, size = 16, color = P.Color.Cash, align = Enum.TextXAlignment.Center, name = "Income" })
	bodyText(body, d.effect, { order = 5, align = Enum.TextXAlignment.Center, name = "Effect" })
	bodyText(body, d.copy, { order = 6, color = P.Color.Hint, align = Enum.TextXAlignment.Center, name = "Copy" })
	if d.action.reason then
		bodyText(body, d.action.reason, {
			order = 7,
			color = if d.action.kind == "Blocked" then ALERT else P.Color.White,
			align = Enum.TextXAlignment.Center,
			name = "ActionNote",
		})
	end
	bodyText(body, "Before", { order = 10, size = 15, font = P.Font.Label, color = P.Color.Hint, name = "BeforeTitle" })
	bodyText(body, d.before, { order = 11, name = "Before" })
	bodyText(body, "After", { order = 12, size = 15, font = P.Font.Label, color = P.Color.WellRim, name = "AfterTitle" })
	bodyText(body, d.after, { order = 13, name = "After" })
	bodyText(body, d.description, { order = 14, color = P.Color.Hint, name = "Description" })
	bodyText(body, d.reserve, { order = 15, color = P.Color.Hint, name = "Reserve" })
	for i, note in d.notes do
		bodyText(body, note, { order = 15 + i, color = P.Color.Hint, name = "Note" .. i })
	end
	keepScroll("details", body)

	-- fixed buttons under the scrolling text
	local foot = Plate.frame(panel, "Actions", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, footH),
		ZIndex = 7,
	})
	local fl = Instance.new("UIListLayout")
	fl.FillDirection = Enum.FillDirection.Horizontal
	fl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	fl.VerticalAlignment = Enum.VerticalAlignment.Center
	fl.Padding = UDim.new(0, px(6))
	fl.SortOrder = Enum.SortOrder.LayoutOrder
	fl.Parent = foot
	-- One button: Unequip when this brainrot is the one in the selected slot, else Equip / Replace
	-- (or a locked button with the short reason; the full reason is the note above).
	local size = UDim2.new(0.92, 0, 0, px(40))
	if d.unequip then
		actionButton(foot, { text = "Unequip", enabled = d.unequip.enabled }, "stop", {
			size = size,
			order = 1,
			name = "DetailsUnequip",
			onClick = function()
				ctx.unequip()
			end,
		})
	elseif d.action.kind == "Blocked" then
		lockedButton(foot, d.action.text, { size = size, order = 1, name = "DetailsAction" })
	else
		actionButton(foot, d.action, "info", {
			size = size,
			order = 1,
			primary = true,
			name = "DetailsAction",
			onClick = function()
				ctx.equip(d.individualId)
			end,
		})
	end
end

------------------------------------------------------------------ right: unlock offer (locked slot selected)

local function buildOffer(right: Instance, o, width: number, height: number)
	local inset = px(P.Stroke.Outline)
	local panelW = math.min(width - 2 * inset, px(430))
	local panel = Plate.frame(right, "Offer", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Well,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, inset),
		Size = UDim2.fromOffset(panelW, height - 2 * inset),
		ZIndex = 6,
	})
	corner(panel, P.Radius.Card)
	stroke(panel, inset)
	local footH = px(56)
	local body = column("OfferBody", {
		parent = panel,
		position = UDim2.new(),
		size = UDim2.new(1, 0, 1, -footH),
		gap = 3,
		padLeft = 10,
		padRight = 12,
		align = Enum.HorizontalAlignment.Center,
		z = 6,
	})
	Plate.Title(body, o.title, { size = 26, frameSize = UDim2.new(1, 0, 0, px(34)), order = 1, z = 7 })
	for i, line in o.lines do
		bodyText(body, line, {
			order = 1 + i,
			size = 16,
			color = if i == 1 then P.Color.Cash else P.Color.White,
			align = Enum.TextXAlignment.Center,
			name = "Line" .. i,
		})
	end
	if o.shortfall then
		bodyText(body, o.shortfall, { order = 20, size = 16, color = STOP, align = Enum.TextXAlignment.Center, name = "Shortfall" })
	end
	local size = UDim2.new(0.86, 0, 0, px(44))
	local position = UDim2.new(0.5, 0, 1, -px(8))
	local anchor = Vector2.new(0.5, 1)
	if o.action.kind == "Buy" then
		actionButton(panel, o.action, "go", {
			icon = Theme.Icons.Cash,
			size = size,
			position = position,
			anchor = anchor,
			primary = true,
			name = "OfferBuy",
			onClick = function()
				ctx.buy(o.slot)
			end,
		})
	else
		lockedButton(panel, o.action.text, { size = size, position = position, anchor = anchor, name = "OfferLocked" })
	end
end

------------------------------------------------------------------ render

local render

local function queueRetry()
	if retryQueued then
		return
	end
	retryQueued = true
	task.delay(0.05, function()
		retryQueued = false
		render()
	end)
end

render = function()
	if not window or not isOpen or not ctx then
		return
	end
	local v = ctx.view()
	if not v then
		return
	end
	local size = window.contentSize()
	if size.X < 8 or size.Y < 8 then
		queueRetry() -- the window has not been laid out yet
		return
	end
	window.setStat(v.stat)
	local detailsId = v.details and v.details.individualId or nil
	local key = tostring(v.pending) .. "|" .. tostring(v.selectedSlot) .. "|" .. tostring(detailsId)
	if v.source == lastSource and key == lastKey and statusLabel and statusLabel.Parent then
		statusLabel.Text = v.status -- only the message changed ("Still checking…")
		return
	end

	for name, sf in scrollers do
		if sf.Parent then
			scrollY[name] = sf.CanvasPosition.Y
		end
	end
	if detailsId ~= lastDetailsId then
		scrollY.details = 0
	end
	table.clear(scrollers)
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	local old = window.Content:FindFirstChild("Area")
	if old then
		old:Destroy()
	end
	local pop = firstRender
	firstRender = false
	lastSource, lastKey, lastDetailsId = v.source, key, detailsId

	local W, H = math.floor(size.X), math.floor(size.Y)
	local area = Plate.frame(window.Content, "Area", { Size = UDim2.fromOffset(W, H), ZIndex = 5 })
	local topH, statusH, gap = px(24), px(22), px(4)
	local midY = topH + gap
	local midH = H - topH - statusH - 2 * gap
	local leftW = math.floor(math.min(px(246), W * 0.36))
	local rightX = leftW + px(6)
	local rightW = W - rightX

	buildSummary(area, v, topH)
	statusLabel = Plate.Label(area, v.status, {
		size = 16,
		min = 14,
		color = ALERT,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -px(8), 0, statusH),
		position = UDim2.new(0, px(4), 1, -statusH),
		z = 7,
		name = "Status",
	})
	buildLeft(area, v, midY, leftW, midH)

	local right = Plate.frame(area, "Right", {
		Position = UDim2.fromOffset(rightX, midY),
		Size = UDim2.fromOffset(rightW, midH),
		ZIndex = 5,
	})
	if v.offer then
		buildOffer(right, v.offer, rightW, midH)
		return
	end
	local panelW = if v.details then math.floor(math.min(px(210), rightW * 0.46)) else 0
	local gridW = rightW - panelW - (if v.details then px(6) else 0)
	buildRoster(right, v, gridW, midH, pop)
	if v.details then
		buildDetails(right, v.details, gridW + px(6), panelW, midH)
	end
end

------------------------------------------------------------------ public (called by ChariotTeamController)

function Screen.open(context)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Brainrots",
			title = "Team",
			icon = Theme.Icons.Cart,
			aspect = 2.3,
			widthScale = 0.92,
			heightScale = 0.88,
			maxSize = Vector2.new(780, 343),
			onClose = function()
				if ctx then
					ctx.close()
				end
			end,
		})
	end
	isOpen = true
	firstRender = true
	lastSource, lastKey, lastDetailsId, statusLabel = nil, nil, nil, nil
	table.clear(scrollers)
	table.clear(scrollY)
	window.open()
	window.clearContent()
	task.defer(render)
end

-- Redraw from ctx.view() (state, selection, pending or status changed).
function Screen.update()
	render()
end

function Screen.close(instant: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
	if renderBag then
		renderBag.clean() -- loops and click handlers stop now; the window clears its content when hidden
		renderBag = nil
	end
	statusLabel = nil
	table.clear(scrollers)
	if window then
		window.close(instant)
	end
end

function Screen.isOpen(): boolean
	return isOpen
end

function Screen.destroy()
	Screen.close(true)
	if window then
		window.destroy()
		window = nil
	end
	ctx = nil
end

return Screen
