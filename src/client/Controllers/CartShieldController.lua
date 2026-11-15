--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local Presentation = require(ReplicatedStorage.Shared.Utility.CartShieldPresentation)
local CargoOverlay = require(ReplicatedStorage.Shared.Utility.CartShieldCargoOverlay)
local LocalCart = require(script.Parent.Parent.State.LocalCartState)

local Controller = {}
local player = Players.LocalPlayer
local started = false
local generation = 0
local records: { [Model]: any } = {}
local activeRecords: { [Model]: any } = {}
local connections: { RBXScriptConnection } = {}
local runtimeConnections: { RBXScriptConnection } = {}
local folderConnections: { RBXScriptConnection } = {}
local feedbackConnections: { RBXScriptConnection } = {}
local runtime: Folder? = nil
local cartsFolder: Folder? = nil
local countdown: RBXScriptConnection? = nil
local gui: ScreenGui? = nil
local bounds: Frame? = nil
local panel: Frame? = nil
local title: TextLabel? = nil
local status: TextLabel? = nil
local feedback: TextLabel? = nil
local shieldIcon: Frame? = nil
local feedbackMessage: string? = nil
local feedbackCart: Model? = nil
local feedbackIdentity: any? = nil
local feedbackVersion = 0
local feedbackRemote: RemoteEvent? = nil

local function disconnect(list: { RBXScriptConnection })
	for _, connection in list do connection:Disconnect() end
	table.clear(list)
end

local function clock(): number return Workspace:GetServerTimeNow() end

local function updateHud()
	if not panel or not title or not status or not bounds then return end
	local cart = LocalCart.GetCart()
	local record = cart and records[cart]
	local view = Presentation.View(record and record.Snapshot, clock())
	panel.Visible = started and (view.visible or feedbackMessage ~= nil) and player:GetAttribute("ChariotTeamMenuOpen") ~= true
	local layout = Presentation.Layout(bounds.AbsoluteSize)
	panel.Position, panel.Size = layout.Position, layout.Size
	local width, height = layout.Size.X.Offset, layout.Size.Y.Offset
	local narrow = width < 160
	if shieldIcon then shieldIcon.Visible = view.visible and not narrow end
	title.Position = UDim2.fromOffset(if narrow then 8 else 32, 5)
	title.Size = UDim2.new(1, if narrow then -16 else -40, 0, 23)
	title.TextSize = if narrow then 14 else 16
	title.Visible, status.Visible = view.visible, view.visible
	title.Text, status.Text = view.title, view.status
	status.TextColor3 = if view.active then Color3.fromRGB(153, 221, 255) else Color3.fromRGB(195, 204, 211)
	status.Size = UDim2.new(1, -16, 0, height - 31)
	if feedback then
		feedback.Text, feedback.Visible = feedbackMessage or "", feedbackMessage ~= nil
		feedback.Position = UDim2.fromOffset(8, if view.visible then height else 5)
		feedback.Size = UDim2.new(1, -16, 0, if view.visible then 34 else height - 10)
		if feedbackMessage and view.visible then panel.Size = UDim2.fromOffset(width, height + 36) end
	end
end

local updateCountdown

local function scheduleExpiry(cart: Model, record: any, value: any)
	if Presentation.SameWindow(record.ExpiryWindow or {}, value) then return end
	local expected = { cartGeneration = value.cartGeneration, lifecycleId = value.lifecycleId, protectedUntil = value.protectedUntil }
	record.ExpiryWindow = expected
	local function expire()
		if not started or records[cart] ~= record or not Presentation.SameWindow(expected, record.Snapshot) then return end
		local now = clock()
		if now < expected.protectedUntil then task.delay(expected.protectedUntil - now, expire) return end
		if record.Overlay then
			record.Overlay:Tick(now)
			if record.Snapshot.capacity == 0 then record.Overlay:Destroy() record.Overlay = nil end
		end
		activeRecords[cart] = nil
		updateHud()
		updateCountdown()
	end
	task.delay(math.max(0, expected.protectedUntil - clock()), expire)
end

