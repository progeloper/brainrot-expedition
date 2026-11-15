--!nocheck
-- MenusV2 HUD "Inventory" window (I key / HUD button). Owned items only; no buying here.
-- Every action reuses Phase13ShopController's facade (deps.shop.Context()):
--   Equip weapon  -> ctx.select("Weapon", id)
--   Drive cart    -> ctx.select("Cart", id)
--   Select design -> ctx.select("Design", id)
-- The server only accepts Select near the right place (Phase13RuntimeService ValidateContext,
-- DATA_CONTRACT §1.8): Weapon <= 12 studs from the Weapons stall anchor; Cart <= 12 from the Carts
-- stall anchor or <= 18 from the player's own CartSpawn; Design <= 12 from the own base entrance.
-- The same distance check decides here whether the button is live or a locked "go there" button
-- (tap = 6 s bouncing arrow over the place, WorldPointer). ⚙ in the header opens the existing
-- Settings view (deps.shop.OpenAppearance()).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local WorldPointer = require(script.Parent.WorldPointer)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Tiers = require(ReplicatedStorage.Shared.Config.WeaponTiersV2)
local Phase13 = require(ReplicatedStorage.Shared.Config.Phase13)

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local WINDOW_ID = "Inventory"

-- server ranges (Phase13RuntimeService.ValidateContext)
local WEAPON_RANGE = 12
local CART_STALL_RANGE = 12
local CART_DOCK_RANGE = 18
local BASE_RANGE = 12

local Screen = {}

local deps = nil
local ctx = nil
local window = nil
local isOpen = false
local tab = "Weapons"
local tabs = nil
local renderBag = nil
local openBag = nil
local lastNear = ""

local TABS = {
	{ id = "Weapons", text = "Weapons" },
	{ id = "Carts", text = "Carts" },
	{ id = "Bases", text = "Bases" },
}
-- Playtest Fixes 2 Part G: Inventory > Trails (LegsTrainingV1Enabled). One trail equipped at a time.
local Legs = require(ReplicatedStorage.Shared.Config.LegsTraining)
local legsOn = require(ReplicatedStorage.Shared.Config.LegsTrainingFlags).Enabled()
if legsOn then
	table.insert(TABS, { id = "Trails", text = "Trails" })
end

local FAMILIES = {
	{ id = "Bow", label = "Bows" },
	{ id = "Crossbow", label = "Crossbows" },
	{ id = "Gun", label = "Blasters" },
}
local FAMILY_NAME = { Bow = "Bow", Crossbow = "Crossbow", Gun = "Blaster" }

------------------------------------------------------------------ world places (cached per open)

local places = { at = -math.huge }

local function valid(x: Instance?): boolean
	return x ~= nil and x:IsDescendantOf(workspace)
end

local function resolvePlaces()
	if valid(places.weapon) and valid(places.cart) and valid(places.entrance) then
		return places
	end
	if os.clock() - places.at < 3 then
		return places
	end
	places.at = os.clock()
	if not valid(places.weapon) then
		local _, anchor = WorldPointer.stallPrompt("Weapon")
		places.weapon = anchor
	end
	if not valid(places.cart) then
		local _, anchor = WorldPointer.stallPrompt("Cart")
		places.cart = anchor
	end
	if not valid(places.entrance) then
		places.entrance = WorldPointer.baseEntrance()
	end
	local base = WorldPointer.ownBase()
	places.dock = base and base:FindFirstChild("CartSpawn")
	return places
end

local function nearState()
	local pl = resolvePlaces()
	return {
		weapon = WorldPointer.distanceTo(pl.weapon) <= WEAPON_RANGE,
		cart = WorldPointer.distanceTo(pl.cart) <= CART_STALL_RANGE or WorldPointer.distanceTo(pl.dock) <= CART_DOCK_RANGE,
		base = WorldPointer.distanceTo(pl.entrance) <= BASE_RANGE,
	}
end

local function nearKey(n): string
	return (if n.weapon then "W" else "-") .. (if n.cart then "C" else "-") .. (if n.base then "B" else "-")
end

------------------------------------------------------------------ helpers

local function snapshot()
	return ctx and ctx.snapshot()
end

local function toast(text: string)
	Plate.Toast(MenusV2.Gui(), text, { color = P.Color.White })
end

