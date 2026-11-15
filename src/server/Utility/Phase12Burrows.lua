--!nocheck
-- Burrows provide authored, validated locations to the existing spawner. They
-- have no population, AI, physics assemblies, lights or update loop.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12)
local Territory = require(ReplicatedStorage.Shared.Config.BrainrotTerritory)
local RegionSpawnCatalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Routes = require(script.Parent.BurrowRouteCatalog)
local RouteRules = require(ReplicatedStorage.Shared.Utility.BrainrotRouteRules)

local Burrows = {}
local usableByRegion = {}
local lastReport = nil
local prefixes = {
	REGION_BEACH = "B",
	REGION_FOREST = "F",
	REGION_SWAMP = "S",
	REGION_JUNGLE = "J",
	REGION_ARCTIC = "A",
	REGION_VOLCANO = "V",
	REGION_GLITCH = "G",
}
local colors = {
	REGION_BEACH = Color3.fromRGB(164, 121, 68),
	REGION_FOREST = Color3.fromRGB(70, 103, 48),
	REGION_SWAMP = Color3.fromRGB(77, 77, 51),
	REGION_JUNGLE = Color3.fromRGB(56, 107, 59),
	REGION_ARCTIC = Color3.fromRGB(122, 179, 207),
	REGION_VOLCANO = Color3.fromRGB(100, 57, 61),
	REGION_GLITCH = Color3.fromRGB(101, 49, 153),
}

local function compactPose(pose)
	return { X = pose.X, Y = pose.Y, Z = pose.Z }
end

local function markerPose(instance)
	local marker = instance:FindFirstChild("Emergence", true)
		or instance:FindFirstChild("Opening", true)
	if marker and marker:IsA("Attachment") then
		return marker.WorldCFrame
	end
	if marker and marker:IsA("BasePart") then
		return marker.CFrame
	end
	return nil
end

local function ground(point, excluded)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded or {}
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(point + Vector3.yAxis * 8, -Vector3.yAxis * 16, params)
	if not hit or hit.Normal.Y < 0.9 or not hit.Instance:IsA("BasePart") then
		return nil
	end
	return hit
end

local function validate(regionId, pose, exclude, occupied)
	local reasons = {}
	if not pose or not RegionSpawnCatalog.ContainsPosition(regionId, pose.Position, 2) then
		return false, { "REGION_OR_EMERGENCE_INVALID" }
	end
	-- Opening and approach are supported by current authored spawn geometry.
	for _, offset in
		{
			Vector3.zero,
			Vector3.new(-4, 0, 0),
			Vector3.new(4, 0, 0),
			Vector3.new(0, 0, -6),
			Vector3.new(0, 0, -12),
		}
	do
		local point = pose:PointToWorldSpace(offset)
		local support = ground(point, exclude)
		if
			not support
			or math.abs(support.Position.Y - pose.Y) > 0.65
			or not RegionSpawnCatalog.ContainsPosition(regionId, support.Position, 2)
		then
			table.insert(reasons, "UNSUPPORTED_OPENING_OR_CART_APPROACH")
			break
		end
	end
	local approach = pose * CFrame.new(0, 3, -4)
	local size = Vector3.new(11, 5.6, 19)
	if RegionSpawnCatalog.IsProtectedSpace(approach, size) then
		table.insert(reasons, "PROTECTED_SPACE")
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude or {}
	params.RespectCanCollide = true
	params.MaxParts = 64
	for _, part in Workspace:GetPartBoundsInBox(approach, size, params) do
		if part.CanCollide and part.Position.Y + part.Size.Y / 2 > pose.Y + 0.5 then
			table.insert(reasons, "OPENING_OR_APPROACH_BLOCKED")
			break
		end
		if
			part:GetAttribute("MainDrivingLane") == true
			or part:GetAttribute("DrivingLane") == true
			or string.find(string.lower(part.Name), "road", 1, true)
			or string.find(string.lower(part.Name), "lane", 1, true)
		then
			table.insert(reasons, "MAIN_DRIVING_LANE")
			break
		end
	end
	for _, prior in occupied or {} do
		local delta = prior.Position - pose.Position
		if Vector3.new(delta.X, 0, delta.Z).Magnitude < 22 then
			table.insert(reasons, "BURROW_TOO_CLOSE")
			break
		end
	end
	return #reasons == 0, reasons
end

