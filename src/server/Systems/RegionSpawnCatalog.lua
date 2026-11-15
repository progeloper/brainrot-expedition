--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CreatureAssets = require(script.Parent.Parent.Utility.CreatureAssetService)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local BrainrotTerritory = require(ReplicatedStorage.Shared.Config.BrainrotTerritory)
local Phase10 = require(ReplicatedStorage.Shared.Config.Phase10)
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local CartLocalPlacement = require(script.Parent.Parent.Utility.CartLocalPlacement)

export type ValidationIssue = {
	severity: "Error" | "Warning",
	code: string,
	message: string,
	speciesId: string?,
	regionId: string?,
	areaId: string?,
}

export type ValidationReport = {
	errors: { ValidationIssue },
	warnings: { ValidationIssue },
}

export type SpawnArea = {
	Id: string,
	RegionId: string,
	Kind: "Point" | "Volume",
	Reference: string,
	Part: BasePart,
	Enabled: boolean,
	ProbeCount: number,
	UsableProbeCount: number,
	IsFloorSurface: boolean,
}

export type SelectionCandidate = {
	id: string,
	tier: string,
	assignmentStatus: string,
	homeRegionId: string?,
	allowedRegionIds: { string },
	spawnEnabled: boolean,
	launchStatus: string,
	naturalSpawnEligible: boolean,
	modelReady: boolean,
	behaviourReady: boolean,
	locationReady: boolean,
	globalWithinTierWeight: number?,
	readinessReasons: { string },
}

type Index = {
	regionsById: { [string]: any },
	regionOrder: { string },
	speciesById: { [string]: any },
	approvedSpeciesByRegion: { [string]: { string } },
	areasByRegion: { [string]: { SpawnArea } },
	areasById: { [string]: SpawnArea },
	boundariesByRegion: { [string]: { BasePart } },
	protectedInstances: { Instance },
	envelopesByModelRef: { [string]: { LocalFrame: CFrame, Size: Vector3 } },
	context: any,
	report: ValidationReport,
}

local RegionSpawnCatalog = {}
local log = Logger.new("RegionSpawnCatalog")
local currentIndex: Index? = nil
local started = false

local READY_BEHAVIOURS = table.freeze({
	Wanderer = true,
	ReactiveRunner = true,
	Sprinter = true,
	Zigzag = true,
	Camouflage = true,
	DecoySplit = true,
	LegendaryPursuit = true,
})
local FLOOR_VERTICAL_TOLERANCE_STUDS = 8

local function nonEmpty(value: any): boolean
	return type(value) == "string" and string.match(value, "%S") ~= nil
end

local function finiteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and math.abs(value.X) < math.huge
		and value.Y == value.Y
		and math.abs(value.Y) < math.huge
		and value.Z == value.Z
		and math.abs(value.Z) < math.huge
end

local function addIssue(
	report: ValidationReport,
	severity: "Error" | "Warning",
	code: string,
	message: string,
	speciesId: string?,
	regionId: string?,
	areaId: string?
)
	local item: ValidationIssue = {
		severity = severity,
		code = code,
		message = message,
		speciesId = speciesId,
		regionId = regionId,
		areaId = areaId,
	}
	table.insert(if severity == "Error" then report.errors else report.warnings, item)
end

local function cloneReport(report: ValidationReport): ValidationReport
	return {
		errors = table.clone(report.errors),
		warnings = table.clone(report.warnings),
	}
end

local function resolvePath(root: Instance, reference: string): Instance?
	local current: Instance? = root
	local first = true
	for segment in string.gmatch(reference, "[^%./]+") do
		if first and segment == root.Name then
			first = false
			continue
		end
		first = false
		current = if current then current:FindFirstChild(segment) else nil
		if current == nil then
			return nil
		end
	end
	return current
end

local function defaultContext(): any
	local map = Workspace:FindFirstChild("MapBlockout")
	local protectedInstances: { Instance } = {}
	for _, instance in
		{
			if map then map:FindFirstChild("PlayerBasePatches") else nil,
			if map then map:FindFirstChild("ServiceStallPatches") else nil,
			Workspace:FindFirstChild("CartSpawns"),
		}
	do
		if instance then
			table.insert(protectedInstances, instance)
		end
	end
	return {
		Root = Workspace,
		AssetFolder = CreatureAssets.GetBrainrotFolder(),
		ProtectedInstances = protectedInstances,
	}
end

local function resolveReference(context: any, reference: string): Instance?
	if type(context.ResolveReference) == "function" then
		return context.ResolveReference(reference)
	end
	return resolvePath(context.Root or Workspace, reference)
end

local function isAuthoredFloor(part: BasePart): boolean
	return part:GetAttribute("LayoutRole") == "Floor"
		and nonEmpty(part:GetAttribute("CellId"))
		and part:GetAttribute("GeneratedBy") == "CreateBasicMap_v1"
end

local function collectBoundaryParts(instance: Instance): { BasePart }
	local parts: { BasePart } = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and (descendant:GetAttribute("RegionBoundary") == true or isAuthoredFloor(descendant))
		then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function collectAreaParts(instance: Instance): { BasePart }
	local parts: { BasePart } = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and (descendant:GetAttribute("SpawnAreaId") ~= nil or isAuthoredFloor(descendant))
		then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function probePositions(part: BasePart, kind: "Point" | "Volume"): { Vector3 }
	if kind == "Point" then
		return { part.Position }
	end
	local points = {}
	for _, x in { -0.35, 0, 0.35 } do
		for _, z in { -0.35, 0, 0.35 } do
			table.insert(
				points,
				part.CFrame:PointToWorldSpace(
					Vector3.new(
						part.Size.X * x,
						if isAuthoredFloor(part) then part.Size.Y * 0.5 else -part.Size.Y * 0.5,
						part.Size.Z * z
					)
				)
			)
		end
	end
	return points
end

local function defaultProbeGround(point: Vector3, area: SpawnArea): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if area.IsFloorSurface then {} else { area.Part }
	params.RespectCanCollide = true
	params.IgnoreWater = false
	local result = Workspace:Raycast(point + Vector3.yAxis * 4, -Vector3.yAxis * 8, params)
	return result ~= nil
		and result.Material ~= Enum.Material.Water
		and result.Normal.Y >= BrainrotTerritory.MinWalkableNormalY
		and math.abs(result.Position.Y - point.Y) <= 2
end

local function countUsableProbes(area: SpawnArea, context: any): (number, number)
	local positions = probePositions(area.Part, area.Kind)
	local usable = 0
	for _, point in positions do
		local accepted = if type(context.ProbeGround) == "function"
			then context.ProbeGround(point, area)
			else defaultProbeGround(point, area)
		if accepted then
			usable += 1
		end
	end
	return #positions, usable
