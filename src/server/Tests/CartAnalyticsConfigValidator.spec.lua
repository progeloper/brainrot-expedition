--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartAnalytics = require(ReplicatedStorage.Shared.Config.CartAnalytics)
	local CartAnalyticsConfigValidator =
		require(ReplicatedStorage.Shared.Validation.CartAnalyticsConfigValidator)

	local function cloneConfig(): any
		return {
			Enabled = CartAnalytics.Enabled,
			EventVersion = CartAnalytics.EventVersion,
			Development = table.clone(CartAnalytics.Development),
		}
	end

	local function expectInvalid(config: any)
		expect(CartAnalyticsConfigValidator.Validate(config).IsValid).to.equal(false)
	end

	describe("CartAnalyticsConfigValidator", function()
		it("accepts the complete Phase 1R configuration", function()
			local result = CartAnalyticsConfigValidator.Validate(CartAnalytics)

			expect(result.IsValid).to.equal(true)
			expect(#result.Errors).to.equal(0)
		end)

		it("requires the enable flag, event version, and Development section", function()
			expectInvalid(nil)
			expectInvalid({})

			local invalidEnabled = cloneConfig()

			invalidEnabled.Enabled = "true"
			expectInvalid(invalidEnabled)

			local invalidVersion = cloneConfig()

			invalidVersion.EventVersion = 2
			expectInvalid(invalidVersion)

			local invalidDevelopment = cloneConfig()

			invalidDevelopment.Development = false
			expectInvalid(invalidDevelopment)
		end)

		it("rejects missing, non-finite, non-number, or out-of-range tuning", function()
			for _, field in { "MeaningfulMovementSpeed", "MovementConfirmationDuration" } do
				local missing = cloneConfig()

				missing.Development[field] = nil
				expectInvalid(missing)

				for _, invalidValue in { "invalid", 0 / 0, math.huge, -math.huge, 0, -1 } do
					local invalid = cloneConfig()

					invalid.Development[field] = invalidValue
					expectInvalid(invalid)
				end
			end
		end)

		it("rejects unknown root and Development fields", function()
			local unknownRoot = cloneConfig()

			unknownRoot.Provider = "Unapproved"
			expectInvalid(unknownRoot)

			local unknownDevelopment = cloneConfig()

			unknownDevelopment.Development.PositionSampleRate = 60
			expectInvalid(unknownDevelopment)
		end)
	end)
end
