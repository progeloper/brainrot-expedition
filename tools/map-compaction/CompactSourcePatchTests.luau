-- Local Lune regression suite. No Studio/world/profile execution or native fit claim.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3
local root=process.args[1] or "."
local function read(path) return fs.readFile(root.."/"..path) end
local cases={}
local function add(name,fn) table.insert(cases,{name=name,run=fn}) end
local function close(a,b,tol) assert(math.abs(a-b)<=(tol or 1e-5),tostring(a).." != "..tostring(b)) end
local function fails(fn,contains)
 local ok,reason=pcall(fn);assert(not ok,"Required fail-closed guard unexpectedly accepted input")
 if contains then assert(tostring(reason):find(contains,1,true),tostring(reason)) end
end
local function clone(value)
 if type(value)~="table" then return value end
 local out={};for k,v in value do out[k]=clone(v) end;return out
end
local methods={}
local mt={__index=function(self,key) return methods[key] or rawget(self,"_data")[key] end,
 __newindex=function(self,key,value)
  local d=rawget(self,"_data")
  if key=="Parent" then
   if d.Parent then local c=rawget(d.Parent,"_children");for i,o in c do if o==self then table.remove(c,i);break end end end
   if value then table.insert(rawget(value,"_children"),self) end
  end
  d[key]=value
 end}
local function object(class,name,parent)
 local result=setmetatable({_data={ClassName=class,Name=name or class,Source="",Value=""},_children={},_attrs={}},mt)
 result.Parent=parent;return result
end
function methods:GetChildren() return table.clone(rawget(self,"_children")) end
function methods:GetAttribute(key) return rawget(self,"_attrs")[key] end
function methods:SetAttribute(key,value) rawget(self,"_attrs")[key]=value end
function methods:GetAttributes() return table.clone(rawget(self,"_attrs")) end
function methods:FindFirstChild(name)
 for _,o in self:GetChildren() do if o.Name==name then return o end end;return nil
end
function methods:IsDescendantOf(parent) local p=self.Parent;while p do if p==parent then return true end;p=p.Parent end;return false end
function methods:GetFullName() return (if self.Parent and self.Parent.Name~="game" then self.Parent:GetFullName().."." else "")..self.Name end
function methods:IsA(class) return self.ClassName==class or (class=="BasePart" and self.ClassName=="Part") end
function methods:Destroy() for _,o in self:GetChildren() do o:Destroy() end;self.Parent=nil;self.Destroyed=true end
local function makeGame()
 local g=object("DataModel","game");g.PlaceId=91958083796436;g.GameId=10548905405
 local ws=object("Workspace","Workspace",g);local ss=object("ServerStorage","ServerStorage",g)
 local rs=object("ReplicatedStorage","ReplicatedStorage",g);local sh=object("Folder","Shared",rs)
 object("Folder","Config",sh);object("Folder","Utility",sh)
 local server=object("ServerScriptService","ServerScriptService",g);local s=object("Folder","Server",server);object("Folder","Systems",s);object("Folder","Services",s)
 local map=object("Model","MapBlockout",ws)
 local guid=0
 local services={RunService={IsStudio=function()return true end,IsRunning=function()return false end},HttpService={JSONDecode=function(_,text)return serde.decode("json",text)end,GenerateGUID=function()guid+=1;return "test-"..guid end},Workspace=ws,ServerStorage=ss,ReplicatedStorage=rs}
 g.GetService=function(_,name)return assert(services[name],name)end
 return g,ws,map,ss
end
local function environment(g,ws,extras)
 local env={game=g,workspace=ws,CFrame=CFrame,Vector3=Vector3,Color3=Color3,Enum=roblox.Enum,Instance={new=function(class)return object(class)end}}
 for k,v in extras or {} do env[k]=v end;return env