local function makeTemplate(folder, id, regionId, pose, areaId)
	local model = Instance.new("Model")
	model.Name = "Burrow_" .. id
	model:SetAttribute("Phase12BurrowId", id)
	model:SetAttribute("RegionId", regionId)
	model:SetAttribute("SpawnAreaId", areaId)
	model:SetAttribute("Enabled", true)
	local main = colors[regionId] or Color3.fromRGB(91, 80, 101)
	local pieces = {
		{ "SideLeft", Vector3.new(1, 6, 5), Vector3.new(-4, 3, 1.5), main },
		{ "SideRight", Vector3.new(1, 6, 5), Vector3.new(4, 3, 1.5), main },
		{
			"Lintel",
			Vector3.new(9, 1, 5),
			Vector3.new(0, 6.5, 1.5),
			main:Lerp(Color3.new(1, 1, 1), 0.14),
		},
		{
			"SupportedBase",
			Vector3.new(9, 0.25, 5),
			Vector3.new(0, 0.125, 1.5),
			main:Lerp(Color3.new(0, 0, 0), 0.15),
		},
		{
			"DarkInterior",
			Vector3.new(7, 6, 0.25),
			Vector3.new(0, 3, 4),
			Color3.fromRGB(20, 18, 29),
		},
	}
	for _, spec in pieces do
		local part = Instance.new("Part")
		part.Name, part.Size, part.CFrame, part.Color =
			spec[1], spec[2], pose * CFrame.new(spec[3]), spec[4]
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.Material = Enum.Material.Glacier
		part.MaterialVariant = "Bingus_Saved_Studs_13719188279"
		part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		part.Parent = model
	end
	local marker = Instance.new("Attachment")
	marker.Name = "Emergence"
	marker.CFrame = model.SupportedBase.CFrame:ToObjectSpace(pose)
	marker.Parent = model.SupportedBase
	model.Parent = folder
	return model
end

