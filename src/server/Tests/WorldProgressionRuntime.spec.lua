--!nocheck
return function()
	local Runtime=require(script.Parent.Parent.Services.WorldProgressionRuntime)
	local Schema=require(script.Parent.Parent.Data.PlayerProfileSchema)
	local function fixture(callback)
		local cleanup={}
		local map=Instance.new("Folder")
		for name,x in {Camp=0,Forest=100,Beach=200} do
			local folder=Instance.new("Folder") folder.Name=name folder.Parent=map
			local floor=Instance.new("Part") floor.Size=Vector3.new(100,4,100) floor.Position=Vector3.new(x,-2,0)
			floor:SetAttribute("LayoutRole","Floor") floor:SetAttribute("GeneratedBy","CreateBasicMap_v1") floor.Parent=folder
		end
		local folder=Instance.new("Folder") folder.Name="ProgressionGates" folder.Parent=map
		local gate=Instance.new("Model") gate.Name="Beach" gate.Parent=folder
		gate:SetAttribute("RegionId","REGION_BEACH") gate:SetAttribute("LogicalRegionKey","Beach") gate:SetAttribute("InwardNormal",Vector3.xAxis)
		for _,name in {"InteractionAnchor","Approach","Threshold","SafeCharacterExterior","SafeCartExterior","DoorPresentation"} do
			local part=Instance.new("Part") part.Name=name part.Anchored=true part.CanCollide=false
			part.Position=if name:match("Exterior") then Vector3.new(130,3,0) else Vector3.new(150,3,0)
			part.Parent=gate
		end
		local character=Instance.new("Model") character.Parent=workspace
		local root=Instance.new("Part") root.Name="HumanoidRootPart" root.Anchored=true root.Position=Vector3.new(145,3,0) root.Parent=character
		character.PrimaryPart=root
		local humanoid=Instance.new("Humanoid") humanoid.Parent=character
		local player={UserId=74005,Character=character}
		local data=Schema.CreateDefault()
		local profile={}
		function profile:IsWritable() return true end
		function profile:GetStatus() return "Ready" end
		function profile:GetReadableData() return data end
		function profile:SubscribeSaveConfirmed() return {Disconnect=function() end} end
		local runtime=Runtime.new({Map=map,Profile=profile,Carts={GetCartRecords=function() return {} end},
			Occupants={GetOccupants=function() return {} end,GetOwnerUserId=function() return nil end,
				GetDriver=function() return nil end,CanPlayerControlCart=function() return false end}})
		runtime.access:SetOperational("REGION_BEACH",true)
		local ok,failure=xpcall(function() callback(runtime,player,root,humanoid,data,gate,function(work) table.insert(cleanup,work) end) end,debug.traceback)
		runtime:Destroy() character:Destroy() map:Destroy()
		for _,work in cleanup do work() end
		assert(ok,failure)
	end
	it("rejects distance and dead-character context through the actual geometry adapter",function()
		fixture(function(runtime,player,root,humanoid)
			local context,code=runtime:ValidateGateContext(player,"Beach")
			expect(context.currencyConfirmed).to.equal(true) expect(code).to.equal(nil)
			root.Position=Vector3.new(100,3,0)
			local absent,far=runtime:ValidateGateContext(player,"Beach") expect(absent).to.equal(nil) expect(far).to.equal("TooFarFromGate")
			humanoid.Health=0
			local dead,reason=runtime:ValidateGateContext(player,"Beach") expect(dead).to.equal(nil) expect(reason).to.equal("CharacterUnavailable")
		end)
	end)
	it("corrects a locked character using root clearance and keeps profile data intact",function()
		fixture(function(runtime,player,root,_,data)
			root.Position=Vector3.new(180,3,0)
			data.Economy.Balance=125.5
			local token=player.Character
			expect(runtime:CorrectPlayer(player,"REGION_BEACH",token)).to.equal(true)
			expect(root.Position.X).to.equal(130) expect(root.Position.Y>3).to.equal(true)
			expect(data.Economy.Balance).to.equal(125.5)
			expect(data.WorldProgression.PersonalUnlocks.Beach).to.equal(nil)
		end)
	end)
	it("rechecks permanent access and character identity before correction",function()
		fixture(function(runtime,player,root,_,data)
			root.Position=Vector3.new(180,3,0) local before=root.CFrame
			expect(runtime:CorrectPlayer(player,"REGION_BEACH",{})).to.equal(false)
			data.WorldProgression.PersonalUnlocks.Beach={source="purchase"}
			expect(runtime:CorrectPlayer(player,"REGION_BEACH",player.Character)).to.equal(false)
			expect(root.CFrame).to.equal(before)
		end)
	end)
	it("rebinds one gate prompt and preserves personal grants through replacement",function()
		fixture(function(runtime,_,_,_,data,gate)
			local prompt=Instance.new("ProximityPrompt") prompt.Name="UnlockPrompt" prompt.Parent=gate.InteractionAnchor
			runtime.operationalKeys.Beach=true runtime:WatchGate(gate)
			local first=runtime.gateBindings.REGION_BEACH.connection
			expect(runtime:RefreshGate(gate)).to.equal(true)
			expect(runtime.gateBindings.REGION_BEACH.connection).to.equal(first)
			data.WorldProgression.PersonalUnlocks.Beach={source="purchase"}
			local parent=gate.Parent local replacement=gate:Clone()
			gate.Parent=nil runtime:RemoveGate(gate)
			expect(runtime.access:IsOperational("REGION_BEACH")).to.equal(false)
			expect(data.WorldProgression.PersonalUnlocks.Beach~=nil).to.equal(true)
			replacement.Parent=parent runtime:WatchGate(replacement)
			expect(runtime.access:IsOperational("REGION_BEACH")).to.equal(true)
			expect(runtime.gateBindings.REGION_BEACH.instance).to.equal(replacement)
			runtime:RemoveGate(gate)
			expect(runtime.gateBindings.REGION_BEACH.instance).to.equal(replacement)
			gate:Destroy()
		end)
	end)
	it("does not activate an incomplete replacement and releases obsolete subscriptions",function()
		fixture(function(runtime,_,_,_,_,gate)
			local prompt=Instance.new("ProximityPrompt") prompt.Name="UnlockPrompt" prompt.Parent=gate.InteractionAnchor
			runtime.operationalKeys.Beach=true runtime:WatchGate(gate)
			local parent=gate.Parent local replacement=gate:Clone() replacement.SafeCartExterior:Destroy()
			gate.Parent=nil runtime:RemoveGate(gate) replacement.Parent=parent runtime:WatchGate(replacement)
			expect(runtime.gateBindings.REGION_BEACH).to.equal(nil)
			expect(runtime.gateWatchers[gate]).to.equal(nil)
			expect(runtime.access:IsOperational("REGION_BEACH")).to.equal(false)
			gate:Destroy()
		end)
	end)
	it("cleans a removed gate folder and binds its replacement without duplicated prompts",function()
		fixture(function(runtime,_,_,_,_,gate)
			local prompt=Instance.new("ProximityPrompt") prompt.Name="UnlockPrompt" prompt.Parent=gate.InteractionAnchor
			runtime.operationalKeys.Beach=true runtime:BindGateFolder(gate.Parent)
			local old=gate.Parent local replacement=old:Clone()
			old.Parent=nil runtime:ClearGateFolder()
			expect(runtime.access:IsOperational("REGION_BEACH")).to.equal(false)
			expect(next(runtime.gateWatchers)).to.equal(nil)
			replacement.Parent=runtime.options.Map runtime:BindGateFolder(replacement)
			expect(runtime.access:IsOperational("REGION_BEACH")).to.equal(true)
			local connection=runtime.gateBindings.REGION_BEACH.connection runtime:BindGateFolder(replacement)
			expect(runtime.gateBindings.REGION_BEACH.connection).to.equal(connection)
			old:Destroy()
		end)
	end)
	it("observes new successful banking proof once without reclassifying restored proof",function()
		fixture(function(runtime,player,_,_,data)
			local events={} runtime.options.OnEvent=function(name,fields) table.insert(events,{name=name,fields=fields}) end
			data.WorldProgression.BankedSpecies.BRT_011={rarityAtFirstBank="Uncommon",source="legacy_bank_record"}
			runtime:ObserveProgress(player)
			expect(#events).to.equal(1) expect(events[1].name).to.equal("ProgressionProfileReady")
			data.Collection.BrainrotInstances["real-bank-id"]={speciesId="BRT_019",metadata={}}
			data.Base.Slots["1"].brainrotId="real-bank-id"
			data.WorldProgression.BankedSpecies.BRT_019={rarityAtFirstBank="Rare",source="deposit"}
			runtime:ObserveProgress(player) runtime:ObserveProgress(player)
			expect(#events).to.equal(2) expect(events[2].name).to.equal("BankingProofAdded")
			expect(events[2].fields.individualId).to.equal("real-bank-id")
			data.Base.Slots["1"].brainrotId=nil data.Collection.BrainrotInstances["real-bank-id"]=nil
			runtime:ObserveProgress(player) expect(#events).to.equal(2)
		end)
	end)
	it("publishes the committed player and refreshed banking requirements through the storage observer",function()
		fixture(function(runtime,player,_,_,data,_,cleanup)
			local replicatedStorage=game:GetService("ReplicatedStorage")
			local existingFolder=replicatedStorage:FindFirstChild("Remotes")
			local existingRemotes={}
			local createdRemotes={}
			for _,remote in if existingFolder then existingFolder:GetChildren() else {} do existingRemotes[remote]=true end
			local readyDisconnected,storageDisconnected=false,false
			cleanup(function()
				local folder=replicatedStorage:FindFirstChild("Remotes")
				for _,remote in createdRemotes do remote:Destroy() end
				if not existingFolder and folder and #folder:GetChildren()==0 then folder:Destroy() end
				expect(readyDisconnected).to.equal(true)
				expect(storageDisconnected).to.equal(true)
			end)
			local observer
			runtime.options.Storage={ObserveStorage=function(_,current)
				observer=current
				return function() storageDisconnected=true end
			end}
			runtime.options.Profile.SubscribeReady=function()
				return {Disconnect=function() readyDisconnected=true end}
			end
			local published,messages={},{}
			local publish=runtime.Publish
			runtime.Publish=function(self,recipient)
				table.insert(published,{recipient=recipient})
				if recipient==player then publish(self,recipient) end
			end
			runtime.Send=function(self,recipient,message)
				table.insert(messages,{recipient=recipient,kind=message.kind,summary=self:Summary(recipient)})
			end
			runtime:BindInteractions()
			for _,remote in replicatedStorage.Remotes:GetChildren() do
				if not existingRemotes[remote] then table.insert(createdRemotes,remote) end
			end
			-- Cache the empty proof before the commit, as a client opening its gate panel does.
			runtime:Publish(player)
			expect(messages[#messages].summary.gates.Beach.branchA.count).to.equal(0)
			table.clear(published) table.clear(messages)
			data.Collection.BrainrotInstances["committed-individual"]={speciesId="BRT_011",metadata={}}
			data.Base.Slots["1"].brainrotId="committed-individual"
			data.WorldProgression.BankedSpecies.BRT_011={rarityAtFirstBank="Uncommon",source="deposit"}
			local storage={BaseId="regression-base"}
			local snapshot=table.freeze({table.freeze({ItemId="committed-individual",BrainrotId="BRT_011"})})
			-- BaseStorageSystem dispatches Player, storage, revision, snapshot; no assignment wrapper.
			observer.OnCommitted(player,storage,1,snapshot)
			expect(#published).to.equal(1) expect(published[1].recipient).to.equal(player)
			expect(#messages).to.equal(1) expect(messages[1].recipient).to.equal(player)
			expect(messages[1].kind).to.equal("Summary")
			expect(messages[1].summary.gates.Beach.branchA.count).to.equal(1)
			expect(messages[1].summary.gates.Beach.bankingSatisfied).to.equal(true)
			observer.OnCommitted(player,storage,2,snapshot)
			expect(#published).to.equal(2)
			expect(messages[2].summary.gates.Beach.branchA.count).to.equal(1)
		end)
	end)
	it("reports denied wild actions once without retargeting or changing proof",function()
		fixture(function(runtime,player,root,_,data)
			root.Position=Vector3.new(100,3,0)
			local events={} runtime.options.OnEvent=function(name) table.insert(events,name) end
			for _=1,10 do
				local allowed,code=runtime:ValidateWildAction(player,Vector3.new(180,3,0))
				expect(allowed).to.equal(false) expect(code).to.equal("RegionAccessRequired")
			end
			expect(#events).to.equal(1) expect(events[1]).to.equal("UnauthorizedWildAction")
			expect(next(data.WorldProgression.BankedSpecies)).to.equal(nil)
		end)
	end)
	it("keeps personal hunting and cart access independent and recovers only the denied player",function()
		fixture(function(runtime,player,root,_,data)
			local otherCharacter=player.Character:Clone() otherCharacter.Parent=runtime.options.Map
			local other={UserId=1,Character=otherCharacter}
			local otherData=Schema.CreateDefault() otherData.WorldProgression.PersonalUnlocks.Beach={source="purchase"}
			runtime.options.Profile.GetReadableData=function(_,who) return if who==other then otherData else data end
			local cart,otherCart={},{}
			local drivers={[cart]=player,[otherCart]=other}
			local owners={[cart]=player.UserId,[otherCart]=other.UserId}
			runtime.options.Occupants.GetOwnerUserId=function(_,model) return owners[model] end
			runtime.options.Occupants.GetDriver=function(_,model) return drivers[model] end
			runtime.options.Occupants.CanPlayerControlCart=function(_,who,model)
				return drivers[model]==who and owners[model]==who.UserId
			end
			root.Position=Vector3.new(180,3,0) otherCharacter.PrimaryPart.Position=Vector3.new(180,3,0)
			data.Economy.Balance=125.5
			expect(runtime.access:GetEffectiveAccess(player,"REGION_BEACH")).to.equal(false)
			expect(runtime.access:GetEffectiveAccess(other,"REGION_BEACH")).to.equal(true)
			expect(runtime.access:GetCartEntryAccess(cart,"REGION_BEACH").allowed).to.equal(false)
			expect(runtime.access:GetCartEntryAccess(otherCart,"REGION_BEACH").allowed).to.equal(true)
			local allowed,code=runtime:ValidateWildAction(player,Vector3.new(180,3,0))
			expect(allowed).to.equal(false) expect(code).to.equal("RegionAccessRequired")
			expect(runtime:ValidateWildAction(other,Vector3.new(180,3,0))).to.equal(true)
			expect(runtime:Summary(player).guest).to.equal(nil)
			local otherBefore=otherCharacter.PrimaryPart.CFrame
			expect(runtime:CorrectPlayer(player,"REGION_BEACH",player.Character)).to.equal(true)
			expect(root.Position.X).to.equal(130)
			expect(runtime:CorrectPlayer(other,"REGION_BEACH",otherCharacter)).to.equal(false)
			expect(otherCharacter.PrimaryPart.CFrame).to.equal(otherBefore)
			-- Dismounting does not remove permanent permission or lend it to others.
			drivers[otherCart]=nil
			expect(runtime.access:CanBoard(other)).to.equal(true)
			expect(runtime.access:GetEffectiveAccess(other,"REGION_BEACH")).to.equal(true)
			expect(runtime.access:GetCartEntryAccess(otherCart,"REGION_BEACH").allowed).to.equal(false)
			drivers[cart]=other
			expect(runtime.access:GetCartEntryAccess(cart,"REGION_BEACH").code).to.equal("OwnerDriverRequired")
			expect(data.Economy.Balance).to.equal(125.5)
			expect(data.WorldProgression.PersonalUnlocks.Beach).to.equal(nil)
			expect(otherData.WorldProgression.PersonalUnlocks.Beach.source).to.equal("purchase")
		end)
	end)

	it("clears actual cart denial on unseat and permits a far remount before denying reentry",function()
		fixture(function(runtime,player,_,_,data)
			local cart=Instance.new("Model") cart.Name="SPEC_DeniedCart" cart.Parent=runtime.options.Map
			local root=Instance.new("Part") root.Name="Root" root.Anchored=true
			root.Size=Vector3.new(8,3,12)
			root.CFrame=CFrame.lookAt(Vector3.new(145,3,0),Vector3.new(146,3,0))
			root.Parent=cart cart.PrimaryPart=root
			local seated=true
			runtime.options.Carts.GetCartRecords=function() return {{Model=cart,OwnerUserId=player.UserId}} end
			runtime.options.Occupants.GetOccupants=function() return if seated then {player} else {} end
			runtime.options.Occupants.GetOwnerUserId=function() return player.UserId end
			runtime.options.Occupants.GetDriver=function() return if seated then player else nil end
			runtime.options.Occupants.CanPlayerControlCart=function(_,who,model) return seated and who==player and model==cart end
			root.AssemblyLinearVelocity=Vector3.new(30,0,0)
			runtime:RefreshEntities() runtime.guard:Step()
			expect(cart:GetAttribute("WorldGateDeniedNormal")).to.equal(Vector3.xAxis)
			seated=false
			runtime:RefreshEntities() runtime.guard:Step()
			expect(cart:GetAttribute("WorldGateDeniedNormal")).to.equal(nil)
			root.CFrame=CFrame.lookAt(Vector3.new(100,3,0),Vector3.new(101,3,0))
			root.AssemblyLinearVelocity=Vector3.zero seated=true
			runtime:RefreshEntities() runtime.guard:Step()
			expect(cart:GetAttribute("WorldGateDeniedNormal")).to.equal(nil)
			root.CFrame=CFrame.lookAt(Vector3.new(145,3,0),Vector3.new(146,3,0))
			root.AssemblyLinearVelocity=Vector3.new(30,0,0)
			runtime:RefreshEntities() runtime.guard:Step()
			expect(cart:GetAttribute("WorldGateDeniedNormal")).to.equal(Vector3.xAxis)
			expect(data.WorldProgression.PersonalUnlocks.Beach).to.equal(nil)
			expect(data.Economy.Balance).to.equal(0)
		end)
	end)

end
