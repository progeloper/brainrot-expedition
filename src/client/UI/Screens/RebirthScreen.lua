--!nocheck
-- MenusV2 Rebirth window (from the legacy "Base" branch + rebirth()). Opened only by the base entrance
-- prompt (server Phase13Update {kind="Open", category="Base"}); Phase13ShopController keeps every remote call:
--   Quote   -> ctx.rebirthQuote(rewardId, route) = {action="Quote", rewardId, route}
--   Rebirth -> ctx.rebirthConfirm(q)             = q + {action="Rebirth", operationId, sequence}
--   Design  -> ctx.select("Design", id)          = mutate("Select", "Design", id)
--   Preview Rift -> ctx.previewRift(nil, false)  (local dialog; the legacy Base tab's rift tile)
-- Every number comes from Config/Phase13, the snapshot or the server quote. The cinematic and the
-- server flow are unchanged (Phase13Update "Confirmed" -> rebirth presentation).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local Config = require(ReplicatedStorage.Shared.Config.Phase13)

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local RED = Color3.fromRGB(255, 92, 92) -- legacy YOU LOSE colour
local GREEN = P.Color.Cash
local WHITE = Color3.fromRGB(235, 233, 247)
local ERROR_RED = Color3.fromHex("#FF6B7A")

local player = Players.LocalPlayer

local Screen = {}

local ctx = nil
local window = nil
local tab = "Next"
local tabs = nil
local renderBag = nil
local confirm = nil -- { q, route, reward } while the confirm panel is shown
local quoting = false
local openToken = 0

local TABS = {
	{ id = "Next", text = "Rebirth" },
	{ id = "Designs", text = "Designs" },
}

local function snapshot()
	return ctx and ctx.snapshot()
end

local function strings()
	return ctx.strings
end

-- same helper as the legacy rebirth() confirm
local function duration(seconds)
	if type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 then
		return "no time"
	end
	if seconds < 3600 then
		return string.format("%d min", math.max(1, math.floor(seconds / 60 + 0.5)))
	end
	return string.format("%.1f h", seconds / 3600)
end

-- legacy rebirth(): the message for a quote that is not ok
local function quoteMessage(q): string
	local Strings = strings()
	if q.code == "INSUFFICIENT_CASH" then
		return Strings.Format("NeedCashAmount", ctx.cash(math.max(0, (q.price or 0) - (q.totalCash or 0))))
	elseif q.code == "BASE_NOT_FULL" then
		return Strings.Format("FillSlots", tostring(q.capacity))
	elseif q.code == "MISSING_QUALITY" then
		return Strings.Format(
			"NeedQuality",
			tostring(math.max(0, (q.requiredIndividuals or 4) - (q.qualifyingIndividuals or 0))),
			tostring(q.minimumRarity)
		)
	end
	return ctx.message(q)
end

-- legacy rebirth(): the reward text of an ok quote
local function rewardText(q): string
	local Strings = strings()
	if q.rewardKind == "Prestige" then
		return Strings.Format("PrestigeTitle", tostring((q.prestigeCount or 0) + 1))
	elseif q.rewardKind == "Expansion" then
		return Strings.Format(
			"SlotReward",
			tostring(
				(Config.ExpansionRows[math.max(1, table.find(Config.ExpansionCapacities, q.capacity) or 1)] or {}).capacity
					or "?"
			)
		)
	end
	return Strings.DesignReward
end

local function nextExpansion(s)
	for _, row in Config.ExpansionRows do
		if row.capacity > s.capacity then
			return row
		end
	end
	return nil
end

local function prestigeOffer(s)
	local prestige = s.economy and s.economy.prestige
	if s.capacity >= Config.MaxSlots and prestige and prestige.price then
		return prestige
	end
	return nil
end

local function designName(id: string): string
	for _, row in Config.DesignRows do
		if row.id == id then
			return row.displayName
		end
	end
	return "—"
end

------------------------------------------------------------------ actions
local render -- forward

local function toast(text: string, color: Color3?)
	Plate.Toast(MenusV2.Gui(), text, { color = color or ERROR_RED })
end

local function startRebirth(rewardId: string, route: string)
	if quoting or not ctx or ctx.isBusy() then
		return
	end
	quoting = true
	local token = openToken
	local q = ctx.rebirthQuote(rewardId, route)
	quoting = false
	if token ~= openToken or not window or not window.isOpen() or not q then
		return
	end
	if not q.ok then
		local text = quoteMessage(q)
		toast(text)
		if tabs then
			tabs.setHint(text)
		end
		return
	end
	confirm = { q = q, route = route, reward = rewardText(q) }
	render(true)
end

------------------------------------------------------------------ builders
local function rebirthButtons(card, rewardId: string, cashOnly: boolean, primary: boolean)
	local h = if cashOnly then 34 else 30
	Plate.Button(card.Footer, {
		variant = "go",
		text = "Rebirth (Cash)",
		icon = Theme.Icons.Cash,
		primary = primary,
		size = UDim2.new(0.92, 0, 0, px(h)),
		order = 5,
		textSize = 16,
		bag = renderBag,
		name = "CashRebirth",
		onClick = function()
			startRebirth(rewardId, "Cash")
		end,
	})
	if not cashOnly then
		Plate.Button(card.Footer, {
			variant = "info",
			text = "Rebirth (Collection)",
			size = UDim2.new(0.92, 0, 0, px(h)),
			order = 6,
			textSize = 16,
			bag = renderBag,
			name = "CollectionRebirth",
			onClick = function()
				startRebirth(rewardId, "Collection")
			end,
		})
	end
end

local function infoPanel(parent: Instance, height: number, lines)
	local f = Plate.frame(parent, "Info", {
		BackgroundTransparency = 0.15,
		BackgroundColor3 = P.Color.Ink,
		Size = UDim2.fromOffset(px(250), height),
		LayoutOrder = 99,
		ZIndex = 5,
	})
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px(P.Radius.Card))
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromHex("#3A3D50")
	st.Thickness = px(2)
	st.Parent = f
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, px(6))
	l.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, px(8))
	pad.PaddingLeft = UDim.new(0, px(10))
	pad.PaddingRight = UDim.new(0, px(10))
	pad.Parent = f
	for i, line in lines do
		Plate.Label(f, line.text, {
			size = line.size or 16,
			min = 14,
			wrap = true,
			font = line.font,
			color = line.color or WHITE,
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(1, 0, 0, px(line.height or 22)),
			order = i,
			z = 6,
		})
	end
	return f
