-- Stage only genuine, every-corner-verified new native road assets in ServerStorage.
-- This function does not apply geometry to Workspace or alter original templates.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local MaterialService = game:GetService("MaterialService")
local EXPECTED = HttpService:JSONDecode([====[[{"id":"Path_Arctic_2_0","localBounds":[[-156.0,0.0,-122.0],[156.0,0.0,122.0]],"pathRGB":[215,235,250],"pivot":[385.0,0.07999995164573193,-474.0],"region":"Arctic","size":[312.0,0,244.0],"triangles":33},{"id":"Path_Arctic_3_0","localBounds":[[-40.0,0.0,-61.0],[40.0,0.0,61.0]],"pathRGB":[215,235,250],"pivot":[581.0,0.07999995164573193,-535.0],"region":"Arctic","size":[80.0,0,122.0],"triangles":10},{"id":"Path_Beach_0_0","localBounds":[[-102.0,0.0,-97.3966064453125],[102.0,0.0,97.3966064453125]],"pathRGB":[224,172,83],"pivot":[-609.0,0.07999995164573193,-308.60339],"region":"Beach","size":[204.0,0,194.79322],"triangles":36},{"id":"Path_Beach_0_1","localBounds":[[-58.0,0.0,-188.93983459472656],[58.0,0.0,188.93983459472656]],"pathRGB":[224,172,83],"pivot":[-653.0,0.07999995164573193,-22.2669415],"region":"Beach","size":[116.0,0,377.879677],"triangles":50},{"id":"Path_Beach_0_2","localBounds":[[-14.0,0.0,-17.663551330566406],[14.0,0.0,17.663551330566406]],"pathRGB":[224,172,83],"pivot":[-627.0,0.07999995164573193,184.33644850000002],"region":"Beach","size":[28.0,0,35.327102999999994],"triangles":8},{"id":"Path_Camp_1_0","localBounds":[[-180.47119140625,0.0,-39.013431549072266],[180.47119140625,0.0,39.013431549072266]],"pathRGB":[232,201,138],"pivot":[-86.5288135,0.07999995164573193,-250.2202125],"region":"Camp","size":[360.942373,0,78.02686500000002],"triangles":49},{"id":"Path_Camp_1_1","localBounds":[[-186.43038940429688,0.0,-188.93983459472656],[186.43038940429688,0.0,188.93983459472656]],"pathRGB":[232,201,138],"pivot":[-75.80326300000002,0.07999995164573193,-22.2669415],"region":"Camp","size":[372.860764,0,377.879677],"triangles":203},{"id":"Path_Camp_1_2","localBounds":[[-25.63212776184082,0.0,-17.663551330566406],[25.63212776184082,0.0,17.663551330566406]],"pathRGB":[232,201,138],"pivot":[-231.849181,0.07999995164573193,184.33644850000002],"region":"Camp","size":[51.26425600000002,0,35.327102999999994],"triangles":12},{"id":"Path_Camp_2_0","localBounds":[[-54.12453079223633,0.0,-40.499412536621094],[54.12453079223633,0.0,40.499412536621094]],"pathRGB":[232,201,138],"pivot":[174.875468,0.07999995164573193,-251.70619349999998],"region":"Camp","size":[108.249064,0,80.99882699999998],"triangles":35},{"id":"Path_Camp_2_1","localBounds":[[-59.186439514160156,0.0,-188.93983459472656],[59.186439514160156,0.0,188.93983459472656]],"pathRGB":[232,201,138],"pivot":[169.8135595,0.07999995164573193,-22.2669415],"region":"Camp","size":[118.372881,0,377.879677],"triangles":87},{"id":"Path_Camp_2_2","localBounds":[[-30.3914737701416,0.0,-15.280373573303223],[30.3914737701416,0.0,15.280373573303223]],"pathRGB":[232,201,138],"pivot":[198.60852649999998,0.07999995164573193,181.953271],"region":"Camp","size":[60.78294700000001,0,30.56074799999999],"triangles":14},{"id":"Path_Forest_0_0","localBounds":[[-120.0,0.0,-97.3966064453125],[120.0,0.0,97.3966064453125]],"pathRGB":[179,119,69],"pivot":[-387.0,0.07999995164573193,-308.60339],"region":"Forest","size":[240.0,0,194.79322],"triangles":62},{"id":"Path_Forest_0_1","localBounds":[[-58.0,0.0,-188.93983459472656],[58.0,0.0,188.93983459472656]],"pathRGB":[179,119,69],"pivot":[-413.0,0.07999995164573193,-22.2669415],"region":"Forest","size":[116.0,0,377.879677],"triangles":43},{"id":"Path_Forest_0_2","localBounds":[[-12.415887832641602,0.0,-17.663551330566406],[12.415887832641602,0.0,17.663551330566406]],"pathRGB":[179,119,69],"pivot":[-387.0,0.07999995164573193,184.33644850000002],"region":"Forest","size":[24.83177599999999,0,35.327102999999994],"triangles":4},{"id":"Path_Forest_1_0","localBounds":[[-188.8135528564453,0.0,-122.0],[188.8135528564453,0.0,122.0]],"pathRGB":[179,119,69],"pivot":[-78.1864405,0.07999995164573193,-474.0],"region":"Forest","size":[377.627119,0,244.0],"triangles":59},{"id":"Path_Forest_2_0","localBounds":[[-59.186439514160156,0.0,-32.0],[59.186439514160156,0.0,32.0]],"pathRGB":[179,119,69],"pivot":[169.8135595,0.07999995164573193,-564.0],"region":"Forest","size":[118.372881,0,64.0],"triangles":14},{"id":"Path_GlitchZone_2_2","localBounds":[[-156.0,0.0,-148.0],[156.0,0.0,148.0]],"pathRGB":[55,43,68],"pivot":[385.0,0.07999995164573193,350.0],"region":"Glitch Zone","size":[312.0,0,296.0],"triangles":43},{"id":"Path_GlitchZone_3_2","localBounds":[[-46.0,0.0,-109.0],[46.0,0.0,109.0]],"pathRGB":[55,43,68],"pivot":[587.0,0.07999995164573193,369.0],"region":"Glitch Zone","size":[92.0,0,218.0],"triangles":16},{"id":"Path_Jungle_0_2","localBounds":[[-76.0,0.0,-61.0],[76.0,0.0,61.0]],"pathRGB":[194,146,71],"pivot":[-343.0,0.07999995164573193,443.0],"region":"Jungle","size":[152.0,0,122.0],"triangles":14},{"id":"Path_Jungle_1_2","localBounds":[[-188.8135528564453,0.0,-151.0],[188.8135528564453,0.0,151.0]],"pathRGB":[194,146,71],"pivot":[-78.1864405,0.07999995164573193,353.0],"region":"Jungle","size":[377.627119,0,302.0],"triangles":69},{"id":"Path_Jungle_2_2","localBounds":[[-59.186439514160156,0.0,-14.0],[59.186439514160156,0.0,14.0]],"pathRGB":[194,146,71],"pivot":[169.8135595,0.07999995164573193,292.0],"region":"Jungle","size":[118.372881,0,28.0],"triangles":10},{"id":"Path_Swamp_0_2","localBounds":[[-152.0,0.0,-141.0],[152.0,0.0,141.0]],"pathRGB":[151,112,76],"pivot":[-507.0,0.07999995164573193,343.0],"region":"Swamp","size":[304.0,0,282.0],"triangles":54},{"id":"Path_Volcano_2_0","localBounds":[[-156.0,0.0,-19.485980987548828],[156.0,0.0,19.485980987548828]],"pathRGB":[157,127,143],"pivot":[385.0,0.07999995164573193,-272.719626],"region":"Volcano","size":[312.0,0,38.97196199999999],"triangles":6},{"id":"Path_Volcano_2_1","localBounds":[[-156.0,0.0,-122.3364486694336],[156.0,0.0,122.3364486694336]],"pathRGB":[157,127,143],"pivot":[385.0,0.07999995164573193,44.3364485],"region":"Volcano","size":[312.0,0,244.672897],"triangles":35},{"id":"Path_Volcano_2_2","localBounds":[[-129.0,0.0,-17.663551330566406],[129.0,0.0,17.663551330566406]],"pathRGB":[157,127,143],"pivot":[358.0,0.07999995164573193,184.33644850000002],"region":"Volcano","size":[258.0,0,35.327102999999994],"triangles":10},{"id":"Path_Volcano_3_0","localBounds":[[-66.0,0.0,-131.3966064453125],[66.0,0.0,131.3966064453125]],"pathRGB":[157,127,143],"pivot":[607.0,0.07999995164573193,-342.60339],"region":"Volcano","size":[132.0,0,262.79322],"triangles":31},{"id":"Path_Volcano_3_1","localBounds":[[-66.0,0.0,-175.65423583984375],[66.0,0.0,175.65423583984375]],"pathRGB":[157,127,143],"pivot":[607.0,0.07999995164573193,-35.5525425],"region":"Volcano","size":[132.0,0,351.30847500000004],"triangles":40}]]====])
local SOURCE_HASH = "73c1deb0ee7abe3b758ed67ea68f57f4e4dcc42137de3e692939040961c24bdf"
local IMPORT_HASH = "bdd81be39782c1649694deecaf3264e5e82db25d9bb7ed7f783f05c1ab6fbd4e"
local GEOMETRY_HASH = "696d1821c5ebc3a595f9437366c1c777f31d6ea5f2b0f303fd8a2a895a32dbb0"
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
			and (importRoot.Name == "CompactMap_ImportedRoads" or importRoot.Name == "CompactMapRoads" and importRoot.Parent.Name == "CompactMap_ImportedAssets")
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
