--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartStabilityMath = require(ReplicatedStorage.Shared.Utility.CartStabilityMath)
	local CartStabilityProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartStabilityProfileResolver)
	local CartStabilityTypes = require(ReplicatedStorage.Shared.Types.CartStabilityTypes)

	type EffectiveStabilityProfile = CartStabilityTypes.EffectiveStabilityProfile

	local profile = CartStabilityProfileResolver.Resolve(Ids.Carts.ScrapChariot)

	local function expectClose(actual: number, expected: number, tolerance: number?)
		expect(math.abs(actual - expected) <= (tolerance or 1e-5)).to.equal(true)
	end

	local function expectVectorClose(actual: Vector3, expected: Vector3, tolerance: number?)
		expect((actual - expected).Magnitude <= (tolerance or 1e-5)).to.equal(true)
	end

	local function computeStep(
		rootCFrame: CFrame,
		angularVelocity: Vector3,
		previousTorque: Vector3?,
		deltaTime: number?,
		profileOverride: EffectiveStabilityProfile?,
		assistanceMultiplier: number?,
		assemblyMass: number?
	)
		return CartStabilityMath.ComputeStep({
			RootCFrame = rootCFrame,
			AngularVelocity = angularVelocity,
			AssemblyMass = assemblyMass or 100,
			DesiredUp = Vector3.yAxis,
			IntendedHeading = rootCFrame.LookVector,
			PreviousTorque = previousTorque or Vector3.zero,
			PreviousHeading = -Vector3.zAxis,
			AssistanceMultiplier = assistanceMultiplier or 1,
			DeltaTime = deltaTime or 1,
			Profile = profileOverride or profile,
		})
	end

	describe("CartStabilityMath", function()
		it("builds an orthonormal heading frame without forcing world north", function()
			local frame, heading =
				CartStabilityMath.BuildHeadingFrame(Vector3.new(1, 0.4, 1), Vector3.yAxis, nil)
			local expectedHeading = Vector3.new(1, 0, 1).Unit

			expectVectorClose(heading, expectedHeading)
			expectVectorClose(frame.LookVector, expectedHeading)
			expectVectorClose(frame.UpVector, Vector3.yAxis)
			expectClose(frame.RightVector:Dot(frame.UpVector), 0)
			expectClose(frame.RightVector:Dot(frame.LookVector), 0)
		end)

		it(
			"uses a supplied tilted up reference so heading control need not level the cart",
			function()
				local tiltedUp = CFrame.Angles(0, 0, math.rad(12)).UpVector
				local frame = CartStabilityMath.BuildHeadingFrame(
					Vector3.new(1, 0, 0),
					tiltedUp,
					-Vector3.zAxis
				)

				expectVectorClose(frame.UpVector, tiltedUp.Unit)
				expectClose(frame.LookVector:Dot(tiltedUp.Unit), 0)
			end
		)

		it("uses a deterministic fallback for vertical or zero headings", function()
			local firstFrame, firstHeading =
				CartStabilityMath.BuildHeadingFrame(Vector3.yAxis, Vector3.yAxis, nil)
			local secondFrame, secondHeading =
				CartStabilityMath.BuildHeadingFrame(Vector3.zero, Vector3.yAxis, nil)

			expectVectorClose(firstHeading, secondHeading)
			expectVectorClose(firstFrame.LookVector, secondFrame.LookVector)
			expectClose(firstHeading:Dot(Vector3.yAxis), 0)
		end)

		it("changes heading while retaining the existing roll and pitch magnitude", function()
			local current = CFrame.new(4, 5, 6)
				* CFrame.Angles(math.rad(9), math.rad(25), math.rad(11))
			local target, resolvedHeading = CartStabilityMath.ApplyHeadingPreservingTilt(
				current,
				Vector3.xAxis,
				Vector3.yAxis,
				current.LookVector
			)
			local _, targetHeading = CartStabilityMath.BuildHeadingFrame(
				target.LookVector,
				Vector3.yAxis,
				resolvedHeading
			)

			expectVectorClose(target.Position, current.Position)
			expectClose(target.UpVector:Dot(Vector3.yAxis), current.UpVector:Dot(Vector3.yAxis))
			expect(targetHeading:Dot(Vector3.xAxis) > 0.99).to.equal(true)
		end)

		it("extracts roll error around the resolved forward axis", function()
			local current = CFrame.Angles(0, 0, math.rad(20))
			local result = CartStabilityMath.GetOrientationError(
				current.UpVector,
				Vector3.yAxis,
				-Vector3.zAxis
			)

			expectClose(math.abs(result.RollAngle), math.rad(20))
			expectClose(result.PitchAngle, 0)
			expectClose(result.TiltAngle, math.rad(20))
		end)

		it("extracts pitch error around the resolved lateral axis", function()
			local current = CFrame.Angles(math.rad(15), 0, 0)
			local result = CartStabilityMath.GetOrientationError(
				current.UpVector,
				Vector3.yAxis,
				-Vector3.zAxis
			)

			expectClose(result.RollAngle, 0)
			expectClose(math.abs(result.PitchAngle), math.rad(15))
			expectClose(result.TiltAngle, math.rad(15))
		end)

		it("chooses a deterministic heading-relative recovery axis when inverted", function()
			local first =
				CartStabilityMath.GetOrientationError(-Vector3.yAxis, Vector3.yAxis, Vector3.xAxis)
			local second =
				CartStabilityMath.GetOrientationError(-Vector3.yAxis, Vector3.yAxis, Vector3.xAxis)

			expectClose(first.TiltAngle, math.pi)
			expectVectorClose(first.CorrectionAxis, Vector3.xAxis)
			expectVectorClose(first.CorrectionAxis, second.CorrectionAxis)
		end)

		it("decomposes angular velocity into heading-relative roll, pitch, and yaw", function()
			local heading = -Vector3.zAxis
			local right = Vector3.xAxis
			local up = Vector3.yAxis
			local result = CartStabilityMath.DecomposeAngularVelocity(
				heading * 2 + right * 3 + up * 4,
				heading,
				up
			)

			expectClose(result.Roll, 2)
			expectClose(result.Pitch, 3)
			expectClose(result.Yaw, 4)
		end)

		it("provides a smooth progressive correction curve", function()
			local free = math.rad(6)
			local moderate = math.rad(18)
			local strong = math.rad(55)
			local low =
				CartStabilityMath.GetProgressiveCorrection(math.rad(10), free, moderate, strong)
			local medium =
				CartStabilityMath.GetProgressiveCorrection(math.rad(30), free, moderate, strong)

			expect(CartStabilityMath.GetProgressiveCorrection(free, free, moderate, strong)).to.equal(
				0
			)
			expectClose(
				CartStabilityMath.GetProgressiveCorrection(moderate, free, moderate, strong),
				0.5
			)
			expect(CartStabilityMath.GetProgressiveCorrection(strong, free, moderate, strong)).to.equal(
				1
			)
			expect(low > 0 and low < 0.5).to.equal(true)
			expect(medium > 0.5 and medium < 1).to.equal(true)

			local belowModerate =
				CartStabilityMath.GetProgressiveCorrection(moderate - 1e-7, free, moderate, strong)
			local aboveModerate =
				CartStabilityMath.GetProgressiveCorrection(moderate + 1e-7, free, moderate, strong)

			expectClose(belowModerate, aboveModerate, 1e-5)
		end)

		it("allows small free-angle lean without corrective torque", function()
			local result = computeStep(CFrame.Angles(0, 0, math.rad(3)), Vector3.zero)

			expect(result.Mode).to.equal("Free")
			expect(result.CorrectionStrength).to.equal(0)
			expectVectorClose(result.Torque, Vector3.zero)
		end)

		it("returns zero torque when the approved profile explicitly disables stability", function()
			local disabledProfile = table.clone(profile) :: any

			disabledProfile.Enabled = false

			local result = computeStep(
				CFrame.Angles(0, 0, math.rad(70)),
				Vector3.new(4, 5, 6),
				Vector3.new(1000, 1000, 1000),
				nil,
				disabledProfile
			)

			expectVectorClose(result.Torque, Vector3.zero)
		end)

		it("increases correction progressively from moderate to severe tilt", function()
			local moderate = computeStep(CFrame.Angles(0, 0, math.rad(12)), Vector3.zero)
			local strong = computeStep(CFrame.Angles(0, 0, math.rad(30)), Vector3.zero)
			local severe = computeStep(CFrame.Angles(0, 0, math.rad(70)), Vector3.zero)

			expect(moderate.Mode).to.equal("Moderate")
			expect(strong.Mode).to.equal("Strong")
			expect(severe.Mode).to.equal("Severe")
			expect(moderate.CorrectionStrength < strong.CorrectionStrength).to.equal(true)
			expect(strong.CorrectionStrength < severe.CorrectionStrength).to.equal(true)
			expect(severe.SevereTilt).to.equal(true)
			expect(severe.Torque.Magnitude <= profile.MaxCorrectiveTorque).to.equal(true)
		end)

		it("corrects pitch around the lateral axis while leaving yaw unforced", function()
			local rootCFrame = CFrame.Angles(math.rad(25), math.rad(90), 0)
			local result = computeStep(rootCFrame, Vector3.zero)
			local error = CartStabilityMath.GetOrientationError(
				rootCFrame.UpVector,
				Vector3.yAxis,
				result.Heading
			)

			expect(result.Torque:Dot(error.CorrectionAxis) > 0).to.equal(true)
			expectClose(result.Torque:Dot(Vector3.yAxis), 0)
		end)

		it("scales non-saturated correction by the supplied state multiplier", function()
			local rootCFrame = CFrame.Angles(0, 0, math.rad(12))
			local full = computeStep(rootCFrame, Vector3.zero, nil, nil, nil, 1)
			local half = computeStep(rootCFrame, Vector3.zero, nil, nil, nil, 0.5)

			expect(half.Torque.Magnitude < full.Torque.Magnitude).to.equal(true)
			expectClose(half.Torque.Magnitude / full.Torque.Magnitude, 0.5, 1e-3)
		end)

		it("damps roll and pitch angular velocity without damping ordinary yaw", function()
			local roll = computeStep(CFrame.identity, -Vector3.zAxis)
			local pitch = computeStep(CFrame.identity, Vector3.xAxis)
			local yaw = computeStep(CFrame.identity, Vector3.yAxis)

			expect(roll.Torque:Dot(-Vector3.zAxis) < 0).to.equal(true)
			expect(pitch.Torque:Dot(Vector3.xAxis) < 0).to.equal(true)
			expectVectorClose(yaw.Torque, Vector3.zero)
		end)

		it("does not accelerate roll or pitch beyond the corrective response ceiling", function()
			local maximumResponse = math.rad(profile.MaxCorrectiveAngularResponseDegreesPerSecond)

			for _, disturbance in
				{
					CFrame.Angles(0, 0, math.rad(35)),
					CFrame.Angles(math.rad(30), 0, 0),
				}
			do
				local orientationError = CartStabilityMath.GetOrientationError(
					disturbance.UpVector,
					Vector3.yAxis,
					disturbance.LookVector
				)
				local correctionAxis = orientationError.CorrectionAxis
				local atCeiling = computeStep(disturbance, correctionAxis * maximumResponse)
				local aboveCeiling = computeStep(disturbance, correctionAxis * maximumResponse * 2)
				local movingAway = computeStep(disturbance, -correctionAxis * maximumResponse * 2)
				local staleCorrectiveTorque = correctionAxis * profile.MaxCorrectiveTorque
				local atCeilingWithStaleTorque = computeStep(
					disturbance,
					correctionAxis * maximumResponse,
					staleCorrectiveTorque,
					1 / 60
				)
				local aboveCeilingWithStaleTorque = computeStep(
					disturbance,
					correctionAxis * maximumResponse * 2,
					staleCorrectiveTorque,
					1 / 60
				)

				expect(atCeiling.Torque:Dot(correctionAxis) <= 1e-5).to.equal(true)
				expect(aboveCeiling.Torque:Dot(correctionAxis) < 0).to.equal(true)
				expect(movingAway.Torque:Dot(correctionAxis) > 0).to.equal(true)
				expect(atCeilingWithStaleTorque.Torque:Dot(correctionAxis) <= 1e-5).to.equal(true)
				expect(aboveCeilingWithStaleTorque.Torque:Dot(correctionAxis) < 0).to.equal(true)
			end
		end)

		it("applies optional yaw damping only beyond its configured extreme threshold", function()
			local yawProfile = table.clone(profile) :: any

			yawProfile.ExtremeYawDamping = 1

			local below =
				computeStep(CFrame.identity, Vector3.yAxis * math.rad(200), nil, nil, yawProfile)
			local above =
				computeStep(CFrame.identity, Vector3.yAxis * math.rad(300), nil, nil, yawProfile)

			expectVectorClose(below.Torque, Vector3.zero)
			expect(above.Torque:Dot(Vector3.yAxis) < 0).to.equal(true)
		end)

		it("caps torque after severe recovery and assistance multipliers", function()
			local result = computeStep(
				CFrame.Angles(0, 0, math.rad(90)),
				-Vector3.zAxis * 100,
				nil,
				nil,
				nil,
				100
			)

			expect(result.Torque.Magnitude <= profile.MaxCorrectiveTorque).to.equal(true)
		end)

		it("smooths torque using the configured exponential response", function()
			local previous = Vector3.new(1000, 0, 0)
			local unchanged = computeStep(CFrame.identity, Vector3.zero, previous, 0)
			local decayed = computeStep(CFrame.identity, Vector3.zero, previous, 0.25)

			expectVectorClose(unchanged.Torque, previous)
			expect(decayed.Torque.Magnitude < previous.Magnitude).to.equal(true)
			expect(CartStabilityMath.GetExponentialAlpha(profile.ResponseSpeed, 0)).to.equal(0)
		end)

		it("returns finite bounded torque for invalid or negative delta time", function()
			for _, deltaTime in { 0 / 0, math.huge, -math.huge, -1 } do
				local result = computeStep(
					CFrame.Angles(0, 0, math.rad(35)),
					Vector3.zero,
					Vector3.zero,
					deltaTime
				)

				expect(result.Torque.X == result.Torque.X).to.equal(true)
				expect(result.Torque.Y == result.Torque.Y).to.equal(true)
				expect(result.Torque.Z == result.Torque.Z).to.equal(true)
				expect(result.Torque.Magnitude <= profile.MaxCorrectiveTorque).to.equal(true)
			end
		end)

		it("fails safely with invalid assembly mass or non-finite previous torque", function()
			local invalidMass = computeStep(
				CFrame.Angles(0, 0, math.rad(30)),
				Vector3.zero,
				Vector3.new(100, 0, 0),
				nil,
				nil,
				nil,
				0
			)
			local invalidPrevious = computeStep(
				CFrame.Angles(0, 0, math.rad(30)),
				Vector3.zero,
				Vector3.new(0 / 0, 0, 0)
			)

			expectVectorClose(invalidMass.Torque, Vector3.zero)
			expect(invalidPrevious.Torque.Magnitude <= profile.MaxCorrectiveTorque).to.equal(true)
		end)

		it("returns finite deterministic bounded recovery output near inversion", function()
			for _, angleDegrees in { 179.9, 180, 180.1 } do
				local inverted = CFrame.Angles(math.rad(angleDegrees), math.rad(37), 0)
				local first = computeStep(inverted, Vector3.zero)
				local second = computeStep(inverted, Vector3.zero)

				expectVectorClose(first.Torque, second.Torque)
				expectVectorClose(first.Heading, second.Heading)
				expect(first.Torque.X == first.Torque.X).to.equal(true)
				expect(first.Torque.Y == first.Torque.Y).to.equal(true)
				expect(first.Torque.Z == first.Torque.Z).to.equal(true)
				expect(first.Torque.Magnitude <= profile.MaxCorrectiveTorque).to.equal(true)
			end
		end)
	end)
end
