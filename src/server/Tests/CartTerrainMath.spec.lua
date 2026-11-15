--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartTerrainMath = require(ReplicatedStorage.Shared.Utility.CartTerrainMath)

	local slopeProfile = {
		SlopeEffectStartDegrees = 3,
		FullSlopeEffectDegrees = 35,
		MaximumUphillAccelerationReduction = 0.25,
		MaximumDownhillAcceleration = 3,
		MaximumDownhillCoastReduction = 0.2,
	}

	local function expectClose(actual: number, expected: number, tolerance: number?)
		expect(math.abs(actual - expected) <= (tolerance or 1e-5)).to.equal(true)
	end

	local function expectVectorClose(actual: Vector3, expected: Vector3, tolerance: number?)
		expect((actual - expected).Magnitude <= (tolerance or 1e-5)).to.equal(true)
	end

	local function getTiltedUp(angleDegrees: number): Vector3
		return CFrame.fromAxisAngle(Vector3.xAxis, math.rad(angleDegrees))
			:VectorToWorldSpace(Vector3.yAxis)
	end

	describe("CartTerrainMath", function()
		describe("terrain-plane frames", function()
			it("projects vectors onto a finite plane", function()
				local normal = getTiltedUp(20)
				local projected = CartTerrainMath.ProjectOntoPlane(Vector3.new(2, 4, -8), normal)

				expectClose(projected:Dot(normal), 0)
			end)

			it("fails finite-safely for invalid vectors and degenerate normals", function()
				expectVectorClose(
					CartTerrainMath.ProjectOntoPlane(Vector3.new(0 / 0, 1, 0), Vector3.yAxis),
					Vector3.zero
				)
				expectVectorClose(
					CartTerrainMath.ProjectOntoPlane(Vector3.xAxis, Vector3.zero),
					Vector3.zero
				)
				expectVectorClose(
					CartTerrainMath.ProjectOntoPlane(Vector3.xAxis, Vector3.new(math.huge, 0, 0)),
					Vector3.zero
				)
			end)

			it("builds an orthonormal flat-ground tangent frame", function()
				local forward, right = CartTerrainMath.BuildTangentFrame(
					Vector3.new(0, 0.5, -1),
					Vector3.yAxis,
					Vector3.xAxis
				)

				expectVectorClose(forward, -Vector3.zAxis)
				expectVectorClose(right, Vector3.xAxis)
				expectClose(forward:Dot(right), 0)
				expectClose(forward:Dot(Vector3.yAxis), 0)
				expectClose(right:Dot(Vector3.yAxis), 0)
			end)

			it("projects heading into an inclined terrain frame", function()
				local up = getTiltedUp(20)
				local forward, right =
					CartTerrainMath.BuildTangentFrame(-Vector3.zAxis, up, Vector3.xAxis)

				expectClose(forward.Magnitude, 1)
				expectClose(right.Magnitude, 1)
				expectClose(forward:Dot(up), 0)
				expectClose(right:Dot(up), 0)
				expectClose(forward:Dot(right), 0)
				expect(CartTerrainMath.GetSignedSlopeDegrees(forward) > 19.9).to.equal(true)
			end)

			it("uses a deterministic fallback for vertical or invalid headings", function()
				local firstForward, firstRight =
					CartTerrainMath.BuildTangentFrame(Vector3.yAxis, Vector3.yAxis, -Vector3.zAxis)
				local secondForward, secondRight = CartTerrainMath.BuildTangentFrame(
					Vector3.new(0 / 0, 0, 0),
					Vector3.yAxis,
					-Vector3.zAxis
				)

				expectVectorClose(firstForward, -Vector3.zAxis)
				expectVectorClose(secondForward, firstForward)
				expectVectorClose(secondRight, firstRight)
			end)

			it("keeps a contour-following heading level on a side slope", function()
				local sideSlopeUp = CFrame.fromAxisAngle(Vector3.zAxis, math.rad(25))
					:VectorToWorldSpace(Vector3.yAxis)
				local forward = CartTerrainMath.BuildTangentFrame(-Vector3.zAxis, sideSlopeUp, nil)

				expectClose(CartTerrainMath.GetSignedSlopeDegrees(forward), 0)
			end)

			it("rotates heading around terrain up without leaving its tangent plane", function()
				local up = getTiltedUp(18)
				local forward = CartTerrainMath.BuildTangentFrame(-Vector3.zAxis, up, Vector3.xAxis)
				local rotated =
					CartTerrainMath.RotateHeading(forward, up, math.rad(90), Vector3.xAxis)

				expectClose(rotated.Magnitude, 1)
				expectClose(rotated:Dot(up), 0)
				expectClose(rotated:Dot(forward), 0, 1e-4)
			end)

			it("preserves heading when rotation input is invalid or zero", function()
				local forward = Vector3.new(1, 0, -1).Unit

				expectVectorClose(
					CartTerrainMath.RotateHeading(forward, Vector3.yAxis, 0, -Vector3.zAxis),
					forward
				)
				expectVectorClose(
					CartTerrainMath.RotateHeading(forward, Vector3.yAxis, 0 / 0, -Vector3.zAxis),
					forward
				)
			end)
		end)

		describe("ground-normal resolution", function()
			it("combines consistent supporting normals", function()
				local first = getTiltedUp(4)
				local second = getTiltedUp(6)
				local combined, accepted =
					CartTerrainMath.CombineGroundNormals({ first, second }, Vector3.yAxis, 65, 15)

				expect(accepted).to.equal(2)
				expect(combined ~= nil).to.equal(true)
				expectVectorClose(combined :: Vector3, getTiltedUp(5), 1e-4)
			end)

			it("rejects non-finite, zero, wall-like, and downward normals", function()
				local combined, accepted = CartTerrainMath.CombineGroundNormals({
					Vector3.new(0 / 0, 1, 0),
					Vector3.zero,
					Vector3.xAxis,
					-Vector3.yAxis,
				}, Vector3.yAxis, 65, 20)

				expect(combined).to.equal(nil)
				expect(accepted).to.equal(0)
			end)

			it("rejects an otherwise driveable angular outlier", function()
				local flat = Vector3.yAxis
				local nearFlat = getTiltedUp(5)
				local outlier = getTiltedUp(50)
				local combined, accepted = CartTerrainMath.CombineGroundNormals(
					{ outlier, flat, nearFlat },
					Vector3.yAxis,
					65,
					12
				)

				expect(accepted).to.equal(2)
				expect(combined ~= nil).to.equal(true)
				expect(CartTerrainMath.GetSlopeAngleDegrees(combined :: Vector3) < 3).to.equal(true)
			end)

			it("produces equivalent results regardless of sample order", function()
				local normals = { getTiltedUp(-3), getTiltedUp(2), getTiltedUp(6) }
				local first, firstCount =
					CartTerrainMath.CombineGroundNormals(normals, Vector3.yAxis, 65, 15)
				local second, secondCount = CartTerrainMath.CombineGroundNormals(
					{ normals[3], normals[1], normals[2] },
					Vector3.yAxis,
					65,
					15
				)

				expect(firstCount).to.equal(secondCount)
				expectVectorClose(first :: Vector3, second :: Vector3)
			end)

			it("returns the unsigned angle between terrain normal and world up", function()
				expectClose(
					CartTerrainMath.GetSlopeAngleDegrees(getTiltedUp(30), Vector3.yAxis),
					30
				)
				expect(CartTerrainMath.GetSlopeAngleDegrees(Vector3.zero)).to.equal(0)
				expect(CartTerrainMath.GetSlopeAngleDegrees(Vector3.new(0 / 0, 0, 0))).to.equal(0)
			end)

			it("rejects invalid normal-combination limits deterministically", function()
				for _, invalidValue in { 0 / 0, math.huge, -math.huge, -1 } do
					local normal, accepted = CartTerrainMath.CombineGroundNormals(
						{ Vector3.yAxis },
						Vector3.yAxis,
						invalidValue,
						15
					)

					expect(normal).to.equal(nil)
					expect(accepted).to.equal(0)
				end
			end)
		end)

		describe("desired-up smoothing", function()
			it("smoothly approaches a new terrain normal", function()
				local target = getTiltedUp(30)
				local smoothed = CartTerrainMath.SmoothDesiredUp(Vector3.yAxis, target, 5, 360, 0.1)
				local smoothedAngle = CartTerrainMath.GetSlopeAngleDegrees(smoothed)

				expect(smoothedAngle > 0).to.equal(true)
				expect(smoothedAngle < 30).to.equal(true)
				expectClose(smoothed.Magnitude, 1)
			end)

			it("caps terrain-normal rotation by angular rate", function()
				local target = getTiltedUp(60)
				local smoothed =
					CartTerrainMath.SmoothDesiredUp(Vector3.yAxis, target, 1000, 10, 0.5)

				expectClose(CartTerrainMath.GetSlopeAngleDegrees(smoothed), 5, 1e-3)
			end)

			it("does not change orientation at zero or invalid delta time", function()
				for _, deltaTime in { 0, -1, 0 / 0, math.huge } do
					expectVectorClose(
						CartTerrainMath.SmoothDesiredUp(
							Vector3.yAxis,
							getTiltedUp(30),
							10,
							120,
							deltaTime
						),
						Vector3.yAxis
					)
				end
			end)

			it("retains a finite previous reference when the target is invalid", function()
				expectVectorClose(
					CartTerrainMath.SmoothDesiredUp(
						getTiltedUp(10),
						Vector3.new(0 / 0, 0, 0),
						10,
						120,
						0.1
					),
					getTiltedUp(10)
				)
			end)

			it("crosses opposing crest normals without a snap or non-finite result", function()
				local current = getTiltedUp(20)

				for _ = 1, 20 do
					local nextUp =
						CartTerrainMath.SmoothDesiredUp(current, getTiltedUp(-20), 8, 90, 1 / 60)
					local stepDegrees = math.deg(math.acos(math.clamp(current:Dot(nextUp), -1, 1)))

					expect(stepDegrees <= 1.5 + 1e-5).to.equal(true)
					expect(nextUp.X == nextUp.X).to.equal(true)
					expect(nextUp.Y == nextUp.Y).to.equal(true)
					expect(nextUp.Z == nextUp.Z).to.equal(true)
					current = nextUp
				end

				expect(CartTerrainMath.GetSlopeAngleDegrees(current) < 20).to.equal(true)
			end)
		end)

		describe("grounded-state hysteresis", function()
			it("keeps an already grounded cart grounded with full support", function()
				local state, fullElapsed, unsupportedElapsed =
					CartTerrainMath.AdvanceGroundState("Grounded", 0, 0, 3, 2, 0.08, 0.18, 0.1)

				expect(state).to.equal("Grounded")
				expect(fullElapsed).to.equal(0)
				expect(unsupportedElapsed).to.equal(0)
			end)

			it("uses airborne delay to prevent one-frame support loss", function()
				local state, fullElapsed, unsupportedElapsed =
					CartTerrainMath.AdvanceGroundState("Grounded", 0, 0, 0, 2, 0.08, 0.18, 0.1)

				expect(state).to.equal("Partial")
				expect(fullElapsed).to.equal(0)
				expectClose(unsupportedElapsed, 0.1)

				state, fullElapsed, unsupportedElapsed = CartTerrainMath.AdvanceGroundState(
					state,
					fullElapsed,
					unsupportedElapsed,
					0,
					2,
					0.08,
					0.18,
					0.1
				)

				expect(state).to.equal("Airborne")
				expectClose(unsupportedElapsed, 0.2)
			end)

			it("requires sustained full support before airborne reacquisition", function()
				local state, fullElapsed, unsupportedElapsed =
					CartTerrainMath.AdvanceGroundState("Airborne", 0, 0.2, 3, 2, 0.1, 0.18, 0.06)

				expect(state).to.equal("Partial")
				expectClose(fullElapsed, 0.06)
				expect(unsupportedElapsed).to.equal(0)

				state, fullElapsed, unsupportedElapsed = CartTerrainMath.AdvanceGroundState(
					state,
					fullElapsed,
					unsupportedElapsed,
					3,
					2,
					0.1,
					0.18,
					0.06
				)

				expect(state).to.equal("Grounded")
				expect(fullElapsed >= 0.1).to.equal(true)
			end)

			it("classifies one supporting sample as partial and resets both timers", function()
				local state, fullElapsed, unsupportedElapsed =
					CartTerrainMath.AdvanceGroundState("Airborne", 0.07, 0.2, 1, 2, 0.1, 0.18, 0.1)

				expect(state).to.equal("Partial")
				expect(fullElapsed).to.equal(0)
				expect(unsupportedElapsed).to.equal(0)
			end)

			it("supports immediate transitions when both configured delays are zero", function()
				local airborne = CartTerrainMath.AdvanceGroundState("Grounded", 0, 0, 0, 2, 0, 0, 0)
				local grounded = CartTerrainMath.AdvanceGroundState("Airborne", 0, 0, 2, 2, 0, 0, 0)

				expect(airborne).to.equal("Airborne")
				expect(grounded).to.equal("Grounded")
			end)

			it("does not advance hysteresis timers with invalid delta time", function()
				for _, deltaTime in { -1, 0 / 0, math.huge } do
					local state, _, unsupportedElapsed = CartTerrainMath.AdvanceGroundState(
						"Grounded",
						0,
						0,
						0,
						2,
						0.1,
						0.2,
						deltaTime
					)

					expect(state).to.equal("Partial")
					expect(unsupportedElapsed).to.equal(0)
				end
			end)
		end)

		describe("slope response", function()
			it("returns positive uphill, negative downhill, and zero side-slope grade", function()
				local uphill = Vector3.new(0, math.sin(math.rad(20)), -math.cos(math.rad(20)))
				local downhill = Vector3.new(0, -math.sin(math.rad(20)), -math.cos(math.rad(20)))

				expectClose(CartTerrainMath.GetSignedSlopeDegrees(uphill), 20)
				expectClose(CartTerrainMath.GetSignedSlopeDegrees(downhill), -20)
				expect(CartTerrainMath.GetSignedSlopeDegrees(-Vector3.zAxis)).to.equal(0)
				expect(CartTerrainMath.GetSignedSlopeDegrees(Vector3.new(0 / 0, 0, 0))).to.equal(0)
			end)

			it("keeps flat and below-threshold terrain at exact identity", function()
				for _, slope in { -3, -1, 0, 1, 3 } do
					local result = CartTerrainMath.GetSlopeInfluence(slope, slopeProfile)

					expect(result.ResponseStrength).to.equal(0)
					expect(result.AccelerationMultiplier).to.equal(1)
					expect(result.DownhillAcceleration).to.equal(0)
					expect(result.CoastMultiplier).to.equal(1)
				end
			end)

			it("reduces uphill acceleration smoothly without adding downhill force", function()
				local medium = CartTerrainMath.GetSlopeInfluence(19, slopeProfile)
				local full = CartTerrainMath.GetSlopeInfluence(35, slopeProfile)

				expect(medium.ResponseStrength > 0 and medium.ResponseStrength < 1).to.equal(true)
				expect(medium.AccelerationMultiplier < 1).to.equal(true)
				expect(medium.AccelerationMultiplier > 0.75).to.equal(true)
				expect(medium.DownhillAcceleration).to.equal(0)
				expect(medium.CoastMultiplier).to.equal(1)
				expect(full.ResponseStrength).to.equal(1)
				expectClose(full.AccelerationMultiplier, 0.75)
			end)

			it("adds bounded downhill assistance and reduces coast resistance", function()
				local medium = CartTerrainMath.GetSlopeInfluence(-19, slopeProfile)
				local full = CartTerrainMath.GetSlopeInfluence(-100, slopeProfile)

				expect(medium.ResponseStrength > 0 and medium.ResponseStrength < 1).to.equal(true)
				expect(medium.AccelerationMultiplier).to.equal(1)
				expect(medium.DownhillAcceleration > 0).to.equal(true)
				expect(medium.DownhillAcceleration < 3).to.equal(true)
				expect(medium.CoastMultiplier < 1 and medium.CoastMultiplier > 0.8).to.equal(true)
				expect(full.ResponseStrength).to.equal(1)
				expect(full.DownhillAcceleration).to.equal(3)
				expectClose(full.CoastMultiplier, 0.8)
			end)

			it("uses equal response strength for equal uphill and downhill grades", function()
				local uphill = CartTerrainMath.GetSlopeInfluence(18, slopeProfile)
				local downhill = CartTerrainMath.GetSlopeInfluence(-18, slopeProfile)

				expectClose(uphill.ResponseStrength, downhill.ResponseStrength)
			end)

			it("defensively bounds approved modifier magnitudes", function()
				local extremeProfile = table.clone(slopeProfile)

				extremeProfile.MaximumUphillAccelerationReduction = 10
				extremeProfile.MaximumDownhillAcceleration = -10
				extremeProfile.MaximumDownhillCoastReduction = 10

				local uphill = CartTerrainMath.GetSlopeInfluence(100, extremeProfile)
				local downhill = CartTerrainMath.GetSlopeInfluence(-100, extremeProfile)

				expect(uphill.AccelerationMultiplier).to.equal(0)
				expect(downhill.DownhillAcceleration).to.equal(0)
				expect(downhill.CoastMultiplier).to.equal(0)
			end)

			it("returns flat identity for malformed slope inputs", function()
				for _, invalidSlope in { 0 / 0, math.huge, -math.huge } do
					local result = CartTerrainMath.GetSlopeInfluence(invalidSlope, slopeProfile)

					expect(result.ResponseStrength).to.equal(0)
					expect(result.AccelerationMultiplier).to.equal(1)
					expect(result.DownhillAcceleration).to.equal(0)
					expect(result.CoastMultiplier).to.equal(1)
				end

				local invalidProfile = table.clone(slopeProfile)

				invalidProfile.FullSlopeEffectDegrees = 0 / 0

				local result = CartTerrainMath.GetSlopeInfluence(20, invalidProfile)

				expect(result.ResponseStrength).to.equal(0)
				expect(result.AccelerationMultiplier).to.equal(1)
			end)

			it("is deterministic for repeated terrain inputs", function()
				local first = CartTerrainMath.GetSlopeInfluence(-22.5, slopeProfile)
				local second = CartTerrainMath.GetSlopeInfluence(-22.5, slopeProfile)

				expect(first.ResponseStrength).to.equal(second.ResponseStrength)
				expect(first.AccelerationMultiplier).to.equal(second.AccelerationMultiplier)
				expect(first.DownhillAcceleration).to.equal(second.DownhillAcceleration)
				expect(first.CoastMultiplier).to.equal(second.CoastMultiplier)
			end)
		end)
	end)
end
