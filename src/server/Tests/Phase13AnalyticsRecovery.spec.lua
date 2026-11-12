return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local RS = game:GetService("ReplicatedStorage")
	local Adapter = require(script.Parent.Parent.Services.Phase13AnalyticsService)
	local Metrics = require(script.Parent.Parent.Services.Phase13MetricsService)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Weapons = require(RS.Shared.Config.Weapons)
	local key2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name
	local key3 = Enum.AnalyticsCustomFieldKeys.CustomField03.Name
	local function drain()
		for _ = 1, 80 do
			Adapter:Step(0)
		end
		return Adapter:GetRecorder()
	end
	local function events(name, category, result)
		local resultRows = {}
		for _, e in drain() do
			if
				e.name == name
				and (not category or e.fields[key2] == category)
				and (not result or e.fields[key3] == result)
			then
				table.insert(resultRows, e)
			end
		end
		return resultRows
	end
	describe("Phase 13 actual recovery and checkpoint observations", function()
		it(
			"uses the captured upgrade balance through its covering revision without consulting later profile state",
			function()
				Adapter:_ResetForTests()
				local p = {}
				local offer = { id = "CART_SPEED_1", price = 500 }
				local receipt = table.freeze({
					kind = "PurchaseCommitted",
					offerId = offer.id,
					commitRevision = 7,
					chargedAmount = 500,
					balanceAfter = 500.5,
				})
				local profiles = require(script.Parent.Parent.Services.PlayerDataService)
				local previous = profiles.GetReadableData
				profiles.GetReadableData = function()
					error("Observer must not reread a later wallet")
				end
				local ok, failure = xpcall(function()
					expect(Metrics:_ObserveUpgradePurchaseForTests(p, offer, 7, receipt)).to.equal(true)
					Metrics:_FlushTransactionsForTests(p, 6)
					local function economyRows()
						local found = {}
						for _, row in drain() do
							if row.kind == "Economy" then
								table.insert(found, row)
							end
						end
						return found
					end
					expect(#economyRows()).to.equal(0)
					Metrics:_FlushTransactionsForTests(p, 7)
					local rows = economyRows()
					expect(#rows).to.equal(1)
					expect(rows[1].amount).to.equal(500)
					expect(rows[1].balance).to.equal(500.5)
					expect(rows[1].sku).to.equal("CART_UPGRADE")
					expect(Metrics:_ObserveUpgradePurchaseForTests(p, offer, 7, receipt)).to.equal(true)
					Metrics:_FlushTransactionsForTests(p, 7)
					expect(#economyRows()).to.equal(1)
					expect(Metrics:_ObserveUpgradePurchaseForTests(p, offer, 8, receipt)).to.equal(false)
					expect(Metrics:_ObserveUpgradePurchaseForTests(p, { id = "CARGO_1", price = 500 }, 7, receipt)).to.equal(
						false
					)
				end, debug.traceback)
				profiles.GetReadableData = previous
				assert(ok, failure)
			end
		)
		it("observes cash-rebirth affordability from wallet plus uncollected cash", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = 100000000000
			data.Base.Slots["1"].accumulatedCash = 30000000000
			local expansion
			for _, offer in Metrics:_AffordableOffersForTests(data) do
				if offer.key == "Rebirth:EXP_018" then
					expansion = offer
				end
			end
			expect(expansion.price).to.equal(125000000000)
		end)
		it("records capture to durable first bank once and excludes owned moves", function()
			Adapter:_ResetForTests()
			local p = {}
			Adapter:ObserveSecuredAcquisition(p, "Theft", "fresh-id")
			Adapter:ObserveFirstBank(p, { individualId = "fresh-id" })
			Adapter:ObserveFirstBank(p, { individualId = "fresh-id" })
			Adapter:ObserveFirstBank(p, { individualId = "unobserved-owned-id" })
			expect(#events("CaptureToBankDuration", "Theft")).to.equal(1)
			expect(events("CaptureToBankDuration", "Theft")[1].value >= 0).to.equal(true)
		end)
		it("accepts one bounded cinematic diagnostic only for the confirmed operation", function()
			Adapter:_ResetForTests()
			local p = {}
			local report = { kind = "Cinematic", operationId = "visual", reason = "Completed", elapsed = 7 }
			expect(Adapter:ObserveCinematicOutcome(p, report)).to.equal(false)
			Adapter:Receipt(
				p,
				"Rebirth",
				{ state = "Confirmed", operationId = "visual", result = { route = "Cash", sacrificedCash = 10 } }
			)
			report.reason, report.elapsed = "Skipped", 0.9
			expect(Adapter:ObserveCinematicOutcome(p, report)).to.equal(false)
			report.reason, report.elapsed = "Completed", 7
			expect(Adapter:ObserveCinematicOutcome(p, report)).to.equal(true)
			expect(Adapter:ObserveCinematicOutcome(p, report)).to.equal(false)
			expect(events("CinematicOutcome", "CinematicCash", "Completed")[1].value).to.equal(7)
		end)
		it("rejects non-finite economy observations without affecting gameplay", function()
			Adapter:_ResetForTests()
			expect(Adapter:Economy({}, "Source", math.huge, 1, "Cash", "FIXTURE")).to.equal(false)
			expect(Adapter:Economy({}, "Source", 1, math.huge, "Cash", "FIXTURE")).to.equal(false)
			expect(Adapter:Economy({}, "Sink", 1, 0 / 0, "Cash", "FIXTURE")).to.equal(false)
			expect(Adapter:Economy({}, "Source", 9e15 + 1, 1, "Cash", "FIXTURE")).to.equal(false)
		end)
		it("measures base CPS milestones once and ignores paid production multiplication", function()
			Adapter:_ResetForTests()
			local p = {}
			Adapter:BeginRecovery(p, { route = "Collection", baseCpsBefore = 400, sacrificedIndividuals = 12 })
			Adapter:ObserveRecoveryBank(p)
			Adapter:_ObserveSnapshotForTests(p, 10, { baseCps = 100, productionCps = 800 })
			Adapter:_ObserveSnapshotForTests(p, 10, { baseCps = 200, productionCps = 800 })
			Adapter:_ObserveSnapshotForTests(p, 10, { baseCps = 400 })
			Adapter:_ObserveSnapshotForTests(p, 10, { baseCps = 400 })
			expect(#events("RebirthRecoveryDuration", "RecoveryFirstEarner")).to.equal(1)
			expect(events("RebirthRecoveryDuration", "RecoveryCps25")[1].value).to.equal(10)
			expect(events("RebirthRecoveryDuration", "RecoveryCps50")[1].value).to.equal(20)
			expect(events("RebirthRecoveryDuration", "RecoveryCps100")[1].value).to.equal(30)
			expect(#events("RebirthRecoveryDuration", "RecoveryCps100")).to.equal(1)
		end)
		it("does not treat purchased cash or balances as earned cash recovery", function()
			Adapter:_ResetForTests()
			local p = {}
			Adapter:BeginRecovery(p, { route = "Cash", sacrificedCash = 1000 })
			Adapter:Receipt(
				p,
				"PaidCash",
				{ state = "Confirmed", operationId = "paid", result = { amount = 10000, balance = 10000 } }
			)
			Adapter:_ObserveSnapshotForTests(p, 12, { balance = 10000, baseCps = 0 })
			expect(#events("RebirthRecoveryDuration")).to.equal(0)
			Adapter:ObserveEarnedCash(p, 250)
			Adapter:_ObserveSnapshotForTests(p, 1, { balance = 10250 })
			expect(events("RebirthRecoveryDuration", "RecoveryCash25")[1].value).to.equal(13)
			expect(#events("RebirthRecoveryDuration", "RecoveryCash50")).to.equal(0)
		end)
		it("keeps departure and new-sacrifice outcomes incomplete without fictional success durations", function()
			Adapter:_ResetForTests()
			local p = {}
			Adapter:BeginRecovery(p, { route = "Collection", baseCpsBefore = 100, sacrificedIndividuals = 5 })
			Adapter:_ObserveSnapshotForTests(p, 9, { baseCps = 0 })
			Adapter:BeginRecovery(p, { route = "Collection", baseCpsBefore = 0, sacrificedIndividuals = 2 })
			Adapter:ObserveDeparture(p)
			expect(#events("RebirthOutcome", "RecoveryCollection", "Incomplete")).to.equal(2)
			expect(#events("RebirthRecoveryDuration")).to.equal(0)
		end)
		it("emits each checkpoint dimension once and affordability once despite oscillation", function()
			Adapter:_ResetForTests()
			local p = {}
			Adapter:ObserveSecuredAcquisition(p, "Theft", "id")
			expect(Adapter:ObserveSecuredAcquisition(p, "Theft", "id")).to.equal(false)
			local snapshot = {
				unlockedRegions = 3,
				capacity = 18,
				occupancy = 7,
				incomeBand = 2,
				rebirthCount = 1,
				paidCohort = 0,
				affordableOffers = { { key = "Weapon:WPN_B02", category = "Weapon", price = 100 } },
			}
			Adapter:_ObserveSnapshotForTests(p, 899, snapshot)
			expect(#events("SessionCheckpoint")).to.equal(0)
			Adapter:_ObserveSnapshotForTests(p, 1, snapshot)
			Adapter:_ObserveSnapshotForTests(p, 1, {})
			Adapter:_ObserveSnapshotForTests(p, 1, snapshot)
			expect(#events("SessionCheckpoint")).to.equal(9)
			expect(events("SessionCheckpoint", "Capacity", "Checkpoint15")[1].value).to.equal(18)
			expect(events("SessionCheckpoint", "TheftAcquisitions", "Checkpoint15")[1].value).to.equal(1)
			expect(#events("AffordabilityReached")).to.equal(1)
		end)
		it("uses canonical catalogue ownership and sequential upgrade prices", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = 9e13
			local offers = Metrics:_AffordableOffersForTests(data)
			local seen = {}
			for _, offer in offers do
				seen[offer.key] = offer
			end
			expect(seen["Weapon:HRP_001"]).to.equal(nil)
			for _, weapon in Weapons.GetAll() do
				if weapon.price > 0 then
					expect(seen["Weapon:" .. weapon.id].price).to.equal(weapon.price)
				end
			end
			expect(seen["Speed:1"].price).to.equal(500000000)
			expect(seen["Speed:2"]).to.equal(nil)
			expect(seen["Equipped:3"].price).to.equal(500000000)
		end)
		it("aggregates actual save results and omits unknown completed latency", function()
			Adapter:_ResetForTests()
			local p = {}
			Metrics:_ObserveSaveDiagnosticForTests(p, { kind = "SaveStarted", at = 10, generation = 1 })
			Metrics:_ObserveSaveDiagnosticForTests(p, { kind = "SaveRetry", at = 12, generation = 1 })
			Metrics:_ObserveSaveDiagnosticForTests(p, {
				kind = "SaveAttemptCompleted",
				at = 12,
				generation = 1,
				attemptSequence = 1,
				ok = false,
				uncertain = true,
			})
			Metrics:_FlushSaveHealthForTests(p, 14)
			expect(events("SaveHealth", "SaveAttempts")[1].value).to.equal(1)
			expect(events("SaveHealth", "SaveFailures")[1].value).to.equal(1)
			expect(events("SaveHealth", "SaveUncertainAttempts")[1].value).to.equal(1)
			expect(#events("SaveHealth", "SaveLatencySeconds")).to.equal(0)
			expect(events("SaveHealth", "SavePendingSeconds")[1].value).to.equal(4)
			Metrics:_ObserveSaveDiagnosticForTests(p, {
				kind = "SaveAttemptCompleted",
				at = 15,
				generation = 1,
				attemptSequence = 2,
				ok = true,
				uncertain = false,
			})
			Metrics:_ObserveSaveDiagnosticForTests(
				p,
				{ kind = "SaveConfirmed", at = 15, generation = 1, savedRevision = 3, currentRevision = 3 }
			)
			Metrics:_FlushSaveHealthForTests(p, 15)
			expect(events("SaveHealth", "SaveLatencySeconds")[1].value).to.equal(5)
			expect(events("SaveHealth", "SaveConfirmations")[2].value).to.equal(1)
		end)
		it(
			"counts every failed backend attempt including terminal failure and ignores duplicate/out-of-order diagnostic replay",
			function()
				Adapter:_ResetForTests()
				local p = {}
				Metrics:_ObserveSaveDiagnosticForTests(p, { kind = "SaveStarted", generation = 4, at = 10 })
				for attempt = 1, 5 do
					local row = {
						kind = "SaveAttemptCompleted",
						at = 10 + attempt,
						generation = 4,
						attemptSequence = attempt,
						eventId = "save:test:attempt:" .. attempt,
						ok = false,
						uncertain = true,
					}
					Metrics:_ObserveSaveDiagnosticForTests(p, row)
					Metrics:_ObserveSaveDiagnosticForTests(p, row)
				end
				Metrics:_ObserveSaveDiagnosticForTests(p, {
					kind = "SaveAttemptCompleted",
					at = 20,
					generation = 4,
					attemptSequence = 2,
					ok = false,
					uncertain = true,
				})
				Metrics:_ObserveSaveDiagnosticForTests(p, {
					kind = "SaveAttemptCompleted",
					at = 20,
					generation = 3,
					attemptSequence = 99,
					ok = false,
					uncertain = true,
				})
				Metrics:_FlushSaveHealthForTests(p, 20)
				expect(events("SaveHealth", "SaveAttempts")[1].value).to.equal(5)
				expect(events("SaveHealth", "SaveFailures")[1].value).to.equal(5)
				expect(events("SaveHealth", "SaveUncertainAttempts")[1].value).to.equal(5)
				expect(#events("SaveHealth", "SaveLatencySeconds")).to.equal(0)
				Metrics:_ObserveSaveDiagnosticForTests(p, {
					kind = "SaveAttemptCompleted",
					at = 21,
					generation = 4,
					attemptSequence = 5,
					ok = false,
					uncertain = true,
				})
				Metrics:_ObserveSaveDiagnosticForTests(p, {
					kind = "SaveAttemptCompleted",
					at = 22,
					generation = 4,
					attemptSequence = 6,
					ok = true,
					uncertain = false,
				})
				Metrics:_ObserveSaveDiagnosticForTests(
					p,
					{ kind = "SaveConfirmed", at = 22, generation = 4, savedRevision = 1, currentRevision = 1 }
				)
				Metrics:_FlushSaveHealthForTests(p, 22)
				expect(events("SaveHealth", "SaveAttempts")[2].value).to.equal(1)
				expect(events("SaveHealth", "SaveFailures")[2].value).to.equal(0)
				expect(events("SaveHealth", "SaveUncertainAttempts")[2].value).to.equal(0)
			end
		)
		it("requires the real preview and confirmation before the durable rebirth funnel step", function()
			Adapter:_ResetForTests()
			local p = {}
			Adapter:ObserveRebirthQuote(p, { ok = true, rewardId = "EXP_018", route = "Cash", previewRevision = 2 })
			expect(
				Adapter:ObserveRebirthConfirm(p, { rewardId = "EXP_018", route = "Collection", previewRevision = 2 })
			).to.equal(false)
			expect(Adapter:ObserveRebirthConfirm(p, { rewardId = "EXP_018", route = "Cash", previewRevision = 2 })).to.equal(
				true
			)
			Adapter:Receipt(p, "Rebirth", {
				state = "Confirmed",
				operationId = "fixture",
				result = {
					rewardId = "EXP_018",
					rewardKind = "Expansion",
					route = "Cash",
					capacity = 18,
					sacrificedCash = 1000,
				},
			})
			local step4, expansion = 0, 0
			for _, event in drain() do
				if event.kind == "Funnel" and event.name == "RebirthTransaction" and event.step == 4 then
					step4 += 1
				end
				if event.kind == "Funnel" and event.name == "ExpansionProgression" and event.step == 1 then
					expansion += 1
				end
			end
			expect(step4).to.equal(1)
			expect(expansion).to.equal(1)
		end)
	end)
	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
