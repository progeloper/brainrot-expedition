--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DecoySplitTiming = require(ReplicatedStorage.Shared.Behaviours.DecoySplitTiming)
local BrainrotDisplayMetadata = require(ReplicatedStorage.Shared.Utility.BrainrotDisplayMetadata)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local DecoyVisuals = require(script.Parent.Parent.Parent.Utility.DecoyVisuals)
local ReactiveRunner = require(script.Parent.ReactiveRunner)

export type ThreatCandidate = ReactiveRunner.ThreatCandidate

export type Config = {
	AwarenessRadius: number,
	DisengageRadius: number,
	DisengageGraceSeconds: number,
	SenseIntervalSeconds: number,
	MaxDecoysPerEncounter: number,
	MaxActiveEncounters: number,
	ActiveDurationSeconds: number,
	CooldownSeconds: number,
	FailedStartRetrySeconds: number,
	DecoyUpdateIntervalSeconds: number,
	MinimumSpacingStuds: number,
	MaximumSpacingStuds: number,
	SeparationPaddingStuds: number,
	CuePulsePeriodSeconds: number,
	CuePulseDurationSeconds: number,
	TrailLifetimeSeconds: number,
	TrailMaxLengthStuds: number,
	TrailWidthStuds: number,
}

export type DecoyRecord = {
	Id: string,
	EncounterId: string,
	State: State,
	Model: Model,
	HitProxy: BasePart,
	Offset: Vector3,
	HitProxyLocalFrame: CFrame,
	HitProxySize: Vector3,
	Active: boolean,
}

export type State = {
	active: boolean,
	revision: number,
	encounterId: string?,
	startedAt: number?,
	expiresAt: number?,
	nextAllowedAt: number,
	nextFailedStartAt: number,
	nextDecoyUpdateAt: number,
	noThreatSince: number?,
	realLane: number?,
	spacing: number?,
	courseRight: Vector3?,
	owner: Model?,
	runtimeId: string?,
	brainrotId: string?,
	folder: Folder?,
	decoys: { [string]: DecoyRecord },
	capacityReserved: boolean,
}

export type Context = {
	Authorized: boolean,
	LifecycleEligible: boolean,
	RuntimeId: string,
	BrainrotId: string,
	Position: Vector3,
	Forward: Vector3,
	CourseDirection: Vector3?,
	Candidates: { ThreatCandidate },
	Sensing: boolean,
	CanSeeCandidate: (ThreatCandidate) -> boolean,
	GetHitEnvelope: () -> (CFrame?, Vector3?),
	ResolvePlacement: (CFrame, CFrame, Vector3) -> CFrame?,
	ResolveFollowPose: (DecoyRecord, CFrame) -> CFrame?,
	LaneChoice: number?,
	CreateVisual: ((string, string, string, CFrame, Vector3) -> (any?, string?))?,
}

export type Result = {
	Started: boolean?,
	Ended: boolean?,
	Reason: string?,
	EncounterId: string?,
	DecoyCount: number?,
}

local DecoySplit = {}
local log = Logger.new("DecoySplit")
local DIRECTION_EPSILON = 1e-5
local activeEncounterCount = 0
local activeByRuntimeId: { [string]: State } = {}
local activeByDecoyId: { [string]: DecoyRecord } = {}
local activeByProxy: { [Instance]: DecoyRecord } = {}
local staleDecoyObjects: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function countDecoys(state: State): number
	local count = 0
	for _, record in state.decoys do
		if record.Active then
			count += 1
		end
	end
	return count
end

function DecoySplit.GetSnapshot(state: State, runtimeId: string): DecoySplitTiming.Snapshot
	return {
		runtimeId = runtimeId,
		revision = state.revision,
		active = state.active and countDecoys(state) > 0,
		encounterId = state.encounterId,
		startedAt = state.startedAt,
		expiresAt = state.expiresAt,
		decoyCount = if state.active then countDecoys(state) else 0,
	}
end

function DecoySplit.Publish(owner: Model, state: State)
	owner:SetAttribute(
		BrainrotDisplayConfig.Attributes.DecoySplitSnapshot,
		DecoySplitTiming.EncodeSnapshot(DecoySplit.GetSnapshot(state, state.runtimeId or owner.Name))
	)
end

function DecoySplit.CreateState(_now: number, preservedNextAllowedAt: number?): State
	return {
		active = false,
		revision = 0,
		encounterId = nil,
		startedAt = nil,
		expiresAt = nil,
		nextAllowedAt = preservedNextAllowedAt or 0,
		nextFailedStartAt = 0,
		nextDecoyUpdateAt = 0,
		noThreatSince = nil,
		realLane = nil,
		spacing = nil,
		courseRight = nil,
		owner = nil,
		runtimeId = nil,
		brainrotId = nil,
		folder = nil,
		decoys = {},
		capacityReserved = false,
	}
