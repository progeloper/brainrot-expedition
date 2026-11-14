--!strict
-- This is the only detailed world/transport renderer in protocol mode. Rendered
-- parts never participate in hit queries, transfers, population or ownership.
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Collection = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Config = require(RS.Shared.Config.CreatureReplication)
local Rules = require(RS.Shared.Utility.CreatureProtocolRules)
local Provider = require(RS.Shared.Utility.CreatureTemplateProvider)
local Scale = require(RS.Shared.Utility.BrainrotVisualScale)
local Display = require(RS.Shared.Config.BrainrotDisplayConfig)
local ResolvedQuality = require(RS.Shared.Utility.ResolvedPresentationQuality)
local Cache = require(script.Parent.CreatureTemplateCache)
-- Brainrot animation playback (rig + animation brief v5, D.1); inert unless the flag is on.
local Anim = require(script.Parent.CreatureAnimationController)
local Ownership = require(RS.Shared.Utility.PresentationOwnership).new()
-- Playtest Fixes E4 (flag-gated): catch pop and the Mythic/Secret first-sighting beat. Presentation only.
local PlaytestFlags = require(RS.Shared.Config.PlaytestFixesFlags)
local Ladder = require(RS.Shared.Config.PlaytestFixes).SizeLadder
local TweenService = game:GetService("TweenService")
local sightedRarities: { [string]: boolean } = {}
local SIGHTING_RARITIES = { Mythic = true, Celestial = true, Secret = true }
local Controller = {}
local packetState = { epoch = -1, sequence = -1 }
local entries, tombstones, tombstoneOrder = {}, {}, {}
local folder, remote, active
local connections, lifecycle = {}, 0
local frames, rejected, contextChanges, detailed = 0, 0, 0, 0
local contextAt = 0 -- os.clock() of the latest interest snapshot (Celebrate on fresh catches only)
local pendingBankSeen: { [string]: boolean } = {} -- rows seen with PendingBank = true (fresh banks)
local interestEntries, interestExits = 0, 0
local function destroyView(entry)
	if entry.row then
		Ownership.Revoke(entry.row.id)
	end
	entry.owner = nil
	entry.transport = nil
	if entry.anim then
		Anim.Detach(entry)
	end
	if entry.model then
		entry.model:Destroy()
		entry.model = nil
	end
end
local function clear()
	for _, entry in entries do
		destroyView(entry)
	end
	table.clear(entries)
	table.clear(tombstones)
	table.clear(tombstoneOrder)
end
local function copyAttributes(model, row)
	local desired = table.clone(row.attributes)
	desired.CreatureLocalVisual, desired.CreatureProtocolId = true, row.id
	desired.PreserveAuthoredBodyColours = true
	desired.CreatureProtocolState, desired.RegionId = row.state, row.regionId
	desired.Phase12FormationLOD = model:GetAttribute("Phase12FormationLOD")
	desired.PlaytestSizeRatio = model:GetAttribute("PlaytestSizeRatio") -- size ladder (local scale)
	for name in model:GetAttributes() do
		if desired[name] == nil then
			model:SetAttribute(name, nil)
		end
	end
	for name, value in desired do
		if model:GetAttribute(name) ~= value then
			model:SetAttribute(name, value)
		end
	end
end
local function applyQueryPolicy(model, row)
	local queryableWorld = (row.state == "Awake" or row.state == "Sleeping")
		and row.attributes.EffectKind ~= "Decoy"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanQuery = queryableWorld and part:GetAttribute("CreatureOriginalCanQuery") == true
		end
	end
end
-- The carried/cargo view pops 0.7 -> 1.12 -> 1.0 (Back out, 0.3 s) when it changes into that role.
-- Visual only: the local model is rescaled about its pivot; the authority proxy is never touched.
local function catchPop(model)
	local base = model:GetScale()
	local pop = Ladder.CatchPop
	local value = Instance.new("NumberValue")
	value.Value = pop.From
	model:ScaleTo(base * pop.From)
	local connection = value.Changed:Connect(function(v)
		if model.Parent then
			model:ScaleTo(base * v)
		end
	end)
	local up = TweenService:Create(
		value,
		TweenInfo.new(pop.Seconds * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = pop.Peak }
	)
	up.Completed:Once(function()
		local down = TweenService:Create(
			value,
			TweenInfo.new(pop.Seconds * 0.4, Enum.EasingStyle.Quad),
			{ Value = 1 }
		)
		down.Completed:Once(function()
			connection:Disconnect()
			value:Destroy()
			if model.Parent then
				model:ScaleTo(base)
			end
		end)
		down:Play()
	end)
	up:Play()
end

