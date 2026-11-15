--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Http = game:GetService("HttpService")
local Flags = require(RS.Shared.Config.FeatureFlags)
local Environment = require(RS.Shared.Config.Environment)
local Runtime = require(script.Parent.Parent.Utility.CartShieldRuntime)
local Boundary = require(script.Parent.Parent.Utility.CartShieldBaseBoundary)
local Profiles = require(script.Parent.PlayerDataService)
local Carts = require(script.Parent.CartService)
local Cargo = require(script.Parent.CartCargoService)
local Teams = require(script.Parent.ChariotTeamService)
local Ready = require(script.Parent.PlayerWorldLifecycle)
local Bases = require(script.Parent.Parent.Systems.PlayerBaseSystem)
local Regions = require(script.Parent.Parent.Systems.RegionSpawnCatalog)

local Service = {}
Service.__index = Service
local CACHE_LIMIT, CACHE_SECONDS = 64, 120

local function ownBase(owner: Player, record: any): string?
	if not record or not record.Model or not record.Model:IsDescendantOf(Workspace) or not record.Model.PrimaryPart then return nil end
	local assignment = Bases:GetAssignment(owner)
	if not assignment or not Bases:IsCurrentAssignment(assignment) then return nil end
	local zone = Boundary.FindZone(assignment.Base, assignment.BaseId)
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not zone or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return nil end
	if not Boundary.Qualifies(assignment.Base, assignment.BaseId, root.Position, record.Model.PrimaryPart.Position) then return nil end
	return assignment.BaseId .. ":" .. tostring(assignment.Generation) .. ":" .. tostring(record.Generation)
end

local function defaults(): any
	return {
		Now = function() return Workspace:GetServerTimeNow() end,
		Enabled = function() return Flags.EquippedTeamsEnabled and (Environment.MainGameplayEnabled or not Environment.IsProduction) end,
		IsPlayer = function(player) return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players end,
		Session = function(player) return if Profiles:GetStatus(player) == "Ready" then Profiles:GetSessionHandle(player) else nil end,
		OwnerReady = function(owner) return Profiles:GetStatus(owner) == "Ready" and Ready:IsReady(owner) end,
		Capacity = function(owner) local stats = Teams:GetStats(owner.UserId) return stats and stats.shieldCapacity or 0 end,
		Cart = function(owner) return Carts:GetCartRecord(owner) end,
		Player = function(id) return Players:GetPlayerByUserId(id) end,
		CargoRecord = function(cart, slot) return Cargo:GetSlotRecord(cart, slot) end,
		CargoRevision = function(cart) return Cargo:GetCargoRevision(cart) end,
		OwnBase = ownBase,
		ProtectedArea = function(cart, attacker)
			local root = cart.PrimaryPart
			local character = attacker.Character
			local attackerRoot = character and character:FindFirstChild("HumanoidRootPart")
			return not root or Regions.ContainsPosition("REGION_CAMP", root.Position, 20)
				or (attackerRoot and Regions.ContainsPosition("REGION_CAMP", attackerRoot.Position, 20)) == true
		end,
	}
end

function Service.new(dependencies: any?): any
	return setmetatable({ D = dependencies or defaults(), Native = dependencies == nil, States = {}, Connections = {},
		Started = false, Heartbeat = nil, Remote = nil, PollElapsed = 0 }, Service)
end

local function finite(value: any): boolean return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function id(value: any): boolean return type(value) == "string" and #value > 0 and #value <= 128 end
local function integer(value: any): boolean return finite(value) and value >= 1 and value <= 9007199254740991 and value % 1 == 0 end
local function rejected(code: string): any return { accepted = false, protected = false, allowKnockoff = false, consumed = false, code = code } end

-- Phase 10 callbacks must complete synchronously. Reject a yielding validator
-- before any Shield mutation; no client-facing shortcut calls this interface.
local function synchronous(callback: any, context: any): (boolean, any, any)
	local thread = coroutine.create(callback)
	local ok, result, reason = coroutine.resume(thread, context)
	if not ok then return false, nil, "CALLBACK_FAILED" end
	if coroutine.status(thread) ~= "dead" then coroutine.close(thread) return false, nil, "CALLBACK_YIELDED" end
	return true, result, reason
end

function Service:State(owner: any): any?
	local session = self.D.Session(owner)
	if not session or not self.D.OwnerReady(owner) then return nil end
	local state = self.States[owner]
	if not state or state.Generation ~= session.Generation then
		state = { Generation = session.Generation, Runtime = Runtime.Create(self.D.Now(), Http:GenerateGUID(false)),
			Cart = nil, CartGeneration = nil, Busy = false, Cache = {}, CacheOrder = {}, HighWater = {}, FeedbackAt = {} }
		self.States[owner] = state
	end
	return state
