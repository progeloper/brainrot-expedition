--!strict
-- Isolated live fixtures use the existing store and lock implementation. The
-- namespace is a Studio-only server attribute, never a client request or grant.
local ProfileKey = {}
-- Studio Play with no namespace set (it is lost whenever an unsaved attribute is dropped) uses this
-- isolated key instead of refusing the profile and kicking. Only Studio running the Production
-- environment needs it (other Studio environments keep ordinary keys); published servers never do.
ProfileKey.DefaultStudioNamespace = "studio"
function ProfileKey.StudioNamespace(namespace: any, studioProduction: boolean): any
	if studioProduction and namespace == nil then return ProfileKey.DefaultStudioNamespace end
	return namespace
end
function ProfileKey.Resolve(userId: number, prefix: string, namespace: any, studio: boolean, production: boolean, allowIsolatedProductionStudio: boolean?): (string?, string?)
	local ordinary = prefix .. tostring(userId)
	if not studio or (production and allowIsolatedProductionStudio ~= true) or namespace == nil then return ordinary, nil end
	if type(namespace) ~= "string" or #namespace == 0 or #namespace > 48
		or not namespace:match("^[%w_-]+$") then
		return nil, "INVALID_STUDIO_PROFILE_NAMESPACE"
	end
	local key = "phase8_test_" .. namespace .. "_" .. ordinary
	if #key > 50 then return nil, "STUDIO_PROFILE_KEY_TOO_LONG" end
	return key, nil
end
return table.freeze(ProfileKey)
