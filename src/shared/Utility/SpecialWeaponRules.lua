--!strict
-- Camp Rework (12 Nov 2026): pure rules for the special weapons. No services or Instances.
-- Won specials are earned, never bought, never sold:
--   Collector's Bow       15 species discovered      (bronze medal pedestal)
--   Getaway Crossbow      25 clean villager escapes  (silver)
--   Secret Hunter Blaster first Secret caught        (gold)
-- Every grant runs inside the existing Phase13 critical transaction (server only).
local Weapons = require(script.Parent.Parent.Config.Weapons)
local Catalog = require(script.Parent.Parent.Config.BrainrotCatalog)

local Rules = {}

Rules.MaxCleanEscapes = 1_000_000

-- Distinct canonical species with a saved discovery proof.
function Rules.SpeciesDiscovered(data: any): number
	local seen: { [string]: boolean } = {}
	local count = 0
	local species = type(data) == "table" and type(data.Collection) == "table" and data.Collection.Species or nil
	if type(species) ~= "table" then
		return 0
	end
	for rawId, proof in species do
		local definition = if proof then Catalog.Get(rawId) else nil
		if definition and not seen[definition.id] then
			seen[definition.id] = true
			count += 1
		end
	end
	return count
end

function Rules.SecretCaught(data: any): boolean
	local species = type(data) == "table" and type(data.Collection) == "table" and data.Collection.Species or nil
	if type(species) ~= "table" then
		return false
	end
	for rawId, proof in species do
		if proof and Catalog.GetRarity(rawId) == "Secret" then
			return true
		end
	end
	return false
end

function Rules.CleanEscapes(data: any): number
	local p = type(data) == "table" and data.Phase13 or nil
	local n = if type(p) == "table" then p.CleanEscapes else nil
	return if type(n) == "number" and n == n and n >= 0 and n % 1 == 0 then n else 0
end

-- Progress toward one milestone: (current, target, met).
function Rules.Progress(data: any, unlock: any): (number, number, boolean)
	if type(unlock) ~= "table" or unlock.kind ~= "Milestone" then
		return 0, 0, false
	end
	local current = 0
	if unlock.milestone == "SpeciesDiscovered" then
		current = Rules.SpeciesDiscovered(data)
	elseif unlock.milestone == "CleanEscapes" then
		current = Rules.CleanEscapes(data)
	elseif unlock.milestone == "SecretCaught" then
		current = if Rules.SecretCaught(data) then 1 else 0
	end
	return current, unlock.target, current >= unlock.target
end

-- Won specials the profile has earned but does not own yet (stable order).
function Rules.Earned(data: any): { string }
	local out = {}
	local owned = type(data) == "table" and type(data.Phase13) == "table" and data.Phase13.OwnedWeaponIds or nil
	if type(owned) ~= "table" then
		return out
	end
	for _, definition in Weapons.GetSpecials() do
		local special = definition.special
		if special.source == "Won" and owned[definition.id] ~= true then
			local _, _, met = Rules.Progress(data, special.unlock)
			if met then
				table.insert(out, definition.id)
			end
		end
	end
	return out
end

-- Critical-transaction mutator: grant every earned Won special. Idempotent.
function Rules.ApplyEarned(data: any): (boolean, any)
	local earned = Rules.Earned(data)
	if #earned == 0 then
		return false, { code = "NOTHING_EARNED" }
	end
	for _, id in earned do
		data.Phase13.OwnedWeaponIds[id] = true
	end
	return true, { code = "APPLIED", category = "SpecialWeapon", granted = earned }
end

-- Critical-transaction mutator: count one clean escape, then grant anything it earned.
function Rules.ApplyCleanEscape(data: any): (boolean, any)
	local p = type(data) == "table" and data.Phase13 or nil
	if type(p) ~= "table" then
		return false, { code = "PROFILE_NOT_READY" }
	end
	p.CleanEscapes = math.min(Rules.MaxCleanEscapes, Rules.CleanEscapes(data) + 1)
	local granted = Rules.Earned(data)
	for _, id in granted do
		p.OwnedWeaponIds[id] = true
	end
	return true, { code = "APPLIED", category = "CleanEscape", cleanEscapes = p.CleanEscapes, granted = granted }
end

-- Snapshot rows for the Weapons stall pedestals and the shop (client display only).
function Rules.Snapshot(data: any): { any }
	local owned = type(data) == "table" and type(data.Phase13) == "table" and data.Phase13.OwnedWeaponIds or {}
	local rows = {}
	for _, definition in Weapons.GetSpecials() do
		local special = definition.special
		local current, target = Rules.Progress(data, special.unlock)
		table.insert(rows, {
			id = definition.id,
			name = definition.displayName,
			source = special.source,
			unlock = special.unlock,
			owned = owned[definition.id] == true,
			progress = current,
			target = target,
		})
	end
	return rows
end

return table.freeze(Rules)
