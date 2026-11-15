--!nocheck
-- One passive 1Hz scheduler; uses existing server validation/intent/terrain APIs.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local Runtime=require(script.Parent.Parent.Utility.Phase13MovementAnalyticsRuntime)
local Carts=require(script.Parent.CartService)
local Occupants=require(script.Parent.CartOccupantService)
local Longitudinal=require(script.Parent.CartLongitudinalStateService)
local Validation=require(script.Parent.CartMovementValidationService)
local Terrain=require(script.Parent.CartTerrainService)
local Regions=require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Profiles=require(script.Parent.PlayerDataService)
local Service={}
local started=false
local runtime=nil
local deps={}
local connections={}
local failureCount=0
local lastError=nil
function Service:Step(now)
 if not runtime then return end
 local current={}
 for _,record in Carts:GetCartRecords()do
  local cart=record.Model;current[cart]=true
  local root=cart:FindFirstChild("Root")
  local driver=Occupants:GetDriver(cart)
  local intent=Longitudinal:GetMovementAttempt(cart)
  local validation=Validation:GetSnapshot(cart)
  local terrain=Terrain:GetSnapshot(cart)
  local measuredPosition=validation and validation.LastValidCFrame.Position
  local region=if measuredPosition then Regions.GetRegionAtPosition(measuredPosition,math.huge)else nil
  local eligible=root~=nil and driver~=nil and intent~=nil and intent.Driver==driver and validation~=nil
   and now-validation.LastValidSampleTime<=2 and validation.LastSampleTime==validation.LastValidSampleTime
   and not validation.CorrectionActive and not validation.PositionCorrectionPending
   and cart:GetAttribute("ResetActive")~=true and Workspace:GetAttribute("Phase12ResetCommitting")~=true
  runtime:Observe(cart,{Driver=driver,Epoch=intent and intent.Epoch,Region=region and region.id,Position=measuredPosition,
   Speed=validation and validation.LastHorizontalSpeed,Eligible=eligible,Forward=intent and intent.Forward==true,
   Grounded=terrain and terrain.Grounded==true and now-terrain.SampledAt<=2,Slope=terrain and terrain.SlopeAngleDegrees},now)
 end
 for cart in runtime.Carts do if not current[cart]then runtime:Remove(cart,now)end end
 local ready={}
 for _,player in Players:GetPlayers()do if Profiles:GetStatus(player)=="Ready"then table.insert(ready,player)end end
 table.sort(ready,function(a,b)return a.UserId<b.UserId end)
 runtime:Flush(now,ready[1],deps.World.GetPopulationSnapshot())
end
function Service:Start(options)
 if started then return false end
 deps=options or {}
 assert(deps.World and deps.Analytics,"World and Analytics required")
 started=true
 runtime=Runtime.new(function(player,name,value,fields)return deps.Analytics:Record(player,name,value,fields)end,Workspace:GetServerTimeNow())
 deps.World.SetAdmissionObserver(function(category)runtime:Admission(category)end)
 local retirement=assert(deps.World.SubscribeFreshRetirementObserver(function(_record,reason)runtime:Retirement(reason)end),"Retirement diagnostic subscription required")
 table.insert(connections,retirement)
 table.insert(connections,Profiles:SubscribeDiagnostics(function(_player,receipt)runtime:SessionDiagnostic(receipt)end))
 local elapsed=0
 table.insert(connections,RunService.Heartbeat:Connect(function(dt)
  elapsed+=dt
  if elapsed>=1 then
   elapsed=0
   local ok,why=pcall(self.Step,self,Workspace:GetServerTimeNow())
   if not ok then failureCount+=1;lastError=tostring(why):sub(1,240)end
  end
 end))
 table.insert(connections,Players.PlayerRemoving:Connect(function(player)
  for key,s in runtime.Carts do if s.Driver==player then runtime:Remove(key,Workspace:GetServerTimeNow())end end
  -- Player departure emits completed interrupted summaries before adapter teardown.
  local pending=runtime.Pending[player]
  if pending then
   for _,row in pending do pcall(deps.Analytics.Record,deps.Analytics,player,row.Name,if row.Weight>0 then row.Value/row.Weight else row.Value,{category=row.Category,result=row.Result})end
   runtime.Pending[player]=nil
  end
 end))
 return true
end
function Service:GetDiagnostics()
 local count=0;if runtime then for _ in runtime.Carts do count+=1 end end
 return {Started=started,TrackedCarts=count,Connections=#connections,SampleHz=1,SummaryWindowSeconds=60,
  FailureCount=failureCount,LastError=lastError}
end
function Service:Stop()
 if not started then return end
 started=false;deps.World.SetAdmissionObserver(nil)
 for _,connection in connections do connection:Disconnect()end
 table.clear(connections);runtime=nil
end
return Service
