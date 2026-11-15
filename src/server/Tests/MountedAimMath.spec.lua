--!strict

return function()
	local Shared = game:GetService("ReplicatedStorage").Shared
	local Aim = require(Shared.Config.MountedAim)
	local AimMath = require(Shared.Utility.MountedAimMath)
	local CartCameraMath = require(Shared.Utility.CartCameraMath)
	local function near(actual: number, expected: number)
		expect(math.abs(actual - expected) < 1e-5).to.equal(true)
	end

	describe("MountedAimMath", function()
		it("enters from the actual displayed direction rather than cart heading", function()
			local view = CFrame.Angles(0, math.rad(73), 0) * CFrame.Angles(math.rad(-19), 0, 0)
			local yaw, pitch = AimMath.FromLookVector(view.LookVector, Aim.MinimumPitch, Aim.MaximumPitch)
			local aim = AimMath.GetDesiredCFrame(
				Vector3.new(20, 4, -15),
				yaw,
				pitch,
				Aim.Distance,
				Aim.ShoulderOffset,
				Aim.HeightOffset
			)
			near(aim.LookVector:Dot(view.LookVector), 1)
		end)

		it("retains a held world direction with no pointer delta while its cart moves", function()
			local yaw, pitch = 1.2, 0.18
			local first =
				AimMath.GetDesiredCFrame(Vector3.zero, yaw, pitch, Aim.Distance, Aim.ShoulderOffset, Aim.HeightOffset)
			-- Six seconds exceeds the ordinary cruise recenter delay several times.
			for _ = 1, 360 do
				yaw, pitch = AimMath.ApplyLook(
					yaw,
					pitch,
					Vector2.zero,
					Vector2.zero,
					1 / 60,
					Aim.MouseRadiansPerPixel,
					Aim.GamepadRadiansPerSecond,
					Aim.MinimumPitch,
					Aim.MaximumPitch
				)
			end
			local moved = AimMath.GetDesiredCFrame(
				Vector3.new(25, 3, -8),
				yaw,
				pitch,
				Aim.Distance,
				Aim.ShoulderOffset,
				Aim.HeightOffset
			)
			near(first.LookVector:Dot(moved.LookVector), 1)
			near((moved.Position - first.Position - Vector3.new(25, 3, -8)).Magnitude, 0)
		end)

		it("places the cart below and beside the centre ray rather than on it", function()
			for _, pitch in { Aim.MinimumPitch, 0, Aim.MaximumPitch } do
				local frame = AimMath.GetDesiredCFrame(
					Vector3.zero,
					0.8,
					pitch,
					Aim.Distance,
					Aim.ShoulderOffset,
					Aim.HeightOffset
				)
				local cart = frame:PointToObjectSpace(Vector3.zero)
				expect(cart.Y < 0).to.equal(true)
				expect(cart.X < 0).to.equal(true)
				expect(cart.Z < 0).to.equal(true)
			end
		end)

		it("keeps a level horizon regardless of cart slope or aim heading", function()
			local frame = AimMath.GetDesiredCFrame(
				Vector3.new(0, 5, 0),
				-1.4,
				0.6,
				Aim.Distance,
				Aim.ShoulderOffset,
				Aim.HeightOffset
			)
			near(frame.RightVector:Dot(Vector3.yAxis), 0)
			expect(frame.UpVector.Y > 0).to.equal(true)
			expect(CartCameraMath.IsFiniteCFrame(frame)).to.equal(true)
		end)

		it("maps pointer and raw controller vertical directions consistently", function()
			local pointerYaw, pointerPitch = AimMath.ApplyLook(
				0,
				0,
				Vector2.new(20, -20),
				Vector2.zero,
				1,
				Aim.MouseRadiansPerPixel,
				Aim.GamepadRadiansPerSecond,
				Aim.MinimumPitch,
				Aim.MaximumPitch
			)
			local stickYaw, stickPitch = AimMath.ApplyLook(
				0,
				0,
				Vector2.zero,
				Vector2.new(1, 1),
				0.1,
				Aim.MouseRadiansPerPixel,
				Aim.GamepadRadiansPerSecond,
				Aim.MinimumPitch,
				Aim.MaximumPitch
			)
			expect(pointerYaw < 0 and pointerPitch > 0).to.equal(true)
			expect(stickYaw < 0 and stickPitch > 0).to.equal(true)
		end)

		it("uses a frame-rate-independent controller angular rate", function()
			local function step(count: number): (number, number)
				local yaw, pitch = 0, 0
				for _ = 1, count do
					yaw, pitch = AimMath.ApplyLook(
						yaw,
						pitch,
						Vector2.zero,
						Vector2.new(0.6, 0.15),
						1 / count,
						Aim.MouseRadiansPerPixel,
						Aim.GamepadRadiansPerSecond,
						Aim.MinimumPitch,
						Aim.MaximumPitch
					)
				end
				return yaw, pitch
			end
			local yawA, pitchA = step(30)
			local yawB, pitchB = step(144)
			near(yawA, yawB)
			near(pitchA, pitchB)
		end)

		it("clamps pitch and wraps yaw without rolling or inverting", function()
			local yaw, pitch = AimMath.ApplyLook(
				math.pi - 0.01,
				0,
				Vector2.new(-99999, -99999),
				Vector2.zero,
				1,
				Aim.MouseRadiansPerPixel,
				Aim.GamepadRadiansPerSecond,
				Aim.MinimumPitch,
				Aim.MaximumPitch
			)
			expect(yaw >= -math.pi and yaw <= math.pi).to.equal(true)
			near(pitch, Aim.MaximumPitch)
			local _, lower = AimMath.ApplyLook(
				0,
				0,
				Vector2.new(0, 99999),
				Vector2.zero,
				1,
				Aim.MouseRadiansPerPixel,
				Aim.GamepadRadiansPerSecond,
				Aim.MinimumPitch,
				Aim.MaximumPitch
			)
			near(lower, Aim.MinimumPitch)
		end)
	end)
end
