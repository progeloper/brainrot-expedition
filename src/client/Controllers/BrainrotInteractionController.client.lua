--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RemoteNames = require(ReplicatedStorage:WaitForChild("Shared").Constants.RemoteNames)
local Exact = require(ReplicatedStorage.Shared.Config.PlaytestExact)
local Selector = require(ReplicatedStorage.Shared.Utility.ExactInteractionSelector).new()
local Hud = require(script.Parent.ExactHudController)
local NativePending = nil
local NativeConnections = {}
local function revisionFor(id)
	for _, row in ipairs(require(script.Parent.CreaturePresentationController).GetSnapshot()) do
		if row.id == id then
			return row.revision
		end
	end
	return nil
end
local PrimaryHighlight = nil
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Config = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)
local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)
local State = require(script.Parent.Parent.Utility.BrainrotInteractionState)
local InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)
local Visibility = require(script.Parent.RegionVisibilityController)
local SlotPresentation = require(ReplicatedStorage.Shared.Utility.BaseSlotPresentation)
local Feedback = require(script.Parent.Parent.Utility.Phase10Feedback)
local RemoteBinding = require(script.Parent.Parent.Utility.RemoteDependencyBinding)
local requests: { [string]: RemoteEvent } = {}
local requestBindings = {}
local requestNames = {
	Drop = RemoteNames.DropCarriedRequest,
	Base = RemoteNames.PlaceCarriedRequest,
	Cargo = RemoteNames.LoadCarriedRequest,
	Pickup = RemoteNames.PickupCargoRequest,
	Replace = RemoteNames.ReplaceCargoRequest,
}
local CombatStrings = require(ReplicatedStorage.Shared.Config.Phase13CombatStrings)
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local PROMPT_TAG, PLATFORM_TAG, CARGO_SLOT_TAG = "BrainrotWorldPickup", "BrainrotStoragePlatform", "BrainrotCargoSlot"
local DROP_ACTION = "BrainrotDropCarried"
local state = State.new(HttpService:GenerateGUID(false))
local entries: { [BasePart]: any } = {}
local drivePrompts = {}
local worldPrompts: { [ProximityPrompt]: boolean } = {}
local mutedPrompts: { [ProximityPrompt]: boolean } = {}
local SHOP_PROMPT_TAG = "Phase13ShopInteraction"
local shopPrompts: { [ProximityPrompt]: boolean } = {}
local mutedShopPrompts: { [ProximityPrompt]: boolean } = {}
local shopPromptCount = 0
local carts: { [Model]: any } = {}
local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local humanoidConnections: { RBXScriptConnection } = {}
local rootConnection: RBXScriptConnection? = nil
local boundCharacter: Model? = nil
local selected: any = nil
local activePrimary = false
local diagnosticEntry: any = nil
local holdIntent: any = nil
local dropBound, destroyed, refreshQueued = false, false, false
local lastTrace = ""
local promptSerial = 0
local feedbackUntil = 0
local refreshContext: () -> ()

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "BrainrotCarryFeedback", false
local label = Instance.new("TextLabel")
label.AnchorPoint, label.Position = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -90)
label.Size, label.BackgroundTransparency = UDim2.fromOffset(460, 52), 0.3
label.TextWrapped = true
label.BackgroundColor3, label.TextColor3 = Color3.fromRGB(30, 36, 42), Color3.fromRGB(220, 245, 255)
label.TextSize, label.Font = 16, Enum.Font.Gotham
label.Text, label.Visible, label.Parent = "", false, gui
gui.Parent = player:WaitForChild("PlayerGui")
gui.Enabled = false -- superseded feedback/custom slot renderer
Hud.Start()
table.insert(
	connections,
	Feedback.GetEvent().Event:Connect(function(message: string)
		Hud.Feedback(message)
		label.Text, label.Visible, feedbackUntil = message, false, os.clock() + Exact.Interaction.RequestTimeout
	end)
)

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function queueRefresh()
	if destroyed or refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		if not destroyed then
			refreshContext()
		end
	end)
end

local function trace(event: string)
	if not RunService:IsStudio() or ReplicatedStorage:GetAttribute("HuntingAimTrace") ~= true then
		return
	end
	local entry = if selected then selected.Entry else diagnosticEntry
	local prompt = if entry then entry.Prompt else nil
	local pending = state.Pending
	local cart = entry and entry.Cart
	local capacity = cart and cart:GetAttribute("CargoCapacity")
	local revision = cart and cart:GetAttribute("CargoRevision")
	local slotSummary = {}
	local map = if cart and type(capacity) == "number" then CartAssetValidator.GetCargoSlotMap(cart, capacity) else nil
	for _, slot in map or {} do
		table.insert(
			slotSummary,
			slot.Id .. "=" .. tostring(slot.Part:GetAttribute("CargoItemId")) .. "@" .. slot.Attachment:GetFullName()
		)
	end
	local key = table.concat({
		event,
		tostring(revision),
		tostring(selected and selected.Action),
		tostring(if entry then entry.Serial else nil),
		tostring(prompt and prompt.Enabled),
		tostring(entry and entry.Shown),
		tostring(holdIntent ~= nil),
		tostring(player:GetAttribute("CarriedItemId")),
		tostring(entry and entry.Target:GetAttribute("CargoItemId")),
		tostring(entry and entry.LOS),
		tostring(selected and selected.Target),
		tostring(pending and pending.Token),
	}, "|")
	if key == lastTrace then
		return
	end
	lastTrace = key
	print(
		string.format(
			"[CartInteraction] capacity=%s revision=%s slots=%s action=%s selection=eligible-pointer/current/nearest",
			tostring(capacity),
			tostring(revision),
			table.concat(slotSummary, ";"),
			tostring(selected and selected.Action)
		)
	)
	print(
		string.format(
			"[CartInteraction] state=%s cart=%s slot=%s prompt=%s serial=%s parent=%s enabled=%s shown=%s holding=%s carry=%s occupant=%s distance=%s selected=%s LOS=%s pending=%s busy=%s",
			event,
			if entry and entry.Cart then entry.Cart:GetFullName() else "none",
			tostring(entry and entry.Target:GetAttribute("CargoSlotId")),
			tostring(prompt),
			tostring(entry and entry.Serial),
			if prompt and prompt.Parent then prompt.Parent:GetFullName() else "none",
			tostring(prompt and prompt.Enabled),
			tostring(entry and entry.Shown),
			tostring(holdIntent ~= nil),
			tostring(player:GetAttribute("CarriedItemId")),
			tostring(entry and entry.Target:GetAttribute("CargoItemId")),
			if entry and entry.Distance then string.format("%.2f", entry.Distance) else "none",
			if selected then selected.Target:GetFullName() else "none",
			tostring(entry and entry.LOS),
			tostring(pending and pending.Token),
			tostring(pending ~= nil)
		)
	)
