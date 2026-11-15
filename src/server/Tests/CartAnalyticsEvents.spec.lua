--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local AnalyticsEvents = require(ReplicatedStorage.Shared.Constants.AnalyticsEvents)
	local CartAnalytics = require(ReplicatedStorage.Shared.Config.CartAnalytics)
	local eventsByKey = AnalyticsEvents :: { [string]: string? }

	local REQUIRED_EVENTS = {
		CartSpawned = "cart_spawned",
		CartDriverEntered = "cart_driver_entered",
		CartMovementStarted = "cart_movement_started",
		CartDriverExited = "cart_driver_exited",
		CartResetRequested = "cart_reset_requested",
		CartResetApproved = "cart_reset_approved",
		CartResetRejected = "cart_reset_rejected",
		CartResetCompleted = "cart_reset_completed",
		CartDespawned = "cart_despawned",
		CartMovementCorrected = "cart_movement_corrected",
	}

	describe("Phase 1R analytics event catalogue", function()
		it("centralises all ten required version-one cart event names", function()
			local seen: { [string]: boolean } = {}
			local count = 0

			for key, expectedName in REQUIRED_EVENTS do
				local actualName = eventsByKey[key]

				expect(actualName).to.equal(expectedName)
				assert(actualName ~= nil, "required analytics event must exist")
				expect(seen[actualName]).to.equal(nil)

				seen[actualName] = true
				count += 1
			end

			expect(count).to.equal(10)
			expect(CartAnalytics.EventVersion).to.equal(1)
		end)

		it("removes superseded unversioned cart transition names", function()
			expect(eventsByKey.CartReset).to.equal(nil)
			expect(eventsByKey.CartEntered).to.equal(nil)
			expect(eventsByKey.CartExited).to.equal(nil)
		end)
	end)
end
