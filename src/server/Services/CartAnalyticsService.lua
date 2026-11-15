--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CartAnalytics = require(ReplicatedStorage.Shared.Config.CartAnalytics)
local CartReset = require(ReplicatedStorage.Shared.Config.CartReset)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local CartResetLifecycle = require(ReplicatedStorage.Shared.Utility.CartResetLifecycle)
local CartAnalyticsReasonMapper =
	require(ReplicatedStorage.Shared.Utility.CartAnalyticsReasonMapper)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local CartAnalyticsConfigValidator =
	require(ReplicatedStorage.Shared.Validation.CartAnalyticsConfigValidator)

local CartAnalyticsAdapter = require(script.Parent.Parent.Utility.CartAnalyticsAdapter)
local CartAnalyticsRuntime = require(script.Parent.Parent.Utility.CartAnalyticsRuntime)
local CartMovementValidationService = require(script.Parent.CartMovementValidationService)
local CartOccupantService = require(script.Parent.CartOccupantService)
local CartResetRequestService = require(script.Parent.CartResetRequestService)
local CartService = require(script.Parent.CartService)

type Adapter = CartAnalyticsAdapter.Adapter
type Provider = CartAnalyticsAdapter.Provider
type EventRequest = CartAnalyticsRuntime.EventRequest
type Runtime = CartAnalyticsRuntime.Runtime
type SpawnedCartRecord = CartService.SpawnedCartRecord
type ResetResult = {
	Approved: boolean,
	Reason: string,
}

local log = Logger.new("CartAnalyticsService")
local CartAnalyticsService = {}

local connections: { RBXScriptConnection } = {}
local runtime: Runtime? = nil
local adapter: Adapter? = nil
local configuredProvider: Provider? = nil
local started = false
local reportedCallbackErrors: { [string]: boolean } = {}

local DEVELOPMENT_PROVIDER: Provider = table.freeze({
	Emit = function(_self: Provider, eventName: string, payload: { [string]: any })
		log:Debug(
			"Cart analytics Event=%s RuntimeCartId=%s UserId=%s",
			eventName,
			tostring(payload.RuntimeCartId),
			tostring(payload.PlayerUserId)
		)
	end,
}) :: any

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function runSafely(label: string, callback: () -> ())
	local succeeded, errorMessage = pcall(callback)

	if succeeded then
		return
	end

	local key = string.format("%s:%s", label, tostring(errorMessage))

	if reportedCallbackErrors[key] then
		return
	end

	reportedCallbackErrors[key] = true
	log:Warn("Analytics observer isolated failure Transition=%s Error=%s", label, errorMessage)
end

local function emitRequests(requests: { EventRequest })
	local currentAdapter = adapter

	if currentAdapter == nil then
		return
	end

	for _, request in requests do
		local payload = table.clone(request.Fields)

		payload.EventVersion = CartAnalytics.EventVersion
		payload.BuildId = Environment.BuildId
		payload.Environment = Environment.Name
		payload.ServerTimestamp = request.ServerTimestamp
		payload.PlayerUserId = request.PlayerUserId

		if request.RuntimeCartId ~= nil then
			payload.RuntimeCartId = request.RuntimeCartId
		end

		-- Adapter validation and provider dispatch are both protected. Continue the
		-- ordered sequence even when one best-effort delivery fails.
		currentAdapter:Emit(request.Name, payload)
	end
end

local function handleSpawn(record: SpawnedCartRecord, now: number)
	local currentRuntime = runtime

	if currentRuntime == nil then
		return
	end

	emitRequests(currentRuntime:RegisterCart({
		Key = record.Model,
		OwnerUserId = record.OwnerUserId,
		CartId = record.CartId,
		SpawnId = record.SpawnId,
		SpawnedAt = record.CreatedAt,
	}, now))

	-- Normal bootstrap subscribes before carts spawn. This reconciliation also
	-- preserves the active authoritative driver if the analytics owner is safely
	-- restarted while a ready cart already exists.
	local snapshot = currentRuntime:GetSnapshot(record.Model)
	local previousDriverUserId = if snapshot ~= nil then snapshot.CurrentDriverUserId else nil
	local currentDriver = CartOccupantService:GetDriver(record.Model)
	local currentDriverUserId = if currentDriver ~= nil then currentDriver.UserId else nil

	if previousDriverUserId ~= currentDriverUserId then
		emitRequests(
			currentRuntime:DriverChanged(
				record.Model,
				previousDriverUserId,
				currentDriverUserId,
				"Unknown",
				now,
				"Unknown"
			)
		)
	end
