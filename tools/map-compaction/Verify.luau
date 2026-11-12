--!nocheck
-- Read-only desired-state verification. No gameplay requires, setters, allocations or asset publication.
-- Apply calls this before final Completed attributes; failures are retained on options.lastStaticProof.
local API = {}
local Http = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")
local MIGRATION = "CompactMap_V1"
local BASELINE = "3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310"
local CANONICAL = "078a93ed83234709bec5799997d7ee41a8dd28cb39bc5fdd8ef18992d3353005"
local IMPORT = "bdd81be39782c1649694deecaf3264e5e82db25d9bb7ed7f783f05c1ab6fbd4e"
local ROAD_HASH = "696d1821c5ebc3a595f9437366c1c777f31d6ea5f2b0f303fd8a2a895a32dbb0"
local PATCHED = {
	["ReplicatedStorage.Shared.Config.BaseLayoutConfig"] = true,
	["ServerScriptService.Server.Systems.BaseIncomePlaqueSystem"] = true,
	["ServerScriptService.Server.Systems.RegionSpawnCatalog"] = true,
	["ServerScriptService.Server.Systems.BrainrotSaleSystem"] = true,
	["ServerScriptService.Server.Services.UpgradeService"] = true,
}
local TOL = 0.01
local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function encode(v)
	local t = typeof(v)
	if t == "Vector3" then
		return { type = t, value = { v.X, v.Y, v.Z } }
	end
	if t == "Vector2" then
		return { type = t, value = { v.X, v.Y } }
	end
	if t == "CFrame" then
		return { type = t, value = { v:GetComponents() } }
	end
	if t == "Color3" then
		return { type = t, value = { v.R, v.G, v.B } }
	end
	if t == "UDim2" then
		return { type = t, value = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } }
	end
	if t == "UDim" then
		return { type = t, value = { v.Scale, v.Offset } }
	end
	if t == "PhysicalProperties" then
		return {
			type = t,
			value = { v.Density, v.Friction, v.Elasticity, v.FrictionWeight, v.ElasticityWeight },
		}
	end
	if t == "EnumItem" then
		return { type = t, value = tostring(v) }
	end
	return v
end
local function equal(a, b, tolerance)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) == "number" then
		return finite(a) and finite(b) and math.abs(a - b) <= (tolerance or 1e-6)
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not equal(v, b[k], tolerance) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end
local function tagsSame(a, b)
	if #a ~= #b then
		return false
	end
	local s = {}
	for _, x in a do
		s[x] = true
	end
	for _, x in b do
		if not s[x] then
			return false
		end
	end
	return true
end
local function frame(v)
	return CFrame.new(table.unpack(v))
end
local function vec(v)
	return Vector3.new(table.unpack(v))
end
local function scaledLocal(cf, s)
	return CFrame.new(cf.Position * s) * (cf - cf.Position)
end
local function bounds(part)
	local cf, s = part.CFrame, part.Size
	local r = { cf:GetComponents() }
	local half = { s.X / 2, s.Y / 2, s.Z / 2 }
	local ex = {}
	for i = 1, 3 do
		ex[i] = 0
		for j = 1, 3 do
			ex[i] += math.abs(r[3 + (i - 1) * 3 + j]) * half[j]
		end
	end
	return {
		minX = r[1] - ex[1],
		maxX = r[1] + ex[1],
		minY = r[2] - ex[2],
		maxY = r[2] + ex[2],
		minZ = r[3] - ex[3],
		maxZ = r[3] + ex[3],
	}
end
local function contact(a, b, tolerance)
	local d = {
		x = math.max(0, math.min(a.maxX, b.maxX) - math.max(a.minX, b.minX)),
		y = math.max(0, math.min(a.maxY, b.maxY) - math.max(a.minY, b.minY)),
		z = math.max(0, math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ)),
	}
	return {
		depths = d,
		volume = d.x * d.y * d.z,
		minimumAxisDepth = math.min(d.x, d.y, d.z),
		overlapsBeyondTolerance = d.x > tolerance and d.y > tolerance and d.z > tolerance,
		perAxisToleranceStuds = tolerance,
	}
