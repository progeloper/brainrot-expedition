--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CartModelUtility = require(script.Parent.Parent.Utility.CartModelUtility)
local CartLocalPlacement = require(script.Parent.Parent.Utility.CartLocalPlacement)
local Roaming = require(script.Parent.DevelopmentBrainrotRoaming)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local BrainrotInteraction = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)
local BrainrotPopulation = require(ReplicatedStorage.Shared.Config.BrainrotPopulation)
local Phase10 = require(ReplicatedStorage.Shared.Config.Phase10)
local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local GemRules = require(ReplicatedStorage.Shared.Utility.GemRules)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.Economy)
-- Core Loop V2: with the Herds part on, HuntDirector is the only natural spawn source (A1).
local CoreLoopFlags = require(ReplicatedStorage.Shared.Config.CoreLoopFlags)
local CoreLoop = require(ReplicatedStorage.Shared.Config.CoreLoop)
local directedSpawning = CoreLoopFlags.Part("Herds")
local accessPolicyRef: any = nil -- the world-progression population policy, when configured
-- P15 Mutation Storm: server-wide mutation chance for new spawns while active.
local function stormMutationChance(): number
	return GemRules.MutationChance(
		Phase12.MutationChance,
		workspace:GetAttribute(EconomyConfig.MutationStorm.Attribute),
		workspace:GetServerTimeNow()
	)
end
local BrainrotTerritory = require(ReplicatedStorage.Shared.Config.BrainrotTerritory)
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local BrainrotDisplayMetadata = require(ReplicatedStorage.Shared.Utility.BrainrotDisplayMetadata)
local CreatureAssets = require(script.Parent.Parent.Utility.CreatureAssetService)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local RegionSpawnCatalog = require(script.Parent.RegionSpawnCatalog)
local SpawnSelection = require(script.Parent.SpawnSelection)
local NaturalTerritory = require(script.Parent.NaturalTerritory)
local Phase12Burrows = require(script.Parent.Parent.Utility.Phase12Burrows)
local RouteCatalog = require(script.Parent.Parent.Utility.BurrowRouteCatalog)
local RouteRules = require(ReplicatedStorage.Shared.Utility.BrainrotRouteRules)
local BankBarrier = require(script.Parent.Parent.Utility.OrdinaryBankBarrier)
local HuntFlow = require(ReplicatedStorage.Shared.Config.HuntFlow)
local Players = game:GetService("Players")
local freshRetirementSubscribers: {[any]: (any,string)->()} = {}
local admissionObserver: ((string,string)->())? = nil

local TEST_SPAWN_CFRAME = CFrame.new(0, 0, -30) * CFrame.Angles(0, math.rad(90), 0)
local TEST_SPAWN_COUNT = 10
local PILOT_SPECIES = table.freeze({ "BRT_007", "BRT_011", "BRT_015", "BRT_016" })
local TEST_SPAWN_RADIUS = 30
local MIN_SPAWN_SEPARATION = 6
local SPAWN_POSITION_ATTEMPTS = 12
local random = Random.new()

export type WorldRecord = {
	ItemId: string,
	BrainrotId: string,
	Metadata: { [string]: any },
	World: {
		Name: string,
		Scale: number,
		SpawnPosition: { X: number, Y: number, Z: number },
		SpawnRegionId: string?,
		TerritoryRegionId: string?,
		ReturnRegionId: string?,
		RouteJourney: any?,
	},
}

type HuntBody = {
	Body: BasePart,
	Parts: { [Instance]: boolean },
	Scale: number,
	Size: Vector3,
	LocalFrame: CFrame,
}

type Registration = {
	Record: WorldRecord,
	Sleeping: boolean,
	SleepStartedAt: number?,
	SleepUntil: number?,
	LifecycleRevision: number,
	SleepIndicator: BillboardGui?,
	Connections: { RBXScriptConnection },
	HuntBody: HuntBody?,
	PopulationRegionId: string?,
}

export type WildMember = {
	RuntimeId: string,
	SpeciesId: string,
	BehaviourId: string,
	State: string?,
	FirstAcquiredAt: number?,
	PopulationRegionId: string?,
}

export type SpawnReservation = {
	ReservationId: string,
	RegionId: string,
	SpeciesId: string,
	BehaviourId: string,
	MutationId: string?,
}

type PopulationDependencies = {
	GetRegion: ((string) -> any?)?,
	ChooseRegion: ((any, { [string]: boolean }) -> (string?, string?, boolean?))?,
	SelectSpecies: ((string, any) -> any)?,
	SpawnReservation: ((SpawnReservation, (string) -> (boolean, string?)) -> (boolean, string?))?,
	Schedule: ((number, () -> ()) -> ())?,
	GenerateReservationId: (() -> string)?,
	OnChanged: ((string, any) -> ())?,
	CheckReadiness: (() -> (boolean, string?))?,
}

type PopulationState = {
	Config: any,
	Dependencies: PopulationDependencies,
	Members: { [string]: WildMember },
	WildCount: number,
	WildByRegion: { [string]: number },
	WildByBehaviour: { [string]: number },
	Reservations: { [string]: SpawnReservation },
	ReservedCount: number,
	ReservedByRegion: { [string]: number },
	ReservedByBehaviour: { [string]: number },
	Running: boolean,
	Generation: number,
	ReconcileScheduled: boolean,
}

local DevelopmentBrainrotSpawner = {}
local log = Logger.new("BrainrotPopulation")
local worldChanged = Instance.new("BindableEvent")
DevelopmentBrainrotSpawner.WorldChanged = worldChanged.Event
local populationChanged = Instance.new("BindableEvent")
DevelopmentBrainrotSpawner.PopulationChanged = populationChanged.Event
local naturalSpawnCommitted = Instance.new("BindableEvent")
DevelopmentBrainrotSpawner.NaturalSpawnCommitted = naturalSpawnCommitted.Event
local registrations: { [Model]: Registration } = {}
local modelsById: { [string]: Model } = {}
local preparedByToken: { [any]: any } = {}
local preparedByModel: { [Model]: boolean } = {}
local preparedFreshMembers: { [any]: string } = {}
local pendingPublication: { [Model]: boolean } = {}
local pendingUnregisterReason: { [Model]: string } = {}
local pendingFreshReleases: { [string]: any } = {}
local reservationJourneys: { [string]: any } = {}
local pendingBanks: { [string]: any } = {}
local freshReleaseTokens: { [any]: any } = {}
local lastPendingReleasePass = 0
local lastNaturalConstructionAt = -math.huge
local currentResetGeneration = 0
local boundFolder: Folder? = nil
local folderAddedConnection: RBXScriptConnection? = nil
local productionPopulation: PopulationState
local requestProductionReconcile: ((string, number?) -> (boolean, string?))? = nil
local sleepHeartbeatConnection: RBXScriptConnection? = nil
local sleepClock = function(): number
	return Workspace:GetServerTimeNow()
end

-- Runtime location/status mirrors never become persistent species metadata.
local transientAttributes = {
	ItemId = true,
	BrainrotId = true,
	[BrainrotDisplayConfig.Attributes.DisplayState] = true,
	[BrainrotDisplayConfig.Attributes.MutationId] = true,
	[BrainrotDisplayConfig.Attributes.CarrierUserId] = true,
	[BrainrotDisplayConfig.Attributes.CamouflageSnapshot] = true,
	[BrainrotDisplayConfig.Attributes.DecoySplitSnapshot] = true,
	Captured = true,
	BrainrotSleepUntil = true,
	BrainrotLifecycleRevision = true,
	CarriedByUserId = true,
	AttachmentIndex = true,
	SlotIndex = true,
	CampReturnRegionId = true,
	Phase10TargetKind = true,
	Phase10CartId = true,
	Phase10Banked = true,
	OwnerUserId = true,
	PickupClaimUserId = true,
	CapturedByUserId = true,
}

local function copyData(value: any, ancestors: any?): any
	if type(value) ~= "table" then
		assert(typeof(value) ~= "Instance", "World metadata must not contain Instances")
		return value
	end
	local seen = ancestors or {}
	assert(not seen[value], "Cyclic world metadata")
	seen[value] = true
	local result = {}
	for key, child in value do
		assert(type(key) == "string" or type(key) == "number", "Invalid metadata key")
		result[key] = copyData(child, seen)
	end
	seen[value] = nil
	return table.freeze(result)
end

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function positiveInteger(value: any): boolean
	return finite(value) and value > 0 and value % 1 == 0
end

-- Observe completed authority rejections only; telemetry never changes a result,
-- invokes RNG or runs for a disposable population fixture.
local function admissionDenied(state: PopulationState,reason: string?)
 if state~=productionPopulation or not admissionObserver or not reason or reason=="CONSTRUCTION_STAGED"then return end
 local category=if reason=="SERVER_POPULATION_TARGET_REACHED"then "GlobalCap"
  elseif reason=="REGION_POPULATION_CAP_REACHED"or reason=="REGION_QUOTA_REACHED"
   or reason=="NO_ACCESSIBLE_REGION_DEFICIT"or reason=="REGION_ACCESS_CHANGED"or reason=="REGION_NOT_SPAWNABLE"then "RegionalQuota"
  elseif reason=="PROFILE_POPULATION_CAP_REACHED"then "BehaviourCap"
  elseif reason:find("ROUTE")or reason:find("ENTRANCE")or reason:find("EXIT")or reason:find("BURROW")
   or reason:find("PLACEMENT")or reason:find("SUPPORT")or reason:find("CLEARANCE")then "NoValidRoute"
  else "NoValidSpecies"
 pcall(admissionObserver,category,reason)
end

local function cloneCounts(source: { [string]: number }): { [string]: number }
	return table.clone(source)
end

local function increment(index: { [string]: number }, key: string, amount: number)
	local nextValue = (index[key] or 0) + amount
	if nextValue == 0 then
		index[key] = nil
	else
		assert(nextValue > 0, "Population index cannot be negative")
		index[key] = nextValue
	end
end

local function normalizePopulationRegion(rawRegionId: any): string?
	local regionId = Regions.NormalizeId(rawRegionId)
	local region = if regionId then Regions.Get(regionId) else nil
	if region == nil or region.kind ~= "Hunting" or not region.naturalSpawnAllowed then
		return nil
	end
	return regionId
end

local function validatePopulationConfig(config: any)
	assert(type(config) == "table", "Population config must be a table")
	assert(positiveInteger(config.TargetWildPopulation), "TargetWildPopulation must be positive")
	assert(finite(config.ReplenishDelaySeconds) and config.ReplenishDelaySeconds > 0, "Invalid replenish delay")
	assert(finite(config.RetryDelaySeconds) and config.RetryDelaySeconds > 0, "Invalid retry delay")
	assert(positiveInteger(config.MaxSpawnReservationsPerPass), "Invalid reservation pass limit")
	assert(type(config.ProfileAdmissionCaps) == "table", "ProfileAdmissionCaps must be a table")
	for profile, cap in config.ProfileAdmissionCaps do
		assert(type(profile) == "string" and positiveInteger(cap), "Invalid profile admission cap")
	end
end

local function createPopulationState(config: any, dependencies: PopulationDependencies?): PopulationState
	validatePopulationConfig(config)
	return {
		Config = config,
		Dependencies = dependencies or {},
		Members = {},
		WildCount = 0,
		WildByRegion = {},
		WildByBehaviour = {},
		Reservations = {},
		ReservedCount = 0,
		ReservedByRegion = {},
		ReservedByBehaviour = {},
		Running = false,
		Generation = 0,
		ReconcileScheduled = false,
	}
end

local function emitPopulationChanged(state: PopulationState, kind: string, payload: any)
	local callback = state.Dependencies.OnChanged
	if callback then
		callback(kind, payload)
	end
end

local function resolveWildMember(runtimeId: any, speciesId: any, populationRegionId: any): (WildMember?, string?)
	if type(runtimeId) ~= "string" or runtimeId == "" then
		return nil, "INVALID_RUNTIME_ID"
	end
	local definition = BrainrotCatalog.Get(speciesId)
	if definition == nil then
		return nil, "UNKNOWN_SPECIES"
	end
	local member: WildMember = {
		RuntimeId = runtimeId,
		SpeciesId = definition.id,
		BehaviourId = definition.behaviourId,
		State = "World",
		PopulationRegionId = normalizePopulationRegion(populationRegionId),
	}
	return table.freeze(member), nil
end

local function registerWild(
	state: PopulationState,
	runtimeId: any,
	speciesId: any,
	populationRegionId: any,
	emit: boolean?
): (boolean, string?)
	if state.Members[runtimeId] ~= nil then
		return false, "ALREADY_REGISTERED"
	end
	if
		Phase10.Enabled
		and emit ~= false
		and state.WildCount + state.ReservedCount >= state.Config.TargetWildPopulation
	then
		admissionDenied(state,"SERVER_POPULATION_TARGET_REACHED")
		return false, "SERVER_POPULATION_TARGET_REACHED"
	end
	local member, reason = resolveWildMember(runtimeId, speciesId, populationRegionId)
	if member == nil then
		return false, reason
	end
	-- Weapon Tiers V2 (flag-gated inside HpForSpecies): HP scales by the individual's spawn/population
	-- region, resolved once here and stored as MaxHp so it never changes mid-catch. Flag off: unchanged.
	local hpRegionId = member.PopulationRegionId
	if hpRegionId == nil then
		local model = modelsById[member.RuntimeId]
		local registration = if model then registrations[model] else nil
		hpRegionId = if registration
			then NaturalTerritory.GetSpawnRegionId(registration.Record)
			else nil
	end
	local hp = Phase12Rules.HpForSpecies(member.SpeciesId, hpRegionId)
	local definition = BrainrotCatalog.Get(member.SpeciesId)
	local escape = Phase12.EscapeByRarity[if definition then definition.tier else "Common"]
	local enriched = table.clone(member)
	enriched.Phase12 = table.freeze({
		MaxHp = hp, RemainingHp = hp, CapturedOnce = false,
		EscapeAttemptsUsed = 0, EscapeMaxAttempts = if escape then escape.MaxAttempts else 0,
		EscapeRemainingSeconds = nil, EscapeDeadline = nil, EscapeGeneration = 0,
		WarningGeneration = 0, Retired = false, Revision = 0, MutationId = "None",
		OrdinaryReservationId = member.RuntimeId, ResetGeneration = currentResetGeneration,
	})
	member = table.freeze(enriched)
	state.Members[member.RuntimeId] = member
	state.WildCount += 1
	increment(state.WildByBehaviour, member.BehaviourId, 1)
	if member.PopulationRegionId then
		increment(state.WildByRegion, member.PopulationRegionId, 1)
	end
	if emit ~= false then
		emitPopulationChanged(state, "WildMembershipAdded", member)
	end
	return true, nil
end

local function unregisterWild(
	state: PopulationState,
	runtimeId: any,
	reason: string?,
	emit: boolean?
): (boolean, string?)
	if type(runtimeId) ~= "string" or runtimeId == "" then
		return false, "INVALID_RUNTIME_ID"
	end
	local member = state.Members[runtimeId]
	if member == nil then
		return false, "ALREADY_ABSENT"
	end
	state.Members[runtimeId] = nil
	state.WildCount -= 1
	assert(state.WildCount >= 0, "Wild population cannot be negative")
	increment(state.WildByBehaviour, member.BehaviourId, -1)
	if member.PopulationRegionId then
		increment(state.WildByRegion, member.PopulationRegionId, -1)
	end
	if emit ~= false then
		emitPopulationChanged(state, "WildMembershipRemoved", {
			RuntimeId = runtimeId,
			Reason = reason or "Removed",
			Member = member,
		})
	end
	return true, nil
end

-- Members count individuals, including transit/pending representations. A visual
-- leaving Workspace is never evidence that an ordinary individual was banked.
local function setMemberState(state: PopulationState, runtimeId: string, location: string): boolean
	local member = state.Members[runtimeId]
	if member == nil or member.State == location then
		return false
	end
	local nextMember = table.clone(member)
	nextMember.State = location
	state.Members[runtimeId] = table.freeze(nextMember)
	emitPopulationChanged(state, "OrdinaryStateChanged", state.Members[runtimeId])
	return true
end

local function firstBank(state: PopulationState, runtimeId: string): (boolean, string?)
	return unregisterWild(state, runtimeId, "FirstBank")
end

local function removeReservation(
	state: PopulationState,
	reservationId: any,
	reason: string?,
	emit: boolean?
): (SpawnReservation?, string?)
	if type(reservationId) ~= "string" or reservationId == "" then
		return nil, "INVALID_RESERVATION_ID"
	end
	local reservation = state.Reservations[reservationId]
	if reservation == nil then
		return nil, "ALREADY_RELEASED"
	end
	state.Reservations[reservationId] = nil
	reservationJourneys[reservationId] = nil
	state.ReservedCount -= 1
	assert(state.ReservedCount >= 0, "Reserved population cannot be negative")
	increment(state.ReservedByRegion, reservation.RegionId, -1)
	increment(state.ReservedByBehaviour, reservation.BehaviourId, -1)
	if emit ~= false then
		emitPopulationChanged(state, "SpawnReservationReleased", {
			Reservation = reservation,
			Reason = reason or "Released",
		})
	end
	return reservation, nil
end

local function regionAdmissionLimit(state: PopulationState, regionId: string): number?
	local getter = state.Dependencies.GetRegion
	local region = if getter then getter(regionId) else Regions.Get(regionId)
	if type(region) ~= "table" then
		return nil
	end
	for _, key in { "maxWild", "populationCap" } do
		local value = region[key]
		if positiveInteger(value) then
			return value
		end
	end
	return nil
end

