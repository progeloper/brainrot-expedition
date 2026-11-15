--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)

local Ids = require(ReplicatedStorage.Shared.Constants.Ids)

local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local CartMovementTypes = require(ReplicatedStorage.Shared.Types.CartMovementTypes)
local CartMovementProfileResolver = require(ReplicatedStorage.Shared.Utility.CartMovementProfileResolver)
local CartPerformanceResolver = require(ReplicatedStorage.Shared.Utility.CartPerformanceResolver)
local CartTeamPerformance = require(ReplicatedStorage.Shared.Utility.CartTeamPerformance)

local CollisionGroups = require(ReplicatedStorage.Shared.Config.CollisionGroups)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local RuntimeFolders = require(script.Parent.Parent.Utility.RuntimeFolders)

local CartModelUtility = require(script.Parent.Parent.Utility.CartModelUtility)
local CartResetExecutor = require(script.Parent.Parent.Utility.CartResetExecutor)
local CartLocalPlacement = require(script.Parent.Parent.Utility.CartLocalPlacement)
local CartGeometry = require(ReplicatedStorage.Shared.Utility.CartGeometry)
local CartGeometrySwap = require(script.Parent.Parent.Utility.CartGeometrySwap)

local CartAssetService = require(script.Parent.CartAssetService)

local CartSpawnRegistry = require(script.Parent.CartSpawnRegistry)
local CartSpawnValidator = require(ReplicatedStorage.Shared.Validation.CartSpawnValidator)
local PlayerBaseSystem = require(script.Parent.Parent.Systems.PlayerBaseSystem)

type CartSpawnRecord = CartSpawnRegistry.CartSpawnRecord

local CollisionService = require(script.Parent.CollisionService)

local CartOccupantService = require(script.Parent.CartOccupantService)
local CartAssemblyValidationService = require(script.Parent.CartAssemblyValidationService)
local CartTerrainService = require(script.Parent.CartTerrainService)
local CartStabilityService = require(script.Parent.CartStabilityService)
local CartArcadeService = require(script.Parent.CartArcadeService)
local CartArcadeRig = require(ReplicatedStorage.Shared.Utility.CartArcadeRig)

local Workspace = game:GetService("Workspace")

local log = Logger.new("CartService")
type EffectiveMovementProfile = CartMovementTypes.EffectiveMovementProfile

export type SpawnedCartRecord = {
	OwnerUserId: number,
	CartId: string,
	SpawnId: string,
	Model: Model,
	SpawnCFrame: CFrame,
	CreatedAt: number,
	MovementProfile: EffectiveMovementProfile,
	PerformanceResult: any,
	PerformanceRevision: number,
	PerformanceSignature: string,
	Generation: number,
}

export type CartService = {
	CartSpawned: RBXScriptSignal,
	CartDespawned: RBXScriptSignal,
	PerformanceChanged: RBXScriptSignal,

	GetCart: (self: CartService, player: Player) -> Model?,
	GetCartRecords: (self: CartService) -> { SpawnedCartRecord },
	GetCartRecord: (self: CartService, player: Player) -> SpawnedCartRecord?,
	GetCartRecordByOwnerUserId: (self: CartService, ownerUserId: number) -> SpawnedCartRecord?,
	ConfigurePerformance: (self: CartService, options: any?) -> (),
	ResolveEffectivePerformance: (
		self: CartService,
		ownerUserId: number,
		cartId: string,
		runtimeCart: Model?
	) -> any,
	ReconcileCartPerformance: (self: CartService, cart: Model, reason: string?) -> any,
	ReconcileOwnerPerformance: (self: CartService, ownerUserId: number, reason: string?) -> any?,

	DespawnCart: (self: CartService, player: Player, reason: string?, expectedHandle: any?) -> boolean?,
	SetCargoRemovalHandler: (self: CartService, handler: (Model) -> boolean?) -> (),

	SpawnCart: (self: CartService, player: Player, cartId: string?, spawnId: string?) -> Model,

	ResetCart: (
		self: CartService,
		player: Player,
		((string) -> (boolean, string?))?
	) -> (boolean, string?, boolean),

	Start: (self: CartService) -> (),
}

local CartService: CartService = {} :: CartService
local cartSpawnedEvent = Instance.new("BindableEvent")
local cartDespawnedEvent = Instance.new("BindableEvent")
local performanceChangedEvent = Instance.new("BindableEvent")

CartService.CartSpawned = cartSpawnedEvent.Event
CartService.CartDespawned = cartDespawnedEvent.Event
CartService.PerformanceChanged = performanceChangedEvent.Event

local cartsByUserId: {
	[number]: SpawnedCartRecord,
} = {}
local ownersByUserId: { [number]: Player } = {}
local departingPlayers: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local started = false
local cargoRemovalHandler: ((Model) -> boolean?)? = nil
local nextCartGeneration = 0
local performanceOwnerStateReader: ((number) -> any?)? = nil
local performanceResolverOptions: any = nil

local PERFORMANCE_ATTRIBUTES = CartMovementProfileResolver.Attributes

local teamStatsReader = nil
function CartService:ConfigureTeamStats(reader)
	teamStatsReader = reader
end
local burstStateReader = nil
function CartService:ConfigureBurstState(reader)
	burstStateReader = reader
end

local function performanceSignature(result: any): string
	return table.concat({
		tostring(result.status),
		tostring(result.baseSpeed),
		tostring(result.purchasedSpeedContribution),
		tostring(result.resolvedSpeed),
		tostring(result.normalResolvedSpeed),
		tostring(result.hitMultiplier),
		tostring(result.burstCapacity),
		tostring(result.burstActive),
		table.concat(result.appliedOfferIds or {}, ","),
	}, "|")
end