end

local function handleDespawn(record: SpawnedCartRecord, reason: string, now: number)
	local currentRuntime = runtime

	if currentRuntime == nil then
		return
	end

	emitRequests(
		currentRuntime:DespawnCart(
			record.Model,
			CartAnalyticsReasonMapper.Despawn(reason),
			CartAnalyticsReasonMapper.DriverExit(reason),
			now
		)
	)
end

local function handleDriverChanged(
	cart: Model,
	previousDriver: Player?,
	nextDriver: Player?,
	reason: string
)
	local currentRuntime = runtime

	if currentRuntime == nil then
		return
	end

	emitRequests(
		currentRuntime:DriverChanged(
			cart,
			if previousDriver ~= nil then previousDriver.UserId else nil,
			if nextDriver ~= nil then nextDriver.UserId else nil,
			CartAnalyticsReasonMapper.DriverExit(reason),
			Workspace:GetServerTimeNow(),
			"Unknown"
		)
	)
end

local function handleMovementStarted(cart: Model, driver: Player, direction: string, now: number)
	local currentRuntime = runtime

	if currentRuntime == nil or (direction ~= "Forward" and direction ~= "Reverse") then
		return
	end

	emitRequests(
		currentRuntime:MovementStarted(
			cart,
			driver.UserId,
			direction :: CartAnalyticsRuntime.MovementDirection,
			now
		)
	)
end

local function finiteAttribute(cart: Model, attribute: string): number?
	local value = cart:GetAttribute(attribute)

	if type(value) == "number" and value == value and math.abs(value) < math.huge then
		return value
	end

	return nil
end

local function handleResetProcessed(
	player: Player,
	cartRecord: SpawnedCartRecord?,
	result: ResetResult,
	requestReceivedAt: number,
	requestCompletedAt: number,
	_argumentCount: number
)
	local currentRuntime = runtime

	if currentRuntime == nil then
		return
	end

	local cart = if cartRecord ~= nil then cartRecord.Model else nil
	local resetStartedAt = if cart ~= nil
		then finiteAttribute(cart, CartResetLifecycle.Attributes.StartedAt)
		else nil
	local resetCompletedAt = if cart ~= nil
		then finiteAttribute(cart, CartResetLifecycle.Attributes.CompletedAt)
		else nil

	emitRequests(currentRuntime:RecordResetOutcome({
		PlayerUserId = player.UserId,
		CartKey = cart,
		Approved = result.Approved,
		Reason = result.Reason,
		RequestedAt = requestReceivedAt,
		CompletedAt = requestCompletedAt,
		ResetStartedAt = resetStartedAt,
		ResetCompletedAt = resetCompletedAt,
	}))
end

local function handleCorrection(
	cart: Model,
	_driver: Player?,
	category: string,
	severity: string,
	reason: string,
	revision: number,
	now: number
)
	local currentRuntime = runtime

	if currentRuntime == nil then
		return
	end

	emitRequests(currentRuntime:RecordCorrection({
		CartKey = cart,
		Revision = revision,
		Category = category,
		Severity = if severity == "Severe" then "Severe" else "Corrective",
		Reason = reason,
		ServerTimestamp = now,
	}))
end

function CartAnalyticsService:SetProvider(provider: Provider?)
	assert(not started, "analytics provider must be configured before service start")
	configuredProvider = provider
end

function CartAnalyticsService:GetSnapshot(cart: Model): CartAnalyticsRuntime.Snapshot?
	local currentRuntime = runtime

	return if currentRuntime ~= nil then currentRuntime:GetSnapshot(cart) else nil
end

function CartAnalyticsService:GetRecordCount(): number
	local currentRuntime = runtime

	return if currentRuntime ~= nil then currentRuntime:GetRecordCount() else 0
end

function CartAnalyticsService:GetDiagnostics()
	return table.freeze({
		Started = started,
		RecordCount = self:GetRecordCount(),
		SharedConnectionCount = #connections,
		AdapterActive = if adapter ~= nil then 1 else 0,
		ProviderConfigured = if configuredProvider ~= nil then 1 else 0,
	})
end

