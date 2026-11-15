--!nocheck
-- MenusV2 Carts stall (from "Trail Shop"). Opened only by the Carts stall prompt (server
-- Phase13Update {kind="Open", category="Cart"}); Phase13ShopController keeps every remote call:
--   Drive   -> ctx.select("Cart", id)   = mutate("Select", "Cart", id)
--   Buy     -> ctx.buy("Cart", id)      = mutate(Strings.Purchase, "Cart", id)
--   Preview -> ctx.preview("Cart", row.assetName) (local ViewportFrame)
-- Cargo upgrades are bought in the Cargo bay window (CargoBayScreen / CartUpgradeController:
-- CartUpgradeShopRequest + a server-opened contextId from the CartUpgradeStall prompt), so the Cargo
-- tab is read-only: it shows the track from config and points at the bay (WorldPointer).
-- Every number comes from Config/Phase13, Config/Upgrades or the server snapshot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local CargoBay = require(script.Parent.CargoBayScreen)
local WorldPointer = require(script.Parent.WorldPointer)
local Phase13 = require(ReplicatedStorage.Shared.Config.Phase13)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local FlairStyles = require(ReplicatedStorage.Shared.Config.CartFlairStyles)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local Screen = {}

local ctx = nil
local window = nil
local tab = "Carts"
local tabs = nil
local renderBag = nil

local TABS = {
	{ id = "Carts", text = "Carts" },
	{ id = "Cargo", text = "Cargo" },
}
local CLASS_ORDER = { Balanced = 1, Scout = 2, Reinforced = 3 }
local ROMAN = { "I", "II", "III", "IV", "V", "VI" }
-- card colours by cart tier (Theme.Plate comment: carts T0/T1/T2/T3 reuse T1/T2/T4/T8)
local TIER_BG = { [0] = P.Tier.T1, [1] = P.Tier.T2, [2] = P.Tier.T4, [3] = P.Tier.T8 }
local INK = P.Color.Ink

local function snapshot()
	return ctx and ctx.snapshot()
end

------------------------------------------------------------------ config-derived data
-- 9 carts sorted by price, then class (Balanced, Scout, Reinforced).
local function cartRows()
	local rows = table.clone(Phase13.CartRows)
	table.sort(rows, function(a, b)
		if a.price ~= b.price then
			return a.price < b.price
		end
		return (CLASS_ORDER[a.classId] or 9) < (CLASS_ORDER[b.classId] or 9)
	end)
	return rows
end

-- Tier = rank of the distinct non-starter price (500M -> T1, 125B -> T2, 6T -> T3); starter = T0.
local function cartTiers(rows)
	local prices = {}
	local seen = {}
	for _, r in rows do
		if not r.starter and r.price > 0 and not seen[r.price] then
			seen[r.price] = true
			table.insert(prices, r.price)
		end
	end
	table.sort(prices)
	local rank = {}
	for i, p in prices do
		rank[p] = i
	end
	local tiers = {}
	for _, r in rows do
		tiers[r.id] = if r.starter or r.price <= 0 then 0 else (rank[r.price] or 1)
	end
	return tiers
end

-- Class speed rank (1 = slowest) from Phase13.Classes, used for the fallback "Speed" pips.
local function speedRanks()
	local list = {}
	for id, c in Phase13.Classes do
		table.insert(list, { id = id, speed = c.speed })
	end
	table.sort(list, function(a, b)
		return a.speed < b.speed
	end)
	local ranks, n = {}, 0
	local last = nil
	for _, e in list do
		if e.speed ~= last then
			n += 1
			last = e.speed
		end
		ranks[e.id] = n
	end
	return ranks, n
end

-- Flair label named by the cart's CartFlairStyles layers (tier layer list in that file's header).
local function flairLabel(assetName: string): string?
	local style = FlairStyles.Carts and FlairStyles.Carts[assetName]
	if not style then
		return nil
	end
	if style.Aura then
		return "Aura + " .. (style.Cycle or "Glow")
	elseif style.Wing and style.Flame then
		return "Wings + Flames"
	elseif style.Trail then
		return "Trails + Smoke"
	end
	return "Neon + Underglow"
end

local function cargoOffers()
	local out = {}
	for _, offer in Upgrades.GetAll() do
		if offer.category == "Cargo" and offer.grant and offer.grant.trackId == "Cargo" then
			table.insert(out, offer)
		end
	end
	table.sort(out, function(a, b)
		return (a.grant.level or 0) < (b.grant.level or 0)
	end)
	return out
