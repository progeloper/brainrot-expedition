--!strict

export type DriverCandidate = {
	Player: Player,
	Character: Model,
	Humanoid: Humanoid,
}

export type DriverRegistration = {
	Cart: Model,
	Root: BasePart,
	DriverSeat: VehicleSeat,
	OwnerUserId: number,
}

export type DriverRecord = {
	Cart: Model,
	Root: BasePart,
	DriverSeat: VehicleSeat,
	OwnerUserId: number,
	ActivePlayer: Player?,
	ActiveCharacter: Model?,
	ActiveHumanoid: Humanoid?,
	ControlEnabled: boolean,
	ControlSuspended: boolean,
	Revision: number,
}

export type Adapter = {
	ValidateCandidate: (record: DriverRecord, candidate: DriverCandidate) -> (boolean, string),
	SetNetworkOwner: (record: DriverRecord, player: Player?) -> (boolean, string?),
	SetActiveDriverUserId: (record: DriverRecord, userId: number) -> (boolean, string?),
	OnDriverChanged: (
		cart: Model,
		previousDriver: Player?,
		nextDriver: Player?,
		reason: string,
		revision: number
	) -> (),
	Warn: (message: string) -> (),
}

export type Authority = {
	Register: (self: Authority, registration: DriverRegistration) -> (boolean, string?),
	Unregister: (
		self: Authority,
		cart: Model,
		reason: string,
		skipNetworkOwnership: boolean?
	) -> boolean,
	Refresh: (
		self: Authority,
		cart: Model,
		candidate: DriverCandidate?,
		reason: string,
		forceNetworkOwnership: boolean?
	) -> (boolean, string?),
	RevokeControl: (self: Authority, cart: Model, reason: string) -> boolean,
	RevokeControlIfCurrent: (
		self: Authority,
		cart: Model,
		candidate: DriverCandidate,
		revision: number,
		reason: string
	) -> boolean,
	SuspendControl: (self: Authority, cart: Model, reason: string) -> boolean,
	ResumeControl: (self: Authority, cart: Model) -> boolean,
	GetDriver: (self: Authority, cart: Model) -> Player?,
	GetCartDrivenBy: (self: Authority, player: Player) -> Model?,
	IsDriver: (self: Authority, player: Player, cart: Model) -> boolean,
	CanPlayerControlCart: (self: Authority, player: Player, cart: Model) -> boolean,
	IsRegistered: (self: Authority, cart: Model) -> boolean,
	GetStateSnapshot: (self: Authority, cart: Model) -> DriverRecord?,
}

local CartDriverAuthority = {}
CartDriverAuthority.__index = CartDriverAuthority

type AuthorityPrivate = Authority & {
	_adapter: Adapter,
	_recordsByCart: { [Model]: DriverRecord },
	_cartByDriver: { [Player]: Model },
}

local function warnAdapter(self: AuthorityPrivate, message: string)
	self._adapter.Warn(message)
end

local function setActiveDriverUserId(
	self: AuthorityPrivate,
	record: DriverRecord,
	userId: number
): boolean
	local success, errorMessage = self._adapter.SetActiveDriverUserId(record, userId)

	if not success then
		warnAdapter(
			self,
			string.format(
				"Failed to replicate ActiveDriverUserId=%d for %s: %s",
				userId,
				record.Cart.Name,
				errorMessage or "unknown error"
			)
		)
	end

	return success
end

local function restoreServerOwnership(
	self: AuthorityPrivate,
	record: DriverRecord,
	reason: string
): boolean
	local success, errorMessage = self._adapter.SetNetworkOwner(record, nil)

	if not success then
		warnAdapter(
			self,
			string.format(
				"Failed to return %s to server ownership. Reason=%s Error=%s",
				record.Cart.Name,
				reason,
				errorMessage or "unknown error"
			)
		)
	end

	return success
end

local function clearActiveDriver(
	self: AuthorityPrivate,
	record: DriverRecord,
	reason: string,
	restoreOwnership: boolean
): boolean
	local previousDriver = record.ActivePlayer

	if previousDriver == nil then
		record.ActiveCharacter = nil
		record.ActiveHumanoid = nil
		record.ControlEnabled = false
		return false
	end

	record.ActivePlayer = nil
	record.ActiveCharacter = nil
	record.ActiveHumanoid = nil
	record.ControlEnabled = false
	record.Revision += 1

	local reverseCart = self._cartByDriver[previousDriver]

	if reverseCart == record.Cart then
		self._cartByDriver[previousDriver] = nil
	elseif reverseCart ~= nil then
		warnAdapter(
			self,
			string.format(
				"Active-driver reverse lookup mismatch for UserId=%d Cart=%s",
				previousDriver.UserId,
				record.Cart.Name
			)
		)
	end

	setActiveDriverUserId(self, record, 0)

	if restoreOwnership then
		restoreServerOwnership(self, record, reason)
	end

	self._adapter.OnDriverChanged(record.Cart, previousDriver, nil, reason, record.Revision)

	return true
