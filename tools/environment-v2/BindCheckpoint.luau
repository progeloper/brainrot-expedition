--!nocheck
-- Read-only persistent-input binder after a DEV reopen; uses explicit saved references, never path guessing.
local B = {}
function B.Bind(options)
	assert(game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(), "DEV Edit only")
	assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Wrong DEV")
	local sceneSHA, sourceSHA = options.sceneSHA256, options.sourcesSHA256
	assert(
		type(sceneSHA) == "string" and #sceneSHA == 64 and type(sourceSHA) == "string" and #sourceSHA == 64,
		"Pass original verified exported SHA256 values"
	)
	local checkpoint = assert(
		game:GetService("ServerStorage"):FindFirstChild("EnvironmentV2_Checkpoint_" .. sceneSHA:sub(1, 12)),
		"Persisted checkpoint missing"
	)
	assert(
		checkpoint:GetAttribute("ArtOwner") == "BR_EnvironmentArt_V2"
			and checkpoint:GetAttribute("NoRuntimeUse") == true
			and checkpoint:GetAttribute("Completed") == true
			and checkpoint:GetAttribute("BaselineSceneSHA256") == sceneSHA
			and checkpoint:GetAttribute("BaselineSourcesSHA256") == sourceSHA,
		"Checkpoint provenance/binding mismatch"
	)
	local function read(name, expectedSHA)
		local folder = assert(checkpoint:FindFirstChild(name), "Missing complete bounded data")
		assert(folder:GetAttribute("SHA256") == expectedSHA, "Recorded data SHA binding differs")
		local rows = folder:GetChildren()
		table.sort(rows, function(a, b)
			return a.Name < b.Name
		end)
		local parts = {}
		for i, node in rows do
			assert(
				node.ClassName == "StringValue"
					and node.Name == string.format("Chunk_%04d", i)
					and #node.Value > 0
					and #node.Value <= 60000,
				"Invalid/noncontiguous UTF8 data chunk"
			)
			parts[i] = node.Value
		end
		local text = table.concat(parts)
		assert(
			#parts == folder:GetAttribute("ChunkCount") and #text == folder:GetAttribute("Bytes"),
			"Incomplete persistent JSON bytes"
		)
		return text, game:GetService("HttpService"):JSONDecode(text), parts
	end
	local manifestJSON, manifest, manifestChunks = read("BeforeManifest", sceneSHA)
	local sourcesJSON, sources, sourceChunks = read("BeforeSources", sourceSHA)
	assert(
		manifest.owner == "BR_EnvironmentArt_V2"
			and manifest.sourcesCount == 357
			and #sources == 357
			and manifest.brainrotModels == 35
			and manifest.brainrotBaseParts == 890,
		"Complete original baseline required"
	)
	assert(
		#manifest.records == checkpoint:GetAttribute("CapturedRecords")
			and #sources == checkpoint:GetAttribute("CapturedSources"),
		"Captured record population differs"
	)
	local refs = { game = game }
	local identities = {}
	for _, object in checkpoint.OriginalRefs:GetChildren() do
		assert(object.ClassName == "ObjectValue" and object.Value, "Missing original identity")
		local key = object:GetAttribute("OriginalKey")
		local node = object.Value
		assert(
			type(key) == "string"
				and not refs[key]
				and not identities[node]
				and node.Name == object:GetAttribute("OriginalName")
				and node.ClassName == object:GetAttribute("OriginalClass"),
			"Explicit original identity/key/class mismatch"
		)
		refs[key] = node
		identities[node] = key
	end
	for _, row in manifest.records do
		assert(
			refs[row.key]
				and refs[row.key].Name == row.name
				and refs[row.key].ClassName == row.class
				and refs[row.parent],
			"Complete protected original refs required"
		)
	end
	for _, row in sources do
		assert(
			refs[row.key]
				and refs[row.key].Name == row.name
				and refs[row.key].ClassName == row.class
				and refs[row.parent],
			"Complete original source refs required"
		)
	end
	local map
	for _, row in manifest.roots do
		if row.role == "Map" then
			map = refs[row.key]
		end
	end
	assert(map == workspace:FindFirstChild("MapBlockout"), "Persistent current map identity differs")
	-- Caller must independently SHA256-check the returned complete bytes before cold acceptance.
	local context = {
		owner = "BR_EnvironmentArt_V2",
		checkpoint = checkpoint,
		manifest = manifest,
		sources = sources,
		refs = refs,
		map = map,
		manifestJSON = manifestJSON,
		sourcesJSON = sourcesJSON,
		manifestChunks = manifestChunks,
		sourceChunks = sourceChunks,
		sceneSHA256 = sceneSHA,
		sourcesSHA256 = sourceSHA,
	}
	shared.EnvironmentV2Baseline = context
	return {
		status = "ReboundExplicitPersistentBaseline",
		records = #manifest.records,
		sources = #sources,
		manifestBytes = #manifestJSON,
		sourcesBytes = #sourcesJSON,
		manifestChunks = #manifestChunks,
		sourceChunks = #sourceChunks,
		worldWrites = 0,
		sourceWrites = 0,
		newInstances = 0,
		cryptographicReadbackCheckedByThisHelper = false,
		installedLayerVerified = false,
	}
end
return B
