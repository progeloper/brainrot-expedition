--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config.BaseLayoutConfig)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local EnvironmentStuds = require(ReplicatedStorage.Shared.Utility.EnvironmentStudMaterialPolicy)
local SlotPresentation = require(ReplicatedStorage.Shared.Utility.BaseSlotPresentation)
local PlayerBaseSystem = require(script.Parent.PlayerBaseSystem)
local BaseStorageSystem = require(script.Parent.BaseStorageSystem)
local BrainrotIncomeSystem = require(script.Parent.BrainrotIncomeSystem)
-- Playtest Fixes 2 Part C (flag-gated): 6-stud sensor + a 5 Hz presence poll over each owner's pads.
local Fixes2Flags = require(ReplicatedStorage.Shared.Config.PlaytestFixes2Flags)
local PadConfig = require(ReplicatedStorage.Shared.Config.PlaytestFixes2).CashPads
local CashPadRules = require(ReplicatedStorage.Shared.Utility.CashPadRules)

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
local padPollAccumulator = 0
type PadPollParams = { character: Model, params: OverlapParams }
local padPollParams: { [Player]: PadPollParams } = setmetatable({}, { __mode = "k" }) :: any
-- Studio QA counters (read through ServerStorage.CashPadsQA, see Start).
local padStats =
	{ touchAttempts = 0, pollAttempts = 0, pollQueries = 0, pollSeconds = 0, polls = 0 }
local padEvents: { any }? = nil -- Studio QA only: {serverTime, "BaseId:PlatformId", source}

local function cashPadsOn(): boolean
	return Fixes2Flags.Part("CashPads")
end

local function touchHeight(): number
	return if cashPadsOn() then PadConfig.TouchHeightStuds else Config.PLAQUE_TOUCH_HEIGHT_STUDS
end

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
	if base:GetAttribute("AuthoredBaseLayout") == true then
		local origin = base:GetAttribute("BaseOrigin")
		if typeof(origin) == "CFrame" then
			return origin
		end
		local authoredPivot = base:GetAttribute("Phase5DLayoutPivot")
		if typeof(authoredPivot) == "CFrame" then
			return authoredPivot
		end
		return base:GetPivot()
	end
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
	part.Material = Enum.Material.SmoothPlastic
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
	pillar.CFrame = root * CFrame.new(localPosition.X, floorTopY + pillarHeight / 2, localPosition.Z)
	pillar.Color = style.Color
	pillar.Material = style.Material
	pillar.MaterialVariant = style.MaterialVariant
	pillar.CollisionGroup = style.CollisionGroup
	pillar.CanCollide = style.CanCollide
	pillar.CanTouch = style.CanTouch
	pillar.CanQuery = style.CanQuery
	EnvironmentStuds.Apply(pillar)
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
	createPillarsAlongEdge(container, root, floorTopY, pillarHeight, style, "Back", backLeft, backRight, nil)
	createPillarsAlongEdge(container, root, floorTopY, pillarHeight, style, "Left", frontLeft, backLeft, nil)
	createPillarsAlongEdge(container, root, floorTopY, pillarHeight, style, "Right", frontRight, backRight, nil)
end

local function ensureInterior(base: Model, root: CFrame, platformFloorY: number): number
	if base:GetAttribute("AuthoredBaseLayout") == true then
		local foundation = base:FindFirstChild("Foundation")
		assert(
			foundation and foundation:IsA("BasePart") and foundation.Parent == base,
			"Authored base requires a direct Foundation BasePart"
		)
		assert(
			foundation.Anchored and foundation.CanCollide and foundation.CanQuery,
			"Authored Foundation must remain anchored, colliding and queryable"
		)
		assert(
			root.UpVector:Dot(Vector3.yAxis) > 0.9999 and foundation.CFrame.UpVector:Dot(Vector3.yAxis) > 0.9999,
			"Authored base floor must remain level"
		)
		return platformTopLocalY(root, foundation)
	end
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
	local floorTopY = if createdFloor then platformFloorY else platformTopLocalY(root, resolvedFloor)
	configureStructuralPart(resolvedFloor)
	local pillarStyle = captureStructuralStyle(resolvedFloor)
	EnvironmentStuds.Apply(resolvedFloor, Enum.Material.SmoothPlastic)
	resolvedFloor.Size =
		Vector3.new(Config.BASE_FOOTPRINT_WIDTH_STUDS, floorThickness, Config.BASE_FOOTPRINT_DEPTH_STUDS)
	resolvedFloor.CFrame = root * CFrame.new(0, floorTopY - floorThickness / 2, 0)

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