local function publishPerformance(cart: Model, result: any, revision: number)
	cart:SetAttribute(PERFORMANCE_ATTRIBUTES.Status, result.status)
	cart:SetAttribute(PERFORMANCE_ATTRIBUTES.BaseSpeed, result.baseSpeed)
	cart:SetAttribute(PERFORMANCE_ATTRIBUTES.PurchasedSpeedContribution, result.purchasedSpeedContribution)
	cart:SetAttribute(PERFORMANCE_ATTRIBUTES.ResolvedMaxTravelSpeed, result.resolvedSpeed)
	cart:SetAttribute("BaseMaxTravelSpeed", result.baseResolvedSpeed or result.resolvedSpeed)
	cart:SetAttribute("NormalMaxTravelSpeed", result.normalResolvedSpeed or result.resolvedSpeed)
	cart:SetAttribute("TeamHitMultiplier", result.hitMultiplier or 1)
	cart:SetAttribute("TeamBurstCapacity", result.burstCapacity or 0)
	cart:SetAttribute("TeamAccelerationMultiplier", nil)
	cart:SetAttribute("TeamReelMultiplier", nil)
	cart:SetAttribute("TeamSpeedRatio", result.teamSpeedRatio or 1)
	-- Revision is the coherent publication marker and is deliberately written last.
	cart:SetAttribute(PERFORMANCE_ATTRIBUTES.Revision, revision)
end

function CartService:SetCargoRemovalHandler(handler: (Model) -> boolean?)
	cargoRemovalHandler = handler
end

function CartService:ResolveEffectivePerformance(ownerUserId: number, cartId: string, runtimeCart: Model?): any
	local ownerState = if performanceOwnerStateReader ~= nil then performanceOwnerStateReader(ownerUserId) else nil
	local base = CartPerformanceResolver.Resolve(ownerState, {
		cartId = cartId,
		ownerUserId = ownerUserId,
		durableCartId = if runtimeCart ~= nil then runtimeCart:GetAttribute("DurableCartId") else nil,
		runtimeCart = runtimeCart,
	}, performanceResolverOptions)
	local enabled = FeatureFlags.EquippedTeamsEnabled
	local team = if enabled and teamStatsReader then teamStatsReader(ownerUserId) else nil
	local burst = if enabled
			and burstStateReader
			and runtimeCart
		then burstStateReader(ownerUserId, runtimeCart)
		else nil
	return CartTeamPerformance.Resolve(base, team, burst ~= nil and burst.Active == true)
end

function CartService:ConfigurePerformance(options: any?)
	performanceOwnerStateReader = if type(options) == "table" then options.OwnerStateReader else nil
	performanceResolverOptions = if type(options) == "table" then options.ResolverOptions else nil
	for _, record in cartsByUserId do
		if record.Model.Parent ~= nil then
			self:ReconcileCartPerformance(record.Model, "PerformanceConfigurationChanged")
		end
	end
end

local function getCartRecord(player: Player): SpawnedCartRecord?
	return if ownersByUserId[player.UserId] == player then cartsByUserId[player.UserId] else nil
end

local function clearNetworkOwnership(cartModel: Model)
	local root = CartModelUtility.GetRoot(cartModel)

	local success, errorMessage = pcall(function()
		CartModelUtility.SetRootAnchoredOnly(cartModel, false)

		if CartOccupantService:IsCartRegistered(cartModel) then
			CartOccupantService:RevokeControl(cartModel, "CartService clearing network ownership")
		end
		root:SetNetworkOwner(nil)
	end)

	if not success then
		log:Warn("Failed to clear network owner: %s", tostring(errorMessage))
	end
end

local function restoreAuthorizedNetworkOwner(cartModel: Model)
	if CartOccupantService:IsCartRegistered(cartModel) then
		CartOccupantService:RestoreNetworkOwnership(cartModel, "CartService ownership restoration")
		return
	end
	local root = CartModelUtility.GetRoot(cartModel)

	local canSet, reason = root:CanSetNetworkOwnership()

	if not canSet then
		log:Warn("Cannot set network owner for %s: %s", cartModel.Name, tostring(reason))

		return
	end

	-- A newly spawned, not-yet-registered cart has no accepted driver. Ownership
	-- of the cart item is not permission to simulate it (including while carrying).
	root:SetNetworkOwner(nil)
end

local function prepareClone(cartModel: Model, player: Player, cartId: string, spawnId: string)
	cartModel.Name = string.format("Cart_%d", player.UserId)

	cartModel:SetAttribute("OwnerUserId", player.UserId)

	cartModel:SetAttribute("CartId", cartId)

	cartModel:SetAttribute("SpawnId", spawnId)

	cartModel:SetAttribute("SpawnedAt", Workspace:GetServerTimeNow())

	cartModel:SetAttribute("RuntimeCart", true)
end

function CartService:GetCart(player: Player): Model?
	local record = getCartRecord(player)

	if record == nil then
		return nil
	end

	if record.Model.Parent == nil then
		cartsByUserId[player.UserId] = nil
		ownersByUserId[player.UserId] = nil
		return nil
	end

	return record.Model
end

function CartService:GetCartRecord(player: Player): SpawnedCartRecord?
	return getCartRecord(player)
end

function CartService:GetCartHandle(player: Player): any?
	local record = getCartRecord(player)
	if record == nil or record.Model.Parent == nil then
		return nil
	end
	return table.freeze({
		Player = player,
		OwnerUserId = record.OwnerUserId,
		Model = record.Model,
		Generation = record.Generation,
	})
end

function CartService:IsCurrentCartHandle(handle: any): boolean
	if type(handle) ~= "table" or handle.Player == nil then
		return false
	end
	local record = getCartRecord(handle.Player)
	return record ~= nil
		and record.OwnerUserId == handle.OwnerUserId
		and record.Model == handle.Model
		and record.Generation == handle.Generation
end

function CartService:IsAuthorizedDriver(player: Player, cart: Model): boolean
	local record = getCartRecord(player)
	return record ~= nil and record.Model == cart and CartOccupantService:IsDriver(player, cart)
end

function CartService:GetCartRecords(): { SpawnedCartRecord }
	local records: { SpawnedCartRecord } = {}

	for _, record in cartsByUserId do
		if record.Model.Parent ~= nil then
			table.insert(records, record)
		end
	end

	return records
end

