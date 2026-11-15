--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartGamepad = require(ReplicatedStorage.Shared.Config.CartGamepad)
	local CartGamepadConfigValidator =
		require(ReplicatedStorage.Shared.Validation.CartGamepadConfigValidator)

	local function cloneConfig(): any
		return {
			Development = table.clone(CartGamepad.Development),
		}
	end

	describe("CartGamepadConfigValidator", function()
		it("accepts the configured Phase 1P values", function()
			local result = CartGamepadConfigValidator.Validate(CartGamepad)

			expect(result.IsValid).to.equal(true)
			expect(#result.Errors).to.equal(0)
		end)

		it("rejects a missing configuration or Development table", function()
			expect(CartGamepadConfigValidator.Validate(nil).IsValid).to.equal(false)
			expect(CartGamepadConfigValidator.Validate({}).IsValid).to.equal(false)
			expect(CartGamepadConfigValidator.Validate({ Development = true }).IsValid).to.equal(
				false
			)
		end)

		it("rejects missing, non-number, NaN, and infinite fields", function()
			for _, field in
				{
					"MovementStickDeadzone",
					"CameraStickDeadzone",
					"TriggerDeadzone",
					"CameraRadiansPerSecond",
				}
			do
				local missing = cloneConfig()

				missing.Development[field] = nil
				expect(CartGamepadConfigValidator.Validate(missing).IsValid).to.equal(false)

				for _, invalidValue in { "invalid", 0 / 0, math.huge, -math.huge } do
					local config = cloneConfig()

					config.Development[field] = invalidValue
					expect(CartGamepadConfigValidator.Validate(config).IsValid).to.equal(false)
				end
			end
		end)

		it("rejects dead zones outside the half-open zero-to-one range", function()
			for _, field in { "MovementStickDeadzone", "CameraStickDeadzone", "TriggerDeadzone" } do
				for _, invalidValue in { -0.01, 1, 2 } do
					local config = cloneConfig()

					config.Development[field] = invalidValue
					expect(CartGamepadConfigValidator.Validate(config).IsValid).to.equal(false)
				end
			end
		end)

		it("rejects non-positive or unsafe camera angular rates", function()
			for _, invalidValue in { -1, 0, math.pi * 8 + 0.01 } do
				local config = cloneConfig()

				config.Development.CameraRadiansPerSecond = invalidValue
				expect(CartGamepadConfigValidator.Validate(config).IsValid).to.equal(false)
			end
		end)
	end)
end
