--!strict

return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

	describe("Phase 7B-1 upgrade catalogue", function()
		it("resolves only stable canonical IDs and never falls back", function()
			expect(Upgrades.Get("CART_SPEED_1").displayName).to.equal("Speed 1")
			expect(Upgrades.Get("Speed I")).to.equal(nil)
			expect(Upgrades.Get("500")).to.equal(nil)
			expect(Upgrades.Get("UNKNOWN")).to.equal(nil)
		end)

		it("releases eight player-wide sequential speed/cargo offers",function()
            local first,second=Upgrades.GetAll(),Upgrades.GetAll()
            expect(#first).to.equal(9)
            local released=Upgrades.GetReleased() expect(#released).to.equal(8)
            for index,offer in first do
                expect(offer.id).to.equal(second[index].id)
                if index>1 then expect(first[index-1].displayOrder<offer.displayOrder).to.equal(true) end
            end
            for _,offer in released do
                expect(offer.ownershipScope.kind).to.equal("PlayerWide")
                expect(offer.applicability.kind).to.equal("AllOwnedCarts")
                local level=offer.grant.level
                local prefix=if offer.grant.trackId=="Cargo" then "CARGO_" else "CART_SPEED_"
                expect(offer.requirements.priorOfferId).to.equal(if level>1 then prefix..(level-1) else nil)
            end
        end)

		it("keeps unapproved handling explicitly deferred and unavailable", function()
			for _, offerId in { "OFFROAD_1" } do
				local offer = assert(Upgrades.Get(offerId))
				expect(offer.releaseStatus).to.equal("Deferred")
				expect(offer.definitionStatus).to.equal("PendingDecision")
			end
		end)

		it("scales authoritative source prices once and explicit incremental effect units", function()
			expect(Upgrades.Get("CART_SPEED_1").price).to.equal(500000000)
			expect(Upgrades.Get("CARGO_1").price).to.equal(1500000000)
			expect(Upgrades.Get("CART_SPEED_2").price).to.equal(2500000000)
			expect(Upgrades.Get("CARGO_2").price).to.equal(12500000000)
			expect(Upgrades.Get("OFFROAD_1").price).to.equal(12000000)
			expect(Upgrades.Get("CART_SPEED_2").effect.value).to.equal(0.10)
			expect(Upgrades.Get("CARGO_2").effect.value).to.equal(1)
		end)

		it("composes speed fractions additively from the unchanged synthetic baseline", function()
			local first =
				assert(Upgrades.PreviewDeclaredResult("CartBaseSpeed", 60, { "CART_SPEED_1" }))
			local combined = assert(
				Upgrades.PreviewDeclaredResult(
					"CartBaseSpeed",
					60,
					{ "CART_SPEED_1", "CART_SPEED_2" }
				)
			)
			expect(math.abs(first - 66) < 1e-9).to.equal(true)
			expect(math.abs(combined - 72) < 1e-9).to.equal(true)
		end)

		it("adds each cargo level once instead of treating level II as plus two", function()
			local cargoOne =
				assert(Upgrades.PreviewDeclaredResult("CargoCapacity", 3, { "CARGO_1" }))
			local cargoTwo =
				assert(Upgrades.PreviewDeclaredResult("CargoCapacity", 3, { "CARGO_1", "CARGO_2" }))
			expect(cargoOne).to.equal(4)
			expect(cargoTwo).to.equal(5)
		end)

		it(
			"reports pending decisions without treating the review catalogue as malformed",
			function()
				local report = Upgrades.Validate()
				expect(report.IsValid).to.equal(true)
				expect(#report.Errors).to.equal(0)
				expect(#report.Blockers > 0).to.equal(true)
			end
		)

		it("rejects invalid prices and a released offer with no approved scope", function()
			local source = table.clone(Upgrades.GetAll())
			local invalidPrice = table.clone(source[1])
			invalidPrice.price = math.huge
			local missingScope = table.clone(source[2])
			missingScope.ownershipScope = nil
			missingScope.definitionStatus = "Complete"
			missingScope.releaseStatus = "Released"
			local report = Upgrades.ValidateDefinitions({ invalidPrice, missingScope }, {})
			expect(report.IsValid).to.equal(false)
			local codes = {}
			for _, issue in report.Errors do
				codes[issue.code] = true
			end
			expect(codes.INVALID_PRICE).to.equal(true)
			expect(codes.INVALID_OWNERSHIP_SCOPE).to.equal(true)
		end)

		it("rejects display text that disagrees with typed effect data", function()
			local source = table.clone(Upgrades.GetAll())
			local mismatch = table.clone(source[1])
			mismatch.effect = table.clone(mismatch.effect)
			mismatch.effect.summary = "+40% cart speed"
			local report = Upgrades.ValidateDefinitions({ mismatch }, {})
			expect(report.IsValid).to.equal(false)
			expect(report.Errors[1].code).to.equal("EFFECT_SUMMARY_MISMATCH")
		end)

		it("rejects empty or noncanonical compatible-cart lists", function()
			local source = table.clone(assert(Upgrades.Get("CART_SPEED_1")))
			source.applicability = { kind = "CartModel", cartIds = {} }
			local empty = Upgrades.ValidateDefinitions({ source }, {})
			expect(empty.IsValid).to.equal(false)
			expect(empty.Errors[1].code).to.equal("EMPTY_COMPATIBLE_CARTS")

			source.applicability = { kind = "CartModel", cartIds = { StarterCart = true } }
			local invalid = Upgrades.ValidateDefinitions({ source }, {})
			expect(invalid.IsValid).to.equal(false)
			expect(invalid.Errors[1].code).to.equal("INVALID_COMPATIBLE_CART")
		end)

		it("does not revive obsolete tether or gadget-cooldown rows as buyable offers", function()
			expect(Upgrades.Get("TETHER_1")).to.equal(nil)
			expect(Upgrades.Get("TETHER_2")).to.equal(nil)
			expect(Upgrades.Get("GADGET_COOLDOWN_1")).to.equal(nil)
		end)
	end)
	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
