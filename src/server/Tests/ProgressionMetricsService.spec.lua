--!nocheck

return function()
	local Service = require(script.Parent.Parent.Services.ProgressionMetricsService)

	local function signal()
		local listeners = {}
		local result = {}
		function result:Connect(callback)
			local connection = {}
			listeners[connection] = callback
			function connection.Disconnect()
				listeners[connection] = nil
			end
			return connection
		end
		function result:Fire(...)
			for _, callback in listeners do
				callback(...)
			end
		end
		return result
	end

	local function dotBoundary()
		local callback = nil
		return {
			SubscribeCommitted = function(nextCallback)
				callback = nextCallback
				return {
					Disconnect = function()
						callback = nil
					end,
				}
			end,
			Emit = function(_, player, receipt)
				if callback then
					callback(player, receipt)
				end
			end,
		}
	end

	local function methodBoundary()
		local listener = nil
		local boundary = {}
		function boundary:SubscribeCommitted(callback)
			listener = callback
			return {
				Disconnect = function()
					listener = nil
				end,
			}
		end
		function boundary:Emit(player, receipt)
			if listener then
				listener(player, receipt)
			end
		end
		return boundary
	end

	-- These tests isolate orchestration only. The separate persistence integration
	-- fixture exercises real economic owners and their production receipts.
	local function serviceFixture(callback)
		Service:Stop()
		local f = { now = 0, generation = 1, ready = false, worldReady = false }
		f.player = { UserId = 7002, CharacterRemoving = signal() }
		f.players = { PlayerAdded = signal(), PlayerRemoving = signal() }
		function f.players:GetPlayers()
			return {}
		end
		f.data = {
			Economy = { Balance = 400.5 },
			Collection = { BrainrotInstances = {} },
			Base = { Slots = { ["1"] = { accumulatedCash = 120.25 } } },
		}
		f.diagnostics, f.finalizers, f.worldSignal, f.worldDiagnostics =
			signal(), signal(), signal(), signal()
		local profile = {}
		function profile:GetSessionHandle(player)
			return { Player = player, UserId = player.UserId, Generation = f.generation }
		end
		function profile:IsCurrentSessionHandle(handle)
			return handle.Player == f.player and handle.Generation == f.generation
		end
		function profile:GetReadableData()
			return if f.ready then f.data else nil
		end
		function profile:GetDiagnostics()
			return {
				status = if f.ready then "Ready" else "Loading",
				generation = f.generation,
				profileOrigin = "Existing",
			}
		end
		function profile:SubscribeDiagnostics(cb)
			return f.diagnostics:Connect(cb)
		end
		function profile:RegisterCloseFinalizer(cb)
			return f.finalizers:Connect(cb)
		end
		local world = {}
		function world:IsReady()
			return f.worldReady
		end
		function world:SubscribeReady(cb)
			return f.worldSignal:Connect(cb)
		end
		function world:SubscribeDiagnostics(cb)
			return f.worldDiagnostics:Connect(cb)
		end
		f.currency, f.income = methodBoundary(), methodBoundary()
		f.interaction, f.sale = dotBoundary(), dotBoundary()
		f.upgradeEvents = signal()
		local upgrades = {}
		function upgrades:GetMeasurementOffers()
			if f.offerFailure == "throw" then
				error("Controlled measurement evaluator failure")
			end
			if f.offerFailure == "not-table" then
				return false
			end
			return f.offers or {}
		end
		function upgrades:SubscribeObservations(cb)
			return f.upgradeEvents:Connect(cb)
		end
		local storage = {}
		function storage:ObserveStorage()
			return function() end
		end
		function storage:GetStorageForPlayer()
			return nil
		end
		f.location = { character = {}, alive = true, position = "REGION_CAMP" }
		Service:Start({
			Players = f.players,
			Profile = profile,
			WorldLifecycle = world,
			Currency = f.currency,
			Income = f.income,
			Interaction = f.interaction,
			Sale = f.sale,
			Upgrade = upgrades,
			Storage = storage,
			Catalog = {
				GetCashPerSecond = function()
					return 0
				end,
			},
			Environment = { BuildId = "orchestration-fixture", Name = "Development" },
			Now = function()
				return f.now
			end,
			GenerateObservationId = function()
				return "fixture-" .. tostring(f.generation)
			end,
			ConnectScheduler = false,
			LogReports = false,
			ReadLocation = function()
				return f.location
			end,
			Regions = {
				GetRegionAtPosition = function(position)
					return if position then { id = position } else nil
				end,
			},
		})
		function f.Load()
			f.players.PlayerAdded:Fire(f.player)
			f.diagnostics:Fire(f.player, { kind = "LoadStarted", generation = f.generation })
			f.ready = true
			f.diagnostics:Fire(
				f.player,
				{ kind = "LoadCompleted", generation = f.generation, profileOrigin = "Existing" }
			)
		end
		function f.WorldReady()
			f.worldReady = true
			f.worldSignal:Fire(f.player)
		end
		function f.Sample(at, region)
			f.now = at
			f.location.position = region
			Service:Step(0.5)
		end
		local ok, failure = xpcall(function()
			callback(f)
		end, debug.traceback)
		Service:Stop()
		assert(ok, failure)
	end

	describe("Phase 7G-1 observation lifecycle boundaries", function()
		it("counts a committed discarded stay once without inventing wallet earnings", function()
			serviceFixture(function(f)
				f.Load()
				f.WorldReady()
				f.data.Base.Slots["1"].accumulatedCash = 0
				local receipt = {
					kind = "PlatformCashDiscarded",
					generation = 1,
					revision = 2,
					eventId = "platform-discard:2",
					amount = 120.25,
					signedAmount = -120.25,
				}
				f.diagnostics:Fire(f.player, receipt)
				f.diagnostics:Fire(f.player, receipt)
				local report = Service:GetReport(f.player)
				expect(report.economy.platformAdjustments).to.equal(-120.25)
				expect(report.economy.walletCredits).to.equal(0)
				expect(report.economy.reconciled).to.equal(true)
			end)
		end)
		it(
			"closes stale affordability during evaluator failure and resumes without counting the unknown interval",
			function()
				serviceFixture(function(f)
					f.offers = {
						{
							offerId = "FIXTURE",
							offerKey = "FIXTURE|player|v1",
							targetKey = "player",
							termsVersion = "v1",
							price = 300,
							owned = false,
							ready = true,
							prerequisitesSatisfied = true,
							fundsSufficient = true,
							pathBlocked = false,
						},
					}
					f.Load()
					f.WorldReady()
					local baseline = Service:GetReport(f.player)
					expect(baseline.referenceNextAffordablePurchase.offerId).to.equal("FIXTURE")
					expect(baseline.session.coverage.offerEvaluation).to.equal("AVAILABLE")
					f.now = 10
					f.offerFailure = "throw"
					Service:RefreshOffers(f.player)
					f.now = 20
					local unavailable = Service:GetReport(f.player)
					expect(unavailable.session.coverage.offerEvaluation).to.equal("UNAVAILABLE")
					expect(unavailable.referenceNextAffordablePurchase).to.equal(nil)
					expect(unavailable.offers[1].active).to.equal(false)
					expect(unavailable.offers[1].currentAffordable).to.equal(false)
					expect(unavailable.offers[1].cumulativeEligibleAffordableDuration).to.equal(10)
					f.now = 25
					f.offerFailure = "not-table"
					Service:RefreshOffers(f.player)
					expect(Service:GetReport(f.player).referenceNextAffordablePurchase).to.equal(
						nil
					)
					f.now = 30
					f.offerFailure = nil
					Service:RefreshOffers(f.player)
					f.now = 35
					local resumed = Service:GetReport(f.player)
					expect(resumed.session.coverage.offerEvaluation).to.equal("AVAILABLE")
					expect(resumed.referenceNextAffordablePurchase.offerId).to.equal("FIXTURE")
					expect(resumed.offers[1].affordableWindowEntries).to.equal(2)
					expect(resumed.offers[1].firstEligibleAffordableAt).to.equal(0)
					expect(resumed.offers[1].cumulativeEligibleAffordableDuration).to.equal(15)
					expect(f.data.Economy.Balance).to.equal(400.5)
					expect(f.data.Base.Slots["1"].accumulatedCash).to.equal(120.25)
				end)
			end
		)
		it("uses one server receipt clock even when producer clocks are unrelated", function()
			serviceFixture(function(f)
				f.Load()
				f.WorldReady()
				f.now = 30
				f.data.Economy.Balance += 10
				f.currency:Emit(f.player, {
					kind = "WalletCredit",
					sessionGeneration = 1,
					eventId = "different-clock",
					at = 987654321,
					amount = 10,
					balanceAfter = 410.5,
					source = "BrainrotSale",
					revision = 1,
				})
				local report = Service:GetReport(f.player)
				expect(report.milestones.firstSaleAt).to.equal(30)
				expect(report.economy.reconciled).to.equal(true)
				expect(report.session.coverage.timestampBasis).to.equal("SERVER_RECEIPT_TIME")
			end)
		end)
		it(
			"seeds newly observed purchase terms from the actual committed pre-debit receipt",
			function()
				serviceFixture(function(f)
					f.data.Economy.Balance = 600.5
					f.Load()
					f.WorldReady()
					f.now = 10
					f.data.Economy.Balance = 100.5
					local receipt = {
						kind = "PurchaseCommitted",
						sessionGeneration = 1,
						eventId = "new-terms",
						requestId = "new-terms",
						offerId = "FIXTURE",
						offerKey = "FIXTURE|player|terms2",
						targetKey = "player",
						termsVersion = "terms2",
						price = 500,
						chargedAmount = 500,
						balanceBefore = 600.5,
						balanceAfter = 100.5,
						commitRevision = 1,
						ready = true,
						prerequisitesSatisfied = true,
						fundsSufficient = true,
					}
					f.upgradeEvents:Fire(f.player, receipt)
					f.upgradeEvents:Fire(f.player, receipt)
					local report = Service:GetReport(f.player)
					expect(report.economy.walletDebits).to.equal(500)
					expect(report.economy.reconciled).to.equal(true)
					expect(report.offers[1].owned).to.equal(true)
					expect(report.offers[1].purchaseCommittedAt).to.equal(10)
				end)
			end
		)
		it(
			"waits for the full world owner and reads authoritative balances without causing settlement",
			function()
				serviceFixture(function(f)
					f.Load()
					expect(Service:GetReport(f.player).session.clocks.worldReadyAt).to.equal(nil)
					f.now = 4
					f.WorldReady()
					local before = Service:GetReport(f.player)
					expect(before.session.clocks.worldReadyAt).to.equal(4)
					f.data.Economy.Balance += 25 -- intentionally missing receipt must remain visible
					local report = Service:GetReport(f.player)
					expect(report.economy.walletResidual).to.equal(25)
					expect(report.economy.reconciled).to.equal(false)
					expect(report.session.clocks.reportClosedAt).to.equal(nil)
					Service:GetReport(f.player)
					expect(f.data.Economy.Balance).to.equal(425.5)
					expect(f.data.Base.Slots["1"].accumulatedCash).to.equal(120.25)
				end)
			end
		)
		it(
			"does not treat repeated world binding as departure and samples stable actual-region transitions",
			function()
				serviceFixture(function(f)
					f.Load()
					f.WorldReady()
					f.Sample(0, "REGION_CAMP")
					f.Sample(1, "REGION_CAMP")
					f.Sample(2, "REGION_FOREST")
					f.Sample(2.5, "REGION_FOREST")
					expect(Service:GetReport(f.player).activity.activeOuting).to.equal(nil)
					f.Sample(3, "REGION_FOREST")
					expect(Service:GetReport(f.player).activity.activeOuting.departureAt).to.equal(
						3
					)
					f.WorldReady() -- reassigned cart/base readiness is not a new session or departure
					expect(Service:GetReport(f.player).session.clocks.departureCutoffAt).to.equal(
						nil
					)
					f.player.CharacterRemoving:Fire()
					f.Sample(4, "REGION_CAMP")
					f.Sample(5, "REGION_CAMP")
					local report = Service:GetReport(f.player)
					expect(report.activity.outings[1].terminationReason).to.equal(
						"CharacterDeathReset"
					)
					expect(report.activity.outings[1].returnAt).to.equal(nil)
				end)
			end
		)
		it(
			"rejects old-generation callbacks after the same player starts a new profile session",
			function()
				serviceFixture(function(f)
					f.Load()
					f.WorldReady()
					f.generation = 2
					f.now = 20
					f.Load()
					f.WorldReady()
					f.currency:Emit(f.player, {
						kind = "WalletCredit",
						sessionGeneration = 1,
						eventId = "old",
						amount = 50,
						balanceAfter = 450.5,
						source = "Test",
					})
					local report = Service:GetReport(f.player)
					expect(report.economy.otherWalletCredits).to.equal(0)
					expect(report.session.coverage.staleReceiptsRejected).to.equal(1)
				end)
			end
		)
		it(
			"captures final authorized settlement then keeps only a detached summary until close acknowledgement",
			function()
				serviceFixture(function(f)
					f.Load()
					f.WorldReady()
					f.now = 10
					f.diagnostics:Fire(f.player, { kind = "CloseStarted", generation = 1 })
					f.data.Base.Slots["1"].accumulatedCash += 60
					f.income:Emit(f.player, {
						kind = "PlatformIncomeProduced",
						sessionGeneration = 1,
						eventId = "final-income",
						amount = 60,
						byIndividual = {},
					})
					f.finalizers:Fire(f.player)
					expect(Service:GetDiagnostics().active).to.equal(0)
					expect(Service:GetDiagnostics().joining).to.equal(0)
					expect(Service:GetDiagnostics().detached).to.equal(1)
					f.ready = false
					f.now = 15
					f.diagnostics:Fire(
						f.player,
						{ kind = "SaveConfirmed", generation = 1, revision = 3 }
					)
					f.diagnostics:Fire(
						f.player,
						{ kind = "CloseCompleted", generation = 1, revision = 3 }
					)
					local report = Service:GetCompletedReports()[1]
					expect(report.economy.endingSettledPlatformCash).to.equal(180.25)
					expect(report.economy.reconciled).to.equal(true)
					expect(report.persistence.closeStatus).to.equal("Confirmed")
					expect(report.session.clocks.reportClosedAt).to.equal(15)
					expect(Service:GetDiagnostics().detached).to.equal(0)
				end)
			end
		)
		it(
			"reports failed and cancelled loads without retaining a player or inventing starting zero money",
			function()
				serviceFixture(function(f)
					f.players.PlayerAdded:Fire(f.player)
					f.diagnostics:Fire(
						f.player,
						{ kind = "LoadRejected", generation = 1, code = "LOAD_FAILED" }
					)
					expect(Service:GetDiagnostics().joining).to.equal(0)
					local report = Service:GetCompletedReports()[1]
					expect(report.economy.status).to.equal("NOT_OBSERVED")
					expect(report.economy.endingWallet).to.equal(nil)
					f.players.PlayerAdded:Fire(f.player)
					f.players.PlayerRemoving:Fire(f.player)
					expect(Service:GetDiagnostics().joining).to.equal(0)
					expect(#Service:GetCompletedReports()).to.equal(2)
				end)
			end
		)
	end)

	describe("Phase 7G-1 production observation wiring", function()
		it("routes the exact deterministic trace through committed domain observers", function()
			Service:Stop()
			local now = -5
			local player = { UserId = 7001, Name = "MetricsFixture" }
			local playerAdded, playerRemoving = signal(), signal()
			local players = {
				PlayerAdded = playerAdded,
				PlayerRemoving = playerRemoving,
			}
			function players:GetPlayers()
				return {}
			end

			local profileData = {
				Economy = { Balance = 400.5 },
				Collection = { BrainrotInstances = {} },
				Base = {
					Slots = {
						["1"] = { accumulatedCash = 0 },
						["4"] = { accumulatedCash = 120.25 },
					},
				},
			}
			local profileDiagnostic = nil
			local profile = {}
			function profile:SubscribeDiagnostics(callback)
				profileDiagnostic = callback
				return {
					Disconnect = function()
						profileDiagnostic = nil
					end,
				}
			end
			function profile:GetReadableData(subject)
				return if subject == player then profileData else nil
			end
			function profile:GetDiagnostics(subject)
				return if subject == player
					then { status = "Ready", generation = 1, profileOrigin = "ConfirmedNew" }
					else nil
			end
			function profile:GetSessionHandle(subject)
				return { Player = subject, UserId = subject.UserId, Generation = 1 }
			end
			function profile:IsCurrentSessionHandle(handle)
				return handle.Player == player and handle.Generation == 1
			end
			function profile:RegisterCloseFinalizer()
				return { Disconnect = function() end }
			end
			local worldReady = signal()
			local world = {}
			function world:SubscribeReady(callback)
				return worldReady:Connect(callback)
			end
			function world:IsReady()
				return true
			end

			local storage = {}
			function storage:ObserveStorage(_observer)
				return function() end
			end

			local owned = false
			local upgradeObservation = nil
			local upgrade = {}
			function upgrade:SubscribeObservations(callback)
				upgradeObservation = callback
				return {
					Disconnect = function()
						upgradeObservation = nil
					end,
				}
			end
			function upgrade:GetMeasurementOffers()
				return {
					{
						offerId = "TEST_CARGO",
						targetKey = "fixture-cart",
						termsVersion = "terms-v1",
						offerKey = "TEST_CARGO|fixture-cart|terms-v1",
						price = 500,
						owned = owned,
						fundsSufficient = profileData.Economy.Balance >= 500,
						ready = true,
						prerequisitesSatisfied = true,
						pathBlocked = false,
					},
				}
			end

			local currency = methodBoundary()
			local income = methodBoundary()
			function income:GetStateSnapshot()
				return nil
			end
			local interaction = dotBoundary()
			local sale = dotBoundary()

			Service:Start({
				Players = players,
				Profile = profile,
				Upgrade = upgrade,
				Currency = currency,
				Income = income,
				Storage = storage,
				WorldLifecycle = world,
				ConnectScheduler = false,
				Regions = false,
				LogReports = false,
				Interaction = interaction,
				Sale = sale,
				Catalog = {
					GetCashPerSecond = function()
						return 0
					end,
				},
				Environment = {
					BuildId = "test-build",
					Name = "Development",
				},
				Now = function()
					return now
				end,
				GenerateObservationId = function()
					return "wired-observation"
				end,
			})

			playerAdded:Fire(player)
			now = -1
			profileDiagnostic(player, {
				kind = "LoadCompleted",
				eventId = "load-completed",
				profileOrigin = "ConfirmedNew",
			})
			now = 0
			worldReady:Fire(player)
			now = 10
			interaction:Emit(player, {
				kind = "WildAcquired",
				eventId = "acquire:fresh-1",
				individualId = "fresh-1",
				speciesId = "TEST_COMMON",
			})
			now = 30
			income:Emit(player, {
				kind = "PlatformIncomeProduced",
				eventId = "income:30",
				amount = 60,
				byIndividual = {},
			})
			now = 60
			upgradeObservation(player, {
				kind = "ContextIssued",
				eventId = "context-1",
				contextId = "context-1",
				offerKeys = { "TEST_CARGO|fixture-cart|terms-v1" },
			})
			now = 61
			upgradeObservation(player, {
				kind = "MenuRendered",
				eventId = "context-1:menu",
				contextId = "context-1",
				inputCategory = "Touch",
			})
			now = 90
			profileData.Economy.Balance = 520.5
			currency:Emit(player, {
				kind = "WalletCredit",
				eventId = "revision-1:sale",
				amount = 120,
				source = "BrainrotSale",
				balanceAfter = 520.5,
				revision = 1,
			})
			sale:Emit(player, {
				kind = "BrainrotSold",
				eventId = "sale:fresh-1",
				individualId = "fresh-1",
				revision = 1,
			})
			now = 119
			upgradeObservation(player, {
				kind = "PurchaseAttempt",
				eventId = "purchase-1",
				requestId = "purchase-1",
				offerKey = "TEST_CARGO|fixture-cart|terms-v1",
			})
			now = 120
			profileData.Economy.Balance = 20.5
			owned = true
			upgradeObservation(player, {
				kind = "PurchaseCommitted",
				eventId = "purchase-1",
				requestId = "purchase-1",
				offerKey = "TEST_CARGO|fixture-cart|terms-v1",
				accepted = true,
				chargedAmount = 500,
				balanceAfter = 20.5,
				persistence = "Pending",
			})
			now = 130
			upgradeObservation(player, {
				kind = "PurchaseSaveConfirmed",
				eventId = "purchase-1:saved",
				requestId = "purchase-1",
				offerKey = "TEST_CARGO|fixture-cart|terms-v1",
			})
			now = 150
			profileData.Economy.Balance = 200.75
			profileData.Base.Slots["4"].accumulatedCash = 0
			currency:Emit(player, {
				kind = "WalletCredit",
				eventId = "revision-3:collection",
				amount = 180.25,
				source = "PlatformIncomeClaim",
				balanceAfter = 200.75,
				revision = 3,
			})
			now = 180
			local report = Service:GetReport(player)
			expect(report.session.observationId).to.equal("wired-observation")
			expect(report.session.profileOrigin).to.equal("ConfirmedNew")
			expect(report.economy.platformIncomeGenerated).to.equal(60)
			expect(report.economy.platformCashCollected).to.equal(180.25)
			expect(report.economy.salesCurrentSessionAssets).to.equal(120)
			expect(report.economy.walletDebits).to.equal(500)
			expect(report.economy.endingWallet).to.equal(200.75)
			expect(report.economy.reconciled).to.equal(true)
			expect(report.offers[1].firstContextIssuedAt).to.equal(60)
			expect(report.offers[1].firstMenuRenderedAt).to.equal(61)
			expect(report.offers[1].firstEligibleAffordableAt).to.equal(90)
			expect(report.offers[1].purchaseCommittedAt).to.equal(120)
			expect(report.offers[1].persistence).to.equal("Confirmed")
			Service:Stop()
		end)
	end)
	it("bridges actual region purchase receipts into the existing reconciled economy report",function()
		serviceFixture(function(f)
			f.data.Economy.Balance=30000000 f.Load() f.WorldReady()
			f.now=1 f.data.Economy.Balance=5000000
			local receipt={key="Beach",price=25000000,wallet=5000000,transactionId="phase8-debit",revision=1}
			Service:ObserveWorldProgression(f.player,"GatePurchaseCommitted",receipt)
			Service:ObserveWorldProgression(f.player,"GatePurchaseCommitted",receipt)
			local report=Service:GetReport(f.player)
			expect(report.economy.walletDebits).to.equal(25000000) expect(report.economy.reconciled).to.equal(true)
			expect(report.worldProgression.gates.Beach.confirmedUnlockAt).to.equal(nil)
			f.now=2 Service:ObserveWorldProgression(f.player,"GatePurchaseConfirmed",receipt)
			expect(Service:GetReport(f.player).worldProgression.gates.Beach.confirmedUnlockAt).to.equal(2)
		end)
	end)
	it("connects a real introduced-species acquisition receipt to that individual's bank proof",function()
		serviceFixture(function(f)
			f.Load() f.WorldReady() f.now=1 f.location.position="REGION_BEACH"
			f.interaction:Emit(f.player,{kind="WildAcquired",eventId="caught-014",individualId="catch-014",speciesId="BRT_014"})
			f.now=2 Service:ObserveWorldProgression(f.player,"BankingProofAdded",{individualId="catch-014",speciesId="BRT_014",rarity="Uncommon"})
			local gate=Service:GetReport(f.player).worldProgression.gates.Beach
			expect(gate.introducedCatchAt).to.equal(1) expect(gate.introducedBankAt).to.equal(2)
		end)
	end)
	it("does not count a high-region public pickup in Camp as an introduced-region hunt",function()
		serviceFixture(function(f)
			f.Load() f.WorldReady() f.now=1 f.location.position="REGION_CAMP"
			f.interaction:Emit(f.player,{kind="WildAcquired",eventId="camp-014",individualId="camp-drop",speciesId="BRT_014"})
			f.now=2 Service:ObserveWorldProgression(f.player,"BankingProofAdded",{individualId="camp-drop",speciesId="BRT_014",rarity="Uncommon"})
			expect(Service:GetReport(f.player).worldProgression.gates.Beach).to.equal(nil)
		end)
	end)

	it(
		"accounts combined own earnings and one paid retention receipt separately without replaying the reward",
		function()
			serviceFixture(function(f)
				f.Load()
				f.WorldReady()
				f.now = 1
				f.data.Economy.Balance = 25000520.75
				f.data.Base.Slots["1"].accumulatedCash = 0
				local first = {
					kind = "WalletCredit",
					eventId = "claim:1",
					operationSequence = 1,
					stream = "Currency",
					amount = 120.25,
					source = "PlatformIncomeClaim",
					balanceBefore = 400.5,
					balanceAfter = 25000520.75,
					revision = 1,
					retention = {
						amountCash = 25000000,
						transitions = {
							{ grantId = "retention:0:camp_payday", amountCash = 25000000 },
						},
					},
				}
				f.currency:Emit(f.player, first)
				f.currency:Emit(f.player, first)
				local report = Service:GetReport(f.player)
				expect(report.economy.platformCashCollected).to.equal(120.25)
				expect(report.economy.otherWalletCredits).to.equal(25000000)
				expect(report.economy.walletCredits).to.equal(25000120.25)
				expect(report.economy.endingWallet).to.equal(25000520.75)
				expect(report.economy.reconciled).to.equal(true)
				f.now = 2
				f.income:Emit(
					f.player,
					{ kind = "PlatformIncomeProduced", eventId = "income:2", amount = 10.5 }
				)
				f.data.Economy.Balance = 25000531.25
				f.currency:Emit(f.player, {
					kind = "WalletCredit",
					eventId = "claim:2",
					operationSequence = 2,
					stream = "Currency",
					amount = 10.5,
					source = "PlatformIncomeClaim",
					balanceAfter = 25000531.25,
					revision = 2,
					retention = { amountCash = 0, transitions = {} },
				})
				f.currency:Emit(f.player, first)
				report = Service:GetReport(f.player)
				expect(report.economy.platformCashCollected).to.equal(130.75)
				expect(report.economy.platformIncomeGenerated).to.equal(10.5)
				expect(report.economy.otherWalletCredits).to.equal(25000000)
				expect(report.economy.walletCredits).to.equal(25000130.75)
				expect(report.economy.walletResidual).to.equal(0)
				expect(report.economy.platformResidual).to.equal(0)
				expect(report.economy.reconciled).to.equal(true)
				expect(f.data.Economy.Balance).to.equal(25000531.25)
			end)
		end
	)
end
