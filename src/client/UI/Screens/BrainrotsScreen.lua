--!nocheck
-- HUD "Brainrots" window (B key / HUD button). View + navigation only: every action goes through a
-- controller (RetentionController.Request with the legacy payloads, ChariotTeamController.OpenFromMenu,
-- Phase13ShopController.OpenAppearance); nothing here touches a remote. Tabs:
--   Mine   - brainrots the player owns right now, read from the same replicated world attributes the
--            interaction controller uses: own base platforms (StorageBrainrotId), own cart cargo slots
--            (CargoBrainrotId) and the carried item (CarriedItemId). Mutations come from the display
--            models' MutationId / BrainrotMutationId attributes.
--   Index  - every catalogue species; discovered state from the retention snapshot (collection.entries).
--            Rewards column: Equip / Unequip ({action="EquipMilestone", slot, value}). Tapping a species
--            opens the side panel: Feature / Unfeature ({action="FeatureDiscovery", speciesId}), the
--            banked variants, personal records (Phase12 progress, read-only) and a Settings chip.
--   Quests - the three daily quests, UTC reset countdown, daily supplies claim ({action="ClaimSupply"})
--            and the pinned progression goal ({action="PinGoal", goalId}).
-- Sorting (Mine): Income / Rarity. "Newest" is omitted: no acquisition time is replicated to the client.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local WorldPointer = require(script.Parent.WorldPointer)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local MutationCatalog = require(ReplicatedStorage.Shared.Config.MutationCatalog)
local DisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local RetentionView = require(ReplicatedStorage.Shared.Utility.RetentionPresentation)
local CashFormat = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local VisualRules = require(ReplicatedStorage.Shared.Utility.FirstSessionVisualRules)

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local player = Players.LocalPlayer
local WINDOW_ID = "Brainrots"

local Screen = {}

local deps = nil
local window = nil
local isOpen = false
local tab = "Mine"
local tabs = nil
local renderBag = nil -- cards/panel of the current render
local openBag = nil -- listeners/polls while the window is open
local sortMode = "Income"
local selectedItemId: string? = nil
local selectedSpeciesId: string? = nil -- Index side panel
local goalChoiceId: string? = nil -- Quests: the goal candidate being browsed (view state only)
local savedScroll: { [string]: Vector2 } = {} -- scroll positions kept across refreshes of one tab
local renderQueued = false
local dropScroll: string? = nil -- scroller to reset on the next rebuild (a different card was picked)
local progress = nil -- last Phase12 progress table (personal records), read-only
local progressState = "idle" -- idle | loading | ready | unavailable
local seenFound: { [string]: boolean }? = nil -- species seen discovered this session (flash once)
local lastSignature = ""
local requestedRetention = false

local TABS = {
	{ id = "Mine", text = "Mine" },
	{ id = "Index", text = "Index" },
	{ id = "Quests", text = "Quests" },
}
local TAB_IDS = { Mine = true, Index = true, Quests = true }
local EQUIP_SLOTS = { "Title", "Nameplate", "Plaque", "Badge" }

local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Celestial", "Secret" }
local RARITY_RANK = {}
for i, r in RARITY_ORDER do
	RARITY_RANK[r] = i
end

local WHERE_TEXT = { Base = "In your base", Cart = "In your cart", Carried = "You're carrying it" }

------------------------------------------------------------------ helpers

local function rate(n: number?): string
	local v = n or 0
	local s
	if v < 1000 and v ~= math.floor(v) then
		s = string.format("%.1f", v):gsub("%.0$", "")
	else
		s = Theme.abbreviate(v)
	end
	return "+$" .. s .. "/s"
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

local function speciesList()
	local list = {}
	for _, def in BrainrotCatalog.GetAll() do
		if type(def.id) == "string" and string.match(def.id, "^BRT_%d%d%d$") then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local function mutationOf(model: Instance?): string
	if not model then
		return "None"
	end
	local raw = model:GetAttribute("MutationId") or model:GetAttribute(DisplayConfig.Attributes.MutationId)
	local ok, id = pcall(Phase12Rules.NormalizeMutation, raw)
	return if ok and id then id else "None"
end

-- First Model under `container` whose ItemId attribute matches.
local function visualFor(container: Instance?, itemId: string): Model?
	if not container then
		return nil
	end
	for _, d in container:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("ItemId") == itemId then
			return d
		end
	end
	return nil
end

local function makeEntry(itemId: string, speciesId: any, model: Model?, where: string, order: number)
	local def = BrainrotCatalog.Get(speciesId or (model and model:GetAttribute("BrainrotId")))
	if not def then
		return nil
	end
	local mutationId = mutationOf(model)
	return {
		itemId = itemId,
		def = def,
		mutationId = mutationId,
		income = VisualRules.EffectiveIncome(def.cashPerSecond, mutationId) or def.cashPerSecond or 0,
		where = where,
		order = order,
	}
end

-- Everything the local player owns now (base platforms, own cart cargo, carried).
local function collectOwned()
	local out, seen, order = {}, {}, 0
	local function push(e)
		if e and not seen[e.itemId] then
			seen[e.itemId] = true
			order += 1
			e.order = order
			table.insert(out, e)
		end
	end
	-- carried
	local carried = player:GetAttribute("CarriedItemId")
	if type(carried) == "string" then
		local model = visualFor(player.Character, carried)
		push(makeEntry(carried, player:GetAttribute("CarriedBrainrotId"), model, "Carried", 0))
	end
	-- own cart cargo
	for _, slot in CollectionService:GetTagged("BrainrotCargoSlot") do
		local folder = slot.Parent
		local cart = folder and folder.Parent
		local itemId = slot:GetAttribute("CargoItemId")
		if
			cart
			and cart:GetAttribute("OwnerUserId") == player.UserId
			and slot:GetAttribute("CargoOccupied") == true
			and type(itemId) == "string"
		then
			local model = visualFor(cart:FindFirstChild("CargoVisuals"), itemId)
			push(makeEntry(itemId, slot:GetAttribute("CargoBrainrotId"), model, "Cart", 0))
		end
	end
	-- own base platforms
	local assigned = player:GetAttribute("AssignedBaseId")
	for _, platform in CollectionService:GetTagged("BrainrotStoragePlatform") do
		local base = platform.Parent
		local itemId = platform:GetAttribute("StorageItemId")
		if
			base
			and base:GetAttribute("OwnerUserId") == player.UserId
			and (assigned == nil or base:GetAttribute("BaseId") == assigned)
			and platform:GetAttribute("StorageOccupied") == true
			and type(itemId) == "string"
		then
			local model = visualFor(base:FindFirstChild("StoredBrainrots"), itemId)
			push(makeEntry(itemId, platform:GetAttribute("StorageBrainrotId"), model, "Base", 0))
		end
	end
	return out
end

local function signature(list): string
	local parts = {}
	for _, e in list do
		table.insert(parts, e.itemId .. ":" .. e.def.id .. ":" .. e.mutationId .. ":" .. e.where)
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

local function sortOwned(list)
	table.sort(list, function(a, b)
		local ra, rb = RARITY_RANK[a.def.tier] or 0, RARITY_RANK[b.def.tier] or 0
		if sortMode == "Rarity" then
			if ra ~= rb then
				return ra > rb
			end
			if a.income ~= b.income then
				return a.income > b.income
			end
		else
			if a.income ~= b.income then
				return a.income > b.income
			end
			if ra ~= rb then
				return ra > rb
			end
		end
		return a.order < b.order
	end)
