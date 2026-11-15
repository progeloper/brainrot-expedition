--!nocheck
-- Detached, root-executed DEV Edit transaction. No Source assignments, gameplay requires or publication APIs.
local A = {}
local OWNER, VARIANT = "BR_EnvironmentArt_V2", "Bingus_Saved_Studs_13719188279"
local function hash(s)
	return type(s) == "string" and #s == 64 and s:match("^[0-9a-f]+$")
end
local function cf(a)
	assert(type(a) == "table" and #a == 12, "Full CFrame required")
	return CFrame.new(table.unpack(a))
end
local function vec(a)
	assert(type(a) == "table" and #a == 3, "Full XYZ required")
	return Vector3.new(table.unpack(a))
end
local function multiply(a, b)
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
local function rgb(a)
	assert(type(a) == "table" and #a == 3, "Exact RGB palette required")
	return Color3.fromRGB(a[1], a[2], a[3])
end
local function primitiveBounds(frame, size)
	local ext = Vector3.new(
		math.abs(frame.RightVector.X) * size.X
			+ math.abs(frame.UpVector.X) * size.Y
			+ math.abs(frame.LookVector.X) * size.Z,
		math.abs(frame.RightVector.Y) * size.X
			+ math.abs(frame.UpVector.Y) * size.Y
			+ math.abs(frame.LookVector.Y) * size.Z,
		math.abs(frame.RightVector.Z) * size.X
			+ math.abs(frame.UpVector.Z) * size.Y
			+ math.abs(frame.LookVector.Z) * size.Z
	) / 2
	local lo, hi = frame.Position - ext, frame.Position + ext
	return { minX = lo.X, maxX = hi.X, minY = lo.Y, maxY = hi.Y, minZ = lo.Z, maxZ = hi.Z }
end
local function mergeBounds(total, one)
	if not total then
		return one
	end
	for n, v in one do
		total[n] = if n:sub(1, 3) == "min" then math.min(total[n], v) else math.max(total[n], v)
	end
	return total
end
local function nativeTransform(root, unit, size, scale)
	assert(
		(unit.UpVector - Vector3.yAxis).Magnitude < 0.001
			and math.abs(math.abs(unit.RightVector.X) + math.abs(unit.RightVector.Z) - 1) < 0.001,
		"Native group frame must be canonical/cardinal; no scaled shear"
	)
	local offset = multiply(unit.Position, scale)
	local sx = math.abs(unit.RightVector.X) * scale.X
		+ math.abs(unit.RightVector.Y) * scale.Y
		+ math.abs(unit.RightVector.Z) * scale.Z
	local sy = math.abs(unit.UpVector.X) * scale.X
		+ math.abs(unit.UpVector.Y) * scale.Y
		+ math.abs(unit.UpVector.Z) * scale.Z
	local sz = math.abs(unit.LookVector.X) * scale.X
		+ math.abs(unit.LookVector.Y) * scale.Y
		+ math.abs(unit.LookVector.Z) * scale.Z
	return root * CFrame.new(offset) * unit.Rotation, Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
end
local function decoded(value, baseline, layer)
	if type(value) ~= "table" or not value.type then
		return value
	end
	local t, v = value.type, value.value
	if t == "nil" then
		return nil
	end
	if t == "Color3" then
		return Color3.new(table.unpack(v))
	end
	if t == "CFrame" then
		return cf(v)
	end
	if t == "Vector3" then
		return vec(v)
	end
	if t == "OwnedInstance" then
		assert(layer, "Controlled owned target requires stage/layer")
		local found
		for _, node in layer:GetDescendants() do
			if
				node:IsA("Part")
				and node.Name == value.ownedChildId
				and node:GetAttribute("EnvironmentId") == value.ownerRowId
			then
				assert(not found, "Ambiguous owned target")
				found = node
			end
		end
		assert(found and found:GetAttribute("EnvironmentRole") == "VisibleSignFace", "Owned sign target missing")
		return found
	end
	if t == "Instance" then
		return assert(baseline.refs[value.key], "Captured reference missing")
	end
	error("Unsupported approved property/attribute delta type " .. t)
end
local function setOwned(part, row, role)
	part:SetAttribute("ArtOwner", OWNER)
	part:SetAttribute("ArtVersion", 2)
	part:SetAttribute("EnvironmentId", row.id)
	part:SetAttribute("EnvironmentRole", role)
	part.Anchored = true
	part.CanTouch = false
	part.CollisionGroup = "Default"
	part.Material = Enum.Material.Glacier
	part.MaterialVariant = VARIANT
	part.Reflectance = 0
	part:SetAttribute("SurfaceStyle", "SavedBingusStuds")
	part:SetAttribute("StudsPerTile", 0.25)
	part:SetAttribute("StudMaterialAssetId", 13719188279)
	part:SetAttribute("MapArtStaticStudMaterial", true)
	for _, tag in game:GetService("CollectionService"):GetTags(part) do
		game:GetService("CollectionService"):RemoveTag(part, tag)
	end
end
local function writeJSON(parent, name, text, Audit)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	local chunks = Audit.UTF8Chunks(text)
	folder:SetAttribute("Bytes", #text)
	folder:SetAttribute("ChunkCount", #chunks)
	for i, chunk in chunks do
		local node = Instance.new("StringValue")
		node.Name = string.format("Chunk_%04d", i)
		node.Value = chunk
		node.Parent = folder
	end
	return folder
end
local function readJSON(parent, name)
	local folder = assert(parent:FindFirstChild(name), "Persistent rollback JSON missing")
	local nodes = folder:GetChildren()
	table.sort(nodes, function(a, b)
		return a.Name < b.Name
	end)
	local chunks = {}
	for i, node in nodes do
		assert(
			node.ClassName == "StringValue" and node.Name == string.format("Chunk_%04d", i),
			"Rollback chunks noncontiguous"
		)
		chunks[i] = node.Value
	end
	local text = table.concat(chunks)
	assert(
		#text == folder:GetAttribute("Bytes") and #chunks == folder:GetAttribute("ChunkCount"),
		"Rollback bytes incomplete"
	)
	return game:GetService("HttpService"):JSONDecode(text)
end
local function preflightNative(options)
	local proof = options.nativeProof
	assert(
		proof and proof.passed == true and proof.completeBatch == true and hash(proof.sourceSHA256),
		"Complete actual native import proof required"
	)
	local proofGroups = {}
	for _, group in proof.groups do
		assert(group.passed == true and group.complete == true, "Incomplete native group proof")
		local key = group.prototypeId .. "/" .. group.exportGroup
		assert(not proofGroups[key], "Duplicate native group evidence")
		proofGroups[key] = group
	end
	for key, expected in options.expectedNative do
		local original = assert(options.nativeAssets[key], "Missing native group " .. key)
		local group = assert(proofGroups[key], "No actual proof for " .. key)
		assert(
			original:IsA("MeshPart") and original:IsDescendantOf(game:GetService("ServerStorage")),
			"Genuine normalized unit meshes must remain in owned ServerStorage"
		)
		assert(
			original.MeshId == expected.meshId and group.meshId == expected.meshId and original.MeshId ~= "",
			"Actual proof/template/descriptor MeshId mismatch"
		)
		assert(
			expected.triangles == group.actualTriangles and expected.sourceSHA256 == proof.sourceSHA256,
			"Exact final source/triangle binding"
		)
		assert(
			options.auditAPI.Equal({ original.CFrame:GetComponents() }, expected.localCFrame, 0.001)
				and (original.Size - vec(expected.size)).Magnitude <= 0.001,
			"Actual canonical template frame/size mismatch"
		)
		assert(
			#original:GetChildren() == 0,
			"Normalize imported mesh groups to script/texture/helper-free units before cloning"
		)
	end
end
local function verificationOptions(options, layer, archive, expectedBounds)
	return {
		auditAPI = options.auditAPI,
		baseline = options.baseline,
		manifest = options.manifest,
		layerRoot = layer,
		nativeProof = options.nativeProof,
		nativeAssets = options.nativeAssets,
		expectedNative = options.expectedNative,
		archiveParent = archive,
		archiveParents = options.archiveParents,
		propertyChanges = options.propertyChanges,
		attributeChanges = options.attributeChanges,
		allowBibleAlbedoEdits = options.allowBibleAlbedoEdits,
		expectedBounds = expectedBounds,
	}
end
local function currentOriginalRecord(baseline, key)
	local node = assert(baseline.refs[key], "Missing reviewed original ref")
	return node
end
local function rollback(journal, baseline)
	local errors = {}
	local function attempt(label, fn)
		local ok, why = pcall(fn)
		if not ok then
			table.insert(errors, label .. ": " .. tostring(why))
		end
	end
	local deltas = if journal:GetAttribute("MutationStarted") == true then readJSON(journal, "BeforeDeltas") else {}
	for i = #deltas, 1, -1 do
		local delta = deltas[i]
		local node = baseline.refs[delta.key]
		attempt(delta.key, function()
			assert(node, "Rollback identity missing")
			if delta.kind == "Property" then
				node[delta.name] = decoded(delta.value, baseline)
			elseif delta.kind == "Attribute" then
				node:SetAttribute(delta.name, decoded(delta.value, baseline))
			else
				error("Unknown rollback delta")
			end
		end)
	end
	for _, ref in if journal:GetAttribute("MutationStarted") == true then journal.OriginalParents:GetChildren() else {} do
		attempt(ref.Name, function()
			local key = ref:GetAttribute("OriginalKey")
			local parent = ref.Value
			local node = assert(baseline.refs[key], "Archived original missing")
			assert(parent, "Original parent missing")
			node.Parent = parent
		end)
	end
	local installed = journal:FindFirstChild("InstalledLayerRef")
	if installed and installed.Value then
		attempt("Owned installed layer", function()
			assert(installed.Value:GetAttribute("ArtOwner") == OWNER, "Wrong layer owner")
			installed.Value:Destroy()
		end)
	end
	local stage = journal:FindFirstChild("StageRef")
	if stage and stage.Value then
		attempt("Owned staged layer", function()
			assert(stage.Value:GetAttribute("ArtOwner") == OWNER, "Wrong stage owner")
			stage.Value:Destroy()
		end)
	end
	journal:SetAttribute("Status", if #errors == 0 then "RolledBack" else "RollbackIncomplete")
	return { passed = #errors == 0, status = journal:GetAttribute("Status"), errors = errors, originalSourceWrites = 0 }
end
function A.Rollback(options)
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"DEV Edit rollback only"
	)
	assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Wrong DEV")
	local journal = assert(options.journal, "Pass exact owned journal")
	assert(
		journal:GetAttribute("ArtOwner") == OWNER and journal:IsDescendantOf(game:GetService("ServerStorage")),
		"Wrong rollback owner/location"
	)
	local baseline = options.baseline or assert(shared.EnvironmentV2Baseline, "Baseline required")
	local restored = rollback(journal, baseline)
	if options.verifyAPI and options.auditAPI then
		restored.originalBaseline = options.verifyAPI.Preserve({
			auditAPI = options.auditAPI,
			baseline = baseline,
			manifest = {
				migrationId = OWNER,
				baselineSceneSHA256 = baseline.sceneSHA256,
				archive = {},
				boundaryArchive = {},
			},
		})
		restored.passed = restored.passed and restored.originalBaseline.passed
	end
	return restored
end
function A.Apply(options)
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"DEV Edit installation only"
	)
	assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Wrong DEV")
	options.baseline = options.baseline or assert(shared.EnvironmentV2Baseline, "Fresh bound baseline required")
	local baseline, Audit, Verify =
		options.baseline,
		assert(options.auditAPI, "Audit API required"),
		assert(options.verifyAPI, "Verify API required")
	local manifest = assert(options.manifest, "Exact frozen layout required")
	local desired = options.manifestHash
	assert(
		hash(desired)
			and manifest.migrationId == OWNER
			and manifest.applyEligible == true
			and manifest.baselineSceneSHA256 == baseline.sceneSHA256,
		"Exact frozen baseline/desired binding required"
	)
	assert(
		type(options.manifestJSON) == "string"
			and Audit.Equal(game:GetService("HttpService"):JSONDecode(options.manifestJSON), manifest, 0),
		"Persist exact same reviewed manifest JSON"
	)
	local map = baseline.map
	assert(map == workspace:FindFirstChild("MapBlockout"), "Original reduced map identity required")
	local layerName = options.layerName or "EnvironmentArt_V2"
	local existing = map:FindFirstChild(layerName)
	if existing then
		assert(
			existing:GetAttribute("ArtOwner") == OWNER
				and existing:GetAttribute("EnvironmentV2Hash") == desired
				and existing:GetAttribute("EnvironmentV2Status") == "Completed",
			"Existing different/incomplete environment must not be overwritten"
		)
		local journal = assert(
			game:GetService("ServerStorage"):FindFirstChild("EnvironmentV2_Journal_" .. desired:sub(1, 12)),
			"Existing committed journal missing"
		)
		local boundsById = readJSON(journal, "ExpectedBounds")
		local proof = Verify.Verify(verificationOptions(options, existing, journal.Archive, boundsById))
		assert(proof.passed, "Idempotent verification failed; no writes performed")
		return {
			status = "Retained",
			proof = proof,
			geometryWrites = 0,
			sourceWrites = 0,
			colorWrites = 0,
			metadataWrites = 0,
			archiveWrites = 0,
			newInstances = 0,
		}
	end
	preflightNative(options)
	-- Baseline-only preflight cannot approve unreviewed mutations before installation.
	local clean = {
		schemaVersion = 2,
		migrationId = OWNER,
		baselineSceneSHA256 = baseline.sceneSHA256,
		archive = {},
		boundaryArchive = {},
	}
	local before = Verify.Preserve({ auditAPI = Audit, baseline = baseline, manifest = clean })
	assert(before.passed, "Original fresh baseline changed; invalidate plan before staging")
	local SS = game:GetService("ServerStorage")
	local journalName = "EnvironmentV2_Journal_" .. desired:sub(1, 12)
	assert(
		not SS:FindFirstChild(journalName),
		"Prior transaction journal exists; inspect/rollback rather than overwrite"
	)
	local journal, stage, installedRef, archive, parents
	local setupNodes = {}
	local function owned(className)
		local node = Instance.new(className)
		table.insert(setupNodes, node)
		return node
	end
	local setupOK, setupError = xpcall(function()
		journal = owned("Folder")
		journal.Name = journalName
		journal:SetAttribute("ArtOwner", OWNER)
		journal:SetAttribute("NoRuntimeUse", true)
		journal:SetAttribute("EnvironmentV2Hash", desired)
		journal:SetAttribute("BaselineSceneSHA256", baseline.sceneSHA256)
		journal:SetAttribute("Status", "Preparing")
		journal.Parent = SS
		stage = owned("Folder")
		stage.Name = layerName
		stage:SetAttribute("ArtOwner", OWNER)
		stage:SetAttribute("ArtVersion", 2)
		stage:SetAttribute("EnvironmentV2Hash", desired)
		stage:SetAttribute("EnvironmentV2Status", "Staged")
		stage.Parent = journal
		local stageRef = owned("ObjectValue")
		stageRef.Name = "StageRef"
		stageRef.Value = stage
		stageRef.Parent = journal
		installedRef = owned("ObjectValue")
		installedRef.Name = "InstalledLayerRef"
		installedRef.Parent = journal
		archive = owned("Folder")
		archive.Name = "Archive"
		archive:SetAttribute("ArtOwner", OWNER)
		archive:SetAttribute("NoRuntimeUse", true)
		archive.Parent = journal
		parents = owned("Folder")
		parents.Name = "OriginalParents"
		parents.Parent = journal
	end, debug.traceback)
	if not setupOK then
		local errors = {}
		for i = #setupNodes, 1, -1 do
			local removed, reason = pcall(function()
				setupNodes[i]:Destroy()
			end)
			if not removed then
				table.insert(errors, tostring(reason))
			end
		end
		local cleanProof = Verify.Preserve({ auditAPI = Audit, baseline = baseline, manifest = clean })
		assert(
			#errors == 0 and cleanProof.passed,
			"Owned setup cleanup failed; originals were not intentionally written"
		)
		return {
			status = "FailedBeforeStaging",
			reason = tostring(setupError),
			cleanupPassed = true,
			originalBaselineAfterCleanup = cleanProof,
			worldWrites = 0,
			sourceWrites = 0,
			fullAcceptancePassed = false,
		}
	end
	local expectedBounds, deltas = {}, {}
	local writes = { geometry = 0, color = 0, metadata = 0, archives = 0 }
	local proof
	local ok, reason = xpcall(function()
		writeJSON(journal, "Manifest", options.manifestJSON, Audit)
		writeJSON(journal, "NativeProof", game:GetService("HttpService"):JSONEncode(options.nativeProof), Audit)
		writeJSON(journal, "ExpectedNative", game:GetService("HttpService"):JSONEncode(options.expectedNative), Audit)
		local archives = {}
		for _, row in manifest.archive or {} do
			table.insert(archives, row)
		end
		for _, row in manifest.boundaryArchive or {} do
			table.insert(archives, row)
		end
		local allowed = verificationOptions(options, stage, archive, expectedBounds)
		allowed.validateChangesOnly = true
		local allowedProof = Verify.Preserve(allowed)
		assert(allowedProof.passed, "Unapproved exception scope; no original mutations started")
		local seen = {}
		for i, row in archives do
			assert(not seen[row.originalKey], "Duplicate archive root")
			seen[row.originalKey] = true
			local node = currentOriginalRecord(baseline, row.originalKey)
			local ref = Instance.new("ObjectValue")
			ref.Name = string.format("Parent_%04d", i)
			ref:SetAttribute("OriginalKey", row.originalKey)
			ref.Value = node.Parent
			ref.Parent = parents
		end
		for key, changes in options.propertyChanges or {} do
			local node = currentOriginalRecord(baseline, key)
			local current = Audit.Record(node, function(ref)
				for k, n in baseline.refs do
					if n == ref then
						return k
					end
				end
				error("Unknown original property ref")
			end)
			for field in changes do
				table.insert(deltas, { kind = "Property", key = key, name = field, value = current.properties[field] })
			end
		end
		for key, changes in options.attributeChanges or {} do
			local node = currentOriginalRecord(baseline, key)
			local current = Audit.Record(node, function(ref)
				for k, n in baseline.refs do
					if n == ref then
						return k
					end
				end
				error("Unknown original attribute ref")
			end)
			for field in changes do
				table.insert(deltas, {
					kind = "Attribute",
					key = key,
					name = field,
					value = current.attributes[field] or { type = "nil" },
				})
			end
		end
		writeJSON(journal, "BeforeDeltas", game:GetService("HttpService"):JSONEncode(deltas), Audit)
		for _, row in manifest.objects do
			if not row.existingOriginalKey then
				local model = Instance.new("Model")
				model.Name = row.id
				model:SetAttribute("ArtOwner", OWNER)
				model:SetAttribute("ArtVersion", 2)
				model:SetAttribute("EnvironmentId", row.id)
				model:SetAttribute("PrototypeId", row.prototypeId)
				model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
				model.Parent = stage
				local root, scale = cf(row.rootCFrame), vec(row.axisScale)
				assert(scale.X > 0 and scale.Y > 0 and scale.Z > 0, "Positive approved axis scale")
				local groups = row.meshGroups or row.meshGroupIds
				if row.role == "Motif" then
					local descriptor = assert(row.motif, "Optional motif requires exact world box descriptor")
					local part = Instance.new("Part")
					part.Parent = model
					part.Name = row.id .. "_Surface"
					part.Shape = Enum.PartType.Block
					part.CFrame = cf(descriptor.cframe)
					part.Size = vec(descriptor.size)
					setOwned(part, row, "Visible")
					part.Transparency = 0
					part.LocalTransparencyModifier = 0
					part.CanCollide = false
					part.CanQuery = false
					part.CastShadow = false
					part.Color = rgb(descriptor.color)
					part:SetAttribute("PrototypeId", row.prototypeId)
					part:SetAttribute("SourceTriangles", 12)
					part:SetAttribute("SourceSHA256", options.nativeProof.sourceSHA256)
					expectedBounds[row.id] = primitiveBounds(cf(descriptor.cframe), vec(descriptor.size))
					writes.geometry += 1
					groups = {}
				else
					assert(
						type(groups) == "table" and #groups > 0,
						"Every assembly needs exact normalized meshGroups; no guessed groups"
					)
				end
				local sourceGroups = {}
				for _, spec in groups do
					local prototype = spec.prototypeId or row.prototypeId
					local groupId = spec.exportGroup or spec.groupId
					local key = prototype .. "/" .. groupId
					local expected = assert(options.expectedNative[key], "Expected actual unit group missing")
					local original = assert(options.nativeAssets[key], "Native imported asset missing")
					local part = original:Clone()
					part.Parent = model
					part.Name = prototype .. "_" .. groupId
					local transform, size = nativeTransform(root, cf(expected.localCFrame), vec(expected.size), scale)
					part.CFrame = transform
					part.Size = size
					part.PivotOffset = CFrame.identity
					setOwned(part, row, "Visible")
					part.Transparency = 0
					part.LocalTransparencyModifier = 0
					part.CanCollide = false
					part.CanQuery = false
					part.TextureID = ""
					part.DoubleSided = false
					part:SetAttribute("PrototypeId", prototype)
					part:SetAttribute("ExportGroup", groupId)
					part:SetAttribute("SourceSHA256", options.nativeProof.sourceSHA256)
					part:SetAttribute("SourceTriangles", expected.triangles)
					part:SetAttribute("ImportedMeshId", part.MeshId)
					part.Color = rgb(Verify.PaletteRGB(spec, row))
					part.CastShadow = row.role == "Hero"
						or row.role == "Boundary"
						or row.role == "Burrow"
						or (row.role == "Tree" and groupId == "A")
					part.RenderFidelity = Enum.RenderFidelity.Automatic
					sourceGroups[key] = part
					expectedBounds[row.id] = mergeBounds(expectedBounds[row.id], primitiveBounds(transform, size))
					writes.geometry += 1
				end
				if row.signFaceProxy then
					local descriptor = row.signFaceProxy
					assert(
						descriptor.sourceRole == "SignFace"
							and descriptor.sourceTriangles == 12
							and descriptor.size[1] == 16
							and descriptor.size[2] == 5
							and descriptor.size[3] == 0.1,
						"Exact approved sign proxy dimensions required"
					)
					local part = Instance.new("Part")
					part.Parent = model
					part.Name = descriptor.id
					part.Shape = Enum.PartType.Block
					part.CFrame = cf(descriptor.cframe)
					part.Size = vec(descriptor.size)
					setOwned(part, row, "VisibleSignFace")
					part.Transparency = 0
					part.LocalTransparencyModifier = 0
					part.CanCollide = false
					part.CanQuery = false
					part.CastShadow = false
					part.Color = rgb(Verify.PaletteRGB(descriptor, row))
					part:SetAttribute("SourceTriangles", 12)
					part:SetAttribute("SourceSHA256", options.nativeProof.sourceSHA256)
					part:SetAttribute("PrototypeId", "GateSignFace")
					expectedBounds[row.id] =
						mergeBounds(expectedBounds[row.id], primitiveBounds(part.CFrame, part.Size))
					writes.geometry += 1
				end
				for _, box in row.colliders or {} do
					local part = Instance.new("Part")
					part.Parent = model
					part.Name = box.id
					part.Shape = Enum.PartType.Block
					part.CFrame = cf(box.cframe)
					part.Size = vec(box.size)
					setOwned(part, row, "Collider")
					part:SetAttribute("EnvironmentColliderId", box.id)
					part.Transparency = 1
					part.CanCollide = true
					part.CanQuery = true
					part.CastShadow = false
					writes.geometry += 1
				end
				for _, marker in row.markers or {} do
					local parent = assert(sourceGroups["BurrowCore/A"], "Markers require real imported CoreA")
					local node = Instance.new("Attachment")
					node.Parent = parent
					node.Name = marker.name
					local world = if marker.worldCFrame
						then cf(marker.worldCFrame)
						else select(
							1,
							nativeTransform(
								root,
								cf(assert(marker.localCFrame, "Exact marker frame required")),
								Vector3.zero,
								scale
							)
						)
					node.CFrame = parent.CFrame:ToObjectSpace(world)
					node:SetAttribute("Art_BurrowId", row.id)
					node:SetAttribute("Art_RegionKey", row.regionId)
					node:SetAttribute("Art_InterfaceVersion", 1)
					node:SetAttribute("Art_RuntimeRegistered", false)
				end
				model.WorldPivot = root
			end
		end
		writeJSON(journal, "ExpectedBounds", game:GetService("HttpService"):JSONEncode(expectedBounds), Audit)
		journal:SetAttribute("Status", "Installing")
		journal:SetAttribute("MutationStarted", true)
		-- All inverse operations already exist before the first original-parent/property write.
		for _, row in archives do
			local node = currentOriginalRecord(baseline, row.originalKey)
			node.Parent = archive
			writes.archives += 1
		end
		for key, changes in options.propertyChanges or {} do
			local node = currentOriginalRecord(baseline, key)
			for name, value in changes do
				node[name] = decoded(value, baseline, stage)
				if name == "Color" then
					writes.color += 1
				else
					writes.metadata += 1
				end
			end
		end
		for key, changes in options.attributeChanges or {} do
			local node = currentOriginalRecord(baseline, key)
			for name, value in changes do
				node:SetAttribute(name, decoded(value, baseline))
				writes.metadata += 1
			end
		end
		stage.Parent = map
		installedRef.Value = stage
		stage:SetAttribute("EnvironmentV2Status", "Completed")
		proof = Verify.Verify(verificationOptions(options, stage, archive, expectedBounds))
		assert(
			proof.passed,
			"Static preservation/layer verification failed: " .. game:GetService("HttpService"):JSONEncode(proof)
		)
		writeJSON(journal, "InstallationProof", game:GetService("HttpService"):JSONEncode(proof), Audit)
		journal:SetAttribute("Status", "Completed")
	end, debug.traceback)
	if not ok then
		local rollbackProof = rollback(journal, baseline)
		local cleanProof = Verify.Preserve({ auditAPI = Audit, baseline = baseline, manifest = clean })
		local failure = {
			status = "FailedAndRolledBack",
			reason = tostring(reason),
			rollback = rollbackProof,
			originalBaselineAfterRollback = cleanProof,
			sourceWrites = 0,
			fullAcceptancePassed = false,
		}
		writeJSON(journal, "FailureProof", game:GetService("HttpService"):JSONEncode(failure), Audit)
		assert(
			rollbackProof.passed and cleanProof.passed,
			"Automatic rollback incomplete; inspect owned journal, do not force another install"
		)
		return failure
	end
	return {
		status = if manifest.triangleBudgetException and #(manifest.unplacedMandatory or {}) == 1
			then "ImplementedWithDocumentedCampAndBudgetExceptions"
			elseif manifest.triangleBudgetException then "ImplementedWithDocumentedBudgetException"
			elseif #(manifest.unplacedMandatory or {}) == 1 then "ImplementedWithDocumentedCampConflict"
			else "ImplementedStaticCandidate",
		journal = journal:GetFullName(),
		layer = stage:GetFullName(),
		manifestHash = desired,
		proof = proof,
		geometryWrites = writes.geometry,
		colorWrites = writes.color,
		metadataWrites = writes.metadata,
		archiveWrites = writes.archives,
		sourceWrites = 0,
		fullAcceptancePassed = false,
	}
end
return A
