--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local CartTerrainTypes = require(ReplicatedStorage.Shared.Types.CartTerrainTypes)
local CartTerrainProfileValidator =
	require(ReplicatedStorage.Shared.Validation.CartTerrainProfileValidator)

type EffectiveTerrainProfile = CartTerrainTypes.EffectiveTerrainProfile

local COMPONENT = "CartTerrainProfileResolver"

local CartTerrainProfileResolver = {}

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

function CartTerrainProfileResolver.Resolve(cartId: unknown): EffectiveTerrainProfile
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

	local base = definition.Terrain

	CartTerrainProfileValidator.AssertValidBase(resolvedCartId, base)

	local profile: EffectiveTerrainProfile = {
		CartId = resolvedCartId,
		Enabled = base.Enabled,

		ProbeOriginHeight = base.ProbeOriginHeight,
		GroundDetectionDistance = base.GroundDetectionDistance,
		MaximumSupportGap = base.MaximumSupportGap,
		MaximumSupportPenetration = base.MaximumSupportPenetration,
		LateralProbeFraction = base.LateralProbeFraction,
		ForwardProbeFraction = base.ForwardProbeFraction,
		FullGroundedHitCount = base.FullGroundedHitCount,

		GroundedReacquireDelay = base.GroundedReacquireDelay,
		AirborneDelay = base.AirborneDelay,
		NormalResponseSpeed = base.NormalResponseSpeed,
		MaximumNormalChangeDegreesPerSecond = base.MaximumNormalChangeDegreesPerSecond,
		AirborneWorldUpResponseSpeed = base.AirborneWorldUpResponseSpeed,
		NormalOutlierAngleDegrees = base.NormalOutlierAngleDegrees,

		SlopeEffectStartDegrees = base.SlopeEffectStartDegrees,
		FullSlopeEffectDegrees = base.FullSlopeEffectDegrees,
		MaximumClimbAngleDegrees = base.MaximumClimbAngleDegrees,
		MaximumGroundAngleDegrees = base.MaximumGroundAngleDegrees,
		MaximumUphillAccelerationReduction = base.MaximumUphillAccelerationReduction,
		MaximumDownhillAcceleration = base.MaximumDownhillAcceleration,
		MaximumDownhillCoastReduction = base.MaximumDownhillCoastReduction,

		PartialSupportStabilityMultiplier = base.PartialSupportStabilityMultiplier,
		AirborneStabilityMultiplier = base.AirborneStabilityMultiplier,

		DrivenSampleRate = base.DrivenSampleRate,
		ServerMovingSampleRate = base.ServerMovingSampleRate,
		ServerSettledSampleRate = base.ServerSettledSampleRate,
		ServerSettledSpeedThreshold = base.ServerSettledSpeedThreshold,
	}

	CartTerrainProfileValidator.AssertValidEffective(resolvedCartId, profile)

	return table.freeze(profile)
end

function CartTerrainProfileResolver.ResolveForCart(cart: unknown): EffectiveTerrainProfile
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

	return CartTerrainProfileResolver.Resolve(cartId)
end

function CartTerrainProfileResolver.ValidateAll()
	for cartId in Carts do
		CartTerrainProfileResolver.Resolve(cartId)
	end
end

return CartTerrainProfileResolver
