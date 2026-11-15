--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Handling = require(ReplicatedStorage.Shared.Config.CartHandlingConfig)
local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local CartMovementTypes = require(ReplicatedStorage.Shared.Types.CartMovementTypes)
local CartMovementProfileValidator = require(ReplicatedStorage.Shared.Validation.CartMovementProfileValidator)

type EffectiveMovementProfile = CartMovementTypes.EffectiveMovementProfile

local COMPONENT = "CartMovementProfileResolver"

local CartMovementProfileResolver = {}

CartMovementProfileResolver.Attributes = table.freeze({
	BaseSpeed = "PerformanceBaseSpeed",
	PurchasedSpeedContribution = "PerformanceSpeedContribution",
	ResolvedMaxTravelSpeed = "ResolvedMaxTravelSpeed",
	Status = "PerformanceStatus",
	Revision = "PerformanceRevision",
})

local function assertCartId(cartId: unknown): string
	if type(cartId) ~= "string" or cartId == "" then
		error(
			string.format(
				"[%s] CartId=%s Field=CartId Value=%s (%s) Expected=non-empty string assigned by the server",
				COMPONENT,
				tostring(cartId),
				tostring(cartId),
				type(cartId)
			),
			3
		)
	end

	return cartId
end

function CartMovementProfileResolver.Resolve(cartId: unknown, performance: any?): EffectiveMovementProfile
	local resolvedCartId = assertCartId(cartId)
	local definition = Carts[resolvedCartId]

	if definition == nil then
		error(
			string.format(
				"[%s] CartId=%s Field=CartId Value=%s Expected=approved cart definition; no fallback was used",
				COMPONENT,
				resolvedCartId,
				resolvedCartId
			),
			2
		)
	end

	CartMovementProfileValidator.AssertValidBase(resolvedCartId, definition)

	if definition.Id ~= resolvedCartId then
		error(
			string.format(
				"[%s] CartId=%s Field=Id Value=%s Expected=definition Id matching its configuration key",
				COMPONENT,
				resolvedCartId,
				tostring(definition.Id)
			),
			2
		)
	end

	local maxTravelSpeed = definition.MaxTravelSpeed
	if performance ~= nil then
		if
			type(performance) ~= "table"
			or performance.status ~= "Ready"
			or type(performance.baseSpeed) ~= "number"
			or performance.baseSpeed ~= definition.MaxTravelSpeed
			or type(performance.resolvedSpeed) ~= "number"
			or performance.resolvedSpeed ~= performance.resolvedSpeed
			or math.abs(performance.resolvedSpeed) == math.huge
			or performance.resolvedSpeed <= 0
		then
			error(
				string.format(
					"[%s] CartId=%s Field=performance Value=%s Expected=current Ready performance derived from this cart baseline",
					COMPONENT,
					resolvedCartId,
					tostring(performance)
				),
				2
			)
		end
		maxTravelSpeed = performance.resolvedSpeed
	end

	-- Apply the existing authoritative legal speed once, then scale response.
	local responseScale = maxTravelSpeed / Handling.StarterSpeed
	local profile: EffectiveMovementProfile = {
		CartId = resolvedCartId,

		HuntingSpeed = definition.HuntingSpeed,
		MaxTravelSpeed = maxTravelSpeed,
		ControlReferenceSpeed = Handling.StarterSpeed,
		ForwardAcceleration = definition.ForwardAcceleration * responseScale,
		HighSpeedAccelerationMultiplier = definition.HighSpeedAccelerationMultiplier,
		AccelerationCurveExponent = definition.AccelerationCurveExponent,
		CoastDeceleration = definition.CoastDeceleration * responseScale,
		HighSpeedCoastDecelerationMultiplier = definition.HighSpeedCoastDecelerationMultiplier,
		Braking = definition.Braking * responseScale,
		HighSpeedBrakingMultiplier = definition.HighSpeedBrakingMultiplier,
		RecoveryBackupSpeed = definition.RecoveryBackupSpeed,
		RecoveryBackupAcceleration = definition.RecoveryBackupAcceleration,
		RecoveryBackupDeceleration = definition.RecoveryBackupDeceleration,
		RecoveryInputDelay = definition.RecoveryInputDelay,
		NearZeroSpeedThreshold = definition.NearZeroSpeedThreshold,
		LongitudinalInputDeadzone = definition.LongitudinalInputDeadzone,
		LongitudinalTransitionRetryInterval = definition.LongitudinalTransitionRetryInterval,
		LongitudinalTransitionMaximumRetryInterval = definition.LongitudinalTransitionMaximumRetryInterval,

		TurnRate = definition.TurnRate,
		StationarySteeringThreshold = definition.StationarySteeringThreshold,
		LowSpeedSteeringMultiplier = definition.LowSpeedSteeringMultiplier,
		HighSpeedSteeringMultiplier = definition.HighSpeedSteeringMultiplier,
		SteeringInterpolationExponent = definition.SteeringInterpolationExponent,

		LateralGrip = definition.LateralGrip,
		HighSpeedLateralGripMultiplier = definition.HighSpeedLateralGripMultiplier,
		DriveForceLimit = definition.DriveForceLimit,
		UprightResponsiveness = definition.UprightResponsiveness,
		UprightTorque = definition.UprightTorque,
		MaxAngularSpeed = definition.MaxAngularSpeed,

		GroundFriction = definition.GroundFriction,
		GroundFrictionWeight = definition.GroundFrictionWeight,
	}

	CartMovementProfileValidator.AssertValidEffective(resolvedCartId, profile)

	return table.freeze(profile)
end

function CartMovementProfileResolver.ResolveForCart(cart: unknown): EffectiveMovementProfile
	if typeof(cart) ~= "Instance" or not cart:IsA("Model") then
		error(
			string.format(
				"[%s] CartId=unknown Field=cart Value=%s Expected=live runtime cart Model",
				COMPONENT,
				tostring(cart)
			),
			2
		)
	end

	local cartModel = cart :: Model
	local cartId = cartModel:GetAttribute("CartId")

	if cartModel.Parent == nil then
		error(
			string.format(
				"[%s] CartId=%s Field=Model.Parent Value=nil Cart=%s Expected=live runtime cart whose Parent is not nil",
				COMPONENT,
				tostring(cartId),
				cartModel.Name
			),
			2
		)
	end

	local resolvedSpeed = cartModel:GetAttribute(CartMovementProfileResolver.Attributes.ResolvedMaxTravelSpeed)
	if resolvedSpeed == nil then
		return CartMovementProfileResolver.Resolve(cartId)
	end
	local definition = if type(cartId) == "string" then Carts[cartId] else nil
	return CartMovementProfileResolver.Resolve(cartId, {
		status = "Ready",
		baseSpeed = if definition ~= nil then definition.MaxTravelSpeed else nil,
		resolvedSpeed = resolvedSpeed,
		purchasedSpeedContribution = cartModel:GetAttribute(
			CartMovementProfileResolver.Attributes.PurchasedSpeedContribution
		) or 0,
	})
end

function CartMovementProfileResolver.ValidateAll()
	for cartId in Carts do
		CartMovementProfileResolver.Resolve(cartId)
	end
end

return CartMovementProfileResolver
