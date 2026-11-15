--!strict
-- Core Loop V2, Part A: the spawn director. With CoreLoopFlags.Part("Herds") on it is the only source
-- of natural spawns: every wild brainrot exists because it was ordered for a specific hunter, as a herd
-- ahead of them (3-6, exactly one Star) or a loner near them. DevelopmentBrainrotSpawner keeps owning
-- reservation, construction, registration and retirement (SpawnDirected / RetireFreshIndividual).
-- Retirement follows DespawnPolicy (A7): nothing is retired near a hunter; Stars leave visibly.
-- All decisions are server-side; clients only read attributes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local CoreLoop = require(Shared.Config.CoreLoop)
local CoreLoopFlags = require(Shared.Config.CoreLoopFlags)
local Regions = require(Shared.Config.Regions)
local CampExits = require(Shared.Config.CampExits)
local HerdComposer = require(Shared.CoreLoop.HerdComposer)
local StarGrade = require(Shared.CoreLoop.StarGrade)
local OddsText = require(Shared.CoreLoop.OddsText)
local DespawnPolicy = require(Shared.CoreLoop.DespawnPolicy)
local RushClock = require(Shared.CoreLoop.RushClock)
local RegionSpawnCatalog = require(script.Parent.RegionSpawnCatalog)
local Progress = require(script.Parent.Parent.Services.CoreLoopProgress)
local CartLocalPlacement = require(script.Parent.Parent.Utility.CartLocalPlacement)
local CartLocalCorrection = require(Shared.Config.CartLocalCorrection)

type Role = "Snack" | "Loner" | "Star" | "Ambient"
type Entry = {
	Model: Model,
	Record: any,
	Role: Role,
	OwnerUserId: number?,
	HerdId: string?,
	RegionId: string,
	SpawnedAt: number,
	UnseenSince: number?,
	FarSince: number?, -- loners: beyond Loners.FarStuds of the owner
	StarFirstSeenAt: number?,
	LeavingSince: number?,
	Diving: boolean,
	TrueGrade: string?, -- server-only (B1)
	VisibleGrade: string?, -- Stars: set at spawn; TrueGrade replaces it at the KO
	SuperPlus: string?, -- cached "Super" / "Jackpot" for the per-tick snapshot
	WasSleeping: boolean,
	Parity: number, -- which despawn half checks this entry (fixed at creation)
}
type Herd = {
	Id: string,
	Kind: "Wild" | "Village",
	Centre: Vector3,
	OrderedAt: number,
	Members: { [Model]: boolean },
	Star: Model?,
}
type Hunter = {
	Player: any, -- the Player, or a QA virtual hunter key (Studio only)
	UserId: number,
	Virtual: boolean,
	Busy: boolean, -- a placement job is in flight
	RegionCache: string?,
	RegionCachePos: Vector3?,
	InCampCache: boolean?,
	Samples: { { t: number, p: Vector3 } },
	LastSampleAt: number,
	Herd: Herd?,
	LastOrderAt: number,
	Loners: { [Model]: boolean },
	HuntingSeconds: number,
	LastKoAt: number?,
	-- Pending forced Star (Lucky / pity, Part C). Shortens the order cooldown (A3).
	PendingStar: ("Super" | "Jackpot")?,
}

local Director = {}

local dependencies: any = nil
local connection: RBXScriptConnection? = nil
local accumulator = 0
local random = Random.new()
local entries: { [Model]: Entry } = {}
local hunters: { [any]: Hunter } = {}
local rushOverride: string? = nil -- QA only
local virtualProvider: (() -> { any })? = nil -- QA only: extra hunter rows
local frameRing: { number } = {} -- last 3600 director frame costs (ms) for the p99
local frameRingIndex = 1
-- 4-tick cycle: 0 snapshot, 1 despawn (even rows), 2 snapshot, 3 despawn (odd rows). The snapshot
-- refreshes at 2 Hz and every brainrot's retirement check runs at 1 Hz; no tick carries both.
local tickPhase = 0
local nextParity = 0
local lastFilterAt = -math.huge
local lastTickRows: { any } = {}
-- Studio QA only; set ServerStorage.CoreLoopMeasureOnScreen = false to exclude it from a perf run.
local measureOnScreen = RunService:IsStudio()
	and game:GetService("ServerStorage"):GetAttribute("CoreLoopMeasureOnScreen") ~= false
local accessOverride = false -- QA only: ignore region locks for the test profile

-- Placement runs as time-sliced jobs so one herd order never spikes a frame (P-1).
type Job = { State: Hunter, Co: thread }
local jobs: { Job } = {}
local frameStartedAt = 0
local FRAME_BUDGET_SECONDS = 0.0008 -- leaves headroom under the 2 ms P-1 peak
local superInView: (any, { any }) -> boolean
local trySave: (Entry) -> ()
local lonersShort: (Hunter) -> boolean
local enqueue: (Hunter, () -> ()) -> ()
local function checkpoint()
	if os.clock() - frameStartedAt > FRAME_BUDGET_SECONDS then
		coroutine.yield()
	end
end

