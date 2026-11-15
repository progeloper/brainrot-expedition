--!strict
-- One bounded scheduler owns reversible local presentation. Collision stays server-owned.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ResolvedQuality = require(RS.Shared.Utility.ResolvedPresentationQuality)
local BaseSlots = require(RS.Shared.Utility.BaseSlotPresentation)
local PresentationPolicy = require(RS.Shared.Utility.RegionPresentationPolicy)
local RemoteBinding = require(script.Parent.Parent.Utility.RemoteDependencyBinding)
local Weapons = require(RS.Shared.Config.Weapons)
local Carts = require(RS.Shared.Config.Carts)
local Phase13 = require(RS.Shared.Config.Phase13)
local Teams = require(RS.Shared.Config.ChariotTeam)
local Handling = require(RS.Shared.Config.CartHandlingConfig)
local HandlingMath = require(RS.Shared.Utility.CartHandlingMath)
local LocalCart = require(script.Parent.Parent.State.LocalCartState)
local Geometry = require(RS.Shared.Config.CartGeometry)
local maximumRange, maximumSpeed = 0, 0
for _, definition in Weapons.GetAll() do
	maximumRange = math.max(maximumRange, definition.stats.rangeStuds)
end
for _, definition in Carts do
	maximumSpeed = math.max(
		maximumSpeed,
		definition.MaxTravelSpeed
			* (1 + 0.1 * Phase13.MaxSpeedLevel)
			* (1 + Teams.EffectCaps.Speed)
			* Teams.Burst.SpeedMultiplier
	)
end
-- Fastest legitimate class + purchased levels + equipped effects + Burst.
-- Readiness latency is conservatively assumed, not measured on a phone.
local halfLength = 0
for _,g in pairs(Geometry) do if not g.DevelopmentOnly then halfLength=math.max(halfLength,g.RootSize.Z/2) end end
local planningStoppingDistance = maximumSpeed^2/(2*(Handling.Braking*(maximumSpeed/Handling.StarterSpeed)*0.9))
local measuredStoppingDistance = 0 -- old slow-controller measurements are historical
local protectedRadius = math.max(maximumRange+32,HandlingMath.VisibleDistance(maximumSpeed,
    Handling.Braking*(maximumSpeed/Handling.StarterSpeed)*0.9,halfLength))
local streamPending=false
local streamGeneration=0
local streamKey=nil
local streamSession=nil
local streamCart=nil
local lastStreamAt=-math.huge
local streamRequests=0

local remoteBinding = nil
local registrationGeneration = 0
local dependencyState, dependencyReason = "Loading", "WAITING_FOR_Phase13Interest"
local player = Players.LocalPlayer
local Controller = {}
local current = nil
local unlocked = {}
local sequence = -1
local active = false
local connections = {}
local heartbeatConnection = nil
local records = {}
local spatialRecords = {}
local lastSpatialCameraPosition = nil
local lastSpatialCharacterPosition = nil
local nextOptionalReleaseAt = nil
local arrivalSerial, immediateApplications, spatialPasses = 0, 0, 0
local hiddenNativeRecords = {}
local ancestorBindings = {}
local slotGroups = {}
local storedRecords = {}
local bindingRebuilds, semanticEvaluations, storedRecordVisits, distanceEvaluations = 0, 0, 0, 0
local apply, hiddenValue, bindRecord, updateStoredRegistration, presentRecord
local knownModels = {}
local modelConnections = {}
local avatarConnections = {}
local dynamicRoots = {}
local movingRegionCache = {}
local cacheEpoch, syncSerial = 0, 0
local regionLookups = 0
local dirty = true
local floors = {}
local avatarRoots = {}
local storedModels = {}
local proxyFolder = nil
local names = {
	Forest = "REGION_FOREST",
	Beach = "REGION_BEACH",
	Swamp = "REGION_SWAMP",
	Jungle = "REGION_JUNGLE",
	Arctic = "REGION_ARCTIC",
	Volcano = "REGION_VOLCANO",
	["Glitch Zone"] = "REGION_GLITCH",
	Camp = "REGION_CAMP",
}
local function regionOf(instance)
	regionLookups += 1
	for other, character in avatarRoots do
		if other ~= player and character and instance:IsDescendantOf(character) then
			return other:GetAttribute("Phase13RegionId") or "UNREADY"
		end
	end
	local p = instance
	local candidate = nil
	local inMap = false
	while p and p ~= workspace do
		if p:GetAttribute("GlobalNavigationFacade") == true or p.Name == "ProgressionGates" then
			return nil
		end
		local id = p:GetAttribute("RegionId") or p:GetAttribute("SpawnRegionId") or p:GetAttribute("HomeRegionId")
		if type(id) == "string" and id:match("^REGION_") then
			return id
		end
		if p.Parent and p.Parent.Name == "MapBlockout" and names[p.Name] then
			return names[p.Name]
		end
		if p:IsA("BasePart") then
			candidate = candidate or p.Position
		elseif p:IsA("Model") then
			candidate = candidate or p:GetPivot().Position
		end
		if p.Name == "MapBlockout" then
			inMap = true
		end
		p = p.Parent
	end
	if candidate then
		for floor, id in floors do
			if floor.Parent then
				local q = floor.CFrame:PointToObjectSpace(candidate)
				if math.abs(q.X) <= floor.Size.X / 2 and math.abs(q.Z) <= floor.Size.Z / 2 then
					return id
				end
			end
		end
	end
	return if inMap then "UNREADY" else nil
