--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Carts = require(ReplicatedStorage.Shared.Config.Carts)
	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartMovementValidation = require(ReplicatedStorage.Shared.Config.CartMovementValidation)
	local CartMovementMath = require(ReplicatedStorage.Shared.Utility.CartMovementMath)
	local CartMovementProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartMovementProfileResolver)
	local CartMovementValidationMath =
		require(ReplicatedStorage.Shared.Utility.CartMovementValidationMath)

	local EPSILON = 1e-9
	local function near(first: number, second: number): boolean
		return math.abs(first - second) <= EPSILON
	end

	describe("Phase 7D movement-profile integration", function()
		it("raises the forward ceiling while keeping matched-speed controls unchanged", function()
			local baseline = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local baseSpeed = baseline.MaxTravelSpeed
			local speedOne = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot, {
				status = "Ready",
				baseSpeed = baseSpeed,
				resolvedSpeed = baseSpeed * 1.04,
			})
			local speedOneAndTwo = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot, {
				status = "Ready",
				baseSpeed = baseSpeed,
				resolvedSpeed = baseSpeed * 1.09,
			})

			expect(near(speedOne.MaxTravelSpeed / baseline.MaxTravelSpeed, 1.04)).to.equal(true)
			expect(near(speedOneAndTwo.MaxTravelSpeed / baseline.MaxTravelSpeed, 1.09)).to.equal(
				true
			)
			local physicalSpeed = 28
			local baseAcceleration = CartMovementMath.InterpolateBySpeed(
				physicalSpeed,
				baseline.HuntingSpeed,
				baseline.ControlReferenceSpeed,
				1,
				baseline.HighSpeedAccelerationMultiplier,
				baseline.AccelerationCurveExponent
			)
			local upgradedAcceleration = CartMovementMath.InterpolateBySpeed(
				physicalSpeed,
				speedOne.HuntingSpeed,
				speedOne.ControlReferenceSpeed,
				1,
				speedOne.HighSpeedAccelerationMultiplier,
				speedOne.AccelerationCurveExponent
			)
			local baseSteering = CartMovementMath.GetSteeringMultiplier(
				physicalSpeed,
				baseline.HuntingSpeed,
				baseline.ControlReferenceSpeed,
				baseline.LowSpeedSteeringMultiplier,
				baseline.HighSpeedSteeringMultiplier,
				baseline.SteeringInterpolationExponent
			)
			local upgradedSteering = CartMovementMath.GetSteeringMultiplier(
				physicalSpeed,
				speedOne.HuntingSpeed,
				speedOne.ControlReferenceSpeed,
				speedOne.LowSpeedSteeringMultiplier,
				speedOne.HighSpeedSteeringMultiplier,
				speedOne.SteeringInterpolationExponent
			)

			expect(near(baseAcceleration, upgradedAcceleration)).to.equal(true)
			expect(near(baseSteering, upgradedSteering)).to.equal(true)
			-- Arcade contract: response scales with the resolved ceiling exactly once.
			expect(near(speedOne.ForwardAcceleration, baseline.ForwardAcceleration * 1.04)).to.equal(true)
			expect(near(speedOne.Braking, baseline.Braking * 1.04)).to.equal(true)
			expect(speedOne.RecoveryBackupSpeed).to.equal(baseline.RecoveryBackupSpeed)
			expect(speedOne.TurnRate).to.equal(baseline.TurnRate)
			expect(speedOne.MaxAngularSpeed).to.equal(baseline.MaxAngularSpeed)
		end)

		it("updates server movement envelopes from the same resolved ceiling", function()
			local baseline = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot)
			local baseSpeed = baseline.MaxTravelSpeed
			local upgraded = CartMovementProfileResolver.Resolve(Ids.Carts.ScrapChariot, {
				status = "Ready",
				baseSpeed = baseSpeed,
				resolvedSpeed = baseSpeed * 1.04,
			})
			local baseThresholds =
				CartMovementValidationMath.BuildThresholds(baseline, CartMovementValidation)
			local upgradedThresholds =
				CartMovementValidationMath.BuildThresholds(upgraded, CartMovementValidation)

			expect(upgradedThresholds.ForwardObservation > baseThresholds.ForwardObservation).to.equal(
				true
			)
			-- Reverse shares the forward ceiling and the acceleration envelope follows
			-- the scaled response, so both rise with the resolved ceiling.
			expect(upgradedThresholds.ReverseObservation > baseThresholds.ReverseObservation).to.equal(
				true
			)
			expect(
				upgradedThresholds.AccelerationObservation > baseThresholds.AccelerationObservation
			).to.equal(true)
		end)

		it("does not mutate cargo configuration or runtime cargo attributes", function()
			local definition = Carts[Ids.Carts.ScrapChariot]
			local originalCapacity = definition.CargoCapacity
			local container = Instance.new("Folder")
			local cart = Instance.new("Model")
			cart:SetAttribute("CartId", Ids.Carts.ScrapChariot)
			cart:SetAttribute("CargoCapacity", 4)
			local resolvedSpeed = definition.MaxTravelSpeed * 1.04
			cart:SetAttribute(CartMovementProfileResolver.Attributes.ResolvedMaxTravelSpeed, resolvedSpeed)
			cart.Parent = container

			local profile = CartMovementProfileResolver.ResolveForCart(cart)
			expect(profile.MaxTravelSpeed).to.equal(resolvedSpeed)
			expect(cart:GetAttribute("CargoCapacity")).to.equal(4)
			expect(definition.CargoCapacity).to.equal(originalCapacity)
			expect(#cart:GetChildren()).to.equal(0)

			container:Destroy()
		end)
	end)
end
