--!nocheck
-- MenusV2 Sell stall (from the legacy "Sell" branch). Opened only by the Sell stall prompt (server
-- Phase13Update {kind="Open", category="Sell"}); Phase13ShopController keeps every remote call:
--   Brainrots -> ctx.sellList()              = {action="SellList"} (banked brainrots + server sale values)
--                ctx.sellBanked(ids, total)  = {action="SellBanked", ids, expectedTotal} (one request)
--                ctx.sellCarried()           = {action="SellCarried"} (server opens BrainrotSaleController)
--   Weapons   -> ctx.sellBack("Weapon", id)  = {action="SellBack", category, id, operationId}
--   Carts     -> ctx.sellBack("Cart", id)    (one call per picked item, sequential)
-- Values: the same floor(price * 0.25) the legacy client shows. Brainrot prices are never computed
-- here: each banked row carries the server's value, and the carried one is priced by the server dialog.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Tiers = require(ReplicatedStorage.Shared.Config.WeaponTiersV2)
local Config = require(ReplicatedStorage.Shared.Config.Phase13)
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local RATE = 0.25 -- legacy Sell branch (Phase13Rules.SellBackValue = floor(price * 0.25))
local PICK_GREEN = Color3.fromHex("#8DFF3A")
local STOP_RED = Color3.fromHex("#FF6B7A")
local LEFT_W = 112 -- baseline px
local BAR_H = 56
local GAP = 8

local player = Players.LocalPlayer

local Screen = {}

local ctx = nil
local window = nil
local tab = "Brainrots"
local sort = "Value"
local picked = {} -- [id] = true (current tab only)
local selling = false
local sellToken = 0
local renderBag = nil
local barBag = nil -- left column + bottom bar (rebuilt on every pick)
local chromeBag = nil -- side tabs + attribute watchers (cleaned on close)
local sideTabs = {}
local confirmWin = nil
local totalShown = 0
-- Banked brainrots (server list). `token` drops a reply that arrives after a newer request or a close.
local banked = { rows = nil, loading = false, token = 0, failed = false }
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Celestial", "Secret" }
local SAFE_RANK = 2 -- "Pick Commons" picks Common and Uncommon only; rarer ones are tapped one by one
local function rarityRank(tier): number
	return table.find(RARITY_ORDER, tier) or 1
end

local TABS = {
	{ id = "Brainrots", text = "Brainrots" },
	{ id = "Weapon", text = "Weapons" },
	{ id = "Cart", text = "Carts" },
}

local function snapshot()
	return ctx and ctx.snapshot()
end

