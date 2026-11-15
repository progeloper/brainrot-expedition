--!strict

local CartAnalyticsReasonMapper = {}

function CartAnalyticsReasonMapper.DriverExit(reason: string): string
	local lowered = string.lower(reason)

	if string.find(lowered, "service stopp", 1, true) ~= nil then
		return "ServiceShutdown"
	elseif
		string.find(lowered, "player remov", 1, true) ~= nil
		or string.find(lowered, "player leav", 1, true) ~= nil
	then
		return "PlayerLeaving"
	elseif string.find(lowered, "replacing", 1, true) ~= nil then
		return "CartReplaced"
	elseif
		string.find(lowered, "driver replaced", 1, true) ~= nil
		or string.find(lowered, "assigned to another cart", 1, true) ~= nil
	then
		return "DriverReplaced"
	elseif
		string.find(lowered, "seat", 1, true) ~= nil
		or string.find(lowered, "occupant", 1, true) ~= nil
		or string.find(lowered, "vacant", 1, true) ~= nil
	then
		return "SeatExited"
	elseif
		string.find(lowered, "character", 1, true) ~= nil
		or string.find(lowered, "humanoid", 1, true) ~= nil
	then
		return "CharacterInvalidated"
	elseif
		string.find(lowered, "destroy", 1, true) ~= nil
		or string.find(lowered, "removed", 1, true) ~= nil
		or string.find(lowered, "invalid", 1, true) ~= nil
	then
		return "CartDestroyed"
	end

	return "Unknown"
end

function CartAnalyticsReasonMapper.Despawn(reason: string): string
	local lowered = string.lower(reason)

	if string.find(lowered, "service stopp", 1, true) ~= nil then
		return "ServiceShutdown"
	elseif string.find(lowered, "player leav", 1, true) ~= nil then
		return "PlayerLeaving"
	elseif string.find(lowered, "replac", 1, true) ~= nil then
		return "Replacement"
	elseif
		string.find(lowered, "model destroy", 1, true) ~= nil
		or string.find(lowered, "model removed", 1, true) ~= nil
	then
		return "ModelDestroyed"
	elseif reason == "cart despawning" then
		return "ExplicitDespawn"
	elseif string.find(lowered, "fatal runtime", 1, true) ~= nil then
		return "ExplicitDespawn"
	end

	return "Unknown"
end

return table.freeze(CartAnalyticsReasonMapper)
