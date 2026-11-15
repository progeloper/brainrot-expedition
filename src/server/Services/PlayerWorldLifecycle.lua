--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local PlayerDataService = require(script.Parent.PlayerDataService)
local CartService = require(script.Parent.CartService)
local PlayerBaseSystem = require(script.Parent.Parent.Systems.PlayerBaseSystem)
local BaseStorageSystem = require(script.Parent.Parent.Systems.BaseStorageSystem)

local log = Logger.new("PlayerWorldLifecycle")
local BASE_WAIT_DEADLINE_SECONDS = 10

local PlayerWorldLifecycle = {}
local started = false
local dependencies: any = nil
local states: { [Player]: any } = {}
local generationsByUserId: { [number]: number } = {}
local readyListeners: { [any]: (Player) -> () } = {}
local connections: { any } = {}
local baseConnection: any = nil
local diagnosticListeners: { [any]: (Player, any) -> () } = {}
local diagnosticSequence = 0

local function deps(): any
	return dependencies
		or {
			Profile = PlayerDataService,
			Base = PlayerBaseSystem,
			Storage = BaseStorageSystem,
			Cart = CartService,
			CartEnabled = FeatureFlags.CartEnabled,
			Delay = task.delay,
		}
end

local function sameAssignment(left: any, right: any): boolean
	return left ~= nil
		and right ~= nil
		and left.Player == right.Player
		and left.Base == right.Base
		and left.BaseId == right.BaseId
		and left.Generation == right.Generation
end

local function current(state: any): boolean
	local d = deps()
	return states[state.Player] == state
		and state.Player.Parent == Players
		and generationsByUserId[state.Player.UserId] == state.Generation
		and d.Profile:IsCurrentSessionHandle(state.Session)
end

local function setStatus(state: any, status: string, code: string?)
	if states[state.Player] ~= state then
		return
	end
	state.Status = status
	state.Code = code
	pcall(function()
		state.Player:SetAttribute("PlayerWorldStatus", status)
		state.Player:SetAttribute("PlayerWorldStatusCode", code)
	end)
	local kind = if status == "Restoring"
		then "WorldRestoreStarted"
		elseif status == "Ready" then "WorldRestoreReady"
		elseif status == "Blocked" then "WorldRestoreBlocked"
		else nil
	if kind then
		diagnosticSequence += 1
		local receipt = table.freeze({
			kind = kind,
			eventId = "world:" .. tostring(diagnosticSequence),
			at = workspace:GetServerTimeNow(),
			sessionGeneration = state.Session.Generation,
			worldGeneration = state.Generation,
			code = code,
		})
		for _, callback in diagnosticListeners do
			local ok, failure = pcall(callback, state.Player, receipt)
			if not ok then
				log:Warn("World diagnostic observer failed: %s", tostring(failure))
			end
		end
	end
end

local function notifyReady(player: Player)
	for _, callback in readyListeners do
		local ok, failure = pcall(callback, player)
		if not ok then
			log:Warn("World-ready listener failed UserId=%d: %s", player.UserId, tostring(failure))
		end
	end
end

local function stateFor(player: Player): any?
	local d = deps()
	local session = d.Profile:GetSessionHandle(player)
	if session == nil then
		return nil
	end
	local state = states[player]
	if
		state
		and state.Session.Player == session.Player
		and state.Session.UserId == session.UserId
		and state.Session.Generation == session.Generation
	then
		return state
	end
	local generation = (generationsByUserId[player.UserId] or 0) + 1
	generationsByUserId[player.UserId] = generation
	state = {
		Player = player,
		Session = session,
		Generation = generation,
		Status = "WaitingForProfile",
		Restoring = false,
		BaseWaitScheduled = false,
	}
	states[player] = state
	return state
end

local function scheduleBaseDeadline(state: any)
	if state.BaseWaitScheduled then
		return
	end
	state.BaseWaitScheduled = true
	deps().Delay(BASE_WAIT_DEADLINE_SECONDS, function()
		if
			current(state)
			and state.Status == "WaitingForBase"
			and deps().Base:GetAssignment(state.Player) == nil
		then
			setStatus(state, "Blocked", "NO_BASE_AVAILABLE")
			pcall(function()
				state.Player:Kick(
					"No player base is available in this server. Please try another server."
				)
			end)
		end
	end)
end

