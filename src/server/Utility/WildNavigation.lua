--!nocheck
-- One fair, bounded path queue, pumped by the existing roaming heartbeat.
local RS = game:GetService("ReplicatedStorage")
local Pathfinding = game:GetService("PathfindingService")
local Regions = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Catalog = require(script.Parent.BurrowRouteCatalog)
local Scale = require(RS.Shared.Utility.BrainrotVisualScale)
local C = require(RS.Shared.Config.AfternoonRepair).Roaming
local Navigation = {}
local queue, queued, starts = {}, {}, {}
local outstanding = 0
local stats = {
	started = 0,
	completed = 0,
	rejected = 0,
	stale = 0,
	maxOutstanding = 0,
	maxStartsInWindow = 0,
	segmentChecks = 0,
}
local function params(model)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.RespectCanCollide = true
	local excluded = { model }
	for _, name in
		{ "Runtime", "Phase12Burrows", "CreaturePresentation", "ChariotTeamPresentation" }
	do
		local x = workspace:FindFirstChild(name)
		if x then
			table.insert(excluded, x)
		end
	end
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	p.FilterDescendantsInstances = excluded
	return p
end
function Navigation.Body(model)
	local _, size = Scale.GetVisualBounds(model)
	assert(size and size.X > 0 and size.Y > 0 and size.Z > 0, "Measured body envelope required")
	return size
end
function Navigation.Project(motor, point)
	local hit = workspace:Raycast(
		point + Vector3.yAxis * C.GroundUp,
		-Vector3.yAxis * C.GroundDown,
		motor.Params
	)
	if not hit or hit.Normal.Y < C.GroundNormal then
		return nil
	end
	if not Regions.ContainsPosition(motor.Route.RegionId, hit.Position, C.GroundTolerance) then
		return nil
	end
	return hit.Position
end
function Navigation.ValidateSegment(motor, a, b)
	stats.segmentChecks += 1
	local delta = b - a
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local direction = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.zAxis
	local size = motor.BodySize
	-- The entire swept rectangle must fit the authoritative floor union, not
	-- just endpoints. This rejects shortcuts across concave region cut-outs.
	local sweep = CFrame.lookAt(
		(a + b) / 2 + Vector3.yAxis * (size.Y / 2 + C.BodyClearance),
		(a + b) / 2 + Vector3.yAxis * (size.Y / 2 + C.BodyClearance) + direction
	)
	local inside, why = Regions.IsInsideHuntingSpace(
		motor.Route.RegionId,
		sweep,
		Vector3.new(size.X, size.Y, flat.Magnitude + size.Z),
		0
	)
	if not inside then
		return false, why
	end
	local count = math.max(1, math.ceil(delta.Magnitude / C.GroundStep))
	local tangent = Vector3.new(-direction.Z, 0, direction.X)
	for i = 0, count do
		local point = a:Lerp(b, i / count)
		for _, side in { -1, 1 } do
			for _, front in { -1, 1 } do
				local sample = point
					+ tangent * (side * size.X / 2)
					+ direction * (front * size.Z / 2)
				local hit = workspace:Raycast(
					sample + Vector3.yAxis * C.GroundUp,
					-Vector3.yAxis * C.GroundDown,
					motor.Params
				)
				if
					not hit
					or hit.Normal.Y < C.GroundNormal
					or math.abs(hit.Position.Y - point.Y) > C.GroundTolerance
				then
					return false, "UNSUPPORTED_FOOTPRINT"
				end
			end
		end
	end
	local frame = CFrame.lookAt(
		a + Vector3.yAxis * (size.Y / 2 + C.BodyClearance),
		a + Vector3.yAxis * (size.Y / 2 + C.BodyClearance) + direction
	)
	local box = Vector3.new(size.X, size.Y, size.Z)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = motor.ObstacleParams.FilterDescendantsInstances
	overlap.RespectCanCollide = true
	overlap.MaxParts = 1
	if #workspace:GetPartBoundsInBox(frame, box, overlap) > 0 then
		return false, "FOOTPRINT_START_BLOCKED"
	end
	if delta.Magnitude > 1e-6 and workspace:Blockcast(frame, box, delta, motor.ObstacleParams) then
		return false, "BLOCKED_LEG"
	end
	return true
end
function Navigation.ValidateGoal(motor, point)
	-- Reserve enough measured footprint to turn toward the next independently
	-- chosen heading. A legal incoming orientation alone can strand a wide body
	-- at a region edge where no outgoing orientation fits.
	local size = motor.BodySize
	local diameter = math.sqrt(size.X * size.X + size.Z * size.Z)
	local centre = point + Vector3.yAxis * (size.Y / 2 + C.BodyClearance)
	if
		not Regions.IsInsideHuntingSpace(
			motor.Route.RegionId,
			CFrame.new(centre),
			Vector3.new(diameter, size.Y, diameter),
			0
		)
	then
		return false
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local p = point + Vector3.new(x * diameter / 2, 0, z * diameter / 2)
			local hit = workspace:Raycast(
				p + Vector3.yAxis * C.GroundUp,
				-Vector3.yAxis * C.GroundDown,
				motor.Params
			)
			if
				not hit
				or hit.Normal.Y < C.GroundNormal
				or math.abs(hit.Position.Y - point.Y) > C.GroundTolerance
			then
				return false
			end
		end
	end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = motor.ObstacleParams.FilterDescendantsInstances
	op.RespectCanCollide = true
	op.MaxParts = 1
	return #workspace:GetPartBoundsInBox(
		CFrame.new(centre),
		Vector3.new(diameter, size.Y, diameter),
		op
	) == 0