end

local function renderNext(row, s, cardSize, height)
	local Strings = strings()
	local expansion = nextExpansion(s)
	local prestige = prestigeOffer(s)
	local lines = { { text = "Base slots: " .. tostring(s.capacity), size = 20, font = P.Font.Title, height = 26 } }
	local i = 0
	if expansion then
		i += 1
		local card = Plate.ItemCard(row, {
			name = Strings.Format("SlotReward", tostring(expansion.capacity)),
			sub = "Rebirth reward",
			image = Theme.Icons.Rebirth,
			background = P.Tier.WonGold,
			rays = true,
			size = cardSize,
			imageHeight = 0.28, -- leaves room for Cash + Collection buttons
			index = i,
			bag = renderBag,
			pop = renderBag.pop,
		})
		rebirthButtons(card, expansion.id, false, player:GetAttribute("RebirthReady") == true)
		table.insert(lines, {
			text = Strings.Format("ExpansionDetail", ctx.cash(expansion.price), expansion.minimumRarity),
			height = 76,
		})
	end
	if prestige then
		i += 1
		local card = Plate.ItemCard(row, {
			name = Strings.Format("PrestigeTitle", tostring(prestige.count + 1)),
			sub = Common.money(prestige.price),
			image = Theme.Icons.Rebirth,
			background = P.Tier.T8,
			rainbow = true,
			rays = true,
			size = cardSize,
			imageHeight = 0.48,
			index = i,
			bag = renderBag,
			pop = renderBag.pop,
		})
		rebirthButtons(card, "PRESTIGE", true, false)
		table.insert(lines, { text = Strings.Format("PrestigeDetail", ctx.cash(prestige.price)), height = 56 })
	end
	if not expansion and not prestige then
		table.insert(lines, { text = "Your base is at its biggest.", height = 26 })
	end
	-- the rift shown during the rebirth (the legacy Base tab's rift tile): a local preview dialog
	i += 1
	local riftCard = Plate.ItemCard(row, {
		name = "Rebirth Rift",
		sub = "Opens when you rebirth",
		image = Theme.Icons.Rebirth,
		background = P.Tier.Dark,
		size = cardSize,
		imageHeight = 0.48,
		index = i,
		bag = renderBag,
		pop = renderBag.pop,
	})
	Common.Action(riftCard, {
		kind = "info",
		text = "Preview Rift",
		bag = renderBag,
		onClick = function()
			ctx.previewRift(nil, false)
		end,
	})
	table.insert(lines, { text = Strings.Preserve, color = P.Color.Hint, height = 40 })
	infoPanel(row, height, lines)
end

local function renderDesigns(row, s, cardSize)
	local selectedSlot = nil
	for i, d in Config.DesignRows do
		local owned = s.ownedDesigns[d.id] == true
		local selected = s.selectedDesign == d.id
		local card = Plate.ItemCard(row, {
			name = d.displayName,
			sub = if owned then "Owned" else "Rebirth reward",
			image = Shots.get(d.id),
			background = if owned then P.Tier.T3 else P.Tier.Dark,
			rays = selected,
			size = cardSize,
			imageHeight = 0.4,
			index = i,
			bag = renderBag,
			pop = renderBag.pop,
		})
		if selected then
			selectedSlot = card.Root
			Common.Action(card, { kind = "well", text = "Selected", bag = renderBag })
		elseif owned then
			Common.Action(card, {
				kind = "info",
				text = "Select",
				bag = renderBag,
				onClick = function()
					ctx.select("Design", d.id)
				end,
			})
		else
			rebirthButtons(card, d.id, false, false)
		end
	end
	Common.scrollTo(row, selectedSlot)
end

local function confirmLine(parent: Instance, text: string, color: Color3, order: number, size: number?, height: number?)
	return Plate.Label(parent, text, {
		size = size or 18,
		min = 14,
		wrap = true,
		color = color,
		font = P.Font.Title,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 0, px(height or 28)),
		order = order,
		z = 6,
	})
