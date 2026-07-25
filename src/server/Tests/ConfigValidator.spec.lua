--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local ConfigValidator = require(ReplicatedStorage.Shared.Validation.ConfigValidator)

	describe("ConfigValidator", function()
		it("accepts unique IDs", function()
			expect(function()
				ConfigValidator.AssertUniqueIds("Test", {
					First = "ONE",
					Second = "TWO",
				})
			end).never.to.throw()
		end)

		it("rejects duplicate IDs", function()
			expect(function()
				ConfigValidator.AssertUniqueIds("Test", {
					First = "DUPLICATE",
					Second = "DUPLICATE",
				})
			end).to.throw()
		end)
	end)
end
