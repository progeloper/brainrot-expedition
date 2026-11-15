--!strict

return function()
	local StarterPlayer = game:GetService("StarterPlayer")
	local clientRoot = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
	local stateModule = clientRoot:WaitForChild("State"):WaitForChild("LocalCartResetState")
	local LocalCartResetState = require(stateModule :: ModuleScript)

	describe("LocalCartResetState", function()
		it("does not let a stale request release a newer suspension on the same cart", function()
			local cart = Instance.new("Model")

			LocalCartResetState.SetActive(nil, false)

			local firstRevision = LocalCartResetState.SetActive(cart, true)

			LocalCartResetState.SetActive(cart, false, firstRevision)

			local secondRevision = LocalCartResetState.SetActive(cart, true)

			LocalCartResetState.SetActive(cart, false, firstRevision)
			expect(LocalCartResetState.IsActiveFor(cart)).to.equal(true)

			LocalCartResetState.SetActive(cart, false, secondRevision)
			expect(LocalCartResetState.IsActiveFor(cart)).to.equal(false)

			cart:Destroy()
		end)

		it("publishes only real local suspension transitions", function()
			local cart = Instance.new("Model")
			local transitionCount = 0
			local connection = LocalCartResetState.Changed:Connect(function()
				transitionCount += 1
			end)

			LocalCartResetState.SetActive(nil, false)
			local activeRevision = LocalCartResetState.SetActive(cart, true)

			LocalCartResetState.SetActive(cart, true)
			LocalCartResetState.SetActive(cart, false, activeRevision)

			expect(transitionCount).to.equal(2)
			expect(LocalCartResetState.IsActiveFor(cart)).to.equal(false)

			connection:Disconnect()
			cart:Destroy()
		end)
	end)
end
