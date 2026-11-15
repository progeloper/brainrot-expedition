--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local WorldProgression=require(ReplicatedStorage.Shared.Config.WorldProgression)
local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local TeamConfig = require(ReplicatedStorage.Shared.Config.ChariotTeam)
local OrdinarySpawnCeilings = require(ReplicatedStorage.Shared.Utility.OrdinarySpawnCeilings)
local RegionSpawnCatalog = require(script.Parent.RegionSpawnCatalog)
local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12)

export type ValidationIssue = {
	code: string,
	message: string,
	tier: string?,
	speciesId: string?,
}

export type ValidationReport = {
	errors: { ValidationIssue },
	warnings: { ValidationIssue },
	exclusions: { ValidationIssue },
}

local SpawnSelection = {}
local serverRandom = Random.new()

local standardTierSet: { [string]: boolean } = {}
for _, tier in Rarities.StandardOrder do
	standardTierSet[tier] = true
end
table.freeze(standardTierSet)

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function finiteNonnegative(value: any): boolean
	return finiteNumber(value) and value >= 0
end

local function addIssue(
	list: { ValidationIssue },
	code: string,
	message: string,
	tier: string?,
	speciesId: string?
)
	table.insert(
		list,
		table.freeze({
			code = code,
			message = message,
			tier = tier,
			speciesId = speciesId,
		})
	)
end

local function freezeReport(report: ValidationReport): ValidationReport
	table.freeze(report.errors)
	table.freeze(report.warnings)
	table.freeze(report.exclusions)
	return table.freeze(report)
end

local function newReport(): ValidationReport
	return { errors = {}, warnings = {}, exclusions = {} }
end

local function freezeMap(source: { [any]: any }): { [any]: any }
	return table.freeze(table.clone(source))
end

local function canonicalAllowedRegion(candidate: any, regionId: string): boolean
	if type(candidate.allowedRegionIds) ~= "table" then
		return false
	end
	for _, rawRegionId in candidate.allowedRegionIds do
		if Regions.NormalizeId(rawRegionId) == regionId then
			return true
		end
	end
	return false
end

local function appendPositive(
	entries: { any },
	total: number,
	entry: any,
	weight: number
): (number?, string?)
	local newTotal = total + weight
	if not finiteNumber(newTotal) then
		return nil, "WEIGHT_TOTAL_NOT_FINITE"
	end
	if newTotal <= total then
		return nil, "WEIGHT_PRECISION_LOSS"
	end
	entry.weight = weight
	entry.cumulativeEnd = newTotal
	table.insert(entries, entry)
	return newTotal, nil
end

local function compileFailure(status: string, regionId: string?, report: ValidationReport): any
	return table.freeze({
		status = status,
		regionId = regionId,
		pool = nil,
		report = freezeReport(report),
	})
end