-- Close the window and point at a place in the world.
local function pointTo(kind: string)
	local pl = resolvePlaces()
	local target, label, fallback
	if kind == "Weapon" then
		target, label, fallback = pl.weapon, "Weapons", "The Weapons stall is at camp"
	elseif kind == "Cart" then
		target, label, fallback = pl.cart, "Carts", "The Carts stall is at camp"
	else
		target, label, fallback = pl.entrance, "Your base", "Head to your base entrance"
	end
	Screen.close(false)
	if not WorldPointer.show(target, 6, label) then
		toast(fallback)
	end
end

-- carts: card colours by price step (T0/T1/T2/T3 -> Tier T1/T2/T4/T8)
local CART_TIER = {}
do
	local prices = {}
	for _, row in Phase13.CartRows do
		if not table.find(prices, row.price) then
			table.insert(prices, row.price)
		end
	end
	table.sort(prices)
	local map = { 1, 2, 4, 8 }
	for _, row in Phase13.CartRows do
		local rank = table.find(prices, row.price) or 1
		CART_TIER[row.id] = map[math.min(rank, #map)]
	end
end

local function cardSize()
	-- content height at the window's resting scale (the open tween starts smaller)
	local scale = window.Root:FindFirstChild("OpenScale")
	local k = if scale and scale.Scale > 0 then scale.Scale else 1
	local h = window.Content.AbsoluteSize.Y / k - px(44) - px(14)
	return UDim2.fromOffset(px(158), math.max(px(170), h))
end

local function divider(row: Instance, text: string, order: number)
	local f = Instance.new("Frame")
	f.Name = "Group_" .. text
	f.BackgroundColor3 = P.Color.Well
	f.BorderSizePixel = 0
	f.Size = UDim2.new(0, px(30), 1, -px(14))
	f.LayoutOrder = order
	f.ZIndex = 5
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, P.Radius.Card)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Thickness = px(2)
	s.Color = P.Color.Ink
	s.Parent = f
	f.Parent = row
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(px(150), px(26))
	holder.Rotation = -90
	holder.ZIndex = 6
	holder.Parent = f
	Plate.Label(holder, text, { size = 18, z = 6 })
	return f
end

-- Locked "go there" button: the shake comes from Plate; the tap also shows the world arrow.
local function lockedGo(card, text: string, kind: string)
	local b = Common.Action(card, { kind = "locked", text = text, bag = renderBag })
	renderBag.add(b.Root.Activated:Connect(function()
		pointTo(kind)
	end))
	return b
end

-- The trailing "More at the X stall →" card.
local function moreCard(row: Instance, props)
	local card = Plate.ItemCard(row, {
		name = props.name,
		sub = props.sub,
		image = props.image,
		background = P.Tier.Dark,
		size = props.size,
		index = props.index,
		order = props.order,
		bag = renderBag,
		pop = props.pop,
		onClick = function()
			pointTo(props.kind)
		end,
	})
	Common.Action(card, {
		kind = "info",
		text = props.button,
		bag = renderBag,
		onClick = function()
			pointTo(props.kind)
		end,
	})
	return card
end

------------------------------------------------------------------ tabs

local function ownedWeaponCount(s): (number, number)
	local owned, total = 0, 0
	for _, r in Weapons.GetAll() do
		total += 1
		if s and s.ownedWeapons and s.ownedWeapons[r.id] then
			owned += 1
		end
	end
	for _, d in Weapons.GetSpecials() do
		total += 1
		if s and s.ownedWeapons and s.ownedWeapons[d.id] then
			owned += 1
		end
	end
	return owned, total
end

local function renderWeapons(s, row, size, near, pop)
	local owned, total = ownedWeaponCount(s)
	window.setStat("Weapons " .. owned .. "/" .. total)
	local def = Weapons.Get(s.selectedWeapon)
	if tabs then
		tabs.setHint(if near.weapon then "Equipped: " .. (def and def.displayName or "—") else "Equip at the Weapons stall")
	end
	local i, equippedSlot = 0, nil
	local ownedSet = s.ownedWeapons or {}
	local function action(card, id)
		if s.selectedWeapon == id then
			equippedSlot = card.Root
			Common.Action(card, { kind = "well", text = "Equipped", bag = renderBag })
		elseif near.weapon then
			Common.Action(card, { kind = "info", text = "Equip", bag = renderBag, onClick = function()
				ctx.select("Weapon", id)
			end })
		else
			lockedGo(card, "At Weapons stall", "Weapon")
		end
	end
	for _, fam in FAMILIES do
		local rows = {}
		for _, r in Weapons.GetAll() do
			if r.family == fam.id and ownedSet[r.id] then
				table.insert(rows, r)
			end
		end
		table.sort(rows, function(a, b)
			return (Tiers.TierFromWeaponId(a.id) or 0) < (Tiers.TierFromWeaponId(b.id) or 0)
		end)
		if #rows > 0 then
			i += 1
			divider(row, fam.label, i)
			for _, r in rows do
				i += 1
				local tier = Tiers.TierFromWeaponId(r.id) or 1
				local style = Common.tierStyle(tier)
				local card = Plate.ItemCard(row, {
					name = r.displayName,
					sub = "T" .. tier .. " · " .. FAMILY_NAME[fam.id],
					image = Shots.get(r.id),
					background = style.background,
					rainbow = style.rainbow,
					radial = style.radial,
					rays = style.rays,
					size = size,
					index = math.min(i, 12),
					order = i,
					bag = renderBag,
					pop = pop,
				})
				Plate.Pips(card.Footer, "Power", tier, 8, { size = UDim2.new(0.9, 0, 0, px(22)), order = 1 })
				action(card, r.id)
			end
		end
	end
	local specials = {}
	for _, d in Weapons.GetSpecials() do
		if ownedSet[d.id] then
			table.insert(specials, d)
		end
	end
	if #specials > 0 then
		i += 1
		divider(row, "Specials", i)
		for _, d in specials do
			i += 1
			local unlock = d.special and d.special.unlock or {}
			local bg = if unlock.kind == "Pass" then P.Tier.Robux
				elseif unlock.kind == "Gems" then P.Tier.Gem
				elseif unlock.medal == "Gold" then P.Tier.WonGold
				elseif unlock.medal == "Silver" then P.Tier.WonSilver
				else P.Tier.WonBronze
			local power = Tiers.Specials and Tiers.Specials[d.id] and Tiers.Specials[d.id].powerTier or 1
			local card = Plate.ItemCard(row, {
				name = d.displayName,
				sub = "Special · " .. (FAMILY_NAME[d.family] or d.family or ""),
				image = Shots.get(d.id),
				background = bg,
				rays = true,
				size = size,
				index = math.min(i, 12),
				order = i,
				bag = renderBag,
				pop = pop,
			})
			Plate.Pips(card.Footer, "Power", power, 8, { size = UDim2.new(0.9, 0, 0, px(22)), order = 1 })
			action(card, d.id)
		end
	end
	i += 1
	moreCard(row, {
		name = "More weapons",
		sub = "Buy at the Weapons stall",
		image = Shots.get("WPN_B02"),
		button = "Weapons stall →",
		kind = "Weapon",
		size = size,
		index = math.min(i, 12),
		order = i,
		pop = pop,
	})
	return equippedSlot
end

local function renderCarts(s, row, size, near, pop)
	local owned, total = 0, #Phase13.CartRows
	local ownedSet = s.ownedCarts or {}
	for _, r in Phase13.CartRows do
		if ownedSet[r.id] then
			owned += 1
		end
	end
	window.setStat("Carts " .. owned .. "/" .. total)
	local cargoLevel = tonumber(s.cargoLevel) or 0
	if tabs then
		tabs.setHint(if near.cart then "Cargo level " .. cargoLevel else "Drive one from the Carts stall or your dock")
	end
	local i, drivingSlot = 0, nil
	for _, r in Phase13.CartRows do
		if not ownedSet[r.id] then
			continue
		end
		i += 1
		local style = Common.tierStyle(CART_TIER[r.id])
		local card = Plate.ItemCard(row, {
			name = r.displayName,
			sub = tostring(r.classId or ""),
			image = Shots.get(r.assetName),
			background = style.background,
			rainbow = style.rainbow,
			radial = style.radial,
			rays = style.rays,
			size = size,
			index = math.min(i, 12),
			order = i,
			bag = renderBag,
			pop = pop,
		})
		local badge = Instance.new("Frame")
		badge.Name = "CargoBadge"
		badge.BackgroundColor3 = P.Color.Well
		badge.BorderSizePixel = 0
		badge.Size = UDim2.new(0.9, 0, 0, px(22))
		badge.LayoutOrder = 1
		badge.ZIndex = 9
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, P.Radius.Pill)
		bc.Parent = badge
		local bs = Instance.new("UIStroke")
		bs.Thickness = px(2)
		bs.Color = P.Color.Ink
		bs.Parent = badge
		badge.Parent = card.Footer
		Plate.Label(badge, "Cargo Lv " .. cargoLevel, { size = 15, z = 10 })
		if s.selectedCart == r.id then
			drivingSlot = card.Root
			Common.Action(card, { kind = "well", text = "Driving", bag = renderBag })
		elseif near.cart then
			Common.Action(card, { kind = "info", text = "Drive", bag = renderBag, onClick = function()
				ctx.select("Cart", r.id)
			end })
		else
			lockedGo(card, "At Carts stall", "Cart")
		end
	end
	i += 1
	moreCard(row, {
		name = "More carts",
		sub = "Buy at the Carts stall",
		image = Shots.get("NeonCruiser"),
		button = "Carts stall →",
		kind = "Cart",
		size = size,
		index = math.min(i, 12),
		order = i,
		pop = pop,
	})
	return drivingSlot
