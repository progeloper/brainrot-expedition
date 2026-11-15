--!strict

return function()
	local CartDriverPolicy = require(script.Parent.Parent.Utility.CartDriverPolicy)

	type PermissionContext = CartDriverPolicy.PermissionContext

	local function createAllowedContext(): PermissionContext
		return {
			FeatureEnabled = true,
			CartRegistered = true,
			CartAlive = true,
			ControlSuspended = false,
			PlayerActive = true,
			CharacterValid = true,
			OccupantMatchesCharacter = true,
			OwnerUserId = 101,
			PlayerUserId = 101,
		}
	end

	describe("CartDriverPolicy", function()
		it("returns no character for an empty seat", function()
			expect(CartDriverPolicy.ResolveCharacter(nil)).to.equal(nil)
		end)

		it("returns no character for an unparented Humanoid", function()
			local humanoid = Instance.new("Humanoid")

			expect(CartDriverPolicy.ResolveCharacter(humanoid)).to.equal(nil)

			humanoid:Destroy()
		end)

		it("returns no character when the Humanoid parent is not a Model", function()
			local container = Instance.new("Folder")
			local humanoid = Instance.new("Humanoid")

			humanoid.Parent = container

			expect(CartDriverPolicy.ResolveCharacter(humanoid)).to.equal(nil)

			container:Destroy()
		end)

		it("resolves the Humanoid's character Model", function()
			local character = Instance.new("Model")
			local humanoid = Instance.new("Humanoid")

			humanoid.Parent = character

			expect(CartDriverPolicy.ResolveCharacter(humanoid)).to.equal(character)

			character:Destroy()
		end)

		it("accepts a fully valid owner-driver context", function()
			local allowed, reason = CartDriverPolicy.Evaluate(createAllowedContext())

			expect(allowed).to.equal(true)
			expect(reason).to.equal("allowed")
		end)

		it("rejects every invalid authority context with a stable reason", function()
			local cases = {
				{
					Field = "FeatureEnabled",
					Value = false,
					Reason = "cart feature is disabled",
				},
				{
					Field = "CartRegistered",
					Value = false,
					Reason = "cart is not registered",
				},
				{
					Field = "CartAlive",
					Value = false,
					Reason = "cart is not active",
				},
				{
					Field = "ControlSuspended",
					Value = true,
					Reason = "cart control is suspended",
				},
				{
					Field = "PlayerActive",
					Value = false,
					Reason = "player is not active",
				},
				{
					Field = "CharacterValid",
					Value = false,
					Reason = "player character is not valid",
				},
				{
					Field = "OccupantMatchesCharacter",
					Value = false,
					Reason = "driver seat occupant does not match the player character",
				},
				{
					Field = "PlayerUserId",
					Value = 202,
					Reason = "player is not the cart owner",
				},
			}

			for _, case in cases do
				local context = createAllowedContext()
				local dynamicContext = context :: any

				dynamicContext[case.Field] = case.Value

				local allowed, reason = CartDriverPolicy.Evaluate(context)

				expect(allowed).to.equal(false)
				expect(reason).to.equal(case.Reason)
			end
		end)

		it("keeps permanent owner identity separate from a rejected active driver", function()
			local context = createAllowedContext()

			context.OwnerUserId = 101
			context.PlayerUserId = 202

			local allowed, reason = CartDriverPolicy.Evaluate(context)

			expect(allowed).to.equal(false)
			expect(reason).to.equal("player is not the cart owner")
			expect(context.OwnerUserId).to.equal(101)
		end)
	end)
end
