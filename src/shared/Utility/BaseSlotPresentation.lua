--!strict
-- Only base slot/stage presentation. Storage/profile ownership remains server authority.
local Presentation = {}
local stageByCapacity = table.freeze({ [12] = 0, [18] = 1, [24] = 1, [30] = 2, [36] = 2, [42] = 3, [48] = 3 })
local parsedStates: { [Instance]: any } = setmetatable({}, { __mode = "k" })

local function properties(instance: Instance): { string }
	if instance:IsA("BasePart") then
		return { "Transparency", "CanCollide", "CanTouch", "CanQuery", "LocalTransparencyModifier" }
	elseif instance:IsA("GuiBase3d") then
		return { "Visible" }
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		return { "Transparency" }
	elseif
		instance:IsA("LayerCollector")
		or instance:IsA("Highlight")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Light")
		or instance:IsA("ProximityPrompt")
	then
		return { "Enabled" }
	elseif instance:IsA("ClickDetector") then
		return { "MaxActivationDistance" }
	end
	return {}
end

function Presentation.Capture(instance: Instance, authored: any?)
	for _, property in properties(instance) do
		local key = "BaseAuthored_" .. property
		if authored and authored[property] ~= nil then
			instance:SetAttribute(key, authored[property])
		elseif instance:GetAttribute(key) == nil then
			instance:SetAttribute(key, (instance :: any)[property])
		end
	end
end

function Presentation.CaptureGroup(root: Instance, authored: any?)
	Presentation.Capture(root, authored)
	for _, descendant in root:GetDescendants() do
		Presentation.Capture(descendant)
	end
end

function Presentation.GetAuthoredProperty(instance: Instance, property: string): any
	local value = instance:GetAttribute("BaseAuthored_" .. property)
	if type(value) == "boolean" and instance:GetAttribute("BaseContent_" .. property) == false then
		return false
	end
	return value
end

function Presentation.SetContentProperty(instance: Instance, property: string, enabled: boolean)
	instance:SetAttribute("BaseContent_" .. property, enabled)
end

function Presentation.SetContentEnabled(instance: Instance, enabled: boolean)
	Presentation.SetContentProperty(instance, "Enabled", enabled)
end

local function state(base: Instance): any?
	local token = base:GetAttribute("BasePresentationState")
	if type(token) ~= "string" then
		return nil
	end
	local cached = parsedStates[base]
	if cached and cached.Token == token then
		return cached
	end
	local ready, owner, revision, capacity = token:match("^(%d):(%-?%d+):(%d+):(%d+)$")
	local parsed = {
		Token = token,
		Ready = ready == "1",
		Owner = tonumber(owner),
		Revision = tonumber(revision),
		Capacity = tonumber(capacity),
	}
	parsed.Stage = stageByCapacity[parsed.Capacity]
	parsedStates[base] = parsed
	return parsed
end

local function activeFor(base: Instance, index: any, requiredStage: any, token: any): boolean
	local snapshot = state(base)
	local owner, revision = base:GetAttribute("OwnerUserId"), base:GetAttribute("BaseOwnershipRevision")
	local authoring = snapshot ~= nil and snapshot.Owner == 0 and owner == nil
		and not base:IsDescendantOf(game:GetService("Workspace"))
	return snapshot ~= nil
		and (authoring or (owner == snapshot.Owner and revision == snapshot.Revision))
		and snapshot.Ready
		and snapshot.Stage ~= nil
		and token == snapshot.Token
		and (index == nil or (type(index) == "number" and index % 1 == 0 and index >= 1 and index <= snapshot.Capacity))
		and type(requiredStage) == "number"
		and requiredStage >= 0
		and requiredStage <= snapshot.Stage
end

function Presentation.IsActive(instance: Instance): boolean?
	local current: Instance? = instance
	local semantic: Instance? = nil
	while current do
		if not semantic and current:GetAttribute("BaseRequiredStage") ~= nil then
			semantic = current
		end
		if current:GetAttribute("BasePresentationManaged") == true then
			if not semantic then
				return nil
			end
			return activeFor(
				current,
				semantic:GetAttribute("BaseSlotIndex"),
				semantic:GetAttribute("BaseRequiredStage"),
				semantic:GetAttribute("BaseSlotState")
			)
		end
		current = current.Parent
	end
	-- A streamed or not-yet-parented managed group starts unavailable.
	return if semantic then false else nil
end

local function applyOne(instance: Instance, active: boolean)
	for _, property in properties(instance) do
		-- Server transparency is authoritative; distance culling alone owns local modifiers.
		if property ~= "LocalTransparencyModifier" then
			local authored = Presentation.GetAuthoredProperty(instance, property)
			if authored ~= nil then
				local hidden = if property == "Transparency"
					then 1
					elseif property == "MaxActivationDistance" then 0
					else false
				local value = if active then authored else hidden
				if (instance :: any)[property] ~= value then
					(instance :: any)[property] = value
				end
			end
		end
	end
	if not active and (instance:IsA("ParticleEmitter") or instance:IsA("Trail")) then
		instance:Clear()
	end
