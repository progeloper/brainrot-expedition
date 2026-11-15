--!strict

local Rarities = require(script.Parent.Rarities)
local WorldProgression = require(script.Parent.WorldProgression)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Environment = require(script.Parent.Environment)
-- Original workbook units are retained; Phase 13 publishes CPS ×1,000,000 and sale ×500,000.

export type Tier = Rarities.Rarity
export type ExpeditionRole = "Sprinter" | "Tracker" | "Wrangler" | "Hauler" | "Trickster" | "Lucky"

export type LaunchStatus = "Live" | "Teased"
export type RegionAssignmentStatus = "Approved" | "Pending" | "Conflict"

export type BehaviourId =
	"Wanderer"
	| "ReactiveRunner"
	| "Sprinter"
	| "Trickster"
	| "Hauler"
	| "Zigzag"
	| "Camouflage"
	| "DecoySplit"
	| "LegendaryPursuit"
	| "MythicEvent"
	| "Pending"

export type BrainrotDefinition = {
	id: string,
	displayName: string,
	tier: Tier,
	modelRef: string,
	cashPerSecond: number,
	originalCashPerSecond: number,
	originalSellValue: number,
	sellValue: number,
	launchStatus: LaunchStatus,
	behaviourId: BehaviourId,
	expeditionRole: ExpeditionRole,
	homeRegionId: string,
	allowedRegionIds: { string },
	regionAssignmentStatus: RegionAssignmentStatus,
	spawnEnabled: boolean,
	chariotEffect: any?,
	developmentFixture: boolean?,
}

type SourceRow = { [number]: any }

-- Phase 6A-1's single authoritative species declaration. Source IDs are retained here
-- only long enough to normalize them into the project's underscore-form canonical IDs.
local rows: { SourceRow } = {
	{ "BRT-001", "Bingus Baguette", "Common", "REGION_FOREST", "Sprinter", 1.8, 108, "Live" },
	{ "BRT-002", "Tralalero Toad", "Common", "REGION_BEACH", "Tracker", 2, 120, "Live" },
	{ "BRT-003", "Cappuccino Capybara", "Common", "REGION_SWAMP", "Wrangler", 2.2, 132, "Live" },
	{ "BRT-004", "Ballerina Banana", "Common", "REGION_BEACH", "Hauler", 2.3, 138, "Live" },
	{ "BRT-005", "Bombardiro Pigeon", "Common", "REGION_VOLCANO", "Trickster", 1.9, 114, "Live" },
	{ "BRT-006", "Spaghetti Crocodilo", "Common", "REGION_SWAMP", "Lucky", 1.8, 108, "Live" },
	{ "BRT-007", "Tung Tung Tung Sahur", "Common", "REGION_VOLCANO", "Sprinter", 2, 120, "Live" },
	{ "BRT-008", "Lirili Larila", "Common", "REGION_ARCTIC", "Tracker", 2.2, 132, "Live" },
	{ "BRT-009", "Chimpanzini Bananini", "Common", "REGION_JUNGLE", "Wrangler", 2.3, 138, "Live" },
	{ "BRT-010", "Talpa Di Fero", "Common", "REGION_FOREST", "Hauler", 1.9, 114, "Live" },
	{ "BRT-011", "Glorbo Fruttodrillo", "Uncommon", "REGION_JUNGLE", "Trickster", 4, 240, "Live" },
	{ "BRT-012", "Frigo Camelo", "Uncommon", "REGION_ARCTIC", "Lucky", 4.5, 270, "Live" },
	{ "BRT-013", "Cavallo Virtuoso", "Uncommon", "REGION_FOREST", "Sprinter", 5, 300, "Live" },
	{ "BRT-014", "Bandito Bobritto", "Uncommon", "REGION_SWAMP", "Tracker", 5.2, 312, "Live" },
	{
		"BRT-015",
		"Strawberelli Flamingelli",
		"Uncommon",
		"REGION_BEACH",
		"Wrangler",
		4.3,
		258,
		"Live",
	},
	{ "BRT-016", "Gorillo Subwoofero", "Uncommon", "REGION_JUNGLE", "Hauler", 4, 240, "Live" },
	{
		"BRT-017",
		"Orangutini Ananassini",
		"Uncommon",
		"REGION_VOLCANO",
		"Trickster",
		4.5,
		270,
		"Live",
	},
	{ "BRT-018", "Zibra Zubra Zibralini", "Uncommon", "REGION_FOREST", "Lucky", 5, 300, "Live" },
	{ "BRT-019", "Trenostruzzo Turbo 3000", "Rare", "REGION_SWAMP", "Sprinter", 10.8, 648, "Live" },
	{ "BRT-020", "Bisonte Giuppitere", "Rare", "REGION_ARCTIC", "Tracker", 12, 720, "Live" },
	{ "BRT-021", "Cacto Hipopotamo", "Rare", "REGION_VOLCANO", "Wrangler", 13.2, 792, "Live" },
	{ "BRT-022", "Trulimero Trulicina", "Rare", "REGION_JUNGLE", "Hauler", 13.8, 828, "Live" },
	{ "BRT-023", "Giraffa Celeste", "Rare", "REGION_GLITCH", "Trickster", 11.4, 684, "Live" },
	{ "BRT-024", "Nooo My Hotspot", "Rare", "REGION_FOREST", "Lucky", 10.8, 648, "Live" },
	{ "BRT-025", "Salamino Penguino", "Rare", "REGION_ARCTIC", "Sprinter", 12, 720, "Live" },
	{ "BRT-026", "Rhino Toasterino", "Epic", "REGION_JUNGLE", "Tracker", 36, 2160, "Live" },
	{ "BRT-027", "Tralalero Tralala", "Epic", "REGION_BEACH", "Wrangler", 40, 2400, "Live" },
	{ "BRT-028", "Tartaragno", "Epic", "REGION_GLITCH", "Hauler", 44, 2640, "Live" },
	{ "BRT-029", "Cocofanto Elefanto", "Epic", "REGION_VOLCANO", "Trickster", 46, 2760, "Live" },
	{ "BRT-030", "Tractoro Dinosauro", "Epic", "REGION_GLITCH", "Lucky", 38, 2280, "Live" },
	{ "BRT-031", "Odin Din Din Dun", "Legendary", "REGION_GLITCH", "Sprinter", 135, 8100, "Live" },
	{
		"BRT-032",
		"La Vaca Saturno Saturnita",
		"Legendary",
		"REGION_GLITCH",
		"Tracker",
		150,
		9000,
		"Live",
	},
	{
		"BRT-033",
		"Dragon Cannelloni",
		"Legendary",
		"REGION_ARCTIC",
		"Wrangler",
		165,
		9900,
		"Teased",
	},
	{ "BRT-034", "Orcalero Orcala", "Mythic", "REGION_BEACH", "Hauler", 720, 43200, "Teased" },
	{
		"BRT-035",
		"La Secret Combinasion",
		"Secret",
		"REGION_SWAMP",
		"Trickster",
		2250,
		135000,
		"Teased",
	},
}

