--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Carts = require(ReplicatedStorage.Shared.Config.Carts)
	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartMovementProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartMovementProfileResolver)

	local function expectFailure(cartId: any, expectedText: string)
		local success, errorMessage = pcall(function()
			CartMovementProfileResolver.Resolve(cartId)
		end)

		expect(success).to.equal(false)
		expect(string.find(tostring(errorMessage), expectedText, 1, true) ~= nil).to.equal(true)
	end

	describe("CartMovementProfileResolver", function()
		it("resolves the complete hunting-cart movement profile", function()
			local profile = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local expectedValues = {
				HuntingSpeed = 20,
				MaxTravelSpeed = 48,
				ControlReferenceSpeed = 48,
				ForwardAcceleration = 80,
				HighSpeedAccelerationMultiplier = 1,
				AccelerationCurveExponent = 1.35,
				CoastDeceleration = 140,
				HighSpeedCoastDecelerationMultiplier = 1,
				Braking = 140,
				HighSpeedBrakingMultiplier = 1,
				RecoveryBackupSpeed = 3.5,
				RecoveryBackupAcceleration = 6,
				RecoveryBackupDeceleration = 12,
				RecoveryInputDelay = 0.45,
				NearZeroSpeedThreshold = 0.6,
				LongitudinalInputDeadzone = 0.05,
				LongitudinalTransitionRetryInterval = 0.1,
				LongitudinalTransitionMaximumRetryInterval = 1,
				TurnRate = 300,
				StationarySteeringThreshold = 0.5,
				LowSpeedSteeringMultiplier = 1,
				HighSpeedSteeringMultiplier = 170 / 300,
				SteeringInterpolationExponent = 1.35,
				LateralGrip = 10,
				HighSpeedLateralGripMultiplier = 1.25,
				DriveForceLimit = 180,
				UprightResponsiveness = 55,
				UprightTorque = 42000,
				MaxAngularSpeed = 300,
				GroundFriction = 0.08,
				GroundFrictionWeight = 100,
			}

			expect(profile.CartId).to.equal(Ids.Carts.ScrapChariot)

			for field, expectedValue in expectedValues do
				expect((profile :: any)[field]).to.equal(expectedValue)
			end
		end)

		it("does not expose legacy conventional reverse values", function()
			local profile = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)

			expect((profile :: any).MaxReverseSpeed).to.equal(nil)
			expect((profile :: any).ReverseAcceleration).to.equal(nil)
			expect((profile :: any).ReverseSpeedMultiplier).to.equal(nil)
		end)

		it("returns a frozen copy instead of the source definition", function()
			local source = Carts[Ids.Carts.ScrapChariot]
			local sourceTravelSpeed = source.MaxTravelSpeed
			local profile = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)

			expect((profile :: any) == (source :: any)).to.equal(false)
			expect(table.isfrozen(profile)).to.equal(true)
			expect(table.isfrozen(source)).to.equal(true)

			local mutationSucceeded = pcall(function()
				(profile :: any).MaxTravelSpeed = 999
			end)

			expect(mutationSucceeded).to.equal(false)
			expect(source.MaxTravelSpeed).to.equal(sourceTravelSpeed)
		end)

		it("returns deterministic values in fresh snapshots", function()
			local first = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local second = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)

			expect((first :: any) == (second :: any)).to.equal(false)

			for field, firstValue in first :: any do
				expect((second :: any)[field]).to.equal(firstValue)
			end
		end)

		-- Arcade contract: a purchased contribution raises the forward ceiling and
		-- scales acceleration/braking by the same ratio; everything else is unchanged.
		it("changes only the forward ceiling and its response scale for a validated purchased contribution", function()
			local profile = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot, {
				status = "Ready",
				baseSpeed = 48,
				resolvedSpeed = 49.92,
			})
			local responseScale = 49.92 / 48

			expect(profile.MaxTravelSpeed).to.equal(49.92)
			expect(profile.ControlReferenceSpeed).to.equal(48)
			expect(profile.ForwardAcceleration).to.equal(80 * responseScale)
			expect(profile.Braking).to.equal(140 * responseScale)
			expect(profile.CoastDeceleration).to.equal(140 * responseScale)
			expect(profile.RecoveryBackupSpeed).to.equal(3.5)
			expect(profile.TurnRate).to.equal(300)
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

			cart.Name = "TestCart"
			cart.Parent = container

			local missingSuccess, missingError = pcall(function()
				CartMovementProfileResolver.ResolveForCart(cart)
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
			expect(CartMovementProfileResolver.ResolveForCart(cart).MaxTravelSpeed).to.equal(48)
			cart:SetAttribute(CartMovementProfileResolver.Attributes.ResolvedMaxTravelSpeed, 49.92)
			local upgraded = CartMovementProfileResolver.ResolveForCart(cart)
			expect(upgraded.MaxTravelSpeed).to.equal(49.92)
			expect(upgraded.ControlReferenceSpeed).to.equal(48)

			cart:Destroy()

			local destroyedSuccess, destroyedError = pcall(function()
				CartMovementProfileResolver.ResolveForCart(cart)
			end)

			expect(destroyedSuccess).to.equal(false)
			expect(string.find(tostring(destroyedError), "live runtime cart", 1, true) ~= nil).to.equal(
				true
			)

			container:Destroy()
		end)

		it("resolves a fresh profile for each runtime cart", function()
			local container = Instance.new("Folder")
			local firstCart = Instance.new("Model")
			local replacementCart = Instance.new("Model")

			firstCart:SetAttribute("CartId", Ids.Carts.ScrapChariot)
			replacementCart:SetAttribute("CartId", Ids.Carts.ScrapChariot)
			firstCart.Parent = container
			replacementCart.Parent = container

			local first = CartMovementProfileResolver.ResolveForCart(firstCart)
			local replacement = CartMovementProfileResolver.ResolveForCart(replacementCart)

			expect((first :: any) == (replacement :: any)).to.equal(false)
			expect(first.MaxTravelSpeed).to.equal(replacement.MaxTravelSpeed)
			expect(first.RecoveryBackupSpeed).to.equal(replacement.RecoveryBackupSpeed)

			container:Destroy()
		end)

		it("validates all currently configured cart profiles", function()
			expect(function()
				CartMovementProfileResolver.ValidateAll()
			end).never.to.throw()
		end)
	end)
end