end

local function drivingName(s): string
	for _, r in Phase13.CartRows do
		if s and r.id == s.selectedCart then
			return r.displayName
		end
	end
	return "—"
end

------------------------------------------------------------------ small builders
local function plaque(parent: Instance, order: number): Frame
	local f = Plate.frame(parent, "Plaque", {
		BackgroundTransparency = 0.25,
		BackgroundColor3 = INK,
		Size = UDim2.new(0.9, 0, 0, px(22)),
		LayoutOrder = order,
		ZIndex = 6,
	})
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px(3))
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = INK
	st.Thickness = px(2)
	st.Parent = f
	return f
end

local function lampsPlaque(footer: Frame, lit: number, total: number)
	local f = plaque(footer, 1)
	local row = Plate.frame(f, "Row", { Size = UDim2.fromScale(1, 1), ZIndex = 7 })
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, px(4))
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = row
	Plate.Label(row, "Lamps", { size = 15, min = 14, frameSize = UDim2.fromScale(0.42, 0.9), z = 8, order = 0 })
	for i = 1, total do
		local on = i <= lit
		local lamp = Plate.frame(row, "Lamp" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = if on then Color3.fromHex("#FFE14A") else Color3.fromHex("#4A36A0"),
			Size = UDim2.fromOffset(px(11), px(11)),
			LayoutOrder = i,
			ZIndex = 8,
		})
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = lamp
		local st = Instance.new("UIStroke")
		st.Color = INK
		st.Thickness = px(2)
		st.Parent = lamp
		if on and not Juice.reduced() then
			-- flicker (mockup "bulb" 1.1 s, staggered)
			Plate.loop(renderBag, lamp, 0.55, { BackgroundColor3 = Color3.fromHex("#B89A20") }, true, i * 0.35)
		end
	end
end

------------------------------------------------------------------ "Buy at Cargo bay"
-- Closes the stall and points at the bay's anvil (the part tagged CartUpgradeStall): standing nearer
-- the anvil than the counter, its prompt opens the Cargo bay window.
local function pointToCargoBay()
	local part = CargoBay.stallPart()
	if ctx then
		ctx.close()
	end
	if not (part and WorldPointer.show(part, 6, "Cargo bay")) then
		Plate.Toast(MenusV2.Gui(), "Cargo upgrades are at the cart upgrade bay")
	end
end

-- First tries to press the bay's own prompt for the player (the bay window then replaces this one). The
-- engine only accepts that while the prompt is on screen, so if nothing opened, point the way instead.
local function goToCargoBay()
	if not CargoBay.request() then
		pointToCargoBay()
		return
	end
	task.delay(0.8, function()
		if not CargoBay.isOpen() and window and window.isOpen() then
			pointToCargoBay()
		end
	end)
end

------------------------------------------------------------------ render
local function statText(s): string?
	if not s then
		return nil
	end
	if tab == "Cargo" then
		return "Cargo " .. (s.cargoLevel or 0) .. "/" .. #cargoOffers()
	end
	local owned = 0
	for _, r in Phase13.CartRows do
		if s.ownedCarts and s.ownedCarts[r.id] then
			owned += 1
		end
	end
	return "Owned " .. owned .. "/" .. #Phase13.CartRows
end

local function renderCarts(row, s, cardSize, pop)
	local rows = cartRows()
	local tiers = cartTiers(rows)
	local ranks, maxRank = speedRanks()
	local balance = s.balance or 0
	local owned = s.ownedCarts or {}
	-- the ONE breathing primary: the cheapest affordable unowned cart
	local primaryId, cheapest = nil, math.huge
	for _, r in rows do
		if not owned[r.id] and r.price <= balance and r.price < cheapest then
			primaryId, cheapest = r.id, r.price
		end
	end
	local drivenSlot = nil
	for i, r in rows do
		local tier = tiers[r.id]
		local card = Plate.ItemCard(row, {
			name = r.displayName,
			sub = if tier == 0 then "T0 · Starter" else "T" .. tier .. " · " .. r.classId,
			image = Shots.get(r.assetName),
			background = TIER_BG[tier] or P.Tier.T1,
			rainbow = tier == 3,
			rays = tier >= 2,
			size = cardSize,
			index = i,
			bag = renderBag,
			pop = pop,
			onClick = function()
				ctx.preview("Cart", r.assetName)
			end,
		})
		local flair = flairLabel(r.assetName)
		if flair then
			local f = plaque(card.Footer, 1)
			Plate.Label(f, flair, { size = 15, min = 14, frameSize = UDim2.new(1, -px(6), 1, 0), position = UDim2.fromOffset(px(3), 0), z = 8 })
		else
			Plate.Pips(card.Footer, "Speed", ranks[r.classId] or 1, maxRank, { size = UDim2.new(0.9, 0, 0, px(22)), order = 1 })
		end
		if s.selectedCart == r.id then
			drivenSlot = card.Root
			Common.Action(card, { kind = "well", text = "Driving", bag = renderBag })
		elseif owned[r.id] then
			Common.Action(card, { kind = "info", text = "Drive", bag = renderBag, onClick = function()
				ctx.select("Cart", r.id)
			end })
		elseif r.price <= balance then
			Common.Action(card, {
				kind = "go",
				text = Common.money(r.price),
				icon = Theme.Icons.Cash,
				primary = r.id == primaryId,
				bag = renderBag,
				onClick = function()
					ctx.buy("Cart", r.id)
				end,
			})
		else
			Common.Action(card, { kind = "locked", text = "Need " .. Common.money(r.price), bag = renderBag })
		end
	end
	Common.scrollTo(row, drivenSlot)