local function canReserve(
	state: PopulationState,
	regionId: any,
	speciesId: any,
	directed: boolean?
): (boolean, string?, string?, string?)
	local canonicalRegion = Regions.NormalizeId(regionId)
	-- Core Loop V2: directed spawns check access eligibility in SpawnDirected and use the director's own
	-- caps, so they read the static region definition instead of the 42-split quota view.
	local regionGetter = if directed then nil else state.Dependencies.GetRegion
	local region = if canonicalRegion
		then (if regionGetter then regionGetter(canonicalRegion) else Regions.Get(canonicalRegion))
		else nil
	if
		canonicalRegion == nil
		or type(region) ~= "table"
		or region.kind ~= "Hunting"
		or region.naturalSpawnAllowed ~= true
	then
		return false, "REGION_NOT_SPAWNABLE", nil, nil
	end
	local definition = BrainrotCatalog.Get(speciesId)
	if definition == nil then
		return false, "UNKNOWN_SPECIES", canonicalRegion, nil
	end
	if state.WildCount + state.ReservedCount >= state.Config.TargetWildPopulation then
		return false, "SERVER_POPULATION_TARGET_REACHED", canonicalRegion, definition.behaviourId
	end
	local profileCap = state.Config.ProfileAdmissionCaps[definition.behaviourId]
	if
		profileCap == nil
		or (state.WildByBehaviour[definition.behaviourId] or 0)
				+ (state.ReservedByBehaviour[definition.behaviourId] or 0)
			>= profileCap
	then
		return false, "PROFILE_POPULATION_CAP_REACHED", canonicalRegion, definition.behaviourId
	end
	local regionCap = if directed then nil else regionAdmissionLimit(state, canonicalRegion)
	if
		regionCap ~= nil
		and (state.WildByRegion[canonicalRegion] or 0) + (state.ReservedByRegion[canonicalRegion] or 0) >= regionCap
	then
		return false, "REGION_POPULATION_CAP_REACHED", canonicalRegion, definition.behaviourId
	end
	return true, nil, canonicalRegion, definition.behaviourId
end

local function reserveSpawn(
	state: PopulationState,
	regionId: any,
	speciesId: any,
	mutationOverride: string?,
	directed: boolean?
): (SpawnReservation?, string?)
	local admitted, reason, canonicalRegion, behaviourId = canReserve(state, regionId, speciesId, directed)
	if not admitted then
		admissionDenied(state,reason)
		return nil, reason
	end
	local generator = state.Dependencies.GenerateReservationId
	local reservationId = if generator then generator() else HttpService:GenerateGUID(false)
	if type(reservationId) ~= "string" or reservationId == "" then
		return nil, "INVALID_RESERVATION_ID"
	end
	if state.Reservations[reservationId] ~= nil then
		return nil, "DUPLICATE_RESERVATION_ID"
	end
	local definition = BrainrotCatalog.Get(speciesId)
	-- One independent roll belongs to the counted pending reservation. Placement
	-- and asset-preparation retries never consume another mutation draw.
	local mutationId, mutationReason = "None",nil
	if mutationOverride ~= nil then
		-- Core Loop V2: the director already rolled this individual's one mutation (K1).
		mutationId = mutationOverride
	elseif Phase12.Enabled then mutationId,mutationReason=Phase12Rules.RollMutation(random, stormMutationChance()) end
	if mutationId == nil then
		return nil, mutationReason or "MUTATION_UNAVAILABLE"
	end
	local reservation: SpawnReservation = table.freeze({
		ReservationId = reservationId,
		RegionId = canonicalRegion :: string,
		SpeciesId = (definition :: any).id,
		BehaviourId = behaviourId :: string,
		MutationId = mutationId,
	})
	state.Reservations[reservationId] = reservation
	state.ReservedCount += 1
	increment(state.ReservedByRegion, reservation.RegionId, 1)
	increment(state.ReservedByBehaviour, reservation.BehaviourId, 1)
	emitPopulationChanged(state, "SpawnReserved", reservation)
	return reservation, nil
end

local function commitReservation(
	state: PopulationState,
	reservationId: any,
	runtimeId: any,
	validateEntity: ((SpawnReservation, string) -> boolean)?
): (boolean, string?)
	local reservation = if type(reservationId) == "string" then state.Reservations[reservationId] else nil
	if reservation == nil then
		return false, "UNKNOWN_RESERVATION"
	end
	if type(runtimeId) ~= "string" or runtimeId == "" then
		return false, "INVALID_RUNTIME_ID"
	end
	if validateEntity and not validateEntity(reservation, runtimeId) then
		return false, "INVALID_REGISTERED_ENTITY"
	end
	local existing = state.Members[runtimeId]
	if existing and existing.SpeciesId ~= reservation.SpeciesId then
		return false, "RUNTIME_ID_CONFLICT"
	end
	if existing == nil then
		local registered, registerReason =
			registerWild(state, runtimeId, reservation.SpeciesId, reservation.RegionId, false)
		if not registered then
			return false, registerReason
		end
	end
	local member = state.Members[runtimeId]
	if member and member.Phase12 then
		local phaseState = table.clone(member.Phase12)
		phaseState.MutationId = reservation.MutationId or "None"
		phaseState.OrdinaryReservationId = reservation.ReservationId
		local enriched = table.clone(member)
		enriched.Phase12 = table.freeze(phaseState)
		state.Members[runtimeId] = table.freeze(enriched)
	end
	removeReservation(state, reservation.ReservationId, "Committed", false)
	emitPopulationChanged(state, "SpawnCommitted", {
		RuntimeId = runtimeId,
		Reservation = reservation,
	})
	return true, nil
end

local function populationSnapshot(state: PopulationState): any
	local members = {}
	local states = { World = 0, Carried = 0, Cargo = 0, PendingWorld = 0 }
	for _, member in state.Members do
		states[member.State or "World"] = (states[member.State or "World"] or 0) + 1
		table.insert(members, member)
	end
	table.sort(members, function(left, right)
		return left.RuntimeId < right.RuntimeId
	end)
	local reservations = {}
	for _, reservation in state.Reservations do
		table.insert(reservations, reservation)
	end
	table.sort(reservations, function(left, right)
		return left.ReservationId < right.ReservationId
	end)
	return table.freeze({
		Target = state.Config.TargetWildPopulation,
		Wild = state.WildCount, -- Compatibility: ordinary individuals, including transit.
		Ordinary = state.WildCount,
		States = table.freeze(states),
		PendingRepresentations = states.PendingWorld,
		Reserved = state.ReservedCount,
		Effective = state.WildCount + state.ReservedCount,
		ByRegion = table.freeze(cloneCounts(state.WildByRegion)),
		ByBehaviour = table.freeze(cloneCounts(state.WildByBehaviour)),
		ReservedByRegion = table.freeze(cloneCounts(state.ReservedByRegion)),
		ReservedByBehaviour = table.freeze(cloneCounts(state.ReservedByBehaviour)),
		Members = table.freeze(members),
		Reservations = table.freeze(reservations),
		Running = state.Running,
		ReconcileScheduled = state.ReconcileScheduled,
	})
end

local function validatePopulationConsistency(state: PopulationState): (boolean, { string })
	local total = 0
	local byRegion: { [string]: number } = {}
	local byBehaviour: { [string]: number } = {}
	for _, member in state.Members do
		total += 1
		increment(byBehaviour, member.BehaviourId, 1)
		if member.PopulationRegionId then
			increment(byRegion, member.PopulationRegionId, 1)
		end
	end
	local reserved = 0
	local reservedByRegion: { [string]: number } = {}
	local reservedByBehaviour: { [string]: number } = {}
	for _, reservation in state.Reservations do
		reserved += 1
		increment(reservedByRegion, reservation.RegionId, 1)
		increment(reservedByBehaviour, reservation.BehaviourId, 1)
	end
	local issues = {}
	local function compare(label: string, expected: { [string]: number }, actual: { [string]: number })
		for key, value in expected do
			if actual[key] ~= value then
				table.insert(
					issues,
					string.format("%s:%s expected %d got %s", label, key, value, tostring(actual[key]))
				)
			end
		end
		for key, value in actual do
			if expected[key] ~= value then
				table.insert(
					issues,
					string.format("%s:%s cached %d got %s", label, key, value, tostring(expected[key]))
				)
			end
		end
	end
	if total ~= state.WildCount then
		table.insert(issues, string.format("wild total expected %d got %d", total, state.WildCount))
	end
	if reserved ~= state.ReservedCount then
		table.insert(issues, string.format("reserved total expected %d got %d", reserved, state.ReservedCount))
	end
	compare("wild region", byRegion, state.WildByRegion)
	compare("wild behaviour", byBehaviour, state.WildByBehaviour)
	compare("reserved region", reservedByRegion, state.ReservedByRegion)
	compare("reserved behaviour", reservedByBehaviour, state.ReservedByBehaviour)
	return #issues == 0, issues
end

local productionPopulationDependencies: PopulationDependencies = {
	GetRegion = function(regionId)
		return Regions.Get(regionId)
	end,
	Schedule = function(delaySeconds, callback)
		task.delay(delaySeconds, callback)
	end,
	GenerateReservationId = function()
		return HttpService:GenerateGUID(false)
	end,
	OnChanged = function(kind, payload)
		populationChanged:Fire(kind, payload)
		if kind == "WildMembershipAdded" then
			log:Debug(
				"WildMembershipAdded runtimeId=%s speciesId=%s total=%d",
				payload.RuntimeId,
				payload.SpeciesId,
				productionPopulation.WildCount
			)
		elseif kind == "WildMembershipRemoved" then
			log:Debug(
				"WildMembershipRemoved runtimeId=%s reason=%s total=%d",
				payload.RuntimeId,
				payload.Reason,
				productionPopulation.WildCount
			)
		elseif kind == "SpawnReserved" then
			log:Debug(
				"SpawnReserved reservationId=%s regionId=%s speciesId=%s profile=%s",
				payload.ReservationId,
				payload.RegionId,
				payload.SpeciesId,
				payload.BehaviourId
			)
		elseif kind == "SpawnCommitted" then
			log:Debug(
				"SpawnCommitted runtimeId=%s reservationId=%s",
				payload.RuntimeId,
				payload.Reservation.ReservationId
			)
		end
	end,
}
-- A1: with the director on, the server budget is TargetWild 64 and every profile cap x1.5 (rounded up).
local function effectivePopulationConfig(): any
	if not directedSpawning then
		return BrainrotPopulation
	end
	local caps = {}
	for profile, cap in BrainrotPopulation.ProfileAdmissionCaps do
		caps[profile] = math.ceil(cap * CoreLoop.Population.AdmissionCapScale)
	end
	local config = table.clone(BrainrotPopulation)
	config.TargetWildPopulation = CoreLoop.Population.TargetWild
	config.MaxSpawnReservationsPerPass = CoreLoop.Population.ReservationsPerPass
	config.ProfileAdmissionCaps = table.freeze(caps)
	return table.freeze(config)
end
productionPopulation = createPopulationState(effectivePopulationConfig(), productionPopulationDependencies)

local function validPose(pose: any): boolean
	if typeof(pose) ~= "CFrame" then
		return false
	end
	for _, component in { pose:GetComponents() } do
		if not finite(component) then
			return false
		end
	end
	return true
end

local function getBrainrotFolder(): Folder?
	local runtime = Workspace:FindFirstChild("Runtime")
	local folder = if runtime then runtime:FindFirstChild("Brainrots") else nil
	return if folder and folder:IsA("Folder") then folder else nil
end

-- Drive-by loop (owner decision, 10 Nov 2026): spawn for the hunter, despawn fairly.
local rareWaveUntil = 0
local huntFlowStats = { Ahead = 0, Mouth = 0, Stranded = 0, DepartBlocked = 0, WaveUpgrades = 0 }

local function playerGroundPositions(): { { Position: Vector3, Velocity: Vector3, Player: Player } }
	local rows = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(rows, { Position = root.Position, Velocity = root.AssemblyLinearVelocity, Player = player })
		end
	end
	return rows
end

local function awakeWildNear(position: Vector3, radius: number): number
	local count = 0
	for model, registration in registrations do
		if registration.Record.Metadata.DurableOwnerUserId == nil and model.Parent ~= nil then
			local offset = model:GetPivot().Position - position
			if offset.X * offset.X + offset.Z * offset.Z <= radius * radius then
				count += 1
			end
		end
	end
	return count
end

local function playerWithin(position: Vector3, radius: number, rows: { any }): boolean
	for _, row in rows do
		local offset = row.Position - position
		if offset.X * offset.X + offset.Z * offset.Z <= radius * radius then
			return true
		end
	end
	return false
end

-- A validated spot ahead of the hunter who currently has the fewest targets.
-- Uses the region's authored spawn volumes and the same placement validator as
-- every other natural spawn; returns nil when no such spot exists.
local function findPlayerFacingPlacement(speciesId: string, regionId: string): CFrame?
	if not HuntFlow.PlayerSpawnEnabled then
		return nil
	end
	local volumes = {}
	for _, area in RegionSpawnCatalog.GetSpawnAreas(regionId) do
		if type(area) == "table" and area.Enabled == true and area.Kind == "Volume" then
			table.insert(volumes, area)
		end
	end
	if #volumes == 0 then
		return nil
	end
	local hunters = {}
	for _, row in playerGroundPositions() do
		local nearby = awakeWildNear(row.Position, HuntFlow.NearbyRadius)
		if nearby < HuntFlow.NearbyTarget then
			table.insert(hunters, { Row = row, Nearby = nearby })
		end
	end
	table.sort(hunters, function(a, b)
		return a.Nearby < b.Nearby
	end)
	local attempts = 0
	for _, hunter in hunters do
		local row = hunter.Row
		local flat = Vector3.new(row.Velocity.X, 0, row.Velocity.Z)
		local moving = flat.Magnitude >= HuntFlow.MovingSpeed
		for _ = 1, 4 do
			if attempts >= HuntFlow.AheadAttempts then
				return nil
			end
			attempts += 1
			local heading = if moving
				then math.atan2(flat.X, flat.Z)
					+ math.rad(random:NextNumber(-HuntFlow.AheadSpreadDegrees, HuntFlow.AheadSpreadDegrees))
				else random:NextNumber(0, 2 * math.pi)
			local distance = random:NextNumber(HuntFlow.AheadMin, HuntFlow.AheadMax)
			local point = row.Position + Vector3.new(math.sin(heading), 0, math.cos(heading)) * distance
			if not RegionSpawnCatalog.ContainsPosition(regionId, point, math.huge) then
				continue
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { getBrainrotFolder() :: Instance }
			params.RespectCanCollide = true
			local hit = Workspace:Raycast(point + Vector3.yAxis * 80, -Vector3.yAxis * 200, params)
			if not hit or hit.Material == Enum.Material.Water then
				continue
			end
			for _, area in volumes do
				local localPoint = area.Part.CFrame:PointToObjectSpace(hit.Position)
				if
					math.abs(localPoint.X) <= area.Part.Size.X * 0.5
					and math.abs(localPoint.Z) <= area.Part.Size.Z * 0.5
				then
					local result = RegionSpawnCatalog.ValidatePlacement(speciesId, regionId, area.Id, hit.Position)
					if result.valid and typeof(result.placementPivot) == "CFrame" then
						local position = result.placementPivot.Position
						local toward = row.Position - position
						return CFrame.lookAt(position, position + Vector3.new(toward.Z, 0, -toward.X))
					end
					break
				end
			end
		end
	end
	return nil
end

-- Burrow departure is refused while a player is close or just after a hit.
local function departureIsFair(record: any, model: Model): boolean
	local state = DevelopmentBrainrotSpawner.GetPhase12State(record)
	local hitAt = state and state.LastAcceptedDamageTime
	if type(hitAt) == "number" and Workspace:GetServerTimeNow() - hitAt <= HuntFlow.DepartBlockAfterHitSeconds then
		return false
	end
	return not playerWithin(model:GetPivot().Position, HuntFlow.DepartBlockRadius, playerGroundPositions())
end

local strandedSince: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastStrandedSweep = 0

local function retireStranded(limit: number, commonOnly: boolean, minimumSeconds: number, rows: { any }): number
	local now = os.clock()
	local retired = 0
	for model, registration in table.clone(registrations) do
		local record = registration.Record
		if record.Metadata.DurableOwnerUserId ~= nil or registration.Sleeping or pendingBanks[record.ItemId] then
			strandedSince[model] = nil
			continue
		end
		if playerWithin(model:GetPivot().Position, HuntFlow.StrandedRadius, rows) then
			strandedSince[model] = nil
			continue
		end
		local since = strandedSince[model]
		if not since then
			strandedSince[model] = now
			since = now
		end
		if retired >= limit or now - since < minimumSeconds then
			continue
		end
		local state = DevelopmentBrainrotSpawner.GetPhase12State(record)
		local hitAt = state and state.LastAcceptedDamageTime
		if type(hitAt) == "number" and Workspace:GetServerTimeNow() - hitAt <= HuntFlow.DepartBlockAfterHitSeconds then
			continue
		end
		if commonOnly then
			local definition = BrainrotCatalog.Get(record.BrainrotId)
			if not definition or definition.tier ~= "Common" then
				continue
			end
		end
		if DevelopmentBrainrotSpawner.RetireFreshIndividual(record, "NoPlayerNearby") then
			retired += 1
		end
	end
	return retired
end

-- Recycles brainrots nobody can see toward a hunter who has too few targets.
local function sweepStranded()
	if directedSpawning then
		return -- Core Loop V2: HuntDirector owns retirement (DespawnPolicy).
	end
	local now = os.clock()
	if now - lastStrandedSweep < HuntFlow.StrandedSweepSeconds then
		return
	end
	lastStrandedSweep = now
	local rows = playerGroundPositions()
	local starved = false
	local hunters = {}
	for _, row in rows do
		if not RegionSpawnCatalog.ContainsPosition(Regions.CampId, row.Position, math.huge) then
			table.insert(hunters, row)
			if awakeWildNear(row.Position, HuntFlow.NearbyRadius) < HuntFlow.StarvedBelow then
				starved = true
			end
		end
	end
	if not starved then
		-- Keep the timers fresh so a hunter leaving Camp gets a prompt recycle.
		retireStranded(0, false, math.huge, rows)
		return
	end
	huntFlowStats.Stranded += retireStranded(HuntFlow.StrandedPerSweep, false, HuntFlow.StrandedSeconds, rows)
end

function DevelopmentBrainrotSpawner.BeginRareWave(seconds: number): any
	rareWaveUntil = os.clock() + math.max(0, seconds)
	local recycled = retireStranded(HuntFlow.RareWaveRecycle, true, 0, playerGroundPositions())
	if requestProductionReconcile then
		requestProductionReconcile("RareWave", Phase12.SpawnConstructionInterval)
	end
	return { Seconds = seconds, Recycled = recycled }
end

function DevelopmentBrainrotSpawner.IsRareWaveActive(): boolean
	return os.clock() < rareWaveUntil
end

function DevelopmentBrainrotSpawner.GetHuntFlowDiagnostics(): any
	local copy = table.clone(huntFlowStats)
	copy.RareWaveActive = os.clock() < rareWaveUntil
	return copy
