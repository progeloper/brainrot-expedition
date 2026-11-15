--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CartReset = require(ReplicatedStorage.Shared.Config.CartReset)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local CartResetRequestProtocol = require(ReplicatedStorage.Shared.Utility.CartResetRequestProtocol)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CartResetRequestState = require(script.Parent.Parent.Utility.CartResetRequestState)
local CartService = require(script.Parent.CartService)

type ReasonCode = CartResetRequestProtocol.ReasonCode
type Result = CartResetRequestProtocol.Result
type RequestStore = CartResetRequestState.Store

type CartContext = {
	Cart: Model,
	CartId: string,
	CartName: string,
}

local log = Logger.new("CartResetRequestService")
local CartResetRequestService = {}
local resetProcessedEvent = Instance.new("BindableEvent")

-- One authoritative domain signal carries the server-received request and its
-- terminal Phase 1K/1J result. Phase 1R expands it into ordered requested and
-- approved/rejected/completed events without putting provider logic here.
CartResetRequestService.ResetProcessed = resetProcessedEvent.Event

local DEPENDENCY_WAIT_TIMEOUT_SECONDS = 10

local requestStore: RequestStore? = nil
local developmentStateReservations: { [number]: boolean } = {}
local resetRemote: RemoteFunction? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local started = false

local function getServerTime(): number
	return Workspace:GetServerTimeNow()
end

local function bindRemote(handler: (Player, ...any) -> Result): RemoteFunction
	local remotes = ReplicatedStorage:WaitForChild("Remotes", DEPENDENCY_WAIT_TIMEOUT_SECONDS)

	assert(remotes ~= nil, "Timed out waiting for ReplicatedStorage.Remotes")

	local existing = remotes:FindFirstChild(RemoteNames.CartResetRequest)

	if existing ~= nil then
		assert(existing:IsA("RemoteFunction"), "CartResetRequest must be a RemoteFunction")
		existing.OnServerInvoke = handler
		return existing
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = RemoteNames.CartResetRequest
	remote.OnServerInvoke = handler
	remote.Parent = remotes

	return remote
end

local function formatCartContext(context: CartContext?): (string, string)
	return if context ~= nil then context.CartName else "unknown", if context ~= nil then context.CartId else "unknown"
end

local function reportRejection(
	player: Player,
	context: CartContext?,
	reason: ReasonCode,
	retryAfterSeconds: number,
	rejectionCount: number,
	suspicious: boolean,
	internalDetail: string?
)
	local cartName, cartId = formatCartContext(context)

	if reason == CartResetRequestProtocol.ReasonCodes.InternalFailure then
		log:Warn(
			"Reset Request Internal Failure UserId=%d Cart=%s CartId=%s Reason=%s Detail=%s",
			player.UserId,
			cartName,
			cartId,
			reason,
			internalDetail or "unavailable"
		)
	elseif suspicious and Environment.Name == "Development" then
		log:Warn(
			"Repeated Reset Request Rejections UserId=%d Cart=%s CartId=%s Reason=%s Count=%d RetryAfter=%.3f",
			player.UserId,
			cartName,
			cartId,
			reason,
			rejectionCount,
			retryAfterSeconds
		)
	else
		log:Debug(
			"Reset Request Rejected UserId=%d Cart=%s CartId=%s Reason=%s RetryAfter=%.3f Count=%d",
			player.UserId,
			cartName,
			cartId,
			reason,
			retryAfterSeconds,
			rejectionCount
		)
	end
end

local function createRejection(
	player: Player,
	context: CartContext?,
	reason: ReasonCode,
	retryAfterSeconds: number,
	now: number,
	safeToResume: boolean,
	internalDetail: string?
): Result
	local store = requestStore
	local rejectionCount = 0
	local suspicious = false

	if store ~= nil and player.Parent == Players then
		rejectionCount, suspicious = store:RecordRejection(player.UserId, reason, now)
	end

	reportRejection(player, context, reason, retryAfterSeconds, rejectionCount, suspicious, internalDetail)

	return CartResetRequestProtocol.CreateResult(false, reason, retryAfterSeconds, now, safeToResume)
end

local function processRequest(player: Player, argumentCount: number): Result
	-- Keep the installed request throttle for stale clients while retiring the
	-- action itself. No payload, lease, driver state or cooldown grants movement.
	local store = requestStore
	local now = getServerTime()
	if store and player.Parent == Players then
		local allowed, reason, retry = store:RecordAttempt(player.UserId, now, argumentCount)
		if not allowed then
			return createRejection(
				player,
				nil,
				reason or CartResetRequestProtocol.ReasonCodes.InvalidRequest,
				retry,
				now,
				true,
				nil
			)
		end
	end
	return createRejection(
		player,
		nil,
		CartResetRequestProtocol.ReasonCodes.ResetUnavailable,
		0,
		getServerTime(),
		true,
		"Manual reset removed; correction is automatic"
	)
