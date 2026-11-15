--!nocheck
return function()
	local Rarities = require(game.ReplicatedStorage.Shared.Config.Rarities)

	describe("Phase 6B rarity metadata", function()
		it("converts only the six audited legacy numeric tiers", function()
			local expected = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
			for tier, rarity in expected do
				expect(Rarities.FromLegacyTier(tier)).to.equal(rarity)
			end
			for _, value in { 0, -1, 1.5, 7, 8, math.huge, -math.huge } do
				expect(Rarities.FromLegacyTier(value)).to.equal(nil)
			end
			expect(Rarities.FromLegacyTier(0 / 0)).to.equal(nil)
			expect(Rarities.FromLegacyTier(nil)).to.equal(nil)
			expect(Rarities.FromLegacyTier("3")).to.equal(nil)
		end)

		it("normalizes supported names without defaulting malformed values", function()
			expect(Rarities.Normalize("common")).to.equal("Common")
			expect(Rarities.Normalize(" COMMON ")).to.equal("Common")
			expect(Rarities.Normalize("legendary")).to.equal("Legendary")
			expect(Rarities.Normalize("MYTHIC")).to.equal("Mythic")
			expect(Rarities.Normalize("secret")).to.equal("Secret")
			expect(Rarities.Normalize("Ultra")).to.equal(nil)
			expect(Rarities.Normalize(1)).to.equal(nil)
		end)

		it("keeps Secret outside the standard progression order", function()
			local expected = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Celestial" }
			expect(#Rarities.StandardOrder).to.equal(7)
			for rank, rarity in expected do
				expect(Rarities.StandardOrder[rank]).to.equal(rarity)
				expect(Rarities.GetStandardRank(rarity)).to.equal(rank)
				expect(Rarities.IsStandard(rarity)).to.equal(true)
			end
			expect(Rarities.IsStandard("Secret")).to.equal(false)
			expect(Rarities.GetStandardRank("Secret")).to.equal(nil)
			expect(Rarities.GetDisplayRank("Secret")).to.equal(8)
			expect(Rarities.GetStandardRank("Ultra")).to.equal(nil)
		end)
	end)
end
