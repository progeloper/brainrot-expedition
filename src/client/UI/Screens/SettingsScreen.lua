--!nocheck
-- Settings window (from the legacy shop "Settings" tab). Opened by Phase13ShopController for the
-- category "Settings" (HUD gear, Inventory gear, Retention cosmetic unlocks); the controller keeps
-- every remote call:
--   Reduced Motion -> ctx.setReducedMotion(bool)   = VFXSettingsRequest {action="Set", ReducedMotion}
--   Look option    -> ctx.appearance(key, value)   = {action="Appearance", key, value, operationId}
--   Cosmetic None / Equip -> ctx.appearance(slot, "None" | id)
--   Cosmetic Buy   -> ctx.cosmeticPurchase(id)     = {action="CosmeticPurchase", id, operationId}
-- Graphics quality goes through Phase12PresentationController.SetVfxQuality when that exists.
-- Selected states, prices and lock reasons come from the server snapshot / player attributes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local StudPop = require(ReplicatedStorage.Shared.UI.StudPop)
local Finishes = require(ReplicatedStorage.Shared.Config.Phase13OptionalFinishes).Finishes

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local ERROR_RED = Color3.fromHex("#FF6B7A")
local BASE_HINT = "Changes save at your base"

local player = Players.LocalPlayer

local Screen = {}

local ctx = nil
local window = nil
local tab = "Game"
local tabs = nil
local renderBag = nil
local openBag = nil
local openToken = 0
local renderedTab = nil -- keeps the scroll position across refreshes of the same tab

local TABS = {
	{ id = "Game", text = "Game" },
	{ id = "Look", text = "Look" },
	{ id = "Cosmetics", text = "Cosmetics" },
	{ id = "About", text = "About" },
}
local HINTS = { Look = BASE_HINT, Cosmetics = BASE_HINT }

-- Same keys, values and optional (entitlement-gated) finishes as the legacy Settings tab.
local LOOK = {
	{ key = "VIPBadge", values = { "On", "Off" } },
	{ key = "VIPTitle", values = { "On", "Off" } },
	{ key = "VIPChat", values = { "On", "Off" } },
	{ key = "RiftVariant", values = { "Default", "Riftgold" }, optional = "FIN_SINGULARITY" },
	{ key = "BaseFinish", values = { "Default", "Riftgold" }, optional = "FIN_AURORA" },
	{ key = "CartFinish", values = { "Default", "Riftgold", "Trailblazer" }, optional = "FIN_GLACIER" },
	{ key = "WeaponFinish", values = { "Default", "Riftgold", "Trailblazer" }, optional = "FIN_PRISM" },
}
local QUALITY = { "Auto", "Low", "Medium", "High" }
local SLOTS = { "Flag", "BaseBanner", "Trail" }
local SLOT_TITLES = { Flag = "Chariot Flag", BaseBanner = "Base Banner", Trail = "Cart Trail" }

local render -- forward

local function snapshot()
	return ctx and ctx.snapshot()
end

local function toast(text: string?, color: Color3?)
	if type(text) == "string" and text ~= "" then
		Plate.Toast(MenusV2.Gui(), text, { color = color or ERROR_RED })
	end
end

local function stillOpen(token: number): boolean
	return token == openToken and window ~= nil and window.isOpen()
end

-- Phase12PresentationController owns the graphics quality (GetVfxSettings / SetVfxQuality).
local function presentation()
	local ok, module = pcall(require, script.Parent.Parent.Parent.Controllers.Phase12PresentationController)
	return if ok and type(module) == "table" then module else nil
end

local function vfxSettings()
	local p = presentation()
	if p and type(p.GetVfxSettings) == "function" then
		local ok, settings = pcall(p.GetVfxSettings)
		if ok and type(settings) == "table" then
			return settings
		end
	end
	return nil
end

-- The quality picked this session (it applies before the save lands), else the saved attribute.
local function currentQuality(): string
	local quality = player:GetAttribute("VFXQuality")
	local settings = vfxSettings()
	if settings and type(settings.quality) == "string" then
		quality = settings.quality
	end
	return if quality == "Low" or quality == "Medium" or quality == "High" then quality else "Auto"
