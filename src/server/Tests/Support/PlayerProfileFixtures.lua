--!nocheck

-- Synthetic compatibility fixtures, not historical production player exports.
-- Versions 0/1 reconstruct documented supported migration shapes. Cart/weapon
-- ownership and selection are not current persistent source fields; do not add
-- fictional equipment state merely to claim coverage of an unreleased system.
local Schema = require(script.Parent.Parent.Parent.Data.PlayerProfileSchema)

local Fixtures = {}

function Fixtures.Clone(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, nested in value do
		copy[key] = Fixtures.Clone(nested)
	end
	return copy
end

function Fixtures.FullProfile(version, playerNumber)
	local number = playerNumber or 1
	local prefix = "synthetic-player-" .. number .. ":"
	local data = Schema.CreateDefault()
	data.Economy.Balance = if number == 1 then 1000.5 else 82.375
	data.Economy.SyntheticAuditTag = "preserve-unrelated-economy-field"
	data.Collection.BrainrotInstances = {
		[prefix .. "a"] = { speciesId = "BRT_001", metadata = { fixture = true, variant = "A" } },
		[prefix .. "b"] = { speciesId = "BRT_001", metadata = { fixture = true, variant = "B" } },
		[prefix .. "c"] = {
			speciesId = "BRT_999",
			metadata = { fixture = true, unknownDefinition = { preserve = "same-identity" } },
		},
		[prefix .. "d"] = { speciesId = "BRT_007", metadata = { labels = { "one", "two" } } },
	}
	data.Base.Slots["1"] = { brainrotId = prefix .. "a", accumulatedCash = 120.25 }
	data.Base.Slots["2"] = { brainrotId = prefix .. "b", accumulatedCash = 33.4 }
	data.Base.Slots["3"] = { brainrotId = prefix .. "c", accumulatedCash = 0.125 }
	-- Empty platforms retain money independently of occupant ownership.
	-- Explicit migration tests separately inject historical empty-slot balances.
	data.Base.Slots["4"] = { accumulatedCash = 0 }
	data.Base.Slots["12"] = { brainrotId = prefix .. "d", accumulatedCash = 0.5 * number }
	data.Progression.Upgrades = {
		CARGO_1 = true,
		CART_SPEED_1 = true,
		SYNTHETIC_UNKNOWN_UPGRADE = true,
	}
	data.Settings = { Music = false, Volume = 0.375, Input = { AimAssist = true } }
	data.SyntheticUnknownExtension = { revision = 17, nested = { "preserve", false, 4.125 } }
	data.WorldProgression.BankedSpecies = {
		BRT_001 = { rarityAtFirstBank = "Common", source = "legacy_bank_record" },
		BRT_007 = { rarityAtFirstBank = "Common", source = "legacy_bank_record" },
	}
	-- These synthetic schema-compatibility fixtures already use denomination 2;
	-- separate migration fixtures exercise genuinely legacy monetary amounts.
	if version == 0 then
		data.SchemaVersion = 0
		data.Balance = data.Economy.Balance
		data.Economy.Balance = nil
	elseif version == 1 then
		data.SchemaVersion = 1
	end
	return data
end


-- Independent expected extension for historical NORMAL synthetic profiles.
-- Do not invoke the migration under test or alter any historical field/value.
function Fixtures.WithPhase12ExpectedFields(source)
	local expected = Fixtures.Clone(source)
	-- Independent expected cosmetic defaults for old profiles; do not invoke
	-- the migration under test or change any existing unrelated preference.
	expected.Settings = expected.Settings or {}
	expected.Settings.VFXQuality = expected.Settings.VFXQuality or "Auto"
	if expected.Settings.ReducedMotion == nil then expected.Settings.ReducedMotion = false end
	expected.Collection.Species = expected.Collection.Species or {}
	expected.Collection.Mutations = expected.Collection.Mutations or {}
	expected.Collection.SpeciesMutations = expected.Collection.SpeciesMutations or {}
	for _, record in expected.Collection.BrainrotInstances do
		assert(record.mutationId == nil or record.mutationId == "None", "Expected fixture is a historical normal individual")
		record.mutationId, record.firstBankCompleted = "None", true
		record.metadata = record.metadata or {}
		record.metadata.MutationId, record.metadata.FirstBankCompleted = "None", true
		expected.Collection.Species[record.speciesId] = expected.Collection.Species[record.speciesId] or true
		expected.Collection.Mutations.Normal = expected.Collection.Mutations.Normal or true
		local mutations = expected.Collection.SpeciesMutations[record.speciesId] or {}
		mutations.Normal = mutations.Normal or true
		expected.Collection.SpeciesMutations[record.speciesId] = mutations
	end
	expected.Progression = expected.Progression or { Upgrades = {} }
	expected.Progression.ExpeditionBest = expected.Progression.ExpeditionBest or { haulCount = 0, cashPerSecond = 0, sellValue = 0 }
	return expected
end

function Fixtures.AssertDeepEqual(actual, expected, path)
	local currentPath = path or "profile"
	assert(type(actual) == type(expected), currentPath .. ": type changed")
	if type(expected) ~= "table" then
		assert(
			actual == expected or (actual ~= actual and expected ~= expected),
			currentPath .. ": value changed"
		)
		return
	end
	for key, value in expected do
		Fixtures.AssertDeepEqual(actual[key], value, currentPath .. "." .. tostring(key))
	end
	for key in actual do
		assert(expected[key] ~= nil, currentPath .. "." .. tostring(key) .. ": unexpected field")
	end
end

return table.freeze(Fixtures)
