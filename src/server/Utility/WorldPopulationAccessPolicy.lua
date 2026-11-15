--!strict
-- Policy adapter for the existing 42-target registry/reservation scheduler.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Config.WorldProgression)
local Quota=require(ReplicatedStorage.Shared.Utility.WorldPopulationQuota)
local Selector=require(script.Parent.Parent.Systems.SpawnSelection)
local Validator=require(script.Parent.WorldPoolValidator)
local Policy={}
Policy.__index=Policy
function Policy.new(dependencies: any): any
	assert(dependencies.Progression and dependencies.Access and dependencies.GetPlayers and dependencies.GetPlayerState,"Population access requires authoritative state")
	return setmetatable({d=dependencies,now=dependencies.Now or os.clock,lastCheck=-math.huge,
		quotas={},weights={},signature=nil,compilation=dependencies.Compilation or Validator.Validate(),changes=0},Policy)
end
function Policy:CheckReadiness(): (boolean,string?)
	if not self.compilation.ready then return false,"PHASE8_POOL_VALIDATION_FAILED" end
	for _,definition in Config.Ordered do
		if definition.index>=1 and self.d.Access:IsOperational(definition.regionId) then
			if not self.compilation.pools[definition.regionId] then return false,"OPERATIONAL_POOL_MISSING" end
			if self.d.ValidateGeometry and not self.d.ValidateGeometry(definition.regionId) then return false,"OPERATIONAL_SPAWN_GEOMETRY_MISSING" end
		end
	end
	return true,nil
end
function Policy:Step(): boolean
	local now=self.now()
	if now-self.lastCheck<1 then return false end self.lastCheck=now
	local operational,players,signature={},{},{}
	for _,definition in Config.Ordered do
		if definition.index>=1 and self.d.Access:IsOperational(definition.regionId) then
			operational[definition.regionId]=true table.insert(signature,definition.regionId)
		end
	end
	local actualPlayers=table.clone(self.d.GetPlayers())
	table.sort(actualPlayers,function(a,b) return a.UserId<b.UserId end)
	for _,player in actualPlayers do
		local state=self.d.GetPlayerState(player)
		local highest=self.d.Progression:GetHighestPersonalIndex(player)
		if not state or not state.ready or not highest then continue end
		table.insert(players,{userId=player.UserId,ready=true,highestIndex=highest})
		table.insert(signature,tostring(player.UserId)..":"..tostring(highest))
	end
	local fingerprint=table.concat(signature,"|")
	if fingerprint==self.signature then return false end
	self.signature=fingerprint
	local allocation=Quota.Allocate(players,operational,42)
	self.quotas,self.weights=allocation.quotas,allocation.weights self.changes+=1
	if self.d.OnChanged then self.d.OnChanged(allocation) end
	if self.d.Spawner then self.d.Spawner.RequestPopulationReconcile("WorldAccessQuotaChanged",0) end
	return true
end
function Policy:IsEligibleNow(regionId: string): boolean
	local definition=Config.ById[regionId]
	if not definition or definition.index<1 or not self.d.Access:IsOperational(regionId) then return false end
	for _,player in self.d.GetPlayers() do
		local state=self.d.GetPlayerState(player)
		if not state or not state.ready then continue end
		local highest=self.d.Progression:GetHighestPersonalIndex(player)
		if highest and highest>=definition.index then return true end

	end
	return false
end
function Policy:GetQuota(regionId: string): number
	return if self:IsEligibleNow(regionId) then self.quotas[regionId] or 0 else 0
end
function Policy:ChooseRegion(snapshot: any,tried: {[string]:boolean}): (string?,string?,boolean?)
	local selected,largest=nil,0
	for _,definition in Config.Ordered do
		if tried[definition.regionId] then continue end
		local deficit=self:GetQuota(definition.regionId)-(snapshot.ByRegion[definition.regionId] or 0)
			-(snapshot.ReservedByRegion[definition.regionId] or 0)
		if deficit>largest then selected,largest=definition.regionId,deficit end
	end
	return selected,if selected then nil else "NO_ACCESSIBLE_REGION_DEFICIT",false
end
function Policy:SelectSpecies(regionId: string,availability: any): any
	if self:GetQuota(regionId)<=0 then return {status="NO_ELIGIBLE_SPECIES_NOW",regionId=regionId} end
	local pool=self.compilation.pools[regionId]
	if not pool then return {status="INVALID_CONFIGURATION",regionId=regionId} end
	return Selector.Select(Selector.PrepareEffective(pool,availability))
end
return Policy
