--!nocheck
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Rules = require(RS.Shared.Utility.Phase13Rules)
	local Values = require(RS.Shared.Utility.Phase12Rules)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local function seed()
		local d = Schema.CreateDefault()
		d.Economy.Balance = 123.5
		for i = 1, 14 do
			local id = "owned:" .. i
			d.Collection.BrainrotInstances[id] =
				{ speciesId = if i <= 4 then "BRT_019" else "BRT_001", mutationId = "None", firstBankCompleted = true }
			if i <= 12 then
				d.Base.Slots[tostring(i)] = { brainrotId = id, accumulatedCash = i + 0.25 }
			end
		end
		d.ChariotTeam.Assignments["1"] = "owned:1"
		d.Collection.Species.BRT_019 = true
		d.WorldReadyPlaytimeSeconds = 1234
		return d
	end
	local function request(d, id, route)
		local q = Rules.QuoteRebirth(d, id, route)
		return { rewardId = id, route = route, previewRevision = q.previewRevision, inventorySignature = q.inventorySignature }
	end
	describe("Phase13 atomic pure rebirth rules", function()
		it("consumes ALL settled cash including surplus and retains every individual/progression", function()
			local d = seed()
			d.Economy.Balance = 140000000000
			local ownedBefore = Fixtures.Clone(d.Collection.BrainrotInstances)
			local total = assert(Rules.Cash(d))
			local ok, result = Rules.ApplyRebirth(d, request(d, "EXP_018", "Cash"), 10)
			expect(ok).to.equal(true)
			expect(result.sacrificedCash).to.equal(total)
			expect(d.Economy.Balance).to.equal(0)
			expect(Rules.Cash(d)).to.equal(0)
			Fixtures.AssertDeepEqual(d.Collection.BrainrotInstances, ownedBefore)
			expect(d.Base.Slots["1"].brainrotId).to.equal("owned:1")
			expect(d.ChariotTeam.Assignments["1"]).to.equal("owned:1")
			expect(Rules.GetCapacity(d)).to.equal(18)
			expect(d.Phase13.RebirthCount).to.equal(1)
			expect(d.WorldReadyPlaytimeSeconds).to.equal(1234)
		end)
		it("counts four separate IDs of one Rare species and removes ALL durable individuals", function()
			local d = seed()
			local total = assert(Rules.Cash(d))
			local q = Rules.QuoteRebirth(d, "BDS_002", "Collection")
			expect(q.ok).to.equal(true)
			expect(q.qualifyingIndividuals).to.equal(4)
			local ok, result = Rules.ApplyRebirth(d, request(d, "BDS_002", "Collection"), 20)
			expect(ok).to.equal(true)
			expect(result.sacrificedIndividuals).to.equal(14)
			expect(next(d.Collection.BrainrotInstances)).to.equal(nil)
			expect(d.Economy.Balance).to.equal(total)
			expect(d.Collection.Species.BRT_019).to.equal(true)
			expect(d.ChariotTeam.Assignments["1"]).to.equal(false)
			for _, slot in d.Base.Slots do
				expect(slot.brainrotId).to.equal(nil)
				expect(slot.accumulatedCash).to.equal(0)
			end
			expect(d.Phase13.OwnedBaseDesigns.BDS_002).to.equal(true)
			expect(d.Phase13.RebirthCount).to.equal(1)
		end)
		it("counts only unlocked occupied producers in CPS while sacrificing all owned individuals", function()
			local d = seed()
			local first = Rules.QuoteRebirth(d, "EXP_018", "Collection")
			expect(first.ownedCount).to.equal(14)
			expect(first.baseCps).to.equal(57600000)
			d.Collection.BrainrotInstances.spare = { speciesId = "BRT_032", mutationId = "Astral" }
			d.Commerce.Entitlements.INCOME_2X = true
			local nextQuote = Rules.QuoteRebirth(d, "EXP_018", "Collection")
			expect(nextQuote.ownedCount).to.equal(15)
			expect(nextQuote.baseCps).to.equal(first.baseCps)
			expect(nextQuote.productionCps).to.equal(first.baseCps * 2)
			-- The equipped individual already occupies one platform; it is not a second producer.
			expect(d.ChariotTeam.Assignments["1"]).to.equal("owned:1")
		end)
		it("rejects stale inventory, partial bases and too few quality IDs without mutation", function()
			local d = seed()
			local r = request(d, "EXP_018", "Collection")
			d.Collection.BrainrotInstances["owned:14"].mutationId = "Shiny"
			local before = Fixtures.Clone(d)
			local ok, result = Rules.ApplyRebirth(d, r, 30)
			expect(ok).to.equal(false)
			expect(result.code).to.equal("STALE_INVENTORY")
			Fixtures.AssertDeepEqual(d, before)
			d.Base.Slots["12"].brainrotId = nil
			expect(Rules.QuoteRebirth(d, "EXP_018", "Collection").code).to.equal("BASE_NOT_FULL")
			d = seed()
			d.Collection.BrainrotInstances["owned:4"].speciesId = "BRT_001"
			expect(Rules.QuoteRebirth(d, "EXP_018", "Collection").code).to.equal("MISSING_QUALITY")
		end)
		it("keeps routes independent and designs independent while expansions are sequential", function()
			local d = Schema.CreateDefault()
			d.Economy.Balance = 30000000000000
			expect(Rules.QuoteRebirth(d, "EXP_024", "Cash").code).to.equal("SEQUENTIAL_REWARD_REQUIRED")
			local ok = Rules.ApplyRebirth(d, request(d, "BDS_008", "Cash"), 40)
			expect(ok).to.equal(true)
			expect(d.Phase13.OwnedBaseDesigns.BDS_008).to.equal(true)
			expect(Rules.QuoteRebirth(d, "BDS_008", "Cash").code).to.equal("ALREADY_OWNED")
			local count = d.Phase13.RebirthCount
			local money = d.Economy.Balance
			expect(Rules.Select(d, "Design", "BDS_008")).to.equal(true)
			expect(d.Phase13.RebirthCount).to.equal(count)
			expect(d.Economy.Balance).to.equal(money)
			d = seed()
			expect(Rules.QuoteRebirth(d, "EXP_018", "Collection").ok).to.equal(true)
			expect(Rules.QuoteRebirth(d, "EXP_018", "Cash").ok).to.equal(false)
		end)
		it("grows each six-slot expansion through48 with locked slots still empty", function()
			local d = Schema.CreateDefault()
			for _, pair in
				{ { "EXP_018", 18 }, { "EXP_024", 24 }, { "EXP_030", 30 }, { "EXP_036", 36 }, { "EXP_042", 42 }, {
					"EXP_048",
					48,
				} }
			do
				d.Economy.Balance = 60000000000000
				expect(Rules.ApplyRebirth(d, request(d, pair[1], "Cash"), 50)).to.equal(true)
				expect(Rules.GetCapacity(d)).to.equal(pair[2])
				expect(Schema.ValidateLoaded(d)).to.equal(true)
			end
			expect(d.Phase13.RebirthCount).to.equal(6)
		end)
	end)
	describe("Phase13 swap conservation", function()
		for _, action in { "Swap", "SellAndReplace" } do
			it("settles once and preserves mutation/identity for " .. action, function()
				local d = seed()
				d.Collection.BrainrotInstances["owned:1"].mutationId = "Shiny"
				local wallet = d.Economy.Balance
				local accrued = d.Base.Slots["1"].accumulatedCash
				local canonical = Values.EffectiveValues("BRT_019", "Shiny").sellValue
				local r = {
					slotIndex = 1,
					outgoingId = "owned:1",
					incomingFresh = true,
					action = action,
					previewRevision = 0,
					ownerUserId = 123,
					incomingRecord = {
						ItemId = "fresh:1",
						BrainrotId = "BRT_007",
						MutationId = "Astral",
						Metadata = { MutationId = "Astral" },
					},
				}
				local ok, result = Rules.ApplySwap(d, r, 60)
				expect(ok).to.equal(true)
				expect(d.Base.Slots["1"].brainrotId).to.equal("fresh:1")
				expect(d.Base.Slots["1"].accumulatedCash).to.equal(0)
				expect(d.Economy.Balance).to.equal(
					wallet + accrued + (if action == "SellAndReplace" then canonical else 0)
				)
				expect(result.saleCash).to.equal(if action == "SellAndReplace" then canonical else 0)
				expect(d.Collection.BrainrotInstances["fresh:1"].mutationId).to.equal("Astral")
				expect(d.Collection.BrainrotInstances["owned:1"] ~= nil).to.equal(action == "Swap")
				expect(d.ChariotTeam.Assignments["1"]).to.equal(false)
				local before = Fixtures.Clone(d)
				expect(Rules.ApplySwap(d, r, 61)).to.equal(false)
				Fixtures.AssertDeepEqual(d, before)
			end)
		end
		it("moves a previously owned incoming individual without minting a second one", function()
			local d = seed()
			local r = {
				slotIndex = 1,
				outgoingId = "owned:1",
				incomingFresh = false,
				action = "Swap",
				previewRevision = 0,
				incomingRecord = { ItemId = "owned:14", BrainrotId = "BRT_001", MutationId = "None" },
			}
			expect(Rules.ApplySwap(d, r, 70)).to.equal(true)
			local count = 0
			for _ in d.Collection.BrainrotInstances do
				count += 1
			end
			expect(count).to.equal(14)
			expect(d.Base.Slots["1"].brainrotId).to.equal("owned:14")
		end)
		it("rejects overflow and ownership conflicts before credit or reward", function()
			local d = seed()
			d.Economy.Balance = 9007199254740991
			local r = {
				slotIndex = 1,
				outgoingId = "owned:1",
				incomingFresh = true,
				action = "SellAndReplace",
				previewRevision = 0,
				incomingRecord = { ItemId = "fresh:1", BrainrotId = "BRT_007", MutationId = "None" },
			}
			local before = Fixtures.Clone(d)
			local ok, result = Rules.ApplySwap(d, r, 80)
			expect(ok).to.equal(false)
			expect(result.code).to.equal("MONETARY_OVERFLOW")
			Fixtures.AssertDeepEqual(d, before)
			r.incomingRecord.ItemId = "owned:14"
			ok, result = Rules.ApplySwap(d, r, 80)
			expect(ok).to.equal(false)
			expect(result.code).to.equal("OWNERSHIP_CHANGED")
			Fixtures.AssertDeepEqual(d, before)
		end)
	end)
	describe("B06 unavailable ledger monetary boundaries", function()
		it("validates all ledger values but excludes unavailable money from Cash eligibility and sacrifice", function()
			local d = seed()
			d.Economy.Balance = 1
			d.Collection.BrainrotInstances.legacy = { speciesId = "BRT_002" }
			d.Base.Slots["48"] = { brainrotId = "legacy", accumulatedCash = 1e12 + 0.125 }
			local original = Fixtures.Clone(d)
			local q = Rules.QuoteRebirth(d, "EXP_018", "Cash")
			expect(q.code).to.equal("INSUFFICIENT_CASH")
			local expected = d.Economy.Balance
			for i = 1, 12 do
				expected += d.Base.Slots[tostring(i)].accumulatedCash
			end
			expect(Rules.Cash(d)).to.equal(expected)
			local ok = Rules.ApplyRebirth(d, request(d, "EXP_018", "Cash"), 5)
			expect(ok).to.equal(false)
			Fixtures.AssertDeepEqual(d, original)
			d.Base.Slots["48"].accumulatedCash = -1
			expect(Rules.Cash(d)).to.equal(nil)
		end)
		it("never clears newly unlocked old-locked money and refuses whole Collection sacrifice unchanged", function()
			local d = seed()
			d.Phase13.ExpansionLevel = 5
			d.Economy.Balance = 6e13
			d.Collection.BrainrotInstances.legacy = { speciesId = "BRT_002" }
			d.Base.Slots["48"] = { brainrotId = "legacy", accumulatedCash = 321.125 }
			local before = Fixtures.Clone(d)
			local q = Rules.QuoteRebirth(d, "BDS_002", "Collection")
			expect(q.code).to.equal("UNAVAILABLE_SAVED_SLOT")
			local allowed = Rules.ApplyRebirth(d, request(d, "BDS_002", "Collection"), 5)
			expect(allowed).to.equal(false)
			Fixtures.AssertDeepEqual(d, before)
			local cash = Rules.Cash(d)
			local ok, result = Rules.ApplyRebirth(d, request(d, "EXP_048", "Cash"), 5)
			expect(ok).to.equal(true)
			expect(result.sacrificedCash).to.equal(cash)
			expect(d.Economy.Balance).to.equal(0)
			expect(d.Base.Slots["48"].accumulatedCash).to.equal(321.125)
			expect(d.Base.Slots["48"].brainrotId).to.equal("legacy")
			Fixtures.AssertDeepEqual(d.Collection, before.Collection)
			expect(Rules.Cash(d)).to.equal(321.125)
		end)
	end)
end
