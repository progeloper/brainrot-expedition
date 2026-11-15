--!nocheck
return function()
 local Rules=require(game.ReplicatedStorage.Shared.Utility.BrainrotRouteRules)
 local Data=require(game.ReplicatedStorage.Shared.Config.BurrowRoutes)
 local Motor=require(script.Parent.Parent.Utility.BurrowRouteMotor)
 local Barrier=require(script.Parent.Parent.Utility.OrdinaryBankBarrier)
 local Selector=require(script.Parent.Parent.Systems.SpawnSelection)
 local Progression=require(game.ReplicatedStorage.Shared.Config.WorldProgression)
 local Catalog=require(script.Parent.Parent.Utility.BurrowRouteCatalog)
 local World=require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
 local function near(a,b) return math.abs(a-b)<1e-8 end
 local function fixture(points)
  local model=Instance.new("Model");local root=Instance.new("Part");root.Anchored=true;root.Parent=model;model.PrimaryPart=root
  model:PivotTo(CFrame.new(points[1]))
  local route={Id="A>B",EntranceId="A",DestinationId="B",RegionId="REGION_FOREST",Version="fixture",Points=points,Length=Rules.Length(points)}
  local state={Route=Rules.NewJourney(route)}
  local departures,segments=0,{}
  local blocked=false
  local geometry={
   Get=function()return route end,
   ValidateSegment=function(_,a,b) table.insert(segments,{a,b});return not blocked,"FIXTURE_BLOCKED"end,
   ValidateArrival=function(journey,position)return journey.DestinationBurrowId=="B"and(position-points[#points]).Magnitude<=3 end,
   FindReconnect=function(journey,position)
    if blocked then return nil,"FIXTURE_BLOCKED"end
    return Rules.Project(points,position,journey.Progress)
   end,
  }
  local motor=Motor.Create(model,route,{
   GetState=function()return state end,
   Commit=function(nextRoute)state.Route=nextRoute;return true end,
   OnDepart=function()departures+=1;return true end,
  },{GroundOffset=0,Geometry=geometry})
  return {Model=model,Motor=motor,Route=route,State=state,Segments=segments,
   Departures=function()return departures end,Block=function(value)blocked=value end}
 end
 describe("Phase 13 cached route contract",function()
  it("contains 21 mouths and 42 independently validated exact reverse routes",function()
   expect(Data.Ready).to.equal(true);expect(#Data.Mouths).to.equal(21);expect(#Data.Routes).to.equal(42)
   local routes,regions={},{}
   for _,mouth in Data.Mouths do regions[mouth.RegionId]=(regions[mouth.RegionId]or 0)+1;expect(mouth.RegionId=="REGION_CAMP").to.equal(false)end
   for _,count in regions do expect(count).to.equal(3)end
   for _,route in Data.Routes do routes[route.Id]=route;expect(route.Validated).to.equal(true)end
   for _,route in Data.Routes do
    local reverse=routes[route.DestinationId..">"..route.EntranceId]
    expect(reverse~=nil).to.equal(true);expect(#reverse.Points).to.equal(#route.Points)
    for i,p in route.Points do local q=reverse.Points[#route.Points+1-i];expect(p.X==q.X and p.Y==q.Y and p.Z==q.Z).to.equal(true)end
   end
  end)
  it("draws each entrance and each different destination uniformly without retries",function()
   local ids={"A","B","C"};local routes={};local counts={}
   for _,a in ids do for _,b in ids do if a~=b then routes[a..">"..b]={Id=a..">"..b}end end end
   for entrance=1,3 do for destination=1,2 do
    local draws=0
    local selected=Rules.PickJourney(ids,routes,function(low,high)
     draws+=1;expect(low).to.equal(1);expect(high).to.equal(if draws==1 then 3 else 2)
     return if draws==1 then entrance else destination
    end)
    counts[selected.Id]=(counts[selected.Id]or 0)+1;expect(draws).to.equal(2)
   end end
   for _,count in counts do expect(count).to.equal(1)end
  end)
  it("fails closed when a region lacks a selected reachable destination",function()
   local value,reason=Rules.PickJourney({"A","B","C"},{["A>B"]={}},function()return 1 end)
   expect(value).to.equal(nil);expect(reason).to.equal("REGION_REQUIRES_TWO_REACHABLE_DESTINATIONS")
  end)
  it("resolves all rarity speeds independently of mutation",function()
   for index,tier in {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Celestial","Secret"} do
    expect(near(Rules.Speed(tier),6*1.1^(index-1))).to.equal(true)
   end
   expect(Rules.Speed("Astral")).to.equal(Rules.Speed("Celestial"))
  end)
  it("advances equal elapsed distance at 2 Hz and 10 Hz",function()
   local a=fixture({Vector3.zero,Vector3.new(100,0,0)});local b=fixture({Vector3.zero,Vector3.new(100,0,0)})
   for i=1,4 do Motor.Step(a.Motor,.5,6,i*.5)end
   for i=1,20 do Motor.Step(b.Motor,.1,6,i*.1)end
   expect(near(a.State.Route.Progress,12)).to.equal(true);expect(near(a.State.Route.Progress,b.State.Route.Progress)).to.equal(true)
   a.Model:Destroy();b.Model:Destroy()
  end)
  it("walks every detour corner instead of cutting a diagonal chord",function()
   local f=fixture({Vector3.zero,Vector3.new(10,0,0),Vector3.new(10,0,20)})
   Motor.Step(f.Motor,1,15,1)
   expect((f.Model:GetPivot().Position-Vector3.new(10,0,5)).Magnitude<1e-6).to.equal(true)
   expect(#f.Segments).to.equal(2);expect(f.Segments[1][2]).to.equal(Vector3.new(10,0,0));f.Model:Destroy()
  end)
  it("walks a local reconnect after a manoeuvre without rerolling the destination",function()
   local f=fixture({Vector3.zero,Vector3.new(100,0,0)})
   Motor.Step(f.Motor,1,6,1);f.Model:PivotTo(CFrame.new(6,0,4));Motor.Step(f.Motor,.5,6,1.5)
   expect(f.Model:GetPivot().Position).to.equal(Vector3.new(6,0,1));expect(f.State.Route.DestinationBurrowId).to.equal("B")
   expect(f.State.Route.Progress).to.equal(6);f.Model:Destroy()
  end)
  it("retains progress and identity when a native movement check blocks",function()
   local f=fixture({Vector3.zero,Vector3.new(100,0,0)});f.Block(true);Motor.Step(f.Motor,.5,6,.5)
   expect(f.State.Route.Progress).to.equal(0);expect(f.Departures()).to.equal(0);expect(f.Motor.BlockedReason).to.equal("FIXTURE_BLOCKED");f.Model:Destroy()
  end)
  it("crossing an unrelated mouth does not trigger departure",function()
   local f=fixture({Vector3.zero,Vector3.new(100,0,0)});f.Model:PivotTo(CFrame.new(50,0,0))
   expect(Motor.CheckArrival(f.Motor,10)).to.equal(false);expect(f.Departures()).to.equal(0);f.Model:Destroy()
  end)
  it("checks first-arrival grace once and never renews it after later damage or sleep",function()
   local route={Id="A>B",EntranceId="A",DestinationId="B",RegionId="R",Version="V"}
   local state,phase=Rules.Arrival(Rules.NewJourney(route),10,7)
   expect(phase).to.equal("Grace");expect(state.GraceUntil).to.equal(16)
   state=Rules.PauseForSleep(state);state,phase=Rules.Arrival(state,15,15)
   expect(state.GraceUntil).to.equal(16);expect(phase).to.equal("Grace")
   state,phase=Rules.Arrival(state,20,20);expect(phase).to.equal("Entering");expect(state.GraceUntil).to.equal(16)
   state,phase=Rules.Arrival(state,20.6,20.6);expect(phase).to.equal("Depart")
  end)
  it("uses normal entry without grace for damage older than three seconds",function()
   local state,phase=Rules.Arrival({ArrivalChecked=false,GraceUsed=false},10,6.999)
   expect(phase).to.equal("Entering");expect(state.GraceUsed).to.equal(false)
   state,phase=Rules.Arrival(state,10.6,10.5);expect(phase).to.equal("Depart");expect(state.GraceUsed).to.equal(false)
  end)
  it("projects only to the remaining route after a release",function()
   local p=Rules.Project({Vector3.zero,Vector3.new(100,0,0)},Vector3.new(2,0,1),40)
   expect(p.Progress).to.equal(40);expect(p.Point).to.equal(Vector3.new(40,0,0))
  end)
 end)
 describe("Phase 13 native destination and release geometry",function()
  local function nativeGeometry(callback)
   local folder=Instance.new("Folder");folder.Name="Phase13NativeRouteFixture";folder.Parent=workspace
   local floor=Instance.new("Part");floor.Name="Support";floor.Anchored=true;floor.Size=Vector3.new(128,1,128)
   floor.CFrame=CFrame.new(6000,1999.5,6000);floor.CanCollide=true;floor.Parent=folder
   local points={{X=5960,Y=2000,Z=6000},{X=6040,Y=2000,Z=6000}}
   local data={Ready=true,GeometryVersion="NativeFixture",Hull={X=2,Y=4,Z=2},MaxReconnectDistance=8,ArrivalRadius=3,
    Mouths={{Id="F01",RegionId="REGION_FOREST",Position=points[1]},{Id="F02",RegionId="REGION_FOREST",Position=points[2]}},
    Routes={{Id="F01>F02",EntranceId="F01",DestinationId="F02",RegionId="REGION_FOREST",Validated=true,Points=points}}}
   local ran,failure=xpcall(function()
    Catalog._TestWithGeometry(data,function(region,point)
     local p=floor.CFrame:PointToObjectSpace(point)
     return region=="REGION_FOREST"and math.abs(p.X)<=64 and math.abs(p.Z)<=64 and math.abs(p.Y-.5)<=2
    end,function()
     local route=assert(Catalog.Get("F01>F02"))
     callback(route,Rules.NewJourney(route),folder)
    end)
   end,debug.traceback)
   folder:Destroy();assert(ran,failure)
  end
  it("accepts a native supported endpoint and rejects an adjacent floor height",function()
   nativeGeometry(function(route,journey)
    local endpoint=route.Points[#route.Points]
    expect(Catalog.ValidateArrival(journey,endpoint)).to.equal(true)
    local ok,reason=Catalog.ValidateArrival(journey,endpoint+Vector3.yAxis)
    expect(ok).to.equal(false);expect(reason).to.equal("NOT_AT_DESTINATION")
   end)
  end)
  it("rejects arrival through a newly introduced native wall",function()
   nativeGeometry(function(route,journey,folder)
    local endpoint=route.Points[#route.Points];local direction=(endpoint-route.Points[#route.Points-1]).Unit
    local wall=Instance.new("Part");wall.Name="Wall";wall.Anchored=true;wall.CanCollide=true
    wall.Size=Vector3.new(2,7,2);wall.CFrame=CFrame.new(endpoint-direction+Vector3.yAxis*3.5);wall.Parent=folder
    expect(Catalog.ValidateArrival(journey,endpoint-direction*2)).to.equal(false)
   end)
  end)
  it("rejects a foreign-region release and a distant in-region reconnect",function()
   nativeGeometry(function(route,journey)
    local value,reason=Catalog.FindReconnect(journey,Vector3.new(0,2000,0))
    expect(value).to.equal(nil);expect(reason).to.equal("ORIGINAL_ROUTE_REGION_REQUIRED")
    local point,direction=Rules.Sample(route.Points,40);local perpendicular=Vector3.new(-direction.Z,0,direction.X)
    value,reason=Catalog.FindReconnect(journey,point+perpendicular*20)
    expect(value).to.equal(nil);expect(reason).to.equal("NO_LOCAL_ROUTE_RECONNECT")
   end)
  end)
  it("rejects an endpoint that does not match the persisted destination",function()
   nativeGeometry(function(route,journey)
    journey.DestinationBurrowId="F03"
    local ok,reason=Catalog.ValidateArrival(journey,route.Points[#route.Points])
    expect(ok).to.equal(false);expect(reason).to.equal("DESTINATION_CHANGED")
   end)
  end)
  it("returns a reactive excursion around a real obstacle instead of stalling at a blocked nearest projection",function()
   nativeGeometry(function(route,journey,folder)
    local model=Instance.new("Model");model.Name="ExcursionIndividual";model.Parent=folder
    local root=Instance.new("Part");root.Name="Root";root.Anchored=true;root.CanCollide=false;root.Parent=model;model.PrimaryPart=root
    journey.Progress=20
    local start=Rules.Sample(route.Points,20);model:PivotTo(CFrame.new(start))
    local state={Route=journey}
    local motor=Motor.Create(model,route,{GetState=function()return state end,
     Commit=function(nextRoute)state.Route=nextRoute;return true end,OnDepart=function()return false end},{GroundOffset=0,Geometry=Catalog})
    local wall=Instance.new("Part");wall.Name="ProjectionBlocker";wall.Anchored=true;wall.CanCollide=true
    wall.Size=Vector3.new(3,7,4);wall.CFrame=CFrame.new(start+Vector3.new(10,3.5,5));wall.Parent=folder
    local first=start+Vector3.new(0,0,10);local second=first+Vector3.new(10,0,0)
    expect(Motor.RecordExcursion(motor,start,first)).to.equal(true);model:PivotTo(CFrame.new(first))
    expect(Motor.RecordExcursion(motor,first,second)).to.equal(true);model:PivotTo(CFrame.new(second))
    expect(Catalog.FindReconnect(state.Route,second,{model},40)).to.equal(nil)
    -- Sleep state clones preserve the reversible corridor and selected IDs.
    state.Route=Rules.PauseForSleep(state.Route)
    Motor.Step(motor,1,10,1);expect((model:GetPivot().Position-first).Magnitude<.01).to.equal(true)
    Motor.Step(motor,1,10,2);expect((model:GetPivot().Position-start).Magnitude<.01).to.equal(true)
    Motor.Step(motor,.5,6,2.5)
    expect(state.Route.Progress>20).to.equal(true);expect(state.Route.DestinationBurrowId).to.equal("F02")
    expect(state.Route.ExcursionReturn).to.equal(nil)
   end)
  end)
  it("activates a real counted natural record and retains its frozen journey through sleep/wake",function()
   nativeGeometry(function(route,journey)
    local owned={};local RS=game.ReplicatedStorage
    local assets=RS:FindFirstChild("StudioAssets")
    if not assets then assets=Instance.new("Folder");assets.Name="StudioAssets";assets.Parent=RS;table.insert(owned,assets)end
    local brainrots=assets:FindFirstChild("Brainrots")
    if not brainrots then brainrots=Instance.new("Folder");brainrots.Name="Brainrots";brainrots.Parent=assets;table.insert(owned,brainrots)end
    if not brainrots:FindFirstChild("BRT_001")then
     local model=Instance.new("Model");model.Name="BRT_001"
     local root=Instance.new("Part");root.Name="Root";root.Transparency=1;root.Size=Vector3.one;root.Anchored=true;root.CanQuery=false;root.CanCollide=false;root.Parent=model
     local body=Instance.new("Part");body.Name="Body";body.Size=Vector3.new(2,4,2);body.CFrame=CFrame.new(0,2,0);body.Anchored=true;body.CanQuery=true;body.Parent=model
     local capture=Instance.new("Attachment");capture.Name="CaptureAttachment";capture.Parent=body
     local cargo=Instance.new("Attachment");cargo.Name="CargoAttachment";cargo.CFrame=CFrame.new(0,-2,0);cargo.Parent=body
     model.PrimaryPart=root;model.Parent=brainrots;table.insert(owned,model)
    end
    local record,prepared
    local subscriptions={}
    local ran,failure=xpcall(function()
     local why;record,why=World.CreateWorldRecord("BRT_001","Phase13_RouteActivationFixture",CFrame.new(route.Points[1]),"REGION_FOREST",{Journey=journey,MutationId="None"})
     assert(record,why);prepared=assert(World.PrepareWorldRepresentation(record,CFrame.new(route.Points[1])))
     local model,reason=World.ActivatePreparedWorld(prepared);assert(model,reason)
     local state=World.GetPhase12State(record)
     expect(state.Route.RouteId).to.equal(route.Id);expect(table.isfrozen(state.Route)).to.equal(true)
     expect(World.TrySleep(model)).to.equal(true);expect(World.ResumeWorld(model)).to.equal(true)
     state=World.GetPhase12State(record);expect(state.RemainingHp).to.equal(state.MaxHp)
     expect(state.Route.EntranceBurrowId).to.equal("F01");expect(state.Route.DestinationBurrowId).to.equal("F02")
     expect(World.GetRouteSnapshot(model).RouteId).to.equal(route.Id)
     record=assert(World.GetWorldRecord(model),"Retirement fixture requires the canonical activated source")
     local observed,disconnected=0,0
     local function subscribe(callback)
      local connection=assert(World.SubscribeFreshRetirementObserver(callback),"Read-only retirement subscription must be accepted")
      table.insert(subscriptions,connection);return connection
     end
     subscribe(function(actual,retirementReason)expect(actual).to.equal(record);expect(retirementReason).to.equal("BurrowDeparture");observed+=1 end)
     subscribe(function()error("INJECTED_RETIREMENT_OBSERVER_FAILURE")end)
     local off=subscribe(function()disconnected+=1 end);off.Disconnect()
     for _=1,6 do subscribe(function()end)end
     local excess,excessReason=World.SubscribeFreshRetirementObserver(function()end)
     expect(excess).to.equal(nil);expect(excessReason).to.equal("RETIREMENT_OBSERVER_LIMIT")
     local population=World.GetPopulationSnapshot().Effective
     expect(World.RetireFreshIndividual(record,"BurrowDeparture")).to.equal(true)
     expect(World.GetPopulationSnapshot().Effective).to.equal(population-1)
     expect(observed).to.equal(1);expect(disconnected).to.equal(0)
     expect(World.RetireFreshIndividual(record,"BurrowDeparture")).to.equal(false);expect(observed).to.equal(1)
    end,debug.traceback)
    for _,connection in subscriptions do connection.Disconnect()end
    if record then World.DestroyWorldForTesting(record.ItemId)end
    if prepared then World.DiscardPreparedWorld(prepared)end
    for i=#owned,1,-1 do owned[i]:Destroy()end
    assert(ran,failure)
   end)
  end)
 end)
 describe("Phase 13 counted pending bank absence recovery",function()
  it("aborts an absent first bank to the same counted local release without changing route or handling",function()
   local RS=game.ReplicatedStorage;local owned={}
   local support=Instance.new("Part");support.Name="Phase13PendingAbsenceSupport";support.Anchored=true
   support.Size=Vector3.new(64,1,64);support.CFrame=CFrame.new(7000,1999.5,7000);support.Parent=workspace;table.insert(owned,support)
   local assets=RS:FindFirstChild("StudioAssets")
   if not assets then assets=Instance.new("Folder");assets.Name="StudioAssets";assets.Parent=RS;table.insert(owned,assets)end
   local brainrots=assets:FindFirstChild("Brainrots")
   if not brainrots then brainrots=Instance.new("Folder");brainrots.Name="Brainrots";brainrots.Parent=assets;table.insert(owned,brainrots)end
   if not brainrots:FindFirstChild("BRT_001")then
    local model=Instance.new("Model");model.Name="BRT_001"
    local root=Instance.new("Part");root.Name="Root";root.Transparency=1;root.Size=Vector3.one;root.Anchored=true;root.CanQuery=false;root.CanCollide=false;root.Parent=model
    local body=Instance.new("Part");body.Name="Body";body.Size=Vector3.new(2,4,2);body.CFrame=CFrame.new(0,2,0);body.Anchored=true;body.CanQuery=true;body.Parent=model
    local capture=Instance.new("Attachment");capture.Name="CaptureAttachment";capture.Parent=body
    local cargo=Instance.new("Attachment");cargo.Name="CargoAttachment";cargo.CFrame=CFrame.new(0,-2,0);cargo.Parent=body
    model.PrimaryPart=root;model.Parent=brainrots;table.insert(owned,model)
   end
   local record,prepared,operation
   local before=World.GetPopulationSnapshot().Effective
   local ran,failure=xpcall(function()
    local pose=CFrame.new(7000,2000,7000)*CFrame.Angles(0,.4,0)
    local journey=Rules.NewJourney({Id="F01>F02",EntranceId="F01",DestinationId="F02",RegionId="REGION_FOREST",Version=Data.GeometryVersion})
    record=assert(World.CreateWorldRecord("BRT_001","Phase13_PendingAbsenceFixture",pose,"REGION_FOREST",{MutationId="Golden",Journey=journey}))
    prepared=assert(World.PrepareWorldRepresentation(record,pose))
    local model=assert(World.ActivatePreparedWorld(prepared))
    record=assert(World.GetWorldRecord(model),"Activated source must expose its canonical authoritative record")
    expect(World.TrySleep(model)).to.equal(true)
    local taken,controlled=World.TakeSleepingWorld(model,record);assert(taken,"Sleeping natural source must transfer to controlled custody");record=controlled;model:Destroy()
    World.MarkFreshTransit(record,"Cargo")
    local retained=World.UpdatePhase12State(record,{EscapeAttemptsUsed=2,EscapeMaxAttempts=3,EscapeRemainingSeconds=2.75,
     EscapeGeneration=7,WarningGeneration=6,Route=table.freeze({RouteId="F01>F02",EntranceBurrowId="F01",DestinationBurrowId="F02",
      RegionId="REGION_FOREST",RouteVersion=Data.GeometryVersion,Progress=12,ArrivalChecked=true,GraceUsed=true,GraceUntil=80,Generation=4})})
    assert(retained,"Fresh escape/route state must exist before pending bank")
    operation="Bank:"..record.ItemId
    expect(World.GetPopulationSnapshot().Effective).to.equal(before+1)
    expect(World.BeginPendingBank(record,operation,7)).to.equal(true)
    expect(World.GetPopulationSnapshot().Effective).to.equal(before+1)
    expect(World.IsPendingBank(record.ItemId)).to.equal(true)
    expect(World.CanAbortPendingBankToFreshRelease(record,"Bank:wrong-operation",pose)).to.equal(false)
    expect(World.GetPopulationSnapshot().Effective).to.equal(before+1)
    local wrongSpecies=table.clone(record);wrongSpecies.BrainrotId="BRT_002"
    expect(World.AbortPendingBankToFreshRelease(wrongSpecies,operation,pose)).to.equal(false)
    local wrongMutation=table.clone(record);wrongMutation.Metadata=table.clone(record.Metadata);wrongMutation.Metadata.MutationId="Shiny"
    expect(World.AbortPendingBankToFreshRelease(wrongMutation,operation,pose)).to.equal(false)
    expect(World.CanAbortPendingBankToFreshRelease(record,operation,Vector3.zero)).to.equal(false)
    expect(World.CanAbortPendingBankToFreshRelease(record,operation,CFrame.new(0/0,0,0))).to.equal(false)
    expect(World.IsPendingBank(record.ItemId)).to.equal(true)
    expect(World.GetPhase12State(record)).to.equal(retained)
    expect(World.CanAbortPendingBankToFreshRelease(record,operation,pose)).to.equal(true)
    expect(World.IsPendingBank(record.ItemId)).to.equal(true)
    expect(World.AbortPendingBankToFreshRelease(record,operation,pose)).to.equal(true)
    expect(World.GetPopulationSnapshot().Effective).to.equal(before+1)
    expect(World.IsPendingBank(record.ItemId)).to.equal(false)
    expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
    expect(World.GetPhase12State(record)).to.equal(retained)
    local queued
    for _,entry in World.GetPopulationSnapshot().PendingWorldRecords do if entry.ItemId==record.ItemId then queued=entry end end
    assert(queued,"Aborted bank must retain counted PendingWorld queue custody");expect(queued.Pose).to.equal(pose);expect(queued.MutationId).to.equal("Golden")
    local member
    for _,entry in World.GetWildSnapshot()do if entry.RuntimeId==record.ItemId then member=entry end end
    expect(member.State).to.equal("PendingWorld");expect(member.PendingBankAbort.Record.Metadata).to.equal(record.Metadata)
    expect(World.PrepareFreshRelease(record,pose)).to.equal(nil) -- No legal local route at this captured source pose.
    expect(World.CanAbortPendingBankToFreshRelease(record,operation,pose)).to.equal(true)
    expect(World.AbortPendingBankToFreshRelease(record,operation,pose)).to.equal(true)
    expect(World.AbortPendingBankToFreshRelease(record,operation,pose+CFrame.new(1,0,0).Position)).to.equal(false)
    local retired,why=World.RetireUnconfirmedPendingBank(record,operation)
    expect(retired).to.equal(false);expect(why).to.equal("SAVE_CONFIRMATION_OR_COUNTED_RELEASE_REQUIRED")
    expect(World.GetPopulationSnapshot().Effective).to.equal(before+1)
    expect(World.GetPhase12State(record)).to.equal(retained)
    for _,entry in World.GetPopulationSnapshot().PendingWorldRecords do if entry.ItemId==record.ItemId then expect(entry.Pose).to.equal(pose)end end
   end,debug.traceback)
   -- Disposable fixture cleanup even if an assertion interrupts the normal path.
   if record then
    if World.IsPendingBank(record.ItemId)then World.ConfirmPendingBank(record,operation)end
    World.DestroyWorldForTesting(record.ItemId)
   end
   if prepared then World.DiscardPreparedWorld(prepared)end
   for i=#owned,1,-1 do owned[i]:Destroy()end
   assert(ran,failure)
  end)
 end)
 describe("Phase 13 pending bank reservation barrier",function()
  it("retains one counted member until confirmation and releases it exactly once",function()
   local pending={};local members={id={SpeciesId="BRT_001"}};local record={ItemId="id",BrainrotId="BRT_001"};local released=0
   expect(Barrier.Begin(pending,members,record,"Bank:id",4)).to.equal(true)
   expect(Barrier.Begin(pending,members,record,"Bank:id",4)).to.equal(true)
   expect(members.id~=nil).to.equal(true);expect(pending.id.CoveringRevision).to.equal(4)
   local function release(id)released+=1;members[id]=nil;return true end
   expect(Barrier.Confirm(pending,members,"id","Bank:id",release)).to.equal(true)
   expect(Barrier.Confirm(pending,members,"id","Bank:id",release)).to.equal(true)
   expect(released).to.equal(1);expect(pending.id).to.equal(nil)
  end)
  it("retains a pending bank when publication fails and rejects identity mismatch",function()
   local pending={};local members={id={SpeciesId="BRT_001"}}
   expect(Barrier.Begin(pending,members,{ItemId="id",BrainrotId="BRT_002"},"Bank:id",4)).to.equal(false)
   expect(Barrier.Begin(pending,members,{ItemId="id",BrainrotId="BRT_001"},"Bank:id",4)).to.equal(true)
   expect(Barrier.Confirm(pending,members,"id","Bank:id",function()return false,"RETRY"end)).to.equal(false)
   expect(pending.id~=nil and members.id~=nil).to.equal(true)
  end)
 end)
 describe("Phase 13 Glitch absolute rare probability",function()
  it("keeps BRT_032 at .0002 without redistributing the other tiers",function()
   local pool=Progression.Pools.REGION_GLITCH;local candidates={}
   for tier,ids in pool.species do for _,id in ids do table.insert(candidates,{id=id,tier=tier,assignmentStatus="Approved",
    homeRegionId=Progression.HomeBySpecies[id],allowedRegionIds=Progression.AllowedBySpecies[id],spawnEnabled=true,
    launchStatus="Live",naturalSpawnEligible=true,modelReady=true,behaviourReady=true,locationReady=true,globalWithinTierWeight=1})end end
   local compiled=Selector.CompileRegion("REGION_GLITCH",{id="REGION_GLITCH",kind="Hunting",enabled=true,naturalSpawnAllowed=true,
    spawnSelection={tierWeights=pool.tierWeights,speciesWeightOverrides=pool.speciesWeightOverrides}},candidates,{BRT_032=.0002}).pool
   expect(compiled~=nil).to.equal(true)
   local report=Selector.DescribeDistribution(compiled);local probabilities={}
   for _,row in report.species do probabilities[row.speciesId]=row.effectiveOverallProbability end
   expect(near(probabilities.BRT_031,.5998)).to.equal(true);expect(near(probabilities.BRT_032,.0002)).to.equal(true)
   local other=0;for id,p in probabilities do if id~="BRT_031"and id~="BRT_032"then other+=p end end
   expect(near(other,.4)).to.equal(true)
  end)
 end)
end