local stats = {
	Orders = 0,
	WildHerds = 0,
	VillageHerds = 0,
	OrderFailures = 0,
	PlacementRejects = {} :: { [string]: number },
	Spawned = 0,
	Loners = 0,
	RetiredUnseen = 0,
	RetiredAmbient = 0,
	StarsLeft = 0,
	RetiredInView = 0, -- A-6: must stay 0 (Dive excluded; it is the visible exit)
	KOs = 0,
	KoGaps = {} :: { number },
	TickMsTotal = 0,
	TickMsPeak = 0,
	Ticks = 0,
	HerdSizes = {} :: { [number]: number },
	StarGrades = { Star = 0, Super = 0, Jackpot = 0 },
	-- A-1: checked at the moment each member actually spawns.
	SpawnChecks = 0,
	MinPlayerDistanceViolations = 0,
	MinPadDistanceViolations = 0,
	MemberSpacingViolations = 0,
	-- B-5: hunting seconds with a Super+ Star within 300 studs inside the +-75 degree view.
	HuntingSecondsTotal = 0,
	SuperVisibleSeconds = 0,
	SectionMs = { Snapshot = 0, Hunters = 0, Despawn = 0 },
	SectionTotalMs = { Snapshot = 0, Hunters = 0, Despawn = 0 },
	Frames = 0,
	FramesOver2Ms = 0,
	PlacementBudgetWaits = 0,
	-- P-1: whole director cost per server frame (tick + placement jobs).
	FrameMsPeak = 0, -- director logic only (spawner calls excluded, see SpawnerCallMsPeak)
	SpawnerCallMsPeak = 0, -- one RetireFreshIndividual / SpawnDirected call
	PlacementCallMsPeak = 0, -- one RegionSpawnCatalog.ValidatePlacement call
	RetireQueuePeak = 0,
	JobsRun = 0,
	-- A7 Saved overflow sleepers.
	Saved = 0,
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function reject(reason: string)
	stats.PlacementRejects[reason] = (stats.PlacementRejects[reason] or 0) + 1
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Live player rows (protection uses every live player, a superset of hunters: never retire in view).
local function playerRows(): { { Player: Player, Position: Vector3, Velocity: Vector3, Look: Vector3 } }
	local rows = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			-- QA SimHunter moves an anchored root and publishes its simulated velocity (Studio only).
			local simVelocity = if RunService:IsStudio()
				then player:GetAttribute("CoreLoopSimVelocity")
				else nil
			table.insert(rows, {
				Player = player,
				UserId = player.UserId,
				Virtual = false,
				Position = root.Position,
				Velocity = if typeof(simVelocity) == "Vector3"
					then simVelocity
					else root.AssemblyLinearVelocity,
				Look = root.CFrame.LookVector,
			})
		end
	end
	if virtualProvider and RunService:IsStudio() then
		for _, row in virtualProvider() do
			row.Virtual = true
			table.insert(rows, row)
		end
	end
	return rows
end

local function inCamp(position: Vector3): boolean
	return RegionSpawnCatalog.ContainsPosition(Regions.CampId, position, math.huge)
end

local function huntingRegionAt(position: Vector3): string?
	local region = RegionSpawnCatalog.GetRegionAtPosition(position, 8)
	if region and region.id ~= Regions.CampId and region.kind == "Hunting" then
		return region.id
	end
	return nil
end

-- §3 Hunter predicate.
local function hunterState(player: any, userId: number?, virtual: boolean?): Hunter
	local state = hunters[player]
	if not state then
		state = {
			Player = player,
			UserId = userId or (player :: any).UserId,
			Virtual = virtual == true,
			Busy = false,
			Samples = {},
			LastSampleAt = -math.huge,
			Herd = nil,
			LastOrderAt = -math.huge,
			Loners = {},
			HuntingSeconds = 0,
			LastKoAt = nil,
			PendingStar = nil,
		}
		hunters[player] = state
	end
	return state
end

local function isActive(state: Hunter, position: Vector3, t: number): boolean
	if t - state.LastSampleAt >= 1 then
		state.LastSampleAt = t
		table.insert(state.Samples, { t = t, p = position })
	end
	local window = CoreLoop.Hunter.ActiveWindowSeconds
	while #state.Samples > 0 and t - state.Samples[1].t > window do
		table.remove(state.Samples, 1)
	end
	for _, sample in state.Samples do
		if flatDistance(sample.p, position) > CoreLoop.Hunter.ActiveMoveStuds then
			return true
		end
	end
	return false
end

local function rushKind(): "Idle" | "Rush" | "Mega"
	if rushOverride == "Rush" or rushOverride == "Mega" then
		return rushOverride :: any
	end
	local world = dependencies and dependencies.WorldService
	local snapshot = world and world.GetRush and world:GetRush()
	return if snapshot then RushClock.ActiveKind(snapshot) else "Idle"
end

-- Ground + spawn-volume + ValidatePlacement for one point. Returns the validated pivot.
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.RespectCanCollide = true

local function refreshRayFilter()
	local exclusions: { Instance } = {}
	local runtime = Workspace:FindFirstChild("Runtime")
	if runtime then
		table.insert(exclusions, runtime)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclusions, player.Character)
		end
	end
	raycastParams.FilterDescendantsInstances = exclusions
end

local minSlopeY = math.cos(math.rad(CoreLoop.Herd.MaxSlopeDeg))

local function groundAt(point: Vector3): (Vector3?, string?)
	local hit = Workspace:Raycast(point + Vector3.yAxis * 80, -Vector3.yAxis * 220, raycastParams)
	if not hit then
		return nil, "NO_GROUND"
	end
	if hit.Material == Enum.Material.Water then
		return nil, "WATER"
	end
	if hit.Normal.Y < minSlopeY then
		return nil, "SLOPE"
	end
	return hit.Position, nil
end

local function volumeAt(regionId: string, position: Vector3): string?
	for _, area in RegionSpawnCatalog.GetSpawnAreas(regionId) do
		if type(area) == "table" and area.Enabled == true and area.Kind == "Volume" then
			local localPoint = area.Part.CFrame:PointToObjectSpace(position)
			if
				math.abs(localPoint.X) <= area.Part.Size.X * 0.5
				and math.abs(localPoint.Z) <= area.Part.Size.Z * 0.5
			then
				return area.Id
			end
		end
	end
	return nil
end

local lanePoints: { Vector3 } = {}
for _, lane in CampExits.Lanes do
	for _, point in lane.points do
		table.insert(lanePoints, point)
	end
end

-- A moving cart closes ~25 studs between placement and the last pop (stagger + job latency), so the
-- 45-stud rule is checked against where each player is now AND where they will be in POP_LEAD seconds.
local POP_LEAD = 0.75
local function clearOfPadsAndPlayers(position: Vector3, rows: { any }): string?
	for _, row in rows do
		local ahead = row.Position + Vector3.new(row.Velocity.X, 0, row.Velocity.Z) * POP_LEAD
		if
			flatDistance(row.Position, position) < CoreLoop.Herd.MinPlayerDistance
			or flatDistance(ahead, position) < CoreLoop.Herd.MinPlayerDistance
		then
			return "NEAR_PLAYER"
		end
	end
	for _, point in lanePoints do
		if flatDistance(point, position) < CoreLoop.Herd.MinPadDistance then
			return "NEAR_LANE"
		end
	end
	if inCamp(position) then
		return "IN_CAMP"
	end
	-- Camp (bases, cart spawns) padded by MinPadDistance: probe the four flat offsets.
	local pad = CoreLoop.Herd.MinPadDistance
	for _, offset in
		{
			Vector3.new(pad, 0, 0),
			Vector3.new(-pad, 0, 0),
			Vector3.new(0, 0, pad),
			Vector3.new(0, 0, -pad),
		}
	do
		if inCamp(position + offset) then
			return "NEAR_CAMP"
		end
	end
	return nil
end

-- Spawner calls (model destroy / construction) are timed separately from the director's own logic.
local spawnerMsThisFrame = 0
local function timedSpawnerCall<A..., R...>(fn: (A...) -> R..., ...: A...): R...
	local started = os.clock()
	local results = table.pack(fn(...))
	local ms = (os.clock() - started) * 1000
	spawnerMsThisFrame += ms
	stats.SpawnerCallMsPeak = math.max(stats.SpawnerCallMsPeak, ms)
	return table.unpack(results, 1, results.n)
end

-- ValidatePlacement (RegionSpawnCatalog) is timed the same way, under its own peak.
local function timedPlacementCall(...: any): any
	local started = os.clock()
	local result = RegionSpawnCatalog.ValidatePlacement(...)
	local ms = (os.clock() - started) * 1000
	spawnerMsThisFrame += ms
	stats.PlacementCallMsPeak = math.max(stats.PlacementCallMsPeak, ms)
	return result
end

-- ValidatePlacement spends the server-wide placement query budget (60 world + 60 terrain per second),
-- which cart safety correction and launch checks share. Herd placement only uses the spare half: a job
-- waits (yielding frame by frame) until at least half of each budget is left this second.
local PLACEMENT_RESERVE_SHARE = 0.5
local function placementBudgetLeft(): number
	local diagnostics = CartLocalPlacement.GetDiagnostics()
	local worldLimit = CartLocalCorrection.MaximumWorldQueriesPerSecond
	local terrainLimit = CartLocalCorrection.MaximumTerrainQueriesPerSecond
	local at = Workspace:GetServerTimeNow()
	if at < diagnostics.window or at - diagnostics.window >= 1 then
		return math.min(worldLimit, terrainLimit)
	end
	return math.min(worldLimit - diagnostics.world, terrainLimit - diagnostics.terrain)
