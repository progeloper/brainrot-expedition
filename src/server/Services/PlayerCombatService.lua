--!strict
-- One server-owned deadline state per UserId, shared by the existing accepted
-- shot path. Restrictions survive cart/character changes and quick reconnects.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.Phase10)
local Profile = require(script.Parent.PlayerDataService)
local WorldReady = require(script.Parent.PlayerWorldLifecycle)
local Regions = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Combat = {}
local states: { [number]: any } = {}
local restrictions: { [number]: { [number]: number } } = {}
local physical: { [Player]: any } = {}
local clocks: { [Player]: any } = {}
local generation = 0
local started = false
local connections = {}
local bindings = {}
local deps: any = nil
local Analytics = require(script.Parent.Phase13AnalyticsService)
local theftSummaryAt: { [Player]: number } = {}
local function theftMetric(player: Player, result: string)
	local at = os.clock()
	if result ~= "Success" and at - (theftSummaryAt[player] or -math.huge) < 2 then
		return
	end
	theftSummaryAt[player] = at
	pcall(Analytics.Record, Analytics, player, "TheftOutcome", 1, { category = "Theft", result = result })
end
local phase13Service: any = nil
local optOutRemote: RemoteEvent? = nil
function Combat:ConfigurePhase13Service(service: any)
	phase13Service = service
end
function Combat:IsNewcomerProtected(player): boolean
	local ended = phase13Service and phase13Service:IsNewcomerProtectionEnded(player)
	return not ended and self:GetPlaytime(player) < Config.BeginnerSeconds
end
local function now(): number
	return if deps and deps.Now then deps.Now() else Workspace:GetServerTimeNow()
end
local function ready(player): boolean
	return if deps and deps.Ready then deps.Ready(player) else WorldReady:IsReady(player) and Profile:IsWritable(player)
end
local function state(player): any
	local s = states[player.UserId]
	if not s then
		s = { DazeEnd = 0, ProtectionEnd = 0, Revision = 0, OriginalProtectionEnd = 0 }
		states[player.UserId] = s
	end
	return s
