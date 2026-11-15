--!strict

-- Cart upgrade ("Cargo bay") menu: logic only. The server opens it (OpenCartUpgradeShop, from the
-- "Upgrade Cart" prompt on the part tagged CartUpgradeStall); this controller validates the payload,
-- owns the offer/pending/status state and makes every remote call. The view is
-- UI/Screens/CargoBayScreen (a Plate window in MenusV2); it reads Snapshot() and calls back through
-- the context table below. The view is optional: with injected dependencies and no `View` (specs)
-- the controller runs headless.
--   Buy    -> CartUpgradeShopRequest:InvokeServer({ operation = "Purchase", contextId, requestId, offerId })
--             (8 s without a reply -> one { operation = "Status", ... } check with the same requestId)
--   Open   -> { operation = "Presentation", kind = "MenuRendered", contextId, inputCategory }
--   Track  -> Phase12ProgressRequest:InvokeServer({ action = "TrackUpgrade", offerId })
--   Close  -> CloseCartUpgradeShop:FireServer(contextId)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)

local Controller = {}
local RESPONSE_TIMEOUT_SECONDS = 8

local dependencies: any = nil
local configuredDependencies: any = nil
local started = false
local view: any = nil -- CargoBayScreen (or a spec fake); nil = headless
local connections: { any } = {}
local context: any = nil
local cardsById: { [string]: any } = {} -- offerId -> { Card = live copy of the server card, Order = n }
local orderedCards: { any } = {} -- the same live cards in server order
local tracks: { [string]: any } = {} -- offerId -> { busy, tracked, text }
local menuGeneration = 0
local state = "Closed"
local pending: any = nil
local status = "" -- purchase status line ("Buying…", "Owned • Saving…", a result code, …)
local statusLine = "" -- what the view shows: the newest of the purchase status and the Track result
local scrollGestureMoved = false

local function disconnect(list: { any })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function nonEmptyString(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= 128 and value:match("%c") == nil
end

local function finiteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function inputCategory(): string
	local touch = UserInputService.TouchEnabled
	local keyboard = UserInputService.KeyboardEnabled or UserInputService.MouseEnabled
	local gamepad = UserInputService.GamepadEnabled
	if touch and (keyboard or gamepad) then
		return "Hybrid"
	elseif touch then
		return "Touch"
	elseif gamepad and not keyboard then
		return "Gamepad"
	elseif keyboard then
		return "Desktop"
	end
	return "Unknown"
end

local function validCard(card: any): boolean
	if
		type(card) ~= "table"
		or not nonEmptyString(card.offerId)
		or not nonEmptyString(card.title)
		or not nonEmptyString(card.effectSummary)
		or not nonEmptyString(card.ownershipSummary)
		or not finiteNonNegative(card.price)
		or not nonEmptyString(card.priceText)
		or not nonEmptyString(card.state)
		or type(card.canActivate) ~= "boolean"
		or type(card.requirementLines) ~= "table"
	then
		return false
	end
	for _, line in card.requirementLines do
		if not nonEmptyString(line) then
			return false
		end
	end
	return true
end

local function validOpenPayload(value: any): boolean
	if
		type(value) ~= "table"
		or not nonEmptyString(value.contextId)
		or not finiteNonNegative(value.expiresAtServerTime)
		or value.expiresAtServerTime <= dependencies.Now()
		or not finiteNonNegative(value.balance)
		or type(value.offers) ~= "table"
		or #value.offers > 64
	then
		return false
	end
	local seen = {}
	for _, card in value.offers do
		if not validCard(card) or seen[card.offerId] then
			return false
		end
		seen[card.offerId] = true
	end
	return true
end

------------------------------------------------------------------ view seam (optional)

-- Calls view[method](...) when a view is attached. A view error never breaks the purchase logic.
local function callView(method: string, ...: any): boolean
	if view == nil or type(view[method]) ~= "function" then
		return true
	end
	local ok, problem = pcall(view[method], ...)
	if not ok and dependencies and dependencies.Warn then
		dependencies.Warn(string.format("CartUpgradeController view.%s failed: %s", method, tostring(problem)))
	end
	return ok
end

local function refreshView()
	callView("update")
end

-- kind: "pending" | "accepted" | "error" | "owned" | "track"
local function setStatus(text: string, kind: string?)
	status = text
	statusLine = text
	refreshView()
	if kind then
		callView("notify", kind, text)
	end
end

local function balanceText(): string
	return if context then "Cash " .. CurrencyFormatter.FormatExactCash(context.balance) else ""
end

-- What the view draws. `offers` are the controller's live copies (server text untouched; `state`,
-- `canActivate` and `actionLabel` change only when the server accepts a purchase).
local function snapshot(): any
	if context == nil then
		return nil
	end
	return {
		contextId = context.contextId,
		expiresAtServerTime = context.expiresAtServerTime,
		balance = context.balance,
		balanceText = balanceText(),
		offers = orderedCards,
		state = state,
		busy = pending ~= nil,
		pendingOfferId = if pending then pending.OfferId else nil,
		status = statusLine,
		trackEnabled = Phase12.Enabled == true,
		tracks = tracks,
	}
