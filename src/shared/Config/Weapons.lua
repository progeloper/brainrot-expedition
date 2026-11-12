--!strict
-- Phase 13 authoritative cash catalogue. P15: prices re-anchored to final revenue. Runtime identity is independent of art/name.
-- Weapon Tiers V2 (FeatureFlags.WeaponTiersV2Enabled) swaps only the stat profile per tier; rows are unchanged.
local TiersV2 = require(script.Parent.WeaponTiersV2)
-- Legacy profiles: used whenever Weapon Tiers V2 is off.
local profiles = {
	B1 = { 1, 0.75, 100 },
	B2 = { 1, 0.65, 90 },
	B3 = { 1, 0.85, 115 },
	B4 = { 2, 1.40, 95 },
	C1 = { 2, 1.40, 110 },
	C2 = { 2, 1.20, 95 },
	C3 = { 2, 1.50, 125 },
	C4 = { 2, 1.30, 110 },
	G1 = { 1, 0.45, 70 },
	G2 = { 1, 0.35, 55 },
	G3 = { 1, 0.55, 90 },
	G4 = { 1, 0.40, 75 },
}
local rows = {
	{ "HRP_001", "Trailwood Bow", "Bow", "B1", 0 },
	{ "WPN_B02", "Copperstring Bow", "Bow", "B2", 400000000 },
	{ "WPN_B03", "Horizon Bow", "Bow", "B3", 3000000000 },
	{ "WPN_B04", "Thorncrest Bow", "Bow", "B4", 30000000000 },
	{ "WPN_B05", "Prismstring Bow", "Bow", "B2", 150000000000 },
	{ "WPN_B06", "Frostbranch Bow", "Bow", "B3", 1000000000000 },
	{ "WPN_B07", "Solarhorn Bow", "Bow", "B4", 5000000000000 },
	{ "WPN_B08", "Riftcrown Bow", "Bow", "B4", 20000000000000 },
	{ "WPN_C01", "Scrapbolt Crossbow", "Crossbow", "C1", 50000000 },
	{ "WPN_C02", "Twinrail Crossbow", "Crossbow", "C2", 400000000 },
	{ "WPN_C03", "Farwatch Crossbow", "Crossbow", "C3", 3000000000 },
	{ "WPN_C04", "Ironbloom Crossbow", "Crossbow", "C4", 30000000000 },
	{ "WPN_C05", "Voltspine Crossbow", "Crossbow", "C2", 150000000000 },
	{ "WPN_C06", "Glacierlock Crossbow", "Crossbow", "C3", 1000000000000 },
	{ "WPN_C07", "Sunforge Crossbow", "Crossbow", "C4", 5000000000000 },
	{ "WPN_C08", "Voidcrest Crossbow", "Crossbow", "C4", 20000000000000 },
	{ "WPN_G01", "Tinpop Blaster", "Gun", "G1", 50000000 },
	{ "WPN_G02", "Zipfire Blaster", "Gun", "G2", 400000000 },
	{ "WPN_G03", "Longline Blaster", "Gun", "G3", 3000000000 },
	{ "WPN_G04", "Neonpulse Blaster", "Gun", "G4", 30000000000 },
	{ "WPN_G05", "Sparkstorm Blaster", "Gun", "G2", 150000000000 },
	{ "WPN_G06", "Frostline Blaster", "Gun", "G3", 1000000000000 },
	{ "WPN_G07", "Sunburst Blaster", "Gun", "G4", 5000000000000 },
	{ "WPN_G08", "Riftflare Blaster", "Gun", "G4", 20000000000000 },
}
-- Special weapons (Camp Rework, 12 Nov 2026): off the tier ladder, never bought with Cash and never
-- sold. Premium ones come from Gems or a Robux pass; Won ones from milestones (SpecialWeaponRules).
-- They are defined on both stat paths so ownership/equip always resolves; GetAll() stays the
-- 24-row ladder, so shops and the 8-per-family validation are unaffected.
local specialRows = {
	{ "WPN_SP_RIFTBLASTER", "Rift Blaster", "Gun", "Premium", { kind = "Pass", passId = "WPN_SP_RIFTBLASTER", robux = 499 } },
	{ "WPN_SP_PRISMREPEATER", "Prism Repeater", "Crossbow", "Premium", { kind = "Gems", itemId = "WEAPON_PRISMREPEATER", gems = 300 } },
	{ "WPN_SP_CRYSTALLANCE", "Crystal Lance", "Crossbow", "Premium", { kind = "Gems", itemId = "WEAPON_CRYSTALLANCE", gems = 900 } },
	{ "WPN_SP_COLLECTORSBOW", "Collector's Bow", "Bow", "Won", { kind = "Milestone", milestone = "SpeciesDiscovered", target = 15, medal = "Bronze" } },
	{ "WPN_SP_GETAWAY", "Getaway Crossbow", "Crossbow", "Won", { kind = "Milestone", milestone = "CleanEscapes", target = 25, medal = "Silver" } },
	{ "WPN_SP_SECRETHUNTER", "Secret Hunter Blaster", "Gun", "Won", { kind = "Milestone", milestone = "SecretCaught", target = 1, medal = "Gold" } },
}
local function stats(p: { number })
	return table.freeze({
		damage = p[1],
		rangeStuds = p[3],
		fireIntervalSeconds = p[2],
		projectileSpeedStudsPerSecond = 500,
		projectileSpeedAuthority = "PresentationOnly",
		assistAcquireHalfAngleRadians = math.rad(10),
		assistRetainHalfAngleRadians = math.rad(16),
	})