end
local function load(source,env,name) return luau.load(source,{debugName=name,environment=env,injectGlobals=true})() end
local g,ws,map=makeGame()
local moduleSource=read("docs/map-compaction/source-patches/proposals/ReplicatedStorage/Shared/Utility/CompactMapGeometry.lua")
local Geometry=load(moduleSource,environment(g,ws),"@CompactMapGeometry")
local function baseGeometry()
 local z={-48.85,-36.67,-24.49,-12.31,-.13,12.05};local slots={}
 for i=1,12 do local side=if i<=6 then -1 else 1;slots[i]={Index=i,Side=side,X=-13.73+side*12.77,Z=z[if i<=6 then i else i-6],PadNormalStuds=13.92,PadTangentialStuds=10.16} end
 return {formationCenterX=-13.73,formationCenterZ=-18.4,rowOffsetX=12.77,zCenters=z,padNormalStuds=13.92,padTangentialStuds=10.16,slots=slots,support={centreX=-13.73,centreZ=-20.38,width=46.26,depth=79.34},perimeter={centreX=-13.73,centreZ=-20.38,width=46.26,depth=79.34,frontSign=-1,postWidth=.5,postDepth=.5}}
end
local function validRaw()
 local raw={schemaVersion=1,migrationId="CompactMap_V1",runtimeValidated=true,planHash=string.rep("a",64),bases={},staticWallObstacles={},services={}}
 for i=1,12 do raw.bases[string.format("Base_%02d",i)]=baseGeometry() end
 for _,name in {"AnnouncementStall","BrainrotTrainStall","BuyCartStall","KitStall","SellStall","WeaponHarpoonStall"} do raw.services[name]={logicalInteractionEnvelope=if name=="BuyCartStall" then {64,1,40} else {56,1,32}} end
 return raw
end
add("Original unmarked layout retains old fallback",function() assert(Geometry.Read(map)==nil) end)
add("Canonical twelve-base data is deeply frozen without mutating inputs",function()
 local raw=validRaw();local before=serde.encode("json",raw);local data=Geometry.Validate(raw)
 assert(table.isfrozen(data) and table.isfrozen(data.bases.Base_01.slots[1]));assert(not table.isfrozen(raw));assert(before==serde.encode("json",raw))
end)
add("Marked missing data fails instead of using old locals",function()
 local _,_,m=makeGame();m:SetAttribute("CompactMapMigrationId","CompactMap_V1");fails(function()Geometry.Read(m)end,"incomplete")
end)
add("Incomplete journal status fails",function()
 local _,_,m=makeGame();m:SetAttribute("CompactMapMigrationId","CompactMap_V1");m:SetAttribute("CompactMapStatus","InProgress");fails(function()Geometry.Read(m)end,"incomplete")
end)
add("Oversized runtime data fails",function()
 local _,_,m=makeGame();m:SetAttribute("CompactMapMigrationId","CompactMap_V1");m:SetAttribute("CompactMapStatus","Completed")
 local v=object("StringValue","CompactMapRuntimeGeometry",m);v.Value=string.rep("x",200001);fails(function()Geometry.Read(m)end,"oversize")
end)
add("Wrong plan hash fails before cache is accepted",function()
 local _,_,m=makeGame();m:SetAttribute("CompactMapMigrationId","CompactMap_V1");m:SetAttribute("CompactMapStatus","Completed");m:SetAttribute("CompactMapDesiredHash",string.rep("b",64))
 object("StringValue","CompactMapRuntimeGeometry",m).Value=serde.encode("json",validRaw());fails(function()Geometry.Read(m)end,"hash mismatch")
end)
add("Runtime cache refuses a mid-session manifest change",function()
 local _,_,m=makeGame();m:SetAttribute("CompactMapMigrationId","CompactMap_V1");m:SetAttribute("CompactMapStatus","Completed");m:SetAttribute("CompactMapDesiredHash",string.rep("a",64))
 local v=object("StringValue","CompactMapRuntimeGeometry",m);v.Value=serde.encode("json",validRaw());Geometry.Read(m);v.Value=v.Value.." ";fails(function()Geometry.Read(m)end,"restart required")
end)
add("Missing base and stable slot reorder are rejected",function()
 local raw=validRaw();raw.bases.Base_12=nil;fails(function()Geometry.Validate(raw)end,"twelve bases")
 raw=validRaw();raw.bases.Base_01.slots[1].Index=2;fails(function()Geometry.Validate(raw)end,"identity/order")
end)
add("Individual slot nudges and nonuniform row strides are rejected",function()
 local raw=validRaw();raw.bases.Base_01.slots[4].X+=.05;fails(function()Geometry.Validate(raw)end,"uniform final")
 raw=validRaw();raw.bases.Base_01.zCenters[4]+=.1;fails(function()Geometry.Validate(raw)end,"uniform")
end)
add("Double-added formation centroid and missing post dimensions fail",function()
 local raw=validRaw();raw.bases.Base_01.formationCenterZ=0;fails(function()Geometry.Validate(raw)end,"centroid")
 raw=validRaw();raw.bases.Base_01.perimeter.postWidth=nil;fails(function()Geometry.Validate(raw)end,"finite number")
end)
add("Pad support is checked in absolute final local space",function()
 local raw=validRaw();raw.bases.Base_01.support.depth=64;fails(function()Geometry.Validate(raw)end,"outside")
end)
local function serviceFixture(name)
 local _,localWs,m=makeGame();m:SetAttribute("CompactMapMigrationId","CompactMap_V1");m:SetAttribute("CompactMapStatus","Completed");m:SetAttribute("CompactMapDesiredHash",string.rep("a",64))
 object("StringValue","CompactMapRuntimeGeometry",m).Value=serde.encode("json",validRaw())
 local p=object("Part",name,object("Folder","ServiceStallPatches",m));p.Size=Vector3.new(28,1,22);p.CFrame=CFrame.new(100,.55,-40)*CFrame.Angles(0,.8,0);p:SetAttribute("LayoutRole","ServiceStall")
 p:SetAttribute("LogicalInteractionEnvelope",if name=="BuyCartStall" then Vector3.new(64,1,40) else Vector3.new(56,1,32))
 return p,localWs,m
