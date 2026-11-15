--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local CartMovementTypes = require(ReplicatedStorage.Shared.Types.CartMovementTypes)
local CartLongitudinalStateMachine = require(ReplicatedStorage.Shared.Utility.CartLongitudinalStateMachine)
local CartTerrainMath = require(ReplicatedStorage.Shared.Utility.CartTerrainMath)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CartModelUtility = require(script.Parent.Parent.Utility.CartModelUtility)
local CartAssemblyValidationService = require(script.Parent.CartAssemblyValidationService)
local CartOccupantService = require(script.Parent.CartOccupantService)
local CartTerrainService = require(script.Parent.CartTerrainService)

type EffectiveMovementProfile = CartMovementTypes.EffectiveMovementProfile
type LongitudinalIntent = CartMovementTypes.LongitudinalIntent
type LongitudinalSnapshot = CartMovementTypes.LongitudinalSnapshot

type RuntimeRecord = {
	Cart: Model,
	Root: BasePart,
	Profile: EffectiveMovementProfile,
	Snapshot: LongitudinalSnapshot,
	ActiveDriver: Player?,
	AuthorityEpoch: number,
	Revision: number,
	LastRequestSequence: number,
	LastIntentEpisode: number,
	LastIntent: LongitudinalIntent,
	RequestWindowStartedAt: number,
	AcceptedRequestsInWindow: number,
	NextSnapshotResponseAt: number,
	Connections: { RBXScriptConnection },
}

local ATTRIBUTES = CartLongitudinalStateMachine.Attributes
local DEPENDENCY_WAIT_TIMEOUT_SECONDS = 10
local MAX_ACCEPTED_REQUESTS_PER_INTERVAL = 2

local log = Logger.new("CartLongitudinalStateService")
local CartLongitudinalStateService = {}

local recordsByCart: { [Model]: RuntimeRecord } = {}
local recordsByDriver: { [Player]: RuntimeRecord } = {}
local driverChangedConnection: RBXScriptConnection? = nil
local requestConnection: RBXScriptConnection? = nil
local intentRemote: RemoteEvent? = nil
local started = false

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function transitionsEqual(first: any, second: any): boolean
	return first == second
		or (
			first ~= nil
			and second ~= nil
			and first.TargetState == second.TargetState
			and first.StartedAt == second.StartedAt
		)
end

local function snapshotsEqual(first: LongitudinalSnapshot, second: LongitudinalSnapshot): boolean
	return first.CurrentState == second.CurrentState
		and first.PreviousState == second.PreviousState
		and first.StateEnteredAt == second.StateEnteredAt
		and transitionsEqual(first.CurrentTransition, second.CurrentTransition)
end

local function publish(record: RuntimeRecord)
	if record.Cart.Parent == nil then
		return
	end

	local snapshot = record.Snapshot
	local transition = snapshot.CurrentTransition

	record.Cart:SetAttribute(ATTRIBUTES.State, snapshot.CurrentState)
	record.Cart:SetAttribute(ATTRIBUTES.PreviousState, snapshot.PreviousState)
	record.Cart:SetAttribute(
		ATTRIBUTES.RequestedState,
		if transition ~= nil then transition.TargetState else snapshot.CurrentState
	)
	record.Cart:SetAttribute(ATTRIBUTES.StateEnteredAt, snapshot.StateEnteredAt)
	record.Cart:SetAttribute(ATTRIBUTES.TransitionStartedAt, if transition ~= nil then transition.StartedAt else 0)
	record.Cart:SetAttribute(ATTRIBUTES.Revision, record.Revision)
	record.Cart:SetAttribute(ATTRIBUTES.AuthorityEpoch, record.AuthorityEpoch)
end

local function sendSnapshot(record: RuntimeRecord, player: Player, requestAccepted: boolean, forceResponse: boolean)
	local remote = intentRemote

	if remote == nil or player.Parent ~= Players then
		return
	end

	local now = Workspace:GetServerTimeNow()

	if not forceResponse and now < record.NextSnapshotResponseAt then
		return
	end

	record.NextSnapshotResponseAt = now + record.Profile.LongitudinalTransitionRetryInterval

	local transition = record.Snapshot.CurrentTransition

	remote:FireClient(
		player,
		record.Cart,
		record.AuthorityEpoch,
		record.Revision,
		record.Snapshot.CurrentState,
		if transition ~= nil then transition.StartedAt else 0,
		record.LastRequestSequence,
		record.LastIntentEpisode,
		requestAccepted
	)
end

