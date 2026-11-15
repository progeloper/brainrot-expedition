--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CreatureAssets=require(script.Parent.CreatureAssetService)
local Config=require(ReplicatedStorage.Shared.Config.WorldProgression)
local Catalog=require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Selector=require(script.Parent.Parent.Systems.SpawnSelection)
local Validator={}
local tiers={"Common","Uncommon","Rare","Epic","Legendary","Mythic"}
local function modelValid(definition)
	local model=CreatureAssets.GetTemplate(definition.id)
	if not model or not model:IsA("Model") or not model.PrimaryPart then return false end
	local count,body=0,nil
	for _,instance in model:GetDescendants() do
		if instance.Name=="Body" then
			if not instance:IsA("BasePart") or not instance.CanQuery then return false end
			count+=1 body=instance
		end
	end
	return count==1 and body:FindFirstChild("CargoAttachment")~=nil
		and body.CargoAttachment:IsA("Attachment")
end
function Validator.Validate(options: any?): any
	local settings=options or {}
	local pools=settings.Pools or Config.Pools
	local validateModel=settings.ValidateModel or modelValid
	local errors,compiled,reachability,seenModels={},{},{},{}
	local function issue(code,region,id) table.insert(errors,{code=code,regionId=region,speciesId=id}) end
	for _,definition in Config.Ordered do
		if definition.index<=0 then continue end
		local pool=pools[definition.regionId]
		if not pool then issue("POOL_MISSING",definition.regionId,nil) continue end
		local total,candidates,seen=0,{},{}
		for _,tier in tiers do
			local weight=pool.tierWeights[tier]
			if type(weight)~="number" or weight~=weight or weight<0 or weight==math.huge then
				issue("INVALID_WEIGHT",definition.regionId,nil)
			else total+=weight end
			local ids=pool.species[tier] or {}
			if type(weight)=="number" and weight>0 and #ids==0 then issue("EMPTY_WEIGHTED_TIER",definition.regionId,nil) end
			for _,id in ids do
				if seen[id] then issue("DUPLICATE_SPECIES",definition.regionId,id) end seen[id]=true
				local species=Catalog.Get(id)
				if not species or species.id~=id or species.launchStatus~="Live" or not species.spawnEnabled then
					issue("SPECIES_NOT_LIVE",definition.regionId,id) continue
				end
				if species.tier~=tier then issue("RARITY_MISMATCH",definition.regionId,id) end
				if seenModels[id]==nil then seenModels[id]=validateModel(species)==true end
				if not seenModels[id] then issue("MODEL_CONTRACT_MISSING",definition.regionId,id) end
				table.insert(candidates,{id=id,tier=species.tier,assignmentStatus="Approved",
					homeRegionId=Config.HomeBySpecies[id],allowedRegionIds=Config.AllowedBySpecies[id],
					spawnEnabled=true,launchStatus="Live",naturalSpawnEligible=true,
					modelReady=seenModels[id],behaviourReady=true,locationReady=true,globalWithinTierWeight=1})
			end
		end
		if math.abs(total-1)>1e-9 then issue("WEIGHT_SUM_MISMATCH",definition.regionId,nil) end
		if (pool.tierWeights.Secret or 0)~=0 then issue("SECRET_WEIGHT_FORBIDDEN",definition.regionId,nil) end
		if settings.ValidateGeometry and not settings.ValidateGeometry(definition.regionId) then issue("REGION_GEOMETRY_MISSING",definition.regionId,nil) end
		local compilation=Selector.CompileRegion(definition.regionId,{id=definition.regionId,kind="Hunting",
			enabled=true,naturalSpawnAllowed=true,spawnSelection={tierWeights=pool.tierWeights,speciesWeightOverrides=pool.speciesWeightOverrides or {}}},candidates)
		if not compilation.pool then issue("SELECTOR_COMPILE_FAILED",definition.regionId,nil) else compiled[definition.regionId]=compilation.pool end
	end
	for id,home in Config.HomeBySpecies do
		local allowed=Config.AllowedBySpecies[id]
		if not Config.ById[home] or not allowed or not table.find(allowed,home) then issue("HOME_NOT_ALLOWED",home,id) end
	end
	for region,pool in pools do
		local exclusive=pool.exclusive
		if not exclusive then continue end
		for other,otherPool in pools do
			local found=false
			for _,ids in otherPool.species do if table.find(ids,exclusive) then found=true break end end
			if (region==other and not found) or (region~=other and found) then issue("EXCLUSIVE_VIOLATION",other,exclusive) end
		end
	end
	for _,definition in Config.Ordered do
		if definition.index<=1 then continue end
		local earlier={}
		for _,prior in Config.Ordered do
			if prior.index>=1 and prior.index<definition.index then
				local pool=pools[prior.regionId]
				if pool then for tier,ids in pool.species do for _,id in ids do earlier[id]=tier end end end
			end
		end
		local function branch(requirement)
			if not requirement then return nil end
			local count=0
			for _,tier in earlier do if (Config.OrdinaryRarity[tier] or 0)>=Config.OrdinaryRarity[requirement[1]] then count+=1 end end
			return {count=count,required=requirement[2],reachable=count>=requirement[2]}
		end
		local a,b=branch(definition.branchA),branch(definition.branchB)
		reachability[definition.key]={branchA=a,branchB=b,reachable=a.reachable or (b and b.reachable) or false}
		if not reachability[definition.key].reachable then issue("NO_EARLIER_OR_ROUTE",definition.regionId,nil) end
	end
	return {ready=#errors==0,errors=errors,pools=compiled,reachability=reachability}
end
return Validator