end
add("Unmarked service keeps original actual size",function()
 local _,_,m=makeGame();local p=object("Part","SellStall",m);p.Size=Vector3.new(56,1,32);assert(Geometry.ResolveInteractionSize(p)==p.Size)
end)
add("Missing or changed canonical service envelope fails closed",function()
 local raw=validRaw();raw.services=nil;fails(function()Geometry.Validate(raw)end,"services required")
 raw=validRaw();raw.services.SellStall.logicalInteractionEnvelope={28,1,22};fails(function()Geometry.Validate(raw)end,"envelope changed")
 raw=validRaw();raw.services.Extra={logicalInteractionEnvelope={56,1,32}};fails(function()Geometry.Validate(raw)end,"identity invalid")
end)
add("Compact service retains captured logical size despite smaller support",function()
 for _,name in {"SellStall","BuyCartStall"} do local p=serviceFixture(name);local expected=if name=="BuyCartStall" then Vector3.new(64,1,40) else Vector3.new(56,1,32);assert(Geometry.ResolveInteractionSize(p)==expected and p.Size~=expected) end
end)
add("Missing or drifting actual service envelope is rejected",function()
 local p=serviceFixture("SellStall");p:SetAttribute("LogicalInteractionEnvelope",nil);fails(function()Geometry.ResolveInteractionSize(p)end,"missing/invalid")
 p:SetAttribute("LogicalInteractionEnvelope",Vector3.new(28,1,22));fails(function()Geometry.ResolveInteractionSize(p)end,"drifted")
end)
add("Compact service rejects changed owner or role",function()
 local p=serviceFixture("SellStall");p:SetAttribute("LayoutRole","Other");fails(function()Geometry.ResolveInteractionSize(p)end,"identity/owner")
 p:SetAttribute("LayoutRole","ServiceStall");p.Parent=object("Folder","Other",p.Parent.Parent);fails(function()Geometry.ResolveInteractionSize(p)end,"identity/owner")
end)
local wallRows={{id="L",minX=-3,maxX=3,minY=-2,maxY=24,minZ=-90,maxZ=-20},{id="R",minX=-3,maxX=3,minY=-2,maxY=24,minZ=20,maxZ=90}}
local walls=Geometry.BuildWallIndex(wallRows)
add("Actual wall overlap is blocked",function() assert(Geometry.WallHit(walls,CFrame.new(0,3,30),Vector3.new(4,6,4),0)=="R") end)
add("Full aperture remains open",function() assert(Geometry.WallHit(walls,CFrame.new(0,3,0),Vector3.new(24,6,36),0)==nil) end)
add("Only positive overlap is blocked at an exact edge",function()
 assert(Geometry.WallHit(walls,CFrame.new(5,3,30),Vector3.new(4,6,4),0)==nil)
 assert(Geometry.WallHit(walls,CFrame.new(4.99,3,30),Vector3.new(4,6,4),0)=="R")
end)
add("Spawn clearance applies two studs outside the wall",function()
 assert(Geometry.WallHit(walls,CFrame.new(6,3,30),Vector3.new(2,6,2),0)==nil)
 assert(Geometry.WallHit(walls,CFrame.new(5.99,3,30),Vector3.new(2,6,2),2)=="R")
end)
add("Wall mask respects vertical separation",function() assert(Geometry.WallHit(walls,CFrame.new(0,27,30),Vector3.new(4,6,4),0)==nil) end)
add("All rotated half axes participate in conservative footprint projection",function()
 assert(Geometry.WallHit(walls,CFrame.new(5,3,30)*CFrame.Angles(0,math.pi/4,0),Vector3.new(2,6,8),0)=="R")
end)
add("Malformed dense arrays and duplicate wall IDs fail",function()
 fails(function()Geometry.BuildWallIndex({[2]=wallRows[1]})end,"sparse")
 fails(function()Geometry.BuildWallIndex({wallRows[1],wallRows[1]})end,"duplicate")
end)
add("Huge wall and query spans fail before an unbounded loop",function()
 local huge=clone(wallRows[1]);huge.maxX=1e10;fails(function()Geometry.BuildWallIndex({huge})end,"cell budget")
 fails(function()Geometry.WallHit(walls,CFrame.new(),Vector3.new(1e10,3,1e10),0)end,"cell budget")
 fails(function()Geometry.WallHit(walls,CFrame.new(),Vector3.new(-1,3,2),0)end,"size invalid")
end)
local ownerSource=read("docs/map-compaction/source-patches/proposals/ServerScriptService/Server/Systems/BaseIncomePlaqueSystem.lua")
local function extract(source,name)
 local start=assert(source:find("local function "..name.."(",1,true),name);local finish=assert(source:find("\nend",start,true),name)
 return source:sub(start,finish+3)