function CartService:GetCartRecordByOwnerUserId(ownerUserId: number): SpawnedCartRecord?
	local record = cartsByUserId[ownerUserId]

	if record ~= nil and record.Model.Parent == nil then
		cartsByUserId[ownerUserId] = nil
		ownersByUserId[ownerUserId] = nil
		return nil
	end

	return record
end

function CartService:ReconcileCartPerformance(cart: Model, reason: string?): any
	local ownerUserId = cart:GetAttribute("OwnerUserId")
	local record = if type(ownerUserId) == "number" then cartsByUserId[ownerUserId] else nil
	if record == nil or record.Model ~= cart or cart.Parent == nil then
		return table.freeze({ status = "StaleCart", code = "STALE_CART_BINDING" })
	end
	local performance = self:ResolveEffectivePerformance(record.OwnerUserId, record.CartId, cart)
	if performance.status ~= "Ready" or type(performance.resolvedSpeed) ~= "number" then
		return performance
	end
	local signature = performanceSignature(performance)
	if signature == record.PerformanceSignature then
		return performance
	end
	local resolved, profileOrError = pcall(function()
		return CartMovementProfileResolver.Resolve(record.CartId, performance)
	end)
	if not resolved then
		log:Warn(
			"Rejected cart performance result Cart=%s CartId=%s Error=%s",
			cart.Name,
			record.CartId,
			tostring(profileOrError)
		)
		return table.freeze({ status = "InvalidPerformance", code = "INVALID_MOVEMENT_PROFILE" })
	end
	local profile = profileOrError :: EffectiveMovementProfile
	local longitudinalReady, longitudinalError = CartArcadeService:UpdateProfile(cart, profile)
	if not longitudinalReady then
		return table.freeze({
			status = "RuntimeNotReady",
			code = "ARCADE_PROFILE_NOT_READY",
			detail = longitudinalError,
		})
	end

	local previousProfile = record.MovementProfile
	record.MovementProfile = profile
	record.PerformanceResult = performance
	record.PerformanceSignature = signature
	record.PerformanceRevision += 1
	publishPerformance(cart, performance, record.PerformanceRevision)
	performanceChangedEvent:Fire(record, previousProfile, profile, reason or "Reconciled")
	log:Info(
		"CartPerformanceReconciled userId=%d cartId=%s speed=%.2f contribution=%.3f revision=%d reason=%s",
		record.OwnerUserId,
		record.CartId,
		profile.MaxTravelSpeed,
		performance.purchasedSpeedContribution,
		record.PerformanceRevision,
		reason or "Reconciled"
	)
	return performance
end

function CartService:ReconcileOwnerPerformance(ownerUserId: number, reason: string?): any?
	local record = self:GetCartRecordByOwnerUserId(ownerUserId)
	if record == nil then
		return nil
	end
	return self:ReconcileCartPerformance(record.Model, reason)
end

local function unregisterRuntimeServices(cartModel: Model, reason: string)
	CartArcadeService:UnregisterCart(cartModel, reason)
	CartStabilityService:UnregisterCart(cartModel, reason)
	CartTerrainService:UnregisterCart(cartModel, reason)
	CartOccupantService:UnregisterCart(cartModel, reason)
	CartAssemblyValidationService:ForgetCart(cartModel, reason)
end

function CartService:DespawnCart(player: Player, reason: string?, expectedHandle: any?)
	local record = getCartRecord(player)

	if record == nil then
		return
	end
	if
		expectedHandle ~= nil
		and (
			expectedHandle.Player ~= player
			or expectedHandle.Model ~= record.Model
			or expectedHandle.Generation ~= record.Generation
		)
	then
		return
	end
	-- Synchronous record handoff BEFORE any despawn observer or ancestor deletion.
	-- A handler error stops removal rather than silently discarding unbanked cargo.
	if cargoRemovalHandler and cargoRemovalHandler(record.Model) == false then
		log:Warn("Retained obsolete cart: fresh destination unavailable UserId=%d", player.UserId)
		return false
	end

	cartsByUserId[player.UserId] = nil
	ownersByUserId[player.UserId] = nil
	local despawnedAt = Workspace:GetServerTimeNow()

	cartDespawnedEvent:Fire(record, reason or "Unknown", despawnedAt)

	if record.Model.Parent ~= nil then
		clearNetworkOwnership(record.Model)
		unregisterRuntimeServices(record.Model, reason or "Cart despawned")
		record.Model:Destroy()
	end

	log:Info("Despawned cart for %s. Reason=%s", player.Name, reason or "Unknown")
	return true
end

-- Only a freshly acquired new session may finish an exact departed actor's
-- retained cart. Known pending-bank source cleanup must precede count release;
-- unrelated fresh cargo uses the existing counted logout return queue.
function CartService:RecoverDepartedCart(oldPlayer: Player, newPlayer: Player, canonicalData: any): (boolean, string?)
	if oldPlayer == newPlayer or oldPlayer.UserId ~= newPlayer.UserId or oldPlayer.Parent == Players then
		return false, "OLD_OWNER_ACTIVE"
	end
	local profiles = require(script.Parent.PlayerDataService)
	local session = profiles:GetSessionHandle(newPlayer)
	if not session or not profiles:IsCurrentSessionHandle(session) or not profiles:GetReadableData(newPlayer) then
		return false, "PROFILE_NOT_READY"
	end
	local banked = require(script.Parent.BankedBrainrotService)
	local reconciled = banked:ReconcilePendingBanksOnAcquire(newPlayer)
	if not reconciled.ok or banked:HasPendingBank(newPlayer) then
		return false, "BANK_SAVE_PENDING"
	end
	local cargo = require(script.Parent.CartCargoService)
	if not cargo:ReconcileRecoveredCartReturns(oldPlayer, canonicalData) then
		return false, "CARGO_RETURN_PENDING"
	end
	local record = getCartRecord(oldPlayer)
	if not record then
		return true
	end
	if not cargo:PrepareRecoveredCartRemoval(record.Model, oldPlayer, canonicalData) then
		return false, "CARGO_RECOVERY_PENDING"
	end
	local handle = self:GetCartHandle(oldPlayer)
	return self:DespawnCart(oldPlayer, "Recovered departed cart", handle) == true, nil
