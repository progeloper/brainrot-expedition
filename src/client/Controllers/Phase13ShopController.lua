--!strict
-- Phase 13 shop logic. No view code lives here: every category opens a Stud Pop Plate screen
-- (src/client/UI/Screens) that reads the snapshot and calls back through `ctx`. This controller keeps
-- every remote call, payload, busy/pending state and the Saving -> Status polling.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local Marketplace = game:GetService("MarketplaceService")
local PriceRules = require(RS.Shared.Utility.Phase13CommerceRules)
local Strings = require(RS.Shared.Config.Phase13Strings)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)
local MenusV2 = require(script.Parent.Parent.UI.MenusV2)
local StallAudit = require(script.Parent.Parent.Utility.StallAudit)
-- category -> screen module (Screen.open(ctx, category), update(), notify(result, text), close(instant))
local SCREENS = {
	Weapon = "StallWeaponsScreen",
	Cart = "StallCartsScreen",
	Sell = "StallSellScreen",
	Training = "StallTrainingScreen",
	Base = "RebirthScreen",
	Passes = "PassesGemsScreen",
	Cash = "PassesGemsScreen",
	Cosmetics = "PassesGemsScreen",
	Settings = "SettingsScreen",
}
-- opened at a stall/base prompt: the window closes when the player leaves it (MenusV2 anchor)
local STALL_PROMPTS = { Weapon = true, Cart = true, Sell = true, Training = true, Base = true }
-- Playtest Fixes F2: Passes & Gems opened at the Gems stall closes like the other stalls when you leave.
if require(RS.Shared.Config.PlaytestFixesFlags).Part("GemsStall") then
	STALL_PROMPTS.Passes = true
end
local player = Players.LocalPlayer
local Controller = {}
local screen: any = nil -- the open screen module (nil = shop closed)
local previewScreen: any = nil -- PreviewScreen, loaded on first use
local remote: any = nil
local update: any = nil
local snapshot: any = nil
local current = "Passes"
local busy = false
local pending: any = nil
local started = false
local connections = {}
local generation = 0
local regionalPrices = {}
local priceRequests = {}
local characterConnections = {}
local watchedCharacter: any = nil
local function screenModule(name: string): any
	local module = script.Parent.Parent.UI.Screens:FindFirstChild(name)
	return if module then require(module) else nil
end
local function cash(value)
	local n = tonumber(value) or 0
	for _, unit in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" } } do
		if n >= unit[1] then
			local scaled = string.format("%.2f", n / unit[1])
			return (scaled:gsub("0+$", ""):gsub("%.$", "")) .. unit[2]
		end
	end
	return string.format("%.0f", n)
end
-- A yielding Snapshot may complete after Close, death, Stop or a newer open.
-- Keep the computed result local until the exact request/context still owns it.
function Controller.CreateOpenRequestFlow()
	local currentTicket = nil
	local flow = {}
	function flow:Cancel()
		currentTicket = nil
	end
	function flow:Run(character, fetchSnapshot, isCurrentContext, applySnapshot)
		local ticket = {}
		currentTicket = ticket
		local result = fetchSnapshot()
		if currentTicket ~= ticket or not isCurrentContext(character) then
			return false
		end
		currentTicket = nil
		return applySnapshot(result)
	end
	return flow
end
local openRequests = Controller.CreateOpenRequestFlow()
-- Focus ownership helpers shared with RetentionController's panel (and unit-tested). The shop's own
-- Plate windows take no gamepad selection, so the shop no longer keeps a flow of its own.
function Controller.IsRestorableSelection(value, playerGui, shopGui)
	if typeof(value) ~= "Instance" or not value:IsA("GuiObject") or not value.Parent
		or not value.Selectable or not playerGui or not value:IsDescendantOf(playerGui)
		or (shopGui and value:IsDescendantOf(shopGui)) then
		return false
	end
	local ancestor = value
	while ancestor and ancestor ~= playerGui do
		if ancestor:IsA("GuiObject") and not ancestor.Visible
			or ancestor:IsA("LayerCollector") and not ancestor.Enabled then
			return false
		end
		ancestor = ancestor.Parent
	end
	return ancestor == playerGui
