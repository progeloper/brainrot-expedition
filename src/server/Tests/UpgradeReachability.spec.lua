--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
	local Eligibility = require(ReplicatedStorage.Shared.Utility.UpgradeEligibility)

	local function definition(id: string, requirements: any?): any
		return {
			id = id,
			price = 100,
			requirements = requirements or {},
		}
	end

	local operational = {
		currencyEarningOperational = true,
		rankProviderOperational = true,
		cartAcquisitionByTier = { [1] = true, [2] = true, [3] = true },
	}

	describe("Phase 7B-1 prerequisite reachability", function()
		it(
			"finds all released sequential requirement paths operational in the current project",
			function()
				local report = Eligibility.ValidateReachability(Upgrades.GetAll(), {
					currencyEarningOperational = true,
					rankProviderOperational = false,
					cartAcquisitionByTier = { [1] = true, [2] = false, [3] = false },
				})
				expect(report.byOfferId.CART_SPEED_1.structurallyValid).to.equal(true)
				expect(report.byOfferId.CART_SPEED_1.operational).to.equal(true)
				expect(report.byOfferId.CARGO_1.structurallyValid).to.equal(true)
				expect(report.byOfferId.CARGO_1.operational).to.equal(true)
				expect(report.byOfferId.CART_SPEED_2.structurallyValid).to.equal(true)
				expect(report.byOfferId.CART_SPEED_2.operational).to.equal(true)
				expect(report.byOfferId.CARGO_2.structurallyValid).to.equal(true)
				expect(report.byOfferId.OFFROAD_1.operational).to.equal(false)
			end
		)

		it("detects unknown predecessors and self-dependency", function()
			local unknown = Eligibility.ValidateReachability({
				definition("A", { priorOfferId = "MISSING" }),
			}, operational)
			expect(unknown.structurallyValid).to.equal(false)
			expect(unknown.errors[1].code).to.equal("UNKNOWN_PREDECESSOR")
			local self = Eligibility.ValidateReachability({
				definition("A", { priorOfferId = "A" }),
			}, operational)
			expect(self.structurallyValid).to.equal(false)
			expect(self.errors[1].code).to.equal("SELF_DEPENDENCY")
		end)

		it("detects a two-offer cycle", function()
			local report = Eligibility.ValidateReachability({
				definition("A", { priorOfferId = "B" }),
				definition("B", { priorOfferId = "A" }),
			}, operational)
			expect(report.structurallyValid).to.equal(false)
			local found = false
			for _, issue in report.errors do
				found = found or issue.code == "PREREQUISITE_CYCLE"
			end
			expect(found).to.equal(true)
		end)

		it("does not mistake rank fields or cart assets for operational providers", function()
			local rank = Eligibility.ValidateReachability({
				definition("RANKED", { requiredRank = 5 }),
			}, {
				currencyEarningOperational = true,
				rankProviderOperational = false,
			})
			expect(rank.operational).to.equal(false)
			expect(rank.blockers[1].code).to.equal("RANK_PROVIDER_UNAVAILABLE")
			local cart = Eligibility.ValidateReachability({
				definition("TIERED", {
					cartQualification = { mode = "OwnsAtLeastTier", minimumTier = 2 },
				}),
			}, {
				currencyEarningOperational = true,
				cartAcquisitionByTier = { [2] = false },
			})
			expect(cart.operational).to.equal(false)
			expect(cart.blockers[1].code).to.equal("CART_ACQUISITION_UNAVAILABLE")
		end)

		it("rejects development-only grants as the normal progression path", function()
			local report = Eligibility.ValidateReachability({
				definition("TIERED", {
					cartQualification = { mode = "OwnsAtLeastTier", minimumTier = 2 },
				}),
			}, {
				currencyEarningOperational = true,
				cartAcquisitionByTier = { [2] = "DevelopmentOnly" },
			})
			expect(report.operational).to.equal(false)
			expect(report.blockers[1].code).to.equal("DEVELOPMENT_ONLY_PROVIDER")
		end)

		it("accepts a valid starter and sequential prerequisite path", function()
			local report = Eligibility.ValidateReachability({
				definition("STARTER"),
				definition("SECOND", { priorOfferId = "STARTER" }),
			}, operational)
			expect(report.structurallyValid).to.equal(true)
			expect(report.operational).to.equal(true)
			expect(report.byOfferId.SECOND.operational).to.equal(true)
		end)

		it("marks an unavailable future provider without changing definitions", function()
			local source = {
				definition("FUTURE", {
					cartQualification = { mode = "OwnsAtLeastTier", minimumTier = 3 },
				}),
			}
			local report = Eligibility.ValidateReachability(source, {
				currencyEarningOperational = true,
				cartAcquisitionByTier = { [3] = false },
			})
			expect(report.operational).to.equal(false)
			expect(source[1].requirements.cartQualification.minimumTier).to.equal(3)
		end)
	end)
end
