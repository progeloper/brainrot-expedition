--!nocheck
-- Purely read-only DEV Edit QA: no requires, clone/create/destroy, model moves,
-- attributes, Source writes, player/profile access or gameplay registration.
local V = {}
local OWNER = "BR_EnvironmentArt_V2"
local EXPECTED_JSON = [==[__EXPECTED_JSON__]==]
local Math = (function()
	-- __MATH_SOURCE__
end)()
local function array(frame)
	return { frame:GetComponents() }
end
local function xyz(v)
	return { v.X, v.Y, v.Z }
end
local function frame(a)
	return CFrame.new(table.unpack(a))
end
local function nearFrame(actual, expected)
	return Math.Close(array(actual), expected, 0.01)
end
local function actualBox(part)
	-- Installed masks are true primitive Parts. External PartOperation bounds
	-- remain conservative native extents, rather than a render-mesh claim.
	local transform, size = part.CFrame, part.Size
	if part:IsA("PartOperation") then
		transform, size = part.ExtentsCFrame, part.ExtentsSize
	end
	return Math.Box(array(transform), xyz(size))
end
local function polygonQueryBounds(poly, lowY, highY)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	assert(
		type(poly.convexCells) == "table" and #poly.convexCells > 0,
		"Exact convex reservation decomposition required"
	)
	for _, p in poly.exterior do
		x0 = math.min(x0, p[1])
		x1 = math.max(x1, p[1])
		z0 = math.min(z0, p[2])
		z1 = math.max(z1, p[2])
	end
	return CFrame.new((x0 + x1) / 2, (lowY + highY) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, highY - lowY, z1 - z0)
