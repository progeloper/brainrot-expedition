--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local Runtime = require(script.Parent.Parent.Utility.CartBurstRuntime)
local RequestState = require(script.Parent.Parent.Utility.CartBurstRequestState)
local Carts = require(script.Parent.CartService)
local Occupants = require(script.Parent.CartOccupantService)
local Profiles = require(script.Parent.PlayerDataService)
local Teams = require(script.Parent.ChariotTeamService)

local CartBurstService = {}
local states: { [Player]: any } = {}
local connections: { RBXScriptConnection } = {}
local remote: RemoteEvent? = nil
local started = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function ownerState(owner: Player, at: number): any?
	local handle = Profiles:GetSessionHandle(owner)
	if not handle or Profiles:GetStatus(owner) ~= "Ready" then
		return nil
	end
	local state = states[owner]
	if not state or state.Generation ~= handle.Generation then
		state = {
			Generation = handle.Generation,
			Runtime = Runtime.Create(at),
			Cart = nil,
			Driver = nil,
			DriverRevision = nil,
			Requests = {},
			RequestWindows = {},
		}
		states[owner] = state
	end
	return state
end

local function capacity(owner: Player): number
	local stats = Teams:GetStats(owner.UserId)
	return if FeatureFlags.EquippedTeamsEnabled and stats then stats.burstCapacity or 0 else 0
end

local function braking(cart: Model?): boolean
	if not cart then
		return false
	end
	if cart:GetAttribute("CartArcadeVersion")==1 then return cart:GetAttribute("CartDriveBraking")==true or cart:GetAttribute("CartDrivePaused")==true end
	local seat = cart:FindFirstChild("DriverSeat")
	return cart:GetAttribute("LongitudinalState") == "Braking"
		or cart:GetAttribute("LongitudinalRequestedState") == "Braking"
		or (seat ~= nil and seat:IsA("VehicleSeat") and seat.ThrottleFloat < -0.05)
end

local function validDriver(cart: Model?, driver: Player?): boolean
	if not cart or not driver or cart.Parent == nil or driver.Parent ~= Players then
		return false
	end
	return FeatureFlags.EquippedTeamsEnabled
		and FeatureFlags.CartEnabled
		and cart:GetAttribute("ResetActive") ~= true
		and driver:GetAttribute("TeamManagementOpen") ~= true
		and (driver:GetAttribute("Phase10DazeEnd") or 0) <= now()
		and Occupants:IsDriver(driver, cart)
		and Occupants:CanPlayerControlCart(driver, cart)
end

local function publish(state: any, cart: Model?, at: number)
	if not cart or cart.Parent == nil then
		return
	end
	local value = state.Runtime
	cart:SetAttribute("BurstCapacity", value.Capacity)
	cart:SetAttribute("BurstEnergy", value.Energy)
	cart:SetAttribute("BurstActive", value.Active)
	cart:SetAttribute("BurstRechargeState", Runtime.RechargeState(value, at))
	cart:SetAttribute("BurstRechargeEligibleAt", value.RechargeEligibleAt)
	cart:SetAttribute("BurstSnapshotAt", at)
end

local function reconcile(owner: Player, state: any, at: number, explicitCapacity: number?): any?
	local record = Carts:GetCartRecord(owner)
	local cart = if record then record.Model else nil
	local driver = if cart then Occupants:GetDriver(cart) else nil
	local revision = if cart then Occupants:GetDriverRevision(cart) else nil
	local previousActive = state.Runtime.Active
	Runtime.Bind(state, cart, driver, revision, at)
	Runtime.Step(state.Runtime, at, explicitCapacity or capacity(owner), validDriver(cart, driver), braking(cart))
	publish(state, cart, at)
	if previousActive ~= state.Runtime.Active and cart then
		Carts:ReconcileOwnerPerformance(owner.UserId, "BurstStateChanged")
	end
	return record
end

