--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialPolicy = require(ReplicatedStorage.Shared.Utility.EnvironmentStudMaterialPolicy)

local CartGreyboxConfigValidator =
	require(ReplicatedStorage.Shared.Validation.CartGreyboxConfigValidator)

type AnyTable = { [any]: any }

export type BuildResult = {
	RouteFolder: Folder,
	SpawnMarkers: { BasePart },
	SpawnIdsBySection: { [string]: { string } },
	StartCFramesBySection: { [string]: CFrame },
}

local CartGreyboxRouteBuilder = {}

local FLOOR_COLOR = Color3.fromRGB(93, 98, 110)
local OBSTACLE_COLOR = Color3.fromRGB(207, 115, 74)
local ROUTE_ACCENT_COLOR = Color3.fromRGB(94, 173, 203)

local function cframeIsFinite(value: CFrame): boolean
	for _, component in { value:GetComponents() } do
		if component ~= component or math.abs(component) == math.huge then
			return false
		end
	end

	return true
end

local function createPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	canCollide: boolean?,
	transparency: number?
): Part
	local part = Instance.new("Part")

	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = canCollide ~= false
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = transparency or 0
	MaterialPolicy.Apply(part, Enum.Material.SmoothPlastic)
	part.Parent = parent

	return part
end

local function createLabel(parent: Instance, baseCFrame: CFrame, text: string)
	local anchor = createPart(
		parent,
		"SectionLabelAnchor",
		Vector3.new(1, 1, 1),
		baseCFrame * CFrame.new(0, 8, 28),
		ROUTE_ACCENT_COLOR,
		false,
		1
	)

	local billboard = Instance.new("BillboardGui")

	billboard.Name = "SectionLabel"
	billboard.Size = UDim2.fromOffset(320, 48)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 180
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")

	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 31)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(240, 244, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = billboard
end

local function createWall(
	parent: Instance,
	name: string,
	baseCFrame: CFrame,
	localPosition: Vector3,
	size: Vector3
)
	createPart(parent, name, size, baseCFrame * CFrame.new(localPosition), OBSTACLE_COLOR)
end

local function createSectionGeometry(
	sectionModel: Model,
	section: AnyTable,
	baseCFrame: CFrame,
	floorThickness: number
)
	local footprint = section.Footprint :: Vector2

	createPart(
		sectionModel,
		"Floor",
		Vector3.new(footprint.X, floorThickness, footprint.Y),
		baseCFrame * CFrame.new(0, -floorThickness * 0.5, 0),
		FLOOR_COLOR
	)

	local kind = section.Kind :: string

	if kind == "RampUp" or kind == "RampDown" then
		-- Every section starts the cart at local +Z, facing local -Z. A positive
		-- X rotation raises that forward direction; a negative rotation lowers it.
		local angle = if kind == "RampUp" then math.rad(7) else math.rad(-7)

		createPart(
			sectionModel,
			"GentleRamp",
			Vector3.new(footprint.X * 0.7, 1, footprint.Y * 0.72),
			baseCFrame * CFrame.new(0, 2.2, -2) * CFrame.Angles(angle, 0, 0),
			ROUTE_ACCENT_COLOR
		)
	elseif kind == "SideSlope" then
		createPart(
			sectionModel,
			"SideSlope",
			Vector3.new(footprint.X * 0.72, 1, footprint.Y * 0.75),
			baseCFrame * CFrame.new(0, 2.4, -2) * CFrame.Angles(0, 0, math.rad(7)),
			ROUTE_ACCENT_COLOR
		)
	elseif kind == "Crest" then
		createPart(
			sectionModel,
			"CrestApproach",
			Vector3.new(footprint.X * 0.7, 1, footprint.Y * 0.42),
			baseCFrame * CFrame.new(0, 1.6, 9) * CFrame.Angles(math.rad(7), 0, 0),
			ROUTE_ACCENT_COLOR
		)
		createPart(
			sectionModel,
			"CrestDeparture",
			Vector3.new(footprint.X * 0.7, 1, footprint.Y * 0.42),
			baseCFrame * CFrame.new(0, 1.6, -9) * CFrame.Angles(math.rad(-7), 0, 0),
			ROUTE_ACCENT_COLOR
		)
	elseif kind == "Bumps" then
		for index, localZ in { 12, 4, -4, -12 } do
			createPart(
				sectionModel,
				string.format("Bump%d", index),
				Vector3.new(footprint.X * 0.7, 1, 2.5),
				baseCFrame * CFrame.new(0, 0.45, localZ),
				ROUTE_ACCENT_COLOR
			)
		end
	elseif kind == "Narrow" then
		createWall(
			sectionModel,
			"LeftWall",
			baseCFrame,
			Vector3.new(-9, 4, -2),
			Vector3.new(2, 8, footprint.Y * 0.78)
		)
		createWall(
			sectionModel,
			"RightWall",
			baseCFrame,
			Vector3.new(9, 4, -2),
			Vector3.new(2, 8, footprint.Y * 0.78)
		)
	elseif kind == "CameraWall" then
		createWall(
			sectionModel,
			"CameraWall",
			baseCFrame,
			Vector3.new(0, 8, 28),
			Vector3.new(42, 16, 2)
		)
	elseif kind == "CameraCorner" then
		createWall(
			sectionModel,
			"CameraRearWall",
			baseCFrame,
			Vector3.new(0, 8, 28),
			Vector3.new(42, 16, 2)
		)
		createWall(
			sectionModel,
			"CameraSideWall",
			baseCFrame,
			Vector3.new(20, 8, 10),
			Vector3.new(2, 16, 38)
		)
	elseif kind == "Collision" then
		createWall(
			sectionModel,
			"CollisionObstacle",
			baseCFrame,
			Vector3.new(0, 4, -7),
			Vector3.new(14, 8, 6)
		)
	elseif kind == "Tilt" then
		createPart(
			sectionModel,
			"TiltBlock",
			Vector3.new(18, 2, 14),
			baseCFrame * CFrame.new(0, 1.2, -5) * CFrame.Angles(0, 0, math.rad(12)),
			ROUTE_ACCENT_COLOR
		)
	elseif kind == "Stuck" then
		createWall(
			sectionModel,
			"StuckLeft",
			baseCFrame,
			Vector3.new(-8, 4, -5),
			Vector3.new(2, 8, 24)
		)
		createWall(
			sectionModel,
			"StuckRight",
			baseCFrame,
			Vector3.new(8, 4, -5),
			Vector3.new(2, 8, 24)
		)
		createWall(
			sectionModel,
			"StuckEnd",
			baseCFrame,
			Vector3.new(0, 4, -16),
			Vector3.new(18, 8, 2)
		)
	elseif kind == "Performance" then
		local spawnOffsets = section.SpawnOffsets :: { Vector3 }
		local barrierZ = -(footprint.Y * 0.5 - 8)

		for laneIndex, spawnOffset in spawnOffsets do
			local lane = createPart(
				sectionModel,
				string.format("PerformanceLane_%02d", laneIndex),
				Vector3.new(20, 0.08, footprint.Y - 12),
				baseCFrame * CFrame.new(spawnOffset.X, 0.04, -4),
				ROUTE_ACCENT_COLOR,
				false,
				0.35
			)

			lane.CanQuery = false

			createPart(
				sectionModel,
				string.format("PerformanceEndBarrier_%02d", laneIndex),
				Vector3.new(20, 6, 2),
				baseCFrame * CFrame.new(spawnOffset.X, 3, barrierZ),
				OBSTACLE_COLOR
			)
		end
	end

	createLabel(sectionModel, baseCFrame, string.format("%s — %s", section.Id, section.Label))
end

local function cleanup(result: BuildResult)
	for _, marker in result.SpawnMarkers do
		if marker.Parent ~= nil then
			marker:Destroy()
		end
	end

	if result.RouteFolder.Parent ~= nil then
		result.RouteFolder:Destroy()
	end

	table.clear(result.SpawnMarkers)
	table.clear(result.SpawnIdsBySection)
	table.clear(result.StartCFramesBySection)
end

function CartGreyboxRouteBuilder.Build(
	config: AnyTable,
	canonicalSpawnCFrame: CFrame,
	routeParent: Instance,
	spawnFolder: Folder
): (BuildResult?, string?)
	local validation = CartGreyboxConfigValidator.Validate(config)

	if not validation.IsValid then
		return nil, table.concat(validation.Errors, "; ")
	end

	if not cframeIsFinite(canonicalSpawnCFrame) then
		return nil, "canonical spawn CFrame must be finite"
	end

	if routeParent.Parent == nil and routeParent ~= game then
		return nil, "route parent must belong to a live hierarchy"
	end

	if routeParent:FindFirstChild(config.RouteFolderName) ~= nil then
		return nil, string.format("route folder %s already exists", config.RouteFolderName)
	end

	local markerNamesBySection: { { string } } = {}
	local spawnIdsBySection: { { string } } = {}
	local plannedSpawnIds: { [string]: boolean } = {}

	for index, section in config.Sections do
		local spawnOffsets = section.SpawnOffsets or { section.StartOffset }
		local markerNames: { string } = {}
		local spawnIds: { string } = {}

		for laneIndex = 1, #spawnOffsets do
			local hasMultipleLanes = #spawnOffsets > 1
			local markerName = if hasMultipleLanes
				then string.format("GreyboxSpawn_%02d_Lane_%d", index, laneIndex)
				else string.format("GreyboxSpawn_%02d", index)
			local baseSpawnId = config.SpawnIdPrefix .. section.Id
			local spawnId = if hasMultipleLanes
				then string.format("%s_LANE_%d", baseSpawnId, laneIndex)
				else baseSpawnId

			if spawnFolder:FindFirstChild(markerName) ~= nil then
				return nil, string.format("spawn marker %s already exists", markerName)
			end

			if plannedSpawnIds[spawnId] then
				return nil,
					string.format("SpawnId %s is duplicated by route configuration", spawnId)
			end

			for _, child in spawnFolder:GetChildren() do
				if child:GetAttribute("SpawnId") == spawnId then
					return nil, string.format("SpawnId %s already exists", spawnId)
				end
			end

			plannedSpawnIds[spawnId] = true
			markerNames[laneIndex] = markerName
			spawnIds[laneIndex] = spawnId
		end

		markerNamesBySection[index] = markerNames
		spawnIdsBySection[index] = spawnIds
	end

	local routeFolder = Instance.new("Folder")

	routeFolder.Name = config.RouteFolderName
	routeFolder:SetAttribute(config.OwnedAttribute, true)
	routeFolder.Parent = routeParent

	local result: BuildResult = {
		RouteFolder = routeFolder,
		SpawnMarkers = {},
		SpawnIdsBySection = {},
		StartCFramesBySection = {},
	}

	local buildSucceeded, buildError = pcall(function()
		local routeOrigin = canonicalSpawnCFrame * CFrame.new(config.RouteOffset)

		for index, section in config.Sections do
			local sectionBase = routeOrigin
				* CFrame.new(
					section.GridColumn * config.GridSpacing.X,
					0,
					section.GridRow * config.GridSpacing.Y
				)
			local startCFrame = sectionBase * CFrame.new(section.StartOffset)
			local sectionModel = Instance.new("Model")

			sectionModel.Name = section.Id
			sectionModel:SetAttribute(config.OwnedAttribute, true)
			sectionModel:SetAttribute(config.SectionIdAttribute, section.Id)
			sectionModel.Parent = routeFolder

			createSectionGeometry(sectionModel, section, sectionBase, config.FloorThickness)

			local spawnOffsets = section.SpawnOffsets or { section.StartOffset }
			local sectionSpawnIds: { string } = {}

			for laneIndex, spawnOffset in spawnOffsets do
				local spawnId = spawnIdsBySection[index][laneIndex]
				local marker = createPart(
					spawnFolder,
					markerNamesBySection[index][laneIndex],
					Vector3.new(4, 0.2, 4),
					sectionBase * CFrame.new(spawnOffset),
					ROUTE_ACCENT_COLOR,
					false,
					1
				)

				marker.CanQuery = false
				marker:SetAttribute("SpawnId", spawnId)
				marker:SetAttribute("CartId", config.CartId)
				marker:SetAttribute("Enabled", true)
				marker:SetAttribute("Priority", config.SpawnPriorityBase + index)
				marker:SetAttribute("DebugOnly", true)
				marker:SetAttribute(config.OwnedAttribute, true)
				marker:SetAttribute(config.SectionIdAttribute, section.Id)

				table.insert(result.SpawnMarkers, marker)
				table.insert(sectionSpawnIds, spawnId)
			end

			result.SpawnIdsBySection[section.Id] = sectionSpawnIds
			result.StartCFramesBySection[section.Id] = startCFrame
		end
	end)

	if not buildSucceeded then
		cleanup(result)

		return nil, string.format("route build failed: %s", tostring(buildError))
	end

	return result, nil
end

function CartGreyboxRouteBuilder.Destroy(result: BuildResult)
	cleanup(result)
end

return table.freeze(CartGreyboxRouteBuilder)
