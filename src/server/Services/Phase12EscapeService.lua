--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config.Phase12)
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Runtime = require(script.Parent.Parent.Utility.Phase12EscapeRuntime)
local Service = {}
local deps: any = nil
local connection: RBXScriptConnection? = nil
local random = Random.new()
local retries: { [string]: number } = {}
local resetPausedRecords: { [number]: any } = {}
local diagnostics = { Armed = 0, Committed = 0, PreparationFailures = 0, Warnings = 0 }
local function now()
	return if deps and deps.Now then deps.Now() else Workspace:GetServerTimeNow()
end
local function getPlayers()
	return if deps and deps.GetPlayers then deps.GetPlayers() else Players:GetPlayers()
end
local function configFor(record)
	local definition = Catalog.Get(record.BrainrotId)
	return if definition then Config.EscapeByRarity[definition.tier] else nil
end
local function replace(record, state)
	return deps.World.UpdatePhase12State(record, function(current)
		for key, value in state do
			current[key] = value
		end
		current.EscapeDeadline = state.EscapeDeadline
		current.EscapeRemainingSeconds = state.EscapeRemainingSeconds
		current.ResetPausedGeneration = state.ResetPausedGeneration
		return true
	end)
end
local function present(model, state, config)
	if not model or model.Parent == nil then
		return
	end
	model:SetAttribute("Phase12CapturedOnce", state.CapturedOnce)
	model:SetAttribute("Phase12EscapeDeadline", state.EscapeDeadline)
	model:SetAttribute("Phase12EscapeWarningSeconds", config.WarningSeconds)
	model:SetAttribute("Phase12EscapeRemainingJumps", math.max(0, state.EscapeMaxAttempts - state.EscapeAttemptsUsed))
	model:SetAttribute("Phase12EscapeGeneration", state.EscapeGeneration)
end
function Service:OnPickup(_player, record, visual)
	if not deps then
		return
	end
	local state = deps.World.GetPhase12State(record)
	local config = configFor(record)
	if not state or not config or state.Retired then
		return
	end
	local nextState = Runtime.Pickup(state, config, now(), function()
		return random:NextNumber()
	end)
	if nextState.EscapeGeneration ~= state.EscapeGeneration then
		diagnostics.Armed += 1
	end
	state = replace(record, nextState)
	if state then
		present(visual, state, config)
	end
end
local function exact(source)
	if source.Kind == "Carried" then
		local current = deps.Interaction.GetCarriedState(source.Player)
		return current and current.Record == source.Record and not current.Busy and not current.Returning
	end
	return source.Cart.Parent ~= nil
		and deps.Cargo:GetCargoRevision(source.Cart) == source.Revision
		and deps.Cargo:GetSlotRecord(source.Cart, source.SlotId) == source.Record
end
local function canRelease(source)
	if not deps.WorldService then
		return true
	end
	local position = if source.Kind == "Cargo"
		then source.Cart:GetPivot().Position
		elseif
			source.Player.Character and source.Player.Character:FindFirstChild("HumanoidRootPart")
		then source.Player.Character.HumanoidRootPart.Position
		else nil
	if not position then
		return false
	end
	return deps.WorldService:CanCommit(nil, position, source.Player)