end

-- Small pill (badge / chip) inside a card or panel.
local function pill(parent: Instance, text: string, bg: Color3, textColor: Color3, props)
	local f = Instance.new("Frame")
	f.Name = "Pill_" .. text
	f.BackgroundColor3 = bg
	f.BorderSizePixel = 0
	f.AnchorPoint = props.anchor or Vector2.zero
	f.Position = props.position or UDim2.new()
	f.Size = UDim2.fromOffset(px(20), px(props.height or 18))
	f.AutomaticSize = Enum.AutomaticSize.X
	f.ZIndex = props.z or 11
	f.LayoutOrder = props.order or 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, P.Radius.Pill)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Thickness = px(2)
	s.Color = P.Color.Ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(5))
	pad.PaddingRight = UDim.new(0, px(5))
	pad.Parent = f
	local l = Plate.Label(f, text, { size = 14, color = textColor, z = (props.z or 11) + 1, strokePx = if textColor == P.Color.Ink then 0 else 2 })
	l.TextScaled = false
	l.TextSize = px(14)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromScale(0, 1)
	f.Parent = parent
	return f
end

-- Safe call into RetentionController (nil when retention is off or the call fails).
local function rcall(name: string, ...)
	local r = deps and deps.retention
	local fn = r and r[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, ...)
	return if ok then value else nil
end

local function retentionSnapshot()
	return rcall("GetSnapshot")
end

-- What the legacy panel rendered from: the live snapshot while available, else the last confirmed one.
local function retentionView()
	return rcall("GetView") or retentionSnapshot()
end

-- The legacy gate on every mutating button: panel reachable (eligible) and the request owner ready.
-- A background snapshot read does not grey the buttons out (a tap during it gets "One moment…").
local function canAct(): boolean
	return rcall("IsAvailable") == true and rcall("CanMutate", true) == true
end

local function blockReason(): string
	local s = retentionSnapshot()
	if rcall("IsRequestPending") == true or (s and s.status == "Saving") then
		return "Saving…"
	end
	return "Unavailable"
end

-- species id -> collection entry (nil while retention is unavailable)
local function collectionIndex()
	local s = retentionView()
	local collection = s and s.collection
	if type(collection) ~= "table" or type(collection.entries) ~= "table" then
		return nil, nil
	end
	local byId = {}
	for _, e in collection.entries do
		if type(e) == "table" and type(e.id) == "string" then
			byId[e.id] = e
		end
	end
	return byId, collection
end

local function foundCount(byId): number
	local n = 0
	for _, e in byId or {} do
		if e.discovered == true then
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------ actions

local function toast(text: string)
	Plate.Toast(MenusV2.Gui(), text, { color = P.Color.White })
end

local function goSell()
	Screen.close(false)
	if not WorldPointer.show(WorldPointer.sellStall(), 6, "Sell") then
		toast("The Sell stall is at camp")
	end
end

local function controller(name: string)
	local folder = script.Parent.Parent.Parent:FindFirstChild("Controllers")
	local module = folder and folder:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function openTeam()
	Screen.close(false)
	local team = controller("ChariotTeamController")
	if team then
		task.spawn(team.OpenFromMenu)
	end
end

-- Legacy "Appearance / owned cosmetics", "View / Equip in Appearance" and "Collection / effects
-- settings": all land on the Settings window through the shop controller's own open path.
local function openSettings(cosmeticId: string?)
	Screen.close(false)
	local shop = deps and deps.shop
	if shop and type(shop.OpenAppearance) == "function" then
		task.spawn(shop.OpenAppearance, cosmeticId)
	end
end

-- RetentionController.Request owns pending / rate limiting; the payloads are the legacy ones.
local function send(payload)
	if rcall("Request", payload) ~= true then
		toast("One moment…")
	end
end

local function requestSnapshotOnce()
	if not requestedRetention then
		requestedRetention = true
		rcall("Request", { action = "Snapshot" })
	end
end

------------------------------------------------------------------ render helpers

local render

------------------------------------------------------------------ favourite lock
-- Starred brainrots can't be sold. The truth is the shop snapshot's `favourites`; `favAnswer` holds the
-- server's latest answer per brainrot until the next snapshot arrives.
local favAnswer: { [string]: boolean } = {}
local function shopContext()
	local shop = deps and deps.shop
	return if shop and type(shop.Context) == "function" then shop.Context() else nil
end
local function isFavourite(itemId: string): boolean
	if favAnswer[itemId] ~= nil then
		return favAnswer[itemId]
	end
	local c = shopContext()
	local s = c and c.snapshot()
	return type(s) == "table" and type(s.favourites) == "table" and s.favourites[itemId] == true
end
local function setFavourite(itemId: string, value: boolean)
	local c = shopContext()
	if not c or type(c.setFavourite) ~= "function" then
		return
	end
	task.spawn(function()
		local result = c.setFavourite(itemId, value)
		if type(result) == "table" and result.ok then
			favAnswer[itemId] = result.favourite == true
			toast(if value then "Favourite! It can't be sold." else "Not a favourite any more")
		elseif type(result) == "table" and result.code == "NOT_OWNED" then
			toast("Bank it first, then you can star it.")
		else
			toast("Couldn't change that. Try again.")
		end
		if isOpen and tab == "Mine" then
			render(false)
		end
	end)
end
-- Fetches a fresh snapshot (the HUD can open this window before any shop was opened).
local function refreshFavourites()
	local c = shopContext()
	if not c then
		return
	end
	task.spawn(function()
		c.refresh()
		table.clear(favAnswer)
		if isOpen and tab == "Mine" then
			render(false)
		end
	end)
end


-- One deferred rebuild per burst of controller events (a request fires Changed two or three times).
local function scheduleRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		if isOpen then
			render(false)
		end
	end)
end

local function newArea(): Frame
	local area = Instance.new("Frame")
	area.Name = "Cards"
	area.BackgroundTransparency = 1
	area.Size = UDim2.fromScale(1, 1)
	area.ZIndex = 5
	area.Parent = window.Content
	renderBag.add(area)
	return area
end

-- A refresh rebuilds the tab; put each scroller back where the player left it.
local function keepScroll(sf: ScrollingFrame, key: string)
	sf:SetAttribute("ScrollKey", key)
	local want = savedScroll[key]
	if not want or (want.X <= 0 and want.Y <= 0) then
		return
	end
	local function apply()
		if sf.Parent then
			sf.CanvasPosition = want
		end
	end
	task.defer(apply)
	local conn = sf:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(apply)
	renderBag.add(conn)
	task.delay(0.4, function()
		conn:Disconnect()
	end)
end

-- Left-aligned wrapped text that grows downwards (goal requirements, status lines).
local function textBlock(parent: Instance, text: string, opts)
	local o = opts or {}
	local l = Plate.Label(parent, text, {
		size = o.size or 14,
		color = o.color,
		font = o.font,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
		order = o.order,
		z = o.z or 7,
		name = o.name,
		frameSize = UDim2.fromScale(1, 0),
	})
	l.TextScaled = false
	l.TextSize = px(math.max(14, o.size or 14))
	l.AutomaticSize = Enum.AutomaticSize.Y
	return l