local function removeCart(cart: Model)
	local record = records[cart]
	if not record then return end
	records[cart] = nil
	activeRecords[cart] = nil
	record.Generation += 1
	disconnect(record.Connections)
	if record.Overlay then record.Overlay:Destroy() end
	if feedbackCart == cart then feedbackVersion += 1 feedbackMessage, feedbackCart, feedbackIdentity = nil, nil, nil end
	updateHud()
	updateCountdown()
end

local function applySnapshot(cart: Model, record: any)
	if not started or records[cart] ~= record then return end
	local value = Presentation.Read(cart)
	if value and not Presentation.Accept(record.Snapshot, value, cart:GetAttribute("CartGeneration")) then return end
	record.Snapshot = value
	if feedbackCart == cart and Presentation.ShouldClearFeedback(value, feedbackIdentity, {
		cartGeneration = cart:GetAttribute("CartGeneration"), lifecycleId = cart:GetAttribute("ShieldLifecycleId"),
		revision = cart:GetAttribute("ShieldRevision"),
	}, clock()) then
		feedbackVersion += 1
		feedbackMessage, feedbackCart, feedbackIdentity = nil, nil, nil
	end
	local view = Presentation.View(value, clock())
	if view.active then
		if not record.Overlay then record.Overlay = CargoOverlay.new(cart) end
		record.Overlay:Sync(value, clock())
		activeRecords[cart] = record
		scheduleExpiry(cart, record, value)
	else
		activeRecords[cart] = nil
		if record.Overlay then
			if value and value.capacity > 0 then record.Overlay:Sync(value, clock())
			else record.Overlay:Destroy() record.Overlay = nil end
		end
	end
	updateHud()
	updateCountdown()
end

local function queueSnapshot(cart: Model, record: any)
	if record.Pending then return end
	record.Pending = true
	local expected = record.Generation
	task.defer(function()
		if not started or records[cart] ~= record or record.Generation ~= expected then return end
		record.Pending = false
		applySnapshot(cart, record)
	end)
end

local function addCart(cart: Instance)
	if not cart:IsA("Model") or records[cart] or cart:GetAttribute("RuntimeCart") ~= true then return end
	local record = { Snapshot = nil, Overlay = nil, Connections = {}, Generation = 0, Pending = false,
		FeedbackLifecycle = nil, FeedbackRevision = -1 }
	records[cart] = record
	for _, attribute in { "ShieldRevision", "ShieldLifecycleId", "ShieldCartGeneration", "CartGeneration", "ShieldCapacity", "ShieldRemaining", "ShieldProtectionExpiresAt" } do
		table.insert(record.Connections, cart:GetAttributeChangedSignal(attribute):Connect(function() queueSnapshot(cart, record) end))
	end
	table.insert(record.Connections, cart.Destroying:Connect(function() removeCart(cart) end))
	applySnapshot(cart, record)
end

updateCountdown = function()
	if next(activeRecords) == nil then
		if countdown then countdown:Disconnect() countdown = nil end
		return
	end
	if countdown then return end
	local elapsed = 0
	countdown = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then return end
		elapsed = 0
		local now = clock()
		-- Only live protection windows are visited. No per-frame cart/cargo scan.
		for cart, record in activeRecords do
			if record.Overlay then record.Overlay:Tick(now) end
			if not Presentation.View(record.Snapshot, now).active then
				activeRecords[cart] = nil
				if record.Overlay and (not record.Snapshot or record.Snapshot.capacity == 0) then
					record.Overlay:Destroy() record.Overlay = nil
				end
			end
		end
		updateHud()
		updateCountdown()
	end)
end

local function bindCartFolder(folder: Folder?)
	if folder == cartsFolder then return end
	disconnect(folderConnections)
	for cart in records do removeCart(cart) end
	cartsFolder = folder
	if not folder then return end
	table.insert(folderConnections, folder.ChildAdded:Connect(addCart))
	table.insert(folderConnections, folder.ChildRemoved:Connect(function(child) if child:IsA("Model") then removeCart(child) end end))
	for _, cart in folder:GetChildren() do addCart(cart) end
end

