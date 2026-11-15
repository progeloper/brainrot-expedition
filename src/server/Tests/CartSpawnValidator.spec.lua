--!nocheck

return function()
	local ReplicatedStorage =
		game:GetService("ReplicatedStorage")

	local CartSpawnValidator = require(
		ReplicatedStorage.Shared.Validation.CartSpawnValidator
	)

	describe("CartSpawnValidator", function()
		it("accepts a valid spawn", function()
			local part = Instance.new("Part")

			part.Anchored = true
			part.CanCollide = false

			part:SetAttribute(
				"SpawnId",
				"CSP_TEST"
			)

			part:SetAttribute(
				"CartId",
				"CRT_TEST"
			)

			part:SetAttribute(
				"Enabled",
				true
			)

			part:SetAttribute(
				"Priority",
				1
			)

			local result =
				CartSpawnValidator.Validate(part)

			expect(result.IsValid).to.equal(true)

			part:Destroy()
		end)

		it("rejects a missing SpawnId", function()
			local part = Instance.new("Part")

			part.Anchored = true

			part:SetAttribute(
				"CartId",
				"CRT_TEST"
			)

			part:SetAttribute(
				"Enabled",
				true
			)

			part:SetAttribute(
				"Priority",
				1
			)

			local result =
				CartSpawnValidator.Validate(part)

			expect(result.IsValid).to.equal(false)

			part:Destroy()
		end)
	end)
end