-- Compiles one immutable, reference-free pool. Candidates are snapshots supplied
-- by RegionSpawnCatalog; this module never owns species membership or readiness.
function SpawnSelection.CompileRegion(regionId: unknown, config: any, candidates: any, ceilingOverride: any?): any
	local report = newReport()
	local ceilings = ceilingOverride or (if FeatureFlags.EquippedTeamsEnabled and (Environment.MainGameplayEnabled or not Environment.IsProduction) then TeamConfig.SpawnCeilings else {})
	ceilings = if type(ceilings) == "table" then ceilings else {}
	for speciesId, ceiling in ceilings do
		if BrainrotCatalog.NormalizeId(speciesId) ~= speciesId or not finiteNonnegative(ceiling) or ceiling > 1 then
			addIssue(report.errors, "INVALID_ORDINARY_SPAWN_CEILING", "ordinary ceiling must use a canonical species ID and finite probability from zero through one", nil, tostring(speciesId))
		end
	end
	if #report.errors > 0 then return compileFailure("INVALID_CONFIGURATION", nil, report) end
	local normalizedRegion = Regions.NormalizeId(regionId)
	if normalizedRegion == nil then
		addIssue(
			report.errors,
			"UNKNOWN_REGION",
			"region is not a current canonical region",
			nil,
			nil
		)
		return compileFailure("UNKNOWN_REGION", nil, report)
	end

	local region = config
	if type(region) ~= "table" then
		addIssue(report.errors, "UNKNOWN_REGION", "region configuration is missing", nil, nil)
		return compileFailure("UNKNOWN_REGION", normalizedRegion, report)
	end
	if Regions.NormalizeId(region.id) ~= normalizedRegion then
		addIssue(
			report.errors,
			"REGION_ID_MISMATCH",
			"region configuration does not match the request",
			nil,
			nil
		)
	end
	if region.kind ~= "Hunting" or region.naturalSpawnAllowed ~= true then
		addIssue(
			report.errors,
			"REGION_NOT_SPAWNABLE",
			"region is not an ordinary natural-spawn hunting region",
			nil,
			nil
		)
		return compileFailure("REGION_NOT_SPAWNABLE", normalizedRegion, report)
	end
	if region.enabled ~= true then
		addIssue(report.errors, "REGION_DISABLED", "region is disabled", nil, nil)
	end

	local selection = region.spawnSelection
	if type(selection) ~= "table" then
		addIssue(
			report.errors,
			"MISSING_SPAWN_SELECTION",
			"current-region tier weights have not been approved",
			nil,
			nil
		)
		selection = {}
	end
	local rawTierWeights = if type(selection.tierWeights) == "table"
		then selection.tierWeights
		else {}
	local rawOverrides = if type(selection.speciesWeightOverrides) == "table"
		then selection.speciesWeightOverrides
		else {}
	if selection.tierWeights ~= nil and type(selection.tierWeights) ~= "table" then
		addIssue(report.errors, "INVALID_TIER_WEIGHTS", "tierWeights must be a table", nil, nil)
	end
	if
		selection.speciesWeightOverrides ~= nil
		and type(selection.speciesWeightOverrides) ~= "table"
	then
		addIssue(
			report.errors,
			"INVALID_SPECIES_WEIGHT_OVERRIDES",
			"speciesWeightOverrides must be a table",
			nil,
			nil
		)
	end

	for key in rawTierWeights do
		if
			type(key) ~= "string"
			or (standardTierSet[key] ~= true and not (key == "Secret" and rawTierWeights[key] == 0))
		then
			addIssue(
				report.errors,
				"UNKNOWN_TIER_WEIGHT_KEY",
				"unsupported tier-weight key " .. tostring(key),
				tostring(key),
				nil
			)
		end
	end
	local configuredTierWeights: { [string]: number } = {}
	if rawTierWeights.Secret ~= nil then
		configuredTierWeights.Secret = rawTierWeights.Secret
	end
	local tierWeightsComplete = true
	local tierWeightsValid = true
	local positiveTierCount = 0
	for _, tier in Rarities.StandardOrder do
		local value = rawTierWeights[tier]
		if tier == "Celestial" and value == nil then value = 0 end
		if value == nil then
			tierWeightsComplete = false
			addIssue(
				report.errors,
				"MISSING_TIER_WEIGHT",
				"standard tier key is required",
				tier,
				nil
			)
		elseif not finiteNonnegative(value) then
			tierWeightsValid = false
			addIssue(
				report.errors,
				"INVALID_TIER_WEIGHT",
				"tier weight must be a finite nonnegative number",
				tier,
				nil
			)
		else
			configuredTierWeights[tier] = value
			if value > 0 then
				positiveTierCount += 1
			end
		end
	end
	if tierWeightsComplete and tierWeightsValid and positiveTierCount == 0 then
		addIssue(
			report.errors,
			"ALL_TIER_WEIGHTS_ZERO",
			"at least one tier weight must be positive",
			nil,
			nil
		)
	end

	local candidateList = if type(candidates) == "table" then candidates else {}
	if type(candidates) ~= "table" then
		addIssue(
			report.errors,
			"INVALID_CANDIDATES",
			"candidate snapshot must be a table",
			nil,
			nil
		)
	end
	local candidateById: { [string]: any } = {}
	local orderedCandidateIds: { string } = {}
	for _, candidate in candidateList do
		if type(candidate) ~= "table" then
			addIssue(
				report.errors,
				"INVALID_CANDIDATE",
				"candidate record must be a table",
				nil,
				nil
			)
			continue
		end
		local canonicalId = BrainrotCatalog.NormalizeId(candidate.id)
		if canonicalId == nil then
			addIssue(
				report.errors,
				"UNKNOWN_SPECIES",
				"candidate has an invalid species ID",
				nil,
				nil
			)
		elseif candidateById[canonicalId] ~= nil then
			addIssue(
				report.errors,
				"DUPLICATE_SPECIES_ID",
				"candidate IDs collide after normalization",
				nil,
				canonicalId
			)
		else
			candidateById[canonicalId] = candidate
			table.insert(orderedCandidateIds, canonicalId)
		end
	end
	table.sort(orderedCandidateIds)

	local approvedMemberSet: { [string]: boolean } = {}
	for _, speciesId in orderedCandidateIds do
		local candidate = candidateById[speciesId]
		if
			candidate.assignmentStatus == "Approved"
			and canonicalAllowedRegion(candidate, normalizedRegion)
		then
			approvedMemberSet[speciesId] = true
		end
	end
	if next(approvedMemberSet) == nil then
		addIssue(
			report.errors,
			"MISSING_APPROVED_MEMBERSHIP",
			"region has no approved species membership",
			nil,
			nil
		)
	end

	local overrides: { [string]: number } = {}
	for rawId, weight in rawOverrides do
		local speciesId = BrainrotCatalog.NormalizeId(rawId)
		if speciesId == nil or candidateById[speciesId] == nil then
			addIssue(
				report.errors,
				"UNKNOWN_SPECIES_WEIGHT_OVERRIDE",
				"species override does not resolve to a candidate",
				nil,
				if speciesId then speciesId else tostring(rawId)
			)
		elseif approvedMemberSet[speciesId] ~= true then
			addIssue(
				report.errors,
				"SPECIES_WEIGHT_OVERRIDE_OUTSIDE_REGION",
				"species override is outside the approved regional pool",
				nil,
				speciesId
			)
		elseif not finiteNonnegative(weight) then
			addIssue(
				report.errors,
				"INVALID_SPECIES_WEIGHT",
				"species override must be a finite nonnegative number",
				nil,
				speciesId
			)
		else
			overrides[speciesId] = weight
		end
	end

	local eligibleByTier: { [string]: { any } } = {}
	for _, tier in Rarities.StandardOrder do
		eligibleByTier[tier] = {}
	end
	for _, speciesId in orderedCandidateIds do
		local candidate = candidateById[speciesId]
		if approvedMemberSet[speciesId] ~= true then
			addIssue(
				report.exclusions,
				"REGION_ASSIGNMENT_NOT_APPROVED",
				"candidate is not an approved member of this region",
				candidate.tier,
				speciesId
			)
			continue
		end
		-- Launch activation is evaluated before gameplay-tier semantics. Deferred
		-- catalogue rows (including a future Secret row) remain valid preserved
		-- content, but they are not members of the current ordinary spawn pool and
		-- must not block its readiness gate.
		if candidate.spawnEnabled == false then
			addIssue(
				report.exclusions,
				"SPAWN_DISABLED",
				"species is not activated for natural spawning",
				tostring(candidate.tier),
				speciesId
			)
			continue
		end
		if candidate.launchStatus ~= nil and candidate.launchStatus ~= "Live" then
			addIssue(
				report.exclusions,
				"CONTENT_NOT_LIVE",
				"species launch mode excludes ordinary spawning",
				tostring(candidate.tier),
				speciesId
			)
			continue
		end
		if candidate.naturalSpawnEligible == false then
			addIssue(
				report.exclusions,
				"ACQUISITION_MODE_EXCLUDED",
				"species is not ordinary natural-spawn content",
				tostring(candidate.tier),
				speciesId
			)
			continue
		end
		if ceilings[speciesId] == 0 then
			addIssue(report.exclusions, "ORDINARY_SPAWN_CEILING_ZERO", "species has zero ordinary-spawn probability; special eligibility is unchanged", tostring(candidate.tier), speciesId)
			continue
		end
		local tier = Rarities.Normalize(candidate.tier)
		if tier == nil or not Rarities.IsStandard(tier) or tier ~= candidate.tier then
			addIssue(
				report.errors,
				"INVALID_SPECIES_TIER",
				"species tier is not canonical",
				candidate.tier,
				speciesId
			)
			continue
		end
		if candidate.definitionExists == false then
			addIssue(
				report.errors,
				"UNKNOWN_SPECIES",
				"candidate definition is unavailable",
				tier,
				speciesId
			)
			continue
		end
		local ready = true
		if candidate.modelReady == false then
			ready = false
			addIssue(
				report.errors,
				"MODEL_MISSING",
				"enabled natural candidate has no ready model",
				tier,
				speciesId
			)
		end
		if candidate.behaviourReady == false then
			ready = false
			addIssue(
				report.errors,
				"BEHAVIOUR_NOT_READY",
				"enabled natural candidate behaviour is not ready",
				tier,
				speciesId
			)
		end
		if candidate.locationReady == false then
			ready = false
			addIssue(
				report.errors,
				"LOCATION_NOT_READY",
				"enabled natural candidate has no usable regional location",
				tier,
				speciesId
			)
		end
		if not ready then
			continue
		end

		local weight = overrides[speciesId]
		local source = "RegionOverride"
		if weight == nil then
			weight = candidate.globalWithinTierWeight
			source = "GlobalWithinTier"
		end
		if weight == nil then
			weight = 1
			source = "Default"
		end
		if not finiteNonnegative(weight) then
			addIssue(
				report.errors,
				"INVALID_SPECIES_WEIGHT",
				"resolved species weight must be finite and nonnegative",
				tier,
				speciesId
			)
			continue
		end
		if weight == 0 then
			addIssue(
				report.exclusions,
				"SPECIES_WEIGHT_ZERO",
				"species has an explicit zero effective weight",
				tier,
				speciesId
			)
			continue
		end
		table.insert(eligibleByTier[tier], {
			speciesId = speciesId,
			tier = tier,
			resolvedWeight = weight,
			weightSource = source,
		})
	end

	local compiledTiers: { any } = {}
	local totalTierWeight = 0
	if #eligibleByTier.Celestial == 0 then
		addIssue(report.exclusions,"EMPTY_CELESTIAL_POOL","No enabled Celestial species/asset; effective probability is zero","Celestial",nil)
	end
	for _, tier in Rarities.StandardOrder do
		local tierWeight = configuredTierWeights[tier]
		if tierWeight == nil or tierWeight <= 0 then
			continue
		end
		local speciesEntries: { any } = {}
		local speciesTotal = 0
		for _, candidate in eligibleByTier[tier] do
			local entry = {
				speciesId = candidate.speciesId,
				tier = tier,
				weightSource = candidate.weightSource,
			}
			local nextTotal, reason =
				appendPositive(speciesEntries, speciesTotal, entry, candidate.resolvedWeight)
			if nextTotal == nil then
				addIssue(
					report.errors,
					reason :: string,
					"species cumulative weight is numerically invalid",
					tier,
					candidate.speciesId
				)
				continue
			end
			speciesTotal = nextTotal
		end
		if #speciesEntries == 0 then
			addIssue(
				report.exclusions,
				"NO_ELIGIBLE_SPECIES_IN_POSITIVE_TIER",
				"empty positive tier is excluded; remaining eligible weights renormalize",
				tier,
				nil
			)
			continue
		end
		for _, entry in speciesEntries do
			table.freeze(entry)
		end
		table.freeze(speciesEntries)
		local tierEntry = {
			tier = tier,
			configuredWeight = tierWeight,
			species = speciesEntries,
			totalSpeciesWeight = speciesTotal,
		}
		local nextTotal, reason =
			appendPositive(compiledTiers, totalTierWeight, tierEntry, tierWeight)
		if nextTotal == nil then
			addIssue(
				report.errors,
				reason :: string,
				"tier cumulative weight is numerically invalid",
				tier,
				nil
			)
			continue
		end
		totalTierWeight = nextTotal
	end

	if #report.errors > 0 then
		return compileFailure("INVALID_CONFIGURATION", normalizedRegion, report)
	end
	for _, tierEntry in compiledTiers do
		table.freeze(tierEntry)
	end
	table.freeze(compiledTiers)
	local pool = table.freeze({
		kind = "CompiledRegionPool",
		regionId = normalizedRegion,
		weightSource = region.phase12WeightSource or "VerifiedCurrentConfiguration",
		configuredTierWeights = freezeMap(configuredTierWeights),
		speciesWeightOverrides = freezeMap(overrides),
		ordinarySpawnCeilings = freezeMap(ceilings),
		tiers = compiledTiers,
		totalTierWeight = totalTierWeight,
		staticExclusions = table.freeze(table.clone(report.exclusions)),
	})
	return table.freeze({
		status = "Compiled",
		regionId = normalizedRegion,
		pool = pool,
		report = freezeReport(report),
	})
