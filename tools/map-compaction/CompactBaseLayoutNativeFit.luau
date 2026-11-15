--!nocheck
-- Controlled isolated native fit. All mutation is owned ServerStorage clones; no gameplay startups.
local Fit={}
local function bounds(model,reference,scale)
 local low,high=Vector3.one*math.huge,Vector3.one*-math.huge;local count=0
 for _,part in model:GetDescendants()do
  if part:IsA('BasePart')and scale.IsVisualPart(part,model)then
   local cf,size=part.CFrame,part.Size;if part:IsA('PartOperation')then cf,size=part.ExtentsCFrame,part.ExtentsSize end
   local frame=reference:ToObjectSpace(cf);local half=size/2
   for _,x in {-1,1}do for _,y in {-1,1}do for _,z in {-1,1}do local p=frame*(half*Vector3.new(x,y,z));low=low:Min(p);high=high:Max(p)end end end
   count+=1
  end
 end
 assert(count>0,'Native visible geometry required')
 return{min={low.X,low.Y,low.Z},max={high.X,high.Y,high.Z},parts=count}
end
local function strip(clone)
 local cs=game:GetService('CollectionService');local nodes=clone:GetDescendants();table.insert(nodes,clone)
 for _,node in nodes do for _,tag in cs:GetTags(node)do cs:RemoveTag(node,tag)end;if node:IsA('LuaSourceContainer')then node:Destroy()end end
