--!nocheck
-- Source-only native Edit audit. Mutations are restricted to owned ServerStorage clones.
-- No gameplay module require, Source writes, camera, Play, player/profile or original geometry writes.
local Run = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local Http = game:GetService("HttpService")
local SS = game:GetService("ServerStorage")
local API = {}
local EPS = 0.0001
local FACTORS = {0.75,0.8,0.85,0.9,0.95,1}
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
local function plainBounds(low,high)
 return {min={low.X,low.Y,low.Z},max={high.X,high.Y,high.Z},size={high.X-low.X,high.Y-low.Y,high.Z-low.Z}}
end
local function nativeEnvelope(model,reference,scaleOwner)
 local low,high=Vector3.one*math.huge,Vector3.one*-math.huge
 local count,native=0,0
 for _,part in model:GetDescendants()do
  if part:IsA("BasePart")and scaleOwner.IsVisualPart(part,model)then
   local cf,size=part.CFrame,part.Size
   if part:IsA("PartOperation")then cf,size=part.ExtentsCFrame,part.ExtentsSize;native+=1 end
   local frame=reference:ToObjectSpace(cf);local half=size/2
   for _,x in {-1,1}do for _,y in {-1,1}do for _,z in {-1,1}do
    local point=frame*(half*Vector3.new(x,y,z));low=low:Min(point);high=high:Max(point)
   end end end
   count+=1
  end
 end
 assert(count>0,"No native visible geometry")
 return plainBounds(low,high),count,native
end
-- A centred full-support pad cannot be shifted away from its prescribed slot centre.
function API.SupportPad(bounds,currentSize,margin)
 margin=margin or 1
 return {
  x=math.max(currentSize.X,2*(math.max(math.abs(bounds.min[1]),math.abs(bounds.max[1]))+margin)),
  z=math.max(currentSize.Z,2*(math.max(math.abs(bounds.min[3]),math.abs(bounds.max[3]))+margin)),
 }
end
function API.SignedGap(left,right,axis)return right.min[axis]-left.max[axis]end
function API.TranslateBounds(bounds,delta)
 return {min={bounds.min[1]+delta.X,bounds.min[2]+delta.Y,bounds.min[3]+delta.Z},max={bounds.max[1]+delta.X,bounds.max[2]+delta.Y,bounds.max[3]+delta.Z},size=table.clone(bounds.size)}
end
local function padBounds(cf,root,size)
 local low,high=Vector3.one*math.huge,Vector3.one*-math.huge
 local frame=root:ToObjectSpace(cf)
 for _,x in {-1,1}do for _,z in {-1,1}do local p=frame*Vector3.new(x*size.x/2,0,z*size.z/2);low=low:Min(p);high=high:Max(p)end end
 return plainBounds(low,high)
end
local function slotsFor(base)
 local slots={}
 for _,part in base:GetChildren()do
  local index=part:GetAttribute("SlotIndex")or tonumber(part.Name:match("^Slot_(%d+)$"))
  if index~=nil then
   assert(part:IsA("BasePart")and index%1==0 and index>=1 and index<=12 and slots[index]==nil,"Bad isolated slot identity")
   local marker=assert(part:FindFirstChild("BrainrotPlacement"),"Missing marker")
   assert(marker:IsA("Attachment")or marker:IsA("BasePart"),"Bad marker class")
   slots[index]={Index=index,Platform=part,Marker=marker}
  end
 end
 for i=1,12 do assert(slots[i],"Missing isolated slot "..i)end
 return slots
end
local function stripCloneTags(clone)
 local nodes=clone:GetDescendants();table.insert(nodes,clone)
 for _,node in nodes do
  for _,tag in CS:GetTags(node)do CS:RemoveTag(node,tag)end
  if node:IsA("LuaSourceContainer")then node:Destroy()end
 end