------------------------------------------------------------------ data
-- Cart tier is implicit by price (DATA_CONTRACT §4): rank of distinct prices, mapped T1/T2/T4/T8.
local CART_TIER_MAP = { 1, 2, 4, 8 }
local function cartTier(price: number): number
	local prices = {}
	for _, row in Config.CartRows do
		if not table.find(prices, row.price) then
			table.insert(prices, row.price)
		end
	end
	table.sort(prices)
	local rank = table.find(prices, price) or 1
	return CART_TIER_MAP[math.clamp(rank, 1, #CART_TIER_MAP)] or 1
end

-- Same rows and filters as the legacy Sell branch.
local function sellRows(s, category: string)
	local rows = {}
	if category == "Brainrots" then
		-- server rows; a brainrot that is still saving its bank can't be sold yet
		for _, r in banked.rows or {} do
			local rank = rarityRank(r.tier)
			local mutated = type(r.mutationId) == "string" and r.mutationId ~= "None"
			table.insert(rows, {
				id = r.id,
				name = r.displayName,
				value = r.sellValue,
				tier = rank,
				rarity = r.tier,
				image = Shots.get(r.speciesId),
				-- a favourite, or one still saving its bank, can't be picked
				inUse = r.saving == true or r.favourite == true,
				favourite = r.favourite == true,
				blockedText = if r.saving == true then "Saving" else nil,
				blockedToast = if r.favourite == true then "That's a favourite. Tap its star to unstar it."
					else "Still saving. Try again in a moment.",
				brainrot = true,
				mutationId = if mutated then r.mutationId else nil,
				team = r.team == true,
				-- never part of "Pick Commons", and named in a second confirm
				risky = rank > SAFE_RANK or mutated or r.team == true,
			})
		end
	end
	if not s then
		return rows
	end
	if category == "Weapon" then
		for _, row in Weapons.GetAll() do
			if s.ownedWeapons[row.id] == true and Weapons.IsSellable(row.id) then
				table.insert(rows, {
					id = row.id,
					name = row.displayName,
					value = math.floor(row.price * RATE),
					tier = Tiers.TierFromWeaponId(row.id) or 1,
					image = Shots.get(row.id),
					inUse = s.selectedWeapon == row.id,
				})
			end
		end
	elseif category == "Cart" then
		for _, row in Config.CartRows do
			if s.ownedCarts[row.id] == true and not row.starter and row.price > 0 then
				table.insert(rows, {
					id = row.id,
					name = row.displayName,
					value = math.floor(row.price * RATE),
					tier = cartTier(row.price),
					image = Shots.get(row.assetName),
					inUse = s.selectedCart == row.id,
				})
			end
		end
	end
	table.sort(rows, function(a, b)
		if sort == "Rarity" and a.tier ~= b.tier then
			return a.tier > b.tier
		end
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.name < b.name
	end)
	return rows
end

-- The carried brainrot, found the way BrainrotInteractionController does.
local function carriedSpecies(): string?
	local species = player:GetAttribute("CarriedBrainrotId")
	if type(species) ~= "string" then
		local char = player.Character
		local carried = char and char:FindFirstChild("CarriedBrainrot")
		species = carried and carried:GetAttribute("BrainrotId")
	end
	if type(species) == "string" then
		return species
	end
	return nil
end

local function isCarrying(): boolean
	return player:GetAttribute("CarriedItemId") ~= nil or carriedSpecies() ~= nil
end

local function pickedCount(): number
	local n = 0
	for _ in picked do
		n += 1
	end
	return n
end

------------------------------------------------------------------ small builders
local function panel(parent: Instance, name: string, props): Frame
	local f = Plate.frame(parent, name, props)
	f.BackgroundTransparency = 0.15
	f.BackgroundColor3 = P.Color.Ink
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px(P.Radius.Card))
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromHex("#3A3D50")
	st.Thickness = px(2)
	st.Parent = f
	return f
end

local function vlist(parent: Instance, gap: number)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, px(gap))
	l.Parent = parent
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, px(8))
	pad.PaddingLeft = UDim.new(0, px(6))
	pad.PaddingRight = UDim.new(0, px(6))
	pad.Parent = parent
	return l
end

local render, renderChrome -- forward

local function statText(): string
	return "Picked " .. pickedCount()
end

-- Stars or unstars one banked brainrot. The row is updated from the server's answer.
local favouriteBusy = false
local function toggleFavourite(r)
	if selling or favouriteBusy or not ctx then
		return
	end
	favouriteBusy = true
	local context, want = ctx, not r.favourite
	task.spawn(function()
		local result = context.setFavourite(r.id, want)
		favouriteBusy = false
		if type(result) == "table" and result.ok then
			for _, row in banked.rows or {} do
				if row.id == r.id then
					row.favourite = result.favourite == true
				end
			end
			if result.favourite then
				picked[r.id] = nil
			end
			if window and window.isOpen() then
				Juice.sound("Click")
				Plate.Toast(MenusV2.Gui(), if result.favourite then "Favourite! It can't be sold." else "Not a favourite any more", {
					color = if result.favourite then Common.StarGold else P.Color.White,
				})
			end
		end
		if tab == "Brainrots" and window and window.isOpen() then
			render(false)
		end
	end)
end