end
function Controller.CreateSelectionOwnershipFlow(getSelected, setSelected, isOwned, isUsable)
	local opened, remembered, previous = false, false, nil
	local flow = {}
	function flow:Open()
		if opened then return false end
		local selected = getSelected()
		previous = if selected and not isOwned(selected) and isUsable(selected) then selected else nil
		opened, remembered = true, true
		return true
	end
	function flow:RestoreClosed(allowEmpty)
		if opened or not remembered then return false end
		local selected = getSelected()
		-- Once closed, a later callback cannot recreate focus the player cleared.
		if selected == nil and allowEmpty ~= true then return false end
		-- A different UI has taken focus; this shop cannot take it back.
		if selected ~= nil and not isOwned(selected) then return false end
		local restore = if previous and not isOwned(previous) and isUsable(previous) then previous else nil
		if selected ~= restore then setSelected(restore) end
		return true
	end
	function flow:Close()
		local wasOpen = opened
		opened = false
		return self:RestoreClosed(wasOpen)
	end
	function flow:Forget()
		opened, remembered, previous = false, false, nil
	end
	return flow
end
local function call(payload)
	if not remote then
		return { ok = false, code = "UNAVAILABLE" }
	end
	local ok, result = pcall(remote.InvokeServer, remote, payload)
	return if ok and type(result) == "table" then result else { ok = false, code = "UNAVAILABLE" }
end
local function message(result)
	if result.state == "Saving" then
		return Strings.Saving
	end
	if result.ok then
		return Strings.Saved
	end
	if result.code == "STALE_PREVIEW" or result.code == "STALE_INVENTORY" then
		return Strings.Stale
	end
	if result.code == "INSUFFICIENT_CASH" then
		return Strings.NeedCash
	end
	if result.code == "INSUFFICIENT_GEMS" then
		return Strings.NotEnoughGems
	end
	if result.code == "BOOST_FULL" then
		return Strings.BoostFull
	end
	if result.code == "STORM_FULL" then
		return Strings.StormFull
	end
	if
		result.code == "PROFILE_STORAGE_HEADROOM"
		or result.code == "PAID_LEDGER_FULL"
		or result.code == "PAID_CAPACITY_RECOVERY_BLOCKED"
		or result.code == "ENVELOPE_MEASUREMENT_UNAVAILABLE"
	then
		return Strings.PaidTemporarilyUnavailable
	end
	if result.code == "BUSY" then
		return Strings.Pending
	end
	if result.code == "EQUIPPED" then
		return "Switch to something else first, then sell it."
	end
	if result.code == "NOT_SELLABLE" or result.code == "NOT_FOR_SALE" then
		return "This can't be sold."
	end
	if result.code == "Favourite" or result.code == "FAVOURITE" then
		return "That's a favourite. Unstar it first."
	end
	if result.code == "NOT_OWNED" then
		return "Bank it first, then you can star it."
	end
	if result.code == "QuoteChanged" then
		return "Prices changed. Check the total and try again."
	end
	if result.code == "NotOnPlatform" then
		return "One of those isn't on a platform any more."
	end
	if result.code == "BankSavePending" or result.code == "BANK_SAVE_PENDING" then
		return "Still saving. Try again in a moment."
	end
	if result.code == "TooFarAway" then
		return Strings.ShopRequired
	end
	if result.code == "NOT_CARRYING" or result.code == "NO_CARRIED_BRAINROT" then
		return "Carry a brainrot to the counter to sell it."
	end
	if result.code == "OWN_BASE_REQUIRED" or result.code == "SHOP_REQUIRED" or result.code == "CAMP_REQUIRED" then
		return Strings.ShopRequired
	end
	return Strings.Unavailable
end
-- Status text for the player goes to the open screen (each screen decides how to show it).
local function notify(result, text)
	if screen and screen.notify then
		screen.notify(result, text)
	end
end
local function render()
	if screen then
		screen.update()
	end
end
-- MenusV2 windows outside the shop (HUD Inventory) listen for fresh snapshots.
Controller.Changed = Instance.new("BindableEvent")
local function refresh()
	local token = generation
	local result = call({ action = "Snapshot" })
	if started and generation == token and result.ok then
		snapshot = result
		Controller.Changed:Fire(snapshot)
	end
end
local function closePreview()
	if previewScreen then
		previewScreen.close(true)
	end
end
local function disconnectScoped(values)
	for _, connection in values do connection:Disconnect() end
	table.clear(values)