end

local function handleRequest(player: Player, ...: any): Result
	local requestReceivedAt = getServerTime()
	local argumentCount = select("#", ...)
	local cartRecord = CartService:GetCartRecord(player)
	local result = processRequest(player, argumentCount)

	resetProcessedEvent:Fire(player, cartRecord, result, requestReceivedAt, getServerTime(), argumentCount)

	return result
end

function CartResetRequestService:Start()
	if started then
		return
	end

	requestStore = CartResetRequestState.new({
		RequestAttemptInterval = CartReset.RequestAttemptInterval,
		SuccessfulResetCooldown = CartReset.SuccessfulResetCooldown,
		SuspiciousRejectionThreshold = CartReset.SuspiciousRejectionThreshold,
		SuspiciousRejectionWindow = CartReset.SuspiciousRejectionWindow,
	})
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		local store = requestStore

		if store ~= nil then
			store:RemoveUser(player.UserId)
		end
	end)
	started = true
	resetRemote = bindRemote(handleRequest)

	log:Info(
		"Cart reset request security ready AttemptInterval=%.1f Cooldown=%.1f",
		CartReset.RequestAttemptInterval,
		CartReset.SuccessfulResetCooldown
	)
end

local function isDevelopmentRequestAvailable(): boolean
	return Environment.Name == "Development" and Environment.EnableDebugTools and RunService:IsStudio()
end

function CartResetRequestService:ReserveDevelopmentRequestState(userId: number): (boolean, string?)
	if not isDevelopmentRequestAvailable() then
		return false, "Development reset requests are unavailable outside Development Studio"
	end

	local store = requestStore

	if not started or store == nil then
		return false, "reset request service is not started"
	end

	if developmentStateReservations[userId] == true then
		return true, nil
	end

	if store:GetSnapshot(userId) ~= nil then
		return false, "test player already has authoritative reset-security state"
	end

	developmentStateReservations[userId] = true

	return true, nil
end

function CartResetRequestService:ProcessDevelopmentRequest(player: Player): (Result?, string?)
	if not isDevelopmentRequestAvailable() then
		return nil, "Development reset requests are unavailable outside Development Studio"
	end

	if not started then
		return nil, "reset request service is not started"
	end

	if developmentStateReservations[player.UserId] ~= true then
		return nil, "Development reset-request state was not reserved for this test player"
	end

	-- This server-only Phase 1T hook deliberately traverses the same Phase 1K
	-- handler as the RemoteFunction. It accepts no payload, cart, destination, or
	-- arbitrary timing and therefore cannot create a second reset-security path.
	return handleRequest(player), nil
end

function CartResetRequestService:ClearDevelopmentRequestState(userId: number): (boolean, string?)
	if not isDevelopmentRequestAvailable() then
		return false, "Development reset-request cleanup is unavailable outside Development Studio"
	end

	local store = requestStore

	if not started or store == nil then
		return false, "reset request service is not started"
	end

	if developmentStateReservations[userId] ~= true then
		return false, "Development reset-request state is not owned by the harness"
	end

	-- Reservation succeeds only when no authoritative state existed for this user,
	-- so cleanup cannot erase a pre-existing cooldown or rejection record.
	store:RemoveUser(userId)
	developmentStateReservations[userId] = nil

	return true, nil
end

function CartResetRequestService:GetDiagnostics()
	local store = requestStore

	return table.freeze({
		Started = started,
		SecurityRecordCount = if store ~= nil then store:GetRecordCount() else 0,
		DevelopmentReservationCount = (function(): number
			local count = 0

			for _ in developmentStateReservations do
				count += 1
			end

			return count
		end)(),
		SharedConnectionCount = if playerRemovingConnection ~= nil then 1 else 0,
		RemoteCount = if resetRemote ~= nil then 1 else 0,
	})
end

function CartResetRequestService:Stop()
	if not started then
		return
	end

	started = false

	if resetRemote ~= nil then
		resetRemote.OnServerInvoke = nil
		resetRemote = nil
	end

	if playerRemovingConnection ~= nil then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	if requestStore ~= nil then
		requestStore:Clear()
		requestStore = nil
	end

	table.clear(developmentStateReservations)

	log:Info("Cart reset request security stopped")
end

return CartResetRequestService