end

local function renderConfirm(area: Frame, height: number)
	local Strings = strings()
	local q, route = confirm.q, confirm.route
	local cardH = height
	local cardW = math.floor(cardH * 0.7)
	local image = if q.rewardKind == "Design" then Shots.get(q.rewardId) else Theme.Icons.Rebirth
	local name = if q.rewardKind == "Design" then designName(q.rewardId) else confirm.reward
	Plate.ItemCard(area, {
		name = name,
		sub = if route == "Cash" then "Cash rebirth" else "Brainrot rebirth",
		image = image,
		background = P.Tier.WonGold,
		rays = true,
		size = UDim2.fromOffset(cardW, cardH),
		imageHeight = 0.6,
		index = 1,
		bag = renderBag,
		pop = renderBag.pop,
	})
	local side = Plate.frame(area, "ConfirmPanel", {
		Position = UDim2.fromOffset(cardW + px(12), 0),
		Size = UDim2.new(1, -(cardW + px(12)), 0, height),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = P.Color.Ink,
		ZIndex = 5,
	})
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px(P.Radius.Card))
	c.Parent = side
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(4))
	list.Parent = side
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, px(8))
	pad.PaddingLeft = UDim.new(0, px(12))
	pad.PaddingRight = UDim.new(0, px(12))
	pad.Parent = side

	confirmLine(side, Strings.ConfirmRebirth, P.Color.White, 1, 22, 28)
	if route == "Cash" then
		confirmLine(side, Strings.Format("YouLoseCash", "$" .. ctx.cash(q.lostCash or q.totalCash)), RED, 2)
	else
		confirmLine(side, Strings.Format("YouLoseCollection", tostring(q.lostIndividuals or q.ownedCount)), RED, 2)
	end
	confirmLine(side, Strings.Format("YouGet", confirm.reward, tostring(q.gemReward or 0)), GREEN, 3, 17, 40)
	if q.gemReward then
		confirmLine(
			side,
			Strings.Format(
				"RebirthRewards",
				tostring(q.gemReward),
				tostring(math.floor(((q.incomeBonusAfter or 0) - (q.incomeBonusBefore or 0)) * 100 + 0.5)),
				tostring(math.floor((q.incomeBonusAfter or 0) * 100 + 0.5))
			),
			GREEN,
			4,
			15,
			22
		)
	end
	if route == "Cash" then
		confirmLine(side, Strings.Format("PaybackCash", duration(q.paybackSeconds)), WHITE, 5, 16, 24)
		confirmLine(side, Strings.CashBoundary .. " " .. Strings.PaidWarning, P.Color.Hint, 6, 14, 34)
	else
		confirmLine(side, Strings.Format("PaybackCollection", tostring(q.lostIndividuals or q.ownedCount)), WHITE, 5, 16, 24)
	end

	local buttons = Plate.frame(side, "Buttons", { Size = UDim2.new(1, 0, 0, px(48)), LayoutOrder = 9, ZIndex = 6 })
	local bl = Instance.new("UIListLayout")
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	bl.VerticalAlignment = Enum.VerticalAlignment.Center
	bl.Padding = UDim.new(0, px(10))
	bl.Parent = buttons
	Plate.Button(buttons, {
		variant = "tabOff",
		text = "Back",
		size = UDim2.fromOffset(px(100), px(44)),
		order = 1,
		bag = renderBag,
		onClick = function()
			confirm = nil
			render(true)
		end,
	})
	-- armed after 1 s, like the legacy confirm modal
	local armed = false
	local go
	go = Plate.Button(buttons, {
		variant = "locked",
		text = "Rebirth",
		lockedReason = "Rebirth",
		icon = Theme.Icons.Rebirth,
		primary = true,
		size = UDim2.fromOffset(px(150), px(44)),
		order = 2,
		textSize = 22,
		bag = renderBag,
		name = "ConfirmRebirth",
		onClick = function()
			if not armed or ctx.isBusy() then
				return
			end
			armed = false
			local quote = q
			confirm = nil
			render(false)
			ctx.rebirthConfirm(quote)
		end,
	})
	local token = openToken
	local current = confirm
	task.delay(1, function()
		if token == openToken and confirm == current and go.Root.Parent then
			armed = true
			go.setVariant("go")
		end
	end)
