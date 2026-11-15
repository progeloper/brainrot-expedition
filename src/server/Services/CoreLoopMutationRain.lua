--!strict
-- Core Loop V2 K4: Mutation Rain. Once per MEGA RUSH, every PRESENT player (input in the last 300 s, §3) gets
-- one strike at a random moment of the MEGA on a random UNMUTATED brainrot displayed on their base.
-- Outcome Shiny 80% / Golden 18% / Glitched 2% (never Radioactive or Astral).
--
-- Persistence uses the existing durable critical-operation path (Phase13Service:CommitCritical →
-- PlayerDataService:CommitCriticalMutation), so:
--   * it is idempotent per (MEGA id, userId): the operation id is the key and the journal replays it;
--   * income is cut over at the old rate before the change, then the save is requested;
--   * the live base entry adopts the mutation only after the profile holds it (BaseStorage:AdoptCommittedMutation).
-- The individual's existing mutation field is written (record.mutationId / metadata.MutationId and any legacy
-- copies kept equal, as Phase12Progress.Migrate does). No schema change. Discovery maps and Gems are not
-- touched (Gems stay a first-bank reward).
-- Presentation: CoreLoopEvent { kind = "Rain" } to every client (each client shows it within 150 studs, L3.12);
-- the owner also gets a toast. The H4 "MUTATION RAIN!" banner arrives with the banner queue (CP-C).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CoreLoop = require(Shared.Config.CoreLoop)
local CoreLoopFlags = require(Shared.Config.CoreLoopFlags)
local BrainrotCatalog = require(Shared.Config.BrainrotCatalog)
local MutationRoller = require(Shared.CoreLoop.MutationRoller)
local Phase12Progress = require(script.Parent.Parent.Data.Phase12Progress)

local PRESENT_SECONDS = 300 -- §3 present player
local EDGE_SECONDS = 5 -- strike inside the MEGA, not on its first or last seconds
local RETRY_SECONDS = 2
local GRACE_AFTER_MEGA = 30 -- keep retrying a busy profile this long after the MEGA ends
local OPERATION_KIND = "CoreLoopMutationRain"

local Rain = {}

type Strike = { At: number, Key: string, EndsAt: number, Tries: number, Done: boolean }