end
local defaults={PLATFORM_COUNT=12,PLATFORMS_PER_SIDE=6,PLATFORM_ROW_OFFSET_X=7.25,PLATFORM_SIDE_STUDS=3/math.sqrt(2),PLATFORM_Z_CENTERS={-11.25,-6.75,-2.25,2.25,6.75,11.25},BASE_FOOTPRINT_WIDTH_STUDS=36,BASE_FOOTPRINT_DEPTH_STUDS=32,PLAQUE_TOUCH_HEIGHT_STUDS=1}
local makePositions=extract(ownerSource,"setMarkerFacing").."\n"..extract(ownerSource,"positionPlatforms").."\nreturn positionPlatforms"
local position=load(makePositions,environment(g,ws,{Config=defaults,platformIdFromPart=function(p)return p.Id end,platformTopLocalY=function(rootFrame,p)return rootFrame:PointToObjectSpace(p.CFrame.Position).Y+p.Size.Y/2 end}),"@ActualProposedPositionPlatforms")
local function platformSlots(frame)
 local slots={}
 for i=1,12 do local p={Id=i,Size=Vector3.new(10,.75,10),CFrame=frame*CFrame.new(0,1,0)};local marker=object("Attachment");marker.CFrame=CFrame.new(.1,.375,.2)
  slots[i]={Index=i,Platform=p,Marker=marker}
 end;return slots