end

function CartDriverAuthority.new(adapter: Adapter): Authority
	local self: AuthorityPrivate = setmetatable({
		_adapter = adapter,
		_recordsByCart = {},
		_cartByDriver = {},
	}, CartDriverAuthority) :: any

	return self
end

function CartDriverAuthority.Register(
	self: AuthorityPrivate,
	registration: DriverRegistration
): (boolean, string?)
	local cart = registration.Cart

	if self._recordsByCart[cart] ~= nil then
		return false, "cart is already registered"
	end

	local record: DriverRecord = {
		Cart = cart,
		Root = registration.Root,
		DriverSeat = registration.DriverSeat,
		OwnerUserId = registration.OwnerUserId,
		ActivePlayer = nil,
		ActiveCharacter = nil,
		ActiveHumanoid = nil,
		ControlEnabled = false,
		ControlSuspended = false,
		Revision = 0,
	}

	self._recordsByCart[cart] = record

	if not setActiveDriverUserId(self, record, 0) then
		self._recordsByCart[cart] = nil
		return false, "failed to initialise replicated driver state"
	end

	local ownershipSuccess = restoreServerOwnership(self, record, "cart registration")

	if not ownershipSuccess then
		self._recordsByCart[cart] = nil
		return false, "failed to confirm server ownership"
	end

	return true
end

function CartDriverAuthority.Unregister(
	self: AuthorityPrivate,
	cart: Model,
	reason: string,
	skipNetworkOwnership: boolean?
): boolean
	local record = self._recordsByCart[cart]

	if record == nil then
		return false
	end

	record.ControlSuspended = true
	local hadDriver = clearActiveDriver(self, record, reason, skipNetworkOwnership ~= true)

	if not hadDriver and skipNetworkOwnership ~= true then
		setActiveDriverUserId(self, record, 0)
		restoreServerOwnership(self, record, reason)
	end

	self._recordsByCart[cart] = nil

	return true
end

function CartDriverAuthority.Refresh(
	self: AuthorityPrivate,
	cart: Model,
	candidate: DriverCandidate?,
	reason: string,
	forceNetworkOwnership: boolean?
): (boolean, string?)
	local record = self._recordsByCart[cart]

	if record == nil then
		return false, "cart is not registered"
	end

	if candidate == nil then
		if forceNetworkOwnership then
			clearActiveDriver(self, record, reason, false)

			if not restoreServerOwnership(self, record, reason) then
				return false, "server ownership refresh failed"
			end

			return true
		end

		clearActiveDriver(self, record, reason, true)
		return true
	end

	if
		record.ActivePlayer == candidate.Player
		and record.ActiveCharacter == candidate.Character
		and record.ActiveHumanoid == candidate.Humanoid
		and record.ControlEnabled
	then
		local remainsValid, rejectionReason = self._adapter.ValidateCandidate(record, candidate)

		if remainsValid then
			if forceNetworkOwnership then
				local ownershipSuccess, ownershipError =
					self._adapter.SetNetworkOwner(record, candidate.Player)

				if not ownershipSuccess then
					clearActiveDriver(self, record, "network ownership refresh failed", true)
					return false, ownershipError or "network ownership refresh failed"
				end
			end

			return true
		end

		clearActiveDriver(self, record, rejectionReason, true)
		return false, rejectionReason
	end

	local permitted, rejectionReason = self._adapter.ValidateCandidate(record, candidate)

	if not permitted then
		return false, rejectionReason
	end
	-- An invalid driver claim must not evict a different
	-- accepted driver. Only a validated replacement can retire that authority.
	if record.ActivePlayer ~= nil then
		clearActiveDriver(self, record, "driver replaced", true)
	end

	local previousCart = self._cartByDriver[candidate.Player]

	if previousCart ~= nil and previousCart ~= cart then
		local previousRecord = self._recordsByCart[previousCart]

		if previousRecord ~= nil then
			clearActiveDriver(self, previousRecord, "driver assigned to another cart", true)
		else
			self._cartByDriver[candidate.Player] = nil
		end
	end

	permitted, rejectionReason = self._adapter.ValidateCandidate(record, candidate)

	if not permitted then
		return false, rejectionReason
	end

	local ownershipSuccess, ownershipError = self._adapter.SetNetworkOwner(record, candidate.Player)

	if not ownershipSuccess then
		restoreServerOwnership(self, record, "driver ownership assignment failed")
		return false, ownershipError or "network ownership assignment failed"
	end

	permitted, rejectionReason = self._adapter.ValidateCandidate(record, candidate)

	if not permitted then
		restoreServerOwnership(self, record, "driver became invalid during assignment")
		return false, rejectionReason
	end

	record.ActivePlayer = candidate.Player
	record.ActiveCharacter = candidate.Character
	record.ActiveHumanoid = candidate.Humanoid
	record.ControlEnabled = true
	record.Revision += 1
	self._cartByDriver[candidate.Player] = cart

	if not setActiveDriverUserId(self, record, candidate.Player.UserId) then
		record.ActivePlayer = nil
		record.ActiveCharacter = nil
		record.ActiveHumanoid = nil
		record.ControlEnabled = false
		self._cartByDriver[candidate.Player] = nil
		restoreServerOwnership(self, record, "driver state replication failed")
		return false, "failed to replicate active driver"
	end

	self._adapter.OnDriverChanged(cart, nil, candidate.Player, reason, record.Revision)

	return true
