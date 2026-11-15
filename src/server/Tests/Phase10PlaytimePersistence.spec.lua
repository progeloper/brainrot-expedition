--!nocheck
-- Actual profile snapshot/save/close/rejoin path; backend and world-ready clock
-- are isolated fixtures, not a production datastore or native multi-client test.
return function()
 local Profile=require(script.Parent.Parent.Services.PlayerDataService)
 local Combat=require(script.Parent.Parent.Services.PlayerCombatService)
 local Schema=require(script.Parent.Parent.Data.PlayerProfileSchema)
 local Backend=require(script.Parent.Support.FakePlayerProfileBackend)
 local Players=game:GetService('Players')
 describe('Phase10 saved world-ready beginner clock',function()
  it('backfills only missing playtime and preserves legacy owned records',function()
   local data=Schema.CreateDefault()
   data.WorldReadyPlaytimeSeconds=nil
   data.Collection.BrainrotInstances.legacy={speciesId='BRT_007',metadata={Mutation='Original'}}
   data.Base.Slots['1'].brainrotId='legacy'
   local migrated=assert(Schema.Migrate(data))
   expect(migrated.WorldReadyPlaytimeSeconds).to.equal(0)
   expect(migrated.Collection.BrainrotInstances.legacy.metadata.Mutation).to.equal('Original')
   for _,bad in {-1,0/0,math.huge,'900'} do
    data.WorldReadyPlaytimeSeconds=bad
    expect(Schema.Migrate(data)).to.equal(nil)
   end
  end)
  it('counts only ready time, expires between samples, and saves/rejoins without another grant',function()
   local backend=Backend.new({Now=function() return 1000 end})
   local clock,worldReady=100,false
   local model=Instance.new('Model') model.Parent=workspace
   local root=Instance.new('Part') root.Name='HumanoidRootPart' root.Anchored=true root.Parent=model
   local humanoid=Instance.new('Humanoid') humanoid.RequiresNeck=false humanoid.Parent=model
   local function player()
    local p={UserId=-887001,Name='PlaytimeFixture',Parent=Players,Character=model,Attributes={}}
    function p:SetAttribute(key,value) self.Attributes[key]=value end
    function p:GetAttribute(key) return self.Attributes[key] end
    function p:Kick() end
    return p
   end
   local p=player() local current={p}
   Profile:_ResetForTests()
   Profile:Init({Backend=backend,UnixNow=function() return 1000 end,MonotonicNow=function() return 1000 end,KickOnFailure=false})
   Combat:_ConfigureForTests({Now=function() return clock end,Ready=function() return worldReady end,
    Players=function() return current end,Camp=function() return false end})
   local ok,err=xpcall(function()
    assert(Profile:LoadPlayerAsync(p).ok,'playtime fixture load failed')
    Combat:Step() clock=500 Combat:Step()
    expect(Combat:GetPlaytime(p)).to.equal(0)
    worldReady=true Combat:Step()
    clock=1399.999
    expect(Combat:GetPlaytime(p)<900).to.equal(true)
    clock=1400 -- no Step yet: the exact eligibility endpoint still applies
    expect(Combat:GetPlaytime(p)).to.equal(900)
    expect(Combat:GetProtectionReason(p)).to.equal(nil)
    Profile:RegisterSnapshotPreparer(function(subject) return Combat:PreparePlaytimeSnapshot(subject) end)
    assert(Profile:SaveNowAsync(p,'PlaytimeFixture').ok,'playtime fixture save failed')
    expect(backend:GetRecord('player_'..p.UserId).Data.WorldReadyPlaytimeSeconds).to.equal(900)
    assert(Profile:ClosePlayerAsync(p,'PlaytimeFixture').ok,'playtime fixture close failed')
    worldReady=false clock=2400
    local rejoined=player() current={rejoined}
    assert(Profile:LoadPlayerAsync(rejoined).ok,'playtime fixture rejoin failed')
    Combat:Step()
    expect(Profile:GetReadableData(rejoined).WorldReadyPlaytimeSeconds).to.equal(900)
    expect(Combat:GetPlaytime(rejoined)).to.equal(900)
    worldReady=true Combat:Step()
    expect(Combat:GetProtectionReason(rejoined)).to.equal(nil)
    expect(Combat:GetPlaytime(rejoined)).to.equal(900)
   end,debug.traceback)
   Combat:_ConfigureForTests(nil) Profile:_ResetForTests() model:Destroy()
   if not ok then error(err) end
  end)
 end)
end