local function resetRecord(record: RuntimeRecord, reason: string, advanceEpoch: boolean)
	local previousState = record.Snapshot.CurrentState
	local previousStateEnteredAt = record.Snapshot.StateEnteredAt
	local now = Workspace:GetServerTimeNow()

	if advanceEpoch then
		record.AuthorityEpoch += 1
	end

	record.LastRequestSequence = -1
	record.LastIntentEpisode = -1
	record.LastIntent = "None"
	record.RequestWindowStartedAt = 0
	record.AcceptedRequestsInWindow = 0
	record.NextSnapshotResponseAt = 0
	record.Snapshot = CartLongitudinalStateMachine.Create(now)
	record.Revision += 1
	publish(record)

	if record.ActiveDriver ~= nil then
		sendSnapshot(record, record.ActiveDriver, true, true)
	end

	if previousState ~= "Idle" then
		log:Debug(
			"State Cart=%s CartId=%s DriverUserId=%s Previous=%s Current=Idle Requested=Idle Speed=0.00 TimeInPrevious=%.3f Revision=%d Reason=%s",
			record.Cart.Name,
			record.Profile.CartId,
			if record.ActiveDriver ~= nil then tostring(record.ActiveDriver.UserId) else "none",
			previousState,
			math.max(0, now - previousStateEnteredAt),
			record.Revision,
			reason
		)
	end
end

local function cleanupRecord(record: RuntimeRecord, reason: string): boolean
	if recordsByCart[record.Cart] ~= record then
		return false
	end

	if record.ActiveDriver ~= nil and recordsByDriver[record.ActiveDriver] == record then
		recordsByDriver[record.ActiveDriver] = nil
	end

	recordsByCart[record.Cart] = nil
	disconnectAll(record.Connections)

	log:Debug(
		"Cleared longitudinal state Cart=%s CartId=%s Revision=%d Reason=%s",
		record.Cart.Name,
		record.Profile.CartId,
		record.Revision,
		reason
	)

	return true
end

local function registerCart(cart: Model, profile: EffectiveMovementProfile): (RuntimeRecord?, string?)
	local existing = recordsByCart[cart]

	if existing ~= nil then
		return existing, nil
	end

	if cart.Parent == nil or cart:GetAttribute("RuntimeCart") ~= true then
		return nil, "cart is not an active runtime cart"
	end

	if not CartAssemblyValidationService:IsCartValid(cart) then
		return nil, "cart has not passed runtime assembly validation"
	end

	local cartId = cart:GetAttribute("CartId")

	if type(cartId) ~= "string" or cartId ~= profile.CartId then
		return nil,
			string.format("movement profile CartId mismatch (Cart=%s Profile=%s)", tostring(cartId), profile.CartId)
	end

	local rootSuccess, rootOrError = pcall(function()
		return CartModelUtility.GetRoot(cart)
	end)

	if not rootSuccess then
		return nil, string.format("cart root lookup failed: %s", tostring(rootOrError))
	end

	local activeDriver = CartOccupantService:GetDriver(cart)
	local record: RuntimeRecord = {
		Cart = cart,
		Root = rootOrError :: BasePart,
		Profile = profile,
		Snapshot = CartLongitudinalStateMachine.Create(Workspace:GetServerTimeNow()),
		ActiveDriver = activeDriver,
		AuthorityEpoch = if activeDriver ~= nil then 1 else 0,
		Revision = 0,
		LastRequestSequence = -1,
		LastIntentEpisode = -1,
		LastIntent = "None",
		RequestWindowStartedAt = 0,
		AcceptedRequestsInWindow = 0,
		NextSnapshotResponseAt = 0,
		Connections = {},
	}

	recordsByCart[cart] = record

	if activeDriver ~= nil then
		recordsByDriver[activeDriver] = record
	end

	publish(record)

	table.insert(
		record.Connections,
		cart:GetAttributeChangedSignal("LastServerMovementUpdate"):Connect(function()
			if recordsByCart[cart] == record then
				resetRecord(record, "server movement correction or reset", true)
			end
		end)
	)
	table.insert(
		record.Connections,
		cart.AncestryChanged:Connect(function()
			if cart.Parent == nil then
				task.defer(function()
					cleanupRecord(record, "cart removed from hierarchy")
				end)
			end
		end)
	)

	log:Debug("Initialized longitudinal state Cart=%s CartId=%s Current=Idle", cart.Name, record.Profile.CartId)

	return record, nil
end

local function getSignedForwardSpeed(record: RuntimeRecord): number
	local terrain = CartTerrainService:GetSnapshot(record.Cart)
	local desiredUp = if terrain ~= nil then terrain.DesiredUp else Vector3.yAxis
	local tangentForward = CartTerrainMath.BuildTangentFrame(record.Root.CFrame.LookVector, desiredUp, nil)

	return record.Root.AssemblyLinearVelocity:Dot(tangentForward)
end

