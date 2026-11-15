--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
	local Resolver = require(ReplicatedStorage.Shared.Utility.CartPerformanceResolver)

	local cartDefinitions = {
		CRT_TEST_30 = { MaxTravelSpeed = 30 },
		CRT_TEST_40 = { MaxTravelSpeed = 40 },
		CRT_001 = { MaxTravelSpeed = 30 },
		CRT_999 = { MaxTravelSpeed = 40 },
	}
	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) <= 1e-9
	end

	local function readyOffer(id: string, scopeKind: string?, applicationKind: string?): any
		local offer = table.clone(assert(Upgrades.Get(id)))
		offer.definitionStatus = "Complete"
		offer.effectStatus = "Ready"
		offer.releaseStatus = "Released"
		offer.ownershipScope = { kind = scopeKind or "PlayerWide" }
		offer.applicability = { kind = applicationKind or "AllOwnedCarts" }
		return offer
	end

	local function owner(ownedIds: { string }?): any
		local ids = {}
		for _, id in ownedIds or {} do
			ids[id] = true
		end
		return {
			status = "Ready",
			userId = 101,
			ownedOfferIds = ids,
			ownedCarts = {},
		}
	end

	local function resolve(baseId: string, snapshot: any?, offers: { any }, descriptor: any?): any
		return Resolver.Resolve(snapshot, descriptor or {
			cartId = baseId,
			ownerUserId = 101,
		}, {
			cartDefinitions = cartDefinitions,
			offers = offers,
		})
	end

	describe("Phase 7D cart performance resolver", function()
		it("adds Speed I and II as base-relative contributions", function()
			local speedOne = readyOffer("CART_SPEED_1")
			local speedTwo = readyOffer("CART_SPEED_2")
			local noUpgrade = resolve("CRT_TEST_30", owner(), { speedOne, speedTwo })
			local speedOne30 =
				resolve("CRT_TEST_30", owner({ "CART_SPEED_1" }), { speedOne, speedTwo })
			local both30 = resolve(
				"CRT_TEST_30",
				owner({ "CART_SPEED_1", "CART_SPEED_2" }),
				{ speedOne, speedTwo }
			)
			local speedOne40 =
				resolve("CRT_TEST_40", owner({ "CART_SPEED_1" }), { speedOne, speedTwo })
			local both40 = resolve(
				"CRT_TEST_40",
				owner({ "CART_SPEED_1", "CART_SPEED_2" }),
				{ speedOne, speedTwo }
			)
			expect(noUpgrade.resolvedSpeed).to.equal(30)
			expect(near(speedOne30.resolvedSpeed, 33)).to.equal(true)
			expect(near(both30.resolvedSpeed, 36)).to.equal(true)
			expect(near(speedOne40.resolvedSpeed, 44)).to.equal(true)
			expect(near(both40.resolvedSpeed, 48)).to.equal(true)
		end)

		it("recomputes idempotently without mutating definitions or ownership", function()
			local speedOne = readyOffer("CART_SPEED_1")
			local snapshot = owner({ "CART_SPEED_1" })
			for _ = 1, 100 do
				local result = resolve("CRT_TEST_30", snapshot, { speedOne })
				expect(near(result.resolvedSpeed, 33)).to.equal(true)
				expect(result.purchasedSpeedContribution).to.equal(0.10)
				expect(result.controlReferenceSpeed).to.equal(30)
			end
			expect(cartDefinitions.CRT_TEST_30.MaxTravelSpeed).to.equal(30)
			expect(speedOne.effect.value).to.equal(0.10)
			expect(snapshot.ownedOfferIds.CART_SPEED_1).to.equal(true)
		end)

		it("fails closed when an approved speed effect lacks owner state", function()
			local result = resolve("CRT_TEST_30", nil, { readyOffer("CART_SPEED_1") })
			expect(result.status).to.equal("NotReady")
			expect(result.resolvedSpeed).to.equal(nil)
			expect(result.code).to.equal("OWNER_STATE_NOT_READY")
		end)

		it("applies the released player-wide Speed I to each owned cart model", function()
			local realOffers = {
				assert(Upgrades.Get("CART_SPEED_1")),
				assert(Upgrades.Get("CART_SPEED_2")),
				assert(Upgrades.Get("OFFROAD_1")),
			}
			local result = Resolver.Resolve(owner({ "CART_SPEED_1" }), {
				cartId = "CRT_001",
				ownerUserId = 101,
			}, { offers = realOffers, cartDefinitions = cartDefinitions })
			expect(result.status).to.equal("Ready")
			expect(result.baseSpeed).to.equal(30)
			expect(near(result.resolvedSpeed, 33)).to.equal(true)
			expect(result.appliedOfferIds[1]).to.equal("CART_SPEED_1")
			local incompatible = Resolver.Resolve(owner({ "CART_SPEED_1" }), {
				cartId = "CRT_999",
				ownerUserId = 101,
			}, { offers = realOffers, cartDefinitions = cartDefinitions })
			expect(incompatible.resolvedSpeed).to.equal(44)
			expect(#incompatible.appliedOfferIds).to.equal(1)
			expect(result.handlingSupported).to.equal(false)
			expect(result.handlingCode).to.equal("HANDLING_EFFECT_UNDEFINED")
		end)

		it("does not use purchase visibility to revoke an owned effect", function()
			local speedOne = readyOffer("CART_SPEED_1")
			speedOne.releaseStatus = "Deferred"
			local result = resolve("CRT_TEST_30", owner({ "CART_SPEED_1" }), { speedOne })
			expect(near(result.resolvedSpeed, 33)).to.equal(true)
		end)

		it("ignores unknown ownership and speculative level data", function()
			local speedOne = readyOffer("CART_SPEED_1")
			local snapshot = owner({ "UNKNOWN", "CART_SPEED_1" })
			snapshot.upgradeTrackLevels = { CartSpeed = 99 }
			local result = resolve("CRT_TEST_30", snapshot, { speedOne })
			expect(result.purchasedSpeedContribution).to.equal(0.10)
			expect(near(result.resolvedSpeed, 33)).to.equal(true)
		end)

		it("uses the cart owner and durable identity rather than driver state", function()
			local speedOne =
				readyOffer("CART_SPEED_1", "ParticularOwnedCart", "ParticularOwnedCart")
			local snapshot = owner()
			snapshot.ownedCarts.cartA = { ownedOfferIds = { CART_SPEED_1 = true } }
			snapshot.ownedCarts.cartB = { ownedOfferIds = {} }
			local onA = resolve("CRT_TEST_30", snapshot, { speedOne }, {
				cartId = "CRT_TEST_30",
				ownerUserId = 101,
				driverUserId = 202,
				durableCartId = "cartA",
			})
			local onB = resolve("CRT_TEST_30", snapshot, { speedOne }, {
				cartId = "CRT_TEST_30",
				ownerUserId = 101,
				driverUserId = 101,
				durableCartId = "cartB",
			})
			expect(near(onA.resolvedSpeed, 33)).to.equal(true)
			expect(onB.resolvedSpeed).to.equal(30)
			local foreign = resolve("CRT_TEST_30", snapshot, { speedOne }, {
				cartId = "CRT_TEST_30",
				ownerUserId = 202,
				durableCartId = "cartA",
			})
			expect(foreign.status).to.equal("InvalidOwner")
		end)

		it("rejects duplicate offer definitions instead of stacking them", function()
			local speedOne = readyOffer("CART_SPEED_1")
			local result = resolve("CRT_TEST_30", owner({ "CART_SPEED_1" }), { speedOne, speedOne })
			expect(result.status).to.equal("InvalidConfiguration")
			expect(result.code).to.equal("DUPLICATE_OFFER_ID")
		end)
	end)
end