-- Asks the server for the banked list again (on open, on the Brainrots tab, after a sale).
local function fetchBanked()
	if not ctx then
		return
	end
	banked.token += 1
	local token = banked.token
	banked.loading = true
	local context = ctx
	task.spawn(function()
		local result = context.sellList()
		if token ~= banked.token then
			return
		end
		banked.loading = false
		if type(result) == "table" and result.ok and type(result.rows) == "table" then
			banked.rows, banked.failed = result.rows, false
		else
			banked.failed = true
		end
		if tab == "Brainrots" and window and window.isOpen() then
			render(false)
		end
	end)
end

------------------------------------------------------------------ render

local function setPickVisual(entry, on: boolean, animate: boolean)
	entry.stroke.Color = if on then PICK_GREEN else entry.ring
	entry.stroke.Thickness = if on then px(4) else px(P.Stroke.Outline)
	entry.tick.Visible = on
	if on and animate and not Juice.reduced() then
		Juice.pop(entry.tick, 1.4)
	end
end

-- One confirm dialog above the Sell window. Replaces any confirm already open.
local function openConfirm(props)
	if confirmWin then
		confirmWin.destroy()
		confirmWin = nil
	end
	local gui = MenusV2.Gui()
	local win
	local function done()
		task.delay(0.5, win.destroy)
		if confirmWin == win then
			confirmWin = nil
		end
	end
	win = Plate.Confirm(gui, {
		title = props.title,
		body = props.body,
		confirmText = props.confirmText or "Sell",
		confirmVariant = "stop",
		confirmIcon = Theme.Icons.Cash,
		onConfirm = function()
			done()
			props.onConfirm()
		end,
		onCancel = done,
	})
	-- above the Sell window (Sibling ZIndex: both windows sit at ZIndex 1/2)
	win.Root.ZIndex = 4
	for _, child in gui:GetChildren() do
		if child.Name == "Dialog_Scrim" then
			child.ZIndex = 3
		end
	end
	confirmWin = win
end

local function plural(n: number, word: string): string
	return string.format("%d %s%s", n, word, if n == 1 then "" else "s")
end