end
local function setShopOpen(value)
	local requested = value == true
	if not requested then openRequests:Cancel() end
	if requested then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not started or player:GetAttribute("Phase13CinematicActive") == true
			or not humanoid or humanoid.Health <= 0 then
			return false
		end
	end
	player:SetAttribute("Phase13ShopOpen", requested)
	if not requested then
		closePreview()
		if screen then
			-- animate the Plate window out; the shop's state is already closed
			local closing = screen
			screen = nil
			closing.close()
			MenusV2.cleared("shop")
		end
	end
	return requested
end
local function bindCharacter(character)
	disconnectScoped(characterConnections)
	watchedCharacter = character
	if not character then return end
	local function watchHumanoid(humanoid)
		if not started or watchedCharacter ~= character or not humanoid:IsA("Humanoid") then return end
		disconnectScoped(characterConnections)
		table.insert(characterConnections, humanoid.Died:Connect(function()
			if watchedCharacter == character then setShopOpen(false) end
		end))
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		watchHumanoid(humanoid)
	else
		table.insert(characterConnections, character.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then watchHumanoid(child) end
		end))
	end
end
local function track(result)
	notify(result, message(result))
	if result.state == "Saving" then
		pending = result.operationId
		local id = pending
		local token = generation
		task.spawn(function()
			local toldPending = false
			while started and pending == id and generation == token do
				task.wait(1)
				local status = call({ action = "Status", operationId = id })
				if status.state == "Confirmed" then
					pending = nil
					busy = false
					notify(status, Strings.Saved)
					refresh()
					render()
					return
				end
				if not toldPending then
					toldPending = true -- once per operation, not every poll
					notify(status, Strings.Pending)
				end
			end
		end)
	else
		busy = false
		refresh()
		render()
	end
end
local function mutate(action, category, id)
	if busy or not snapshot then
		return
	end
	busy = true
	track(call({
		action = action,
		category = category,
		id = id,
		operationId = Http:GenerateGUID(false),
		previewRevision = snapshot.previewRevision,
		sequence = snapshot.nextSequence,
	}))
end
-- Marketplace localized prices must be retrieved in this client context.
-- The server sends only verified configured identities and remains the prompt/grant authority.
local function regionalPrice(offer)
	if
		not offer.enabled
		or type(offer.platformId) ~= "number"
		or (offer.platformKind ~= "Product" and offer.platformKind ~= "GamePass")
	then
		return nil
	end
	local key = offer.platformKind .. ":" .. tostring(offer.platformId)
	local cached = regionalPrices[key]
	if cached and os.clock() - cached.at < (if cached.value ~= nil then 300 else 15) then
		return cached.value
	end
	if not priceRequests[key] then
		local token = {}
		priceRequests[key] = token
		task.defer(function()
			if priceRequests[key] ~= token or not started then
				return
			end
			local ok, info = pcall(
				Marketplace.GetProductInfoAsync,
				Marketplace,
				offer.platformId,
				if offer.platformKind == "Product" then Enum.InfoType.Product else Enum.InfoType.GamePass
			)
			if priceRequests[key] ~= token then
				return
			end
			regionalPrices[key] = { value = if ok then PriceRules.DisplayPrice(offer, info) else nil, at = os.clock() }
			priceRequests[key] = nil
			-- a price arrived: the open screen shows it (Passes & Gems, Weapons specials)
			if started then
				render()
			end
		end)
	end
	return nil
end
-- Screen facade: every function sends exactly the payload the legacy panel sent for that action.
local function newGuid()
	return Http:GenerateGUID(false)
end
local ctx = {}
ctx.snapshot = function()
	return snapshot
end
ctx.category = function()
	return current
end
ctx.isBusy = function()
	return busy or pending ~= nil
end
ctx.cash = function(value)
	return cash(value)
end
ctx.message = function(result)
	return message(result)
end
ctx.strings = Strings
ctx.regionalPrice = function(row)
	return regionalPrice(row)
end
-- Weapon/Cart: legacy sends mutate("Select" | Strings.Purchase, category, id)
ctx.select = function(category, id)
	mutate("Select", category, id)
end
ctx.buy = function(category, id)
	mutate(Strings.Purchase, category, id)
end
ctx.trainingRoller = function(rollerId)
	if busy or pending then
		return
	end
	busy = true
	track(call({ action = "TrainingRoller", rollerId = rollerId, operationId = newGuid() }))
end
ctx.gemShop = function(itemId)
	if busy or pending then
		return
	end
	busy = true
	track(call({ action = "GemShop", itemId = itemId, operationId = newGuid() }))
