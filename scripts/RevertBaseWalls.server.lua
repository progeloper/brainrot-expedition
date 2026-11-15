--!nocheck
-- Playtest Fixes 2, Part D revert: removes the base wall colliders that
-- tools/playtest_fixes2/BuildBaseWalls.edit.luau authored. Run in Studio EDIT mode (command bar), then
-- save the place. The shell meshes (Primary / Accent / Support) were never changed, so after this the
-- bases are exactly as before (walk-through walls). Not mapped by Rojo; it is a one-off tool.
local removed = 0
for _, base in workspace.MapBlockout.PlayerBasePatches:GetChildren() do
	local folder = base:FindFirstChild("WallColliders")
	if folder and folder:GetAttribute("PlaytestFixes2") == "BaseWalls" then
		removed += #folder:GetChildren()
		folder:Destroy()
	end
end
print(string.format("[RevertBaseWalls] removed %d colliders", removed))
return removed