end

local function resolveSpawnRecord(cartId: string, spawnId: string?, homeBase: Model?): CartSpawnRecord
	if homeBase ~= nil then
		local marker = homeBase:FindFirstChild("CartSpawn")
		assert(marker ~= nil and marker:IsA("BasePart"), "Assigned base requires CartSpawn BasePart")
		CartSpawnValidator.AssertValid(marker)
		-- The assigned base pad is shared by all owned Phase 13 cart variants.
		-- Its authored starter CartId remains registry metadata, not an entitlement.
		-- Owner-specific homes must not become candidates in the shared default-pad registry.
		return {
			Id = marker:GetAttribute("SpawnId") :: string,
			CartId = cartId,
			Priority = marker:GetAttribute("Priority") :: number,
			Enabled = marker:GetAttribute("Enabled") :: boolean,
			DebugOnly = marker:GetAttribute("DebugOnly") == true,
			Part = marker,
			CFrame = marker.CFrame,
		}
	end

	if spawnId ~= nil then
		local requestedSpawn: CartSpawnRecord? = CartSpawnRegistry:GetById(spawnId)

		if requestedSpawn == nil then
			error(string.format("Unknown cart SpawnId %s", spawnId), 2)
		end

		return requestedSpawn :: CartSpawnRecord
	end

	local defaultSpawn: CartSpawnRecord? = CartSpawnRegistry:GetDefaultForCart(cartId)

	if defaultSpawn == nil then
		error(string.format("No enabled spawn for CartId %s", cartId), 2)
	end

	return defaultSpawn :: CartSpawnRecord
end

function CartService:SpawnCart(player: Player, cartId: string?, spawnId: string?): Model
	assert(FeatureFlags.CartEnabled, "Cart feature is disabled")

	assert(player.Parent == Players and not departingPlayers[player], "Player is not active")
	local oldOwner = ownersByUserId[player.UserId]
	if oldOwner and oldOwner ~= player then
		local profiles = require(script.Parent.PlayerDataService)
		local recovered, reason = self:RecoverDepartedCart(oldOwner, player, profiles:GetReadableData(player))
		assert(recovered, "Departed cart recovery waits: " .. tostring(reason))
	end

	-- Explicit scenario pads keep their existing replacement behaviour.
	local homeBase = if spawnId == nil then PlayerBaseSystem:GetBase(player) else nil
	local existing = self:GetCart(player)
	if existing ~= nil and homeBase ~= nil then
		assert(CartAssemblyValidationService:IsCartValid(existing), "Existing cart is awaiting validation cleanup")
		return existing
	end
	if existing ~= nil then
		assert(
			self:DespawnCart(player, "Replacing existing cart") ~= false,
			"Cart replacement waits for a coherent local fresh-cargo destination"
		)
	end
	assert(cartsByUserId[player.UserId] == nil, "Another Player instance still owns this UserId's cart")

	local ownerState = if performanceOwnerStateReader then performanceOwnerStateReader(player.UserId) else nil
	local selectedId = ownerState and ownerState.phase13 and ownerState.phase13.SelectedCartId
	local resolvedCartId = cartId or selectedId or Ids.Carts.ScrapChariot

	local definition = Carts[resolvedCartId]

	assert(definition ~= nil, string.format("Unknown CartId %s", resolvedCartId))

	local spawnRecord: CartSpawnRecord = resolveSpawnRecord(resolvedCartId, spawnId, homeBase)

	assert(spawnRecord.Enabled, string.format("Cart spawn %s is disabled", spawnRecord.Id))

	local cartModel = CartAssetService:CloneAsset(resolvedCartId)
	-- Asset readiness may yield. Recheck ownership before publishing or claiming the clone.
	if
		player.Parent ~= Players
		or departingPlayers[player]
		or (homeBase ~= nil and PlayerBaseSystem:GetBase(player) ~= homeBase)
	then
		cartModel:Destroy()
		error("Cart creation cancelled: player left or base assignment changed", 2)
	end
	local concurrentCart = self:GetCart(player)
	if concurrentCart ~= nil and homeBase ~= nil then
		cartModel:Destroy()
		assert(CartAssemblyValidationService:IsCartValid(concurrentCart), "Concurrent cart is not valid")
		return concurrentCart
	end
	if cartsByUserId[player.UserId] ~= nil then
		cartModel:Destroy()
		error("Cart creation cancelled: owner record changed while loading the asset", 2)
	end
	local performance = self:ResolveEffectivePerformance(player.UserId, resolvedCartId, cartModel)
	if performance.status ~= "Ready" or type(performance.resolvedSpeed) ~= "number" then
		cartModel:Destroy()
		error(string.format("Cart creation cancelled: performance unavailable (%s)", tostring(performance.code)), 2)
	end
	local movementProfile = CartMovementProfileResolver.Resolve(resolvedCartId, performance)

	prepareClone(cartModel, player, resolvedCartId, spawnRecord.Id)
	publishPerformance(cartModel, performance, 1)
	CartArcadeRig.Configure(cartModel)

	CartModelUtility.SetAnchored(cartModel, true)
	local assignedFrame = spawnRecord.CFrame * CartGeometry.SpawnOffset(cartModel)
	local assignedIdentity = if homeBase
		then {
			Base = homeBase,
			Marker = spawnRecord.Part,
			Player = player,
			CurrentBase = function()
				return PlayerBaseSystem:GetBase(player)
			end,
		}
		else nil
	while true do
		local clear, obstruction = CartLocalPlacement.ValidateAssignedSpawn(cartModel, assignedFrame, assignedIdentity)
		if clear then
			break
		end
		cartModel:SetAttribute("PendingSpawnReason", obstruction)
		task.wait(1)
		if
			player.Parent ~= Players
			or departingPlayers[player]
			or (homeBase and PlayerBaseSystem:GetBase(player) ~= homeBase)
		then
			cartModel:Destroy()
			error("Assigned cart spawn cancelled with player/base lifecycle", 2)
		end
		if self:GetCart(player) then
			cartModel:Destroy()
			return self:GetCart(player) :: Model
		end
	end
	cartModel:SetAttribute("PendingSpawnReason", nil)

	cartModel.Parent = RuntimeFolders.GetCartsFolder()

	cartModel:PivotTo(spawnRecord.CFrame * CartGeometry.SpawnOffset(cartModel))

	CollisionService:SetModelCollisionGroup(cartModel, CollisionGroups.Carts)

	CartModelUtility.ZeroVelocities(cartModel)

	CartModelUtility.SetRootAnchoredOnly(cartModel, false)

	restoreAuthorizedNetworkOwner(cartModel)

	nextCartGeneration += 1
	cartModel:SetAttribute("CartGeneration", nextCartGeneration)
	local record: SpawnedCartRecord = {
		OwnerUserId = player.UserId,
		CartId = resolvedCartId,
		SpawnId = spawnRecord.Id,
		Model = cartModel,
		SpawnCFrame = spawnRecord.CFrame * CartGeometry.SpawnOffset(cartModel),
		CreatedAt = Workspace:GetServerTimeNow(),
		MovementProfile = movementProfile,
		PerformanceResult = performance,
		PerformanceRevision = 1,
		PerformanceSignature = performanceSignature(performance),
		Generation = nextCartGeneration,
	}

	cartsByUserId[player.UserId] = record
	ownersByUserId[player.UserId] = player

	local registered, registrationError = pcall(function()
		local assemblyValid, _, assemblyError = CartAssemblyValidationService:RegisterCart(cartModel)
		assert(assemblyValid, assemblyError or "cart assembly registration failed")

		local occupantRegistered, occupantError = CartOccupantService:RegisterCart(cartModel, player.UserId)
		assert(occupantRegistered, occupantError or "cart occupancy registration failed")

		local terrainRegistered, terrainError = CartTerrainService:RegisterCart(cartModel)
		assert(terrainRegistered, terrainError or "cart terrain registration failed")

		local stabilityRegistered, stabilityError = CartStabilityService:RegisterCart(cartModel)
		assert(stabilityRegistered, stabilityError or "cart stability registration failed")

		local longitudinalRegistered, longitudinalError =
			CartArcadeService:RegisterCart(cartModel, movementProfile)
		assert(longitudinalRegistered, longitudinalError or "cart arcade registration failed")
	end)
	if not registered then
		if cartsByUserId[player.UserId] == record then
			self:DespawnCart(player, "Cart registration failed")
		end
		error(tostring(registrationError), 2)
	end

	cartSpawnedEvent:Fire(record, record.CreatedAt)

	cartModel.Destroying:Connect(function()
		local current = cartsByUserId[player.UserId]

		if current and current.Model == cartModel then
			cartsByUserId[player.UserId] = nil
			ownersByUserId[player.UserId] = nil
		end
	end)

	log:Info("Spawned %s for %s at %s", resolvedCartId, player.Name, spawnRecord.Id)

	return cartModel