end

local function closeMenu(notifyServer: boolean)
	if context == nil then
		return
	end
	local contextId = context.contextId
	context = nil
	menuGeneration += 1
	state = "Closed"
	status = ""
	statusLine = ""
	table.clear(tracks)
	if notifyServer then
		dependencies.CloseRemote:FireServer(contextId)
	end
	callView("close", false)
end

local function updateAccepted(result: any)
	local refs = cardsById[result.offerId]
	if refs then
		refs.Card.state = "Owned"
		refs.Card.canActivate = false
		refs.Card.actionLabel = "Owned"
	end
	if finiteNonNegative(result.balance) then
		context.balance = result.balance
	end
	setStatus(if result.persistence == "Confirmed" then "Owned" else "Owned • Saving…", "accepted")
end

local function finishRequest(generation: number, result: any)
	if pending == nil or pending.Generation ~= generation then
		return
	end
	local request = pending
	pending = nil
	if type(result) ~= "table" or result.requestId ~= request.RequestId then
		if context and menuGeneration == generation then
			state = "Open"
			setStatus("Purchase result unavailable. Try again.", "error")
		end
		return
	end
	if result.outcome == "Accepted" then
		if context and menuGeneration == generation then
			state = "Open"
			updateAccepted(result)
		end
	elseif context and menuGeneration == generation then
		state = "Open"
		setStatus(tostring(result.code or "Purchase unavailable"), "error")
	end
end

local function invokeStatus(request: any)
	local statusPayload = {
		operation = "Status",
		contextId = request.ContextId,
		requestId = request.RequestId,
		offerId = request.OfferId,
	}
	local ok, result = pcall(dependencies.RequestRemote.InvokeServer, dependencies.RequestRemote, statusPayload)
	if ok then
		finishRequest(request.Generation, result)
	end
end

local function submit(offerId: string)
	if context == nil or state ~= "Open" or pending ~= nil or scrollGestureMoved then
		return
	end
	local refs = cardsById[offerId]
	if refs == nil or refs.Card.canActivate ~= true then
		return
	end
	local requestId = dependencies.GenerateRequestId()
	local request = {
		Generation = menuGeneration,
		ContextId = context.contextId,
		RequestId = requestId,
		OfferId = offerId,
	}
	pending = request
	state = "Submitting"
	setStatus("Buying…", "pending")
	dependencies.Delay(RESPONSE_TIMEOUT_SECONDS, function()
		if pending == request then
			state = "Resolving"
			setStatus("Checking purchase…", "pending")
			dependencies.Spawn(function()
				invokeStatus(request)
			end)
		end
	end)
	dependencies.Spawn(function()
		local payload = {
			operation = "Purchase",
			contextId = request.ContextId,
			requestId = request.RequestId,
			offerId = request.OfferId,
		}
		local ok, result = pcall(dependencies.RequestRemote.InvokeServer, dependencies.RequestRemote, payload)
		if ok then
			finishRequest(request.Generation, result)
		elseif context and menuGeneration == request.Generation then
			setStatus("Checking purchase…", "pending")
		end
	end)
end

local function progressRemote(): any
	if dependencies.ProgressRemote ~= nil then
		return dependencies.ProgressRemote
	end
	local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = if remoteFolder then remoteFolder:FindFirstChild(RemoteNames.Phase12ProgressRequest) else nil
	return if remote and remote:IsA("RemoteFunction") then remote else nil
end

-- "Track wallet progress" for one offer (Phase 12). One request per offer at a time.
local function track(offerId: string)
	if context == nil or Phase12.Enabled ~= true or cardsById[offerId] == nil then
		return
	end
	local entry = tracks[offerId]
	if entry and entry.busy then
		return
	end
	local remote = progressRemote()
	if remote == nil then
		return
	end
	if entry == nil then
		entry = { busy = false, tracked = false, text = nil }
		tracks[offerId] = entry
	end
	entry.busy = true
	refreshView()
	local token = menuGeneration
	dependencies.Spawn(function()
		local ok, result = pcall(remote.InvokeServer, remote, { action = "TrackUpgrade", offerId = offerId })
		if token ~= menuGeneration or tracks[offerId] ~= entry then
			return
		end
		entry.busy = false
		local progress = if ok and type(result) == "table" then (result.progress or result) else nil
		local tracked = if type(progress) == "table"
			then (progress.trackedUpgrade or (progress.snapshot and progress.snapshot.trackedUpgrade))
			else nil
		if tracked and finiteNonNegative(tracked.shortfall) then
			entry.tracked = true
			entry.text = "Tracking · " .. CurrencyFormatter.FormatCompactCash(tracked.shortfall) .. " Wallet Shortfall"
		else
			entry.tracked = false
			entry.text = "Unavailable To Track"
		end
		statusLine = entry.text
		refreshView()
		callView("notify", "track", entry.text)
	end)
end

-- Handed to the view on open. Screens never call remotes; they call these.
local viewContext = table.freeze({
	snapshot = snapshot,
	buy = submit,
	track = track,
	close = function()
		closeMenu(true)
	end,
	-- A press that began on a buy button / moved 10 px or more (a scroll, not a tap).
	pressBegan = function()
		scrollGestureMoved = false
	end,
	pressMoved = function()
		scrollGestureMoved = true
	end,
})

