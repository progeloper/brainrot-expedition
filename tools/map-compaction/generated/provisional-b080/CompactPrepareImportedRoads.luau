-- Stage only genuine, every-corner-verified new native road assets in ServerStorage.
-- This function does not apply geometry to Workspace or alter original templates.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local MaterialService = game:GetService("MaterialService")
local EXPECTED = HttpService:JSONDecode([====[[{"id":"Path_Arctic_2_0","localBounds":[[-156.0,0.0,-122.0],[156.0,0.0,122.0]],"pathRGB":[215,235,250],"pivot":[369.0,0.07999995164573193,-458.0],"region":"Arctic","size":[312.0,0,244.0],"triangles":33},{"id":"Path_Arctic_3_0","localBounds":[[-40.0,0.0,-61.0],[40.0,0.0,61.0]],"pathRGB":[215,235,250],"pivot":[565.0,0.07999995164573193,-519.0],"region":"Arctic","size":[80.0,0,122.0],"triangles":10},{"id":"Path_Beach_0_0","localBounds":[[-102.0,0.0,-94.56271362304688],[102.0,0.0,94.56271362304688]],"pathRGB":[224,172,83],"pivot":[-593.0,0.07999995164573193,-295.43728799999997],"region":"Beach","size":[204.0,0,189.125424],"triangles":36},{"id":"Path_Beach_0_1","localBounds":[[-58.0,0.0,-176.74569702148438],[58.0,0.0,176.74569702148438]],"pathRGB":[224,172,83],"pivot":[-637.0,0.07999995164573193,-24.12887699999999],"region":"Beach","size":[116.0,0,353.491398],"triangles":50},{"id":"Path_Beach_0_2","localBounds":[[-14.0,0.0,-16.69158935546875],[14.0,0.0,16.69158935546875]],"pathRGB":[224,172,83],"pivot":[-611.0,0.07999995164573193,169.308411],"region":"Beach","size":[28.0,0,33.38317799999999],"triangles":8},{"id":"Path_Camp_1_0","localBounds":[[-169.5830535888672,0.0,-36.62813186645508],[169.5830535888672,0.0,36.62813186645508]],"pathRGB":[232,201,138],"pivot":[-81.416949,0.07999995164573193,-237.50270849999998],"region":"Camp","size":[339.166102,0,73.25626499999998],"triangles":47},{"id":"Path_Camp_1_1","localBounds":[[-175.0145721435547,0.0,-176.74569702148438],[175.0145721435547,0.0,176.74569702148438]],"pathRGB":[232,201,138],"pivot":[-72.116268,0.07999995164573193,-24.12887699999999],"region":"Camp","size":[350.02914599999997,0,353.491398],"triangles":201},{"id":"Path_Camp_1_2","localBounds":[[-24.744277954101562,0.0,-16.69158935546875],[24.744277954101562,0.0,16.69158935546875]],"pathRGB":[232,201,138],"pivot":[-216.9052555,0.07999995164573193,169.308411],"region":"Camp","size":[49.48855499999999,0,33.38317799999999],"triangles":12},{"id":"Path_Camp_2_0","localBounds":[[-51.29063415527344,0.0,-37.74028015136719],[51.29063415527344,0.0,37.74028015136719]],"pathRGB":[232,201,138],"pivot":[161.709366,0.07999995164573193,-238.614858],"region":"Camp","size":[102.581268,0,75.48056400000002],"triangles":33},{"id":"Path_Camp_2_1","localBounds":[[-55.050846099853516,0.0,-176.74569702148438],[55.050846099853516,0.0,176.74569702148438]],"pathRGB":[232,201,138],"pivot":[157.9491525,0.07999995164573193,-24.12887699999999],"region":"Camp","size":[110.101695,0,353.491398],"triangles":83},{"id":"Path_Camp_2_2","localBounds":[[-29.419511795043945,0.0,-14.757009506225586],[29.419511795043945,0.0,14.757009506225586]],"pathRGB":[232,201,138],"pivot":[183.580489,0.07999995164573193,167.3738315],"region":"Camp","size":[58.839022,0,29.51401899999999],"triangles":13},{"id":"Path_Forest_0_0","localBounds":[[-120.0,0.0,-94.56271362304688],[120.0,0.0,94.56271362304688]],"pathRGB":[179,119,69],"pivot":[-371.0,0.07999995164573193,-295.43728799999997],"region":"Forest","size":[240.0,0,189.125424],"triangles":62},{"id":"Path_Forest_0_1","localBounds":[[-58.0,0.0,-176.74569702148438],[58.0,0.0,176.74569702148438]],"pathRGB":[179,119,69],"pivot":[-397.0,0.07999995164573193,-24.12887699999999],"region":"Forest","size":[116.0,0,353.491398],"triangles":43},{"id":"Path_Forest_0_2","localBounds":[[-12.172897338867188,0.0,-16.69158935546875],[12.172897338867188,0.0,16.69158935546875]],"pathRGB":[179,119,69],"pivot":[-371.0,0.07999995164573193,169.308411],"region":"Forest","size":[24.345793999999955,0,33.38317799999999],"triangles":4},{"id":"Path_Forest_1_0","localBounds":[[-176.94915771484375,0.0,-122.0],[176.94915771484375,0.0,122.0]],"pathRGB":[179,119,69],"pivot":[-74.0508475,0.07999995164573193,-458.0],"region":"Forest","size":[353.898305,0,244.0],"triangles":59},{"id":"Path_Forest_2_0","localBounds":[[-55.050846099853516,0.0,-32.0],[55.050846099853516,0.0,32.0]],"pathRGB":[179,119,69],"pivot":[157.9491525,0.07999995164573193,-548.0],"region":"Forest","size":[110.101695,0,64.0],"triangles":14},{"id":"Path_GlitchZone_2_2","localBounds":[[-156.0,0.0,-148.0],[156.0,0.0,148.0]],"pathRGB":[55,43,68],"pivot":[369.0,0.07999995164573193,334.0],"region":"Glitch Zone","size":[312.0,0,296.0],"triangles":43},{"id":"Path_GlitchZone_3_2","localBounds":[[-46.0,0.0,-109.0],[46.0,0.0,109.0]],"pathRGB":[55,43,68],"pivot":[571.0,0.07999995164573193,353.0],"region":"Glitch Zone","size":[92.0,0,218.0],"triangles":16},{"id":"Path_Jungle_0_2","localBounds":[[-76.0,0.0,-61.0],[76.0,0.0,61.0]],"pathRGB":[194,146,71],"pivot":[-327.0,0.07999995164573193,427.0],"region":"Jungle","size":[152.0,0,122.0],"triangles":14},{"id":"Path_Jungle_1_2","localBounds":[[-176.94915771484375,0.0,-151.0],[176.94915771484375,0.0,151.0]],"pathRGB":[194,146,71],"pivot":[-74.0508475,0.07999995164573193,337.0],"region":"Jungle","size":[353.898305,0,302.0],"triangles":68},{"id":"Path_Jungle_2_2","localBounds":[[-55.050846099853516,0.0,-14.0],[55.050846099853516,0.0,14.0]],"pathRGB":[194,146,71],"pivot":[157.9491525,0.07999995164573193,276.0],"region":"Jungle","size":[110.101695,0,28.0],"triangles":10},{"id":"Path_Swamp_0_2","localBounds":[[-152.0,0.0,-141.0],[152.0,0.0,141.0]],"pathRGB":[151,112,76],"pivot":[-491.0,0.07999995164573193,327.0],"region":"Swamp","size":[304.0,0,282.0],"triangles":54},{"id":"Path_Volcano_2_0","localBounds":[[-156.0,0.0,-19.112150192260742],[156.0,0.0,19.112150192260742]],"pathRGB":[157,127,143],"pivot":[369.0,0.07999995164573193,-257.2429905],"region":"Volcano","size":[312.0,0,38.224299],"triangles":6},{"id":"Path_Volcano_2_1","localBounds":[[-156.0,0.0,-115.30841064453125],[156.0,0.0,115.30841064453125]],"pathRGB":[157,127,143],"pivot":[369.0,0.07999995164573193,37.30841100000001],"region":"Volcano","size":[312.0,0,230.616822],"triangles":30},{"id":"Path_Volcano_2_2","localBounds":[[-129.0,0.0,-16.69158935546875],[129.0,0.0,16.69158935546875]],"pathRGB":[157,127,143],"pivot":[342.0,0.07999995164573193,169.308411],"region":"Volcano","size":[258.0,0,33.38317799999999],"triangles":10},{"id":"Path_Volcano_3_0","localBounds":[[-66.0,0.0,-128.56271362304688],[66.0,0.0,128.56271362304688]],"pathRGB":[157,127,143],"pivot":[591.0,0.07999995164573193,-329.43728799999997],"region":"Volcano","size":[132.0,0,257.125424],"triangles":31},{"id":"Path_Volcano_3_1","localBounds":[[-66.0,0.0,-164.99661254882812],[66.0,0.0,164.99661254882812]],"pathRGB":[157,127,143],"pivot":[591.0,0.07999995164573193,-35.877966],"region":"Volcano","size":[132.0,0,329.99321999999995],"triangles":40}]]====])
local SOURCE_HASH = "a9520966d90b9955285786839991af17486cc53e09012e98589d64a6fd6670c3"
local IMPORT_HASH = "352ec7d09d9884a4ecc8c98fbe10006d4bbd770c2d6104ffa0a5eb3f254a87b1"
local GEOMETRY_HASH = "8b52d62328fdba429c4124e911b2a59e95550f3682ec37c95c8db782a08dd484"
local ROUTE_HASH = "7c0411ac82bd863df409dcf71ebc49f6649564dcb30aa2a6a9e6e59408dd20a5"
local OWNER = "BrainrotExpedition_MapArt"
local MIGRATION = "CompactMap_V1"
local SAVED = "Bingus_Saved_Studs_13719188279"
local function asset(value)
	local id = tostring(value):match("^rbxassetid://([1-9]%d*)$")
	assert(id, "Expected genuine native numeric asset URI")
	return id