end
local function measureCandidate(baseName,root,slots,measured,b,currentPadSizes)
 local out={baseId=baseName,b=b,placementRule="Runtime owner slots contracted horizontally from immutable baseline; yaw/marker offsets/display scale preserved",required={visibleGap=2,padGap=2,collectionAisle=6,supportMarginEachSide=1},minimumVisibleGap=math.huge,minimumPadGap=math.huge,minimumCollectionAisle=math.huge,maximumSupportOverflow=0,witnesses={},speciesCases=#measured}
 local poses={}
 for index,slot in slots do
  local old=root:ToObjectSpace(slot.Platform.CFrame)
  poses[index]={old=old,new=root*CFrame.new(old.X*b,old.Y,old.Z*b)*old.Rotation,delta=Vector3.new(old.X*(b-1),0,old.Z*(b-1))}
 end
 local lowBySlot,highBySlot,padBySlot={},{},{}
 for index in slots do
  lowBySlot[index]={};highBySlot[index]={}
  local side=index<=6 and -1 or 1
  local referenceIndex=side<0 and 1 or 7
  local displacement=poses[index].old.Position-poses[referenceIndex].old.Position+poses[index].delta
  local widest={x=currentPadSizes[index].X,z=currentPadSizes[index].Z}
  for _,species in measured do
   local data=species.bySide[tostring(side)]
   local bounds=API.TranslateBounds(data.baseBounds,displacement)
   if lowBySlot[index].value==nil or bounds.min[3]<lowBySlot[index].value then lowBySlot[index]={value=bounds.min[3],id=species.id,bounds=bounds}end
   if highBySlot[index].value==nil or bounds.max[3]>highBySlot[index].value then highBySlot[index]={value=bounds.max[3],id=species.id,bounds=bounds}end
   local needed=API.SupportPad(data.platformBounds,currentPadSizes[index],1)
   widest.x=math.max(widest.x,needed.x);widest.z=math.max(widest.z,needed.z)
  end
  padBySlot[index]=padBounds(poses[index].new,root,widest)
 end
 for side=0,1 do for row=1,5 do
  local a,bindex=row+side*6,row+1+side*6
  local visible=lowBySlot[bindex].value-highBySlot[a].value
  local pads=API.SignedGap(padBySlot[a],padBySlot[bindex],3)
  if visible<out.minimumVisibleGap then out.minimumVisibleGap=visible;out.witnesses.visibleGap={leftSlot=a,rightSlot=bindex,leftSpecies=highBySlot[a].id,rightSpecies=lowBySlot[bindex].id,actual=visible,required=2,shortfall=math.max(0,2-visible),leftBounds=highBySlot[a].bounds,rightBounds=lowBySlot[bindex].bounds}end
  if pads<out.minimumPadGap then out.minimumPadGap=pads;out.witnesses.padGap={leftSlot=a,rightSlot=bindex,actual=pads,required=2,shortfall=math.max(0,2-pads),leftBounds=padBySlot[a],rightBounds=padBySlot[bindex]}end
 end end
 for row=1,6 do
  local aisle=API.SignedGap(padBySlot[row],padBySlot[row+6],1)
  if aisle<out.minimumCollectionAisle then out.minimumCollectionAisle=aisle;out.witnesses.collectionAisle={leftSlot=row,rightSlot=row+6,actual=aisle,required=6,shortfall=math.max(0,6-aisle),leftBounds=padBySlot[row],rightBounds=padBySlot[row+6]}end
 end
 -- Native runtime floor is36x32; brief retains its prescribed centre/yaw, then contracts XZ.
 local floorHalfX,floorHalfZ=18*b,16*b
 for index,bounds in padBySlot do
  local overflow=math.max(0,-floorHalfX-bounds.min[1],bounds.max[1]-floorHalfX,-floorHalfZ-bounds.min[3],bounds.max[3]-floorHalfZ)
  if overflow>out.maximumSupportOverflow then out.maximumSupportOverflow=overflow;out.witnesses.runtimeFloorSupport={slot=index,overflow=overflow,padBounds=bounds,floorHalfX=floorHalfX,floorHalfZ=floorHalfZ}end
 end
 out.interiorPassing=out.minimumVisibleGap+EPS>=2 and out.minimumPadGap+EPS>=2 and out.minimumCollectionAisle+EPS>=6 and out.maximumSupportOverflow<=EPS
 out.status=out.interiorPassing and "InteriorNecessaryConditionsPass"or"InteriorFitFail"
 out.fullCandidateAcceptance="NotAssessed: cart,service,route,gate,wall,reservation and exterior checks are separate owners"
 return out
end
function API.Audit(options)
 options=options or {}
 assert(Run:IsStudio()and not Run:IsRunning(),"RuntimeBaseFit requires native Studio Edit")
 assert(game.PlaceId==91958083796436 and game.GameId==10548905405,"Wrong DEV identity")
 local adapter=assert(options.Adapter,"Fresh source adapter required")
 local map=assert(workspace:FindFirstChild("MapBlockout"),"Missing map")
 local assets=assert(game.ReplicatedStorage:FindFirstChild("StudioAssets"),"Missing assets")
 local roots={map,assets};local baseline=assert(options.Baseline,"Missing fresh BeforeManifest")
 local sourceCheck=adapter.CheckSources()
 local baselineChecked=guardBaseline(baseline,roots)
 local originals=snapshot(roots)
 local stage=Instance.new("Folder");stage.Name="CompactMapV1_RuntimeBaseFit_"..Http:GenerateGUID(false)
 stage:SetAttribute("Owner","CompactMap_V1_RuntimeBaseFit");stage.Parent=SS
 local start=os.clock();local report
 local success,failure=xpcall(function()
  local deps=adapter.Create()
  local eligible,excluded={},{}
  for _,definition in deps.Catalog.GetAll()do
   if definition.launchStatus=="Live"and definition.spawnEnabled==true then table.insert(eligible,definition)else table.insert(excluded,{id=definition.id,launchStatus=definition.launchStatus,spawnEnabled=definition.spawnEnabled})end
  end
  table.sort(eligible,function(a,b)return a.id<b.id end)
  assert(#eligible>0,"No current supported species")
  local baseFolder=assert(map:FindFirstChild("PlayerBasePatches"),"Missing bases")
  local bases={}
  for _,base in baseFolder:GetChildren()do if base:IsA("Model")and base.Name:match("^Base_%d%d$")then table.insert(bases,base)end end
  table.sort(bases,function(a,b)return a.Name<b.Name end);assert(#bases==12,"Expected12bases")
  report={schemaVersion=1,migrationId="CompactMap_V1",mode="NativeEditIsolatedClones",status="Measured",capturedAtUTC=os.date("!%Y-%m-%dT%H:%M:%SZ"),placeId=game.PlaceId,universeId=game.GameId,engine=baseline.engine,immutableManagedSHA256=baseline.baselineManagedContentSHA256,sourceBundleSHA256=baseline.sourceBundleSHA256,sourceEvidence=sourceCheck,baselineNodesChecked=baselineChecked,targetHeight=deps.Scale.TARGET_HEIGHT_STUDS,eligibilityRule="Current captured BrainrotCatalog: launchStatus Live and spawnEnabled true; assets must resolve through exact CreateItemVisual",eligibleSpeciesCount=#eligible,excludedSpecies=excluded,bases={},candidateSummary={},sourceWrites=0,originalObjectWrites=0,workspaceWrites=0,temporaryParent="ServerStorage",nativeEnvelope="PartOperation.ExtentsCFrame/ExtentsSize; other visible BasePart.CFrame/Size; exact current IsVisualPart",heightScaleBasis="Unchanged current CFrame/Size BrainrotVisualScale; native extents used only for support/gap measurements",padRetentionPolicy="Retain each current Edit pad's larger horizontal size (10x10), enlarge for native full support+1 on each side",currentRuntimeOwnerPadSide=deps.Config.PLATFORM_SIDE_STUDS,fullAcceptance=false,unassessed={"cart loaded footprint/approach","services","roads","region walls/gates","all source/cache migration","ordinaryPlay/rejoin/multiplayer/performance"}}
  local visualFolder=Instance.new("Folder");visualFolder.Name="NativeFactoryClones";visualFolder.Parent=stage
  local visuals={}
  for _,definition in eligible do
   local template=assert(assets.Brainrots:FindFirstChild(definition.modelRef),"Eligible template missing "..definition.id)
   local sourceHeight=assert(deps.Scale.GetVisualHeight(template))
   local visual=assert(deps.Factory:CreateItemVisual(definition.id),"Exact factory failed "..definition.id)
   visual.Parent=visualFolder
   for _,part in visual:GetDescendants()do if part:IsA("BasePart")then part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false end end
   table.insert(visuals,{id=definition.id,definition=definition,visual=visual,sourceHeight=sourceHeight,sourceScale=template:GetScale(),canonicalScale=visual:GetScale()})
   task.wait()
  end
  for _,originalBase in bases do
   local clone=assert(originalBase:Clone());clone.Parent=stage;stripCloneTags(clone)
   local slots=slotsFor(clone);local currentPads={}
   for index,slot in slots do currentPads[index]=slot.Platform.Size end
   local root,placements,floorY=deps.Layout.Apply(clone,slots)
   local measured={};local nativeCalls=0
   for _,item in visuals do
    local species={id=item.id,displayName=item.definition.displayName,sourceHeight=item.sourceHeight,sourceScale=item.sourceScale,canonicalScale=item.canonicalScale,bySide={}}
    for _,index in {1,7}do
     local slot=slots[index];deps.Place(item.visual,slot);nativeCalls+=1
     local markerFrame=slot.Marker:IsA("Attachment")and slot.Marker.WorldCFrame or slot.Marker.CFrame
     local bounds,count,native=nativeEnvelope(item.visual,root,deps.Scale)
     local localBounds=nativeEnvelope(item.visual,slot.Platform.CFrame,deps.Scale)
     species.bySide[tostring(index==1 and -1 or 1)]={baseBounds=bounds,platformBounds=localBounds,visibleParts=count,nativePartOperations=native,markerWorldCFrame={markerFrame:GetComponents()},displayPivot={item.visual:GetPivot():GetComponents()}}
    end
    table.insert(measured,species)
    task.wait()
   end
   -- Every row uses the same native heading/height; projections are rigid translations only.
   for index,slot in slots do
    local ref=slots[index<=6 and 1 or 7];local a=root:ToObjectSpace(slot.Platform.CFrame);local bcf=root:ToObjectSpace(ref.Platform.CFrame)
    assert(near(encoded(a.Rotation),encoded(bcf.Rotation))and math.abs(a.Y-bcf.Y)<EPS,"Rows are not rigid-translation equivalent")
    assert(near(encoded(slot.Marker.CFrame),encoded(ref.Marker.CFrame)),"Marker offsets differ across rows")
   end
   local baseReport={id=originalBase.Name,originalPivot={originalBase:GetPivot():GetComponents()},runtimeRoot={root:GetComponents()},runtimeFloorY=floorY,runtimePlacements=placements,nativePlacementCalls=nativeCalls,logicalSlots=12,originalEditPadSize={currentPads[1].X,currentPads[1].Y,currentPads[1].Z},runtimePadSize={slots[1].Platform.Size.X,slots[1].Platform.Size.Y,slots[1].Platform.Size.Z},measuredSpecies=measured,candidates={}}
   for _,factor in FACTORS do table.insert(baseReport.candidates,measureCandidate(originalBase.Name,root,slots,measured,factor,currentPads))end
   table.insert(report.bases,baseReport)
   clone:Destroy()
   if options.InjectFailureAfterBase==#report.bases then error("Injected cleanup regression")end
   task.wait()
  end
  for index,factor in FACTORS do
   local row={b=factor,passingBases=0,failingBases=0,minimumVisibleGap=math.huge,minimumPadGap=math.huge,minimumCollectionAisle=math.huge,maximumRuntimeFloorOverflow=0}
   for _,base in report.bases do local c=base.candidates[index];if c.interiorPassing then row.passingBases+=1 else row.failingBases+=1 end;row.minimumVisibleGap=math.min(row.minimumVisibleGap,c.minimumVisibleGap);row.minimumPadGap=math.min(row.minimumPadGap,c.minimumPadGap);row.minimumCollectionAisle=math.min(row.minimumCollectionAisle,c.minimumCollectionAisle);row.maximumRuntimeFloorOverflow=math.max(row.maximumRuntimeFloorOverflow,c.maximumSupportOverflow)end
   row.interiorPassing=row.passingBases==12;table.insert(report.candidateSummary,row)
  end
  report.outerFallbackPermitted=false
  report.outerFallbackReason="Interior-Camp necessary conditions govern this audit; outside-Camp fallback cannot repair failed slot spacing"
 end,debug.traceback)
 stage:Destroy()
 local preserved,guardResult=pcall(function()local count=assertPreserved(originals,roots);adapter.CheckSources();return count end)
 assert(preserved,"Fit cleanup/original preservation failed: "..tostring(guardResult))
 if not success then error("RuntimeBaseFit failed; all owned clones removed and "..guardResult.." originals preserved: "..tostring(failure))end
 report.cleanup={stageRemoved=stage.Parent==nil,originalInstancesUnchanged=guardResult,originalSourcesUnchanged=true}
 report.elapsedSeconds=os.clock()-start
 report.nativeExecutionPassed=true
 return report
end
return API