-- "Epic Cavallo, Shiny Glorbo, Lirili (on your team) and 2 more": each name says why it was flagged
local function riskyNames(list): string
	local names = {}
	for i, r in list do
		if i > 3 then
			break
		end
		local name = r.name
		if r.mutationId then
			name = r.mutationId .. " " .. name
		elseif r.tier > SAFE_RANK then
			name = r.rarity .. " " .. name
		end
		if r.team then
			name ..= " (on your team)"
		end
		table.insert(names, name)
	end
	local text = table.concat(names, ", ")
	if #list > 3 then
		text ..= " and " .. (#list - 3) .. " more"
	end
	return text
end

-- Banked brainrots: one server request for the whole pick. The total sent is the total shown; the
-- server refuses the sale if its own total differs.
local function sellPickedBrainrots()
	local rows = sellRows(snapshot(), "Brainrots")
	local list, ids, risky, total = {}, {}, {}, 0
	for _, r in rows do
		if picked[r.id] and not r.inUse then
			table.insert(list, r)
			table.insert(ids, r.id)
			total += r.value
			if r.risky then
				table.insert(risky, r)
			end
		end
	end
	if #list == 0 then
		return
	end
	local function go()
		if selling or not ctx then
			return
		end
		sellToken += 1
		local token = sellToken
		selling = true
		render(false)
		local context = ctx
		task.spawn(function()
			local result = context.sellBanked(ids, total)
			if token ~= sellToken then
				return
			end
			selling = false
			if type(result) == "table" and result.ok then
				local gone = {}
				for _, id in result.soldIds or {} do
					gone[id] = true
					picked[id] = nil
				end
				local kept = {}
				for _, r in banked.rows or {} do
					if not gone[r.id] then
						table.insert(kept, r)
					end
				end
				banked.rows = kept
				if window and window.isOpen() then
					local gui = MenusV2.Gui()
					Plate.Toast(gui, "+" .. Common.money(result.paid) .. "!", { icon = Theme.Icons.Cash })
					if result.code == "PartlySold" then
						Plate.Toast(gui, string.format("Sold %d of %d", result.sold, result.requested), { color = STOP_RED, top = 0.3 })
					end
					Juice.sound("Purchase", 0.05)
				end
			end
			fetchBanked() -- the server list is the truth, sold or refused
			render(false)
		end)
	end
	local body = string.format("You get %s Cash. This can't be undone.", Common.money(total))
	openConfirm({
		title = "Sell " .. plural(#list, "brainrot") .. "?",
		body = body,
		onConfirm = function()
			if #risky == 0 then
				go()
				return
			end
			-- rare, mutated or team brainrots get a second, named confirm
			task.delay(0.55, function()
				if not window or not window.isOpen() or tab ~= "Brainrots" or selling then
					return
				end
				openConfirm({
					title = "Are you sure?",
					body = "This sells " .. riskyNames(risky) .. ". Gone for good!",
					confirmText = if #list == 1 then "Sell it" else "Sell them",
					onConfirm = go,
				})
			end)
		end,
	})
end

local function sellPicked()
	if selling or not ctx then
		return
	end
	if tab == "Brainrots" then
		sellPickedBrainrots()
		return
	end
	local s = snapshot()
	local rows = sellRows(s, tab)
	local list, total = {}, 0
	for _, r in rows do
		if picked[r.id] and not r.inUse then
			table.insert(list, r)
			total += r.value
		end
	end
	if #list == 0 then
		return
	end
	local category = tab
	openConfirm({
		title = "Sell " .. plural(#list, "item") .. "?",
		body = string.format("You get %s Cash. This can't be undone.", Common.money(total)),
		onConfirm = function()
			sellToken += 1
			local token = sellToken
			selling = true
			render(false)
			task.spawn(function()
				local soldValue, soldCount = 0, 0
				local function waitIdle(): boolean
					local t0 = os.clock()
					while ctx and ctx.isBusy() do
						if token ~= sellToken or os.clock() - t0 > 15 then
							return false
						end
						task.wait(0.2)
					end
					return token == sellToken
				end
				for _, r in list do
					if not waitIdle() then
						break
					end
					ctx.sellBack(category, r.id)
					if not waitIdle() then
						break
					end
					local now = snapshot()
					local owned = now and (if category == "Weapon" then now.ownedWeapons else now.ownedCarts)
					if owned and owned[r.id] ~= true then
						soldValue += r.value
						soldCount += 1
						picked[r.id] = nil
					else
						break -- rejected (the controller already toasted why); stop the batch
					end
				end
				if token ~= sellToken then
					return
				end
				selling = false
				if soldCount > 0 and window and window.isOpen() then
					Plate.Toast(MenusV2.Gui(), "+" .. Common.money(soldValue) .. "!", { icon = Theme.Icons.Cash })
					Juice.sound("Purchase", 0.05)
				end
				render(false)
			end)
		end,
	})
end

local function buildLeftColumn(content: Frame, height: number)
	local col = panel(content, "LeftColumn", {
		Size = UDim2.fromOffset(px(LEFT_W), height),
		ZIndex = 5,
	})
	vlist(col, 6)
	Plate.Label(col, "Sort By:", { size = 18, frameSize = UDim2.new(1, 0, 0, px(22)), order = 1, z = 6 })
	local sortRow = Plate.frame(col, "SortRow", { Size = UDim2.new(1, 0, 0, px(38)), LayoutOrder = 2, ZIndex = 6 })
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sl.Padding = UDim.new(0, px(4))
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = sortRow
	for i, k in { "Value", "Rarity" } do
		Plate.Button(sortRow, {
			variant = if sort == k then "go" else "tabOff",
			text = k,
			size = UDim2.new(0.5, -px(2), 1, 0),
			order = i,
			textSize = 16,
			bag = barBag,
			onClick = function()
				if sort ~= k then
					sort = k
					render(true)
				end
			end,
		})
	end
	local rows = sellRows(snapshot(), tab)
	-- Brainrots: the one-tap pick is Common/Uncommon, un-mutated and off the team only
	local selectLabel = if tab == "Brainrots" then "Pick Commons" else "Select All"
	local pickable, allPicked = 0, true
	for _, r in rows do
		if not r.inUse and not r.risky then
			pickable += 1
			if not picked[r.id] then
				allPicked = false
			end
		end
	end
	local clear = if pickable > 0 then allPicked else pickedCount() > 0
	Plate.Button(col, {
		variant = if pickable == 0 and not clear then "locked" else "info",
		text = if clear then "Clear" else selectLabel,
		lockedReason = if tab == "Brainrots" then "Commons" else selectLabel, -- room for the lock icon
		icon = if clear or pickable == 0 or tab == "Brainrots" then nil else Theme.Icons.Check,
		size = UDim2.new(1, 0, 0, px(34)),
		order = 5,
		textSize = if tab == "Brainrots" then 15 else 17,
		bag = barBag,
		onClick = function()
			if selling then
				return
			end
			if clear then
				table.clear(picked)
			else
				for _, r in rows do
					if not r.inUse and not r.risky then
						picked[r.id] = true
					end
				end
			end
			render(false)
		end,
	})
	local hint = if tab == "Weapon" then "Starter, won and premium weapons can't be sold"
		elseif tab == "Brainrots" then "Star = safe. Rare ones: tap each"
		else "Tap to pick, then Sell"
	Plate.Label(col, hint, {
		size = 15,
		min = 14,
		wrap = true,
		color = P.Color.Hint,
		frameSize = UDim2.new(1, 0, 0, px(52)),
		order = 6,
		z = 6,
	})
end

local function hopIcon(parent: Instance, order: number): ImageLabel
	local holder = Plate.frame(parent, "CashIcon", { Size = UDim2.fromOffset(px(30), px(30)), LayoutOrder = order, ZIndex = 6 })
	local ic = Plate.Icon(holder, Theme.Icons.Cash, UDim2.fromScale(1, 1), 7)
	ic.AnchorPoint = Vector2.new(0.5, 1)
	ic.Position = UDim2.fromScale(0.5, 1)
	if not Juice.reduced() then
		Plate.loop(barBag, ic, 0.8, { Position = UDim2.new(0.5, 0, 1, -px(5)) }, true)
	end
	return ic
end

local function buildBottomBar(content: Frame, y: number, total: number, count: number)
	local bar = panel(content, "BottomBar", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, px(BAR_H)),
		ZIndex = 5,
	})
	local left = Plate.frame(bar, "Left", { Position = UDim2.fromOffset(px(12), 0), Size = UDim2.new(1, -px(200), 1, 0), ZIndex = 6 })
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, px(8))
	l.Parent = left
	local btnSize = UDim2.fromOffset(px(170), px(44))
	local btnPos = UDim2.new(1, -px(10), 0.5, 0)
	local anchor = Vector2.new(1, 0.5)

	Plate.Label(left, "Total Value:", {
		size = 22,
		font = P.Font.Title,
		frameSize = UDim2.fromOffset(px(130), px(40)),
		align = Enum.TextXAlignment.Left,
		order = 1,
		z = 7,
	})
	hopIcon(left, 2)
	local totalLabel = Plate.Label(left, Common.money(totalShown), {
		size = 28,
		font = P.Font.Title,
		color = P.Color.Cash,
		frameSize = UDim2.fromOffset(px(110), px(40)),
		align = Enum.TextXAlignment.Left,
		order = 3,
		z = 7,
	})
	if total ~= totalShown and not Juice.reduced() then
		Juice.countUp(totalLabel, totalShown, total, Common.money)
	else
		totalLabel.Text = Common.money(total)
	end
	totalShown = total
	if count > 0 and not Juice.reduced() then
		local sc = Juice.scaleOf(totalLabel)
		Plate.loop(barBag, sc, 0.7, { Scale = 1.08 }, true)
	end
	Plate.Label(left, count .. " picked", {
		size = 16,
		color = P.Color.Hint,
		frameSize = UDim2.fromOffset(px(70), px(30)),
		align = Enum.TextXAlignment.Left,
		order = 4,
		z = 7,
	})
	if selling then
		Plate.Button(bar, { variant = "locked", lockedReason = "Selling…", size = btnSize, position = btnPos, anchor = anchor, textSize = 22, bag = barBag })
	elseif count == 0 then
		Plate.Button(bar, { variant = "locked", lockedReason = "Pick One", size = btnSize, position = btnPos, anchor = anchor, textSize = 22, bag = barBag })
	else
		Plate.Button(bar, {
			variant = "stop",
			text = "Sell",
			primary = true,
			size = btnSize,
			position = btnPos,
			anchor = anchor,
			textSize = 24,
			bag = barBag,
			name = "SellPicked",
			onClick = sellPicked,
		})
	end
