--!nocheck

return function()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local UpgradeService = require(script.Parent.Parent.Services.UpgradeService)
	local Eligibility = require(ReplicatedStorage.Shared.Utility.UpgradeEligibility)
	local RealCatalogue = require(ReplicatedStorage.Shared.Config.Upgrades)

	local function copySource(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, child in value do
			copy[key] = copySource(child)
		end
		return copy
	end

	local function expectSourceEqual(actual, expected)
		expect(type(actual)).to.equal(type(expected))
		if type(expected) ~= "table" then
			expect(actual).to.equal(expected)
			return
		end
		for key, child in expected do
			expectSourceEqual(actual[key], child)
		end
		for key in actual do
			expect(expected[key] ~= nil).to.equal(true)
		end
	end

	local function expectNoMutation(context, before)
		expectSourceEqual(context.data, before)
		expect(context.getRevision()).to.equal(0)
		expect(context.getSaveRequests()).to.equal(0)
		expect(context.getGrants()).to.equal(0)
	end

	local function offer(id, price, order)
		return {
			id = id,
			displayName = id == "FIXTURE_A" and "Fixture A" or "Fixture B",
			category = "Cargo",
			price = price,
			currencyId = "Cash",
			grant = { kind = "UpgradeTrackLevel", trackId = id, level = 1 },
			ownershipScope = { kind = "PlayerWide" },
			applicability = { kind = "AllOwnedCarts" },
			requirements = {},
			effect = {
				statId = "CargoCapacity",
				operation = "AddSlots",
				value = 1,
				unit = "Slots",
				summary = "+1 cargo slot",
			},
			displayOrder = order,
			definitionStatus = "Complete",
			releaseStatus = "Released",
			effectStatus = "ReadyFixtureOnly",
			openDecisionCodes = {},
		}
	end

	local function fixture(callback, options)
		UpgradeService:Stop()
		local part = Instance.new("Part")
		part.Name = "SPEC_UPGRADE_STALL"
		part.Anchored = true
		part.Parent = workspace
		local player = {
			Name = "UpgradeSpecPlayer",
			UserId = -77001,
			Parent = Players,
		}
		local session = { Player = player, UserId = player.UserId, Generation = 1 }
		local data = {
			SchemaVersion = 2,
			Economy = {
				Balance = if options and options.balance ~= nil then options.balance else 1000.5,
			},
			Progression = { Upgrades = {} },
			Collection = {
				BrainrotInstances = { A = { speciesId = "BRT_007" } },
			},
			Base = {
				Slots = {
					["2"] = { brainrotId = "A", accumulatedCash = 0 },
					["4"] = { accumulatedCash = 120.25 },
				},
			},
		}
		local revision = 0
		local saveRequests = 0
		local observations = {}
		local observationCountAtSave = nil
		local writable = true
		local worldReady = true
		local inRange = true
		local profile = {}
		function profile:IsWritable(subject)
			return subject == player and session ~= nil and writable
		end
		function profile:GetSessionHandle(subject)
			return if subject == player then session else nil
		end
		function profile:IsCurrentSessionHandle(handle)
			return handle == session
		end
		function profile:GetReadableData(subject)
			return if subject == player then data else nil
		end
		function profile:GetWritableData(subject)
			return if self:IsWritable(subject) then data else nil
		end
		function profile:CommitMutation(subject, mutate)
			if not self:IsWritable(subject) then
				return { ok = false, code = "PROFILE_NOT_READY" }
			end
			local committed, result = mutate(data)
			if committed ~= true then
				return result
			end
			revision += 1
			result.ok = true
			result.committed = true
			result.revision = revision
			return result
		end
		function profile:RequestSave(subject, reason)
			expect(subject).to.equal(player)
			expect(type(reason)).to.equal("string")
			saveRequests += 1
			observationCountAtSave = #observations
			if options and options.confirmSynchronously then
				UpgradeService:_TestConfirmSave(subject, revision)
			end
			return { ok = true, code = "SCHEDULED" }
		end

		local offers = {
			offer("FIXTURE_A", 500, 10),
			offer("FIXTURE_B", 750, 20),
		}
		local byId = {}
		for _, definition in offers do
			byId[definition.id] = definition
		end
		local catalogue = {}
		function catalogue.Get(id)
			return byId[id]
		end
		function catalogue.GetAll()
			return table.clone(offers)
		end

		local sequence = 0
		local clock = 100
		local grants = 0
		local lastGrantTarget = nil
		UpgradeService:Init({
			Profile = profile,
			Currency = {
				PrepareSpend = function(_, profileData, cost)
					return Currency:PrepareSpend(profileData, cost)
				end,
				SyncBalance = function() end,
			},
			Catalogue = catalogue,
			Eligibility = Eligibility,
			Readiness = {
				effectReadyByOfferId = { FIXTURE_A = true, FIXTURE_B = true },
				persistenceReadyByScope = { PlayerWide = true },
				cartAcquisitionByTier = {},
				rankProviderOperational = false,
			},
			WorldReady = function(subject)
				return subject == player and worldReady
			end,
			WithinShopRange = function(subject, target)
				return subject == player and target == part and inRange
			end,
			ResolveTarget = function()
				return nil, if options then options.targetReason else nil
			end,
			BuildPlayerSnapshot = function(subject, profileData)
				return {
					status = "Ready",
					userId = subject.UserId,
					balance = profileData.Economy.Balance,
					ownedOfferIds = profileData.Progression.Upgrades,
				}
			end,
			ApplyGrant = function(profileData, definition, target)
				if profileData.Progression.Upgrades[definition.id] then
					return false, "ALREADY_OWNED"
				end
				profileData.Progression.Upgrades[definition.id] = true
				grants += 1
				lastGrantTarget = target
				return true, nil
			end,
			Now = function()
				return clock
			end,
			GenerateId = function()
				sequence += 1
				return "context-" .. sequence
			end,
		})
		local observationConnection = UpgradeService:SubscribeObservations(function(subject, receipt)
			expect(subject).to.equal(player)
			table.insert(observations, receipt)
			if options and options.observerThrows then
				error("synthetic telemetry delivery failure")
			end
		end)
		local opened = UpgradeService:OpenShop(player, part)
		assert(opened.ok, opened.code)
		local contextId = opened.payload.contextId

		local ok, problem = xpcall(function()
			callback({
				player = player,
				part = part,
				profile = profile,
				data = data,
				offers = offers,
				contextId = contextId,
				observations = observations,
				getObservationCountAtSave = function()
					return observationCountAtSave
				end,
				setSession = function(value)
					session = value
				end,
				getSession = function()
					return session
				end,
				getRevision = function()
					return revision
				end,
				getSaveRequests = function()
					return saveRequests
				end,
				getGrants = function()
					return grants
				end,
				getLastGrantTarget = function()
					return lastGrantTarget
				end,
				setWritable = function(value)
					writable = value
				end,
				setWorldReady = function(value)
					worldReady = value
				end,
				setInRange = function(value)
					inRange = value
				end,
				setClock = function(value)
					clock = value
				end,
			})
		end, debug.traceback)
		observationConnection.Disconnect()
		UpgradeService:Stop()
		part:Destroy()
		assert(ok, problem)
	end

	local function request(context, requestId, offerId)
		return UpgradeService:Purchase(context.player, {
			contextId = context.contextId,
			requestId = requestId,
			offerId = offerId,
		})
	end

	describe("Phase 7B-2 upgrade purchase service", function()
		it("rejects malformed purchase payloads and each invalid identifier without mutation", function()
			for _, invalid in { false, 7, "Purchase" } do
				fixture(function(context)
					local before = copySource(context.data)
					expect(UpgradeService:Purchase(context.player, invalid).code).to.equal("INVALID_REQUEST")
					expect(UpgradeService:Purchase(context.player, nil).code).to.equal("INVALID_REQUEST")
					expectNoMutation(context, before)
				end)
			end
			for _, field in { "contextId", "requestId", "offerId" } do
				for _, invalid in { false, 17, {}, "", string.rep("x", 129), "invalid\nidentifier" } do
					fixture(function(context)
						local before = copySource(context.data)
						local payload = {
							contextId = context.contextId,
							requestId = "invalid-field",
							offerId = "FIXTURE_A",
						}
						payload[field] = invalid
						expect(UpgradeService:Purchase(context.player, payload).code).to.equal("INVALID_REQUEST")
						payload[field] = nil
						expect(UpgradeService:Purchase(context.player, payload).code).to.equal("INVALID_REQUEST")
						expectNoMutation(context, before)
					end)
				end
			end
		end)

		it("rejects foreign expired stale unready and out-of-range purchase contexts without mutation", function()
			local cases = {
				{
					code = "INVALID_CONTEXT",
					prepare = function(context)
						context.contextId = "foreign-context"
					end,
				},
				{
					code = "INVALID_CONTEXT",
					prepare = function(context)
						context.player = { Name = "OtherUpgradePlayer", UserId = -77002, Parent = Players }
					end,
				},
				{
					code = "CONTEXT_EXPIRED",
					prepare = function(context)
						context.setClock(220)
					end,
				},
				{
					code = "SESSION_CHANGED",
					prepare = function(context)
						context.setSession({
							Player = context.player,
							UserId = context.player.UserId,
							Generation = 2,
						})
					end,
				},
				{
					code = "SESSION_CHANGED",
					prepare = function(context)
						context.setWritable(false)
					end,
				},
				{
					code = "WORLD_NOT_READY",
					prepare = function(context)
						context.setWorldReady(false)
					end,
				},
				{
					code = "TOO_FAR_AWAY",
					prepare = function(context)
						context.setInRange(false)
					end,
				},
				{
					code = "TOO_FAR_AWAY",
					prepare = function(context)
						context.part.Parent = nil
					end,
				},
			}
			for _, case in cases do
				fixture(function(context)
					local before = copySource(context.data)
					case.prepare(context)
					expect(request(context, "invalid-context", "FIXTURE_A").code).to.equal(case.code)
					expectNoMutation(context, before)
				end)
			end
		end)

		it("ignores forged purchase economics and targets while preserving authoritative source", function()
			for _, balance in { 100.5, 1000.5 } do
				fixture(function(context)
					local expected = copySource(context.data)
					local result = UpgradeService:Purchase(context.player, {
						contextId = context.contextId,
						requestId = "forged-economics",
						offerId = "FIXTURE_A",
						price = 0,
						chargedAmount = -500,
						balance = 999999999,
						balanceBefore = 999999999,
						balanceAfter = 999999999,
						grant = {
							kind = "UpgradeTrackLevel",
							trackId = "FIXTURE_B",
							level = 99,
						},
						target = { durableCartId = "other-player-cart", ownerUserId = -77002 },
						targetKey = "other-player-cart",
					})
					if balance < 500 then
						expect(result.code).to.equal("INSUFFICIENT_FUNDS")
						expectNoMutation(context, expected)
					else
						expect(result.outcome).to.equal("Accepted")
						expect(result.chargedAmount).to.equal(500)
						expect(result.balance).to.equal(500.5)
						expected.Economy.Balance = 500.5
						expected.Progression.Upgrades.FIXTURE_A = true
						expectSourceEqual(context.data, expected)
						expect(context.getLastGrantTarget()).to.equal(nil)
						expect(context.getRevision()).to.equal(1)
						expect(context.getSaveRequests()).to.equal(1)
						expect(context.getGrants()).to.equal(1)
					end
				end, { balance = balance })
			end
		end)

		it("enforces the purchase burst budget without spending and refills on server time", function()
			fixture(function(context)
				local before = copySource(context.data)
				for index = 1, 6 do
					expect(request(context, "unknown-" .. index, "FORGED_OFFER").code).to.equal("UNKNOWN_OFFER")
				end
				expect(request(context, "limited", "FIXTURE_A").code).to.equal("RATE_LIMITED")
				expectNoMutation(context, before)
				context.setClock(101)
				local accepted = request(context, "refilled", "FIXTURE_A")
				expect(accepted.outcome).to.equal("Accepted")
				before.Economy.Balance = 500.5
				before.Progression.Upgrades.FIXTURE_A = true
				expectSourceEqual(context.data, before)
				expect(context.getRevision()).to.equal(1)
				expect(context.getSaveRequests()).to.equal(1)
				expect(context.getGrants()).to.equal(1)
			end)
		end)

		it("observes the actual immutable purchase commit before requesting its save", function()
			fixture(function(context)
				context.setClock(120)
				local forwarded, forwardedSubject, forwardedOffer, forwardedRevision
				local forwardedConnection = UpgradeService:SubscribePurchaseCommitted(
					function(subject, committedOffer, _target, revision, receipt)
						forwarded, forwardedSubject, forwardedOffer, forwardedRevision =
							receipt, subject, committedOffer, revision
					end
				)
				local result = request(context, "observed-direct", "FIXTURE_A")
				expect(result.outcome).to.equal("Accepted")
				expect(#context.observations).to.equal(2)
				local receipt = context.observations[2]
				expect(receipt.kind).to.equal("PurchaseCommitted")
				expect(table.isfrozen(receipt)).to.equal(true)
				expect(receipt.at).to.equal(120)
				expect(receipt.requestId).to.equal("observed-direct")
				expect(receipt.balanceBefore).to.equal(1000.5)
				expect(receipt.balanceAfter).to.equal(500.5)
				expect(receipt.price).to.equal(500)
				expect(receipt.chargedAmount).to.equal(500)
				expect(receipt.sessionGeneration).to.equal(1)
				expect(type(receipt.operationSequence)).to.equal("number")
				expect(receipt.commitRevision).to.equal(1)
				expect(receipt.ready and receipt.prerequisitesSatisfied and receipt.fundsSufficient).to.equal(true)
				expect(context.getObservationCountAtSave()).to.equal(2)
				-- A later balance cannot rewrite the earlier immutable receipt,
				-- even if the Bindable callback is delivered on a later scheduler turn.
				context.data.Economy.Balance = 17.25
				task.wait()
				forwardedConnection:Disconnect()
				-- BindableEvent copies synthetic table actors; production Players are Instances.
				expect(forwardedSubject.UserId).to.equal(context.player.UserId)
				expect(forwardedOffer.id).to.equal("FIXTURE_A")
				expect(forwardedRevision).to.equal(1)
				expect(forwarded.offerId).to.equal(receipt.offerId)
				expect(forwarded.commitRevision).to.equal(receipt.commitRevision)
				expect(forwarded.balanceAfter).to.equal(500.5)
				expect(request(context, "observed-direct", "FIXTURE_A").duplicate).to.equal(true)
				expect(#context.observations).to.equal(2)
			end)
		end)

		it("orders a synchronous covering acknowledgement after its purchase commit receipt", function()
			fixture(function(context)
				local result = request(context, "immediate-save", "FIXTURE_A")
				expect(result.persistence).to.equal("Confirmed")
				expect(#context.observations).to.equal(3)
				local committed, confirmed = context.observations[2], context.observations[3]
				expect(committed.kind).to.equal("PurchaseCommitted")
				expect(confirmed.kind).to.equal("PurchaseSaveConfirmed")
				expect(confirmed.commitRevision).to.equal(committed.commitRevision)
				expect(confirmed.sessionGeneration).to.equal(committed.sessionGeneration)
				UpgradeService:_TestConfirmSave(context.player, result.commitRevision)
				expect(#context.observations).to.equal(3)
			end, { confirmSynchronously = true })
		end)

		it("observes bounded current-context attempts without replaying accepted results", function()
			fixture(function(context)
				local payload = {
					operation = "Purchase",
					contextId = context.contextId,
					requestId = "request-observed",
					offerId = "FIXTURE_A",
				}
				expect(UpgradeService:HandleRequest(context.player, payload).outcome).to.equal("Accepted")
				expect(#context.observations).to.equal(3)
				expect(context.observations[2].kind).to.equal("PurchaseAttempt")
				expect(context.observations[3].kind).to.equal("PurchaseCommitted")
				expect(UpgradeService:HandleRequest(context.player, payload).duplicate).to.equal(true)
				expect(#context.observations).to.equal(3)
				for _, invalid in { string.rep("x", 129), "invalid\nrequest" } do
					payload.requestId = invalid
					expect(UpgradeService:HandleRequest(context.player, payload).code).to.equal("INVALID_REQUEST")
				end
				payload.requestId, payload.contextId = "wrong-context", "not-this-context"
				expect(UpgradeService:HandleRequest(context.player, payload).code).to.equal("INVALID_CONTEXT")
				expect(#context.observations).to.equal(3)
				payload.requestId, payload.contextId, payload.offerId = "rejected", context.contextId, "FIXTURE_B"
				expect(UpgradeService:HandleRequest(context.player, payload).code).to.equal("INSUFFICIENT_FUNDS")
				expect(#context.observations).to.equal(5)
				expect(context.observations[5].kind).to.equal("PurchaseResult")
				expect(context.observations[5].accepted).to.equal(false)
			end)
		end)

		it("sequences covering save observations by delivery rather than purchase order", function()
			fixture(function(context)
				local first = request(context, "purchase-earlier", "FIXTURE_A")
				local second = request(context, "purchase-later", "FIXTURE_B")
				expect(first.outcome).to.equal("Accepted")
				expect(second.outcome).to.equal("Accepted")
				local commitsById = {}
				for _, receipt in context.observations do
					if receipt.kind == "PurchaseCommitted" then
						commitsById[receipt.requestId] = receipt
					end
				end
				local lastDeliverySequence = commitsById[second.requestId].operationSequence
				UpgradeService:_TestConfirmSave(context.player, second.commitRevision)
				local confirmations = 0
				for _, receipt in context.observations do
					if receipt.kind == "PurchaseSaveConfirmed" then
						confirmations += 1
						expect(receipt.operationSequence > lastDeliverySequence).to.equal(true)
						lastDeliverySequence = receipt.operationSequence
						expect(receipt.purchaseOperationSequence).to.equal(
							commitsById[receipt.requestId].operationSequence
						)
					end
				end
				expect(confirmations).to.equal(2)
				expect(context.getRevision()).to.equal(2)
				expect(context.getSaveRequests()).to.equal(2)
				expect(context.data.Economy.Balance).to.equal(750.5)
				local countBeforeReplay = #context.observations
				UpgradeService:_TestConfirmSave(context.player, second.commitRevision)
				expect(#context.observations).to.equal(countBeforeReplay)
			end, { balance = 2000.5 })
		end)

		it("rejects unbounded or economic client fields from presentation observations", function()
			fixture(function(context)
				local payload = {
					contextId = context.contextId,
					kind = "MenuRendered",
					inputCategory = "Touch",
				}
				for _, extra in
					{
						{ offerId = string.rep("x", 129) },
						{ offerId = "FIXTURE_A" },
						{ wallet = 123 },
						{ properties = {} },
					}
				do
					local invalid = table.clone(payload)
					for key, value in extra do
						invalid[key] = value
					end
					expect(UpgradeService:ObservePresentation(context.player, invalid).ok).to.equal(false)
				end
				expect(#context.observations).to.equal(1)
				expect(UpgradeService:ObservePresentation(context.player, payload).ok).to.equal(true)
				expect(UpgradeService:ObservePresentation(context.player, payload).ok).to.equal(true)
				expect(#context.observations).to.equal(2)
				expect(context.observations[2].sessionGeneration).to.equal(1)
				expect(context.observations[2].inputCategory).to.equal("Touch")
				payload.kind, payload.offerId = "OfferInspected", "NOT_INCLUDED"
				expect(UpgradeService:ObservePresentation(context.player, payload).code).to.equal("UNKNOWN_OFFER")
				expect(#context.observations).to.equal(2)
				payload.offerId = "FIXTURE_A"
				expect(UpgradeService:ObservePresentation(context.player, payload).ok).to.equal(true)
				expect(UpgradeService:ObservePresentation(context.player, payload).ok).to.equal(true)
				expect(#context.observations).to.equal(3)
				expect(context.observations[3].offerKey).to.equal(
					UpgradeService:GetMeasurementOffers(context.player)[1].offerKey
				)
			end)
		end)

		it("limits presentation work without spending purchase rate tokens", function()
			fixture(function(context)
				local payload = {
					contextId = context.contextId,
					kind = "MenuRendered",
					inputCategory = "Unknown",
				}
				local limited = false
				for _ = 1, 12 do
					limited = UpgradeService:ObservePresentation(context.player, payload).code == "RATE_LIMITED"
						or limited
				end
				expect(limited).to.equal(true)
				expect(#context.observations).to.equal(2)
				expect(request(context, "unaffected-purchase", "FIXTURE_A").outcome).to.equal("Accepted")
			end)
		end)

		it("versions measurement terms when effect or prerequisite configuration changes", function()
			fixture(function(context)
				local first = UpgradeService:GetMeasurementOffers(context.player)[1]
				context.offers[1].effect.value = 2
				local effectChanged = UpgradeService:GetMeasurementOffers(context.player)[1]
				expect(effectChanged.termsVersion ~= first.termsVersion).to.equal(true)
				context.offers[1].requirements.requiredRank = 3
				local requirementsChanged = UpgradeService:GetMeasurementOffers(context.player)[1]
				expect(requirementsChanged.termsVersion ~= effectChanged.termsVersion).to.equal(true)
				expect(context.data.Economy.Balance).to.equal(1000.5)
				expect(context.getRevision()).to.equal(0)
				expect(context.getSaveRequests()).to.equal(0)
			end)
		end)

		it("does not undo or repeat a purchase when an observation subscriber throws", function()
			fixture(function(context)
				expect(request(context, "telemetry-throws", "FIXTURE_A").outcome).to.equal("Accepted")
				expect(context.getGrants()).to.equal(1)
				expect(context.getRevision()).to.equal(1)
				expect(context.getSaveRequests()).to.equal(1)
				expect(context.data.Economy.Balance).to.equal(500.5)
			end, { observerThrows = true })
		end)

		it("reports unavailable scope targets without hiding independent prerequisites", function()
			fixture(function(context)
				local measured = UpgradeService:GetMeasurementOffers(context.player)[1]
				expect(measured.ready).to.equal(false)
				expect(measured.pathBlocked).to.equal(true)
				expect(measured.prerequisitesSatisfied).to.equal(true)
				expect(measured.fundsSufficient).to.equal(true)
				expect(measured.primaryReason).to.equal("TARGET_UNAVAILABLE")
				expect(context.getRevision()).to.equal(0)
				expect(context.getSaveRequests()).to.equal(0)
			end, { targetReason = "TARGET_UNAVAILABLE" })
		end)

		it("commits wallet and ownership in one revision without touching banked/base state", function()
			fixture(function(context)
				local ownedBefore = context.data.Collection.BrainrotInstances.A
				local slotBefore = context.data.Base.Slots["2"]
				local emptyCash = context.data.Base.Slots["4"].accumulatedCash
				local result = request(context, "request-a", "FIXTURE_A")
				expect(result.outcome).to.equal("Accepted")
				expect(result.balance).to.equal(500.5)
				expect(result.chargedAmount).to.equal(500)
				expect(result.commitRevision).to.equal(1)
				expect(result.persistence).to.equal("Pending")
				expect(context.data.Progression.Upgrades.FIXTURE_A).to.equal(true)
				expect(context.data.Collection.BrainrotInstances.A).to.equal(ownedBefore)
				expect(context.data.Base.Slots["2"]).to.equal(slotBefore)
				expect(context.data.Base.Slots["4"].accumulatedCash).to.equal(emptyCash)
				expect(context.getRevision()).to.equal(1)
				expect(context.getSaveRequests()).to.equal(1)
				expect(context.getGrants()).to.equal(1)
			end)
		end)

		it("returns the same request result and persistent ownership prevents a second charge", function()
			fixture(function(context)
				local first = request(context, "same", "FIXTURE_A")
				local duplicate = request(context, "same", "FIXTURE_A")
				local freshId = request(context, "fresh", "FIXTURE_A")
				expect(first.outcome).to.equal("Accepted")
				expect(duplicate.outcome).to.equal("Accepted")
				expect(duplicate.duplicate).to.equal(true)
				expect(freshId.code).to.equal("ALREADY_OWNED")
				expect(context.data.Economy.Balance).to.equal(500.5)
				expect(context.getRevision()).to.equal(1)
				expect(context.getGrants()).to.equal(1)
			end)
		end)

		it("rejects a reused request ID with a different concrete offer", function()
			fixture(function(context)
				request(context, "collision", "FIXTURE_A")
				local mismatched = request(context, "collision", "FIXTURE_B")
				expect(mismatched.code).to.equal("REQUEST_ID_MISMATCH")
				expect(context.data.Progression.Upgrades.FIXTURE_B).to.equal(nil)
				expect(context.data.Economy.Balance).to.equal(500.5)
			end)
		end)

		it("serializes competing purchases against the current wallet", function()
			fixture(function(context)
				local first = request(context, "buy-b", "FIXTURE_B")
				local second = request(context, "buy-a", "FIXTURE_A")
				expect(first.outcome).to.equal("Accepted")
				expect(second.code).to.equal("INSUFFICIENT_FUNDS")
				expect(context.data.Economy.Balance).to.equal(250.5)
				expect(context.data.Progression.Upgrades.FIXTURE_B).to.equal(true)
				expect(context.data.Progression.Upgrades.FIXTURE_A).to.equal(nil)
				expect(context.getRevision()).to.equal(1)
			end)
		end)

		it("requires another activation when server-owned offer terms change", function()
			fixture(function(context)
				context.offers[1].price = 600
				local result = request(context, "terms", "FIXTURE_A")
				expect(result.code).to.equal("OFFER_CHANGED")
				expect(context.data.Economy.Balance).to.equal(1000.5)
				expect(context.getGrants()).to.equal(0)
			end)
		end)

		it("distinguishes accepted from revision-confirmed persistence", function()
			fixture(function(context)
				local accepted = request(context, "save", "FIXTURE_A")
				expect(accepted.persistence).to.equal("Pending")
				UpgradeService:_TestConfirmSave(context.player, accepted.commitRevision - 1)
				local pending = UpgradeService:GetRequestStatus(context.player, {
					contextId = context.contextId,
					requestId = "save",
					offerId = "FIXTURE_A",
				})
				expect(pending.persistence).to.equal("Pending")
				UpgradeService:_TestConfirmSave(context.player, accepted.commitRevision)
				local confirmed = UpgradeService:GetRequestStatus(context.player, {
					contextId = context.contextId,
					requestId = "save",
					offerId = "FIXTURE_A",
				})
				expect(confirmed.persistence).to.equal("Confirmed")
			end)
		end)

		it("does not confirm a purchase after the exact profile session changes", function()
			fixture(function(context)
				local accepted = request(context, "old-session", "FIXTURE_A")
				context.setSession({
					Player = context.player,
					UserId = context.player.UserId,
					Generation = 2,
				})
				local observedBeforeOldAcknowledgement = #context.observations
				UpgradeService:_TestConfirmSave(context.player, accepted.commitRevision)
				expect(#context.observations).to.equal(observedBeforeOldAcknowledgement)
				local status = UpgradeService:GetRequestStatus(context.player, {
					contextId = context.contextId,
					requestId = "old-session",
					offerId = "FIXTURE_A",
				})
				expect(status.persistence).to.equal("Pending")
			end)
		end)

		it("retains a coherent ownership-and-wallet snapshot for a fresh session", function()
			fixture(function(context)
				request(context, "persist", "FIXTURE_A")
				local snapshot = table.clone(context.data)
				snapshot.Economy = table.clone(context.data.Economy)
				snapshot.Progression = table.clone(context.data.Progression)
				snapshot.Progression.Upgrades = table.clone(context.data.Progression.Upgrades)
				expect(snapshot.Economy.Balance).to.equal(500.5)
				expect(snapshot.Progression.Upgrades.FIXTURE_A).to.equal(true)
			end)
		end)

		it("keeps every real catalogue offer unavailable and never calls a grant", function()
			fixture(function(context)
				UpgradeService:Stop()
				UpgradeService:Init({
					Profile = context.profile,
					Currency = {
						PrepareSpend = function(_, profileData, cost)
							return Currency:PrepareSpend(profileData, cost)
						end,
						SyncBalance = function() end,
					},
					Catalogue = RealCatalogue,
					Eligibility = Eligibility,
					WorldReady = function()
						return true
					end,
					WithinShopRange = function()
						return true
					end,
					BuildPlayerSnapshot = function(subject, profileData)
						return {
							status = "Ready",
							userId = subject.UserId,
							balance = profileData.Economy.Balance,
						}
					end,
					ApplyGrant = function()
						error("production grant must remain unreachable")
					end,
					Now = function()
						return 100
					end,
					GenerateId = function()
						return "real-context"
					end,
				})
				local opened = assert(
					UpgradeService:OpenShop(context.player, context.part).payload,
					"expected real catalogue review context"
				)
				for _, card in opened.offers do
					expect(card.canActivate).to.equal(false)
				end
				local result = UpgradeService:Purchase(context.player, {
					contextId = opened.contextId,
					requestId = "real-offer",
					offerId = "CARGO_1",
				})
				expect(result.outcome).to.equal("Rejected")
				expect(context.data.Economy.Balance).to.equal(1000.5)
			end)
		end)
	end)
end
