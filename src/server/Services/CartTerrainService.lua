--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CartTerrainProfileResolver =
	require(ReplicatedStorage.Shared.Utility.CartTerrainProfileResolver)
local CartTerrainSampler = require(ReplicatedStorage.Shared.Utility.CartTerrainSampler)
local CartTerrainTypes = require(ReplicatedStorage.Shared.Types.CartTerrainTypes)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CartAssemblyValidationService = require(script.Parent.CartAssemblyValidationService)
local CartOccupantService = require(script.Parent.CartOccupantService)

type EffectiveTerrainProfile = CartTerrainTypes.EffectiveTerrainProfile
type TerrainSampler = CartTerrainSampler.Sampler
type TerrainSnapshot = CartTerrainTypes.TerrainSnapshot

type RuntimeRecord = {
	Cart: Model,
	Root: BasePart,
	Profile: EffectiveTerrainProfile,
	Sampler: TerrainSampler,
	Driving: boolean,
	Suspended: boolean,
	Cleaning: boolean,
	Revision: number,
	LastDriverRevision: number,
	LastSampleAttemptTime: number,
	OwnershipBlocked: boolean,
	Connections: { RBXScriptConnection },
}

local ASSEMBLY_STATE_ATTRIBUTE = "AssemblyValidationState"
local MAX_SERVER_SAMPLES_PER_FRAME = 2

local log = Logger.new("CartTerrainService")
local CartTerrainService = {}