end
local function rootOf(player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end
function Combat:IsCampPosition(position: Vector3): boolean
	if deps and deps.Camp then
		return deps.Camp(position)
	end
	-- Camp uses the same authored floor columns as region/gate authority.
	-- Jumping above natural-spawn floor tolerance never removes PvP safety.
	return Regions.ContainsPosition("REGION_CAMP", position, math.huge)
end
function Combat:IsInCamp(player): boolean
	local root = rootOf(player)
	return root ~= nil and self:IsCampPosition(root.Position)
end
function Combat:IsDazed(player): boolean
	local s = state(player)
	if s.DazeEnd > 0 and now() >= s.DazeEnd then
		self:FinishDaze(player, s.DazeEnd)
	end
	return Config.Enabled and s.DazeEnd > now()
end
local function publish(player, s)
	player:SetAttribute("Phase10DazeEnd", s.DazeEnd)
	player:SetAttribute("Phase10ProtectionEnd", s.ProtectionEnd)
	player:SetAttribute("Phase10DazeRevision", s.Revision)
end
local function restorePhysical(player)
	local old = physical[player]
	if not old then
		return
	end
	physical[player] = nil
	if player.Character == old.Character and old.Humanoid.Parent and old.Humanoid.Health > 0 then
		old.Humanoid.WalkSpeed = old.WalkSpeed
		old.Humanoid.JumpPower = old.JumpPower
		old.Humanoid.JumpHeight = old.JumpHeight
		old.Humanoid.AutoRotate = old.AutoRotate
	end
end
local function disablePhysical(player)
	local character = player.Character
	local h = character and character:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then
		return
	end
	if physical[player] and physical[player].Character ~= character then
		physical[player] = nil
	end
	if not physical[player] then
		physical[player] = {
			Character = character,
			Humanoid = h,
			WalkSpeed = h.WalkSpeed,
			JumpPower = h.JumpPower,
			JumpHeight = h.JumpHeight,
			AutoRotate = h.AutoRotate,
		}
	end
	h.WalkSpeed = 0
	h.JumpPower = 0
	h.JumpHeight = 0
	h.AutoRotate = false
	h.Jump = false
	h:Move(Vector3.zero)
end
function Combat:FinishDaze(player, at: number?): boolean
	local s = state(player)
	if s.DazeEnd == 0 then
		return false
	end
	local ended = at or now()
	s.DazeEnd = 0
	s.ProtectionEnd = math.min(ended + Config.ProtectionSeconds, s.OriginalProtectionEnd)
	restorePhysical(player)
	publish(player, s)
	return true
end
function Combat:GetPlaytime(player): number
	if deps and deps.Playtime then
		return deps.Playtime(player)
	end
	local data = Profile:GetReadableData(player)
	local saved = if data then data.WorldReadyPlaytimeSeconds or 0 else 0
	local c = clocks[player]
	if c and c.Ready and ready(player) then
		local at = now()
		c.Pending += math.max(0, at - c.Last)
		c.Last = at
	end
	return saved + (if c then c.Pending else 0)
end
function Combat:GetProtectionReason(player, ignoreBeginner: boolean?): string?
	if self:IsDazed(player) then
		return "Dazed"
	end
	if self:IsInCamp(player) then
		return "Camp protects players and cargo."
	end
	if not ignoreBeginner and self:IsNewcomerProtected(player) then
		return "Beginner protection."
	end
	if state(player).ProtectionEnd > now() then
		return "Player is protected."
	end
	return nil
end
function Combat:CanAct(player, allowCriticalOwner: boolean?): (boolean, string?)
	if
		not allowCriticalOwner
		and phase13Service
		and type(phase13Service.IsBusy) == "function"
		and phase13Service:IsBusy(player)
	then
		return false, "Saving. Try again after confirmation."
	end
	if self:IsDazed(player) then
		return false, "Dazed"
	end
	return true, nil
end
function Combat:CanAttack(attacker, victim, position: Vector3?, ignoreAttackerBeginner: boolean?): (boolean, string?)
	if not Config.Enabled then
		return false, "PvP is unavailable."
	end
	if attacker == victim then
		return false, "Own possessions are protected."
	end
	if not ready(attacker) or not ready(victim) then
		return false, "Player is not ready."
	end
	local a, v = rootOf(attacker), rootOf(victim)
	local ah = attacker.Character and attacker.Character:FindFirstChildOfClass("Humanoid")
	local vh = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	if not a or not v or not ah or not vh or ah.Health <= 0 or vh.Health <= 0 then
		return false, "Target is unavailable."
	end
	local reason = self:GetProtectionReason(attacker, ignoreAttackerBeginner) or self:GetProtectionReason(victim)
	if reason then
		return false, reason
	end
	if position and self:IsCampPosition(position) then
		return false, "Camp protects players and cargo."
	end
	local row = restrictions[attacker.UserId]
	if row and (row[victim.UserId] or 0) > now() then
		return false, "Wait before attacking the same player again."
	end
	return true, nil
end
local function recordRestriction(attacker, victim, at)
	local row = restrictions[attacker.UserId]
	if not row then
		row = {}
		restrictions[attacker.UserId] = row
	end
	row[victim.UserId] = at + Config.SameVictimSeconds
end
function Combat:CommitDaze(attacker, victim, expectedCharacter): (boolean, string?)
	local ok, reason = self:CanAttack(attacker, victim)
	if not ok or victim.Character ~= expectedCharacter then
		return false, reason or "Stale target."
	end
	local at = now()
	local s = state(victim)
	s.Revision += 1
	s.DazeEnd = at + Config.DazeSeconds
	s.OriginalProtectionEnd = s.DazeEnd + Config.ProtectionSeconds
	victim:SetAttribute("Phase10DazeCharacterGeneration", expectedCharacter:GetAttribute("Phase10CharacterGeneration"))
	recordRestriction(attacker, victim, at)
	disablePhysical(victim)
	publish(victim, s)
	return true, nil
end
function Combat:CommitCargoProtection(attacker, victim): (boolean, string?)
	local ok, reason = self:CanAttack(attacker, victim)
	if not ok then
		return false, reason
	end
	local at = now()
	local s = state(victim)
	s.ProtectionEnd = at + Config.CargoProtectionSeconds
	s.Revision += 1
	recordRestriction(attacker, victim, at)
	publish(victim, s)
	return true, nil
end
local function tickPlaytime(player, at)
	local c = clocks[player]
	if not c then
		c = { Last = at, Pending = 0, Ready = false }
		clocks[player] = c
	end
	if c.Ready and ready(player) then
		c.Pending += math.max(0, at - c.Last)
	end
	c.Last = at
	c.Ready = ready(player)
end
local function flushPlaytime(player): boolean
	tickPlaytime(player, now())
	local c = clocks[player]
	local data = Profile:GetReadableData(player)
	if not c or c.Pending <= 0 or not data then
		return false
	end
	-- Snapshot/departure hooks run inside the existing profile owner. A single
	-- scalar update keeps normal autosave/session/revision semantics.
	data.WorldReadyPlaytimeSeconds = (data.WorldReadyPlaytimeSeconds or 0) + c.Pending
	c.Pending = 0
	return true
end
function Combat:PreparePlaytimeSnapshot(player): boolean
	return flushPlaytime(player)
end
function Combat:Step()
	local at = now()
	for _, player in (if deps and deps.Players then deps.Players() else Players:GetPlayers()) do
		tickPlaytime(player, at)
		local s = state(player)
		if s.DazeEnd > 0 then
			if at >= s.DazeEnd then
				self:FinishDaze(player, s.DazeEnd)
			elseif self:IsInCamp(player) then
				self:FinishDaze(player, at)
			else
				disablePhysical(player)
			end
		end
		player:SetAttribute("Phase10BeginnerProtected", self:IsNewcomerProtected(player))
		local pendingId = s.PendingOptOutId
		if pendingId and phase13Service and phase13Service:IsNewcomerProtectionEnded(player) then
			s.PendingOptOutId = nil
			-- The confirmed critical receipt is the sole ProtectionOptOut producer.
			player:SetAttribute("Phase13ProtectionOptOutPending", nil)
			if optOutRemote then
				optOutRemote:FireClient(player, {
					status = "Saved",
					operationId = pendingId,
					message = "Beginner protection ended. Choose a target and fire again.",
				})
			end
		end
		player:SetAttribute("Phase10InCamp", self:IsInCamp(player))
	end
	for attacker, row in restrictions do
		for victim, deadline in row do
			if deadline <= at then
				row[victim] = nil
			end
		end
		if not next(row) then
			restrictions[attacker] = nil
		end
	end
	for userId, s in states do
		if math.max(s.ProtectionEnd, s.OriginalProtectionEnd) <= at and not Players:GetPlayerByUserId(userId) then
			states[userId] = nil
		end
	end
end
local function bindCharacter(player, character)
	generation += 1
	character:SetAttribute("Phase10CharacterGeneration", generation)
	local s = state(player)
	if s.DazeEnd > now() then
		player:SetAttribute("Phase10DazeCharacterGeneration", generation)
		disablePhysical(player)
	end
	publish(player, s)
end
function Combat:Start()
	if started or not Config.Enabled then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local existing = remotes:FindFirstChild("ProtectionOptOutRequest")
	if not existing then
		existing = Instance.new("RemoteEvent")
		existing.Name = "ProtectionOptOutRequest"
		existing.Parent = remotes
	end
	assert(existing:IsA("RemoteEvent"), "Protection opt-out remote class conflict")
	optOutRemote = existing
	table.insert(
		connections,
		optOutRemote.OnServerEvent:Connect(function(player, request)
			if
				type(request) ~= "table"
				or request.confirm ~= true
				or type(request.operationId) ~= "string"
				or #request.operationId > 128
				or #request.operationId < 8
			then
				return
			end
			if not ready(player) or not phase13Service then
				optOutRemote:FireClient(
					player,
					{ status = "Unavailable", message = "Protection settings are unavailable. Try again." }
				)
				return
			end
			if not self:IsNewcomerProtected(player) then
				optOutRemote:FireClient(player, { status = "Saved", message = "Choose a target and fire again." })
				return
			end
			local own = state(player)
			if own.PendingOptOutId then
				optOutRemote:FireClient(player, { status = "Saving", message = "Saving protection choice…" })
				return
			end
			local ok, result = pcall(phase13Service.EndNewcomerProtection, phase13Service, player, request.operationId)
			if
				not ok
				or (
					type(result) == "table"
					and result.ok == false
					and result.state ~= "Saving"
					and result.status ~= "Saving"
					and result.code ~= "Saving"
					and result.status ~= "Pending"
				)
			then
				optOutRemote:FireClient(
					player,
					{ status = "Unavailable", message = "Your choice could not be saved. Protection remains active." }
				)
				return
			end
			own.PendingOptOutId = request.operationId
			player:SetAttribute("Phase13ProtectionOptOutPending", true)
			optOutRemote:FireClient(
				player,
				{ status = "Saving", operationId = request.operationId, message = "Saving protection choice…" }
			)
		end)
	)
	local function bind(player)
		bindings[player] = {}
		table.insert(
			bindings[player],
			player.CharacterAdded:Connect(function(c)
				bindCharacter(player, c)
			end)
		)
		table.insert(
			bindings[player],
			player.CharacterRemoving:Connect(function()
				physical[player] = nil
			end)
		)
		if player.Character then
			bindCharacter(player, player.Character)
		end
		publish(player, state(player))
	end
	table.insert(connections, Players.PlayerAdded:Connect(bind))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(p)
			physical[p] = nil
			local clock = clocks[p]
			if Profile:GetReadableData(p) == nil and (not clock or clock.Pending == 0) then
				clocks[p] = nil
			end
			for _, c in bindings[p] or {} do
				c:Disconnect()
			end
			bindings[p] = nil
		end)
	)
	for _, p in Players:GetPlayers() do
		bind(p)
	end
	table.insert(
		connections,
		Profile:RegisterSnapshotPreparer(function(p)
			return flushPlaytime(p)
		end)
	)
	table.insert(
		connections,
		Profile:RegisterCloseFinalizer(function(p)
			clocks[p] = nil
		end)
	)
	table.insert(
		connections,
		Profile:RegisterDeparturePreparer(function(p)
			if flushPlaytime(p) then
				Profile:MarkDirty(p)
			end
			return true
		end)
	)
	table.insert(
		connections,
		WorldReady:SubscribeReady(function(p)
			tickPlaytime(p, now())
			clocks[p].Ready = true
		end)
	)
	local elapsed = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < Config.SampleSeconds then
				return
			end
			elapsed = 0
			self:Step()
		end)
	)
