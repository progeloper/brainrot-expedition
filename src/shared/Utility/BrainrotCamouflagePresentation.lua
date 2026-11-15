--!strict

type PartState = {
	Part: BasePart,
	BaselineLocalTransparency: number,
	BaselineCastShadow: boolean,
	LastLocalTransparency: number?,
	LastCastShadow: boolean?,
}

type TransparencyState = {
	Visual: any,
	BaselineTransparency: number,
	LastTransparency: number?,
}

type ToggleState = {
	Visual: any,
	Property: "Enabled" | "Visible",
	Baseline: boolean,
	LastApplied: boolean?,
}

export type Binding = {
	Model: Model,
	Parts: { [BasePart]: PartState },
	TransparencyVisuals: { [Instance]: TransparencyState },
	Toggles: { [Instance]: ToggleState },
	Cue: Highlight,
	Connections: { RBXScriptConnection },
	VisualConnections: { [Instance]: RBXScriptConnection },
	Dirty: boolean,
	Applying: boolean,
	CamouflageAmount: number,
	FullReveal: boolean,
	CueTransparency: number?,
	Destroyed: boolean,
}

local BrainrotCamouflagePresentation = {}
local CUE_NAME = "CamouflageRevealCue"

local function nearlyEqual(left: number, right: number): boolean
	return math.abs(left - right) <= 1e-6
end

function BrainrotCamouflagePresentation.ComposeLocalTransparency(
	normalLocalModifier: number,
	camouflageAmount: number
): number
	local normal = math.clamp(normalLocalModifier, 0, 1)
	local camouflage = math.clamp(camouflageAmount, 0, 1)
	return 1 - (1 - normal) * (1 - camouflage)
end

local function restorePart(state: PartState)
	local part = state.Part
	if part.Parent == nil then
		return
	end
	if
		state.LastLocalTransparency == nil
		or nearlyEqual(part.LocalTransparencyModifier, state.LastLocalTransparency)
	then
		part.LocalTransparencyModifier = state.BaselineLocalTransparency
	end
	if state.LastCastShadow == nil or part.CastShadow == state.LastCastShadow then
		part.CastShadow = state.BaselineCastShadow
	end
	state.LastLocalTransparency = nil
	state.LastCastShadow = nil
end

local function restoreTransparency(state: TransparencyState)
	local visual = state.Visual
	if visual.Parent == nil then
		return
	end
	if
		state.LastTransparency == nil or nearlyEqual(visual.Transparency, state.LastTransparency)
	then
		visual.Transparency = state.BaselineTransparency
	end
	state.LastTransparency = nil
end

local function restoreToggle(state: ToggleState)
	local visual = state.Visual
	if visual.Parent == nil then
		return
	end
	if state.LastApplied == nil or visual[state.Property] == state.LastApplied then
		visual[state.Property] = state.Baseline
	end
	state.LastApplied = nil
end

local function applyPart(state: PartState, amount: number, fullReveal: boolean)
	local part = state.Part
	if part.Parent == nil then
		return
	end
	if
		state.LastLocalTransparency ~= nil
		and not nearlyEqual(part.LocalTransparencyModifier, state.LastLocalTransparency)
	then
		state.BaselineLocalTransparency = part.LocalTransparencyModifier
	end
	local localTransparency = BrainrotCamouflagePresentation.ComposeLocalTransparency(
		state.BaselineLocalTransparency,
		amount
	)
	if
		state.LastLocalTransparency == nil
		or not nearlyEqual(state.LastLocalTransparency, localTransparency)
	then
		part.LocalTransparencyModifier = localTransparency
		state.LastLocalTransparency = localTransparency
	end
	local castShadow = state.BaselineCastShadow and fullReveal and amount <= 1e-6
	if state.LastCastShadow == nil or state.LastCastShadow ~= castShadow then
		part.CastShadow = castShadow
		state.LastCastShadow = castShadow
	end
end

