--!strict
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Marketplace = game:GetService("MarketplaceService")
local PriceRules = require(RS.Shared.Utility.Phase13CommerceRules)
local AppearanceRules = require(RS.Shared.Utility.Phase13AppearanceRules)
local Config = require(RS.Shared.Config.Phase13)
local Weapons = require(RS.Shared.Config.Weapons)
local Strings = require(RS.Shared.Config.Phase13Strings)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)
local StudPopUI = require(script.Parent.Parent.UI.StudPopUI)
local ROBUX_GLYPH = utf8.char(0xE002)
local player = Players.LocalPlayer
local Controller = {}
local gui = nil
local panel = nil
local content = nil
local notice = nil
local modal = nil
local remote = nil
local update = nil
local snapshot = nil
local current = "Passes"
local busy = false
local pending = nil
local started = false
local connections = {}
local generation = 0
local regionalPrices = {}
local priceRequests = {}
local riftPreview = nil
local panelConstraints = nil
local headerTitle = nil
local warningClock = nil
local clockConnections = {}
local characterConnections = {}
local watchedCharacter = nil
local function releaseRiftPreview()
	if riftPreview then
		riftPreview.Destroy()
		riftPreview = nil
	end
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
-- Shop owns focus only while its panel is open or a just-closed cinematic
-- resolves native fallback selection. The persistent HUD opener is owned too.
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
local shopFocus = Controller.CreateSelectionOwnershipFlow(function()
	return GuiService.SelectedObject
end, function(value)
	GuiService.SelectedObject = value
end, function(value)
	return typeof(value) == "Instance" and gui ~= nil and value:IsDescendantOf(gui)
end, function(value)
	return Controller.IsRestorableSelection(value, player and player:FindFirstChildOfClass("PlayerGui"), gui)
end)
local function call(payload)
	local ok, result = pcall(remote.InvokeServer, remote, payload)
	return if ok and type(result) == "table" then result else { ok = false, code = "UNAVAILABLE" }
end
local function text(parent, value, size)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = value
	label.TextColor3 = Color3.fromRGB(235, 233, 247)
	label.Font = Enum.Font.Gotham
	label.TextSize = size or 16
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 24)
	label.Parent = parent
	return label
end
local function button(parent, value, action)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 44)
	b.BackgroundColor3 = Color3.fromRGB(65, 55, 104)
	b.BorderSizePixel = 0
	b.Text = value
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 15
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Selectable = true
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	b.Activated:Connect(action)
	return b
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
	if result.code == "NOT_CARRYING" or result.code == "NO_CARRIED_BRAINROT" then
		return "Carry a brainrot to the counter to sell it."
	end
	if result.code == "OWN_BASE_REQUIRED" or result.code == "SHOP_REQUIRED" or result.code == "CAMP_REQUIRED" then
		return Strings.ShopRequired
	end
	return Strings.Unavailable
end
local render
local function refresh()
	local token = generation
	local result = call({ action = "Snapshot" })
	if started and generation == token and result.ok then
		snapshot = result
	end
end
local function closeModal()
	local hadModal = modal ~= nil
	releaseRiftPreview()
	if modal then
		modal:Destroy()
		modal = nil
	end
	if hadModal then
		task.defer(function()
			if started and panel and panel.Visible and current == "Base" and not modal and render then
				render()
			end
		end)
	end
end
local function disconnectScoped(values)
	for _, connection in values do connection:Disconnect() end
	table.clear(values)
end
local function updateShopLayout()
	if not gui or not panel or not panelConstraints then return end
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	local top = math.max(12, size.Y * 0.08)
	local clock = warningClock
	if clock and clock.Parent and clock.Visible then
		-- Both absolute rectangles use native GUI coordinates. Input coordinates
		-- are unrelated to this layout comparison and need no inset conversion.
		local warningBottom = clock.AbsolutePosition.Y + clock.AbsoluteSize.Y - gui.AbsolutePosition.Y
		top = math.max(top, warningBottom + 8)
	end
	top = math.clamp(top, 0, math.max(0, size.Y - 12))
	local availableHeight = math.max(1, size.Y - top - 12)
	local availableWidth = math.max(1, size.X - 24)
	panelConstraints.MinSize = Vector2.zero
	panelConstraints.MaxSize = Vector2.new(math.min(960, availableWidth), math.min(760, availableHeight))
	panelConstraints.MinSize = Vector2.new(math.min(300, availableWidth), math.min(260, availableHeight))
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, top)
	local height = math.min(760, size.Y * 0.84, availableHeight)
	panel.Size = UDim2.new(0.88, 0, 0, height)
	if headerTitle and notice and content then
		local compact = height < 300
		headerTitle.Visible = not compact
		notice.Position = UDim2.fromOffset(18, if compact then 8 else 120)
		notice.Size = if compact then UDim2.new(1, -136, 0, 44) else UDim2.new(1, -36, 0, 48)
		notice.TextSize = if compact then 14 else 15
		content.Position = UDim2.fromOffset(16, if compact then 122 else 174)
		content.Size = UDim2.new(1, -32, 1, if compact then -138 else -190)
	end
