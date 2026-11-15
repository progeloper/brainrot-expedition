--!nocheck
return function()
 local Rules=require(game.ReplicatedStorage.Shared.Utility.ChariotTeamRules)
 local Schema=require(script.Parent.Parent.Data.PlayerProfileSchema)
 local function near(a,b) assert(math.abs(a-b)<1e-9, tostring(a)..' != '..tostring(b)) end
 local function spend(data,cost) return {ok=data.Economy.Balance>=cost,balance=data.Economy.Balance-cost,balanceBefore=data.Economy.Balance} end
 describe('Phase 9 schema and ownership',function()
  it('adds only two empty slots to an existing profile',function()local d=Schema.CreateDefault()d.ChariotTeam=nil d.Economy.Balance=123.25 d.Base.Slots['1'].accumulatedCash=11.5 local migrated=Schema.Migrate(d)expect(migrated.ChariotTeam.PurchasedExtraSlots).to.equal(0)near(migrated.Economy.Balance,123.25)near(migrated.Base.Slots['1'].accumulatedCash,11.5)end)
  it('sparse six-slot assignments survive save and restore',function()local d=Schema.CreateDefault() d.ChariotTeam.PurchasedExtraSlots=4 for _,i in {2,6} do local id='owned'..i d.Collection.BrainrotInstances[id]={speciesId='BRT_001'}d.Base.Slots[tostring(i)].brainrotId=id d.ChariotTeam.Assignments[tostring(i)]=id end local restored=Schema.Migrate(Schema.CreateSaveSnapshot(d))expect(restored.ChariotTeam.Assignments['1']).to.equal(false)expect(restored.ChariotTeam.Assignments['6']).to.equal('owned6')end)
  for _,value in {-1,5,1.2,'4'} do it('preserves malformed entitlement '..tostring(value)..' and disables only team',function()local d=Schema.CreateDefault()d.ChariotTeam.PurchasedExtraSlots=value local migrated=Schema.Migrate(d)expect(migrated.ChariotTeam.PurchasedExtraSlots).to.equal(value)expect(Rules.Validate(migrated.ChariotTeam)).to.equal(false)expect(Schema.ValidateLoaded(migrated)).to.equal(true)end)end
  it('does not overwrite an unsupported newer team schema',function()local d=Schema.CreateDefault()d.ChariotTeam.SchemaVersion=99 local m=Schema.Migrate(d)expect(m.ChariotTeam.SchemaVersion).to.equal(99)expect(Rules.Validate(m.ChariotTeam)).to.equal(false)end)
  it('repairs locked duplicate and missing references without deleting owned records or cash',function()
   local d=Schema.CreateDefault()d.Collection.BrainrotInstances.a={speciesId='BRT_999'}d.Base.Slots['1'].brainrotId='a'd.Base.Slots['1'].accumulatedCash=17.25 d.ChariotTeam.Assignments['1']='a'd.ChariotTeam.Assignments['2']='a'd.ChariotTeam.Assignments['6']='a'
   expect(Rules.Repair(d).changed).to.equal(true)expect(d.ChariotTeam.Assignments['1']).to.equal('a')expect(d.ChariotTeam.Assignments['2']).to.equal(false)expect(d.ChariotTeam.Assignments['6']).to.equal(false)expect(d.Collection.BrainrotInstances.a.speciesId).to.equal('BRT_999')near(d.Base.Slots['1'].accumulatedCash,17.25)
  end)
  it('successful pickup clears reference while retaining ownership and accrued cash',function()
   local d=Schema.CreateDefault()d.Collection.BrainrotInstances.a={speciesId='BRT_001'}d.Base.Slots['1'].brainrotId='a'd.Base.Slots['1'].accumulatedCash=1.25 d.ChariotTeam.Assignments['2']='a'local before=Schema.CreateSaveSnapshot(d)d.Base.Slots['1'].brainrotId=nil expect(Rules.ClearRemoved(d,before)).to.equal(true)expect(d.ChariotTeam.Assignments['2']).to.equal(false)near(d.Base.Slots['1'].accumulatedCash,1.25)expect(d.Collection.BrainrotInstances.a.speciesId).to.equal('BRT_001')
  end)
  it('continuous direct platform move retains assignment',function()local d=Schema.CreateDefault()d.Collection.BrainrotInstances.a={speciesId='BRT_001'}d.Base.Slots['1'].brainrotId='a'd.ChariotTeam.Assignments['1']='a'local before=Schema.CreateSaveSnapshot(d)d.Base.Slots['1'].brainrotId=nil d.Base.Slots['2'].brainrotId='a'expect(Rules.ClearRemoved(d,before)).to.equal(false)expect(d.ChariotTeam.Assignments['1']).to.equal('a')end)
 end)
 describe('Phase 9 purchase economics',function()
  it('buys exactly slot three retaining fractional cash and empty new slot',function()local d=Schema.CreateDefault()d.Economy.Balance=500000500.25 local r=Rules.Buy(d,3,1,spend)expect(r.ok).to.equal(true)near(d.Economy.Balance,500.25)expect(d.ChariotTeam.PurchasedExtraSlots).to.equal(1)expect(d.ChariotTeam.Assignments['3']).to.equal(false)end)
  it('old target offer never buys the next slot or charges twice',function()local d=Schema.CreateDefault()d.Economy.Balance=1000000000 Rules.Buy(d,3,1,spend)local r=Rules.Buy(d,3,1,spend)expect(r.code).to.equal('ALREADY_APPLIED')near(d.Economy.Balance,500000000)expect(d.ChariotTeam.PurchasedExtraSlots).to.equal(1)end)
  it('all four sequential purchases cost exactly 244500000000',function()local d=Schema.CreateDefault()d.Economy.Balance=244500000000.25 for i=3,6 do expect(Rules.Buy(d,i,1,spend).ok).to.equal(true)end near(d.Economy.Balance,.25)expect(d.ChariotTeam.PurchasedExtraSlots).to.equal(4)expect(Rules.Buy(d,7,1,spend).ok).to.equal(false)end)
  it('does not round a shortfall up or sweep platform money',function()local d=Schema.CreateDefault()d.ChariotTeam.PurchasedExtraSlots=1 d.Economy.Balance=3999999999.99 d.Base.Slots['1'].accumulatedCash=100000 expect(Rules.Buy(d,4,1,spend).ok).to.equal(false)near(d.Economy.Balance,3999999999.99)near(d.Base.Slots['1'].accumulatedCash,100000)end)
  it('cannot skip preceding purchases',function()local d=Schema.CreateDefault()d.Economy.Balance=1e6 expect(Rules.Buy(d,6,1,spend).ok).to.equal(false)expect(d.ChariotTeam.PurchasedExtraSlots).to.equal(0)near(d.Economy.Balance,1e6)end)
  it('configuration changes require a reviewed new offer',function()local d=Schema.CreateDefault()d.Economy.Balance=2000 expect(Rules.Buy(d,3,2,spend).code).to.equal('STALE_OFFER')near(d.Economy.Balance,2000)end)
 end)
	describe("B06 unavailable individuals are not team providers", function()
		it("excludes a locked owned ID until legitimate capacity unlock without deleting its record or cash", function()
			local d = Schema.CreateDefault()
			d.Collection.BrainrotInstances.legacy = { speciesId = "BRT_002" }
			d.Base.Slots["48"] = { brainrotId = "legacy", accumulatedCash = 321.125 }
			d.ChariotTeam.Assignments["1"] = "legacy"
			expect(Rules.Platform(d, "legacy")).to.equal(nil)
			expect(Rules.Repair(d).changed).to.equal(true)
			expect(d.ChariotTeam.Assignments["1"]).to.equal(false)
			expect(d.Base.Slots["48"].accumulatedCash).to.equal(321.125)
			expect(d.Collection.BrainrotInstances.legacy.speciesId).to.equal("BRT_002")
			d.Phase13.ExpansionLevel = 6
			expect(Rules.Platform(d, "legacy")).to.equal(48)
		end)
	end)
end
