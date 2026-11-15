--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local player = Players.LocalPlayer
local log = Logger.new("LocalCartState")

local LocalCartState = {}

local changedEvent = Instance.new("BindableEvent")
local currentCart: Model? = nil
local currentSeat: VehicleSeat? = nil
local currentRuntime: Folder? = nil
local currentFolder: Folder? = nil
local authorized = false
local started = false
local generation = 0

local workspaceConnections: { RBXScriptConnection } = {}
local runtimeConnections: { RBXScriptConnection } = {}
local folderConnections: { RBXScriptConnection } = {}
local cartConnections: { RBXScriptConnection } = {}
local seatConnections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}

LocalCartState.Changed = changedEvent.Event

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function calculateAuthorization(): boolean
	local cart = currentCart
	local seat = currentSeat
	local character = player.Character
	local activeDriverUserId = if cart ~= nil then cart:GetAttribute("ActiveDriverUserId") else nil

	return type(activeDriverUserId) == "number"
		and player:GetAttribute("CarriedItemId") == nil -- UI mirror only; server owns eligibility.
		and activeDriverUserId == player.UserId
		and seat ~= nil
		and character ~= nil
		and seat.Occupant ~= nil
		and seat.Occupant.Parent == character
end

local function publishAuthorization(nextAuthorization: boolean, force: boolean?)
	local changed = nextAuthorization ~= authorized

	authorized = nextAuthorization

	if changed then
		log:Info(
			"Driver authorization changed: %s ActiveDriverUserId=%s Occupant=%s",
			tostring(authorized),
			if currentCart ~= nil
				then tostring(currentCart:GetAttribute("ActiveDriverUserId"))
				else "None",
			if currentSeat ~= nil and currentSeat.Occupant ~= nil
				then currentSeat.Occupant:GetFullName()
				else "None"
		)
	end

	if changed or force then
		changedEvent:Fire(currentCart, authorized)
	end
end

local function publish(force: boolean?)
	publishAuthorization(calculateAuthorization(), force)
end

local function bindSeat(seat: VehicleSeat, expectedCart: Model, expectedGeneration: number)
	if not started or currentCart ~= expectedCart or generation ~= expectedGeneration then
		return
	end

	disconnectAll(seatConnections)
	currentSeat = seat

	table.insert(
		seatConnections,
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			publish(false)
		end)
	)

	publish(true)
end

local function setCart(cart: Model?)
	if currentCart == cart then
		return
	end

	local previous = currentCart

	generation += 1
	local expectedGeneration = generation

	disconnectAll(cartConnections)
	disconnectAll(seatConnections)
	currentCart = cart
	currentSeat = nil
	authorized = false

	if previous ~= nil then
		log:Info("Lost local cart %s", previous:GetFullName())
	end

	if cart == nil then
		changedEvent:Fire(nil, false)
		return
	end

	log:Info(
		"Discovered local cart %s CartId=%s OwnerUserId=%s",
		cart:GetFullName(),
		tostring(cart:GetAttribute("CartId")),
		tostring(cart:GetAttribute("OwnerUserId"))
	)

	table.insert(
		cartConnections,
		cart:GetAttributeChangedSignal("ActiveDriverUserId"):Connect(function()
			if currentCart == cart and generation == expectedGeneration then
				publish(false)
			end
		end)
	)
	table.insert(
		cartConnections,
		cart.Destroying:Connect(function()
			if currentCart == cart and generation == expectedGeneration then
				disconnectAll(seatConnections)
				currentSeat = nil
				publish(true)
			end
		end)
	)

	local existingSeat = cart:FindFirstChild("DriverSeat")

	if existingSeat ~= nil and existingSeat:IsA("VehicleSeat") then
		bindSeat(existingSeat, cart, expectedGeneration)
		return
	end

	changedEvent:Fire(cart, false)

	table.insert(
		cartConnections,
		cart.ChildAdded:Connect(function(child)
			if child.Name == "DriverSeat" and child:IsA("VehicleSeat") then
				bindSeat(child, cart, expectedGeneration)
			end
		end)
	)

	local replicatedSeat = cart:FindFirstChild("DriverSeat")

	if replicatedSeat ~= nil and replicatedSeat:IsA("VehicleSeat") then
		bindSeat(replicatedSeat, cart, expectedGeneration)
		return
	end

	task.delay(5, function()
		if
			started
			and currentCart == cart
			and currentSeat == nil
			and generation == expectedGeneration
		then
			log:Warn("Owned cart %s did not replicate DriverSeat within 5 seconds", cart.Name)
		end
	end)