local function refreshRuntime()
	local found = Workspace:FindFirstChild("Runtime")
	local nextRuntime = if found and found:IsA("Folder") then found else nil
	if nextRuntime ~= runtime then
		disconnect(runtimeConnections)
		runtime = nextRuntime
		if runtime then
			local function refreshFolder()
				local carts = runtime and runtime:FindFirstChild("Carts")
				bindCartFolder(if carts and carts:IsA("Folder") then carts else nil)
			end
			table.insert(runtimeConnections, runtime.ChildAdded:Connect(refreshFolder))
			table.insert(runtimeConnections, runtime.ChildRemoved:Connect(refreshFolder))
		end
	end
	local carts = runtime and runtime:FindFirstChild("Carts")
	bindCartFolder(if carts and carts:IsA("Folder") then carts else nil)
end

local function showFeedback(value: any)
	if not started or type(value) ~= "table" or not feedback then return end
	if value.kind ~= "Block" and value.kind ~= "Protected" and value.kind ~= "Refill" then return end
	if value.message ~= "Cargo protected!" and value.message ~= "Shield blocked your hit." and value.message ~= "Shield refilled." then return end
	local cart = value.cart
	if typeof(cart) ~= "Instance" or not cart:IsA("Model") or cart.Parent == nil
		or value.cartGeneration ~= cart:GetAttribute("CartGeneration") then return end
	local currentLife = cart:GetAttribute("ShieldLifecycleId")
	if currentLife ~= nil and currentLife ~= value.lifecycleId then return end
	local record = records[cart]
	if record then
		if record.FeedbackLifecycle == value.lifecycleId and type(value.revision) == "number" and value.revision < record.FeedbackRevision then return end
		record.FeedbackLifecycle = value.lifecycleId
		record.FeedbackRevision = value.revision or record.FeedbackRevision
	end
	feedbackVersion += 1
	local expectedFeedback, expectedGeneration = feedbackVersion, generation
	feedbackMessage, feedbackCart = value.message, cart
	feedbackIdentity = { cartGeneration = value.cartGeneration, lifecycleId = value.lifecycleId, revision = value.revision }
	updateHud()
	task.delay(2.5, function()
		if started and feedback and feedbackVersion == expectedFeedback and generation == expectedGeneration then
			feedbackMessage, feedbackCart, feedbackIdentity = nil, nil, nil
			updateHud()
		end
	end)
end

local function bindFeedback()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local found = folder and folder:FindFirstChild("CartShieldFeedback")
	local nextRemote = if found and found:IsA("RemoteEvent") then found else nil
	if nextRemote == feedbackRemote then return end
	disconnect(feedbackConnections)
	feedbackRemote = nextRemote
	if nextRemote then table.insert(feedbackConnections, nextRemote.OnClientEvent:Connect(showFeedback)) end
end

