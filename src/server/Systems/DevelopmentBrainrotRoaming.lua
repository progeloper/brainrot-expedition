--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BrainrotBehaviours = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local BrainrotTerritory = require(ReplicatedStorage.Shared.Config.BrainrotTerritory)
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local CamouflageTiming = require(ReplicatedStorage.Shared.Behaviours.CamouflageTiming)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local Camouflage = require(script.Parent.Behaviours.Camouflage)
local DecoySplit = require(script.Parent.Behaviours.DecoySplit)
local LegendaryPursuit = require(script.Parent.Behaviours.LegendaryPursuit)
local NaturalTerritory = require(script.Parent.NaturalTerritory)
local ReactiveRunner = require(script.Parent.Behaviours.ReactiveRunner)
local Sprinter = require(script.Parent.Behaviours.Sprinter)
local Zigzag = require(script.Parent.Behaviours.Zigzag)
local RegionSpawnCatalog = require(script.Parent.RegionSpawnCatalog)
local RouteRules = require(ReplicatedStorage.Shared.Utility.BrainrotRouteRules)
local RouteMotor = require(script.Parent.Parent.Utility.BurrowRouteMotor)
local CharacterMotion = require(ReplicatedStorage.Shared.Config.CharacterMotion)
local MotionTuning = CharacterMotion.Brainrot

local DevelopmentBrainrotRoaming = {}
local log = Logger.new("DevelopmentBrainrotRoaming")

local ROAM_RADIUS = 20
local NORMAL_MOVE_SPEED = 6
local PAUSE_MIN = 1
local PAUSE_MAX = 3
local ARRIVAL_DISTANCE = 1.5
local DIRECTION_EPSILON = 1e-5
local MAX_ROUTE_HALF_WIDTH = 3
local MAX_GROUND_DELTA = 3
local GROUND_PROBE_HEIGHT = 8
local GROUND_PROBE_DEPTH = 16
local MIN_WALKABLE_NORMAL_Y = BrainrotTerritory.MinWalkableNormalY
local BLOCKED_LOG_INTERVAL = 5
local MAX_MOVEMENT_STEP_SECONDS = 0.10
local MAX_BLOCKCAST_DISTANCE = 1024 - 0.001
local ZIGZAG_MOVEMENT_SUBSTEP_SECONDS = 1 / 60
local ZIGZAG_RETRY_ANGLES = table.freeze({ 0, 30, -30, 60, -60 })
local CAMP_RETURN_STEP_DISTANCES = table.freeze({ 18, 9, 4.5, 2.25 })
local CAMP_RETURN_RETRY_ANGLES = table.freeze({ 0, 30, -30, 60, -60, 90, -90 })

type ThreatCandidate = ReactiveRunner.ThreatCandidate
type ReactionState = ReactiveRunner.State
type SprinterState = Sprinter.State
type ZigzagState = Zigzag.State
type CamouflageState = Camouflage.State
type DecoySplitState = DecoySplit.State
type LegendaryPursuitState = LegendaryPursuit.State

type Controller = {
	RouteMotor: any?,
	NormalSpeed: number,
	AccumulatedDelta: number,
	Origin: Vector3,
	RouteParams: RaycastParams,
	Paused: boolean,
	Generation: number,
	Connections: { RBXScriptConnection },
	BehaviourId: string,
	SpawnRegionId: string?,
	TerritoryRegionId: string?,
	ReturnRegionId: string?,
	ReturningToRegion: boolean,
	CampReturnAttempts: number,
	ReturnSteering: any?,
	ReturnStuckReported: boolean?,
	LastReturnBlocker: string?,
	RecoveringTerritory: boolean,
	TerritoryRecoveryGoal: Vector3?,
	NextTerritoryRecoveryAt: number,
	Reaction: ReactionState,
	Sprint: SprinterState,
	Zigzag: ZigzagState,
	Camouflage: CamouflageState,
	DecoySplit: DecoySplitState,
	LegendaryPursuit: LegendaryPursuitState,
	RoamGoal: Vector3?,
	NextRoamAt: number,
	ActiveGoal: Vector3?,
	ActiveGoalKind: string?,
	TurnFromYaw: number?,
	TurnToYaw: number?,
	TurnStartedAt: number?,
	LastBlockedLogAt: number?,
	-- Natural movement presentation (CharacterMotion). Never read by gameplay rules.
	Motion: string?,
	StillSince: number?,
	WasLocked: boolean,
	AlertUntil: number,
	NoticeUntil: number,
	NoticeFace: Vector3?,
	NoticeArmed: boolean,
	NoticeCooldownUntil: number,
}

local SIGNATURE_OFTEN_TIERS: { [string]: boolean } = table.freeze({
	Legendary = true,
	Mythic = true,
	Celestial = true,
	Astral = true,
	Secret = true,
})

local started = false
local heartbeatConnection: RBXScriptConnection? = nil
local sensingElapsed = 0
local latestThreatCandidates: { ThreatCandidate } = {}
local controllers: { [Model]: Controller } = {}
local sprinterCooldownByItemId: { [string]: number } = {}
local decoyCooldownByItemId: { [string]: number } = {}
local legendaryCooldownByItemId: { [string]: number } = {}
local interestResolver: ((string?, Vector3) -> boolean)? = nil

local function isInWorld(brainrot: Model): boolean
	local runtime = Workspace:FindFirstChild("Runtime")
	local folder = if runtime then runtime:FindFirstChild("Brainrots") else nil
	return folder ~= nil and brainrot.Parent == folder
end

local function finitePosition(position: Vector3): boolean
	return position.X == position.X
		and math.abs(position.X) < math.huge
		and position.Y == position.Y
		and math.abs(position.Y) < math.huge
		and position.Z == position.Z
		and math.abs(position.Z) < math.huge
end

local function flatDirection(direction: Vector3): Vector3?
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	return if finitePosition(horizontal) and horizontal.Magnitude > DIRECTION_EPSILON
		then horizontal.Unit
		else nil
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (math.pi * 2) - math.pi
end

