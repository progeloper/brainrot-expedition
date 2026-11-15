--!nocheck
-- Actual profile owner and currency service, with only its storage transport fake.
return function()
	local Players=game:GetService("Players")
	local Profile=require(script.Parent.Parent.Services.PlayerDataService)
	local Service=require(script.Parent.Parent.Services.WorldProgressionService)
	local Schema=require(script.Parent.Parent.Data.PlayerProfileSchema)
	local FakeBackend=require(script.Parent.Support.FakePlayerProfileBackend)
	local Rules=require(game.ReplicatedStorage.Shared.Utility.WorldProgressionRules)
	local function harness(callback, options)
		Profile:_ResetForTests()
		local now=1000
		local data=Schema.CreateDefault()
		data.Economy.Balance=4000000000.125
		Rules.AddBankedProof(data,"BRT_011","deposit",100)
		local key="player_84621"
		local backend=FakeBackend.new({Now=function() return now end,
			Records={[key]={Data=data,OwnerToken=nil,LeaseExpiresAt=0,LastRevision=0}},
			FailBeforeSaveCount=options and options.failCount or 0})
		local player={UserId=84621,Name="Phase8Fixture",Parent=Players}
		function player:SetAttribute() end function player:Kick() end
		Profile:Init({Backend=backend,UnixNow=function() return now end,MonotonicNow=function() return now end,
			Wait=function(seconds) now+=seconds end,Random=function() return 0 end,KickOnFailure=false})
		assert(Profile:LoadPlayerAsync(player).ok, "Real profile fixture failed to acquire")
		local originalRequestSave=Profile.RequestSave
		Profile.RequestSave=function() return {ok=true,code="DEFERRED_FIXTURE"} end
		local service=Service.new({Profile=Profile,Now=function() return now end,
			ValidateGateContext=function()
				return {ready=Profile:GetStatus(player)=="Ready",writable=Profile:IsWritable(player),
					currencyConfirmed=true,operational=true}
			end})
		local ok,failure=xpcall(function() callback(service,player,backend,key,function(seconds) now+=seconds end) end,debug.traceback)
		service:Destroy()
		Profile.RequestSave=originalRequestSave
		Profile:_ResetForTests()
		assert(ok,failure)
	end
	it("uses the real serialized profile mutex and confirms its exact saved revision",function()
		harness(function(service,player,backend,key)
			local result=service:Request(player,{regionKey="Beach",requestId="first"})
			expect(result.code).to.equal("PurchasePending")
			expect(Profile:GetReadableData(player).Economy.Balance).to.equal(.125)
			expect(service:GetPersonalAccess(player,"REGION_BEACH")).to.equal(false)
			expect(backend.Records[key].Data.Economy.Balance).to.equal(4000000000.125)
			expect(Profile:SaveNowAsync(player,"fixture-confirm").ok).to.equal(true)
			expect(service:GetPersonalAccess(player,"REGION_BEACH")).to.equal(true)
			expect(backend.Records[key].Data.Economy.Balance).to.equal(.125)
			expect(backend.Records[key].Data.WorldProgression.PersonalUnlocks.Beach.pricePaid).to.equal(4000000000)
		end)
	end)
	it("preserves later legitimate wallet mutations in the real pending-save snapshot",function()
		harness(function(service,player,backend,key)
			service:Request(player,{regionKey="Beach",requestId="first"})
			expect(Profile:CommitMutation(player,function(data)
				data.Economy.Balance+=188250+972000
				return true
			end).ok).to.equal(true)
			expect(Profile:SaveNowAsync(player,"fixture-collect-sale").ok).to.equal(true)
			expect(backend.Records[key].Data.Economy.Balance).to.equal(1160250.125)
			expect(service:GetPersonalAccess(player,"REGION_BEACH")).to.equal(true)
		end)
	end)
	it("withholds access across a failed real save batch and reconciles without a second debit",function()
		harness(function(service,player,backend,key)
			service:Request(player,{regionKey="Beach",requestId="first"})
			expect(Profile:SaveNowAsync(player,"fixture-failure").ok).to.equal(false)
			expect(service:GetPersonalAccess(player,"REGION_BEACH")).to.equal(false)
			expect(backend.Records[key].Data.Economy.Balance).to.equal(4000000000.125)
			expect(service:Request(player,{regionKey="Beach",requestId="first"}).code).to.equal("PurchasePending")
			expect(Profile:SaveNowAsync(player,"fixture-reconcile").ok).to.equal(true)
			expect(backend.Records[key].Data.Economy.Balance).to.equal(.125)
			expect(service:GetPersonalAccess(player,"REGION_BEACH")).to.equal(true)
		end,{failCount=5})
	end)
end