end
local function waitForPlacementBudget()
	local reserve = math.ceil(
		math.min(
			CartLocalCorrection.MaximumWorldQueriesPerSecond,
			CartLocalCorrection.MaximumTerrainQueriesPerSecond
		) * PLACEMENT_RESERVE_SHARE
	)
	local waited = false
	while placementBudgetLeft() < reserve do
		waited = true
		coroutine.yield()
	end
	if waited then
		stats.PlacementBudgetWaits += 1
	end
end

local function validateMember(
	speciesId: string,
	regionId: string,
	point: Vector3
): (CFrame?, string?)
	if not RegionSpawnCatalog.ContainsPosition(regionId, point, math.huge) then
		return nil, "OUTSIDE_REGION"
	end
	local ground, reason = groundAt(point)
	if not ground then
		return nil, reason
	end
	local areaId = volumeAt(regionId, ground)
	if not areaId then
		return nil, "NO_SPAWN_VOLUME"
	end
	waitForPlacementBudget()
	local result = timedPlacementCall(speciesId, regionId, areaId, ground)
	if not (result.valid and typeof(result.placementPivot) == "CFrame") then
		local first = if type(result.reasons) == "table" then result.reasons[1] else nil
		return nil, "PLACEMENT_" .. tostring(first or "INVALID")
	end
	return result.placementPivot, nil
end

-- Villager homes per region (guard zone = union of GuardZoneRadius circles).
local homesByRegion: { [string]: { Vector3 } } = {}
do
	local folder = Shared.Config:FindFirstChild("Villagers")
	if folder then
		for _, module in folder:GetChildren() do
			if module:IsA("ModuleScript") then
				local ok, data = pcall(require, module)
				if ok and type(data) == "table" and type(data.regionId) == "string" then
					local homes = {}
					for _, villager in data.villagers or {} do
						if type(villager.home) == "table" and villager.type ~= "Shouter" then
							table.insert(homes, Vector3.new(villager.home[1], 0, villager.home[2]))
						end
					end
					homesByRegion[data.regionId] = homes
				end
			end
		end
	end
end

local function inGuardZone(regionId: string, point: Vector3): (boolean, number)
	local nearest = math.huge
	for _, home in homesByRegion[regionId] or {} do
		nearest = math.min(nearest, flatDistance(home, point))
	end
	return nearest <= CoreLoop.Herd.GuardZoneRadius, nearest
end

local function headingFor(row: any): (number, number, number, number)
	local flat = Vector3.new(row.Velocity.X, 0, row.Velocity.Z)
	local h = CoreLoop.Herd
	if flat.Magnitude >= h.MovingSpeed then
		return math.atan2(flat.X, flat.Z), h.AheadSpreadDeg, h.AheadMin, h.AheadMax
	end
	local look = Vector3.new(row.Look.X, 0, row.Look.Z)
	local yaw = if look.Magnitude > 0.01
		then math.atan2(look.X, look.Z)
		else random:NextNumber(0, 2 * math.pi)
	return yaw, h.StillSpreadDeg, h.StillMin, h.StillMax
end

local function pointAt(origin: Vector3, yaw: number, distance: number): Vector3
	return origin + Vector3.new(math.sin(yaw), 0, math.cos(yaw)) * distance
end

-- A4: village points inside the guard zone, >= VillageMinHomeDistance from every home, in the cone.
local function villageCandidates(
	regionId: string,
	origin: Vector3,
	yaw: number,
	spread: number
): { Vector3 }
	local points = {}
	if not homesByRegion[regionId] or #homesByRegion[regionId] == 0 then
		return points
	end
	for distance = 60, 140, 16 do
		for angle = -spread, spread, 10 do
			local point = pointAt(origin, yaw + math.rad(angle), distance)
			local inside, nearest = inGuardZone(regionId, point)
			if inside and nearest >= CoreLoop.Herd.VillageMinHomeDistance then
				table.insert(points, point)
			end
		end
	end
	return points
end

local function chooseKind(
	state: Hunter,
	regionId: string,
	origin: Vector3,
	yaw: number,
	spread: number,
	preferVillage: boolean?
): ("Wild" | "Village", { Vector3 })
	local candidates = villageCandidates(regionId, origin, yaw, spread)
	if #candidates == 0 then
		return "Wild", candidates
	end
	-- Part I: no Village herds until the first bank (first session only).
	if
		dependencies.IsFirstSessionBeforeBank
		and dependencies.IsFirstSessionBeforeBank(state.Player)
	then
		return "Wild", candidates
	end
	if preferVillage or random:NextNumber() < CoreLoop.Herd.VillageChance then
		return "Village", candidates -- a Lucky Star is a Village herd when possible (C1)
	end
	return "Wild", candidates
end

local function newEntry(
	model: Model,
	record: any,
	role: Role,
	owner: number?,
	herdId: string?,
	regionId: string
): Entry
	local entry: Entry = {
		Model = model,
		Record = record,
		Role = role,
		OwnerUserId = owner,
		HerdId = herdId,
		RegionId = regionId,
		SpawnedAt = now(),
		UnseenSince = nil,
		FarSince = nil,
		StarFirstSeenAt = nil,
		LeavingSince = nil,
		Diving = false,
		TrueGrade = nil,
		VisibleGrade = nil,
		SuperPlus = nil,
		WasSleeping = false,
		Parity = nextParity,
	}
	nextParity = 1 - nextParity
	entries[model] = entry
	return entry
end

local function regionLoad(regionId: string): number
	local _, _, byRegion = dependencies.Spawner.GetPopulationCounts()
	return byRegion[regionId] or 0
end

local function serverLoad(): number
	local wild, reserved = dependencies.Spawner.GetPopulationCounts()
	return wild + reserved
end

-- One read of every tracked brainrot per tick (position, sleep, Star grade), shared by every hunter
-- check and the despawn pass, so the tick cost grows with entries + hunters, not entries x hunters.
type Snap = { Model: Model, Entry: Entry, Position: Vector3, Sleeping: boolean, SuperPlus: string? }
-- Awake entries bucketed on a PerHunterRadius grid, so a hunter checks only the 3x3 cells around it.
local GRID = CoreLoop.Population.PerHunterRadius
local awakeGrid: { [number]: { Snap } } = {}
local function cellKey(x: number, z: number): number
	return x * 65536 + z
end
-- Snapshot rows and grid buckets are pooled across ticks (no per-tick table churn).
local snapRows: { Snap } = {}
local snapPool: { Snap } = {}
local bucketPool: { { Snap } } = {}
local function snapshot(): { Snap }
	for _, item in snapRows do
		table.insert(snapPool, item)
	end
	table.clear(snapRows)
	for _, bucket in awakeGrid do
		table.clear(bucket)
		table.insert(bucketPool, bucket)
	end
	table.clear(awakeGrid)
	local rows = snapRows
	for model, entry in entries do
		if model.Parent then
			local item: Snap = table.remove(snapPool) or ({} :: any)
			item.Model = model
			item.Entry = entry
			item.Position = model:GetPivot().Position
			item.Sleeping = dependencies.Spawner.IsSleepingModel(model)
			item.SuperPlus = entry.SuperPlus
			table.insert(rows, item)
			if not item.Sleeping then
				local key =
					cellKey(math.floor(item.Position.X / GRID), math.floor(item.Position.Z / GRID))
				local bucket = awakeGrid[key]
				if not bucket then
					bucket = table.remove(bucketPool) or {}
					awakeGrid[key] = bucket
				end
				table.insert(bucket, item)
			end
		end
	end
	return rows
