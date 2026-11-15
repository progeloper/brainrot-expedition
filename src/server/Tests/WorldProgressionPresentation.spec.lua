--!nocheck
return function()
	local Config=require(game.ReplicatedStorage.Shared.Config.WorldProgression)
	local View=require(game.ReplicatedStorage.Shared.Utility.WorldProgressionPresentation)
	local function summary(key,wallet,code)
		local definition=Config.ByKey[key]
		return {ready=true,personalUnlocks={},gates={[key]={code=code or "Eligible",eligible=code==nil,
			wallet=wallet,shortfall=math.max(0,definition.price-wallet),
			branchA={count=0,required=definition.branchA[2],rarity=definition.branchA[1]},
			branchB=if definition.branchB then {count=2,required=definition.branchB[2],rarity=definition.branchB[1]} else nil}}}
	end
	it("shows exact prices and fractional resulting wallets for every paid region",function()
		for _,definition in Config.Ordered do
			if definition.index<=1 then continue end
			local view=View.Build(definition.key,summary(definition.key,definition.price+.125),true)
			expect(view.action).to.equal("Pay "..View.Exact(definition.price).." & Unlock")
			expect(view.body:find("Your wallet after purchase: 0.125",1,true)~=nil).to.equal(true)
			expect(view.enabled).to.equal(true)
		end
	end)
	it("keeps an underfunded Beach amount distinct from the exact price",function()
		local view=View.Build("Beach",summary("Beach",24999999.99,"InsufficientCash"),false)
		expect(view.body:find("24,999,999.99",1,true)~=nil).to.equal(true)
		expect(view.body:find("Shortfall:",1,true)~=nil).to.equal(true)
		expect(view.enabled).to.equal(false)
	end)
	it("displays both OR branches and the exact predecessor",function()
		local view=View.Build("Swamp",summary("Swamp",200000000,"BankedRequirementMissing"),false)
		expect(view.body:find("Personally unlock Beach first",1,true)~=nil).to.equal(true)
		expect(view.body:find("0 / 1 Rare+",1,true)~=nil).to.equal(true)
		expect(view.body:find("2 / 3 Uncommon+",1,true)~=nil).to.equal(true)
		expect(view.body:find("\n\nOR\n\n",1,true)~=nil).to.equal(true)
	end)
	it("ignores historical guest summaries in personal purchase presentation",function()
		local snapshot=summary("Beach",30000000,"PreviousRegionRequired")
		snapshot.guest={regionId="REGION_BEACH",status="Active"}
		local view=View.Build("Beach",snapshot,false)
		expect(view.body:find("guest",1,true)).to.equal(nil)
		expect(view.body:find("expedition guide",1,true)).to.equal(nil)
		expect(view.enabled).to.equal(false)
	end)
	it("shows loading, pending, unavailable and owned without enabling payment",function()
		expect(View.Build("Beach",nil,false).body).to.equal("Loading your progress…")
		for _,code in {"PurchasePending","RegionUnavailable","AlreadyUnlocked"} do
			expect(View.Build("Beach",summary("Beach",25000000,code),false).enabled).to.equal(false)
		end
	end)
	it("uses a fake clock for the eight-second pending notice without declaring failure",function()
		expect(View.PendingLabel(100,107.999)).to.equal("Saving your unlock…")
		expect(View.PendingLabel(100,108)).to.equal("Still saving your unlock…")
		expect(View.PendingLabel(100,160)).to.equal("Still saving your unlock…")
	end)

	it("does not tell a permanently owned region to pay another shortfall",function()
		local view=View.Build("Beach",summary("Beach",.125,"AlreadyUnlocked"),false)
		expect(view.body:find("Shortfall:",1,true)==nil).to.equal(true)
		expect(view.action).to.equal("Permanently unlocked")
		expect(View.ResultMessage("InsufficientCash")).to.equal("Collect more wallet cash to cover the shortfall.")
	end)

	it("never labels a newly permanent owner as personally locked while a stale guest summary clears",function()
		local snapshot=summary("Beach",0,"AlreadyUnlocked")
		snapshot.personalUnlocks.Beach=true snapshot.guest={regionId="REGION_BEACH",status="Active"}
		local view=View.Build("Beach",snapshot,false)
		expect(view.body:find("Personal region still locked",1,true)).to.equal(nil)
		expect(view.action).to.equal("Permanently unlocked")
	end)

end