end
add("Actual proposed owner preserves old layout when compact data is absent",function()
 local frame=CFrame.new(100,2,-40)*CFrame.Angles(0,math.pi,0);local slots=platformSlots(frame);local data=position(frame,slots,nil)
 close(frame:PointToObjectSpace(slots[1].Platform.CFrame.Position).X,-7.25);close(data[1].ZCenter,-11.25);close(slots[1].Platform.Size.X,3/math.sqrt(2));close(data[1].PlatformTopY,1.375)
end)
add("Actual owner uses final local slots once and correct rectangular pad axes",function()
 local frame=CFrame.new(100,2,-40)*CFrame.Angles(0,math.pi,0);local slots=platformSlots(frame);local data=position(frame,slots,baseGeometry())
 for i=1,12 do local localP=frame:PointToObjectSpace(slots[i].Platform.CFrame.Position);close(localP.X,baseGeometry().slots[i].X);close(localP.Z,baseGeometry().slots[i].Z);close(slots[i].Platform.Size.X,10.16);close(slots[i].Platform.Size.Z,13.92);close(slots[i].Marker.CFrame.Y,.375);assert(data[i].PlatformNormalStuds==13.92 and data[i].Side==baseGeometry().slots[i].Side) end
 local facing=frame:VectorToObjectSpace(slots[1].Platform.CFrame.LookVector);close(facing.X,1);close(facing.Z,0)
end)
add("Actual owner repeats without rescaling coordinates or pads",function()
 local frame=CFrame.new(100,2,-40);local slots=platformSlots(frame);position(frame,slots,baseGeometry());local before=slots[1].Platform.CFrame;position(frame,slots,baseGeometry());assert(slots[1].Platform.CFrame==before);close(slots[1].Platform.Size.Z,13.92)
end)
local postRows={}
local perimeter=load(extract(ownerSource,"createPillarsAlongEdge").."\n"..extract(ownerSource,"createPerimeterPillars").."\nreturn createPerimeterPillars",environment(g,ws,{Config=defaults,PILLAR_ORIGINAL_WIDTH_STUDS=1.25,PILLAR_ORIGINAL_DEPTH_STUDS=1.25,PILLAR_WIDTH_STUDS=.625,PILLAR_DEPTH_STUDS=.625,PILLAR_MAX_SPACING_STUDS=6,ENTRANCE_CLEAR_WIDTH_STUDS=10,clearManagedPillars=function()table.clear(postRows)end,entranceSign=function()return -1 end,createPillar=function(_,_,name,point,_,_,style)table.insert(postRows,{name=name,point=point,style=style})end}),"@ActualProposedPerimeter")
add("Actual perimeter opening follows shifted aisle and final post widths",function()
 local geometry=baseGeometry();perimeter({}, {}, CFrame.new(),0,10,{},geometry)
 local frontZ=geometry.perimeter.centreZ-(geometry.perimeter.depth-1)/2
 for _,post in postRows do
  assert(post.style.PostWidth==.5 and post.style.PostDepth==.5)
  if math.abs(post.point.Z-frontZ)<1e-6 then assert(math.abs(post.point.X+13.73)>=5,"Post blocks shifted entrance") end
 end
 assert(#postRows>0)
end)
add("Plaque inner edges retain a six-stud usable collection aisle",function()
 local geometry=baseGeometry();local left=geometry.slots[1].X+geometry.padNormalStuds/2+.55+2.25
 local right=geometry.slots[7].X-geometry.padNormalStuds/2-.55-2.25;close(right-left,6.02)
 assert(ownerSource:find("local plaqueX = placement.XCenter - placement.Side * inward",1,true))
end)
add("Compact Foundation branch retains original visual and physical fields",function()
 local container=object("Folder","IncomePlaqueLayout");local base=object("Model","Base_01");local floor=object("Part","Foundation",base)
 floor:SetAttribute("LayoutRole","Foundation");floor.Size=Vector3.new(96,1,64);floor.CFrame=CFrame.new(0,.5,0);floor.Color=Color3.fromRGB(238,246,255);floor.CanTouch=false;floor.CanCollide=true;floor.Physics="frozen-original"
 local configureCalls,materialCalls=0,0
 local fn=load(extract(ownerSource,"ensureInterior").."\nreturn ensureInterior",environment(g,ws,{LAYOUT_CONTAINER_NAME="IncomePlaqueLayout",LEGACY_WALL_NAMES={},Config=defaults,ensureFolder=function()return container end,StaticMaterial={Apply=function(p)assert(p==floor);materialCalls+=1 end},configureStructuralPart=function()configureCalls+=1 end,platformTopLocalY=function()return 1 end,captureStructuralStyle=function(p)return {Color=p.Color}end,removeLegacyWalls=function()end,createPerimeterPillars=function()end}),"@ActualFoundationOwner")
 fn(base,CFrame.new(),1,baseGeometry());assert(configureCalls==0 and materialCalls==1);assert(floor.Color==Color3.fromRGB(238,246,255) and floor.CanTouch==false and floor.CanCollide==true and floor.Physics=="frozen-original")
end)
add("Actual sale and upgrade range calculations match captured ranges",function()
 local interaction={SELL_INTERACTION_DISTANCE=12,SELL_SERVER_DISTANCE_TOLERANCE=2}
 for _,row in {{name="SellStall",path="ServerScriptService/Server/Systems/BrainrotSaleSystem.lua",fn="isPlayerWithinSaleRange"},{name="BuyCartStall",path="ServerScriptService/Server/Services/UpgradeService.lua",fn="withinShopRange"}} do
  local part,localWs=serviceFixture(row.name);local before=read("docs/map-compaction/live-sources/"..row.path);local after=read("docs/map-compaction/source-patches/proposals/"..row.path)
  local context={Root={Position=Vector3.zero}};local oldPart=object("Part",row.name,localWs);oldPart.Size=Geometry.ResolveInteractionSize(part);oldPart.CFrame=part.CFrame
  local function range(source,target)
   return load(extract(source,row.fn).."\nreturn "..row.fn,environment(g,localWs,{Workspace=localWs,InteractionConfig=interaction,CompactMapGeometry=Geometry,getSalePoint=function()return target end,playerRoot=function()return context.Root end,deps=function()return {}end}),"@ActualServiceRange")
  end
  local original,patched=range(before,oldPart),range(after,part)
  for _,x in {-60,-42,-29,0,29,42,60} do for _,z in {-48,-32,-17,0,17,32,48} do for _,y in {0,7,20} do
   context.Root.Position=part.CFrame:PointToWorldSpace(Vector3.new(x,y,z));assert(original(context,oldPart)==patched(context,part),row.name.." range changed")
  end end end
 end
end)
add("All six historical tools reject any partial or complete compact marker",function()
 local manifest=serde.decode("json",read("docs/map-compaction/source-patches/SourcePatchManifest.json"))
 for _,row in manifest.guardedInstallerProposals do
  local source=read(row.proposal);local finish=assert(source:find("\nend\n",1,true));local guard=source:sub(1,finish+4).."\nreturn true"
  for _,mark in {"CompactMapMigrationId","CompactMapStatus","CompactMapDesiredHash","CompactMapRuntimeGeometry"} do
   local localGame,localWs,localMap=makeGame()
   assert(load(guard,environment(localGame,localWs),"@HistoricalGuard") == true)
   if mark=="CompactMapRuntimeGeometry" then object("StringValue",mark,localMap) else localMap:SetAttribute(mark,"partial") end
   fails(function()load(guard,environment(localGame,localWs),"@HistoricalGuard")end,"Historical installer is superseded")
  end
 end
end)
local payload=serde.decode("json",read("docs/map-compaction/source-patches/SourcePatchPayload.json"))
local applySource=read("tools/map-compaction/ApplyCompactSourcePatches.luau")
local function sourceFixture()
 local gameObj,work,mapObj,ss=makeGame()
 local function resolve(path)
  local current=gameObj;for part in path:gmatch("[^%.]+") do current=assert(current:FindFirstChild(part),path) end;return current
 end
 for _,patch in payload.patches do local pp,name=patch.path:match("^(.*)%.([^%.]+)$");local target=object("ModuleScript",name,resolve(pp));target.Source=patch.beforeSource;target:SetAttribute("ExistingUnrelated",17) end
 local backups=object("Folder","MapCompactionBackups",ss);local backup=object("Folder","CompactMap_V1_3fb9d9e8a543",backups);backup:SetAttribute("BaselineManagedSHA256","3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310")
 local api=load(applySource,environment(gameObj,work),"@ActualSourceTransaction")
 return api,resolve,mapObj,ss
end
local options={baselineVerified=true,nativeOwnerFitVerified=true,verifiedPlanHash=string.rep("a",64)}
add("Source transaction requires actual-fit and recoverable-baseline attestations",function()
 local api=sourceFixture();fails(function()api.Apply({baselineVerified=true,verifiedPlanHash=string.rep("a",64)})end,"actual compact owner-fit")
end)
add("Source transaction prepares only exact five owners plus one module",function()
 local api,resolve=sourceFixture();local report=api.Apply(options);assert(report.created==1 and report.updated==#payload.patches and report.sourceWrites==#payload.patches+1 and report.worldWrites==0);assert(api.Verify().exactPatchedOwners==#payload.patches)
 for _,patch in payload.patches do assert(resolve(patch.path).Source==patch.afterSource and resolve(patch.path):GetAttribute("ExistingUnrelated")==17) end
end)
add("Unchanged source transaction writes zero on rerun",function()
 local api=sourceFixture();api.Apply(options);local report,journal=api.Apply(options);assert(report.created==0 and report.updated==0 and report.sourceWrites==0 and report.retained==#payload.patches+1 and journal==nil)
end)
add("Unrelated live-source drift is rejected before any write",function()
 local api,resolve,_,ss=sourceFixture();resolve(payload.patches[2].path).Source="unrelated dirty update";local before=#ss:GetChildren();fails(function()api.Apply(options)end,"drifted")
 assert(resolve(payload.patches[1].path).Source==payload.patches[1].beforeSource and #ss:GetChildren()==before)
end)
add("All six injected transaction failures restore original contents and remove new owner",function()
 for n=1,#payload.patches+1 do
  local api,resolve=sourceFixture();local fault=clone(options);fault.faultAfterSourceWrites=n;fails(function()api.Apply(fault)end,"rolled back")
  for _,patch in payload.patches do assert(resolve(patch.path).Source==patch.beforeSource) end
  assert(resolve("ReplicatedStorage.Shared.Utility"):FindFirstChild("CompactMapGeometry")==nil)
 end
end)
add("Committed source journal supports explicit complete rollback",function()
 local api,resolve=sourceFixture();local _,journal=api.Apply(options);local report=api.Rollback(journal);assert(report.restoredOriginalSources==#payload.patches and report.removedNewOwners==1)
 for _,patch in payload.patches do assert(resolve(patch.path).Source==patch.beforeSource) end
end)
add("Rollback refuses to erase an unrelated subsequent source edit",function()
 local api,resolve=sourceFixture();local _,journal=api.Apply(options);resolve(payload.patches[2].path).Source="later unrelated edit";fails(function()api.Rollback(journal)end,"Unrelated source drift")
 assert(resolve(payload.patches[1].path).Source==payload.patches[1].afterSource)
end)
add("Read-only rollback preflight verifies identities without changing any source",function()
 local api,resolve=sourceFixture();local _,journal=api.Apply(options);local report=api.ValidateRollback(journal)
 assert(report.sourceWrites==0 and report.checkedOriginalSources==#payload.patches and report.checkedNewOwners==1)
 for _,patch in payload.patches do assert(resolve(patch.path).Source==patch.afterSource) end
 resolve(payload.patches[1].path).Source="unrelated";fails(function()api.ValidateRollback(journal)end,"Unrelated source drift")
end)
add("Rollback rejects duplicate or out-of-scope journal rows before writing",function()
 local api,resolve=sourceFixture();local _,journal=api.Apply(options)
 local record=journal:FindFirstChild("Source_01");local extra=object("Folder","Duplicate",journal);extra:SetAttribute("Path",record:GetAttribute("Path"))
 for _,child in record:GetChildren() do local c=object(child.ClassName,child.Name,extra);c.Value=child.Value end
 fails(function()api.ValidateRollback(journal)end,"unknown/duplicate")
 for _,patch in payload.patches do assert(resolve(patch.path).Source==patch.afterSource) end
end)
local rootApplySource=read("tools/map-compaction/Apply.luau")
local persist=load(extract(rootApplySource,"persistJSON").."\nreturn persistJSON",environment(g,ws,{MIGRATION="CompactMap_V1"}),"@ActualWorldJournalPersist")
add("Persistent world journal chunks preserve exact JSON at UTF-8 boundaries",function()
 local journal=object("Folder","Journal");local text='{"payload":"'..string.rep("a",59987).."é"..string.rep("b",60001).."🐒"..'"}'
 persist(journal,"RuntimeGeometry_JSON_Chunks",text,string.rep("a",64));local folder=journal:FindFirstChild("RuntimeGeometry_JSON_Chunks");assert(folder:GetAttribute("Bytes")==#text and folder:GetAttribute("ChunkCount")==3 and folder:GetAttribute("DesiredHash")==string.rep("a",64))
 local values={};for _,v in folder:GetChildren() do assert(#v.Value<=60000 and utf8.len(v.Value));table.insert(values,v.Value) end
 assert(table.concat(values)==text);assert(serde.decode("json",table.concat(values)).payload==serde.decode("json",text).payload)
end)
local function rollbackFixture()
 local gameObj,localWs,_,ss=makeGame();gameObj.ServerStorage=ss
 local backupRoot=object("Folder","MapCompactionBackups",ss);ss.MapCompactionBackups=backupRoot
 local backup=object("Folder","CompactMap_V1_3fb9d9e8a543",backupRoot);local chunks=object("Folder","BeforeManifest_JSON_Chunks",backup);backup.BeforeManifest_JSON_Chunks=chunks
 local rootNode=object("Folder","CapturedMap",localWs);local group=object("Folder","OwnedFolder",rootNode);local leaf=object("Part","OwnedPart",group)
 local function row(key,name,class,parent) return {key=key,path=name,parent=parent,name=name,class=class,attributes={},tags={},archivable=true} end
 local baseline={objects={row("MAP","CapturedMap","Folder","game/Workspace:Workspace[1]"),row("GROUP","OwnedFolder","Folder","MAP"),row("LEAF","OwnedPart","Part","GROUP")},externalStaticObjects={}}
 local value=object("StringValue","Chunk_0001",chunks);value.Value=serde.encode("json",baseline)
 local txn=object("Folder","Transaction",ss);txn:SetAttribute("MigrationId","CompactMap_V1");txn:SetAttribute("BaselineSHA256","3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310")
 txn.OriginalRefs=object("Folder","OriginalRefs",txn);txn.MeshBackups=object("Folder","MeshBackups",txn);object("Folder","CreatedRefs",txn)
 local refs={};for _,pair in {{"MAP",rootNode},{"GROUP",group},{"LEAF",leaf}} do local ref=object("ObjectValue",pair[1],txn.OriginalRefs);ref:SetAttribute("OriginalKey",pair[1]);ref.Value=pair[2];refs[pair[1]]=ref end
 local sourceJournal=object("Folder","SourceJournalActual",ss);object("ObjectValue","SourceJournal",txn).Value=sourceJournal
 local sourceCalls=0;local sourceAPI={ValidateRollback=function()sourceCalls+=1 end,Rollback=function()sourceCalls+=1 end}
 local originalGet=gameObj.GetService;gameObj.GetService=function(_,name)if name=="CollectionService" then return {GetTags=function()return {}end,RemoveTag=function()end,AddTag=function()end}end;return originalGet(gameObj,name)end
 local api=load(read("tools/map-compaction/Rollback.luau"),environment(gameObj,localWs),"@ActualRootWorldRollback")
 return api,txn,sourceAPI,refs,baseline,value,rootNode,group,leaf,localWs,function()return sourceCalls end
end
add("World rollback rejects missing captured internal parent before source writes",function()
 local api,txn,sourceAPI,refs,_,_,_,_,_,_,calls=rollbackFixture();refs.GROUP:Destroy();fails(function()api.Rollback(txn,sourceAPI)end,"baseline reference missing");assert(calls()==0)
end)
add("World rollback rejects an unknown external parent before source writes",function()
 local api,txn,sourceAPI,_,baseline,value,_,_,_,_,calls=rollbackFixture();baseline.objects[1].parent="OtherExternal";value.Value=serde.encode("json",baseline);fails(function()api.Rollback(txn,sourceAPI)end,"external rollback parent");assert(calls()==0)
end)
add("World rollback restores exact captured internal and external parents",function()
 local api,txn,sourceAPI,_,_,_,rootNode,group,leaf,localWs,calls=rollbackFixture();local wrong=object("Folder","WrongParent",localWs);rootNode.Parent=wrong;leaf.Parent=rootNode
 local report=api.Rollback(txn,sourceAPI);assert(report.passed and report.restoredOriginalObjects==3 and calls()==2 and rootNode.Parent==localWs and group.Parent==rootNode and leaf.Parent==group and txn:GetAttribute("Status")=="RolledBack")
end)
local result={schemaVersion=1,scope="Compact source proposals and read-only runtime geometry",runtime="Official local Lune 0.10.5",actualNativeFit="NotRunByThisSuite",studioWrites=0,gameplayRequires=0,passed=0,failed=0,cases={}}
for _,test in cases do
 local ok,reason=pcall(test.run);table.insert(result.cases,{name=test.name,passed=ok,error=if ok then nil else tostring(reason)})
 if ok then result.passed+=1 else result.failed+=1;print(test.name..": "..tostring(reason)) end
end
fs.writeFile(root.."/docs/map-compaction/source-patches/SourcePatchTestResults.json",serde.encode("json",result,true))
print(string.format("%d passed, %d failed",result.passed,result.failed));assert(result.failed==0,"Compact source regressions failed")