end

local function nearestVisible(
	position: Vector3,
	candidates: { ThreatCandidate },
	radius: number,
	canSeeCandidate: (ThreatCandidate) -> boolean
): ThreatCandidate?
	return ReactiveRunner.SelectThreat(position, candidates, canSeeCandidate, {
		AwarenessRadius = radius,
	})
end

local function horizontal(direction: Vector3): Vector3?
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.X == flat.X and flat.Z == flat.Z and flat.Magnitude > DIRECTION_EPSILON then flat.Unit else nil
end

local function getDecoyRoot(): Folder?
	local runtime = Workspace:FindFirstChild("Runtime")
	if runtime == nil then
		return nil
	end
	local existing = runtime:FindFirstChild("Decoys")
	if existing then
		return if existing:IsA("Folder") then existing else nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decoys"
	folder.Parent = runtime
	return folder
end

local function removeDecoyInternal(record: DecoyRecord, reason: string)
	if not record.Active then
		return false
	end
	record.Active = false
	activeByDecoyId[record.Id] = nil
	activeByProxy[record.HitProxy] = nil
	staleDecoyObjects[record.HitProxy] = true
	staleDecoyObjects[record.Model] = true
	if record.HitProxy.Parent ~= nil then
		record.HitProxy.CanQuery = false
	end
	record.State.decoys[record.Id] = nil
	if record.Model.Parent ~= nil then
		record.Model:Destroy()
	end
	log:Info("[DecoySplit] DecoyRemoved encounterId=%s decoyId=%s reason=%s", record.EncounterId, record.Id, reason)
	return true
end

local function endState(state: State, reason: string, _now: number): boolean
	if not state.active then
		return false
	end
	state.active = false
	state.revision += 1
	local encounterId = state.encounterId
	for _, record in table.clone(state.decoys) do
		removeDecoyInternal(record, reason)
	end
	if state.folder and state.folder.Parent ~= nil then
		state.folder:Destroy()
	end
	if state.runtimeId and activeByRuntimeId[state.runtimeId] == state then
		activeByRuntimeId[state.runtimeId] = nil
	end
	if state.capacityReserved then
		state.capacityReserved = false
		activeEncounterCount = math.max(0, activeEncounterCount - 1)
	end
	state.folder = nil
	state.encounterId = nil
	state.startedAt = nil
	state.expiresAt = nil
	state.noThreatSince = nil
	state.realLane = nil
	state.spacing = nil
	state.courseRight = nil
	state.nextDecoyUpdateAt = 0
	local owner = state.owner
	if owner and owner.Parent ~= nil then
		DecoySplit.Publish(owner, state)
	end
	log:Info(
		"[DecoySplit] Ended realRuntimeId=%s encounterId=%s reason=%s",
		tostring(state.runtimeId),
		tostring(encounterId),
		reason
	)
	return true
end

function DecoySplit.EndEncounter(realRuntimeId: string, reason: string, now: number): boolean
	local state = activeByRuntimeId[realRuntimeId]
	return state ~= nil and endState(state, reason, now)
end

function DecoySplit.RemoveDecoy(decoyId: string, reason: string, now: number): boolean
	local record = activeByDecoyId[decoyId]
	if record == nil or not removeDecoyInternal(record, reason) then
		return false
	end
	local state = record.State
	if countDecoys(state) == 0 then
		endState(state, "NoDecoys", now)
	else
		state.revision += 1
		if state.owner and state.owner.Parent ~= nil then
			DecoySplit.Publish(state.owner, state)
		end
	end
	return true
end

function DecoySplit.ResolveHit(instance: Instance): ("NotDecoy" | "Active" | "Stale", string?)
	local record = activeByProxy[instance]
	if record and record.Active then
		return "Active", record.Id
	end
	if staleDecoyObjects[instance] then
		return "Stale", nil
	end
	local cursor: Instance? = instance
	while cursor and cursor ~= Workspace do
		if cursor:GetAttribute("EffectKind") == "Decoy" then
			local runtime = Workspace:FindFirstChild("Runtime")
			local decoys = if runtime then runtime:FindFirstChild("Decoys") else nil
			if decoys and cursor:IsDescendantOf(decoys) then
				return "Stale", nil
			end
			break
		end
		cursor = cursor.Parent
	end
	return "NotDecoy", nil
end