local function positionPlatforms(root: CFrame, slots: { any }, authoredBase: Model?): (any, number)
	local ordered = table.clone(slots)
	table.sort(ordered, function(left, right)
		return left.Index < right.Index
	end)
	assert(#ordered == Config.PLATFORM_COUNT, "Phase 13 requires exactly 48 authored logical platforms")
	local placementById = {}
	local floorY = math.huge
	local groundTopY = platformTopLocalY(root, ordered[1].Platform)
	for order, slot in ordered do
		local platform = slot.Platform :: BasePart
		local platformId = platformIdFromPart(platform)
		assert(platformId == slot.Index, "Platform stable ID changed during layout")
		local topY = platformTopLocalY(root, platform)
		floorY = math.min(floorY, topY - platform.Size.Y)
		if authoredBase then
			assert(slot.Index == order, "Authored base requires distinct platform indices 1 through 48")
			assert(
				platform.Parent == authoredBase and platform.Anchored,
				"Authored platforms must remain direct anchored base children"
			)
			local marker = slot.Marker
			assert(
				typeof(marker) == "Instance"
					and marker.Parent == platform
					and marker.Name == "BrainrotPlacement"
					and (marker:IsA("Attachment") or marker:IsA("BasePart")),
				"Authored platform requires its direct BrainrotPlacement marker"
			)
			assert(platform.CFrame.UpVector:Dot(Vector3.yAxis) > 0.9999, "Authored platform must remain level")
			placementById[slot.Index] = {
				Authored = true,
				FloorIndex = math.floor((order - 1) / Config.PLATFORMS_PER_FLOOR),
				Platform = platform,
				PlatformTopY = topY,
			}
			continue
		end
		local floorIndex = math.floor((order - 1) / Config.PLATFORMS_PER_FLOOR)
		local localIndex = (order - 1) % Config.PLATFORMS_PER_FLOOR + 1
		local side = if localIndex <= Config.PLATFORMS_PER_SIDE then -1 else 1
		local row = if side < 0 then localIndex else localIndex - Config.PLATFORMS_PER_SIDE
		topY = groundTopY + floorIndex * Config.FLOOR_PITCH_STUDS
		local x = side * Config.PLATFORM_ROW_OFFSET_X
		local z = Config.PLATFORM_Z_CENTERS[row]
		local localPosition = Vector3.new(x, topY - platform.Size.Y / 2, z)
		local localFacing =
			CFrame.lookAt(localPosition, Vector3.new(0, localPosition.Y, localPosition.Z), Vector3.yAxis)
		local markerOffset = if slot.Marker:IsA("Attachment")
			then slot.Marker.CFrame
			else platform.CFrame:ToObjectSpace((slot.Marker :: BasePart).CFrame)
		platform.Size = Vector3.new(Config.PLATFORM_SIDE_STUDS, platform.Size.Y, Config.PLATFORM_SIDE_STUDS)
		platform.CFrame = root * localFacing
		platform.Anchored = true
		setMarkerFacing(slot, platform.CFrame, markerOffset)
		placementById[slot.Index] = {
			Side = side,
			FloorIndex = floorIndex,
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
	SlotPresentation.Capture(gui, { Enabled = true })

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
	local binding = plaqueBindings[plaque]
	local slot = binding and binding.State.Platforms and binding.State.Platforms[platformId]
	local locked = slot == nil
		or slot.Platform:GetAttribute("LockedSlot") == true
		or SlotPresentation.IsActive(slot.Platform) == false
	local saving = slot and slot.Platform:GetAttribute("PendingBank") == true or false
	plaque:SetAttribute("LockedSlot", locked)
	plaque:SetAttribute("PendingBank", saving)
	if binding and binding.Sensor then
		SlotPresentation.SetContentProperty(binding.Sensor, "CanTouch", not locked and not saving)
	end
	local gui, label = ensureAmountView(plaque)
	local cash = plaque:GetAttribute("UnclaimedCashSnapshot")
	local safeCash = if type(cash) == "number" and cash == cash and cash >= 0 then cash else 0
	local showAmount = plaque:GetAttribute("IncomeSnapshotReady") == true
		and plaque:GetAttribute("IncomeOccupied") == true
	label.Text = if locked
		then ""
		elseif saving then "Saving..."
		elseif showAmount then formatCashSnapshot(safeCash)
		else ""
	SlotPresentation.SetContentEnabled(gui, not locked and (saving or showAmount))
	if binding then
		SlotPresentation.BindSlot(plaque, binding.Base, platformId)
	end
end

local function candidatePlaques(base: Model): { BasePart }
	local result = {}
	for _, descendant in base:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and (CollectionService:HasTag(descendant, PLAQUE_TAG) or descendant.Name:match("^IncomePlaque_") ~= nil)
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

function BaseIncomePlaqueSystem:HandlePlaqueTouch(plaque: BasePart, touchedPart: any, source: string?): any
	local binding = plaqueBindings[plaque]
	if not started or not binding or states[binding.Base] ~= binding.State then
		return nil
	end
	if SlotPresentation.IsActive(plaque) == false then
		return { ok = false, code = "InvalidPlatform" }
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
	if source == "poll" then
		padStats.pollAttempts += 1
	else
		padStats.touchAttempts += 1
	end
	if padEvents then
		if #padEvents < 600 then
			table.insert(padEvents, { now, key, source or "touch" })
		end
	end
	local result = incomeSystem:TryClaimPlatform(player, binding.BaseId, binding.PlatformId)
	if result and result.ok then
		local snapshot = incomeSystem:GetPlatformIncomeSnapshot(binding.BaseId, binding.PlatformId)
		if snapshot then
			applyIncomeSnapshotToPlaque(plaque, binding.BaseId, binding.PlatformId, binding.OwnerUserId, snapshot)
		end
		plaque:SetAttribute("LastClaimUserId", player.UserId)
		plaque:SetAttribute("LastClaimAmount", result.paid or 0)
		plaque:SetAttribute("ClaimResetAmount", result.remainingExact or 0)
		local claimRevision = plaque:GetAttribute("ClaimRevision")
		plaque:SetAttribute("ClaimRevision", (if type(claimRevision) == "number" then claimRevision else 0) + 1)
	end
	return result
end

local function bindPlaqueTouch(state: any, plaque: BasePart, platformId: number, claimSensorCFrame: CFrame)
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
	end
	local touchSensor = sensor :: BasePart
	touchSensor.Size = Vector3.new(PLAQUE_WIDTH_STUDS, touchHeight(), PLAQUE_DEPTH_STUDS)
	touchSensor.CFrame = claimSensorCFrame
	touchSensor.Anchored = true
	touchSensor.CanCollide = false
	touchSensor.CanTouch = true
	touchSensor.CanQuery = false
	touchSensor.Massless = true
	touchSensor.Transparency = 1
	touchSensor.CastShadow = false
	SlotPresentation.Capture(touchSensor, { Transparency = 1, CanCollide = false, CanTouch = true, CanQuery = false })
	SlotPresentation.ApplyGroup(touchSensor, false)
	touchSensor.Parent = plaque
	binding.Sensor = touchSensor
	binding.TouchedConnection = touchSensor.Touched:Connect(function(otherPart)
		BaseIncomePlaqueSystem:HandlePlaqueTouch(plaque, otherPart)
	end)
	plaqueBindings[plaque] = binding
	state.Plaques[platformId] = plaque
end

-- Native full48 cash-pad census validated only these generated approaches.
-- Every logical platform, placement marker and stair remains in its original pose.
local AUTHORED_CASH_PAD_APPROACH: { [number]: string } = table.freeze({
	[5] = "Rear",
	[17] = "PedestalFront",
	[18] = "PedestalFront",
	[23] = "PedestalFront",
	[24] = "PedestalFront",
	[29] = "PedestalFront",
	[30] = "PedestalFront",
	[35] = "PedestalFront",
	[36] = "PedestalFront",
	[41] = "PedestalFront",
	[42] = "PedestalFront",
	[47] = "PedestalFront",
	[48] = "PedestalFront",
})
local function authoredPlaquePosition(base: Model, platformId: number, platform: BasePart, position: Vector3): Vector3
	local approach = AUTHORED_CASH_PAD_APPROACH[platformId]
	if approach == nil then
		return position
	end
	assert(
		platform.Parent == base and platform:GetAttribute("SlotIndex") == platformId,
		"Authored cash-pad platform identity changed"
	)
	if approach == "Rear" then
		local foundation = base:FindFirstChild("Foundation")
		assert(foundation and foundation:IsA("BasePart"), "Authored cash-pad Foundation missing")
		return position + foundation.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 5.5))
	end
	local look = platform.CFrame.LookVector
	local inward = Vector3.new(look.X, 0, look.Z).Unit
	local radial = platform.Size.Z / 2 - PLAQUE_DEPTH_STUDS / 2 - 0.25
	assert(radial >= 0 and platform.Size.X >= PLAQUE_WIDTH_STUDS + 0.5, "Authored pedestal cannot contain cash pad")
	local front = platform.Position + inward * radial
	local topY = platform.Position.Y + platform.Size.Y / 2
	return Vector3.new(front.X, topY + PLAQUE_FLOOR_CLEARANCE_STUDS + PLAQUE_THICKNESS_STUDS / 2, front.Z)
