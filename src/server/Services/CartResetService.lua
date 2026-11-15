--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local CartResetLifecycle = require(ReplicatedStorage.Shared.Utility.CartResetLifecycle)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Config = require(ReplicatedStorage.Shared.Config.CartLocalCorrection)
local Stuck = require(ReplicatedStorage.Shared.Utility.CartStuckAttempt)
local ResetMath = require(ReplicatedStorage.Shared.Utility.CartResetMath)
local Placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
local Longitudinal = require(script.Parent.CartLongitudinalStateService)
local Terrain = require(script.Parent.CartTerrainService)

local CartAssemblyValidationService = require(script.Parent.CartAssemblyValidationService)
local CartService = require(script.Parent.CartService)

type ResetState = CartResetLifecycle.ResetState
type ResetSnapshot = CartResetLifecycle.Snapshot
type ResetStage = "Suspension" | "Reposition" | "Recovery" | "Resume"

type RuntimeReset = {
	Player: Player,
	Cart: Model,
	CartId: string,
	Snapshot: ResetSnapshot,
	Finalized: boolean,
	FailureLogged: boolean,
	CartDestroyingConnection: RBXScriptConnection?,
}

local log = Logger.new("CartResetService")
local CartResetService = {}

local resetsByPlayer: { [Player]: RuntimeReset } = {}
local resetsByCart: { [Model]: RuntimeReset } = {}
local playerRemovingConnection: RBXScriptConnection? = nil
local started = false
local sampleConnection: RBXScriptConnection? = nil
local attempts: { [Model]: any } = {}
local lastSampleAt = -math.huge
local diagnostics = { Samples = 0, Attempts = 0, Completed = 0, Blocked = 0 }

local function transition(record: RuntimeReset, targetState: ResetState): (boolean, string?)
	local nextSnapshot, transitionError =
		CartResetLifecycle.Transition(record.Snapshot, targetState, Workspace:GetServerTimeNow())

	if nextSnapshot == nil then
		return false, transitionError
	end

	record.Snapshot = nextSnapshot
	if record.Cart.Parent then
		record.Cart:SetAttribute(
			CartResetLifecycle.Attributes.Active,
			CartResetLifecycle.IsExecutionActive(targetState)
		)
		if targetState == "Suspension" then
			record.Cart:SetAttribute(CartResetLifecycle.Attributes.StartedAt, nextSnapshot.StateEnteredAt)
		end
		if targetState == "Resume" then
			record.Cart:SetAttribute(CartResetLifecycle.Attributes.CompletedAt, nextSnapshot.StateEnteredAt)
		end
	end
	return true, nil
end

local function clearRecord(record: RuntimeReset)
	record.Finalized = true

	if record.CartDestroyingConnection ~= nil then
		record.CartDestroyingConnection:Disconnect()
		record.CartDestroyingConnection = nil
	end

	if resetsByPlayer[record.Player] == record then
		resetsByPlayer[record.Player] = nil
	end

	if resetsByCart[record.Cart] == record then
		resetsByCart[record.Cart] = nil
	end
end

local function failRecord(record: RuntimeReset, reason: string, retainSuspended: boolean?)
	if record.Finalized then
		return
	end

	if CartResetLifecycle.CanTransition(record.Snapshot.CurrentState, "Failed") then
		transition(record, "Failed")
	end

	if retainSuspended ~= true and record.Snapshot.CurrentState == "Failed" then
		transition(record, "Idle")
	end

	if retainSuspended ~= true then
		clearRecord(record)
	end

	if not record.FailureLogged then
		record.FailureLogged = true
		log:Warn(
			"Reset Failed Player=%s UserId=%d Cart=%s CartId=%s Reason=%s",
			record.Player.Name,
			record.Player.UserId,
			record.Cart.Name,
			record.CartId,
			reason
		)
	end
end

local function createRecord(player: Player, cart: Model, cartId: string): (RuntimeReset?, string?)
	local now = Workspace:GetServerTimeNow()
	local record: RuntimeReset = {
		Player = player,
		Cart = cart,
		CartId = cartId,
		Snapshot = CartResetLifecycle.Create(now),
		Finalized = false,
		FailureLogged = false,
		CartDestroyingConnection = nil,
	}

	for _, state in { "HoldStarted", "HoldComplete", "Validation" } do
		local transitioned, transitionError = transition(record, state :: ResetState)

		if not transitioned then
			return nil, transitionError
		end
	end

	return record, nil
end

