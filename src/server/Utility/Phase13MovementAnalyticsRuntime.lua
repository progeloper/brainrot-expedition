--!nocheck
-- Passive, bounded aggregates of observed authority samples. No gameplay writes.
local Runtime={}
Runtime.__index=Runtime
local denialCategories={GlobalCap=true,RegionalQuota=true,BehaviourCap=true,NoValidRoute=true,NoValidSpecies=true}
local function finite(x)return type(x)=="number"and x==x and math.abs(x)<math.huge end
function Runtime.new(emit,now)
 return setmetatable({Emit=emit,Carts={},Pending={},Denied={},Global={},Window=now},Runtime)
end
local function aggregate(self,player,name,category,value,result,weight)
 if not player or not finite(value)or value<0 then return end
 local pending=self.Pending[player]or {};self.Pending[player]=pending
 local key=name..":"..category..":"..result
 local row=pending[key]
 if row then
  if category=="CartTripPeakSpeed"or category=="CartStallSlopeDegrees"then row.Value=math.max(row.Value,value)
  else row.Value+=value end
  row.Weight+=(weight or 0)
 else pending[key]={Name=name,Category=category,Value=value,Result=result,Weight=weight or 0}end
end
local function closeTrip(self,s,now,result)
 local t=s.Trip;if not t then return end
 if t.Censored or t.StartedOutside then result="Interrupted"end
 aggregate(self,s.Driver,"CartTrip","CartTripEpisodes",1,result)
 aggregate(self,s.Driver,"CartTrip","CartTripSeconds",math.max(0,now-t.Started),result)
 aggregate(self,s.Driver,"CartTrip","CartTripDistanceStuds",t.Distance,result)
 aggregate(self,s.Driver,"CartTrip","CartTripMeanSpeed",t.SpeedSum,result,t.Samples)
 aggregate(self,s.Driver,"CartTrip","CartTripPeakSpeed",t.Peak,result)
 s.Trip=nil
end
local function closeStall(self,s,continuing)
 local stall=s.Stall
 if stall and stall.Duration>=5 then
  local unreported=stall.Duration-(stall.ReportedDuration or 0)
  if unreported>0 then aggregate(self,s.Driver,"CartStall","CartStallSeconds",unreported,"Recorded")end
  if not stall.Reported then aggregate(self,s.Driver,"CartStall","CartStallEpisodes",1,"Recorded")end
  aggregate(self,s.Driver,"CartStall","CartStallSlopeDegrees",stall.PeakSlope,"Recorded")
  stall.Reported=true;stall.ReportedDuration=stall.Duration
 end
 if not continuing then s.Stall=nil end
end
local function globalCount(self,key)
 self.Global[key]=math.min(1000000,(self.Global[key]or 0)+1)
end
function Runtime:Retirement(reason)
 if reason=="BurrowDeparture"then globalCount(self,"BurrowDeparture")
 elseif type(reason)=="string"and(reason=="Phase12Reset"or reason:match("^Phase12Reset:"))then globalCount(self,"ResetOutcome")end
end
function Runtime:SessionDiagnostic(receipt)
 if type(receipt)~="table"then return end
 if receipt.kind=="SessionLost"then globalCount(self,"RecoveryPending")
 elseif receipt.kind=="SessionRecovered"then globalCount(self,"RecoverySuccess")end
end
function Runtime:Admission(category)
 if denialCategories[category]then self.Denied[category]=(self.Denied[category]or 0)+1 end
end
function Runtime:Remove(key,now)
 local s=self.Carts[key];if not s then return end
 closeTrip(self,s,now,"Interrupted");closeStall(self,s);self.Carts[key]=nil
end
function Runtime:Observe(key,sample,now)
 local s=self.Carts[key]
 if not s then
  s={Driver=sample.Driver,Region=sample.Region,At=now,Position=sample.Position,Epoch=sample.Epoch}
  self.Carts[key]=s
 end
 if s.Driver~=sample.Driver or s.Epoch~=sample.Epoch or not sample.Eligible then
  closeTrip(self,s,now,"Interrupted");closeStall(self,s)
  s.Driver=sample.Driver;s.Region=sample.Region;s.At=now;s.Position=sample.Position;s.Epoch=sample.Epoch
  return
 end
 local dt=now-s.At
 if not finite(dt)or dt<=0 then return end
 if sample.Driver and sample.Region and sample.Region~="REGION_CAMP"and not s.Trip then
  s.Trip={Started=now,StartedOutside=s.Region~="REGION_CAMP",Distance=0,SpeedSum=0,Samples=0,Peak=0,Censored=false}
 end
 if s.Trip then
  if dt>2.5 then s.Trip.Censored=true
  elseif s.Position and sample.Position then s.Trip.Distance+=(sample.Position-s.Position).Magnitude end
  if finite(sample.Speed)and sample.Speed>=0 then
   s.Trip.SpeedSum+=sample.Speed;s.Trip.Samples+=1;s.Trip.Peak=math.max(s.Trip.Peak,sample.Speed)
  end
  if sample.Region=="REGION_CAMP"then closeTrip(self,s,now,"Success")end
 end
 -- Stall means >=5 observed seconds of accepted Forward intent, <0.5 studs/s,
 -- grounded fresh terrain and an eligible uncorrected exact cart/driver epoch.
 -- Neutral/braking/menu/reset/invalid sample never counts as a stall.
 if sample.Driver and sample.Forward and sample.Grounded and finite(sample.Speed)and sample.Speed<.5 and dt<=2.5 then
  local stall=s.Stall or {Duration=0,PeakSlope=0};s.Stall=stall
  stall.Duration+=dt
  if finite(sample.Slope)then stall.PeakSlope=math.max(stall.PeakSlope,sample.Slope)end
 else closeStall(self,s)end
 s.Region=sample.Region;s.At=now;s.Position=sample.Position
end
function Runtime:Flush(now,representative,population,force)
 if not force and now-self.Window<60 then return false end
 self.Window=now
 -- A continuing stall reports elapsed chunks without counting its episode twice.
 for _,s in self.Carts do closeStall(self,s,true)end
 for player,rows in self.Pending do
  for _,row in rows do pcall(self.Emit,player,row.Name,if row.Weight>0 then row.Value/row.Weight else row.Value,{category=row.Category,result=row.Result})end
 end
 table.clear(self.Pending)
 if representative then
  for category,count in self.Denied do pcall(self.Emit,representative,"AdmissionDenied",count,{category=category,result="Denied"})end
  local definitions={BurrowDeparture={"BurrowDeparture","Hunt","Success"},ResetOutcome={"ResetOutcome","Reset","Success"},
   RecoveryPending={"TransactionRecovery","Save","Pending"},RecoverySuccess={"TransactionRecovery","Save","Success"}}
  for key,count in self.Global do local row=definitions[key];pcall(self.Emit,representative,row[1],count,{category=row[2],result=row[3]})end
  if population then
   pcall(self.Emit,representative,"AvailabilitySummary",population.Effective,{category="ReservedIdentities",result="Recorded"})
   pcall(self.Emit,representative,"AvailabilitySummary",population.AwakeCreatures,{category="AwakeCreatures",result="Recorded"})
  end
 end
 table.clear(self.Denied)
 table.clear(self.Global)
 return true
end
return Runtime
