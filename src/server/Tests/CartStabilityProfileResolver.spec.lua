--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Carts = require(ReplicatedStorage.Shared.Config.Carts)
	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartStabilityProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartStabilityProfileResolver)

	local function expectFailure(cartId: any, expectedText: string)
		local success, errorMessage = pcall(function()
			CartStabilityProfileResolver.Resolve(cartId)
		end)

		expect(success).to.equal(false)
		expect(string.find(tostring(errorMessage), expectedText, 1, true) ~= nil).to.equal(true)
	end

	describe("CartStabilityProfileResolver", function()
		it("resolves the exact Scrap Chariot Development stability profile", function()
			local profile = CartStabilityProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local expectedValues = {
				Enabled = true,
				OrientationErrorDeadZoneDegrees = 1,
				FreeRollAngleDegrees = 6,
				FreePitchAngleDegrees = 4,
				ModerateRollAngleDegrees = 18,
				ModeratePitchAngleDegrees = 14,
				StrongRollAngleDegrees = 55,
				StrongPitchAngleDegrees = 45,
				UprightStrength = 1,
				RollCorrectionStrength = 1,
				PitchCorrectionStrength = 0.75,
				RollDamping = 0.42,
				PitchDamping = 0.5,
				MaxCorrectiveTorque = 42000,
				MaxCorrectiveAngularResponseDegreesPerSecond = 120,
				ResponseSpeed = 12,
				StationaryAssistanceMultiplier = 0.85,
				DrivingAssistanceMultiplier = 1,
				SevereTiltRecoveryMultiplier = 1.35,
				ExtremeYawDamping = 0,
				ExtremeYawThresholdDegreesPerSecond = 240,
			}

			expect(profile.CartId).to.equal(Ids.Carts.ScrapChariot)

			for field, expectedValue in expectedValues do
				expect((profile :: any)[field]).to.equal(expectedValue)
			end
		end)

		it("freezes the nested source and a fresh copied result", function()
			local source = Carts[Ids.Carts.ScrapChariot].Stability
			local originalTorque = source.MaxCorrectiveTorque
			local profile = CartStabilityProfileResolver.Resolve(Ids.Carts.ScrapChariot)

			expect((profile :: any) == (source :: any)).to.equal(false)
			expect(table.isfrozen(source)).to.equal(true)
			expect(table.isfrozen(profile)).to.equal(true)

			local sourceMutationSucceeded = pcall(function()
				(source :: any).MaxCorrectiveTorque = 1
			end)
			local resultMutationSucceeded = pcall(function()
				(profile :: any).MaxCorrectiveTorque = 1
			end)

			expect(sourceMutationSucceeded).to.equal(false)
			expect(resultMutationSucceeded).to.equal(false)
			expect(source.MaxCorrectiveTorque).to.equal(originalTorque)
		end)

		it("returns deterministic values in separate snapshots", function()
			local first = CartStabilityProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local second = CartStabilityProfileResolver.Resolve(Ids.Carts.ScrapChariot)

			expect((first :: any) == (second :: any)).to.equal(false)

			for field, firstValue in first :: any do
				expect((second :: any)[field]).to.equal(firstValue)
			end
		end)

		it("rejects unknown, empty, and nonstring CartIds without a fallback", function()
			expectFailure("CRT_UNKNOWN", "no fallback was used")
			expectFailure(Ids.Carts.ReinforcedWagon, "no fallback was used")
			expectFailure("", "non-empty string assigned by the server")
			expectFailure(123, "non-empty string assigned by the server")
		end)

		it("rejects missing CartIds and destroyed runtime carts", function()
			local container = Instance.new("Folder")
			local cart = Instance.new("Model")

			cart.Name = "StabilityTestCart"
			cart.Parent = container

			local missingSuccess, missingError = pcall(function()
				CartStabilityProfileResolver.ResolveForCart(cart)
			end)

			expect(missingSuccess).to.equal(false)
			expect(
				string.find(
					tostring(missingError),
					"non-empty string assigned by the server",
					1,
					true
				) ~= nil
			).to.equal(true)

			cart:SetAttribute("CartId", Ids.Carts.ScrapChariot)
			expect(CartStabilityProfileResolver.ResolveForCart(cart).Enabled).to.equal(true)

			cart:Destroy()

			local destroyedSuccess, destroyedError = pcall(function()
				CartStabilityProfileResolver.ResolveForCart(cart)
			end)

			expect(destroyedSuccess).to.equal(false)
			expect(string.find(tostring(destroyedError), "live runtime cart", 1, true) ~= nil).to.equal(
				true
			)

			container:Destroy()
		end)

		it("resolves a fresh profile for a replacement runtime cart", function()
			local container = Instance.new("Folder")
			local firstCart = Instance.new("Model")
			local replacementCart = Instance.new("Model")

			firstCart:SetAttribute("CartId", Ids.Carts.ScrapChariot)
			replacementCart:SetAttribute("CartId", Ids.Carts.ScrapChariot)
			firstCart.Parent = container
			replacementCart.Parent = container

			local first = CartStabilityProfileResolver.ResolveForCart(firstCart)
			local replacement = CartStabilityProfileResolver.ResolveForCart(replacementCart)

			expect((first :: any) == (replacement :: any)).to.equal(false)
			expect(first.MaxCorrectiveTorque).to.equal(replacement.MaxCorrectiveTorque)

			container:Destroy()
		end)

		it("validates every configured cart profile", function()
			expect(function()
				CartStabilityProfileResolver.ValidateAll()
			end).never.to.throw()
		end)
	end)
end
