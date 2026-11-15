--!nocheck
return function()
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Service = require(script.Parent.Parent.Services.WorldProgressionService)
	local Rules = require(game:GetService("ReplicatedStorage").Shared.Utility.WorldProgressionRules)
	local function fixture()
		local player = {UserId = 42}
		local data = Schema.CreateDefault()
		data.Economy.Balance = 4005000000.125
		Rules.AddBankedProof(data, "BRT_011", "deposit", 100)
		local now, revision, saves, confirmed = 10, 0, 0, {}
		local profile = {}
		function profile:GetWritableData() return data end
		function profile:GetReadableData() return data end
		function profile:IsWritable() return true end
		function profile:GetSessionHandle() return {Generation = 1} end
		function profile:IsCurrentSessionHandle(handle) return handle.Generation == 1 end
		function profile:SubscribeSaveConfirmed(callback)
			self.confirm = callback
			return {Disconnect = function() self.confirm = nil end}
		end
		function profile:CommitMutation(_, callback)
			local snapshot = assert(Schema.CreateSaveSnapshot(data))
			local ok, result = callback(data)
			if not ok then data = snapshot return result end
			revision += 1
			return {ok = true, revision = revision}
		end
		function profile:RequestSave() saves += 1 end
		local context = {ready = true, writable = true, currencyConfirmed = true, operational = true}
		local failure
		local service = Service.new({Profile = profile, Now = function() return now end,
			OperationId = function() return "fixture-operation" end, UnixNow = function() return 100 end,
			ValidateGateContext = function() return if failure then nil else context, failure end,
			OnResult = function(_, result) table.insert(confirmed, result) end})
		return {player = player, service = service, profile = profile, data = function() return data end,
			advance = function() now += 1 end, fail = function(code) failure = code end,
			saves = function() return saves end, confirmed = confirmed}
	end
	local request = {regionKey = "Beach", requestId = "first"}
	it("debits once coherently and withholds runtime access until a covering save", function()
		local f = fixture()
		expect(f.service:Request(f.player, request).state).to.equal("PendingCommit")
		expect(f.data().Economy.Balance).to.equal(5000000.125)
		expect(f.data().WorldProgression.PersonalUnlocks.Beach.pricePaid).to.equal(4000000000)
		expect(f.service:GetPersonalAccess(f.player, "REGION_BEACH")).to.equal(false)
		f.profile.confirm(f.player, 0)
		expect(#f.confirmed).to.equal(0)
		f.profile.confirm(f.player, 1)
		expect(f.service:GetPersonalAccess(f.player, "REGION_BEACH")).to.equal(true)
		expect(#f.confirmed).to.equal(1)
		f.profile.confirm(f.player, 1)
		expect(#f.confirmed).to.equal(1)
	end)
	it("retries the same identity and blocks a second pending request without another debit", function()
		local f = fixture()
		f.service:Request(f.player, request)
		for _ = 1, 10 do expect(f.service:Request(f.player, request).code).to.equal("PurchasePending") end
		expect(f.service:Request(f.player, {regionKey = "Swamp", requestId = "second"}).code).to.equal("PurchasePending")
		expect(f.data().Economy.Balance).to.equal(5000000.125)
		expect(f.saves()).to.equal(1)
		f.profile.confirm(f.player, 1)
		expect(f.service:Request(f.player, request).code).to.equal("Success")
		f.advance()
		expect(f.service:Request(f.player, {regionKey = "Beach", requestId = "owned"}).code).to.equal("AlreadyUnlocked")
		expect(f.data().Economy.Balance).to.equal(5000000.125)
	end)
	it("preserves collection and sale money received during an ambiguous save", function()
		local f = fixture()
		f.service:Request(f.player, request)
		f.profile:CommitMutation(f.player, function(data)
			data.Economy.Balance += 188250 + 972000
			return true
		end)
		expect(f.service:GetPersonalAccess(f.player, "REGION_BEACH")).to.equal(false)
		f.profile.confirm(f.player, 2)
		expect(f.data().Economy.Balance).to.equal(6160250.125)
		expect(f.confirmed[1].wallet).to.equal(6160250.125)
	end)
	it("rejects additional authoritative fields and malformed request identities", function()
		local f = fixture()
		for _, payload in {false, {regionKey = "Beach", requestId = ""},
			{regionKey = "Beach", requestId = string.rep("x", 65)},
			{regionKey = "Beach", requestId = "x", price = 0},
			{regionKey = {}, requestId = "x"}} do
			expect(f.service:Request(f.player, payload).code).to.equal("InvalidRequest")
		end
		expect(f.saves()).to.equal(0)
		expect(f.data().Economy.Balance).to.equal(4005000000.125)
	end)
	it("denies an underfunded wallet without collecting platform money", function()
		local f = fixture()
		f.data().Economy.Balance = 3999999999.99
		f.data().Base.Slots["1"].accumulatedCash = 10000000
		expect(f.service:Request(f.player, request).code).to.equal("InsufficientCash")
		expect(f.data().Base.Slots["1"].accumulatedCash).to.equal(10000000)
		expect(f.data().WorldProgression.PersonalUnlocks.Beach).to.equal(nil)
	end)
	it("preserves fractional excess and exact-price zero through the mutation adapter", function()
		for _, extra in {0, 0.125} do
			local f = fixture()
			f.data().Economy.Balance = 4000000000 + extra
			f.service:Request(f.player, request)
			expect(f.data().Economy.Balance).to.equal(extra)
			f.profile.confirm(f.player, 1)
			expect(f.service:GetPersonalAccess(f.player, "REGION_BEACH")).to.equal(true)
		end
	end)
	it("rechecks a concurrent legitimate spend at the serialized commit", function()
		local f = fixture()
		local original = f.profile.CommitMutation
		function f.profile:CommitMutation(player, callback)
			f.data().Economy.Balance = 3999999999.99
			return original(self, player, callback)
		end
		expect(f.service:Request(f.player, request).code).to.equal("InsufficientCash")
		expect(f.data().WorldProgression.PersonalUnlocks.Beach).to.equal(nil)
		expect(f.saves()).to.equal(0)
	end)
	it("rejects far or unavailable character contexts and rate limits new attempts", function()
		local f = fixture()
		f.fail("TooFarFromGate")
		expect(f.service:Request(f.player, request).code).to.equal("TooFarFromGate")
		expect(f.service:Request(f.player, {regionKey = "Beach", requestId = "next"}).code).to.equal("RateLimited")
		expect(f.saves()).to.equal(0)
	end)
	it("does not confirm an operation from a replaced profile session", function()
		local f = fixture()
		f.service:Request(f.player, request)
		function f.profile:IsCurrentSessionHandle() return false end
		f.profile.confirm(f.player, 1)
		expect(#f.confirmed).to.equal(0)
		expect(f.service:GetPersonalAccess(f.player, "REGION_BEACH")).to.equal(false)
	end)
	it("does not advertise pending access or permit it to sponsor an expedition", function()
		local f = fixture()
		local context = function() return {ready=true, writable=true, currencyConfirmed=true, operational=true} end
		f.service:Request(f.player, request)
		expect(f.service:GetHighestPersonalIndex(f.player)).to.equal(1)
		local summary = f.service:GetSummary(f.player, context)
		expect(summary.personalUnlocks.Beach).to.equal(nil)
		expect(summary.gates.Beach.code).to.equal("PurchasePending")
		expect(summary.gates.Beach.alreadyPersonallyUnlocked).to.equal(false)
		expect(summary.gates.Swamp.code).to.equal("PreviousRegionRequired")
		expect(summary.BankedSpecies).to.equal(nil)
		f.profile.confirm(f.player, 1)
		expect(f.service:GetHighestPersonalIndex(f.player)).to.equal(2)
		expect(f.service:GetSummary(f.player, context).personalUnlocks.Beach).to.equal(true)
	end)

	it("emits one coherent debit observation and one confirmed milestone for duplicate requests",function()
		local f=fixture() local events={}
		f.service.onEvent=function(name,fields) table.insert(events,{name=name,fields=fields}) end
		f.service:Request(f.player,request)
		for _=1,10 do f.service:Request(f.player,request) end
		local commits,successes=0,0
		for _,event in events do
			if event.name=="GatePurchaseCommitted" then commits+=1 expect(event.fields.price).to.equal(4000000000) expect(event.fields.wallet).to.equal(5000000.125) end
			if event.name=="GatePurchaseConfirmed" then successes+=1 end
		end
		expect(commits).to.equal(1) expect(successes).to.equal(0)
		f.profile.confirm(f.player,1) f.profile.confirm(f.player,1)
		for _,event in events do if event.name=="GatePurchaseConfirmed" then successes+=1 end end
		expect(successes).to.equal(1) expect(f.data().Economy.Balance).to.equal(5000000.125)
	end)
	it("cannot break payment or confirmation when an observation listener fails",function()
		local f=fixture() f.service.onEvent=function() error("diagnostic fixture failure") end
		expect(f.service:Request(f.player,request).state).to.equal("PendingCommit")
		f.profile.confirm(f.player,1)
		expect(f.service:GetPersonalAccess(f.player,"REGION_BEACH")).to.equal(true)
		expect(f.data().Economy.Balance).to.equal(5000000.125)
	end)
	it("records banking and cash eligibility only when first observed and bounds rejected-request notices",function()
		local f=fixture() local counts={}
		f.service.onEvent=function(name) counts[name]=(counts[name] or 0)+1 end
		local function context() return {ready=true,writable=true,currencyConfirmed=true,operational=true} end
		f.service:GetSummary(f.player,context) f.service:GetSummary(f.player,context)
		expect(counts.BankingRequirementEligible).to.equal(1) expect(counts.CashRequirementEligible).to.equal(1)
		for _=1,100 do f.service:Request(f.player,{badField=true}) end
		expect(counts.GatePurchaseRejected).to.equal(1) expect(f.data().Economy.Balance).to.equal(4005000000.125)
	end)

	it("caches summary counts while keeping commit qualification authoritative",function()
		local f=fixture()
		local function context() return {ready=true,writable=true,currencyConfirmed=true,operational=true} end
		local first=f.service:GetSummary(f.player,context)
		local cached=f.service.requirementCounts[f.player].counts
		f.data().Economy.Balance+=1
		f.service:GetSummary(f.player,context)
		expect(f.service.requirementCounts[f.player].counts).to.equal(cached)
		first.counts.Uncommon=999
		expect(cached.Uncommon).to.equal(1)
		f.data().WorldProgression.BankedSpecies={}
		expect(f.service:Request(f.player,request).code).to.equal("BankedRequirementMissing")
		f.service:InvalidateRequirements(f.player)
		expect(f.service:GetSummary(f.player,context).counts.Uncommon).to.equal(0)
	end)

end