end
function Controller.GetRegion()
	return current
end
function Controller.IsRegionVisible(id)
	return current ~= nil and id == current and unlocked[id] == true
end
function Controller.IsVisible(value)
	local id = if type(value) == "string" then value else regionOf(value)
	return id == nil or Controller.IsRegionVisible(id)
end
local function acceptContext(message)
	if
		type(message) ~= "table"
		or message.kind ~= "Context"
		or type(message.sequence) ~= "number"
		or message.sequence ~= message.sequence
		or message.sequence % 1 ~= 0
		or message.sequence <= sequence
		or (message.regionId ~= nil and (type(message.regionId) ~= "string" or not message.regionId:match("^REGION_")))
		or type(message.unlocked) ~= "table"
	then
		return false
	end
	local allowed = {}
	for id, value in message.unlocked do
		if type(id) == "string" and id:match("^REGION_") and value == true then
			allowed[id] = true
		end
	end
	sequence = message.sequence
	current = message.regionId
	unlocked = allowed
	cacheEpoch += 1
	dirty = true
	if player then
		player:SetAttribute("Phase13VisibleRegionId", current)
	end
	return true
end
local function movingRoot(instance)
	local p = instance
	while p and p ~= workspace do
		if
			p:IsA("Model")
			and (
				dynamicRoots[p]
				or p:GetAttribute("RuntimeCart") == true
				or (p.Parent and p.Parent.Name == "Brainrots" and p.Parent.Parent and p.Parent.Parent.Name == "Runtime")
			)
		then
			return p
		end
		p = p.Parent
	end
	return nil
end
local function cachedRegion(instance, record)
	if record.cacheEpoch ~= cacheEpoch or record.parent ~= instance.Parent then
		record.parent = instance.Parent
		record.cacheEpoch = cacheEpoch
		record.moving = movingRoot(instance)
		if not record.moving then
			record.regionId = regionOf(instance)
		end
	end
	if record.moving then
		local cached = movingRegionCache[record.moving]
		if not cached or cached.serial ~= syncSerial or cached.epoch ~= cacheEpoch then
			cached = { serial = syncSerial, epoch = cacheEpoch, regionId = regionOf(record.moving) }
			movingRegionCache[record.moving] = cached
		end
		return cached.regionId
	end
	return record.regionId
end
local function floorRegion(instance)
	local p = instance.Parent
	while p and p ~= workspace do
		local id = p:GetAttribute("RegionId")
		if type(id) == "string" and id:match("^REGION_") then
			return id
		end
		if names[p.Name] then
			return names[p.Name]
		end
		p = p.Parent
	end
	return nil
end
local function refreshFloorRegistration(instance)
	if not instance:IsA("BasePart") then
		return
	end
	local owner = if instance:GetAttribute("LayoutRole") == "Floor"
			and instance:GetAttribute("GeneratedBy") == "CreateBasicMap_v1"
		then floorRegion(instance)
		else nil
	if floors[instance] ~= owner then
		floors[instance] = owner
		cacheEpoch += 1
	end
end

local function refreshSlotGroup(group)
	semanticEvaluations += 1
	group.active = BaseSlots.IsActive(group.root)
	local hiddenProxies = {}
	for instance, record in group.records do
		record.slotActive = group.active
		-- Assignment/token invalidation must hide before the next distance pass.
		if group.active == false and instance.Parent then
			pcall(apply, instance, record, true)
			local stored = record.stored and storedModels[record.stored]
			if stored and stored.proxy and not hiddenProxies[stored] then
				hiddenProxies[stored] = true
				for _, part in stored.proxyParts do
					part.LocalTransparencyModifier = 1
				end
			end
		elseif instance.Parent and presentRecord then
			pcall(presentRecord, instance, record)
		end
	end
	dirty = true
end
local function releaseRecordBindings(instance, record)
	if record.ancestryConnection then
		record.ancestryConnection:Disconnect()
		record.ancestryConnection = nil
	end
	if record.slotGroup then
		local group = record.slotGroup
		group.records[instance] = nil
		if next(group.records) == nil then
			slotGroups[group.root] = nil
		end
		record.slotGroup = nil
	end
	for _, node in record.bindingPath or {} do
		local binding = ancestorBindings[node]
		if binding then
			binding.records[instance] = nil
			if next(binding.records) == nil then
				binding.attributes:Disconnect()
				if binding.name then
					binding.name:Disconnect()
				end
				ancestorBindings[node] = nil
			end
		end
	end
	record.bindingPath = nil
	local stored = record.stored and storedModels[record.stored]
	if stored then
		stored.records[instance] = nil
	end
	storedRecords[instance] = nil
end
local function rebindAffected(node)
	local binding = ancestorBindings[node]
	if not binding then
		return
	end
	-- Rebinding changes memberships and may release the binding itself.
	local affected = {}
	for instance, record in binding.records do
		table.insert(affected, { instance, record })
	end
	for _, row in affected do
		if records[row[1]] == row[2] then
			bindRecord(row[1], row[2])
		end
	end
	local groups = {}
	for _, row in affected do
		if row[2].slotGroup then
			groups[row[2].slotGroup] = true
		end
	end
	for group in groups do
		refreshSlotGroup(group)
	end
	dirty = true
