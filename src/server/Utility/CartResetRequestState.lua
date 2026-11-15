--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartResetRequestProtocol = require(ReplicatedStorage.Shared.Utility.CartResetRequestProtocol)

type ReasonCode = CartResetRequestProtocol.ReasonCode

export type Config = {
	RequestAttemptInterval: number,
	SuccessfulResetCooldown: number,
	SuspiciousRejectionThreshold: number,
	SuspiciousRejectionWindow: number,
}

type RejectionWindow = {
	StartedAt: number,
	Count: number,
	Logged: boolean,
}

type UserState = {
	LastAttemptAt: number?,
	CooldownExpiresAt: number,
	ProcessingToken: number?,
	NextToken: number,
	Rejections: { [ReasonCode]: RejectionWindow },
}

export type Lease = {
	UserId: number,
	Token: number,
	State: UserState,
}

export type Snapshot = {
	LastAttemptAt: number?,
	CooldownExpiresAt: number,
	Processing: boolean,
	ProcessingToken: number?,
	RejectionCounts: { [string]: number },
}

export type Store = {
	RecordAttempt: (
		self: Store,
		userId: number,
		now: number,
		argumentCount: number
	) -> (boolean, ReasonCode?, number),
	TryAcquire: (self: Store, userId: number, now: number) -> (Lease?, ReasonCode?, number),
	Finish: (self: Store, lease: Lease, completedAt: number, committedSuccess: boolean) -> boolean,
	RecordRejection: (
		self: Store,
		userId: number,
		reason: ReasonCode,
		now: number
	) -> (number, boolean),
	GetCooldownRemaining: (self: Store, userId: number, now: number) -> number,
	GetSnapshot: (self: Store, userId: number) -> Snapshot?,
	GetRecordCount: (self: Store) -> number,
	RemoveLeaseState: (self: Store, lease: Lease) -> boolean,
	RemoveUser: (self: Store, userId: number) -> boolean,
	Clear: (self: Store) -> (),
}

type StoreImplementation = Store & {
	_config: Config,
	_states: { [number]: UserState },
}

local CartResetRequestState = {}
local StoreMethods = {}
StoreMethods.__index = StoreMethods

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function assertUserId(userId: number)
	assert(isFiniteNumber(userId) and userId % 1 == 0, "reset security UserId must be finite")
end

local function assertTime(now: number)
	assert(isFiniteNumber(now), "reset security time must be finite")
end

local function validateConfig(config: Config)
	assert(
		isFiniteNumber(config.RequestAttemptInterval) and config.RequestAttemptInterval > 0,
		"reset request-attempt interval must be positive"
	)
	assert(
		isFiniteNumber(config.SuccessfulResetCooldown) and config.SuccessfulResetCooldown > 0,
		"successful-reset cooldown must be positive"
	)
	assert(
		isFiniteNumber(config.SuspiciousRejectionThreshold)
			and config.SuspiciousRejectionThreshold > 0
			and config.SuspiciousRejectionThreshold % 1 == 0,
		"suspicious-rejection threshold must be a positive integer"
	)
	assert(
		isFiniteNumber(config.SuspiciousRejectionWindow) and config.SuspiciousRejectionWindow > 0,
		"suspicious-rejection window must be positive"
	)
end

local function newUserState(): UserState
	return {
		LastAttemptAt = nil,
		CooldownExpiresAt = 0,
		ProcessingToken = nil,
		NextToken = 1,
		Rejections = {},
	}
end

local function getOrCreateState(self: StoreImplementation, userId: number): UserState
	local state = self._states[userId]

	if state == nil then
		state = newUserState()
		self._states[userId] = state
	end

	return state
end

function StoreMethods:RecordAttempt(
	userId: number,
	now: number,
	argumentCount: number
): (boolean, ReasonCode?, number)
	assertUserId(userId)
	assertTime(now)

	local implementation = self :: StoreImplementation
	local state = getOrCreateState(implementation, userId)
	local previousAttemptAt = state.LastAttemptAt

	-- Every arrival becomes the next rate-limit reference, including malformed
	-- and already-rate-limited requests.
	state.LastAttemptAt = now

	if
		not isFiniteNumber(argumentCount)
		or argumentCount < 0
		or argumentCount % 1 ~= 0
		or argumentCount ~= 0
	then
		return false, CartResetRequestProtocol.ReasonCodes.InvalidRequest, 0
	end

	if previousAttemptAt ~= nil then
		local elapsed = math.max(0, now - previousAttemptAt)

		if elapsed < implementation._config.RequestAttemptInterval then
			return false,
				CartResetRequestProtocol.ReasonCodes.RateLimited,
				implementation._config.RequestAttemptInterval - elapsed
		end
	end

	return true, nil, 0