end

local function containsPoint(part: BasePart, point: Vector3, margin: Vector3?): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	local inset = margin or Vector3.zero
	return math.abs(localPoint.X) <= math.max(0, half.X - inset.X)
		and math.abs(localPoint.Y) <= math.max(0, half.Y - inset.Y)
		and math.abs(localPoint.Z) <= math.max(0, half.Z - inset.Z)
end

local function containsSurfacePoint(part: BasePart, point: Vector3, margin: Vector3?): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	local inset = margin or Vector3.zero
	return math.abs(localPoint.X) <= math.max(0, half.X - inset.X)
		and math.abs(localPoint.Z) <= math.max(0, half.Z - inset.Z)
end

local function boxCorners(frame: CFrame, size: Vector3): { Vector3 }
	local corners = {}
	local half = size * 0.5
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(corners, frame:PointToWorldSpace(half * Vector3.new(x, y, z)))
			end
		end
	end
	return corners
end

local function boxFitsPart(
	frame: CFrame,
	size: Vector3,
	container: BasePart,
	boundaryPadding: number?
): boolean
	local padding = math.max(0, boundaryPadding or 0)
	local inset = Vector3.new(padding, 0, padding)
	local minimumSurfaceY = math.huge
	for _, corner in boxCorners(frame, size) do
		local contains = if isAuthoredFloor(container)
			then containsSurfacePoint(container, corner, inset)
			else containsPoint(container, corner, inset)
		if not contains then
			return false
		end
		if isAuthoredFloor(container) then
			minimumSurfaceY =
				math.min(minimumSurfaceY, container.CFrame:PointToObjectSpace(corner).Y)
		end
	end
	if isAuthoredFloor(container) then
		local surfaceY = container.Size.Y * 0.5
		return minimumSurfaceY >= surfaceY - 2
			and minimumSurfaceY <= surfaceY + FLOOR_VERTICAL_TOLERANCE_STUDS
	end
	return true
end

-- A region can consist of adjacent native floor tiles. A padded body may
-- straddle an internal seam without fitting one tile. Cover its conservative
-- world X/Z rectangle with the union, retaining exterior padding and vertical
-- support tolerance. Exact interval coverage rejects gaps and concave cutouts;
-- no spatial queries or foreign-region tiles are introduced. Non-axis-aligned
-- authored floors retain the existing single-part predicate above.
local function boxFitsFloorUnion(
	frame: CFrame,
	size: Vector3,
	boundaries: { BasePart },
	padding: number
): boolean
	local minX, maxX, minZ, maxZ, bottom = math.huge, -math.huge, math.huge, -math.huge, math.huge
	for _, corner in boxCorners(frame, size) do
		minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
		minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
		bottom = math.min(bottom, corner.Y)
	end
	minX, maxX, minZ, maxZ = minX - padding, maxX + padding, minZ - padding, maxZ + padding
	local rectangles, cuts = {}, { minX, maxX }
	for _, floor in boundaries do
		local axes = floor.CFrame
		local aligned = math.abs(axes.UpVector.Y - 1) < 1e-6
			and math.max(math.abs(axes.RightVector.X), math.abs(axes.RightVector.Z)) > 1 - 1e-6
		local top = floor.Position.Y + floor.Size.Y * 0.5
		if
			isAuthoredFloor(floor)
			and aligned
			and bottom >= top - 2
			and bottom <= top + FLOOR_VERTICAL_TOLERANCE_STUDS
		then
			local halfX = (
				math.abs(axes.RightVector.X) * floor.Size.X
				+ math.abs(axes.LookVector.X) * floor.Size.Z
			) * 0.5
			local halfZ = (
				math.abs(axes.RightVector.Z) * floor.Size.X
				+ math.abs(axes.LookVector.Z) * floor.Size.Z
			) * 0.5
			local x1, x2 =
				math.max(minX, floor.Position.X - halfX), math.min(maxX, floor.Position.X + halfX)
			local z1, z2 =
				math.max(minZ, floor.Position.Z - halfZ), math.min(maxZ, floor.Position.Z + halfZ)
			if x1 < x2 and z1 < z2 then
				table.insert(rectangles, { X1 = x1, X2 = x2, Z1 = z1, Z2 = z2 })
				table.insert(cuts, x1)
				table.insert(cuts, x2)
			end
		end
	end
	if #rectangles < 2 then
		return false
	end
	table.sort(cuts)
	for i = 2, #cuts do
		local left, right = cuts[i - 1], cuts[i]
		if right <= left then
			continue
		end
		local intervals = {}
		for _, rectangle in rectangles do
			if rectangle.X1 <= left and rectangle.X2 >= right then
				table.insert(intervals, rectangle)
			end
		end
		table.sort(intervals, function(a, b)
			return a.Z1 < b.Z1
		end)
		local covered = minZ
		for _, interval in intervals do
			if interval.Z1 > covered then
				return false
			end
			covered = math.max(covered, interval.Z2)
		end
		if covered < maxZ then
			return false
		end
	end
	return true
end

local function boxesOverlapByCorners(leftFrame: CFrame, leftSize: Vector3, right: BasePart): boolean
	if isAuthoredFloor(right) then
		local minimumY, maximumY = math.huge, -math.huge
		for _, corner in boxCorners(leftFrame, leftSize) do
			local localPoint = right.CFrame:PointToObjectSpace(corner)
			minimumY, maximumY = math.min(minimumY, localPoint.Y), math.max(maximumY, localPoint.Y)
		end
		local surfaceY = right.Size.Y * 0.5
		if maximumY < surfaceY - 2 or minimumY > surfaceY + FLOOR_VERTICAL_TOLERANCE_STUDS then
			return false
		end
	end
	local rightContains = if isAuthoredFloor(right) then containsSurfacePoint else containsPoint
	if rightContains(right, leftFrame.Position) then
		return true
	end
	for _, corner in boxCorners(leftFrame, leftSize) do
		if rightContains(right, corner) then
			return true
		end
	end
	for _, corner in boxCorners(right.CFrame, right.Size) do
		local localPoint = leftFrame:PointToObjectSpace(corner)
		local half = leftSize * 0.5
		if
			math.abs(localPoint.X) <= half.X
			and (isAuthoredFloor(right) or math.abs(localPoint.Y) <= half.Y)
			and math.abs(localPoint.Z) <= half.Z
		then
			return true
		end
	end
	return false
end