-- First Mythic/Celestial/Secret seen this session within FirstSightingRadius: a pulsing ground ring in
-- the rarity colour and a 0.2 s camera nudge.
local function sightingBeat(model, rarity)
	local theme = require(RS.Shared.UI.Theme)
	local colour = theme.Rarity[rarity] or Color3.new(1, 1, 1)
	local _, size = model:GetBoundingBox()
	local ring = Instance.new("Part")
	ring.Name = "SightingRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow =
		true, false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = colour
	ring.Transparency = 0.3
	local radius = math.max(size.X, size.Z) * 0.75
	ring.Size = Vector3.new(0.12, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(model:GetPivot().Position + Vector3.new(0, 0.1, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	local pulse = TweenService:Create(
		ring,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 4, true),
		{ Transparency = 0.85 }
	)
	pulse.Completed:Once(function()
		ring:Destroy()
	end)
	pulse:Play()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local rest = humanoid.CameraOffset
		humanoid.CameraOffset = rest + Vector3.new(0, 0.35, 0)
		TweenService
			:Create(humanoid, TweenInfo.new(Ladder.CameraNudgeSeconds, Enum.EasingStyle.Quad), {
				CameraOffset = rest,
			})
			:Play()
	end
end

local function createView(entry, lod)
	local row = entry.row
	local template = Provider.Get(row.speciesId, lod)
	if not template then
		return false
	end
	local model = template:Clone()
	model.Name = "Creature_" .. row.id
	for _, node in { model, table.unpack(model:GetDescendants()) } do
		for _, tag in Collection:GetTags(node) do
			Collection:RemoveTag(node, tag)
		end
		if
			node:IsA("LuaSourceContainer")
			or node:IsA("ProximityPrompt")
			or node:IsA("Humanoid")
			or node:IsA("Sound")
			or node:IsA("Light")
			or node:IsA("ParticleEmitter")
		then
			node:Destroy()
		elseif node:IsA("BasePart") then
			node:SetAttribute("CreatureOriginalCanQuery", node.CanQuery)
			node.Anchored, node.CanCollide, node.CanTouch, node.CanQuery = true, false, false, false
			node.CastShadow = false
			node.AssemblyLinearVelocity, node.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
	end
	model:SetAttribute("BrainrotId", row.speciesId)
	require(RS.Shared.Utility.WorldStudPolicy).ApplyModel(model, "Creature")
	local normalized, _, reason =
		Scale.ApplyCanonicalScale(model, "CreaturePresentation:" .. row.state)
	if not normalized then
		model:Destroy()
		warn(reason)
		return false
	end

	copyAttributes(model, row)
	applyQueryPolicy(model, row)
	model:SetAttribute("Phase12FormationLOD", if lod == "Full" then nil else lod)
	model:PivotTo(entry.target)
	destroyView(entry)
	local handle = Ownership.Bind(row.id, row.revision, row.state)
	entry.owner = handle
	model:SetAttribute("BindGeneration", handle.generation)
	model:SetAttribute("PresentationRevision", row.revision)
	local root = model.PrimaryPart
	local proxy = Controller.ResolveAuthority(model)
	local moving = row.state == "Cart" or row.state == "Carried"
	if root then
		local jointed = {}
		for _, x in ipairs(model:GetDescendants()) do
			if x:IsA("JointInstance") or x:IsA("WeldConstraint") then
				if x.Part1 then
					jointed[x.Part1] = true
				end
			end
		end
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = part == root
				part.Massless = true
				part.CastShadow = false
				if part ~= root and not jointed[part] then
					local weld = Instance.new("WeldConstraint")
					weld.Name = "PresentationInternalRigid"
					weld.Part0 = root
					weld.Part1 = part
					weld.Parent = root
				end
			end
		end
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		if moving and proxy and proxy.PrimaryPart then
			model:PivotTo(proxy:GetPivot())
			root.Anchored = false
			root.RootPriority = -127
			local mount = Instance.new("WeldConstraint")
			mount.Name = "PresentationTransport"
			mount.Part0 = proxy.PrimaryPart
			mount.Part1 = root
			mount.Parent = root
			entry.transport = mount
			Ownership.Own(handle, function()
				mount:Destroy()
			end)
			local connection = proxy.AncestryChanged:Connect(function()
				if
					Ownership.IsCurrent(handle, row.id, row.revision, row.state)
					and not proxy:IsDescendantOf(workspace)
				then
					destroyView(entry)
				end
			end)
			Ownership.Own(handle, function()
				connection:Disconnect()
			end)
		end
	end
	entry.model, entry.lod = model, lod
	entry.previous, entry.at, entry.settled = entry.target, os.clock(), true
	if entry.popPending then
		entry.popPending = nil
		task.defer(catchPop, model)
	end
	model.Parent = if row.state == "Deposited"
			and proxy
			and proxy.Parent
		then proxy.Parent
		else folder
	Ownership.Own(handle, function()
		model:Destroy()
	end)
	Collection:AddTag(model, Display.CollectionTag)
	Anim.Attach(entry)
	return true
end
local function accept(packet)
	local oldEpoch, oldRegion = packetState.epoch, packetState.regionId
	if not Rules.AcceptPacket(packetState, packet) then
		rejected += 1
		return false
	end
	if packet.kind == "Context" then
		if oldEpoch ~= packet.epoch then
			if oldRegion ~= nil then
				interestExits += 1
			end
			if packet.regionId ~= nil then
				interestEntries += 1
			end
		end
		clear()
		contextChanges += 1
		contextAt = os.clock()
		packetState.regionId = packet.regionId
		Cache.SetEpoch(packet.epoch)
		return true
	end
	if
		packet.kind ~= "Delta"
		or type(packet.upserts) ~= "table"
		or type(packet.removals) ~= "table"
		or #packet.upserts > Config.MaxPacketEntities
		or #packet.removals > Config.MaxPacketEntities
	then
		return false
	end
	for _, removed in packet.removals do
		local entry = entries[removed.id]
		if Rules.AcceptEntity(entry and entry.row or tombstones[removed.id], removed) then
			if entry then
				destroyView(entry)
				entries[removed.id] = nil
			end
			tombstones[removed.id] = removed
			table.insert(tombstoneOrder, removed.id)
			while #tombstoneOrder > Config.MaxTombstones do
				local expired = table.remove(tombstoneOrder, 1)
				tombstones[expired] = nil
			end
		end
	end
	for _, row in packet.upserts do
		local entry = entries[row.id]
		if
			type(row.attributes) == "table"
			and typeof(row.pose) == "CFrame"
			and Rules.IsFinite(row.scale)
			and row.scale > 0
			and Rules.ValidTemplate(row.speciesId, "Full")
			and Rules.AcceptEntity(entry and entry.row or tombstones[row.id], row)
		then
			local was = entry and entry.row
			if
				entry
				and was
				and (
					was.state ~= row.state
					or was.generation ~= row.generation
					or was.sourceGeneration ~= row.sourceGeneration
				)
			then
				destroyView(entry)
				if
					was.state ~= row.state
					and (row.state == "Cart" or row.state == "Carried")
					and PlaytestFlags.Part("SizeLadder")
				then
					entry.popPending = true
				end
				-- Catch reveal and bank: the new view opens with Celebrate (animated views only).
				if
					was.state ~= row.state
					and (row.state == "Carried" or row.state == "Cart" or row.state == "Deposited")
					and Anim.Available()
				then
					entry.celebratePending = true
				end
			end
			if not entry then
				entry = {}
				entries[row.id] = entry
				-- A catch arrives as a new row: celebrate your own fresh ones, never the rows that
				-- were already there when the interest snapshot loaded.
				local me = Players.LocalPlayer and Players.LocalPlayer.UserId
				if
					(row.state == "Cart" or row.state == "Carried")
					and os.clock() - contextAt > 3
					and (row.attributes.OwnerUserId == me or row.attributes.Phase10OwnerUserId == me or row.attributes.CarrierUserId == me)
					and Anim.Available()
				then
					entry.celebratePending = true
				end
			end
			-- A bank: the row was seen pending (PendingBank = true) and is now Deposited. This holds
			-- across the interest snapshot that arriving at the base triggers.
			if row.attributes.PendingBank == true then
				pendingBankSeen[row.id] = true
			elseif pendingBankSeen[row.id] and row.state == "Deposited" then
				pendingBankSeen[row.id] = nil
				if entry.anim then
					entry.anim.celebrate = true
				elseif Anim.Available() then
					entry.celebratePending = true
				end
			end
			if entry.target ~= row.pose then
				entry.previous = if entry.model then entry.model:GetPivot() else row.pose
				entry.target, entry.at, entry.settled =
					row.pose, os.clock(), row.state == "Deposited"
				if entry.model and row.state == "Deposited" then
					entry.model:PivotTo(row.pose)
				end
			end
			entry.row = row
			if entry.model then
				if was.speciesId ~= row.speciesId or was.scale ~= row.scale then
					destroyView(entry)
				elseif was.revision ~= row.revision then
					copyAttributes(entry.model, row)
					applyQueryPolicy(entry.model, row)
				end
			end
		end
	end
	return true
end
-- Local hit feedback resolves only to a current replicated authority handle.
-- A local part or its HP/state never authorizes a server interaction.
function Controller.ResolveAuthority(instance)
	local model = instance
	while model and model ~= workspace do
		if model:IsA("Model") and model:GetAttribute("CreatureLocalVisual") == true then
			break
		end
		model = model.Parent
	end
	if not model or model == workspace then
		return nil
	end
	local id = model:GetAttribute("CreatureProtocolId")
	local entry = entries[id]
	if not entry then
		return nil
	end
	local proxy = entry.proxy
	if
		proxy
		and proxy.Parent
		and proxy:IsDescendantOf(workspace)
		and proxy:GetAttribute("ItemId") == id
	then
		return proxy
	end
	for _, candidate in Collection:GetTagged(Display.CollectionTag) do
		if
			candidate:IsA("Model")
			and candidate:GetAttribute("CreatureProxy") == true
			and candidate:IsDescendantOf(workspace)
			and (candidate:GetAttribute("ItemId") or candidate:GetAttribute("DecoyId")) == id
		then
			entry.proxy = candidate
			return candidate
		end
	end
	return nil
end
function Controller.ResolveVisual(model)
	if model and model:GetAttribute("CreatureProxy") == true then
		local entry = entries[model:GetAttribute("ItemId") or model:GetAttribute("DecoyId")]
		return entry and entry.model
	end
	return model
end
function Controller.GetWorldModels()
	local result = {}
	for _, entry in entries do
		if entry.model and (entry.row.state == "Awake" or entry.row.state == "Sleeping") then
			table.insert(result, entry.model)
		end
	end
	return result
end
function Controller.GetSnapshot()
	local result = {}
	for id, entry in entries do
		table.insert(result, {
			id = id,
			speciesId = entry.row.speciesId,
			regionId = entry.row.regionId,
			state = entry.row.state,
			revision = entry.row.revision,
			generation = entry.row.generation,
			bindGeneration = entry.owner and entry.owner.generation,
			transportAttachments = if entry.transport then 1 else 0,
			rendered = entry.model ~= nil,
			lod = entry.lod,
		})
	end
	return result
end
function Controller.IsPresentationCurrent(model, revision, generation)
	local id = model:GetAttribute("CreatureProtocolId")
	local entry = id and entries[id]
	return entry ~= nil
		and entry.model == model
		and entry.owner ~= nil
		and entry.owner.generation == generation
		and Ownership.IsCurrent(entry.owner, id, revision, entry.row.state)
end
function Controller.GetDiagnostics()
	local count, parts, pending = 0, 0, 0
	local authorityProxies, localFullModels, localReducedModels = 0, 0, 0
	for _, model in Collection:GetTagged(Display.CollectionTag) do
		if model:IsA("Model") and model:IsDescendantOf(workspace) then
			if model:GetAttribute("CreatureProxy") == true then
				authorityProxies += 1
			elseif
				model:GetAttribute("CreatureLocalVisual") == true
				or model:GetAttribute("Phase12FormationLOD") ~= nil
			then
				local lod = model:GetAttribute("Phase12FormationLOD")
				if lod == nil or lod == "Detailed" then
					localFullModels += 1
				else
					localReducedModels += 1
				end
			end
		end
	end
	for _, entry in entries do
		count += 1
		if not entry.model then
			pending += 1
		else
			for _, part in entry.model:GetDescendants() do
				if part:IsA("BasePart") then
					parts += 1
				end
			end
		end
	end
	return {
		interestEntries = interestEntries,
		interestExits = interestExits,
		authorityProxies = authorityProxies,
		localFullModels = localFullModels,
		localReducedModels = localReducedModels,
		regionId = packetState.regionId,
		epoch = packetState.epoch,
		sequence = packetState.sequence,
		connections = #connections,
		entries = count,
		renderedParts = parts,
		pendingTemplates = pending,
		rejectedPackets = rejected,
		contextChanges = contextChanges,
		frames = frames,
		detailedBaseModels = detailed,
		resolvedPresentationQuality = ResolvedQuality.GetDiagnostics(
			if Players.LocalPlayer then Players.LocalPlayer:GetAttribute("VFXQuality") else nil
		),
		cache = Cache.GetDiagnostics(),
	}
end
-- Disposable native fixtures exercise the actual receiver without starting a
-- renderer or a second heartbeat. Shipping callers cannot access this seam.
function Controller._AcceptForTesting(packet)
	assert(
		Run:IsStudio()
			and game:GetAttribute("BrainrotTestDiagnosticsDisabled") == true
			and not active,
		"Disposable inactive fixture required"
	)
	return accept(packet)
end
function Controller._ClearForTesting()
	assert(
		Run:IsStudio()
			and game:GetAttribute("BrainrotTestDiagnosticsDisabled") == true
			and not active,
		"Disposable inactive fixture required"
	)
	clear()
	packetState.epoch, packetState.sequence, packetState.regionId = -1, -1, nil
end
function Controller.Start()
	if active then
		return false
	end
	-- Server chooses the mode before creating world representations. A missing
	-- protocol remote cannot silently create a second legacy rendering path.
	local remotes = RS:WaitForChild("Remotes")
	remote = remotes:WaitForChild(Config.RemoteName, 20)
	if not remote or RS:GetAttribute("Phase13CreatureProtocolEnabled") ~= true then
		return false
	end
	active = true
	lifecycle += 1
	local ownerGeneration = lifecycle
	folder = Instance.new("Folder")
	folder.Name = "Phase13CreatureVisuals"
	folder.Parent = workspace
	Cache.Start(remote)
	table.insert(connections, remote.OnClientEvent:Connect(accept))
	remote:FireServer({ kind = "Context" })
	task.delay(1.1, function()
		if active and ownerGeneration == lifecycle and packetState.epoch < 0 then
			remote:FireServer({ kind = "Context" })
		end
	end)
	local lastLOD, version = 0, -1
	table.insert(
		connections,
		Run.RenderStepped:Connect(function(dt)
			frames += 1
			local now, camera = os.clock(), workspace.CurrentCamera
			local refresh = now - lastLOD >= 0.25 or version ~= Provider.GetVersion()
			if refresh then
				lastLOD, version = now, Provider.GetVersion()
				local base = {}
				for _, entry in entries do
					if entry.row.state == "Deposited" then
						table.insert(base, {
							entry = entry,
							distance = if camera
								then (entry.target.Position - camera.CFrame.Position).Magnitude
								else math.huge,
							owner = entry.row.attributes.OwnerUserId == Players.LocalPlayer.UserId
								or entry.row.attributes.Phase10OwnerUserId
									== Players.LocalPlayer.UserId,
						})
					elseif
						not entry.model
						or (
							(entry.row.state == "Cart" or entry.row.state == "Carried")
							and not entry.transport
						)
					then
						createView(entry, "Full")
					end
				end
				table.sort(base, function(a, b)
					return if a.owner ~= b.owner then a.owner else a.distance < b.distance
				end)
				detailed = 0
				for _, candidate in base do
					local entry = candidate.entry
					local lod = "Full" -- Every admitted world role uses its complete canonical model.
					entry.hidden = Rules.ShouldHideBase(candidate.distance, entry.hidden)
					if entry.hidden then
						destroyView(entry)
					else
						if not entry.model or entry.lod ~= lod then
							createView(entry, lod)
						end
						if entry.model and entry.lod == "Full" then
							detailed += 1
						end
					end
				end
				Players.LocalPlayer:SetAttribute("Phase13DetailedBaseModels", detailed)
				Anim.RefreshLod(entries, camera)
				if PlaytestFlags.Part("SizeLadder") and camera then
					local catalog = require(RS.Shared.Config.BrainrotCatalog)
					for _, entry in entries do
						local state = entry.row.state
						if entry.model and (state == "Awake" or state == "Sleeping") then
							local rarity = catalog.GetRarity(entry.row.speciesId)
							if
								rarity
								and SIGHTING_RARITIES[rarity]
								and not sightedRarities[rarity]
								and (entry.target.Position - camera.CFrame.Position).Magnitude
									<= Ladder.FirstSightingRadius
							then
								sightedRarities[rarity] = true
								sightingBeat(entry.model, rarity)
							end
						end
					end
				end
			end
			local serverNow = workspace:GetServerTimeNow()
			for _, entry in entries do
				-- Animated wild views use the smoothed pose; everything else keeps the lerp.
				local smoothed = entry.anim ~= nil
					and not entry.transport
					and Anim.Smooth(entry, dt)
				if entry.anim then
					Anim.Update(entry, serverNow)
				end
				if not smoothed and entry.model and not entry.transport and not entry.settled then
					entry.model:PivotTo(
						Rules.Interpolate(
							entry.previous,
							entry.target,
							now - entry.at,
							Config.InterpolationSeconds
						)
					)
					if now - entry.at >= Config.InterpolationSeconds then
						entry.settled = true
					end
				end
			end
		end)
	)
	return true
end
function Controller.Stop()
	lifecycle += 1
	active = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	Cache.Stop()
	packetState.epoch, packetState.sequence, packetState.regionId = -1, -1, nil
	remote = nil
end
return Controller