end
local structuralAttributes = {
	BaseRequiredStage = true,
	BasePresentationManaged = true,
	LayoutRole = true,
	PresentationClass = true,
	VisibilityOwner = true,
	RuntimeCart = true,
	GeneratedBy = true,
}
local slotAttributes = {
	BasePresentationState = true,
	OwnerUserId = true,
	BaseOwnershipRevision = true,
	BaseSlotState = true,
	BaseSlotIndex = true,
}
local function watchAncestor(node)
	local binding = ancestorBindings[node]
	if binding then
		return binding
	end
	binding = { records = {} }
	ancestorBindings[node] = binding
	binding.attributes = node.AttributeChanged:Connect(function(key)
		if ancestorBindings[node] ~= binding then
			return
		end
		local own = records[node]
		if own and (key == "BaseAuthored_" .. own.property or key == "BaseContent_" .. own.property) then
			own.authored = BaseSlots.GetAuthoredProperty(node, own.property)
			if own.authored ~= nil then
				own.original = own.authored
			end
			pcall(apply, node, own, own.hidden)
			dirty = true
		end
		if structuralAttributes[key] then
			refreshFloorRegistration(node)
			rebindAffected(node)
		elseif slotAttributes[key] then
			local groups = {}
			for _, record in binding.records do
				if record.slotGroup then
					groups[record.slotGroup] = true
				end
			end
			for group in groups do
				refreshSlotGroup(group)
			end
		elseif
			key == "RegionId"
			or key == "SpawnRegionId"
			or key == "HomeRegionId"
			or key == "GlobalNavigationFacade"
		then
			cacheEpoch += 1
			dirty = true
		elseif key == "CreatureProxy" then
			updateStoredRegistration(node)
			rebindAffected(node)
		end
	end)
	if node:IsA("Model") or node:IsA("Folder") then
		binding.name = node:GetPropertyChangedSignal("Name"):Connect(function()
			if ancestorBindings[node] ~= binding then
				return
			end
			updateStoredRegistration(node)
			cacheEpoch += 1
			rebindAffected(node)
		end)
	end
	return binding
end
bindRecord = function(instance, record, refresh)
	releaseRecordBindings(instance, record)
	bindingRebuilds += 1
	local path, semantic, stored, part = {}, nil, nil, nil
	local semanticStopped = false
	local node = instance
	while node and node ~= game do
		table.insert(path, node)
		watchAncestor(node).records[instance] = record
		if not semantic and not semanticStopped and node:GetAttribute("BaseRequiredStage") ~= nil then
			semantic = node
		end
		semanticStopped = semanticStopped or node:GetAttribute("BasePresentationManaged") == true
		stored = stored or (if storedModels[node] then node else nil)
		part = part or (if node:IsA("BasePart") then node else nil)
		if node == workspace then
			break
		end
		node = node.Parent
	end
	record.bindingPath = path
	record.stored, record.part = stored, part
	record.lodHidden = nil
	if stored then
		storedRecords[instance] = record
		local state = storedModels[stored]
		state.records[instance] = record
		record.lodHidden = state.hidden or state.reduced
	end
	local classification
	record.inMap, record.mandatory, classification = PresentationPolicy.Classify(instance)
	record.classification=classification
	record.critical=classification=="CriticalBoundary"or classification=="CriticalRoute"
	record.externalVisibilityOwner=false
	for _,ancestor in ipairs(path)do if ancestor:GetAttribute("VisibilityOwner")=="GateAccess"then record.externalVisibilityOwner=true;break end end
	spatialRecords[instance] = if record.inMap then record else nil
	record.optionalVisible, record.optionalReleaseAt = false, nil
	record.cacheEpoch = nil
	record.slotActive = nil
	if semantic then
		local group = slotGroups[semantic]
		if not group then
			semanticEvaluations += 1
			group = { root = semantic, active = BaseSlots.IsActive(semantic), records = {} }
			slotGroups[semantic] = group
		elseif refresh then
			refreshSlotGroup(group)
		end
		group.records[instance] = record
		record.slotGroup = group
		record.slotActive = group.active
	end
	record.bindingRevision = (record.bindingRevision or 0) + 1
	local revision = record.bindingRevision
	record.ancestryConnection = instance.AncestryChanged:Connect(function()
		if records[instance] == record and record.bindingRevision == revision then
			bindRecord(instance, record, true)
			dirty = true
		end
	end)
	if record.slotActive == false and instance.Parent then
		pcall(apply, instance, record, true)
		local state = record.stored and storedModels[record.stored]
		if state and state.proxy then
			for _, proxyPart in state.proxyParts do
				proxyPart.LocalTransparencyModifier = 1
			end
		end
	end
	refreshFloorRegistration(instance)
	-- Arrival/reparent/late semantic data must not wait for a periodic full pass.
	if presentRecord and instance.Parent then
		immediateApplications += 1
		pcall(presentRecord, instance, record)
	end