end

local function buildGrid(area: Frame, areaW: number, areaH: number, rows)
	local grid = Common.CardGrid(area, {
		position = UDim2.new(),
		size = UDim2.fromOffset(areaW, areaH),
		cell = Vector2.new(90, 100),
		gap = GAP,
	})
	grid.Name = "Grid"
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	local cellW = math.floor((areaW - px(12) - 4 * px(GAP)) / 5)
	local cellH = math.floor(cellW * 1.1)
	layout.CellSize = UDim2.fromOffset(cellW, cellH)
	local brainrots = tab == "Brainrots"
	local carrying = brainrots and isCarrying()
	if #rows == 0 and not carrying then
		grid:Destroy()
		local title, sub = "Nothing else to sell", "Starter, Robux, Gem and won items are never sold."
		if brainrots then
			if banked.rows == nil then
				title = if banked.failed then "Couldn't load your brainrots" else "Loading…"
				sub = if banked.failed then "Close the window and open it again." else ""
			else
				title, sub = "No brainrots on your platforms", "Bank one at your base, then sell it here."
			end
		end
		Plate.Label(area, title, { size = 22, frameSize = UDim2.new(1, 0, 0, px(34)), position = UDim2.fromOffset(0, px(40)), z = 6 })
		Plate.Label(area, sub, {
			size = 16,
			color = P.Color.Hint,
			frameSize = UDim2.new(1, 0, 0, px(24)),
			position = UDim2.fromOffset(0, px(78)),
			z = 6,
		})
		return
	end
	if carrying then
		-- the brainrot in the player's hands keeps its own sale: the server prices it in its dialog
		local species = carriedSpecies()
		local def = species and Catalog.Get(species)
		local tier = def and def.tier or nil
		local card = Plate.ItemCard(grid, {
			name = if def then def.displayName else "Your brainrot",
			image = if species then Shots.get(species) else "",
			background = P.Tier.Dark,
			ring = PICK_GREEN,
			rays = tier ~= nil and rarityRank(tier) > SAFE_RANK,
			compact = true,
			size = UDim2.fromOffset(cellW, cellH),
			index = 0,
			bag = renderBag,
			pop = renderBag.pop,
			onClick = function()
				if selling or not ctx or ctx.isBusy() then
					return
				end
				ctx.sellCarried() -- ok: the controller closes the shop and the server opens the sale dialog
			end,
		})
		card.Root.Name = "Card_Carried"
		Plate.Label(card.Footer, "Carried: Sell", { size = 17, min = 14, font = P.Font.Title, color = PICK_GREEN, frameSize = UDim2.fromScale(0.95, 0.95), order = 1 })
	end
	for i, r in rows do
		local style = Common.tierStyle(r.tier)
		-- rarity ring, darkened so the bright green "picked" ring never reads as Uncommon
		local ring = if brainrots
			then (Theme.Rarity[r.rarity] or P.Color.White):Lerp(P.Color.Ink, 0.45)
			else style.background[#style.background]
		local entry = {}
		local card = Plate.ItemCard(grid, {
			name = r.name,
			image = r.image,
			background = P.Tier.Dark,
			ring = ring,
			compact = true,
			size = UDim2.fromOffset(cellW, cellH),
			index = i,
			bag = renderBag,
			pop = renderBag.pop,
			onClick = function()
				if selling then
					return
				end
				if r.inUse then
					Plate.Toast(MenusV2.Gui(), r.blockedToast or "In use: switch first", { color = STOP_RED })
					return
				end
				local on = not picked[r.id]
				picked[r.id] = on or nil
				setPickVisual(entry, on, true)
				renderChrome()
			end,
		})
		entry.ring = ring
		entry.stroke = card.Outer:FindFirstChildOfClass("UIStroke")
		local tick = Plate.Icon(card.Outer, Theme.Icons.Check, UDim2.fromOffset(px(24), px(24)), 13)
		tick.AnchorPoint = Vector2.new(1, 0)
		tick.Position = UDim2.new(1, -px(3), 0, px(3))
		tick.Visible = false
		entry.tick = tick
		if r.mutationId or r.team then
			-- what makes this one special, on the picture (the footer keeps the price)
			Plate.Label(card.ImageArea, r.mutationId or "Team", {
				size = 14,
				min = 14,
				font = P.Font.Title,
				color = if r.mutationId then (Theme.Mutation[r.mutationId] or P.Color.White) else PICK_GREEN,
				align = Enum.TextXAlignment.Left,
				frameSize = UDim2.new(1, -px(6), 0, px(16)),
				position = UDim2.new(0, px(4), 1, -px(18)),
				z = 12,
				name = "Tag",
			})
		end
		if r.brainrot then
			-- favourite star: its own button above the card's hit area (a starred brainrot can't be sold)
			local starButton = Instance.new("TextButton")
			starButton.Name = "StarButton"
			starButton.Text = ""
			starButton.BackgroundTransparency = 1
			starButton.Size = UDim2.fromOffset(px(34), px(34))
			starButton.ZIndex = 14
			starButton.Parent = card.Outer
			Common.Star(starButton, r.favourite, { size = 34, anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5), z = 15 })
			renderBag.add(starButton.Activated:Connect(function()
				toggleFavourite(r)
			end))
		end
		if r.inUse and (r.blockedText or not r.brainrot) then
			Plate.Label(card.Footer, r.blockedText or "In use", { size = 16, min = 14, color = P.Color.Hint, frameSize = UDim2.fromScale(0.95, 0.95), order = 1 })
		else
			Plate.Label(card.Footer, Common.money(r.value), { size = 20, min = 14, font = P.Font.Title, color = P.Color.Cash, frameSize = UDim2.fromScale(0.95, 0.95), order = 1 })
		end
		setPickVisual(entry, picked[r.id] == true, false)
	end
