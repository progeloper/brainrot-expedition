--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CollisionGroups = require(ReplicatedStorage.Shared.Config.CollisionGroups)
local Volume = require(script.Parent.CartCameraVolume)
local CartCameraMath = require(ReplicatedStorage.Shared.Utility.CartCameraMath)

export type Config = {
	Enabled: boolean,
	QueryRadius: number,
	SurfaceBuffer: number,
	MinimumDistance: number,
	OutwardRecoverySpeed: number,
	DistanceTolerance: number,
}

export type QueryFunction = (
	origin: Vector3,
	radius: number,
	direction: Vector3,
	params: RaycastParams
) -> RaycastResult?

export type Result = {
	CorrectedPosition: Vector3,
	DesiredDistance: number,
	CorrectedDistance: number,
	Obstructed: boolean,
	HitInstance: Instance?,
	HitDistance: number?,
	MinimumCompromised: boolean,
	Recovering: boolean,
	InitialOverlap: boolean,
	QueryPerformed: boolean,
	QueryFailed: boolean,
	Failure: string?,
	FilterRevision: number,
}

export type Resolver = {
	SetFilterContext: (self: Resolver, cart: Model?, character: Model?) -> (),
	GetFilterRevision: (self: Resolver) -> number,
	GetCurrentDistance: (self: Resolver) -> number?,
	Resolve: (
		self: Resolver,
		origin: Vector3,
		desiredPosition: Vector3,
		deltaTime: number,
		resynchronize: boolean
	) -> (Result?, string?),
	Reset: (self: Resolver) -> (),
	Destroy: (self: Resolver) -> (),
}

type ResolverPrivate = Resolver & {
	_config: Config,
	_volume: any,
	_query: QueryFunction,
	_raycastParams: RaycastParams,
	_cart: Model?,
	_character: Model?,
	_currentDistance: number?,
	_currentDeficit: number?,
	_filterRevision: number,
	_destroyed: boolean,
	_result: Result,
}

local DIRECTION_EPSILON = 1e-6

local ResolverMethods = {}
ResolverMethods.__index = ResolverMethods

local CartCameraOcclusion = {}

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function performSpherecast(
	origin: Vector3,
	radius: number,
	direction: Vector3,
	params: RaycastParams
): RaycastResult?
	return Workspace:Spherecast(origin, radius, direction, params)
end

local function refreshFilter(self: ResolverPrivate)
	local filter: { Instance } = {}
	local cart = self._cart
	local character = self._character

	if cart ~= nil and cart.Parent ~= nil then
		table.insert(filter, cart)
	end

	if character ~= nil and character ~= cart and character.Parent ~= nil then
		table.insert(filter, character)
	end

	self._filterRevision += 1
	self._raycastParams.FilterDescendantsInstances = filter
end

function CartCameraOcclusion.ResolveSafeDistance(
	desiredDistance: number,
	hitDistance: number?,
	surfaceBuffer: number,
	minimumDistance: number
): (number, boolean)
	if hitDistance == nil then
		return desiredDistance, false
	end

	local safeDistance = math.clamp(hitDistance - surfaceBuffer, 0, desiredDistance)

	-- Never force the camera through a closer obstruction merely to honour the
	-- preferred minimum. The flag makes that exceptional compression observable.
	return safeDistance, safeDistance < minimumDistance
end

function CartCameraOcclusion.ResolveQueryFailureDistance(
	desiredDistance: number,
	currentDistance: number?,
	minimumDistance: number
): number
	-- A failed query must never expand beyond a previously known-safe close
	-- position. With no close history, conservatively contract to the preferred minimum.
	return math.min(desiredDistance, currentDistance or minimumDistance, minimumDistance)
end

function CartCameraOcclusion.AdvanceDeficit(
	currentDeficit: number?,
	targetDeficit: number,
	outwardRecoverySpeed: number,
	distanceTolerance: number,
	deltaTime: number,
	resynchronize: boolean
): number
	if
		resynchronize
		or currentDeficit == nil
		or not isFiniteNumber(currentDeficit)
		or currentDeficit < 0
	then
		return targetDeficit
	end

	if targetDeficit >= currentDeficit then
		return targetDeficit
	end

	local alpha = CartCameraMath.GetExponentialAlpha(outwardRecoverySpeed, deltaTime)
	local nextDeficit = currentDeficit + (targetDeficit - currentDeficit) * alpha

	if nextDeficit - targetDeficit <= distanceTolerance then
		return targetDeficit
	end

	return math.max(nextDeficit, targetDeficit)
end