end

local function configurePlaque(state: any, plaque: BasePart, platformId: number, placement: any, floorTopY: number)
	floorTopY += (placement.FloorIndex or 0) * Config.FLOOR_PITCH_STUDS
	plaque.Name = getPlaqueName(platformId)
	plaque.Size = Vector3.new(PLAQUE_WIDTH_STUDS, PLAQUE_THICKNESS_STUDS, PLAQUE_DEPTH_STUDS)
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.CanTouch = false
	plaque.CanQuery = true
	plaque.Massless = true
	plaque.Material = Enum.Material.SmoothPlastic
	plaque.Color = Color3.fromRGB(60, 255, 90)
	plaque.Transparency = 0
	EnvironmentStuds.Apply(plaque, Enum.Material.SmoothPlastic)
	plaque.TopSurface = Enum.SurfaceType.Smooth
	plaque.BottomSurface = Enum.SurfaceType.Smooth
	if placement.Authored then
		local platform = placement.Platform :: BasePart
		assert(platform.Parent == state.Base, "Authored plaque platform no longer belongs to its base")
		local front = platform.CFrame.LookVector
		local levelInward = Vector3.new(front.X, 0, front.Z).Unit
		local frontPosition = platform.Position
			+ levelInward * (platform.Size.Z / 2 + PLAQUE_PLATFORM_GAP_STUDS + PLAQUE_DEPTH_STUDS / 2)
		local floorPosition = state.Root:PointToWorldSpace(
			Vector3.new(0, floorTopY + PLAQUE_FLOOR_CLEARANCE_STUDS + PLAQUE_THICKNESS_STUDS / 2, 0)
		)
		local plaquePosition = authoredPlaquePosition(
			state.Base,
			platformId,
			platform,
			Vector3.new(frontPosition.X, floorPosition.Y, frontPosition.Z)
		)
		plaque.CFrame = CFrame.lookAt(plaquePosition, plaquePosition + levelInward, Vector3.yAxis)
	else
		local inward = Config.PLATFORM_SIDE_STUDS / 2 + PLAQUE_PLATFORM_GAP_STUDS + PLAQUE_DEPTH_STUDS / 2
		local plaqueX = placement.Side * (Config.PLATFORM_ROW_OFFSET_X - inward)
		local plaqueY = floorTopY + PLAQUE_FLOOR_CLEARANCE_STUDS + PLAQUE_THICKNESS_STUDS / 2
		local plaquePosition = state.Root:PointToWorldSpace(Vector3.new(plaqueX, plaqueY, placement.ZCenter))
		local inwardDirection = state.Root:VectorToWorldSpace(Vector3.new(-placement.Side, 0, 0))
		local levelInward = Vector3.new(inwardDirection.X, 0, inwardDirection.Z).Unit
		plaque.CFrame = CFrame.lookAt(plaquePosition, plaquePosition + levelInward, Vector3.yAxis)
	end

	-- The contact envelope follows this pad, not a second offset layout.
	local claimSensorCFrame = plaque.CFrame
		* CFrame.new(0, PLAQUE_THICKNESS_STUDS / 2 + touchHeight() / 2, 0)
	if plaque:GetAttribute("ClaimRevision") == nil then
		plaque:SetAttribute("ClaimRevision", 0)
	end
	CollectionService:AddTag(plaque, PLAQUE_TAG)
	SlotPresentation.Capture(plaque, { Transparency = 0, CanCollide = false, CanTouch = false, CanQuery = true })
	bindPlaqueTouch(state, plaque, platformId, claimSensorCFrame)
	applyIncomeSnapshotToPlaque(plaque, state.BaseId, platformId, state.OwnerUserId, nil)
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
			SlotPresentation.ApplyGroup(plaque, false)
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
		applyIncomeSnapshotToPlaque(request.Plaque, request.BaseId, request.PlatformId, request.OwnerUserId, snapshot)
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
			applyIncomeSnapshotToPlaque(plaque, state.BaseId, platformId, state.OwnerUserId, snapshot)
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

