--!strict
-- One owner composes the permanent approved baseline and temporary event deltas.
-- No frame connections, world geometry, particles, texture preloads or server loops.
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Configuration = require(script.Parent.Parent.Config.ApprovedSky)
local Owner = {}
local FACE_PROPERTIES = { "SkyboxFt", "SkyboxBk", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SkyboxDn" }
-- Read stock sky values from the installed engine, including sun/moon/stars.
local STOCK_SKY_PROPERTIES = {
	"SkyboxFt",
	"SkyboxBk",
	"SkyboxRt",
	"SkyboxLf",
	"SkyboxUp",
	"SkyboxDn",
	"SkyboxOrientation",
	"CelestialBodiesShown",
	"SunTextureId",
	"MoonTextureId",
	"SunAngularSize",
	"MoonAngularSize",
	"StarCount",
}
local stockSky = Instance.new("Sky")
local stockSkyValues = {}
for _, property in STOCK_SKY_PROPERTIES do
	stockSkyValues[property] = stockSky[property]
end
stockSky:Destroy()
local REQUIRED_LIGHTING = {
	"LightingStyle",
	"PrioritizeLightingQuality",
	"Ambient",
	"OutdoorAmbient",
	"Brightness",
	"ClockTime",
	"GeographicLatitude",
	"ExposureCompensation",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"GlobalShadows",
	"ColorShift_Top",
	"ColorShift_Bottom",
}
local SCHEMAS = {
	BlurEffect = { "Enabled" },
	Atmosphere = { "Color", "Decay", "Density", "Offset", "Haze", "Glare" },
	BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
	ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
	SunRaysEffect = { "Enabled", "Intensity", "Spread" },
	DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
}
local TOKEN_ATTRIBUTE = "ApprovedCosmicSkyEventToken"
local VERSION_ATTRIBUTE = "ApprovedCosmicBaselineVersion"
local EVENT_ATTRIBUTE = "ApprovedCosmicTemporaryEffect"
local EVENT_NAME = "Phase12SkyTint"
local AUTHORING_ONLY_LIGHTING = { LightingStyle = true, PrioritizeLightingQuality = true }
local PROPERTY_TYPES = {
	LightingStyle = "EnumItem",
	PrioritizeLightingQuality = "boolean",
	Ambient = "Color3",
	OutdoorAmbient = "Color3",
	Brightness = "number",
	ClockTime = "number",
	GeographicLatitude = "number",
	ExposureCompensation = "number",
	EnvironmentDiffuseScale = "number",
	EnvironmentSpecularScale = "number",
	GlobalShadows = "boolean",
	ShadowSoftness = "number",
	ColorShift_Top = "Color3",
	ColorShift_Bottom = "Color3",
	FogColor = "Color3",
	FogStart = "number",
	FogEnd = "number",
	Color = "Color3",
	Decay = "Color3",
	Density = "number",
	Offset = "number",
	Haze = "number",
	Glare = "number",
	Enabled = "boolean",
	Intensity = "number",
	Spread = "number",
	Size = "number",
	Threshold = "number",
	Contrast = "number",
	Saturation = "number",
	TintColor = "Color3",
	FarIntensity = "number",
	FocusDistance = "number",
	InFocusRadius = "number",
	NearIntensity = "number",
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function validProperty(property: string, value: any): boolean
	local expected = PROPERTY_TYPES[property]
	if expected == nil or typeof(value) ~= expected then
		return false
	end
	if expected == "number" then
		return finite(value)
	end
	if expected == "Color3" then
		return finite(value.R) and finite(value.G) and finite(value.B)
	end
	if property == "LightingStyle" then
		return value == Enum.LightingStyle.Soft or value == Enum.LightingStyle.Realistic
	end
	return true
end
local function allowedProperty(className: string, property: string): boolean
	if className == "Lighting" then
		return table.find(REQUIRED_LIGHTING, property) ~= nil
			or property == "FogColor"
			or property == "FogStart"
			or property == "FogEnd"
	end
	return SCHEMAS[className] ~= nil and table.find(SCHEMAS[className], property) ~= nil
end
local function validate(configuration: any): (boolean, string?)
	if type(configuration) ~= "table" or configuration.Enabled ~= true then
		return false, "PENDING_APPROVED_BASELINE"
	end
	if type(configuration.Version) ~= "string" or configuration.Version == "" then
		return false, "BASELINE_VERSION_REQUIRED"
	end
	if configuration.SkyMode ~= "RobloxDefault" then
		if type(configuration.Faces) ~= "table" or typeof(configuration.SkyboxOrientation) ~= "Vector3" then
			return false, "SIX_REAL_FACES_AND_FIXED_ORIENTATION_REQUIRED"
		end
		if
			not finite(configuration.SkyboxOrientation.X)
			or not finite(configuration.SkyboxOrientation.Y)
			or not finite(configuration.SkyboxOrientation.Z)
		then
			return false, "NONFINITE_SKY_ORIENTATION"
		end
		local ids = {}
		for _, property in FACE_PROPERTIES do
			local value = configuration.Faces[property]
			local number = if type(value) == "string" then value:match("^rbxassetid://(%d+)$") else nil
			if not number or not tonumber(number) or tonumber(number) <= 0 or ids[number] then
				return false, "INVALID_OR_REPEATED_SKY_FACE:" .. property
			end
			ids[number] = true
		end
	end
	if type(configuration.OwnedNames) ~= "table" or type(configuration.Lighting) ~= "table" then
		return false, "APPROVED_LIGHTING_DESCRIPTOR_REQUIRED"
	end
	for _, property in REQUIRED_LIGHTING do
		if configuration.Lighting[property] == nil then
			return false, "MISSING_LIGHTING:" .. property
		end
	end
	for className, properties in SCHEMAS do
		local values = configuration[className]
		if type(values) ~= "table" or type(configuration.OwnedNames[className]) ~= "string" then
			return false, "MISSING_OWNED_EFFECT:" .. className
		end
		for _, property in properties do
			if values[property] == nil then
				return false, "MISSING_EFFECT_PROPERTY:" .. className .. "." .. property
			end
		end
	end
	if type(configuration.OwnedNames.Sky) ~= "string" then
		return false, "SKY_OWNER_NAME_REQUIRED"
	end
	for _, className in
		{
			"Lighting",
			"Atmosphere",
			"BloomEffect",
			"ColorCorrectionEffect",
			"SunRaysEffect",
			"DepthOfFieldEffect",
			"BlurEffect",
		}
	do
		local values = configuration[className]
		for property, value in values do
			if not allowedProperty(className, property) or not validProperty(property, value) then
				return false, "UNSUPPORTED_BASELINE_PROPERTY:" .. property
			end
		end
	end
	return true
end
local function createOwner(context: any)
	local root = context.root
	local provider = context.configurationProvider
	local readLighting = context.readLighting
	local writeLighting = context.writeLighting
	local configurationOverride = nil
	local reducedEffects = false
	local diagnostics = {
		applies = 0,
		applicationReady = false,
		eventClaims = 0,
		staleReleases = 0,
		propertyWrites = 0,
		skyTextureWrites = 0,
		authoringOnlyMismatches = {},
		runtimePropertyFailures = {},
	}
	local api = {}
	local function currentConfiguration()
		return configurationOverride or provider()
	end
	local function ownedObject(className: string, name: string): (Instance?, string?)
		local named = root:FindFirstChild(name)
		if named then
			return if named:IsA(className) then named else nil,
				if named:IsA(className) then nil else "OWNER_NAME_CLASS_CONFLICT:" .. name
		end
		local found = nil
		for _, child in root:GetChildren() do
			if child:IsA(className) and child:GetAttribute(EVENT_ATTRIBUTE) ~= true and child.Name ~= EVENT_NAME then
				if found then
					return nil, "AMBIGUOUS_ARTIST_OWNED_CLASS:" .. className
				end
				found = child
			end
		end
		-- A sole artist-owned instance keeps its identity and name.
		return found
	end
	local function removeEventTint(token: string?)
		for _, child in root:GetChildren() do
			if child.Name == EVENT_NAME and child:IsA("ColorCorrectionEffect") then
				local owned = child:GetAttribute(EVENT_ATTRIBUTE) == true
				local childToken = child:GetAttribute(TOKEN_ATTRIBUTE)
				-- Adopt only the known old coordinator's untagged temporary effect.
				if (owned and (token == nil or childToken == token)) or (token == nil and not owned) then
					child:Destroy()
				end
			end
		end
	end
	local function setProperty(instance: Instance, property: string, value: any, texture: boolean?)
		local readable, actual = pcall(function()
			return instance[property]
		end)
		if not readable then
			table.insert(
				diagnostics.runtimePropertyFailures,
				instance.Name .. "." .. property .. ":" .. tostring(actual)
			)
			return
		end
		if actual ~= value then
			local writable, reason = pcall(function()
				instance[property] = value
			end)
			if not writable then
				table.insert(
					diagnostics.runtimePropertyFailures,
					instance.Name .. "." .. property .. ":" .. tostring(reason)
				)
				return
			end
			diagnostics.propertyWrites += 1
			if texture then
				diagnostics.skyTextureWrites += 1
			end
		end
	end
	local function resolveObjects(configuration: any): (any?, string?)
		local objects = {}
		for _, className in
			{
				"Sky",
				"Atmosphere",
				"BloomEffect",
				"ColorCorrectionEffect",
				"SunRaysEffect",
				"DepthOfFieldEffect",
				"BlurEffect",
			}
		do
			local object, reason = ownedObject(className, configuration.OwnedNames[className])
			if className == "Sky" and configuration.SkyMode == "RobloxDefault" then
				-- There is one stock-sky owner. Remove extra Sky instances only;
				-- do not touch Atmosphere, lights or temporary gameplay effects.
				object = root:FindFirstChild(configuration.OwnedNames.Sky)
				if object and not object:IsA("Sky") then
					return nil, "OWNER_NAME_CLASS_CONFLICT:Sky"
				end
				for _, child in root:GetChildren() do
					if child:IsA("Sky") then
						if not object then
							object = child
						else
							if child ~= object then
								child:Destroy()
							end
						end
					end
				end
				reason = nil
			end
			if reason then
				return nil, reason
			end
			objects[className] = object or false
		end
		return objects
	end
	function api.ApplyBaseline(configuration: any?): (boolean, string?)
		local candidate = configuration or currentConfiguration()
		diagnostics.applicationReady = false
		diagnostics.desiredVersion = if type(candidate) == "table" then candidate.Version else nil
		local ok, reason = validate(candidate)
		if not ok then
			diagnostics.lastApplicationReason = reason
			return false, reason
		end
		local objects, objectReason = resolveObjects(candidate)
		if not objects then
			diagnostics.lastApplicationReason = objectReason
			return false, objectReason
		end
		if configuration then
			configurationOverride = configuration
		end
		diagnostics.authoringOnlyMismatches, diagnostics.runtimePropertyFailures = {}, {}
		-- Resolve conflicts before any mutation; no empty or partial face mapping is written.
		for className, object in objects do
			if object == false then
				local created = Instance.new(className)
				created.Name, created.Parent = candidate.OwnedNames[className], root
				objects[className] = created
			end
		end
		root:SetAttribute(TOKEN_ATTRIBUTE, nil)
		removeEventTint(nil)
		for property, value in candidate.Lighting do
			local readable, actual = pcall(readLighting, property)
			if not readable then
				table.insert(diagnostics.runtimePropertyFailures, "Lighting." .. property .. ":" .. tostring(actual))
			elseif actual ~= value then
				if AUTHORING_ONLY_LIGHTING[property] and context.authoring ~= true then
					diagnostics.authoringOnlyMismatches[property] = {
						expected = tostring(value),
						actual = tostring(actual),
						action = "Persist in Edit; normal client skips restricted write",
					}
				else
					local writable, writeReason = pcall(writeLighting, property, value)
					if writable then
						diagnostics.propertyWrites += 1
					else
						table.insert(
							diagnostics.runtimePropertyFailures,
							"Lighting." .. property .. ":" .. tostring(writeReason)
						)
					end
				end
			end
		end
		local sky = objects.Sky
		if candidate.SkyMode == "RobloxDefault" then
			for _, property in STOCK_SKY_PROPERTIES do
				setProperty(sky, property, stockSkyValues[property], table.find(FACE_PROPERTIES, property) ~= nil)
			end
		else
			for _, property in FACE_PROPERTIES do
				setProperty(sky, property, candidate.Faces[property], true)
			end
			setProperty(sky, "SkyboxOrientation", candidate.SkyboxOrientation)
			if candidate.SkySettings then
				for property, value in pairs(candidate.SkySettings) do
					setProperty(sky, property, value)
				end
			end
		end
		for className, properties in SCHEMAS do
			for _, property in properties do
				setProperty(
					objects[className],
					property,
					if className == "BloomEffect"
							and property == "Enabled"
							and reducedEffects
						then false
						else candidate[className][property]
				)
			end
		end
		if next(diagnostics.authoringOnlyMismatches) or #diagnostics.runtimePropertyFailures > 0 then
			diagnostics.lastApplicationReason = "BASELINE_PROPERTY_MISMATCH_REQUIRES_AUTHORING_OR_RUNTIME_SUPPORT"
			return false, diagnostics.lastApplicationReason
		end
		root:SetAttribute(VERSION_ATTRIBUTE, candidate.Version)
		diagnostics.applies += 1
		diagnostics.applicationReady, diagnostics.lastApplicationReason = true, nil
		return true
	end
	function api.BeginEvent(overrides: any): (string?, string?)
		if type(overrides) ~= "table" then
			return nil, "EVENT_OVERRIDES_REQUIRED"
		end
		for className, values in overrides do
			if (className ~= "Atmosphere" and className ~= "ColorCorrectionEffect") or type(values) ~= "table" then
				return nil, "UNSUPPORTED_EVENT_LAYER"
			end
			for property, value in values do
				if not allowedProperty(className, property) or not validProperty(property, value) then
					return nil, "INVALID_EVENT_PROPERTY:" .. property
				end
			end
		end
		local applied, reason = api.ApplyBaseline()
		if not applied then
			return nil, reason
		end
		local configuration = currentConfiguration()
		local token = context.makeToken()
		root:SetAttribute(TOKEN_ATTRIBUTE, token)
		local atmosphere = ownedObject("Atmosphere", configuration.OwnedNames.Atmosphere)
		if atmosphere and type(overrides.Atmosphere) == "table" then
			for _, property in SCHEMAS.Atmosphere do
				if overrides.Atmosphere[property] ~= nil then
					setProperty(atmosphere, property, overrides.Atmosphere[property])
				end
			end
		end
		if type(overrides.ColorCorrectionEffect) == "table" then
			local tint = Instance.new("ColorCorrectionEffect")
			tint.Name = EVENT_NAME
			tint:SetAttribute(EVENT_ATTRIBUTE, true)
			tint:SetAttribute(TOKEN_ATTRIBUTE, token)
			for _, property in SCHEMAS.ColorCorrectionEffect do
				if overrides.ColorCorrectionEffect[property] ~= nil then
					tint[property] = overrides.ColorCorrectionEffect[property]
				end
			end
			tint.Parent = root
		end
		diagnostics.eventClaims += 1
		return token
	end
	function api.EndEvent(token: string?): (boolean, string?)
		if token == nil or root:GetAttribute(TOKEN_ATTRIBUTE) ~= token then
			if token then
				removeEventTint(token)
			end
			diagnostics.staleReleases += 1
			return false, "STALE_EVENT_OWNER"
		end
		-- Reread the current descriptor; never restore a pre-event custom-sky snapshot.
		return api.ApplyBaseline()
	end
	function api.SetReducedEffects(value)
		reducedEffects = value == true
		local cfg = currentConfiguration()
		local bloom = root:FindFirstChild(cfg.OwnedNames.BloomEffect)
		if bloom and bloom:IsA("BloomEffect") then
			bloom.Enabled = cfg.BloomEffect.Enabled and not reducedEffects
		end
	end
	function api.GetStatus(): (boolean, string?)
		local configuration = currentConfiguration()
		local valid, reason = validate(configuration)
		if not valid then
			return false, reason
		end
		if not diagnostics.applicationReady or root:GetAttribute(VERSION_ATTRIBUTE) ~= configuration.Version then
			return false, diagnostics.lastApplicationReason or "APPROVED_BASELINE_NOT_APPLIED"
		end
		return true
	end
	function api.GetBaselineValues(className: string)
		local configuration = currentConfiguration()
		if not validate(configuration) or (className ~= "Lighting" and SCHEMAS[className] == nil) then
			return nil
		end
		return table.clone(configuration[className])
	end
	function api.GetDiagnostics()
		local result = table.clone(diagnostics)
		local configuration = currentConfiguration()
		result.configurationReady, result.pendingReason = validate(configuration)
		result.skyMode = configuration.SkyMode or "Custom"
		result.assetReferencesInstalled = configuration.AssetReferencesInstalled == true
		result.normalClientTextureFetchVerified = configuration.NormalClientTextureFetchVerified == true
		result.baselineVersion = root:GetAttribute(VERSION_ATTRIBUTE)
		result.activeEventToken = root:GetAttribute(TOKEN_ATTRIBUTE)
		result.objects = #root:GetChildren()
		return result
	end
	return api
end
local default = createOwner({
	root = Lighting,
	authoring = RunService:IsStudio() and not RunService:IsRunning(),
	configurationProvider = function()
		return Configuration
	end,
	readLighting = function(property)
		return Lighting[property]
	end,
	writeLighting = function(property, value)
		Lighting[property] = value
	end,
	makeToken = function()
		return HttpService:GenerateGUID(false)
	end,
})
Owner.SetReducedEffects = default.SetReducedEffects
Owner.ApplyBaseline = default.ApplyBaseline
Owner.BeginEvent = default.BeginEvent
Owner.EndEvent = default.EndEvent
Owner.GetStatus = default.GetStatus
Owner.GetBaselineValues = default.GetBaselineValues
Owner.GetDiagnostics = default.GetDiagnostics
-- Isolated native QA owns a Folder and a lighting-property adapter, never Lighting.
function Owner.CreateForTesting(context: any)
	assert(
		RunService:IsStudio() and context.root ~= Lighting and context.root:IsA("Folder"),
		"Isolated Studio fixture only"
	)
	return createOwner(context)
end
return Owner