end

function CartDriverAuthority.RevokeControl(
	self: AuthorityPrivate,
	cart: Model,
	reason: string
): boolean
	local record = self._recordsByCart[cart]

	if record == nil then
		return false
	end

	return clearActiveDriver(self, record, reason, true)
end

function CartDriverAuthority.RevokeControlIfCurrent(
	self: AuthorityPrivate,
	cart: Model,
	candidate: DriverCandidate,
	revision: number,
	reason: string
): boolean
	local record = self._recordsByCart[cart]

	if
		record == nil
		or record.Revision ~= revision
		or record.ActivePlayer ~= candidate.Player
		or record.ActiveCharacter ~= candidate.Character
		or record.ActiveHumanoid ~= candidate.Humanoid
	then
		return false
	end

	return clearActiveDriver(self, record, reason, true)
end

function CartDriverAuthority.SuspendControl(
	self: AuthorityPrivate,
	cart: Model,
	reason: string
): boolean
	local record = self._recordsByCart[cart]

	if record == nil then
		return false
	end

	record.ControlSuspended = true

	if not clearActiveDriver(self, record, reason, true) then
		setActiveDriverUserId(self, record, 0)
		restoreServerOwnership(self, record, reason)
	end

	return true
end

function CartDriverAuthority.ResumeControl(self: AuthorityPrivate, cart: Model): boolean
	local record = self._recordsByCart[cart]

	if record == nil then
		return false
	end

	record.ControlSuspended = false
	return true
end

function CartDriverAuthority.GetDriver(self: AuthorityPrivate, cart: Model): Player?
	local record = self._recordsByCart[cart]

	return if record ~= nil then record.ActivePlayer else nil
end

function CartDriverAuthority.GetCartDrivenBy(self: AuthorityPrivate, player: Player): Model?
	return self._cartByDriver[player]
end

function CartDriverAuthority.IsDriver(self: AuthorityPrivate, player: Player, cart: Model): boolean
	return self:GetDriver(cart) == player
end

function CartDriverAuthority.CanPlayerControlCart(
	self: AuthorityPrivate,
	player: Player,
	cart: Model
): boolean
	local record = self._recordsByCart[cart]

	if
		record == nil
		or record.ActivePlayer ~= player
		or record.ActiveCharacter == nil
		or record.ActiveHumanoid == nil
		or not record.ControlEnabled
		or record.ControlSuspended
		or self._cartByDriver[player] ~= cart
	then
		return false
	end

	local candidate: DriverCandidate = {
		Player = player,
		Character = record.ActiveCharacter,
		Humanoid = record.ActiveHumanoid,
	}
	local valid, reason = self._adapter.ValidateCandidate(record, candidate)
	if not valid then
		-- Rejecting an input alone is insufficient for client-owned physics: retire
		-- this driver's role and return ownership through the usual revocation path.
		clearActiveDriver(self, record, reason, true)
	end

	return valid
end

function CartDriverAuthority.IsRegistered(self: AuthorityPrivate, cart: Model): boolean
	return self._recordsByCart[cart] ~= nil
end

function CartDriverAuthority.GetStateSnapshot(self: AuthorityPrivate, cart: Model): DriverRecord?
	local record = self._recordsByCart[cart]

	if record == nil then
		return nil
	end

	return table.freeze({
		Cart = record.Cart,
		Root = record.Root,
		DriverSeat = record.DriverSeat,
		OwnerUserId = record.OwnerUserId,
		ActivePlayer = record.ActivePlayer,
		ActiveCharacter = record.ActiveCharacter,
		ActiveHumanoid = record.ActiveHumanoid,
		ControlEnabled = record.ControlEnabled,
		ControlSuspended = record.ControlSuspended,
		Revision = record.Revision,
	})
end

return CartDriverAuthority
