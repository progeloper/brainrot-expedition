--!strict
-- Exact authored query shapes stay server-private. Returned hits retain the
-- existing proxy Body identity; this service never owns population or damage.
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local Collection = game:GetService("CollectionService")
local Assets = require(script.Parent.CreatureAssetService)
local Config = require(RS.Shared.Config.CreatureReplication)
local VisualScale = require(RS.Shared.Utility.BrainrotVisualScale)
local Service = {}
local scene: WorldModel? = nil
local prototypes: { [Model]: any } = {}
local tracked: { [Model]: any } = {}
local byPart: { [BasePart]: any } = {}
local lastError: string? = nil
local failures = 0
local function fail(reason: string): (boolean, string)
	lastError = reason
	failures += 1
	return false, reason
end
local function finiteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.max(math.abs(value.X), math.abs(value.Y), math.abs(value.Z)) < math.huge
end
local function ensureScene(): WorldModel?
	if scene and scene.Parent == SS then
		return scene
	end
	local existing = SS:FindFirstChild("Phase13CreatureQueryScene")
	if existing then
		if not existing:IsA("WorldModel") or existing:GetAttribute("Phase13QueryOwned") ~= true then
			fail("QUERY_SCENE_CONFLICT")
			return nil
		end
		scene = existing
	else
		local model = Instance.new("WorldModel")
		model.Name = "Phase13CreatureQueryScene"
		model:SetAttribute("Phase13QueryOwned", true)
		model.UseWorkspaceCollisionGroups = true
		model.Parent = SS
		scene = model
	end
	return scene
end
function Service.Untrack(proxy: Model): boolean
	local record = tracked[proxy]
	if not record then
		return false
	end
	tracked[proxy] = nil
	for _, connection in record.Connections do
		connection:Disconnect()
	end
	for _, part in record.Parts do
		byPart[part] = nil
	end
	record.Model:Destroy()
	return true
end
local function discardPrototype(source: Model)
	local prototype = prototypes[source]
	if not prototype then
		return
	end
	prototypes[source] = nil
	prototype.Connection:Disconnect()
	for proxy, record in tracked do
		if record.Source == source then
			Service.Untrack(proxy)
		end
	end
	prototype.Model:Destroy()
end
local function prototypeFor(source: Model): any?
	if prototypes[source] then
		return prototypes[source]
	end
	local model = source:Clone()
	if not model or not model.PrimaryPart then
		if model then
			model:Destroy()
		end
		return nil
	end
	local keep: { [Instance]: boolean } = {}
	local parts = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and (item.CanQuery or item == model.PrimaryPart) then
			if item.CanQuery then
				item:SetAttribute("CreatureQueryOriginalMaterial", item.Material.Name)
				item:SetAttribute("CreatureQueryHuntEligible", VisualScale.IsVisualPart(item, model))
				item:SetAttribute("CreatureQueryOriginalCollide", item.CanCollide)
				table.insert(parts, item)
			end
			local ancestor: Instance? = item
			while ancestor and ancestor ~= model do
				keep[ancestor] = true
				ancestor = ancestor.Parent
			end
		end
	end
	if #parts == 0 then
		model:Destroy()
		return nil
	end
	local items = model:GetDescendants()
	table.insert(items, model)
	for _, item in items do
		for _, tag in Collection:GetTags(item) do
			Collection:RemoveTag(item, tag)
		end
		if item ~= model and not keep[item] then
			item:Destroy()
		elseif item:IsA("BasePart") then
			-- Native collision geometry and mesh/union fidelity are unchanged.
			item.Transparency, item.CastShadow, item.Anchored, item.Massless = 1, false, true, true
			item.CanCollide, item.CanTouch = false, false
			item.Material, item.MaterialVariant, item.Reflectance = Enum.Material.SmoothPlastic, "", 0
			if item:IsA("MeshPart") then
				item.TextureID = ""
			end
		end
	end
	local prototype = { Model = model, Connection = nil }
	prototype.Connection = source.Destroying:Connect(function()
		discardPrototype(source)
	end)
	prototypes[source] = prototype
	return prototype