end
local function release(source, state, at)
	local record = source.Record
	if not exact(source) then
		return false, "SOURCE_CHANGED"
	end
	local nextState = Runtime.CommitJump(state, at, state.MaxHp)
	if not nextState then
		return false, "NOT_DUE"
	end
	local function validate()
		local current = deps.World.GetPhase12State(record)
		return exact(source)
			and current
			and not current.Retired
			and current.EscapeGeneration == state.EscapeGeneration
			and current.EscapeAttemptsUsed == state.EscapeAttemptsUsed
			and canRelease(source)
	end
	local model, reason
	if source.Kind == "Carried" then
		local token
		token, reason = deps.Interaction.PrepareHeldRelease(source.Player, record.ItemId)
		if not token then
			return false, reason
		end
		-- PrepareHeldRelease owns the carry Busy lock. Revalidate its immutable
		-- identity and attempt generation inside that owner's commit, not its lock.
		local committed
		committed, reason, model = deps.Interaction.CommitHeldRelease(token, function()
			local current = deps.World.GetPhase12State(record)
			if
				not current
				or current.Retired
				or current.EscapeGeneration ~= state.EscapeGeneration
				or current.EscapeAttemptsUsed ~= state.EscapeAttemptsUsed
				or not canRelease(source)
			then
				return false
			end
			return replace(record, nextState) ~= nil
		end)
		if not committed then
			return false, reason
		end
	else
		local origin = if source.Visual and source.Visual.Parent
			then source.Visual:GetPivot()
			else source.Cart:GetPivot()
		local token
		token, reason = deps.World.PrepareFreshRelease(
			record,
			origin,
			if source.Visual then { source.Visual } else {},
			nil,
			source.Cart
		)
		if not token then
			return false, reason
		end
		local transfer
		model, reason = deps.World.CommitFreshRelease(token, function()
			if not validate() then
				return false
			end
			transfer = deps.Cargo:DetachSlotForTransfer(source.Cart, source.SlotId, record.ItemId)
			if not transfer then
				return false
			end
			if not replace(record, nextState) then
				deps.Cargo:RestoreTransfer(source.Cart, transfer)
				transfer = nil
				return false
			end
			return true
		end)
		if not model then
			deps.World.DiscardFreshRelease(token)
			return false, reason
		end
		assert(deps.Cargo:FinalizeTransfer(source.Cart, transfer), "Self-release cargo finalization failed")
	end
	model:SetAttribute("Phase12CapturedOnce", true)
	model:SetAttribute("Phase12RemainingHp", nextState.MaxHp)
	retries[record.ItemId] = nil
	diagnostics.Committed += 1
	if deps.Events then
		deps.Events:Broadcast(
			"Escape",
			record,
			source.Player,
			{
				position = model:GetPivot().Position,
				ownerOnly = true,
				landingPosition = model:GetPivot().Position,
				remainingJumps = nextState.EscapeMaxAttempts - nextState.EscapeAttemptsUsed,
				generation = nextState.EscapeGeneration,
				cueUntil = at + Config.Presentation.EscapeCueSeconds,
			}
		)
	end
	return true, nil