end

-- Vertical scrolling list column.
local function scrollColumn(parent: Instance, name: string, position: UDim2, size: UDim2, key: string): ScrollingFrame
	local col = Instance.new("ScrollingFrame")
	col.Name = name
	col.BackgroundTransparency = 1
	col.BorderSizePixel = 0
	col.Position = position
	col.Size = size
	col.ScrollingDirection = Enum.ScrollingDirection.Y
	col.AutomaticCanvasSize = Enum.AutomaticSize.Y
	col.CanvasSize = UDim2.new()
	col.ScrollBarThickness = px(4)
	col.ScrollBarImageColor3 = Color3.fromHex("#9A9CAB")
	col.ZIndex = 5
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(5))
	list.Parent = col
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(2))
	pad.PaddingRight = UDim.new(0, px(7))
	pad.PaddingTop = UDim.new(0, px(2))
	pad.PaddingBottom = UDim.new(0, px(6))
	pad.Parent = col
	col.Parent = parent
	keepScroll(col, key)
	return col
end

-- Dark well that grows with its stacked children.
local function wellFrame(parent: Instance, name: string, order: number, rim: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = P.Color.Well
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order
	f.ZIndex = 6
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, P.Radius.Card)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Thickness = px(2)
	s.Color = rim or P.Color.Ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(7))
	pad.PaddingRight = UDim.new(0, px(7))
	pad.PaddingTop = UDim.new(0, px(5))
	pad.PaddingBottom = UDim.new(0, px(7))
	pad.Parent = f
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(4))
	list.Parent = f
	f.Parent = parent
	return f
end

-- A button that is either live or a grey lock with the reason (never a dead-looking live button).
local function actionButton(parent: Instance, props)
	local live = props.enabled == true
	return Plate.Button(parent, {
		variant = if live then (props.variant or "info") else "locked",
		text = props.text,
		lockedReason = if live then nil else (props.reason or blockReason()),
		icon = if live then props.icon else nil,
		primary = live and props.primary == true,
		size = props.size,
		position = props.position,
		anchor = props.anchor,
		order = props.order,
		textSize = props.textSize or 18,
		name = props.name,
		bag = renderBag,
		onClick = if live then props.onClick else nil,
	})
end

local function sortColumn(parent: Instance)
	local col = Instance.new("Frame")
	col.Name = "SortColumn"
	col.BackgroundTransparency = 1
	col.Position = UDim2.fromOffset(0, px(44))
	col.Size = UDim2.new(0, px(118), 1, -px(44))
	col.ZIndex = 5
	col.Parent = parent
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(6))
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = col
	Plate.Label(col, "Sort by:", { size = 18, frameSize = UDim2.new(1, 0, 0, px(24)), order = 1 })
	for i, mode in { "Income", "Rarity" } do
		Plate.Button(col, {
			variant = if sortMode == mode then "info" else "tabOff",
			text = mode,
			size = UDim2.new(1, -px(6), 0, px(40)),
			order = 1 + i,
			textSize = 18,
			bag = renderBag,
			onClick = function()
				if sortMode ~= mode then
					sortMode = mode
					render(false)
				end
			end,
		})
	end
	-- Always here (also with no brainrots yet): the legacy panel's "Manage team" was never gated on owning one.
	Plate.Button(col, {
		variant = "info",
		text = "Team",
		icon = Theme.Icons.Cart,
		size = UDim2.new(1, -px(6), 0, px(40)),
		order = 9,
		textSize = 18,
		name = "Btn_Team",
		bag = renderBag,
		onClick = openTeam,
	})
	Plate.Label(col, "Tap one to see what you can do", {
		size = 15,
		min = 14,
		wrap = true,
		color = P.Color.Hint,
		frameSize = UDim2.new(1, 0, 0, px(52)),
		order = 10,
	})
	return col
end

-- Side panel shell shared by Mine and Index: scrolling well, display shot and a close button.
local function panelShell(parent: Instance, width: number, ring: Color3, shotId: string, key: string, silhouette: boolean, onClose: () -> ()): ScrollingFrame
	local panel = Instance.new("ScrollingFrame")
	panel.Name = "SidePanel"
	panel.BackgroundColor3 = P.Color.Well
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, 0, 0, px(44))
	panel.Size = UDim2.new(0, width, 1, -px(44))
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
	panel.ScrollBarThickness = px(5)
	panel.ZIndex = 6
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, P.Radius.Card)
	c.Parent = panel
	local s = Instance.new("UIStroke")
	s.Thickness = px(P.Stroke.Outline)
	s.Color = ring
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px(8))
	pad.PaddingRight = UDim.new(0, px(10))
	pad.PaddingTop = UDim.new(0, px(6))
	pad.PaddingBottom = UDim.new(0, px(8))
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(5))
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = panel
	panel.Parent = parent
	keepScroll(panel, key)

	-- top row: shot + close
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, px(70))
	top.LayoutOrder = 1
	top.ZIndex = 7
	top.Parent = panel
	local shot = Shots.get(shotId)
	if shot ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "Shot"
		img.BackgroundTransparency = 1
		img.Image = shot
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.new(1, -px(52), 1, 0)
		img.ZIndex = 8
		if silhouette then
			img.ImageColor3 = Color3.new(0, 0, 0)
			img.ImageTransparency = 0.25
		end
		img.Parent = top
	end
	Plate.Button(top, {
		variant = "stop",
		icon = Theme.Icons.Close,
		size = UDim2.fromOffset(px(40), px(36)),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		name = "PanelClose",
		bag = renderBag,
		onClick = onClose,
	})
	return panel
end

local function chipRow(panel: Instance, order: number): Frame
	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, 0, 0, px(20))
	chips.LayoutOrder = order
	chips.ZIndex = 7
	chips.Parent = panel
	local cl = Instance.new("UIListLayout")
	cl.FillDirection = Enum.FillDirection.Horizontal
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cl.Padding = UDim.new(0, px(4))
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Parent = chips
	return chips
end

------------------------------------------------------------------ Mine