local function getModel(index: Index, definition: any): Model?
	if type(index.context.ResolveModel) == "function" then
		local model = index.context.ResolveModel(definition)
		return if model and model:IsA("Model") then model else nil
	end
	local folder = index.context.AssetFolder
	local model = if folder and folder:IsA("Instance")
		then folder:FindFirstChild(definition.modelRef)
		else nil
	return if model and model:IsA("Model") then model else nil
end

local function getEnvelope(index: Index, definition: any): (CFrame?, Vector3?, string?)
	local cached = index.envelopesByModelRef[definition.modelRef]
	if cached then
		return cached.LocalFrame, cached.Size, nil
	end
	local model = getModel(index, definition)
	if model == nil then
		return nil, nil, "MODEL_MISSING"
	end
	local body = model:FindFirstChild("Body", true)
	if body == nil or not body:IsA("BasePart") or not body.CanQuery then
		return nil, nil, "MODEL_MISSING"
	end
	-- Use the same effect-free visible bounds that the existing world factory uses
	-- to ground a model. Body remains the required capture identity, while authored
	-- limbs and props still have to fit the placement clearance.
	local localFrame, size, reason = BrainrotVisualScale.GetVisualBounds(model)
	if localFrame and size then
		-- The world factory canonicalizes every source to the shared gameplay height
		-- before activation. Apply that same pivot-relative scale mathematically here
		-- so placement checks use the real world envelope without cloning or mutating
		-- the authored source asset on every candidate attempt.
		-- Playtest Fixes size ladder: wild brainrots spawn at their rarity height (flag-gated).
		local correction = BrainrotVisualScale.HeightForSpecies(definition.id, "Wild") / size.Y
		if correction ~= correction or correction <= 0 or correction == math.huge then
			return nil, nil, "INVALID_VISIBLE_BOUNDS"
		end
		localFrame = CFrame.new(localFrame.Position * correction) * localFrame.Rotation
		size *= correction
		index.envelopesByModelRef[definition.modelRef] = table.freeze({
			LocalFrame = localFrame,
			Size = size,
		})
	end
	return localFrame, size, reason
end

local function behaviourReady(index: Index, definition: any): boolean
	if type(index.context.IsBehaviourReady) == "function" then
		return index.context.IsBehaviourReady(definition.behaviourId, definition)
	end
	return READY_BEHAVIOURS[definition.behaviourId] == true
end

local function current(): Index
	if currentIndex == nil then
		RegionSpawnCatalog.BuildIndex(Regions.GetAll(), BrainrotCatalog.GetAll(), nil)
	end
	return currentIndex :: Index
end