end
function Combat:Stop()
	for _, p in Players:GetPlayers() do
		if flushPlaytime(p) and Profile:IsWritable(p) then
			Profile:MarkDirty(p)
		end
	end
	for _, c in connections do
		c:Disconnect()
	end
	for _, list in bindings do
		for _, c in list do
			c:Disconnect()
		end
	end
	for p in physical do
		restorePhysical(p)
	end
	for _, p in Players:GetPlayers() do
		p:SetAttribute("Phase10DazeEnd", 0)
		p:SetAttribute("Phase10ProtectionEnd", 0)
	end
	table.clear(connections)
	table.clear(bindings)
	started = false
end
local transactions: any = nil
function Combat:ConfigureTransactions(options: any)
	transactions = options
end
local function playerById(id): any
	return if deps and deps.PlayerByUserId then deps.PlayerByUserId(id) else Players:GetPlayerByUserId(id)
end
local function playerFromCharacter(model): any
	return if deps and deps.PlayerFromCharacter
		then deps.PlayerFromCharacter(model)
		else Players:GetPlayerFromCharacter(model)
end
local function classifyImpact(part: Instance): any?
	if not transactions then
		return nil
	end
	local cargo = transactions.Cargo:ResolveHit(part)
	if cargo then
		return { Kind = "Cargo", Source = cargo, Victim = playerById(cargo.Cart:GetAttribute("OwnerUserId")) }
	end
	local item: Instance? = part
	while item and item ~= Workspace do
		if item:IsA("Model") then
			if item:GetAttribute("Phase10TargetKind") == "Held" then
				local victim = playerById(item:GetAttribute("OwnerUserId"))
				local record = victim and transactions.Carry.GetCarriedRecord(victim)
				if
					not victim
					or not record
					or record.ItemId ~= item:GetAttribute("ItemId")
					or not item:IsDescendantOf(victim.Character)
				then
					return { Kind = "Protected", Victim = victim }
				end
				if transactions.Banked:ClassifyRecord(victim, record) ~= "FreshUnbanked" then
					return { Kind = "Protected", Victim = victim }
				end
				return { Kind = "Player", Victim = victim }
			end
			local victim = playerFromCharacter(item)
			if victim then
				return { Kind = "Player", Victim = victim }
			end
		end
		item = item.Parent
	end
	return nil