end
updateStoredRegistration = function(instance)
	if not instance:IsA("Model") then
		return
	end
	local shouldStore = instance.Name:match("^Stored_") and instance:GetAttribute("CreatureProxy") ~= true
	local state = storedModels[instance]
	if shouldStore and not state then
		storedModels[instance] = { proxy = nil, hidden = false, records = {} }
		rebindAffected(instance)
	elseif not shouldStore and state then
		if state.proxy then
			state.proxy:Destroy()
		end
		storedModels[instance] = nil
		rebindAffected(instance)
	end
end

local function remember(instance)
	if proxyFolder and instance:IsDescendantOf(proxyFolder) then
		return
	end
	if instance:IsA("Model") then
		knownModels[instance] = true
	end
	updateStoredRegistration(instance)
	if
		instance:IsA("BasePart")
		and instance:GetAttribute("LayoutRole") == "Floor"
		and instance:GetAttribute("GeneratedBy") == "CreateBasicMap_v1"
	then
		local owner = floorRegion(instance)
		if owner then
			floors[instance] = owner
			cacheEpoch += 1
		end
	end
	if instance:IsA("Model") and not modelConnections[instance] then
		local list = {}
		modelConnections[instance] = list
		for _, key in { "RegionId", "SpawnRegionId", "HomeRegionId" } do
			table.insert(
				list,
				instance:GetAttributeChangedSignal(key):Connect(function()
					dirty = true
					cacheEpoch += 1
				end)
			)
		end
		table.insert(
			list,
			instance.AncestryChanged:Connect(function()
				if not movingRoot(instance) then
					cacheEpoch += 1
				end
				dirty = true
			end)
		)
	end

	if records[instance] then
		return
	end
	local property = nil
	if instance:IsA("BasePart") then
		property = "LocalTransparencyModifier"
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		property = "Transparency"
	elseif
		instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Highlight")
		or instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("ProximityPrompt")
		or instance:IsA("Light")
	then
		property = "Enabled"
	elseif instance:IsA("Sound") then
		property = "Volume"
	elseif instance:IsA("Humanoid") then
		property = "DisplayDistanceType"
	end
	if property then
		local authored = BaseSlots.GetAuthoredProperty(instance, property)
		arrivalSerial += 1
		local record = {
			arrivedAt = os.clock(),
			generation = arrivalSerial,
			property = property,
			authored = authored,
			original = if authored ~= nil then authored else instance[property],
			hidden = false,
		}
		records[instance] = record
		bindRecord(instance, record)
	end
end
hiddenValue = function(property)
	if property == "LocalTransparencyModifier" or property == "Transparency" then
		return 1
	end
	if property == "Volume" then
		return 0
	end
	if property == "DisplayDistanceType" then
		return Enum.HumanoidDisplayDistanceType.None
	end
	return false
end
apply = function(instance, record, hidden)
	if record.externalVisibilityOwner then return end
	local property = record.property
	local propertyValue = instance[property]
	local permitted = record.slotActive
	local authored = record.authored
	if authored ~= nil then
		record.original = authored
	end
	hidden = hidden or permitted == false
	if hidden then
		local value = hiddenValue(property)
		if authored == nil and (not record.hidden or propertyValue ~= record.applied) then
			record.original = propertyValue
		end
		if propertyValue ~= value then
			instance[property] = value
		end
		record.hidden, record.applied = true, value
		if property ~= "LocalTransparencyModifier" then
			hiddenNativeRecords[instance] = record
		end
	elseif record.hidden then
		-- A replicated/native write may arrive immediately before region entry.
		if authored == nil and propertyValue ~= record.applied then
			record.original = propertyValue
		end
		if propertyValue ~= record.original then
			instance[property] = record.original
		end
		record.hidden, record.applied = false, nil
		hiddenNativeRecords[instance] = nil
	elseif authored == nil then
		record.original = propertyValue
	elseif propertyValue ~= authored then
		instance[property] = authored
	end
end
local function release(instance, record)
	-- Streaming may reuse the same client instance. Return local overrides before
	-- forgetting it, otherwise re-entry captures our own hidden value as authored.
	local authored = record.authored
	local value = if authored ~= nil then authored else record.original
	if record.slotActive == false and record.property ~= "LocalTransparencyModifier" then
		value = hiddenValue(record.property)
	end
	if record.hidden and instance[record.property] == record.applied then
		instance[record.property] = value
	end
end
local function forget(instance)
	local record = records[instance]
	if record then
		pcall(release, instance, record)
		releaseRecordBindings(instance, record)
	end
	records[instance] = nil
	spatialRecords[instance] = nil
	hiddenNativeRecords[instance] = nil
	local state = storedModels[instance]
	if state and state.proxy then
		state.proxy:Destroy()
	end
	storedModels[instance] = nil
	rebindAffected(instance)
	if modelConnections[instance] then
		for _, connection in modelConnections[instance] do
			connection:Disconnect()
		end
		modelConnections[instance] = nil
	end
	knownModels[instance], movingRegionCache[instance] = nil, nil
	if floors[instance] then
		cacheEpoch += 1
	end
	floors[instance] = nil
	dirty = true
end
local function enforceHiddenNativeProperties()
	-- LTM is client-only and cannot be overwritten by a server property update.
	-- Poll only the cached native properties that can replicate while hidden;
	-- no descendant rescans or per-property signal connections are introduced.
	for instance, record in hiddenNativeRecords do
		if record.hidden and instance.Parent then
			pcall(apply, instance, record, true)
		end
	end