end

local function awakeOwnedNear(state: Hunter, position: Vector3, _snap: { Snap }): (number, number)
	local awakeHerd, awakeAll = 0, 0
	local radius = CoreLoop.Population.PerHunterRadius
	local radiusSq = radius * radius
	local members = if state.Herd then state.Herd.Members else nil
	local cx, cz = math.floor(position.X / GRID), math.floor(position.Z / GRID)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local bucket = awakeGrid[cellKey(cx + dx, cz + dz)]
			if bucket then
				for _, row in bucket do
					local ox, oz = row.Position.X - position.X, row.Position.Z - position.Z
					if ox * ox + oz * oz <= radiusSq then
						awakeAll += 1
						if members and members[row.Model] then
							awakeHerd += 1
						end
					end
				end
			end
		end
	end
	return awakeHerd, awakeAll
end

local function spawnMember(
	state: Hunter,
	herdId: string?,
	regionId: string,
	role: Role,
	member: HerdComposer.Member,
	pose: CFrame,
	extra: { [string]: any }
): Entry?
	local attributes: { [string]: any } = {
		CoreLoopRole = role,
		CoreLoopOwnerUserId = state.UserId,
		CoreLoopHerdId = herdId,
		-- K2: the mutation TYPE stays server-side until the KO; clients see a shimmer.
		CoreLoopMutationHidden = if member.mutationId ~= "None"
				and CoreLoopFlags.Part("MutationReveal")
			then true
			else nil,
	}
	for k, v in extra do
		attributes[k] = v
	end
	-- Final A-1 guard at the pop: a snack or loner that a player has reached is not spawned.
	if role ~= "Star" then
		for _, row in playerRows() do
			if flatDistance(row.Position, pose.Position) < CoreLoop.Herd.MinPlayerDistance then
				reject("POP_NEAR_PLAYER")
				return nil
			end
		end
	end
	local model, record, reason = timedSpawnerCall(dependencies.Spawner.SpawnDirected, {
		RegionId = regionId,
		SpeciesId = member.speciesId,
		MutationId = member.mutationId,
		Pose = pose,
		Attributes = attributes,
	})
	if not model then
		reject("SPAWN_" .. tostring(reason))
		return nil
	end
	stats.Spawned += 1
	-- A-1, measured where the member actually stands at spawn time.
	local at = model:GetPivot().Position
	stats.SpawnChecks += 1
	for _, row in playerRows() do
		if flatDistance(row.Position, at) < CoreLoop.Herd.MinPlayerDistance then
			stats.MinPlayerDistanceViolations += 1
			break
		end
	end
	for _, point in lanePoints do
		if flatDistance(point, at) < CoreLoop.Herd.MinPadDistance then
			stats.MinPadDistanceViolations += 1
			break
		end
	end
	if herdId then
		for other, otherEntry in entries do
			if
				otherEntry.HerdId == herdId
				and other.Parent
				and flatDistance(other:GetPivot().Position, at)
					< CoreLoop.Herd.MemberSpacing - 0.5
			then
				stats.MemberSpacingViolations += 1
				break
			end
		end
	end
	return newEntry(model, record, role, state.UserId, herdId, regionId)
end