local function acquireRequestWindow(record: RuntimeRecord, now: number): boolean
	local interval = record.Profile.LongitudinalTransitionRetryInterval

	if now < record.RequestWindowStartedAt or now - record.RequestWindowStartedAt >= interval then
		record.RequestWindowStartedAt = now
		record.AcceptedRequestsInWindow = 0
	end

	if record.AcceptedRequestsInWindow >= MAX_ACCEPTED_REQUESTS_PER_INTERVAL then
		return false
	end

	record.AcceptedRequestsInWindow += 1

	return true
end

local function handleRequest(
	player: Player,
	requestedCart: unknown,
	throttleValue: unknown,
	expectedEpoch: unknown,
	requestSequence: unknown,
	intentEpisode: unknown
)
	local record = recordsByDriver[player]

	if record == nil or recordsByCart[record.Cart] ~= record then
		return
	end

	if requestedCart ~= record.Cart then
		sendSnapshot(record, player, false, false)
		return
	end

	if
		type(expectedEpoch) ~= "number"
		or expectedEpoch ~= record.AuthorityEpoch
		or type(requestSequence) ~= "number"
		or requestSequence ~= requestSequence
		or math.abs(requestSequence) == math.huge
		or requestSequence < 0
		or requestSequence % 1 ~= 0
		or requestSequence <= record.LastRequestSequence
		or type(intentEpisode) ~= "number"
		or intentEpisode ~= intentEpisode
		or math.abs(intentEpisode) == math.huge
		or intentEpisode < 0
		or intentEpisode % 1 ~= 0
		or intentEpisode < record.LastIntentEpisode
	then
		sendSnapshot(record, player, false, false)
		return
	end

	if type(throttleValue) ~= "number" or throttleValue ~= throttleValue or math.abs(throttleValue) == math.huge then
		sendSnapshot(record, player, false, false)
		return
	end

	if
		record.ActiveDriver ~= player
		or player.Parent ~= Players
		or record.Cart.Parent == nil
		or record.Root.Parent == nil
		or record.Root.Anchored
		or not CartAssemblyValidationService:IsCartValid(record.Cart)
		or not CartOccupantService:CanPlayerControlCart(player, record.Cart)
	then
		return
	end

	local clampedThrottle = math.clamp(throttleValue, -1, 1)
	local requestIntent =
		CartLongitudinalStateMachine.ResolveIntent(clampedThrottle, record.Profile.LongitudinalInputDeadzone)

	if intentEpisode == record.LastIntentEpisode and requestIntent ~= record.LastIntent then
		sendSnapshot(record, player, false, false)
		return
	end

	local now = Workspace:GetServerTimeNow()

	if not acquireRequestWindow(record, now) then
		sendSnapshot(record, player, false, false)
		return
	end

	local forwardSpeed = getSignedForwardSpeed(record)

	record.LastRequestSequence = requestSequence

	local previousIntent = record.LastIntent
	local previousIntentEpisode = record.LastIntentEpisode

	record.LastIntent = requestIntent
	record.LastIntentEpisode = intentEpisode

	local previousSnapshot = record.Snapshot
	local stateInputSnapshot = previousSnapshot

	if
		CartLongitudinalStateMachine.RequiresReverseEpisodeRestart(
			previousIntent,
			requestIntent,
			previousIntentEpisode,
			intentEpisode
		)
	then
		stateInputSnapshot =
			CartLongitudinalStateMachine.Step(stateInputSnapshot, 0, forwardSpeed, now, record.Profile).Snapshot
	end

	local result =
		CartLongitudinalStateMachine.Step(stateInputSnapshot, clampedThrottle, forwardSpeed, now, record.Profile)

	if snapshotsEqual(previousSnapshot, result.Snapshot) then
		-- Every accepted request must receive its acknowledgement even when the
		-- state itself is unchanged. The client uses that acknowledgement to
		-- complete a fresh driver-authority handshake safely.
		sendSnapshot(record, player, true, true)
		return
	end

	record.Snapshot = result.Snapshot
	record.Revision += 1
	publish(record)

	if result.RecoveredFromInvalidState then
		log:Warn(
			"Recovered invalid longitudinal state Cart=%s CartId=%s DriverUserId=%d Revision=%d",
			record.Cart.Name,
			record.Profile.CartId,
			player.UserId,
			record.Revision
		)
	elseif previousSnapshot.CurrentState ~= result.Snapshot.CurrentState then
		log:Debug(
			"State Cart=%s CartId=%s DriverUserId=%d Previous=%s Current=%s Requested=%s Speed=%.2f TimeInPrevious=%.3f Revision=%d",
			record.Cart.Name,
			record.Profile.CartId,
			player.UserId,
			previousSnapshot.CurrentState,
			result.Snapshot.CurrentState,
			result.RequestedState,
			forwardSpeed,
			math.max(0, now - previousSnapshot.StateEnteredAt),
			record.Revision
		)
	end

	sendSnapshot(record, player, true, true)
