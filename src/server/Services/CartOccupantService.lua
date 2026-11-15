--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local SeatContract = require(ReplicatedStorage.Shared.Utility.CartSeatContract)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CartDriverAuthority = require(script.Parent.Parent.Utility.CartDriverAuthority)
local CartDriverPolicy = require(script.Parent.Parent.Utility.CartDriverPolicy)
local CartModelUtility = require(script.Parent.Parent.Utility.CartModelUtility)
local CartAssemblyValidationService = require(script.Parent.CartAssemblyValidationService)

type Authority = CartDriverAuthority.Authority
type DriverCandidate = CartDriverAuthority.DriverCandidate
type DriverRecord = CartDriverAuthority.DriverRecord

type SeatExitToken = {
	Humanoid: Humanoid,
	Character: Model,
	Player: Player?,
	DriverSeat: VehicleSeat,
	OccupancySequence: number,
	DriverRevision: number,
	NativeWeld: JointInstance?,
	NativeWeldCaptured: boolean,
	Steps: number,
	ExitRequested: boolean,
}

type ConnectionRecord = {
	CartConnections: { RBXScriptConnection },
	DriverConnections: { RBXScriptConnection },
	OccupancySequence: number,
	PendingSeatExit: SeatExitToken?,
}

local ACTIVE_DRIVER_ATTRIBUTE = "ActiveDriverUserId"

local log = Logger.new("CartOccupantService")
local driverChangedEvent = Instance.new("BindableEvent")
local occupantsChangedEvent = Instance.new("BindableEvent")

local CartOccupantService = {}

local connectionsByCart: { [Model]: ConnectionRecord } = {}
local pendingSeatExits: { [Model]: { Registration: ConnectionRecord, Token: SeatExitToken } } = {}
local seatExitHeartbeatConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local started = false
local authority: Authority
local isCarrying: ((Player) -> boolean)? = nil
local driverEligibility: ((Player) -> (boolean, string?))? = nil
local carryChangedSignal: RBXScriptSignal? = nil
local carryChangedConnection: RBXScriptConnection? = nil

local function dazeDeadline(player: Player?): number?
	if not player or type(player.GetAttribute) ~= "function" then
		return nil
	end
	local deadline = player:GetAttribute("Phase10DazeEnd")
	return if type(deadline) == "number" then deadline else nil
end

function CartOccupantService:SetCarryingPredicate(predicate: ((Player) -> boolean)?, changedSignal: RBXScriptSignal?)
	if carryChangedConnection then
		carryChangedConnection:Disconnect()
		carryChangedConnection = nil
	end
	isCarrying = predicate
	carryChangedSignal = changedSignal
	if changedSignal then
		carryChangedConnection = changedSignal:Connect(function(player)
			self:EnforceCarryRestriction(player)
		end)
	end
	for cart in connectionsByCart do
		local driver = authority:GetDriver(cart)
		if driver then
			self:EnforceCarryRestriction(driver)
		end
	end
end

-- Bootstrap supplies existing profile/world readiness without circular service
-- dependencies. Every admission and accepted input re-reads this predicate.
function CartOccupantService:SetDriverEligibilityPredicate(predicate: ((Player) -> (boolean, string?))?)
	driverEligibility = predicate
	for cart in connectionsByCart do
		for _, player in self:GetOccupants(cart) do
			self:EnforceDriverEligibility(player)
		end
	end
end

function CartOccupantService:CanEnterDriver(player: Player): (boolean, string?)
	if driverEligibility then
		local eligible, reason = driverEligibility(player)
		if not eligible then
			return false, reason or "player is not ready"
		end
	end
	if isCarrying and isCarrying(player) then
		return false, "carrying a brainrot"
	end
	return true, nil
end

