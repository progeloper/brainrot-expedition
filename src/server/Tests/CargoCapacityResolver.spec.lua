--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
	local Resolver = require(ReplicatedStorage.Shared.Utility.CargoCapacityResolver)

	local cartDefinitions = {
		CRT_TEST_3 = { CargoCapacity = 3 },
		CRT_TEST_4 = { CargoCapacity = 4 },
		CRT_001 = { CargoCapacity = 3 },
		CRT_999 = { CargoCapacity = 4 },
	}

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
		local target = descriptor or { cartId = baseId, ownerUserId = 101 }
		return Resolver.Resolve(snapshot, target, {
			cartDefinitions = cartDefinitions,
			offers = offers,
		})
	end

	describe("Phase 7C cargo capacity resolver", function()
		it("derives base plus each applicable incremental grant", function()
			local cargoOne = readyOffer("CARGO_1")
			local cargoTwo = readyOffer("CARGO_2")
			expect(resolve("CRT_TEST_3", owner(), { cargoOne, cargoTwo }).effectiveCapacity).to.equal(
				3
			)
			expect(
				resolve("CRT_TEST_3", owner({ "CARGO_1" }), { cargoOne, cargoTwo }).effectiveCapacity
			).to.equal(4)
			expect(
				resolve("CRT_TEST_3", owner({ "CARGO_1", "CARGO_2" }), { cargoOne, cargoTwo }).effectiveCapacity
			).to.equal(5)
			expect(
				resolve("CRT_TEST_4", owner({ "CARGO_1", "CARGO_2" }), { cargoOne, cargoTwo }).effectiveCapacity
			).to.equal(6)
		end)

		it("recomputes idempotently without mutating shared definitions", function()
			local cargoOne = readyOffer("CARGO_1")
			local snapshot = owner({ "CARGO_1" })
			for _ = 1, 100 do
				local result = resolve("CRT_TEST_3", snapshot, { cargoOne })
				expect(result.effectiveCapacity).to.equal(4)
				expect(result.upgradeBonus).to.equal(1)
			end
			expect(cartDefinitions.CRT_TEST_3.CargoCapacity).to.equal(3)
			expect(cargoOne.effect.value).to.equal(1)
		end)

		it("fails closed when an approved effect lacks loaded owner state", function()
			local result = resolve("CRT_TEST_3", nil, { readyOffer("CARGO_1") })
			expect(result.status).to.equal("NotReady")
			expect(result.effectiveCapacity).to.equal(nil)
			expect(result.code).to.equal("OWNER_STATE_NOT_READY")
		end)

		it("applies released player-wide Cargo I to every owned cart model", function()
			local realOffers = { assert(Upgrades.Get("CARGO_1")), assert(Upgrades.Get("CARGO_2")) }
			local result = resolve("CRT_001", owner({ "CARGO_1" }), realOffers)
			expect(result.status).to.equal("Ready")
			expect(result.effectiveCapacity).to.equal(4)
			expect(result.appliedOfferIds[1]).to.equal("CARGO_1")
			local incompatible = resolve("CRT_999", owner({ "CARGO_1" }), realOffers)
			expect(incompatible.effectiveCapacity).to.equal(5)
			expect(#incompatible.appliedOfferIds).to.equal(1)
			expect(#result.blockedOfferIds).to.equal(0)
		end)

		it("does not use purchase release state to confiscate an owned entitlement", function()
			local cargoOne = readyOffer("CARGO_1")
			cargoOne.releaseStatus = "Deferred"
			local result = resolve("CRT_TEST_3", owner({ "CARGO_1" }), { cargoOne })
			expect(result.effectiveCapacity).to.equal(4)
		end)

		it("ignores unknown ownership and a second speculative level representation", function()
			local cargoOne = readyOffer("CARGO_1")
			local snapshot = owner({ "UNKNOWN", "CARGO_1" })
			snapshot.upgradeTrackLevels = { Cargo = 99 }
			local result = resolve("CRT_TEST_3", snapshot, { cargoOne })
			expect(result.upgradeBonus).to.equal(1)
			expect(result.effectiveCapacity).to.equal(4)
		end)

		it("uses the cart owner and durable cart identity for per-cart grants", function()
			local cargoOne = readyOffer("CARGO_1", "ParticularOwnedCart", "ParticularOwnedCart")
			local snapshot = owner()
			snapshot.ownedCarts.cartA = { ownedOfferIds = { CARGO_1 = true } }
			snapshot.ownedCarts.cartB = { ownedOfferIds = {} }
			local onA = resolve("CRT_TEST_3", snapshot, { cargoOne }, {
				cartId = "CRT_TEST_3",
				ownerUserId = 101,
				durableCartId = "cartA",
			})
			local onB = resolve("CRT_TEST_3", snapshot, { cargoOne }, {
				cartId = "CRT_TEST_3",
				ownerUserId = 101,
				durableCartId = "cartB",
			})
			expect(onA.effectiveCapacity).to.equal(4)
			expect(onB.effectiveCapacity).to.equal(3)
			local foreign = resolve("CRT_TEST_3", snapshot, { cargoOne }, {
				cartId = "CRT_TEST_3",
				ownerUserId = 202,
				durableCartId = "cartA",
			})
			expect(foreign.status).to.equal("InvalidOwner")
		end)
	end)
end