end

function Presentation.ApplyGroup(root: Instance, active: boolean)
	Presentation.CaptureGroup(root)
	applyOne(root, active)
	for _, descendant in root:GetDescendants() do
		applyOne(descendant, active)
	end
	root:SetAttribute("BaseSlotActive", active)
end

local function plannedActive(token: any, index: number?, requiredStage: number): boolean
	if type(token) ~= "string" then
		return false
	end
	local ready, _, _, capacityText = token:match("^(%d):(%-?%d+):(%d+):(%d+)$")
	local capacity = tonumber(capacityText)
	local stage = capacity and stageByCapacity[capacity]
	return ready == "1"
		and stage ~= nil
		and requiredStage <= stage
		and (index == nil or (index >= 1 and index <= capacity))
end

function Presentation.BindSlot(root: Instance, base: Instance, index: number, token: string?)
	root:SetAttribute("BaseSlotIndex", index)
	root:SetAttribute("BaseRequiredStage", root:GetAttribute("Phase13Floor") or math.floor((index - 1) / 12))
	root:SetAttribute("BaseSlotState", token or base:GetAttribute("BasePresentationState"))
	Presentation.ApplyGroup(
		root,
		plannedActive(root:GetAttribute("BaseSlotState"), index, root:GetAttribute("BaseRequiredStage"))
	)
end

function Presentation.BindStage(root: Instance, base: Instance, requiredStage: number, token: string?)
	root:SetAttribute("BaseRequiredStage", requiredStage)
	root:SetAttribute("BaseSlotState", token or base:GetAttribute("BasePresentationState"))
	Presentation.ApplyGroup(root, plannedActive(root:GetAttribute("BaseSlotState"), nil, requiredStage))
end

function Presentation.Invalidate(base: Instance, owner: number?, revision: number?)
	base:SetAttribute("BasePresentationManaged", true)
	base:SetAttribute("BasePresentationReady", false)
	base:SetAttribute("BasePresentationState", string.format("0:%d:%d:0", owner or 0, revision or 0))
	base:SetAttribute("BaseCommittedCapacity", 0)
	for _, descendant in base:GetDescendants() do
		if descendant:GetAttribute("BaseRequiredStage") ~= nil then
			Presentation.ApplyGroup(descendant, false)
		end
	end
end

-- Context is taken only from the server assignment and the confirmed profile path.
function Presentation.Begin(base: Instance, capacity: number, context: any?): string?
	assert(stageByCapacity[capacity] ~= nil, "Invalid committed base capacity")
	local owner = base:GetAttribute("OwnerUserId")
	local revision = base:GetAttribute("BaseOwnershipRevision")
	local authoring = owner == nil and not base:IsDescendantOf(game:GetService("Workspace"))
	if context ~= nil and (context.OwnerUserId ~= owner or context.AssignmentRevision ~= revision) then
		return nil -- An old owner's callback cannot invalidate a current assignment.
	end
	if context ~= nil and context.ProfileReady ~= true then
		Presentation.Invalidate(base, owner, revision)
		return nil
	end
	local ready = authoring
		or (context ~= nil and type(owner) == "number" and owner ~= 0 and type(revision) == "number")
	local token =
		string.format("%d:%d:%d:%d", if ready then 1 else 0, owner or 0, revision or 0, if ready then capacity else 0)
	base:SetAttribute("BasePresentationManaged", true)
	-- The old atomic snapshot becomes unavailable before any member of the next batch is changed.
	base:SetAttribute("BasePresentationReady", false)
	base:SetAttribute("BasePresentationState", string.format("0:%d:%d:0", owner or 0, revision or 0))
	return token
end

function Presentation.Publish(base: Instance, token: string, capacity: number)
	base:SetAttribute("BaseCommittedCapacity", if token:sub(1, 1) == "1" then capacity else 0)
	base:SetAttribute("BasePresentationState", token)
	base:SetAttribute("BasePresentationReady", token:sub(1, 1) == "1")
end

-- Requests also validate their registered slot and writable profile in BaseStorageSystem.
function Presentation.CanUseSlot(base: Instance, index: number, owner: number, revision: number): boolean
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 48 then
		return false
	end
	if base:GetAttribute("BasePresentationManaged") ~= true then
		return true
	end
	local snapshot = state(base)
	return snapshot ~= nil
		and snapshot.Owner == owner
		and snapshot.Revision == revision
		and activeFor(base, index, math.floor((index - 1) / 12), snapshot.Token)
end

Presentation.StageByCapacity = stageByCapacity
return table.freeze(Presentation)