end
local function nearcf(a,b)for i,v in {a:GetComponents()}do assert(math.abs(v-({b:GetComponents()})[i])<.0001,'Native canonical CF differs')end end
local function point(row)return Vector3.new(row[1],row[2],row[3])end
function Fit.Audit(stage,deps,options)
 local canonical=options.Candidate;local raw=options.RuntimeGeometry;local locals=options.PartLocals
 assert(raw.runtimeValidated==false,'Production source must remain unvalidated')
 -- Private completed owner is solely a controlled fixture for the proposal parser; it cannot reach Workspace.
 local fixtureRaw=table.clone(raw);fixtureRaw.runtimeValidated=true
 local privateMap=Instance.new('Folder');privateMap.Name='MapBlockout';privateMap:SetAttribute('Owner','CompactMap_V1_BaseFixture');privateMap:SetAttribute('CompactMapMigrationId','CompactMap_V1');privateMap:SetAttribute('CompactMapStatus','Completed');privateMap:SetAttribute('CompactMapDesiredHash',raw.planHash);privateMap.Parent=stage
 local value=Instance.new('StringValue');value.Name='CompactMapRuntimeGeometry';value.Value=game:GetService('HttpService'):JSONEncode(fixtureRaw);value.Parent=privateMap
 local report={schemaVersion=1,migrationId='CompactMap_V1',b=canonical.b,status='NativeFixtureMeasured',placeId=game.PlaceId,universeId=game.GameId,nativeProposalFitPassed=false,fullAcceptancePassed=false,productionRuntimeValidated=false,privateOwnerFixtureOnly=true,sourceWrites=0,originalObjectWrites=0,workspaceWrites=0,nativeFactoryCalls=0,nativeDisplayPlacementCalls=0,logicalSpeciesSlotCases=0,releasedSpeciesCount=0,minimumVisibleGap=math.huge,minimumPadGap=math.huge,minimumFullSupportMargin=math.huge,minimumClaimFaceAisle=math.huge,bases={},proposalEvidence=options.ProposalEvidence,shellGeometryStatus='Source fitted components only; native imported corner verification pending',cartDrivingTurningPassed=false,unassessed={'fitted shell imported IDs/corners/native materials','ordinary loaded driving/turning','coplanar HouseRamp presentation','full routes/services/region walls/site collision','profile/multiplayer/gameplay'}}
 local definitions=deps.Catalog.GetAll();table.sort(definitions,function(a,b)return a.id<b.id end);local visuals={}
 for _,d in definitions do if d.launchStatus=='Live'and d.spawnEnabled==true then local model=assert(deps.Factory:CreateItemVisual(d.id));model.Parent=stage;strip(model);for _,p in model:GetDescendants()do if p:IsA('BasePart')then p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false end end;table.insert(visuals,{id=d.id,model=model,scale=model:GetScale()});report.nativeFactoryCalls+=1;task.wait()end end
 report.releasedSpeciesCount=#visuals;assert(#visuals==32,'Current release eligibility drifted')
 local originals=workspace.MapBlockout.PlayerBasePatches
 for _,localRow in locals.bases do
  local original=assert(originals:FindFirstChild(localRow.id));local base=original:Clone();base.Parent=privateMap;strip(base)
  local originalFoundation=original.Foundation;local foundationStyle={}
  for _,name in {'Color','Anchored','CanCollide','CanTouch','CanQuery','CollisionGroup','Transparency','CastShadow','TopSurface','BottomSurface','LeftSurface','RightSurface','FrontSurface','BackSurface','CustomPhysicalProperties','CurrentPhysicalProperties'}do foundationStyle[name]=originalFoundation[name]end
  local root=original:GetPivot();base:SetAttribute('Phase5DLayoutPivot',root)
  local slots={};local markerOffsets={}
  for _,row in localRow.parts do
   local part=assert(base:FindFirstChild(row.name));assert(part.ClassName==row.class,'Copied canonical part class changed')
   part.Size=point(row.size);part.CFrame=root*CFrame.new(table.unpack(row.localCFrame));deps.Material.Apply(part,Enum.Material.Glacier)
   if row.stableSlotIndex then local marker=assert(part:FindFirstChild('BrainrotPlacement'));nearcf(marker.CFrame,CFrame.new(table.unpack(row.BrainrotPlacementLocalCFrame)));slots[row.stableSlotIndex]={Index=row.stableSlotIndex,Platform=part,Marker=marker};markerOffsets[row.stableSlotIndex]=marker.CFrame end
  end
  local geometry=assert(options.Proposed.Config.GetGeometry(base),'Private canonical geometry did not resolve')
  local appliedRoot,placements,floor=options.Proposed.Layout.Apply(base,slots)
  nearcf(appliedRoot,root);assert(not base.Phase5DInterior:FindFirstChild('BaseFloor'),'Unexpected duplicate floor')
  local nativeFloor=base.Foundation;nearcf(nativeFloor.CFrame,root*CFrame.new(geometry.support.centreX,.5,geometry.support.centreZ));assert(math.abs(nativeFloor.Size.X-geometry.support.width)<.0001 and math.abs(nativeFloor.Size.Z-geometry.support.depth)<.0001,'Foundation support size drift')
  for name,expectedStyle in foundationStyle do
   local actualStyle=nativeFloor[name]
   if typeof(expectedStyle)=='PhysicalProperties'then for _,component in {'Density','Friction','Elasticity','FrictionWeight','ElasticityWeight'}do assert(actualStyle and math.abs(actualStyle[component]-expectedStyle[component])<=1e-6,'Reused Foundation physics changed: '..component)end
   else assert(actualStyle==expectedStyle,'Reused original Foundation style/flags changed: '..name)end
  end
  local b={foundationOriginalColourFlagsEffectivePhysicsPreserved=true,id=localRow.id,nativeDisplayPlacementCalls=0,logicalSpeciesSlotCases=0,foundationSourceReused=true,noRuntimeFloorOverlay=true,slotIdentityAndMarkersPassed=true,minimumFullSupportMargin=math.huge,minimumVisibleGap=math.huge,minimumPadGap=math.huge,minimumClaimFaceAisle=math.huge,nativeSpecies={},nativePadCFrames={},nativePlaqueCFrames={}}
  local first={}
  for i,slot in slots do
   local expected=localRow.parts[i] -- Direct name lookup below handles source child order.
   for _,r in localRow.parts do if r.name==slot.Platform.Name then expected=r;break end end
   nearcf(root:ToObjectSpace(slot.Platform.CFrame),CFrame.new(table.unpack(expected.localCFrame)));nearcf(slot.Marker.CFrame,markerOffsets[i]);local resolvedId=slot.Platform:GetAttribute('SlotIndex')or tonumber(slot.Platform.Name:match('^Slot_(%d+)$'));assert(resolvedId==i and slot.Platform:GetAttribute('SlotId')==string.format('Slot_%02d',i),'Stable slot identity drift')
   local ref=slots[i<=6 and 1 or 7];local localCf=root:ToObjectSpace(slot.Platform.CFrame);local refCf=root:ToObjectSpace(ref.Platform.CFrame);nearcf(localCf.Rotation,refCf.Rotation);assert(math.abs(localCf.Y-refCf.Y)<.0001,'Rows not rigid translation equivalent');nearcf(slot.Marker.CFrame,ref.Marker.CFrame)
   b.nativePadCFrames[i]={localCf:GetComponents()}
   -- Source-exact configurePlaque geometry prefix; excludes bindings and income/profile operations.
   local plaque=Instance.new('Part');plaque.Parent=base;local sensorCf=options.Proposed.Layout.ConfigurePlaqueGeometry({Root=root},plaque,i,placements[i],floor)
   local sensor=Instance.new('Part');sensor.Name='PrivateClaimSensor';sensor.Size=Vector3.new(plaque.Size.X,deps.Config.PLAQUE_TOUCH_HEIGHT_STUDS,plaque.Size.Z);sensor.CFrame=sensorCf;sensor.Transparency=1;sensor.Anchored=true;sensor.CanCollide=false;sensor.CanTouch=false;sensor.CanQuery=false;sensor.Parent=plaque
   b.nativePlaqueCFrames[i]={root:ToObjectSpace(plaque.CFrame):GetComponents()}
   first[i]={min=math.huge,max=-math.huge,padMin=geometry.slots[i].Z-geometry.padTangentialStuds/2,padMax=geometry.slots[i].Z+geometry.padTangentialStuds/2}
  end
  for _,v in visuals do
   assert(v.model:GetScale()==v.scale,'Fixture changed canonical scale')
   local species={id=v.id,canonicalScale=v.scale,bySide={}}
   for _,i in {1,7}do
    deps.Place(v.model,slots[i]);local inPad=bounds(v.model,slots[i].Platform.CFrame,deps.Scale);local inBase=bounds(v.model,root,deps.Scale);b.nativeDisplayPlacementCalls+=1;report.nativeDisplayPlacementCalls+=1
    local margin=math.min(geometry.padTangentialStuds/2-math.max(math.abs(inPad.min[1]),math.abs(inPad.max[1])),geometry.padNormalStuds/2-math.max(math.abs(inPad.min[3]),math.abs(inPad.max[3])))
    assert(margin>=1-.0001,'Released visual is not fully supported with one-stud margin: '..v.id)
    b.minimumFullSupportMargin=math.min(b.minimumFullSupportMargin,margin)
    species.bySide[tostring(i==1 and -1 or 1)]={nativePadBounds=inPad,nativeBaseBounds=inBase,fullSupportMargin=margin}
    for j=i,i+5 do
     local delta=geometry.slots[j].Z-geometry.slots[i].Z
     first[j].min=math.min(first[j].min,inBase.min[3]+delta);first[j].max=math.max(first[j].max,inBase.max[3]+delta)
     b.logicalSpeciesSlotCases+=1;report.logicalSpeciesSlotCases+=1
    end
   end
   table.insert(b.nativeSpecies,species);task.wait()
  end
  for side=0,1 do for station=1,5 do local a=first[side*6+station];local c=first[side*6+station+1];b.minimumVisibleGap=math.min(b.minimumVisibleGap,c.min-a.max);b.minimumPadGap=math.min(b.minimumPadGap,c.padMin-a.padMax)end end
  for i=1,6 do
   local left=CFrame.new(table.unpack(b.nativePlaqueCFrames[i]));local right=CFrame.new(table.unpack(b.nativePlaqueCFrames[i+6]));local clear=right.X-left.X-options.Proposed.PlaqueDepth
   b.minimumClaimFaceAisle=math.min(b.minimumClaimFaceAisle,clear)
  end
  assert(b.minimumVisibleGap>=2-.0001 and b.minimumPadGap>=2-.0001 and b.minimumClaimFaceAisle>=6-.0001,'Compact native gaps or claim face aisle fail')
  local cartCf=root:ToObjectSpace(base.CartSpawn.CFrame);local cargo=options.Cargo.maximumLoadedEnvelope;local halfPad=base.CartDisplay.Size/2;local cartPad=root:ToObjectSpace(base.CartDisplay.CFrame)
  local minMargin=math.huge
  for _,x in {cargo.min[1],cargo.max[1]}do for _,z in {cargo.min[3],cargo.max[3]}do
   local world=(base.CartSpawn.CFrame*CFrame.new(0,4,0))*Vector3.new(x,0,z);local inCartPad=base.CartDisplay.CFrame:PointToObjectSpace(world)
   minMargin=math.min(minMargin,halfPad.X-math.abs(inCartPad.X),halfPad.Z-math.abs(inCartPad.Z))
  end end
  assert(minMargin>=2-.0001,'Native maximum loaded cart unsupported')
  local supportRight=geometry.support.centreX+geometry.support.width/2
  b.loadedCartSupport={nativeProjectionEvidence=options.CargoEvidence,minimumCentredMargin=minMargin,marginRequired=2,sourceActualFactoryCalls=options.Cargo.nativeFactoryCalls,sourceActualMountPoseCalls=options.Cargo.nativeMountPoseCalls,cartSpawnLocal={cartCf:GetComponents()},cartDisplayLocal={cartPad:GetComponents()},cartDisplaySize={base.CartDisplay.Size.X,base.CartDisplay.Size.Y,base.CartDisplay.Size.Z},cartApproachWidth=base.CartRamp.Size.X,approachVsSupportGap=cartCf.X-12-supportRight}
  assert(base.CartRamp.Size.X>=24-.0001 and b.loadedCartSupport.approachVsSupportGap>=.2-.0001,'Cart twenty-four approach intersects support')
  local approach=canonical.functionalApproachCorrection
  local localHouse=root:ToObjectSpace(base.HouseRamp.CFrame);local localCartRamp=root:ToObjectSpace(base.CartRamp.CFrame)
  assert(math.abs(localHouse.X-geometry.formationCenterX)<.0001 and math.abs(localHouse.Z-approach.houseRamp.centreZ)<.0001,'House ramp does not align common door')
  assert(base.HouseRamp.Size.X==20 and base.HouseRamp.Size.Z==12 and base.CartRamp.Size.X==24 and base.CartRamp.Size.Z==12,'Functional ramp dimensions changed')
  local floorFront=geometry.support.centreZ-geometry.support.depth/2
  local houseJoin=localHouse.Z+base.HouseRamp.Size.Z/2-floorFront;local cartFront=root:ToObjectSpace(base.CartDisplay.CFrame).Z-base.CartDisplay.Size.Z/2;local cartJoin=localCartRamp.Z+base.CartRamp.Size.Z/2-cartFront
  assert(math.abs(houseJoin-.2)<.0001 and math.abs(cartJoin-.2)<.0001,'Ramp high edge does not meet its support')
  assert(floorFront-approach.loopNearEdgeZ>=2-.0001 and cartFront-approach.loopNearEdgeZ>=2-.0001,'Support intrudes frozen Camp loop')
  b.functionalApproachGeometry={houseRampLocal={localHouse:GetComponents()},cartRampLocal={localCartRamp:GetComponents()},houseRampOriginalSizePreserved=true,cartRampOriginalSizePreserved=true,houseSupportJoinOverlap=houseJoin,cartSupportJoinOverlap=cartJoin,numericalFrozenLoopCentreZ=approach.loopCentreZ,supportRoadClearance=floorFront-approach.loopNearEdgeZ,cartRoadClearance=cartFront-approach.loopNearEdgeZ,loadedLateralTurningAcceptance=false}
  b.nativeProposalInteriorPassed=true
  report.minimumVisibleGap=math.min(report.minimumVisibleGap,b.minimumVisibleGap);report.minimumPadGap=math.min(report.minimumPadGap,b.minimumPadGap);report.minimumFullSupportMargin=math.min(report.minimumFullSupportMargin,b.minimumFullSupportMargin);report.minimumClaimFaceAisle=math.min(report.minimumClaimFaceAisle,b.minimumClaimFaceAisle)
  table.insert(report.bases,b);base:Destroy();task.wait()
 end
 assert(#report.bases==12 and report.nativeDisplayPlacementCalls==768 and report.logicalSpeciesSlotCases==4608,'Native case coverage incomplete')
 report.nativeProposalFitPassed=true
 return report
end
return Fit
