--!nocheck
return function()
	local Config=require(game.ReplicatedStorage.Shared.Config.WorldProgression)
	local Validator=require(script.Parent.Parent.Utility.WorldPoolValidator)
	local Selection=require(script.Parent.Parent.Systems.SpawnSelection)
	local function validate(options)
		options=options or {} options.ValidateModel=options.ValidateModel or function() return true end
		return Validator.Validate(options)
	end
	local function clonePools()
		local pools={}
		for region,pool in Config.Pools do
			local species={} for tier,ids in pool.species do species[tier]=table.clone(ids) end
			pools[region]={exclusive=pool.exclusive,tierWeights=table.clone(pool.tierWeights),species=species,
				speciesWeightOverrides=table.clone(pool.speciesWeightOverrides or {})}
		end
		return pools
	end
	it("accepts current cargo/body models without retired markers and still rejects invalid authority",function()
		local Run=game:GetService("RunService")
		local SS=game:GetService("ServerStorage")
		local Server=game:GetService("ServerScriptService"):FindFirstChild("Server")
		local boot=Server and Server:FindFirstChild("Bootstrap")
		assert(Run:IsStudio() and (not Run:IsRunning() or (game:GetAttribute("BrainrotTestDiagnosticsDisabled")==true
			and boot and boot:IsA("Script") and boot.Disabled)),"Isolated UNIT or Edit only")
		local Assets=require(script.Parent.Parent.Utility.CreatureAssetService)
		local Catalog=require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
		assert(Assets.IsEnabled(),"Current asset protocol required")
		local previous=SS:FindFirstChild("Phase13CreatureAssets")
		local previousParent=previous and previous.Parent
		if previous then previous.Parent=nil end
		local host=Instance.new("Folder") host.Name="Phase13CreatureAssets"
		local templates=Instance.new("Folder") templates.Name="Brainrots" templates.Parent=host
		local firstBody,firstCargo,firstId
		local ok,failure=xpcall(function()
			for _,pool in Config.Pools do for _,ids in pool.species do for _,id in ids do
				local definition=assert(Catalog.Get(id))
				if not templates:FindFirstChild(definition.modelRef) then
					local model=Instance.new("Model") model.Name=definition.modelRef
					local body=Instance.new("Part") body.Name="Body" body.CanQuery=true body.Anchored=true body.Parent=model
					local cargo=Instance.new("Attachment") cargo.Name="CargoAttachment" cargo.Parent=body
					model.PrimaryPart=body model.Parent=templates
					if firstBody==nil then firstBody,firstCargo,firstId=body,cargo,id end
				end
			end end end
			host.Parent=SS
			-- Use the actual default model validator rather than the selector-only test adapter.
			expect(Validator.Validate().ready).to.equal(true)
			local function rejectsFirst()
				local report=Validator.Validate()
				for _,issue in report.errors do
					if issue.speciesId==firstId and issue.code=="MODEL_CONTRACT_MISSING" then return true end
				end
				return false
			end
			local badMarker=Instance.new("Folder") badMarker.Name="CaptureAttachment" badMarker.Parent=firstBody
			expect(Validator.Validate().ready).to.equal(true) badMarker:Destroy()
			local firstModel=firstBody.Parent
			firstModel.PrimaryPart=nil expect(rejectsFirst()).to.equal(true) firstModel.PrimaryPart=firstBody
			local duplicateBody=Instance.new("Part") duplicateBody.Name="Body" duplicateBody.Parent=firstModel
			expect(rejectsFirst()).to.equal(true) duplicateBody:Destroy()
			firstBody.CanQuery=false expect(rejectsFirst()).to.equal(true) firstBody.CanQuery=true
			firstCargo.Parent=nil expect(rejectsFirst()).to.equal(true) firstCargo.Parent=firstBody
			expect(Validator.Validate().ready).to.equal(true)
		end,debug.traceback)
		host:Destroy()
		if firstCargo and firstCargo.Parent==nil then firstCargo:Destroy() end
		if previous then previous.Parent=previousParent end
		assert(ok,failure)
	end)
	it("validates exact desired launch pools and honest earlier OR reachability",function()
		local report=validate() expect(report.ready).to.equal(true) expect(#report.errors).to.equal(0)
		for _,route in report.reachability do expect(route.reachable).to.equal(true) end
		expect(report.reachability.GlitchZone.branchA.count).to.equal(1)
		expect(report.reachability.GlitchZone.branchA.reachable).to.equal(false)
		expect(report.reachability.GlitchZone.branchB.reachable).to.equal(true)
	end)
	it("rejects missing assets and does not silently erase an explicit species",function()
		local report=validate({ValidateModel=function(species) return species.id~="BRT_012" end})
		expect(report.ready).to.equal(false)
		local found=false for _,error in report.errors do if error.speciesId=="BRT_012" and error.code=="MODEL_CONTRACT_MISSING" then found=true end end
		expect(found).to.equal(true)
	end)
	it("rejects mismatched tiers, duplicate IDs and nonfinite weights",function()
		local pools=clonePools() table.insert(pools.REGION_BEACH.species.Uncommon,"BRT_001")
		pools.REGION_FOREST.tierWeights.Common=0/0
		expect(validate({Pools=pools}).ready).to.equal(false)
	end)
	it("protects exclusivity and leaves teased species outside all launch pools",function()
		local pools=clonePools() table.insert(pools.REGION_BEACH.species.Common,"BRT_007")
		expect(validate({Pools=pools}).ready).to.equal(false)
		for _,pool in Config.Pools do for _,ids in pool.species do for _,id in ids do
			expect(id~="BRT_033" and id~="BRT_034" and id~="BRT_035").to.equal(true)
		end end end
	end)
	it("preserves cap-driven exclusions through the existing selector",function()
		local pool=validate().pools.REGION_GLITCH
		local effective=Selection.PrepareEffective(pool,{blockedSpecies={BRT_032="PROFILE_POPULATION_CAP_REACHED"}})
		local sawOrdinaryLegendary=false
		for index=1,100 do
			local choice=Selection.Select(effective,function()return index/101 end)
			expect(choice.speciesId~="BRT_032").to.equal(true)
			if choice.speciesId=="BRT_031"then sawOrdinaryLegendary=true end
		end
		expect(sawOrdinaryLegendary).to.equal(true)
		local blocked={} for _,tier in pool.tiers do for _,species in tier.species do blocked[species.speciesId]="CAP" end end
		expect(Selection.PrepareEffective(pool,{blockedSpecies=blocked}).status).to.equal("NO_ELIGIBLE_SPECIES_NOW")
	end)
	it("keeps deterministic tier/species boundary draws in the existing selector",function()
		local effective=Selection.PrepareEffective(validate().pools.REGION_FOREST,{})
		expect(Selection.Select(effective,function() return 0 end).speciesId).to.equal("BRT_001")
		expect(Selection.Select(effective,function() return 1 end).speciesId).to.equal("BRT_019")
		local draws={.68,0} local index=0
		expect(Selection.Select(effective,function() index+=1 return draws[index] end).speciesId).to.equal("BRT_011")
		expect(Selection.Select(effective,function() return 1.01 end).status).to.equal("INVALID_RANDOM_VALUE")
	end)
	for _,definition in Config.Ordered do
		if definition.index<=0 then continue end
		it("matches 100,000 fixed-seed two-stage draws against the effective pool for "..definition.displayName,function()
			local report=validate() assert(report.ready,"Explicit Phase 8 pool configuration must compile")
			local compiled=report.pools[definition.regionId]
			local effective=Selection.PrepareEffective(compiled,{})
			local distribution=Selection.DescribeDistribution(compiled,effective)
			local tierProbabilities={}
			for _,row in distribution.tiers do tierProbabilities[row.tier]=row.effectiveProbability end
			-- Analytic probabilities prove the ceilings. A rare sampled count can
			-- fluctuate above N × ceiling without changing its configured odds.
			for _,row in distribution.species do
				local ceiling=compiled.ordinarySpawnCeilings[row.speciesId]
				if ceiling~=nil then expect(row.effectiveOverallProbability<=ceiling+1e-12).to.equal(true) end
			end
			if compiled.ordinarySpawnCeilings.BRT_032 and definition.regionId=="REGION_GLITCH" then
				expect(math.abs(tierProbabilities.Legendary-.60)<1e-12).to.equal(true)
			end
			local random=Random.new(8000+definition.index)
			local drawCount=100000
			local counts,speciesCounts={},{}
			for _=1,drawCount do
				local choice=Selection.Select(effective,function() return random:NextNumber() end)
				assert(choice.status=="Selected",choice.status)
				counts[choice.tier]=(counts[choice.tier] or 0)+1
				speciesCounts[choice.speciesId]=(speciesCounts[choice.speciesId] or 0)+1
			end
			local function matches(actual,p)
				if p==0 then expect(actual).to.equal(0) return end
				local expected=drawCount*p
				local tolerance=6*math.sqrt(drawCount*p*(1-p))+1
				expect(math.abs(actual-expected)<=tolerance).to.equal(true)
			end
			for tier in Config.Pools[definition.regionId].tierWeights do
				matches(counts[tier] or 0,tierProbabilities[tier] or 0)
			end
			for _,row in distribution.species do
				matches(speciesCounts[row.speciesId] or 0,row.effectiveOverallProbability)
			end
		end)
	end
end