end

local function finish(token: string, message: string?): boolean
	if not state:Finish(token) then
		return false
	end
	if message then
		Hud.Feedback(message)
		label.Text, label.Visible = message, false
		feedbackUntil = os.clock() + 2
	end
	trace("finished")
	queueRefresh()
	return true
end

local function cancelContext()
	activePrimary = false
	holdIntent = nil
	if state.Pending then
		finish(state.Pending.Token, nil)
	end
	queueRefresh()
end

local function begin(kind: string, id: string, target: Instance?): any?
	if not requests[kind] then
		Feedback.Show("Transfer unavailable · " .. tostring(requestNames[kind] or kind))
		return nil
	end
	if InputPolicy.IsBlocked(player, GuiService, UserInputService) or NativePending then
		return nil
	end
	local request = state:Begin(kind, id, target, boundCharacter, player:GetAttribute("CarriedItemId"), os.clock())
	if request then
		request.Cart = selected and selected.Cart
		request.StateRevision = revisionFor(id)
		request.SpeciesId = player:GetAttribute("CarriedBrainrotId")
		if selected and selected.Target then
			request.SpeciesId = request.SpeciesId
				or selected.Target:GetAttribute("CargoBrainrotId")
				or selected.Target:GetAttribute("StorageBrainrotId")
		end
		if not request.SpeciesId and boundCharacter then
			local carried = boundCharacter:FindFirstChild("CarriedBrainrot")
			request.SpeciesId = carried and carried:GetAttribute("BrainrotId")
		end
		request.Occupant = if selected and selected.Target == target then selected.Occupant else nil
		label.Visible = true
		task.delay(Config.REQUEST_TIMEOUT, function()
			if not destroyed then
				finish(request.Token, "No response")
			end
		end)
	end
	return request
end

local function oldName(target: BasePart): string
	local species = target:GetAttribute("CargoBrainrotId")
	local definition = Catalog.GetDefinition(species)
	return if definition then definition.displayName else tostring(species or "Brainrot")
end

local comparisonGui: ScreenGui? = nil
local comparisonGeneration = 0
local function closeComparison()
	comparisonGeneration += 1
	if comparisonGui then
		comparisonGui:Destroy()
		comparisonGui = nil
	end
	player:SetAttribute("Phase13CompareDialogOpen", nil)
	queueRefresh()
end
local function openComparison(context: any)
	if comparisonGui then
		return
	end
	comparisonGeneration += 1
	local ownerGeneration = comparisonGeneration
	player:SetAttribute("Phase13CompareDialogOpen", true)
	local screen = Instance.new("ScreenGui")
	screen.Name = "Phase13PlatformComparison"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 85
	comparisonGui = screen
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.Parent = screen
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0, 420)
	panel.BackgroundColor3 = Color3.fromRGB(24, 30, 42)
	panel.Parent = shade
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 420)
	limit.Parent = panel
	local function text(name, value, pos, size)
		local node = Instance.new("TextLabel")
		node.Name = name
		node.Text = value
		node.Position = pos
		node.Size = size
		node.BackgroundTransparency = 1
		node.TextColor3 = Color3.fromRGB(235, 244, 255)
		node.Font = Enum.Font.Gotham
		node.TextSize = 15
		node.TextWrapped = true
		node.TextYAlignment = Enum.TextYAlignment.Top
		node.Parent = panel
		return node
	end
	text("Title", CombatStrings.Compare, UDim2.fromOffset(12, 12), UDim2.new(1, -24, 0, 28)).TextSize = 22
	local left = text("Current", CombatStrings.LoadingCurrent, UDim2.fromOffset(12, 58), UDim2.new(0.5, -20, 0, 225))
	local right = text("Incoming", CombatStrings.LoadingIncoming, UDim2.new(0.5, 8, 0, 58), UDim2.new(0.5, -20, 0, 225))
	local status = text("Status", CombatStrings.Checking, UDim2.fromOffset(12, 284), UDim2.new(1, -24, 0, 60))
	local function button(value, x, width)
		local node = Instance.new("TextButton")
		node.Text = value
		node.Position = UDim2.new(x, 8, 1, -64)
		node.Size = UDim2.new(width, -16, 0, 48)
		node.Font = Enum.Font.GothamBold
		node.TextSize = 15
		node.TextWrapped = true
		node.TextColor3 = Color3.new(1, 1, 1)
		node.BackgroundColor3 = Color3.fromRGB(45, 82, 110)
		node.Selectable = true
		node.Parent = panel
		return node
	end
	local cancel = button(CombatStrings.Cancel, 0, 0.25)
	local swap = button(CombatStrings.Swap, 0.25, 0.32)
	local sell = button(CombatStrings.SellReplace, 0.57, 0.43)
	swap.Active = false
	sell.Active = false
	cancel.Activated:Connect(closeComparison)
	screen.Parent = player:WaitForChild("PlayerGui")
	GuiService.SelectedObject = cancel
	local operationId = HttpService:GenerateGUID(false)
	task.spawn(function()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild("Phase13PlatformCompare")
		if not remote or not remote:IsA("RemoteFunction") then
			status.Text = CombatStrings.CompareUnavailable
			return
		end
		local ok, preview = pcall(remote.InvokeServer, remote, "Preview", context.Target, context.CarryId)
		if comparisonGeneration ~= ownerGeneration then
			return
		end
		if not ok or type(preview) ~= "table" or preview.ok ~= true then
			status.Text = CombatStrings.CompareChanged
			return
		end
		local function describe(title, item)
			return string.format(
				CombatStrings.Description,
				title,
				item.name,
				item.rarity,
				item.mutation,
				CurrencyFormatter.FormatCompactCash(item.productionCashPerSecond),
				CurrencyFormatter.FormatCompactCash(item.cashPerSecond),
				tostring(item.effect),
				tostring(item.effectValue),
				CurrencyFormatter.FormatCompactCash(item.sellValue),
				if item.equipped then CombatStrings.EquippedWarning else CombatStrings.NotEquipped
			)
		end
		left.Text = describe(CombatStrings.Current, preview.current)
		right.Text = describe(CombatStrings.Incoming, preview.incoming)
		status.Text = string.format(
			CombatStrings.IncomeChange,
			(if preview.incomeChange >= 0 then "+" else "−")
				.. CurrencyFormatter.FormatCompactCash(math.abs(preview.incomeChange))
		)
		swap.Active = true
		sell.Active = true
		local submitting = false
		local function commit(action)
			if submitting or comparisonGeneration ~= ownerGeneration then
				return
			end
			submitting = true
			swap.Active = false
			sell.Active = false
			status.Text = CombatStrings.SavingSwap
			task.spawn(function()
				local sent, result = pcall(remote.InvokeServer, remote, "Commit", preview.token, action, operationId)
				while
					comparisonGeneration == ownerGeneration
					and (not sent or (type(result) == "table" and result.ok == true and result.state == "Saving"))
				do
					task.wait(0.5)
					sent, result = pcall(remote.InvokeServer, remote, "Status", operationId)
				end
				if comparisonGeneration ~= ownerGeneration then
					return
				end
				if sent and type(result) == "table" and result.ok == true and result.state == "Confirmed" then
					closeComparison()
					Feedback.Show(CombatStrings.PlatformSaved)
				else
					status.Text = CombatStrings.SwapUnavailable
				end
			end)
		end
		swap.Activated:Connect(function()
			commit("Swap")
		end)
		sell.Activated:Connect(function()
			commit("SellAndReplace")
		end)
	end)
