--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local POLICY = require(ReplicatedStorage.Shared.Config.CartMovementValidation)
	local CartMovementValidationMath =
		require(ReplicatedStorage.Shared.Utility.CartMovementValidationMath)

	local PROFILE = table.freeze({
		MaxTravelSpeed = 36,
		RecoveryBackupSpeed = 3.5,
		ForwardAcceleration = 16,
		CoastDeceleration = 20,
		Braking = 48,
		RecoveryBackupAcceleration = 6,
		RecoveryBackupDeceleration = 12,
		MaxAngularSpeed = 130,
	})

	local function evaluate(overrides: { [string]: any }?)
		local sample = {
			RootCFrame = CFrame.identity,
			LinearVelocity = Vector3.zero,
			AngularVelocity = Vector3.zero,
			PreviousPosition = nil,
			PreviousHorizontalSpeed = nil,
			ElapsedTime = 0.25,
			TrustedDisplacement = false,
		}

		for key, value in overrides or {} do
			sample[key] = value
		end

		return CartMovementValidationMath.EvaluateSample(sample :: any, PROFILE, POLICY)
	end

	local function hasReason(result: any, expectedReason: string): boolean
		for _, reason in result.Reasons do
			if reason == expectedReason then
				return true
			end
		end

		return false
	end

	describe("CartMovementValidationMath", function()
		it("detects finite and non-finite scalar, vector, and CFrame values", function()
			expect(CartMovementValidationMath.IsFiniteNumber(4)).to.equal(true)
			expect(CartMovementValidationMath.IsFiniteNumber(0 / 0)).to.equal(false)
			expect(CartMovementValidationMath.IsFiniteNumber(math.huge)).to.equal(false)
			expect(CartMovementValidationMath.IsFiniteVector3(Vector3.new(1, 2, 3))).to.equal(true)
			expect(CartMovementValidationMath.IsFiniteVector3(Vector3.new(1, -math.huge, 3))).to.equal(
				false
			)
			expect(CartMovementValidationMath.IsFiniteCFrame(CFrame.identity)).to.equal(true)
			expect(CartMovementValidationMath.IsFiniteCFrame(CFrame.new(math.huge, 0, 0))).to.equal(
				false
			)
		end)

		it("decomposes forward, reverse, and lateral speed from structural heading", function()
			local forward = CartMovementValidationMath.DecomposeHorizontalVelocity(
				CFrame.identity,
				Vector3.new(5, 20, -30)
			)
			local reverse = CartMovementValidationMath.DecomposeHorizontalVelocity(
				CFrame.identity,
				Vector3.new(-4, 0, 12)
			)

			expect(forward).never.to.equal(nil)
			expect((forward :: any).ForwardSpeed).to.equal(30)
			expect((forward :: any).ReverseSpeed).to.equal(0)
			expect((forward :: any).LateralSpeed).to.equal(5)
			expect(reverse).never.to.equal(nil)
			expect((reverse :: any).ForwardSpeed).to.equal(0)
			expect((reverse :: any).ReverseSpeed).to.equal(12)
			expect((reverse :: any).LateralSpeed).to.equal(4)
		end)

		it(
			"uses cart yaw rather than world axes and remains deterministic near vertical",
			function()
				local yawed = CartMovementValidationMath.DecomposeHorizontalVelocity(
					CFrame.Angles(0, math.rad(90), 0),
					Vector3.new(-20, 0, 0)
				)
				local pitched = CartMovementValidationMath.DecomposeHorizontalVelocity(
					CFrame.Angles(math.rad(90), 0, 0),
					Vector3.new(0, 0, -10)
				)

				expect(yawed).never.to.equal(nil)
				expect(math.abs((yawed :: any).ForwardSpeed - 20) < 1e-4).to.equal(true)
				expect(pitched).never.to.equal(nil)
				expect(math.abs((pitched :: any).ForwardSpeed - 10) < 1e-4).to.equal(true)
			end
		)

		it("builds all speed thresholds from the approved movement profile", function()
			local thresholds = CartMovementValidationMath.BuildThresholds(PROFILE, POLICY)

			expect(math.abs(thresholds.ForwardObservation - 58.6) < 1e-6).to.equal(true)
			-- Reverse shares the forward ceiling (a legal turnaround carries travel speed backwards).
			expect(math.abs(thresholds.ReverseObservation - 60.6) < 1e-6).to.equal(true)
			expect(thresholds.LateralObservation).to.equal(68)
			expect(thresholds.OverallObservation).to.equal(81)
			expect(thresholds.HorizontalCorrective).to.equal(105)
			expect(thresholds.HorizontalSevere).to.equal(138)
			expect(thresholds.AccelerationObservation).to.equal(232)
			expect(thresholds.AngularSpeedObservationDegrees).to.equal(445)
			expect(thresholds.AngularSpeedSevereDegrees).to.equal(1080)
			expect(table.isfrozen(thresholds)).to.equal(true)
		end)

		it(
			"uses the global horizontal cap when a profile-derived severe limit is larger",
			function()
				local thresholds = CartMovementValidationMath.BuildThresholds({
					MaxTravelSpeed = 100,
					RecoveryBackupSpeed = PROFILE.RecoveryBackupSpeed,
					ForwardAcceleration = PROFILE.ForwardAcceleration,
					CoastDeceleration = PROFILE.CoastDeceleration,
					Braking = PROFILE.Braking,
					RecoveryBackupAcceleration = PROFILE.RecoveryBackupAcceleration,
					RecoveryBackupDeceleration = PROFILE.RecoveryBackupDeceleration,
					MaxAngularSpeed = PROFILE.MaxAngularSpeed,
				}, POLICY)

				expect(thresholds.HorizontalSevere).to.equal(220)
			end
		)

		it("passes configured forward and reverse movement plus generous tolerance", function()
			expect(evaluate({ LinearVelocity = Vector3.new(0, 0, -36) }).Severity).to.equal("Valid")
			expect(evaluate({ LinearVelocity = Vector3.new(0, 0, 3.5) }).Severity).to.equal("Valid")
			expect(evaluate({ LinearVelocity = Vector3.new(0, 0, -58) }).Severity).to.equal("Valid")
		end)

		it("observes forward and reverse limits independently", function()
			local forward = evaluate({ LinearVelocity = Vector3.new(0, 0, -59) })
			local reverse = evaluate({ LinearVelocity = Vector3.new(0, 0, 61) })

			expect(forward.Severity).to.equal("Observation")
			expect(hasReason(forward, "ForwardSpeedExceeded")).to.equal(true)
			expect(reverse.Severity).to.equal("Observation")
			expect(hasReason(reverse, "ReverseSpeedExceeded")).to.equal(true)
		end)

		it(
			"tolerates collision-like lateral speed before observing the lateral envelope",
			function()
				expect(evaluate({ LinearVelocity = Vector3.new(67, 0, 0) }).Severity).to.equal(
					"Valid"
				)

				local exceeded = evaluate({ LinearVelocity = Vector3.new(69, 0, 0) })

				expect(exceeded.Severity).to.equal("Observation")
				expect(hasReason(exceeded, "LateralSpeedExceeded")).to.equal(true)
			end
		)

		it(
			"observes overall diagonal speed even when neither component alone is extreme",
			function()
				local result = evaluate({ LinearVelocity = Vector3.new(66, 0, -50) })

				expect(result.Severity).to.equal("Observation")
				expect(hasReason(result, "OverallHorizontalSpeedExceeded")).to.equal(true)
			end
		)

		it("classifies corrective and severe horizontal speeds", function()
			local corrective = evaluate({ LinearVelocity = Vector3.new(0, 0, -106) })
			local severe = evaluate({ LinearVelocity = Vector3.new(0, 0, -139) })

			expect(corrective.Severity).to.equal("Corrective")
			expect(hasReason(corrective, "CorrectiveHorizontalSpeed")).to.equal(true)
			expect(severe.Severity).to.equal("Severe")
			expect(hasReason(severe, "SevereHorizontalSpeed")).to.equal(true)
		end)

		it("classifies horizontal displacement using elapsed server time", function()
			local normal = evaluate({
				RootCFrame = CFrame.new(23, 0, 0),
				PreviousPosition = Vector3.zero,
			})
			local observed = evaluate({
				RootCFrame = CFrame.new(24, 0, 0),
				PreviousPosition = Vector3.zero,
			})
			local corrective = evaluate({
				RootCFrame = CFrame.new(43, 0, 0),
				PreviousPosition = Vector3.zero,
			})
			local severe = evaluate({
				RootCFrame = CFrame.new(67, 0, 0),
				PreviousPosition = Vector3.zero,
			})

			expect(normal.Severity).to.equal("Valid")
			expect(observed.Severity).to.equal("Observation")
			expect(corrective.Severity).to.equal("Corrective")
			expect(severe.Severity).to.equal("Severe")
		end)

		it("scales displacement envelopes with varying sample intervals", function()
			local short = evaluate({
				RootCFrame = CFrame.new(23, 0, 0),
				PreviousPosition = Vector3.zero,
				ElapsedTime = 0.25,
			})
			local delayed = evaluate({
				RootCFrame = CFrame.new(38, 0, 0),
				PreviousPosition = Vector3.zero,
				ElapsedTime = 0.5,
			})

			expect(short.Severity).to.equal("Valid")
			expect(delayed.Severity).to.equal("Valid")
		end)

		it("exempts trusted reset displacement without exempting physical state", function()
			local trusted = evaluate({
				RootCFrame = CFrame.new(1000, 0, 0),
				PreviousPosition = Vector3.zero,
				TrustedDisplacement = true,
			})
			local badVelocity = evaluate({
				RootCFrame = CFrame.new(1000, 0, 0),
				PreviousPosition = Vector3.zero,
				TrustedDisplacement = true,
				LinearVelocity = Vector3.new(0, 0, -139),
			})

			expect(trusted.Severity).to.equal("Valid")
			expect(badVelocity.Severity).to.equal("Severe")
		end)

		it("uses the strongest approved acceleration or deceleration as tolerance", function()
			local brakingLike = evaluate({
				LinearVelocity = Vector3.new(0, 0, -48),
				PreviousHorizontalSpeed = 0,
				ElapsedTime = 0.25,
			})
			local impossible = evaluate({
				LinearVelocity = Vector3.new(0, 0, -60),
				PreviousHorizontalSpeed = 0,
				ElapsedTime = 0.25,
			})

			expect(brakingLike.HorizontalAcceleration).to.equal(192)
			expect(hasReason(brakingLike, "HorizontalAccelerationExceeded")).to.equal(false)
			expect(impossible.HorizontalAcceleration).to.equal(240)
			expect(hasReason(impossible, "HorizontalAccelerationExceeded")).to.equal(true)
		end)

		it("uses acceleration only as observation-level supporting evidence", function()
			local result = evaluate({
				LinearVelocity = Vector3.new(0, 0, -60),
				PreviousHorizontalSpeed = 0,
				ElapsedTime = 0.25,
			})

			expect(result.Severity).to.equal("Observation")
		end)

		it("observes and hard-limits upward and downward velocity separately", function()
			expect(evaluate({ LinearVelocity = Vector3.new(0, 91, 0) }).Severity).to.equal(
				"Observation"
			)
			expect(evaluate({ LinearVelocity = Vector3.new(0, -241, 0) }).Severity).to.equal(
				"Observation"
			)
			expect(evaluate({ LinearVelocity = Vector3.new(0, 181, 0) }).Severity).to.equal(
				"Severe"
			)
			expect(evaluate({ LinearVelocity = Vector3.new(0, -351, 0) }).Severity).to.equal(
				"Severe"
			)
		end)

		it("uses elapsed time plus additive tolerance for vertical displacement", function()
			local upwardObservation = evaluate({
				RootCFrame = CFrame.new(0, 31, 0),
				PreviousPosition = Vector3.zero,
			})
			local upwardSevere = evaluate({
				RootCFrame = CFrame.new(0, 71, 0),
				PreviousPosition = Vector3.zero,
			})
			local downwardObservation = evaluate({
				RootCFrame = CFrame.new(0, -69, 0),
				PreviousPosition = Vector3.zero,
			})

			expect(upwardObservation.Severity).to.equal("Observation")
			expect(upwardSevere.Severity).to.equal("Severe")
			expect(downwardObservation.Severity).to.equal("Observation")
		end)

		it("converts observed angular velocity to degrees exactly once", function()
			local normal = evaluate({
				AngularVelocity = Vector3.new(0, math.rad(440), 0),
			})
			local observed = evaluate({
				AngularVelocity = Vector3.new(0, math.rad(446), 0),
			})
			local severe = evaluate({
				AngularVelocity = Vector3.new(0, math.rad(1081), 0),
			})

			expect(math.abs(normal.AngularSpeedDegrees - 440) < 1e-4).to.equal(true)
			expect(normal.Severity).to.equal("Valid")
			expect(observed.Severity).to.equal("Observation")
			expect(severe.Severity).to.equal("Severe")
		end)

		it(
			"classifies non-finite physical state as severe without continuing arithmetic",
			function()
				local badPosition = evaluate({ RootCFrame = CFrame.new(math.huge, 0, 0) })
				local badLinear = evaluate({ LinearVelocity = Vector3.new(0 / 0, 0, 0) })
				local badAngular = evaluate({ AngularVelocity = Vector3.new(0, math.huge, 0) })

				expect(badPosition.Severity).to.equal("Severe")
				expect(badPosition.HasFinitePhysicalState).to.equal(false)
				expect(badPosition.CanCorrect).to.equal(true)
				expect(badLinear.Severity).to.equal("Severe")
				expect(badAngular.Severity).to.equal("Severe")
				expect(badLinear.HorizontalSpeed).to.equal(0)
			end
		)

		it(
			"treats invalid elapsed time as internal invalidity that cannot correct physics",
			function()
				for _, elapsedTime in { 0, -1, 0 / 0, math.huge } do
					local result = evaluate({
						ElapsedTime = elapsedTime,
						PreviousPosition = Vector3.zero,
						PreviousHorizontalSpeed = 0,
						LinearVelocity = Vector3.new(0, 0, -139),
					})

					expect(result.Severity).to.equal("Invalid")
					expect(result.ElapsedTimeValid).to.equal(false)
					expect(result.CanCorrect).to.equal(false)
					expect(result.ObservedHorizontalSpeed).to.equal(0)
					expect(result.HorizontalAcceleration).to.equal(0)
				end
			end
		)

		it("promotes external authority observations into the same immutable result", function()
			local valid = evaluate()
			local observed = CartMovementValidationMath.PromoteResult(
				valid,
				"Observation",
				"NetworkOwnerTransition"
			)
			local corrective = CartMovementValidationMath.PromoteResult(
				observed,
				"Corrective",
				"PersistentNetworkOwnerMismatch"
			)
			local notDemoted = CartMovementValidationMath.PromoteResult(
				corrective,
				"Observation",
				"NoDriverAcceleration"
			)

			expect(valid.Severity).to.equal("Valid")
			expect(#valid.Reasons).to.equal(0)
			expect(observed.Severity).to.equal("Observation")
			expect(observed.Reasons[1]).to.equal("NetworkOwnerTransition")
			expect(corrective.Severity).to.equal("Corrective")
			expect(notDemoted.Severity).to.equal("Corrective")
			expect(notDemoted.HorizontalSpeed).to.equal(valid.HorizontalSpeed)
			expect(table.isfrozen(notDemoted)).to.equal(true)
			expect(table.isfrozen(notDemoted.Reasons)).to.equal(true)
		end)

		it("preserves invalid clock samples as non-corrective during promotion", function()
			local invalid = evaluate({ ElapsedTime = 0 })
			local promoted =
				CartMovementValidationMath.PromoteResult(invalid, "Severe", "AuthorityMismatch")

			expect(promoted.Severity).to.equal("Invalid")
			expect(promoted.CanCorrect).to.equal(false)
			expect(promoted.Reasons[#promoted.Reasons]).to.equal("AuthorityMismatch")
			expect(function()
				CartMovementValidationMath.PromoteResult(invalid, "Observation", "")
			end).to.throw()
		end)

		it("does not treat driver or movement-update labels as trusted displacement", function()
			local untrusted = evaluate({
				RootCFrame = CFrame.new(67, 0, 0),
				PreviousPosition = Vector3.zero,
				TrustedDisplacement = false,
			})
			local driverTransition = CartMovementValidationMath.PromoteResult(
				untrusted,
				"Observation",
				"DriverTransition"
			)
			local movementUpdate = CartMovementValidationMath.PromoteResult(
				driverTransition,
				"Observation",
				"LastServerMovementUpdate"
			)
			local trustedReset = evaluate({
				RootCFrame = CFrame.new(67, 0, 0),
				PreviousPosition = Vector3.zero,
				TrustedDisplacement = true,
			})

			expect(untrusted.Severity).to.equal("Severe")
			expect(driverTransition.Severity).to.equal("Severe")
			expect(movementUpdate.Severity).to.equal("Severe")
			expect(trustedReset.Severity).to.equal("Valid")
		end)

		it("returns immutable deterministic diagnostics", function()
			local first = evaluate({ LinearVelocity = Vector3.new(0, 0, -59) })
			local second = evaluate({ LinearVelocity = Vector3.new(0, 0, -59) })

			expect(first.Severity).to.equal(second.Severity)
			expect(first.Reasons[1]).to.equal(second.Reasons[1])
			expect(table.isfrozen(first)).to.equal(true)
			expect(table.isfrozen(first.Reasons)).to.equal(true)
		end)
	end)
end
