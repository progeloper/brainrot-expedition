-- Playtest Fixes Part A, Studio EDIT mode only (MCP execute_luau or the command bar).
-- One-time authoring migration of the stored V5 world (ServerStorage.TerrainRedesign.World): every
-- eligible prop part gets the bases' Environment_Saved_Studs variant (see Shared.Utility.MapStudPolicy).
-- A rebuild through tools/terrain/BuildWorld.edit.luau produces the same result.
-- Undo: scripts/RevertMapStuds.server.lua (attribute backup; JSON copy in docs/playtest_fixes/).
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local Policy = require(game:GetService("ReplicatedStorage").Shared.Utility.MapStudPolicy)
local world = game:GetService("ServerStorage").TerrainRedesign.World
local function count(root)
	local n, parts, textures = 0, 0, 0
	for _, d in root:GetDescendants() do
		n += 1
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Texture") then
			textures += 1
		end
	end
	return n, parts, textures
end
local beforeAll, beforeParts, beforeTextures = count(world)
local regions = {}
for _, region in world:GetChildren() do
	local s = Policy.ApplyTree(region, 400)
	regions[region.Name] = s
	task.wait()
end
local afterAll, afterParts, afterTextures = count(world)
return game:GetService("HttpService"):JSONEncode({
	before = { instances = beforeAll, parts = beforeParts, textures = beforeTextures },
	after = { instances = afterAll, parts = afterParts, textures = afterTextures },
	regions = regions,
})