end
local function trigger(entry: any)
	local intent = holdIntent
	refreshContext() -- Re-read source and exact slot before sending any intent.
	local context = selected
	if comparisonGui or state.Pending or not context or context.Entry ~= entry or not entry.Prompt.Enabled then
		return
	end
	if context.Action == "Compare" then
		openComparison(context)
		return
	end
	if context.Action == "Replace" then
		if
			not intent
			or holdIntent ~= intent
			or intent.Entry ~= entry
			or intent.CarryId ~= context.CarryId
			or intent.Occupant ~= context.Occupant
			or os.clock() - intent.BeganAt < 0.55
		then
			return
		end
	end
	holdIntent = nil
	local id = State.RequestItemId(context)
	if type(id) ~= "string" then
		return
	end
	local request = begin(context.Action, id, context.Target)
	if not request then
		return
	end
	label.Text = if State.IsPickup(context)
		then "Picking up…"
		elseif context.Action == "Replace" then "Replacing " .. oldName(context.Target) .. "…"
		elseif context.Action == "Cargo" then "Loading…"
		else "Placing…"
	trace("triggered")
	if context.Action == "Base" then
		requests.Base:FireServer(context.Target, id, request.Token, request.StateRevision)
	elseif context.Action == "Replace" then
		requests.Replace:FireServer(
			context.Cart,
			context.SlotId,
			context.Occupant,
			id,
			request.Token,
			request.StateRevision
		)
	else
		requests[context.Action]:FireServer(context.Cart, context.SlotId, id, request.Token, request.StateRevision)
	end
	refreshContext()
end

local function hold(entry: any, began: boolean)
	if began then
		refreshContext()
		if selected and selected.Entry == entry and selected.Action == "Replace" and not state.Pending then
			holdIntent = {
				Entry = entry,
				CarryId = selected.CarryId,
				Occupant = selected.Occupant,
				BeganAt = os.clock(),
			}
			label.Text = oldName(entry.Target) .. " will be released awake · hold to replace"
			trace("hold-began")
		end
	else
		local ended = holdIntent
		-- Native hold-end can accompany Triggered; only Triggered mutates. Defer
		-- cancellation so a completed hold can consume its exact intent once.
		task.defer(function()
			if ended and holdIntent == ended then
				holdIntent = nil
				trace("hold-cancelled")
				queueRefresh()
			end
		end)
	end
end

local function shown(entry: any, visible: boolean)
	-- Presentation only: never disable/destroy a reusable prompt in PromptHidden.
	if not visible and holdIntent and holdIntent.Entry == entry then
		hold(entry, false)
	end
	trace(if visible then "shown" else "hidden")
end

local function canRestoreShopPrompt(prompt: ProximityPrompt): boolean
	return Visibility.IsVisible(prompt) and SlotPresentation.IsActive(prompt) ~= false
end

local function restoreMuted()
	for prompt in mutedPrompts do
		if prompt.Parent and prompt.Enabled == false then
			prompt.Enabled = true
		end
	end
	table.clear(mutedPrompts)
	activePrimary = false
	state:ClearShopPriorityKeys()
	State.UpdateShopPromptPriority(shopPrompts, mutedShopPrompts, false, canRestoreShopPrompt)
	table.clear(shopPrompts)
	shopPromptCount = 0
end

local function watchCart(cart: Model)
	if carts[cart] then
		carts[cart].Count += 1
		return
	end
	local record = { Count = 1, Prompts = {}, Connections = {} }
	carts[cart] = record
	local function add(instance: Instance)
		if instance:IsA("ProximityPrompt") and instance.Name ~= "PlaceCarriedBrainrot" then
			record.Prompts[instance] = true
		end
	end
	for _, descendant in cart:GetDescendants() do
		add(descendant)
	end
	table.insert(record.Connections, cart.DescendantAdded:Connect(add))
	table.insert(
		record.Connections,
		cart.DescendantRemoving:Connect(function(instance)
			record.Prompts[instance] = nil
			if instance:IsA("ProximityPrompt") then
				mutedPrompts[instance] = nil
			end
		end)
	)
	table.insert(record.Connections, cart.AttributeChanged:Connect(queueRefresh))
end