function DecoySplit.GetActiveTarget(decoyId: any): (Model?, BasePart?)
	if type(decoyId) ~= "string" or decoyId == "" then
		return nil, nil
	end
	local record = activeByDecoyId[decoyId]
	if
		record == nil
		or not record.Active
		or record.Model.Parent == nil
		or record.HitProxy.Parent == nil
		or not record.HitProxy.CanQuery
	then
		return nil, nil
	end
	return record.Model, record.HitProxy
end

function DecoySplit.OnValidatedDecoyHit(hitInstance: Instance, _now: number): (boolean, string?, string?)
	local classification, decoyId = DecoySplit.ResolveHit(hitInstance)
	if classification ~= "Active" or decoyId == nil then
		return false, nil, classification
	end
	local record = activeByDecoyId[decoyId]
	if record == nil or not record.Active then
		return false, decoyId, "Stale"
	end
	local encounterId = record.EncounterId
	log:Info("[DecoySplit] DecoyHit encounterId=%s decoyId=%s", encounterId, decoyId)
	return DecoySplit.RemoveDecoy(decoyId, "Hit", _now), decoyId, encounterId
end

local function failStart(state: State, now: number, config: Config, reason: string): Result
	state.nextFailedStartAt = now + config.FailedStartRetrySeconds
	return { Reason = reason }
end

function DecoySplit.TryStart(realEntity: Model, state: State, context: Context, now: number, config: Config): Result
	if
		state.active
		or not context.Authorized
		or not context.LifecycleEligible
		or not context.Sensing
		or now < state.nextAllowedAt
		or now < state.nextFailedStartAt
	then
		return {}
	end
	if activeEncounterCount >= config.MaxActiveEncounters then
		return failStart(state, now, config, "EffectCap")
	end
	local threat = nearestVisible(context.Position, context.Candidates, config.AwarenessRadius, context.CanSeeCandidate)
	if threat == nil then
		return {}
	end
	local hitFrame, hitSize = context.GetHitEnvelope()
	if hitFrame == nil or hitSize == nil then
		return failStart(state, now, config, "MissingEnvelope")
	end
	local _, visualSize = BrainrotVisualScale.GetVisualBounds(realEntity)
	if visualSize == nil then
		return failStart(state, now, config, "MissingVisualBounds")
	end
	local horizontalDiameter = math.max(hitSize.X, hitSize.Z, visualSize.X, visualSize.Z)
	local spacing = math.max(config.MinimumSpacingStuds, horizontalDiameter + config.SeparationPaddingStuds)
	if spacing > config.MaximumSpacingStuds then
		return failStart(state, now, config, "EnvelopeExceedsSpacing")
	end

	local forward = horizontal(context.CourseDirection or context.Forward)
		or ReactiveRunner.ComputeEscapeDirection(context.Position, threat.Position, context.Forward)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local realLane = context.LaneChoice
	if realLane ~= -1 and realLane ~= 0 and realLane ~= 1 then
		realLane = math.random(-1, 1)
	end
	local realPivot = realEntity:GetPivot()
	local localHitFrame = realPivot:ToObjectSpace(hitFrame)
	local encounterId = HttpService:GenerateGUID(false)
	local root = getDecoyRoot()
	if root == nil then
		return failStart(state, now, config, "MissingRuntime")
	end

	activeEncounterCount += 1
	state.capacityReserved = true
	local prepared = {}
	local createVisual = context.CreateVisual or DecoyVisuals.Create
	for _, lane in { -1, 0, 1 } do
		if lane == realLane or #prepared >= config.MaxDecoysPerEncounter then
			continue
		end
		local offset = right * ((lane - (realLane :: number)) * spacing)
		local desired = CFrame.new(realPivot.Position + offset) * realPivot.Rotation
		local accepted = context.ResolvePlacement(desired, localHitFrame, hitSize)
		if accepted == nil then
			continue
		end
		local index = #prepared + 1
		local decoyId = string.format("D:%s:%d", encounterId, index)
		local visual, visualReason = createVisual(context.BrainrotId, decoyId, encounterId, localHitFrame, hitSize)
		if visual == nil then
			for _, staged in prepared do
				staged.Visual.Model:Destroy()
			end
			state.capacityReserved = false
			activeEncounterCount = math.max(0, activeEncounterCount - 1)
			return failStart(state, now, config, visualReason or "ConstructionFailed")
		end
		visual.Model:PivotTo(accepted)
		table.insert(prepared, { Id = decoyId, Visual = visual, Offset = offset })
	end
	if #prepared == 0 then
		state.capacityReserved = false
		activeEncounterCount = math.max(0, activeEncounterCount - 1)
		return failStart(state, now, config, "NoSafePosition")
	end

	local folder = Instance.new("Folder")
	folder.Name = "Encounter_" .. encounterId
	folder:SetAttribute("EffectKind", "DecoyEncounter")
	folder:SetAttribute("EncounterId", encounterId)
	state.active = true
	state.revision += 1
	state.encounterId = encounterId
	state.startedAt = now
	state.expiresAt = now + config.ActiveDurationSeconds
	state.nextAllowedAt = state.expiresAt + config.CooldownSeconds
	state.nextFailedStartAt = 0
	state.nextDecoyUpdateAt = now + config.DecoyUpdateIntervalSeconds
	state.noThreatSince = nil
	state.realLane = realLane
	state.spacing = spacing
	state.courseRight = right
	state.owner = realEntity
	state.runtimeId = context.RuntimeId
	state.brainrotId = context.BrainrotId
	state.folder = folder
	state.decoys = {}
	activeByRuntimeId[context.RuntimeId] = state
	for _, staged in prepared do
		local visual = staged.Visual
		local record: DecoyRecord = {
			Id = staged.Id,
			EncounterId = encounterId,
			State = state,
			Model = visual.Model,
			HitProxy = visual.HitProxy,
			Offset = staged.Offset,
			HitProxyLocalFrame = localHitFrame,
			HitProxySize = hitSize,
			Active = true,
		}
		state.decoys[record.Id] = record
		activeByDecoyId[record.Id] = record
		activeByProxy[record.HitProxy] = record
		record.Model.Parent = folder
		record.Model:SetAttribute("CreatureVisualKind", "Decoy")
		record.Model:SetAttribute("ItemId", record.Id) -- Presentation identity only; never a population member.
		BrainrotDisplayMetadata.Apply(record.Model, { BrainrotId = context.BrainrotId }, "Awake")
	end
	folder.Parent = root
	DecoySplit.Publish(realEntity, state)
	log:Info(
		"[DecoySplit] Started realRuntimeId=%s encounterId=%s decoyCount=%d expiresAt=%.3f",
		context.RuntimeId,
		encounterId,
		#prepared,
		state.expiresAt
	)
	return {
		Started = true,
		EncounterId = encounterId,
		DecoyCount = #prepared,
	}
