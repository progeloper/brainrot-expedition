--!strict

-- Pure weapon-profile resolution. It does not inspect profiles, grant
-- ownership, select equipment, clone Tools, fire shots or mutate definitions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local WeaponStats = {}

local function finitePositive(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and math.abs(value) < math.huge
end

local function definitionFrom(weaponId: string, options: any?): any?
	if type(options) == "table" and type(options.definitions) == "table" then
		return options.definitions[weaponId]
	end
	return Weapons.Get(weaponId)
end

local function validAuthority(value: any): boolean
	return value == "Gameplay" or value == "PresentationOnly"
end

local function finish(values: any): any
	return table.freeze(values)
end

local function resolveDefinition(definition: any, options: any?, visiting: { [string]: boolean }): any
	if type(definition) ~= "table" or type(definition.id) ~= "string" then
		return finish({ status = "Invalid", code = "INVALID_WEAPON_DEFINITION" })
	end
	if visiting[definition.id] then
		return finish({ status = "Invalid", code = "WEAPON_PROFILE_CYCLE" })
	end
	visiting[definition.id] = true

	local stats = definition.stats
	local modifiers = definition.modifiers
	local values: any
	if stats ~= nil and modifiers ~= nil then
		values = { status = "Invalid", code = "MIXED_ABSOLUTE_AND_DERIVED_STATS" }
	elseif type(stats) == "table" then
		values = {
			status = "Ready",
			code = "ABSOLUTE_PROFILE",
			weaponId = definition.id,
			family = definition.family or "Bow",
			profileId = definition.profileId,
			damage = stats.damage or 1,
			definitionRevision = definition.definitionRevision,
			rangeStuds = stats.rangeStuds,
			fireIntervalSeconds = stats.fireIntervalSeconds,
			projectileSpeedStudsPerSecond = stats.projectileSpeedStudsPerSecond,
			projectileSpeedAuthority = stats.projectileSpeedAuthority,
			assistAcquireHalfAngleRadians = stats.assistAcquireHalfAngleRadians,
			assistRetainHalfAngleRadians = stats.assistRetainHalfAngleRadians,
		}
	elseif type(modifiers) == "table" and type(definition.baseWeaponId) == "string" then
		local baseDefinition = definitionFrom(definition.baseWeaponId, options)
		if baseDefinition == nil then
			values = { status = "Invalid", code = "UNKNOWN_BASE_WEAPON" }
		else
			local base = resolveDefinition(baseDefinition, options, visiting)
			if base.status ~= "Ready" then
				values = { status = "Invalid", code = base.code }
			else
				local rangeFactor = modifiers.rangeFactor or 1
				local intervalFactor = modifiers.fireIntervalFactor or 1
				local projectileFactor = modifiers.projectileSpeedFactor or 1
				local acquireFactor = modifiers.assistAcquireAngleFactor or 1
				local retainFactor = modifiers.assistRetainAngleFactor or 1
				values = {
					status = "Ready",
					code = "DERIVED_PROFILE",
					weaponId = definition.id,
					family = definition.family or base.family,
					profileId = definition.profileId,
					damage = base.damage * (modifiers.damageFactor or 1),
					definitionRevision = definition.definitionRevision,
					rangeStuds = base.rangeStuds * rangeFactor,
					fireIntervalSeconds = base.fireIntervalSeconds * intervalFactor,
					projectileSpeedStudsPerSecond = base.projectileSpeedStudsPerSecond * projectileFactor,
					projectileSpeedAuthority = base.projectileSpeedAuthority,
					assistAcquireHalfAngleRadians = base.assistAcquireHalfAngleRadians * acquireFactor,
					assistRetainHalfAngleRadians = base.assistRetainHalfAngleRadians * retainFactor,
				}
			end
		end
	else
		values = { status = "Invalid", code = "MISSING_WEAPON_STATS" }
	end
	visiting[definition.id] = nil

	if values.status ~= "Ready" then
		return finish(values)
	end
	if
		type(values.definitionRevision) ~= "number"
		or values.definitionRevision % 1 ~= 0
		or values.definitionRevision < 1
	then
		return finish({ status = "Invalid", code = "INVALID_DEFINITION_REVISION" })
	end
	for _, field in
		{
			"damage",
			"rangeStuds",
			"fireIntervalSeconds",
			"projectileSpeedStudsPerSecond",
			"assistAcquireHalfAngleRadians",
			"assistRetainHalfAngleRadians",
		}
	do
		if not finitePositive(values[field]) then
			return finish({ status = "Invalid", code = "INVALID_" .. string.upper(field) })
		end
	end
	if
		values.assistAcquireHalfAngleRadians >= math.pi
		or values.assistRetainHalfAngleRadians >= math.pi
		or values.assistRetainHalfAngleRadians < values.assistAcquireHalfAngleRadians
	then
		return finish({ status = "Invalid", code = "INVALID_ASSIST_ANGLES" })
	end
	if not validAuthority(values.projectileSpeedAuthority) then
		return finish({ status = "Invalid", code = "INVALID_PROJECTILE_AUTHORITY" })
	end
	return finish(values)
end

function WeaponStats.Resolve(weaponId: any, options: any?): any
	if type(weaponId) ~= "string" then
		return finish({ status = "Invalid", code = "INVALID_WEAPON_ID" })
	end
	local definition = definitionFrom(weaponId, options)
	if definition == nil then
		return finish({ status = "Unavailable", code = "UNKNOWN_WEAPON_ID", weaponId = weaponId })
	end
	return resolveDefinition(definition, options, {})
end

function WeaponStats.GetSelected(data: any): any
	local phase = type(data) == "table" and data.Phase13
	local selected = type(phase) == "table" and phase.SelectedWeaponId
	local owned = type(phase) == "table" and phase.OwnedWeaponIds
	if type(selected) ~= "string" or not Weapons.Get(selected) then
		selected = Weapons.StarterWeaponId
	end
	if selected ~= Weapons.StarterWeaponId and (type(owned) ~= "table" or owned[selected] ~= true) then
		return finish({ status = "Unavailable", code = "WEAPON_NOT_OWNED" })
	end
	return WeaponStats.Resolve(selected)
end

function WeaponStats.IsReady(profile: any): boolean
	return type(profile) == "table"
		and profile.status == "Ready"
		and type(profile.weaponId) == "string"
		and type(profile.definitionRevision) == "number"
		and profile.definitionRevision % 1 == 0
		and profile.definitionRevision >= 1
		and finitePositive(profile.damage or 1)
		and finitePositive(profile.rangeStuds)
		and finitePositive(profile.fireIntervalSeconds)
		and finitePositive(profile.projectileSpeedStudsPerSecond)
		and validAuthority(profile.projectileSpeedAuthority)
		and finitePositive(profile.assistAcquireHalfAngleRadians)
		and finitePositive(profile.assistRetainHalfAngleRadians)
		and profile.assistAcquireHalfAngleRadians < math.pi
		and profile.assistRetainHalfAngleRadians < math.pi
		and profile.assistRetainHalfAngleRadians >= profile.assistAcquireHalfAngleRadians
end

function WeaponStats.CaptureShotProfile(profile: any, equipmentRevision: number?): any?
	if not WeaponStats.IsReady(profile) then
		return nil
	end
	local revision = equipmentRevision or 0
	if
		type(revision) ~= "number"
		or revision ~= revision
		or math.abs(revision) == math.huge
		or revision < 0
		or revision % 1 ~= 0
	then
		return nil
	end
	return table.freeze({
		status = "Ready",
		code = "CAPTURED_PROFILE",
		weaponId = profile.weaponId,
		family = profile.family or "Bow",
		profileId = profile.profileId,
		damage = profile.damage or 1,
		definitionRevision = profile.definitionRevision,
		equipmentRevision = revision,
		rangeStuds = profile.rangeStuds,
		fireIntervalSeconds = profile.fireIntervalSeconds,
		projectileSpeedStudsPerSecond = profile.projectileSpeedStudsPerSecond,
		projectileSpeedAuthority = profile.projectileSpeedAuthority,
		assistAcquireHalfAngleRadians = profile.assistAcquireHalfAngleRadians,
		assistRetainHalfAngleRadians = profile.assistRetainHalfAngleRadians,
	})
end

return table.freeze(WeaponStats)