end
local function bindWarningClock(clock)
	if warningClock == clock then return end
	disconnectScoped(clockConnections)
	warningClock = clock
	if clock then
		for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do
			table.insert(clockConnections, clock:GetPropertyChangedSignal(property):Connect(updateShopLayout))
		end
		table.insert(clockConnections, clock.Destroying:Connect(function()
			if warningClock == clock then
				disconnectScoped(clockConnections)
				warningClock = nil
				updateShopLayout()
			end
		end))
	end
	updateShopLayout()
end
local function setShopOpen(value)
	local requested = value == true
	if not requested then openRequests:Cancel() end
	if requested then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not started or not panel or player:GetAttribute("Phase13CinematicActive") == true
			or not humanoid or humanoid.Health <= 0 then
			return false
		end
	end
	if requested and panel and not panel.Visible then shopFocus:Open() end
	if panel then panel.Visible = requested end
	player:SetAttribute("Phase13ShopOpen", requested)
	if requested then
		updateShopLayout()
	else
		-- Destroying a selected modal can choose the persistent Shop HUD opener.
		-- Restore only owned focus after that native transition has happened.
		closeModal()
		shopFocus:Close()
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
-- Rebirth UI v2 lines: red YOU LOSE, green YOU GET, payback; confirm enables once they are on screen.
local function richLines(parent, lines)
	for _, line in lines do
		local label = text(parent, line[1], 18)
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = line[2]
	end
end
local function displayConfirm(title, body, onConfirm, lines)
	closeModal()
	modal = Instance.new("Frame")
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(12, 10, 22)
	modal.BackgroundTransparency = 0.05
	modal.ZIndex = 20
	modal.Parent = panel
	local box = Instance.new("ScrollingFrame")
	box.AutomaticCanvasSize = Enum.AutomaticSize.Y
	box.CanvasSize = UDim2.new()
	box.ScrollBarThickness = 6
	box.Size = UDim2.new(1, -48, 1, -48)
	box.Position = UDim2.fromOffset(24, 24)
	box.BackgroundTransparency = 1
	box.Parent = modal
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 15)
	layout.Parent = box
	text(box, title, 22)
	if lines then
		richLines(box, lines)
	end
	text(box, body, 17)
	local cancel = button(box, Strings.Cancel, closeModal)
	local armed = lines == nil
	local confirm = button(box, Strings.ConfirmSacrifice, function()
		if busy or not armed then
			return
		end
		closeModal()
		onConfirm()
	end)
	confirm.BackgroundColor3 = Color3.fromRGB(155, 62, 76)
	if not armed then
		-- enabled only after YOU LOSE / YOU GET have been on screen
		confirm.Active = false
		confirm.AutoButtonColor = false
		confirm.BackgroundTransparency = 0.5
		task.delay(1, function()
			armed = true
			if confirm.Parent then
				confirm.Active = true
				confirm.AutoButtonColor = true
				confirm.BackgroundTransparency = 0
			end
		end)
	end
	GuiService.SelectedObject = cancel
end
local function preview(category, id, finish)
	closeModal()
	local assets = RS:FindFirstChild("CodeAssets")
	local source = nil
	if category == "Weapon" then
		local f = assets and assets:FindFirstChild("Weapons")
		source = f and f:FindFirstChild(id)
	elseif category == "Cart" then
		local f = RS:FindFirstChild("StudioAssets") and RS.StudioAssets:FindFirstChild("Carts")
		source = f and f:FindFirstChild(id)
	elseif category == "Base" then
		local f = assets and assets:FindFirstChild("BaseDesigns")
		source = f and f:FindFirstChild(id)
	end
	if not source then
		notice.Text = Strings.PreviewUnavailable
		return
	end
	modal = Instance.new("Frame")
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(17, 15, 29)
	modal.ZIndex = 20
	modal.Parent = panel
	local view = Instance.new("ViewportFrame")
	view.Size = UDim2.new(1, -32, 1, -100)
	view.Position = UDim2.fromOffset(16, 16)
	view.BackgroundColor3 = Color3.fromRGB(38, 33, 55)
	view.Ambient = Color3.fromRGB(210, 210, 220)
	view.LightColor = Color3.new(1, 1, 1)
	view.Parent = modal
	local world = Instance.new("WorldModel")
	world.Parent = view
	local clone = source:Clone()
	local model
	if clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		for _, child in clone:GetChildren() do
			child.Parent = model
		end
		clone:Destroy()
	end
	model.Parent = world
	AppearanceRules.Apply(model, finish or "Default", category, id)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		elseif part:IsA("LuaSourceContainer") then
			part:Destroy()
		end
	end
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(radius * 0.95, radius * 0.65, -radius * 1.25), cf.Position)
	camera.Parent = view
	view.CurrentCamera = camera
	local close = button(modal, Strings.ClosePreview, closeModal)
	close.Size = UDim2.new(1, -32, 0, 44)
	close.Position = UDim2.new(0, 16, 1, -60)
	GuiService.SelectedObject = close