end
local function buildDefinitions(v2: boolean): ({ any }, { [string]: any })
	local ordered, byId = {}, {}
	for _, row in rows do
		local p = profiles[row[4]]
		local profileId = row[4]
		local revision = 13
		if v2 then
			local id, family = tostring(row[1]), tostring(row[3])
			local tier = assert(TiersV2.TierFromWeaponId(id), "WeaponTiersV2: no tier for " .. id)
			local v =
				assert(TiersV2.ProfileFor(family, tier), "WeaponTiersV2: no profile for " .. id)
			p = { v.damage, v.fireIntervalSeconds, v.rangeStuds }
			profileId = "V2_" .. string.sub(family, 1, 1) .. tostring(tier)
			revision = TiersV2.DefinitionRevision
		end
		local definition = table.freeze({
			id = row[1],
			displayName = row[2],
			family = row[3],
			profileId = profileId,
			price = row[5],
			definitionRevision = revision,
			starterEntitlement = row[1] == "HRP_001",
			assetName = row[1],
			stats = table.freeze({
				damage = p[1],
				rangeStuds = p[3],
				fireIntervalSeconds = p[2],
				projectileSpeedStudsPerSecond = 500,
				projectileSpeedAuthority = "PresentationOnly",
				assistAcquireHalfAngleRadians = math.rad(10),
				assistRetainHalfAngleRadians = math.rad(16),
			}),
		})
		table.insert(ordered, definition)
		byId[definition.id] = definition
	end
	for _, row in specialRows do
		local v = assert(TiersV2.SpecialProfile(row[1]), "WeaponTiersV2: no special profile for " .. row[1])
		local definition = table.freeze({
			id = row[1],
			displayName = row[2],
			family = row[3],
			profileId = "SP_" .. string.sub(row[1], 8),
			price = 0,
			definitionRevision = TiersV2.DefinitionRevision,
			starterEntitlement = false,
			assetName = row[1],
			special = table.freeze({ source = row[4], unlock = if table.isfrozen(row[5]) then row[5] else table.freeze(row[5]) }),
			stats = stats({ v.damage, v.fireIntervalSeconds, v.rangeStuds }),
		})
		byId[definition.id] = definition
	end
	return ordered, byId
end
local ordered, byId = buildDefinitions(TiersV2.Enabled())
local Weapons = { StarterWeaponId = "HRP_001", Definitions = table.freeze(byId), ConfigurationVersion = "P13_20261018" }
-- Pure builder for tests/tools: returns a fresh frozen id -> definition map for either path. It does
-- not change the active catalogue, which is fixed for the session from FeatureFlags.WeaponTiersV2Enabled.
function Weapons.BuildDefinitions(v2: boolean): { [string]: any }
	local _, built = buildDefinitions(v2 == true)
	return table.freeze(built)
end
function Weapons.Get(id: any): any
	return if type(id) == "string" then byId[id] else nil
end
-- The 24-row tier ladder (shops, ladder validation, retention goals). Specials are separate.
function Weapons.GetAll(): { any }
	return table.clone(ordered)
end
function Weapons.GetSpecials(): { any }
	local out = {}
	for _, row in specialRows do
		table.insert(out, byId[row[1]])
	end
	return out
end
function Weapons.IsSpecial(id: any): boolean
	local d = Weapons.Get(id)
	return d ~= nil and d.special ~= nil
end
-- Only Cash-bought ladder weapons can be sold back (25%). Never the starter, a special
-- (Premium Robux/Gem or Won), or anything unknown.
function Weapons.IsSellable(id: any): boolean
	local d = Weapons.Get(id)
	return d ~= nil and d.special == nil and not d.starterEntitlement and d.price > 0
end
function Weapons.Validate(): { string }
	local errors, families, starters = {}, { Bow = 0, Crossbow = 0, Gun = 0 }, 0
	for _, d in ordered do
		if byId[d.id] ~= d then
			table.insert(errors, "DUPLICATE_WEAPON_ID:" .. d.id)
		end
		if d.starterEntitlement then
			starters += 1
		end
		families[d.family] += 1
		if d.price < 0 or d.price % 1 ~= 0 then
			table.insert(errors, "INVALID_PRICE:" .. d.id)
		end
		for _, key in
			{
				"damage",
				"rangeStuds",
				"fireIntervalSeconds",
				"projectileSpeedStudsPerSecond",
				"assistAcquireHalfAngleRadians",
				"assistRetainHalfAngleRadians",
			}
		do
			local v = d.stats[key]
			if type(v) ~= "number" or v ~= v or v <= 0 or math.abs(v) == math.huge then
				table.insert(errors, "INVALID_" .. key .. ":" .. d.id)
			end
		end
	end
	if starters ~= 1 then
		table.insert(errors, "INVALID_STARTER_COUNT")
	end
	for family, n in families do
		if n ~= 8 then
			table.insert(errors, "INVALID_FAMILY_COUNT:" .. family)
		end
	end
	for _, row in specialRows do
		local d = byId[row[1]]
		if not d or not d.special or string.sub(row[1], 1, 7) ~= "WPN_SP_" then
			table.insert(errors, "INVALID_SPECIAL:" .. row[1])
		elseif TiersV2.TierFromWeaponId(row[1]) ~= nil then
			table.insert(errors, "SPECIAL_ON_LADDER:" .. row[1])
		elseif families[d.family] == nil then
			table.insert(errors, "INVALID_SPECIAL_FAMILY:" .. row[1])
		end
	end
	table.sort(errors)
	return errors
end
return table.freeze(Weapons)
