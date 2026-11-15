--!strict
-- Small authoritative presentation events. Cosmetics cannot commit inventory,
-- income, ownership, escape or reset outcomes through this service.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Shared.Config.Phase12)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local RegionCatalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Burrows = require(script.Parent.Parent.Utility.Phase12Burrows)
local CartService = require(script.Parent.CartService)
local BaseSystem = require(script.Parent.Parent.Systems.PlayerBaseSystem)
local Progress = require(script.Parent.Parent.Data.Phase12Progress)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local log = Logger.new("Phase12EventService")
local Service = {}
local dependencies: any = nil
local eventRemote: RemoteEvent? = nil
local progressRemote: RemoteFunction? = nil
local connections: { any } = {}
local seen: { [string]: boolean } = {}
local history: { string } = {}
local batches: { [Player]: any } = {}
local requestTimes: { [Player]: number } = {}
local generation = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end
local function positionValid(value: any): boolean
	return typeof(value) == "Vector3"
		and Rules.IsFinite(value.X)
		and Rules.IsFinite(value.Y)
		and Rules.IsFinite(value.Z)
end
local function actorPosition(player: Player?): Vector3?
	local root = if player and player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end
local function remember(id: string): boolean
	if seen[id] then
		return false
	end
	seen[id] = true
	table.insert(history, id)
	if #history > 128 then
		seen[table.remove(history, 1)] = nil
	end
	return true
end
local function ensureRemote(name: string, className: string): any
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	local remote = folder:FindFirstChild(name)
	if remote == nil then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
	assert(remote:IsA(className), name .. " must be " .. className)
	return remote
end
local function location(position: Vector3?, extra: any?): any
	local resolved = { regionId = nil, regionName = "Unknown region", landmarkId = nil, location = "Unknown region" }
	if positionValid(position) then
		local region = RegionCatalog.GetRegionAtPosition(position)
		if region then
			resolved.regionId, resolved.regionName = region.id, region.displayName
			resolved.landmarkId = Burrows.Nearest(region.id, position)
		end
		local world = dependencies and dependencies.WorldService
		if world and type(world.GetLocation) == "function" then
			local ok, result = pcall(world.GetLocation, world, position)
			if ok and type(result) == "table" then
				resolved.regionId = result.regionId or resolved.regionId
				resolved.regionName = result.regionName or resolved.regionName
				resolved.landmarkId = result.landmarkId or result.landmark or result.burrowId or resolved.landmarkId
			end
		end
	end
	if extra and type(extra.landmarkId or extra.burrowId) == "string" then
		resolved.landmarkId = extra.landmarkId or extra.burrowId
	end
	resolved.location = resolved.regionName .. (if resolved.landmarkId then " / " .. resolved.landmarkId else "")
	return resolved
end
local function bankSign(player: Player, fallback: Vector3?): Vector3?
	local base = BaseSystem:GetBase(player)
	local sign = if base then base:FindFirstChild("OwnershipSign") else nil
	if sign and sign:IsA("Model") then
		for _, part in sign:GetChildren() do
			if part:IsA("BasePart") and part:FindFirstChildOfClass("SurfaceGui") then
				return part.Position
			end
		end
		return sign:GetPivot().Position
	end
	return fallback
