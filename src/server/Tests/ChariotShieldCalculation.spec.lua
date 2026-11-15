--!nocheck
return function()
 local Shared=game.ReplicatedStorage.Shared
 local Rules=require(Shared.Utility.ChariotTeamRules)
 local Config=require(Shared.Config.ChariotTeam)
 local Effects=require(Shared.Config.ChariotEffectDefinitions)
 local Catalog=require(Shared.Config.BrainrotCatalog)
 local Schema=require(script.Parent.Parent.Data.PlayerProfileSchema)
 local function near(a,b)assert(math.abs(a-b)<1e-9,tostring(a)..' != '..tostring(b))end
 local function definition(species,effect,grant,target,cps,rarity)
  return {id=species,tier=rarity or 'Common',cashPerSecond=cps or 2700,
   chariotEffect={effect=effect or 'Shield',contribution=if not effect or effect=='Shield' then 1 else nil,
    contributors=grant or 1,amplifierTarget=if (grant or 1)>1 then target else nil}}
 end
 local function provider(individual,species,grant)
  local id=species or 'FIXTURE_SHIELD_ORDINARY'
  return {individualId=individual,speciesId=id,definition=definition(id,'Shield',grant,'Shield')}
 end
 local function amplifier(individual,target,grant)
  local id='FIXTURE_'..target..'_AMPLIFIER_'..grant
  return {individualId=individual,speciesId=id,definition=definition(id,'Speed',grant,target)}
 end
 local function selected(stats)
  local ids={} for _,detail in stats.details do if detail.effect=='Shield' and detail.selected then table.insert(ids,detail.individualId) end end
  table.sort(ids)return table.concat(ids,',')
 end
 describe('Shield whole-charge providers and matching traits',function()
  for _,case in {{0,1,0},{0,2,0},{0,3,0},{1,1,1},{1,2,1},{1,3,1},{2,1,1},{2,2,2},{2,3,2},{3,2,2},{3,3,3},{6,3,3}} do
   it(case[1]..' providers with Top '..case[2]..' yields '..case[3]..' charges',function()
    local entries={}
    for i=1,case[1] do entries[i]=provider('owned'..i,'FIXTURE_SHIELD_PROVIDER_'..i,if i==1 then case[2] else 1) end
    if case[1]==0 and case[2]>1 then entries[1]=amplifier('amp','Shield',case[2]) end
    local stats=Rules.Calculate(entries)
    expect(stats.shieldCapacity).to.equal(case[3]) expect(stats.shieldCapacity%1).to.equal(0)
    expect(stats.limits.Shield).to.equal(case[2]) expect(stats.effects.Shield.selected).to.equal(case[3])
   end)
  end
  it('same-species Top 2 copies each supply one whole charge',function()
   local stats=Rules.Calculate({provider('a','FIXTURE_SHIELD_TOP2',2),provider('b','FIXTURE_SHIELD_TOP2',2)})
   expect(stats.shieldCapacity).to.equal(2)
   for _,detail in stats.details do expect(detail.rawContribution).to.equal(1)expect(detail.duplicateFactor).to.equal(1)expect(detail.contribution).to.equal(1)expect(detail.appliedContribution).to.equal(1)end
  end)
  it('same-species Top 3 copies remain three whole charges',function()
   local stats=Rules.Calculate({provider('a','FIXTURE_SHIELD_TOP3',3),provider('b','FIXTURE_SHIELD_TOP3',3),provider('c','FIXTURE_SHIELD_TOP3',3)})
   expect(stats.shieldCapacity).to.equal(3) for _,detail in stats.details do expect(detail.contribution).to.equal(1) end
  end)
  it('six same-species Top 3 copies stop at three charges without fraction discounts',function()
   local entries={}for i=1,6 do entries[i]=provider('owned'..i,'FIXTURE_SHIELD_TOP3',3)end
   local stats=Rules.Calculate(entries)expect(stats.shieldCapacity).to.equal(3)expect(stats.count).to.equal(6)
   for _,detail in stats.details do expect(detail.duplicateFactor).to.equal(1)expect(detail.contribution).to.equal(1)end
   expect(stats.details['4'].statusLabel).to.equal('Shield contribution limit reached')
  end)
  it('two Top 2 traits do not stack into Top 3 or multiply capacity',function()
   local stats=Rules.Calculate({provider('a','FIXTURE_SHIELD_TOP2',2),provider('b','FIXTURE_SHIELD_TOP2',2),provider('c')})
   expect(stats.limits.Shield).to.equal(2)expect(stats.shieldCapacity).to.equal(2)
  end)
  it('the strongest Top 3 trait wins over Top 2',function()
   local stats=Rules.Calculate({provider('a','FIXTURE_SHIELD_TOP2',2),provider('b','FIXTURE_SHIELD_TOP3',3),provider('c')})
   expect(stats.limits.Shield).to.equal(3)expect(stats.shieldCapacity).to.equal(3)
  end)
  for _,effect in {'Speed','Hit','Burst'} do
   it('a Top 3 '..effect..' trait cannot raise Shield',function()
    local amp=amplifier('amp',effect,3)
    local stats=Rules.Calculate({provider('a'),provider('b'),amp})
    expect(stats.shieldCapacity).to.equal(1)expect(stats.limits.Shield).to.equal(1)expect(stats.limits[effect]).to.equal(3)
   end)
  end
  it('an other-primary Shield amplifier supplies no Shield charge of its own',function()
   local amp=amplifier('amp','Shield',3)
   local alone=Rules.Calculate({amp})expect(alone.shieldCapacity).to.equal(0)expect(alone.limits.Shield).to.equal(3)
   near(alone.speedBonus,.0095)expect(alone.limits.Speed).to.equal(1)
   local team=Rules.Calculate({provider('a'),provider('b'),amp})
   expect(team.shieldCapacity).to.equal(2)expect(team.effects.Shield.providers).to.equal(2)
   expect(team.details['3'].effect).to.equal('Speed')expect(team.details['3'].amplifierTarget).to.equal('Shield')
   expect(team.details['3'].trait).to.equal('Top 3 Shield')near(team.details['3'].contribution,.0095)
  end)
  it('a primary-Shield amplifier counts as one selected provider',function()
   local stats=Rules.Calculate({provider('amp','FIXTURE_SHIELD_TOP3',3),provider('other')})
   expect(stats.shieldCapacity).to.equal(2)expect(stats.details['1'].selected).to.equal(true)expect(stats.details['1'].appliedContribution).to.equal(1)
  end)
  it('without an amplifier only the best ID contributes and explains the limit',function()
   local stats=Rules.Calculate({provider('z'),provider('a')})
   expect(selected(stats)).to.equal('a')expect(stats.details['1'].statusLabel).to.equal('A Shield amplifier is needed')
  end)
  it('stable individual IDs make slot reorder and duplicate ranking irrelevant to capacity',function()
   local entries={provider('c','FIXTURE_SHIELD_TOP2',2),provider('a','FIXTURE_SHIELD_TOP2',2),provider('b','FIXTURE_SHIELD_TOP2',2)}
   local first=Rules.Calculate(entries)local reordered=Rules.Calculate({entries[3],entries[1],entries[2]})
   expect(first.shieldCapacity).to.equal(2)expect(reordered.shieldCapacity).to.equal(2)expect(selected(first)).to.equal('a,b')expect(selected(reordered)).to.equal('a,b')
  end)
  it('one individual cannot produce two charges from duplicate assignments',function()
   local stats=Rules.Calculate({provider('same','FIXTURE_SHIELD_TOP3',3),provider('same','FIXTURE_SHIELD_TOP3',3)})
   expect(stats.shieldCapacity).to.equal(1)expect(stats.details['2'].issue).to.equal('DUPLICATE_INDIVIDUAL')
  end)
  it('locked providers and locked amplifiers contribute nothing',function()
   local stats=Rules.Calculate({['1']=provider('a'),['2']=provider('b'),['3']=amplifier('locked','Shield',3)},2)
   expect(stats.shieldCapacity).to.equal(1)expect(stats.limits.Shield).to.equal(1)expect(stats.details['3'].issue).to.equal('LOCKED_SLOT')
  end)
  for _,rarity in {'Common','Uncommon','Rare','Epic','Legendary','Mythic','Secret'} do
   it(rarity..' Shield contribution ignores CPS scaling',function()
    for _,cps in {.001,2700,1e12} do
     local def=definition('FIXTURE_SHIELD_CPS','Shield',1,nil,cps,rarity)
     local raw=Rules.Individual(def,def.id)expect(raw.valid).to.equal(true)expect(raw.valueFactor).to.equal(1)expect(raw.contribution).to.equal(1)
    end
   end)
  end
  it('Shield does not depend on missing numerical rarity references',function()
   local raw=Rules.Individual(definition('FIXTURE_SHIELD_REFERENCE','Shield'),nil,{ranges={},count=0,valid=false})
   expect(raw.valid).to.equal(true)expect(raw.contribution).to.equal(1)
  end)
  it('adding a future provider leaves the fixed 35-species anchors unchanged',function()
   local definitions={}for _,def in Catalog.GetAll()do definitions[def.id]=def end
   definitions.FIXTURE_SHIELD_FUTURE=definition('FIXTURE_SHIELD_FUTURE','Shield',3,'Shield',1e12,'Legendary')
   local references=Rules.BuildReferences(definitions)
   expect(#Config.LegacyReferenceSpeciesIds).to.equal(35)expect(references.count).to.equal(35)
   near(references.ranges.Legendary.minimum,135000000)near(references.ranges.Legendary.maximum,165000000)
  end)
  it('a whole-team replacement preview changes only derived maximum capacity',function()
   local entries={provider('a','FIXTURE_SHIELD_TOP3',3),provider('b'),provider('c')}
   local before=Rules.Calculate(entries)
   local replacement={individualId='speed',speciesId='BRT_001',definition=Catalog.Get('BRT_001')}
   local preview=Rules.Preview(entries,1,replacement)
   expect(before.shieldCapacity).to.equal(3)expect(preview.shieldCapacity).to.equal(1)expect(preview.shieldRemaining).to.equal(nil)
   expect(entries[1].individualId).to.equal('a')near(preview.speedBonus,.0095)
  end)
 end)
 describe('Four-effect definitions and safe static validation',function()
  it('publishes four stable metadata definitions without changing slot schema',function()
   expect(#Effects.Ordered).to.equal(4)expect(table.concat(Effects.OrderedIds,',')).to.equal('Speed,Hit,Burst,Shield')
   expect(Effects.Get('Shield').Stat).to.equal('shieldCapacity')expect(Effects.Get('Shield').UsesCPS).to.equal(false)
   expect(Effects.Get('Shield').Description).to.equal('Blocks a cargo hit and protects your cargo for 5 seconds. Refills at your base.')
   expect(Config.Version).to.equal(1)expect(Config.SchemaVersion).to.equal(1)expect(Config.Shield.ProtectionSeconds).to.equal(5)
   expect(Rules.ValidateSpeciesEffects().errors[1]).to.equal(nil)
  end)
  local cases={
   {{effect='Shield',contribution=0},'SHIELD_CONTRIBUTION_INVALID'},
   {{effect='Shield',contribution=.5},'SHIELD_CONTRIBUTION_INVALID'},
   {{effect='Shield',contribution=2},'SHIELD_CONTRIBUTION_INVALID'},
   {{effect='Shield',contribution='1'},'SHIELD_CONTRIBUTION_INVALID'},
   {{effect='Shield'},'SHIELD_CONTRIBUTION_INVALID'},
   {{effect='Universal',contribution=1},'EFFECT_IDENTIFIER_INVALID'},
   {{effect='shield',contribution=1},'EFFECT_IDENTIFIER_INVALID'},
   {{effect='Shield',contribution=1,contributors=0},'CONTRIBUTOR_LIMIT_INVALID'},
   {{effect='Shield',contribution=1,contributors=1.5},'CONTRIBUTOR_LIMIT_INVALID'},
   {{effect='Shield',contribution=1,contributors=4},'CONTRIBUTOR_LIMIT_INVALID'},
   {{effect='Shield',contribution=1,contributors='2'},'CONTRIBUTOR_LIMIT_INVALID'},
   {{effect='Shield',contribution=1,contributors=2,amplifierTarget='Universal'},'AMPLIFIER_TARGET_INVALID'},
   {{effect='Shield',contribution=1,contributors=1,amplifierTarget='Shield'},'AMPLIFIER_WITHOUT_GRANT'},
   {{effect='Speed',contribution=1},'NUMERICAL_CONTRIBUTION_OVERRIDE'},
  }
  for index,case in cases do
   it('rejects malformed static definition '..index..' without rewriting saves',function()
    local valid,code=Effects.ValidateSpeciesEffect(case[1],'FIXTURE_SHIELD_INVALID')
    expect(valid).to.equal(false)expect(code).to.equal(case[2])
    local def=definition('FIXTURE_SHIELD_INVALID','Shield')def.chariotEffect=case[1]
    local stats=Rules.Calculate({{individualId='owned',speciesId=def.id,definition=def}})
    expect(stats.shieldCapacity).to.equal(0)expect(stats.details['1'].valid).to.equal(false)
    local data=Schema.CreateDefault()data.Economy.Balance=123.25 data.Base.Slots['1'].accumulatedCash=9.75
    data.Collection.BrainrotInstances.owned={speciesId='BRT_001'}data.Base.Slots['1'].brainrotId='owned'data.ChariotTeam.Assignments['1']='owned'
    local restored=Schema.Migrate(Schema.CreateSaveSnapshot(data))
    expect(restored.ChariotTeam.Assignments['1']).to.equal('owned')near(restored.Economy.Balance,123.25)near(restored.Base.Slots['1'].accumulatedCash,9.75)
   end)
  end
  it('does not reinterpret an explicit malformed effect as the legacy assignment',function()
   local def=table.clone(Catalog.Get('BRT_001'))def.chariotEffect=false
   local raw=Rules.Individual(def)expect(raw.valid).to.equal(false)expect(raw.issue).to.equal('EFFECT_DEFINITION_INVALID')
  end)
  it('preserves existing Speed and Hit numerical acceptance fixtures',function()
   local function ordinary(id,species)return {individualId=id,speciesId=species,definition=Catalog.Get(species)}end
   local speed=Rules.Calculate({ordinary('vaca','BRT_032'),ordinary('shark','BRT_027'),provider('shield')})
   near(speed.speedBonus,.0772)expect(speed.shieldCapacity).to.equal(1)
   for _,case in {{1,3},{2,4.8},{3,5}}do local entries={}for i=1,case[1]do entries[i]=ordinary('secret'..i,'BRT_035')end
    local stats=Rules.Calculate(entries)near(stats.hitMultiplier,case[2])expect(stats.shieldCapacity).to.equal(0)
   end
  end)
 end)
end
