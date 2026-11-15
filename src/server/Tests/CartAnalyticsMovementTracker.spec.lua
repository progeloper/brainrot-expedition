--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartAnalytics = require(ReplicatedStorage.Shared.Config.CartAnalytics)
	local CartAnalyticsMovementTracker =
		require(ReplicatedStorage.Shared.Utility.CartAnalyticsMovementTracker)

	describe("CartAnalyticsMovementTracker", function()
		it("rejects jitter and starts a candidate at meaningful speed", function()
			local candidate, emitted, shouldEmit = CartAnalyticsMovementTracker.Advance(
				nil,
				false,
				CartAnalytics.Development.MeaningfulMovementSpeed - 0.01,
				10,
				true,
				CartAnalytics.Development
			)

			expect(candidate).to.equal(nil)
			expect(emitted).to.equal(false)
			expect(shouldEmit).to.equal(false)

			candidate, emitted, shouldEmit = CartAnalyticsMovementTracker.Advance(
				nil,
				false,
				CartAnalytics.Development.MeaningfulMovementSpeed,
				10,
				true,
				CartAnalytics.Development
			)

			expect(candidate).to.equal(10)
			expect(emitted).to.equal(false)
			expect(shouldEmit).to.equal(false)
		end)

		it("requires sustained movement for the configured confirmation duration", function()
			local candidate = 20
			local emitted = false
			local shouldEmit = false

			candidate, emitted, shouldEmit = CartAnalyticsMovementTracker.Advance(
				candidate,
				emitted,
				5,
				20 + CartAnalytics.Development.MovementConfirmationDuration - 0.01,
				true,
				CartAnalytics.Development
			)

			expect(candidate).to.equal(20)
			expect(shouldEmit).to.equal(false)

			candidate, emitted, shouldEmit = CartAnalyticsMovementTracker.Advance(
				candidate,
				emitted,
				5,
				20 + CartAnalytics.Development.MovementConfirmationDuration,
				true,
				CartAnalytics.Development
			)

			expect(candidate).to.equal(nil)
			expect(emitted).to.equal(true)
			expect(shouldEmit).to.equal(true)
		end)

		it("emits at most once and clears interrupted candidates", function()
			local candidate, emitted, shouldEmit = CartAnalyticsMovementTracker.Advance(
				1,
				true,
				10,
				5,
				true,
				CartAnalytics.Development
			)

			expect(candidate).to.equal(nil)
			expect(emitted).to.equal(true)
			expect(shouldEmit).to.equal(false)

			candidate, emitted, shouldEmit = CartAnalyticsMovementTracker.Advance(
				3,
				false,
				10,
				3.1,
				false,
				CartAnalytics.Development
			)

			expect(candidate).to.equal(nil)
			expect(emitted).to.equal(false)
			expect(shouldEmit).to.equal(false)
		end)

		it("defends against non-finite values and clock regression", function()
			local candidate, emitted, shouldEmit = CartAnalyticsMovementTracker.Advance(
				1,
				false,
				0 / 0,
				2,
				true,
				CartAnalytics.Development
			)

			expect(candidate).to.equal(nil)
			expect(emitted).to.equal(false)
			expect(shouldEmit).to.equal(false)

			candidate = select(
				1,
				CartAnalyticsMovementTracker.Advance(
					5,
					false,
					5,
					4,
					true,
					CartAnalytics.Development
				)
			)

			expect(candidate).to.equal(4)
		end)
	end)
end
