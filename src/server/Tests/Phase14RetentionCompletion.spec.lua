--!nocheck
-- Exact contract tests against actual pure rules/profile extension. Native Play,
-- touch/input and persistent-session evidence are separate acceptance rows.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Rules = require(RS.Shared.Utility.RetentionRules)
	local Goals = require(RS.Shared.Utility.RetentionGoals)
	local Progression = require(RS.Shared.Utility.Phase13Rules)
	local Money = require(RS.Shared.Utility.CurrencyDenomination)
	local Progress = require(script.Parent.Parent.Data.Phase12Progress)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local function bank(data, id, species, at, mutation)
		local receipt = Progress.RecordFirstBank(data, {
			ItemId = id,
			BrainrotId = species or "BRT_001",
			Metadata = { MutationId = mutation or "None", AcquisitionKind = "Hunt" },
		}, nil, at)
		if receipt then
			data.Collection.BrainrotInstances[id] = {
				speciesId = receipt.speciesId,
				mutationId = receipt.mutationId,
				firstBankCompleted = true,
				firstBankedAt = receipt.firstBankedAt,
			}
		end
		return receipt
	end
	local function payday(data, at, id, earnings)
		return Rules.RecordPlatformSettlement(data, {
			source = "OwnPlatformIncome",
			ownerUserId = 814014,
			at = at,
			operationId = id or "earnings:1",
			earnings = earnings or 1,
		})
	end
	local function fullDay(data, day)
		local at = day * 86400 + 5
		bank(data, tostring(day) .. ":a", "BRT_001", at)
		bank(data, tostring(day) .. ":b", "BRT_001", at)
		bank(data, tostring(day) .. ":c", "BRT_002", at)
		payday(data, at, "settlement:" .. day)
		assert(Rules.ClaimSupply(data, at))
	end
	describe("Phase14 exact three quests and authoritative reward basis", function()
		it("A, A, B pays 5U only at B and stores at most two base species", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = 0.375
			bank(data, "a", "BRT_001", 86401, "None")
			bank(data, "b", "BRT_001", 86402, "Golden")
			expect(data.Economy.Balance).to.equal(0.375)
			expect(data.Retention.Day.field_research.count).to.equal(1)
			local receipt = bank(data, "c", "BRT_002", 86403)
			expect(data.Economy.Balance).to.equal(1250000000.375)
			expect(#receipt.retention.transitions).to.equal(2)
			expect(#data.Retention.Day.field_research.species).to.equal(2)
			for i = 4, 20 do
				bank(data, "extra" .. i, "BRT_003", 86404)
			end
			expect(#data.Retention.Day.field_research.species).to.equal(2)
			expect(data.Economy.Balance).to.equal(1250000000.375)
			expect(Schema.ValidateLoaded(data)).to.equal(true)
		end)
		it("A, B, A pays Research on the second bank and Home on the third", function()
			local data = Schema.CreateDefault()
			bank(data, "a", "BRT_001", 86401)
			bank(data, "b", "BRT_002", 86402)
			expect(data.Economy.Balance).to.equal(500000000)
			expect(data.Retention.Day.bring_them_home.paid).to.equal(false)
			bank(data, "c", "BRT_001", 86403)
			expect(data.Economy.Balance).to.equal(1250000000)
		end)
		for _, row in
			{
				{ "Forest", 250000000 },
				{ "Beach", 2500000000 },
				{ "Swamp", 10000000000 },
				{ "Jungle", 50000000000 },
				{ "Arctic", 100000000000 },
				{ "Volcano", 250000000000 },
				{ "GlitchZone", 500000000000 },
			}
		do
			it("freezes exact " .. row[1] .. " unit from permanent proof; a full ordinary day is 7U", function()
				local data = Schema.CreateDefault()
				data.WorldProgression.PersonalUnlocks[row[1]] = { source = "purchase" }
				fullDay(data, 1)
				expect(data.Retention.Day.unitCash).to.equal(row[2])
				expect(data.Economy.Balance).to.equal(row[2] * 7)
				expect(Schema.ValidateLoaded(data)).to.equal(true)
			end)
		end
		it("does not freeze on reads or migration; only the next day observes a later unlock", function()
			local data = Schema.CreateDefault()
			Rules.Migrate(data)
			Goals.Options(data)
			expect(data.Retention.Day).to.equal(nil)
			bank(data, "freeze:a", "BRT_001", 86401)
			data.WorldProgression.PersonalUnlocks.Beach = { source = "purchase" }
			payday(data, 86402)
			Rules.ClaimSupply(data, 86403)
			expect(data.Retention.Day.unitCash).to.equal(250000000)
			bank(data, "freeze:b", "BRT_001", 172801)
			expect(data.Retention.Day.unitCash).to.equal(2500000000)
		end)
		it("duplicate receipt after midnight cannot create or advance a new day", function()
			local data = Schema.CreateDefault()
			bank(data, "original", "BRT_001", 86399)
			local before = Fixtures.Clone(data)
			expect(bank(data, "original", "BRT_001", 86401)).to.equal(nil)
			Fixtures.AssertDeepEqual(data, before)
		end)
		it("own-platform settlement pays once; zero and unrelated sources do not qualify", function()
			local data = Schema.CreateDefault()
			bank(data, "eligible", "BRT_001", 86401)
			for _, proof in
				{
					{ source = "BrainrotSale", earnings = 5 },
					{ source = "OwnPlatformIncome", earnings = 0 },
					{ source = "StarterPack", earnings = 3000000000 },
					{ source = "Admin", earnings = 5 },
				}
			do
				proof.operationId, proof.ownerUserId, proof.at = "invalid", 814014, 86402
				Rules.RecordPlatformSettlement(data, proof)
			end
			expect(data.Retention.Day.camp_payday.count).to.equal(0)
			payday(data, 86402)
			payday(data, 86402)
			expect(data.Economy.Balance).to.equal(250000000)
		end)
		it("ordinary earnings plus U share one Currency mutation; unrelated credits are excluded", function()
			local data = Schema.CreateDefault()
			bank(data, "eligible", "BRT_001", 86401)
			local commits = 0
			local owner = {
				CommitMutation = function(_, _, mutator)
					local prior = Fixtures.Clone(data)
					local accepted, result = mutator(data)
					if not accepted then
						data = prior
						return result
					end
					assert(Schema.ValidateLoaded(data))
					commits += 1
					result.revision = commits
					return result
				end,
			}
			local player = { UserId = 814014 }
			Currency:_ResetForTests(owner)
			local ok, why = pcall(function()
				for _, source in { "BrainrotSale", "Refund", "StarterPack", "RetentionReward", "Admin" } do
					assert(Currency:TryCredit(player, 1, source).committed, "ordinary fixture credit rejected")
				end
				expect(data.Retention.Day.camp_payday.count).to.equal(0)
				data.Base.Slots["1"].accumulatedCash = 10.25
				local before = data.Economy.Balance
				local result = Currency:TryCreditWithSource(player, 10.25, "PlatformIncomeClaim", function(current)
					if current.Base.Slots["1"].accumulatedCash ~= 10.25 then
						return false, "SOURCE_CHANGED"
					end
					current.Base.Slots["1"].accumulatedCash = 0
					return true
				end, {
					source = "OwnPlatformIncome",
					ownerUserId = player.UserId,
					earnings = 10.25,
					at = 86402,
					operationId = "ownplatform:1",
				})
				expect(commits).to.equal(6)
				expect(result.balance - before).to.equal(250000010.25)
				expect(data.Base.Slots["1"].accumulatedCash).to.equal(0)
				expect(data.Retention.Day.camp_payday.paid).to.equal(true)
			end)
			Currency:_ResetForTests()
			assert(ok, why)
		end)
	end)
	describe("Phase14 trusted Studio identity and schema guards", function()
		it("negative Studio identity qualifies through Currency; another owner proof does not", function()
			local data = Schema.CreateDefault()
			bank(data, "studio:eligible", "BRT_001", 86401)
			local owner = {
				CommitMutation = function(_, _, mutator)
					local accepted, result = mutator(data)
					assert(accepted and Schema.ValidateLoaded(data), "negative Studio identity mutation rejected")
					result.revision = 1
					return result
				end,
			}
			local player = { UserId = -2 }
			Currency:_ResetForTests(owner)
			local ok, why = pcall(function()
				local wrong = {
					source = "OwnPlatformIncome",
					ownerUserId = -1,
					earnings = 1,
					at = 86402,
					operationId = "wrong-owner",
				}
				assert(
					Currency:TryCreditWithSource(player, 1, "PlatformIncomeClaim", function()
						return true
					end, wrong).committed,
					"ordinary E rejected"
				)
				expect(data.Retention.Day.camp_payday.paid).to.equal(false)
				local proof = {
					source = "OwnPlatformIncome",
					ownerUserId = -2,
					earnings = 1.25,
					at = 86402,
					operationId = "studio-payday",
				}
				assert(
					Currency:TryCreditWithSource(player, 1.25, "PlatformIncomeClaim", function()
						return true
					end, proof).committed,
					"Studio own E rejected"
				)
				expect(data.Economy.Balance).to.equal(250000002.25)
				expect(data.Retention.Day.camp_payday.paid).to.equal(true)
			end)
			Currency:_ResetForTests()
			assert(ok, why)
		end)
		it(
			"actual profile schema rejects forged goals, unowned selections, features and invalid supply fields",
			function()
				for _, corrupt in
					{
						function(data)
							data.Progression.TrackedUpgradeId = "MadeUp:Cheap"
						end,
						function(data)
							data.Retention.SelectedTitle = "P14_TITLE_COLLECTOR"
						end,
						function(data)
							data.Retention.FeaturedSpeciesId = "BRT_001"
						end,
						function(data)
							data.Retention.Supplies.lifetimeClaims = -1
						end,
						function(data)
							data.Retention.Milestones.FAKE = { earned = true, source = "forged" }
						end,
					}
				do
					local data = Schema.CreateDefault()
					corrupt(data)
					expect(Schema.ValidateLoaded(data)).to.equal(false)
				end
				for _, legacy in { "CART_SPEED_1", "CART_SPEED_5", "CARGO_3" } do
					local data = Schema.CreateDefault()
					data.Progression.TrackedUpgradeId = legacy
					expect(Schema.ValidateLoaded(data)).to.equal(true)
				end
			end
		)
	end)
	describe("Phase14 outgoing platform settlement", function()
		for _, action in { "Swap", "SellAndReplace" } do
			it("qualifies positive platformE once while separating sale cash for " .. action, function()
				local data = Schema.CreateDefault()
				bank(data, "outgoing", "BRT_001", 86401)
				bank(data, "incoming", "BRT_002", 86401)
				data.Base.Slots["1"].brainrotId, data.Base.Slots["1"].accumulatedCash = "outgoing", 10.25
				local before = data.Economy.Balance
				local request = {
					action = action,
					slotIndex = 1,
					outgoingId = "outgoing",
					incomingFresh = false,
					previewRevision = data.Phase13.EligibilityRevision,
					ownerUserId = 814014,
					operationId = "swap:payday",
					incomingRecord = { ItemId = "incoming", BrainrotId = "BRT_002", MutationId = "None" },
				}
				local accepted, result = Progression.ApplySwap(data, request, 86402)
				expect(accepted).to.equal(true)
				expect(data.Economy.Balance - before).to.equal(250000010.25 + result.saleCash)
				expect(data.Retention.Day.camp_payday.paid).to.equal(true)
				expect(Progression.ApplySwap(data, request, 86403)).to.equal(false)
			end)
		end
	end)
	describe("Phase14 supplies, rollover and once-only durable ownership", function()
		it("14 full Forest dates total 100U = 25B and both milestone cosmetics once", function()
			local data = Schema.CreateDefault()
			for day = 1, 14 do
				fullDay(data, day)
			end
			expect(data.Economy.Balance).to.equal(25000000000)
			expect(data.Retention.Supplies.lifetimeClaims).to.equal(14)
			expect(data.Commerce.Entitlements.P14_FLAG_CAMP).to.equal(true)
			expect(data.Commerce.Entitlements.P14_BASE_EXPEDITION).to.equal(true)
			expect(data.Commerce.Appearance.Flag).to.equal(nil)
			expect(data.Commerce.Appearance.BaseBanner).to.equal(nil)
			expect(Schema.ValidateLoaded(data)).to.equal(true)
		end)
		it("14 supply-only dates total 16U = 4B; missed dates pause lifetime claims", function()
			local data = Schema.CreateDefault()
			data.Collection.Species.BRT_001 = true
			Rules.Migrate(data)
			for n = 1, 14 do
				assert(Rules.ClaimSupply(data, (n * 3) * 86400 + 1))
			end
			expect(data.Economy.Balance).to.equal(4000000000)
			expect(data.Retention.Supplies.lifetimeClaims).to.equal(14)
			expect(data.Retention.Day.bring_them_home.count).to.equal(0)
			local before = Fixtures.Clone(data)
			expect(Rules.ClaimSupply(data, 42 * 86400 + 2)).to.equal(false)
			Fixtures.AssertDeepEqual(data, before)
		end)
		it("claims 21 and 28 remain 2U without extra cosmetics or conversion", function()
			local data = Schema.CreateDefault()
			data.Collection.Species.BRT_001 = true
			Rules.Migrate(data)
			for n = 1, 28 do
				local _, receipt = Rules.ClaimSupply(data, n * 86400 + 1)
				if n == 21 or n == 28 then
					expect(receipt.amountCash).to.equal(500000000)
					expect(receipt.cosmeticId).to.equal(nil)
				end
			end
			expect(data.Economy.Balance).to.equal(8000000000)
			local owned = 0
			for _, value in data.Commerce.Entitlements do
				if value then
					owned += 1
				end
			end
			expect(owned).to.equal(2)
		end)
		it("an old-day pending reward survives midnight and recovers at its original unit once", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = Money.MAX_AMOUNT
			for i = 1, 3 do
				bank(data, "overflow:" .. i, "BRT_001", 86401)
			end
			local id, reward = next(data.Retention.PendingRewards)
			expect(reward.amountCash).to.equal(750000000)
			data.WorldProgression.PersonalUnlocks.Beach = { source = "purchase" }
			bank(data, "newday", "BRT_002", 172801)
			expect(data.Retention.Day.unitCash).to.equal(2500000000)
			expect(data.Retention.PendingRewards[id].dayKey).to.equal(1)
			data.Economy.Balance = 0.25
			expect(Rules.RecoverPending(data, id)).to.equal(true)
			expect(data.Economy.Balance).to.equal(750000000.25)
			expect(Rules.RecoverPending(data, id)).to.equal(false)
			expect(data.Retention.Day.bring_them_home.paid).to.equal(false)
			expect(Schema.ValidateLoaded(data)).to.equal(true)
		end)
		it("claim 7 cash and cosmetic recover together without automatic equip", function()
			local data = Schema.CreateDefault()
			data.Collection.Species.BRT_001 = true
			Rules.Migrate(data)
			for n = 1, 6 do
				assert(Rules.ClaimSupply(data, n * 86400 + 1))
			end
			data.Economy.Balance = Money.MAX_AMOUNT
			local accepted, result = Rules.ClaimSupply(data, 7 * 86400 + 1)
			expect(accepted).to.equal(true)
			expect(result.code).to.equal("SUPPLY_PENDING")
			expect(data.Retention.Supplies.lifetimeClaims).to.equal(7)
			expect(data.Commerce.Entitlements.P14_FLAG_CAMP).to.equal(nil)
			data.Economy.Balance = 0
			expect(Rules.RecoverPending(data)).to.equal(true)
			expect(data.Economy.Balance).to.equal(500000000)
			expect(data.Commerce.Entitlements.P14_FLAG_CAMP).to.equal(true)
			expect(Rules.RecoverPending(data)).to.equal(false)
			expect(data.Commerce.Appearance.Flag).to.equal(nil)
		end)
		it("new players cannot claim or freeze; trusted bank history makes legacy players eligible", function()
			local data = Schema.CreateDefault()
			expect(Rules.ClaimSupply(data, 86401)).to.equal(false)
			expect(data.Retention.Day).to.equal(nil)
			data.Collection.Species.BRT_001 = true
			Rules.Migrate(data)
			expect(Rules.ClaimSupply(data, 86401)).to.equal(true)
			expect(data.Retention.Day.bring_them_home.count).to.equal(0)
		end)
	end)
	describe("Phase14 permanent milestones, single selection, goal references andrebirth", function()
		it("awards exact discovery thresholds and actual anomaly once without cash or invented history", function()
			local data = Schema.CreateDefault()
			for i = 1, 30 do
				data.Collection.Species[string.format("BRT_%03d", i)] = true
			end
			Rules.Migrate(data)
			for _, id in
				{
					"P14_TITLE_COLLECTOR",
					"P14_NAMEPLATE_FIELD_RESEARCH",
					"P14_TITLE_EXPEDITION_EXPERT",
					"P14_PLAQUE_MASTER_COLLECTOR",
				}
			do
				expect(data.Retention.Milestones[id].earned).to.equal(true)
			end
			expect(data.Retention.Milestones.P14_BADGE_ANOMALY_FOUND).to.equal(nil)
			expect(next(data.Collection.SpeciesMutations)).to.equal(nil)
			data.Collection.SpeciesMutations.BRT_001 = { Normal = true, Golden = true }
			expect(#Rules.ReconcileMilestones(data)).to.equal(1)
			expect(#Rules.ReconcileMilestones(data)).to.equal(0)
			expect(data.Economy.Balance).to.equal(0)
			expect(Rules.EquipMilestone(data, "Title", "P14_TITLE_COLLECTOR")).to.equal(true)
			expect(Rules.ResolveTitle(data)).to.equal("Collector")
			expect(Rules.EquipMilestone(data, "Title", "P14_TITLE_EXPEDITION_EXPERT")).to.equal(true)
			expect(Rules.ResolveTitle(data)).to.equal("Expedition Expert")
			expect(Rules.EquipMilestone(data, "Title", "None")).to.equal(true)
			expect(Rules.ResolveTitle(data)).to.equal(nil)
			expect(Schema.ValidateLoaded(data)).to.equal(true)
		end)
		it("Rift Patron retains accepted ownership within one title selection", function()
			local data = Schema.CreateDefault()
			data.Commerce.Entitlements.VIP, data.Commerce.Appearance.VIPTitle = true, "On"
			expect(Rules.ResolveTitle(data)).to.equal("Rift Patron")
			Rules.EquipMilestone(data, "Title", "None")
			expect(Rules.ResolveTitle(data)).to.equal(nil)
			Rules.EquipMilestone(data, "Title", "RiftPatron")
			expect(Rules.ResolveTitle(data)).to.equal("Rift Patron")
		end)
		it("uses actual prices and balances, one goal, and explicit sacrifice warnings", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = 50.25
			expect(Goals.Pin(data, "Speed:1")).to.equal(true)
			local goal = Goals.Resolve(data, data.Progression.TrackedUpgradeId)
			expect(goal.price).to.equal(500000000)
			expect(goal.balance).to.equal(50.25)
			expect(goal.shortfall).to.equal(499999949.75)
			expect(Goals.Pin(data, "MadeUp:Cheap")).to.equal(false)
			expect(data.Progression.TrackedUpgradeId).to.equal("Speed:1")
			data.Base.Slots["1"].accumulatedCash = 100
			goal = Goals.Resolve(data, "Rebirth:EXP_018:Cash")
			expect(goal.balance).to.equal(150.25)
			expect(goal.cashSacrificeAll).to.equal(true)
			goal = Goals.Resolve(data, "Rebirth:EXP_018:Collection")
			expect(goal.currency).to.equal("Owned qualifying brainrots")
			expect(goal.prerequisites.requiredIndividuals).to.equal(4)
			expect(goal.prerequisites.qualifyingIndividuals).to.equal(0)
		end)
		it("cash rebirth preserves frozen quests, supplies, discovery, milestones and access proof", function()
			local data = Schema.CreateDefault()
			fullDay(data, 1)
			data.WorldProgression.PersonalUnlocks.Beach = { source = "purchase" }
			local retention, collection, unlocks =
				Fixtures.Clone(data.Retention),
				Fixtures.Clone(data.Collection.Species),
				Fixtures.Clone(data.WorldProgression.PersonalUnlocks)
			data.Economy.Balance = 126000000000
			expect(
				Progression.ApplyRebirth(
					data,
					{ rewardId = "EXP_018", route = "Cash", previewRevision = data.Phase13.EligibilityRevision },
					86420
				)
			).to.equal(true)
			Fixtures.AssertDeepEqual(data.Retention, retention)
			Fixtures.AssertDeepEqual(data.Collection.Species, collection)
			Fixtures.AssertDeepEqual(data.WorldProgression.PersonalUnlocks, unlocks)
			expect(data.Economy.Balance).to.equal(0)
		end)
	end)
end
