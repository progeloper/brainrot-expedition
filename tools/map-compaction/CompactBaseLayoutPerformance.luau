--!nocheck
-- Authorized controlled Edit render fixture. Root alone executes. No original/source/gameplay writes.
local P={};local Run=game:GetService('RunService');local Stats=game:GetService('Stats');local CS=game:GetService('CollectionService');local Http=game:GetService('HttpService')
local IDS={'BRT_002','BRT_028','BRT_006','BRT_001','BRT_010','BRT_012','BRT_016','BRT_019','BRT_027','BRT_031','BRT_032','BRT_030'}
local REQUIRED={'FrameTime','RenderCPUFrameTime','RenderGPUFrameTime','PhysicsStepTime','TotalMemoryMb'}
local EXTRA={'SceneDrawcallCount','SceneTriangleCount','InstanceCount','PrimitivesCount'}
local function metric(name)
 local ok,value=pcall(function()if name=='TotalMemoryMb'then return Stats:GetTotalMemoryUsageMb()end;return Stats[name]end)
 if ok and type(value)=='number'and value==value and math.abs(value)<math.huge then return value end
 return nil
end
local function properties(object,names)
 local out={};for _,name in names do local ok,value=pcall(function()return object[name]end);out[name]=if ok then tostring(value)else'Unsupported'end;return out
end
local function strip(clone)
 local nodes=clone:GetDescendants();table.insert(nodes,clone)
 for _,n in nodes do for _,tag in CS:GetTags(n)do CS:RemoveTag(n,tag)end;if n:IsA('LuaSourceContainer')then n:Destroy()end end
end
local function slots(base)
 local out={};for _,p in base:GetChildren()do if p:IsA('BasePart')then local i=p:GetAttribute('SlotIndex')or tonumber(p.Name:match('^Slot_(%d+)$'));if i then assert(i>=1 and i<=12 and not out[i],'Invalid fixture stable slot');out[i]={Index=i,Platform=p,Marker=assert(p:FindFirstChild('BrainrotPlacement'))}end end end
 for i=1,12 do assert(out[i],'Missing fixture slot')end;return out
end
local function baseFrame(base)
 local frame=base:GetAttribute('BaseOrigin');if typeof(frame)=='CFrame'then return frame end;return base:GetPivot()
end
local function schedule(map)
 local camp=CFrame.new(-19,.04999995231628418,-46)
 local b1=baseFrame(assert(map.PlayerBasePatches:FindFirstChild('Base_01')));local b8=baseFrame(assert(map.PlayerBasePatches:FindFirstChild('Base_08')))
 local beach=assert(map.ProgressionGates:FindFirstChild('Beach')):GetPivot();local volcano=assert(map.ProgressionGates:FindFirstChild('Volcano')):GetPivot()
 local out={}
 for _,v in {{'CampOverview',camp,Vector3.new(0,250,90),Vector3.new(0,0,0)},{'Base01',b1,Vector3.new(0,48,-76),Vector3.new(0,3,-23)},{'Base08',b8,Vector3.new(0,48,-76),Vector3.new(0,3,-23)},{'BeachGate',beach,Vector3.new(65,40,45),Vector3.new(0,0,0)},{'VolcanoGate',volcano,Vector3.new(-65,40,45),Vector3.new(0,0,0)}}do
  local eye,look=v[2]*v[3],v[2]*v[4];table.insert(out,{id=v[1],ownerFrame={v[2]:GetComponents()},cameraOffset={v[3].X,v[3].Y,v[3].Z},focusOffset={v[4].X,v[4].Y,v[4].Z},camera=CFrame.lookAt(eye,look),focus=CFrame.new(look),fov=70})
 end
 return out