end

function SpawnSelection.PrepareEffective(compiledPool: any, availabilitySnapshot: any?): any
	if type(compiledPool) ~= "table" or compiledPool.kind ~= "CompiledRegionPool" then
		return table.freeze({
			status = "INVALID_CONFIGURATION",
			regionId = if type(compiledPool) == "table" then compiledPool.regionId else nil,
			tiers = table.freeze({}),
			totalTierWeight = 0,
			temporaryExclusions = table.freeze({}),
		})
	end
	local snapshot = if type(availabilitySnapshot) == "table" then availabilitySnapshot else {}
	local blockedSpecies = if type(snapshot.blockedSpecies) == "table"
		then snapshot.blockedSpecies
		else {}
	local blockedTiers = if type(snapshot.blockedTiers) == "table"
		then snapshot.blockedTiers
		else {}
	local tiers: { any } = {}
	local exclusions: { any } = {}
	local totalTierWeight = 0

	for _, compiledTier in compiledPool.tiers do
		local tier = compiledTier.tier
		if blockedTiers[tier] ~= nil then
			table.insert(
				exclusions,
				table.freeze({
					code = "TIER_TEMPORARILY_BLOCKED",
					tier = tier,
					reason = tostring(blockedTiers[tier]),
				})
			)
			continue
		end
		local species: { any } = {}
		local totalSpeciesWeight = 0
		for _, compiledSpecies in compiledTier.species do
			local reason = blockedSpecies[compiledSpecies.speciesId]
			if reason ~= nil then
				table.insert(
					exclusions,
					table.freeze({
						code = "SPECIES_TEMPORARILY_BLOCKED",
						tier = tier,
						speciesId = compiledSpecies.speciesId,
						reason = tostring(reason),
					})
				)
				continue
			end
			local entry = {
				speciesId = compiledSpecies.speciesId,
				tier = tier,
				weightSource = compiledSpecies.weightSource,
			}
			local nextTotal =
				appendPositive(species, totalSpeciesWeight, entry, compiledSpecies.weight)
			if nextTotal == nil then
				return table.freeze({
					status = "INVALID_CONFIGURATION",
					regionId = compiledPool.regionId,
					tiers = table.freeze({}),
					totalTierWeight = 0,
					temporaryExclusions = table.freeze(exclusions),
				})
			end
			totalSpeciesWeight = nextTotal
		end
		if #species == 0 then
			table.insert(
				exclusions,
				table.freeze({
					code = "TIER_HAS_NO_ELIGIBLE_SPECIES_NOW",
					tier = tier,
					reason = "All positive-weight species are temporarily unavailable",
				})
			)
			continue
		end
		local tierEntry = {
			tier = tier,
			configuredWeight = compiledTier.configuredWeight,
			species = species,
			totalSpeciesWeight = totalSpeciesWeight,
		}
		local nextTotal =
			appendPositive(tiers, totalTierWeight, tierEntry, compiledTier.configuredWeight)
		if nextTotal == nil then
			return table.freeze({
				status = "INVALID_CONFIGURATION",
				regionId = compiledPool.regionId,
				tiers = table.freeze({}),
				totalTierWeight = 0,
				temporaryExclusions = table.freeze(exclusions),
			})
		end
		totalTierWeight = nextTotal
	end

	local bounded = if #tiers > 0
		then OrdinarySpawnCeilings.Apply(tiers, totalTierWeight, compiledPool.ordinarySpawnCeilings or {})
		else { Status = "Ready", Tiers = tiers, TotalTierWeight = totalTierWeight, Adjustments = table.freeze({}) }
	tiers, totalTierWeight = bounded.Tiers, bounded.TotalTierWeight
	if bounded.Status ~= "Ready" then
		table.insert(exclusions, table.freeze({ code = bounded.Status, reason = "No uncapped eligible species can receive the remaining ordinary probability" }))
	end
	for _, tierEntry in tiers do
		for _, entry in tierEntry.species do table.freeze(entry) end
		table.freeze(tierEntry.species)
		table.freeze(tierEntry)
	end
	table.freeze(tiers)
	table.freeze(exclusions)
	return table.freeze({
		status = if #tiers == 0 then "NO_ELIGIBLE_SPECIES_NOW" else "Ready",
		regionId = compiledPool.regionId,
		weightSource = compiledPool.weightSource,
		tiers = tiers,
		totalTierWeight = totalTierWeight,
		temporaryExclusions = exclusions,
		ordinarySpawnCeilingStatus = bounded.Status,
		ordinarySpawnCeilingAdjustments = bounded.Adjustments,
	})
