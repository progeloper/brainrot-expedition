local preservedBefore=assert(shared.CompactMapBeforeManifest)
local preservedSources=assert(shared.CompactMapSources)
local HttpService=game:GetService("HttpService")
local CS=game:GetService("CollectionService")
local Run=game:GetService("RunService")
assert(not Run:IsRunning(),"Compaction audit requires Edit")
assert(game.PlaceId==91958083796436,"Wrong DEV place")
assert(game.GameId==10548905405,"Wrong DEV universe")
local map=workspace:FindFirstChild("MapBlockout")
assert(map,"Missing map")
local keys={}
local function key(o)
 if keys[o]then return keys[o]end
 if o==game then return "game"end
 local index=1
 if o.Parent then for _,s in o.Parent:GetChildren()do if s==o then break end;if s.Name==o.Name and s.ClassName==o.ClassName then index+=1 end end end
 local value=(o.Parent and key(o.Parent)or"detached").."/"..o.ClassName..":"..o.Name.."["..index.."]"
 keys[o]=value
 return value
end
local function enc(v)
 local t=typeof(v)
 if t=="Instance"then return {type=t,path=v:GetFullName(),key=key(v)}end
 if t=="Vector3"then return {type=t,value={v.X,v.Y,v.Z}}end
 if t=="Vector2"then return {type=t,value={v.X,v.Y}}end
 if t=="CFrame"then return {type=t,value={v:GetComponents()}}end
 if t=="Color3"then return {type=t,value={v.R,v.G,v.B}}end
 if t=="UDim2"then return {type=t,value={v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset}}end
 if t=="UDim"then return {type=t,value={v.Scale,v.Offset}}end
 if t=="PhysicalProperties"then return {type=t,value={v.Density,v.Friction,v.Elasticity,v.FrictionWeight,v.ElasticityWeight}}end
 if t=="EnumItem"then return {type=t,value=tostring(v)}end
 if t=="number"or t=="string"or t=="boolean"or t=="nil"then return v end
 return {type=t,value=tostring(v)}
end
local function props(o,names)
 local p={}
 for _,n in names do local ok,v=pcall(function()return o[n]end);if ok then p[n]=enc(v)else p[n]={unavailable=true,error=tostring(v)}end end
 return p
end
local baseNames={"CFrame","Size","PivotOffset","Anchored","CanCollide","CanQuery","CanTouch","CollisionGroup","Transparency","Reflectance","CastShadow","Material","MaterialVariant","Color","CustomPhysicalProperties","CurrentPhysicalProperties","TopSurface","BottomSurface","LeftSurface","RightSurface","FrontSurface","BackSurface"}
local function record(o)
 local a={};for n,v in pairs(o:GetAttributes())do a[n]=enc(v)end
 local r={key=key(o),path=o:GetFullName(),name=o.Name,class=o.ClassName,parent=o.Parent and key(o.Parent)or nil,archivable=o.Archivable,attributes=a,tags=CS:GetTags(o)}
 local ok,id=pcall(function()return o:GetDebugId()end);if ok then r.debugId=id end
 if o:IsA("BasePart")then r.properties=props(o,baseNames);local ok,mass=pcall(function()return o:GetMass()end);if ok then r.mass=mass end end
 if o:IsA("MeshPart")then r.mesh=props(o,{"MeshId","TextureID","CollisionFidelity","RenderFidelity","DoubleSided"})end
 if o:IsA("UnionOperation")then r.union=props(o,{"AssetId","UsePartColor","CollisionFidelity","RenderFidelity"})end
 if o:IsA("Model")then r.pivot=enc(o:GetPivot());r.scale=o:GetScale();r.model=props(o,{"PrimaryPart","ModelStreamingMode","WorldPivot"})end
 if o:IsA("Attachment")then r.attachment=props(o,{"CFrame","WorldCFrame","Visible","Axis","SecondaryAxis"})end
 if o:IsA("ProximityPrompt")then r.prompt=props(o,{"ActionText","ObjectText","Enabled","MaxActivationDistance","RequiresLineOfSight","HoldDuration","KeyboardKeyCode","GamepadKeyCode","Exclusivity"})end
 if o:IsA("ObjectValue")then r.reference=enc(o.Value)end
 if o:IsA("ValueBase")and not o:IsA("ObjectValue")then r.value=props(o,{"Value"})end
 if o:IsA("Texture")or o:IsA("Decal")then r.texture=props(o,{"Texture","Transparency","Color3","Face","ZIndex"});if o:IsA("Texture")then r.tiling=props(o,{"StudsPerTileU","StudsPerTileV","OffsetStudsU","OffsetStudsV"})end end
 if o:IsA("SurfaceAppearance")then r.surface=props(o,{"ColorMap","NormalMap","RoughnessMap","MetalnessMap","AlphaMode","Color"})end
 if o:IsA("GuiObject")then r.gui=props(o,{"Size","Position","Visible","BackgroundColor3","BackgroundTransparency","ZIndex"})end
 if o:IsA("TextLabel")or o:IsA("TextButton")or o:IsA("TextBox")then r.text=props(o,{"Text","TextColor3","Font","TextSize","TextScaled","TextStrokeColor3","TextStrokeTransparency"})end
 if o:IsA("SurfaceGui")or o:IsA("BillboardGui")then r.worldGui=props(o,{"Adornee","Enabled","AlwaysOnTop","LightInfluence"})end
 if o:IsA("Constraint")then r.constraint=props(o,{"Enabled","Attachment0","Attachment1"})end
 if o:IsA("JointInstance")or o:IsA("WeldConstraint")then r.joint=props(o,{"Part0","Part1"});if o:IsA("JointInstance")then r.jointFrames=props(o,{"C0","C1"})end end
 return r
