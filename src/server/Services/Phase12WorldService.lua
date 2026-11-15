--!nocheck
-- One synchronized server cycle; all economic retirement uses current source
-- owners and the existing ordinary population ledger.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config.Phase12)
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local RegionSpawnCatalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Policy = require(script.Parent.Parent.Utility.Phase13ResetPolicy)
local HuntFlow = require(game:GetService("ReplicatedStorage").Shared.Config.HuntFlow)
local resetWipesOverride: boolean? = nil
local Analytics = require(script.Parent.Phase13AnalyticsService)
local escapeService = nil
local Burrows = require(script.Parent.Parent.Utility.Phase12Burrows)
-- Core Loop V2 (Part H / J2): with the Rush part on, this clock runs BRAINROT RUSH only. It never
-- increments Phase12CycleId, never commits a reset and never publishes reset/rare-wave events, so no
-- interaction, carry, load or compare dialog is cancelled by the clock.
local CoreLoopFlags = require(ReplicatedStorage.Shared.Config.CoreLoopFlags)
local RushClock = require(ReplicatedStorage.Shared.CoreLoop.RushClock)
local rushMode = CoreLoopFlags.Part("Rush")
local rushClockStart = 0
local rushSnapshot = nil
local rushStateObserver = nil

local Service = {}
local dependencies = nil
local started = false
local connection = nil
local cycleId = 0
local deadline = 0
local phase = "Hunt"
local committing = false
local pending = {}
local lastSample = -math.huge
local lastReset = nil
local resetResolveAt = 0
local random = Random.new()
local isolatedResetRequests = 0

local function now()
	return if dependencies and dependencies.Now then dependencies.Now() else Workspace:GetServerTimeNow()
end
local function getPlayers()
	return if dependencies and dependencies.GetPlayers then dependencies.GetPlayers() else Players:GetPlayers()
end
local function publish(kind, payload)
	if dependencies and dependencies.PublishEvent then
		dependencies.PublishEvent(kind, payload)
	end
end
local function setCycleAttributes()
	Workspace:SetAttribute("Phase12CycleId", cycleId)
	-- Rush mode publishes no reset deadline: the world reset clock and the "Rare wave" HUD row read it.
	Workspace:SetAttribute("Phase12ResetDeadline", if rushMode then nil else deadline)
	Workspace:SetAttribute("Phase12ResetPhase", phase)
	Workspace:SetAttribute("Phase12ResetCommitting", committing)
end

local function stepRush(at)
	local snapshot = RushClock.At(at, rushClockStart)
	local previous = rushSnapshot
	rushSnapshot = snapshot
	if previous and previous.state == snapshot.state and previous.rushStartsAt == snapshot.rushStartsAt then
		return
	end
	Workspace:SetAttribute("RushState", snapshot.state)
	Workspace:SetAttribute("RushStartsAt", snapshot.rushStartsAt)
	Workspace:SetAttribute("RushEndsAt", snapshot.rushEndsAt)
	Workspace:SetAttribute("RushMega", snapshot.mega)
	-- Clients read the attributes; the Phase12 event channel only carries record/reset payloads.
	if rushStateObserver then
		pcall(rushStateObserver, snapshot, previous)
	end
end

-- QA only (CoreLoopQA "ForceRush"): moves the RUSH clock origin so `now` lands in the requested state.
-- Never touches Phase12CycleId.
function Service:_ForceRushForQA(kind)
	if not RunService:IsStudio() or not rushMode or not started then
		return false
	end
	local offsets = { Idle = 1, Warning = 181, Countdown = 233, Rush = 241, Mega = 811 }
	local offset = offsets[kind or "Idle"]
	if not offset then
		return false
	end
	rushClockStart = now() - offset
	rushSnapshot = nil
	stepRush(now())
	return true
end

function Service:SetRushObserver(observer)
	rushStateObserver = observer
end

-- Current RUSH snapshot (nil outside rush mode). Read by HuntDirector for the H2 modifiers.
function Service:GetRush()
	return rushSnapshot
end
function Service:IsRushMode()
	return rushMode
end

function Service:IsInCamp(position)
	return typeof(position) == "Vector3" and RegionSpawnCatalog.ContainsPosition(Regions.CampId, position, math.huge)
end
function Service:IsResetCommitting()
	return committing
end
function Service:SetEscapeService(value)
	escapeService = value
