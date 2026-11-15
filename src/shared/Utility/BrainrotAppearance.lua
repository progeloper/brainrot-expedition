--!strict
-- Rendering integration, not a second mutation-material owner. All mutations
-- delegate to the separately installed, immutable-preset native adapter.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialService = game:GetService("MaterialService")
local Templates = require(ReplicatedStorage.Shared.Utility.CreatureTemplateProvider)
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotAppearanceCatalog)
local Config = require(ReplicatedStorage.Shared.Config.Phase12)
local Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local Roles = require(ReplicatedStorage.Shared.Config.MutationSurfaceRoles)
local Native = require(ReplicatedStorage.Shared.Utility.MutationAppearanceAdapter)
local Appearance = {}
local bindings: { [Model]: any } = {}
local normalGlowCount = 0
local warned: { [string]: boolean } = {}
local formationSourceRoles: { [string]: any } = {}
local colourRoles = {
	Primary = "primary",
	Secondary = "shadow",
	Accent = "highlight",
	SpecialSilver = "highlight",
	SpecialBronze = "shadow",
}
local function colourKey(color: Color3): string
	return string.format(
		"%d:%d:%d",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end
local function formationRoles(model: Model)
	local supplied, unknown, complete = {}, {}, true
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("CreatureSurfaceRole")
			if type(role) ~= "string" then
				complete = false
				break
			end
			supplied[part] = { path = part.Name, role = role }
			if role == "Preserve" then
				table.insert(unknown, part.Name)
			end
		end
	end
	if complete then
		return { parts = supplied, missing = unknown, unknown = unknown }
	end
	local id = Roles.GetSpeciesId(model)
	local map = formationSourceRoles[id]
	if not map then
		map = {}
		local source = Templates.Get(id, "Full")
		if source and source:IsA("Model") then
			for part, assignment in Roles.Resolve(source).parts do
				local key = colourKey(part.Color)
				local counts = map[key] or {}
				map[key] = counts
				counts[assignment.role] = (counts[assignment.role] or 0) + 1
			end
		end
		if source then
			formationSourceRoles[id] = map
		end
	end
	local result, unmatched = {}, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local role = "Preserve"
			if part.Name == "BodyCue" then
				role = "Primary"
			elseif part.Name == "SpeciesCue" then
				role = "Secondary"
			else
				local counts = map[colourKey(part.Color)]
				if counts then
					if counts.Neutral then
						role = "Neutral"
					else
						local maximum = 0
						for _, candidate in
							{ "Primary", "Secondary", "Accent", "SpecialSilver", "SpecialBronze" }
						do
							if (counts[candidate] or 0) > maximum then
								role = candidate
								maximum = counts[candidate]
							end
						end
					end
				end
			end
			result[part] = { path = part.Name, role = role }
			if role == "Preserve" then
				table.insert(unmatched, part.Name)
			end
		end
	end
	return { parts = result, missing = unmatched, unknown = unmatched }
end
local function restoreFormation(binding)
	for part, source in binding.formationParts or {} do
		if part.Parent then
			part.Color = source.color
			part.MaterialVariant = source.variant
			part.Reflectance = source.reflectance
			if part:IsA("UnionOperation") then
				part.UsePartColor = source.usePartColor
			end
		end
	end
end
local function applyFormation(
	model: Model,
	binding: any,
	mutation: string,
	state: string,
	quality: string,
	context: any
)
	if not binding.formationParts then
		binding.formationParts = {}
		local resolved = formationRoles(model)
		binding.formationIssues = resolved.unknown
		for part, assignment in resolved.parts do
			binding.formationParts[part] = {
				role = assignment.role,
				color = part.Color,
				variant = part.MaterialVariant,
				reflectance = part.Reflectance,
				usePartColor = if part:IsA("UnionOperation") then part.UsePartColor else nil,
			}
		end
	end
	local selection, reason = Native.ResolvePreset(mutation, state, quality, context)
	if not selection then
		binding.result = { complete = false, issues = binding.formationIssues, reason = reason }
		return
	end
	local plan = {}
	for part, source in binding.formationParts do
		if colourRoles[source.role] and part.Parent then
			local preset = selection.roles[source.role]
			local variant = preset and MaterialService:FindFirstChild(preset.variant)
			if not variant or variant.BaseMaterial ~= part.Material then
				binding.result = {
					complete = false,
					issues = binding.formationIssues,
					reason = "SOURCE_BASE_MATERIAL_MISMATCH:" .. part.Name,
				}
				return
			end
			table.insert(plan, { part = part, preset = preset })
		end
	end
	if #plan == 0 then
		binding.result = {
			complete = false,
			issues = binding.formationIssues,
			reason = "NO_SUPPORTED_MUTABLE_SURFACES",
		}
		return
	end
	for _, item in plan do
		item.part.Color = item.preset.color
		item.part.MaterialVariant = item.preset.variant
		item.part.Reflectance = 0
		if item.part:IsA("UnionOperation") then
			item.part.UsePartColor = true
		end
	end
	binding.formationPresetState = selection.state
	binding.result = {
		complete = #binding.formationIssues == 0,
		issues = binding.formationIssues,
		reducedVariant = true,
	}
end
local function bindingFor(model: Model)
	local binding = bindings[model]
	if not binding then
		binding = {
			normalParts = {},
			normalApplied = false,
			glow = nil,
			mutation = "None",
			state = "Awake",
			revision = 0,
			contextSignature = nil,
		}
		bindings[model] = binding
	end
	return binding
end
local function removeGlow(binding)
	if binding.glow then
		binding.glow:Destroy()
		binding.glow = nil
		normalGlowCount = math.max(0, normalGlowCount - 1)
	end
end
local function restoreNormal(binding)
	if not binding.normalApplied then
		return
	end
	for part, original in binding.normalParts do
		if part.Parent then
			part.Color = original.color
			if part:IsA("UnionOperation") then
				part.UsePartColor = original.usePartColor
			end
		end
	end
	binding.normalApplied = false
	removeGlow(binding)
end
local function contextKey(state, context)
	return table.concat({
		state,
		tostring(context.isVisible),
		tostring(context.camouflageConcealed),
		tostring(context.glowAdmitted),
		tostring(context.semanticOverlaysClear),
		tostring(context.detailLevel),
		tostring(math.ceil((context.warningProgress or 0) * 4)),
	}, ":")
end
function Appearance.UpdateAppearanceState(model: Model, state: string, context: any?)
	local binding = bindings[model]
	if not binding then
		return
	end
	local supplied = table.clone(context or {})
	if
		binding.mutation == "Astral"
		and supplied.glowAdmitted == true
		and not binding.nativeAdmitted
		and normalGlowCount + Native.GetDebugStats().auraHandles
			>= Config.Presentation.MaxDetailedGlows
	then
		supplied.glowAdmitted = false
	end
	local key = contextKey(state, supplied)
	if key == binding.contextSignature then
		return
	end
	binding.contextSignature = key
	binding.revision += 1 -- presentation ordering only; server state/deadlines remain the inputs
	binding.state = state
	if binding.formationParts and binding.mutation ~= "None" then
		applyFormation(
			model,
			binding,
			binding.mutation,
			state,
			supplied.detailLevel or binding.quality,
			supplied
		)
		return
	end
	if binding.mutation == "None" then
		if binding.glow then
			binding.glow.FillColor, binding.glow.OutlineColor =
				binding.colours.primary, binding.colours.highlight
		end
		local wants = supplied.glowAdmitted == true
			and supplied.isVisible ~= false
			and supplied.semanticOverlaysClear ~= false
			and not supplied.camouflageConcealed
			and binding.rarity ~= "Common"
		if not wants then
			removeGlow(binding)
		end
		if
			wants
			and not binding.glow
			and normalGlowCount + Native.GetDebugStats().auraHandles
				< Config.Presentation.MaxDetailedGlows
		then
			local glow = Instance.new("Highlight")
			glow.Name, glow.Adornee, glow.DepthMode =
				"Phase12RarityGlow", model, Enum.HighlightDepthMode.Occluded
			glow.FillColor, glow.OutlineColor = binding.colours.primary, binding.colours.highlight
			glow.FillTransparency, glow.OutlineTransparency = 0.96, 0.60
			glow.Parent = model
			binding.glow = glow
			normalGlowCount += 1
		end
	else
		local ok, result = Native.UpdateAppearanceState(model, state, binding.revision, supplied)
		binding.result = result
		binding.nativeAdmitted = supplied.glowAdmitted == true
			and supplied.isVisible == true
			and supplied.semanticOverlaysClear == true
			and not supplied.camouflageConcealed
			and (state == "Awake" or state == "EscapeWarning")
		if not ok and result and result.reason and not warned[result.reason] then
			warned[result.reason] = true
			warn("[Phase12Appearance] " .. result.reason)
		end
	end
end
function Appearance.ApplyAppearance(
	model: Model,
	rarity: string,
	mutationId: any,
	state: string,
	detail: string,
	context: any?
)
	local mutation = Rules.NormalizeMutation(mutationId) or "None"
	local binding = bindingFor(model)
	-- Optional glow admission is separate from the authoritative material tier.
	local quality = (context and context.detailLevel) or "Low"
	binding.quality = quality
	local supplied = table.clone(context or {})
	supplied.detailLevel = quality
	supplied.glowAdmitted = supplied.glowAdmitted == true and detail == "Detailed"
	if mutation == "None" then
		if binding.mutation ~= "None" then
			Native.RestoreOriginalAppearance(model)
			if binding.formationParts then
				restoreFormation(binding)
			end
		end
		binding.rarity, binding.colours =
			rarity, Catalog.Rarities[rarity] or Catalog.Rarities.Common
		for part in binding.normalParts do
			if part.Parent == nil or not part:IsDescendantOf(model) then
				binding.normalParts[part] = nil
			end
		end
		local voxel = model:GetAttribute("VoxelCreatureVersion") == 4
		local resolved = if voxel
			then { missing = {} }
			elseif model:GetAttribute("Phase12FormationLOD") then formationRoles(model)
			else Roles.Resolve(model)
		-- Normal means canonical art, including unflagged/reconstructed roles.
		restoreNormal(binding)
		binding.normalApplied = false
		binding.result = { complete = #resolved.missing == 0, issues = resolved.missing }
	else
		restoreNormal(binding)
		removeGlow(binding)
		-- Voxel V4 models always use their full role map, never formation unions.
		if
			model:GetAttribute("Phase12FormationLOD")
			and model:GetAttribute("VoxelCreatureVersion") ~= 4
		then
			applyFormation(model, binding, mutation, state, quality, supplied)
		else
			local ok, result = Native.ApplyAppearance(model, rarity, mutation, state, quality)
			binding.result = result
			if not ok and result and result.reason and not warned[result.reason] then
				warned[result.reason] = true
				warn("[Phase12Appearance] " .. result.reason)
			end
		end
	end
	binding.mutation = mutation
	binding.contextSignature = nil
	Appearance.UpdateAppearanceState(model, state, supplied)
	return binding.result and binding.result.complete == true, binding.result
end
function Appearance.Step(serverTime: number, reducedMotion: boolean)
	Native.StepVoxel(serverTime, reducedMotion)
	for _, binding in bindings do
		if binding.glow and binding.rarity == "Mythic" then
			binding.glow.OutlineTransparency = if reducedMotion
				then 0.5
				else 0.4 + 0.2 * math.sin(serverTime * math.pi * 1.6)
		end
	end
end
function Appearance.Restore(model: Model)
	local binding = bindings[model]
	Native.CleanupAppearance(model)
	if binding then
		if binding.formationParts then
			restoreFormation(binding)
		end
		restoreNormal(binding)
		removeGlow(binding)
		bindings[model] = nil
	end
end
function Appearance.GetDiagnostics()
	local count, issues = 0, 0
	for _, binding in bindings do
		count += 1
		if binding.result and binding.result.issues then
			issues += #binding.result.issues
		end
	end
	local native = Native.GetDebugStats()
	return {
		boundModels = count,
		detailedGlows = normalGlowCount + native.auraHandles,
		normalGlows = normalGlowCount,
		native = native,
		compatibilityIssues = issues,
		textureAssetsInstalled = Catalog.TextureAssetsInstalled,
		textureRenderingVerified = Catalog.TextureRenderingVerified,
	}
end
return table.freeze(Appearance)
