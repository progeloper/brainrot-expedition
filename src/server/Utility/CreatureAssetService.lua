--!strict
-- Canonical art remains unchanged; replicated server models contain authority geometry only.
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Config = require(RS.Shared.Config.CreatureReplication)
local Catalog = require(RS.Shared.Config.BrainrotCatalog)
local VisualScale = require(RS.Shared.Utility.BrainrotVisualScale)
local Service = {}
local PRIVATE_NAME = "Phase13CreatureAssets"

function Service.IsEnabled(): boolean
	return Config.Enabled == true
		and not (RunService:IsStudio() and workspace:GetAttribute("Phase13LegacyCreatureReplication") == true)
end
local function legacyAssets(): Instance?
	return RS:FindFirstChild("StudioAssets")
end
function Service.Prepare(): (boolean, string?)
	if not Service.IsEnabled() then
		return true, "LEGACY_STUDIO_COMPARISON"
	end
	local target = SS:FindFirstChild(PRIVATE_NAME)
	if target and not target:IsA("Folder") then
		return false, "PRIVATE_CONTAINER_CONFLICT"
	end
	local source = legacyAssets()
	-- Preflight every move before changing any parent; never replace accepted art.
	for _, name in { "Brainrots", "ChariotFormation" } do
		local existing = if target then target:FindFirstChild(name) else nil
		local incoming = if source then source:FindFirstChild(name) else nil
		if existing and incoming and existing ~= incoming then
			return false, "ASSET_FOLDER_CONFLICT_" .. name
		end
		if (existing and not existing:IsA("Folder")) or (incoming and not incoming:IsA("Folder")) then
			return false, "ASSET_FOLDER_TYPE_" .. name
		end
		if not existing and not incoming then
			return false, "MISSING_ASSET_FOLDER_" .. name
		end
	end
	if not target then
		target = Instance.new("Folder")
		target.Name, target.Parent = PRIVATE_NAME, SS
	end
	for _, name in { "Brainrots", "ChariotFormation" } do
		local incoming = if source then source:FindFirstChild(name) else nil
		if incoming then
			incoming.Parent = target
		end
	end
	return true, nil
end
local function assetFolder(name: string): Instance?
	local private = SS:FindFirstChild(PRIVATE_NAME)
	local folder = if private then private:FindFirstChild(name) else nil
	if folder then
		return folder
	end
	-- This branch exists only for the explicit legacy A/B mode and disposable
	-- native fixtures. A shipping server never falls back to replicated art.
	if
		not Service.IsEnabled()
		or (RunService:IsStudio() and game:GetAttribute("BrainrotTestDiagnosticsDisabled") == true)
	then
		local assets = legacyAssets()
		return if assets then assets:FindFirstChild(name) else nil
	end
	return nil
end
function Service.GetBrainrotFolder(): Instance?
	return assetFolder("Brainrots")
end
function Service.GetTemplate(species: string, lod: string?): Model?
	local definition = Catalog.Get(species)
	local modelRef = if definition
		then definition.modelRef
		elseif RunService:IsStudio() and string.match(species, "^SPEC_") then species
		else nil
	if type(modelRef) ~= "string" then
		return nil
	end
	local source: Instance? = nil
	if lod == nil or lod == "Full" then
		local folder = assetFolder("Brainrots")
		source = if folder then folder:FindFirstChild(modelRef) else nil
		-- Disposable spec fixtures author their SPEC_ templates in the legacy
		-- replicated folder. Only the headless test place sets this attribute.
		if
			source == nil
			and RunService:IsStudio()
			and game:GetAttribute("BrainrotTestDiagnosticsDisabled") == true
		then
			local assets = legacyAssets()
			local legacy = if assets then assets:FindFirstChild("Brainrots") else nil
			source = if legacy then legacy:FindFirstChild(modelRef) else nil
		end
	else
		local folder = assetFolder("ChariotFormation")
		local entry = if folder then folder:FindFirstChild(species) else nil
		source = if entry then entry:FindFirstChild(lod) else nil
	end
	return if source and source:IsA("Model") then source else nil