end
local function polygonArea(p)
	local a = 0
	for i, v in p do
		local q = p[i % #p + 1]
		a += v[1] * q[2] - q[1] * v[2]
	end
	return math.abs(a) / 2
end
local function clip(p, axis, limit, greater)
	local out = {}
	if #p == 0 then
		return out
	end
	local function inside(v)
		return if greater then v[axis] >= limit else v[axis] <= limit
	end
	local prev = p[#p]
	local prevIn = inside(prev)
	for _, current in p do
		local inNow = inside(current)
		if inNow ~= prevIn then
			local t = (limit - prev[axis]) / (current[axis] - prev[axis])
			table.insert(
				out,
				{ prev[1] + t * (current[1] - prev[1]), prev[2] + t * (current[2] - prev[2]) }
			)
		end
		if inNow then
			table.insert(out, current)
		end
		prev = current
		prevIn = inNow
	end
	return out
end
local function polygonInBounds(p, b)
	p = clip(p, 1, b.minX, true)
	p = clip(p, 1, b.maxX, false)
	p = clip(p, 2, b.minZ, true)
	p = clip(p, 2, b.maxZ, false)
	return if #p >= 3 then polygonArea(p) else 0
end
local function genuine(id)
	return type(id) == "string" and id:match("^rbxassetid://[1-9]%d*$") ~= nil
end
function API.Verify(options)
	options = options or {}
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"Compact static Verify requires DEV Edit"
	)
	assert(
		game.PlaceId == 91958083796436 and game.GameId == 10548905405,
		"Wrong DEV place/universe"
	)
	local plan = assert(options.plan, "Desired plan required")
	local map = assert(workspace:FindFirstChild("MapBlockout"), "MapBlockout missing")
	local before = assert(shared.CompactMapBeforeManifest, "Frozen before manifest missing")
	local originals =
		assert(shared.CompactMapManagedOriginals, "Original instance references missing")
	local native = assert(shared.CompactMapOriginalNativeValues, "Original native values missing")
	local proof = {
		schemaVersion = 1,
		migrationId = MIGRATION,
		planHash = plan.planHash,
		passed = false,
		status = "Checking",
		failures = {},
		checks = 0,
		counts = {
			managed = 0,
			protected = 0,
			external = 0,
			operations = 0,
			newWalls = 0,
			retainedOuter = 0,
			archivedShared = 0,
			floors = 0,
			roads = 0,
			shells = 0,
			rebuiltMeshInstances = 0,
			wallMaskRows = 0,
			unpatchedSources = 0,
		},
		toleranceStuds = TOL,
		worldWrites = 0,
		sourceWrites = 0,
		assetWrites = 0,
		gameplayRequires = 0,
		geometryCornerReadback = "Bound to prior complete actual native import proof; not repeated by this static verifier",
		cartDrivingTurning = "NotAssessed",
		gameplay = "NotAssessed",
		performance = "NotAssessed",
	}
	options.lastStaticProof = proof
	local function check(ok, scope, message)
		proof.checks += 1
		if not ok then
			table.insert(proof.failures, { scope = scope, message = message })
		end
		return ok
	end
	local function run(scope, callback)
		local ok, err = xpcall(callback, debug.traceback)
		if not ok then
			check(false, scope, tostring(err))
		end
	end
	local function same(actual, expected, scope, label, tolerance)
		local ok = equal(encode(actual), expected, tolerance)
		return check(ok, scope, label .. " differs from desired/captured value")
	end
	local function value(node, name, expected, scope, tolerance)
		if type(expected) == "table" and expected.unavailable then
			return
		end
		if type(expected) == "table" and expected.type == "Instance" then
			check(
				node[name] == originals[expected.key],
				scope,
				name .. " original reference changed"
			)
		else
			same(node[name], expected, scope, name, tolerance)
		end
	end
	check(
		plan.migrationId == MIGRATION and plan.baselineManagedContentSHA256 == BASELINE,
		"Plan",
		"Migration/baseline binding mismatch"
	)
	check(
		type(plan.planHash) == "string"
			and #plan.planHash == 64
			and plan.planHash:match("^[0-9a-f]+$") ~= nil,
		"Plan",
		"Desired hash must be canonical64hex"
	)
	check(plan.status == "ReadyForNativeApply", "Plan", "Plan not ready for native application")
	check(
		options.roadGeometryHash == ROAD_HASH,
		"Plan",
		"Frozen selected road geometry hash mismatch"
	)
	local byKey, byPath, operations, owned, updates = {}, {}, {}, {}, {}
	for _, rows in { before.objects, before.externalStaticObjects, before.protectedSourceAssets } do
		for _, r in rows do
			byKey[r.key] = r
			byPath[r.path] = r
		end
	end
	for _, o in plan.ownership do
		check(not owned[o.key], "Ownership", "Duplicate original ownership " .. o.path)
		owned[o.key] = o
		local r = byKey[o.key]
		check(
			r ~= nil and r.path == o.path,
			"Ownership",
			"Missing/wrong frozen ownership " .. o.path
		)
	end
	check(
		#plan.ownership == #before.objects and #before.objects == 1555,
		"Ownership",
		"Expected all1555 original managed instances"
	)
	for _, o in plan.operations do
		check(operations[o.key] == nil, "Operations", "Duplicate operation " .. o.path)
		operations[o.key] = o
	end
	for _, u in assert(options.metadata, "Metadata required").updates do
		check(updates[u.key] == nil, "Metadata", "Duplicate metadata owner")
		updates[u.key] = u
	end
	local txn =
		SS:FindFirstChild("CompactMapV1_WorldJournal_" .. tostring(plan.planHash):sub(1, 12))
	local retired = txn and txn:FindFirstChild("RetiredSharedSeparators")
	check(
		txn
			and txn:GetAttribute("MigrationId") == MIGRATION
			and txn:GetAttribute("DesiredHash") == plan.planHash
			and txn:GetAttribute("BaselineSHA256") == BASELINE,
		"Journal",
		"Exact migration journal missing"
	)
	check(retired ~= nil, "Journal", "Archived separator folder missing")
	if map:GetAttribute("CompactMapMigrationId") ~= nil then
		check(
			map:GetAttribute("CompactMapMigrationId") == MIGRATION
				and map:GetAttribute("CompactMapDesiredHash") == plan.planHash
				and map:GetAttribute("CompactMapStatus") == "Completed",
			"Completion",
			"Existing completion marker differs"
		)
	end
	local roads =
		assert(SS:FindFirstChild("CompactMapRoadTemplates"), "Native road templates missing")
	local shell =
		assert(SS:FindFirstChild("CompactMapShellTemplate"), "Native shell template missing")
	local cube =
		assert(SS:FindFirstChild("CompactMapWallCubeTemplate"), "Native cube template missing")
	local asset = assert(options.nativeAssetsProof, "Native assets proof missing")
	local assetById = {}
	local tris, corners = 0, 0
	run("NativeAssets", function()
		check(
			asset.passed == true
				and asset.status == "Passed"
				and asset.completeBatch == true
				and #asset.groups == 31,
			"NativeAssets",
			"Complete actual31group native proof required"
		)
		check(
			asset.canonicalSourceSHA256 == CANONICAL
				and asset.studioImportSHA256 == IMPORT
				and asset.roadGeometryHash == ROAD_HASH,
			"NativeAssets",
			"Exact imported source/hash binding required"
		)
		for _, g in asset.groups do
			check(not assetById[g.id], "NativeAssets", "Duplicate proof group " .. g.id)
			assetById[g.id] = g
			check(
				g.passed == true
					and g.geometryCornersComplete == true
					and g.sourceWindingPassed == true
					and g.sourceUVValuesPassed == true
					and g.hardNormalsPassed == true
					and genuine(g.meshId)
					and g.actualTriangles == g.expectedTriangles
					and g.checkedCorners == g.expectedTriangles * 3,
				"NativeAssets",
				"Incomplete corners/native geometry proof " .. g.id
			)
			tris += g.actualTriangles or 0
			corners += g.checkedCorners or 0
		end
		check(
			tris == 2659 and corners == 7977,
			"NativeAssets",
			"Expected2659triangles/7977corner native proof"
		)
	end)
	local function meshTemplate(node, template, id, scope)
		local g = assetById[id]
		check(
			node:IsA("MeshPart") and template:IsA("MeshPart") and g ~= nil,
			scope,
			"Native mesh template/proof not bound " .. id
		)
		if not g then
			return
		end
		same(
			template.CFrame,
			encode(CFrame.new(table.unpack(g.canonicalCentre))),
			scope,
			"Canonical native template centre/identity rotation",
			TOL
		)
		local wantedSize = table.clone(g.sizeXYZ)
		if g.prototypeId == "CompactMapRoads" then
			wantedSize[2] = 0.05
			check(
				(g.maximumNormalError or math.huge) <= 1e-5,
				scope,
				"Road normals differ from strict +Y source"
			)
		end
		same(
			template.Size,
			encode(vec(wantedSize)),
			scope,
			"Canonical native template dimensions",
			TOL
		)
		check(
			genuine(node.MeshId) and node.MeshId == template.MeshId and node.MeshId == g.meshId,
			scope,
			"Persistent native MeshId differs " .. id
		)
		for _, name in { "TextureID", "CollisionFidelity", "RenderFidelity", "DoubleSided" } do
			same(node[name], encode(template[name]), scope, name)
		end
		check(
			node:FindFirstChildWhichIsA("SurfaceAppearance") == nil and node.TextureID == "",
			scope,
			"Static custom map remains on saved-stud mesh"
		)
	end
	check(
		cube:IsA("MeshPart") and cube.CollisionFidelity == Enum.CollisionFidelity.Box,
		"NativeAssets",
		"Actual closed native cube Box collision required"
	)
	meshTemplate(cube, cube, "CompactWallCube_Unit", "NativeCube")
	local function ancestorOperation(r)
		local path = r.path
		while path:find(".", 1, true) do
			path = path:match("^(.*)%.[^.]+$")
			local row = byPath[path]
			if row and operations[row.key] then
				return operations[row.key], row
			end
		end
		return nil, nil
	end
	local replacements, expectedNodes = {}, {}
	for _, op in plan.operations do
		local node = originals[op.key]
		if op.category == "RebuiltRoadSurface" then
			replacements[op.key] =
				{ template = roads:FindFirstChild(op.meshPrototype), id = op.meshPrototype }
		end
		if op.category == "FittedBaseShell" and node then
			for _, r in before.objects do
				if r.parent == op.key and r.class == "MeshPart" then
					replacements[r.key] = {
						template = shell:FindFirstChild(r.name),
						id = "CompactShowhouseShell_A_" .. r.name,
						root = op,
					}
				end
			end
		end
	end
	local function desiredGeometry(r)
		local op = operations[r.key]
		local replacement = replacements[r.key]
		if replacement then
			local t = assert(replacement.template, "Missing template " .. replacement.id)
			return if replacement.root then frame(replacement.root.pivot) * t.CFrame else t.CFrame,
				t.Size,
				1
		end
		local old = r.properties and frame(r.properties.CFrame.value)
		local size = r.properties and vec(r.properties.Size.value)
		if op and op.cframe then
			return frame(op.cframe), if op.size then vec(op.size) else size, 1
		end
		local parent, pr = ancestorOperation(r)
		if parent and parent.pivot and pr.pivot then
			local s = (parent.scale or pr.scale) / pr.scale
			return if old
				then frame(parent.pivot) * scaledLocal(frame(pr.pivot.value):ToObjectSpace(old), s)
				else nil,
				if size then size * s else nil,
				s
		end
		return old, size, 1
	end
	local function verifyAttributes(node, r)
		local expected = table.clone(r.attributes)
		local op = operations[r.key]
		local u = updates[r.key]
		if op and op.attributes then
			for k, v in op.attributes do
				expected[k] = v
			end
		end
		if u then
			for _, k in u.remove do
				expected[k] = nil
			end
			for k, v in u.after do
				expected[k] = v
			end
		end
		if node == map then
			expected.LayoutVersion = before.objects[1].attributes.LayoutVersion + 1
			if node:GetAttribute("CompactMapMigrationId") ~= nil then
				expected.CompactMapMigrationId = MIGRATION
				expected.CompactMapDesiredHash = plan.planHash
				expected.CompactMapStatus = "Completed"
			end
		elseif r.path == "Workspace.MapBlockout.MapArt" then
			expected.CompactMapGeometryHash = plan.geometryPlanHash
		elseif r.path == "Workspace.MapBlockout.Paths.StyledSurfaces" then
			expected.CompactMapGeometryHash = options.roadGeometryHash
		end
		local actual = node:GetAttributes()
		for k, v in expected do
			same(actual[k], v, r.path, "Attribute " .. k, TOL)
		end
		for k in actual do
			check(expected[k] ~= nil, r.path, "Unexpected original attribute " .. k)
		end
	end
	local function verifyOriginal(r, kind)
		local node = assert(originals[r.key], "Missing original reference " .. r.path)
		local n = assert(native[r.key], "Missing captured native record " .. r.path)
		check(
			n.instance == node
				and node.ClassName == r.class
				and node.Name == r.name
				and node.Archivable == r.archivable,
			r.path,
			"Original identity/class/name/Archivable changed"
		)
		local op = operations[r.key]
		if op and op.retire then
			check(
				node.Parent == retired and not node:IsDescendantOf(workspace),
				r.path,
				"Superseded separator remains in world or wrong archive"
			)
		else
			check(
				node.Parent == n.parent and node:GetFullName() == r.path,
				r.path,
				"Original parent/reference changed"
			)
		end
		expectedNodes[node] = true
		verifyAttributes(node, r)
		check(tagsSame(r.tags, CS:GetTags(node)), r.path, "Original tags changed")
		if r.properties then
			local cf, size, s = desiredGeometry(r)
			same(node.CFrame, encode(cf), r.path, "Desired CFrame", TOL)
			same(node.Size, encode(size), r.path, "Desired Size", TOL)
			for name, v in r.properties do
				if name ~= "CFrame" and name ~= "Size" and name ~= "CustomPhysicalProperties" then
					if name == "PivotOffset" and s ~= 1 then
						same(
							node.PivotOffset,
							encode(scaledLocal(frame(v.value), s)),
							r.path,
							name,
							TOL
						)
					else
						value(node, name, v, r.path, 1e-5)
					end
				end
			end
			check(
				equal(encode(node.CustomPhysicalProperties), encode(n.customPhysics), 1e-6),
				r.path,
				"Original explicit/default CustomPhysicalProperties changed"
			)
		end
		if r.mesh then
			local rep = replacements[r.key]
			if rep then
				meshTemplate(
					node,
					assert(rep.template, "Missing rebuilt native template " .. rep.id),
					rep.id,
					r.path
				)
				proof.counts.rebuiltMeshInstances += 1
			else
				for name, v in r.mesh do
					value(node, name, v, r.path)
				end
			end
		end
		if r.union then
			for name, v in r.union do
				value(node, name, v, r.path)
			end
		end
		if r.pivot then
			if op and op.pivot then
				same(node:GetPivot(), encode(frame(op.pivot)), r.path, "Desired Model pivot", TOL)
			elseif op and op.gateGround and node.PrimaryPart == nil then
				same(
					node:GetPivot(),
					encode(CFrame.new(table.unpack(op.gateGround))),
					r.path,
					"Gate ground pivot",
					TOL
				)
			else
				same(node:GetPivot(), r.pivot, r.path, "Original Model pivot", TOL)
			end
			same(node:GetScale(), op and op.scale or r.scale, r.path, "Model scale")
			check(
				node.PrimaryPart == n.primaryPart and node.ModelStreamingMode == n.streamingMode,
				r.path,
				"Original primary/streaming state changed"
			)
		end
		if r.attachment then
			local _, _, s = desiredGeometry(r)
			for name, v in r.attachment do
				if name == "CFrame" and s ~= 1 then
					same(
						node.CFrame,
						encode(scaledLocal(frame(v.value), s)),
						r.path,
						"Attachment local frame",
						TOL
					)
				elseif name ~= "WorldCFrame" then
					value(node, name, v, r.path, TOL)
				end
			end
		end
		if r.reference then
			check(
				node.Value == originals[r.reference.key],
				r.path,
				"Original ObjectValue target changed"
			)
		end
		if r.value and r.name ~= "InstalledFootprints" then
			for name, v in r.value do
				value(node, name, v, r.path)
			end
		end
		for _, group in
			{
				"prompt",
				"texture",
				"tiling",
				"surface",
				"gui",
				"text",
				"worldGui",
				"constraint",
				"joint",
				"jointFrames",
			}
		do
			if r[group] then
				for name, v in r[group] do
					value(node, name, v, r.path, 1e-5)
				end
			end
		end
		proof.counts[kind] += 1
	end
	for _, rows in
		{
			{ before.objects, "managed" },
			{ before.externalStaticObjects, "external" },
			{ before.protectedSourceAssets, "protected" },
		}
	do
		for _, r in rows[1] do
			run(r.path, function()
				verifyOriginal(r, rows[2])
			end)
		end
	end
	check(
		proof.counts.managed == 1555
			and proof.counts.protected == 1163
			and proof.counts.external == 2,
		"OriginalCounts",
		"Expected1555 managed/1163 protected/2 external verified originals"
	)
	run("EnvironmentPreservation", function()
		local priorFailureCount = #proof.failures
		for name, want in before.lighting do
			value(game.Lighting, name, want, "Lighting", 1e-6)
		end
		for name, want in before.streaming do
			value(workspace, name, want, "Streaming", 1e-6)
		end
		local effects = {}
		for _, r in before.effects do
			local node = assert(originals[r.key], "Original lighting effect missing " .. r.path)
			effects[node] = true
			check(
				node.Parent == game.Lighting
					and node.Name == r.name
					and node.ClassName == r.class
					and node.Archivable == r.archivable,
				"LightingEffects",
				"Original effect identity changed " .. r.path
			)
			local attrs = node:GetAttributes()
			for name, want in r.attributes do
				same(attrs[name], want, r.path, "Attribute " .. name)
			end
			for name in attrs do
				check(r.attributes[name] ~= nil, r.path, "Unexpected effect attribute " .. name)
			end
			check(tagsSame(r.tags, CS:GetTags(node)), r.path, "Original effect tags changed")
			for name, want in r.properties do
				value(node, name, want, r.path, 1e-6)
			end
		end
		for _, node in game.Lighting:GetChildren() do
			check(
				effects[node] == true,
				"LightingEffects",
				"Unexpected original environment child " .. node:GetFullName()
			)
		end
		local physics = game:GetService("PhysicsService")
		local actual = physics:GetRegisteredCollisionGroups()
		local expected = {}
		check(
			#actual == #before.collisionMatrix,
			"CollisionMatrix",
			"Registered collision group count changed"
		)
		for _, r in before.collisionMatrix do
			expected[r.name] = true
			for name, want in r.mask do
				check(
					physics:CollisionGroupsAreCollidable(r.name, name) == want,
					"CollisionMatrix",
					"Original collision rule changed " .. r.name .. "/" .. name
				)
			end
		end
		for _, r in actual do
			check(
				expected[r.name] == true,
				"CollisionMatrix",
				"Unexpected collision group " .. r.name
			)
		end
		proof.environment = {
			lightingPreserved = #proof.failures == priorFailureCount,
			effects = #before.effects,
			streamingPreserved = #proof.failures == priorFailureCount,
			collisionGroups = #actual,
		}
	end)
	for _, op in plan.operations do
		proof.counts.operations += 1
		if op.category == "RegionFloor" then
			proof.counts.floors += 1
		end
		if op.category == "RebuiltRoadSurface" then
			proof.counts.roads += 1
		end
		if op.category == "FittedBaseShell" then
			proof.counts.shells += 1
		end
		if op.category == "RetainedOuterContainment" then
			proof.counts.retainedOuter += 1
		end
		if op.retire then
			proof.counts.archivedShared += 1
		end
	end
	check(
		proof.counts.floors == 25
			and proof.counts.roads == 27
			and proof.counts.shells == 12
			and proof.counts.rebuiltMeshInstances == 63,
		"OriginalGeometry",
		"Expected25floor/27road/12shell/63rebuilt mesh instances"
	)
	check(
		proof.counts.retainedOuter == 10
			and proof.counts.archivedShared == 31
			and retired
			and #retired:GetChildren() == 31,
		"Separators",
		"Expected10 retained/31 archived original separators"
	)
	local wallFolder = map:FindFirstChild("RegionWalls")
	local actualWalls, maskById = {}, {}
	run("Walls", function()
		assert(wallFolder and wallFolder:IsA("Folder"), "RegionWalls missing")
		expectedNodes[wallFolder] = true
		check(
			wallFolder:GetAttribute("CompactMapMigrationId") == MIGRATION
				and wallFolder:GetAttribute("CompactMapDesiredHash") == plan.planHash,
			"Walls",
			"Wall folder ownership/hash differs"
		)
		check(
			#plan.walls == 54 and #wallFolder:GetChildren() == 54,
			"Walls",
			"Expected exactly54 new walls"
		)
		for _, w in plan.walls do
			local matches = {}
			for _, c in wallFolder:GetChildren() do
				if c.Name == w.id then
					table.insert(matches, c)
				end
			end
			assert(#matches == 1, "Expected one new wall " .. w.id)
			local node = matches[1]
			expectedNodes[node] = true
			meshTemplate(node, cube, "CompactWallCube_Unit", w.id)
			same(node.CFrame, encode(frame(w.cframe)), w.id, "Wall CFrame", TOL)
			same(node.Size, encode(vec(w.size)), w.id, "Wall Size", TOL)
			for name, want in
				{
					Anchored = true,
					CanCollide = true,
					CanQuery = true,
					CanTouch = false,
					CastShadow = true,
					Transparency = 0,
					Reflectance = 0,
					CollisionGroup = "Default",
					Material = Enum.Material.Glacier,
					MaterialVariant = "Bingus_Saved_Studs_13719188279",
					CollisionFidelity = Enum.CollisionFidelity.Box,
				}
			do
				same(node[name], encode(want), w.id, name)
			end
			same(
				node.Color,
				encode(Color3.fromRGB(table.unpack(w.tintRGB))),
				w.id,
				"Wall tint",
				1e-5
			)
			for name, want in
				{
					CompactMapMigrationId = MIGRATION,
					CompactMapDesiredHash = plan.planHash,
					StudsPerTile = 0.25,
					StudMaterialAssetId = 13719188279,
					RunId = w.runId,
					RegionPair = table.concat(w.regionPair, "|"),
				}
			do
				same(node:GetAttribute(name), want, w.id, "Attribute " .. name)
			end
			local b = bounds(node)
			maskById[w.id] = b
			table.insert(actualWalls, { id = w.id, bounds = b })
			proof.counts.newWalls += 1
		end
		for _, op in plan.operations do
			if op.category == "RetainedOuterContainment" then
				local node = originals[op.key]
				local id = "EXISTING_"
					.. op.path:match("ProgressionGates%.(.+)$"):gsub("%.BoundarySeparators%.", "_")
				maskById[id] = bounds(node)
			end
		end
		proof.wallPhysicalContacts = {}
		proof.maximumWallContactDepth = 0
		proof.maximumWallContactVolume = 0
		proof.wallPairsChecked = 0
		for i = 1, #actualWalls do
			for j = i + 1, #actualWalls do
				local first, second = actualWalls[i], actualWalls[j]
				local c = contact(first.bounds, second.bounds, TOL)
				proof.wallPairsChecked += 1
				proof.maximumWallContactDepth =
					math.max(proof.maximumWallContactDepth, c.minimumAxisDepth)
				proof.maximumWallContactVolume = math.max(proof.maximumWallContactVolume, c.volume)
				if c.volume > 0 then
					c.first = first.id
					c.second = second.id
					c.boundsFirst = first.bounds
					c.boundsSecond = second.bounds
					c.toleratedNativeSeam = not c.overlapsBeyondTolerance
					table.insert(proof.wallPhysicalContacts, c)
				end
				check(
					not c.overlapsBeyondTolerance,
					"WallIntersections",
					string.format(
						"Wall pair %s/%s penetrates XYZ %.9g/%.9g/%.9g studs, volume %.9g; every positive axis must exceed %.3g to be a forbidden overlap",
						first.id,
						second.id,
						c.depths.x,
						c.depths.y,
						c.depths.z,
						c.volume,
						TOL
					)
				)
			end
		end
	end)
	run("RuntimeGeometry", function()
		assert(
			type(options.runtimeJSON) == "string" and #options.runtimeJSON < 200000,
			"Bounded exact runtimeJSON required"
		)
		local raw = Http:JSONDecode(options.runtimeJSON)
		local node =
			assert(map:FindFirstChild("CompactMapRuntimeGeometry"), "Runtime StringValue missing")
		expectedNodes[node] = true
		check(
			node:IsA("StringValue") and node.Value == options.runtimeJSON,
			"RuntimeGeometry",
			"Installed exact runtime bytes differ"
		)
		check(
			node:GetAttribute("CompactMapMigrationId") == MIGRATION
				and node:GetAttribute("CompactMapDesiredHash") == plan.planHash,
			"RuntimeGeometry",
			"Runtime ownership/hash differs"
		)
		check(
			raw.migrationId == MIGRATION
				and raw.runtimeValidated == true
				and raw.planHash == plan.planHash,
			"RuntimeGeometry",
			"Unvalidated/mismatched runtime hash"
		)
		check(#raw.staticWallObstacles == 64, "RuntimeGeometry", "Expected64 wall mask rows")
		local seen = {}
		for _, r in raw.staticWallObstacles do
			check(not seen[r.id], "RuntimeGeometry", "Duplicate wall mask " .. r.id)
			seen[r.id] = true
			local b = maskById[r.id]
			check(b ~= nil, "RuntimeGeometry", "Unknown static wall mask " .. r.id)
			if b then
				for _, k in { "minX", "maxX", "minY", "maxY", "minZ", "maxZ" } do
					check(
						finite(r[k]) and math.abs(r[k] - b[k]) <= TOL,
						"RuntimeGeometry",
						"Actual wall AABB mismatch " .. r.id .. " " .. k
					)
				end
			end
			proof.counts.wallMaskRows += 1
		end
		for id in maskById do
			check(seen[id] == true, "RuntimeGeometry", "Missing physical wall mask " .. id)
		end
		local baseCount, serviceCount = 0, 0
		for id in raw.bases do
			baseCount += 1
			check(
				map.PlayerBasePatches:FindFirstChild(id) ~= nil,
				"RuntimeGeometry",
				"Unknown owner base " .. id
			)
		end
		-- Camp Rework (12 Nov 2026) removed the coloured service pads; only the invisible SellStall sale
		-- anchor remains (now under the new Sell counter) plus StallFootprint_* spawn exclusions.
		local campRework = map.MapArt:FindFirstChild("Services") ~= nil
			and map.MapArt.Services:FindFirstChild("Kiosk_SellStall") ~= nil
			and map.MapArt.Services.Kiosk_SellStall:GetAttribute("CampReworkStall") ~= nil
		for id in raw.services do
			serviceCount += 1
			check(
				map.ServiceStallPatches:FindFirstChild(id) ~= nil or (campRework and id ~= "SellStall"),
				"RuntimeGeometry",
				"Unknown owner service " .. id
			)
		end
		check(
			baseCount == 12 and serviceCount == 6,
			"RuntimeGeometry",
			"Expected12base/6service owner descriptors"
		)
	end)
	run("Footprints", function()
		local r = assert(
			byPath["Workspace.MapBlockout.MapArt.InstalledFootprints"],
			"Captured footprint cache missing"
		)
		local node = originals[r.key]
		local actual = Http:JSONDecode(node.Value)
		check(
			#actual == 343 and equal(actual, plan.artFootprints, TOL),
			"Footprints",
			"343 installed canonical footprint rows differ"
		)
	end)
	run("ServiceSupport", function()
		local patches = map.ServiceStallPatches
		local services = map.MapArt:FindFirstChild("Services")
		local sellStall = services and services:FindFirstChild("Kiosk_SellStall")
		if sellStall and sellStall:GetAttribute("CampReworkStall") ~= nil then
			-- Camp Rework: SellSignSupport (and the legacy SELL BRAINROTS board it held) were removed;
			-- the new Sell stall has its own sign. The sale anchor must sit under its counter, invisible.
			local anchor = patches:FindFirstChild("SellStall")
			check(anchor ~= nil and anchor.Transparency == 1 and anchor.CanCollide == false, "ServiceSupport",
				"Camp Rework sale anchor missing or visible/colliding")
			check(patches:FindFirstChild("SellSignSupport") == nil, "ServiceSupport", "Removed sign support came back")
			return
		end
		local service = patches.SellStall
		local node = assert(patches:FindFirstChild("SellSignSupport"), "Sell sign support missing")
		expectedNodes[node] = true
		check(
			node.ClassName == "Part"
				and node:GetAttribute("CompactMapMigrationId") == MIGRATION
				and node:GetAttribute("CompactMapDesiredHash") == plan.planHash,
			"ServiceSupport",
			"Support owner/class/hash differs"
		)
		same(
			node.CFrame,
			encode(service.CFrame * CFrame.new(-20, 0, 20.477256774902344)),
			"ServiceSupport",
			"Support CFrame",
			TOL
		)
		same(
			node.Size,
			encode(Vector3.new(6, service.Size.Y, 5)),
			"ServiceSupport",
			"Support Size",
			TOL
		)
		for _, name in
			{
				"CanCollide",
				"CanQuery",
				"CanTouch",
				"Color",
				"Material",
				"MaterialVariant",
				"CustomPhysicalProperties",
			}
		do
			same(node[name], encode(service[name]), "ServiceSupport", name)
		end
		check(
			node.Anchored
				and node:GetAttribute("StudsPerTile") == 0.25
				and node:GetAttribute("StudMaterialAssetId") == 13719188279,
			"ServiceSupport",
			"Support anchored/studs contract"
		)
	end)

	run("RegionalFloorUnions", function()
		local groups = {}
		for _, op in plan.operations do
			if op.category == "RegionFloor" then
				local r = byKey[op.key]
				local parent = originals[r.parent]
				groups[parent] = groups[parent] or {}
				table.insert(groups[parent], bounds(originals[op.key]))
			end
		end
		local regions = 0
		for parent, boxes in pairs(groups) do
			regions += 1
			local loX, hiX, loZ, hiZ = math.huge, -math.huge, math.huge, -math.huge
			local edges, seen = {}, {}
			for _, b in boxes do
				loX = math.min(loX, b.minX)
				hiX = math.max(hiX, b.maxX)
				loZ = math.min(loZ, b.minZ)
				hiZ = math.max(hiZ, b.maxZ)
				for _, x in { b.minX, b.maxX } do
					if not seen[x] then
						seen[x] = true
						table.insert(edges, x)
					end
				end
			end
			table.sort(edges)
			local area = 0
			for i = 1, #edges - 1 do
				local a, b = edges[i], edges[i + 1]
				local intervals = {}
				for _, box in boxes do
					if box.minX < b and box.maxX > a then
						table.insert(intervals, { box.minZ, box.maxZ })
					end
				end
				table.sort(intervals, function(left, right)
					return left[1] < right[1]
				end)
				local low, high, length = nil, nil, 0
				for _, interval in intervals do
					if low == nil then
						low, high = interval[1], interval[2]
					elseif interval[1] <= high then
						high = math.max(high, interval[2])
					else
						length += high - low
						low, high = interval[1], interval[2]
					end
				end
				if low then
					length += high - low
				end
				area += (b - a) * length
			end
			local originX, originZ = map:GetAttribute("OriginX"), map:GetAttribute("OriginZ")
			same(
				parent:GetAttribute("BoundsMin"),
				encode(Vector3.new(loX - originX, 0, loZ - originZ)),
				parent:GetFullName(),
				"Actual floor union lower bounds",
				TOL
			)
			same(
				parent:GetAttribute("BoundsMax"),
				encode(Vector3.new(hiX - originX, 0, hiZ - originZ)),
				parent:GetFullName(),
				"Actual floor union upper bounds",
				TOL
			)
			check(
				math.abs(parent:GetAttribute("NavigableFloorArea") - area)
					<= math.max(0.25, area * 1e-5),
				parent:GetFullName(),
				"Actual floor union area differs from region descriptor"
			)
		end
		check(regions == 8, "RegionalFloorUnions", "Expected8 physical region unions")
		proof.regionFloorUnions = regions
	end)
	if options.routeDraft then
		run("Crossings", function()
			local draft = options.routeDraft
			check(
				draft.baselineManagedContentSHA256 == BASELINE
					and equal(draft.candidate, plan.candidate, 1e-6),
				"Crossings",
				"Route draft not same frozen candidate"
			)
			check(
				equal(draft.walls, plan.walls, 1e-6),
				"Crossings",
				"Desired walls differ from classified aperture draft"
			)
			check(
				draft.routeConnectivity.count == 1,
				"Crossings",
				"Canonical route surface source has disconnected components"
			)
			check(
				#draft.connectivityCaps == 26 and #draft.gateAprons == 6,
				"Crossings",
				"Expected26 connectivity caps/six gate aprons"
			)
			check(
				#draft.approvedOpeningPolygons == 7 and #draft.crossings == 12,
				"Crossings",
				"Expected7 aperture owners/12 route crossings"
			)
			local paid, closed, free = 0, 0, 0
			for _, c in draft.crossings do
				if c.accessPolicy == "ExistingPaidGate" then
					paid += 1
					check(
						c.clearWidth == 24 and c.owningGate ~= nil,
						"Crossings",
						"Paid24clear aperture owner missing"
					)
				elseif c.accessPolicy == "ExistingEquivalentRestriction" then
					closed += 1
					check(c.apertureWidth == 0, "Crossings", "Closed alternate gained aperture")
				else
					free += 1
				end
			end
			check(
				paid == 6 and closed == 5 and free == 1,
				"Crossings",
				"Crossing access classification changed"
			)
			for _, o in draft.approvedOpeningPolygons do
				for _, p in o.polygons do
					for _, w in actualWalls do
						check(
							polygonInBounds(p, w.bounds) <= 1e-4,
							"Crossings",
							"Actual wall intrudes full-thickness opening " .. o.id .. "/" .. w.id
						)
					end
				end
			end
			proof.crossings = {
				paid = paid,
				closed = closed,
				free = free,
				openingOwners = 7,
				fullThicknessOpeningWallIntersectionsChecked = true,
			}
		end)
	else
		check(
			false,
			"Crossings",
			"options.routeDraft required for classified full-thickness opening verification"
		)
	end
	run("RemainingSources", function()
		local untouched, patched = 0, 0
		for _, s in assert(shared.CompactMapSources, "Frozen sources missing") do
			local node = assert(originals[s.key], "Original source reference missing " .. s.path)
			check(
				node.ClassName == s.class and node.Name == s.name and node:GetFullName() == s.path,
				"RemainingSources",
				"Original source identity/parent changed " .. s.path
			)
			if s.enabled ~= nil then
				check(
					node.Enabled == s.enabled and tostring(node.RunContext) == s.runContext,
					"RemainingSources",
					"Original script activation changed " .. s.path
				)
			end
			if PATCHED[s.path] then
				patched += 1
			else
				check(
					node.Source == s.source,
					"RemainingSources",
					"Unpatched live source changed " .. s.path
				)
				untouched += 1
			end
		end
		check(
			patched == 5 and untouched == 351,
			"RemainingSources",
			"Expected5patched/351 untouched original owners"
		)
		proof.counts.unpatchedSources = untouched
		local src = assert(options.sourceAPI, "Source owner verifier required").Verify()
		check(
			src.passed == true and src.exactPatchedOwners == 5 and src.newOwnerCount == 1,
			"SourceOwners",
			"Exact5patched/new utility source verification failed"
		)
		proof.sourceOwners = src
	end)
	run("UnexpectedWorldInstances", function()
		for _, node in map:GetDescendants() do
			check(
				expectedNodes[node] == true,
				"WorldOwnership",
				"Unexpected new/unclassified map descendant " .. node:GetFullName()
			)
		end
	end)
	proof.passed = #proof.failures == 0
	proof.status = if proof.passed then "Passed" else "Failed"
	proof.failureSummary = if proof.passed
		then ""
		else string.format(
			"%d failures; first: %s: %s",
			#proof.failures,
			proof.failures[1].scope,
			proof.failures[1].message
		)
	proof.nativeAssets = {
		groups = 31,
		triangles = tris,
		corners = corners,
		canonicalSourceSHA256 = CANONICAL,
		studioImportSHA256 = IMPORT,
		roadGeometryHash = ROAD_HASH,
	}
	if not proof.passed then
		warn("CompactMap static Verify " .. proof.failureSummary)
	end
	return proof
end
API.Contact = contact
API.Equal = equal
API.Bounds = bounds
API.PolygonInBounds = polygonInBounds
return API
