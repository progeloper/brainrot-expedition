--!strict

local WorldProgression=require(script.Parent.WorldProgression)
local operational={REGION_FOREST=true}
for _,key in WorldProgression.OperationalKeys do operational[WorldProgression.ByKey[key].regionId]=true end

export type RegionKind = "Hunting" | "Hub"

export type TierWeights = {
	Common: number,
	Uncommon: number,
	Rare: number,
	Epic: number,
	Legendary: number,
	Mythic: number,
	Secret: number,
}

export type SpawnSelectionConfig = {
	tierWeights: TierWeights,
	speciesWeightOverrides: { [string]: number },
}

export type RegionDefinition = {
	id: string,
	displayName: string,
	kind: RegionKind,
	enabled: boolean,
	naturalSpawnAllowed: boolean,
	boundaryRefs: { string },
	spawnAreaRefs: { string },
	-- Camp deliberately has no selection; every hunting region uses the approved
	-- current-region workbook distribution.
	spawnSelection: SpawnSelectionConfig?,
}

type SourceRow = { [number]: any }

-- These references point at the existing Studio-authored MapBlockout folders.
-- RegionSpawnCatalog accepts only their CreateBasicMap floor Parts, so art and
-- props added below a biome folder do not silently become spatial authority.
local rows: { SourceRow } = {
	{
		"REGION_BEACH",
		"Beach",
		"Hunting",
		true,
		true,
		{ "MapBlockout/Beach" },
		{ "MapBlockout/Beach" },
		{
			tierWeights = {
				Common = 0.724,
				Uncommon = 0.266,
				Rare = 0,
				Epic = 0.01,
				Legendary = 0,
				Mythic = 0,
				Secret = 0,
			},
			speciesWeightOverrides = {},
		},
	},
	{
		"REGION_FOREST",
		"Forest",
		"Hunting",
		true,
		true,
		{ "MapBlockout/Forest" },
		{ "MapBlockout/Forest" },
		{
			tierWeights = {
				Common = 0.687,
				Uncommon = 0.253,
				Rare = 0.06,
				Epic = 0,
				Legendary = 0,
				Mythic = 0,
				Secret = 0,
			},
			speciesWeightOverrides = {},
		},
	},
	{
		"REGION_SWAMP",
		"Swamp",
		"Hunting",
		true,
		true,
		{ "MapBlockout/Swamp" },
		{ "MapBlockout/Swamp" },
		{
			tierWeights = {
				Common = 0.43,
				Uncommon = 0.355,
				Rare = 0.215,
				Epic = 0,
				Legendary = 0,
				Mythic = 0,
				Secret = 0,
			},
			speciesWeightOverrides = {},
		},
	},
	{
		"REGION_JUNGLE",
		"Jungle",
		"Hunting",
		true,
		true,
		{ "MapBlockout/Jungle" },
		{ "MapBlockout/Jungle" },
		{
			tierWeights = {
				Common = 0.404,
				Uncommon = 0.333,
				Rare = 0.202,
				Epic = 0.061,
				Legendary = 0,
				Mythic = 0,
				Secret = 0,
			},
			speciesWeightOverrides = {},
		},
	},
	{
		"REGION_ARCTIC",
		"Arctic",
		"Hunting",
		true,
		true,
		{ "MapBlockout/Arctic" },
		{ "MapBlockout/Arctic" },
		{
			tierWeights = {
				Common = 0.231,
				Uncommon = 0.359,
				Rare = 0.41,
				Epic = 0,
				Legendary = 0,
				Mythic = 0,
				Secret = 0,
			},
			speciesWeightOverrides = {},
		},
	},
	{
		"REGION_VOLCANO",
		"Volcano",
		"Hunting",
		true,
		true,
		{ "MapBlockout/Volcano" },
		{ "MapBlockout/Volcano" },
		{
			tierWeights = {
				Common = 0.189,
				Uncommon = 0.295,
				Rare = 0.337,
				Epic = 0.179,
				Legendary = 0,
				Mythic = 0,
				Secret = 0,
			},
			speciesWeightOverrides = {},
		},
	},
	{
		"REGION_GLITCH",
		"Glitch Zone",
		"Hunting",
		true,
		true,
		{ "MapBlockout/Glitch Zone" },
		{ "MapBlockout/Glitch Zone" },
		{
			tierWeights = {
				Common = 0,
				Uncommon = 0,
				Rare = 0.425,
				Epic = 0.4,
				Legendary = 0.175,
				Mythic = 0,
				Secret = 0,
			},
			speciesWeightOverrides = {},
		},
	},
	{ "REGION_CAMP", "Camp", "Hub", true, false, { "MapBlockout/Camp" }, {}, nil },
}

local ordered: { RegionDefinition } = {}
local byId: { [string]: RegionDefinition } = {}
local aliases: { [string]: string } = {}

local function aliasKey(rawId: unknown): string?
	if type(rawId) ~= "string" then
		return nil
	end
	local trimmed = string.match(rawId, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return nil
	end
	return string.lower(trimmed)
end

local function freezeSpawnSelection(value: any): SpawnSelectionConfig?
	if value == nil then
		return nil
	end
	local tierWeights = table.freeze(table.clone(value.tierWeights or {}))
	local speciesWeightOverrides = table.freeze(table.clone(value.speciesWeightOverrides or {}))
	return table.freeze({
		tierWeights = tierWeights,
		speciesWeightOverrides = speciesWeightOverrides,
	}) :: any
end

for _, row in rows do
	local definition: RegionDefinition = {
		id = row[1],
		displayName = row[2],
		kind = row[3],
		enabled = row[4],
		naturalSpawnAllowed = row[5],
		boundaryRefs = table.freeze(table.clone(row[6])),
		spawnAreaRefs = table.freeze(table.clone(row[7])),
		spawnSelection = freezeSpawnSelection(if operational[row[1]] and WorldProgression.Pools[row[1]]
			then {tierWeights=WorldProgression.Pools[row[1]].tierWeights,speciesWeightOverrides=WorldProgression.Pools[row[1]].speciesWeightOverrides} else row[8]),
	}
	assert(byId[definition.id] == nil, "Duplicate current region ID " .. definition.id)
	table.freeze(definition)
	byId[definition.id] = definition
	aliases[assert(aliasKey(definition.id))] = definition.id
	aliases[assert(aliasKey(definition.displayName))] = definition.id
	if definition.id == "REGION_GLITCH" then
		aliases[assert(aliasKey("GlitchZone"))] = definition.id
	end
	table.insert(ordered, definition)
end

table.freeze(ordered)
table.freeze(byId)
table.freeze(aliases)

local Regions = {
	Definitions = byId,
	ById = byId,
	Aliases = aliases,
	CampId = "REGION_CAMP",
}

function Regions.NormalizeId(rawId: unknown): string?
	local key = aliasKey(rawId)
	return if key then aliases[key] else nil
end

function Regions.Get(rawId: unknown): RegionDefinition?
	local id = Regions.NormalizeId(rawId)
	return if id then byId[id] else nil
end

function Regions.GetAll(): { RegionDefinition }
	return table.clone(ordered)
end

return table.freeze(Regions)