end

local tierRank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Celestial = 7, Astral = 7, Secret = 8 }
local function waveSelect(select: (string, any) -> any, regionId: string, availability: any): any
	local best = select(regionId, availability)
	if os.clock() >= rareWaveUntil or type(best) ~= "table" or best.status ~= "Selected" then
		return best
	end
	local function rank(selection: any): number
		local definition = BrainrotCatalog.Get(selection.speciesId)
		return if definition then tierRank[definition.tier] or 1 else 1
	end
	local bestRank = rank(best)
	for _ = 2, HuntFlow.RareWaveDraws do
		local candidate = select(regionId, availability)
		if type(candidate) == "table" and candidate.status == "Selected" and rank(candidate) > bestRank then
			best, bestRank = candidate, rank(candidate)
			huntFlowStats.WaveUpgrades += 1
		end
	end
	return best
end

local function getTemplate(species: string): Model?
	return CreatureAssets.GetTemplate(species)
end

local function hasHitGeometry(model: Model): boolean
	local body = model:FindFirstChild("Body", true)
	return body ~= nil and body:IsA("BasePart") and body.CanQuery
end

local function readMetadata(model: Model, existing: any?): any
	local metadata = {}
	if existing then
		for key, value in existing do
			metadata[key] = value
		end
	end
	for key, value in model:GetAttributes() do
		if not transientAttributes[key] then
			metadata[key] = value
		end
	end
	return copyData(metadata)
end

local function isBodyGeometry(part: BasePart, model: Model): boolean
	return part.CanQuery and BrainrotVisualScale.IsVisualPart(part, model)
end

local function withWorldScale(record: WorldRecord, scale: number): WorldRecord
	local normalized = table.clone(record)
	local world = table.clone(record.World)
	world.Scale = scale
	normalized.World = table.freeze(world)
	return table.freeze(normalized) :: WorldRecord
end

local function measureHuntBody(brainrot: Model, body: BasePart, parts: { [Instance]: boolean }): HuntBody
	local proxyFrame, proxySize = BrainrotVisualScale.GetProxyBounds(brainrot, "Hunt")
	if proxyFrame and proxySize then
		return { Body = body, Parts = parts, Scale = brainrot:GetScale(), Size = proxySize, LocalFrame = proxyFrame }
	end
	local pivot = brainrot:GetPivot()
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	for part in parts do
		if part:IsA("BasePart") and part:IsDescendantOf(brainrot) then
			local frame, half = pivot:ToObjectSpace(part.CFrame), part.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local point = frame * (half * Vector3.new(x, y, z))
						low = low:Min(point)
						high = high:Max(point)
					end
				end
			end
		end
	end
	return {
		Body = body,
		Parts = parts,
		Scale = brainrot:GetScale(),
		Size = high - low,
		LocalFrame = CFrame.new((low + high) / 2),
	}
end

local function cacheHuntBody(brainrot: Model): HuntBody?
	local body = brainrot:FindFirstChild("Body", true)
	if not body or not body:IsA("BasePart") or not body.CanQuery then
		return nil
	end
	local proxyFrame, proxySize = BrainrotVisualScale.GetProxyBounds(brainrot, "Hunt")
	if proxyFrame and proxySize then
		return { Body = body, Parts = table.freeze({ [body] = true }), Scale = brainrot:GetScale(),
			Size = proxySize, LocalFrame = proxyFrame }
	end
	local parts: { [Instance]: boolean } = {}
	for _, descendant in brainrot:GetDescendants() do
		if descendant:IsA("BasePart") and isBodyGeometry(descendant, brainrot) then
			parts[descendant] = true
		end
	end
	if not parts[body] then
		return nil
	end
	return measureHuntBody(brainrot, body, table.freeze(parts))
end

local function unregister(brainrot: Model, reason: string?)
	local registration = registrations[brainrot]
	if registration == nil then
		return
	end
	BrainrotDisplayMetadata.Clear(brainrot)
	registrations[brainrot] = nil
	if registration.SleepIndicator then
		registration.SleepIndicator:Destroy()
	end
	if modelsById[registration.Record.ItemId] == brainrot then
		modelsById[registration.Record.ItemId] = nil
	end
	local actualReason = reason or pendingUnregisterReason[brainrot] or "Removed"
	local removed = false
	if Phase10.Enabled and actualReason ~= "TestCleanup" and actualReason ~= "Teardown" then
		if actualReason == "PickedUp" then
			setMemberState(productionPopulation, registration.Record.ItemId, "Carried")
		elseif
			actualReason ~= "ActivationFailed"
			and actualReason ~= "MovementRegistrationFailed"
			and actualReason ~= "PopulationRegistrationFailed"
		then
			-- Unexpected world visual loss keeps the same counted record and pose.
			if productionPopulation.Members[registration.Record.ItemId] then
				local ok, pose = pcall(function()
					return brainrot:GetPivot()
				end)
				if ok then
					DevelopmentBrainrotSpawner.QueueFreshRelease(registration.Record, pose)
				end
			end
		end
	else
		removed = unregisterWild(productionPopulation, registration.Record.ItemId, actualReason)
	end
	pendingUnregisterReason[brainrot] = nil
	if removed and requestProductionReconcile then
		requestProductionReconcile(actualReason, nil)
	end
	Roaming.Unregister(brainrot)
	for _, connection in registration.Connections do
		connection:Disconnect()
	end
	local pending = pendingPublication[brainrot]
	pendingPublication[brainrot] = nil
	if not pending then
		worldChanged:Fire(brainrot)
	end
end

local function registerWorld(
	brainrot: Model,
	record: WorldRecord,
	populationRegionId: string?,
	deferWildRegistration: boolean?
): boolean
	local folder = getBrainrotFolder()
	if folder == nil or brainrot.Parent ~= folder then
		return false
	end
	local previous = modelsById[record.ItemId]
	if previous ~= nil and previous ~= brainrot then
		if previous.Parent == folder then
			return false
		end
		unregister(previous)
	end
	if registrations[brainrot] ~= nil then
		return registrations[brainrot].Record.ItemId == record.ItemId
	end
	local registration: Registration = {
		Record = record,
		Sleeping = false,
		SleepStartedAt = nil,
		SleepUntil = nil,
		LifecycleRevision = 0,
		Connections = {},
		HuntBody = cacheHuntBody(brainrot),
		PopulationRegionId = normalizePopulationRegion(populationRegionId),
	}
	registrations[brainrot] = registration
	modelsById[record.ItemId] = brainrot
	table.insert(
		registration.Connections,
		brainrot.Destroying:Connect(function()
			unregister(brainrot, pendingUnregisterReason[brainrot] or "Destroyed")
		end)
	)
	table.insert(
		registration.Connections,
		brainrot.AncestryChanged:Connect(function()
			if brainrot.Parent ~= getBrainrotFolder() then
				unregister(brainrot, pendingUnregisterReason[brainrot] or "LeftWorld")
			end
		end)
	)
	local secured = Phase10.Enabled and type(record.Metadata.DurableOwnerUserId) == "number"
	if secured then
		registration.Sleeping = true
		brainrot:SetAttribute("Captured", true)
		brainrot:SetAttribute("Phase10Banked", true)
		brainrot:SetAttribute("OwnerUserId", record.Metadata.DurableOwnerUserId)
	elseif
		not Roaming.Register(
			brainrot,
			brainrot:GetPivot().Position,
			NaturalTerritory.GetSpawnRegionId(record),
			NaturalTerritory.GetTerritoryRegionId(record),
			NaturalTerritory.GetReturnRegionId(record)
		)
	then
		unregister(brainrot, "MovementRegistrationFailed")
		return false
	end
	BrainrotDisplayMetadata.Apply(
		brainrot,
		record,
		if secured then BrainrotDisplayConfig.States.Sleeping else BrainrotDisplayConfig.States.Awake,
		nil
	)
	brainrot:SetAttribute("BrainrotSleepUntil", nil)
	brainrot:SetAttribute("BrainrotLifecycleRevision", registration.LifecycleRevision)
	if not deferWildRegistration and not secured then
		local _, populationReason =
			registerWild(productionPopulation, record.ItemId, record.BrainrotId, registration.PopulationRegionId)
		if
			populationReason ~= nil
			and populationReason ~= "ALREADY_REGISTERED"
			and not (RunService:IsStudio() and string.match(record.BrainrotId, "^SPEC_"))
		then
			unregister(brainrot, "PopulationRegistrationFailed")
			return false
		end
	end
	if not secured then
		local member = productionPopulation.Members[record.ItemId]
		if member and member.Phase12 and member.Phase12.MutationId ~= record.Metadata.MutationId then
			local replacement = table.clone(member)
			local state = table.clone(member.Phase12)
			state.MutationId = record.Metadata.MutationId or "None"
			replacement.Phase12 = table.freeze(state)
			productionPopulation.Members[record.ItemId] = table.freeze(replacement)
		end
		setMemberState(productionPopulation, record.ItemId, "World")
	end
	if not pendingPublication[brainrot] then
		worldChanged:Fire(brainrot)
	end
	return true
end

-- Adoption is only for live development spawns, never detached restoration staging.
local function registerDevelopmentBrainrot(instance: Instance)
	if not instance:IsA("Model") or preparedByModel[instance] or registrations[instance] ~= nil then
		return
	end
	local definition = BrainrotCatalog.Get(instance:GetAttribute("BrainrotId"))
	if definition == nil or not hasHitGeometry(instance) then
		return
	end
	local scaled, _, scaleReason = BrainrotVisualScale.ApplyCanonicalScale(instance, "WorldAdopted")
	if not scaled then
		warn("[DevelopmentBrainrotSpawner] Rejected unscalable world model: " .. tostring(scaleReason))
		return
	end
	local itemId = instance:GetAttribute("ItemId")
	if typeof(itemId) ~= "string" or itemId == "" then
		itemId = HttpService:GenerateGUID(false)
		instance:SetAttribute("ItemId", itemId)
	end
	instance:SetAttribute("BrainrotId", definition.id)
	local position = instance:GetPivot().Position
	local record: WorldRecord = table.freeze({
		ItemId = itemId :: string,
		BrainrotId = definition.id,
		Metadata = readMetadata(instance),
		World = table.freeze({
			Name = instance.Name,
			Scale = instance:GetScale(),
			SpawnPosition = table.freeze({ X = position.X, Y = position.Y, Z = position.Z }),
		}),
	})
	if not registerWorld(instance, record) then
		warn("[DevelopmentBrainrotSpawner] Rejected duplicate or invalid world registration: " .. instance.Name)
	end
end

local function ensureBrainrotFolder(): Folder
	local runtime = Workspace:FindFirstChild("Runtime")
	if runtime == nil then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = Workspace
	end
	local folder = runtime:FindFirstChild("Brainrots")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Brainrots"
		folder.Parent = runtime
	end
	assert(folder:IsA("Folder"), "Runtime.Brainrots must be a Folder")
	if boundFolder ~= folder then
		if folderAddedConnection then
			folderAddedConnection:Disconnect()
		end
		boundFolder = folder
		folderAddedConnection = folder.ChildAdded:Connect(registerDevelopmentBrainrot)
		for _, child in folder:GetChildren() do
			registerDevelopmentBrainrot(child)
		end
	end
	return folder :: Folder
end

function DevelopmentBrainrotSpawner.GetWorldRecord(brainrot: Model): (WorldRecord?, string?)
	local registration = registrations[brainrot]
	if registration == nil or pendingPublication[brainrot] or brainrot.Parent ~= getBrainrotFolder() then
		return nil, "NOT_REGISTERED"
	end
	-- Identity and gameplay metadata are the immutable server record, not editable
	-- presentation attributes. Only this owner's TrySleep creates a pickup sleeper.
	return registration.Record,
		if brainrot:GetAttribute("Phase12InteractionReady") == false then "WorldEmerging"
		elseif registration.Sleeping
			then "WorldSleeping"
			elseif brainrot:GetAttribute("Captured") == true then "LEGACY_CAPTURED"
			else "WorldAwake"
end

-- Protected dropped originals are session world sources, not extra individuals.
-- Departure settles their existing owned records before retiring these visuals.
function DevelopmentBrainrotSpawner.GetSecuredWorldRecords(ownerUserId: number): { any }
	local records = {}
	if not Phase10.Enabled then
		return records
	end
	for model, registration in registrations do
		if
			registration.Record.Metadata.DurableOwnerUserId == ownerUserId
			and model.Parent == getBrainrotFolder()
			and not pendingPublication[model]
		then
			table.insert(records, registration.Record)
		end
	end
	return records
end

function DevelopmentBrainrotSpawner.RetireSecuredWorld(itemId: string, ownerUserId: number): (boolean, string?)
	local model = modelsById[itemId]
	local registration = if model then registrations[model] else nil
	if not registration then
		return true, "ALREADY_RETIRED"
	end
	if not Phase10.Enabled or registration.Record.Metadata.DurableOwnerUserId ~= ownerUserId then
		return false, "OWNERSHIP_CHANGED"
	end
	pendingUnregisterReason[model] = "OwnedRestored"
	unregister(model, "OwnedRestored")
	model:Destroy()
	return true, nil
end

function DevelopmentBrainrotSpawner.GetWorldModels(): { Model }
	local models = {}
	for model in registrations do
		if not pendingPublication[model] and model.Parent == getBrainrotFolder() then
			table.insert(models, model)
		end
	end
	return models
end

-- Exact Studio-fixture cleanup seam. GetWorldModels intentionally hides a model
-- while its publication is still private, so a fixture teardown that only scans
-- public world members can miss the narrow activation window and leave that model
-- obstructing the next fixed-geometry fixture. This removes only the requested
-- test-owned identity; live gameplay cannot call this boundary.
function DevelopmentBrainrotSpawner.DestroyWorldForTesting(itemId: string): (boolean, string?)
	if not RunService:IsStudio() then
		return false, "STUDIO_ONLY"
	end
	local model = modelsById[itemId]
	local removed = unregisterWild(productionPopulation, itemId, "TestCleanup")
	pendingFreshReleases[itemId] = nil
	for token in table.clone(freshReleaseTokens) do
		if token.Record.ItemId == itemId then
			DevelopmentBrainrotSpawner.DiscardFreshRelease(token)
		end
	end
	if model == nil then
		return removed, if removed then nil else "NOT_REGISTERED"
	end
	pendingPublication[model] = nil
	pendingUnregisterReason[model] = "TestCleanup"
	model.Parent = nil
	unregister(model, "TestCleanup")
	model:Destroy()
	return true, nil
end

-- Exact server-owned identity lookup for shot intent and other bounded runtime
-- validation. Callers still revalidate the returned lifecycle state before a
-- mutation; replicated attributes and physical Models are never ownership.
function DevelopmentBrainrotSpawner.GetWorldModelById(itemId: any): (Model?, WorldRecord?, string?)
	if type(itemId) ~= "string" or itemId == "" then
		return nil, nil, "INVALID_ITEM_ID"
	end
	local model = modelsById[itemId]
	if model == nil then
		return nil, nil, "NOT_REGISTERED"
	end
	local record, state = DevelopmentBrainrotSpawner.GetWorldRecord(model)
	if record == nil then
		return nil, nil, state
	end
	return model, record, state
end

function DevelopmentBrainrotSpawner.IsWild(runtimeId: any): boolean
	return type(runtimeId) == "string" and productionPopulation.Members[runtimeId] ~= nil
end

function DevelopmentBrainrotSpawner.HasOrdinaryReservation(runtimeId: any): boolean
	return DevelopmentBrainrotSpawner.IsWild(runtimeId)
end

-- HP and transport state live on the existing ordinary member, never a second
-- inventory. Record copies and visual transfers all address the same ItemId.
function DevelopmentBrainrotSpawner.GetPhase12State(record: any): any?
	if type(record) ~= "table" or type(record.Metadata) ~= "table"
		or record.Metadata.DurableOwnerUserId ~= nil then return nil end
	local member = productionPopulation.Members[record.ItemId]
	if not member or member.SpeciesId ~= record.BrainrotId then return nil end
	return member.Phase12
end

function DevelopmentBrainrotSpawner.PublishPhase12State(model: Model, record: any)
	local state=DevelopmentBrainrotSpawner.GetPhase12State(record)
	if not state or not model.Parent then return end
	model:SetAttribute("Phase12CapturedOnce",state.CapturedOnce)
	model:SetAttribute("Phase12MaxHp",state.MaxHp)
	model:SetAttribute("Phase12RemainingHp",state.RemainingHp)
	if state.Route then
		model:SetAttribute("EntranceBurrowId",state.Route.EntranceBurrowId)
		model:SetAttribute("DestinationBurrowId",state.Route.DestinationBurrowId)
		model:SetAttribute("BrainrotRouteId",state.Route.RouteId)
		model:SetAttribute("BrainrotRouteVersion",state.Route.RouteVersion)
		model:SetAttribute("BrainrotRouteGeneration",state.Route.Generation)
	end
end

function DevelopmentBrainrotSpawner.NotifyAcceptedDamage(record: any, at: number?): (boolean,string?)
	local time=at or Workspace:GetServerTimeNow()
	if not finite(time)then return false,"INVALID_TIME"end
	local state,reason=DevelopmentBrainrotSpawner.UpdatePhase12State(record,{LastAcceptedDamageTime=time})
	return state~=nil,reason
end

function DevelopmentBrainrotSpawner.GetRouteSnapshot(record: any): any?
	if typeof(record)=="Instance"then local registration=registrations[record];record=registration and registration.Record end
	local state=DevelopmentBrainrotSpawner.GetPhase12State(record)
	return if state and state.Route then copyData(state.Route)else nil
end

function DevelopmentBrainrotSpawner.ValidateFreshRouteRelease(record: any, pose: CFrame, ignored: {Instance}?): (boolean,string?,any?)
	if type(record)=="table" and pendingBanks[record.ItemId] then return false,"PENDING_BANK_SAVE"end
	local state=DevelopmentBrainrotSpawner.GetPhase12State(record)
	if not state then
		if RunService:IsStudio()and type(record)=="table"and type(record.World)=="table"and not record.World.SpawnRegionId then return true,nil,nil end
		return false,"NOT_ORDINARY"
	end
	if not state.Route then
		-- Trusted, non-natural Studio fixtures retain the old isolated harness API.
		if RunService:IsStudio()and type(record.World)=="table"and not record.World.SpawnRegionId then return true,nil,nil end
		return false,"ORDINARY_ROUTE_MISSING"
	end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=ignored or {};params.RespectCanCollide=true
	local hit=Workspace:Raycast(pose.Position+Vector3.yAxis*8,-Vector3.yAxis*16,params)
	if not hit then return false,"NO_ROUTE_RELEASE_SUPPORT"end
	local reconnect,reason=RouteCatalog.FindReconnect(state.Route,hit.Position,ignored)
	return reconnect~=nil,reason,reconnect
