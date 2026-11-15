--!nocheck
-- Cached authored routes. Dynamic reconnect/arrival checks never create or move map content.
local RS = game:GetService("ReplicatedStorage")
local W = workspace
local Data = require(RS.Shared.Config.BurrowRoutes)
local Rules = require(RS.Shared.Utility.BrainrotRouteRules)
local Regions = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Catalog = {}
local routes, mouths, byRegion = {}, {}, {}
local fixtureOverride = false
local containsRegion = Regions.ContainsPosition
local function vector(p)
	return Vector3.new(p.X, p.Y, p.Z)
end
local function buildCache()
	routes, mouths, byRegion = {}, {}, {}
	if not Data.Ready then
		return
	end
	for _, row in Data.Mouths do
		local m = table.clone(row)
		m.Position = vector(row.Position)
		mouths[m.Id] = table.freeze(m)
		byRegion[m.RegionId] = byRegion[m.RegionId] or {}
		table.insert(byRegion[m.RegionId], m.Id)
	end
	for _, row in Data.Routes do
		if row.Validated == true then
			local r = table.clone(row)
			r.Points = {}
			for _, p in row.Points do
				table.insert(r.Points, vector(p))
			end
			r.Length = Rules.Length(r.Points)
			r.Version = Data.GeometryVersion
			table.freeze(r.Points)
			routes[r.Id] = table.freeze(r)
		end
	end
	for regionId, ids in byRegion do
		table.sort(ids)
		if #ids == 1 then
			local id = ids[1]
			local point = mouths[id].Position
			routes[id .. ">" .. id] = table.freeze({
				Id = id .. ">" .. id,
				RegionId = regionId,
				EntranceId = id,
				DestinationId = id,
				Points = table.freeze({ point, point }),
				Length = 0,
				Version = Data.GeometryVersion,
			})
		end
	end
end
buildCache()
function Catalog.IsReady()
	if fixtureOverride then
		return true
	end
	local folder = W:FindFirstChild("Phase12Burrows")
	return Data.Ready
		and folder ~= nil
		and folder:GetAttribute("Phase13GeometryVersion") == Data.GeometryVersion
end
function Catalog.Get(id)
	return if Catalog.IsReady() then routes[id] else nil
end
function Catalog.GetMouth(id)
	return mouths[id]
end
function Catalog.GetVersion()
	return Data.GeometryVersion
end
function Catalog.GetRegionRoutes(regionId)
	local result = {}
	for id, route in routes do
		if route.RegionId == regionId then
			result[id] = route
		end
	end
	return result
end
function Catalog.Pick(regionId, random)
	if not Catalog.IsReady() then
		return nil, "ROUTE_GEOMETRY_NOT_VALIDATED"
	end
	return Rules.PickJourney(byRegion[regionId] or {}, routes, function(a, b)
		return random:NextInteger(a, b)
	end)
end
local function params(ignored)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = table.clone(ignored or {})
	local f = W:FindFirstChild("Phase12Burrows")
	if f then
		table.insert(excluded, f)
	end
	p.FilterDescendantsInstances = excluded
	p.RespectCanCollide = true
	return p
end
function Catalog.ValidateSegment(regionId, a, b, ignored)
	if not Catalog.IsReady() or not Data.Hull then
		return false, "ROUTE_GEOMETRY_NOT_VALIDATED"
	end
	local size = vector(Data.Hull)
	local rp = params(ignored)
	local count = math.max(1, math.ceil((b - a).Magnitude / 4))
	for i = 0, count do
		local point = a:Lerp(b, i / count)
		for _, offset in
			{
				Vector3.zero,
				Vector3.new(-size.X / 2, 0, -size.Z / 2),
				Vector3.new(-size.X / 2, 0, size.Z / 2),
				Vector3.new(size.X / 2, 0, -size.Z / 2),
				Vector3.new(size.X / 2, 0, size.Z / 2),
			}
		do
			local sample = point + offset
			if not containsRegion(regionId, sample, 2) then
				return false, "ROUTE_LEAVES_REGION"
			end
			local h = W:Raycast(sample + Vector3.yAxis * 8, -Vector3.yAxis * 16, rp)
			if not h or h.Normal.Y < 0.9 or math.abs(h.Position.Y - point.Y) > 0.65 then
				return false, "ROUTE_SUPPORT_CHANGED"
			end
		end
	end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = rp.FilterDescendantsInstances
	op.RespectCanCollide = true
	op.MaxParts = 1
	local cf = CFrame.new(a + Vector3.yAxis * (size.Y / 2 + 0.15))
	if #W:GetPartBoundsInBox(cf, size, op) > 0 then
		return false, "ROUTE_START_BLOCKED"
	end
	local delta = b - a
	if delta.Magnitude > 1e-6 then
		local distance = delta.Magnitude
		local covered = 0
		while covered < distance do
			local step = math.min(1023.999, distance - covered)
			if W:Blockcast(cf + delta.Unit * covered, size, delta.Unit * step, rp) then
				return false, "ROUTE_BLOCKED"
			end
			covered += step
		end
	end
	return true, nil
