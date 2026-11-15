--!nocheck
-- Reconstruct ephemeral verification inputs from persistent owned journals after a DEV reopen.
-- No original-instance/source/property/tag writes, gameplay requires, HTTP or new Instances.
-- Call Rebind({verify=loadedVerifyAPI, sourceAPI=loadedExactSourceAPI, rollbackAPI=optionalLoadedAPI}).
local API = {}
local Http = game:GetService("HttpService")
local SS = game:GetService("ServerStorage")
local MIGRATION = "CompactMap_V1"
local BASELINE = "3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310"
local ROAD_HASH = "696d1821c5ebc3a595f9437366c1c777f31d6ea5f2b0f303fd8a2a895a32dbb0"
local function child(parent, name, class)
	local matches = {}
	for _, node in parent:GetChildren() do
		if node.Name == name then
			table.insert(matches, node)
		end
	end
	assert(
		#matches == 1,
		"Exactly one persistent child required: " .. parent:GetFullName() .. "." .. name
	)
	assert(not class or matches[1].ClassName == class, "Persistent child class differs: " .. name)
	return matches[1]
end
local pathIndex
local function resolve(path, class)
	if not pathIndex then
		pathIndex = {}
		for _, node in game:GetDescendants() do
			local name = node:GetFullName()
			pathIndex[name] = pathIndex[name] or {}
			table.insert(pathIndex[name], node)
		end
	end
	local found = {}
	for _, node in pathIndex[path] or {} do
		if not class or node.ClassName == class then
			table.insert(found, node)
		end
	end
	assert(
		#found == 1,
		"Unique literal full-name reference required: " .. path .. " (" .. #found .. " matches)"
	)
	return found[1]