end
local function summary(values)
 if #values==0 then return{status='Unsupported',count=0}end
 table.sort(values);local total=0;for _,v in values do total+=v end
 return{count=#values,min=values[1],max=values[#values],mean=total/#values,p50=values[math.ceil(#values*.5)],p95=values[math.ceil(#values*.95)]}
end
local function collectView(camera,view,options)
 local frameError=0;local focusError=0;local rows={};local viewportStart={camera.ViewportSize.X,camera.ViewportSize.Y};local getters={};for _,n in REQUIRED do getters[n]={}end;for _,n in EXTRA do getters[n]={}end
 local function ownCamera()
  camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=view.camera;camera.Focus=view.focus;camera.FieldOfView=view.fov
 end
 ownCamera();task.wait(options.WarmSeconds or 2)
 local start=os.clock();local last=start
 for index=1,120 do
  ownCamera();task.wait(options.SampleIntervalSeconds or 1/60)
  local now=os.clock();local row={index=index,wallElapsed=now-start,sampleInterval=now-last,metrics={}};last=now
  frameError=math.max(frameError,(camera.CFrame.Position-view.camera.Position).Magnitude,(camera.CFrame.LookVector-view.camera.LookVector).Magnitude);focusError=math.max(focusError,(camera.Focus.Position-view.focus.Position).Magnitude)
  for name,values in getters do local value=metric(name);if value~=nil then row.metrics[name]=value;table.insert(values,value)end end
  table.insert(rows,row)
 end
 local out={id=view.id,ownerFrame=view.ownerFrame,cameraOffset=view.cameraOffset,focusOffset=view.focusOffset,cameraCFrame={view.camera:GetComponents()},focus={view.focus:GetComponents()},fieldOfView=view.fov,viewportStart=viewportStart,viewportEnd={camera.ViewportSize.X,camera.ViewportSize.Y},maximumCameraError=frameError,maximumFocusError=focusError,elapsedSeconds=os.clock()-start,actualSamples=#rows,requiredSamples=120,samples=rows,metrics={},accepted=false,sampling='120 native Stats property readbacks at yielded wall-clock samples; not 120 unique GPU/CPU scope frames'}
 local allPositive=true
 for name,values in getters do
  local s=summary(values);local positives=0;for _,v in values do if v>0 then positives+=1 end end;s.positiveCount=positives
  s.status=if #values==120 and positives==120 then'All120PositiveNativeReadbacks'elseif #values==0 then'Unsupported'else'AvailableButPartialOrZero'
  s.rawUnit=if name=='FrameTime'then'seconds (official Stats docs)'elseif name=='TotalMemoryMb'then'MB (official Stats docs)'elseif table.find(EXTRA,name)then'count'else'native Stats property value; ratio comparison only'
  if table.find(REQUIRED,name)and s.status~='All120PositiveNativeReadbacks'then allPositive=false end;out.metrics[name]=s
 end
 out.cameraStable=frameError<=.001 and focusError<=.001 and out.viewportStart[1]==out.viewportEnd[1]and out.viewportStart[2]==out.viewportEnd[2]
 out.accepted=out.cameraStable and allPositive;out.status=if out.accepted then'ControlledNativeStatsSamplesComplete'else'NotAssessedMissingMetricOrCameraCoverage'
 return out
end
function P.Capture(options)
 assert(Run:IsStudio()and not Run:IsRunning(),'Performance fixture is native Studio Edit only')
 assert(game.PlaceId==91958083796436 and game.GameId==10548905405,'Wrong DEV')
 assert(options.Mode=='Before'or options.Mode=='After','Exact fixture mode required')
 local adapter=options.Adapter;adapter.CheckSources();local deps=adapter.Create();local map=assert(workspace:FindFirstChild('MapBlockout'));local assets=assert(game.ReplicatedStorage:FindFirstChild('StudioAssets'))
 local roots={map,assets};local before=options.Guard.Snapshot(roots)
 local stage=Instance.new('Folder');stage.Name='CompactMapV1_Performance_'..Http:GenerateGUID(false);stage:SetAttribute('Owner','CompactMap_V1_Performance');stage.Parent=workspace
 local camera=assert(workspace.CurrentCamera,"Current native camera required");local saved={Type=camera.CameraType,CFrame=camera.CFrame,Focus=camera.Focus,FieldOfView=camera.FieldOfView};local report
 local ok,reason=xpcall(function()
  local privateMap=Instance.new('Folder');privateMap.Name='MapBlockout';privateMap.Parent=stage
  local proposal=options.Proposed and options.Proposed.Create(deps)
  if options.Mode=='After'then
   local liveValue=assert(map:FindFirstChild('CompactMapRuntimeGeometry'),'Installed runtime geometry missing')
   assert(liveValue:IsA('StringValue')and map:GetAttribute('CompactMapMigrationId')=='CompactMap_V1'and map:GetAttribute('CompactMapStatus')=='Completed','Installed compact map is incomplete')
   local text=liveValue.Value
   local raw=Http:JSONDecode(text);assert(raw.runtimeValidated and raw.migrationId=='CompactMap_V1'and raw.planHash==map:GetAttribute('CompactMapDesiredHash'),'Actual installed validated after geometry/hash required')
   privateMap:SetAttribute('CompactMapMigrationId','CompactMap_V1');privateMap:SetAttribute('CompactMapStatus','Completed');privateMap:SetAttribute('CompactMapDesiredHash',raw.planHash)
   local value=Instance.new('StringValue');value.Name='CompactMapRuntimeGeometry';value.Value=text;value.Parent=privateMap
  end
  local calls,parts,bases=0,0,0
  for i=1,12 do
   local original=assert(map.PlayerBasePatches:FindFirstChild(string.format('Base_%02d',i)));local clone=original:Clone();clone.Parent=privateMap;strip(clone);clone:SetAttribute('Phase5DLayoutPivot',baseFrame(original));local ss=slots(clone)
   if options.Mode=='Before'then deps.Layout.Apply(clone,ss)else proposal.Layout.Apply(clone,ss)end
   for index,id in IDS do
    local def=assert(deps.Catalog.GetById(id));assert(def.launchStatus=='Live'and def.spawnEnabled==true,'Fixture species is not currently eligible')
    local visual=assert(deps.Factory:CreateItemVisual(id));visual.Parent=clone;strip(visual);deps.Place(visual,ss[index]);calls+=1
    for _,p in visual:GetDescendants()do if p:IsA('BasePart')then p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false end end
   end
   for _,p in clone:GetDescendants()do if p:IsA('BasePart')then p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;parts+=1 end end
   bases+=1;task.wait()
  end
  assert(calls==144 and bases==12,'Incomplete controlled display population')
  report={schemaVersion=1,migrationId='CompactMap_V1',mode=options.Mode,scope='Controlled Edit render fixture, source-exact owner base presentation with 144 released canonical static display clones',placeId=game.PlaceId,universeId=game.GameId,engine=(function()local f=getfenv(0).version;return if type(f)=="function"then f()else"Unavailable"end)(),sourceEvidence=options.SourceEvidence,fixtureSpeciesByStableSlot=IDS,fixtureBaseCount=bases,fixtureFactoryPlacements=calls,fixtureBaseParts=parts,fixtureStageOwner='CompactMap_V1_Performance',profilesOrEconomyStarted=false,gameplayAcceptance=false,multiplayerAcceptance=false,phoneGpuAcceptance=false,originalSourceWrites=0,originalObjectWrites=0,controlledCameraOnly=true,lighting={clockTime=game.Lighting.ClockTime,brightness=game.Lighting.Brightness,exposure=game.Lighting.ExposureCompensation},renderSettings=properties(settings().Rendering,{'QualityLevel','EditQualityLevel'}),viewport={camera.ViewportSize.X,camera.ViewportSize.Y},views={},metricSource='Native Stats properties; official docs https://create.roblox.com/docs/reference/engine/classes/Stats',limitations={'This is controlled Edit rendering with additional duplicate cloned base geometry, not ordinary Play or full twelve-player load.','120 wall-clock yielded samples may observe repeated engine frames; no unique native GPU frame/scope proof is claimed.','Stats.FrameTime is client-only; if unavailable/zero in this privileged Edit VM the view is NotAssessed.','All raw CPU/GPU/Physics values are preserved; no undocumented unit conversion.','Root must compare exact quality, viewport, engine, clock, species/slots, source construction method and metric availability before ratios.'}}
  for _,view in schedule(map)do table.insert(report.views,collectView(camera,view,options));task.wait()end
  report.nativeStatsCoverageComplete=true;for _,view in report.views do if not view.accepted then report.nativeStatsCoverageComplete=false end end
  report.status=if report.nativeStatsCoverageComplete then'ControlledStatsCompleteGameplayUnverified'else'NotAssessedMetricCoveragePartial'
 end,debug.traceback)
 stage:Destroy();camera.CameraType=saved.Type;camera.CFrame=saved.CFrame;camera.Focus=saved.Focus;camera.FieldOfView=saved.FieldOfView
 local unchanged=options.Guard.AssertPreserved(before,roots);adapter.CheckSources()
 assert(ok,'Controlled performance fixture failed; cleanup completed: '..tostring(reason))
 report.cleanup={fixtureRemoved=stage.Parent==nil,originalNodesPreserved=unchanged,originalSourcesPreserved=true,cameraRestored=true};return report
end
return P