function CartOccupantService:IsDriving(player: Player): boolean
	if authority:GetCartDrivenBy(player) ~= nil then
		return true
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid then humanoid.SeatPart else nil
	if not seat or not (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
		return false
	end
	-- Include actual seat entry before the authority's Occupant callback runs.
	for cart in connectionsByCart do
		if seat == cart:FindFirstChild("DriverSeat") and seat.Occupant == humanoid then
			return true
		end
	end
	return false
end

CartOccupantService.DriverChanged = driverChangedEvent.Event
CartOccupantService.OccupantsChanged = occupantsChangedEvent.Event

-- Physical owner occupancy remains visible while control is suspended or dazed.
-- Registration supplies ownership; cart names and replicated attributes do not.
function CartOccupantService:GetOwnerUserId(cart: Model): number?
	local record = authority:GetStateSnapshot(cart)
	return if record and connectionsByCart[cart] then record.OwnerUserId else nil
end

function CartOccupantService:GetOccupants(cart: Model): { Player }
	local record = authority:GetStateSnapshot(cart)
	if not record or not connectionsByCart[cart] or cart.Parent == nil then
		return {}
	end
	local seat = record.DriverSeat
	if not SeatContract.IsSeat(cart, seat) then
		return {}
	end
	local humanoid = seat.Occupant
	local character = humanoid and humanoid.Parent
	local player = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
	if
		player
		and player.UserId == record.OwnerUserId
		and player.Parent == Players
		and player.Character == character
		and character:IsDescendantOf(Workspace)
		and humanoid.Health > 0
		and humanoid.SeatPart == seat
	then
		return { player }
	end
	return {}
end

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function disconnectDriverConnections(cart: Model)
	local connections = connectionsByCart[cart]

	if connections ~= nil then
		disconnectAll(connections.DriverConnections)
	end
end

local function formatCartContext(record: DriverRecord): string
	return string.format(
		"Cart=%s CartId=%s OwnerUserId=%d",
		record.Cart.Name,
		tostring(record.Cart:GetAttribute("CartId")),
		record.OwnerUserId
	)
end

local function validateCandidate(record: DriverRecord, candidate: DriverCandidate): (boolean, string)
	local cart = record.Cart
	local root = record.Root
	local seat = record.DriverSeat
	local player = candidate.Player
	local character = candidate.Character
	local humanoid = candidate.Humanoid
	local connectionRecord = connectionsByCart[cart]
	local dazeEnd = dazeDeadline(player)
	if
		type(dazeEnd) == "number"
		and dazeEnd > Workspace:GetServerTimeNow()
		and not (
			record.ActivePlayer == player
			and record.ActiveCharacter == character
			and record.ActiveHumanoid == humanoid
		)
	then
		return false, "player is dazed"
	end
	local cartAlive = cart.Parent ~= nil
		and root.Parent ~= nil
		and seat.Parent ~= nil
		and root:IsDescendantOf(cart)
		and seat:IsDescendantOf(cart)
		and cart:GetAttribute("RuntimeCart") == true
	local playerActive = player.Parent == Players
	local characterValid = player.Character == character
		and character.Parent ~= nil
		and character:IsDescendantOf(Workspace)
		and humanoid.Parent == character
		and humanoid.Health > 0
	local occupantMatches = seat.Occupant == humanoid and humanoid.SeatPart == seat
	local canEnter, entryReason = CartOccupantService:CanEnterDriver(player)
	if not canEnter then
		return false, entryReason :: string
	end

	if record.ControlSuspended then
		return false, "cart control is suspended"
	end

	if CartAssemblyValidationService:GetState(cart) == "Preparing" then
		local assemblyValid, _, assemblyReason =
			CartAssemblyValidationService:RevalidateCart(cart, "DriverSeat candidate reconciliation")

		if not assemblyValid then
			return false, assemblyReason or "cart assembly reconciliation failed"
		end
	end

	if not CartAssemblyValidationService:IsCartValid(cart) then
		return false, "cart assembly is not in a valid controllable state"
	end

	return CartDriverPolicy.Evaluate({
		FeatureEnabled = FeatureFlags.CartEnabled,
		CartRegistered = connectionRecord ~= nil and authority:IsRegistered(cart),
		CartAlive = cartAlive,
		ControlSuspended = record.ControlSuspended,
		PlayerActive = playerActive,
		CharacterValid = characterValid,
		OccupantMatchesCharacter = occupantMatches,
		OwnerUserId = record.OwnerUserId,
		PlayerUserId = player.UserId,
	})
end

local function setNetworkOwner(record: DriverRecord, player: Player?): (boolean, string?)
	local root = record.Root
	local deadline = if player then dazeDeadline(player) else nil
	if type(deadline) == "number" and deadline > Workspace:GetServerTimeNow() then
		player = nil
	end

	if root.Parent == nil then
		return false, "cart root is no longer parented"
	end

	if player ~= nil then
		local permitted, rejection = CartOccupantService:CanEnterDriver(player)
		if not permitted then
			return false, rejection
		end
		if not root:IsDescendantOf(record.Cart) or record.Cart.Parent == nil then
			return false, "cart root is no longer active"
		end

		if player.Parent ~= Players then
			return false, "driver is no longer active"
		end

		local canSet, reason = root:CanSetNetworkOwnership()

		if not canSet then
			return false, tostring(reason)
		end
	end

	local success, errorMessage = pcall(function()
		root:SetNetworkOwner(player)
	end)

	if not success then
		return false, tostring(errorMessage)
	end

	return true
end

local function setActiveDriverUserId(record: DriverRecord, userId: number): (boolean, string?)
	local success, errorMessage = pcall(function()
		record.Cart:SetAttribute(ACTIVE_DRIVER_ATTRIBUTE, userId)
	end)

	if not success then
		return false, tostring(errorMessage)
	end

	return true
end

local function revokeIfCurrent(
	cart: Model,
	player: Player,
	character: Model,
	humanoid: Humanoid,
	revision: number,
	reason: string
)
	authority:RevokeControlIfCurrent(cart, {
		Player = player,
		Character = character,
		Humanoid = humanoid,
	}, revision, reason)
end

local function bindDriverConnections(cart: Model)
	local connectionRecord = connectionsByCart[cart]
	local record = authority:GetStateSnapshot(cart)

	if connectionRecord == nil or record == nil then
		return
	end

	disconnectAll(connectionRecord.DriverConnections)

	local player = record.ActivePlayer
	local character = record.ActiveCharacter
	local humanoid = record.ActiveHumanoid
	local revision = record.Revision

	if player == nil or character == nil or humanoid == nil then
		return
	end
	local function synchronizeDaze()
		local current = authority:GetStateSnapshot(cart)
		if not current or current.Revision ~= revision or current.ActivePlayer ~= player then
			return
		end
		if not CartOccupantService:CanEnterDriver(player) then
			CartOccupantService:EnforceDriverEligibility(player)
			return
		end
		local deadline = dazeDeadline(player)
		local dazed = type(deadline) == "number" and deadline > Workspace:GetServerTimeNow()
		cart:SetAttribute("DriverDazed", dazed)
		if dazed then
			CartOccupantService:ClearDriverInput(player, cart)
			local constraints = cart:FindFirstChild("Constraints")
			local actuator = constraints and constraints:FindFirstChild("DriveVelocity")
			if actuator and actuator:IsA("LinearVelocity") then
				actuator.Enabled = false
			end
			-- Retain physical seat and authority while server physics is suspended.
			setNetworkOwner(current, nil)
		else
			setNetworkOwner(current, player)
		end
	end
	if type(player.GetAttributeChangedSignal) == "function" then
		table.insert(
			connectionRecord.DriverConnections,
			player:GetAttributeChangedSignal("Phase10DazeEnd"):Connect(synchronizeDaze)
		)
		for _, attribute in { "PlayerWorldStatus", "PlayerDataStatus" } do
			table.insert(
				connectionRecord.DriverConnections,
				player:GetAttributeChangedSignal(attribute):Connect(function()
					local current = authority:GetStateSnapshot(cart)
					if current and current.Revision == revision and current.ActivePlayer == player then
						CartOccupantService:EnforceDriverEligibility(player)
					end
				end)
			)
		end
	end
	synchronizeDaze()

	table.insert(
		connectionRecord.DriverConnections,
		humanoid.Died:Connect(function()
			revokeIfCurrent(cart, player, character, humanoid, revision, "driver Humanoid died")
		end)
	)
	table.insert(
		connectionRecord.DriverConnections,
		humanoid.Destroying:Connect(function()
			revokeIfCurrent(cart, player, character, humanoid, revision, "driver Humanoid destroyed")
		end)
	)
	table.insert(
		connectionRecord.DriverConnections,
		humanoid.Seated:Connect(function(active, currentSeat)
			if not active or currentSeat ~= record.DriverSeat then
				revokeIfCurrent(cart, player, character, humanoid, revision, "driver Humanoid left DriverSeat")
			end
		end)
	)
	table.insert(
		connectionRecord.DriverConnections,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(Workspace) then
				revokeIfCurrent(cart, player, character, humanoid, revision, "driver character removed from Workspace")
			end
		end)
	)
	table.insert(
		connectionRecord.DriverConnections,
		player.CharacterRemoving:Connect(function(removingCharacter)
			if removingCharacter == character then
				revokeIfCurrent(cart, player, character, humanoid, revision, "driver character removing")
			end
		end)
	)