local function createHud()
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui or not started then return end
	local screen = Instance.new("ScreenGui")
	screen.Name, screen.ResetOnSpawn = "CartShieldGui", false
	require(script.Parent.Parent.UI.StudPopUI).skin(screen, { hints = { SafeArea = "plain" }, windowDepth = 0 })
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.IgnoreGuiInset, screen.ClipToDeviceSafeArea = false, true
	screen.DisplayOrder = 20
	screen.Parent = playerGui
	gui = screen
	local safe = Instance.new("Frame") safe.Name = "SafeArea" safe.Size = UDim2.fromScale(1, 1) safe.BackgroundTransparency = 1 safe.Parent = screen bounds = safe
	local frame = Instance.new("Frame") frame.Name = "ShieldPanel" frame.BackgroundColor3 = Color3.fromRGB(19, 26, 39) frame.BackgroundTransparency = 0.08 frame.BorderSizePixel = 0 frame.Visible = false frame.Parent = safe panel = frame
	local corner = Instance.new("UICorner") corner.CornerRadius = UDim.new(0, 8) corner.Parent = frame
	local stroke = Instance.new("UIStroke") stroke.Color = Color3.fromRGB(153, 221, 255) stroke.Parent = frame
	local icon = Instance.new("Frame") icon.Name = "ShieldIcon" icon.Position = UDim2.fromOffset(10, 7) icon.Size = UDim2.fromOffset(15, 17) icon.BackgroundColor3 = Color3.fromRGB(153, 221, 255) icon.BorderSizePixel = 0 icon.Parent = frame
	shieldIcon = icon
	local iconCorner = Instance.new("UICorner") iconCorner.CornerRadius = UDim.new(0, 5) iconCorner.Parent = icon
	local point = Instance.new("Frame") point.Rotation = 45 point.Position = UDim2.fromOffset(3, 10) point.Size = UDim2.fromOffset(9, 9) point.BackgroundColor3 = icon.BackgroundColor3 point.BorderSizePixel = 0 point.Parent = icon
	local counter = Instance.new("TextLabel") counter.Name = "ShieldCounter" counter.Position = UDim2.fromOffset(32, 5) counter.Size = UDim2.new(1, -40, 0, 23) counter.BackgroundTransparency = 1 counter.Font = Enum.Font.GothamBold counter.TextSize = 16 counter.TextXAlignment = Enum.TextXAlignment.Left counter.TextColor3 = Color3.fromRGB(245, 241, 231) counter.Parent = frame title = counter
	local info = Instance.new("TextLabel") info.Name = "ProtectionStatus" info.Position = UDim2.fromOffset(8, 29) info.Size = UDim2.new(1, -16, 1, -31) info.BackgroundTransparency = 1 info.Font = Enum.Font.GothamMedium info.TextSize = 14 info.TextWrapped = true info.TextYAlignment = Enum.TextYAlignment.Top info.TextXAlignment = Enum.TextXAlignment.Left info.Parent = frame status = info
	local toast = Instance.new("TextLabel") toast.Name = "ShieldFeedback" toast.BackgroundTransparency = 1 toast.Font = Enum.Font.GothamBold toast.TextSize = 14 toast.TextColor3 = Color3.fromRGB(153, 221, 255) toast.TextWrapped = true toast.Visible = false toast.Parent = frame feedback = toast
	table.insert(connections, safe:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateHud))
end

function Controller.Start()
	if started or not FeatureFlags.EquippedTeamsEnabled then return end
	started = true
	generation += 1
	createHud()
	table.insert(connections, Workspace.ChildAdded:Connect(refreshRuntime))
	table.insert(connections, Workspace.ChildRemoved:Connect(refreshRuntime))
	table.insert(connections, LocalCart.Changed:Connect(updateHud))
	table.insert(connections, player:GetAttributeChangedSignal("ChariotTeamMenuOpen"):Connect(updateHud))
	table.insert(connections, ReplicatedStorage.ChildAdded:Connect(bindFeedback))
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		table.insert(connections, remotes.ChildAdded:Connect(bindFeedback))
		table.insert(connections, remotes.ChildRemoved:Connect(bindFeedback))
	end
	bindFeedback()
	refreshRuntime()
	updateHud()
end

function Controller.Stop()
	if not started then return end
	started = false
	generation += 1
	for cart in records do removeCart(cart) end
	disconnect(connections)
	disconnect(runtimeConnections)
	disconnect(folderConnections)
	disconnect(feedbackConnections)
	if countdown then countdown:Disconnect() countdown = nil end
	if gui then gui:Destroy() end
	gui, bounds, panel, title, status, feedback, shieldIcon = nil, nil, nil, nil, nil, nil, nil
	feedbackMessage, feedbackCart, feedbackIdentity = nil, nil, nil
	runtime, cartsFolder, feedbackRemote = nil, nil, nil
end

function Controller.Diagnostics(): any
	local carts, active, models, highlights, count = 0, 0, 0, 0, #connections + #runtimeConnections + #folderConnections + #feedbackConnections
	for _ in activeRecords do active += 1 end
	for _, record in records do
		carts += 1 count += #record.Connections
		if record.Overlay then
			local values = record.Overlay:Diagnostics()
			models += values.records highlights += values.highlights count += values.connections
		end
	end
	return { carts = carts, active = active, cargoModels = models, highlights = highlights, connections = count, schedulers = if countdown then 1 else 0 }
end

return Controller