end
function Service:Step(at: number?)
	if not deps then
		return
	end
	local time = at or now()
	local sources, seen = {}, {}
	for _, player in getPlayers() do
		local carried = deps.Interaction.GetCarriedState(player)
		if carried then
			table.insert(
				sources,
				{
					Kind = "Carried",
					Player = player,
					Record = carried.Record,
					Visual = carried.Visual,
					Busy = carried.Busy or carried.Returning,
				}
			)
		end
		local cart = deps.Cart:GetCart(player)
		if cart then
			for _, source in deps.Cargo:GetTransportSources(cart) do
				source.Player = player
				source.Kind = "Cargo"
				table.insert(sources, source)
			end
		end
	end
	local due, focus = {}, {}
	for _, source in sources do
		local record = source.Record
		seen[record.ItemId] = true
		local state = deps.World.GetPhase12State(record)
		local config = configFor(record)
		if not state or not config or state.Retired or state.ResetPausedGeneration ~= nil then
			continue
		end
		-- Recovery of an already armed attempt preserves the exact remaining time.
		-- A next independent interval is armed only by actual world pickup.
		if state.EscapeDeadline == nil and state.EscapeRemainingSeconds ~= nil and not source.Busy then
			state = replace(
				record,
				Runtime.Pickup(state, config, time, function()
					return random:NextNumber()
				end)
			)
		end
		if not state then
			continue
		end
		present(source.Visual, state, config)
		if state.EscapeDeadline then
			if time >= state.EscapeDeadline - config.WarningSeconds then
				local previous = focus[source.Player]
				if
					not previous
					or state.EscapeDeadline < previous.State.EscapeDeadline
					or (
						state.EscapeDeadline == previous.State.EscapeDeadline
						and record.ItemId < previous.Source.Record.ItemId
					)
				then
					focus[source.Player] =
						{ Source = source, State = state, Count = if previous then previous.Count + 1 else 1 }
				elseif previous then
					previous.Count += 1
				end
			end
			if time >= state.EscapeDeadline and not source.Busy and time >= (retries[record.ItemId] or 0) then
				table.insert(due, { Source = source, State = state })
			end
		end
	end
	-- External releases pause in the existing world registration path. No timer
	-- is cleared during hand/cargo/slot transitions or rolled again after a drop.
	table.sort(due, function(a, b)
		if a.State.EscapeDeadline == b.State.EscapeDeadline then
			return a.Source.Record.ItemId < b.Source.Record.ItemId
		end
		return a.State.EscapeDeadline < b.State.EscapeDeadline
	end)
	for _, entry in due do
		local committed = release(entry.Source, entry.State, time)
		if not committed then
			retries[entry.Source.Record.ItemId] = time + Config.EscapeRetrySeconds
			diagnostics.PreparationFailures += 1
		end
	end
	for _, player in getPlayers() do
		local focused = focus[player]
		player:SetAttribute("Phase12EscapeInstanceId", if focused then focused.Source.Record.ItemId else nil)
		player:SetAttribute("Phase12EscapeDeadline", if focused then focused.State.EscapeDeadline else nil)
		player:SetAttribute(
			"Phase12EscapeRemainingJumps",
			if focused then focused.State.EscapeMaxAttempts - focused.State.EscapeAttemptsUsed else nil
		)
		player:SetAttribute("Phase12EscapeOtherCount", if focused then focused.Count - 1 else nil)
	end
	for id in retries do
		if not seen[id] then
			retries[id] = nil
		end
	end
end
function Service:PauseForReset(cycleId: number, records: any?): boolean
	if not deps then
		return false
	end
	local seen = resetPausedRecords[cycleId] or {}
	resetPausedRecords[cycleId] = seen
	local list = records or {}
	if not records then
		for _, player in getPlayers() do
			local held = deps.Interaction.GetCarriedState(player)
			if held then
				table.insert(list, held.Record)
			end
			local cart = deps.Cart:GetCart(player)
			if cart then
				for _, source in deps.Cargo:GetTransportSources(cart) do
					table.insert(list, source.Record)
				end
			end
		end
	end
	for _, record in list do
		local state = deps.World.GetPhase12State(record)
		if state and not state.Retired then
			local nextState = Runtime.PauseForReset(state, now(), cycleId)
			if replace(record, nextState) then
				seen[record.ItemId] = record
			end
		end
	end
	return true
end
function Service:ResumeAfterReset(cycleId: number): boolean
	if not deps then
		return false
	end
	for _, record in resetPausedRecords[cycleId] or {} do
		local state = deps.World.GetPhase12State(record)
		if state then
			local nextState = Runtime.ResumeAfterReset(state, now(), cycleId)
			if nextState then
				replace(record, nextState)
			end
		end
	end
	resetPausedRecords[cycleId] = nil
	return true
end

function Service:Start(options)
	if deps or not Config.Enabled then
		return false
	end
	deps = options
	if deps.WorldService and deps.WorldService.SetEscapeService then
		deps.WorldService:SetEscapeService(Service)
	end
	random = options.Random or Random.new()
	deps.Interaction.SetPickupObserver(function(...)
		Service:OnPickup(...)
	end)
	local last = -math.huge
	if options.Heartbeat ~= false then
		connection = RunService.Heartbeat:Connect(function()
			local at = now()
			if at - last < Config.EscapeSampleSeconds then
				return
			end
			last = at
			Service:Step(at)
		end)
	end
	return true
end
function Service:Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if deps then
		deps.Interaction.SetPickupObserver(nil)
	end
	deps = nil
	table.clear(retries)
	table.clear(resetPausedRecords)
end
function Service:GetDiagnostics()
	return table.clone(diagnostics)
end
return Service