end

local function renderCargo(row, s, cardSize, pop)
	local offers = cargoOffers()
	local level = s.cargoLevel or 0
	local balance = s.balance or 0
	local total = #offers
	for i, offer in offers do
		local n = offer.grant.level or i
		local card = Plate.ItemCard(row, {
			name = "Cargo " .. (ROMAN[n] or tostring(n)),
			sub = if n <= level then "Lamp Level " .. n else "Lamp Level " .. n .. " · " .. Common.money(offer.price),
			image = nil,
			background = P.Tier.Cargo,
			rays = n >= 2,
			size = cardSize,
			index = i,
			bag = renderBag,
			pop = pop,
		})
		-- no display shot: drop the TODO placeholder and draw the pallet
		for _, child in card.ImageArea:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		CargoBay.pallet(card.ImageArea, n, i, renderBag)
		lampsPlaque(card.Footer, n, total)
		if n <= level then
			Common.Action(card, { kind = "well", text = "Owned", bag = renderBag })
		elseif n == level + 1 then
			-- bought in the Cargo bay window at the bay (needs the server-opened contextId)
			Common.Action(card, {
				kind = "info",
				text = "Buy at Cargo bay",
				primary = offer.price <= balance,
				bag = renderBag,
				onClick = goToCargoBay,
			})
		else
			Common.Action(card, { kind = "locked", text = "Need Cargo " .. (ROMAN[n - 1] or tostring(n - 1)), bag = renderBag })
		end
	end
end

local function render(pop: boolean)
	if not window then
		return
	end
	local s = snapshot()
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	local area = window.Content:FindFirstChild("Cards")
	if area then
		area:Destroy()
	end
	window.setStat(statText(s))
	if tabs then
		tabs.setHint(if tab == "Cargo" then "Bigger cargo = more brainrots per trip" else "Driving: " .. drivingName(s))
	end
	if not s then
		Plate.Label(window.Content, "Loading…", { size = 20, frameSize = UDim2.new(1, 0, 0, px(40)), position = UDim2.fromOffset(0, px(60)) })
		return
	end
	local row = Common.CardRow(window.Content, {
		position = UDim2.fromOffset(0, px(44)),
		size = UDim2.new(1, 0, 1, -px(44)),
	})
	row.Name = "Cards"
	local cardH = window.contentSize().Y - px(44) - px(14)
	local cardSize = UDim2.fromOffset(px(132), math.max(px(170), cardH))
	if tab == "Cargo" then
		renderCargo(row, s, cardSize, pop)
	else
		renderCarts(row, s, cardSize, pop)
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

function Screen.open(context, _category: string?)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Carts",
			title = "Carts",
			icon = Theme.Icons.Cart,
			aspect = 980 / 505, -- Carts.dc.html window
			maxSize = Vector2.new(980 / 1.5, 505 / 1.5),
			onClose = function()
				ctx.close()
			end,
		})
	end
	tab = "Carts"
	window.open()
	window.clearContent()
	tabs = Plate.Tabs(window.Content, { tabs = TABS, active = tab, onSelect = selectTab, bag = window.bag, tabWidth = 104 })
	task.defer(render, true)
end

function Screen.update()
	render(false)
end

function Screen.notify(result, text)
	Common.notify(MenusV2.Gui(), result, text)
end

function Screen.close(instant: boolean?)
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
