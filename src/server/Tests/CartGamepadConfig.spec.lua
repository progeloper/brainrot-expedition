--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartGamepad = require(ReplicatedStorage.Shared.Config.CartGamepad)

	describe("CartGamepad configuration", function()
		it("centralises the existing stick dead zones and Phase 1P Development tuning", function()
			expect(CartGamepad.Development.MovementStickDeadzone).to.equal(0.14)
			expect(CartGamepad.Development.CameraStickDeadzone).to.equal(0.14)
			expect(CartGamepad.Development.TriggerDeadzone).to.equal(0.05)
			expect(CartGamepad.Development.CameraRadiansPerSecond).to.equal(math.pi)
		end)

		it("freezes the configuration and its nested Development table", function()
			expect(table.isfrozen(CartGamepad)).to.equal(true)
			expect(table.isfrozen(CartGamepad.Development)).to.equal(true)
		end)
	end)
end