end

-- Existing model/root/semantic identities survive choices. Legacy skins retain
-- their old path; fitted units change physical/layout data atomically at the dock
-- after unoccupied/parked preflight, retaining cargo individuals and save owners.
local function ownedSelectionBusy(cart: Model?): boolean
	return Workspace:GetAttribute("Phase12ResetCommitting") == true
		or (cart ~= nil and cart:GetAttribute("Phase13CargoResetGeneration") ~= nil)
end
local function validateOwnedDock(player: Player, cart: Model?): (boolean, string?)
	if not cart or cart.Parent == nil then
		return false, "OWN_CART_UNAVAILABLE"
	end
	if ownedSelectionBusy(cart) then
		return false, "RESET_BUSY"
	end
	local base = PlayerBaseSystem:GetBase(player)
	local dock = base and base:FindFirstChild("CartSpawn")
	if
		not dock
		or not dock:IsA("BasePart")
		or (CartModelUtility.GetRoot(cart).Position - dock.Position).Magnitude > 18
	then
		return false, "OWN_CART_MUST_BE_DOCKED"
	end
	local cargo = require(script.Parent.CartCargoService)
	return cargo:CanSelectOwnedCart(cart)
end
local function validateGeometrySelection(token: any): (boolean,string?)
	local cart=token.Handle.Model
	local seat=CartModelUtility.GetDriverSeat(cart)
	local root=CartModelUtility.GetRoot(cart)
	if seat.Occupant or seat:FindFirstChild("SeatWeld")then return false,"DISMOUNT_BEFORE_VEHICLE_CHANGE"end
	if root.AssemblyLinearVelocity.Magnitude>0.6 or root.AssemblyAngularVelocity.Magnitude>0.1 then return false,"PARK_BEFORE_VEHICLE_CHANGE"end
	local base=PlayerBaseSystem:GetBase(token.Player)
	local marker=base and base:FindFirstChild("CartSpawn")
	if not marker or not marker:IsA("BasePart")or marker.CFrame*CartGeometry.SpawnOffset(token.Asset)~=token.DockFrame then return false,"DOCK_CHANGED"end
	local probe=token.Asset:Clone()
	probe:SetAttribute("OwnerUserId",token.Player.UserId);probe:SetAttribute("CartId",token.CartId);probe:SetAttribute("SpawnId",cart:GetAttribute("SpawnId"))
	local ok,clear,why=pcall(function()
		return CartLocalPlacement.ValidateAssignedSpawn(probe,token.DockFrame,{
			Base=base,Marker=marker,Player=token.Player,ExistingCart=cart,
			CurrentBase=function()return PlayerBaseSystem:GetBase(token.Player)end,
		})
	end)
	probe:Destroy()
	return ok and clear==true,if ok then why else "GEOMETRY_PLACEMENT_UNAVAILABLE"
end