end

-- current rows, and the picked total/count (drops picks that were sold or became in use)
local function tally()
	local rows = sellRows(snapshot(), tab)
	local total, count, present = 0, 0, {}
	for _, r in rows do
		if not r.inUse then
			present[r.id] = true
			if picked[r.id] then
				total += r.value
				count += 1
			end
		end
	end
	for id in picked do
		if not present[id] then
			picked[id] = nil
		end
	end
	return rows, total, count
end

-- Left column, bottom bar and stat pill only (a pick never rebuilds the cards).
renderChrome = function()
	if not window or not window.isOpen() or not snapshot() then
		return
	end
	if barBag then
		barBag.clean()
	end
	barBag = Plate.Bag()
	for _, name in { "LeftColumn", "BottomBar" } do
		local old = window.Content:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local _, total, count = tally()
	window.setStat(statText())
	local ch = window.contentSize().Y
	buildLeftColumn(window.Content, ch - px(BAR_H) - px(6))
	buildBottomBar(window.Content, ch - px(BAR_H), total, count)
end

render = function(pop: boolean)
	if not window or not window.isOpen() then
		return
	end
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	renderBag.pop = pop
	local old = window.Content:FindFirstChild("Area")
	if old then
		old:Destroy()
	end
	local s = snapshot()
	local rows = tally()
	if not s then
		window.setStat(statText())
		Plate.Label(window.Content, "Loading…", { size = 20, frameSize = UDim2.new(1, 0, 0, px(40)), position = UDim2.fromOffset(0, px(60)), name = "Area" })
		return
	end
	local cw, ch = window.contentSize().X, window.contentSize().Y
	local topH = ch - px(BAR_H) - px(6)
	local areaW = cw - px(LEFT_W) - px(GAP)
	local area = Plate.frame(window.Content, "Area", {
		Position = UDim2.fromOffset(px(LEFT_W) + px(GAP), 0),
		Size = UDim2.fromOffset(areaW, topH),
		ZIndex = 5,
	})
	buildGrid(area, areaW, topH, rows)
	renderChrome()
