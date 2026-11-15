--!strict
-- Cosmetic preferences only. No gameplay/profile authority comes from clients.
local Protocol = {}
local MODES = table.freeze({ Auto = true, Low = true, Medium = true, High = true })

function Protocol.IsMode(value: any): boolean
	return type(value) == "string" and MODES[value] == true
end

function Protocol.Default(): any
	return { VFXQuality = "Auto", ReducedMotion = false }
end

function Protocol.Read(settings: any): any
	if type(settings) ~= "table" then
		return Protocol.Default()
	end
	return {
		VFXQuality = if Protocol.IsMode(settings.VFXQuality) then settings.VFXQuality else "Auto",
		ReducedMotion = settings.ReducedMotion == true,
	}
end

function Protocol.ValidateRequest(payload: any): (any?, string?)
	if type(payload) ~= "table" or getmetatable(payload) ~= nil then
		return nil, "INVALID_REQUEST"
	end
	local count = 0
	for key in payload do
		count += 1
		if count > 3 or (key ~= "action" and key ~= "VFXQuality" and key ~= "ReducedMotion") then
			return nil, "INVALID_REQUEST"
		end
	end
	if payload.action == "Get" then
		return if count == 1 then { action = "Get" } else nil, if count == 1 then nil else "INVALID_REQUEST"
	end
	if payload.action ~= "Set" or count < 2 then
		return nil, "INVALID_REQUEST"
	end
	if payload.VFXQuality ~= nil and not Protocol.IsMode(payload.VFXQuality) then
		return nil, "INVALID_VFX_QUALITY"
	end
	if payload.ReducedMotion ~= nil and type(payload.ReducedMotion) ~= "boolean" then
		return nil, "INVALID_REDUCED_MOTION"
	end
	return {
		action = "Set",
		VFXQuality = payload.VFXQuality,
		ReducedMotion = payload.ReducedMotion,
	}, nil
end

function Protocol.MigrateProfile(data: any): boolean
	if data.Settings == nil then
		data.Settings = Protocol.Default()
		return true
	end
	-- An unknown historical non-table Settings extension must not block loading
	-- or be silently discarded. Reads use safe local defaults; writes decline it.
	if type(data.Settings) ~= "table" then
		return false
	end
	local normalized = Protocol.Read(data.Settings)
	local changed = data.Settings.VFXQuality ~= normalized.VFXQuality
		or data.Settings.ReducedMotion ~= normalized.ReducedMotion
	data.Settings.VFXQuality = normalized.VFXQuality
	data.Settings.ReducedMotion = normalized.ReducedMotion
	return changed
end

function Protocol.Apply(data: any, patch: any): (boolean, string?)
	local checked, reason = Protocol.ValidateRequest(patch)
	if not checked or checked.action ~= "Set" then
		return false, reason or "INVALID_REQUEST"
	end
	if data.Settings ~= nil and type(data.Settings) ~= "table" then
		return false, "PREFERENCES_UNAVAILABLE"
	end
	data.Settings = data.Settings or Protocol.Default()
	if checked.VFXQuality ~= nil then
		data.Settings.VFXQuality = checked.VFXQuality
	end
	if checked.ReducedMotion ~= nil then
		data.Settings.ReducedMotion = checked.ReducedMotion
	end
	return true, nil
end

return table.freeze(Protocol)
