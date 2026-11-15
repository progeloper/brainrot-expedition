--!nocheck
return function()
	local Config=require(game.ReplicatedStorage.Shared.Config.WorldProgression)
	local Quota=require(game.ReplicatedStorage.Shared.Utility.WorldPopulationQuota)
	local all={}
	for _,definition in Config.Ordered do if definition.index>=1 then all[definition.regionId]=true end end
	it("allocates only Forest for twelve new ready players",function()
		local players={} for id=1,12 do table.insert(players,{userId=id,ready=true,highestIndex=1}) end
		local result=Quota.Allocate(players,all)
		expect(result.quotas.REGION_FOREST).to.equal(42) expect(result.quotas.REGION_BEACH).to.equal(nil)
	end)
	it("allocates the exact one-highest-Beach example",function()
		local result=Quota.Allocate({{ready=true,highestIndex=2}},all)
		expect(result.quotas.REGION_FOREST).to.equal(14) expect(result.quotas.REGION_BEACH).to.equal(28)
	end)
	it("uses the required largest-remainder tie order for highest Glitch",function()
		local result=Quota.Allocate({{ready=true,highestIndex=7}},all)
		for id,count in {REGION_FOREST=6,REGION_BEACH=6,REGION_SWAMP=5,REGION_JUNGLE=5,REGION_ARCTIC=5,REGION_VOLCANO=5,REGION_GLITCH=10} do
			expect(result.quotas[id]).to.equal(count)
		end
	end)
	it("pauses with no ready players and ignores loading profiles",function()
		expect(Quota.Allocate({},all).total).to.equal(0)
		expect(Quota.Allocate({{ready=false,highestIndex=7}},all).total).to.equal(0)
	end)
	it("never allocates a configured but nonoperational region",function()
		local result=Quota.Allocate({{ready=true,highestIndex=7}},{REGION_FOREST=true,REGION_BEACH=true})
		expect(result.quotas.REGION_SWAMP).to.equal(nil) expect(result.total).to.equal(42)
	end)
	it("ignores former guest claims while deduplicating real progressed players",function()
		local result=Quota.Allocate({{userId=1,ready=true,highestIndex=2},{userId=2,ready=true,highestIndex=1,guestRegionId="REGION_BEACH"},
			{userId=2,ready=true,highestIndex=1,guestRegionId="REGION_BEACH"}},all)
		expect(result.weights.REGION_FOREST).to.equal(2) expect(result.weights.REGION_BEACH).to.equal(2)
		expect(result.total).to.equal(42)
		local unqualified=Quota.Allocate({{userId=2,ready=true,highestIndex=1,guestRegionId="REGION_BEACH"}},all)
		expect(unqualified.quotas.REGION_BEACH).to.equal(nil)
		expect(unqualified.quotas.REGION_FOREST).to.equal(42)
	end)

	it("keeps every allocation at the one global target",function()
		for highest=1,7 do
			local result=Quota.Allocate({{ready=true,highestIndex=highest}},all)
			local total=0 for _,value in result.quotas do total+=value end expect(total).to.equal(42)
		end
	end)
end