function RegionSpawnCatalog.BuildIndex(
	regionDefinitions: { any }?,
	speciesDefinitions: { any }?,
	mapContext: any?
): ValidationReport
	local report: ValidationReport = { errors = {}, warnings = {} }
	local context = mapContext or defaultContext()
	local index: Index = {
		regionsById = {},
		regionOrder = {},
		speciesById = {},
		approvedSpeciesByRegion = {},
		areasByRegion = {},
		areasById = {},
		boundariesByRegion = {},
		protectedInstances = table.clone(context.ProtectedInstances or {}),
		envelopesByModelRef = {},
		context = context,
		report = report,
	}

	for _, definition in regionDefinitions or Regions.GetAll() do
		local regionId = Regions.NormalizeId(definition.id)
		if regionId == nil or regionId ~= definition.id then
			addIssue(
				report,
				"Error",
				"UNKNOWN_REGION",
				"region definition has a non-canonical ID",
				nil,
				definition.id,
				nil
			)
			continue
		end
		if index.regionsById[regionId] then
			addIssue(
				report,
				"Error",
				"DUPLICATE_REGION_ID",
				"region ID is declared more than once",
				nil,
				regionId,
				nil
			)
			continue
		end
		index.regionsById[regionId] = definition
		table.insert(index.regionOrder, regionId)
		index.approvedSpeciesByRegion[regionId] = {}
		index.areasByRegion[regionId] = {}
		index.boundariesByRegion[regionId] = {}

		if definition.kind == "Hub" and definition.naturalSpawnAllowed == true then
			addIssue(
				report,
				"Error",
				"CAMP_NOT_SPAWNABLE",
				"hub regions cannot permit natural spawning",
				nil,
				regionId,
				nil
			)
		end
		if regionId == Regions.CampId and #(definition.spawnAreaRefs or {}) > 0 then
			addIssue(
				report,
				"Error",
				"CAMP_NOT_SPAWNABLE",
				"Camp must not reference natural spawn areas",
				nil,
				regionId,
				nil
			)
		end

		for _, reference in definition.boundaryRefs or {} do
			local instance = resolveReference(context, reference)
			if instance == nil then
				addIssue(
					report,
					"Error",
					"MISSING_REGION_BOUNDARY",
					"boundary reference does not resolve: " .. reference,
					nil,
					regionId,
					nil
				)
			else
				for _, part in collectBoundaryParts(instance) do
					table.insert(index.boundariesByRegion[regionId], part)
				end
			end
		end

		for _, reference in definition.spawnAreaRefs or {} do
			local instance = resolveReference(context, reference)
			if instance == nil then
				addIssue(
					report,
					"Error",
					"MISSING_SPAWN_AREA",
					"spawn-area reference does not resolve: " .. reference,
					nil,
					regionId,
					nil
				)
				continue
			end
			local parts = collectAreaParts(instance)
			if #parts == 0 then
				addIssue(
					report,
					"Error",
					"MISSING_SPAWN_AREA",
					"spawn-area reference contains no BaseParts: " .. reference,
					nil,
					regionId,
					nil
				)
			end
			for _, part in parts do
				local floorSurface = isAuthoredFloor(part)
				local areaId = part:GetAttribute("SpawnAreaId")
				if floorSurface and not nonEmpty(areaId) then
					areaId = regionId .. ":" .. tostring(part:GetAttribute("CellId"))
				end
				local areaRegionId = Regions.NormalizeId(part:GetAttribute("RegionId"))
				if floorSurface and areaRegionId == nil then
					areaRegionId = regionId
				end
				local kind = part:GetAttribute("SpawnAreaKind")
				if floorSurface and kind == nil then
					kind = "Volume"
				end
				if not nonEmpty(areaId) or (kind ~= "Point" and kind ~= "Volume") then
					addIssue(
						report,
						"Error",
						"INVALID_SPAWN_AREA",
						"spawn area needs SpawnAreaId and Point/Volume kind",
						nil,
						regionId,
						if type(areaId) == "string" then areaId else nil
					)
					continue
				end
				if areaRegionId ~= regionId then
					addIssue(
						report,
						"Error",
						"SPAWN_AREA_REGION_MISMATCH",
						"spawn area RegionId does not match its configured region",
						nil,
						regionId,
						areaId
					)
					continue
				end
				if index.areasById[areaId] then
					addIssue(
						report,
						"Error",
						"DUPLICATE_SPAWN_AREA_ID",
						"SpawnAreaId is declared more than once",
						nil,
						regionId,
						areaId
					)
					continue
				end
				if not part.Anchored then
					addIssue(
						report,
						"Error",
						"INVALID_SPAWN_AREA",
						"spawn area must be anchored",
						nil,
						regionId,
						areaId
					)
					continue
				end
				if
					kind == "Point"
					and (part.CanCollide or part.CanTouch or part.CanQuery or part.CastShadow)
				then
					addIssue(
						report,
						"Error",
						"INVALID_SPAWN_AREA",
						"point helper must not collide, touch, query or cast shadows",
						nil,
						regionId,
						areaId
					)
					continue
				end
				local enabledAttribute = part:GetAttribute("Enabled")
				local area: SpawnArea = {
					Id = areaId,
					RegionId = regionId,
					Kind = kind,
					Reference = reference,
					Part = part,
					Enabled = if type(enabledAttribute) == "boolean"
						then enabledAttribute
						else true,
					ProbeCount = 0,
					UsableProbeCount = 0,
					IsFloorSurface = floorSurface,
				}
				area.ProbeCount, area.UsableProbeCount = countUsableProbes(area, context)
				table.freeze(area)
				index.areasById[area.Id] = area
				table.insert(index.areasByRegion[regionId], area)
				if area.Enabled and area.UsableProbeCount == 0 then
					addIssue(
						report,
						"Warning",
						"NO_VALID_GROUND",
						"spawn area has no usable deterministic ground probes",
						nil,
						regionId,
						area.Id
					)
				end
			end
		end

		if definition.enabled == true and definition.kind == "Hunting" then
			if #index.boundariesByRegion[regionId] == 0 then
				addIssue(
					report,
					"Error",
					"MISSING_REGION_BOUNDARY",
					"enabled hunting region has no resolved boundary",
					nil,
					regionId,
					nil
				)
			end
			if definition.naturalSpawnAllowed == true and #index.areasByRegion[regionId] == 0 then
				addIssue(
					report,
					"Error",
					"MISSING_SPAWN_AREA",
					"enabled hunting region has no registered spawn areas",
					nil,
					regionId,
					nil
				)
			end
		end
	end

	for _, definition in speciesDefinitions or BrainrotCatalog.GetAll() do
		local speciesId = BrainrotCatalog.NormalizeId(definition.id)
		if speciesId == nil or speciesId ~= definition.id then
			addIssue(
				report,
				"Error",
				"UNKNOWN_SPECIES",
				"species definition has a non-canonical ID",
				definition.id,
				nil,
				nil
			)
			continue
		end
		if index.speciesById[speciesId] then
			addIssue(
				report,
				"Error",
				"DUPLICATE_SPECIES_ID",
				"species ID is declared more than once",
				speciesId,
				nil,
				nil
			)
			continue
		end
		index.speciesById[speciesId] = definition
		local status = definition.regionAssignmentStatus
		if status == "Pending" then
			addIssue(
				report,
				"Warning",
				"REGION_ASSIGNMENT_PENDING",
				"current-map assignment requires approval",
				speciesId,
				nil,
				nil
			)
		elseif status == "Conflict" then
			addIssue(
				report,
				"Warning",
				"REGION_ASSIGNMENT_CONFLICT",
				"approved sources conflict",
				speciesId,
				nil,
				nil
			)
		elseif status == "Approved" then
			local homeRegionId = Regions.NormalizeId(definition.homeRegionId)
			local allowedSet: { [string]: boolean } = {}
			for _, rawRegionId in definition.allowedRegionIds or {} do
				local regionId = Regions.NormalizeId(rawRegionId)
				if regionId == nil or index.regionsById[regionId] == nil then
					addIssue(
						report,
						"Error",
						"UNKNOWN_REGION",
						"approved assignment references an unknown region",
						speciesId,
						rawRegionId,
						nil
					)
				elseif regionId == Regions.CampId then
					addIssue(
						report,
						"Error",
						"CAMP_NOT_SPAWNABLE",
						"Camp cannot be an allowed natural-spawn region",
						speciesId,
						regionId,
						nil
					)
				elseif allowedSet[regionId] then
					addIssue(
						report,
						"Error",
						"DUPLICATE_ALLOWED_REGION",
						"approved assignment repeats a region",
						speciesId,
						regionId,
						nil
					)
				else
					allowedSet[regionId] = true
					table.insert(index.approvedSpeciesByRegion[regionId], speciesId)
				end
			end
			if homeRegionId == nil or not allowedSet[homeRegionId] then
				addIssue(
					report,
					"Error",
					"HOME_NOT_ALLOWED",
					"approved home must appear in the allowed list",
					speciesId,
					homeRegionId,
					nil
				)
			end
		else
			addIssue(
				report,
				"Error",
				"INVALID_REGION_ASSIGNMENT_STATUS",
				"assignment status is invalid",
				speciesId,
				nil,
				nil
			)
		end
	end

	for _, speciesIds in index.approvedSpeciesByRegion do
		table.sort(speciesIds)
	end
	for _, areas in index.areasByRegion do
		table.sort(areas, function(left, right)
			return left.Id < right.Id
		end)
	end
	for _, boundary in index.boundariesByRegion[Regions.CampId] or {} do
		table.insert(index.protectedInstances, boundary)
	end
	currentIndex = index
	return cloneReport(report)
end

function RegionSpawnCatalog.GetSpeciesAssignment(speciesId: unknown): any?
	local index = current()
	local normalized = BrainrotCatalog.NormalizeId(speciesId)
	local definition = if normalized then index.speciesById[normalized] else nil
	if definition == nil then
		return nil
	end
	return table.freeze({
		homeRegionId = definition.homeRegionId,
		allowedRegionIds = table.freeze(table.clone(definition.allowedRegionIds or {})),
		status = definition.regionAssignmentStatus,
	})
end

function RegionSpawnCatalog.ResolveHomeRegion(speciesId: unknown): (string?, string?)
	local assignment = RegionSpawnCatalog.GetSpeciesAssignment(speciesId)
	if assignment == nil then
		return nil, "UNKNOWN_SPECIES"
	end
	if assignment.status ~= "Approved" then
		return nil,
			if assignment.status == "Conflict"
				then "REGION_ASSIGNMENT_CONFLICT"
				else "REGION_ASSIGNMENT_PENDING"
	end
	local homeRegionId = Regions.NormalizeId(assignment.homeRegionId)
	local region = if homeRegionId then Regions.Get(homeRegionId) else nil
	if region == nil or region.kind ~= "Hunting" or region.naturalSpawnAllowed ~= true then
		return nil, "INVALID_HOME_REGION"
	end
	for _, rawRegionId in assignment.allowedRegionIds do
		if Regions.NormalizeId(rawRegionId) == homeRegionId then
			return homeRegionId, nil
		end
	end
	return nil, "HOME_NOT_ALLOWED"
