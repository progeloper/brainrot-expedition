--!strict
-- Binds the shared guard to existing profiles, actual seats and assembly reset.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Config.WorldProgression)
local Math=require(ReplicatedStorage.Shared.Utility.RegionGuardMath)
local Descriptors=require(script.Parent.Parent.Utility.RegionGateDescriptors)
local Reset=require(script.Parent.Parent.Utility.CartResetExecutor)
local Progression=require(script.Parent.WorldProgressionService)
local Access=require(script.Parent.RegionAccessService)
local Boundary=require(script.Parent.RegionBoundaryGuard)
local PopulationPolicy=require(script.Parent.Parent.Utility.WorldPopulationAccessPolicy)
local SpawnRegions=require(script.Parent.Parent.Systems.RegionSpawnCatalog)
local Names=require(ReplicatedStorage.Shared.Constants.RemoteNames)
local CollectionService=game:GetService("CollectionService")
local StormResponse=require(script.Parent.StormBoundaryResponse)
local StormBoundaries=require(ReplicatedStorage.Shared.Config.StormBoundaries)
local MistResponse=require(script.Parent.OutOfBoundsResponse)
local IslandEdge=require(ReplicatedStorage.Shared.Config.IslandEdge)
local Runtime={}
Runtime.__index=Runtime
function Runtime.new(options: any): any
	assert(options.Map and options.Profile and options.Carts and options.Occupants,"Missing authoritative adapters")
	local self=setmetatable({options=options,connections={},cache={},playerCarts={},correcting={},
		gateBindings={},gateWatchers={},operationalKeys={},observedProgress={},
		descriptors=Descriptors.new(options.Map),accumulator=0,destroyed=false},Runtime)
	self.progression=Progression.new({Profile=options.Profile,
		ValidateGateContext=function(player,key) return self:ValidateGateContext(player,key) end,
		OnEvent=function(name,data,player) self:RecordEvent(name,data,player) end,
		OnResult=function(player,result)
			if options.Currency and result.code=="Success" then options.Currency:SyncBalance(player) end
			if options.OnResult then options.OnResult(player,result) end
			self:Send(player,{kind="Result",result=result})
		end})
	self.access=Access.new({Progression=self.progression,Occupants=options.Occupants,Descriptors=self.descriptors,
		GetPlayerState=function(player) return self:GetPlayerState(player) end})
	self.guard=Boundary.new({Access=self.access,Descriptors=self.descriptors,
		GetEntities=function() return self.entities or {} end,
		Correct=function(entity,region)
			if entity.cart then return self:CorrectCart(entity.cart,region) end
			return self:CorrectPlayer(entity.members[1],region,entity.characterToken)
		end,
		SetDenied=function(entity,normal)
			if entity.cart and entity.cart.Parent then entity.cart:SetAttribute("WorldGateDeniedNormal",normal) end
		end,
		StopInward=function(entity,normal)
			if entity.root.Parent then entity.root.AssemblyLinearVelocity=Math.RemoveInwardVelocity(entity.root.AssemblyLinearVelocity,normal) end
		end,
		Notice=function(player,code,region)
			if options.OnNotice then options.OnNotice(player,code,region) end
			self:RecordEvent("UnauthorizedRegionEntry",{code=code,regionId=region},player)
			self:Send(player,{kind="Notice",text="Personally unlock "..Config.ById[region].displayName.." to enter this region."})
		end,
		Storm=if options.StormEnabled then self:CreateStormResponse() else nil})
	if options.StormEnabled then self.mist=self:CreateMistResponse() end
	return self
