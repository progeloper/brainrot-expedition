--!nocheck
-- Detached read-only DEV Edit verifier. It never starts gameplay, requires gameplay owners, or writes Instances.
local V = {}
local OWNER = "BR_EnvironmentArt_V2"
local VARIANT = "Bingus_Saved_Studs_13719188279"
local LIMITS = {
	visible = 384,
	colliders = 360,
	baseParts = 750,
	instances = 1500,
	triangles = 40000,
	meshIds = 36,
	scenery = 133,
	trees = 36,
	motifs = 4,
}
local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
function V.PaletteRGB(spec, row)
	local channels = spec.colorRGB
		or spec.color
		or (row and row.palette and row.palette[spec.exportGroup or spec.groupId])
	assert(type(channels) == "table" and #channels == 3, "Exact frozen RGB bytes required")
	local count = 0
	for key, channel in channels do
		assert(
			type(key) == "number"
				and key % 1 == 0
				and key >= 1
				and key <= 3
				and finite(channel)
				and channel % 1 == 0
				and channel >= 0
				and channel <= 255,
			"Only three finite integer RGB bytes are allowed"
		)
		count += 1
	end
	assert(count == 3, "Dense RGB array required")
	if spec.colorRGB and spec.color then
		for i = 1, 3 do
			assert(spec.colorRGB[i] == spec.color[i], "Conflicting color aliases")
		end
	end
	return channels
end
function V.BoundaryTarget(actual)
	assert(finite(actual) and actual % 1 == 0 and actual >= 0, "Finite whole boundary module count required")
	return { target = 64, actual = actual, met = actual <= 64, status = if actual <= 64 then "Met" else "NotMet" }
end
function V.ValidateTriangleException(actual, exception)
	assert(
		type(exception) == "table"
			and exception.originalLimit == 40000
			and exception.maximumApprovedActual == 44000
			and exception.sourceProjectedTriangles == 43558
			and exception.actualInstalledTriangles == actual
			and actual == exception.sourceProjectedTriangles
			and actual > 40000
			and actual <= 44000
			and exception.sourceSHA256 == "f9e940205f6c35805cff5674ef0079347090d4a8a431b02dbef457b3aba05dec"
			and exception.baselineSceneSHA256 == "f396b10caf4d1ab7e6b9aa8dd61fcab89bc904f33d95c899de887ac9950089e9"
			and exception.basis == "CurrentUserBrickDirective"
			and type(exception.reason) == "string"
			and #exception.reason > 0,
		"Only the exact selected current-source brick composition exception may exceed40000; native count must agree"
	)
	return true
end
function V.ValidateCounts(counts, unplacedMandatory, triangleBudgetException)
	V.BoundaryTarget(counts.boundary)
	for name, limit in LIMITS do
		assert(
			finite(counts[name]) and counts[name] % 1 == 0 and counts[name] >= 0,
			"Environment cost must be a finite nonnegative integer: " .. name
		)
		if name == "triangles" and triangleBudgetException then
			V.ValidateTriangleException(counts.triangles, triangleBudgetException)
		else
			assert(counts[name] <= limit, "Environment budget " .. name .. " exceeds " .. limit)
		end
	end
	assert(counts.visible + counts.colliders == counts.baseParts, "Every new Part must have exactly one audited role")
	local missing = unplacedMandatory or {}
	assert(type(missing) == "table" and #missing <= 1, "Only the explicit Bible Camp fit conflict may remain unplaced")
	local missingKeys = 0
	for key in missing do
		assert(
			type(key) == "number" and key % 1 == 0 and key >= 1 and key <= #missing,
			"Dense explicit omission array required"
		)
		missingKeys += 1
	end
	assert(missingKeys == #missing, "Dense explicit omission array required")
	if #missing == 1 then
		local item = missing[1]
		local evidence = item.evidence
		assert(
			item.role == "Burrow"
				and item.prototypeId == "BurrowCore"
				and item.regionId == "REGION_CAMP"
				and type(item.id) == "string"
				and #item.id > 0
				and type(item.reason) == "string"
				and #item.reason > 0,
			"Exact documented Camp burrow conflict required"
		)
		assert(
			type(evidence) == "table"
				and evidence.status == "NoFitAfterFullDeterministicSearch"
				and type(evidence.baselineSceneSHA256) == "string"
				and evidence.baselineSceneSHA256:match("^[0-9a-f]+$") ~= nil
				and #evidence.baselineSceneSHA256 == 64
				and type(evidence.assetSourceSHA256) == "string"
				and evidence.assetSourceSHA256:match("^[0-9a-f]+$") ~= nil
				and #evidence.assetSourceSHA256 == 64
				and evidence.minimumBoundaryDepthTested == 8
				and evidence.allCardinalYawsTested == true
				and evidence.gridStepStuds == 4
				and evidence.exactProjectionTested == true
				and finite(evidence.candidatesEvaluated)
				and evidence.candidatesEvaluated > 0
				and evidence.candidatesEvaluated % 1 == 0,
			"Actual full Camp no-fit evidence required; no guessed omission"
		)
	end
	assert(
		counts.burrows == 15 - #missing and counts.heroes == 8,
		"All placed burrows/hero slots required except exact documented Camp conflict"
	)
	return true
end
local function dense(rows, maximum, label)
	assert(type(rows) == "table", label .. " array required")
	local count = 0
	for k in rows do
		assert(type(k) == "number" and k % 1 == 0 and k >= 1 and k <= maximum, label .. " invalid dense key")
		count += 1
	end
	assert(count == #rows, label .. " sparse array")
	return rows
end
local function report()
	return {
		schemaVersion = 2,
		owner = OWNER,
		checks = 0,
		failures = {},
		failed = 0,
		worldWrites = 0,
		sourceWrites = 0,
		gameplayRequires = 0,
	}
end
local function check(r, condition, message)
	r.checks += 1
	if not condition then
		r.failed += 1
		if #r.failures < 200 then
			table.insert(r.failures, message)
		end
	end
	return condition
end
local function finish(r)
	r.passed = r.failed == 0
	r.failureListTruncated = r.failed > #r.failures
	r.status = if r.passed then "Passed" else "Failed"
	return r
end
local function frame(a)
	assert(type(a) == "table" and #a == 12, "Full CFrame array required")
	return CFrame.new(table.unpack(a))
end
local function vector(a)
	assert(type(a) == "table" and #a == 3, "Full size array required")
	return Vector3.new(table.unpack(a))
end
local function bounds(cf, size)
	local e = Vector3.new(
		math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z,
		math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z,
		math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z
	) / 2
	local lo, hi = cf.Position - e, cf.Position + e
	return { minX = lo.X, maxX = hi.X, minY = lo.Y, maxY = hi.Y, minZ = lo.Z, maxZ = hi.Z }
end
-- Only the two actual ordinary-view occlusion corrections approved for this frozen
-- environment may change original sign orientation/tangent. Original sign/GUI data
-- remains protected by Preserve; these are owned presentation poses only.
local SIGN_CORRECTIONS = {
	VolcanoSouthCampFace_v2 = {
		owner = "Gate_Volcano_Header_01",
		child = "Gate_Volcano_SignFaceProxy",
		originalSignPath = "Workspace.MapBlockout.ProgressionGates.Volcano.Sign",
		cframe = { 197, 22.549999237060547, -243.9588746257614, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
		viewpoint = { 205, 7, -225 },
	},
	JungleAdjacentWallEdgeClearance_v2 = {
		owner = "Gate_Jungle_Header_01",
		child = "Gate_Jungle_SignFaceProxy",
		originalSignPath = "Workspace.MapBlockout.ProgressionGates.Jungle.Sign",
		cframe = { -242.733642578125, 22.549999237060547, 153.9, -1, 0, 0, 0, 1, 0, 0, 0, -1 },
		viewpoint = { -242.733642578125, 7, 117.9 },
	},
}
local function finiteArrayNear(actual, expected, tolerance)
	if type(actual) ~= "table" or #actual ~= #expected then
		return false
	end
	local count = 0
	for key, n in actual do
		if
			type(key) ~= "number"
			or key % 1 ~= 0
			or key < 1
			or key > #expected
			or not finite(n)
			or math.abs(n - expected[key]) > tolerance
		then
			return false
		end
		count += 1
	end
	return count == #expected
end
function V.SignPresentationCorrection(proxy, row)
	local evidence = proxy.clearanceEvidence or {}
	local name = proxy.presentationOverride or evidence.presentationOverride
	if not name then
		return nil
	end
	local correction =
		assert(SIGN_CORRECTIONS[name], "Only two exact reviewed sign presentation corrections are permitted")
	assert(
		row.id == correction.owner
			and proxy.id == correction.child
			and proxy.originalSignPath == correction.originalSignPath
			and proxy.sourceContractSHA256 == "ee0fac1b3cbbfa848181ecfa6997d0ba1dc0ab7091a6e778513b24ce41a55846"
			and finiteArrayNear(proxy.cframe, correction.cframe, 1e-6)
			and finiteArrayNear(evidence.legalViewpoint, correction.viewpoint, 1e-6),
		"Sign presentation correction must bind the exact approved owner, pose and legal viewpoint"
	)
	return correction
end
-- Read-only closed segment/OBB slab test. Frame and size arrays are measured from
-- actual installed primitive colliders, never only from success metadata.
function V.SignSegmentIntersectsBox(startPoint, endPoint, boxFrame, boxSize, tolerance)
	tolerance = tolerance or 1e-5
	assert(finite(tolerance) and tolerance >= 0, "Finite nonnegative sign LOS tolerance")
	for _, data in { { startPoint, 3 }, { endPoint, 3 }, { boxFrame, 12 }, { boxSize, 3 } } do
		assert(type(data[1]) == "table" and #data[1] == data[2], "Dense sign LOS geometry array required")
		for _, value in data[1] do
			assert(finite(value), "Finite sign LOS geometry required")
		end
	end
	local deltaStart = { startPoint[1] - boxFrame[1], startPoint[2] - boxFrame[2], startPoint[3] - boxFrame[3] }
	local deltaEnd = { endPoint[1] - boxFrame[1], endPoint[2] - boxFrame[2], endPoint[3] - boxFrame[3] }
	local enter, leave = 0, 1
	for axis = 1, 3 do
		local x, y, z = boxFrame[axis + 3], boxFrame[axis + 6], boxFrame[axis + 9]
		local a = deltaStart[1] * x + deltaStart[2] * y + deltaStart[3] * z
		local b = deltaEnd[1] * x + deltaEnd[2] * y + deltaEnd[3] * z
		assert(boxSize[axis] > 0, "Positive native collider size required")
		local half = boxSize[axis] / 2 - tolerance
		if half <= 0 then
			return false
		end
		local movement = b - a
		if math.abs(movement) <= 1e-12 then
			if math.abs(a) >= half then
				return false
			end
		else
			local lo, hi = (-half - a) / movement, (half - a) / movement
			if lo > hi then
				lo, hi = hi, lo
			end
			enter, leave = math.max(enter, lo), math.min(leave, hi)
			if enter > leave then
				return false
			end
		end
	end
	return leave >= 0 and enter <= 1
end
function V.ResolveOwnedInstance(value, root)
	assert(
		type(value) == "table" and value.type == "OwnedInstance" and root,
		"Exact owned-instance delta and layer root required"
	)
	local target
	for _, node in root:GetDescendants() do
		if
			node.Name == value.ownedChildId
			and node:IsA("Part")
			and node:GetAttribute("EnvironmentId") == value.ownerRowId
		then
			assert(not target, "Ambiguous owned sign face")
			target = node
		end
	end
	assert(
		target
			and target:GetAttribute("ArtOwner") == OWNER
			and target:GetAttribute("EnvironmentRole") == "VisibleSignFace"
			and target.Parent:IsA("Model")
			and target.Parent:GetAttribute("EnvironmentId") == value.ownerRowId,
		"Controlled six sign-face target missing"
	)
	return target
end
function V.Preserve(options)
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"Preservation API requires DEV Edit"
	)
	local Audit = assert(options.auditAPI, "Pass detached exact Audit API")
	local context = options.baseline or assert(shared.EnvironmentV2Baseline, "Fresh baseline missing")
	local r = report()
	local inverse = {}
	for key, node in context.refs do
		inverse[node] = key
	end
	local fallbackKey = select(1, Audit.KeyFactory())
	local key = function(node)
		return inverse[node] or fallbackKey(node)
	end
	local byKey = {}
	for _, row in context.manifest.records do
		byKey[row.key] = row
	end
	local archives = {}
	local manifest = assert(options.manifest, "Reviewed final manifest required")
	local archiveRows = {}
	for _, item in manifest.archive or {} do
		table.insert(archiveRows, item)
	end
	for _, item in manifest.boundaryArchive or {} do
		table.insert(archiveRows, item)
	end
	check(
		r,
		context.sceneSHA256 ~= nil and manifest.baselineSceneSHA256 == context.sceneSHA256,
		"Exact fresh scene SHA binding"
	)
	for _, item in archiveRows do
		local row = byKey[item.originalKey]
		local node = row and context.refs[row.key]
		assert(row and row.scope == "Map" and not archives[row.key], "Unknown/duplicate/protected archive key")
		local oldArt = row.path:sub(1, #"Workspace.MapBlockout.MapArt.Scenery.")
				== "Workspace.MapBlockout.MapArt.Scenery."
			or row.path:sub(1, #"Workspace.MapBlockout.MapArt.Backdrops.")
				== "Workspace.MapBlockout.MapArt.Backdrops."
		local oldWall = row.path == "Workspace.MapBlockout.RegionWalls"
			or row.path:find("Workspace.MapBlockout.RegionWalls.", 1, true) == 1
			or (
				row.class == "Part"
				and row.name:match("^BoulderWall_")
				and row.attributes.ManagedBy == "Phase8Perimeter_v1"
			)
		assert(oldArt or oldWall, "Archive scope cannot include floor/road/base/service/gate functional geometry")
		assert(
			type(item.reason) == "string"
				and #item.reason > 0
				and type(item.oldOwner) == "string"
				and #item.oldOwner > 0,
			"Explicit reviewed archive ownership/reason required"
		)
		local parent = if options.archiveParents then options.archiveParents[row.key] else options.archiveParent
		assert(
			parent
				and parent:IsDescendantOf(game:GetService("ServerStorage"))
				and parent:GetAttribute("ArtOwner") == OWNER
				and parent:GetAttribute("NoRuntimeUse") == true,
			"Exact owned off-world archive destination required"
		)
		archives[row.key] = parent
		if not options.validateChangesOnly then
			check(
				r,
				node.Parent == parent and not node:IsDescendantOf(workspace),
				"Archived original is outside active world: " .. row.path
			)
		end
	end
	local signProxies, signProxyCount = {}, 0
	for _, object in manifest.objects or {} do
		local proxy = object.signFaceProxy
		if proxy then
			local binding = proxy.adorneeChange and (proxy.adorneeChange.newValue or proxy.adorneeChange)
			local gui, sign = byKey[proxy.originalGuiKey], byKey[proxy.originalSignKey]
			assert(
				gui
					and gui.scope == "Map"
					and gui.class == "SurfaceGui"
					and gui.name == "GateSign"
					and gui.path:match("^Workspace%.MapBlockout%.ProgressionGates%.[^%.]+%.Sign%.GateSign$")
					and sign
					and sign.class == "Part"
					and sign.name == "Sign"
					and gui.parent == sign.key
					and object.role == "Boundary"
					and object.boundaryKind == "GateLintel"
					and proxy.sourceRole == "SignFace"
					and not signProxies[gui.key],
				"Only exact six original paid-gate SurfaceGui bindings may use owned faces"
			)
			assert(
				binding
					and binding.type == "OwnedInstance"
					and binding.ownerRowId == object.id
					and binding.ownedChildId == proxy.id,
				"Proxy binding must name its exact owner row/child"
			)
			signProxies[gui.key] = proxy
			signProxyCount += 1
		end
	end
	assert(signProxyCount == 0 or signProxyCount == 6, "All six paid-sign bindings must be explicit")
	local propertyChanges = options.propertyChanges or {}
	local attributeChanges = options.attributeChanges or {}
	local permittedValues = {
		["Workspace.MapBlockout.CompactMapRuntimeGeometry"] = true,
		["Workspace.MapBlockout.MapArt.InstalledFootprints"] = true,
	}
	for originalKey, changes in propertyChanges do
		local row = assert(byKey[originalKey], "Unknown property exception")
		if row.class == "SurfaceGui" and signProxies[originalKey] then
			for name, value in changes do
				assert(
					name == "Adornee"
						and Audit.Equal(
							value,
							signProxies[originalKey].adorneeChange.newValue or signProxies[originalKey].adorneeChange,
							0
						),
					"Only exact controlled original SurfaceGui.Adornee may change"
				)
			end
		elseif row.class == "StringValue" and permittedValues[row.path] then
			for name, value in changes do
				assert(
					name == "Value" and type(value) == "string" and #value <= 200000,
					"Exact bounded Value exception only"
				)
			end
		else
			local floor = row.class == "Part"
				and row.scope == "Map"
				and row.attributes.LayoutRole == "Floor"
				and row.attributes.GeneratedBy == "CreateBasicMap_v1"
				and row.name:match("^Floor_R%d_C%d$")
			local road = row.class == "MeshPart"
				and row.path:find("Workspace.MapBlockout.Paths.StyledSurfaces.", 1, true) == 1
				and row.name:match("^Path_")
			assert(
				options.allowBibleAlbedoEdits == true and (floor or road),
				"Only opted-in exact existing25 floor/27 decorative road colors may change"
			)
			for name, value in changes do
				assert(
					name == "Color" and type(value) == "table" and value.type == "Color3" and #value.value == 3,
					"Exact typed albedo exception only"
				)
				for _, channel in value.value do
					assert(finite(channel) and channel >= 0 and channel <= 1, "Finite RGB albedo")
				end
			end
		end
	end
	local Http = game:GetService("HttpService")
	for originalKey, changes in propertyChanges do
		local row = byKey[originalKey]
		if row.class == "StringValue" then
			local old = Http:JSONDecode(row.properties.Value)
			local new = Http:JSONDecode(changes.Value)
			if row.name == "CompactMapRuntimeGeometry" then
				for name, value in old do
					if name ~= "staticWallObstacles" then
						check(r, Audit.Equal(new[name], value, 0), "Canonical owner field preserved: " .. name)
					end
				end
				for name in new do
					check(
						r,
						name == "staticWallObstacles" or old[name] ~= nil,
						"No unrelated runtime owner fields added: " .. name
					)
				end
				local ids = {}
				for _, wall in dense(new.staticWallObstacles, 512, "Canonical collider masks") do
					check(
						r,
						type(wall.id) == "string" and #wall.id > 0 and #wall.id <= 128 and not ids[wall.id],
						"Bounded unique mask ID"
					)
					ids[wall.id] = true
					for _, axis in { "X", "Y", "Z" } do
						check(
							r,
							finite(wall["min" .. axis])
								and finite(wall["max" .. axis])
								and wall["min" .. axis] < wall["max" .. axis],
							"Positive finite mask bounds"
						)
					end
				end
			else
				local oldById, regions, archivedIds = {}, {}, {}
				for _, item in archiveRows do
					local archived = byKey[item.originalKey]
					if archived then
						archivedIds[archived.name] = true
					end
				end
				for _, footprint in dense(old, 345, "Original art footprints") do
					oldById[footprint.id] = footprint
					regions[footprint.regionId] = true
				end
				local ids = {}
				for _, footprint in dense(new, 345, "Updated art footprints") do
					check(
						r,
						type(footprint.id) == "string"
							and #footprint.id > 0
							and #footprint.id <= 128
							and not ids[footprint.id]
							and regions[footprint.regionId],
						"Bounded unique canonical footprint"
					)
					ids[footprint.id] = footprint
					check(
						r,
						finite(footprint.minX)
							and finite(footprint.maxX)
							and finite(footprint.minZ)
							and finite(footprint.maxZ)
							and footprint.minX < footprint.maxX
							and footprint.minZ < footprint.maxZ,
						"Positive finite footprint bounds"
					)
				end
				-- Camp Rework (12 Nov 2026): the kiosk footprints moved with the new seeded camp layout
				-- (Config/CampLayout); the Kit kiosk was removed. Only the twelve base shells stay fixed.
				local campRework = workspace.MapBlockout.MapArt:FindFirstChild("Services") ~= nil
					and workspace.MapBlockout.MapArt.Services:FindFirstChild("Kiosk_SellStall") ~= nil
					and workspace.MapBlockout.MapArt.Services.Kiosk_SellStall:GetAttribute("CampReworkStall") ~= nil
				local protectedCount = 0
				for id, footprint in oldById do
					local fixed = id:match("^Showhouse_Base_%d%d$") or (not campRework and id:match("^Kiosk_"))
					if fixed then
						protectedCount += 1
					end
					if fixed or (not archivedIds[id] and not (campRework and id:match("^Kiosk_"))) then
						check(
							r,
							Audit.Equal(ids[id], footprint, 0),
							"Unarchived/base/service footprint retained exactly: " .. id
						)
					end
				end
				check(r, protectedCount == (if campRework then 12 else 18),
					"All twelve shell (and, before Camp Rework, six service) canonical footprint rows preserved")
			end
		end
	end
	for originalKey, changes in attributeChanges do
		local row = assert(byKey[originalKey], "Unknown attribute exception")
		assert(
			row.path == "Workspace.MapBlockout" or row.path == "Workspace.MapBlockout.MapArt",
			"Only parent art metadata attributes may change"
		)
		for name in changes do
			assert(
				name == "EnvironmentV2Owner" or name == "EnvironmentV2Hash" or name == "EnvironmentV2Status",
				"Unapproved original attribute change"
			)
		end
	end
	if options.validateChangesOnly then
		r.status = "ApprovedExceptionScope"
		r.preservationAssessed = false
		local result = finish(r)
		result.status = if result.passed then "ApprovedExceptionScope" else "FailedExceptionScope"
		return result
	end
	for _, before in context.manifest.records do
		local node = assert(context.refs[before.key], "Missing baseline identity")
		check(r, node:IsDescendantOf(game), "Original deleted/detached: " .. before.path)
		local actual = Audit.Record(node, key)
		check(
			r,
			actual.name == before.name and actual.class == before.class and actual.archivable == before.archivable,
			"Original identity/class/archivable: " .. before.path
		)
		check(
			r,
			node.Parent == (archives[before.key] or context.refs[before.parent]),
			"Original parent identity: " .. before.path
		)
		check(r, Audit.Equal(actual.tags, before.tags, 0), "Original tags: " .. before.path)
		local wantedAttributes = table.clone(before.attributes)
		for n, value in attributeChanges[before.key] or {} do
			wantedAttributes[n] = value
		end
		check(r, Audit.Equal(actual.attributes, wantedAttributes, 0), "Original attributes: " .. before.path)
		local wantedProperties = table.clone(before.properties)
		for n, value in propertyChanges[before.key] or {} do
			if type(value) == "table" and value.type == "OwnedInstance" then
				local owned = V.ResolveOwnedInstance(value, options.layerRoot)
				wantedProperties[n] = { type = "Instance", key = key(owned), path = owned:GetFullName() }
			else
				wantedProperties[n] = value
			end
		end
		for name, value in wantedProperties do
			check(
				r,
				Audit.Equal(actual.properties[name], value, 1e-6),
				"Original property " .. name .. ": " .. before.path
			)
		end
		check(
			r,
			Audit.Equal(actual.pivot, before.pivot, 1e-6)
				and Audit.Equal(actual.scale, before.scale, 1e-6)
				and Audit.Equal(actual.mass, before.mass, 1e-6),
			"Original pivot/scale/mass: " .. before.path
		)
	end
	local sourcesCount = 0
	for _, node in game:GetDescendants() do
		if node:IsA("LuaSourceContainer") then
			sourcesCount += 1
		end
	end
	check(r, sourcesCount == #context.sources, "No extra/deleted source containers")
	for _, before in context.sources do
		local node = context.refs[before.key]
		check(
			r,
			node
				and node:IsDescendantOf(game)
				and node.ClassName == before.class
				and node.Name == before.name
				and key(node.Parent) == before.parent,
			"Source identity/parent: " .. before.path
		)
		check(r, node.Source == before.source, "Exact current source bytes: " .. before.path)
		local actual = Audit.Record(node, key)
		check(
			r,
			Audit.Equal(actual.attributes, before.attributes, 0)
				and Audit.Equal(actual.properties, before.properties, 0),
			"Source metadata/enabled/run context: " .. before.path
		)
		if before.editorSourceAvailable then
			local ok, text = pcall(function()
				return game:GetService("ScriptEditorService"):GetEditorSource(node)
			end)
			check(r, ok and text == before.editorSource, "Exact current editor buffer: " .. before.path)
		end
	end
	check(
		r,
		Audit.Equal(Audit.Environment(key), context.manifest.environment, 1e-6),
		"Lighting/streaming/avatar/collision/material owner settings unchanged"
	)
	r.originalRecords = #context.manifest.records
	r.sources = #context.sources
	r.brainrotModels = 35
	r.brainrotBaseParts = 890
	r.archiveRoots = #archiveRows
	r.approvedSourceChanges = 0
	return finish(r)
end
local function normalizeRegion(id)
	local name = tostring(id):upper():gsub("^REGION_", ""):gsub("[%s_]", "")
	return if name == "GLITCHZONE" then "GLITCH" else name
end
function V.Layer(options)
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"Layer API requires DEV Edit"
	)
	local r = report()
	local manifest = assert(options.manifest, "Manifest required")
	local root = assert(options.layerRoot, "Installed layer required")
	assert(
		root:IsDescendantOf(workspace.MapBlockout) and root:GetAttribute("ArtOwner") == OWNER,
		"Exact installed owned layer required"
	)
	assert(
		manifest.migrationId == OWNER and manifest.applyEligible == true,
		"Frozen apply-eligible environment manifest required"
	)
	local prototypeRoles = {
		Broadleaf = "Tree",
		Palm = "Tree",
		SwampTree = "Tree",
		RockCluster = "Rock",
		Shrub = "Shrub",
		Terrace = "Terrace",
		SecondaryRuin = "SecondaryRuin",
		ForestRuin = "Hero",
		BeachSeaGate = "Hero",
		SwampCistern = "Hero",
		JungleObservatory = "Hero",
		ArcticIgloo = "Hero",
		VolcanoMassif = "Hero",
		GlitchTemple = "Hero",
		CampWaystone = "Hero",
		CliffRun = "Boundary",
		GateLintel = "Boundary",
		BurrowCore = "Burrow",
		Burrow = "Burrow",
		BurrowAssembly = "Burrow",
	}
	local validRoles = {
		Tree = true,
		Rock = true,
		Shrub = true,
		Terrace = true,
		SecondaryRuin = true,
		Hero = true,
		Burrow = true,
		Boundary = true,
		Motif = true,
	}
	local expected = {}
	local counts = {
		visible = 0,
		colliders = 0,
		baseParts = 0,
		instances = 1 + #root:GetDescendants(),
		triangles = 0,
		meshIds = 0,
		scenery = 0,
		trees = 0,
		boundary = 0,
		motifs = 0,
		burrows = 0,
		heroes = 0,
	}
	local treesByRegion, burrowsByRegion, heroesByRegion = {}, {}, {}
	for _, row in manifest.objects do
		assert(type(row.id) == "string" and #row.id > 0 and not expected[row.id], "Unique bounded assembly ID required")
		expected[row.id] = row
		check(r, validRoles[row.role] == true, "Known assembly role: " .. row.id)
		if prototypeRoles[row.prototypeId] then
			check(
				r,
				row.role == prototypeRoles[row.prototypeId],
				"Prototype category cannot be relabelled to evade budget: " .. row.id
			)
		end
		local region = normalizeRegion(row.regionId)
		if row.role == "Boundary" then
			counts.boundary += 1
		elseif row.role == "Motif" then
			counts.motifs += 1
		else
			counts.scenery += 1
		end
		if row.role == "Tree" then
			counts.trees += 1
			treesByRegion[region] = (treesByRegion[region] or 0) + 1
		end
		if row.role == "Burrow" then
			counts.burrows += 1
			burrowsByRegion[region] = (burrowsByRegion[region] or 0) + 1
		end
		if row.role == "Hero" then
			counts.heroes += 1
			heroesByRegion[region] = (heroesByRegion[region] or 0) + 1
		end
	end
	local proof = assert(options.nativeProof, "Actual complete native prototype proof required")
	assert(
		proof.passed == true
			and proof.completeBatch == true
			and type(proof.sourceSHA256) == "string"
			and #proof.sourceSHA256 == 64,
		"No prepared/mock native proof; exact source hash required"
	)
	check(r, manifest.assetSourceSHA256 == proof.sourceSHA256, "Frozen placement and actual native source hashes match")
	local nativeByMesh, nativeByKey = {}, {}
	for _, group in proof.groups do
		assert(
			group.passed == true
				and group.complete == true
				and type(group.meshId) == "string"
				and #group.meshId > 0
				and type(group.prototypeId) == "string"
				and (group.exportGroup == "A" or group.exportGroup == "B")
				and finite(group.actualTriangles)
				and group.actualTriangles > 0,
			"Normalized actual native group evidence required"
		)
		assert(not nativeByMesh[group.meshId], "Unique actual mesh evidence required")
		nativeByMesh[group.meshId] = group
		local nativeKey = group.prototypeId .. "/" .. group.exportGroup
		assert(not nativeByKey[nativeKey], "Unique actual prototype/group evidence required")
		nativeByKey[nativeKey] = group
	end
	if #(manifest.unplacedMandatory or {}) == 1 then
		local omitted = manifest.unplacedMandatory[1]
		check(
			r,
			omitted.evidence and omitted.evidence.baselineSceneSHA256 == manifest.baselineSceneSHA256,
			"Camp no-fit search binds the exact current scene"
		)
		check(
			r,
			omitted.evidence and omitted.evidence.assetSourceSHA256 == proof.sourceSHA256,
			"Camp no-fit search binds the exact final native source"
		)
		for _, nativeKey in { "BurrowCore/A", "BurrowBrow/A", "BurrowBrow/B" } do
			local actualGroup = nativeByKey[nativeKey]
			local prototype = options.nativeAssets and options.nativeAssets[nativeKey]
			check(
				r,
				actualGroup
					and prototype
					and prototype:IsA("MeshPart")
					and prototype:IsDescendantOf(game:GetService("ServerStorage"))
					and prototype.MeshId == actualGroup.meshId,
				"Complete native Camp Core/Brow assets retained off-world: " .. nativeKey
			)
		end
	end
	local assemblyModels, colliders, meshes, actualGroups = {}, {}, {}, {}
	local visibleSignFaces = 0
	local allowedClasses = { Folder = true, Model = true, MeshPart = true, Part = true, Attachment = true }
	for _, node in root:GetDescendants() do
		check(
			r,
			allowedClasses[node.ClassName] == true,
			"No runtime/effect/texture/UI/unclassified layer instance: " .. node:GetFullName()
		)
		for _, tag in game:GetService("CollectionService"):GetTags(node) do
			check(r, tag == OWNER, "No gameplay activation tag: " .. node:GetFullName() .. "/" .. tag)
		end
		if node:IsA("Model") then
			check(
				r,
				node.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent
					and node.ModelStreamingMode ~= Enum.ModelStreamingMode.PersistentPerPlayer,
				"No new whole-region persistent streaming model"
			)
		end
		if node:IsA("Model") and type(node:GetAttribute("EnvironmentId")) == "string" then
			local id = node:GetAttribute("EnvironmentId")
			local ancestor = node.Parent
			while ancestor ~= root and ancestor and ancestor:GetAttribute("EnvironmentId") == nil do
				ancestor = ancestor.Parent
			end
			if ancestor == root then
				check(r, expected[id] ~= nil and not assemblyModels[id], "Manifest assembly identity: " .. id)
				assemblyModels[id] = node
			end
		end
		if node:IsA("BasePart") then
			counts.baseParts += 1
			local id = node:GetAttribute("EnvironmentId")
			local row = expected[id]
			check(
				r,
				row ~= nil
					and node:GetAttribute("ArtOwner") == OWNER
					and node:GetAttribute("ArtVersion") == 2
					and node.Anchored
					and node.CanTouch == false
					and node.CollisionGroup == "Default",
				"Part ownership/static flags: " .. node:GetFullName()
			)
			local role = node:GetAttribute("EnvironmentRole")
			if role == "Visible" or role == "VisibleSignFace" then
				counts.visible += 1
				if role == "VisibleSignFace" then
					visibleSignFaces += 1
				end
				check(
					r,
					node.Transparency == 0
						and node.LocalTransparencyModifier == 0
						and not node.CanCollide
						and not node.CanQuery
						and node.Reflectance == 0,
					"Opaque nonphysical visible art: " .. node:GetFullName()
				)
				check(
					r,
					node.Material == Enum.Material.Glacier
						and node.MaterialVariant == VARIANT
						and node:GetAttribute("StudsPerTile") == 0.25,
					"Saved uniform stud material: " .. node:GetFullName()
				)
				local triangles = 0
				if node:IsA("MeshPart") then
					local group = nativeByMesh[node.MeshId]
					check(
						r,
						group ~= nil
							and node:GetAttribute("ImportedMeshId") == node.MeshId
							and node.TextureID == ""
							and node.DoubleSided == false,
						"Actual genuine imported group ID/opaque export: " .. node:GetFullName()
					)
					if group then
						triangles = group.actualTriangles
						check(
							r,
							node:GetAttribute("SourceTriangles") == triangles
								and node:GetAttribute("SourceSHA256") == proof.sourceSHA256
								and node:GetAttribute("PrototypeId") == group.prototypeId
								and node:GetAttribute("ExportGroup") == group.exportGroup,
							"Source/native triangles/prototype/group match: " .. node:GetFullName()
						)
						if row then
							actualGroups[id] = actualGroups[id] or {}
							local nativeKey = group.prototypeId .. "/" .. group.exportGroup
							check(
								r,
								not actualGroups[id][nativeKey],
								"No duplicate visible export group: " .. id .. "/" .. nativeKey
							)
							actualGroups[id][nativeKey] = node
							check(
								r,
								(
									row.role == "Burrow"
									and (group.prototypeId == "BurrowCore" or group.prototypeId == "BurrowBrow")
								) or group.prototypeId == row.prototypeId,
								"Actual prototype role cannot be relabelled: " .. node:GetFullName()
							)
						end
					end
					meshes[node.MeshId] = true
				else
					check(
						r,
						node.ClassName == "Part"
							and node.Shape == Enum.PartType.Block
							and row
							and (
								(row.role == "Motif" and role == "Visible")
								or (
									role == "VisibleSignFace"
									and row.signFaceProxy
									and node.Name == row.signFaceProxy.id
								)
							),
						"Only motifs may use ordinary visible block Parts"
					)
					triangles = 12
				end
				counts.triangles += triangles
				if
					row
					and (
						row.role == "Rock"
						or row.role == "Shrub"
						or row.role == "SecondaryRuin"
						or row.role == "Motif"
					)
				then
					check(r, not node.CastShadow, "Small scenery shadows off")
				end
				if row and role ~= "VisibleSignFace" and (row.role == "Boundary" or row.role == "Hero") then
					check(r, node.CastShadow, "Landform/hero shadow casts")
				end
				if row and row.role == "Tree" then
					check(
						r,
						node.CastShadow == (node:GetAttribute("ExportGroup") == "A"),
						"Initial tree support shadows on/canopy off"
					)
				end
				if row and row.prototypeId == "CliffRun" and node:IsA("MeshPart") then
					check(r, node.RenderFidelity == Enum.RenderFidelity.Automatic, "Boundary automatic render fidelity")
				end
			elseif role == "Collider" then
				counts.colliders += 1
				local colliderId = node:GetAttribute("EnvironmentColliderId")
				check(r, type(colliderId) == "string" and not colliders[colliderId], "Unique collider ID")
				if type(colliderId) == "string" then
					colliders[colliderId] = node
				end
				check(
					r,
					node.ClassName == "Part"
						and node.Shape == Enum.PartType.Block
						and node.Transparency == 1
						and node.CanCollide
						and node.CanQuery
						and not node.CastShadow,
					"Exact simple solid collider flags"
				)
			else
				check(r, false, "Every Part must be Visible or Collider; hidden roots are forbidden")
			end
		end
	end
	local installedUniqueMeshIds = 0
	for _ in meshes do
		installedUniqueMeshIds += 1
	end
	-- The prototype-ID budget includes complete imported source assets retained off-world, not only visible copies.
	counts.meshIds = #proof.groups
	local colliderRows = 0
	local referencedColliderIds = {}
	for id, row in expected do
		local model = assemblyModels[id]
		if row.existingOriginalKey then
			check(
				r,
				options.baseline.refs[row.existingOriginalKey] ~= nil,
				"Existing hero slot bound to preserved original"
			)
		else
			check(r, model ~= nil, "Required placed assembly: " .. id)
		end
		if model then
			local cf = frame(row.rootCFrame)
			local expectedGroups = {}
			if row.role ~= "Motif" then
				check(
					r,
					type(row.meshGroups or row.meshGroupIds) == "table" and #(row.meshGroups or row.meshGroupIds) > 0,
					"Every nonmotif assembly lists its frozen export groups: " .. id
				)
			end
			for _, spec in dense(row.meshGroups or row.meshGroupIds or {}, 3, "Manifest export groups") do
				local nativeKey = (spec.prototypeId or row.prototypeId) .. "/" .. (spec.exportGroup or spec.groupId)
				assert(not expectedGroups[nativeKey], "Duplicate frozen prototype/group row")
				expectedGroups[nativeKey] = true
				local part = actualGroups[id] and actualGroups[id][nativeKey]
				local unit = options.expectedNative and options.expectedNative[nativeKey]
				check(r, part and unit, "Exact frozen group descriptor/instance: " .. id .. "/" .. nativeKey)
				if part and unit then
					check(
						r,
						unit.meshId == part.MeshId
							and unit.sourceSHA256 == proof.sourceSHA256
							and unit.triangles == nativeByMesh[part.MeshId].actualTriangles,
						"Exact independent unit/source/triangle binding: " .. id .. "/" .. nativeKey
					)
					local localCF, localSize, axisScale =
						frame(unit.localCFrame), vector(unit.size), vector(row.axisScale)
					local localPosition = localCF.Position
					local offset = Vector3.new(
						localPosition.X * axisScale.X,
						localPosition.Y * axisScale.Y,
						localPosition.Z * axisScale.Z
					)
					local expectedCF = cf * CFrame.new(offset) * localCF.Rotation
					local function extentAxis(basis)
						return math.abs(basis.X) * axisScale.X
							+ math.abs(basis.Y) * axisScale.Y
							+ math.abs(basis.Z) * axisScale.Z
					end
					local expectedSize = Vector3.new(
						localSize.X * extentAxis(localCF.RightVector),
						localSize.Y * extentAxis(localCF.UpVector),
						localSize.Z * extentAxis(localCF.LookVector)
					)
					check(
						r,
						options.auditAPI.Equal({ part.CFrame:GetComponents() }, { expectedCF:GetComponents() }, 0.01)
							and (part.Size - expectedSize).Magnitude <= 0.01
							and options.auditAPI.Equal(
								{ part.PivotOffset:GetComponents() },
								{ 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
								1e-6
							),
						"Exact per-group source transform/size/pivot: " .. id .. "/" .. nativeKey
					)
					local color = V.PaletteRGB(spec, row)
					check(
						r,
						math.abs(part.Color.R - color[1] / 255) <= 1e-6
							and math.abs(part.Color.G - color[2] / 255) <= 1e-6
							and math.abs(part.Color.B - color[3] / 255) <= 1e-6,
						"Exact frozen group palette: " .. id .. "/" .. nativeKey
					)
				end
			end
			for nativeKey in actualGroups[id] or {} do
				check(r, expectedGroups[nativeKey], "No extra unmanifested visible group: " .. id .. "/" .. nativeKey)
			end
			local scale = row.axisScale
			check(
				r,
				type(scale) == "table"
					and #scale == 3
					and finite(scale[1])
					and finite(scale[2])
					and finite(scale[3])
					and scale[1] > 0
					and scale[2] > 0
					and scale[3] > 0,
				"Positive frozen axis scale: " .. id
			)
			if row.role == "Tree" or row.role == "Rock" or row.role == "Shrub" then
				check(
					r,
					scale
						and math.abs(scale[1] - scale[2]) < 1e-6
						and math.abs(scale[2] - scale[3]) < 1e-6
						and scale[1] <= 1.10,
					"Approved uniform scenery scale: " .. id
				)
			end
			check(
				r,
				(cf.UpVector - Vector3.yAxis).Magnitude <= 0.001
					and math.abs(math.abs(cf.RightVector.X) + math.abs(cf.RightVector.Z) - 1) <= 0.001,
				"Cardinal yaw with no pitch/roll: " .. id
			)
			check(
				r,
				options.auditAPI.Equal({ model:GetPivot():GetComponents() }, { cf:GetComponents() }, 0.01),
				"Ground/mouth pivot: " .. id
			)
			if row.signFaceProxy then
				local proxy = row.signFaceProxy
				local part = model:FindFirstChild(proxy.id)
				local gui = options.baseline.refs[proxy.originalGuiKey]
				local color = V.PaletteRGB(proxy, row)
				check(
					r,
					part
						and part.ClassName == "Part"
						and part.Shape == Enum.PartType.Block
						and part:GetAttribute("EnvironmentRole") == "VisibleSignFace"
						and part:GetAttribute("EnvironmentId") == id
						and part.Size.X == 16
						and part.Size.Y == 5
						and math.abs(part.Size.Z - 0.1) < 1e-6
						and part:GetAttribute("SourceTriangles") == 12
						and part:GetAttribute("SourceSHA256") == proof.sourceSHA256
						and options.auditAPI.Equal({ part.CFrame:GetComponents() }, proxy.cframe, 0.01)
						and not part.CastShadow
						and math.abs(part.Color.R - color[1] / 255) < 1e-6
						and math.abs(part.Color.G - color[2] / 255) < 1e-6
						and math.abs(part.Color.B - color[3] / 255) < 1e-6
						and gui
						and gui.Adornee == part,
					"Exact approved primitive gate sign face and original GUI binding: " .. id
				)
				if part and gui then
					local sign = options.baseline.refs[proxy.originalSignKey]
					local normal = -part.CFrame.LookVector
					local delta = part.Position - sign.Position
					local correction = V.SignPresentationCorrection(proxy, row)
					local rotationRetained = options.auditAPI.Equal(
						{ part.CFrame.Rotation:GetComponents() },
						{ sign.CFrame.Rotation:GetComponents() },
						0.001
					)
					check(
						r,
						gui.Face == Enum.NormalId.Back
							and math.abs(delta:Dot(sign.CFrame.UpVector)) <= 0.01
							and (
								if correction
									then (correction.owner == "Gate_Volcano_Header_01" or rotationRetained)
									else rotationRetained and math.abs(delta:Dot(sign.CFrame.RightVector)) <= 0.01
							),
						"Original FaceBack/vertical retained; only exact two approved owned pose corrections: " .. id
					)
					local viewpoint = (proxy.clearanceEvidence or {}).legalViewpoint
					check(
						r,
						finiteArrayNear(viewpoint, viewpoint or {}, 0) and #viewpoint == 3,
						"Reviewed legal sign viewpoint required: " .. id
					)
					if viewpoint and #viewpoint == 3 then
						local eye = vector(viewpoint)
						check(
							r,
							(eye - part.Position):Dot(normal) > 0.01,
							"Legal sign viewpoint is in front of the retained FaceBack surface: " .. id
						)
						local tests, blocked = 0, 0
						for _, obstacle in colliders do
							check(
								r,
								not V.SignSegmentIntersectsBox(
									viewpoint,
									viewpoint,
									{ obstacle.CFrame:GetComponents() },
									{ obstacle.Size.X, obstacle.Size.Y, obstacle.Size.Z }
								),
								"Legal sign viewpoint outside actual owned collider: " .. id .. "/" .. obstacle.Name
							)
						end
						for _, u in { -1, -0.5, 0, 0.5, 1 } do
							for _, v in { -1, 0, 1 } do
								local endpoint = part.CFrame
									* Vector3.new(u * part.Size.X / 2, v * part.Size.Y / 2, part.Size.Z / 2)
								for _, obstacle in colliders do
									tests += 1
									if
										V.SignSegmentIntersectsBox(
											viewpoint,
											{ endpoint.X, endpoint.Y, endpoint.Z },
											{ obstacle.CFrame:GetComponents() },
											{ obstacle.Size.X, obstacle.Size.Y, obstacle.Size.Z }
										)
									then
										blocked += 1
										check(
											r,
											false,
											"Full sign face LOS blocked by actual owned collider: "
												.. id
												.. "/"
												.. obstacle.Name
										)
									end
								end
							end
						end
						r.signColliderLOS = r.signColliderLOS or {}
						table.insert(
							r.signColliderLOS,
							{
								id = id,
								viewpoint = viewpoint,
								faceSamples = 15,
								actualColliderRayTests = tests,
								blocked = blocked,
								scope = "Actual owned primitive collider OBBs; native pixels and protected visual meshes assessed separately",
							}
						)
					end
					local nearestInner = part.Position:Dot(normal) - part.Size.Z / 2
					local maximumOpaque = -math.huge
					for _, mesh in model:GetDescendants() do
						if mesh:IsA("MeshPart") and mesh:GetAttribute("EnvironmentRole") == "Visible" then
							local f, size = mesh.CFrame, mesh.Size
							local support = (
								math.abs(f.RightVector:Dot(normal)) * size.X
								+ math.abs(f.UpVector:Dot(normal)) * size.Y
								+ math.abs(f.LookVector:Dot(normal)) * size.Z
							) / 2
							maximumOpaque = math.max(maximumOpaque, f.Position:Dot(normal) + support)
						end
					end
					check(
						r,
						maximumOpaque > -math.huge and nearestInner - maximumOpaque >= 0.04,
						"Actual sign proxy inner face lies outside every opaque header native extent: " .. id
					)
				end
			end
			if row.prototypeId == "CliffRun" then
				check(
					r,
					finite(row.length)
						and row.length > 0
						and row.length <= 256
						and (row.depth == 40 or row.depth == 32 or row.depth == 24 or row.depth == 16 or row.depth == 8)
						and finite(row.coreHeight)
						and row.coreHeight >= 72
						and row.coreHeight % 4 == 0,
					"Cliff run maximumlength/approveddepth/safe core height: " .. id
				)
				check(r, #(row.colliders or {}) == 1, "Single continuous cliff core collider: " .. id)
				if row.colliders and row.colliders[1] then
					local core = colliders[row.colliders[1].id]
					local coreBounds = core and bounds(core.CFrame, core.Size)
					check(
						r,
						coreBounds and coreBounds.maxY - cf.Position.Y >= row.coreHeight - 0.01,
						"Actual solid cliff top retains the prescribed safeheight: " .. id
					)
				end
			end
			for _, collider in row.colliders or {} do
				assert(not referencedColliderIds[collider.id], "Duplicate collider in manifest")
				referencedColliderIds[collider.id] = true
				colliderRows += 1
				local node = colliders[collider.id]
				check(
					r,
					node and node:GetAttribute("EnvironmentId") == id,
					"Manifest collider ownership: " .. collider.id
				)
				if node then
					check(
						r,
						options.auditAPI.Equal({ node.CFrame:GetComponents() }, collider.cframe, 0.01)
							and (node.Size - vector(collider.size)).Magnitude <= 0.01,
						"Exact wall/roof/component collision box: " .. collider.id
					)
				end
			end
			local actualBounds
			for _, part in model:GetDescendants() do
				if
					part:IsA("BasePart")
					and (
						part:GetAttribute("EnvironmentRole") == "Visible"
						or part:GetAttribute("EnvironmentRole") == "VisibleSignFace"
					)
				then
					local b = bounds(part.CFrame, part.Size)
					if not actualBounds then
						actualBounds = b
					else
						for name, value in b do
							actualBounds[name] = if name:sub(1, 3) == "min"
								then math.min(actualBounds[name], value)
								else math.max(actualBounds[name], value)
						end
					end
				end
			end
			local plannedBounds = (options.expectedBounds and options.expectedBounds[id])
				or row.actualBounds
				or row.bounds
			for i, axis in { "X", "Y", "Z" } do
				for _, edge in { "min", "max" } do
					local name = edge .. axis
					local value = plannedBounds
						and (plannedBounds[name] or (plannedBounds[edge] and plannedBounds[edge][i]))
					check(
						r,
						actualBounds and finite(value) and math.abs(actualBounds[name] - value) <= 0.01,
						"Actual visible footprint vs frozen placement: " .. id .. "/" .. name
					)
				end
			end
			if row.role == "Burrow" then
				local markerNames = { Art_Mouth = true, Art_Exit = true, Art_Turn = true, Art_Hide = true }
				local markers = 0
				for _, node in model:GetDescendants() do
					if node:IsA("Attachment") then
						markers += 1
						check(r, markerNames[node.Name] == true, "Only four inactive burrow interface markers")
						local attrs = node:GetAttributes()
						local attrCount = 0
						for _ in attrs do
							attrCount += 1
						end
						check(
							r,
							attrCount == 4
								and attrs.Art_BurrowId == id
								and attrs.Art_RegionKey == row.regionId
								and attrs.Art_InterfaceVersion == 1
								and attrs.Art_RuntimeRegistered == false,
							"Exact inactive marker attributes"
						)
						check(
							r,
							node.Parent:IsA("MeshPart")
								and node.Parent:GetAttribute("PrototypeId") == "BurrowCore"
								and node.Parent:GetAttribute("ExportGroup") == "A",
							"Marker attached to real Core A; no hidden root"
						)
					end
				end
				local names = {}
				for _, marker in model:GetDescendants() do
					if marker:IsA("Attachment") then
						names[marker.Name] = (names[marker.Name] or 0) + 1
					end
				end
				check(
					r,
					names.Art_Mouth == 1
						and names.Art_Exit == 1
						and names.Art_Turn == 1
						and names.Art_Hide == 1
						and markers == 4
						and #(row.colliders or {}) == 7,
					"Burrow four unique markers/seven exact wall+roof boxes"
				)
				local markerRows = {}
				for _, marker in row.markers or {} do
					markerRows[marker.name] = marker
				end
				for name in markerNames do
					local marker = model:FindFirstChild(name, true)
					local planned = markerRows[name]
					check(
						r,
						marker
							and planned
							and options.auditAPI.Equal(
								{ marker.WorldCFrame:GetComponents() },
								planned.worldCFrame,
								0.01
							),
						"Actual fitted marker frame/order: " .. id .. "/" .. name
					)
				end
			end
		end
	end
	check(r, colliderRows == counts.colliders, "No missing/extra unmanifested collider")
	local treeLimits = { CAMP = 2, FOREST = 10, BEACH = 6, SWAMP = 6, JUNGLE = 10, ARCTIC = 2, VOLCANO = 0, GLITCH = 0 }
	for region, limit in treeLimits do
		check(r, (treesByRegion[region] or 0) <= limit, "Regional tree ceiling " .. region)
		check(
			r,
			(burrowsByRegion[region] or 0) == (if region == "CAMP" then 1 - #(manifest.unplacedMandatory or {}) else 2),
			"Required regional burrows " .. region
		)
		check(r, heroesByRegion[region] == 1, "One primary regional hero " .. region)
	end
	local budgetOK, budgetError =
		pcall(V.ValidateCounts, counts, manifest.unplacedMandatory, manifest.triangleBudgetException)
	check(r, budgetOK, tostring(budgetError))
	if manifest.triangleBudgetException then
		local exception = manifest.triangleBudgetException
		check(
			r,
			exception.sourceSHA256 == proof.sourceSHA256
				and exception.baselineSceneSHA256 == manifest.baselineSceneSHA256,
			"Explicit triangle exception binds actual final source/currentscene"
		)
		local projected = 0
		for _, row in manifest.objects do
			assert(
				finite(row.expectedExportTriangles)
					and row.expectedExportTriangles % 1 == 0
					and row.expectedExportTriangles >= 0,
				"Frozen per-placement export triangle proof required"
			)
			projected += row.expectedExportTriangles
		end
		check(
			r,
			projected == exception.sourceProjectedTriangles and counts.triangles == projected,
			"Actual installed native triangles agree with the exact selected source projection"
		)
	end
	-- All exact collider AABBs must be fed into the existing bounded geometry owner, without Source edits.
	local runtime = game:GetService("HttpService"):JSONDecode(workspace.MapBlockout.CompactMapRuntimeGeometry.Value)
	local masks = {}
	for _, m in dense(runtime.staticWallObstacles, 512, "Current owner masks") do
		check(r, not masks[m.id], "Unique geometry owner mask")
		masks[m.id] = m
	end
	for id, node in colliders do
		local m = masks[id]
		check(r, m ~= nil, "Every new collider has a canonical runtime exclusion: " .. id)
		if m then
			local b = bounds(node.CFrame, node.Size)
			for name, value in b do
				check(
					r,
					finite(m[name]) and math.abs(m[name] - value) <= 0.01,
					"Actual collider/mask bound " .. id .. "/" .. name
				)
			end
		end
	end
	local variant = game:GetService("MaterialService"):FindFirstChild(VARIANT)
	check(
		r,
		variant
			and variant:IsA("MaterialVariant")
			and variant.BaseMaterial == Enum.Material.Glacier
			and variant.StudsPerTile == 0.25,
		"Saved shared material actual .25"
	)
	for _, node in workspace:GetDescendants() do
		if
			node:GetAttribute("ArtOwner") == OWNER
			or node:GetAttribute("SourceSHA256") == proof.sourceSHA256
			or (node:IsA("MeshPart") and nativeByMesh[node.MeshId] ~= nil)
		then
			check(
				r,
				node == root or node:IsDescendantOf(root),
				"No active source/import/environment duplicate outside owned layer"
			)
		end
	end
	check(r, visibleSignFaces == 6, "Exactly six approved native primitive sign faces")
	r.visibleSignFaces = visibleSignFaces
	r.gateSignActualPlayReadability = "NotAssessed; actual GateInit/GUI readback and normal camera view required"
	r.counts = counts
	r.budgets = LIMITS
	r.strictTriangleBudgetPassed = counts.triangles <= LIMITS.triangles
	r.triangleBudgetException = manifest.triangleBudgetException
	r.triangleBudgetStatus = if r.strictTriangleBudgetPassed then "Met" else "NotMet_DocumentedException"
	r.boundaryTarget = V.BoundaryTarget(counts.boundary)
	r.actualNativeGroups = #proof.groups
	r.actualInstalledUniqueMeshIds = installedUniqueMeshIds
	r.unplacedMandatory = manifest.unplacedMandatory or {}
	r.fullFifteenBurrowsPlaced = counts.burrows == 15
	r.runtimeRegisteredBurrows = 0
	r.newRuntimeScripts = 0
	r.huntingAreaAndSightLines = "Require separate actual numeric planner/grid/ray evidence; not inferred from counts"
	r.jumpResistance = "NotAssessed; ordinary jump/loaded driving required"
	r.burrowSweepAndOcclusion = "NotAssessed; separate full native sweep/views required"
	r.performance = "NotAssessed"
	r.fullGameplayAcceptancePassed = false
	return finish(r)
end
function V.Verify(options)
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"Read-only verifier requires DEV Edit"
	)
	assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Wrong DEV")
	local fullOptions = table.clone(options)
	fullOptions.validateChangesOnly = false
	local preservation = V.Preserve(fullOptions)
	local layer = V.Layer(options)
	return {
		schemaVersion = 2,
		owner = OWNER,
		passed = preservation.passed and layer.passed,
		status = if preservation.passed and layer.passed
			then (if options.manifest.triangleBudgetException
					and #(options.manifest.unplacedMandatory or {}) == 1
				then "ImplementedWithDocumentedCampAndBudgetExceptions"
				elseif options.manifest.triangleBudgetException then "ImplementedWithDocumentedBudgetException"
				elseif #(options.manifest.unplacedMandatory or {}) == 1 then "ImplementedWithDocumentedCampConflict"
				else "StaticPreservationAndLayerPassedAcceptancePartial")
			else "Failed",
		preservation = preservation,
		layer = layer,
		worldWrites = 0,
		sourceWrites = 0,
		gameplayRequires = 0,
		fullAcceptancePassed = false,
	}
end
return V