end
local function describe(kind: string, record: any, player: Player?, extra: any?): any?
	if type(record) ~= "table" then
		return nil
	end
	local id = record.ItemId or record.individualId
	local species = record.BrainrotId or record.speciesId
	local definition = Catalog.Get(species)
	if type(id) ~= "string" or definition == nil or definition.developmentFixture == true then
		return nil
	end
	local mutation = Progress.MutationId(record)
	if mutation == nil then
		return nil
	end
	local detail = extra or {}
	local position = if positionValid(detail.position) then detail.position else actorPosition(player)
	local where = location(position, detail)
	local world = record.World or {}
	local identified = mutation ~= "Astral"
		or world.FirstCaptureCompleted == true
		or world.firstCaptureCompleted == true
		or (kind ~= "Spawn")
	local values = Rules.EffectiveValues(species, mutation)
	if values == nil then
		return nil
	end
	return {
		eventId = detail.eventId or (string.lower(kind) .. ":" .. id),
		kind = kind,
		individualId = id,
		instanceId = id,
		speciesId = species,
		displayName = if identified then definition.displayName else "ASTRAL",
		name = if identified then definition.displayName else "ASTRAL",
		mutationId = mutation,
		rarity = definition.tier,
		rank = Rules.SpectacleRank(definition.tier, mutation),
		username = if player then player.Name else nil,
		userId = if player then player.UserId else nil,
		sourceAnchor = detail.sourceAnchor,
		position = position,
		regionId = where.regionId,
		regionName = where.regionName,
		landmarkId = where.landmarkId,
		location = where.location,
		at = now(),
		startTime = now(),
		cycleId = detail.cycleId,
		seed = detail.seed or math.random(1, 2147483646),
		cashPerSecond = values.cashPerSecond,
		sellValue = values.sellValue,
		global = Rules.GlobalAnnouncement(definition.tier, mutation),
		ownerOnly = detail.ownerOnly,
		chatOnly = detail.chatOnly,
		suppressChat = detail.suppressChat,
		firstSpecies = detail.firstSpecies,
		firstSpeciesMutation = detail.firstSpeciesMutation,
		discovery = { species = detail.firstSpecies, mutation = detail.firstSpeciesMutation },
		platformPosition = position,
		recordImprovements = detail.recordImprovements,
		baseId = detail.baseId,
		platformId = detail.platformId,
		landingPosition = detail.landingPosition,
	}
end
local function interested(regionId: any): any?
	local interest = dependencies and dependencies.Interest
	if type(regionId) == "string" and interest and type(interest.GetObservers) == "function" then
		local ok, observers = pcall(interest.GetObservers, interest, regionId)
		if ok and type(observers) == "table" then
			return observers
		end
	end
	return nil
end
local function resetDelivery(payload: any)
	if not eventRemote then
		return
	end
	local snapshots = payload.representations
	if type(snapshots) ~= "table" then
		eventRemote:FireAllClients(payload)
		return
	end
	local byPlayer = {}
	for _, snapshot in snapshots do
		local copy = table.clone(snapshot)
		local region = typeof(copy.Pose) == "CFrame"
			and RegionCatalog.GetRegionAtPosition(copy.Pose.Position, math.huge)
		copy.RegionId = region and region.id or nil
		local observers = if copy.RegionId then (interested(copy.RegionId) or Players:GetPlayers()) else {}
		for _, observer in observers do
			local list = byPlayer[observer] or {}
			byPlayer[observer] = list
			table.insert(list, copy)
		end
	end
	for _, observer in Players:GetPlayers() do
		local copy = table.clone(payload)
		copy.representations = byPlayer[observer] or {}
		eventRemote:FireClient(observer, copy)
	end
end

local function deliver(payload: any, owner: Player?)
	local remote = eventRemote
	if remote == nil then
		return
	end
	local observers = interested(payload.regionId)
	if observers and payload.ownerOnly ~= true then
		local delivered = {}
		for _, observer in observers do
			delivered[observer] = true
			remote:FireClient(observer, payload)
		end
		if owner and owner.Parent == Players and not delivered[owner] then
			remote:FireClient(owner, payload)
		end
		if payload.global == true then
			local metadata = table.clone(payload)
			metadata.chatOnly = true
			metadata.position = nil
			for _, observer in Players:GetPlayers() do
				if not delivered[observer] and observer ~= owner then
					remote:FireClient(observer, metadata)
				end
			end
		end
		return
	end
	if payload.global == true and payload.ownerOnly ~= true then
		remote:FireAllClients(payload)
		return
	end
	if owner and owner.Parent == Players then
		remote:FireClient(owner, payload)
	end
	if payload.ownerOnly == true or payload.chatOnly == true then
		return
	end
	-- Low-rarity mutations and Rare discoveries have nearby cues and celebration.
	if payload.rank > 0 and positionValid(payload.position) then
		for _, player in Players:GetPlayers() do
			if player == owner then
				continue
			end
			local position = actorPosition(player)
			if position and (position - payload.position).Magnitude <= 120 then
				remote:FireClient(player, payload)
			end
		end
	end
end

