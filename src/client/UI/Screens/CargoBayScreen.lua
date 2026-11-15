--!nocheck
-- MenusV2 Cargo bay (cart upgrades). Opened only by the server: OpenCartUpgradeShop, fired from the
-- "Upgrade Cart" prompt (CartUpgradePrompt) on the part tagged CartUpgradeStall. CartUpgradeController
-- keeps all state and every remote call; this screen draws ctx.snapshot() and calls back:
--   Buy    -> ctx.buy(offerId)    = CartUpgradeShopRequest { operation = "Purchase", contextId, requestId, offerId }
--   Track  -> ctx.track(offerId)  = Phase12ProgressRequest { action = "TrackUpgrade", offerId }
--   Close  -> ctx.close()         = CloseCartUpgradeShop:FireServer(contextId)
-- One card per server offer, in server order. Title, effect, ownership, requirement lines, price and
-- lock reason are the server's text, shown unchanged. Config (Upgrades) is read only to pick the
-- drawing: Cargo track offers get the pallet with `level` crates lit.
-- Also exports the pallet drawing and the bay lookup for StallCartsScreen's Cargo tab.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)

local Plate, Theme = Common.Plate, Common.Theme
local P = Theme.Plate
local px = Theme.px

local Screen = {}

local WINDOW_ID = "CargoBay"
local STALL_TAG = "CartUpgradeStall"
local PROMPT_NAME = "CartUpgradePrompt"
local INK = P.Color.Ink
local TOP_H = 28 -- balance + status strip
local ACTION_H = 42
local SCROLL_MOVE_PX = 10 -- a press that travels this far is a scroll, not a buy
local STATUS_COLOR = Color3.fromRGB(255, 235, 130)
local ERROR_COLOR = Color3.fromHex("#FF6B7A")
local INFO_COLOR = Color3.fromHex("#9AD2FF")

local ctx = nil
local window = nil
local isOpen = false
local renderBag = nil
local renderQueued = false
local popNext = false
local balanceLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
-- The bay's anvil and the Carts counter stand a few studs apart and share a key (E / X), so one press
-- can fire both prompts. Whichever prompt the player stands closer to wins that press.
local SHOP_ID = "shop"
local TIE_SECONDS = 0.3
local SHOP_RECENT_SECONDS = 0.75
local expectedUntil = 0
local openToken = 0
local wonAt = -math.huge -- when a prompt press last opened the bay ahead of the Carts shop

------------------------------------------------------------------ shared with StallCartsScreen
local function inkBox(parent: Instance, name: string, color: Color3, x: number, y: number, w: number, h: number, z: number, transparency: number?): Frame
	local f = Plate.frame(parent, name, {
		BackgroundTransparency = transparency or 0,
		BackgroundColor3 = color,
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		ZIndex = z,
	})
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px(2))
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = INK
	st.Thickness = px(2)
	st.Transparency = transparency or 0
	st.Parent = f
	return f
end

-- Pallet with `lit` of 3 crates (mockup SVG viewBox 160x110, Frames only); unlit crates are ghosts.
-- The bob loop is registered on `bag`.
function Screen.pallet(area: Frame, lit: number, index: number, bag): Frame
	local holder = Plate.frame(area, "Pallet", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.86, 0.92),
		ZIndex = 7,
	})
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 160 / 110
	ar.Parent = holder
	local function vb(name, color, x, y, w, h, z, t)
		return inkBox(holder, name, color, x / 160, y / 110, w / 160, h / 110, z, t)
	end
	vb("Board", Color3.fromHex("#A8743F"), 20, 86, 120, 11, 8)
	for i, fx in { 26, 72, 118 } do
		vb("Foot" .. i, Color3.fromHex("#7A4A22"), fx, 96, 16, 9, 7)
	end
	local crates = {
		{ 28, 50, Color3.fromHex("#D89A4A"), Color3.fromHex("#8A5A32") },
		{ 84, 50, Color3.fromHex("#D89A4A"), Color3.fromHex("#8A5A32") },
		{ 56, 14, Color3.fromHex("#FFD27A"), Color3.fromHex("#C98A4B") },
	}
	for i, c in crates do
		local ghost = if i <= lit then 0 else 0.82
		local crate = vb("Crate" .. i, c[3], c[1], c[2], 48, 36, 9, ghost)
		for s = -1, 1, 2 do
			Plate.frame(crate, "Brace", {
				BackgroundTransparency = ghost,
				BackgroundColor3 = c[4],
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1.12, 0.1),
				Rotation = s * 36.87,
				ZIndex = 10,
			})
		end
	end
	if bag and not Juice.reduced() then
		Plate.loop(bag, holder, P.Motion.ItemBob / 2, { Position = UDim2.new(0.5, 0, 0.52, -px(P.Motion.ItemBobPx)) }, true, (index % 5) * 0.3)
	end
	return holder