function CartBurstService:Request(player: Player, request: any): (boolean, string)
	if not started or not FeatureFlags.EquippedTeamsEnabled then
		return false, "DISABLED"
	end
	if not RequestState.IsValid(request) then
		return false, "INVALID_REQUEST"
	end
	local cart = request.cart
	local ownerId = cart:GetAttribute("OwnerUserId")
	local record = if type(ownerId) == "number" then Carts:GetCartRecordByOwnerUserId(ownerId) else nil
	if not record or record.Model ~= cart or record.Generation ~= request.generation then
		return false, "STALE_CART"
	end
	if not validDriver(cart, player) then
		return false, "INVALID_DRIVER"
	end
	local owner = Players:GetPlayerByUserId(record.OwnerUserId)
	local at = now()
	local state = owner and ownerState(owner, at)
	if not owner or not state then
		return false, "OWNER_NOT_READY"
	end
	local fresh, rejection = RequestState.Accept(state, player, request.sequence, at)
	if not fresh then
		return false, rejection :: string
	end
	reconcile(owner, state, at)
	local previousActive = state.Runtime.Active
	local accepted, reason
	if request.action == "Stop" then
		Runtime.Stop(state.Runtime, at, "MANUAL")
		accepted, reason = true, "STOPPED"
	else
		accepted, reason = Runtime.Toggle(state.Runtime, at, capacity(owner), validDriver(cart, player), braking(cart))
	end
	publish(state, cart, at)
	if previousActive ~= state.Runtime.Active then
		Carts:ReconcileOwnerPerformance(owner.UserId, "BurstRequest")
	end
	return accepted, reason
end

function CartBurstService:GetSnapshot(owner: Player): any?
	local state = states[owner]
	if not state then
		return nil
	end
	local value = table.clone(state.Runtime)
	value.Generation = state.Generation
	return table.freeze(value)
end

function CartBurstService:Start()
	if started or not FeatureFlags.EquippedTeamsEnabled then
		return
	end
	started = true
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	local existing = folder:FindFirstChild("CartBurstRequest")
	assert(existing == nil or existing:IsA("RemoteEvent"), "CartBurstRequest remote type conflict")
	remote = (existing or Instance.new("RemoteEvent")) :: RemoteEvent
	remote.Name = "CartBurstRequest"
	remote.Parent = folder
	Carts:ConfigureBurstState(function(ownerId, cart)
		local owner = Players:GetPlayerByUserId(ownerId)
		local state = owner and states[owner]
		local driver = Occupants:GetDriver(cart)
		local revision = Occupants:GetDriverRevision(cart)
		return if state
				and Runtime.IsBound(state, cart, driver, revision)
				and validDriver(cart, driver)
			then state.Runtime
			else nil
	end)
	table.insert(
		connections,
		remote.OnServerEvent:Connect(function(player, request)
			self:Request(player, request)
		end)
	)
	table.insert(
		connections,
		Occupants.DriverChanged:Connect(function(cart)
			local ownerId = cart:GetAttribute("OwnerUserId")
			local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
			local state = owner and ownerState(owner, now())
			if owner and state then
				reconcile(owner, state, now())
			end
		end)
	)
	table.insert(
		connections,
		Carts.CartDespawned:Connect(function(record)
			local owner = Players:GetPlayerByUserId(record.OwnerUserId)
			local state = owner and states[owner]
			if owner and state then
				reconcile(owner, state, now())
			end
		end)
	)
	table.insert(
		connections,
		Carts.CartSpawned:Connect(function(record)
			local owner = Players:GetPlayerByUserId(record.OwnerUserId)
			local state = owner and ownerState(owner, now())
			if owner and state then
				reconcile(owner, state, now())
			end
		end)
	)
	table.insert(
		connections,
		Carts.PerformanceChanged:Connect(function(record)
			local owner = Players:GetPlayerByUserId(record.OwnerUserId)
			local state = owner and ownerState(owner, now())
			if owner and state then
				reconcile(owner, state, now(), record.PerformanceResult.burstCapacity or 0)
			end
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			states[player] = nil
			for _, state in states do
				state.Requests[player] = nil
				state.RequestWindows[player] = nil
			end
		end)
	)
	local accumulator = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			accumulator += dt
			if accumulator < 0.1 then
				return
			end
			accumulator = 0
			local at = now()
			for _, owner in Players:GetPlayers() do
				local state = ownerState(owner, at)
				if state then
					reconcile(owner, state, at)
				elseif states[owner] then
					local stale = states[owner]
					Runtime.Step(stale.Runtime, at, stale.Runtime.Capacity, false, false)
					publish(stale, stale.Cart, at)
					Carts:ReconcileOwnerPerformance(owner.UserId, "BurstOwnerUnavailable")
				end
			end
		end)
	)
end

function CartBurstService:Stop()
	if not started then
		return
	end
	started = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	Carts:ConfigureBurstState(nil)
	for owner, state in states do
		Runtime.Stop(state.Runtime, now(), "DISABLED")
		publish(state, state.Cart, now())
		Carts:ReconcileOwnerPerformance(owner.UserId, "BurstDisabled")
	end
end

return CartBurstService