local recordsByCart: { [Model]: RuntimeRecord } = {}
local orderedRecords: { RuntimeRecord } = {}
local roundRobinCursor = 1
local preSimulationConnection: RBXScriptConnection? = nil
local driverChangedConnection: RBXScriptConnection? = nil
local started = false

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function removeOrderedRecord(record: RuntimeRecord)
	for index, candidate in orderedRecords do
		if candidate == record then
			table.remove(orderedRecords, index)

			if index < roundRobinCursor then
				roundRobinCursor -= 1
			end

			break
		end
	end

	if #orderedRecords == 0 then
		roundRobinCursor = 1
	else
		roundRobinCursor = math.clamp(roundRobinCursor, 1, #orderedRecords)
	end
end

local function cleanupRecord(record: RuntimeRecord, reason: string): boolean
	if recordsByCart[record.Cart] ~= record then
		return false
	end

	record.Cleaning = true
	record.Suspended = true
	record.Revision += 1
	recordsByCart[record.Cart] = nil
	removeOrderedRecord(record)
	disconnectAll(record.Connections)
	record.Sampler:Destroy()

	log:Debug(
		"Cleaned terrain state Cart=%s CartId=%s Revision=%d Reason=%s",
		record.Cart.Name,
		record.Profile.CartId,
		record.Revision,
		reason
	)

	return true
end

local function liveContractIsValid(record: RuntimeRecord): boolean
	return record.Cart.Parent ~= nil
		and record.Root.Parent ~= nil
		and record.Root:IsDescendantOf(record.Cart)
		and record.Cart:GetAttribute(ASSEMBLY_STATE_ATTRIBUTE) == "Valid"
		and CartAssemblyValidationService:IsCartValid(record.Cart)
end

local function attachRecordConnections(record: RuntimeRecord)
	table.insert(
		record.Connections,
		record.Cart.Destroying:Connect(function()
			cleanupRecord(record, "cart destroying")
		end)
	)
	table.insert(
		record.Connections,
		record.Cart.AncestryChanged:Connect(function()
			if record.Cart.Parent == nil then
				cleanupRecord(record, "cart removed from hierarchy")
			end
		end)
	)
	table.insert(
		record.Connections,
		record.Root.AncestryChanged:Connect(function()
			if not record.Root:IsDescendantOf(record.Cart) then
				cleanupRecord(record, "Root removed from cart")
			end
		end)
	)
end

local function getSampleRate(record: RuntimeRecord): number
	local snapshot = record.Sampler:GetSnapshot()
	local velocity = record.Root.AssemblyLinearVelocity
	local moving = not isFiniteNumber(velocity.X)
		or not isFiniteNumber(velocity.Y)
		or not isFiniteNumber(velocity.Z)
		or velocity.Magnitude > record.Profile.ServerSettledSpeedThreshold
		or snapshot.State ~= "Grounded"

	return if moving
		then record.Profile.ServerMovingSampleRate
		else record.Profile.ServerSettledSampleRate
end

local function sampleRecordIfDue(record: RuntimeRecord, now: number): (boolean, string?)
	if
		record.Cleaning
		or record.Suspended
		or record.Driving
		or recordsByCart[record.Cart] ~= record
		or not liveContractIsValid(record)
		or record.Root.Anchored
	then
		return false, "cart is not eligible for server terrain sampling"
	end

	local rate = getSampleRate(record)

	if not record.Sampler:ShouldSample(now, rate) then
		return false, "terrain sample is not due"
	end

	if now - record.LastSampleAttemptTime < 1 / rate then
		return false, "network-ownership retry is backed off"
	end

	record.LastSampleAttemptTime = now

	local ownershipSuccess, networkOwner = pcall(function()
		return record.Root:GetNetworkOwner()
	end)

	if not ownershipSuccess or networkOwner ~= nil then
		local reason = if ownershipSuccess
			then string.format(
				"unexpected network owner UserId=%d",
				(networkOwner :: Player).UserId
			)
			else string.format("GetNetworkOwner failed: %s", tostring(networkOwner))

		if not record.OwnershipBlocked then
			record.OwnershipBlocked = true
			log:Warn(
				"Server terrain sampling blocked Cart=%s CartId=%s Reason=%s",
				record.Cart.Name,
				record.Profile.CartId,
				reason
			)
		end

		return false, reason
	end

	if record.OwnershipBlocked then
		record.OwnershipBlocked = false
		log:Debug(
			"Server terrain sampling resumed Cart=%s CartId=%s",
			record.Cart.Name,
			record.Profile.CartId
		)
	end

	local previousSampleCount = record.Sampler:GetSnapshot().SampleCount
	local snapshot = record.Sampler:SampleNow(now)

	if snapshot.SampleCount <= previousSampleCount then
		return false, "terrain sampler did not produce a fresh snapshot"
	end

	return true, nil
end

local function updateServerTerrain()
	local recordCount = #orderedRecords

	if recordCount == 0 then
		return
	end

	local now = os.clock()
	local inspected = 0
	local sampled = 0

	while
		inspected < recordCount
		and sampled < MAX_SERVER_SAMPLES_PER_FRAME
		and #orderedRecords > 0
	do
		if roundRobinCursor > #orderedRecords then
			roundRobinCursor = 1
		end

		local record = orderedRecords[roundRobinCursor]

		roundRobinCursor += 1
		inspected += 1

		if sampleRecordIfDue(record, now) then
			sampled += 1
		end
	end
end

local function onDriverChanged(
	cart: Model,
	_previousDriver: Player?,
	nextDriver: Player?,
	reason: string,
	driverRevision: number
)
	local record = recordsByCart[cart]

	if record == nil or record.Cleaning or driverRevision <= record.LastDriverRevision then
		return
	end

	record.LastDriverRevision = driverRevision
	record.Driving = nextDriver ~= nil
	record.Revision += 1
	record.LastSampleAttemptTime = -math.huge
	record.OwnershipBlocked = false

	if record.Driving then
		record.Sampler:Suspend()
	else
		record.Sampler:Reset()
		record.Sampler:Resume()

		local sampled, sampleError = sampleRecordIfDue(record, os.clock())

		if not sampled then
			log:Warn(
				"Driver-exit terrain refresh deferred Cart=%s CartId=%s Reason=%s",
				record.Cart.Name,
				record.Profile.CartId,
				sampleError or "unknown sampling failure"
			)
		end
	end

	log:Debug(
		"Terrain ownership mode changed Cart=%s CartId=%s ServerSampling=%s DriverUserId=%d Reason=%s",
		record.Cart.Name,
		record.Profile.CartId,
		tostring(not record.Driving and not record.Suspended),
		if nextDriver ~= nil then nextDriver.UserId else 0,
		reason
	)
end

function CartTerrainService:Start()
	if started then
		assert(
			preSimulationConnection ~= nil and driverChangedConnection ~= nil,
			"started terrain service lost its global connections"
		)
		return
	end

	started = true
	driverChangedConnection = CartOccupantService.DriverChanged:Connect(onDriverChanged)
	preSimulationConnection = RunService.PreSimulation:Connect(updateServerTerrain)

	log:Info(
		"Cart terrain service ready ServerSampleBudgetPerFrame=%d",
		MAX_SERVER_SAMPLES_PER_FRAME
	)
end

function CartTerrainService:RegisterCart(cart: Model): (boolean, string?)
	if recordsByCart[cart] ~= nil then
		return false, "cart already has a terrain state"
	end

	if not started then
		return false, "cart terrain service must start before cart registration"
	end

	if cart.Parent == nil or cart:GetAttribute("RuntimeCart") ~= true then
		return false, "cart must be a live runtime model"
	end

	if
		cart:GetAttribute(ASSEMBLY_STATE_ATTRIBUTE) ~= "Valid"
		or not CartAssemblyValidationService:IsCartValid(cart)
	then
		return false, "cart assembly must pass fatal validation before terrain registration"
	end

	local rootInstance = cart:FindFirstChild("Root")

	if rootInstance == nil or not rootInstance:IsA("BasePart") then
		return false, "cart requires direct Root BasePart"
	end

	if rootInstance.Anchored then
		return false, "cart Root must be unanchored before terrain registration"
	end

	local resolveSuccess, profileOrError = pcall(function()
		return CartTerrainProfileResolver.ResolveForCart(cart)
	end)

	if not resolveSuccess then
		return false,
			string.format("terrain profile resolution failed: %s", tostring(profileOrError))
	end

	local profile = profileOrError :: EffectiveTerrainProfile
	local samplerSuccess, samplerOrError = pcall(function()
		return CartTerrainSampler.new(cart, rootInstance, profile)
	end)

	if not samplerSuccess then
		return false, string.format("terrain sampler creation failed: %s", tostring(samplerOrError))
	end

	local activeDriver = CartOccupantService:GetDriver(cart)
	local sampler = samplerOrError :: TerrainSampler
	local record: RuntimeRecord = {
		Cart = cart,
		Root = rootInstance,
		Profile = profile,
		Sampler = sampler,
		Driving = activeDriver ~= nil,
		Suspended = false,
		Cleaning = false,
		Revision = 1,
		LastDriverRevision = -1,
		LastSampleAttemptTime = -math.huge,
		OwnershipBlocked = false,
		Connections = {},
	}

	recordsByCart[cart] = record
	table.insert(orderedRecords, record)
	attachRecordConnections(record)

	if record.Driving then
		sampler:Suspend()
	else
		sampler:Resume()

		local sampled, sampleError = sampleRecordIfDue(record, os.clock())

		if not sampled then
			cleanupRecord(record, "initial terrain sample failed")
			return false,
				string.format(
					"initial terrain sample failed: %s",
					sampleError or "unknown sampling failure"
				)
		end
	end

	local snapshot = sampler:GetSnapshot()

	log:Info(
		"Registered cart terrain Cart=%s CartId=%s State=%s Hits=%d MovingHz=%.1f SettledHz=%.1f",
		cart.Name,
		profile.CartId,
		snapshot.State,
		snapshot.HitCount,
		profile.ServerMovingSampleRate,
		profile.ServerSettledSampleRate
	)

	return true, nil
end

function CartTerrainService:SuspendCart(cart: Model, reason: string): (boolean, string?)
	local record = recordsByCart[cart]

	if record == nil then
		return false, "cart has no terrain state"
	end

	if record.Cleaning then
		return false, "cart terrain state is cleaning"
	end

	if record.Suspended then
		return true, nil
	end

	record.Suspended = true
	record.Revision += 1
	record.Sampler:Suspend()

	log:Debug(
		"Suspended cart terrain Cart=%s CartId=%s Reason=%s",
		record.Cart.Name,
		record.Profile.CartId,
		reason
	)

	return true, nil
end

function CartTerrainService:ResumeCart(cart: Model, reason: string): (boolean, string?)
	local record = recordsByCart[cart]

	if record == nil then
		return false, "cart has no terrain state"
	end

	if record.Cleaning then
		return false, "cart terrain state is cleaning"
	end

	if not liveContractIsValid(record) or record.Root.Anchored then
		return false, "cart assembly must be valid and unanchored before terrain resumes"
	end

	record.Suspended = false
	record.Revision += 1
	record.LastSampleAttemptTime = -math.huge
	record.OwnershipBlocked = false
	record.Sampler:Reset()

	if record.Driving then
		record.Sampler:Suspend()
	else
		record.Sampler:Resume()

		local sampled, sampleError = sampleRecordIfDue(record, os.clock())

		if not sampled then
			record.Suspended = true
			record.Sampler:Suspend()
			return false,
				string.format(
					"fresh terrain sample failed during resume: %s",
					sampleError or "unknown sampling failure"
				)
		end
	end

	log:Debug(
		"Resumed cart terrain Cart=%s CartId=%s Reason=%s",
		record.Cart.Name,
		record.Profile.CartId,
		reason
	)

	return true, nil
end

function CartTerrainService:UnregisterCart(cart: Model, reason: string?): boolean
	local record = recordsByCart[cart]

	if record == nil then
		return false
	end

	return cleanupRecord(record, reason or "cart terrain unregistered")
end

function CartTerrainService:IsCartRegistered(cart: Model): boolean
	return recordsByCart[cart] ~= nil
end

function CartTerrainService:GetSnapshot(cart: Model): TerrainSnapshot?
	local record = recordsByCart[cart]

	if record == nil or record.Cleaning then
		return nil
	end

	return record.Sampler:GetSnapshot()
end

function CartTerrainService:GetDiagnostics()
	local recordConnectionCount = 0
	local totalSampleCount = 0

	for _, record in recordsByCart do
		recordConnectionCount += #record.Connections
		totalSampleCount += record.Sampler:GetSnapshot().SampleCount
	end

	return table.freeze({
		Started = started,
		RecordCount = #orderedRecords,
		RecordConnectionCount = recordConnectionCount,
		SharedConnectionCount = (if preSimulationConnection ~= nil then 1 else 0)
			+ (if driverChangedConnection ~= nil then 1 else 0),
		SchedulerCount = if preSimulationConnection ~= nil then 1 else 0,
		SampleBudgetPerFrame = MAX_SERVER_SAMPLES_PER_FRAME,
		TotalSampleCount = totalSampleCount,
	})
end

return CartTerrainService