end

local function renderBases(s, row, size, near, pop)
	local owned, total, anyMissing = 0, #Phase13.DesignRows, false
	local ownedSet = s.ownedDesigns or {}
	for _, r in Phase13.DesignRows do
		if ownedSet[r.id] then
			owned += 1
		else
			anyMissing = true
		end
	end
	window.setStat("Designs " .. owned .. "/" .. total)
	if tabs then
		-- expansions: read-only (they come from Rebirth at the base entrance)
		tabs.setHint("Base slots: " .. tostring(s.capacity or "—"))
	end
	local i, selectedSlot = 0, nil
	for _, r in Phase13.DesignRows do
		if not ownedSet[r.id] then
			continue
		end
		i += 1
		local card = Plate.ItemCard(row, {
			name = r.displayName,
			sub = "Base design",
			image = Shots.get(r.id),
			background = Common.tierStyle(i).background,
			rays = i >= 3,
			size = size,
			index = math.min(i, 12),
			order = i,
			bag = renderBag,
			pop = pop,
		})
		if s.selectedDesign == r.id then
			selectedSlot = card.Root
			Common.Action(card, { kind = "well", text = "Selected", bag = renderBag })
		elseif near.base then
			Common.Action(card, { kind = "info", text = "Select", bag = renderBag, onClick = function()
				ctx.select("Design", r.id)
			end })
		else
			lockedGo(card, "At your base", "Base")
		end
	end
	if anyMissing then
		i += 1
		moreCard(row, {
			name = "New designs",
			sub = "From Rebirth at your base",
			image = if Theme.Icons.Rebirth ~= "" then Theme.Icons.Rebirth else nil,
			button = "Your base →",
			kind = "Base",
			size = size,
			index = math.min(i, 12),
			order = i,
			pop = pop,
		})
	end
	return selectedSlot