end
function Service.Track(proxy: Model, species: string): (boolean, string?)
	if not Assets.IsEnabled() then
		return false, "LEGACY_REPLICATION"
	end
	if not proxy:IsDescendantOf(workspace) or proxy:GetAttribute("CreatureProxy") ~= true then
		return false, "INACTIVE_AUTHORITY_PROXY"
	end
	local body = proxy:FindFirstChild("Body", true)
	if not body or not body:IsA("BasePart") or not body.CanQuery then
		return fail("QUERYABLE_BODY_REQUIRED")
	end
	local source = Assets.GetTemplate(species, "Full")
	if not source then
		return fail("SOURCE_TEMPLATE_MISSING")
	end
	local record = tracked[proxy]
	if record and (record.Source ~= source or record.Species ~= species) then
		Service.Untrack(proxy)
		record = nil
	end
	if not record then
		local count = 0
		for _ in tracked do
			count += 1
		end
		if count >= Config.MaxEntities then
			return fail("QUERY_ENTITY_LIMIT")
		end
		local target = ensureScene()
		if not target then
			return false, "QUERY_SCENE_CONFLICT"
		end
		local prototype = prototypeFor(source)
		if not prototype then
			return fail("QUERY_PROTOTYPE_INVALID")
		end
		local model = prototype.Model:Clone()
		if not model then
			return fail("QUERY_CLONE_FAILED")
		end
		local parts = {}
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") and item.CanQuery then
				table.insert(parts, item)
			end
		end
		record = {
			Model = model,
			Source = source,
			Species = species,
			Body = body,
			Proxy = proxy,
			Parts = parts,
			Connections = {},
		}
		record.Equivalent = {}
		local proxyItems = proxy:GetDescendants()
		for _, item in proxyItems do
			local names = {}
			local ancestor = item
			while ancestor and ancestor ~= proxy do
				table.insert(names, 1, ancestor.Name)
				ancestor = ancestor.Parent
			end
			local twin = model
			for _, name in names do
				twin = if twin then twin:FindFirstChild(name) else nil
			end
			if twin then
				record.Equivalent[item] = twin
			end
		end
		tracked[proxy] = record
		for _, part in parts do
			byPart[part] = record
		end
		table.insert(
			record.Connections,
			proxy.Destroying:Connect(function()
				Service.Untrack(proxy)
			end)
		)
		table.insert(
			record.Connections,
			proxy.AncestryChanged:Connect(function()
				if not proxy:IsDescendantOf(workspace) then
					Service.Untrack(proxy)
				end
			end)
		)
		model.Name, model.Parent = "Query_" .. species, target
	end
	local ok, why = pcall(function()
		if record.Scale ~= proxy:GetScale() then
			record.Model:ScaleTo(proxy:GetScale())
			record.Scale = proxy:GetScale()
		end
		local pose = proxy:GetPivot()
		if record.Pose ~= pose then
			record.Model:PivotTo(pose)
			record.Pose = pose
		end
	end)
	if not ok then
		Service.Untrack(proxy)
		return fail("QUERY_TRANSFORM_FAILED:" .. tostring(why))
	end
	return true, nil
end
function Service.SyncWorld(models: { Model }): (boolean, any)
	if not Assets.IsEnabled() then
		Service.Stop()
		return true, { tracked = 0, failed = 0, removed = 0, legacy = true }
	end
	local retained, failed, removed, count = {}, 0, 0, 0
	for _, model in models do
		if model:IsA("Model") and model:GetAttribute("CreatureProxy") == true then
			local species = model:GetAttribute("BrainrotId")
			if type(species) ~= "string" then
				failed += 1
				continue
			end
			local ok = Service.Track(model, species)
			if ok then
				retained[model] = true
				count += 1
			else
				failed += 1
			end
		end
	end
	for model in tracked do
		if not retained[model] then
			Service.Untrack(model)
			removed += 1
		end
	end
	return failed == 0, { tracked = count, failed = failed, removed = removed }