local function commitGeometrySelection(self: any,_player: Player,record: any,cart: Model,token: any,cartId: string): boolean
	local allowed,why=token.Validate()
	if not allowed then log:Warn("Vehicle fit selection rejected: %s",tostring(why));return false end
	local transaction,prepareReason=CartGeometrySwap.Prepare(cart,token.Asset,token.DockFrame)
	if not transaction then log:Warn("Vehicle unit unavailable: %s",tostring(prepareReason));return false end
	local root=CartModelUtility.GetRoot(cart)
	local previousId,previousSkin=record.CartId,cart:GetAttribute("Phase13SelectedSkin")
	local previousSignature,previousPerformance,previousProfile,previousRevision=record.PerformanceSignature,record.PerformanceResult,record.MovementProfile,record.PerformanceRevision
	local stabilitySuspended,terrainSuspended,controlSuspended=false,false,false
	local revision=nil
	local applied=false
	local ok,failure=pcall(function()
		assert(CartOccupantService:SuspendControl(cart,"vehicle geometry swap"),"control suspension failed");controlSuspended=true
		local stable,stableReason=CartStabilityService:SuspendCart(cart,"vehicle geometry swap");assert(stable,stableReason);stabilitySuspended=true
		local terrain,terrainReason=CartTerrainService:SuspendCart(cart,"vehicle geometry swap");assert(terrain,terrainReason);terrainSuspended=true
		local begun,newRevision,mutationReason=CartAssemblyValidationService:BeginMutation(cart,"vehicle geometry swap");assert(begun and newRevision,mutationReason);revision=newRevision
		root.Anchored=true;CartModelUtility.ZeroVelocities(cart)
		transaction.Apply();applied=true
		CartArcadeRig.Configure(cart)
		CollisionService:SetModelCollisionGroup(cart,CollisionGroups.Carts)
		record.CartId=cartId;record.PerformanceSignature=""
		cart:SetAttribute("CartId",cartId);cart:SetAttribute("Phase13SelectedSkin",cartId)
		cart:SetAttribute("LastServerMovementUpdate",Workspace:GetServerTimeNow())
		root.Anchored=false;CartModelUtility.ZeroVelocities(cart)
		local valid,_,reason=CartAssemblyValidationService:CompleteMutation(cart,revision,"Runtime","vehicle unit installed",true);assert(valid,reason)
		assert(self:ReconcileCartPerformance(cart,"OwnedCartGeometrySelection").status=="Ready","performance reconciliation failed")
		local terrainReady,terrainReason2=CartTerrainService:ResumeCart(cart,"vehicle geometry swap");assert(terrainReady,terrainReason2);terrainSuspended=false
		local stabilityReady,stabilityReason2=CartStabilityService:ResumeCart(cart,"vehicle geometry swap");assert(stabilityReady,stabilityReason2);stabilitySuspended=false
		assert(CartOccupantService:ResumeControl(cart,"vehicle geometry swap"),"control resume failed");controlSuspended=false
		assert(CartOccupantService:RestoreNetworkOwnership(cart,"vehicle geometry swap"),"network ownership restore failed")
	end)
	if ok then transaction.Commit();return true end
	-- Restore the complete prior physical/layout/presentation unit. Saves and
	-- cargo records are untouched; a durable choice retries through normal flow.
	local recovered,recoveryReason=pcall(function()
		-- A later resume can fail after an earlier subsystem is running. Stop
		-- those readers again before restoring their previous geometry snapshot.
		if applied then
			assert(CartOccupantService:SuspendControl(cart,"vehicle geometry rollback"));controlSuspended=true
			assert(CartStabilityService:SuspendCart(cart,"vehicle geometry rollback"));stabilitySuspended=true
			assert(CartTerrainService:SuspendCart(cart,"vehicle geometry rollback"));terrainSuspended=true
		end
		if applied then
			if CartAssemblyValidationService:GetState(cart)~="Preparing"then local expected=if CartAssemblyValidationService:GetState(cart)=="Invalid"then revision else nil;local begun,r=CartAssemblyValidationService:BeginMutation(cart,"vehicle geometry rollback",expected);assert(begun and r,"geometry rollback mutation unavailable");revision=r end
			root.Anchored=true
		end
		transaction.Rollback()
		CartArcadeRig.Configure(cart)
		record.CartId=previousId;record.PerformanceSignature=previousSignature;record.PerformanceResult=previousPerformance;record.MovementProfile=previousProfile;record.PerformanceRevision=previousRevision
		cart:SetAttribute("CartId",previousId);cart:SetAttribute("Phase13SelectedSkin",previousSkin)
		if previousPerformance then publishPerformance(cart,previousPerformance,previousRevision)end
		if previousProfile then CartArcadeService:UpdateProfile(cart,previousProfile)end
		root.Anchored=false;CartModelUtility.ZeroVelocities(cart)
		if revision then local valid,_,reason=CartAssemblyValidationService:CompleteMutation(cart,revision,"Runtime","vehicle geometry rollback",true);assert(valid,reason)end
		if terrainSuspended then assert(CartTerrainService:ResumeCart(cart,"vehicle geometry rollback"))end
		if stabilitySuspended then assert(CartStabilityService:ResumeCart(cart,"vehicle geometry rollback"))end
		if controlSuspended then assert(CartOccupantService:ResumeControl(cart,"vehicle geometry rollback"))end
		assert(CartOccupantService:RestoreNetworkOwnership(cart,"vehicle geometry rollback"))
	end)
	log:Warn("Retained previous vehicle after geometry selection failure: %s; rollback=%s %s",tostring(failure),tostring(recovered),tostring(recoveryReason))
	return false