end

local function positionOf(inst: Instance?): Vector3?
	if inst and inst:IsA("BasePart") then
		return inst.Position
	elseif inst and inst:IsA("Attachment") then
		return inst.WorldPosition
	elseif inst and inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

-- The cargo bay in the world: the part tagged CartUpgradeStall (the server binds its prompt to a BasePart).
function Screen.stallPart(): BasePart?
	for _, inst in CollectionService:GetTagged(STALL_TAG) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			return inst
		elseif inst:IsA("Model") and inst:IsDescendantOf(workspace) then
			local p = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
			if p then
				return p
			end
		end
	end
	return nil
end

-- The "Upgrade Cart" prompt nearest the player (the server's Open event doesn't name it).
function Screen.stallPrompt(): ProximityPrompt?
	local player = Players.LocalPlayer
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local best, bestDist = nil, math.huge
	local function consider(d: Instance)
		if d:IsA("ProximityPrompt") and d.Name == PROMPT_NAME then
			local pos = positionOf(d.Parent)
			local dist = if root and pos then (root.Position - pos).Magnitude else 0
			if best == nil or dist < bestDist then
				best, bestDist = d, dist
			end
		end
	end
	for _, inst in CollectionService:GetTagged(STALL_TAG) do
		if inst:IsDescendantOf(workspace) then
			for _, d in inst:GetDescendants() do
				consider(d)
			end
		end
	end
	return best
end

-- Presses the bay's own prompt for the player (the same server path as pressing it in the world), so the
-- Carts window can open the bay. False when the prompt is missing, disabled or out of reach.
function Screen.request(): boolean
	local prompt = Screen.stallPrompt()
	local player = Players.LocalPlayer
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = prompt and positionOf(prompt.Parent)
	if not (prompt and prompt.Enabled and root and pos) or (root.Position - pos).Magnitude > prompt.MaxActivationDistance then
		return false
	end
	expectedUntil = os.clock() + 2
	prompt:InputHoldBegin()
	prompt:InputHoldEnd()
	return true
end

------------------------------------------------------------------ offer helpers (read-only)
local function snapshot()
	return ctx and ctx.snapshot()
end

-- Cargo track level of an offer (config), nil for anything else the server lists.
local function cargoLevel(offerId: string): number?
	local def = Upgrades.Get(offerId)
	if def and def.category == "Cargo" and type(def.grant) == "table" and def.grant.trackId == "Cargo" then
		return def.grant.level
	end
	return nil
end

local function isOwned(offer): boolean
	return offer.state == "Owned" or offer.state == "Maxed"
end

local function statText(s): string?
	local total, owned, cargoTotal, cargoOwned = 0, 0, 0, 0
	for _, offer in s.offers do
		total += 1
		if isOwned(offer) then
			owned += 1
		end
		if cargoLevel(offer.offerId) then
			cargoTotal += 1
			if isOwned(offer) then
				cargoOwned += 1
			end
		end
	end
	if cargoTotal > 0 then
		return "Cargo " .. cargoOwned .. "/" .. cargoTotal
	elseif total > 0 then
		return "Owned " .. owned .. "/" .. total
	end
	return nil
end

-- The server's reason for a card that can't be bought: its explanation, else its first requirement line.
local function lockReason(offer): string
	if type(offer.primaryExplanation) == "string" and offer.primaryExplanation ~= "" then
		return offer.primaryExplanation
	end
	return offer.requirementLines[1] or offer.actionLabel or "Locked"
end

------------------------------------------------------------------ small builders
-- Fixed 14 px wrapped body text that grows downwards (server sentences, never rewritten).
local function bodyText(parent: Instance, name: string, text: string, color: Color3?, order: number): TextLabel
	local l = Plate.Label(parent, text, { size = 14, min = 14, wrap = true, color = color, order = order, name = name, z = 9 })
	l.TextScaled = false
	l.TextSize = px(14)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.fromScale(1, 0)
	return l
