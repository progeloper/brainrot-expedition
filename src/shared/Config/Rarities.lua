--!strict

export type StandardRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Celestial"
export type Rarity = StandardRarity | "Secret"

local standardOrder: { StandardRarity } = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Celestial",
}
local displayOrder: { Rarity } = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Celestial",
	"Secret",
}

local canonicalByLower: { [string]: Rarity } = {}
local standardRankByRarity: { [string]: number } = {}
local displayRankByRarity: { [string]: number } = {}
local legacyTierToRarity: { [number]: StandardRarity } = {}

for rank, rarity in standardOrder do
	canonicalByLower[string.lower(rarity)] = rarity
	standardRankByRarity[rarity] = rank
	if rank<=6 then legacyTierToRarity[rank] = rarity end
end
canonicalByLower.secret = "Secret"
for rank, rarity in displayOrder do
	displayRankByRarity[rarity] = rank
end

table.freeze(standardOrder)
table.freeze(displayOrder)
table.freeze(canonicalByLower)
table.freeze(standardRankByRarity)
table.freeze(displayRankByRarity)
table.freeze(legacyTierToRarity)

local Rarities = {
	Common = "Common" :: Rarity,
	Uncommon = "Uncommon" :: Rarity,
	Rare = "Rare" :: Rarity,
	Epic = "Epic" :: Rarity,
	Legendary = "Legendary" :: Rarity,
	Mythic = "Mythic" :: Rarity,
	Celestial = "Celestial" :: Rarity,
	Secret = "Secret" :: Rarity,
	StandardOrder = standardOrder,
	DisplayOrder = displayOrder,
}

function Rarities.FromLegacyTier(value: unknown): Rarity?
	if
		type(value) ~= "number"
		or value ~= value
		or math.abs(value) == math.huge
		or value % 1 ~= 0
	then
		return nil
	end
	-- Only the six audited legacy tiers convert numerically. New Celestial is name based; Secret is
	-- deliberately absent from this ordinary-tier compatibility boundary.
	return legacyTierToRarity[value]
end

function Rarities.Normalize(value: unknown): Rarity?
	if type(value) ~= "string" then
		return nil
	end
	local trimmed = string.match(value, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return nil
	end
	return canonicalByLower[string.lower(trimmed)]
end

function Rarities.IsValid(value: unknown): boolean
	return type(value) == "string" and canonicalByLower[string.lower(value)] == value
end

function Rarities.IsStandard(value: unknown): boolean
	local rarity = Rarities.Normalize(value)
	return rarity ~= nil and standardRankByRarity[rarity] ~= nil
end

function Rarities.GetStandardRank(value: unknown): number?
	local rarity = Rarities.Normalize(value)
	return if rarity then standardRankByRarity[rarity] else nil
end

function Rarities.GetDisplayRank(value: unknown): number?
	local rarity = Rarities.Normalize(value)
	return if rarity then displayRankByRarity[rarity] else nil
end

return table.freeze(Rarities)