end

function Service:Publish(state: any, cart: any)
	if not cart or cart.Parent == nil then return end
	local value = state.Runtime
	local capacity = if value.Enabled then value.Capacity else 0
	local remaining = if value.Enabled then value.Remaining else 0
	-- Revision is written last so observers can take one coherent snapshot.
	cart:SetAttribute("ShieldCapacity", capacity)
	cart:SetAttribute("ShieldRemaining", remaining)
	cart:SetAttribute("ShieldProtectionExpiresAt", value.ProtectionExpiresAt)
	cart:SetAttribute("ShieldLifecycleId", value.LifecycleId)
	cart:SetAttribute("ShieldCartGeneration", state.CartGeneration)
	cart:SetAttribute("ShieldRevision", value.Revision)
end

function Service:Feedback(player: any, state: any, kind: string, message: string, at: number)
	local payload = { kind = kind, message = message, cart = state.Cart, cartGeneration = state.CartGeneration,
		generation = state.Generation, lifecycleId = state.Runtime.LifecycleId, revision = state.Runtime.Revision,
		expiresAt = state.Runtime.ProtectionExpiresAt }
	if self.D.Feedback then self.D.Feedback(player, payload)
	elseif self.Remote and self.D.IsPlayer(player) then self.Remote:FireClient(player, payload) end
	if kind == "Protected" or kind == "Block" then state.FeedbackAt[player] = at end
end

function Service:Reconcile(owner: any): any?
	local state = self:State(owner)
	if not state then return nil end
	local at = self.D.Now()
	local record = self.D.Cart(owner)
	local previousCart = state.Cart
	if previousCart ~= (record and record.Model) and previousCart and previousCart.Parent then
		previousCart:SetAttribute("ShieldProtectionExpiresAt", 0)
		previousCart:SetAttribute("ShieldCapacity", 0)
		previousCart:SetAttribute("ShieldRemaining", 0)
	end
	state.Cart = record and record.Model
	state.CartGeneration = record and record.Generation
	local enabled = self.Started and self.D.Enabled()
	local capacity = if enabled then self.D.Capacity(owner) else state.Runtime.Capacity
	if not finite(capacity) or capacity % 1 ~= 0 or capacity < 0 or capacity > 3 then capacity = 0 end
	local baseKey = if enabled and record then self.D.OwnBase(owner, record) else nil
	local result = Runtime.Reconcile(state.Runtime, at, capacity, enabled, baseKey)
	self:Publish(state, state.Cart)
	if result.refilled then self:Feedback(owner, state, "Refill", "Shield refilled.", at) end
	self:RefreshPolling()
	return state
end

function Service:RefreshPolling()
	if not self.Native then return end
	local relevant = false
	if self.Started and self.D.Enabled() then
		for _, state in self.States do
			if state.Runtime.Capacity > 0 or state.Runtime.ProtectionExpiresAt > 0 then relevant = true break end
		end
	end
	if relevant and not self.Heartbeat then
		self.Heartbeat = Run.Heartbeat:Connect(function(dt)
			self.PollElapsed += dt
			if self.PollElapsed < 0.25 then return end
			self.PollElapsed = 0
			for owner, state in self.States do
				if state.Runtime.Capacity > 0 or state.Runtime.ProtectionExpiresAt > 0 then self:Reconcile(owner) end
			end
		end)
	elseif not relevant and self.Heartbeat then self.Heartbeat:Disconnect() self.Heartbeat = nil self.PollElapsed = 0 end
end

local function prune(state: any, at: number)
	while #state.CacheOrder > 0 do
		local first = state.CacheOrder[1]
		local cached = state.Cache[first]
		if #state.CacheOrder <= CACHE_LIMIT and cached and at - cached.At < CACHE_SECONDS then break end
		table.remove(state.CacheOrder, 1)
		state.Cache[first] = nil
	end
end