end

local function onDriverChanged(
	cart: Model,
	previousDriver: Player?,
	nextDriver: Player?,
	reason: string,
	revision: number
)
	disconnectDriverConnections(cart)
	if previousDriver ~= nil then
		CartOccupantService:ClearDriverInput(previousDriver, cart)
	end

	if nextDriver ~= nil then
		bindDriverConnections(cart)
	end

	local record = authority:GetStateSnapshot(cart)

	log:Debug(
		"Driver transition Cart=%s CartId=%s OwnerUserId=%s PreviousUserId=%s NextUserId=%s Revision=%d Reason=%s",
		cart.Name,
		tostring(cart:GetAttribute("CartId")),
		if record ~= nil then tostring(record.OwnerUserId) else "unknown",
		if previousDriver ~= nil then tostring(previousDriver.UserId) else "none",
		if nextDriver ~= nil then tostring(nextDriver.UserId) else "none",
		revision,
		reason
	)

	driverChangedEvent:Fire(cart, previousDriver, nextDriver, reason, revision)
end

authority = CartDriverAuthority.new({
	ValidateCandidate = validateCandidate,
	SetNetworkOwner = setNetworkOwner,
	SetActiveDriverUserId = setActiveDriverUserId,
	OnDriverChanged = onDriverChanged,
	Warn = function(message)
		log:Warn("%s", message)
	end,
})