end

function RegionSpawnCatalog.IsSpeciesAllowedInRegion(speciesId: unknown, regionId: unknown): boolean
	local index = current()
	local normalizedSpecies = BrainrotCatalog.NormalizeId(speciesId)
	local normalizedRegion = Regions.NormalizeId(regionId)
	local definition = if normalizedSpecies then index.speciesById[normalizedSpecies] else nil
	local region = if normalizedRegion then index.regionsById[normalizedRegion] else nil
	if
		definition == nil
		or region == nil
		or normalizedRegion == Regions.CampId
		or region.kind ~= "Hunting"
		or not region.naturalSpawnAllowed
		or definition.regionAssignmentStatus ~= "Approved"
	then
		return false
	end
	for _, allowedRegionId in definition.allowedRegionIds or {} do
		if allowedRegionId == normalizedRegion then
			return true
		end
	end
	return false
end

function RegionSpawnCatalog.GetApprovedSpeciesIds(regionId: unknown): { string }
	local index = current()
	local normalized = Regions.NormalizeId(regionId)
	if normalized == nil or normalized == Regions.CampId then
		return {}
	end
	return table.clone(index.approvedSpeciesByRegion[normalized] or {})
end

function RegionSpawnCatalog.GetSpawnAreas(regionId: unknown): { SpawnArea }
	local index = current()
	local normalized = Regions.NormalizeId(regionId)
	if normalized == nil or normalized == Regions.CampId then
		return {}
	end
	return table.clone(index.areasByRegion[normalized] or {})
end

function RegionSpawnCatalog.ContainsPosition(
	regionId: unknown,
	position: unknown,
	verticalTolerance: number?
): boolean
	if not finiteVector3(position) then
		return false
	end
	local index = current()
	local normalized = Regions.NormalizeId(regionId)
	if normalized == nil then
		return false
	end
	local tolerance = verticalTolerance
	if type(tolerance) ~= "number" or tolerance ~= tolerance or tolerance < 0 then
		tolerance = FLOOR_VERTICAL_TOLERANCE_STUDS
	end
	for _, boundary in index.boundariesByRegion[normalized] or {} do
		if isAuthoredFloor(boundary) then
			local localPoint = boundary.CFrame:PointToObjectSpace(position :: Vector3)
			if
				containsSurfacePoint(boundary, position :: Vector3)
				and math.abs(localPoint.Y - boundary.Size.Y * 0.5) <= tolerance
			then
				return true
			end
		elseif containsPoint(boundary, position :: Vector3) then
			return true
		end
	end
	return false
end

function RegionSpawnCatalog.GetRegionAtPosition(position: unknown, verticalTolerance: number?): any?
	local index = current()
	for _, regionId in index.regionOrder do
		if RegionSpawnCatalog.ContainsPosition(regionId, position, verticalTolerance) then
			return index.regionsById[regionId]
		end
	end
	return nil
end

-- Supplies static, reference-free selector inputs from the authoritative Phase
-- 6F-1 relationship. It deliberately returns approved regional members only;
-- SpawnSelection still validates every field and never owns a second species list.
function RegionSpawnCatalog.GetSelectionCandidates(regionId: unknown): { SelectionCandidate }
	local index = current()
	local normalized = Regions.NormalizeId(regionId)
	if normalized == nil or normalized == Regions.CampId then
		return {}
	end
	local candidates: { SelectionCandidate } = {}
	for _, speciesId in index.approvedSpeciesByRegion[normalized] or {} do
		local definition = index.speciesById[speciesId]
		if definition == nil then
			continue
		end
		local readiness = RegionSpawnCatalog.EvaluateNaturalSpawnReadiness(speciesId, normalized)
		local reasonSet: { [string]: boolean } = {}
		for _, reason in readiness.reasons do
			reasonSet[reason] = true
		end
		local reasons = table.freeze(table.clone(readiness.reasons))
		local allowedRegionIds = table.freeze(table.clone(definition.allowedRegionIds or {}))
		local candidate: SelectionCandidate = {
			id = speciesId,
			tier = definition.tier,
			assignmentStatus = definition.regionAssignmentStatus,
			homeRegionId = definition.homeRegionId,
			allowedRegionIds = allowedRegionIds,
			spawnEnabled = definition.spawnEnabled == true,
			launchStatus = definition.launchStatus,
			naturalSpawnEligible = definition.launchStatus == "Live",
			modelReady = reasonSet.MODEL_MISSING ~= true,
			behaviourReady = reasonSet.BEHAVIOUR_NOT_READY ~= true,
			locationReady = reasonSet.MISSING_REGION_BOUNDARY ~= true
				and reasonSet.MISSING_SPAWN_AREA ~= true,
			-- No catalogue field currently has verified within-tier-weight semantics.
			globalWithinTierWeight = nil,
			readinessReasons = reasons,
		}
		table.freeze(candidate)
		table.insert(candidates, candidate)
	end
	return candidates
end