local deps: any = nil
local started = false
local lastActive: { [Player]: number } = {}
local strikes: { [Player]: Strike } = {}
local megasSeen: { [string]: boolean } = {}
local megaCount = 0
local fxSent: { [string]: boolean } = {}
local presentOverride: boolean? = nil
local stats = {
	Megas = 0,
	Scheduled = 0,
	Struck = 0,
	NotPresent = 0,
	NoneEligible = 0,
	Failed = 0,
	Replayed = 0,
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rng(): Random
	return Random.new()
end

local function remote(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("CoreLoopEvent")
	return if event and event:IsA("RemoteEvent") then event else nil
end

local function isPresent(player: Player): boolean
	if presentOverride ~= nil then
		return presentOverride
	end
	local at = lastActive[player]
	return at ~= nil and now() - at <= PRESENT_SECONDS
end

-- Server-observed input: walking or steering/throttling a seat. The client's throttled input ping
-- (TrainingInput, any InputBegan, at most once per 20 s) is also counted.
local function sampleActivity()
	local t = now()
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local seat = humanoid.SeatPart
			local driving = seat
				and seat:IsA("VehicleSeat")
				and (
					(seat :: VehicleSeat).ThrottleFloat ~= 0
					or (seat :: VehicleSeat).SteerFloat ~= 0
				)
			if humanoid.MoveDirection.Magnitude > 0.1 or driving then
				lastActive[player] = t
			end
		end
	end
end

-- Shiny 80 / Golden 18 / Glitched 2 (CoreLoop.Mutation.Rain.Shares); never Radioactive or Astral.
function Rain.RollOutcome(random: Random): string
	return MutationRoller.RainOutcome(random)
end

-- Unmutated displayed brainrots on the player's base: { platformId, itemId, speciesId }.
local function eligible(player: Player): ({ any }, number)
	local storage = deps.BaseStorageSystem:GetStorageForPlayer(player)
	local list, displayed = {}, 0
	if not storage then
		return list, 0
	end
	for _, platformId in storage:GetPlatformIds() do
		local record = storage:GetPlatformRecord(platformId)
		if record then
			displayed += 1
			if Phase12Progress.MutationId(record) == "None" then
				table.insert(list, {
					PlatformId = platformId,
					ItemId = record.ItemId,
					SpeciesId = record.BrainrotId,
				})
			end
		end
	end
	return list, displayed
end

local function setMutation(record: any, mutationId: string)
	record.mutationId = mutationId
	if type(record.metadata) ~= "table" then
		record.metadata = {}
	end
	record.metadata.MutationId = mutationId
	if record.MutationId ~= nil then
		record.MutationId = mutationId
	end
	local legacy = record.metadata.Mutation
	if type(legacy) == "table" then
		for _, key in { "Id", "MutationId" } do
			if legacy[key] ~= nil then
				legacy[key] = mutationId
			end
		end
	end
end

local function speciesName(speciesId: string): string
	local definition = BrainrotCatalog.Get(speciesId)
	return if definition and type(definition.displayName) == "string"
		then definition.displayName
		else speciesId
end

local function present(player: Player, result: any, operationId: string)
	if fxSent[operationId] then
		return
	end
	fxSent[operationId] = true
	local storage = deps.BaseStorageSystem:GetStorageForPlayer(player)
	local display = storage and storage:GetPlatformDisplay(result.PlatformId)
	local event = remote()
	if not event then
		return
	end
	local name = speciesName(result.SpeciesId)
	event:FireAllClients({
		kind = "Rain",
		model = display,
		position = if display then display:GetPivot().Position else nil,
		mutation = result.MutationId,
		owner = player.DisplayName,
		ownerUserId = player.UserId,
		species = name,
	})
	if player.Parent == Players then
		event:FireClient(player, {
			kind = "Toast",
			text = string.format(
				"MUTATION RAIN! Your %s turned %s!",
				name,
				string.upper(result.MutationId)
			),
			tone = "go",
		})
	end
	if deps.Analytics then
		pcall(deps.Analytics.Record, deps.Analytics, player, "CL_Rain", 1, nil)
	end
end

-- One attempt. Returns true when the strike is resolved (struck, replayed, or nothing to do).
local function attempt(player: Player, strike: Strike): boolean
	local operationId = string.format("CL_RAIN:%s:%d", strike.Key, player.UserId)
	local data = deps.Profile:GetReadableData(player)
	local prior = data
		and data.Phase13
		and data.Phase13.Operations
		and data.Phase13.Operations[operationId]
	if prior then
		stats.Replayed += 1
		return true -- already applied for this MEGA (idempotent across retries and rejoins)
	end
	local list, displayed = eligible(player)
	if #list == 0 then
		stats.NoneEligible += 1
		if displayed > 0 then
			local event = remote()
			if event and player.Parent == Players then
				event:FireClient(player, {
					kind = "Toast",
					text = "All your brainrots are mutated — nice!",
					tone = "go",
				})
			end
		end
		return true
	end
	local random = rng()
	local pick = list[random:NextInteger(1, #list)]
	local mutationId = Rain.RollOutcome(random)
	local storage = deps.BaseStorageSystem:GetStorageForPlayer(player)
	local outcome = deps.Phase13Service:CommitCritical(
		player,
		operationId,
		OPERATION_KIND,
		function(current: any)
			local currentRecord = storage and storage:GetPlatformRecord(pick.PlatformId)
			if not currentRecord or currentRecord.ItemId ~= pick.ItemId then
				return false, { ok = false, code = "RAIN_TARGET_MOVED" }
			end
			local owned = current.Collection and current.Collection.BrainrotInstances[pick.ItemId]
			if type(owned) ~= "table" or Phase12Progress.MutationId(owned) ~= "None" then
				return false, { ok = false, code = "RAIN_TARGET_NOT_ELIGIBLE" }
			end
			setMutation(owned, mutationId)
			return true,
				{
					PlatformId = pick.PlatformId,
					ItemId = pick.ItemId,
					SpeciesId = pick.SpeciesId,
					MutationId = mutationId,
					MegaKey = strike.Key,
				}
		end,
		{
			onCommitted = function(result: any)
				local live = deps.BaseStorageSystem:GetStorageForPlayer(player)
				if
					not live
					or not live:AdoptCommittedMutation(
						result.PlatformId,
						result.ItemId,
						result.MutationId
					)
				then
					return false -- Phase13Service retries the hook until the live entry adopts it
				end
				deps.BaseStorageSystem:NotifyRecordChanged(player)
				present(player, result, operationId)
				return true
			end,
		}
	)
	if type(outcome) == "table" and outcome.ok then
		stats.Struck += 1
		return true
	end
	local code = if type(outcome) == "table" then outcome.code else nil
	if code == "RAIN_TARGET_MOVED" or code == "RAIN_TARGET_NOT_ELIGIBLE" then
		return false -- re-pick next attempt
	end
	return false
end

local function step()
	local t = now()
	local snapshot = deps.WorldService:GetRush()
	if snapshot and snapshot.state == "Mega" then
		local key = string.format("%s%d", Rain._KeyPrefix, math.floor(snapshot.rushStartsAt))
		if not megasSeen[key] then
			megasSeen[key] = true
			megaCount += 1
			stats.Megas += 1
		end
		local every = math.max(1, CoreLoop.Mutation.Rain.EveryNthMega)
		if megaCount % every == 0 then
			local from = math.max(t + 1, snapshot.rushStartsAt + EDGE_SECONDS)
			local to = snapshot.rushEndsAt - EDGE_SECONDS
			for _, player in Players:GetPlayers() do
				local existing = strikes[player]
				if (not existing or existing.Key ~= key) and to - from >= 1 then
					strikes[player] = {
						At = from + rng():NextNumber() * (to - from),
						Key = key,
						EndsAt = snapshot.rushEndsAt,
						Tries = 0,
						Done = false,
					}
					stats.Scheduled += 1
				end
			end
		end
	end
	for player, strike in strikes do
		if strike.Done or t < strike.At then
			continue
		end
		if player.Parent ~= Players then
			strikes[player] = nil
			continue
		end
		if strike.Tries == 0 and not isPresent(player) then
			stats.NotPresent += 1
			strike.Done = true
			continue
		end
		strike.Tries += 1
		local ok, resolved = pcall(attempt, player, strike)
		if ok and resolved then
			strike.Done = true
		elseif t > strike.EndsAt + GRACE_AFTER_MEGA or strike.Tries >= 15 then
			stats.Failed += 1
			strike.Done = true
		else
			strike.At = t + RETRY_SECONDS
		end
	end
end

function Rain.Start(options: any): boolean
	if started or not CoreLoopFlags.Part("MutationRain") then
		return false
	end
	if
		not (
			options.WorldService
			and options.BaseStorageSystem
			and options.Phase13Service
			and options.Profile
		)
	then
		return false
	end
	started = true
	deps = options
	Rain._KeyPrefix = (if game.JobId ~= "" then string.sub(game.JobId, 1, 8) else "studio") .. ":"
	for _, player in Players:GetPlayers() do
		lastActive[player] = now()
	end
	Players.PlayerAdded:Connect(function(player)
		lastActive[player] = now() -- joining counts as input
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastActive[player] = nil
		strikes[player] = nil
	end)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
		local ping = remotes and remotes:WaitForChild("TrainingInput", 60)
		if ping and ping:IsA("RemoteEvent") then
			ping.OnServerEvent:Connect(function(player)
				lastActive[player] = now()
			end)
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 then
			return
		end
		elapsed = 0
		pcall(sampleActivity)
		local ok, err = pcall(step)
		if not ok then
			warn("[CoreLoopMutationRain] " .. tostring(err))
		end
	end)
	return true
end

Rain._KeyPrefix = "studio:"

function Rain.GetStats(): any
	return table.clone(stats)
end

-- QA (Studio only, via CoreLoopQA): force presence, or strike a player now under a unique key.
function Rain._SetPresentForQA(value: boolean?)
	if RunService:IsStudio() then
		presentOverride = value
	end
end

function Rain._StrikeNowForQA(player: Player, key: string?): any
	if not RunService:IsStudio() or not started then
		return "NOT_RUNNING"
	end
	local strike: Strike = {
		At = 0,
		Key = key or ("QA" .. tostring(math.floor(os.clock() * 1000))),
		EndsAt = now() + 60,
		Tries = 1,
		Done = false,
	}
	local ok, resolved = pcall(attempt, player, strike)
	return { ok = ok, resolved = resolved, key = strike.Key }
end

function Rain._SlotsForQA(player: Player): any
	if not started then
		return nil
	end
	local storage = deps.BaseStorageSystem:GetStorageForPlayer(player)
	if not storage then
		return "NO_STORAGE"
	end
	local out = {}
	for _, platformId in storage:GetPlatformIds() do
		local record = storage:GetPlatformRecord(platformId)
		if record then
			table.insert(
				out,
				string.format(
					"%d:%s/%s",
					platformId,
					record.BrainrotId,
					Phase12Progress.MutationId(record)
				)
			)
		end
	end
	return out
end

function Rain._LastActiveForQA(player: Player): number?
	return lastActive[player]
end

return Rain