end
function CartService:PrepareOwnedCartSelection(player: Player, cartId: string): (any?, string?)
	local state = if performanceOwnerStateReader then performanceOwnerStateReader(player.UserId) else nil
	local p = state and state.phase13
	if not p or not p.OwnedCartIds or p.OwnedCartIds[cartId] ~= true or not Carts[cartId] then
		return nil, "CART_NOT_OWNED"
	end
	local cart = self:GetCart(player)
	if ownedSelectionBusy(cart) then
		return nil, "RESET_BUSY"
	end
	if cart and not CartAssemblyValidationService:IsCartValid(cart) then
		return nil, "CART_NOT_READY"
	end
	local allowed, dockReason = validateOwnedDock(player, cart)
	if not allowed then
		return nil, dockReason
	end
	-- Asset readiness may yield; no ownership or live state changes during preparation.
	local ok, asset = pcall(function()
		return CartAssetService:GetAsset(cartId)
	end)
	if not ok then
		return nil, "CART_ASSET_UNAVAILABLE"
	end
	if player.Parent ~= Players or ownedSelectionBusy(self:GetCart(player)) then
		return nil, "CONTEXT_CHANGED"
	end
	local visual = asset:FindFirstChild("Visual")
	local root = asset:FindFirstChild("Root")
	if not visual or not visual:IsA("Model") or not root or not root:IsA("BasePart") then
		return nil, "CART_ASSET_INCOMPATIBLE"
	end
	local geometryChange=cart and (cart:GetAttribute("CartGeometryId")~=nil or asset:GetAttribute("CartGeometryId")~=nil)
	local base=if geometryChange then PlayerBaseSystem:GetBase(player)else nil
	local dock=base and base:FindFirstChild("CartSpawn")
	if geometryChange and (not dock or not dock:IsA("BasePart"))then return nil,"DOCK_UNAVAILABLE"end
	local token = {
		GeometryChange=geometryChange,
		DockFrame=if dock and dock:IsA("BasePart")then dock.CFrame*CartGeometry.SpawnOffset(asset)else nil,
		Player = player,
		CartId = cartId,
		Asset = asset,
		Visual = visual,
		SourceRoot = root,
		Handle = self:GetCartHandle(player),
	}
	token.Validate = function()
		if not self:IsCurrentCartHandle(token.Handle) then
			return false, "CART_CHANGED"
		end
		local dockValid,dockWhy=validateOwnedDock(player,self:GetCart(player))
		if not dockValid then return false,dockWhy end
		if token.GeometryChange then return validateGeometrySelection(token)end
		return true,nil
	end
	local valid, why = token.Validate()
	if not valid then
		return nil, why
	end
	return token, nil
end
function CartService:CommitOwnedCartSelection(player: Player, preparation: any, cartId: string): boolean
	if type(preparation) ~= "table" or preparation.Player ~= player or preparation.CartId ~= cartId then
		return false
	end
	local state = if performanceOwnerStateReader then performanceOwnerStateReader(player.UserId) else nil
	local p = state and state.phase13
	if not p or p.SelectedCartId ~= cartId or p.OwnedCartIds[cartId] ~= true then
		return false
	end
	local cart = self:GetCart(player)
	if ownedSelectionBusy(cart) then
		return false
	end
	if cart then
		local cargo = require(script.Parent.CartCargoService)
		if not cargo:CanSelectOwnedCart(cart) then
			return false
		end
	end
	-- A destroyed cart will be created directly from the durable selected asset on
	-- its next normal spawn. No cargo-bearing model is replaced here.
	if not cart then
		return true
	end
	local record = getCartRecord(player)
	if not record or not CartAssemblyValidationService:IsCartValid(cart) then
		return false
	end
	if record.CartId == cartId and cart:GetAttribute("Phase13SelectedSkin") == cartId
		and cart:GetAttribute("CartGeometryId")==preparation.Asset:GetAttribute("CartGeometryId")
		and cart:GetAttribute("CartGeometryRevision")==preparation.Asset:GetAttribute("CartGeometryRevision")
		and CartGeometry.ValidateTemplate(cart)then
		return true
	end
	if preparation.GeometryChange then return commitGeometrySelection(self,player,record,cart,preparation,cartId)end
	local old = cart:FindFirstChild("Visual")
	local chassis = old and old:FindFirstChild("Chassis")
	if not old or not chassis or not chassis:IsA("BasePart") or not chassis.CanCollide then
		return false
	end
	local visual = preparation.Visual:Clone()
	local replacementChassis = visual:FindFirstChild("Chassis")
	if replacementChassis then
		replacementChassis:Destroy()
	end
	local root = CartModelUtility.GetRoot(cart)
	for _, child in visual:GetDescendants() do
		if child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
	for _, part in visual:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = root.CFrame * preparation.SourceRoot.CFrame:ToObjectSpace(part.CFrame)
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.RootPriority = -127
			local weld = Instance.new("WeldConstraint")
			weld.Name = "Phase13SkinWeld"
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	-- The verified physical collision chassis lives inside Visual. Preserve its
	-- exact part, frame, collision properties and every external rigid link.
	chassis.Parent = visual
	for _, joint in old:GetDescendants() do
		if
			(joint:IsA("WeldConstraint") or joint:IsA("JointInstance"))
			and (joint.Part0 == chassis or joint.Part1 == chassis)
		then
			joint.Parent = chassis
		end
	end
	if old then
		for _, joint in cart:GetDescendants() do
			if joint:IsA("WeldConstraint") or joint:IsA("JointInstance") then
				if
					(joint.Part0 and joint.Part0:IsDescendantOf(old))
					or (joint.Part1 and joint.Part1:IsDescendantOf(old))
				then
					joint:Destroy()
				end
			end
		end
		old:Destroy()
	end
	visual.Name = "Visual"
	visual.Parent = cart
	CollisionService:SetModelCollisionGroup(visual, CollisionGroups.Carts)
	record.CartId = cartId
	record.PerformanceSignature = ""
	cart:SetAttribute("CartId", cartId)
	cart:SetAttribute("Phase13SelectedSkin", cartId)
	return self:ReconcileCartPerformance(cart, "OwnedCartSelection").status == "Ready"
end

-- Removed gameplay/base-return API. Retained only to fail closed for old callers.
function CartService:ResetCart(_player: Player, _stageCallback: any?): (boolean, string?, boolean)
	return false, "Manual reset removed; cart correction is automatic", true
end

-- Caller supplies a server-prepared local plan, never an assigned spawn frame.
function CartService:CorrectCartLocal(player: Player, plan: any, stageCallback: any?): (boolean, string?, boolean)
	local record = getCartRecord(player)
	if not record or record.Model ~= plan.cart then
		return false, "active cart changed", true
	end
	return CartResetExecutor.ExecuteLocal(record.Model, plan, player, stageCallback)
end