end
-- TerrainRedesign only: out-of-bounds sea mist past the island edge (push -> grace -> shore).
-- Characters only; a cart cannot leave the island over the solid perimeter colliders.
function Runtime:CreateMistResponse(): any
	return MistResponse.new({Edge=IslandEdge,
		Push=function(entity,normal,exit)
			local remote=self:StormRemote()
			for _,player in entity.members do
				if player.Parent==Players then
					remote:FireClient(player,{kind="Mist",normal=normal,exit=exit,cart=entity.cart~=nil})
				end
			end
		end,
		ResolveLanding=function(entity,point) return self:ResolveStormLanding(entity,point) end,
		Move=function(entity,landing)
			if entity.cart then return false end
			return self:CorrectPlayer(entity.members[1],nil,entity.characterToken,landing)
		end,
		Hub=function()
			local spawn=workspace:FindFirstChildWhichIsA("SpawnLocation",true)
			return if spawn then spawn.Position+Vector3.new(0,spawn.Size.Y/2,0) else nil
		end,
		Storming=function(entity)
			local storm=self.guard.a.Storm
			return storm~=nil and storm.active[entity.id]~=nil
		end,
		Record=function(data,entity)
			self:RecordEvent("StormPushed",data,if entity then entity.members[1] else nil)
		end})
