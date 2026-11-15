--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartCameraRuntimeState = require(ReplicatedStorage.Shared.Utility.CartCameraRuntimeState)

	local function validContext(): CartCameraRuntimeState.ActivationContext
		return {
			ControllerStarted = true,
			PlayerActive = true,
			AuthorizedDriver = true,
			CartAvailable = true,
			CartReady = true,
			TargetValid = true,
			CameraAvailable = true,
			CameraInputApplicable = true,
		}
	end

	describe("CartCameraRuntimeState", function()
		it("starts inactive and requires every authoritative activation condition", function()
			local snapshot = CartCameraRuntimeState.Create()
			local context = validContext()

			expect(snapshot.Active).to.equal(false)
			expect(CartCameraRuntimeState.CanActivate(context)).to.equal(true)

			for _, field in
				{
					"ControllerStarted",
					"PlayerActive",
					"AuthorizedDriver",
					"CartAvailable",
					"CartReady",
					"TargetValid",
					"CameraAvailable",
					"CameraInputApplicable",
				}
			do
				local rejected = table.clone(context)

				rejected[field] = false
				expect(CartCameraRuntimeState.CanActivate(rejected)).to.equal(false)
			end
		end)

		it("allows reset-time Preparing only for an already-active suspended camera", function()
			expect(CartCameraRuntimeState.IsCartReady("Valid", false, false)).to.equal(true)
			expect(CartCameraRuntimeState.IsCartReady("Preparing", false, true)).to.equal(false)
			expect(CartCameraRuntimeState.IsCartReady("Preparing", true, false)).to.equal(false)
			expect(CartCameraRuntimeState.IsCartReady("Preparing", true, true)).to.equal(true)
			expect(CartCameraRuntimeState.IsCartReady("Invalid", true, true)).to.equal(false)
			expect(CartCameraRuntimeState.IsCartReady("Destroying", true, true)).to.equal(false)
		end)

		it("activates once and invalidates stale context revisions on deactivation", function()
			local initial = CartCameraRuntimeState.Create()
			local active = CartCameraRuntimeState.Activate(initial)
			local duplicate = CartCameraRuntimeState.Activate(active)

			expect(active.Active).to.equal(true)
			expect(active.ResyncRequired).to.equal(true)
			expect(duplicate).to.equal(active)
			expect(CartCameraRuntimeState.IsCurrent(active, active.ContextRevision)).to.equal(true)

			local inactive = CartCameraRuntimeState.Deactivate(active)

			expect(inactive.Active).to.equal(false)
			expect(inactive.ContextRevision > active.ContextRevision).to.equal(true)
			expect(CartCameraRuntimeState.IsCurrent(inactive, active.ContextRevision)).to.equal(
				false
			)
		end)

		it("marks reset transitions for direct follow resynchronisation", function()
			local snapshot = CartCameraRuntimeState.Activate(CartCameraRuntimeState.Create())

			snapshot = CartCameraRuntimeState.ConsumeResync(snapshot)
			expect(snapshot.ResyncRequired).to.equal(false)

			snapshot = CartCameraRuntimeState.SetResetSuspended(snapshot, true)
			expect(snapshot.ResetSuspended).to.equal(true)
			expect(snapshot.ResyncRequired).to.equal(true)
			expect(snapshot.ManualInputActive).to.equal(false)

			snapshot = CartCameraRuntimeState.ConsumeResync(snapshot)
			snapshot = CartCameraRuntimeState.SetResetSuspended(snapshot, false)
			expect(snapshot.ResetSuspended).to.equal(false)
			expect(snapshot.ResyncRequired).to.equal(true)
		end)

		it("clears manual input without discarding the active camera context", function()
			local snapshot = CartCameraRuntimeState.Activate(CartCameraRuntimeState.Create())

			snapshot = CartCameraRuntimeState.SetManualInputActive(snapshot, true)
			expect(snapshot.ManualInputActive).to.equal(true)

			snapshot = CartCameraRuntimeState.ClearManualInput(snapshot)
			expect(snapshot.Active).to.equal(true)
			expect(snapshot.ManualInputActive).to.equal(false)
		end)
	end)
end