local function sidePanel(parent: Instance, e, width: number)
	local panel = panelShell(parent, width, rarityColor(e.def.tier), e.def.id, "MinePanel", false, function()
		selectedItemId = nil
		render(false)
	end)
	Plate.Label(panel, e.def.displayName, {
		size = 20,
		font = P.Font.Title,
		wrap = true,
		frameSize = UDim2.new(1, 0, 0, px(26)),
		order = 2,
	})
	local chips = chipRow(panel, 3)
	pill(chips, e.def.tier, rarityColor(e.def.tier), P.Color.Ink, { order = 1, z = 8 })
	if e.mutationId ~= "None" then
		local m = MutationCatalog.ById[e.mutationId]
		pill(chips, m and m.displayName or e.mutationId, Theme.Mutation[e.mutationId] or P.Color.White, P.Color.Ink, { order = 2, z = 8 })
	end
	Plate.Label(panel, rate(e.income), {
		size = 20,
		font = P.Font.Title,
		color = P.Color.Cash,
		frameSize = UDim2.new(1, 0, 0, px(24)),
		order = 4,
	})
	Plate.Label(panel, WHERE_TEXT[e.where] or "", {
		size = 15,
		color = P.Color.Hint,
		frameSize = UDim2.new(1, 0, 0, px(20)),
		order = 6,
	})
	local favourite = isFavourite(e.itemId)
	Plate.Button(panel, {
		variant = if favourite then "tabOff" else "info",
		text = if favourite then "Unstar" else "Favourite",
		icon = if favourite then Theme.Icons.StarOff else Theme.Icons.Star,
		size = UDim2.new(1, 0, 0, px(40)),
		order = 5, -- right under the income, so it shows without scrolling
		textSize = 18,
		name = "Btn_Favourite",
		bag = renderBag,
		onClick = function()
			setFavourite(e.itemId, not favourite)
		end,
	})
	Plate.Button(panel, {
		variant = "info",
		text = "Team",
		icon = Theme.Icons.Cart,
		size = UDim2.new(1, 0, 0, px(40)),
		order = 7,
		textSize = 18,
		bag = renderBag,
		onClick = openTeam,
	})
	if favourite then
		Plate.Label(panel, "Favourites can't be sold", {
			size = 15,
			min = 14,
			color = Common.StarGold,
			frameSize = UDim2.new(1, 0, 0, px(40)),
			order = 8,
		})
	else
		Plate.Button(panel, {
			variant = "info",
			text = "Sell at the Sell stall →",
			size = UDim2.new(1, 0, 0, px(40)),
			order = 8,
			textSize = 15,
			bag = renderBag,
			onClick = goSell,
		})
	end
	Plate.Label(panel, if e.where == "Carried" then "Carry it to a base slot to place it" else "Pick it up with E to move it", {
		size = 14,
		wrap = true,
		color = P.Color.Hint,
		frameSize = UDim2.new(1, 0, 0, px(36)),
		order = 9,
	})
	return panel
end

