--!strict
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local Collection = game:GetService("CollectionService")
local Config = require(RS.Shared.Config.CreatureReplication)
local Rules = require(RS.Shared.Utility.CreatureProtocolRules)
local Provider = require(RS.Shared.Utility.CreatureTemplateProvider)
local Cache = {}
local templates, requested, receiving = {}, {}, {}
local epoch, active, remote = -1, false, nil
local connections, lifecycle = {}, 0
local used, requestAt, supplied, evicted = 0, 0, 0, 0
local function trim()
	local count = 0
	for _ in templates do
		count += 1
	end
	while count > Config.MaxCachedTemplates do
		local oldest, age
		for key, item in templates do
			if age == nil or item.used < age then
				oldest, age = key, item.used
			end
		end
		if not oldest then
			break
		end
		templates[oldest].model:Destroy()
		templates[oldest] = nil
		count -= 1
		evicted += 1
	end
end
function Cache.Get(species: string, lod: string?): Model?
	lod = lod or "Full"
	if not Rules.ValidTemplate(species, lod) then
		return nil
	end
	local key = Rules.TemplateKey(species, lod)
	local item = templates[key]
	used += 1
	if item then
		item.used = used
		return item.model
	end
	requested[key] = requested[key] or { speciesId = species, lod = lod, at = -math.huge }
	return nil
end
function Cache.SetEpoch(value: number)
	if value == epoch then
		return
	end
	epoch = value
	table.clear(requested)
end
local function accept(model)
	if not model:IsA("Model") or receiving[model] then
		return
	end
	receiving[model] = true
	local ownerGeneration = lifecycle
	task.spawn(function()
		local began = os.clock()
		local expected = model:GetAttribute("CreatureSupplyDescendants")
		while
			active
			and ownerGeneration == lifecycle
			and model.Parent
			and (type(expected) ~= "number" or #model:GetDescendants() < expected)
			and os.clock() - began < 5
		do
			Run.Heartbeat:Wait()
			expected = model:GetAttribute("CreatureSupplyDescendants")
		end
		local species, lod = model:GetAttribute("CreatureSupplySpecies"), model:GetAttribute("CreatureSupplyLOD")
		local token, suppliedEpoch =
			model:GetAttribute("CreatureSupplyToken"), model:GetAttribute("CreatureSupplyEpoch")
		if
			active
			and ownerGeneration == lifecycle
			and model.Parent
			and suppliedEpoch == epoch
			and Rules.ValidTemplate(species, lod)
			and type(expected) == "number"
			and #model:GetDescendants() >= expected
		then
			local copy = model:Clone()
			for _, node in { copy, table.unpack(copy:GetDescendants()) } do
				for _, tag in Collection:GetTags(node) do
					Collection:RemoveTag(node, tag)
				end
			end
			local key = Rules.TemplateKey(species, lod)
			local old = templates[key]
			if old then
				old.model:Destroy()
			end
			used += 1
			templates[key], requested[key] = { model = copy, used = used }, nil
			supplied += 1
			trim()
			Provider.NotifyChanged()
		end
		if active and ownerGeneration == lifecycle and remote and Rules.ValidTemplate(species, lod) then
			remote:FireServer({
				kind = "TemplateAck",
				speciesId = species,
				lod = lod,
				token = token,
				epoch = suppliedEpoch,
			})
		end
		receiving[model] = nil
	end)
end
function Cache.GetDiagnostics()
	local count, parts = 0, 0
	for _, item in templates do
		count += 1
		for _, part in item.model:GetDescendants() do
			if part:IsA("BasePart") then
				parts += 1
			end
		end
	end
	return {
		templates = count,
		cachedParts = parts,
		supplied = supplied,
		evicted = evicted,
		epoch = epoch,
		connections = #connections,
	}
end
function Cache.Start(event)
	if active then
		return false
	end
	active, remote = true, event
	lifecycle += 1
	Provider.SetResolver(Cache.Get)
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local watched = {}
	local function watch(folder)
		if folder.Name ~= Config.SupplyName or watched[folder] then
			return
		end
		watched[folder] = true
		table.insert(connections, folder.ChildAdded:Connect(accept))
		for _, model in folder:GetChildren() do
			accept(model)
		end
		table.insert(
			connections,
			folder.Destroying:Connect(function()
				watched[folder] = nil
			end)
		)
	end
	table.insert(connections, gui.ChildAdded:Connect(watch))
	for _, folder in gui:GetChildren() do
		watch(folder)
	end
	table.insert(
		connections,
		Run.Heartbeat:Connect(function()
			local now = os.clock()
			if epoch < 0 or now < requestAt then
				return
			end
			for _, request in requested do
				if now - request.at >= 1 then
					request.at, requestAt = now, now + Config.TemplateRequestIntervalSeconds + 0.01
					remote:FireServer({
						kind = "Template",
						speciesId = request.speciesId,
						lod = request.lod,
						epoch = epoch,
					})
					break
				end
			end
		end)
	)
	return true
end
function Cache.Stop()
	active, remote, epoch = false, nil, -1
	lifecycle += 1
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, item in templates do
		item.model:Destroy()
	end
	table.clear(templates)
	table.clear(requested)
	table.clear(receiving)
	Provider.SetResolver(nil)
	Provider.NotifyChanged()
	requestAt = 0
end
return Cache