end

-- "Saving…" / "Saved to your profile" / "This session only" for the last quality change
local function qualityStatus(): string
	local settings = vfxSettings()
	return if settings and type(settings.status) == "string" then settings.status else ""
end

-- "FIN_PRISM" -> "Prism" (first word of the configured finish name)
local function valueText(value: string): string
	local definition = Finishes[value]
	if definition and type(definition.Name) == "string" then
		return definition.Name:match("^%S+") or value
	end
	return value
end

------------------------------------------------------------------ list building
local function buildList()
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "Area"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Position = UDim2.fromOffset(0, px(44))
	sf.Size = UDim2.new(1, 0, 1, -px(44))
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.CanvasSize = UDim2.new()
	sf.ScrollBarThickness = px(6)
	sf.ScrollBarImageColor3 = Color3.fromHex("#9A9CAB")
	sf.ZIndex = 5
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, px(6))
	layout.Parent = sf
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(4))
	pad.PaddingRight = UDim.new(0, px(10))
	pad.PaddingTop = UDim.new(0, px(4))
	pad.PaddingBottom = UDim.new(0, px(6))
	pad.Parent = sf
	sf.Parent = window.Content
	return { frame = sf, count = 0, height = px(10) }
end

-- One row; `panel` rows get the dark plate behind them. The canvas height is kept by hand so the
-- scroll position can be restored right after a refresh.
local function addRow(list, height: number, panel: boolean?): Frame
	list.count += 1
	local row = Plate.frame(list.frame, "Row" .. list.count, {
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = list.count,
		ZIndex = 5,
	})
	if panel then
		row.BackgroundTransparency = 0.15
		row.BackgroundColor3 = P.Color.Ink
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, px(P.Radius.Card))
		c.Parent = row
	end
	list.height += height + px(6)
	list.frame.CanvasSize = UDim2.fromOffset(0, list.height)
	return row
end

local function sectionTitle(list, text: string)
	local row = addRow(list, px(28), false)
	Plate.Label(row, text, {
		size = 20,
		min = 14,
		font = P.Font.Title,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -px(8), 1, 0),
		position = UDim2.fromOffset(px(4), 0),
		z = 6,
	})
end

local function noteRow(list, text: string, color: Color3?)
	local row = addRow(list, px(40), true)
	Plate.Label(row, text, {
		size = 16,
		min = 14,
		wrap = true,
		color = color or P.Color.Hint,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -px(24), 1, 0),
		position = UDim2.fromOffset(px(12), 0),
		z = 6,
	})
end

-- "Title   [A] [B] [C]": the selected option is a well, the others are info buttons.
local function optionRow(list, title: string, options: { { value: any, text: string } }, selected: any, onPick: (any) -> ())
	local row = addRow(list, px(60), true)
	row.Name = "Option_" .. title
	Plate.Label(row, title, {
		size = 18,
		min = 14,
		wrap = true,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(0.3, -px(14), 1, 0),
		position = UDim2.fromOffset(px(12), 0),
		z = 6,
	})
	local holder = Plate.frame(row, "Options", {
		Position = UDim2.fromScale(0.3, 0),
		Size = UDim2.new(0.7, -px(8), 1, 0),
		ZIndex = 6,
	})
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, px(8))
	l.Parent = holder
	local size = UDim2.new(0.25, -px(8), 0, px(48))
	for i, option in options do
		if option.value == selected then
			Plate.StateWell(holder, option.text, { size = size, order = i, bag = renderBag, textSize = 16 })
		else
			Plate.Button(holder, {
				variant = "info",
				text = option.text,
				size = size,
				order = i,
				textSize = 17,
				bag = renderBag,
				name = "Opt_" .. tostring(option.value),
				onClick = function()
					onPick(option.value)
				end,
			})
		end
	end
end

------------------------------------------------------------------ Game
local savingMotion = false

