--!strict
-- TerrainRedesign (V5) switch. The V5 world is the only map (owner, 10 Nov 2026). The saved place
-- stores it in ServerStorage.TerrainRedesign (Folder "World" + TerrainRegions). The legacy
-- inner walls, shells and region art were deleted from the place (10 Nov 2026), so the archive steps
-- below normally find nothing; they remain as a guard for older place versions.
--
-- Apply (every server start, before WorldVisualRepair): archives the legacy wall geometry
-- under ServerStorage.LegacyMap (never deleted), hides the floor slabs (they stay in place as the
-- authoritative region/spawn footprints), pastes the stored terrain and parents the World.
-- Revert restores everything; Studio Edit previews use Apply/Revert in pairs.
local ServerStorage = game:GetService("ServerStorage")

local Switch = {}

local LEGACY_FOLDERS = { "GateApertureClosures", "RegionWalls" }
local WALL_PROTOTYPES = { CliffRun = true, GateLintel = true }
-- Outer map-edge runs stay (CP-D's island edge + sea mist replace them). Where a rebuilt region's
-- island rim stands in front of them, their visuals turn transparent (hidesLegacy).
local PERIMETER_RUNS =
	{ EV2_Run_01 = true, EV2_Run_02 = true, EV2_Run_03 = true, EV2_Run_04 = true }
local function runKey(name: string): string
	return string.match(name, "^(EV2_Run_%d+)") or name
end
local FLOOR_ATTRS = { "Transparency", "CanCollide", "CanQuery", "CastShadow" }
-- Below the pool and brook beds (terrain water renders at about -2 over a -8 bed), so it never covers
-- water; still fills the distance before terrain streams in.
local BASEPLATE_TOP = -9
-- Base cart ramps were authored for the legacy floor (toe at y = 0.05). The V5 ground is about
-- -0.48, which leaves a half-stud lip that stops a returning cart dead. Each ramp wedge is deepened
-- so its toe sits just under the terrain while its top stays level with the cart pad.
local RAMP_TOE_Y = -0.55
local BASEPLATE_COLOUR = "#2FBF5A" -- V4 WatermelonGreen: reads as distant ground before terrain streams
local REGION_FOLDERS =
	{ "Camp", "Forest", "Beach", "Swamp", "Jungle", "Arctic", "Volcano", "Glitch Zone" }

local function store(): Folder?
	return ServerStorage:FindFirstChild("TerrainRedesign") :: Folder?
end

local function legacyRoot(): Folder
	local root = ServerStorage:FindFirstChild("LegacyMap") :: Folder?
	if not root then
		local folder = Instance.new("Folder")
		folder.Name = "LegacyMap"
		folder.Parent = ServerStorage
		root = folder
	end
	return root :: Folder
end

local function archive(instance: Instance, group: string)
	if not instance.Parent then
		return
	end
	instance:SetAttribute("LegacyMapParent", instance.Parent:GetFullName())
	instance:SetAttribute("LegacyMapGroup", group)
	instance.Parent = legacyRoot()
end

-- Rebuilt regions replace their EV2 dressing and first-session props (declared by region data).
-- Region data is static, so it is read once. Each module is a large generated table; yielding
-- between them resets Roblox's script-timeout clock, which a long unyielding server boot can
-- otherwise exhaust on a slow machine. The yield is skipped where yielding is not allowed.
local rebuiltCache: { [string]: any }? = nil
local function rebuiltRegions(): { [string]: any }
	if rebuiltCache then
		return rebuiltCache
	end
	local result = {}
	local config = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	local regions = config
		and config:FindFirstChild("Config")
		and config.Config:FindFirstChild("TerrainRegions")
	if not regions then
		return result
	end
	for _, module in regions:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, data = pcall(require, module)
			if ok and type(data) == "table" and data.replacesLegacy then
				result[data.key] = {
					prefixes = data.replacesLegacy,
					hides = data.hidesLegacy or {},
					folder = data.floorFolder or data.key,
					floors = { data.floorFolder or data.key },
				}
			end
			if coroutine.isyieldable() then
				task.wait()
			end
		end
	end
	rebuiltCache = result
	return result
end

local function inFloors(map: Instance, folderName: string, position: Vector3): boolean
	local folder = map:FindFirstChild(folderName)
	if not folder then
		return false
	end
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local p = part.CFrame:PointToObjectSpace(position)
			if math.abs(p.X) <= part.Size.X / 2 and math.abs(p.Z) <= part.Size.Z / 2 then
				return true
			end
		end
	end
	return false
end

-- Island rim: the perimeter shells and cliff art a rebuilt region's rim stands in front of only turn
-- transparent. Their invisible colliders, CanCollide and CanQuery are untouched, so the map boundary
-- is exactly as before. Idempotent; Revert restores LegacyRimTransparency.
local function hidePart(part: Instance)
	if
		part:IsA("BasePart")
		and part.Transparency < 1
		and part:GetAttribute("LegacyRimTransparency") == nil
	then
		part:SetAttribute("LegacyRimTransparency", part.Transparency)
		part.Transparency = 1
	end
end

local function rimHides(rebuilt: { [string]: any }): { [string]: boolean }
	local hides = {}
	for _, entry in rebuilt do
		for _, name in entry.hides do
			hides[name] = true
		end
	end
	return hides
end

local function hideRimCovered(map: Instance, rebuilt: { [string]: any })
	local hides = rimHides(rebuilt)
	for _, folderName in { "NavigationShells", "EnvironmentArt_V2" } do
		local folder = map:FindFirstChild(folderName)
		for _, model in if folder then folder:GetChildren() else {} do
			if hides[model.Name] then
				for _, part in model:GetDescendants() do
					hidePart(part)
				end
			end
		end
	end
end

function Switch.IsAvailable(): boolean
	local s = store()
	return s ~= nil and s:FindFirstChild("World") ~= nil
end

-- Before WorldVisualRepair/FirstSessionWorldArt run.
function Switch.Apply(map: Instance): (boolean, string?)
	local s = store()
	if not s or not s:FindFirstChild("World") then
		return false, "TerrainRedesign store missing"
	end
	if workspace:GetAttribute("TerrainRedesignActive") then
		return true, nil
	end
	for _, name in LEGACY_FOLDERS do
		local folder = map:FindFirstChild(name)
		if folder then
			archive(folder, "Walls")
		end
	end
	local shells = map:FindFirstChild("NavigationShells")
	for _, shell in if shells then shells:GetChildren() else {} do
		if not PERIMETER_RUNS[runKey(shell.Name)] then
			archive(shell, "Walls")
		end
	end
	local art = map:FindFirstChild("EnvironmentArt_V2")
	local rebuilt = rebuiltRegions()
	if art then
		for _, model in art:GetChildren() do
			if WALL_PROTOTYPES[model:GetAttribute("PrototypeId") :: any] then
				if not PERIMETER_RUNS[runKey(model.Name)] then
					archive(model, "Walls")
				end
			else
				for _, entry in rebuilt do
					for _, prefix in entry.prefixes do
						if string.sub(model.Name, 1, #prefix) == prefix then
							archive(model, "RebuiltRegionArt")
						end
					end
				end
			end
		end
	end
	hideRimCovered(map, rebuilt)
	-- Floors stay as invisible authoritative footprints (RegionGateDescriptors, RegionSpawnCatalog).
	-- Only regions that have V5 terrain lose their visible slab; the rest keep walking on it.
	local hidden = {}
	for _, entry in rebuilt do
		for _, folderName in (entry :: any).floors do
			hidden[folderName] = true
		end
	end
	for _, folderName in REGION_FOLDERS do
		local folder = if hidden[folderName] then map:FindFirstChild(folderName) else nil
		for _, part in if folder then folder:GetChildren() else {} do
			if part:IsA("BasePart") and part:GetAttribute("LayoutRole") == "Floor" then
				for _, key in FLOOR_ATTRS do
					part:SetAttribute("LegacyFloor" .. key, (part :: any)[key])
				end
				part.Transparency, part.CanCollide, part.CanQuery, part.CastShadow =
					1, false, false, false
			end
		end
	end
	-- The legacy Baseplate (top y = 0) sits above the V5 ground surface (-0.5). It is lowered to a top
	-- of BASEPLATE_TOP and tinted, so it hides under streamed terrain but still fills the distance (and
	-- catches anything) where a client has not streamed terrain in yet. Fully restorable.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if
		baseplate
		and baseplate:IsA("BasePart")
		and baseplate:GetAttribute("LegacyBaseplateCFrame") == nil
	then
		baseplate:SetAttribute("LegacyBaseplateCFrame", baseplate.CFrame)
		baseplate:SetAttribute("LegacyBaseplateColor", baseplate.Color)
		local lift = BASEPLATE_TOP - (baseplate.Position.Y + baseplate.Size.Y / 2)
		baseplate.CFrame = baseplate.CFrame + Vector3.new(0, lift, 0)
		baseplate.Color = Color3.fromHex(BASEPLATE_COLOUR)
	end
	local bases = map:FindFirstChild("PlayerBasePatches")
	for _, base in if bases then bases:GetChildren() else {} do
		local ramp = base:FindFirstChild("CartRamp")
		if ramp and ramp:IsA("BasePart") and ramp:GetAttribute("LegacyRampCFrame") == nil then
			local top = ramp.Position.Y + ramp.Size.Y / 2
			local height = top - RAMP_TOE_Y
			-- Upright ramps only; anything else keeps its authored shape.
			if ramp.CFrame.UpVector.Y > 0.999 and height > ramp.Size.Y then
				ramp:SetAttribute("LegacyRampCFrame", ramp.CFrame)
				ramp:SetAttribute("LegacyRampSize", ramp.Size)
				local drop = (height - ramp.Size.Y) / 2
				ramp.Size = Vector3.new(ramp.Size.X, height, ramp.Size.Z)
				ramp.CFrame = ramp.CFrame - Vector3.new(0, drop, 0)
			end
		end
	end
	local terrain = workspace.Terrain
	for _, region in s:GetChildren() do
		if region:IsA("TerrainRegion") then
			local corner = region:GetAttribute("CornerCell")
			if typeof(corner) == "Vector3" then
				terrain:PasteRegion(region, Vector3int16.new(corner.X, corner.Y, corner.Z), true)
				task.wait()
			end
		end
	end
	for materialName, hex in s:GetAttributes() :: any do
		local ok, material = pcall(function()
			return (Enum.Material :: any)[string.match(materialName, "^Colour_(.+)$") or ""]
		end)
		if ok and material and type(hex) == "string" then
			terrain:SetMaterialColor(material, Color3.fromHex(hex))
		end
	end
	local water = s:GetAttribute("WaterColour")
	if type(water) == "string" then
		terrain.WaterColor = Color3.fromHex(water)
	end
	terrain.WaterWaveSize = 0.05
	terrain.WaterReflectance = 0
	pcall(function()
		(terrain :: any).Decoration = false
	end)
	local world = s:FindFirstChild("World") :: Instance
	world:SetAttribute("TerrainRedesignStored", true)
	-- Static world art, like the skyline markers: RegionVisibilityController otherwise hides every
	-- non-map instance outside the player's current unlocked region (props, gates and landmarks alike).
	world:SetAttribute("GlobalNavigationFacade", true)
	world.Parent = workspace
	workspace:SetAttribute("TerrainRedesignActive", true)
	workspace:SetAttribute(
		"TerrainRedesignRebuilt",
		table.concat(
			(function()
				local keys = {}
				for key in rebuilt do
					table.insert(keys, key)
				end
				table.sort(keys)
				return keys
			end)(),
			","
		)
	)
	return true, nil
end

local GATE_DRESSING = {
	SupportLeft = true,
	SupportRight = true,
	Lintel = true,
	BoulderFootLeft = true,
	BoulderFootRight = true,
}

-- Gates keep their models, prompts, DoorPresentation and Sign (GateAccessPresentation still binds);
-- only the old frame dressing is hidden (collision kept) because the V5 voxel arch replaces it.
function Switch.HideLegacyGateDressing(map: Instance)
	local gates = map:FindFirstChild("ProgressionGates")
	for _, gate in if gates then gates:GetChildren() else {} do
		for _, item in gate:GetDescendants() do
			if
				item:IsA("BasePart")
				and GATE_DRESSING[item.Name]
				and item:GetAttribute("LegacyGateTransparency") == nil
			then
				item:SetAttribute("LegacyGateTransparency", item.Transparency)
				item.Transparency = 1
			end
		end
		local landmarks = gate:FindFirstChild("RouteLandmarks")
		if landmarks and landmarks:GetAttribute("LegacyGateParent") == nil then
			archive(landmarks, "GateDressing")
		end
	end
end

-- After WorldVisualRepair + FirstSessionWorldArt: hide their skyline marker and prop clusters inside
-- rebuilt regions, and the old gate frame dressing.
local rimWatch: RBXScriptConnection? = nil

function Switch.ApplyAfterFirstSessionArt(map: Instance)
	if not workspace:GetAttribute("TerrainRedesignActive") then
		return
	end
	Switch.HideLegacyGateDressing(map)
	-- WorldVisualRepair rebuilds the perimeter shells (Core + FacadeCrest) at start and whenever their
	-- source changes, so the rim hide runs again now and for any shell part added later.
	local rebuiltNow = rebuiltRegions()
	hideRimCovered(map, rebuiltNow)
	local shells = map:FindFirstChild("NavigationShells")
	if shells and not rimWatch then
		local hides = rimHides(rebuiltNow)
		rimWatch = shells.DescendantAdded:Connect(function(part)
			local run = part.Parent
			while run and run.Parent ~= shells do
				run = run.Parent
			end
			if run and hides[run.Name] then
				hidePart(part)
			end
		end)
	end
	local root = map:FindFirstChild("FirstSessionArt")
	if not root then
		return
	end
	for key, entry in rebuiltRegions() do
		local markers = root:FindFirstChild("SkylineMarkers")
		local marker = markers and markers:FindFirstChild("Skyline_" .. key)
		if marker then
			archive(marker, "RebuiltRegionArt")
		end
		local clusters = root:FindFirstChild("PropClusters")
		for _, model in if clusters then clusters:GetChildren() else {} do
			if
				model:IsA("Model")
				and inFloors(map, (entry :: any).folder, model:GetPivot().Position)
			then
				archive(model, "RebuiltRegionArt")
			end
		end
	end
end

-- Edit-mode previews only (the server never reverts).
function Switch.Revert(map: Instance)
	local s = store()
	local world = workspace:FindFirstChild("World")
	if world and world:GetAttribute("TerrainRedesignStored") and s then
		world.Parent = s
	end
	if rimWatch then
		rimWatch:Disconnect()
		rimWatch = nil
	end
	workspace.Terrain:Clear()
	local legacy = ServerStorage:FindFirstChild("LegacyMap")
	for _, item in if legacy then legacy:GetChildren() else {} do
		local path = item:GetAttribute("LegacyMapParent")
		local parent: Instance? = game
		for segment in string.gmatch(tostring(path), "[^%.]+") do
			parent = parent and parent:FindFirstChild(segment)
		end
		if parent then
			item.Parent = parent
			item:SetAttribute("LegacyMapParent", nil)
			item:SetAttribute("LegacyMapGroup", nil)
		end
	end
	if legacy and #legacy:GetChildren() == 0 then
		legacy:Destroy()
	end
	for _, folderName in REGION_FOLDERS do
		local folder = map:FindFirstChild(folderName)
		for _, part in if folder then folder:GetChildren() else {} do
			if part:IsA("BasePart") and part:GetAttribute("LegacyFloorTransparency") ~= nil then
				for _, key in FLOOR_ATTRS do
					(part :: any)[key] = part:GetAttribute("LegacyFloor" .. key)
					part:SetAttribute("LegacyFloor" .. key, nil)
				end
			end
		end
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if
		baseplate
		and baseplate:IsA("BasePart")
		and baseplate:GetAttribute("LegacyBaseplateCFrame") ~= nil
	then
		baseplate.CFrame = baseplate:GetAttribute("LegacyBaseplateCFrame") :: CFrame
		baseplate.Color = baseplate:GetAttribute("LegacyBaseplateColor") :: Color3
		baseplate:SetAttribute("LegacyBaseplateCFrame", nil)
		baseplate:SetAttribute("LegacyBaseplateColor", nil)
	end
	local bases = map:FindFirstChild("PlayerBasePatches")
	for _, base in if bases then bases:GetChildren() else {} do
		local ramp = base:FindFirstChild("CartRamp")
		if ramp and ramp:IsA("BasePart") and ramp:GetAttribute("LegacyRampCFrame") ~= nil then
			ramp.Size = ramp:GetAttribute("LegacyRampSize") :: Vector3
			ramp.CFrame = ramp:GetAttribute("LegacyRampCFrame") :: CFrame
			ramp:SetAttribute("LegacyRampCFrame", nil)
			ramp:SetAttribute("LegacyRampSize", nil)
		end
	end
	for _, folderName in { "NavigationShells", "EnvironmentArt_V2" } do
		local folder = map:FindFirstChild(folderName)
		for _, item in if folder then folder:GetDescendants() else {} do
			local authored = item:GetAttribute("LegacyRimTransparency")
			if authored ~= nil and item:IsA("BasePart") then
				item.Transparency = authored
				item:SetAttribute("LegacyRimTransparency", nil)
			end
		end
	end
	local gates = map:FindFirstChild("ProgressionGates")
	for _, item in if gates then gates:GetDescendants() else {} do
		local authored = item:GetAttribute("LegacyGateTransparency")
		if authored ~= nil and item:IsA("BasePart") then
			item.Transparency = authored
			item:SetAttribute("LegacyGateTransparency", nil)
		end
	end
	workspace:SetAttribute("TerrainRedesignActive", nil)
	workspace:SetAttribute("TerrainRedesignRebuilt", nil)
end

return Switch