end
function Catalog.FindReconnect(journey, groundPosition, ignored, maximumDistance)
	local route = Catalog.Get(journey.RouteId)
	if not route or route.Version ~= journey.RouteVersion then
		return nil, "ROUTE_VERSION_INVALIDATED"
	end
	if not containsRegion(route.RegionId, groundPosition, 2) then
		return nil, "ORIGINAL_ROUTE_REGION_REQUIRED"
	end
	if journey.Wandering then
		local clear, why =
			Catalog.ValidateSegment(route.RegionId, groundPosition, groundPosition, ignored)
		if clear then
			return { Point = groundPosition, Progress = journey.Progress, Distance = 0 }, nil
		end
		return nil, why
	end
	local projection = Rules.Project(route.Points, groundPosition, journey.Progress)
	if
		not projection
		or projection.Distance > (maximumDistance or Data.MaxReconnectDistance or 8)
	then
		return nil, "NO_LOCAL_ROUTE_RECONNECT"
	end
	local clear, reason =
		Catalog.ValidateSegment(route.RegionId, groundPosition, projection.Point, ignored)
	if not clear then
		return nil, reason
	end
	return {
		Point = projection.Point,
		Progress = projection.Progress,
		Distance = projection.Distance,
	},
		nil
end
function Catalog.ValidateArrival(journey, groundPosition, ignored)
	local route = Catalog.Get(journey.RouteId)
	if
		not route
		or route.DestinationId ~= journey.DestinationBurrowId
		or route.Version ~= journey.RouteVersion
	then
		return false, "DESTINATION_CHANGED"
	end
	local endpoint = route.Points[#route.Points]
	if
		(groundPosition - endpoint).Magnitude > (Data.ArrivalRadius or 3)
		or math.abs(groundPosition.Y - endpoint.Y) > 0.65
	then
		return false, "NOT_AT_DESTINATION"
	end
	return Catalog.ValidateSegment(route.RegionId, groundPosition, endpoint, ignored)
end
-- Scoped native-fixture data, not a replacement collision implementation. The
-- same production ray/overlap/sweep functions query real temporary Parts. Restored
-- even when a fixture throws; unavailable outside Studio and never remote-exposed.
function Catalog._TestWithGeometry(data, contains, callback)
	assert(game:GetService("RunService"):IsStudio(), "Studio fixture only")
	local previous = {
		Data = Data,
		Routes = routes,
		Mouths = mouths,
		ByRegion = byRegion,
		Contains = containsRegion,
		Fixture = fixtureOverride,
	}
	Data = data
	containsRegion = contains
	fixtureOverride = true
	local result = table.pack(xpcall(function()
		buildCache()
		return callback()
	end, debug.traceback))
	Data = previous.Data
	routes = previous.Routes
	mouths = previous.Mouths
	byRegion = previous.ByRegion
	containsRegion = previous.Contains
	fixtureOverride = previous.Fixture
	if not result[1] then
		error(result[2], 0)
	end
	return table.unpack(result, 2, result.n)
end
function Catalog.Report()
	local count = 0
	for _ in routes do
		count += 1
	end
	return {
		Ready = Catalog.IsReady(),
		GeometryVersion = Data.GeometryVersion,
		RouteCount = count,
		Mouths = mouths,
	}
end
return Catalog
