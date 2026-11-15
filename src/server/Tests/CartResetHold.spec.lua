--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartResetHold = require(ReplicatedStorage.Shared.Utility.CartResetHold)

	describe("CartResetHold", function()
		it("requires one continuous second and completes exactly once", function()
			local snapshot = CartResetHold.Create()
			local started, startError = CartResetHold.Begin(snapshot)

			expect(startError).to.equal(nil)
			snapshot = started :: any

			local half, halfCompleted, halfError = CartResetHold.Advance(snapshot, 0.5, 1)

			expect(halfError).to.equal(nil)
			expect(halfCompleted).to.equal(false)
			snapshot = half :: any
			expect(snapshot.State).to.equal("Holding")
			expect(snapshot.Elapsed).to.equal(0.5)

			local complete, completed, completeError = CartResetHold.Advance(snapshot, 0.5, 1)

			expect(completeError).to.equal(nil)
			expect(completed).to.equal(true)
			snapshot = complete :: any
			expect(snapshot.State).to.equal("Complete")
			expect(snapshot.Elapsed).to.equal(1)

			local repeated, repeatedCompletion = CartResetHold.Advance(snapshot, 10, 1)

			expect(repeated).to.equal(snapshot)
			expect(repeatedCompletion).to.equal(false)
		end)

		it("cancels an early release and restarts elapsed time from zero", function()
			local snapshot = CartResetHold.Begin(CartResetHold.Create()) :: any

			snapshot = CartResetHold.Advance(snapshot, 0.75, 1) :: any

			local released, cancelled, releaseError = CartResetHold.Release(snapshot)

			expect(releaseError).to.equal(nil)
			expect(cancelled).to.equal(true)
			snapshot = released :: any
			expect(snapshot.State).to.equal("Idle")
			expect(snapshot.Elapsed).to.equal(0)

			snapshot = CartResetHold.Begin(snapshot) :: any
			expect(snapshot.State).to.equal("Holding")
			expect(snapshot.Elapsed).to.equal(0)
		end)

		it("rearmer release after completion is not reported as cancellation", function()
			local snapshot = CartResetHold.Begin(CartResetHold.Create()) :: any

			snapshot = CartResetHold.Advance(snapshot, 1, 1) :: any

			local released, cancelled = CartResetHold.Release(snapshot)

			expect(cancelled).to.equal(false)
			expect((released :: any).State).to.equal("Idle")
		end)

		it("rejects a second begin until release rearms the hold", function()
			local holding = CartResetHold.Begin(CartResetHold.Create()) :: any
			local complete = CartResetHold.Advance(holding, 1, 1) :: any

			expect(CartResetHold.Begin(holding)).to.equal(nil)
			expect(CartResetHold.Begin(complete)).to.equal(nil)
		end)

		it("keeps an idle release idle without reporting cancellation", function()
			local released, cancelled, releaseError = CartResetHold.Release(CartResetHold.Create())

			expect(releaseError).to.equal(nil)
			expect(cancelled).to.equal(false)
			expect((released :: any).State).to.equal("Idle")
			expect((released :: any).Elapsed).to.equal(0)
		end)

		it("clamps overshoot and is deterministic for equivalent elapsed time", function()
			local started = CartResetHold.Begin(CartResetHold.Create()) :: any
			local overshoot, overshootCompleted = CartResetHold.Advance(started, 2, 1)
			local split = CartResetHold.Advance(started, 0.4, 1) :: any
			local splitComplete, splitCompleted = CartResetHold.Advance(split, 0.6, 1)

			expect(overshootCompleted).to.equal(true)
			expect((overshoot :: any).Elapsed).to.equal(1)
			expect((overshoot :: any).State).to.equal("Complete")
			expect(splitCompleted).to.equal(true)
			expect((splitComplete :: any).Elapsed).to.equal(1)
			expect((splitComplete :: any).State).to.equal("Complete")
		end)

		it("rejects negative and non-finite timing values", function()
			local snapshot = CartResetHold.Begin(CartResetHold.Create()) :: any

			local negative = CartResetHold.Advance(snapshot, -0.1, 1)
			local nan = CartResetHold.Advance(snapshot, 0 / 0, 1)
			local infinity = CartResetHold.Advance(snapshot, math.huge, 1)
			local zeroDuration = CartResetHold.Advance(snapshot, 0.1, 0)

			expect(negative).to.equal(nil)
			expect(nan).to.equal(nil)
			expect(infinity).to.equal(nil)
			expect(zeroDuration).to.equal(nil)
		end)

		it("rejects malformed hold snapshots", function()
			local badState = table.freeze({
				State = "Broken",
				Elapsed = 0,
				Revision = 0,
			})
			local negativeElapsed = table.freeze({
				State = "Idle",
				Elapsed = -1,
				Revision = 0,
			})
			local nanElapsed = table.freeze({
				State = "Idle",
				Elapsed = 0 / 0,
				Revision = 0,
			})
			local negativeRevision = table.freeze({
				State = "Idle",
				Elapsed = 0,
				Revision = -1,
			})
			local fractionalRevision = table.freeze({
				State = "Idle",
				Elapsed = 0,
				Revision = 0.5,
			})

			expect(CartResetHold.Begin(badState :: any)).to.equal(nil)
			expect(CartResetHold.Begin(negativeElapsed :: any)).to.equal(nil)
			expect(CartResetHold.Begin(nanElapsed :: any)).to.equal(nil)
			expect(CartResetHold.Begin(negativeRevision :: any)).to.equal(nil)
			expect(CartResetHold.Begin(fractionalRevision :: any)).to.equal(nil)
		end)

		it("returns fresh frozen snapshots without mutating prior state", function()
			local idle = CartResetHold.Create()
			local holding = CartResetHold.Begin(idle) :: any
			local advanced = CartResetHold.Advance(holding, 0.25, 1) :: any

			expect(table.isfrozen(idle)).to.equal(true)
			expect(table.isfrozen(holding)).to.equal(true)
			expect(table.isfrozen(advanced)).to.equal(true)
			expect(idle.State).to.equal("Idle")
			expect(idle.Elapsed).to.equal(0)
			expect(holding.State).to.equal("Holding")
			expect(holding.Elapsed).to.equal(0)
			expect(advanced.Elapsed).to.equal(0.25)
		end)
	end)
end
