--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartResetLifecycle = require(ReplicatedStorage.Shared.Utility.CartResetLifecycle)

	local function transition(snapshot: any, state: any, now: number): any
		local nextSnapshot, transitionError = CartResetLifecycle.Transition(snapshot, state, now)

		expect(transitionError).to.equal(nil)
		expect(nextSnapshot == nil).to.equal(false)

		return nextSnapshot
	end

	describe("CartResetLifecycle", function()
		it("implements the exact successful Phase 1J lifecycle", function()
			local snapshot = CartResetLifecycle.Create(0)
			local expectedStates = {
				"HoldStarted",
				"HoldComplete",
				"Validation",
				"Suspension",
				"Reposition",
				"Recovery",
				"Resume",
				"Idle",
			}

			for index, state in expectedStates do
				local previousState = snapshot.CurrentState

				snapshot = transition(snapshot, state, index)
				expect(snapshot.CurrentState).to.equal(state)
				expect(snapshot.PreviousState).to.equal(previousState)
				expect(snapshot.Revision).to.equal(index)
				expect(snapshot.StateEnteredAt).to.equal(index)
				expect(table.isfrozen(snapshot)).to.equal(true)
			end
		end)

		it("supports early hold cancellation and requires a fresh hold", function()
			local snapshot = transition(CartResetLifecycle.Create(0), "HoldStarted", 0.1)

			snapshot = transition(snapshot, "Cancelled", 0.5)
			expect(snapshot.CurrentState).to.equal("Cancelled")

			snapshot = transition(snapshot, "Idle", 0.5)
			expect(snapshot.CurrentState).to.equal("Idle")

			snapshot = transition(snapshot, "HoldStarted", 1)
			expect(snapshot.CurrentState).to.equal("HoldStarted")
			expect(snapshot.StateEnteredAt).to.equal(1)
		end)

		it("supports deterministic failure recovery from every execution stage", function()
			for _, failureState in
				{ "Validation", "Suspension", "Reposition", "Recovery", "Resume" }
			do
				local snapshot = CartResetLifecycle.Create(0)
				local path = {
					"HoldStarted",
					"HoldComplete",
					"Validation",
					"Suspension",
					"Reposition",
					"Recovery",
					"Resume",
				}

				for index, state in path do
					snapshot = transition(snapshot, state, index)

					if state == failureState then
						break
					end
				end

				snapshot = transition(snapshot, "Failed", 10)
				expect(snapshot.CurrentState).to.equal("Failed")

				snapshot = transition(snapshot, "Idle", 10)
				expect(snapshot.CurrentState).to.equal("Idle")
			end
		end)

		it("rejects skipped, backward, repeated, and unknown transitions", function()
			local snapshot = CartResetLifecycle.Create(0)
			local skipped, skippedError = CartResetLifecycle.Transition(snapshot, "Validation", 1)

			expect(skipped).to.equal(nil)
			expect(type(skippedError)).to.equal("string")

			snapshot = transition(snapshot, "HoldStarted", 1)

			local repeated = CartResetLifecycle.Transition(snapshot, "HoldStarted", 1)
			local backward = CartResetLifecycle.Transition(snapshot, "Idle", 1)
			local unknown = CartResetLifecycle.Transition(snapshot, "Teleporting" :: any, 1)

			expect(repeated).to.equal(nil)
			expect(backward).to.equal(nil)
			expect(unknown).to.equal(nil)
		end)

		it("rejects non-finite and backwards transition times", function()
			local snapshot = transition(CartResetLifecycle.Create(1), "HoldStarted", 2)

			local nanResult = CartResetLifecycle.Transition(snapshot, "HoldComplete", 0 / 0)
			local infinityResult =
				CartResetLifecycle.Transition(snapshot, "HoldComplete", math.huge)
			local backwardsResult = CartResetLifecycle.Transition(snapshot, "HoldComplete", 1)

			expect(nanResult).to.equal(nil)
			expect(infinityResult).to.equal(nil)
			expect(backwardsResult).to.equal(nil)
		end)

		it("rejects non-finite lifecycle creation times", function()
			expect(function()
				CartResetLifecycle.Create(0 / 0)
			end).to.throw()
			expect(function()
				CartResetLifecycle.Create(math.huge)
			end).to.throw()
		end)

		it("rejects malformed runtime snapshots without mutating them", function()
			local malformedCurrent = table.freeze({
				CurrentState = "Teleporting",
				PreviousState = "Idle",
				StateEnteredAt = 0,
				Revision = 0,
			})
			local malformedPrevious = table.freeze({
				CurrentState = "Idle",
				PreviousState = "Teleporting",
				StateEnteredAt = 0,
				Revision = 0,
			})
			local malformedRevision = table.freeze({
				CurrentState = "Idle",
				PreviousState = "Idle",
				StateEnteredAt = 0,
				Revision = 0 / 0,
			})
			local malformedTime = table.freeze({
				CurrentState = "Idle",
				PreviousState = "Idle",
				StateEnteredAt = 0 / 0,
				Revision = 0,
			})

			local currentResult =
				CartResetLifecycle.Transition(malformedCurrent :: any, "HoldStarted", 1)
			local previousResult =
				CartResetLifecycle.Transition(malformedPrevious :: any, "HoldStarted", 1)
			local revisionResult =
				CartResetLifecycle.Transition(malformedRevision :: any, "HoldStarted", 1)
			local timeResult = CartResetLifecycle.Transition(malformedTime :: any, "HoldStarted", 1)

			expect(currentResult).to.equal(nil)
			expect(previousResult).to.equal(nil)
			expect(revisionResult).to.equal(nil)
			expect(timeResult).to.equal(nil)
			expect((malformedPrevious :: any).PreviousState).to.equal("Teleporting")
		end)

		it("uses stable frozen replication attribute names", function()
			expect(CartResetLifecycle.Attributes.Active).to.equal("ResetActive")
			expect(CartResetLifecycle.Attributes.StartedAt).to.equal("ResetStartedAt")
			expect(CartResetLifecycle.Attributes.CompletedAt).to.equal("ResetCompletedAt")
			expect(table.isfrozen(CartResetLifecycle.Attributes)).to.equal(true)
		end)

		it("marks only validation through resume as execution-active", function()
			for _, state in { "Validation", "Suspension", "Reposition", "Recovery", "Resume" } do
				expect(CartResetLifecycle.IsExecutionActive(state)).to.equal(true)
			end

			for _, state in { "Idle", "HoldStarted", "HoldComplete", "Cancelled", "Failed" } do
				expect(CartResetLifecycle.IsExecutionActive(state)).to.equal(false)
			end
		end)

		it("is deterministic for equivalent transition sequences", function()
			local first = CartResetLifecycle.Create(0)
			local second = CartResetLifecycle.Create(0)

			for index, state in
				{
					"HoldStarted",
					"HoldComplete",
					"Validation",
					"Suspension",
					"Reposition",
					"Recovery",
					"Resume",
					"Idle",
				}
			do
				first = transition(first, state, index)
				second = transition(second, state, index)
			end

			expect(first.CurrentState).to.equal(second.CurrentState)
			expect(first.PreviousState).to.equal(second.PreviousState)
			expect(first.StateEnteredAt).to.equal(second.StateEnteredAt)
			expect(first.Revision).to.equal(second.Revision)
		end)
	end)
end
