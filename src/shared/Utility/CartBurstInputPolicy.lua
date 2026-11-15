--!strict

local Policy = {}

function Policy.CanActivate(context: any): boolean
	return context.FeatureEnabled == true
		and context.AuthorizedDriver == true
		and context.CartAlive == true
		and context.WindowFocused == true
		and context.TextFocused ~= true
		and context.SystemMenuOpen ~= true
		and context.TeamMenuOpen ~= true
		and context.ResetActive ~= true
end

return table.freeze(Policy)