local function removeTarget(target: BasePart)
	local entry = entries[target]
	if not entry then
		return
	end
	entries[target] = nil
	if selected and selected.Target == target then
		selected = nil
		holdIntent = nil
	end
	if state.Pending and state.Pending.Target == target then
		finish(state.Pending.Token, nil)
	end
	disconnectAll(entry.Connections)
	State.RemovePrompt(entry)
	if entry.Cart and carts[entry.Cart] then
		local record = carts[entry.Cart]
		record.Count -= 1
		if record.Count == 0 then
			for prompt in record.Prompts do
				if mutedPrompts[prompt] and prompt.Parent and not prompt.Enabled then
					prompt.Enabled = true
				end
				mutedPrompts[prompt] = nil
			end
			disconnectAll(record.Connections)
			carts[entry.Cart] = nil
		end
	end
	queueRefresh()
end

local function addTarget(instance: Instance, kind: string)
	if not instance:IsA("BasePart") or entries[instance] then
		return
	end
	local folder = instance.Parent
	local cart = if kind == "Cargo" and folder then folder.Parent else nil
	if cart and not cart:IsA("Model") then
		cart = nil
	end
	local entry = { Target = instance, Kind = kind, Cart = cart, Connections = {} }
	entries[instance] = entry
	if cart then
		watchCart(cart)
	end
	table.insert(entry.Connections, instance.AttributeChanged:Connect(queueRefresh))
	table.insert(entry.Connections, instance:GetPropertyChangedSignal("CFrame"):Connect(queueRefresh))
	table.insert(entry.Connections, instance.ChildAdded:Connect(queueRefresh))
	table.insert(entry.Connections, instance.ChildRemoved:Connect(queueRefresh))
	table.insert(
		entry.Connections,
		instance.AncestryChanged:Connect(function()
			if not instance:IsDescendantOf(workspace) then
				removeTarget(instance)
			else
				queueRefresh()
			end
		end)
	)
	table.insert(
		entry.Connections,
		instance.Destroying:Connect(function()
			removeTarget(instance)
		end)
	)
	queueRefresh()
end

local function requestDrop(_: string, input: Enum.UserInputState): Enum.ContextActionResult
	if InputPolicy.IsBlocked(player, GuiService, UserInputService) then
		return Enum.ContextActionResult.Pass
	end
	if input == Enum.UserInputState.Begin and not state.Pending then
		local id = player:GetAttribute("CarriedItemId")
		if type(id) == "string" then
			local request = begin("Drop", id, nil)
			if request then
				holdIntent = nil
				label.Text = "Dropping…"
				requests.Drop:FireServer(id, request.Token, request.StateRevision)
				refreshContext()
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