local function candidatePose(area, attempt)
	local part = area.Part
	if not part or not part:IsA("BasePart") then
		return nil
	end
	local offsets = {
		Vector2.new(-0.34, -0.34),
		Vector2.new(0.34, -0.34),
		Vector2.new(-0.34, 0.34),
		Vector2.new(0.34, 0.34),
		Vector2.new(-0.34, 0),
		Vector2.new(0.34, 0),
		Vector2.new(0, -0.34),
		Vector2.new(0, 0.34),
	}
	local offset = offsets[(attempt - 1) % #offsets + 1]
	local point = part.CFrame:PointToWorldSpace(
		Vector3.new(offset.X * part.Size.X, part.Size.Y / 2, offset.Y * part.Size.Z)
	)
	local support = ground(point, {})
	if not support then
		return nil
	end
	local yaw = math.atan2(offset.X, offset.Y)
	-- Entrance faces the interior of the existing floor; carts approach from the
	-- clear negative local-Z side without entering the decorative tunnel.
	return CFrame.new(support.Position) * CFrame.Angles(0, yaw, 0)
end

function Burrows.Audit(createShortfall)
	table.clear(usableByRegion)
	local report = {
		Regions = {},
		Existing = {},
		Created = {},
		Rejected = {},
		TargetPerRegion = Phase12.BurrowsPerRegion,
	}
	local seenIds = {}
	local occupied = {}
	for _, region in Regions.GetAll() do
		if region.kind == "Hunting" then
			usableByRegion[region.id] = {}
		end
	end
	for _, instance in Workspace:GetDescendants() do
		if not instance:IsA("Model") and not instance:IsA("Folder") then
			continue
		end
		local id = instance:GetAttribute("Phase12BurrowId")
			or instance:GetAttribute("BrainrotBurrowId")
		if type(id) ~= "string" or id == "" then
			continue
		end
		local regionId = Regions.NormalizeId(instance:GetAttribute("RegionId"))
		local pose = markerPose(instance)
		local valid, reasons = false, { "UNKNOWN_HUNTING_REGION" }
		if regionId and usableByRegion[regionId] then
			valid, reasons = validate(regionId, pose, { instance }, occupied)
		end
		if seenIds[id] then
			valid = false
			table.insert(reasons, "DUPLICATE_BURROW_ID")
		end
		if instance:GetAttribute("Enabled") == false then
			valid = false
			table.insert(reasons, "DISABLED")
		end
		seenIds[id] = true
		local areaId = instance:GetAttribute("SpawnAreaId")
		if not areaId and regionId then
			for _, area in RegionSpawnCatalog.GetSpawnAreas(regionId) do
				local localPoint = if pose
					then area.Part.CFrame:PointToObjectSpace(pose.Position)
					else Vector3.new(math.huge, 0, 0)
				if
					math.abs(localPoint.X) <= area.Part.Size.X / 2
					and math.abs(localPoint.Z) <= area.Part.Size.Z / 2
				then
					areaId = area.Id
					break
				end
			end
		end
		if not areaId then
			valid = false
			table.insert(reasons, "SPAWN_AREA_UNRESOLVED")
		end
		local entry = {
			Id = id,
			RegionId = regionId,
			Pose = pose,
			Instance = instance,
			AreaId = areaId,
			Usable = valid,
		}
		local summary = {
			Id = id,
			RegionId = regionId,
			Position = if pose then compactPose(pose) else nil,
			Usable = valid,
			Reasons = reasons,
		}
		table.insert(report.Existing, summary)
		if valid then
			table.insert(usableByRegion[regionId], entry)
			table.insert(occupied, pose)
		end
	end
	local folder = Workspace:FindFirstChild("Phase12Burrows")
	if createShortfall and not folder then
		folder = Instance.new("Folder")
		folder.Name = "Phase12Burrows"
		folder.Parent = Workspace
	end
	for _, region in Regions.GetAll() do
		if region.kind ~= "Hunting" then
			continue
		end
		local entries = usableByRegion[region.id]
		local before = #entries
		local attempts = 0
		if createShortfall then
			for _, area in RegionSpawnCatalog.GetSpawnAreas(region.id) do
				if not area.Enabled or area.UsableProbeCount == 0 then
					continue
				end
				for sample = 1, 8 do
					if
						#entries >= Phase12.BurrowsPerRegion
						or attempts >= Territory.MaxPlacementAttemptsPerSpawn
					then
						break
					end
					attempts += 1
					local pose = candidatePose(area, sample)
					local valid, reasons =
						validate(region.id, pose, folder and { folder } or {}, occupied)
					if not valid then
						table.insert(
							report.Rejected,
							{ RegionId = region.id, AreaId = area.Id, Reasons = reasons }
						)
						continue
					end
					local sequence = 1
					while
						seenIds[(prefixes[region.id] or "X") .. string.format("%02d", sequence)]
					do
						sequence += 1
					end
					local id = (prefixes[region.id] or "X") .. string.format("%02d", sequence)
					seenIds[id] = true
					local model = makeTemplate(folder, id, region.id, pose, area.Id)
					table.insert(entries, {
						Id = id,
						RegionId = region.id,
						Pose = pose,
						Instance = model,
						AreaId = area.Id,
						Usable = true,
					})
					table.insert(occupied, pose)
					table.insert(report.Created, {
						Id = id,
						RegionId = region.id,
						AreaId = area.Id,
						Position = compactPose(pose),
						VisibleCuboids = 5,
					})
				end
				if
					#entries >= Phase12.BurrowsPerRegion
					or attempts >= Territory.MaxPlacementAttemptsPerSpawn
				then
					break
				end
			end
		end
		table.sort(entries, function(a, b)
			return a.Id < b.Id
		end)
		table.insert(report.Regions, {
			RegionId = region.id,
			ExistingUsable = before,
			Created = #entries - before,
			Usable = #entries,
			Shortfall = math.max(0, Phase12.BurrowsPerRegion - #entries),
			PlacementAttempts = attempts,
		})
	end
	lastReport = report
	return report
end

function Burrows.FindDestination(speciesId, regionId, random, existingJourney)
	local route, reason
	if existingJourney then
		route = Routes.Get(existingJourney.RouteId)
	else
		route, reason = Routes.Pick(regionId, random)
	end
	if not route then
		return nil, nil, reason or "ROUTE_VERSION_INVALIDATED", existingJourney
	end
	local journey = existingJourney or RouteRules.NewJourney(route)
	local entrance = nil
	for _, entry in usableByRegion[regionId] or {} do
		if entry.Id == journey.EntranceBurrowId then
			entrance = entry
			break
		end
	end
	if not entrance or not entrance.Instance.Parent then
		return nil, nil, "SELECTED_ENTRANCE_UNAVAILABLE", journey
	end
	local exit = entrance.Instance:FindFirstChild("Exit", true)
	if not exit or not exit:IsA("Attachment") then
		return nil, nil, "EXPLICIT_EXIT_REQUIRED", journey
	end
	local result = RegionSpawnCatalog.ValidatePlacement(
		speciesId,
		regionId,
		entrance.AreaId,
		entrance.Pose.Position
	)
	if not result.valid then
		return nil, entrance.Id, "SELECTED_ENTRANCE_BLOCKED", journey
	end
	local forward = route.Points[2] - route.Points[1]
	if forward.Magnitude < 1e-6 then
		forward = entrance.Pose.LookVector
	end
	local pose = CFrame.lookAt(
		result.placementPivot.Position,
		result.placementPivot.Position + Vector3.new(forward.X, 0, forward.Z)
	)
	return pose, entrance.Id, nil, journey
end

function Burrows.Nearest(regionId, position)
	local selected, distance = nil, math.huge
	for _, burrow in usableByRegion[regionId] or {} do
		if not burrow.Instance.Parent then
			continue
		end
		local candidate = (burrow.Pose.Position - position).Magnitude
		if
			candidate < distance or (candidate == distance and selected and burrow.Id < selected.Id)
		then
			selected, distance = burrow, candidate
		end
	end
	return if selected then selected.Id else nil
end

function Burrows.GetReport()
	return lastReport
end
return Burrows