-- Playtest Fixes 2 C1: one 5 Hz pass over each owner's own pads. Touched stays the instant trigger;
-- this catches walk-ons Touched misses and keeps claiming while the owner stands on a pad. Only pads
-- within reach of the owner are queried (one GetPartBoundsInBox each, whitelisting the owner).
local function overlapFor(player: Player, character: Model): OverlapParams
	local cached = padPollParams[player]
	if cached and cached.character == character then
		return cached.params
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { character }
	params.MaxParts = 1
	padPollParams[player] = { character = character, params = params }
	return params
end

local function pollPads()
	local startedAt = os.clock()
	local now = clock()
	for _, state in states do
		local owner = if state.OwnerUserId ~= 0 then getPlayerByUserId(state.OwnerUserId) else nil
		local character = owner and owner.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if owner and character and root and root:IsA("BasePart") then
			for _, plaque in state.Plaques do
				local binding = plaqueBindings[plaque]
				local sensor = binding and binding.Sensor
				if binding and sensor and sensor.Parent then
					local present = false
					local hit: BasePart? = nil
					local reach = math.max(sensor.Size.X, sensor.Size.Y, sensor.Size.Z) / 2 + 4
					if sensor.CanTouch and (root.Position - sensor.Position).Magnitude <= reach then
						padStats.pollQueries += 1
						local params = overlapFor(owner, character)
						local parts = Workspace:GetPartBoundsInBox(sensor.CFrame, sensor.Size, params)
						-- the handler rejects accessory/tool parts, so claim with the character's root
						present = parts[1] ~= nil
						hit = if present then root else nil
					end
					local unclaimed = CashPadRules.Unclaimed(
						plaque:GetAttribute("UnclaimedCashSnapshot"),
						plaque:GetAttribute("IncomeRatePerSecond"),
						plaque:GetAttribute("IncomeSnapshotServerTime"),
						now
					)
					if
						CashPadRules.ShouldClaim(
							present,
							binding.PollPresent == true,
							now,
							binding.PollLastClaimAt or -math.huge,
							unclaimed,
							PadConfig.RepeatSeconds,
							PadConfig.MinClaim
						)
					then
						binding.PollLastClaimAt = now
						BaseIncomePlaqueSystem:HandlePlaqueTouch(plaque, hit, "poll")
					end
					binding.PollPresent = present
				end
			end
		end
	end
	padStats.polls += 1
	padStats.pollSeconds += os.clock() - startedAt
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
	local placementById, platformFloorY =
		positionPlatforms(root, slots, if base:GetAttribute("AuthoredBaseLayout") == true then base else nil)
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
		Platforms = (function()
			local byId = {}
			for _, slot in slots do
				byId[slot.Index] = slot
			end
			return byId
		end)(),
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
				and (candidate:GetAttribute("PlatformId") == nil or candidate:GetAttribute("PlatformId") == platformId)
			then
				selected = candidate
				break
			end
		end
		if not selected then
			selected = Instance.new("Part")
		end
		used[selected] = true
		-- Configure and suppress the entire new group before publishing it to clients.
		configurePlaque(state, selected, platformId, placementById[platformId], floorTopY)
		selected.Parent = container
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

	local registeredBases = baseSystem:GetRegisteredBases()
	local yieldSetup = deps.YieldSetup or task.wait
	for index, base in registeredBases do
		-- Each base is built atomically; yield only between startup batches.
		-- Assignment/storage observers remain synchronous and never yield.
		if index > 1 then yieldSetup() end
		local ownerUserId = base:GetAttribute("OwnerUserId")
		local built, reason =
			self:BuildBase(base, if type(ownerUserId) == "number" and ownerUserId ~= 0 then ownerUserId else 0)
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
	-- A player may join while startup yields. Reconcile those earlier bases
	-- after subscriptions are established; do not miss the assignment/bind.
	for _, base in registeredBases do
		local state = states[base]
		if state then
			local owner = base:GetAttribute("OwnerUserId")
			state.OwnerUserId = if type(owner) == "number" then owner else 0
			for _, plaque in state.Plaques do
				local binding = plaqueBindings[plaque]
				if binding then binding.OwnerUserId = state.OwnerUserId end
			end
			local player = if state.OwnerUserId ~= 0 then getPlayerByUserId(state.OwnerUserId) else nil
			local storage = if player then storageSystem:GetStorageForPlayer(player) else nil
			if storage then refreshBaseSnapshots(base, storage, true) end
		end
	end
	if deps.ConnectSnapshotRefresh ~= false then
		local heartbeat = deps.Heartbeat or RunService.Heartbeat
		snapshotAccumulator = 0
		local pollOn = cashPadsOn()
		local pollInterval = 1 / PadConfig.PollHz
		padPollAccumulator = 0
		snapshotConnection = heartbeat:Connect(function(deltaTime)
			snapshotAccumulator += deltaTime
			if snapshotAccumulator >= PLAQUE_SNAPSHOT_REFRESH_SECONDS then
				snapshotAccumulator %= PLAQUE_SNAPSHOT_REFRESH_SECONDS
				refreshAccumulatedPlaques()
			end
			if pollOn then
				padPollAccumulator += deltaTime
				if padPollAccumulator >= pollInterval then
					padPollAccumulator %= pollInterval
					pollPads()
				end
			end
		end)
	end
	-- Studio QA: claim-trigger counters for the scripted walk-on test (attribute-gated, never live).
	if RunService:IsStudio() and game:GetService("ServerStorage"):GetAttribute("CashPadsQA") == true then
		local ServerStorage = game:GetService("ServerStorage")
		local qa = ServerStorage:FindFirstChild("CashPadsQA") or Instance.new("BindableFunction")
		qa.Name = "CashPadsQA";
		(qa :: BindableFunction).OnInvoke = function(command: string)
			if command == "Reset" then
				for key in padStats do
					padStats[key] = 0
				end
				padEvents = {}
			elseif command == "Events" then
				return padEvents or {}
			end
			return table.clone(padStats)
		end
		qa.Parent = ServerStorage
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
	baseSystem, storageSystem, incomeSystem = PlayerBaseSystem, BaseStorageSystem, BrainrotIncomeSystem
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