function CartCameraOcclusion.ResolvePosition(
	origin: Vector3,
	desiredPosition: Vector3,
	correctedDistance: number
): Vector3?
	if
		not CartCameraMath.IsFiniteVector3(origin)
		or not CartCameraMath.IsFiniteVector3(desiredPosition)
		or not isFiniteNumber(correctedDistance)
		or correctedDistance < 0
	then
		return nil
	end

	local offset = desiredPosition - origin
	local desiredDistance = offset.Magnitude

	if not isFiniteNumber(desiredDistance) or desiredDistance <= DIRECTION_EPSILON then
		return nil
	end

	return origin + offset.Unit * math.min(correctedDistance, desiredDistance)
end

function CartCameraOcclusion.ApplyCorrectedPosition(
	baseCFrame: CFrame,
	correctedPosition: Vector3
): CFrame?
	if
		not CartCameraMath.IsFiniteCFrame(baseCFrame)
		or not CartCameraMath.IsFiniteVector3(correctedPosition)
	then
		return nil
	end

	return CFrame.new(correctedPosition) * baseCFrame.Rotation
end

function CartCameraOcclusion.new(config: Config, query: QueryFunction?): Resolver
	local raycastParams = RaycastParams.new()

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true
	raycastParams.CollisionGroup = CollisionGroups.Carts

	local self: ResolverPrivate = setmetatable({
		_config = config,
		_volume = if query == nil then Volume.new(config) else nil,
		_query = query or performSpherecast,
		_raycastParams = raycastParams,
		_cart = nil,
		_character = nil,
		_currentDistance = nil,
		_currentDeficit = nil,
		_filterRevision = 0,
		_destroyed = false,
		_result = {
			CorrectedPosition = Vector3.zero,
			DesiredDistance = 0,
			CorrectedDistance = 0,
			Obstructed = false,
			HitInstance = nil,
			HitDistance = nil,
			MinimumCompromised = false,
			Recovering = false,
			InitialOverlap = false,
			QueryPerformed = false,
			QueryFailed = false,
			Failure = nil,
			FilterRevision = 0,
		},
	}, ResolverMethods) :: any

	refreshFilter(self)

	return self
end

function ResolverMethods.SetFilterContext(self: ResolverPrivate, cart: Model?, character: Model?)
	if self._destroyed or (self._cart == cart and self._character == character) then
		return
	end

	self._cart = cart
	self._character = character
	if self._volume then self._volume:SetContext(cart,character)end
	refreshFilter(self)
end

function ResolverMethods.GetFilterRevision(self: ResolverPrivate): number
	return self._filterRevision
end

function ResolverMethods.GetCurrentDistance(self: ResolverPrivate): number?
	return self._currentDistance
end

