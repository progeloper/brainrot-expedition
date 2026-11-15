-- Playtest Fixes Part A capture aid, Studio EDIT mode only. Clones one tree/rock/palm/shrub per region
-- and every region landmark out of the stored V5 world into Workspace._PlaytestPreview, in two rows on
-- a plate at y = 1000 (clear of the legacy map), plus a base slot for stud-size comparison. Returns the
-- placed centres for fixed-camera captures. Archivable = false: never saved with the place.
local Y = 1000
local world = game:GetService("ServerStorage").TerrainRedesign.World
local old = workspace:FindFirstChild("_PlaytestPreview")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "_PlaytestPreview"
folder.Archivable = false
local plate = Instance.new("Part")
plate.Anchored = true
plate.Size = Vector3.new(1400, 1, 400)
plate.CFrame = CFrame.new(500, Y - 0.5, 60)
plate.Color = Color3.fromRGB(96, 178, 72)
plate.Material = Enum.Material.SmoothPlastic
plate.Parent = folder
local ROW_A = {
	{ "Forest", "Forest_TreePine" }, { "Forest", "Forest_TreeRound" }, { "Forest", "Forest_Rock" },
	{ "Forest", "Forest_Shrub" }, { "Forest", "Forest_MushroomBig" }, { "Beach", "Beach_PalmTree" },
	{ "Beach", "Beach_Umbrella" }, { "Swamp", "Swamp_DeadTree" }, { "Jungle", "Jungle_TreeTall" },
	{ "Arctic", "Arctic_IcePine" }, { "Volcano", "Volcano_CharredTree" }, { "GlitchZone", "Glitch_PixelTree" },
}
local out = {}
local function place(model: Model, x: number, z: number)
	local clone = model:Clone()
	local cf, size = clone:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	clone:PivotTo(clone:GetPivot() + Vector3.new(x - cf.Position.X, Y - bottom, z - cf.Position.Z))
	clone.Parent = folder
	table.insert(out, string.format("%s x=%.0f z=%.0f h=%.0f w=%.0f", clone.Name, x, z, size.Y, math.max(size.X, size.Z)))
	return size
end
local x = 0
for _, pick in ROW_A do
	for _, m in world[pick[1]]:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Kit") == pick[2] then
			local size = place(m, x, 0)
			x += math.max(size.X, size.Z) + 14
			break
		end
	end
end
x = 0
for _, region in world:GetChildren() do
	for _, m in region:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Role") == "Landmark" then
			local _, size = m:GetBoundingBox()
			local size2 = place(m, x + size.X / 2, 150)
			x += size2.X + 20
		end
	end
end
-- A base slot (the reference stud size) next to row A.
local base = workspace.MapBlockout.PlayerBasePatches:FindFirstChild("Base_07")
local slot = base and base:FindFirstChild("Slot_04")
if slot then
	local c = slot:Clone()
	c.Anchored = true
	c.CFrame = CFrame.new(-30, Y + c.Size.Y / 2, 0)
	c.Parent = folder
	table.insert(out, "BaseSlot x=-30 z=0")
end
folder.Parent = workspace
return table.concat(out, "\n")