end

function DecoySplit.Interrupt(realEntity: Model, state: State, now: number, reason: string): boolean
	state.owner = realEntity
	if state.active then
		return endState(state, reason, now)
	end
	return false
end

function DecoySplit.Step(
	realEntity: Model,
	state: State,
	context: Context,
	now: number,
	_dt: number,
	config: Config
): Result
	state.owner = realEntity
	state.runtimeId = context.RuntimeId
	state.brainrotId = context.BrainrotId
	if not context.Authorized or not context.LifecycleEligible then
		if DecoySplit.Interrupt(realEntity, state, now, "Lifecycle") then
			return { Ended = true, Reason = "Lifecycle" }
		end
		return {}
	end
	if not state.active then
		return DecoySplit.TryStart(realEntity, state, context, now, config)
	end
	if now >= (state.expiresAt :: number) then
		endState(state, "Expired", now)
		return { Ended = true, Reason = "Expired" }
	end
	if context.Sensing then
		local observer =
			nearestVisible(context.Position, context.Candidates, config.DisengageRadius, context.CanSeeCandidate)
		if observer then
			state.noThreatSince = nil
		else
			state.noThreatSince = state.noThreatSince or now
			if now - (state.noThreatSince :: number) >= config.DisengageGraceSeconds then
				endState(state, "Disengaged", now)
				return { Ended = true, Reason = "Disengaged" }
			end
		end
	end
	if now < state.nextDecoyUpdateAt then
		return {}
	end
	state.nextDecoyUpdateAt = now + config.DecoyUpdateIntervalSeconds
	local realPivot = realEntity:GetPivot()
	local blocked = {}
	for id, record in state.decoys do
		if not record.Active or record.Model.Parent == nil or record.HitProxy.Parent == nil then
			table.insert(blocked, id)
			continue
		end
		local desired = CFrame.new(realPivot.Position + record.Offset) * realPivot.Rotation
		local accepted = context.ResolveFollowPose(record, desired)
		if accepted == nil then
			table.insert(blocked, id)
		else
			record.Model:PivotTo(accepted)
		end
	end
	for _, id in blocked do
		DecoySplit.RemoveDecoy(id, "Blocked", now)
	end
	if not state.active then
		return { Ended = true, Reason = "NoDecoys" }
	end
	return {}
end

function DecoySplit.GetDiagnostics()
	local decoys = 0
	for _ in activeByDecoyId do
		decoys += 1
	end
	return {
		ActiveEncounters = activeEncounterCount,
		ActiveDecoys = decoys,
		HitProxies = decoys,
	}
end

return DecoySplit