refreshContext = function()
	activePrimary = false
	if destroyed then
		return
	end
	local character = if player.Character == boundCharacter then boundCharacter else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local alive = humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart")
	local driving = humanoid ~= nil
		and humanoid.Sit
		and humanoid.SeatPart ~= nil
		and humanoid.SeatPart.Name == "DriverSeat"
	local suspended = InputPolicy.IsBlocked(player, GuiService, UserInputService)
	local carryId = player:GetAttribute("CarriedItemId")
	local carrying = type(carryId) == "string"
	local pending = state.Pending
	if
		pending
		and (
			not alive
			or driving
			or suspended
			or pending.Character ~= character
			or pending.CarryId ~= carryId
			or (pending.Target and not pending.Target:IsDescendantOf(workspace))
		)
	then
		finish(pending.Token, nil)
	end
	local candidates = {}
	local slotMaps, cartFull = {}, {}
	for cart in carts do
		local capacity = cart:GetAttribute("CargoCapacity")
		local map = if type(capacity) == "number" then CartAssetValidator.GetCargoSlotMap(cart, capacity) else nil
		if map then
			local full = true
			local slots = {}
			for _, slot in map do
				slots[slot.Part] = slot
				if
					slot.Part:GetAttribute("CargoOccupied") ~= true
					or type(slot.Part:GetAttribute("CargoItemId")) ~= "string"
				then
					full = false
				end
			end
			slotMaps[cart], cartFull[cart] = slots, full
		end
	end
	diagnosticEntry = nil
	local _preferred: Instance? = nil
	for target, entry in entries do
		local marker = target:FindFirstChild(if entry.Kind == "Cargo" then "CargoAttachment" else "BrainrotPlacement")
		local markerValid = marker and (marker:IsA("Attachment") or marker:IsA("BasePart"))
		if markerValid and target:IsDescendantOf(workspace) then
			if entry.Marker ~= marker or not entry.Prompt or entry.Prompt.Parent ~= marker then
				entry.Marker = marker
				promptSerial += 1
				entry.Serial = promptSerial
				State.EnsurePrompt(entry, trigger, hold, shown)
			end
		else
			State.RemovePrompt(entry)
			continue
		end
		if not alive or driving or suspended or NativePending or not requests.Base then
			continue
		end
		local position = if marker:IsA("Attachment") then marker.WorldPosition else (marker :: BasePart).Position
		local distance = ((root :: BasePart).Position - position).Magnitude
		entry.Distance, entry.LOS = distance, "not eligible"
		if entry.Kind == "Cargo" and (not diagnosticEntry or distance < diagnosticEntry.Distance) then
			diagnosticEntry = entry
		end
		if
			distance > math.min(Exact.Interaction.Range, Config.PLACEMENT_INTERACT_RADIUS)
			or not Visibility.IsVisible(target)
		then
			continue
		end
		local cart = entry.Cart
		local occupant, slotId, action = nil, nil, nil
		if entry.Kind == "Cargo" then
			local slot = if cart and slotMaps[cart] then slotMaps[cart][target] else nil
			local removalOnly = target:GetAttribute("CargoRemovalOnly") == true
			slotId = if slot then slot.Id elseif removalOnly then target:GetAttribute("CargoSlotId") else nil
			local occupied = target:GetAttribute("CargoOccupied")
			occupant = target:GetAttribute("CargoItemId")
			if
				not cart
				or target.Parent ~= cart:FindFirstChild("CargoSlots")
				or not cart:IsDescendantOf(workspace)
				or cart:GetAttribute("RuntimeCart") ~= true
				or cart:GetAttribute("OwnerUserId") ~= player.UserId
				or type(slotId) ~= "string"
				or distance > Config.PLACEMENT_INTERACT_RADIUS
				or occupied == nil
				or (occupied == true and type(occupant) ~= "string")
			then
				continue
			end
			action = if removalOnly
				then if not carrying and occupied == true then "Pickup" else nil
				else State.CargoAction(carrying, occupied == true, cartFull[cart] == true)
			if not action or action == "Replace" then
				continue
			end
			entry.LOS = true
			local pointed = mouse.Target
			if pointed then
				if pointed == target or pointed:IsDescendantOf(target) then
					_preferred = target
				end
				local visual = pointed:FindFirstAncestorOfClass("Model")
				if
					visual
					and visual.Parent == cart:FindFirstChild("CargoVisuals")
					and "Slot" .. tostring(visual:GetAttribute("AttachmentIndex")) == slotId
				then
					_preferred = target
				end
			end
		else
			local base = target.Parent
			local occupied = target:GetAttribute("StorageOccupied")
			occupant = target:GetAttribute("StorageItemId")
			if
				distance > Config.PLACEMENT_INTERACT_RADIUS
				or target:GetAttribute("LockedSlot") == true
				or SlotPresentation.IsActive(target) == false
				or player:GetAttribute("PlayerDataWritable") ~= true
				or not State.IsPlatformFront(target.CFrame, (root :: BasePart).Position)
				or not base
				or base:GetAttribute("BaseId") ~= player:GetAttribute("AssignedBaseId")
				or base:GetAttribute("OwnerUserId") ~= player.UserId
				or occupied == nil
				or (carrying and occupied == true and type(occupant) ~= "string")
				or (not carrying and (occupied ~= true or type(occupant) ~= "string"))
			then
				continue
			end
			if carrying and occupied == true then
				continue
			end
			action = "Base"
		end
		table.insert(candidates, {
			Target = target,
			Entry = entry,
			Cart = cart,
			SlotId = slotId,
			SlotIndex = if slotId then tonumber(slotId:match("%d+$")) else nil,
			Action = action,
			CarryId = carryId,
			Occupant = occupant,
			Distance = distance,
			LOS = true,
			Key = target:GetFullName(),
		})
	end
	-- Add only eligible native sleeping-world prompts to the same selector.
	if alive and not carrying and not driving and not suspended and not state.Pending and not NativePending then
		for prompt in worldPrompts do
			local body = prompt.Parent
			local model = body and body.Parent
			while
				model
				and model ~= workspace
				and not (
					model:IsA("Model")
					and type(model:GetAttribute("ItemId")) == "string"
					and type(model:GetAttribute("BrainrotId")) == "string"
				)
			do
				model = model.Parent
			end
			if model == workspace then
				model = nil
			end
			if
				body
				and body:IsA("BasePart")
				and model
				and model:GetAttribute("Captured") == true
				and model:GetAttribute("Phase12InteractionReady") ~= false
				and model:GetAttribute("Phase10Banked") ~= true
			then
				table.insert(candidates, {
					Target = body,
					Entry = { Prompt = prompt, Target = body, Kind = "World" },
					Action = "World",
					CarryId = nil,
					Occupant = prompt:GetAttribute("ItemId"),
					Distance = ((root :: BasePart).Position - body.Position).Magnitude,
					Key = tostring(prompt:GetAttribute("ItemId")),
					Model = model,
				})
			end
		end
	end
	if alive and not carrying and not driving and not suspended and not state.Pending and not NativePending then
		for prompt in drivePrompts do
			local seat = prompt.Parent
			local cart = seat and seat.Parent
			if
				seat
				and seat:IsA("VehicleSeat")
				and cart
				and cart:GetAttribute("OwnerUserId") == player.UserId
				and seat.Occupant == nil
			then
				table.insert(candidates, {
					Target = seat,
					Entry = { Prompt = prompt, Target = seat, Kind = "Drive" },
					Action = "Drive",
					Cart = cart,
					Distance = ((root :: BasePart).Position - seat.Position).Magnitude,
					Key = "drive:" .. tostring(cart:GetAttribute("CartGeneration")),
				})
			end
		end
	end
	local scored = {}
	local camera = workspace.CurrentCamera
	if camera then
		for _, candidate in ipairs(candidates) do
			local entry = candidate.Entry
			local marker = entry.Marker or entry.Target
			local anchor = if marker:IsA("Attachment") then marker.WorldPosition else marker.Position
			local visibleCentre = nil
			if candidate.Occupant and candidate.Action ~= "World" then
				local base = if candidate.Cart then candidate.Cart else candidate.Target.Parent
				local folder = base
					and base:FindFirstChild(if candidate.Cart then "CargoVisuals" else "StoredBrainrots")
				if folder then
					for _, m in folder:GetChildren() do
						if m:IsA("Model") and m:GetAttribute("ItemId") == candidate.Occupant then
							local visual = require(script.Parent.CreaturePresentationController).ResolveVisual(m) or m
							local bounds =
								require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale).GetVisualBounds(visual)
							visibleCentre = if bounds
								then (visual:GetPivot() * bounds).Position
								else visual:GetPivot().Position
							break
						end
					end
				end
			end
			local measuredCentre = nil
			if candidate.Model then
				local bounds =
					require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale).GetVisualBounds(candidate.Model)
				if bounds then
					measuredCentre = (candidate.Model:GetPivot() * bounds).Position
				end
			end
			local centre = visibleCentre
				or measuredCentre
				or (if candidate.Model then candidate.Model:GetPivot().Position else entry.Target.Position)
			local point, onScreen = camera:WorldToViewportPoint(centre)
			local delta = centre - camera.CFrame.Position
			local angle = math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(delta.Unit), -1, 1)))
			local head = character and character:FindFirstChild("Head")
			local origin = if head and head:IsA("BasePart") then head.Position else (root :: BasePart).Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = if candidate.Cart then { character, candidate.Cart } else { character }
			params.RespectCanCollide = false
			params.IgnoreWater = false
			local hit = workspace:Raycast(origin, anchor - origin, params)
			local targetModel = candidate.Model or candidate.Target
			local hitAuthority = hit
				and require(script.Parent.CreaturePresentationController).ResolveAuthority(hit.Instance)
			local clear = not hit
				or hit.Instance == targetModel
				or hit.Instance:IsDescendantOf(targetModel)
				or (candidate.Model ~= nil and hitAuthority == candidate.Model)
			if candidate.Entry.Kind == "Base" and hit then
				clear = hit.Instance == candidate.Target or hit.Instance:IsDescendantOf(candidate.Target)
			end
			local range = if candidate.Action == "World" or candidate.Action == "Drive"
				then candidate.Entry.Prompt.MaxActivationDistance
				else Config.PLACEMENT_INTERACT_RADIUS
			candidate.id = candidate.Key
			candidate.revision = tostring(carryId)
				.. ":"
				.. tostring(candidate.Occupant)
				.. ":"
				.. tostring(candidate.Action)
			candidate.revision ..= ":" .. tostring(revisionFor(candidate.Occupant or candidate.CarryId))
			candidate.angle, candidate.distance, candidate.serverRange, candidate.drive =
				angle, candidate.Distance, range, candidate.Action == "Drive"
			candidate.valid = onScreen
				and point.Z > 0
				and clear
				and candidate.Distance <= math.min(Exact.Interaction.Range, range)
			table.insert(scored, candidate)
		end
	end
	local nextSelected = Selector.Update(scored, os.clock())

	if
		holdIntent
		and (
			not nextSelected
			or nextSelected.Entry ~= holdIntent.Entry
			or nextSelected.CarryId ~= holdIntent.CarryId
			or nextSelected.Occupant ~= holdIntent.Occupant
		)
	then
		holdIntent = nil
	end
	selected = nextSelected
	local platformReady = true

	pending = state.Pending
	if pending and pending.Target then
		local valid = false
		for _, context in candidates do
			if context.Target == pending.Target and context.Occupant == pending.Occupant then
				valid = true
				break
			end
		end
		if not valid then
			finish(pending.Token, nil)
		end
	end
	-- Only one local primary prompt is actionable. State changes update its text,
	-- not its identity or activation connection. Native hide/show never owns eligibility.
	for _, entry in entries do
		local prompt = entry.Prompt
		if prompt then
			local active = comparisonGui == nil and selected ~= nil and selected.Entry == entry and not state.Pending
			if entry.Kind == "Base" then
				active = active and platformReady
			end
			if selected and selected.Entry == entry then
				prompt.ActionText = if selected.Action == "Compare"
					then CombatStrings.Compare
					elseif selected.Action == "Replace" then "Hold to replace"
					elseif selected.Action == "Pickup" or selected.Occupant ~= nil then "Pick up"
					elseif selected.Action == "Cargo" then "Load onto cart"
					else "Place"
				prompt.ObjectText = if selected.Action == "Replace"
					then oldName(entry.Target) .. " · " .. selected.SlotId
					elseif selected.SlotId then selected.SlotId
					else "Platform"
				prompt.HoldDuration = if selected.Action == "Replace" then 0.6 else 0
			end
			prompt.Enabled = active
			activePrimary = activePrimary or active
		end
	end
	State.UpdateShopPromptPriority(
		shopPrompts,
		mutedShopPrompts,
		state:HasShopPriority(activePrimary),
		canRestoreShopPrompt
	)
	-- Keep competing seat keys suppressed while this cargo request is pending;
	-- disabling its button must not expose a second E action mid-press.
	local activeCart = if selected then selected.Cart else nil
	for prompt in mutedPrompts do
		if not activeCart or not prompt:IsDescendantOf(activeCart) then
			if prompt.Parent and not prompt.Enabled then
				prompt.Enabled = true
			end
			mutedPrompts[prompt] = nil
		end
	end
	if activeCart and carts[activeCart] then
		for prompt in carts[activeCart].Prompts do
			if
				prompt.Enabled
				and (prompt.KeyboardKeyCode == Enum.KeyCode.E or prompt.GamepadKeyCode == Enum.KeyCode.ButtonX)
			then
				mutedPrompts[prompt] = true
				prompt.Enabled = false -- Local conflict suppression only; never force seat entry.
			end
		end
	end
	for prompt in worldPrompts do
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Enabled = selected ~= nil
			and selected.Action == "World"
			and selected.Entry.Prompt == prompt
			and not NativePending
			and not state.Pending
	end

	local canDrop = carrying and alive and not suspended
	if canDrop and not dropBound then
		ContextActionService:BindAction(DROP_ACTION, requestDrop, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
		dropBound = true
	elseif not canDrop and dropBound then
		ContextActionService:UnbindAction(DROP_ACTION)
		dropBound = false
	end
	if not state.Pending and not holdIntent and os.clock() >= feedbackUntil then
		label.Text, label.Visible = "", false
	end
	if NativePending then
		local parent = NativePending.prompt.Parent
		if not alive or (NativePending.revision and revisionFor(NativePending.id) ~= NativePending.revision) then
			NativePending = nil
		elseif parent and parent:IsA("VehicleSeat") then
			if parent.Occupant ~= nil then
				NativePending = nil
			end
		elseif parent then
			local owner = parent:FindFirstAncestorOfClass("Model")
			if owner and owner:GetAttribute("Captured") ~= true then
				NativePending = nil
			end
		end
	end
	if NativePending then
		if driving or player:GetAttribute("CarriedItemId") == NativePending.id or not NativePending.prompt.Parent then
			NativePending = nil
		elseif os.clock() >= NativePending.expires then
			NativePending = nil
			Hud.Feedback("No response")
		end
	end
	local displayAction = nil
	if selected and not state.Pending and not NativePending and not driving and not suspended then
		local value = selected
		local species = value.Model and value.Model:GetAttribute("BrainrotId")
			or value.Target:GetAttribute("CargoBrainrotId")
			or value.Target:GetAttribute("StorageBrainrotId")
		local definition = Catalog.GetDefinition(species)
		displayAction = {
			action = if value.Action == "Drive"
				then "Drive"
				elseif value.Action == "World" or value.Action == "Pickup" or value.Occupant then "Pick up"
				elseif value.Action == "Cargo" then "Load"
				else "Place",
			name = if definition then definition.displayName else value.SlotId or "Platform",
			individualId = value.Occupant,
			activate = function()
				if value.Action == "World" or value.Action == "Drive" then
					if NativePending then
						return
					end
					value.Entry.Prompt:InputHoldBegin()
					value.Entry.Prompt:InputHoldEnd()
					NativePending = {
						id = value.Occupant or value.Key,
						revision = revisionFor(value.Occupant),
						prompt = value.Entry.Prompt,
						expires = os.clock() + Exact.Interaction.RequestTimeout,
					}
					refreshContext()
				else
					trigger(value.Entry)
				end
			end,
		}
	end
	Hud.Action(
		displayAction,
		if canDrop
			then function()
				requestDrop(DROP_ACTION, Enum.UserInputState.Begin)
			end
			else nil
	)
	for prompt in drivePrompts do
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Enabled = selected ~= nil
			and selected.Action == "Drive"
			and selected.Entry.Prompt == prompt
			and not NativePending
	end
	local prototype = workspace:FindFirstChild("SleepSelectedTarget")
	if not PrimaryHighlight and prototype and prototype:IsA("Highlight") then
		PrimaryHighlight = prototype:Clone()
		PrimaryHighlight.Name = "SelectedInteractionDestination"
		PrimaryHighlight.Parent = workspace
	end
	if PrimaryHighlight then
		PrimaryHighlight.Enabled = displayAction ~= nil
		PrimaryHighlight.Adornee = if selected then selected.Model or selected.Target else nil
	end
	trace("context")
end

local function bindCharacter(character: Model?)
	activePrimary = false
	state:ClearShopPriorityKeys()
	cancelContext()
	boundCharacter = character
	disconnectAll(characterConnections)
	disconnectAll(humanoidConnections)
	if rootConnection then
		rootConnection:Disconnect()
		rootConnection = nil
	end
	local function bindRoot()
		if rootConnection then
			rootConnection:Disconnect()
			rootConnection = nil
		end
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			rootConnection = root:GetPropertyChangedSignal("CFrame"):Connect(queueRefresh)
		end
		queueRefresh()
	end
	local function bindHumanoid()
		disconnectAll(humanoidConnections)
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			table.insert(humanoidConnections, humanoid.Seated:Connect(cancelContext))
			table.insert(humanoidConnections, humanoid.HealthChanged:Connect(queueRefresh))
		end
		queueRefresh()
	end
	if character then
		local function changed(child: Instance)
			if child:IsA("Humanoid") then
				bindHumanoid()
			elseif child.Name == "HumanoidRootPart" then
				bindRoot()
			elseif child:IsA("Tool") then
				cancelContext()
			end -- Hunting is not a cargo eligibility gate.
		end
		table.insert(characterConnections, character.ChildAdded:Connect(changed))
		table.insert(characterConnections, character.ChildRemoved:Connect(changed))
	end
	bindRoot()
	bindHumanoid()
end

for kind, name in requestNames do
	requestBindings[kind] = RemoteBinding.new({
		Root = ReplicatedStorage,
		Name = name,
		OnRemote = function(remote)
			requests[kind] = remote
			if not remote and state.Pending and state.Pending.Kind == kind then
				finish(state.Pending.Token, "Transfer unavailable · server registration")
			end
			queueRefresh()
			if not remote then
				return nil
			end
			return remote.OnClientEvent:Connect(function(id, success, reason, token)
				if kind == "Pickup" and NativePending and id == NativePending.id and token == "native:" .. id then
					NativePending = nil
					if not success then
						Hud.Feedback(reason or "Could not pick up")
					end
					queueRefresh()
					return
				end
				local pending = state.Pending
				if not pending or pending.Token ~= token or pending.Kind ~= kind or pending.ItemId ~= id then
					return
				end
				local message

				if success then
					message = if kind == "Drop"
						then "Released awake"
						elseif kind == "Pickup" then nil
						elseif kind == "Replace" then "Replaced · previous brainrot released awake"
						elseif kind == "Cargo" then nil
						else nil
				elseif reason == "NO_SAFE_POSE" then
					message = "No safe ground nearby · source unchanged"
				elseif reason == "OUT_OF_REACH" or reason == "OBSTRUCTED" then
					message = "Move closer or around the obstruction"
				elseif reason == "NOT_OWNER" then
					message = "Use your own current cart or base"
				elseif reason == "DRIVING" then
					message = "Dismount before handling cargo"
				elseif reason == "STALE_ID" or reason == "SOURCE_CHANGED" then
					message = "That item or slot changed · try again"
				else
					message = "Could not transfer · source unchanged"
				end
				finish(token, message)
			end)
		end,
		OnState = function(status, reason)
			player:SetAttribute("Transfer" .. kind .. "DependencyState", status)
			player:SetAttribute("Transfer" .. kind .. "DependencyReason", reason)
		end,
	})
end

-- Phase13Runtime remains the sole creator. Observe only its semantic tag, never
-- scan Workspace or all UI for conflicts. The authored map has a bounded set.
local function addShopPrompt(instance: Instance)
	if
		not instance:IsA("ProximityPrompt")
		or shopPrompts[instance]
		or (instance.Name ~= "Phase13ShopPrompt" and instance.Name ~= "Phase13BaseUpgradePrompt")
	then
		return
	end
	if shopPromptCount >= 64 then
		warn("[CartInteraction] Authored Shop prompt registry exceeded64; extra prompt was not mutated")
		return
	end
	shopPrompts[instance] = true
	shopPromptCount += 1
	State.UpdateShopPromptPriority(
		shopPrompts,
		mutedShopPrompts,
		state:HasShopPriority(activePrimary),
		canRestoreShopPrompt
	)
end
table.insert(connections, CollectionService:GetInstanceAddedSignal(SHOP_PROMPT_TAG):Connect(addShopPrompt))
table.insert(
	connections,
	CollectionService:GetInstanceRemovedSignal(SHOP_PROMPT_TAG):Connect(function(instance)
		if instance:IsA("ProximityPrompt") and shopPrompts[instance] then
			shopPrompts[instance] = nil
			shopPromptCount -= 1
			State.UpdateShopPromptPriority(
				shopPrompts,
				mutedShopPrompts,
				state:HasShopPriority(activePrimary),
				canRestoreShopPrompt
			)
		end
	end)
)
for _, prompt in CollectionService:GetTagged(SHOP_PROMPT_TAG) do
	addShopPrompt(prompt)
end
table.insert(
	connections,
	UserInputService.InputBegan:Connect(function(input)
		if state:TrackShopPriorityKey(input.KeyCode, true, activePrimary) then
			queueRefresh()
		end
	end)
)
table.insert(
	connections,
	UserInputService.InputEnded:Connect(function(input)
		if state:TrackShopPriorityKey(input.KeyCode, false, activePrimary) then
			queueRefresh()
		end
	end)
)
table.insert(
	connections,
	UserInputService.WindowFocusReleased:Connect(function()
		state:ClearShopPriorityKeys()
		cancelContext()
	end)
)

-- Only the player's own base platforms can ever be eligible (refreshContext requires
-- BaseId == AssignedBaseId), so the other bases' platforms are pooled but never registered:
-- no per-refresh scan, connections or ProximityPrompt for them.
local platformPool: { [BasePart]: boolean } = {}
local function ownPlatform(instance: Instance): boolean
	local base = instance.Parent
	local assigned = player:GetAttribute("AssignedBaseId")
	return base ~= nil and assigned ~= nil and base:GetAttribute("BaseId") == assigned
