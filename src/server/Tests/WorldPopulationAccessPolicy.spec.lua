--!nocheck
return function()
	local Policy=require(script.Parent.Parent.Utility.WorldPopulationAccessPolicy)
	local Validator=require(script.Parent.Parent.Utility.WorldPoolValidator)
	local function fixture()
		local a,b={UserId=1},{UserId=2}
		local players={a} local highest={[a]=1,[b]=1}
		local states={[a]={ready=true,alive=true,regionId="REGION_FOREST"},[b]={ready=true,alive=true,regionId="REGION_FOREST"}}
		local guests={} local now,requests=0,0
		local policy=Policy.new({Progression={GetHighestPersonalIndex=function(_,p) return highest[p] end},
			Access={IsOperational=function(_,id) return id=="REGION_FOREST" or id=="REGION_BEACH" end},
			GetPlayers=function() return players end,GetPlayerState=function(p) return states[p] end,Now=function() return now end,
			Compilation=Validator.Validate({ValidateModel=function() return true end}),
			Spawner={RequestPopulationReconcile=function() requests+=1 end}})
		return {policy=policy,a=a,b=b,highest=highest,states=states,guests=guests,
			setPlayers=function(list) players=list end,advance=function(n) now+=n end,requests=function() return requests end}
	end
	it("debounces changed access and does not reschedule unchanged allocations",function()
		local f=fixture() expect(f.policy:Step()).to.equal(true)
		expect(f.policy:GetQuota("REGION_FOREST")).to.equal(42)
		f.highest[f.a]=2 f.advance(.999) expect(f.policy:Step()).to.equal(false)
		f.advance(.001) expect(f.policy:Step()).to.equal(true)
		expect(f.policy:GetQuota("REGION_FOREST")).to.equal(14) expect(f.policy:GetQuota("REGION_BEACH")).to.equal(28)
		f.advance(1) expect(f.policy:Step()).to.equal(false) expect(f.requests()).to.equal(2)
	end)
	it("chooses the largest real deficit including outstanding reservations",function()
		local f=fixture() f.highest[f.a]=2 f.policy:Step()
		local id=f.policy:ChooseRegion({ByRegion={REGION_FOREST=14},ReservedByRegion={REGION_BEACH=27}}, {})
		expect(id).to.equal("REGION_BEACH")
		expect(f.policy:ChooseRegion({ByRegion={REGION_FOREST=14,REGION_BEACH=28},ReservedByRegion={}},{})).to.equal(nil)
	end)
	it("pauses immediately on the last departure even before the quota debounce",function()
		local f=fixture() f.policy:Step() f.setPlayers({})
		expect(f.policy:GetQuota("REGION_FOREST")).to.equal(0)
		expect(f.policy:SelectSpecies("REGION_FOREST",{}).status).to.equal("NO_ELIGIBLE_SPECIES_NOW")
		expect(f.policy:ChooseRegion({ByRegion={},ReservedByRegion={}},{})).to.equal(nil)
	end)
	it("aggregates independent personal progress and ignores former guest state",function()
		local f=fixture() f.highest[f.a]=2 f.setPlayers({f.a,f.b})
		f.guests[f.b]={regionId="REGION_BEACH",status="Active"}
		f.policy:Step() expect(f.policy.weights.REGION_BEACH).to.equal(2)
		f.states[f.b].regionId="REGION_BEACH" f.advance(1)
		expect(f.policy:Step()).to.equal(false)
		expect(f.policy.weights.REGION_BEACH).to.equal(2)
		f.setPlayers({f.b}) f.advance(1) f.policy:Step()
		expect(f.policy:GetQuota("REGION_BEACH")).to.equal(0)
		expect(f.policy:GetQuota("REGION_FOREST")).to.equal(42)
	end)

	it("uses the exact compiled pool and respects temporary cap exclusions",function()
		local f=fixture() f.policy:Step()
		local blocked={} for id=1,19 do blocked[string.format("BRT_%03d",id)]="CAP" end
		expect(f.policy:SelectSpecies("REGION_FOREST",{blockedSpecies=blocked}).status).to.equal("NO_ELIGIBLE_SPECIES_NOW")
		expect(f.policy:SelectSpecies("REGION_BEACH",{}).status).to.equal("NO_ELIGIBLE_SPECIES_NOW")
		local result=f.policy:SelectSpecies("REGION_FOREST",{})
		expect(result.status).to.equal("Selected")
		expect(result.tier~="Epic" and result.tier~="Legendary").to.equal(true)
	end)
	it("binds the actual registry without Camp pilots or mutations to existing members",function()
		local World=require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
		World.Stop()
		local before=World.GetPopulationSnapshot()
		local policy={CheckReadiness=function() return true end,GetQuota=function() return 0 end,
			ChooseRegion=function() return nil,"NO_READY_PLAYERS",false end,
			SelectSpecies=function() return {status="NO_ELIGIBLE_SPECIES_NOW"} end}
		local ok,failure=xpcall(function()
			expect(World.ConfigurePopulationAccess(policy)).to.equal(true)
			World.Start()
			local after=World.GetPopulationSnapshot()
			expect(after.Wild).to.equal(before.Wild)
			expect(after.Reserved).to.equal(0)
			expect(World.ValidatePopulationConsistency()).to.equal(true)
		end,debug.traceback)
		World.Stop()
		World.ConfigurePopulationAccess(nil)
		assert(ok,failure)
	end)

end