local function renderMine(pop: boolean)
	local owned = collectOwned()
	lastSignature = signature(owned)
	sortOwned(owned)
	window.setStat("Owned " .. #owned)
	if tabs then
		local base, cart, carried = 0, 0, 0
		for _, e in owned do
			if e.where == "Base" then
				base += 1
			elseif e.where == "Cart" then
				cart += 1
			else
				carried += 1
			end
		end
		tabs.setHint(string.format("Base %d · Cart %d · Carried %d", base, cart, carried))
	end
	local area = newArea()

	sortColumn(area)
	local selected = nil
	for _, e in owned do
		if e.itemId == selectedItemId then
			selected = e
		end
	end
	if not selected then
		selectedItemId = nil
	end
	local leftW = px(126)
	local panelW = if selected then px(200) else 0
	if selected then
		sidePanel(area, selected, panelW)
	end
	if #owned == 0 then
		Plate.Label(area, "No brainrots yet. Shoot one to sleep and carry it home!", {
			size = 20,
			wrap = true,
			color = P.Color.Hint,
			frameSize = UDim2.new(1, -leftW - px(20), 0, px(80)),
			position = UDim2.fromOffset(leftW + px(10), px(90)),
		})
		return
	end
	local grid = Common.CardGrid(area, {
		position = UDim2.fromOffset(leftW, px(44)),
		size = UDim2.new(1, -leftW - panelW - (if selected then px(6) else 0), 1, -px(44)),
		cell = Vector2.new(102, 132),
		gap = 8,
	})
	keepScroll(grid, "MineGrid")
	for i, e in owned do
		local tier = e.def.tier
		local card = Plate.ItemCard(grid, {
			name = e.def.displayName,
			image = Shots.get(e.def.id),
			background = tint(tier),
			ring = if e.itemId == selectedItemId then P.Color.White else rarityColor(tier),
			rays = (Theme.RarityIntensity[tier] or 1) >= 4,
			compact = true,
			size = UDim2.fromScale(1, 1),
			index = math.min(i, 14),
			order = i,
			bag = renderBag,
			pop = pop,
			onClick = function()
				selectedItemId = if selectedItemId == e.itemId then nil else e.itemId
				dropScroll = "MinePanel"
				render(false)
			end,
		})
		local income = Plate.Label(card.Footer, rate(e.income), { size = 16, color = P.Color.Cash, frameSize = UDim2.fromScale(1, 0.9), order = 1 })
		income.Name = "Income"
		if isFavourite(e.itemId) then
			Common.Star(card.ImageArea, true, { size = 30, anchor = Vector2.new(1, 1), position = UDim2.new(1, -px(1), 1, px(2)), z = 11 })
		end
		pill(card.Inner, e.where, P.Color.Ink, P.Color.White, { position = UDim2.fromOffset(px(3), px(3)), z = 11 })
		if e.mutationId ~= "None" then
			local m = MutationCatalog.ById[e.mutationId]
			pill(card.Inner, m and m.displayName or e.mutationId, Theme.Mutation[e.mutationId] or P.Color.White, P.Color.Ink, {
				anchor = Vector2.new(1, 0),
				position = UDim2.new(1, -px(3), 0, px(3)),
				z = 11,
			})
		end
	end
end

------------------------------------------------------------------ Index

local function flash(card)
	if Juice.reduced() then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "FoundFlash"
	f.BackgroundColor3 = P.Color.White
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 11
	f.Parent = card.Inner
	task.delay(0.35, function()
		if f.Parent then
			Juice.pop(card.Outer or card.Root, 1.12)
			local t = TweenService:Create(f, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
			t.Completed:Once(function()
				f:Destroy()
			end)
			t:Play()
		end
	end)
end

-- Personal records come from Phase12PresentationController.GetCollectionProgress() (the request the
-- retired "Collection & Effects" panel sent). It can yield, so it runs off the render path.
local function loadProgress(refresh: boolean)
	if progressState == "loading" then
		return
	end
	local presentation = controller("Phase12PresentationController")
	if not presentation or type(presentation.GetCollectionProgress) ~= "function" then
		progressState = "unavailable"
		return
	end
	progressState = "loading"
	task.spawn(function()
		local ok, result = pcall(presentation.GetCollectionProgress, refresh)
		if ok and type(result) == "table" then
			progress, progressState = result, "ready"
		else
			progressState = "unavailable"
		end
		if tab == "Index" and selectedSpeciesId then
			scheduleRender()
		end
	end)
end

local function finiteNumber(v): boolean
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end

-- The retired panel's summary: personal best haul, mutation finds and the tracked upgrade shortfall.
local function recordsText(p): string
	local best = if type(p.personalBest) == "table" then p.personalBest else {}
	local finds = 0
	for _, map in if type(p.speciesMutations) == "table" then p.speciesMutations else {} do
		if type(map) == "table" then
			for _, found in map do
				if found then
					finds += 1
				end
			end
		end
	end
	local lines = {
		"Best haul: " .. tostring(best.haulCount or 0) .. " catches",
		"Best income: " .. CashFormat.FormatCompactCash(best.cashPerSecond or 0) .. " Cash/s",
		"Best worth: " .. CashFormat.FormatCompactCash(best.sellValue or 0) .. " Cash",
		"Mutation finds: " .. tostring(finds),
	}
	local upgrade = p.trackedUpgrade
	if type(upgrade) == "table" and finiteNumber(upgrade.shortfall) then
		table.insert(
			lines,
			tostring(upgrade.displayName or upgrade.offerId)
				.. ": "
				.. CashFormat.FormatCompactCash(upgrade.shortfall)
				.. " wallet shortfall"
		)
	end
	return table.concat(lines, "\n")
end

-- Variants actually banked: the retention entry's list, else the Phase12 stamps for the species.
local function variantsText(e, speciesId: string): string
	if e.discovered ~= true then
		return "Not caught yet · no variants recorded"
	end
	local names = {}
	for _, v in if type(e.variants) == "table" then e.variants else {} do
		table.insert(names, tostring(v))
	end
	if #names == 0 and progress and type(progress.speciesMutations) == "table" then
		local stamps = progress.speciesMutations[speciesId]
		if type(stamps) == "table" then
			for _, mutation in { "None", "Shiny", "Golden", "Glitched", "Radioactive", "Astral" } do
				if stamps[mutation] or (mutation == "None" and stamps.Normal) then
					table.insert(names, if mutation == "None" then "Normal" else mutation)
				end
			end
		end
	end
	return if #names > 0 then "Banked variants: " .. table.concat(names, ", ") else "Banked variants: none recorded"
end

local function indexPanel(parent: Instance, def, e, collection, width: number)
	local discovered = e.discovered == true
	local can = canAct()
	local panel = panelShell(parent, width, if discovered then rarityColor(def.tier) else P.Color.Ink, def.id, "IndexPanel", not discovered, function()
		selectedSpeciesId = nil
		render(false)
	end)
	Plate.Label(panel, if discovered then def.displayName else tostring(e.name or "???"), {
		size = 20,
		font = P.Font.Title,
		wrap = true,
		frameSize = UDim2.new(1, 0, 0, px(26)),
		order = 2,
	})
	local featured = collection.featuredSpeciesId == e.id
	if discovered or featured then
		local chips = chipRow(panel, 3)
		if discovered then
			pill(chips, def.tier, rarityColor(def.tier), P.Color.Ink, { order = 1, z = 8 })
		end
		if featured then
			pill(chips, "Featured", P.Color.WellRim, P.Color.Ink, { order = 2, z = 8 })
		end
	end
	textBlock(panel, variantsText(e, def.id), { order = 4, color = P.Color.Hint, name = "Variants" })

	-- Feature / Unfeature: the legacy inspect + "Featured discovery: None" pair.
	if featured then
		actionButton(panel, {
			text = "Unfeature",
			enabled = can,
			size = UDim2.new(1, 0, 0, px(40)),
			order = 5,
			name = "Unfeature",
			onClick = function()
				send({ action = "FeatureDiscovery", speciesId = "None" })
			end,
		})
	else
		actionButton(panel, {
			text = "Feature",
			enabled = can and e.canFeature == true,
			reason = if e.canFeature == true then nil else "Catch It First",
			size = UDim2.new(1, 0, 0, px(40)),
			order = 5,
			name = "Feature",
			onClick = function()
				send({ action = "FeatureDiscovery", speciesId = e.id })
			end,
		})
	end

	-- read-only personal records (not per species; they ride along with every inspected card)
	Plate.Label(panel, "Your Records", {
		size = 16,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 0, px(20)),
		order = 6,
		z = 7,
	})
	if progressState == "idle" then
		loadProgress(true)
	end
	textBlock(panel, if progress
		then recordsText(progress)
		elseif progressState == "loading" then "Loading your records…"
		else "Records unavailable right now", { order = 7, color = P.Color.Hint, name = "Records" })

	Plate.Button(panel, {
		variant = "info",
		text = "Settings",
		icon = Theme.Icons.Settings,
		size = UDim2.new(1, 0, 0, px(40)),
		order = 9,
		textSize = 17,
		name = "Settings",
		bag = renderBag,
		onClick = function()
			openSettings(nil)
		end,
	})
	return panel
end

-- One row of the Rewards column: label + state line, and Equip / Unequip where the snapshot allows it.
local function rewardRow(col: Instance, order: number, props)
	local hasButton = props.button ~= nil
	local row = Instance.new("Frame")
	row.Name = props.name
	row.BackgroundColor3 = P.Color.Well
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, px(if hasButton then 88 else 38))
	row.LayoutOrder = order
	row.ZIndex = 6
	row.Parent = col
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, P.Radius.Button)
	rc.Parent = row
	local rs = Instance.new("UIStroke")
	rs.Thickness = px(2)
	rs.Color = if props.lit then P.Color.WellRim else P.Color.Ink
	rs.Parent = row
	Plate.Label(row, props.label, {
		size = 15,
		frameSize = UDim2.new(1, -px(30), 0, px(21)),
		position = UDim2.fromOffset(px(6), 0),
		align = Enum.TextXAlignment.Left,
		z = 7,
	})
	Plate.Label(row, props.sub, {
		size = 14,
		color = if props.lit then P.Color.WellRim else P.Color.Hint,
		frameSize = UDim2.new(1, -px(30), 0, px(17)),
		position = UDim2.fromOffset(px(6), px(21)),
		align = Enum.TextXAlignment.Left,
		z = 7,
	})
	if props.check and Theme.Icons.Check ~= "" then
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = Theme.Icons.Check
		ic.AnchorPoint = Vector2.new(1, 0)
		ic.Position = UDim2.new(1, -px(4), 0, px(8))
		ic.Size = UDim2.fromOffset(px(22), px(22))
		ic.ZIndex = 7
		ic.Parent = row
	end
	if hasButton then
		actionButton(row, {
			text = props.button.text,
			enabled = props.button.enabled,
			size = UDim2.new(1, -px(10), 0, px(40)),
			position = UDim2.fromOffset(px(5), px(42)),
			textSize = 16,
			name = props.button.text,
			onClick = props.button.onClick,
		})
	end
	return row
end

local function unequip(slot: string)
	return function()
		send({ action = "EquipMilestone", slot = slot, value = "None" })
	end
end