local developmentFixtures: { [string]: BrainrotDefinition } = {}

local function fixturesEnabled(): boolean
	return RunService:IsStudio()
		and not Environment.IsProduction
		and ReplicatedStorage:GetAttribute("ShieldDevelopmentFixturesEnabled") == true
end

local function normalizeId(rawId: unknown): string?
	if type(rawId) ~= "string" then
		return nil
	end
	local trimmed = string.match(rawId, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return nil
	end
	local canonical = string.upper(trimmed):gsub("-", "_")
	if fixturesEnabled() and developmentFixtures[canonical] then
		return canonical
	end
	if not string.match(canonical, "^BRT_%d%d%d$") then
		return nil
	end
	return canonical
end

local ordered: { BrainrotDefinition } = {}
local byId: { [string]: BrainrotDefinition } = {}
local aliases: { [string]: string } = {}
local behaviourAssignments: { [string]: BehaviourId } = table.freeze({
	BRT_011 = "ReactiveRunner",
	BRT_012 = "ReactiveRunner",
	BRT_013 = "ReactiveRunner",
	BRT_014 = "ReactiveRunner",
	BRT_015 = "ReactiveRunner",
	BRT_016 = "ReactiveRunner",
	BRT_017 = "ReactiveRunner",
	BRT_018 = "ReactiveRunner",
	BRT_019 = "Sprinter",
	BRT_020 = "Sprinter",
	BRT_021 = "Sprinter",
	BRT_022 = "Sprinter",
	BRT_023 = "Sprinter",
	BRT_024 = "Sprinter",
	BRT_025 = "Sprinter",
	BRT_028 = "Camouflage",
	BRT_029 = "DecoySplit",
	BRT_031 = "LegendaryPursuit",
	BRT_032 = "LegendaryPursuit",
	BRT_033 = "LegendaryPursuit",
})

for _, row in rows do
	local id = assert(normalizeId(row[1]), "Invalid source roster ID")
	assert(byId[id] == nil, "Duplicate source roster ID " .. id)
	local definition: BrainrotDefinition = {
		id = id,
		displayName = row[2],
		tier = row[3],
		modelRef = id,
		originalCashPerSecond = row[6],
		originalSellValue = row[7],
		cashPerSecond = row[6] * 1000000,
		sellValue = row[7] * 500000,
		launchStatus = row[8],
		-- Explicit species assignment remains independent of rarity and equipped-team role.
		behaviourId = behaviourAssignments[id] or "Wanderer",
		expeditionRole = row[5],
		homeRegionId = WorldProgression.HomeBySpecies[id] or row[4],
		allowedRegionIds = WorldProgression.AllowedBySpecies[id] or table.freeze({ row[4] }),
		regionAssignmentStatus = "Approved",
		spawnEnabled = row[8] == "Live",
		chariotEffect = row[9], -- Optional future species effect; legacy rows keep their installed assignments.
	}
	table.freeze(definition)
	byId[id] = definition
	aliases[string.gsub(id, "_", "-")] = id
	table.insert(ordered, definition)
end

table.freeze(byId)
table.freeze(ordered)
table.freeze(aliases)

local Catalog: { [string]: any } = {
	Definitions = byId,
	ById = byId,
	Aliases = aliases,
}

function Catalog.NormalizeId(rawId: unknown): string?
	return normalizeId(rawId)
end

function Catalog.Get(rawId: unknown): BrainrotDefinition?
	local id = normalizeId(rawId)
	return if id then byId[id] or (if fixturesEnabled() then developmentFixtures[id] else nil) else nil
end

-- Explicit, transient Studio fixtures exercise the real ownership/asset/equip
-- pipeline. They never join GetAll(), Definitions, spawn pools or release offers.
function Catalog.RegisterDevelopmentFixtures(definitions: { BrainrotDefinition })
	assert(fixturesEnabled(), "Development fixtures require an explicit non-production Studio override")
	local Effects = require(script.Parent.ChariotEffectDefinitions)
	local nextFixtures = {}
	for _, definition in definitions do
		assert(
			type(definition.id) == "string" and string.match(definition.id, "^FIXTURE_[A-Z0-9_]+$"),
			"Use an unmistakable FIXTURE_ identifier"
		)
		assert(
			definition.developmentFixture == true and definition.spawnEnabled == false,
			"Fixtures cannot enter release pools"
		)
		assert(
			type(definition.modelRef) == "string" and type(definition.displayName) == "string",
			"Fixture presentation is required"
		)
		local valid, reason = Effects.ValidateSpeciesEffect(definition.chariotEffect)
		assert(valid, reason or "Invalid fixture effect")
		assert(nextFixtures[definition.id] == nil, "Duplicate fixture identifier")
		nextFixtures[definition.id] = table.freeze(table.clone(definition))
	end
	developmentFixtures = nextFixtures
end

function Catalog.ClearDevelopmentFixtures()
	table.clear(developmentFixtures)
end

function Catalog.GetAll(): { BrainrotDefinition }
	return table.clone(ordered)
end

function Catalog.GetRarity(rawId: unknown): Rarities.Rarity?
	local definition = Catalog.Get(rawId)
	return if definition then definition.tier else nil
end

function Catalog.IsDeclaredSpawnEnabled(rawId: unknown): boolean
	local definition = Catalog.Get(rawId)
	return definition ~= nil and definition.spawnEnabled
end

-- Legacy helpers delegate to the same frozen definitions.
function Catalog.ResolveId(rawId: unknown): (string?, string?)
	local id = normalizeId(rawId)
	if id == nil then
		return nil, "invalid species identifier"
	end
	if Catalog.Get(id) == nil then
		return nil, "unknown species " .. id
	end
	return id, nil
end

function Catalog.GetDefinition(rawId: unknown): (BrainrotDefinition?, string?)
	local id, reason = Catalog.ResolveId(rawId)
	return if id then Catalog.Get(id) else nil, reason
end

Catalog.GetById = Catalog.GetDefinition

function Catalog.GetCashPerSecond(rawId: unknown): (number?, string?)
	local definition, reason = Catalog.GetDefinition(rawId)
	return if definition then definition.cashPerSecond else nil, reason
end

-- Retained for existing callers. The reusable validator remains the validation owner.
function Catalog.Validate(source: any?): any
	local Validator = require(script.Parent.Parent.Validation.BrainrotCatalogValidator)
	local definitions = if source == nil then Catalog.GetAll() else {}
	if source ~= nil then
		for _, definition in source do
			table.insert(definitions, definition)
		end
	end
	local report = Validator.ValidateDefinitions(definitions)
	local errors = {}
	for _, item in report.errors do
		table.insert(errors, string.format("%s: %s", item.code, item.message))
	end
	return {
		IsValid = #errors == 0,
		Errors = errors,
		InvalidDefinitions = {},
		ValidAliases = aliases,
	}
end

for id, definition in byId do
	Catalog[id] = definition
end

return table.freeze(Catalog)
