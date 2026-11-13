--!strict
-- Authority remains in the existing world/carry/cargo/platform services. This
-- adapter observes their committed Models; removing a view never retires an ID.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local Collection = game:GetService("CollectionService")
local Http = game:GetService("HttpService")
local Config = require(RS.Shared.Config.CreatureReplication)
local Rules = require(RS.Shared.Utility.CreatureProtocolRules)
local Display = require(RS.Shared.Config.BrainrotDisplayConfig)
local Regions = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Assets = require(script.Parent.Parent.Utility.CreatureAssetService)
local Roles = require(RS.Shared.Config.MutationSurfaceRoles)
local VoxelV4 = require(RS.Shared.Utility.VoxelCreatureRegistry)
local Service = {}
local started = false
local interest, remote
local tracked, clients, revisions = {}, {}, {}
local serial, sequence, revisionSerial = 0, 0, 0
local queued = false
local counters = { packets = 0, upserts = 0, removals = 0, poseUpdates = 0, templateCopies = 0, templateDenied = 0 }
-- Studio-only measurement seam (ServerStorage.CreatureMotionQA = true before Play): an
-- estimate of creature row bytes sent, mirrored to ServerStorage.CreatureReplicationQA.
local qaEnabled = Run:IsStudio() and game:GetService("ServerStorage"):GetAttribute("CreatureMotionQA") == true
local qaBytes, qaMirrorAt = 0, 0
local colourRoles = {}
local function colourKey(color)
	return string.format("%d:%d:%d", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end
local function annotateFormation(copy, species)
	local map = colourRoles[species]
	if not map then
		map = {}
		local source = Assets.GetTemplate(species, "Full")
		if source then
			for part, assignment in Roles.Resolve(source).parts do
				local key = colourKey(part.Color)
				local counts = map[key] or {}
				map[key] = counts
				counts[assignment.role] = (counts[assignment.role] or 0) + 1
			end
		end
		colourRoles[species] = map
	end
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			local role = if part.Name == "BodyCue"
				then "Primary"
				elseif part.Name == "SpeciesCue" then "Secondary"
				else "Preserve"
			local counts = map[colourKey(part.Color)]
			if role == "Preserve" and counts then
				if counts.Neutral then
					role = "Neutral"
				else
					local maximum = 0
					for _, candidate in { "Primary", "Secondary", "Accent", "SpecialSilver", "SpecialBronze" } do
						if (counts[candidate] or 0) > maximum then
							role, maximum = candidate, counts[candidate]
						end
					end
				end
			end
			part:SetAttribute("CreatureSurfaceRole", role)
		end
	end
end
local attrs = {
	"ItemId",
	"BrainrotId",
	"BrainrotMutationId",
	"MutationId",
	"BrainrotDisplayState",
	"CarrierUserId",
	"Captured",
	"CapturedOnce",
	"Phase12CapturedOnce",
	"Phase12MaxHp",
	"Phase12RemainingHp",
	"Phase13LastDamageAt",
	"BrainrotSleepUntil",
	"Phase12SleepUntil",
	"Phase12EscapeDeadline",
	"Phase12EscapeWarningSeconds",
	"Phase12PresentationState",
	"Phase12InteractionReady",
	"Phase12LifecycleRevision",
	"Phase12RouteEntranceId",
	"Phase12RouteDestinationId",
	"Phase12RouteVersion",
	"Phase12SourceGeneration",
	"Phase10Banked",
	"Phase10TargetKind",
	"Phase10OwnerUserId",
	"OwnerUserId",
	"BrainrotLifecycleRevision",
	"BrainrotRouteGeneration",
	"BrainrotRouteId",
	"BrainrotRouteVersion",
	"EntranceBurrowId",
	"DestinationBurrowId",
	"Phase12EmergenceReadyAt",
	"Phase12BurrowId",
	"Phase12Retired",
	"Phase12ResetGeneration",
	"Phase13CargoResetGeneration",
	"Phase12EscapeGeneration",
	"Phase12EscapeInstanceId",
	"Phase12EscapeOtherCount",
	"Phase12EscapeRemainingJumps",
	"PendingBank",
	"BrainrotCamouflageSnapshot",
	"BrainrotDecoySplitSnapshot",
	"EffectKind",
	"DecoyId",
	-- Presentation-only motion state (CharacterMotion). Nil unless natural motion is on.
	"Motion",
	"MotionAt",
	"MotionSeed",
}
local function send(player, state, kind, fields)
	sequence += 1
	fields.kind, fields.epoch, fields.sequence = kind, state.epoch, sequence
	remote:FireClient(player, fields)
	counters.packets += 1
end
local function validModel(model)
	return model.Parent ~= nil and model:IsDescendantOf(workspace) and model:GetAttribute("CreatureProxy") == true
end
local function rowFor(model, binding)
	if not validModel(model) then
		return nil
	end
	local id = model:GetAttribute("ItemId") or model:GetAttribute("DecoyId")
	local species = model:GetAttribute("BrainrotId")
	if not Rules.ValidId(id) or not Rules.ValidTemplate(species, "Full") then
		return nil
	end
	local pose = model:GetPivot()
	if binding.pose ~= pose then
		binding.pose = pose
		local region = Regions.GetRegionAtPosition(pose.Position, math.huge)
		binding.regionId = region and region.id
	end
	local regionId = binding.regionId
	if not regionId then
		return nil
	end
	if binding.dirty then
		binding.attributes = {}
		for _, name in attrs do
			binding.attributes[name] = model:GetAttribute(name)
		end
		if binding.attributes.OwnerUserId == nil then
			local ancestor = model.Parent
			while ancestor and ancestor ~= workspace do
				local owner = ancestor:GetAttribute("OwnerUserId")
				if type(owner) == "number" then
					binding.attributes.OwnerUserId = owner
					break
				end
				ancestor = ancestor.Parent
			end
		end
		binding.dirty = false
	end
	local attributes = binding.attributes
	attributes.RegionId = regionId -- physical location, not the catch's home region
	local state = attributes.BrainrotDisplayState or "Awake"
	return {
		id = id,
		speciesId = species,
		regionId = regionId,
		pose = pose,
		scale = model:GetScale(),
		state = state,
		attributes = attributes,
		model = model,
		source = binding.serial,
		sourceGeneration = model:GetAttribute("BrainrotRouteGeneration") or model:GetAttribute(
			"Phase12ResetGeneration"
		) or model:GetAttribute("Phase12SourceGeneration") or model:GetAttribute("Phase12EscapeGeneration"),
		priority = Rules.RepresentationPriority(state, attributes.PendingBank),
	}
end
local function sameState(left, right)
	if not left or left.source ~= right.source or left.regionId ~= right.regionId or left.scale ~= right.scale then
		return false
	end
	for _, name in attrs do
		if left.attributes[name] ~= right.attributes[name] then
			return false
		end
	end
	return true
end
local function activeRows()
	local selected = {}
	for model, binding in tracked do
		local row = rowFor(model, binding)
		if row then
			local old = selected[row.id]
			if not old or row.priority > old.priority or row.priority == old.priority and row.source > old.source then
				selected[row.id] = row
			end
		end
	end
	for id, row in selected do
		local last = revisions[id]
		if not sameState(last, row) then
			revisionSerial += 1
			Rules.StampRepresentation(row, revisionSerial)
		else
			row.revision, row.generation = last.revision, last.generation
		end
		row.attributes=table.clone(row.attributes)
        row.attributes.PresentationRevision=row.revision
        revisions[id] = row
	end
	-- Active identities only. A global increasing revision avoids an unbounded
	-- history of retired catches while keeping recreated representations newer.
	for id in revisions do
		if not selected[id] then
			revisions[id] = nil
		end
	end
	return selected
end
local function encoded(row)
	return {
		id = row.id,
		speciesId = row.speciesId,
		regionId = row.regionId,
		pose = row.pose,
		scale = row.scale,
		state = row.state,
		attributes = row.attributes,
		revision = row.revision,
		generation = row.generation,
		sourceGeneration = row.sourceGeneration,
	}
end
local function supplyFolder(player)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return nil
	end
	local folder = gui:FindFirstChild(Config.SupplyName)
	if not folder then
		folder = Instance.new("ScreenGui")
		folder.Name, folder.ResetOnSpawn, folder.Enabled = Config.SupplyName, false, false
		folder.Parent = gui
	end
	return folder
end
local function cleanSupply(state, now)
	for key, item in state.supply do
		if item.model.Parent == nil or now - item.at > Config.SupplyLifetimeSeconds then
			item.model:Destroy()
			state.supply[key] = nil
		end
	end
end
local function authorizedSpecies(_player, state, species)
	for _, row in state.sent do
		if row.speciesId == species then
			return true
		end
	end
	-- Equipped teams are server-authored descriptors. Only a same-region cart may
	-- supply their species; an arbitrary request cannot reveal another region.
	local runtime = workspace:FindFirstChild("Runtime")
	local carts = runtime and runtime:FindFirstChild("Carts")
	if carts then
		for _, cart in carts:GetChildren() do
			if cart:IsA("Model") then
				local region = Regions.GetRegionAtPosition(cart:GetPivot().Position, math.huge)
				local text = cart:GetAttribute("ChariotTeamPublic")
				if region and region.id == state.regionId and type(text) == "string" and #text < 8000 then
					local ok, descriptor = pcall(Http.JSONDecode, Http, text)
					if ok and type(descriptor) == "table" and type(descriptor.entries) == "table" then
						for _, entry in descriptor.entries do
							if entry.speciesId == species then
								return true
							end
						end
					end
				end
			end
		end
	end
	return state.presentationUntil
		and os.clock() < state.presentationUntil
		and state.presentationSpecies[species] == true
end
function Service:AuthorizePresentation(player, descriptors)
	local state = clients[player]
	if not state then
		return false
	end
	state.presentationSpecies = {}
	for index, item in descriptors do
		if index > 48 then
			break
		end
		local id = item.speciesId or item.BrainrotId
		if Rules.ValidTemplate(id, "Full") then
			state.presentationSpecies[id] = true
		end
	end
	state.presentationUntil = os.clock() + 15
	return true
end
function Service:Step(poseTick)
	if not remote then
		return
	end
	local selected = activeRows()
	for _, player in Players:GetPlayers() do
		local context = interest:GetContext(player)
		local epoch = context and context.sequence or 0
		local region = context and context.regionId
		local state = clients[player]
		if not state then
			state = { epoch = -1, sent = {}, supply = {}, requestedAt = {}, presentationSpecies = {} }
			clients[player] = state
		end
		if state.epoch ~= epoch or state.regionId ~= region then
			for _, item in state.supply do
				item.model:Destroy()
			end
			state.supply = {}
			state.epoch, state.regionId, state.sent = epoch, region, {}
			send(player, state, "Context", { regionId = region, version = Config.ProtocolVersion })
		end
		local upserts, removals, visible = {}, {}, {}
		local count = 0
		for id, row in selected do
			if region and row.regionId == region and context.unlocked[region] == true then
				count += 1
				if count <= Config.MaxEntities then
					visible[id] = true
					local prior = state.sent[id]
					if not prior or row.revision ~= prior.revision or poseTick and row.pose ~= prior.pose then
						table.insert(upserts, encoded(row))
						if prior and row.revision == prior.revision then
							counters.poseUpdates += 1
						end
						state.sent[id] = row
					end
				end
			end
		end
		for id, previous in state.sent do
			local row = selected[id]
			if not row or not visible[id] then
				table.insert(removals, { id = id, revision = previous.revision + 1, generation = previous.generation })
				state.sent[id] = nil
			end
		end
		for offset = 1, math.max(#upserts, #removals), Config.MaxPacketEntities do
			local add, remove = {}, {}
			for i = offset, math.min(offset + Config.MaxPacketEntities - 1, #upserts) do
				table.insert(add, upserts[i])
			end
			for i = offset, math.min(offset + Config.MaxPacketEntities - 1, #removals) do
				table.insert(remove, removals[i])
			end
			send(
				player,
				state,
				"Delta",
				{ upserts = add, removals = remove, serverTime = workspace:GetServerTimeNow() }
			)
		end
		counters.upserts += #upserts
		counters.removals += #removals
		if qaEnabled then
			for _, row in upserts do
				qaBytes += 80 + #Http:JSONEncode(row.attributes)
			end
		end
		cleanSupply(state, os.clock())
	end
end
local function schedule()
	if queued then
		return
	end
	queued = true
	task.defer(function()
		queued = false
		Service:Step(false)
	end)
end
local function untrack(model)
	local binding = tracked[model]
	if not binding then
		return
	end
	for _, connection in binding.connections do
		connection:Disconnect()
	end
	tracked[model] = nil
	schedule()
end
local function track(model)
	if not model:IsA("Model") or tracked[model] or model:GetAttribute("CreatureProxy") ~= true then
		return
	end
	serial += 1
	local binding = { serial = serial, connections = {}, dirty = true }
	tracked[model] = binding
	table.insert(
		binding.connections,
		model.AttributeChanged:Connect(function()
			binding.dirty = true
			schedule()
		end)
	)
	table.insert(
		binding.connections,
		model.AncestryChanged:Connect(function()
			binding.dirty = true
			schedule()
		end)
	)
	table.insert(
		binding.connections,
		model.Destroying:Connect(function()
			untrack(model)
		end)
	)
	schedule()
end
function Service:GetPresentationRevision(id)
 local row=revisions[id];return row and row.revision
end
function Service:GetDiagnostics()
	local result = table.clone(counters)
	result.tracked, result.clients, result.activeSupply = 0, 0, 0
	for _ in tracked do
		result.tracked += 1
	end
	for _, state in clients do
		result.clients += 1
		for _ in state.supply do
			result.activeSupply += 1
		end
	end
	return result
end
function Service:GetRecipientSnapshot(player)
	local state = clients[player]
	if not state then
		return nil
	end
	local result = { epoch = state.epoch, regionId = state.regionId, entries = {}, supply = 0 }
	for _, row in state.sent do
		table.insert(result.entries, {
			id = row.id,
			speciesId = row.speciesId,
			state = row.state,
			revision = row.revision,
			generation = row.generation,
			regionId = row.regionId,
		})
	end
	for _ in state.supply do
		result.supply += 1
	end
	return result
end
function Service:Start(options)
	if started or RS:GetAttribute("Phase13CreatureProtocolEnabled") ~= true then
		return false
	end
	started = true
	interest = assert(options.Interest,"Creature interest owner required")
	local folder = RS:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = RS
	end
	remote = folder:FindFirstChild(Config.RemoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Config.RemoteName
		remote.Parent = folder
	end
	remote.OnServerEvent:Connect(function(player, request)
		local state = clients[player]
		if not state or type(request) ~= "table" then
			return
		end
		if request.kind == "Context" then
			if state.contextAt and os.clock() - state.contextAt < Config.ContextRequestIntervalSeconds then
				return
			end
			state.contextAt, state.epoch = os.clock(), -1
			schedule()
			return
		end
		if request.epoch ~= state.epoch or not Rules.ValidTemplate(request.speciesId, request.lod) then
			return
		end
		local currentContext = interest:GetContext(player)
		if not currentContext or currentContext.sequence ~= state.epoch then
			schedule()
			return
		end
		local key = Rules.TemplateKey(request.speciesId, request.lod)
		if request.kind == "TemplateAck" then
			local item = state.supply[key]
			if item and request.token == item.token then
				item.model:Destroy()
				state.supply[key] = nil
			end
			return
		end
		if
			request.kind ~= "Template"
			or state.templateAt and os.clock() - state.templateAt < Config.TemplateRequestIntervalSeconds
		then
			return
		end
		state.templateAt = os.clock()
		if not authorizedSpecies(player, state, request.speciesId) then
			counters.templateDenied += 1
			return
		end
		cleanSupply(state, os.clock())
		if state.supply[key] then
			return
		end
		local count = 0
		for _ in state.supply do
			count += 1
		end
		if count >= Config.MaxSupplyTemplates then
			return
		end
		-- Voxel V4 replaces client visuals only: one Full V4 model serves every LOD
		-- and role. Authority proxies still come from the legacy template.
		local voxel = VoxelV4.GetActiveTemplate(request.speciesId)
		local source = voxel or Assets.GetTemplate(request.speciesId, request.lod)
		local parent = supplyFolder(player)
		if not source or not parent then
			return
		end
		local copy = source:Clone()
		if request.lod ~= "Full" and not voxel then
			annotateFormation(copy, request.speciesId)
		end
		for _, node in { copy, table.unpack(copy:GetDescendants()) } do
			for _, tag in Collection:GetTags(node) do
				Collection:RemoveTag(node, tag)
			end
			if node:IsA("LuaSourceContainer") then
				node:Destroy()
			end
		end
		local token = Http:GenerateGUID(false)
		copy.Name = key
		copy:SetAttribute("CreatureSupplyToken", token)
		copy:SetAttribute("CreatureSupplyEpoch", state.epoch)
		copy:SetAttribute("CreatureSupplySpecies", request.speciesId)
		copy:SetAttribute("CreatureSupplyLOD", request.lod)
		copy:SetAttribute("CreatureSupplyDescendants", #copy:GetDescendants())
		state.supply[key] = { model = copy, token = token, at = os.clock() }
		copy.Parent = parent
		counters.templateCopies += 1
	end)
	Collection:GetInstanceAddedSignal(Display.CollectionTag):Connect(track)
	Collection:GetInstanceRemovedSignal(Display.CollectionTag):Connect(untrack)
	for _, model in Collection:GetTagged(Display.CollectionTag) do
		track(model)
	end
	Players.PlayerRemoving:Connect(function(player)
		local state = clients[player]
		if state then
			for _, item in state.supply do
				item.model:Destroy()
			end
		end
		clients[player] = nil
	end)
	local elapsed = 0
	Run.Heartbeat:Connect(function(dt)
		elapsed += dt
		if qaEnabled and os.clock() - qaMirrorAt >= 1 then
			qaMirrorAt = os.clock()
			game:GetService("ServerStorage"):SetAttribute(
				"CreatureReplicationQA",
				string.format(
					"bytes=%d upserts=%d poseUpdates=%d packets=%d",
					qaBytes,
					counters.upserts,
					counters.poseUpdates,
					counters.packets
				)
			)
		end
		if elapsed >= Config.PoseIntervalSeconds then
			elapsed %= Config.PoseIntervalSeconds
			Service:Step(true)
		end
	end)
	self:Step(true)
	return true
end
return Service