end

local function findOwnedCart(folder: Folder): Model?
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == player.UserId then
			return child
		end
	end

	return nil
end

local function refreshCart()
	setCart(if currentFolder ~= nil then findOwnedCart(currentFolder) else nil)
end

local function bindCartFolder(folder: Folder?)
	if currentFolder == folder then
		refreshCart()
		return
	end

	disconnectAll(folderConnections)
	currentFolder = folder

	if folder == nil then
		setCart(nil)
		return
	end

	log:Info("Bound runtime cart folder %s", folder:GetFullName())

	table.insert(folderConnections, folder.ChildAdded:Connect(refreshCart))
	table.insert(folderConnections, folder.ChildRemoved:Connect(refreshCart))
	table.insert(
		folderConnections,
		folder.Destroying:Connect(function()
			if currentFolder == folder then
				bindCartFolder(nil)
			end
		end)
	)

	refreshCart()
end

local function bindRuntime(runtime: Folder?)
	if currentRuntime == runtime then
		return
	end

	disconnectAll(runtimeConnections)
	currentRuntime = runtime

	if runtime == nil then
		bindCartFolder(nil)
		return
	end

	local function refreshFolder()
		local carts = runtime:FindFirstChild("Carts")

		bindCartFolder(if carts ~= nil and carts:IsA("Folder") then carts else nil)
	end

	table.insert(runtimeConnections, runtime.ChildAdded:Connect(refreshFolder))
	table.insert(runtimeConnections, runtime.ChildRemoved:Connect(refreshFolder))
	table.insert(
		runtimeConnections,
		runtime.Destroying:Connect(function()
			if currentRuntime == runtime then
				bindRuntime(nil)
			end
		end)
	)

	refreshFolder()
end

local function refreshRuntime()
	local runtime = Workspace:FindFirstChild("Runtime")

	bindRuntime(if runtime ~= nil and runtime:IsA("Folder") then runtime else nil)
end

function LocalCartState.GetCart(): Model?
	return currentCart
end

function LocalCartState.IsAuthorizedDriver(): boolean
	return authorized
end

function LocalCartState.Start()
	if started then
		return
	end

	started = true
	generation += 1

	table.insert(workspaceConnections, Workspace.ChildAdded:Connect(refreshRuntime))
	table.insert(workspaceConnections, Workspace.ChildRemoved:Connect(refreshRuntime))
	table.insert(
		characterConnections,
		player:GetAttributeChangedSignal("CarriedItemId"):Connect(function()
			-- Existing Changed subscribers clear this client's input, actuators and
			-- driving camera. Never write to another driver's cart from this mirror.
			publish(false)
		end)
	)
	table.insert(
		characterConnections,
		player.CharacterAdded:Connect(function()
			publish(false)
		end)
	)
	table.insert(
		characterConnections,
		player.CharacterRemoving:Connect(function(character)
			local occupant = if currentSeat ~= nil then currentSeat.Occupant else nil

			if occupant ~= nil and occupant.Parent == character then
				publishAuthorization(false, false)
			else
				publish(false)
			end
		end)
	)

	refreshRuntime()
	log:Info("Local cart state started")
end

function LocalCartState.Stop()
	if not started then
		return
	end

	started = false
	generation += 1

	disconnectAll(workspaceConnections)
	disconnectAll(runtimeConnections)
	disconnectAll(folderConnections)
	disconnectAll(cartConnections)
	disconnectAll(seatConnections)
	disconnectAll(characterConnections)

	currentRuntime = nil
	currentFolder = nil
	currentSeat = nil
	setCart(nil)

	log:Info("Local cart state stopped")
end

return LocalCartState
