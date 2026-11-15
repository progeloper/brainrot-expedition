--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartMovementMath = require(ReplicatedStorage.Shared.Utility.CartMovementMath)
	local EPSILON = 1e-6

	local function expectNear(actual: number, expected: number)
		expect(math.abs(actual - expected) <= EPSILON).to.equal(true)
	end

	describe("CartMovementMath", function()
		it("applies and rescales an input deadzone", function()
			expect(CartMovementMath.ApplyDeadzone(0.1, 0.14)).to.equal(0)
			expect(CartMovementMath.ApplyDeadzone(-1, 0.14)).to.equal(-1)
		end)

		it("returns zero at both deadzone boundaries", function()
			expect(CartMovementMath.ApplyDeadzone(0.14, 0.14)).to.equal(0)
			expect(CartMovementMath.ApplyDeadzone(-0.14, 0.14)).to.equal(0)
		end)

		it("projects velocity onto cart-local axes", function()
			local result = CartMovementMath.DecomposeVelocity(
				Vector3.new(3, 4, -10),
				Vector3.new(0, 0, -1),
				Vector3.new(1, 0, 0),
				36
			)

			expect(result.ForwardSpeed).to.equal(10)
			expect(result.LateralSpeed).to.equal(3)
			expectNear(result.AbsoluteSpeed, math.sqrt(125))
			expect(result.NormalizedForwardSpeed).to.equal(10 / 36)
		end)

		it("handles zero velocity magnitude", function()
			local result = CartMovementMath.DecomposeVelocity(
				Vector3.zero,
				Vector3.new(0, 0, -1),
				Vector3.new(1, 0, 0),
				36
			)

			expect(result.ForwardSpeed).to.equal(0)
			expect(result.LateralSpeed).to.equal(0)
			expect(result.AbsoluteSpeed).to.equal(0)
			expect(result.NormalizedForwardSpeed).to.equal(0)
		end)

		it("returns zero normalized speed when maximum speed is zero", function()
			local result = CartMovementMath.DecomposeVelocity(
				Vector3.new(0, 0, -10),
				Vector3.new(0, 0, -1),
				Vector3.new(1, 0, 0),
				0
			)

			expect(result.ForwardSpeed).to.equal(10)
			expect(result.AbsoluteSpeed).to.equal(10)
			expect(result.NormalizedForwardSpeed).to.equal(0)
		end)

		it("keeps hunting-speed interpolation at zero until hunting pace", function()
			expect(CartMovementMath.GetSpeedInterpolation(0, 20, 36, 1.35)).to.equal(0)
			expect(CartMovementMath.GetSpeedInterpolation(20, 20, 36, 1.35)).to.equal(0)
		end)

		it("clamps speed interpolation at maximum travel pace", function()
			expect(CartMovementMath.GetSpeedInterpolation(36, 20, 36, 1.35)).to.equal(1)
			expect(CartMovementMath.GetSpeedInterpolation(50, 20, 36, 1.35)).to.equal(1)
		end)

		it("increases speed interpolation monotonically", function()
			local low = CartMovementMath.GetSpeedInterpolation(24, 20, 36, 1.35)
			local medium = CartMovementMath.GetSpeedInterpolation(28, 20, 36, 1.35)
			local high = CartMovementMath.GetSpeedInterpolation(32, 20, 36, 1.35)

			expect(low > 0).to.equal(true)
			expect(low < medium).to.equal(true)
			expect(medium < high).to.equal(true)
			expect(high < 1).to.equal(true)
		end)

		it(
			"interpolates acceleration from responsive hunting pace to gradual travel pace",
			function()
				expect(CartMovementMath.InterpolateBySpeed(20, 20, 36, 16, 4, 1.35)).to.equal(16)
				expect(CartMovementMath.InterpolateBySpeed(36, 20, 36, 16, 4, 1.35)).to.equal(4)

				local medium = CartMovementMath.InterpolateBySpeed(28, 20, 36, 16, 4, 1.35)

				expect(medium < 16).to.equal(true)
				expect(medium > 4).to.equal(true)
			end
		)

		it("makes passive slowing, braking, and lateral stability speed dependent", function()
			local highSpeedCoast =
				CartMovementMath.InterpolateBySpeed(36, 20, 36, 20, 20 * 0.75, 1.35)
			local highSpeedBrake =
				CartMovementMath.InterpolateBySpeed(36, 20, 36, 48, 48 * 1.15, 1.35)
			local highSpeedGrip =
				CartMovementMath.InterpolateBySpeed(36, 20, 36, 10, 10 * 1.25, 1.35)

			expect(highSpeedCoast < 20).to.equal(true)
			expect(highSpeedBrake > 48).to.equal(true)
			expect(highSpeedGrip > 10).to.equal(true)
		end)

		it("reduces steering smoothly between hunting and travel pace", function()
			expect(CartMovementMath.GetSteeringMultiplier(20, 20, 36, 1.15, 0.32, 1.35)).to.equal(
				1.15
			)
			expectNear(CartMovementMath.GetSteeringMultiplier(36, 20, 36, 1.15, 0.32, 1.35), 0.32)

			local low = CartMovementMath.GetSteeringMultiplier(24, 20, 36, 1.15, 0.32, 1.35)
			local high = CartMovementMath.GetSteeringMultiplier(32, 20, 36, 1.15, 0.32, 1.35)

			expect(low > high).to.equal(true)
			expect(low < 1.15).to.equal(true)
			expect(high > 0.32).to.equal(true)
		end)

		it("reverses steering direction at the exact recovery steering threshold", function()
			expect(CartMovementMath.GetTravelDirection(0.5, 0.5)).to.equal(1)
			expect(CartMovementMath.GetTravelDirection(-0.5, 0.5)).to.equal(-1)
		end)

		it("approaches speed without overshooting either direction", function()
			expect(CartMovementMath.ApproachSpeed(0, 20, 16, 0.5)).to.equal(8)
			expect(CartMovementMath.ApproachSpeed(19, 20, 16, 0.1)).to.equal(20)
			expect(CartMovementMath.ApproachSpeed(20, 0, 20, 0.25)).to.equal(15)
			expect(CartMovementMath.ApproachSpeed(0, -3.5, 6, 1)).to.equal(-3.5)
		end)

		it("does not advance speed with non-positive delta time", function()
			expect(CartMovementMath.ApproachSpeed(7, 20, 16, 0)).to.equal(7)
			expect(CartMovementMath.ApproachSpeed(7, 20, 16, -1)).to.equal(7)
		end)

		it("calculates a tolerant travel distance", function()
			expect(CartMovementMath.GetPlausibleTravelDistance(36, 0.25, 2, 10)).to.equal(28)
		end)

		it("returns zero exponential alpha at zero delta", function()
			expect(CartMovementMath.GetExponentialAlpha(18, 0)).to.equal(0)
		end)
	end)
end
