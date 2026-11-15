--!strict
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Catalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Progression = require(RS.Shared.Config.WorldProgression)
local Profiles = require(script.Parent.PlayerDataService)
local StreamingApproach = require(RS.Shared.Utility.RegionStreamingApproachPolicy)
local Service = {}
local deps = {}
local contexts = {}
local started = false
local sequence = 0
local remote = nil
local prefetches = {}

local function prefetch(player, root, regionId, unlocked)
	local descriptors = deps.Access and deps.Access.descriptors
	if not root or not descriptors then
		return
	end
	local gates = {}
	for _, definition in Progression.Ordered do
		if definition.index <= 1 then
			continue
		end
		local gate = descriptors:GetGate(definition.regionId)
		if gate then
			table.insert(gates, {
				key = gate.key,
				regionId = gate.regionId,
				exteriorRegion = gate.exteriorRegion,
				position = gate.threshold,
				normal = gate.normal,
			})
		end
	end
	local selected = StreamingApproach.Select(root.Position, regionId, unlocked, gates)
	local state = prefetches[player]
	if not state then
		state = { requests = 0, completed = 0, failed = 0, stale = 0, pending = false }
		prefetches[player] = state
	end
	local now = os.clock()
	if state.character ~= player.Character then
		state.character = player.Character
		StreamingApproach.TryRequest(state, nil, now)
	end
	local allowed, generation = StreamingApproach.TryRequest(state, if selected then selected.key else nil, now)
	if not allowed then
		return
	end
	state.requests += 1
	state.last = {
		gateKey = selected.gateKey,
		destinationRegion = selected.destinationRegion,
		approachDistance = selected.approachDistance,
		target = selected.position,
		timeoutSeconds = StreamingApproach.RequestTimeout,
	}
	local character = player.Character
	task.spawn(function()
		local ok = pcall(function()
			player:RequestStreamAroundAsync(selected.position, StreamingApproach.RequestTimeout)
		end)
		if prefetches[player] ~= state then
			return
		end
		local current = StreamingApproach.CompleteRequest(state, generation, ok)
		if not current or player.Character ~= character then
			state.stale += 1
		end
		if ok then
			state.completed += 1
		else
			state.failed += 1
		end
		state.last.result = if ok then "REQUEST_RETURNED_NOT_COLLISION_PROOF" else "STREAM_REQUEST_FAILED"
	end)
end

function Service:GetPrefetchDiagnostics(player)
	local state = prefetches[player]
	if not state then
		return { requests = 0, completed = 0, failed = 0, stale = 0, pending = false }
	end
	return {
		requests = state.requests,
		completed = state.completed,
		failed = state.failed,
		stale = state.stale,
		pending = state.pending,
		last = if state.last then table.clone(state.last) else nil,
		maximumConcurrentRequests = 1,
		cooldownCacheEntries = if state.key then 1 else 0,
		maximumCooldownCacheEntries = 1,
		approachAttempts = state.attempts or 0,
		maximumAttemptsPerApproach = StreamingApproach.MaximumAttempts,
		scheduler = "Existing10HzInterestHeartbeat",
	}
end
function Service:GetRegion(player)
	return contexts[player] and contexts[player].regionId
end
function Service:IsObserved(regionId, _position)
	for _, context in contexts do
		if context.regionId == regionId then
			return true
		end
	end
	return false
end
function Service:GetObservers(regionId)
	local result = {}
	for player, context in contexts do
		if context.regionId == regionId and player.Parent == Players then
			table.insert(result, player)
		end
	end
	return result
end
function Service:GetContext(player)
	return contexts[player]
end
function Service:Step()
	sequence += 1
	for _, player in Players:GetPlayers() do
		local data = Profiles:GetReadableData(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local region = if root then Catalog.GetRegionAtPosition(root.Position, math.huge) else nil
		local unlocked = { REGION_CAMP = true }
		local signature = ""
		if data and data.WorldProgression and Profiles:GetStatus(player) == "Ready" then
			for _, definition in Progression.Ordered do
				local allowed = definition.index <= 1
				if deps.Access then
					allowed = deps.Access:GetEffectiveAccess(player, definition.regionId) == true
				elseif definition.index > 1 then
					allowed = data.WorldProgression.PersonalUnlocks[definition.key] ~= nil
						and Profiles:IsRevisionConfirmed(player, Profiles:GetCurrentRevision(player) or math.huge)
				end
				if allowed then
					unlocked[definition.regionId] = true
					signature ..= definition.key
				end
			end
		end
		local id = if data and root and region and unlocked[region.id] then region.id else nil
		prefetch(player, root, id, unlocked)
		local prior = contexts[player]
		if not prior or prior.regionId ~= id or prior.signature ~= signature or prior.character ~= player.Character then
			contexts[player] = {
				regionId = id,
				signature = signature,
				unlocked = unlocked,
				character = player.Character,
				sequence = sequence,
			}
			player:SetAttribute("Phase13RegionId", id)
			if remote then
				remote:FireClient(player, { kind = "Context", regionId = id, unlocked = unlocked, sequence = sequence })
			end
		end
	end
end
function Service:Start(options)
	if started then
		return false
	end
	started = true
	deps = options or {}
	local folder = RS:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = RS
	end
	remote = folder:FindFirstChild("Phase13Interest")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "Phase13Interest"
		remote.Parent = folder
	end
	assert(remote:IsA("RemoteEvent"), "Phase13Interest requires a functional RemoteEvent")
	local cooldown = {}
	remote.OnServerEvent:Connect(function(player, message)
		if message ~= "Context" or cooldown[player] and os.clock() - cooldown[player] < 1 then
			return
		end
		cooldown[player] = os.clock()
		local c = contexts[player]
		if c then
			remote:FireClient(
				player,
				{ kind = "Context", regionId = c.regionId, unlocked = c.unlocked, sequence = c.sequence }
			)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		contexts[player] = nil
		cooldown[player] = nil
		prefetches[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			self:Step()
		end
	end)
	return true
end
return Service