end

------------------------------------------------------------------ side tabs (outside the right edge)
local function sideTabImage(id: string): string
	if id == "Brainrots" then
		return Shots.get(carriedSpecies() or "BRT_019")
	elseif id == "Weapon" then
		return Shots.get("HRP_001")
	end
	return Shots.get("ScrapChariot")
end

local function selectTab(id: string)
	if id == tab or selling then
		return
	end
	tab = id
	table.clear(picked)
	totalShown = 0
	for tid, b in sideTabs do
		b.setVariant(if tid == tab then "go" else "tabOff")
	end
	if tab == "Brainrots" then
		fetchBanked()
	end
	render(true)
end

local function buildSideTabs()
	local col = Plate.frame(window.Root, "SideTabs", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(1, px(10), 0, px(56)),
		Size = UDim2.new(0, px(76), 1, -px(70)),
		ZIndex = 3,
	})
	chromeBag.add(col)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, px(10))
	l.Parent = col
	table.clear(sideTabs)
	for i, t in TABS do
		local b = Plate.Button(col, {
			variant = if t.id == tab then "go" else "tabOff",
			text = t.text,
			size = UDim2.fromOffset(px(76), px(72)),
			order = i,
			textSize = 16,
			bag = chromeBag,
			name = "SideTab_" .. t.id,
			onClick = function()
				selectTab(t.id)
			end,
		})
		local row = b.Face:FindFirstChild("Row")
		if row then
			row.Size = UDim2.fromScale(1, 0.4)
		end
		local img = sideTabImage(t.id)
		if img ~= "" then
			local im = Plate.Icon(b.Face, img, UDim2.fromScale(0.62, 0.55), 8)
			im.AnchorPoint = Vector2.new(0.5, 1)
			im.Position = UDim2.new(0.5, 0, 1, -px(4))
		end
		sideTabs[t.id] = b
	end