local function open(value: any)
	if not validOpenPayload(value) then
		dependencies.Warn("Rejected invalid OpenCartUpgradeShop payload")
		return
	end
	if context then
		dependencies.CloseRemote:FireServer(context.contextId)
	end
	menuGeneration += 1
	context = value
	pending = nil
	state = "Open"
	status = ""
	statusLine = ""
	scrollGestureMoved = false
	table.clear(cardsById)
	table.clear(orderedCards)
	table.clear(tracks)
	for order, card in value.offers do
		local copy = table.clone(card)
		orderedCards[order] = copy
		cardsById[copy.offerId] = { Card = copy, Order = order }
	end
	if not callView("open", viewContext) then
		closeMenu(true)
		return
	end
	if dependencies.ReportPresentation then
		dependencies.ReportPresentation({
			operation = "Presentation",
			kind = "MenuRendered",
			contextId = value.contextId,
			inputCategory = dependencies.InputCategory and dependencies.InputCategory() or "Unknown",
		})
	end
end

local function handleUpdate(value: any)
	if type(value) ~= "table" or value.kind ~= "PurchasePersistence" then
		return
	end
	if pending and value.requestId == pending.RequestId then
		return
	end
	local refs = if context then cardsById[value.offerId] else nil
	if refs and value.persistence == "Confirmed" then
		-- the legacy card showed "OWNED" here; the model now says so for the view
		refs.Card.state = "Owned"
		refs.Card.canActivate = false
		refs.Card.actionLabel = "Owned"
		setStatus("Owned", "owned")
	end
end

function Controller.Init(options: any)
	assert(not started, "Cannot replace CartUpgradeController dependencies after Start")
	configuredDependencies = options
end

function Controller.Start(): boolean
	if started then
		return false
	end
	started = true
	local player = if configuredDependencies then configuredDependencies.Player else Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	dependencies = configuredDependencies
		or {
			Player = player,
			OpenRemote = remotes:WaitForChild(RemoteNames.OpenCartUpgradeShop),
			RequestRemote = remotes:WaitForChild(RemoteNames.CartUpgradeShopRequest),
			CloseRemote = remotes:WaitForChild(RemoteNames.CloseCartUpgradeShop),
			UpdateRemote = remotes:WaitForChild(RemoteNames.CartUpgradeShopUpdate),
			InputBegan = UserInputService.InputBegan,
			Now = function()
				return Workspace:GetServerTimeNow()
			end,
			GenerateRequestId = function()
				return HttpService:GenerateGUID(false)
			end,
			Spawn = task.spawn,
			Delay = task.delay,
			Warn = warn,
			InputCategory = inputCategory,
		}
	if configuredDependencies == nil then
		dependencies.ReportPresentation = function(payload)
			dependencies.Spawn(function()
				pcall(dependencies.RequestRemote.InvokeServer, dependencies.RequestRemote, payload)
			end)
		end
		-- The Plate window. Injected dependencies choose their own view (or none: headless).
		local ok, screen = pcall(require, (script.Parent.Parent :: any).UI.Screens.CargoBayScreen)
		if ok then
			dependencies.View = screen
		else
			warn("CartUpgradeController: CargoBayScreen unavailable: " .. tostring(screen))
		end
	end
	view = dependencies.View
	table.insert(connections, dependencies.OpenRemote.OnClientEvent:Connect(open))
	table.insert(connections, dependencies.UpdateRemote.OnClientEvent:Connect(handleUpdate))
	table.insert(
		connections,
		dependencies.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean?)
			if gameProcessed then
				return
			end
			if context and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
				closeMenu(true)
			end
		end)
	)
	return true
end

function Controller.Stop()
	if not started then
		return
	end
	if context then
		closeMenu(false)
	end
	disconnect(connections)
	view = nil
	context = nil
	pending = nil
	state = "Closed"
	status = ""
	statusLine = ""
	table.clear(cardsById)
	table.clear(orderedCards)
	table.clear(tracks)
	dependencies = nil
	configuredDependencies = nil
	started = false
	scrollGestureMoved = false
end

-- The view's read model (nil while closed).
function Controller.Snapshot(): any
	return snapshot()
end

function Controller.IsOpen(): boolean
	return context ~= nil
end

function Controller._TestGetState(): any
	return {
		View = view,
		Context = context,
		Cards = cardsById,
		Offers = orderedCards,
		Tracks = tracks,
		State = state,
		Pending = pending,
		Generation = menuGeneration,
		Status = status,
		StatusLine = statusLine,
		BalanceText = balanceText(),
		Snapshot = snapshot(),
	}
end

function Controller._TestActivate(offerId: string)
	submit(offerId)
end

function Controller._TestTrack(offerId: string)
	track(offerId)
end

function Controller._TestSetScrollGestureMoved(value: boolean)
	scrollGestureMoved = value
end

function Controller._TestClose()
	closeMenu(true)
end

return Controller