end

function StoreMethods:TryAcquire(userId: number, now: number): (Lease?, ReasonCode?, number)
	assertUserId(userId)
	assertTime(now)

	local implementation = self :: StoreImplementation
	local state = getOrCreateState(implementation, userId)

	if state.ProcessingToken ~= nil then
		return nil, CartResetRequestProtocol.ReasonCodes.ResetAlreadyActive, 0
	end

	if state.CooldownExpiresAt > now then
		return nil,
			CartResetRequestProtocol.ReasonCodes.CooldownActive,
			state.CooldownExpiresAt - now
	end

	local token = state.NextToken

	state.NextToken += 1
	state.ProcessingToken = token

	return {
		UserId = userId,
		Token = token,
		State = state,
	}, nil, 0
end

function StoreMethods:Finish(lease: Lease, completedAt: number, committedSuccess: boolean): boolean
	assertTime(completedAt)

	local implementation = self :: StoreImplementation
	local state = implementation._states[lease.UserId]

	if state ~= lease.State or state.ProcessingToken ~= lease.Token then
		return false
	end

	state.ProcessingToken = nil

	if committedSuccess then
		state.CooldownExpiresAt = completedAt + implementation._config.SuccessfulResetCooldown
		table.clear(state.Rejections)
	end

	return true
end

function StoreMethods:RecordRejection(
	userId: number,
	reason: ReasonCode,
	now: number
): (number, boolean)
	assertUserId(userId)
	assertTime(now)
	assert(
		CartResetRequestProtocol.IsReasonCode(reason)
			and reason ~= CartResetRequestProtocol.ReasonCodes.Approved,
		"rejection diagnostics require a rejection reason"
	)

	local implementation = self :: StoreImplementation
	local state = implementation._states[userId]

	-- Diagnostics must never recreate state removed by PlayerRemoving or Stop.
	-- Every live request already created its state when RecordAttempt ran.
	if state == nil then
		return 0, false
	end

	local window = state.Rejections[reason]

	if
		window == nil
		or now < window.StartedAt
		or now - window.StartedAt >= implementation._config.SuspiciousRejectionWindow
	then
		window = {
			StartedAt = now,
			Count = 0,
			Logged = false,
		}
		state.Rejections[reason] = window
	end

	window.Count = math.min(window.Count + 1, implementation._config.SuspiciousRejectionThreshold)

	local shouldLog = window.Count >= implementation._config.SuspiciousRejectionThreshold
		and not window.Logged

	if shouldLog then
		window.Logged = true
	end

	return window.Count, shouldLog
end

function StoreMethods:GetCooldownRemaining(userId: number, now: number): number
	assertUserId(userId)
	assertTime(now)

	local implementation = self :: StoreImplementation
	local state = implementation._states[userId]

	return if state ~= nil then math.max(0, state.CooldownExpiresAt - now) else 0
end

function StoreMethods:GetSnapshot(userId: number): Snapshot?
	assertUserId(userId)

	local implementation = self :: StoreImplementation
	local state = implementation._states[userId]

	if state == nil then
		return nil
	end

	local rejectionCounts: { [string]: number } = {}

	for reason, window in state.Rejections do
		rejectionCounts[reason] = window.Count
	end

	return table.freeze({
		LastAttemptAt = state.LastAttemptAt,
		CooldownExpiresAt = state.CooldownExpiresAt,
		Processing = state.ProcessingToken ~= nil,
		ProcessingToken = state.ProcessingToken,
		RejectionCounts = table.freeze(rejectionCounts),
	})
end

function StoreMethods:GetRecordCount(): number
	local implementation = self :: StoreImplementation
	local count = 0

	for _ in implementation._states do
		count += 1
	end

	return count
end

function StoreMethods:RemoveUser(userId: number): boolean
	assertUserId(userId)

	local implementation = self :: StoreImplementation
	local existed = implementation._states[userId] ~= nil

	implementation._states[userId] = nil

	return existed
end

function StoreMethods:RemoveLeaseState(lease: Lease): boolean
	local implementation = self :: StoreImplementation

	if implementation._states[lease.UserId] ~= lease.State then
		return false
	end

	implementation._states[lease.UserId] = nil
	return true
end

function StoreMethods:Clear()
	local implementation = self :: StoreImplementation

	table.clear(implementation._states)
end

function CartResetRequestState.new(config: Config): Store
	validateConfig(config)

	return setmetatable({
		_config = table.freeze(table.clone(config)),
		_states = {},
	}, StoreMethods) :: any
end

return table.freeze(CartResetRequestState)