end
local function isOwner(model)
	if not player then
		return false
	end
	local p = model
	while p and p ~= workspace do
		if p:GetAttribute("OwnerUserId") == player.UserId then
			return true
		end
		p = p.Parent
	end
	return false
end
-- Stored records whose LOD state changed in the last syncLOD pass; only these (and records under
-- moving roots) are re-presented on the 0.5 s tick instead of a full sync of every record.
local lodChanged = {}
local function syncLOD()
	if next(storedModels) == nil then
		if player and player:GetAttribute("Phase13DetailedBaseModels") ~= 0 then
			player:SetAttribute("Phase13DetailedBaseModels", 0)
		end
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	debug.profilebegin("RegionVisibility.StoredLOD")
	local ranked = {}
	for model, state in storedModels do
		if not model.Parent then
			if state.proxy then
				state.proxy:Destroy()
			end
			storedModels[model] = nil
			continue
		end
		table.insert(ranked, {
			model = model,
			state = state,
			distance = (model:GetPivot().Position - camera.CFrame.Position).Magnitude,
			owner = isOwner(model),
		})
	end
	table.sort(ranked, function(a, b)
		if a.owner ~= b.owner then
			return a.owner
		end
		return a.distance < b.distance
	end)
	local limit = ResolvedQuality.GetPlatformDetailCap(if player then player:GetAttribute("VFXQuality") else nil)
	local count = 0
	for index, row in ranked do
		local state = row.state
		local permitted = next(state.records) ~= nil
		for _, record in state.records do
			if record.slotActive == false then
				permitted = false
				break
			end
		end
		local visible = Controller.IsRegionVisible("REGION_CAMP")
			and permitted
			and row.distance <= (if state.hidden then 160 else 180)
		local reduced = visible and (index > limit or row.distance > 80)
		state.hidden = not visible
		state.reduced = reduced
		if visible and not reduced then
			count += 1
		end
		if reduced and not state.proxy then
			local species = row.model:GetAttribute("BrainrotId")
			local presentation = require(RS.Shared.Utility.ChariotPresentation)
			local proxy = presentation.Clone(species or "", "Reduced")
			proxy.Name = "ReducedBaseDisplay"
			local _, bounds = row.model:GetBoundingBox()
			presentation.Fit(proxy, bounds.X, bounds.Y, bounds.Z)
			state.proxyParts = {}
			for _, p in proxy:GetDescendants() do
				if p:IsA("BasePart") then
					table.insert(state.proxyParts, p)
					p.Anchored = true
					p.CanCollide = false
					p.CanTouch = false
					p.CanQuery = false
				elseif p:IsA("Light") or p:IsA("LuaSourceContainer") or p:IsA("ParticleEmitter") then
					p:Destroy()
				end
			end
			proxy:PivotTo(row.model:GetPivot())
			proxy.Parent = proxyFolder
			state.proxy = proxy
		end
		if state.proxy then
			for _, p in state.proxyParts do
				p.LocalTransparencyModifier = if reduced then 0 else 1
			end
		end
	end
	for instance, record in storedRecords do
		storedRecordVisits += 1
		if not instance.Parent then
			forget(instance)
			continue
		end
		local model = record.stored
		if model then
			local state = storedModels[model]
			local lodHidden = state and (state.hidden or state.reduced)
			if lodHidden ~= record.lodHidden then
				record.lodHidden = lodHidden
				lodChanged[instance] = record
			end
		end
	end
	if player and player:GetAttribute("Phase13DetailedBaseModels") ~= count then
		player:SetAttribute("Phase13DetailedBaseModels", count)
	end
	debug.profileend()
end

-- Apply one registered instance. Cached region/semantic authority stays owned by
-- the existing record; arrival work does not trigger an all-Workspace scan.
presentRecord = function(instance, record, camera, now)
	camera = camera or workspace.CurrentCamera
	now = now or os.clock()
	local allowed = if sequence < 0 then { REGION_CAMP = true } else unlocked
	local id = cachedRegion(instance, record)
	local visible = id == nil or Controller.IsRegionVisible(id)
    if record.inMap and not record.critical then
        local distance=math.huge
        local authorized=id==nil or allowed[id]==true
        local needsDistance=(record.mandatory and not authorized) or (authorized and not record.mandatory and id~=current)
        if needsDistance then
            local part=record.part
            if part and camera then
                distanceEvaluations+=1
                if record.boundsFrame~=part.CFrame or record.boundsSize~=part.Size then record.boundsFrame,record.boundsSize=part.CFrame,part.Size end
                distance=PresentationPolicy.DistanceToBounds(camera.CFrame.Position,record.boundsFrame,record.boundsSize)
                if lastSpatialCharacterPosition then distance=math.min(distance,PresentationPolicy.DistanceToBounds(lastSpatialCharacterPosition,part.CFrame,part.Size)) end
            end
            record.optionalVisible,record.optionalReleaseAt=PresentationPolicy.OptionalVisible(
                record.optionalVisible,record.optionalReleaseAt,distance,protectedRadius,now)
            visible=record.optionalVisible
        else
            record.optionalVisible,record.optionalReleaseAt=false,nil
            visible=PresentationPolicy.StaticVisible(id,current,allowed,record.mandatory,distance,protectedRadius,record.classification)
        end
    end

	if record.optionalReleaseAt and (not nextOptionalReleaseAt or record.optionalReleaseAt < nextOptionalReleaseAt) then
		nextOptionalReleaseAt = record.optionalReleaseAt
	end
	if record.critical then visible=true end
	apply(instance, record, (not record.critical and record.lodHidden == true) or not visible)
	if record.appliedAt == nil then
		record.appliedAt = now
	end
	record.lastAppliedAt = now