end

function DevelopmentBrainrotSpawner.UpdatePhase12State(record: any, changes: any): (any?, string?)
	local previous = DevelopmentBrainrotSpawner.GetPhase12State(record)
	if not previous or previous.Retired then return nil, "NOT_ORDINARY_OR_RETIRED" end
	local member = productionPopulation.Members[record.ItemId]
	local nextState = table.clone(previous)
	if type(changes) == "function" then
		if changes(nextState) == false then return nil, "STATE_UPDATE_REJECTED" end
	elseif type(changes) == "table" then
		for key, value in changes do nextState[key] = value end
	else return nil, "INVALID_STATE_UPDATE" end
	if not finite(nextState.MaxHp) or nextState.MaxHp <= 0
		or not finite(nextState.RemainingHp) or nextState.RemainingHp < 0 or nextState.RemainingHp > nextState.MaxHp
		or not finite(nextState.EscapeAttemptsUsed) or nextState.EscapeAttemptsUsed < 0 or nextState.EscapeAttemptsUsed % 1 ~= 0
		or not finite(nextState.EscapeMaxAttempts) or nextState.EscapeMaxAttempts < nextState.EscapeAttemptsUsed
		or nextState.EscapeMaxAttempts % 1 ~= 0
		or (nextState.EscapeRemainingSeconds ~= nil and (not finite(nextState.EscapeRemainingSeconds) or nextState.EscapeRemainingSeconds < 0))
		or (nextState.EscapeDeadline ~= nil and not finite(nextState.EscapeDeadline)) then
		return nil, "INVALID_PHASE12_STATE"
	end
	-- A callback must be synchronous. If its exact member changed, the old result
	-- cannot replace a newer transport/capture transition.
	if productionPopulation.Members[record.ItemId] ~= member then return nil, "STATE_REVISION_CHANGED" end
	nextState.Revision = previous.Revision + 1
	local replacement = table.clone(member)
	replacement.Phase12 = table.freeze(nextState)
	productionPopulation.Members[record.ItemId] = table.freeze(replacement)
	return replacement.Phase12, nil
end

function DevelopmentBrainrotSpawner.RetireFreshIndividual(record: any, reason: string?): (boolean, string?)
	if type(record)=="table" and pendingBanks[record.ItemId] then return false,"PENDING_BANK_SAVE"end
	local phaseState = DevelopmentBrainrotSpawner.GetPhase12State(record)
	if not phaseState then return false, "NOT_ORDINARY_OR_BANKED" end
	-- Remove the reservation before any Destroying/death callback can attempt to
	-- recreate the old source. Such callbacks now fail the ordinary-member check.
	local removed, failure = unregisterWild(productionPopulation, record.ItemId, reason or "Phase12Reset")
	if not removed then return false, failure end
	for _, observer in table.clone(freshRetirementSubscribers) do pcall(observer,record,reason or "Phase12Reset")end
	pendingFreshReleases[record.ItemId] = nil
	for token in table.clone(freshReleaseTokens) do
		if token.Record.ItemId == record.ItemId then DevelopmentBrainrotSpawner.DiscardFreshRelease(token) end
	end
	local model = modelsById[record.ItemId]
	if model then
		model:SetAttribute("Phase12Retired", true)
		pendingUnregisterReason[model] = reason or "Phase12Reset"
		unregister(model, reason or "Phase12Reset")
		model:Destroy()
	end
	if requestProductionReconcile then requestProductionReconcile(reason or "Retired",BrainrotPopulation.ReplenishDelaySeconds)end
	return true, nil
end

-- Reset retires every fresh world representation, including Camp. Committed
-- cargo has a different owner and is deliberately absent from this collection.
function DevelopmentBrainrotSpawner.ResetOutsideCamp(_isInCamp: (Vector3) -> boolean, cycleId: number): any
	currentResetGeneration = cycleId
	-- Prepared releases are visual staging only. Fence every old-cycle callback,
	-- including the preparations whose committed cargo member survives this reset.
	for token in table.clone(freshReleaseTokens) do
		DevelopmentBrainrotSpawner.DiscardFreshRelease(token)
	end
	local retired = {}
	local representations = {}
	for model, registration in table.clone(registrations) do
		local record = registration.Record
		if record.Metadata.DurableOwnerUserId == nil and not pendingBanks[record.ItemId] then
			local bounds,size=model:GetBoundingBox()
			table.insert(representations,{ItemId=record.ItemId,BrainrotId=record.BrainrotId,MutationId=record.Metadata.MutationId or "None",
				Pose=bounds,Bounds=size,WorldPivot=model:GetPivot(),SourceGeneration=registration.LifecycleRevision})
			if DevelopmentBrainrotSpawner.RetireFreshIndividual(record, "Phase12Reset") then table.insert(retired, record.ItemId) end
		end
	end
	for itemId, pending in table.clone(pendingFreshReleases) do
		if not pendingBanks[itemId] and DevelopmentBrainrotSpawner.RetireFreshIndividual(pending.Record, "Phase12Reset") then
			table.insert(retired, itemId)
		end
	end
	local cancelledReservations = 0
	for reservationId in table.clone(productionPopulation.Reservations) do
		-- Every pending natural reservation belongs to a hunting region. Retire
		-- before selecting replacements; never momentarily double the 42 slots.
		if removeReservation(productionPopulation, reservationId, "Phase12Reset") then cancelledReservations += 1 end
	end
	table.sort(retired)
	if requestProductionReconcile then requestProductionReconcile("Phase12Reset", Phase12.SpawnConstructionInterval) end
	return { RetiredIds = retired, RetiredCount = #retired, CancelledReservations = cancelledReservations,
		SurvivingOrdinary = productionPopulation.WildCount, CycleId = cycleId,Representations=representations }
end

function DevelopmentBrainrotSpawner.GetWildCount(): number
	return productionPopulation.WildCount
end

function DevelopmentBrainrotSpawner.GetWildSnapshot(): { WildMember }
	return table.clone(populationSnapshot(productionPopulation).Members)
end

function DevelopmentBrainrotSpawner.GetPopulationSnapshot(): any
	local snapshot = table.clone(populationSnapshot(productionPopulation))
	local pending = {}
	for id, release in pendingFreshReleases do
		table.insert(
			pending,
			table.freeze({
				ItemId = id,
				BrainrotId = release.Record.BrainrotId,
				Position = release.Pose.Position,
				Pose = release.Pose,
				MutationId = Phase12Rules.RecordMutation(release.Record),
				RetryAt = release.RetryAt,
				LastError = release.LastError,
			})
		)
	end
	snapshot.PendingWorldRecords = table.freeze(pending)
	local awake=0
	for model,registration in registrations do
		if not registration.Sleeping and not pendingPublication[model] and model.Parent~=nil
			and model:GetAttribute("Phase12InteractionReady")~=false
			and productionPopulation.Members[registration.Record.ItemId]~=nil then awake+=1 end
	end
	snapshot.AwakeCreatures=awake
	return table.freeze(snapshot)
end

function DevelopmentBrainrotSpawner.ValidatePopulationConsistency(): (boolean, { string })
	return validatePopulationConsistency(productionPopulation)
end

function DevelopmentBrainrotSpawner.CommitSpawnReservation(reservationId: any, runtimeId: any): (boolean, string?)
	return commitReservation(productionPopulation, reservationId, runtimeId, function(reservation, expectedRuntimeId)
		local model = modelsById[expectedRuntimeId]
		local registration = if model then registrations[model] else nil
		return registration ~= nil
			and registration.Record.ItemId == expectedRuntimeId
			and registration.Record.BrainrotId == reservation.SpeciesId
			and model.Parent == getBrainrotFolder()
	end)
end

function DevelopmentBrainrotSpawner.ReleaseSpawnReservation(reservationId: any, reason: string?): (boolean, string?)
	local reservation, releaseReason = removeReservation(productionPopulation, reservationId, reason or "Failed")
	if reservation == nil then
		return false, releaseReason
	end
	return true, nil
end

-- World registration is the lifecycle truth. This helper is safe for duplicate
-- state-change signals and never infers membership from a presentation clone.
function DevelopmentBrainrotSpawner.SyncWildMembership(brainrot: Model): (boolean, string?)
	local registration = registrations[brainrot]
	if registration and brainrot.Parent == getBrainrotFolder() then
		return registerWild(
			productionPopulation,
			registration.Record.ItemId,
			registration.Record.BrainrotId,
			registration.PopulationRegionId
		)
	end
	local runtimeId = brainrot:GetAttribute("ItemId")
	if Phase10.Enabled then
		return false, "VISUAL_NOT_AUTHORITATIVE"
	end
	return unregisterWild(productionPopulation, runtimeId, "LifecycleSync")
end

-- Body is the real centre reference. Cache only original visual geometry at
-- registration, before runtime decorations; compound body parts also count as
-- visible body hits, not walls occluding their own creature. The cache lives and
-- dies with the registry. Store UNPADDED dimensions and a pivot-relative frame.
function DevelopmentBrainrotSpawner.GetHuntBounds(
	brainrot: Model,
	expectedRecord: WorldRecord
): (CFrame?, Vector3?, BasePart?, {
	[Instance]: boolean,
}?)
	local record, state = DevelopmentBrainrotSpawner.GetWorldRecord(brainrot)
	if record ~= expectedRecord or state ~= "WorldAwake" then
		return nil, nil, nil, nil
	end
	local registration = registrations[brainrot]
	local cached = registration.HuntBody
	if not cached or not cached.Body:IsDescendantOf(brainrot) or not cached.Body.CanQuery then
		return nil, nil, nil, nil
	end
	if cached.Scale ~= brainrot:GetScale() then
		cached = measureHuntBody(brainrot, cached.Body, cached.Parts)
		registration.HuntBody = cached
	end
	return brainrot:GetPivot() * cached.LocalFrame,
		Vector3.new(
			math.max(cached.Size.X * 2.5, 12),
			math.max(cached.Size.Y * 2.5, 12),
			math.max(cached.Size.Z * 2.5, 12)
		),
		cached.Body,
		cached.Parts
end

-- Synchronous ownership handoff. The caller must already have staged its carry
-- visual and same-record return preparation; neither caller nor this path yields.
function DevelopmentBrainrotSpawner.TakeSleepingWorld(
	brainrot: Model,
	expectedRecord: WorldRecord,
	playerControlledRecord: WorldRecord?
): (boolean, WorldRecord?)
	local registration = registrations[brainrot]
	if
		not registration
		or registration.Record ~= expectedRecord
		or not registration.Sleeping
		or brainrot.Parent ~= getBrainrotFolder()
	then
		return false, nil
	end
	local controlledRecord, controlledReason
	if playerControlledRecord then
		controlledRecord = playerControlledRecord
	else
		controlledRecord, controlledReason = NaturalTerritory.ClearForPlayerControl(expectedRecord)
	end
	if
		controlledRecord == nil
		or controlledRecord.ItemId ~= expectedRecord.ItemId
		or controlledRecord.BrainrotId ~= expectedRecord.BrainrotId
		or NaturalTerritory.GetTerritoryRegionId(controlledRecord) ~= nil
		or NaturalTerritory.GetSpawnRegionId(controlledRecord) ~= NaturalTerritory.GetSpawnRegionId(expectedRecord)
	then
		return false, nil
	end
	if controlledReason ~= nil then
		return false, nil
	end
	registration.Record = controlledRecord
	pendingUnregisterReason[brainrot] = "PickedUp"
	brainrot.Parent = nil
	unregister(brainrot, "PickedUp")
	return true, controlledRecord
end

function DevelopmentBrainrotSpawner.CreatePlayerControlledRecord(record: WorldRecord): (WorldRecord?, string?)
	return NaturalTerritory.ClearForPlayerControl(record)
end

function DevelopmentBrainrotSpawner.TrySleep(brainrot: Model): (boolean, string?)
	local record, state = DevelopmentBrainrotSpawner.GetWorldRecord(brainrot)
	if Phase10.Enabled and record and type(record.Metadata.DurableOwnerUserId) == "number" then
		return false, "BANKED_PROTECTED"
	end
	if record == nil then
		return false, state
	end
	if state ~= "WorldAwake" then
		return false, "ALREADY_SLEEPING"
	end
	if not Roaming.Pause(brainrot, "Sleeping") then
		return false, "NOT_REGISTERED"
	end
	local registration = registrations[brainrot]
	local now = sleepClock()
	registration.Sleeping = true
	registration.SleepStartedAt = now
	registration.SleepUntil = now + (Phase12Rules.GroundSleepForSpecies(record.BrainrotId)or BrainrotInteraction.SLEEP_DURATION_SECONDS)
	registration.LifecycleRevision += 1
	brainrot:SetAttribute("Captured", true)
	brainrot:SetAttribute("BrainrotSleepUntil", registration.SleepUntil)
	brainrot:SetAttribute("BrainrotLifecycleRevision", registration.LifecycleRevision)
	if Phase12.Enabled then
		DevelopmentBrainrotSpawner.UpdatePhase12State(record,function(nextState)
			nextState.CapturedOnce=true;nextState.RemainingHp=0
			if nextState.Route then nextState.Route=table.freeze(RouteRules.PauseForSleep(nextState.Route))end
		end)
		DevelopmentBrainrotSpawner.PublishPhase12State(brainrot,record)
	end
	BrainrotDisplayMetadata.Apply(brainrot, record, BrainrotDisplayConfig.States.Sleeping, nil)
	log:Debug(
		"BrainrotSleepStarted runtimeId=%s speciesId=%s revision=%d sleepUntil=%.3f",
		record.ItemId,
		record.BrainrotId,
		registration.LifecycleRevision,
		registration.SleepUntil
	)
	worldChanged:Fire(brainrot)
	return true, nil
end

-- Only explicit sleep may wake this same representation. A legacy net/reel
-- target must retire its old Model and use prepare/activate: its delayed capture
-- closures refer to that old instance and must never reach the returned clone.
function DevelopmentBrainrotSpawner.ResumeWorld(brainrot: Model): (boolean, string?)
	local registration = registrations[brainrot]
	if registration == nil or brainrot.Parent ~= getBrainrotFolder() then
		return false, "NOT_REGISTERED"
	end
	if Phase10.Enabled and type(registration.Record.Metadata.DurableOwnerUserId) == "number" then
		return true, nil -- Secured owner-only sleeper retains durable ownership.
	end
	if brainrot:GetAttribute("Captured") == true and not registration.Sleeping then
		return false, "LEGACY_CAPTURE_REQUIRES_RESTORATION"
	end
	-- Registration already starts a fresh world representation awake. Keep that
	-- activation path idempotent: lifecycle revisions describe real state changes,
	-- not reconstruction callbacks that happen to ask for the current state again.
	if not registration.Sleeping then
		return true, nil
	end
	registration.Sleeping = false
	registration.SleepStartedAt = nil
	registration.SleepUntil = nil
	registration.LifecycleRevision += 1
	if registration.SleepIndicator then
		registration.SleepIndicator:Destroy()
		registration.SleepIndicator = nil
	end
	brainrot:SetAttribute("Captured", false)
	brainrot:SetAttribute("BrainrotSleepUntil", nil)
	brainrot:SetAttribute("BrainrotLifecycleRevision", registration.LifecycleRevision)
	local resumed = Roaming.Resume(brainrot, brainrot:GetPivot().Position)
	if resumed then
		local record=registration.Record
		local state=DevelopmentBrainrotSpawner.GetPhase12State(record)
		if Phase12.Enabled and state then
			DevelopmentBrainrotSpawner.UpdatePhase12State(record,{RemainingHp=state.MaxHp})
		end
		DevelopmentBrainrotSpawner.PublishPhase12State(brainrot,record)
		BrainrotDisplayMetadata.Apply(brainrot, registration.Record, BrainrotDisplayConfig.States.Awake, nil)
	end
	worldChanged:Fire(brainrot)
	return resumed, nil
end

function DevelopmentBrainrotSpawner.ProcessSleepExpirations(now: number?): number
	local at = now or sleepClock()
	if not finite(at) then
		return 0
	end
	local expired = {}
	for brainrot, registration in registrations do
		if
			registration.Sleeping
			and registration.SleepUntil ~= nil
			and at >= registration.SleepUntil
			and brainrot.Parent == getBrainrotFolder()
		then
			table.insert(expired, brainrot)
		end
	end
	local resumed = 0
	for _, brainrot in expired do
		local registration = registrations[brainrot]
		if
			registration
			and registration.Sleeping
			and registration.SleepUntil ~= nil
			and at >= registration.SleepUntil
		then
			local record = registration.Record
			if DevelopmentBrainrotSpawner.ResumeWorld(brainrot) then
				resumed += 1
				log:Debug(
					"BrainrotSleepExpired runtimeId=%s speciesId=%s revision=%d",
					record.ItemId,
					record.BrainrotId,
					registration.LifecycleRevision
				)
			end
		end
	end
	return resumed
end

-- Bounded read-only diagnostic fanout. Failure/disconnect cannot undo
-- successful retirement or mutate current ownership/population state.
function DevelopmentBrainrotSpawner.SubscribeFreshRetirementObserver(observer: (any,string)->()): (any?,string?)
	if type(observer) ~= "function" then return nil,"INVALID_OBSERVER" end
	local count = 0
	for _ in freshRetirementSubscribers do count += 1 end
	if count >= 8 then return nil,"RETIREMENT_OBSERVER_LIMIT" end
	local connection = {}
	freshRetirementSubscribers[connection] = observer
	function connection.Disconnect()
		freshRetirementSubscribers[connection] = nil
	end
	return connection,nil
end

function DevelopmentBrainrotSpawner.SetAdmissionObserver(observer: ((string,string)->())?)
	admissionObserver=observer
end

function DevelopmentBrainrotSpawner._TestSetSleepClock(provider: (() -> number)?)
	sleepClock = provider or function(): number
		return Workspace:GetServerTimeNow()
	end