function CartOccupantService:ClearDriverInput(player: Player, cart: Model): boolean
	local record = authority:GetStateSnapshot(cart)
	if not record or (record.ActivePlayer ~= nil and record.ActivePlayer ~= player) then
		return false
	end
	local occupant = record.DriverSeat.Occupant
	if occupant ~= nil and occupant.Parent ~= player.Character then
		return false -- A stranger cannot zero the owner's seat.
	end
	if record.ActivePlayer ~= player and occupant == nil then
		-- Only a just-revoked driver calls this vacant-seat case internally through
		-- DriverChanged. No client remote exposes this method.
		if cart:GetAttribute(ACTIVE_DRIVER_ATTRIBUTE) ~= 0 then
			return false
		end
	end
	record.DriverSeat.Throttle, record.DriverSeat.ThrottleFloat = 0, 0
	record.DriverSeat.Steer, record.DriverSeat.SteerFloat = 0, 0
	-- The existing DriverChanged subscriber clears that driver's longitudinal
	-- intent/epoch. LocalCartState clears its keyboard/gamepad/physics actuators.
	return true
end

-- Exact identity/revision fences are shared by the native exit pump and race
-- regressions. Readiness recovery alone cannot turn a rejected entry into a grant.
function CartOccupantService.IsCurrentRejectedSeatExit(context: any): boolean
	return context.CurrentRegistration == context.Registration
		and context.CurrentPending == context.Token
		and context.CurrentCart == context.Cart
		and context.CurrentSeat == context.Seat
		and context.OccupancySequence == context.ExpectedOccupancySequence
		and context.DriverRevision == context.ExpectedDriverRevision
		and context.ActiveHumanoid ~= context.Humanoid
		and context.SeatOccupant == context.Humanoid
		and context.HumanoidSeat == context.Seat
		and context.NativeWeld == context.ExpectedNativeWeld
		and context.CartAlive == true
		and context.CharacterCurrent == true
end

local function seatWeldForCharacter(seat: VehicleSeat, character: Model): JointInstance?
	for _, joint in seat:GetChildren() do
		if joint.Name == "SeatWeld" and joint:IsA("JointInstance") then
			local a, b = joint.Part0, joint.Part1
			if
				(a == seat and b and b:IsDescendantOf(character))
				or (b == seat and a and a:IsDescendantOf(character))
			then
				return joint
			end
		end
	end
	return nil
end

local function clearPendingSeatExit(cart: Model, token: SeatExitToken)
	local pending = pendingSeatExits[cart]
	if pending and pending.Token == token then
		if pending.Registration.PendingSeatExit == token then
			pending.Registration.PendingSeatExit = nil
		end
		pendingSeatExits[cart] = nil
	end
end

local function disconnectIdleSeatExitPump()
	if next(pendingSeatExits) == nil and seatExitHeartbeatConnection then
		seatExitHeartbeatConnection:Disconnect()
		seatExitHeartbeatConnection = nil
	end
end

local function stepPendingSeatExits()
	for cart, pending in pendingSeatExits do
		local registration, token = pending.Registration, pending.Token
		local humanoid, character, seat = token.Humanoid, token.Character, token.DriverSeat
		local current = authority:GetStateSnapshot(cart)
		local weld = seatWeldForCharacter(seat, character)
		-- Occupant may fire just before the original native weld is parented.
		-- Capture it once for this unchanged entry, never adopt a replacement.
		if not token.NativeWeldCaptured and weld then
			token.NativeWeld, token.NativeWeldCaptured = weld, true
		end
		local player = token.Player
		local isCurrent = current ~= nil
			and CartOccupantService.IsCurrentRejectedSeatExit({
				Registration = registration,
				CurrentRegistration = connectionsByCart[cart],
				Token = token,
				CurrentPending = registration.PendingSeatExit,
				Cart = cart,
				CurrentCart = current and current.Cart,
				Seat = seat,
				CurrentSeat = current and current.DriverSeat,
				ExpectedOccupancySequence = token.OccupancySequence,
				OccupancySequence = registration.OccupancySequence,
				ExpectedDriverRevision = token.DriverRevision,
				DriverRevision = current and current.Revision,
				Humanoid = humanoid,
				ActiveHumanoid = current and current.ActiveHumanoid,
				SeatOccupant = seat.Occupant,
				HumanoidSeat = humanoid.SeatPart,
				ExpectedNativeWeld = token.NativeWeld,
				NativeWeld = weld,
				CartAlive = cart.Parent ~= nil and seat.Parent == cart,
				CharacterCurrent = humanoid.Parent == character and humanoid.Health > 0 and character:IsDescendantOf(
					Workspace
				) and (not player or player.Parent == Players and player.Character == character),
			})
		if not isCurrent then
			clearPendingSeatExit(cart, token)
		else
			token.Steps += 1
			if token.Steps >= 4 then
				log:Warn("Native rejected-seat exit did not settle Cart=%s", cart.Name)
				clearPendingSeatExit(cart, token)
			elseif token.Steps >= 2 and token.NativeWeld and not token.ExitRequested then
				-- Two Heartbeats guarantee a complete native simulation step. Only
				-- the physical exit waits; authority/input were already revoked.
				humanoid.Sit = false
				token.ExitRequested = true
			end
		end
	end
	disconnectIdleSeatExitPump()
end

