--!strict
-- Fallback sleep thresholds for representations without authoritative Phase12 HP.
-- Existing Phase12 HP, accepted weapon damage and team rules remain authoritative.
local requiredHits: { [string]: number } = {}
for index = 1, 35 do
	requiredHits[string.format("BRT_%03d", index)] = 1
end

return table.freeze({
	DefaultRequiredHits = 1,
	RequiredHitsBySpecies = table.freeze(requiredHits),
	MaximumHitMultiplier = 5,
})