end
local function sync()
	debug.profilebegin("RegionVisibility.Sync")
	syncSerial += 1
	local camera, now = workspace.CurrentCamera, os.clock()
	nextOptionalReleaseAt = nil
	for instance, record in records do
		if not instance.Parent then
			forget(instance)
			continue
		end
		pcall(presentRecord, instance, record, camera, now)
	end
	table.clear(lodChanged)
	dirty = false
	debug.profileend()
end
-- Periodic 0.5 s pass: LOD changes plus anything riding a moving root (carts, creatures, avatars),
-- whose region can change without any signal. Static records wait for a real dirty event.
local function syncPeriodic()
	debug.profilebegin("RegionVisibility.SyncPeriodic")
	syncSerial += 1
	local camera, now = workspace.CurrentCamera, os.clock()
	for instance, record in lodChanged do
		if instance.Parent and records[instance] == record then
			pcall(presentRecord, instance, record, camera, now)
		end
	end
	table.clear(lodChanged)
	for instance, record in records do
		if record.moving and instance.Parent then
			pcall(presentRecord, instance, record, camera, now)
		end
	end
	debug.profileend()
end
local function syncSpatial(cameraOverride)
	local camera = cameraOverride or workspace.CurrentCamera
	local characterRoot = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local cameraPosition = camera and camera.CFrame.Position
	local characterPosition = characterRoot and characterRoot.Position
	local now = os.clock()
	if
		cameraPosition == lastSpatialCameraPosition
		and characterPosition == lastSpatialCharacterPosition
		and (not nextOptionalReleaseAt or now < nextOptionalReleaseAt)
	then
		return
	end
	lastSpatialCameraPosition, lastSpatialCharacterPosition = cameraPosition, characterPosition
	spatialPasses += 1
	syncSerial += 1
	nextOptionalReleaseAt = nil
	for instance, record in spatialRecords do
		if instance.Parent then
			pcall(presentRecord, instance, record, camera, now)
		else
			forget(instance)
		end
	end
end

-- Existing visibility scheduler owns the only ordinary driving look-ahead
-- request. Engine completion never directly changes visibility or permissions.
local function requestAhead()
    local cart=LocalCart.GetCart()
    local session=cart and cart:GetAttribute("CartDriveSession")
    if cart~=streamCart or session~=streamSession then
        streamCart,streamSession=cart,session;streamGeneration+=1;streamKey=nil
    end
    if not active or not cart or not LocalCart.IsAuthorizedDriver() or streamPending
        or os.clock()-lastStreamAt<Handling.StreamingRequestSeconds then return end
    local root=cart:FindFirstChild("Root")
    if not root or not root:IsA("BasePart") then return end
    local velocity=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z)
    local direction=HandlingMath.Unit(if velocity.Magnitude>1 then velocity else root.CFrame.LookVector,Vector3.new(0,0,-1))
    local destination=root.Position+direction*protectedRadius
    local key=tostring(session)..":"..math.floor(destination.X/64)..":"..math.floor(destination.Z/64)
    if key==streamKey then return end
    streamKey=key;streamPending=true;lastStreamAt=os.clock();streamRequests+=1
    local generation=streamGeneration
    task.spawn(function()
        pcall(function() player:RequestStreamAroundAsync(destination,Handling.StreamingRequestTimeout) end)
        streamPending=false
        if not active or streamGeneration~=generation then return end
    end)
end

