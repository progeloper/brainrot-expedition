--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CartAnalyticsReasonMapper =
		require(ReplicatedStorage.Shared.Utility.CartAnalyticsReasonMapper)

	describe("CartAnalyticsReasonMapper", function()
		it("maps only currently distinguishable driver lifecycle reasons", function()
			expect(CartAnalyticsReasonMapper.DriverExit("driver Humanoid left DriverSeat")).to.equal(
				"SeatExited"
			)
			expect(CartAnalyticsReasonMapper.DriverExit("driver replaced")).to.equal(
				"DriverReplaced"
			)
			expect(CartAnalyticsReasonMapper.DriverExit("Replacing existing cart")).to.equal(
				"CartReplaced"
			)
			expect(CartAnalyticsReasonMapper.DriverExit("driver Player removing")).to.equal(
				"PlayerLeaving"
			)
			expect(CartAnalyticsReasonMapper.DriverExit("driver character removing")).to.equal(
				"CharacterInvalidated"
			)
			expect(CartAnalyticsReasonMapper.DriverExit("cart destroying")).to.equal(
				"CartDestroyed"
			)
			expect(CartAnalyticsReasonMapper.DriverExit("new future reason")).to.equal("Unknown")
		end)

		it("maps authoritative cart removal reasons without inferring player intent", function()
			expect(CartAnalyticsReasonMapper.Despawn("Player leaving")).to.equal("PlayerLeaving")
			expect(CartAnalyticsReasonMapper.Despawn("Replacing existing cart")).to.equal(
				"Replacement"
			)
			expect(CartAnalyticsReasonMapper.Despawn("Model destroyed")).to.equal("ModelDestroyed")
			expect(CartAnalyticsReasonMapper.Despawn("Model removed from hierarchy")).to.equal(
				"ModelDestroyed"
			)
			expect(CartAnalyticsReasonMapper.Despawn("cart despawning")).to.equal("ExplicitDespawn")
			expect(CartAnalyticsReasonMapper.Despawn("unclassified cleanup")).to.equal("Unknown")
		end)
	end)
end