local function validateResetStart(player: Player, expectedCart: Model): (CartService.SpawnedCartRecord?, string?)
	if player.Parent ~= Players then
		return nil, "player is no longer active"
	end

	local cartRecord = CartService:GetCartRecord(player)

	if cartRecord == nil then
		return nil, "player has no active cart"
	end

	local cart = cartRecord.Model

	if cart ~= expectedCart then
		return nil, "active cart changed before reset began"
	end

	if cart.Parent == nil or cart:GetAttribute("RuntimeCart") ~= true then
		return nil, "cart is destroyed or inactive"
	end

	if resetsByPlayer[player] ~= nil or resetsByCart[cart] ~= nil then
		return nil, "cart is already resetting"
	end

	if cart:GetAttribute(CartResetLifecycle.Attributes.Active) == true then
		return nil, "cart is already resetting"
	end

	if not CartAssemblyValidationService:IsCartValid(cart) then
		return nil, "cart assembly is not valid"
	end

	if not CartService:IsAuthorizedDriver(player, cart) then
		return nil, "player must be the active driver"
	end

	return cartRecord, nil
end

function CartResetService:IsResetActive(player: Player, cart: Model): boolean
	return resetsByPlayer[player] ~= nil
		or resetsByCart[cart] ~= nil
		or cart:GetAttribute(CartResetLifecycle.Attributes.Active) == true
end

local function beginCorrection(player: Player, expectedCart: Model, plan: any): (boolean, string?, boolean)
	if not started then
		return false, "reset lifecycle service is not running", true
	end

	local cartRecord, validationError = validateResetStart(player, expectedCart)

	if cartRecord == nil then
		return false, validationError or "reset validation failed", true
	end

	local record, recordError = createRecord(player, cartRecord.Model, cartRecord.CartId)

	if record == nil then
		return false, recordError or "reset lifecycle could not start", true
	end

	resetsByPlayer[player] = record
	resetsByCart[cartRecord.Model] = record
	record.CartDestroyingConnection = cartRecord.Model.Destroying:Connect(function()
		failRecord(record, "cart destroyed during reset", false)
	end)

	log:Info(
		"Reset Started Player=%s UserId=%d Cart=%s CartId=%s SpawnId=%s",
		player.Name,
		player.UserId,
		cartRecord.Model.Name,
		cartRecord.CartId,
		cartRecord.SpawnId
	)

	local function advanceStage(stage: ResetStage): (boolean, string?)
		if resetsByPlayer[player] ~= record or resetsByCart[record.Cart] ~= record then
			return false, "reset transaction is stale"
		end

		local currentRecord = CartService:GetCartRecord(player)

		if currentRecord ~= cartRecord or currentRecord.Model ~= record.Cart then
			return false, "cart was destroyed or replaced during reset"
		end

		return transition(record, stage :: ResetState)
	end

	local callSucceeded, resetSucceeded, resetError, safeToResume = pcall(function()
		return CartService:CorrectCartLocal(player, plan, advanceStage)
	end)

	if not callSucceeded then
		local cartSafeToResume = not (
			record.Cart.Parent ~= nil and record.Cart:GetAttribute(CartResetLifecycle.Attributes.Active) == true
		)

		failRecord(record, string.format("reset execution errored: %s", tostring(resetSucceeded)), not cartSafeToResume)
		return false, "Reset failed", cartSafeToResume
	end

	if not resetSucceeded then
		failRecord(record, resetError or "reset execution failed", safeToResume ~= true)
		return false, resetError or "Reset failed", safeToResume == true
	end

	if record.Snapshot.CurrentState ~= "Resume" then
		failRecord(record, "reset execution completed before the Resume stage")
		return false, "Reset failed", true
	end

	local returnedToIdle, idleError = transition(record, "Idle")

	if not returnedToIdle then
		failRecord(record, idleError or "reset lifecycle could not return to Idle")
		return false, "Reset failed", true
	end

	clearRecord(record)

	log:Info(
		"Reset Complete Player=%s UserId=%d Cart=%s CartId=%s",
		player.Name,
		player.UserId,
		cartRecord.Model.Name,
		cartRecord.CartId
	)

	return true, nil, true
end

function CartResetService:BeginReset(_player: Player, _expectedCart: Model): (boolean, string?, boolean)
	return false, "Manual reset removed; correction is automatic", true
end

function CartResetService:ConfigurePlacement(options: any)
	Placement.Configure(options)
end