function Controller.Start()
	if active then
		return false
	end
	active = true
	proxyFolder = Instance.new("Folder")
	proxyFolder.Name = "Phase13LocalBaseLOD"
	proxyFolder.Parent = workspace
	table.insert(
		connections,
		workspace.DescendantAdded:Connect(function(instance)
			remember(instance)
			dirty = true
		end)
	)
	table.insert(connections, workspace.DescendantRemoving:Connect(forget))
	registrationGeneration += 1
	local generation = registrationGeneration
	task.spawn(function()
		local budgetStarted = os.clock()
		for _, instance in workspace:GetDescendants() do
			if not active or registrationGeneration ~= generation then
				return
			end
			if instance:IsDescendantOf(workspace) then
				remember(instance)
			end
			if os.clock() - budgetStarted >= 0.002 then
				dirty = true
				RunService.Heartbeat:Wait()
				budgetStarted = os.clock()
			end
		end
		dirty = true
	end)
	remoteBinding = RemoteBinding.new({
		Root = RS,
		Name = "Phase13Interest",
		OnRemote = function(remote)
			if not remote then
				return nil
			end
			local connection = remote.OnClientEvent:Connect(acceptContext)
			remote:FireServer("Context")
			return connection
		end,
		OnState = function(status, reason)
			dependencyState, dependencyReason = status, reason
			player:SetAttribute("RegionPresentationDependencyState", status)
			player:SetAttribute("RegionPresentationDependencyReason", reason)
		end,
	})
	local elapsed = 0
	local lodElapsed = 0
	local maintenanceElapsed = 0
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		lodElapsed += dt
		maintenanceElapsed += dt
		if maintenanceElapsed >= 0.2 then
			maintenanceElapsed = 0
			enforceHiddenNativeProperties()
		end
		if lodElapsed >= 0.5 then
			lodElapsed = 0
			syncLOD()
			if not dirty then
				syncPeriodic()
			end
		end
		if elapsed >= 0.1 then
			elapsed = 0
			requestAhead()
			if dirty then
				sync()
			else
				syncSpatial()
			end
		end
	end)
	table.insert(connections, heartbeatConnection)
	local function clearAvatar(other)
		local previous = avatarRoots[other]
		if previous then
			dynamicRoots[previous] = nil
			movingRegionCache[previous] = nil
		end
		for _, c in avatarConnections[other] or {} do
			c:Disconnect()
		end
		avatarConnections[other] = nil
		avatarRoots[other] = nil
	end
	local function bindAvatar(other)
		clearAvatar(other)
		avatarRoots[other] = other.Character
		if other.Character then
			dynamicRoots[other.Character] = true
		end
		cacheEpoch += 1
		avatarConnections[other] = {
			other.CharacterAdded:Connect(function(character)
				local old = avatarRoots[other]
				if old then
					dynamicRoots[old] = nil
					movingRegionCache[old] = nil
				end
				avatarRoots[other] = character
				dynamicRoots[character] = true
				dirty = true
				cacheEpoch += 1
			end),
			other:GetAttributeChangedSignal("Phase13RegionId"):Connect(function()
				dirty = true
				cacheEpoch += 1
			end),
		}
	end

	for _, other in Players:GetPlayers() do
		bindAvatar(other)
	end
	table.insert(connections, Players.PlayerAdded:Connect(bindAvatar))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(other)
			clearAvatar(other)
			dirty = true
		end)
	)
	syncLOD()
	sync()
	return true
end
function Controller.Stop()
	streamGeneration += 1
	streamKey = nil
	active = false
	registrationGeneration += 1
	if remoteBinding then
		remoteBinding:Destroy()
		remoteBinding = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	heartbeatConnection = nil
	for _, list in modelConnections do
		for _, c in list do
			c:Disconnect()
		end
	end
	table.clear(modelConnections)
	for _, list in avatarConnections do
		for _, c in list do
			c:Disconnect()
		end
	end
	table.clear(avatarConnections)
	for instance, record in records do
		if instance.Parent then
			pcall(release, instance, record)
		end
		releaseRecordBindings(instance, record)
	end
	table.clear(records)
	table.clear(spatialRecords)
	lastSpatialCameraPosition, lastSpatialCharacterPosition = nil, nil
	nextOptionalReleaseAt = nil
	table.clear(hiddenNativeRecords)
	table.clear(storedRecords)
	table.clear(slotGroups)
	table.clear(knownModels)
	table.clear(dynamicRoots)
	table.clear(movingRegionCache)
	table.clear(avatarRoots)
	table.clear(floors)
	cacheEpoch += 1
	for _, state in storedModels do
		if state.proxy then
			state.proxy:Destroy()
		end
	end
	table.clear(storedModels)
	if proxyFolder then
		proxyFolder:Destroy()
		proxyFolder = nil
	end
	current = nil
	unlocked = {}
	sequence = -1
