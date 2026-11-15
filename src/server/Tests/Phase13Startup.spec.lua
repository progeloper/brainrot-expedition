--!nocheck
return function()
 local System=require(script.Parent.Parent.Systems.BaseIncomePlaqueSystem)
 it("yields only between startup base batches and keeps Start idempotent",function()
  local original=System.BuildBase
  for _,count in {1,12}do
   System:Destroy()
   local bases={} local builds,yields=0,0
   for i=1,count do local b=Instance.new("Model");b:SetAttribute("OwnerUserId",0);table.insert(bases,b)end
   System.BuildBase=function(_,base,owner)builds+=1;assert(base==bases[builds]);assert(owner==0);return true end
   local deps={Base={GetRegisteredBases=function()return bases end,SubscribeAssignments=function()return {Disconnect=function()end}end},Storage={ObserveStorage=function()return function()end end},Income={},YieldSetup=function()yields+=1;assert(builds==yields,"yield inside a partial base")end,ConnectSnapshotRefresh=false}
   local ok,why=pcall(function()
    assert(System:Init(deps));assert(System:Start());assert(builds==count);assert(yields==count-1)
    assert(System:Start()==false);assert(builds==count);assert(yields==count-1)
   end)
   System:Destroy();for _,b in bases do b:Destroy()end;System.BuildBase=original
   assert(ok,why)
  end
 end)
end
