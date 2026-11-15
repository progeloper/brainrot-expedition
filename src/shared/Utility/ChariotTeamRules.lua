--!strict
local Config = require(script.Parent.Parent.Config.ChariotTeam)
local Catalog = require(script.Parent.Parent.Config.BrainrotCatalog)
local Effects = require(script.Parent.Parent.Config.ChariotEffectDefinitions)
local Progression = require(script.Parent.Phase13Rules)
local Rules = {}
function Rules.Finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end
function Rules.ValidId(v: any): boolean
	return type(v) == "string" and #v > 0 and #v <= 128 and not v:find("%c")
end
function Rules.Default(): any
	local assignments = {}
	for i = 1, 6 do
		assignments[tostring(i)] = false
	end
	return { SchemaVersion = 1, PurchasedExtraSlots = 0, Assignments = assignments }
end
function Rules.Validate(team: any): (boolean, string?)
	if type(team) ~= "table" then
		return false, "TEAM_SHAPE_INVALID"
	end
	if team.SchemaVersion ~= 1 then
		return false, "TEAM_SCHEMA_UNSUPPORTED"
	end
	local n = team.PurchasedExtraSlots
	if not Rules.Finite(n) or n % 1 ~= 0 or n < 0 or n > 4 then
		return false, "TEAM_ENTITLEMENT_INVALID"
	end
	if type(team.Assignments) ~= "table" then
		return false, "TEAM_ASSIGNMENTS_INVALID"
	end
	for key, value in team.Assignments do
		local index = type(key) == "string" and tonumber(key)
		if not index or index % 1 ~= 0 or index < 1 or index > 6 or tostring(index) ~= key then
			return false, "TEAM_ASSIGNMENTS_INVALID"
		end
		if value ~= false and not Rules.ValidId(value) then
			return false, "TEAM_ASSIGNMENTS_INVALID"
		end
	end
	for i = 1, 6 do
		if team.Assignments[tostring(i)] == nil then
			return false, "TEAM_ASSIGNMENTS_INVALID"
		end
	end
	return true, nil
end
function Rules.Migrate(data: any): boolean
	if data.ChariotTeam == nil then
		data.ChariotTeam = Rules.Default()
		return true
	end
	-- Malformed/newer data is preserved. Only this subsystem becomes unavailable.
	return false
end
function Rules.Platform(data: any, id: string): number?
	for i = 1, Progression.GetCapacity(data) do
		local s = data.Base.Slots[tostring(i)]
		if s and s.brainrotId == id then
			return i
		end
	end
	return nil