local function sample(now: number)
	if not Config.Enabled or now - lastSampleAt < Config.SampleInterval then
		return
	end
	lastSampleAt = now
	local present = {}
	for _, record in CartService:GetCartRecords() do
		local cart = record.Model
		present[cart] = true
		local attempt = attempts[cart]
		if not attempt then
			attempt = { State = Stuck.Create(), Heading = nil, Driver = nil, Epoch = nil, InFlight = false }
			attempts[cart] = attempt
		end
		local input = Longitudinal:GetMovementAttempt(cart)
		local driver = input and input.Driver
		local root = cart:FindFirstChild("Root")
		if not root or not root:IsA("BasePart") then
			Stuck.Clear(attempt.State)
			continue
		end
		local heading = ResetMath.FlattenHeading(root.CFrame.LookVector)
		if heading then
			attempt.Heading = heading
		end
		if attempt.Driver ~= driver or attempt.Epoch ~= (input and input.Epoch) then
			Stuck.Clear(attempt.State)
			attempt.Driver, attempt.Epoch = driver, input and input.Epoch
		end
		local eligible = driver ~= nil
			and input.Forward
			and not input.Brake
			and not attempt.InFlight
			and not CartResetService:IsResetActive(driver, cart)
			and CartService:IsAuthorizedDriver(driver, cart)
			and not root.Anchored
			and (driver:GetAttribute("Phase10DazeEnd") or 0) <= now
			and driver:GetAttribute("TeamManagementOpen") ~= true
		local supported = false
		if eligible then
			local terrain = Terrain:GetSnapshot(cart)
			-- The existing upright sampler already proves ordinary support. A
			-- overturned cart uses a bounded world-down body-contact check.
			if root.CFrame.UpVector.Y > 0.15 and terrain and os.clock() - terrain.SampledAt < 0.5 then
				supported = terrain.Grounded
			else
				if now - (attempt.SupportAt or -math.huge) >= 0.2 then
					attempt.Support, attempt.SupportAt = Placement.IsSupported(cart), now
				end
				supported = attempt.Support == true
			end
		end
		diagnostics.Samples += 1
		if not Stuck.Step(attempt.State, root.Position, eligible and supported, now, Config) then
			continue
		end
		diagnostics.Attempts += 1
		local desired = heading
			or attempt.Heading
			or ResetMath.FlattenHeading(record.SpawnCFrame.LookVector)
			or -Vector3.zAxis
		local plan, reason = Placement.Prepare(cart, driver, desired)
		if not plan then
			diagnostics.Blocked += 1
			cart:SetAttribute("LocalCorrectionBlockedReason", reason)
			continue
		end
		attempt.InFlight = true
		Stuck.Clear(attempt.State)
		local expectedDriver, expectedEpoch = driver, input.Epoch
		task.spawn(function()
			-- Staging does not grant a lease across a later driver/input change.
			local latest = Longitudinal:GetMovementAttempt(cart)
			if
				not latest
				or latest.Driver ~= expectedDriver
				or latest.Epoch ~= expectedEpoch
				or not latest.Forward
				or latest.Brake
			then
				attempt.InFlight = false
				return
			end
			local succeeded, failure = beginCorrection(expectedDriver, cart, plan)
			attempt.InFlight = false
			if succeeded then
				diagnostics.Completed += 1
				cart:SetAttribute("LocalCorrectionBlockedReason", nil)
				-- Existing feedback consumers can display the authoritative concise result.
				expectedDriver:SetAttribute("Phase10CartCorrectionAt", Workspace:GetServerTimeNow())
			else
				cart:SetAttribute("LocalCorrectionBlockedReason", failure)
			end
		end)
	end
	for cart in attempts do
		if not present[cart] then
			attempts[cart] = nil
		end
	end
end

function CartResetService:Start()
	if started then
		return
	end

	started = true
	sampleConnection = RunService.Heartbeat:Connect(function()
		sample(Workspace:GetServerTimeNow())
	end)

	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		local record = resetsByPlayer[player]

		if record ~= nil then
			failRecord(record, "player left during reset", false)
		end
	end)

	log:Info("Cart reset lifecycle service ready")
end

function CartResetService:GetDiagnostics()
	local playerRecordCount = 0
	local cartRecordCount = 0
	local activeCartConnectionCount = 0

	for _, record in resetsByPlayer do
		playerRecordCount += 1

		if record.CartDestroyingConnection ~= nil then
			activeCartConnectionCount += 1
		end
	end

	for _ in resetsByCart do
		cartRecordCount += 1
	end

	return table.freeze({
		Started = started,
		PlayerRecordCount = playerRecordCount,
		CartRecordCount = cartRecordCount,
		ActiveCartConnectionCount = activeCartConnectionCount,
		SharedConnectionCount = (if playerRemovingConnection ~= nil then 1 else 0)
			+ (if sampleConnection ~= nil then 1 else 0),
		Automatic = table.clone(diagnostics),
		PlacementQueries = Placement.GetDiagnostics(),
	})
end

function CartResetService:Stop()
	if not started then
		return
	end

	started = false
	if sampleConnection then
		sampleConnection:Disconnect()
		sampleConnection = nil
	end
	table.clear(attempts)

	if playerRemovingConnection ~= nil then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	local activeRecords: { RuntimeReset } = {}

	for _, record in resetsByPlayer do
		table.insert(activeRecords, record)
	end

	for _, record in activeRecords do
		failRecord(record, "reset service stopped", false)
	end

	table.clear(resetsByPlayer)
	table.clear(resetsByCart)

	log:Info("Cart reset lifecycle service stopped")
end

return CartResetService
