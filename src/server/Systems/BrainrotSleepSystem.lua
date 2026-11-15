--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CartCamera = require(ReplicatedStorage.Shared.Config.CartCamera)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local WeaponCadence = require(ReplicatedStorage.Shared.Utility.WeaponCadence)
local SeatState = require(ReplicatedStorage.Shared.Utility.HumanoidSeatState)
local WeaponStats = require(ReplicatedStorage.Shared.Utility.WeaponStats)
local SleepConfig = require(ReplicatedStorage.Shared.Config.BrainrotSleep)
local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)

local CartService = require(script.Parent.Parent.Services.CartService)
local PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)
local CartOccupantService = require(script.Parent.Parent.Services.CartOccupantService)
local DecoySplit = require(script.Parent.Behaviours.DecoySplit)
local World = require(script.Parent.DevelopmentBrainrotSpawner)
local Roaming = require(script.Parent.DevelopmentBrainrotRoaming)
local CreatureQuery = require(script.Parent.Parent.Utility.CreatureQueryService)
local function authorityRaycast(origin: Vector3, direction: Vector3, params: RaycastParams): any
	local worldHit = Workspace:Raycast(origin, direction, params)
	local shapeHit = CreatureQuery.Raycast(origin, direction, params)
	return if shapeHit and (not worldHit or shapeHit.Distance < worldHit.Distance) then shapeHit else worldHit
end

local CAMERA_POSITION_TOLERANCE = 8 -- Avatar focus, camera smoothing and replication allowance.
local UNIT_DIRECTION_TOLERANCE = 0.01
local SURFACE_TOLERANCE = 0.01
local MIN_FORWARD_AIM_DOT = 0.5 -- At most 60 degrees of near-muzzle parallax, not aim assist.

type FiringContext = { Cart: Model?, Character: Model, Origin: Vector3, AcceptedRequestId: number? }
type Shot = { Origin: Vector3, Endpoint: Vector3, WeaponProfile: any }
type HuntCandidate = {
	Model: Model,
	Record: World.WorldRecord,
	Body: BasePart,
	Parts: { [Instance]: boolean },
	Depth: number,
}
type ResolvedShotAim = {
	Mode: "ASSIST_LOCK" | "CROSSHAIR_FREE",
	Direction: Vector3,
	AimPoint: Vector3,
	Candidate: HuntCandidate?,
	LockedTargetId: string?,
	LockedTargetKind: string?,
	FallbackReason: string?,
}

local BrainrotSleepSystem = {}
local started = false
local interestService: any = nil
function BrainrotSleepSystem.SetInterestService(service: any)
	interestService = service
end
local impactHandler: any = nil
local actionValidator: any = nil
local semanticObstruction: any = nil
local sleepRequestRemote: RemoteEvent? = nil
local shotTiming: { [Player]: any } = {}
local lastAcceptedRequestId: { [Player]: number } = {}
local isCarrying: ((Player) -> boolean)? = nil
local regionAccessValidator: ((Player, Model) -> (boolean, string?))? = nil
local weaponProfileResolver: ((Player) -> (any, number?))? = nil
local cartHitMultiplierResolver: ((Model) -> number)? = nil
local requiredHitsResolver: ((string) -> number?)? = nil
-- Weak target keys do not retain departed world models. Record identity and
-- lifecycle revision reset progress after sleep/wake or a representation change.
local targetHealth: { [Model]: any } = setmetatable({}, { __mode = "k" })
local nowProvider: () -> number = os.clock
local connections: { RBXScriptConnection } = {}
local ownsRemote = false
local DEFAULT_WEAPON_PROFILE = WeaponStats.Resolve(Weapons.StarterWeaponId)
assert(WeaponStats.IsReady(DEFAULT_WEAPON_PROFILE), "Starter weapon profile must be valid")

-- Phase 3 can supply its authoritative read-only predicate without a cyclic
-- require or trusting a client/replicated carry flag. No carry system is added here.
function BrainrotSleepSystem.SetRegionAccessValidator(validator: ((Player, Model) -> (boolean, string?))?)
	regionAccessValidator = validator
end

function BrainrotSleepSystem.SetSemanticObstructionResolver(resolver: any)
	semanticObstruction = resolver
end
function BrainrotSleepSystem.SetImpactHandler(handler: any)
	impactHandler = handler
end
function BrainrotSleepSystem.SetActionValidator(validator: any)
	actionValidator = validator
end

-- Read-only observer for accepted brainrot hits (villager guards). It runs deferred,
-- after the hit is fully committed, and cannot change damage, sleep or acquisition.
local hitObserver: ((Player, Model, boolean) -> ())? = nil
-- Core Loop V2: extra accepted-hit subscribers (HuntDirector KO telemetry). The single villager
-- observer above is unchanged.
local coreLoopHitObservers: { (Player, Model, boolean) -> () } = {}
function BrainrotSleepSystem.AddHitSubscriber(observer: (Player, Model, boolean) -> ())
	table.insert(coreLoopHitObservers, observer)
end
-- Core Loop V2 (B2): told when a shot hit another player's exclusive Star (dealt 0).
local coreLoopNotYoursObservers: { (Player, Model) -> () } = {}
function BrainrotSleepSystem.AddNotYoursSubscriber(observer: (Player, Model) -> ())
	table.insert(coreLoopNotYoursObservers, observer)
end

function BrainrotSleepSystem.SetHitObserver(observer: ((Player, Model, boolean) -> ())?)
	hitObserver = observer
end

