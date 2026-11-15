--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CartTerrainMath = require(ReplicatedStorage.Shared.Utility.CartTerrainMath)
local CartGeometry = require(ReplicatedStorage.Shared.Utility.CartGeometry)
local CartTerrainTypes = require(ReplicatedStorage.Shared.Types.CartTerrainTypes)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

type EffectiveTerrainProfile = CartTerrainTypes.EffectiveTerrainProfile
type GroundState = CartTerrainTypes.GroundState
type TerrainSnapshot = CartTerrainTypes.TerrainSnapshot

export type Sampler = {
	GetSnapshot: (self: Sampler) -> TerrainSnapshot,
	SetIgnoredCharacter: (self: Sampler, character: Model?) -> (),
	ShouldSample: (self: Sampler, now: number, sampleRate: number) -> boolean,
	SampleNow: (self: Sampler, now: number) -> TerrainSnapshot,
	Suspend: (self: Sampler) -> (),
	Resume: (self: Sampler) -> (),
	Reset: (self: Sampler) -> (),
	Destroy: (self: Sampler) -> (),
}

type SamplerPrivate = Sampler & {
	_cart: Model,
	_root: BasePart,
	_profile: EffectiveTerrainProfile,
	_raycastParams: RaycastParams,
	_ignoredCharacter: Model?,
	_ignoredCharacterFiltered: boolean,
	_snapshot: TerrainSnapshot,
	_state: GroundState,
	_fullSupportElapsed: number,
	_unsupportedElapsed: number,
	_lastSampleTime: number,
	_revision: number,
	_sampleCount: number,
	_needsPrime: boolean,
	_suspended: boolean,
	_destroyed: boolean,
}

local WORLD_UP = Vector3.yAxis
local PROBE_COUNT = 3
local MINIMUM_VERTICAL_ROOT_ALIGNMENT = 1e-4
local ASSEMBLY_STATE_ATTRIBUTE = "AssemblyValidationState"

local log = Logger.new("CartTerrainSampler")

local SamplerMethods = {}
SamplerMethods.__index = SamplerMethods

local CartTerrainSampler = {}

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function makeSnapshot(
	state: GroundState,
	rawNormal: Vector3,
	desiredUp: Vector3,
	hitCount: number,
	groundDistance: number,
	slopeAngleDegrees: number,
	responseStrength: number,
	stabilityMultiplier: number,
	sampledAt: number,
	revision: number,
	sampleCount: number,
	maximumClimbAngleDegrees: number
): TerrainSnapshot
	local grounded = state ~= "Airborne"

	return table.freeze({
		State = state,
		Grounded = grounded,
		FullyGrounded = state == "Grounded",
		Driveable = grounded and slopeAngleDegrees <= maximumClimbAngleDegrees,
		RawNormal = rawNormal,
		DesiredUp = desiredUp,
		HitCount = hitCount,
		GroundDistance = groundDistance,
		SlopeAngleDegrees = slopeAngleDegrees,
		Confidence = hitCount / PROBE_COUNT,
		TerrainResponseStrength = responseStrength,
		StabilityMultiplier = stabilityMultiplier,
		SampledAt = sampledAt,
		Revision = revision,
		SampleCount = sampleCount,
	})
end

local function makeResetSnapshot(
	profile: EffectiveTerrainProfile,
	revision: number,
	sampleCount: number
): TerrainSnapshot
	if not profile.Enabled then
		return makeSnapshot(
			"Grounded",
			WORLD_UP,
			WORLD_UP,
			PROBE_COUNT,
			0,
			0,
			0,
			1,
			0,
			revision,
			sampleCount,
			profile.MaximumClimbAngleDegrees
		)
	end

	return makeSnapshot(
		"Airborne",
		Vector3.zero,
		WORLD_UP,
		0,
		0,
		0,
		0,
		profile.AirborneStabilityMultiplier,
		0,
		revision,
		sampleCount,
		profile.MaximumClimbAngleDegrees
	)
end

local function refreshFilter(self: SamplerPrivate)
	local filter: { Instance } = { self._cart }
	local character = self._ignoredCharacter
	local characterFiltered = character ~= nil and character.Parent ~= nil

	if character ~= nil and characterFiltered then
		table.insert(filter, character)
	end

	self._ignoredCharacterFiltered = characterFiltered
	self._raycastParams.FilterDescendantsInstances = filter
