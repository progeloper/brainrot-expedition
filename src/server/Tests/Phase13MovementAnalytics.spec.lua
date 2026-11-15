return function()
 local Runtime=require(script.Parent.Parent.Utility.Phase13MovementAnalyticsRuntime)
 local function fixture()
  local events={}
  local runtime=Runtime.new(function(player,name,value,fields)table.insert(events,{Player=player,Name=name,Value=value,Category=fields.category,Result=fields.result})end,0)
  return runtime,events
 end
 local function sample(region,x,speed,forward,epoch)
  return {Driver="fixture-player",Region=region,Position=Vector3.new(x,0,0),Speed=speed,Forward=forward==true,
   Grounded=true,Slope=7,Eligible=true,Epoch=epoch or 1}
 end
 local function sum(events,name,category)
  local value=0;for _,e in events do if e.Name==name and e.Category==category then value+=e.Value end end;return value
 end
 describe("Phase13 passive movement/admission aggregates",function()
  it("aggregates actual rejection categories once per sixty-second window and distinguishes identities from awake",function()
   local r,e=fixture()
   for _=1,17 do r:Admission("BehaviourCap")end
   r:Admission("client-arbitrary-category")
   expect(r:Flush(59,"fixture-player",{Effective=42,AwakeCreatures=9})).to.equal(false)
   expect(#e).to.equal(0)
   expect(r:Flush(60,"fixture-player",{Effective=42,AwakeCreatures=9})).to.equal(true)
   expect(sum(e,"AdmissionDenied","BehaviourCap")).to.equal(17)
   expect(sum(e,"AvailabilitySummary","ReservedIdentities")).to.equal(42)
   expect(sum(e,"AvailabilitySummary","AwakeCreatures")).to.equal(9)
   expect(r:Flush(60,"fixture-player",nil)).to.equal(false)
   expect(#e).to.equal(3)
  end)
  it("measures only sampled cart positions and speeds and retains interrupted trip denominator",function()
   local r,e=fixture()
   r:Observe("cart",sample("REGION_CAMP",0,0),0)
   r:Observe("cart",sample("REGION_FOREST",10,10),1)
   r:Observe("cart",sample("REGION_FOREST",20,10),2)
   r:Observe("cart",sample("REGION_CAMP",30,10),3)
   r:Observe("cart",sample("REGION_FOREST",40,10),4)
   r:Remove("cart",6)
   r:Flush(60,nil,nil)
   expect(sum(e,"CartTrip","CartTripSeconds")).to.equal(4)
   expect(sum(e,"CartTrip","CartTripEpisodes")).to.equal(2)
   expect(sum(e,"CartTrip","CartTripDistanceStuds")).to.equal(40)
   local success,interrupted=0,0
   for _,event in e do if event.Name=="CartTrip"and event.Category=="CartTripSeconds"then
    if event.Result=="Success"then success+=1 elseif event.Result=="Interrupted"then interrupted+=1 end
   end end
   expect(success).to.equal(1);expect(interrupted).to.equal(1)
  end)
  it("counts one grounded forward-intent stall across multiple flushes and ignores intentional neutral stops",function()
   local r,e=fixture()
   r:Observe("cart",sample("REGION_CAMP",0,0,true),0)
   for at=1,60 do r:Observe("cart",sample("REGION_CAMP",0,0,true),at)end
   r:Flush(60,nil,nil)
   for at=61,70 do r:Observe("cart",sample("REGION_CAMP",0,0,true),at)end
   r:Observe("cart",sample("REGION_CAMP",0,0,false),71)
   for at=72,120 do r:Observe("cart",sample("REGION_CAMP",0,0,false),at)end
   r:Flush(120,nil,nil)
   expect(sum(e,"CartStall","CartStallEpisodes")).to.equal(1)
   expect(sum(e,"CartStall","CartStallSeconds")).to.equal(70)
  end)
  it("does not mistake an invalid/reset/changed-epoch displacement for travelled distance",function()
   local r,e=fixture()
   r:Observe("cart",sample("REGION_CAMP",0,0),0)
   r:Observe("cart",sample("REGION_FOREST",10,10),1)
   local reset=sample("REGION_CAMP",1000,0);reset.Eligible=false
   r:Observe("cart",reset,2)
   r:Observe("cart",sample("REGION_FOREST",5000,0,false,2),3)
   r:Flush(60,nil,nil)
   expect(sum(e,"CartTrip","CartTripDistanceStuds")).to.equal(10)
   expect(sum(e,"CartStall","CartStallEpisodes")).to.equal(0)
  end)
  it("bounds successful departure/reset and canonical recovery diagnostics to one sanitized global window",function()
   local r,e=fixture()
   for _=1,20 do r:Retirement("BurrowDeparture")end
   r:Retirement("Phase12Reset:9");r:Retirement("Phase12Reset");r:Retirement("FailedPreparation")
   r:SessionDiagnostic({kind="SessionLost",code="PRIVATE_BACKEND_DETAIL",eventId="PRIVATE_ID"})
   r:SessionDiagnostic({kind="SessionRecovered",rawProfile={Balance=100}})
   r:SessionDiagnostic({kind="RecoveryRequested"})
   expect(r:Flush(59,"representative",nil)).to.equal(false);expect(#e).to.equal(0)
   expect(r:Flush(60,"representative",nil)).to.equal(true);expect(#e).to.equal(4)
   expect(sum(e,"BurrowDeparture","Hunt")).to.equal(20);expect(sum(e,"ResetOutcome","Reset")).to.equal(2)
   local pending,success=0,0
   for _,event in e do
    expect(event.Player).to.equal("representative")
    if event.Name=="TransactionRecovery"then
     expect(event.Category).to.equal("Save")
     if event.Result=="Pending"then pending+=event.Value elseif event.Result=="Success"then success+=event.Value end
    end
   end
   expect(pending).to.equal(1);expect(success).to.equal(1)
   expect(r:Flush(60,"representative",nil)).to.equal(false);expect(#e).to.equal(4)
   r.Emit=function()error("INJECTED_GLOBAL_TELEMETRY_FAILURE")end;r:Retirement("BurrowDeparture")
   expect(r:Flush(120,"representative",nil)).to.equal(true);expect(next(r.Global)).to.equal(nil)
  end)
  it("isolates telemetry failure from observations and drops bounded-window aggregates",function()
   local r=Runtime.new(function()error("INJECTED_ANALYTICS_FAILURE")end,0)
   r:Admission("GlobalCap")
   expect(r:Flush(60,"fixture-player",{Effective=42,AwakeCreatures=0})).to.equal(true)
   expect(next(r.Denied)).to.equal(nil)
   expect(next(r.Pending)).to.equal(nil)
  end)
 end)
end