-- A contact can publish Occupant/SeatPart while Humanoid is still Landed.
-- Breaking SeatWeld in that partial transition can strand read-only SeatPart.
-- Use one bounded shared pump and one entry per cart to request native exit;
-- never destroy its joint, move the character or assign a humanoid state.
local function unseatRejectedOccupant(record: DriverRecord, humanoid: Humanoid)
	local cart, seat = record.Cart, record.DriverSeat
	local registration = connectionsByCart[cart]
	local current = authority:GetStateSnapshot(cart)
	local character = humanoid.Parent
	if not registration or not current or seat.Occupant ~= humanoid or not character or not character:IsA("Model") then
		return
	end
	local prior = registration.PendingSeatExit
	if
		prior
		and prior.Humanoid == humanoid
		and prior.OccupancySequence == registration.OccupancySequence
		and prior.DriverRevision == current.Revision
		and prior.DriverSeat == seat
	then
		return
	end
	local originalWeld = seatWeldForCharacter(seat, character)
	local token: SeatExitToken = {
		Humanoid = humanoid,
		Character = character,
		Player = Players:GetPlayerFromCharacter(character),
		DriverSeat = seat,
		OccupancySequence = registration.OccupancySequence,
		DriverRevision = current.Revision,
		NativeWeld = originalWeld,
		NativeWeldCaptured = originalWeld ~= nil,
		Steps = 0,
		ExitRequested = false,
	}
	registration.PendingSeatExit = token
	pendingSeatExits[cart] = { Registration = registration, Token = token }
	if not seatExitHeartbeatConnection then
		seatExitHeartbeatConnection = RunService.Heartbeat:Connect(stepPendingSeatExits)
	end
end

local function restoreAfterRejectedOccupancy(cart: Model)
	local current = authority:GetStateSnapshot(cart)
	if current and current.ActivePlayer == nil then
		current.DriverSeat.Throttle, current.DriverSeat.ThrottleFloat = 0, 0
		current.DriverSeat.Steer, current.DriverSeat.SteerFloat = 0, 0
		local ok, reason = setNetworkOwner(current, nil)
		if not ok then
			log:Warn("Could not restore server ownership after driver rejection: %s", tostring(reason))
		end
	end
end

local function rejectIneligibleDriver(player: Player, cart: Model, rejectionReason: string?): boolean
	local eligible, currentReason = CartOccupantService:CanEnterDriver(player)
	if eligible then
		return false
	end
	local record = authority:GetStateSnapshot(cart)
	if not record then
		return false
	end
	local occupant = record.DriverSeat.Occupant
	local seatedHere = occupant ~= nil and occupant.Parent == player.Character
	if record.ActivePlayer ~= player and not seatedHere then
		return false -- Another player's carry state does not affect the owner.
	end
	CartOccupantService:ClearDriverInput(player, cart)
	if record.ActivePlayer == player and record.ActiveCharacter and record.ActiveHumanoid then
		authority:RevokeControlIfCurrent(cart, {
			Player = player,
			Character = record.ActiveCharacter,
			Humanoid = record.ActiveHumanoid,
		}, record.Revision, rejectionReason or currentReason or "driver is ineligible")
	end
	if seatedHere and occupant then
		unseatRejectedOccupant(record, occupant)
	end
	restoreAfterRejectedOccupancy(cart)
	return true
end

function CartOccupantService:EnforceDriverEligibility(player: Player)
	local eligible, reason = self:CanEnterDriver(player)
	if eligible then
		return
	end
	local driven = authority:GetCartDrivenBy(player)
	if driven then
		rejectIneligibleDriver(player, driven, reason)
	end
	-- Catch a contact-seat entry before its Occupant callback grants a role.
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid then humanoid.SeatPart else nil
	if seat then
		for cart in connectionsByCart do
			if cart:FindFirstChild("DriverSeat") == seat then
				rejectIneligibleDriver(player, cart, reason)
				break
			end
		end
	end
end

-- Retained carrying notification interface; the same narrow cleanup now also
-- handles an owner whose existing profile/world eligibility has expired.
function CartOccupantService:EnforceCarryRestriction(player: Player)
	self:EnforceDriverEligibility(player)
end

local function resolveCandidate(record: DriverRecord): (DriverCandidate?, string?)
	local occupant = record.DriverSeat.Occupant

	if occupant == nil then
		return nil, "driver seat vacant"
	end

	local character = CartDriverPolicy.ResolveCharacter(occupant)

	if character == nil then
		return nil, "occupant has no valid character"
	end

	local player = Players:GetPlayerFromCharacter(character)

	if player == nil then
		return nil, "occupant is not a Player character"
	end

	return {
		Player = player,
		Character = character,
		Humanoid = occupant,
	}
end