end

function DevelopmentBrainrotSpawner.Unregister(brainrot: Model): (boolean, string?)
	local folder = getBrainrotFolder()
	if folder ~= nil and brainrot.Parent == folder then
		return false, "STILL_IN_WORLD"
	end
	unregister(brainrot, "Removed")
	return true, nil
end

-- Saved ownership deliberately has no world pose, timer or territory. Rebuild
-- only the runtime return envelope when the existing platform owner has already
-- validated an exact restored individual for pickup. This is not a new spawn:
-- no GUID, metadata roll, clone, registration or profile write occurs here.
function DevelopmentBrainrotSpawner.CreateRestoredWorldRecord(record: any, pose: CFrame): (WorldRecord?, string?)
	if
		type(record) ~= "table"
		or type(record.ItemId) ~= "string"
		or record.ItemId == ""
		or type(record.BrainrotId) ~= "string"
		or type(record.Metadata) ~= "table"
		or not finite(record.Metadata.DurableOwnerUserId)
		or record.World ~= nil
		or not validPose(pose)
	then
		return nil, "INVALID_RESTORED_RECORD_OR_POSE"
	end
	local source = getTemplate(record.BrainrotId)
	if source == nil then
		return nil, "INVALID_ASSET"
	end
	local scale = source:GetScale()
	if not finite(scale) or scale <= 0 then
		return nil, "INVALID_ASSET_SCALE"
	end
	local copied, metadata = pcall(copyData, record.Metadata)
	if not copied then
		return nil, "INVALID_METADATA"
	end
	local position = pose.Position
	return table.freeze({
		ItemId = record.ItemId,
		BrainrotId = record.BrainrotId,
		Metadata = metadata,
		World = table.freeze({
			Name = "Brainrot_" .. record.BrainrotId .. "_Restored",
			Scale = scale,
			SpawnPosition = table.freeze({ X = position.X, Y = position.Y, Z = position.Z }),
		}),
	}),
		nil
end

function DevelopmentBrainrotSpawner.PrepareWorldRepresentation(record: WorldRecord, pose: CFrame): (any?, string?)
	local spawnRegionId = if type(record) == "table" and type(record.World) == "table"
		then record.World.SpawnRegionId
		else nil
	local territoryRegionId = if type(record) == "table" and type(record.World) == "table"
		then record.World.TerritoryRegionId
		else nil
	local returnRegionId = if type(record) == "table" and type(record.World) == "table"
		then record.World.ReturnRegionId
		else nil
	if
		type(record) ~= "table"
		or type(record.ItemId) ~= "string"
		or record.ItemId == ""
		or type(record.BrainrotId) ~= "string"
		or type(record.Metadata) ~= "table"
		or type(record.World) ~= "table"
		or not finite(record.World.Scale)
		or record.World.Scale <= 0
		or type(record.World.Name) ~= "string"
		or type(record.World.SpawnPosition) ~= "table"
		or not finite(record.World.SpawnPosition.X)
		or not finite(record.World.SpawnPosition.Y)
		or not finite(record.World.SpawnPosition.Z)
		or not validPose(pose)
		or (spawnRegionId ~= nil and (type(spawnRegionId) ~= "string" or Regions.NormalizeId(spawnRegionId) ~= spawnRegionId or spawnRegionId == Regions.CampId))
		or (territoryRegionId ~= nil and (type(territoryRegionId) ~= "string" or territoryRegionId ~= spawnRegionId or Regions.NormalizeId(
			territoryRegionId
		) ~= territoryRegionId))
		or (
			returnRegionId ~= nil
			and (
				type(returnRegionId) ~= "string"
				or Regions.NormalizeId(returnRegionId) ~= returnRegionId
				or returnRegionId == Regions.CampId
				or territoryRegionId ~= nil
			)
		)
	then
		return nil, "INVALID_RECORD_OR_POSE"
	end
	local source = getTemplate(record.BrainrotId)
	if source == nil then
		return nil, "INVALID_ASSET"
	end
	local model: Model? = nil
	local saved: WorldRecord? = nil
	local ok = pcall(function()
		local copied = copyData(record) :: WorldRecord
		model = CreatureAssets.CreateProxy(record.BrainrotId)
		assert(model, "World template could not be cloned")
		local clone = model :: Model
		assert(hasHitGeometry(clone), "World template needs queryable Body")
		clone.Name = record.World.Name
		local scaled, _, scaleReason = BrainrotVisualScale.ApplyCanonicalScale(clone, "WorldPrepared")
		assert(scaled, scaleReason)
		saved = withWorldScale(copied, clone:GetScale())
		-- The proxy retains the original query Body, attachments, scale and bounds;
		-- canonical art is supplied selectively to authorized clients.
		for key in transientAttributes do
			clone:SetAttribute(key, nil)
		end
		for key, value in (saved :: WorldRecord).Metadata do
			if not transientAttributes[key] and type(value) ~= "table" then
				clone:SetAttribute(key, value)
			end
		end
		clone:SetAttribute("ItemId", record.ItemId)
		clone:SetAttribute("BrainrotId", record.BrainrotId)
		clone:SetAttribute("Captured", false)
		for _, item in clone:GetDescendants() do
			if item.Name == "BrainrotSleepIndicator" and item:IsA("BillboardGui") then
				item:Destroy()
			end
		end
		clone:PivotTo(pose)
		CartModelUtility.SetAnchored(clone, true)
		CartModelUtility.ZeroVelocities(clone)
	end)
	if not ok or model == nil then
		if model then
			model:Destroy()
		end
		return nil, "INVALID_ASSET_OR_METADATA"
	end
	local prepared = table.freeze({ Model = model, Record = saved })
	preparedByToken[prepared] = prepared
	preparedByModel[model] = true
	return prepared, nil
end

local function isLiveObstacle(instance: Instance): boolean
	local ancestor: Instance? = instance
	while ancestor and ancestor ~= Workspace do
		if
			ancestor:IsA("Model")
			and (
				ancestor:FindFirstChildOfClass("Humanoid") ~= nil
				or ancestor:GetAttribute("RuntimeCart") == true
				or ancestor:GetAttribute("CartId") ~= nil
				or ancestor:GetAttribute("ItemId") ~= nil
			)
		then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

-- Bounded, conservative placement for the current upright, constant-height
-- roaming policy. No region registry/ground helper currently owns world roamers.
-- Only the detached preparation and retired presentation may be ignored here;
-- characters, carts, other creatures and solid scenery remain obstacles.
function DevelopmentBrainrotSpawner.FindSafeReleasePose(
	prepared: any,
	sourcePose: CFrame,
	ignoredPresentation: { Instance },
	exactFallback: boolean?,
	carrier: Model?,
	releaseCart: any? -- Live cart for replacement, cached {Radius} after cart removal.
): CFrame?
	local staged = preparedByToken[prepared]
	if not staged or staged.Model.Parent ~= nil or not validPose(sourcePose) then
		return nil
	end
	local model = staged.Model
	local pivot = model:GetPivot()
	local bounds, size = model:GetBoundingBox()
	local relativeBounds = pivot:ToObjectSpace(bounds)
	local half = size / 2
	local extent = Vector3.new(
		math.abs(bounds.RightVector.X) * half.X
			+ math.abs(bounds.UpVector.X) * half.Y
			+ math.abs(bounds.LookVector.X) * half.Z,
		math.abs(bounds.RightVector.Y) * half.X
			+ math.abs(bounds.UpVector.Y) * half.Y
			+ math.abs(bounds.LookVector.Y) * half.Z,
		math.abs(bounds.RightVector.Z) * half.X
			+ math.abs(bounds.UpVector.Z) * half.Y
			+ math.abs(bounds.LookVector.Z) * half.Z
	)
	local bottomOffset = bounds.Y - extent.Y - pivot.Y
	local footprint = math.sqrt(extent.X ^ 2 + extent.Z ^ 2)
	local distance = math.max(5, footprint + 2.5)
	if not exactFallback and distance > (if Phase10.Enabled then Phase10.DropRadius else 12) then
		return nil -- Do not move a large species arbitrarily far to make it fit.
	end
	if releaseCart and not exactFallback and not Phase10.Enabled then
		-- Same ground, obstacle and transit policy as Drop, but begin outside the
		-- cart's CURRENT horizontal bounds rather than inside chassis/wheels.
		local radius
		if typeof(releaseCart) == "Instance" and releaseCart:IsA("Model") then
			if not releaseCart:IsDescendantOf(Workspace) then
				return nil
			end
			local cartBounds, cartSize = releaseCart:GetBoundingBox()
			local centreOffset = (Vector2.new(cartBounds.X, cartBounds.Z) - Vector2.new(sourcePose.X, sourcePose.Z)).Magnitude
			radius = centreOffset + cartSize.Magnitude / 2
		elseif type(releaseCart) == "table" and finite(releaseCart.Radius) and releaseCart.Radius >= 0 then
			radius = releaseCart.Radius
		else
			return nil
		end
		distance = math.max(distance, radius + footprint + 1)
		if distance > (if Phase10.Enabled then Phase10.DropRadius else 32) then
			return nil
		end -- Bounded nearby release, never a distant fallback.
	end
	local sourceRegion = if Phase10.Enabled
		then RegionSpawnCatalog.GetRegionAtPosition(sourcePose.Position, math.huge)
		else nil
	local sourceInCamp = Phase10.Enabled
		and RegionSpawnCatalog.ContainsPosition(Regions.CampId, sourcePose.Position, 30)
	local forward = Vector3.new(sourcePose.LookVector.X, 0, sourcePose.LookVector.Z)
	forward = if forward.Magnitude > 0.001 then forward.Unit else Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis)
	local offsets = if exactFallback
		then { Vector3.zero }
		else {
			forward,
			right,
			-right,
			(forward + right).Unit,
			(forward - right).Unit,
			(-forward + right).Unit,
			(-forward - right).Unit,
			-forward,
		}
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, ignoredPresentation
	params.RespectCanCollide = true
	params.IgnoreWater = false
	local overlap = OverlapParams.new()
	overlap.FilterType, overlap.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, ignoredPresentation
	overlap.RespectCanCollide = true
	local queryOverlap = OverlapParams.new()
	queryOverlap.FilterType, queryOverlap.FilterDescendantsInstances =
		Enum.RaycastFilterType.Exclude, ignoredPresentation
	local transit = RaycastParams.new()
	local transitIgnored = table.clone(ignoredPresentation)
	if carrier then
		table.insert(transitIgnored, carrier) -- Only the sweep's starting carrier, not the destination.
	end
	if Phase10.Enabled and typeof(releaseCart) == "Instance" then
		table.insert(transitIgnored, releaseCart)
	end
	transit.FilterType, transit.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, transitIgnored
	transit.RespectCanCollide = true
	for _, direction in offsets do
		local point = sourcePose.Position + direction * distance
		local proposed = CFrame.new(point) * pivot.Rotation
		local centre = (proposed * relativeBounds).Position
		local low, high = math.huge, -math.huge
		local supported = true
		for _, sample in
			{
				Vector3.zero,
				Vector3.new(-extent.X, 0, -extent.Z),
				Vector3.new(extent.X, 0, -extent.Z),
				Vector3.new(-extent.X, 0, extent.Z),
				Vector3.new(extent.X, 0, extent.Z),
			}
		do
			local ground = Workspace:Raycast(
				Vector3.new(centre.X, sourcePose.Y + 2, centre.Z) + sample,
				Vector3.new(0, -14, 0),
				params
			)
			if
				not ground
				or ground.Normal.Y < 0.98
				or ground.Material == Enum.Material.Water
				or isLiveObstacle(ground.Instance)
				or (Phase10.Enabled and not CartLocalPlacement.IsBrainrotSupport(ground, sourceInCamp))
				or (
					ground.Instance:IsA("BasePart")
					and not ground.Instance:IsA("Terrain")
					and not ground.Instance.Anchored
				)
			then
				supported = false
				break
			end
			low, high = math.min(low, ground.Position.Y), math.max(high, ground.Position.Y)
			-- Also catch Terrain/overhangs, which part-bound overlap alone cannot prove clear.
			if
				Workspace:Raycast(ground.Position + Vector3.new(0, 0.15, 0), Vector3.new(0, extent.Y * 2, 0), params)
			then
				supported = false
				break
			end
		end
		if not supported or high - low > 0.25 then
			continue
		end
		proposed = CFrame.new(
			point.X,
			high - bottomOffset + (if Phase10.Enabled then Phase10.SafetySkin else 0.1),
			point.Z
		) * pivot.Rotation
		local box = proposed * relativeBounds
		if Phase10.Enabled then
			if not sourceInCamp and RegionSpawnCatalog.IsProtectedSpace(box, size) then
				continue
			end
			if
				sourceRegion
				and sourceRegion.kind == "Hunting"
				and not RegionSpawnCatalog.IsInsideRegionSpace(sourceRegion.id, box, size, 0)
			then
				continue
			end
		end
		local clearanceSize = size
			+ Vector3.new(
				if Phase10.Enabled then Phase10.SafetySkin * 2 else 0.2,
				0,
				if Phase10.Enabled then Phase10.SafetySkin * 2 else 0.2
			)
		if #Workspace:GetPartBoundsInBox(box, clearanceSize, overlap) > 0 then
			continue
		end
		local blocked = false
		for _, part in Workspace:GetPartBoundsInBox(box, clearanceSize, queryOverlap) do
			if isLiveObstacle(part) then
				blocked = true
				break
			end
		end
		if blocked then
			continue
		end
		if
			Phase10.Enabled
			and (
				not CartLocalPlacement.IsBrainrotGateClear(box, size)
				or not CartLocalPlacement.IsTerrainClear(box, clearanceSize)
			)
		then
			continue
		end
		if not exactFallback then
			local start = Vector3.new(sourcePose.X, box.Y, sourcePose.Z)
			local delta = box.Position - start
			if
				delta.Magnitude > 0.001
				and Workspace:Blockcast(CFrame.new(start) * box.Rotation, clearanceSize, delta, transit)
			then
				continue -- Never drop through a thin wall into an adjacent room/base.
			end
		end
		if Phase12.Enabled and staged.Record.Metadata.DurableOwnerUserId==nil then
			local routeClear=DevelopmentBrainrotSpawner.ValidateFreshRouteRelease(staged.Record,proposed,transitIgnored)
			if not routeClear then continue end
		end
		return proposed
	end
	return nil
end

function DevelopmentBrainrotSpawner.ActivatePreparedWorld(
	prepared: any,
	commitOwnership: (() -> boolean)?,
	spawnReservationId: string?
): (Model?, string?)
	local staged = preparedByToken[prepared]
	if staged == nil or staged.Model.Parent ~= nil then
		return nil, "INVALID_PREPARATION"
	end
	local requiredMember=preparedFreshMembers[prepared]
	if requiredMember and productionPopulation.Members[requiredMember]==nil then
		return nil,"FRESH_SOURCE_RETIRED"
	end
	local spawnReservation = if spawnReservationId then productionPopulation.Reservations[spawnReservationId] else nil
	if spawnReservationId and spawnReservation == nil then
		return nil, "UNKNOWN_RESERVATION"
	end
	if spawnReservation and spawnReservation.SpeciesId ~= staged.Record.BrainrotId then
		return nil, "RESERVATION_SPECIES_MISMATCH"
	end
	local folder = ensureBrainrotFolder()
	local activationRecord = staged.Record
	if
		spawnReservation == nil
		and NaturalTerritory.GetReturnRegionId(activationRecord) == nil
		and not (Phase10.Enabled and type(activationRecord.Metadata.DurableOwnerUserId) == "number")
	then
		local bounds, size = staged.Model:GetBoundingBox()
		local insideCamp = RegionSpawnCatalog.IsInsideRegionSpace(Regions.CampId, bounds, size, 0)
		local currentPhase=DevelopmentBrainrotSpawner.GetPhase12State(activationRecord)
		if insideCamp and not (currentPhase and currentPhase.Route)then
			local homeRegionId, homeReason = RegionSpawnCatalog.ResolveHomeRegion(activationRecord.BrainrotId)
			if homeRegionId == nil then
				log:Warn(
					"CampReturnBlocked runtimeId=%s speciesId=%s code=%s",
					activationRecord.ItemId,
					activationRecord.BrainrotId,
					tostring(homeReason)
				)
				return nil, "CAMP_RETURN_REGION_INVALID"
			end
			local returning, returnReason = NaturalTerritory.BindCampReturn(activationRecord, homeRegionId)
			if returning == nil then
				return nil, returnReason or "CAMP_RETURN_REGION_INVALID"
			end
			activationRecord = returning
		end
	end
	local previous = modelsById[staged.Record.ItemId]
	if previous ~= nil and previous.Parent == folder then
		return nil, "INDIVIDUAL_ALREADY_IN_WORLD"
	end
	local priorMember = productionPopulation.Members[staged.Record.ItemId]
	local priorState = if priorMember then priorMember.State or "World" else nil
	local deferredPublication = commitOwnership ~= nil or spawnReservation ~= nil
	if deferredPublication then
		pendingPublication[staged.Model] = true
	end
	-- Parenting can fire ChildAdded immediately. The private staging guard keeps
	-- discovery inactive until this exact representation is registered once.
	local ok = pcall(function()
		staged.Model.Parent = folder
		assert(
			registerWorld(
				staged.Model,
				activationRecord,
				if spawnReservation then spawnReservation.RegionId else nil,
				spawnReservation ~= nil
			),
			"World registration failed"
		)
		if commitOwnership then
			-- Fresh preparation is already awake and Register starts ordinary roaming
			-- once. The non-yielding cargo/carry handoff precedes world publication.
			assert(commitOwnership(), "World-return source changed before commit")
		elseif spawnReservation == nil then
			assert(DevelopmentBrainrotSpawner.ResumeWorld(staged.Model), "World resume failed")
		end
		if spawnReservation then
			local committed, commitReason = DevelopmentBrainrotSpawner.CommitSpawnReservation(
				spawnReservation.ReservationId,
				activationRecord.ItemId
			)
			assert(committed, commitReason or "Population reservation commit failed")
		end
	end)
	if not ok then
		pendingUnregisterReason[staged.Model] = "ActivationFailed"
		unregister(staged.Model, "ActivationFailed")
		if priorState then
			setMemberState(productionPopulation, staged.Record.ItemId, priorState)
		end
		-- An externally destroyed staging model has a locked Parent. Retire only
		-- this preparation; never throw while cleaning up or touch another owner.
		DevelopmentBrainrotSpawner.DiscardPreparedWorld(prepared)
		return nil, "ACTIVATION_FAILED"
	end
	preparedByToken[prepared] = nil
	preparedFreshMembers[prepared] = nil
	preparedByModel[staged.Model] = nil
	pendingFreshReleases[activationRecord.ItemId] = nil
	if spawnReservation == nil and activationRecord.Metadata.DurableOwnerUserId == nil then
		local phaseState = DevelopmentBrainrotSpawner.GetPhase12State(activationRecord)
		if phaseState then
			DevelopmentBrainrotSpawner.UpdatePhase12State(activationRecord, function(state)
				if state.EscapeDeadline ~= nil then
					state.EscapeRemainingSeconds = math.max(0,state.EscapeDeadline-sleepClock())
					state.EscapeDeadline = nil
				end
				local registration = registrations[staged.Model]
				if registration and not registration.Sleeping then
					state.RemainingHp = state.MaxHp
				end
			end)
		end
	end
	local routeState=DevelopmentBrainrotSpawner.GetPhase12State(activationRecord)
	if routeState and not routeState.Route and activationRecord.World.RouteJourney then
		DevelopmentBrainrotSpawner.UpdatePhase12State(activationRecord,{Route=copyData(activationRecord.World.RouteJourney)})
		routeState=DevelopmentBrainrotSpawner.GetPhase12State(activationRecord)
	end
	if routeState and routeState.Route then
		local route=RouteCatalog.Get(routeState.Route.RouteId)
		if route then
			Roaming.ConfigureRoute(staged.Model,route,{
				GetState=function()return DevelopmentBrainrotSpawner.GetPhase12State(activationRecord)end,
				Commit=function(nextRoute)
					return DevelopmentBrainrotSpawner.UpdatePhase12State(activationRecord,{Route=table.freeze(nextRoute)})~=nil
				end,
				OnDepart=function()
					if modelsById[activationRecord.ItemId]~=staged.Model then return false end
					if not departureIsFair(activationRecord, staged.Model) then
						huntFlowStats.DepartBlocked += 1
						return false
					end
					return DevelopmentBrainrotSpawner.RetireFreshIndividual(activationRecord,"BurrowDeparture")
				end,
			})
		end
	end
	DevelopmentBrainrotSpawner.PublishPhase12State(staged.Model,activationRecord)
	if deferredPublication then
		pendingPublication[staged.Model] = nil
		-- Once ownership committed, notification failure must never delete the live
		-- individual or replay replacement. Retry only publication of this model.
		local published, failure = pcall(function()
			worldChanged:Fire(staged.Model)
		end)
		if not published then
			published, failure = pcall(function()
				worldChanged:Fire(staged.Model)
			end)
			if not published then
				warn("[World] Committed publication: " .. tostring(failure))
			end
		end
	end
	return staged.Model, nil