local function yawFromDirection(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function directionFromYaw(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function runtimeId(brainrot: Model): string
	local itemId = brainrot:GetAttribute("ItemId")
	return if typeof(itemId) == "string" and itemId ~= "" then itemId else brainrot.Name
end

local function cancelMovement(controller: Controller)
	controller.Generation += 1
	controller.RoamGoal = nil
	controller.NextRoamAt = 0
	controller.ActiveGoal = nil
	controller.ActiveGoalKind = nil
	controller.TurnFromYaw = nil
	controller.TurnToYaw = nil
	controller.TurnStartedAt = nil
end

local function publishCamouflage(brainrot: Model, controller: Controller)
	local snapshot = Camouflage.GetSnapshot(controller.Camouflage, runtimeId(brainrot))
	brainrot:SetAttribute(
		BrainrotDisplayConfig.Attributes.CamouflageSnapshot,
		CamouflageTiming.EncodeSnapshot(snapshot)
	)
end

local function interruptBehaviours(brainrot: Model, controller: Controller, reason: string)
	if controller.RouteMotor then
		RouteMotor.Interrupt(controller.RouteMotor, reason)
	end
	if controller.Reaction.lockedThreatUserId ~= nil then
		log:Info("[ReactiveRunner] Interrupted runtimeId=%s reason=%s", runtimeId(brainrot), reason)
	end
	ReactiveRunner.Reset(controller.Reaction)
	local previousPhase = controller.Sprint.Phase
	local hadSprinterWork = previousPhase == "Burst"
		or previousPhase == "Recovery"
		or controller.Sprint.lockedThreatUserId ~= nil
	Sprinter.Interrupt(controller.Sprint, os.clock(), reason)
	if controller.BehaviourId == "Sprinter" then
		local itemId = brainrot:GetAttribute("ItemId")
		if
			typeof(itemId) == "string"
			and itemId ~= ""
			and controller.Sprint.nextBurstAt > os.clock()
		then
			sprinterCooldownByItemId[itemId] =
				math.max(sprinterCooldownByItemId[itemId] or 0, controller.Sprint.nextBurstAt)
		end
		if hadSprinterWork then
			log:Info("[Sprinter] Interrupted runtimeId=%s reason=%s", runtimeId(brainrot), reason)
		end
	end
	local hadZigzagWork = controller.Zigzag.Mode ~= "Inactive"
		or controller.Zigzag.lockedThreatUserId ~= nil
	Zigzag.Interrupt(controller.Zigzag, os.clock(), reason)
	if controller.BehaviourId == "Zigzag" and hadZigzagWork then
		log:Info("[Zigzag] Interrupted runtimeId=%s reason=%s", runtimeId(brainrot), reason)
	end
	local camouflageWasActive = controller.Camouflage.active
	if Camouflage.Interrupt(controller.Camouflage, Workspace:GetServerTimeNow(), reason) then
		publishCamouflage(brainrot, controller)
		if controller.BehaviourId == "Camouflage" and camouflageWasActive then
			log:Info("[Camouflage] Interrupted runtimeId=%s reason=%s", runtimeId(brainrot), reason)
		end
	end
	local decoyWasActive = controller.DecoySplit.active
	DecoySplit.Interrupt(brainrot, controller.DecoySplit, Workspace:GetServerTimeNow(), reason)
	if controller.BehaviourId == "DecoySplit" then
		local itemId = brainrot:GetAttribute("ItemId")
		if
			type(itemId) == "string"
			and itemId ~= ""
			and controller.DecoySplit.nextAllowedAt > Workspace:GetServerTimeNow()
		then
			decoyCooldownByItemId[itemId] =
				math.max(decoyCooldownByItemId[itemId] or 0, controller.DecoySplit.nextAllowedAt)
		end
		if decoyWasActive then
			log:Info("[DecoySplit] Interrupted runtimeId=%s reason=%s", runtimeId(brainrot), reason)
		end
	end
	local legendaryWasActive = controller.LegendaryPursuit.active
	LegendaryPursuit.Interrupt(
		controller.LegendaryPursuit,
		os.clock(),
		reason,
		BrainrotBehaviours.LegendaryPursuit
	)
	if controller.BehaviourId == "LegendaryPursuit" then
		local itemId = brainrot:GetAttribute("ItemId")
		if
			type(itemId) == "string"
			and itemId ~= ""
			and controller.LegendaryPursuit.nextAllowedAt > os.clock()
		then
			legendaryCooldownByItemId[itemId] = math.max(
				legendaryCooldownByItemId[itemId] or 0,
				controller.LegendaryPursuit.nextAllowedAt
			)
		end
		if legendaryWasActive then
			log:Info(
				"[LegendaryPursuit] Interrupted runtimeId=%s reason=%s",
				runtimeId(brainrot),
				reason
			)
		end
	end
	controller.LastBlockedLogAt = nil
	-- Sleep/pickup interrupts the old escape episode as well as its movement.
	-- A later awake world entry chooses again from its current position.
	controller.ReturnSteering = nil
	controller.TerritoryRecoveryGoal = nil
	controller.NextTerritoryRecoveryAt = 0
	cancelMovement(controller)
end

-- Presentation-only motion state on the existing creature row (sent only on change).
local function setMotion(brainrot: Model, controller: Controller, motion: string)
	if controller.Motion == motion then
		return
	end
	controller.Motion = motion
	brainrot:SetAttribute("Motion", motion)
	brainrot:SetAttribute("MotionAt", math.round(Workspace:GetServerTimeNow() * 100) / 100)
end

local function noticeRadius(behaviourId: string): number
	local tuning = (BrainrotBehaviours :: any)[behaviourId]
	return if tuning
		then tuning.AwarenessRadius * MotionTuning.NoticeRadiusFactor
		else MotionTuning.WandererNoticeRadius
end

local function pickTarget(origin: Vector3): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * ROAM_RADIUS
	return origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function setActiveGoal(
	brainrot: Model,
	controller: Controller,
	goal: Vector3,
	kind: string,
	now: number
)
	if
		controller.ActiveGoal ~= nil
		and controller.ActiveGoalKind == kind
		and (controller.ActiveGoal - goal).Magnitude <= 0.05
	then
		return
	end
	controller.ActiveGoal = goal
	controller.ActiveGoalKind = kind
	local pivot = brainrot:GetPivot()
	local desired = flatDirection(goal - pivot.Position)
	if desired == nil then
		controller.TurnFromYaw = nil
		controller.TurnToYaw = nil
		controller.TurnStartedAt = nil
		return
	end
	local current = flatDirection(pivot.LookVector) or desired
	local currentYaw, desiredYaw = yawFromDirection(current), yawFromDirection(desired)
	controller.TurnFromYaw = currentYaw
	controller.TurnToYaw = desiredYaw
	controller.TurnStartedAt = if (kind == "Escape" or kind == "SprinterEscape")
			and math.abs(wrapAngle(desiredYaw - currentYaw)) > math.rad(5)
		then now
		else nil
end

local function moveToward(
	brainrot: Model,
	controller: Controller,
	target: Vector3,
	dt: number,
	now: number,
	arrivalDistance: number,
	turnBlendSeconds: number,
	goalKind: string,
	moveSpeed: number?,
	canAdvance: ((Vector3, Vector3) -> boolean)?
): (boolean, boolean)
	setActiveGoal(brainrot, controller, target, goalKind, now)
	local pivot = brainrot:GetPivot()
	local current = Vector3.new(pivot.Position.X, controller.Origin.Y, pivot.Position.Z)
	local targetFlat = Vector3.new(target.X, controller.Origin.Y, target.Z)
	local delta = targetFlat - current
	local distance = delta.Magnitude
	if distance <= arrivalDistance then
		return true, false
	end
	local direction = delta / distance
	local facing = direction
	if
		turnBlendSeconds > 0
		and controller.TurnStartedAt ~= nil
		and controller.TurnFromYaw ~= nil
		and controller.TurnToYaw ~= nil
	then
		local alpha = math.clamp((now - controller.TurnStartedAt) / turnBlendSeconds, 0, 1)
		local yawDelta = wrapAngle(controller.TurnToYaw - controller.TurnFromYaw)
		facing = directionFromYaw(controller.TurnFromYaw + yawDelta * alpha)
		if alpha < 1 then
			if goalKind ~= "SprinterEscape" then
				brainrot:PivotTo(CFrame.lookAt(current, current + facing, Vector3.yAxis))
				return false, false
			end
		else
			controller.TurnStartedAt = nil
		end
	end
	local speed = if moveSpeed ~= nil
			and moveSpeed == moveSpeed
			and moveSpeed >= 0
		then moveSpeed
		else controller.NormalSpeed
	local step = math.min(distance, speed * math.min(math.max(dt, 0), MAX_MOVEMENT_STEP_SECONDS))
	local nextPosition = current + direction * step
	if step > 0 and canAdvance ~= nil and not canAdvance(current, nextPosition) then
		return false, true
	end
	if
		step > 0
		and controller.RouteMotor
		and not RouteMotor.RecordExcursion(controller.RouteMotor, current, nextPosition)
	then
		return false, true
	end
	brainrot:PivotTo(CFrame.lookAt(nextPosition, nextPosition + facing, Vector3.yAxis))
	return distance - step <= arrivalDistance, false
end

local function startMovement(brainrot: Model, controller: Controller)
	-- Movement is advanced by one shared Heartbeat connection in Start().
	-- Registration/resume retain this call site so existing lifecycle ownership stays intact.
	if not started or controller.Paused or controllers[brainrot] ~= controller then
		return
	end
end

local function occupiedCart(character: Model): Model?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local current: Instance? = if humanoid then humanoid.SeatPart else nil
	while current and current ~= Workspace do
		if
			current:IsA("Model")
			and (
				current:GetAttribute("RuntimeCart") == true
				or current:GetAttribute("CartId") ~= nil
			)
		then
			return current
		end
		current = current.Parent
	end
	return nil
end

function DevelopmentBrainrotRoaming.BuildThreatSnapshot(): { ThreatCandidate }
	local candidates = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if
			character ~= nil
			and character.Parent ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and root ~= nil
			and root:IsA("BasePart")
			and finitePosition(root.Position)
		then
			table.insert(candidates, {
				UserId = player.UserId,
				Character = character,
				Position = root.Position,
			})
		end
	end
	return candidates
end

local function canSeeCandidate(brainrot: Model, candidate: ThreatCandidate): boolean
	local character = candidate.Character
	if typeof(character) ~= "Instance" or not character:IsA("Model") or character.Parent == nil then
		return false
	end
	local origin = brainrot:GetPivot().Position
	local direction = candidate.Position - origin
	if direction.Magnitude <= DIRECTION_EPSILON then
		return true
	end
	local ignored: { Instance } = { brainrot, character }
	local cart = occupiedCart(character)
	if cart then
		table.insert(ignored, cart)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	return Workspace:Raycast(origin, direction, params) == nil
end

local function routeParams(brainrot: Model): RaycastParams
	local controller = controllers[brainrot]
	if controller ~= nil then
		return controller.RouteParams
	end
	-- The self-only filter is stable for this controller's lifetime. Reuse it
	-- across route and movement checks; unregistered fixture callers stay transient.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { brainrot }
	params.RespectCanCollide = true
	return params
end

local function hasUsableGround(point: Vector3, referenceY: number, params: RaycastParams): boolean
	local result = Workspace:Raycast(
		point + Vector3.yAxis * GROUND_PROBE_HEIGHT,
		-Vector3.yAxis * GROUND_PROBE_DEPTH,
		params
	)
	return result ~= nil
		and result.Normal.Y >= MIN_WALKABLE_NORMAL_Y
		and math.abs(result.Position.Y - referenceY) <= MAX_GROUND_DELTA
end

local function movementEnvelope(brainrot: Model): (CFrame?, Vector3?)
	local body = brainrot:FindFirstChild("Body", true)
	if body == nil or not body:IsA("BasePart") then
		return nil, nil
	end
	-- Body is the project's canonical visible torso/collision reference. Avoid the
	-- full decorative bounding box so fins, props and nametag helpers do not turn
	-- into an inflated movement volume.
	-- CSG Body authoring origins can differ from their actual geometry centre.
	-- Casting Size at that origin puts an otherwise grounded torso below floor
	-- seams. Extents retain the same torso geometry without using its art pivot.
	local extentsSize = body.ExtentsSize
	return body.ExtentsCFrame,
		Vector3.new(
			math.max(0.5, extentsSize.X),
			math.max(0.5, extentsSize.Y),
			math.max(0.5, extentsSize.Z)
		)
end

local function movementEnvelopeAt(brainrot: Model, position: Vector3): (CFrame?, Vector3?)
	local bodyFrame, bodySize = movementEnvelope(brainrot)
	if bodyFrame == nil or bodySize == nil then
		return nil, nil
	end
	local pivot = brainrot:GetPivot()
	local localBodyFrame = pivot:ToObjectSpace(bodyFrame)
	return CFrame.new(position) * pivot.Rotation * localBodyFrame, bodySize
end

-- Camp return must protect the whole grounded character column, not only an
-- elevated torso. Otherwise a target can walk onto a low base foundation and
-- become trapped when its torso later reaches a taller ramp or building part.
local function campReturnProtectionEnvelopeAt(
	brainrot: Model,
	position: Vector3,
	groundY: number
): (CFrame?, Vector3?)
	local bodyFrame, bodySize = movementEnvelopeAt(brainrot, position)
	if bodyFrame == nil or bodySize == nil then
		return nil, nil
	end
	local bodyBottom = bodyFrame.Position.Y - bodySize.Y * 0.5
	local bodyTop = bodyFrame.Position.Y + bodySize.Y * 0.5
	local bottom = math.min(groundY, bodyBottom)
	local top = math.max(groundY + 0.5, bodyTop)
	local height = math.max(0.5, top - bottom)
	local centre = Vector3.new(bodyFrame.Position.X, bottom + height * 0.5, bodyFrame.Position.Z)
	return CFrame.new(centre) * bodyFrame.Rotation, Vector3.new(bodySize.X, height, bodySize.Z)
end

-- Test the whole grounded step before selecting it. Checking only its endpoint
-- lets a low foundation/ramp sit between two safe positions, so the movement
-- guard immediately rejects the selected goal forever. The horizontal radius
-- covers Body rotation and its offset from the model pivot as moveToward faces
-- the step, without including art. Its centre must not move when yaw changes.
local function campReturnRouteEnvelope(
	brainrot: Model,
	from: Vector3,
	to: Vector3,
	groundY: number
): (CFrame?, Vector3?)
	local frame, size = campReturnProtectionEnvelopeAt(brainrot, from, groundY)
	if frame == nil or size == nil then
		return nil, nil
	end
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local horizontalOffset =
		Vector2.new(frame.Position.X - from.X, frame.Position.Z - from.Z).Magnitude
	local width = math.sqrt(size.X * size.X + size.Z * size.Z) + 2 * horizontalOffset
	local centre = Vector3.new(from.X, frame.Position.Y, from.Z) + delta * 0.5
	local direction = if delta.Magnitude > DIRECTION_EPSILON then delta.Unit else Vector3.zAxis
	return CFrame.lookAt(centre, centre + direction),
		Vector3.new(width, size.Y, delta.Magnitude + width)
end

local function isInsideTerritory(
	brainrot: Model,
	controller: Controller,
	position: Vector3
): boolean
	if controller.TerritoryRegionId == nil then
		return true
	end
	local frame, size = movementEnvelopeAt(brainrot, position)
	if frame == nil or size == nil then
		return false
	end
	return RegionSpawnCatalog.IsInsideHuntingSpace(
		controller.TerritoryRegionId,
		frame,
		size,
		BrainrotTerritory.BoundaryPaddingStuds
	)
end

local function isInsideRegion(
	brainrot: Model,
	regionId: string,
	position: Vector3,
	padding: number?
): boolean
	local frame, size = movementEnvelopeAt(brainrot, position)
	if frame == nil or size == nil then
		return false
	end
	return RegionSpawnCatalog.IsInsideRegionSpace(regionId, frame, size, padding)
end

local function routeSegmentLengths(distance: number): { number }
	local lengths = {}
	local remaining = math.max(0, distance)
	while remaining > DIRECTION_EPSILON do
		local length = math.min(MAX_BLOCKCAST_DISTANCE, remaining)
		table.insert(lengths, length)
		remaining -= length
	end
	return lengths
end

local function blockcastRoute(
	brainrot: Model,
	startPosition: Vector3,
	goal: Vector3,
	params: RaycastParams,
	returnDiagnostics: Controller?
): boolean
	local bodyFrame, bodySize = movementEnvelope(brainrot)
	if bodyFrame == nil or bodySize == nil then
		return false
	end
	local pivot = brainrot:GetPivot()
	local atStart = CFrame.new(startPosition) * pivot.Rotation * pivot:ToObjectSpace(bodyFrame)
	local displacement = Vector3.new(goal.X - startPosition.X, 0, goal.Z - startPosition.Z)
	local distance = displacement.Magnitude
	if distance <= DIRECTION_EPSILON then
		return true
	end
	local direction = displacement.Unit
	local travelled = 0
	for _, segmentDistance in routeSegmentLengths(distance) do
		local segmentFrame = atStart + direction * travelled
		local hit = Workspace:Blockcast(segmentFrame, bodySize, direction * segmentDistance, params)
		if hit ~= nil then
			if returnDiagnostics then
				returnDiagnostics.LastReturnBlocker = string.sub(hit.Instance:GetFullName(), 1, 512)
			end
			return false
		end
		travelled += segmentDistance
	end
	return true
end

local function isSafeRoute(
	brainrot: Model,
	controller: Controller,
	startPosition: Vector3,
	goal: Vector3
): boolean
	local flatDelta = Vector3.new(goal.X - startPosition.X, 0, goal.Z - startPosition.Z)
	if flatDelta.Magnitude <= DIRECTION_EPSILON then
		return false
	end
	local originDelta = Vector3.new(goal.X - controller.Origin.X, 0, goal.Z - controller.Origin.Z)
	if originDelta.Magnitude > ROAM_RADIUS then
		return false
	end
	if not isInsideTerritory(brainrot, controller, goal) then
		return false
	end
	local direction = flatDelta.Unit
	local right = Vector3.new(-direction.Z, 0, direction.X)
	local _, boundsSize = brainrot:GetBoundingBox()
	local halfWidth =
		math.min(MAX_ROUTE_HALF_WIDTH, math.max(0.75, math.max(boundsSize.X, boundsSize.Z) * 0.5))
	local params = routeParams(brainrot)
	if not blockcastRoute(brainrot, startPosition, goal, params) then
		return false
	end
	for _, lateral in { -halfWidth, 0, halfWidth } do
		for _, height in { 0.5, math.max(0.5, math.min(4, boundsSize.Y * 0.6)) } do
			local rayOrigin = startPosition + right * lateral + Vector3.yAxis * height
			if Workspace:Raycast(rayOrigin, flatDelta, params) ~= nil then
				return false
			end
		end
	end
	for _, progress in { 0.33, 0.66, 1 } do
		local point = startPosition + flatDelta * progress
		if
			not isInsideTerritory(brainrot, controller, point)
			or not hasUsableGround(point, controller.Origin.Y, params)
		then
			return false
		end
	end
	return true
end

local function isSafeMovementStep(
	brainrot: Model,
	controller: Controller,
	startPosition: Vector3,
	nextPosition: Vector3
): boolean
	local delta = Vector3.new(nextPosition.X - startPosition.X, 0, nextPosition.Z - startPosition.Z)
	if delta.Magnitude <= DIRECTION_EPSILON then
		return true
	end
	local originDelta =
		Vector3.new(nextPosition.X - controller.Origin.X, 0, nextPosition.Z - controller.Origin.Z)
	if originDelta.Magnitude > ROAM_RADIUS then
		return false
	end
	if not isInsideTerritory(brainrot, controller, nextPosition) then
		return false
	end
	local params = routeParams(brainrot)
	return blockcastRoute(brainrot, startPosition, nextPosition, params)
		and hasUsableGround(nextPosition, controller.Origin.Y, params)
end

local function isSafeTerritoryRecoveryRoute(
	brainrot: Model,
	controller: Controller,
	startPosition: Vector3,
	goal: Vector3
): boolean
	local flatDelta = Vector3.new(goal.X - startPosition.X, 0, goal.Z - startPosition.Z)
	if
		flatDelta.Magnitude <= DIRECTION_EPSILON
		or not isInsideTerritory(brainrot, controller, goal)
	then
		return false
	end
	local params = routeParams(brainrot)
	if not blockcastRoute(brainrot, startPosition, goal, params) then
		return false
	end
	for _, progress in { 0.33, 0.66, 1 } do
		local point = startPosition + flatDelta * progress
		local frame, size = movementEnvelopeAt(brainrot, point)
		local protected = if frame and size
			then RegionSpawnCatalog.IsProtectedSpace(frame, size)
			else true
		local protectedCampStart = controller.ReturningToRegion
			and isInsideRegion(brainrot, Regions.CampId, point, 0)
		if
			(protected and not protectedCampStart)
			or not hasUsableGround(point, controller.Origin.Y, params)
		then
			return false
		end
	end
	return true
end

local function chooseTerritoryRecoveryGoal(
	brainrot: Model,
	controller: Controller,
	position: Vector3
): Vector3?
	local candidates = {}
	for _, area in RegionSpawnCatalog.GetSpawnAreas(controller.TerritoryRegionId) do
		if area.Enabled and area.UsableProbeCount > 0 and area.Part:IsA("BasePart") then
			local part = area.Part
			local candidate = if area.Kind == "Volume"
				then part.CFrame:PointToWorldSpace(Vector3.new(0, -part.Size.Y * 0.5, 0))
				else part.Position
			table.insert(candidates, Vector3.new(candidate.X, controller.Origin.Y, candidate.Z))
		end
	end
	if controller.ReturningToRegion then
		if controller.ReturnSteering and controller.ReturnSteering.ReturnStuck then
			return nil
		end
		table.sort(candidates, function(left, right)
			return (left - position).Magnitude < (right - position).Magnitude
		end)
		local destination = candidates[1]
		if destination == nil then
			return nil
		end
		local params = routeParams(brainrot)
		controller.ReturnSteering = controller.ReturnSteering
			or NaturalTerritory.CreateReturnSteering()
		return NaturalTerritory.SelectReturnStep(
			position,
			destination,
			CAMP_RETURN_STEP_DISTANCES,
			CAMP_RETURN_RETRY_ANGLES,
			function(candidate)
				local frame, size =
					campReturnRouteEnvelope(brainrot, position, candidate, controller.Origin.Y)
				if frame == nil or size == nil then
					controller.LastReturnBlocker = "INVALID_ENVELOPE"
					return false
				end
				local protected, protectionReason, protectionOwner =
					RegionSpawnCatalog.IsProtectedForCampReturn(frame, size)
				if protected then
					controller.LastReturnBlocker = protectionOwner
						or protectionReason
						or "PROTECTED_AREA_OVERLAP"
					return false
				end
				if not blockcastRoute(brainrot, position, candidate, params, controller) then
					return false
				end
				local grounded = hasUsableGround(candidate, controller.Origin.Y, params)
				if not grounded then
					controller.LastReturnBlocker = "NO_USABLE_GROUND"
				end
				return grounded
			end,
			controller.ReturnSteering
		)
	end
	return NaturalTerritory.SelectRecoveryGoal(position, candidates, function(candidate)
		return isInsideTerritory(brainrot, controller, candidate)
	end, function(candidate)
		return isSafeTerritoryRecoveryRoute(brainrot, controller, position, candidate)
	end)
end

local function updateTerritoryRecovery(
	brainrot: Model,
	controller: Controller,
	now: number,
	dt: number
)
	local position = brainrot:GetPivot().Position
	if isInsideTerritory(brainrot, controller, position) then
		if controller.ReturningToRegion then
			local destination = controller.ReturnRegionId
			controller.ReturningToRegion = false
			controller.ReturnSteering = nil
			controller.ReturnStuckReported = nil
			controller.LastReturnBlocker = nil
			controller.ReturnRegionId = nil
			controller.TerritoryRegionId = nil
			controller.Origin = position
			brainrot:SetAttribute("CampReturnRegionId", nil)
			log:Info(
				"CampReturnCompleted runtimeId=%s destination=%s attempts=%d",
				runtimeId(brainrot),
				tostring(destination),
				controller.CampReturnAttempts
			)
		end
		controller.RecoveringTerritory = false
		controller.TerritoryRecoveryGoal = nil
		controller.NextTerritoryRecoveryAt = 0
		return
	end
	if controller.TerritoryRecoveryGoal == nil and now >= controller.NextTerritoryRecoveryAt then
		controller.TerritoryRecoveryGoal =
			chooseTerritoryRecoveryGoal(brainrot, controller, position)
		if controller.TerritoryRecoveryGoal == nil then
			if controller.ReturnSteering and controller.ReturnSteering.ReturnStuck then
				if not controller.ReturnStuckReported then
					controller.ReturnStuckReported = true
					log:Warn(
						"RETURN_STUCK runtimeId=%s species=%s home=%s position=%s homeDistance=%s decisions=%s lastBlocker=%s",
						runtimeId(brainrot),
						tostring(brainrot:GetAttribute("BrainrotId")),
						tostring(controller.ReturnRegionId),
						tostring(position),
						tostring(controller.ReturnSteering.LastHomeDistance),
						tostring(controller.ReturnSteering.DecisionCount),
						tostring(controller.LastReturnBlocker or "UNOBSERVED")
					)
				end
				return
			end
			if
				controller.ReturningToRegion
				and (
					controller.LastBlockedLogAt == nil
					or now - controller.LastBlockedLogAt >= BLOCKED_LOG_INTERVAL
				)
			then
				controller.LastBlockedLogAt = now
				log:Warn(
					"CampReturnBlocked runtimeId=%s destination=%s position=%s",
					runtimeId(brainrot),
					tostring(controller.ReturnRegionId),
					tostring(position)
				)
			end
			controller.NextTerritoryRecoveryAt = now
				+ BrainrotBehaviours.ReactiveRunner.BlockedRetrySeconds
			return
		end
		if controller.ReturningToRegion then
			controller.CampReturnAttempts += 1
			log:Info(
				"CampReturnRetargeted runtimeId=%s destination=%s attempt=%d",
				runtimeId(brainrot),
				tostring(controller.ReturnRegionId),
				controller.CampReturnAttempts
			)
		end
	end
	local goal = controller.TerritoryRecoveryGoal
	if goal == nil then
		return
	end
	local function canAdvance(current: Vector3, nextPosition: Vector3): boolean
		if
			not controller.ReturningToRegion
			and (nextPosition - goal).Magnitude >= (current - goal).Magnitude
		then
			return false
		end
		local params = routeParams(brainrot)
		local frame, size
		if controller.ReturningToRegion then
			frame, size =
				campReturnRouteEnvelope(brainrot, current, nextPosition, controller.Origin.Y)
		else
			frame, size = movementEnvelopeAt(brainrot, nextPosition)
		end
		local protected = true
		local protectionReason: string? = "INVALID_ENVELOPE"
		local protectionOwner: string? = nil
		if frame and size then
			if controller.ReturningToRegion then
				protected, protectionReason, protectionOwner =
					RegionSpawnCatalog.IsProtectedForCampReturn(frame, size)
			else
				protected, protectionReason = RegionSpawnCatalog.IsProtectedSpace(frame, size)
			end
		end
		if frame == nil or size == nil or protected then
			if controller.ReturningToRegion then
				controller.LastReturnBlocker = protectionOwner
					or protectionReason
					or "PROTECTED_AREA_OVERLAP"
			end
			return false
		end
		if
			not blockcastRoute(
				brainrot,
				current,
				nextPosition,
				params,
				if controller.ReturningToRegion then controller else nil
			)
		then
			return false
		end
		local grounded = hasUsableGround(nextPosition, controller.Origin.Y, params)
		if controller.ReturningToRegion and not grounded then
			controller.LastReturnBlocker = "NO_USABLE_GROUND"
		end
		return grounded
	end
	local arrived, blocked = moveToward(
		brainrot,
		controller,
		goal,
		dt,
		now,
		ARRIVAL_DISTANCE,
		0,
		"TerritoryRecovery",
		controller.NormalSpeed,
		canAdvance
	)
	if arrived or blocked then
		controller.TerritoryRecoveryGoal = nil
		controller.NextTerritoryRecoveryAt = now
			+ BrainrotBehaviours.ReactiveRunner.BlockedRetrySeconds
	end
end

local function resolveDecoyPose(
	owner: Model,
	controller: Controller,
	desiredPivot: CFrame,
	hitProxyLocalFrame: CFrame,
	hitProxySize: Vector3,
	movingVisual: Model?
): CFrame?
	local ignored: { Instance } = { owner }
	if movingVisual then
		table.insert(ignored, movingVisual)
	end
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = ignored
	groundParams.RespectCanCollide = true
	local ground = Workspace:Raycast(
		desiredPivot.Position + Vector3.yAxis * GROUND_PROBE_HEIGHT,
		-Vector3.yAxis * GROUND_PROBE_DEPTH,
		groundParams
	)
	if
		ground == nil
		or ground.Material == Enum.Material.Water
		or ground.Normal.Y < MIN_WALKABLE_NORMAL_Y
		or math.abs(ground.Position.Y - owner:GetPivot().Position.Y) > MAX_GROUND_DELTA
	then
		return nil
	end
	local accepted = CFrame.new(desiredPivot.X, ground.Position.Y, desiredPivot.Z)
		* desiredPivot.Rotation
	local worldHitFrame = accepted * hitProxyLocalFrame
	if
		controller.TerritoryRegionId ~= nil
		and not RegionSpawnCatalog.IsInsideHuntingSpace(
			controller.TerritoryRegionId,
			worldHitFrame,
			hitProxySize,
			BrainrotTerritory.BoundaryPaddingStuds
		)
	then
		return nil
	end
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local overlapIgnored = table.clone(ignored)
	table.insert(overlapIgnored, ground.Instance)
	overlapParams.FilterDescendantsInstances = overlapIgnored
	overlapParams.RespectCanCollide = false
	overlapParams.MaxParts = 1
	local overlapSize = Vector3.new(
		math.max(0.1, hitProxySize.X - 0.05),
		math.max(0.1, hitProxySize.Y - 0.05),
		math.max(0.1, hitProxySize.Z - 0.05)
	)
	if #Workspace:GetPartBoundsInBox(worldHitFrame, overlapSize, overlapParams) > 0 then
		return nil
	end

	local startPivot = if movingVisual then movingVisual:GetPivot() else owner:GetPivot()
	local displacement = accepted.Position - startPivot.Position
	if displacement.Magnitude > DIRECTION_EPSILON then
		local decoyRouteParams = RaycastParams.new()
		decoyRouteParams.FilterType = Enum.RaycastFilterType.Exclude
		decoyRouteParams.FilterDescendantsInstances = overlapIgnored
		decoyRouteParams.RespectCanCollide = false
		local startFrame = startPivot * hitProxyLocalFrame
		if Workspace:Blockcast(startFrame, overlapSize, displacement, decoyRouteParams) ~= nil then
			return nil
		end
	end
	return accepted
end

local function resolveEscapeGoal(
	brainrot: Model,
	controller: Controller,
	position: Vector3,
	_threatPosition: Vector3,
	preferredDirection: Vector3,
	desiredDistance: number
): Vector3?
	return ReactiveRunner.ResolveEscapeGoal(
		position,
		preferredDirection,
		desiredDistance,
		function(candidate)
			local goal = Vector3.new(candidate.X, controller.Origin.Y, candidate.Z)
			return isSafeRoute(brainrot, controller, position, goal)
		end
	)
end

local function resolveSprinterEscapeGoal(
	brainrot: Model,
	controller: Controller,
	position: Vector3,
	_threatPosition: Vector3,
	preferredDirection: Vector3,
	desiredDistance: number,
	minimumDistance: number
): Vector3?
	local function resolveAtDistance(distance: number): Vector3?
		return ReactiveRunner.ResolveEscapeGoal(
			position,
			preferredDirection,
			distance,
			function(candidate)
				local goal = Vector3.new(candidate.X, controller.Origin.Y, candidate.Z)
				local horizontalDistance =
					Vector3.new(goal.X - position.X, 0, goal.Z - position.Z).Magnitude
				return horizontalDistance >= minimumDistance
					and isSafeRoute(brainrot, controller, position, goal)
			end
		)
	end
	local goal = resolveAtDistance(desiredDistance)
	if goal ~= nil or desiredDistance <= minimumDistance + DIRECTION_EPSILON then
		return goal
	end
	-- The shared helper's shorter pass is one-half length. At the current
	-- six-stud normal speed that is below the eight-stud Sprinter minimum, so
	-- explicitly make the one permitted minimum-clearance pass.
	return resolveAtDistance(minimumDistance)
end

local function rotateHorizontal(direction: Vector3, angleDegrees: number): Vector3
	local angle = math.rad(angleDegrees)
	local right = direction:Cross(Vector3.yAxis)
	return (direction * math.cos(angle) + right * math.sin(angle)).Unit
end

local function isSafeZigzagPatternCourse(
	brainrot: Model,
	controller: Controller,
	position: Vector3,
	direction: Vector3,
	desiredDistance: number
): boolean
	local centreGoal = position + direction * desiredDistance
	centreGoal = Vector3.new(centreGoal.X, controller.Origin.Y, centreGoal.Z)
	if not isSafeRoute(brainrot, controller, position, centreGoal) then
		return false
	end
	local plannedSeconds = BrainrotBehaviours.Zigzag.SweepDurationSeconds
		+ BrainrotBehaviours.Zigzag.StraightDurationSeconds
	local plan = Zigzag.BuildCyclePlan(
		desiredDistance / plannedSeconds,
		BrainrotBehaviours.Zigzag.InitialSide,
		BrainrotBehaviours.Zigzag
	)
	if plan == nil then
		return false
	end
	local sweepDistance = plan.BaseSpeed * plan.SweepDurationSeconds
	local sweepAngle = math.deg(plan.EffectiveAngleRadians)
	for _, angleDegrees in { sweepAngle, -sweepAngle } do
		local sweepDirection = rotateHorizontal(direction, angleDegrees)
		local sweepGoal = position + sweepDirection * sweepDistance
		sweepGoal = Vector3.new(sweepGoal.X, controller.Origin.Y, sweepGoal.Z)
		if not isSafeRoute(brainrot, controller, position, sweepGoal) then
			return false
		end
	end
	return true
end

local function resolveZigzagCourse(
	brainrot: Model,
	controller: Controller,
	position: Vector3,
	_threatPosition: Vector3,
	preferredDirection: Vector3,
	desiredDistance: number
): Vector3?
	for _, angleDegrees in ZIGZAG_RETRY_ANGLES do
		local direction = rotateHorizontal(preferredDirection, angleDegrees)
		if
			isSafeZigzagPatternCourse(brainrot, controller, position, direction, desiredDistance)
		then
			return direction
		end
	end
	return nil
end

local function isZigzagCourseSafe(
	brainrot: Model,
	controller: Controller,
	position: Vector3,
	direction: Vector3,
	desiredDistance: number
): boolean
	return isSafeZigzagPatternCourse(brainrot, controller, position, direction, desiredDistance)
end

local function lifecycleEligible(brainrot: Model, controller: Controller): boolean
	return started
		and controllers[brainrot] == controller
		and not controller.Paused
		and isInWorld(brainrot)
		and brainrot:GetAttribute("Captured") ~= true
end

local function updateRoaming(
	brainrot: Model,
	controller: Controller,
	now: number,
	dt: number,
	moveSpeed: number?
)
	if controller.NoticeFace ~= nil then
		if now < controller.NoticeUntil then
			-- Notice beat: stop and turn to look at the player, then carry on.
			local pivot = brainrot:GetPivot()
			local currentYaw =
				yawFromDirection(flatDirection(pivot.LookVector) or controller.NoticeFace)
			local turn = math.rad(MotionTuning.NoticeTurnRateDegrees) * math.max(dt, 0)
			local yaw = currentYaw
				+ math.clamp(
					wrapAngle(yawFromDirection(controller.NoticeFace) - currentYaw),
					-turn,
					turn
				)
			brainrot:PivotTo(
				CFrame.lookAt(pivot.Position, pivot.Position + directionFromYaw(yaw), Vector3.yAxis)
			)
			if controller.RouteMotor then
				controller.RouteMotor.Speed = 0
			end
			return
		end
		controller.NoticeFace = nil
	end
	if controller.RouteMotor then
		RouteMotor.Step(
			controller.RouteMotor,
			dt,
			moveSpeed or controller.NormalSpeed,
			Workspace:GetServerTimeNow()
		)
		controller.Origin = brainrot:GetPivot().Position
		return
	end
	if controller.RoamGoal == nil then
		if now < controller.NextRoamAt then
			return
		end
		if controller.TerritoryRegionId == nil then
			controller.RoamGoal = pickTarget(controller.Origin)
		else
			local position = brainrot:GetPivot().Position
			for _ = 1, BrainrotTerritory.MaxPlacementAttemptsPerSpawn do
				local candidate = pickTarget(controller.Origin)
				if isSafeRoute(brainrot, controller, position, candidate) then
					controller.RoamGoal = candidate
					break
				end
			end
			if controller.RoamGoal == nil then
				controller.NextRoamAt = now + BrainrotBehaviours.ReactiveRunner.BlockedRetrySeconds
				return
			end
		end
	end
	local canAdvance = if controller.TerritoryRegionId
		then function(current, nextPosition)
			return isSafeMovementStep(brainrot, controller, current, nextPosition)
		end
		else nil
	local arrived, blocked = moveToward(
		brainrot,
		controller,
		controller.RoamGoal,
		dt,
		now,
		ARRIVAL_DISTANCE,
		0,
		"Roaming",
		moveSpeed,
		canAdvance
	)
	if arrived then
		controller.RoamGoal = nil
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
		controller.NextRoamAt = now + PAUSE_MIN + math.random() * (PAUSE_MAX - PAUSE_MIN)
	elseif blocked then
		controller.RoamGoal = nil
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
		controller.NextRoamAt = now + BrainrotBehaviours.ReactiveRunner.BlockedRetrySeconds
	end
end

local function logDecision(
	brainrot: Model,
	controller: Controller,
	decision: ReactiveRunner.Decision,
	position: Vector3,
	candidates: { ThreatCandidate },
	now: number
)
	if decision.AcquiredUserId ~= nil then
		local distance = -1
		for _, candidate in candidates do
			if candidate.UserId == decision.AcquiredUserId then
				distance = (candidate.Position - position).Magnitude
				break
			end
		end
		log:Info(
			"[ReactiveRunner] Acquired runtimeId=%s speciesId=%s threatUserId=%d distance=%.2f",
			runtimeId(brainrot),
			tostring(brainrot:GetAttribute("BrainrotId")),
			decision.AcquiredUserId,
			distance
		)
	end
	if decision.ReleaseReason ~= nil then
		log:Info(
			"[ReactiveRunner] Released runtimeId=%s reason=%s",
			runtimeId(brainrot),
			decision.ReleaseReason
		)
	end
	if
		decision.RouteBlocked == true
		and (
			controller.LastBlockedLogAt == nil
			or now - controller.LastBlockedLogAt >= BLOCKED_LOG_INTERVAL
		)
	then
		controller.LastBlockedLogAt = now
		log:Debug(
			"[ReactiveRunner] RouteBlocked runtimeId=%s retryAt=%.2f",
			runtimeId(brainrot),
			now + BrainrotBehaviours.ReactiveRunner.BlockedRetrySeconds
		)
	end
end

local function updateReactiveRunner(
	brainrot: Model,
	controller: Controller,
	now: number,
	dt: number,
	sensing: boolean,
	candidates: { ThreatCandidate }
)
	local pivot = brainrot:GetPivot()
	local position = pivot.Position
	local decision = ReactiveRunner.Step(controller.Reaction, {
		LifecycleEligible = lifecycleEligible(brainrot, controller),
		Position = position,
		Forward = pivot.LookVector,
		ResolvedSpeed = controller.NormalSpeed,
		Candidates = candidates,
		Sensing = sensing,
		CanSeeCandidate = function(candidate)
			return canSeeCandidate(brainrot, candidate)
		end,
		ResolveEscapeGoal = function(current, threat, preferred, distance)
			return resolveEscapeGoal(brainrot, controller, current, threat, preferred, distance)
		end,
	}, now, BrainrotBehaviours.ReactiveRunner)
	logDecision(brainrot, controller, decision, position, candidates, now)

	if decision.AcquiredUserId ~= nil or decision.ReleaseReason ~= nil then
		controller.RoamGoal = nil
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
		controller.NextRoamAt = now
	end
	if decision.Kind == "UseRoaming" then
		updateRoaming(brainrot, controller, now, dt)
	elseif decision.Kind == "Escape" and decision.Goal ~= nil then
		moveToward(
			brainrot,
			controller,
			decision.Goal,
			dt,
			now,
			BrainrotBehaviours.ReactiveRunner.GoalReachedDistance,
			BrainrotBehaviours.ReactiveRunner.TurnBlendSeconds,
			"Escape",
			nil,
			if controller.TerritoryRegionId
				then function(current, nextPosition)
					return isSafeMovementStep(brainrot, controller, current, nextPosition)
				end
				else nil
		)
	elseif decision.Kind == "Hold" then
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
	elseif decision.Kind == "Stop" then
		cancelMovement(controller)
	end
end

local function sprinterThreatDistance(
	userId: number,
	position: Vector3,
	candidates: { ThreatCandidate }
): number
	for _, candidate in candidates do
		if candidate.UserId == userId then
			return (candidate.Position - position).Magnitude
		end
	end
	return -1
end

local function logSprinterDecision(
	brainrot: Model,
	controller: Controller,
	result: Sprinter.Decision,
	position: Vector3,
	candidates: { ThreatCandidate },
	now: number
)
	local state = controller.Sprint
	if result.AcquiredUserId ~= nil then
		log:Info(
			"[Sprinter] Acquired runtimeId=%s speciesId=%s threatUserId=%d distance=%.2f",
			runtimeId(brainrot),
			tostring(brainrot:GetAttribute("BrainrotId")),
			result.AcquiredUserId,
			sprinterThreatDistance(result.AcquiredUserId, position, candidates)
		)
	end
	if result.ReleaseReason ~= nil then
		log:Info(
			"[Sprinter] Released runtimeId=%s reason=%s",
			runtimeId(brainrot),
			result.ReleaseReason
		)
	end
	if result.BurstStarted then
		local baseSpeed = state.cycleBaseSpeed or controller.NormalSpeed
		log:Info(
			"[Sprinter] BurstStarted runtimeId=%s threatUserId=%s baseSpeed=%.2f peakSpeed=%.2f startedAt=%.3f",
			runtimeId(brainrot),
			tostring(state.lockedThreatUserId),
			baseSpeed,
			baseSpeed * BrainrotBehaviours.Sprinter.BurstSpeedMultiplier,
			now
		)
	end
	if result.RecoveryStarted then
		log:Info(
			"[Sprinter] RecoveryStarted runtimeId=%s reason=%s at=%.3f",
			runtimeId(brainrot),
			result.RecoveryReason or "CompletedBurst",
			now
		)
	end
	if result.CooldownStarted then
		log:Info(
			"[Sprinter] CooldownStarted runtimeId=%s nextBurstAt=%.3f",
			runtimeId(brainrot),
			state.nextBurstAt
		)
	end
	if
		result.RouteBlocked == true
		and (
			controller.LastBlockedLogAt == nil
			or now - controller.LastBlockedLogAt >= BLOCKED_LOG_INTERVAL
		)
	then
		controller.LastBlockedLogAt = now
		log:Debug(
			"[Sprinter] RouteBlocked runtimeId=%s retryAt=%.3f",
			runtimeId(brainrot),
			state.nextBlockedRetryAt
		)
	end
end

local function updateSprinter(
	brainrot: Model,
	controller: Controller,
	now: number,
	dt: number,
	sensing: boolean,
	candidates: { ThreatCandidate }
)
	local pivot = brainrot:GetPivot()
	local position = pivot.Position
	local result = Sprinter.Step(controller.Sprint, {
		LifecycleEligible = lifecycleEligible(brainrot, controller),
		Position = position,
		Forward = pivot.LookVector,
		ResolvedSpeed = controller.NormalSpeed,
		Candidates = candidates,
		Sensing = sensing,
		CanSeeCandidate = function(candidate)
			return canSeeCandidate(brainrot, candidate)
		end,
		ResolveEscapeGoal = function(current, threat, preferred, distance, minimumDistance)
			return resolveSprinterEscapeGoal(
				brainrot,
				controller,
				current,
				threat,
				preferred,
				distance,
				minimumDistance
			)
		end,
	}, now, BrainrotBehaviours.Sprinter)
	logSprinterDecision(brainrot, controller, result, position, candidates, now)

	if result.BurstStarted or result.AcquiredUserId ~= nil or result.ReleaseReason ~= nil then
		controller.RoamGoal = nil
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
		controller.NextRoamAt = now
	end
	if result.Kind == "Roam" then
		updateRoaming(brainrot, controller, now, dt, result.RequestedSpeed)
	elseif result.Kind == "Escape" and result.Goal ~= nil then
		local boundedDt = math.min(math.max(dt, 0), MAX_MOVEMENT_STEP_SECONDS)
		local moveSpeed = result.RequestedSpeed or controller.NormalSpeed
		if controller.Sprint.burstStartedAt ~= nil and boundedDt > 0 then
			moveSpeed = Sprinter.AverageSpeed(
				controller.Sprint,
				now - boundedDt,
				now,
				BrainrotBehaviours.Sprinter
			)
		end
		local _, blocked = moveToward(
			brainrot,
			controller,
			result.Goal,
			boundedDt,
			now,
			ARRIVAL_DISTANCE,
			BrainrotBehaviours.ReactiveRunner.TurnBlendSeconds,
			"SprinterEscape",
			moveSpeed,
			function(current, nextPosition)
				return isSafeMovementStep(brainrot, controller, current, nextPosition)
			end
		)
		if blocked and controller.Sprint.Phase == "Burst" then
			local entered = Sprinter.EnterRecovery(
				controller.Sprint,
				now,
				moveSpeed,
				"Blocked",
				BrainrotBehaviours.Sprinter
			)
			if entered then
				controller.ActiveGoal = nil
				controller.ActiveGoalKind = nil
				log:Info(
					"[Sprinter] RecoveryStarted runtimeId=%s reason=Blocked at=%.3f",
					runtimeId(brainrot),
					now
				)
			end
		end
	elseif result.Kind == "Hold" then
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
	elseif result.Kind == "Stop" then
		cancelMovement(controller)
	end
end

local function moveZigzagStep(
	brainrot: Model,
	controller: Controller,
	direction: Vector3,
	moveSpeed: number,
	dt: number
): boolean
	local flat = flatDirection(direction)
	if flat == nil or dt <= 0 or moveSpeed <= 0 then
		return true
	end
	local pivot = brainrot:GetPivot()
	local current = Vector3.new(pivot.Position.X, controller.Origin.Y, pivot.Position.Z)
	local nextPosition = current + flat * moveSpeed * dt
	if not isSafeMovementStep(brainrot, controller, current, nextPosition) then
		return false
	end
	if
		controller.RouteMotor
		and not RouteMotor.RecordExcursion(controller.RouteMotor, current, nextPosition)
	then
		return false
	end
	brainrot:PivotTo(CFrame.lookAt(nextPosition, nextPosition + flat, Vector3.yAxis))
	return true
end

local function logZigzagDecision(
	brainrot: Model,
	controller: Controller,
	result: Zigzag.Decision,
	position: Vector3,
	candidates: { ThreatCandidate },
	now: number
)
	if result.Engaged then
		local plan = controller.Zigzag.cyclePlan
		log:Info(
			"[Zigzag] Engaged runtimeId=%s speciesId=%s threatUserId=%s effectiveAngle=%.2f normalSpeed=%.2f distance=%.2f",
			runtimeId(brainrot),
			tostring(brainrot:GetAttribute("BrainrotId")),
			tostring(controller.Zigzag.lockedThreatUserId),
			if plan then math.deg(plan.EffectiveAngleRadians) else 0,
			if plan then plan.BaseSpeed else controller.NormalSpeed,
			if result.AcquiredUserId
				then sprinterThreatDistance(result.AcquiredUserId, position, candidates)
				else -1
		)
	end
	if result.ReleaseReason ~= nil then
		log:Info(
			"[Zigzag] Released runtimeId=%s reason=%s",
			runtimeId(brainrot),
			result.ReleaseReason
		)
	end
	if result.CourseChanged and result.CourseChangeReason ~= "Stall" then
		log:Info(
			"[Zigzag] CourseChanged runtimeId=%s reason=%s",
			runtimeId(brainrot),
			result.CourseChangeReason or "CycleBoundary"
		)
	end
	if
		result.RouteBlocked == true
		and (
			controller.LastBlockedLogAt == nil
			or now - controller.LastBlockedLogAt >= BLOCKED_LOG_INTERVAL
		)
	then
		controller.LastBlockedLogAt = now
		log:Debug(
			"[Zigzag] Blocked runtimeId=%s retryAt=%.3f",
			runtimeId(brainrot),
			controller.Zigzag.nextBlockedRetryAt
		)
	end
end

local function advanceZigzag(
	brainrot: Model,
	controller: Controller,
	startAt: number,
	endAt: number,
	fallbackDirection: Vector3,
	moveSpeed: number
): boolean
	local cursor = startAt
	while cursor < endAt - DIRECTION_EPSILON do
		local segmentEnd = math.min(endAt, cursor + ZIGZAG_MOVEMENT_SUBSTEP_SECONDS)
		local boundary = Zigzag.NextMovementBoundary(controller.Zigzag, cursor)
		if boundary ~= nil and boundary > cursor + DIRECTION_EPSILON then
			segmentEnd = math.min(segmentEnd, boundary)
		end
		local sampleAt = (cursor + segmentEnd) * 0.5
		local direction = select(1, Zigzag.SampleDirection(controller.Zigzag, sampleAt))
			or fallbackDirection
		if not moveZigzagStep(brainrot, controller, direction, moveSpeed, segmentEnd - cursor) then
			return false
		end
		cursor = segmentEnd
	end
	return true
end

local function advanceStraightZigzag(
	brainrot: Model,
	controller: Controller,
	direction: Vector3,
	moveSpeed: number,
	duration: number
): boolean
	local remaining = duration
	while remaining > DIRECTION_EPSILON do
		local stepDuration = math.min(remaining, ZIGZAG_MOVEMENT_SUBSTEP_SECONDS)
		if not moveZigzagStep(brainrot, controller, direction, moveSpeed, stepDuration) then
			return false
		end
		remaining -= stepDuration
	end
	return true
end

local function updateZigzag(
	brainrot: Model,
	controller: Controller,
	now: number,
	dt: number,
	sensing: boolean,
	candidates: { ThreatCandidate }
)
	local pivot = brainrot:GetPivot()
	local position = pivot.Position
	local previousMode = controller.Zigzag.Mode
	local previousCourse = controller.Zigzag.courseForward
	local previousCycleStartAt = controller.Zigzag.cycleStartAt
	local previousCyclePlan = controller.Zigzag.cyclePlan
	local result = Zigzag.Step(controller.Zigzag, {
		Authorized = controller.BehaviourId == "Zigzag",
		LifecycleEligible = lifecycleEligible(brainrot, controller),
		Position = position,
		Forward = pivot.LookVector,
		ResolvedSpeed = controller.NormalSpeed,
		Candidates = candidates,
		Sensing = sensing,
		CanSeeCandidate = function(candidate)
			return canSeeCandidate(brainrot, candidate)
		end,
		ResolveSafeCourse = function(current, threat, preferred, distance)
			return resolveZigzagCourse(brainrot, controller, current, threat, preferred, distance)
		end,
		IsCourseSafe = function(current, direction, distance)
			return isZigzagCourseSafe(brainrot, controller, current, direction, distance)
		end,
	}, now, dt, BrainrotBehaviours.Zigzag)
	logZigzagDecision(brainrot, controller, result, position, candidates, now)

	if
		result.AcquiredUserId ~= nil
		or result.ReleaseReason ~= nil
		or result.Engaged
		or result.CourseChanged
	then
		controller.RoamGoal = nil
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
		controller.NextRoamAt = now
	end
	if result.Kind == "Roam" then
		updateRoaming(brainrot, controller, now, dt)
	elseif result.Kind == "Escape" and result.Direction ~= nil then
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = "ZigzagEscape"
		local boundedDt = math.min(math.max(dt, 0), MAX_MOVEMENT_STEP_SECONDS)
		if
			result.CourseChangeReason == "CycleBoundary"
			and previousCourse ~= nil
			and previousCycleStartAt ~= nil
			and previousCyclePlan ~= nil
			and boundedDt > 0
		then
			local frameStart = now - boundedDt
			local completedCycles = math.floor(
				math.max(0, now - previousCycleStartAt) / previousCyclePlan.CycleDurationSeconds
			)
			local boundaryAt = previousCycleStartAt
				+ completedCycles * previousCyclePlan.CycleDurationSeconds
			local straightDuration = math.max(0, math.min(now, boundaryAt) - frameStart)
			if
				straightDuration > 0
				and not advanceStraightZigzag(
					brainrot,
					controller,
					previousCourse,
					previousCyclePlan.BaseSpeed,
					straightDuration
				)
			then
				Zigzag.OnMovementBlocked(controller.Zigzag, now, BrainrotBehaviours.Zigzag)
			end
		end
		-- Transition frames begin from the actual position. Historical movement is
		-- never replayed through a newly selected course or after a stalled frame.
		if
			result.Engaged
			or result.CourseChanged
			or (previousMode == "Reorienting" and controller.Zigzag.Mode == "Pattern")
		then
			boundedDt = 0
		end
		if boundedDt > 0 then
			local advanced = advanceZigzag(
				brainrot,
				controller,
				now - boundedDt,
				now,
				result.Direction,
				result.RequestedSpeed or controller.NormalSpeed
			)
			if not advanced then
				Zigzag.OnMovementBlocked(controller.Zigzag, now, BrainrotBehaviours.Zigzag)
				controller.ActiveGoal = nil
				controller.ActiveGoalKind = nil
				if
					controller.LastBlockedLogAt == nil
					or now - controller.LastBlockedLogAt >= BLOCKED_LOG_INTERVAL
				then
					controller.LastBlockedLogAt = now
					log:Debug(
						"[Zigzag] Blocked runtimeId=%s retryAt=%.3f",
						runtimeId(brainrot),
						controller.Zigzag.nextBlockedRetryAt
					)
				end
			end
		end
	elseif result.Kind == "Hold" then
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
	elseif result.Kind == "Stop" then
		cancelMovement(controller)
	end
end

local function logLegendaryDecision(
	brainrot: Model,
	controller: Controller,
	result: LegendaryPursuit.Decision,
	now: number
)
	local state = controller.LegendaryPursuit
	if result.Started then
		local plan = state.plan
		log:Info(
			"[LegendaryPursuit] Started runtimeId=%s speciesId=%s threatUserId=%s plannedEndAt=%.3f baseSpeed=%.2f peakSpeed=%.2f openingSpeed=%.2f",
			runtimeId(brainrot),
			tostring(brainrot:GetAttribute("BrainrotId")),
			tostring(state.lockedThreatUserId),
			state.plannedEndAt or now,
			if plan then plan.BaseSpeed else controller.NormalSpeed,
			if plan then plan.MotionProfile.PeakSpeed else controller.NormalSpeed,
			if plan then plan.OpeningSpeed else controller.NormalSpeed
		)
	end
	if result.StageChanged and state.active then
		log:Info(
			"[LegendaryPursuit] StageChanged runtimeId=%s stage=%s startsAt=%.3f endsAt=%s",
			runtimeId(brainrot),
			state.Stage,
			state.stageStartedAt or now,
			tostring(state.stageEndsAt)
		)
	end
	if result.EndedReason ~= nil then
		log:Info(
			"[LegendaryPursuit] Ended runtimeId=%s reason=%s",
			runtimeId(brainrot),
			result.EndedReason
		)
	end
end

local function updateLegendaryPursuit(
	brainrot: Model,
	controller: Controller,
	now: number,
	dt: number,
	sensing: boolean,
	candidates: { ThreatCandidate }
)
	local pivot = brainrot:GetPivot()
	local position = pivot.Position
	local result = LegendaryPursuit.Step(
		controller.LegendaryPursuit,
		{
			Authorized = controller.BehaviourId == "LegendaryPursuit",
			LifecycleEligible = lifecycleEligible(brainrot, controller),
			RuntimeId = runtimeId(brainrot),
			Position = position,
			Forward = pivot.LookVector,
			ResolvedSpeed = controller.NormalSpeed,
			Candidates = candidates,
			Sensing = sensing,
			CanSeeCandidate = function(candidate)
				return canSeeCandidate(brainrot, candidate)
			end,
			ResolveBurstCourse = function(current, threat, preferred, distance, minimumDistance)
				local goal = resolveSprinterEscapeGoal(
					brainrot,
					controller,
					current,
					threat,
					preferred,
					distance,
					minimumDistance
				)
				return if goal then flatDirection(goal - current) else nil
			end,
			ResolveZigzagCourse = function(current, threat, preferred, distance)
				return resolveZigzagCourse(
					brainrot,
					controller,
					current,
					threat,
					preferred,
					distance
				)
			end,
		},
		now,
		dt,
		BrainrotBehaviours.LegendaryPursuit,
		BrainrotBehaviours.Sprinter,
		BrainrotBehaviours.Zigzag
	)
	logLegendaryDecision(brainrot, controller, result, now)

	if result.Started or result.StageChanged or result.EndedReason ~= nil then
		controller.RoamGoal = nil
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
		controller.NextRoamAt = now
	end
	if result.Kind == "Roam" then
		updateRoaming(brainrot, controller, now, dt)
	elseif result.Kind == "Escape" and result.Direction ~= nil then
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = "LegendaryPursuit"
		local boundedDt = math.min(math.max(dt, 0), MAX_MOVEMENT_STEP_SECONDS)
		-- A stage transition begins at the real current position. Never replay the
		-- previous stage's movement using the new speed or direction.
		if result.Started or result.StageChanged then
			boundedDt = 0
		end
		local cursor = now - boundedDt
		local blocked = false
		while cursor < now - DIRECTION_EPSILON do
			local segmentEnd = math.min(now, cursor + ZIGZAG_MOVEMENT_SUBSTEP_SECONDS)
			local sampleAt = (cursor + segmentEnd) * 0.5
			local direction, speed =
				LegendaryPursuit.SampleCurrentMotion(controller.LegendaryPursuit, sampleAt)
			if
				direction == nil
				or speed == nil
				or not moveZigzagStep(brainrot, controller, direction, speed, segmentEnd - cursor)
			then
				blocked = true
				break
			end
			cursor = segmentEnd
		end
		if blocked then
			local previousStage = controller.LegendaryPursuit.Stage
			if
				LegendaryPursuit.OnMovementBlocked(
					controller.LegendaryPursuit,
					now,
					BrainrotBehaviours.LegendaryPursuit
				)
			then
				controller.ActiveGoalKind = nil
				log:Info(
					"[LegendaryPursuit] StageChanged runtimeId=%s stage=%s startsAt=%.3f endsAt=%s reason=Blocked previousStage=%s",
					runtimeId(brainrot),
					controller.LegendaryPursuit.Stage,
					controller.LegendaryPursuit.stageStartedAt or now,
					tostring(controller.LegendaryPursuit.stageEndsAt),
					previousStage
				)
			end
		end
	elseif result.Kind == "Hold" then
		controller.ActiveGoal = nil
		controller.ActiveGoalKind = nil
	elseif result.Kind == "Stop" then
		cancelMovement(controller)
	end
end

local function updateCamouflage(
	brainrot: Model,
	controller: Controller,
	movementNow: number,
	scheduleNow: number,
	dt: number,
	sensing: boolean,
	candidates: { ThreatCandidate }
)
	local position = brainrot:GetPivot().Position
	local result = Camouflage.Step(controller.Camouflage, {
		Authorized = controller.BehaviourId == "Camouflage",
		LifecycleEligible = lifecycleEligible(brainrot, controller),
		Position = position,
		Candidates = candidates,
		Sensing = sensing,
		CanSeeCandidate = function(candidate)
			return canSeeCandidate(brainrot, candidate)
		end,
	}, scheduleNow, BrainrotBehaviours.Camouflage)
	if result.Activated then
		publishCamouflage(brainrot, controller)
		log:Info(
			"[Camouflage] Activated runtimeId=%s speciesId=%s threatUserId=%s distance=%.2f cycleStart=%.3f",
			runtimeId(brainrot),
			tostring(brainrot:GetAttribute("BrainrotId")),
			tostring(result.ActivatingUserId),
			result.ActivatingDistance or -1,
			scheduleNow
		)
	elseif result.Deactivated then
		publishCamouflage(brainrot, controller)
		log:Info(
			"[Camouflage] Released runtimeId=%s reason=%s",
			runtimeId(brainrot),
			result.Reason or "Disengaged"
		)
	end
	-- Camouflage is presentation/assistance only. The one existing motor retains
	-- normal roaming ownership and the normal resolved speed.
	updateRoaming(brainrot, controller, movementNow, dt)
end

local function updateDecoySplit(
	brainrot: Model,
	controller: Controller,
	movementNow: number,
	scheduleNow: number,
	dt: number,
	sensing: boolean,
	candidates: { ThreatCandidate }
)
	local pivot = brainrot:GetPivot()
	local position = pivot.Position
	local courseDirection = if controller.ActiveGoal
		then flatDirection(controller.ActiveGoal - position)
		else flatDirection(pivot.LookVector)
	DecoySplit.Step(brainrot, controller.DecoySplit, {
		Authorized = controller.BehaviourId == "DecoySplit",
		LifecycleEligible = lifecycleEligible(brainrot, controller),
		RuntimeId = runtimeId(brainrot),
		BrainrotId = tostring(brainrot:GetAttribute("BrainrotId")),
		Position = position,
		Forward = pivot.LookVector,
		CourseDirection = courseDirection,
		Candidates = candidates,
		Sensing = sensing,
		CanSeeCandidate = function(candidate)
			return canSeeCandidate(brainrot, candidate)
		end,
		GetHitEnvelope = function()
			local localFrame, visualSize = BrainrotVisualScale.GetVisualBounds(brainrot)
			if localFrame == nil or visualSize == nil then
				return nil, nil
			end
			return brainrot:GetPivot() * localFrame,
				Vector3.new(
					math.max(visualSize.X * 2.5, 12),
					math.max(visualSize.Y * 2.5, 12),
					math.max(visualSize.Z * 2.5, 12)
				)
		end,
		ResolvePlacement = function(desired, localFrame, size)
			return resolveDecoyPose(brainrot, controller, desired, localFrame, size, nil)
		end,
		ResolveFollowPose = function(record, desired)
			return resolveDecoyPose(
				brainrot,
				controller,
				desired,
				record.HitProxyLocalFrame,
				record.HitProxySize,
				record.Model
			)
		end,
		LaneChoice = math.random(-1, 1),
	}, scheduleNow, dt, BrainrotBehaviours.DecoySplit)
	-- The real individual remains owned by the existing normal roaming motor.
	updateRoaming(brainrot, controller, movementNow, dt)
end

local function reconcileTerritoryPresence(
	brainrot: Model,
	controller: Controller,
	inside: boolean,
	now: number
)
	if not inside and not controller.RecoveringTerritory then
		controller.RecoveringTerritory = true
		controller.TerritoryRecoveryGoal = nil
		controller.NextTerritoryRecoveryAt = now
		interruptBehaviours(brainrot, controller, "TerritoryBoundary")
		log:Debug(
			"[NaturalTerritory] Recovering out-of-bounds runtimeId=%s regionId=%s",
			runtimeId(brainrot),
			controller.TerritoryRegionId
		)
	elseif inside and not controller.ReturningToRegion then
		-- Camp return must still reach updateTerritoryRecovery, which owns clearing
		-- its return identity/attribute on arrival. A sensing frame must not bypass it.
		controller.RecoveringTerritory = false
		controller.TerritoryRecoveryGoal = nil
		controller.NextTerritoryRecoveryAt = 0
	end
end

-- Notice beat trigger: a player crossing the notice radius in front of a calm creature.
-- Approaching from behind skips it, so a creature can be crept up on.
local function updateNotice(
	brainrot: Model,
	controller: Controller,
	position: Vector3,
	candidates: { ThreatCandidate },
	now: number
)
	local radius = noticeRadius(controller.BehaviourId)
	local nearest: ThreatCandidate? = nil
	local nearestDistance = math.huge
	for _, candidate in candidates do
		local offset = candidate.Position - position
		local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = candidate, distance
		end
	end
	if nearest == nil or nearestDistance > radius + MotionTuning.NoticeRearmMargin then
		controller.NoticeArmed = true
		return
	end
	if
		nearestDistance > radius
		or not controller.NoticeArmed
		or now < controller.NoticeCooldownUntil
		or controller.WasLocked
	then
		return
	end
	controller.NoticeArmed = false
	controller.NoticeCooldownUntil = now + MotionTuning.NoticeCooldownSeconds
	local toPlayer = flatDirection(nearest.Position - position)
	local look = flatDirection(brainrot:GetPivot().LookVector)
	if toPlayer == nil or look == nil or look:Dot(toPlayer) < 0 then
		return
	end
	controller.NoticeFace = toPlayer
	controller.NoticeUntil = now + MotionTuning.NoticeSeconds
end

local function updateMotion(
	brainrot: Model,
	controller: Controller,
	before: Vector3,
	elapsed: number,
	now: number
)
	local after = brainrot:GetPivot().Position
	local speed = if elapsed > 1e-3
		then Vector3.new(after.X - before.X, 0, after.Z - before.Z).Magnitude / elapsed
		else 0
	local locked = controller.Reaction.lockedThreatUserId ~= nil
		or controller.Sprint.lockedThreatUserId ~= nil
		or controller.Zigzag.lockedThreatUserId ~= nil
		or controller.LegendaryPursuit.active
	if locked and not controller.WasLocked then
		-- The "!" telegraph. The behaviour itself is not delayed or changed.
		controller.AlertUntil = now + MotionTuning.AlertSeconds
	end
	controller.WasLocked = locked
	local motor = controller.RouteMotor
	if now < controller.AlertUntil then
		controller.StillSince = nil
		setMotion(brainrot, controller, "Alert")
	elseif controller.NoticeFace ~= nil then
		-- Stopped to look at the player: idle at once, no debounce.
		setMotion(brainrot, controller, "Idle")
	elseif speed > MotionTuning.MovingSpeed then
		controller.StillSince = nil
		local fleeing = controller.ActiveGoalKind == "Escape"
			or controller.ActiveGoalKind == "SprinterEscape"
			or controller.Zigzag.Mode ~= "Inactive"
			or controller.LegendaryPursuit.active
		setMotion(brainrot, controller, if fleeing then "Run" else "Walk")
	else
		local since = controller.StillSince or now
		controller.StillSince = since
		if motor and motor.PauseKind == "Signature" then
			setMotion(brainrot, controller, "Signature")
		elseif
			controller.Motion == nil
			or now - since
				>= (if locked
					then MotionTuning.LockedIdleDebounceSeconds
					else MotionTuning.IdleDebounceSeconds)
		then
			-- A fleeing creature that turns on the spot keeps its Run/Alert state.
			setMotion(brainrot, controller, "Idle")
		end
	end
end

local function updateAll(deltaTime: number)
	local now = os.clock()
	local scheduleNow = Workspace:GetServerTimeNow()
	local naturalMotion = CharacterMotion.BrainrotsEnabled()
	RouteMotor.Pump(os.clock())
	sensingElapsed += math.max(deltaTime, 0)
	local sensingInterval = math.min(
		0.1,
		BrainrotBehaviours.ReactiveRunner.SenseIntervalSeconds,
		BrainrotBehaviours.Sprinter.SenseIntervalSeconds,
		BrainrotBehaviours.Zigzag.SenseIntervalSeconds,
		BrainrotBehaviours.Camouflage.SenseIntervalSeconds,
		BrainrotBehaviours.DecoySplit.SenseIntervalSeconds,
		BrainrotBehaviours.LegendaryPursuit.SenseIntervalSeconds
	)
	local sensing = sensingElapsed >= sensingInterval
	local candidates = latestThreatCandidates
	if sensing then
		-- Evaluate current time once after a stalled frame; never replay a scan backlog.
		sensingElapsed = 0
		candidates = DevelopmentBrainrotRoaming.BuildThreatSnapshot()
		latestThreatCandidates = candidates
	end
	for itemId, nextBurstAt in sprinterCooldownByItemId do
		if now >= nextBurstAt then
			sprinterCooldownByItemId[itemId] = nil
		end
	end
	for itemId, nextAllowedAt in decoyCooldownByItemId do
		if scheduleNow >= nextAllowedAt then
			decoyCooldownByItemId[itemId] = nil
		end
	end
	for itemId, nextAllowedAt in legendaryCooldownByItemId do
		if now >= nextAllowedAt then
			legendaryCooldownByItemId[itemId] = nil
		end
	end
	for brainrot, controller in controllers do
		controller.AccumulatedDelta += math.max(deltaTime, 0)
		if brainrot:GetAttribute("Phase12InteractionReady") == false then
			controller.AccumulatedDelta = 0
			continue
		end
		if not lifecycleEligible(brainrot, controller) then
			controller.AccumulatedDelta = 0
			if not controller.Paused then
				controller.Paused = true
				interruptBehaviours(brainrot, controller, "Lifecycle")
			end
			if naturalMotion and brainrot:GetAttribute("Captured") == true then
				setMotion(brainrot, controller, "Sleep")
			end
		else
			local position = brainrot:GetPivot().Position
			local observed = interestResolver == nil
				or interestResolver(controller.TerritoryRegionId, position)
			local nearby = false
			for _, candidate in candidates do
				if (candidate.Position - position).Magnitude <= 160 then
					nearby = true
					break
				end
			end
			local active = controller.Reaction.lockedThreatUserId ~= nil
				or controller.Sprint.lockedThreatUserId ~= nil
				or controller.Zigzag.Mode ~= "Inactive"
				or controller.LegendaryPursuit.active
			local interval = if observed or nearby or active then 0.1 else 0.5
			if controller.RouteMotor and controller.AccumulatedDelta + 1e-6 < interval then
				continue
			end
			local elapsed = controller.AccumulatedDelta
			controller.AccumulatedDelta = 0
			-- Per-owner ticks can be out of phase with the global snapshot tick.
			-- Use the most recent <=0.1s snapshot at every scheduled route step;
			-- otherwise a fixed phase offset could suppress reactive sensing forever.
			local controllerSensing = sensing or controller.RouteMotor ~= nil
			if
				controller.RouteMotor
				and controller.RouteMotor.Phase == "Entering"
				and RouteMotor.CheckArrival(controller.RouteMotor, scheduleNow)
			then
				continue
			end
			-- Segment validation catches ordinary movement immediately. This lower-rate
			-- check detects an externally displaced natural owner without adding a
			-- second spatial-query pass for every entity on every frame.
			if controller.TerritoryRegionId ~= nil and controllerSensing then
				local inside = isInsideTerritory(brainrot, controller, brainrot:GetPivot().Position)
				reconcileTerritoryPresence(brainrot, controller, inside, now)
			end
			if naturalMotion and controllerSensing and not controller.RecoveringTerritory then
				updateNotice(brainrot, controller, position, candidates, now)
			end
			if controller.RecoveringTerritory then
				-- Keep the existing guarded recovery owner when a reactive move has
				-- left ordinary hunting space. An in-region wander leg cannot own it.
				updateTerritoryRecovery(brainrot, controller, now, elapsed)
			else
				if controller.BehaviourId == "ReactiveRunner" then
					updateReactiveRunner(
						brainrot,
						controller,
						now,
						elapsed,
						controllerSensing,
						candidates
					)
				elseif controller.BehaviourId == "Sprinter" then
					updateSprinter(
						brainrot,
						controller,
						now,
						elapsed,
						controllerSensing,
						candidates
					)
				elseif controller.BehaviourId == "Zigzag" then
					updateZigzag(brainrot, controller, now, elapsed, controllerSensing, candidates)
				elseif controller.BehaviourId == "Camouflage" then
					updateCamouflage(
						brainrot,
						controller,
						now,
						scheduleNow,
						elapsed,
						controllerSensing,
						candidates
					)
				elseif controller.BehaviourId == "DecoySplit" then
					updateDecoySplit(
						brainrot,
						controller,
						now,
						scheduleNow,
						elapsed,
						controllerSensing,
						candidates
					)
				elseif controller.BehaviourId == "LegendaryPursuit" then
					updateLegendaryPursuit(
						brainrot,
						controller,
						now,
						elapsed,
						controllerSensing,
						candidates
					)
				else
					updateRoaming(brainrot, controller, now, elapsed)
				end
			end
			if naturalMotion and controllers[brainrot] == controller then
				updateMotion(brainrot, controller, position, elapsed, now)
			end
		end
	end
end

function DevelopmentBrainrotRoaming.Pause(brainrot: Model, reason: string?): boolean
	local controller = controllers[brainrot]
	if controller == nil then
		return false
	end
	if not controller.Paused then
		controller.Paused = true
		interruptBehaviours(brainrot, controller, reason or "Paused")
	end
	return true
end

function DevelopmentBrainrotRoaming.Resume(brainrot: Model, resumePosition: Vector3?): boolean
	local controller = controllers[brainrot]
	if
		controller == nil
		or not isInWorld(brainrot)
		or brainrot:GetAttribute("Captured") == true
	then
		return false
	end
	if resumePosition ~= nil and not finitePosition(resumePosition) then
		return false
	end
	-- Repeated resume of a running model must not restart or multiply its task.
	if controller.Paused then
		controller.AccumulatedDelta = 0
		controller.Origin = resumePosition or controller.Origin
		controller.Paused = false
		ReactiveRunner.Reset(controller.Reaction)
		Sprinter.Interrupt(controller.Sprint, os.clock(), "Resume")
		Zigzag.Interrupt(controller.Zigzag, os.clock(), "Resume")
		if Camouflage.Interrupt(controller.Camouflage, Workspace:GetServerTimeNow(), "Resume") then
			publishCamouflage(brainrot, controller)
		end
		DecoySplit.Interrupt(
			brainrot,
			controller.DecoySplit,
			Workspace:GetServerTimeNow(),
			"Resume"
		)
		LegendaryPursuit.Interrupt(
			controller.LegendaryPursuit,
			os.clock(),
			"Resume",
			BrainrotBehaviours.LegendaryPursuit
		)
		cancelMovement(controller)
	end
	startMovement(brainrot, controller)
	return true
end

function DevelopmentBrainrotRoaming.Unregister(brainrot: Model, reason: string?): boolean
	local controller = controllers[brainrot]
	if controller == nil then
		return false
	end
	interruptBehaviours(brainrot, controller, reason or "Removed")
	if controller.RouteMotor then
		RouteMotor.Destroy(controller.RouteMotor)
	end
	controllers[brainrot] = nil
	for _, connection in controller.Connections do
		connection:Disconnect()
	end
	return true
end

-- Server-side counterpart to the existing presentation eligibility rule. This
-- is consulted only when validating an explicit assist-lock shot; ordinary
-- direct projectile intersections remain valid while Camouflage is concealed.
function DevelopmentBrainrotRoaming.IsAimAssistEligible(brainrot: Model, nowValue: number?): boolean
	local controller = controllers[brainrot]
	if controller == nil or controller.BehaviourId ~= "Camouflage" then
		return true
	end
	local snapshot = Camouflage.GetSnapshot(controller.Camouflage, runtimeId(brainrot))
	local sample = CamouflageTiming.Sample(
		snapshot,
		nowValue or Workspace:GetServerTimeNow(),
		BrainrotBehaviours.Camouflage
	)
	return sample.fullReveal
end

local function resolveBehaviourId(brainrot: Model): string
	local definition = BrainrotCatalog.Get(brainrot:GetAttribute("BrainrotId"))
	if definition ~= nil then
		if definition.behaviourId == "ReactiveRunner" then
			return "ReactiveRunner"
		elseif definition.behaviourId == "Sprinter" then
			return "Sprinter"
		elseif definition.behaviourId == "Zigzag" then
			return "Zigzag"
		elseif definition.behaviourId == "Camouflage" then
			return "Camouflage"
		elseif definition.behaviourId == "DecoySplit" then
			return "DecoySplit"
		elseif definition.behaviourId == "LegendaryPursuit" then
			return "LegendaryPursuit"
		end
	end
	-- The Phase 6A-2 pilot override remains baseline-only for unfinished profiles.
	return "Wanderer"
end

-- Only the world owner registers living representations. Detached staging and
-- stripped cargo/display clones never enter this controller registry.
function DevelopmentBrainrotRoaming.Register(
	brainrot: Model,
	origin: Vector3?,
	spawnRegionId: string?,
	territoryRegionId: string?,
	returnRegionId: string?
): boolean
	if not isInWorld(brainrot) then
		return false
	end
	if controllers[brainrot] ~= nil then
		return true
	end
	local centre = origin or brainrot:GetPivot().Position
	if not finitePosition(centre) then
		return false
	end
	local now = os.clock()
	local itemId = brainrot:GetAttribute("ItemId")
	local preservedNextBurstAt = if typeof(itemId) == "string"
		then sprinterCooldownByItemId[itemId]
		else nil
	local preservedDecoyNextAllowedAt = if typeof(itemId) == "string"
		then decoyCooldownByItemId[itemId]
		else nil
	local preservedLegendaryNextAllowedAt = if typeof(itemId) == "string"
		then legendaryCooldownByItemId[itemId]
		else nil
	local scheduleNow = Workspace:GetServerTimeNow()
	local controller: Controller = {
		RouteMotor = nil,
		NormalSpeed = NORMAL_MOVE_SPEED,
		AccumulatedDelta = 0,
		Origin = centre,
		RouteParams = routeParams(brainrot),
		Paused = brainrot:GetAttribute("Captured") == true,
		Generation = 0,
		Connections = {},
		BehaviourId = resolveBehaviourId(brainrot),
		SpawnRegionId = spawnRegionId,
		TerritoryRegionId = returnRegionId or territoryRegionId,
		ReturnRegionId = returnRegionId,
		ReturningToRegion = returnRegionId ~= nil,
		CampReturnAttempts = 0,
		RecoveringTerritory = returnRegionId ~= nil,
		TerritoryRecoveryGoal = nil,
		NextTerritoryRecoveryAt = 0,
		Reaction = ReactiveRunner.CreateState(now),
		Sprint = Sprinter.CreateState(now, preservedNextBurstAt),
		Zigzag = Zigzag.CreateState(now),
		Camouflage = Camouflage.CreateState(scheduleNow),
		DecoySplit = DecoySplit.CreateState(scheduleNow, preservedDecoyNextAllowedAt),
		LegendaryPursuit = LegendaryPursuit.CreateState(now, preservedLegendaryNextAllowedAt),
		RoamGoal = nil,
		NextRoamAt = 0,
		ActiveGoal = nil,
		ActiveGoalKind = nil,
		TurnFromYaw = nil,
		TurnToYaw = nil,
		TurnStartedAt = nil,
		LastBlockedLogAt = nil,
		Motion = nil,
		StillSince = nil,
		WasLocked = false,
		AlertUntil = 0,
		NoticeUntil = 0,
		NoticeFace = nil,
		NoticeArmed = true,
		NoticeCooldownUntil = 0,
	}
	controllers[brainrot] = controller
	if CharacterMotion.BrainrotsEnabled() then
		brainrot:SetAttribute("MotionSeed", CharacterMotion.SeedFor(runtimeId(brainrot)))
	end
	if returnRegionId ~= nil then
		brainrot:SetAttribute("CampReturnRegionId", returnRegionId)
		log:Info(
			"CampReturnStarted runtimeId=%s destination=%s position=%s",
			runtimeId(brainrot),
			returnRegionId,
			tostring(centre)
		)
	end
	publishCamouflage(brainrot, controller)
	DecoySplit.Publish(brainrot, controller.DecoySplit)
	table.insert(
		controller.Connections,
		brainrot.Destroying:Connect(function()
			DevelopmentBrainrotRoaming.Unregister(brainrot, "Destroyed")
		end)
	)
	table.insert(
		controller.Connections,
		brainrot.AncestryChanged:Connect(function()
			if not isInWorld(brainrot) then
				DevelopmentBrainrotRoaming.Unregister(brainrot, "Removed")
			end
		end)
	)
	-- Compatibility with the old capture writer until Phase 1B replaces it.
	table.insert(
		controller.Connections,
		brainrot:GetAttributeChangedSignal("Captured"):Connect(function()
			if brainrot:GetAttribute("Captured") == true then
				DevelopmentBrainrotRoaming.Pause(brainrot, "Sleeping")
			else
				DevelopmentBrainrotRoaming.Resume(brainrot, brainrot:GetPivot().Position)
			end
		end)
	)
	startMovement(brainrot, controller)
	return true
end

-- The world owner attaches the persisted state callbacks after its transfer commits.
function DevelopmentBrainrotRoaming.ConfigureRoute(
	brainrot: Model,
	route: any,
	context: any
): (boolean, string?)
	local controller = controllers[brainrot]
	if not controller then
		return false, "MODEL_NOT_REGISTERED"
	end
	local definition = BrainrotCatalog.Get(brainrot:GetAttribute("BrainrotId"))
	local motor, reason = RouteMotor.Create(brainrot, route, context)
	if not motor then
		return false, reason
	end
	controller.RouteMotor = motor
	motor.SignatureEvery = if definition and SIGNATURE_OFTEN_TIERS[definition.tier]
		then MotionTuning.SignatureEveryLegendary
		else nil
	controller.NormalSpeed = RouteRules.Speed(if definition then definition.tier else "Common")
	controller.TerritoryRegionId = route.RegionId
	controller.ReturnRegionId = nil
	controller.ReturningToRegion = false
	controller.RecoveringTerritory = false
	controller.AccumulatedDelta = 0
	brainrot:SetAttribute("CampReturnRegionId", nil)
	return true, nil
end

function DevelopmentBrainrotRoaming.ConfigureInterest(resolver: (string?, Vector3) -> boolean)
	interestResolver = resolver
end

function DevelopmentBrainrotRoaming.GetPresentationSnapshot(regionId: string?): { any }
	local rows = {}
	for model, controller in controllers do
		if regionId == nil or controller.TerritoryRegionId == regionId then
			local motor = controller.RouteMotor
			local state = if motor then motor.Context.GetState() else nil
			local route = if state then state.Route else nil
			table.insert(rows, {
				ItemId = model:GetAttribute("ItemId"),
				speciesId = model:GetAttribute("BrainrotId"),
				mutationId = if state
					then state.MutationId
					else model:GetAttribute("BrainrotMutationId") or "None",
				regionId = controller.TerritoryRegionId,
				cframe = model:GetPivot(),
				HP = if state then state.RemainingHp else model:GetAttribute("RemainingHp"),
				MaxHP = if state then state.MaxHp else model:GetAttribute("MaxHp"),
				state = if controller.Paused
					then "Sleeping"
					else if motor and motor.Phase then motor.Phase else "Wild",
				deadline = if controller.Paused
					then model:GetAttribute("BrainrotSleepUntil")
					else if route then route.GraceUntil else nil,
				sequence = if motor then motor.Sequence else controller.Generation,
				generation = if route then route.Generation else controller.Generation,
				routeProgress = if route then route.Progress else nil,
			})
		end
	end
	table.sort(rows, function(a, b)
		return tostring(a.ItemId) < tostring(b.ItemId)
	end)
	return rows
end

function DevelopmentBrainrotRoaming.GetDiagnostics()
	local registered, running, paused, reactive, locked, sprinters, bursts, recoveries =
		0, 0, 0, 0, 0, 0, 0, 0
	local territoryBound, recoveringTerritory = 0, 0
	local zigzags, zigzagPatterns, zigzagBlocked = 0, 0, 0
	local camouflages, activeCamouflages = 0, 0
	local decoySplits, activeDecoySplits = 0, 0
	local legendaryPursuits, activeLegendaryPursuits = 0, 0
	for _, controller in controllers do
		registered += 1
		territoryBound += if controller.TerritoryRegionId ~= nil then 1 else 0
		recoveringTerritory += if controller.RecoveringTerritory then 1 else 0
		running += if started and not controller.Paused then 1 else 0
		paused += if controller.Paused then 1 else 0
		reactive += if controller.BehaviourId == "ReactiveRunner" then 1 else 0
		locked += if controller.Reaction.lockedThreatUserId ~= nil then 1 else 0
		sprinters += if controller.BehaviourId == "Sprinter" then 1 else 0
		bursts += if controller.Sprint.Phase == "Burst" then 1 else 0
		recoveries += if controller.Sprint.Phase == "Recovery" then 1 else 0
		zigzags += if controller.BehaviourId == "Zigzag" then 1 else 0
		zigzagPatterns += if controller.Zigzag.Mode == "Pattern" then 1 else 0
		zigzagBlocked += if controller.Zigzag.Mode == "Blocked" then 1 else 0
		camouflages += if controller.BehaviourId == "Camouflage" then 1 else 0
		activeCamouflages += if controller.Camouflage.active then 1 else 0
		decoySplits += if controller.BehaviourId == "DecoySplit" then 1 else 0
		activeDecoySplits += if controller.DecoySplit.active then 1 else 0
		legendaryPursuits += if controller.BehaviourId == "LegendaryPursuit" then 1 else 0
		activeLegendaryPursuits += if controller.LegendaryPursuit.active then 1 else 0
	end
	local decoyDiagnostics = DecoySplit.GetDiagnostics()
	local legendaryDiagnostics = LegendaryPursuit.GetDiagnostics()
	return table.freeze({
		Registered = registered,
		Running = running,
		Paused = paused,
		TerritoryBound = territoryBound,
		RecoveringTerritory = recoveringTerritory,
		Reactive = reactive,
		LockedThreats = locked,
		Sprinters = sprinters,
		SprinterBursts = bursts,
		SprinterRecoveries = recoveries,
		Zigzags = zigzags,
		ZigzagPatterns = zigzagPatterns,
		ZigzagBlocked = zigzagBlocked,
		Camouflages = camouflages,
		ActiveCamouflages = activeCamouflages,
		DecoySplits = decoySplits,
		ActiveDecoySplits = activeDecoySplits,
		ActiveDecoyEncounters = decoyDiagnostics.ActiveEncounters,
		ActiveDecoys = decoyDiagnostics.ActiveDecoys,
		DecoyHitProxies = decoyDiagnostics.HitProxies,
		LegendaryPursuits = legendaryPursuits,
		ActiveLegendaryPursuits = activeLegendaryPursuits,
		ReservedLegendaryPursuits = legendaryDiagnostics.ActiveEncounters,
		PreservedSprinterCooldowns = (function()
			local count = 0
			for _ in sprinterCooldownByItemId do
				count += 1
			end
			return count
		end)(),
		PreservedDecoyCooldowns = (function()
			local count = 0
			for _ in decoyCooldownByItemId do
				count += 1
			end
			return count
		end)(),
		PreservedLegendaryCooldowns = (function()
			local count = 0
			for _ in legendaryCooldownByItemId do
				count += 1
			end
			return count
		end)(),
		SchedulerConnections = if heartbeatConnection then 1 else 0,
	})
end

function DevelopmentBrainrotRoaming._TestRouteSegmentLengths(distance: number): { number }
	return routeSegmentLengths(distance)
end

function DevelopmentBrainrotRoaming._TestRouteParams(brainrot: Model): RaycastParams
	return routeParams(brainrot)
end

function DevelopmentBrainrotRoaming._TestMovementEnvelope(brainrot: Model): (CFrame?, Vector3?)
	return movementEnvelope(brainrot)
end

function DevelopmentBrainrotRoaming._TestReconcileTerritoryPresence(
	brainrot: Model,
	controller: any,
	inside: boolean,
	now: number
)
	reconcileTerritoryPresence(brainrot, controller, inside, now)
end

function DevelopmentBrainrotRoaming._TestCampReturnProtectionEnvelope(
	brainrot: Model,
	position: Vector3,
	groundY: number
): (CFrame?, Vector3?)
	return campReturnProtectionEnvelopeAt(brainrot, position, groundY)
end

function DevelopmentBrainrotRoaming._TestCampReturnRouteEnvelope(
	brainrot: Model,
	from: Vector3,
	to: Vector3,
	groundY: number
): (CFrame?, Vector3?)
	return campReturnRouteEnvelope(brainrot, from, to, groundY)
end

function DevelopmentBrainrotRoaming.Start()
	if started then
		return
	end
	started = true
	heartbeatConnection = RunService.Heartbeat:Connect(updateAll)
	-- Read-only Studio QA seam (ServerStorage.CreatureMotionQA = true before Play).
	-- execute_luau gets its own module cache, so live controller state needs this.
	local ServerStorage = game:GetService("ServerStorage")
	if RunService:IsStudio() and ServerStorage:GetAttribute("CreatureMotionQA") == true then
		local fn = Instance.new("BindableFunction")
		fn.Name = "CreatureMotionQA"
		fn.OnInvoke = function(command: string)
			if command == "Diagnostics" then
				return DevelopmentBrainrotRoaming.GetDiagnostics()
			elseif command == "Controllers" then
				local rows = {}
				for model, controller in controllers do
					local motor = controller.RouteMotor
					table.insert(rows, {
						id = runtimeId(model),
						species = model:GetAttribute("BrainrotId"),
						behaviour = controller.BehaviourId,
						paused = controller.Paused,
						ready = model:GetAttribute("Phase12InteractionReady"),
						motor = motor ~= nil,
						phase = if motor then motor.Phase else nil,
						pending = if motor then motor.Pending else nil,
						hasGoal = if motor then motor.Goal ~= nil else controller.RoamGoal ~= nil,
						blocked = if motor then motor.BlockedReason else nil,
						recovering = controller.RecoveringTerritory,
						region = controller.TerritoryRegionId,
						speed = controller.NormalSpeed,
						reactLock = controller.Reaction.lockedThreatUserId,
						sprintPhase = controller.Sprint.Phase,
						sprintLock = controller.Sprint.lockedThreatUserId,
						goalKind = controller.ActiveGoalKind,
						motion = controller.Motion,
						noticing = controller.NoticeFace ~= nil,
						noticeArmed = controller.NoticeArmed,
						pauseKind = if motor then motor.PauseKind else nil,
						position = model:GetPivot().Position,
						observed = interestResolver == nil or interestResolver(
							controller.TerritoryRegionId,
							model:GetPivot().Position
						),
					})
				end
				return rows
			end
			return nil
		end
		fn.Parent = ServerStorage
	end
end

return DevelopmentBrainrotRoaming