local function refreshOccupancy(cart: Model, reason: string, forceNetworkOwnership: boolean?): boolean
	local record = authority:GetStateSnapshot(cart)

	if record == nil then
		log:Warn(
			"Cannot refresh unknown cart Cart=%s CartId=%s Reason=%s",
			cart.Name,
			tostring(cart:GetAttribute("CartId")),
			reason
		)
		return false
	end

	local candidate, resolutionReason = resolveCandidate(record)

	if candidate == nil then
		local refreshed = authority:Refresh(cart, nil, resolutionReason or reason, forceNetworkOwnership)

		if not refreshed then
			return false
		end

		local rejected = record.DriverSeat.Occupant
		if rejected then
			unseatRejectedOccupant(record, rejected)
			restoreAfterRejectedOccupancy(cart)
			log:Warn(
				"Rejected driver occupant %s AttemptedUserId=unknown Reason=%s",
				formatCartContext(record),
				resolutionReason or "occupant resolution failed"
			)
		end

		return record.DriverSeat.Occupant == nil
	end
	local eligible, entryReason = CartOccupantService:CanEnterDriver(candidate.Player)
	if not eligible then
		rejectIneligibleDriver(candidate.Player, cart, entryReason)
		return false
	end

	local success, rejectionReason = authority:Refresh(cart, candidate, reason, forceNetworkOwnership)

	if not success then
		local suspendedOwner = rejectionReason == "cart control is suspended"
			and candidate.Player.UserId == record.OwnerUserId
			and candidate.Player.Parent == Players
			and candidate.Player.Character == candidate.Character
			and candidate.Humanoid.Parent == candidate.Character
			and candidate.Humanoid.Health > 0
			and candidate.Humanoid.SeatPart == record.DriverSeat
		if not suspendedOwner then
			unseatRejectedOccupant(record, candidate.Humanoid)
			restoreAfterRejectedOccupancy(cart)
		end

		log:Warn(
			"Rejected driver %s AttemptedUserId=%d Reason=%s",
			formatCartContext(record),
			candidate.Player.UserId,
			rejectionReason or "unknown rejection"
		)
	end

	return success
end

function CartOccupantService:RegisterCart(cartModel: Model, ownerUserId: number): (boolean, string?)
	if authority:IsRegistered(cartModel) then
		log:Warn(
			"Duplicate cart registration rejected Cart=%s CartId=%s",
			cartModel.Name,
			tostring(cartModel:GetAttribute("CartId"))
		)
		return false, "cart is already registered"
	end

	if cartModel.Parent == nil or cartModel:GetAttribute("RuntimeCart") ~= true then
		return false, "cart must be a live registered runtime model"
	end

	if not CartAssemblyValidationService:IsCartValid(cartModel) then
		return false, "cart assembly must pass fatal validation before occupancy registration"
	end

	local resolvedContract, rootOrError, resolvedSeat = pcall(function()
		return CartModelUtility.GetRoot(cartModel), CartModelUtility.GetDriverSeat(cartModel)
	end)

	if not resolvedContract then
		return false,
			string.format(
				"Cart=%s CartId=%s driver occupancy registration failed: %s",
				cartModel.Name,
				tostring(cartModel:GetAttribute("CartId")),
				tostring(rootOrError)
			)
	end

	local root = rootOrError :: BasePart
	local seat = resolvedSeat :: VehicleSeat
	local connectionRecord: ConnectionRecord = {
		CartConnections = {},
		DriverConnections = {},
		OccupancySequence = 0,
		PendingSeatExit = nil,
	}

	connectionsByCart[cartModel] = connectionRecord

	local registered, registrationWarning = authority:Register({
		Cart = cartModel,
		Root = root,
		DriverSeat = seat,
		OwnerUserId = ownerUserId,
	})

	if not registered then
		connectionsByCart[cartModel] = nil
		return false, registrationWarning
	end

	-- Contextual Drive submits to the existing occupancy authority. Touch
	-- boarding and all ownership/network/input arbitration remain unchanged.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ContextDrive"
	prompt.ActionText = "Drive"
	prompt.ObjectText = "Cart"
	prompt.MaxActivationDistance = require(ReplicatedStorage.Shared.Config.ChariotTeam).ManageDistance
	prompt.RequiresLineOfSight = true
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = seat
	prompt:SetAttribute("CartGeneration", cartModel:GetAttribute("CartGeneration"))
	game:GetService("CollectionService"):AddTag(prompt, "ContextDrivePrompt")
	table.insert(
		connectionRecord.CartConnections,
		prompt.Triggered:Connect(function(player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local body = character and character:FindFirstChild("HumanoidRootPart")
			if
				connectionsByCart[cartModel] ~= connectionRecord
				or not authority:IsRegistered(cartModel)
				or player.UserId ~= ownerUserId
				or not self:CanEnterDriver(player)
				or not humanoid
				or humanoid.Health <= 0
				or not body
				or seat.Occupant
				or humanoid.SeatPart
				or (body.Position - seat.Position).Magnitude > prompt.MaxActivationDistance
			then
				return
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character, cartModel }
			params.RespectCanCollide = true
			if workspace:Raycast(body.Position, seat.Position - body.Position, params) then
				return
			end
			seat:Sit(humanoid)
		end)
	)
	local function scheduleOccupancy(reason: string)
		-- Roblox fires Occupant while it is still parenting SeatWeld and updating
		-- Humanoid.SeatPart. Reconcile after that native transaction completes;
		-- input checks continue requiring exact current occupancy in the meantime.
		connectionRecord.OccupancySequence += 1
		local expectedSequence = connectionRecord.OccupancySequence
		local expectedOccupant = seat.Occupant
		task.defer(function()
			if
				connectionsByCart[cartModel] ~= connectionRecord
				or connectionRecord.OccupancySequence ~= expectedSequence
				or not authority:IsRegistered(cartModel)
				or cartModel.Parent == nil
				or seat.Parent ~= cartModel
				or seat.Occupant ~= expectedOccupant
			then
				return
			end
			refreshOccupancy(cartModel, reason)
			occupantsChangedEvent:Fire(cartModel)
		end)
	end

	table.insert(
		connectionRecord.CartConnections,
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			scheduleOccupancy("DriverSeat occupant changed")
		end)
	)
	table.insert(
		connectionRecord.CartConnections,
		seat.AncestryChanged:Connect(function()
			if not seat:IsDescendantOf(cartModel) then
				log:Warn(
					"Driver occupancy contract invalidated Cart=%s CartId=%s Component=DriverSeat",
					cartModel.Name,
					tostring(cartModel:GetAttribute("CartId"))
				)
				self:UnregisterCart(cartModel, "DriverSeat removed from cart")
			end
		end)
	)
	table.insert(
		connectionRecord.CartConnections,
		root.AncestryChanged:Connect(function()
			if not root:IsDescendantOf(cartModel) then
				log:Warn(
					"Driver occupancy contract invalidated Cart=%s CartId=%s Component=Root",
					cartModel.Name,
					tostring(cartModel:GetAttribute("CartId"))
				)
				self:UnregisterCart(cartModel, "Root removed from cart")
			end
		end)
	)
	table.insert(
		connectionRecord.CartConnections,
		cartModel.AncestryChanged:Connect(function()
			if cartModel.Parent == nil then
				log:Warn(
					"Driver occupancy cleaned up after hierarchy removal Cart=%s CartId=%s",
					cartModel.Name,
					tostring(cartModel:GetAttribute("CartId"))
				)
				self:UnregisterCart(cartModel, "cart removed from hierarchy")
			end
		end)
	)
	table.insert(
		connectionRecord.CartConnections,
		cartModel.Destroying:Connect(function()
			self:UnregisterCart(cartModel, "cart destroying", true)
		end)
	)

	log:Debug(
		"Registered driver occupancy %s RootAnchored=%s AssemblyMass=%.2f",
		formatCartContext(authority:GetStateSnapshot(cartModel) :: DriverRecord),
		tostring(root.Anchored),
		root.AssemblyMass
	)

	scheduleOccupancy("cart registered")

	return true, registrationWarning