end
local function reconcilePlatforms()
	for platform in platformPool do
		if ownPlatform(platform) then
			addTarget(platform, "Base")
		else
			removeTarget(platform)
		end
	end
end
local function addTagged(instance: Instance, kind: string)
	if kind == "Base" then
		if not instance:IsA("BasePart") then
			return
		end
		platformPool[instance] = true
		if not ownPlatform(instance) then
			return
		end
	end
	addTarget(instance, kind)
end
for tag, kind in { [PLATFORM_TAG] = "Base", [CARGO_SLOT_TAG] = "Cargo" } do
	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			addTagged(v, kind)
		end)
	)
	table.insert(
		connections,
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if v:IsA("BasePart") then
				platformPool[v] = nil
				removeTarget(v)
			end
		end)
	)
	for _, instance in CollectionService:GetTagged(tag) do
		addTagged(instance, kind)
	end
end
table.insert(connections, player:GetAttributeChangedSignal("AssignedBaseId"):Connect(reconcilePlatforms))
local function addDrivePrompt(p)
	if p:IsA("ProximityPrompt") then
		drivePrompts[p] = true
		NativeConnections[p] = p.PromptButtonHoldBegan:Connect(function()
			if selected and selected.Entry.Prompt == p and not NativePending then
				NativePending =
					{ id = selected.Key, prompt = p, expires = os.clock() + Exact.Interaction.RequestTimeout }
			end
		end)
		queueRefresh()
	end