local function setReducedMotion(value: boolean)
	if savingMotion or not ctx then
		return
	end
	savingMotion = true
	local token = openToken
	local ok = ctx.setReducedMotion(value) -- yields; nil = another action is in flight
	savingMotion = false
	if ok == nil or not stillOpen(token) then
		return
	end
	local Strings = ctx.strings
	toast(if ok then Strings.Saved else Strings.Unavailable, if ok then P.Color.Cash else ERROR_RED)
	render(false)
end

local function setQuality(mode: string)
	local p = presentation()
	if not p or type(p.SetVfxQuality) ~= "function" then
		return
	end
	local token = openToken
	local called, ok, message = pcall(p.SetVfxQuality, mode)
	if not stillOpen(token) then
		return
	end
	if not (called and ok) then
		toast(if called and type(message) == "string" and message ~= "" then message else ctx.strings.Unavailable)
	end
	render(false) -- the save status shows in the tab hint
end

local function renderGame(list)
	local Strings = ctx.strings
	local reduced = player:GetAttribute("ReducedMotion") == true
	optionRow(list, Strings.SettingsLabels.ReducedMotion, {
		{ value = true, text = "On" },
		{ value = false, text = "Off" },
	}, reduced, setReducedMotion)
	local p = presentation()
	if p and type(p.SetVfxQuality) == "function" then
		local options = {}
		for _, mode in QUALITY do
			table.insert(options, { value = mode, text = mode })
		end
		optionRow(list, "Graphics quality", options, currentQuality(), setQuality)
	end
end

------------------------------------------------------------------ Look
local function renderLook(list, s)
	local Strings = ctx.strings
	local chosen = if type(s.appearance) == "table" then s.appearance else {}
	for _, entry in LOOK do
		local values = table.clone(entry.values)
		if entry.optional and player:GetAttribute("Entitlement_" .. entry.optional) == true then
			table.insert(values, entry.optional)
		end
		local options = {}
		for _, value in values do
			table.insert(options, { value = value, text = valueText(value) })
		end
		-- nothing saved yet: VIP toggles are off and finishes are Default
		local selected = chosen[entry.key] or (if values[1] == "On" then "Off" else "Default")
		optionRow(list, Strings.SettingsLabels[entry.key], options, selected, function(value)
			ctx.appearance(entry.key, value)
		end)
	end
end

------------------------------------------------------------------ Cosmetics
-- name | detail | one action (right)
local function cosmeticRow(list, name: string, detail: string)
	local row = addRow(list, px(60), true)
	row.Name = "Cosmetic_" .. name
	Plate.Label(row, name, {
		size = 18,
		min = 14,
		wrap = true,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(0.32, -px(14), 1, 0),
		position = UDim2.fromOffset(px(12), 0),
		z = 6,
	})
	if detail ~= "" then
		Plate.Label(row, detail, {
			size = 15,
			min = 14,
			wrap = true,
			color = P.Color.Hint,
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(0.38, -px(8), 1, 0),
			position = UDim2.fromScale(0.32, 0),
			z = 6,
		})
	end
	return row
end

local function rowAction(row: Frame, props)
	local size = UDim2.new(0.28, -px(8), 0, px(48))
	local position = UDim2.new(1, -px(8), 0.5, 0)
	local anchor = Vector2.new(1, 0.5)
	if props.kind == "well" then
		return Plate.StateWell(row, props.text, { size = size, position = position, anchor = anchor, bag = renderBag, textSize = 16 })
	end
	return Plate.Button(row, {
		variant = props.kind,
		text = props.text,
		lockedReason = if props.kind == "locked" then props.text else nil,
		icon = props.icon,
		primary = props.primary,
		size = size,
		position = position,
		anchor = anchor,
		textSize = 17,
		bag = renderBag,
		name = props.name,
		onClick = props.onClick,
	})
end

