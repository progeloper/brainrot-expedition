--!strict

return function()
	local StarterPlayer = game:GetService("StarterPlayer")
	local clientRoot = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
	local controllerModule =
		clientRoot:WaitForChild("Controllers"):WaitForChild("CartInputController")
	local CartInputController = require(controllerModule :: ModuleScript)

	-- Published axes pass through a Vector2 (single precision) in the arcade adapter.
	local function expectAxis(actual: number, expected: number)
		expect(math.abs(actual - expected) <= 1e-6).to.equal(true)
	end

	local function resetControllerState()
		CartInputController.SetGamepadCameraOrbitEnabled(false)
		CartInputController.SetResetEnabled(false)
		CartInputController.ClearGamepadInput()
		CartInputController.SetKeyboardResetHeld(false)
		CartInputController.SetInputDevice("KeyboardMouse")
		CartInputController.ClearMovementInput()
		-- Arcade contract: clearing movement requires a fresh gesture. One neutral
		-- poll releases that gate so the next intent a test sets is published.
		CartInputController.GetState()
	end

	describe("CartInputController Phase 1L boundary", function()
		it("publishes normalized forward, reverse/brake, steering, and neutral intent", function()
			resetControllerState()

			expect(CartInputController.SetKeyboardMovementIntent(1, -1)).to.equal(true)
			local forwardLeft = CartInputController.GetState()

			expect(forwardLeft.Throttle).to.equal(1)
			expect(forwardLeft.Steering).to.equal(-1)
			expect(forwardLeft.Brake).to.equal(false)

			expect(CartInputController.SetKeyboardMovementIntent(-1, 1)).to.equal(true)
			local reverseRight = CartInputController.GetState()

			-- Arcade contract: Brake reports a neutral stick. A backward gesture is
			-- camera-relative movement intent, not a brake.
			expect(reverseRight.Throttle).to.equal(-1)
			expect(reverseRight.Steering).to.equal(1)
			expect(reverseRight.Brake).to.equal(false)

			expect(CartInputController.SetKeyboardMovementIntent(0, 0)).to.equal(true)
			local neutral = CartInputController.GetState()

			expect(neutral.Throttle).to.equal(0)
			expect(neutral.Steering).to.equal(0)
			expect(neutral.Brake).to.equal(true)
		end)

		it("does not publish duplicate intent changes", function()
			resetControllerState()

			expect(CartInputController.SetKeyboardMovementIntent(1, 0)).to.equal(true)
			expect(CartInputController.SetKeyboardMovementIntent(1, 0)).to.equal(false)
		end)

		it("rejects non-normalized intent", function()
			resetControllerState()

			expect(CartInputController.SetKeyboardMovementIntent(0.5, 0)).to.equal(false)
			expect(CartInputController.SetKeyboardMovementIntent(0, math.huge)).to.equal(false)
			expect(CartInputController.GetState().Throttle).to.equal(0)
			expect(CartInputController.GetState().Steering).to.equal(0)
		end)

		it("clears movement intent without changing physical state", function()
			resetControllerState()
			CartInputController.SetKeyboardMovementIntent(-1, -1)

			CartInputController.ClearMovementInput()

			local neutral = CartInputController.GetState()

			expect(neutral.Throttle).to.equal(0)
			expect(neutral.Steering).to.equal(0)
			expect(neutral.Brake).to.equal(true)

			-- A still-held intent stays suppressed until the input returns to neutral.
			CartInputController.ClearMovementInput()
			CartInputController.SetKeyboardMovementIntent(1, 0)
			expect(CartInputController.GetState().Throttle).to.equal(0)
			CartInputController.SetKeyboardMovementIntent(0, 0)
			CartInputController.GetState()
			CartInputController.SetKeyboardMovementIntent(1, 0)
			expect(CartInputController.GetState().Throttle).to.equal(1)
			resetControllerState()
		end)

		it("clears only the keyboard movement source through the PC boundary", function()
			resetControllerState()
			CartInputController.SetKeyboardMovementIntent(1, 1)

			expect(CartInputController.ClearKeyboardMovementInput()).to.equal(true)
			expect(CartInputController.ClearKeyboardMovementInput()).to.equal(false)
			expect(CartInputController.GetState().Throttle).to.equal(0)
			expect(CartInputController.GetState().Steering).to.equal(0)
		end)

		it("publishes keyboard reset transitions only while reset input is enabled", function()
			resetControllerState()
			local transitionCount = 0
			local lastHeld = false
			local connection = CartInputController.ResetHeldChanged:Connect(function(held)
				transitionCount += 1
				lastHeld = held
			end)

			expect(CartInputController.SetKeyboardResetHeld(true)).to.equal(false)
			expect(transitionCount).to.equal(0)

			CartInputController.SetResetEnabled(true)
			expect(CartInputController.SetKeyboardResetHeld(true)).to.equal(true)
			expect(lastHeld).to.equal(true)
			expect(CartInputController.SetKeyboardResetHeld(true)).to.equal(false)
			expect(transitionCount).to.equal(1)

			expect(CartInputController.SetKeyboardResetHeld(false)).to.equal(true)
			expect(lastHeld).to.equal(false)
			expect(transitionCount).to.equal(2)

			connection:Disconnect()
			resetControllerState()
		end)

		it("keeps PC camera orbit state separate from movement and reset intent", function()
			resetControllerState()
			CartInputController.SetKeyboardMovementIntent(1, -1)

			CartInputController.SetPCCameraOrbitEnabled(true)
			expect(CartInputController.ConsumePCCameraOrbit()).to.equal(Vector2.zero)
			CartInputController.SetPCCameraOrbitEnabled(false)

			local state = CartInputController.GetState()

			expect(state.Throttle).to.equal(1)
			expect(state.Steering).to.equal(-1)
			expect(state.ResetHeld).to.equal(false)
			resetControllerState()
		end)
	end)

	describe("CartInputController Phase 1P shared boundary", function()
		it("accepts finite normalized analogue gamepad movement intent", function()
			resetControllerState()

			expect(CartInputController.SetGamepadMovementIntent(0.45, -0.7)).to.equal(true)
			local forwardLeft = CartInputController.GetState()

			expect(forwardLeft.InputDevice).to.equal("Gamepad")
			expectAxis(forwardLeft.Throttle, 0.45)
			expectAxis(forwardLeft.Steering, -0.7)
			expect(forwardLeft.Brake).to.equal(false)
			expect(CartInputController.SetGamepadMovementIntent(-1, 1)).to.equal(true)

			local reverseRight = CartInputController.GetState()

			expect(reverseRight.Throttle).to.equal(-1)
			expect(reverseRight.Steering).to.equal(1)
			expect(reverseRight.Brake).to.equal(false)
			expect(CartInputController.SetGamepadMovementIntent(-1, 1)).to.equal(false)
			resetControllerState()
		end)

		it("rejects malformed or out-of-range analogue gamepad intent", function()
			resetControllerState()
			CartInputController.SetGamepadMovementIntent(0.25, -0.5)

			for _, values in
				{
					{ 0 / 0, 0 },
					{ math.huge, 0 },
					{ 0, -math.huge },
					{ 1.01, 0 },
					{ 0, -1.01 },
				}
			do
				expect(CartInputController.SetGamepadMovementIntent(values[1], values[2])).to.equal(
					false
				)
			end

			local unchanged = CartInputController.GetState()

			expect(unchanged.Throttle).to.equal(0.25)
			expect(unchanged.Steering).to.equal(-0.5)
			resetControllerState()
		end)

		it("publishes device changes and neutralizes the previous source", function()
			resetControllerState()
			local transitions = {}
			local connection = CartInputController.InputDeviceChanged:Connect(
				function(nextDevice, previousDevice)
					table.insert(transitions, { Next = nextDevice, Previous = previousDevice })
				end
			)

			CartInputController.SetResetEnabled(true)
			CartInputController.SetGamepadCameraOrbitEnabled(true)
			CartInputController.SetGamepadMovementIntent(0.75, -0.25)
			CartInputController.SetGamepadCameraIntent(0.4, -0.3)
			CartInputController.SetGamepadResetHeld(true)

			expect(#transitions).to.equal(1)
			expect(transitions[1].Previous).to.equal("KeyboardMouse")
			expect(transitions[1].Next).to.equal("Gamepad")
			expect(CartInputController.SetInputDevice("Gamepad")).to.equal(false)

			CartInputController.SetKeyboardMovementIntent(1, 0)

			local keyboard = CartInputController.GetState()

			expect(#transitions).to.equal(2)
			expect(transitions[2].Previous).to.equal("Gamepad")
			expect(transitions[2].Next).to.equal("KeyboardMouse")
			expect(keyboard.Throttle).to.equal(1)
			expect(keyboard.Steering).to.equal(0)
			expect(keyboard.ResetHeld).to.equal(false)
			expect(CartInputController.GetGamepadCameraIntent()).to.equal(Vector2.zero)

			connection:Disconnect()
			resetControllerState()
		end)

		it("keeps gamepad movement, camera, and reset sources independently clearable", function()
			resetControllerState()
			CartInputController.SetResetEnabled(true)
			CartInputController.SetGamepadCameraOrbitEnabled(true)
			CartInputController.SetGamepadMovementIntent(0.6, 0.2)

			expect(CartInputController.SetGamepadCameraIntent(-0.4, 0.3)).to.equal(true)
			expect(CartInputController.SetGamepadResetHeld(true)).to.equal(true)

			local combined = CartInputController.GetState()

			expectAxis(combined.Throttle, 0.6)
			expectAxis(combined.Steering, 0.2)
			expect(combined.ResetHeld).to.equal(true)
			expect(CartInputController.GetGamepadCameraIntent()).to.equal(Vector2.new(-0.4, 0.3))
			expect(CartInputController.ClearGamepadCameraIntent()).to.equal(true)
			expectAxis(CartInputController.GetState().Throttle, 0.6)
			expect(CartInputController.IsResetHeld()).to.equal(true)
			expect(CartInputController.ClearGamepadInput()).to.equal(true)

			local neutral = CartInputController.GetState()

			expect(neutral.Throttle).to.equal(0)
			expect(neutral.Steering).to.equal(0)
			expect(neutral.ResetHeld).to.equal(false)
			expect(CartInputController.GetGamepadCameraIntent()).to.equal(Vector2.zero)
			resetControllerState()
		end)

		it("caches camera intent across camera handoff but rejects malformed values", function()
			resetControllerState()

			expect(CartInputController.SetGamepadCameraIntent(0.5, 0)).to.equal(true)
			expect(CartInputController.GetGamepadCameraIntent()).to.equal(Vector2.zero)
			CartInputController.SetGamepadCameraOrbitEnabled(true)
			expect(CartInputController.GetGamepadCameraIntent()).to.equal(Vector2.new(0.5, 0))
			CartInputController.SetGamepadCameraOrbitEnabled(false)
			expect(CartInputController.GetGamepadCameraIntent()).to.equal(Vector2.zero)
			CartInputController.SetGamepadCameraOrbitEnabled(true)
			expect(CartInputController.GetGamepadCameraIntent()).to.equal(Vector2.new(0.5, 0))
			CartInputController.ClearGamepadCameraIntent()
			expect(CartInputController.SetGamepadCameraIntent(0 / 0, 0)).to.equal(false)
			expect(CartInputController.SetGamepadCameraIntent(0, math.huge)).to.equal(false)
			expect(CartInputController.SetGamepadCameraIntent(-1.01, 0)).to.equal(false)
			expect(CartInputController.GetGamepadCameraIntent()).to.equal(Vector2.zero)
			resetControllerState()
		end)
	end)
end
