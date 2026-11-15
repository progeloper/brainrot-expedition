
-- Edit-only authoring helper. Apply the saved stud maps to environment scopes only.
assert(game.PlaceId==91958083796436 and game.GameId==10548905405,"Use Brainrot Expedition DEV")
assert(not game.RunService:IsRunning(),"Run in Edit")
local source=assert(game.MaterialService:FindFirstChild("Bingus_Saved_Studs_13719188279"),"Saved stud material missing")
assert(source.BaseMaterial==Enum.Material.Glacier and source.StudsPerTile==.25,"Preserve the original brainrot material")
local name="Environment_Saved_Studs_13719188279"
local variant=game.MaterialService:FindFirstChild(name)
if not variant then
 variant=source:Clone()
 variant.Name=name
 variant.StudsPerTile=4
 variant:SetAttribute("EnvironmentSurfaceOnly",true)
 variant:SetAttribute("SourceVariant",source.Name)
 variant.Parent=game.MaterialService
end
assert(variant:IsA("MaterialVariant")and variant.BaseMaterial==Enum.Material.Glacier and variant.StudsPerTile==4 and variant.ColorMap==source.ColorMap and variant.NormalMap==source.NormalMap,"Environment material differs from saved maps")
local Policy=require(game.ReplicatedStorage.Shared.Utility.EnvironmentStudMaterialPolicy)
local roots={workspace.MapBlockout,workspace.Baseplate,game.ServerStorage.EnvironmentV2_ImportedAssets,game.ServerStorage.MapArtRoadTemplates,game.ServerStorage.CompactMapRoadTemplates,game.ServerStorage.CompactMapShellTemplate,game.ReplicatedStorage.StudioAssets.MapArtPrototypes,game.ReplicatedStorage.StudioAssets.BaseSigns}
local changed=0 local visible=0 local skipped=0
for _,root in roots do
 local nodes=root:GetDescendants();table.insert(nodes,root)
 for _,p in nodes do
  if p:IsA("BasePart")and not p:IsA("Terrain")and p.Transparency<1 then
   visible+=1
   local missing=p.Material~=Enum.Material.Glacier or p.MaterialVariant~=name or p:GetAttribute("StudsPerTile")~=4
   if Policy.Apply(p)then if missing then changed+=1 end else skipped+=1 end
  end
 end
end
return {environmentVisible=visible,updated=changed,protectedSkipped=skipped,studsPerTile=4,originalBrainrotStudsPerTile=source.StudsPerTile}
