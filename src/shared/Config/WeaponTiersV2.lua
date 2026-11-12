--!strict
-- Weapon Tiers V2 (owner-approved design, 11 Nov 2026). Gated by FeatureFlags.WeaponTiersV2Enabled.
-- With the flag off nothing here is consulted: brainrot HP and weapon stats stay exactly as before.
--   HP = Phase12.HpByRarity[tier] x RegionHpMultiplier[spawn/population region] (unknown/nil region -> 1)
--   Every weapon tier (the two-digit number in its ID; HRP_001 is Bow tier 1) gets its own profile.
-- Prices, IDs, names, families, ownership and receipts are unchanged.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FeatureFlags = require(script.Parent.FeatureFlags)

export type TierProfile = { damage: number, fireIntervalSeconds: number, rangeStuds: number }

-- Bumped only on the V2 path so V2 captured shot profiles never compare equal to legacy ones.
local DEFINITION_REVISION = 14

local RegionHpMultiplier = table.freeze({
	REGION_FOREST = 1,
	REGION_BEACH = 4,
	REGION_SWAMP = 10,
	REGION_JUNGLE = 25,
	REGION_ARCTIC = 70,
	REGION_VOLCANO = 200,
	REGION_GLITCH = 550,
})

-- { damage, fireIntervalSeconds, rangeStuds } for tiers 1..8. "Gun" is the Blaster family.
local rawProfiles: { [string]: { { number } } } = {
	Bow = {
		{ 1, 0.75, 90 },
		{ 2, 0.70, 95 },
		{ 5, 0.66, 100 },
		{ 12, 0.62, 105 },
		{ 30, 0.58, 110 },
		{ 80, 0.55, 115 },
		{ 220, 0.52, 120 },
		{ 600, 0.50, 130 },
	},
	Crossbow = {
		{ 2, 1.30, 110 },
		{ 4, 1.24, 115 },
		{ 10, 1.18, 120 },
		{ 24, 1.12, 125 },
		{ 60, 1.06, 130 },
		{ 160, 1.00, 135 },
		{ 440, 0.95, 140 },
		{ 1200, 0.90, 150 },
	},
	Gun = {
		{ 1, 0.38, 65 },
		{ 1, 0.36, 68 },
		{ 2, 0.34, 70 },
		{ 6, 0.32, 72 },
		{ 15, 0.30, 75 },
		{ 40, 0.28, 78 },
		{ 110, 0.26, 80 },
		{ 300, 0.25, 85 },
	},
}

local profiles: { [string]: { TierProfile } } = {}
for family, rows in rawProfiles do
	local list: { TierProfile } = {}
	for tier, row in rows do
		list[tier] =
			table.freeze({ damage = row[1], fireIntervalSeconds = row[2], rangeStuds = row[3] })
	end
	profiles[family] = table.freeze(list)
end

-- Latched once per session so HP and weapon definitions can never disagree mid-session.
-- In Studio only, the ReplicatedStorage attribute WeaponTiersV2Preview = true enables an isolated
-- preview (same pattern as VoxelCreaturesV4Preview); live servers only read the flag.
local active = FeatureFlags.WeaponTiersV2Enabled == true
	or (RunService:IsStudio() and ReplicatedStorage:GetAttribute("WeaponTiersV2Preview") == true)

-- Special weapons (Camp Rework, 12 Nov 2026) sit OFF the tier ladder: new IDs, never counted in
-- the 8-per-family checks, never returned by TierFromWeaponId. Each borrows a tier's power.
-- powerTier is used only to look up the borrowed profile; `profile` overrides it outright.
export type SpecialRow = {
	id: string,
	family: string,
	powerTier: number,
	source: string, -- "Premium" | "Won"
	profile: TierProfile?,
}
local specials: { [string]: SpecialRow } = {
	WPN_SP_RIFTBLASTER = { id = "WPN_SP_RIFTBLASTER", family = "Gun", powerTier = 5, source = "Premium" },
	-- Tier 4 Crossbow power with 2x fire rate and half damage.
	WPN_SP_PRISMREPEATER = {
		id = "WPN_SP_PRISMREPEATER",
		family = "Crossbow",
		powerTier = 4,
		source = "Premium",
		profile = { damage = 12, fireIntervalSeconds = 0.56, rangeStuds = 125 },
	},
	WPN_SP_CRYSTALLANCE = { id = "WPN_SP_CRYSTALLANCE", family = "Crossbow", powerTier = 6, source = "Premium" },
	WPN_SP_COLLECTORSBOW = { id = "WPN_SP_COLLECTORSBOW", family = "Bow", powerTier = 3, source = "Won" },
	WPN_SP_GETAWAY = { id = "WPN_SP_GETAWAY", family = "Crossbow", powerTier = 5, source = "Won" },
	WPN_SP_SECRETHUNTER = { id = "WPN_SP_SECRETHUNTER", family = "Gun", powerTier = 7, source = "Won" },
}
for id, row in specials do
	if row.profile then
		row.profile = table.freeze(row.profile :: any)
	end
	specials[id] = table.freeze(row)
end

local WeaponTiersV2 = {
	DefinitionRevision = DEFINITION_REVISION,
	Specials = table.freeze(specials),
	RegionHpMultiplier = RegionHpMultiplier,
	Profiles = table.freeze(profiles),
	Families = table.freeze({ "Bow", "Crossbow", "Gun" }),
	TierCount = 8,
}

function WeaponTiersV2.Enabled(): boolean
	return active
end

-- HRP_001 -> 1, WPN_B02 -> 2, WPN_C08 -> 8. Anything else (including WPN_SP_* specials) -> nil.
function WeaponTiersV2.TierFromWeaponId(weaponId: any): number?
	if type(weaponId) ~= "string" then
		return nil
	end
	local digits = if weaponId == "HRP_001"
		then "01"
		else string.match(weaponId, "^WPN_[BCG](%d%d)$")
	local tier = if digits then tonumber(digits) else nil
	return if tier and tier >= 1 and tier <= WeaponTiersV2.TierCount then tier else nil
end

function WeaponTiersV2.IsSpecial(weaponId: any): boolean
	return type(weaponId) == "string" and specials[weaponId] ~= nil
end

-- A special's stats: its explicit profile, else the borrowed tier profile of its family.
function WeaponTiersV2.SpecialProfile(weaponId: any): TierProfile?
	local row = if type(weaponId) == "string" then specials[weaponId] else nil
	if not row then
		return nil
	end
	if row.profile then
		return row.profile
	end
	local list = profiles[row.family]
	return if list then list[row.powerTier] else nil
end

function WeaponTiersV2.ProfileFor(family: any, tier: any): TierProfile?
	local list = if type(family) == "string" then profiles[family] else nil
	return if list and type(tier) == "number" then list[tier] else nil
end

function WeaponTiersV2.HpMultiplierForRegion(regionId: any): number
	local multiplier = if type(regionId) == "string"
		then (RegionHpMultiplier :: any)[regionId]
		else nil
	return if type(multiplier) == "number" then multiplier else 1
end

return table.freeze(WeaponTiersV2)