end

local function getOrCreateRemote(): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes", DEPENDENCY_WAIT_TIMEOUT_SECONDS)

	assert(remotes ~= nil, "Timed out waiting for ReplicatedStorage.Remotes")

	local existing = remotes:FindFirstChild(RemoteNames.CartLongitudinalIntentRequest)

	if existing ~= nil then
		assert(existing:IsA("RemoteEvent"), "CartLongitudinalIntentRequest must be a RemoteEvent")
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = RemoteNames.CartLongitudinalIntentRequest
	remote.Parent = remotes

	return remote
end

local function onDriverChanged(
	cart: Model,
	previousDriver: Player?,
	nextDriver: Player?,
	reason: string,
	_revision: number
)
	local record = recordsByCart[cart]

	if record == nil then
		log:Warn(
			"Ignored driver transition for unregistered longitudinal cart Cart=%s CartId=%s Reason=%s",
			cart.Name,
			tostring(cart:GetAttribute("CartId")),
			reason
		)
		return
	end

	if previousDriver ~= nil and recordsByDriver[previousDriver] == record then
		recordsByDriver[previousDriver] = nil
	end

	record.ActiveDriver = nextDriver

	if nextDriver ~= nil then
		recordsByDriver[nextDriver] = record
	end

	resetRecord(record, reason, true)
end

function CartLongitudinalStateService:RegisterCart(cart: Model, profile: EffectiveMovementProfile): (boolean, string?)
	if not started then
		return false, "longitudinal state service has not started"
	end

	local record, registerError = registerCart(cart, profile)

	return record ~= nil, registerError
end

function CartLongitudinalStateService:UpdateProfile(cart: Model, profile: EffectiveMovementProfile): (boolean, string?)
	local record = recordsByCart[cart]
	if record == nil then
		return false, "cart is not registered with longitudinal state"
	end
	if cart.Parent == nil or cart:GetAttribute("CartId") ~= profile.CartId then
		return false, "movement profile does not match the active cart"
	end

	-- Keep the current intent/state handshake intact. Only future boundary and
	-- retry calculations read the new immutable snapshot.
	record.Profile = profile
	return true, nil
end

function CartLongitudinalStateService:UnregisterCart(cart: Model, reason: string): boolean
	local record = recordsByCart[cart]

	if record == nil then
		return false
	end

	return cleanupRecord(record, reason)
end

function CartLongitudinalStateService:Start()
	if started then
		return
	end

	local remote = getOrCreateRemote()
	intentRemote = remote

	driverChangedConnection = CartOccupantService.DriverChanged:Connect(onDriverChanged)
	requestConnection = remote.OnServerEvent:Connect(handleRequest)
	started = true

	log:Info("Cart longitudinal state service ready")
end

-- Accepted intent for this exact cart/driver generation. Menus, braking,
-- neutral input and driver changes publish None or reset the authority epoch.
function CartLongitudinalStateService:GetMovementAttempt(cart: Model): any?
	local record = recordsByCart[cart]
	if not record then
		return nil
	end
	return {
		Driver = record.ActiveDriver,
		Forward = record.LastIntent == "Forward",
		Brake = record.LastIntent == "Reverse",
		Epoch = record.AuthorityEpoch,
	}
end

function CartLongitudinalStateService:IsCartRegistered(cart: Model): boolean
	return recordsByCart[cart] ~= nil
end

function CartLongitudinalStateService:GetDiagnostics()
	local recordCount = 0
	local driverRecordCount = 0
	local recordConnectionCount = 0

	for _, record in recordsByCart do
		recordCount += 1
		recordConnectionCount += #record.Connections
	end

	for _ in recordsByDriver do
		driverRecordCount += 1
	end

	return table.freeze({
		Started = started,
		RecordCount = recordCount,
		DriverRecordCount = driverRecordCount,
		RecordConnectionCount = recordConnectionCount,
		SharedConnectionCount = (if driverChangedConnection ~= nil then 1 else 0)
			+ (if requestConnection ~= nil then 1 else 0),
		RemoteCount = if intentRemote ~= nil then 1 else 0,
	})
end

function CartLongitudinalStateService:Stop()
	if not started then
		return
	end

	started = false

	if driverChangedConnection ~= nil then
		driverChangedConnection:Disconnect()
		driverChangedConnection = nil
	end

	if requestConnection ~= nil then
		requestConnection:Disconnect()
		requestConnection = nil
	end

	local records: { RuntimeRecord } = {}

	for _, record in recordsByCart do
		table.insert(records, record)
	end

	for _, record in records do
		cleanupRecord(record, "service stopping")
	end

	table.clear(recordsByDriver)
	intentRemote = nil
	log:Info("Cart longitudinal state service stopped")
end

return CartLongitudinalStateService
