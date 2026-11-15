--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartGamepadInputMath = require(ReplicatedStorage.Shared.Utility.CartGamepadInputMath)
	local CartLongitudinalStateMachine =
		require(ReplicatedStorage.Shared.Utility.CartLongitudinalStateMachine)
	local CartMovementProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartMovementProfileResolver)

	local EPSILON = 1e-6

	local function expectNear(actual: number, expected: number, epsilon: number?)
		expect(math.abs(actual - expected) <= (epsilon or EPSILON)).to.equal(true)
	end

	describe("CartGamepadInputMath", function()
		it(
			"maps Roblox thumbstick and L2 position axes through the locked adapter convention",
			function()
				local movement = CartGamepadInputMath.ReadMovementStick(Vector3.new(-0.4, 0.7, 0))
				local camera = CartGamepadInputMath.ReadCameraStick(Vector3.new(0.3, 0.8, 0))
				local trigger = CartGamepadInputMath.ReadLeftTrigger(Vector3.new(0, 0, 0.65))

				expect(movement).to.equal(Vector2.new(-0.4, 0.7))
				expect(camera).to.equal(Vector2.new(0.3, -0.8))
				expectNear(trigger :: number, 0.65)
			end
		)

		it("rejects non-finite Roblox axis positions", function()
			local movement = CartGamepadInputMath.ReadMovementStick(Vector3.new(0 / 0, 0, 0))
			local camera = CartGamepadInputMath.ReadCameraStick(Vector3.new(0, math.huge, 0))
			local trigger = CartGamepadInputMath.ReadLeftTrigger(Vector3.new(0, 0, -math.huge))

			expect(movement).to.equal(nil)
			expect(camera).to.equal(nil)
			expect(trigger).to.equal(nil)
		end)

		it("removes radial stick drift and linearly remaps the remaining range", function()
			local drift, driftError =
				CartGamepadInputMath.ApplyRadialDeadzone(Vector2.new(0.1, 0), 0.14)
			local halfway, halfwayError =
				CartGamepadInputMath.ApplyRadialDeadzone(Vector2.new(0.57, 0), 0.14)
			local full, fullError =
				CartGamepadInputMath.ApplyRadialDeadzone(Vector2.new(0, 1), 0.14)

			expect(driftError).to.equal(nil)
			expect(halfwayError).to.equal(nil)
			expect(fullError).to.equal(nil)
			expect(drift).to.equal(Vector2.zero)
			expectNear((halfway :: Vector2).X, 0.5)
			expectNear((halfway :: Vector2).Y, 0)
			expect(full).to.equal(Vector2.new(0, 1))
		end)

		it("keeps deliberate input immediately above each dead zone", function()
			local stick = CartGamepadInputMath.ApplyRadialDeadzone(Vector2.new(0.1401, 0), 0.14)
			local trigger = CartGamepadInputMath.ApplyTriggerDeadzone(0.0501, 0.05)

			expect((stick :: Vector2).X > 0).to.equal(true)
			expect((trigger :: number) > 0).to.equal(true)
		end)

		it("preserves radial direction and clamps over-range stick magnitude", function()
			local diagonal = Vector2.new(0.6, 0.8)
			local resolved = CartGamepadInputMath.ApplyRadialDeadzone(diagonal, 0.14) :: Vector2
			local overRange =
				CartGamepadInputMath.ApplyRadialDeadzone(Vector2.new(3, 4), 0.14) :: Vector2

			expectNear(resolved.Magnitude, 1)
			expectNear(resolved.Unit:Dot(diagonal.Unit), 1)
			expectNear(overRange.Magnitude, 1)
			expectNear(overRange.Unit:Dot(Vector2.new(3, 4).Unit), 1)
		end)

		it("rejects non-finite stick input and invalid dead zones", function()
			local nonFinite, nonFiniteError =
				CartGamepadInputMath.ApplyRadialDeadzone(Vector2.new(0 / 0, 0), 0.14)
			local invalidDeadzone, deadzoneError =
				CartGamepadInputMath.ApplyRadialDeadzone(Vector2.zero, 1)

			expect(nonFinite).to.equal(nil)
			expect(type(nonFiniteError)).to.equal("string")
			expect(invalidDeadzone).to.equal(nil)
			expect(type(deadzoneError)).to.equal("string")
		end)

		it("remaps the trigger to zero-to-one and clamps the raw range", function()
			local drift = CartGamepadInputMath.ApplyTriggerDeadzone(0.05, 0.05)
			local halfway = CartGamepadInputMath.ApplyTriggerDeadzone(0.525, 0.05)
			local full = CartGamepadInputMath.ApplyTriggerDeadzone(1, 0.05)
			local belowRange = CartGamepadInputMath.ApplyTriggerDeadzone(-1, 0.05)
			local aboveRange = CartGamepadInputMath.ApplyTriggerDeadzone(2, 0.05)

			expect(drift).to.equal(0)
			expectNear(halfway :: number, 0.5)
			expect(full).to.equal(1)
			expect(belowRange).to.equal(0)
			expect(aboveRange).to.equal(1)
		end)

		it("rejects non-finite trigger input and invalid trigger dead zones", function()
			local nonFinite, nonFiniteError = CartGamepadInputMath.ApplyTriggerDeadzone(0 / 0, 0.05)
			local invalidDeadzone, deadzoneError =
				CartGamepadInputMath.ApplyTriggerDeadzone(0.5, -0.1)

			expect(nonFinite).to.equal(nil)
			expect(type(nonFiniteError)).to.equal("string")
			expect(invalidDeadzone).to.equal(nil)
			expect(type(deadzoneError)).to.equal("string")
		end)

		it("keeps the established left stick fully bidirectional", function()
			local forward = CartGamepadInputMath.ResolveMovement(Vector2.new(0, 1), 0, 0.14, 0.05)
			local backward = CartGamepadInputMath.ResolveMovement(Vector2.new(0, -1), 0, 0.14, 0.05)

			expect((forward :: CartGamepadInputMath.MovementIntent).LongitudinalIntent).to.equal(1)
			expect((backward :: CartGamepadInputMath.MovementIntent).LongitudinalIntent).to.equal(
				-1
			)
		end)

		it("gives processed LT brake/reverse intent priority without stacking", function()
			local intent =
				CartGamepadInputMath.ResolveMovement(Vector2.new(0.5, 1), 1, 0.14, 0.05) :: CartGamepadInputMath.MovementIntent

			expect(intent.LongitudinalIntent).to.equal(-1)
			expect(intent.SteeringIntent > 0 and intent.SteeringIntent <= 1).to.equal(true)
		end)

		it("keeps steering and longitudinal intent independent and bounded", function()
			local intent = CartGamepadInputMath.ResolveMovement(
				Vector2.new(-0.8, 0.6),
				0,
				0.14,
				0.05
			) :: CartGamepadInputMath.MovementIntent

			expect(intent.SteeringIntent < 0).to.equal(true)
			expect(intent.LongitudinalIntent > 0).to.equal(true)
			expect(math.abs(intent.SteeringIntent) <= 1).to.equal(true)
			expect(math.abs(intent.LongitudinalIntent) <= 1).to.equal(true)
		end)

		it("applies the same radial policy to right-stick camera intent", function()
			local drift = CartGamepadInputMath.ResolveCamera(Vector2.new(0.1, 0), 0.14)
			local manual = CartGamepadInputMath.ResolveCamera(Vector2.new(1, 0), 0.14)

			expect(drift).to.equal(Vector2.zero)
			expect(manual).to.equal(Vector2.new(1, 0))
		end)

		it("feeds LT negative intent into the existing Phase 1I state machine", function()
			local profile = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local intent =
				CartGamepadInputMath.ResolveMovement(Vector2.new(0.5, 1), 1, 0.14, 0.05) :: CartGamepadInputMath.MovementIntent
			local result = CartLongitudinalStateMachine.Step(
				CartLongitudinalStateMachine.Create(0),
				intent.LongitudinalIntent,
				10,
				0.1,
				profile
			)

			expect(intent.LongitudinalIntent).to.equal(-1)
			expect(result.Intent).to.equal("Reverse")
			expect(result.Snapshot.CurrentState).to.equal("Braking")
		end)
	end)
end