local function renderIndex(pop: boolean)
	local species = speciesList()
	local total = #species
	local byId, collection = collectionIndex()
	local area = newArea()

	if not byId then
		window.setStat(nil)
		if tabs then
			tabs.setHint("")
		end
		Plate.Label(area, "The Index is getting ready. Check back in a moment!", {
			size = 20,
			wrap = true,
			color = P.Color.Hint,
			frameSize = UDim2.new(1, -px(40), 0, px(80)),
			position = UDim2.fromOffset(px(20), px(90)),
		})
		requestSnapshotOnce()
		return
	end
	requestSnapshotOnce() -- the legacy panel refreshed its snapshot each time it opened

	local found = foundCount(byId)
	local can = canAct()
	window.setStat("Found " .. found .. "/" .. total)
	if tabs then
		local nextMilestone = collection.nextMilestone
		tabs.setHint(if type(nextMilestone) == "table" and nextMilestone.required
			then string.format("Next: %s at %d", tostring(nextMilestone.label), nextMilestone.required)
			else "Catch them all!")
	end

	-- first look this session = the baseline; later discoveries flash once
	local firstLook = seenFound == nil
	if firstLook then
		seenFound = {}
	end

	-- left column: progress, what is equipped / featured, and the discovery rewards
	local leftW = px(156)
	local col = scrollColumn(area, "Progress", UDim2.fromOffset(0, px(44)), UDim2.new(0, leftW - px(6), 1, -px(44)), "IndexLeft")
	Plate.StripedProgress(col, {
		frac = if total > 0 then found / total else 0,
		text = "Found " .. found .. "/" .. total,
		size = UDim2.new(1, 0, 0, px(26)),
		order = 1,
		bag = renderBag,
		colors = { Color3.fromHex("#FFB0E4"), Color3.fromHex("#FF7AD0"), Color3.fromHex("#FF3D9E") },
	})
	textBlock(col, "Title: " .. tostring(collection.title or "None") .. "\nNameplate: " .. tostring(collection.nameplate or "None"), {
		order = 2,
		color = P.Color.Hint,
		name = "Equipped",
	})
	local featuredId = collection.featuredSpeciesId
	if type(featuredId) == "string" and featuredId ~= "None" then
		local featuredDef = BrainrotCatalog.Get(featuredId)
		rewardRow(col, 3, {
			name = "Featured",
			label = "Featured",
			sub = if featuredDef then featuredDef.displayName else featuredId,
			lit = true,
			button = { text = "Unfeature", enabled = can, onClick = function()
				send({ action = "FeatureDiscovery", speciesId = "None" })
			end },
		})
	end

	local milestones = if type(collection.milestones) == "table" then collection.milestones else {}
	local covered = {} -- slot -> its equipped value has a row with Unequip
	if #milestones > 0 or collection.riftPatronOwned == true then
		Plate.Label(col, "Rewards", { size = 17, frameSize = UDim2.new(1, 0, 0, px(22)), order = 9, align = Enum.TextXAlignment.Left })
	end
	for i, m in milestones do
		local owned = m.owned == true
		local slot = if type(m.slot) == "string" then m.slot else nil
		local selected = slot ~= nil and collection["selected" .. slot] == m.id
		if selected then
			covered[slot] = true
		end
		local need = if m.anomaly
			then "Bank a mutated one"
			else tostring(collection.count or found) .. "/" .. tostring(m.required) .. " species"
		local button = nil
		if owned and slot then
			button = if selected
				then { text = "Unequip", enabled = can, onClick = unequip(slot) }
				else { text = "Equip", enabled = can, onClick = function()
					send({ action = "EquipMilestone", slot = slot, value = m.id })
				end }
		end
		rewardRow(col, 10 + i, {
			name = "Milestone_" .. tostring(m.id),
			label = tostring(m.label or m.id),
			sub = if selected then "Equipped" elseif owned then "Earned" elseif m.state == "Saving" then "Saving…" else need,
			lit = owned,
			check = owned,
			button = button,
		})
	end
	-- VIP title (legacy "Equip Rift Patron title")
	if collection.riftPatronOwned == true then
		local selected = collection.selectedTitle == "RiftPatron"
		if selected then
			covered.Title = true
		end
		rewardRow(col, 40, {
			name = "RiftPatron",
			label = "Rift Patron",
			sub = if selected then "Equipped" else "VIP title",
			lit = true,
			check = true,
			button = if selected
				then { text = "Unequip", enabled = can, onClick = unequip("Title") }
				else { text = "Equip", enabled = can, onClick = function()
					send({ action = "EquipMilestone", slot = "Title", value = "RiftPatron" })
				end },
		})
	end
	-- anything else equipped in a slot can still be taken off (legacy "<Slot>: None")
	for i, slot in EQUIP_SLOTS do
		local value = collection["selected" .. slot]
		if value ~= nil and value ~= "None" and not covered[slot] then
			rewardRow(col, 50 + i, {
				name = "Slot_" .. slot,
				label = slot,
				sub = tostring(collection[string.lower(slot)] or value),
				lit = true,
				button = { text = "Unequip", enabled = can, onClick = unequip(slot) },
			})
		end
	end

	-- side panel for the tapped species (anything the snapshot does not hide)
	local selectedDef, selectedEntry = nil, nil
	if selectedSpeciesId then
		local e = byId[selectedSpeciesId]
		if e and e.hidden ~= true then
			selectedDef, selectedEntry = BrainrotCatalog.Get(selectedSpeciesId), e
		end
		if not selectedDef then
			selectedSpeciesId, selectedEntry = nil, nil
		end
	end
	local panelW = if selectedEntry then px(200) else 0
	if selectedEntry then
		indexPanel(area, selectedDef, selectedEntry, collection, panelW)
	end

	local grid = Common.CardGrid(area, {
		position = UDim2.fromOffset(leftW, px(44)),
		size = UDim2.new(1, -leftW - panelW - (if selectedEntry then px(6) else 0), 1, -px(44)),
		cell = Vector2.new(102, 132),
		gap = 8,
	})
	keepScroll(grid, "IndexGrid")
	for i, def in species do
		local e = byId[def.id]
		local discovered = e ~= nil and e.discovered == true
		local inspectable = e ~= nil and e.hidden ~= true
		local name = if discovered then def.displayName
			elseif e and not e.hidden and type(e.name) == "string" then e.name
			else "???"
		local card = Plate.ItemCard(grid, {
			name = name,
			image = Shots.get(def.id),
			background = if discovered then tint(def.tier) else P.Tier.Dark,
			ring = if def.id == selectedSpeciesId then P.Color.White
				elseif discovered then rarityColor(def.tier)
				else P.Color.Ink,
			rays = discovered and (Theme.RarityIntensity[def.tier] or 1) >= 4,
			compact = true,
			size = UDim2.fromScale(1, 1),
			index = math.min(i, 14),
			order = i,
			bag = renderBag,
			pop = pop,
			onClick = if inspectable
				then function()
					selectedSpeciesId = if selectedSpeciesId == def.id then nil else def.id
					dropScroll = "IndexPanel"
					render(false)
				end
				else nil,
		})
		if featuredId == def.id then
			pill(card.Inner, "Featured", P.Color.WellRim, P.Color.Ink, { position = UDim2.fromOffset(px(3), px(3)), z = 11 })
		end
		if discovered then
			Plate.Label(card.Footer, def.tier, { size = 15, color = rarityColor(def.tier), frameSize = UDim2.fromScale(1, 0.9), order = 1 })
			if not firstLook and not seenFound[def.id] then
				flash(card)
			end
			seenFound[def.id] = true
		else
			if card.Image then
				card.Image.ImageColor3 = Color3.new(0, 0, 0)
				card.Image.ImageTransparency = 0.25
			end
			if Theme.Icons.Lock ~= "" then
				local lock = Instance.new("ImageLabel")
				lock.Name = "Lock"
				lock.BackgroundTransparency = 1
				lock.Image = Theme.Icons.Lock
				lock.AnchorPoint = Vector2.new(0.5, 0.5)
				lock.Position = UDim2.fromScale(0.5, 0.55)
				lock.Size = UDim2.fromScale(0.42, 0.42)
				lock.ZIndex = 8
				local a = Instance.new("UIAspectRatioConstraint")
				a.Parent = lock
				lock.Parent = card.ImageArea
			end
			Plate.Label(card.Footer, if e then "Catch it!" else "Coming soon", {
				size = 15,
				color = if e then Theme.Variant.alert.hi else P.Color.Hint,
				frameSize = UDim2.fromScale(1, 0.9),
				order = 1,
			})
		end
	end
end

------------------------------------------------------------------ Quests