end
local objects={record(map)}
for _,o in map:GetDescendants()do table.insert(objects,record(o))end
local assets=game.ReplicatedStorage:FindFirstChild("StudioAssets")
local protected={}
if assets then table.insert(protected,record(assets));for _,o in assets:GetDescendants()do table.insert(protected,record(o))end end
local external={};local bp=workspace:FindFirstChild("Baseplate");if bp then table.insert(external,record(bp));for _,o in bp:GetDescendants()do table.insert(external,record(o))end end
local sources={};local referenceConsumers={};local excludedOwnedJournalRefs=0
local function ownedJournalReference(o)
 local ancestor=o.Parent
 while ancestor and ancestor~=game.ServerStorage do
  if ancestor.Parent==game.ServerStorage and ancestor:IsA("Folder") and ancestor.Name:match("^CompactMapV1_WorldJournal_") then
   return ancestor:GetAttribute("MigrationId")=="CompactMap_V1" and ancestor:GetAttribute("BaselineSHA256")=="3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310" and type(ancestor:GetAttribute("DesiredHash"))=="string" and #ancestor:GetAttribute("DesiredHash")==64
  end
  ancestor=ancestor.Parent
 end
 return false
end
for _,o in game:GetDescendants()do
 if o:IsA("LuaSourceContainer")then local ok,source=pcall(function()return o.Source end);if ok then local row={key=key(o),path=o:GetFullName(),class=o.ClassName,name=o.Name,source=source,attributes=record(o).attributes};if o:IsA("BaseScript")then row.enabled=o.Enabled;row.runContext=tostring(o.RunContext)end;table.insert(sources,row)end end
 if o:IsA("ObjectValue")and o.Value and (o.Value==map or o.Value:IsDescendantOf(map))then if ownedJournalReference(o)then excludedOwnedJournalRefs+=1 else table.insert(referenceConsumers,record(o))end end
end
table.sort(objects,function(a,b)return a.key<b.key end)
table.sort(protected,function(a,b)return a.key<b.key end)
table.sort(sources,function(a,b)return a.key<b.key end)
local lighting=props(game.Lighting,{"Ambient","OutdoorAmbient","Brightness","ClockTime","ColorShift_Bottom","ColorShift_Top","EnvironmentDiffuseScale","EnvironmentSpecularScale","ExposureCompensation","GlobalShadows","ShadowSoftness","LightingStyle","PrioritizeLightingQuality"})
local effects={};for _,o in game.Lighting:GetChildren()do local r=record(o);r.properties=props(o,{"Enabled","Intensity","Size","Threshold","Saturation","Contrast","Brightness","TintColor","Density","Offset","Haze","Glare","Decay","Color"});table.insert(effects,r)end
local physics=game:GetService("PhysicsService");local collision={};local groups=physics:GetRegisteredCollisionGroups()
for _,a in groups do local row={name=a.name,mask={}};for _,b in groups do row.mask[b.name]=physics:CollisionGroupsAreCollidable(a.name,b.name)end;table.insert(collision,row)end
local before={schemaVersion=1,migrationId="CompactMap_V1",placeId=game.PlaceId,universeId=game.GameId,engine=version(),capturedAtUTC=os.date("!%Y-%m-%dT%H:%M:%SZ"),mode="Edit",objects=objects,protectedSourceAssets=protected,externalStaticObjects=external,referenceConsumers=referenceConsumers,lighting=lighting,effects=effects,streaming=props(workspace,{"StreamingEnabled","StreamingMinRadius","StreamingTargetRadius","StreamingIntegrityMode","ModelStreamingBehavior"}),collisionMatrix=collision,sourcesCount=#sources,managedInstanceCount=#objects,protectedAssetInstanceCount=#protected,sourceCapture="All readable LuaSourceContainers in current Edit datamodel"}

local comparisons=0
local failures={}
local function equal(a,b,path)
 comparisons+=1
 if type(a)~=type(b) then table.insert(failures,path..":type"); return end
 if type(a)~="table"then
  if a~=b then table.insert(failures,path..":value")end
  return
 end
 for k,v in pairs(a)do
  if k~="capturedAtUTC" and k~="debugId"then equal(v,b[k],path.."."..tostring(k))end
 end
 for k,v in pairs(b)do
  if k~="capturedAtUTC"and k~="debugId"and a[k]==nil then table.insert(failures,path.."."..tostring(k)..":added")end
 end
end
equal(preservedBefore,before,"BeforeManifest")
equal(preservedSources,sources,"LiveSources")
local backup=assert(shared.CompactMapBackup)
local snapshot=assert(backup:FindFirstChild("MapBlockout_Before"))
assert(1+#snapshot:GetDescendants()==#preservedBefore.objects,"Incomplete map snapshot")
assert(#backup.LiveSources_Before:GetChildren()==#preservedSources,"Incomplete source snapshot")
for _,v in backup.LiveSources_Before:GetChildren()do
 local found=false
 for _,s in preservedSources do
  if s.path==v:GetAttribute("OriginalPath")then assert(s.source==v.Value,"Backup source mismatch");found=true;break end
 end
 assert(found,"Unmatched backup source")
end
local result={excludedOwnedJournalRefs=excludedOwnedJournalRefs,passed=#failures==0,failures=failures,comparisons=comparisons,managedInstances=#objects,
protectedAssetInstances=#protected,liveSources=#sources,backupMapInstances=1+#snapshot:GetDescendants(),
backupSources=#backup.LiveSources_Before:GetChildren(),workspaceWrites=0,sourceWrites=0,backupPath=backup:GetFullName()}
shared.CompactMapBaselineProof=result
return result