-- A3-A5: order one herd for this hunter. Returns true when at least the Star and one member spawned.
local function orderHerd(state: Hunter, row: any, regionId: string, t: number): boolean
	local yaw, spread, minD, maxD = headingFor(row)
	local options: any = if state.Virtual then {} else Progress.ComposeOptions(state.Player)
	local kind, villagePoints =
		chooseKind(state, regionId, row.Position, yaw, spread, options.preferVillage)
	local rush = rushKind()
	local herd = HerdComposer.Compose(regionId, kind, rush, random, {
		stormMult = dependencies.StormMultiplier and dependencies.StormMultiplier() or 1,
		minTrueGrade = options.minTrueGrade or state.PendingStar,
		mutatedSnack = options.mutatedSnack,
	})
	if not herd then
		stats.OrderFailures += 1
		reject("COMPOSE_FAILED")
		return false
	end
	local rows = playerRows()
	for _ = 1, CoreLoop.Herd.Attempts do
		checkpoint()
		local centre: Vector3
		if kind == "Village" and #villagePoints > 0 then
			centre = villagePoints[random:NextInteger(1, #villagePoints)]
		else
			centre = pointAt(
				row.Position,
				yaw + math.rad(random:NextNumber(-spread, spread)),
				random:NextNumber(minD, maxD)
			)
		end
		local blocked = clearOfPadsAndPlayers(centre, rows)
		if blocked then
			reject(blocked)
			continue
		end
		local centreGround, groundReason = groundAt(centre)
		if not centreGround then
			reject(groundReason or "NO_GROUND")
			continue
		end
		-- Star first, nearest the centre (0-3 studs), then members on the 5-12 ring, >= 6 apart.
		local placed: { { member: HerdComposer.Member, pose: CFrame } } = {}
		local used: { Vector3 } = {}
		for index, member in herd.members do
			local pose: CFrame? = nil
			for _ = 1, 6 do
				checkpoint()
				local radius = if index == 1
					then random:NextNumber(0, 3)
					else random:NextNumber(
						CoreLoop.Herd.MemberRingMin,
						CoreLoop.Herd.MemberRingMax
					)
				local point = pointAt(centreGround, random:NextNumber(0, 2 * math.pi), radius)
				local spaced = true
				for _, other in used do
					if flatDistance(other, point) < CoreLoop.Herd.MemberSpacing then
						spaced = false
						break
					end
				end
				if spaced and not clearOfPadsAndPlayers(point, rows) then
					local candidate, reason = validateMember(member.speciesId, regionId, point)
					if candidate then
						pose = candidate
						break
					end
					reject("MEMBER_" .. tostring(reason))
				end
			end
			if pose then
				table.insert(used, pose.Position)
				table.insert(placed, { member = member, pose = pose })
			elseif index == 1 then
				break -- no Star, no herd
			end
		end
		if
			#placed < CoreLoop.Herd.MinValidMembers
			or not placed[1]
			or not placed[1].member.star
		then
			reject("TOO_FEW_MEMBERS")
			continue
		end
		-- Placement may have waited for query budget: re-check every pose against where players are now.
		local fresh = playerRows()
		local stale = false
		for _, slot in placed do
			if clearOfPadsAndPlayers(slot.pose.Position, fresh) == "NEAR_PLAYER" then
				stale = true
				break
			end
		end
		if stale then
			reject("STALE_PLACEMENT")
			continue
		end
		local herdId = string.sub(HttpService:GenerateGUID(false), 1, 8)
		local record: Herd = {
			Id = herdId,
			Kind = kind,
			Centre = centreGround,
			OrderedAt = t,
			Members = {},
			Star = nil,
		}
		state.Herd = record
		if kind == "Village" then
			stats.VillageHerds += 1
		else
			stats.WildHerds += 1
		end
		stats.HerdSizes[#placed] = (stats.HerdSizes[#placed] or 0) + 1
		stats.StarGrades[herd.visibleGrade] += 1
		state.PendingStar = nil
		if not state.Virtual then
			Progress.OnHerdComposed(state.Player, herd, options)
		end
		local arrival = options.arrival or (if herd.trueGrade == "Jackpot" then "Rift" else "Beam")
		-- F1: members pop staggered PopStagger apart, Star last.
		local order = {}
		for i = 2, #placed do
			table.insert(order, placed[i])
		end
		table.insert(order, placed[1])
		local spawnAt = now()
		for i, slot in order do
			task.delay((i - 1) * CoreLoop.Fx.PopStagger, function()
				if state.Herd ~= record or hunters[state.Player] ~= state then
					return
				end
				local isStar = slot.member.star
				local extra: { [string]: any } = {}
				if isStar then
					extra.CoreLoopStar = true
					extra.StarOwnerUserId = state.UserId
					extra.StarExclusiveUntil = spawnAt + CoreLoop.Star.OwnerExclusiveSeconds
					extra.VisibleGrade = herd.visibleGrade
					extra.StarOdds = OddsText.ForIndividual(regionId, slot.member.speciesId, "None")
					extra.Guarded = kind == "Village"
					extra.Arrival = arrival
					extra.StarSource = options.source
				end
				local entry = spawnMember(
					state,
					herdId,
					regionId,
					if isStar then "Star" else "Snack",
					slot.member,
					slot.pose,
					extra
				)
				if entry then
					record.Members[entry.Model] = true
					if isStar then
						record.Star = entry.Model
						entry.TrueGrade = herd.trueGrade
						entry.VisibleGrade = herd.visibleGrade
						entry.SuperPlus = if herd.visibleGrade == "Super"
								or herd.visibleGrade == "Jackpot"
							then herd.visibleGrade
							else nil
					end
				end
			end)
		end
		if dependencies.Analytics and not state.Virtual then
			pcall(
				dependencies.Analytics.Record,
				dependencies.Analytics,
				state.Player,
				"CL_HerdOrdered",
				#placed,
				nil
			)
		end
		return true
	end
	stats.OrderFailures += 1
	return false
end

-- Cheap pre-check so a placement job is created only when a loner is actually missing.
lonersShort = function(state: Hunter): boolean
	local wanted = if rushKind() ~= "Idle"
		then CoreLoop.Loners.RushPerHunter
		else CoreLoop.Loners.PerHunter
	local count = 0
	for model in state.Loners do
		if model.Parent and entries[model] then
			count += 1
		end
	end
	return count < wanted
end

local function topUpLoners(state: Hunter, row: any, regionId: string)
	local wanted = if rushKind() ~= "Idle"
		then CoreLoop.Loners.RushPerHunter
		else CoreLoop.Loners.PerHunter
	local count = 0
	for model in state.Loners do
		if model.Parent and entries[model] then
			count += 1
		else
			state.Loners[model] = nil
		end
	end
	if count >= wanted then
		return
	end
	local rows = playerRows()
	local look = Vector3.new(row.Look.X, 0, row.Look.Z)
	local yaw = if look.Magnitude > 0.01
		then math.atan2(look.X, look.Z)
		else random:NextNumber(0, 2 * math.pi)
	local member = HerdComposer.RollSnack(
		regionId,
		rushKind(),
		random,
		dependencies.StormMultiplier and dependencies.StormMultiplier() or 1
	)
	if not member then
		return
	end
	for _ = 1, 4 do
		checkpoint()
		local point = pointAt(
			row.Position,
			yaw + math.rad(random:NextNumber(-CoreLoop.Loners.SpreadDeg, CoreLoop.Loners.SpreadDeg)),
			random:NextNumber(CoreLoop.Loners.Min, CoreLoop.Loners.Max)
		)
		local blocked = clearOfPadsAndPlayers(point, rows)
		if not blocked then
			local pose = validateMember(member.speciesId, regionId, point)
			if pose then
				local entry = spawnMember(state, nil, regionId, "Loner", member, pose, {})
				if entry then
					state.Loners[entry.Model] = true
					stats.Loners += 1
					if not state.Virtual then
						Progress.OnLonerSpawned(state.Player, member.mutationId)
					end
				end
				return
			end
		end
	end
end

-- Owner entered Camp / died / left: herd and loners become ambient at once (A7).
local function releaseToAmbient(state: Hunter)
	if state.Herd then
		for model in state.Herd.Members do
			local entry = entries[model]
			if entry then
				entry.Role = "Ambient"
				entry.OwnerUserId = nil
				if model.Parent then
					model:SetAttribute("CoreLoopRole", "Ambient")
				end
			end
		end
		state.Herd = nil
	end
	for model in state.Loners do
		local entry = entries[model]
		if entry then
			entry.Role = "Ambient"
			entry.OwnerUserId = nil
		end
	end
	table.clear(state.Loners)
end

local function retire(entry: Entry, reason: string)
	local ok = timedSpawnerCall(dependencies.Spawner.RetireFreshIndividual, entry.Record, reason)
	if ok then
		entries[entry.Model] = nil
	end
	return ok
end

-- Retirements decided in a tick are executed one per frame (P-1), re-checked against rule zero.
type PendingRetire = { Entry: Entry, Reason: string, Kind: string }
local retireQueue: { PendingRetire } = {}
local queuedRetire: { [Entry]: boolean } = {}

local function onDive(entry: Entry)
	entry.Diving = true
	entry.Model:SetAttribute("StarDiving", now())
	stats.StarsLeft += 1
	task.delay(CoreLoop.Despawn.DiveSeconds, function()
		if entries[entry.Model] == entry and entry.Model.Parent then
			if dependencies.Spawner.IsSleepingModel(entry.Model) then
				entry.Diving = false
				entry.Model:SetAttribute("StarDiving", nil)
				return
			end
			retire(entry, "StarDive")
		end
	end)
end

local function lastHitAt(entry: Entry): number?
	local stamped = entry.Model:GetAttribute("Phase13LastDamageAt")
	if type(stamped) == "number" then
		return stamped
	end
	local phase = dependencies.Spawner.GetPhase12State(entry.Record)
	local at = phase and phase.LastAcceptedDamageTime
	return if type(at) == "number" then at else nil
end

-- One facts table reused for every DespawnPolicy call (no per-entry allocation).
local reusableFacts: DespawnPolicy.Facts = {
	role = "Snack",
	now = 0,
	nearestHunterDistance = math.huge,
}

local function stepDespawn(rows: { any }, t: number, snap: { Snap }, parity: number)
	local seenRadius = CoreLoop.Star.SeenRadius
	local coneCos = math.cos(math.rad(CoreLoop.Star.SeenConeDeg))
	for model in entries do
		if model.Parent == nil then
			-- Carried, loaded, banked or retired elsewhere: no longer a wild director entry.
			entries[model] = nil
		end
	end
	for _, item in snap do
		local model, entry = item.Model, item.Entry
		if entry.Parity ~= parity then
			continue
		end
		if entries[model] ~= entry or entry.Diving then
			continue
		end
		local position = item.Position
		local nearest = math.huge
		local owner: any = nil
		for _, row in rows do
			local d = flatDistance(row.Position, position)
			nearest = math.min(nearest, d)
			if row.UserId == entry.OwnerUserId then
				owner = row
			end
		end
		if nearest > CoreLoop.Despawn.ProtectRadius then
			entry.UnseenSince = entry.UnseenSince or t
		else
			entry.UnseenSince = nil
		end
		local sleeping = item.Sleeping
		if sleeping and not entry.WasSleeping then
			entry.WasSleeping = true
		elseif not sleeping then
			entry.WasSleeping = false
			if model:GetAttribute("SavedUntil") ~= nil then
				model:SetAttribute("SavedUntil", nil)
				model:SetAttribute("SavedOwnerUserId", nil)
			end
		end
		-- B1 StarFirstSeenAt: owner within SeenRadius and the Star inside its +-SeenConeDeg view.
		if entry.Role == "Star" and not entry.StarFirstSeenAt and owner then
			local offset =
				Vector3.new(position.X - owner.Position.X, 0, position.Z - owner.Position.Z)
			local look = Vector3.new(owner.Look.X, 0, owner.Look.Z)
			if
				offset.Magnitude <= seenRadius
				and (
					offset.Magnitude < 1
					or (look.Magnitude > 0.01 and offset.Unit:Dot(look.Unit) >= coneCos)
				)
			then
				entry.StarFirstSeenAt = t
				model:SetAttribute("StarFirstSeenAt", t)
				if dependencies.Analytics and owner and not owner.Virtual then
					pcall(
						dependencies.Analytics.Record,
						dependencies.Analytics,
						owner.Player,
						"CL_StarSeen",
						StarGrade.Rank(model:GetAttribute("VisibleGrade") or "Star"),
						nil
					)
				end
			end
		end
		-- Loners recycle after FarSeconds beyond FarStuds of their owner.
		if entry.Role == "Loner" then
			local far = not owner
				or flatDistance(owner.Position, position) > CoreLoop.Loners.FarStuds
			entry.FarSince = if far then (entry.FarSince or t) else nil
		end
		local facts = reusableFacts
		facts.role = entry.Role
		facts.now = t
		facts.nearestHunterDistance = nearest
		facts.unseenSince = entry.UnseenSince
		facts.asleep = sleeping
		facts.pendingBank = false
		facts.lastHitAt = lastHitAt(entry)
		facts.starFirstSeenAt = entry.StarFirstSeenAt
		facts.leavingSince = entry.LeavingSince
		local decision = DespawnPolicy.Decide(facts)
		if
			entry.Role == "Loner"
			and decision == "Keep"
			and entry.FarSince
			and t - entry.FarSince >= CoreLoop.Loners.FarSeconds
			and not DespawnPolicy.Protected(facts)
			and nearest > CoreLoop.Despawn.ProtectRadius
		then
			decision = "Retire"
		end
		if decision == "Retire" then
			if nearest <= CoreLoop.Despawn.ProtectRadius then
				stats.RetiredInView += 1 -- defensive: DespawnPolicy never asks for this
			end
			if not queuedRetire[entry] then
				queuedRetire[entry] = true
				table.insert(retireQueue, {
					Entry = entry,
					Reason = if entry.Role == "Ambient"
						then "CoreLoopAmbient"
						else "CoreLoopUnseen",
					Kind = entry.Role,
				})
				stats.RetireQueuePeak = math.max(stats.RetireQueuePeak, #retireQueue)
			end
		elseif decision == "StartLeaving" then
			entry.LeavingSince = t
			model:SetAttribute(
				"StarLeavingUntil",
				(entry.StarFirstSeenAt :: number) + CoreLoop.Star.LifeSeconds
			)
		elseif decision == "Dive" then
			if dependencies.Analytics and owner and not owner.Virtual then
				pcall(
					dependencies.Analytics.Record,
					dependencies.Analytics,
					owner.Player,
					"CL_StarLeft",
					1,
					nil
				)
			end
			onDive(entry)
		end
	end
end

-- B-5: a Super+ Star (anyone's) within the Super draw distance and inside the hunter's view cone.
local superConeCos = math.cos(math.rad(CoreLoop.Star.SeenConeDeg))
superInView = function(row: any, snap: { Snap }): boolean
	local look = Vector3.new(row.Look.X, 0, row.Look.Z)
	for _, item in snap do
		local grade = item.SuperPlus
		if grade then
			do
				local p = item.Position
				local offset = Vector3.new(p.X - row.Position.X, 0, p.Z - row.Position.Z)
				local reach = if grade == "Jackpot" then math.huge else 300
				if
					offset.Magnitude <= reach
					and (
						offset.Magnitude < 1
						or (look.Magnitude > 0.01 and offset.Unit:Dot(look.Unit) >= superConeCos)
					)
				then
					return true
				end
			end
		end
	end
	return false
end

enqueue = function(state: Hunter, body: () -> ())
	if state.Busy then
		return
	end
	state.Busy = true
	local co = coroutine.create(function()
		-- Raycast exclusions (characters, Runtime) are only needed by placement: refresh at most 1 Hz.
		if os.clock() - lastFilterAt >= 1 then
			lastFilterAt = os.clock()
			refreshRayFilter()
		end
		local ok, err = pcall(body)
		state.Busy = false
		if not ok then
			warn("[HuntDirector] placement job failed: " .. tostring(err))
		end
	end)
	table.insert(jobs, { State = state, Co = co })
end

local function drainRetireQueue(rows: { any })
	local pending = table.remove(retireQueue, 1)
	if not pending then
		return
	end
	local entry = pending.Entry
	queuedRetire[entry] = nil
	if entries[entry.Model] ~= entry or entry.Model.Parent == nil then
		return
	end
	-- Rule zero again at execution time: never near anyone, never asleep.
	local position = entry.Model:GetPivot().Position
	for _, row in rows do
		if flatDistance(row.Position, position) <= CoreLoop.Despawn.ProtectRadius then
			return
		end
	end
	if dependencies.Spawner.IsSleepingModel(entry.Model) then
		return
	end
	if retire(entry, pending.Reason) then
		if pending.Kind == "Ambient" then
			stats.RetiredAmbient += 1
		else
			stats.RetiredUnseen += 1
		end
	end
end

local function runJobs()
	local index = 1
	while index <= #jobs and os.clock() - frameStartedAt <= FRAME_BUDGET_SECONDS do
		local job = jobs[index]
		coroutine.resume(job.Co)
		stats.JobsRun += 1
		if coroutine.status(job.Co) == "dead" then
			table.remove(jobs, index)
		else
			index += 1
		end
	end
end

local function tick(dt: number)
	debug.profilebegin("CoreLoop.HuntDirector")
	local started = os.clock()
	local t = now()
	local rows = playerRows()
	lastTickRows = rows
	-- Snapshot + despawn run together at 2 Hz; hunter checks reuse the snapshot in between
	-- (brainrots move a few studs in 0.5 s; retirements re-check live positions before acting).
	tickPhase = (tickPhase + 1) % 4
	local snap = if tickPhase % 2 == 0 or #snapRows == 0 then snapshot() else snapRows
	local sectionAt = os.clock()
	stats.SectionMs.Snapshot = math.max(stats.SectionMs.Snapshot, (sectionAt - started) * 1000)
	stats.SectionTotalMs.Snapshot += (sectionAt - started) * 1000
	-- Hunters and their eligibility (real players; plus QA virtual hunters in Studio).
	local candidates = {}
	local present: { [any]: boolean } = {}
	for _, row in rows do
		present[row.Player] = true
	end
	for key, state in hunters do
		if not present[key] then
			releaseToAmbient(state) -- dead, respawning, or a removed virtual hunter
			if state.Virtual then
				hunters[key] = nil
			end
		end
	end
	for _, row in rows do
		local player = row.Player
		local state = hunterState(player, row.UserId, row.Virtual)
		-- Camp and region lookups are polygon tests: reuse both until the hunter moves 12 studs.
		local cached = state.RegionCachePos ~= nil
			and flatDistance(state.RegionCachePos :: Vector3, row.Position) < 12
		if not cached then
			state.InCampCache = inCamp(row.Position)
			state.RegionCache = if state.InCampCache then nil else huntingRegionAt(row.Position)
			state.RegionCachePos = row.Position
		end
		if state.InCampCache then
			releaseToAmbient(state)
			state.Samples = {}
			continue
		end
		local regionId: string? = state.RegionCache
		local active = isActive(state, row.Position, t)
		if not regionId or not active then
			continue
		end
		if not row.Virtual then
			if player:GetAttribute("TrainingActive") == true then
				continue
			end
			if
				not accessOverride
				and dependencies.AccessReader
				and not dependencies.AccessReader(player, regionId)
			then
				continue
			end
		end
		state.HuntingSeconds += dt
		stats.HuntingSecondsTotal += dt
		if not row.Virtual then
			local due = Progress.OnHunting(player, dt) -- C3 pity / owed Lucky Star
			if due and state.PendingStar ~= "Jackpot" then
				state.PendingStar = due
			end
		end
		-- B-5 is a QA measurement: computed in Studio only.
		if measureOnScreen and superInView(row, snap) then
			stats.SuperVisibleSeconds += dt
		end
		local awakeHerd, awakeAll = awakeOwnedNear(state, row.Position, snap)
		table.insert(candidates, {
			State = state,
			Row = row,
			RegionId = regionId,
			AwakeHerd = awakeHerd,
			AwakeAll = awakeAll,
		})
	end
	-- A1 priority: hunters with no herd, then fewest awake within PerHunterRadius.
	table.sort(candidates, function(a, b)
		local aNone, bNone = a.State.Herd == nil, b.State.Herd == nil
		if aNone ~= bNone then
			return aNone
		end
		return a.AwakeAll < b.AwakeAll
	end)
	local rush = rushKind()
	local reorderAt = if rush ~= "Idle"
		then CoreLoop.Rush.ReorderAwakeAtMost
		else CoreLoop.Herd.ReorderAwakeAtMost
	local cooldown = if rush == "Mega"
		then CoreLoop.Rush.MegaOrderCooldown
		elseif rush == "Rush" then CoreLoop.Rush.OrderCooldown
		else CoreLoop.Herd.OrderCooldown
	for _, c in candidates do
		local state: Hunter = c.State
		local herd = state.Herd
		local needs = herd == nil
			or c.AwakeHerd <= reorderAt
			or flatDistance(herd.Centre, c.Row.Position) > CoreLoop.Herd.ReorderFarStuds
		local wait = if state.PendingStar then CoreLoop.Herd.PendingStarCooldown else cooldown
		local capped = c.AwakeAll >= CoreLoop.Population.PerHunterAwakeCap
			or serverLoad() >= CoreLoop.Population.TargetWild
			or regionLoad(c.RegionId) >= CoreLoop.Population.PerRegionCap
		if state.Busy then
			continue
		end
		if needs and not capped and t - state.LastOrderAt >= wait then
			-- The old herd is simply left behind: its snacks retire 8 s after going unseen and its
			-- Star keeps its own life timer (A7). Only Camp / death / leaving makes members ambient.
			state.Herd = nil
			state.LastOrderAt = t
			stats.Orders += 1
			local row, regionId = c.Row, c.RegionId
			enqueue(state, function()
				orderHerd(state, row, regionId, t)
				topUpLoners(state, row, regionId)
			end)
		elseif not capped and lonersShort(state) then
			local row, regionId = c.Row, c.RegionId
			enqueue(state, function()
				topUpLoners(state, row, regionId)
			end)
		end
	end
	stats.SectionMs.Hunters = math.max(stats.SectionMs.Hunters, (os.clock() - sectionAt) * 1000)
	stats.SectionTotalMs.Hunters += (os.clock() - sectionAt) * 1000
	sectionAt = os.clock()
	-- The despawn pass runs at half the director rate (2 Hz); its windows are 8-20 s.
	if tickPhase % 2 == 1 then
		stepDespawn(rows, t, snap, if tickPhase == 1 then 0 else 1)
	end
	stats.SectionMs.Despawn = math.max(stats.SectionMs.Despawn, (os.clock() - sectionAt) * 1000)
	Progress.Step() -- combo expiry + x4 magnet (C/D)
	stats.SectionTotalMs.Despawn += (os.clock() - sectionAt) * 1000
	local ms = (os.clock() - started) * 1000
	stats.Ticks += 1
	stats.TickMsTotal += ms
	stats.TickMsPeak = math.max(stats.TickMsPeak, ms)
	debug.profileend()
end

-- A7 Saved: a KO'd herd member / Star / loner within SavedRadius of its owner's cart while that cargo is
-- full sleeps SavedExtraSleep longer and only its owner may take it. Max 1 Star + 2 others per hunter.
trySave = function(entry: Entry)
	local d = CoreLoop.Despawn
	local info = dependencies.GetCartInfo and dependencies.GetCartInfo(entry.OwnerUserId)
	if not info or not info.Full or typeof(info.Position) ~= "Vector3" then
		return
	end
	if flatDistance(info.Position, entry.Model:GetPivot().Position) > d.SavedRadius then
		return
	end
	local stars, snacks = 0, 0
	local t = now()
	for model, other in entries do
		local untilAt = model:GetAttribute("SavedUntil")
		if other.OwnerUserId == entry.OwnerUserId and type(untilAt) == "number" and untilAt > t then
			if other.Role == "Star" then
				stars += 1
			else
				snacks += 1
			end
		end
	end
	if
		(entry.Role == "Star" and stars >= d.SavedMaxStars)
		or (entry.Role ~= "Star" and snacks >= d.SavedMaxSnacks)
	then
		return
	end
	local wakeAt = dependencies.Spawner.ExtendSleep(entry.Model, d.SavedExtraSleep)
	if not wakeAt then
		return
	end
	local remaining = wakeAt - dependencies.Spawner.SleepClock()
	entry.Model:SetAttribute("SavedOwnerUserId", entry.OwnerUserId)
	entry.Model:SetAttribute("SavedUntil", t + remaining)
	stats.Saved += 1
end

local function onHit(player: Player, model: Model, slept: boolean)
	local entry = entries[model]
	local forwarded, err = pcall(Progress.OnHit, player, model, slept, entry)
	if not forwarded then
		warn("[HuntDirector] progress hit failed: " .. tostring(err))
	end
	if not slept then
		return
	end
	stats.KOs += 1
	local state = hunters[player]
	local t = now()
	if state then
		if state.LastKoAt then
			table.insert(stats.KoGaps, t - state.LastKoAt)
			if #stats.KoGaps > 2000 then
				table.remove(stats.KoGaps, 1)
			end
		end
		state.LastKoAt = t
	end
	if dependencies.Analytics then
		pcall(dependencies.Analytics.Record, dependencies.Analytics, player, "CL_KO", 1, nil)
	end
	if entry and entry.Role == "Star" and entry.TrueGrade then
		model:SetAttribute("TrueGrade", entry.TrueGrade) -- revealed on KO (K2)
		if entry.TrueGrade == "Super" or entry.TrueGrade == "Jackpot" then
			entry.SuperPlus = entry.TrueGrade
		end
	end
	if entry and entry.OwnerUserId and entry.Role ~= "Ambient" then
		trySave(entry)
	end
end

function Director.Start(options: any): boolean
	if connection or not CoreLoopFlags.Part("Herds") then
		return false
	end
	assert(
		options and options.Spawner and options.Spawner.SpawnDirected,
		"HuntDirector needs the spawner"
	)
	dependencies = options
	random = options.Random or Random.new()
	if options.SleepSystem and options.SleepSystem.AddHitSubscriber then
		options.SleepSystem.AddHitSubscriber(onHit)
	end
	local interval = 1 / CoreLoop.Population.DirectorHz
	connection = RunService.Heartbeat:Connect(function(dt)
		frameStartedAt = os.clock()
		accumulator += dt
		if accumulator >= interval then
			local step = accumulator
			accumulator = 0
			local ok, err = pcall(tick, step)
			if not ok then
				warn("[HuntDirector] tick failed: " .. tostring(err))
			end
		end
		if #jobs > 0 then
			runJobs()
		end
		if #retireQueue > 0 then
			drainRetireQueue(lastTickRows)
		end
		local frameMs = (os.clock() - frameStartedAt) * 1000 - spawnerMsThisFrame
		spawnerMsThisFrame = 0
		stats.FrameMsPeak = math.max(stats.FrameMsPeak, frameMs)
		stats.Frames += 1
		if frameMs > 2 then
			stats.FramesOver2Ms += 1
		end
		frameRing[frameRingIndex] = frameMs
		frameRingIndex = frameRingIndex % 3600 + 1
	end)
	Players.PlayerRemoving:Connect(function(player)
		local state = hunters[player]
		if state then
			releaseToAmbient(state)
			hunters[player] = nil
		end
	end)
	return true
end

function Director.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

function Director.RushKind(): "Idle" | "Rush" | "Mega"
	return rushKind()
end

-- Part C hook: the next herd for this hunter carries a forced Star (Lucky / pity).
function Director.RequestForcedStar(player: Player, minimum: "Super" | "Jackpot")
	hunterState(player).PendingStar = minimum
end

function Director.GetHuntingSeconds(player: Player): number
	local state = hunters[player]
	return if state then state.HuntingSeconds else 0
end

-- QA (dev only): stats for A-1..A-6, L-1, B-5.
function Director.GetStats(): any
	local copy = table.clone(stats)
	copy.PlacementRejects = table.clone(stats.PlacementRejects)
	copy.SectionMs = table.clone(stats.SectionMs)
	copy.SectionAvgMs = {}
	for name, total in stats.SectionTotalMs do
		copy.SectionAvgMs[name] = if stats.Ticks > 0 then total / stats.Ticks else 0
	end
	local ring = table.clone(frameRing)
	table.sort(ring)
	copy.FrameMsP99 = if #ring > 0 then ring[math.max(1, math.floor(#ring * 0.99))] else nil
	copy.FrameMsP50 = if #ring > 0 then ring[math.max(1, math.floor(#ring * 0.5))] else nil
	copy.HerdSizes = table.clone(stats.HerdSizes)
	copy.StarGrades = table.clone(stats.StarGrades)
	local gaps = table.clone(stats.KoGaps)
	table.sort(gaps)
	copy.KoGaps = nil
	copy.KoGapMedian = if #gaps > 0 then gaps[math.ceil(#gaps / 2)] else nil
	copy.KoGapCount = #gaps
	copy.TickMsAverage = if stats.Ticks > 0 then stats.TickMsTotal / stats.Ticks else 0
	copy.Tracked = 0
	copy.TrackedByRole = {}
	for _, entry in entries do
		copy.Tracked += 1
		copy.TrackedByRole[entry.Role] = (copy.TrackedByRole[entry.Role] or 0) + 1
	end
	copy.Rush = rushKind()
	copy.SuperVisibleShare = if stats.HuntingSecondsTotal > 0
		then stats.SuperVisibleSeconds / stats.HuntingSecondsTotal
		else nil
	copy.Jobs = #jobs
	copy.Spawner = dependencies and dependencies.Spawner.GetDirectedStats() or nil
	return copy
end

function Director._SetVirtualHuntersForQA(provider: (() -> { any })?)
	assert(RunService:IsStudio(), "QA only")
	virtualProvider = provider
end

-- QA: pretend each hunter's cart sits at their character with full cargo (A7 Saved test).
function Director._SetFullCartOverrideForQA(on: boolean)
	assert(RunService:IsStudio(), "QA only")
	if on then
		local original = dependencies.GetCartInfo
		dependencies._OriginalGetCartInfo = dependencies._OriginalGetCartInfo or original
		dependencies.GetCartInfo = function(userId: number)
			local player = Players:GetPlayerByUserId(userId)
			local root = player
				and player.Character
				and player.Character:FindFirstChild("HumanoidRootPart")
			return if root and root:IsA("BasePart")
				then { Position = root.Position, Full = true }
				else nil
		end
	elseif dependencies._OriginalGetCartInfo then
		dependencies.GetCartInfo = dependencies._OriginalGetCartInfo
	end
end

function Director._SetAccessOverrideForQA(value: boolean)
	assert(RunService:IsStudio(), "QA only")
	accessOverride = value
end

function Director._SetRushOverrideForQA(kind: string?)
	assert(RunService:IsStudio(), "QA only")
	rushOverride = kind
end

function Director._ResetStatsForQA()
	assert(RunService:IsStudio(), "QA only")
	stats.Orders, stats.WildHerds, stats.VillageHerds, stats.OrderFailures = 0, 0, 0, 0
	stats.PlacementRejects, stats.Spawned, stats.Loners = {}, 0, 0
	stats.RetiredUnseen, stats.RetiredAmbient, stats.StarsLeft, stats.RetiredInView = 0, 0, 0, 0
	stats.KOs, stats.KoGaps, stats.TickMsTotal, stats.TickMsPeak, stats.Ticks = 0, {}, 0, 0, 0
	stats.HerdSizes, stats.StarGrades = {}, { Star = 0, Super = 0, Jackpot = 0 }
	stats.SpawnChecks, stats.MinPlayerDistanceViolations, stats.MinPadDistanceViolations = 0, 0, 0
	stats.MemberSpacingViolations, stats.HuntingSecondsTotal, stats.SuperVisibleSeconds = 0, 0, 0
	stats.FrameMsPeak, stats.JobsRun, stats.Saved = 0, 0, 0
	stats.SpawnerCallMsPeak, stats.RetireQueuePeak, stats.PlacementCallMsPeak = 0, 0, 0
	stats.SectionMs = { Snapshot = 0, Hunters = 0, Despawn = 0 }
	stats.SectionTotalMs = { Snapshot = 0, Hunters = 0, Despawn = 0 }
	stats.Frames, stats.FramesOver2Ms, stats.PlacementBudgetWaits = 0, 0, 0
	table.clear(frameRing)
	frameRingIndex = 1
end

return Director