end

local function getProbeOrigins(self: SamplerPrivate): ({ Vector3 }, any?)
	local geometry = CartGeometry.Get(self._cart)
	if geometry and geometry.Ground.CylinderSamples then
		local origins={}
		for _,sample in geometry.Ground.CylinderSamples do
			local localProbe=sample.Hub+sample.Axis*sample.AxialOffset
			table.insert(origins,self._root.CFrame:PointToWorldSpace(localProbe)+WORLD_UP*self._profile.ProbeOriginHeight)
		end
		return origins,geometry.Ground.CylinderSamples
	elseif geometry then
		local origins = {}
		for _, contact in geometry.Ground.ContactSamples do
			table.insert(origins, self._root.CFrame:PointToWorldSpace(contact) + WORLD_UP * self._profile.ProbeOriginHeight)
		end
		return origins,nil
	end
	local root = self._root
	local profile = self._profile
	local forward, right = CartTerrainMath.BuildTangentFrame(root.CFrame.LookVector, WORLD_UP, nil)
	local baseOrigin = root.Position + WORLD_UP * profile.ProbeOriginHeight
	local lateralOffset = right * root.Size.X * profile.LateralProbeFraction
	local forwardOffset = forward * root.Size.Z * profile.ForwardProbeFraction

	return {
		baseOrigin - lateralOffset,
		baseOrigin + lateralOffset,
		baseOrigin + forwardOffset,
	},nil
end

local function finiteVector(v: Vector3): boolean
	return typeof(v)=="Vector3" and isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)
end

-- Signed vertical distance from an oriented cylinder's support plane to the
-- hit plane. Local -Y is not the cylinder bottom after pitch/roll changes.
function CartTerrainSampler.CylinderPlaneGap(hub: Vector3,axis: Vector3,radius: number,halfThickness: number,hitPosition: Vector3,normal: Vector3): number?
	if not finiteVector(hub) or not finiteVector(axis) or not finiteVector(hitPosition) or not finiteVector(normal) or axis.Magnitude<1e-6 or normal.Magnitude<1e-6 or not isFiniteNumber(radius) or radius<=0 or not isFiniteNumber(halfThickness) or halfThickness<=0 then return nil end
	local n=normal.Unit
	local vertical=n:Dot(WORLD_UP)
	if vertical<=MINIMUM_VERTICAL_ROOT_ALIGNMENT then return nil end
	local along=math.clamp(axis.Unit:Dot(n),-1,1)
	local support=radius*math.sqrt(math.max(0,1-along*along))+halfThickness*math.abs(along)
	local gap=(n:Dot(hub-hitPosition)-support)/vertical
	return if isFiniteNumber(gap) then gap else nil
end

local function getStabilityMultiplier(profile: EffectiveTerrainProfile, state: GroundState): number
	if state == "Grounded" then
		return 1
	elseif state == "Partial" then
		return profile.PartialSupportStabilityMultiplier
	end

	return profile.AirborneStabilityMultiplier
end

local function getRootLowerFaceDistance(root: BasePart, origin: Vector3): number?
	local rootUp = root.CFrame.UpVector
	local verticalAlignment = rootUp:Dot(WORLD_UP)

	-- A sideways or inverted Root has no meaningful lower Y-face intersection
	-- beneath these world-down probes. Treat it as unsupported and leave severe
	-- orientation recovery to the bounded Phase 1G stability policy.
	if
		not isFiniteNumber(verticalAlignment)
		or verticalAlignment <= MINIMUM_VERTICAL_ROOT_ALIGNMENT
	then
		return nil
	end

	local lowerFacePoint = root.Position - rootUp * root.Size.Y * 0.5
	local distance = (origin - lowerFacePoint):Dot(rootUp) / verticalAlignment

	if not isFiniteNumber(distance) or distance < 0 then
		return nil
	end

	return distance
end