end
local function riftTile(parent, vip, finishId)
	releaseRiftPreview()
	local presentation = require(script.Parent.Phase12PresentationController)
	if presentation.PrepareRiftPreview then
		local descriptor = nil
		if finishId == "FIN_SINGULARITY" then
			local definition = require(RS.Shared.Config.Phase13OptionalFinishes).Finishes.FIN_SINGULARITY
			descriptor = { PrimaryImage = definition.TextureAssetId }
		end
		riftPreview = presentation.PrepareRiftPreview(parent, { vip = vip == true, asset = descriptor, title = if descriptor then "Singularity DEV preview" else nil })
	else
		text(parent, Strings.RiftLoading)
	end
end
local function previewRift(finishId)
	closeModal()
	modal = Instance.new("Frame")
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(17, 15, 29)
	modal.ZIndex = 20
	modal.Parent = panel
	local owner = Instance.new("Frame")
	owner.Size = UDim2.new(1, -32, 1, -100)
	owner.Position = UDim2.fromOffset(16, 16)
	owner.BackgroundTransparency = 1
	owner.Parent = modal
	riftTile(owner, finishId ~= "FIN_SINGULARITY", finishId)
	local close = button(modal, Strings.ClosePreview, closeModal)
	close.Size = UDim2.new(1, -32, 0, 44)
	close.Position = UDim2.new(0, 16, 1, -60)
	GuiService.SelectedObject = close
