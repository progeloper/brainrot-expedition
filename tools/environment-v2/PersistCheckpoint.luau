--!nocheck
-- Root-only editor-time authoring checkpoint; writes exclusively to its new owned ServerStorage subtree.
local P = {}
local OWNER = "BR_EnvironmentArt_V2"
local function sha(s) return type(s) == "string" and #s == 64 and s:match("^[0-9a-f]+$") end
function P.Persist(options)
	assert(game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(), "DEV Edit only")
	assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Wrong DEV")
	local context = assert(shared.EnvironmentV2Baseline, "Fresh capture is required")
	local Audit = assert(options.auditAPI, "Exact detached Audit API required")
	assert(sha(options.sceneSHA256) and sha(options.sourcesSHA256), "Root must supply SHA256 of exact complete exported manifest/source JSON bytes")
	local freshKey = select(1, Audit.KeyFactory())
	for _, r in context.manifest.records do
		local node = assert(context.refs[r.key], "Missing original reference")
		local actual = Audit.Record(node, freshKey); actual.scope = r.scope
		assert(Audit.Equal(r, actual, 0), "Changed after capture, checkpoint aborted: " .. r.path)
	end
	for _, r in context.sources do
		local node = assert(context.refs[r.key], "Missing source reference"); assert(node.Source == r.source, "Source changed after capture: " .. r.path)
		if r.editorSourceAvailable then assert(game:GetService("ScriptEditorService"):GetEditorSource(node) == r.editorSource, "Editor bytes changed after capture: " .. r.path) end
	end
	local SS = game:GetService("ServerStorage")
	local name = "EnvironmentV2_Checkpoint_" .. options.sceneSHA256:sub(1, 12)
	local old = SS:FindFirstChild(name)
	if old then
		assert(old:IsA("Folder") and old:GetAttribute("ArtOwner") == OWNER and old:GetAttribute("BaselineSceneSHA256") == options.sceneSHA256 and old:GetAttribute("BaselineSourcesSHA256") == options.sourcesSHA256 and old:GetAttribute("Completed") == true, "Conflicting/incomplete checkpoint; do not overwrite")
		return { status = "RetainedOwnedCheckpoint", path = old:GetFullName(), worldWrites = 0, sourceWrites = 0 }
	end
	local stage = Instance.new("Folder"); stage.Name = name; stage:SetAttribute("ArtOwner", OWNER); stage:SetAttribute("NoRuntimeUse", true)
	local ok, reason = xpcall(function()
		local function store(kind, pieces, bytes, hash)
			local folder = Instance.new("Folder"); folder.Name = kind; folder.Parent = stage
			folder:SetAttribute("ChunkCount", #pieces); folder:SetAttribute("Bytes", bytes); folder:SetAttribute("SHA256", hash)
			for i, text in pieces do assert(#text <= 60000, "Native chunk bound exceeded"); local v = Instance.new("StringValue"); v.Name = string.format("Chunk_%04d", i); v.Value = text; v.Parent = folder end
		end
		store("BeforeManifest", context.manifestChunks, #context.manifestJSON, options.sceneSHA256)
		store("BeforeSources", context.sourceChunks, #context.sourcesJSON, options.sourcesSHA256)
		local refs = Instance.new("Folder"); refs.Name = "OriginalRefs"; refs.Parent = stage
		local keys = {}; for key, node in context.refs do if node ~= game then table.insert(keys, key) end end; table.sort(keys)
		for i, key in keys do local node = context.refs[key]; local ref = Instance.new("ObjectValue"); ref.Name = string.format("Ref_%05d", i); ref:SetAttribute("OriginalKey", key); ref:SetAttribute("OriginalName", node.Name); ref:SetAttribute("OriginalClass", node.ClassName); ref.Value = node; ref.Parent = refs end
		-- Complete geometry backups stay outside Workspace. Their tags are removed only from clones.
		local copies = Instance.new("Folder"); copies.Name = "GeometryCopies"; copies.Parent = stage
		for _, root in context.manifest.roots do
			if root.role == "Map" or root.role == "ProtectedAssets" or root.role == "External" then
				local original = context.refs[root.key]; local clone = assert(original:Clone(), "Original root is not archivable")
				clone.Parent = copies; clone.Name = root.role .. "_Before"
				assert(#clone:GetDescendants() == #original:GetDescendants(), "Incomplete geometry copy")
				local nodes = clone:GetDescendants(); table.insert(nodes, clone)
				for _, node in nodes do
					for _, tag in game:GetService("CollectionService"):GetTags(node) do game:GetService("CollectionService"):RemoveTag(node, tag) end
					-- Never add new LuaSourceContainers to the place through this checkpoint.
					assert(not node:IsA("LuaSourceContainer"), "Geometry copy contains a source; exact source bytes already preserved in bounded chunks")
				end
			end
		end
		stage:SetAttribute("BaselineSceneSHA256", options.sceneSHA256); stage:SetAttribute("BaselineSourcesSHA256", options.sourcesSHA256)
		stage:SetAttribute("CapturedSources", #context.sources); stage:SetAttribute("CapturedRecords", #context.manifest.records); stage:SetAttribute("Completed", true)
	end, debug.traceback)
	if not ok then stage:Destroy(); error("Owned checkpoint cleanup completed: " .. tostring(reason)) end
	stage.Parent = SS
	context.sceneSHA256 = options.sceneSHA256; context.sourcesSHA256 = options.sourcesSHA256; context.checkpoint = stage
	return { status = "CreatedOwnedCheckpoint", path = stage:GetFullName(), sources = #context.sources, records = #context.manifest.records, refs = #stage.OriginalRefs:GetChildren(), maximumChunkBytes = 60000, workspaceWrites = 0, originalWrites = 0, sourceWrites = 0, allCopiesOutsideWorkspace = true }
end
return P