function BrainrotSleepSystem.SetCarryingPredicate(predicate: ((Player) -> boolean)?)
	isCarrying = predicate
end

-- Phase 7E selection can inject the current server-owned profile without
-- coupling current sleeping to persistence. Nil preserves the starter-only
-- production state. Tests may inject approved fixtures and must restore nil.
function BrainrotSleepSystem.SetWeaponProfileResolver(resolver: ((Player) -> (any, number?))?)
	weaponProfileResolver = resolver
end

-- The team service supplies a read-only owner lookup for the occupied cart.
-- Authorization remains in resolveFiringContext; an on-foot launcher uses ×1.
function BrainrotSleepSystem.SetCartHitMultiplierResolver(resolver: ((Model) -> number)?)
	cartHitMultiplierResolver = resolver
end

-- Isolated test/future-tuning adapter. Current released configuration remains
-- explicitly one hit for all 35 species; nil restores that configuration.
function BrainrotSleepSystem.SetRequiredHitsResolver(resolver: ((string) -> number?)?)
	requiredHitsResolver = resolver
end

-- regionId (the record's immutable spawn region) only matters when Weapon Tiers V2 is on; the
-- normal path reads the individual's stored Phase12 MaxHp instead of calling this.
local function resolveRequiredHits(speciesId: string, regionId: string?): number
	if requiredHitsResolver then
		local ok, required = pcall(requiredHitsResolver, speciesId)
		if ok and type(required) == "number" and required == required and required > 0 and required < math.huge then
			return required
		end
	end
	local id = BrainrotCatalog.NormalizeId(speciesId)
	return if Phase12.Enabled and id
		then Phase12Rules.HpForSpecies(id, regionId) or SleepConfig.DefaultRequiredHits
		elseif id then SleepConfig.RequiredHitsBySpecies[id] or SleepConfig.DefaultRequiredHits
		else SleepConfig.DefaultRequiredHits
end

local function resolveHitMultiplier(cart: Model?): number
	if cart and cartHitMultiplierResolver then
		local ok, multiplier = pcall(cartHitMultiplierResolver, cart)
		if
			ok
			and type(multiplier) == "number"
			and multiplier == multiplier
			and multiplier >= 1
			and multiplier < math.huge
		then
			return math.min(multiplier, SleepConfig.MaximumHitMultiplier)
		end
	end
	return 1
end

function BrainrotSleepSystem.SetNowProvider(provider: (() -> number)?)
	nowProvider = provider or os.clock
end

local function resolveWeaponProfile(player: Player): (any?, string?)
	local profile, equipmentRevision
	if weaponProfileResolver then
		local ok, resolved, revision = pcall(weaponProfileResolver, player)
		if not ok then
			return nil, "weapon profile unavailable"
		end
		profile, equipmentRevision = resolved, revision
	else
		local data = PlayerDataService:GetReadableData(player)
		profile = WeaponStats.GetSelected(data)
		equipmentRevision = if type(data) == "table" and type(data.Phase13) == "table"
			then data.Phase13.EligibilityRevision or 0
			else 0
	end
	local captured = WeaponStats.CaptureShotProfile(profile, equipmentRevision)
	if not captured then
		return nil, "weapon profile unavailable"
	end
	return captured, nil
end

local function isLauncher(tool: Instance): boolean
	return tool:IsA("Tool") and tool.Name == "SleepLauncher" and tool:GetAttribute("BrainrotSleepLauncher") == true
end

local function hasOtherWeapon(character: Model): boolean
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and not isLauncher(child) then
			return true
		end
	end
	return false
end

local function finiteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and math.abs(value.X) < math.huge
		and value.Y == value.Y
		and math.abs(value.Y) < math.huge
		and value.Z == value.Z
		and math.abs(value.Z) < math.huge
end

local function getSleepRequestRemote(): RemoteEvent
	if sleepRequestRemote and sleepRequestRemote.Parent then
		return sleepRequestRemote
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	local remote = remotes:FindFirstChild("SleepRequest")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "SleepRequest"
		remote.Parent = remotes
		ownsRemote = true
	end
	assert(remote:IsA("RemoteEvent"), "SleepRequest must be a RemoteEvent")
	sleepRequestRemote = remote
	return remote
end

local function resolveFiringContext(player: Player): (FiringContext?, string?)
	if actionValidator then
		local allowed, reason = actionValidator(player)
		if not allowed then
			return nil, reason or "Controls disabled"
		end
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if
		player.Parent ~= Players
		or not character
		or not character:IsDescendantOf(Workspace)
		or not humanoid
		or humanoid.Health <= 0
	then
		return nil, "not living"
	end
	if isCarrying and isCarrying(player) then
		return nil, "carrying"
	end
	local seat = humanoid.SeatPart
	-- Only genuinely on-foot characters can fall back to their equipped Tool.
	-- An unauthorized seat context must not bypass mounted restrictions.
	if not SeatState.IsSeated(humanoid) then
		local launcher: Tool? = nil
		for _, child in character:GetChildren() do
			if isLauncher(child) then
				if launcher ~= nil then
					return nil, "multiple launchers equipped"
				end
				launcher = child :: Tool
			end
		end
		if not launcher or not launcher.Enabled then
			return nil, "launcher not equipped"
		end
		if hasOtherWeapon(character) then
			return nil, "using another weapon"
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if
			not root
			or not root:IsA("BasePart")
			or (root.AssemblyRootPart and not root.AssemblyRootPart:IsDescendantOf(character))
		then
			return nil, "not on foot"
		end
		local handle = launcher:FindFirstChild("Handle")
		local muzzle = if handle then handle:FindFirstChild("Muzzle") else nil
		if
			not handle
			or not handle:IsA("BasePart")
			or not muzzle
			or not muzzle:IsA("Attachment")
			or not finiteVector(muzzle.WorldPosition)
		then
			return nil, "no valid launcher muzzle"
		end
		return { Character = character, Origin = muzzle.WorldPosition }, nil
	end
	if not seat or not (seat:IsA("Seat") or seat:IsA("VehicleSeat")) or seat.Occupant ~= humanoid then
		return nil, "not mounted"
	end

	-- Resolve the canonical cart owned by this player, then re-read its actual
	-- DriverSeat occupancy and current server authority before every shot.
	local record = CartService:GetCartRecord(player)
	local cart = if record then record.Model else nil
	if
		not record
		or not cart
		or record.OwnerUserId ~= player.UserId
		or not cart:IsDescendantOf(Workspace)
		or cart:GetAttribute("RuntimeCart") ~= true
	then
		return nil, "no registered owned cart"
	end
	local driverSeat = cart:FindFirstChild("DriverSeat")
	if
		seat ~= driverSeat
		or not seat:IsA("VehicleSeat")
		or not CartOccupantService:CanPlayerControlCart(player, cart)
	then
		return nil, "not authorized owner driver"
	end

	local muzzle = cart:FindFirstChild("HarpoonOrigin", true)
	local origin = if muzzle and muzzle:IsA("Attachment")
		then muzzle.WorldPosition
		elseif muzzle and muzzle:IsA("BasePart") then muzzle.Position
		else nil
	if not finiteVector(origin) then
		return nil, "no valid HarpoonOrigin"
	end
	return { Cart = cart, Character = character, Origin = origin :: Vector3 }, nil
end

function BrainrotSleepSystem.ValidateFiringContext(player: Player, expected: any): boolean
	local current = resolveFiringContext(player)
	return current ~= nil and current.Character == expected.Character and current.Cart == expected.Cart
end

local function resolveCentredAim(
	player: Player,
	context: FiringContext,
	cameraOrigin: Vector3,
	cameraDirection: Vector3,
	params: RaycastParams,
	weaponRangeStuds: number
): (Vector3?, string?)
	local root = context.Character:FindFirstChild("HumanoidRootPart")
	local head = context.Character:FindFirstChild("Head")
	local focus = if head and head:IsA("BasePart") then head else root
	if not focus or not focus:IsA("BasePart") then
		return nil, "no camera focus"
	end
	local focusPosition = focus.Position
	local maximumOffset = player.CameraMaxZoomDistance
	if context.Cart then
		local target = context.Cart:FindFirstChild("CameraTarget")
		if target and target:IsA("BasePart") then
			focusPosition = target.Position
		end
		-- Use the existing camera envelope and supported default zoom.
		-- Do not assume every third-person camera sits next to the muzzle.
		maximumOffset = math.max(
			maximumOffset,
			math.max(CartCamera.Distance, CartCamera.MobileDistance) + math.abs(CartCamera.HeightOffset)
		)
	else
		local humanoid = context.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			maximumOffset += humanoid.CameraOffset.Magnitude
		end
	end
	if (cameraOrigin - focusPosition).Magnitude > maximumOffset + CAMERA_POSITION_TOLERANCE then
		return nil, "camera origin outside permitted offset"
	end

	-- Far forward intersection of C + tD with the accepted shot-profile sphere
	-- about M. The range is captured once and never reread after acceptance.
	-- Clamping a distant camera point along a DIFFERENT muzzle ray leaves a
	-- sideways miss. This endpoint remains on the submitted centre-camera line.
	local cameraFromMuzzle = cameraOrigin - context.Origin
	local projection = cameraFromMuzzle:Dot(cameraDirection)
	local discriminant = projection * projection
		- (cameraFromMuzzle:Dot(cameraFromMuzzle) - weaponRangeStuds * weaponRangeStuds)
	if discriminant < 0 then
		return nil, "camera ray misses weapon range"
	end
	local depth = -projection + math.sqrt(discriminant)
	if depth <= SURFACE_TOLERANCE then
		return nil, "no forward aim in weapon range"
	end
	local cameraHit = authorityRaycast(cameraOrigin, cameraDirection * depth, params)
	local point = if cameraHit then cameraHit.Position else cameraOrigin + cameraDirection * depth
	local offset = point - context.Origin
	if offset:Dot(cameraDirection) <= SURFACE_TOLERANCE then
		return nil, "camera obstruction behind muzzle"
	end
	if offset.Magnitude > weaponRangeStuds + SURFACE_TOLERANCE then
		return nil, "camera obstruction outside weapon range"
	end
	-- A point barely ahead of the muzzle but far to its side otherwise passes
	-- the positive-dot test and sends a nearly lateral shot across the avatar.
	-- Reject that close geometry; do NOT skip its wall or substitute a far point.
	if offset.Unit:Dot(cameraDirection) < MIN_FORWARD_AIM_DOT then
		return nil, "aim point too close to muzzle plane"
	end
	return point, nil
end

-- Slab intersection in model-local coordinates. The interval is clipped to
-- forward, muzzle-reachable centre-ray depths before choosing a target.
local function intersectHuntBounds(
	cameraOrigin: Vector3,
	cameraDirection: Vector3,
	frame: CFrame,
	size: Vector3,
	minimumDepth: number,
	maximumDepth: number
): number?
	local origin = frame:PointToObjectSpace(cameraOrigin)
	local direction = frame:VectorToObjectSpace(cameraDirection)
	local half = size / 2
	local near, far = minimumDepth, maximumDepth
	for _, axis in { "X", "Y", "Z" } do
		local o, d, h = origin[axis], direction[axis], half[axis]
		if math.abs(d) < 1e-8 then
			if math.abs(o) > h then
				return nil
			end
		else
			local a, b = (-h - o) / d, (h - o) / d
			near, far = math.max(near, math.min(a, b)), math.min(far, math.max(a, b))
		end
		if far < near then
			return nil
		end
	end
	return near
end

local function hasHuntLineOfSight(
	candidate: HuntCandidate,
	muzzle: Vector3,
	cameraOrigin: Vector3,
	cameraDirection: Vector3,
	params: RaycastParams,
	weaponRangeStuds: number
): boolean
	-- The real Body centre is the reference, never an exposed invisible-box edge.
	-- Mesh centres can be hollow: require the absence of foreign cover, not a
	-- mandatory ray hit on a surface at the centre. Keep the visible near surface
	-- when present so range behavior at the existing boundary is unchanged.
	local toBody = candidate.Body.Position - cameraOrigin
	if toBody:Dot(cameraDirection) <= SURFACE_TOLERANCE then
		return false
	end
	local cameraHit = authorityRaycast(cameraOrigin, toBody.Unit * (toBody.Magnitude + SURFACE_TOLERANCE), params)
	if
		cameraHit
		and (
			not candidate.Parts[cameraHit.Instance]
			or (type(cameraHit) == "table" and cameraHit.QueryPartHuntEligible == false)
		)
	then
		return false
	end
	local reference = if cameraHit then cameraHit.Position else candidate.Body.Position
	local toReference = reference - muzzle
	if
		toReference:Dot(cameraDirection) <= SURFACE_TOLERANCE
		or toReference.Magnitude > weaponRangeStuds + SURFACE_TOLERANCE
	then
		return false
	end
	local muzzleHit = authorityRaycast(
		muzzle,
		toReference.Unit * math.min(toReference.Magnitude + SURFACE_TOLERANCE, weaponRangeStuds),
		params
	)
	if
		muzzleHit
		and (
			not candidate.Parts[muzzleHit.Instance]
			or (type(muzzleHit) == "table" and muzzleHit.QueryPartHuntEligible == false)
		)
	then
		return false
	end

	local endpoint = cameraOrigin + cameraDirection * candidate.Depth
	local toEndpoint = endpoint - muzzle
	if
		toEndpoint.Magnitude <= SURFACE_TOLERANCE
		or toEndpoint.Magnitude > weaponRangeStuds + SURFACE_TOLERANCE
		or toEndpoint.Unit:Dot(cameraDirection) < MIN_FORWARD_AIM_DOT
	then
		return false
	end
	-- The camera path is already capped at A2's first world obstruction. Also
	-- test the NEW muzzle-to-centred-depth segment, not just the old far shot.
	local obstruction = authorityRaycast(muzzle, toEndpoint, params)
	return obstruction == nil or obstruction.Distance >= toEndpoint.Magnitude - SURFACE_TOLERANCE
end

-- Only enlarged-bound intersections: camera tracking changes the displayed aim,
-- never a hidden server padding/retargeting fallback.
function BrainrotSleepSystem.FindCentredHuntTarget(
	muzzle: Vector3,
	cameraOrigin: Vector3,
	cameraDirection: Vector3,
	aimPoint: Vector3,
	params: RaycastParams,
	weaponRangeStuds: number?,
	expectedItemId: string?,
	allowSleeping: boolean?
): HuntCandidate?
	if not CreatureQuery.SyncWorld(World.GetWorldModels()) then
		return nil
	end
	local resolvedRange = weaponRangeStuds or DEFAULT_WEAPON_PROFILE.rangeStuds
	if
		type(resolvedRange) ~= "number"
		or resolvedRange ~= resolvedRange
		or resolvedRange <= 0
		or math.abs(resolvedRange) == math.huge
	then
		return nil
	end
	local fromMuzzle = cameraOrigin - muzzle
	local axial = fromMuzzle:Dot(cameraDirection)
	local lateral = (fromMuzzle - cameraDirection * axial).Magnitude
	if lateral > resolvedRange then
		return nil
	end
	-- Leave a few tolerance units beyond the muzzle plane. A camera/muzzle
	-- already inside a large box must not produce a zero-length shot; world
	-- coordinate precision can round an exact 0.01-stud endpoint below tolerance.
	local minimumDepth = math.max(
		SURFACE_TOLERANCE * 4,
		-axial - math.sqrt(resolvedRange * resolvedRange - lateral * lateral),
		-axial + lateral * MIN_FORWARD_AIM_DOT / math.sqrt(1 - MIN_FORWARD_AIM_DOT ^ 2) + SURFACE_TOLERANCE * 4
	)
	local maximumDepth = (aimPoint - cameraOrigin):Dot(cameraDirection)
	local direct: { HuntCandidate } = {}
	-- This is the existing lifecycle registry, evaluated only on an accepted
	-- shot. No target cache/second registry or per-frame Workspace discovery.
	for _, model in World.GetWorldModels() do
		local record, state = World.GetWorldRecord(model)
		if
			not record
			or (state ~= "WorldAwake" and not (allowSleeping and state == "WorldSleeping"))
			or (expectedItemId ~= nil and record.ItemId ~= expectedItemId)
		then
			continue
		end
		local frame, size, body, parts = World.GetHuntBounds(model, record)
		if not frame or not size or not body or not parts then
			continue
		end
		local bodyDepth = (body.Position - cameraOrigin):Dot(cameraDirection)
		if bodyDepth <= SURFACE_TOLERANCE then
			continue
		end
		local function intersect(): number?
			return intersectHuntBounds(cameraOrigin, cameraDirection, frame, size, minimumDepth, maximumDepth)
		end
		local depth = intersect()
		if depth then
			table.insert(direct, {
				Model = model,
				Record = record,
				Body = body,
				Parts = parts,
				Depth = depth,
			})
		end
	end
	local function order(a: HuntCandidate, b: HuntCandidate): boolean
		-- Quantise only sub-millistud noise for a transitive, deterministic sort.
		local aDepth, bDepth = math.round(a.Depth * 1000), math.round(b.Depth * 1000)
		if aDepth ~= bDepth then
			return aDepth < bDepth
		end
		return a.Record.ItemId < b.Record.ItemId
	end
	table.sort(direct, order)
	for _, candidate in direct do
		if hasHuntLineOfSight(candidate, muzzle, cameraOrigin, cameraDirection, params, resolvedRange) then
			return candidate
		end
	end
	return nil
end

local function normalizedDirection(value: any): Vector3?
	if not finiteVector(value) then
		return nil
	end
	local magnitude = value.Magnitude
	if math.abs(magnitude - 1) > UNIT_DIRECTION_TOLERANCE then
		return nil
	end
	return value / magnitude
end

local function withinAssistCone(left: Vector3, right: Vector3, halfAngle: number): boolean
	return left:Dot(right) >= math.cos(halfAngle + UNIT_DIRECTION_TOLERANCE)
end

local function resolveShotAim(
	player: Player,
	context: FiringContext,
	intent: any,
	params: RaycastParams,
	profile: any,
	submittedDirection: Vector3,
	crosshairDirection: Vector3
): (ResolvedShotAim?, string?)
	local function free(reason: string?): (ResolvedShotAim?, string?)
		local point, failure =
			resolveCentredAim(player, context, intent.CameraOrigin, crosshairDirection, params, profile.rangeStuds)
		if not point then
			return nil, failure
		end
		return {
			Mode = "CROSSHAIR_FREE",
			Direction = crosshairDirection,
			AimPoint = point,
			Candidate = nil,
			LockedTargetId = nil,
			LockedTargetKind = nil,
			FallbackReason = reason,
		},
			nil
	end

	local mode = intent.ShotMode
	if mode == nil then
		mode = "CROSSHAIR_FREE" -- Compatible with accepted pre-snapshot clients/tests.
	end
	if mode ~= "ASSIST_LOCK" and mode ~= "CROSSHAIR_FREE" then
		return nil, "invalid shot mode"
	end
	if mode == "CROSSHAIR_FREE" then
		return free(nil)
	end

	local targetId = intent.LockedTargetId
	local targetKind = intent.LockedTargetKind
	if type(targetId) ~= "string" or targetId == "" or (targetKind ~= "Brainrot" and targetKind ~= "Decoy") then
		return free("INVALID_LOCK_IDENTITY")
	end

	local targetPoint: Vector3?
	local candidate: HuntCandidate? = nil
	if targetKind == "Brainrot" then
		local model, record, state = World.GetWorldModelById(targetId)
		if
			model == nil
			or record == nil
			or (state ~= "WorldAwake" and state ~= "WorldSleeping")
			or (state == "WorldAwake" and not Roaming.IsAimAssistEligible(model))
		then
			return free("LOCK_NOT_AVAILABLE")
		end
		local _, _, body = World.GetHuntBounds(model, record)
		if body == nil then
			return free("LOCK_GEOMETRY_UNAVAILABLE")
		end
		targetPoint = body.Position
	else
		local _, proxy = DecoySplit.GetActiveTarget(targetId)
		if proxy == nil then
			return free("LOCK_NOT_AVAILABLE")
		end
		targetPoint = proxy.Position
	end

	local cameraOffset = (targetPoint :: Vector3) - intent.CameraOrigin
	local muzzleOffset = (targetPoint :: Vector3) - context.Origin
	if
		cameraOffset.Magnitude <= SURFACE_TOLERANCE
		or muzzleOffset.Magnitude <= SURFACE_TOLERANCE
		or muzzleOffset.Magnitude > profile.rangeStuds + SURFACE_TOLERANCE
	then
		return free("LOCK_OUT_OF_RANGE")
	end
	local targetDirection = cameraOffset.Unit
	if
		not withinAssistCone(crosshairDirection, targetDirection, profile.assistRetainHalfAngleRadians)
		or not withinAssistCone(submittedDirection, targetDirection, profile.assistRetainHalfAngleRadians)
	then
		return free("LOCK_OUTSIDE_ASSIST_CONE")
	end
	local point, failure =
		resolveCentredAim(player, context, intent.CameraOrigin, targetDirection, params, profile.rangeStuds)
	if not point then
		return free("LOCK_" .. tostring(failure))
	end

	if targetKind == "Brainrot" then
		candidate = BrainrotSleepSystem.FindCentredHuntTarget(
			context.Origin,
			intent.CameraOrigin,
			targetDirection,
			point,
			params,
			profile.rangeStuds,
			targetId,
			true
		)
		if candidate == nil then
			return free("LOCK_LINE_OF_SIGHT_BLOCKED")
		end
	else
		local cameraHit = authorityRaycast(
			intent.CameraOrigin,
			targetDirection * math.min(cameraOffset.Magnitude + SURFACE_TOLERANCE, profile.rangeStuds),
			params
		)
		local classification, decoyId = "NotDecoy", nil
		if cameraHit then
			classification, decoyId = DecoySplit.ResolveHit(cameraHit.Instance)
		end
		if classification ~= "Active" or decoyId ~= targetId then
			return free("LOCK_LINE_OF_SIGHT_BLOCKED")
		end
	end

	return {
		Mode = "ASSIST_LOCK",
		Direction = targetDirection,
		AimPoint = point,
		Candidate = candidate,
		LockedTargetId = targetId,
		LockedTargetKind = targetKind,
		FallbackReason = nil,
	},
		nil
end

-- One shared server implementation. Only the RemoteEvent supplies the Player;
-- the client supplies a camera WORLD POINT and UNIT DIRECTION, never a hit,
-- weapon origin, cart or sleep state. Exact client pixels cannot be proven here.
local function handleFireRequest(player: Player, intent: any, decision: any): (Shot?, string?)
	if type(intent) ~= "table" or not finiteVector(intent.CameraOrigin) then
		return nil, "invalid aim"
	end
	local submittedDirection = normalizedDirection(intent.CameraDirection)
	if not submittedDirection then
		return nil, "invalid camera direction"
	end
	local crosshairDirection = if intent.CrosshairDirection == nil
		then submittedDirection
		else normalizedDirection(intent.CrosshairDirection)
	if not crosshairDirection then
		return nil, "invalid crosshair direction"
	end
	local profile, profileReason = resolveWeaponProfile(player)
	if not profile then
		return nil, profileReason
	end
	decision.WeaponId = profile.weaponId
	decision.EquipmentRevision = profile.equipmentRevision
	decision.RangeStuds = profile.rangeStuds
	decision.FireIntervalSeconds = profile.fireIntervalSeconds
	decision.ProjectileSpeedStudsPerSecond = profile.projectileSpeedStudsPerSecond
	decision.ProjectileSpeedAuthority = profile.projectileSpeedAuthority
	local requestId = decision.RequestId
	if requestId ~= nil and lastAcceptedRequestId[player] ~= nil and requestId <= lastAcceptedRequestId[player] then
		return nil, "duplicate request"
	end
	local now = nowProvider()
	local cadenceReady = WeaponCadence.CanAccept(shotTiming[player], now, profile.fireIntervalSeconds)
	if not cadenceReady then
		return nil, "cooldown"
	end
	local context, reason = resolveFiringContext(player)
	if not context then
		return nil, reason
	end
	local queryReady = CreatureQuery.SyncWorld(World.GetWorldModels())
	if not queryReady then
		return nil, "authority query unavailable"
	end
	decision.Context = if context.Cart then "mounted" else "handheld"
	decision.Muzzle = tostring(context.Origin)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = { context.Character }
	if context.Cart then
		table.insert(excluded, context.Cart)
	end
	local ownCart = CartService:GetCart(player)
	if ownCart and ownCart ~= context.Cart and ownCart:GetAttribute("OwnerUserId") == player.UserId then
		table.insert(excluded, ownCart)
	end
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = false
	params.RespectCanCollide = false -- Non-queryable beams/carry/cargo/base displays stay cosmetic.
	local resolvedAim, aimReason =
		resolveShotAim(player, context, intent, params, profile, submittedDirection, crosshairDirection)
	if not resolvedAim then
		return nil, aimReason
	end
	if resolvedAim.Candidate and regionAccessValidator then
		local allowed, accessReason = regionAccessValidator(player, resolvedAim.Candidate.Model)
		if not allowed then
			return nil, accessReason or "RegionAccessRequired"
		end
	end
	local cameraDirection = resolvedAim.Direction
	local aimPoint = resolvedAim.AimPoint
	decision.ShotMode = resolvedAim.Mode
	decision.LockedTargetId = resolvedAim.LockedTargetId
	decision.LockedTargetKind = resolvedAim.LockedTargetKind
	decision.LockFallbackReason = resolvedAim.FallbackReason
	local offset = aimPoint - context.Origin
	local distance = offset.Magnitude
	if distance <= SURFACE_TOLERANCE then
		return nil, "invalid aim"
	end
	local acceptedTiming = WeaponCadence.Accept(now, profile.fireIntervalSeconds)
	if not acceptedTiming then
		return nil, "weapon cadence unavailable"
	end
	shotTiming[player] = acceptedTiming
	if requestId ~= nil then
		lastAcceptedRequestId[player] = requestId
	end
	-- Copy the immutable accepted identity from the server cadence/replay ledger
	-- into its own firing context. Downstream cargo protection never authorizes a
	-- shot from a client-provided identity alone.
	context.AcceptedRequestId = requestId
	-- This is an obstruction query, NOT a brainrot whitelist. Walls, terrain,
	-- other carts and already-sleeping bodies still stop the shot.
	-- Tiny surface tolerance avoids missing the camera's exact surface point;
	-- the actual muzzle query is never longer than the existing weapon range.
	local direction = offset / distance * math.min(distance + SURFACE_TOLERANCE, profile.rangeStuds)
	local hit = authorityRaycast(context.Origin, direction, params)
	local endpoint = if hit then hit.Position else aimPoint
	if semanticObstruction then
		local barrier = semanticObstruction(player, context.Origin, endpoint)
		if barrier then
			decision.ImpactKind = "WorldHit"
			decision.Obstruction = barrier.Instance:GetFullName()
			decision.Phase10Message = "Region gate blocks this shot."
			decision.Slept = false
			return { Origin = context.Origin, Endpoint = barrier.Position, WeaponProfile = profile }, nil
		end
	end
	decision.Obstruction = if hit then hit.Instance:GetFullName() else "none"
	if hit then
		-- Temporary effects are classified before the ordinary collectible lookup.
		-- A decoy is a terminal, non-piercing impact and its owner is never used as
		-- a wild-sleep fallback. Stale effect objects remain terminal as well.
		local decoyKind = DecoySplit.ResolveHit(hit.Instance)
		if decoyKind == "Active" then
			local consumed, decoyId = DecoySplit.OnValidatedDecoyHit(hit.Instance, now)
			decision.ImpactKind = if consumed then "DecoyHit" else "RejectedOrStaleDecoy"
			decision.DecoyId = decoyId
			decision.Slept = false
			return { Origin = context.Origin, Endpoint = endpoint, WeaponProfile = profile }, nil
		elseif decoyKind == "Stale" then
			decision.ImpactKind = "RejectedOrStaleDecoy"
			decision.Slept = false
			return { Origin = context.Origin, Endpoint = endpoint, WeaponProfile = profile }, nil
		end
	end
	-- A special impact is terminal. The released representation is never fed
	-- back into this accepted shot's wild sleep search.
	if hit and impactHandler then
		local cameraHit = authorityRaycast(intent.CameraOrigin, crosshairDirection * profile.rangeStuds, params)
		local handled, outcome, message = impactHandler(player, context, hit, cameraHit, intent)
		if handled then
			decision.ImpactKind = outcome or "ProtectedTarget"
			decision.Phase10Message = message
			decision.Slept = false
			return { Origin = context.Origin, Endpoint = endpoint, WeaponProfile = profile }, nil
		end
	end
	local candidate = resolvedAim.Candidate
	if resolvedAim.Mode == "CROSSHAIR_FREE" then
		candidate = BrainrotSleepSystem.FindCentredHuntTarget(
			context.Origin,
			intent.CameraOrigin,
			cameraDirection,
			aimPoint,
			params,
			profile.rangeStuds
		)
	end
	local target = if candidate then candidate.Model else nil
	decision.ItemId = if candidate then candidate.Record.ItemId else nil
	decision.Depth = if candidate then candidate.Depth else nil
	local slept = false
	local alreadySleeping = false
	local progressed = false
	if candidate then
		if regionAccessValidator then
			local allowed, accessReason = regionAccessValidator(player, candidate.Model)
			if not allowed then
				return nil, accessReason or "RegionAccessRequired"
			end
		end
		-- Core Loop V2 (B2): for 20 s after spawn only the owner's shots damage a Star. Others still fire
		-- (one validated shot, same endpoints) but deal 0. Attributes exist only when the director runs.
		local exclusiveUntil = candidate.Model:GetAttribute("StarExclusiveUntil")
		local starOwner = candidate.Model:GetAttribute("StarOwnerUserId")
		local notYours = type(exclusiveUntil) == "number"
			and type(starOwner) == "number"
			and starOwner ~= player.UserId
			and Workspace:GetServerTimeNow() < exclusiveUntil
		decision.NotYours = notYours or nil
		-- No yield between this identity/state recheck and the single mutation.
		local record, state = World.GetWorldRecord(candidate.Model)
		if notYours then
			endpoint = intent.CameraOrigin + cameraDirection * candidate.Depth
			for _, observer in coreLoopNotYoursObservers do
				task.defer(observer, player, candidate.Model)
			end
		elseif record == candidate.Record and state == "WorldAwake" then
			local hpState = if Phase12.Enabled and World.GetPhase12State then World.GetPhase12State(record) else nil
			local previous = targetHealth[candidate.Model]
			local revision = candidate.Model:GetAttribute("BrainrotLifecycleRevision")
			local maximum = if hpState
				then hpState.MaxHp
				else resolveRequiredHits(
					record.BrainrotId,
					record.World and record.World.SpawnRegionId
				)
			local remaining = if hpState
				then hpState.RemainingHp
				elseif
					previous
					and previous.Record == record
					and previous.Revision == revision
				then previous.RemainingHp
				else maximum
			local multiplier = resolveHitMultiplier(context.Cart)
			-- Current shooting-to-sleep health, independent of the retired capture meter.
			local nextHp = Phase12Rules.Damage(remaining, maximum, multiplier, profile.damage)
			if nextHp ~= nil then
				progressed = true
				targetHealth[candidate.Model] = { Record = record, Revision = revision, RemainingHp = nextHp }
				if hpState then
					World.UpdatePhase12State(record, { RemainingHp = nextHp })
				end
				candidate.Model:SetAttribute("Phase12MaxHp", maximum)
				candidate.Model:SetAttribute("Phase12RemainingHp", nextHp)
				decision.HitMultiplier = multiplier
				candidate.Model:SetAttribute("Phase13LastDamageAt", Workspace:GetServerTimeNow())
				decision.BaseDamage = profile.damage
				decision.AcceptedDamage = math.min(remaining, (profile.damage or 1) * multiplier)
				if World.NotifyAcceptedDamage and nextHp < remaining then
					World.NotifyAcceptedDamage(record, Workspace:GetServerTimeNow())
				end
				decision.RemainingHp = nextHp
				decision.MaxHp = maximum
				if nextHp <= 0 then
					slept = World.TrySleep(candidate.Model)
					if slept then
						if hpState then
							World.UpdatePhase12State(record, { CapturedOnce = true, RemainingHp = 0 })
						end
						candidate.Model:SetAttribute("Phase12CapturedOnce", true)
					else
						local currentRecord, currentState = World.GetWorldRecord(candidate.Model)
						alreadySleeping = currentRecord == candidate.Record and currentState == "WorldSleeping"
					end
				end
			end
		elseif record == candidate.Record and state == "WorldSleeping" then
			alreadySleeping = true
		end
		if progressed or slept or alreadySleeping then
			endpoint = intent.CameraOrigin + cameraDirection * candidate.Depth
		end
	end
	if hitObserver and candidate and (progressed or slept) then
		task.defer(hitObserver, player, candidate.Model, slept)
	end
	if candidate and (progressed or slept) then
		for _, observer in coreLoopHitObservers do
			task.defer(observer, player, candidate.Model, slept)
		end
	end
	decision.Slept = slept
	decision.Target = if target then target.Name else nil
	decision.ImpactKind = if decision.NotYours
		then "NotYours"
		elseif slept
		then "BrainrotHit"
		elseif alreadySleeping then "AlreadySleeping"
		elseif progressed then "BrainrotDamageHit"
		elseif hit then "WorldHit"
		else "Miss"

	-- Reuse the existing result direction of SleepRequest. Every accepted shot,
	-- including misses, sends exactly one pair of fixed endpoints to all viewers.
	return { Origin = context.Origin, Endpoint = endpoint, WeaponProfile = profile }, nil
end

function BrainrotSleepSystem.HandleFireRequest(player: Player, intent: any): (Shot?, string?)
	if player.GetAttribute and player:GetAttribute("TeamManagementOpen") then
		return nil, "management open"
	end
	local id = if type(intent) == "table" then intent.RequestId else nil
	if type(id) ~= "number" or id ~= id or id < 1 or id > 9007199254740991 or id % 1 ~= 0 then
		id = nil
	end
	local decision: any = { RequestId = id, PlayerId = player.UserId }
	local shot, reason = handleFireRequest(player, intent, decision)
	decision.Accepted, decision.Reason =
		shot ~= nil,
		reason or (if decision.ImpactKind == "BrainrotHit"
			then "hit"
			elseif decision.ImpactKind == "BrainrotDamageHit" then "sleep damage"
			elseif decision.ImpactKind == "AlreadySleeping" then "already sleeping"
			elseif decision.ImpactKind == "DecoyHit" then "decoy"
			elseif decision.ImpactKind == "RejectedOrStaleDecoy" then "stale decoy"
			else "miss")
	if RunService:IsStudio() and ReplicatedStorage:GetAttribute("HuntingAimTrace") == true then
		print(
			string.format(
				"[HuntingAim][decision] request=%s player=%s accepted=%s reason=%s weapon=%s equipmentRevision=%s context=%s shotMode=%s lockedKind=%s lockedId=%s fallback=%s M=%s C=%s D=%s crosshair=%s range=%.3f obstruction=%s item=%s depth=%s slept=%s",
				tostring(id),
				player.Name,
				tostring(decision.Accepted),
				tostring(decision.Reason),
				tostring(decision.WeaponId),
				tostring(decision.EquipmentRevision),
				tostring(decision.Context),
				tostring(decision.ShotMode),
				tostring(decision.LockedTargetKind),
				tostring(decision.LockedTargetId),
				tostring(decision.LockFallbackReason),
				tostring(decision.Muzzle),
				tostring(type(intent) == "table" and intent.CameraOrigin),
				tostring(type(intent) == "table" and intent.CameraDirection),
				tostring(type(intent) == "table" and intent.CrosshairDirection),
				decision.RangeStuds or 0,
				tostring(decision.Obstruction),
				tostring(decision.ItemId),
				tostring(decision.Depth),
				tostring(decision.Slept)
			)
		)
	end
	if shot then
		local remote = getSleepRequestRemote()
		local observers = Players:GetPlayers()
		if interestService then
			local region = interestService:GetRegion(player)
			if region then
				observers = interestService:GetObservers(region)
			end
			if not table.find(observers, player) then
				table.insert(observers, player)
			end
		end
		for _, observer in observers do
			-- Observers only consume endpoints. Keep full acknowledgement/diagnostic
			-- data private to the shooter without changing a bolt's audience or timing.
			remote:FireClient(
				observer,
				shot.Origin,
				shot.Endpoint,
				if observer == player then decision else nil,
				shot.WeaponProfile
			)
		end
	elseif id and typeof(player) == "Instance" and player:IsA("Player") then
		getSleepRequestRemote():FireClient(player, nil, nil, decision)
	end
	return shot, reason
end

function BrainrotSleepSystem:Start(): boolean
	if started then
		return false
	end
	started = true
	table.insert(connections, getSleepRequestRemote().OnServerEvent:Connect(BrainrotSleepSystem.HandleFireRequest))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			shotTiming[player] = nil
			lastAcceptedRequestId[player] = nil
		end)
	)
	return true
end

function BrainrotSleepSystem:Stop(): boolean
	local changed = started or ownsRemote
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if ownsRemote and sleepRequestRemote then
		sleepRequestRemote:Destroy()
	end
	ownsRemote = false
	sleepRequestRemote = nil
	started = false
	table.clear(shotTiming)
	table.clear(lastAcceptedRequestId)
	table.clear(targetHealth)
	return changed
end

function BrainrotSleepSystem.GetDiagnostics(): any
	return { Started = started, ConnectionCount = #connections, Endpoint = "SleepRequest", OwnsRemote = ownsRemote }
end

return BrainrotSleepSystem