end

local function requestClose(instant: boolean?)
	local c = ctx
	if c then
		c.close() -- controller: CloseCartUpgradeShop, then Screen.close
	end
	Screen.close(instant) -- no-op when the controller already closed the view
end

local function buildTop()
	local top = Plate.frame(window.Content, "Top", { Size = UDim2.new(1, 0, 0, px(TOP_H)), ZIndex = 6 })
	local left = Plate.frame(top, "Balance", { Position = UDim2.fromOffset(px(4), 0), Size = UDim2.fromScale(0.45, 1), ZIndex = 6 })
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, px(5))
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = left
	Plate.Icon(left, Theme.Icons.Cash, UDim2.fromOffset(px(22), px(22)), 7, 1)
	balanceLabel = Plate.Label(left, "", { size = 18, align = Enum.TextXAlignment.Left, color = P.Color.Cash, z = 7, order = 2, name = "BalanceText" })
	balanceLabel.TextScaled = false
	balanceLabel.TextSize = px(18)
	balanceLabel.AutomaticSize = Enum.AutomaticSize.X
	balanceLabel.Size = UDim2.fromScale(0, 1)
	statusLabel = Plate.Label(top, "", {
		size = 16,
		min = 14,
		align = Enum.TextXAlignment.Right,
		color = STATUS_COLOR,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -px(6), 0, 0),
		frameSize = UDim2.new(0.55, -px(6), 1, 0),
		z = 7,
		name = "StatusMessage",
	})
end

-- A press on a buy button that travels (the row scrolls sideways) must not become a purchase.
local function guardScroll(button: GuiButton)
	local active: InputObject? = nil
	local start: Vector3? = nil
	renderBag.add(button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			active, start = input, input.Position
			if ctx then
				ctx.pressBegan()
			end
		end
	end))
	renderBag.add(button.InputChanged:Connect(function(input)
		if input == active and start ~= nil and (input.Position - start).Magnitude >= SCROLL_MOVE_PX then
			if ctx then
				ctx.pressMoved()
			end
		end
	end))
end

