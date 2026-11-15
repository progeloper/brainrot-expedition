--!strict

export type PermissionContext = {
	FeatureEnabled: boolean,
	CartRegistered: boolean,
	CartAlive: boolean,
	ControlSuspended: boolean,
	PlayerActive: boolean,
	CharacterValid: boolean,
	OccupantMatchesCharacter: boolean,
	OwnerUserId: number,
	PlayerUserId: number,
}

local CartDriverPolicy = {}

function CartDriverPolicy.ResolveCharacter(occupant: Humanoid?): Model?
	if occupant == nil then
		return nil
	end

	local character = occupant.Parent

	if character == nil or not character:IsA("Model") then
		return nil
	end

	return character
end

function CartDriverPolicy.Evaluate(context: PermissionContext): (boolean, string)
	if not context.FeatureEnabled then
		return false, "cart feature is disabled"
	end

	if not context.CartRegistered then
		return false, "cart is not registered"
	end

	if not context.CartAlive then
		return false, "cart is not active"
	end

	if context.ControlSuspended then
		return false, "cart control is suspended"
	end

	if not context.PlayerActive then
		return false, "player is not active"
	end

	if not context.CharacterValid then
		return false, "player character is not valid"
	end

	if not context.OccupantMatchesCharacter then
		return false, "driver seat occupant does not match the player character"
	end

	-- Phase 1E preserves the established owner-only Development rule. This is the
	-- only ownership policy decision; occupancy and authority code remain reusable.
	if context.OwnerUserId ~= context.PlayerUserId then
		return false, "player is not the cart owner"
	end

	return true, "allowed"
end

return CartDriverPolicy