end
local function sameImpact(a, b): boolean
	if not a or not b or a.Kind ~= b.Kind then
		return false
	end
	if a.Kind == "Cargo" then
		return a.Source.Cart == b.Source.Cart and a.Source.Record == b.Source.Record
	end
	return a.Victim == b.Victim
end
local function message(player, text)
	if transactions and transactions.Feedback then
		transactions.Feedback(player, text)
	end
end
-- Called once after the existing accepted camera/muzzle rays and cadence. It
-- terminates the shot even on protection/stale/capacity rejection.
function Combat:ResolveImpact(attacker, context, hit, cameraHit, intent): (boolean, string?, string?)
	if not Config.Enabled or not transactions then
		return false, nil, nil
	end
	local target = classifyImpact(hit.Instance)
	if not target then
		return false, nil, nil
	end
	if target.Kind == "Protected" then
		return true, "ProtectedTarget", "Banked brainrots are protected."
	end
	if not cameraHit or not sameImpact(target, classifyImpact(cameraHit.Instance)) then
		return true, "UnavailableTarget", "Keep the target under the crosshair."
	end
	local requestId = intent.RequestId
	if
		type(requestId) ~= "number"
		or requestId ~= requestId
		or requestId < 1
		or requestId > 9007199254740991
		or requestId % 1 ~= 0
	then
		return true, "StaleTarget", "Stale shot."
	end
	local victim = target.Victim
	if not victim then
		return true, "UnavailableTarget", "Target is unavailable."
	end
	local priorHeld = transactions.Carry.GetCarriedRecord(victim)
	local freshTheft = (target.Kind == "Cargo" and target.Source.Fresh)
		or (priorHeld and transactions.Banked:ClassifyRecord(victim, priorHeld) == "FreshUnbanked")
	if freshTheft and self:IsNewcomerProtected(attacker) then
		local otherwiseEligible = self:CanAttack(attacker, victim, hit.Position, true)
		if otherwiseEligible then
			theftMetric(attacker, "Pending")
			return true, "ProtectionOptOutRequired", "Stealing ends your beginner protection. Continue?"
		end
	end
	local allowed, reason = self:CanAttack(attacker, victim, hit.Position)
	if not allowed then
		if freshTheft then
			theftMetric(attacker, "Denied")
		end
		return true, "ProtectedTarget", reason
	end
	local character = victim.Character
	local held = transactions.Carry.GetCarriedRecord(victim)
	local freshHeld = held and transactions.Banked:ClassifyRecord(victim, held) == "FreshUnbanked"
	local producesTheft = (target.Kind == "Cargo" and target.Source.Fresh) or freshHeld
	if producesTheft and context.Cart and not transactions.Cargo:CanAcceptCargo(context.Cart) then
		return true, "CargoFull", "Make space in your cargo before knocking a catch loose."
	end
	if target.Kind == "Cargo" then
		local source = target.Source
		if self:IsCampPosition(source.Cart:GetPivot().Position) then
			return true, "ProtectedTarget", "Camp protects players and cargo."
		end
		if not source.Fresh then
			return true, "ProtectedTarget", "Banked brainrots are protected."
		end
		if intent.TargetItemId ~= source.Record.ItemId or intent.TargetCartId ~= source.Cart:GetAttribute("CartId") then
			return true, "StaleTarget", "Cargo target changed."
		end
		local token, prepareReason = transactions.World.PrepareFreshRelease(
			source.Record,
			source.Visual:GetPivot(),
			{ source.Visual },
			nil,
			source.Cart
		)
		if not token then
			return true, "UnsafeDrop", "No safe space to release this catch: " .. tostring(prepareReason)
		end
		local transfer
		local model, commitReason
		local function validateSource()
			if not source.Visual:IsDescendantOf(source.Cart) or not source.Cart:IsDescendantOf(Workspace) then
				return false
			end
			local current = transactions.Cargo:ResolveHit(hit.Instance)
			local valid = self:CanAttack(attacker, victim, source.Visual:GetPivot().Position)
			if
				not valid
				or self:IsCampPosition(source.Cart:GetPivot().Position)
				or not current
				or current.Record ~= source.Record
				or current.Cart ~= source.Cart
				or current.Revision ~= source.Revision
				or current.Fresh ~= true
				or victim.Character ~= character
				or (transactions.ValidateContext and not transactions.ValidateContext(attacker, context))
				or (context.Cart and not transactions.Cargo:CanAcceptCargo(context.Cart))
			then
				return false
			end
			return true
		end
		local function commitKnockoff()
			-- World activation owns its existing safe-placement/population rollback.
			-- Shield must decide BEFORE this call: activation registers the prepared
			-- representation before its non-yielding source-commit callback runs.
			model, commitReason = transactions.World.CommitFreshRelease(token, function()
				if not validateSource() then
					return false
				end
				transfer = transactions.Cargo:DetachSlotForTransfer(
					source.Cart,
					"Slot" .. source.Record.AttachmentIndex,
					source.Record.ItemId
				)
				if not transfer then
					return false
				end
				if not self:CommitCargoProtection(attacker, victim) then
					transactions.Cargo:RestoreTransfer(source.Cart, transfer)
					transfer = nil
					return false
				end
				return true
			end)
			if model then
				transactions.Cargo:FinalizeTransfer(source.Cart, transfer)
			end
			return model ~= nil, commitReason
		end
		if transactions.Shield then
			local acceptedId = context.AcceptedRequestId
			if acceptedId ~= requestId then
				transactions.World.DiscardFreshRelease(token)
				return true, "StaleTarget", "Stale accepted shot."
			end
			local shieldContext, contextReason =
				transactions.Shield:CreateCargoAttackContext(attacker, acceptedId, source)
			if not shieldContext then
				transactions.World.DiscardFreshRelease(token)
				return true, "StaleTarget", contextReason
			end
			local decision =
				transactions.Shield:ResolveValidatedCargoAttack(shieldContext, validateSource, commitKnockoff)
			if decision.protected then
				transactions.World.DiscardFreshRelease(token)
				-- The Shield feedback channel owns block messaging. This remains a terminal
				-- accepted shot and never falls through into wild targeting/player daze.
				return true, "CargoShieldBlocked", nil
			end
			if not decision.accepted then
				transactions.World.DiscardFreshRelease(token)
				return true,
					"StaleTarget",
					if decision.code == "DUPLICATE_ATTACK" or decision.code == "OLD_ATTACK" then nil else decision.code
			end
		else
			commitKnockoff()
		end
		if not model then
			transactions.World.DiscardFreshRelease(token)
			return true, "StaleTarget", commitReason or "Cargo target changed."
		end
		if transactions.World.UpdatePhase12State then
			transactions.World.UpdatePhase12State(
				source.Record,
				{ LastReleaseKind = "Theft", LastTheftAttackerUserId = attacker.UserId }
			)
		end
		-- A committed, revalidated source release proves this opportunity existed.
		pcall(Analytics.ObserveLegalTheftAttempt, Analytics, attacker)
		local name = transactions.Name(source.Record.BrainrotId)
		message(victim, name .. " was knocked loose!")
		theftMetric(attacker, "Success")
		return true, "CargoKnockedLoose", name .. " knocked loose — capture it!"
	end
	if intent.TargetPlayerUserId ~= nil and intent.TargetPlayerUserId ~= victim.UserId then
		return true, "StaleTarget", "Player target changed."
	end
	if held then
		local token, prepareReason = transactions.Carry.PrepareHeldRelease(victim, held.ItemId)
		if not token then
			return true, "UnsafeDrop", "No safe space to release this catch: " .. tostring(prepareReason)
		end
		local committed, commitReason = transactions.Carry.CommitHeldRelease(token, function()
			if transactions.ValidateContext and not transactions.ValidateContext(attacker, context) then
				return false
			end
			if context.Cart and freshHeld and not transactions.Cargo:CanAcceptCargo(context.Cart) then
				return false
			end
			return self:CommitDaze(attacker, victim, character)
		end)
		if not committed then
			return true, "StaleTarget", commitReason or "Player target changed."
		end
		if freshHeld and transactions.World.UpdatePhase12State then
			transactions.World.UpdatePhase12State(
				held,
				{ LastReleaseKind = "Theft", LastTheftAttackerUserId = attacker.UserId }
			)
		end
		message(victim, transactions.Name(held.BrainrotId) .. " was knocked loose!")
	else
		if transactions.ValidateContext and not transactions.ValidateContext(attacker, context) then
			return true, "StaleTarget", "Firing context changed."
		end
		local committed, commitReason = self:CommitDaze(attacker, victim, character)
		if not committed then
			return true, "ProtectedTarget", commitReason
		end
	end
	if freshHeld then
		pcall(Analytics.ObserveLegalTheftAttempt, Analytics, attacker)
		theftMetric(attacker, "Success")
	end
	return true, "PlayerDazed", "Player dazed."
end

function Combat:GetDiagnostics(player): any
	local s = state(player)
	return {
		DazeEnd = s.DazeEnd,
		ProtectionEnd = s.ProtectionEnd,
		Playtime = self:GetPlaytime(player),
		Restrictions = restrictions[player.UserId],
	}
end
function Combat:_ConfigureForTests(options)
	deps = options
	table.clear(states)
	table.clear(restrictions)
	table.clear(physical)
	table.clear(clocks)
end
return Combat