end

render = function(pop: boolean)
	if not window or not window.isOpen() then
		return
	end
	local s = snapshot()
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	renderBag.pop = pop
	local old = window.Content:FindFirstChild("Area")
	if old then
		old:Destroy()
	end
	window.setStat("Rebirth " .. tostring(s and s.rebirthCount or 0))
	if tabs then
		tabs.setHint(if confirm then "Check before you rebirth"
			elseif not s then ""
			elseif tab == "Designs" then "Selected: " .. designName(s.selectedDesign)
			else "Rebirth here at your base")
	end
	if not s then
		Plate.Label(window.Content, "Loading…", { size = 20, frameSize = UDim2.new(1, 0, 0, px(40)), position = UDim2.fromOffset(0, px(60)), name = "Area" })
		return
	end
	local height = window.contentSize().Y - px(44)
	if confirm then
		local area = Plate.frame(window.Content, "Area", {
			Position = UDim2.fromOffset(0, px(44)),
			Size = UDim2.new(1, 0, 0, height),
			ZIndex = 5,
		})
		renderConfirm(area, height - px(6))
		return
	end
	local row = Common.CardRow(window.Content, {
		position = UDim2.fromOffset(0, px(44)),
		size = UDim2.new(1, 0, 0, height),
	})
	row.Name = "Area"
	local cardSize = UDim2.fromOffset(px(160), math.max(px(190), height - px(14)))
	if tab == "Designs" then
		renderDesigns(row, s, cardSize)
	else
		renderNext(row, s, cardSize, math.max(px(190), height - px(14)))
	end
end

local function selectTab(id: string)
	if id == tab then
		return
	end
	tab = id
	confirm = nil
	if tabs then
		tabs.setActive(id)
	end
	render(true)
end

function Screen.open(context, _category: string?)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Rebirth",
			title = "Rebirth",
			icon = Theme.Icons.Rebirth,
			onClose = function()
				ctx.close()
			end,
		})
	end
	openToken += 1
	quoting = false
	confirm = nil
	tab = "Next"
	window.open()
	window.clearContent()
	local list = {}
	for _, t in TABS do
		table.insert(list, { id = t.id, text = t.text })
	end
	tabs = Plate.Tabs(window.Content, { tabs = list, active = tab, onSelect = selectTab, bag = window.bag, tabWidth = 110 })
	task.defer(render, true)
end

function Screen.update()
	render(false)
end

function Screen.notify(result, text)
	Common.notify(MenusV2.Gui(), result, text)
end

function Screen.close(instant: boolean?)
	openToken += 1
	confirm = nil
	quoting = false
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
