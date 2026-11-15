--!nocheck
return function()
	local RS=game:GetService("ReplicatedStorage")
	local Money=require(RS.Shared.Utility.CurrencyDenomination)
	local Rules=require(RS.Shared.Utility.WorldProgressionRules)
	local Config=require(RS.Shared.Config.WorldProgression)
	local Schema=require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Store=require(script.Parent.Parent.Data.PlayerProfileStore)
	local Catalog=require(RS.Shared.Config.BrainrotCatalog)
	local Upgrades=require(RS.Shared.Config.Upgrades)
	local function legacy(wallet)
		local d=Schema.CreateDefault()
		d.CurrencyVersion,d.WorldProgression=nil,nil
        d.Phase13,d.Commerce=nil,nil
        for i=13,48 do d.Base.Slots[tostring(i)]=nil end
		d.Economy.Balance=wallet
		return d
	end
	local function proof(d,ids)
		for _,id in ids do Rules.AddBankedProof(d,id,"deposit",100) end
	end
	local ready={ready=true,writable=true,currencyConfirmed=true,operational=true}
	it("rejects unsupported fractional precision before monetary mutation", function()
		local amount, reason=Money.Convert(2 ^ 42 + 0.125,1)
		expect(amount).to.equal(nil)
		expect(reason).to.equal("MONETARY_PRECISION_UNSUPPORTED")
		expect(Money.Convert(2 ^ 40 + 0.125,1)).to.equal((2 ^ 40 + 0.125)*1500)
	end)

	describe("Phase 8 monetary migration",function()
		it("converts wallet and every occupied/empty platform once with fractions",function()
			local d=legacy(1000)
			d.Collection.BrainrotInstances.a={speciesId="BRT_011"}
			d.Base.Slots["1"].brainrotId="a"
			for _,slot in d.Base.Slots do slot.accumulatedCash=125.5 end
			d.Settings={fraction=0.125,rank=3}
			local result=assert(Schema.Migrate(d))
			expect(result.CurrencyVersion).to.equal(2)
			expect(result.Economy.Balance).to.equal(1500000)
			for i=1,12 do expect(result.Base.Slots[tostring(i)].accumulatedCash).to.equal(188250) end
            for i=13,48 do expect(result.Base.Slots[tostring(i)].accumulatedCash).to.equal(0) end
			expect(result.Settings.fraction).to.equal(0.125)
			expect(d.Economy.Balance).to.equal(1000)
			local again,_,changed=Schema.Migrate(result)
			expect(again.Economy.Balance).to.equal(1500000)
			expect(changed).to.equal(false)
			expect(Money.Convert(0.125,1)).to.equal(187.5)
		end)
		it("creates denomination 2 defaults without legacy gifts",function()
			local d=Schema.CreateDefault()
			expect(d.CurrencyVersion).to.equal(2)
			expect(d.WorldProgression.LegacyGrantVersion).to.equal(1)
			expect(d.WorldProgression.PersonalUnlocks.Beach).to.equal(nil)
		end)
		it("rejects unsupported currency and bad numbers without mutation",function()
			local d=legacy(0)
			d.CurrencyVersion=3
			local result,reason=Schema.Migrate(d)
			expect(result).to.equal(nil)
			expect(reason).to.equal("UNSUPPORTED_CURRENCY_VERSION")
			for _,value in {-1,math.huge,0/0,Money.MAX_AMOUNT} do
				expect(Money.Convert(value,1)).to.equal(nil)
			end
		end)
		it("publishes authoritative source prices and rates in final units once",function()
			expect(math.abs(Catalog.Get("BRT_019").cashPerSecond - 10800000) < 1e-8).to.equal(true)
			expect(Catalog.Get("BRT_019").sellValue).to.equal(324000000)
			expect(Upgrades.Get("CART_SPEED_1").price).to.equal(500000000)
			expect(Upgrades.Get("CARGO_1").price).to.equal(1500000000)
			expect(Upgrades.Get("CARGO_2").releaseStatus).to.equal("Released")
			expect(Config.ByKey.Beach.price).to.equal(4000000000)
		end)
		it("persists migration through the actual store acquisition transform",function()
			local raw={Transport={Version=1,LeaseExpiresAt=0,LastRevision=0},Data=legacy(20000)}
			raw.Data.Collection.BrainrotInstances.a={speciesId="BRT_011"}
			local backend={UpdateAsync=function(_,_,transform) raw=transform(raw,nil) return raw end}
			local owner=Store.new({DataStore=backend,Available=true,UnixNow=function() return 10 end})
			local result=owner:Acquire("fixture","token",180)
			expect(result.ok).to.equal(true)
			expect(raw.Data.CurrencyVersion).to.equal(2)
			expect(raw.Data.Economy.Balance).to.equal(30000000)
			expect(raw.Data.WorldProgression.PersonalUnlocks.Beach.source).to.equal("legacy_progress")
			local reload=owner:Acquire("fixture","token",180)
			expect(reload.data.Economy.Balance).to.equal(30000000)
		end)
		it("does not confirm failed or ambiguous acquisition; retries never multiply twice",function()
			local raw={Transport={Version=1,LeaseExpiresAt=0,LastRevision=0},Data=legacy(1000)}
			local fail=true
			local backend={UpdateAsync=function(_,_,transform)
				if fail then error("definite before transform") end
				raw=transform(raw,nil)
				if fail==nil then fail=false error("response lost after commit") end
				return raw
			end}
			local owner=Store.new({DataStore=backend,Available=true,UnixNow=function() return 10 end})
			expect(owner:Acquire("fixture","token",180).ok).to.equal(false)
			expect(raw.Data.Economy.Balance).to.equal(1000)
			fail=nil
			expect(owner:Acquire("fixture","token",180).ok).to.equal(false)
			expect(raw.Data.CurrencyVersion).to.equal(2)
			expect(owner:Acquire("fixture","token",180).data.Economy.Balance).to.equal(1500000)
		end)
	end)
	it("upgrades the writer fence atomically and refuses currency downgrade saves", function()
		local raw={Transport={Version=1,LeaseExpiresAt=0,LastRevision=0},Data=legacy(1000)}
		local backend={UpdateAsync=function(_,_,transform) raw=transform(raw,nil) return raw end}
		local owner=Store.new({DataStore=backend,Available=true,UnixNow=function() return 10 end})
		local acquired=owner:Acquire("fixture","token",180)
		expect(acquired.ok).to.equal(true)
		expect(raw.Transport.Version).to.equal(3)
		expect(raw.Data.CurrencyVersion).to.equal(2)
		-- The old adapter's exact Version==1 guard rejects this entire envelope.
		expect(raw.Transport.Version==1).to.equal(false)
		local bad=Schema.CreateDefault() bad.CurrencyVersion=1 bad.Economy.Balance=1
		expect(owner:Save("fixture","token","downgrade",1,bad,180).code).to.equal("UNSUPPORTED_WRITE_CURRENCY")
		expect(raw.Data.Economy.Balance).to.equal(1500000)
		expect(raw.Transport.LastRevision).to.equal(0)
	end)

	describe("Historical banking and no-charge legacy grants",function()
		it("deduplicates species and excludes Secret",function()
			local d=Schema.CreateDefault()
			for _=1,10 do Rules.AddBankedProof(d,"BRT-011","deposit",100) end
			Rules.AddBankedProof(d,"BRT_035","deposit",100)
			expect(Rules.Count(d).Uncommon).to.equal(1)
			expect(Rules.Count(d).Mythic).to.equal(0)
			proof(d,{"BRT_026"})
			expect(Rules.Count(d).Epic).to.equal(1)
			expect(Rules.Count(d).Rare).to.equal(1)
		end)
		for _,case in {
			{20000,{"BRT_011"},2}, {500000,{"BRT_026"},4},
			{8000000,{"BRT_026","BRT_027","BRT_028","BRT_029"},7},
			{8000000,{"BRT_001"},1},
		} do
			it("grants the verified consecutive prefix without debit at legacy wallet "..case[1],function()
				local d=legacy(case[1])
				for i,id in case[2] do d.Collection.BrainrotInstances[tostring(i)]={speciesId=id} end
				local converted=assert(Schema.Migrate(d))
				expect(Rules.Highest(converted)).to.equal(case[3])
				expect(converted.Economy.Balance).to.equal(case[1]*1500)
				converted.Economy.Balance=12000000000
				local again=assert(Schema.Migrate(converted))
				expect(Rules.Highest(again)).to.equal(case[3])
			end)
		end
		it("does not infer proof from discovery or blank slots",function()
			local d=legacy(8000000)
			d.Collection.Seen={BRT_026=true}
			d.Base.Slots["1"].accumulatedCash=125.5
			local converted=assert(Schema.Migrate(d))
			expect(Rules.Count(converted).Epic).to.equal(0)
			expect(Rules.Highest(converted)).to.equal(1)
		end)
	end)
	it("preserves historical ordinary rarity when canonicalizing a banked alias", function()
		local d=Schema.CreateDefault()
		d.WorldProgression.BankedSpecies["BRT-011"]={rarityAtFirstBank="Rare",source="legacy_bank_record",firstBankedAt=10}
		d.Collection.BrainrotInstances.a={speciesId="BRT_011"}
		local migrated=assert(Schema.Migrate(d))
		expect(migrated.WorldProgression.BankedSpecies.BRT_011.rarityAtFirstBank).to.equal("Rare")
		expect(migrated.WorldProgression.BankedSpecies.BRT_011.firstBankedAt).to.equal(10)
		expect(migrated.WorldProgression.BankedSpecies["BRT-011"]).to.equal(nil)
		expect(Rules.Count(migrated).Rare).to.equal(1)
		expect(Rules.Count(migrated).Uncommon).to.equal(1)
	end)
	it("retains removed species historical rarity but never invents unknown banking rarity", function()
		local d=Schema.CreateDefault()
		d.WorldProgression.BankedSpecies.BRT_999={rarityAtFirstBank="Epic",source="legacy_bank_record"}
		d.Collection.BrainrotInstances.unknown={speciesId="BRT_998"}
		local migrated=assert(Schema.Migrate(d))
		expect(Rules.Count(migrated).Epic).to.equal(1)
		expect(migrated.WorldProgression.BankedSpecies.BRT_998).to.equal(nil)
		expect(migrated.Collection.BrainrotInstances.unknown.speciesId).to.equal("BRT_998")
	end)

	describe("Exact gate OR requirements",function()
		for _,definition in Config.Ordered do
			if definition.index<=1 then continue end
			it(definition.key.." uses exact affordability and fractional arithmetic",function()
				local d=Schema.CreateDefault()
				for _,earlier in Config.Ordered do
					if earlier.index<definition.index then d.WorldProgression.PersonalUnlocks[earlier.key]={source="purchase"} end
				end
				proof(d,{"BRT_026","BRT_027","BRT_028","BRT_029"})
				d.Economy.Balance=definition.price-0.01
				expect(Rules.Evaluate(d,definition.key,ready).code).to.equal("InsufficientCash")
				d.Economy.Balance=definition.price
				expect(Rules.Evaluate(d,definition.key,ready).eligible).to.equal(true)
				d.Economy.Balance+=0.125
				expect(d.Economy.Balance-definition.price).to.equal(0.125)
			end)
		end
		it("allows Swamp either through one Rare or three distinct Uncommons",function()
			local d=Schema.CreateDefault()
			d.WorldProgression.PersonalUnlocks.Beach={source="purchase"}
			d.Economy.Balance=60000000000
			proof(d,{"BRT_011","BRT_012"})
			expect(Rules.Evaluate(d,"Swamp",ready).eligible).to.equal(false)
			proof(d,{"BRT_013"})
			expect(Rules.Evaluate(d,"Swamp",ready).eligible).to.equal(true)
			d.WorldProgression.BankedSpecies={}
			proof(d,{"BRT_019"})
			expect(Rules.Evaluate(d,"Swamp",ready).eligible).to.equal(true)
		end)
		it("does not count one Legendary as two Epics or temporary predecessor access",function()
			local d=Schema.CreateDefault()
			proof(d,{"BRT_031"})
			expect(Rules.Banking(d,Config.ByKey.Arctic).passed).to.equal(false)
			d.Economy.Balance=60000000000
			expect(Rules.Evaluate(d,"Swamp",ready).code).to.equal("PreviousRegionRequired")
		end)
	end)
end