end

function SpawnSelection.PickWeighted(entries: any, totalWeight: any, unit: any): (any?, string?)
	if not finiteNumber(unit) or unit < 0 or unit > 1 then
		return nil, "INVALID_RANDOM_VALUE"
	end
	if
		type(entries) ~= "table"
		or #entries == 0
		or not finiteNumber(totalWeight)
		or totalWeight <= 0
	then
		return nil, "INTERNAL_SELECTION_ERROR"
	end
	if unit == 1 then
		return entries[#entries], nil
	end
	local threshold = unit * totalWeight
	for _, entry in entries do
		if threshold < entry.cumulativeEnd then
			return entry, nil
		end
	end
	if threshold == totalWeight then
		return entries[#entries], nil
	end
	return nil, "INTERNAL_SELECTION_ERROR"
end

function SpawnSelection.Select(effectivePool: any, nextUnit: (() -> number)?): any
	if type(effectivePool) ~= "table" or effectivePool.status == "INVALID_CONFIGURATION" then
		return table.freeze({ status = "INVALID_CONFIGURATION" })
	end
	if effectivePool.status == "NO_ELIGIBLE_SPECIES_NOW" then
		return table.freeze({
			status = "NO_ELIGIBLE_SPECIES_NOW",
			regionId = effectivePool.regionId,
		})
	end
	if effectivePool.status ~= "Ready" then
		return table.freeze({ status = "INVALID_CONFIGURATION" })
	end
	local draw = nextUnit or function()
		return serverRandom:NextNumber()
	end
	local tierUnit = draw()
	local tierEntry, tierError =
		SpawnSelection.PickWeighted(effectivePool.tiers, effectivePool.totalTierWeight, tierUnit)
	if tierEntry == nil then
		return table.freeze({
			status = tierError,
			regionId = effectivePool.regionId,
		})
	end
	-- Always consume the independent species draw, even for a one-species tier.
	local speciesUnit = draw()
	local speciesEntry, speciesError =
		SpawnSelection.PickWeighted(tierEntry.species, tierEntry.totalSpeciesWeight, speciesUnit)
	if speciesEntry == nil then
		return table.freeze({
			status = speciesError,
			regionId = effectivePool.regionId,
			tier = tierEntry.tier,
		})
	end
	return table.freeze({
		status = "Selected",
		regionId = effectivePool.regionId,
		tier = tierEntry.tier,
		speciesId = speciesEntry.speciesId,
	})
end

function SpawnSelection.DescribeDistribution(compiledPool: any, effectivePool: any?): any
	if type(compiledPool) ~= "table" or compiledPool.kind ~= "CompiledRegionPool" then
		return table.freeze({ status = "INVALID_CONFIGURATION" })
	end
	local baseline = SpawnSelection.PrepareEffective(compiledPool, nil)
	local effective = effectivePool or baseline
	local baselineTierByName: { [string]: any } = {}
	for _, entry in baseline.tiers do baselineTierByName[entry.tier] = entry end
	local effectiveTierByName: { [string]: any } = {}
	if effective.status == "Ready" then
		for _, tierEntry in effective.tiers do
			effectiveTierByName[tierEntry.tier] = tierEntry
		end
	end
	local compiledTierByName: { [string]: any } = {}
	for _, tierEntry in compiledPool.tiers do
		compiledTierByName[tierEntry.tier] = tierEntry
	end

	local tierRows: { any } = {}
	local speciesRows: { any } = {}
	local defaultedSpeciesIds: { string } = {}
	for _, tier in Rarities.StandardOrder do
		local compiledTier = compiledTierByName[tier]
		local baselineTier = baselineTierByName[tier]
		local effectiveTier = effectiveTierByName[tier]
		local configuredWeight = compiledPool.configuredTierWeights[tier] or 0
		table.insert(
			tierRows,
			table.freeze({
				tier = tier,
				configuredWeight = configuredWeight,
				authoredProbability = if compiledTier then compiledTier.configuredWeight / compiledPool.totalTierWeight else 0,
				baselineProbability = if baselineTier
					then baselineTier.configuredWeight / baseline.totalTierWeight
					else 0,
				baselineEligibleSpeciesCount = if compiledTier then #compiledTier.species else 0,
				effectiveEligibleSpeciesCount = if effectiveTier then #effectiveTier.species else 0,
				effectiveProbability = if effectiveTier and effective.totalTierWeight > 0
					then effectiveTier.configuredWeight / effective.totalTierWeight
					else 0,
				exclusionReason = if configuredWeight == 0
					then "TIER_WEIGHT_ZERO"
					elseif compiledTier and not effectiveTier then "NO_ELIGIBLE_SPECIES_NOW"
					else nil,
			})
		)
		if compiledTier then
			local baselineSpeciesById: { [string]: any } = {}
			if baselineTier then for _, entry in baselineTier.species do baselineSpeciesById[entry.speciesId] = entry end end
			local effectiveSpeciesById: { [string]: any } = {}
			if effectiveTier then
				for _, entry in effectiveTier.species do
					effectiveSpeciesById[entry.speciesId] = entry
				end
			end
			for _, entry in compiledTier.species do
				local baselineEntry = baselineSpeciesById[entry.speciesId]
				local effectiveEntry = effectiveSpeciesById[entry.speciesId]
				local authoredTierProbability = compiledTier.configuredWeight / compiledPool.totalTierWeight
				local authoredConditional = entry.weight / compiledTier.totalSpeciesWeight
				local baselineTierProbability = if baselineTier then baselineTier.configuredWeight / baseline.totalTierWeight else 0
				local baselineConditional = if baselineEntry and baselineTier then baselineEntry.weight / baselineTier.totalSpeciesWeight else 0
				local effectiveConditional = if effectiveEntry and effectiveTier
					then effectiveEntry.weight / effectiveTier.totalSpeciesWeight
					else 0
				local effectiveTierProbability = if effectiveEntry
						and effectiveTier
						and effective.totalTierWeight > 0
					then effectiveTier.configuredWeight / effective.totalTierWeight
					else 0
				table.insert(
					speciesRows,
					table.freeze({
						speciesId = entry.speciesId,
						tier = tier,
						withinTierWeight = entry.weight,
						weightSource = entry.weightSource,
						ordinarySpawnCeiling = compiledPool.ordinarySpawnCeilings[entry.speciesId],
						authoredConditionalProbability = authoredConditional,
						authoredOverallProbability = authoredTierProbability * authoredConditional,
						baselineConditionalProbability = baselineConditional,
						baselineOverallProbability = baselineTierProbability * baselineConditional,
						effectiveConditionalProbability = effectiveConditional,
						effectiveOverallProbability = effectiveTierProbability
							* effectiveConditional,
					})
				)
				if entry.weightSource == "Default" then
					table.insert(defaultedSpeciesIds, entry.speciesId)
				end
			end
		end
	end
	table.freeze(tierRows)
	table.freeze(speciesRows)
	table.freeze(defaultedSpeciesIds)
	return table.freeze({
		status = "Ready",
		regionId = compiledPool.regionId,
		baselineTierDenominator = baseline.totalTierWeight,
		weightSource = compiledPool.weightSource,
		authoredTierDenominator = compiledPool.totalTierWeight,
		effectiveTierDenominator = effective.totalTierWeight or 0,
		tiers = tierRows,
		species = speciesRows,
		staticExclusions = compiledPool.staticExclusions,
		temporaryExclusions = effective.temporaryExclusions or table.freeze({}),
		defaultedSpeciesIds = defaultedSpeciesIds,
		ordinarySpawnCeilingStatus = effective.ordinarySpawnCeilingStatus,
		ordinarySpawnCeilingAdjustments = effective.ordinarySpawnCeilingAdjustments,
	})
end

function SpawnSelection.CompileConfiguredRegion(regionId: unknown): any
	local region = Regions.Get(regionId)
	if region == nil then
		return SpawnSelection.CompileRegion(regionId, nil, {})
	end
	local resolved = table.clone(region)
	local selection = region.spawnSelection
	local validCurrent = type(selection) == "table" and type(selection.tierWeights) == "table"
	if validCurrent then
		local total=0
		for _, tier in Rarities.DisplayOrder do
			local value=selection.tierWeights[tier]
			if tier=="Celestial" and value==nil then value=0 end
			if not finiteNonnegative(value) or (tier=="Secret" and value~=0) then validCurrent=false break end
			total+=value
		end
		if math.abs(total-1)>1e-9 then validCurrent=false end
	end
	if validCurrent then
		local weights = table.clone(selection.tierWeights)
		-- Celestial is a new empty tier. Existing valid seven-tier tables remain
		-- the authority; adding its explicit zero does not redistribute a live rate.
		if weights.Celestial == nil then weights.Celestial = 0 end
		resolved.spawnSelection = { tierWeights=weights, speciesWeightOverrides=selection.speciesWeightOverrides or {} }
	else
		local fallback = Phase12.RegionFallbackWeights[region.id] or Phase12.RegionFallbackWeights[region.displayName]
		if fallback then
			local weights = {}
			for tier, weight in fallback do weights[tier]=weight/100 end
			resolved.spawnSelection = { tierWeights=weights, speciesWeightOverrides={} }
			resolved.phase12WeightSource = "UserAuthoredDevelopmentFallback"
		end
	end
	return SpawnSelection.CompileRegion(
		region.id,
		resolved,
		RegionSpawnCatalog.GetSelectionCandidates(region.id)
	)
end

-- Production activation gate. Configuration, map geometry, exact tier sums and
-- every statically required regional pool must all be valid before the shared
-- population scheduler may start. This is observation only: it does not spawn,
-- settle, mutate, or retry anything.
function SpawnSelection.EvaluateConfiguredWorldReadiness(): any
	local active={REGION_FOREST=true}
	local expectedCount=1
	for _,key in WorldProgression.OperationalKeys do
		local id=WorldProgression.ByKey[key].regionId
		if not active[id] then active[id]=true expectedCount+=1 end
	end
	local reasons = {}
	local regions = {}
	local geometry = RegionSpawnCatalog.ValidateConfiguration()
	local globallySafe = true
	for _, issue in geometry.errors do
		if issue.regionId == nil or issue.regionId == Regions.CampId then globallySafe=false end
		if not issue.regionId or active[issue.regionId] then
			table.insert(reasons, string.format("%s:%s", issue.code, issue.regionId or "WORLD"))
		end
	end
	local huntingCount = 0
	local readyCount = 0
	for _, region in Regions.GetAll() do
		if region.kind == "Hub" then
			if
				region.id ~= Regions.CampId
				or region.naturalSpawnAllowed
				or region.spawnSelection ~= nil
			then
				table.insert(reasons, "INVALID_CAMP_NATURAL_SPAWN_CONTRACT")
				globallySafe=false
			end
			continue
		end
		if not active[region.id] then continue end
		huntingCount += 1
		local regionReasons = {}
		local compilation = SpawnSelection.CompileConfiguredRegion(region.id)
		if compilation.pool ~= nil then
			if #compilation.pool.tiers==0 then table.insert(regionReasons,"NO_ELIGIBLE_REGION_POOL") end
			local total = 0
			for _, tier in Rarities.DisplayOrder do
				local weight = compilation.pool.configuredTierWeights[tier]
				if tier == "Celestial" and weight == nil then weight = 0 end
				if not finiteNonnegative(weight) then
					table.insert(regionReasons, "INVALID_TIER_WEIGHT:" .. tier)
				else
					total += weight
				end
			end
			if math.abs(total - 1) > 1e-9 then
				table.insert(regionReasons, "TIER_WEIGHT_SUM_MISMATCH")
			end
		end
		if compilation.pool == nil then
			for _, issue in compilation.report.errors do
				table.insert(regionReasons, issue.code .. (issue.tier and ":" .. issue.tier or ""))
			end
		end
		if #regionReasons == 0 then
			readyCount += 1
		else
			for _, reason in regionReasons do
				table.insert(reasons, region.id .. ":" .. reason)
			end
		end
		table.insert(
			regions,
			table.freeze({
				regionId = region.id,
				ready = #regionReasons == 0,
				reasons = table.freeze(regionReasons),
			})
		)
	end
	table.freeze(regions)
	table.freeze(reasons)
	return table.freeze({
		ready = if Phase12.Enabled then globallySafe and readyCount > 0
			else #reasons == 0 and huntingCount == expectedCount and readyCount == huntingCount,
		huntingRegionCount = huntingCount,
		readyRegionCount = readyCount,
		regions = regions,
		reasons = reasons,
	})
end

-- Server-only adapter for a future existing spawn owner. It makes a choice and
-- nothing else: no runtime ID, placement, Model construction or retry occurs here.
function SpawnSelection.SelectConfiguredRegion(
	regionId: unknown,
	availabilitySnapshot: any?,
	nextUnit: (() -> number)?
): any
	local compilation = SpawnSelection.CompileConfiguredRegion(regionId)
	if compilation.pool == nil then
		return table.freeze({
			status = compilation.status,
			regionId = compilation.regionId,
			report = compilation.report,
		})
	end
	local effective = SpawnSelection.PrepareEffective(compilation.pool, availabilitySnapshot)
	return SpawnSelection.Select(effective, nextUnit)
end

return table.freeze(SpawnSelection)