end
function Controller.GetDiagnostics()
	local function connectedCount(list)
		local count = 0
		for _, connection in list do
			if connection.Connected then
				count += 1
			end
		end
		return count
	end
	local result = {
		visible = 0,
		detailed = 0,
		reduced = 0,
		hidden = 0,
		interestSubscriptions = if current and unlocked[current] then 1 else 0,
		renderDistance = 180,
		protectedInterestRadius = protectedRadius,
		streamRequests = streamRequests,
		streamPending = streamPending,
		readinessLatencyAssumption = Handling.ReadinessLatency,
		maximumConfiguredCaptureRange = maximumRange,
		maximumConfiguredTravelSpeed = maximumSpeed,
		measuredStartingStoppingDistance = measuredStoppingDistance,
		planningStoppingDistance = planningStoppingDistance,
		stoppingEvidence = "Stage6FourFlatScoutBurstTrials;PeakToNearZeroSampled;Planning140DerivedNotUniversal",
		dependencyState = dependencyState,
		dependencyReason = dependencyReason,
		resolvedPresentationQuality = ResolvedQuality.GetDiagnostics(
			if player then player:GetAttribute("VFXQuality") else nil
		),
		regionLookups = regionLookups,
		bindingRebuilds = bindingRebuilds,
		semanticEvaluations = semanticEvaluations,
		storedRecordVisits = storedRecordVisits,
		distanceEvaluations = distanceEvaluations,
		cachedStoredRecords = 0,
		ancestorBindingGroups = 0,
		semanticBindingGroups = 0,
		activeBindingConnections = 0,
		cachedRecords = 0,
		cachedSpatialRecords = 0,
		immediateApplications = immediateApplications,
		spatialPasses = spatialPasses,
		presentationIntervalSeconds = 0.1,
		hiddenMaintenanceIntervalSeconds = 0.2,
		optionalReleaseGraceSeconds = PresentationPolicy.ReleaseGraceSeconds,
		storedLODModels = 0,
		activeGlobalConnections = connectedCount(connections),
		activeModelConnections = 0,
		modelConnectionGroups = 0,
		activeAvatarConnections = 0,
		avatarConnectionGroups = 0,
		activeHeartbeatSchedules = if heartbeatConnection and heartbeatConnection.Connected then 1 else 0,
	}
	for _, list in modelConnections do
		result.modelConnectionGroups += 1
		result.activeModelConnections += connectedCount(list)
	end
	for _, list in avatarConnections do
		result.avatarConnectionGroups += 1
		result.activeAvatarConnections += connectedCount(list)
	end
	for _ in records do
		result.cachedRecords += 1
	end
	for _ in spatialRecords do
		result.cachedSpatialRecords += 1
	end
	for _, record in records do
		if record.ancestryConnection and record.ancestryConnection.Connected then
			result.activeBindingConnections += 1
		end
	end
	for _, binding in ancestorBindings do
		result.ancestorBindingGroups += 1
		if binding.attributes.Connected then
			result.activeBindingConnections += 1
		end
		if binding.name and binding.name.Connected then
			result.activeBindingConnections += 1
		end
	end
	for _ in slotGroups do
		result.semanticBindingGroups += 1
	end
	for _ in storedRecords do
		result.cachedStoredRecords += 1
	end
	for _ in storedModels do
		result.storedLODModels += 1
	end
	for model in knownModels do
		if not model.Parent then
			knownModels[model] = nil
			continue
		end
		local relevant = model:GetAttribute("CreatureProxy") ~= true
			and (type(model:GetAttribute("BrainrotId")) == "string" or model:GetAttribute("RuntimeCart") == true)
		if not relevant then
			continue
		end
		local state = storedModels[model]
		local hidden = (state and state.hidden) or not Controller.IsVisible(model)
		if hidden then
			result.hidden += 1
		else
			result.visible += 1
			local lod = model:GetAttribute("Phase12FormationLOD")
			if (state and state.reduced) or (type(lod) == "string" and lod ~= "Detailed") then
				result.reduced += 1
			else
				result.detailed += 1
			end
		end
	end
	return result
end
-- Read-only per-instance receipt. It certifies property application only, not
-- asset delivery/GPU readiness. No new scheduler, connection or remote is owned.
function Controller.GetPresentationState(instance)
	local record = records[instance]
	if not record then
		return nil
	end
	return {
		generation = record.generation,
		bindingRevision = record.bindingRevision,
		arrivedAt = record.arrivedAt,
		appliedAt = record.appliedAt,
		lastAppliedAt = record.lastAppliedAt,
		regionId = record.regionId,
		mandatory = record.mandatory,
		slotActive = record.slotActive,
		hidden = record.hidden,
		optionalReleaseAt = record.optionalReleaseAt,
		property = record.property,
	}
end
-- Read-only controller context tests run only in disposable Studio fixtures.
function Controller._AcceptContextForTesting(message)
	if not RunService:IsStudio() or active then
		return false
	end
	return acceptContext(message)
end

function Controller._ApplyHiddenForTesting(instance, hidden)
	assert(RunService:IsStudio() and not active, "Inactive disposable fixture required")
	remember(instance)
	local record = assert(records[instance], "Unsupported visibility fixture")
	apply(instance, record, hidden)
end
function Controller._EnforceHiddenForTesting()
	assert(RunService:IsStudio() and not active, "Inactive disposable fixture required")
	enforceHiddenNativeProperties()
end
function Controller._CacheRegionForTesting(instance)
	if not RunService:IsStudio() or active then
		return nil
	end
	local parent = instance.Parent
	while parent and parent ~= workspace do
		if parent:IsA("Model") then
			remember(parent)
		end
		parent = parent.Parent
	end
	remember(instance)
	syncSerial += 1
	return if records[instance] then cachedRegion(instance, records[instance]) else regionOf(instance)
end

function Controller._SyncForTesting()
	assert(RunService:IsStudio() and not active, "Inactive disposable fixture required")
	sync()
end
function Controller._RememberForTesting(instance)
	assert(RunService:IsStudio() and not active, "Inactive disposable fixture required")
	remember(instance)
end
function Controller._SpatialForTesting(camera)
	assert(RunService:IsStudio() and not active, "Inactive disposable fixture required")
	syncSpatial(camera)
end
function Controller._SyncLODForTesting()
	assert(RunService:IsStudio() and not active, "Inactive disposable fixture required")
	syncLOD()
end
function Controller._RecordCacheForTesting(instance)
	assert(RunService:IsStudio() and not active, "Inactive disposable fixture required")
	local record = records[instance]
	return if record
		then {
			slotActive = record.slotActive,
			stored = record.stored,
			mandatory = record.mandatory,
			inMap = record.inMap,
			part = record.part,
			authored = record.authored,
		}
		else nil
end
function Controller._ForgetForTesting(instance)
	assert(RunService:IsStudio() and not active, "Inactive disposable fixture required")
	forget(instance)
end

return Controller