end

function DevelopmentBrainrotSpawner.DiscardPreparedWorld(prepared: any): boolean
	local staged = preparedByToken[prepared]
	if staged == nil then
		return false
	end
	preparedByToken[prepared] = nil
	preparedFreshMembers[prepared] = nil
	preparedByModel[staged.Model] = nil
	staged.Model:Destroy()
	pendingPublication[staged.Model] = nil
	return true
end

-- Domain-specific staging: source stays authoritative until the callback commits.
-- Callbacks must not yield and must revalidate exact individual/container/generation.
function DevelopmentBrainrotSpawner.PrepareFreshRelease(
	record: any,
	sourcePose: CFrame,
	ignored: { Instance }?,
	carrier: Model?,
	cart: any?
): (any?, string?)
	if not Phase10.Enabled then
		return nil, "PHASE10_DISABLED"
	end
	if Phase12.Enabled and type(record)=="table" and type(record.Metadata)=="table"
		and record.Metadata.DurableOwnerUserId==nil and not DevelopmentBrainrotSpawner.GetPhase12State(record) then
		return nil,"FRESH_SOURCE_RETIRED_OR_NOT_ORDINARY"
	end
	local controlled, reason = NaturalTerritory.ClearForPlayerControl(record)
	if not controlled then
		return nil, reason
	end
	local prepared, failure = DevelopmentBrainrotSpawner.PrepareWorldRepresentation(controlled, sourcePose)
	if not prepared then
		return nil, failure
	end
	if Phase12.Enabled and controlled.Metadata.DurableOwnerUserId==nil then preparedFreshMembers[prepared]=controlled.ItemId end
	local pose =
		DevelopmentBrainrotSpawner.FindSafeReleasePose(prepared, sourcePose, ignored or {}, false, carrier, cart)
	if not pose then
		DevelopmentBrainrotSpawner.DiscardPreparedWorld(prepared)
		return nil, "NO_SAFE_POSE"
	end
	prepared.Model:PivotTo(pose)
	local token = table.freeze({ Record = controlled, Model = prepared.Model, Pose = pose })
	freshReleaseTokens[token] = { Prepared = prepared, Ignored = ignored or {}, Carrier = carrier, Cart = cart, ResetGeneration=currentResetGeneration }
	return token, nil
end

function DevelopmentBrainrotSpawner.CommitFreshRelease(token: any, commitSource: () -> boolean): (Model?, string?)
	local stage = freshReleaseTokens[token]
	if stage and stage.ResetGeneration~=currentResetGeneration then
		DevelopmentBrainrotSpawner.DiscardFreshRelease(token)
		return nil,"RESET_GENERATION_CHANGED"
	end
	if not stage or type(commitSource) ~= "function" then
		return nil, "INVALID_PREPARATION"
	end
	local prepared = stage.Prepared
	local pose = DevelopmentBrainrotSpawner.FindSafeReleasePose(
		prepared,
		token.Pose,
		stage.Ignored,
		true,
		stage.Carrier,
		stage.Cart
	)
	if not pose then
		return nil, "NO_SAFE_POSE"
	end
	prepared.Model:PivotTo(pose)
	local model, reason = DevelopmentBrainrotSpawner.ActivatePreparedWorld(prepared, commitSource)
	if model then
		freshReleaseTokens[token] = nil
		pendingFreshReleases[token.Record.ItemId] = nil
	end
	return model, reason
end

function DevelopmentBrainrotSpawner.DiscardFreshRelease(token: any): boolean
	local stage = freshReleaseTokens[token]
	if not stage then
		return false
	end
	freshReleaseTokens[token] = nil
	return DevelopmentBrainrotSpawner.DiscardPreparedWorld(stage.Prepared)
end

function DevelopmentBrainrotSpawner.MarkFreshTransit(record: any, location: string): boolean
	if not Phase10.Enabled or type(record) ~= "table" then
		return false
	end
	return setMemberState(productionPopulation, record.ItemId, location)
end

function DevelopmentBrainrotSpawner.MarkFirstAcquisition(record: any): boolean
	local member = if type(record) == "table" then productionPopulation.Members[record.ItemId] else nil
	if not member or member.FirstAcquiredAt ~= nil then
		return false
	end
	local nextMember = table.clone(member)
	nextMember.FirstAcquiredAt = Workspace:GetServerTimeNow()
	productionPopulation.Members[record.ItemId] = table.freeze(nextMember)
	return true
end

function DevelopmentBrainrotSpawner.BeginPendingBank(record: any,operationId: string,coveringRevision: number?): (boolean,string?)
	if not Phase10.Enabled or type(record) ~= "table" then
		return false, "PHASE10_DISABLED"
	end
    local ok,reason=BankBarrier.Begin(pendingBanks,productionPopulation.Members,record,operationId,coveringRevision)
    if not ok then return false,reason end
	setMemberState(productionPopulation,record.ItemId,"PendingBank")
	pendingFreshReleases[record.ItemId]=nil
	return true,nil
end

function DevelopmentBrainrotSpawner.ConfirmPendingBank(record: any,operationId: string): (boolean,string?)
	local id=if type(record)=="table"then record.ItemId else record
	if type(id)~="string"or operationId~="Bank:"..id then return false,"INVALID_BANK_CONFIRMATION"end
    local released,reason=BankBarrier.Confirm(pendingBanks,productionPopulation.Members,id,operationId,function(itemId)
        return firstBank(productionPopulation,itemId)
    end)
    if not released then return false,reason end
    pendingFreshReleases[id]=nil
    if reason=="ALREADY_CONFIRMED" then return true,reason end
	if requestProductionReconcile then requestProductionReconcile("FirstBankConfirmed",nil)end
	return true,nil
end

-- Only the persistence owner calls after a new exact backend acquisition proves
-- absence. A save timeout alone never authorizes this custody transition.
local function pendingBankReleasePreflight(record: any,operationId: string,pose: CFrame): (boolean,string?,any?)
	if not Phase10.Enabled or type(record)~="table"or type(record.ItemId)~="string"
		or operationId~="Bank:"..record.ItemId or not validPose(pose)then return false,"INVALID_BANK_RELEASE",nil end
	if type(record.Metadata)~="table"or record.Metadata.DurableOwnerUserId~=nil then return false,"BANKED_PROTECTED",nil end
	local member=productionPopulation.Members[record.ItemId]
	if not member or member.SpeciesId~=record.BrainrotId then return false,"BANK_RECOVERY_IDENTITY_CHANGED",nil end
	local mutation=Phase12Rules.RecordMutation(record)
	if not mutation or not member.Phase12 or member.Phase12.Retired
		or mutation~=Phase12Rules.NormalizeMutation(member.Phase12.MutationId)then return false,"BANK_RECOVERY_MUTATION_CHANGED",nil end
	local pending=pendingBanks[record.ItemId]
	if not pending then
		local completed=member.PendingBankAbort
		if completed and completed.OperationId==operationId and completed.Record==record
			and completed.MutationId==mutation and completed.Pose==pose then return true,"ALREADY_RELEASED",nil end
		return false,"BANK_NOT_PENDING_OR_RELEASE_POSE_CHANGED",nil
	end
	if pending.OperationId~=operationId or pending.Record~=record or pending.Record.ItemId~=record.ItemId
		or pending.Record.BrainrotId~=record.BrainrotId or member.State~="PendingBank"then
		return false,"BANK_RECOVERY_IDENTITY_CHANGED",nil
	end
	if Phase12Rules.RecordMutation(pending.Record)~=mutation then return false,"BANK_RECOVERY_MUTATION_CHANGED",nil end
	if pendingFreshReleases[record.ItemId]then return false,"BANK_RELEASE_CUSTODY_CONFLICT",nil end
	local controlled,reason=NaturalTerritory.ClearForPlayerControl(pending.Record)
	if not controlled then return false,reason,nil end
	return true,nil,controlled
end

function DevelopmentBrainrotSpawner.CanAbortPendingBankToFreshRelease(record: any,operationId: string,pose: CFrame): (boolean,string?)
	local ok,reason=pendingBankReleasePreflight(record,operationId,pose)
	return ok,reason
end

function DevelopmentBrainrotSpawner.AbortPendingBankToFreshRelease(record: any,operationId: string,pose: CFrame): (boolean,string?)
	local ok,reason,controlled=pendingBankReleasePreflight(record,operationId,pose)
	if not ok or reason=="ALREADY_RELEASED"then return ok,reason end
	local member=productionPopulation.Members[record.ItemId]
	local nextMember=table.clone(member)
	nextMember.State="PendingWorld"
	-- One bounded proof on the existing identity makes post-publication retries
	-- idempotent, including after queue activation. Never move its first pose.
	nextMember.PendingBankAbort=table.freeze({OperationId=operationId,Record=record,Pose=pose,
		MutationId=Phase12Rules.RecordMutation(record)})
	local committed=table.freeze(nextMember)
	-- No yields or observers before local queue custody and member state exist.
	-- The exact same Phase12/route/handling/escape state and count are retained.
	pendingFreshReleases[record.ItemId]={Record=controlled,Pose=pose,SourceCart=nil,RetryAt=0,LastError=nil}
	productionPopulation.Members[record.ItemId]=committed
	pendingBanks[record.ItemId]=nil
	pcall(emitPopulationChanged,productionPopulation,"OrdinaryStateChanged",committed)
	return true,nil
end

-- Ordinary logout uses PublishExistingWorldDrop. Absence is not spawn credit.
function DevelopmentBrainrotSpawner.RetireUnconfirmedPendingBank(_record: any,_operationId: string): (boolean,string?)
	return false,"SAVE_CONFIRMATION_OR_COUNTED_RELEASE_REQUIRED"
end

-- Compatibility name is now confirmation-only; in-memory ownership is not durability.
function DevelopmentBrainrotSpawner.CommitFirstBank(_record: any): (boolean,string?)
	return false,"COVERING_SAVE_CONFIRMATION_REQUIRED"
end

function DevelopmentBrainrotSpawner.IsPendingBank(itemId: string): boolean
	return pendingBanks[itemId]~=nil
end

-- Unavoidable departure accepts a counted pending destination. No species reroll,
-- spawn-point/base fallback, expiry, or durable-profile promotion.
function DevelopmentBrainrotSpawner.CanQueueFreshRelease(record: any, pose: CFrame): (boolean, string?)
	if not Phase10.Enabled or type(record) ~= "table" or not validPose(pose) then
		return false, "INVALID_RELEASE"
	end
	if pendingBanks[record.ItemId] then return false,"PENDING_BANK_SAVE"end
	local member = productionPopulation.Members[record.ItemId]
	if not member then
		return false, "NOT_ORDINARY"
	end
	if member.SpeciesId ~= record.BrainrotId then
		return false, "IDENTITY_CONFLICT"
	end
	if type(record.Metadata) ~= "table" or record.Metadata.DurableOwnerUserId ~= nil then
		return false, "BANKED_PROTECTED"
	end
	local controlled, reason = NaturalTerritory.ClearForPlayerControl(record)
	if not controlled then
		return false, reason
	end
	return true, nil
end

function DevelopmentBrainrotSpawner.QueueFreshRelease(record: any, pose: CFrame, sourceCart: Model?): (boolean, string?)
	local permitted, preflightReason = DevelopmentBrainrotSpawner.CanQueueFreshRelease(record, pose)
	if not permitted then
		return false, preflightReason
	end
	if pendingFreshReleases[record.ItemId] then
		return true, "ALREADY_PENDING"
	end
	local controlled, reason = NaturalTerritory.ClearForPlayerControl(record)
	if not controlled then
		return false, reason
	end
	pendingFreshReleases[record.ItemId] =
		{ Record = controlled, Pose = pose, SourceCart = sourceCart, RetryAt = 0, LastError = nil }
	setMemberState(productionPopulation, record.ItemId, "PendingWorld")
	return true, nil
end

function DevelopmentBrainrotSpawner.ProcessPendingFreshReleases(now: number?): number
	local at = now or os.clock()
	if at < lastPendingReleasePass + Phase10.RetrySeconds then
		return 0
	end
	lastPendingReleasePass = at
	local attempted = 0
	for itemId, pending in pendingFreshReleases do
		if attempted >= BrainrotPopulation.MaxSpawnReservationsPerPass then
			break
		end
		if at < pending.RetryAt then
			continue
		end
		attempted += 1
		pending.RetryAt = at + 1
		local sourceCart = pending.SourceCart
		if sourceCart and not sourceCart:IsDescendantOf(Workspace) then
			sourceCart = nil
		end
		local token, reason =
			DevelopmentBrainrotSpawner.PrepareFreshRelease(pending.Record, pending.Pose, nil, nil, sourceCart)
		if token then
			local model, commitReason = DevelopmentBrainrotSpawner.CommitFreshRelease(token, function()
				return pendingFreshReleases[itemId] == pending
			end)
			if not model then
				DevelopmentBrainrotSpawner.DiscardFreshRelease(token)
				reason = commitReason
			end
		end
		pending.LastError = reason
	end
	return attempted
end

local function getSpawnCFrame(selectedPositions: { Vector3 }): CFrame
	local origin = TEST_SPAWN_CFRAME.Position
	local rotation = TEST_SPAWN_CFRAME - TEST_SPAWN_CFRAME.Position
	local selectedPosition = origin
	for _ = 1, SPAWN_POSITION_ATTEMPTS do
		local candidate = origin
			+ Vector3.new(
				random:NextNumber(-TEST_SPAWN_RADIUS, TEST_SPAWN_RADIUS),
				0,
				random:NextNumber(-TEST_SPAWN_RADIUS, TEST_SPAWN_RADIUS)
			)
		local separated = true
		for _, position in selectedPositions do
			local delta = Vector3.new(candidate.X - position.X, 0, candidate.Z - position.Z)
			if delta.Magnitude < MIN_SPAWN_SEPARATION then
				separated = false
				break
			end
		end
		if separated then
			selectedPosition = candidate
			break
		end
	end
	table.insert(selectedPositions, selectedPosition)
	return CFrame.new(selectedPosition) * rotation
end

function DevelopmentBrainrotSpawner.GetPilotSpecies(): { string }
	return table.clone(PILOT_SPECIES)
end

function DevelopmentBrainrotSpawner.CreateWorldRecord(
	speciesId: string,
	worldName: string,
	pose: CFrame,
	naturalRegionId: string?,
	options: any?
): (WorldRecord?, string?)
	if type(worldName) ~= "string" or worldName == "" or not validPose(pose) then
		return nil, "INVALID_WORLD_REQUEST"
	end
	local definition = BrainrotCatalog.Get(speciesId)
	if definition == nil then
		return nil, "UNKNOWN_SPECIES"
	end
	local source = getTemplate(definition.id)
	if source == nil then
		return nil, "INVALID_ASSET"
	end
	local position = pose.Position
	local mutationId = if options then options.MutationId else nil
	if mutationId == nil then
		local reason
		if Phase12.Enabled then mutationId,reason=Phase12Rules.RollMutation(random, stormMutationChance()) else mutationId="None" end
		if mutationId == nil then return nil, reason or "MUTATION_UNAVAILABLE" end
	end
	local metadata = table.clone(readMetadata(source, { Tier = definition.tier }))
	metadata.MutationId = mutationId
	if options and options.BurrowId then metadata.Phase12BurrowId = options.BurrowId end
	local record = table.freeze({
		ItemId = if options and options.ItemId then options.ItemId else HttpService:GenerateGUID(false),
		BrainrotId = definition.id,
		Metadata = copyData(metadata),
		World = table.freeze({
			Name = worldName,
			Scale = source:GetScale(),
			SpawnPosition = table.freeze({ X = position.X, Y = position.Y, Z = position.Z }),
			RouteJourney = if options and options.Journey then copyData(options.Journey)else nil,
		}),
	})
	if naturalRegionId ~= nil then
		return NaturalTerritory.BindNaturalSpawn(record, naturalRegionId)
	end
	return record, nil