local function renderCosmetics(list, s)
	local Strings = ctx.strings
	local attachments = s.attachmentCosmetics
	if type(attachments) ~= "table" or type(attachments.slots) ~= "table" then
		noteRow(list, Strings.Unavailable)
		return
	end
	local ready = attachments.available == true
	local balance = s.balance or 0
	-- the ONE breathing primary: the cheapest Cash cosmetic the player can buy right now
	local primaryId, cheapest = nil, math.huge
	if ready then
		for _, slot in SLOTS do
			local choice = attachments.slots[slot]
			for _, row in (type(choice) == "table" and choice.rows) or {} do
				if
					row.availableForPurchase == true
					and type(row.priceCash) == "number"
					and row.priceCash <= balance
					and row.priceCash < cheapest
				then
					primaryId, cheapest = row.id, row.priceCash
				end
			end
		end
	end
	for _, slot in SLOTS do
		local choice = attachments.slots[slot]
		if type(choice) == "table" then
			sectionTitle(list, SLOT_TITLES[slot])
			if ready then
				local none = cosmeticRow(list, "None", "")
				if choice.selected == "None" then
					rowAction(none, { kind = "well", text = "Selected" })
				else
					rowAction(none, {
						kind = "info",
						text = "Select",
						name = "None_" .. slot,
						onClick = function()
							ctx.appearance(slot, "None")
						end,
					})
				end
			else
				noteRow(list, Strings.Unavailable)
			end
			for _, row in choice.rows or {} do
				local shown = row.presentationReady == true
				local name = row.name or row.id
				local detail = row.acquisitionText or ""
				local action
				if row.selected and shown then
					action = { kind = "well", text = "Equipped" }
				elseif ready and row.availableForSelection == true and shown and not row.selected then
					action = {
						kind = "info",
						text = "Equip",
						onClick = function()
							ctx.appearance(slot, row.id)
						end,
					}
				elseif ready and row.availableForPurchase == true then
					local price = row.priceCash
					if type(price) == "number" and price > balance then
						action = { kind = "locked", text = "Need " .. Common.money(price) }
					else
						action = {
							kind = "go",
							text = Common.money(price),
							icon = Theme.Icons.Cash,
							primary = row.id == primaryId,
							onClick = function()
								ctx.cosmeticPurchase(row.id)
							end,
						}
					end
				else
					-- locked: the server's reason, with how the cosmetic is earned next to it
					local reason = row.availabilityReason
					local text = if not ready or reason == "PRESENTATION_UNAVAILABLE" or (row.acquisition == "Paid" and not row.owned)
						then "Unavailable"
						else "Locked"
					if row.selected then
						detail = if detail ~= "" then detail .. " · Selected" else "Selected"
					elseif row.owned then
						detail = if detail ~= "" then detail .. " · Owned" else "Owned"
					elseif row.acquisition == "Cash" and type(row.priceCash) == "number" then
						detail = if detail ~= "" then detail .. " · " .. Common.money(row.priceCash) else Common.money(row.priceCash)
					end
					action = { kind = "locked", text = text }
				end
				action.name = "Action_" .. tostring(row.id)
				rowAction(cosmeticRow(list, name, detail), action)
			end
		end
	end
	if list.count == 0 then
		noteRow(list, Strings.Unavailable)
	end
end

------------------------------------------------------------------ About
local function renderAbout()
	local area = Plate.frame(window.Content, "Area", {
		Position = UDim2.fromOffset(0, px(44)),
		Size = UDim2.new(1, 0, 1, -px(44)),
		ZIndex = 5,
	})
	local holder = Plate.frame(area, "AboutLogo", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.9, 0.7),
		ZIndex = 6,
	})
	-- still: no loops left running when the window closes
	local logo = StudPop.Logo(holder, UDim2.fromScale(1, 1), { peekImage = Shots.get("BRT_019"), still = true })
	logo.Root.AnchorPoint = Vector2.new(0.5, 0)
	logo.Root.Position = UDim2.fromScale(0.5, 0)
	renderBag.add(function()
		logo.destroy()
	end)
	Plate.Label(area, string.format(
		-- Playtest Fixes 2 E2: the switch hash shows whether this session runs the same features
		-- as another (Studio vs device).
		"Build %s · Switches %s · Place version %s",
		tostring(ReplicatedStorage:GetAttribute("ReleaseBuildId") or "Loading"),
		require(ReplicatedStorage.Shared.Utility.SwitchTable).Hash(),
		tostring(ReplicatedStorage:GetAttribute("ReleasePlaceVersion") or "Loading")
	), {
		size = 16,
		min = 14,
		wrap = true,
		color = P.Color.Hint,
		frameSize = UDim2.fromScale(1, 0.22),
		position = UDim2.fromScale(0, 0.76),
		z = 6,
		name = "BuildLine",
	})
