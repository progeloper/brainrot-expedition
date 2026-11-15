-- DEV ONLY. Studio Edit mode (MCP execute_luau or the command bar); never Rojo-mapped, never shipped.
-- Reverts Playtest Fixes Part A: every World prop part carrying StudMigrationOriginal* attributes gets
-- its original Material, MaterialVariant, CustomPhysicalProperties, colour and stud Textures back.
-- Covers the stored world (ServerStorage.TerrainRedesign.World) and a previewed Workspace.World.
-- The JSON copy of the same backup is docs/playtest_fixes/stud_backup.json.
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "RevertMapStuds: run in Edit mode only")
local Policy = require(game:GetService("ReplicatedStorage").Shared.Utility.MapStudPolicy)

local roots = {}
local store = game:GetService("ServerStorage"):FindFirstChild("TerrainRedesign")
if store and store:FindFirstChild("World") then
	table.insert(roots, store.World)
end
if workspace:FindFirstChild("World") then
	table.insert(roots, workspace.World)
end
local total = 0
for _, root in roots do
	total += Policy.RevertTree(root, 400)
end
print(string.format("[RevertMapStuds] restored %d parts across %d roots", total, #roots))
return total