function CartAnalyticsService:Start()
	if started then
		return
	end

	local validation = CartAnalyticsConfigValidator.Validate(CartAnalytics)

	if not validation.IsValid then
		for _, validationError in validation.Errors do
			log:Warn("Invalid cart analytics configuration: %s", validationError)
		end

		return
	end

	local provider = configuredProvider

	if provider == nil and not Environment.IsProduction then
		provider = DEVELOPMENT_PROVIDER
	end

	adapter = CartAnalyticsAdapter.new({
		Enabled = CartAnalytics.Enabled,
		Provider = provider,
	})

	if runtime == nil then
		runtime = CartAnalyticsRuntime.new(CartReset.RequestAttemptInterval)
	end

	started = true
	table.clear(reportedCallbackErrors)

	table.insert(
		connections,
		CartService.CartSpawned:Connect(function(record, now)
			runSafely("CartSpawned", function()
				handleSpawn(record, now)
			end)
		end)
	)
	table.insert(
		connections,
		CartService.CartDespawned:Connect(function(record, reason, now)
			runSafely("CartDespawned", function()
				handleDespawn(record, reason, now)
			end)
		end)
	)
	table.insert(
		connections,
		CartOccupantService.DriverChanged:Connect(function(cart, previousDriver, nextDriver, reason)
			runSafely("DriverChanged", function()
				handleDriverChanged(cart, previousDriver, nextDriver, reason)
			end)
		end)
	)
	table.insert(
		connections,
		CartMovementValidationService.MeaningfulMovementStarted:Connect(
			function(cart, driver, direction, now)
				runSafely("MeaningfulMovementStarted", function()
					handleMovementStarted(cart, driver, direction, now)
				end)
			end
		)
	)
	table.insert(
		connections,
		CartMovementValidationService.CorrectionApplied:Connect(
			function(cart, driver, category, severity, reason, revision, now)
				runSafely("CorrectionApplied", function()
					handleCorrection(cart, driver, category, severity, reason, revision, now)
				end)
			end
		)
	)
	table.insert(
		connections,
		CartResetRequestService.ResetProcessed:Connect(
			function(
				player,
				cartRecord,
				result,
				requestReceivedAt,
				requestCompletedAt,
				argumentCount
			)
				runSafely("ResetProcessed", function()
					handleResetProcessed(
						player,
						cartRecord,
						result,
						requestReceivedAt,
						requestCompletedAt,
						argumentCount
					)
				end)
			end
		)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			local currentRuntime = runtime

			if currentRuntime ~= nil then
				currentRuntime:RemovePlayer(player.UserId)
			end
		end)
	)

	-- Bootstrap starts this owner before the Development spawner. Reconciliation
	-- also makes a deliberate analytics-owner restart idempotent: unchanged carts
	-- keep their runtime IDs and spawn deduplication, while transitions that took
	-- place with instrumentation stopped are not reconstructed speculatively.
	local currentRuntime = runtime :: Runtime
	local readyRecords = CartService:GetCartRecords()
	local readyModels: { [Model]: boolean } = {}
	local reconciliationTime = Workspace:GetServerTimeNow()

	for _, record in readyRecords do
		readyModels[record.Model] = true
	end

	for _, cartKey in currentRuntime:GetRegisteredKeys() do
		if typeof(cartKey) == "Instance" and cartKey:IsA("Model") and not readyModels[cartKey] then
			currentRuntime:DiscardCart(cartKey)
		end
	end

	for _, record in readyRecords do
		runSafely("ExistingCart", function()
			handleSpawn(record, reconciliationTime)
		end)
	end

	log:Info(
		"Cart analytics ready Enabled=%s Provider=%s EventVersion=%d PlatformPolicy=Unknown",
		tostring(CartAnalytics.Enabled),
		if configuredProvider ~= nil
			then "Injected"
			elseif Environment.IsProduction then "Noop"
			else "DevelopmentLog",
		CartAnalytics.EventVersion
	)
end

function CartAnalyticsService:Stop()
	if not started then
		return
	end

	started = false
	disconnectAll()

	-- Preserve only bounded, runtime-cart correlation state across an intentional
	-- owner restart. Actual cart/driver teardown remains authoritative and clears
	-- records through its normal signals; server shutdown releases module memory.
	adapter = nil
	table.clear(reportedCallbackErrors)
	log:Info("Cart analytics stopped")
end

return CartAnalyticsService