function CartTerrainSampler.new(
	cart: Model,
	root: BasePart,
	profile: EffectiveTerrainProfile
): Sampler
	assert(cart.Parent ~= nil, "CartTerrainSampler requires a live cart")
	assert(root:IsDescendantOf(cart), "CartTerrainSampler Root must belong to the cart")

	local raycastParams = RaycastParams.new()

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true

	local self: SamplerPrivate = setmetatable({
		_cart = cart,
		_root = root,
		_profile = profile,
		_raycastParams = raycastParams,
		_ignoredCharacter = nil,
		_ignoredCharacterFiltered = false,
		_snapshot = makeResetSnapshot(profile, 1, 0),
		_state = if profile.Enabled then "Airborne" else "Grounded",
		_fullSupportElapsed = 0,
		_unsupportedElapsed = 0,
		_lastSampleTime = -math.huge,
		_revision = 1,
		_sampleCount = 0,
		_needsPrime = true,
		_suspended = true,
		_destroyed = false,
	}, SamplerMethods) :: any

	refreshFilter(self)

	return self
end

function SamplerMethods.GetSnapshot(self: SamplerPrivate): TerrainSnapshot
	return self._snapshot
end

function SamplerMethods.SetIgnoredCharacter(self: SamplerPrivate, character: Model?)
	if self._destroyed then
		return
	end

	local shouldFilterCharacter = character ~= nil and character.Parent ~= nil

	if
		self._ignoredCharacter == character
		and self._ignoredCharacterFiltered == shouldFilterCharacter
	then
		return
	end

	self._ignoredCharacter = character
	refreshFilter(self)
end

function SamplerMethods.ShouldSample(self: SamplerPrivate, now: number, sampleRate: number): boolean
	if
		self._destroyed
		or self._suspended
		or not self._profile.Enabled
		or not isFiniteNumber(now)
		or not isFiniteNumber(sampleRate)
		or sampleRate <= 0
	then
		return false
	end

	return now - self._lastSampleTime >= 1 / sampleRate
end

