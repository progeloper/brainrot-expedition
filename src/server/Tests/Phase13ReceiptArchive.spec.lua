--!nocheck
-- Synthetic records only. No production service or player is acquired.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Http = game:GetService("HttpService")
	local Players = game:GetService("Players")
	local Store = require(script.Parent.Parent.Data.PlayerProfileStore)
	local OldStore = require(script.Parent.Support.PreArchivePlayerProfileStore)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Rules = require(RS.Shared.Utility.Phase13CommerceRules)
	local Capacity = require(RS.Shared.Utility.Phase13CommerceCapacity)
	local Service = require(script.Parent.Parent.Services.Phase13CommerceService)
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local Transactions = require(script.Parent.Parent.Services.Phase13Service)
	local function copy(v) return Capacity.Copy(v) end
	local function equal(a,b)
		if type(a)~=type(b) then return false end
		if type(a)~="table" then return a==b end
		for k,v in a do if not equal(v,b[k]) then return false end end
		for k in b do if a[k]==nil then return false end end
		return true
	end
	local function fixture(count)
		local f = { now=1000, records={}, calls={}, reexecute=true }
		f.key="player_831339"
		local data=Schema.CreateDefault()
		data.Economy.Balance=123.5
		for n=1,count do
			assert(Rules.GrantReceipt(data,string.format("original-%05d",n),101,500000000,1000,"FIXTURE"))
			data.Commerce.ProcessedReceipts[string.format("original-%05d",n)].CommitRevision=n
		end
		f.records[f.key]={Transport={Version=3,OwnerToken="owner-a",LeaseExpiresAt=5000,LastRevision=count,LastOperationId="fixture"},Data=data,RetainedExtension={Sentinel="preserve"}}
		f.original=copy(f.records[f.key])
		function f:GetAsync(key,options)
			assert(options and options.UseCache==false,"Authoritative reads must bypass cache")
			table.insert(self.calls,{kind="Read",key=key})
			if self.failLookup and key:match("^paid1_") then error("synthetic lookup unavailable") end
			return copy(self.records[key]) -- self.cached is intentionally ignored.
		end
		function f:UpdateAsync(key,transform)
			local before=copy(self.records[key])
			local proposed=transform(copy(before))
			if self.reexecute then proposed=transform(copy(before)) end
			local phase=if key:match("^paid1_") then "Copy"
				elseif proposed and before and proposed.Transport.LastRevision>before.Transport.LastRevision then "Publish" else "Fence"
			table.insert(self.calls,{kind=phase,key=key})
			if phase=="Copy" then self.copyIndex=(self.copyIndex or 0)+1 end
			local faultApplies=phase~="Copy" or not self.faultIndex or self.copyIndex==self.faultIndex
			if faultApplies and self.fault==phase.."Before" then self.fault=nil;error("synthetic failure before "..phase) end
			self.records[key]=copy(proposed)
			if self.transferAt==phase then self.transferAt=nil;self.records[self.key].Transport.OwnerToken="owner-b" end
			if faultApplies and self.fault==phase.."After" then self.fault=nil;error("synthetic lost response after "..phase) end
			return copy(self.records[key])
		end
		function f.store(enabled)
			return Store.new({DataStore=f,Available=true,EnablePaidReceiptArchive=enabled~=false,UnixNow=function()return f.now end,ArchiveBudget=function()return f.budget or 1000 end})
		end
		return f
	end
	local function archive(f,token)
		return f.store():ArchivePaidReceipts(f.key,token or "owner-a","archive:"..tostring(f.records[f.key].Transport.LastRevision),f.records[f.key].Transport.LastRevision)
	end
	describe("Permanent paid receipt archive",function()
		it("makes real room at the unchanged 10000-entry limit and preserves original reward and unrelated data",function()
			local f=fixture(10000)
			expect(Capacity.CheckLedger(f.records[f.key].Data,false).ok).to.equal(false)
			local saved=f.records[f.key].Data.Economy.Balance
			local a=archive(f);expect(a.ok).to.equal(true);expect(a.moved).to.equal(8)
			expect(f.records[f.key].Data.Commerce.ReceiptCount).to.equal(9992)
			expect(Capacity.CheckLedger(f.records[f.key].Data,false).ok).to.equal(true)
			expect(f.records[f.key].Data.Economy.Balance).to.equal(saved)
			expect(f.records[f.key].RetainedExtension.Sentinel).to.equal("preserve")
			expect(equal(f.records[f.key].Data.Base,f.original.Data.Base)).to.equal(true)
			local old=f.store():LookupPaidReceipt(f.key,"owner-a","original-00001")
			expect(old.ok).to.equal(true);expect(old.receipt.Amount).to.equal(500000000)
		end)
		it("keeps both paid flags false and normal Transport3 profiles on the old default path",function()
			local config=require(RS.Shared.Config.Phase13Commerce)
			expect(config.ProductionDeliveryEnabled).to.equal(false);expect(config.PaidCapacityRecoveryReady).to.equal(false)
			local f=fixture(3);local a=f.store(false):ArchivePaidReceipts(f.key,"owner-a","disabled",3)
			expect(a.code).to.equal("PAID_ARCHIVE_DISABLED");expect(f.records[f.key].Transport.Version).to.equal(3)
		end)
		it("rejects actual frozen old Save Renew and Release writers after the version fence",function()
			local f=fixture(3);expect(archive(f).ok).to.equal(true)
			local before=copy(f.records[f.key]);local old=OldStore.new({DataStore=f,Available=true,UnixNow=function()return f.now end})
			expect(old:Save(f.key,"owner-a","stale-save",99,f.original.Data,180).ok).to.equal(false)
			expect(old:Renew(f.key,"owner-a","stale-renew",180).ok).to.equal(false)
			expect(old:Release(f.key,"owner-a","stale-release",99,f.original.Data).ok).to.equal(false)
			expect(equal(f.records[f.key],before)).to.equal(true)
		end)
		for _,at in {"FenceBefore","FenceAfter","CopyBefore","CopyAfter","PublishBefore","PublishAfter"} do
			it("recovers interruption at "..at.." with permanent lookup after fresh acquisition",function()
				local f=fixture(12);f.fault=at;expect(archive(f).ok).to.equal(false)
				f.now=6000
				local a=f.store():Acquire(f.key,"owner-b",180)
				expect(a.ok).to.equal(true)
				if f.records[f.key].Transport.Version==3 then expect(archive(f,"owner-b").ok).to.equal(true) end
				local lookup=f.store():LookupPaidReceipt(f.key,"owner-b","original-00001")
				expect(lookup.ok).to.equal(true);expect(lookup.receipt.Amount).to.equal(500000000)
				expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance)
				expect(f.records[f.key].Data.Commerce.ReceiptCount+f.records[f.key].Transport.PaidArchive.Count).to.equal(12)
			end)
		end
		for index=2,8 do for _,edge in {"Before","After"} do
			it("recovers exact durable copy boundary "..index..edge,function()
				local f=fixture(12);f.fault="Copy"..edge;f.faultIndex=index
				expect(archive(f).ok).to.equal(false)
				f.now=6000;expect(f.store():Acquire(f.key,"owner-b",180).ok).to.equal(true)
				for n=1,8 do expect(f.store():LookupPaidReceipt(f.key,"owner-b",string.format("original-%05d",n)).receipt.Amount).to.equal(500000000) end
				expect(f.records[f.key].Data.Commerce.ReceiptCount+f.records[f.key].Transport.PaidArchive.Count).to.equal(12)
				expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance)
			end)
		end end
		it("uses actual encoding below at and over a reduced simulated byte limit including ordinary growth",function()
			local envelope={Transport={Version=4},Data={padding="",ordinary="quoted\"\\value"}}
			local simulatedLimit=32768
			local margin=Capacity.EntryLimitBytes-simulatedLimit
			local budget=simulatedLimit-Capacity.ProjectionGrowthReserveBytes
			local overhead=#Http:JSONEncode(envelope)
			envelope.Data.padding=string.rep("x",budget-overhead-1)
			expect(Capacity.MeasureEnvelope(envelope,margin).ok).to.equal(true)
			envelope.Data.padding..="x";expect(Capacity.MeasureEnvelope(envelope,margin).ok).to.equal(true)
			envelope.Data.ordinary..="x";expect(Capacity.MeasureEnvelope(envelope,margin).ok).to.equal(false)
		end)
		it("retains unsupported historical commit metadata without guessing a grant or moving history",function()
			local f=fixture(3)
			for _,r in f.records[f.key].Data.Commerce.ProcessedReceipts do r.CommitRevision=nil end
			local a=archive(f);expect(a.code).to.equal("PAID_ARCHIVE_NO_CONFIRMED_ROWS")
			expect(f.records[f.key].Transport.Version).to.equal(3)
			expect(f.records[f.key].Data.Commerce.ReceiptCount).to.equal(3)
		end)
		it("defers budget exhaustion without mutation and resumes after budget returns",function()
			local f=fixture(3);f.budget=0
			expect(archive(f).code).to.equal("PAID_ARCHIVE_BUDGET")
			expect(equal(f.records[f.key],f.original)).to.equal(true)
			f.budget=1000;expect(archive(f).ok).to.equal(true)
			expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance)
		end)
		it("does not publish history removal after ownership transfers during copy",function()
			local f=fixture(12);f.transferAt="Copy"
			expect(archive(f).ok).to.equal(false)
			expect(f.records[f.key].Data.Commerce.ReceiptCount).to.equal(12)
			expect(f.store():LookupPaidReceipt(f.key,"owner-a","original-00001").ok).to.equal(false)
			expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance)
		end)
		it("refuses a modern stale snapshot even when its revision is artificially greater",function()
			local f=fixture(12);expect(archive(f).ok).to.equal(true)
			local current=f.records[f.key].Transport.LastRevision
			expect(f.store():Save(f.key,"owner-a","stale-snapshot",current+100,f.original.Data,180).ok).to.equal(false)
			expect(f.records[f.key].Data.Commerce.ReceiptCount).to.equal(4)
		end)
		it("retains evidence on unavailable or corrupt archive lookup and ignores stale cached absence",function()
			local f=fixture(3);expect(archive(f).ok).to.equal(true);f.cached={}
			expect(f.store():LookupPaidReceipt(f.key,"owner-a","original-00001").receipt.Amount).to.equal(500000000)
			f.failLookup=true;expect(f.store():LookupPaidReceipt(f.key,"owner-a","original-00001").ok).to.equal(false);f.failLookup=false
			for k,v in f.records do if k:match("^paid1_") and v.PurchaseId=="original-00001" then v.Receipt.ConfigVersion=nil end end
			expect(f.store():LookupPaidReceipt(f.key,"owner-a","original-00001").code).to.equal("PAID_ARCHIVE_CONFLICT")
			expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance)
		end)
		it("keeps archive keys within50 characters and detects full identity conflicts instead of overwriting",function()
			local f=fixture(3);expect(archive(f).ok).to.equal(true)
			for k,v in f.records do if k:match("^paid1_") then expect(#k<=50).to.equal(true);v.ProfileKey="different-owner" end end
			expect(f.store():LookupPaidReceipt(f.key,"owner-a","original-00001").code).to.equal("PAID_ARCHIVE_CONFLICT")
		end)
		it("completes three full-capacity recovery/refill cycles with all earlier archived IDs replayable after restart",function()
			local f=fixture(10000);local expected=f.original.Data.Economy.Balance
			for cycle=1,3 do
				expect(archive(f).ok).to.equal(true)
				local current=copy(f.records[f.key].Data)
				for n=1,8 do local id=string.format("new-%d-%d",cycle,n);assert(Rules.GrantReceipt(current,id,101,500000000,1000,"FIXTURE"));current.Commerce.ProcessedReceipts[id].CommitRevision=f.records[f.key].Transport.LastRevision+1;expected+=500000000 end
				expect(f.store():Save(f.key,"owner-a","refill-"..cycle,f.records[f.key].Transport.LastRevision+1,current,180).ok).to.equal(true)
				expect(f.records[f.key].Data.Commerce.ReceiptCount).to.equal(10000)
				local acquired=f.store():Acquire(f.key,"owner-a",180);expect(acquired.ok).to.equal(true)
				for n=1,8 do expect(f.store():LookupPaidReceipt(f.key,"owner-a",string.format("original-%05d",n)).receipt.Amount).to.equal(500000000) end
				expect(f.records[f.key].Data.Economy.Balance).to.equal(expected)
			end
			expect(f.records[f.key].Transport.PaidArchive.Count).to.equal(24)
		end)
		it("bootstraps at the actual encoded maximum without oversized publication or loss of ordinary fields",function()
			local f=fixture(100);f.records[f.key].Padding=""
			local overhead=#Http:JSONEncode(f.records[f.key]);f.records[f.key].Padding=string.rep("x",4194304-overhead)
			expect(#Http:JSONEncode(f.records[f.key])).to.equal(4194304)
			expect(archive(f).ok).to.equal(true)
			expect(#Http:JSONEncode(f.records[f.key])<4194304).to.equal(true)
			expect(#f.records[f.key].Padding).to.equal(4194304-overhead)
			expect(Capacity.MeasureEnvelope(f.records[f.key]).ok).to.equal(false) -- Needs more batches before a new prompt/grant.
		end)
		it("delivers a pending valid receipt through the actual profile/coordinator/dispatcher after full-ledger recovery without a new purchase",function()
			local f=fixture(10000);f.records[f.key].Transport.OwnerToken=nil;f.records[f.key].Transport.LeaseExpiresAt=0
			Profile:_ResetForTests();Transactions:_ResetForTests()
			local player={UserId=831339,Name="SyntheticArchive",Parent=Players,Attributes={}}
			function player:SetAttribute(k,v)self.Attributes[k]=v end
			local income={BeginCriticalCutover=function()return {} end,EndCriticalCutover=function()return true end}
			local ok,why=xpcall(function()
				Profile:Init({Backend=f.store(),UnixNow=function()return f.now end,MonotonicNow=function()return f.now end,Wait=function(n)f.now+=n end,Random=function()return 0 end,KickOnFailure=false})
				expect(Profile:LoadPlayerAsync(player).ok).to.equal(true)
				Transactions:Start({Profile=Profile,Income=income,Now=function()return f.now end,Currency={SyncBalance=function()end}})
				Service:_ConfigureForTests({Profile=Profile,Transactions=Transactions,UniverseId=999,Catalogue={UniverseId=999,Version="FIXTURE",Passes={},Products={{id="FIXTURE",platformId=101,verifiedUniverseId=999,amount=500000000}}},ResolvePlayer=function()return player end,Telemetry={Record=function()end,Funnel=function()end}})
				local receipt={PlayerId=player.UserId,ProductId=101,PurchaseId="pending-before-full"}
				expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
				Service:RecoverPending(player)
				expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
				expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance+500000000)
				for _=1,3 do expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted) end
				local old={PlayerId=player.UserId,ProductId=101,PurchaseId="original-00001"}
				expect(Service:ProcessReceipt(old)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
				expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance+500000000)
				-- A competing callback grants and archives the same ID after our
				-- lookup returns. The coordinator must reject our stale epoch.
				local originalLookup=Profile.LookupPaidReceipt
				local armed=true
				local contended={PlayerId=player.UserId,ProductId=101,PurchaseId="aaa-contended"}
				Profile.LookupPaidReceipt=function(self,p,id)
					local value=originalLookup(self,p,id)
					if armed and id==contended.PurchaseId then
						armed=false
						expect(Service:ProcessReceipt(contended)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
						expect(Profile:RecoverPaidReceiptCapacity(player).ok).to.equal(true)
					end
					return value
				end
				local competed,err=pcall(function()
					expect(Service:ProcessReceipt(contended)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
					expect(Service:ProcessReceipt(contended)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance+1000000000)
				end)
				Profile.LookupPaidReceipt=originalLookup
				assert(competed,err)
				-- An uncertain archive write must end writability immediately;
				-- the session cannot continue saving a pre-fence snapshot.
				f.fault="CopyAfter"
				local interrupted=Profile:RecoverPaidReceiptCapacity(player)
				expect(interrupted.ok).to.equal(false)
				expect(Profile:IsWritable(player)).to.equal(false)
				expect(f.records[f.key].Data.Economy.Balance).to.equal(f.original.Data.Economy.Balance+1000000000)
			end,debug.traceback)
			Service:_ResetFixture();Transactions:_ResetForTests();Profile:_ResetForTests();assert(ok,why)
		end)
	end)
end