------------------------------------------------------------------ render
local function buildCard(row: Instance, s, offer, index: number, cardSize: UDim2, primaryId: string?, pop: boolean)
	local level = cargoLevel(offer.offerId)
	local card = Plate.ItemCard(row, {
		name = offer.title,
		sub = offer.effectSummary,
		image = if level then nil else Theme.Icons.Cart,
		background = P.Tier.Cargo,
		rays = level ~= nil and level >= 2,
		size = cardSize,
		index = index,
		bag = renderBag,
		pop = pop,
		imageHeight = 0.25,
	})
	card.Root.Name = "Offer_" .. offer.offerId
	if level then
		-- no display shot: drop the placeholder and draw the pallet
		for _, child in card.ImageArea:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local art = Plate.frame(card.ImageArea, "PalletArea", {
			Size = UDim2.fromScale(if s.trackEnabled then 0.62 else 1, 1),
			ZIndex = 6,
		})
		Screen.pallet(art, level, index, renderBag)
	end

	-- Track wallet progress (Phase 12): small, info, one per card
	if s.trackEnabled then
		local entry = s.tracks[offer.offerId]
		local tracked = entry ~= nil and entry.tracked == true
		local busy = entry ~= nil and entry.busy == true
		local trackButton = Plate.Button(card.ImageArea, {
			variant = "info",
			text = if tracked then nil else "Track",
			icon = if tracked then Theme.Icons.Check else nil,
			size = UDim2.fromOffset(px(60), px(40)),
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -px(5), 0.5, 0),
			textSize = 16,
			bag = renderBag,
			name = "Track",
			onClick = if busy
				then nil
				else function()
					ctx.track(offer.offerId)
				end,
		})
		trackButton.Root.ZIndex = 8
	end

	-- footer: the server's ownership + requirement text, then the ONE action pinned to the bottom
	local stack = Plate.frame(card.Footer, "Stack", { Size = UDim2.fromScale(1, 1), ZIndex = 9 })
	local textArea = Plate.frame(stack, "Text", {
		Position = UDim2.fromScale(0.04, 0),
		Size = UDim2.new(0.92, 0, 1, -px(ACTION_H + 8)),
		ZIndex = 9,
		ClipsDescendants = true,
	})
	local tl = Instance.new("UIListLayout")
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.VerticalAlignment = Enum.VerticalAlignment.Top -- if a long requirement overflows, the tail clips, not the top
	tl.Padding = UDim.new(0, px(2))
	tl.Parent = textArea
	bodyText(textArea, "Ownership", offer.ownershipSummary, P.Color.Hint, 1)
	if #offer.requirementLines > 0 then
		bodyText(textArea, "Requirement", table.concat(offer.requirementLines, " • "), nil, 2)
	end

	local actionSize = UDim2.new(0.92, 0, 0, px(ACTION_H))
	local actionPos = UDim2.new(0.5, 0, 1, -px(5))
	local actionAnchor = Vector2.new(0.5, 1)
	if isOwned(offer) then
		Plate.StateWell(stack, offer.actionLabel or "Owned", {
			size = actionSize,
			position = actionPos,
			anchor = actionAnchor,
			bag = renderBag,
			textSize = 17,
		})
		return card
	end
	local buying = s.pendingOfferId == offer.offerId
	local button
	if offer.canActivate then
		button = Plate.Button(stack, {
			variant = "go",
			text = if buying then "Buying…" else offer.priceText,
			icon = Theme.Icons.Cash,
			primary = offer.offerId == primaryId and not s.busy,
			size = actionSize,
			position = actionPos,
			anchor = actionAnchor,
			textSize = 18,
			bag = renderBag,
			name = "Buy",
			onClick = if s.busy
				then nil
				else function()
					ctx.buy(offer.offerId)
				end,
		})
		guardScroll(button.Root)
	else
		button = Plate.LockedButton(stack, lockReason(offer), {
			size = actionSize,
			position = actionPos,
			anchor = actionAnchor,
			textSize = 16,
			bag = renderBag,
			name = "Locked",
		})
	end
	if button.Label then
		-- exact prices and lock reasons are long: give the text everything beside the icon
		button.Label.Size = UDim2.new(1, -px(34), 1, 0)
		button.Label.TextWrapped = not offer.canActivate
	end
	return card
end

local function render()
	renderQueued = false
	local pop = popNext
	popNext = false
	if not window or not isOpen then
		return
	end
	local s = snapshot()
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	local old = window.Content:FindFirstChild("Cards")
	local keep = if old and not pop then old.CanvasPosition else nil
	if old then
		old:Destroy()
	end
	if not s then
		window.setStat(nil)
		return
	end
	window.setStat(statText(s))
	if balanceLabel then
		balanceLabel.Text = s.balanceText
	end
	if statusLabel then
		statusLabel.Text = s.status or ""
	end

	local row = Common.CardRow(window.Content, {
		position = UDim2.fromOffset(0, px(TOP_H + 2)),
		size = UDim2.new(1, 0, 1, -px(TOP_H + 2)),
	})
	row.Name = "Cards"
	local size = window.contentSize()
	local n = #s.offers
	local gap = px(8)
	local shown = math.clamp(n, 1, 3)
	local cardW = math.clamp(math.floor((size.X - px(8) - gap * (shown - 1)) / shown), px(190), px(240))
	local cardH = math.max(px(170), size.Y - px(TOP_H + 2) - px(14))
	local cardSize = UDim2.fromOffset(cardW, cardH)
	if n * cardW + (n - 1) * gap + px(8) <= size.X then
		local list = row:FindFirstChildOfClass("UIListLayout")
		if list then
			list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		end
	end

	-- the ONE breathing primary: the cheapest offer the server says can be bought now
	local primaryId, cheapest = nil, math.huge
	for _, offer in s.offers do
		if offer.canActivate and offer.price < cheapest then
			primaryId, cheapest = offer.offerId, offer.price
		end
	end
	local focus, firstCargo, firstOpen = nil, nil, nil
	for i, offer in s.offers do
		local card = buildCard(row, s, offer, i, cardSize, primaryId, pop)
		if offer.offerId == primaryId then
			focus = card.Root
		end
		if not isOwned(offer) then
			firstOpen = firstOpen or card.Root
			if cargoLevel(offer.offerId) then
				firstCargo = firstCargo or card.Root
			end
		end
	end
	if n == 0 then
		Plate.Label(row, "No upgrades here yet", { size = 18, frameSize = UDim2.fromOffset(px(300), px(40)) })
	end
	if keep then
		task.defer(function()
			if row.Parent then
				row.CanvasPosition = keep
			end
		end)
	else
		-- open on what can be bought now, else the next cargo level, else the first unowned card
		Common.scrollTo(row, focus or firstCargo or firstOpen)
	end
