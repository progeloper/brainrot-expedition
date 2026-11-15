-- Studio EDIT mode only (MCP execute_luau or the command bar). Deterministic rebuild of the V5 world
-- store: ServerStorage.TerrainRedesign = { World (prop models), Terrain_V5 (one TerrainRegion) }.
-- Workspace terrain is cleared again at the end; the world lives only in the store; every server start swaps it in. Set PREVIEW = true to leave the V5 look applied
-- for captures, and run TerrainRedesignSwitch.Revert(workspace.MapBlockout) before saving.
--
-- Studio caches require() per ModuleScript instance and Rojo live-sync edits Source in place, so the
-- builder runs from a sandbox copy of Shared.Config + TerrainBuilder (nested requires stay fresh).
-- Regenerate the data first: python3 -I tools/terrain/author_v5.py && stylua src/shared/Config/Terrain*
local PREVIEW = false

local ServerStorage = game:GetService("ServerStorage")
local src = game:GetService("ReplicatedStorage").Shared
local box = Instance.new("Folder")
box.Name = "_V5Sandbox"
box.Parent = ServerStorage
local cfg = src.Config:Clone()
cfg.Parent = box
local util = Instance.new("Folder")
util.Name = "Utility"
util.Parent = box
src.Utility.TerrainBuilder:Clone().Parent = util
src.Utility.MapStudPolicy:Clone().Parent = util
local switchModule = game.ServerScriptService.Server.Utility.TerrainRedesignSwitch:Clone()
switchModule.Parent = box

local Switch = require(switchModule)
local Builder = require(util.TerrainBuilder)
local Palette = require(cfg.TerrainPalette)
local R = {}
for _, x in cfg.TerrainRegions:GetChildren() do
	R[x.Name] = require(x)
end
local kits = {}
for _, x in cfg.TerrainKits:GetChildren() do
	kits[x.Name] = require(x)
end

Switch.Revert(workspace.MapBlockout)
local store = ServerStorage:FindFirstChild("TerrainRedesign")
if not store then
	store = Instance.new("Folder")
	store.Name = "TerrainRedesign"
	store.Parent = ServerStorage
end
for _, child in store:GetChildren() do
	child:Destroy()
end

local terrain = workspace.Terrain
terrain:Clear()
local ORDER = { "Camp", "Forest", "Beach", "Swamp", "Jungle", "Arctic", "Volcano", "GlitchZone" }
for _, key in ORDER do
	Builder.ShapeTerrain(terrain, R[key], 4)
end
for _, key in ORDER do
	Builder.ShapeSeams(terrain, R[key]) -- seams after every neighbour is shaped
end
-- CP-D: ocean beyond the rim coast (stored as its own TerrainRegion; its island band is identical).
local Edge = require(cfg.IslandEdge)
Builder.ShapeOcean(terrain, Edge)
for _, materials in Palette.Materials do
	for materialName, hex in materials do
		store:SetAttribute("Colour_" .. materialName, hex)
	end
end
store:SetAttribute("WaterColour", Palette.WaterColour)
-- Owner request (10 Nov): every visible terrain surface carries the saved AF2 studs. Point each palette
-- material at its existing AF2_Building_<Material> variant (place-level MaterialService setting; no part
-- in the place uses Cobblestone, Concrete or Pavement, so only terrain changes). Water takes no variant.
local MaterialService = game:GetService("MaterialService")
for _, materials in Palette.Materials do
	for materialName in materials do
		local variant = MaterialService:FindFirstChild("AF2_Building_" .. materialName, true)
		assert(variant and variant:IsA("MaterialVariant"), "missing AF2 stud variant for " .. materialName)
		MaterialService:SetBaseMaterialOverride(Enum.Material[materialName], variant.Name)
	end
end
-- WorldToCellPreferSolid returns Vector3 cell indices; fills reach 8 studs under neighbour floors and
-- the island rim rises to y 186 just inside the outer walls (east rim outer edge x 740).
local a = terrain:WorldToCellPreferSolid(Vector3.new(-776, -14, -680))
local b = terrain:WorldToCellPreferSolid(Vector3.new(744, 190, 592))
local region = terrain:CopyRegion(Region3int16.new(Vector3int16.new(a.X, a.Y, a.Z), Vector3int16.new(b.X, b.Y, b.Z)))
region.Name = "Terrain_V5"
region:SetAttribute("CornerCell", Vector3.new(a.X, a.Y, a.Z))
region.Parent = store
do
	local reach = Edge.Ocean.Reach
	local lo = terrain:WorldToCellPreferSolid(
		Vector3.new(Edge.Coast.min.X - reach, Edge.Ocean.BedBottomY, Edge.Coast.min.Y - reach)
	)
	local hi = terrain:WorldToCellPreferSolid(
		Vector3.new(Edge.Coast.max.X + reach, Edge.Ocean.SurfaceY + Edge.Ocean.IsletCap + 1, Edge.Coast.max.Y + reach)
	)
	local ocean = terrain:CopyRegion(
		Region3int16.new(Vector3int16.new(lo.X, lo.Y, lo.Z), Vector3int16.new(hi.X, hi.Y, hi.Z))
	)
	ocean.Name = "Terrain_V5_Ocean"
	ocean:SetAttribute("CornerCell", Vector3.new(lo.X, lo.Y, lo.Z))
	ocean.Parent = store
end

local world = Instance.new("Folder")
world.Name = "World"
world.Parent = store
local summary = {}
-- Playtest Fixes Part A (13 Nov): props carry the bases' Environment_Saved_Studs variant instead of the
-- 0.8-transparent overlay Textures. Same rule as the in-place migration; scripts/RevertMapStuds undoes it.
local PlaytestFixes = require(cfg.PlaytestFixes)
local MapStuds = if PlaytestFixes.Parts.MapStuds then require(util.MapStudPolicy) else nil
for _, key in { "Gates", "Camp", "Forest", "Beach", "Swamp", "Jungle", "Arctic", "Volcano", "GlitchZone" } do
	local root = Builder.Dress(R[key], kits, world, 2)
	if MapStuds then
		MapStuds.ApplyTree(root, 400)
	end
	local fp = Builder.Fingerprint(root)
	table.insert(summary, string.format("%s parts=%d neon=%d textures=%d models=%d", key, fp.parts, fp.neon, fp.textures, fp.models))
	task.wait()
end
terrain:Clear()
box:Destroy()
if PREVIEW then
	Switch.Apply(workspace.MapBlockout)
	Switch.HideLegacyGateDressing(workspace.MapBlockout)
end
return table.concat(summary, "\n")