end

function CartOccupantService:UnregisterCart(cartModel: Model, reason: string?, skipNetworkOwnership: boolean?): boolean
	local connectionRecord = connectionsByCart[cartModel]

	if connectionRecord == nil then
		log:Warn(
			"Cannot unregister unknown cart Cart=%s CartId=%s Reason=%s",
			cartModel.Name,
			tostring(cartModel:GetAttribute("CartId")),
			reason or "cart unregistered"
		)
		return false
	end

	local pending = pendingSeatExits[cartModel]
	if pending then
		clearPendingSeatExit(cartModel, pending.Token)
	end
	disconnectIdleSeatExitPump()
	disconnectAll(connectionRecord.DriverConnections)
	disconnectAll(connectionRecord.CartConnections)
	connectionsByCart[cartModel] = nil
	occupantsChangedEvent:Fire(cartModel)

	return authority:Unregister(cartModel, reason or "cart unregistered", skipNetworkOwnership)
end

-- Drive-and-Hunt: the server seats the owner in their own DriverSeat after it has
-- placed the cart beside them (gate launch, CART, LOAD & GO). Same eligibility as
-- the ContextDrive prompt; reach and line of sight are replaced by the caller's
-- server-side placement. Occupancy, authority and network ownership then follow
-- the ordinary Occupant-changed path.
function CartOccupantService:SeatOwner(player: Player, cartModel: Model): (boolean, string?)
	local seat = cartModel:FindFirstChild("DriverSeat")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not seat or not seat:IsA("VehicleSeat") or connectionsByCart[cartModel] == nil then
		return false, "cart is not registered"
	end
	if not authority:IsRegistered(cartModel) or self:GetOwnerUserId(cartModel) ~= player.UserId then
		return false, "not the owner's cart"
	end
	local eligible, reason = self:CanEnterDriver(player)
	if not eligible then
		return false, reason
	end
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return false, "character cannot sit"
	end
	if seat.Occupant ~= nil or seat:FindFirstChild("SeatWeld") ~= nil then
		return false, "seat is occupied"
	end
	seat:Sit(humanoid)
	return true, nil