end
local function huntBounds(model: Model): (CFrame?, Vector3?)
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	local count, pivot = 0, model:GetPivot()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.CanQuery and VisualScale.IsVisualPart(part, model) then
			count += 1
			local frame, half = pivot:ToObjectSpace(part.CFrame), part.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local point = frame * (half * Vector3.new(x, y, z))
						low, high = low:Min(point), high:Max(point)
					end
				end
			end
		end
	end
	if count == 0 then
		return nil, nil
	end
	return CFrame.new((low + high) / 2), high - low
end
function Service.CreateProxy(species: string): (Model?, string?)
	local template = Service.GetTemplate(species)
	if not template then
		return nil, "MISSING_SOURCE_ASSET"
	end
	local clone = template:Clone()
	if not clone then
		return nil, "CLONE_FAILED"
	end
	-- Strip inherited discovery tags even in controlled legacy comparison mode.
	local descendants = clone:GetDescendants()
	table.insert(descendants, clone)
	for _, instance in descendants do
		for _, tag in CollectionService:GetTags(instance) do
			CollectionService:RemoveTag(instance, tag)
		end
	end
	if not Service.IsEnabled() then
		return clone, nil
	end
	local ok, reason = pcall(function()
		local body = clone:FindFirstChild("Body", true)
		local root = clone.PrimaryPart
		assert(body and body:IsA("BasePart") and body.CanQuery, "QUERYABLE_BODY_REQUIRED")
		assert(root and root:IsDescendantOf(clone), "PRIMARY_ROOT_REQUIRED")
		local capture, cargo = body:FindFirstChild("CaptureAttachment"), body:FindFirstChild("CargoAttachment")
		-- Preserve accepted attachment metadata, but obsolete marker shape cannot
		-- reject a current Body/root/cargo asset or become authority geometry.
		if capture and not capture:IsA("Attachment") then capture = nil end
		assert(cargo == nil or cargo:IsA("Attachment"), "INVALID_CARGO_ATTACHMENT")
		local visualFrame, visualSize = VisualScale.GetVisualBounds(clone)
		local huntFrame, huntSize = huntBounds(clone)
		assert(visualFrame and visualSize and huntFrame and huntSize, "ORIGINAL_BOUNDS_REQUIRED")
		local pivot = clone:GetPivot()
		local fullFrame, fullSize = clone:GetBoundingBox()
		local keep: { [Instance]: boolean } = {}
		local preserved = { body, root }
		if capture then table.insert(preserved, capture) end
		if cargo then table.insert(preserved, cargo) end
		for _, item in preserved do
			local ancestor: Instance? = item
			while ancestor and ancestor ~= clone do
				keep[ancestor] = true
				ancestor = ancestor.Parent
			end
		end
		for _, item in clone:GetDescendants() do
			if not keep[item] then
				item:Destroy()
			end
		end
		for _, part in { body, root } do
			part.Transparency, part.CastShadow = 1, false
			part.Anchored = true
		end
		local envelope = Instance.new("Part")
		envelope.Name, envelope.Size, envelope.CFrame = "CreatureBoundsEnvelope", fullSize, fullFrame
		envelope.Transparency, envelope.CastShadow = 1, false
		envelope.Anchored, envelope.Massless = true, true
		envelope.CanCollide, envelope.CanTouch, envelope.CanQuery = false, false, false
		envelope:SetAttribute("BrainrotVisualHelper", true)
		envelope.Parent = clone
		clone:SetAttribute("CreatureProxy", true)
		clone:SetAttribute("CreatureBoundsSourceScale", clone:GetScale())
		clone:SetAttribute("CreatureVisualBoundsFrame", visualFrame)
		clone:SetAttribute("CreatureVisualBoundsSize", visualSize)
		clone:SetAttribute("CreatureHuntBoundsFrame", huntFrame)
		clone:SetAttribute("CreatureHuntBoundsSize", huntSize)
		clone:PivotTo(pivot)
	end)
	if not ok then
		clone:Destroy()
		return nil, tostring(reason)
	end
	return clone, nil
end
return table.freeze(Service)
