--!strict
-- Actual temporary ServerScript in ordinary DEV Play; never execute_luau's module cache.
-- Reads existing state only. The sole created instance is the owned report StringValue.
local Run = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
assert(Run:IsStudio() and Run:IsServer() and Run:IsRunning(), "Actual Studio server Play required")
assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Existing DEV only")
assert(script:IsA("Script") and script.Parent == SSS, "Use an actual temporary ServerScript")
local label = script:GetAttribute("RunLabel")
local expectedHash = script:GetAttribute("ExpectedPlanHash")
assert(type(label)=="string" and #label<=64 and label:match("^[%w_%-]+$"), "Bounded RunLabel required")
assert(type(expectedHash)=="string" and #expectedHash==64 and expectedHash:match("^[0-9a-f]+$"), "Exact applied plan hash required")
local map = workspace:FindFirstChild("MapBlockout")
assert(map and map:GetAttribute("CompactMapMigrationId")=="CompactMap_V1" and map:GetAttribute("CompactMapStatus")=="Completed", "Completed compact owner required")
assert(map:GetAttribute("CompactMapDesiredHash")==expectedHash, "Applied plan hash differs")
local value = map:FindFirstChild("CompactMapRuntimeGeometry")
assert(value and value:IsA("StringValue") and #value.Value<=200000, "Bounded current runtime manifest required")
local raw = Http:JSONDecode(value.Value)
assert(raw.runtimeValidated==true and raw.planHash==expectedHash, "Runtime manifest not validated/matched")
local server=SSS:FindFirstChild("Server")
assert(server and server:FindFirstChild("Services") and server:FindFirstChild("Systems"), "Existing server owners required")
-- These modules are already loaded by the normal bootstrap. Never call Init/Start/Bind/Sync.
local Profile=require(server.Services.PlayerDataService)
local Base=require(server.Systems.PlayerBaseSystem)
local Cart=require(server.Services.CartService)
local Cargo=require(server.Services.CartCargoService)
local Carry=require(server.Systems.BrainrotInteractionSystem)
local World=require(server.Systems.DevelopmentBrainrotSpawner)
local Geometry=require(RS.Shared.Utility.CompactMapGeometry)
local data=Geometry.Validate(raw) -- pure validation; no replacement/cached session mutation
local copied=0
local function copy(v:any,depth:number?):any
 copied+=1;local n=depth or 0;assert(copied<=100000 and n<=14,"Complete readback bound exceeded")
 local k=typeof(v)
 if k=="number" then assert(v==v and math.abs(v)<math.huge,"Nonfinite state");return v end
 if k=="nil" or k=="boolean" or k=="string" then return v end
 if k=="Vector3" then return {v.X,v.Y,v.Z} end
 if k=="CFrame" then return {v:GetComponents()} end
 if k=="Color3" then return {v.R,v.G,v.B} end
 if k=="Instance" then return v:GetFullName() end
 if k~="table" then return tostring(v) end
 local out={};for key,x in v do assert(type(key)=="string" or type(key)=="number","Unsupported key");out[key]=copy(x,n+1) end
 return out
end
local report:any={schemaVersion=1,status="ActualReadbackAcceptancePartial",migrationId="CompactMap_V1",planHash=expectedHash,
 runLabel=label,timestamp=DateTime.now():ToIsoDate(),serverTime=workspace:GetServerTimeNow(),placeId=game.PlaceId,universeId=game.GameId,
 moduleCache="Actual ordinary ServerScript VM",profileWrites=0,gameplayWrites=0,sourceWrites=0,remoteCalls=0,initializersCalled=0,
 instanceWrites="One owned ServerStorage report only",checks={},bases={},players={},gates={},walls={},services={},
 ordinaryInteractionsExecutedByCollector=false,fullGameplayAcceptancePassed=false,phoneTested=false,multiplayerTested=false,
 performanceTested=false,sourceEqualityProof="Separate native Edit byte guards required; Source is not readable by an ordinary ServerScript",
 unassessed={"normal driving on all twelve approaches including loaded turning","catch/selected-target LOS/reel/deposit/collect/lift/drop/sale loop",
 "six paid gate one-debit purchases and per-client permissions/guest corrections","isolated-profile cross-plot rejoin/empty-slot retained cash",
 "stream-out/rebind/mobile/gamepad/two-client tests","matched full section15 performance and required full private suite"}}
local function check(id:string,ok:boolean,details:any)
 table.insert(report.checks,{id=id,status=if ok then "Passed" else "Failed",details=details})
end
local function near(a:number,b:number):boolean return math.abs(a-b)<=.001 end
local function envelope(model:Model,frame:CFrame,visibleOnly:boolean):any
 local lo,hi=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
 local count=0
 for _,p in model:GetDescendants() do
  if p:IsA("BasePart") and (not visibleOnly or p.Transparency<1) then
   local cf,size=p.CFrame,p.Size
   if p:IsA("PartOperation") then cf,size=p.ExtentsCFrame,p.ExtentsSize end
   for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
    local q=frame:PointToObjectSpace(cf:PointToWorldSpace(size*Vector3.new(x,y,z)*.5))
    lo=Vector3.new(math.min(lo.X,q.X),math.min(lo.Y,q.Y),math.min(lo.Z,q.Z))
    hi=Vector3.new(math.max(hi.X,q.X),math.max(hi.Y,q.Y),math.max(hi.Z,q.Z))
   end end end
   count+=1
  end
 end
 return if count>0 then {min=copy(lo),max=copy(hi),partCount=count,visibleOnly=visibleOnly,basis="PartOperation native Extents; other BasePart CFrame/Size"} else nil
end
local function partRecord(p:BasePart):any
 return {path=p:GetFullName(),size=copy(p.Size),cframe=copy(p.CFrame),colour=copy(p.Color),attributes=copy(p:GetAttributes()),
 anchored=p.Anchored,canCollide=p.CanCollide,canTouch=p.CanTouch,canQuery=p.CanQuery,material=p.Material.Name,variant=p.MaterialVariant}
end
local patches=map:FindFirstChild("PlayerBasePatches")
assert(patches,"Missing existing base folder")
local registered=Base:GetRegisteredBases();local registeredSet={}
for _,b in registered do registeredSet[b]=true end
check("ActualBaseRegistry12",#registered==12,{count=#registered})
for i=1,12 do
 local id=string.format("Base_%02d",i);local b=patches:FindFirstChild(id);local g=data.bases[id]
 check(id..".Exists",b~=nil and b:IsA("Model"),id)
 if not b or not b:IsA("Model") then continue end
 local root=b:GetAttribute("BaseOrigin");assert(typeof(root)=="CFrame","Captured structural BaseOrigin required")
 local row:any={id=id,root=copy(root),registered=registeredSet[b]==true,ownerUserId=b:GetAttribute("OwnerUserId"),pads={},plaques={},displays={}}
 check(id..".Registered",row.registered,id)
 local pads,plaques={},{}
 for _,p in b:GetDescendants() do
  if p:IsA("BasePart") then
   local slot=p.Name:match("^Slot_(%d+)$");local plaque=p.Name:match("^IncomePlaque_(%d+)$")
   if slot then assert(pads[tonumber(slot)]==nil,"Duplicate slot identity");pads[tonumber(slot)]=p end
   if plaque then assert(plaques[tonumber(plaque)]==nil,"Duplicate plaque identity");plaques[tonumber(plaque)]=p end
  end
 end
 local padCount,plaqueCount=0,0
 for _ in pads do padCount+=1 end;for _ in plaques do plaqueCount+=1 end
 check(id..".12Pads",padCount==12,{count=padCount});check(id..".12Plaques",plaqueCount==12,{count=plaqueCount})
 for n=1,12 do
  local p=pads[n];local slot=g.slots[n]
  if p then
   local q=root:ToObjectSpace(p.CFrame);local inward=Vector3.new(-slot.Side,0,0)
   local ok=near(q.X,slot.X) and near(q.Z,slot.Z) and q.LookVector:Dot(inward)>=.999999 and near(p.Size.X,g.padTangentialStuds) and near(p.Size.Z,g.padNormalStuds)
   local stable=p:GetAttribute("SlotIndex") or tonumber(tostring(p:GetAttribute("SlotId")):match("^Slot_(%d+)$")) or n
   check(id..".Pad"..n,ok and stable==n,{localCFrame=copy(q),actualSize=copy(p.Size),canonical=copy(slot),resolvedStableId=stable})
   table.insert(row.pads,partRecord(p))
  end
  local plaque=plaques[n]
  if plaque then
   local q=root:ToObjectSpace(plaque.CFrame);local expectedX=slot.X-slot.Side*(g.padNormalStuds/2+.55+2.25/2)
   local sensor=plaque:FindFirstChild("TouchSensor")
   -- Exact current owner contract; inspect existing sensor only.
   local ok=near(q.X,expectedX) and near(q.Z,slot.Z) and near(plaque.Size.X,3.5) and near(plaque.Size.Y,.18) and near(plaque.Size.Z,2.25)
   check(id..".Plaque"..n,ok,{localCFrame=copy(q),size=copy(plaque.Size),claimSensorFound=sensor~=nil})
   local sensorPassed=sensor~=nil and sensor:IsA("BasePart") and sensor.Anchored and sensor.CanTouch and not sensor.CanCollide and not sensor.CanQuery and near(sensor.Size.X,3.5) and near(sensor.Size.Y,1) and near(sensor.Size.Z,2.25)
   if sensorPassed then
    local offset=plaque.CFrame:ToObjectSpace(sensor.CFrame)
    sensorPassed=near(offset.X,0) and near(offset.Y,.59) and near(offset.Z,0) and offset.RightVector:Dot(Vector3.xAxis)>=.999999 and offset.UpVector:Dot(Vector3.yAxis)>=.999999 and offset.LookVector:Dot(-Vector3.zAxis)>=.999999
   end
   check(id..".ClaimSensor"..n,sensorPassed,{path=sensor and sensor:GetFullName(),collectionTriggeredByCollector=false})
   local pr=partRecord(plaque);pr.children={}
   for _,child in plaque:GetChildren() do
    if child:IsA("BasePart") then table.insert(pr.children,partRecord(child)) end
   end
   table.insert(row.plaques,pr)
  end
 end
 local foundation=b:FindFirstChild("Foundation")
 if foundation and foundation:IsA("BasePart") then
  row.foundation=partRecord(foundation);local q=root:ToObjectSpace(foundation.CFrame)
  check(id..".CanonicalFoundation",near(q.X,g.support.centreX) and near(q.Z,g.support.centreZ) and near(foundation.Size.X,g.support.width) and near(foundation.Size.Z,g.support.depth),row.foundation)
 else check(id..".CanonicalFoundation",false,"Missing original Foundation") end
 local stored=b:FindFirstChild("StoredBrainrots")
 for _,display in if stored then stored:GetChildren() else {} do
  if not display:IsA("Model") then continue end
  local n=display:GetAttribute("SlotIndex");local p=if type(n)=="number" then pads[n] else nil
  local env=envelope(display,root,true)
  local entry:any={path=display:GetFullName(),attributes=copy(display:GetAttributes()),modelScale=display:GetScale(),visibleEnvelope=env}
  if p and env then
   local q=root:ToObjectSpace(p.CFrame);local margin=math.min(env.min[1]-(q.X-g.padNormalStuds/2),(q.X+g.padNormalStuds/2)-env.max[1],env.min[3]-(q.Z-g.padTangentialStuds/2),(q.Z+g.padTangentialStuds/2)-env.max[3])
   entry.minimumSupportMargin=margin
   check(id..".StoredDisplaySupport."..tostring(n),margin>=-.001,entry)
   entry.fullOneStudMarginPassed=margin>=1-.001
   check(id..".StoredDisplayOneStudMargin."..tostring(n),entry.fullOneStudMarginPassed,{minimumSupportMargin=margin,requiredMargin=1})
  else check(id..".StoredDisplaySupport."..display.Name,false,"Missing stable pad/envelope") end
  table.insert(row.displays,entry)
 end
 table.insert(report.bases,row)
end
local stalls=map:FindFirstChild("ServiceStallPatches")
for id,g in data.services do
 local p=stalls and stalls:FindFirstChild(id)
 if p and p:IsA("BasePart") then
  local size=Geometry.ResolveInteractionSize(p)
  check("ServiceLogicalRange."..id,near(size.X,g.logicalInteractionEnvelope[1]) and near(size.Y,g.logicalInteractionEnvelope[2]) and near(size.Z,g.logicalInteractionEnvelope[3]),copy(size))
  table.insert(report.services,partRecord(p))
 else check("ServiceLogicalRange."..id,false,"Missing original stable stall") end
end
for _,player in Players:GetPlayers() do
 local profile,reason=Profile:GetReadableData(player);local diagnostic=Profile:GetDiagnostics(player)
 local base=Base:GetBase(player);local assignment=Base:GetAssignment(player);local record=Cart:GetCartRecord(player);local cart=record and record.Model
 local row:any={name=player.Name,userId=player.UserId,attributes=copy(player:GetAttributes()),status=Profile:GetStatus(player),
 writable=Profile:IsWritable(player),diagnostics=copy(diagnostic),readableReason=reason,base=base and base:GetFullName(),
 assignment=copy(assignment),carry=copy(Carry.GetCarriedState(player)),profile=profile and copy({CurrencyVersion=profile.CurrencyVersion,
 Economy=profile.Economy,Collection=profile.Collection,Base=profile.Base,WorldProgression=profile.WorldProgression,Progression=profile.Progression})}
 check("PlayerReady."..player.UserId,row.status=="Ready" and row.writable==true and profile~=nil,{status=row.status,writable=row.writable,reason=reason})
 check("OrdinaryProfile."..player.UserId,diagnostic~=nil and diagnostic.isolatedTestProfile==false,{diagnostics=copy(diagnostic)})
 check("CurrentBaseAssignment."..player.UserId,assignment~=nil and Base:IsCurrentAssignment(assignment) and base~=nil,copy(assignment))
 if cart and cart.Parent then
  row.cart={path=cart:GetFullName(),attributes=copy(cart:GetAttributes()),pivot=copy(cart:GetPivot()),cargo=copy(Cargo:GetCargoSnapshot(cart)),
   cargoCount=Cargo:GetCargoCount(cart),cargoRevision=Cargo:GetCargoRevision(cart),allPhysicalEnvelope=envelope(cart,cart:GetPivot(),false),seats={}}
  for _,p in cart:GetDescendants() do
   if p:IsA("Seat") or p:IsA("VehicleSeat") then table.insert(row.cart.seats,{path=p:GetFullName(),disabled=p.Disabled,occupant=p.Occupant and p.Occupant.Parent:GetFullName(),cframe=copy(p.CFrame)}) end
  end
  if base then row.cart.currentEnvelopeInAssignedBase=envelope(cart,base:GetAttribute("BaseOrigin"),false) end
 end
 table.insert(report.players,row)
end
local gates=map:FindFirstChild("ProgressionGates")
for _,m in if gates then gates:GetChildren() else {} do
 local row:any={path=m:GetFullName(),attributes=copy(m:GetAttributes()),parts={},prompts={},effectiveAccess="NotAssessed; no safe exported runtime access instance"}
 for _,p in m:GetDescendants() do
  if p:IsA("BasePart") then table.insert(row.parts,partRecord(p))
  elseif p:IsA("ProximityPrompt") then table.insert(row.prompts,{path=p:GetFullName(),enabled=p.Enabled,maxActivationDistance=p.MaxActivationDistance,holdDuration=p.HoldDuration,key=p.KeyboardKeyCode.Name}) end
 end
 table.insert(report.gates,row)
end
local walls=map:FindFirstChild("RegionWalls")
local wallParts,collidable,queryable=0,0,0
for _,p in if walls then walls:GetDescendants() else {} do
 if p:IsA("BasePart") then
  wallParts+=1;if p.CanCollide then collidable+=1 end;if p.CanQuery then queryable+=1 end
  table.insert(report.walls,partRecord(p))
 end
end
report.wallSummary={parts=wallParts,collidableParts=collidable,queryableParts=queryable,manifestObstacles=#data.staticWallObstacles,geometryRayApertureAcceptance="NotAssessed by snapshot"}
report.population=copy(World.GetPopulationSnapshot())
report.actualPlayerCount=#report.players
check("ActualOrdinaryPlayerPresent",report.actualPlayerCount>0,{count=report.actualPlayerCount})
report.checkSummary={passed=0,failed=0}
for _,c in report.checks do report.checkSummary[if c.status=="Passed" then "passed" else "failed"]+=1 end
report.copiedNodes=copied
-- Native StringValue.Value has a 200,000-byte limit. Keep complete JSON in UTF-8-safe 60k chunks.
local name="CompactMapV1_PlayReadOnly_"..label
local existing=SS:FindFirstChild(name)
assert(existing==nil or ((existing:IsA("Folder") or existing:IsA("StringValue")) and existing:GetAttribute("Owner")=="CompactMap_V1"),"Report name occupied")
local encoded=Http:JSONEncode(report)
assert(#encoded<=4000000,"Complete report exceeds explicit 4MB budget; no truncated report accepted")
local output=Instance.new("Folder")
output.Name=name;output:SetAttribute("Owner","CompactMap_V1");output:SetAttribute("ReadbackOnly",true)
local wrote,writeError=xpcall(function()
 local cursor,count=1,0
 while cursor<=#encoded do
  local last=math.min(#encoded,cursor+60000-1)
  -- Avoid splitting before any UTF-8 continuation byte in the next chunk.
  while last<#encoded do
   local nextByte=string.byte(encoded,last+1)
   if nextByte and nextByte>=128 and nextByte<=191 then last-=1 else break end
  end
  assert(last>=cursor,"Invalid UTF-8 chunk boundary")
  count+=1;local child=Instance.new("StringValue")
  child.Name=string.format("Chunk_%04d",count);child.Value=string.sub(encoded,cursor,last);child.Parent=output
  cursor=last+1
 end
 output:SetAttribute("ChunkCount",count);output:SetAttribute("JSONBytes",#encoded)
 output:SetAttribute("ChecksPassed",report.checkSummary.passed);output:SetAttribute("ChecksFailed",report.checkSummary.failed)
 output:SetAttribute("ActualPlayers",report.actualPlayerCount);output:SetAttribute("FullGameplayAcceptancePassed",false)
 local pieces={}
 for i=1,count do pieces[i]=output[string.format("Chunk_%04d",i)].Value end
 assert(table.concat(pieces)==encoded,"Complete report chunk readback differs")
 local summary=Instance.new("StringValue");summary.Name="Summary"
 local playerSummary={}
 for _,row in report.players do
  table.insert(playerSummary,{name=row.name,userId=row.userId,status=row.status,writable=row.writable,base=row.base,
   profileOrigin=row.diagnostics and row.diagnostics.profileOrigin,isolatedTestProfile=row.diagnostics and row.diagnostics.isolatedTestProfile,
   cargoCount=row.cart and row.cart.cargoCount})
 end
 summary.Value=Http:JSONEncode({schemaVersion=1,status=report.status,runLabel=label,planHash=expectedHash,
  checkSummary=report.checkSummary,players=playerSummary,wallSummary=report.wallSummary,
  profileWrites=0,gameplayWrites=0,sourceWrites=0,fullGameplayAcceptancePassed=false,
  reportEncoding="Concatenate Chunk_0001 through ChunkCount in numeric order; Summary is partial metadata only"})
 assert(#summary.Value<=60000,"Summary exceeds native budget");summary.Parent=output
 output:SetAttribute("CompleteReport",true)
end,debug.traceback)
if not wrote then output:Destroy();error(writeError,0) end
-- Replace only a previous report owned by this helper after complete construction/readback.
if existing then existing:Destroy() end
output.Parent=SS
print("[CompactMap_V1 actual server readback] "..name.." chunks="..output:GetAttribute("ChunkCount").." bytes="..#encoded.." checks="..report.checkSummary.passed.." failed="..report.checkSummary.failed.." fullGameplay=UNVERIFIED")