end

local function queueRender(pop: boolean?)
	if pop then
		popNext = true
	end
	if renderQueued then
		return
	end
	renderQueued = true
	task.defer(render)
end

------------------------------------------------------------------ public (called by CartUpgradeController)
local function show(context)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "CargoBay",
			title = "Cargo",
			icon = Theme.Icons.Cart,
			aspect = 980 / 505, -- same frame as the Carts stall
			maxSize = Vector2.new(980 / 1.5, 505 / 1.5),
			onClose = function()
				requestClose(false)
			end,
		})
	end
	-- anchored to the bay prompt: walking away, dying or driving off closes it like the stalls
	MenusV2.setOpen(WINDOW_ID, requestClose, Screen.stallPrompt())
	isOpen = true
	window.open()
	window.clearContent()
	buildTop()
	queueRender(true)
end

local function shopJustOpened(): boolean
	return MenusV2.currentId() == SHOP_ID and MenusV2.currentAge() < SHOP_RECENT_SECONDS
end

local function distanceTo(prompt: ProximityPrompt?): number?
	local player = Players.LocalPlayer
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = prompt and positionOf(prompt.Parent)
	return if root and pos then (root.Position - pos).Magnitude else nil
end

-- True when the player stands nearer the bay's anvil than any shop prompt in reach.
local function bayIsCloser(): boolean
	local bay, shop = distanceTo(Screen.stallPrompt()), distanceTo(MenusV2.nearestPrompt())
	return bay ~= nil and (shop == nil or bay < shop)
end

-- For the shop controller: the bay just won a shared press, so the Carts shop from that press stays shut.
function Screen.holdsPress(): boolean
	return isOpen and os.clock() - wonAt < SHOP_RECENT_SECONDS
end

function Screen.open(context)
	openToken += 1
	local token = openToken
	if os.clock() <= expectedUntil then
		expectedUntil = 0
		show(context)
		return
	end
	local closer = bayIsCloser()
	if shopJustOpened() then
		-- the same press opened the Carts shop first
		if closer then
			wonAt = os.clock()
			show(context) -- replaces the shop window
		else
			context.close() -- hand the bay's server context back
		end
		return
	end
	if MenusV2.nearestPrompt() == nil then
		show(context)
		return
	end
	if closer then
		wonAt = os.clock()
		show(context)
		return
	end
	-- a nearer shop prompt is in reach, so the same press may be opening it: let it land first
	task.delay(TIE_SECONDS, function()
		if token ~= openToken then
			return
		end
		if shopJustOpened() then
			context.close()
		else
			show(context)
		end
	end)
end

-- Controller state changed (pending, result, balance, track).
function Screen.update()
	if isOpen then
		queueRender(false)
	end
end

-- kind: "pending" | "accepted" | "error" | "owned" | "track". The status line always shows the text;
-- results also pop a toast.
function Screen.notify(kind: string, text: string?)
	if not isOpen or type(text) ~= "string" or text == "" then
		return
	end
	local gui = MenusV2.Gui()
	if kind == "accepted" then
		Plate.Toast(gui, text, { icon = Theme.Icons.Check })
	elseif kind == "error" then
		Plate.Toast(gui, text, { color = ERROR_COLOR })
	elseif kind == "track" then
		Plate.Toast(gui, text, { color = INFO_COLOR })
	end
end

function Screen.close(instant: boolean?)
	openToken += 1 -- drops an open that is still waiting on the tie-break
	if not isOpen then
		return
	end
	isOpen = false
	ctx = nil
	if renderBag then
		renderBag.clean()
		renderBag = nil
	end
	balanceLabel, statusLabel = nil, nil
	if window then
		window.close(instant)
	end
	MenusV2.cleared(WINDOW_ID)
end

function Screen.isOpen(): boolean
	return isOpen
end

return Screen