end

-- Drive-and-Hunt HOP OUT: stand the owner up from their own DriverSeat. The
-- existing Occupant-changed path revokes control and network ownership.
function CartOccupantService:UnseatOwner(player: Player, cartModel: Model): (boolean, string?)
	local seat = cartModel:FindFirstChild("DriverSeat")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not seat or not seat:IsA("VehicleSeat") or self:GetOwnerUserId(cartModel) ~= player.UserId then
		return false, "not the owner's cart"
	end
	if not humanoid or seat.Occupant ~= humanoid then
		return false, "not seated"
	end
	humanoid.Sit = false
	return true, nil
end

function CartOccupantService:GetDriver(cartModel: Model): Player?
	return authority:GetDriver(cartModel)
end

-- The revision advances on every accepted authority transition, including a
-- revoke/restore that returns to the same player before deferred observers run.
function CartOccupantService:GetDriverRevision(cartModel: Model): number?
	local record = authority:GetStateSnapshot(cartModel)
	return if record then record.Revision else nil
end

function CartOccupantService:IsDriver(player: Player, cartModel: Model): boolean
	return authority:IsDriver(player, cartModel)
end

function CartOccupantService:CanPlayerControlCart(player: Player, cartModel: Model): boolean
	local eligible, reason = self:CanEnterDriver(player)
	if not eligible then
		rejectIneligibleDriver(player, cartModel, reason)
		return false
	end
	local deadline = dazeDeadline(player)
	if type(deadline) == "number" and deadline > Workspace:GetServerTimeNow() then
		return false
	end
	return CartAssemblyValidationService:IsCartValid(cartModel) and authority:CanPlayerControlCart(player, cartModel)
end

function CartOccupantService:RevokeControl(cartModel: Model, reason: string?): boolean
	return authority:RevokeControl(cartModel, reason or "control revoked")
end

function CartOccupantService:SuspendControl(cartModel: Model, reason: string?): boolean
	return authority:SuspendControl(cartModel, reason or "control suspended")
end

function CartOccupantService:ResumeControl(cartModel: Model, reason: string?): boolean
	if not CartAssemblyValidationService:IsCartValid(cartModel) then
		return false
	end

	if not authority:ResumeControl(cartModel) then
		return false
	end

	return refreshOccupancy(cartModel, reason or "control resumed")
end

function CartOccupantService:RefreshOccupancy(cartModel: Model, reason: string?): boolean
	return refreshOccupancy(cartModel, reason or "occupancy refresh requested")
end

function CartOccupantService:RestoreNetworkOwnership(cartModel: Model, reason: string?): boolean
	return refreshOccupancy(cartModel, reason or "network ownership refresh requested", true)
end

function CartOccupantService:IsCartRegistered(cartModel: Model): boolean
	return connectionsByCart[cartModel] ~= nil
end

function CartOccupantService:GetDiagnostics()
	local recordCount = 0
	local cartConnectionCount = 0
	local driverConnectionCount = 0
	local pendingSeatExitCount = 0

	for _, connectionRecord in connectionsByCart do
		recordCount += 1
		cartConnectionCount += #connectionRecord.CartConnections
		driverConnectionCount += #connectionRecord.DriverConnections
		pendingSeatExitCount += if connectionRecord.PendingSeatExit then 1 else 0
	end

	return table.freeze({
		Started = started,
		RecordCount = recordCount,
		CartConnectionCount = cartConnectionCount,
		DriverConnectionCount = driverConnectionCount,
		PendingSeatExitCount = pendingSeatExitCount,
		SeatExitHeartbeatConnectionCount = if seatExitHeartbeatConnection then 1 else 0,
		SharedConnectionCount = (if playerRemovingConnection ~= nil then 1 else 0)
			+ (if carryChangedConnection ~= nil then 1 else 0)
			+ (if seatExitHeartbeatConnection ~= nil then 1 else 0),
	})
end

function CartOccupantService:Start()
	if started then
		return
	end

	started = true
	self:SetCarryingPredicate(isCarrying, carryChangedSignal)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		for cart in connectionsByCart do
			if self:GetOwnerUserId(cart) == player.UserId then
				occupantsChangedEvent:Fire(cart)
			end
		end
		local drivenCart = authority:GetCartDrivenBy(player)

		if drivenCart ~= nil then
			authority:RevokeControl(drivenCart, "driver Player removing")
		end
	end)

	log:Info("Cart occupant service ready")
end

function CartOccupantService:Stop()
	if carryChangedConnection then
		carryChangedConnection:Disconnect()
		carryChangedConnection = nil
	end
	if not started then
		return
	end

	started = false

	if playerRemovingConnection ~= nil then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	local registeredCarts: { Model } = {}

	for cart in connectionsByCart do
		table.insert(registeredCarts, cart)
	end

	for _, cart in registeredCarts do
		self:UnregisterCart(cart, "occupant service stopping")
	end

	log:Info("Cart occupant service stopped")
end

return CartOccupantService
