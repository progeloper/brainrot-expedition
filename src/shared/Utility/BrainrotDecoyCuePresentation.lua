--!strict

export type Binding = {
	Model: Model,
	Root: BasePart,
	Attachment0: Attachment,
	Attachment1: Attachment,
	Trail: Trail,
	Highlight: Highlight,
	Destroyed: boolean,
}

local BrainrotDecoyCuePresentation = {}
local CUE_COLOR = Color3.fromRGB(0, 235, 255)
local ATTACHMENT_0 = "DecoyRealCue0"
local ATTACHMENT_1 = "DecoyRealCue1"
local TRAIL_NAME = "DecoyRealTrail"
local HIGHLIGHT_NAME = "DecoyRealPulse"

local function resolveRoot(model: Model): BasePart?
	local body = model:FindFirstChild("Body", true)
	if body and body:IsA("BasePart") then
		return body
	end
	local primary = model.PrimaryPart
	return if primary and primary:IsDescendantOf(model)
		then primary
		else model:FindFirstChildWhichIsA("BasePart", true)
end

function BrainrotDecoyCuePresentation.Bind(
	model: Model,
	trailLifetime: number,
	trailMaxLength: number,
	trailWidth: number
): Binding?
	local root = resolveRoot(model)
	if root == nil then
		return nil
	end
	for _, name in { ATTACHMENT_0, ATTACHMENT_1, TRAIL_NAME, HIGHLIGHT_NAME } do
		local old = model:FindFirstChild(name, true)
		if old then
			old:Destroy()
		end
	end
	local localBounds, size = model:GetBoundingBox()
	local centre = root.CFrame:PointToObjectSpace(localBounds.Position)
	local halfWidth = math.max(0.05, trailWidth * 0.5)
	local vertical = math.clamp(size.Y * 0.2, 0.2, 0.8)

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = ATTACHMENT_0
	attachment0.Position = centre + Vector3.new(-halfWidth, vertical, 0)
	attachment0.Parent = root
	local attachment1 = Instance.new("Attachment")
	attachment1.Name = ATTACHMENT_1
	attachment1.Position = centre + Vector3.new(halfWidth, vertical, 0)
	attachment1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = ColorSequence.new(CUE_COLOR)
	trail.Lifetime = trailLifetime
	trail.MaxLength = trailMaxLength
	trail.WidthScale = NumberSequence.new(1)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.FaceCamera = true
	trail.Enabled = true
	trail.Archivable = false
	trail.Parent = root

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineColor = CUE_COLOR
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Archivable = false
	highlight.Parent = model

	return {
		Model = model,
		Root = root,
		Attachment0 = attachment0,
		Attachment1 = attachment1,
		Trail = trail,
		Highlight = highlight,
		Destroyed = false,
	}
end

function BrainrotDecoyCuePresentation.Update(binding: Binding, pulseTransparency: number?)
	if binding.Destroyed then
		return
	end
	if binding.Highlight.Parent == nil or binding.Trail.Parent == nil then
		return
	end
	binding.Trail.Enabled = true
	if pulseTransparency == nil then
		binding.Highlight.Enabled = false
		binding.Highlight.OutlineTransparency = 1
	else
		binding.Highlight.OutlineTransparency = math.clamp(pulseTransparency, 0, 1)
		binding.Highlight.Enabled = binding.Highlight.OutlineTransparency < 1
	end
end

function BrainrotDecoyCuePresentation.Unbind(binding: Binding)
	if binding.Destroyed then
		return
	end
	binding.Destroyed = true
	if binding.Trail.Parent ~= nil then
		binding.Trail.Enabled = false
		binding.Trail:Clear()
		binding.Trail:Destroy()
	end
	if binding.Highlight.Parent ~= nil then
		binding.Highlight.Enabled = false
		binding.Highlight:Destroy()
	end
	if binding.Attachment0.Parent ~= nil then
		binding.Attachment0:Destroy()
	end
	if binding.Attachment1.Parent ~= nil then
		binding.Attachment1:Destroy()
	end
end

return table.freeze(BrainrotDecoyCuePresentation)
