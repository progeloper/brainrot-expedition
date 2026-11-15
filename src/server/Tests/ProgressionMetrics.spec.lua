--!strict

return function()
	local ProgressionMetrics = require(script.Parent.Parent.Analytics.ProgressionMetrics)

	local function fixture(starting: any?): any
		local state = starting or {}
		return ProgressionMetrics.new({
			joinAt = state.joinAt or -5,
			profileReadyAt = state.profileReadyAt or -1,
			worldReadyAt = state.worldReadyAt or 0,
			measurementStartedAt = state.worldReadyAt or 0,
			observationId = state.observationId or "test-observation",
			buildId = "test-build",
			configurationId = "test-config",
			environment = "Development",
			profileOrigin = state.profileOrigin or "ControlledTestFixture",
			startingState = {
				wallet = state.wallet or 0,
				settledPlatformCash = state.platformCash or 0,
				occupiedSlotCount = state.occupiedSlotCount or 0,
				bankedIndividualCount = state.bankedIndividualCount or 0,
				passiveIncomeRate = state.passiveIncomeRate or 0,
				ownedProgression = state.ownedProgression,
			},
			startingOwnedIndividuals = state.startingOwnedIndividuals or {},
		})
	end

	local function observeOffer(metrics: any, at: number, values: any?)
		local state = values or {}
		metrics:ObserveOfferState({
			at = at,
			offerId = state.offerId or "TEST_CARGO",
			targetKey = state.targetKey or "fixture-cart",
			termsVersion = state.termsVersion or "terms-v1",
			price = state.price or 500,
			ownedAtStart = state.ownedAtStart == true,
			owned = state.owned == true,
			fundsSufficient = state.fundsSufficient == true,
			ready = state.ready ~= false,
			prerequisitesSatisfied = state.prerequisitesSatisfied ~= false,
			pathBlocked = state.pathBlocked == true,
			primaryReason = state.primaryReason,
			isBaseline = state.isBaseline,
			displayOrder = state.displayOrder,
		})
	end

	describe("Phase 7G-1 progression measurement", function()
		it(
			"measures camp service and one bank-to-bank interval per completed outing cycle",
			function()
				local metrics = fixture()
				observeOffer(metrics, 0, { price = 1000 })
				for index = 1, 2 do
					local base = (index - 1) * 20
					metrics:ObserveRegion({ state = "OutsideCamp", at = base })
					metrics:ObserveRegion({
						state = "InHuntingRegion",
						regionId = "TEST",
						at = base + 1,
					})
					metrics:ObserveMilestone({
						kind = "ValidSleepHit",
						eventId = "sleep:" .. index,
						at = base + 2,
					})
					metrics:ObserveMilestone({
						kind = "WildAcquired",
						eventId = "outing-acquire:" .. index,
						individualId = "outing-individual:" .. index,
						at = base + 2.5,
					})
					metrics:ObserveEconomic({
						kind = "PlatformIncomeProduced",
						eventId = "field:" .. index,
						at = base + 3,
						amount = 20 * index,
					})
					metrics:ObserveRegion({ state = "AtCamp", at = base + 10 })
					metrics:ObserveMilestone({
						kind = "BankedPlaced",
						eventId = "bank:" .. index,
						at = base + 11,
					})
					metrics:ObserveMilestone({
						kind = "BankedPlaced",
						eventId = "bank-repeat:" .. index,
						at = base + 12,
					})
					metrics:ObserveEconomic({
						kind = "PlatformIncomeProduced",
						eventId = "camp:" .. index,
						at = base + 13,
						amount = 10,
					})
				end
				expect(metrics:BuildReport(35).similarExpeditionsRemaining.status).to.equal(
					"INSUFFICIENT_DATA"
				)
				metrics:ObserveRegion({ state = "OutsideCamp", at = 40 })
				local report = metrics:BuildReport(40)
				expect(report.activity.completedOutings).to.equal(2)
				expect(report.activity.bankToBankCount).to.equal(1)
				expect(report.activity.bankToBankDurationTotal).to.equal(20)
				expect(report.activity.outings[1].campServiceDuration).to.equal(10)
				expect(report.activity.outings[1].firstBankAfterReturnAt).to.equal(11)
				expect(report.activity.outings[1].firstSleepAt).to.equal(2)
				expect(report.activity.outings[1].firstAcquisitionAt).to.equal(2.5)
				expect(report.activity.outings[1].acquisitionOperations).to.equal(1)
				expect(report.activity.outings[2].bankToBankDuration).to.equal(20)
				expect(report.similarExpeditionsRemaining.sampleCount).to.equal(2)
				expect(report.similarExpeditionsRemaining.representativeOrdinaryCurrencyPerCycle).to.equal(
					40
				)
				expect(report.similarExpeditionsRemaining.estimatedSimilarCycles).to.equal(25)
			end
		)

		it("retains complete zero-earning cycles in the recent comparable median", function()
			local metrics = fixture()
			observeOffer(metrics, 0, { price = 1000 })
			for index, amount in { 100, 0, 0, 100 } do
				local base = (index - 1) * 20
				metrics:ObserveRegion({ state = "OutsideCamp", at = base })
				metrics:ObserveRegion({
					state = "InHuntingRegion",
					regionId = "TEST",
					at = base + 1,
				})
				if amount > 0 then
					metrics:ObserveEconomic({
						kind = "PlatformIncomeProduced",
						eventId = "cycle:" .. index,
						at = base + 2,
						amount = amount,
					})
				end
				metrics:ObserveRegion({ state = "AtCamp", at = base + 10 })
			end
			metrics:ObserveRegion({ state = "OutsideCamp", at = 80 })
			expect(#metrics.recentComparableCurrency).to.equal(3)
			expect(metrics.recentComparableCurrency[1]).to.equal(0)
			expect(metrics.recentComparableCurrency[2]).to.equal(0)
			expect(metrics.recentComparableCurrency[3]).to.equal(100)
			local report = metrics:BuildReport(80)
			expect(report.activity.completedOutings).to.equal(4)
			expect(report.similarExpeditionsRemaining.status).to.equal("INSUFFICIENT_DATA")
			expect(report.similarExpeditionsRemaining.estimatedSimilarCycles).to.equal(nil)
		end)

		it("keeps interrupted camp-service intervals out of ordinary cycle estimates", function()
			local metrics = fixture()
			metrics:ObserveRegion({ state = "OutsideCamp", at = 0 })
			metrics:ObserveRegion({ state = "InHuntingRegion", regionId = "TEST", at = 1 })
			metrics:ObserveRegion({ state = "AtCamp", at = 10 })
			metrics:BeginDeparture(15, "ServerShutdown")
			local outing = metrics:BuildReport(30).activity.outings[1]
			expect(outing.campServiceObserved).to.equal("Interrupted")
			expect(outing.campServiceTerminationReason).to.equal("ServerShutdown")
			expect(outing.nextDepartureAt).to.equal(nil)
			expect(outing.comparable).to.equal(false)
		end)

		it(
			"labels short observation rates and never adds collection to currency production",
			function()
				local metrics = fixture({ wallet = 400.5, platformCash = 120.25 })
				metrics:ObserveEconomic({
					kind = "PlatformIncomeProduced",
					eventId = "income",
					at = 30,
					amount = 60,
				})
				metrics:ObserveEconomic({
					kind = "WalletCredit",
					eventId = "sale",
					source = "BrainrotSale",
					at = 90,
					amount = 120,
					balanceAfter = 520.5,
				})
				metrics:ObserveEconomic({
					kind = "WalletDebit",
					eventId = "purchase",
					at = 120,
					amount = 500,
					balanceAfter = 20.5,
				})
				metrics:ObserveEconomic({
					kind = "PlatformCollection",
					eventId = "collect",
					at = 150,
					amount = 180.25,
					balanceAfter = 200.75,
				})
				metrics:SetEndingState(200.75, 0, 180)
				local report = metrics:BuildReport(180)
				expect(report.economy.walletCredits).to.equal(300.25)
				expect(report.rates.nonTransferCashInPerPlayableMinute).to.equal(60)
				expect(report.rates.shortWindow).to.equal(true)
				expect(report.rates.firstTenMinuteCoverage).to.equal("INCOMPLETE")
			end
		)
		it("rejects replayed sequenced cash after bounded event IDs have been evicted", function()
			local metrics = fixture()
			for index = 1, 140 do
				metrics:ObserveEconomic({
					kind = "WalletCredit",
					eventId = "cash:" .. index,
					stream = "Currency",
					operationSequence = index,
					at = index,
					amount = 1,
					balanceAfter = index,
				})
			end
			expect(metrics:ObserveEconomic({
				kind = "WalletCredit",
				eventId = "cash:1",
				stream = "Currency",
				operationSequence = 1,
				at = 141,
				amount = 1,
				balanceAfter = 1,
			})).to.equal(false)
			metrics:SetEndingState(140, 0, 142)
			local report = metrics:BuildReport(142)
			expect(report.economy.otherWalletCredits).to.equal(140)
			expect(report.economy.reconciled).to.equal(true)
			expect(report.coverage.dedupEvictions > 0).to.equal(true)
		end)

		it(
			"retains a reconciled cutoff when a late unsequenced rejection warns about closed coverage",
			function()
				local metrics = fixture({
					wallet = 600.5,
					platformCash = 129,
					startingOwnedIndividuals = { saved = true },
				})
				observeOffer(metrics, 0, { fundsSufficient = true, isBaseline = true })
				for index = 1, 140 do
					expect(metrics:ObserveEconomic({
						kind = "PlatformIncomeProduced",
						eventId = "settlement:" .. index,
						stream = "Income",
						operationSequence = index,
						at = index,
						amount = 1.25,
						byIndividual = { saved = 1.25 },
					})).to.equal(true)
				end
				metrics:ObserveEconomic({
					kind = "PlatformCollection",
					eventId = "collect:1",
					stream = "Currency",
					operationSequence = 1,
					at = 300,
					amount = 20,
					balanceAfter = 620.5,
				})
				metrics:SetEndingState(620.5, 284, 600, 284, false)
				local cutoff = metrics:BuildReport(600)
				-- JSON captures this already-built detached report, not the mutable aggregator.
				local HttpService = game:GetService("HttpService")
				local cutoffBefore = HttpService:JSONEncode(cutoff)
				expect(cutoff.coverage.dedupEvictions > 0).to.equal(true)
				expect(cutoff.economy.reconciled).to.equal(true)
				expect(cutoff.economy.accountingCoverage).to.equal("OBSERVED_RECEIPTS")
				expect(cutoff.coverage.unsequencedReplayWindowExceeded).to.equal(false)
				local key = cutoff.offers[1].offerKey
				metrics:ObservePurchase({
					kind = "Attempt",
					requestId = "late",
					offerKey = key,
					at = 610,
				})
				expect(metrics:ObservePurchase({
					kind = "Result",
					requestId = "late",
					offerKey = key,
					at = 611,
					accepted = false,
					code = "CONTEXT_EXPIRED",
				})).to.equal(true)
				metrics:BeginDeparture(620, "Disconnect")
				metrics:SetEndingState(620.5, 284, 620, 284)
				local closed = metrics:BuildReport(621)
				expect(closed.coverage.unsequencedReplayWindowExceeded).to.equal(true)
				expect(closed.economy.accountingCoverage).to.equal("INCOMPLETE_COVERAGE")
				expect(closed.economy.reconciled).to.equal(false)
				for _, field in
					{
						"endingWallet",
						"endingSettledPlatformCash",
						"platformIncomeGenerated",
						"platformIncomeFromStartingAssets",
						"platformCashCollected",
						"walletCredits",
						"walletDebits",
						"walletAdjustments",
						"platformAdjustments",
						"otherWalletCredits",
						"expectedEndingWallet",
						"expectedEndingPlatformCash",
					}
				do
					expect(closed.economy[field]).to.equal(cutoff.economy[field])
				end
				expect(closed.economy.walletResidual).to.equal(0)
				expect(closed.economy.platformResidual).to.equal(0)
				expect(closed.economy.combinedResidual).to.equal(0)
				expect(closed.economy.walletDebits).to.equal(0)
				expect(closed.offers[1].attempts).to.equal(1)
				expect(closed.offers[1].rejections.CONTEXT_EXPIRED).to.equal(1)
				expect(closed.offers[1].owned).to.equal(false)
				expect(closed.offers[1].purchaseCommittedAt).to.equal(nil)
				expect(closed.offers[1].persistence).to.equal("NotPurchased")
				expect(closed.persistence.pendingPurchaseCount).to.equal(0)
				expect(HttpService:JSONEncode(cutoff)).to.equal(cutoffBefore)
				expect(cutoff.offers[1].attempts).to.equal(0)
				expect(cutoff.offers[1].rejections.CONTEXT_EXPIRED).to.equal(nil)
				expect(cutoff.economy.reconciled).to.equal(true)
			end
		)

		it(
			"records commit-time affordability from actual before-context after wallet deduction",
			function()
				local metrics = fixture({ wallet = 100 })
				observeOffer(metrics, 0, {})
				metrics:ObservePurchase({
					kind = "Result",
					requestId = "commit",
					offerKey = "TEST_CARGO|fixture-cart|terms-v1",
					at = 20,
					accepted = true,
					chargedAmount = 500,
					balanceBefore = 520.5,
					balanceAfter = 20.5,
					ready = true,
					prerequisitesSatisfied = true,
					commitRevision = 7,
					persistence = "Confirmed",
				})
				local report = metrics:BuildReport(30)
				expect(report.offers[1].firstEligibleAffordableAt).to.equal(20)
				expect(report.offers[1].purchaseCommitRevision).to.equal(7)
				expect(report.offers[1].purchaseSavedAt).to.equal(nil)
				expect(report.persistence.pendingPurchaseCount).to.equal(0)
			end
		)

		it(
			"marks exact unique identity coverage unavailable when bounded identity detail overflows",
			function()
				local metrics = fixture()
				for index = 1, 140 do
					metrics:ObserveMilestone({
						kind = "WildAcquired",
						eventId = "wild:" .. index,
						stream = "Interaction",
						operationSequence = index,
						individualId = "individual:" .. index,
						speciesId = "BRT_001",
						at = index,
					})
				end
				local report = metrics:BuildReport(150)
				expect(report.activity.counts.acquisitionOperations).to.equal(140)
				expect(report.activity.uniqueIndividualAcquisitions).to.equal(nil)
				expect(report.coverage.uniqueIndividualCountExact).to.equal(false)
				expect(report.activity.uniqueSpeciesAcquired).to.equal(1)
			end
		)

		it(
			"closes absent scope candidates and keeps periodic balance reads separate from report closure",
			function()
				local metrics = fixture({ wallet = 600 })
				observeOffer(metrics, 0, { fundsSufficient = true, targetKey = "cart-a" })
				observeOffer(metrics, 10, { fundsSufficient = true, targetKey = "cart-b" })
				metrics:ReconcileOfferCandidates({ "TEST_CARGO|cart-b|terms-v1" }, 10)
				metrics:SetEndingState(600, 0, 15, 0, false)
				local report = metrics:BuildReport(20)
				expect(report.offers[1].currentAffordable).to.equal(false)
				expect(report.offers[1].cumulativeEligibleAffordableDuration).to.equal(10)
				expect(report.referenceNextAffordablePurchase.targetKey).to.equal("cart-b")
				expect(report.session.clocks.reportClosedAt).to.equal(nil)
			end
		)

		it(
			"does not claim reconciled money when authoritative ending state is unavailable",
			function()
				local metrics = fixture({ wallet = 1 })
				metrics.coverage.endingAuthorityUnavailable = true
				local report = metrics:BuildReport(10)
				expect(report.economy.walletResidual).to.equal(0)
				expect(report.economy.reconciled).to.equal(false)
				expect(report.economy.accountingCoverage).to.equal("INCOMPLETE_COVERAGE")
			end
		)
		it("closes superseded terms and excludes them from current references", function()
			local metrics = fixture({ wallet = 600 })
			observeOffer(metrics, 0, { fundsSufficient = true })
			observeOffer(metrics, 10, { termsVersion = "terms-v2", price = 750 })
			local report = metrics:BuildReport(20)
			expect(report.offers[1].currentAffordable).to.equal(false)
			expect(report.offers[1].cumulativeEligibleAffordableDuration).to.equal(10)
			expect(report.referenceNextAffordablePurchase.termsVersion).to.equal("terms-v2")
		end)

		it(
			"does not backdate prerequisites for a candidate first observed after baseline",
			function()
				local metrics = fixture({ wallet = 600 })
				observeOffer(metrics, 60, { fundsSufficient = true })
				local offer = metrics:BuildReport(70).offers[1]
				expect(offer.prerequisitesSatisfiedAtStart).to.equal(false)
				expect(offer.firstPrerequisiteSatisfiedAt).to.equal(60)
				expect(offer.firstFundsSufficientAt).to.equal(60)
			end
		)

		it(
			"retains an exact early purchase acknowledgement without inferring one from revisions",
			function()
				local metrics = fixture({ wallet = 600 })
				observeOffer(metrics, 0, { fundsSufficient = true })
				local key = "TEST_CARGO|fixture-cart|terms-v1"
				metrics:ObservePurchase({
					kind = "SaveConfirmed",
					requestId = "early",
					offerKey = key,
					at = 12,
				})
				metrics:ObservePurchase({
					kind = "Result",
					requestId = "early",
					offerKey = key,
					at = 10,
					accepted = true,
					chargedAmount = 500,
					balanceAfter = 100,
				})
				local report = metrics:BuildReport(20)
				expect(report.persistence.pendingPurchaseCount).to.equal(0)
				expect(report.offers[1].persistence).to.equal("Confirmed")
				expect(report.offers[1].purchaseSavedAt).to.equal(12)
				expect(report.offers[1].purchaseConfirmationLatency).to.equal(2)
				local pending = fixture({ wallet = 600 })
				observeOffer(pending, 0, { fundsSufficient = true })
				pending:ObservePurchase({
					kind = "Result",
					requestId = "pending",
					offerKey = key,
					at = 10,
					accepted = true,
					chargedAmount = 500,
					balanceAfter = 100,
				})
				pending:ObserveDiagnostic({
					kind = "SaveConfirmed",
					eventId = "unrelated",
					revision = 999,
					at = 15,
				})
				expect(pending:BuildReport(20).offers[1].persistence).to.equal("Pending")
			end
		)

		it(
			"confirms reversed purchase origins using increasing acknowledgement delivery sequences",
			function()
				local metrics = fixture({ wallet = 1000 })
				for index = 1, 2 do
					local offerId = "TEST_CARGO_" .. index
					observeOffer(metrics, 0, { offerId = offerId, fundsSufficient = true })
					expect(metrics:ObservePurchase({
						kind = "Result",
						requestId = "purchase:" .. index,
						offerKey = offerId .. "|fixture-cart|terms-v1",
						at = index * 10,
						accepted = true,
						chargedAmount = 500,
						balanceAfter = 1000 - 500 * index,
						commitRevision = index,
						operationSequence = index,
					})).to.equal(true)
				end
				expect(metrics:BuildReport(25).persistence.pendingPurchaseCount).to.equal(2)
				for deliveryIndex, purchaseIndex in { 2, 1 } do
					local receipt = {
						kind = "SaveConfirmed",
						requestId = "purchase:" .. purchaseIndex,
						offerKey = "TEST_CARGO_" .. purchaseIndex .. "|fixture-cart|terms-v1",
						at = 29 + deliveryIndex,
						operationSequence = 2 + deliveryIndex,
						purchaseOperationSequence = purchaseIndex,
					}
					expect(metrics:ObservePurchase(receipt)).to.equal(true)
					expect(metrics:ObservePurchase(receipt)).to.equal(false)
				end
				local report = metrics:BuildReport(35)
				expect(report.persistence.pendingPurchaseCount).to.equal(0)
				expect(report.offers[1].persistence).to.equal("Confirmed")
				expect(report.offers[1].purchaseSavedAt).to.equal(31)
				expect(report.offers[2].persistence).to.equal("Confirmed")
				expect(report.offers[2].purchaseSavedAt).to.equal(30)
				expect(report.economy.walletDebits).to.equal(1000)
				expect(report.economy.endingWallet).to.equal(0)
			end
		)

		it("keeps a mid-outing observation censored instead of a comparable normal trip", function()
			local metrics = fixture()
			metrics:ObserveEconomic({
				kind = "PlatformIncomeProduced",
				eventId = "before",
				at = 5,
				amount = 100,
			})
			metrics:ObserveRegion({ state = "InHuntingRegion", regionId = "TEST", at = 10 })
			metrics:ObserveRegion({ state = "AtCamp", at = 20 })
			local outing = metrics:BuildReport(20).activity.outings[1]
			expect(outing.terminationReason).to.equal("TrackingStartedMidOuting")
			expect(outing.platformProduction).to.equal(0)
			expect(outing.comparable).to.equal(false)
		end)

		it(
			"excludes starting-asset liquidation and test grants from similar-cycle estimates",
			function()
				local metrics = fixture({ startingOwnedIndividuals = { old = true } })
				observeOffer(metrics, 0, { price = 1000 })
				for index = 1, 2 do
					metrics:ObserveRegion({ state = "OutsideCamp", at = index * 10 })
					metrics:ObserveRegion({
						state = "InHuntingRegion",
						regionId = "TEST",
						at = index * 10 + 1,
					})
					metrics:ObserveEconomic({
						kind = "WalletCredit",
						source = "BrainrotSale",
						revision = index,
						eventId = "sale:" .. index,
						amount = 50,
						at = index * 10 + 2,
					})
					metrics:ObserveSaleProvenance({
						individualId = "old",
						revision = index,
						eventId = "provenance:" .. index,
						at = index * 10 + 2,
					})
					metrics:ObserveEconomic({
						kind = "WalletCredit",
						source = "TestGrant",
						eventId = "grant:" .. index,
						amount = 50,
						at = index * 10 + 3,
					})
					metrics:ObserveRegion({ state = "AtCamp", at = index * 10 + 4 })
				end
				expect(metrics:BuildReport(30).similarExpeditionsRemaining.status).to.equal(
					"INSUFFICIENT_DATA"
				)
			end
		)

		it("bounds context details while retaining session outing totals and coverage", function()
			local metrics = fixture()
			for index = 1, 140 do
				metrics:ObserveShop({
					kind = "ContextIssued",
					eventId = "context:" .. index,
					contextId = "context:" .. index,
					offerKeys = {},
					at = index,
				})
			end
			local contextCount = 0
			for _ in metrics.contexts do
				contextCount += 1
			end
			expect(contextCount <= 128).to.equal(true)
			for index = 1, 11 do
				metrics:ObserveRegion({ state = "OutsideCamp", at = 200 + index * 3 })
				metrics:ObserveRegion({
					state = "InHuntingRegion",
					regionId = "TEST",
					at = 201 + index * 3,
				})
				metrics:ObserveRegion({ state = "AtCamp", at = 202 + index * 3 })
			end
			local report = metrics:BuildReport(240)
			expect(report.activity.completedOutings).to.equal(11)
			expect(#report.activity.outings).to.equal(10)
			expect(report.coverage.mapEvictions.contexts > 0).to.equal(true)
			expect(report.coverage.outingDetailDrops).to.equal(1)
		end)

		it(
			"uses supplied collectible cash rather than assuming all saved platform stock is available",
			function()
				local metrics = fixture({ platformCash = 200 })
				observeOffer(metrics, 0, { price = 100 })
				expect(
					metrics:BuildReport(10).offers[1].shortfallAfterCollectingAvailablePlatformCash
				).to.equal(nil)
				metrics:SetEndingState(0, 200, 20, 20)
				expect(
					metrics:BuildReport(20).offers[1].shortfallAfterCollectingAvailablePlatformCash
				).to.equal(80)
			end
		)

		it(
			"stops playable affordability time at departure and returns detached nested reports",
			function()
				local metrics = fixture({ wallet = 600, ownedProgression = { CARGO_1 = true } })
				observeOffer(metrics, 0, { fundsSufficient = true })
				metrics:BeginDeparture(100)
				local report = metrics:BuildReport(120)
				expect(report.session.playableDuration).to.equal(100)
				expect(report.offers[1].cumulativeEligibleAffordableDuration).to.equal(100)
				report.startingState.ownedProgression.CARGO_1 = false
				expect(metrics:BuildReport(120).startingState.ownedProgression.CARGO_1).to.equal(
					true
				)
			end
		)
		it(
			"reconciles the exact transfer, production, exposure, purchase, and save fixture",
			function()
				local metrics = fixture({ wallet = 400.5, platformCash = 120.25 })
				observeOffer(metrics, 0, { fundsSufficient = false })
				metrics:ObserveMilestone({
					kind = "WildAcquired",
					eventId = "acquire:fresh-1:10",
					at = 10,
					individualId = "fresh-1",
					speciesId = "TEST_COMMON",
				})
				metrics:ObserveEconomic({
					kind = "PlatformIncomeProduced",
					eventId = "income:30",
					at = 30,
					amount = 60,
					byIndividual = {},
				})
				metrics:ObserveShop({
					kind = "ContextIssued",
					eventId = "context-1",
					at = 60,
					contextId = "context-1",
					offerKeys = { "TEST_CARGO|fixture-cart|terms-v1" },
				})
				metrics:ObserveShop({
					kind = "MenuRendered",
					eventId = "context-1:render",
					at = 61,
					contextId = "context-1",
					inputCategory = "Touch",
				})
				metrics:ObserveEconomic({
					kind = "WalletCredit",
					eventId = "revision-1:sale",
					at = 90,
					amount = 120,
					source = "BrainrotSale",
					balanceAfter = 520.5,
					revision = 1,
				})
				metrics:ObserveSaleProvenance({
					eventId = "sale:fresh-1",
					at = 90,
					individualId = "fresh-1",
					revision = 1,
				})
				observeOffer(metrics, 90, { fundsSufficient = true })
				metrics:ObservePurchase({
					kind = "Attempt",
					requestId = "purchase-1",
					offerKey = "TEST_CARGO|fixture-cart|terms-v1",
					at = 119,
				})
				metrics:ObservePurchase({
					kind = "Result",
					requestId = "purchase-1",
					offerKey = "TEST_CARGO|fixture-cart|terms-v1",
					at = 120,
					accepted = true,
					chargedAmount = 500,
					balanceAfter = 20.5,
					persistence = "Pending",
				})
				observeOffer(metrics, 120, {
					fundsSufficient = false,
					owned = true,
				})
				metrics:ObservePurchase({
					kind = "SaveConfirmed",
					requestId = "purchase-1",
					offerKey = "TEST_CARGO|fixture-cart|terms-v1",
					at = 130,
				})
				metrics:ObserveEconomic({
					kind = "PlatformCollection",
					eventId = "revision-3:collection",
					at = 150,
					amount = 180.25,
					balanceAfter = 200.75,
				})
				metrics:SetEndingState(200.75, 0, 180)

				-- Replayed domain receipts and acknowledgements do not change totals.
				expect(metrics:ObserveEconomic({
					kind = "PlatformCollection",
					eventId = "revision-3:collection",
					at = 151,
					amount = 180.25,
					balanceAfter = 200.75,
				})).to.equal(false)
				expect(metrics:ObservePurchase({
					kind = "SaveConfirmed",
					requestId = "purchase-1",
					offerKey = "TEST_CARGO|fixture-cart|terms-v1",
					at = 151,
				})).to.equal(false)

				local report = metrics:BuildReport(180)
				expect(report.economy.endingWallet).to.equal(200.75)
				expect(report.economy.endingSettledPlatformCash).to.equal(0)
				expect(report.economy.platformIncomeGenerated).to.equal(60)
				expect(report.economy.platformCashCollected).to.equal(180.25)
				expect(report.economy.salesCurrentSessionAssets).to.equal(120)
				expect(report.economy.walletDebits).to.equal(500)
				expect(report.economy.reconciled).to.equal(true)
				expect(report.economy.combinedResidual).to.equal(0)
				expect(report.offers[1].firstMenuRenderedAt).to.equal(61)
				expect(report.offers[1].firstFundsSufficientAt).to.equal(90)
				expect(report.offers[1].firstEligibleAffordableAt).to.equal(90)
				expect(report.offers[1].purchaseCommittedAt).to.equal(120)
				expect(report.offers[1].cumulativeEligibleAffordableDuration).to.equal(30)
				expect(report.offers[1].persistence).to.equal("Confirmed")
				expect(report.session.inputCategory).to.equal("Touch")
			end
		)

		it("keeps returning-empty origin separate from starting development", function()
			local metrics = fixture({ profileOrigin = "Existing", wallet = 0, platformCash = 0 })
			local report = metrics:BuildReport(60)
			expect(report.session.profileOrigin).to.equal("Existing")
			expect(report.startingState.wallet).to.equal(0)
			expect(report.startingState.occupiedSlotCount).to.equal(0)
		end)

		it(
			"labels an offer affordable at start without claiming it was earned instantly",
			function()
				local metrics = fixture({ wallet = 600 })
				observeOffer(metrics, 0, { fundsSufficient = true })
				local offer = metrics:BuildReport(10).offers[1]
				expect(offer.fundsSufficientAtStart).to.equal(true)
				expect(offer.firstFundsSufficientAt).to.equal(0)
				expect(offer.firstEligibleAffordableSinceWorldReady).to.equal(0)
			end
		)

		it("separates a financial lock from an unavailable prerequisite path", function()
			local metrics = fixture({ wallet = 6500 })
			observeOffer(metrics, 0, {
				offerId = "RANK_LOCKED",
				price = 6500,
				fundsSufficient = true,
				prerequisitesSatisfied = false,
				primaryReason = "RANK_REQUIRED",
			})
			observeOffer(metrics, 0, {
				offerId = "PATH_BLOCKED",
				price = 500,
				fundsSufficient = true,
				ready = false,
				prerequisitesSatisfied = false,
				pathBlocked = true,
				primaryReason = "RANK_PROVIDER_UNAVAILABLE",
			})
			local offers = metrics:BuildReport(10).offers
			expect(offers[1].firstFundsSufficientAt).to.equal(0)
			expect(offers[1].firstEligibleAffordableAt).to.equal(nil)
			expect(offers[1].pathBlocked).to.equal(true)
			expect(offers[2].firstFundsSufficientAt).to.equal(0)
			expect(offers[2].firstEligibleAffordableAt).to.equal(nil)
			expect(offers[2].prerequisitesSatisfied).to.equal(false)
		end)

		it("tracks multiple affordability windows after other spending", function()
			local metrics = fixture({ wallet = 600 })
			observeOffer(metrics, 0, { fundsSufficient = true })
			metrics:ObserveEconomic({
				kind = "WalletDebit",
				eventId = "other-spend",
				at = 10,
				amount = 500,
				balanceAfter = 100,
			})
			observeOffer(metrics, 10, { fundsSufficient = false })
			metrics:ObserveEconomic({
				kind = "WalletCredit",
				eventId = "other-credit",
				at = 20,
				amount = 450,
				source = "ExistingReward",
				balanceAfter = 550,
			})
			observeOffer(metrics, 20, { fundsSufficient = true })
			local offer = metrics:BuildReport(30).offers[1]
			expect(offer.affordableWindowEntries).to.equal(2)
			expect(offer.cumulativeEligibleAffordableDuration).to.equal(20)
		end)

		it("retains censored purchases and interrupted reset outings", function()
			local metrics = fixture({ wallet = 600 })
			observeOffer(metrics, 0, { fundsSufficient = true })
			metrics:ObserveRegion({ at = 5, state = "OutsideCamp" })
			metrics:ObserveRegion({ at = 10, state = "InHuntingRegion", regionId = "TEST" })
			metrics:ObserveRegion({ at = 20, state = "Interrupted", reason = "CharacterReset" })
			local report = metrics:BuildReport(30)
			expect(report.offers[1].purchaseCommittedAt).to.equal(nil)
			expect(report.activity.outings[1].terminationReason).to.equal("CharacterReset")
			expect(report.activity.outings[1].returnAt).to.equal(nil)
		end)

		it("counts repeated acquisition operations but one unique individual", function()
			local metrics = fixture()
			for index = 1, 2 do
				metrics:ObserveMilestone({
					kind = "WildAcquired",
					eventId = "acquire:same:" .. tostring(index),
					at = index,
					individualId = "same-individual",
					speciesId = "TEST_COMMON",
				})
			end
			local report = metrics:BuildReport(10)
			expect(report.activity.counts.acquisitionOperations).to.equal(2)
			expect(report.activity.uniqueIndividualAcquisitions).to.equal(1)
		end)

		it("classifies a sale of a starting asset as liquidation", function()
			local metrics = fixture({
				wallet = 10,
				startingOwnedIndividuals = { ["old-individual"] = true },
			})
			metrics:ObserveEconomic({
				kind = "WalletCredit",
				eventId = "sale-credit",
				at = 5,
				amount = 120,
				source = "BrainrotSale",
				balanceAfter = 130,
				revision = 1,
			})
			metrics:ObserveSaleProvenance({
				eventId = "sale-old",
				at = 5,
				individualId = "old-individual",
				revision = 1,
			})
			local economy = metrics:BuildReport(10).economy
			expect(economy.salesStartingAssets).to.equal(120)
			expect(economy.salesCurrentSessionAssets).to.equal(0)
		end)

		it("keeps totals after the bounded detail buffer truncates", function()
			local metrics = fixture()
			for index = 1, 140 do
				metrics:ObserveEconomic({
					kind = "WalletCredit",
					eventId = "credit:" .. tostring(index),
					at = index,
					amount = 1,
					source = "ExistingReward",
					balanceAfter = index,
				})
			end
			local report = metrics:BuildReport(140)
			expect(report.economy.otherWalletCredits).to.equal(140)
			expect(report.coverage.detailDrops > 0).to.equal(true)
			expect(#report.coverage.recentDetails <= 128).to.equal(true)
		end)

		it("builds repeated reports without changing economic or profile inputs", function()
			local profile = { Economy = { Balance = 42.5 }, Revision = 7 }
			local metrics = fixture({ wallet = profile.Economy.Balance })
			local first = metrics:BuildReport(10)
			local second = metrics:BuildReport(20)
			expect(first.economy.endingWallet).to.equal(second.economy.endingWallet)
			expect(profile.Economy.Balance).to.equal(42.5)
			expect(profile.Revision).to.equal(7)
		end)
	end)
	it("accounts for region debits once without confusing pending persistence with an unlock",function()
		local m=fixture({wallet=30000000})
		local debit={kind="GatePurchaseCommitted",key="Beach",at=1,price=25000000,wallet=5000000,transactionId="gate-tx",eventId="gate-tx"}
		expect(m:ObserveWorldProgression(debit)).to.equal(true)
		expect(m:ObserveWorldProgression(debit)).to.equal(false)
		local pending=m:BuildReport(1)
		expect(pending.economy.walletDebits).to.equal(25000000)
		expect(pending.economy.endingWallet).to.equal(5000000)
		expect(pending.worldProgression.gates.Beach.confirmedUnlockAt).to.equal(nil)
		m:ObserveWorldProgression({kind="GatePurchaseConfirmed",key="Beach",at=2,eventId="gate-tx",transactionId="gate-tx"})
		local confirmed=m:BuildReport(2)
		expect(confirmed.worldProgression.gates.Beach.confirmedUnlockAt).to.equal(2)
		expect(confirmed.worldProgression.gates.Beach.sincePreviousUnlockSeconds).to.equal(3)
		expect(confirmed.economy.walletDebits).to.equal(25000000)
	end)
	it("keeps phase events bounded and never stores arbitrary profile payloads",function()
		local m=fixture()
		for i=1,150 do m:ObserveWorldProgression({kind="GatePanelOpened",at=i,key="Beach",fullProfile={secret="not retained"}}) end
		local report=m:BuildReport(150).worldProgression
		expect(#report.events).to.equal(128) expect(report.eventDrops).to.equal(22)
		expect(report.events[1].fullProfile).to.equal(nil)
		expect(m:ObserveWorldProgression({kind="InventedEvent",at=151})).to.equal(false)
	end)
	it("rejects retired guest receipts and preserves personal legacy and fixture cohorts",function()
		local m=fixture({profileOrigin="ConfirmedNew"})
		expect(m:ObserveWorldProgression({kind="GuestVisitAdmitted",guest=false,at=1})).to.equal(false)
		expect(m:BuildReport(1).worldProgression.cohort).to.equal("FreshSolo")
		expect(m:ObserveWorldProgression({kind="GuestVisitAdmitted",guest=true,at=2})).to.equal(false)
		expect(m:BuildReport(2).worldProgression.cohort).to.equal("FreshSolo")
		m:ObserveWorldProgression({kind="ProgressionProfileReady",legacyRegions="Beach",fixture=true,at=3})
		local report=m:BuildReport(3).worldProgression
		expect(report.cohort).to.equal("LegacyGranted") expect(report.seededFixture).to.equal(true)
	end)

end