-- Server-only wipe lifecycle entry, fenced by the current exact pending job.
-- Existing spawn support/clearance and assembly/movement validation stay active.
function CartService:ReturnCartForTimedWipe(player: Player, cart: Model, cycleId: number): (boolean, string?)
	local world = require(script.Parent.Phase12WorldService)
	if not world:IsReturnAuthorized(player, cart, cycleId) or self:GetCart(player) ~= cart then
		return false, "Invalid wipe generation"
	end
	local base = PlayerBaseSystem:GetBase(player)
	local marker = base and base:FindFirstChild("CartSpawn")
	if not marker or not marker:IsA("BasePart") then
		return false, "Assigned spawn unavailable"
	end
	local frame = marker.CFrame * CartGeometry.SpawnOffset(cart)
	local assignment = {
		Base = base,
		Marker = marker,
		Player = player,
		CurrentBase = function()
			return PlayerBaseSystem:GetBase(player)
		end,
	}
	local function valid()
		return player.Parent == Players
			and self:GetCart(player) == cart
			and world:IsReturnAuthorized(player, cart, cycleId)
			and assignment.CurrentBase() == base
			and marker.Parent == base
			and marker.CFrame * CartGeometry.SpawnOffset(cart) == frame
	end
	if cart:GetAttribute("Phase12StreamingCycle") ~= cycleId then
		cart:SetAttribute("Phase12StreamingCycle", cycleId)
		local ok = pcall(function()
			player:RequestStreamAroundAsync(frame.Position, 2)
		end)
		if not ok then
			cart:SetAttribute("Phase12StreamingCycle", nil)
			return false, "Streaming preparation pending"
		end
	end
	if not valid() then
		return false, "Assigned return changed"
	end
	local placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
	local clear, reason = placement.ValidateAssignedSpawn(cart, frame, assignment)
	if not clear then
		return false, reason
	end
	cart:SetAttribute("CartResetActive", true)
	local ok, result, detail =
		pcall(CartResetExecutor.ReturnAssignedForWipe, cart, frame, { Validate = valid, Assignment = assignment })
	if cart.Parent then
		cart:SetAttribute("CartResetActive", false)
	end
	if not ok then
		return false, tostring(result)
	end
	return result, detail
end

-- Drive-and-Hunt: move the owner's own parked, empty cart to a server-chosen frame.
-- The frame comes from DriveAndHuntService (never a client); clearance, support and
-- gate/region permission are re-proved inside the executor at commit.
function CartService:RelocateParkedCart(player: Player, cart: Model, frame: CFrame): (boolean, string?)
	local record = getCartRecord(player)
	if not record or record.Model ~= cart or cart.Parent == nil then
		return false, "active cart changed"
	end
	if cart:GetAttribute("CartResetActive") == true then
		return false, "cart correction in progress"
	end
	local function valid()
		local current = getCartRecord(player)
		return player.Parent == Players and current ~= nil and current.Model == cart and cart.Parent ~= nil
	end
	cart:SetAttribute("CartResetActive", true)
	local ok, result, detail = pcall(CartResetExecutor.RelocateParked, cart, frame, { Validate = valid })
	if cart.Parent then
		cart:SetAttribute("CartResetActive", false)
	end
	if not ok then
		return false, tostring(result)
	end
	return result, detail
end

function CartService:Start()
	if started then
		return
	end
	if not FeatureFlags.CartEnabled then
		log:Info("Cart feature disabled")
		return
	end
	started = true

	CartAssemblyValidationService:SetFatalHandler(function(cartModel, result, reason, failedRevision)
		local ownerUserId = cartModel:GetAttribute("OwnerUserId")
		local record = if typeof(ownerUserId) == "number" then cartsByUserId[ownerUserId] else nil

		if record ~= nil and record.Model == cartModel then
			task.defer(function()
				local player = Players:GetPlayerByUserId(ownerUserId :: number)

				if player ~= nil and cartsByUserId[ownerUserId] == record and getCartRecord(player) == record and CartAssemblyValidationService:IsCurrentFailure(cartModel,result,failedRevision) then
					self:DespawnCart(player, reason)
				end
			end)
		end
	end)

	CartStabilityService:SetFatalHandler(function(cartModel, reason)
		local ownerUserId = cartModel:GetAttribute("OwnerUserId")
		local record = if typeof(ownerUserId) == "number" then cartsByUserId[ownerUserId] else nil

		if record ~= nil and record.Model == cartModel then
			task.defer(function()
				local player = Players:GetPlayerByUserId(ownerUserId :: number)

				if player ~= nil and cartsByUserId[ownerUserId] == record and getCartRecord(player) == record then
					self:DespawnCart(player, reason)
				end
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		departingPlayers[player] = true
		self:DespawnCart(player, "Player leaving")
	end)
	require(script.Parent.PlayerDataService):SubscribeSessionRecovered(function(oldPlayer, newPlayer, canonicalData)
		return self:RecoverDepartedCart(oldPlayer, newPlayer, canonicalData)
	end)

	log:Info("Cart service ready")
end

-- Scoped synthetic record seam for disposable Edit-mode tests only. It cannot
-- bind a real Player or run in Play, and always restores all runtime readers.
function CartService:_TestWithOwnedSelectionRecord(player: any, record: any, reader: any, callback: any)
	assert(
		game:GetService("RunService"):IsStudio()
			and not game:GetService("RunService"):IsRunning()
			and type(player) == "table",
		"Synthetic Edit fixture only"
	)
	local oldRecord, oldOwner = cartsByUserId[player.UserId], ownersByUserId[player.UserId]
	local oldReader, oldTeam, oldBurst = performanceOwnerStateReader, teamStatsReader, burstStateReader
	cartsByUserId[player.UserId] = record
	ownersByUserId[player.UserId] = player
	performanceOwnerStateReader = reader
	teamStatsReader = nil
	burstStateReader = nil
	local ok, result = xpcall(callback, debug.traceback)
	cartsByUserId[player.UserId] = oldRecord
	ownersByUserId[player.UserId] = oldOwner
	performanceOwnerStateReader = oldReader
	teamStatsReader = oldTeam
	burstStateReader = oldBurst
	assert(ok, result)
end

return CartService
