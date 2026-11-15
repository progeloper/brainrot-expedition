--!strict
-- Lookup for Voxel V4 species data, installed native templates and V4 presentation
-- measurements. Presentation only: the server's authority proxy, hitbox and
-- interaction bounds keep using the legacy templates and are never routed here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Flags = require(Shared.Config.FeatureFlags)

local Registry = {}
local dataCache: { [string]: any } = {}
local measureCache: { [string]: any } = {}

local function dataFolder(): Instance?
	local config = Shared:FindFirstChild("Config")
	return config and config:FindFirstChild("VoxelCreatures")
end

-- Config.VoxelCreaturesV4Enabled swaps the whole layer. In Studio only, the
-- ReplicatedStorage attribute VoxelCreaturesV4Preview enables isolated previews.
function Registry.Enabled(): boolean
	if Flags.VoxelCreaturesV4Enabled == true then
		return true
	end
	return RunService:IsStudio()
		and ReplicatedStorage:GetAttribute("VoxelCreaturesV4Preview") == true
end

function Registry.GetData(species: string): any?
	local cached = dataCache[species]
	if cached ~= nil then
		return cached or nil
	end
	local folder = dataFolder()
	local module = folder and folder:FindFirstChild(species)
	local data = if module and module:IsA("ModuleScript") then require(module) :: any else nil
	dataCache[species] = data or false
	return data
end

function Registry.ListSpecies(): { string }
	local result = {}
	local folder = dataFolder()
	if folder then
		for _, module in folder:GetChildren() do
			if module:IsA("ModuleScript") then
				table.insert(result, module.Name)
			end
		end
	end
	table.sort(result)
	return result
end

function Registry.GetTemplate(species: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("CodeAssets")
	local folder = assets and assets:FindFirstChild("CreaturesV4")
	local template = folder and folder:FindFirstChild(species .. "_V4")
	if
		template
		and template:IsA("Model")
		and template:GetAttribute("VoxelCreatureVersion") == 4
	then
		return template
	end
	return nil
end

-- Template used for client visuals (every role) when the layer is enabled.
function Registry.GetActiveTemplate(species: string): Model?
	if not Registry.Enabled() then
		return nil
	end
	return Registry.GetTemplate(species)
end

function Registry.IsVoxelModel(model: Instance): boolean
	return model:GetAttribute("VoxelCreatureVersion") == 4
end

function Registry.Measure(species: string): any?
	local cached = measureCache[species]
	if cached then
		return cached
	end
	local data = Registry.GetData(species)
	if not data then
		return nil
	end
	local Builder = require(Shared.Utility.VoxelCreatureBuilder)
	local measured = Builder.Measure(data)
	measureCache[species] = measured
	return measured
end

-- Species-level measurement for layout consumers (cargo rows, base displays):
-- V4 when the layer is enabled and the species has an installed V4 template.
function Registry.SpeciesMeasurement(species: any, legacy: any): any
	if type(species) == "string" and Registry.Enabled() and Registry.GetTemplate(species) then
		return Registry.Measure(species) or legacy
	end
	return legacy
end

-- Model-level measurement: V4 models always use V4 data, legacy models legacy data.
local scaledCache: { [any]: { [number]: any } } = setmetatable({}, { __mode = "k" }) :: any

-- Playtest Fixes size ladder: a model scaled off the shared 6.7-stud height carries
-- PlaytestSizeRatio; its normalized (placement / name tag / shadow / "?" anchor) measurements follow.
-- Raw fields (s0, ymin, ymax, ...) are untouched, so normalization itself is unaffected.
local function scaled(measurement: any, ratio: any): any
	if
		type(measurement) ~= "table"
		or type(ratio) ~= "number"
		or ratio <= 0
		or math.abs(ratio - 1) < 1e-4
	then
		return measurement
	end
	local byRatio = scaledCache[measurement]
	if not byRatio then
		byRatio = {}
		scaledCache[measurement] = byRatio
	end
	local hit = byRatio[ratio]
	if hit then
		return hit
	end
	local copy = table.clone(measurement)
	for _, key in { "normalizedSize", "normalizedTop", "groundPoint" } do
		if typeof(copy[key]) == "Vector3" then
			copy[key] = copy[key] * ratio
		end
	end
	byRatio[ratio] = copy
	return copy
end

function Registry.ModelMeasurement(model: Instance, legacy: any): any
	local ratio = model:GetAttribute("PlaytestSizeRatio")
	if Registry.IsVoxelModel(model) then
		local species = model:GetAttribute("VoxelSpeciesId")
		return if type(species) == "string" then scaled(Registry.Measure(species), ratio) else nil
	end
	return scaled(legacy, ratio)
end

return table.freeze(Registry)
