local Run=game:GetService("RunService")
local CS=game:GetService("CollectionService")
local Http=game:GetService("HttpService")
local SS=game:GetService("ServerStorage")
local BASE_PROPERTIES = {"CFrame","Size","PivotOffset","Anchored","CanCollide","CanTouch","CanQuery","CollisionGroup","Transparency","Reflectance","CastShadow","Material","MaterialVariant","Color","CustomPhysicalProperties","CurrentPhysicalProperties","TopSurface","BottomSurface","LeftSurface","RightSurface","FrontSurface","BackSurface"}
local function near(a,b)
 if typeof(a)~=typeof(b)then return false end
 if type(a)=="table"then for k,v in pairs(a)do if not near(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
 if typeof(a)=="number"then return math.abs(a-b)<=1e-6 end
 return a==b
end

local function encoded(v)
 local kind=typeof(v)
 if kind=="CFrame"then return {type=kind,value={v:GetComponents()}}end
 if kind=="Vector3"then return {type=kind,value={v.X,v.Y,v.Z}}end
 if kind=="Vector2"then return {type=kind,value={v.X,v.Y}}end
 if kind=="Color3"then return {type=kind,value={v.R,v.G,v.B}}end
 if kind=="PhysicalProperties"then return {type=kind,value={v.Density,v.Friction,v.Elasticity,v.FrictionWeight,v.ElasticityWeight}}end
 if kind=="EnumItem"then return {type=kind,value=tostring(v)}end
 if kind=="Instance"then return v end
 return v
end

local function indexedKeys(roots)
 local keys={}
 local function key(node)
  if node==game then return "game"end
  if keys[node]then return keys[node]end
  local index=1
  for _,sibling in node.Parent:GetChildren()do
   if sibling==node then break end
   if sibling.Name==node.Name and sibling.ClassName==node.ClassName then index+=1 end
  end
  local value=key(node.Parent).."/"..node.ClassName..":"..node.Name.."["..index.."]"
  keys[node]=value;return value
 end
 local map={}
 for _,root in roots do map[key(root)]=root;for _,node in root:GetDescendants()do map[key(node)]=node end end
 return map
end

local function snapshot(roots)
 local result={}
 for _,root in roots do
  local nodes=root:GetDescendants();table.insert(nodes,root)
  for _,node in nodes do
   local row={Parent=node.Parent,Name=node.Name,Archivable=node.Archivable,Attributes=node:GetAttributes(),Tags=CS:GetTags(node),Properties={},Children=node:GetChildren()}
   table.sort(row.Tags)
   if node:IsA("BasePart")then
    for _,name in BASE_PROPERTIES do row.Properties[name]=encoded(node[name])end
    row.Properties.Mass=node:GetMass()
    if node:IsA("PartOperation")then row.Properties.ExtentsCFrame=encoded(node.ExtentsCFrame);row.Properties.ExtentsSize=encoded(node.ExtentsSize)end
    if node:IsA("MeshPart")then for _,name in {"MeshId","TextureID","CollisionFidelity","RenderFidelity","DoubleSided"}do row.Properties[name]=encoded(node[name])end end
    if node:IsA("UnionOperation")then for _,name in {"UsePartColor","AssetId","CollisionFidelity","RenderFidelity","SmoothingAngle"}do local ok,value=pcall(function()return node[name]end);if ok then row.Properties[name]=encoded(value)end end end
   end
   if node:IsA("Attachment")then row.Properties.CFrame=encoded(node.CFrame);row.Properties.WorldCFrame=encoded(node.WorldCFrame)end
   if node:IsA("Model")then row.Properties.Pivot=encoded(node:GetPivot());row.Properties.Scale=node:GetScale();row.Properties.PrimaryPart=node.PrimaryPart;row.Properties.WorldPivot=encoded(node.WorldPivot)end
   if node:IsA("LuaSourceContainer")then row.Properties.Source=node.Source end
   result[node]=row
  end
 end
 return result
end

local function assertPreserved(before,roots)
 local after=snapshot(roots);local count=0
 for node,row in pairs(before)do assert(near(row,after[node]),"Original changed during fit audit: "..row.Name);count+=1 end
 for node in pairs(after)do assert(before[node],"New original-root descendant during audit: "..node:GetFullName())end
 return count
end

local function guardBaseline(baseline,roots)
 assert(baseline and baseline.migrationId=="CompactMap_V1","Pass the fresh complete BeforeManifest")
 assert(baseline.baselineManagedContentSHA256=="3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310","Wrong immutable managed baseline")
 assert(baseline.protectedAssetsContentSHA256=="bd66b9485de2f171ae7f33e2b5c5480e48f685d14126131cd53513b4f94b6a43","Wrong protected baseline")
 local current=indexedKeys(roots);local checked=0
 for _,rows in {baseline.objects,baseline.protectedSourceAssets}do
  for _,row in rows do
   local node=assert(current[row.key],"Baseline node missing "..row.path)
   assert(node.ClassName==row.class and node.Name==row.name,"Baseline identity changed "..row.path)
   assert(near((function()local out={};for k,v in pairs(node:GetAttributes())do out[k]=encoded(v)end;return out end)(),row.attributes),"Baseline attributes changed "..row.path)
   if row.properties then for name,value in pairs(row.properties)do
    if not (type(value)=="table" and value.unavailable)then assert(near(encoded(node[name]),value),"Baseline property changed "..row.path.."."..name)end
   end end
   if row.attachment then for _,name in {"CFrame","WorldCFrame"}do assert(near(encoded(node[name]),row.attachment[name]),"Baseline attachment changed "..row.path)end end
   if row.pivot then assert(near(encoded(node:GetPivot()),row.pivot),"Baseline pivot changed "..row.path);assert(node:GetScale()==row.scale,"Baseline scale changed "..row.path)end
   checked+=1
  end
 end
 local actual=0;for _ in pairs(current)do actual+=1 end
 assert(actual==checked,"Extra managed/protected objects appeared after capture")
 return checked
end
local G={}
function G.Run(options,operation)
 assert(Run:IsStudio()and not Run:IsRunning(),"Native compact fixture requires Edit")
 assert(game.PlaceId==91958083796436 and game.GameId==10548905405,"Wrong DEV")
 local adapter=assert(options.Adapter,"Fresh adapter required");adapter.CheckSources()
 local roots={assert(workspace:FindFirstChild("MapBlockout")),assert(game.ReplicatedStorage:FindFirstChild("StudioAssets"))}
 local checked=guardBaseline(assert(options.Baseline,"Fresh baseline required"),roots)
 local before=snapshot(roots)
 local stage=Instance.new("Folder");stage.Name="CompactMapV1_BaseFixture_"..Http:GenerateGUID(false);stage:SetAttribute("Owner","CompactMap_V1_BaseFixture");stage.Parent=SS
 local start=os.clock()
 local ok,result=xpcall(function()return operation(stage,adapter.Create())end,debug.traceback)
 stage:Destroy()
 local unchanged=assertPreserved(before,roots);adapter.CheckSources()
 assert(ok,"Native fixture failed; owned stage removed and originals unchanged: "..tostring(result))
 result.cleanup={stageRemoved=stage.Parent==nil,originalInstancesUnchanged=unchanged,originalSourcesUnchanged=true};result.baselineNodesChecked=checked;result.elapsedSeconds=os.clock()-start;result.nativeExecutionPassed=true
 return result
end
return G