-- The legacy row status: committed count, then paid / saving / in progress with the server amount.
local function questStatus(value, state): string
	local amount = if type(value.rewardCash) == "number"
		then CashFormat.FormatExactCash(value.rewardCash) .. " Cash"
		else "Amount unavailable"
	return string.format("%d/%d · ", state.count, state.target)
		.. (
			if state.paid
				then "Completed · Paid " .. amount
				elseif state.state == "Saving" then "Saving · " .. amount
				elseif state.state == "Unavailable" then "Unavailable"
				else amount .. " · In progress"
		)
end

local function questRow(col: Instance, order: number, id: string, value, state)
	local row = wellFrame(col, "Quest_" .. id, order, if state.paid then P.Color.WellRim else nil)
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, px(22))
	head.LayoutOrder = 1
	head.ZIndex = 7
	head.Parent = row
	Plate.Label(head, tostring(value.label or id), {
		size = 17,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -px(26), 1, 0),
		z = 7,
		name = "Quest",
	})
	if state.paid and Theme.Icons.Check ~= "" then
		local ic = Instance.new("ImageLabel")
		ic.Name = "Paid"
		ic.BackgroundTransparency = 1
		ic.Image = Theme.Icons.Check
		ic.AnchorPoint = Vector2.new(1, 0.5)
		ic.Position = UDim2.fromScale(1, 0.5)
		ic.Size = UDim2.fromOffset(px(20), px(20))
		ic.ZIndex = 8
		ic.Parent = head
	end
	if type(value.instruction) == "string" and value.instruction ~= "" then
		textBlock(row, value.instruction, { order = 2, color = P.Color.Hint, name = "Task" })
	end
	Plate.StripedProgress(row, {
		frac = state.ratio,
		text = questStatus(value, state),
		size = UDim2.new(1, 0, 0, px(24)),
		order = 3,
		bag = renderBag,
		colors = if state.paid then P.Button.go else nil,
	})
	return row
end

-- Daily supplies: today's state, the streak checkpoints and the one Claim.
local function suppliesWell(col: Instance, order: number, data, can: boolean)
	local supply = if type(data.supplies) == "table" then data.supplies else {}
	local view = RetentionView.Supply(retentionSnapshot(), rcall("IsRequestPending", "ClaimSupply") == true)
	local well = wellFrame(col, "Supplies", order, if view.state == "Available" and view.enabled then P.Color.WellRim else nil)
	Plate.Label(well, "Daily Supplies" .. (if type(supply.cyclePosition) == "number" then " · Day " .. supply.cyclePosition .. "/7" else ""), {
		size = 17,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 0, px(22)),
		order = 1,
		z = 7,
	})
	local checkpoint = supply.checkpoints
		and supply.checkpoints[if supply.nextLifetimeClaim == 7 then 1 elseif supply.nextLifetimeClaim == 14 then 2 else 0]
	textBlock(well, (if supply.claimedToday
		then "Claimed today. Come back after the UTC reset."
		else "One claim per UTC day. Missed days do not reset the streak.")
		.. (if checkpoint then "\nThis claim also earns " .. tostring(checkpoint.label) .. "." else ""), { order = 2, name = "SupplyStatus" })
	textBlock(well, "Claims so far: " .. tostring(supply.lifetimeClaims or 0) .. " · Next: " .. tostring(supply.nextLifetimeClaim or 1), {
		order = 3,
		color = P.Color.Hint,
		name = "LifetimeProgress",
	})
	for index = 1, 2 do
		local value = supply.checkpoints and supply.checkpoints[index]
		if type(value) == "table" then
			local owned = value.owned == true
			local line = Instance.new("Frame")
			line.Name = "Checkpoint" .. index
			line.BackgroundTransparency = 1
			line.Size = UDim2.new(1, 0, 0, px(if owned then 40 else 18))
			line.LayoutOrder = 3 + index
			line.ZIndex = 7
			line.Parent = well
			Plate.Label(line, "Claim " .. tostring(value.lifetimeClaim) .. " · " .. tostring(value.label) .. " · " .. (if owned
				then "Owned"
				else tostring(math.min(supply.lifetimeClaims or 0, value.lifetimeClaim)) .. "/" .. tostring(value.lifetimeClaim)), {
				size = 14,
				color = if owned then P.Color.WellRim else P.Color.Hint,
				align = Enum.TextXAlignment.Left,
				wrap = true,
				frameSize = UDim2.new(1, -(if owned then px(78) else 0), 1, 0),
				z = 7,
			})
			if owned then
				-- legacy "View / Equip in Appearance"
				Plate.Button(line, {
					variant = "info",
					text = "View",
					size = UDim2.fromOffset(px(72), px(40)),
					position = UDim2.fromScale(1, 0.5),
					anchor = Vector2.new(1, 0.5),
					textSize = 16,
					name = "ViewEquip",
					bag = renderBag,
					onClick = function()
						openSettings(value.cosmeticId)
					end,
				})
			end
		end
	end
	local size = UDim2.new(1, 0, 0, px(48))
	if view.state == "Claimed" then
		Plate.StateWell(well, "Claimed Today", { size = size, order = 8, bag = renderBag, textSize = 18 })
	else
		actionButton(well, {
			variant = "go",
			text = view.text,
			enabled = can and view.enabled == true,
			reason = if view.enabled == true then nil else view.text,
			primary = true, -- the tab's one breathing primary, only while the claim is live
			icon = Theme.Icons.Gift,
			size = size,
			order = 8,
			name = "Claim",
			onClick = function()
				send({ action = "ClaimSupply" })
			end,
		})
	end
	return well
end

-- Pinned progression goal: browse the server's options, Pin / Unpin. Pinning never buys anything.
local function goalWell(col: Instance, order: number, data, can: boolean)
	local options = if type(data.goalOptions) == "table" then data.goalOptions else {}
	local chosen = nil
	for _, value in options do
		if value.id == goalChoiceId then
			chosen = value
			break
		end
	end
	if not chosen then
		chosen = options[1]
		goalChoiceId = chosen and chosen.id
	end
	local goal = if type(data.goal) == "table" then data.goal else nil
	local well = wellFrame(col, "PinnedGoal", order)
	Plate.Label(well, if goal then "Pinned: " .. tostring(goal.name) else "Progression Goal: None", {
		size = 17,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 0, px(22)),
		order = 1,
		z = 7,
		name = "Pinned",
	})
	textBlock(well, RetentionView.GoalText(goal), { order = 2, name = "Requirements" })
	textBlock(well, if chosen
		then "Selected goal: " .. tostring(chosen.name) .. "\n" .. RetentionView.GoalText(chosen)
		else "No available goal choices", { order = 3, color = P.Color.Hint, name = "Candidate" })

	local buttons = {}
	if #options > 1 then
		table.insert(buttons, { text = "Next Goal", variant = "tabOff", enabled = true, onClick = function()
			local index = 0
			for i, value in options do
				if value.id == goalChoiceId then
					index = i
					break
				end
			end
			goalChoiceId = options[index % #options + 1].id
			render(false)
		end })
	end
	if chosen and goal and chosen.id == goal.id then
		table.insert(buttons, { well = "Pinned" })
	elseif chosen then
		table.insert(buttons, { text = "Pin", enabled = can, onClick = function()
			if goalChoiceId then
				send({ action = "PinGoal", goalId = goalChoiceId })
			end
		end })
	end
	if goal then
		table.insert(buttons, { text = "Unpin", enabled = can, onClick = function()
			send({ action = "PinGoal", goalId = "None" })
		end })
	end
	if #buttons > 0 then
		local row = Instance.new("Frame")
		row.Name = "GoalActions"
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, px(44))
		row.LayoutOrder = 4
		row.ZIndex = 7
		row.Parent = well
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, px(6))
		list.Parent = row
		local n = #buttons
		local size = UDim2.new(1 / n, -math.ceil(px(6) * (n - 1) / n), 0, px(42))
		for i, b in buttons do
			if b.well then
				Plate.StateWell(row, b.well, { size = size, order = i, bag = renderBag, textSize = 16 })
			else
				actionButton(row, {
					text = b.text,
					variant = b.variant,
					enabled = b.enabled,
					size = size,
					order = i,
					textSize = 16,
					name = string.gsub(b.text, " ", ""),
					onClick = b.onClick,
				})
			end
		end
	end
	return well