end
function V.Verify(options)
	options = options or {}
	assert(
		not game:GetService("RunService"):IsRunning(),
		"Read-only installed QA requires DEV Edit"
	)
	assert(game.PlaceId == 91958083796436, "Exact DEV place required")
	local expected = game:GetService("HttpService"):JSONDecode(EXPECTED_JSON)
	local map = assert(workspace:FindFirstChild("MapBlockout"), "Original map missing")
	local layer = options.layer
		or assert(map:FindFirstChild("EnvironmentArt_V2"), "Installed environment missing")
	assert(
		layer:IsDescendantOf(map)
			and layer:GetAttribute("ArtOwner") == OWNER
			and layer:GetAttribute("EnvironmentV2Status") == "Completed",
		"Completed owned installed layer required"
	)
	local wildRows = options.wildRows
		or (
			shared.EnvironmentV2WildNativeExtentsResult
			and shared.EnvironmentV2WildNativeExtentsResult.rows
		)
	assert(
		type(wildRows) == "table" and #wildRows == 35,
		"Exactly 35 measured native species required"
	)
	if options.manifest then
		assert(
			options.manifest.assetSourceSHA256 == expected.sourceSHA256
				and options.manifest.planSHA256 == expected.planSHA256,
			"Frozen source/plan hash binding required"
		)
	end
	local wild, maximumRadius, maximumTop, minimumBottom = {}, 0, -math.huge, math.huge
	local seenWild, measuredNativeMaximumRadius = 0, 0
	for i, row in wildRows do
		assert(
			type(i) == "number" and i % 1 == 0 and i >= 1 and i <= 35,
			"Dense native extent rows required"
		)
		assert(
			type(row) == "table" and type(row.id) == "string" and not wild[row.id],
			"Unique native species required"
		)
		local reference = assert(expected.wild[row.id], "Unexpected native species")
		assert(
			Math.Close(row.native.min, reference.min, 1e-6)
				and Math.Close(row.native.max, reference.max, 1e-6)
				and math.abs(row.canonicalScale - reference.scale) <= 1e-7,
			"Measured native envelope/provenance drift: " .. row.id
		)
		assert(
			Math.Close(row.groundPivot, reference.groundPivot, 1e-6),
			"Canonical ground pivot changed: " .. row.id
		)
		local radius = Math.Radius(row.native)
		assert(
			Math.Finite(row.native.rootRadialExtent)
				and row.native.rootRadialExtent > 0
				and radius + 1e-5 >= row.native.rootRadialExtent,
			"Native root-radius envelope inconsistent"
		)
		maximumRadius = math.max(maximumRadius, radius)
		maximumTop = math.max(maximumTop, row.native.max[2])
		minimumBottom = math.min(minimumBottom, row.native.min[2])
		wild[row.id] = row
		seenWild += 1
		measuredNativeMaximumRadius =
			math.max(measuredNativeMaximumRadius, row.native.rootRadialExtent)
	end
	assert(seenWild == 35, "Dense complete native species set required")
	local horizontalPadding = options.horizontalPadding or 2
	local verticalPadding = options.verticalPadding or 0.05
	assert(
		horizontalPadding >= 2
			and Math.Finite(horizontalPadding)
			and verticalPadding > 0
			and Math.Finite(verticalPadding),
		"At least 2-stud horizontal and positive vertical padding required"
	)
	local report = {
		passed = true,
		status = "NativeInstalledColliderQA",
		sourceSHA256 = expected.sourceSHA256,
		planSHA256 = expected.planSHA256,
		wildEvidenceSHA256 = expected.wildEvidenceSHA256,
		measuredSpecies = 35,
		rooms = {},
		failures = {},
		floorGapRows = {},
		floorGapWarnings = {},
		externalReservations = {},
		horizontalPadding = horizontalPadding,
		verticalPadding = verticalPadding,
		continuousTranslationChecks = 0,
		continuousYawTurnChecks = 0,
		markerFramesChecked = 0,
		colliderContractsChecked = 0,
		nativeOcclusionRays = 0,
		originalWorldWrites = 0,
		sourceWrites = 0,
		instanceWrites = 0,
		gameplayRequires = 0,
		gameplayRegistration = 0,
		renderedMeshVisibility = "NotAssessed",
		ordinaryEscapeMovement = "NotRun",
		floorContactScope = "Signed native visible-extent gaps at unchanged interface ground pivots; no pose lift or floor physics assertion",
	}
	local function check(ok, text)
		if not ok then
			report.passed = false
			table.insert(report.failures, text)
		end
	end
	local models = {}
	for _, node in layer:GetDescendants() do
		if node:IsA("Model") and node:GetAttribute("PrototypeId") == "BurrowCore" then
			local id = node:GetAttribute("EnvironmentId")
			assert(not models[id], "Duplicate installed burrow ID")
			models[id] = node
		end
	end
	local seenRooms = 0
	local globalMinimumWallGap = math.huge
	local globalDarkGap, globalHideGroundGap, globalExitGroundGap = math.huge, math.huge, math.huge
	local roiRows = {}
	for _, row in expected.rooms do
		seenRooms += 1
		local model = assert(models[row.id], "Installed planned burrow missing: " .. row.id)
		check(nearFrame(model:GetPivot(), row.rootCFrame), "Actual room root frame " .. row.id)
		local root = frame(row.rootCFrame)
		local actualMarkers, actualColliders = {}, {}
		for _, node in model:GetDescendants() do
			if node:IsA("Attachment") then
				check(
					actualMarkers[node.Name] == nil,
					"Duplicate marker " .. row.id .. "/" .. node.Name
				)
				actualMarkers[node.Name] = node
			elseif node:IsA("BasePart") and node:GetAttribute("EnvironmentRole") == "Collider" then
				local id = node:GetAttribute("EnvironmentColliderId")
				check(
					actualColliders[id] == nil,
					"Duplicate collider " .. row.id .. "/" .. tostring(id)
				)
				actualColliders[id] = node
			elseif node:IsA("MeshPart") then
				check(
					node:GetAttribute("SourceSHA256") == expected.sourceSHA256,
					"Actual source binding " .. row.id .. "/" .. node.Name
				)
			end
		end
		local paths = {}
		for _, name in expected.pathOrder do
			local node =
				assert(actualMarkers[name], "Actual marker missing: " .. row.id .. "/" .. name)
			check(
				node.Parent:IsA("MeshPart")
					and node.Parent:GetAttribute("PrototypeId") == "BurrowCore"
					and node.Parent:GetAttribute("ExportGroup") == "A",
				"Real Core A marker parent " .. row.id .. "/" .. name
			)
			check(
				nearFrame(node.WorldCFrame, row.markers[name]),
				"Exact marker world frame " .. row.id .. "/" .. name
			)
			check(
				node:GetAttribute("Art_BurrowId") == row.id
					and node:GetAttribute("Art_RuntimeRegistered") == false,
				"Inactive marker identity " .. row.id .. "/" .. name
			)
			report.markerFramesChecked += 1
			table.insert(paths, xyz(node.WorldPosition))
		end
		local colliders, nativeBoxes = {}, {}
		local actualRoofUnderside = math.huge
		for _, planned in row.colliders do
			local node =
				assert(actualColliders[planned.id], "Actual collider missing: " .. planned.id)
			check(
				node:IsA("Part")
					and node.Shape == Enum.PartType.Block
					and node.Anchored
					and node.CanCollide
					and node.CanQuery
					and not node.CanTouch
					and node.Transparency == 1,
				"Actual solid/query collider contract " .. planned.id
			)
			check(
				nearFrame(node.CFrame, planned.cframe)
					and Math.Close(xyz(node.Size), planned.size, 0.01),
				"Actual collider box drift " .. planned.id
			)
			table.insert(colliders, node)
			table.insert(nativeBoxes, { id = planned.id, box = actualBox(node) })
			report.colliderContractsChecked += 1
			if planned.id:match("Collider_[67]$") then
				local half = node.Size / 2
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							actualRoofUnderside = math.min(
								actualRoofUnderside,
								root:PointToObjectSpace(node.CFrame * (half * Vector3.new(x, y, z))).Y
							)
						end
					end
				end
			end
		end
		local count = 0
		for _ in actualColliders do
			count += 1
		end
		check(count == 7, "Exactly seven installed colliders " .. row.id)
		count = 0
		for _ in actualMarkers do
			count += 1
		end
		check(count == 4, "Exactly four installed markers " .. row.id)
		local room = {
			id = row.id,
			regionId = row.regionId,
			speciesChecked = 35,
			wallGapLowerBound = math.huge,
			headroom = math.huge,
			collisionFailures = {},
			markerLocalFrames = {},
			floorWarningSpecies = {},
		}
		for name, node in actualMarkers do
			room.markerLocalFrames[name] = array(root:ToObjectSpace(node.WorldCFrame))
		end
		check(
			Math.Close(
				xyz(root:PointToObjectSpace(actualMarkers.Art_Mouth.WorldPosition)),
				{ 0, 0.04, 0 },
				0.01
			),
			"Local mouth W/H origin " .. row.id
		)
		check(
			Math.Close(
				xyz(root:PointToObjectSpace(actualMarkers.Art_Turn.WorldPosition)),
				{ 0, 0.04, 36 },
				0.01
			),
			"Local turn L geometry " .. row.id
		)
		check(
			Math.Close(
				xyz(root:PointToObjectSpace(actualMarkers.Art_Hide.WorldPosition)),
				{ 54, 0.04, 36 },
				0.01
			),
			"Local hide chamber " .. row.id
		)
		for _, species in wildRows do
			for segment = 1, 3 do
				local a, b = paths[segment], paths[segment + 1]
				local yaw = Math.Heading(a, b)
				local body = Math.WildBox(
					Math.Frame(a, yaw),
					species.native,
					horizontalPadding,
					verticalPadding
				)
				for _, obstacle in nativeBoxes do
					local hit = Math.Sweep(body, Math.Sub(b, a), obstacle.box)
					report.continuousTranslationChecks += 1
					room.wallGapLowerBound =
						math.min(room.wallGapLowerBound, hit.wholeSweepSeparatingGap)
					if hit.intersects then
						local text = row.id
							.. "/"
							.. species.id
							.. "/segment"
							.. segment
							.. "/"
							.. obstacle.id
						check(false, "Swept padded native box intersects " .. text)
						table.insert(room.collisionFailures, text)
					end
				end
			end
			-- This square encloses the complete root-relative yaw orbit, not only
			-- sampled angles or a centred half-bounding-box radius.
			local turn = Math.TurnBox(
				array(actualMarkers.Art_Turn.WorldCFrame),
				species.native,
				horizontalPadding,
				verticalPadding
			)
			for _, obstacle in nativeBoxes do
				local hit = Math.Sweep(turn, { 0, 0, 0 }, obstacle.box)
				report.continuousYawTurnChecks += 1
				room.wallGapLowerBound =
					math.min(room.wallGapLowerBound, hit.wholeSweepSeparatingGap)
				if hit.intersects then
					check(
						false,
						"All-yaw padded turn envelope intersects "
							.. row.id
							.. "/"
							.. species.id
							.. "/"
							.. obstacle.id
					)
				end
			end
			local headroom = actualRoofUnderside - 0.04 - species.native.max[2]
			room.headroom = math.min(room.headroom, headroom)
			check(headroom >= 4, "At least four-stud headroom " .. row.id .. "/" .. species.id)
			local nativeBottom = species.native.min[2]
			local hideY = root:PointToObjectSpace(actualMarkers.Art_Hide.WorldPosition).Y
			local exitY = root:PointToObjectSpace(actualMarkers.Art_Exit.WorldPosition).Y
			local gap = hideY + nativeBottom - 0.04
			globalDarkGap = math.min(globalDarkGap, gap)
			globalHideGroundGap = math.min(globalHideGroundGap, hideY + nativeBottom)
			globalExitGroundGap = math.min(globalExitGroundGap, exitY + nativeBottom)
			local floorRow = {
				roomId = row.id,
				speciesId = species.id,
				darkFloorGap = gap,
				hideToMouthGroundGap = hideY + nativeBottom,
				exitGroundGap = exitY + nativeBottom,
				groundPivotLiftApplied = 0,
			}
			table.insert(report.floorGapRows, floorRow)
			if gap < -1e-5 then
				table.insert(room.floorWarningSpecies, species.id)
				table.insert(report.floorGapWarnings, floorRow)
			end
		end
		room.actualRoofUndersideLocalY = actualRoofUnderside
		globalMinimumWallGap = math.min(globalMinimumWallGap, room.wallGapLowerBound)
		local rays = RaycastParams.new()
		rays.FilterType = Enum.RaycastFilterType.Include
		rays.FilterDescendantsInstances = colliders
		rays.RespectCanCollide = false
		rays.IgnoreWater = true
		rays.CollisionGroup = "Default"
		local radius = maximumRadius
		local targetMin = { 54 - radius, 0.04 + minimumBottom, 36 - radius }
		local targetMax = { 54 + radius, 0.04 + maximumTop, 36 + radius }
		local roomRays, blocked = 0, 0
		for _, eye in expected.occlusionEyes do
			local worldEye = root:PointToWorldSpace(Vector3.new(table.unpack(eye)))
			for ix = 0, 2 do
				for iy = 0, 2 do
					for iz = 0, 2 do
						if ix == 1 and iy == 1 and iz == 1 then
							continue
						end
						local target = root:PointToWorldSpace(
							Vector3.new(
								targetMin[1] + (targetMax[1] - targetMin[1]) * ix / 2,
								targetMin[2] + (targetMax[2] - targetMin[2]) * iy / 2,
								targetMin[3] + (targetMax[3] - targetMin[3]) * iz / 2
							)
						)
						local result = workspace:Raycast(worldEye, target - worldEye, rays)
						roomRays += 1
						if
							result
							and result.Distance < (target - worldEye).Magnitude - 1e-4
							and result.Instance:GetAttribute("EnvironmentId") == row.id
						then
							blocked += 1
						else
							check(
								false,
								"Collider LOS sample unblocked "
									.. row.id
									.. "/view"
									.. tostring(eye[1])
									.. ","
									.. tostring(eye[2])
									.. ","
									.. tostring(eye[3])
							)
						end
					end
				end
			end
		end
		room.nativeOcclusionRays = roomRays
		room.blockedColliderRays = blocked
		report.nativeOcclusionRays += roomRays
		table.insert(report.rooms, room)
		for i, polygon in row.apronPolygons do
			table.insert(roiRows, {
				id = row.id .. "/Apron" .. i,
				kind = "BurrowApron",
				polygon = polygon,
				groundY = root.Position.Y,
			})
		end
	end
	local actualRoomCount = 0
	for _ in models do
		actualRoomCount += 1
	end
	check(actualRoomCount == 14 and seenRooms == 14, "Exactly fourteen installed planned rooms")
	for _, roi in expected.externalReservations do
		table.insert(roiRows, roi)
	end
	local overlaps = OverlapParams.new()
	overlaps.FilterType = Enum.RaycastFilterType.Exclude
	overlaps.FilterDescendantsInstances = {}
	overlaps.RespectCanCollide = false
	overlaps.CollisionGroup = "Default"
	overlaps.MaxParts = 0
	for _, roi in roiRows do
		local lowY, highY = roi.groundY + 0.001, roi.groundY + maximumTop + 4.1
		local cf, size = polygonQueryBounds(roi.polygon, lowY, highY)
		local candidates = workspace:GetPartBoundsInBox(cf, size, overlaps)
		local obstacles = {}
		for _, part in candidates do
			if part.CanQuery then
				local hit = false
				for _, cell in roi.polygon.convexCells do
					if Math.ConvexPrismIntersectsBox(cell, lowY, highY, actualBox(part), 1e-4) then
						hit = true
						break
					end
				end
				if hit then
					table.insert(obstacles, part:GetFullName())
					check(
						false,
						"Queryable native part envelope obstructs "
							.. roi.id
							.. ": "
							.. part:GetFullName()
					)
				end
			end
		end
		table.sort(obstacles)
		table.insert(report.externalReservations, {
			id = roi.id,
			kind = roi.kind,
			convexReservationCells = #roi.polygon.convexCells,
			exactPolygonArea = roi.polygon.decompositionArea,
			queryCandidates = #candidates,
			intersectingQueryableEnvelopes = obstacles,
			passed = #obstacles == 0,
		})
	end
	report.roomsChecked = #report.rooms
	report.minimumPaddedWholeSweepAxisGap = globalMinimumWallGap
	report.measuredNativePartCornerMaximumRadius = measuredNativeMaximumRadius
	report.conservativeCombinedExtentBoxRadius = maximumRadius
	report.minimumUnliftedDarkFloorGap = globalDarkGap
	report.minimumHideGroundGap = globalHideGroundGap
	report.minimumExitGroundGap = globalExitGroundGap
	report.floorVisualContactPassed = globalDarkGap >= -1e-5
	report.floorVisualContactStatus = if report.floorVisualContactPassed
		then "NoMeasuredPenetration"
		else "MeasuredBelowPivotExtentAtUnchangedMarkers_ReviewRequired"
	report.scope =
		"Continuous analytical padded-OBB translations and conservative complete-yaw turn enclosure against actual installed seven box colliders; engine CanQuery LOS samples and reservation broadphase followed by exact convex-polygon-prism/native-envelope SAT. Not rendered-pixel occlusion, actual actor navigation, avatar/cart physics or gameplay acceptance."
	report.completeBurrowGameplayAcceptance = "NotAssessed"
	return report
end
return V