local function applyTransparency(state: TransparencyState, amount: number)
	local visual = state.Visual
	if visual.Parent == nil then
		return
	end
	if
		state.LastTransparency ~= nil
		and not nearlyEqual(visual.Transparency, state.LastTransparency)
	then
		state.BaselineTransparency = visual.Transparency
	end
	local transparency = 1 - (1 - state.BaselineTransparency) * (1 - amount)
	if state.LastTransparency == nil or not nearlyEqual(state.LastTransparency, transparency) then
		visual.Transparency = transparency
		state.LastTransparency = transparency
	end
end

local function applyToggle(state: ToggleState, fullReveal: boolean)
	local visual = state.Visual
	if visual.Parent == nil then
		return
	end
	local enabled = state.Baseline and fullReveal
	if state.LastApplied == nil or state.LastApplied ~= enabled then
		visual[state.Property] = enabled
		state.LastApplied = enabled
	end
end

local function registerDescendant(binding: Binding, descendant: Instance)
	if descendant == binding.Cue or descendant.Name == CUE_NAME then
		return
	end
	if descendant:IsA("BasePart") then
		binding.Parts[descendant] = {
			Part = descendant,
			BaselineLocalTransparency = descendant.LocalTransparencyModifier,
			BaselineCastShadow = descendant.CastShadow,
			LastLocalTransparency = nil,
			LastCastShadow = nil,
		}
		binding.VisualConnections[descendant] = descendant
			:GetPropertyChangedSignal("LocalTransparencyModifier")
			:Connect(function()
				local state = binding.Parts[descendant]
				if
					not binding.Applying
					and state
					and (
						state.LastLocalTransparency == nil
						or not nearlyEqual(
							descendant.LocalTransparencyModifier,
							state.LastLocalTransparency
						)
					)
				then
					binding.Dirty = true
				end
			end)
	elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
		binding.TransparencyVisuals[descendant] = {
			Visual = descendant,
			BaselineTransparency = descendant.Transparency,
			LastTransparency = nil,
		}
		binding.VisualConnections[descendant] = descendant
			:GetPropertyChangedSignal("Transparency")
			:Connect(function()
				local state = binding.TransparencyVisuals[descendant]
				if
					not binding.Applying
					and state
					and (
						state.LastTransparency == nil
						or not nearlyEqual(descendant.Transparency, state.LastTransparency)
					)
				then
					binding.Dirty = true
				end
			end)
	elseif
		descendant:IsA("ParticleEmitter")
		or descendant:IsA("Trail")
		or descendant:IsA("Beam")
		or descendant:IsA("Light")
		or descendant:IsA("Smoke")
		or descendant:IsA("Fire")
		or descendant:IsA("Sparkles")
		or descendant:IsA("Highlight")
	then
		binding.Toggles[descendant] = {
			Visual = descendant,
			Property = "Enabled",
			Baseline = (descendant :: any).Enabled,
			LastApplied = nil,
		}
	elseif descendant:IsA("SelectionBox") then
		binding.Toggles[descendant] = {
			Visual = descendant,
			Property = "Visible",
			Baseline = descendant.Visible,
			LastApplied = nil,
		}
	end
end

local function unregisterDescendant(binding: Binding, descendant: Instance)
	local connection = binding.VisualConnections[descendant]
	if connection then
		connection:Disconnect()
		binding.VisualConnections[descendant] = nil
	end
	local partState = binding.Parts[descendant :: any]
	if partState then
		restorePart(partState)
		binding.Parts[descendant :: any] = nil
	end
	local transparencyState = binding.TransparencyVisuals[descendant]
	if transparencyState then
		restoreTransparency(transparencyState)
		binding.TransparencyVisuals[descendant] = nil
	end
	local toggleState = binding.Toggles[descendant]
	if toggleState then
		restoreToggle(toggleState)
		binding.Toggles[descendant] = nil
	end
end

