--!strict

local Config = require(script.Parent.Parent.Config.PlayerDataConfig)

local Money = require(game.ReplicatedStorage.Shared.Utility.CurrencyDenomination)
local WorldRules = require(game.ReplicatedStorage.Shared.Utility.WorldProgressionRules)
local TeamRules = require(game.ReplicatedStorage.Shared.Utility.ChariotTeamRules)
local Catalog = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Phase12Progress = require(script.Parent.Phase12Progress)
local VFXSettings = require(game.ReplicatedStorage.Shared.Utility.VFXSettingsProtocol)
local Phase13Rules = require(game.ReplicatedStorage.Shared.Utility.Phase13Rules)
local CommerceRules = require(game.ReplicatedStorage.Shared.Utility.Phase13CommerceRules)
local RetentionRules = require(game.ReplicatedStorage.Shared.Utility.RetentionRules)
local GemRules = require(game.ReplicatedStorage.Shared.Utility.GemRules)
local Schema = {}
local SLOT_COUNT = 12

local function finiteNonNegative(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= Config.MaxBalance
		and math.abs(value) < math.huge
end

local function cloneSerializable(value: any, seen: { [any]: boolean }): (any?, string?)
	local valueType = type(value)
	if valueType == "nil" or valueType == "string" or valueType == "boolean" then
		return value, nil
	end
	if valueType == "number" then
		if value ~= value or math.abs(value) == math.huge then
			return nil, "NON_FINITE_NUMBER"
		end
		return value, nil
	end
	if valueType ~= "table" then
		return nil, "UNSERIALIZABLE_VALUE"
	end
	if seen[value] then
		return nil, "CYCLIC_TABLE"
	end
	seen[value] = true
	local copy = {}
	for key, nested in value do
		local keyType = type(key)
		if keyType ~= "string" and keyType ~= "number" then
			seen[value] = nil
			return nil, "UNSERIALIZABLE_KEY"
		end
		local nestedCopy, reason = cloneSerializable(nested, seen)
		if reason then
			seen[value] = nil
			return nil, reason
		end
		copy[key] = nestedCopy
	end
	seen[value] = nil
	return copy, nil
end

function Schema.CreateDefault(): any
	local data = {
		SchemaVersion = Config.SchemaVersion,
		Settings = VFXSettings.Default(),
		CurrencyVersion = 2,
		WorldReadyPlaytimeSeconds = 0,
		WorldProgression = WorldRules.CreateDefault(),
		ChariotTeam = TeamRules.Default(),
		Economy = {
			Balance = Config.StartingBalance,
		},
		Collection = {
			BrainrotInstances = {},
			Species = {},
			Mutations = {},
			SpeciesMutations = {},
		},
		Progression = {
			Upgrades = {},
			ExpeditionBest = { haulCount = 0, cashPerSecond = 0, sellValue = 0 },
		},
		Base = Schema.CreateDefaultBaseData(48),
	}
	data.Phase13 = Phase13Rules.Default()
	local ok, reason = CommerceRules.Migrate(data)
	assert(ok, reason)
	data.Retention = RetentionRules.Default()
	GemRules.Migrate(data)
	return data
end

function Schema.CreateDefaultBaseData(count: number?): any
	local slots = {}
	for index = 1, count or SLOT_COUNT do
		slots[tostring(index)] = { accumulatedCash = 0 }
	end
	return { Slots = slots }
end

local function validIndividualId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= 128 and value:match("%c") == nil
end

local function validSpeciesId(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	-- Preserve unknown canonical species in saves. The extra path is only the
	-- explicitly enabled, registered transient Studio fixture catalogue; its
	-- adapter returns nil outside that development override, including Production.
	if value:match("^BRT_%d%d%d$") ~= nil then
		return true
	end
	local definition = Catalog.Get(value)
	return Catalog.NormalizeId(value) == value
		and definition ~= nil
		and definition.developmentFixture == true
		and definition.spawnEnabled == false
end

function Schema.ValidateBaseData(rawData: any): (boolean, string?)
	if type(rawData.Collection) ~= "table" or type(rawData.Collection.BrainrotInstances) ~= "table" then
		return false, "OWNED_BRAINROTS_NOT_TABLE"
	end
	local owned = rawData.Collection.BrainrotInstances
	for individualId, record in owned do
		if not validIndividualId(individualId) then
			return false, "INVALID_INDIVIDUAL_ID"
		end
		if type(record) ~= "table" or not validSpeciesId(record.speciesId) then
			return false, "INVALID_OWNED_BRAINROT"
		end
		if record.metadata ~= nil and type(record.metadata) ~= "table" then
			return false, "INVALID_INDIVIDUAL_METADATA"
		end
		-- Favourite lock (12 Nov 2026): absent, or exactly true. Set only by
		-- BankedBrainrotService:SetFavourite; a favourite cannot be sold.
		if record.favourite ~= nil and record.favourite ~= true then
			return false, "INVALID_INDIVIDUAL_FAVOURITE"
		end
	end
	if type(rawData.Base) ~= "table" or type(rawData.Base.Slots) ~= "table" then
		return false, "BASE_SLOTS_NOT_TABLE"
	end
	local referenced = {}
	local slotLimit = if rawData.Phase13 then 48 else SLOT_COUNT
	local slotCount = 0
	for key, slot in rawData.Base.Slots do
		local index = if type(key) == "string" then tonumber(key) else nil
		if not index or index % 1 ~= 0 or index < 1 or index > slotLimit or key ~= tostring(index) then
			return false, "INVALID_SLOT_ID"
		end
		slotCount += 1
		if type(slot) ~= "table" or not finiteNonNegative(slot.accumulatedCash) then
			return false, "INVALID_SLOT_BALANCE"
		end
		-- Valid unavailable legacy records remain owned and serializable. Runtime
		-- storage diagnoses/skips them; they are not permission to collect or move.
		local individualId = slot.brainrotId
		if individualId ~= nil then
			if not validIndividualId(individualId) or owned[individualId] == nil then
				return false, "MISSING_OWNED_BRAINROT"
			end
			if referenced[individualId] then
				return false, "DUPLICATE_SLOT_REFERENCE"
			end
			referenced[individualId] = true
		end
	end
	if slotCount ~= slotLimit then
		return false, "MISSING_BASE_SLOT"
	end
	return true, nil
end

function Schema.MigrateBaseData(rawData: any): (boolean, string?)
	if type(rawData) ~= "table" then
		return false, "PROFILE_NOT_TABLE"
	end
	if rawData.Collection == nil then
		rawData.Collection = {}
	elseif type(rawData.Collection) ~= "table" then
		return false, "OWNED_BRAINROTS_NOT_TABLE"
	end
	if rawData.Collection.BrainrotInstances == nil then
		rawData.Collection.BrainrotInstances = {}
	elseif type(rawData.Collection.BrainrotInstances) ~= "table" then
		return false, "OWNED_BRAINROTS_NOT_TABLE"
	end
	if rawData.Base == nil then
		rawData.Base = Schema.CreateDefaultBaseData()
	elseif type(rawData.Base) ~= "table" then
		return false, "BASE_SLOTS_NOT_TABLE"
	elseif rawData.Base.Slots == nil then
		rawData.Base.Slots = Schema.CreateDefaultBaseData().Slots
	elseif type(rawData.Base.Slots) ~= "table" then
		return false, "BASE_SLOTS_NOT_TABLE"
	else
		for index = 1, SLOT_COUNT do
			local key = tostring(index)
			if rawData.Base.Slots[key] == nil then
				rawData.Base.Slots[key] = { accumulatedCash = 0 }
			end
		end
	end
	return Schema.ValidateBaseData(rawData)
end

function Schema.ValidateLoaded(rawData: any): (boolean, string?)
	if type(rawData) ~= "table" then
		return false, "PROFILE_NOT_TABLE"
	end
	if rawData.SchemaVersion ~= Config.SchemaVersion then
		return false,
			if type(rawData.SchemaVersion) == "number" and rawData.SchemaVersion > Config.SchemaVersion
				then "UNSUPPORTED_NEWER_SCHEMA"
				else "UNSUPPORTED_SCHEMA"
	end
	if rawData.WorldReadyPlaytimeSeconds ~= nil and (not finiteNonNegative(rawData.WorldReadyPlaytimeSeconds)) then
		return false, "INVALID_WORLD_READY_PLAYTIME"
	end
	if type(rawData.Economy) ~= "table" then
		return false, "ECONOMY_NOT_TABLE"
	end
	if rawData.CurrencyVersion ~= nil and rawData.CurrencyVersion ~= 1 and rawData.CurrencyVersion ~= 2 then
		return false, "UNSUPPORTED_CURRENCY_VERSION"
	end
	if not finiteNonNegative(rawData.Economy.Balance) then
		return false, "INVALID_BALANCE"
	end
	local validGems, gemReason = GemRules.Validate(rawData)
	if not validGems then
		return false, gemReason
	end
	-- Historical profiles may omit these optional containers. A present malformed
	-- value is corruption, not permission for a gameplay grant to replace it.
	if rawData.Progression ~= nil then
		if type(rawData.Progression) ~= "table" then
			return false, "PROGRESSION_NOT_TABLE"
		end
		if rawData.Progression.Upgrades ~= nil and type(rawData.Progression.Upgrades) ~= "table" then
			return false, "UPGRADES_NOT_TABLE"
		end
	end
	local validBase, baseReason = Schema.ValidateBaseData(rawData)
	if not validBase then
		return false, baseReason
	end
	if rawData.Phase13 ~= nil then
		local valid, reason = Phase13Rules.Validate(rawData)
		if not valid then
			return false, reason
		end
	end
	if rawData.Commerce ~= nil then
		local valid, reason = CommerceRules.Validate(rawData)
		if not valid then
			return false, reason
		end
	end
	local validRetention, retentionReason = RetentionRules.Validate(rawData)
	if not validRetention then return false, retentionReason end
	local validProgress, progressReason = Phase12Progress.Validate(rawData)
	if not validProgress then
		return false, progressReason
	end
	local _, serializableReason = cloneSerializable(rawData, {})
	if serializableReason then
		return false, serializableReason
	end
	return true, nil
end

-- Validate before applying this approved semantic migration. In particular,
-- malformed/negative balances must not be disguised as an empty-slot reset.
local function normalizeEmptySlotCash(_data: any): boolean
	-- Phase 8: the balance belongs to the platform and survives occupant removal.
	return false
end

function Schema.MigrateSchema(rawData: any): (any?, string?, boolean?)
	if type(rawData) ~= "table" then
		return nil, "PROFILE_NOT_TABLE", nil
	end
	if rawData.SchemaVersion == Config.SchemaVersion then
		local valid, reason = Schema.ValidateLoaded(rawData)
		if not valid then
			return nil, reason, nil
		end
		local copy, copyReason = cloneSerializable(rawData, {})
		if copyReason then
			return nil, copyReason, nil
		end
		return copy, nil, normalizeEmptySlotCash(copy)
	end

	if rawData.SchemaVersion == 1 then
		local migrated, copyReason = cloneSerializable(rawData, {})
		if copyReason then
			return nil, copyReason, nil
		end
		migrated.SchemaVersion = Config.SchemaVersion
		local baseValid, baseReason = Schema.MigrateBaseData(migrated)
		if not baseValid then
			return nil, baseReason, nil
		end
		local valid, reason = Schema.ValidateLoaded(migrated)
		if valid then
			normalizeEmptySlotCash(migrated)
		end
		return if valid then migrated else nil, reason, if valid then true else nil
	end

	-- Version zero is the pre-profile runtime account shape used by the existing
	-- CurrencySystem. It was not a deployed DataStore format, but supporting it
	-- gives controlled test/import tooling one explicit, non-ambiguous bridge.
	if rawData.SchemaVersion == 0 then
		if rawData.Economy ~= nil and type(rawData.Economy) ~= "table" then
			return nil, "ECONOMY_NOT_TABLE", nil
		end
		local legacyBalance = rawData.Balance
		local nestedBalance = if type(rawData.Economy) == "table" then rawData.Economy.Balance else nil
		if nestedBalance ~= nil and nestedBalance ~= legacyBalance then
			return nil, "CONFLICTING_LEGACY_BALANCE", nil
		end
		if not finiteNonNegative(legacyBalance) then
			return nil, "INVALID_BALANCE", nil
		end
		local migrated, copyReason = cloneSerializable(rawData, {})
		if copyReason then
			return nil, copyReason, nil
		end
		migrated.SchemaVersion = Config.SchemaVersion
		migrated.Balance = nil
		if migrated.Economy == nil then
			migrated.Economy = {}
		end
		migrated.Economy.Balance = legacyBalance
		local baseValid, baseReason = Schema.MigrateBaseData(migrated)
		if not baseValid then
			return nil, baseReason, nil
		end
		local valid, reason = Schema.ValidateLoaded(migrated)
		if valid then
			normalizeEmptySlotCash(migrated)
		end
		return if valid then migrated else nil, reason, if valid then true else nil
	end

	return nil,
		if type(rawData.SchemaVersion) == "number" and rawData.SchemaVersion > Config.SchemaVersion
			then "UNSUPPORTED_NEWER_SCHEMA"
			else "UNSUPPORTED_SCHEMA",
		nil
end

function Schema.Migrate(rawData: any): (any?, string?, boolean?)
	local data, reason, schemaChanged = Schema.MigrateSchema(rawData)
	if not data then
		return nil, reason, nil
	end
	local validMoney, moneyReason, moneyChanged = Money.MigrateRecord(data)
	if not validMoney then
		return nil, moneyReason, nil
	end
	local validWorld, worldReason, worldChanged = WorldRules.Migrate(data)
	if not validWorld then
		return nil, worldReason, nil
	end
	local playtimeChanged = data.WorldReadyPlaytimeSeconds == nil
	if playtimeChanged then
		data.WorldReadyPlaytimeSeconds = 0
	end
	local teamChanged = TeamRules.Migrate(data)
	local phase12Changed = Phase12Progress.Migrate(data)
	local phase13Ok, phase13Reason, phase13Changed = Phase13Rules.Migrate(data)
	if not phase13Ok then
		return nil, phase13Reason, nil
	end
	local commerceChanged = data.Commerce == nil
	local commerceOk, commerceReason = CommerceRules.Migrate(data)
	if not commerceOk then
		return nil, commerceReason, nil
	end
	local retentionOk, retentionReason, retentionChanged = RetentionRules.Migrate(data)
	if not retentionOk then return nil, retentionReason, nil end
	local settingsChanged = VFXSettings.MigrateProfile(data)
	local gemsChanged = GemRules.Migrate(data)
	return data,
		nil,
		gemsChanged
			or retentionChanged
			or phase13Changed
			or commerceChanged
			or settingsChanged
			or phase12Changed
			or schemaChanged == true
			or moneyChanged == true
			or worldChanged == true
			or teamChanged
			or playtimeChanged
end

function Schema.CreateSaveSnapshot(profileData: any): (any?, string?)
	if type(profileData) ~= "table" or profileData.CurrencyVersion ~= 2 then
		return nil, "UNSUPPORTED_WRITE_CURRENCY"
	end
	local valid, reason = Schema.ValidateLoaded(profileData)
	if not valid then
		return nil, reason
	end
	return cloneSerializable(profileData, {})
end

return table.freeze(Schema)