end

local render: (boolean) -> ()
local equipPending = false
local function equipTrail(trailId: string)
	if equipPending then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("LegsRequest")
	if not remote or not remote:IsA("RemoteFunction") then
		toast("Trails are not available right now")
		return
	end
	equipPending = true
	task.spawn(function()
		local ok, result = pcall(function()
			return (remote :: RemoteFunction):InvokeServer({ action = "EquipTrail", trailId = trailId })
		end)
		equipPending = false
		if not ok or type(result) ~= "table" or result.ok ~= true then
			toast("Could not equip that trail")
		end
		render(false)
	end)
end

local function renderTrails(row, size, pop)
	local localPlayer = game:GetService("Players").LocalPlayer
	local owned = {}
	for id in string.gmatch(tostring(localPlayer:GetAttribute("LegsOwnedTrails") or ""), "[^,]+") do
		owned[id] = true
	end
	local equipped = tostring(localPlayer:GetAttribute("LegsEquippedTrail") or "")
	local level = tonumber(localPlayer:GetAttribute("LegsLevel")) or 0
	local count = 0
	for _ in owned do
		count += 1
	end
	window.setStat("Trails " .. count .. "/" .. #Legs.Trails)
	if tabs then
		tabs.setHint("Legs LV " .. level .. " · run the treadmill at Training")
	end
	local selectedSlot = nil
	for i, trail in Legs.Trails do
		local card = Plate.ItemCard(row, {
			name = trail.name,
			sub = if trail.unlockLevel then "Free at Legs " .. trail.unlockLevel else "Gems trail",
			image = if trail.priceGems then Theme.Icons.Gem else Theme.Icons.Bolt,
			background = Common.tierStyle(i).background,
			rays = i >= 4,
			size = size,
			index = math.min(i, 12),
			order = i,
			bag = renderBag,
			pop = pop,
		})
		if equipped == trail.id then
			selectedSlot = card.Root
			Common.Action(card, { kind = "info", text = "Unequip", bag = renderBag, onClick = function()
				equipTrail("")
			end })
		elseif owned[trail.id] then
			Common.Action(card, { kind = "go", text = "Equip", bag = renderBag, onClick = function()
				equipTrail(trail.id)
			end })
		elseif trail.unlockLevel then
			Common.Action(card, { kind = "locked", text = "Legs " .. trail.unlockLevel, bag = renderBag })
		else
			Common.Action(card, { kind = "locked", text = tostring(trail.priceGems) .. " Gems", bag = renderBag })
		end
	end
	return selectedSlot
end

render = function(pop: boolean)
	if not window or not isOpen then
		return
	end
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	local old = window.Content:FindFirstChild("Cards")
	if old then
		old:Destroy()
	end
	local s = snapshot()
	local near = nearState()
	lastNear = nearKey(near)
	if not s then
		window.setStat(nil)
		local l = Plate.Label(window.Content, "Loading…", { size = 20, frameSize = UDim2.new(1, 0, 0, px(40)), position = UDim2.fromOffset(0, px(60)) })
		l.Name = "Cards"
		return
	end
	local row = Common.CardRow(window.Content, {
		position = UDim2.fromOffset(0, px(44)),
		size = UDim2.new(1, 0, 1, -px(44)),
	})
	row.Name = "Cards"
	renderBag.add(row)
	local size = cardSize()
	local focus
	if tab == "Trails" and legsOn then
		focus = renderTrails(row, size, pop)
	elseif tab == "Carts" then
		focus = renderCarts(s, row, size, near, pop)
	elseif tab == "Bases" then
		focus = renderBases(s, row, size, near, pop)
	else
		focus = renderWeapons(s, row, size, near, pop)
	end
	Common.scrollTo(row, focus)
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

local function startListeners()
	openBag = Plate.Bag()
	local shop = deps and deps.shop
	if shop and typeof(shop.Changed) == "Instance" and shop.Changed:IsA("BindableEvent") then
		openBag.add(shop.Changed.Event:Connect(function()
			render(false)
		end))
	end
	local alive = true
	openBag.add(function()
		alive = false
	end)
	if legsOn then
		-- Trails tab: ownership/equip come from server-published player attributes
		local localPlayer = game:GetService("Players").LocalPlayer
		for _, name in { "LegsOwnedTrails", "LegsEquippedTrail", "LegsLevel" } do
			openBag.add(localPlayer:GetAttributeChangedSignal(name):Connect(function()
				if tab == "Trails" then
					render(false)
				end
			end))
		end
	end
	-- fresh snapshot (yields) then render
	task.spawn(function()
		if ctx and ctx.refresh then
			ctx.refresh()
		end
		if alive and isOpen then
			render(false)
		end
	end)
	-- distance-gated buttons: re-check twice a second, rebuild only when a gate flips
	task.spawn(function()
		while alive and isOpen do
			task.wait(0.5)
			if alive and isOpen and nearKey(nearState()) ~= lastNear then
				render(false)
			end
		end
	end)
end

local function openSettings()
	local shop = deps and deps.shop
	Screen.close(false)
	if shop and type(shop.OpenAppearance) == "function" then
		shop.OpenAppearance()
		toast("Settings save at your base")
	end
end

------------------------------------------------------------------ public

function Screen.open(d)
	deps = d or deps
	if isOpen then
		return
	end
	ctx = deps and deps.shop and deps.shop.Context and deps.shop.Context() or nil
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Inventory",
			title = "Inventory",
			icon = Theme.Icons.Shop,
			onClose = function()
				Screen.close(false)
			end,
		})
		-- ⚙ left of ✕ (lives with the window)
		local gear = Plate.Button(window.Header, {
			variant = "tabOff",
			icon = Theme.Icons.Settings,
			size = UDim2.fromOffset(px(40), px(36)),
			position = UDim2.new(1, -px(56), 0.5, -px(2)),
			anchor = Vector2.new(1, 0.5),
			name = "Settings",
			onClick = openSettings,
		})
		gear.Root.ZIndex = 14
	end
	MenusV2.setOpen(WINDOW_ID, function(instant)
		Screen.close(instant)
	end, nil)
	isOpen = true
	places.at = -math.huge
	window.open()
	window.clearContent()
	local list = {}
	for _, t in TABS do
		table.insert(list, { id = t.id, text = t.text })
	end
	tabs = Plate.Tabs(window.Content, { tabs = list, active = tab, onSelect = selectTab, bag = window.bag, tabWidth = 104 })
	startListeners()
	task.defer(render, true)
end

function Screen.close(instant: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
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
	MenusV2.cleared(WINDOW_ID)
end

function Screen.toggle(d)
	if isOpen then
		Screen.close(false)
	else
		Screen.open(d)
	end
end

function Screen.isOpen(): boolean
	return isOpen
end

return Screen
