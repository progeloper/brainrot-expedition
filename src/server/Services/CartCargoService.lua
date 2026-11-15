--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CreatureAssets = require(script.Parent.Parent.Utility.CreatureAssetService)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)
local CollisionGroups = require(ReplicatedStorage.Shared.Config.CollisionGroups)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local BrainrotDisplayMetadata = require(ReplicatedStorage.Shared.Utility.BrainrotDisplayMetadata)
local CargoCapacityResolver = require(ReplicatedStorage.Shared.Utility.CargoCapacityResolver)
local CartService = require(script.Parent.CartService)
local CollisionService = require(script.Parent.CollisionService)
local AssemblyValidation = require(script.Parent.CartAssemblyValidationService)
local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)

export type CargoEntry = {
	ItemId: string,
	BrainrotId: string,
	Metadata: { [string]: any },
	World: { [string]: any }?, -- Preserved restoration data; optional for legacy species-only cargo.
	AttachmentIndex: number,
}

local Trace = require(script.Parent.Parent.Utility.BrainrotDiagnostics)
local CartCargoService = {}
local cargoByCart: { [Model]: any } = {}
local started = false
local CARGO_SLOT_TAG = "BrainrotCargoSlot"
local preparedInsertions: { [any]: any } = {}
local pendingReturns: { [string]: any } = {}
local capacityOwnerStateReader: ((number) -> any?)? = nil
local capacityResolverOptions: any = nil
local Phase10 = require(ReplicatedStorage.Shared.Config.Phase10)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local classifyRecord: any = nil

function CartCargoService:ConfigureProvenance(reader: any)
	classifyRecord = reader
end

local function isFresh(record: any, ownerId: number?): boolean
	if not Phase10.Enabled then
		return false
	end
	if classifyRecord then
		return classifyRecord(record, ownerId) == "FreshUnbanked"
	end
	return record.Metadata == nil or record.Metadata.DurableOwnerUserId == nil
end

local function cargoCount(state: any): number
	local count = 0
	for _, entry in state.ById do
		if type(entry) == "table" then
			count += 1
		end
	end
	return count
end

local function capacityDescriptor(cart: Model): any
	return {
		cartId = cart:GetAttribute("CartId"),
		ownerUserId = cart:GetAttribute("OwnerUserId"),
		durableCartId = cart:GetAttribute("DurableCartId"),
		runtimeCart = cart,
	}
end

function CartCargoService:ResolveEffectiveCargoCapacity(cart: Model): any
	local ownerId = cart:GetAttribute("OwnerUserId")
	local ownerState = if capacityOwnerStateReader ~= nil and type(ownerId) == "number"
		then capacityOwnerStateReader(ownerId)
		else nil
	local resolverOptions = capacityResolverOptions
	if capacityOwnerStateReader == nil then
		resolverOptions = table.clone(capacityResolverOptions or {})
		resolverOptions.offers = {} -- Legacy/test carts retain their authored baseline only.
	end
	return CargoCapacityResolver.Resolve(ownerState, capacityDescriptor(cart), resolverOptions)
end

function CartCargoService:GetCargoCapacityReadiness(cart: Model): any
	local capacity = self:ResolveEffectiveCargoCapacity(cart)
	if capacity.status ~= "Ready" or type(capacity.effectiveCapacity) ~= "number" then
		return capacity
	end
	local layout = CartAssetValidator.ValidateCargoLayout(cart, capacity.effectiveCapacity)
	if layout.status ~= "Ready" then
		return table.freeze({
			status = "LayoutNotReady",
			code = "CARGO_LAYOUT_NOT_READY",
			baseCapacity = capacity.baseCapacity,
			upgradeBonus = capacity.upgradeBonus,
			effectiveCapacity = capacity.effectiveCapacity,
			appliedOfferIds = capacity.appliedOfferIds,
			blockedOfferIds = capacity.blockedOfferIds,
			layout = layout,
		})
	end
	return table.freeze({
		status = "Ready",
		code = capacity.code,
		baseCapacity = capacity.baseCapacity,
		upgradeBonus = capacity.upgradeBonus,
		effectiveCapacity = capacity.effectiveCapacity,
		appliedOfferIds = capacity.appliedOfferIds,
		blockedOfferIds = capacity.blockedOfferIds,
		layout = layout,
	})
end

function CartCargoService:ConfigureCapacity(options: any?)
	capacityOwnerStateReader = if type(options) == "table" then options.OwnerStateReader else nil
	capacityResolverOptions = if type(options) == "table" then options.ResolverOptions else nil
	for cart, state in cargoByCart do
		if cart.Parent ~= nil then
			self:ReconcileCargoCapacity(cart, "CapacityConfigurationChanged")
		else
			state.CapacitySignature = nil
		end
	end
end

-- Legacy secured records may lack restoration fields, not identity or sleep.
-- Derive only missing geometry context from the real source template; never mint
-- a new individual or impose a new sleep flag on cargo.
local function withWorldContext(record: CargoEntry, pose: CFrame): CargoEntry
	if record.World then
		return record
	end
	local template = CreatureAssets.GetTemplate(record.BrainrotId)
	if not template or not template:IsA("Model") then
		return record -- Keep custody; a missing template may become available later.
	end
	local normalized = table.clone(record)
	local canonicalScale = BrainrotVisualScale.GetCanonicalModelScale(template)
	if canonicalScale == nil then
		return record
	end
	normalized.World = table.freeze({
		Name = template.Name,
		Scale = canonicalScale,
		SpawnPosition = table.freeze({ X = pose.X, Y = pose.Y, Z = pose.Z }),
	})
	return table.freeze(normalized)
end