function Service:CreateCargoAttackContext(attacker: any, acceptedRequestId: any, source: any): (any?, string?)
	if not integer(acceptedRequestId) or type(source) ~= "table" or type(source.Record) ~= "table"
		or not id(source.Record.ItemId) or not integer(source.Record.AttachmentIndex) then return nil, "INVALID_CONTEXT" end
	local session = self.D.Session(attacker)
	local cart = source.Cart
	if not session or typeof(cart) ~= "Instance" or not cart:IsA("Model") then return nil, "STALE_ATTACKER_OR_CART" end
	local ownerId = cart:GetAttribute("OwnerUserId")
	local owner = type(ownerId) == "number" and self.D.Player(ownerId)
	local record = owner and self.D.Cart(owner)
	if not record or record.Model ~= cart then return nil, "STALE_CART_OR_CARGO" end
	return {
		subject = "CartCargo", attackId = "capture:" .. tostring(acceptedRequestId), attackSequence = acceptedRequestId,
		attacker = attacker, attackerGeneration = session.Generation, cart = cart, cartGeneration = record.Generation,
		cargoSlotId = "Slot" .. tostring(source.Record.AttachmentIndex), cargoItemId = source.Record.ItemId,
		cargoRevision = source.Revision,
	}, nil
end

-- Connected call site: PlayerCombatService.ResolveImpact's accepted fresh
-- cargo-hit branch, before World.CommitFreshRelease and its ejection transaction.
-- The callback owns all
-- shot/target/range/obstruction/cooldown/eligibility/player-protection rules.
-- It is called again at this boundary; the Shield service owns no combat mode.
-- commitKnockoff is invoked at most once and ONLY for ALLOW, in this same
-- non-yielding critical section. Never eject separately after this returns.
function Service:ResolveValidatedCargoAttack(context: any, finalValidate: any, commitKnockoff: any): any
	if not self.Started then return rejected("NOT_STARTED") end
	if type(context) ~= "table" or context.subject ~= "CartCargo" then return rejected("WRONG_SUBJECT") end
	if type(finalValidate) ~= "function" or type(commitKnockoff) ~= "function" then return rejected("INTEGRATION_REQUIRED") end
	if not id(context.attackId) or not integer(context.attackSequence) or not integer(context.attackerGeneration)
		or not integer(context.cartGeneration) or not id(context.cargoItemId) or type(context.cargoSlotId) ~= "string"
		or not context.cargoSlotId:match("^Slot[1-9]%d*$") or #context.cargoSlotId > 16
		or not finite(context.cargoRevision) or context.cargoRevision < 0 or context.cargoRevision % 1 ~= 0 then return rejected("INVALID_CONTEXT") end
	local attacker, cart = context.attacker, context.cart
	if not self.D.IsPlayer(attacker) or typeof(cart) ~= "Instance" or not cart:IsA("Model") then return rejected("INVALID_ATTACKER_OR_CART") end
	local attackerSession = self.D.Session(attacker)
	if not attackerSession or attackerSession.Generation ~= context.attackerGeneration then return rejected("STALE_ATTACKER") end
	local ownerId = cart:GetAttribute("OwnerUserId")
	local owner = if type(ownerId) == "number" then self.D.Player(ownerId) else nil
	if not owner or owner == attacker then return rejected("INELIGIBLE_OWNER") end
	local state = self:Reconcile(owner)
	if not state then return rejected("OWNER_NOT_READY") end
	if state.Busy then return rejected("BUSY") end
	local at = self.D.Now()
	prune(state, at)
	local key = tostring(attacker.UserId) .. ":" .. tostring(context.attackerGeneration)
	local attackKey = key .. ":" .. context.attackId
	if state.Cache[attackKey] then return rejected("DUPLICATE_ATTACK") end
	if context.attackSequence <= (state.HighWater[key] or 0) then return rejected("OLD_ATTACK") end
	local function current(): boolean
		local record = self.D.Cart(owner)
		local session = self.D.Session(owner)
		local shooterSession = self.D.Session(attacker)
		local cargo = self.D.CargoRecord(cart, context.cargoSlotId)
		return self.D.IsPlayer(owner) and self.D.IsPlayer(attacker) and shooterSession ~= nil
			and shooterSession.Generation == context.attackerGeneration and cart:IsDescendantOf(Workspace)
			and cart:GetAttribute("RuntimeCart") == true and record ~= nil and record.Model == cart and record.OwnerUserId == ownerId
			and record.Generation == context.cartGeneration and state.Cart == cart and state.CartGeneration == context.cartGeneration
			and session ~= nil and session.Generation == state.Generation and self.D.OwnerReady(owner)
			and cargo ~= nil and cargo.ItemId == context.cargoItemId and self.D.CargoRevision(cart) == context.cargoRevision
	end
	if not current() then return rejected("STALE_CART_OR_CARGO") end
	if context.safeAreaRejected == true or self.D.ProtectedArea(cart, attacker) then return rejected("PROTECTED_AREA") end
	state.Busy = true
	local called, valid, reason = synchronous(finalValidate, context)
	if not called or valid ~= true then state.Busy = false return rejected(reason or "ATTACK_REJECTED") end
	-- The second identity/safe-area check is adjacent to the Shield decision.
	if not current() or self.D.ProtectedArea(cart, attacker) then state.Busy = false return rejected("SOURCE_CHANGED") end
	at = self.D.Now()
	state.HighWater[key] = context.attackSequence
	state.Cache[attackKey] = { At = at }
	table.insert(state.CacheOrder, attackKey)
	prune(state, at)
	local result
	if not self.D.Enabled() then
		-- Disabling Shield removes protection, never the normal validated combat
		-- path. Keep its spent reserve while the caller commits its own knockoff.
		Runtime.Reconcile(state.Runtime, at, state.Runtime.Capacity, false, nil)
		result = { accepted = true, code = "ALLOW_KNOCKOFF", protected = false, allowKnockoff = true, consumed = false }
	else
		result = Runtime.ResolveAttack(state.Runtime, at)
	end
	if result.allowKnockoff then
		local committed, accepted, failure = synchronous(commitKnockoff, context)
		result.knockoffCommitted = committed and accepted == true
		if not result.knockoffCommitted then result.accepted = false result.code = failure or "KNOCKOFF_REJECTED" end
	end
	state.Busy = false
	self:Publish(state, cart)
	if result.consumed then
		self:Feedback(owner, state, "Block", "Cargo protected!", at)
		self:Feedback(attacker, state, "Block", "Shield blocked your hit.", at)
	elseif result.protected and at - (state.FeedbackAt[attacker] or -math.huge) >= 1 then
		self:Feedback(attacker, state, "Protected", "Shield blocked your hit.", at)
	end
	self:RefreshPolling()
	return result