end
ctx.sellBack = function(category, id)
	if busy or pending then
		return
	end
	busy = true
	track(call({ action = "SellBack", category = category, id = id, operationId = newGuid() }))
end
-- Sell stall > Brainrots: the player's banked brainrots with the server's sale values (read-only).
ctx.sellList = function()
	return call({ action = "SellList" })
end
-- Sells the picked banked brainrots in one request. `expectedTotal` is the total the player was shown;
-- the server sells nothing if its own total differs.
ctx.sellBanked = function(ids, expectedTotal)
	if busy or pending then
		return nil
	end
	busy = true
	local result = call({ action = "SellBanked", ids = ids, expectedTotal = expectedTotal })
	busy = false
	if not result.ok then
		notify(result, message(result))
	end
	refresh()
	return result
end
-- Favourite lock: stars or unstars one owned brainrot ({action="Favourite", id, value}). A starred
-- brainrot cannot be sold. The fresh snapshot carries `favourites`.
ctx.setFavourite = function(id, value)
	local result = call({ action = "Favourite", id = id, value = value == true })
	if not result.ok then
		notify(result, message(result))
	end
	refresh()
	return result
end
ctx.sellCarried = function()
	if busy or pending then
		return nil
	end
	local result = call({ action = "SellCarried" })
	if not result.ok then
		notify(result, message(result))
	else
		setShopOpen(false)
	end
	return result
end
ctx.prompt = function(offerId)
	if busy or pending then
		return nil
	end
	busy = true
	local result = call({ action = "Prompt", offerId = offerId })
	busy = false
	return result
end
ctx.rebirthQuote = function(rewardId, route)
	if busy then
		return nil
	end
	return call({ action = "Quote", rewardId = rewardId, route = route })
end
ctx.rebirthConfirm = function(q)
	busy = true
	q.action = "Rebirth"
	q.operationId = newGuid()
	q.sequence = q.nextSequence
	track(call(q))
end
-- Appearance (Settings > Look / Cosmetics). The server accepts these only at the player's own base.
ctx.appearance = function(key, value)
	if busy then
		return
	end
	busy = true
	track(call({ action = "Appearance", key = key, value = value, operationId = newGuid() }))
end
ctx.cosmeticPurchase = function(id)
	if busy then
		return
	end
	busy = true
	track(call({ action = "CosmeticPurchase", id = id, operationId = newGuid() }))
end
-- Reduced Motion is a VFX setting (its own remote). Returns true when the server saved it, false
-- when it did not, nil when another action is still in flight (nothing sent).
ctx.setReducedMotion = function(value)
	if busy then
		return nil
	end
	busy = true
	local name = require(RS.Shared.Constants.RemoteNames).VFXSettingsRequest
	local settings = RS.Remotes:FindFirstChild(name)
	local ok, result = pcall(function()
		return settings:InvokeServer({ action = "Set", ReducedMotion = value == true })
	end)
	busy = false
	return ok and type(result) == "table" and result.ok == true
end
-- 3D previews are local only (PreviewScreen: a dialog above the open window).
local function preview(): any
	if not previewScreen then
		previewScreen = screenModule("PreviewScreen")
	end
	return previewScreen
end
-- kind: "Weapon" | "Cart" | "Base"; id: weapon id / cart assetName / design id; finish: optional finish id
ctx.preview = function(kind, id, finish)
	return preview().open(kind, id, finish)
end
-- finishId nil = the VIP rift, "FIN_SINGULARITY" = its DEV preview; vip = false shows the plain rift
ctx.previewRift = function(finishId, vip)
	return preview().openRift(finishId, vip)
end
-- several previews in one dialog: { { label, kind, id, finish } | { label, rift = true, finishId, vip } }
ctx.previewSet = function(items, index)
	return preview().openSet(items, index)
end
ctx.close = function()
	setShopOpen(false)
end
ctx.refresh = function()
	refresh()
end