end
local function chunks(parent, name, hash)
	local folder = child(parent, name, "Folder")
	local entries = folder:GetChildren()
	local pieces = {}
	assert(#entries > 0, "Persistent JSON is empty: " .. name)
	table.sort(entries, function(a, b)
		return a.Name < b.Name
	end)
	for i, node in entries do
		assert(
			node.ClassName == "StringValue" and node.Name == string.format("Chunk_%04d", i),
			"Noncontiguous/invalid JSON chunk " .. name
		)
		assert(#node.Value > 0, "Empty JSON chunk " .. name)
		pieces[i] = node.Value
	end
	if folder:GetAttribute("ChunkCount") ~= nil then
		assert(
			folder:GetAttribute("ChunkCount") == #pieces,
			"Recorded JSON chunk count differs " .. name
		)
	end
	if hash then
		assert(
			folder:GetAttribute("MigrationId") == MIGRATION
				and folder:GetAttribute("DesiredHash") == hash,
			"Journal JSON hash/provenance differs " .. name
		)
	end
	local text = table.concat(pieces)
	if folder:GetAttribute("Bytes") ~= nil then
		assert(folder:GetAttribute("Bytes") == #text, "Recorded JSON byte count differs " .. name)
	end
	return text, Http:JSONDecode(text)
end
local function decode(v, refs)
	if type(v) ~= "table" or not v.type then
		return v
	end
	local a = v.value
	if v.type == "CFrame" then
		return CFrame.new(table.unpack(a))
	end
	if v.type == "Vector3" then
		return Vector3.new(table.unpack(a))
	end
	if v.type == "Vector2" then
		return Vector2.new(table.unpack(a))
	end
	if v.type == "Color3" then
		return Color3.new(table.unpack(a))
	end
	if v.type == "UDim" then
		return UDim.new(table.unpack(a))
	end
	if v.type == "UDim2" then
		return UDim2.new(a[1], a[2], a[3], a[4])
	end
	if v.type == "PhysicalProperties" then
		return PhysicalProperties.new(table.unpack(a))
	end
	if v.type == "EnumItem" then
		local enum, name = a:match("^Enum%.([^%.]+)%.([^%.]+)$")
		assert(
			enum and name and Enum[enum] and Enum[enum][name],
			"Unknown captured enum " .. tostring(a)
		)
		return Enum[enum][name]
	end
	if v.type == "Instance" then
		return refs[v.key] or resolve(v.path)
	end
	error("Unsupported captured native baseline kind " .. tostring(v.type))
end
function API.Rebind(options)
	options = options or {}
	pathIndex = nil
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"Cold rebind requires DEV Edit"
	)
	assert(
		game.PlaceId == 91958083796436 and game.GameId == 10548905405,
		"Wrong DEV place/universe"
	)
	assert(
		options.verify and type(options.verify.Verify) == "function",
		"Pass the exact loaded read-only Verify API"
	)
	assert(
		options.sourceAPI and type(options.sourceAPI.Verify) == "function",
		"Pass the exact loaded source-owner tool API"
	)
	local map = child(workspace, "MapBlockout", "Folder")
	local hash = map:GetAttribute("CompactMapDesiredHash")
	assert(
		map:GetAttribute("CompactMapMigrationId") == MIGRATION
			and map:GetAttribute("CompactMapStatus") == "Completed",
		"Only a completed persisted compact map can be rebound"
	)
	assert(
		type(hash) == "string" and #hash == 64 and hash:match("^[0-9a-f]+$"),
		"Completed desired hash missing"
	)
	local journal = child(SS, "CompactMapV1_WorldJournal_" .. hash:sub(1, 12), "Folder")
	assert(
		journal:GetAttribute("MigrationId") == MIGRATION
			and journal:GetAttribute("DesiredHash") == hash
			and journal:GetAttribute("Status") == "Completed"
			and journal:GetAttribute("BaselineSHA256") == BASELINE,
		"Completed persistent world journal mismatch"
	)
	local backups = child(SS, "MapCompactionBackups", "Folder")
	local checkpoint = child(backups, "CompactMap_V1_3fb9d9e8a543", "Folder")
	assert(
		checkpoint:GetAttribute("MigrationId") == MIGRATION
			and checkpoint:GetAttribute("BaselineManagedSHA256") == BASELINE
			and checkpoint:GetAttribute("NoRuntimeUse") == true,
		"Reviewed immutable checkpoint mismatch"
	)
	local beforeText, before = chunks(checkpoint, "BeforeManifest_JSON_Chunks")
	local _, plan = chunks(journal, "PlanManifest_JSON_Chunks", hash)
	local runtimeText, runtime = chunks(journal, "RuntimeGeometry_JSON_Chunks", hash)
	local _, metadata = chunks(journal, "MetadataPatch_JSON_Chunks", hash)
	local _, nativeAssets = chunks(journal, "NativeAssets_JSON_Chunks", hash)
	local sourcesText, sources = chunks(journal, "OriginalSources_JSON_Chunks", hash)
	local _, routeDraft = chunks(journal, "RouteDraft_JSON_Chunks", hash)
	assert(
		plan.migrationId == MIGRATION
			and plan.planHash == hash
			and plan.baselineManagedContentSHA256 == BASELINE
			and plan.status == "ReadyForNativeApply",
		"Persistent desired plan binding mismatch"
	)
	assert(
		runtime.migrationId == MIGRATION
			and runtime.planHash == hash
			and runtime.runtimeValidated == true,
		"Persistent runtime descriptor binding mismatch"
	)
	assert(
		nativeAssets.passed == true
			and nativeAssets.status == "Passed"
			and nativeAssets.completeBatch == true
			and #nativeAssets.groups == 31,
		"Complete persistent actual native proof missing"
	)
	assert(
		nativeAssets.roadGeometryHash == ROAD_HASH,
		"Persistent native road geometry proof differs"
	)
	assert(
		routeDraft.baselineManagedContentSHA256 == BASELINE,
		"Persistent classified route baseline differs"
	)
	assert(
		#before.objects == 1555
			and #before.protectedSourceAssets == 1163
			and #before.externalStaticObjects == 2
			and #sources == 356,
		"Complete frozen original record population required"
	)
	assert(
		1 + #child(checkpoint, "MapBlockout_Before", "Folder"):GetDescendants() == #before.objects,
		"Incomplete captured checkpoint map clone"
	)
	local rows, refs = {}, {}
	for _, group in { before.objects, before.externalStaticObjects } do
		for _, r in group do
			assert(not rows[r.key], "Duplicate frozen original key " .. r.key)
			rows[r.key] = r
		end
	end
	local persistentRefs = child(journal, "OriginalRefs", "Folder")
	local count = 0
	for _, ref in persistentRefs:GetChildren() do
		assert(
			ref.ClassName == "ObjectValue" and ref.Value,
			"Missing persistent original reference"
		)
		local key = ref:GetAttribute("OriginalKey")
		local r = rows[key]
		assert(
			r and not refs[key],
			"Unknown/duplicate persistent original reference " .. tostring(key)
		)
		assert(
			ref.Value.Name == r.name and ref.Value.ClassName == r.class,
			"Persistent original identity/class drift " .. r.path
		)
		refs[key] = ref.Value
		count += 1
	end
	assert(count == 1557, "Complete1557 persistent managed/external original references required")
	for key, r in rows do
		assert(refs[key], "Missing persistent original key " .. r.path)
	end
	local function bindPersistent(folderName, records)
		local expected = {}
		for _, r in records do
			assert(not expected[r.key], "Duplicate captured ref key " .. r.key)
			expected[r.key] = r
		end
		local folder = child(journal, folderName, "Folder")
		local seen = {}
		local bound = 0
		for _, record in folder:GetChildren() do
			assert(
				record.ClassName == "ObjectValue" and record.Value,
				"Missing explicit persistent identity " .. folderName
			)
			local key = record:GetAttribute("OriginalKey")
			local r = expected[key]
			assert(
				r and not seen[key],
				"Unknown/duplicate persistent identity " .. folderName .. "/" .. tostring(key)
			)
			seen[key] = true
			local node = record.Value
			assert(
				node.ClassName == r.class and node.Name == r.name,
				"Explicit persistent identity/class changed " .. r.path
			)
			if refs[key] then
				assert(refs[key] == node, "Conflicting persistent original identity " .. r.path)
			else
				refs[key] = node
			end
			bound += 1
		end
		assert(bound == #records, "Incomplete explicit persistent identities " .. folderName)
	end
	bindPersistent("ProtectedRefs", before.protectedSourceAssets)
	bindPersistent("SourceRefs", sources)
	bindPersistent("EnvironmentRefs", before.effects)

	-- Complete original source records are immutable journal input, never recaptured from patched Sources.
	local sourceFolder = child(checkpoint, "LiveSources_Before", "Folder")
	local baselineSources = {}
	assert(#sourceFolder:GetChildren() == 356, "Incomplete original-source checkpoint")
	for _, node in sourceFolder:GetChildren() do
		assert(node.ClassName == "StringValue", "Invalid original-source checkpoint row")
		local path = node:GetAttribute("OriginalPath")
		assert(
			type(path) == "string" and not baselineSources[path],
			"Unknown/duplicate source checkpoint path"
		)
		baselineSources[path] = { source = node.Value, class = node:GetAttribute("OriginalClass") }
	end
	local sourcePaths = {}
	for _, r in sources do
		assert(not sourcePaths[r.path], "Duplicate original source record " .. r.path)
		sourcePaths[r.path] = true
		local saved =
			assert(baselineSources[r.path], "Original source missing from checkpoint " .. r.path)
		assert(
			saved.source == r.source and saved.class == r.class,
			"Original source journal/checkpoint drift " .. r.path
		)
		local node = assert(refs[r.key], "Persistent source identity missing " .. r.path)
		assert(node:GetFullName() == r.path, "Persistent source parent/path changed " .. r.path)
		if refs[r.key] then
			assert(refs[r.key] == node, "Original source reference collision " .. r.path)
		else
			refs[r.key] = node
		end
	end
	local native = {}
	for _, group in { before.objects, before.protectedSourceAssets, before.externalStaticObjects } do
		for _, r in group do
			local node = assert(refs[r.key], "Original identity missing " .. r.path)
			local parent = refs[r.parent]
			if not parent then
				assert(
					r.path:sub(-#r.name) == r.name
						and r.path:sub(#r.path - #r.name, #r.path - #r.name) == ".",
					"Captured parent/name suffix differs " .. r.path
				)
				local path = r.path:sub(1, #r.path - #r.name - 1)
				parent = resolve(path)
				refs[r.parent] = parent
			end
			local n = {
				instance = node,
				parent = parent,
				name = r.name,
				archivable = r.archivable,
				attributes = {},
				tags = table.clone(r.tags),
				properties = {},
				key = r.key,
				kind = if group == before.objects
					then "Managed"
					elseif group == before.protectedSourceAssets then "Protected"
					else "External",
			}
			for name, v in r.attributes do
				n.attributes[name] = decode(v, refs)
			end
			if r.properties then
				for name, v in r.properties do
					if not (type(v) == "table" and v.unavailable) then
						n.properties[name] = decode(v, refs)
					end
				end
				n.customPhysicsWasNil = r.properties.CustomPhysicalProperties == nil
				n.customPhysics = decode(r.properties.CustomPhysicalProperties, refs)
			end
			if r.pivot then
				n.pivot = decode(r.pivot, refs)
				n.scale = r.scale
				n.primaryPart = decode(r.model.PrimaryPart, refs)
				n.streamingMode = decode(r.model.ModelStreamingMode, refs)
			end
			if r.attachment then
				n.attachmentCFrame = decode(r.attachment.CFrame, refs)
			end
			if r.reference then
				n.reference = decode(r.reference, refs)
			end
			if r.value then
				n.value = r.value.Value
			end
			native[r.key] = n
		end
	end
	-- Publish only ephemeral Lua references after the entire persistent rebind passes preflight.
	shared.CompactMapBeforeManifest = before
	shared.CompactMapBeforeJSON = beforeText
	shared.CompactMapManagedOriginals = refs
	shared.CompactMapOriginalNativeValues = native
	shared.CompactMapSources = sources
	shared.CompactMapSourcesJSON = sourcesText
	shared.CompactMapBackup = checkpoint
	shared.CompactMapWorldJournal = journal
	shared.CompactMapNativeAssetsProof = nativeAssets
	local desired = {
		plan = plan,
		metadata = metadata,
		runtimeJSON = runtimeText,
		nativeAssetsProof = nativeAssets,
		routeDraft = routeDraft,
		roadGeometryHash = ROAD_HASH,
		verify = options.verify,
		sourceAPI = options.sourceAPI,
		rollbackAPI = options.rollbackAPI,
	}
	local report = {
		passed = true,
		status = "ReboundPersistentCompletedState",
		migrationId = MIGRATION,
		planHash = hash,
		journal = journal:GetFullName(),
		checkpoint = checkpoint:GetFullName(),
		managedOriginals = 1555,
		protectedOriginals = 1163,
		externalOriginals = 2,
		originalSources = 356,
		persistentOriginalRefs = 1557,
		nativeBaselineOrigin = "Decoded immutable BeforeManifest; no current geometry recapture",
		managedIdentityMode = "Saved OriginalRefs ObjectValues",
		protectedIdentityMode = "Saved ProtectedRefs ObjectValues",
		sourceIdentityMode = "Saved SourceRefs ObjectValues (literal dotted names preserved)",
		environmentIdentityMode = "Saved EnvironmentRefs ObjectValues",
		worldWrites = 0,
		sourceWrites = 0,
		baselineWrites = 0,
		assetWrites = 0,
		newInstances = 0,
		verifiedAppliedState = false,
	}
	return desired, report
end
function API.Verify(options)
	local desired, report = API.Rebind(options)
	local proof = desired.verify.Verify(desired)
	report.verifiedAppliedState = proof.passed
	report.status = if proof.passed
		then "ColdPersistentVerificationPassed"
		else "ColdPersistentVerificationFailed"
	report.passed = proof.passed
	report.staticProof = proof
	return report, desired
end
return API