end
table.insert(connections, CollectionService:GetInstanceAddedSignal("ContextDrivePrompt"):Connect(addDrivePrompt))
table.insert(
	connections,
	CollectionService:GetInstanceRemovedSignal("ContextDrivePrompt"):Connect(function(p)
		drivePrompts[p] = nil
		queueRefresh()
	end)
)
for _, p in CollectionService:GetTagged("ContextDrivePrompt") do
	addDrivePrompt(p)
end
local function addWorldPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		worldPrompts[instance] = true
		NativeConnections[instance] = instance.PromptButtonHoldBegan:Connect(function()
			if selected and selected.Entry.Prompt == instance and not NativePending then
				NativePending = {
					id = instance:GetAttribute("ItemId"),
					revision = revisionFor(instance:GetAttribute("ItemId")),
					prompt = instance,
					expires = os.clock() + Exact.Interaction.RequestTimeout,
				}
			end
		end)
		queueRefresh()
	end
end
table.insert(connections, CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(addWorldPrompt))
table.insert(
	connections,
	CollectionService:GetInstanceRemovedSignal(PROMPT_TAG):Connect(function(v)
		if v:IsA("ProximityPrompt") then
			worldPrompts[v] = nil
			if NativeConnections[v] then
				NativeConnections[v]:Disconnect()
				NativeConnections[v] = nil
			end
		end
	end)
)
for _, instance in CollectionService:GetTagged(PROMPT_TAG) do
	addWorldPrompt(instance)
