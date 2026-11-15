--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartCamera = require(ReplicatedStorage.Shared.Config.CartCamera)
	local CartGamepad = require(ReplicatedStorage.Shared.Config.CartGamepad)
	local CartCameraMath = require(ReplicatedStorage.Shared.Utility.CartCameraMath)

	local EPSILON = 1e-5

	local function expectNear(actual: number, expected: number, epsilon: number?)
		expect(math.abs(actual - expected) <= (epsilon or EPSILON)).to.equal(true)
	end

	describe("CartCameraMath", function()
		it("builds the locked 28-stud orbit and 9-stud height framing", function()
			local target = CFrame.new(10, 2, -4)
			local root = CFrame.new(10, 0, -4)
			local desired, focus = CartCameraMath.GetDesiredCFrame(target, root, 0, 0, 28, 9)
			local separateHeight = Vector3.yAxis * 9
			local orbitComponent = desired.Position - focus - separateHeight

			expectNear(orbitComponent.Magnitude, 28)
			expectNear(desired.Position.Y - focus.Y, 9)
			expect((desired.Position - focus).Z > 0).to.equal(true)
			expectNear(desired.LookVector:Dot((focus - desired.Position).Unit), 1)
			expect(CartCameraMath.IsFiniteCFrame(desired)).to.equal(true)
		end)

		it("uses structural forward rather than travel velocity", function()
			local target = CFrame.new(0, 3, 0)
			local root = CFrame.Angles(0, math.rad(90), 0)
			local desired = CartCameraMath.GetDesiredCFrame(target, root, 0, 0, 28, 9)

			-- The API has no velocity input, so reversing cannot flip this structural heading.
			expect(desired.Position.X > 0).to.equal(true)
			expectNear(math.abs(desired.Position.X), 28)
		end)

		it("resolves structural yaw and preserves its fallback for a vertical heading", function()
			expectNear(CartCameraMath.GetStructuralYaw(CFrame.new()), 0)
			expectNear(
				CartCameraMath.GetStructuralYaw(CFrame.Angles(0, math.rad(90), 0)),
				math.rad(90)
			)
			expectNear(
				CartCameraMath.GetStructuralYaw(CFrame.Angles(0, math.rad(-90), 0)),
				math.rad(-90)
			)

			local vertical = CFrame.lookAt(Vector3.zero, Vector3.yAxis, Vector3.zAxis)

			expectNear(CartCameraMath.GetStructuralYaw(vertical, 0.73), 0.73)
		end)

		it("applies locked sensitivity through the configured radians-per-pixel scale", function()
			local yaw, pitch = CartCameraMath.ApplyManualOrbit(
				0,
				0,
				Vector2.new(100, -50),
				0.8,
				0.003,
				math.rad(-20),
				math.rad(35)
			)

			expectNear(yaw, -0.24)
			expectNear(pitch, 0.12)
		end)

		it("clamps pitch and wraps yaw without camera inversion", function()
			local yaw, pitch = CartCameraMath.ApplyManualOrbit(
				math.pi - 0.01,
				0,
				Vector2.new(-1000, -1000),
				0.8,
				0.003,
				math.rad(-20),
				math.rad(35)
			)

			expect(yaw >= -math.pi and yaw <= math.pi).to.equal(true)
			expectNear(pitch, math.rad(35))
		end)

		it(
			"applies locked gamepad sensitivity exactly once at a frame-rate-independent rate",
			function()
				local stickIntent = Vector2.new(1, -0.1)
				local angularRate = CartGamepad.Development.CameraRadiansPerSecond
				local oneStepYaw, oneStepPitch = CartCameraMath.ApplyGamepadOrbit(
					0,
					0,
					stickIntent,
					CartCamera.GamepadSensitivity,
					angularRate,
					1,
					math.rad(-20),
					math.rad(35)
				)
				local manyStepYaw = 0
				local manyStepPitch = 0

				for _ = 1, 60 do
					manyStepYaw, manyStepPitch = CartCameraMath.ApplyGamepadOrbit(
						manyStepYaw,
						manyStepPitch,
						stickIntent,
						CartCamera.GamepadSensitivity,
						angularRate,
						1 / 60,
						math.rad(-20),
						math.rad(35)
					)
				end

				expectNear(oneStepYaw, -CartCamera.GamepadSensitivity * angularRate)
				expectNear(oneStepPitch, CartCamera.GamepadSensitivity * angularRate * 0.1)
				expectNear(manyStepYaw, oneStepYaw)
				expectNear(manyStepPitch, oneStepPitch)
			end
		)

		it("recentres by the shortest angle without overshoot", function()
			local wrapped = CartCameraMath.WrapAngle(math.rad(350))
			local nextYaw = CartCameraMath.RecenterYaw(wrapped, 3.5, 1 / 60)

			expectNear(wrapped, math.rad(-10))
			expect(nextYaw < 0).to.equal(true)
			expect(math.abs(nextYaw) < math.abs(wrapped)).to.equal(true)
		end)

		it("waits for the locked delay and restarts after new manual input", function()
			expect(CartCameraMath.ShouldRecenter(11.24, 10, 1.25, false, false)).to.equal(false)
			expect(CartCameraMath.ShouldRecenter(11.25, 10, 1.25, false, false)).to.equal(true)
			expect(CartCameraMath.ShouldRecenter(11.25, 10, 1.25, true, false)).to.equal(false)
			expect(CartCameraMath.ShouldRecenter(11.25, 10, 1.25, false, true)).to.equal(false)
			expect(CartCameraMath.ShouldRecenter(11.5, 11, 1.25, false, false)).to.equal(false)
		end)

		it("recentres comparably across frame rates", function()
			local oneStep = CartCameraMath.RecenterYaw(1.2, 3.5, 1)
			local manySteps = 1.2

			for _ = 1, 60 do
				manySteps = CartCameraMath.RecenterYaw(manySteps, 3.5, 1 / 60)
			end

			expectNear(oneStep, manySteps, 1e-4)
		end)

		it("smooths opposite orientations without producing a non-finite frame", function()
			local current = CFrame.lookAt(Vector3.zero, -Vector3.zAxis)
			local targetPosition = Vector3.new(10, 5, -2)
			local target = CFrame.lookAt(targetPosition, targetPosition + Vector3.zAxis)
			local smoothed = CartCameraMath.SmoothCFrame(current, target, 10, 12, 0.1)

			expect(CartCameraMath.IsFiniteCFrame(smoothed)).to.equal(true)
			expect(smoothed.Position.X > 0 and smoothed.Position.X < 10).to.equal(true)
		end)

		it("follows comparably across frame rates", function()
			local current = CFrame.lookAt(Vector3.new(-5, 2, 8), Vector3.zero)
			local target = CFrame.new(15, 7, -20) * CFrame.Angles(0.2, 1.1, -0.1)
			local oneStep = CartCameraMath.SmoothCFrame(current, target, 10, 12, 1)
			local manySteps = current

			for _ = 1, 60 do
				manySteps = CartCameraMath.SmoothCFrame(manySteps, target, 10, 12, 1 / 60)
			end

			expect((oneStep.Position - manySteps.Position).Magnitude < 1e-4).to.equal(true)
			expect(oneStep.LookVector:Dot(manySteps.LookVector) > 0.9999).to.equal(true)
		end)

		it("rejects non-finite vectors and frames", function()
			expect(CartCameraMath.IsFiniteVector3(Vector3.new(0, 1, 2))).to.equal(true)
			expect(CartCameraMath.IsFiniteVector3(Vector3.new(0 / 0, 1, 2))).to.equal(false)
			expect(CartCameraMath.IsFiniteCFrame(CFrame.new())).to.equal(true)
			expect(CartCameraMath.IsFiniteCFrame(CFrame.new(math.huge, 0, 0))).to.equal(false)
		end)
	end)
end