end
function Service:IsReturnAuthorized(player, cart, expectedCycleId)
	local job = pending[player]
	return job ~= nil
		and job.CycleId == expectedCycleId
		and job.State.Cart == cart
		and job.State.ReturnCart
		and job.HeldDone
		and job.CargoDone
end
function Service:GetCycleSnapshot()
	return { cycleId = cycleId, deadline = deadline, phase = phase, committing = committing, serverTime = now() }
end
-- Server-only QA boundary. It changes no clock and uses the existing heartbeat,
-- retirement jobs and visual event owner. No client remote calls this method.
function Service:_AccelerateIsolatedResetForTesting(expectedRunId)
	local storage = game:GetService("ServerStorage")
	if
		not RunService:IsStudio()
		or not RunService:IsServer()
		or game.PlaceId ~= 91958083796436
		or game.GameId ~= 10548905405
		or storage:GetAttribute("Phase8TestProfileNamespace") ~= "p13r19multi"
		or Workspace:GetAttribute("Phase13QAIsolationConfirmed") ~= true
	then
		return false, "ISOLATED_NATIVE_TEST_REQUIRED"
	end
	local ok, args = pcall(function()
		return game:GetService("StudioTestService"):GetTestArgs()
	end)
	if
		not ok
		or type(args) ~= "table"
		or args.token ~= "p13r19multi"
		or args.allowIsolatedResetAcceleration ~= true
		or type(expectedRunId) ~= "string"
		or expectedRunId ~= args.runId
		or expectedRunId ~= Workspace:GetAttribute("Phase13QARunId")
	then
		return false, "EXPLICIT_NATIVE_TEST_ARGUMENT_REQUIRED"
	end
	if not started or not connection or (dependencies and dependencies.Now ~= nil) then
		return false, "REAL_CLOCK_SINGLETON_REQUIRED"
	end
	if committing or now() < resetResolveAt then
		return false, "RESET_BOUNDARY_BUSY"
	end
	if isolatedResetRequests >= 10 then
		return false, "ISOLATED_RESET_LIMIT"
	end
	isolatedResetRequests += 1
	local at = now()
	deadline = at
	setCycleAttributes()
	return true,
		{
			cycleIdBefore = cycleId,
			requestedAt = at,
			request = isolatedResetRequests,
			proof = "Explicit isolated acceleration; next normal heartbeat owns the actual reset. Original300second timing not claimed.",
		}
end
function Service:CanCommit(expectedCycleId, _position, player)
	if expectedCycleId ~= nil and expectedCycleId ~= cycleId then
		return false, "RETIRED_CYCLE"
	end
	if player and pending[player] then
		return false, "PLAYER_RESET_PENDING"
	end
	if committing then
		return false, "WORLD_RESET_COMMITTING"
	end
	return true, nil
end

local function ready(player)
	if dependencies.WorldReady then
		return dependencies.WorldReady(player) == true
	end
	local data = dependencies.PlayerDataService
	return (not data or data:IsWritable(player)) and player.Character ~= nil
