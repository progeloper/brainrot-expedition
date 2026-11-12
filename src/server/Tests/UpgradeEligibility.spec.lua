--!strict

return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
	local Eligibility = require(ReplicatedStorage.Shared.Utility.UpgradeEligibility)
	local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)

	local function playerSnapshot(balance: number): any
		return {
			status = "Ready",
			userId = 1001,
			balance = balance,
			rank = 1,
			ownedOfferIds = {},
			ownedCarts = {
				starter = { tier = 1, modelId = "CRT_001", ownedOfferIds = {} },
				tierTwo = { tier = 2, modelId = "CRT_002", ownedOfferIds = {} },
			},
			equippedCartDurableId = "starter",
			ownedEquipment = {},
		}
	end

	local function completeOffer(baseId: string, scope: any?, requirements: any?): any
		local offer = table.clone(assert(Upgrades.Get(baseId)))
		offer.definitionStatus = "Complete"
		offer.releaseStatus = "Released"
		offer.ownershipScope = scope or { kind = "PlayerWide" }
		offer.applicability = { kind = "AllOwnedCarts" }
		offer.requirements = requirements or {}
		return offer
	end

	local function readiness(offerId: string): any
		return {
			effectReadyByOfferId = { [offerId] = true },
			persistenceReadyByScope = {
				PlayerWide = true,
				ParticularOwnedCart = true,
				EquipmentOwnership = true,
			},
			currencyEarningOperational = true,
			rankProviderOperational = true,
			cartAcquisitionByTier = { [1] = true, [2] = true, [3] = true },
		}
	end

	local function expectEquivalent(actual: any, expected: any)
		expect(type(actual)).to.equal(type(expected))
		if type(expected) ~= "table" then
			expect(actual).to.equal(expected)
			return
		end
		for key, value in expected do
			expectEquivalent(actual[key], value)
		end
		for key in actual do
			expect(expected[key] ~= nil).to.equal(true)
		end
	end

	describe("Phase 7B-1 read-only upgrade eligibility", function()
		it("treats an unavailable profile as Loading instead of a zero wallet", function()
			local evaluation = Eligibility.Evaluate("CART_SPEED_1", nil, nil, {})
			expect(evaluation.outcome).to.equal("Loading")
			expect(evaluation.primaryReason.code).to.equal("PROFILE_LOADING")
		end)

		it("keeps a released offer unavailable when its effect boundary is not ready", function()
			local snapshot = playerSnapshot(1000000000)
			snapshot.ownedOfferIds.UNKNOWN_SAVED_ID = true
			local beforeBalance = snapshot.balance
			local evaluation = Eligibility.Evaluate("CART_SPEED_1", snapshot, nil, {})
			expect(evaluation.outcome).to.equal("Unavailable")
			expect(evaluation.primaryReason.code).to.equal("EFFECT_NOT_READY")
			expect(snapshot.balance).to.equal(beforeBalance)
			expect(snapshot.ownedOfferIds.UNKNOWN_SAVED_ID).to.equal(true)
		end)

		it("distinguishes Available and an exact fractional shortfall", function()
			local offer = completeOffer("CART_SPEED_1")
			local available =
				Eligibility.EvaluateOffer(offer, playerSnapshot(500000000), nil, readiness(offer.id))
			expect(available.outcome).to.equal("Available")
			local short =
				Eligibility.EvaluateOffer(offer, playerSnapshot(499999999.75), nil, readiness(offer.id))
			expect(short.outcome).to.equal("InsufficientFunds")
			expect(short.shortfall).to.equal(0.25)
			expect(short.primaryReason.message).to.equal("Need $0.25 more.")
		end)

		it("decomposes funds from non-price readiness without mutating the snapshot", function()
			local offer = completeOffer("CART_SPEED_1", nil, { requiredRank = 5 })
			local snapshot = playerSnapshot(1000000000)
			snapshot.rank = 4
			local decomposition =
				Eligibility.DecomposeOffer(offer, snapshot, nil, readiness(offer.id))
			expect(decomposition.fundsSufficient).to.equal(true)
			expect(decomposition.ready).to.equal(true)
			expect(decomposition.prerequisitesSatisfied).to.equal(false)
			expect(decomposition.pathBlocked).to.equal(false)
			expect(snapshot.balance).to.equal(1000000000)
			expect(snapshot.rank).to.equal(4)
		end)

		it(
			"separates a missing rank provider from a player below an operational rank gate",
			function()
				local offer = completeOffer("CART_SPEED_1", nil, { requiredRank = 5 })
				local missing = readiness(offer.id)
				missing.rankProviderOperational = false
				expect(Eligibility.EvaluateOffer(offer, playerSnapshot(500000000), nil, missing).outcome).to.equal(
					"Unavailable"
				)
				local lowRank = playerSnapshot(500000000)
				lowRank.rank = 4
				expect(Eligibility.EvaluateOffer(offer, lowRank, nil, readiness(offer.id)).outcome).to.equal(
					"Locked"
				)
			end
		)

		it("observes satisfied prerequisites even while the effect is unavailable", function()
			local offer = completeOffer("CART_SPEED_1", nil, { requiredRank = 1 })
			local unavailable = readiness(offer.id)
			unavailable.effectReadyByOfferId[offer.id] = false
			local snapshot = playerSnapshot(500000000)
			local observed = Eligibility.DecomposeOffer(offer, snapshot, nil, unavailable)
			expect(observed.fundsSufficient).to.equal(true)
			expect(observed.prerequisitesSatisfied).to.equal(true)
			expect(observed.ready).to.equal(false)
			expect(observed.definitionReady).to.equal(true)
			expect(observed.effectReady).to.equal(false)
			expect(observed.eligible).to.equal(false)
			expect(observed.eligibleAffordable).to.equal(false)
			expect(observed.pathBlocked).to.equal(true)
			expect(Eligibility.EvaluateOffer(offer, snapshot, nil, unavailable).outcome).to.equal(
				"Unavailable"
			)
			expect(snapshot.balance).to.equal(500000000)
		end)

		it("retains missing-provider blockage separately from sufficient funds", function()
			local offer = completeOffer("CART_SPEED_1", nil, { requiredRank = 5 })
			local missing = readiness(offer.id)
			missing.rankProviderOperational = false
			local observed = Eligibility.DecomposeOffer(offer, playerSnapshot(1000000000), nil, missing)
			expect(observed.fundsSufficient).to.equal(true)
			expect(observed.prerequisitesSatisfied).to.equal(false)
			expect(observed.ready).to.equal(false)
			expect(observed.pathBlocked).to.equal(true)
			expect(observed.nonPricePrimaryReason).to.equal("RANK_PROVIDER_UNAVAILABLE")
		end)

		it("does not infer effect readiness from already-owned presentation", function()
			local offer = completeOffer("CART_SPEED_1")
			local snapshot = playerSnapshot(500000000)
			snapshot.ownedOfferIds[offer.id] = true
			local unavailable = readiness(offer.id)
			unavailable.effectReadyByOfferId[offer.id] = false
			local observed = Eligibility.DecomposeOffer(offer, snapshot, nil, unavailable)
			expect(observed.owned).to.equal(true)
			expect(observed.prerequisitesSatisfied).to.equal(true)
			expect(observed.ready).to.equal(false)
			expect(observed.outcome).to.equal("Owned")
			expect(observed.alreadyOwned).to.equal(true)
			expect(observed.fundsSufficient).to.equal(true)
			expect(observed.effectReady).to.equal(false)
			expect(observed.eligible).to.equal(false)
			expect(observed.eligibleAffordable).to.equal(false)
			expect(Eligibility.EvaluateOffer(offer, snapshot, nil, unavailable).outcome).to.equal(
				"Owned"
			)
		end)

		it("keeps scope ownership intact while observing its actual readiness callback", function()
			for _, scope in { "PlayerWide", "ParticularOwnedCart", "EquipmentOwnership" } do
				local offer = completeOffer("CART_SPEED_1", { kind = scope })
				local snapshot = playerSnapshot(500000000)
				local target = { durableCartId = "starter", ownerUserId = snapshot.userId }
				snapshot.ownedOfferIds[offer.id] = true
				snapshot.ownedCarts.starter.ownedOfferIds[offer.id] = true
				offer.grant = { equipmentId = "HRP_TEST" }
				snapshot.ownedEquipment.HRP_TEST = true
				local supplied = readiness(offer.id)
				local observedOriginalInput = false
				supplied.effectReadyByOfferId[offer.id] = function(definition, owner, context)
					observedOriginalInput = definition == offer
						and owner == snapshot
						and context == target
					return false
				end
				local before = Eligibility.EvaluateOffer(offer, snapshot, target, supplied)
				local observed = Eligibility.DecomposeOffer(offer, snapshot, target, supplied)
				expect(observedOriginalInput).to.equal(true)
				expect(observed.owned).to.equal(true)
				expect(observed.effectReady).to.equal(false)
				expect(observed.pathReady).to.equal(false)
				expect(observed.eligibleAffordable).to.equal(false)
				expect(snapshot.ownedOfferIds[offer.id]).to.equal(true)
				expect(snapshot.ownedCarts.starter.ownedOfferIds[offer.id]).to.equal(true)
				expect(snapshot.ownedEquipment.HRP_TEST).to.equal(true)
				expectEquivalent(
					Eligibility.EvaluateOffer(offer, snapshot, target, supplied),
					before
				)
			end
		end)

		it("reports owned ready content without making it an eligible unowned purchase", function()
			local offer = completeOffer("CART_SPEED_1")
			local snapshot = playerSnapshot(500000000)
			snapshot.ownedOfferIds[offer.id] = true
			local observed = Eligibility.DecomposeOffer(offer, snapshot, nil, readiness(offer.id))
			expect(observed.owned).to.equal(true)
			expect(observed.definitionReady).to.equal(true)
			expect(observed.effectReady).to.equal(true)
			expect(observed.pathReady).to.equal(true)
			expect(observed.prerequisitesSatisfied).to.equal(true)
			expect(observed.fundsSufficient).to.equal(true)
			expect(observed.eligible).to.equal(false)
			expect(observed.eligibleAffordable).to.equal(false)
		end)

		it(
			"keeps definition and path availability independent from prerequisite satisfaction",
			function()
				local offer = completeOffer("CART_SPEED_1")
				offer.definitionStatus, offer.releaseStatus = "PendingDecision", "Deferred"
				local snapshot = playerSnapshot(500000000)
				local supplied = readiness(offer.id)
				local before = Eligibility.EvaluateOffer(offer, snapshot, nil, supplied)
				local observed = Eligibility.DecomposeOffer(offer, snapshot, nil, supplied)
				expect(observed.fundsSufficient).to.equal(true)
				expect(observed.prerequisitesSatisfied).to.equal(true)
				expect(observed.definitionReady).to.equal(false)
				expect(observed.effectReady).to.equal(true)
				expect(observed.pathReady).to.equal(false)
				expect(observed.eligibleAffordable).to.equal(false)
				expectEquivalent(Eligibility.EvaluateOffer(offer, snapshot, nil, supplied), before)
			end
		)

		it(
			"preserves purchase evaluations across reporting of available locked and invalid contexts",
			function()
				for _, scenario in
					{
						"Available",
						"InsufficientFunds",
						"Locked",
						"Loading",
						"ForeignCart",
						"MissingCart",
						"InvalidOffer",
						"InvalidBalance",
					}
				do
					local offer = completeOffer("CART_SPEED_1")
					local snapshot =
						playerSnapshot(if scenario == "InsufficientFunds" then 499999999.75 else 500000000)
					local target = nil
					local supplied = readiness(offer.id)
					if scenario == "Locked" then
						offer.requirements = { requiredRank = 5 }
					elseif scenario == "Loading" then
						snapshot.status = "Loading"
					elseif scenario == "ForeignCart" or scenario == "MissingCart" then
						offer.ownershipScope = { kind = "ParticularOwnedCart" }
						if scenario == "ForeignCart" then
							target = { durableCartId = "starter", ownerUserId = 9999 }
						end
					elseif scenario == "InvalidOffer" then
						offer = nil
					elseif scenario == "InvalidBalance" then
						snapshot.balance = nil
					end
					local before = Eligibility.EvaluateOffer(offer, snapshot, target, supplied)
					local observed = Eligibility.DecomposeOffer(offer, snapshot, target, supplied)
					expectEquivalent(
						Eligibility.EvaluateOffer(offer, snapshot, target, supplied),
						before
					)
					expect(observed.outcome).to.equal(before.outcome)
					expect(observed.eligibleAffordable).to.equal(scenario == "Available")
					expect(observed.eligible).to.equal(
						scenario == "Available" or scenario == "InsufficientFunds"
					)
					if scenario == "InsufficientFunds" then
						expect(observed.eligible).to.equal(true)
						expect(observed.fundsSufficient).to.equal(false)
					elseif scenario == "ForeignCart" or scenario == "MissingCart" then
						expect(observed.prerequisitesSatisfied).to.equal(true)
						expect(observed.pathReady).to.equal(false)
					end
				end
			end
		)

		it("keeps own-tier and equipped-tier requirements semantically distinct", function()
			local owns = completeOffer("CART_SPEED_1", nil, {
				cartQualification = { mode = "OwnsAtLeastTier", minimumTier = 2 },
			})
			local equipped = completeOffer("CART_SPEED_1", nil, {
				cartQualification = { mode = "EquippedOwnedCartAtLeastTier", minimumTier = 2 },
			})
			local snapshot = playerSnapshot(500000000)
			expect(Eligibility.EvaluateOffer(owns, snapshot, nil, readiness(owns.id)).outcome).to.equal(
				"Available"
			)
			expect(
				Eligibility.EvaluateOffer(equipped, snapshot, nil, readiness(equipped.id)).outcome
			).to.equal("Locked")
		end)

		it(
			"uses durable cart identity and rejects a borrowed cart for per-cart ownership",
			function()
				local offer = completeOffer("CARGO_1", { kind = "ParticularOwnedCart" })
				local snapshot = playerSnapshot(1500000000)
				snapshot.ownedCarts.tierTwo.ownedOfferIds[offer.id] = true
				local owned = Eligibility.ResolveOwnership(offer, snapshot, {
					durableCartId = "tierTwo",
					ownerUserId = snapshot.userId,
				})
				expect(owned.owned).to.equal(true)
				expect(Eligibility.ResolveOwnership(offer, snapshot, {
					durableCartId = "starter",
					ownerUserId = snapshot.userId,
				}).owned).to.equal(false)
				expect(Eligibility.ResolveOwnership(offer, snapshot, {
					durableCartId = "tierTwo",
					ownerUserId = 9999,
				}).code).to.equal("FOREIGN_CART")
			end
		)

		it("keeps player-wide ownership across runtime cart replacement", function()
			local offer = completeOffer("CART_SPEED_1")
			local snapshot = playerSnapshot(500000000)
			snapshot.ownedOfferIds[offer.id] = true
			expect(Eligibility.ResolveOwnership(offer, snapshot, { runtimeCart = "old" }).owned).to.equal(
				true
			)
			expect(
				Eligibility.ResolveOwnership(offer, snapshot, { runtimeCart = "replacement" }).owned
			).to.equal(true)
		end)

		it("keeps equipment ownership separate from currently equipped applicability", function()
			local offer = completeOffer("CART_SPEED_1", { kind = "EquipmentOwnership" })
			offer.grant = { kind = "EquipmentOwnership", equipmentId = "HRP_TEST" }
			local snapshot = playerSnapshot(500000000)
			snapshot.ownedEquipment.HRP_TEST = true
			snapshot.equippedEquipmentId = "HRP_OTHER"
			expect(Eligibility.ResolveOwnership(offer, snapshot, nil).owned).to.equal(true)
		end)

		it("shows Owned before temporary readiness failures", function()
			local offer = completeOffer("CART_SPEED_1")
			local snapshot = playerSnapshot(500000000)
			snapshot.ownedOfferIds[offer.id] = true
			local unavailable = readiness(offer.id)
			unavailable.effectReadyByOfferId[offer.id] = false
			expect(Eligibility.EvaluateOffer(offer, snapshot, nil, unavailable).outcome).to.equal(
				"Owned"
			)
		end)

		it("produces mobile-readable data without hover or invented absolute stats", function()
			local offer = completeOffer("CARGO_1", { kind = "ParticularOwnedCart" })
			local evaluation = Eligibility.EvaluateOffer(
				offer,
				playerSnapshot(1499999999.75),
				{ durableCartId = "tierTwo", ownerUserId = 1001 },
				readiness(offer.id)
			)
			local view = Eligibility.DescribeOffer(offer, evaluation, {
				targetCartDisplayName = "Reinforced Expedition Wagon With A Long Name",
			})
			expect(view.priceText).to.equal("$1,500,000,000")
			expect(view.effectSummary).to.equal("+1 cargo slot")
			expect(view.ownershipSummary).to.equal(
				"Applies to your selected Reinforced Expedition Wagon With A Long Name"
			)
			expect(view.primaryExplanation).to.equal("Need $0.25 more.")
			expect(view.actionLabel).to.equal("Need more Cash")
			expect(view.canActivate).to.equal(false)
			expect(view.beforeValue).to.equal(nil)
		end)

		it("formats exact large and fractional cash without changing source values", function()
			expect(CurrencyFormatter.FormatExactCash(1234567)).to.equal("$1,234,567")
			expect(CurrencyFormatter.FormatExactCash(499.75)).to.equal("$499.75")
			expect(CurrencyFormatter.FormatExactCash(0.25)).to.equal("$0.25")
		end)
	end)
	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