function Service:Broadcast(kind: string, record: any, player: Player?, extra: any?): any?
	if dependencies == nil then
		return nil
	end
	if
		record == nil and (kind == "ResetCycle" or kind == "ResetWarning" or kind == "Reset" or kind == "ResetRetire")
	then
		local detail = extra or {}
		local payload = {
			eventId = detail.eventId or (kind .. ":" .. tostring(detail.cycleId) .. ":" .. tostring(detail.phase)),
			kind = kind,
			cycleId = detail.cycleId,
			deadline = detail.deadline,
			startTime = detail.startTime or now(),
			at = now(),
			phase = detail.phase,
			seed = detail.seed or math.random(1, 2147483646),
			global = true,
			representations = detail.representations,
			retiredGeneration = detail.retiredGeneration,
		}
		if remember(payload.eventId) and eventRemote then
			resetDelivery(payload)
		end
		return payload
	end
	local payload = describe(kind, record, player, extra)
	if payload == nil or not remember(payload.eventId) then
		return nil
	end
	-- Ordinary spawn still commits to gameplay, but has no spectacle announcement.
	if kind == "Spawn" and payload.rank == 0 then
		return payload
	end
	deliver(payload, player)
	return payload
end

local function compare(left: any, right: any): boolean
	if left.rank ~= right.rank then
		return left.rank < right.rank
	end
	if left.cashPerSecond ~= right.cashPerSecond then
		return left.cashPerSecond < right.cashPerSecond
	end
	if left.sellValue ~= right.sellValue then
		return left.sellValue < right.sellValue
	end
	return left.individualId < right.individualId