function SamplerMethods.SampleNow(self: SamplerPrivate, now: number): TerrainSnapshot
	if
		self._destroyed
		or self._suspended
		or not isFiniteNumber(now)
		or self._cart.Parent == nil
		or self._root.Parent == nil
		or not self._root:IsDescendantOf(self._cart)
		or self._root.Anchored
		or self._cart:GetAttribute(ASSEMBLY_STATE_ATTRIBUTE) ~= "Valid"
	then
		return self._snapshot
	end

	local profile = self._profile

	if not profile.Enabled then
		return self._snapshot
	end

	local deltaTime = if isFiniteNumber(self._lastSampleTime)
		then math.max(now - self._lastSampleTime, 0)
		else 0

	self._lastSampleTime = now
	self._sampleCount += 1

	local normals: { Vector3 } = {}
	local acceptedDistanceTotal = 0
	local acceptedDistanceCount = 0
	-- Cylinder probes begin at independently authored axial positions; their
	-- support-plane gap uses the full true cylinder, not a fictitious flat rim.
	local origins,cylinders=getProbeOrigins(self)
	local geometry=CartGeometry.Get(self._cart)
	for index,origin in origins do
		local cylinder=if cylinders then cylinders[index] else nil
		local extraReach=if cylinder then cylinder.Radius+cylinder.HalfThickness else 0
		local direction=-WORLD_UP*(profile.ProbeOriginHeight+profile.GroundDetectionDistance+extraReach)
		local result=Workspace:Raycast(origin,direction,self._raycastParams)
		local supportGap=nil
		if result then
			if cylinder then
				supportGap=CartTerrainSampler.CylinderPlaneGap(self._root.CFrame:PointToWorldSpace(cylinder.Hub),self._root.CFrame:VectorToWorldSpace(cylinder.Axis),cylinder.Radius,cylinder.HalfThickness,result.Position,result.Normal)
			else
				local lowerFaceDistance=if geometry then profile.ProbeOriginHeight else getRootLowerFaceDistance(self._root,origin)
				if lowerFaceDistance then supportGap=result.Distance-lowerFaceDistance end
			end
		end
		if result~=nil and supportGap~=nil then
			local angle=CartTerrainMath.GetSlopeAngleDegrees(result.Normal,WORLD_UP)

			-- The long ray is a sensing envelope, not proof of contact. A surface
			-- only supports the cart when it is close to the authored support shape,
			-- allowing only a small tolerance for ordinary contact penetration.
			if
				angle <= profile.MaximumGroundAngleDegrees
				and supportGap <= profile.MaximumSupportGap
				and supportGap >= -profile.MaximumSupportPenetration
			then
				table.insert(normals, result.Normal)
				acceptedDistanceTotal += math.max(supportGap, 0)
				acceptedDistanceCount += 1
			end
		end
	end

	local rawNormal, hitCount = CartTerrainMath.CombineGroundNormals(
		normals,
		WORLD_UP,
		profile.MaximumGroundAngleDegrees,
		profile.NormalOutlierAngleDegrees
	)
	local previousState = self._state
	local nextState, fullSupportElapsed, unsupportedElapsed = CartTerrainMath.AdvanceGroundState(
		previousState,
		self._fullSupportElapsed,
		self._unsupportedElapsed,
		hitCount,
		profile.FullGroundedHitCount,
		profile.GroundedReacquireDelay,
		profile.AirborneDelay,
		deltaTime
	)

	self._state = nextState
	self._fullSupportElapsed = fullSupportElapsed
	self._unsupportedElapsed = unsupportedElapsed

	local previousDesiredUp = self._snapshot.DesiredUp
	local targetUp = if rawNormal ~= nil
		then rawNormal
		elseif nextState == "Airborne" then WORLD_UP
		else previousDesiredUp
	local responseSpeed = if nextState == "Airborne"
		then profile.AirborneWorldUpResponseSpeed
		else profile.NormalResponseSpeed
	-- Prime a newly registered or reset sampler before actuators resume. This
	-- avoids treating world up as terrain up for the first driven frame while
	-- preserving smoothing for every live terrain transition after that.
	local desiredUp = if self._needsPrime
			and rawNormal ~= nil
			and hitCount >= profile.FullGroundedHitCount
		then rawNormal
		else CartTerrainMath.SmoothDesiredUp(
			previousDesiredUp,
			targetUp,
			responseSpeed,
			profile.MaximumNormalChangeDegreesPerSecond,
			deltaTime
		)

	self._needsPrime = false
	local slopeAngleDegrees = CartTerrainMath.GetSlopeAngleDegrees(desiredUp, WORLD_UP)
	local supportStrength = if nextState == "Grounded"
		then 1
		elseif nextState == "Partial" then hitCount / PROBE_COUNT
		else 0
	local responseStrength = CartTerrainMath.GetSlopeInfluence(slopeAngleDegrees, profile).ResponseStrength
		* supportStrength
	local groundDistance = if acceptedDistanceCount > 0
		then acceptedDistanceTotal / acceptedDistanceCount
		else 0

	self._revision += 1
	self._snapshot = makeSnapshot(
		nextState,
		rawNormal or Vector3.zero,
		desiredUp,
		hitCount,
		groundDistance,
		slopeAngleDegrees,
		responseStrength,
		getStabilityMultiplier(profile, nextState),
		now,
		self._revision,
		self._sampleCount,
		profile.MaximumClimbAngleDegrees
	)

	if previousState ~= nextState then
		log:Debug(
			"Ground state changed Cart=%s CartId=%s State=%s->%s Hits=%d Slope=%.1f Confidence=%.2f",
			self._cart.Name,
			profile.CartId,
			previousState,
			nextState,
			hitCount,
			slopeAngleDegrees,
			self._snapshot.Confidence
		)
	end

	return self._snapshot
end

function SamplerMethods.Suspend(self: SamplerPrivate)
	if self._destroyed then
		return
	end

	self._suspended = true
end

function SamplerMethods.Resume(self: SamplerPrivate)
	if self._destroyed then
		return
	end

	self._suspended = false
	self._lastSampleTime = -math.huge
end

function SamplerMethods.Reset(self: SamplerPrivate)
	if self._destroyed then
		return
	end

	self._state = if self._profile.Enabled then "Airborne" else "Grounded"
	self._fullSupportElapsed = 0
	self._unsupportedElapsed = 0
	self._lastSampleTime = -math.huge
	self._needsPrime = true
	self._revision += 1
	self._snapshot = makeResetSnapshot(self._profile, self._revision, self._sampleCount)
end

function SamplerMethods.Destroy(self: SamplerPrivate)
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._suspended = true
	self._ignoredCharacter = nil
	self._ignoredCharacterFiltered = false
	self._raycastParams.FilterDescendantsInstances = {}
end

return CartTerrainSampler
