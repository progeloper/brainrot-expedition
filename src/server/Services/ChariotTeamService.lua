--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MaterialPolicy = require(RS.Shared.Utility.EnvironmentStudMaterialPolicy)
local Http = game:GetService("HttpService")
local Run = game:GetService("RunService")
local Rules = require(RS.Shared.Utility.ChariotTeamRules)
local Config = require(RS.Shared.Config.ChariotTeam)
local Effects = require(RS.Shared.Config.ChariotEffectDefinitions)
local Catalog = require(RS.Shared.Config.BrainrotCatalog)
local Phase12Rules = require(RS.Shared.Utility.Phase12Rules)
local Progression = require(RS.Shared.Utility.Phase13Rules)
local CartsConfig = require(RS.Shared.Config.Carts)
local Safety = require(RS.Shared.Config.CartMovementSafety)
local Profile = require(script.Parent.PlayerDataService)
local Carts = require(script.Parent.CartService)
local Storage = require(script.Parent.Parent.Systems.BaseStorageSystem)
local Regions = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
local WorldReady = require(script.Parent.PlayerWorldLifecycle)
local Carry = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
local Service = {}
local gateReader = nil
function Service:ConfigureGateAccess(reader)
	gateReader = reader
end
local clock = os.clock
local states = {}
local connections = {}
local started = false
local remote
local updates
local reconciledListeners = {}
function Service:SubscribeReconciled(callback)
	assert(type(callback) == "function", "Team reconciliation observer must be a function")
	local connection = {}
	reconciledListeners[connection] = callback
	function connection.Disconnect()
		reconciledListeners[connection] = nil
	end
	return connection
end
local function disconnectShield(s)
	if s.shieldConnection then
		s.shieldConnection:Disconnect()
		s.shieldConnection = nil
	end
end
local function ensureRemote(class, name)
	local folder = RS:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = RS
	local r = folder:FindFirstChild(name) or Instance.new(class)
	assert(r.ClassName == class, "Remote class conflict")
	r.Name = name
	r.Parent = folder
	return r
end
local function state(player)
	local h = Profile:GetSessionHandle(player)
	if not h then
		return nil
	end
	local s = states[player]
	if not s or s.session ~= h.Generation then
		if s then
			disconnectShield(s)
		end
		s = {
			session = h.Generation,
			revision = 0,
			rosterRevision = 0,
			signature = "",
			rosterSignature = "",
			stats = Rules.Calculate({}),
			entries = {},
			cache = {},
			order = {},
			buckets = {},
			cart = nil,
			stationarySince = nil,
		}
		states[player] = s
	end
	return s
end
local function roster(data)
	local rows = {}
	local entries = {}
	local t = data.ChariotTeam
	local valid = Rules.Validate(t)
	local assigned = {}
	if valid then
		for i = 1, 6 do
			local id = t.Assignments[tostring(i)]
			if id then
				assigned[id] = i
			end
		end
	end
	for i = 1, Progression.GetCapacity(data) do
		local slot = data.Base.Slots[tostring(i)]
		local id = slot.brainrotId
		local record = id and data.Collection.BrainrotInstances[id]
		if record then
			local def = Catalog.Get(record.speciesId)
			local power = Rules.Individual(def, record.speciesId)
			local effectDefinition = power.effect and Effects.Get(power.effect)
			table.insert(rows, {
				individualId = id,
				speciesId = record.speciesId,
				name = def and def.displayName or "Unavailable brainrot",
				platform = i,
				classification = power.classification or "Unavailable",
				cps = def and def.cashPerSecond * Phase12Rules.MutationMultiplier(
					Phase12Rules.RecordMutation(record) or "None"
				) or 0,
				mutationId = Phase12Rules.RecordMutation(record) or "None",
				effect = power.effect,
				contribution = power.contribution,
				grant = power.contributorsGranted,
				amplifierTarget = power.amplifierTarget,
				trait = power.trait,
				effectDescription = effectDefinition and effectDefinition.Description,
				rank = power.rank or 0,
				valid = power.valid,
				issue = power.issue,
				equippedSlot = assigned[id],
			})
		end
	end
	if valid then
		for i = 1, math.min(6, 2 + t.PurchasedExtraSlots) do
			local id = t.Assignments[tostring(i)]
			local record = id and data.Collection.BrainrotInstances[id]
			if id and Rules.Platform(data, id) then
				entries[tostring(i)] = {
					individualId = id,
					speciesId = record and record.speciesId or "Unavailable",
					definition = record and Catalog.Get(record.speciesId),
					mutationId = if record then Phase12Rules.RecordMutation(record) or "None" else "None",
				}
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		elseif a.contribution ~= b.contribution then
			return (a.contribution or 0) > (b.contribution or 0)
		elseif a.platform ~= b.platform then
			return a.platform < b.platform
		else
			return a.individualId < b.individualId
		end
	end)
	return rows, entries