end
local function flushBank(player: Player, batch: any)
	if batches[player] ~= batch then
		return
	end
	batches[player] = nil
	if player.Parent ~= Players or dependencies == nil or #batch.records == 0 then
		return
	end
	table.sort(batch.records, compare)
	local strongest = batch.records[#batch.records]
	local payload = table.clone(strongest)
	payload.eventId, payload.kind = batch.id, "Bank"
	payload.main, payload.records, payload.totalCount = strongest, batch.records, #batch.records
	payload.batchReady, payload.firstBank = true, true
	payload.suppressChat, payload.chatOnly = true, false
	payload.cashPerSecond, payload.sellValue = batch.cashPerSecond, batch.sellValue
	payload.progress = dependencies.Banked:GetProgressSnapshot(player)
	payload.signPosition = bankSign(player, strongest.position)
	payload.baseSignPosition = payload.signPosition
	payload.location = "@" .. player.Name .. "'s base"
	payload.firstSpecies, payload.firstSpeciesMutation = nil, nil
	if remember(payload.eventId) then
		deliver(payload, player)
	end
end
local function bankCommitted(player: Player, receipt: any)
	local payload = describe("Bank", receipt, player, receipt)
	if payload == nil then
		return
	end
	local batch = batches[player]
	if batch == nil then
		batch =
			{ id = "bank-batch:" .. HttpService:GenerateGUID(false), records = {}, cashPerSecond = 0, sellValue = 0 }
		batches[player] = batch
		local currentGeneration = generation
		task.delay(Config.BankBatchSeconds, function()
			if currentGeneration == generation then
				flushBank(player, batch)
			end
		end)
	end
	-- The storage adapter emits each first-bank receipt once. Keep an additional
	-- compact ID guard for observers/replays without a permanent event ledger.
	if not remember(payload.eventId) then
		return
	end
	table.insert(batch.records, payload)
	batch.cashPerSecond += payload.cashPerSecond
	batch.sellValue += payload.sellValue
	if payload.global then
		local chat = table.clone(payload)
		chat.chatOnly, chat.location, chat.kind = true, "@" .. player.Name .. "'s base", "BankReceipt"
		deliver(chat, player)
	end
end

function Service:Start(options: any): boolean
	if dependencies ~= nil or not Config.Enabled then
		return false
	end
	dependencies = options
	if options.WorldService and type(options.WorldService.IsInCamp) == "function" then
		options.Banked:SetCampClassifier(function(player)
			local position = actorPosition(player)
			return if position then options.WorldService:IsInCamp(position) else nil
		end)
	end
	generation += 1
	eventRemote = ensureRemote(RemoteNames.Phase12Event, "RemoteEvent")
	progressRemote = ensureRemote(RemoteNames.Phase12ProgressRequest, "RemoteFunction")
	progressRemote.OnServerInvoke = function(player, payload)
		if player.Parent ~= Players or not options.PlayerData:IsWritable(player) then
			return { ok = false, code = "PROFILE_NOT_READY" }
		end
		if type(payload) ~= "table" or (payload.action ~= "Snapshot" and payload.action ~= "TrackUpgrade") then
			return { ok = false, code = "INVALID_REQUEST" }
		end
		for key in payload do
			if key ~= "action" and (payload.action ~= "TrackUpgrade" or key ~= "offerId") then
				return { ok = false, code = "UNEXPECTED_FIELD" }
			end
		end
		if payload.action == "TrackUpgrade" and (type(payload.offerId) ~= "string" or #payload.offerId > 128) then
			return { ok = false, code = "INVALID_OFFER" }
		end
		local at = now()
		if requestTimes[player] and at - requestTimes[player] < 0.25 then
			return { ok = false, code = "RATE_LIMITED" }
		end
		requestTimes[player] = at
		if payload.action == "TrackUpgrade" then
			local result = options.Banked:TrackUpgrade(player, payload.offerId)
			if result.ok then
				result.progress = options.Banked:GetProgressSnapshot(player)
			end
			return result
		end
		return { ok = true, progress = options.Banked:GetProgressSnapshot(player) }
	end
	table.insert(connections, options.Banked:SubscribeBankCommitted(bankCommitted))
	table.insert(
		connections,
		options.Interaction.SubscribeCommitted(function(player, receipt)
			if receipt.kind == "WildAcquired" then
				local record = options.Interaction.GetCarriedRecord(player)
				if record and record.ItemId == receipt.individualId then
					Service:Broadcast(
						"Catch",
						record,
						player,
						{ eventId = receipt.eventId, position = actorPosition(player) }
					)
				end
			elseif receipt.kind == "BankedPlaced" then
				Service:Broadcast(
					"BankAcknowledgement",
					{ ItemId = receipt.individualId, BrainrotId = receipt.speciesId, mutationId = receipt.mutationId },
					player,
					{ eventId = receipt.eventId, ownerOnly = true, suppressChat = true }
				)
			elseif receipt.kind == "CargoPlaced" then
				local cart = CartService:GetCart(player)
				local record = if cart then options.Cargo:GetCargoItem(cart, receipt.individualId) else nil
				if record then
					Service:Broadcast("Load", record, player, { eventId = receipt.eventId, ownerOnly = true })
				end
			end
		end)
	)
	if options.World.NaturalSpawnCommitted then
		table.insert(
			connections,
			options.World.NaturalSpawnCommitted:Connect(function(record, model, _regionId, burrowId)
				if model and model.Parent then
					Service:Broadcast("Spawn", record, nil, {
						position = model:GetPivot().Position,
						sourceAnchor = model:GetPivot() + Vector3.yAxis * require(
							ReplicatedStorage.Shared.Config.PlaytestPresentationMetadata
						).RiftSource.SpawnLift,
						burrowId = burrowId,
						cycleId = workspace:GetAttribute("Phase12CycleId"),
					})
				end
			end)
		)
	end
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			batches[player], requestTimes[player] = nil, nil
		end)
	)
	if options.Upgrade and type(options.Upgrade.SubscribePurchaseCommitted) == "function" then
		table.insert(
			connections,
			options.Upgrade:SubscribePurchaseCommitted(function(player)
				if player.Parent == Players and eventRemote then
					eventRemote:FireClient(player, {
						eventId = "progress:" .. HttpService:GenerateGUID(false),
						kind = "Progress",
						progress = options.Banked:GetProgressSnapshot(player),
						at = now(),
						ownerOnly = true,
					})
				end
			end)
		)
	end
	log:Info("Authoritative Phase 12 event bridge ready")
	return true
end

function Service:Stop()
	generation += 1
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(batches)
	table.clear(requestTimes)
	table.clear(seen)
	table.clear(history)
	if progressRemote then
		progressRemote.OnServerInvoke = nil
	end
	if dependencies and dependencies.Banked then
		dependencies.Banked:SetCampClassifier(nil)
	end
	dependencies, eventRemote, progressRemote = nil, nil, nil
end

return Service