end
table.insert(
	connections,
	player:GetAttributeChangedSignal("CarriedItemId"):Connect(function()
		if NativePending and player:GetAttribute("CarriedItemId") == NativePending.id then
			NativePending = nil
		end
		queueRefresh()
	end)
)
table.insert(connections, player:GetAttributeChangedSignal("Phase10DazeEnd"):Connect(cancelContext))
table.insert(connections, player:GetAttributeChangedSignal("AssignedBaseId"):Connect(queueRefresh))
table.insert(connections, player:GetAttributeChangedSignal("Phase13ShopOpen"):Connect(cancelContext))
table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
table.insert(
	connections,
	player.CharacterRemoving:Connect(function(character)
		if character == boundCharacter then
			bindCharacter(nil)
		end
	end)
)
table.insert(connections, GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(cancelContext))
table.insert(connections, UserInputService.TextBoxFocused:Connect(cancelContext))
table.insert(connections, UserInputService.TextBoxFocusReleased:Connect(queueRefresh))
table.insert(connections, mouse.Move:Connect(queueRefresh))
table.insert(connections, State.WatchSpatialContext(RunService.Heartbeat, queueRefresh))
bindCharacter(player.Character)
refreshContext()

script.Destroying:Connect(function()
	destroyed = true
	for _, binding in requestBindings do
		binding:Destroy()
	end
	table.clear(requestBindings)
	closeComparison()
	disconnectAll(connections)
	disconnectAll(characterConnections)
	disconnectAll(humanoidConnections)
	if rootConnection then
		rootConnection:Disconnect()
		rootConnection = nil
	end
	if state.Pending then
		state:Finish(state.Pending.Token)
	end
	restoreMuted()
	for target in entries do
		removeTarget(target)
	end
	for prompt in worldPrompts do
		if prompt.Parent then
			prompt.Enabled = true
		end
	end
	for _, connection in NativeConnections do
		connection:Disconnect()
	end
	table.clear(NativeConnections)
	table.clear(worldPrompts)
	ContextActionService:UnbindAction(DROP_ACTION)
	if PrimaryHighlight then
		PrimaryHighlight:Destroy()
	end
	Hud.Action(nil, nil)
	gui:Destroy()
end)

table.insert(connections, player.CharacterRemoving:Connect(closeComparison))
table.insert(connections, workspace:GetAttributeChangedSignal("Phase12CycleId"):Connect(closeComparison))
table.insert(connections, UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(queueRefresh))
