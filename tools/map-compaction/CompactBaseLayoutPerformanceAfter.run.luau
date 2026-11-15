local Http=game:GetService("HttpService")
local Adapter=assert(loadstring([==[local ExpectedCurrent={Config=[[--!strict

local CompactMapGeometry = require(game:GetService("ReplicatedStorage").Shared.Utility.CompactMapGeometry)

-- The 36-by-32-stud footprint is a project visual estimate derived from the
-- compact reference layout, not an official published dimension.
local BaseLayoutConfig = {
	STANDARD_ROBLOX_PLAYER_HEIGHT_STUDS = 5.0,
	BRAINROT_TARGET_VISIBLE_HEIGHT_STUDS = 3.5,
	PLATFORM_DIAGONAL_STUDS = 3.0,
	PLATFORM_SIDE_STUDS = 3 / math.sqrt(2),

	BASE_FOOTPRINT_WIDTH_STUDS = 36,
	BASE_FOOTPRINT_DEPTH_STUDS = 32,
	BASE_WALL_HEIGHT_STUDS = 10,
	BASE_WALL_THICKNESS_STUDS = 1,
	PLATFORM_COUNT = 12,
	PLATFORMS_PER_SIDE = 6,
	PLATFORM_ROW_OFFSET_X = 7.25,
	PLATFORM_Z_CENTERS = table.freeze({ -11.25, -6.75, -2.25, 2.25, 6.75, 11.25 }),

	PLAQUE_INWARD_DEPTH_STUDS = 1.75,
	PLAQUE_TANGENTIAL_WIDTH_STUDS = 3.0,
	PLAQUE_HEIGHT_STUDS = 0.20,
	PLAQUE_PLATFORM_GAP_STUDS = 0.25,
	PLAQUE_VISIBLE_RISE_STUDS = 0.03,
	-- The visible plaque remains flush and non-colliding. This invisible vertical
	-- contact envelope reaches ordinary avatar feet, which rest above the floor.
	PLAQUE_TOUCH_HEIGHT_STUDS = 1.0,
	PLAQUE_TOUCH_COOLDOWN_SECONDS = 0.5,
}

-- Compact values are final evaluated locals; all original scale/economy constants remain unchanged.
function BaseLayoutConfig.GetGeometry(base: Model): any?
	return CompactMapGeometry.ResolveBase(base)
end

return table.freeze(BaseLayoutConfig)
]],Income=[[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config.BaseLayoutConfig)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local StaticMaterial = require(ReplicatedStorage.Shared.Utility.MapArtStaticMaterialPolicy)
local PlayerBaseSystem = require(script.Parent.PlayerBaseSystem)
local BaseStorageSystem = require(script.Parent.BaseStorageSystem)
local BrainrotIncomeSystem = require(script.Parent.BrainrotIncomeSystem)

local log = Logger.new("BaseIncomePlaqueSystem")
local PLAQUE_TAG = "BrainrotIncomePlaque"
local LAYOUT_CONTAINER_NAME = "Phase5DInterior"
local PLAQUE_CONTAINER_NAME = "IncomePlaques"
local TOUCH_SENSOR_NAME = "TouchSensor"
local AMOUNT_SURFACE_NAME = "AmountSurfaceGui"
local AMOUNT_LABEL_NAME = "AmountLabel"
local AMOUNT_STROKE_NAME = "AmountStroke"
local PLAQUE_WIDTH_STUDS = 3.5
local PLAQUE_THICKNESS_STUDS = 0.18
local PLAQUE_DEPTH_STUDS = 2.25
local PLAQUE_PLATFORM_GAP_STUDS = 0.55
local PLAQUE_FLOOR_CLEARANCE_STUDS = 0.02
local PLAQUE_SNAPSHOT_REFRESH_SECONDS = 1
local PILLAR_MANAGED_BY = "BaseIncomePlaqueSystem"
local PILLAR_ORIGINAL_WIDTH_STUDS = 1.25
local PILLAR_ORIGINAL_DEPTH_STUDS = 1.25
local PILLAR_WIDTH_STUDS = PILLAR_ORIGINAL_WIDTH_STUDS * 0.5
local PILLAR_DEPTH_STUDS = PILLAR_ORIGINAL_DEPTH_STUDS * 0.5
local PILLAR_MAX_SPACING_STUDS = 6
local ENTRANCE_CLEAR_WIDTH_STUDS = 10
local LEGACY_WALL_NAMES = table.freeze({ "LeftWall", "RightWall", "BackWall" })

local BaseIncomePlaqueSystem = {}
local started = false
local initialDependencies: any? = nil
local assignmentConnection: any? = nil
local unsubscribeStorage: (() -> ())? = nil
local snapshotConnection: RBXScriptConnection? = nil
local snapshotAccumulator = 0
local baseSystem: any = PlayerBaseSystem
local storageSystem: any = BaseStorageSystem
local incomeSystem: any = BrainrotIncomeSystem
local clock = function(): number
	return Workspace:GetServerTimeNow()
end
local getPlayerFromCharacter = function(character: Model): Player?
	return Players:GetPlayerFromCharacter(character)
end
local getPlayerByUserId = function(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end
local states: { [Model]: any } = {}
local plaqueBindings: { [BasePart]: any } = {}
local touchAttempts: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" })

local function getPlaqueName(platformId: number): string
	return "IncomePlaque_" .. tostring(platformId)
end

local function platformIdFromPart(platform: BasePart): number?
	local attribute = platform:GetAttribute("SlotIndex")
	if type(attribute) == "number" and attribute % 1 == 0 then
		return attribute
	end
	return tonumber(platform.Name:match("^Slot_(%d+)$"))
end

local function baseRootCFrame(base: Model): CFrame
	local saved = base:GetAttribute("Phase5DLayoutPivot")
	if typeof(saved) == "CFrame" then
		return saved
	end
	local root = base:GetPivot()
	base:SetAttribute("Phase5DLayoutPivot", root)
	return root
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), name .. " must be a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensurePart(base: Model, container: Folder, name: string): (BasePart, boolean)
	local existing = base:FindFirstChild(name) or container:FindFirstChild(name)
	if existing then
		assert(existing:IsA("BasePart"), name .. " must be a BasePart")
		return existing, false
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Parent = container
	return part, true
end

local function configureStructuralPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	StaticMaterial.Apply(part, Enum.Material.SmoothPlastic)
	part.Color = Color3.fromRGB(91, 98, 104)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function platformTopLocalY(root: CFrame, platform: BasePart): number
	return root:PointToObjectSpace(platform.Position).Y + platform.Size.Y / 2
end

local function entranceSign(base: Model, root: CFrame): number
	for _, name in { "CartSpawn", "PlayerSpawn" } do
		local marker = base:FindFirstChild(name)
		if marker and marker:IsA("BasePart") then
			local localZ = root:PointToObjectSpace(marker.Position).Z
			if math.abs(localZ) > 0.01 then
				return if localZ > 0 then 1 else -1
			end
		end
	end
	return -1
end

type StructuralStyle = {
	PostWidth: number?,
	PostDepth: number?,
	Color: Color3,
	Material: Enum.Material,
	MaterialVariant: string,
	EffectivePhysicalProperties: PhysicalProperties,
	CollisionGroup: string,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
}

local function captureStructuralStyle(part: BasePart): StructuralStyle
	return {
		Color = part.Color,
		Material = part.Material,
		MaterialVariant = part.MaterialVariant,
		EffectivePhysicalProperties = part.CurrentPhysicalProperties,
		CollisionGroup = part.CollisionGroup,
		CanCollide = part.CanCollide,
		CanTouch = part.CanTouch,
		CanQuery = part.CanQuery,
	}
end

local function legacyWall(base: Model, container: Folder, name: string): BasePart?
	local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
	return if candidate and candidate:IsA("BasePart") then candidate else nil
end

local function removeLegacyWalls(base: Model, container: Folder)
	for _, name in LEGACY_WALL_NAMES do
		local direct = base:FindFirstChild(name)
		if direct and direct:IsA("BasePart") then
			direct:Destroy()
		end
		local generated = container:FindFirstChild(name)
		if generated and generated:IsA("BasePart") then
			generated:Destroy()
		end
	end
end

local function clearManagedPillars(container: Folder)
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("ManagedBy") == PILLAR_MANAGED_BY then
			child:Destroy()
		end
	end
end

local function createPillar(
	container: Folder,
	root: CFrame,
	name: string,
	localPosition: Vector3,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle
)
	local pillar = Instance.new("Part")
	pillar.Name = name
	pillar:SetAttribute("ManagedBy", PILLAR_MANAGED_BY)
	configureStructuralPart(pillar)
	pillar.Size = Vector3.new(style.PostWidth or PILLAR_WIDTH_STUDS, pillarHeight, style.PostDepth or PILLAR_DEPTH_STUDS)
	pillar.CFrame = root
		* CFrame.new(localPosition.X, floorTopY + pillarHeight / 2, localPosition.Z)
	pillar.Color = style.Color
	pillar.Material = style.Material
	pillar.MaterialVariant = style.MaterialVariant
	pillar.CustomPhysicalProperties = style.EffectivePhysicalProperties
	pillar.CollisionGroup = style.CollisionGroup
	pillar.CanCollide = style.CanCollide
	pillar.CanTouch = style.CanTouch
	pillar.CanQuery = style.CanQuery
	StaticMaterial.Apply(pillar)
	pillar.Parent = container
end

local function createPillarsAlongEdge(
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle,
	edgeName: string,
	startLocalPosition: Vector3,
	endLocalPosition: Vector3,
	shouldSkip: ((Vector3) -> boolean)?
)
	local edgeLength = (endLocalPosition - startLocalPosition).Magnitude
	local intervalCount = math.max(1, math.ceil(edgeLength / PILLAR_MAX_SPACING_STUDS))
	local placedIndex = 0
	for interval = 1, intervalCount - 1 do
		local localPosition = startLocalPosition:Lerp(endLocalPosition, interval / intervalCount)
		if not shouldSkip or not shouldSkip(localPosition) then
			placedIndex += 1
			createPillar(
				container,
				root,
				string.format("BasePillar_%s_%02d", edgeName, placedIndex),
				localPosition,
				floorTopY,
				pillarHeight,
				style
			)
		end
	end
end

local function createPerimeterPillars(
	base: Model,
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle,
	geometry: any?
)
	clearManagedPillars(container)
	-- Preserve the established perimeter centreline while reducing only each
	-- pillar's horizontal cross-section.
	local perimeter = if geometry then geometry.perimeter else nil
	local width = if perimeter then perimeter.width else Config.BASE_FOOTPRINT_WIDTH_STUDS
	local depth = if perimeter then perimeter.depth else Config.BASE_FOOTPRINT_DEPTH_STUDS
	local centreX = if perimeter then perimeter.centreX else 0
	local centreZ = if perimeter then perimeter.centreZ else 0
	local postWidth = if perimeter then perimeter.postWidth else PILLAR_WIDTH_STUDS
	local postDepth = if perimeter then perimeter.postDepth else PILLAR_DEPTH_STUDS
	style = table.clone(style)
	style.PostWidth = postWidth
	style.PostDepth = postDepth
	local halfWidth = (width - (if perimeter then postWidth * 2 else PILLAR_ORIGINAL_WIDTH_STUDS)) / 2
	local halfDepth = (depth - (if perimeter then postDepth * 2 else PILLAR_ORIGINAL_DEPTH_STUDS)) / 2
	local frontSign = if perimeter and perimeter.frontSign then perimeter.frontSign else entranceSign(base, root)
	local frontZ = centreZ + frontSign * halfDepth
	local backZ = centreZ - frontSign * halfDepth
	local frontLeft = Vector3.new(centreX - halfWidth, 0, frontZ)
	local frontRight = Vector3.new(centreX + halfWidth, 0, frontZ)
	local backLeft = Vector3.new(centreX - halfWidth, 0, backZ)
	local backRight = Vector3.new(centreX + halfWidth, 0, backZ)

	for name, localPosition in
		{
			BasePillar_Corner_FL = frontLeft,
			BasePillar_Corner_FR = frontRight,
			BasePillar_Corner_BL = backLeft,
			BasePillar_Corner_BR = backRight,
		}
	do
		createPillar(container, root, name, localPosition, floorTopY, pillarHeight, style)
	end

	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Front",
		frontLeft,
		frontRight,
		function(localPosition)
			return math.abs(localPosition.X - centreX) < ENTRANCE_CLEAR_WIDTH_STUDS / 2
		end
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Back",
		backLeft,
		backRight,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Left",
		frontLeft,
		backLeft,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Right",
		frontRight,
		backRight,
		nil
	)
end

local function ensureInterior(base: Model, root: CFrame, platformFloorY: number, geometry: any?): number
	local container = ensureFolder(base, LAYOUT_CONTAINER_NAME)
	local floor: BasePart? = nil
	if geometry then
		-- Compact support reuses the migrated authoritative Foundation. No coplanar runtime floor.
		local foundation = base:FindFirstChild("Foundation")
		assert(foundation and foundation:IsA("BasePart") and foundation:GetAttribute("LayoutRole") == "Foundation", "Compact base Foundation is missing or has changed identity")
		floor = foundation :: BasePart
	else
		for _, name in { "BaseFloor", "Floor", "InteriorFloor", "GroundFloor" } do
			local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
			if candidate and candidate:IsA("BasePart") then
				floor = candidate
				break
			end
		end
	end
	local createdFloor = false
	if not floor then
		floor, createdFloor = ensurePart(base, container, "BaseFloor")
	end
	local resolvedFloor = floor :: BasePart
	local floorThickness = if createdFloor then 1 else math.max(resolvedFloor.Size.Y, 0.2)
	local floorTopY = if createdFloor
		then platformFloorY
		else platformTopLocalY(root, resolvedFloor)
	if geometry then
		-- Retain the authoritative Foundation colour, flags and effective physics.
		StaticMaterial.Apply(resolvedFloor)
	else
		configureStructuralPart(resolvedFloor)
	end
	local support = if geometry then geometry.support else nil
	resolvedFloor.Size = Vector3.new(
		if support then support.width else Config.BASE_FOOTPRINT_WIDTH_STUDS,
		floorThickness,
		if support then support.depth else Config.BASE_FOOTPRINT_DEPTH_STUDS
	)
	resolvedFloor.CFrame = root * CFrame.new(
		if support then support.centreX else 0, floorTopY - floorThickness / 2,
		if support then support.centreZ else 0
	)

	local pillarStyle = captureStructuralStyle(resolvedFloor)
	local pillarHeight = Config.BASE_WALL_HEIGHT_STUDS
	for _, wallName in LEGACY_WALL_NAMES do
		local wall = legacyWall(base, container, wallName)
		if wall then
			pillarStyle = captureStructuralStyle(wall)
			pillarHeight = wall.Size.Y
			break
		end
	end
	removeLegacyWalls(base, container)
	createPerimeterPillars(base, container, root, floorTopY, pillarHeight, pillarStyle, geometry)
	return floorTopY
end

local function setMarkerFacing(slot: any, platformCFrame: CFrame, markerOffset: CFrame)
	if slot.Marker:IsA("Attachment") then
		slot.Marker.CFrame = CFrame.new(markerOffset.Position)
	else
		local marker = slot.Marker :: BasePart
		marker.CFrame = platformCFrame * CFrame.new(markerOffset.Position)
	end
end

local function positionPlatforms(root: CFrame, slots: { any }, geometry: any?): (any, number)
	local ordered = table.clone(slots)
	table.sort(ordered, function(left, right)
		return left.Index < right.Index
	end)
	assert(#ordered == Config.PLATFORM_COUNT, "Phase 5D requires exactly 12 platforms")
	local placementById = {}
	local floorY = math.huge
	for order, slot in ordered do
		local platform = slot.Platform :: BasePart
		local platformId = platformIdFromPart(platform)
		assert(platformId == slot.Index, "Platform stable ID changed during layout")
		local topY = platformTopLocalY(root, platform)
		floorY = math.min(floorY, topY - platform.Size.Y)
		local side = if order <= Config.PLATFORMS_PER_SIDE then -1 else 1
		local row = if side < 0 then order else order - Config.PLATFORMS_PER_SIDE
		local canonical = if geometry then geometry.slots[slot.Index] else nil
		assert(not canonical or (canonical.Index == slot.Index and canonical.Side == side), "Compact stable slot identity changed")
		local x = if canonical then canonical.X else side * Config.PLATFORM_ROW_OFFSET_X
		local z = if canonical then canonical.Z else Config.PLATFORM_Z_CENTERS[row]
		local normalSize = if canonical then canonical.PadNormalStuds else Config.PLATFORM_SIDE_STUDS
		local tangentSize = if canonical then canonical.PadTangentialStuds else Config.PLATFORM_SIDE_STUDS
		local aisleX = if geometry then geometry.formationCenterX else 0
		local localPosition = Vector3.new(x, topY - platform.Size.Y / 2, z)
		local localFacing = CFrame.lookAt(
			localPosition,
			Vector3.new(aisleX, localPosition.Y, localPosition.Z),
			Vector3.yAxis
		)
		local markerOffset = if slot.Marker:IsA("Attachment")
			then slot.Marker.CFrame
			else platform.CFrame:ToObjectSpace((slot.Marker :: BasePart).CFrame)
		platform.Size =
			Vector3.new(tangentSize, platform.Size.Y, normalSize)
		platform.CFrame = root * localFacing
		platform.Anchored = true
		setMarkerFacing(slot, platform.CFrame, markerOffset)
		placementById[slot.Index] = {
			Side = side,
			XCenter = x,
			ZCenter = z,
			PlatformNormalStuds = normalSize,
			PlatformTopY = topY,
		}
	end
	assert(floorY < math.huge, "Phase 5D platforms have no usable floor datum")
	return placementById, floorY
end

local function ensureAmountView(plaque: BasePart): (SurfaceGui, TextLabel)
	for _, child in plaque:GetChildren() do
		if child.Name == "IncomeSurfaceGui" or child.Name == "AmountBillboard" then
			child:Destroy()
		end
	end

	local surface: SurfaceGui? = nil
	for _, child in plaque:GetChildren() do
		if child.Name == AMOUNT_SURFACE_NAME then
			if surface == nil and child:IsA("SurfaceGui") then
				surface = child
			else
				child:Destroy()
			end
		end
	end
	if surface == nil then
		surface = Instance.new("SurfaceGui")
		surface.Name = AMOUNT_SURFACE_NAME
		surface.Parent = plaque
	end
	local gui = surface :: SurfaceGui
	gui.Adornee = plaque
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	-- Top-face UV axes differ from the pad's forward/right axes. Rotate the
	-- label within the swapped canvas so it reads from this platform's front.
	gui.CanvasSize = Vector2.new(112, 200)
	gui.MaxDistance = 35
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.ClipsDescendants = true
	gui.ZOffset = 0
	gui.Active = false
	gui.Enabled = false

	local label = gui:FindFirstChild(AMOUNT_LABEL_NAME)
	if label and not label:IsA("TextLabel") then
		label:Destroy()
		label = nil
	end
	for _, child in gui:GetChildren() do
		if child:IsA("TextLabel") and child ~= label then
			child:Destroy()
		end
	end
	if not label then
		label = Instance.new("TextLabel")
		label.Name = AMOUNT_LABEL_NAME
		label.Parent = gui
	end
	local amount = label :: TextLabel
	amount.AnchorPoint = Vector2.new(0.5, 0.5)
	amount.Position = UDim2.fromScale(0.5, 0.5)
	amount.Size = UDim2.fromOffset(190, 72)
	amount.AutomaticSize = Enum.AutomaticSize.None
	amount.BackgroundTransparency = 1
	amount.BorderSizePixel = 0
	amount.Font = Enum.Font.FredokaOne
	amount.TextColor3 = Color3.fromRGB(255, 255, 255)
	amount.TextTransparency = 0
	amount.TextSize = 36
	amount.TextScaled = false
	amount.TextWrapped = false
	amount.TextTruncate = Enum.TextTruncate.None
	amount.TextXAlignment = Enum.TextXAlignment.Center
	amount.TextYAlignment = Enum.TextYAlignment.Center
	amount.TextStrokeTransparency = 1
	amount.RichText = false
	amount.Active = false
	amount.Selectable = false
	amount.Rotation = -90
	amount.Text = ""

	for _, child in amount:GetChildren() do
		if child:IsA("UITextSizeConstraint") or child:IsA("UIScale") then
			child:Destroy()
		end
	end
	local stroke: UIStroke? = nil
	for _, child in amount:GetChildren() do
		if child:IsA("UIStroke") then
			if stroke == nil and child.Name == AMOUNT_STROKE_NAME then
				stroke = child
			else
				child:Destroy()
			end
		end
	end
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = AMOUNT_STROKE_NAME
		stroke.Parent = amount
	end
	local outline = stroke :: UIStroke
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Color = Color3.fromRGB(8, 8, 10)
	outline.Thickness = 2
	outline.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Transparency = 0
	return gui, amount
end

local function formatCashSnapshot(value: any): string
	local safe = if type(value) == "number" and value == value and value >= 0 then value else 0
	return CurrencyFormatter.FormatCompactCash(math.floor(safe))
end

local function applyIncomeSnapshotToPlaque(
	plaque: BasePart,
	baseId: string,
	platformId: number,
	ownerUserId: number,
	snapshot: any?
)
	plaque:SetAttribute("BaseId", baseId)
	plaque:SetAttribute("PlatformId", platformId)
	plaque:SetAttribute("BaseOwnerUserId", ownerUserId)
	if snapshot then
		plaque:SetAttribute("IncomeSnapshotReady", true)
		plaque:SetAttribute("IncomeOccupied", snapshot.Occupied == true)
		plaque:SetAttribute("IncomeRatePerSecond", snapshot.RatePerSecond or 0)
		plaque:SetAttribute("UnclaimedCashSnapshot", snapshot.UnclaimedCashSnapshot or 0)
		plaque:SetAttribute("IncomeSnapshotServerTime", snapshot.SnapshotServerTime or 0)
		plaque:SetAttribute("IncomeRevision", snapshot.Revision or 0)
	else
		plaque:SetAttribute("IncomeSnapshotReady", false)
		plaque:SetAttribute("IncomeOccupied", false)
		plaque:SetAttribute("IncomeRatePerSecond", 0)
		plaque:SetAttribute("UnclaimedCashSnapshot", 0)
		plaque:SetAttribute("IncomeSnapshotServerTime", 0)
		plaque:SetAttribute("IncomeRevision", 0)
	end
	local gui, label = ensureAmountView(plaque)
	local cash = plaque:GetAttribute("UnclaimedCashSnapshot")
	local safeCash = if type(cash) == "number" and cash == cash and cash >= 0 then cash else 0
	local showAmount = plaque:GetAttribute("IncomeSnapshotReady") == true
		and plaque:GetAttribute("IncomeOccupied") == true
	label.Text = if showAmount then formatCashSnapshot(safeCash) else ""
	gui.Enabled = showAmount
end

local function candidatePlaques(base: Model): { BasePart }
	local result = {}
	for _, descendant in base:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and (
				CollectionService:HasTag(descendant, PLAQUE_TAG)
				or descendant.Name:match("^IncomePlaque_") ~= nil
			)
		then
			table.insert(result, descendant)
		end
	end
	return result
end

local function retirePlaque(plaque: BasePart)
	local binding = plaqueBindings[plaque]
	if binding and binding.TouchedConnection then
		binding.TouchedConnection:Disconnect()
	end
	plaqueBindings[plaque] = nil
	CollectionService:RemoveTag(plaque, PLAQUE_TAG)
	plaque:Destroy()
end

local function characterFromTouchedPart(part: any): Model?
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil
	end
	if part:FindFirstAncestorWhichIsA("Accessory") or part:FindFirstAncestorWhichIsA("Tool") then
		return nil
	end
	return part:FindFirstAncestorOfClass("Model")
end

function BaseIncomePlaqueSystem:HandlePlaqueTouch(plaque: BasePart, touchedPart: any): any
	local binding = plaqueBindings[plaque]
	if not started or not binding or states[binding.Base] ~= binding.State then
		return nil
	end
	local character = characterFromTouchedPart(touchedPart)
	local player = if character then getPlayerFromCharacter(character) else nil
	if
		player == nil
		or player.Parent ~= Players
		or player.Character ~= character
		or not touchedPart:IsDescendantOf(character)
	then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	-- Touched is the trigger; TouchEnded is not a reliable lifetime boundary
	-- (limbs can be removed or contacts can disappear without the callback).
	-- Bound duplicate limb notifications by time, never by a permanent latch.
	local key = binding.BaseId .. ":" .. tostring(binding.PlatformId)
	local attempts = touchAttempts[player]
	if not attempts then
		attempts = {}
		touchAttempts[player] = attempts
	end
	local now = clock()
	if now < (attempts[key] or 0) then
		return { ok = false, code = "Busy" }
	end
	attempts[key] = now + Config.PLAQUE_TOUCH_COOLDOWN_SECONDS
	local result = incomeSystem:TryClaimPlatform(player, binding.BaseId, binding.PlatformId)
	if result and result.ok then
		local snapshot = incomeSystem:GetPlatformIncomeSnapshot(binding.BaseId, binding.PlatformId)
		if snapshot then
			applyIncomeSnapshotToPlaque(
				plaque,
				binding.BaseId,
				binding.PlatformId,
				binding.OwnerUserId,
				snapshot
			)
		end
		plaque:SetAttribute("LastClaimUserId", player.UserId)
		plaque:SetAttribute("LastClaimAmount", result.paid or 0)
		plaque:SetAttribute("ClaimResetAmount", result.remainingExact or 0)
		local claimRevision = plaque:GetAttribute("ClaimRevision")
		plaque:SetAttribute(
			"ClaimRevision",
			(if type(claimRevision) == "number" then claimRevision else 0) + 1
		)
	end
	return result
end

local function bindPlaqueTouch(
	state: any,
	plaque: BasePart,
	platformId: number,
	claimSensorCFrame: CFrame
)
	local previous = plaqueBindings[plaque]
	if previous and previous.TouchedConnection then
		previous.TouchedConnection:Disconnect()
	end
	local binding = {
		State = state,
		Base = state.Base,
		BaseId = state.BaseId,
		PlatformId = platformId,
		OwnerUserId = state.OwnerUserId,
	}
	local sensor = plaque:FindFirstChild(TOUCH_SENSOR_NAME)
	if sensor and not sensor:IsA("BasePart") then
		sensor:Destroy()
		sensor = nil
	end
	if not sensor then
		sensor = Instance.new("Part")
		sensor.Name = TOUCH_SENSOR_NAME
		sensor.Parent = plaque
	end
	local touchSensor = sensor :: BasePart
	touchSensor.Size =
		Vector3.new(PLAQUE_WIDTH_STUDS, Config.PLAQUE_TOUCH_HEIGHT_STUDS, PLAQUE_DEPTH_STUDS)
	touchSensor.CFrame = claimSensorCFrame
	touchSensor.Anchored = true
	touchSensor.CanCollide = false
	touchSensor.CanTouch = true
	touchSensor.CanQuery = false
	touchSensor.Massless = true
	touchSensor.Transparency = 1
	touchSensor.CastShadow = false
	binding.Sensor = touchSensor
	binding.TouchedConnection = touchSensor.Touched:Connect(function(otherPart)
		BaseIncomePlaqueSystem:HandlePlaqueTouch(plaque, otherPart)
	end)
	plaqueBindings[plaque] = binding
	state.Plaques[platformId] = plaque
end

local function configurePlaque(
	state: any,
	plaque: BasePart,
	platformId: number,
	placement: any,
	floorTopY: number
)
	plaque.Name = getPlaqueName(platformId)
	plaque.Size = Vector3.new(PLAQUE_WIDTH_STUDS, PLAQUE_THICKNESS_STUDS, PLAQUE_DEPTH_STUDS)
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.CanTouch = false
	plaque.CanQuery = true
	plaque.Massless = true
	plaque.Color = Color3.fromRGB(60, 255, 90)
	plaque.Transparency = 0
	StaticMaterial.Apply(plaque, Enum.Material.SmoothPlastic)
	plaque.TopSurface = Enum.SurfaceType.Smooth
	plaque.BottomSurface = Enum.SurfaceType.Smooth
	local inward = placement.PlatformNormalStuds / 2
		+ PLAQUE_PLATFORM_GAP_STUDS
		+ PLAQUE_DEPTH_STUDS / 2
	local plaqueX = placement.XCenter - placement.Side * inward
	local plaqueY = floorTopY + PLAQUE_FLOOR_CLEARANCE_STUDS + PLAQUE_THICKNESS_STUDS / 2
	local plaquePosition =
		state.Root:PointToWorldSpace(Vector3.new(plaqueX, plaqueY, placement.ZCenter))
	local inwardDirection = state.Root:VectorToWorldSpace(Vector3.new(-placement.Side, 0, 0))
	local levelInward = Vector3.new(inwardDirection.X, 0, inwardDirection.Z).Unit
	plaque.CFrame = CFrame.lookAt(plaquePosition, plaquePosition + levelInward, Vector3.yAxis)

	-- The contact envelope follows this pad, not a second offset layout.
	local claimSensorCFrame = plaque.CFrame
		* CFrame.new(0, PLAQUE_THICKNESS_STUDS / 2 + Config.PLAQUE_TOUCH_HEIGHT_STUDS / 2, 0)
	if plaque:GetAttribute("ClaimRevision") == nil then
		plaque:SetAttribute("ClaimRevision", 0)
	end
	CollectionService:AddTag(plaque, PLAQUE_TAG)
	applyIncomeSnapshotToPlaque(plaque, state.BaseId, platformId, state.OwnerUserId, nil)
	bindPlaqueTouch(state, plaque, platformId, claimSensorCFrame)
end

local function disconnectState(state: any)
	for _, plaque in state.Plaques do
		local binding = plaqueBindings[plaque]
		if binding and binding.TouchedConnection then
			binding.TouchedConnection:Disconnect()
		end
		plaqueBindings[plaque] = nil
	end
	if state.DestroyingConnection then
		state.DestroyingConnection:Disconnect()
		state.DestroyingConnection = nil
	end
	table.clear(state.Plaques)
end

local function teardownBase(base: Model, destroyPlaques: boolean)
	local state = states[base]
	if state then
		disconnectState(state)
		states[base] = nil
	end
	for _, plaque in candidatePlaques(base) do
		if destroyPlaques then
			retirePlaque(plaque)
		else
			plaque:SetAttribute("BaseOwnerUserId", 0)
		end
	end
	table.clear(touchAttempts)
end

local function applyPendingSnapshots(pending: { any })
	if #pending == 0 then
		return
	end
	local snapshots = incomeSystem:SyncPlatformSnapshots(pending)
	for index, request in pending do
		local snapshot = snapshots[index]
		if snapshot then
			applyIncomeSnapshotToPlaque(
				request.Plaque,
				request.BaseId,
				request.PlatformId,
				request.OwnerUserId,
				snapshot
			)
		end
	end
end

local function refreshBaseSnapshots(base: Model, storage: any?, forceAll: boolean)
	local state = states[base]
	if not state then
		return
	end
	local pending = {}
	for platformId, plaque in state.Plaques do
		local snapshot = incomeSystem:GetPlatformIncomeSnapshot(state.BaseId, platformId)
		local record = if storage then storage:GetPlatformRecord(platformId) else nil
		local changed = forceAll
			or snapshot == nil
			or snapshot.Occupied ~= (record ~= nil)
			or snapshot.IndividualId ~= (if record then record.ItemId else nil)
			or snapshot.CatalogueId ~= (if record then record.BrainrotId else nil)
		if changed then
			table.insert(pending, {
				BaseId = state.BaseId,
				PlatformId = platformId,
				Plaque = plaque,
				OwnerUserId = state.OwnerUserId,
			})
			continue
		end
		if snapshot then
			applyIncomeSnapshotToPlaque(
				plaque,
				state.BaseId,
				platformId,
				state.OwnerUserId,
				snapshot
			)
		end
	end
	applyPendingSnapshots(pending)
end

local function refreshAccumulatedPlaques()
	local pending = {}
	for base, state in states do
		local player = if state.OwnerUserId ~= 0 then getPlayerByUserId(state.OwnerUserId) else nil
		local storage = if player then storageSystem:GetStorageForPlayer(player) else nil
		if storage and storage.Base == base then
			for platformId, plaque in state.Plaques do
				local current = incomeSystem:GetPlatformIncomeSnapshot(state.BaseId, platformId)
				if current and current.Occupied then
					table.insert(pending, {
						BaseId = state.BaseId,
						PlatformId = platformId,
						Plaque = plaque,
						OwnerUserId = state.OwnerUserId,
					})
				end
			end
		end
	end
	applyPendingSnapshots(pending)
end

function BaseIncomePlaqueSystem:BuildBase(base: Model, ownerUserId: number?): (boolean, string?)
	if typeof(base) ~= "Instance" or not base:IsA("Model") or base.Parent == nil then
		return false, "INVALID_BASE"
	end
	local slots = storageSystem:GetRegisteredPlatforms(base)
	if not slots or #slots ~= Config.PLATFORM_COUNT then
		return false, "INVALID_PLATFORMS"
	end
	-- Resolve/validate before any teardown: marked compact data must never fall back.
	local geometry = Config.GetGeometry(base)
	teardownBase(base, false)
	local root = baseRootCFrame(base)
	local placementById, platformFloorY = positionPlatforms(root, slots, geometry)
	local floorTopY = ensureInterior(base, root, platformFloorY, geometry)
	local baseId = base:GetAttribute("BaseId")
	if type(baseId) ~= "string" or baseId == "" then
		return false, "INVALID_BASE_ID"
	end
	local state = {
		Base = base,
		BaseId = baseId,
		Root = root,
		OwnerUserId = ownerUserId or 0,
		Plaques = {},
	}
	states[base] = state
	local container = ensureFolder(base, PLAQUE_CONTAINER_NAME)
	local candidates = candidatePlaques(base)
	local used: { [BasePart]: boolean } = {}
	for platformId = 1, Config.PLATFORM_COUNT do
		local expectedName = getPlaqueName(platformId)
		local selected: BasePart? = nil
		for _, candidate in candidates do
			if
				not used[candidate]
				and candidate.Name == expectedName
				and (
					candidate:GetAttribute("PlatformId") == nil
					or candidate:GetAttribute("PlatformId") == platformId
				)
			then
				selected = candidate
				break
			end
		end
		if not selected then
			selected = Instance.new("Part")
			selected.Parent = container
		end
		selected.Parent = container
		used[selected] = true
		configurePlaque(state, selected, platformId, placementById[platformId], floorTopY)
	end
	for _, candidate in candidates do
		if not used[candidate] then
			retirePlaque(candidate)
		end
	end
	state.DestroyingConnection = base.Destroying:Connect(function()
		teardownBase(base, true)
	end)
	if storageSystem.RefreshPlatformDisplays then
		storageSystem:RefreshPlatformDisplays(base)
	end
	return true, nil
end

function BaseIncomePlaqueSystem:GetPlaques(base: Model): { BasePart }
	local state = states[base]
	local result = {}
	if state then
		for platformId = 1, Config.PLATFORM_COUNT do
			if state.Plaques[platformId] then
				table.insert(result, state.Plaques[platformId])
			end
		end
	end
	return result
end

function BaseIncomePlaqueSystem:Init(dependencies: any?): boolean
	if started then
		return false
	end
	initialDependencies = dependencies or {}
	return true
end

function BaseIncomePlaqueSystem:Start(dependencies: any?): boolean
	if started then
		return false
	end
	local deps = dependencies or initialDependencies or {}
	baseSystem = deps.Base or PlayerBaseSystem
	storageSystem = deps.Storage or BaseStorageSystem
	incomeSystem = deps.Income or BrainrotIncomeSystem
	clock = deps.Now or function(): number
		return Workspace:GetServerTimeNow()
	end
	getPlayerFromCharacter = deps.GetPlayerFromCharacter
		or function(character: Model): Player?
			return Players:GetPlayerFromCharacter(character)
		end
	getPlayerByUserId = deps.GetPlayerByUserId
		or function(userId: number): Player?
			return Players:GetPlayerByUserId(userId)
		end
	started = true

	for _, base in baseSystem:GetRegisteredBases() do
		local ownerUserId = base:GetAttribute("OwnerUserId")
		local built, reason = self:BuildBase(
			base,
			if type(ownerUserId) == "number" and ownerUserId ~= 0 then ownerUserId else 0
		)
		if not built then
			log:Warn("Phase 5D layout unavailable for %s: %s", base:GetFullName(), tostring(reason))
		elseif type(ownerUserId) == "number" and ownerUserId ~= 0 then
			local player = getPlayerByUserId(ownerUserId)
			local storage = if player then storageSystem:GetStorageForPlayer(player) else nil
			if storage then
				refreshBaseSnapshots(base, storage, true)
			end
		end
	end

	assignmentConnection = baseSystem:SubscribeAssignments(function(player, base)
		local built, reason = self:BuildBase(base, player.UserId)
		if not built then
			log:Warn("Phase 5D assignment layout failed: %s", tostring(reason))
			return
		end
		local storage = storageSystem:GetStorageForPlayer(player)
		if storage then
			refreshBaseSnapshots(base, storage, true)
		end
	end, function(_, base)
		teardownBase(base, false)
	end)

	unsubscribeStorage = storageSystem:ObserveStorage({
		OnBound = function(player, storage)
			local base = storage.Base
			if not states[base] then
				self:BuildBase(base, player.UserId)
			end
			local state = states[base]
			if state then
				state.OwnerUserId = player.UserId
				for _, binding in plaqueBindings do
					if binding.State == state then
						binding.OwnerUserId = player.UserId
					end
				end
				refreshBaseSnapshots(base, storage, true)
			end
		end,
		OnCommitted = function(_, storage)
			refreshBaseSnapshots(storage.Base, storage, false)
		end,
		OnReleasing = function(_, storage)
			refreshBaseSnapshots(storage.Base, storage, false)
		end,
	})
	if deps.ConnectSnapshotRefresh ~= false then
		local heartbeat = deps.Heartbeat or RunService.Heartbeat
		snapshotAccumulator = 0
		snapshotConnection = heartbeat:Connect(function(deltaTime)
			snapshotAccumulator += deltaTime
			if snapshotAccumulator >= PLAQUE_SNAPSHOT_REFRESH_SECONDS then
				snapshotAccumulator %= PLAQUE_SNAPSHOT_REFRESH_SECONDS
				refreshAccumulatedPlaques()
			end
		end)
	end
	return true
end

function BaseIncomePlaqueSystem:Destroy(): boolean
	if assignmentConnection then
		assignmentConnection:Disconnect()
		assignmentConnection = nil
	end
	if unsubscribeStorage then
		unsubscribeStorage()
		unsubscribeStorage = nil
	end
	if snapshotConnection then
		snapshotConnection:Disconnect()
		snapshotConnection = nil
	end
	snapshotAccumulator = 0
	local bases = {}
	for base in states do
		table.insert(bases, base)
	end
	for _, base in bases do
		teardownBase(base, false)
	end
	table.clear(plaqueBindings)
	table.clear(touchAttempts)
	started = false
	initialDependencies = nil
	baseSystem, storageSystem, incomeSystem =
		PlayerBaseSystem, BaseStorageSystem, BrainrotIncomeSystem
	clock = function(): number
		return Workspace:GetServerTimeNow()
	end
	getPlayerFromCharacter = function(character: Model): Player?
		return Players:GetPlayerFromCharacter(character)
	end
	getPlayerByUserId = function(userId: number): Player?
		return Players:GetPlayerByUserId(userId)
	end
	return true
end

return BaseIncomePlaqueSystem
]]}
-- Generated from the fresh native Edit source capture. No live require cache or Source writes.
local E={}
E["Config"]={path="ReplicatedStorage.Shared.Config.BaseLayoutConfig",sha256="fec81ec990b6f2837150781feaef1f90055adf336b2987ae440a22e128cf332e",source=[[--!strict

-- The 36-by-32-stud footprint is a project visual estimate derived from the
-- compact reference layout, not an official published dimension.
local BaseLayoutConfig = {
	STANDARD_ROBLOX_PLAYER_HEIGHT_STUDS = 5.0,
	BRAINROT_TARGET_VISIBLE_HEIGHT_STUDS = 3.5,
	PLATFORM_DIAGONAL_STUDS = 3.0,
	PLATFORM_SIDE_STUDS = 3 / math.sqrt(2),

	BASE_FOOTPRINT_WIDTH_STUDS = 36,
	BASE_FOOTPRINT_DEPTH_STUDS = 32,
	BASE_WALL_HEIGHT_STUDS = 10,
	BASE_WALL_THICKNESS_STUDS = 1,
	PLATFORM_COUNT = 12,
	PLATFORMS_PER_SIDE = 6,
	PLATFORM_ROW_OFFSET_X = 7.25,
	PLATFORM_Z_CENTERS = table.freeze({ -11.25, -6.75, -2.25, 2.25, 6.75, 11.25 }),

	PLAQUE_INWARD_DEPTH_STUDS = 1.75,
	PLAQUE_TANGENTIAL_WIDTH_STUDS = 3.0,
	PLAQUE_HEIGHT_STUDS = 0.20,
	PLAQUE_PLATFORM_GAP_STUDS = 0.25,
	PLAQUE_VISIBLE_RISE_STUDS = 0.03,
	-- The visible plaque remains flush and non-colliding. This invisible vertical
	-- contact envelope reaches ordinary avatar feet, which rest above the floor.
	PLAQUE_TOUCH_HEIGHT_STUDS = 1.0,
	PLAQUE_TOUCH_COOLDOWN_SECONDS = 0.5,
}

return table.freeze(BaseLayoutConfig)
]]}
E["Scale"]={path="ReplicatedStorage.Shared.Utility.BrainrotVisualScale",sha256="c1982d3caa30bbbe32ceacd75cecf724c6ce6240026b53cf7d5bb68559b1ab4b",source=[[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotVisualScale = {}

BrainrotVisualScale.BRAINROT_PLAYER_HEIGHT_RATIO = 0.64
-- Body-only bounds of the project's intended default R15 gameplay rig, measured
-- once with a clean HumanoidDescription (no accessories, Tools or HumanoidRootPart).
BrainrotVisualScale.PLAYER_REFERENCE_HEIGHT_STUDS = 5.457267761230469
BrainrotVisualScale.TARGET_HEIGHT_STUDS = BrainrotVisualScale.PLAYER_REFERENCE_HEIGHT_STUDS
	* BrainrotVisualScale.BRAINROT_PLAYER_HEIGHT_RATIO
BrainrotVisualScale.TOLERANCE_STUDS = math.max(0.03, BrainrotVisualScale.TARGET_HEIGHT_STUDS * 0.01)

local EXCLUDED_NAME_FRAGMENTS = {
	"hitbox",
	"proxy",
	"helper",
	"prompt",
	"indicator",
	"debug",
	"selection",
	"effect",
	"label",
	"capturednet",
	"carriedbrainrot",
	"cargovisual",
	"stored_",
}

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

-- This predicate deliberately does not depend on CanQuery/CanCollide. Carry,
-- cargo and storage presentations disable those properties after creation, but
-- their visible geometry must still measure identically to the world model.
function BrainrotVisualScale.IsVisualPart(part: BasePart, model: Model): boolean
	if not part:IsDescendantOf(model) or part.Transparency >= 1 then
		return false
	end
	local ancestor: Instance? = part
	while ancestor and ancestor ~= model do
		if ancestor:IsA("Tool") or ancestor:GetAttribute("BrainrotVisualHelper") == true then
			return false
		end
		local name = string.lower(ancestor.Name)
		for _, fragment in EXCLUDED_NAME_FRAGMENTS do
			if string.find(name, fragment, 1, true) then
				return false
			end
		end
		ancestor = ancestor.Parent
	end
	return true
end

-- Returns visual bounds in model-pivot space so callers can position the model
-- after scaling without allowing invisible gameplay geometry to affect contact.
function BrainrotVisualScale.GetVisualBounds(model: Model): (CFrame?, Vector3?, string?)
	local pivot = model:GetPivot()
	local low = Vector3.one * math.huge
	local high = Vector3.one * -math.huge
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and BrainrotVisualScale.IsVisualPart(descendant, model) then
			count += 1
			local frame = pivot:ToObjectSpace(descendant.CFrame)
			local half = descendant.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local point = frame * (half * Vector3.new(x, y, z))
						low = low:Min(point)
						high = high:Max(point)
					end
				end
			end
		end
	end
	if count == 0 then
		return nil, nil, "NO_VISIBLE_PARTS"
	end
	local size = high - low
	if not finite(size.X) or not finite(size.Y) or not finite(size.Z) or size.Y <= 0.0001 then
		return nil, nil, "INVALID_VISIBLE_BOUNDS"
	end
	return CFrame.new((low + high) / 2), size, nil
end

function BrainrotVisualScale.GetVisualHeight(model: Model): (number?, string?)
	local _, size, reason = BrainrotVisualScale.GetVisualBounds(model)
	if not size then
		return nil, reason
	end
	return size.Y, nil
end

function BrainrotVisualScale.GetCanonicalModelScale(model: Model): (number?, string?)
	local height, reason = BrainrotVisualScale.GetVisualHeight(model)
	if not height then
		return nil, reason
	end
	local currentScale = model:GetScale()
	local scale = currentScale * (BrainrotVisualScale.TARGET_HEIGHT_STUDS / height)
	if not finite(scale) or scale <= 0 then
		return nil, "INVALID_CANONICAL_SCALE"
	end
	return scale, nil
end

-- Absolute and idempotent: correction is always derived from current visible
-- height, never from a previous lifecycle multiplier.
function BrainrotVisualScale.ApplyCanonicalScale(
	model: Model,
	context: string?
): (boolean, number?, string?)
	local currentHeight, reason = BrainrotVisualScale.GetVisualHeight(model)
	if not currentHeight then
		return false, nil, reason
	end
	local currentScale = model:GetScale()
	local correction = BrainrotVisualScale.TARGET_HEIGHT_STUDS / currentHeight
	local newScale = currentScale * correction
	if
		not finite(currentScale)
		or currentScale <= 0
		or not finite(correction)
		or correction <= 0
		or not finite(newScale)
		or newScale <= 0
	then
		return false, nil, "INVALID_SCALE"
	end
	model:ScaleTo(newScale)
	local measured, measureReason = BrainrotVisualScale.GetVisualHeight(model)
	if not measured then
		return false, nil, measureReason
	end
	if ReplicatedStorage:GetAttribute("BrainrotScaleTrace") == true then
		print(
			string.format(
				"[BrainrotScale] context=%s model=%s item=%s before=%.6f target=%.6f correction=%.6f scale=%.6f after=%.6f",
				context or "unspecified",
				model:GetFullName(),
				tostring(model:GetAttribute("ItemId")),
				currentHeight,
				BrainrotVisualScale.TARGET_HEIGHT_STUDS,
				correction,
				model:GetScale(),
				measured
			)
		)
	end
	if
		math.abs(measured - BrainrotVisualScale.TARGET_HEIGHT_STUDS)
		> BrainrotVisualScale.TOLERANCE_STUDS
	then
		return false, measured, "TARGET_NOT_REACHED"
	end
	return true, measured, nil
end

return table.freeze(BrainrotVisualScale)
]]}
E["Material"]={path="ReplicatedStorage.Shared.Utility.MapArtStaticMaterialPolicy",sha256="5d5ab2bf99191c87c26831183926112aabb94c3943a7af3d95df93fe3807bc1f",source=[[--!strict
-- Presentation only: preserve transforms, flags, colours, UI and effective physics.
local MaterialService = game:GetService("MaterialService")
local NAME = "Bingus_Saved_Studs_13719188279"
local variant = MaterialService:FindFirstChild(NAME)
assert(variant and variant:IsA("MaterialVariant") and variant.BaseMaterial == Enum.Material.Glacier and variant.StudsPerTile == 0.25, "Saved uniform stud material is unavailable")

local MapArtStaticMaterialPolicy = {}

-- legacyDefaultMaterial preserves the previous creator's intended material physics
-- for a new uncustomized Part. A captured variant/custom style takes precedence.
function MapArtStaticMaterialPolicy.Apply(part: BasePart, legacyDefaultMaterial: Enum.Material?): boolean
	if part.Transparency >= 1 then
		return false
	end
	local physical = part.CurrentPhysicalProperties
	local custom = part.CustomPhysicalProperties
	if custom == nil and part.MaterialVariant == "" and legacyDefaultMaterial ~= nil then
		physical = PhysicalProperties.new(legacyDefaultMaterial)
	end
	part.Material = Enum.Material.Glacier
	part.MaterialVariant = NAME
	local after = part.CurrentPhysicalProperties
	if custom == nil and (
		physical.Density ~= after.Density
		or physical.Friction ~= after.Friction
		or physical.Elasticity ~= after.Elasticity
		or physical.FrictionWeight ~= after.FrictionWeight
		or physical.ElasticityWeight ~= after.ElasticityWeight
	) then
		part.CustomPhysicalProperties = physical
	end
	part:SetAttribute("SurfaceStyle", "SavedBingusStuds")
	part:SetAttribute("StudsPerTile", 0.25)
	part:SetAttribute("StudMaterialAssetId", 13719188279)
	part:SetAttribute("MapArtStaticStudMaterial", true)
	return true
end

return table.freeze(MapArtStaticMaterialPolicy)
]]}
E["Catalog"]={path="ReplicatedStorage.Shared.Config.BrainrotCatalog",sha256="729f9c514a36858323b1a26c9d2ec5c09b91552d0adfc77fc488c22ef3389bcf",source=[[--!strict

local Rarities = require(script.Parent.Rarities)
local Money = require(script.Parent.Parent.Utility.CurrencyDenomination)
local WorldProgression = require(script.Parent.WorldProgression)
-- rows are legacy-denomination inputs; published definitions are denomination 2.

export type Tier = Rarities.Rarity
export type ExpeditionRole = "Sprinter" | "Tracker" | "Wrangler" | "Hauler" | "Trickster" | "Lucky"

export type LaunchStatus = "Live" | "Teased"
export type RegionAssignmentStatus = "Approved" | "Pending" | "Conflict"

export type BehaviourId =
	"Wanderer"
	| "ReactiveRunner"
	| "Sprinter"
	| "Trickster"
	| "Hauler"
	| "Zigzag"
	| "Camouflage"
	| "DecoySplit"
	| "LegendaryPursuit"
	| "MythicEvent"
	| "Pending"

export type BrainrotDefinition = {
	id: string,
	displayName: string,
	tier: Tier,
	modelRef: string,
	cashPerSecond: number,
	sellValue: number,
	launchStatus: LaunchStatus,
	behaviourId: BehaviourId,
	expeditionRole: ExpeditionRole,
	homeRegionId: string,
	allowedRegionIds: { string },
	regionAssignmentStatus: RegionAssignmentStatus,
	spawnEnabled: boolean,
}

type SourceRow = { [number]: any }

-- Phase 6A-1's single authoritative species declaration. Source IDs are retained here
-- only long enough to normalize them into the project's underscore-form canonical IDs.
local rows: { SourceRow } = {
	{ "BRT-001", "Bingus Baguette", "Common", "REGION_FOREST", "Sprinter", 1.8, 108, "Live" },
	{ "BRT-002", "Tralalero Toad", "Common", "REGION_BEACH", "Tracker", 2, 120, "Live" },
	{ "BRT-003", "Cappuccino Capybara", "Common", "REGION_SWAMP", "Wrangler", 2.2, 132, "Live" },
	{ "BRT-004", "Ballerina Banana", "Common", "REGION_BEACH", "Hauler", 2.3, 138, "Live" },
	{ "BRT-005", "Bombardiro Pigeon", "Common", "REGION_VOLCANO", "Trickster", 1.9, 114, "Live" },
	{ "BRT-006", "Spaghetti Crocodilo", "Common", "REGION_SWAMP", "Lucky", 1.8, 108, "Live" },
	{ "BRT-007", "Tung Tung Tung Sahur", "Common", "REGION_VOLCANO", "Sprinter", 2, 120, "Live" },
	{ "BRT-008", "Lirili Larila", "Common", "REGION_ARCTIC", "Tracker", 2.2, 132, "Live" },
	{ "BRT-009", "Chimpanzini Bananini", "Common", "REGION_JUNGLE", "Wrangler", 2.3, 138, "Live" },
	{ "BRT-010", "Talpa Di Fero", "Common", "REGION_FOREST", "Hauler", 1.9, 114, "Live" },
	{ "BRT-011", "Glorbo Fruttodrillo", "Uncommon", "REGION_JUNGLE", "Trickster", 4, 240, "Live" },
	{ "BRT-012", "Frigo Camelo", "Uncommon", "REGION_ARCTIC", "Lucky", 4.5, 270, "Live" },
	{ "BRT-013", "Cavallo Virtuoso", "Uncommon", "REGION_FOREST", "Sprinter", 5, 300, "Live" },
	{ "BRT-014", "Bandito Bobritto", "Uncommon", "REGION_SWAMP", "Tracker", 5.2, 312, "Live" },
	{
		"BRT-015",
		"Strawberelli Flamingelli",
		"Uncommon",
		"REGION_BEACH",
		"Wrangler",
		4.3,
		258,
		"Live",
	},
	{ "BRT-016", "Gorillo Subwoofero", "Uncommon", "REGION_JUNGLE", "Hauler", 4, 240, "Live" },
	{
		"BRT-017",
		"Orangutini Ananassini",
		"Uncommon",
		"REGION_VOLCANO",
		"Trickster",
		4.5,
		270,
		"Live",
	},
	{ "BRT-018", "Zibra Zubra Zibralini", "Uncommon", "REGION_FOREST", "Lucky", 5, 300, "Live" },
	{ "BRT-019", "Trenostruzzo Turbo 3000", "Rare", "REGION_SWAMP", "Sprinter", 10.8, 648, "Live" },
	{ "BRT-020", "Bisonte Giuppitere", "Rare", "REGION_ARCTIC", "Tracker", 12, 720, "Live" },
	{ "BRT-021", "Cacto Hipopotamo", "Rare", "REGION_VOLCANO", "Wrangler", 13.2, 792, "Live" },
	{ "BRT-022", "Trulimero Trulicina", "Rare", "REGION_JUNGLE", "Hauler", 13.8, 828, "Live" },
	{ "BRT-023", "Giraffa Celeste", "Rare", "REGION_GLITCH", "Trickster", 11.4, 684, "Live" },
	{ "BRT-024", "Nooo My Hotspot", "Rare", "REGION_FOREST", "Lucky", 10.8, 648, "Live" },
	{ "BRT-025", "Salamino Penguino", "Rare", "REGION_ARCTIC", "Sprinter", 12, 720, "Live" },
	{ "BRT-026", "Rhino Toasterino", "Epic", "REGION_JUNGLE", "Tracker", 36, 2160, "Live" },
	{ "BRT-027", "Tralalero Tralala", "Epic", "REGION_BEACH", "Wrangler", 40, 2400, "Live" },
	{ "BRT-028", "Tartaragno", "Epic", "REGION_GLITCH", "Hauler", 44, 2640, "Live" },
	{ "BRT-029", "Cocofanto Elefanto", "Epic", "REGION_VOLCANO", "Trickster", 46, 2760, "Live" },
	{ "BRT-030", "Tractoro Dinosauro", "Epic", "REGION_GLITCH", "Lucky", 38, 2280, "Live" },
	{ "BRT-031", "Odin Din Din Dun", "Legendary", "REGION_GLITCH", "Sprinter", 135, 8100, "Live" },
	{
		"BRT-032",
		"La Vaca Saturno Saturnita",
		"Legendary",
		"REGION_GLITCH",
		"Tracker",
		150,
		9000,
		"Live",
	},
	{
		"BRT-033",
		"Dragon Cannelloni",
		"Legendary",
		"REGION_ARCTIC",
		"Wrangler",
		165,
		9900,
		"Teased",
	},
	{ "BRT-034", "Orcalero Orcala", "Mythic", "REGION_BEACH", "Hauler", 720, 43200, "Teased" },
	{
		"BRT-035",
		"La Secret Combinasion",
		"Secret",
		"REGION_SWAMP",
		"Trickster",
		2250,
		135000,
		"Teased",
	},
}

local function normalizeId(rawId: unknown): string?
	if type(rawId) ~= "string" then
		return nil
	end
	local trimmed = string.match(rawId, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return nil
	end
	local canonical = string.upper(trimmed):gsub("-", "_")
	if not string.match(canonical, "^BRT_%d%d%d$") then
		return nil
	end
	return canonical
end

local ordered: { BrainrotDefinition } = {}
local byId: { [string]: BrainrotDefinition } = {}
local aliases: { [string]: string } = {}
local behaviourAssignments: { [string]: BehaviourId } = table.freeze({
	BRT_011 = "ReactiveRunner",
	BRT_012 = "ReactiveRunner",
	BRT_013 = "ReactiveRunner",
	BRT_014 = "ReactiveRunner",
	BRT_015 = "ReactiveRunner",
	BRT_016 = "ReactiveRunner",
	BRT_017 = "ReactiveRunner",
	BRT_018 = "ReactiveRunner",
	BRT_019 = "Sprinter",
	BRT_020 = "Sprinter",
	BRT_021 = "Sprinter",
	BRT_022 = "Sprinter",
	BRT_023 = "Sprinter",
	BRT_024 = "Sprinter",
	BRT_025 = "Sprinter",
	BRT_028 = "Camouflage",
	BRT_029 = "DecoySplit",
	BRT_031 = "LegendaryPursuit",
	BRT_032 = "LegendaryPursuit",
	BRT_033 = "LegendaryPursuit",
})

for _, row in rows do
	local id = assert(normalizeId(row[1]), "Invalid source roster ID")
	assert(byId[id] == nil, "Duplicate source roster ID " .. id)
	local definition: BrainrotDefinition = {
		id = id,
		displayName = row[2],
		tier = row[3],
		modelRef = id,
		cashPerSecond = Money.FromLegacy(row[6]),
		sellValue = Money.FromLegacy(row[7]),
		launchStatus = row[8],
		-- Explicit species assignment remains independent of rarity and equipped-team role.
		behaviourId = behaviourAssignments[id] or "Wanderer",
		expeditionRole = row[5],
		homeRegionId = WorldProgression.HomeBySpecies[id] or row[4],
		allowedRegionIds = WorldProgression.AllowedBySpecies[id] or table.freeze({ row[4] }),
		regionAssignmentStatus = "Approved",
		spawnEnabled = row[8] == "Live",
	}
	table.freeze(definition)
	byId[id] = definition
	aliases[string.gsub(id, "_", "-")] = id
	table.insert(ordered, definition)
end

table.freeze(byId)
table.freeze(ordered)
table.freeze(aliases)

local Catalog: { [string]: any } = {
	Definitions = byId,
	ById = byId,
	Aliases = aliases,
}

function Catalog.NormalizeId(rawId: unknown): string?
	return normalizeId(rawId)
end

function Catalog.Get(rawId: unknown): BrainrotDefinition?
	local id = normalizeId(rawId)
	return if id then byId[id] else nil
end

function Catalog.GetAll(): { BrainrotDefinition }
	return table.clone(ordered)
end

function Catalog.GetRarity(rawId: unknown): Rarities.Rarity?
	local definition = Catalog.Get(rawId)
	return if definition then definition.tier else nil
end

function Catalog.IsDeclaredSpawnEnabled(rawId: unknown): boolean
	local definition = Catalog.Get(rawId)
	return definition ~= nil and definition.spawnEnabled
end

-- Legacy helpers delegate to the same frozen definitions.
function Catalog.ResolveId(rawId: unknown): (string?, string?)
	local id = normalizeId(rawId)
	if id == nil then
		return nil, "invalid species identifier"
	end
	if byId[id] == nil then
		return nil, "unknown species " .. id
	end
	return id, nil
end

function Catalog.GetDefinition(rawId: unknown): (BrainrotDefinition?, string?)
	local id, reason = Catalog.ResolveId(rawId)
	return if id then byId[id] else nil, reason
end

Catalog.GetById = Catalog.GetDefinition

function Catalog.GetCashPerSecond(rawId: unknown): (number?, string?)
	local definition, reason = Catalog.GetDefinition(rawId)
	return if definition then definition.cashPerSecond else nil, reason
end

-- Retained for existing callers. The reusable validator remains the validation owner.
function Catalog.Validate(source: any?): any
	local Validator = require(script.Parent.Parent.Validation.BrainrotCatalogValidator)
	local definitions = if source == nil then Catalog.GetAll() else {}
	if source ~= nil then
		for _, definition in source do
			table.insert(definitions, definition)
		end
	end
	local report = Validator.ValidateDefinitions(definitions)
	local errors = {}
	for _, item in report.errors do
		table.insert(errors, string.format("%s: %s", item.code, item.message))
	end
	return {
		IsValid = #errors == 0,
		Errors = errors,
		InvalidDefinitions = {},
		ValidAliases = aliases,
	}
end

for id, definition in byId do
	Catalog[id] = definition
end

return table.freeze(Catalog)

]]}
E["Rarities"]={path="ReplicatedStorage.Shared.Config.Rarities",sha256="f57fd51128b41d2b1109fdbe8293655db4f5a88438976aaa912a9483a118b4fd",source=[[--!strict

export type StandardRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type Rarity = StandardRarity | "Secret"

local standardOrder: { StandardRarity } = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
}
local displayOrder: { Rarity } = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Secret",
}

local canonicalByLower: { [string]: Rarity } = {}
local standardRankByRarity: { [string]: number } = {}
local displayRankByRarity: { [string]: number } = {}
local legacyTierToRarity: { [number]: StandardRarity } = {}

for rank, rarity in standardOrder do
	canonicalByLower[string.lower(rarity)] = rarity
	standardRankByRarity[rarity] = rank
	legacyTierToRarity[rank] = rarity
end
canonicalByLower.secret = "Secret"
for rank, rarity in displayOrder do
	displayRankByRarity[rarity] = rank
end

table.freeze(standardOrder)
table.freeze(displayOrder)
table.freeze(canonicalByLower)
table.freeze(standardRankByRarity)
table.freeze(displayRankByRarity)
table.freeze(legacyTierToRarity)

local Rarities = {
	Common = "Common" :: Rarity,
	Uncommon = "Uncommon" :: Rarity,
	Rare = "Rare" :: Rarity,
	Epic = "Epic" :: Rarity,
	Legendary = "Legendary" :: Rarity,
	Mythic = "Mythic" :: Rarity,
	Secret = "Secret" :: Rarity,
	StandardOrder = standardOrder,
	DisplayOrder = displayOrder,
}

function Rarities.FromLegacyTier(value: unknown): Rarity?
	if
		type(value) ~= "number"
		or value ~= value
		or math.abs(value) == math.huge
		or value % 1 ~= 0
	then
		return nil
	end
	-- There is no persisted Tier = 7 contract in the current project. Secret is
	-- deliberately absent from this ordinary-tier compatibility boundary.
	return legacyTierToRarity[value]
end

function Rarities.Normalize(value: unknown): Rarity?
	if type(value) ~= "string" then
		return nil
	end
	local trimmed = string.match(value, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return nil
	end
	return canonicalByLower[string.lower(trimmed)]
end

function Rarities.IsValid(value: unknown): boolean
	return type(value) == "string" and canonicalByLower[string.lower(value)] == value
end

function Rarities.IsStandard(value: unknown): boolean
	local rarity = Rarities.Normalize(value)
	return rarity ~= nil and standardRankByRarity[rarity] ~= nil
end

function Rarities.GetStandardRank(value: unknown): number?
	local rarity = Rarities.Normalize(value)
	return if rarity then standardRankByRarity[rarity] else nil
end

function Rarities.GetDisplayRank(value: unknown): number?
	local rarity = Rarities.Normalize(value)
	return if rarity then displayRankByRarity[rarity] else nil
end

return table.freeze(Rarities)
]]}
E["Money"]={path="ReplicatedStorage.Shared.Utility.CurrencyDenomination",sha256="5f4cd46cc741a89e8fb09c837461c1085bce18eeaaf2aa4068685ec56c34d26e",source=[=[--!strict
-- All consumers use final units. Only source tables and supported legacy saves convert.
local Currency = {
	LEGACY_CURRENCY_VERSION = 1,
	SCALED_CURRENCY_VERSION = 2,
	CURRENCY_SCALE_FACTOR = 1500,
	MAX_AMOUNT = 9007199254740991,
}

function Currency.Validate(value: any): (boolean, string?)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge or value < 0 then
		return false, "INVALID_MONETARY_VALUE"
	end
	if value > Currency.MAX_AMOUNT then return false, "MONETARY_OVERFLOW" end
	return true, nil
end

function Currency.Convert(value: any, version: any): (number?, string?)
	if version ~= 1 and version ~= 2 then return nil, "UNSUPPORTED_CURRENCY_VERSION" end
	local valid, reason = Currency.Validate(value)
	if not valid then return nil, reason end
	if version == 2 then return value, nil end
	if value > Currency.MAX_AMOUNT / 1500 then return nil, "MONETARY_OVERFLOW" end
	local converted = value * 1500
	if not Currency.Validate(converted) then return nil, "MONETARY_OVERFLOW" end
	-- Large products have a wider representable spacing. Check the exact fractional
	-- product against that spacing rather than silently dropping saved fractions.
	if converted >= 2 ^ 46 then
		local _, exponent = math.frexp(converted)
		local spacing = 2 ^ (exponent - 53)
		if ((value % 1) * 1500) % spacing ~= 0 then
			return nil, "MONETARY_PRECISION_UNSUPPORTED"
		end
	end
	return converted, nil
end

function Currency.FromLegacy(value: number): number
	local converted, reason = Currency.Convert(value, 1)
	assert(converted ~= nil, reason)
	return converted :: number
end

-- Mutates only a private normalized working record, never a live profile.
-- The caller persists amounts and marker together under the profile lease.
function Currency.MigrateRecord(data: any): (boolean, string?, boolean?)
	local version = data.CurrencyVersion
	if version == nil then
		if data.SchemaVersion ~= 2 then return false, "UNSUPPORTED_LEGACY_SCHEMA", nil end
		version = 1
	end
	if version ~= 1 and version ~= 2 then return false, "UNSUPPORTED_CURRENCY_VERSION", nil end
	local changes = {}
	local function plan(container, key): string?
		local amount, reason = Currency.Convert(container[key], version)
		if amount == nil then return reason end
		table.insert(changes, { container, key, amount })
		return nil
	end
	local reason = plan(data.Economy, "Balance")
	if reason then return false, reason, nil end
	for _, slot in data.Base.Slots do
		reason = plan(slot, "accumulatedCash")
		if reason then return false, reason, nil end
	end
	-- No durable replayable cash receipt is present in the current schema.
	-- Transport operation IDs/revisions and audit receipts remain unchanged.
	for _, change in changes do change[1][change[2]] = change[3] end
	data.CurrencyVersion = 2
	return true, nil, version == 1
end

return table.freeze(Currency)
]=]}
E["Progression"]={path="ReplicatedStorage.Shared.Config.WorldProgression",sha256="c67e34661a03cf3f379593ed1c9b5caf59c431241805e9a5782c6de90adddfd8",source=[[--!strict
-- Prices below are FINAL denomination 2; never apply the source-table multiplier.
-- Explicit Phase 8 pools; central data does not activate a region.
local poolRows = {
	Forest = {weights={0.68,0.26,0.06,0,0,0}, exclusive="BRT_007", species={
		Common={"BRT_001","BRT_002","BRT_003","BRT_004","BRT_005","BRT_006","BRT_007","BRT_008","BRT_009","BRT_010"},
		Uncommon={"BRT_011","BRT_013"},
		Rare={"BRT_019"},
		Epic={},
		Legendary={},
		Mythic={},
	}},
	Beach = {weights={0.4,0.4,0.2,0,0,0}, exclusive="BRT_012", species={
		Common={"BRT_001","BRT_002","BRT_003","BRT_004","BRT_005","BRT_006","BRT_008","BRT_009","BRT_010"},
		Uncommon={"BRT_011","BRT_012","BRT_013","BRT_014","BRT_015"},
		Rare={"BRT_019","BRT_020"},
		Epic={},
		Legendary={},
		Mythic={},
	}},
	Swamp = {weights={0.15,0.3,0.4,0.15,0,0}, exclusive="BRT_021", species={
		Common={"BRT_001","BRT_002","BRT_003","BRT_004","BRT_005","BRT_006","BRT_008","BRT_009","BRT_010"},
		Uncommon={"BRT_011","BRT_013","BRT_014","BRT_015","BRT_016","BRT_017","BRT_018"},
		Rare={"BRT_019","BRT_020","BRT_021","BRT_022"},
		Epic={"BRT_026","BRT_028","BRT_030"},
		Legendary={},
		Mythic={},
	}},
	Jungle = {weights={0.05,0.15,0.45,0.35,0,0}, exclusive="BRT_027", species={
		Common={"BRT_008","BRT_009","BRT_010"},
		Uncommon={"BRT_014","BRT_015","BRT_016","BRT_017","BRT_018"},
		Rare={"BRT_019","BRT_020","BRT_022","BRT_023","BRT_024","BRT_025"},
		Epic={"BRT_026","BRT_027","BRT_028","BRT_030"},
		Legendary={},
		Mythic={},
	}},
	Arctic = {weights={0,0.05,0.25,0.7,0,0}, exclusive="BRT_029", species={
		Common={},
		Uncommon={"BRT_016","BRT_017","BRT_018"},
		Rare={"BRT_020","BRT_022","BRT_023","BRT_024","BRT_025"},
		Epic={"BRT_026","BRT_028","BRT_029","BRT_030"},
		Legendary={},
		Mythic={},
	}},
	Volcano = {weights={0,0,0.1,0.65,0.25,0}, exclusive="BRT_031", species={
		Common={},
		Uncommon={},
		Rare={"BRT_022","BRT_023","BRT_024","BRT_025"},
		Epic={"BRT_026","BRT_028","BRT_030"},
		Legendary={"BRT_031"},
		Mythic={},
	}},
	GlitchZone = {weights={0,0,0.05,0.35,0.6,0}, exclusive="BRT_032", species={
		Common={},
		Uncommon={},
		Rare={"BRT_023","BRT_024","BRT_025"},
		Epic={"BRT_026","BRT_028","BRT_030"},
		Legendary={"BRT_032"},
		Mythic={},
	}},
}
local homeKeys = {
	BRT_001="Forest",
	BRT_002="Forest",
	BRT_003="Forest",
	BRT_004="Forest",
	BRT_005="Forest",
	BRT_006="Forest",
	BRT_007="Forest",
	BRT_008="Forest",
	BRT_009="Forest",
	BRT_010="Forest",
	BRT_011="Forest",
	BRT_012="Beach",
	BRT_013="Forest",
	BRT_014="Beach",
	BRT_015="Beach",
	BRT_016="Swamp",
	BRT_017="Swamp",
	BRT_018="Swamp",
	BRT_019="Forest",
	BRT_020="Beach",
	BRT_021="Swamp",
	BRT_022="Swamp",
	BRT_023="Jungle",
	BRT_024="Jungle",
	BRT_025="Arctic",
	BRT_026="Swamp",
	BRT_027="Jungle",
	BRT_028="Jungle",
	BRT_029="Arctic",
	BRT_030="Jungle",
	BRT_031="Volcano",
	BRT_032="GlitchZone",
}
local rows = {
	{ "Camp", "REGION_CAMP", "Camp", 0, nil, 0, nil, nil, {0,0} },
	{ "Forest", "REGION_FOREST", "Forest", 1, nil, 0, nil, nil, {0,0} },
	{ "Beach", "REGION_BEACH", "Beach", 2, "Forest", 25000000, {"Uncommon",1}, nil, {15,25} },
	{ "Swamp", "REGION_SWAMP", "Swamp", 3, "Beach", 200000000, {"Rare",1}, {"Uncommon",3}, {45,60} },
	{ "Jungle", "REGION_JUNGLE", "Jungle", 4, "Swamp", 750000000, {"Epic",1}, {"Rare",4}, {45,75} },
	{ "Arctic", "REGION_ARCTIC", "Arctic", 5, "Jungle", 2000000000, {"Epic",2}, {"Rare",5}, {60,90} },
	{ "Volcano", "REGION_VOLCANO", "Volcano", 6, "Arctic", 4000000000, {"Legendary",1}, {"Epic",3}, {60,90} },
	{ "GlitchZone", "REGION_GLITCH", "Glitch Zone", 7, "Volcano", 10000000000, {"Legendary",2}, {"Epic",4}, {90,120} },
}
local byKey, byId, ordered = {}, {}, {}
for _, row in rows do
	local definition = {
		key=row[1], regionId=row[2], displayName=row[3], index=row[4], predecessor=row[5],
		price=row[6], branchA=row[7], branchB=row[8], targetMinutes=row[9],
	}
	if definition.branchA then table.freeze(definition.branchA) end
	if definition.branchB then table.freeze(definition.branchB) end
	table.freeze(definition.targetMinutes)
	table.freeze(definition)
	byKey[definition.key], byId[definition.regionId] = definition, definition
	table.insert(ordered, definition)
end
local pools, allowed, homes = {}, {}, {}
local tierOrder={"Common","Uncommon","Rare","Epic","Legendary","Mythic"}
for _,definition in ordered do
	local source=poolRows[definition.key]
	if not source then continue end
	local weights={Secret=0}
	for index,tier in tierOrder do
		weights[tier]=source.weights[index]
		for _,id in source.species[tier] do
			allowed[id]=allowed[id] or {} table.insert(allowed[id],definition.regionId)
		end
		table.freeze(source.species[tier])
	end
	pools[definition.regionId]=table.freeze({species=table.freeze(source.species),
		tierWeights=table.freeze(weights),exclusive=source.exclusive})
end
for id,key in homeKeys do homes[id]=byKey[key].regionId end
for _,regions in allowed do table.freeze(regions) end
return table.freeze({
	Pools=table.freeze(pools), HomeBySpecies=table.freeze(homes), AllowedBySpecies=table.freeze(allowed),
	OperationalKeys=table.freeze({"Beach","Swamp","Jungle","Arctic","Volcano","GlitchZone"}), -- Added sequentially only after each area checkpoint.
	ByKey=table.freeze(byKey), ById=table.freeze(byId), Ordered=table.freeze(ordered),
	OrdinaryRarity=table.freeze({Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6}),
	REGION_GUARD_INTERVAL_SECONDS=0.10, UNAUTHORIZED_NOTICE_COOLDOWN_SECONDS=2,
	GUEST_REVOCATION_EGRESS_SECONDS=5, GATE_PROMPT_DISTANCE_STUDS=12,
	GATE_PURCHASE_MAX_DISTANCE_STUDS=16, GATE_PROMPT_HOLD_SECONDS=0.35,
	GATE_REQUEST_MIN_INTERVAL_SECONDS=1, MAX_GATE_REQUEST_ID_LENGTH_BYTES=64,
	MAX_GATE_REGION_KEY_LENGTH_BYTES=32, CLIENT_PENDING_NOTICE_SECONDS=8,
	UNLOCK_CELEBRATION_SECONDS=1.5,
})
]]}
E["Income"]={path="ServerScriptService.Server.Systems.BaseIncomePlaqueSystem",sha256="36abfff76ed6d107ae63c7fe0b72882f2de09d1840b784f1fe04153f71320574",source=[[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config.BaseLayoutConfig)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local StaticMaterial = require(ReplicatedStorage.Shared.Utility.MapArtStaticMaterialPolicy)
local PlayerBaseSystem = require(script.Parent.PlayerBaseSystem)
local BaseStorageSystem = require(script.Parent.BaseStorageSystem)
local BrainrotIncomeSystem = require(script.Parent.BrainrotIncomeSystem)

local log = Logger.new("BaseIncomePlaqueSystem")
local PLAQUE_TAG = "BrainrotIncomePlaque"
local LAYOUT_CONTAINER_NAME = "Phase5DInterior"
local PLAQUE_CONTAINER_NAME = "IncomePlaques"
local TOUCH_SENSOR_NAME = "TouchSensor"
local AMOUNT_SURFACE_NAME = "AmountSurfaceGui"
local AMOUNT_LABEL_NAME = "AmountLabel"
local AMOUNT_STROKE_NAME = "AmountStroke"
local PLAQUE_WIDTH_STUDS = 3.5
local PLAQUE_THICKNESS_STUDS = 0.18
local PLAQUE_DEPTH_STUDS = 2.25
local PLAQUE_PLATFORM_GAP_STUDS = 0.55
local PLAQUE_FLOOR_CLEARANCE_STUDS = 0.02
local PLAQUE_SNAPSHOT_REFRESH_SECONDS = 1
local PILLAR_MANAGED_BY = "BaseIncomePlaqueSystem"
local PILLAR_ORIGINAL_WIDTH_STUDS = 1.25
local PILLAR_ORIGINAL_DEPTH_STUDS = 1.25
local PILLAR_WIDTH_STUDS = PILLAR_ORIGINAL_WIDTH_STUDS * 0.5
local PILLAR_DEPTH_STUDS = PILLAR_ORIGINAL_DEPTH_STUDS * 0.5
local PILLAR_MAX_SPACING_STUDS = 6
local ENTRANCE_CLEAR_WIDTH_STUDS = 10
local LEGACY_WALL_NAMES = table.freeze({ "LeftWall", "RightWall", "BackWall" })

local BaseIncomePlaqueSystem = {}
local started = false
local initialDependencies: any? = nil
local assignmentConnection: any? = nil
local unsubscribeStorage: (() -> ())? = nil
local snapshotConnection: RBXScriptConnection? = nil
local snapshotAccumulator = 0
local baseSystem: any = PlayerBaseSystem
local storageSystem: any = BaseStorageSystem
local incomeSystem: any = BrainrotIncomeSystem
local clock = function(): number
	return Workspace:GetServerTimeNow()
end
local getPlayerFromCharacter = function(character: Model): Player?
	return Players:GetPlayerFromCharacter(character)
end
local getPlayerByUserId = function(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end
local states: { [Model]: any } = {}
local plaqueBindings: { [BasePart]: any } = {}
local touchAttempts: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" })

local function getPlaqueName(platformId: number): string
	return "IncomePlaque_" .. tostring(platformId)
end

local function platformIdFromPart(platform: BasePart): number?
	local attribute = platform:GetAttribute("SlotIndex")
	if type(attribute) == "number" and attribute % 1 == 0 then
		return attribute
	end
	return tonumber(platform.Name:match("^Slot_(%d+)$"))
end

local function baseRootCFrame(base: Model): CFrame
	local saved = base:GetAttribute("Phase5DLayoutPivot")
	if typeof(saved) == "CFrame" then
		return saved
	end
	local root = base:GetPivot()
	base:SetAttribute("Phase5DLayoutPivot", root)
	return root
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), name .. " must be a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensurePart(base: Model, container: Folder, name: string): (BasePart, boolean)
	local existing = base:FindFirstChild(name) or container:FindFirstChild(name)
	if existing then
		assert(existing:IsA("BasePart"), name .. " must be a BasePart")
		return existing, false
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Parent = container
	return part, true
end

local function configureStructuralPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	StaticMaterial.Apply(part, Enum.Material.SmoothPlastic)
	part.Color = Color3.fromRGB(91, 98, 104)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function platformTopLocalY(root: CFrame, platform: BasePart): number
	return root:PointToObjectSpace(platform.Position).Y + platform.Size.Y / 2
end

local function entranceSign(base: Model, root: CFrame): number
	for _, name in { "CartSpawn", "PlayerSpawn" } do
		local marker = base:FindFirstChild(name)
		if marker and marker:IsA("BasePart") then
			local localZ = root:PointToObjectSpace(marker.Position).Z
			if math.abs(localZ) > 0.01 then
				return if localZ > 0 then 1 else -1
			end
		end
	end
	return -1
end

type StructuralStyle = {
	Color: Color3,
	Material: Enum.Material,
	MaterialVariant: string,
	EffectivePhysicalProperties: PhysicalProperties,
	CollisionGroup: string,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
}

local function captureStructuralStyle(part: BasePart): StructuralStyle
	return {
		Color = part.Color,
		Material = part.Material,
		MaterialVariant = part.MaterialVariant,
		EffectivePhysicalProperties = part.CurrentPhysicalProperties,
		CollisionGroup = part.CollisionGroup,
		CanCollide = part.CanCollide,
		CanTouch = part.CanTouch,
		CanQuery = part.CanQuery,
	}
end

local function legacyWall(base: Model, container: Folder, name: string): BasePart?
	local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
	return if candidate and candidate:IsA("BasePart") then candidate else nil
end

local function removeLegacyWalls(base: Model, container: Folder)
	for _, name in LEGACY_WALL_NAMES do
		local direct = base:FindFirstChild(name)
		if direct and direct:IsA("BasePart") then
			direct:Destroy()
		end
		local generated = container:FindFirstChild(name)
		if generated and generated:IsA("BasePart") then
			generated:Destroy()
		end
	end
end

local function clearManagedPillars(container: Folder)
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("ManagedBy") == PILLAR_MANAGED_BY then
			child:Destroy()
		end
	end
end

local function createPillar(
	container: Folder,
	root: CFrame,
	name: string,
	localPosition: Vector3,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle
)
	local pillar = Instance.new("Part")
	pillar.Name = name
	pillar:SetAttribute("ManagedBy", PILLAR_MANAGED_BY)
	configureStructuralPart(pillar)
	pillar.Size = Vector3.new(PILLAR_WIDTH_STUDS, pillarHeight, PILLAR_DEPTH_STUDS)
	pillar.CFrame = root
		* CFrame.new(localPosition.X, floorTopY + pillarHeight / 2, localPosition.Z)
	pillar.Color = style.Color
	pillar.Material = style.Material
	pillar.MaterialVariant = style.MaterialVariant
	pillar.CustomPhysicalProperties = style.EffectivePhysicalProperties
	pillar.CollisionGroup = style.CollisionGroup
	pillar.CanCollide = style.CanCollide
	pillar.CanTouch = style.CanTouch
	pillar.CanQuery = style.CanQuery
	StaticMaterial.Apply(pillar)
	pillar.Parent = container
end

local function createPillarsAlongEdge(
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle,
	edgeName: string,
	startLocalPosition: Vector3,
	endLocalPosition: Vector3,
	shouldSkip: ((Vector3) -> boolean)?
)
	local edgeLength = (endLocalPosition - startLocalPosition).Magnitude
	local intervalCount = math.max(1, math.ceil(edgeLength / PILLAR_MAX_SPACING_STUDS))
	local placedIndex = 0
	for interval = 1, intervalCount - 1 do
		local localPosition = startLocalPosition:Lerp(endLocalPosition, interval / intervalCount)
		if not shouldSkip or not shouldSkip(localPosition) then
			placedIndex += 1
			createPillar(
				container,
				root,
				string.format("BasePillar_%s_%02d", edgeName, placedIndex),
				localPosition,
				floorTopY,
				pillarHeight,
				style
			)
		end
	end
end

local function createPerimeterPillars(
	base: Model,
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle
)
	clearManagedPillars(container)
	-- Preserve the established perimeter centreline while reducing only each
	-- pillar's horizontal cross-section.
	local halfWidth = (Config.BASE_FOOTPRINT_WIDTH_STUDS - PILLAR_ORIGINAL_WIDTH_STUDS) / 2
	local halfDepth = (Config.BASE_FOOTPRINT_DEPTH_STUDS - PILLAR_ORIGINAL_DEPTH_STUDS) / 2
	local frontZ = entranceSign(base, root) * halfDepth
	local backZ = -frontZ
	local frontLeft = Vector3.new(-halfWidth, 0, frontZ)
	local frontRight = Vector3.new(halfWidth, 0, frontZ)
	local backLeft = Vector3.new(-halfWidth, 0, backZ)
	local backRight = Vector3.new(halfWidth, 0, backZ)

	for name, localPosition in
		{
			BasePillar_Corner_FL = frontLeft,
			BasePillar_Corner_FR = frontRight,
			BasePillar_Corner_BL = backLeft,
			BasePillar_Corner_BR = backRight,
		}
	do
		createPillar(container, root, name, localPosition, floorTopY, pillarHeight, style)
	end

	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Front",
		frontLeft,
		frontRight,
		function(localPosition)
			return math.abs(localPosition.X) < ENTRANCE_CLEAR_WIDTH_STUDS / 2
		end
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Back",
		backLeft,
		backRight,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Left",
		frontLeft,
		backLeft,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Right",
		frontRight,
		backRight,
		nil
	)
end

local function ensureInterior(base: Model, root: CFrame, platformFloorY: number): number
	local container = ensureFolder(base, LAYOUT_CONTAINER_NAME)
	local floor: BasePart? = nil
	for _, name in { "BaseFloor", "Floor", "InteriorFloor", "GroundFloor" } do
		local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
		if candidate and candidate:IsA("BasePart") then
			floor = candidate
			break
		end
	end
	local createdFloor = false
	if not floor then
		floor, createdFloor = ensurePart(base, container, "BaseFloor")
	end
	local resolvedFloor = floor :: BasePart
	local floorThickness = if createdFloor then 1 else math.max(resolvedFloor.Size.Y, 0.2)
	local floorTopY = if createdFloor
		then platformFloorY
		else platformTopLocalY(root, resolvedFloor)
	configureStructuralPart(resolvedFloor)
	resolvedFloor.Size = Vector3.new(
		Config.BASE_FOOTPRINT_WIDTH_STUDS,
		floorThickness,
		Config.BASE_FOOTPRINT_DEPTH_STUDS
	)
	resolvedFloor.CFrame = root * CFrame.new(0, floorTopY - floorThickness / 2, 0)

	local pillarStyle = captureStructuralStyle(resolvedFloor)
	local pillarHeight = Config.BASE_WALL_HEIGHT_STUDS
	for _, wallName in LEGACY_WALL_NAMES do
		local wall = legacyWall(base, container, wallName)
		if wall then
			pillarStyle = captureStructuralStyle(wall)
			pillarHeight = wall.Size.Y
			break
		end
	end
	removeLegacyWalls(base, container)
	createPerimeterPillars(base, container, root, floorTopY, pillarHeight, pillarStyle)
	return floorTopY
end

local function setMarkerFacing(slot: any, platformCFrame: CFrame, markerOffset: CFrame)
	if slot.Marker:IsA("Attachment") then
		slot.Marker.CFrame = CFrame.new(markerOffset.Position)
	else
		local marker = slot.Marker :: BasePart
		marker.CFrame = platformCFrame * CFrame.new(markerOffset.Position)
	end
end

local function positionPlatforms(root: CFrame, slots: { any }): (any, number)
	local ordered = table.clone(slots)
	table.sort(ordered, function(left, right)
		return left.Index < right.Index
	end)
	assert(#ordered == Config.PLATFORM_COUNT, "Phase 5D requires exactly 12 platforms")
	local placementById = {}
	local floorY = math.huge
	for order, slot in ordered do
		local platform = slot.Platform :: BasePart
		local platformId = platformIdFromPart(platform)
		assert(platformId == slot.Index, "Platform stable ID changed during layout")
		local topY = platformTopLocalY(root, platform)
		floorY = math.min(floorY, topY - platform.Size.Y)
		local side = if order <= Config.PLATFORMS_PER_SIDE then -1 else 1
		local row = if side < 0 then order else order - Config.PLATFORMS_PER_SIDE
		local x = side * Config.PLATFORM_ROW_OFFSET_X
		local z = Config.PLATFORM_Z_CENTERS[row]
		local localPosition = Vector3.new(x, topY - platform.Size.Y / 2, z)
		local localFacing = CFrame.lookAt(
			localPosition,
			Vector3.new(0, localPosition.Y, localPosition.Z),
			Vector3.yAxis
		)
		local markerOffset = if slot.Marker:IsA("Attachment")
			then slot.Marker.CFrame
			else platform.CFrame:ToObjectSpace((slot.Marker :: BasePart).CFrame)
		platform.Size =
			Vector3.new(Config.PLATFORM_SIDE_STUDS, platform.Size.Y, Config.PLATFORM_SIDE_STUDS)
		platform.CFrame = root * localFacing
		platform.Anchored = true
		setMarkerFacing(slot, platform.CFrame, markerOffset)
		placementById[slot.Index] = {
			Side = side,
			ZCenter = z,
			PlatformTopY = topY,
		}
	end
	assert(floorY < math.huge, "Phase 5D platforms have no usable floor datum")
	return placementById, floorY
end

local function ensureAmountView(plaque: BasePart): (SurfaceGui, TextLabel)
	for _, child in plaque:GetChildren() do
		if child.Name == "IncomeSurfaceGui" or child.Name == "AmountBillboard" then
			child:Destroy()
		end
	end

	local surface: SurfaceGui? = nil
	for _, child in plaque:GetChildren() do
		if child.Name == AMOUNT_SURFACE_NAME then
			if surface == nil and child:IsA("SurfaceGui") then
				surface = child
			else
				child:Destroy()
			end
		end
	end
	if surface == nil then
		surface = Instance.new("SurfaceGui")
		surface.Name = AMOUNT_SURFACE_NAME
		surface.Parent = plaque
	end
	local gui = surface :: SurfaceGui
	gui.Adornee = plaque
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	-- Top-face UV axes differ from the pad's forward/right axes. Rotate the
	-- label within the swapped canvas so it reads from this platform's front.
	gui.CanvasSize = Vector2.new(112, 200)
	gui.MaxDistance = 35
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.ClipsDescendants = true
	gui.ZOffset = 0
	gui.Active = false
	gui.Enabled = false

	local label = gui:FindFirstChild(AMOUNT_LABEL_NAME)
	if label and not label:IsA("TextLabel") then
		label:Destroy()
		label = nil
	end
	for _, child in gui:GetChildren() do
		if child:IsA("TextLabel") and child ~= label then
			child:Destroy()
		end
	end
	if not label then
		label = Instance.new("TextLabel")
		label.Name = AMOUNT_LABEL_NAME
		label.Parent = gui
	end
	local amount = label :: TextLabel
	amount.AnchorPoint = Vector2.new(0.5, 0.5)
	amount.Position = UDim2.fromScale(0.5, 0.5)
	amount.Size = UDim2.fromOffset(190, 72)
	amount.AutomaticSize = Enum.AutomaticSize.None
	amount.BackgroundTransparency = 1
	amount.BorderSizePixel = 0
	amount.Font = Enum.Font.FredokaOne
	amount.TextColor3 = Color3.fromRGB(255, 255, 255)
	amount.TextTransparency = 0
	amount.TextSize = 36
	amount.TextScaled = false
	amount.TextWrapped = false
	amount.TextTruncate = Enum.TextTruncate.None
	amount.TextXAlignment = Enum.TextXAlignment.Center
	amount.TextYAlignment = Enum.TextYAlignment.Center
	amount.TextStrokeTransparency = 1
	amount.RichText = false
	amount.Active = false
	amount.Selectable = false
	amount.Rotation = -90
	amount.Text = ""

	for _, child in amount:GetChildren() do
		if child:IsA("UITextSizeConstraint") or child:IsA("UIScale") then
			child:Destroy()
		end
	end
	local stroke: UIStroke? = nil
	for _, child in amount:GetChildren() do
		if child:IsA("UIStroke") then
			if stroke == nil and child.Name == AMOUNT_STROKE_NAME then
				stroke = child
			else
				child:Destroy()
			end
		end
	end
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = AMOUNT_STROKE_NAME
		stroke.Parent = amount
	end
	local outline = stroke :: UIStroke
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Color = Color3.fromRGB(8, 8, 10)
	outline.Thickness = 2
	outline.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Transparency = 0
	return gui, amount
end

local function formatCashSnapshot(value: any): string
	local safe = if type(value) == "number" and value == value and value >= 0 then value else 0
	return CurrencyFormatter.FormatCompactCash(math.floor(safe))
end

local function applyIncomeSnapshotToPlaque(
	plaque: BasePart,
	baseId: string,
	platformId: number,
	ownerUserId: number,
	snapshot: any?
)
	plaque:SetAttribute("BaseId", baseId)
	plaque:SetAttribute("PlatformId", platformId)
	plaque:SetAttribute("BaseOwnerUserId", ownerUserId)
	if snapshot then
		plaque:SetAttribute("IncomeSnapshotReady", true)
		plaque:SetAttribute("IncomeOccupied", snapshot.Occupied == true)
		plaque:SetAttribute("IncomeRatePerSecond", snapshot.RatePerSecond or 0)
		plaque:SetAttribute("UnclaimedCashSnapshot", snapshot.UnclaimedCashSnapshot or 0)
		plaque:SetAttribute("IncomeSnapshotServerTime", snapshot.SnapshotServerTime or 0)
		plaque:SetAttribute("IncomeRevision", snapshot.Revision or 0)
	else
		plaque:SetAttribute("IncomeSnapshotReady", false)
		plaque:SetAttribute("IncomeOccupied", false)
		plaque:SetAttribute("IncomeRatePerSecond", 0)
		plaque:SetAttribute("UnclaimedCashSnapshot", 0)
		plaque:SetAttribute("IncomeSnapshotServerTime", 0)
		plaque:SetAttribute("IncomeRevision", 0)
	end
	local gui, label = ensureAmountView(plaque)
	local cash = plaque:GetAttribute("UnclaimedCashSnapshot")
	local safeCash = if type(cash) == "number" and cash == cash and cash >= 0 then cash else 0
	local showAmount = plaque:GetAttribute("IncomeSnapshotReady") == true
		and plaque:GetAttribute("IncomeOccupied") == true
	label.Text = if showAmount then formatCashSnapshot(safeCash) else ""
	gui.Enabled = showAmount
end

local function candidatePlaques(base: Model): { BasePart }
	local result = {}
	for _, descendant in base:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and (
				CollectionService:HasTag(descendant, PLAQUE_TAG)
				or descendant.Name:match("^IncomePlaque_") ~= nil
			)
		then
			table.insert(result, descendant)
		end
	end
	return result
end

local function retirePlaque(plaque: BasePart)
	local binding = plaqueBindings[plaque]
	if binding and binding.TouchedConnection then
		binding.TouchedConnection:Disconnect()
	end
	plaqueBindings[plaque] = nil
	CollectionService:RemoveTag(plaque, PLAQUE_TAG)
	plaque:Destroy()
end

local function characterFromTouchedPart(part: any): Model?
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil
	end
	if part:FindFirstAncestorWhichIsA("Accessory") or part:FindFirstAncestorWhichIsA("Tool") then
		return nil
	end
	return part:FindFirstAncestorOfClass("Model")
end

function BaseIncomePlaqueSystem:HandlePlaqueTouch(plaque: BasePart, touchedPart: any): any
	local binding = plaqueBindings[plaque]
	if not started or not binding or states[binding.Base] ~= binding.State then
		return nil
	end
	local character = characterFromTouchedPart(touchedPart)
	local player = if character then getPlayerFromCharacter(character) else nil
	if
		player == nil
		or player.Parent ~= Players
		or player.Character ~= character
		or not touchedPart:IsDescendantOf(character)
	then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	-- Touched is the trigger; TouchEnded is not a reliable lifetime boundary
	-- (limbs can be removed or contacts can disappear without the callback).
	-- Bound duplicate limb notifications by time, never by a permanent latch.
	local key = binding.BaseId .. ":" .. tostring(binding.PlatformId)
	local attempts = touchAttempts[player]
	if not attempts then
		attempts = {}
		touchAttempts[player] = attempts
	end
	local now = clock()
	if now < (attempts[key] or 0) then
		return { ok = false, code = "Busy" }
	end
	attempts[key] = now + Config.PLAQUE_TOUCH_COOLDOWN_SECONDS
	local result = incomeSystem:TryClaimPlatform(player, binding.BaseId, binding.PlatformId)
	if result and result.ok then
		local snapshot = incomeSystem:GetPlatformIncomeSnapshot(binding.BaseId, binding.PlatformId)
		if snapshot then
			applyIncomeSnapshotToPlaque(
				plaque,
				binding.BaseId,
				binding.PlatformId,
				binding.OwnerUserId,
				snapshot
			)
		end
		plaque:SetAttribute("LastClaimUserId", player.UserId)
		plaque:SetAttribute("LastClaimAmount", result.paid or 0)
		plaque:SetAttribute("ClaimResetAmount", result.remainingExact or 0)
		local claimRevision = plaque:GetAttribute("ClaimRevision")
		plaque:SetAttribute(
			"ClaimRevision",
			(if type(claimRevision) == "number" then claimRevision else 0) + 1
		)
	end
	return result
end

local function bindPlaqueTouch(
	state: any,
	plaque: BasePart,
	platformId: number,
	claimSensorCFrame: CFrame
)
	local previous = plaqueBindings[plaque]
	if previous and previous.TouchedConnection then
		previous.TouchedConnection:Disconnect()
	end
	local binding = {
		State = state,
		Base = state.Base,
		BaseId = state.BaseId,
		PlatformId = platformId,
		OwnerUserId = state.OwnerUserId,
	}
	local sensor = plaque:FindFirstChild(TOUCH_SENSOR_NAME)
	if sensor and not sensor:IsA("BasePart") then
		sensor:Destroy()
		sensor = nil
	end
	if not sensor then
		sensor = Instance.new("Part")
		sensor.Name = TOUCH_SENSOR_NAME
		sensor.Parent = plaque
	end
	local touchSensor = sensor :: BasePart
	touchSensor.Size =
		Vector3.new(PLAQUE_WIDTH_STUDS, Config.PLAQUE_TOUCH_HEIGHT_STUDS, PLAQUE_DEPTH_STUDS)
	touchSensor.CFrame = claimSensorCFrame
	touchSensor.Anchored = true
	touchSensor.CanCollide = false
	touchSensor.CanTouch = true
	touchSensor.CanQuery = false
	touchSensor.Massless = true
	touchSensor.Transparency = 1
	touchSensor.CastShadow = false
	binding.Sensor = touchSensor
	binding.TouchedConnection = touchSensor.Touched:Connect(function(otherPart)
		BaseIncomePlaqueSystem:HandlePlaqueTouch(plaque, otherPart)
	end)
	plaqueBindings[plaque] = binding
	state.Plaques[platformId] = plaque
end

local function configurePlaque(
	state: any,
	plaque: BasePart,
	platformId: number,
	placement: any,
	floorTopY: number
)
	plaque.Name = getPlaqueName(platformId)
	plaque.Size = Vector3.new(PLAQUE_WIDTH_STUDS, PLAQUE_THICKNESS_STUDS, PLAQUE_DEPTH_STUDS)
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.CanTouch = false
	plaque.CanQuery = true
	plaque.Massless = true
	plaque.Color = Color3.fromRGB(60, 255, 90)
	plaque.Transparency = 0
	StaticMaterial.Apply(plaque, Enum.Material.SmoothPlastic)
	plaque.TopSurface = Enum.SurfaceType.Smooth
	plaque.BottomSurface = Enum.SurfaceType.Smooth
	local inward = Config.PLATFORM_SIDE_STUDS / 2
		+ PLAQUE_PLATFORM_GAP_STUDS
		+ PLAQUE_DEPTH_STUDS / 2
	local plaqueX = placement.Side * (Config.PLATFORM_ROW_OFFSET_X - inward)
	local plaqueY = floorTopY + PLAQUE_FLOOR_CLEARANCE_STUDS + PLAQUE_THICKNESS_STUDS / 2
	local plaquePosition =
		state.Root:PointToWorldSpace(Vector3.new(plaqueX, plaqueY, placement.ZCenter))
	local inwardDirection = state.Root:VectorToWorldSpace(Vector3.new(-placement.Side, 0, 0))
	local levelInward = Vector3.new(inwardDirection.X, 0, inwardDirection.Z).Unit
	plaque.CFrame = CFrame.lookAt(plaquePosition, plaquePosition + levelInward, Vector3.yAxis)

	-- The contact envelope follows this pad, not a second offset layout.
	local claimSensorCFrame = plaque.CFrame
		* CFrame.new(0, PLAQUE_THICKNESS_STUDS / 2 + Config.PLAQUE_TOUCH_HEIGHT_STUDS / 2, 0)
	if plaque:GetAttribute("ClaimRevision") == nil then
		plaque:SetAttribute("ClaimRevision", 0)
	end
	CollectionService:AddTag(plaque, PLAQUE_TAG)
	applyIncomeSnapshotToPlaque(plaque, state.BaseId, platformId, state.OwnerUserId, nil)
	bindPlaqueTouch(state, plaque, platformId, claimSensorCFrame)
end

local function disconnectState(state: any)
	for _, plaque in state.Plaques do
		local binding = plaqueBindings[plaque]
		if binding and binding.TouchedConnection then
			binding.TouchedConnection:Disconnect()
		end
		plaqueBindings[plaque] = nil
	end
	if state.DestroyingConnection then
		state.DestroyingConnection:Disconnect()
		state.DestroyingConnection = nil
	end
	table.clear(state.Plaques)
end

local function teardownBase(base: Model, destroyPlaques: boolean)
	local state = states[base]
	if state then
		disconnectState(state)
		states[base] = nil
	end
	for _, plaque in candidatePlaques(base) do
		if destroyPlaques then
			retirePlaque(plaque)
		else
			plaque:SetAttribute("BaseOwnerUserId", 0)
		end
	end
	table.clear(touchAttempts)
end

local function applyPendingSnapshots(pending: { any })
	if #pending == 0 then
		return
	end
	local snapshots = incomeSystem:SyncPlatformSnapshots(pending)
	for index, request in pending do
		local snapshot = snapshots[index]
		if snapshot then
			applyIncomeSnapshotToPlaque(
				request.Plaque,
				request.BaseId,
				request.PlatformId,
				request.OwnerUserId,
				snapshot
			)
		end
	end
end

local function refreshBaseSnapshots(base: Model, storage: any?, forceAll: boolean)
	local state = states[base]
	if not state then
		return
	end
	local pending = {}
	for platformId, plaque in state.Plaques do
		local snapshot = incomeSystem:GetPlatformIncomeSnapshot(state.BaseId, platformId)
		local record = if storage then storage:GetPlatformRecord(platformId) else nil
		local changed = forceAll
			or snapshot == nil
			or snapshot.Occupied ~= (record ~= nil)
			or snapshot.IndividualId ~= (if record then record.ItemId else nil)
			or snapshot.CatalogueId ~= (if record then record.BrainrotId else nil)
		if changed then
			table.insert(pending, {
				BaseId = state.BaseId,
				PlatformId = platformId,
				Plaque = plaque,
				OwnerUserId = state.OwnerUserId,
			})
			continue
		end
		if snapshot then
			applyIncomeSnapshotToPlaque(
				plaque,
				state.BaseId,
				platformId,
				state.OwnerUserId,
				snapshot
			)
		end
	end
	applyPendingSnapshots(pending)
end

local function refreshAccumulatedPlaques()
	local pending = {}
	for base, state in states do
		local player = if state.OwnerUserId ~= 0 then getPlayerByUserId(state.OwnerUserId) else nil
		local storage = if player then storageSystem:GetStorageForPlayer(player) else nil
		if storage and storage.Base == base then
			for platformId, plaque in state.Plaques do
				local current = incomeSystem:GetPlatformIncomeSnapshot(state.BaseId, platformId)
				if current and current.Occupied then
					table.insert(pending, {
						BaseId = state.BaseId,
						PlatformId = platformId,
						Plaque = plaque,
						OwnerUserId = state.OwnerUserId,
					})
				end
			end
		end
	end
	applyPendingSnapshots(pending)
end

function BaseIncomePlaqueSystem:BuildBase(base: Model, ownerUserId: number?): (boolean, string?)
	if typeof(base) ~= "Instance" or not base:IsA("Model") or base.Parent == nil then
		return false, "INVALID_BASE"
	end
	local slots = storageSystem:GetRegisteredPlatforms(base)
	if not slots or #slots ~= Config.PLATFORM_COUNT then
		return false, "INVALID_PLATFORMS"
	end
	teardownBase(base, false)
	local root = baseRootCFrame(base)
	local placementById, platformFloorY = positionPlatforms(root, slots)
	local floorTopY = ensureInterior(base, root, platformFloorY)
	local baseId = base:GetAttribute("BaseId")
	if type(baseId) ~= "string" or baseId == "" then
		return false, "INVALID_BASE_ID"
	end
	local state = {
		Base = base,
		BaseId = baseId,
		Root = root,
		OwnerUserId = ownerUserId or 0,
		Plaques = {},
	}
	states[base] = state
	local container = ensureFolder(base, PLAQUE_CONTAINER_NAME)
	local candidates = candidatePlaques(base)
	local used: { [BasePart]: boolean } = {}
	for platformId = 1, Config.PLATFORM_COUNT do
		local expectedName = getPlaqueName(platformId)
		local selected: BasePart? = nil
		for _, candidate in candidates do
			if
				not used[candidate]
				and candidate.Name == expectedName
				and (
					candidate:GetAttribute("PlatformId") == nil
					or candidate:GetAttribute("PlatformId") == platformId
				)
			then
				selected = candidate
				break
			end
		end
		if not selected then
			selected = Instance.new("Part")
			selected.Parent = container
		end
		selected.Parent = container
		used[selected] = true
		configurePlaque(state, selected, platformId, placementById[platformId], floorTopY)
	end
	for _, candidate in candidates do
		if not used[candidate] then
			retirePlaque(candidate)
		end
	end
	state.DestroyingConnection = base.Destroying:Connect(function()
		teardownBase(base, true)
	end)
	if storageSystem.RefreshPlatformDisplays then
		storageSystem:RefreshPlatformDisplays(base)
	end
	return true, nil
end

function BaseIncomePlaqueSystem:GetPlaques(base: Model): { BasePart }
	local state = states[base]
	local result = {}
	if state then
		for platformId = 1, Config.PLATFORM_COUNT do
			if state.Plaques[platformId] then
				table.insert(result, state.Plaques[platformId])
			end
		end
	end
	return result
end

function BaseIncomePlaqueSystem:Init(dependencies: any?): boolean
	if started then
		return false
	end
	initialDependencies = dependencies or {}
	return true
end

function BaseIncomePlaqueSystem:Start(dependencies: any?): boolean
	if started then
		return false
	end
	local deps = dependencies or initialDependencies or {}
	baseSystem = deps.Base or PlayerBaseSystem
	storageSystem = deps.Storage or BaseStorageSystem
	incomeSystem = deps.Income or BrainrotIncomeSystem
	clock = deps.Now or function(): number
		return Workspace:GetServerTimeNow()
	end
	getPlayerFromCharacter = deps.GetPlayerFromCharacter
		or function(character: Model): Player?
			return Players:GetPlayerFromCharacter(character)
		end
	getPlayerByUserId = deps.GetPlayerByUserId
		or function(userId: number): Player?
			return Players:GetPlayerByUserId(userId)
		end
	started = true

	for _, base in baseSystem:GetRegisteredBases() do
		local ownerUserId = base:GetAttribute("OwnerUserId")
		local built, reason = self:BuildBase(
			base,
			if type(ownerUserId) == "number" and ownerUserId ~= 0 then ownerUserId else 0
		)
		if not built then
			log:Warn("Phase 5D layout unavailable for %s: %s", base:GetFullName(), tostring(reason))
		elseif type(ownerUserId) == "number" and ownerUserId ~= 0 then
			local player = getPlayerByUserId(ownerUserId)
			local storage = if player then storageSystem:GetStorageForPlayer(player) else nil
			if storage then
				refreshBaseSnapshots(base, storage, true)
			end
		end
	end

	assignmentConnection = baseSystem:SubscribeAssignments(function(player, base)
		local built, reason = self:BuildBase(base, player.UserId)
		if not built then
			log:Warn("Phase 5D assignment layout failed: %s", tostring(reason))
			return
		end
		local storage = storageSystem:GetStorageForPlayer(player)
		if storage then
			refreshBaseSnapshots(base, storage, true)
		end
	end, function(_, base)
		teardownBase(base, false)
	end)

	unsubscribeStorage = storageSystem:ObserveStorage({
		OnBound = function(player, storage)
			local base = storage.Base
			if not states[base] then
				self:BuildBase(base, player.UserId)
			end
			local state = states[base]
			if state then
				state.OwnerUserId = player.UserId
				for _, binding in plaqueBindings do
					if binding.State == state then
						binding.OwnerUserId = player.UserId
					end
				end
				refreshBaseSnapshots(base, storage, true)
			end
		end,
		OnCommitted = function(_, storage)
			refreshBaseSnapshots(storage.Base, storage, false)
		end,
		OnReleasing = function(_, storage)
			refreshBaseSnapshots(storage.Base, storage, false)
		end,
	})
	if deps.ConnectSnapshotRefresh ~= false then
		local heartbeat = deps.Heartbeat or RunService.Heartbeat
		snapshotAccumulator = 0
		snapshotConnection = heartbeat:Connect(function(deltaTime)
			snapshotAccumulator += deltaTime
			if snapshotAccumulator >= PLAQUE_SNAPSHOT_REFRESH_SECONDS then
				snapshotAccumulator %= PLAQUE_SNAPSHOT_REFRESH_SECONDS
				refreshAccumulatedPlaques()
			end
		end)
	end
	return true
end

function BaseIncomePlaqueSystem:Destroy(): boolean
	if assignmentConnection then
		assignmentConnection:Disconnect()
		assignmentConnection = nil
	end
	if unsubscribeStorage then
		unsubscribeStorage()
		unsubscribeStorage = nil
	end
	if snapshotConnection then
		snapshotConnection:Disconnect()
		snapshotConnection = nil
	end
	snapshotAccumulator = 0
	local bases = {}
	for base in states do
		table.insert(bases, base)
	end
	for _, base in bases do
		teardownBase(base, false)
	end
	table.clear(plaqueBindings)
	table.clear(touchAttempts)
	started = false
	initialDependencies = nil
	baseSystem, storageSystem, incomeSystem =
		PlayerBaseSystem, BaseStorageSystem, BrainrotIncomeSystem
	clock = function(): number
		return Workspace:GetServerTimeNow()
	end
	getPlayerFromCharacter = function(character: Model): Player?
		return Players:GetPlayerFromCharacter(character)
	end
	getPlayerByUserId = function(userId: number): Player?
		return Players:GetPlayerByUserId(userId)
	end
	return true
end

return BaseIncomePlaqueSystem
]]}
E["Storage"]={path="ServerScriptService.Server.Systems.BaseStorageSystem",sha256="4e15a4c21d452ad72e481083b058a97009c2a5fd865c5e074b9bc726ee71e45d",source=[[--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local BaseStorage = require(script.Parent.Parent.Classes.BaseStorage)
local PlayerBaseSystem = require(script.Parent.PlayerBaseSystem)
local CartService = require(script.Parent.Parent.Services.CartService)
local CartCargoService = require(script.Parent.Parent.Services.CartCargoService)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local BrainrotDisplayMetadata = require(ReplicatedStorage.Shared.Utility.BrainrotDisplayMetadata)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)
local BankedBrainrotService = require(script.Parent.Parent.Services.BankedBrainrotService)

local EXPECTED_SLOT_COUNT = 12
local PLACEMENT_GAP = 0.05
local log = Logger.new("BaseStorageSystem")
local Trace = require(script.Parent.Parent.Utility.BrainrotDiagnostics)
local BaseStorageSystem = {}
local started = false
local lifecycleConnection: any = nil
local profileReadyConnection: any = nil
local profileOwner: any? = PlayerDataService
local registered: { [Model]: any } = {}
local assignments: { [Model]: any } = {}
local busyCarts: { [Model]: boolean } = {}
local busyStorage: { [any]: boolean } = {}
local observers: { [any]: any } = {}
local notifying = false
local PLATFORM_TAG = "BrainrotStoragePlatform"
local platformSlots: { [BasePart]: any } = {}
local preparedPlacements: { [any]: any } = {}
local restoreAssignment: (any, number?) -> ()

local function publishOccupancy(current: any)
	for _, slot in registered[current.Storage.Base] or {} do
		local record = current.Storage:GetPlatformRecord(slot.Index)
		slot.Platform:SetAttribute("StorageOccupied", record ~= nil)
		slot.Platform:SetAttribute("StorageItemId", if record then record.ItemId else nil)
		slot.Platform:SetAttribute("StorageBrainrotId", if record then record.BrainrotId else nil)
	end
end

-- Domain-specific, synchronous read-only observers. Never yield or mutate inventory.
function BaseStorageSystem:ObserveStorage(observer: any): () -> ()
	local key = {}
	observers[key] = observer
	Trace.Emit("BOOT", "storage_observer_registered", function()
		return {
			observer = Trace.Id(key),
			onBound = observer.OnBound ~= nil,
			onChanging = observer.OnChanging ~= nil,
			onCommitted = observer.OnCommitted ~= nil,
			onReleasing = observer.OnReleasing ~= nil,
		}
	end)
	return function()
		observers[key] = nil
		Trace.Forget(key)
	end
end

local function notify(kind: string, current: any, revision: number?, snapshot: any?)
	-- Presentation mirrors never decide ownership or slot availability.
	local mirrored, mirrorError = pcall(publishOccupancy, current)
	if not mirrored then
		log:Warn("Storage occupancy mirror failed: %s", tostring(mirrorError))
	end
	Trace.Emit("5C", "notification_enter", function()
		local f = Trace.Fields(current.Player, nil, current.Storage)
		f.kind, f.snapshotCount, f.notificationAtMs =
			kind, snapshot and #snapshot or "none", math.floor(os.clock() * 1000)
		f.changeTimestampSource = "income_callback_samples_existing_nowMs"
		return f
	end)
	local wasNotifying = notifying
	notifying = true
	for _, observer in observers do
		local callback = observer[kind]
		if callback then
			Trace.Emit("5C", "observer_enter", function()
				return {
					kind = kind,
					storage = Trace.Id(current.Storage),
					storageRevision = revision or "none",
				}
			end)
			local ok, failure = pcall(callback, current.Player, current.Storage, revision, snapshot)
			Trace.Emit("5C", "observer_exit", {
				kind = kind,
				result = if ok then "returned" else "exception",
				error = if ok then "none" else tostring(failure),
			}, not ok)
			if not ok then
				log:Warn(
					"Storage %s observer failed BaseId=%s: %s",
					kind,
					current.Storage.BaseId,
					tostring(failure)
				)
			end
		end
	end
	notifying = wasNotifying
	Trace.Emit(
		"5C",
		"notification_exit",
		{ kind = kind, result = "dispatch_complete", notifying = notifying }
	)
end

local function freezeSnapshot(value: any): any
	for _, child in value do
		if type(child) == "table" then
			freezeSnapshot(child)
		end
	end
	return table.freeze(value)
end

local function validSlot(base: Model, slot: BaseStorage.SlotDescriptor): boolean
	return base:IsDescendantOf(Workspace)
		and slot.Platform.Parent == base
		and slot.Marker.Parent == slot.Platform
		and slot.Marker.Name == "BrainrotPlacement"
		and (slot.Platform:GetAttribute("SlotIndex") or tonumber(
			slot.Platform.Name:match("^Slot_(%d+)$")
		)) == slot.Index
		and (slot.Marker:IsA("Attachment") or slot.Marker:IsA("BasePart"))
end

local function collectSlots(base: Model): (any?, string?)
	local descriptors = {}
	for _, platform in base:GetChildren() do
		local namedIndex = tonumber(platform.Name:match("^Slot_(%d+)$"))
		local attributeIndex = platform:GetAttribute("SlotIndex")
		local index = attributeIndex or namedIndex
		if index == nil then
			continue
		end
		local path = platform:GetFullName()
		if
			type(index) ~= "number"
			or index % 1 ~= 0
			or index < 1
			or index > EXPECTED_SLOT_COUNT
		then
			return nil, string.format("%s invalid slot index %s", path, tostring(index))
		end
		if namedIndex and namedIndex ~= index then
			return nil, string.format("%s conflicting slot index %s", path, tostring(index))
		end
		if descriptors[index] ~= nil or not platform:IsA("BasePart") then
			return nil, string.format("%s duplicate/unsupported slot %d", path, index)
		end
		local marker = platform:FindFirstChild("BrainrotPlacement")
		if marker == nil or not (marker:IsA("Attachment") or marker:IsA("BasePart")) then
			return nil,
				string.format("%s slot %d needs BrainrotPlacement Attachment/Part", path, index)
		end
		local slot = { Index = index, Platform = platform, Marker = marker }
		if not validSlot(base, slot) then
			return nil,
				string.format("%s slot %d marker belongs to another base/platform", path, index)
		end
		descriptors[index] = table.freeze(slot)
	end
	for index = 1, EXPECTED_SLOT_COUNT do
		if descriptors[index] == nil then
			return nil, string.format("%s missing slot %d", base:GetFullName(), index)
		end
	end
	return table.freeze(descriptors), nil
end

local function registerBase(base: Model)
	if registered[base] ~= nil then
		return
	end
	local slots, reason = collectSlots(base)
	registered[base] = slots or false
	Trace.Emit("BOOT", "slots_registered", function()
		return {
			base = base,
			baseId = base:GetAttribute("BaseId"),
			slotCount = slots and #slots or 0,
			reason = reason or "ready",
		}
	end, slots == nil)
	if slots then
		for index, slot in slots do
			platformSlots[slot.Platform] = { Base = base, Slot = slot }
			CollectionService:AddTag(slot.Platform, PLATFORM_TAG)
			slot.Platform:SetAttribute("StorageOccupied", false)
			Trace.Emit("BOOT", "slot_inventory", function()
				return {
					baseId = base:GetAttribute("BaseId"),
					slot = index,
					platform = slot.Platform,
					marker = slot.Marker,
					valid = validSlot(base, slot),
					occupancy = "unbound",
				}
			end)
		end
	end
	if not slots then
		log:Warn(
			"Storage disabled for BaseId=%s: %s",
			tostring(base:GetAttribute("BaseId")),
			reason or "invalid platforms"
		)
	end
end

local function sameAssignment(left: any, right: any): boolean
	return left ~= nil
		and right ~= nil
		and left.Player == right.Player
		and left.Base == right.Base
		and left.Generation == right.Generation
end

local function releaseAssignment(player: Player, base: Model, handle: any?)
	local current = assignments[base]
	Trace.Emit("5C", "storage_release_enter", function()
		return {
			userId = player.UserId,
			base = base,
			assignmentMatches = current ~= nil and current.Player == player,
		}
	end)
	if
		current == nil
		or current.Player ~= player
		or (handle ~= nil and not sameAssignment(current.Assignment, handle))
	then
		return
	end
	notify("OnReleasing", current)
	-- Invalidate lookup and storage before ownership can offer this physical base again.
	assignments[base] = nil
	current.Storage:Destroy()
	publishOccupancy(current)
	if current.CreatedContainer and current.Container and #current.Container:GetChildren() == 0 then
		current.Container:Destroy()
	end
end

local function bindAssignment(player: Player, base: Model, suppliedHandle: any?)
	if not PlayerBaseSystem:IsOwner(player, base) then
		return
	end
	local handle = suppliedHandle or PlayerBaseSystem:GetAssignment(player)
	if handle == nil or not PlayerBaseSystem:IsCurrentAssignment(handle) then
		return
	end
	local slots = registered[base]
	if not slots then
		return
	end
	local current = assignments[base]
	if
		current
		and current.Player == player
		and current.Storage:IsActive()
		and sameAssignment(current.Assignment, handle)
	then
		return
	end
	if current then
		releaseAssignment(current.Player, base)
	end
	local profileData = if profileOwner then profileOwner:GetWritableData(player) else nil
	if profileOwner and profileData == nil then
		return
	end
	-- Both ProfileReady and assignment callbacks can reach this binder before
	-- PlayerWorldLifecycle. Resolve crash-retained ownership before any display
	-- or income source is exposed, once per exact profile session. Legacy isolated
	-- non-session fixture adapters have no persistent acquisition to reconcile.
	if profileOwner and profileOwner.GetSessionHandle and profileOwner.IsCurrentSessionHandle then
		local result = BankedBrainrotService:ReconcileInitialOwnedLocations(player, profileOwner)
		if result.ok ~= true then
			log:Warn(
				"Initial owned-location reconciliation blocked userId=%d code=%s",
				player.UserId,
				tostring(result.code)
			)
			return
		end
	end
	assignments[base] = {
		Player = player,
		Assignment = handle,
		Storage = BaseStorage.new(base, player.UserId, slots, profileData),
		Ready = false,
	}
	restoreAssignment(assignments[base])
	if assignments[base] == nil or not sameAssignment(assignments[base].Assignment, handle) then
		return
	end
	assignments[base].Ready = true
	Trace.Emit("5C", "storage_bound", function()
		return Trace.Fields(player, nil, assignments[base].Storage)
	end)
	notify("OnBound", assignments[base])
end

function BaseStorageSystem:GetStorageForPlayer(player: Player): any?
	local base = PlayerBaseSystem:GetBase(player)
	local current = if base then assignments[base] else nil
	if
		current
		and current.Player == player
		and current.Storage:IsActive()
		and current.Ready == true
		and PlayerBaseSystem:IsOwner(player, base :: Model)
	then
		return current.Storage
	end
	return nil
end

function BaseStorageSystem:GetBindingHandle(player: Player): any?
	local base = PlayerBaseSystem:GetBase(player)
	local current = if base then assignments[base] else nil
	if
		current == nil
		or current.Player ~= player
		or current.Ready ~= true
		or not current.Storage:IsActive()
		or not PlayerBaseSystem:IsCurrentAssignment(current.Assignment)
	then
		return nil
	end
	return current.Assignment
end

function BaseStorageSystem:EnsureBound(
	player: Player,
	base: Model,
	assignmentHandle: any
): (boolean, string?)
	if
		assignmentHandle == nil
		or assignmentHandle.Player ~= player
		or assignmentHandle.Base ~= base
		or not PlayerBaseSystem:IsCurrentAssignment(assignmentHandle)
	then
		return false, "STALE_ASSIGNMENT"
	end
	bindAssignment(player, base, assignmentHandle)
	local current = assignments[base]
	if
		current ~= nil
		and current.Player == player
		and current.Ready == true
		and sameAssignment(current.Assignment, assignmentHandle)
	then
		return true, nil
	end
	return false,
		if profileOwner and profileOwner:GetWritableData(player) == nil
			then "PROFILE_NOT_READY"
			else "BIND_FAILED"
end

-- Server-only read access for physical presentation owners. The descriptors and
-- their contained slot records are frozen during registration; inventory authority
-- remains in BaseStorage.
function BaseStorageSystem:GetRegisteredPlatforms(base: Model): any?
	local slots = registered[base]
	return if type(slots) == "table" then slots else nil
end

-- Resolve only registered physical brainrot slots, never a slab/cart platform,
-- colour, arbitrary descendant name or a client-supplied base identity.
function BaseStorageSystem:ResolvePlatform(player: Player, platform: any): (any?, any?, string?)
	if typeof(platform) ~= "Instance" or not platform:IsA("BasePart") then
		return nil, nil, "INVALID_PLATFORM"
	end
	local registeredSlot = platformSlots[platform]
	local storage = self:GetStorageForPlayer(player)
	if not registeredSlot then
		return nil, nil, "INVALID_PLATFORM"
	end
	if not storage or storage.Base ~= registeredSlot.Base then
		return nil, nil, "NOT_OWNER"
	end
	if storage:IsProfileBacked() and not profileOwner:IsWritable(player) then
		return nil, nil, "PROFILE_NOT_READY"
	end
	if not validSlot(storage.Base, registeredSlot.Slot) then
		return nil, nil, "INVALID_PLATFORM"
	end
	return registeredSlot.Slot, storage, nil
end

function BaseStorageSystem:GetPlatformRecord(base: Model, platform: BasePart): any?
	local binding, current = platformSlots[platform], assignments[base]
	if not binding or binding.Base ~= base or not current then
		return nil
	end
	return current.Storage:GetPlatformRecord(binding.Slot.Index)
end

-- Server-only exact-slot transfer used by the existing carry interaction. The
-- pre-change notification settles the outgoing occupant at this boundary; the
-- platform ledger itself is never cleared or moved with the individual.
function BaseStorageSystem:TryRemoveFromPlatform(
	player: Player,
	platform: any,
	expectedItemId: any
): (any?, string?)
	if notifying then
		return nil, "BUSY"
	end
	local slot, storage, reason = self:ResolvePlatform(player, platform)
	if not slot or not storage then
		return nil, reason
	end
	if busyStorage[storage] then
		return nil, "BUSY"
	end
	local mutationToken
	mutationToken, reason = storage:TryBeginPlatformMutation(slot.Index)
	if not mutationToken then
		return nil, reason
	end
	local current = assignments[storage.Base]
	local before = storage:GetPlatformRecord(slot.Index)
	if
		current == nil
		or current.Player ~= player
		or before == nil
		or type(expectedItemId) ~= "string"
		or before.ItemId ~= expectedItemId
	then
		storage:EndPlatformMutation(slot.Index, mutationToken)
		return nil, if before == nil then "EMPTY" else "STALE_ID"
	end

	busyStorage[storage] = true
	local removed: any? = nil
	local ok, failure = xpcall(function()
		-- Income observes the still-occupied slot here and settles through the
		-- current server-time boundary before the occupant is cleared.
		notify("OnChanging", current)
		local display
		if storage:IsProfileBacked() then
			local mutation = profileOwner:CommitMutation(player, function(data)
				if not storage:IsBoundToProfile(data) then
					return false, { ok = false, code = "PROFILE_SOURCE_CHANGED" }
				end
				local record, currentDisplay, removeReason =
					storage:RemovePlatformRecord(slot.Index, expectedItemId)
				if not record then
					return false, { ok = false, code = removeReason or "SOURCE_CHANGED" }
				end
				return true, { ok = true, record = record, display = currentDisplay }
			end)
			if mutation.ok then
				removed, display = mutation.record, mutation.display
			else
				reason = mutation.code
			end
		else
			removed, display, reason = storage:RemovePlatformRecord(slot.Index, expectedItemId)
		end
		if removed == nil then
			return
		end
		notify("OnCommitted", current, storage:GetRevision(), freezeSnapshot(storage:GetSnapshot()))
		if display and display.Parent then
			local destroyed, destroyError = pcall(function()
				display:Destroy()
			end)
			if not destroyed then
				log:Warn(
					"Committed platform display cleanup %s failed: %s",
					tostring(expectedItemId),
					tostring(destroyError)
				)
			end
		end
	end, debug.traceback)
	busyStorage[storage] = nil
	storage:EndPlatformMutation(slot.Index, mutationToken)
	if not ok then
		log:Warn("Platform removal %s failed: %s", tostring(expectedItemId), tostring(failure))
		return nil, "INTERNAL_ERROR"
	end
	return removed, if removed then nil else reason
end

local function context(player: Player, cart: Model, expected: any): (any?, string?)
	if player.Parent ~= Players or cart.Parent == nil or CartService:GetCart(player) ~= cart then
		Trace.Emit("5C", "item_context_reject", function()
			return {
				reason = "player_or_cart_changed",
				playerPresent = player.Parent == Players,
				cartLive = cart.Parent ~= nil,
				currentCartMatches = CartService:GetCart(player) == cart,
			}
		end, true)
		return nil, "INVALID_CONTEXT"
	end
	local record = CartService:GetCartRecordByOwnerUserId(player.UserId)
	if record == nil or record.Model ~= cart or record.OwnerUserId ~= player.UserId then
		Trace.Emit("5C", "item_context_reject", {
			reason = "cart_record_or_owner",
			recordMatches = record ~= nil and record.Model == cart,
			cartOwner = record and record.OwnerUserId or "none",
		}, true)
		return nil, "INVALID_CONTEXT"
	end
	local base = PlayerBaseSystem:GetBase(player)
	if base == nil or not PlayerBaseSystem:IsOwner(player, base) then
		Trace.Emit(
			"5C",
			"item_context_reject",
			{ reason = "base_missing_or_not_owned", base = base or "none" },
			true
		)
		return nil, "INVALID_CONTEXT"
	end
	if registered[base] == false then
		Trace.Emit(
			"5C",
			"item_context_reject",
			{ reason = "platform_registration_failed", base = base },
			true
		)
		return nil, "INVALID_PLATFORM"
	end
	local current = assignments[base]
	if
		current == nil
		or current.Player ~= player
		or current.Storage ~= expected
		or not current.Storage:IsActive()
		or current.Storage.OwnerUserId ~= player.UserId
		or current.Storage.BaseId ~= base:GetAttribute("BaseId")
	then
		Trace.Emit("5C", "item_context_reject", function()
			return {
				reason = "storage_assignment_changed",
				assignmentPresent = current ~= nil,
				playerMatches = current ~= nil and current.Player == player,
				storageMatches = current ~= nil and current.Storage == expected,
				active = current ~= nil and current.Storage:IsActive(),
				owner = current and current.Storage.OwnerUserId or "none",
				expectedStorage = Trace.Id(expected),
				actualStorage = Trace.Id(current and current.Storage),
				baseId = base:GetAttribute("BaseId"),
				storedBaseId = current and current.Storage.BaseId or "none",
			}
		end, true)
		return nil, "INVALID_CONTEXT"
	end
	if current.Storage:IsProfileBacked() and not profileOwner:IsWritable(player) then
		return nil, "PROFILE_NOT_READY"
	end
	return current, nil
end

local function containerFor(current: any): Folder
	if current.Container then
		assert(current.Container.Parent == current.Storage.Base, "Storage display container moved")
		return current.Container
	end
	local existing = current.Storage.Base:FindFirstChild("StoredBrainrots")
	if existing then
		assert(existing:IsA("Folder"), "StoredBrainrots must be a Folder")
		current.Container = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = "StoredBrainrots"
		folder.Parent = current.Storage.Base
		current.Container = folder
		current.CreatedContainer = true
	end
	return current.Container
end

local function placeDisplayAtSlot(display: Model, slot: BaseStorage.SlotDescriptor): (any, any)
	local placement = if slot.Marker:IsA("Attachment")
		then slot.Marker.WorldCFrame
		else slot.Marker.CFrame
	local facing = display:GetAttribute("DisplayFacingOffset")
	if typeof(facing) == "CFrame" then
		placement *= facing
	end
	local pivotToBounds, size, boundsReason = BrainrotVisualScale.GetVisualBounds(display)
	assert(pivotToBounds and size, boundsReason)
	display:PivotTo(
		placement * CFrame.new(0, size.Y / 2 + PLACEMENT_GAP, 0) * pivotToBounds:Inverse()
	)
	return placement, size
end

local function prepareDisplay(item: any, slot: BaseStorage.SlotDescriptor): Model?
	Trace.Emit(
		"5C",
		"display_prepare_enter",
		{ itemId = item.ItemId, species = item.BrainrotId, slot = slot.Index, marker = slot.Marker }
	)
	local display = CartCargoService:CreateItemVisual(item.BrainrotId)
	if display == nil then
		return nil
	end
	local ok, failure = pcall(function()
		display.Name = "Stored_" .. item.ItemId
		display:SetAttribute("ItemId", item.ItemId)
		display:SetAttribute("BrainrotId", item.BrainrotId)
		display:SetAttribute("SlotIndex", slot.Index)
		BrainrotDisplayMetadata.SetIdentity(display, item)
		for _, part in display:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
		local placement, size = placeDisplayAtSlot(display, slot)
		Trace.Emit("5C", "display_prepare_exit", function()
			return {
				display = display,
				markerTransform = placement,
				boundsSize = size,
				calculatedPivot = display:GetPivot(),
				actualPivot = display:GetPivot(),
				anchored = true,
				canCollide = false,
				result = "prepared",
			}
		end)
	end)
	if not ok then
		Trace.Emit(
			"5C",
			"display_prepare_error",
			{ error = tostring(failure), committed = false },
			true
		)
		display:Destroy()
		log:Warn("Display preparation failed for %s: %s", item.ItemId, tostring(failure))
		return nil
	end
	return display
end

restoreAssignment = function(current: any, onlySlotIndex: number?)
	local storage = current.Storage
	if not profileOwner then
		return
	end
	local profileData = profileOwner:GetReadableData(current.Player)
	if
		not storage:IsProfileBacked()
		or not storage:IsBoundToProfile(profileData)
		or type(profileData.Collection) ~= "table"
		or type(profileData.Collection.BrainrotInstances) ~= "table"
	then
		return
	end
	local owned = profileData.Collection.BrainrotInstances
	for _, slot in registered[storage.Base] do
		if onlySlotIndex ~= nil and slot.Index ~= onlySlotIndex then
			continue
		end
		if
			assignments[storage.Base] ~= current
			or not PlayerBaseSystem:IsCurrentAssignment(current.Assignment)
		then
			return
		end
		local slotData = profileData.Base.Slots[tostring(slot.Index)]
		local individualId = slotData and slotData.brainrotId
		if type(individualId) ~= "string" then
			continue
		end
		local saved = owned[individualId]
		if type(saved) ~= "table" or type(saved.speciesId) ~= "string" then
			continue
		end
		local item = {
			ItemId = individualId,
			BrainrotId = saved.speciesId,
			Metadata = if type(saved.metadata) == "table" then saved.metadata else {},
		}
		local display = prepareDisplay(item, slot)
		if
			assignments[storage.Base] ~= current
			or not PlayerBaseSystem:IsCurrentAssignment(current.Assignment)
		then
			if display then
				display:Destroy()
			end
			return
		end
		if display then
			display.Parent = containerFor(current)
		end
		local bound, reason =
			storage:BindRestoredRecord(slot.Index, item, display, onlySlotIndex ~= nil)
		if not bound then
			if display then
				display:Destroy()
			end
			log:Warn("Saved slot %d restoration rejected: %s", slot.Index, tostring(reason))
		elseif display then
			BrainrotDisplayMetadata.Apply(
				display,
				item,
				BrainrotDisplayConfig.States.Deposited,
				nil
			)
		else
			log:Warn(
				"Saved individual %s (%s) retained without a display asset",
				individualId,
				saved.speciesId
			)
		end
	end
end

-- Death/reset has already committed this exact owned individual to a logical
-- slot. Bind that source once through the existing display/income boundary;
-- this is not another deposit, ownership grant, or profile mutation.
function BaseStorageSystem:BindReturnedOwnedIndividual(
	player: Player,
	slotId: string,
	individualId: string
): (boolean, string?)
	local storage = self:GetStorageForPlayer(player)
	local slotIndex = tonumber(slotId)
	if not storage or not storage:IsValidPlatformId(slotIndex) then
		return false, "STORAGE_NOT_READY"
	end
	local current = assignments[storage.Base]
	if not current or not PlayerBaseSystem:IsCurrentAssignment(current.Assignment) then
		return false, "STALE_ASSIGNMENT"
	end
	local existing = storage:GetPlatformRecord(slotIndex)
	if existing then
		return existing.ItemId == individualId,
			if existing.ItemId == individualId then "ALREADY_BOUND" else "SOURCE_CHANGED"
	end
	local data = profileOwner and profileOwner:GetReadableData(player)
	if not storage:IsBoundToProfile(data) or data.Base.Slots[slotId].brainrotId ~= individualId then
		return false, "PROFILE_SOURCE_CHANGED"
	end
	if notifying or busyStorage[storage] then
		return false, "BUSY"
	end
	local token, reason = storage:TryBeginPlatformMutation(slotIndex)
	if not token then
		return false, reason
	end
	busyStorage[storage] = true
	local bound = false
	local ok, failure = xpcall(function()
		notify("OnChanging", current)
		restoreAssignment(current, slotIndex)
		local record = storage:GetPlatformRecord(slotIndex)
		bound = record ~= nil and record.ItemId == individualId
		if bound then
			notify(
				"OnCommitted",
				current,
				storage:GetRevision(),
				freezeSnapshot(storage:GetSnapshot())
			)
		end
	end, debug.traceback)
	busyStorage[storage] = nil
	storage:EndPlatformMutation(slotIndex, token)
	if not ok then
		log:Warn(
			"Committed owned return binding failed individualId=%s: %s",
			individualId,
			tostring(failure)
		)
		return false, "RESTORE_FAILED"
	end
	return bound, if bound then nil else "SOURCE_CHANGED"
end

-- A hot layout rebuild may move an anchored platform. Re-seat only known stored
-- displays at their canonical markers; their established visual scale is unchanged.
function BaseStorageSystem:RefreshPlatformDisplays(base: Model): boolean
	local current = assignments[base]
	local slots = registered[base]
	if not current or type(slots) ~= "table" or not current.Storage:IsActive() then
		return false
	end
	local container = base:FindFirstChild("StoredBrainrots")
	if not container or not container:IsA("Folder") then
		return true
	end
	for platformId, slot in slots do
		local record = current.Storage:GetPlatformRecord(platformId)
		if record then
			local display = container:FindFirstChild("Stored_" .. record.ItemId)
			if display and display:IsA("Model") then
				local ok, failure = pcall(function()
					placeDisplayAtSlot(display, slot)
					BrainrotDisplayMetadata.Apply(
						display,
						record,
						BrainrotDisplayConfig.States.Deposited,
						nil
					)
				end)
				if not ok then
					log:Warn(
						"Could not re-seat stored display %s after layout rebuild: %s",
						record.ItemId,
						tostring(failure)
					)
				end
			end
		end
	end
	return true
end

-- Internal two-stage handoff for a carried individual. Preparation may fail or
-- yield; Commit does not notify. The caller clears its source before Finish
-- publishes the existing storage revision to income observers.
function BaseStorageSystem:PrepareStoreAtPlatform(
	player: Player,
	platform: any,
	item: any
): (any?, string?)
	local slot, storage, reason = self:ResolvePlatform(player, platform)
	if not slot or not storage then
		return nil, reason
	end
	if notifying or busyStorage[storage] then
		return nil, "BUSY"
	end
	local mutationToken
	mutationToken, reason = storage:TryBeginPlatformMutation(slot.Index)
	if not mutationToken then
		return nil, reason
	end
	local reservation
	reservation, reason = storage:TryReserveSlot(item.ItemId, slot.Index)
	if not reservation then
		storage:EndPlatformMutation(slot.Index, mutationToken)
		return nil, reason
	end
	busyStorage[storage] = true
	local token = table.freeze({})
	local stage = {
		Player = player,
		Platform = platform,
		Slot = slot,
		Storage = storage,
		Current = assignments[storage.Base],
		Item = item,
		Reservation = reservation,
		MutationToken = mutationToken,
		Committed = false,
	}
	preparedPlacements[token] = stage
	local ok, failure = pcall(function()
		stage.Display = prepareDisplay(item, slot)
		assert(stage.Display, "Platform display unavailable")
		stage.Container = containerFor(stage.Current)
	end)
	if not ok then
		self:FinishPlatformPlacement(token)
		log:Warn("Platform preparation failed for %s: %s", item.ItemId, tostring(failure))
		return nil, "PREPARATION_FAILED"
	end
	return token, nil
end

function BaseStorageSystem:CommitPlatformPlacement(token: any): (boolean, string?)
	local stage = preparedPlacements[token]
	if not stage or stage.Committed then
		return false, "INVALID_CONTEXT"
	end
	local slot, storage, reason = self:ResolvePlatform(stage.Player, stage.Platform)
	if
		slot ~= stage.Slot
		or storage ~= stage.Storage
		or assignments[storage.Base] ~= stage.Current
	then
		return false, reason or "INVALID_CONTEXT"
	end
	local reservedSlot = storage:GetReservedSlot(stage.Reservation, stage.Item.ItemId)
	-- BaseStorage deliberately copies descriptors; compare the authoritative
	-- index and Instances rather than table identity across the registry boundary.
	if
		not reservedSlot
		or reservedSlot.Index ~= slot.Index
		or reservedSlot.Platform ~= slot.Platform
		or reservedSlot.Marker ~= slot.Marker
	then
		return false, "INVALID_PLATFORM"
	end
	notify("OnChanging", stage.Current)
	local ok, accepted, failure = pcall(function()
		assert(stage.Container.Parent == storage.Base, "Destination container moved")
		stage.Display.Parent = stage.Container
		assert(stage.Display:IsDescendantOf(storage.Base), "Destination display moved")
		if storage:IsProfileBacked() then
			local mutation = profileOwner:CommitMutation(stage.Player, function(data)
				if not storage:IsBoundToProfile(data) then
					return false, { ok = false, code = "PROFILE_SOURCE_CHANGED" }
				end
				local committed, commitReason =
					storage:CommitReservation(stage.Reservation, stage.Item, stage.Display)
				return committed, { ok = committed, code = commitReason }
			end)
			return mutation.ok == true, mutation.code
		end
		return storage:CommitReservation(stage.Reservation, stage.Item, stage.Display)
	end)
	-- A post-commit exception is not a failed transfer. Never retain a second
	-- carried owner or retry into another slot after durable in-session commit.
	local stored = storage:GetPlatformRecord(slot.Index)
	stage.Committed = stored ~= nil and stored.ItemId == stage.Item.ItemId
	if not ok then
		log:Warn(
			"Platform commit %s committed=%s: %s",
			stage.Item.ItemId,
			tostring(stage.Committed),
			tostring(accepted)
		)
	end
	return stage.Committed,
		if stage.Committed then nil else (if ok then failure else "COMMIT_FAILED")
end

function BaseStorageSystem:FinishPlatformPlacement(token: any)
	local stage = preparedPlacements[token]
	if not stage then
		return
	end
	preparedPlacements[token] = nil -- Exactly one finalisation/notification.
	local ok, failure = pcall(function()
		if stage.Committed then
			BrainrotDisplayMetadata.Apply(
				stage.Display,
				stage.Item,
				BrainrotDisplayConfig.States.Deposited,
				nil
			)
			notify(
				"OnCommitted",
				stage.Current,
				stage.Storage:GetRevision(),
				freezeSnapshot(stage.Storage:GetSnapshot())
			)
		elseif stage.Display then
			stage.Display:Destroy()
		end
	end)
	stage.Storage:CancelReservation(stage.Reservation)
	stage.Storage:EndPlatformMutation(stage.Slot.Index, stage.MutationToken)
	busyStorage[stage.Storage] = nil
	if not ok then
		-- Existing income Step reconciles a missed storage revision. Do not turn
		-- a notification/presentation error into a second inventory transfer.
		log:Warn(
			"Platform finalisation %s committed=%s: %s",
			stage.Item.ItemId,
			tostring(stage.Committed),
			tostring(failure)
		)
	end
end

-- Trusted server-only, single-item operation. Physical arrival belongs to Phase 5C-2.
-- All dependencies are already loaded; the complete transfer is synchronous/non-yielding.
function BaseStorageSystem:TryDepositItem(
	player: Player,
	cart: Model,
	itemId: string,
	expectedStorage: any
): any
	local traceScope = if Trace.Enabled()
		then Trace.Scope({
			userId = player.UserId,
			cartId = cart:GetAttribute("CartId") or "none",
			baseId = expectedStorage and expectedStorage.BaseId or "none",
			storage = Trace.Id(expectedStorage),
			itemId = itemId,
		})
		else nil
	local function traceEnd(result: any, committed: boolean?)
		Trace.Emit("5C", "item_end", function()
			local fields = Trace.Fields(player, cart, expectedStorage)
			fields.itemId, fields.result, fields.committed = itemId, result.code, committed == true
			fields.error = result.presentationError or "none"
			fields.cartGuard, fields.storageGuard = Trace.Id(busyCarts), Trace.Id(busyStorage)
			fields.cartGuardHeld, fields.storageGuardHeld =
				busyCarts[cart] ~= nil,
				expectedStorage ~= nil and busyStorage[expectedStorage] ~= nil
			return fields
		end, result.code == "INTERNAL_ERROR" or result.presentationError ~= nil)
		Trace.Close(traceScope)
	end
	Trace.Emit("5C", "item_enter", { notifying = notifying })
	if notifying then
		Trace.Emit(
			"5C",
			"item_reject",
			{ result = "BUSY", reason = "storage_notification_in_progress" }
		)
		traceEnd({ code = "BUSY" })
		return { ok = false, code = "BUSY", itemId = itemId }
	end
	local current, reason = context(player, cart, expectedStorage)
	if current == nil then
		traceEnd({ code = reason })
		return { ok = false, code = reason, itemId = itemId }
	end
	local storage = current.Storage
	Trace.Emit("5C", "item_guard_check", function()
		return {
			cartGuard = Trace.Id(busyCarts),
			cartKey = Trace.Id(cart),
			cartHeld = busyCarts[cart] ~= nil,
			storageGuard = Trace.Id(busyStorage),
			storageKey = Trace.Id(storage),
			storageHeld = busyStorage[storage] ~= nil,
			acquiredBy = if busyCarts[cart] or busyStorage[storage]
				then "TryDepositItem"
				else "none",
		}
	end)
	if busyCarts[cart] or busyStorage[storage] then
		Trace.Emit("5C", "item_reject", { result = "BUSY", reason = "transfer_guard_held" })
		traceEnd({ code = "BUSY" })
		return { ok = false, code = "BUSY", itemId = itemId }
	end
	busyCarts[cart] = true
	busyStorage[storage] = true
	Trace.Emit("5C", "item_guard_acquired", function()
		return {
			cartGuard = Trace.Id(busyCarts),
			cartKey = Trace.Id(cart),
			storageGuard = Trace.Id(busyStorage),
			storageKey = Trace.Id(storage),
			acquiredBy = "TryDepositItem",
		}
	end)

	local reservation, detached, display, slot, item
	local committed = false
	local result = { ok = false, code = "INTERNAL_ERROR", itemId = itemId }
	local ok, failure = xpcall(function()
		Trace.Emit("5C", "resolve_item_enter", { itemId = itemId })
		item = CartCargoService:GetCargoItem(cart, itemId)
		Trace.Emit("5C", "resolve_item_exit", function()
			return {
				itemId = itemId,
				belongsToCart = item ~= nil,
				species = item and item.BrainrotId or "none",
				attachment = item and item.AttachmentIndex or "none",
				alreadyStored = storage:ContainsItem(itemId),
			}
		end)
		if item == nil then
			result.code = if storage:ContainsItem(itemId) then "ALREADY_STORED" else "NOT_IN_CARGO"
			return
		end
		reservation, reason = storage:TryReserveSlot(itemId)
		Trace.Emit("5C", "reserve_result", function()
			local f = Trace.Fields(player, cart, storage)
			f.itemId, f.token, f.result = itemId, Trace.Id(reservation), reason or "reserved"
			return f
		end)
		if reservation == nil then
			result.code = reason
			return
		end
		slot = storage:GetReservedSlot(reservation, itemId)
		Trace.Emit("5C", "reserved_platform", function()
			return {
				slot = slot and slot.Index or "none",
				marker = slot and slot.Marker or "none",
				valid = slot ~= nil and validSlot(storage.Base, slot),
			}
		end)
		if slot == nil or not validSlot(storage.Base, slot) then
			result.code = "INVALID_PLATFORM"
			return
		end
		display = prepareDisplay(item, slot)
		if display == nil then
			result.code = "INVALID_ASSET"
			return
		end
		Trace.Emit("5C", "container_enter", { base = storage.Base })
		local container = containerFor(current)
		Trace.Emit("5C", "container_exit", { container = container })
		local stillCurrent = context(player, cart, storage)
		Trace.Emit("5C", "revalidate", function()
			return {
				contextMatches = stillCurrent == current,
				itemMatches = CartCargoService:GetCargoItem(cart, itemId) == item,
				markerValid = validSlot(storage.Base, slot),
				reservationMatches = storage:GetReservedSlot(reservation, itemId) == slot,
			}
		end)
		if stillCurrent ~= current or CartCargoService:GetCargoItem(cart, itemId) ~= item then
			result.code = "INVALID_CONTEXT"
			return
		end
		if
			not validSlot(storage.Base, slot)
			or storage:GetReservedSlot(reservation, itemId) ~= slot
		then
			result.code = "INVALID_PLATFORM"
			return
		end
		Trace.Emit("5C", "detach_enter", { itemId = itemId, attachment = item.AttachmentIndex })
		detached, reason = CartCargoService:DetachForTransfer(cart, itemId)
		Trace.Emit("5C", "detach_exit", function()
			return {
				token = Trace.Id(detached),
				result = reason or "detached",
				cargoRevision = CartCargoService:GetCargoRevision(cart),
				cargoRemaining = CartCargoService:GetCargoCount(cart),
				visualRemoval = "deferred_until_finalize",
			}
		end)
		if detached == nil then
			result.code = reason
			return
		end
		Trace.Emit("5C", "display_parent_enter", { container = container })
		display.Parent = container
		Trace.Emit("5C", "display_parent_exit", function()
			return { display = display, parent = display.Parent, pivot = display:GetPivot() }
		end)
		assert(
			container.Parent == storage.Base and display:IsDescendantOf(storage.Base),
			"Destination display container is no longer live"
		)
		notify("OnChanging", current)
		local accepted, commitReason
		if storage:IsProfileBacked() then
			local mutation = profileOwner:CommitMutation(player, function(data)
				if not storage:IsBoundToProfile(data) then
					return false, { ok = false, code = "PROFILE_SOURCE_CHANGED" }
				end
				local committedNow, reasonNow =
					storage:CommitReservation(reservation, item, display)
				return committedNow, { ok = committedNow, code = reasonNow }
			end)
			accepted, commitReason = mutation.ok == true, mutation.code
		else
			accepted, commitReason = storage:CommitReservation(reservation, item, display)
		end
		Trace.Emit(
			"5C",
			"commit_result",
			{ result = commitReason or "accepted", accepted = accepted }
		)
		if not accepted then
			result.code = commitReason or "INTERNAL_ERROR"
			return
		end
		committed = true
		result = { ok = true, code = "DEPOSITED", itemId = itemId, slotIndex = slot.Index }
	end, debug.traceback)

	-- Guaranteed cleanup is independent of the protected body. Never roll back committed truth.
	if committed then
		local notified = false
		local function committedSnapshot()
			if notified then
				return
			end
			notified = true
			notify(
				"OnCommitted",
				current,
				storage:GetRevision(),
				freezeSnapshot(storage:GetSnapshot())
			)
		end
		Trace.Emit("5C", "finalize_enter", { committed = committed })
		local finalized, accepted, presentationError = pcall(function()
			return CartCargoService:FinalizeTransfer(cart, detached, committedSnapshot)
		end)
		Trace.Emit("5C", "finalize_exit", {
			committed = committed,
			called = finalized,
			accepted = accepted,
			error = presentationError or (if not finalized then tostring(accepted) else "none"),
		}, not finalized or not accepted or presentationError ~= nil)
		-- Preserve notification even if an unexpected finalisation/presentation exception
		-- escaped after inventory commit. The income revision guard detects missed history.
		committedSnapshot()
		local displayed, displayError = pcall(function()
			BrainrotDisplayMetadata.Apply(
				display,
				item,
				BrainrotDisplayConfig.States.Deposited,
				nil
			)
		end)
		if not displayed then
			log:Warn("Committed deposit %s nametag error: %s", itemId, tostring(displayError))
		end
		if not finalized or not accepted or presentationError then
			local problem = if not finalized
				then tostring(accepted)
				else tostring(presentationError or "token finalisation rejected")
			log:Warn("Committed deposit %s presentation/finalisation error: %s", itemId, problem)
			result.presentationError = problem
		end
	else
		if detached ~= nil then
			Trace.Emit("5C", "restore_enter", { committed = committed })
			local restored, restoreResult = pcall(function()
				return CartCargoService:RestoreTransfer(cart, detached)
			end)
			Trace.Emit(
				"5C",
				"restore_exit",
				{ called = restored, result = restoreResult },
				not restored or not restoreResult
			)
			if not restored or not restoreResult then
				log:Warn(
					"Cargo rollback invariant failed for %s: %s",
					itemId,
					tostring(restoreResult)
				)
			end
		end
		if display ~= nil then
			Trace.Emit("5C", "display_cleanup_enter", { committed = committed, display = display })
			local cleaned, cleanupError = pcall(function()
				display:Destroy()
			end)
			Trace.Emit(
				"5C",
				"display_cleanup_exit",
				{ result = cleaned, error = cleanupError or "none" },
				not cleaned
			)
			if not cleaned then
				log:Warn(
					"Temporary display cleanup failed for %s: %s",
					itemId,
					tostring(cleanupError)
				)
			end
		end
	end
	if reservation ~= nil then
		local cancelled, cancelError = pcall(function()
			storage:CancelReservation(reservation)
		end)
		Trace.Emit(
			"5C",
			"reservation_cleanup_exit",
			{ result = cancelled, error = cancelError or "none", committed = committed },
			not cancelled
		)
		if not cancelled then
			log:Warn("Reservation cleanup failed for %s: %s", itemId, tostring(cancelError))
		end
	end
	Trace.Emit("5C", "item_guard_release_enter", { committed = committed })
	busyCarts[cart] = nil
	busyStorage[storage] = nil
	Trace.Emit("5C", "item_cleanup_check", function()
		local inCargo, inStorage =
			CartCargoService:GetCargoItem(cart, itemId) ~= nil, storage:ContainsItem(itemId)
		local reservationHeld = reservation ~= nil
			and storage:GetReservedSlot(reservation, itemId) ~= nil
		local displayLive = display ~= nil and display:IsDescendantOf(storage.Base)
		local mismatch = (inCargo and inStorage)
			or (inStorage and not displayLive)
			or reservationHeld
			or busyCarts[cart] ~= nil
			or busyStorage[storage] ~= nil
		if mismatch then
			Trace.Emit("5C", "invariant_disagreement", {
				itemId = itemId,
				inCargo = inCargo,
				inStorage = inStorage,
				displayLive = displayLive,
				reservationHeld = reservationHeld,
				committed = committed,
			}, true)
		end
		return {
			inCargo = inCargo,
			inStorage = inStorage,
			displayLive = displayLive,
			reservationHeld = reservationHeld,
			committed = committed,
			result = if mismatch then "mismatch" else "consistent",
			error = if ok then "none" else tostring(failure),
		}
	end, not ok)
	if not ok then
		log:Warn("Deposit %s failed before commit: %s", itemId, tostring(failure))
	end
	traceEnd(result, committed)
	return result
end

function BaseStorageSystem:Start(options: any?)
	Trace.Emit("BOOT", "storage_start", { module = script, alreadyStarted = started })
	if started then
		return
	end
	profileOwner = if options and options.Profile ~= nil then options.Profile else PlayerDataService
	started = true
	for _, base in PlayerBaseSystem:GetRegisteredBases() do
		registerBase(base)
	end
	lifecycleConnection = PlayerBaseSystem:SubscribeAssignments(bindAssignment, releaseAssignment)
	if profileOwner and profileOwner.SubscribeReady then
		profileReadyConnection = profileOwner:SubscribeReady(function(player)
			local base = PlayerBaseSystem:GetBase(player)
			if base then
				bindAssignment(player, base, PlayerBaseSystem:GetAssignment(player))
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		local base = PlayerBaseSystem:GetBase(player)
		if base then
			bindAssignment(player, base, PlayerBaseSystem:GetAssignment(player))
		end
	end
	Trace.Emit(
		"BOOT",
		"storage_ready",
		{ started = started, lifecycleSubscribed = lifecycleConnection ~= nil }
	)
end

function BaseStorageSystem:Destroy()
	if lifecycleConnection then
		lifecycleConnection:Disconnect()
		lifecycleConnection = nil
	end
	if profileReadyConnection then
		profileReadyConnection:Disconnect()
		profileReadyConnection = nil
	end
	for base, current in assignments do
		releaseAssignment(current.Player, base)
	end
	for token in preparedPlacements do
		self:FinishPlatformPlacement(token)
	end
	for platform in platformSlots do
		CollectionService:RemoveTag(platform, PLATFORM_TAG)
		platform:SetAttribute("StorageOccupied", nil)
		platform:SetAttribute("StorageItemId", nil)
		platform:SetAttribute("StorageBrainrotId", nil)
	end
	table.clear(platformSlots)
	table.clear(registered)
	table.clear(busyCarts)
	table.clear(busyStorage)
	profileOwner = PlayerDataService
	started = false
end

return BaseStorageSystem
]]}
E["Cargo"]={path="ServerScriptService.Server.Services.CartCargoService",sha256="7030175ee3cbd2d60ebd68b7a7bae2500fc5357f22313fca4f56cc296a8dcec0",source=[[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)
local CollisionGroups = require(ReplicatedStorage.Shared.Config.CollisionGroups)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local BrainrotDisplayMetadata = require(ReplicatedStorage.Shared.Utility.BrainrotDisplayMetadata)
local CargoCapacityResolver = require(ReplicatedStorage.Shared.Utility.CargoCapacityResolver)
local CartService = require(script.Parent.CartService)
local CollisionService = require(script.Parent.CollisionService)
local AssemblyValidation = require(script.Parent.CartAssemblyValidationService)
local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)

export type CargoEntry = {
	ItemId: string,
	BrainrotId: string,
	Metadata: { [string]: any },
	World: { [string]: any }?, -- Preserved restoration data; optional for legacy species-only cargo.
	AttachmentIndex: number,
}

local Trace = require(script.Parent.Parent.Utility.BrainrotDiagnostics)
local CartCargoService = {}
local cargoByCart: { [Model]: any } = {}
local started = false
local CARGO_SLOT_TAG = "BrainrotCargoSlot"
local preparedInsertions: { [any]: any } = {}
local pendingReturns: { [string]: any } = {}
local capacityOwnerStateReader: ((number) -> any?)? = nil
local capacityResolverOptions: any = nil

local function cargoCount(state: any): number
	local count = 0
	for _, entry in state.ById do
		if type(entry) == "table" then
			count += 1
		end
	end
	return count
end

local function capacityDescriptor(cart: Model): any
	return {
		cartId = cart:GetAttribute("CartId"),
		ownerUserId = cart:GetAttribute("OwnerUserId"),
		durableCartId = cart:GetAttribute("DurableCartId"),
		runtimeCart = cart,
	}
end

function CartCargoService:ResolveEffectiveCargoCapacity(cart: Model): any
	local ownerId = cart:GetAttribute("OwnerUserId")
	local ownerState = if capacityOwnerStateReader ~= nil and type(ownerId) == "number"
		then capacityOwnerStateReader(ownerId)
		else nil
	local resolverOptions = capacityResolverOptions
	if capacityOwnerStateReader == nil then
		resolverOptions = table.clone(capacityResolverOptions or {})
		resolverOptions.offers = {} -- Legacy/test carts retain their authored baseline only.
	end
	return CargoCapacityResolver.Resolve(ownerState, capacityDescriptor(cart), resolverOptions)
end

function CartCargoService:GetCargoCapacityReadiness(cart: Model): any
	local capacity = self:ResolveEffectiveCargoCapacity(cart)
	if capacity.status ~= "Ready" or type(capacity.effectiveCapacity) ~= "number" then
		return capacity
	end
	local layout = CartAssetValidator.ValidateCargoLayout(cart, capacity.effectiveCapacity)
	if layout.status ~= "Ready" then
		return table.freeze({
			status = "LayoutNotReady",
			code = "CARGO_LAYOUT_NOT_READY",
			baseCapacity = capacity.baseCapacity,
			upgradeBonus = capacity.upgradeBonus,
			effectiveCapacity = capacity.effectiveCapacity,
			appliedOfferIds = capacity.appliedOfferIds,
			blockedOfferIds = capacity.blockedOfferIds,
			layout = layout,
		})
	end
	return table.freeze({
		status = "Ready",
		code = capacity.code,
		baseCapacity = capacity.baseCapacity,
		upgradeBonus = capacity.upgradeBonus,
		effectiveCapacity = capacity.effectiveCapacity,
		appliedOfferIds = capacity.appliedOfferIds,
		blockedOfferIds = capacity.blockedOfferIds,
		layout = layout,
	})
end

function CartCargoService:ConfigureCapacity(options: any?)
	capacityOwnerStateReader = if type(options) == "table" then options.OwnerStateReader else nil
	capacityResolverOptions = if type(options) == "table" then options.ResolverOptions else nil
	for cart, state in cargoByCart do
		if cart.Parent ~= nil then
			self:ReconcileCargoCapacity(cart, "CapacityConfigurationChanged")
		else
			state.CapacitySignature = nil
		end
	end
end

-- Legacy secured records may lack restoration fields, not identity or sleep.
-- Derive only missing geometry context from the real source template; never mint
-- a new individual or impose a new sleep flag on cargo.
local function withWorldContext(record: CargoEntry, pose: CFrame): CargoEntry
	if record.World then
		return record
	end
	local definition = BrainrotCatalog.Get(record.BrainrotId)
	local modelRef = if definition
		then definition.modelRef
		elseif
			RunService:IsStudio() and string.match(record.BrainrotId, "^SPEC_")
		then record.BrainrotId
		else nil
	local assets = ReplicatedStorage:FindFirstChild("StudioAssets")
	local templates = if assets then assets:FindFirstChild("Brainrots") else nil
	local template = if templates and modelRef then templates:FindFirstChild(modelRef) else nil
	if not template or not template:IsA("Model") then
		return record -- Keep custody; a missing template may become available later.
	end
	local normalized = table.clone(record)
	local canonicalScale = BrainrotVisualScale.GetCanonicalModelScale(template)
	if canonicalScale == nil then
		return record
	end
	normalized.World = table.freeze({
		Name = template.Name,
		Scale = canonicalScale,
		SpawnPosition = table.freeze({ X = pose.X, Y = pose.Y, Z = pose.Z }),
	})
	return table.freeze(normalized)
end

local function rememberCartPose(cart: Model, state: any)
	if not cart:IsDescendantOf(Workspace) or not cart.PrimaryPart then
		return
	end
	local pose = cart:GetPivot()
	for _, n in { pose:GetComponents() } do
		if n ~= n or math.abs(n) == math.huge then
			return
		end
	end
	local bounds, size = cart:GetBoundingBox()
	local radius = (Vector2.new(bounds.X, bounds.Z) - Vector2.new(pose.X, pose.Z)).Magnitude
		+ size.Magnitude / 2
	state.LastPose, state.LastBounds = pose, { Radius = radius }
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { cart }
	params.RespectCanCollide = true
	local ground =
		Workspace:Raycast(pose.Position + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	if
		ground
		and ground.Material ~= Enum.Material.Water
		and ground.Normal.Y >= 0.98
		and (
			ground.Instance:IsA("Terrain")
			or (ground.Instance:IsA("BasePart") and ground.Instance.Anchored)
		)
	then
		state.LastSupportedPose, state.LastSupportedBounds = pose, state.LastBounds
	end
end

function CartCargoService:PrepareCartRemoval(cart: Model)
	local state = cargoByCart[cart]
	if not state then
		return
	end
	pcall(rememberCartPose, cart, state)
	-- Snapshot all records before releasing this owner's table. No clones/yields
	-- here: a Destroying callback can run after descendant geometry disappeared.
	local records = table.clone(state.Entries)
	if state.Transfer then
		table.insert(records, state.Transfer.Entry)
	end
	if state.DepartureTransfer then
		for _, removed in state.DepartureTransfer.Entries do
			table.insert(records, removed.Entry)
		end
	end
	for _, entry in records do
		if not pendingReturns[entry.ItemId] then
			pendingReturns[entry.ItemId] = {
				Record = entry,
				Pose = state.LastSupportedPose or state.LastPose,
				Bounds = state.LastSupportedBounds or state.LastBounds,
				RetryAt = 0,
			}
		end
	end
	cargoByCart[cart] = nil
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	Trace.Forget(cart)
end

function CartCargoService:ProcessPendingReturns()
	for id, pending in pendingReturns do
		if pending.Busy or os.clock() < pending.RetryAt then
			continue
		end
		pending.Busy = true
		local reason
		local ok, failure = pcall(function()
			if not pending.Pose then
				reason = "NO_LAST_POSE"
				return
			end
			if not pending.Prepared then
				pending.Record = withWorldContext(pending.Record, pending.Pose)
				pending.Prepared, reason =
					World.PrepareWorldRepresentation(pending.Record, pending.Pose)
			end
			if not pending.Prepared then
				return
			end
			local pose = World.FindSafeReleasePose(
				pending.Prepared,
				pending.Pose,
				{},
				false,
				nil,
				pending.Bounds
			)
			if not pose then
				reason = "NO_SAFE_POSE"
				return
			end
			pending.Prepared.Model:PivotTo(pose)
			local _, activationReason = World.ActivatePreparedWorld(pending.Prepared, function()
				if pendingReturns[id] ~= pending then
					return false
				end
				pendingReturns[id] = nil -- Same-ID custody changes before world publication.
				return true
			end)
			reason = activationReason
		end)
		pending.Busy = false
		if pendingReturns[id] ~= pending then
			print("[CargoReturn] Restored " .. id .. " " .. pending.Record.BrainrotId)
			continue -- Post-commit errors must not replay or delete the living model.
		end
		local errorText = tostring(if ok then reason else failure)
		if pending.Prepared and errorText ~= "NO_SAFE_POSE" then
			World.DiscardPreparedWorld(pending.Prepared)
			pending.Prepared = nil
		end
		pending.RetryAt = os.clock() + 1
		if pending.LastError ~= errorText then
			pending.LastError = errorText
			warn("[CargoReturn] Pending " .. id .. ": " .. errorText)
		end
	end
end

function CartCargoService:GetRemovalDiagnostics()
	local ids = {}
	for id in pendingReturns do
		table.insert(ids, id)
	end
	table.sort(ids)
	return table.freeze({ PendingIds = table.freeze(ids), SharedHeartbeat = started })
end

-- Exact fixture-owned teardown seam. A failed Studio test can stop between
-- PrepareCartRemoval and publication; without cancelling that one item, the
-- shared heartbeat can publish it into the next fixture's fixed world corridor.
-- Live gameplay cannot call this boundary.
function CartCargoService:CancelPendingReturnForTesting(itemId: string): (boolean, string?)
	if not RunService:IsStudio() then
		return false, "STUDIO_ONLY"
	end
	local pending = pendingReturns[itemId]
	if pending == nil then
		return false, "NOT_PENDING"
	end
	pendingReturns[itemId] = nil
	if pending.Prepared ~= nil then
		World.DiscardPreparedWorld(pending.Prepared)
		pending.Prepared = nil
	end
	return true, nil
end

-- Metadata is plain bounded item data, not a visual/Instance or a container location.
local function copyMetadata(source: { [any]: any }, freeze: boolean?, ancestors: any?): any
	local seen = ancestors or {}
	assert(not seen[source], "Cyclic cargo metadata")
	seen[source] = true
	local result = {}
	for key, value in source do
		if type(key) == "string" or type(key) == "number" then
			local kind = typeof(value)
			if kind == "table" then
				result[key] = copyMetadata(value, freeze, seen)
			elseif kind == "string" or kind == "number" or kind == "boolean" then
				result[key] = value
			end
		end
	end
	seen[source] = nil
	return if freeze then table.freeze(result) else result
end

local function getBrainrotTemplate(brainrotId: string): Model?
	local definition = BrainrotCatalog.Get(brainrotId)
	local modelRef = if definition
		then definition.modelRef
		elseif RunService:IsStudio() and string.match(brainrotId, "^SPEC_") then brainrotId
		else nil
	local assets = ReplicatedStorage:FindFirstChild("StudioAssets")
	local brainrots = if assets then assets:FindFirstChild("Brainrots") else nil
	local template = if brainrots and modelRef then brainrots:FindFirstChild(modelRef) else nil
	Trace.Emit("5C", "asset_lookup", {
		species = brainrotId,
		rawKey = brainrotId,
		canonicalKey = if definition then definition.id else "invalid",
		lookupKey = modelRef or "none",
		container = brainrots or "none",
		template = template or "none",
		templateClass = template and template.ClassName or "none",
		result = if template and template:IsA("Model") then "found" else "INVALID_ASSET",
	}, template == nil or not template:IsA("Model"))
	return if template and template:IsA("Model") then template else nil
end

local function getAuthoredCargoSlot(cart: Model, index: number): (BasePart?, CFrame?, Attachment?)
	local slot = CartAssetValidator.GetCargoSlot(cart, index)
	if slot then
		return slot.Part, slot.Attachment.WorldCFrame, slot.Attachment
	end
	return nil, nil
end

local function getCargoSlot(cart: Model, index: number): (BasePart?, CFrame?, Attachment?)
	local readiness = CartCargoService:GetCargoCapacityReadiness(cart)
	if
		readiness.status ~= "Ready"
		or type(readiness.effectiveCapacity) ~= "number"
		or index > readiness.effectiveCapacity
	then
		return nil, nil
	end
	return getAuthoredCargoSlot(cart, index)
end

local function getCargoVisualContainer(cart: Model): Folder
	local existing = cart:FindFirstChild("CargoVisuals")
	if existing then
		assert(existing:IsA("Folder"), "CargoVisuals must be a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "CargoVisuals"
	folder.Parent = cart
	return folder
end

local function getCargoVisualRoot(visual: Model): BasePart?
	if visual.PrimaryPart then
		return visual.PrimaryPart
	end
	local body = visual:FindFirstChild("Body", true)
	return if body and body:IsA("BasePart")
		then body
		else visual:FindFirstChildWhichIsA("BasePart", true)
end

-- Shared canonical, synchronous clone path for cargo and base displays.
-- No source model is moved; joints to external assemblies are discarded before parenting.
function CartCargoService:CreateItemVisual(brainrotId: string): Model?
	local template = getBrainrotTemplate(brainrotId)
	if template == nil then
		return nil
	end
	Trace.Emit("5C", "asset_clone_enter", { species = brainrotId, template = template })
	local visual = template:Clone()
	Trace.Emit("5C", "asset_clone_exit", {
		species = brainrotId,
		clone = visual or "none",
		result = if visual then "cloned" else "INVALID_ASSET",
	}, visual == nil)
	if visual == nil then
		return nil
	end
	local ok, failure = pcall(function()
		local function outside(instance: Instance?): boolean
			return instance ~= nil and not instance:IsDescendantOf(visual)
		end
		local descendants = visual:GetDescendants()
		table.insert(descendants, visual)
		for _, instance in descendants do
			for _, tag in CollectionService:GetTags(instance) do
				CollectionService:RemoveTag(instance, tag)
			end
			if instance:IsA("LuaSourceContainer") then
				instance:Destroy()
			elseif
				instance:IsA("JointInstance")
				or instance:IsA("WeldConstraint")
				or instance:IsA("NoCollisionConstraint")
			then
				if outside(instance.Part0) or outside(instance.Part1) then
					Trace.Emit("5C", "external_joint_found", {
						joint = instance,
						part0 = instance.Part0 or "none",
						part1 = instance.Part1 or "none",
						action = "existing_preparation_removes_joint",
					})
					instance:Destroy()
				end
			elseif instance:IsA("Constraint") then
				if outside(instance.Attachment0) or outside(instance.Attachment1) then
					Trace.Emit("5C", "external_constraint_found", {
						constraint = instance,
						action = "existing_preparation_removes_constraint",
					})
					instance:Destroy()
				end
			end
		end
		assert(getCargoVisualRoot(visual), "Brainrot visual has no BasePart")
		visual:SetAttribute("Captured", nil)
		local scaled, _, scaleReason =
			BrainrotVisualScale.ApplyCanonicalScale(visual, "LightweightVisual")
		assert(scaled, scaleReason)
	end)
	if not ok then
		Trace.Emit(
			"5C",
			"asset_prepare_error",
			{ error = tostring(failure), species = brainrotId },
			true
		)
		visual:Destroy()
		warn(
			string.format(
				"[Cargo] Visual preparation failed for %s: %s",
				brainrotId,
				tostring(failure)
			)
		)
		return nil
	end
	return visual
end

local function prepareCargoVisual(entry: CargoEntry): any?
	local visual = CartCargoService:CreateItemVisual(entry.BrainrotId)
	if visual == nil then
		return nil
	end
	local ok, failure = pcall(function()
		visual.Name = string.format("CargoVisual_%d_%s", entry.AttachmentIndex, entry.BrainrotId)
		visual:SetAttribute("ItemId", entry.ItemId)
		visual:SetAttribute("BrainrotId", entry.BrainrotId)
		visual:SetAttribute("Captured", true)
		visual:SetAttribute("AttachmentIndex", entry.AttachmentIndex)
		BrainrotDisplayMetadata.SetIdentity(visual, entry)
		local root = getCargoVisualRoot(visual) :: BasePart
		-- Cargo is a rigid, inert presentation, never world AI or an avatar rig.
		-- Keep this sanitisation out of the shared factory used by banked displays.
		for _, item in visual:GetDescendants() do
			if
				item:IsA("JointInstance")
				or item:IsA("WeldConstraint")
				or item:IsA("Constraint")
				or item:IsA("BodyMover")
				or item:IsA("Humanoid")
				or item:IsA("Animator")
				or item:IsA("AnimationController")
				or item:IsA("ProximityPrompt")
				or item:IsA("ClickDetector")
				or item:IsA("Beam")
				or item:IsA("Trail")
				or item:IsA("ParticleEmitter")
				or item:IsA("Sound")
			then
				item:Destroy()
			end
		end
		for _, part in visual:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.Massless = true
				part.RootPriority = -127 -- Visual only; never alter the chassis priority.
				if part ~= root then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = part
					weld.Parent = root
				end
			end
		end
		CollisionService:SetModelCollisionGroup(visual, CollisionGroups.Carts)
		local mount = Instance.new("WeldConstraint")
		mount.Name, mount.Enabled, mount.Part1, mount.Parent = "CargoMount", false, root, root
	end)
	if not ok then
		visual:Destroy()
		warn("[Cargo] Mount failed: " .. tostring(failure))
		return nil
	end
	local root = getCargoVisualRoot(visual) :: BasePart
	return { Model = visual, Root = root, Mount = root:FindFirstChild("CargoMount") }
end

-- A synchronous physical change is one existing assembly mutation, including
-- rollback. Never leave validation suppressed across a yield/ownership commit.
local function mutateCargoVisual(cart: Model, action: () -> ())
	if AssemblyValidation:GetState(cart) == nil then
		action() -- Unregistered isolated factories/tests retain their existing path.
		return
	end
	local accepted, revision, reason = AssemblyValidation:BeginMutation(cart, "cargo visual")
	assert(accepted and revision, reason or "Cart assembly is not ready")
	local ok, failure = pcall(action)
	local valid, _, validationReason =
		AssemblyValidation:CompleteMutation(cart, revision :: number, "Runtime", "cargo visual")
	assert(ok, tostring(failure))
	assert(valid, validationReason or "Cargo assembly validation failed")
end

local function destroyCargoVisual(cart: Model, visual: Model)
	if visual:IsDescendantOf(cart) and AssemblyValidation:GetState(cart) == "Valid" then
		mutateCargoVisual(cart, function()
			visual:Destroy()
		end)
	else
		visual:Destroy() -- Cleanup must remain possible during cart teardown.
	end
end

local function mountCargoVisual(prepared: any, slot: BasePart, frame: CFrame, container: Folder)
	-- Re-read the moving attachment at commit. Position before joining assemblies;
	-- never anchor, PivotTo or zero velocities on a model already welded to a cart.
	mutateCargoVisual(container.Parent :: Model, function()
		local ok, failure = pcall(function()
			prepared.Model:PivotTo(frame)
			prepared.Model.Parent = container
			prepared.Mount.Part0 = slot
			prepared.Mount.Enabled = true
		end)
		if not ok then
			prepared.Model:Destroy()
			error(tostring(failure))
		end
	end)
end

local function createCargoVisual(cart: Model, entry: CargoEntry): Model?
	-- Existing cargo remains representable for removal even if a later config or
	-- applicability change makes its slot admission-inactive.
	local slot, frame = getAuthoredCargoSlot(cart, entry.AttachmentIndex)
	if not slot or not frame then
		return nil
	end
	local prepared = prepareCargoVisual(entry)
	if not prepared then
		return nil
	end
	local ok, failure = pcall(function()
		mountCargoVisual(prepared, slot, frame, getCargoVisualContainer(cart))
	end)
	if not ok then
		prepared.Model:Destroy()
		warn("[Cargo] Mount failed: " .. tostring(failure))
		return nil
	end
	BrainrotDisplayMetadata.Apply(prepared.Model, entry, BrainrotDisplayConfig.States.Cart, nil)
	return prepared.Model
end

local function getOrCreateCargo(cart: Model): any
	local state = cargoByCart[cart]
	if state == nil then
		state = {
			Entries = {},
			ById = {},
			Occupancy = {},
			Visuals = {},
			Revision = 0,
			Transfer = nil,
			DepartureTransfer = nil,
			Insertion = nil,
			Connections = {},
		}
		cargoByCart[cart] = state
		rememberCartPose(cart, state)
		table.insert(
			state.Connections,
			cart.Destroying:Connect(function()
				CartCargoService:PrepareCartRemoval(cart)
			end)
		)
		table.insert(
			state.Connections,
			cart.AncestryChanged:Connect(function()
				if not cart:IsDescendantOf(Workspace) then
					CartCargoService:PrepareCartRemoval(cart)
				end
			end)
		)
	end
	return state
end

local function updateCargoAttributes(cart: Model, state: any)
	if cart.Parent ~= nil then
		local readiness = CartCargoService:GetCargoCapacityReadiness(cart)
		local capacity = if type(readiness.effectiveCapacity) == "number"
			then readiness.effectiveCapacity
			else 0
		local signature = table.concat({
			tostring(readiness.status),
			tostring(readiness.code),
			tostring(readiness.baseCapacity),
			tostring(readiness.upgradeBonus),
			tostring(capacity),
		}, "|")
		if state.CapacitySignature ~= nil and state.CapacitySignature ~= signature then
			state.Revision += 1
		end
		state.CapacitySignature = signature
		cart:SetAttribute("CargoCount", cargoCount(state))
		cart:SetAttribute("CargoBaseCapacity", readiness.baseCapacity)
		cart:SetAttribute("CargoUpgradeBonus", readiness.upgradeBonus)
		cart:SetAttribute("CargoCapacity", capacity)
		cart:SetAttribute("CargoCapacityStatus", readiness.status)
		cart:SetAttribute("CargoLayoutReady", readiness.status == "Ready")
		cart:SetAttribute("CargoRevision", state.Revision)
		local folder = cart:FindFirstChild("CargoSlots")
		for _, child in if folder and folder:IsA("Folder") then folder:GetChildren() else {} do
			if not child:IsA("BasePart") then
				continue
			end
			local index = tonumber(child.Name:match("^Slot([1-9]%d*)$"))
			if index == nil then
				continue
			end
			local enabled = readiness.status == "Ready" and index <= capacity
			local occupiedId = state.Occupancy[index]
			local removalOnly = not enabled and occupiedId ~= nil
			child:SetAttribute("CargoSlotId", "Slot" .. index)
			child:SetAttribute("CargoSlotEnabled", enabled)
			child:SetAttribute("CargoRemovalOnly", removalOnly)
			child:SetAttribute("CargoOccupied", occupiedId ~= nil)
			child:SetAttribute("CargoItemId", occupiedId)
			local occupant = state.ById[occupiedId]
			child:SetAttribute("CargoBrainrotId", if occupant then occupant.BrainrotId else nil)
			if enabled or removalOnly then
				CollectionService:AddTag(child, CARGO_SLOT_TAG) -- UI hints, not authority.
			elseif CollectionService:HasTag(child, CARGO_SLOT_TAG) then
				CollectionService:RemoveTag(child, CARGO_SLOT_TAG)
			end
		end
		if readiness.status == "LayoutNotReady" and state.LastLayoutWarning ~= signature then
			state.LastLayoutWarning = signature
			warn("[Cargo] Layout not ready " .. cart:GetFullName())
		end
	end
end

function CartCargoService:ReconcileCargoCapacity(cart: Model, _reason: string?): any
	local state = getOrCreateCargo(cart)
	updateCargoAttributes(cart, state)
	return self:GetCargoCapacityReadiness(cart)
end

function CartCargoService:ReconcileOwnerCapacity(ownerUserId: number, reason: string?): any?
	local record = CartService:GetCartRecordByOwnerUserId(ownerUserId)
	if record == nil or record.Model == nil then
		return nil
	end
	return self:ReconcileCargoCapacity(record.Model, reason)
end

local function ensureStarted()
	if started then
		return
	end
	started = true
	CartService:SetCargoRemovalHandler(function(cart)
		CartCargoService:PrepareCartRemoval(cart)
	end)
	CartService.CartSpawned:Connect(function(record)
		updateCargoAttributes(record.Model, getOrCreateCargo(record.Model))
	end)
	CartService.CartDespawned:Connect(function(record)
		CartCargoService:PrepareCartRemoval(record.Model) -- Idempotent fallback.
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		for cart, state in cargoByCart do
			if cargoCount(state) > 0 then
				pcall(rememberCartPose, cart, state)
			end
		end
		CartCargoService:ProcessPendingReturns()
	end)
	for _, record in CartService:GetCartRecords() do
		updateCargoAttributes(record.Model, getOrCreateCargo(record.Model))
	end
end

local function freeAttachment(cart: Model, state: any): number?
	if state.Transfer ~= nil or state.Insertion ~= nil then
		return nil
	end
	for index = 1, CartCargoService:GetCargoCapacity(cart) do
		if state.Occupancy[index] == nil and getCargoSlot(cart, index) ~= nil then
			return index
		end
	end
	return nil
end

function CartCargoService:AddCargo(
	cart: Model,
	brainrotId: string,
	metadata: { [string]: any }?
): CargoEntry?
	ensureStarted()
	if cart.Parent == nil or brainrotId == "" then
		return nil
	end
	local state = getOrCreateCargo(cart)
	local index = freeAttachment(cart, state)
	if index == nil or cargoCount(state) >= self:GetCargoCapacity(cart) then
		warn("[Cargo] Cannot add cargo: no free cargo attachment")
		return nil
	end
	local itemMetadata = copyMetadata(metadata or {}, true)
	local entry: CargoEntry = withWorldContext(
		table.freeze({
			ItemId = HttpService:GenerateGUID(false),
			BrainrotId = brainrotId,
			Metadata = itemMetadata,
			AttachmentIndex = index,
		}),
		cart:GetPivot()
	)
	table.insert(state.Entries, entry)
	state.ById[entry.ItemId] = entry
	state.Occupancy[index] = entry.ItemId
	state.Revision += 1
	updateCargoAttributes(cart, state)
	state.Visuals[entry.ItemId] = createCargoVisual(cart, entry)
	print(
		string.format(
			"[Cargo] Added %s to cart %s",
			brainrotId,
			tostring(cart:GetAttribute("CartId"))
		)
	)
	Trace.Emit("5C", "cargo_added", function()
		return {
			cartId = cart:GetAttribute("CartId"),
			cart = cart,
			itemId = entry.ItemId,
			species = brainrotId,
			attachment = index,
			cargoRevision = state.Revision,
			cargoCount = cargoCount(state),
			visual = state.Visuals[entry.ItemId] or "none",
		}
	end)
	return entry
end

function CartCargoService:GetCargoItem(cart: Model, itemId: string): CargoEntry?
	local state = cargoByCart[cart]
	return if state then state.ById[itemId] else nil
end

local function slotIndex(cart: Model, slotId: any): number?
	if type(slotId) ~= "string" or #slotId > 16 then
		return nil
	end
	local index = tonumber(slotId:match("^Slot([1-9]%d*)$"))
	return if index and index <= CartCargoService:GetCargoCapacity(cart) then index else nil
end

local function authoredSlotIndex(cart: Model, slotId: any): number?
	if type(slotId) ~= "string" or #slotId > 16 then
		return nil
	end
	local index = tonumber(slotId:match("^Slot([1-9]%d*)$"))
	return if index and CartAssetValidator.GetCargoSlot(cart, index) ~= nil then index else nil
end

local function currentCart(cart: any): boolean
	if
		typeof(cart) ~= "Instance"
		or not cart:IsA("Model")
		or not cart:IsDescendantOf(Workspace)
		or cart:GetAttribute("RuntimeCart") ~= true
	then
		return false
	end
	local ownerId = cart:GetAttribute("OwnerUserId")
	if type(ownerId) ~= "number" then
		return false
	end
	local record = CartService:GetCartRecordByOwnerUserId(ownerId)
	return record ~= nil and record.Model == cart and record.OwnerUserId == ownerId
end

function CartCargoService:CanPlayerHandleCargo(player: Player, cart: any): boolean
	-- Same authoritative owner/current-cart policy as the existing cargo transfer.
	if player.Parent ~= Players or not currentCart(cart) then
		return false
	end
	local record = CartService:GetCartRecordByOwnerUserId(player.UserId)
	return record ~= nil
		and record.Model == cart
		and record.OwnerUserId == player.UserId
		and CartService:GetCart(player) == cart
end

function CartCargoService:ResolveCargoSlot(cart: any, slotId: any): (BasePart?, Attachment?)
	if not currentCart(cart) then
		return nil, nil
	end
	local index = slotIndex(cart, slotId)
	if not index then
		return nil, nil
	end
	local slot, _, attachment = getCargoSlot(cart, index)
	return slot, attachment
end

-- Removal may target an already-occupied authored slot that is no longer enabled
-- for admission. This does not make the slot loadable or replaceable.
function CartCargoService:ResolveStoredCargoSlot(cart: any, slotId: any): (BasePart?, Attachment?)
	if not currentCart(cart) then
		return nil, nil
	end
	local index = authoredSlotIndex(cart, slotId)
	local state = if index then cargoByCart[cart] else nil
	if index == nil or state == nil or state.Occupancy[index] == nil then
		return nil, nil
	end
	local slot, _, attachment = getAuthoredCargoSlot(cart, index)
	return slot, attachment
end

function CartCargoService:GetSlotRecord(cart: Model, slotId: any): CargoEntry?
	local index = authoredSlotIndex(cart, slotId)
	local state = cargoByCart[cart]
	local id = if index and state then state.Occupancy[index] else nil
	return if id then state.ById[id] else nil
end

function CartCargoService:CanReplaceCargo(cart: Model): (boolean, string?)
	local map = CartAssetValidator.GetCargoSlotMap(cart, self:GetCargoCapacity(cart))
	if not map then
		return false, "INVALID_SLOT_MAP"
	end
	for _, slot in map do
		if not self:GetSlotRecord(cart, slot.Id) then
			return false, "EMPTY_SLOT_AVAILABLE"
		end
	end
	return true, nil
end

local function canInsert(
	cart: any,
	slotId: any,
	record: any,
	token: any?,
	old: CargoEntry?
): (boolean, string?)
	local slot = CartCargoService:ResolveCargoSlot(cart, slotId)
	if not slot then
		return false, "INVALID_SLOT"
	end
	if
		type(record) ~= "table"
		or type(record.ItemId) ~= "string"
		or record.ItemId == ""
		or type(record.BrainrotId) ~= "string"
		or record.BrainrotId == ""
		or type(record.Metadata) ~= "table"
	then
		return false, "INVALID_RECORD"
	end
	local state = cargoByCart[cart]
	if state then
		if state.Transfer or (state.Insertion and state.Insertion ~= token) then
			return false, "BUSY"
		end
		if state.ById[record.ItemId] then
			return false, "ALREADY_STORED"
		end
		if old then
			local full, reason = CartCargoService:CanReplaceCargo(cart)
			if not full then
				return false, reason
			end
			if
				state.ById[old.ItemId] ~= old
				or state.Occupancy[slotIndex(cart, slotId)] ~= old.ItemId
			then
				return false, "STALE_ID"
			end
		elseif state.Occupancy[slotIndex(cart, slotId)] then
			return false, "OCCUPIED"
		end
		if not old and cargoCount(state) >= CartCargoService:GetCargoCapacity(cart) then
			return false, "NO_SPACE"
		end
	end
	return true, nil
end

function CartCargoService:CanInsertAtSlot(cart: any, slotId: any, record: any): (boolean, string?)
	return canInsert(cart, slotId, record, nil)
end

local function prepareSlotChange(
	player: Player,
	cart: any,
	slotId: any,
	record: any,
	old: CargoEntry?
): (any?, string?)
	if not CartCargoService:CanPlayerHandleCargo(player, cart) then
		return nil, "NOT_OWNER"
	end
	local valid, reason = canInsert(cart, slotId, record, nil, old)
	if not valid then
		return nil, reason
	end
	local state = getOrCreateCargo(cart)
	local slot, attachment = CartCargoService:ResolveCargoSlot(cart, slotId)
	local token = table.freeze({})
	local stage = {
		Player = player,
		Cart = cart,
		SlotId = slotId,
		Slot = slot,
		Attachment = attachment,
		State = state,
		Committed = false,
		OldEntry = old,
		OldVisual = if old then state.Visuals[old.ItemId] else nil,
	}
	preparedInsertions[token], state.Insertion = stage, token
	local ok, failure = pcall(function()
		-- Keep the entire individual, including World restoration fields. Only its
		-- container-local slot changes; never reconstruct an individual from species.
		local entry = table.clone(copyMetadata(record, true))
		entry.AttachmentIndex = slotIndex(cart, slotId)
		stage.Entry = table.freeze(entry)
		stage.Visual = prepareCargoVisual(stage.Entry)
		assert(stage.Visual, "Cargo display unavailable")
		stage.Container = getCargoVisualContainer(cart)
	end)
	if not ok then
		CartCargoService:FinishInsertAtSlot(token)
		warn("[Cargo] Load preparation failed: " .. tostring(failure))
		return nil, "PREPARATION_FAILED"
	end
	return token, nil
end

function CartCargoService:PrepareInsertAtSlot(
	player: Player,
	cart: any,
	slotId: any,
	record: any
): (any?, string?)
	return prepareSlotChange(player, cart, slotId, record, nil)
end

function CartCargoService:PrepareReplaceAtSlot(
	player: Player,
	cart: any,
	slotId: any,
	expectedOldId: any,
	record: any
): (any?, string?)
	if not self:CanPlayerHandleCargo(player, cart) or not self:ResolveCargoSlot(cart, slotId) then
		return nil, "NOT_OWNER"
	end
	local old = self:GetSlotRecord(cart, slotId)
	if not old or old.ItemId ~= expectedOldId then
		return nil, "STALE_ID"
	end
	return prepareSlotChange(player, cart, slotId, record, old)
end

local function validatePreparedChange(token: any): (any?, string?)
	local stage = preparedInsertions[token]
	if not stage or stage.Committed then
		return nil, "INVALID_CONTEXT"
	end
	local cart, state = stage.Cart, stage.State
	if
		cargoByCart[cart] ~= state
		or state.Insertion ~= token
		or not CartCargoService:CanPlayerHandleCargo(stage.Player, cart)
	then
		return nil, "INVALID_CONTEXT"
	end
	local valid, reason = canInsert(cart, stage.SlotId, stage.Entry, token, stage.OldEntry)
	if not valid then
		return nil, reason
	end
	local slot, attachment = CartCargoService:ResolveCargoSlot(cart, stage.SlotId)
	if slot ~= stage.Slot or attachment ~= stage.Attachment or stage.Container.Parent ~= cart then
		return nil, "INVALID_SLOT"
	end
	return stage, nil
end

-- Mount only the NEW inert display before compare-and-replace. Rollback may
-- discard this staging; the old slot display is never moved/anchored/detached.
function CartCargoService:MountPreparedReplacement(token: any): (boolean, string?)
	local stage, reason = validatePreparedChange(token)
	if not stage or not stage.OldEntry or stage.Mounted then
		return false, reason or "INVALID_CONTEXT"
	end
	local ok = pcall(
		mountCargoVisual,
		stage.Visual,
		stage.Slot,
		stage.Attachment.WorldCFrame,
		stage.Container
	)
	stage.Mounted = ok
	if ok and stage.OldVisual then
		BrainrotDisplayMetadata.Clear(stage.OldVisual)
	end
	return ok, if ok then nil else "MOUNT_FAILED"
end

-- Pure ownership mutation: no count notifications, Instance writes or yields.
-- The world owner invokes this immediately before publishing its awake record.
function CartCargoService:CommitReplaceAtSlot(token: any): (boolean, string?)
	local stage, reason = validatePreparedChange(token)
	if not stage or not stage.OldEntry or not stage.Mounted then
		return false, reason or "INVALID_CONTEXT"
	end
	if stage.Visual.Model.Parent ~= stage.Container or not stage.Visual.Mount.Enabled then
		return false, "MOUNT_FAILED"
	end
	local state, old, entry = stage.State, stage.OldEntry, stage.Entry
	local index = table.find(state.Entries, old)
	if not index then
		return false, "STALE_ID"
	end
	state.Entries[index] = entry
	state.ById[old.ItemId], state.Visuals[old.ItemId] = nil, nil
	state.ById[entry.ItemId], state.Occupancy[entry.AttachmentIndex] = entry, entry.ItemId
	state.Visuals[entry.ItemId] = stage.Visual.Model
	state.Revision += 1
	stage.Committed = true
	return true, nil
end

-- Table-only ownership commit after all mounting checks. The interaction owner
-- clears its carried record before Finish publishes count/slot presentation.
function CartCargoService:CommitInsertAtSlot(token: any): (boolean, string?)
	local stage, reason = validatePreparedChange(token)
	if not stage or stage.OldEntry then
		return false, reason or "INVALID_CONTEXT"
	end
	local slot, attachment, state = stage.Slot, stage.Attachment, stage.State
	local ok, failure =
		pcall(mountCargoVisual, stage.Visual, slot, attachment.WorldCFrame, stage.Container)
	if not ok then
		warn("[Cargo] Load mount failed: " .. tostring(failure))
		return false, "MOUNT_FAILED"
	end
	local entry = stage.Entry
	table.insert(state.Entries, entry)
	state.ById[entry.ItemId], state.Occupancy[entry.AttachmentIndex] = entry, entry.ItemId
	state.Visuals[entry.ItemId] = stage.Visual.Model
	state.Revision += 1
	stage.Committed = true
	return true, nil
end

function CartCargoService:FinishInsertAtSlot(token: any)
	local stage = preparedInsertions[token]
	if not stage then
		return
	end
	preparedInsertions[token] = nil
	local function present(action: () -> ())
		local ok, failure = pcall(action)
		if not ok then
			ok, failure = pcall(action)
		end -- Repair presentation only, never repeat the mutation.
		if not ok then
			warn(
				"[Cargo] Committed="
					.. tostring(stage.Committed)
					.. " presentation: "
					.. tostring(failure)
			)
		end
	end
	if stage.Committed then
		present(function()
			if stage.OldVisual then
				destroyCargoVisual(stage.Cart, stage.OldVisual)
			end
		end)
		present(function()
			if stage.OldEntry and stage.State.ById[stage.Entry.ItemId] == stage.Entry then
				local visual = stage.State.Visuals[stage.Entry.ItemId]
				if not visual or visual.Parent ~= stage.Container then
					if visual then
						destroyCargoVisual(stage.Cart, visual)
					end
					local repaired = createCargoVisual(stage.Cart, stage.Entry)
					assert(repaired, "Committed cargo display repair failed")
					stage.State.Visuals[stage.Entry.ItemId] = repaired
				end
			end
		end)
		present(function()
			local visual = stage.State.Visuals[stage.Entry.ItemId]
			assert(visual and visual.Parent == stage.Container, "Committed cargo display missing")
			BrainrotDisplayMetadata.Apply(
				visual,
				stage.Entry,
				BrainrotDisplayConfig.States.Cart,
				nil
			)
		end)
		present(function()
			updateCargoAttributes(stage.Cart, stage.State)
		end)
	elseif stage.Visual then
		present(function()
			destroyCargoVisual(stage.Cart, stage.Visual.Model)
		end)
		present(function()
			if stage.OldEntry and stage.OldVisual and stage.OldVisual.Parent then
				BrainrotDisplayMetadata.Apply(
					stage.OldVisual,
					stage.OldEntry,
					BrainrotDisplayConfig.States.Cart,
					nil
				)
			end
		end)
	end
	if stage.State.Insertion == token then
		stage.State.Insertion = nil
	end
end

-- Diagnostics read the existing bounded records; never take another gameplay snapshot.
function CartCargoService:TraceCargoState(cart: Model)
	Trace.Emit("5C", "batch_cargo", function()
		local state = cargoByCart[cart]
		local items = {}
		for _, entry in if state then state.Entries else {} do
			table.insert(
				items,
				entry.ItemId
					.. ":"
					.. entry.BrainrotId
					.. "@"
					.. entry.AttachmentIndex
					.. if entry.AttachmentIndex > self:GetCargoCapacity(cart)
						then "!removal"
						else ""
			)
		end
		return {
			items = table.concat(items, ","),
			cargoCount = state and cargoCount(state) or 0,
			cargoRevision = state and state.Revision or 0,
			transferHeld = state ~= nil and state.Transfer ~= nil,
		}
	end)
end

function CartCargoService:GetCargoSnapshot(cart: Model): { CargoEntry }
	local snapshot = {}
	local state = cargoByCart[cart]
	if state then
		for _, entry in state.Entries do
			table.insert(snapshot, copyMetadata(entry))
		end
	end
	return snapshot
end

function CartCargoService:GetCargo(cart: Model): { CargoEntry }
	ensureStarted()
	return self:GetCargoSnapshot(cart)
end

function CartCargoService:GetCargoCount(cart: Model): number
	local state = cargoByCart[cart]
	return if state then cargoCount(state) else 0
end

function CartCargoService:GetCargoRevision(cart: Model): number
	local state = cargoByCart[cart]
	return if state then state.Revision else 0
end

function CartCargoService:GetCargoCapacity(cart: Model): number
	local readiness = self:ResolveEffectiveCargoCapacity(cart)
	return if readiness.status == "Ready" and type(readiness.effectiveCapacity) == "number"
		then readiness.effectiveCapacity
		else 0
end

function CartCargoService:CanAcceptCargo(cart: Model): boolean
	local state = getOrCreateCargo(cart)
	return cart.Parent ~= nil
		and self:GetCargoCapacityReadiness(cart).status == "Ready"
		and cargoCount(state) < self:GetCargoCapacity(cart)
		and freeAttachment(cart, state) ~= nil
end

-- Exact-slot removal uses the existing reversible transfer and finalisation.
-- No count/visual notification until the interaction owner has assigned carry.
function CartCargoService:DetachSlotForTransfer(
	cart: any,
	slotId: any,
	expectedItemId: any
): (any?, string?)
	local index = authoredSlotIndex(cart, slotId)
	local slot = if index then getAuthoredCargoSlot(cart, index) else nil
	if not slot then
		return nil, "INVALID_SLOT"
	end
	local record = self:GetSlotRecord(cart, slotId)
	if not record or type(expectedItemId) ~= "string" or record.ItemId ~= expectedItemId then
		return nil, "STALE_ID"
	end
	return self:DetachForTransfer(cart, record.ItemId)
end

-- Bounded, synchronous multi-item staging used only by the departure owner so
-- all banked cargo can share one profile mutation. It is reversible until that
-- mutation commits and never creates a world representation itself.
function CartCargoService:PrepareDepartureRemovals(
	cart: Model,
	itemIds: { string }
): (any?, string?)
	local state = cargoByCart[cart]
	if state == nil then
		return nil, "CARGO_NOT_BOUND"
	end
	if state.Transfer ~= nil or state.Insertion ~= nil or state.DepartureTransfer ~= nil then
		return nil, "BUSY"
	end
	local seen: { [string]: boolean } = {}
	local entries = {}
	for _, itemId in itemIds do
		if type(itemId) ~= "string" or seen[itemId] then
			return nil, "INVALID_ITEM_SET"
		end
		seen[itemId] = true
		local entry = state.ById[itemId]
		local order = if entry then table.find(state.Entries, entry) else nil
		if entry == nil or order == nil or state.Occupancy[entry.AttachmentIndex] ~= itemId then
			return nil, "INVALID_CONTEXT"
		end
		table.insert(entries, {
			Entry = entry,
			Order = order,
			Visual = state.Visuals[itemId],
		})
	end
	table.sort(entries, function(left, right)
		return left.Order > right.Order
	end)
	local token = table.freeze({})
	local batch = { Token = token, Entries = entries, Revision = state.Revision }
	state.DepartureTransfer = batch
	for _, removed in entries do
		local entry = removed.Entry
		table.remove(state.Entries, removed.Order)
		state.ById[entry.ItemId] = nil
		state.Occupancy[entry.AttachmentIndex] = nil
	end
	return token, nil
end

function CartCargoService:RestoreDepartureRemovals(cart: Model, token: any): boolean
	local state = cargoByCart[cart]
	local batch = if state then state.DepartureTransfer else nil
	if batch == nil or batch.Token ~= token then
		return false
	end
	table.sort(batch.Entries, function(left, right)
		return left.Order < right.Order
	end)
	for _, removed in batch.Entries do
		local entry = removed.Entry
		if state.ById[entry.ItemId] ~= nil or state.Occupancy[entry.AttachmentIndex] ~= nil then
			return false
		end
		table.insert(state.Entries, removed.Order, entry)
		state.ById[entry.ItemId] = entry
		state.Occupancy[entry.AttachmentIndex] = entry.ItemId
	end
	state.Revision = batch.Revision
	state.DepartureTransfer = nil
	updateCargoAttributes(cart, state)
	return true
end

function CartCargoService:FinalizeDepartureRemovals(cart: Model, token: any): (boolean, string?)
	local state = cargoByCart[cart]
	local batch = if state then state.DepartureTransfer else nil
	if batch == nil or batch.Token ~= token then
		return false, "INVALID_CONTEXT"
	end
	state.DepartureTransfer = nil
	state.Revision = batch.Revision + 1
	local failures = {}
	for _, removed in batch.Entries do
		local itemId = removed.Entry.ItemId
		if state.Visuals[itemId] == removed.Visual then
			state.Visuals[itemId] = nil
		end
		if removed.Visual then
			local ok, failure = pcall(function()
				BrainrotDisplayMetadata.Clear(removed.Visual)
				destroyCargoVisual(cart, removed.Visual)
			end)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
	end
	updateCargoAttributes(cart, state)
	return true, if #failures > 0 then table.concat(failures, "; ") else nil
end

-- Tokens are opaque and local to one synchronous transfer. While detached, captures
-- cannot allocate the reserved source attachment. No presentation or events happen here.
function CartCargoService:DetachForTransfer(cart: Model, itemId: string): (any?, string?)
	local state = cargoByCart[cart]
	Trace.Emit("5C", "source_detach_check", function()
		local item = state and state.ById[itemId]
		return {
			itemId = itemId,
			recordPresent = item ~= nil,
			transferHeld = state ~= nil and state.Transfer ~= nil,
			attachment = item and item.AttachmentIndex or "none",
			attachmentOccupant = item and state.Occupancy[item.AttachmentIndex] or "none",
			visual = state and state.Visuals[itemId] or "none",
			cargoRevision = state and state.Revision or "none",
		}
	end)
	if state == nil or state.ById[itemId] == nil then
		return nil, "NOT_IN_CARGO"
	end
	if state.Transfer ~= nil or state.Insertion ~= nil or state.DepartureTransfer ~= nil then
		return nil, "BUSY"
	end
	local entry = state.ById[itemId]
	local order = table.find(state.Entries, entry)
	if order == nil or state.Occupancy[entry.AttachmentIndex] ~= itemId then
		return nil, "INVALID_CONTEXT"
	end
	local token = table.freeze({})
	local transfer = {
		Token = token,
		Entry = entry,
		Order = order,
		Visual = state.Visuals[itemId],
		Revision = state.Revision,
	}
	state.Transfer = transfer
	table.remove(state.Entries, order)
	state.ById[itemId] = nil
	state.Occupancy[entry.AttachmentIndex] = nil
	Trace.Emit("5C", "source_detached", function()
		return {
			itemId = itemId,
			attachment = entry.AttachmentIndex,
			attachmentOccupied = state.Occupancy[entry.AttachmentIndex] ~= nil,
			recordPresent = state.ById[itemId] ~= nil,
			token = Trace.Id(token),
			visualPresent = transfer.Visual ~= nil and transfer.Visual.Parent ~= nil,
			visualRemoval = "deferred",
			cargoRevision = state.Revision,
			cargoRemaining = cargoCount(state),
		}
	end)
	return token, nil
end

function CartCargoService:RestoreTransfer(cart: Model, token: any): boolean
	local state = cargoByCart[cart]
	local transfer = if state then state.Transfer else nil
	if transfer == nil or transfer.Token ~= token then
		return false
	end
	local entry = transfer.Entry
	if state.ById[entry.ItemId] ~= nil or state.Occupancy[entry.AttachmentIndex] ~= nil then
		return false
	end
	table.insert(state.Entries, transfer.Order, entry)
	state.ById[entry.ItemId] = entry
	state.Occupancy[entry.AttachmentIndex] = entry.ItemId
	state.Revision = transfer.Revision
	state.Transfer = nil
	Trace.Emit("5C", "source_restored", {
		itemId = entry.ItemId,
		attachment = entry.AttachmentIndex,
		cargoRevision = state.Revision,
		cargoRemaining = cargoCount(state),
		visual = state.Visuals[entry.ItemId] or "none",
		result = "restored_original_entry_and_order",
	})
	return true
end

function CartCargoService:FinalizeTransfer(
	cart: Model,
	token: any,
	onCommitted: (() -> ())?
): (boolean, string?)
	local state = cargoByCart[cart]
	local transfer = if state then state.Transfer else nil
	if transfer == nil or transfer.Token ~= token then
		return false, "INVALID_CONTEXT"
	end
	-- Logical finalisation MUST precede any Instance writes. Never restore after this.
	state.Transfer = nil
	state.Revision = transfer.Revision + 1
	local itemId = transfer.Entry.ItemId
	if state.Visuals[itemId] == transfer.Visual then
		state.Visuals[itemId] = nil
	end
	Trace.Emit("5C", "source_logical_finalized", {
		committed = true,
		itemId = itemId,
		attachment = transfer.Entry.AttachmentIndex,
		cargoRevision = state.Revision,
		cargoRemaining = cargoCount(state),
	})
	local errors = {}
	-- Both inventory records and the cargo revision are committed. Notify synchronously
	-- before any fallible Instance cleanup; an observer can never undo this transfer.
	if onCommitted then
		Trace.Emit("5C", "source_commit_callback_enter", { committed = true })
		local notified, failure = pcall(onCommitted)
		Trace.Emit("5C", "source_commit_callback_exit", {
			committed = true,
			result = notified,
			error = if notified then "none" else tostring(failure),
		}, not notified)
		if not notified then
			table.insert(errors, "commit observer: " .. tostring(failure))
		end
	end
	local function present(label: string, action: () -> ())
		Trace.Emit("5C", "source_presentation_enter", { operation = label, committed = true })
		local ok, failure = pcall(action)
		Trace.Emit("5C", "source_presentation_exit", {
			operation = label,
			result = ok,
			error = if ok then "none" else tostring(failure),
			committed = true,
		}, not ok)
		if not ok then
			table.insert(errors, label .. ": " .. tostring(failure))
			-- One bounded, exact-item reconciliation attempt. Never clear a replacement slot.
			Trace.Emit("5C", "source_existing_retry_enter", { operation = label, committed = true })
			local repaired, repairFailure = pcall(action)
			Trace.Emit("5C", "source_existing_retry_exit", {
				operation = label,
				result = repaired,
				error = if repaired then "none" else tostring(repairFailure),
				committed = true,
			}, not repaired)
			if not repaired then
				table.insert(errors, label .. " retry: " .. tostring(repairFailure))
			end
		end
	end
	present("source visual cleanup", function()
		if transfer.Visual then
			BrainrotDisplayMetadata.Clear(transfer.Visual)
			destroyCargoVisual(cart, transfer.Visual)
		end
	end)
	present("cargo attributes", function()
		updateCargoAttributes(cart, state)
	end)
	Trace.Emit("5C", "cargo_finalized", function()
		return {
			committed = true,
			itemId = itemId,
			attachment = transfer.Entry.AttachmentIndex,
			attachmentOccupied = state.Occupancy[transfer.Entry.AttachmentIndex] ~= nil,
			recordPresent = state.ById[itemId] ~= nil,
			oldVisualPresent = transfer.Visual ~= nil and transfer.Visual.Parent ~= nil,
			cargoRevision = state.Revision,
			cargoRemaining = cargoCount(state),
			error = if #errors > 0 then table.concat(errors, "; ") else "none",
		}
	end, #errors > 0)
	return true, if #errors > 0 then table.concat(errors, "; ") else nil
end

function CartCargoService:Start()
	Trace.Emit("BOOT", "cargo_start", { module = script, alreadyStarted = started })
	ensureStarted()
	Trace.Emit("BOOT", "cargo_ready", { started = started })
end

return CartCargoService
]]}
local function resolve(path)
 local node=game
 for segment in string.gmatch(path,"[^.]+") do node=assert(node:FindFirstChild(segment),"Missing source "..path) end
 return node
end
local API={Evidence=E}
function API.CheckSources()
 local checked,editorReadable=0,0
 local SES=game:GetService("ScriptEditorService")
 for key,r in pairs(E) do
  local node=resolve(r.path)
  assert(node:IsA("LuaSourceContainer"),"Wrong source class "..r.path)
  assert(node.Source==(ExpectedCurrent[key]or r.source),"Captured source changed "..r.path)
  local ok,editor=pcall(function()return SES:GetEditorSource(node)end)
  if ok then editorReadable+=1;assert(editor==(ExpectedCurrent[key]or r.source),"Editor buffer changed "..r.path)end
  checked+=1
 end
 return {exactSourceBytesPassed=true,checkedSources=checked,editorSourcesReadable=editorReadable}
end
function API.Create()
 API.CheckSources()
 local byInstance,cache={},{}
 for key,r in pairs(E) do byInstance[resolve(r.path)]=key end
 local function loadCaptured(key)
  if cache[key] then return cache[key]end
  assert(key~="Income"and key~="Storage"and key~="Cargo","Gameplay graphs may not be required")
  local chunk=assert(loadstring(E[key].source,"@Captured/"..E[key].path))
  local env=setmetatable({script=resolve(E[key].path),require=function(instance)
   local dependency=assert(byInstance[instance],"Uncaptured dependency")
   return loadCaptured(dependency)
  end},{__index=getfenv(0)})
  setfenv(chunk,env)
  local value=chunk();cache[key]=value;return value
 end
 local deps={Config=loadCaptured("Config"),Scale=loadCaptured("Scale"),Material=loadCaptured("Material"),Catalog=loadCaptured("Catalog")}
 deps.Layout=assert(loadstring([[return function(deps)
local Config, StaticMaterial = deps.Config, deps.Material
local PLAQUE_TAG = "BrainrotIncomePlaque"
local LAYOUT_CONTAINER_NAME = "Phase5DInterior"
local PLAQUE_CONTAINER_NAME = "IncomePlaques"
local TOUCH_SENSOR_NAME = "TouchSensor"
local AMOUNT_SURFACE_NAME = "AmountSurfaceGui"
local AMOUNT_LABEL_NAME = "AmountLabel"
local AMOUNT_STROKE_NAME = "AmountStroke"
local PLAQUE_WIDTH_STUDS = 3.5
local PLAQUE_THICKNESS_STUDS = 0.18
local PLAQUE_DEPTH_STUDS = 2.25
local PLAQUE_PLATFORM_GAP_STUDS = 0.55
local PLAQUE_FLOOR_CLEARANCE_STUDS = 0.02
local PLAQUE_SNAPSHOT_REFRESH_SECONDS = 1
local PILLAR_MANAGED_BY = "BaseIncomePlaqueSystem"
local PILLAR_ORIGINAL_WIDTH_STUDS = 1.25
local PILLAR_ORIGINAL_DEPTH_STUDS = 1.25
local PILLAR_WIDTH_STUDS = PILLAR_ORIGINAL_WIDTH_STUDS * 0.5
local PILLAR_DEPTH_STUDS = PILLAR_ORIGINAL_DEPTH_STUDS * 0.5
local PILLAR_MAX_SPACING_STUDS = 6
local ENTRANCE_CLEAR_WIDTH_STUDS = 10
local LEGACY_WALL_NAMES = table.freeze({ "LeftWall", "RightWall", "BackWall" })

type StructuralStyle = {
	Color: Color3,
	Material: Enum.Material,
	MaterialVariant: string,
	EffectivePhysicalProperties: PhysicalProperties,
	CollisionGroup: string,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
}
local function platformIdFromPart(platform: BasePart): number?
	local attribute = platform:GetAttribute("SlotIndex")
	if type(attribute) == "number" and attribute % 1 == 0 then
		return attribute
	end
	return tonumber(platform.Name:match("^Slot_(%d+)$"))
end

local function baseRootCFrame(base: Model): CFrame
	local saved = base:GetAttribute("Phase5DLayoutPivot")
	if typeof(saved) == "CFrame" then
		return saved
	end
	local root = base:GetPivot()
	base:SetAttribute("Phase5DLayoutPivot", root)
	return root
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), name .. " must be a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensurePart(base: Model, container: Folder, name: string): (BasePart, boolean)
	local existing = base:FindFirstChild(name) or container:FindFirstChild(name)
	if existing then
		assert(existing:IsA("BasePart"), name .. " must be a BasePart")
		return existing, false
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Parent = container
	return part, true
end

local function configureStructuralPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	StaticMaterial.Apply(part, Enum.Material.SmoothPlastic)
	part.Color = Color3.fromRGB(91, 98, 104)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function platformTopLocalY(root: CFrame, platform: BasePart): number
	return root:PointToObjectSpace(platform.Position).Y + platform.Size.Y / 2
end

local function entranceSign(base: Model, root: CFrame): number
	for _, name in { "CartSpawn", "PlayerSpawn" } do
		local marker = base:FindFirstChild(name)
		if marker and marker:IsA("BasePart") then
			local localZ = root:PointToObjectSpace(marker.Position).Z
			if math.abs(localZ) > 0.01 then
				return if localZ > 0 then 1 else -1
			end
		end
	end
	return -1
end

local function captureStructuralStyle(part: BasePart): StructuralStyle
	return {
		Color = part.Color,
		Material = part.Material,
		MaterialVariant = part.MaterialVariant,
		EffectivePhysicalProperties = part.CurrentPhysicalProperties,
		CollisionGroup = part.CollisionGroup,
		CanCollide = part.CanCollide,
		CanTouch = part.CanTouch,
		CanQuery = part.CanQuery,
	}
end

local function legacyWall(base: Model, container: Folder, name: string): BasePart?
	local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
	return if candidate and candidate:IsA("BasePart") then candidate else nil
end

local function removeLegacyWalls(base: Model, container: Folder)
	for _, name in LEGACY_WALL_NAMES do
		local direct = base:FindFirstChild(name)
		if direct and direct:IsA("BasePart") then
			direct:Destroy()
		end
		local generated = container:FindFirstChild(name)
		if generated and generated:IsA("BasePart") then
			generated:Destroy()
		end
	end
end

local function clearManagedPillars(container: Folder)
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("ManagedBy") == PILLAR_MANAGED_BY then
			child:Destroy()
		end
	end
end

local function createPillar(
	container: Folder,
	root: CFrame,
	name: string,
	localPosition: Vector3,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle
)
	local pillar = Instance.new("Part")
	pillar.Name = name
	pillar:SetAttribute("ManagedBy", PILLAR_MANAGED_BY)
	configureStructuralPart(pillar)
	pillar.Size = Vector3.new(PILLAR_WIDTH_STUDS, pillarHeight, PILLAR_DEPTH_STUDS)
	pillar.CFrame = root
		* CFrame.new(localPosition.X, floorTopY + pillarHeight / 2, localPosition.Z)
	pillar.Color = style.Color
	pillar.Material = style.Material
	pillar.MaterialVariant = style.MaterialVariant
	pillar.CustomPhysicalProperties = style.EffectivePhysicalProperties
	pillar.CollisionGroup = style.CollisionGroup
	pillar.CanCollide = style.CanCollide
	pillar.CanTouch = style.CanTouch
	pillar.CanQuery = style.CanQuery
	StaticMaterial.Apply(pillar)
	pillar.Parent = container
end

local function createPillarsAlongEdge(
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle,
	edgeName: string,
	startLocalPosition: Vector3,
	endLocalPosition: Vector3,
	shouldSkip: ((Vector3) -> boolean)?
)
	local edgeLength = (endLocalPosition - startLocalPosition).Magnitude
	local intervalCount = math.max(1, math.ceil(edgeLength / PILLAR_MAX_SPACING_STUDS))
	local placedIndex = 0
	for interval = 1, intervalCount - 1 do
		local localPosition = startLocalPosition:Lerp(endLocalPosition, interval / intervalCount)
		if not shouldSkip or not shouldSkip(localPosition) then
			placedIndex += 1
			createPillar(
				container,
				root,
				string.format("BasePillar_%s_%02d", edgeName, placedIndex),
				localPosition,
				floorTopY,
				pillarHeight,
				style
			)
		end
	end
end

local function createPerimeterPillars(
	base: Model,
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle
)
	clearManagedPillars(container)
	-- Preserve the established perimeter centreline while reducing only each
	-- pillar's horizontal cross-section.
	local halfWidth = (Config.BASE_FOOTPRINT_WIDTH_STUDS - PILLAR_ORIGINAL_WIDTH_STUDS) / 2
	local halfDepth = (Config.BASE_FOOTPRINT_DEPTH_STUDS - PILLAR_ORIGINAL_DEPTH_STUDS) / 2
	local frontZ = entranceSign(base, root) * halfDepth
	local backZ = -frontZ
	local frontLeft = Vector3.new(-halfWidth, 0, frontZ)
	local frontRight = Vector3.new(halfWidth, 0, frontZ)
	local backLeft = Vector3.new(-halfWidth, 0, backZ)
	local backRight = Vector3.new(halfWidth, 0, backZ)

	for name, localPosition in
		{
			BasePillar_Corner_FL = frontLeft,
			BasePillar_Corner_FR = frontRight,
			BasePillar_Corner_BL = backLeft,
			BasePillar_Corner_BR = backRight,
		}
	do
		createPillar(container, root, name, localPosition, floorTopY, pillarHeight, style)
	end

	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Front",
		frontLeft,
		frontRight,
		function(localPosition)
			return math.abs(localPosition.X) < ENTRANCE_CLEAR_WIDTH_STUDS / 2
		end
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Back",
		backLeft,
		backRight,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Left",
		frontLeft,
		backLeft,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Right",
		frontRight,
		backRight,
		nil
	)
end

local function ensureInterior(base: Model, root: CFrame, platformFloorY: number): number
	local container = ensureFolder(base, LAYOUT_CONTAINER_NAME)
	local floor: BasePart? = nil
	for _, name in { "BaseFloor", "Floor", "InteriorFloor", "GroundFloor" } do
		local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
		if candidate and candidate:IsA("BasePart") then
			floor = candidate
			break
		end
	end
	local createdFloor = false
	if not floor then
		floor, createdFloor = ensurePart(base, container, "BaseFloor")
	end
	local resolvedFloor = floor :: BasePart
	local floorThickness = if createdFloor then 1 else math.max(resolvedFloor.Size.Y, 0.2)
	local floorTopY = if createdFloor
		then platformFloorY
		else platformTopLocalY(root, resolvedFloor)
	configureStructuralPart(resolvedFloor)
	resolvedFloor.Size = Vector3.new(
		Config.BASE_FOOTPRINT_WIDTH_STUDS,
		floorThickness,
		Config.BASE_FOOTPRINT_DEPTH_STUDS
	)
	resolvedFloor.CFrame = root * CFrame.new(0, floorTopY - floorThickness / 2, 0)

	local pillarStyle = captureStructuralStyle(resolvedFloor)
	local pillarHeight = Config.BASE_WALL_HEIGHT_STUDS
	for _, wallName in LEGACY_WALL_NAMES do
		local wall = legacyWall(base, container, wallName)
		if wall then
			pillarStyle = captureStructuralStyle(wall)
			pillarHeight = wall.Size.Y
			break
		end
	end
	removeLegacyWalls(base, container)
	createPerimeterPillars(base, container, root, floorTopY, pillarHeight, pillarStyle)
	return floorTopY
end

local function setMarkerFacing(slot: any, platformCFrame: CFrame, markerOffset: CFrame)
	if slot.Marker:IsA("Attachment") then
		slot.Marker.CFrame = CFrame.new(markerOffset.Position)
	else
		local marker = slot.Marker :: BasePart
		marker.CFrame = platformCFrame * CFrame.new(markerOffset.Position)
	end
end

local function positionPlatforms(root: CFrame, slots: { any }): (any, number)
	local ordered = table.clone(slots)
	table.sort(ordered, function(left, right)
		return left.Index < right.Index
	end)
	assert(#ordered == Config.PLATFORM_COUNT, "Phase 5D requires exactly 12 platforms")
	local placementById = {}
	local floorY = math.huge
	for order, slot in ordered do
		local platform = slot.Platform :: BasePart
		local platformId = platformIdFromPart(platform)
		assert(platformId == slot.Index, "Platform stable ID changed during layout")
		local topY = platformTopLocalY(root, platform)
		floorY = math.min(floorY, topY - platform.Size.Y)
		local side = if order <= Config.PLATFORMS_PER_SIDE then -1 else 1
		local row = if side < 0 then order else order - Config.PLATFORMS_PER_SIDE
		local x = side * Config.PLATFORM_ROW_OFFSET_X
		local z = Config.PLATFORM_Z_CENTERS[row]
		local localPosition = Vector3.new(x, topY - platform.Size.Y / 2, z)
		local localFacing = CFrame.lookAt(
			localPosition,
			Vector3.new(0, localPosition.Y, localPosition.Z),
			Vector3.yAxis
		)
		local markerOffset = if slot.Marker:IsA("Attachment")
			then slot.Marker.CFrame
			else platform.CFrame:ToObjectSpace((slot.Marker :: BasePart).CFrame)
		platform.Size =
			Vector3.new(Config.PLATFORM_SIDE_STUDS, platform.Size.Y, Config.PLATFORM_SIDE_STUDS)
		platform.CFrame = root * localFacing
		platform.Anchored = true
		setMarkerFacing(slot, platform.CFrame, markerOffset)
		placementById[slot.Index] = {
			Side = side,
			ZCenter = z,
			PlatformTopY = topY,
		}
	end
	assert(floorY < math.huge, "Phase 5D platforms have no usable floor datum")
	return placementById, floorY
end
return {Apply=function(base,slots) local root=baseRootCFrame(base); local placements,floorY=positionPlatforms(root,slots); local resolved=ensureInterior(base,root,floorY); return root,placements,resolved end}

end]],"@IsolatedCaptured/Layout"))()(deps)
 deps.Place=assert(loadstring([[return function(deps)
local BrainrotVisualScale=deps.Scale
local PLACEMENT_GAP = 0.05
local function placeDisplayAtSlot(display: Model, slot: BaseStorage.SlotDescriptor): (any, any)
	local placement = if slot.Marker:IsA("Attachment")
		then slot.Marker.WorldCFrame
		else slot.Marker.CFrame
	local facing = display:GetAttribute("DisplayFacingOffset")
	if typeof(facing) == "CFrame" then
		placement *= facing
	end
	local pivotToBounds, size, boundsReason = BrainrotVisualScale.GetVisualBounds(display)
	assert(pivotToBounds and size, boundsReason)
	display:PivotTo(
		placement * CFrame.new(0, size.Y / 2 + PLACEMENT_GAP, 0) * pivotToBounds:Inverse()
	)
	return placement, size
end
return placeDisplayAtSlot

end]],"@IsolatedCaptured/Place"))()(deps)
 deps.Factory=assert(loadstring([[return function(deps)
local BrainrotCatalog, BrainrotVisualScale=deps.Catalog,deps.Scale
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local CollectionService=game:GetService("CollectionService")
local Trace={Emit=function(...) end}
local CartCargoService={}
local function getBrainrotTemplate(brainrotId: string): Model?
	local definition = BrainrotCatalog.Get(brainrotId)
	local modelRef = if definition
		then definition.modelRef
		elseif RunService:IsStudio() and string.match(brainrotId, "^SPEC_") then brainrotId
		else nil
	local assets = ReplicatedStorage:FindFirstChild("StudioAssets")
	local brainrots = if assets then assets:FindFirstChild("Brainrots") else nil
	local template = if brainrots and modelRef then brainrots:FindFirstChild(modelRef) else nil
	Trace.Emit("5C", "asset_lookup", {
		species = brainrotId,
		rawKey = brainrotId,
		canonicalKey = if definition then definition.id else "invalid",
		lookupKey = modelRef or "none",
		container = brainrots or "none",
		template = template or "none",
		templateClass = template and template.ClassName or "none",
		result = if template and template:IsA("Model") then "found" else "INVALID_ASSET",
	}, template == nil or not template:IsA("Model"))
	return if template and template:IsA("Model") then template else nil
end

local function getCargoVisualRoot(visual: Model): BasePart?
	if visual.PrimaryPart then
		return visual.PrimaryPart
	end
	local body = visual:FindFirstChild("Body", true)
	return if body and body:IsA("BasePart")
		then body
		else visual:FindFirstChildWhichIsA("BasePart", true)
end

function CartCargoService:CreateItemVisual(brainrotId: string): Model?
	local template = getBrainrotTemplate(brainrotId)
	if template == nil then
		return nil
	end
	Trace.Emit("5C", "asset_clone_enter", { species = brainrotId, template = template })
	local visual = template:Clone()
	Trace.Emit("5C", "asset_clone_exit", {
		species = brainrotId,
		clone = visual or "none",
		result = if visual then "cloned" else "INVALID_ASSET",
	}, visual == nil)
	if visual == nil then
		return nil
	end
	local ok, failure = pcall(function()
		local function outside(instance: Instance?): boolean
			return instance ~= nil and not instance:IsDescendantOf(visual)
		end
		local descendants = visual:GetDescendants()
		table.insert(descendants, visual)
		for _, instance in descendants do
			for _, tag in CollectionService:GetTags(instance) do
				CollectionService:RemoveTag(instance, tag)
			end
			if instance:IsA("LuaSourceContainer") then
				instance:Destroy()
			elseif
				instance:IsA("JointInstance")
				or instance:IsA("WeldConstraint")
				or instance:IsA("NoCollisionConstraint")
			then
				if outside(instance.Part0) or outside(instance.Part1) then
					Trace.Emit("5C", "external_joint_found", {
						joint = instance,
						part0 = instance.Part0 or "none",
						part1 = instance.Part1 or "none",
						action = "existing_preparation_removes_joint",
					})
					instance:Destroy()
				end
			elseif instance:IsA("Constraint") then
				if outside(instance.Attachment0) or outside(instance.Attachment1) then
					Trace.Emit("5C", "external_constraint_found", {
						constraint = instance,
						action = "existing_preparation_removes_constraint",
					})
					instance:Destroy()
				end
			end
		end
		assert(getCargoVisualRoot(visual), "Brainrot visual has no BasePart")
		visual:SetAttribute("Captured", nil)
		local scaled, _, scaleReason =
			BrainrotVisualScale.ApplyCanonicalScale(visual, "LightweightVisual")
		assert(scaled, scaleReason)
	end)
	if not ok then
		Trace.Emit(
			"5C",
			"asset_prepare_error",
			{ error = tostring(failure), species = brainrotId },
			true
		)
		visual:Destroy()
		warn(
			string.format(
				"[Cargo] Visual preparation failed for %s: %s",
				brainrotId,
				tostring(failure)
			)
		)
		return nil
	end
	return visual
end
return CartCargoService

end]],"@IsolatedCaptured/Factory"))()(deps)
 return deps
end
return API
]==],"@Adapter"))()
local Guard=assert(loadstring([[local Run=game:GetService("RunService")
local CS=game:GetService("CollectionService")
local Http=game:GetService("HttpService")
local SS=game:GetService("ServerStorage")
local BASE_PROPERTIES = {"CFrame","Size","PivotOffset","Anchored","CanCollide","CanTouch","CanQuery","CollisionGroup","Transparency","Reflectance","CastShadow","Material","MaterialVariant","Color","CustomPhysicalProperties","CurrentPhysicalProperties","TopSurface","BottomSurface","LeftSurface","RightSurface","FrontSurface","BackSurface"}
local function near(a,b)
 if typeof(a)~=typeof(b)then return false end
 if type(a)=="table"then for k,v in pairs(a)do if not near(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
 if typeof(a)=="number"then return math.abs(a-b)<=1e-6 end
 return a==b
end

local function encoded(v)
 local kind=typeof(v)
 if kind=="CFrame"then return {type=kind,value={v:GetComponents()}}end
 if kind=="Vector3"then return {type=kind,value={v.X,v.Y,v.Z}}end
 if kind=="Vector2"then return {type=kind,value={v.X,v.Y}}end
 if kind=="Color3"then return {type=kind,value={v.R,v.G,v.B}}end
 if kind=="PhysicalProperties"then return {type=kind,value={v.Density,v.Friction,v.Elasticity,v.FrictionWeight,v.ElasticityWeight}}end
 if kind=="EnumItem"then return {type=kind,value=tostring(v)}end
 if kind=="Instance"then return v end
 return v
end

local function indexedKeys(roots)
 local keys={}
 local function key(node)
  if node==game then return "game"end
  if keys[node]then return keys[node]end
  local index=1
  for _,sibling in node.Parent:GetChildren()do
   if sibling==node then break end
   if sibling.Name==node.Name and sibling.ClassName==node.ClassName then index+=1 end
  end
  local value=key(node.Parent).."/"..node.ClassName..":"..node.Name.."["..index.."]"
  keys[node]=value;return value
 end
 local map={}
 for _,root in roots do map[key(root)]=root;for _,node in root:GetDescendants()do map[key(node)]=node end end
 return map
end

local function snapshot(roots)
 local result={}
 for _,root in roots do
  local nodes=root:GetDescendants();table.insert(nodes,root)
  for _,node in nodes do
   local row={Parent=node.Parent,Name=node.Name,Archivable=node.Archivable,Attributes=node:GetAttributes(),Tags=CS:GetTags(node),Properties={},Children=node:GetChildren()}
   table.sort(row.Tags)
   if node:IsA("BasePart")then
    for _,name in BASE_PROPERTIES do row.Properties[name]=encoded(node[name])end
    row.Properties.Mass=node:GetMass()
    if node:IsA("PartOperation")then row.Properties.ExtentsCFrame=encoded(node.ExtentsCFrame);row.Properties.ExtentsSize=encoded(node.ExtentsSize)end
    if node:IsA("MeshPart")then for _,name in {"MeshId","TextureID","CollisionFidelity","RenderFidelity","DoubleSided"}do row.Properties[name]=encoded(node[name])end end
    if node:IsA("UnionOperation")then for _,name in {"UsePartColor","AssetId","CollisionFidelity","RenderFidelity","SmoothingAngle"}do local ok,value=pcall(function()return node[name]end);if ok then row.Properties[name]=encoded(value)end end end
   end
   if node:IsA("Attachment")then row.Properties.CFrame=encoded(node.CFrame);row.Properties.WorldCFrame=encoded(node.WorldCFrame)end
   if node:IsA("Model")then row.Properties.Pivot=encoded(node:GetPivot());row.Properties.Scale=node:GetScale();row.Properties.PrimaryPart=node.PrimaryPart;row.Properties.WorldPivot=encoded(node.WorldPivot)end
   if node:IsA("LuaSourceContainer")then row.Properties.Source=node.Source end
   result[node]=row
  end
 end
 return result
end

local function assertPreserved(before,roots)
 local after=snapshot(roots);local count=0
 for node,row in pairs(before)do assert(near(row,after[node]),"Original changed during fit audit: "..row.Name);count+=1 end
 for node in pairs(after)do assert(before[node],"New original-root descendant during audit: "..node:GetFullName())end
 return count
end

local function guardBaseline(baseline,roots)
 assert(baseline and baseline.migrationId=="CompactMap_V1","Pass the fresh complete BeforeManifest")
 assert(baseline.baselineManagedContentSHA256=="3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310","Wrong immutable managed baseline")
 assert(baseline.protectedAssetsContentSHA256=="bd66b9485de2f171ae7f33e2b5c5480e48f685d14126131cd53513b4f94b6a43","Wrong protected baseline")
 local current=indexedKeys(roots);local checked=0
 for _,rows in {baseline.objects,baseline.protectedSourceAssets}do
  for _,row in rows do
   local node=assert(current[row.key],"Baseline node missing "..row.path)
   assert(node.ClassName==row.class and node.Name==row.name,"Baseline identity changed "..row.path)
   assert(near((function()local out={};for k,v in pairs(node:GetAttributes())do out[k]=encoded(v)end;return out end)(),row.attributes),"Baseline attributes changed "..row.path)
   if row.properties then for name,value in pairs(row.properties)do
    if not (type(value)=="table" and value.unavailable)then assert(near(encoded(node[name]),value),"Baseline property changed "..row.path.."."..name)end
   end end
   if row.attachment then for _,name in {"CFrame","WorldCFrame"}do assert(near(encoded(node[name]),row.attachment[name]),"Baseline attachment changed "..row.path)end end
   if row.pivot then assert(near(encoded(node:GetPivot()),row.pivot),"Baseline pivot changed "..row.path);assert(node:GetScale()==row.scale,"Baseline scale changed "..row.path)end
   checked+=1
  end
 end
 local actual=0;for _ in pairs(current)do actual+=1 end
 assert(actual==checked,"Extra managed/protected objects appeared after capture")
 return checked
end
local G={}
function G.Run(options,operation)
 assert(Run:IsStudio()and not Run:IsRunning(),"Native compact fixture requires Edit")
 assert(game.PlaceId==91958083796436 and game.GameId==10548905405,"Wrong DEV")
 local adapter=assert(options.Adapter,"Fresh adapter required");adapter.CheckSources()
 local roots={assert(workspace:FindFirstChild("MapBlockout")),assert(game.ReplicatedStorage:FindFirstChild("StudioAssets"))}
 local checked=guardBaseline(assert(options.Baseline,"Fresh baseline required"),roots)
 local before=snapshot(roots)
 local stage=Instance.new("Folder");stage.Name="CompactMapV1_BaseFixture_"..Http:GenerateGUID(false);stage:SetAttribute("Owner","CompactMap_V1_BaseFixture");stage.Parent=SS
 local start=os.clock()
 local ok,result=xpcall(function()return operation(stage,adapter.Create())end,debug.traceback)
 stage:Destroy()
 local unchanged=assertPreserved(before,roots);adapter.CheckSources()
 assert(ok,"Native fixture failed; owned stage removed and originals unchanged: "..tostring(result))
 result.cleanup={stageRemoved=stage.Parent==nil,originalInstancesUnchanged=unchanged,originalSourcesUnchanged=true};result.baselineNodesChecked=checked;result.elapsedSeconds=os.clock()-start;result.nativeExecutionPassed=true
 return result
end
G.Snapshot=snapshot
G.AssertPreserved=assertPreserved
return G
]],"@Guard"))()
local Performance=assert(loadstring([[--!nocheck
-- Authorized controlled Edit render fixture. Root alone executes. No original/source/gameplay writes.
local P={};local Run=game:GetService('RunService');local Stats=game:GetService('Stats');local CS=game:GetService('CollectionService');local Http=game:GetService('HttpService')
local IDS={'BRT_002','BRT_028','BRT_006','BRT_001','BRT_010','BRT_012','BRT_016','BRT_019','BRT_027','BRT_031','BRT_032','BRT_030'}
local REQUIRED={'FrameTime','RenderCPUFrameTime','RenderGPUFrameTime','PhysicsStepTime','TotalMemoryMb'}
local EXTRA={'SceneDrawcallCount','SceneTriangleCount','InstanceCount','PrimitivesCount'}
local function metric(name)
 local ok,value=pcall(function()if name=='TotalMemoryMb'then return Stats:GetTotalMemoryUsageMb()end;return Stats[name]end)
 if ok and type(value)=='number'and value==value and math.abs(value)<math.huge then return value end
 return nil
end
local function properties(object,names)
 local out={};for _,name in names do local ok,value=pcall(function()return object[name]end);out[name]=if ok then tostring(value)else'Unsupported'end;return out
end
local function strip(clone)
 local nodes=clone:GetDescendants();table.insert(nodes,clone)
 for _,n in nodes do for _,tag in CS:GetTags(n)do CS:RemoveTag(n,tag)end;if n:IsA('LuaSourceContainer')then n:Destroy()end end
end
local function slots(base)
 local out={};for _,p in base:GetChildren()do if p:IsA('BasePart')then local i=p:GetAttribute('SlotIndex')or tonumber(p.Name:match('^Slot_(%d+)$'));if i then assert(i>=1 and i<=12 and not out[i],'Invalid fixture stable slot');out[i]={Index=i,Platform=p,Marker=assert(p:FindFirstChild('BrainrotPlacement'))}end end end
 for i=1,12 do assert(out[i],'Missing fixture slot')end;return out
end
local function baseFrame(base)
 local frame=base:GetAttribute('BaseOrigin');if typeof(frame)=='CFrame'then return frame end;return base:GetPivot()
end
local function schedule(map)
 local camp=CFrame.new(-19,.04999995231628418,-46)
 local b1=baseFrame(assert(map.PlayerBasePatches:FindFirstChild('Base_01')));local b8=baseFrame(assert(map.PlayerBasePatches:FindFirstChild('Base_08')))
 local beach=assert(map.ProgressionGates:FindFirstChild('Beach')):GetPivot();local volcano=assert(map.ProgressionGates:FindFirstChild('Volcano')):GetPivot()
 local out={}
 for _,v in {{'CampOverview',camp,Vector3.new(0,250,90),Vector3.new(0,0,0)},{'Base01',b1,Vector3.new(0,48,-76),Vector3.new(0,3,-23)},{'Base08',b8,Vector3.new(0,48,-76),Vector3.new(0,3,-23)},{'BeachGate',beach,Vector3.new(65,40,45),Vector3.new(0,0,0)},{'VolcanoGate',volcano,Vector3.new(-65,40,45),Vector3.new(0,0,0)}}do
  local eye,look=v[2]*v[3],v[2]*v[4];table.insert(out,{id=v[1],ownerFrame={v[2]:GetComponents()},cameraOffset={v[3].X,v[3].Y,v[3].Z},focusOffset={v[4].X,v[4].Y,v[4].Z},camera=CFrame.lookAt(eye,look),focus=CFrame.new(look),fov=70})
 end
 return out
end
local function summary(values)
 if #values==0 then return{status='Unsupported',count=0}end
 table.sort(values);local total=0;for _,v in values do total+=v end
 return{count=#values,min=values[1],max=values[#values],mean=total/#values,p50=values[math.ceil(#values*.5)],p95=values[math.ceil(#values*.95)]}
end
local function collectView(camera,view,options)
 local frameError=0;local focusError=0;local rows={};local viewportStart={camera.ViewportSize.X,camera.ViewportSize.Y};local getters={};for _,n in REQUIRED do getters[n]={}end;for _,n in EXTRA do getters[n]={}end
 local function ownCamera()
  camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=view.camera;camera.Focus=view.focus;camera.FieldOfView=view.fov
 end
 ownCamera();task.wait(options.WarmSeconds or 2)
 local start=os.clock();local last=start
 for index=1,120 do
  ownCamera();task.wait(options.SampleIntervalSeconds or 1/60)
  local now=os.clock();local row={index=index,wallElapsed=now-start,sampleInterval=now-last,metrics={}};last=now
  frameError=math.max(frameError,(camera.CFrame.Position-view.camera.Position).Magnitude,(camera.CFrame.LookVector-view.camera.LookVector).Magnitude);focusError=math.max(focusError,(camera.Focus.Position-view.focus.Position).Magnitude)
  for name,values in getters do local value=metric(name);if value~=nil then row.metrics[name]=value;table.insert(values,value)end end
  table.insert(rows,row)
 end
 local out={id=view.id,ownerFrame=view.ownerFrame,cameraOffset=view.cameraOffset,focusOffset=view.focusOffset,cameraCFrame={view.camera:GetComponents()},focus={view.focus:GetComponents()},fieldOfView=view.fov,viewportStart=viewportStart,viewportEnd={camera.ViewportSize.X,camera.ViewportSize.Y},maximumCameraError=frameError,maximumFocusError=focusError,elapsedSeconds=os.clock()-start,actualSamples=#rows,requiredSamples=120,samples=rows,metrics={},accepted=false,sampling='120 native Stats property readbacks at yielded wall-clock samples; not 120 unique GPU/CPU scope frames'}
 local allPositive=true
 for name,values in getters do
  local s=summary(values);local positives=0;for _,v in values do if v>0 then positives+=1 end end;s.positiveCount=positives
  s.status=if #values==120 and positives==120 then'All120PositiveNativeReadbacks'elseif #values==0 then'Unsupported'else'AvailableButPartialOrZero'
  s.rawUnit=if name=='FrameTime'then'seconds (official Stats docs)'elseif name=='TotalMemoryMb'then'MB (official Stats docs)'elseif table.find(EXTRA,name)then'count'else'native Stats property value; ratio comparison only'
  if table.find(REQUIRED,name)and s.status~='All120PositiveNativeReadbacks'then allPositive=false end;out.metrics[name]=s
 end
 out.cameraStable=frameError<=.001 and focusError<=.001 and out.viewportStart[1]==out.viewportEnd[1]and out.viewportStart[2]==out.viewportEnd[2]
 out.accepted=out.cameraStable and allPositive;out.status=if out.accepted then'ControlledNativeStatsSamplesComplete'else'NotAssessedMissingMetricOrCameraCoverage'
 return out
end
function P.Capture(options)
 assert(Run:IsStudio()and not Run:IsRunning(),'Performance fixture is native Studio Edit only')
 assert(game.PlaceId==91958083796436 and game.GameId==10548905405,'Wrong DEV')
 assert(options.Mode=='Before'or options.Mode=='After','Exact fixture mode required')
 local adapter=options.Adapter;adapter.CheckSources();local deps=adapter.Create();local map=assert(workspace:FindFirstChild('MapBlockout'));local assets=assert(game.ReplicatedStorage:FindFirstChild('StudioAssets'))
 local roots={map,assets};local before=options.Guard.Snapshot(roots)
 local stage=Instance.new('Folder');stage.Name='CompactMapV1_Performance_'..Http:GenerateGUID(false);stage:SetAttribute('Owner','CompactMap_V1_Performance');stage.Parent=workspace
 local camera=assert(workspace.CurrentCamera,"Current native camera required");local saved={Type=camera.CameraType,CFrame=camera.CFrame,Focus=camera.Focus,FieldOfView=camera.FieldOfView};local report
 local ok,reason=xpcall(function()
  local privateMap=Instance.new('Folder');privateMap.Name='MapBlockout';privateMap.Parent=stage
  local proposal=options.Proposed and options.Proposed.Create(deps)
  if options.Mode=='After'then
   local liveValue=assert(map:FindFirstChild('CompactMapRuntimeGeometry'),'Installed runtime geometry missing')
   assert(liveValue:IsA('StringValue')and map:GetAttribute('CompactMapMigrationId')=='CompactMap_V1'and map:GetAttribute('CompactMapStatus')=='Completed','Installed compact map is incomplete')
   local text=liveValue.Value
   local raw=Http:JSONDecode(text);assert(raw.runtimeValidated and raw.migrationId=='CompactMap_V1'and raw.planHash==map:GetAttribute('CompactMapDesiredHash'),'Actual installed validated after geometry/hash required')
   privateMap:SetAttribute('CompactMapMigrationId','CompactMap_V1');privateMap:SetAttribute('CompactMapStatus','Completed');privateMap:SetAttribute('CompactMapDesiredHash',raw.planHash)
   local value=Instance.new('StringValue');value.Name='CompactMapRuntimeGeometry';value.Value=text;value.Parent=privateMap
  end
  local calls,parts,bases=0,0,0
  for i=1,12 do
   local original=assert(map.PlayerBasePatches:FindFirstChild(string.format('Base_%02d',i)));local clone=original:Clone();clone.Parent=privateMap;strip(clone);clone:SetAttribute('Phase5DLayoutPivot',baseFrame(original));local ss=slots(clone)
   if options.Mode=='Before'then deps.Layout.Apply(clone,ss)else proposal.Layout.Apply(clone,ss)end
   for index,id in IDS do
    local def=assert(deps.Catalog.GetById(id));assert(def.launchStatus=='Live'and def.spawnEnabled==true,'Fixture species is not currently eligible')
    local visual=assert(deps.Factory:CreateItemVisual(id));visual.Parent=clone;strip(visual);deps.Place(visual,ss[index]);calls+=1
    for _,p in visual:GetDescendants()do if p:IsA('BasePart')then p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false end end
   end
   for _,p in clone:GetDescendants()do if p:IsA('BasePart')then p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;parts+=1 end end
   bases+=1;task.wait()
  end
  assert(calls==144 and bases==12,'Incomplete controlled display population')
  report={schemaVersion=1,migrationId='CompactMap_V1',mode=options.Mode,scope='Controlled Edit render fixture, source-exact owner base presentation with 144 released canonical static display clones',placeId=game.PlaceId,universeId=game.GameId,engine=(function()local f=getfenv(0).version;return if type(f)=="function"then f()else"Unavailable"end)(),sourceEvidence=options.SourceEvidence,fixtureSpeciesByStableSlot=IDS,fixtureBaseCount=bases,fixtureFactoryPlacements=calls,fixtureBaseParts=parts,fixtureStageOwner='CompactMap_V1_Performance',profilesOrEconomyStarted=false,gameplayAcceptance=false,multiplayerAcceptance=false,phoneGpuAcceptance=false,originalSourceWrites=0,originalObjectWrites=0,controlledCameraOnly=true,lighting={clockTime=game.Lighting.ClockTime,brightness=game.Lighting.Brightness,exposure=game.Lighting.ExposureCompensation},renderSettings=properties(settings().Rendering,{'QualityLevel','EditQualityLevel'}),viewport={camera.ViewportSize.X,camera.ViewportSize.Y},views={},metricSource='Native Stats properties; official docs https://create.roblox.com/docs/reference/engine/classes/Stats',limitations={'This is controlled Edit rendering with additional duplicate cloned base geometry, not ordinary Play or full twelve-player load.','120 wall-clock yielded samples may observe repeated engine frames; no unique native GPU frame/scope proof is claimed.','Stats.FrameTime is client-only; if unavailable/zero in this privileged Edit VM the view is NotAssessed.','All raw CPU/GPU/Physics values are preserved; no undocumented unit conversion.','Root must compare exact quality, viewport, engine, clock, species/slots, source construction method and metric availability before ratios.'}}
  for _,view in schedule(map)do table.insert(report.views,collectView(camera,view,options));task.wait()end
  report.nativeStatsCoverageComplete=true;for _,view in report.views do if not view.accepted then report.nativeStatsCoverageComplete=false end end
  report.status=if report.nativeStatsCoverageComplete then'ControlledStatsCompleteGameplayUnverified'else'NotAssessedMetricCoveragePartial'
 end,debug.traceback)
 stage:Destroy();camera.CameraType=saved.Type;camera.CFrame=saved.CFrame;camera.Focus=saved.Focus;camera.FieldOfView=saved.FieldOfView
 local unchanged=options.Guard.AssertPreserved(before,roots);adapter.CheckSources()
 assert(ok,'Controlled performance fixture failed; cleanup completed: '..tostring(reason))
 report.cleanup={fixtureRemoved=stage.Parent==nil,originalNodesPreserved=unchanged,originalSourcesPreserved=true,cameraRestored=true};return report
end
return P
]],"@Performance"))()
local Proposed=assert(loadstring([=[local P={}
function P.Create(deps)
local geometry=assert(loadstring([[--!strict
-- Read-only CompactMap_V1 runtime geometry. Values are final locals, never scaled again.
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Geometry = {}
local MIGRATION = "CompactMap_V1"
local MAX_BYTES, MAX_WALLS, CELL_SIZE, MAX_CELLS = 200000, 512, 64, 8192
local SERVICE_SIZES = {AnnouncementStall={56,1,32},BrainrotTrainStall={56,1,32},BuyCartStall={64,1,40},KitStall={56,1,32},SellStall={56,1,32},WeaponHarpoonStall={56,1,32}}
local cache: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local function finite(v: any): boolean
 return type(v)=="number" and v==v and math.abs(v)<math.huge
end
local function number(v: any, label: string): number
 assert(finite(v), "Compact geometry finite number required: "..label)
 return v
end
local function positive(v: any, label: string): number
 local n=number(v,label);assert(n>0,"Compact geometry positive size required: "..label);return n
end
local function array(v: any, maximum: number, label: string): any
 assert(type(v)=="table","Compact geometry array required: "..label)
 local count=0
 for k in v do assert(type(k)=="number" and k%1==0 and k>=1 and k<=maximum,"Compact geometry dense bounded array required: "..label);count+=1 end
 assert(count==#v,"Compact geometry sparse array: "..label)
 for i=1,count do assert(v[i]~=nil,"Compact geometry missing array member: "..label) end
 return v
end
local function freeze(v: any): any
 if type(v)=="table" and not table.isfrozen(v) then for _,child in v do freeze(child) end;table.freeze(v) end
 return v
end
local function copy(v: any): any
 if type(v)~="table" then return v end
 local out={};for k,child in v do out[k]=copy(child) end;return out
end
local function rectangle(v: any, label: string): any
 assert(type(v)=="table","Compact geometry rectangle required: "..label)
 return {centreX=number(v.centreX,label..".centreX"),centreZ=number(v.centreZ,label..".centreZ"),width=positive(v.width,label..".width"),depth=positive(v.depth,label..".depth"),frontSign=v.frontSign}
end
function Geometry.Validate(raw: any): any
 assert(type(raw)=="table" and raw.schemaVersion==1 and raw.migrationId==MIGRATION,"Compact geometry schema mismatch")
 assert(raw.runtimeValidated==true,"Compact geometry must be validated before runtime")
 assert(type(raw.planHash)=="string" and #raw.planHash==64 and raw.planHash:match("^[0-9a-f]+$"),"Compact geometry plan hash required")
 assert(type(raw.bases)=="table","Compact geometry bases required")
 local bases,count={},0
 for id,g in raw.bases do
  count+=1;assert(type(id)=="string" and id:match("^Base_%d%d$"),"Compact geometry base ID invalid")
  assert(type(g)=="table","Compact geometry base row required")
  local z=array(g.zCenters,6,id..".zCenters");assert(#z==6,"Compact geometry needs six row centres")
  for i=1,6 do number(z[i],id..".zCenters");if i>1 then assert(z[i]>z[i-1],"Compact geometry row order invalid") end end
  local stride=z[2]-z[1]
  for i=3,6 do assert(math.abs((z[i]-z[i-1])-stride)<=1e-6,"Compact geometry row spacing must be uniform") end
  local slots=array(g.slots,12,id..".slots");assert(#slots==12,"Compact geometry needs twelve stable slots")
  local row={rowOffsetX=positive(g.rowOffsetX,id..".rowOffsetX"),formationCenterX=number(g.formationCenterX,id..".formationCenterX"),formationCenterZ=number(g.formationCenterZ,id..".formationCenterZ"),padNormalStuds=positive(g.padNormalStuds,id..".padNormalStuds"),padTangentialStuds=positive(g.padTangentialStuds,id..".padTangentialStuds"),support=rectangle(g.support,id..".support"),perimeter=rectangle(g.perimeter,id..".perimeter"),zCenters=copy(z),slots={}}
  assert(math.abs((z[1]+z[6])/2-row.formationCenterZ)<=1e-6,"Compact geometry formation centroid mismatch")
  row.perimeter.postWidth=positive(g.perimeter.postWidth,id..".perimeter.postWidth")
  row.perimeter.postDepth=positive(g.perimeter.postDepth,id..".perimeter.postDepth")
  assert(row.perimeter.width>2*row.perimeter.postWidth and row.perimeter.depth>2*row.perimeter.postDepth,"Compact perimeter is too small for posts")
  assert(row.perimeter.frontSign==nil or row.perimeter.frontSign==1 or row.perimeter.frontSign==-1,"Compact geometry front sign invalid")
  for i,slot in slots do
   local side=if i<=6 then -1 else 1;local station=if i<=6 then i else i-6
   assert(type(slot)=="table" and slot.Index==i and slot.Side==side,"Compact geometry stable slot identity/order changed")
   local x,sz=number(slot.X,id..".slotX"),number(slot.Z,id..".slotZ")
   assert(math.abs(x-(row.formationCenterX+side*row.rowOffsetX))<=1e-6 and math.abs(sz-z[station])<=1e-6,"Compact geometry uniform final slot local mismatch")
   assert(slot.PadNormalStuds==nil or math.abs(slot.PadNormalStuds-row.padNormalStuds)<=1e-6,"Compact geometry slot normal size mismatch")
   assert(slot.PadTangentialStuds==nil or math.abs(slot.PadTangentialStuds-row.padTangentialStuds)<=1e-6,"Compact geometry slot tangential size mismatch")
   assert(math.abs(x-row.support.centreX)+row.padNormalStuds/2<=row.support.width/2+.01 and math.abs(sz-row.support.centreZ)+row.padTangentialStuds/2<=row.support.depth/2+.01,"Compact geometry pad outside its support floor")
   row.slots[i]={Index=i,Side=side,X=x,Z=sz,PadNormalStuds=row.padNormalStuds,PadTangentialStuds=row.padTangentialStuds}
  end
  bases[id]=row
 end
 assert(count==12,"Compact geometry requires twelve bases")
 for i=1,12 do assert(bases[string.format("Base_%02d",i)],"Compact geometry base missing") end
 local services=Geometry.ValidateServices(raw.services)
 local walls=Geometry.ValidateWalls(raw.staticWallObstacles or {})
 return freeze({schemaVersion=1,migrationId=MIGRATION,planHash=raw.planHash,bases=bases,services=services,staticWallObstacles=walls})
end
function Geometry.ValidateServices(raw: any): any
 assert(type(raw)=="table","Compact geometry services required")
 local out,count={},0
 for id,row in raw do
  count+=1;local expected=SERVICE_SIZES[id]
  assert(expected and type(row)=="table","Compact geometry service identity invalid")
  local size=array(row.logicalInteractionEnvelope,3,"service.logicalInteractionEnvelope")
  assert(#size==3,"Compact geometry service interaction envelope needs three dimensions")
  for i=1,3 do assert(positive(size[i],"service.logicalInteractionEnvelope")==expected[i],"Compact service logical interaction envelope changed") end
  out[id]={logicalInteractionEnvelope=copy(size)}
 end
 assert(count==6,"Compact geometry needs six stable services")
 for id in SERVICE_SIZES do assert(out[id],"Compact geometry service missing") end
 return freeze(out)
end
function Geometry.ValidateWalls(raw: any): any
 local rows=array(raw,MAX_WALLS,"staticWallObstacles");local seen,out={},{}
 for _,row in rows do
  assert(type(row)=="table" and type(row.id)=="string" and #row.id>0 and #row.id<=128 and not seen[row.id],"Compact static wall ID invalid/duplicate")
  local r={id=row.id,minX=number(row.minX,"wall.minX"),maxX=number(row.maxX,"wall.maxX"),minY=number(row.minY,"wall.minY"),maxY=number(row.maxY,"wall.maxY"),minZ=number(row.minZ,"wall.minZ"),maxZ=number(row.maxZ,"wall.maxZ")}
  assert(r.minX<r.maxX and r.minY<r.maxY and r.minZ<r.maxZ,"Compact static wall bounds invalid")
  seen[r.id]=true;table.insert(out,r)
 end
 table.sort(out,function(a,b)return a.id<b.id end)
 return freeze(out)
end
function Geometry.Read(map: Instance?): any?
 if map==nil then return nil end
 local migration,status,hash=map:GetAttribute("CompactMapMigrationId"),map:GetAttribute("CompactMapStatus"),map:GetAttribute("CompactMapDesiredHash")
 local value=map:FindFirstChild("CompactMapRuntimeGeometry")
 if migration==nil and status==nil and hash==nil and value==nil then return nil end
 assert(migration==MIGRATION and status=="Completed","Compact geometry is incomplete or has an unknown migration")
 assert(value and value:IsA("StringValue") and #value.Value<=MAX_BYTES,"Compact runtime geometry missing/oversize")
 local saved=cache[map]
 if saved then
  assert(saved.value==value and saved.hash==hash and saved.text==value.Value,"Compact runtime geometry changed during session; restart required")
  return saved.data
 end
 local raw=HttpService:JSONDecode(value.Value);local data=Geometry.Validate(raw)
 assert(data.planHash==hash,"Compact runtime geometry desired hash mismatch")
 cache[map]={value=value,hash=hash,text=value.Value,data=data}
 return data
end
function Geometry.ResolveBase(base: Model): any?
 local ancestor: Instance?=base.Parent
 while ancestor and ancestor.Name~="MapBlockout" do ancestor=ancestor.Parent end
 if ancestor==nil then
  assert(base:GetAttribute("CompactMapMigrationId")==nil,"Compact base has no canonical map owner")
  return nil
 end
 local data=Geometry.Read(ancestor);if data==nil then return nil end
 local id=base:GetAttribute("BaseId");assert(type(id)=="string" and data.bases[id],"Compact base ID has no canonical geometry")
 return data.bases[id]
end
function Geometry.ResolveInteractionSize(part: BasePart): Vector3
 assert(part and part:IsA("BasePart"),"Service interaction requires a BasePart")
 local ancestor: Instance?=part.Parent
 while ancestor and ancestor.Name~="MapBlockout" do ancestor=ancestor.Parent end
 if ancestor==nil then
  assert(part:GetAttribute("CompactMapMigrationId")==nil,"Compact service has no canonical map owner")
  return part.Size
 end
 local data=Geometry.Read(ancestor);if data==nil then return part.Size end
 local patches=ancestor:FindFirstChild("ServiceStallPatches")
 assert(patches and part.Parent==patches and part:GetAttribute("LayoutRole")=="ServiceStall","Compact service identity/owner changed")
 local row=data.services[part.Name];assert(row,"Compact service has no canonical logical envelope")
 local size=part:GetAttribute("LogicalInteractionEnvelope")
 assert(typeof(size)=="Vector3" and finite(size.X) and finite(size.Y) and finite(size.Z),"Compact service logical interaction envelope missing/invalid")
 local expected=row.logicalInteractionEnvelope
 assert(math.abs(size.X-expected[1])<=1e-6 and math.abs(size.Y-expected[2])<=1e-6 and math.abs(size.Z-expected[3])<=1e-6,"Compact service logical interaction envelope drifted")
 return size
end
function Geometry.Current(): any? return Geometry.Read(Workspace:FindFirstChild("MapBlockout")) end
local function key(x: number,z: number): string return tostring(x)..":"..tostring(z) end
function Geometry.BuildWallIndex(raw: any): any
 local rows=Geometry.ValidateWalls(raw);local cells,count={},0
 for _,row in rows do
  local nx=math.floor(row.maxX/CELL_SIZE)-math.floor(row.minX/CELL_SIZE)+1
  local nz=math.floor(row.maxZ/CELL_SIZE)-math.floor(row.minZ/CELL_SIZE)+1
  assert(nx*nz<=MAX_CELLS,"Compact wall mask single row cell budget exceeded")
  for x=math.floor(row.minX/CELL_SIZE),math.floor(row.maxX/CELL_SIZE) do
   for z=math.floor(row.minZ/CELL_SIZE),math.floor(row.maxZ/CELL_SIZE) do
    local k=key(x,z);if cells[k]==nil then cells[k]={};count+=1;assert(count<=MAX_CELLS,"Compact wall mask cell budget exceeded") end
    table.insert(cells[k],row)
   end
  end
 end
 return freeze({rows=rows,cells=cells,cellSize=CELL_SIZE})
end
function Geometry.WallHit(index: any,frame: CFrame,size: Vector3,padding: number?): string?
 assert(type(index)=="table" and index.cellSize==CELL_SIZE,"Compact wall index required")
 assert(typeof(frame)=="CFrame" and typeof(size)=="Vector3","Compact wall envelope types invalid")
 for _,v in {frame:GetComponents()} do assert(finite(v),"Compact wall envelope frame invalid") end
 assert(finite(size.X) and finite(size.Y) and finite(size.Z) and size.X>0 and size.Y>0 and size.Z>0,"Compact wall envelope size invalid")
 local p=padding or 0;assert(finite(p) and p>=0,"Compact wall mask padding invalid")
 local half=size*.5
 local ex=math.abs(frame.RightVector.X)*half.X+math.abs(frame.UpVector.X)*half.Y+math.abs(frame.LookVector.X)*half.Z
 local ey=math.abs(frame.RightVector.Y)*half.X+math.abs(frame.UpVector.Y)*half.Y+math.abs(frame.LookVector.Y)*half.Z
 local ez=math.abs(frame.RightVector.Z)*half.X+math.abs(frame.UpVector.Z)*half.Y+math.abs(frame.LookVector.Z)*half.Z
 local x0,x1,z0,z1=frame.X-ex-p,frame.X+ex+p,frame.Z-ez-p,frame.Z+ez+p
 local y0,y1=frame.Y-ey,frame.Y+ey;local seen={}
 local nx=math.floor(x1/CELL_SIZE)-math.floor(x0/CELL_SIZE)+1
 local nz=math.floor(z1/CELL_SIZE)-math.floor(z0/CELL_SIZE)+1
 assert(finite(nx*nz) and nx*nz<=MAX_CELLS,"Compact wall query cell budget exceeded")
 for x=math.floor(x0/CELL_SIZE),math.floor(x1/CELL_SIZE) do
  for z=math.floor(z0/CELL_SIZE),math.floor(z1/CELL_SIZE) do
   for _,wall in index.cells[key(x,z)] or {} do
    if seen[wall.id] then continue end;seen[wall.id]=true
    if x0<wall.maxX and x1>wall.minX and z0<wall.maxZ and z1>wall.minZ and y0<wall.maxY and y1>wall.minY then return wall.id end
   end
  end
 end
 return nil
end
return table.freeze(Geometry)
]],"@ProposedCompactGeometry"))()
local confChunk=assert(loadstring([[--!strict

local CompactMapGeometry = injectedGeometry

-- The 36-by-32-stud footprint is a project visual estimate derived from the
-- compact reference layout, not an official published dimension.
local BaseLayoutConfig = {
	STANDARD_ROBLOX_PLAYER_HEIGHT_STUDS = 5.0,
	BRAINROT_TARGET_VISIBLE_HEIGHT_STUDS = 3.5,
	PLATFORM_DIAGONAL_STUDS = 3.0,
	PLATFORM_SIDE_STUDS = 3 / math.sqrt(2),

	BASE_FOOTPRINT_WIDTH_STUDS = 36,
	BASE_FOOTPRINT_DEPTH_STUDS = 32,
	BASE_WALL_HEIGHT_STUDS = 10,
	BASE_WALL_THICKNESS_STUDS = 1,
	PLATFORM_COUNT = 12,
	PLATFORMS_PER_SIDE = 6,
	PLATFORM_ROW_OFFSET_X = 7.25,
	PLATFORM_Z_CENTERS = table.freeze({ -11.25, -6.75, -2.25, 2.25, 6.75, 11.25 }),

	PLAQUE_INWARD_DEPTH_STUDS = 1.75,
	PLAQUE_TANGENTIAL_WIDTH_STUDS = 3.0,
	PLAQUE_HEIGHT_STUDS = 0.20,
	PLAQUE_PLATFORM_GAP_STUDS = 0.25,
	PLAQUE_VISIBLE_RISE_STUDS = 0.03,
	-- The visible plaque remains flush and non-colliding. This invisible vertical
	-- contact envelope reaches ordinary avatar feet, which rest above the floor.
	PLAQUE_TOUCH_HEIGHT_STUDS = 1.0,
	PLAQUE_TOUCH_COOLDOWN_SECONDS = 0.5,
}

-- Compact values are final evaluated locals; all original scale/economy constants remain unchanged.
function BaseLayoutConfig.GetGeometry(base: Model): any?
	return CompactMapGeometry.ResolveBase(base)
end

return table.freeze(BaseLayoutConfig)
]],"@ProposedBaseLayoutConfig"))
setfenv(confChunk,setmetatable({injectedGeometry=geometry},{__index=getfenv(0)}))
local config=confChunk();local localDeps={Config=config,Material=deps.Material}
local layout=assert(loadstring([[return function(deps)
local Config,StaticMaterial=deps.Config,deps.Material
local PLAQUE_TAG = "BrainrotIncomePlaque"
local LAYOUT_CONTAINER_NAME = "Phase5DInterior"
local PLAQUE_CONTAINER_NAME = "IncomePlaques"
local TOUCH_SENSOR_NAME = "TouchSensor"
local AMOUNT_SURFACE_NAME = "AmountSurfaceGui"
local AMOUNT_LABEL_NAME = "AmountLabel"
local AMOUNT_STROKE_NAME = "AmountStroke"
local PLAQUE_WIDTH_STUDS = 3.5
local PLAQUE_THICKNESS_STUDS = 0.18
local PLAQUE_DEPTH_STUDS = 2.25
local PLAQUE_PLATFORM_GAP_STUDS = 0.55
local PLAQUE_FLOOR_CLEARANCE_STUDS = 0.02
local PLAQUE_SNAPSHOT_REFRESH_SECONDS = 1
local PILLAR_MANAGED_BY = "BaseIncomePlaqueSystem"
local PILLAR_ORIGINAL_WIDTH_STUDS = 1.25
local PILLAR_ORIGINAL_DEPTH_STUDS = 1.25
local PILLAR_WIDTH_STUDS = PILLAR_ORIGINAL_WIDTH_STUDS * 0.5
local PILLAR_DEPTH_STUDS = PILLAR_ORIGINAL_DEPTH_STUDS * 0.5
local PILLAR_MAX_SPACING_STUDS = 6
local ENTRANCE_CLEAR_WIDTH_STUDS = 10
local LEGACY_WALL_NAMES = table.freeze({ "LeftWall", "RightWall", "BackWall" })

type StructuralStyle = {
	PostWidth: number?,
	PostDepth: number?,
	Color: Color3,
	Material: Enum.Material,
	MaterialVariant: string,
	EffectivePhysicalProperties: PhysicalProperties,
	CollisionGroup: string,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
}
local function platformIdFromPart(platform: BasePart): number?
	local attribute = platform:GetAttribute("SlotIndex")
	if type(attribute) == "number" and attribute % 1 == 0 then
		return attribute
	end
	return tonumber(platform.Name:match("^Slot_(%d+)$"))
end

local function baseRootCFrame(base: Model): CFrame
	local saved = base:GetAttribute("Phase5DLayoutPivot")
	if typeof(saved) == "CFrame" then
		return saved
	end
	local root = base:GetPivot()
	base:SetAttribute("Phase5DLayoutPivot", root)
	return root
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), name .. " must be a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensurePart(base: Model, container: Folder, name: string): (BasePart, boolean)
	local existing = base:FindFirstChild(name) or container:FindFirstChild(name)
	if existing then
		assert(existing:IsA("BasePart"), name .. " must be a BasePart")
		return existing, false
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Parent = container
	return part, true
end

local function configureStructuralPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	StaticMaterial.Apply(part, Enum.Material.SmoothPlastic)
	part.Color = Color3.fromRGB(91, 98, 104)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function platformTopLocalY(root: CFrame, platform: BasePart): number
	return root:PointToObjectSpace(platform.Position).Y + platform.Size.Y / 2
end

local function entranceSign(base: Model, root: CFrame): number
	for _, name in { "CartSpawn", "PlayerSpawn" } do
		local marker = base:FindFirstChild(name)
		if marker and marker:IsA("BasePart") then
			local localZ = root:PointToObjectSpace(marker.Position).Z
			if math.abs(localZ) > 0.01 then
				return if localZ > 0 then 1 else -1
			end
		end
	end
	return -1
end

local function captureStructuralStyle(part: BasePart): StructuralStyle
	return {
		Color = part.Color,
		Material = part.Material,
		MaterialVariant = part.MaterialVariant,
		EffectivePhysicalProperties = part.CurrentPhysicalProperties,
		CollisionGroup = part.CollisionGroup,
		CanCollide = part.CanCollide,
		CanTouch = part.CanTouch,
		CanQuery = part.CanQuery,
	}
end

local function legacyWall(base: Model, container: Folder, name: string): BasePart?
	local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
	return if candidate and candidate:IsA("BasePart") then candidate else nil
end

local function removeLegacyWalls(base: Model, container: Folder)
	for _, name in LEGACY_WALL_NAMES do
		local direct = base:FindFirstChild(name)
		if direct and direct:IsA("BasePart") then
			direct:Destroy()
		end
		local generated = container:FindFirstChild(name)
		if generated and generated:IsA("BasePart") then
			generated:Destroy()
		end
	end
end

local function clearManagedPillars(container: Folder)
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("ManagedBy") == PILLAR_MANAGED_BY then
			child:Destroy()
		end
	end
end

local function createPillar(
	container: Folder,
	root: CFrame,
	name: string,
	localPosition: Vector3,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle
)
	local pillar = Instance.new("Part")
	pillar.Name = name
	pillar:SetAttribute("ManagedBy", PILLAR_MANAGED_BY)
	configureStructuralPart(pillar)
	pillar.Size = Vector3.new(style.PostWidth or PILLAR_WIDTH_STUDS, pillarHeight, style.PostDepth or PILLAR_DEPTH_STUDS)
	pillar.CFrame = root
		* CFrame.new(localPosition.X, floorTopY + pillarHeight / 2, localPosition.Z)
	pillar.Color = style.Color
	pillar.Material = style.Material
	pillar.MaterialVariant = style.MaterialVariant
	pillar.CustomPhysicalProperties = style.EffectivePhysicalProperties
	pillar.CollisionGroup = style.CollisionGroup
	pillar.CanCollide = style.CanCollide
	pillar.CanTouch = style.CanTouch
	pillar.CanQuery = style.CanQuery
	StaticMaterial.Apply(pillar)
	pillar.Parent = container
end

local function createPillarsAlongEdge(
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle,
	edgeName: string,
	startLocalPosition: Vector3,
	endLocalPosition: Vector3,
	shouldSkip: ((Vector3) -> boolean)?
)
	local edgeLength = (endLocalPosition - startLocalPosition).Magnitude
	local intervalCount = math.max(1, math.ceil(edgeLength / PILLAR_MAX_SPACING_STUDS))
	local placedIndex = 0
	for interval = 1, intervalCount - 1 do
		local localPosition = startLocalPosition:Lerp(endLocalPosition, interval / intervalCount)
		if not shouldSkip or not shouldSkip(localPosition) then
			placedIndex += 1
			createPillar(
				container,
				root,
				string.format("BasePillar_%s_%02d", edgeName, placedIndex),
				localPosition,
				floorTopY,
				pillarHeight,
				style
			)
		end
	end
end

local function createPerimeterPillars(
	base: Model,
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle,
	geometry: any?
)
	clearManagedPillars(container)
	-- Preserve the established perimeter centreline while reducing only each
	-- pillar's horizontal cross-section.
	local perimeter = if geometry then geometry.perimeter else nil
	local width = if perimeter then perimeter.width else Config.BASE_FOOTPRINT_WIDTH_STUDS
	local depth = if perimeter then perimeter.depth else Config.BASE_FOOTPRINT_DEPTH_STUDS
	local centreX = if perimeter then perimeter.centreX else 0
	local centreZ = if perimeter then perimeter.centreZ else 0
	local postWidth = if perimeter then perimeter.postWidth else PILLAR_WIDTH_STUDS
	local postDepth = if perimeter then perimeter.postDepth else PILLAR_DEPTH_STUDS
	style = table.clone(style)
	style.PostWidth = postWidth
	style.PostDepth = postDepth
	local halfWidth = (width - (if perimeter then postWidth * 2 else PILLAR_ORIGINAL_WIDTH_STUDS)) / 2
	local halfDepth = (depth - (if perimeter then postDepth * 2 else PILLAR_ORIGINAL_DEPTH_STUDS)) / 2
	local frontSign = if perimeter and perimeter.frontSign then perimeter.frontSign else entranceSign(base, root)
	local frontZ = centreZ + frontSign * halfDepth
	local backZ = centreZ - frontSign * halfDepth
	local frontLeft = Vector3.new(centreX - halfWidth, 0, frontZ)
	local frontRight = Vector3.new(centreX + halfWidth, 0, frontZ)
	local backLeft = Vector3.new(centreX - halfWidth, 0, backZ)
	local backRight = Vector3.new(centreX + halfWidth, 0, backZ)

	for name, localPosition in
		{
			BasePillar_Corner_FL = frontLeft,
			BasePillar_Corner_FR = frontRight,
			BasePillar_Corner_BL = backLeft,
			BasePillar_Corner_BR = backRight,
		}
	do
		createPillar(container, root, name, localPosition, floorTopY, pillarHeight, style)
	end

	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Front",
		frontLeft,
		frontRight,
		function(localPosition)
			return math.abs(localPosition.X - centreX) < ENTRANCE_CLEAR_WIDTH_STUDS / 2
		end
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Back",
		backLeft,
		backRight,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Left",
		frontLeft,
		backLeft,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Right",
		frontRight,
		backRight,
		nil
	)
end

local function ensureInterior(base: Model, root: CFrame, platformFloorY: number, geometry: any?): number
	local container = ensureFolder(base, LAYOUT_CONTAINER_NAME)
	local floor: BasePart? = nil
	if geometry then
		-- Compact support reuses the migrated authoritative Foundation. No coplanar runtime floor.
		local foundation = base:FindFirstChild("Foundation")
		assert(foundation and foundation:IsA("BasePart") and foundation:GetAttribute("LayoutRole") == "Foundation", "Compact base Foundation is missing or has changed identity")
		floor = foundation :: BasePart
	else
		for _, name in { "BaseFloor", "Floor", "InteriorFloor", "GroundFloor" } do
			local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
			if candidate and candidate:IsA("BasePart") then
				floor = candidate
				break
			end
		end
	end
	local createdFloor = false
	if not floor then
		floor, createdFloor = ensurePart(base, container, "BaseFloor")
	end
	local resolvedFloor = floor :: BasePart
	local floorThickness = if createdFloor then 1 else math.max(resolvedFloor.Size.Y, 0.2)
	local floorTopY = if createdFloor
		then platformFloorY
		else platformTopLocalY(root, resolvedFloor)
	if geometry then
		-- Retain the authoritative Foundation colour, flags and effective physics.
		StaticMaterial.Apply(resolvedFloor)
	else
		configureStructuralPart(resolvedFloor)
	end
	local support = if geometry then geometry.support else nil
	resolvedFloor.Size = Vector3.new(
		if support then support.width else Config.BASE_FOOTPRINT_WIDTH_STUDS,
		floorThickness,
		if support then support.depth else Config.BASE_FOOTPRINT_DEPTH_STUDS
	)
	resolvedFloor.CFrame = root * CFrame.new(
		if support then support.centreX else 0, floorTopY - floorThickness / 2,
		if support then support.centreZ else 0
	)

	local pillarStyle = captureStructuralStyle(resolvedFloor)
	local pillarHeight = Config.BASE_WALL_HEIGHT_STUDS
	for _, wallName in LEGACY_WALL_NAMES do
		local wall = legacyWall(base, container, wallName)
		if wall then
			pillarStyle = captureStructuralStyle(wall)
			pillarHeight = wall.Size.Y
			break
		end
	end
	removeLegacyWalls(base, container)
	createPerimeterPillars(base, container, root, floorTopY, pillarHeight, pillarStyle, geometry)
	return floorTopY
end

local function setMarkerFacing(slot: any, platformCFrame: CFrame, markerOffset: CFrame)
	if slot.Marker:IsA("Attachment") then
		slot.Marker.CFrame = CFrame.new(markerOffset.Position)
	else
		local marker = slot.Marker :: BasePart
		marker.CFrame = platformCFrame * CFrame.new(markerOffset.Position)
	end
end

local function positionPlatforms(root: CFrame, slots: { any }, geometry: any?): (any, number)
	local ordered = table.clone(slots)
	table.sort(ordered, function(left, right)
		return left.Index < right.Index
	end)
	assert(#ordered == Config.PLATFORM_COUNT, "Phase 5D requires exactly 12 platforms")
	local placementById = {}
	local floorY = math.huge
	for order, slot in ordered do
		local platform = slot.Platform :: BasePart
		local platformId = platformIdFromPart(platform)
		assert(platformId == slot.Index, "Platform stable ID changed during layout")
		local topY = platformTopLocalY(root, platform)
		floorY = math.min(floorY, topY - platform.Size.Y)
		local side = if order <= Config.PLATFORMS_PER_SIDE then -1 else 1
		local row = if side < 0 then order else order - Config.PLATFORMS_PER_SIDE
		local canonical = if geometry then geometry.slots[slot.Index] else nil
		assert(not canonical or (canonical.Index == slot.Index and canonical.Side == side), "Compact stable slot identity changed")
		local x = if canonical then canonical.X else side * Config.PLATFORM_ROW_OFFSET_X
		local z = if canonical then canonical.Z else Config.PLATFORM_Z_CENTERS[row]
		local normalSize = if canonical then canonical.PadNormalStuds else Config.PLATFORM_SIDE_STUDS
		local tangentSize = if canonical then canonical.PadTangentialStuds else Config.PLATFORM_SIDE_STUDS
		local aisleX = if geometry then geometry.formationCenterX else 0
		local localPosition = Vector3.new(x, topY - platform.Size.Y / 2, z)
		local localFacing = CFrame.lookAt(
			localPosition,
			Vector3.new(aisleX, localPosition.Y, localPosition.Z),
			Vector3.yAxis
		)
		local markerOffset = if slot.Marker:IsA("Attachment")
			then slot.Marker.CFrame
			else platform.CFrame:ToObjectSpace((slot.Marker :: BasePart).CFrame)
		platform.Size =
			Vector3.new(tangentSize, platform.Size.Y, normalSize)
		platform.CFrame = root * localFacing
		platform.Anchored = true
		setMarkerFacing(slot, platform.CFrame, markerOffset)
		placementById[slot.Index] = {
			Side = side,
			XCenter = x,
			ZCenter = z,
			PlatformNormalStuds = normalSize,
			PlatformTopY = topY,
		}
	end
	assert(floorY < math.huge, "Phase 5D platforms have no usable floor datum")
	return placementById, floorY
end
local function getPlaqueName(platformId: number): string
	return "IncomePlaque_" .. tostring(platformId)
end
local function configurePlaque(
	state: any,
	plaque: BasePart,
	platformId: number,
	placement: any,
	floorTopY: number
)
	plaque.Name = getPlaqueName(platformId)
	plaque.Size = Vector3.new(PLAQUE_WIDTH_STUDS, PLAQUE_THICKNESS_STUDS, PLAQUE_DEPTH_STUDS)
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.CanTouch = false
	plaque.CanQuery = true
	plaque.Massless = true
	plaque.Color = Color3.fromRGB(60, 255, 90)
	plaque.Transparency = 0
	StaticMaterial.Apply(plaque, Enum.Material.SmoothPlastic)
	plaque.TopSurface = Enum.SurfaceType.Smooth
	plaque.BottomSurface = Enum.SurfaceType.Smooth
	local inward = placement.PlatformNormalStuds / 2
		+ PLAQUE_PLATFORM_GAP_STUDS
		+ PLAQUE_DEPTH_STUDS / 2
	local plaqueX = placement.XCenter - placement.Side * inward
	local plaqueY = floorTopY + PLAQUE_FLOOR_CLEARANCE_STUDS + PLAQUE_THICKNESS_STUDS / 2
	local plaquePosition =
		state.Root:PointToWorldSpace(Vector3.new(plaqueX, plaqueY, placement.ZCenter))
	local inwardDirection = state.Root:VectorToWorldSpace(Vector3.new(-placement.Side, 0, 0))
	local levelInward = Vector3.new(inwardDirection.X, 0, inwardDirection.Z).Unit
	plaque.CFrame = CFrame.lookAt(plaquePosition, plaquePosition + levelInward, Vector3.yAxis)

	-- The contact envelope follows this pad, not a second offset layout.
	local claimSensorCFrame = plaque.CFrame
		* CFrame.new(0, PLAQUE_THICKNESS_STUDS / 2 + Config.PLAQUE_TOUCH_HEIGHT_STUDS / 2, 0)
 return claimSensorCFrame
end
return {Apply=function(base,slots)local root=baseRootCFrame(base);local geometry=assert(Config.GetGeometry(base));local placements,floorY=positionPlatforms(root,slots,geometry);return root,placements,ensureInterior(base,root,floorY,geometry)end,ConfigurePlaqueGeometry=configurePlaque}

end]],"@ProposedBaseOwnerGeometry"))()(localDeps)
return{Config=config,Geometry=geometry,Layout=layout,PlaqueDepth=2.25}
end
return P
]=],"@Proposed"))()
local OriginalCheck=Adapter.CheckSources
function Adapter.CheckSources()local result=OriginalCheck();local node=assert(game.ReplicatedStorage.Shared.Utility:FindFirstChild("CompactMapGeometry"),"Installed geometry owner missing");assert(node.Source==[[--!strict
-- Read-only CompactMap_V1 runtime geometry. Values are final locals, never scaled again.
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Geometry = {}
local MIGRATION = "CompactMap_V1"
local MAX_BYTES, MAX_WALLS, CELL_SIZE, MAX_CELLS = 200000, 512, 64, 8192
local SERVICE_SIZES = {AnnouncementStall={56,1,32},BrainrotTrainStall={56,1,32},BuyCartStall={64,1,40},KitStall={56,1,32},SellStall={56,1,32},WeaponHarpoonStall={56,1,32}}
local cache: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local function finite(v: any): boolean
 return type(v)=="number" and v==v and math.abs(v)<math.huge
end
local function number(v: any, label: string): number
 assert(finite(v), "Compact geometry finite number required: "..label)
 return v
end
local function positive(v: any, label: string): number
 local n=number(v,label);assert(n>0,"Compact geometry positive size required: "..label);return n
end
local function array(v: any, maximum: number, label: string): any
 assert(type(v)=="table","Compact geometry array required: "..label)
 local count=0
 for k in v do assert(type(k)=="number" and k%1==0 and k>=1 and k<=maximum,"Compact geometry dense bounded array required: "..label);count+=1 end
 assert(count==#v,"Compact geometry sparse array: "..label)
 for i=1,count do assert(v[i]~=nil,"Compact geometry missing array member: "..label) end
 return v
end
local function freeze(v: any): any
 if type(v)=="table" and not table.isfrozen(v) then for _,child in v do freeze(child) end;table.freeze(v) end
 return v
end
local function copy(v: any): any
 if type(v)~="table" then return v end
 local out={};for k,child in v do out[k]=copy(child) end;return out
end
local function rectangle(v: any, label: string): any
 assert(type(v)=="table","Compact geometry rectangle required: "..label)
 return {centreX=number(v.centreX,label..".centreX"),centreZ=number(v.centreZ,label..".centreZ"),width=positive(v.width,label..".width"),depth=positive(v.depth,label..".depth"),frontSign=v.frontSign}
end
function Geometry.Validate(raw: any): any
 assert(type(raw)=="table" and raw.schemaVersion==1 and raw.migrationId==MIGRATION,"Compact geometry schema mismatch")
 assert(raw.runtimeValidated==true,"Compact geometry must be validated before runtime")
 assert(type(raw.planHash)=="string" and #raw.planHash==64 and raw.planHash:match("^[0-9a-f]+$"),"Compact geometry plan hash required")
 assert(type(raw.bases)=="table","Compact geometry bases required")
 local bases,count={},0
 for id,g in raw.bases do
  count+=1;assert(type(id)=="string" and id:match("^Base_%d%d$"),"Compact geometry base ID invalid")
  assert(type(g)=="table","Compact geometry base row required")
  local z=array(g.zCenters,6,id..".zCenters");assert(#z==6,"Compact geometry needs six row centres")
  for i=1,6 do number(z[i],id..".zCenters");if i>1 then assert(z[i]>z[i-1],"Compact geometry row order invalid") end end
  local stride=z[2]-z[1]
  for i=3,6 do assert(math.abs((z[i]-z[i-1])-stride)<=1e-6,"Compact geometry row spacing must be uniform") end
  local slots=array(g.slots,12,id..".slots");assert(#slots==12,"Compact geometry needs twelve stable slots")
  local row={rowOffsetX=positive(g.rowOffsetX,id..".rowOffsetX"),formationCenterX=number(g.formationCenterX,id..".formationCenterX"),formationCenterZ=number(g.formationCenterZ,id..".formationCenterZ"),padNormalStuds=positive(g.padNormalStuds,id..".padNormalStuds"),padTangentialStuds=positive(g.padTangentialStuds,id..".padTangentialStuds"),support=rectangle(g.support,id..".support"),perimeter=rectangle(g.perimeter,id..".perimeter"),zCenters=copy(z),slots={}}
  assert(math.abs((z[1]+z[6])/2-row.formationCenterZ)<=1e-6,"Compact geometry formation centroid mismatch")
  row.perimeter.postWidth=positive(g.perimeter.postWidth,id..".perimeter.postWidth")
  row.perimeter.postDepth=positive(g.perimeter.postDepth,id..".perimeter.postDepth")
  assert(row.perimeter.width>2*row.perimeter.postWidth and row.perimeter.depth>2*row.perimeter.postDepth,"Compact perimeter is too small for posts")
  assert(row.perimeter.frontSign==nil or row.perimeter.frontSign==1 or row.perimeter.frontSign==-1,"Compact geometry front sign invalid")
  for i,slot in slots do
   local side=if i<=6 then -1 else 1;local station=if i<=6 then i else i-6
   assert(type(slot)=="table" and slot.Index==i and slot.Side==side,"Compact geometry stable slot identity/order changed")
   local x,sz=number(slot.X,id..".slotX"),number(slot.Z,id..".slotZ")
   assert(math.abs(x-(row.formationCenterX+side*row.rowOffsetX))<=1e-6 and math.abs(sz-z[station])<=1e-6,"Compact geometry uniform final slot local mismatch")
   assert(slot.PadNormalStuds==nil or math.abs(slot.PadNormalStuds-row.padNormalStuds)<=1e-6,"Compact geometry slot normal size mismatch")
   assert(slot.PadTangentialStuds==nil or math.abs(slot.PadTangentialStuds-row.padTangentialStuds)<=1e-6,"Compact geometry slot tangential size mismatch")
   assert(math.abs(x-row.support.centreX)+row.padNormalStuds/2<=row.support.width/2+.01 and math.abs(sz-row.support.centreZ)+row.padTangentialStuds/2<=row.support.depth/2+.01,"Compact geometry pad outside its support floor")
   row.slots[i]={Index=i,Side=side,X=x,Z=sz,PadNormalStuds=row.padNormalStuds,PadTangentialStuds=row.padTangentialStuds}
  end
  bases[id]=row
 end
 assert(count==12,"Compact geometry requires twelve bases")
 for i=1,12 do assert(bases[string.format("Base_%02d",i)],"Compact geometry base missing") end
 local services=Geometry.ValidateServices(raw.services)
 local walls=Geometry.ValidateWalls(raw.staticWallObstacles or {})
 return freeze({schemaVersion=1,migrationId=MIGRATION,planHash=raw.planHash,bases=bases,services=services,staticWallObstacles=walls})
end
function Geometry.ValidateServices(raw: any): any
 assert(type(raw)=="table","Compact geometry services required")
 local out,count={},0
 for id,row in raw do
  count+=1;local expected=SERVICE_SIZES[id]
  assert(expected and type(row)=="table","Compact geometry service identity invalid")
  local size=array(row.logicalInteractionEnvelope,3,"service.logicalInteractionEnvelope")
  assert(#size==3,"Compact geometry service interaction envelope needs three dimensions")
  for i=1,3 do assert(positive(size[i],"service.logicalInteractionEnvelope")==expected[i],"Compact service logical interaction envelope changed") end
  out[id]={logicalInteractionEnvelope=copy(size)}
 end
 assert(count==6,"Compact geometry needs six stable services")
 for id in SERVICE_SIZES do assert(out[id],"Compact geometry service missing") end
 return freeze(out)
end
function Geometry.ValidateWalls(raw: any): any
 local rows=array(raw,MAX_WALLS,"staticWallObstacles");local seen,out={},{}
 for _,row in rows do
  assert(type(row)=="table" and type(row.id)=="string" and #row.id>0 and #row.id<=128 and not seen[row.id],"Compact static wall ID invalid/duplicate")
  local r={id=row.id,minX=number(row.minX,"wall.minX"),maxX=number(row.maxX,"wall.maxX"),minY=number(row.minY,"wall.minY"),maxY=number(row.maxY,"wall.maxY"),minZ=number(row.minZ,"wall.minZ"),maxZ=number(row.maxZ,"wall.maxZ")}
  assert(r.minX<r.maxX and r.minY<r.maxY and r.minZ<r.maxZ,"Compact static wall bounds invalid")
  seen[r.id]=true;table.insert(out,r)
 end
 table.sort(out,function(a,b)return a.id<b.id end)
 return freeze(out)
end
function Geometry.Read(map: Instance?): any?
 if map==nil then return nil end
 local migration,status,hash=map:GetAttribute("CompactMapMigrationId"),map:GetAttribute("CompactMapStatus"),map:GetAttribute("CompactMapDesiredHash")
 local value=map:FindFirstChild("CompactMapRuntimeGeometry")
 if migration==nil and status==nil and hash==nil and value==nil then return nil end
 assert(migration==MIGRATION and status=="Completed","Compact geometry is incomplete or has an unknown migration")
 assert(value and value:IsA("StringValue") and #value.Value<=MAX_BYTES,"Compact runtime geometry missing/oversize")
 local saved=cache[map]
 if saved then
  assert(saved.value==value and saved.hash==hash and saved.text==value.Value,"Compact runtime geometry changed during session; restart required")
  return saved.data
 end
 local raw=HttpService:JSONDecode(value.Value);local data=Geometry.Validate(raw)
 assert(data.planHash==hash,"Compact runtime geometry desired hash mismatch")
 cache[map]={value=value,hash=hash,text=value.Value,data=data}
 return data
end
function Geometry.ResolveBase(base: Model): any?
 local ancestor: Instance?=base.Parent
 while ancestor and ancestor.Name~="MapBlockout" do ancestor=ancestor.Parent end
 if ancestor==nil then
  assert(base:GetAttribute("CompactMapMigrationId")==nil,"Compact base has no canonical map owner")
  return nil
 end
 local data=Geometry.Read(ancestor);if data==nil then return nil end
 local id=base:GetAttribute("BaseId");assert(type(id)=="string" and data.bases[id],"Compact base ID has no canonical geometry")
 return data.bases[id]
end
function Geometry.ResolveInteractionSize(part: BasePart): Vector3
 assert(part and part:IsA("BasePart"),"Service interaction requires a BasePart")
 local ancestor: Instance?=part.Parent
 while ancestor and ancestor.Name~="MapBlockout" do ancestor=ancestor.Parent end
 if ancestor==nil then
  assert(part:GetAttribute("CompactMapMigrationId")==nil,"Compact service has no canonical map owner")
  return part.Size
 end
 local data=Geometry.Read(ancestor);if data==nil then return part.Size end
 local patches=ancestor:FindFirstChild("ServiceStallPatches")
 assert(patches and part.Parent==patches and part:GetAttribute("LayoutRole")=="ServiceStall","Compact service identity/owner changed")
 local row=data.services[part.Name];assert(row,"Compact service has no canonical logical envelope")
 local size=part:GetAttribute("LogicalInteractionEnvelope")
 assert(typeof(size)=="Vector3" and finite(size.X) and finite(size.Y) and finite(size.Z),"Compact service logical interaction envelope missing/invalid")
 local expected=row.logicalInteractionEnvelope
 assert(math.abs(size.X-expected[1])<=1e-6 and math.abs(size.Y-expected[2])<=1e-6 and math.abs(size.Z-expected[3])<=1e-6,"Compact service logical interaction envelope drifted")
 return size
end
function Geometry.Current(): any? return Geometry.Read(Workspace:FindFirstChild("MapBlockout")) end
local function key(x: number,z: number): string return tostring(x)..":"..tostring(z) end
function Geometry.BuildWallIndex(raw: any): any
 local rows=Geometry.ValidateWalls(raw);local cells,count={},0
 for _,row in rows do
  local nx=math.floor(row.maxX/CELL_SIZE)-math.floor(row.minX/CELL_SIZE)+1
  local nz=math.floor(row.maxZ/CELL_SIZE)-math.floor(row.minZ/CELL_SIZE)+1
  assert(nx*nz<=MAX_CELLS,"Compact wall mask single row cell budget exceeded")
  for x=math.floor(row.minX/CELL_SIZE),math.floor(row.maxX/CELL_SIZE) do
   for z=math.floor(row.minZ/CELL_SIZE),math.floor(row.maxZ/CELL_SIZE) do
    local k=key(x,z);if cells[k]==nil then cells[k]={};count+=1;assert(count<=MAX_CELLS,"Compact wall mask cell budget exceeded") end
    table.insert(cells[k],row)
   end
  end
 end
 return freeze({rows=rows,cells=cells,cellSize=CELL_SIZE})
end
function Geometry.WallHit(index: any,frame: CFrame,size: Vector3,padding: number?): string?
 assert(type(index)=="table" and index.cellSize==CELL_SIZE,"Compact wall index required")
 assert(typeof(frame)=="CFrame" and typeof(size)=="Vector3","Compact wall envelope types invalid")
 for _,v in {frame:GetComponents()} do assert(finite(v),"Compact wall envelope frame invalid") end
 assert(finite(size.X) and finite(size.Y) and finite(size.Z) and size.X>0 and size.Y>0 and size.Z>0,"Compact wall envelope size invalid")
 local p=padding or 0;assert(finite(p) and p>=0,"Compact wall mask padding invalid")
 local half=size*.5
 local ex=math.abs(frame.RightVector.X)*half.X+math.abs(frame.UpVector.X)*half.Y+math.abs(frame.LookVector.X)*half.Z
 local ey=math.abs(frame.RightVector.Y)*half.X+math.abs(frame.UpVector.Y)*half.Y+math.abs(frame.LookVector.Y)*half.Z
 local ez=math.abs(frame.RightVector.Z)*half.X+math.abs(frame.UpVector.Z)*half.Y+math.abs(frame.LookVector.Z)*half.Z
 local x0,x1,z0,z1=frame.X-ex-p,frame.X+ex+p,frame.Z-ez-p,frame.Z+ez+p
 local y0,y1=frame.Y-ey,frame.Y+ey;local seen={}
 local nx=math.floor(x1/CELL_SIZE)-math.floor(x0/CELL_SIZE)+1
 local nz=math.floor(z1/CELL_SIZE)-math.floor(z0/CELL_SIZE)+1
 assert(finite(nx*nz) and nx*nz<=MAX_CELLS,"Compact wall query cell budget exceeded")
 for x=math.floor(x0/CELL_SIZE),math.floor(x1/CELL_SIZE) do
  for z=math.floor(z0/CELL_SIZE),math.floor(z1/CELL_SIZE) do
   for _,wall in index.cells[key(x,z)] or {} do
    if seen[wall.id] then continue end;seen[wall.id]=true
    if x0<wall.maxX and x1>wall.minX and z0<wall.maxZ and z1>wall.minZ and y0<wall.maxY and y1>wall.minY then return wall.id end
   end
  end
 end
 return nil
end
return table.freeze(Geometry)
]],"Installed geometry owner source changed");return result end
return Performance.Capture({Mode="After",Adapter=Adapter,Guard=Guard,Proposed=Proposed,RuntimeGeometryText=[[{
  "schemaVersion": 1,
  "migrationId": "CompactMap_V1",
  "runtimeValidated": true,
  "planHash": "46c697d0492ac5fbcc7cfd818ecedd16142c6ebfcaf582c21e85b5b2f0d8d292",
  "bases": {
    "Base_01": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_02": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_03": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_04": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_05": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_06": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_07": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_08": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_09": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_10": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_11": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    },
    "Base_12": {
      "rowOffsetX": 12.77,
      "formationCenterX": -13.33,
      "formationCenterZ": -15.935553619515293,
      "padNormalStuds": 13.92,
      "padTangentialStuds": 10.16,
      "zCenters": [
        -46.38555361951529,
        -34.20555361951529,
        -22.025553619515293,
        -9.845553619515293,
        2.3344463804847067,
        14.514446380484706
      ],
      "support": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625
      },
      "perimeter": {
        "centreX": -13.33,
        "centreZ": -17.854303619515292,
        "width": 46.660000000000004,
        "depth": 79.4625,
        "frontSign": -1,
        "postWidth": 0.53125,
        "postDepth": 0.53125
      },
      "slots": [
        {
          "Index": 1,
          "Side": -1,
          "X": -26.1,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 2,
          "Side": -1,
          "X": -26.1,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 3,
          "Side": -1,
          "X": -26.1,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 4,
          "Side": -1,
          "X": -26.1,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 5,
          "Side": -1,
          "X": -26.1,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 6,
          "Side": -1,
          "X": -26.1,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 7,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -46.38555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 8,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -34.20555361951529,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 9,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -22.025553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 10,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": -9.845553619515293,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 11,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 2.3344463804847067,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        },
        {
          "Index": 12,
          "Side": 1,
          "X": -0.5600000000000005,
          "Z": 14.514446380484706,
          "PadNormalStuds": 13.92,
          "PadTangentialStuds": 10.16
        }
      ]
    }
  },
  "staticWallObstacles": [],
  "nativeInteriorValidationEvidence": {
    "scope": "Actual native isolated owner/interior fit; no gameplay/full-site/native-import pass inferred",
    "file": "/Users/noahodukoya/development/Roblox/BrainrotExpedition/docs/map-compaction/CompactBaseLayoutNativeFit_085.json",
    "sha256": "55cb6543baa13c1557319a0882fd7e34d4b092ba0da4d7e291e86be5413f382e",
    "nativeDisplayPlacements": 768,
    "logicalSpeciesSlotCases": 4608,
    "eligibleSpecies": 32,
    "bases": 12,
    "elapsedSeconds": 7.382369930011919,
    "minimumDisplayGap": 4.844932250976562,
    "minimumPadGap": 2.0199999999999996,
    "minimumFullSupportMargin": 1.0008105850219726,
    "minimumClaimFaceAisle": 6.019989013671875,
    "temporaryStageRemoved": true,
    "originalObjectsPreserved": 2718,
    "checkedLiveSourcesPreserved": 10,
    "allFunctionalRampDimensionsPreserved": true,
    "nativeLoadedCartSupportPassed": true,
    "loadedCartDrivingTurningPassed": false,
    "fullSiteGeometryPassed": false,
    "nativeShellImportPassed": false,
    "gameplayPassed": false
  },
  "services": {
    "AnnouncementStall": {
      "logicalInteractionEnvelope": [
        56,
        1,
        32
      ]
    },
    "BrainrotTrainStall": {
      "logicalInteractionEnvelope": [
        56,
        1,
        32
      ]
    },
    "BuyCartStall": {
      "logicalInteractionEnvelope": [
        64,
        1,
        40
      ]
    },
    "KitStall": {
      "logicalInteractionEnvelope": [
        56,
        1,
        32
      ]
    },
    "SellStall": {
      "logicalInteractionEnvelope": [
        56,
        1,
        32
      ]
    },
    "WeaponHarpoonStall": {
      "logicalInteractionEnvelope": [
        56,
        1,
        32
      ]
    }
  }
}
]],SourceEvidence=Http:JSONDecode([[{"mode":"After","capturedOriginalAdapterSHA256":"de9955f7a6cc5dc1817220ad00dcf925e4e0087af2b0857179d66e8eb4de53cf","canonicalScaleAndFactory":"Exact immutable captured factory/scale/place sources; live byte guards before and after clones","ownerGeometry":"Exact reviewed proposal owner after live-source byte guard","proposals":[{"path":"/Users/noahodukoya/development/Roblox/BrainrotExpedition/docs/map-compaction/source-patches/proposals/ReplicatedStorage/Shared/Config/BaseLayoutConfig.lua","sha256":"9189c6db7f0d570f9f6de286c52f34ff8c31ba5102da930432b23c21fbcb1159"},{"path":"/Users/noahodukoya/development/Roblox/BrainrotExpedition/docs/map-compaction/source-patches/proposals/ServerScriptService/Server/Systems/BaseIncomePlaqueSystem.lua","sha256":"6b47ba8517d8e4a4db56d6eda6f5ebee5873738bf7d4f35ce8b393108607e266"},{"path":"/Users/noahodukoya/development/Roblox/BrainrotExpedition/docs/map-compaction/source-patches/proposals/ReplicatedStorage/Shared/Utility/CompactMapGeometry.lua","sha256":"b01607e4734d92dff22452b6f92cac104cb00e9d1436bb562331f1f9c7801c8f"}],"fixtureHelperSHA256":"fecee30a72ac1fb2ec1fb5d6aae20743ab4c042c3669a432322472611895f8c5","preparationOnly":true}]]),WarmSeconds=2,SampleIntervalSeconds=1/60})
