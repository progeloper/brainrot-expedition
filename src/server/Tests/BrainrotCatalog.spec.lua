--!nocheck
return function()
	local Brainrots = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local rates = {
		1.8,
		2,
		2.2,
		2.3,
		1.9,
		1.8,
		2,
		2.2,
		2.3,
		1.9,
		4,
		4.5,
		5,
		5.2,
		4.3,
		4,
		4.5,
		5,
		10.8,
		12,
		13.2,
		13.8,
		11.4,
		10.8,
		12,
		36,
		40,
		44,
		46,
		38,
		135,
		150,
		165,
		720,
		2250,
	}
	local sales = {
		108,
		120,
		132,
		138,
		114,
		108,
		120,
		132,
		138,
		114,
		240,
		270,
		300,
		312,
		258,
		240,
		270,
		300,
		648,
		720,
		792,
		828,
		684,
		648,
		720,
		2160,
		2400,
		2640,
		2760,
		2280,
		8100,
		9000,
		9900,
		43200,
		135000,
	}

	describe("Phase 6B authoritative species rarity", function()
		it("contains the complete deterministic roster and workbook economy values", function()
			local definitions = Brainrots.GetAll()
			expect(#definitions).to.equal(35)
			local seen, tiers, statuses = {}, {}, {}
			for index, definition in definitions do
				local expectedId = string.format("BRT_%03d", index)
				expect(definition.id).to.equal(expectedId)
				expect(seen[definition.id]).to.equal(nil)
				seen[definition.id] = true
				tiers[definition.tier] = (tiers[definition.tier] or 0) + 1
				statuses[definition.launchStatus] = (statuses[definition.launchStatus] or 0) + 1
				expect(definition.cashPerSecond).to.equal(rates[index] * 1000000)
				expect(definition.sellValue).to.equal(sales[index] * 500000)
			end
			for tier, count in
				{
					Common = 10,
					Uncommon = 8,
					Rare = 7,
					Epic = 5,
					Legendary = 3,
					Mythic = 1,
					Secret = 1,
				}
			do
				expect(tiers[tier]).to.equal(count)
			end
			expect(statuses.Live).to.equal(32)
			expect(statuses.Teased).to.equal(3)
		end)

		it("returns the required definition for the current BRT_007 species", function()
			local definition = Brainrots.Get("BRT_007")
			expect(definition.id).to.equal("BRT_007")
			expect(definition.displayName).to.equal("Tung Tung Tung Sahur")
			expect(definition.tier).to.equal("Common")
			expect(definition.cashPerSecond).to.equal(2000000)
			expect(definition.sellValue).to.equal(60000000)
			expect(definition.launchStatus).to.equal("Live")
			expect(definition.behaviourId).to.equal("Wanderer")
			expect(definition.expeditionRole).to.equal("Sprinter")
			expect(definition.homeRegionId).to.equal("REGION_FOREST")
			expect(definition.allowedRegionIds[1]).to.equal("REGION_FOREST")
			expect(definition.regionAssignmentStatus).to.equal("Approved")
		end)

		it("defines the four 6A-2 pilot species with the same relative economy in scaled units", function()
			local expected = {
				BRT_007 = { "Tung Tung Tung Sahur", "Common", "Sprinter", 2, 120 },
				BRT_011 = { "Glorbo Fruttodrillo", "Uncommon", "Trickster", 4, 240 },
				BRT_015 = { "Strawberelli Flamingelli", "Uncommon", "Wrangler", 4.3, 258 },
				BRT_016 = { "Gorillo Subwoofero", "Uncommon", "Hauler", 4, 240 },
			}
			for id, values in expected do
				local definition = assert(Brainrots.Get(id))
				expect(definition.displayName).to.equal(values[1])
				expect(definition.tier).to.equal(values[2])
				expect(definition.behaviourId).to.equal(
					if id == "BRT_007" then "Wanderer" else "ReactiveRunner"
				)
				expect(definition.expeditionRole).to.equal(values[3])
				expect(definition.cashPerSecond).to.equal(values[4] * 1000000)
				expect(definition.sellValue).to.equal(values[5] * 500000)
				expect(definition.modelRef).to.equal(id)
			end
		end)

		it("assigns Reactive Runner explicitly without deriving it from rarity or role", function()
			for index = 11, 18 do
				local definition = assert(Brainrots.Get(string.format("BRT_%03d", index)))
				expect(definition.behaviourId).to.equal("ReactiveRunner")
			end
			expect(Brainrots.Get("BRT_007").behaviourId).to.equal("Wanderer")
			expect(Brainrots.Get("BRT_007").expeditionRole).to.equal("Sprinter")
			for index = 19, 25 do
				local definition = assert(Brainrots.Get(string.format("BRT_%03d", index)))
				expect(definition.behaviourId).to.equal("Sprinter")
			end
			expect(Brainrots.Get("BRT_028").behaviourId).to.equal("Camouflage")
			expect(Brainrots.Get("BRT_029").behaviourId).to.equal("DecoySplit")
			expect(Brainrots.Get("BRT_030").behaviourId).to.equal("Wanderer")
			for index = 31, 33 do
				expect(Brainrots.Get(string.format("BRT_%03d", index)).behaviourId).to.equal(
					"LegendaryPursuit"
				)
			end
			expect(Brainrots.Get("BRT_031").launchStatus).to.equal("Live")
			expect(Brainrots.Get("BRT_032").launchStatus).to.equal("Live")
			expect(Brainrots.Get("BRT_033").launchStatus).to.equal("Teased")
		end)

		it("resolves canonical named rarity without an alias or unknown fallback", function()
			local expected = {
				BRT_007 = "Common",
				BRT_011 = "Uncommon",
				BRT_019 = "Rare",
				BRT_028 = "Epic",
				BRT_031 = "Legendary",
				BRT_034 = "Mythic",
				BRT_035 = "Secret",
			}
			for id, rarity in expected do
				expect(Brainrots.GetRarity(id)).to.equal(rarity)
			end
			expect(Brainrots.GetRarity("BRT-007")).to.equal("Common")
			expect(Brainrots.GetRarity("BRT-019")).to.equal("Rare")
			expect(Brainrots.GetRarity("BRT_999")).to.equal(nil)
			expect(Brainrots.GetRarity("INVALID")).to.equal(nil)
		end)

		it("keeps rarity, baseline wild behaviour and expedition role independent", function()
			local definition = assert(Brainrots.Get("BRT_007"))
			expect(definition.tier).to.equal("Common")
			expect(definition.behaviourId).to.equal("Wanderer")
			expect(definition.expeditionRole).to.equal("Sprinter")
			expect(definition.rarity).to.equal(nil)
			expect(definition.rank).to.equal(nil)
		end)

		it("normalizes workbook, case and whitespace variants at one boundary", function()
			local expected = Brainrots.Get("BRT_007")
			for _, rawId in { "BRT_007", "BRT-007", "brt_007", "brt-007", " BRT-007 " } do
				expect(Brainrots.NormalizeId(rawId)).to.equal("BRT_007")
				expect(Brainrots.Get(rawId)).to.equal(expected)
			end
		end)

		it("rejects malformed and unknown IDs without substituting BRT_007", function()
			for _, rawId in { "BRT_999", "INVALID", "", "007", "BRT_7", "BRT_0007", "BRT_A07" } do
				expect(Brainrots.Get(rawId)).to.equal(nil)
			end
			expect(Brainrots.Get(nil)).to.equal(nil)
			expect(Brainrots.Get(7)).to.equal(nil)
			expect(Brainrots.NormalizeId(nil)).to.equal(nil)
		end)

		it("returns a disposable ordered array containing immutable definitions", function()
			local first = Brainrots.GetAll()
			first[1] = nil
			local second = Brainrots.GetAll()
			expect(#second).to.equal(35)
			expect(second[1].id).to.equal("BRT_001")
			expect(function()
				second[1].cashPerSecond = 999
			end).to.throw()
			expect(function()
				table.insert(second[1].allowedRegionIds, "Forest")
			end).to.throw()
		end)

		it("preserves approved names and binds explicit Phase 8 natural homes and pools", function()
			local expected = {
				{ "Bingus Baguette", "REGION_FOREST" },
				{ "Tralalero Toad", "REGION_FOREST" },
				{ "Cappuccino Capybara", "REGION_FOREST" },
				{ "Ballerina Banana", "REGION_FOREST" },
				{ "Bombardiro Pigeon", "REGION_FOREST" },
				{ "Spaghetti Crocodilo", "REGION_FOREST" },
				{ "Tung Tung Tung Sahur", "REGION_FOREST" },
				{ "Lirili Larila", "REGION_FOREST" },
				{ "Chimpanzini Bananini", "REGION_FOREST" },
				{ "Talpa Di Fero", "REGION_FOREST" },
				{ "Glorbo Fruttodrillo", "REGION_FOREST" },
				{ "Frigo Camelo", "REGION_BEACH" },
				{ "Cavallo Virtuoso", "REGION_FOREST" },
				{ "Bandito Bobritto", "REGION_BEACH" },
				{ "Strawberelli Flamingelli", "REGION_BEACH" },
				{ "Gorillo Subwoofero", "REGION_SWAMP" },
				{ "Orangutini Ananassini", "REGION_SWAMP" },
				{ "Zibra Zubra Zibralini", "REGION_SWAMP" },
				{ "Trenostruzzo Turbo 3000", "REGION_FOREST" },
				{ "Bisonte Giuppitere", "REGION_BEACH" },
				{ "Cacto Hipopotamo", "REGION_SWAMP" },
				{ "Trulimero Trulicina", "REGION_SWAMP" },
				{ "Giraffa Celeste", "REGION_JUNGLE" },
				{ "Nooo My Hotspot", "REGION_JUNGLE" },
				{ "Salamino Penguino", "REGION_ARCTIC" },
				{ "Rhino Toasterino", "REGION_SWAMP" },
				{ "Tralalero Tralala", "REGION_JUNGLE" },
				{ "Tartaragno", "REGION_JUNGLE" },
				{ "Cocofanto Elefanto", "REGION_ARCTIC" },
				{ "Tractoro Dinosauro", "REGION_JUNGLE" },
				{ "Odin Din Din Dun", "REGION_VOLCANO" },
				{ "La Vaca Saturno Saturnita", "REGION_GLITCH" },
				{ "Dragon Cannelloni", "REGION_ARCTIC" },
				{ "Orcalero Orcala", "REGION_BEACH" },
				{ "La Secret Combinasion", "REGION_SWAMP" },
			}
			local expectedPools = {
				REGION_FOREST = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 19 },
				REGION_BEACH = { 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20 },
				REGION_SWAMP = { 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 26, 28, 30 },
				REGION_JUNGLE = { 8, 9, 10, 14, 15, 16, 17, 18, 19, 20, 22, 23, 24, 25, 26, 27, 28, 30 },
				REGION_ARCTIC = { 16, 17, 18, 20, 22, 23, 24, 25, 26, 28, 29, 30 },
				REGION_VOLCANO = { 22, 23, 24, 25, 26, 28, 30, 31 },
				REGION_GLITCH = { 23, 24, 25, 26, 28, 30, 31, 32 },
			}
			for index, values in expected do
				local definition = assert(Brainrots.Get(string.format("BRT_%03d", index)))
				expect(definition.displayName).to.equal(values[1])
				expect(definition.homeRegionId).to.equal(values[2])
				if index <= 32 then
					local count = 0
					for regionId, ids in expectedPools do
						local included = table.find(ids, index) ~= nil
						expect(table.find(definition.allowedRegionIds, regionId) ~= nil).to.equal(included)
						if included then count += 1 end
					end
					expect(#definition.allowedRegionIds).to.equal(count)
				else
					expect(definition.allowedRegionIds[1]).to.equal(values[2])
					expect(#definition.allowedRegionIds).to.equal(1)
				end
				expect(definition.regionAssignmentStatus).to.equal("Approved")
			end
		end)

		it("preserves legacy access paths as references to the same definitions", function()
			local preferred = Brainrots.Get("BRT_007")
			expect(Brainrots.GetDefinition("BRT-007")).to.equal(preferred)
			expect(Brainrots.GetById("brt_007")).to.equal(preferred)
			expect(Brainrots.Definitions.BRT_007).to.equal(preferred)
			expect(Brainrots.ById.BRT_007).to.equal(preferred)
			expect(Brainrots.BRT_007).to.equal(preferred)
			expect(Brainrots.ResolveId("BRT-007")).to.equal("BRT_007")
		end)

		it("enables exactly the 32 Live species for natural-spawn readiness", function()
			for _, definition in Brainrots.GetAll() do
				expect(Brainrots.IsDeclaredSpawnEnabled(definition.id)).to.equal(
					definition.launchStatus == "Live"
				)
			end
			expect(Brainrots.IsDeclaredSpawnEnabled("BRT_999")).to.equal(false)
		end)
	end)
end
