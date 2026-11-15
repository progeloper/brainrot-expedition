--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartAnalytics = require(ReplicatedStorage.Shared.Config.CartAnalytics)

	describe("CartAnalytics configuration", function()
		it("centralises the Phase 1R schema version and Development tuning", function()
			expect(CartAnalytics.Enabled).to.equal(true)
			expect(CartAnalytics.EventVersion).to.equal(1)
			expect(CartAnalytics.Development.MeaningfulMovementSpeed).to.equal(2.5)
			expect(CartAnalytics.Development.MovementConfirmationDuration).to.equal(0.3)
		end)

		it("freezes the configuration and Development section", function()
			expect(table.isfrozen(CartAnalytics)).to.equal(true)
			expect(table.isfrozen(CartAnalytics.Development)).to.equal(true)
		end)
	end)
end
