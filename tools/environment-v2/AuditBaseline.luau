--!nocheck
-- Load as a detached API. Capture reads the current DEV Edit world and writes only ephemeral shared data.
local A = {}
local OWNER = "BR_EnvironmentArt_V2"
local PLAN = "916d8081573c119b7e868caf853998cd1895976a4d579ca773dbe640bc361dc1"
local function services()
	return game:GetService("CollectionService"), game:GetService("HttpService")
end
local function encode(v, key)
	local t = typeof(v)
	if t == "nil" then return { type = "nil" } end
	if t == "Instance" then return { type = t, key = key(v), path = v:GetFullName() } end
	if t == "CFrame" then return { type = t, value = { v:GetComponents() } } end
	if t == "Vector3" then return { type = t, value = { v.X, v.Y, v.Z } } end
	if t == "Vector2" then return { type = t, value = { v.X, v.Y } } end
	if t == "Color3" then return { type = t, value = { v.R, v.G, v.B } } end
	if t == "UDim" then return { type = t, value = { v.Scale, v.Offset } } end
	if t == "UDim2" then return { type = t, value = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } } end
	if t == "PhysicalProperties" then return { type = t, value = { v.Density, v.Friction, v.Elasticity, v.FrictionWeight, v.ElasticityWeight } } end
	if t == "EnumItem" then return { type = t, value = tostring(v) } end
	assert(t == "number" or t == "string" or t == "boolean", "Unsupported captured kind " .. t)
	return v