local function rememberCartPose(cart: Model, state: any)
	if not cart:IsDescendantOf(Workspace) or not cart.PrimaryPart then
		return
	end
	local pose = cart:GetPivot()
	for _, n in { pose:GetComponents() } do
		if n ~= n or math.abs(n) == math.huge then
			return
		end
	end
	local bounds, size = cart:GetBoundingBox()
	local radius = (Vector2.new(bounds.X, bounds.Z) - Vector2.new(pose.X, pose.Z)).Magnitude + size.Magnitude / 2
	state.LastPose, state.LastBounds = pose, { Radius = radius }
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { cart }
	params.RespectCanCollide = true
	local ground = Workspace:Raycast(pose.Position + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	if
		ground
		and ground.Material ~= Enum.Material.Water
		and ground.Normal.Y >= 0.98
		and (ground.Instance:IsA("Terrain") or (ground.Instance:IsA("BasePart") and ground.Instance.Anchored))
	then
		state.LastSupportedPose, state.LastSupportedBounds = pose, state.LastBounds
	end
end

function CartCargoService:PrepareCartRemoval(cart: Model): (boolean, string?)
	local state = cargoByCart[cart]
	if not state then
		return true, nil
	end
	if state.ResetPreservation then
		local owner = Players:GetPlayerByUserId(cart:GetAttribute("OwnerUserId") or 0)
		if owner then
			return false, "RESET_CARGO_PRESERVED"
		end
		-- A genuine logout follows the ordinary departure policy; reset is not offline insurance.
		state.ResetPreservation = nil
	end
	pcall(rememberCartPose, cart, state)
	-- Snapshot all records before releasing this owner's table. No clones/yields
	-- here: a Destroying callback can run after descendant geometry disappeared.
	local records = table.clone(state.Entries)
	if state.Transfer then
		table.insert(records, state.Transfer.Entry)
	end
	if state.DepartureTransfer then
		for _, removed in state.DepartureTransfer.Entries do
			table.insert(records, removed.Entry)
		end
	end
	local releasePose = state.LastPose
	-- Preflight every counted source before any pending destination changes.
	-- QueueFreshRelease is a synchronous table-only handoff after this proof.
	for _, entry in records do
		if
			Phase10.Enabled
			and isFresh(entry, cart:GetAttribute("OwnerUserId"))
			and World.HasOrdinaryReservation(entry.ItemId)
		then
			local valid, reason = World.CanQueueFreshRelease(entry, releasePose)
			if not valid then
				return false, reason
			end
		end
	end
	for _, entry in records do
		if
			Phase10.Enabled
			and isFresh(entry, cart:GetAttribute("OwnerUserId"))
			and World.HasOrdinaryReservation(entry.ItemId)
		then
			assert(World.QueueFreshRelease(entry, releasePose))
		elseif not pendingReturns[entry.ItemId] then
			pendingReturns[entry.ItemId] = {
				Record = entry,
				Pose = if Phase10.Enabled then state.LastPose else state.LastSupportedPose or state.LastPose,
				Bounds = state.LastSupportedBounds or state.LastBounds,
				RetryAt = 0,
			}
		end
	end
	cargoByCart[cart] = nil
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	Trace.Forget(cart)
	return true, nil
end

-- Character departure keeps the cart and every protected banked slot. Fresh
-- individuals move to the existing counted local-release queue exactly once.
function CartCargoService:ReleaseFreshForCharacterDeparture(cart: Model): (boolean, string?, number)
	if not Phase10.Enabled then
		return false, "PHASE10_DISABLED", 0
	end
	local state = cargoByCart[cart]
	if not state then
		return true, nil, 0
	end
	if state.ResetPreservation then
		return true, nil, 0
	end
	if state.Transfer or state.Insertion or state.DepartureTransfer then
		return false, "BUSY", 0
	end
	local releasePose = cart:GetPivot()
	local fresh = {}
	local ownerId = cart:GetAttribute("OwnerUserId")
	for _, entry in state.Entries do
		if isFresh(entry, ownerId) and World.HasOrdinaryReservation(entry.ItemId) then
			local valid, reason = World.CanQueueFreshRelease(entry, releasePose)
			if not valid then
				return false, reason, 0
			end
			table.insert(fresh, entry)
		end
	end
	local released = 0
	for _, entry in fresh do
		local token, reason = self:DetachSlotForTransfer(cart, "Slot" .. entry.AttachmentIndex, entry.ItemId)
		if not token then
			return false, reason, released
		end
		-- This queue handoff is synchronous and table-only. A failed handoff
		-- restores the exact source record, slot, order, visual and revision.
		local called, queued, failure = pcall(World.QueueFreshRelease, entry, releasePose, cart)
		if not called or not queued then
			assert(self:RestoreTransfer(cart, token), "Character cargo release rollback failed")
			return false, if called then failure else tostring(queued), released
		end
		local finalized, presentationReason = self:FinalizeTransfer(cart, token)
		assert(finalized, "Queued character cargo release could not finalize")
		if presentationReason then
			warn("[CargoDeparture] Presentation: " .. presentationReason)
		end
		released += 1
	end
	return true, nil, released
end

function CartCargoService:ProcessPendingReturns()
	if Phase10.Enabled then
		World.ProcessPendingFreshReleases()
	end
	for id, pending in pendingReturns do
		if pending.Busy or os.clock() < pending.RetryAt then
			continue
		end
		pending.Busy = true
		local reason
		local ok, failure = pcall(function()
			if not pending.Pose then
				reason = "NO_LAST_POSE"
				return
			end
			if not pending.Prepared then
				pending.Record = withWorldContext(pending.Record, pending.Pose)
				pending.Prepared, reason = World.PrepareWorldRepresentation(pending.Record, pending.Pose)
			end
			if not pending.Prepared then
				return
			end
			local pose = World.FindSafeReleasePose(pending.Prepared, pending.Pose, {}, false, nil, pending.Bounds)
			if not pose then
				reason = "NO_SAFE_POSE"
				return
			end
			pending.Prepared.Model:PivotTo(pose)
			local _, activationReason = World.ActivatePreparedWorld(pending.Prepared, function()
				if pendingReturns[id] ~= pending then
					return false
				end
				pendingReturns[id] = nil -- Same-ID custody changes before world publication.
				return true
			end)
			reason = activationReason
		end)
		pending.Busy = false
		if pendingReturns[id] ~= pending then
			print("[CargoReturn] Restored " .. id .. " " .. pending.Record.BrainrotId)
			continue -- Post-commit errors must not replay or delete the living model.
		end
		local errorText = tostring(if ok then reason else failure)
		if pending.Prepared and errorText ~= "NO_SAFE_POSE" then
			World.DiscardPreparedWorld(pending.Prepared)
			pending.Prepared = nil
		end
		pending.RetryAt = os.clock() + 1
		if pending.LastError ~= errorText then
			pending.LastError = errorText
			warn("[CargoReturn] Pending " .. id .. ": " .. errorText)
		end
	end
end

function CartCargoService:GetRemovalDiagnostics()
	local ids = {}
	for id in pendingReturns do
		table.insert(ids, id)
	end
	if Phase10.Enabled then
		for _, pending in World.GetPopulationSnapshot().PendingWorldRecords do
			if not table.find(ids, pending.ItemId) then
				table.insert(ids, pending.ItemId)
			end
		end
	end
	table.sort(ids)
	return table.freeze({ PendingIds = table.freeze(ids), SharedHeartbeat = started })
end

-- Exact fixture-owned teardown seam. A failed Studio test can stop between
-- PrepareCartRemoval and publication; without cancelling that one item, the
-- shared heartbeat can publish it into the next fixture's fixed world corridor.
-- Live gameplay cannot call this boundary.
function CartCargoService:CancelPendingReturnForTesting(itemId: string): (boolean, string?)
	if not RunService:IsStudio() then
		return false, "STUDIO_ONLY"
	end
	local pending = pendingReturns[itemId]
	if pending == nil then
		return false, "NOT_PENDING"
	end
	pendingReturns[itemId] = nil
	if pending.Prepared ~= nil then
		World.DiscardPreparedWorld(pending.Prepared)
		pending.Prepared = nil
	end
	return true, nil
end

-- Metadata is plain bounded item data, not a visual/Instance or a container location.
local function copyMetadata(source: { [any]: any }, freeze: boolean?, ancestors: any?): any
	local seen = ancestors or {}
	assert(not seen[source], "Cyclic cargo metadata")
	seen[source] = true
	local result = {}
	for key, value in source do
		if type(key) == "string" or type(key) == "number" then
			local kind = typeof(value)
			if kind == "table" then
				result[key] = copyMetadata(value, freeze, seen)
			elseif kind == "string" or kind == "number" or kind == "boolean" then
				result[key] = value
			end
		end
	end
	seen[source] = nil
	return if freeze then table.freeze(result) else result
end

local function getBrainrotTemplate(brainrotId: string): Model?
	return CreatureAssets.GetTemplate(brainrotId)
end

local function getAuthoredCargoSlot(cart: Model, index: number): (BasePart?, CFrame?, Attachment?)
	local slot = CartAssetValidator.GetCargoSlot(cart, index)
	if slot then
		return slot.Part, slot.Attachment.WorldCFrame, slot.Attachment
	end
	return nil, nil
end

local function getCargoSlot(cart: Model, index: number): (BasePart?, CFrame?, Attachment?)
	local readiness = CartCargoService:GetCargoCapacityReadiness(cart)
	if
		readiness.status ~= "Ready"
		or type(readiness.effectiveCapacity) ~= "number"
		or index > readiness.effectiveCapacity
	then
		return nil, nil
	end
	return getAuthoredCargoSlot(cart, index)
end

local function getCargoVisualContainer(cart: Model): Folder
	local existing = cart:FindFirstChild("CargoVisuals")
	if existing then
		assert(existing:IsA("Folder"), "CargoVisuals must be a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "CargoVisuals"
	folder.Parent = cart
	return folder
end

local function getCargoVisualRoot(visual: Model): BasePart?
	if visual.PrimaryPart then
		return visual.PrimaryPart
	end
	local body = visual:FindFirstChild("Body", true)
	return if body and body:IsA("BasePart") then body else visual:FindFirstChildWhichIsA("BasePart", true)
end

-- Shared canonical, synchronous clone path for cargo and base displays.
-- No source model is moved; joints to external assemblies are discarded before parenting.
function CartCargoService:CreateItemVisual(brainrotId: string): Model?
	local template = getBrainrotTemplate(brainrotId)
	if template == nil then
		return nil
	end
	Trace.Emit("5C", "asset_clone_enter", { species = brainrotId, template = template })
	local visual = CreatureAssets.CreateProxy(brainrotId)
	Trace.Emit("5C", "asset_clone_exit", {
		species = brainrotId,
		clone = visual or "none",
		result = if visual then "cloned" else "INVALID_ASSET",
	}, visual == nil)
	if visual == nil then
		return nil
	end
	local ok, failure = pcall(function()
		local function outside(instance: Instance?): boolean
			return instance ~= nil and not instance:IsDescendantOf(visual)
		end
		local descendants = visual:GetDescendants()
		table.insert(descendants, visual)
		for _, instance in descendants do
			for _, tag in CollectionService:GetTags(instance) do
				CollectionService:RemoveTag(instance, tag)
			end
			if instance:IsA("LuaSourceContainer") then
				instance:Destroy()
			elseif
				instance:IsA("JointInstance")
				or instance:IsA("WeldConstraint")
				or instance:IsA("NoCollisionConstraint")
			then
				if outside(instance.Part0) or outside(instance.Part1) then
					Trace.Emit("5C", "external_joint_found", {
						joint = instance,
						part0 = instance.Part0 or "none",
						part1 = instance.Part1 or "none",
						action = "existing_preparation_removes_joint",
					})
					instance:Destroy()
				end
			elseif instance:IsA("Constraint") then
				if outside(instance.Attachment0) or outside(instance.Attachment1) then
					Trace.Emit("5C", "external_constraint_found", {
						constraint = instance,
						action = "existing_preparation_removes_constraint",
					})
					instance:Destroy()
				end
			end
		end
		assert(getCargoVisualRoot(visual), "Brainrot visual has no BasePart")
		visual:SetAttribute("Captured", nil)
		local scaled, _, scaleReason = BrainrotVisualScale.ApplyCanonicalScale(visual, "LightweightVisual")
		assert(scaled, scaleReason)
	end)
	if not ok then
		Trace.Emit("5C", "asset_prepare_error", { error = tostring(failure), species = brainrotId }, true)
		visual:Destroy()
		warn(string.format("[Cargo] Visual preparation failed for %s: %s", brainrotId, tostring(failure)))
		return nil
	end
	return visual
end

local function prepareCargoVisual(entry: CargoEntry): any?
	local visual = CartCargoService:CreateItemVisual(entry.BrainrotId)
	if visual == nil then
		return nil
	end
	local ok, failure = pcall(function()
		visual.Name = string.format("CargoVisual_%d_%s", entry.AttachmentIndex, entry.BrainrotId)
		visual:SetAttribute("ItemId", entry.ItemId)
		visual:SetAttribute("BrainrotId", entry.BrainrotId)
		visual:SetAttribute("Captured", true)
		visual:SetAttribute("Phase10TargetKind", if Phase10.Enabled then "Cargo" else nil)
		visual:SetAttribute("Phase10Banked", not isFresh(entry, nil))
		visual:SetAttribute("AttachmentIndex", entry.AttachmentIndex)
		BrainrotDisplayMetadata.SetIdentity(visual, entry)
		local root = getCargoVisualRoot(visual) :: BasePart
		-- Cargo is a rigid, inert presentation, never world AI or an avatar rig.
		-- Keep this sanitisation out of the shared factory used by banked displays.
		for _, item in visual:GetDescendants() do
			if
				item:IsA("JointInstance")
				or item:IsA("WeldConstraint")
				or item:IsA("Constraint")
				or item:IsA("BodyMover")
				or item:IsA("Humanoid")
				or item:IsA("Animator")
				or item:IsA("AnimationController")
				or item:IsA("ProximityPrompt")
				or item:IsA("ClickDetector")
				or item:IsA("Beam")
				or item:IsA("Trail")
				or item:IsA("ParticleEmitter")
				or item:IsA("Sound")
			then
				item:Destroy()
			end
		end
		for _, part in visual:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = Phase10.Enabled and part.Name == "Body"
				part.Massless = true
				part.RootPriority = -127 -- Visual only; never alter the chassis priority.
				if part ~= root then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = part
					weld.Parent = root
				end
			end
		end
		CollisionService:SetModelCollisionGroup(visual, CollisionGroups.Carts)
		local mount = Instance.new("WeldConstraint")
		mount.Name, mount.Enabled, mount.Part1, mount.Parent = "CargoMount", false, root, root
	end)
	if not ok then
		visual:Destroy()
		warn("[Cargo] Mount failed: " .. tostring(failure))
		return nil
	end
	local root = getCargoVisualRoot(visual) :: BasePart
	return { Model = visual, Root = root, Mount = root:FindFirstChild("CargoMount"), Record = entry }
end

-- A synchronous physical change is one existing assembly mutation, including
-- rollback. Never leave validation suppressed across a yield/ownership commit.
local function mutateCargoVisual(cart: Model, action: () -> ())
	if AssemblyValidation:GetState(cart) == nil then
		action() -- Unregistered isolated factories/tests retain their existing path.
		return
	end
	local accepted, revision, reason = AssemblyValidation:BeginMutation(cart, "cargo visual")
	assert(accepted and revision, reason or "Cart assembly is not ready")
	local ok, failure = pcall(action)
	local valid, _, validationReason =
		AssemblyValidation:CompleteMutation(cart, revision :: number, "Runtime", "cargo visual")
	assert(ok, tostring(failure))
	assert(valid, validationReason or "Cargo assembly validation failed")
end

local function destroyCargoVisual(cart: Model, visual: Model)
	if visual:IsDescendantOf(cart) and AssemblyValidation:GetState(cart) == "Valid" then
		mutateCargoVisual(cart, function()
			visual:Destroy()
		end)
	else
		visual:Destroy() -- Cleanup must remain possible during cart teardown.
	end
end

local function mountCargoVisual(prepared: any, slot: BasePart, frame: CFrame, container: Folder)
	-- Re-read the moving attachment at commit. Position before joining assemblies;
	-- never anchor, PivotTo or zero velocities on a model already welded to a cart.
	mutateCargoVisual(container.Parent :: Model, function()
		local ok, failure = pcall(function()
			prepared.Model:PivotTo(frame)
			prepared.Model:SetAttribute("Phase10CartId", container.Parent:GetAttribute("CartId"))
			prepared.Model:SetAttribute("OwnerUserId", container.Parent:GetAttribute("OwnerUserId"))
			prepared.Model:SetAttribute(
				"Phase10Banked",
				not isFresh(prepared.Record, container.Parent:GetAttribute("OwnerUserId"))
			)
			prepared.Model.Parent = container
			prepared.Mount.Part0 = slot
			prepared.Mount.Enabled = true
		end)
		if not ok then
			prepared.Model:Destroy()
			error(tostring(failure))
		end
	end)
end

local function createCargoVisual(cart: Model, entry: CargoEntry): Model?
	-- Existing cargo remains representable for removal even if a later config or
	-- applicability change makes its slot admission-inactive.
	local slot, frame = getAuthoredCargoSlot(cart, entry.AttachmentIndex)
	if not slot or not frame then
		return nil
	end
	local prepared = prepareCargoVisual(entry)
	if not prepared then
		return nil
	end
	local ok, failure = pcall(function()
		mountCargoVisual(prepared, slot, frame, getCargoVisualContainer(cart))
	end)
	if not ok then
		prepared.Model:Destroy()
		warn("[Cargo] Mount failed: " .. tostring(failure))
		return nil
	end
	BrainrotDisplayMetadata.Apply(prepared.Model, entry, BrainrotDisplayConfig.States.Cart, nil)
	return prepared.Model
end

local function getOrCreateCargo(cart: Model): any
	local state = cargoByCart[cart]
	if state == nil then
		state = {
			Entries = {},
			ById = {},
			Occupancy = {},
			Visuals = {},
			Revision = 0,
			Transfer = nil,
			DepartureTransfer = nil,
			Insertion = nil,
			Connections = {},
		}
		cargoByCart[cart] = state
		rememberCartPose(cart, state)
		table.insert(
			state.Connections,
			cart.Destroying:Connect(function()
				CartCargoService:PrepareCartRemoval(cart)
			end)
		)
		table.insert(
			state.Connections,
			cart.AncestryChanged:Connect(function()
				if not cart:IsDescendantOf(Workspace) then
					CartCargoService:PrepareCartRemoval(cart)
				end
			end)
		)
	end
	return state
end

local function reconcileFullCargoLayout(cart, state)
	local G = require(ReplicatedStorage.Shared.Utility.WorldPresentationGeometry)
	local config = require(ReplicatedStorage.Shared.Config.PlaytestExact).Cargo
	local metadata = require(ReplicatedStorage.Shared.Config.PlaytestPresentationMetadata)
	local geometry = G.Cart(cart:GetAttribute("CartId"))
	if not geometry or not cart.PrimaryPart then
		return
	end
	local folder = cart:FindFirstChild("CargoVisuals")
	if not folder then
		return
	end
	local entries = {}
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and type(m:GetAttribute("AttachmentIndex")) == "number" then
			table.insert(
				entries,
				{ speciesId = m:GetAttribute("BrainrotId"), index = m:GetAttribute("AttachmentIndex"), model = m }
			)
		end
	end
	table.sort(entries, function(a, b)
		return a.index < b.index
	end)
	local signature = tostring(cart:GetAttribute("CargoCapacity"))
	for _, e in entries do
		signature ..= ":" .. tostring(e.model:GetAttribute("ItemId")) .. ":" .. tostring(e.model:GetScale())
	end
	if state.PresentationLayoutSignature == signature then
		return
	end
	local rear = geometry.DriverSeat.Frame.Z + metadata.SeatedBodyRearFromSeat
	local deck, authoredDeck
	for _, v in geometry.Colliders do
		if v.Name == "RearDeck" then
			deck = v.Frame.Y + v.Size.Y / 2
			authoredDeck = v
		end
	end
	assert(deck, "Authored rear deck measurement missing")
	local poses, lo, hi = G.Layout(entries, 2, false, rear, deck)
	local columns = 2
	if
		#entries > 0
		and 2 * math.max(math.abs(lo.X), math.abs(hi.X), geometry.VisualBounds.Size.X / 2)
				+ 2 * config.RequiredRouteSideClearanceStuds
			> metadata.Route.MinimumStraightClearWidth
	then
		columns = 1
		poses, lo, hi = G.Layout(entries, 1, false, rear, deck)
	end
	mutateCargoVisual(cart, function()
		for i, e in entries do
			local mount = e.model:FindFirstChild("CargoMount", true)
			if mount and mount:IsA("WeldConstraint") then
				mount.Enabled = false
				e.model:PivotTo(cart.PrimaryPart.CFrame * poses[i].pivot)
				mount.Enabled = true
				e.model:SetAttribute("CargoComputedLocalTarget", poses[i].pivot)
			end
		end
		local rack = cart:FindFirstChild("FullSizeCosmeticCargoDeck")
		if #entries == 0 then
			if rack then
				rack:Destroy()
			end
			cart:SetAttribute("CargoPresentationBoundsMin", nil)
			cart:SetAttribute("CargoPresentationBoundsMax", nil)
		else
			if rack then
				rack:Destroy()
			end
			rack = Instance.new("Folder")
			rack.Name = "FullSizeCosmeticCargoDeck"
			rack.Parent = cart
			local left, right = lo.X - config.RackEdgePaddingStuds, hi.X + config.RackEdgePaddingStuds
			local front, back = lo.Z - config.RackEdgePaddingStuds, hi.Z + config.RackEdgePaddingStuds
			local oldLeft = authoredDeck.Frame.X - authoredDeck.Size.X / 2
			local oldRight = authoredDeck.Frame.X + authoredDeck.Size.X / 2
			local oldFront = authoredDeck.Frame.Z - authoredDeck.Size.Z / 2
			local oldBack = authoredDeck.Frame.Z + authoredDeck.Size.Z / 2
			-- Extend around the authored deck; never put a second coplanar skin over it.
			local spans = {
				{ left, math.min(right, oldLeft), front, back },
				{ math.max(left, oldRight), right, front, back },
				{ math.max(left, oldLeft), math.min(right, oldRight), front, math.min(back, oldFront) },
				{ math.max(left, oldLeft), math.min(right, oldRight), math.max(front, oldBack), back },
			}
			for i, span in spans do
				local x0, x1, z0, z1 = table.unpack(span)
				if x1 > x0 and z1 > z0 then
					local part = Instance.new("Part")
					part.Name = "Extension_" .. i
					part.Anchored = false
					part.CanCollide = false
					part.CanTouch = false
					part.CanQuery = false
					part.Massless = true
					part.CollisionGroup = cart.PrimaryPart.CollisionGroup
					part.CastShadow = false
					part.RootPriority = -127
					part.Color = cart.PrimaryPart.Color
					part.Material = cart.PrimaryPart.Material
					part.Size = Vector3.new(x1 - x0, config.RackDeckThicknessStuds, z1 - z0)
					part.CFrame = cart.PrimaryPart.CFrame
						* CFrame.new((x0 + x1) / 2, deck - config.RackDeckThicknessStuds / 2, (z0 + z1) / 2)
					local weld = Instance.new("WeldConstraint")
					weld.Name = "RackMount"
					weld.Part0 = cart.PrimaryPart
					weld.Part1 = part
					weld.Parent = part
					part.Parent = rack
				end
			end
			cart:SetAttribute("CargoPresentationBoundsMin", lo)
			cart:SetAttribute("CargoPresentationBoundsMax", hi)
		end
	end)
	state.PresentationLayoutSignature = signature
	cart:SetAttribute("CargoPresentationFormation", if columns == 2 then "A" else "B")
end
local function updateCargoAttributes(cart: Model, state: any)
	if cart.Parent ~= nil then
		local readiness = CartCargoService:GetCargoCapacityReadiness(cart)
		local capacity = if type(readiness.effectiveCapacity) == "number" then readiness.effectiveCapacity else 0
		local signature = table.concat({
			tostring(readiness.status),
			tostring(readiness.code),
			tostring(readiness.baseCapacity),
			tostring(readiness.upgradeBonus),
			tostring(capacity),
		}, "|")
		if state.CapacitySignature ~= nil and state.CapacitySignature ~= signature then
			state.Revision += 1
		end
		state.CapacitySignature = signature
		cart:SetAttribute("CargoCount", cargoCount(state))
		cart:SetAttribute("CargoBaseCapacity", readiness.baseCapacity)
		cart:SetAttribute("CargoUpgradeBonus", readiness.upgradeBonus)
		cart:SetAttribute("CargoCapacity", capacity)
		cart:SetAttribute("CargoCapacityStatus", readiness.status)
		cart:SetAttribute("CargoLayoutReady", readiness.status == "Ready")
		cart:SetAttribute("CargoRevision", state.Revision)
		local layoutOk, layoutError = pcall(reconcileFullCargoLayout, cart, state)
		if not layoutOk then
			warn("[Cargo] Full-size presentation reconcile: " .. tostring(layoutError))
		end

		local folder = cart:FindFirstChild("CargoSlots")
		for _, child in if folder and folder:IsA("Folder") then folder:GetChildren() else {} do
			if not child:IsA("BasePart") then
				continue
			end
			local index = tonumber(child.Name:match("^Slot([1-9]%d*)$"))
			if index == nil then
				continue
			end
			local enabled = readiness.status == "Ready" and index <= capacity
			local occupiedId = state.Occupancy[index]
			local removalOnly = not enabled and occupiedId ~= nil
			child:SetAttribute("CargoSlotId", "Slot" .. index)
			child:SetAttribute("CargoSlotEnabled", enabled)
			child:SetAttribute("CargoRemovalOnly", removalOnly)
			child:SetAttribute("CargoOccupied", occupiedId ~= nil)
			child:SetAttribute("CargoItemId", occupiedId)
			local occupant = state.ById[occupiedId]
			child:SetAttribute("CargoBrainrotId", if occupant then occupant.BrainrotId else nil)
			if enabled or removalOnly then
				CollectionService:AddTag(child, CARGO_SLOT_TAG) -- UI hints, not authority.
			elseif CollectionService:HasTag(child, CARGO_SLOT_TAG) then
				CollectionService:RemoveTag(child, CARGO_SLOT_TAG)
			end
		end
		if readiness.status == "LayoutNotReady" and state.LastLayoutWarning ~= signature then
			state.LastLayoutWarning = signature
			warn("[Cargo] Layout not ready " .. cart:GetFullName())
		end
	end
end

function CartCargoService:ReconcileCargoCapacity(cart: Model, _reason: string?): any
	local state = getOrCreateCargo(cart)
	updateCargoAttributes(cart, state)
	return self:GetCargoCapacityReadiness(cart)
end

function CartCargoService:ReconcileOwnerCapacity(ownerUserId: number, reason: string?): any?
	local record = CartService:GetCartRecordByOwnerUserId(ownerUserId)
	if record == nil or record.Model == nil then
		return nil
	end
	return self:ReconcileCargoCapacity(record.Model, reason)
end

local function ensureStarted()
	if started then
		return
	end
	started = true
	CartService:SetCargoRemovalHandler(function(cart)
		return CartCargoService:PrepareCartRemoval(cart)
	end)
	CartService.CartSpawned:Connect(function(record)
		updateCargoAttributes(record.Model, getOrCreateCargo(record.Model))
	end)
	CartService.CartDespawned:Connect(function(record)
		CartCargoService:PrepareCartRemoval(record.Model) -- Idempotent fallback.
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		for cart, state in cargoByCart do
			if cargoCount(state) > 0 then
				pcall(rememberCartPose, cart, state)
			end
		end
		CartCargoService:ProcessPendingReturns()
	end)
	for _, record in CartService:GetCartRecords() do
		updateCargoAttributes(record.Model, getOrCreateCargo(record.Model))
	end
end

local function freeAttachment(cart: Model, state: any): number?
	if state.Transfer ~= nil or state.Insertion ~= nil then
		return nil
	end
	for index = 1, CartCargoService:GetCargoCapacity(cart) do
		if state.Occupancy[index] == nil and getCargoSlot(cart, index) ~= nil then
			return index
		end
	end
	return nil
end

function CartCargoService:AddCargo(cart: Model, brainrotId: string, metadata: { [string]: any }?): CargoEntry?
	ensureStarted()
	if cart.Parent == nil or brainrotId == "" then
		return nil
	end
	local state = getOrCreateCargo(cart)
	local index = freeAttachment(cart, state)
	if index == nil or cargoCount(state) >= self:GetCargoCapacity(cart) then
		warn("[Cargo] Cannot add cargo: no free cargo attachment")
		return nil
	end
	local itemMetadata = copyMetadata(metadata or {}, true)
	local entry: CargoEntry = withWorldContext(
		table.freeze({
			ItemId = HttpService:GenerateGUID(false),
			BrainrotId = brainrotId,
			Metadata = itemMetadata,
			AttachmentIndex = index,
		}),
		cart:GetPivot()
	)
	table.insert(state.Entries, entry)
	state.ById[entry.ItemId] = entry
	state.Occupancy[index] = entry.ItemId
	state.Revision += 1
	updateCargoAttributes(cart, state)
	state.Visuals[entry.ItemId] = createCargoVisual(cart, entry)
	print(string.format("[Cargo] Added %s to cart %s", brainrotId, tostring(cart:GetAttribute("CartId"))))
	Trace.Emit("5C", "cargo_added", function()
		return {
			cartId = cart:GetAttribute("CartId"),
			cart = cart,
			itemId = entry.ItemId,
			species = brainrotId,
			attachment = index,
			cargoRevision = state.Revision,
			cargoCount = cargoCount(state),
			visual = state.Visuals[entry.ItemId] or "none",
		}
	end)
	return entry
end

-- The existing visible torso is the sole inexpensive cargo ray target.
-- Attributes are hints; exact current table/visual/container identity is authority.
function CartCargoService:ResolveHit(part: Instance): any?
	if not Phase10.Enabled then
		return nil
	end
	local visual: Instance? = part
	while visual and visual ~= Workspace do
		if visual:IsA("Model") and visual:GetAttribute("Phase10TargetKind") == "Cargo" then
			break
		end
		visual = visual.Parent
	end
	if not visual or not visual:IsA("Model") then
		return nil
	end
	local folder = visual.Parent
	local cart = folder and folder.Parent
	if not cart or not cart:IsA("Model") then
		return nil
	end
	local state = cargoByCart[cart]
	local id = visual:GetAttribute("ItemId")
	local entry = state and state.ById[id]
	if not entry or state.Visuals[id] ~= visual or state.Occupancy[entry.AttachmentIndex] ~= id then
		return nil
	end
	return {
		Cart = cart,
		Record = entry,
		Visual = visual,
		Revision = state.Revision,
		Fresh = isFresh(entry, cart:GetAttribute("OwnerUserId")),
	}
end

function CartCargoService:GetCargoItem(cart: Model, itemId: string): CargoEntry?
	local state = cargoByCart[cart]
	return if state then state.ById[itemId] else nil
end

local function slotIndex(cart: Model, slotId: any): number?
	if type(slotId) ~= "string" or #slotId > 16 then
		return nil
	end
	local index = tonumber(slotId:match("^Slot([1-9]%d*)$"))
	return if index and index <= CartCargoService:GetCargoCapacity(cart) then index else nil
end

local function authoredSlotIndex(cart: Model, slotId: any): number?
	if type(slotId) ~= "string" or #slotId > 16 then
		return nil
	end
	local index = tonumber(slotId:match("^Slot([1-9]%d*)$"))
	return if index and CartAssetValidator.GetCargoSlot(cart, index) ~= nil then index else nil
end

local function currentCart(cart: any): boolean
	if
		typeof(cart) ~= "Instance"
		or not cart:IsA("Model")
		or not cart:IsDescendantOf(Workspace)
		or cart:GetAttribute("RuntimeCart") ~= true
	then
		return false
	end
	local ownerId = cart:GetAttribute("OwnerUserId")
	if type(ownerId) ~= "number" then
		return false
	end
	local record = CartService:GetCartRecordByOwnerUserId(ownerId)
	return record ~= nil and record.Model == cart and record.OwnerUserId == ownerId
end

function CartCargoService:CanPlayerHandleCargo(player: Player, cart: any): boolean
	-- Same authoritative owner/current-cart policy as the existing cargo transfer.
	if player.Parent ~= Players or not currentCart(cart) then
		return false
	end
	local record = CartService:GetCartRecordByOwnerUserId(player.UserId)
	return record ~= nil
		and record.Model == cart
		and record.OwnerUserId == player.UserId
		and CartService:GetCart(player) == cart
end

function CartCargoService:ResolveCargoSlot(cart: any, slotId: any): (BasePart?, Attachment?)
	if not currentCart(cart) then
		return nil, nil
	end
	local index = slotIndex(cart, slotId)
	if not index then
		return nil, nil
	end
	local slot, _, attachment = getCargoSlot(cart, index)
	return slot, attachment
end

-- Removal may target an already-occupied authored slot that is no longer enabled
-- for admission. This does not make the slot loadable or replaceable.
function CartCargoService:ResolveStoredCargoSlot(cart: any, slotId: any): (BasePart?, Attachment?)
	if not currentCart(cart) then
		return nil, nil
	end
	local index = authoredSlotIndex(cart, slotId)
	local state = if index then cargoByCart[cart] else nil
	if index == nil or state == nil or state.Occupancy[index] == nil then
		return nil, nil
	end
	local slot, _, attachment = getAuthoredCargoSlot(cart, index)
	return slot, attachment
end

function CartCargoService:GetSlotRecord(cart: Model, slotId: any): CargoEntry?
	local index = authoredSlotIndex(cart, slotId)
	local state = cargoByCart[cart]
	local id = if index and state then state.Occupancy[index] else nil
	return if id then state.ById[id] else nil
end

function CartCargoService:CanReplaceCargo(cart: Model): (boolean, string?)
	local map = CartAssetValidator.GetCargoSlotMap(cart, self:GetCargoCapacity(cart))
	if not map then
		return false, "INVALID_SLOT_MAP"
	end
	for _, slot in map do
		if not self:GetSlotRecord(cart, slot.Id) then
			return false, "EMPTY_SLOT_AVAILABLE"
		end
	end
	return true, nil
end

local function canInsert(cart: any, slotId: any, record: any, token: any?, old: CargoEntry?): (boolean, string?)
	local slot = CartCargoService:ResolveCargoSlot(cart, slotId)
	if not slot then
		return false, "INVALID_SLOT"
	end
	if
		type(record) ~= "table"
		or type(record.ItemId) ~= "string"
		or record.ItemId == ""
		or type(record.BrainrotId) ~= "string"
		or record.BrainrotId == ""
		or type(record.Metadata) ~= "table"
	then
		return false, "INVALID_RECORD"
	end
	local state = cargoByCart[cart]
	if state then
		if state.Transfer or (state.Insertion and state.Insertion ~= token) then
			return false, "BUSY"
		end
		if state.ById[record.ItemId] then
			return false, "ALREADY_STORED"
		end
		if old then
			local full, reason = CartCargoService:CanReplaceCargo(cart)
			if not full then
				return false, reason
			end
			if state.ById[old.ItemId] ~= old or state.Occupancy[slotIndex(cart, slotId)] ~= old.ItemId then
				return false, "STALE_ID"
			end
		elseif state.Occupancy[slotIndex(cart, slotId)] then
			return false, "OCCUPIED"
		end
		if not old and cargoCount(state) >= CartCargoService:GetCargoCapacity(cart) then
			return false, "NO_SPACE"
		end
	end
	return true, nil
end

function CartCargoService:CanInsertAtSlot(cart: any, slotId: any, record: any): (boolean, string?)
	return canInsert(cart, slotId, record, nil)
end

local function prepareSlotChange(player: Player, cart: any, slotId: any, record: any, old: CargoEntry?): (any?, string?)
	if not CartCargoService:CanPlayerHandleCargo(player, cart) then
		return nil, "NOT_OWNER"
	end
	local valid, reason = canInsert(cart, slotId, record, nil, old)
	if not valid then
		return nil, reason
	end
	local state = getOrCreateCargo(cart)
	local slot, attachment = CartCargoService:ResolveCargoSlot(cart, slotId)
	local token = table.freeze({})
	local stage = {
		Player = player,
		Cart = cart,
		SlotId = slotId,
		Slot = slot,
		Attachment = attachment,
		State = state,
		Committed = false,
		OldEntry = old,
		OldVisual = if old then state.Visuals[old.ItemId] else nil,
	}
	preparedInsertions[token], state.Insertion = stage, token
	local ok, failure = pcall(function()
		-- Keep the entire individual, including World restoration fields. Only its
		-- container-local slot changes; never reconstruct an individual from species.
		local entry = table.clone(copyMetadata(record, true))
		entry.AttachmentIndex = slotIndex(cart, slotId)
		stage.Entry = table.freeze(entry)
		stage.Visual = prepareCargoVisual(stage.Entry)
		assert(stage.Visual, "Cargo display unavailable")
		stage.Container = getCargoVisualContainer(cart)
	end)
	if not ok then
		CartCargoService:FinishInsertAtSlot(token)
		warn("[Cargo] Load preparation failed: " .. tostring(failure))
		return nil, "PREPARATION_FAILED"
	end
	return token, nil
end

function CartCargoService:PrepareInsertAtSlot(player: Player, cart: any, slotId: any, record: any): (any?, string?)
	return prepareSlotChange(player, cart, slotId, record, nil)
end

function CartCargoService:PrepareReplaceAtSlot(
	player: Player,
	cart: any,
	slotId: any,
	expectedOldId: any,
	record: any
): (any?, string?)
	if not self:CanPlayerHandleCargo(player, cart) or not self:ResolveCargoSlot(cart, slotId) then
		return nil, "NOT_OWNER"
	end
	local old = self:GetSlotRecord(cart, slotId)
	if not old or old.ItemId ~= expectedOldId then
		return nil, "STALE_ID"
	end
	return prepareSlotChange(player, cart, slotId, record, old)
end

local function validatePreparedChange(token: any): (any?, string?)
	local stage = preparedInsertions[token]
	if not stage or stage.Committed then
		return nil, "INVALID_CONTEXT"
	end
	local cart, state = stage.Cart, stage.State
	if
		cargoByCart[cart] ~= state
		or state.Insertion ~= token
		or not CartCargoService:CanPlayerHandleCargo(stage.Player, cart)
	then
		return nil, "INVALID_CONTEXT"
	end
	local valid, reason = canInsert(cart, stage.SlotId, stage.Entry, token, stage.OldEntry)
	if not valid then
		return nil, reason
	end
	local slot, attachment = CartCargoService:ResolveCargoSlot(cart, stage.SlotId)
	if slot ~= stage.Slot or attachment ~= stage.Attachment or stage.Container.Parent ~= cart then
		return nil, "INVALID_SLOT"
	end
	return stage, nil
end

-- Mount only the NEW inert display before compare-and-replace. Rollback may
-- discard this staging; the old slot display is never moved/anchored/detached.
function CartCargoService:MountPreparedReplacement(token: any): (boolean, string?)
	local stage, reason = validatePreparedChange(token)
	if not stage or not stage.OldEntry or stage.Mounted then
		return false, reason or "INVALID_CONTEXT"
	end
	local ok = pcall(mountCargoVisual, stage.Visual, stage.Slot, stage.Attachment.WorldCFrame, stage.Container)
	stage.Mounted = ok
	if ok and stage.OldVisual then
		BrainrotDisplayMetadata.Clear(stage.OldVisual)
	end
	return ok, if ok then nil else "MOUNT_FAILED"
end

-- Pure ownership mutation: no count notifications, Instance writes or yields.
-- The world owner invokes this immediately before publishing its awake record.
function CartCargoService:CommitReplaceAtSlot(token: any): (boolean, string?)
	local stage, reason = validatePreparedChange(token)
	if not stage or not stage.OldEntry or not stage.Mounted then
		return false, reason or "INVALID_CONTEXT"
	end
	if stage.Visual.Model.Parent ~= stage.Container or not stage.Visual.Mount.Enabled then
		return false, "MOUNT_FAILED"
	end
	local state, old, entry = stage.State, stage.OldEntry, stage.Entry
	local index = table.find(state.Entries, old)
	if not index then
		return false, "STALE_ID"
	end
	state.Entries[index] = entry
	state.ById[old.ItemId], state.Visuals[old.ItemId] = nil, nil
	state.ById[entry.ItemId], state.Occupancy[entry.AttachmentIndex] = entry, entry.ItemId
	state.Visuals[entry.ItemId] = stage.Visual.Model
	state.Revision += 1
	stage.Committed = true
	return true, nil
end

-- Table-only ownership commit after all mounting checks. The interaction owner
-- clears its carried record before Finish publishes count/slot presentation.
function CartCargoService:CommitInsertAtSlot(token: any): (boolean, string?)
	local stage, reason = validatePreparedChange(token)
	if not stage or stage.OldEntry then
		return false, reason or "INVALID_CONTEXT"
	end
	local slot, attachment, state = stage.Slot, stage.Attachment, stage.State
	local ok, failure = pcall(mountCargoVisual, stage.Visual, slot, attachment.WorldCFrame, stage.Container)
	if not ok then
		warn("[Cargo] Load mount failed: " .. tostring(failure))
		return false, "MOUNT_FAILED"
	end
	local entry = stage.Entry
	table.insert(state.Entries, entry)
	state.ById[entry.ItemId], state.Occupancy[entry.AttachmentIndex] = entry, entry.ItemId
	state.Visuals[entry.ItemId] = stage.Visual.Model
	state.Revision += 1
	stage.Committed = true
	return true, nil
end

function CartCargoService:FinishInsertAtSlot(token: any)
	local stage = preparedInsertions[token]
	if not stage then
		return
	end
	preparedInsertions[token] = nil
	local function present(action: () -> ())
		local ok, failure = pcall(action)
		if not ok then
			ok, failure = pcall(action)
		end -- Repair presentation only, never repeat the mutation.
		if not ok then
			warn("[Cargo] Committed=" .. tostring(stage.Committed) .. " presentation: " .. tostring(failure))
		end
	end
	if stage.Committed then
		present(function()
			if stage.OldVisual then
				destroyCargoVisual(stage.Cart, stage.OldVisual)
			end
		end)
		present(function()
			if stage.OldEntry and stage.State.ById[stage.Entry.ItemId] == stage.Entry then
				local visual = stage.State.Visuals[stage.Entry.ItemId]
				if not visual or visual.Parent ~= stage.Container then
					if visual then
						destroyCargoVisual(stage.Cart, visual)
					end
					local repaired = createCargoVisual(stage.Cart, stage.Entry)
					assert(repaired, "Committed cargo display repair failed")
					stage.State.Visuals[stage.Entry.ItemId] = repaired
				end
			end
		end)
		present(function()
			local visual = stage.State.Visuals[stage.Entry.ItemId]
			assert(visual and visual.Parent == stage.Container, "Committed cargo display missing")
			BrainrotDisplayMetadata.Apply(visual, stage.Entry, BrainrotDisplayConfig.States.Cart, nil)
		end)
		present(function()
			updateCargoAttributes(stage.Cart, stage.State)
		end)
	elseif stage.Visual then
		present(function()
			destroyCargoVisual(stage.Cart, stage.Visual.Model)
		end)
		present(function()
			if stage.OldEntry and stage.OldVisual and stage.OldVisual.Parent then
				BrainrotDisplayMetadata.Apply(stage.OldVisual, stage.OldEntry, BrainrotDisplayConfig.States.Cart, nil)
			end
		end)
	end
	if stage.State.Insertion == token then
		stage.State.Insertion = nil
	end
end

-- Diagnostics read the existing bounded records; never take another gameplay snapshot.
function CartCargoService:TraceCargoState(cart: Model)
	Trace.Emit("5C", "batch_cargo", function()
		local state = cargoByCart[cart]
		local items = {}
		for _, entry in if state then state.Entries else {} do
			table.insert(
				items,
				entry.ItemId
					.. ":"
					.. entry.BrainrotId
					.. "@"
					.. entry.AttachmentIndex
					.. if entry.AttachmentIndex > self:GetCargoCapacity(cart) then "!removal" else ""
			)
		end
		return {
			items = table.concat(items, ","),
			cargoCount = state and cargoCount(state) or 0,
			cargoRevision = state and state.Revision or 0,
			transferHeld = state ~= nil and state.Transfer ~= nil,
		}
	end)
end

-- Read-only references for the server handling coordinator. Snapshot revisions
-- are validated immediately before committing through the existing transfer API.
function CartCargoService:GetTransportSources(cart: Model): { any }
	local sources = {}
	local state = cargoByCart[cart]
	if not state then
		return sources
	end
	for _, entry in state.Entries do
		table.insert(sources, {
			Record = entry,
			SlotId = "Slot" .. entry.AttachmentIndex,
			Revision = state.Revision,
			Visual = state.Visuals[entry.ItemId],
			Cart = cart,
			Busy = state.Transfer ~= nil or state.Insertion ~= nil or state.DepartureTransfer ~= nil,
		})
	end
	return sources
end

-- Snapshot only already-committed, valid cargo slots. No yielding between identity
-- validation and the generation fence, so an unfinished insertion cannot gain immunity.
function CartCargoService:BeginResetPreservation(player: Player, cycleId: number): any
	local cart = CartService:GetCart(player)
	local state = cart and cargoByCart[cart]
	if not state then
		return { ok = true, records = {}, cart = cart }
	end
	local previous = state.ResetPreservation
	if previous then
		return if previous.Generation == cycleId
			then { ok = true, records = previous.Records, cart = cart }
			else { ok = false, code = "STALE_RESET" }
	end
	if state.Transfer or state.Insertion or state.DepartureTransfer then
		return { ok = false, code = "BUSY" }
	end
	local records, ids = {}, {}
	for _, entry in state.Entries do
		if isFresh(entry, player.UserId) and World.HasOrdinaryReservation(entry.ItemId) then
			if
				state.Occupancy[entry.AttachmentIndex] ~= entry.ItemId
				or not CartAssetValidator.GetCargoSlot(cart, entry.AttachmentIndex)
			then
				return { ok = false, code = "INVALID_CARGO_SLOT" }
			end
			table.insert(records, entry)
			ids[entry.ItemId] = true
		end
	end
	state.ResetPreservation = { Generation = cycleId, Records = records, Ids = ids, Revision = state.Revision }
	cart:SetAttribute("Phase13CargoResetGeneration", cycleId)
	return { ok = true, records = records, cart = cart, revision = state.Revision }
end
function CartCargoService:EndResetPreservation(player: Player, cycleId: number): boolean
	local cart = CartService:GetCart(player)
	local state = cart and cargoByCart[cart]
	if not state or not state.ResetPreservation then
		return true
	end
	if state.ResetPreservation.Generation ~= cycleId then
		return false
	end
	state.ResetPreservation = nil
	if cart.Parent then
		cart:SetAttribute("Phase13CargoResetGeneration", nil)
	end
	return true
end
function CartCargoService:IsResetPreserved(cart: Model): boolean
	local state = cargoByCart[cart]
	return state ~= nil and state.ResetPreservation ~= nil
end
-- Compatibility endpoint now preserves committed fresh cargo under Phase 13.
function CartCargoService:RetireFreshForReset(player: Player, _forfeit: boolean, cycleId: number): any
	local result = self:BeginResetPreservation(player, cycleId)
	result.retired = {}
	return result
end

function CartCargoService:GetCargoSnapshot(cart: Model): { CargoEntry }
	local snapshot = {}
	local state = cargoByCart[cart]
	if state then
		for _, entry in state.Entries do
			table.insert(snapshot, copyMetadata(entry))
		end
	end
	return snapshot
end

function CartCargoService:GetCargo(cart: Model): { CargoEntry }
	ensureStarted()
	return self:GetCargoSnapshot(cart)
end

function CartCargoService:GetCargoCount(cart: Model): number
	local state = cargoByCart[cart]
	return if state then cargoCount(state) else 0
end

function CartCargoService:GetCargoRevision(cart: Model): number
	local state = cargoByCart[cart]
	return if state then state.Revision else 0
end

function CartCargoService:GetCargoCapacity(cart: Model): number
	local readiness = self:ResolveEffectiveCargoCapacity(cart)
	return if readiness.status == "Ready" and type(readiness.effectiveCapacity) == "number"
		then readiness.effectiveCapacity
		else 0
end

function CartCargoService:CanAcceptCargo(cart: Model): boolean
	local state = getOrCreateCargo(cart)
	return cart.Parent ~= nil
		and not state.ResetPreservation
		and Workspace:GetAttribute("Phase12ResetCommitting") ~= true
		and self:GetCargoCapacityReadiness(cart).status == "Ready"
		and cargoCount(state) < self:GetCargoCapacity(cart)
		and freeAttachment(cart, state) ~= nil
end

-- Exact-slot removal uses the existing reversible transfer and finalisation.
-- No count/visual notification until the interaction owner has assigned carry.
function CartCargoService:DetachSlotForTransfer(cart: any, slotId: any, expectedItemId: any): (any?, string?)
	local index = authoredSlotIndex(cart, slotId)
	local slot = if index then getAuthoredCargoSlot(cart, index) else nil
	if not slot then
		return nil, "INVALID_SLOT"
	end
	local record = self:GetSlotRecord(cart, slotId)
	if not record or type(expectedItemId) ~= "string" or record.ItemId ~= expectedItemId then
		return nil, "STALE_ID"
	end
	return self:DetachForTransfer(cart, record.ItemId)
end

-- Bounded, synchronous multi-item staging used only by the departure owner so
-- all banked cargo can share one profile mutation. It is reversible until that
-- mutation commits and never creates a world representation itself.
function CartCargoService:PrepareDepartureRemovals(cart: Model, itemIds: { string }): (any?, string?)
	local state = cargoByCart[cart]
	if state == nil then
		return nil, "CARGO_NOT_BOUND"
	end
	if state.Transfer ~= nil or state.Insertion ~= nil or state.DepartureTransfer ~= nil then
		return nil, "BUSY"
	end
	local seen: { [string]: boolean } = {}
	local entries = {}
	for _, itemId in itemIds do
		if type(itemId) ~= "string" or seen[itemId] then
			return nil, "INVALID_ITEM_SET"
		end
		seen[itemId] = true
		local entry = state.ById[itemId]
		local order = if entry then table.find(state.Entries, entry) else nil
		if entry == nil or order == nil or state.Occupancy[entry.AttachmentIndex] ~= itemId then
			return nil, "INVALID_CONTEXT"
		end
		table.insert(entries, {
			Entry = entry,
			Order = order,
			Visual = state.Visuals[itemId],
		})
	end
	table.sort(entries, function(left, right)
		return left.Order > right.Order
	end)
	local token = table.freeze({})
	local batch = { Token = token, Entries = entries, Revision = state.Revision }
	state.DepartureTransfer = batch
	for _, removed in entries do
		local entry = removed.Entry
		table.remove(state.Entries, removed.Order)
		state.ById[entry.ItemId] = nil
		state.Occupancy[entry.AttachmentIndex] = nil
	end
	return token, nil
end

function CartCargoService:RestoreDepartureRemovals(cart: Model, token: any): boolean
	local state = cargoByCart[cart]
	local batch = if state then state.DepartureTransfer else nil
	if batch == nil or batch.Token ~= token then
		return false
	end
	table.sort(batch.Entries, function(left, right)
		return left.Order < right.Order
	end)
	for _, removed in batch.Entries do
		local entry = removed.Entry
		if state.ById[entry.ItemId] ~= nil or state.Occupancy[entry.AttachmentIndex] ~= nil then
			return false
		end
		table.insert(state.Entries, removed.Order, entry)
		state.ById[entry.ItemId] = entry
		state.Occupancy[entry.AttachmentIndex] = entry.ItemId
	end
	state.Revision = batch.Revision
	state.DepartureTransfer = nil
	updateCargoAttributes(cart, state)
	return true
end

function CartCargoService:FinalizeDepartureRemovals(cart: Model, token: any): (boolean, string?)
	local state = cargoByCart[cart]
	local batch = if state then state.DepartureTransfer else nil
	if batch == nil or batch.Token ~= token then
		return false, "INVALID_CONTEXT"
	end
	state.DepartureTransfer = nil
	state.Revision = batch.Revision + 1
	local failures = {}
	for _, removed in batch.Entries do
		local itemId = removed.Entry.ItemId
		if state.Visuals[itemId] == removed.Visual then
			state.Visuals[itemId] = nil
		end
		if removed.Visual then
			local ok, failure = pcall(function()
				BrainrotDisplayMetadata.Clear(removed.Visual)
				destroyCargoVisual(cart, removed.Visual)
			end)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
	end
	updateCargoAttributes(cart, state)
	return true, if #failures > 0 then table.concat(failures, "; ") else nil
end

-- Tokens are opaque and local to one synchronous transfer. While detached, captures
-- cannot allocate the reserved source attachment. No presentation or events happen here.
function CartCargoService:DetachForTransfer(cart: Model, itemId: string): (any?, string?)
	local state = cargoByCart[cart]
	Trace.Emit("5C", "source_detach_check", function()
		local item = state and state.ById[itemId]
		return {
			itemId = itemId,
			recordPresent = item ~= nil,
			transferHeld = state ~= nil and state.Transfer ~= nil,
			attachment = item and item.AttachmentIndex or "none",
			attachmentOccupant = item and state.Occupancy[item.AttachmentIndex] or "none",
			visual = state and state.Visuals[itemId] or "none",
			cargoRevision = state and state.Revision or "none",
		}
	end)
	if state == nil or state.ById[itemId] == nil then
		return nil, "NOT_IN_CARGO"
	end
	if state.Transfer ~= nil or state.Insertion ~= nil or state.DepartureTransfer ~= nil then
		return nil, "BUSY"
	end
	local entry = state.ById[itemId]
	local order = table.find(state.Entries, entry)
	if order == nil or state.Occupancy[entry.AttachmentIndex] ~= itemId then
		return nil, "INVALID_CONTEXT"
	end
	local token = table.freeze({})
	local transfer = {
		Token = token,
		Entry = entry,
		Order = order,
		Visual = state.Visuals[itemId],
		Revision = state.Revision,
	}
	state.Transfer = transfer
	table.remove(state.Entries, order)
	state.ById[itemId] = nil
	state.Occupancy[entry.AttachmentIndex] = nil
	Trace.Emit("5C", "source_detached", function()
		return {
			itemId = itemId,
			attachment = entry.AttachmentIndex,
			attachmentOccupied = state.Occupancy[entry.AttachmentIndex] ~= nil,
			recordPresent = state.ById[itemId] ~= nil,
			token = Trace.Id(token),
			visualPresent = transfer.Visual ~= nil and transfer.Visual.Parent ~= nil,
			visualRemoval = "deferred",
			cargoRevision = state.Revision,
			cargoRemaining = cargoCount(state),
		}
	end)
	return token, nil
end

function CartCargoService:RestoreTransfer(cart: Model, token: any): boolean
	local state = cargoByCart[cart]
	local transfer = if state then state.Transfer else nil
	if transfer == nil or transfer.Token ~= token then
		return false
	end
	local entry = transfer.Entry
	if state.ById[entry.ItemId] ~= nil or state.Occupancy[entry.AttachmentIndex] ~= nil then
		return false
	end
	table.insert(state.Entries, transfer.Order, entry)
	state.ById[entry.ItemId] = entry
	state.Occupancy[entry.AttachmentIndex] = entry.ItemId
	state.Revision = transfer.Revision
	state.Transfer = nil
	Trace.Emit("5C", "source_restored", {
		itemId = entry.ItemId,
		attachment = entry.AttachmentIndex,
		cargoRevision = state.Revision,
		cargoRemaining = cargoCount(state),
		visual = state.Visuals[entry.ItemId] or "none",
		result = "restored_original_entry_and_order",
	})
	return true
end

function CartCargoService:FinalizeTransfer(cart: Model, token: any, onCommitted: (() -> ())?): (boolean, string?)
	local state = cargoByCart[cart]
	local transfer = if state then state.Transfer else nil
	if transfer == nil or transfer.Token ~= token then
		return false, "INVALID_CONTEXT"
	end
	-- Logical finalisation MUST precede any Instance writes. Never restore after this.
	state.Transfer = nil
	state.Revision = transfer.Revision + 1
	local itemId = transfer.Entry.ItemId
	if state.Visuals[itemId] == transfer.Visual then
		state.Visuals[itemId] = nil
	end
	Trace.Emit("5C", "source_logical_finalized", {
		committed = true,
		itemId = itemId,
		attachment = transfer.Entry.AttachmentIndex,
		cargoRevision = state.Revision,
		cargoRemaining = cargoCount(state),
	})
	local errors = {}
	-- Both inventory records and the cargo revision are committed. Notify synchronously
	-- before any fallible Instance cleanup; an observer can never undo this transfer.
	if onCommitted then
		Trace.Emit("5C", "source_commit_callback_enter", { committed = true })
		local notified, failure = pcall(onCommitted)
		Trace.Emit("5C", "source_commit_callback_exit", {
			committed = true,
			result = notified,
			error = if notified then "none" else tostring(failure),
		}, not notified)
		if not notified then
			table.insert(errors, "commit observer: " .. tostring(failure))
		end
	end
	local function present(label: string, action: () -> ())
		Trace.Emit("5C", "source_presentation_enter", { operation = label, committed = true })
		local ok, failure = pcall(action)
		Trace.Emit("5C", "source_presentation_exit", {
			operation = label,
			result = ok,
			error = if ok then "none" else tostring(failure),
			committed = true,
		}, not ok)
		if not ok then
			table.insert(errors, label .. ": " .. tostring(failure))
			-- One bounded, exact-item reconciliation attempt. Never clear a replacement slot.
			Trace.Emit("5C", "source_existing_retry_enter", { operation = label, committed = true })
			local repaired, repairFailure = pcall(action)
			Trace.Emit("5C", "source_existing_retry_exit", {
				operation = label,
				result = repaired,
				error = if repaired then "none" else tostring(repairFailure),
				committed = true,
			}, not repaired)
			if not repaired then
				table.insert(errors, label .. " retry: " .. tostring(repairFailure))
			end
		end
	end
	present("source visual cleanup", function()
		if transfer.Visual then
			BrainrotDisplayMetadata.Clear(transfer.Visual)
			destroyCargoVisual(cart, transfer.Visual)
		end
	end)
	present("cargo attributes", function()
		updateCargoAttributes(cart, state)
	end)
	Trace.Emit("5C", "cargo_finalized", function()
		return {
			committed = true,
			itemId = itemId,
			attachment = transfer.Entry.AttachmentIndex,
			attachmentOccupied = state.Occupancy[transfer.Entry.AttachmentIndex] ~= nil,
			recordPresent = state.ById[itemId] ~= nil,
			oldVisualPresent = transfer.Visual ~= nil and transfer.Visual.Parent ~= nil,
			cargoRevision = state.Revision,
			cargoRemaining = cargoCount(state),
			error = if #errors > 0 then table.concat(errors, "; ") else "none",
		}
	end, #errors > 0)
	return true, if #errors > 0 then table.concat(errors, "; ") else nil
end

function CartCargoService:Start()
	Trace.Emit("BOOT", "cargo_start", { module = script, alreadyStarted = started })
	ensureStarted()
	Trace.Emit("BOOT", "cargo_ready", { started = started })
end

-- Used only after the critical owner has committed/confirmed removal from the
-- profile. These methods never credit cash or remove fresh unbanked cargo.
function CartCargoService:CanSelectOwnedCart(cart: Model): (boolean, string?)
	local state = cargoByCart[cart]
	if not state then
		return false, "CARGO_NOT_BOUND"
	end
	if
		state.Transfer
		or state.Insertion
		or state.DepartureTransfer
		or state.ResetPreservation
		or Workspace:GetAttribute("Phase12ResetCommitting") == true
	then
		return false, "BUSY"
	end
	return true, nil
end

function CartCargoService:PreflightOwnedSacrifice(player: Player, ids: { string }): (any?, string?)
	local selected = {}
	for _, id in ids do
		selected[id] = true
	end
	for id, pending in pendingReturns do
		if selected[id] and pending.Record.Metadata.DurableOwnerUserId == player.UserId and pending.Busy then
			return nil, "BUSY"
		end
	end
	local affected = {}
	for cart, state in cargoByCart do
		if cart:GetAttribute("OwnerUserId") ~= player.UserId then
			continue
		end
		if state.Transfer or state.Insertion or state.DepartureTransfer or state.ResetPreservation then
			return nil, "BUSY"
		end
		for id, entry in state.ById do
			if selected[id] then
				if isFresh(entry, player.UserId) or entry.Metadata.DurableOwnerUserId ~= player.UserId then
					return nil, "OWNERSHIP_CHANGED"
				end
				if state.Occupancy[entry.AttachmentIndex] ~= id then
					return nil, "SOURCE_CHANGED"
				end
				table.insert(affected, { Cart = cart, Id = id, Entry = entry, Revision = state.Revision })
			end
		end
	end
	return { Entries = affected }, nil
end
function CartCargoService:ReconcileOwnedSacrifice(player: Player, ids: { string }, canonicalData: any?): boolean
	local Profile = require(script.Parent.PlayerDataService)
	local data = canonicalData or Profile:GetReadableData(player)
	if not data or not data.Collection then
		return false
	end
	local selected = {}
	for _, id in ids do
		if data.Collection.BrainrotInstances[id] then
			return false
		end
		selected[id] = true
	end
	for id, pending in table.clone(pendingReturns) do
		if selected[id] and pending.Record.Metadata.DurableOwnerUserId == player.UserId then
			if pending.Busy then
				return false
			end
			pendingReturns[id] = nil
			if pending.Prepared then
				World.DiscardPreparedWorld(pending.Prepared)
				pending.Prepared = nil
			end
		end
	end
	for cart, state in cargoByCart do
		if cart:GetAttribute("OwnerUserId") ~= player.UserId then
			continue
		end
		local remove = {}
		for id, entry in state.ById do
			if
				selected[id]
				and not isFresh(entry, player.UserId)
				and entry.Metadata.DurableOwnerUserId == player.UserId
			then
				table.insert(remove, id)
			end
		end
		if #remove > 0 then
			local token = self:PrepareDepartureRemovals(cart, remove)
			if not token then
				return false
			end
			if not self:FinalizeDepartureRemovals(cart, token) then
				return false
			end
		end
	end
	return true
end

function CartCargoService:HandleAuthoritativeRecovery(
	oldPlayer: Player,
	newPlayerOrData: any,
	dataOrPrevious: any,
	previousData: any?
): boolean
	local canonicalData, previous
	if type(newPlayerOrData) == "table" and newPlayerOrData.Collection then
		canonicalData, previous = newPlayerOrData, dataOrPrevious
	else
		canonicalData, previous = dataOrPrevious, previousData
	end
	local owned = canonicalData and canonicalData.Collection and canonicalData.Collection.BrainrotInstances
	if type(owned) ~= "table" or type(previous) ~= "table" then
		return false
	end
	local absent = {}
	for id in (previous.Collection and previous.Collection.BrainrotInstances) or {} do
		if owned[id] == nil then
			table.insert(absent, id)
		end
	end
	-- This existing exact-original path checks durable metadata, cancels matching
	-- deferred returns and leaves all natural cargo/reservations untouched.
	return self:ReconcileOwnedSacrifice(oldPlayer, absent, canonicalData)
end

-- Capture exact source custody before a first-bank save can yield and its visual
-- can be finalized. The release queue needs the actual local departure pose.
function CartCargoService:GetPendingBankSourcePose(
	oldPlayer: Player,
	exactRecord: any,
	operationId: any
): (boolean, CFrame?)
	if type(exactRecord) ~= "table" or operationId ~= "Bank:" .. tostring(exactRecord.ItemId) then
		return false, nil
	end
	local id = exactRecord.ItemId
	local function matches(record: any): boolean
		return type(record) == "table"
			and record.ItemId == id
			and record.BrainrotId == exactRecord.BrainrotId
			and type(record.Metadata) == "table"
			and record.Metadata.DurableOwnerUserId == nil
			and Phase12Rules.RecordMutation(record) ~= nil
			and Phase12Rules.RecordMutation(record) == Phase12Rules.RecordMutation(exactRecord)
			and World.IsPendingBank(id)
	end
	local pending = pendingReturns[id]
	if pending then
		return matches(pending.Record), if matches(pending.Record) then pending.Pose else nil
	end
	for cart, state in cargoByCart do
		if cart:GetAttribute("OwnerUserId") == oldPlayer.UserId then
			local entry = if state.Transfer and state.Transfer.Entry.ItemId == id
				then state.Transfer.Entry
				else state.ById[id]
			if entry then
				if not matches(entry) then
					return false, nil
				end
				pcall(rememberCartPose, cart, state)
				return true, state.LastPose
			end
		end
	end
	return true, nil
end

-- The bank owner calls this only after fresh backend acquisition proves the
-- exact pending bank's saved/absent outcome, while its reservation is held.
function CartCargoService:ReconcilePendingBankSource(oldPlayer: Player, exactRecord: any, operationId: any): boolean
	if
		type(exactRecord) ~= "table"
		or type(exactRecord.ItemId) ~= "string"
		or operationId ~= "Bank:" .. exactRecord.ItemId
	then
		return false
	end
	local id = exactRecord.ItemId
	local function matches(record: any): boolean
		return type(record) == "table"
			and record.ItemId == id
			and record.BrainrotId == exactRecord.BrainrotId
			and type(record.Metadata) == "table"
			and record.Metadata.DurableOwnerUserId == nil
			and Phase12Rules.RecordMutation(record) ~= nil
			and Phase12Rules.RecordMutation(record) == Phase12Rules.RecordMutation(exactRecord)
			and World.IsPendingBank(id)
	end
	local pending = pendingReturns[id]
	if pending then
		if pending.Busy or not matches(pending.Record) then
			return false
		end
		pendingReturns[id] = nil
		if pending.Prepared then
			World.DiscardPreparedWorld(pending.Prepared)
			pending.Prepared = nil
		end
	end
	for cart, state in cargoByCart do
		if cart:GetAttribute("OwnerUserId") ~= oldPlayer.UserId then
			continue
		end
		local transfer = state.Transfer
		if transfer and transfer.Entry.ItemId == id then
			if not matches(transfer.Entry) then
				return false
			end
			if not self:FinalizeTransfer(cart, transfer.Token) then
				return false
			end
		end
		local entry = state.ById[id]
		if entry then
			if not matches(entry) then
				return false
			end
			local token = self:DetachForTransfer(cart, id)
			if not token or not self:FinalizeTransfer(cart, token) then
				return false
			end
		end
	end
	return true
end

-- A departed cart cannot be rebound as a second owner alongside restored
-- platform state. Retire only exact durable mirrors proven by Acquire; the
-- saved owned table is untouched, including legitimately unassigned IDs.
function CartCargoService:ReconcileRecoveredCartReturns(oldPlayer: Player, canonicalData: any): boolean
	local owned = canonicalData and canonicalData.Collection and canonicalData.Collection.BrainrotInstances
	if type(owned) ~= "table" or oldPlayer.Parent == Players then
		return false
	end
	for id, pending in table.clone(pendingReturns) do
		local record = pending.Record
		if record.Metadata.DurableOwnerUserId == oldPlayer.UserId then
			local saved = owned[id]
			if
				pending.Busy
				or (
					saved
					and (
						saved.speciesId ~= record.BrainrotId
						or Phase12Rules.RecordMutation(saved) ~= Phase12Rules.RecordMutation(record)
					)
				)
			then
				return false
			end
			pendingReturns[id] = nil
			if pending.Prepared then
				World.DiscardPreparedWorld(pending.Prepared)
				pending.Prepared = nil
			end
		end
	end
	return true
end
function CartCargoService:PrepareRecoveredCartRemoval(cart: Model, oldPlayer: Player, canonicalData: any): boolean
	local owned = canonicalData and canonicalData.Collection and canonicalData.Collection.BrainrotInstances
	if
		type(owned) ~= "table"
		or oldPlayer.Parent == Players
		or cart:GetAttribute("OwnerUserId") ~= oldPlayer.UserId
	then
		return false
	end
	local state = cargoByCart[cart]
	if not state then
		return true
	end
	if
		state.Transfer
		or state.Insertion
		or state.DepartureTransfer
		or Workspace:GetAttribute("Phase12ResetCommitting") == true
	then
		return false
	end
	local function canonicalMatch(record: any): boolean
		local saved = owned[record.ItemId]
		return saved == nil
			or (
				saved.speciesId == record.BrainrotId
				and Phase12Rules.RecordMutation(saved) == Phase12Rules.RecordMutation(record)
			)
	end
	local remove = {}
	for id, entry in state.ById do
		local ownerId = entry.Metadata.DurableOwnerUserId
		if ownerId ~= nil then
			if ownerId ~= oldPlayer.UserId or not canonicalMatch(entry) then
				return false
			end
			table.insert(remove, id)
		elseif owned[id] ~= nil or World.IsPendingBank(id) then
			return false -- exact pending-bank source reconciliation must run first
		end
	end
	if not self:ReconcileRecoveredCartReturns(oldPlayer, canonicalData) then
		return false
	end
	-- The actor really left; a reset snapshot must not convert logout into
	-- permanent cart ownership. Normal fresh logout still queues exact IDs.
	state.ResetPreservation = nil
	cart:SetAttribute("Phase13CargoResetGeneration", nil)
	if #remove > 0 then
		local token = self:PrepareDepartureRemovals(cart, remove)
		if not token or not self:FinalizeDepartureRemovals(cart, token) then
			return false
		end
	end
	return self:PrepareCartRemoval(cart)
end
return CartCargoService
