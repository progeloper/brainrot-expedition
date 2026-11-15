--!strict
-- Render-only adapter for EXISTING native Brainrot visuals. It never creates a
-- creature, changes identity/rarity/gameplay attributes, or edits geometry/physics.
-- Shared MaterialVariants are immutable runtime presets. All map content and
-- emissive values are authored into those presets; per-creature state selects a
-- preset instead of mutating MaterialService or swapping map IDs every frame.

local MaterialService = game:GetService("MaterialService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Config = script.Parent.Parent:WaitForChild("Config")
local Catalogue = require(Config:WaitForChild("MutationAppearanceCatalogue"))
local SurfaceRoles = require(Config:WaitForChild("MutationSurfaceRoles"))

local Adapter = {}
local SOURCE_NORMAL = Catalogue.Studs.normalMap
local SOURCE_STUDS_PER_TILE = Catalogue.Studs.studsPerTile
local MAX_AURAS = 12
local MAX_AURA_DISTANCE = 120
local VALID_STATES: { [string]: boolean } = {
	Awake = true,
	Sleeping = true,
	EscapeWarning = true,
	Carried = true,
	Cargo = true,
	Banked = true,
	Equipped = true,
}
local STATE_ALIASES: { [string]: string } = { Cart = "Cargo", Deposited = "Banked" }
local VALID_DETAILS: { [string]: boolean } = { Low = true, Medium = true, High = true }
local MUTABLE_ROLES: { [string]: boolean } =
	{ Primary = true, Secondary = true, Accent = true, SpecialSilver = true, SpecialBronze = true }

type Appearance = {
	color: Color3,
	variant: string,
	reflectance: number,
	usePartColor: boolean?,
}
type PartRecord = {
	path: string,
	role: string,
	original: Appearance,
	material: Enum.Material,
	physical: PhysicalProperties,
	mass: number,
}
type Binding = {
	model: Model,
	speciesId: string?,
	parts: { [BasePart]: PartRecord },
	issues: { string },
	connections: { RBXScriptConnection },
	mutationId: string,
	rarity: string,
	state: string,
	stateRevision: number,
	presetState: string,
	detail: string,
	concealed: boolean,
	context: any,
	aura: BillboardGui?,
	destroyed: boolean,
	wasParented: boolean,
}
local Bindings: { [Model]: Binding } = {}
local VerifiedVariants: { [MaterialVariant]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local auraCount = 0
local counters = {
	applies = 0,
	stateUpdates = 0,
	restores = 0,
	cleanups = 0,
	staleUpdates = 0,
	materialWrites = 0,
	unsupportedSurfaces = 0,
	authoringProofReads = 0,
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function stateName(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local result = STATE_ALIASES[value] or value
	return if VALID_STATES[result] then result else nil
end

local function mutationName(value: any): string?
	-- None is the live serialization sentinel. Celestial is ONLY a historical
	-- mutation alias; the independent Celestial rarity is passed through unchanged.
	if value == nil or value == "None" or value == "Normal" then
		return "Normal"
	end
	if value == "Celestial" then
		value = "Astral"
	end
	return if type(value) == "string" and Catalogue.Mutations[value] then value else nil
end

local function appearance(part: BasePart): Appearance
	return {
		color = part.Color,
		variant = part.MaterialVariant,
		reflectance = part.Reflectance,
		usePartColor = if part:IsA("UnionOperation") then part.UsePartColor else nil,
	}
end

local function restorePart(part: BasePart, original: Appearance)
	part.Color = original.color
	part.MaterialVariant = original.variant
	part.Reflectance = original.reflectance
	if part:IsA("UnionOperation") and original.usePartColor ~= nil then
		part.UsePartColor = original.usePartColor
	end
end

local function samePhysics(left: PhysicalProperties, right: PhysicalProperties): boolean
	return left.Density == right.Density
		and left.Friction == right.Friction
		and left.Elasticity == right.Elasticity
		and left.FrictionWeight == right.FrictionWeight
		and left.ElasticityWeight == right.ElasticityWeight
end

local function colorValue(value: any): Color3?
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" and string.match(value, "^#?%x%x%x%x%x%x$") then
		return Color3.fromHex(string.gsub(value, "#", ""))
	end
	return nil
end

local function clearAura(binding: Binding)
	if binding.aura then
		binding.aura:Destroy()
		binding.aura = nil
		auraCount -= 1
	end
end

local function addIssue(binding: Binding, issue: string)
	if not table.find(binding.issues, issue) then
		table.insert(binding.issues, issue)
	end
end

local function report(binding: Binding?, reason: string?)
	return {
		reason = reason,
		speciesId = if binding then binding.speciesId else nil,
		issues = if binding then table.clone(binding.issues) else {},
		complete = binding ~= nil and #binding.issues == 0 and reason == nil,
	}
end

local function presetState(mutationId: string, state: string, context: any, detail: string): string
	-- Lowest engine quality suppresses PBR normal/specular response. Glitched's
	-- saved diffuse-stud fallback preserves square relief readability there;
	-- this is not a claim of full PBR/specular parity at that quality level.
	local selected = if mutationId == "Glitched" and detail == "Low"
		then "DefaultLow"
		else "Default"
	if mutationId == "Astral" then
		selected = if state == "Awake" then "Awake" else "Revealed"
	end
	if mutationId == "Astral" and state == "EscapeWarning" then
		local progress = if type(context) == "table" then context.warningProgress else nil
		-- The implementation supplies actual warning progress. No escape clock,
		-- guessed duration, delayed gameplay action or per-frame texture update.
		if finite(progress) and progress > 0 then
			selected = "Warning"
				.. tostring(math.clamp(math.ceil(math.clamp(progress, 0, 1) * 4), 1, 4))
		end
	end
	-- Existing camouflage leaves partially transparent source surfaces. A fixed
	-- zero-emission preset prevents their glow from leaking during concealment.
	-- The visibility owner must call again when its actual reveal window ends;
	-- this adapter never guesses a reveal timer or changes local transparency.
	if
		type(context) == "table"
		and (context.isVisible == false or context.camouflageConcealed == true)
	then
		selected ..= "Hidden"
	end
	return selected
end

local function validateVariant(preset: any): (MaterialVariant?, string?)
	if type(preset) ~= "table" or preset.installed ~= true then
		return nil, "PRESET_UNINSTALLED"
	end
	if type(preset.variantName) ~= "string" then
		return nil, "MISSING_VARIANT_NAME"
	end
	local variant = MaterialService:FindFirstChild(preset.variantName)
	if not variant or not variant:IsA("MaterialVariant") then
		return nil, "MATERIAL_VARIANT_MISSING:" .. preset.variantName
	end
	if not VerifiedVariants[variant] then
		if variant.BaseMaterial ~= Enum.Material.Glacier then
			return nil, "BASE_MATERIAL_MISMATCH:" .. preset.variantName
		end
		if
			math.abs(variant.StudsPerTile / SOURCE_STUDS_PER_TILE - 1)
				> require(Config.PlaytestExact).ScaleRelativeErrorLimit
			or variant.MaterialPattern ~= Enum.MaterialPattern.Regular
		then
			return nil, "STUD_CONTRACT_MISMATCH:" .. preset.variantName
		end
		-- Texture-map reads are Plugin-security operations. Native LocalScripts
		-- consume exact Edit-authoring proof; they do not pretend to inspect maps.
		local mapRead, maps = pcall(function()
			return {
				normalMap = variant.NormalMap,
				colorMap = variant.ColorMap,
				roughnessMap = variant.RoughnessMap,
				metalnessMap = variant.MetalnessMap,
			}
		end)
		if not mapRead then
			local encoded = variant:GetAttribute("P12AuthoringProof")
			if type(encoded) ~= "string" or #encoded > 2048 then
				return nil, "AUTHORING_PROOF_REQUIRED:" .. preset.variantName
			end
			local decoded, proof = pcall(HttpService.JSONDecode, HttpService, encoded)
			if
				not decoded
				or type(proof) ~= "table"
				or proof.version ~= Catalogue.Version
				or proof.variantName ~= preset.variantName
			then
				return nil, "INVALID_AUTHORING_PROOF:" .. preset.variantName
			end
			maps = proof
			counters.authoringProofReads += 1
		end
		if maps.normalMap ~= SOURCE_NORMAL then
			return nil, "STUD_CONTRACT_MISMATCH:" .. preset.variantName
		end
		if maps.colorMap == "" or maps.roughnessMap == "" or maps.metalnessMap == "" then
			return nil, "INCOMPLETE_PBR_MAPS:" .. preset.variantName
		end
		if
			maps.colorMap ~= preset.colorMap
			or maps.roughnessMap ~= preset.roughnessMap
			or maps.metalnessMap ~= preset.metalnessMap
		then
			return nil, "PRESET_MAP_REFERENCE_MISMATCH:" .. preset.variantName
		end
		local emissionRead, emission = pcall(function()
			return (variant :: any).EmissiveStrength
		end)
		if
			not emissionRead
			or not finite(emission)
			or not finite(preset.emissiveStrength)
			or math.abs(emission - preset.emissiveStrength) > 1e-5
		then
			return nil, "PRESET_EMISSION_MISMATCH:" .. preset.variantName
		end
		-- A named variant must not introduce density/friction overrides. All
		-- current source body parts use Glacier's existing physical behavior.
		local physicalRead, customPhysical = pcall(function()
			return (variant :: any).CustomPhysicalProperties
		end)
		if physicalRead and customPhysical ~= nil then
			return nil, "PHYSICAL_OVERRIDE_NOT_ALLOWED:" .. preset.variantName
		end
		VerifiedVariants[variant] = true
	end
	return variant, nil
end

-- Full and reduced representations select the same authored state and quality.
-- Returned assignments contain only validated immutable material references.
function Adapter.ResolvePreset(
	mutationId: any,
	presentationState: string,
	detailLevel: string?,
	context: any?
)
	local mutation = mutationName(mutationId)
	local state = stateName(presentationState)
	local detail = detailLevel or "High"
	if not mutation or mutation == "Normal" then
		return nil, "MUTATION_PRESET_REQUIRED"
	end
	if not state or not VALID_DETAILS[detail] then
		return nil, "INVALID_STATE_OR_DETAIL"
	end
	local selected = presetState(mutation, state, context, detail)
	local presets = Catalogue.Mutations[mutation].presets[selected]
	if not presets then
		return nil, "MISSING_STATE_PRESET:" .. mutation .. "/" .. selected
	end
	local assignments = {}
	for role, preset in presets do
		local variant, reason = validateVariant(preset)
		if not variant then
			return nil, reason
		end
		local tint = colorValue(preset.color)
		if not tint then
			return nil, "INVALID_PRESET_COLOR:" .. role
		end
		assignments[role] = { variant = variant.Name, color = tint }
	end
	return { state = selected, roles = assignments }, nil
end

local function addPart(binding: Binding, part: BasePart, path: string, role: string)
	if binding.parts[part] then
		return
	end
	binding.parts[part] = {
		path = path,
		role = role,
		original = appearance(part),
		material = part.Material,
		physical = part.CurrentPhysicalProperties,
		mass = part:GetMass(),
	}
	if role == "Preserve" then
		addIssue(binding, "UNKNOWN_SOURCE_PATH:" .. path)
	end
end

local function newBinding(model: Model): Binding
	local resolved = SurfaceRoles.Resolve(model)
	local binding: Binding = {
		model = model,
		speciesId = resolved.speciesId,
		parts = {},
		issues = {},
		connections = {},
		mutationId = "Normal",
		rarity = "",
		state = "Awake",
		stateRevision = 0,
		presetState = "Default",
		detail = "High",
		concealed = false,
		context = nil,
		aura = nil,
		destroyed = false,
		wasParented = model:IsDescendantOf(game),
	}
	if not resolved.speciesId then
		table.insert(binding.issues, "UNKNOWN_SPECIES")
	end
	for part, entry in resolved.parts do
		addPart(binding, part, entry.path, entry.role)
	end
	for _, path in resolved.missing do
		table.insert(binding.issues, "SOURCE_PART_MISSING:" .. path)
	end
	return binding
end

-- Prepare every eligible assignment before making any appearance write. Source
-- decals, textures, neutral expression parts and unsupported future MeshParts are
-- preserved. A MeshPart needs a separately audited UV/SurfaceAppearance preset.
local function makePlan(binding: Binding, mutationId: string, selectedState: string)
	local entry = Catalogue.Mutations[mutationId]
	local presets = entry and entry.presets and entry.presets[selectedState]
	if not presets then
		return nil, "MISSING_STATE_PRESET:" .. mutationId .. "/" .. selectedState
	end
	local plan = {}
	for part, source in binding.parts do
		if MUTABLE_ROLES[source.role] and part:IsDescendantOf(binding.model) then
			if not (part:IsA("Part") or part:IsA("UnionOperation")) then
				local issue = "UNSUPPORTED_PART_TYPE:" .. source.path .. ":" .. part.ClassName
				if not table.find(binding.issues, issue) then
					table.insert(binding.issues, issue)
					counters.unsupportedSurfaces += 1
				end
			elseif source.material ~= Enum.Material.Glacier or part.Material ~= source.material then
				return nil, "SOURCE_BASE_MATERIAL_MISMATCH:" .. source.path
			elseif string.sub(source.original.variant, 1, 4) == "P12_" then
				return nil, "SOURCE_SNAPSHOT_ALREADY_MUTATED:" .. source.path
			else
				local preset = presets[source.role]
				local variant, reason = validateVariant(preset)
				if not variant then
					return nil, (reason or "INVALID_VARIANT") .. ":" .. source.path
				end
				local tint = colorValue(preset.color)
				if not tint then
					return nil, "INVALID_PRESET_COLOR:" .. source.path
				end
				table.insert(
					plan,
					{ part = part, source = source, variant = variant.Name, color = tint }
				)
			end
		end
	end
	if #plan == 0 then
		return nil, "NO_SUPPORTED_MUTABLE_SURFACES"
	end
	return plan, nil
end

local function writePlan(plan: any): (boolean, string?)
	local previous: { [BasePart]: Appearance } = {}
	local ok, failure = pcall(function()
		for _, item in plan do
			local part = item.part
			previous[part] = appearance(part)
			part.Color = item.color
			part.MaterialVariant = item.variant
			part.Reflectance = 0
			if part:IsA("UnionOperation") then
				part.UsePartColor = true
			end
			if
				not samePhysics(part.CurrentPhysicalProperties, item.source.physical)
				or part:GetMass() ~= item.source.mass
			then
				error("PHYSICAL_INVARIANT_FAILED:" .. item.source.path)
			end
			counters.materialWrites += 1
		end
	end)
	if not ok then
		for part, old in previous do
			pcall(restorePart, part, old)
		end
		return false, tostring(failure)
	end
	return true, nil
end

local function updateAura(binding: Binding)
	local context = binding.context
	local entry = Catalogue.Mutations.Astral
	local settings = entry and entry.aura
	local distance = if type(context) == "table" then context.distanceStuds else nil
	local admitted = RunService:IsClient()
		and binding.model:IsDescendantOf(game)
		and binding.mutationId == "Astral"
		and (binding.state == "Awake" or binding.state == "EscapeWarning")
		and type(settings) == "table"
		and settings.enabled == true
		and type(settings.image) == "string"
		and settings.image ~= ""
		and type(context) == "table"
		and context.glowAdmitted == true
		and context.isVisible == true
		and context.semanticOverlaysClear == true
		and context.camouflageConcealed ~= true
		and finite(distance)
		and distance >= 0
		and distance <= MAX_AURA_DISTANCE
	if not admitted then
		clearAura(binding)
		return
	end
	if not binding.aura and auraCount >= MAX_AURAS then
		return
	end
	if not binding.aura then
		local body: BasePart? = nil
		for part in binding.parts do
			if part.Name == "Body" and part:IsDescendantOf(binding.model) then
				body = part
				break
			end
		end
		if not body then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "P12_AstralLocalAura"
		gui.Archivable = false
		gui.AlwaysOnTop = false -- no shield-film shape or through-wall silhouette
		gui.LightInfluence = 0
		gui.MaxDistance = MAX_AURA_DISTANCE
		local marker = body:FindFirstChild("CaptureAttachment")
		local capture = if marker and marker:IsA("Attachment") then marker else nil
		gui.Adornee = capture or body
		-- Development art starting values, checked against actual model bounds:
		-- one compact sprite covers tall silhouettes and sits just camera-side of
		-- the torso while retaining normal world occlusion. No shell geometry.
		local boundsCFrame, boundsSize = binding.model:GetBoundingBox()
		local sizeScale = if finite(settings.sizeScale) and settings.sizeScale > 0
			then settings.sizeScale
			else 1.08
		local size =
			math.clamp(math.max(boundsSize.X, boundsSize.Y, boundsSize.Z) * sizeScale, 0.5, 12)
		local captureY = if capture and capture:IsA("Attachment")
			then capture.WorldPosition.Y
			else body.Position.Y
		local yOffset = math.max(0, boundsCFrame.Position.Y - captureY)
		local zOffset = math.min(1, math.max(0.2, boundsSize.Z * 0.5 + 0.2))
		gui.StudsOffset = Vector3.new(0, yOffset, zOffset)
		gui.Size = UDim2.fromScale(size, size)
		local image = Instance.new("ImageLabel")
		image.Name = "Radiance"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = settings.image
		image.ImageColor3 = colorValue(settings.tint) or Color3.fromRGB(155, 87, 255)
		image.Parent = gui
		binding.aura = gui
		auraCount += 1
		gui.Parent = binding.model
	end
	local image = binding.aura and binding.aura:FindFirstChild("Radiance")
	if image and image:IsA("ImageLabel") then
		local strength = if binding.state == "Awake" then 1 else 0
		if binding.state == "EscapeWarning" and finite(context.warningProgress) then
			strength = math.clamp(context.warningProgress, 0, 1)
		end
		image.ImageTransparency = 1 - strength
	end
end

local function release(binding: Binding, restore: boolean)
	if binding.destroyed then
		return
	end
	binding.destroyed = true
	clearAura(binding)
	for _, connection in binding.connections do
		connection:Disconnect()
	end
	table.clear(binding.connections)
	if restore then
		for part, source in binding.parts do
			pcall(restorePart, part, source.original)
		end
	end
	table.clear(binding.parts)
	binding.context = nil
	Bindings[binding.model] = nil
end

local function observe(binding: Binding)
	table.insert(
		binding.connections,
		binding.model.Destroying:Connect(function()
			counters.cleanups += 1
			release(binding, false)
		end)
	)
	table.insert(
		binding.connections,
		binding.model.AncestryChanged:Connect(function()
			if binding.model:IsDescendantOf(game) then
				binding.wasParented = true
			elseif binding.wasParented then
				-- A detached/streamed-out actor cannot retain renderer observers or
				-- mutate a later replacement. Rebind on stream-in from authority.
				counters.cleanups += 1
				release(binding, true)
			end
		end)
	)
	table.insert(
		binding.connections,
		binding.model.DescendantAdded:Connect(function(descendant)
			if binding.destroyed or not descendant:IsA("BasePart") then
				return
			end
			local path = SurfaceRoles.GetPath(binding.model, descendant) or descendant.Name
			local role = if binding.speciesId
				then SurfaceRoles.GetRole(binding.speciesId, path)
				else "Preserve"
			addPart(binding, descendant, path, role)
			local missing = table.find(binding.issues, "SOURCE_PART_MISSING:" .. path)
			if missing then
				table.remove(binding.issues, missing)
			end
			local plan, reason = makePlan(binding, binding.mutationId, binding.presetState)
			if plan then
				local ok, writeReason = writePlan(plan)
				if not ok then
					addIssue(binding, writeReason or "STREAM_IN_WRITE_FAILED")
				end
			else
				addIssue(binding, reason or "STREAM_IN_PRESET_FAILED")
			end
		end)
	)
	table.insert(
		binding.connections,
		binding.model.DescendantRemoving:Connect(function(descendant)
			if not descendant:IsA("BasePart") then
				return
			end
			local source = binding.parts[descendant]
			if source then
				pcall(restorePart, descendant, source.original)
				binding.parts[descendant] = nil
				if source.role ~= "Preserve" then
					addIssue(binding, "SOURCE_PART_MISSING:" .. source.path)
				else
					local unknown =
						table.find(binding.issues, "UNKNOWN_SOURCE_PATH:" .. source.path)
					if unknown then
						table.remove(binding.issues, unknown)
					end
				end
				if descendant.Name == "Body" then
					clearAura(binding)
				end
			end
		end)
	)
end


-- ===================================================================== Voxel V4
-- Role recolour for Voxel V4 models (VoxelCreatureVersion = 4). Same public API as
-- the native preset path. Protected parts (eyes, mouth, glass, lamps, markings)
-- are never written. Studs stay: the saved stud MaterialVariant is never changed.
local VoxelPalette = require(Config:WaitForChild("VoxelCreaturePalette"))
type VoxelPart = {
	color: Color3,
	material: Enum.Material,
	variant: string,
	reflectance: number,
	transparency: number,
	role: string,
	relief: boolean,
	emissive: boolean,
}
local VoxelBindings: { [Model]: any } = {}
local voxelStepAt = 0
local voxelCounters = { applies = 0, restores = 0, effects = 0, overlays = 0 }

local function isVoxel(model: Model): boolean
	return model:GetAttribute("VoxelCreatureVersion") == 4
end

local function voxelPreset(model: Model, mutation: string)
	local folder = model:FindFirstChild("Mutations")
	local config = folder and folder:FindFirstChild(mutation)
	local roles = {}
	for _, role in VoxelPalette.Roles do
		local value = config and config:GetAttribute("Role_" .. role)
		roles[role] = if typeof(value) == "Color3"
			then value
			else Color3.fromHex(VoxelPalette.MutationPalettes[mutation][role])
	end
	return roles, config
end

local function newVoxelBinding(model: Model)
	local binding = {
		model = model,
		speciesId = model:GetAttribute("VoxelSpeciesId"),
		parts = {} :: { [BasePart]: VoxelPart },
		mutationId = "Normal",
		rarity = "Common",
		state = "Awake",
		stateRevision = 0,
		detail = "High",
		effects = nil :: Folder?,
		overlays = {} :: { Texture },
		connections = {} :: { RBXScriptConnection },
		nextGlitch = 0,
		glitchUntil = 0,
		seed = 0,
		concealed = false,
		issues = {},
	}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("VoxelV4") == true then
			binding.parts[part] = {
				color = part.Color,
				material = part.Material,
				variant = part.MaterialVariant,
				reflectance = part.Reflectance,
				transparency = part.Transparency,
				role = part:GetAttribute("Role") or "Protected",
				relief = part:GetAttribute("Relief") == true,
				emissive = part:GetAttribute("Emissive") == true,
			}
		end
	end
	for _ in binding.parts do
		binding.seed += 1
	end
	table.insert(
		binding.connections,
		model.Destroying:Connect(function()
			VoxelBindings[model] = nil
		end)
	)
	return binding
end

local function voxelClearEffects(binding)
	if binding.effects then
		binding.effects:Destroy()
		binding.effects = nil
	end
	for _, texture in binding.overlays do
		texture:Destroy()
	end
	table.clear(binding.overlays)
end

local function voxelRestoreParts(binding)
	for part, original in binding.parts do
		if part.Parent then
			part.Color = original.color
			part.Material = original.material
			part.MaterialVariant = original.variant
			part.Reflectance = original.reflectance
			part.Transparency = original.transparency
		end
	end
end

local function voxelRelease(binding, restore: boolean)
	voxelClearEffects(binding)
	if restore then
		voxelRestoreParts(binding)
	end
	for _, connection in binding.connections do
		connection:Disconnect()
	end
	table.clear(binding.connections)
	VoxelBindings[binding.model] = nil
end

local function helperPart(name: string, root: BasePart, size: Vector3, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Transparency = 1
	part.Anchored = false
	part.Massless = true
	part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = false, false, false, false
	part:SetAttribute("BrainrotVisualHelper", true)
	part.Archivable = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, part
	weld.Parent = part
	part.Parent = parent
	return part
end

local function sequence(colors: { string }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(Color3.fromHex(colors[1]))
	end
	return ColorSequence.new(Color3.fromHex(colors[1]), Color3.fromHex(colors[2]))
end

-- Full quality only: overlays on visible relief faces, one emitter sized to the
-- model, the Astral halo and the radial aura. Reduced/Minimal keep colours + studs.
local function voxelBuildEffects(binding, mutation: string, config: Configuration?)
	voxelClearEffects(binding)
	local model: Model = binding.model
	local root = model.PrimaryPart
	if binding.detail ~= "High" or not root or not RunService:IsClient() and not RunService:IsStudio() then
		return
	end
	local effect = VoxelPalette.MutationEffects[mutation]
	local scale = model:GetScale()
	local folder = Instance.new("Folder")
	folder.Name = "V4_MutationEffects"
	folder.Archivable = false
	binding.effects = folder

	local image = config and config:GetAttribute("OverlayImage") or ""
	if type(image) == "string" and image ~= "" then
		for part, record in binding.parts do
			if record.relief and record.role ~= "Protected" then
				for _, face in { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
					local texture = Instance.new("Texture")
					texture.Name = "V4_Overlay"
					texture.Face = face
					texture.Texture = image
					texture.StudsPerTileU = VoxelPalette.OverlayStudsPerTile
					texture.StudsPerTileV = VoxelPalette.OverlayStudsPerTile
					texture.Color3 = Color3.new(1, 1, 1)
					texture.Archivable = false
					texture.Parent = part
					table.insert(binding.overlays, texture)
				end
			end
		end
		voxelCounters.overlays += #binding.overlays
	end

	local fx = root:FindFirstChild("FxCore")
	local centre = if fx and fx:IsA("Attachment") then fx.WorldCFrame else root.CFrame
	local box = config and config:GetAttribute("EmitterBox")
	local boxSize = if typeof(box) == "Vector3" then box * scale else Vector3.new(3, 4, 6) * scale
	local volume = helperPart("V4_FxVolume", root, boxSize, CFrame.new(centre.Position), folder)
	local spec = effect.emitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "V4_Signature"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Rate = spec.rate
	emitter.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
	emitter.Size = NumberSequence.new(spec.size[1] * scale, spec.size[2] * scale)
	emitter.Color = sequence(spec.colors)
	emitter.LightEmission = spec.lightEmission
	emitter.Texture = VoxelPalette.InterimParticleTexture
	emitter.Speed = NumberRange.new(spec.riseStudsPerSecond or 0.4)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Parent = volume

	if effect.halo then
		local Builder = require(script.Parent:WaitForChild("VoxelCreatureBuilder"))
		local radius = (config and config:GetAttribute("HaloRadius") or 2) * scale
		local height = (config and config:GetAttribute("HaloHeight") or 8) * scale
		local halo = Builder.BuildHalo(radius, effect.halo.thickness * scale, effect.halo.color)
		local frame = CFrame.new(root.Position.X, root.Position.Y + height, root.Position.Z)
			* root.CFrame.Rotation
			* CFrame.Angles(math.rad(effect.halo.tiltDegrees), 0, 0)
		halo:PivotTo(frame)
		for _, part in halo:GetChildren() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.Archivable = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = root, part
				weld.Parent = part
			end
		end
		halo.Parent = folder
	end

	local aura = Instance.new("BillboardGui")
	aura.Name = "V4_Aura"
	aura.Archivable = false
	aura.LightInfluence = 0
	aura.MaxDistance = VoxelPalette.Quality.FullMaxDistance
	aura.Adornee = volume
	local auraSize = (config and config:GetAttribute("AuraSize") or 8) * scale
	aura.Size = UDim2.fromScale(auraSize, auraSize)
	local radiance = Instance.new("ImageLabel")
	radiance.Name = "Radiance"
	radiance.BackgroundTransparency = 1
	radiance.Size = UDim2.fromScale(1, 1)
	radiance.Image = VoxelPalette.OverlayImages.AuraRadial
	local glow = config and config:GetAttribute("Glow")
	radiance.ImageColor3 = if typeof(glow) == "Color3" then glow else Color3.new(1, 1, 1)
	radiance.Parent = aura
	aura.Parent = folder
	folder.Parent = model
	voxelCounters.effects += 1
end

-- Astral v979 states: awake = intense compact radiance concealing the body from
-- afar; asleep/banked/equipped = body revealed with a controlled indigo/pearl glow.
local function voxelStateVisuals(binding)
	local aura = binding.effects and binding.effects:FindFirstChild("V4_Aura")
	local radiance = aura and aura:FindFirstChild("Radiance")
	if not (radiance and radiance:IsA("ImageLabel")) then
		return
	end
	if binding.mutationId == "Astral" then
		local awake = binding.state == "Awake" or binding.state == "EscapeWarning"
		radiance.ImageTransparency = if awake then 0.05 else 0.55
		radiance.ImageColor3 = if awake then Color3.new(1, 1, 1) else Color3.fromHex("#6D74FF")
		binding.concealed = binding.state == "Awake"
	else
		radiance.ImageTransparency = 0.72
		binding.concealed = false
	end
end

local function voxelApplyColours(binding, mutation: string)
	local roles, config = voxelPreset(binding.model, mutation)
	binding.roles = roles
	local effect = VoxelPalette.MutationEffects[mutation]
	for part, record in binding.parts do
		if record.role ~= "Protected" and part:GetAttribute("Protected") ~= true and part.Parent then
			local target = roles[record.role]
			if target then
				if mutation == "Radioactive" and not record.emissive then
					local k = 1 + (effect.bodyEmissiveTint or 0)
					target = Color3.new(math.min(1, target.R * k), math.min(1, target.G * k), math.min(1, target.B * k))
				end
				part.Color = target
				part.Transparency = record.transparency
				if not record.emissive then
					part.Reflectance = if binding.detail == "Low" then 0 else effect.reflectance
				end
			end
		end
	end
	return config
end

local function voxelReport(binding)
	return { complete = true, issues = table.clone(binding.issues), voxelV4 = true }
end

local function voxelApply(model: Model, rarity: string, mutation: string, state: string, detail: string)
	voxelCounters.applies += 1
	local existing = VoxelBindings[model]
	if mutation == "Normal" then
		if existing then
			voxelCounters.restores += 1
			voxelRelease(existing, true)
		end
		return true, { complete = true, issues = {}, voxelV4 = true }
	end
	if not VoxelPalette.MutationPalettes[mutation] then
		return false, { complete = false, issues = {}, reason = "UNKNOWN_MUTATION" }
	end
	local binding = existing or newVoxelBinding(model)
	VoxelBindings[model] = binding
	if binding.mutationId ~= mutation then
		voxelRestoreParts(binding)
	end
	binding.rarity, binding.state, binding.detail = rarity, state, detail
	binding.mutationId = mutation
	local config = voxelApplyColours(binding, mutation)
	voxelBuildEffects(binding, mutation, config)
	voxelStateVisuals(binding)
	binding.nextGlitch = os.clock() + 2.5 + (binding.seed % 15) / 10
	return true, voxelReport(binding)
end

local function voxelUpdate(model: Model, state: string, revision: number, context: any)
	local binding = VoxelBindings[model]
	if not binding then
		return false, report(nil, "APPEARANCE_NOT_BOUND")
	end
	if revision < binding.stateRevision then
		counters.staleUpdates += 1
		return false, { complete = false, issues = {}, reason = "STALE_STATE_REVISION" }
	end
	local detail = context.detailLevel or binding.detail
	binding.state, binding.stateRevision = state, revision
	if detail ~= binding.detail then
		binding.detail = detail
		local config = voxelApplyColours(binding, binding.mutationId)
		voxelBuildEffects(binding, binding.mutationId, config)
	end
	local aura = binding.effects and binding.effects:FindFirstChild("V4_Aura")
	if aura and aura:IsA("BillboardGui") then
		aura.Enabled = context.glowAdmitted ~= false and context.camouflageConcealed ~= true
	end
	voxelStateVisuals(binding)
	return true, voxelReport(binding)
end

-- Central scheduler hook (<= 10 Hz): Glitched tick and Radioactive pulse.
function Adapter.StepVoxel(now: number, reducedMotion: boolean?)
	if now - voxelStepAt < 1 / VoxelPalette.EffectTickHz then
		return
	end
	voxelStepAt = now
	local clock = os.clock()
	for _, binding in VoxelBindings do
		if binding.mutationId == "Glitched" and not reducedMotion then
			local tick = VoxelPalette.MutationEffects.Glitched.tick
			local active = clock < binding.glitchUntil
			if not active and clock >= binding.nextGlitch then
				binding.glitchUntil = clock + tick.duration
				binding.nextGlitch = clock
					+ tick.minInterval
					+ (tick.maxInterval - tick.minInterval) * ((binding.seed * 7 + math.floor(clock)) % 10) / 10
				active = true
			end
			local swap = if active then Color3.fromHex(tick.swap[1]) else nil
			for part, record in binding.parts do
				if record.emissive and record.role ~= "Protected" then
					part.Color = swap or (binding.roles and binding.roles[record.role]) or Color3.fromHex(tick.swap[2])
				end
			end
			for _, texture in binding.overlays do
				texture.OffsetStudsU = if active then tick.offsetStuds else 0
			end
		elseif binding.mutationId == "Radioactive" and binding.detail ~= "Low" then
			local pulse = VoxelPalette.MutationEffects.Radioactive.pulse
			local phase = if reducedMotion then 0 else (now % pulse.period) / pulse.period
			local transparency = pulse.maxTransparency * (0.5 - 0.5 * math.cos(phase * 2 * math.pi))
			for part, record in binding.parts do
				if record.emissive and record.role ~= "Protected" then
					part.Transparency = transparency
				end
			end
		end
	end
end

function Adapter.GetVoxelDebugStats()
	local result = table.clone(voxelCounters) :: any
	local count = 0
	for _ in VoxelBindings do
		count += 1
	end
	result.activeBindings = count
	return result
end
-- =================================================================== /Voxel V4

function Adapter.ApplyAppearance(
	model: Model,
	rarity: string,
	mutationId: any,
	presentationState: string,
	detailLevel: string?
)
	counters.applies += 1
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false, report(nil, "EXPECTED_EXISTING_MODEL")
	end
	local mutation = mutationName(mutationId)
	if not mutation then
		return false, report(Bindings[model], "UNKNOWN_MUTATION")
	end
	if mutation == "Normal" then
		return Adapter.RestoreOriginalAppearance(model)
	end
	local state = stateName(presentationState)
	local detail = detailLevel or "High"
	if not state or not VALID_DETAILS[detail] then
		return false, report(Bindings[model], "INVALID_STATE_OR_DETAIL")
	end
	if isVoxel(model) then
		return voxelApply(model, rarity, mutation, state, detail)
	end
	local existing = Bindings[model]
	local binding = existing or newBinding(model)
	local selected = presetState(mutation, state, binding.context, detail)
	if
		existing
		and binding.mutationId == mutation
		and binding.state == state
		and binding.detail == detail
	then
		binding.rarity = rarity
		return true, report(binding, nil)
	end
	local plan, reason = makePlan(binding, mutation, selected)
	if not plan then
		return false, report(binding, reason)
	end
	local ok, writeReason = writePlan(plan)
	if not ok then
		return false, report(binding, writeReason)
	end
	if not existing then
		Bindings[model] = binding
		observe(binding)
	end
	clearAura(binding)
	binding.mutationId = mutation
	binding.rarity = rarity -- independent input; including Celestial rarity unchanged
	binding.state = state
	binding.presetState = selected
	binding.detail = detail
	-- Keep established visibility authority across material changes. Aura is
	-- cleared above and needs a fresh Update to obtain central admission again.
	binding.concealed = mutation == "Astral" and state == "Awake"
	-- Only UpdateAppearanceState consumes the implementation's authoritative
	-- revision. Applying a material must not invent or advance that revision.
	return true, report(binding, nil)
end

function Adapter.UpdateAppearanceState(
	model: Model,
	presentationState: string,
	stateRevision: number,
	transitionContext: any?
)
	counters.stateUpdates += 1
	if VoxelBindings[model] then
		local voxelState = stateName(presentationState)
		if not voxelState or not finite(stateRevision) or stateRevision < 0 then
			return false, report(nil, "INVALID_STATE_OR_REVISION")
		end
		return voxelUpdate(
			model,
			voxelState,
			stateRevision,
			if type(transitionContext) == "table" then transitionContext else {}
		)
	end
	local binding = Bindings[model]
	if not binding then
		return false, report(nil, "APPEARANCE_NOT_BOUND")
	end
	local state = stateName(presentationState)
	if not state or not finite(stateRevision) or stateRevision < 0 then
		return false, report(binding, "INVALID_STATE_OR_REVISION")
	end
	if
		stateRevision < binding.stateRevision
		or (stateRevision == binding.stateRevision and state ~= binding.state)
	then
		counters.staleUpdates += 1
		return false, report(binding, "STALE_STATE_REVISION")
	end
	local context = if type(transitionContext) == "table" then transitionContext else {}
	local detail = context.detailLevel or binding.detail
	if not VALID_DETAILS[detail] then
		return false, report(binding, "INVALID_DETAIL")
	end
	local selected = presetState(binding.mutationId, state, context, detail)
	if selected ~= binding.presetState then
		local plan, reason = makePlan(binding, binding.mutationId, selected)
		if not plan then
			return false, report(binding, reason)
		end
		local ok, writeReason = writePlan(plan)
		if not ok then
			return false, report(binding, writeReason)
		end
	end
	binding.state = state
	binding.stateRevision = stateRevision
	binding.presetState = selected
	binding.detail = detail
	binding.context = table.clone(context)
	binding.concealed = binding.mutationId == "Astral" and state == "Awake"
	updateAura(binding)
	return true, report(binding, nil)
end

function Adapter.RestoreOriginalAppearance(model: Model)
	local voxel = VoxelBindings[model]
	if voxel then
		counters.restores += 1
		voxelCounters.restores += 1
		voxelRelease(voxel, true)
		return true, { complete = true, issues = {}, voxelV4 = true }
	end
	local binding = Bindings[model]
	if not binding then
		return true, { complete = true, issues = {} }
	end
	counters.restores += 1
	release(binding, true)
	return true, { complete = true, issues = {} }
end

function Adapter.CleanupAppearance(model: Model)
	counters.cleanups += 1
	return Adapter.RestoreOriginalAppearance(model)
end

function Adapter.GetAppearanceState(model: Model)
	local voxel = VoxelBindings[model]
	if voxel then
		return {
			speciesId = voxel.speciesId,
			mutationId = voxel.mutationId,
			rarity = voxel.rarity,
			state = voxel.state,
			stateRevision = voxel.stateRevision,
			presetState = "VoxelV4",
			detail = voxel.detail,
			concealed = voxel.concealed,
			issues = table.clone(voxel.issues),
			voxelV4 = true,
		}
	end
	local binding = Bindings[model]
	if not binding then
		return nil
	end
	return {
		speciesId = binding.speciesId,
		mutationId = binding.mutationId,
		rarity = binding.rarity,
		state = binding.state,
		stateRevision = binding.stateRevision,
		presetState = binding.presetState,
		detail = binding.detail,
		concealed = binding.concealed,
		issues = table.clone(binding.issues),
	}
end

function Adapter.GetDebugStats()
	local result = table.clone(counters) :: any
	local count, connections, parts = 0, 0, 0
	for _, binding in Bindings do
		count += 1
		connections += #binding.connections
		for _ in binding.parts do
			parts += 1
		end
	end
	result.activeBindings = count
	result.connections = connections
	result.trackedParts = parts
	result.auraHandles = auraCount
	result.maxAuraHandles = MAX_AURAS
	result.schedulers = 0
	result.tweens = 0
	result.runtimeMapWrites = 0
	return result
end

return table.freeze(Adapter)