function RegionSpawnCatalog.EvaluateNaturalSpawnReadiness(
	speciesId: unknown,
	regionId: unknown
): any
	local index = current()
	local reasons: { string } = {}
	local activationReasons: { string } = {}
	local normalizedSpecies = BrainrotCatalog.NormalizeId(speciesId)
	local normalizedRegion = Regions.NormalizeId(regionId)
	local definition = if normalizedSpecies then index.speciesById[normalizedSpecies] else nil
	local region = if normalizedRegion then index.regionsById[normalizedRegion] else nil
	if definition == nil then
		table.insert(reasons, "UNKNOWN_SPECIES")
	elseif definition.regionAssignmentStatus == "Pending" then
		table.insert(reasons, "REGION_ASSIGNMENT_PENDING")
	elseif definition.regionAssignmentStatus == "Conflict" then
		table.insert(reasons, "REGION_ASSIGNMENT_CONFLICT")
	end
	if region == nil then
		table.insert(reasons, "UNKNOWN_REGION")
	elseif
		normalizedRegion == Regions.CampId
		or region.kind ~= "Hunting"
		or not region.naturalSpawnAllowed
	then
		table.insert(reasons, "CAMP_NOT_SPAWNABLE")
	else
		if #index.boundariesByRegion[normalizedRegion] == 0 then
			table.insert(reasons, "MISSING_REGION_BOUNDARY")
		end
		local usable = false
		for _, area in index.areasByRegion[normalizedRegion] do
			if area.Enabled and area.UsableProbeCount > 0 then
				usable = true
				break
			end
		end
		if not usable then
			table.insert(reasons, "MISSING_SPAWN_AREA")
		end
	end
	if
		definition
		and region
		and not RegionSpawnCatalog.IsSpeciesAllowedInRegion(definition.id, region.id)
	then
		if definition.regionAssignmentStatus == "Approved" then
			table.insert(reasons, "SPECIES_NOT_ALLOWED_IN_REGION")
		end
	end
	if definition then
		if getModel(index, definition) == nil then
			table.insert(reasons, "MODEL_MISSING")
		end
		if not behaviourReady(index, definition) then
			table.insert(reasons, "BEHAVIOUR_NOT_READY")
		end
		if definition.launchStatus ~= "Live" then
			table.insert(activationReasons, "CONTENT_TEASED")
		end
		if definition.spawnEnabled ~= true then
			table.insert(activationReasons, "SPAWN_DISABLED")
		end
	end
	local ready = #reasons == 0
	if not ready then
		table.insert(activationReasons, "NOT_TECHNICALLY_READY")
	end
	return table.freeze({
		ready = ready,
		activated = ready and #activationReasons == 0,
		reasons = table.freeze(reasons),
		activationReasons = table.freeze(activationReasons),
	})
end

local function validateGround(
	index: Index,
	candidate: Vector3,
	area: SpawnArea,
	definition: any
): (boolean, Vector3?, string?)
	if type(index.context.ValidateGround) == "function" then
		return index.context.ValidateGround(candidate, area, definition)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if area.IsFloorSurface then {} else { area.Part }
	params.RespectCanCollide = true
	params.IgnoreWater = false
	local result, queryReason
	if Phase10.Enabled then
		result, queryReason = CartLocalPlacement.ProbeBrainrotGround(
			candidate + Vector3.yAxis * 4,
			-Vector3.yAxis * 8,
			params
		)
	else
		result = Workspace:Raycast(candidate + Vector3.yAxis * 4, -Vector3.yAxis * 8, params)
	end
	if queryReason then
		return false, nil, queryReason
	end
	if
		result == nil
		or result.Material == Enum.Material.Water
		or result.Normal.Y < BrainrotTerritory.MinWalkableNormalY
		or (Phase10.Enabled and not CartLocalPlacement.IsBrainrotSupport(result))
	then
		return false, nil, "NO_VALID_GROUND"
	end
	if math.abs(result.Position.Y - candidate.Y) > 2 then
		return false, nil, "NO_VALID_GROUND"
	end
	return true, result.Position, nil
end

