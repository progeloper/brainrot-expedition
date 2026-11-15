--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Carts = require(ReplicatedStorage.Shared.Config.Carts)
	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartTerrainProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartTerrainProfileResolver)

	local function expectFailure(cartId: any, expectedText: string)
		local success, errorMessage = pcall(function()
			CartTerrainProfileResolver.Resolve(cartId)
		end)

		expect(success).to.equal(false)
		expect(string.find(tostring(errorMessage), expectedText, 1, true) ~= nil).to.equal(true)
	end

	describe("CartTerrainProfileResolver", function()
		it("resolves the exact Scrap Chariot Development terrain profile", function()
			local profile = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local expectedValues = {
				Enabled = true,
				ProbeOriginHeight = 2,
				GroundDetectionDistance = 6,
				MaximumSupportGap = 1.25,
				MaximumSupportPenetration = 0.35,
				LateralProbeFraction = 0.42,
				ForwardProbeFraction = 0.3,
				FullGroundedHitCount = 2,
				GroundedReacquireDelay = 0.08,
				AirborneDelay = 0.18,
				NormalResponseSpeed = 10,
				MaximumNormalChangeDegreesPerSecond = 120,
				AirborneWorldUpResponseSpeed = 2.5,
				NormalOutlierAngleDegrees = 35,
				SlopeEffectStartDegrees = 3,
				FullSlopeEffectDegrees = 35,
				MaximumClimbAngleDegrees = 45,
				MaximumGroundAngleDegrees = 65,
				MaximumUphillAccelerationReduction = 0.25,
				MaximumDownhillAcceleration = 3,
				MaximumDownhillCoastReduction = 0.2,
				PartialSupportStabilityMultiplier = 0.7,
				AirborneStabilityMultiplier = 0.35,
				DrivenSampleRate = 15,
				ServerMovingSampleRate = 10,
				ServerSettledSampleRate = 4,
				ServerSettledSpeedThreshold = 1,
			}

			expect(profile.CartId).to.equal(Ids.Carts.ScrapChariot)

			for field, expectedValue in expectedValues do
				expect((profile :: any)[field]).to.equal(expectedValue)
			end
		end)

		it("freezes the nested source and a fresh copied result", function()
			local source = Carts[Ids.Carts.ScrapChariot].Terrain
			local originalDistance = source.GroundDetectionDistance
			local profile = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)

			expect((profile :: any) == (source :: any)).to.equal(false)
			expect(table.isfrozen(source)).to.equal(true)
			expect(table.isfrozen(profile)).to.equal(true)

			local sourceMutationSucceeded = pcall(function()
				(source :: any).GroundDetectionDistance = 30
			end)
			local resultMutationSucceeded = pcall(function()
				(profile :: any).GroundDetectionDistance = 30
			end)

			expect(sourceMutationSucceeded).to.equal(false)
			expect(resultMutationSucceeded).to.equal(false)
			expect(source.GroundDetectionDistance).to.equal(originalDistance)
		end)

		it("returns deterministic values in separate snapshots", function()
			local first = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local second = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)

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

			cart.Name = "TerrainTestCart"
			cart.Parent = container

			local missingSuccess, missingError = pcall(function()
				CartTerrainProfileResolver.ResolveForCart(cart)
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
			expect(CartTerrainProfileResolver.ResolveForCart(cart).Enabled).to.equal(true)

			cart:Destroy()

			local destroyedSuccess, destroyedError = pcall(function()
				CartTerrainProfileResolver.ResolveForCart(cart)
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

			local first = CartTerrainProfileResolver.ResolveForCart(firstCart)
			local replacement = CartTerrainProfileResolver.ResolveForCart(replacementCart)

			expect((first :: any) == (replacement :: any)).to.equal(false)
			expect(first.NormalResponseSpeed).to.equal(replacement.NormalResponseSpeed)

			container:Destroy()
		end)

		it("validates every configured terrain profile", function()
			expect(function()
				CartTerrainProfileResolver.ValidateAll()
			end).never.to.throw()
		end)
	end)
end