end

local function buildAvailabilitySnapshot(state: PopulationState): any
	local blockedSpecies = {}
	for _, definition in BrainrotCatalog.GetAll() do
		local cap = state.Config.ProfileAdmissionCaps[definition.behaviourId]
		local effective = (state.WildByBehaviour[definition.behaviourId] or 0)
			+ (state.ReservedByBehaviour[definition.behaviourId] or 0)
		if cap == nil or effective >= cap then
			blockedSpecies[definition.id] = "PROFILE_POPULATION_CAP_REACHED"
		end
	end
	return table.freeze({
		blockedSpecies = table.freeze(blockedSpecies),
		blockedTiers = table.freeze({}),
	})
end

-- The workbook approves regional content pools but no per-region population
-- quotas. Choose uniformly from currently untried configured hunting regions;
-- this lets every ready region participate without forcing 42 into seven sixes.
local function chooseConfiguredTargetRegion(
	_state: PopulationState,
	regionsTried: { [string]: boolean }
): (string?, string?, boolean?)
	local candidates = {}
	for _, region in Regions.GetAll() do
		if
			region.kind == "Hunting"
			and region.enabled
			and region.naturalSpawnAllowed
			and not regionsTried[region.id]
		then
			local compilation = SpawnSelection.CompileConfiguredRegion(region.id)
			if compilation.pool ~= nil then
				table.insert(candidates, region.id)
			end
		end
	end
	if #candidates == 0 then
		return nil, "REGION_CONFIGURATION_NOT_READY", true
	end
	return candidates[random:NextInteger(1, #candidates)], nil, false
end

local function defaultSelectSpecies(regionId: string, availability: any): any
	return SpawnSelection.SelectConfiguredRegion(regionId, availability, nil)
end

local function naturalCandidatePosition(area: any, sourceRandom: any): Vector3?
	if type(area) ~= "table" or not area.Enabled or typeof(area.Part) ~= "Instance" then
		return nil
	end
	local part = area.Part
	if not part:IsA("BasePart") then
		return nil
	end
	if area.Kind == "Point" then
		return part.Position
	elseif area.Kind == "Volume" then
		return part.CFrame:PointToWorldSpace(
			Vector3.new(
				sourceRandom:NextNumber(-0.4, 0.4) * part.Size.X,
				if area.IsFloorSurface then part.Size.Y * 0.5 else -part.Size.Y * 0.5,
				sourceRandom:NextNumber(-0.4, 0.4) * part.Size.Z
			)
		)
	end
	return nil
end

local function shuffleAreas(areas: { any }, sourceRandom: any): { any }
	local shuffled = table.clone(areas)
	for index = #shuffled, 2, -1 do
		local selected = sourceRandom:NextInteger(1, index)
		shuffled[index], shuffled[selected] = shuffled[selected], shuffled[index]
	end
	return shuffled
end

local function findNaturalPlacement(
	speciesId: string,
	regionId: string,
	areas: { any },
	sourceRandom: any,
	validate: ((string, string, string, Vector3) -> any)?
): (CFrame?, number, string?)
	local pointAreas, volumeAreas = {}, {}
	for _, area in areas do
		if type(area) == "table" and area.Enabled == true and area.UsableProbeCount ~= 0 then
			if area.Kind == "Point" then
				table.insert(pointAreas, area)
			elseif area.Kind == "Volume" then
				table.insert(volumeAreas, area)
			end
		end
	end
	if #pointAreas == 0 and #volumeAreas == 0 then
		return nil, 0, "NO_SPAWN_AREAS"
	end
	pointAreas = shuffleAreas(pointAreas, sourceRandom)
	volumeAreas = shuffleAreas(volumeAreas, sourceRandom)
	local attempts = 0
	local lastReason: string? = nil
	local validator = validate or RegionSpawnCatalog.ValidatePlacement
	for _, area in pointAreas do
		if attempts >= BrainrotTerritory.MaxPlacementAttemptsPerSpawn then
			break
		end
		local candidate = naturalCandidatePosition(area, sourceRandom)
		if candidate then
			attempts += 1
			local result = validator(speciesId, regionId, area.Id, candidate)
			if result.valid and typeof(result.placementPivot) == "CFrame" then
				return result.placementPivot, attempts, nil
			end
			lastReason = if type(result.reasons) == "table" then result.reasons[1] else "PLACEMENT_UNAVAILABLE"
		end
	end
	local volumeIndex = 1
	while attempts < BrainrotTerritory.MaxPlacementAttemptsPerSpawn and #volumeAreas > 0 do
		local area = volumeAreas[volumeIndex]
		volumeIndex = volumeIndex % #volumeAreas + 1
		local candidate = naturalCandidatePosition(area, sourceRandom)
		if candidate then
			attempts += 1
			local result = validator(speciesId, regionId, area.Id, candidate)
			if result.valid and typeof(result.placementPivot) == "CFrame" then
				return result.placementPivot, attempts, nil
			end
			lastReason = if type(result.reasons) == "table" then result.reasons[1] else "PLACEMENT_UNAVAILABLE"
		end
	end
	return nil,
		attempts,
		if attempts >= BrainrotTerritory.MaxPlacementAttemptsPerSpawn
			then "ATTEMPT_BUDGET_EXHAUSTED"
			else lastReason or "PLACEMENT_UNAVAILABLE"
end

local function performNaturalSpawn(
	reservation: SpawnReservation,
	_commit: (string) -> (boolean, string?)
): (boolean, string?)
	local constructionAt = os.clock()
	if Phase12.Enabled and constructionAt - lastNaturalConstructionAt < Phase12.SpawnConstructionInterval then
		return false, "CONSTRUCTION_STAGED"
	end
	if not RegionSpawnCatalog.IsSpeciesAllowedInRegion(reservation.SpeciesId, reservation.RegionId) then
		return false, "SPECIES_NOT_ALLOWED"
	end
	local readiness = RegionSpawnCatalog.EvaluateNaturalSpawnReadiness(reservation.SpeciesId, reservation.RegionId)
	if not readiness.ready then
		local reason = readiness.reasons[1] or "MODEL_NOT_READY"
		return false, if reason == "MODEL_MISSING" then "MODEL_NOT_READY" else reason
	end
	local pose, burrowId, placementReason,journey = Phase12Burrows.FindDestination(reservation.SpeciesId, reservation.RegionId, random,reservationJourneys[reservation.ReservationId])
	if journey then reservationJourneys[reservation.ReservationId]=journey end
	if pose == nil then
		return false, placementReason or "PLACEMENT_UNAVAILABLE"
	end
	local ahead = findPlayerFacingPlacement(reservation.SpeciesId, reservation.RegionId)
	if ahead then
		pose = ahead
		huntFlowStats.Ahead += 1
	else
		huntFlowStats.Mouth += 1
	end
	local worldName = string.format("%s_Natural_%s", reservation.SpeciesId, string.sub(reservation.ReservationId, 1, 8))
	local record, recordReason = DevelopmentBrainrotSpawner.CreateWorldRecord(
		reservation.SpeciesId, worldName, pose, reservation.RegionId,
		{ MutationId = reservation.MutationId, ItemId = reservation.ReservationId, BurrowId = burrowId,Journey=journey }
	)
	if record == nil then
		return false, recordReason or "MODEL_CONSTRUCTION_FAILED"
	end
	lastNaturalConstructionAt = constructionAt
	local prepared, prepareReason = DevelopmentBrainrotSpawner.PrepareWorldRepresentation(record, pose)
	if prepared == nil then
		return false, prepareReason or "MODEL_CONSTRUCTION_FAILED"
	end
	local emergenceSeconds=if Phase12.Enabled then Phase12.EmergenceSeconds else 0
	local readyAt = Workspace:GetServerTimeNow() + emergenceSeconds
	prepared.Model:SetAttribute("Phase12InteractionReady", not Phase12.Enabled)
	prepared.Model:SetAttribute("Phase12EmergenceReadyAt", readyAt)
	prepared.Model:SetAttribute("Phase12BurrowId", burrowId)
	local model, activationReason =
		DevelopmentBrainrotSpawner.ActivatePreparedWorld(prepared, nil, reservation.ReservationId)
	if model == nil then
		DevelopmentBrainrotSpawner.DiscardPreparedWorld(prepared)
		return false, activationReason or "ACTIVATION_FAILED"
	end
	task.delay(emergenceSeconds, function()
		-- Retired-cycle jobs cannot announce or reactivate a wiped individual.
		-- A genuine counted Camp survivor can still finish its existing emergence.
		if modelsById[record.ItemId] ~= model
			or not DevelopmentBrainrotSpawner.HasOrdinaryReservation(record.ItemId) then return end
		model:SetAttribute("Phase12InteractionReady", true)
		naturalSpawnCommitted:Fire(record, model, reservation.RegionId, model:GetAttribute("Phase12BurrowId"))
		worldChanged:Fire(model)
	end)
	return true, nil
end

-- Core Loop V2 (A1): one directed spawn ordered by HuntDirector for a specific hunter. Uses the same
-- reservation, mutation-per-reservation, record, preparation and activation path as a natural spawn;
-- placement was validated by the director through RegionSpawnCatalog.ValidatePlacement. No burrow,
-- no route journey: the individual pops out of the ground where it was placed (F1) and calm-roams there.
export type DirectedOrder = {
	RegionId: string,
	SpeciesId: string,
	MutationId: string,
	Pose: CFrame,
	Attributes: { [string]: any }?,
	ReadySeconds: number?,
}
local directedStats = { Spawned = 0, Failed = 0, LastFailure = "" }
local directedAccessOverride = false -- QA only (Studio): virtual hunters in locked regions
function DevelopmentBrainrotSpawner._SetDirectedAccessOverrideForQA(value: boolean)
	assert(RunService:IsStudio(), "QA only")
	directedAccessOverride = value
end
function DevelopmentBrainrotSpawner.SpawnDirected(order: DirectedOrder): (Model?, any?, string?)
	if not directedSpawning then
		return nil, nil, "DIRECTOR_DISABLED"
	end
	local function fail(reason: string): (Model?, any?, string?)
		directedStats.Failed += 1
		directedStats.LastFailure = reason
		return nil, nil, reason
	end
	if type(order) ~= "table" or not validPose(order.Pose) then
		return fail("INVALID_ORDER")
	end
	if
		productionPopulation.WildCount + productionPopulation.ReservedCount
		>= CoreLoop.Population.HardCap
	then
		return fail("SERVER_HARD_CAP")
	end
	if not RegionSpawnCatalog.IsSpeciesAllowedInRegion(order.SpeciesId, order.RegionId) then
		return fail("SPECIES_NOT_ALLOWED")
	end
	local readiness =
		RegionSpawnCatalog.EvaluateNaturalSpawnReadiness(order.SpeciesId, order.RegionId)
	if not readiness.ready then
		return fail(readiness.reasons[1] or "MODEL_NOT_READY")
	end
	-- Access: someone on the server must have this region unlocked (the policy's eligibility rule).
	if
		accessPolicyRef
		and not directedAccessOverride
		and not accessPolicyRef:IsEligibleNow(order.RegionId)
	then
		return fail("REGION_NOT_ELIGIBLE")
	end
	local reservation, reserveReason = reserveSpawn(
		productionPopulation,
		order.RegionId,
		order.SpeciesId,
		order.MutationId or "None",
		true
	)
	if reservation == nil then
		return fail(reserveReason or "ADMISSION_DENIED")
	end
	local function release(reason: string): (Model?, any?, string?)
		removeReservation(productionPopulation, reservation.ReservationId, reason)
		return fail(reason)
	end
	local worldName = string.format(
		"%s_Herd_%s",
		reservation.SpeciesId,
		string.sub(reservation.ReservationId, 1, 8)
	)
	local record, recordReason = DevelopmentBrainrotSpawner.CreateWorldRecord(
		reservation.SpeciesId,
		worldName,
		order.Pose,
		reservation.RegionId,
		{ MutationId = reservation.MutationId, ItemId = reservation.ReservationId }
	)
	if record == nil then
		return release(recordReason or "MODEL_CONSTRUCTION_FAILED")
	end
	local prepared, prepareReason =
		DevelopmentBrainrotSpawner.PrepareWorldRepresentation(record, order.Pose)
	if prepared == nil then
		return release(prepareReason or "MODEL_CONSTRUCTION_FAILED")
	end
	local readySeconds = order.ReadySeconds or CoreLoop.Fx.PopSeconds
	prepared.Model:SetAttribute("Phase12InteractionReady", not Phase12.Enabled)
	prepared.Model:SetAttribute(
		"Phase12EmergenceReadyAt",
		Workspace:GetServerTimeNow() + readySeconds
	)
	for name, value in order.Attributes or {} do
		prepared.Model:SetAttribute(name, value)
	end
	if order.Attributes and order.Attributes.CoreLoopMutationHidden then
		-- K2: re-publish identity now that the hidden flag is set (masks the mutation id).
		BrainrotDisplayMetadata.SetIdentity(prepared.Model, record)
	end
	local model, activationReason =
		DevelopmentBrainrotSpawner.ActivatePreparedWorld(prepared, nil, reservation.ReservationId)
	if model == nil then
		DevelopmentBrainrotSpawner.DiscardPreparedWorld(prepared)
		if productionPopulation.Reservations[reservation.ReservationId] then
			return release(activationReason or "ACTIVATION_FAILED")
		end
		return fail(activationReason or "ACTIVATION_FAILED")
	end
	directedStats.Spawned += 1
	task.delay(readySeconds, function()
		if
			modelsById[record.ItemId] ~= model
			or not DevelopmentBrainrotSpawner.HasOrdinaryReservation(record.ItemId)
		then
			return
		end
		model:SetAttribute("Phase12InteractionReady", true)
		-- K2: the spawn announcement never carries a hidden mutation (no rank, no global banner).
		local announced = record
		if model:GetAttribute("CoreLoopMutationHidden") == true then
			local metadata = table.clone(record.Metadata)
			metadata.MutationId = "None"
			announced = table.clone(record)
			announced.Metadata = table.freeze(metadata)
		end
		naturalSpawnCommitted:Fire(announced, model, reservation.RegionId, nil)
		worldChanged:Fire(model)
	end)
	return model, record, nil
end

function DevelopmentBrainrotSpawner.IsDirected(): boolean
	return directedSpawning
end

function DevelopmentBrainrotSpawner.GetDirectedStats(): any
	return table.clone(directedStats)
end

-- Cheap population read for the director (no member sort).
function DevelopmentBrainrotSpawner.GetPopulationCounts(): (number, number, { [string]: number })
	return productionPopulation.WildCount,
		productionPopulation.ReservedCount,
		productionPopulation.WildByRegion
end

-- Core Loop V2 (A7 Saved): add seconds to a current sleep. Returns the new wake time.
function DevelopmentBrainrotSpawner.ExtendSleep(model: Model, seconds: number): number?
	local registration = registrations[model]
	if not registration or not registration.Sleeping or registration.SleepUntil == nil then
		return nil
	end
	registration.SleepUntil += seconds
	model:SetAttribute("BrainrotSleepUntil", registration.SleepUntil)
	return registration.SleepUntil
end

-- Server clock used for sleep deadlines (os.clock-based in production; tests can pin it).
function DevelopmentBrainrotSpawner.SleepClock(): number
	return sleepClock()
end

-- Directed retirement helpers (DespawnPolicy facts).
function DevelopmentBrainrotSpawner.IsSleepingModel(model: Model): boolean
	local registration = registrations[model]
	return registration ~= nil and registration.Sleeping == true
end

local requestPopulationReconcileForState: (PopulationState, string, number?) -> (boolean, string?)

local function runPopulationReconcile(state: PopulationState): any
	if not state.Running then
		return table.freeze({ status = "STOPPED", spawned = 0 })
	end
	state.ReconcileScheduled = false
	if state.Config.NaturalReplenishmentEnabled ~= true then
		return table.freeze({ status = "DISABLED", spawned = 0 })
	end
	if directedSpawning and state == productionPopulation then
		-- Core Loop V2 (A1): no ambient replenishment, no burrow emergence; HuntDirector orders every spawn.
		return table.freeze({ status = "DIRECTED", spawned = 0 })
	end
	local retriedSpawns = 0
	local retryDelay = state.Config.RetryDelaySeconds
	if Phase10.Enabled then
		local attempted = 0
		for _, reservation in table.clone(state.Reservations) do
			if attempted >= state.Config.MaxSpawnReservationsPerPass then
				break
			end
			attempted += 1
			local spawn = state.Dependencies.SpawnReservation or performNaturalSpawn
			local success, failure = spawn(reservation, function(runtimeId)
				return commitReservation(state, reservation.ReservationId, runtimeId, nil)
			end)
			if success and state.Reservations[reservation.ReservationId] == nil then
				retriedSpawns += 1
			end
			if not success then admissionDenied(state,failure)end
			if failure == "CONSTRUCTION_STAGED" then retryDelay = Phase12.SpawnConstructionInterval break end
		end
	end
	local effectiveCount = state.WildCount + state.ReservedCount
	local deficit = state.Config.TargetWildPopulation - effectiveCount
	emitPopulationChanged(state, "Reconcile", {
		Wild = state.WildCount,
		Reserved = state.ReservedCount,
		Target = state.Config.TargetWildPopulation,
		Deficit = deficit,
	})
	if deficit <= 0 then
		admissionDenied(state,"SERVER_POPULATION_TARGET_REACHED")
		if state.ReservedCount > 0 then requestPopulationReconcileForState(state, "PendingSpawnRetry", retryDelay) end
		return table.freeze({ status = "AT_OR_ABOVE_TARGET", spawned = retriedSpawns })
	end

	local attemptBudget = math.min(deficit, state.Config.MaxSpawnReservationsPerPass)
	local regionsTried: { [string]: boolean } = {}
	local regionTryLimit = math.max(1, #Regions.GetAll())
	local reservationsStarted = 0
	local spawned = 0
	local regionTries = 0
	local transientFailure = false
	local staticFailure = false
	local lastReason: string? = nil

	while reservationsStarted < attemptBudget and regionTries < regionTryLimit do
		local chooseRegion = state.Dependencies.ChooseRegion
		local regionId, regionReason, regionStatic
		if chooseRegion then
			regionId, regionReason, regionStatic = chooseRegion(populationSnapshot(state), regionsTried)
		else
			regionId, regionReason, regionStatic = chooseConfiguredTargetRegion(state, regionsTried)
		end
		if regionId == nil then
			lastReason = regionReason or "REGION_POLICY_MISSING"
			admissionDenied(state,lastReason)
			staticFailure = staticFailure or regionStatic == true
			transientFailure = transientFailure or regionStatic ~= true
			break
		end
		local normalizedRegion = Regions.NormalizeId(regionId)
		if normalizedRegion == nil or regionsTried[normalizedRegion] then
			lastReason = if normalizedRegion == nil then "REGION_NOT_SPAWNABLE" else "REGION_POLICY_REPEATED_REGION"
			staticFailure = true
			break
		end
		regionsTried[normalizedRegion] = true
		regionTries += 1

		local regionCap = regionAdmissionLimit(state, normalizedRegion)
		if
			regionCap ~= nil
			and (state.WildByRegion[normalizedRegion] or 0) + (state.ReservedByRegion[normalizedRegion] or 0)
				>= regionCap
		then
			lastReason = "REGION_POPULATION_CAP_REACHED"
			admissionDenied(state,lastReason)
			transientFailure = true
			continue
		end

		local selectSpecies = state.Dependencies.SelectSpecies or defaultSelectSpecies
		local availability=buildAvailabilitySnapshot(state)
		local selection = if state == productionPopulation
			then waveSelect(selectSpecies, normalizedRegion, availability)
			else selectSpecies(normalizedRegion, availability)
		if type(selection) ~= "table" then
			lastReason = "INVALID_CONFIGURATION"
			staticFailure = true
			continue
		elseif selection.status == "NO_ELIGIBLE_SPECIES_NOW" then
			lastReason = selection.status
			-- Production policy wraps the selector. Its only temporary exclusions
			-- are the current quota/access gate and this exact profile-cap map.
			local currentRegion=if state.Dependencies.GetRegion then state.Dependencies.GetRegion(normalizedRegion)else nil
			local deniedReason=if currentRegion and currentRegion.naturalSpawnAllowed==false then "REGION_QUOTA_REACHED"
				elseif next(availability.blockedSpecies)~=nil then "PROFILE_POPULATION_CAP_REACHED"else lastReason
			admissionDenied(state,deniedReason)
			transientFailure = true
			continue
		elseif selection.status ~= "Selected" then
			lastReason = selection.status or "INVALID_CONFIGURATION"
			admissionDenied(state,lastReason)
			staticFailure = true
			continue
		end

		local reservation, reserveReason = reserveSpawn(state, normalizedRegion, selection.speciesId)
		if reservation == nil then
			lastReason = reserveReason or "ADMISSION_CHANGED"
			transientFailure = lastReason == "PROFILE_POPULATION_CAP_REACHED"
				or lastReason == "REGION_POPULATION_CAP_REACHED"
				or lastReason == "SERVER_POPULATION_TARGET_REACHED"
			if lastReason == "SERVER_POPULATION_TARGET_REACHED" then
				break
			end
			continue
		end
		reservationsStarted += 1

		local spawnReservation = state.Dependencies.SpawnReservation or performNaturalSpawn
		local success, failureReason = spawnReservation(reservation, function(runtimeId)
			return commitReservation(state, reservation.ReservationId, runtimeId, nil)
		end)
		if not success or state.Reservations[reservation.ReservationId] ~= nil then
			if failureReason == "CONSTRUCTION_STAGED" then retryDelay = Phase12.SpawnConstructionInterval end
			if state.Reservations[reservation.ReservationId] ~= nil and not Phase10.Enabled then
				removeReservation(state, reservation.ReservationId, failureReason or "SPAWN_NOT_COMMITTED")
			end
			lastReason = failureReason or "SPAWN_NOT_COMMITTED"
			admissionDenied(state,lastReason)
			transientFailure = true
			emitPopulationChanged(state, "SpawnFailed", {
				Reservation = reservation,
				Reason = lastReason,
			})
			break -- One weighted outcome failed; never substitute another species.
		end
		spawned += 1
	end

	local remaining = state.Config.TargetWildPopulation - (state.WildCount + state.ReservedCount)
	if Phase10.Enabled and state.ReservedCount > 0 then
		requestPopulationReconcileForState(state, "PendingSpawnRetry", retryDelay)
	end
	if remaining > 0 then
		if spawned > 0 then
			requestPopulationReconcileForState(state, "DeficitRemains", state.Config.ReplenishDelaySeconds)
		elseif transientFailure and not staticFailure then
			requestPopulationReconcileForState(state, "TransientSpawnFailure", state.Config.RetryDelaySeconds)
		end
	end
	return table.freeze({
		status = if spawned > 0
			then "SPAWNED"
			elseif staticFailure then "STATICALLY_BLOCKED"
			elseif transientFailure then "TEMPORARILY_BLOCKED"
			else "NO_WORK",
		spawned = spawned,
		reason = lastReason,
	})
end

requestPopulationReconcileForState = function(
	state: PopulationState,
	_reason: string,
	delaySeconds: number?
): (boolean, string?)
	if not state.Running then
		return false, "STOPPED"
	end
	if state.Config.NaturalReplenishmentEnabled ~= true then
		return false, "DISABLED"
	end
	if state.ReconcileScheduled then
		return false, "ALREADY_SCHEDULED"
	end
	local schedule = state.Dependencies.Schedule
	if schedule == nil then
		return false, "SCHEDULER_UNAVAILABLE"
	end
	state.ReconcileScheduled = true
	local scheduledGeneration = state.Generation
	schedule(delaySeconds or state.Config.ReplenishDelaySeconds, function()
		if not state.Running or scheduledGeneration ~= state.Generation then
			return
		end
		state.ReconcileScheduled = false
		runPopulationReconcile(state)
	end)
	return true, nil
end

local function startPopulation(state: PopulationState): (boolean, string?)
	if state.Running then
		return false, "ALREADY_RUNNING"
	end
	if state.Config.NaturalReplenishmentEnabled ~= true then
		return false, "DISABLED"
	end
	if state.Dependencies.CheckReadiness then
		local ready, reason = state.Dependencies.CheckReadiness()
		if not ready then
			return false, reason or "CONTENT_NOT_READY"
		end
	end
	state.Running = true
	state.Generation += 1
	return requestPopulationReconcileForState(state, "Startup", state.Config.ReplenishDelaySeconds)
end

local function stopPopulation(state: PopulationState): boolean
	local changed = state.Running or state.ReconcileScheduled or state.ReservedCount > 0
	state.Running = false
	state.Generation += 1
	state.ReconcileScheduled = false
	local reservationIds = {}
	for reservationId in state.Reservations do
		table.insert(reservationIds, reservationId)
	end
	for _, reservationId in reservationIds do
		removeReservation(state, reservationId, "Teardown")
	end
	return changed
end

productionPopulationDependencies.ChooseRegion = function(_snapshot, regionsTried)
	return chooseConfiguredTargetRegion(productionPopulation, regionsTried)
end
productionPopulationDependencies.SelectSpecies = defaultSelectSpecies
productionPopulationDependencies.SpawnReservation = performNaturalSpawn
productionPopulationDependencies.CheckReadiness = function()
	local readiness = SpawnSelection.EvaluateConfiguredWorldReadiness()
	return readiness.ready,
		if readiness.ready
			then nil
			else string.format(
				"CONTENT_NOT_READY:%d/%d_REGIONS_READY",
				readiness.readyRegionCount,
				readiness.huntingRegionCount
			)
end
requestProductionReconcile = function(reason, delaySeconds)
	return requestPopulationReconcileForState(productionPopulation, reason, delaySeconds)
end

local originalPopulationDependencies = table.clone(productionPopulationDependencies)
local accessPopulationConfigured = false

-- Installed before Start; preserves this registry, cap policy and reservation identities.
function DevelopmentBrainrotSpawner.ConfigurePopulationAccess(policy: any): (boolean, string?)
	if productionPopulation.Running or productionPopulation.ReservedCount > 0 then
		return false, "POPULATION_ALREADY_RUNNING"
	end
	if policy == nil then
		accessPopulationConfigured = false
		for key, value in originalPopulationDependencies do
			productionPopulationDependencies[key] = value
		end
		return true, nil
	end
	if
		type(policy) ~= "table"
		or type(policy.ChooseRegion) ~= "function"
		or type(policy.SelectSpecies) ~= "function"
		or type(policy.CheckReadiness) ~= "function"
		or type(policy.GetQuota) ~= "function"
	then
		return false, "INVALID_ACCESS_POLICY"
	end
	accessPopulationConfigured = true
	accessPolicyRef = policy
	productionPopulationDependencies.ChooseRegion = function(snapshot, tried)
		return policy:ChooseRegion(snapshot, tried)
	end
	productionPopulationDependencies.SelectSpecies = function(regionId, availability)
		return policy:SelectSpecies(regionId, availability)
	end
	productionPopulationDependencies.CheckReadiness = function()
		return policy:CheckReadiness()
	end
	productionPopulationDependencies.SpawnReservation = function(reservation, commit)
		if policy:GetQuota(reservation.RegionId) <= 0 then
			return false, "REGION_ACCESS_CHANGED"
		end
		return performNaturalSpawn(reservation, commit)
	end
	productionPopulationDependencies.GetRegion = function(regionId)
		local region = Regions.Get(regionId)
		if not region then
			return nil
		end
		local permitted = table.clone(region)
		local quota = policy:GetQuota(regionId)
		permitted.naturalSpawnAllowed = region.naturalSpawnAllowed and quota > 0
		permitted.populationCap = quota
		return permitted
	end
	return true, nil
end

function DevelopmentBrainrotSpawner.RequestPopulationReconcile(
	reason: string,
	delaySeconds: number?
): (boolean, string?)
	return requestPopulationReconcileForState(productionPopulation, reason, delaySeconds)
end

function DevelopmentBrainrotSpawner.RunPopulationReconcile(): any
	return runPopulationReconcile(productionPopulation)
end

function DevelopmentBrainrotSpawner.Stop(): boolean
	local changed = stopPopulation(productionPopulation)
	for token in table.clone(freshReleaseTokens) do
		DevelopmentBrainrotSpawner.DiscardFreshRelease(token)
	end
	table.clear(pendingFreshReleases)
	if sleepHeartbeatConnection then
		sleepHeartbeatConnection:Disconnect()
		sleepHeartbeatConnection = nil
		changed = true
	end
	return changed
end

-- Deterministic unit boundary. It uses the exact production ledger, admission,
-- reservation and scheduler functions without mutating the live world registry.
function DevelopmentBrainrotSpawner._TestCreatePopulationHarness(config: any, dependencies: any)
	local state = createPopulationState(config, dependencies)
	local harness = {}
	local harnessPendingBanks={}
	function harness:Register(runtimeId, speciesId, regionId)
		return registerWild(state, runtimeId, speciesId, regionId)
	end
	function harness:Transition(runtimeId, location)
		return setMemberState(state, runtimeId, location)
	end
	function harness:BeginPendingBank(runtimeId,revision)
		local member=state.Members[runtimeId]
		if not member then return false,"NOT_ORDINARY"end
		local ok,reason=BankBarrier.Begin(harnessPendingBanks,state.Members,{ItemId=runtimeId,BrainrotId=member.SpeciesId},"Bank:"..runtimeId,revision)
		if ok then setMemberState(state,runtimeId,"PendingBank")end
		return ok,reason
	end
	function harness:ConfirmPendingBank(runtimeId)
		local ok,reason=BankBarrier.Confirm(harnessPendingBanks,state.Members,runtimeId,"Bank:"..runtimeId,function(id)return firstBank(state,id)end)
		if ok and reason~="ALREADY_CONFIRMED"then requestPopulationReconcileForState(state,"FirstBankConfirmed",nil)end
		return ok,reason
	end
	function harness:FirstBank(runtimeId)
		local released, reason = firstBank(state, runtimeId)
		if released then
			requestPopulationReconcileForState(state, "FirstBank", nil)
		end
		return released, reason
	end
	function harness:Unregister(runtimeId, reason)
		if Phase10.Enabled and reason ~= "TestCleanup" and reason ~= "Teardown" then
			return setMemberState(state, runtimeId, if reason == "PickedUp" then "Carried" else "PendingWorld"), nil
		end
		local removed, removeReason = unregisterWild(state, runtimeId, reason)
		if removed then
			requestPopulationReconcileForState(state, reason or "Removed", nil)
		end
		return removed, removeReason
	end
	function harness:Retire(runtimeId,reason)
		-- Same ledger primitive used by RetireFreshIndividual after its world
		-- owner validates the reset/departure lifecycle. No profile ownership.
		local removed,failure=unregisterWild(state,runtimeId,reason or "Phase12Reset")
		if removed then requestPopulationReconcileForState(state,reason or "Phase12Reset",state.Config.ReplenishDelaySeconds)end
		return removed,failure
	end
	function harness:Reserve(regionId, speciesId)
		return reserveSpawn(state, regionId, speciesId)
	end
	function harness:Commit(reservationId, runtimeId)
		return commitReservation(state, reservationId, runtimeId, nil)
	end
	function harness:Release(reservationId, reason)
		local reservation, releaseReason = removeReservation(state, reservationId, reason)
		return reservation ~= nil, releaseReason
	end
	function harness:Availability()
		return buildAvailabilitySnapshot(state)
	end
	function harness:Snapshot()
		return populationSnapshot(state)
	end
	function harness:Validate()
		return validatePopulationConsistency(state)
	end
	function harness:Start()
		return startPopulation(state)
	end
	function harness:Stop()
		return stopPopulation(state)
	end
	function harness:Request(reason, delaySeconds)
		return requestPopulationReconcileForState(state, reason, delaySeconds)
	end
	function harness:Run()
		return runPopulationReconcile(state)
	end
	return harness
end

function DevelopmentBrainrotSpawner._TestFindNaturalPlacement(
	speciesId: string,
	regionId: string,
	areas: { any },
	sourceRandom: any,
	validate: (string, string, string, Vector3) -> any
): (CFrame?, number, string?)
	return findNaturalPlacement(speciesId, regionId, areas, sourceRandom, validate)
end

function DevelopmentBrainrotSpawner.Start()
	if sleepHeartbeatConnection == nil then
		sleepHeartbeatConnection = RunService.Heartbeat:Connect(function()
			DevelopmentBrainrotSpawner.ProcessSleepExpirations()
			if productionPopulation.Running then
				local swept, failure = pcall(sweepStranded)
				if not swept then
					log:Warn("Stranded sweep failed: %s", tostring(failure))
				end
			end
			if Phase10.Enabled then
				DevelopmentBrainrotSpawner.ProcessPendingFreshReleases()
			end
		end)
	end
	local brainrots = ensureBrainrotFolder()
	local selectedPositions: { Vector3 } = {}
	local spawnedBySpecies: { [string]: number } = {}
	-- Fixed Camp pilots are an old development fixture, not part of the access-aware natural pool.
	for index = 1, if accessPopulationConfigured then 0 else TEST_SPAWN_COUNT do
		local speciesId = PILOT_SPECIES[((index - 1) % #PILOT_SPECIES) + 1]
		local name = string.format("%s_Pilot_%02d", speciesId, index)
		local existing = brainrots:FindFirstChild(name)
		if existing then
			registerDevelopmentBrainrot(existing)
			continue
		end
		local pose = getSpawnCFrame(selectedPositions)
		local record, recordReason = DevelopmentBrainrotSpawner.CreateWorldRecord(speciesId, name, pose)
		if record == nil then
			warn(string.format("[DevelopmentBrainrotSpawner] Skipped %s: %s", speciesId, tostring(recordReason)))
			continue
		end
		local prepared, reason = DevelopmentBrainrotSpawner.PrepareWorldRepresentation(record, pose)
		if prepared == nil then
			warn(
				string.format(
					"[DevelopmentBrainrotSpawner] Spawn preparation failed for %s: %s",
					speciesId,
					tostring(reason)
				)
			)
			continue
		end
		-- Development pilots use the same grounded, clearance-checked world
		-- placement as an approved release. A fixed Y=0 visual bottom penetrates
		-- authored floors (top Y=0.05), catching horizontal casts at tile seams.
		local releasePose = DevelopmentBrainrotSpawner.FindSafeReleasePose(prepared, pose, {}, true)
		if releasePose == nil then
			DevelopmentBrainrotSpawner.DiscardPreparedWorld(prepared)
			warn(string.format("[DevelopmentBrainrotSpawner] Pilot placement failed for %s: NO_SAFE_GROUND", speciesId))
			continue
		end
		prepared.Model:PivotTo(releasePose)
		local model, failure = DevelopmentBrainrotSpawner.ActivatePreparedWorld(prepared)
		if model == nil then
			DevelopmentBrainrotSpawner.DiscardPreparedWorld(prepared)
			warn(
				string.format(
					"[DevelopmentBrainrotSpawner] Spawn activation failed for %s: %s",
					speciesId,
					tostring(failure)
				)
			)
		else
			spawnedBySpecies[speciesId] = (spawnedBySpecies[speciesId] or 0) + 1
		end
	end
	if not accessPopulationConfigured then
		print(
			string.format(
				"[DevelopmentBrainrotSpawner] Phase 6A-2 pilot active: %s",
				HttpService:JSONEncode(spawnedBySpecies)
			)
		)
	end
	local _, populationStartReason = startPopulation(productionPopulation)
	if populationStartReason == "DISABLED" then
		log:Info(
			"Wild registry active at %d/%d; natural replenishment remains disabled pending approved regional inputs",
			productionPopulation.WildCount,
			productionPopulation.Config.TargetWildPopulation
		)
	elseif populationStartReason and populationStartReason ~= "ALREADY_RUNNING" then
		log:Warn("Population scheduler did not start: %s", populationStartReason)
		local readiness = SpawnSelection.EvaluateConfiguredWorldReadiness()
		if not readiness.ready then
			log:Warn("Natural-world readiness: %s", table.concat(readiness.reasons, ", "))
		end
	end
end

return DevelopmentBrainrotSpawner