end

------------------------------------------------------------------ screen API
function Screen.open(context, _category: string?)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Sell",
			title = "Sell",
			icon = Theme.Icons.Cash,
			particles = "bills",
			aspect = 2.05,
			widthScale = 0.8,
			maxSize = Vector2.new(650, 320),
			onClose = function()
				ctx.close()
			end,
		})
		window.Root.Position = UDim2.fromScale(0.47, 0.53) -- room for the side tabs
	end
	sellToken += 1
	selling = false
	tab = "Brainrots"
	sort = "Value"
	table.clear(picked)
	totalShown = 0
	banked.rows, banked.loading, banked.failed = nil, false, false
	if chromeBag then
		chromeBag.clean()
	end
	chromeBag = Plate.Bag()
	window.open()
	window.clearContent()
	buildSideTabs()
	-- the carried brainrot can change while the window is open (dropped, banked)
	for _, attr in { "CarriedItemId", "CarriedBrainrotId" } do
		chromeBag.add(player:GetAttributeChangedSignal(attr):Connect(function()
			if tab == "Brainrots" then
				render(false)
			end
		end))
	end
	fetchBanked()
	task.defer(render, true)
end

function Screen.update()
	render(false)
end

function Screen.notify(result, text)
	Common.notify(MenusV2.Gui(), result, text)
end

function Screen.close(instant: boolean?)
	sellToken += 1 -- stops a running batch after its current item
	banked.token += 1 -- drops a list reply that is still on its way
	banked.loading = false
	selling = false
	if confirmWin then
		confirmWin.destroy()
		confirmWin = nil
	end
	if renderBag then
		renderBag.clean()
		renderBag = nil
	end
	if barBag then
		barBag.clean()
		barBag = nil
	end
	if chromeBag then
		chromeBag.clean()
		chromeBag = nil
	end
	table.clear(sideTabs)
	if window then
		window.close(instant)
	end
end

return Screen