end
local function signature(data)
	local t = data.ChariotTeam
	local valid = Rules.Validate(t)
	if not valid then
		return "DISABLED:" .. Http:JSONEncode(t)
	end
	local a = { tostring(t.PurchasedExtraSlots) }
	for i = 1, 6 do
		a[#a + 1] = tostring(t.Assignments[tostring(i)])
	end
	return table.concat(a, "|")
end
local function rosterSignature(data)
	local a = {}
	for i = 1, Progression.GetCapacity(data) do
		local id = data.Base.Slots[tostring(i)].brainrotId
		local r = id and data.Collection.BrainrotInstances[id]
		a[#a + 1] = tostring(id)
			.. ":"
			.. tostring(r and r.speciesId)
			.. ":"
			.. tostring(r and Phase12Rules.RecordMutation(r))
	end
	return table.concat(a, "|")
end
local function plaques(player, data)
	local storage = Storage:GetStorageForPlayer(player)
	if not storage then
		return
	end
	local platforms = Storage:GetRegisteredPlatforms(storage.Base) or {}
	local assigned = {}
	if Rules.Validate(data.ChariotTeam) then
		for i = 1, 6 do
			local id = data.ChariotTeam.Assignments[tostring(i)]
			if id then
				assigned[id] = true
			end
		end
	end
	for _, slot in platforms do
		local platform = slot.Platform
		local id = data.Base.Slots[tostring(slot.Index)].brainrotId
		local show = storage:IsValidPlatformId(slot.Index) and id and assigned[id] or false
		local existing = platform:FindFirstChild("ChariotEquippedPlaque")
		if not show then
			if existing then
				existing:Destroy()
			end
		elseif not existing then
			local plate = Instance.new("Part")
			plate.Name = "ChariotEquippedPlaque"
			plate.Size = Vector3.new(math.min(3.2, platform.Size.X * 0.4), 0.06, 0.65)
			plate.Color = Color3.fromRGB(242, 196, 90)
			plate.Anchored = true
			plate.CanCollide = false
			plate.CanTouch = false
			plate.CanQuery = false
			plate.CastShadow = false
			-- Left front corner; cash uses the established centre/right frontage.
			plate.CFrame = platform.CFrame
				* CFrame.new(-platform.Size.X * 0.27, platform.Size.Y / 2 + 0.045, -platform.Size.Z / 2 + 0.52)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Label"
			gui.Face = Enum.NormalId.Top
			gui.CanvasSize = Vector2.new(440, 92)
			gui.LightInfluence = 0
			gui.MaxDistance = 65
			gui.Parent = plate
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Text = "▰  EQUIPPED"
			text.Font = Enum.Font.GothamBold
			text.TextSize = 62
			text.TextColor3 = Color3.fromRGB(53, 42, 23)
			text.Parent = gui
			local border = Instance.new("UIStroke")
			border.Color = Color3.fromRGB(140, 98, 28)
			border.Thickness = 5
			border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			border.Parent = text
			-- A cuboid cart icon with two square wheels replaces a font-dependent glyph.
			text.Text = "     EQUIPPED"
			for _, v in { { 0.025, 0.25, 0.13, 0.35 }, { 0.035, 0.64, 0.035, 0.17 }, { 0.105, 0.64, 0.035, 0.17 } } do
				local f = Instance.new("Frame")
				f.Position = UDim2.fromScale(v[1], v[2])
				f.Size = UDim2.fromScale(v[3], v[4])
				f.BackgroundColor3 = Color3.fromRGB(53, 42, 23)
				f.BorderSizePixel = 0
				f.Parent = gui
			end
			MaterialPolicy.Apply(plate, Enum.Material.Plastic)
			plate.Parent = platform
			game.CollectionService:AddTag(plate, "ChariotEquippedPlaque")
		end
		if show then
			local p = platform:FindFirstChild("ChariotEquippedPlaque")
			if p then
				if p:IsA("BasePart") then
					MaterialPolicy.Apply(p)
				end
				p:SetAttribute("IndividualId", id)
			end
		end
	end
end
function Service:GetStats(ownerUserId)
	local player = Players:GetPlayerByUserId(ownerUserId)
	local s = player and states[player]
	return s and s.stats
end
-- Current-cart publication is the only source of the live reserve. Preview
-- stats describe maximum capacity, never a refill or a fabricated full bar.
local function shieldSnapshot(cart, stats)
	local fallback =
		{ capacity = stats.shieldCapacity or 0, remaining = 0, protectedUntil = 0, revision = 0, lifecycleId = false }
	if
		not cart
		or not cart.Model
		or cart.Model.Parent == nil
		or cart.Model:GetAttribute("ShieldCartGeneration") ~= cart.Generation
	then
		return fallback
	end
	local model = cart.Model
	local capacity = model:GetAttribute("ShieldCapacity")
	local remaining = model:GetAttribute("ShieldRemaining")
	local expiry = model:GetAttribute("ShieldProtectionExpiresAt")
	local revision = model:GetAttribute("ShieldRevision")
	local lifecycle = model:GetAttribute("ShieldLifecycleId")
	if
		not Rules.Finite(capacity)
		or capacity % 1 ~= 0
		or capacity < 0
		or capacity > Config.EffectCaps.Shield
		or not Rules.Finite(remaining)
		or remaining % 1 ~= 0
		or remaining < 0
		or remaining > capacity
		or not Rules.Finite(expiry)
		or expiry < 0
		or not Rules.Finite(revision)
		or revision % 1 ~= 0
		or revision < 0
		or not Rules.ValidId(lifecycle)
	then
		return fallback
	end
	return {
		capacity = capacity,
		remaining = remaining,
		protectedUntil = expiry,
		revision = revision,
		lifecycleId = lifecycle,
	}
end
function Service:Snapshot(player)
	local data = Profile:GetReadableData(player)
	local s = state(player)
	if not data or not s then
		return nil
	end
	local valid, reason = Rules.Validate(data.ChariotTeam)
	local rows, entries = roster(data)
	local cart = Carts:GetCartRecord(player)
	local assignments = {}
	for i = 1, 6 do
		assignments[tostring(i)] = if valid then data.ChariotTeam.Assignments[tostring(i)] else false
	end
	local baseline = cart and CartsConfig[cart.CartId]
	local performance = cart and cart.PerformanceResult
	local baseSpeed = performance
			and (performance.baseResolvedSpeed or performance.resolvedSpeed / (performance.teamSpeedRatio or 1))
		or 0
	local effective = Rules.Effective({ speed = baseSpeed }, s.stats, { speed = Safety.MaximumTravelSpeed })

	return {
		session = s.session,
		teamRevision = s.revision,
		rosterRevision = s.rosterRevision,
		cartGeneration = cart and cart.Generation,
		cartName = baseline and baseline.DisplayName or "Chariot",
		capacity = if valid then 2 + data.ChariotTeam.PurchasedExtraSlots else 2,
		assignments = assignments,
		rows = rows,
		entries = entries,
		stats = s.stats,
		effective = effective,
		shield = shieldSnapshot(cart, s.stats),
		balance = data.Economy.Balance,
		configVersion = Config.Version,
		disabled = reason,
		baseSpeed = baseSpeed,
		balanceRevision = Config.BalanceRevision,
	}
end
function Service:Reconcile(player, force)
	local data = Profile:GetReadableData(player)
	local s = state(player)
	if not data or not s then
		return
	end
	local sig = signature(data)
	local rsig = rosterSignature(data)
	local teamChanged = sig ~= s.signature
	local rosterChanged = rsig ~= s.rosterSignature
	if teamChanged then
		s.revision += 1
		s.signature = sig
	end
	if rosterChanged then
		s.rosterRevision += 1
		s.rosterSignature = rsig
	end
	if not force and not teamChanged and not rosterChanged then
		return
	end
	local _, entries = roster(data)
	s.entries = entries
	s.stats = Rules.Calculate(entries)
	local cart = Carts:GetCartRecord(player)
	if cart then
		Carts:ReconcileOwnerPerformance(player.UserId, "ChariotTeam")
		local public =
			{ ownerUserId = player.UserId, generation = cart.Generation, revision = s.revision, entries = {} }
		for i = 1, 6 do
			local e = entries[tostring(i)]
			if e then
				table.insert(
					public.entries,
					{ slot = i, individualId = e.individualId, speciesId = e.speciesId, mutationId = e.mutationId }
				)
			end
		end
		cart.Model:SetAttribute("ChariotTeamPublic", Http:JSONEncode(public))
		cart.Model:SetAttribute("TeamReelMultiplier", nil)
		cart.Model:SetAttribute("TeamHitMultiplier", s.stats.hitMultiplier)
		cart.Model:SetAttribute("TeamBurstCapacity", s.stats.burstCapacity)
	end
	plaques(player, data)
	for _, callback in reconciledListeners do
		local ok, failure = pcall(callback, player, s.stats)
		if not ok then
			warn("[Phase9] Team reconciliation observer failed: " .. tostring(failure))
		end
	end
	if updates then
		updates:FireClient(player, { kind = "State", state = self:Snapshot(player) })
	end
end
local function managementPoint(cart)
	local root = cart.PrimaryPart
	local attachment = root and root:FindFirstChild("ManageTeamAttachment")
	return attachment and attachment.WorldPosition
end
function Service:Context(player, expectedGeneration, insideMutation)
	if
		(not insideMutation and not Profile:IsWritable(player))
		or Profile:GetStatus(player) ~= "Ready"
		or not WorldReady:IsReady(player)
	then
		return false, "NOT_READY"
	end
	local cart = Carts:GetCartRecord(player)
	local s = state(player)
	if not cart or not s or (expectedGeneration and cart.Generation ~= expectedGeneration) then
		return false, "WRONG_CART"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local point = managementPoint(cart.Model)
	if
		not humanoid
		or humanoid.Health <= 0
		or humanoid.SeatPart
		or not hrp
		or not point
		or Carry.IsCarrying(player)
	then
		return false, "CONTEXT_LOST"
	end
	if
		(hrp.Position - point).Magnitude > 12
		or not Regions.ContainsPosition("REGION_CAMP", hrp.Position, 20)
		or not Regions.ContainsPosition("REGION_CAMP", cart.Model.PrimaryPart.Position, 20)
	then
		return false, "CONTEXT_LOST"
	end
	if
		cart.Model.PrimaryPart.AssemblyLinearVelocity.Magnitude > 1
		or not s.stationarySince
		or clock() - s.stationarySince < 0.25
	then
		return false, "CONTEXT_LOST"
	end
	return true, nil
end
local function rate(s, kind)
	local tuning = if kind == "Buy" then { 1, 1 } elseif kind == "Open" or kind == "Refresh" then { 3, 2 } else { 6, 3 }
	local now = clock()
	local b = s.buckets[kind == "Buy" and "Buy" or (kind == "Open" or kind == "Refresh") and "Read" or "Edit"]
	local key = if kind == "Buy" then "Buy" elseif kind == "Open" or kind == "Refresh" then "Read" else "Edit"
	if not b then
		b = { tokens = tuning[1], at = now }
		s.buckets[key] = b
	end
	b.tokens = math.min(tuning[1], b.tokens + (now - b.at) * tuning[2])
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end
local allowed = {
	operation = true,
	requestId = true,
	session = true,
	cartGeneration = true,
	expectedTeamRevision = true,
	slot = true,
	individualId = true,
	expectedIndividualId = true,
	configVersion = true,
}
local function payloadValid(p)
	if type(p) ~= "table" then
		return false
	end
	local count = 0
	for k, v in p do
		count += 1
		if
			not allowed[k]
			or count > 9
			or (type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean")
			or (type(v) == "string" and (#v > 128 or v:find("%c")))
			or (type(v) == "number" and not Rules.Finite(v))
		then
			return false
		end
	end
	return ({ Open = true, Refresh = true, Close = true, Equip = true, Replace = true, Unequip = true, Buy = true })[p.operation]
		== true
end
function Service:Request(player, p)
	if not payloadValid(p) then
		return { ok = false, code = "INVALID_REQUEST" }
	end
	local s = state(player)
	if not s or not Profile:IsWritable(player) then
		return { ok = false, code = "NOT_READY" }
	end
	local function reply(r)
		r.state = self:Snapshot(player)
		return r
	end
	if p.operation == "Close" then
		s.menu = false
		player:SetAttribute("TeamManagementOpen", nil)
		return { ok = true, code = "OK" }
	end
	if p.operation ~= "Open" and p.operation ~= "Close" and (p.session ~= s.session or p.cartGeneration == nil) then
		return reply({ ok = false, code = "STALE_STATE" })
	end
	local fingerprint = Http:JSONEncode({
		p.operation,
		p.session or false,
		p.cartGeneration or false,
		p.expectedTeamRevision or false,
		p.slot or false,
		p.individualId or false,
		p.expectedIndividualId or false,
		p.configVersion or false,
	})
	local cached = Rules.ValidId(p.requestId) and s.cache[p.requestId]
	if cached and clock() - cached.at <= 120 then
		if cached.fingerprint ~= fingerprint then
			return reply({ ok = false, code = "INVALID_REQUEST" })
		end
		return reply({ ok = cached.ok, code = if cached.ok then "ALREADY_APPLIED" else cached.code })
	end
	if not rate(s, p.operation) then
		return reply({ ok = false, code = "RATE_LIMITED" })
	end
	local context, contextCode = self:Context(player, p.cartGeneration)
	if not context then
		return reply({ ok = false, code = contextCode })
	end
	if p.operation == "Open" or p.operation == "Refresh" then
		s.menu = true
		player:SetAttribute("TeamManagementOpen", true)
		return reply({ ok = true, code = "OK" })
	end
	if not Rules.ValidId(p.requestId) or not Rules.Finite(p.slot) or p.slot % 1 ~= 0 or p.slot < 1 or p.slot > 6 then
		return reply({ ok = false, code = "INVALID_REQUEST" })
	end
	local result = Profile:CommitMutation(player, function(data)
		local current, code = self:Context(player, p.cartGeneration, true)
		if not current then
			return false, { ok = false, code = code }
		end
		local valid, reason = Rules.Validate(data.ChariotTeam)
		if not valid then
			return false, { ok = false, code = reason }
		end
		if p.operation == "Buy" then
			local r = Rules.Buy(data, p.slot, p.configVersion, function(d, cost)
				return Currency:PrepareSpend(d, cost)
			end)
			return r.committed == true, r
		end
		if p.expectedTeamRevision ~= s.revision then
			return false, { ok = false, code = "STALE_STATE" }
		end
		local team = data.ChariotTeam
		local key = tostring(p.slot)
		local outgoing = team.Assignments[key]
		if p.slot > 2 + team.PurchasedExtraSlots then
			return false, { ok = false, code = "SLOT_LOCKED" }
		end
		if p.operation == "Unequip" then
			if outgoing == false then
				return false, { ok = true, code = "ALREADY_APPLIED" }
			end
			if p.expectedIndividualId ~= outgoing then
				return false, { ok = false, code = "STALE_STATE" }
			end
			team.Assignments[key] = false
			return true, { ok = true, code = "OK" }
		end
		if p.operation == "Equip" and outgoing ~= false then
			return false, { ok = false, code = "STALE_STATE" }
		end
		if p.operation == "Replace" and (outgoing == false or outgoing ~= p.expectedIndividualId) then
			return false, { ok = false, code = "STALE_STATE" }
		end
		if not Rules.ValidId(p.individualId) then
			return false, { ok = false, code = "INVALID_REQUEST" }
		end
		local record = data.Collection.BrainrotInstances[p.individualId]
		if not record then
			return false, { ok = false, code = "NOT_OWNED" }
		end
		if not Rules.Platform(data, p.individualId) then
			return false, { ok = false, code = "NOT_ON_PLATFORM" }
		end
		for i = 1, 6 do
			if team.Assignments[tostring(i)] == p.individualId then
				return false, { ok = false, code = "ALREADY_EQUIPPED" }
			end
		end
		local raw = Rules.Individual(Catalog.Get(record.speciesId), record.speciesId)
		if not raw.valid then
			return false, { ok = false, code = "CATALOGUE_UNAVAILABLE" }
		end
		team.Assignments[key] = p.individualId
		return true, { ok = true, code = "OK" }
	end)
	s.cache[p.requestId] = { fingerprint = fingerprint, ok = result.ok, code = result.code, at = clock() }
	table.insert(s.order, p.requestId)
	while #s.order > 64 do
		local old = table.remove(s.order, 1)
		s.cache[old] = nil
	end
	if result.committed then
		if p.operation == "Buy" then
			Currency:ObserveCommittedSpend(player, result, "ChariotSlot" .. p.slot)
		end
		Currency:SyncBalance(player)
		self:Reconcile(player, false)
	end
	return reply(result)
end
local function setupCart(player, s, record)
	if s.cart == record.Model then
		return
	end
	disconnectShield(s)
	s.cart = record.Model
	s.stationarySince = nil
	local observedCart = record.Model
	local observedSession = s.session
	local observedGeneration = record.Generation
	s.shieldConnection = observedCart:GetAttributeChangedSignal("ShieldRevision"):Connect(function()
		local current = Carts:GetCartRecord(player)
		if
			updates
			and states[player] == s
			and s.session == observedSession
			and current
			and current.Model == observedCart
			and current.Generation == observedGeneration
		then
			updates:FireClient(player, { kind = "State", state = Service:Snapshot(player) })
		end
	end)
	local root = record.Model.PrimaryPart
	local a = root:FindFirstChild("ManageTeamAttachment")
	if not a then
		a = Instance.new("Attachment")
		a.Name = "ManageTeamAttachment"
		a.Position = Vector3.new(-5, 1, 1)
		a.Parent = root
	end
	local prompt = a:FindFirstChild("ManageTeam")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ManageTeam"
		prompt.ActionText = "Manage Team"
		prompt.ObjectText = "Chariot"
		prompt.KeyboardKeyCode = Enum.KeyCode.T
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = a
		game.CollectionService:AddTag(prompt, "ChariotTeamPrompt")
		prompt.Triggered:Connect(function(who)
			if who == player then
				local r = Service:Request(who, { operation = "Open" })
				if r.ok then
					updates:FireClient(who, { kind = "Open", state = r.state })
				else
					updates:FireClient(who, { kind = "Error", code = r.code })
				end
			end
		end)
	end
	Service:Reconcile(player, true)
end
function Service:Start()
	if started then
		return
	end
	started = true
	local configuration = Rules.ValidateSpeciesEffects()
	for _, issue in configuration.errors do
		warn("[Phase9] " .. tostring(issue.speciesId) .. ": " .. issue.code .. " " .. issue.message)
	end
	remote = ensureRemote("RemoteFunction", "ChariotTeamRequest")
	updates = ensureRemote("RemoteEvent", "ChariotTeamUpdate")
	remote.OnServerInvoke = function(player, p)
		return self:Request(player, p)
	end
	Carts:ConfigureTeamStats(function(owner)
		return self:GetStats(owner)
	end)
	table.insert(
		connections,
		Profile:SubscribeMutations(function(player, before, after)
			if signature(before) ~= signature(after) or rosterSignature(before) ~= rosterSignature(after) then
				self:Reconcile(player, false)
			end
		end)
	)
	local function bound(player)
		if not Profile:IsWritable(player) then
			return
		end
		Profile:CommitMutation(player, function(data)
			local migrated = Rules.Migrate(data)
			local repair = Rules.Repair(data)
			if repair.disabled then
				warn("[Phase9] Equipment disabled; repair needed: " .. repair.disabled)
			end
			if repair.changed then
				warn("[Phase9] Assignment repairs: " .. Http:JSONEncode(repair.repairs))
			end
			return migrated or repair.changed, { ok = true, code = "TEAM_RESTORED" }
		end)
		self:Reconcile(player, true)
	end
	Storage:ObserveStorage({
		OnBound = bound,
		OnCommitted = function(player)
			self:Reconcile(player, true)
		end,
		OnReleasing = function(_player, storage)
			for _, slot in Storage:GetRegisteredPlatforms(storage.Base) or {} do
				local plate = slot.Platform:FindFirstChild("ChariotEquippedPlaque")
				if plate then
					plate:Destroy()
				end
			end
		end,
	})
	table.insert(connections, WorldReady:SubscribeReady(bound))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			if states[player] then
				disconnectShield(states[player])
			end
			states[player] = nil
		end)
	)
	local elapsed = 0
	table.insert(
		connections,
		Run.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.1 then
				return
			end
			elapsed = 0
			for _, player in Players:GetPlayers() do
				local s = state(player)
				local record = Carts:GetCartRecord(player)
				if s and record then
					setupCart(player, s, record)
					if gateReader and clock() >= (s.nextGateRefresh or 0) then
						s.nextGateRefresh = clock() + 0.25
						local access = gateReader(record.Model)
						local encoded = Http:JSONEncode(access)
						if encoded ~= s.gateSignature or record.Model:GetAttribute("ChariotGateAccess") ~= encoded then
							s.gateSignature = encoded
							record.Model:SetAttribute("ChariotGateAccess", encoded)
						end
					end
					if record.Model.PrimaryPart.AssemblyLinearVelocity.Magnitude <= 1 then
						s.stationarySince = s.stationarySince or clock()
					else
						s.stationarySince = nil
					end
					if s.menu and not self:Context(player, record.Generation) then
						s.menu = false
						player:SetAttribute("TeamManagementOpen", nil)
						updates:FireClient(player, { kind = "Close", code = "CONTEXT_LOST" })
					end
				elseif s then
					disconnectShield(s)
					s.cart = nil
					s.stationarySince = nil
					if s.menu then
						s.menu = false
						player:SetAttribute("TeamManagementOpen", nil)
						updates:FireClient(player, { kind = "Close", code = "CONTEXT_LOST" })
					end
				end
			end
		end)
	)
end
function Service:_TestSetClock(provider)
	assert(not started, "Test clock cannot replace a running server clock")
	clock = provider
end
function Service:Destroy()
	for _, c in connections do
		c:Disconnect()
	end
	for _, s in states do
		disconnectShield(s)
	end
	table.clear(connections)
	table.clear(states)
	table.clear(reconciledListeners)
	started = false
	clock = os.clock
end
function Service:Diagnostics(player)
	local s = states[player]
	return s and { state = self:Snapshot(player), requests = #s.order, menu = s.menu } or nil
end
return Service