end
local function track(result)
	notice.Text = message(result)
	if result.state == "Saving" then
		pending = result.operationId
		local id = pending
		local token = generation
		task.spawn(function()
			while started and pending == id and generation == token do
				task.wait(1)
				local status = call({ action = "Status", operationId = id })
				if status.state == "Confirmed" then
					pending = nil
					busy = false
					notice.Text = Strings.Saved
					refresh()
					render()
					return
				end
				notice.Text = Strings.Pending
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
local function rebirth(rewardId, route)
	if busy then
		return
	end
	local q = call({ action = "Quote", rewardId = rewardId, route = route })
	if not q.ok then
		if q.code == "INSUFFICIENT_CASH" then
			notice.Text = Strings.Format("NeedCashAmount", cash(math.max(0, (q.price or 0) - (q.totalCash or 0))))
		elseif q.code == "BASE_NOT_FULL" then
			notice.Text = Strings.Format("FillSlots", tostring(q.capacity))
		elseif q.code == "MISSING_QUALITY" then
			notice.Text = Strings.Format(
				"NeedQuality",
				tostring(math.max(0, (q.requiredIndividuals or 4) - (q.qualifyingIndividuals or 0))),
				tostring(q.minimumRarity)
			)
		else
			notice.Text = message(q)
		end
		return
	end
	local reward = if q.rewardKind == "Prestige"
		then Strings.Format("PrestigeTitle", tostring((q.prestigeCount or 0) + 1))
		elseif q.rewardKind == "Expansion"
		then Strings.Format(
			"SlotReward",
			tostring(
				(Config.ExpansionRows[math.max(1, table.find(Config.ExpansionCapacities, q.capacity) or 1)] or {}).capacity
					or "?"
			)
		)
		else Strings.DesignReward
	local body
	if route == "Cash" then
		body = Strings.Format("CashConfirmation", cash(q.totalCash), reward)
			.. "\n"
			.. Strings.CashBoundary
			.. "\n"
			.. Strings.PaidWarning
	else
		body = Strings.Format("CollectionConfirmation", tostring(q.ownedCount), cash(q.productionCps or q.baseCps))
	end
	if q.gemReward then
		body ..= "\n" .. Strings.Format(
			"RebirthRewards",
			tostring(q.gemReward),
			tostring(math.floor(((q.incomeBonusAfter or 0) - (q.incomeBonusBefore or 0)) * 100 + 0.5)),
			tostring(math.floor((q.incomeBonusAfter or 0) * 100 + 0.5))
		)
	end
	body ..= "\n" .. Strings.Preserve
	local lines = nil
	if require(RS.Shared.Config.CampReworkFlags).RebirthUi() then
		local function duration(seconds)
			if type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 then
				return "no time"
			end
			if seconds < 3600 then
				return string.format("%d min", math.max(1, math.floor(seconds / 60 + 0.5)))
			end
			return string.format("%.1f h", seconds / 3600)
		end
		local red, green = Color3.fromRGB(255, 92, 92), Color3.fromRGB(112, 230, 112)
		lines = {
			if route == "Cash"
				then { Strings.Format("YouLoseCash", "$" .. cash(q.lostCash or q.totalCash)), red }
				else { Strings.Format("YouLoseCollection", tostring(q.lostIndividuals or q.ownedCount)), red },
			{ Strings.Format("YouGet", reward, tostring(q.gemReward or 0)), green },
			if route == "Cash"
				then { Strings.Format("PaybackCash", duration(q.paybackSeconds)), Color3.fromRGB(235, 233, 247) }
				else { Strings.Format("PaybackCollection", tostring(q.lostIndividuals or q.ownedCount)), Color3.fromRGB(235, 233, 247) },
		}
	end
	displayConfirm(Strings.ConfirmRebirth, body, function()
		busy = true
		q.action = "Rebirth"
		q.operationId = Http:GenerateGUID(false)
		q.sequence = q.nextSequence
		track(call(q))
	end, lines)
end
local function card(title, detail)
	local frame = Instance.new("Frame")
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.new(1, -12, 0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(34, 30, 51)
	frame.BorderSizePixel = 0
	frame.Parent = content
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame
	text(frame, title, 20)
	text(frame, detail, 15)
	return frame
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
			if started and panel and panel.Visible and (current == "Passes" or current == "Cash") then
				render()
			end
		end)
	end
	return nil
end
render = function()
	releaseRiftPreview()
	if not snapshot or not content then
		return
	end
	for _, child in content:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	notice.Text = if pending
		then Strings.Pending
		else Strings.Format(
			"StatusLine",
			cash(snapshot.balance),
			cash(snapshot.economy and snapshot.economy.gems or 0),
			tostring(snapshot.capacity),
			tostring(snapshot.rebirthCount)
		)
	if current == "Weapon" then
		for _, row in Weapons.GetAll() do
			local owned = snapshot.ownedWeapons[row.id] == true
			local selected = snapshot.selectedWeapon == row.id
			local stats = row.stats
			local f = card(
				row.displayName,
				Strings.Format(
					"WeaponStats",
					row.family,
					tostring(stats.damage),
					tostring(stats.rangeStuds),
					tostring(stats.fireIntervalSeconds),
					if owned then Strings.Owned else Strings.Format("CashPrice", cash(row.price))
				)
			)
			button(f, Strings.Preview, function()
				preview("Weapon", row.id)
			end)
			button(
				f,
				if selected then Strings.Equipped elseif owned then Strings.EquipWeapon else Strings.BuyWeapon,
				function()
					if not selected then
						mutate(if owned then "Select" else Strings.Purchase, "Weapon", row.id)
					end
				end
			)
		end
		-- Camp Rework specials: off the tier ladder, never sellable.
		if type(snapshot.specials) == "table" then
			card("Special weapons", "Premium (Gems or Robux) and Won (milestones). Never sellable.")
			for _, row in snapshot.specials do
				local definition = Weapons.Get(row.id)
				local stats = definition and definition.stats
				local unlock = row.unlock or {}
				local how = if unlock.kind == "Gems" then string.format("%d Gems", unlock.gems or 0)
					elseif unlock.kind == "Pass" then string.format("%d R$ game pass", unlock.robux or 0)
					else string.format("%s %d / %d", if unlock.milestone == "SpeciesDiscovered" then "Species discovered"
						elseif unlock.milestone == "CleanEscapes" then "Clean escapes" else "Secret caught", row.progress or 0, row.target or 0)
				local f = card(
					row.name,
					string.format("%s · %s\nDamage %s · Range %s · %ss", row.source, how,
						tostring(stats and stats.damage or "?"), tostring(stats and stats.rangeStuds or "?"),
						tostring(stats and stats.fireIntervalSeconds or "?"))
				)
				button(f, Strings.Preview, function()
					preview("Weapon", row.id)
				end)
				if row.owned then
					local selected = snapshot.selectedWeapon == row.id
					button(f, if selected then Strings.Equipped else Strings.EquipWeapon, function()
						if not selected then
							mutate("Select", "Weapon", row.id)
						end
					end)
				elseif unlock.kind == "Gems" then
					button(f, string.format("Buy · %d Gems", unlock.gems or 0), function()
						if busy or pending then
							return
						end
						busy = true
						track(call({ action = "GemShop", itemId = unlock.itemId, operationId = Http:GenerateGUID(false) }))
					end)
				elseif unlock.kind == "Pass" then
					local b = button(f, "Robux purchases aren't open yet", function() end)
					b.Active = false
					b.AutoButtonColor = false
				end
			end
		end
	elseif current == "Training" then
		-- Camp Rework Training: cart speed comes from Training levels, trained on the stall rollers.
		local t = snapshot.training
		if type(t) ~= "table" then
			card("Training", Strings.Unavailable)
		else
			card(
				string.format("Training level %d / %d", t.level, t.maxLevel),
				string.format(
					"Cart speed +%d%%\n%s\nDrive your cart up the ramp onto the rollers and stay seated to train.",
					math.floor((t.speedMultiplier - 1) * 100 + 0.5),
					if t.level >= t.maxLevel then "Max level" else string.format("XP %d / %d", math.floor(t.xp), t.xpToNext)
				)
			)
			for _, roller in t.rollers do
				local f = card(roller.name, string.format("x%d Training XP%s", roller.multiplier, if roller.owned then "" else " · " .. cash(roller.price)))
				button(f, if roller.selected then "In use" elseif roller.owned then "Use" else "Buy · " .. cash(roller.price), function()
					if busy or pending or roller.selected then
						return
					end
					busy = true
					track(call({ action = "TrainingRoller", rollerId = roller.id, operationId = Http:GenerateGUID(false) }))
				end)
			end
			card("2x Training", if t.pass then "Owned · double Training XP" else "Robux pass · purchases aren't open yet")
		end
	elseif current == "Sell" then
		-- Camp Rework Sell counter: your carried brainrot, then Cash weapons and carts at 25% back.
		local rate = 0.25
		local f = card("Sell a brainrot", "Carry a brainrot to this counter, then sell it here.")
		button(f, "Sell carried brainrot", function()
			if busy or pending then
				return
			end
			local result = call({ action = "SellCarried" })
			if not result.ok then
				notice.Text = message(result)
			else
				setShopOpen(false)
			end
		end)
		local any = false
		local function sellRow(category, id, name, price, selected)
			any = true
			local refund = math.floor(price * rate)
			local row = card(name, string.format("%s back (25%%)%s", cash(refund), if selected then " · in use: switch first" else ""))
			local b = button(row, string.format("Sell for %s", cash(refund)), function()
				if busy or pending or selected then
					return
				end
				displayConfirm("Sell " .. name .. "?", string.format("You get %s Cash. This can't be undone.", cash(refund)), function()
					busy = true
					track(call({ action = "SellBack", category = category, id = id, operationId = Http:GenerateGUID(false) }))
				end)
			end)
			b.Active = not selected
			b.AutoButtonColor = not selected
		end
		for _, row in Weapons.GetAll() do
			if snapshot.ownedWeapons[row.id] == true and Weapons.IsSellable(row.id) then
				sellRow("Weapon", row.id, row.displayName, row.price, snapshot.selectedWeapon == row.id)
			end
		end
		for _, row in Config.CartRows do
			if snapshot.ownedCarts[row.id] == true and not row.starter and row.price > 0 then
				sellRow("Cart", row.id, row.displayName, row.price, snapshot.selectedCart == row.id)
			end
		end
		if not any then
			card("Nothing else to sell", "Starter, Robux, Gem and won items are never sold.")
		end
	elseif current == "Cart" then
		for _, row in Config.CartRows do
			local owned = snapshot.ownedCarts[row.id] == true
			local selected = snapshot.selectedCart == row.id
			local class = Config.Classes[row.classId]
			local f = card(
				row.displayName,
				Strings.Format(
					"CartStats",
					row.classId,
					tostring(class.speed),
					tostring(class.acceleration),
					tostring(class.braking),
					if owned then Strings.OwnedDock else Strings.Format("CashPrice", cash(row.price))
				)
			)
			button(f, if selected then Strings.InUse elseif owned then Strings.UseDock else Strings.BuyCart, function()
				if not selected then
					mutate(if owned then "Select" else Strings.Purchase, "Cart", row.id)
				end
			end)
			button(f, Strings.PreviewCart, function()
				preview("Cart", row.assetName)
			end)
		end
		if type(snapshot.training) == "table" then
			card(Strings.UpgradesTitle, string.format("Training level %d (speed +%d%%) · Cargo %d slots",
				snapshot.training.level, math.floor((snapshot.training.speedMultiplier - 1) * 100 + 0.5), 3 + snapshot.cargoLevel))
		else
			card(
				Strings.UpgradesTitle,
				Strings.Format("UpgradeStats", tostring(snapshot.speedLevel), tostring(3 + snapshot.cargoLevel))
			)
		end
	elseif current == "Base" then
		local riftCard = card(Strings.RiftPreview, Strings.RiftPreviewDetail)
		local riftOwner = Instance.new("Frame")
		riftOwner.Size = UDim2.new(1, 0, 0, 160)
		riftOwner.BackgroundTransparency = 1
		riftOwner.Parent = riftCard
		riftTile(riftOwner, false)
		for _, row in Config.ExpansionRows do
			if row.capacity > snapshot.capacity then
				local f = card(
					Strings.Format("SlotReward", tostring(row.capacity)),
					Strings.Format("ExpansionDetail", cash(row.price), row.minimumRarity)
				)
				button(f, Strings.CashRebirth, function()
					rebirth(row.id, "Cash")
				end)
				button(f, Strings.CollectionRebirth, function()
					rebirth(row.id, "Collection")
				end)
				break
			end
		end
		local prestige = snapshot.economy and snapshot.economy.prestige
		if snapshot.capacity >= Config.MaxSlots and prestige and prestige.price then
			local f = card(
				Strings.Format("PrestigeTitle", tostring(prestige.count + 1)),
				Strings.Format("PrestigeDetail", cash(prestige.price))
			)
			button(f, Strings.CashRebirth, function()
				rebirth("PRESTIGE", "Cash")
			end)
		end
		for _, row in Config.DesignRows do
			local owned = snapshot.ownedDesigns[row.id] == true
			local selected = snapshot.selectedDesign == row.id
			local f = card(
				row.displayName,
				if owned
					then "Owned · works at every capacity"
					else Strings.Format("DesignDetail", cash(row.price), row.minimumRarity)
			)
			button(f, Strings.Preview, function()
				preview("Base", row.id)
			end)
			if owned then
				button(f, if selected then Strings.InUse else Strings.UseDesign, function()
					if not selected then
						mutate("Select", "Design", row.id)
					end
				end)
			else
				button(f, Strings.CashRebirth, function()
					rebirth(row.id, "Cash")
				end)
				button(f, Strings.CollectionRebirth, function()
					rebirth(row.id, "Collection")
				end)
			end
		end
	elseif current == "Settings" then
		if StudPopUI.enabled() then
			local holder = Instance.new("Frame")
			holder.Name = "AboutLogo"
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.new(1, -12, 0, 150)
			holder:SetAttribute("StudPopOwned", true)
			holder.Parent = content
			local logo = StudPopUI.StudPop.Logo(holder, UDim2.fromScale(1, 1), { peekImage = StudPopUI.portrait("BRT_019"), still = true }) -- still: no loops left running when the shop closes
			logo.Root.AnchorPoint = Vector2.new(0.5, 0)
			logo.Root.Position = UDim2.fromScale(0.5, 0)
		end
		card("Build / About", string.format("%s · place version %s", tostring(RS:GetAttribute("ReleaseBuildId") or "Loading"), tostring(RS:GetAttribute("ReleasePlaceVersion") or "Loading")))
		local f = card(Strings.AppearanceTitle, Strings.AppearanceDetail)
		for key, values in
			{
				VIPBadge = { "On", "Off" },
				VIPTitle = { "On", "Off" },
				VIPChat = { "On", "Off" },
				RiftVariant = { "Default", "Riftgold" },
				BaseFinish = { "Default", "Riftgold" },
				CartFinish = { "Default", "Riftgold", "Trailblazer" },
				WeaponFinish = { "Default", "Riftgold", "Trailblazer" },
				ReducedMotion = { "On", "Off" },
			}
		do
			local optional = ({ WeaponFinish = "FIN_PRISM", CartFinish = "FIN_GLACIER", BaseFinish = "FIN_AURORA", RiftVariant = "FIN_SINGULARITY" })[key]
			if optional and player:GetAttribute("Entitlement_" .. optional) == true then table.insert(values, optional) end
			for _, value in values do
				button(f, Strings.SettingsLabels[key] .. ": " .. value, function()
					if busy then
						return
					end
					busy = true
					if key == "ReducedMotion" then
						local name = require(RS.Shared.Constants.RemoteNames).VFXSettingsRequest
						local settings = RS.Remotes:FindFirstChild(name)
						local ok, result = pcall(function()
							return settings:InvokeServer({ action = "Set", ReducedMotion = value == "On" })
						end)
						busy = false
						notice.Text = if ok and result.ok then Strings.Saved else Strings.Unavailable
						return
					end
					track(
						call({ action = "Appearance", key = key, value = value, operationId = Http:GenerateGUID(false) })
					)
				end)
			end
		end
		local attachments = snapshot.attachmentCosmetics
		if type(attachments) == "table" and type(attachments.slots) == "table" then
			for _, slot in { "Flag", "BaseBanner", "Trail" } do
				local choice = attachments.slots[slot]
				if type(choice) == "table" then
					local title = ({
						Flag = "Chariot flag",
						BaseBanner = "Base banner",
						Trail = "Cart trail",
					})[slot]
					local display = card(title, "Optional appearance · no gameplay effects")
					if attachments.available == true then
						button(
							display,
							if choice.selected == "None" then "None (selected)" else "None",
							function()
								if busy or choice.selected == "None" then
									return
								end
								busy = true
								track(
									call({
										action = "Appearance",
										key = slot,
										value = "None",
										operationId = Http:GenerateGUID(false),
									})
								)
							end
						)
					else
						text(display, Strings.Unavailable, 15)
					end
					for _, row in choice.rows or {} do
						local ready = row.presentationReady == true
						local state = if row.selected
							then (if ready then "Equipped" else "Selected · Appearance unavailable")
							elseif row.owned then (if ready
								then "Owned"
								else "Owned · Appearance unavailable")
							else "Locked"
						if row.acquisition == "Paid" and not row.owned then
							state = "Unavailable"
						end
						local detail = (row.name or row.id)
							.. "\n"
							.. (row.acquisitionText or "")
							.. " · "
							.. state
						if row.acquisition == "Cash" and type(row.priceCash) == "number" then
							detail ..= "\n" .. cash(row.priceCash) .. " Cash"
						end
						text(display, detail, 15)
						if attachments.available == true and row.availableForPurchase == true then
							button(display, "Buy " .. row.name .. " · " .. cash(row.priceCash), function()
								if busy then return end
								busy=true
								track(call({action="CosmeticPurchase",id=row.id,operationId=Http:GenerateGUID(false)}))
							end)
						end
						if
							attachments.available == true
							and row.availableForSelection == true
							and ready
							and not row.selected
						then
							button(display, "Equip " .. row.name, function()
								if busy then
									return
								end
								busy = true
								track(
									call({
										action = "Appearance",
										key = slot,
										value = row.id,
										operationId = Http:GenerateGUID(false),
									})
								)
							end)
						end
					end
				end
			end
		end
	else
		local rows = if current == "Passes"
			then snapshot.commerce.Passes
			elseif current == "Cash" then snapshot.commerce.Cash
			else snapshot.commerce.Cosmetics
		if current == "Cash" then
			local eco = snapshot.economy
			if eco then
				local income = eco.income or {}
				local boostLeft = math.max(0, (player:GetAttribute("CashBoostUntil") or 0) - workspace:GetServerTimeNow())
				local function clock(seconds)
					seconds = math.max(0, math.floor(seconds))
					return if seconds >= 3600
						then string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
						else string.format("%d:%02d", seconds // 60, seconds % 60)
				end
				local head = card(
					Strings.Format("GemBalance", tostring(eco.gems)),
					Strings.Format(
						"IncomeLine",
						string.format("%.2f", income.total or 1):gsub("0+$", ""):gsub("%.$", ""),
						tostring(math.floor((income.rebirthBonus or 0) * 100 + 0.5)),
						if (income.vipBonus or 0) > 0 then Strings.IncomeVip else "",
						if (income.pass or 1) > 1 then Strings.IncomePass else "",
						if boostLeft > 0 then Strings.Format("IncomeBoost", clock(boostLeft)) else ""
					)
				)
				head:SetAttribute("StudPopHint", "card")
				if (snapshot.mutationStormSeconds or 0) > 0 then
					text(head, Strings.Format("StormActive", clock(snapshot.mutationStormSeconds)), 15)
				end
				card(Strings.GemShopTitle, "")
				local items = table.clone(eco.shop or {})
				table.sort(items, function(a, b)
					return (a.order or 0) < (b.order or 0)
				end)
				for _, item in items do
					local detail = item.description
					if item.cash then
						detail ..= "\n" .. Strings.Format("CrateValue", cash(item.cash))
					end
					local f = card(item.name, detail)
					local affordable = (eco.gems or 0) >= item.priceGems
					local b = button(
						f,
						if affordable
							then Strings.Format("GemPrice", tostring(item.priceGems))
							else Strings.Format("NeedGems", tostring(item.priceGems - (eco.gems or 0))),
						function()
							if busy or pending or (snapshot.economy and snapshot.economy.gems or 0) < item.priceGems then
								return
							end
							busy = true
							local result = call({ action = "GemShop", itemId = item.id, operationId = Http:GenerateGUID(false) })
							if item.kind == "CashCrate" and (result.ok or result.state == "Saving") then
								AudioCue.Play(if item.id == "CASH_CRATE_L" then "E5_vault" else "E5_crate", { bus = "Rewards" })
							end
							track(result)
						end
					)
					b:SetAttribute("StudPopHint", if affordable then "gem" else "locked")
					b.Active = affordable
					b.AutoButtonColor = affordable
				end
			end
			card(Strings.GemPacksTitle, Strings.GemPacksDetail .. "\n" .. (snapshot.commerce.stormDisclosure or ""))
		end
		for _, row in rows or {} do
			local price = regionalPrice(row)
			local available = row.enabled == true and price ~= nil
			local label = row.name
			if row.currency == "Gems" and row.bonusPercent then
				label ..= "  +" .. tostring(row.bonusPercent) .. "%" .. (if row.bestValue then " BEST VALUE" else "")
			end
			local f = card(
				label,
				((row.description or "") .. (if row.enabled then "" else "\n" .. (row.reason or Strings.Unavailable)))
					.. "\n"
					.. (if price ~= nil then tostring(price) .. " Robux" else Strings.PriceUnavailable)
			)
			if row.id == "VIP" then
				text(f, Strings.VIPIdentityPreview)
				button(f, Strings.PreviewVIPBase, function()
					preview("Base", snapshot.selectedDesign, "Riftgold")
				end)
				button(f, Strings.PreviewVIPCart, function()
					for _, cart in Config.CartRows do
						if cart.id == snapshot.selectedCart then
							preview("Cart", cart.assetName, "Riftgold")
							break
						end
					end
				end)
				button(f, Strings.PreviewVIPWeapon, function()
					preview("Weapon", snapshot.selectedWeapon, "Riftgold")
				end)
				button(f, Strings.PreviewVIPRift, previewRift)
			end
			-- Preview-only in the exact DEV Studio target; never grants/persists an entitlement.
			local finishDefinition = require(RS.Shared.Config.Phase13OptionalFinishes).Finishes[row.id]
			if finishDefinition and game:GetService("RunService"):IsStudio() and game.PlaceId == 91958083796436 and game.GameId == 10548905405 then
				button(f, "DEV preview (sales disabled)", function()
					if finishDefinition.Category == "Weapon" then preview("Weapon", snapshot.selectedWeapon, row.id)
					elseif finishDefinition.Category == "Base" then preview("Base", snapshot.selectedDesign, row.id)
					elseif finishDefinition.Category == "Cart" then
						for _, cart in Config.CartRows do if cart.id == snapshot.selectedCart then preview("Cart", cart.assetName, row.id); break end end
					else previewRift(row.id) end
				end)
			end
			if row.id == "STARTER_PACK" then
				button(f, Strings.PreviewStarterCart, function()
					preview("Cart", "ScrapChariot", "Trailblazer")
				end)
				button(f, Strings.PreviewStarterWeapon, function()
					preview("Weapon", "HRP_001", "Trailblazer")
				end)
			end
			local b = button(
				f,
				if row.owned then Strings.Owned elseif available then Strings.Purchase else Strings.Unavailable,
				function()
					if busy or pending or not available or row.owned then
						return
					end
					busy = true
					local result = call({ action = "Prompt", offerId = row.id })
					busy = false
					notice.Text = if result.ok then Strings.PromptInstruction else message(result)
				end
			)
			b.Active = available and not row.owned
			b.AutoButtonColor = b.Active
			if StudPopUI.enabled() and available and not row.owned then
				b.Text = ROBUX_GLYPH .. " " .. tostring(price)
				b:SetAttribute("StudPopHint", "robux")
			end
		end
	end
end
local function open(category)
	current = category
	generation += 1
	openRequests:Run(player.Character, function()
		return call({ action = "Snapshot" })
	end, function(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return started and panel ~= nil and panel.Parent ~= nil
			and player.Character == character and humanoid ~= nil and humanoid.Health > 0
			and player:GetAttribute("Phase13CinematicActive") ~= true
	end, function(result)
		if not setShopOpen(true) then return false end
		if result.ok then snapshot = result end
		render()
		if category == "Passes" or category == "Cash" then
			AudioCue.Play("U8", { bus = "UI", cooldown = 1 })
			task.spawn(function()
				call({ action = "OfferView", group = category })
			end)
		end
		return true
	end)
end
-- Reuses the existing appearance panel, profile snapshot and focus flow.
function Controller.OpenAppearance(_cosmeticId)
 if not started then return false end
 open("Settings")
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
	gui = Instance.new("ScreenGui")
	gui.Name = "Phase13Shop"
	gui.DisplayOrder = 70
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	local hud = button(gui, Strings.Shop, function()
		open("Passes")
	end)
	hud.Size = UDim2.fromOffset(96, 44)
	hud.Position = UDim2.new(1, -112, 0, 16)
	panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.88, 0.84)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(20, 17, 34)
	panel.Visible = false
	panel.Parent = gui
	local constraints = Instance.new("UISizeConstraint")
	constraints.MaxSize = Vector2.new(960, 760)
	constraints.MinSize = Vector2.new(300, 260)
	constraints.Parent = panel
	panelConstraints = constraints
	headerTitle = text(panel, "EXPEDITION", 22)
	headerTitle:SetAttribute("StudPopHint", "title")
	headerTitle.Position = UDim2.fromOffset(18, 14)
	local close = button(panel, Strings.Close, function()
		setShopOpen(false)
	end)
	close.Size = UDim2.fromOffset(84, 44)
	close.Position = UDim2.new(1, -100, 0, 8)
	local tabs = Instance.new("ScrollingFrame")
	tabs.Size = UDim2.new(1, -32, 0, 50)
	tabs.Position = UDim2.fromOffset(16, 60)
	tabs.BackgroundTransparency = 1
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.CanvasSize = UDim2.new()
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.ScrollBarThickness = 3
	tabs.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.Parent = tabs
	for _, category in { "Passes", "Cash", "Cosmetics", "Weapon", "Cart", "Base", "Settings" } do
		local b = button(tabs, Strings.Tabs[category] or category, function()
			if category ~= current and category ~= "Passes" and category ~= "Cash" then
				AudioCue.Play("U4", { bus = "UI" })
			end
			open(category)
		end)
		b.Size = UDim2.fromOffset(106, 44)
	end
	notice = text(panel, "", 15)
	notice.Position = UDim2.fromOffset(18, 120)
	notice.Size = UDim2.new(1, -36, 0, 48)
	notice.AutomaticSize = Enum.AutomaticSize.None
	content = Instance.new("ScrollingFrame")
	content.Position = UDim2.fromOffset(16, 174)
	content.Size = UDim2.new(1, -32, 1, -190)
	content.BackgroundTransparency = 1
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.Parent = content
	table.insert(
		connections,
		update.OnClientEvent:Connect(function(payload)
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
				if panel.Visible then
					render()
				end
			end
		end)
	)
	table.insert(
		connections,
		UIS.InputBegan:Connect(function(input, processed)
			if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
				setShopOpen(false)
			end
		end)
	)
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateShopLayout))
	table.insert(connections, gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateShopLayout))
	table.insert(connections, playerGui.DescendantAdded:Connect(function(child)
		if child.Name == "CycleCountdown" and child:IsA("GuiObject") and child.Parent
			and child.Parent.Name == "Phase12CriticalWarnings" then bindWarningClock(child) end
	end))
	local warnings = playerGui:FindFirstChild("Phase12CriticalWarnings")
	local clock = warnings and warnings:FindFirstChild("CycleCountdown")
	if clock and clock:IsA("GuiObject") then bindWarningClock(clock) end
	table.insert(connections, player:GetAttributeChangedSignal("Phase13CinematicActive"):Connect(function()
		if player:GetAttribute("Phase13CinematicActive") == true then
			setShopOpen(false)
		else
			-- Native fallback selection can change while the cinematic owns input.
			-- Clear only this closed shop's focus; Daze retains its own lock.
			shopFocus:RestoreClosed()
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
	updateShopLayout()
	if StudPopUI.enabled() then
		-- The Stud Pop HUD rail opens the shop; the legacy opener stays built for flag-off.
		hud.Visible = false
		StudPopUI.skin(gui)
	end
	return true
end
-- Stud Pop HUD rail / Settings entry: the same open path as the legacy Shop button and prompts.
function Controller.OpenFromHud(category)
	if not started then
		return false
	end
	open(category or "Passes")
	return true
end
function Controller.Stop()
	setShopOpen(false)
	shopFocus:Forget()
	started = false
	disconnectScoped(clockConnections)
	disconnectScoped(characterConnections)
	warningClock, watchedCharacter = nil, nil
	table.clear(priceRequests)
	table.clear(regionalPrices)
	generation += 1
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
	end
	gui, panel, panelConstraints, headerTitle = nil, nil, nil, nil
	snapshot = nil
	closeModal()
end
return Controller