end

------------------------------------------------------------------ render
render = function(_pop: boolean?)
	if not window or not window.isOpen() or not ctx then
		return
	end
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	local scroll = nil
	local old = window.Content:FindFirstChild("Area")
	if old then
		if old:IsA("ScrollingFrame") and renderedTab == tab then
			scroll = old.CanvasPosition
		end
		old:Destroy()
	end
	renderedTab = tab
	if tabs then
		tabs.setHint(if tab == "Game" then qualityStatus() else (HINTS[tab] or ""))
	end
	if tab == "About" then
		renderAbout()
		return
	end
	local s = snapshot()
	if tab ~= "Game" and not s then
		Plate.Label(window.Content, "Loading…", {
			size = 20,
			frameSize = UDim2.new(1, 0, 0, px(40)),
			position = UDim2.fromOffset(0, px(60)),
			name = "Area",
		})
		return
	end
	local list = buildList()
	if tab == "Game" then
		renderGame(list)
	elseif tab == "Look" then
		renderLook(list, s)
	else
		renderCosmetics(list, s)
	end
	if scroll then
		list.frame.CanvasPosition = scroll
	end
end

local function selectTab(id: string)
	if id == tab then
		return
	end
	tab = id
	if tabs then
		tabs.setActive(id)
	end
	render(true)
end

------------------------------------------------------------------ public
-- focus: optional tab id ("Cosmetics" when the controller is asked to show a cosmetic)
function Screen.open(context, _category: string?, focus: string?)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Dialog",
			title = "Settings",
			icon = Theme.Icons.Settings,
			onClose = function()
				ctx.close()
			end,
		})
	end
	openToken += 1
	tab = "Game"
	for _, t in TABS do
		if t.id == focus then
			tab = focus
		end
	end
	renderedTab = nil
	if openBag then
		openBag.clean()
	end
	openBag = Plate.Bag()
	-- the server mirrors saved VFX settings onto the player: keep the Game tab in step
	for _, name in { "ReducedMotion", "VFXQuality" } do
		openBag.add(player:GetAttributeChangedSignal(name):Connect(function()
			if tab == "Game" then
				render(false)
			end
		end))
	end
	local p = presentation()
	local changed = p and p.VfxSettingsChanged
	if typeof(changed) == "Instance" and changed:IsA("BindableEvent") then
		openBag.add(changed.Event:Connect(function()
			if tab == "Game" then
				render(false)
			end
		end))
	end
	window.open()
	window.clearContent()
	local list = {}
	for _, t in TABS do
		table.insert(list, { id = t.id, text = t.text })
	end
	tabs = Plate.Tabs(window.Content, { tabs = list, active = tab, onSelect = selectTab, bag = window.bag, tabWidth = 104 })
	task.defer(render, true)
end

function Screen.update()
	render(false)
end

-- Rejections show the server's message; a finished save says so ("Saved.").
function Screen.notify(result, text)
	if type(result) ~= "table" then
		return
	end
	if result.ok == false then
		toast(text, ERROR_RED)
	elseif result.ok == true and result.state ~= "Saving" then
		toast(text, P.Color.Cash)
	end
end

function Screen.close(instant: boolean?)
	openToken += 1
	if openBag then
		openBag.clean()
		openBag = nil
	end
	if renderBag then
		renderBag.clean()
		renderBag = nil
	end
	tabs = nil
	if window then
		window.close(instant)
	end
end

return Screen