end
local COMMON_PART = { "CFrame", "Size", "PivotOffset", "Anchored", "CanCollide", "CanTouch", "CanQuery", "CollisionGroup", "Transparency", "LocalTransparencyModifier", "Reflectance", "CastShadow", "Material", "MaterialVariant", "Color", "CustomPhysicalProperties", "CurrentPhysicalProperties", "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface", "Massless", "RootPriority" }
local CLASS_PROPERTIES = {
	{ "MeshPart", { "MeshId", "TextureID", "DoubleSided", "RenderFidelity", "CollisionFidelity" } },
	{ "PartOperation", { "AssetId", "UsePartColor", "RenderFidelity", "CollisionFidelity", "SmoothingAngle", "ExtentsCFrame", "ExtentsSize" } },
	{ "Part", { "Shape" } },
	{ "Attachment", { "CFrame", "Visible", "Axis", "SecondaryAxis" } },
	{ "ProximityPrompt", { "ActionText", "ObjectText", "Enabled", "MaxActivationDistance", "RequiresLineOfSight", "HoldDuration", "KeyboardKeyCode", "GamepadKeyCode", "Exclusivity", "ClickablePrompt", "UIOffset" } },
	{ "Texture", { "Texture", "Transparency", "Color3", "Face", "ZIndex", "StudsPerTileU", "StudsPerTileV", "OffsetStudsU", "OffsetStudsV" } },
	{ "Decal", { "Texture", "Transparency", "Color3", "Face", "ZIndex" } },
	{ "SurfaceAppearance", { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap", "AlphaMode", "Color" } },
	{ "MaterialVariant", { "BaseMaterial", "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap", "StudsPerTile", "MaterialPattern" } },
	{ "GuiObject", { "Size", "Position", "AnchorPoint", "Rotation", "Visible", "BackgroundColor3", "BackgroundTransparency", "ZIndex", "LayoutOrder" } },
	{ "TextLabel", { "Text", "TextColor3", "TextTransparency", "Font", "TextSize", "TextScaled", "TextWrapped", "TextXAlignment", "TextYAlignment", "TextStrokeColor3", "TextStrokeTransparency" } },
	{ "ImageLabel", { "Image", "ImageColor3", "ImageTransparency", "ScaleType", "ImageRectOffset", "ImageRectSize" } },
	{ "SurfaceGui", { "Adornee", "Enabled", "AlwaysOnTop", "LightInfluence", "CanvasSize", "PixelsPerStud", "SizingMode", "Face" } },
	{ "BillboardGui", { "Adornee", "Enabled", "AlwaysOnTop", "LightInfluence", "Size", "StudsOffset", "MaxDistance" } },
	{ "UIStroke", { "Color", "Thickness", "Transparency", "Enabled", "ApplyStrokeMode", "LineJoinMode" } },
	{ "Constraint", { "Enabled", "Attachment0", "Attachment1" } },
	{ "JointInstance", { "Part0", "Part1", "C0", "C1", "Enabled" } },
	{ "WeldConstraint", { "Part0", "Part1", "Enabled" } },
	{ "SpecialMesh", { "MeshType", "MeshId", "TextureId", "Offset", "Scale", "VertexColor" } },
	{ "BaseScript", { "Enabled", "RunContext" } },
	{ "Sky", { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId", "SunAngularSize", "MoonAngularSize", "StarCount", "CelestialBodiesShown" } },
	{ "PostEffect", { "Enabled" } },
	{ "BloomEffect", { "Intensity", "Size", "Threshold" } },
	{ "SunRaysEffect", { "Intensity", "Spread" } },
	{ "ColorCorrectionEffect", { "Brightness", "Contrast", "Saturation", "TintColor" } },
	{ "DepthOfFieldEffect", { "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" } },
	{ "Atmosphere", { "Density", "Offset", "Color", "Decay", "Glare", "Haze" } },
}
local LIGHTING = { "Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "ColorShift_Bottom", "ColorShift_Top", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ExposureCompensation", "GlobalShadows", "ShadowSoftness", "LightingStyle", "PrioritizeLightingQuality", "FogColor", "FogStart", "FogEnd" }
local STREAMING = { "StreamingEnabled", "StreamingMinRadius", "StreamingTargetRadius", "StreamingIntegrityMode", "ModelStreamingBehavior" }
local AVATAR = { "CharacterUseJumpPower", "CharacterJumpPower", "CharacterJumpHeight", "CharacterWalkSpeed", "CharacterMaxSlopeAngle" }
function A.KeyFactory()
	local keys, refs = {}, {}
	local function key(node)
		if keys[node] then return keys[node] end
		if node == game then keys[node] = "game"; refs.game = node; return "game" end
		local index = 1
		if node.Parent then
			for _, sibling in node.Parent:GetChildren() do
				if sibling == node then break end
				if sibling.Name == node.Name and sibling.ClassName == node.ClassName then index += 1 end
			end
		end
		local value = (node.Parent and key(node.Parent) or "detached") .. "/" .. node.ClassName .. ":" .. node.Name .. "[" .. index .. "]"
		assert(not refs[value] or refs[value] == node, "Duplicate capture key")
		keys[node], refs[value] = value, node
		return value
	end
	return key, refs
end
function A.Properties(node, names, key)
	local out = {}
	for _, name in names do
		local ok, value = pcall(function() return node[name] end)
		out[name] = if ok then encode(value, key) else { unavailable = true }
	end
	return out
end
function A.Record(node, key)
	local CS = services()
	local attributes = {}; for n, v in node:GetAttributes() do attributes[n] = encode(v, key) end
	local tags = CS:GetTags(node); table.sort(tags)
	local r = { key = key(node), path = node:GetFullName(), name = node.Name, class = node.ClassName, parent = node.Parent and key(node.Parent) or nil, archivable = node.Archivable, attributes = attributes, tags = tags, properties = {} }
	if node:IsA("BasePart") then
		r.properties = A.Properties(node, COMMON_PART, key)
		r.mass = node:GetMass()
	end
	for _, item in CLASS_PROPERTIES do
		if node:IsA(item[1]) then for n, v in A.Properties(node, item[2], key) do r.properties[n] = v end end
	end
	if node:IsA("Model") then
		r.properties.PrimaryPart = encode(node.PrimaryPart, key)
		r.properties.WorldPivot = encode(node.WorldPivot, key)
		r.properties.ModelStreamingMode = encode(node.ModelStreamingMode, key)
		r.pivot = encode(node:GetPivot(), key); r.scale = node:GetScale()
	end
	if node:IsA("ValueBase") then r.properties.Value = encode(node.Value, key) end
	return r
end
function A.Environment(key)
	local physics = game:GetService("PhysicsService")
	local matrix = {}; local groups = physics:GetRegisteredCollisionGroups()
	for _, a in groups do
		local row = { name = a.name, mask = {} }
		for _, b in groups do row.mask[b.name] = physics:CollisionGroupsAreCollidable(a.name, b.name) end
		table.insert(matrix, row)
	end
	table.sort(matrix, function(a, b) return a.name < b.name end)
	local materialOverrides = {}
	for _, material in Enum.Material:GetEnumItems() do local ok, value = pcall(function() return game:GetService("MaterialService"):GetBaseMaterialOverride(material) end); if ok then materialOverrides[material.Name] = value end end
	return { lighting = A.Properties(game:GetService("Lighting"), LIGHTING, key), streaming = A.Properties(workspace, STREAMING, key), avatarSettings = A.Properties(game:GetService("StarterPlayer"), AVATAR, key), materialService = A.Properties(game:GetService("MaterialService"), {"Use2022Materials"}, key), materialOverrides = materialOverrides, collisionMatrix = matrix }
end
function A.Equal(a, b, epsilon)
	if type(a) ~= type(b) then return false end
	if type(a) == "number" then return a == b or math.abs(a - b) <= (epsilon or 0) end
	if type(a) ~= "table" then return a == b end
	if a.type == "Instance" and b.type == "Instance" then return a.key == b.key end
	for k, v in a do if not A.Equal(v, b[k], epsilon) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end
function A.UTF8Chunks(text, limit)
	limit = limit or 60000; assert(limit >= 4 and limit <= 60000, "Bounded UTF8 chunk limit")
	local chunks, start = {}, 1
	while start <= #text do
		local finish = math.min(start + limit - 1, #text)
		while finish < #text and string.byte(text, finish + 1) >= 128 and string.byte(text, finish + 1) <= 191 do finish -= 1 end
		assert(finish >= start, "Invalid UTF8 chunk")
		table.insert(chunks, text:sub(start, finish)); start = finish + 1
	end
	assert(table.concat(chunks) == text, "Complete exact transfer required")
	return chunks
end
function A.Capture(options)
	options = options or {}
	local Run = game:GetService("RunService")
	assert(Run:IsStudio() and not Run:IsRunning(), "Environment baseline requires DEV Edit")
	assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Wrong DEV place/universe")
	local map = assert(workspace:FindFirstChild("MapBlockout"), "Current reduced map missing")
	assert(map:GetAttribute("CompactMapStatus") == "Completed" and map:GetAttribute("CompactMapDesiredHash") == PLAN, "Current completed compact geometry required")
	local key, refs = A.KeyFactory()
	local roots = { { role = "Map", node = map }, { role = "ProtectedAssets", node = assert(game:GetService("ReplicatedStorage"):FindFirstChild("StudioAssets")) }, { role = "External", node = assert(workspace:FindFirstChild("Baseplate")) }, { role = "Lighting", node = game:GetService("Lighting") }, { role = "MaterialService", node = game:GetService("MaterialService") } }
	local records, rootRows, seen = {}, {}, {}
	for _, root in roots do
		table.insert(rootRows, { role = root.role, key = key(root.node), path = root.node:GetFullName() })
		local nodes = root.node:GetDescendants(); table.insert(nodes, 1, root.node)
		for _, node in nodes do if not seen[node] then local r = A.Record(node, key); r.scope = root.role; table.insert(records, r); seen[node] = true end end
	end
	local sources = {}; local SES = game:GetService("ScriptEditorService")
	for _, node in game:GetDescendants() do
		if node:IsA("LuaSourceContainer") then
			local source = node.Source
			local editorOK, editor = pcall(function() return SES:GetEditorSource(node) end)
			local r = A.Record(node, key); r.source = source; r.sourceBytes = #source
			r.editorSourceAvailable = editorOK; if editorOK then r.editorSource = editor; r.editorSourceBytes = #editor end
			table.insert(sources, r)
		end
	end
	table.sort(records, function(a, b) return a.key < b.key end); table.sort(sources, function(a, b) return a.key < b.key end)
	assert(#sources == (options.expectedSources or 357), "Unexpected current source population; inspect and rebind, do not force")
	local brainrots = assert(roots[2].node:FindFirstChild("Brainrots")); local species = 0; local parts = 0
	for _, model in brainrots:GetChildren() do if model:IsA("Model") and model.Name:match("^BRT_%d%d%d$") then species += 1; for _, p in model:GetDescendants() do if p:IsA("BasePart") then parts += 1 end end end end
	assert(species == 35 and parts == 890, "Complete accepted native roster required")
	local manifest = { schemaVersion = 2, owner = OWNER, mode = "Edit", placeId = game.PlaceId, universeId = game.GameId, capturedAtUTC = os.date("!%Y-%m-%dT%H:%M:%SZ"), engine = (function() local f = getfenv(0).version; return if type(f) == "function" then f() else "Unavailable" end)(), compactPlanHash = PLAN, roots = rootRows, records = records, environment = A.Environment(key), sourcesCount = #sources, brainrotModels = species, brainrotBaseParts = parts, terrainVoxelCapture = "Not captured; no terrain voxel edit is permitted by this tool", sourceCapture = "Fresh current357 source bytes and available editor buffers, no local src substitution" }
	local _, Http = services()
	local context = { owner = OWNER, manifest = manifest, sources = sources, refs = refs, map = map, manifestJSON = Http:JSONEncode(manifest), sourcesJSON = Http:JSONEncode(sources), sceneSHA256 = nil }
	context.manifestChunks = A.UTF8Chunks(context.manifestJSON); context.sourceChunks = A.UTF8Chunks(context.sourcesJSON)
	shared.EnvironmentV2Baseline = context
	return { status = "CapturedFreshReadOnlyBaseline", records = #records, sources = #sources, brainrotModels = species, brainrotBaseParts = parts, manifestBytes = #context.manifestJSON, sourceBytes = #context.sourcesJSON, manifestChunks = #context.manifestChunks, sourceChunks = #context.sourceChunks, maximumChunkBytes = 60000, worldWrites = 0, sourceWrites = 0, profilesReadOrWritten = 0 }
end
function A.GetChunk(kind, index)
	local context = assert(shared.EnvironmentV2Baseline, "Capture first")
	local chunks = if kind == "Manifest" then context.manifestChunks elseif kind == "Sources" then context.sourceChunks else nil
	assert(chunks and type(index) == "number" and index % 1 == 0 and chunks[index], "Invalid transfer chunk")
	return { kind = kind, index = index, count = #chunks, bytes = #chunks[index], text = chunks[index], completeJSONBytes = if kind == "Manifest" then #context.manifestJSON else #context.sourcesJSON }
end
return A
