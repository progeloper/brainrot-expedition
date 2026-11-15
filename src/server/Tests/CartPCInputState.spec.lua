--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local StarterPlayer = game:GetService("StarterPlayer")

	local CartResetHold = require(ReplicatedStorage.Shared.Utility.CartResetHold)
	local clientRoot = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
	local stateModule = clientRoot:WaitForChild("Utility"):WaitForChild("CartPCInputState")
	local CartPCInputState = require(stateModule :: ModuleScript)

	local function validContext(): any
		return {
			ControllerStarted = true,
			PlayerActive = true,
			CharacterValid = true,
			CartAvailable = true,
			CartReady = true,
			AuthorizedDriver = true,
			ResetSuspended = false,
			KeyboardEnabled = true,
			InputSuppressed = false,
		}
	end

	describe("CartPCInputState", function()
		it("supports ten enter-drive-stop-resume-exit cycles without retained keys", function()
			local snapshot = CartPCInputState.Create()
			for _ = 1, 10 do
				snapshot = CartPCInputState.Activate(snapshot)
				local revision = snapshot.ContextRevision
				snapshot = CartPCInputState.SetKey(snapshot, "W", true, revision)
				expect(snapshot.LongitudinalIntent).to.equal(1)
				snapshot = CartPCInputState.SetKey(snapshot, "W", false, revision)
				expect(snapshot.LongitudinalIntent).to.equal(0)
				snapshot = CartPCInputState.SetKey(snapshot, "W", true, revision)
				expect(snapshot.LongitudinalIntent).to.equal(1)
				snapshot = CartPCInputState.Deactivate(snapshot)
				expect(snapshot.LongitudinalIntent).to.equal(0)
				snapshot = CartPCInputState.SetKey(snapshot, "W", true, revision)
				expect(snapshot.LongitudinalIntent).to.equal(0)
			end
		end)
		it("starts inactive and neutral", function()
			local snapshot = CartPCInputState.Create()

			expect(snapshot.Active).to.equal(false)
			expect(snapshot.LongitudinalIntent).to.equal(0)
			expect(snapshot.SteeringIntent).to.equal(0)
			expect(snapshot.ResetHeld).to.equal(false)
			expect(table.isfrozen(snapshot)).to.equal(true)
		end)

		it("requires every authoritative activation condition", function()
			local context = validContext()

			expect(CartPCInputState.CanActivate(context)).to.equal(true)

			for _, field in
				{
					"ControllerStarted",
					"PlayerActive",
					"CharacterValid",
					"CartAvailable",
					"CartReady",
					"AuthorizedDriver",
					"KeyboardEnabled",
				}
			do
				local rejectedContext = table.clone(context)

				rejectedContext[field] = false
				expect(CartPCInputState.CanActivate(rejectedContext)).to.equal(false)
			end

			local resetContext = table.clone(context)

			resetContext.ResetSuspended = true
			expect(CartPCInputState.CanActivate(resetContext)).to.equal(false)

			local suppressedContext = table.clone(context)

			suppressedContext.InputSuppressed = true
			expect(CartPCInputState.CanActivate(suppressedContext)).to.equal(false)
		end)

		it("rejects processed or suppressed gameplay input", function()
			local inactive = CartPCInputState.Create()
			local active = CartPCInputState.Activate(inactive)

			expect(CartPCInputState.CanProcessInput(inactive, false, false)).to.equal(false)
			expect(CartPCInputState.CanProcessInput(active, true, false)).to.equal(false)
			expect(CartPCInputState.CanProcessInput(active, false, true)).to.equal(false)
			expect(CartPCInputState.CanProcessInput(active, false, false)).to.equal(true)
		end)

		it("resolves W and S as deterministic longitudinal intent", function()
			local snapshot = CartPCInputState.Activate(CartPCInputState.Create())
			local contextRevision = snapshot.ContextRevision

			snapshot = CartPCInputState.SetKey(snapshot, "W", true, contextRevision)
			expect(snapshot.LongitudinalIntent).to.equal(1)

			snapshot = CartPCInputState.SetKey(snapshot, "S", true, contextRevision)
			expect(snapshot.LongitudinalIntent).to.equal(0)

			snapshot = CartPCInputState.SetKey(snapshot, "W", false, contextRevision)
			expect(snapshot.LongitudinalIntent).to.equal(-1)

			snapshot = CartPCInputState.SetKey(snapshot, "S", false, contextRevision)
			expect(snapshot.LongitudinalIntent).to.equal(0)
		end)

		it("resolves A and D as deterministic steering intent", function()
			local snapshot = CartPCInputState.Activate(CartPCInputState.Create())
			local contextRevision = snapshot.ContextRevision

			snapshot = CartPCInputState.SetKey(snapshot, "A", true, contextRevision)
			expect(snapshot.SteeringIntent).to.equal(-1)

			snapshot = CartPCInputState.SetKey(snapshot, "D", true, contextRevision)
			expect(snapshot.SteeringIntent).to.equal(0)

			snapshot = CartPCInputState.SetKey(snapshot, "A", false, contextRevision)
			expect(snapshot.SteeringIntent).to.equal(1)

			snapshot = CartPCInputState.SetKey(snapshot, "D", false, contextRevision)
			expect(snapshot.SteeringIntent).to.equal(0)
		end)

		it("keeps longitudinal and steering axes independent", function()
			local snapshot = CartPCInputState.Activate(CartPCInputState.Create())
			local contextRevision = snapshot.ContextRevision

			snapshot = CartPCInputState.SetKey(snapshot, "W", true, contextRevision)
			snapshot = CartPCInputState.SetKey(snapshot, "A", true, contextRevision)

			expect(snapshot.LongitudinalIntent).to.equal(1)
			expect(snapshot.SteeringIntent).to.equal(-1)

			snapshot = CartPCInputState.SetKey(snapshot, "W", false, contextRevision)
			expect(snapshot.LongitudinalIntent).to.equal(0)
			expect(snapshot.SteeringIntent).to.equal(-1)
		end)

		it("ignores input while inactive and rejects stale context transitions", function()
			local initial = CartPCInputState.Create()
			local ignored, inactiveChanged = CartPCInputState.SetKey(initial, "W", true, 0)

			expect(ignored).to.equal(initial)
			expect(inactiveChanged).to.equal(false)

			local firstContext = CartPCInputState.Activate(initial)
			local staleContextRevision = firstContext.ContextRevision
			local inactive = CartPCInputState.Deactivate(firstContext)
			local replacementContext = CartPCInputState.Activate(inactive)
			local stale, staleChanged =
				CartPCInputState.SetKey(replacementContext, "W", true, staleContextRevision)

			expect(stale).to.equal(replacementContext)
			expect(staleChanged).to.equal(false)
			expect(stale.LongitudinalIntent).to.equal(0)
		end)

		it("clears all held input without forcing the context inactive", function()
			local snapshot = CartPCInputState.Activate(CartPCInputState.Create())
			local contextRevision = snapshot.ContextRevision

			for _, key in { "W", "A", "R" } do
				snapshot = CartPCInputState.SetKey(snapshot, key, true, contextRevision)
			end

			local cleared, changed = CartPCInputState.Clear(snapshot)

			expect(changed).to.equal(true)
			expect(cleared.Active).to.equal(true)
			expect(cleared.LongitudinalIntent).to.equal(0)
			expect(cleared.SteeringIntent).to.equal(0)
			expect(cleared.ResetHeld).to.equal(false)
		end)

		it("deactivation clears input and invalidates the previous context", function()
			local snapshot = CartPCInputState.Activate(CartPCInputState.Create())
			local activeContextRevision = snapshot.ContextRevision

			snapshot = CartPCInputState.SetKey(snapshot, "S", true, activeContextRevision)
			snapshot = CartPCInputState.SetKey(snapshot, "D", true, activeContextRevision)
			snapshot = CartPCInputState.SetKey(snapshot, "R", true, activeContextRevision)

			local inactive = CartPCInputState.Deactivate(snapshot)

			expect(inactive.Active).to.equal(false)
			expect(inactive.ContextRevision > activeContextRevision).to.equal(true)
			expect(inactive.LongitudinalIntent).to.equal(0)
			expect(inactive.SteeringIntent).to.equal(0)
			expect(inactive.ResetHeld).to.equal(false)
		end)

		it("supports one reset completion per continuous R press", function()
			local snapshot = CartPCInputState.Activate(CartPCInputState.Create())
			local contextRevision = snapshot.ContextRevision
			local requestCount = 0
			local payloadCount = -1
			local hold = CartResetHold.Create()

			local function submitReset(...: any)
				requestCount += 1
				payloadCount = select("#", ...)
			end

			snapshot = CartPCInputState.SetKey(snapshot, "R", true, contextRevision)
			hold = CartResetHold.Begin(hold) :: any

			local completedHold, completed = CartResetHold.Advance(hold, 1, 1)

			hold = completedHold :: any

			if completed then
				submitReset()
			end

			local repeatedHold, repeatedCompletion = CartResetHold.Advance(hold, 10, 1)

			hold = repeatedHold :: any

			if repeatedCompletion then
				submitReset()
			end

			expect(requestCount).to.equal(1)
			expect(payloadCount).to.equal(0)

			snapshot = CartPCInputState.SetKey(snapshot, "R", false, contextRevision)
			hold = CartResetHold.Release(hold) :: any
			expect(snapshot.ResetHeld).to.equal(false)
			expect(hold.State).to.equal("Idle")
		end)

		it("cancels reset hold on early release or authority loss", function()
			local snapshot = CartPCInputState.Activate(CartPCInputState.Create())
			local contextRevision = snapshot.ContextRevision
			local hold = CartResetHold.Create()

			snapshot = CartPCInputState.SetKey(snapshot, "R", true, contextRevision)
			hold = CartResetHold.Begin(hold) :: any
			hold = CartResetHold.Advance(hold, 0.5, 1) :: any
			snapshot = CartPCInputState.SetKey(snapshot, "R", false, contextRevision)

			local released, cancelled = CartResetHold.Release(hold)

			expect(snapshot.ResetHeld).to.equal(false)
			expect(cancelled).to.equal(true)
			expect((released :: any).State).to.equal("Idle")

			snapshot = CartPCInputState.SetKey(snapshot, "R", true, contextRevision)
			snapshot = CartPCInputState.Deactivate(snapshot)
			expect(snapshot.ResetHeld).to.equal(false)
		end)

		it("returns the same snapshot for duplicate key transitions", function()
			local snapshot = CartPCInputState.Activate(CartPCInputState.Create())
			local contextRevision = snapshot.ContextRevision
			local pressed = CartPCInputState.SetKey(snapshot, "W", true, contextRevision)
			local duplicate, changed = CartPCInputState.SetKey(pressed, "W", true, contextRevision)

			expect(duplicate).to.equal(pressed)
			expect(changed).to.equal(false)
		end)
	end)
end