function ResolverMethods.Resolve(
	self: ResolverPrivate,
	origin: Vector3,
	desiredPosition: Vector3,
	deltaTime: number,
	resynchronize: boolean
): (Result?, string?)
	if self._destroyed then
		return nil, "camera occlusion resolver is destroyed"
	end
	-- A disabled obstruction config performs no world query at all; the legacy
	-- branch below already handles that case without touching the volume.
	if self._volume and self._config.Enabled then
		local resolved, volumeFailure =
			self._volume:Resolve(origin, desiredPosition, deltaTime, resynchronize, self._cart, self._character)
		self._currentDistance = if resolved then resolved.CorrectedDistance else nil
		return resolved, volumeFailure
	end

	if
		not CartCameraMath.IsFiniteVector3(origin)
		or not CartCameraMath.IsFiniteVector3(desiredPosition)
		or not isFiniteNumber(deltaTime)
	then
		return nil, "camera occlusion input must be finite"
	end

	local direction = desiredPosition - origin
	local desiredDistance = direction.Magnitude

	if not isFiniteNumber(desiredDistance) or desiredDistance <= DIRECTION_EPSILON then
		return nil, "camera occlusion segment must have nonzero finite length"
	end

	local queryPerformed = false
	local queryFailed = false
	local failure: string? = nil
	local hitInstance: Instance? = nil
	local hitDistance: number? = nil
	local initialOverlap = false

	if self._config.Enabled then
		queryPerformed = true

		local succeeded, queryResult =
			pcall(self._query, origin, self._config.QueryRadius, direction, self._raycastParams)

		if not succeeded then
			queryFailed = true
			failure = tostring(queryResult)
		else
			local forwardHit = queryResult :: RaycastResult?
			local directionUnit = direction.Unit
			local originProbeDistance = if forwardHit ~= nil
				then math.max(forwardHit.Distance - self._config.DistanceTolerance, 0)
				else desiredDistance
			local originProbeDirection = -directionUnit * originProbeDistance
			local originProbePosition = origin - originProbeDirection

			if originProbeDistance <= DIRECTION_EPSILON then
				if forwardHit ~= nil then
					hitInstance = forwardHit.Instance
					hitDistance = forwardHit.Distance
				end
			else
				local probeSucceeded, probeResult = pcall(
					self._query,
					originProbePosition,
					self._config.QueryRadius,
					originProbeDirection,
					self._raycastParams
				)

				if not probeSucceeded then
					queryFailed = true
					failure = tostring(probeResult)

					-- The forward cast is still authoritative safety information. Keep
					-- its nearest hit as a hard upper bound even though the defensive
					-- origin-overlap probe could not complete.
					if forwardHit ~= nil then
						hitInstance = forwardHit.Instance
						hitDistance = forwardHit.Distance
					end
				else
					-- Roblox shape casts omit geometry already intersecting their starting
					-- shape. Start the reverse probe just before the forward contact (or at
					-- the unobstructed endpoint), so any reverse hit inside that known-clear
					-- prefix identifies an origin overlap, including Terrain and thick solids.
					local originProbeHit = probeResult :: RaycastResult?

					if originProbeHit ~= nil then
						hitInstance = originProbeHit.Instance
						hitDistance = 0
						initialOverlap = true
					elseif forwardHit ~= nil then
						hitInstance = forwardHit.Instance
						hitDistance = forwardHit.Distance
					end
				end
			end
		end
	end

	local targetDistance: number
	local minimumCompromised = false

	if queryFailed then
		targetDistance = CartCameraOcclusion.ResolveQueryFailureDistance(
			desiredDistance,
			self._currentDistance,
			self._config.MinimumDistance
		)

		if hitInstance ~= nil then
			local knownHitDistance, knownHitCompromisesMinimum =
				CartCameraOcclusion.ResolveSafeDistance(
					desiredDistance,
					hitDistance,
					self._config.SurfaceBuffer,
					self._config.MinimumDistance
				)

			targetDistance = math.min(targetDistance, knownHitDistance)
			minimumCompromised = knownHitCompromisesMinimum
				or targetDistance < self._config.MinimumDistance
		else
			minimumCompromised = targetDistance < self._config.MinimumDistance
		end
	elseif hitInstance ~= nil then
		targetDistance, minimumCompromised = CartCameraOcclusion.ResolveSafeDistance(
			desiredDistance,
			hitDistance,
			self._config.SurfaceBuffer,
			self._config.MinimumDistance
		)
	else
		targetDistance = desiredDistance
	end

	local targetDeficit = math.max(desiredDistance - targetDistance, 0)
	local correctedDeficit = CartCameraOcclusion.AdvanceDeficit(
		self._currentDeficit,
		targetDeficit,
		self._config.OutwardRecoverySpeed,
		self._config.DistanceTolerance,
		deltaTime,
		resynchronize or queryFailed
	)
	local correctedDistance = math.clamp(desiredDistance - correctedDeficit, 0, targetDistance)
	local correctedPosition =
		CartCameraOcclusion.ResolvePosition(origin, desiredPosition, correctedDistance)

	if correctedPosition == nil then
		return nil, "camera occlusion correction produced an invalid position"
	end

	self._currentDistance = correctedDistance
	self._currentDeficit = math.max(desiredDistance - correctedDistance, 0)

	local result = self._result

	result.CorrectedPosition = correctedPosition
	result.DesiredDistance = desiredDistance
	result.CorrectedDistance = correctedDistance
	result.Obstructed = hitInstance ~= nil
	result.HitInstance = hitInstance
	result.HitDistance = hitDistance
	result.MinimumCompromised = minimumCompromised
	result.Recovering = not queryFailed
		and hitInstance == nil
		and self._currentDeficit > self._config.DistanceTolerance
	result.InitialOverlap = initialOverlap
	result.QueryPerformed = queryPerformed
	result.QueryFailed = queryFailed
	result.Failure = failure
	result.FilterRevision = self._filterRevision

	return result, nil
end

function ResolverMethods.Reset(self: ResolverPrivate)
	if self._volume then self._volume:Reset()end
	if self._destroyed then
		return
	end

	self._currentDistance = nil
	self._currentDeficit = nil

	local result = self._result

	result.CorrectedPosition = Vector3.zero
	result.DesiredDistance = 0
	result.CorrectedDistance = 0
	result.Obstructed = false
	result.HitInstance = nil
	result.HitDistance = nil
	result.MinimumCompromised = false
	result.Recovering = false
	result.InitialOverlap = false
	result.QueryPerformed = false
	result.QueryFailed = false
	result.Failure = nil
	result.FilterRevision = self._filterRevision
end

function ResolverMethods.Destroy(self: ResolverPrivate)
	if self._volume then self._volume:Destroy();self._volume=nil end
	if self._destroyed then
		return
	end

	self:Reset()
	self._destroyed = true
	self._cart = nil
	self._character = nil
	self._raycastParams.FilterDescendantsInstances = {}
end

return table.freeze(CartCameraOcclusion)