end
local function characterState(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if not ready(player) or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character, root, humanoid
end
local function cartState(player)
	local record = dependencies.CartService and dependencies.CartService:GetCartRecord(player)
	local cart = record and record.Model
	return if cart and cart.Parent then cart else nil
end
local function classify(player)
	local character, root, humanoid = characterState(player)
	if not character then
		return {
			Ready = false,
			Policy = "H",
			Player = player,
			Cart = cartState(player),
			ForfeitHeld = true,
			ForfeitCargo = false,
			KillCharacter = false,
			ReturnCart = false,
		}
	end
	local cart = cartState(player)
	local playerInCamp = Service:IsInCamp(root.Position)
	local cartInCamp = cart ~= nil and Service:IsInCamp(cart:GetPivot().Position)
	local policy = if not playerInCamp
		then (if cartInCamp then "D" else "A")
		elseif cart and not cartInCamp then "C"
		else "B"
	return {
		Ready = true,
		Policy = policy,
		Player = player,
		Character = character,
		Humanoid = humanoid,
		Cart = cart,
		PlayerInCamp = playerInCamp,
		CartInCamp = cartInCamp,
		ForfeitHeld = true,
		ForfeitCargo = false,
		ReturnCart = cart ~= nil and (not playerInCamp or not cartInCamp),
		KillCharacter = not playerInCamp,
	}
end

local function updateCampInformation(player)
	local state = classify(player)
	if not state.Ready then
		player:SetAttribute("Phase12CampState", "LOADING")
		return
	end
	local label = if not state.PlayerInCamp
		then "RETURN TO CAMP"
		elseif state.Cart and not state.CartInCamp then "CART OUTSIDE CAMP"
		else "IN CAMP"
	player:SetAttribute("Phase12CampState", label)
	if dependencies.ObserveCampState then
		dependencies.ObserveCampState(player, state.PlayerInCamp, cycleId)
	end
end

local function resultOk(result)
	return result == true or (type(result) == "table" and result.ok == true)
end
local function runRetirementUnsafe(job, at)
	if at < job.RetryAt then
		return false
	end
	job.RetryAt = at + 1
	local player = job.State.Player
	if player.Parent ~= Players then
		pending[player] = nil
		return true
	end
	local state = job.State
	if not job.CargoDone then
		local called, result = pcall(function()
			return dependencies.CargoService:BeginResetPreservation(player, job.CycleId)
		end)
		job.CargoDone = called and resultOk(result)
		if not job.CargoDone then
			if not job.CargoPendingObserved then
				job.CargoPendingObserved = true
				local observer = dependencies.Analytics or Analytics
				pcall(
					observer.Record,
					observer,
					player,
					"ResetOutcome",
					1,
					{ category = "ResetCargoPendingJobs", result = "Pending" }
				)
			end
			job.LastError = "CARGO_PRESERVATION_PENDING:" .. tostring(result and result.code)
			return false
		end
		job.PreservedCargo = result.records or {}
		if escapeService then
			escapeService:PauseForReset(job.CycleId, job.PreservedCargo)
		end
	end
	if not job.HeldDone then
		local ok, result = pcall(function()
			return dependencies.InteractionService:RetireForReset(player, state.ForfeitHeld, job.CycleId)
		end)
		job.HeldDone = ok and resultOk(result)
		if job.HeldDone and result.Representations and #result.Representations > 0 then
			publish("ResetRetire", {
				cycleId = job.CycleId,
				eventId = "reset-held:" .. job.CycleId .. ":" .. player.UserId,
				startTime = at,
				representations = result.Representations,
				phase = "Reset",
			})
		end
		if not job.HeldDone then
			job.LastError = "HELD_RETIREMENT_PENDING:" .. tostring(result)
		end
	end
	if not job.HeldDone or not job.CargoDone then
		return false
	end
	-- All forfeited IDs are retired before native Died/CharacterRemoving cleanup.
	if not job.CharacterDone then
		if state.KillCharacter and player.Character == state.Character and state.Humanoid.Parent then
			if dependencies.InteractionService.MarkResetCharacterDeparture then
				dependencies.InteractionService.MarkResetCharacterDeparture(player, state.Character, job.CycleId)
			else
				state.Character:SetAttribute("Phase12ResetGeneration", job.CycleId)
			end
			state.Humanoid.Health = 0
		end
		job.CharacterDone = true
	end
	if not job.RestoreDone then
		if dependencies.RestoreBanked then
			local ok, result = pcall(dependencies.RestoreBanked, player, job.CycleId)
			job.RestoreDone = ok and result ~= false
			if not job.RestoreDone then
				job.LastError = "BANKED_RESTORE_PENDING:" .. tostring(result)
			end
		else
			job.RestoreDone = true
		end
	end
	if not job.CartDone then
		if not state.ReturnCart or not state.Cart or not state.Cart.Parent then
			job.CartDone = true
		elseif dependencies.ReturnCart then
			local ok, result, reason = pcall(dependencies.ReturnCart, player, state.Cart, job.CycleId)
			job.CartDone = ok and (result == true or resultOk(result))
			if not job.CartDone then
				job.LastError = "BASE_RETURN_PENDING:" .. tostring(reason or result)
			end
		else
			job.LastError = "BASE_RETURN_ADAPTER_MISSING"
		end
	end
	if job.RestoreDone and job.CartDone then
		local resumed, resumeResult =
			pcall(dependencies.CargoService.EndResetPreservation, dependencies.CargoService, player, job.CycleId)
		if not resumed or not resultOk(resumeResult) then
			job.LastError = "CARGO_RESUME_PENDING"
			if not job.CargoPendingObserved then
				job.CargoPendingObserved = true
				local observer = dependencies.Analytics or Analytics
				pcall(
					observer.Record,
					observer,
					player,
					"ResetOutcome",
					1,
					{ category = "ResetCargoPendingJobs", result = "Pending" }
				)
			end
			return false
		end
		if not job.CargoPreservedObserved then
			job.CargoPreservedObserved = true
			local observer = dependencies.Analytics or Analytics
			pcall(
				observer.Record,
				observer,
				player,
				"ResetOutcome",
				#job.PreservedCargo,
				{ category = "ResetCargoPreserved", result = "Success" }
			)
		end
		player:SetAttribute("Phase12ResetRetiring", nil)
		pending[player] = nil
		return true
	end
	return false
end

local function runRetirement(job, at)
	-- Streaming preparation may yield in the existing base-return owner. A new
	-- Heartbeat must never run a second transaction for that exact pending job.
	if job.Busy then
		return false
	end
	job.Busy = true
	local ok, result = pcall(runRetirementUnsafe, job, at)
	job.Busy = false
	if not ok then
		job.LastError = "RESET_JOB_PENDING:" .. tostring(result)
		return false
	end
	return result
end

local function commitReset(at)
	committing = true
	local previousCycle = cycleId
	local crossed = math.max(1, math.floor((at - deadline) / Config.ResetPeriod) + 1)
	cycleId += crossed
	deadline += crossed * Config.ResetPeriod
	phase = "Reset"
	resetResolveAt = at + 3
	setCycleAttributes()
	local classifications = {}
	for _, player in getPlayers() do
		local state = classify(player)
		table.insert(classifications, { userId = player.UserId, policy = state.Policy })
		if
			state.Ready
			or state.Cart ~= nil -- Unready owners still have committed cargo whose clock must pause.
			or (
				dependencies.InteractionService.GetCarriedRecord
				and dependencies.InteractionService.GetCarriedRecord(player)
			)
		then
			player:SetAttribute("Phase12ResetRetiring", cycleId)
			-- Retain a coherent failed job; no callback is allowed to replace this
			-- exact generation with fresh sources while it awaits bounded retry.
			pending[player] = {
				State = state,
				CycleId = cycleId,
				RetryAt = 0,
				HeldDone = not state.ForfeitHeld,
				CargoDone = false,
				CharacterDone = false,
				RestoreDone = not state.Ready,
				CartDone = not state.Ready,
			}
		end
	end
	local world = dependencies.Spawner.ResetOutsideCamp(function(position)
		return Service:IsInCamp(position)
	end, cycleId)
	for _, job in table.clone(pending) do
		runRetirement(job, at)
	end
	lastReset = {
		cycleId = cycleId,
		retiredGeneration = previousCycle,
		skippedCycles = crossed - 1,
		world = world,
		classifications = classifications,
		serverTime = at,
	}
	publish("Reset", {
		cycleId = cycleId,
		deadline = deadline,
		startTime = at,
		seed = random:NextInteger(1, 2147483646),
		phase = "Reset",
		retiredGeneration = previousCycle,
		representations = world.Representations or {},
	})
	if next(pending) == nil then
		committing = false
		if escapeService then
			escapeService:ResumeAfterReset(cycleId)
		end
	end
	setCycleAttributes()
end

-- Owner decision (10 Nov 2026): the cycle no longer wipes the world, kills
-- players or forfeits catches. The same clock now starts a rare wave.
local function commitWave(at)
	local previousCycle = cycleId
	local crossed = math.max(1, math.floor((at - deadline) / Config.ResetPeriod) + 1)
	cycleId += crossed
	deadline += crossed * Config.ResetPeriod
	phase = "Reset"
	resetResolveAt = at + 3
	setCycleAttributes()
	local wave = nil
	if type(dependencies.Spawner.BeginRareWave) == "function" then
		local ok, result = pcall(dependencies.Spawner.BeginRareWave, HuntFlow.RareWaveSeconds)
		wave = if ok then result else nil
	end
	Workspace:SetAttribute("RareWaveUntil", at + HuntFlow.RareWaveSeconds)
	lastReset = {
		cycleId = cycleId,
		retiredGeneration = previousCycle,
		skippedCycles = crossed - 1,
		world = { RetiredIds = {}, RetiredCount = 0, Representations = {}, RareWave = wave },
		classifications = {},
		serverTime = at,
	}
	publish("Reset", {
		cycleId = cycleId,
		deadline = deadline,
		startTime = at,
		seed = random:NextInteger(1, 2147483646),
		phase = "Reset",
		retiredGeneration = previousCycle,
		representations = {},
		rareWaveSeconds = HuntFlow.RareWaveSeconds,
	})
end

-- Specs exercise both rollover paths; nil follows HuntFlow.ResetWipesWorld.
function Service:_SetResetWipesWorldForTesting(value: boolean?)
	resetWipesOverride = value
end
function Service:Step(at)
	if not started then
		return
	end
	at = at or now()
	if at - lastSample < 0.1 then
		return
	end
	lastSample = at
	if rushMode then
		stepRush(at)
		for _, player in getPlayers() do
			updateCampInformation(player)
		end
		return
	end
	if at >= deadline and not committing then
		if resetWipesOverride == true or (resetWipesOverride == nil and HuntFlow.ResetWipesWorld) then
			commitReset(at)
		else
			commitWave(at)
		end
	end
	if committing then
		for _, job in table.clone(pending) do
			runRetirement(job, at)
		end
		if next(pending) == nil then
			committing = false
			if escapeService then
				escapeService:ResumeAfterReset(cycleId)
			end
			setCycleAttributes()
		end
	end
	local remaining = deadline - at
	local nextPhase = if remaining <= Config.ResetCriticalSeconds
		then "Critical"
		elseif remaining <= Config.ResetBuildSeconds then "Build"
		elseif remaining <= Config.ResetWarningSeconds then "Warning"
		else "Hunt"
	if phase ~= nextPhase and not committing and at >= resetResolveAt then
		phase = nextPhase
		setCycleAttributes()
		publish(if phase == "Hunt" then "ResetCycle" else "ResetWarning", {
			cycleId = cycleId,
			deadline = deadline,
			startTime = at,
			seed = random:NextInteger(1, 2147483646),
			phase = phase,
		})
	end
	for _, player in getPlayers() do
		updateCampInformation(player)
	end
end

function Service:Start(options)
	if started or not Config.Enabled then
		return false
	end
	assert(
		options and options.Spawner and options.InteractionService and options.CargoService,
		"Phase12 lifecycle owners required"
	)
	dependencies = options
	random = options.Random or Random.new()
	started = true
	isolatedResetRequests = 0
	cycleId = 1
	deadline = now() + Config.ResetPeriod
	phase = "Hunt"
	committing = false
	lastSample = -math.huge
	setCycleAttributes()
	-- Authored shortfall creation is an explicit edit-time operation. Runtime
	-- instances only audit/reuse the saved compact location providers.
	local audit = if rushMode then nil else Burrows.Audit(false)
	if options.Heartbeat ~= false then
		connection = RunService.Heartbeat:Connect(function()
			self:Step()
		end)
	end
	if rushMode then
		rushClockStart = now()
		rushSnapshot = nil
		stepRush(rushClockStart)
		return true, audit
	end
	publish("ResetCycle", {
		cycleId = cycleId,
		deadline = deadline,
		startTime = now(),
		phase = phase,
		seed = random:NextInteger(1, 2147483646),
	})
	return true, audit
end
function Service:GetDiagnostics()
	local jobs = {}
	for player, job in pending do
		table.insert(jobs, {
			userId = player.UserId,
			cycleId = job.CycleId,
			policy = job.State.Policy,
			HeldDone = job.HeldDone,
			CargoDone = job.CargoDone,
			CartDone = job.CartDone,
			RestoreDone = job.RestoreDone,
			LastError = job.LastError,
		})
	end
	return {
		cycle = self:GetCycleSnapshot(),
		lastReset = lastReset,
		pending = jobs,
		burrows = if rushMode then nil else Burrows.GetReport(),
		rush = rushSnapshot,
	}
end
function Service:Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for player, job in pending do
		if dependencies and dependencies.CargoService then
			dependencies.CargoService:EndResetPreservation(player, job.CycleId)
		end
		if escapeService then
			escapeService:ResumeAfterReset(job.CycleId)
		end
		if player.Parent == Players then
			player:SetAttribute("Phase12ResetRetiring", nil)
		end
	end
	table.clear(pending)
	resetWipesOverride = nil
	started = false
	committing = false
	dependencies = nil
end
function Service:GetLocation(position)
	local region = RegionSpawnCatalog.GetRegionAtPosition(position, 8)
	return {
		regionId = region and region.id,
		regionName = region and region.displayName,
		-- Core Loop V2 (J1): no burrow landmarks; the region display name is the landmark.
		landmark = region and (if rushMode then region.displayName else Burrows.Nearest(region.id, position)),
		position = position,
	}
end

-- Pure policy boundary exercises all player/cart split cases without pretending
-- fixture tables are connected players or real engine Camp classification.
function Service._TestSurvivorPolicy(playerInCamp, cartPresent, cartInCamp, worldReady)
	return Policy.Classify(playerInCamp, cartPresent, cartInCamp, worldReady)
end
return Service