-- `focus` is an optional hint for the screen (Settings: the tab to open on).
local function open(category, focus: string?)
	local name = SCREENS[category]
	if not name then
		warn(string.format("[Phase13Shop] Unknown shop category %s", tostring(category)))
		return
	end
	current = category
	generation += 1
	openRequests:Run(player.Character, function()
		return call({ action = "Snapshot" })
	end, function(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return started
			and player.Character == character and humanoid ~= nil and humanoid.Health > 0
			and player:GetAttribute("Phase13CinematicActive") ~= true
	end, function(result)
		local nextScreen = screenModule(name)
		if not nextScreen then
			warn(string.format("[Phase13Shop] Screen %s is missing", name))
			return false
		end
		if not setShopOpen(true) then
			return false
		end
		closePreview()
		if screen and screen ~= nextScreen then
			local old = screen
			screen = nil
			old.close(true)
		end
		screen = nextScreen
		if result.ok then snapshot = result end
		local anchor = if STALL_PROMPTS[category] then MenusV2.nearestPrompt() else nil
		MenusV2.setOpen("shop", function()
			setShopOpen(false)
		end, anchor)
		-- Playtest Fixes 2 E3 (DEV): which window opened at which stall.
		StallAudit.Record(category, anchor or MenusV2.nearestPrompt())
		nextScreen.open(ctx, category, focus)
		if category == "Passes" or category == "Cash" then
			AudioCue.Play("U8", { bus = "UI", cooldown = 1 })
			task.spawn(function()
				call({ action = "OfferView", group = category })
			end)
		end
		return true
	end)
end
-- HUD Settings / Inventory gear: the Settings window. A cosmetic id (Retention's unlocked cosmetic)
-- opens it on the Cosmetics tab.
function Controller.OpenAppearance(cosmeticId)
	if not started then return false end
	open("Settings", if type(cosmeticId) == "string" then "Cosmetics" else nil)
	return true
end
function Controller.Start()
	if started then
		return false
	end
	started = true
	local remotes = RS:WaitForChild("Remotes")
	remote = remotes:WaitForChild("Phase13Request")
	update = remotes:WaitForChild("Phase13Update")
	table.insert(
		connections,
		update.OnClientEvent:Connect(function(payload)
			if payload.kind == "Open" and payload.category == "Cart" then
				-- The cargo bay's anvil shares a key with the Carts counter; when the player stood nearer
				-- the anvil, the bay took that press and the Carts shop stays shut.
				local bay = require(script.Parent.Parent.UI.Screens.CargoBayScreen) :: any
				if bay.holdsPress() then
					return
				end
			end
			if payload.kind == "Open" then
				open(payload.category)
			elseif payload.kind == "Confirmed" then
				local response = payload.response
				if response.operationId == pending then
					pending = nil
					busy = false
				end
				if response.kind == "Rebirth" then
					setShopOpen(false)
					require(script.Parent.Phase12PresentationController).StartRebirthPresentation(response, {
						reducedMotion = player:GetAttribute("ReducedMotion") == true,
						plot = response.presentation and response.presentation.plot,
						sacrificedIndividuals = response.presentation and response.presentation.sacrificedIndividuals,
						branch = response.result and response.result.route,
						vip = player:GetAttribute("Entitlement_VIP") == true,
					})
				end
				refresh()
				render()
			end
		end)
	)
	table.insert(connections, player:GetAttributeChangedSignal("Phase13CinematicActive"):Connect(function()
		if player:GetAttribute("Phase13CinematicActive") == true then
			setShopOpen(false)
		end
	end))
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		setShopOpen(false)
		bindCharacter(character)
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function(character)
		if watchedCharacter == character then
			setShopOpen(false)
			bindCharacter(nil)
		end
	end))
	bindCharacter(player.Character)
	setShopOpen(false)
	return true
end
-- The facade the screens get; HUD windows (Inventory) use it too.
-- ctx.refresh() fetches a Snapshot and fires Controller.Changed.
function Controller.Context()
	return ctx
end
-- Playtest Fixes 2 A2 watchdog: Phase13ShopOpen is set but the shop window is not the open MenusV2
-- window. Returns true when it healed.
function Controller.HealStale()
	if player:GetAttribute("Phase13ShopOpen") == true and MenusV2.currentId() ~= "shop" then
		setShopOpen(false)
		return true
	end
	return false
end
-- HUD rail, kiosk and Gems pill: the same open path as the server's "Open" event.
function Controller.OpenFromHud(category)
	if not started then
		return false
	end
	open(category or "Passes")
	return true
end
function Controller.Stop()
	setShopOpen(false)
	started = false
	disconnectScoped(characterConnections)
	watchedCharacter = nil
	table.clear(priceRequests)
	table.clear(regionalPrices)
	generation += 1
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	snapshot = nil
end
return Controller
