--!strict

return function()
	local StarterPlayer = game:GetService("StarterPlayer")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local clientRoot = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
	local stateModule = clientRoot:WaitForChild("Utility"):WaitForChild("CartGamepadInputState")
	local CartGamepadInputState = require(stateModule :: ModuleScript)
	local CartReset = require(ReplicatedStorage.Shared.Config.CartReset)
	local CartResetHold = require(ReplicatedStorage.Shared.Utility.CartResetHold)

	local function validContext(): any
		return {
			ControllerStarted = true,
			PlayerActive = true,
			CharacterValid = true,
			CartAvailable = true,
			CartReady = true,
			AuthorizedDriver = true,
			ResetSuspended = false,
			GamepadConnected = true,
			GamepadDeviceActive = true,
			InputSuppressed = false,
		}
	end

	describe("CartGamepadInputState", function()
		it("starts inactive, neutral, and immutable", function()
			local snapshot = CartGamepadInputState.Create()

			expect(snapshot.Active).to.equal(false)
			expect(snapshot.LongitudinalIntent).to.equal(0)
			expect(snapshot.SteeringIntent).to.equal(0)
			expect(snapshot.CameraIntent).to.equal(Vector2.zero)
			expect(snapshot.ResetHeld).to.equal(false)
			expect(table.isfrozen(snapshot)).to.equal(true)
		end)

		it("requires every authoritative activation condition", function()
			local context = validContext()

			expect(CartGamepadInputState.CanActivate(context)).to.equal(true)

			for _, field in
				{
					"ControllerStarted",
					"PlayerActive",
					"CharacterValid",
					"CartAvailable",
					"CartReady",
					"AuthorizedDriver",
					"GamepadConnected",
					"GamepadDeviceActive",
				}
			do
				local rejected = table.clone(context)

				rejected[field] = false
				expect(CartGamepadInputState.CanActivate(rejected)).to.equal(false)
			end

			local reset = table.clone(context)
			local suppressed = table.clone(context)

			reset.ResetSuspended = true
			suppressed.InputSuppressed = true
			expect(CartGamepadInputState.CanActivate(reset)).to.equal(false)
			expect(CartGamepadInputState.CanActivate(suppressed)).to.equal(false)
		end)

		it("rejects processed, suppressed, or inactive input", function()
			local inactive = CartGamepadInputState.Create()
			local active = CartGamepadInputState.Activate(inactive)

			expect(CartGamepadInputState.CanProcessInput(inactive, false, false)).to.equal(false)
			expect(CartGamepadInputState.CanProcessInput(active, true, false)).to.equal(false)
			expect(CartGamepadInputState.CanProcessInput(active, false, true)).to.equal(false)
			expect(CartGamepadInputState.CanProcessInput(active, false, false)).to.equal(true)
		end)

		it("activates neutral and publishes processed analogue movement intent", function()
			local snapshot = CartGamepadInputState.Activate(CartGamepadInputState.Create())
			local contextRevision = snapshot.ContextRevision
			local nextSnapshot, changed, updateError =
				CartGamepadInputState.SetMovementIntent(snapshot, -0.75, 0.4, contextRevision)

			expect(changed).to.equal(true)
			expect(updateError).to.equal(nil)
			expect(nextSnapshot.LongitudinalIntent).to.equal(-0.75)
			expect(nextSnapshot.SteeringIntent).to.equal(0.4)
			expect(nextSnapshot.CameraIntent).to.equal(Vector2.zero)
		end)

		it("publishes camera and reset intent without changing movement intent", function()
			local snapshot = CartGamepadInputState.Activate(CartGamepadInputState.Create())
			local contextRevision = snapshot.ContextRevision

			snapshot = CartGamepadInputState.SetMovementIntent(snapshot, 1, -0.5, contextRevision)
			snapshot = CartGamepadInputState.SetCameraIntent(
				snapshot,
				Vector2.new(0.25, -0.75),
				contextRevision
			)
			local resetSnapshot, changed =
				CartGamepadInputState.SetResetHeld(snapshot, true, contextRevision)

			expect(changed).to.equal(true)
			expect(resetSnapshot.LongitudinalIntent).to.equal(1)
			expect(resetSnapshot.SteeringIntent).to.equal(-0.5)
			expect(resetSnapshot.CameraIntent).to.equal(Vector2.new(0.25, -0.75))
			expect(resetSnapshot.ResetHeld).to.equal(true)
		end)

		it("rejects non-finite or out-of-range processed intent", function()
			local snapshot = CartGamepadInputState.Activate(CartGamepadInputState.Create())
			local contextRevision = snapshot.ContextRevision
			local movement, movementChanged, movementError =
				CartGamepadInputState.SetMovementIntent(snapshot, 0 / 0, 2, contextRevision)
			local camera, cameraChanged, cameraError = CartGamepadInputState.SetCameraIntent(
				snapshot,
				Vector2.new(math.huge, 0),
				contextRevision
			)

			expect(movement).to.equal(snapshot)
			expect(movementChanged).to.equal(false)
			expect(type(movementError)).to.equal("string")
			expect(camera).to.equal(snapshot)
			expect(cameraChanged).to.equal(false)
			expect(type(cameraError)).to.equal("string")
		end)

		it("ignores duplicate and stale-context updates", function()
			local first = CartGamepadInputState.Activate(CartGamepadInputState.Create())
			local firstRevision = first.ContextRevision
			local moved = CartGamepadInputState.SetMovementIntent(first, 0.5, 0, firstRevision)
			local duplicate, duplicateChanged =
				CartGamepadInputState.SetMovementIntent(moved, 0.5, 0, firstRevision)
			local replacement =
				CartGamepadInputState.Activate(CartGamepadInputState.Deactivate(moved))
			local stale, staleChanged =
				CartGamepadInputState.SetCameraIntent(replacement, Vector2.xAxis, firstRevision)

			expect(duplicate).to.equal(moved)
			expect(duplicateChanged).to.equal(false)
			expect(stale).to.equal(replacement)
			expect(staleChanged).to.equal(false)
		end)

		it("clears all processed intent while retaining the active context", function()
			local snapshot = CartGamepadInputState.Activate(CartGamepadInputState.Create())
			local contextRevision = snapshot.ContextRevision

			snapshot = CartGamepadInputState.SetMovementIntent(snapshot, 1, -1, contextRevision)
			snapshot =
				CartGamepadInputState.SetCameraIntent(snapshot, Vector2.new(1, 1), contextRevision)
			snapshot = CartGamepadInputState.SetResetHeld(snapshot, true, contextRevision)

			local cleared, changed = CartGamepadInputState.Clear(snapshot)

			expect(changed).to.equal(true)
			expect(cleared.Active).to.equal(true)
			expect(cleared.ContextRevision).to.equal(contextRevision)
			expect(cleared.LongitudinalIntent).to.equal(0)
			expect(cleared.SteeringIntent).to.equal(0)
			expect(cleared.CameraIntent).to.equal(Vector2.zero)
			expect(cleared.ResetHeld).to.equal(false)
		end)

		it("deactivation neutralises input and invalidates stale callbacks", function()
			local active = CartGamepadInputState.Activate(CartGamepadInputState.Create())
			local contextRevision = active.ContextRevision

			active = CartGamepadInputState.SetMovementIntent(active, -1, 1, contextRevision)
			active = CartGamepadInputState.SetCameraIntent(active, Vector2.xAxis, contextRevision)
			active = CartGamepadInputState.SetResetHeld(active, true, contextRevision)

			local inactive = CartGamepadInputState.Deactivate(active)

			expect(inactive.Active).to.equal(false)
			expect(inactive.ContextRevision > contextRevision).to.equal(true)
			expect(inactive.LongitudinalIntent).to.equal(0)
			expect(inactive.SteeringIntent).to.equal(0)
			expect(inactive.CameraIntent).to.equal(Vector2.zero)
			expect(inactive.ResetHeld).to.equal(false)
		end)

		it("publishes one reset press until release rearms the shared one-second hold", function()
			local snapshot = CartGamepadInputState.Activate(CartGamepadInputState.Create())
			local contextRevision = snapshot.ContextRevision
			local pressed, pressedChanged =
				CartGamepadInputState.SetResetHeld(snapshot, true, contextRevision)
			local duplicate, duplicateChanged =
				CartGamepadInputState.SetResetHeld(pressed, true, contextRevision)
			local hold = CartResetHold.Create()

			hold = CartResetHold.Begin(hold)
			local completedHold, completed =
				CartResetHold.Advance(hold, CartReset.HoldDuration, CartReset.HoldDuration)
			local released, releasedChanged =
				CartGamepadInputState.SetResetHeld(duplicate, false, contextRevision)
			local rearmed, rearmedChanged =
				CartGamepadInputState.SetResetHeld(released, true, contextRevision)

			expect(pressedChanged).to.equal(true)
			expect(duplicateChanged).to.equal(false)
			expect(completed).to.equal(true)
			expect((completedHold :: any).State).to.equal("Complete")
			expect(releasedChanged).to.equal(true)
			expect(rearmedChanged).to.equal(true)
			expect(rearmed.ResetHeld).to.equal(true)
		end)
	end)
end