end

local function renderQuests()
	local area = newArea()
	local data = retentionView()
	local snapshot = retentionSnapshot()
	local service = rcall("GetServiceText")
	if tabs then
		tabs.setHint(rcall("GetResetText") or "")
	end
	if type(data) ~= "table" or rcall("IsAvailable") ~= true then
		-- same gate as the legacy panel: it only opened for an eligible (has banked) player
		window.setStat(nil)
		local text = if not (deps and deps.retention)
			then "Quests are switched off right now."
			elseif type(snapshot) == "table" and snapshot.available == true and snapshot.eligible ~= true then "Bank your first brainrot to unlock Daily Quests!"
			else "Quests are getting ready. Check back in a moment!"
		Plate.Label(area, text, {
			size = 20,
			wrap = true,
			color = P.Color.Hint,
			frameSize = UDim2.new(1, -px(40), 0, px(80)),
			position = UDim2.fromOffset(px(20), px(90)),
		})
		requestSnapshotOnce()
		return
	end
	requestSnapshotOnce() -- the legacy panel refreshed its snapshot each time it opened

	local confirmed = rcall("GetConfirmed")
	local can = canAct()
	window.setStat("Done " .. tostring(RetentionView.Completed(data, confirmed)) .. "/3")

	-- left: the three daily quests
	local left = scrollColumn(area, "QuestList", UDim2.fromOffset(0, px(44)), UDim2.new(0.56, -px(6), 1, -px(44)), "QuestsLeft")
	if type(service) == "string" and service ~= "" then
		textBlock(left, service, { order = 0, color = Theme.Variant.alert.hi, name = "Availability" })
	end
	Plate.Label(left, "Daily Quests", {
		size = 18,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 0, px(22)),
		order = 1,
	})
	for index, id in RetentionView.QuestOrder do
		local value = type(data.daily) == "table" and data.daily[id]
		if type(value) == "table" then
			questRow(left, 1 + index, id, value, RetentionView.Row(data, value, confirmed))
		end
	end
	textBlock(left, if data.estimated
		then "Reward preview. Today's amounts lock in on your first banked action."
		else "Today's rewards use the locked " .. tostring(data.band or "") .. " amount.", {
		order = 8,
		color = P.Color.Hint,
		name = "RewardPreview",
	})

	-- right: supplies claim + pinned goal
	local right = scrollColumn(area, "QuestSide", UDim2.new(0.56, 0, 0, px(44)), UDim2.new(0.44, 0, 1, -px(44)), "QuestsRight")
	suppliesWell(right, 1, data, can)
	goalWell(right, 2, data, can)
end

------------------------------------------------------------------ render

render = function(pop: boolean)
	if not window or not isOpen then
		return
	end
	local old = window.Content:FindFirstChild("Cards")
	if old then
		for _, d in old:GetDescendants() do
			if d:IsA("ScrollingFrame") then
				local key = d:GetAttribute("ScrollKey")
				if type(key) == "string" then
					savedScroll[key] = d.CanvasPosition
				end
			end
		end
	end
	if dropScroll then
		savedScroll[dropScroll] = nil
		dropScroll = nil
	end
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	if old and old.Parent then
		old:Destroy()
	end
	if tab == "Index" then
		renderIndex(pop)
	elseif tab == "Quests" then
		renderQuests()
	else
		renderMine(pop)
	end
end

local function selectTab(id: string)
	if id == tab then
		return
	end
	tab = id
	selectedItemId, selectedSpeciesId = nil, nil
	table.clear(savedScroll)
	if tabs then
		tabs.setActive(id)
	end
	render(true)
end

local function startListeners()
	openBag = Plate.Bag()
	local r = deps and deps.retention
	if r and typeof(r.Changed) == "Instance" and r.Changed:IsA("BindableEvent") then
		openBag.add(r.Changed.Event:Connect(function()
			if tab == "Index" or tab == "Quests" then
				scheduleRender()
			end
		end))
	end
	local presentation = controller("Phase12PresentationController")
	local progressChanged = presentation and presentation.CollectionProgressChanged
	if typeof(progressChanged) == "Instance" and progressChanged:IsA("BindableEvent") then
		openBag.add(progressChanged.Event:Connect(function()
			if progressState ~= "idle" then
				loadProgress(false) -- cached read; ignored while the open-time refresh is in flight
			end
		end))
	end
	-- Mine: re-read the replicated world twice a second; rebuild only when it changed.
	-- Quests: tick the UTC reset countdown (the controller owns the clock and the reset re-fetch).
	local alive = true
	openBag.add(function()
		alive = false
	end)
	task.spawn(function()
		while alive and isOpen do
			task.wait(0.5)
			if alive and isOpen and tab == "Mine" then
				local sig = signature(collectOwned())
				if sig ~= lastSignature then
					render(false)
				end
			elseif alive and isOpen and tab == "Quests" and tabs then
				tabs.setHint(rcall("GetResetText") or "")
			end
		end
	end)
end

------------------------------------------------------------------ public

-- open(deps, tabId?): deps = { shop = Phase13ShopController, retention = RetentionController? };
-- tabId = "Mine" | "Index" | "Quests" (optional; keeps the last tab when omitted).
function Screen.open(d, tabId: string?)
	deps = d or deps
	local wanted = if type(tabId) == "string" and TAB_IDS[tabId] then tabId else nil
	if isOpen then
		if wanted then
			selectTab(wanted)
		end
		return
	end
	if wanted then
		tab = wanted
	end
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Brainrots",
			title = "Brainrots",
			icon = Shots.get("BRT_002"),
			onClose = function()
				Screen.close(false)
			end,
		})
	end
	MenusV2.setOpen(WINDOW_ID, function(instant)
		Screen.close(instant)
	end, nil)
	isOpen = true
	selectedItemId, selectedSpeciesId = nil, nil
	refreshFavourites()
	table.clear(savedScroll)
	requestedRetention = false
	if progressState ~= "loading" then
		progressState = "idle"
	end
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

-- toggle(deps, tabId?): closes when open (on that tab, if one is named); otherwise opens / switches.
function Screen.toggle(d, tabId: string?)
	local wanted = if type(tabId) == "string" and TAB_IDS[tabId] then tabId else nil
	if isOpen and (wanted == nil or wanted == tab) then
		Screen.close(false)
	else
		Screen.open(d, wanted)
	end
end

function Screen.isOpen(): boolean
	return isOpen
end

return Screen
