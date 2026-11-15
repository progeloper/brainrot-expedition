--!nocheck
-- Exercises the production ledger, scheduler and reservation methods via its
-- existing deterministic harness; these are not copied phase rules.
return function()
 local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
 local Config = require(game.ReplicatedStorage.Shared.Config.BrainrotPopulation)
 local Policy = require(script.Parent.Parent.Utility.WorldPopulationAccessPolicy)
 local PoolValidator = require(script.Parent.Parent.Utility.WorldPoolValidator)
 local function fixture(callback)
  local config=table.clone(Config)
  config.ProfileAdmissionCaps=table.clone(Config.ProfileAdmissionCaps)
  config.ProfileAdmissionCaps.Sprinter=64
  local queue,selected,attempted,committed={},0,{},0
  local block=false
  local sequence=0
  local harness=World._TestCreatePopulationHarness(config,{
   GetRegion=function() return {kind="Hunting",naturalSpawnAllowed=true,populationCap=42} end,
   ChooseRegion=function(_,tried) return if not tried.REGION_FOREST then "REGION_FOREST" else nil end,
   SelectSpecies=function() selected+=1; return {status="Selected",speciesId="BRT_019"} end,
   GenerateReservationId=function() sequence+=1; return "reservation-"..sequence end,
   Schedule=function(delay,fn) table.insert(queue,{Delay=delay,Run=fn}) end,
   SpawnReservation=function(reservation,commit)
    table.insert(attempted,reservation)
    if block then return false,"NO_SAFE_POSE" end
    committed+=1
    return commit("replacement-"..committed)
   end,
  })
  local function runNext() assert(table.remove(queue,1)).Run() end
  for index=1,42 do assert(harness:Register("ordinary-"..index,"BRT_019","REGION_FOREST")) end
  assert(harness:Start()); runNext()
  callback(harness,{
   Run=runNext,Queue=queue,Attempts=attempted,
   SetBlocked=function(value) block=value end,
   Selected=function() return selected end,
   Committed=function() return committed end,
  })
  harness:Stop()
 end
 describe("Phase 10 retained ordinary individuals",function()
  it("fills the initially accessible Forest to 42 using default caps and the configured pool",function()
   local player={UserId=-98101}
   local policy=Policy.new({
    Progression={GetHighestPersonalIndex=function() return 1 end},
    Access={IsOperational=function(_,id) return id=="REGION_FOREST" end},
    GetPlayers=function() return {player} end,
    GetPlayerState=function() return {ready=true,alive=true,regionId="REGION_FOREST"} end,
    Now=function() return 0 end,
    -- Models are available in this admission fixture; memberships, weights,
    -- rare ceilings and behaviour profiles use the actual configured data.
    Compilation=PoolValidator.Validate({ValidateModel=function() return true end}),
   })
   expect(policy:Step()).to.equal(true)
   expect(policy:GetQuota("REGION_FOREST")).to.equal(42)
   expect(policy:GetQuota("REGION_BEACH")).to.equal(0)
   local queue,spawned={},0
   -- Pass the actual configuration directly, without admission-cap overrides.
   local ledger=World._TestCreatePopulationHarness(Config,{
    CheckReadiness=function() return policy:CheckReadiness() end,
    ChooseRegion=function(snapshot,tried) return policy:ChooseRegion(snapshot,tried) end,
    SelectSpecies=function(regionId,availability) return policy:SelectSpecies(regionId,availability) end,
    Schedule=function(_,callback) table.insert(queue,callback) end,
    SpawnReservation=function(reservation,commit)
     expect(reservation.RegionId).to.equal("REGION_FOREST")
     spawned+=1
     return commit("initial-forest-"..spawned)
    end,
   })
   local ok,failure=xpcall(function()
    expect(ledger:Start()).to.equal(true)
    for _=1,Config.TargetWildPopulation do
     if #queue==0 then break end
     table.remove(queue,1)()
     expect(ledger:Snapshot().Effective<=42).to.equal(true)
    end
    local snapshot=ledger:Snapshot()
    expect(snapshot.Ordinary).to.equal(42)
    expect(snapshot.Effective).to.equal(42)
    expect(snapshot.Reserved).to.equal(0)
    expect(snapshot.ByRegion.REGION_FOREST).to.equal(42)
    expect(snapshot.ByBehaviour.Wanderer).to.equal(22)
    expect(snapshot.ByBehaviour.ReactiveRunner).to.equal(12)
    expect(snapshot.ByBehaviour.Sprinter).to.equal(8)
    expect(spawned).to.equal(42)
    expect(#queue).to.equal(0)
    expect(ledger:Validate()).to.equal(true)
   end,debug.traceback)
   ledger:Stop()
   assert(ok,failure)
  end)
  it("keeps 42 through sleep, carry, cargo, repeated release and pending departure",function()
   fixture(function(ledger,f)
    expect(ledger:Snapshot().Effective).to.equal(42)
    for _,state in {"Carried","Cargo","World","Carried","PendingWorld","World"} do
     ledger:Transition("ordinary-1",state)
     expect(ledger:Snapshot().Ordinary).to.equal(42)
     expect(ledger:Snapshot().Reserved).to.equal(0)
     expect(ledger:Validate()).to.equal(true)
    end
    expect(ledger:Unregister("ordinary-1","Destroyed")).to.equal(true)
    expect(ledger:Snapshot().States.PendingWorld).to.equal(1)
    expect(ledger:Snapshot().Effective).to.equal(42)
    expect(#f.Queue).to.equal(0)
    expect(f.Selected()).to.equal(0)
   end)
  end)
  it("releases one place only on first bank and none on duplicate bank or sale",function()
   fixture(function(ledger,f)
    ledger:Transition("ordinary-1","Cargo")
    expect(ledger:FirstBank("ordinary-1")).to.equal(true)
    expect(ledger:FirstBank("ordinary-1")).to.equal(false)
    expect(ledger:Snapshot().Effective).to.equal(41)
    f.Run()
    expect(ledger:Snapshot().Effective).to.equal(42)
    expect(f.Committed()).to.equal(1)
    expect(ledger:FirstBank("ordinary-1")).to.equal(false)
    expect(ledger:Unregister("ordinary-1","Sold")).to.equal(false)
    expect(ledger:Snapshot().Effective).to.equal(42)
    expect(f.Committed()).to.equal(1)
   end)
  end)
  it("conserves 42 across mixed locations and releases PendingBank only on covering confirmation",function()
   fixture(function(ledger,f)
    local locations={"World","WorldSleeping","Carried","Cargo","PendingWorld","PendingTransfer"}
    for index=1,42 do ledger:Transition("ordinary-"..index,locations[(index-1)%#locations+1])end
    expect(ledger:Snapshot().Effective).to.equal(42)
    expect(ledger:Register("forty-third","BRT_019","REGION_FOREST")).to.equal(false)
    expect(ledger:BeginPendingBank("ordinary-1",7)).to.equal(true)
    expect(ledger:BeginPendingBank("ordinary-1",7)).to.equal(true)
    expect(ledger:Snapshot().States.PendingBank).to.equal(1)
    expect(ledger:Snapshot().Effective).to.equal(42);expect(#f.Queue).to.equal(0)
    expect(ledger:ConfirmPendingBank("ordinary-1")).to.equal(true)
    expect(ledger:Snapshot().Effective).to.equal(41)
    expect(ledger:ConfirmPendingBank("ordinary-1")).to.equal(true)
    expect(ledger:Snapshot().Effective).to.equal(41);expect(#f.Queue).to.equal(1)
    f.Run();expect(ledger:Snapshot().Effective).to.equal(42)
    expect(f.Committed()).to.equal(1);expect(ledger:Validate()).to.equal(true)
   end)
  end)
  it("retains failed safe-spawn reservation and retries exactly that selected species",function()
   fixture(function(ledger,f)
    f.SetBlocked(true)
    ledger:FirstBank("ordinary-1"); f.Run()
    expect(ledger:Snapshot().Ordinary).to.equal(41)
    expect(ledger:Snapshot().Reserved).to.equal(1)
    expect(ledger:Snapshot().Effective).to.equal(42)
    local reservation=f.Attempts[1]
    f.Run()
    expect(f.Attempts[2]).to.equal(reservation)
    expect(f.Selected()).to.equal(1)
    expect(ledger:Snapshot().Effective).to.equal(42)
    f.SetBlocked(false); f.Run()
    expect(f.Attempts[3]).to.equal(reservation)
    expect(ledger:Snapshot().Reserved).to.equal(0)
    expect(ledger:Snapshot().Ordinary).to.equal(42)
    expect(f.Selected()).to.equal(1)
   end)
  end)
  it("admits at most 30 replacements when 12 of 42 cargo identities survive a reset",function()
   fixture(function(ledger,f)
    for index=1,12 do ledger:Transition("ordinary-"..index,"Cargo")end
    local survivors={}
    for _,member in ledger:Snapshot().Members do if member.State=="Cargo"then survivors[member.RuntimeId]=member.Phase12 end end
    for index=13,42 do expect(ledger:Retire("ordinary-"..index,"Phase12Reset")).to.equal(true)end
    expect(ledger:Snapshot().Ordinary).to.equal(12)
    expect(ledger:Snapshot().States.Cargo).to.equal(12)
    for _,member in ledger:Snapshot().Members do if member.State=="Cargo"then expect(member.Phase12).to.equal(survivors[member.RuntimeId])end end
    while #f.Queue>0 do f.Run();expect(ledger:Snapshot().Effective<=42).to.equal(true)end
    expect(f.Committed()).to.equal(30)
    expect(ledger:Snapshot().Effective).to.equal(42)
    expect(ledger:Snapshot().States.Cargo).to.equal(12)
    for _,member in ledger:Snapshot().Members do if member.State=="Cargo"then expect(member.Phase12).to.equal(survivors[member.RuntimeId])end end
    for index=1,12 do
     -- Retaining the same IDs, rather than manufacturing survivor copies.
     expect(ledger:Register("ordinary-"..index,"BRT_019","REGION_FOREST")).to.equal(false)
    end
    expect(ledger:Validate()).to.equal(true)
   end)
  end)
  it("admits no refill when all 42 identities are surviving committed cargo",function()
   fixture(function(ledger,f)
    for index=1,42 do ledger:Transition("ordinary-"..index,"Cargo")end
    ledger:Request("Phase12Reset",0);f.Run()
    expect(ledger:Snapshot().Effective).to.equal(42);expect(ledger:Snapshot().States.Cargo).to.equal(42)
    expect(f.Selected()).to.equal(0);expect(f.Committed()).to.equal(0);expect(#f.Queue).to.equal(0)
   end)
  end)
  it("coalesces concurrent first banks without exceeding 42 or duplicating a replacement",function()
   fixture(function(ledger,f)
    ledger:FirstBank("ordinary-1"); ledger:FirstBank("ordinary-2")
    expect(#f.Queue).to.equal(1)
    f.Run()
    expect(ledger:Snapshot().Effective<=42).to.equal(true)
    while #f.Queue>0 do f.Run() end
    expect(ledger:Snapshot().Effective).to.equal(42)
    expect(f.Committed()).to.equal(2)
    expect(ledger:Validate()).to.equal(true)
    expect(ledger:Register("overflow","BRT_019","REGION_FOREST")).to.equal(false)
   end)
  end)
 end)
end