local function validateFootprint(
	candidate: Vector3,
	frame: CFrame,
	size: Vector3,
	area: SpawnArea
): (Vector3?, string?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if area.IsFloorSurface then {} else { area.Part }
	params.RespectCanCollide, params.IgnoreWater = true, false
	local half = size / 2
	local extentX = math.abs(frame.RightVector.X) * half.X
		+ math.abs(frame.UpVector.X) * half.Y
		+ math.abs(frame.LookVector.X) * half.Z
	local extentZ = math.abs(frame.RightVector.Z) * half.X
		+ math.abs(frame.UpVector.Z) * half.Y
		+ math.abs(frame.LookVector.Z) * half.Z
	local low, high = math.huge, -math.huge
	for _, offset in
		{
			Vector3.zero,
			Vector3.new(-extentX, 0, -extentZ),
			Vector3.new(extentX, 0, -extentZ),
			Vector3.new(-extentX, 0, extentZ),
			Vector3.new(extentX, 0, extentZ),
		}
	do
		local point = Vector3.new(frame.X, candidate.Y, frame.Z) + offset
		local hit, reason = CartLocalPlacement.ProbeBrainrotGround(
			point + Vector3.yAxis * 4,
			-Vector3.yAxis * 8,
			params
		)
		if reason then
			return nil, reason
		end
		if
			not hit
			or not CartLocalPlacement.IsBrainrotSupport(hit)
			or math.abs(hit.Position.Y - candidate.Y) > 2
		then
			return nil, "UNSUPPORTED_FOOTPRINT"
		end
		low, high = math.min(low, hit.Position.Y), math.max(high, hit.Position.Y)
	end
	if high - low > 0.25 then
		return nil, "UNEVEN_FOOTPRINT"
	end
	return Vector3.new(candidate.X, high, candidate.Z), nil
end

local function isProtected(
	index: Index,
	frame: CFrame,
	size: Vector3,
	ignoredRegionId: string?
): (boolean, string?, string?)
	if ignoredRegionId ~= Regions.CampId then
		for _, boundary in index.boundariesByRegion[Regions.CampId] or {} do
			if boxesOverlapByCorners(frame, size, boundary) then
				return true, "PROTECTED_AREA_OVERLAP", string.sub(boundary:GetFullName(), 1, 512)
			end
		end
	end
	if type(index.context.IsProtected) == "function" then
		local protected, reason = index.context.IsProtected(frame, size)
		return protected, reason, nil
	end
	if #index.protectedInstances == 0 then
		return false, nil, nil
	end
	local protectedInstances = index.protectedInstances
	if ignoredRegionId == Regions.CampId then
		local campBoundaries = {}
		for _, boundary in index.boundariesByRegion[Regions.CampId] or {} do
			campBoundaries[boundary] = true
		end
		protectedInstances = {}
		for _, instance in index.protectedInstances do
			if not campBoundaries[instance] then
				table.insert(protectedInstances, instance)
			end
		end
		if #protectedInstances == 0 then
			return false, nil, nil
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = protectedInstances
	params.RespectCanCollide = false
	params.MaxParts = 1
	local hit = Workspace:GetPartBoundsInBox(frame, size, params)[1]
	return hit ~= nil,
		"PROTECTED_AREA_OVERLAP",
		if hit then string.sub(hit:GetFullName(), 1, 512) else nil
end

function RegionSpawnCatalog.IsProtectedSpace(
	envelopeFrame: unknown,
	envelopeSize: unknown
): (boolean, string?)
	if
		typeof(envelopeFrame) ~= "CFrame"
		or not finiteVector3(
			if typeof(envelopeFrame) == "CFrame" then envelopeFrame.Position else nil
		)
		or not finiteVector3(envelopeSize)
		or envelopeSize.X <= 0
		or envelopeSize.Y <= 0
		or envelopeSize.Z <= 0
	then
		return true, "INVALID_ENVELOPE"
	end
	local protected, reason = isProtected(current(), envelopeFrame, envelopeSize)
	return protected, reason
end

-- The one-time Camp-return lifecycle has already admitted a real world member
-- inside the protected hub. Ignore only the Camp floor while it exits; bases,
-- service stalls, and cart-spawn protection remain authoritative.
function RegionSpawnCatalog.IsProtectedForCampReturn(
	envelopeFrame: unknown,
	envelopeSize: unknown
): (boolean, string?, string?)
	if
		typeof(envelopeFrame) ~= "CFrame"
		or not finiteVector3(
			if typeof(envelopeFrame) == "CFrame" then envelopeFrame.Position else nil
		)
		or not finiteVector3(envelopeSize)
		or envelopeSize.X <= 0
		or envelopeSize.Y <= 0
		or envelopeSize.Z <= 0
	then
		return true, "INVALID_ENVELOPE", nil
	end
	return isProtected(current(), envelopeFrame, envelopeSize, Regions.CampId)
end

function RegionSpawnCatalog.IsInsideHuntingSpace(
	regionId: unknown,
	envelopeFrame: unknown,
	envelopeSize: unknown,
	boundaryPadding: number?
): (boolean, string?)
	local index = current()
	local normalizedRegion = Regions.NormalizeId(regionId)
	local region = if normalizedRegion then index.regionsById[normalizedRegion] else nil
	if
		region == nil
		or normalizedRegion == Regions.CampId
		or region.kind ~= "Hunting"
		or region.enabled ~= true
		or region.naturalSpawnAllowed ~= true
	then
		return false, "REGION_NOT_SPAWNABLE"
	end
	if
		typeof(envelopeFrame) ~= "CFrame"
		or not finiteVector3(
			if typeof(envelopeFrame) == "CFrame" then envelopeFrame.Position else nil
		)
		or not finiteVector3(envelopeSize)
		or envelopeSize.X <= 0
		or envelopeSize.Y <= 0
		or envelopeSize.Z <= 0
	then
		return false, "INVALID_ENVELOPE"
	end
	local padding = boundaryPadding
	if type(padding) ~= "number" or padding ~= padding or padding < 0 or padding == math.huge then
		padding = BrainrotTerritory.BoundaryPaddingStuds
	end
	local inside = false
	for _, boundary in index.boundariesByRegion[normalizedRegion] do
		if boxFitsPart(envelopeFrame, envelopeSize, boundary, padding) then
			inside = true
			break
		end
	end
	if not inside then
		inside = boxFitsFloorUnion(
			envelopeFrame,
			envelopeSize,
			index.boundariesByRegion[normalizedRegion],
			padding
		)
	end
	if not inside then
		return false, "OUTSIDE_REGION"
	end
	local protected, reason = isProtected(index, envelopeFrame, envelopeSize)
	if protected then
		return false, reason or "PROTECTED_AREA_OVERLAP"
	end
	return true, nil
end

-- Boundary-only query used by the one-time Camp-return lifecycle. Unlike the
-- natural-placement query it permits the protected Camp hub and does not imply
-- spawn eligibility.
function RegionSpawnCatalog.IsInsideRegionSpace(
	regionId: unknown,
	envelopeFrame: unknown,
	envelopeSize: unknown,
	boundaryPadding: number?
): (boolean, string?)
	local index = current()
	local normalizedRegion = Regions.NormalizeId(regionId)
	local region = if normalizedRegion then index.regionsById[normalizedRegion] else nil
	if region == nil or region.enabled ~= true then
		return false, "UNKNOWN_REGION"
	end
	if
		typeof(envelopeFrame) ~= "CFrame"
		or not finiteVector3(
			if typeof(envelopeFrame) == "CFrame" then envelopeFrame.Position else nil
		)
		or not finiteVector3(envelopeSize)
		or envelopeSize.X <= 0
		or envelopeSize.Y <= 0
		or envelopeSize.Z <= 0
	then
		return false, "INVALID_ENVELOPE"
	end
	local padding = boundaryPadding
	if type(padding) ~= "number" or padding ~= padding or padding < 0 or padding == math.huge then
		padding = BrainrotTerritory.BoundaryPaddingStuds
	end
	for _, boundary in index.boundariesByRegion[normalizedRegion] do
		if boxFitsPart(envelopeFrame, envelopeSize, boundary, padding) then
			return true, nil
		end
	end
	if
		boxFitsFloorUnion(
			envelopeFrame,
			envelopeSize,
			index.boundariesByRegion[normalizedRegion],
			padding
		)
	then
		return true, nil
	end
	return false, "OUTSIDE_REGION"
end

local function validateClearance(
	index: Index,
	frame: CFrame,
	size: Vector3,
	area: SpawnArea,
	definition: any
): (boolean, string?)
	if type(index.context.ValidateClearance) == "function" then
		return index.context.ValidateClearance(frame, size, area, definition)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { area.Part }
	params.RespectCanCollide = true
	params.MaxParts = 1
	local padded = size
		+ (
			if Phase10.Enabled
				then Vector3.one * Phase10.SafetySkin * 2
				else Vector3.new(0.2, 0, 0.2)
		)
	if Phase10.Enabled then
		local clear, reason = CartLocalPlacement.IsBrainrotVolumeClear(frame, padded, params)
		if not clear then
			return false, reason
		end
		if not CartLocalPlacement.IsBrainrotGateClear(frame, size) then
			return false, "SEMANTIC_GATE_OVERLAP"
		end
		return CartLocalPlacement.IsTerrainClear(frame, size, "OrdinarySpawn")
	end
	return #Workspace:GetPartBoundsInBox(frame, padded, params) == 0, "INSUFFICIENT_CLEARANCE"
end

function RegionSpawnCatalog.ValidatePlacement(
	speciesId: unknown,
	regionId: unknown,
	areaId: unknown,
	candidatePosition: unknown
): any
	local index = current()
	local reasons: { string } = {}
	local normalizedSpecies = BrainrotCatalog.NormalizeId(speciesId)
	local normalizedRegion = Regions.NormalizeId(regionId)
	local definition = if normalizedSpecies then index.speciesById[normalizedSpecies] else nil
	local area = if type(areaId) == "string" then index.areasById[areaId] else nil
	if definition == nil then
		table.insert(reasons, "UNKNOWN_SPECIES")
	end
	if normalizedRegion == nil or index.regionsById[normalizedRegion] == nil then
		table.insert(reasons, "UNKNOWN_REGION")
	elseif normalizedRegion == Regions.CampId then
		table.insert(reasons, "CAMP_NOT_SPAWNABLE")
	end
	if area == nil then
		table.insert(reasons, "MISSING_SPAWN_AREA")
	elseif area.RegionId ~= normalizedRegion then
		table.insert(reasons, "SPAWN_AREA_REGION_MISMATCH")
	elseif not area.Enabled then
		table.insert(reasons, "SPAWN_AREA_DISABLED")
	end
	if not finiteVector3(candidatePosition) then
		table.insert(reasons, "INVALID_CANDIDATE_POSITION")
	end
	if
		definition
		and normalizedRegion
		and not RegionSpawnCatalog.IsSpeciesAllowedInRegion(definition.id, normalizedRegion)
	then
		table.insert(
			reasons,
			if definition.regionAssignmentStatus == "Pending"
				then "REGION_ASSIGNMENT_PENDING"
				elseif
					definition.regionAssignmentStatus == "Conflict"
				then "REGION_ASSIGNMENT_CONFLICT"
				else "SPECIES_NOT_ALLOWED_IN_REGION"
		)
	end
	if #reasons > 0 then
		return table.freeze({ valid = false, reasons = table.freeze(reasons) })
	end

	local localEnvelopeFrame, envelopeSize, envelopeReason = getEnvelope(index, definition)
	if localEnvelopeFrame == nil or envelopeSize == nil then
		table.insert(reasons, envelopeReason or "MODEL_MISSING")
		return table.freeze({ valid = false, reasons = table.freeze(reasons) })
	end
	local candidate = candidatePosition :: Vector3
	local groundValid, groundPosition, groundReason =
		validateGround(index, candidate, area, definition)
	if not groundValid or groundPosition == nil then
		table.insert(reasons, groundReason or "NO_VALID_GROUND")
		return table.freeze({ valid = false, reasons = table.freeze(reasons) })
	end

	local basePivot = CFrame.new(groundPosition.X, groundPosition.Y, groundPosition.Z)
		* area.Part.CFrame.Rotation
	local initialEnvelopeFrame = basePivot * localEnvelopeFrame
	if Phase10.Enabled and type(index.context.ValidateGround) ~= "function" then
		local supportedGround, footprintReason =
			validateFootprint(candidate, initialEnvelopeFrame, envelopeSize, area)
		if not supportedGround then
			return table.freeze({
				valid = false,
				reasons = table.freeze({ footprintReason or "UNSUPPORTED_FOOTPRINT" }),
			})
		end
		groundPosition = supportedGround
	end
	local half = envelopeSize * 0.5
	local verticalHalf = math.abs(initialEnvelopeFrame.RightVector.Y) * half.X
		+ math.abs(initialEnvelopeFrame.UpVector.Y) * half.Y
		+ math.abs(initialEnvelopeFrame.LookVector.Y) * half.Z
	local lift = groundPosition.Y
		- (initialEnvelopeFrame.Position.Y - verticalHalf)
		+ (if Phase10.Enabled then Phase10.SafetySkin else 0.1)
	local placementPivot = basePivot + Vector3.yAxis * lift
	local envelopeFrame = placementPivot * localEnvelopeFrame
	if area.Kind == "Point" then
		local horizontal =
			Vector2.new(candidate.X - area.Part.Position.X, candidate.Z - area.Part.Position.Z)
		if horizontal.Magnitude > 0.75 or math.abs(candidate.Y - area.Part.Position.Y) > 2 then
			table.insert(reasons, "CANDIDATE_OUTSIDE_SPAWN_AREA")
		end
	elseif not boxFitsPart(envelopeFrame, envelopeSize, area.Part) then
		table.insert(reasons, "CANDIDATE_OUTSIDE_SPAWN_AREA")
	end

	local boundaries = index.boundariesByRegion[normalizedRegion]
	local insideBoundary = false
	for _, boundary in boundaries do
		if
			boxFitsPart(
				envelopeFrame,
				envelopeSize,
				boundary,
				BrainrotTerritory.BoundaryPaddingStuds
			)
		then
			insideBoundary = true
			break
		end
	end
	if not insideBoundary then
		table.insert(reasons, "OUTSIDE_REGION_BOUNDARY")
	end
	local protected, protectedReason = isProtected(index, envelopeFrame, envelopeSize)
	if protected then
		table.insert(reasons, protectedReason or "PROTECTED_AREA_OVERLAP")
	end
	local clear, clearanceReason =
		validateClearance(index, envelopeFrame, envelopeSize, area, definition)
	if not clear then
		table.insert(reasons, clearanceReason or "INSUFFICIENT_CLEARANCE")
	end
	return table.freeze({
		valid = #reasons == 0,
		reasons = table.freeze(reasons),
		groundPosition = groundPosition,
		placementPivot = placementPivot,
		placementEnvelope = envelopeFrame,
	})
end

function RegionSpawnCatalog.ValidateConfiguration(): ValidationReport
	return cloneReport(current().report)
end

function RegionSpawnCatalog.GetRegionSummary(): { any }
	local index = current()
	local summary = {}
	for _, regionId in index.regionOrder do
		local readyCount = 0
		for _, speciesId in index.approvedSpeciesByRegion[regionId] do
			if RegionSpawnCatalog.EvaluateNaturalSpawnReadiness(speciesId, regionId).ready then
				readyCount += 1
			end
		end
		local usableAreas = 0
		for _, area in index.areasByRegion[regionId] do
			if area.Enabled and area.UsableProbeCount > 0 then
				usableAreas += 1
			end
		end
		table.insert(
			summary,
			table.freeze({
				regionId = regionId,
				boundaryCount = #index.boundariesByRegion[regionId],
				approvedSpeciesCount = #index.approvedSpeciesByRegion[regionId],
				technicallyReadySpeciesCount = readyCount,
				spawnAreaCount = #index.areasByRegion[regionId],
				usableSpawnAreaCount = usableAreas,
			})
		)
	end
	return summary
end

function RegionSpawnCatalog.Start(): ValidationReport
	if started then
		return RegionSpawnCatalog.ValidateConfiguration()
	end
	local report = RegionSpawnCatalog.BuildIndex(Regions.GetAll(), BrainrotCatalog.GetAll(), nil)
	started = true
	local counts: { [string]: number } = {}
	for _, item in report.errors do
		counts[item.code] = (counts[item.code] or 0) + 1
	end
	for _, item in report.warnings do
		counts[item.code] = (counts[item.code] or 0) + 1
	end
	local summary = {}
	for code, count in counts do
		table.insert(summary, string.format("%s=%d", code, count))
	end
	table.sort(summary)
	log:Info(
		"Regional configuration: %d error(s), %d warning(s), natural spawning unchanged",
		#report.errors,
		#report.warnings
	)
	if #summary > 0 then
		log:Warn("Regional readiness issues: %s", table.concat(summary, ", "))
	end
	return report
end

return RegionSpawnCatalog