end
local function vec(v)
	return Vector3.new(v[1], v[2], v[3])
end
local function frameNear(a, b)
	local x, y = { a:GetComponents() }, { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(x[i] - y[i]) > 1e-5 then
			return false
		end
	end
	return true
end
local function attrs(instance)
	return instance:GetAttributes()
end
local function restoreAttrs(instance, old)
	for k in pairs(instance:GetAttributes()) do
		if old[k] == nil then
			instance:SetAttribute(k, nil)
		end
	end
	for k, v in pairs(old) do
		instance:SetAttribute(k, v)
	end
end
local function matches(part, row, meshId)
	if not part:IsA("MeshPart") or tostring(part.MeshId) ~= meshId or part.TextureID ~= "" then
		return false
	end
	if
		(part.Size - Vector3.new(row.size[1], 0.05, row.size[3])).Magnitude > 1e-5
		or not frameNear(part.CFrame, CFrame.new(vec(row.pivot)))
		or not frameNear(part.PivotOffset, CFrame.identity)
	then
		return false
	end
	if
		part.Material ~= Enum.Material.Glacier
		or part.MaterialVariant ~= SAVED
		or part.Color ~= Color3.fromRGB(unpack(row.pathRGB))
		or not part.Anchored
		or part.CanCollide
		or part.CanQuery
		or part.CanTouch
		or part.CastShadow
		or part.DoubleSided
		or part.Transparency ~= 0
		or part.Reflectance ~= 0
		or part.RenderFidelity ~= Enum.RenderFidelity.Automatic
		or #part:GetChildren() ~= 0
	then
		return false
	end
	local expected = {
		ArtOwner = OWNER,
		ArtVersion = 2,
		ArtRole = "Path",
		PlacementId = row.id,
		ExportGroup = row.id,
		Region = row.region,
		RouteHash = ROUTE_HASH,
		CompactMigrationId = MIGRATION,
		CompactGeometryHash = GEOMETRY_HASH,
		SourceTriangles = row.triangles,
		SurfaceStyle = "SavedBingusStuds",
		StudsPerTile = 0.25,
		StudMaterialAssetId = 13719188279,
	}
	for k, v in pairs(expected) do
		if part:GetAttribute(k) ~= v then
			return false
		end
	end
	return true
end
local function Prepare(importRoot, evidence, options)
	options = options or {}
	assert(
		not RunService:IsRunning() and game.PlaceId == 91958083796436,
		"Prepare compact roads in authorized DEV Edit only"
	)
	assert(
		typeof(importRoot) == "Instance"
			and importRoot.Name == "CompactMap_ImportedRoads"
			and importRoot:IsDescendantOf(ServerStorage),
		"Supply owned native import under ServerStorage.CompactMap_ImportedRoads"
	)
	assert(
		type(evidence) == "table"
			and evidence.status == "Passed"
			and evidence.completeBatch == true
			and #evidence.failures == 0,
		"Complete actual native evidence required"
	)
	assert(
		evidence.canonicalSourceSHA256 == SOURCE_HASH
			and evidence.studioImportSHA256 == IMPORT_HASH
			and evidence.routeGeometryHash == GEOMETRY_HASH,
		"Native evidence hashes differ from compact source"
	)
	assert(
		evidence.checkedGroups == #EXPECTED and #evidence.groups == #EXPECTED,
		"Actual evidence must cover every group exactly once"
	)
	local material = MaterialService:FindFirstChild(SAVED)
	assert(
		material
			and material:IsA("MaterialVariant")
			and material.BaseMaterial == Enum.Material.Glacier
			and math.abs(material.StudsPerTile - 0.25) < 1e-6,
		"Accepted saved-stud material is missing/different"
	)
	assert(
		asset(material.ColorMap) == "10509831729" and asset(material.NormalMap) == "10509831753",
		"Saved-stud image identity changed"
	)
	local found, proof = {}, {} -- Source scans and every proof are validated before mutation.
	for _, part in ipairs(importRoot:GetDescendants()) do
		if part:IsA("MeshPart") then
			assert(not found[part.Name], "Duplicate imported group")
			found[part.Name] = part
		elseif
			part:IsA("LuaSourceContainer")
			or part:IsA("Attachment")
			or part:IsA("Constraint")
		then
			error("Unexpected functional import descendant")
		end
	end
	for _, row in ipairs(evidence.groups) do
		assert(not proof[row.id], "Duplicate native evidence")
		proof[row.id] = row
	end
	local plans, names, totalCorners = {}, {}, 0
	for _, row in ipairs(EXPECTED) do
		names[row.id] = true
		local native = assert(found[row.id], "Native group absent: " .. row.id)
		local p = assert(proof[row.id], "Proof group absent")
		local id = tostring(native.MeshId)
		asset(id)
		assert(
			p.passed
				and p.geometryCornersComplete
				and p.sourceUVValuesPassed
				and p.upwardNormalsPassed
				and p.upwardWindingPassed,
			"Incomplete corner/UV/normal/winding evidence"
		)
		assert(
			p.meshId == id
				and p.expectedTriangles == row.triangles
				and p.actualTriangles == row.triangles
				and p.geometryCornersMatched == row.triangles * 3,
			"Evidence counts/real mesh identity differ"
		)
		assert(
			p.maximumPositionError <= 0.01
				and p.maximumUVError <= 1e-5
				and p.maximumNormalError <= 1e-5,
			"Native corner tolerance failed"
		)
		assert(
			native.Archivable
				and math.abs(native.Size.X - row.size[1]) <= 0.01
				and math.abs(native.Size.Z - row.size[3]) <= 0.01,
			"Native bounds cannot become expected template"
		)
		assert(
			native.Size.Y > 0
				and native.Size.Y <= 0.05001
				and (
					math.abs(native.Size.Y - 0.001) < 1e-5 or math.abs(native.Size.Y - 0.05) < 1e-5
				),
			"Unexpected native planar clamp"
		)
		for _, child in ipairs(native:GetChildren()) do
			assert(
				child:IsA("SurfaceAppearance") and #child:GetChildren() == 0,
				"Unowned native descendant"
			)
		end
		totalCorners += row.triangles * 3
		table.insert(plans, { row = row, native = native, id = id })
	end
	assert(totalCorners == evidence.checkedTriangleCorners, "Complete native corner total differs")
	for name in pairs(found) do
		assert(names[name], "Unexpected native group")
	end
	local destination = ServerStorage:FindFirstChild("CompactMapRoadTemplates")
	if destination then
		assert(
			destination:IsA("Folder")
				and destination:GetAttribute("ArtOwner") == OWNER
				and destination:GetAttribute("CompactMigrationId") == MIGRATION,
			"Preserve unrelated existing templates"
		)
		local prior = destination:GetAttribute("CompactGeometryHash")
		assert(
			prior == GEOMETRY_HASH or options.ReplacePreparedGeometryHash == prior,
			"Explicit prior geometry hash required to replace another candidate"
		)
		local seen = {}
		for _, child in ipairs(destination:GetChildren()) do
			assert(
				not seen[child.Name]
					and names[child.Name]
					and child:IsA("MeshPart")
					and child:GetAttribute("ArtOwner") == OWNER,
				"Duplicate/unknown/unowned existing template"
			)
			seen[child.Name] = true
		end
	end
	local staged = Instance.new("Folder")
	staged.Name = "CompactMapRoadStaging"
	local backups = Instance.new("Folder")
	backups.Name = "CompactMapRoadPreparationRollback"
	local inserted, moved = {}, {}
	local created = false
	local priorAttrs = destination and attrs(destination)
	local report = {
		status = "Passed",
		worldMutations = 0,
		created = 0,
		updated = 0,
		retained = 0,
		sourceSHA256 = SOURCE_HASH,
		studioImportSHA256 = IMPORT_HASH,
		routeGeometryHash = GEOMETRY_HASH,
		checkedNativeTriangleCorners = totalCorners,
		groups = {},
	}
	local ok, result = xpcall(function()
		for _, plan in ipairs(plans) do
			local row = plan.row
			local old = destination and destination:FindFirstChild(row.id)
			plan.old = old
			if old and matches(old, row, plan.id) then
				report.retained += 1
			else
				local part = plan.native:Clone()
				part.Parent = staged
				part.Name = row.id
				for _, child in ipairs(part:GetChildren()) do
					child:Destroy()
				end
				part.Size = Vector3.new(row.size[1], 0.05, row.size[3])
				part.CFrame = CFrame.new(vec(row.pivot))
				part.PivotOffset = CFrame.identity
				part.Material = Enum.Material.Glacier
				part.MaterialVariant = SAVED
				part.Color = Color3.fromRGB(unpack(row.pathRGB))
				part.TextureID = ""
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.DoubleSided = false
				part.RenderFidelity = Enum.RenderFidelity.Automatic
				part.Transparency = 0
				part.Reflectance = 0
				local settings = {
					ArtOwner = OWNER,
					ArtVersion = 2,
					ArtRole = "Path",
					PlacementId = row.id,
					ExportGroup = row.id,
					Region = row.region,
					RouteHash = ROUTE_HASH,
					CompactMigrationId = MIGRATION,
					CompactGeometryHash = GEOMETRY_HASH,
					SourceTriangles = row.triangles,
					SurfaceStyle = "SavedBingusStuds",
					StudsPerTile = 0.25,
					StudMaterialAssetId = 13719188279,
				}
				for k, v in pairs(settings) do
					part:SetAttribute(k, v)
				end
				assert(matches(part, row, plan.id), "Detached template readback failed")
				plan.staged = part
				if old then
					report.updated += 1
				else
					report.created += 1
				end
			end
			table.insert(
				report.groups,
				{
					id = row.id,
					meshId = plan.id,
					pivot = row.pivot,
					size = { row.size[1], 0.05, row.size[3] },
					triangles = row.triangles,
					region = row.region,
					pathRGB = row.pathRGB,
				}
			)
		end
		if not destination then
			destination = Instance.new("Folder")
			destination.Name = "CompactMapRoadTemplates"
			created = true
			destination.Parent = ServerStorage
		end
		for _, plan in ipairs(plans) do
			if plan.staged then
				if plan.old then
					table.insert(moved, plan.old)
					plan.old.Parent = backups
				end
				table.insert(inserted, plan.staged)
				plan.staged.Parent = destination
			end
		end
		destination:SetAttribute("ArtOwner", OWNER)
		destination:SetAttribute("CompactMigrationId", MIGRATION)
		destination:SetAttribute("CompactGeometryHash", GEOMETRY_HASH)
		destination:SetAttribute("RouteHash", ROUTE_HASH)
		destination:SetAttribute("CanonicalSourceSHA256", SOURCE_HASH)
		destination:SetAttribute("StudioImportSHA256", IMPORT_HASH)
		for _, plan in ipairs(plans) do
			assert(
				matches(destination:FindFirstChild(plan.row.id), plan.row, plan.id),
				"Committed template readback failed"
			)
		end
		report.destination = destination:GetFullName()
		return report
	end, debug.traceback)
	if not ok then
		local restoreErrors = {}
		for _, part in ipairs(inserted) do
			local pass, err = pcall(function()
				part.Parent = staged
			end)
			if not pass then
				table.insert(restoreErrors, tostring(err))
			end
		end
		for _, part in ipairs(moved) do
			local pass, err = pcall(function()
				part.Parent = destination
			end)
			if not pass then
				table.insert(restoreErrors, tostring(err))
			end
		end
		if created and destination then
			destination:Destroy()
		elseif destination then
			local pass, err = pcall(restoreAttrs, destination, priorAttrs)
			if not pass then
				table.insert(restoreErrors, tostring(err))
			end
		end
		if #restoreErrors == 0 then
			staged:Destroy()
			backups:Destroy()
		else
			staged.Parent = ServerStorage
			backups.Parent = ServerStorage
		end
		error(
			tostring(result)
				.. (
					#restoreErrors > 0
						and "\nRollback errors: " .. table.concat(restoreErrors, "\n")
					or ""
				),
			0
		)
	end
	staged:Destroy()
	backups:Destroy()
	return result
end
return Prepare
