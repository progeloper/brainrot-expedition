--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureAssets = require(script.Parent.CreatureAssetService)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)

export type Prepared = {
	Model: Model,
	HitProxy: BasePart,
}

local DecoyVisuals = {}

local function shouldDestroy(instance: Instance): boolean
	return instance:IsA("LuaSourceContainer")
		or instance:IsA("ProximityPrompt")
		or instance:IsA("ClickDetector")
		or instance:IsA("DragDetector")
		or instance:IsA("Humanoid")
		or instance:IsA("Animator")
		or instance:IsA("AnimationController")
		or instance:IsA("JointInstance")
		or instance:IsA("Constraint")
		or instance:IsA("BodyMover")
		or instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("Highlight")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Light")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles")
		or instance:IsA("Sound")
		or instance:IsA("ObjectValue")
		or instance:IsA("Tool")
		or instance:IsA("Attachment")
end

local function clearMetadata(instance: Instance)
	for _, tag in CollectionService:GetTags(instance) do
		CollectionService:RemoveTag(instance, tag)
	end
	for attribute in instance:GetAttributes() do
		instance:SetAttribute(attribute, nil)
	end
end

function DecoyVisuals.Create(
	brainrotId: string,
	decoyId: string,
	encounterId: string,
	hitProxyLocalFrame: CFrame,
	hitProxySize: Vector3
): (Prepared?, string?)
	local source = CreatureAssets.GetTemplate(brainrotId)
	if source == nil then
		return nil, "MISSING_SOURCE_ASSET"
	end
	if
		hitProxySize.X <= 0
		or hitProxySize.Y <= 0
		or hitProxySize.Z <= 0
		or hitProxySize.X ~= hitProxySize.X
		or hitProxySize.Y ~= hitProxySize.Y
		or hitProxySize.Z ~= hitProxySize.Z
	then
		return nil, "INVALID_HIT_ENVELOPE"
	end

	local visual, proxyReason = CreatureAssets.CreateProxy(brainrotId)
	if not visual then
		return nil, proxyReason
	end
	local ok, failure = pcall(function()
		local proxyAttributes = {}
		for name, value in visual:GetAttributes() do
			if string.sub(name, 1, 8) == "Creature" then
				proxyAttributes[name] = value
			end
		end
		local descendants = visual:GetDescendants()
		table.insert(descendants, visual)
		for _, instance in descendants do
			clearMetadata(instance)
			if instance ~= visual and shouldDestroy(instance) then
				instance:Destroy()
			end
		end
		for name, value in proxyAttributes do
			visual:SetAttribute(name, value)
		end
		local scaled, _, scaleReason = BrainrotVisualScale.ApplyCanonicalScale(visual, "Decoy")
		assert(scaled, scaleReason)
		local root = visual.PrimaryPart
		if root == nil or not root:IsDescendantOf(visual) then
			local body = visual:FindFirstChild("Body", true)
			root = if body and body:IsA("BasePart") then body else visual:FindFirstChildWhichIsA("BasePart", true)
		end
		assert(root ~= nil and root:IsA("BasePart"), "Decoy visual has no BasePart")
		visual.PrimaryPart = root :: BasePart
		for _, instance in visual:GetDescendants() do
			if instance:IsA("BasePart") then
				instance.Anchored = true
				instance.CanCollide = false
				instance.CanTouch = false
				instance.CanQuery = false
				instance.Massless = true
			end
		end

		local hitProxy = Instance.new("Part")
		hitProxy.Name = "HitProxy"
		hitProxy.Size = hitProxySize
		hitProxy.CFrame = visual:GetPivot() * hitProxyLocalFrame
		hitProxy.Transparency = 1
		hitProxy.Anchored = true
		hitProxy.CanCollide = false
		hitProxy.CanTouch = false
		hitProxy.CanQuery = true
		hitProxy.CastShadow = false
		hitProxy:SetAttribute("EffectKind", "Decoy")
		hitProxy:SetAttribute("DecoyId", decoyId)
		hitProxy:SetAttribute("EncounterId", encounterId)
		hitProxy.Parent = visual

		visual.Name = decoyId
		visual:SetAttribute("BrainrotId", brainrotId)
		visual:SetAttribute("EffectKind", "Decoy")
		visual:SetAttribute("DecoyId", decoyId)
		visual:SetAttribute("EncounterId", encounterId)
	end)
	if not ok then
		visual:Destroy()
		return nil, tostring(failure)
	end
	local proxy = visual:FindFirstChild("HitProxy")
	if proxy == nil or not proxy:IsA("BasePart") then
		visual:Destroy()
		return nil, "MISSING_HIT_PROXY"
	end
	return { Model = visual, HitProxy = proxy }, nil
end

return table.freeze(DecoyVisuals)