end
function Rules.Repair(data: any): any
	local valid, reason = Rules.Validate(data.ChariotTeam)
	if not valid then
		return { changed = false, disabled = reason }
	end
	local t = data.ChariotTeam
	local seen = {}
	local repairs = {}
	for i = 1, 6 do
		local id = t.Assignments[tostring(i)]
		if id then
			local issue = if i > 2 + t.PurchasedExtraSlots
				then "LOCKED_SLOT"
				elseif seen[id] then "DUPLICATE"
				elseif not data.Collection.BrainrotInstances[id] then "NOT_OWNED"
				elseif not Rules.Platform(data, id) then "NOT_ON_PLATFORM"
				else nil
			if issue then
				t.Assignments[tostring(i)] = false
				table.insert(repairs, { slot = i, reason = issue })
			else
				seen[id] = true
			end
		end
	end
	return { changed = #repairs > 0, repairs = repairs }
end
function Rules.ClearRemoved(data: any, before: any): boolean
	if not Rules.Validate(data.ChariotTeam) then
		return false
	end
	local changed = false
	for i = 1, 6 do
		local id = data.ChariotTeam.Assignments[tostring(i)]
		if
			id
			and (
				not data.Collection.BrainrotInstances[id] or (
					Rules.Platform(before, id) and not Rules.Platform(data, id)
				)
			)
		then
			data.ChariotTeam.Assignments[tostring(i)] = false
			changed = true
		end
	end
	return changed
end
function Rules.Classify(def: any): string?
	if type(def) ~= "table" then
		return nil
	end
	if
		def.classification == "Secret"
		or def.isSecret == true
		or def.acquisitionClass == "Secret"
		or def.tier == "Secret"
	then
		return "Secret"
	end
	return def.tier or def.rarity
end
local function roundSpecies(value: number): number
	local scale = 10 ^ Config.SpeciesPrecision
	return math.floor(value * scale + 0.5) / scale
end

-- Membership is the workbook's fixed 35 IDs, including planned species. A new
-- catalogue entry or a temporary spawn exclusion cannot move these anchors.
function Rules.BuildReferences(definitions: any?): any
	local ranges = {}
	local missing = {}
	local invalidClasses = {}
	local count = 0
	for _, id in Config.LegacyReferenceSpeciesIds do
		local spec = Config.SpeciesEffects[id]
		local def = if definitions then definitions[id] else Catalog.Get(id)
		local class = Rules.Classify(def)
		local cps = type(def) == "table" and def.cashPerSecond
		if not class or not Config.RarityBases[class] or not Rules.Finite(cps) or cps <= 0 then
			table.insert(missing, id)
			if type(spec) == "table" and type(spec.rarity) == "string" then
				invalidClasses[spec.rarity] = true
			end
			if class then
				invalidClasses[class] = true
			end
		else
			count += 1
			local range = ranges[class]
			if not range then
				range = { minimum = cps, maximum = cps, count = 0 }
				ranges[class] = range
			end
			range.minimum = math.min(range.minimum, cps)
			range.maximum = math.max(range.maximum, cps)
			range.count += 1
		end
	end
	for class, range in ranges do
		range.valid = not invalidClasses[class]
		table.freeze(range)
	end
	table.sort(missing)
	return table.freeze({ ranges = table.freeze(ranges), missing = table.freeze(missing), count = count, valid = #missing
		== 0 })
end
local liveReferences = Rules.BuildReferences()

function Rules.ValidateSpeciesEffects(definitions: any?): any
	return Effects.ValidateDefinitions(definitions or Config.SpeciesEffects)
end

function Rules.Individual(def: any, speciesId: any?, references: any?): any
	local rawId = speciesId or (type(def) == "table" and def.id)
	local id = Catalog.NormalizeId(rawId)
	-- Pure isolated definitions can use unmistakable fixture IDs. Normal gameplay
	-- obtains def from the authoritative catalogue, which owns eligibility and
	-- the guarded transient fixture registry; client records cannot supply def.
	if not id and type(def) == "table" and def.id == rawId and Rules.ValidId(rawId) and def.chariotEffect ~= nil then
		id = rawId
	end
	local spec = if type(def) == "table" and def.chariotEffect ~= nil
		then def.chariotEffect
		else id and Config.SpeciesEffects[id]
	local validation = Effects.ValidateSpeciesEffectReport(spec, id)
	local effectDefinition = type(spec) == "table" and Effects.Get(spec.effect)
	local class = Rules.Classify(def)
	local tuning = class and Config.RarityBases[class]
	local cps = type(def) == "table" and def.cashPerSecond
	local refs = references or liveReferences
	local range = class and refs.ranges[class]
	local issue = if not id or spec == nil
		then "UNKNOWN_EFFECT_ASSIGNMENT"
		elseif #validation.errors > 0 then validation.errors[1].code
		elseif not tuning then "UNKNOWN_CLASSIFICATION"
		elseif effectDefinition.UsesCPS and (not Rules.Finite(cps) or cps <= 0) then "INVALID_BASE_CPS"
		elseif effectDefinition.UsesCPS and (not range or not range.valid) then "REFERENCE_SET_UNAVAILABLE"
		else nil
	if issue then
		return { valid = false, contribution = 0, displayValue = 0, contributorsGranted = 1, issue = issue }
	end
	local factor = if not effectDefinition.UsesCPS or range.minimum == range.maximum
		then 1
		else roundSpecies(
			math.clamp(
				0.95 + 0.10 * (cps - range.minimum) / (range.maximum - range.minimum),
				Config.ValueFactorMinimum,
				Config.ValueFactorMaximum
			)
		)
	-- Bases and the rounded factor use four decimal units. Multiplying their
	-- integers keeps exact half-up ties (450 * 9500 => 0.0428), without a floating
	-- epsilon that could push values genuinely below the rounding boundary up.
	local scale = 10 ^ Config.SpeciesPrecision
	local baseUnits = if effectDefinition.UsesCPS then math.floor(tuning[spec.effect] * scale + 0.5) else scale
	local factorUnits = math.floor(factor * scale + 0.5)
	local contribution = math.floor((baseUnits * factorUnits + scale / 2) / scale) / scale
	local grant = spec.contributors or Config.DefaultContributors
	local amplifierTarget = if grant > 1 then spec.amplifierTarget or spec.effect else nil
	return {
		valid = true,
		speciesId = id,
		effect = spec.effect,
		contribution = contribution,
		rawContribution = contribution,
		displayValue = contribution + effectDefinition.Neutral,
		valueFactor = factor,
		classification = class,
		rank = tuning.rank,
		cps = cps,
		normalCPS = cps,
		contributorsGranted = grant,
		amplifierTarget = amplifierTarget,
		trait = if amplifierTarget then "Top " .. grant .. " " .. amplifierTarget else "None",
	}
end

local function descending(a: any, b: any): boolean
	if a.contribution ~= b.contribution then
		return a.contribution > b.contribution
	end
	return a.individualId < b.individualId
end
-- Shared by the team calculator and isolated future tuning fixtures. Inputs have
-- already passed ownership/assignment validation and the duplicate boundary.
function Rules.SelectContributors(lists: any, limits: any): any
	local effects = {}
	local anyCapped = false
	for _, definition in Effects.Ordered do
		local effect = definition.Id
		local list = lists[effect] or {}
		table.sort(list, descending)
		local maximum = Config.EffectCaps[effect] - definition.Neutral
		local sum = 0
		local applied = 0
		local selected = 0
		local limit =
			math.clamp(limits[effect] or Config.DefaultContributors, Config.DefaultContributors, Config.MaxContributors)
		for rank, d in list do
			d.effectRank = rank
			d.selected = false
			d.appliedContribution = 0
			if rank <= limit then
				selected += 1
				sum += d.contribution
				d.selected = true
				d.appliedContribution = math.min(d.contribution, math.max(0, maximum - applied))
				applied += d.appliedContribution
				if d.appliedContribution + 1e-12 < d.contribution then
					d.status = "capped"
					d.statusLabel = "Capped"
				elseif effect == "Hit" then
					d.status = "future_hit"
					d.statusLabel = "Future Hit benefit"
				else
					d.status = "contributing"
					d.statusLabel = "Contributing"
				end
			else
				d.status = "below_limit"
				d.statusLabel = if effect == "Shield"
					then (if limit == 1 then "A Shield amplifier is needed" else "Shield contribution limit reached")
					else "Below the limit"
			end
		end
		local capped = sum > maximum + 1e-12
		anyCapped = anyCapped or capped
		effects[effect] = {
			limit = limit,
			providers = #list,
			selected = selected,
			rawBonus = sum,
			appliedBonus = math.min(maximum, sum),
			cap = Config.EffectCaps[effect],
			capped = capped,
		}
	end
	return effects, anyCapped
end
function Rules.Calculate(entries: any, unlockedSlots: any?, references: any?): any
	local groups = {}
	local details = {}
	local count = 0
	local unavailable = 0
	local seen = {}
	local lists = {}
	local limits = {}
	for _, definition in Effects.Ordered do
		lists[definition.Id] = {}
		limits[definition.Id] = Config.DefaultContributors
	end
	local capacity = if Rules.Finite(unlockedSlots)
		then math.clamp(math.floor(unlockedSlots), 0, Config.MaxSlots)
		else Config.MaxSlots
	for i = 1, Config.MaxSlots do
		local e = entries and (entries[tostring(i)] or entries[i])
		if type(e) == "table" then
			count += 1
			local raw = Rules.Individual(e.definition, e.speciesId, references)
			local issue = if i > capacity
				then "LOCKED_SLOT"
				elseif not Rules.ValidId(e.individualId) then "INVALID_INDIVIDUAL_ID"
				elseif seen[e.individualId] then "DUPLICATE_INDIVIDUAL"
				else raw.issue
			local valid = raw.valid and issue == nil
			local d = {
				slot = i,
				individualId = e.individualId,
				speciesId = raw.speciesId or e.speciesId,
				effect = raw.effect,
				rawContribution = raw.contribution,
				valueFactor = raw.valueFactor,
				classification = raw.classification,
				valid = valid,
				issue = issue,
				duplicateFactor = 0,
				contribution = 0,
				appliedContribution = 0,
				selected = false,
				status = "unavailable",
				statusLabel = "Unavailable",
				contributorsGranted = raw.contributorsGranted,
				amplifierTarget = raw.amplifierTarget,
				trait = raw.trait,
			}
			details[tostring(i)] = d
			if valid then
				seen[e.individualId] = true
				local group = groups[d.speciesId] or {}
				groups[d.speciesId] = group
				table.insert(group, d)
				if raw.amplifierTarget then
					limits[raw.amplifierTarget] = math.max(limits[raw.amplifierTarget], raw.contributorsGranted)
				end
			else
				unavailable += 1
			end
		end
	end
	for _, group in groups do
		table.sort(group, function(a, b)
			if a.rawContribution ~= b.rawContribution then
				return a.rawContribution > b.rawContribution
			end
			return a.individualId < b.individualId
		end)
		for index, d in group do
			d.duplicateRank = index
			d.duplicateFactor = if Effects.Get(d.effect).UsesDuplicateFactors
				then Config.DuplicateFactors[index] or 0
				else 1
			-- Only the species calculation is rounded; keep fractional duplicate values.
			d.contribution = d.rawContribution * d.duplicateFactor
			table.insert(lists[d.effect], d)
		end
	end
	local effects, anyCapped = Rules.SelectContributors(lists, limits)
	return {
		count = count,
		unavailable = unavailable,
		details = details,
		limits = limits,
		effects = effects,
		capped = anyCapped,
		speedBonus = effects.Speed.appliedBonus,
		speedMultiplier = 1 + effects.Speed.appliedBonus,
		hitMultiplier = 1 + effects.Hit.appliedBonus,
		burstCapacity = effects.Burst.appliedBonus,
		shieldCapacity = effects.Shield.appliedBonus,
	}
end
function Rules.Effective(base: any, stats: any, limits: any?): any
	local speed = if Rules.Finite(base.speed) then math.max(0, base.speed) else 0
	local ceiling = limits and limits.speed or math.huge
	local multiplier = if Rules.Finite(stats.speedMultiplier)
		then math.clamp(stats.speedMultiplier, 1, 1 + Config.EffectCaps.Speed)
		else 1
	local baseline = math.min(speed, ceiling)
	local requested = speed * multiplier
	local effective = math.min(requested, ceiling)
	return {
		speed = effective,
		baselineSpeed = baseline,
		requestedSpeed = requested,
		speedRatio = if baseline > 0 then effective / baseline else 1,
		percent = { speed = if baseline > 0 then 100 * (effective / baseline - 1) else 0 },
		clipped = { speed = effective < requested },
		hitMultiplier = stats.hitMultiplier,
		burstCapacity = stats.burstCapacity,
		shieldCapacity = stats.shieldCapacity,
	}
end
function Rules.Preview(entries: any, slot: number, candidate: any, unlockedSlots: any?, references: any?): any
	local proposed = table.clone(entries)
	proposed[tostring(slot)] = candidate
	proposed[slot] = nil
	return Rules.Calculate(proposed, unlockedSlots, references)
end
function Rules.Buy(data: any, target: any, version: any, prepareSpend: any): any
	local valid, reason = Rules.Validate(data.ChariotTeam)
	if not valid then
		return { ok = false, code = reason }
	end
	if not Rules.Finite(target) or target % 1 ~= 0 or target < 3 or target > 6 then
		return { ok = false, code = "INVALID_REQUEST" }
	end
	local capacity = 2 + data.ChariotTeam.PurchasedExtraSlots
	if target <= capacity then
		return { ok = true, code = "ALREADY_APPLIED", committed = false }
	end
	if version ~= Config.Version then
		return { ok = false, code = "STALE_OFFER" }
	end
	if target ~= capacity + 1 then
		return { ok = false, code = "SLOT_LOCKED" }
	end
	local spend = prepareSpend(data, Config.Prices[target])
	if not spend.ok then
		return { ok = false, code = "INSUFFICIENT_CASH" }
	end
	data.Economy.Balance = spend.balance
	data.ChariotTeam.PurchasedExtraSlots += 1
	return {
		ok = true,
		committed = true,
		code = "OK",
		price = Config.Prices[target],
		balance = spend.balance,
		balanceBefore = spend.balanceBefore,
	}
end
return table.freeze(Rules)
