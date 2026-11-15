--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local POLICY = require(ReplicatedStorage.Shared.Config.CartMovementValidation)
	local CartMovementValidationMath =
		require(ReplicatedStorage.Shared.Utility.CartMovementValidationMath)
	local CartMovementValidationState =
		require(ReplicatedStorage.Shared.Utility.CartMovementValidationState)

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

	local function evaluate(
		state: CartMovementValidationState.State,
		rootCFrame: CFrame,
		linearVelocity: Vector3,
		now: number,
		elapsedTime: number?
	)
		local result = CartMovementValidationMath.EvaluateSample({
			RootCFrame = rootCFrame,
			LinearVelocity = linearVelocity,
			AngularVelocity = Vector3.zero,
			PreviousPosition = state.LastPosition,
			PreviousHorizontalSpeed = state.LastHorizontalSpeed,
			ElapsedTime = elapsedTime or (now - state.LastSampleTime),
			TrustedDisplacement = false,
		}, PROFILE, POLICY)

		return CartMovementValidationState.ApplyResult(
			state,
			result,
			rootCFrame,
			linearVelocity,
			now,
			POLICY
		)
	end

	describe("CartMovementValidationState", function()
		it("creates an immutable fresh runtime baseline", function()
			local state = CartMovementValidationState.Create(
				CFrame.new(10, 5, 20),
				Vector3.new(3, 0, -4),
				100,
				7
			)

			expect(state.Revision).to.equal(7)
			expect(state.LastPosition).to.equal(Vector3.new(10, 5, 20))
			expect(state.LastHorizontalSpeed).to.equal(5)
			expect(state.ViolationScore).to.equal(0)
			expect(state.ConsecutiveViolations).to.equal(0)
			expect(table.isfrozen(state)).to.equal(true)
		end)

		it("rejects non-finite initial and replacement baselines", function()
			expect(function()
				CartMovementValidationState.Create(CFrame.new(math.huge, 0, 0), Vector3.zero, 0)
			end).to.throw()
			expect(function()
				CartMovementValidationState.Create(CFrame.identity, Vector3.new(0 / 0, 0, 0), 0)
			end).to.throw()
			expect(function()
				CartMovementValidationState.Create(CFrame.identity, Vector3.zero, math.huge)
			end).to.throw()
		end)

		it("advances both sample and last-valid baselines after a valid sample", function()
			local initial = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)
			local nextState, decision =
				evaluate(initial, CFrame.new(0, 0, -4), Vector3.new(0, 0, -16), 0.25)

			expect(nextState.LastPosition).to.equal(Vector3.new(0, 0, -4))
			expect(nextState.LastValidCFrame).to.equal(CFrame.new(0, 0, -4))
			expect(nextState.LastValidSampleTime).to.equal(0.25)
			expect(decision.Action).to.equal("None")
		end)

		it("records an observation without promoting it to last-known-valid", function()
			local initial = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)
			local nextState, decision =
				evaluate(initial, CFrame.identity, Vector3.new(0, 0, -59), 0.25)

			expect(nextState.ViolationScore).to.equal(1)
			expect(nextState.ConsecutiveViolations).to.equal(1)
			expect(nextState.LastSampleTime).to.equal(0.25)
			expect(nextState.LastValidSampleTime).to.equal(0)
			expect(decision.Action).to.equal("Observe")
			expect(decision.CorrectionAllowed).to.equal(false)
		end)

		it("promotes repeated observations to a corrective recommendation", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)
			local decision = nil

			for index = 1, 4 do
				state, decision =
					evaluate(state, CFrame.identity, Vector3.new(0, 0, -59), index * 0.25)
			end

			expect(state.ViolationScore).to.equal(4)
			expect((decision :: any).Action).to.equal("Correct")
			expect((decision :: any).CorrectionAllowed).to.equal(true)
		end)

		it(
			"weights corrective samples while reserving immediate action for severe state",
			function()
				local initial = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)
				local correctiveState, correctiveDecision =
					evaluate(initial, CFrame.identity, Vector3.new(0, 0, -106), 0.25)
				local severeState, severeDecision =
					evaluate(initial, CFrame.identity, Vector3.new(0, 0, -139), 0.25)

				expect(correctiveState.ViolationScore).to.equal(2)
				expect(correctiveDecision.Action).to.equal("Observe")
				expect(severeState.ViolationScore).to.equal(8)
				expect(severeDecision.Action).to.equal("SevereCorrect")
			end
		)

		it("requires two corrective samples to reach the corrective score threshold", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)

			state = select(1, evaluate(state, CFrame.identity, Vector3.new(0, 0, -106), 0.5))

			local repeatedState, decision =
				evaluate(state, CFrame.identity, Vector3.new(0, 0, -106), 1)

			expect(repeatedState.ViolationScore).to.equal(4)
			expect(decision.Action).to.equal("Correct")
		end)

		it("bounds violation score and escalates repeated observations to severe", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)
			local decision = nil

			for index = 1, 12 do
				state, decision =
					evaluate(state, CFrame.identity, Vector3.new(0, 0, -59), index * 0.25)
			end

			expect(state.ViolationScore).to.equal(12)
			expect((decision :: any).Action).to.equal("SevereCorrect")
		end)

		it("decays score and clears consecutive count on valid samples", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)

			state = select(1, evaluate(state, CFrame.identity, Vector3.new(0, 0, -106), 0.25))

			local validState, decision = evaluate(state, CFrame.identity, Vector3.zero, 1.25)

			expect(validState.ViolationScore).to.equal(1)
			expect(validState.ConsecutiveViolations).to.equal(0)
			expect(decision.Action).to.equal("None")
		end)

		it("does not score, correct, or advance on invalid elapsed time", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 5)
			local result = CartMovementValidationMath.EvaluateSample({
				RootCFrame = CFrame.identity,
				LinearVelocity = Vector3.new(0, 0, -139),
				AngularVelocity = Vector3.zero,
				PreviousPosition = state.LastPosition,
				PreviousHorizontalSpeed = state.LastHorizontalSpeed,
				ElapsedTime = 0,
				TrustedDisplacement = false,
			}, PROFILE, POLICY)
			local nextState, decision = CartMovementValidationState.ApplyResult(
				state,
				result,
				CFrame.identity,
				Vector3.new(0, 0, -139),
				5,
				POLICY
			)

			expect(result.Severity).to.equal("Invalid")
			expect(nextState.ViolationScore).to.equal(0)
			expect(nextState.LastSampleTime).to.equal(5)
			expect(decision.Action).to.equal("None")
			expect(decision.CorrectionAllowed).to.equal(false)
		end)

		it("suppresses repeated correction during the internal cooldown", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)

			state = select(1, evaluate(state, CFrame.identity, Vector3.new(0, 0, -106), 0.5))

			local correctedState, firstDecision =
				evaluate(state, CFrame.identity, Vector3.new(0, 0, -106), 1)

			expect(firstDecision.Action).to.equal("Correct")
			correctedState = CartMovementValidationState.MarkCorrection(correctedState, 1)

			local coolingState, coolingDecision =
				evaluate(correctedState, CFrame.identity, Vector3.new(0, 0, -106), 2)

			expect(coolingDecision.RequestedAction).to.equal("Correct")
			expect(coolingDecision.Action).to.equal("Observe")
			expect(coolingDecision.CorrectionSuppressed).to.equal(true)
			expect(CartMovementValidationState.IsCorrectionAllowed(coolingState, 2.49, POLICY)).to.equal(
				false
			)
			expect(CartMovementValidationState.IsCorrectionAllowed(coolingState, 2.5, POLICY)).to.equal(
				true
			)
		end)

		it(
			"retains the trusted baseline while a severe correction is suppressed or pending",
			function()
				local initial = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)
				local recentlyCorrected = CartMovementValidationState.MarkCorrection(initial, 0)
				local displacedCFrame = CFrame.new(100, 0, 0)
				local displacedVelocity = Vector3.new(0, 0, -139)
				local coolingState, coolingDecision =
					evaluate(recentlyCorrected, displacedCFrame, displacedVelocity, 1)

				expect(coolingDecision.RequestedAction).to.equal("SevereCorrect")
				expect(coolingDecision.Action).to.equal("Observe")
				expect(coolingDecision.CorrectionSuppressed).to.equal(true)
				expect(coolingState.LastPosition).to.equal(Vector3.zero)
				expect(coolingState.LastSampleTime).to.equal(0)

				local retryState, retryDecision =
					evaluate(coolingState, displacedCFrame, displacedVelocity, 2)

				expect(retryDecision.Action).to.equal("SevereCorrect")
				expect(retryDecision.CorrectionAllowed).to.equal(true)
				expect(retryState.LastPosition).to.equal(Vector3.zero)
				expect(retryState.LastSampleTime).to.equal(0)
			end
		)

		it("does not let pending severe displacement age into a valid baseline", function()
			local initial = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)
			local displacedCFrame = CFrame.new(67, 0, 0)
			local firstResult = CartMovementValidationMath.EvaluateSample({
				RootCFrame = displacedCFrame,
				LinearVelocity = Vector3.zero,
				AngularVelocity = Vector3.zero,
				PreviousPosition = initial.LastPosition,
				PreviousHorizontalSpeed = initial.LastHorizontalSpeed,
				ElapsedTime = 0.25,
				TrustedDisplacement = false,
			}, PROFILE, POLICY)
			local pendingState = select(
				1,
				CartMovementValidationState.ApplyResult(
					initial,
					firstResult,
					displacedCFrame,
					Vector3.zero,
					0.25,
					POLICY
				)
			)

			expect(firstResult.Severity).to.equal("Severe")
			expect(pendingState.LastPosition).to.equal(Vector3.zero)
			expect(pendingState.LastSampleTime).to.equal(0)

			local agedResult = CartMovementValidationMath.EvaluateSample({
				RootCFrame = displacedCFrame,
				LinearVelocity = Vector3.zero,
				AngularVelocity = Vector3.zero,
				PreviousPosition = pendingState.LastPosition,
				PreviousHorizontalSpeed = pendingState.LastHorizontalSpeed,
				ElapsedTime = 2,
				TrustedDisplacement = false,
			}, PROFILE, POLICY)
			local stillPending = CartMovementValidationMath.PromoteResult(
				agedResult,
				"Severe",
				"PositionCorrectionPending"
			)
			local retryState, retryDecision = CartMovementValidationState.ApplyResult(
				pendingState,
				stillPending,
				displacedCFrame,
				Vector3.zero,
				2,
				POLICY
			)

			expect(agedResult.Severity).to.equal("Valid")
			expect(stillPending.Severity).to.equal("Severe")
			expect(retryDecision.RequestedAction).to.equal("SevereCorrect")
			expect(retryState.LastPosition).to.equal(Vector3.zero)
			expect(retryState.LastSampleTime).to.equal(0)
		end)

		it("does not let a driver transition bless untrusted severe displacement", function()
			local initial = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)
			local displacedCFrame = CFrame.new(67, 0, 0)
			local displacementResult = CartMovementValidationMath.EvaluateSample({
				RootCFrame = displacedCFrame,
				LinearVelocity = Vector3.zero,
				AngularVelocity = Vector3.zero,
				PreviousPosition = initial.LastPosition,
				PreviousHorizontalSpeed = initial.LastHorizontalSpeed,
				ElapsedTime = 0.25,
				TrustedDisplacement = false,
			}, PROFILE, POLICY)
			local driverTransition = CartMovementValidationMath.PromoteResult(
				displacementResult,
				"Observation",
				"DriverTransition"
			)
			local nextState, decision = CartMovementValidationState.ApplyResult(
				initial,
				driverTransition,
				displacedCFrame,
				Vector3.zero,
				0.25,
				POLICY
			)

			expect(driverTransition.Severity).to.equal("Severe")
			expect(decision.Action).to.equal("SevereCorrect")
			expect(nextState.LastPosition).to.equal(Vector3.zero)
			expect(nextState.LastValidCFrame).to.equal(CFrame.identity)
		end)

		it("records correction time only through the explicit successful-action hook", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)

			expect(state.LastCorrectionTime).to.equal(nil)

			local corrected = CartMovementValidationState.MarkCorrection(state, 4)

			expect(state.LastCorrectionTime).to.equal(nil)
			expect(corrected.LastCorrectionTime).to.equal(4)
			expect(table.isfrozen(corrected)).to.equal(true)
			expect(function()
				CartMovementValidationState.MarkCorrection(state, math.huge)
			end).to.throw()
		end)

		it("resets spawn, reset, or replacement baselines with a fresh revision", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0, 1)

			state = select(1, evaluate(state, CFrame.identity, Vector3.new(0, 0, -106), 0.25))

			local reset = CartMovementValidationState.ResetBaseline(
				state,
				CFrame.new(100, 10, 200),
				Vector3.zero,
				1,
				2
			)

			expect(reset.Revision).to.equal(2)
			expect(reset.LastPosition).to.equal(Vector3.new(100, 10, 200))
			expect(reset.LastValidCFrame).to.equal(CFrame.new(100, 10, 200))
			expect(reset.ViolationScore).to.equal(0)
			expect(reset.ConsecutiveViolations).to.equal(0)
		end)

		it("can preserve recent score while resetting baseline after a correction", function()
			local state = CartMovementValidationState.Create(CFrame.identity, Vector3.zero, 0)

			state = select(1, evaluate(state, CFrame.identity, Vector3.new(0, 0, -106), 0.25))
			state = select(1, evaluate(state, CFrame.identity, Vector3.new(0, 0, -106), 0.5))
			state = CartMovementValidationState.MarkCorrection(state, 0.5)

			local reset = CartMovementValidationState.ResetBaseline(
				state,
				CFrame.new(5, 0, 0),
				Vector3.zero,
				0.75,
				nil,
				false
			)

			expect(reset.ViolationScore).to.equal(4)
			expect(reset.ConsecutiveViolations).to.equal(2)
			expect(reset.LastCorrectionTime).to.equal(0.5)
		end)
	end)
end