function PlayerWorldLifecycle:TryRestoreWorld(player: Player): any
	local d = deps()
	if player.Parent ~= Players then
		return { ok = false, code = "PLAYER_NOT_CONNECTED" }
	end
	if d.Profile:GetStatus(player) ~= "Ready" then
		local existing = states[player]
		if existing then
			setStatus(existing, "WaitingForProfile", "PROFILE_NOT_READY")
		end
		return { ok = false, code = "PROFILE_NOT_READY" }
	end
	local state = stateFor(player)
	if state == nil or not current(state) then
		return { ok = false, code = "STALE_SESSION" }
	end
	if state.Status == "Ready" then
		local readyAssignment = d.Base:GetAssignment(player)
		local readyCart = if d.CartEnabled then d.Cart:GetCart(player) else nil
		if
			readyAssignment ~= nil
			and d.Base:IsCurrentAssignment(readyAssignment)
			and sameAssignment(d.Storage:GetBindingHandle(player), readyAssignment)
			and (not d.CartEnabled or readyCart == state.Cart)
		then
			return { ok = true, code = "ALREADY_READY", generation = state.Generation }
		end
		setStatus(state, "WaitingForBase", "BINDING_CHANGED")
	end
	if state.Status == "Closing" or state.Status == "Closed" or state.Status == "Blocked" then
		return { ok = false, code = state.Code or string.upper(state.Status) }
	end
	if state.Restoring then
		return { ok = false, code = "RESTORING" }
	end
	-- Reserve this restoration attempt before assigning a base. AssignBase may
	-- synchronously publish its assignment event, which is allowed to call this
	-- entry point again; that callback must observe the in-flight attempt.
	state.Restoring = true

	local assignment = d.Base:GetAssignment(player)
	if assignment == nil then
		local _, reason = d.Base:AssignBase(player)
		assignment = d.Base:GetAssignment(player)
		if assignment == nil then
			state.Restoring = false
			setStatus(state, "WaitingForBase", reason or "NO_BASE_AVAILABLE")
			scheduleBaseDeadline(state)
			return { ok = false, code = reason or "NO_BASE_AVAILABLE" }
		end
	end

	state.Assignment = assignment
	setStatus(state, "Restoring")
	log:Info(
		"WorldRestoreStarted userId=%d generation=%d baseId=%s baseGeneration=%d",
		player.UserId,
		state.Generation,
		assignment.BaseId,
		assignment.Generation
	)
	local bound, bindReason = d.Storage:EnsureBound(player, assignment.Base, assignment)
	if not bound then
		state.Restoring = false
		setStatus(state, "Blocked", bindReason or "BASE_BIND_FAILED")
		return { ok = false, code = bindReason or "BASE_BIND_FAILED" }
	end

	local cart = if d.CartEnabled then d.Cart:GetCart(player) else nil
	if d.CartEnabled and cart == nil then
		local spawned, result = pcall(function()
			return d.Cart:SpawnCart(player)
		end)
		if not spawned then
			state.Restoring = false
			setStatus(state, "Blocked", "CART_PREPARATION_FAILED")
			log:Warn("WorldRestoreCancelled userId=%d reason=%s", player.UserId, tostring(result))
			return { ok = false, code = "CART_PREPARATION_FAILED" }
		end
		cart = result
	end

	state.Restoring = false
	if
		not current(state)
		or not d.Base:IsCurrentAssignment(assignment)
		or not sameAssignment(d.Storage:GetBindingHandle(player), assignment)
		or (d.CartEnabled and d.Cart:GetCart(player) ~= cart)
	then
		setStatus(state, "Blocked", "STALE_RESTORATION")
		log:Warn("StaleCallbackRejected userId=%d operation=WorldRestore", player.UserId)
		return { ok = false, code = "STALE_RESTORATION" }
	end
	state.Cart = cart
	setStatus(state, "Ready")
	log:Info(
		"WorldRestoreReady userId=%d generation=%d baseId=%s",
		player.UserId,
		state.Generation,
		assignment.BaseId
	)
	notifyReady(player)
	return { ok = true, code = "READY", generation = state.Generation }
end

function PlayerWorldLifecycle:GetStatus(player: Player): string
	local state = states[player]
	return if state then state.Status else "WaitingForProfile"
end

function PlayerWorldLifecycle:IsReady(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.Status == "Ready" and current(state)
end

function PlayerWorldLifecycle:SubscribeReady(callback: (Player) -> ())
	local connection = {}
	readyListeners[connection] = callback
	function connection.Disconnect()
		readyListeners[connection] = nil
	end
	return connection
end

function PlayerWorldLifecycle:SubscribeDiagnostics(callback: (Player, any) -> ())
	local connection = {}
	diagnosticListeners[connection] = callback
	function connection.Disconnect()
		diagnosticListeners[connection] = nil
	end
	return connection
end

function PlayerWorldLifecycle:BeginClosing(player: Player, reason: string)
	local state = states[player]
	if state == nil then
		return
	end
	state.Restoring = false
	setStatus(state, "Closing", reason)
end

function PlayerWorldLifecycle:Start(options: any?): boolean
	if started then
		return true
	end
	started = true
	dependencies = options
	local d = deps()
	table.insert(
		connections,
		d.Profile:SubscribeReady(function(player)
			task.spawn(function()
				self:TryRestoreWorld(player)
			end)
		end)
	)
	baseConnection = d.Base:SubscribeAssignments(function(player)
		task.spawn(function()
			self:TryRestoreWorld(player)
		end)
	end, function(player)
		local state = states[player]
		if state and state.Status ~= "Closing" and state.Status ~= "Closed" then
			setStatus(state, "WaitingForBase", "BASE_REASSIGNED")
		end
		task.defer(function()
			for waitingPlayer, waiting in states do
				if waiting.Status == "WaitingForBase" and waitingPlayer.Parent == Players then
					task.spawn(function()
						self:TryRestoreWorld(waitingPlayer)
					end)
				end
			end
		end)
	end)
	table.insert(
		connections,
		d.Cart.CartSpawned:Connect(function(record)
			local player = Players:GetPlayerByUserId(record.OwnerUserId)
			if player then
				task.defer(function()
					self:TryRestoreWorld(player)
				end)
			end
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			self:BeginClosing(player, "PlayerRemoving")
		end)
	)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:TryRestoreWorld(player)
		end)
	end
	return true
end

function PlayerWorldLifecycle:_ResetForTests()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if baseConnection then
		baseConnection:Disconnect()
		baseConnection = nil
	end
	table.clear(states)
	table.clear(generationsByUserId)
	table.clear(readyListeners)
	table.clear(diagnosticListeners)
	diagnosticSequence = 0
	dependencies = nil
	started = false
end

return PlayerWorldLifecycle