end
function Navigation.Prepare(motor)
	motor.BodySize = Navigation.Body(motor.Model)
	motor.Params = params(motor.Model)
	motor.ObstacleParams = params(motor.Model)
	local excluded = table.clone(motor.ObstacleParams.FilterDescendantsInstances)
	-- Explicit floor membership from the authoritative region catalogue, not
	-- names/size heuristics. Ground rays still include these supported surfaces.
	for _, area in Regions.GetSpawnAreas(motor.Route.RegionId) do
		if area.IsFloorSurface then
			table.insert(excluded, area.Part)
		end
	end
	motor.ObstacleParams.FilterDescendantsInstances = excluded
end
function Navigation.Mouths(motor)
	local report = Catalog.Report()
	local result = {}
	local ids = {}
	-- Authored route graph is immutable connectivity evidence. The current
	-- position still needs a validated direct/pathfinding connection to it.
	for _, r in Catalog.GetRegionRoutes(motor.Route.RegionId) do
		ids[r.EntranceId] = true
		ids[r.DestinationId] = true
	end
	ids[motor.EntranceId] = true
	for id, mouth in report.Mouths do
		if mouth.RegionId == motor.Route.RegionId and ids[id] then
			table.insert(result, { Id = id, Position = mouth.Position })
		end
	end
	table.sort(result, function(a, b)
		return a.Id < b.Id
	end)
	return result
end
function Navigation.ConnectedExit(motor, current, mouth)
	-- Use a validated connection to the cached static graph if a direct leg
	-- is blocked. Every segment is rechecked for this individual's full body.
	for _, r in Catalog.GetRegionRoutes(motor.Route.RegionId) do
		if r.DestinationId == mouth.Id then
			local best
			for i, p in r.Points do
				if Navigation.ValidateSegment(motor, current, p) then
					local points = { p }
					local a = p
					local valid = true
					for j = i + 1, #r.Points do
						local b = r.Points[j]
						if not Navigation.ValidateSegment(motor, a, b) then
							valid = false
							break
						end
						table.insert(points, b)
						a = b
					end
					if valid and (not best or (p - current).Magnitude < best.distance) then
						best = { points = points, distance = (p - current).Magnitude }
					end
				end
			end
			if best then
				return best.points
			end
		end
	end
	return nil
end
function Navigation.Cancel(motor)
	queued[motor] = nil
end
function Navigation.Request(motor, a, b, callback)
	if queued[motor] then
		return false
	end
	local count = 0
	for _ in queued do
		count += 1
	end
	if count >= C.MaxPathQueue then
		return false
	end
	local state = motor.Context.GetState()
	if not state then
		return false
	end
	local job = {
		motor = motor,
		a = a,
		b = b,
		revision = state.Revision,
		generation = motor.Generation,
		callback = callback,
	}
	queued[motor] = job
	table.insert(queue, job)
	return true
end
local function current(job)
	local m = job.motor
	local s = m.Context.GetState()
	return not m.Destroyed
		and m.Model.Parent ~= nil
		and m.Generation == job.generation
		and m.Model:GetAttribute("Captured") ~= true
		and s
		and s.Revision == job.revision
end
function Navigation.Pump(now)
	while starts[1] and now - starts[1] >= 1 do
		table.remove(starts, 1)
	end
	while outstanding < C.PathOutstanding and #starts < C.PathStartsPerSecond and #queue > 0 do
		local job = table.remove(queue, 1)
		if queued[job.motor] ~= job then
			continue
		end
		queued[job.motor] = nil
		if not current(job) then
			stats.stale += 1
			job.callback(nil, "STALE_PATH")
			continue
		end
		table.insert(starts, now)
		outstanding += 1
		stats.started += 1
		stats.maxOutstanding = math.max(stats.maxOutstanding, outstanding)
		stats.maxStartsInWindow = math.max(stats.maxStartsInWindow, #starts)
		task.spawn(function()
			local m = job.motor
			local body = m.BodySize
			local path = Pathfinding:CreatePath({
				AgentRadius = math.ceil(math.max(body.X, body.Z) / 2),
				AgentHeight = math.ceil(body.Y),
				AgentCanJump = false,
				AgentCanClimb = false,
			})
			local ok = pcall(function()
				path:ComputeAsync(job.a, job.b)
			end)
			local points = nil
			if ok and path.Status == Enum.PathStatus.Success then
				points = {}
				local from = job.a
				for _, waypoint in path:GetWaypoints() do
					local point = Navigation.Project(m, waypoint.Position)
					if
						not point
						or waypoint.Action ~= Enum.PathWaypointAction.Walk
						or not Navigation.ValidateSegment(m, from, point)
					then
						points = nil
						break
					end
					table.insert(points, point)
					from = point
				end
				if points and Navigation.ValidateSegment(m, from, job.b) then
					table.insert(points, job.b)
				else
					points = nil
				end
			end
			path:Destroy()
			outstanding -= 1
			stats.completed += 1
			if current(job) then
				if not points then
					stats.rejected += 1
				end
				job.callback(points, if points then nil else "NO_CONNECTED_PATH")
			else
				stats.stale += 1
				job.callback(nil, "STALE_PATH")
			end
		end)
	end
end
function Navigation.GetDiagnostics()
	local r = table.clone(stats)
	r.outstanding = outstanding
	r.queued = 0
	for _ in queued do
		r.queued += 1
	end
	return r
end
return Navigation