function BrainrotCamouflagePresentation.Apply(
	binding: Binding,
	camouflageAmount: number,
	fullReveal: boolean,
	cueTransparency: number?
): boolean
	if binding.Destroyed then
		return false
	end
	local amount = math.clamp(camouflageAmount, 0, 1)
	local visualsChanged = binding.Dirty
		or amount ~= binding.CamouflageAmount
		or fullReveal ~= binding.FullReveal
	local cueChanged = binding.Dirty or cueTransparency ~= binding.CueTransparency
	binding.CamouflageAmount = amount
	binding.FullReveal = fullReveal
	binding.CueTransparency = cueTransparency
	if visualsChanged then
		binding.Applying = true
		for _, state in binding.Parts do
			applyPart(state, amount, fullReveal)
		end
		for _, state in binding.TransparencyVisuals do
			applyTransparency(state, amount)
		end
		for _, state in binding.Toggles do
			applyToggle(state, fullReveal)
		end
		binding.Applying = false
		binding.Dirty = false
	end
	local cue = binding.Cue
	if cueChanged and cue.Parent ~= nil then
		if cueTransparency == nil then
			cue.Enabled = false
		else
			cue.OutlineTransparency = math.clamp(cueTransparency, 0, 1)
			cue.Enabled = cue.OutlineTransparency < 1
		end
	end
	return visualsChanged
end

function BrainrotCamouflagePresentation.RestoreNormal(binding: Binding)
	if binding.Destroyed then
		return
	end
	for _, state in binding.Parts do
		restorePart(state)
	end
	for _, state in binding.TransparencyVisuals do
		restoreTransparency(state)
	end
	for _, state in binding.Toggles do
		restoreToggle(state)
	end
	binding.CamouflageAmount = 0
	binding.FullReveal = true
	binding.CueTransparency = nil
	binding.Cue.Enabled = false
	binding.Dirty = true
end

function BrainrotCamouflagePresentation.Bind(model: Model): Binding
	local cue = Instance.new("Highlight")
	cue.Name = CUE_NAME
	cue.Adornee = model
	cue.DepthMode = Enum.HighlightDepthMode.Occluded
	cue.FillTransparency = 1
	cue.OutlineColor = Color3.fromRGB(255, 255, 255)
	cue.OutlineTransparency = 1
	cue.Enabled = false
	cue.Archivable = false
	cue.Parent = model

	local binding: Binding = {
		Model = model,
		Parts = {},
		TransparencyVisuals = {},
		Toggles = {},
		Cue = cue,
		Connections = {},
		VisualConnections = {},
		Dirty = true,
		Applying = false,
		CamouflageAmount = 0,
		FullReveal = true,
		CueTransparency = nil,
		Destroyed = false,
	}
	for _, descendant in model:GetDescendants() do
		registerDescendant(binding, descendant)
	end
	table.insert(
		binding.Connections,
		model.DescendantAdded:Connect(function(descendant)
			registerDescendant(binding, descendant)
			binding.Dirty = true
			BrainrotCamouflagePresentation.Apply(
				binding,
				binding.CamouflageAmount,
				binding.FullReveal,
				binding.CueTransparency
			)
		end)
	)
	table.insert(
		binding.Connections,
		model.DescendantRemoving:Connect(function(descendant)
			unregisterDescendant(binding, descendant)
		end)
	)
	return binding
end

function BrainrotCamouflagePresentation.Unbind(binding: Binding)
	if binding.Destroyed then
		return
	end
	BrainrotCamouflagePresentation.RestoreNormal(binding)
	binding.Destroyed = true
	for _, connection in binding.Connections do
		connection:Disconnect()
	end
	table.clear(binding.Connections)
	for _, connection in binding.VisualConnections do
		connection:Disconnect()
	end
	table.clear(binding.VisualConnections)
	table.clear(binding.Parts)
	table.clear(binding.TransparencyVisuals)
	table.clear(binding.Toggles)
	binding.Cue:Destroy()
end

return table.freeze(BrainrotCamouflagePresentation)