end

function Service:GetSnapshot(owner: any): any?
	local state = self.States[owner]
	if not state then return nil end
	local value = state.Runtime
	return table.freeze({ capacity = value.Capacity, remaining = value.Remaining, protectedUntil = value.ProtectionExpiresAt,
		revision = value.Revision, lifecycleId = value.LifecycleId, cartGeneration = state.CartGeneration,
		generation = state.Generation, enabled = value.Enabled })
end

function Service:ForgetPlayer(player: any)
	local own = self.States[player]
	if own and own.Cart then
		Runtime.Reconcile(own.Runtime, self.D.Now(), own.Runtime.Capacity, false, nil)
		self:Publish(own, own.Cart)
	end
	self.States[player] = nil
	local prefix = tostring(player.UserId) .. ":"
	for _, state in self.States do
		state.FeedbackAt[player] = nil
		for key in state.HighWater do if key:sub(1, #prefix) == prefix then state.HighWater[key] = nil end end
	end
	self:RefreshPolling()
end

function Service:Start()
	if self.Started then return end
	self.Started = true
	if not self.Native then return end
	local folder = RS:FindFirstChild("Remotes") or Instance.new("Folder") folder.Name = "Remotes" folder.Parent = RS
	local remote = folder:FindFirstChild("CartShieldFeedback") or Instance.new("RemoteEvent")
	assert(remote:IsA("RemoteEvent"), "Shield feedback remote type conflict")
	remote.Name = "CartShieldFeedback" remote.Parent = folder self.Remote = remote
	table.insert(self.Connections, Teams:SubscribeReconciled(function(owner) self:Reconcile(owner) end))
	table.insert(self.Connections, Ready:SubscribeReady(function(owner) self:Reconcile(owner) end))
	table.insert(self.Connections, Bases:SubscribeAssignments(function(owner) task.defer(function() if self.Started then self:Reconcile(owner) end end) end,
		function(owner) local state = self.States[owner] if state then state.Runtime.BaseOccupancyKey = nil end end))
	for _, signal in { Carts.CartSpawned, Carts.CartDespawned } do
		table.insert(self.Connections, signal:Connect(function(record)
			local owner = self.D.Player(record.OwnerUserId)
			if owner then task.defer(function() if self.Started then self:Reconcile(owner) end end) end
		end))
	end
	table.insert(self.Connections, Players.PlayerRemoving:Connect(function(player) self:ForgetPlayer(player) end))
	for _, record in Carts:GetCartRecords() do local owner = self.D.Player(record.OwnerUserId) if owner then self:Reconcile(owner) end end
end

function Service:Stop()
	self.Started = false
	for _, connection in self.Connections do connection:Disconnect() end table.clear(self.Connections)
	for _, state in self.States do
		Runtime.Reconcile(state.Runtime, self.D.Now(), state.Runtime.Capacity, false, nil)
		self:Publish(state, state.Cart)
	end
	self:RefreshPolling()
end

return Service.new()