end
-- TerrainRedesign only. Same access decisions; the response becomes push -> grace -> safe point.
function Runtime:CreateStormResponse(): any
	-- Created now, not on the first push: clients wait a bounded time for it (Play, 9 Nov: a lazily
	-- created remote arrived after the client's wait ended and the client push never ran).
	self:StormRemote()
	return StormResponse.new({Boundaries=StormBoundaries,
		KeyForRegion=function(regionId) local d=Config.ById[regionId] return d and d.key end,
		Push=function(entity,key,normal,exit)
			local remote=self:StormRemote()
			for _,player in entity.members do
				if player.Parent==Players then
					remote:FireClient(player,{kind="Push",regionKey=key,normal=normal,exit=exit,cart=entity.cart~=nil})
				end
			end
		end,
		ResolveLanding=function(entity,point) return self:ResolveStormLanding(entity,point) end,
		Move=function(entity,landing)
			if entity.cart then return self:CorrectCart(entity.cart,nil,landing) end
			return self:CorrectPlayer(entity.members[1],nil,entity.characterToken,landing)
		end,
		LegacyCorrect=function(entity,regionId)
			if entity.cart then return self:CorrectCart(entity.cart,regionId) end
			return self:CorrectPlayer(entity.members[1],regionId,entity.characterToken)
		end,
		Record=function(name,data,entity)
			self:RecordEvent(name,data,if entity then entity.members[1] else nil)
		end})
end
function Runtime:StormRemote(): RemoteEvent
	if self.stormRemote and self.stormRemote.Parent then return self.stormRemote end
	local folder=ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then folder=Instance.new("Folder") folder.Name="Remotes" folder.Parent=ReplicatedStorage end
	local remote=folder:FindFirstChild(Names.StormPush)
	if not remote then remote=Instance.new("RemoteEvent") remote.Name=Names.StormPush remote.Parent=folder end
	assert(remote:IsA("RemoteEvent"),"Invalid Storm remote class")
	self.stormRemote=remote
	return remote
end
-- A landing is valid when every member may stand there and solid, walkable ground exists.
function Runtime:ResolveStormLanding(entity: any,point: Vector2): Vector3?
	local probe=Vector3.new(point.X,0,point.Y)
	local region=self.descriptors:GetRegionAtPosition(probe)
	if not region then return nil end
	local definition=Config.ById[region]
	if definition and definition.index>1 then
		for _,player in entity.members do
			if not self.access:GetEffectiveAccess(player,region) then return nil end
		end
	end
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.RespectCanCollide=true
	local exclude={}
	if entity.cart then table.insert(exclude,entity.cart) end
	for _,player in entity.members do if player.Character then table.insert(exclude,player.Character) end end
	params.FilterDescendantsInstances=exclude
	local hit=workspace:Raycast(probe+Vector3.new(0,160,0),Vector3.new(0,-200,0),params)
	if not hit or hit.Normal.Y<0.75 or hit.Material==Enum.Material.Water then return nil end
	return hit.Position
end
function Runtime:RecordEvent(name: string,data: any,player: Player?)
	if self.options.OnEvent then pcall(self.options.OnEvent,name,data,player) end
end
function Runtime:ObserveProgress(player: Player,initial: boolean?)
	local data=self.options.Profile:GetReadableData(player)
	if not data or not self.options.Profile:IsWritable(player) then return end
	local previous=self.observedProgress[player]
	if not previous then
		previous={species={}} self.observedProgress[player]=previous
		self.progression:InvalidateRequirements(player)
		local legacy={}
		for key,grant in data.WorldProgression.PersonalUnlocks do
			if grant.source=="legacy_progress" then table.insert(legacy,key) end
		end
		table.sort(legacy)
		self:RecordEvent("ProgressionProfileReady",{currencyVersion=data.CurrencyVersion,
			legacyGrantVersion=data.WorldProgression.LegacyGrantVersion,legacyRegions=table.concat(legacy,","),
			fixture=data.WorldProgression.TestFixture~=nil},player)
		initial=true
	end
	for id,proof in data.WorldProgression.BankedSpecies do
		if not previous.species[id] then
			previous.species[id]=true
			self.progression:InvalidateRequirements(player)
			if not initial then
				local individualId=nil
				for _,slot in data.Base.Slots do
					local individual=slot.brainrotId and data.Collection.BrainrotInstances[slot.brainrotId]
					if individual and individual.speciesId==id then individualId=slot.brainrotId break end
				end
				self:RecordEvent("BankingProofAdded",{speciesId=id,rarity=proof.rarityAtFirstBank,individualId=individualId},player)
			end
		end
	end
end
function Runtime:GetPlayerState(player: Player): any?
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then return nil end
	local cart=self.playerCarts[player]
	if cart then
		local seated=false
		for _,occupant in self.options.Occupants:GetOccupants(cart) do if occupant==player then seated=true break end end
		if not seated then cart=nil end
	end
	local state={ready=self.options.Profile:IsWritable(player),alive=humanoid.Health>0,characterToken=character,
		position=root.Position,regionId=self.descriptors:GetRegionAtPosition(root.Position),cart=cart}
	for _,definition in Config.Ordered do
		if definition.index<=1 then continue end
		local cache=if cart then self.cache[cart] else nil
		if self.descriptors:IsInTransition(root.Position,definition.regionId,if cache then cache.extent else 0) then
			state.transitionRegionId=definition.regionId break
		end
	end
	return state
end
function Runtime:GetGateContext(player: Player,key: string): any
	local definition=Config.ByKey[key]
	local gate=definition and self.descriptors:GetGate(definition.regionId)
	local state=self:GetPlayerState(player)
	return {ready=self.options.Profile:GetStatus(player)=="Ready",writable=self.options.Profile:IsWritable(player),
		currencyConfirmed=true,operational=definition~=nil and self.access:IsOperational(definition.regionId),
		alive=state~=nil and state.alive,nearGate=gate~=nil and state~=nil
			and (state.position-gate.anchor.Position).Magnitude<=Config.GATE_PURCHASE_MAX_DISTANCE_STUDS}
end
function Runtime:ValidateWildAction(player: Player,target: any): (boolean,string?)
	local allowed,code=self.access:CanInteractWild(player,target)
	if not allowed then
		self.actionNotices=self.actionNotices or {}
		local now=os.clock()
		if now-(self.actionNotices[player] or -math.huge)>=Config.UNAUTHORIZED_NOTICE_COOLDOWN_SECONDS then
			self.actionNotices[player]=now
			self:RecordEvent("UnauthorizedWildAction",{code=code,
				regionId=self.access:GetCurrentAuthoritativeRegion(target)},player)
		end
	end
	return allowed,code
end
function Runtime:ValidateGateContext(player: Player,key: string): (any?,string?)
	local context=self:GetGateContext(player,key)
	if not context.alive then return nil,"CharacterUnavailable" end
	if not context.operational then return nil,"RegionUnavailable" end
	if not context.nearGate then return nil,"TooFarFromGate" end
	return context,nil
end
function Runtime:RefreshEntities()
	local entities,seen={},{}
	table.clear(self.playerCarts)
	for _,record in self.options.Carts:GetCartRecords() do
		local cart=record.Model
		if not cart or not cart.Parent then continue end
		seen[cart]=true
		local members={}
		for _,player in self.options.Occupants:GetOccupants(cart) do
			if player.UserId==record.OwnerUserId then
				table.insert(members,player) self.playerCarts[player]=cart
			end
		end
		local root=cart.PrimaryPart
		if not root or #members==0 then continue end
		local cache=self.cache[cart]
		local revision=cart:GetAttribute("CargoRevision")
		if not cache or cache.revision~=revision then
			local frame,size=cart:GetBoundingBox()
			cache={revision=revision,relative=root.CFrame:ToObjectSpace(frame),size=size,extent=0}
			self.cache[cart]=cache
		end
		local frame=root.CFrame*cache.relative
		-- Conservative full loaded assembly footprint; no descendant scan per tick.
		cache.extent=math.max(cache.size.X,cache.size.Z)/2
		local ready,alive=true,true
		for _,player in members do
			local state=self:GetPlayerState(player)
			ready=ready and state~=nil and state.ready alive=alive and state~=nil and state.alive
		end
		table.insert(entities,{id=cart,cart=cart,members=members,ready=ready,alive=alive,root=root,
			position=frame.Position,velocity=root.AssemblyLinearVelocity,forward=root.CFrame.LookVector,
			extent=cache.extent,lateralExtent=cache.extent})
	end
	for cart in self.cache do if not seen[cart] then self.cache[cart]=nil end end
	for _,player in Players:GetPlayers() do
		if self.playerCarts[player] then continue end
		local state=self:GetPlayerState(player)
		if not state then continue end
		local root=player.Character:FindFirstChild("HumanoidRootPart")
		table.insert(entities,{id=player,members={player},ready=state.ready,alive=state.alive,
			characterToken=state.characterToken,root=root,position=root.Position,velocity=root.AssemblyLinearVelocity,
			forward=root.CFrame.LookVector,extent=root.Size.Z/2,lateralExtent=root.Size.X/2})
	end
	self.entities=entities
end
function Runtime:CorrectPlayer(player: Player,regionId: string?,token: any,landing: Vector3?): boolean
	local gate=if regionId then self.descriptors:GetSafeExterior(regionId) else nil
	local state=self:GetPlayerState(player)
	if (not gate and not landing) or not state or state.characterToken~=token then return false end
	if regionId and self.access:GetEffectiveAccess(player,regionId) then return false end
	if state.cart then return self:CorrectCart(state.cart,regionId,landing) end
	-- An invalid occupant never gains a cart entity or permission. Detach before
	-- correcting that character so the owner's assembly is never pivoted.
	local seatedHumanoid=player.Character:FindFirstChildOfClass("Humanoid")
	if seatedHumanoid and seatedHumanoid.SeatPart then
		seatedHumanoid.Sit=false
		local deadline=os.clock()+.25
		while seatedHumanoid.SeatPart and os.clock()<deadline do RunService.Heartbeat:Wait() end
		state=self:GetPlayerState(player)
		if not state or state.characterToken~=token or state.cart or seatedHumanoid.SeatPart
			or (regionId and self.access:GetEffectiveAccess(player,regionId)) then return false end
	end
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return false end
	local lift=Vector3.new(0,humanoid.HipHeight+root.Size.Y/2+.25,0)
	-- Storm fallback keeps the character's orientation; the legacy exterior keeps its authored frame.
	local desired=if landing then root.CFrame.Rotation+(landing+lift) else gate.safeCharacter+lift
	character:PivotTo(desired*root.CFrame:Inverse()*character:GetPivot())
	root.AssemblyLinearVelocity=Vector3.zero root.AssemblyAngularVelocity=Vector3.zero
	return true
end
function Runtime:CorrectCart(cart: Model,regionId: string?,landing: Vector3?): boolean
	if self.correcting[cart] then return false end
	local gate=if regionId then self.descriptors:GetSafeExterior(regionId) else nil
	if not gate and not landing then return false end
	-- Storm fallback: the whole assembly (cargo included) moves to the landing, keeping its yaw.
	-- The current region is re-read each stage so access changes still cancel the move.
	local lockedRegion=regionId or (cart.PrimaryPart and self.descriptors:GetRegionAtPosition(cart.PrimaryPart.Position))
	if not lockedRegion then return false end
	local exterior: CFrame
	if landing then
		local root=cart.PrimaryPart
		if not root then return false end
		local look=root.CFrame.LookVector
		local flat=Vector3.new(look.X,0,look.Z)
		if flat.Magnitude<1e-3 then flat=Vector3.new(0,0,-1) end
		-- Authored cart exteriors sit on the y=0 ground plane; reuse their root lift above ground.
		local lift=self.stormCartLift
		if not lift then
			for _,definition in Config.Ordered do
				local exteriorDescriptor=self.descriptors:GetSafeExterior(definition.regionId)
				if exteriorDescriptor then lift=exteriorDescriptor.safeCart.Position.Y break end
			end
			self.stormCartLift=lift
		end
		if not lift then return false end
		exterior=CFrame.lookAt(landing+Vector3.new(0,lift,0),landing+Vector3.new(0,lift,0)+flat.Unit)
	else
		exterior=gate.safeCart
	end
	local ownerUserId=self.options.Occupants:GetOwnerUserId(cart)
	local owner,characterToken=nil,nil
	for _,player in self.options.Occupants:GetOccupants(cart) do
		if player.UserId==ownerUserId then
			local state=self:GetPlayerState(player)
			owner,characterToken=player,if state then state.characterToken else nil
			break
		end
	end
	if not owner or not characterToken then return false end
	local function stillUnauthorized()
		if self.options.Occupants:GetOwnerUserId(cart)~=ownerUserId then return false end
		for _,player in self.options.Occupants:GetOccupants(cart) do
			if player==owner then
				local state=self:GetPlayerState(player)
				return state~=nil and state.characterToken==characterToken
					and not self.access:GetEffectiveAccess(player,lockedRegion)
			end
		end
		return false
	end
	if not stillUnauthorized() then return false end
	self.correcting[cart]=true
	local ok,result=pcall(function()
		return Reset.CorrectRegionEntry(cart,exterior,function(stage)
			if self.destroyed or not cart.Parent then return false,"access correction expired" end
			if stage=="Suspension" or stage=="Reposition" then return stillUnauthorized(),"access changed" end
			return true,nil
		end)
	end)
	self.correcting[cart]=nil
	return ok and result==true
end
function Runtime:Summary(player: Player): any
	return self.progression:GetSummary(player,function(key) return self:GetGateContext(player,key) end)
end
function Runtime:Send(player: Player,message: any)
	if not self.update or player.Parent~=Players then return end
	message.summary=self:Summary(player)
	self.update:FireClient(player,message)
end
function Runtime:Publish(player: Player)
	self:ObserveProgress(player)
	self:Send(player,{kind="Summary"})
end
function Runtime:UnbindGate(regionId: string)
	local binding=self.gateBindings[regionId]
	if binding then
		binding.connection:Disconnect()
		if binding.prompt.Parent then binding.prompt.Enabled=false end
		self.gateBindings[regionId]=nil
	end
end
function Runtime:RefreshGate(model: Instance): boolean
	local key=model.Name
	local definition=Config.ByKey[key]
	local folder=self.options.Map:FindFirstChild("ProgressionGates")
	if self.destroyed or not definition or definition.index<=1 or model.Parent~=folder then return false end
	local ok=self.descriptors:BindGate(definition.regionId,model)
	local operational=ok and self.operationalKeys[key]==true
	self.access:SetOperational(definition.regionId,operational)
	self.summaryDirty=true
	if not ok then self:UnbindGate(definition.regionId) return false end
	local gate=self.descriptors:GetGate(definition.regionId)
	local prompt=gate.anchor:FindFirstChild("UnlockPrompt")
	if not prompt or not prompt:IsA("ProximityPrompt") then
		self.access:SetOperational(definition.regionId,false) self:UnbindGate(definition.regionId) return false
	end
	CollectionService:AddTag(model,"WorldProgressionGate")
	prompt.MaxActivationDistance=Config.GATE_PROMPT_DISTANCE_STUDS
	prompt.HoldDuration=Config.GATE_PROMPT_HOLD_SECONDS prompt.ActionText="View "..definition.displayName
	prompt.Enabled=operational
	local current=self.gateBindings[definition.regionId]
	if current and current.prompt==prompt then return true end
	self:UnbindGate(definition.regionId)
	prompt.Enabled=operational
	local connection=prompt.Triggered:Connect(function(player)
		local now=os.clock()
		if now-((self.panelRequests or {})[player] or -math.huge)<Config.GATE_REQUEST_MIN_INTERVAL_SECONDS then return end
		self.panelRequests=self.panelRequests or {} self.panelRequests[player]=now
		local state=self:GetPlayerState(player)
		if not state or not state.alive or (state.position-gate.anchor.Position).Magnitude>Config.GATE_PURCHASE_MAX_DISTANCE_STUDS then return end
		local summary=self:Summary(player)
		self:RecordEvent("GatePanelOpened",{key=key,code=summary.gates[key].code},player)
		self:Send(player,{kind="Open",key=key})
	end)
	self.gateBindings[definition.regionId]={instance=model,prompt=prompt,connection=connection}
	return true
end
function Runtime:WatchGate(model: Instance)
	if not model:IsA("Model") or self.gateWatchers[model] or not Config.ByKey[model.Name] then return end
	local queued=false
	local watch={connections={},parts={}}
	local function changed()
		if queued then return end queued=true
		task.defer(function() queued=false if not self.destroyed and self.gateWatchers[model] then self:RefreshGate(model) end end)
	end
	local names={InteractionAnchor=true,Approach=true,Threshold=true,SafeCharacterExterior=true,
		SafeCartExterior=true,DoorPresentation=true}
	local function watchPart(part)
		if not part:IsA("BasePart") or not names[part.Name] or watch.parts[part] then return end
		local connections={}
		for _,property in {"CFrame","Anchored","CanCollide","Name"} do
			table.insert(connections,part:GetPropertyChangedSignal(property):Connect(changed))
		end
		watch.parts[part]=connections
	end
	table.insert(watch.connections,model.DescendantAdded:Connect(function(part) watchPart(part) changed() end))
	table.insert(watch.connections,model.DescendantRemoving:Connect(function(part)
		if watch.parts[part] then
			for _,connection in watch.parts[part] do connection:Disconnect() end watch.parts[part]=nil
		end
		changed()
	end))
	table.insert(watch.connections,model:GetAttributeChangedSignal("InwardNormal"):Connect(changed))
	table.insert(watch.connections,model:GetAttributeChangedSignal("RegionId"):Connect(changed))
	table.insert(watch.connections,model:GetAttributeChangedSignal("LogicalRegionKey"):Connect(changed))
	for _,part in model:GetDescendants() do watchPart(part) end
	self.gateWatchers[model]=watch
	self:RefreshGate(model)
end
function Runtime:RemoveGate(model: Instance)
	local watchers=self.gateWatchers[model]
	if watchers then
		for _,connection in watchers.connections do connection:Disconnect() end
		for _,connections in watchers.parts do for _,connection in connections do connection:Disconnect() end end
		self.gateWatchers[model]=nil
	end
	local definition=Config.ByKey[model.Name]
	local binding=definition and self.gateBindings[definition.regionId]
	if binding and binding.instance==model then
		CollectionService:RemoveTag(model,"WorldProgressionGate")
		self:UnbindGate(definition.regionId) self.descriptors:Invalidate(definition.regionId)
		self.access:SetOperational(definition.regionId,false) self.summaryDirty=true
	end
end
function Runtime:ClearGateFolder()
	for _,connection in self.gateFolderConnections or {} do connection:Disconnect() end
	self.gateFolderConnections={} self.gateFolder=nil
	for model in self.gateWatchers do self:RemoveGate(model) end
end
function Runtime:BindGateFolder(folder: Instance)
	if self.gateFolder==folder then return end
	self:ClearGateFolder()
	if folder.Parent~=self.options.Map or folder.Name~="ProgressionGates" then return end
	self.gateFolder=folder
	self.gateFolderConnections={folder.ChildAdded:Connect(function(model) self:WatchGate(model) end),
		folder.ChildRemoved:Connect(function(model) self:RemoveGate(model) end)}
	for _,model in folder:GetChildren() do self:WatchGate(model) end
end
function Runtime:BindInteractions()
	local folder=ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then folder=Instance.new("Folder") folder.Name="Remotes" folder.Parent=ReplicatedStorage end
	local function remote(name)
		local object=folder:FindFirstChild(name)
		if not object then object=Instance.new("RemoteEvent") object.Name=name object.Parent=folder end
		assert(object:IsA("RemoteEvent"),"Invalid progression remote class") return object
	end
	self.request=remote(Names.WorldProgressionRequest) self.update=remote(Names.WorldProgressionUpdate)
	self.snapshotRequests={} self.panelRequests={}
	table.insert(self.connections,self.update.OnServerEvent:Connect(function(player,...)
		if select("#",...)~=0 then return end
		local now=os.clock()
		if now-(self.snapshotRequests[player] or -math.huge)<1 then return end
		self.snapshotRequests[player]=now self:Publish(player)
	end))
	table.insert(self.connections,self.request.OnServerEvent:Connect(function(player,payload,...)
		local result
		if select("#",...)~=0 then result={code="InvalidRequest",state="Rejected"}
		elseif not self.options.PurchasesEnabled then result={code="RegionUnavailable",state="Rejected"}
		else result=self.progression:Request(player,payload) end
		if type(payload)=="table" and type(payload.regionKey)=="string" and Config.ByKey[payload.regionKey] then result.key=payload.regionKey end
		self:Send(player,{kind="Result",result=result})
	end))
	local gates=self.options.Map:FindFirstChild("ProgressionGates")
	if gates then self:BindGateFolder(gates) end
	table.insert(self.connections,self.options.Map.ChildAdded:Connect(function(child)
		if child.Name=="ProgressionGates" then self:BindGateFolder(child) end
	end))
	table.insert(self.connections,self.options.Map.ChildRemoved:Connect(function(child)
		if child==self.gateFolder then self:ClearGateFolder() self.summaryDirty=true end
	end))
	table.insert(self.connections,self.options.Profile:SubscribeReady(function(player) self:Publish(player) end))
	if self.options.Profile.SubscribeDiagnostics then
		table.insert(self.connections,self.options.Profile:SubscribeDiagnostics(function(player,receipt)
			if receipt.kind=="CurrencyMigrationStarted" or receipt.kind=="CurrencyMigrationConfirmed"
				or receipt.kind=="CurrencyMigrationFailed" or receipt.kind=="LegacyGrantCompleted" then
				self:RecordEvent(receipt.kind,receipt,player)
			end
		end))
	end
	if self.options.Currency then table.insert(self.connections,self.options.Currency:SubscribeCommitted(function(player) self:Publish(player) end)) end
	if self.options.Storage then
		local disconnect=self.options.Storage:ObserveStorage({OnCommitted=function(player) self:Publish(player) end})
		table.insert(self.connections,{Disconnect=disconnect})
	end
	for _,player in Players:GetPlayers() do self:Publish(player) end
end
function Runtime:Start(operationalKeys: {string}): boolean
	if self.started or self.destroyed then return false end
	for _,key in operationalKeys do
		local definition=Config.ByKey[key]
		if not definition or (definition.index>1 and not self.descriptors:GetGate(definition.regionId)) then return false end
	end
	for _,key in operationalKeys do self.operationalKeys[key]=true self.access:SetOperational(Config.ByKey[key].regionId,true) end
	if self.options.Spawner then
		self.population=PopulationPolicy.new({Progression=self.progression,Access=self.access,
			GetPlayers=function() return Players:GetPlayers() end,GetPlayerState=function(player) return self:GetPlayerState(player) end,
			Spawner=self.options.Spawner,ValidateGeometry=function(regionId)
				return #(self.descriptors.columns[regionId] or {})>0 and #SpawnRegions.GetSpawnAreas(regionId)>0
			end,OnChanged=self.options.OnQuotaChanged})
		local ready=self.population:CheckReadiness()
		if not ready then return false end
		self.population:Step()
		local configured=self.options.Spawner.ConfigurePopulationAccess(self.population)
		if not configured then return false end
	end
	self.started=true
	if self.options.BindInteractions then self:BindInteractions() end
	table.insert(self.connections,Players.PlayerRemoving:Connect(function(player)
		self.guard:RemovePlayer(player) self.playerCarts[player]=nil
		self.progression:RemovePlayer(player)
		self.observedProgress[player]=nil
		if self.actionNotices then self.actionNotices[player]=nil end
		if self.snapshotRequests then self.snapshotRequests[player]=nil self.panelRequests[player]=nil end
	end))
	table.insert(self.connections,RunService.Heartbeat:Connect(function(dt)
		self.accumulator+=dt
		if self.accumulator<Config.REGION_GUARD_INTERVAL_SECONDS then return end
		self.accumulator%=Config.REGION_GUARD_INTERVAL_SECONDS
		if self.stepping then return end
		self.stepping=true
		local ok,failure=xpcall(function() self:RefreshEntities() self.guard:Step()
			if self.mist then self.mist:Step(self.entities or {}) end
			if self.population then self.population:Step() end
			if self.summaryDirty then
				self.summaryDirty=false
				for _,player in Players:GetPlayers() do self:Publish(player) end
			end
		end,debug.traceback)
		self.stepping=false
		if not ok and os.clock()-(self.lastErrorAt or -math.huge)>=2 then
			self.lastErrorAt=os.clock() warn("[WorldProgression] Access guard failed: "..tostring(failure))
		end
	end))
	return true
end
function Runtime:Destroy()
	self.destroyed=true
	if self.population and self.options.Spawner then
		-- Stop reservations before detaching session-only access callbacks. Never delete wild members.
		if self.options.Spawner.Stop then self.options.Spawner.Stop() end
		self.options.Spawner.ConfigurePopulationAccess(nil)
		self.population=nil
	end
	for _,connection in self.connections do connection:Disconnect() end
	self:ClearGateFolder()
	for model in self.gateWatchers do self:RemoveGate(model) end
	for regionId in self.gateBindings do self:UnbindGate(regionId) end
	for cart in self.cache do if cart.Parent then cart:SetAttribute("WorldGateDeniedNormal",nil) end end
	for _,definition in Config.Ordered do
		local gate=self.descriptors:GetGate(definition.regionId)
		local prompt=gate and gate.anchor:FindFirstChild("UnlockPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then prompt.Enabled=false end
	end
	self.guard:Destroy() if self.mist then self.mist:Destroy() end self.access:Destroy() self.progression:Destroy()
	table.clear(self.cache) table.clear(self.playerCarts)
end
return Runtime
