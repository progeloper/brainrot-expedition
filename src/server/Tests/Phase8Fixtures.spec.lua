--!nocheck
return function()
 local Fixtures=require(script.Parent.Support.ProgressionProfileFixtures)
 local Rules=require(game.ReplicatedStorage.Shared.Utility.WorldProgressionRules)
 local Config=require(game.ReplicatedStorage.Shared.Config.WorldProgression)
 local Schema=require(script.Parent.Parent.Data.PlayerProfileSchema)
 local context={ready=true,writable=true,currencyConfirmed=true,operational=true}
 it("provides isolated schema-compatible exact and fractional cases for every gate and both alternatives",function()
  for _,definition in Config.Ordered do
   if definition.index<=1 then continue end
   for _,branch in (if definition.branchB then {"A","B"} else {"A"}) do
    local exact=Fixtures.CreateGate(definition.key,branch,"Exact")
    expect(Schema.ValidateLoaded(exact)).to.equal(true)
    expect(exact.CurrencyVersion).to.equal(2)
    expect(exact.Economy.Balance).to.equal(definition.price)
    expect(Rules.Evaluate(exact,definition.key,context).eligible).to.equal(true)
    expect(Fixtures.CreateGate(definition.key,branch,"Fractional").Economy.Balance-definition.price).to.equal(.125)
    expect(next(exact.Collection.BrainrotInstances)).to.equal(nil)
   end
  end
 end)
 it("provides separate missing-cash and missing-proof failures without changing prices or inventing occupants",function()
  for _,definition in Config.Ordered do
   if definition.index<=1 then continue end
   expect(Rules.Evaluate(Fixtures.CreateGate(definition.key,"A","Underfunded"),definition.key,context).code).to.equal("InsufficientCash")
   expect(Rules.Evaluate(Fixtures.CreateGate(definition.key,"A","MissingProof"),definition.key,context).code).to.equal("BankedRequirementMissing")
   expect(Rules.Evaluate(Fixtures.CreateGate(definition.key,"A","Owned"),definition.key,context).code).to.equal("AlreadyUnlocked")
   if definition.index>2 then
    expect(Rules.Evaluate(Fixtures.CreateGate(definition.key,"A","MissingPredecessor"),definition.key,context).code).to.equal("PreviousRegionRequired")
   end
  end
 end)
 it("rejects unknown regions, unavailable branches and an impossible missing starter prerequisite fixture",function()
  expect(pcall(Fixtures.CreateGate,"glitch","B","Exact")).to.equal(false)
  expect(pcall(Fixtures.CreateGate,"Beach","B","Exact")).to.equal(false)
  expect(pcall(Fixtures.CreateGate,"Beach","A","MissingPredecessor")).to.equal(false)
 end)
end