end
local function matches(record: any, part: BasePart, filter: Instance): boolean
	if record.Proxy == filter or record.Proxy:IsDescendantOf(filter) then
		return true
	end
	if part == filter or part:IsDescendantOf(filter) then
		return true
	end
	-- Only the actual original Body corresponds to the replicated Body. A limb
	-- maps to that identity on return, but is not removed by a Body-only filter.
	if filter == record.Body and part.Name == "Body" then
		return true
	end
	return false
end
function Service.Raycast(origin: Vector3, direction: Vector3, params: RaycastParams?): any?
	if
		not scene
		or not Assets.IsEnabled()
		or not finiteVector(origin)
		or not finiteVector(direction)
		or direction.Magnitude <= 0
	then
		return nil
	end
	local query = RaycastParams.new()
	-- Normal capture/reach queries exclude a few player/cart ancestors. Map
	-- these once per active model instead of scanning every private art part.
	if params == nil or (params.FilterType == Enum.RaycastFilterType.Exclude and not params.RespectCanCollide) then
		query.FilterType = Enum.RaycastFilterType.Exclude
		local excluded = {}
		for _, filter in if params then params.FilterDescendantsInstances else {} do
			if filter == scene or filter:IsDescendantOf(scene) then
				table.insert(excluded, filter)
			end
			for _, record in tracked do
				if record.Proxy == filter or record.Proxy:IsDescendantOf(filter) then
					table.insert(excluded, record.Model)
				elseif record.Equivalent[filter] then
					table.insert(excluded, record.Equivalent[filter])
				end
			end
		end
		query.FilterDescendantsInstances = excluded
	else
		query.FilterType = Enum.RaycastFilterType.Include
		local allowed = {}
		local filters = if params then params.FilterDescendantsInstances else {}
		local include = params ~= nil and params.FilterType == Enum.RaycastFilterType.Include
		for part, record in byPart do
			local matched = false
			for _, filter in filters do
				if matches(record, part, filter) then
					matched = true
					break
				end
			end
			local collidable = not params
				or not params.RespectCanCollide
				or part:GetAttribute("CreatureQueryOriginalCollide") == true
			if (matched == include) and collidable then
				table.insert(allowed, part)
			end
		end
		if #allowed == 0 then
			return nil
		end
		query.FilterDescendantsInstances = allowed
	end
	query.RespectCanCollide = false -- Original CanCollide was evaluated above; private shapes never simulate collision.
	if params then
		query.IgnoreWater, query.CollisionGroup = params.IgnoreWater, params.CollisionGroup
	end
	local hit = scene:Raycast(origin, direction, query)
	local record = if hit then byPart[hit.Instance] else nil
	if not hit or not record or not record.Proxy:IsDescendantOf(workspace) then
		return nil
	end
	local materialName = hit.Instance:GetAttribute("CreatureQueryOriginalMaterial")
	return {
		Instance = record.Body,
		Position = hit.Position,
		Normal = hit.Normal,
		Distance = hit.Distance,
		Material = if type(materialName) == "string" then Enum.Material[materialName] else hit.Material,
		QueryPartName = hit.Instance.Name,
		QueryPartHuntEligible = hit.Instance:GetAttribute("CreatureQueryHuntEligible") == true,
	}
end
function Service.Stop()
	for proxy in tracked do
		Service.Untrack(proxy)
	end
	for source in prototypes do
		discardPrototype(source)
	end
	if scene then
		scene:Destroy()
		scene = nil
	end
	table.clear(byPart)
end
function Service.GetDiagnostics(): any
	local entities, parts, prototypeCount, connections = 0, 0, 0, 0
	for _, record in tracked do
		entities += 1
		parts += #record.Parts
		connections += #record.Connections
	end
	for _ in prototypes do
		prototypeCount += 1
		connections += 1
	end
	return {
		entities = entities,
		queryParts = parts,
		prototypes = prototypeCount,
		connections = connections,
		privateScene = scene ~= nil and scene.Parent == SS,
		lastError = lastError,
		failureCount = failures,
	}
end
return table.freeze(Service)
