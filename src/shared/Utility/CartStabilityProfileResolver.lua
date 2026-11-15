--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local CartStabilityTypes = require(ReplicatedStorage.Shared.Types.CartStabilityTypes)
local CartStabilityProfileValidator =
	require(ReplicatedStorage.Shared.Validation.CartStabilityProfileValidator)

type EffectiveStabilityProfile = CartStabilityTypes.EffectiveStabilityProfile

local COMPONENT = "CartStabilityProfileResolver"

local CartStabilityProfileResolver = {}

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

function CartStabilityProfileResolver.Resolve(cartId: unknown): EffectiveStabilityProfile
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

	local base = definition.Stability

	CartStabilityProfileValidator.AssertValidBase(resolvedCartId, base)

	local profile: EffectiveStabilityProfile = {
		CartId = resolvedCartId,
		Enabled = base.Enabled,

		OrientationErrorDeadZoneDegrees = base.OrientationErrorDeadZoneDegrees,
		FreeRollAngleDegrees = base.FreeRollAngleDegrees,
		FreePitchAngleDegrees = base.FreePitchAngleDegrees,
		ModerateRollAngleDegrees = base.ModerateRollAngleDegrees,
		ModeratePitchAngleDegrees = base.ModeratePitchAngleDegrees,
		StrongRollAngleDegrees = base.StrongRollAngleDegrees,
		StrongPitchAngleDegrees = base.StrongPitchAngleDegrees,

		UprightStrength = base.UprightStrength,
		RollCorrectionStrength = base.RollCorrectionStrength,
		PitchCorrectionStrength = base.PitchCorrectionStrength,
		RollDamping = base.RollDamping,
		PitchDamping = base.PitchDamping,
		MaxCorrectiveTorque = base.MaxCorrectiveTorque,
		MaxCorrectiveAngularResponseDegreesPerSecond = base.MaxCorrectiveAngularResponseDegreesPerSecond,
		ResponseSpeed = base.ResponseSpeed,

		StationaryAssistanceMultiplier = base.StationaryAssistanceMultiplier,
		DrivingAssistanceMultiplier = base.DrivingAssistanceMultiplier,
		SevereTiltRecoveryMultiplier = base.SevereTiltRecoveryMultiplier,

		ExtremeYawDamping = base.ExtremeYawDamping,
		ExtremeYawThresholdDegreesPerSecond = base.ExtremeYawThresholdDegreesPerSecond,
	}

	CartStabilityProfileValidator.AssertValidEffective(resolvedCartId, profile)

	return table.freeze(profile)
end

function CartStabilityProfileResolver.ResolveForCart(cart: unknown): EffectiveStabilityProfile
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

	return CartStabilityProfileResolver.Resolve(cartId)
end

function CartStabilityProfileResolver.ValidateAll()
	for cartId in Carts do
		CartStabilityProfileResolver.Resolve(cartId)
	end
end

return CartStabilityProfileResolver
