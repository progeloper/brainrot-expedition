--!nocheck
return function()
	local Regions = require(game.ReplicatedStorage.Shared.Config.Regions)
	local Progression = require(game.ReplicatedStorage.Shared.Config.WorldProgression)
	local operational = { REGION_FOREST = true }
	for _, key in Progression.OperationalKeys do operational[Progression.ByKey[key].regionId] = true end
	local Catalog = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)

	describe("Phase 6F-1 current regions", function()
		it(
			"binds seven hunting regions and protected Camp to existing MapBlockout floors",
			function()
				local all = Regions.GetAll()
				expect(#all).to.equal(8)
				local hunting = 0
				for _, definition in all do
					if definition.kind == "Hunting" then
						hunting += 1
						expect(definition.naturalSpawnAllowed).to.equal(true)
						expect(#definition.boundaryRefs).to.equal(1)
						expect(#definition.spawnAreaRefs).to.equal(1)
						expect(definition.spawnSelection ~= nil).to.equal(true)
					else
						expect(definition.id).to.equal("REGION_CAMP")
						expect(definition.naturalSpawnAllowed).to.equal(false)
						expect(#definition.boundaryRefs).to.equal(1)
						expect(#definition.spawnAreaRefs).to.equal(0)
						expect(definition.spawnSelection).to.equal(nil)
					end
				end
				expect(hunting).to.equal(7)
			end
		)

		it("normalizes only explicit current aliases", function()
			expect(Regions.NormalizeId("REGION_GLITCH")).to.equal("REGION_GLITCH")
			expect(Regions.NormalizeId("GlitchZone")).to.equal("REGION_GLITCH")
			expect(Regions.NormalizeId(" Glitch Zone ")).to.equal("REGION_GLITCH")
			expect(Regions.NormalizeId("forest")).to.equal("REGION_FOREST")
			expect(Regions.Get("BEACH").id).to.equal("REGION_BEACH")
		end)

		it("matches exact Phase 8 weights for operational hunting regions", function()
			local expected = {
				REGION_BEACH = { .4, .4, .2, 0, 0, 0, 0 },
				REGION_FOREST = { .68, .26, .06, 0, 0, 0, 0 },
				REGION_SWAMP = { .15, .3, .4, .15, 0, 0, 0 },
				REGION_JUNGLE = { .05, .15, .45, .35, 0, 0, 0 },
				REGION_ARCTIC = { 0, .05, .25, .7, 0, 0, 0 },
				REGION_VOLCANO = { 0, 0, .1, .65, .25, 0, 0 },
				REGION_GLITCH = { 0, 0, .05, .35, .6, 0, 0 },
			}
			local tiers = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
			for regionId, values in expected do
				if not operational[regionId] then continue end
				local selection = assert(
					Regions.Get(regionId).spawnSelection,
					"approved hunting region must define spawn selection"
				)
				local total = 0
				for index, tier in tiers do
					expect(selection.tierWeights[tier]).to.equal(values[index])
					total += values[index]
				end
				expect(math.abs(total - 1) < 1e-9).to.equal(true)
			end
		end)

		it("backs every positive tier weight with a mapped Live species", function()
			for _, region in Regions.GetAll() do
				if region.kind ~= "Hunting" or not operational[region.id] then
					continue
				end
				for tier, weight in region.spawnSelection.tierWeights do
					if weight <= 0 then
						continue
					end
					local found = false
					for _, definition in Catalog.GetAll() do
						if
							definition.tier == tier
							and definition.launchStatus == "Live"
							and definition.spawnEnabled
							and table.find(definition.allowedRegionIds, region.id) ~= nil
						then
							found = true
							break
						end
					end
					expect(found).to.equal(true)
				end
			end
		end)

		it("does not convert legacy or unknown locations", function()
			for _, legacy in
				{
					"Meme Meadows",
					"Brainrot Badlands",
					"Glitchwood",
					"The Rift",
					"Desert",
				}
			do
				expect(Regions.NormalizeId(legacy)).to.equal(nil)
				expect(Regions.Get(legacy)).to.equal(nil)
			end
		end)

		it("returns disposable ordering with immutable definitions and references", function()
			local first = Regions.GetAll()
			first[1] = nil
			local second = Regions.GetAll()
			expect(#second).to.equal(8)
			expect(function()
				second[1].enabled = false
			end).to.throw()
			expect(function()
				table.insert(second[1].spawnAreaRefs, "Invented.Path")
			end).to.throw()
		end)
	end)
end
