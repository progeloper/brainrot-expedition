--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local BaseStorageSystem = require(script.Parent.BaseStorageSystem)
local CartCargoService = require(script.Parent.Parent.Services.CartCargoService)
local CartService = require(script.Parent.Parent.Services.CartService)
local PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)
local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local BrainrotDisplayMetadata = require(ReplicatedStorage.Shared.Utility.BrainrotDisplayMetadata)
local BrainrotVisualScale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local HttpService = game:GetService("HttpService")
local CreatureQuery = require(script.Parent.Parent.Utility.CreatureQueryService)
local Analytics = require(script.Parent.Parent.Services.Phase13AnalyticsService)
local TeamRules = require(ReplicatedStorage.Shared.Utility.ChariotTeamRules)
local EffectText = require(ReplicatedStorage.Shared.Utility.ChariotEffectText)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local Phase13Service = require(script.Parent.Parent.Services.Phase13Service)
local Phase10 = require(ReplicatedStorage.Shared.Config.Phase10)
local TelemetryRules = require(ReplicatedStorage.Shared.Utility.Phase13TelemetryRules)

local REACH = InteractionConfig.PLACEMENT_INTERACT_RADIUS
local PROMPT_TAG = "BrainrotWorldPickup"
local carryPresentation = require(ReplicatedStorage.Shared.Config.PlaytestPresentationMetadata)
local CARRY_OFFSET = CFrame.new(
	carryPresentation.PreviousCarryOffset
		* (
			require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale).TARGET_HEIGHT_STUDS
			/ carryPresentation.PreviousCarryTargetHeight
		)
)

type Dependencies = {
	World: any,
	CreateItemVisual: (string) -> Model?,
	IsDriving: (Player) -> boolean,
	Banked: any?,
	DeparturePolicy: any?,
	Feedback: ((Player, string) -> ())?,
}
type CarryVisual = { Model: Model, Root: BasePart, Weld: WeldConstraint, PivotToBounds: CFrame }
type CarryEntry = {
	Record: any,
	Player: Player,
	Character: Model,
	Root: BasePart,
	Visual: CarryVisual?,
	ReturnPreparation: any?,
	LastReturnPose: CFrame,
	LastCharacterPose: CFrame,
	NextDropAt: number,
	Connections: { RBXScriptConnection },
	Returning: boolean,
	Busy: boolean,
	RetryAt: number,
	LastError: string?,
}

local BrainrotInteractionSystem = {}
local carryChanged = Instance.new("BindableEvent")
BrainrotInteractionSystem.CarryChanged = carryChanged.Event
local committedListeners: { [any]: (Player, any) -> () } = {}
local committedSequence = 0
local dependencies: Dependencies? = nil
local actionValidator: ((Player) -> (boolean, string?))? = nil
local heldReleaseTokens: { [any]: any } = {}
local phase12PickupObserver: any = nil
function BrainrotInteractionSystem.SetPickupObserver(callback: any)
	phase12PickupObserver = callback
end
local regionAccessValidator: ((Player, Model) -> (boolean, string?))? = nil
local carriedByUserId: { [number]: CarryEntry } = {}
local promptByModel: { [Model]: ProximityPrompt } = {}
local targetByPrompt: { [ProximityPrompt]: { Model: Model, ItemId: string } } = {}
local connections: { RBXScriptConnection } = {}
local nextReplaceAt: { [Player]: number } = {}
local departingPlayers: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local characterTrackers: { [Player]: any } = {}
local characterPlayerConnections: { [Player]: { RBXScriptConnection } } = {}
local pickupFailureTimes: { [Player]: number } = {}
local comparisonPreparations: { [Player]: () -> () } = {}
local comparisonPreviews: { [Player]: any } = {}
local comparisonRecoveries: { [Player]: (any) -> boolean } = {}
local departedCargoCharacters: { [Model]: boolean } = setmetatable({}, { __mode = "k" })

local requestGate = require(ReplicatedStorage.Shared.Utility.CommittedRequestGate).new()
local function notifyCommitted(player: Player, receipt: any)
	local replication = require(script.Parent.Parent.Services.CreatureReplicationService)
	replication:Step(false)
	receipt.presentationRevision = replication:GetPresentationRevision(receipt.individualId)
	committedSequence += 1
	local session = PlayerDataService:GetSessionHandle(player)
	receipt.sessionGeneration = if session then session.Generation else nil
	receipt.stream = "Interaction"
	receipt.operationSequence = committedSequence
	local immutable = table.freeze(receipt)
	for _, callback in committedListeners do
		local ok, failure = pcall(callback, player, immutable)
		if not ok then
			warn("[BrainrotInteractionSystem] Observer failed: " .. tostring(failure))
		end
	end
end

function BrainrotInteractionSystem.SubscribeCommitted(callback: (Player, any) -> ()): any
	local connection = {}
	committedListeners[connection] = callback
	function connection.Disconnect()
		committedListeners[connection] = nil
	end
	return connection
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function finitePosition(position: Vector3): boolean
	return position.X == position.X
		and math.abs(position.X) < math.huge
		and position.Y == position.Y
		and math.abs(position.Y) < math.huge
		and position.Z == position.Z
		and math.abs(position.Z) < math.huge
end

function BrainrotInteractionSystem.SetActionValidator(validator: ((Player) -> (boolean, string?))?)
	actionValidator = validator
end

local function canAct(player: Player): (boolean, string?)
	if Phase10.Enabled and actionValidator then
		return actionValidator(player)
	end
	return true, nil
end

local function livingCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if
		player.Parent ~= Players
		or not character
		or not character:IsDescendantOf(Workspace)
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
		or not finitePosition(root.Position)
	then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function BrainrotInteractionSystem.GetCarriedRecord(player: Player): any?
	local entry = carriedByUserId[player.UserId]
	return if entry and entry.Player == player then entry.Record else nil
end

-- Server consumers that coordinate an ownership transition need the carry owner's
-- transition state as well as the immutable individual record. This is a fresh,
-- read-only view; the table and the visual attribute remain non-authoritative.
function BrainrotInteractionSystem.GetCarriedState(player: Player): any?
	local entry = carriedByUserId[player.UserId]
	if not entry or entry.Player ~= player then
		return nil
	end
	return table.freeze({
		Record = entry.Record,
		CarrierUserId = entry.Player.UserId,
		Character = entry.Character,
		Root = entry.Root,
		Visual = if entry.Visual then entry.Visual.Model else nil,
		Busy = entry.Busy,
		Returning = entry.Returning,
	})
end

function BrainrotInteractionSystem.IsCarrying(player: Player): boolean
	return BrainrotInteractionSystem.GetCarriedRecord(player) ~= nil
end

local function canReach(
	player: Player,
	targetPosition: Vector3,
	targetModel: Instance,
	reach: number,
	ignoreTarget: boolean?
): (boolean, string?)
	local allowed, actionReason = canAct(player)
	if not allowed then
		return false, actionReason or "DAZED"
	end
	local character, _, root = livingCharacter(player)
	if not character or not root then
		return false, "NOT_LIVING"
	end
	if not finitePosition(targetPosition) or (root.Position - targetPosition).Magnitude > reach then
		return false, "OUT_OF_REACH"
	end
	local head = character:FindFirstChild("Head")
	local origin = if head and head:IsA("BasePart") then head.Position else root.Position
	local direction = targetPosition - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if ignoreTarget then { character, targetModel } else { character }
	params.IgnoreWater = false
	params.RespectCanCollide = false
	if dependencies and dependencies.World.GetWorldModels then
		local ready = CreatureQuery.SyncWorld(dependencies.World.GetWorldModels())
		if not ready then
			return false, "SOURCE_CHANGED"
		end
	end
	local nativeHit = Workspace:Raycast(origin, direction, params)
	local shapeHit = CreatureQuery.Raycast(origin, direction, params)
	local obstruction = if shapeHit and (not nativeHit or shapeHit.Distance < nativeHit.Distance)
		then shapeHit
		else nativeHit
	if obstruction and obstruction.Instance ~= targetModel and not obstruction.Instance:IsDescendantOf(targetModel) then
		return false, "OBSTRUCTED"
	end
	return true, nil
end

function BrainrotInteractionSystem.SetRegionAccessValidator(validator: ((Player, Model) -> (boolean, string?))?)
	regionAccessValidator = validator
end

function BrainrotInteractionSystem.CanInteract(
	player: Player,
	targetPosition: Vector3,
	targetModel: Instance
): (boolean, string?)
	return canReach(player, targetPosition, targetModel, REACH)
end

local function canReachCargo(player: Player, position: Vector3, cart: Model): (boolean, string?)
	-- Callers first resolve the current permitted cart and exact slot. Ignore only
	-- this cart and the character/carry; external walls, terrain and other carts
	-- remain real obstructions. Measure to the live SLOT anchor, never the chassis.
	return canReach(
		player,
		position,
		cart,
		InteractionConfig.PLACEMENT_INTERACT_RADIUS + InteractionConfig.PLACEMENT_SERVER_TOLERANCE,
		true
	)
end

local function prepareCarryVisual(record: any): CarryVisual?
	local deps = dependencies :: Dependencies
	local visual = deps.CreateItemVisual(record.BrainrotId)
	if not visual then
		return nil
	end
	local result: CarryVisual? = nil
	local ok = pcall(function()
		assert(visual.Parent == nil, "Visual factory must stage a detached clone")
		visual.Name = "CarriedBrainrot"
		-- Only the presentation is sanitized. World restoration uses its untouched
		-- source factory and never copies these non-queryable/massless properties.
		for _, item in visual:GetDescendants() do
			if
				item:IsA("LuaSourceContainer")
				or item:IsA("JointInstance")
				or item:IsA("WeldConstraint")
				or item:IsA("Constraint")
				or item:IsA("BodyMover")
				or item:IsA("Humanoid")
				or item:IsA("AnimationController")
				or item:IsA("Animator")
				or item:IsA("ProximityPrompt")
				or item:IsA("ClickDetector")
				or item:IsA("Sound")
				or item:IsA("ParticleEmitter")
				or item:IsA("Beam")
				or item:IsA("Trail")
				or item:IsA("BillboardGui")
				or item:IsA("SurfaceGui")
			then
				item:Destroy()
			end
		end
		local root = visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart", true)
		assert(root, "No carry root")
		visual.PrimaryPart = root
		for _, item in visual:GetDescendants() do
			for _, tag in CollectionService:GetTags(item) do
				CollectionService:RemoveTag(item, tag)
			end
			if item:IsA("BasePart") then
				item.Anchored, item.Massless, item.RootPriority = false, true, -127
				item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
				item.AssemblyLinearVelocity, item.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
				if item ~= root then
					local weld = Instance.new("WeldConstraint")
					weld.Name, weld.Part0, weld.Part1, weld.Parent = "CarryRigid", root, item, root
				end
			end
		end
		for _, tag in CollectionService:GetTags(visual) do
			CollectionService:RemoveTag(visual, tag)
		end
		visual:SetAttribute("ItemId", record.ItemId)
		visual:SetAttribute("BrainrotId", record.BrainrotId)
		visual:SetAttribute("Captured", true)
		BrainrotDisplayMetadata.SetIdentity(visual, record)
		local weld = Instance.new("WeldConstraint")
		weld.Name, weld.Enabled, weld.Parent = "CarryCharacterWeld", false, root
		local bounds, _, boundsReason = BrainrotVisualScale.GetVisualBounds(visual)
		assert(bounds, boundsReason)
		result = {
			Model = visual,
			Root = root,
			Weld = weld,
			PivotToBounds = bounds,
		}
	end)
	if not ok then
		visual:Destroy()
	end
	return result
end

local function attachPreparedCarry(visual: CarryVisual, entry: CarryEntry)
	assert(entry.Player.Character == entry.Character and entry.Root.Parent == entry.Character, "Character changed")
	-- Position FIRST, weld SECOND. Never PivotTo or zero assembly velocity after
	-- connecting to the avatar, and never change its root or network ownership.
	visual.Model:PivotTo(entry.Root.CFrame * CARRY_OFFSET * visual.PivotToBounds:Inverse())
	visual.Model:SetAttribute(BrainrotDisplayConfig.Attributes.CarrierUserId, entry.Player.UserId)
	if Phase10.Enabled then
		visual.Model:SetAttribute("Phase10TargetKind", "Held")
		visual.Model:SetAttribute("OwnerUserId", entry.Player.UserId)
		visual.Model:SetAttribute("Phase10Banked", type(entry.Record.Metadata.DurableOwnerUserId) == "number")
		local body = visual.Model:FindFirstChild("Body", true)
		if body and body:IsA("BasePart") then
			body.CanQuery = true
		end
	end
	visual.Model.Parent = entry.Character
	visual.Weld.Part0, visual.Weld.Part1 = entry.Root, visual.Root
	visual.Weld.Enabled = true
end

local function detachCarryVisual(entry: CarryEntry)
	local visual = entry.Visual
	if visual then
		BrainrotDisplayMetadata.Clear(visual.Model)
		visual.Weld:Destroy() -- Detach first; never anchor any connected character part.
		visual.Model:Destroy()
	end
	entry.Visual = nil
end

local function retireCommittedCarry(entry: CarryEntry)
	-- Only the obsolete carry model/insurance. Never activate a world return.
	disconnectAll(entry.Connections)
	local function present(action: () -> ())
		local ok, failure = pcall(action)
		if not ok then
			ok, failure = pcall(action)
		end
		if not ok then
			warn("[Place] Committed carry presentation: " .. tostring(failure))
		end
	end
	present(function()
		detachCarryVisual(entry)
	end)
	if entry.ReturnPreparation then
		local preparation = entry.ReturnPreparation
		entry.ReturnPreparation = nil
		present(function()
			(dependencies :: Dependencies).World.DiscardPreparedWorld(preparation)
		end)
	end
	present(function()
		entry.Player:SetAttribute("CarriedItemId", nil)
	end)
	if carriedByUserId[entry.Player.UserId] == entry then
		carriedByUserId[entry.Player.UserId] = nil
	end
	carryChanged:Fire(entry.Player)
end

local function updateReturnPose(entry: CarryEntry)
	if
		entry.Root.Parent == entry.Character
		and entry.Character:IsDescendantOf(Workspace)
		and finitePosition(entry.Root.Position)
	then
		entry.LastCharacterPose = entry.Root.CFrame
	end
	if entry.ReturnPreparation then
		local ignored = if entry.Visual then { entry.Visual.Model } else {}
		local pose = (dependencies :: Dependencies).World.FindSafeReleasePose(
			entry.ReturnPreparation,
			entry.LastCharacterPose,
			ignored,
			false,
			entry.Character
		)
		if pose then
			entry.LastReturnPose = pose
		end
		return pose
	end
	return nil
end

local function preparePrivateRelease(entry: CarryEntry, allowForced: boolean): (CFrame?, string?)
	local deps = dependencies :: Dependencies
	if not entry.ReturnPreparation then
		local prepared, failure = deps.World.PrepareWorldRepresentation(entry.Record, entry.LastReturnPose)
		entry.ReturnPreparation = prepared
		if not prepared then
			return nil, failure or "PREPARATION_FAILED"
		end
	end
	local pose = updateReturnPose(entry)
	if not pose and allowForced then
		pose = deps.World.FindSafeReleasePose(entry.ReturnPreparation, entry.LastReturnPose, {}, true)
	end
	return pose, if pose then nil else "NO_SAFE_POSE"
end

local function publishConfirmedCarryRelease(entry: CarryEntry, allowForced: boolean): boolean
	if carriedByUserId[entry.Player.UserId] ~= entry or not entry.ReturnPreparation then
		return false
	end
	local pose = preparePrivateRelease(entry, allowForced)
	if not pose then
		return false
	end
	local preparation = entry.ReturnPreparation
	preparation.Model:PivotTo(pose)
	local published = (dependencies :: Dependencies).World.ActivatePreparedWorld(preparation, function()
		if carriedByUserId[entry.Player.UserId] ~= entry then
			return false
		end
		carriedByUserId[entry.Player.UserId] = nil
		entry.ReturnPreparation = nil
		return true
	end)
	if not published then
		return false
	end
	entry.Busy = false
	retireCommittedCarry(entry)
	return true
end

local function beginConfirmedCarryRelease(entry: CarryEntry, allowForced: boolean): (boolean, string?)
	local deps = dependencies :: Dependencies
	if
		not deps.Banked
		or type(deps.Banked.IsReleasePending) ~= "function"
		or type(deps.Banked.BeginConfirmedRelease) ~= "function"
	then
		return false, "PERSISTENCE_REQUIRED"
	end
	if deps.Banked:IsReleasePending(entry.Player, entry.Record.ItemId) then
		return true, "RELEASE_PENDING"
	end
	if entry.Busy then
		return false, "BUSY"
	end
	entry.Busy = true
	local pose, reason = preparePrivateRelease(entry, allowForced)
	if not pose then
		entry.Busy = false
		return false, reason
	end
	entry.LastReturnPose = pose
	local result = deps.Banked:BeginConfirmedRelease(entry.Player, entry.Record, function()
		return publishConfirmedCarryRelease(entry, allowForced)
	end, function()
		-- An unconfirmed close must never publish. The departing runtime visual
		-- and private staging model may be discarded without claiming a durable
		-- ownership outcome.
		if entry.Player.Parent ~= Players then
			entry.Busy = false
			retireCommittedCarry(entry)
		end
	end)
	if type(result) ~= "table" or result.ok ~= true then
		entry.Busy = false
		return false, if type(result) == "table" then result.code else "RELEASE_FAILED"
	end
	return true, result.code
end

local function retainTrustedBankedProvenance(entry: CarryEntry)
	local deps = dependencies
	if not Phase10.Enabled or not deps or not deps.Banked or type(deps.Banked.GetOwnedIndividual) ~= "function" then
		return
	end
	local owned = deps.Banked:GetOwnedIndividual(entry.Player, entry.Record.ItemId)
	if type(owned) ~= "table" or owned.speciesId ~= entry.Record.BrainrotId then
		return
	end
	if entry.Record.Metadata.DurableOwnerUserId == entry.Player.UserId then
		return
	end
	local record = table.clone(entry.Record)
	local metadata = table.clone(record.Metadata)
	metadata.DurableOwnerUserId = entry.Player.UserId
	record.Metadata = table.freeze(metadata)
	entry.Record = table.freeze(record)
	if entry.ReturnPreparation then
		deps.World.DiscardPreparedWorld(entry.ReturnPreparation)
		entry.ReturnPreparation = nil
	end
	if entry.Visual then
		entry.Visual.Model:SetAttribute("Phase10Banked", true)
	end
end

-- Both request and lifecycle paths use this transaction. Only server callers
-- select forced cleanup; no client-supplied reason can enable a distant fallback.
local function returnToWorld(entry: CarryEntry, voluntary: boolean?): (boolean, string?)
	if carriedByUserId[entry.Player.UserId] ~= entry or entry.Busy then
		return false, "BUSY"
	end
	local character, _, root = livingCharacter(entry.Player)
	if voluntary and (entry.Returning or character ~= entry.Character or root ~= entry.Root) then
		return false, "NOT_LIVING"
	end
	entry.Busy = true
	retainTrustedBankedProvenance(entry)
	local deps = dependencies :: Dependencies
	if not voluntary then
		-- Detach before the old avatar can disappear. The logical record survives a
		-- blocked fallback and stays in the shared retry path, even on disconnect.
		pcall(updateReturnPose, entry)
		entry.Returning = true
		disconnectAll(entry.Connections)
		detachCarryVisual(entry)
	end
	local ok, restored, reason = pcall(function()
		if not entry.ReturnPreparation then
			local prepared, failure = deps.World.PrepareWorldRepresentation(entry.Record, entry.LastReturnPose)
			entry.ReturnPreparation = prepared
			if not prepared then
				return nil, failure
			end
		end
		-- Preparation may yield in a future asset provider. Recheck exact ownership
		-- and the captured character before deciding or mutating any release pose.
		if carriedByUserId[entry.Player.UserId] ~= entry then
			return nil, "SOURCE_CHANGED"
		end
		local currentCharacter, _, currentRoot = livingCharacter(entry.Player)
		if voluntary and (currentCharacter ~= character or currentRoot ~= root) then
			return nil, "SOURCE_CHANGED"
		end
		local pose = updateReturnPose(entry)
		if not pose and not voluntary then
			pose = deps.World.FindSafeReleasePose(
				entry.ReturnPreparation,
				if Phase10.Enabled then entry.LastCharacterPose else entry.LastReturnPose,
				{},
				true
			)
			if not pose and not Phase10.Enabled then
				local spawn = entry.Record.World.SpawnPosition
				pose = deps.World.FindSafeReleasePose(
					entry.ReturnPreparation,
					CFrame.new(spawn.X, spawn.Y, spawn.Z) * entry.LastReturnPose.Rotation,
					{},
					true
				)
			end
		end
		if not pose then
			return nil, "NO_SAFE_POSE"
		end
		-- No yields from this point through registry activation/ownership commit.
		-- The world model is independent, not the stripped, welded carry display.
		if entry.Visual then
			entry.Visual.Weld.Enabled = false
			entry.Visual.Weld.Part0 = nil
			BrainrotDisplayMetadata.Clear(entry.Visual.Model)
		end
		entry.ReturnPreparation.Model:PivotTo(pose)
		return deps.World.ActivatePreparedWorld(entry.ReturnPreparation)
	end)
	entry.Busy = false
	if ok and restored then
		carriedByUserId[entry.Player.UserId] = nil
		carryChanged:Fire(entry.Player)
		entry.ReturnPreparation = nil
		disconnectAll(entry.Connections)
		detachCarryVisual(entry)
		entry.Player:SetAttribute("CarriedItemId", nil)
		return true
	end
	local errorText = tostring(if ok then reason else restored)
	if voluntary then
		-- A rejected Drop never retires the carried individual or its display.
		-- Restore the existing weld if activation failed after detachment.
		if entry.Visual and not entry.Visual.Weld.Enabled then
			local attached = pcall(attachPreparedCarry, entry.Visual, entry)
			if not attached then
				return returnToWorld(entry)
			end
			BrainrotDisplayMetadata.Apply(
				entry.Visual.Model,
				entry.Record,
				BrainrotDisplayConfig.States.Carried,
				entry.Player.UserId
			)
		end
		if errorText ~= "NO_SAFE_POSE" and errorText ~= "SOURCE_CHANGED" then
			deps.World.DiscardPreparedWorld(entry.ReturnPreparation)
			entry.ReturnPreparation = nil
		end
		return false, errorText
	end
	if
		Phase10.Enabled
		and type(entry.Record.Metadata.DurableOwnerUserId) ~= "number"
		and type(deps.World.QueueFreshRelease) == "function"
	then
		local queued = deps.World.QueueFreshRelease(entry.Record, entry.LastCharacterPose)
		if queued then
			retireCommittedCarry(entry)
			return true, "PENDING_LOCAL_RELEASE"
		end
	end
	-- Never clear the sole logical record on failure. The one shared lifecycle
	-- heartbeat retries this pending return, even after the Player disconnects.
	if entry.ReturnPreparation and errorText ~= "NO_SAFE_POSE" then
		deps.World.DiscardPreparedWorld(entry.ReturnPreparation)
		entry.ReturnPreparation = nil
	end
	entry.RetryAt = os.clock() + 1
	if entry.LastError ~= errorText then
		entry.LastError = errorText
		warn("[Carry] Return pending for " .. entry.Record.ItemId .. ": " .. errorText)
	end
	return false, errorText
end

-- Used by the one accepted-shot resolver for both fresh and secured banked
-- held originals. Preparation may yield; commit rechecks exact carry/character.
function BrainrotInteractionSystem.PrepareHeldRelease(player: Player, expectedId: string): (any?, string?)
	if not Phase10.Enabled or not dependencies then
		return nil, "PHASE10_DISABLED"
	end
	local entry = carriedByUserId[player.UserId]
	if not entry or entry.Player ~= player or entry.Record.ItemId ~= expectedId then
		return nil, "STALE_ID"
	end
	if entry.Busy or entry.Returning then
		return nil, "BUSY"
	end
	local character, _, root = livingCharacter(player)
	if character ~= entry.Character or root ~= entry.Root then
		return nil, "SOURCE_CHANGED"
	end
	if dependencies.Banked and dependencies.Banked:ClassifyRecord(player, entry.Record) == "Uncertain" then
		return nil, "OWNERSHIP_UNCERTAIN"
	end
	entry.Busy = true
	retainTrustedBankedProvenance(entry)
	local token, reason = dependencies.World.PrepareFreshRelease(
		entry.Record,
		root.CFrame,
		if entry.Visual then { entry.Visual.Model, character } else { character },
		character
	)
	if not token then
		entry.Busy = false
		return nil, reason
	end
	local result = table.freeze({ Record = entry.Record, Player = player, Character = character })
	heldReleaseTokens[result] = { Entry = entry, WorldToken = token }
	return result, nil
end

function BrainrotInteractionSystem.DiscardHeldRelease(token: any): boolean
	local stage = heldReleaseTokens[token]
	if not stage then
		return false
	end
	heldReleaseTokens[token] = nil
	(dependencies :: Dependencies).World.DiscardFreshRelease(stage.WorldToken)
	stage.Entry.Busy = false
	return true
end

function BrainrotInteractionSystem.CommitHeldRelease(token: any, validate: (() -> boolean)?): (boolean, string?, Model?)
	local stage = heldReleaseTokens[token]
	if not stage then
		return false, "INVALID_PREPARATION", nil
	end
	local entry = stage.Entry
	local deps = dependencies :: Dependencies
	local model, reason = deps.World.CommitFreshRelease(stage.WorldToken, function()
		local character, _, root = livingCharacter(entry.Player)
		if
			carriedByUserId[entry.Player.UserId] ~= entry
			or character ~= entry.Character
			or root ~= entry.Root
			or entry.Returning
			or not entry.Busy
		then
			return false
		end
		if validate and not validate() then
			return false
		end
		carriedByUserId[entry.Player.UserId] = nil
		return true
	end)
	if not model then
		BrainrotInteractionSystem.DiscardHeldRelease(token)
		return false, reason, nil
	end
	heldReleaseTokens[token] = nil
	entry.Busy = false
	retireCommittedCarry(entry)
	return true, nil, model
end

function BrainrotInteractionSystem.TryDropCarried(player: Player, expectedId: any): (boolean, string?)
	local allowed, actionReason = canAct(player)
	if not allowed then
		return false, actionReason or "DAZED"
	end
	local entry = carriedByUserId[player.UserId]
	if not entry or entry.Player ~= player then
		return false, "EMPTY_HANDS"
	end
	if type(expectedId) ~= "string" or expectedId ~= entry.Record.ItemId then
		return false, "STALE_ID"
	end
	local deps = dependencies :: Dependencies
	if deps.Banked and deps.Banked:GetOwnedIndividual(player, entry.Record.ItemId) ~= nil then
		if Phase10.Enabled then
			return returnToWorld(entry, true)
		end
		local decision = if deps.DeparturePolicy
			then deps.DeparturePolicy.Resolve("DeliberateWorldDrop", "Banked")
			else { ok = false, code = "POLICY_REQUIRED" }
		if decision.ok ~= true then
			-- Keep the exact carry source intact. Publishing it before a confirmed
			-- persistent relinquishment would create a restorable duplicate.
			return false, decision.code or "POLICY_REQUIRED"
		end
		return beginConfirmedCarryRelease(entry, false)
	end
	if os.clock() < entry.NextDropAt then
		return false, "BUSY"
	end
	entry.NextDropAt = os.clock() + 0.25
	return returnToWorld(entry, true)
end

function BrainrotInteractionSystem.MarkResetCharacterDeparture(_player: Player, character: Model, cycleId: number)
	departedCargoCharacters[character] = true
	character:SetAttribute("Phase12ResetGeneration", cycleId)
end

function BrainrotInteractionSystem.HandleCharacterRemoving(player: Player, character: Model): boolean
	local deps = dependencies
	if not deps then
		return false
	end
	local cargoReleased = false
	if Phase10.Enabled and not departingPlayers[player] and not departedCargoCharacters[character] then
		local tracker = characterTrackers[player]
		local currentCharacter = if tracker then tracker.Character == character else player.Character == character
		if currentCharacter then
			local cart = CartService:GetCart(player)
			local ok, reason, released = true, nil, 0
			if cart then
				ok, reason, released = CartCargoService:ReleaseFreshForCharacterDeparture(cart)
			end
			if tracker then
				tracker.Pending = not ok
			end
			if ok then
				departedCargoCharacters[character] = true
				cargoReleased = released > 0
			elseif reason ~= "BUSY" then
				warn("[CargoDeparture] Retaining exact cargo source: " .. tostring(reason))
			end
		end
	end
	local entry = carriedByUserId[player.UserId]
	if not entry or entry.Player ~= player or entry.Character ~= character then
		return cargoReleased
	end
	if
		deps.Banked
		and type(deps.Banked.IsReleasePending) == "function"
		and deps.Banked:IsReleasePending(player, entry.Record.ItemId)
	then
		return true
	end
	local owned = deps.Banked and deps.Banked:GetOwnedIndividual(player, entry.Record.ItemId)
	if owned == nil then
		if Phase10.Enabled then
			return returnToWorld(entry)
		end
		retireCommittedCarry(entry)
		return true
	end
	if type(deps.Banked.ReturnOwnedToAvailableSlot) ~= "function" then
		return false
	end
	local returned = deps.Banked:ReturnOwnedToAvailableSlot(player, entry.Record)
	if type(returned) == "table" and returned.ok == true then
		local bound, bindReason =
			BaseStorageSystem:BindReturnedOwnedIndividual(player, returned.slotId, entry.Record.ItemId)
		if not bound then
			warn("[Carry] Committed banked return awaiting base presentation: " .. tostring(bindReason))
		end
		retireCommittedCarry(entry)
		return true
	end
	if type(returned) == "table" and returned.code == "BASE_FULL" then
		disconnectAll(entry.Connections)
		detachCarryVisual(entry)
		entry.Returning = true
		if Phase10.Enabled then
			return returnToWorld(entry)
		end
		return beginConfirmedCarryRelease(entry, true)
	end
	return false
end

-- Internal recovery seam for a damaged carry presentation or legacy fixture.
-- Character death/reset uses HandleCharacterRemoving and its approved loss/
-- return policy instead of this ordinary world-restoration path.
function BrainrotInteractionSystem.HandleUnexpectedCarryCleanup(player: Player, character: Model): boolean
	local entry = carriedByUserId[player.UserId]
	if not entry or entry.Player ~= player or entry.Character ~= character then
		return false
	end
	return returnToWorld(entry)
end

-- Runs from PlayerDataService's pre-close boundary, before the final snapshot.
-- Persistent carried/cargo outcomes share one profile mutation; fresh cargo is
-- handed to the existing cart-removal world-return queue only after durable
-- cargo has been removed from that cart's authoritative runtime state.
function BrainrotInteractionSystem.HandlePlayerDeparture(player: Player, _reason: string?): (boolean, string?)
	if departingPlayers[player] then
		return true, "ALREADY_PREPARED"
	end
	local deps = dependencies
	if not deps or not deps.Banked then
		return false, "PERSISTENCE_REQUIRED"
	end
	local entry = carriedByUserId[player.UserId]
	if entry and entry.Player ~= player then
		return false, "STALE_CARRY_OWNER"
	end
	if entry and deps.Banked:IsReleasePending(player, entry.Record.ItemId) then
		-- The relinquishment is already represented by its own exact revision.
		-- Final close may cover it; the public copy remains gated by confirmation.
		departingPlayers[player] = true
		return true, "RELEASE_PENDING"
	end

	local cart = CartService:GetCart(player)
	local cargo = if cart then CartCargoService:GetCargoSnapshot(cart) else {}
	local bankedCargoIds = {}
	for _, record in cargo do
		if deps.Banked:GetOwnedIndividual(player, record.ItemId) ~= nil then
			table.insert(bankedCargoIds, record.ItemId)
		end
	end
	local departureToken = nil
	if cart and #bankedCargoIds > 0 then
		local detachReason
		departureToken, detachReason = CartCargoService:PrepareDepartureRemovals(cart, bankedCargoIds)
		if not departureToken then
			return false, detachReason or "CARGO_DETACH_FAILED"
		end
	end

	local securedWorld = if Phase10.Enabled and type(deps.World.GetSecuredWorldRecords) == "function"
		then deps.World.GetSecuredWorldRecords(player.UserId)
		else {}
	local departureRecords = table.clone(cargo)
	for _, record in securedWorld do
		table.insert(departureRecords, record)
	end
	local result = deps.Banked:ApplyLogoutOutcomes(player, if entry then entry.Record else nil, departureRecords)
	if type(result) ~= "table" or result.ok ~= true then
		if departureToken then
			CartCargoService:RestoreDepartureRemovals(cart :: Model, departureToken)
		end
		return false, if type(result) == "table" then result.code else "DEPARTURE_COMMIT_FAILED"
	end
	local outcomes = result.outcomes or {}
	for _, record in securedWorld do
		local outcome = outcomes[record.ItemId]
		if outcome and (outcome.action == "ReturnToAvailableSlot" or outcome.action == "PreserveOwnedUnassigned") then
			local retired, retireReason = deps.World.RetireSecuredWorld(record.ItemId, player.UserId)
			if not retired then
				return false, retireReason or "SECURED_WORLD_RETIRE_FAILED"
			end
		else
			return false, "SECURED_WORLD_OUTCOME_INVALID"
		end
	end
	if departureToken then
		local finalized, finalizeReason = CartCargoService:FinalizeDepartureRemovals(cart :: Model, departureToken)
		if not finalized then
			return false, finalizeReason or "CARGO_FINALIZE_FAILED"
		end
	end
	if cart then
		-- Only fresh cargo remains, so ordinary removal enqueues one identity-
		-- preserving world return for each remaining record.
		local prepared, prepareReason = CartCargoService:PrepareCartRemoval(cart)
		if prepared == false then
			return false, prepareReason or "CARGO_RELEASE_PENDING"
		end
	end
	if entry then
		local outcome = outcomes[entry.Record.ItemId]
		if not outcome then
			return false, "CARRIED_OUTCOME_MISSING"
		end
		if outcome.action == "PublishExistingWorldDrop" then
			returnToWorld(entry)
		elseif
			outcome.action == "ReturnToAvailableSlot"
			or outcome.action == "DestroyOwned"
			or outcome.action == "PreserveOwnedUnassigned"
		then
			retireCommittedCarry(entry)
		else
			return false, "CARRIED_OUTCOME_INVALID"
		end
	end
	departingPlayers[player] = true
	return true, result.code
end

-- Core Loop V2 (A7): a "Saved" overflow sleeper can be taken only by its owner until SavedUntil.
-- The attributes exist only while the director runs, so this is a no-op with the flag off.
local function savedForOther(player: Player, model: any): boolean
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false
	end
	local owner = model:GetAttribute("SavedOwnerUserId")
	local untilAt = model:GetAttribute("SavedUntil")
	return type(owner) == "number"
		and owner ~= player.UserId
		and type(untilAt) == "number"
		and Workspace:GetServerTimeNow() < untilAt
end

local function validatePickup(
	player: Player,
	model: any,
	expectedId: any
): (any?, Model?, Humanoid?, BasePart?, string?)
	local deps = dependencies
	if not deps then
		return nil, nil, nil, nil, "NOT_STARTED"
	end
	local allowed, actionReason = canAct(player)
	if not allowed then
		return nil, nil, nil, nil, actionReason or "DAZED"
	end
	local character, humanoid, root = livingCharacter(player)
	if not character or not humanoid or not root then
		return nil, nil, nil, nil, "NOT_LIVING"
	end
	if carriedByUserId[player.UserId] then
		return nil, nil, nil, nil, "ALREADY_CARRYING"
	end
	if deps.IsDriving(player) then
		return nil, nil, nil, nil, "DRIVING"
	end
	if typeof(model) ~= "Instance" or not model:IsA("Model") or type(expectedId) ~= "string" then
		return nil, nil, nil, nil, "INVALID_TARGET"
	end
	if savedForOther(player, model) then
		return nil, nil, nil, nil, "SAVED_FOR_OWNER"
	end
	local record, state = deps.World.GetWorldRecord(model)
	if not record or state ~= "WorldSleeping" then
		return nil, nil, nil, nil, "NOT_SLEEPING_WORLD"
	end
	if record.ItemId ~= expectedId then
		return nil, nil, nil, nil, "STALE_ID"
	end
	if
		Phase10.Enabled
		and type(record.Metadata.DurableOwnerUserId) == "number"
		and record.Metadata.DurableOwnerUserId ~= player.UserId
	then
		return nil, nil, nil, nil, "BANKED_PROTECTED"
	end
	if
		type(record.Metadata.DurableOwnerUserId) == "number"
		and deps.Banked
		and deps.Banked:GetOwnedIndividual(player, record.ItemId) == nil
	then
		return nil, nil, nil, nil, "OWNERSHIP_CHANGED"
	end
	local body = model:FindFirstChild("Body", true)
	if not body or not body:IsA("BasePart") then
		return nil, nil, nil, nil, "INVALID_TARGET"
	end
	if regionAccessValidator then
		local regionAllowed, accessReason = regionAccessValidator(player, model)
		if not regionAllowed then
			return nil, nil, nil, nil, accessReason or "RegionAccessRequired"
		end
	end
	local reachable, reason = BrainrotInteractionSystem.CanInteract(player, body.Position, model)
	if not reachable then
		return nil, nil, nil, nil, reason
	end
	return record, character, humanoid, root, nil
end

local function newCarryEntry(
	player: Player,
	character: Model,
	root: BasePart,
	record: any,
	visual: CarryVisual,
	returnPreparation: any,
	sourcePose: CFrame
): CarryEntry
	return {
		Record = record,
		Player = player,
		Character = character,
		Root = root,
		Visual = visual,
		ReturnPreparation = returnPreparation,
		LastReturnPose = sourcePose,
		LastCharacterPose = root.CFrame,
		NextDropAt = 0,
		Connections = {},
		Returning = false,
		Busy = true,
		RetryAt = 0,
	}
end

local function installCarryPresentation(entry: CarryEntry, humanoid: Humanoid)
	local player, character = entry.Player, entry.Character
	local function cleanup()
		if carriedByUserId[player.UserId] == entry then
			BrainrotInteractionSystem.HandleCharacterRemoving(player, character)
		end
	end
	table.insert(entry.Connections, humanoid.Died:Connect(cleanup))
	table.insert(entry.Connections, character.Destroying:Connect(cleanup))
	table.insert(
		entry.Connections,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(Workspace) then
				cleanup()
			end
		end)
	)
	table.insert(
		entry.Connections,
		player.CharacterRemoving:Connect(function(removingCharacter)
			if removingCharacter == character then
				cleanup()
			end
		end)
	)
	attachPreparedCarry(entry.Visual :: CarryVisual, entry)
end

local function tryPickupWorld(player: Player, targetModel: any, expectedId: any): (boolean, string?)
	local record, character, humanoid, root, reason = validatePickup(player, targetModel, expectedId)
	if not record or not character or not humanoid or not root then
		return false, reason
	end
	local deps = dependencies :: Dependencies
	local controlledRecord = record
	local phaseState = if deps.World.GetPhase12State then deps.World.GetPhase12State(record) else nil
	local fresh = type(record.Metadata.DurableOwnerUserId) ~= "number"
	local acquisitionKind = if phaseState
			and (
				(phaseState.LastSecuredByUserId ~= nil and phaseState.LastSecuredByUserId ~= player.UserId)
				or (phaseState.LastSecuredByUserId == player.UserId and phaseState.AcquisitionKind == "Theft")
				or (phaseState.LastReleaseKind == "Theft" and phaseState.LastTheftAttackerUserId == player.UserId)
			)
		then "Theft"
		else "Hunt"
	if type(deps.World.CreatePlayerControlledRecord) == "function" then
		local cleared, clearReason = deps.World.CreatePlayerControlledRecord(record)
		if cleared == nil then
			return false, clearReason or "PREPARATION_FAILED"
		end
		controlledRecord = cleared
	end
	local visual: CarryVisual? = nil
	local returnPreparation: any? = nil
	local sourcePose = targetModel:GetPivot()
	local prepared = pcall(function()
		visual = prepareCarryVisual(record)
		assert(visual, "Carry visual unavailable")
		-- A dormant normal-world preparation is cleanup insurance, not another owner.
		-- It survives source-asset removal and never inherits carry-only physics.
		returnPreparation = deps.World.PrepareWorldRepresentation(controlledRecord, sourcePose)
		assert(returnPreparation, "World return preparation unavailable")
	end)
	local function discard()
		if visual then
			visual.Weld:Destroy()
			visual.Model:Destroy()
		end
		if returnPreparation then
			deps.World.DiscardPreparedWorld(returnPreparation)
		end
	end
	if not prepared then
		discard()
		return false, "PREPARATION_FAILED"
	end
	local current, currentCharacter, currentHumanoid, currentRoot, changedReason =
		validatePickup(player, targetModel, expectedId)
	if current ~= record or currentCharacter ~= character or currentHumanoid ~= humanoid or currentRoot ~= root then
		discard()
		return false, changedReason or "SOURCE_CHANGED"
	end
	-- No yields from the final recheck through ownership handoff and attachment.
	if deps.IsDriving(player) then
		discard()
		return false, "DRIVING"
	end
	local taken, committedRecord = deps.World.TakeSleepingWorld(targetModel, record, controlledRecord)
	if not taken then
		discard()
		return false, "SOURCE_CHANGED"
	end
	record = committedRecord or controlledRecord
	local entry = newCarryEntry(player, character, root, record, visual :: CarryVisual, returnPreparation, sourcePose)
	carriedByUserId[player.UserId] = entry
	carryChanged:Fire(player) -- Server-owned notification; consumers re-read IsCarrying.
	local attached, failure = pcall(function()
		player:SetAttribute("CarriedItemId", record.ItemId)
		installCarryPresentation(entry, humanoid)
		BrainrotDisplayMetadata.Apply(
			(entry.Visual :: CarryVisual).Model,
			record,
			BrainrotDisplayConfig.States.Carried,
			player.UserId
		)
	end)
	entry.Busy = false
	targetModel:Destroy() -- The committed entry/return token own the individual now.
	if not attached then
		warn("[Carry] Attachment failed; restoring " .. record.ItemId .. ": " .. tostring(failure))
		returnToWorld(entry)
		return false, "ATTACHMENT_FAILED"
	end
	pcall(updateReturnPose, entry)
	pcall(Analytics.Record, Analytics, player, "AcquisitionAttempt", 1, {
		category = if fresh then acquisitionKind else "OwnedMove",
		result = "Success",
	})
	if phase12PickupObserver then
		phase12PickupObserver(player, record, if entry.Visual then entry.Visual.Model else nil)
	end
	if fresh then
		local previousCarrier = phaseState and phaseState.LastSecuredByUserId
		if deps.World.UpdatePhase12State then
			deps.World.UpdatePhase12State(
				record,
				{ LastSecuredByUserId = player.UserId, LastReleaseKind = "Secured", AcquisitionKind = acquisitionKind }
			)
		end
		if previousCarrier ~= player.UserId then
			pcall(Analytics.ObserveSecuredAcquisition, Analytics, player, acquisitionKind, record.ItemId)
			pcall(Analytics.Funnel, Analytics, player, "EarlyJourney", 2)
			pcall(
				Analytics.Funnel,
				Analytics,
				player,
				if acquisitionKind == "Theft" then "TheftBranch" else "HuntBranch",
				3
			)
		end
	end
	local acquiredAt = Workspace:GetServerTimeNow()
	local bankedSource = Phase10.Enabled and type(record.Metadata.DurableOwnerUserId) == "number"
	local firstAcquisition = not bankedSource
		and (
			not Phase10.Enabled
			or type(deps.World.MarkFirstAcquisition) ~= "function"
			or deps.World.MarkFirstAcquisition(record)
		)

	notifyCommitted(player, {
		kind = if bankedSource then "BankedAcquired" elseif firstAcquisition then "WildAcquired" else "LooseSecured",
		eventId = (if firstAcquisition then "wild-acquired:" else "loose-secured:")
			.. record.ItemId
			.. ":"
			.. tostring(acquiredAt),
		at = acquiredAt,
		individualId = record.ItemId,
		speciesId = record.BrainrotId,
	})
	return true, nil
end

function BrainrotInteractionSystem.TryPickupWorld(player: Player, targetModel: any, expectedId: any): (boolean, string?)
	local success, reason = tryPickupWorld(player, targetModel, expectedId)
	if not success and os.clock() - (pickupFailureTimes[player] or -math.huge) >= 2 then
		pickupFailureTimes[player] = os.clock()
		pcall(function()
			Analytics:Record(
				player,
				"PickupFailure",
				1,
				{ category = TelemetryRules.PickupCategory(reason), result = "Denied" }
			)
		end)
	end
	pcall(function()
		local entry = success and carriedByUserId[player.UserId]
		local identity = if entry then entry.Record.ItemId else expectedId
		if entry and type(entry.Record.Metadata.DurableOwnerUserId) == "number" then
			Analytics:ObserveSecuredAcquisition(player, "OwnedMove", identity)
		end
	end)
	return success, reason
end

local function validateCargoPickup(
	player: Player,
	cart: any,
	slotId: any,
	expectedId: any
): (any?, Model?, Humanoid?, BasePart?, string?)
	local deps = dependencies
	if not deps then
		return nil, nil, nil, nil, "NOT_STARTED"
	end
	local character, humanoid, root = livingCharacter(player)
	if not character or not humanoid or not root then
		return nil, nil, nil, nil, "NOT_LIVING"
	end
	if carriedByUserId[player.UserId] then
		return nil, nil, nil, nil, "ALREADY_CARRYING"
	end
	if deps.IsDriving(player) then
		return nil, nil, nil, nil, "DRIVING"
	end
	if not CartCargoService:CanPlayerHandleCargo(player, cart) then
		return nil, nil, nil, nil, "NOT_OWNER"
	end
	local slot, attachment = CartCargoService:ResolveStoredCargoSlot(cart, slotId)
	if not slot or not attachment then
		return nil, nil, nil, nil, "INVALID_SLOT"
	end
	-- The authoritative cargo container is secured/asleep; display attributes and
	-- clicked descendants are not evidence of custody or a world sleep target.
	local record = CartCargoService:GetSlotRecord(cart, slotId)
	if
		record
		and type(record.Metadata.DurableOwnerUserId) == "number"
		and dependencies.Banked
		and dependencies.Banked:GetOwnedIndividual(player, record.ItemId) == nil
	then
		return nil, nil, nil, nil, "OWNERSHIP_CHANGED"
	end
	if not record or type(expectedId) ~= "string" or record.ItemId ~= expectedId then
		return nil, nil, nil, nil, "STALE_ID"
	end
	local reachable, reason = canReachCargo(player, attachment.WorldPosition, cart)
	if not reachable then
		return nil, nil, nil, nil, reason
	end
	return record, character, humanoid, root, nil
end

function BrainrotInteractionSystem.TryPickupCargo(
	player: Player,
	cart: any,
	slotId: any,
	expectedItemId: any
): (boolean, string?)
	local record, character, humanoid, root, reason = validateCargoPickup(player, cart, slotId, expectedItemId)
	if not record or not character or not humanoid or not root then
		return false, reason
	end
	local deps = dependencies :: Dependencies
	local slot, attachment = CartCargoService:ResolveStoredCargoSlot(cart, slotId)
	local sourcePose = (attachment :: Attachment).WorldCFrame
	local visual: CarryVisual? = nil
	local returnPreparation: any? = nil
	local entry: CarryEntry? = nil
	local function discard()
		if entry then
			disconnectAll(entry.Connections)
		end
		if visual then
			visual.Weld:Destroy()
			visual.Model:Destroy()
		end
		if returnPreparation then
			deps.World.DiscardPreparedWorld(returnPreparation)
		end
	end
	local prepared = pcall(function()
		visual = prepareCarryVisual(record)
		assert(visual, "Carry visual unavailable")
		returnPreparation = deps.World.PrepareWorldRepresentation(record, sourcePose)
		assert(returnPreparation, "World return preparation unavailable")
	end)
	if not prepared then
		discard()
		return false, "PREPARATION_FAILED"
	end
	local function revalidate(): (boolean, string?)
		local current, c, h, r, changed = validateCargoPickup(player, cart, slotId, expectedItemId)
		local s, a = CartCargoService:ResolveStoredCargoSlot(cart, slotId)
		return current == record
			and c == character
			and h == humanoid
			and r == root
			and s == slot
			and a == attachment
			and dependencies == deps,
			changed or "SOURCE_CHANGED"
	end
	local valid
	valid, reason = revalidate()
	if not valid then
		discard()
		return false, reason
	end
	entry = newCarryEntry(player, character, root, record, visual :: CarryVisual, returnPreparation, sourcePose)
	-- Do all fallible attachment work before removing cargo. A failed mount leaves
	-- the slot and its original display intact; no ordinary pickup wakes a world copy.
	local installed = pcall(installCarryPresentation, entry, humanoid)
	if not installed then
		discard()
		return false, "ATTACHMENT_FAILED"
	end
	valid, reason = revalidate()
	if not valid then
		discard()
		return false, reason
	end
	-- Synchronous exact-source removal + carry assignment. Finalize only publishes
	-- count/revision and destroys the renderer's known old slot model, never cart.
	local token
	token, reason = CartCargoService:DetachSlotForTransfer(cart, slotId, record.ItemId)
	if not token then
		discard()
		return false, reason
	end
	carriedByUserId[player.UserId] = entry
	if type(deps.World.MarkFreshTransit) == "function" then
		deps.World.MarkFreshTransit(record, "Carried")
	end
	local finalized = CartCargoService:FinalizeTransfer(cart, token)
	assert(finalized, "Valid cargo transfer token lost before non-yielding finalisation")
	BrainrotDisplayMetadata.Apply(
		(entry.Visual :: CarryVisual).Model,
		record,
		BrainrotDisplayConfig.States.Carried,
		player.UserId
	)
	entry.Busy = false
	local mirrored, mirrorError = pcall(function()
		player:SetAttribute("CarriedItemId", record.ItemId)
	end)
	if not mirrored then
		warn("[Carry] Committed cargo pickup mirror: " .. tostring(mirrorError))
	end
	carryChanged:Fire(player)
	pcall(updateReturnPose, entry)
	return true, nil
end

local function validatePlatformPickup(
	player: Player,
	platform: any,
	expectedId: any
): (any?, any?, Model?, Humanoid?, BasePart?, string?)
	local deps = dependencies
	if not deps then
		return nil, nil, nil, nil, nil, "NOT_STARTED"
	end
	local character, humanoid, root = livingCharacter(player)
	if not character or not humanoid or not root then
		return nil, nil, nil, nil, nil, "NOT_LIVING"
	end
	if carriedByUserId[player.UserId] then
		return nil, nil, nil, nil, nil, "ALREADY_CARRYING"
	end
	if deps.IsDriving(player) then
		return nil, nil, nil, nil, nil, "DRIVING"
	end
	local slot, storage, reason = BaseStorageSystem:ResolvePlatform(player, platform)
	if not slot or not storage then
		return nil, nil, nil, nil, nil, reason
	end
	local record = storage:GetPlatformRecord(slot.Index)
	if not record or type(expectedId) ~= "string" or record.ItemId ~= expectedId then
		return nil, nil, nil, nil, nil, "STALE_ID"
	end
	if deps.Banked and deps.Banked:IsBankPending(player, record.ItemId) then
		return nil, nil, nil, nil, nil, "BANK_SAVE_PENDING"
	end
	local position = if slot.Marker:IsA("Attachment") then slot.Marker.WorldPosition else slot.Marker.Position
	local reachable, reachReason = canReach(
		player,
		position,
		platform,
		InteractionConfig.PLACEMENT_INTERACT_RADIUS + InteractionConfig.PLACEMENT_SERVER_TOLERANCE
	)
	if not reachable then
		return nil, nil, nil, nil, nil, reachReason
	end
	return record, slot, character, humanoid, root, nil
end

-- Deposited pickup reuses the established carry lifecycle. The outgoing income
-- interval is settled by BaseStorageSystem immediately before the exact occupant
-- is removed; the stable platform cash ledger remains at the source platform.
function BrainrotInteractionSystem.TryPickupPlatform(
	player: Player,
	platform: any,
	expectedItemId: any
): (boolean, string?)
	local record, slot, character, humanoid, root, reason = validatePlatformPickup(player, platform, expectedItemId)
	if not record or not slot or not character or not humanoid or not root then
		return false, reason
	end
	local deps = dependencies :: Dependencies
	local sourcePose = if slot.Marker:IsA("Attachment") then slot.Marker.WorldCFrame else slot.Marker.CFrame
	local carryRecord = record
	local visual: CarryVisual? = nil
	local returnPreparation: any? = nil
	local entry: CarryEntry? = nil
	local function discard()
		if entry then
			disconnectAll(entry.Connections)
		end
		if visual then
			visual.Weld:Destroy()
			visual.Model:Destroy()
		end
		if returnPreparation then
			deps.World.DiscardPreparedWorld(returnPreparation)
		end
	end
	local prepared, preparationFailure = pcall(function()
		if record.World == nil then
			local restored, restoreReason = deps.World.CreateRestoredWorldRecord(record, sourcePose)
			assert(restored, restoreReason)
			carryRecord = restored
		end
		visual = prepareCarryVisual(carryRecord)
		assert(visual, "Carry visual unavailable")
		local prepareReason
		returnPreparation, prepareReason = deps.World.PrepareWorldRepresentation(carryRecord, sourcePose)
		assert(returnPreparation, prepareReason or "World return preparation unavailable")
		-- Keep the factory's canonical runtime scale, never the removed storage
		-- record (which intentionally contains no saved world-return envelope).
		carryRecord = returnPreparation.Record or carryRecord
	end)
	if not prepared then
		discard()
		warn("[Carry] Platform pickup preparation failed for " .. record.ItemId .. ": " .. tostring(preparationFailure))
		return false, "PREPARATION_FAILED"
	end
	local function revalidate(): (boolean, string?)
		local current, currentSlot, currentCharacter, currentHumanoid, currentRoot, changed =
			validatePlatformPickup(player, platform, expectedItemId)
		return current ~= nil
			and current.ItemId == record.ItemId
			and currentSlot == slot
			and currentCharacter == character
			and currentHumanoid == humanoid
			and currentRoot == root
			and dependencies == deps,
			changed or "SOURCE_CHANGED"
	end
	local valid
	valid, reason = revalidate()
	if not valid then
		discard()
		return false, reason
	end
	entry = newCarryEntry(player, character, root, carryRecord, visual :: CarryVisual, returnPreparation, sourcePose)
	local installed = pcall(installCarryPresentation, entry, humanoid)
	if not installed then
		discard()
		return false, "ATTACHMENT_FAILED"
	end
	valid, reason = revalidate()
	if not valid then
		discard()
		return false, reason
	end
	local removed
	removed, reason = BaseStorageSystem:TryRemoveFromPlatform(player, platform, record.ItemId)
	if not removed then
		discard()
		return false, reason
	end
	carriedByUserId[player.UserId] = entry
	BrainrotDisplayMetadata.Apply(
		(entry.Visual :: CarryVisual).Model,
		removed,
		BrainrotDisplayConfig.States.Carried,
		player.UserId
	)
	entry.Busy = false
	local mirrored, mirrorError = pcall(function()
		player:SetAttribute("CarriedItemId", removed.ItemId)
	end)
	if not mirrored then
		warn("[Carry] Committed platform pickup mirror: " .. tostring(mirrorError))
	end
	carryChanged:Fire(player)
	pcall(updateReturnPose, entry)
	return true, nil
end

local function validateCarriedSource(player: Player, expectedId: any): (CarryEntry?, string?)
	if not dependencies then
		return nil, "NOT_READY"
	end
	local allowed, actionReason = canAct(player)
	if not allowed then
		return nil, actionReason or "DAZED"
	end
	local character, _, root = livingCharacter(player)
	if not character or not root then
		return nil, "NOT_LIVING"
	end
	local entry = carriedByUserId[player.UserId]
	if not entry or entry.Player ~= player then
		return nil, "EMPTY_HANDS"
	end
	if type(expectedId) ~= "string" or entry.Record.ItemId ~= expectedId then
		return nil, "STALE_ID"
	end
	if dependencies.Banked and dependencies.Banked:IsBankPending(player, entry.Record.ItemId) then
		return nil, "BANK_SAVE_PENDING"
	end
	if entry.Returning or entry.Character ~= character or entry.Root ~= root then
		return nil, "SOURCE_CHANGED"
	end
	if (dependencies :: Dependencies).IsDriving(player) then
		return nil, "DRIVING"
	end
	local visual = entry.Visual
	if not visual or visual.Model.Parent ~= character or not visual.Weld.Enabled then
		return nil, "SOURCE_CHANGED"
	end
	return entry, nil
end

-- Reconciliation removes representations only after the saved ownership map has
-- removed the exact owned original. It never runs sale/sacrifice authority again.
function BrainrotInteractionSystem.PreflightOwnedSacrifice(player: Player, ids: { string }): (any?, string?)
	local data = PlayerDataService:GetReadableData(player)
	if not data or not data.Collection then
		return nil, "PROFILE_NOT_READY"
	end
	local owned = data.Collection.BrainrotInstances
	local selected = {}
	for _, id in ids do
		if type(id) ~= "string" or not owned[id] then
			return nil, "OWNERSHIP_CHANGED"
		end
		if dependencies and dependencies.Banked and dependencies.Banked:IsBankPending(player, id) then
			return nil, "BANK_SAVE_PENDING"
		end
		selected[id] = true
	end
	local entry = carriedByUserId[player.UserId]
	if entry and selected[entry.Record.ItemId] then
		if entry.Busy or entry.Returning or entry.Record.Metadata.DurableOwnerUserId ~= player.UserId then
			return nil, "BUSY"
		end
	end
	return { Ids = selected, Entry = entry, Character = player.Character }, nil
end
function BrainrotInteractionSystem.ReconcileOwnedSacrifice(
	player: Player,
	ids: { string },
	canonicalData: any?
): boolean
	local data = canonicalData or PlayerDataService:GetReadableData(player)
	if not data or not data.Collection then
		return false
	end
	local owned = data.Collection.BrainrotInstances
	for _, id in ids do
		if owned[id] ~= nil then
			return false
		end
		local entry = carriedByUserId[player.UserId]
		if entry and entry.Record.ItemId == id and entry.Record.Metadata.DurableOwnerUserId == player.UserId then
			retireCommittedCarry(entry)
		end
		if dependencies and type(dependencies.World.RetireSecuredWorld) == "function" then
			local ok = dependencies.World.RetireSecuredWorld(id, player.UserId)
			if not ok then
				return false
			end
		end
	end
	return true
end
-- Read-only source pose for the bank owner to retain before save/yield. The
-- reservation remains owned by the pending-bank barrier; no transfer occurs.
function BrainrotInteractionSystem.GetPendingBankSourcePose(
	oldPlayer: Player,
	exactRecord: any,
	operationId: any
): (boolean, CFrame?)
	if
		type(exactRecord) ~= "table"
		or type(exactRecord.ItemId) ~= "string"
		or operationId ~= "Bank:" .. exactRecord.ItemId
	then
		return false, nil
	end
	local entry = carriedByUserId[oldPlayer.UserId]
	if not entry or entry.Player ~= oldPlayer or entry.Record.ItemId ~= exactRecord.ItemId then
		return true, nil
	end
	local mutation = Phase12Rules.RecordMutation(exactRecord)
	if
		type(entry.Record.Metadata.DurableOwnerUserId) == "number"
		or entry.Record.BrainrotId ~= exactRecord.BrainrotId
		or not mutation
		or Phase12Rules.RecordMutation(entry.Record) ~= mutation
		or not dependencies
		or not dependencies.World.IsPendingBank(exactRecord.ItemId)
	then
		return false, nil
	end
	local root = entry.Root
	if
		root.Parent == entry.Character
		and entry.Character:IsDescendantOf(Workspace)
		and finitePosition(root.Position)
	then
		return true, root.CFrame
	end
	return true, entry.LastCharacterPose
end

-- Called by the bank recovery owner only after canonical backend reacquisition
-- has proved the saved/absent outcome. This consumes no reservation or currency.
function BrainrotInteractionSystem.ReconcilePendingBankSource(
	oldPlayer: Player,
	exactRecord: any,
	operationId: any
): boolean
	if
		type(exactRecord) ~= "table"
		or type(exactRecord.ItemId) ~= "string"
		or operationId ~= "Bank:" .. exactRecord.ItemId
	then
		return false
	end
	local entry = carriedByUserId[oldPlayer.UserId]
	if not entry or entry.Player ~= oldPlayer or entry.Record.ItemId ~= exactRecord.ItemId then
		return true
	end
	local mutation = Phase12Rules.RecordMutation(exactRecord)
	if
		type(entry.Record.Metadata.DurableOwnerUserId) == "number"
		or entry.Record.BrainrotId ~= exactRecord.BrainrotId
		or not mutation
		or Phase12Rules.RecordMutation(entry.Record) ~= mutation
		or not dependencies
		or not dependencies.World.IsPendingBank(exactRecord.ItemId)
	then
		return false
	end
	retireCommittedCarry(entry)
	return true
end

-- The newly acquired, validated backend snapshot is authority. No mutation,
-- refund, source save or old confirmation callback runs through this path.
function BrainrotInteractionSystem.HandleAuthoritativeRecovery(
	oldPlayer: Player,
	newPlayerOrData: any,
	dataOrPrevious: any,
	previousData: any?
): boolean
	local canonicalData, previous, newPlayer
	if type(newPlayerOrData) == "table" and newPlayerOrData.Collection then
		canonicalData, previous = newPlayerOrData, dataOrPrevious
	else
		newPlayer, canonicalData, previous = newPlayerOrData, dataOrPrevious, previousData
	end
	local owned = canonicalData and canonicalData.Collection and canonicalData.Collection.BrainrotInstances
	if type(owned) ~= "table" or type(previous) ~= "table" then
		return false
	end
	local recover = comparisonRecoveries[oldPlayer]
	if recover and not recover(canonicalData) then
		return false
	end
	local discard = comparisonPreparations[oldPlayer]
	if discard then
		discard()
	end
	comparisonPreparations[oldPlayer], comparisonPreviews[oldPlayer], comparisonRecoveries[oldPlayer] = nil, nil, nil
	local absent = {}
	for id in (previous.Collection and previous.Collection.BrainrotInstances) or {} do
		if owned[id] == nil then
			table.insert(absent, id)
		end
	end
	if not BrainrotInteractionSystem.ReconcileOwnedSacrifice(oldPlayer, absent, canonicalData) then
		return false
	end
	local entry = carriedByUserId[oldPlayer.UserId]
	if
		entry
		and entry.Player == oldPlayer
		and ((newPlayer and newPlayer ~= oldPlayer) or oldPlayer.Parent ~= Players)
	then
		if type(entry.Record.Metadata.DurableOwnerUserId) ~= "number" then
			if owned[entry.Record.ItemId] ~= nil then
				-- The canonical backend proves first-bank ownership; retire only
				-- the old fresh source mirror, never its saved individual.
				retireCommittedCarry(entry)
			elseif not returnToWorld(entry) then
				return false -- Same counted source remains pending; no new-player hand transfer.
			end
		else
			local canonical = owned[entry.Record.ItemId]
			if
				type(canonical) ~= "table"
				or entry.Record.Metadata.DurableOwnerUserId ~= oldPlayer.UserId
				or canonical.speciesId ~= entry.Record.BrainrotId
				or canonical.mutationId ~= Phase12Rules.RecordMutation(entry.Record)
			then
				return false
			end
			-- Ready restores unassigned durable ownership into the new base. An
			-- old-character hand must not be rebound alongside that platform.
			-- Retire only its exact physical mirror; canonical ownership survives.
			retireCommittedCarry(entry)
		end
	end
	return true
end
local function comparisonContext(player: Player, platform: any, expectedId: any): (any?, string?)
	local incoming, reason = validateCarriedSource(player, expectedId)
	if not incoming then
		return nil, reason
	end
	if incoming.Busy or Workspace:GetAttribute("Phase12ResetCommitting") == true then
		return nil, "BUSY"
	end
	local slot, storage, why = BaseStorageSystem:ResolvePlatform(player, platform)
	if not slot or not storage then
		return nil, why
	end
	local outgoing = storage:GetPlatformRecord(slot.Index)
	if not outgoing or outgoing.ItemId == incoming.Record.ItemId then
		return nil, "STALE_SLOT"
	end
	if dependencies.Banked and dependencies.Banked:IsBankPending(player, outgoing.ItemId) then
		return nil, "BANK_SAVE_PENDING"
	end
	local pose = if slot.Marker:IsA("Attachment") then slot.Marker.WorldCFrame else slot.Marker.CFrame
	local reachable, reachReason = canReach(
		player,
		pose.Position,
		platform,
		InteractionConfig.PLACEMENT_INTERACT_RADIUS + InteractionConfig.PLACEMENT_SERVER_TOLERANCE
	)
	if not reachable then
		return nil, reachReason
	end
	local data = PlayerDataService:GetReadableData(player)
	if not data or not data.Phase13 then
		return nil, "PROFILE_NOT_READY"
	end
	return {
		Entry = incoming,
		Outgoing = outgoing,
		Slot = slot,
		Storage = storage,
		Platform = platform,
		Pose = pose,
		Character = player.Character,
		ResetGeneration = Workspace:GetAttribute("Phase12CycleId"),
		EligibilityRevision = data.Phase13.EligibilityRevision,
		Sequence = data.Phase13.OperationSequence + 1,
	},
		nil
end
local function comparisonDescription(data: any, record: any): any?
	local mutation = Phase12Rules.RecordMutation(record)
	local values = mutation and Phase12Rules.EffectiveValues(record.BrainrotId, mutation)
	local definition = BrainrotCatalog.Get(record.BrainrotId)
	if not values or not definition then
		return nil
	end
	local equipped = false
	for _, id in data.ChariotTeam.Assignments do
		if id == record.ItemId then
			equipped = true
		end
	end
	local effect = TeamRules.Individual(definition, record.BrainrotId)
	return {
		effect = if effect.valid then effect.effect else "Unavailable",
		effectValue = if effect.valid then EffectText.Value(effect.effect, effect.contribution) else "Unavailable",
		individualId = record.ItemId,
		name = definition.displayName,
		rarity = definition.tier,
		mutation = mutation,
		cashPerSecond = values.cashPerSecond,
		productionCashPerSecond = values.cashPerSecond
			* require(ReplicatedStorage.Shared.Utility.Phase13CommerceRules).ProductionMultiplier(data),
		sellValue = values.sellValue,
		equipped = equipped,
	}
end
function BrainrotInteractionSystem.PreviewPlatformSwap(player: Player, platform: any, incomingId: any): any
	local context, reason = comparisonContext(player, platform, incomingId)
	if not context then
		return { ok = false, code = reason }
	end
	local data = PlayerDataService:GetReadableData(player)
	local outgoing = comparisonDescription(data, context.Outgoing)
	local incoming = comparisonDescription(data, context.Entry.Record)
	if not outgoing or not incoming then
		return { ok = false, code = "INVALID_MUTATION" }
	end
	context.Token, context.ExpiresAt = HttpService:GenerateGUID(false), Workspace:GetServerTimeNow() + 20
	comparisonPreviews[player] = context
	return {
		ok = true,
		token = context.Token,
		current = outgoing,
		incoming = incoming,
		incomeChange = incoming.productionCashPerSecond - outgoing.productionCashPerSecond,
		baseIncomeChange = incoming.cashPerSecond - outgoing.cashPerSecond,
		previewRevision = context.EligibilityRevision,
	}
end
function BrainrotInteractionSystem.CommitPlatformSwap(player: Player, token: any, action: any, operationId: any): any
	local context = comparisonPreviews[player]
	if not context or token ~= context.Token or context.ExpiresAt < Workspace:GetServerTimeNow() then
		return { ok = false, code = "STALE_PREVIEW" }
	end
	if action ~= "Swap" and action ~= "SellAndReplace" then
		return { ok = false, code = "INVALID_ACTION" }
	end
	if type(operationId) ~= "string" or #operationId < 8 or #operationId > 128 then
		return { ok = false, code = "INVALID_OPERATION" }
	end
	local current, reason = comparisonContext(player, context.Platform, context.Entry.Record.ItemId)
	if
		not current
		or current.Entry ~= context.Entry
		or current.Outgoing.ItemId ~= context.Outgoing.ItemId
		or current.EligibilityRevision ~= context.EligibilityRevision
	then
		return { ok = false, code = reason or "STALE_PREVIEW" }
	end
	local entry, deps = context.Entry, dependencies
	local outgoingRecord, visual, prepared = context.Outgoing, nil, nil
	if action == "Swap" then
		local ok = pcall(function()
			if outgoingRecord.World == nil then
				local restored, why = deps.World.CreateRestoredWorldRecord(outgoingRecord, context.Pose)
				assert(restored, why)
				outgoingRecord = restored
			end
			visual = prepareCarryVisual(outgoingRecord)
			assert(visual, "CARRY_VISUAL_UNAVAILABLE")
			local why
			prepared, why = deps.World.PrepareWorldRepresentation(outgoingRecord, context.Pose)
			assert(prepared, why)
			outgoingRecord = prepared.Record or outgoingRecord
		end)
		if not ok then
			if visual then
				visual.Model:Destroy()
			end
			if prepared then
				deps.World.DiscardPreparedWorld(prepared)
			end
			return { ok = false, code = "PREPARATION_FAILED" }
		end
	end
	local function discardPrepared()
		if visual then
			visual.Model:Destroy()
			visual = nil
		end
		if prepared then
			deps.World.DiscardPreparedWorld(prepared)
			prepared = nil
		end
	end
	local function reconcileIncoming(saving: boolean): boolean
		if player.Parent ~= Players then
			return true
		end
		if not BaseStorageSystem:ReconcilePlayerFromProfile(player) then
			return false
		end
		local storage = BaseStorageSystem:GetStorageForPlayer(player)
		local slots = storage and BaseStorageSystem:GetRegisteredPlatforms(storage.Base)
		local slot = slots and slots[context.Slot.Index]
		local record = storage and storage:GetPlatformRecord(context.Slot.Index)
		local display = storage and storage:GetPlatformDisplay(context.Slot.Index)
		if
			not slot
			or not slot.Platform.Parent
			or not record
			or record.ItemId ~= entry.Record.ItemId
			or not display
			or not display.Parent
		then
			return false
		end
		slot.Platform:SetAttribute("PendingBank", if saving then true else nil)
		display:SetAttribute("PendingBank", if saving then true else nil)
		context.FinalStorage, context.FinalSlot = storage, slot
		return true
	end

	local recovered = false
	local function recoverStaging(_canonicalData)
		recovered = true
		discardPrepared()
		comparisonPreparations[player], comparisonPreviews[player], comparisonRecoveries[player] = nil, nil, nil
		if carriedByUserId[player.UserId] == entry then
			entry.Busy = false
		end
		return true
	end
	comparisonRecoveries[player] = recoverStaging
	comparisonPreparations[player] = discardPrepared
	entry.Busy = true
	local consumed, outgoingInstalled = false, false
	local response = Phase13Service:CommitPlatformSwap(player, {
		operationId = operationId,
		sequence = context.Sequence,
		previewRevision = context.EligibilityRevision,
		slotIndex = context.Slot.Index,
		outgoingId = context.Outgoing.ItemId,
		incomingRecord = entry.Record,
		incomingFresh = type(entry.Record.Metadata.DurableOwnerUserId) ~= "number",
		ownerUserId = player.UserId,
		action = action,
	}, {
		validate = function(data)
			local root = entry.Root
			if
				dependencies ~= deps
				or carriedByUserId[player.UserId] ~= entry
				or entry.Returning
				or player.Character ~= context.Character
				or root.Parent ~= context.Character
				or (root.Position - context.Pose.Position).Magnitude > InteractionConfig.PLACEMENT_INTERACT_RADIUS + InteractionConfig.PLACEMENT_SERVER_TOLERANCE
				or Workspace:GetAttribute("Phase12ResetCommitting") == true
				or Workspace:GetAttribute("Phase12CycleId") ~= context.ResetGeneration
				or not context.Storage:GetPlatformRecord(context.Slot.Index)
				or context.Storage:GetPlatformRecord(context.Slot.Index).ItemId ~= context.Outgoing.ItemId
			then
				return false, "CONTEXT_CHANGED"
			end
			local head = context.Character:FindFirstChild("Head")
			local origin = if head and head:IsA("BasePart") then head.Position else root.Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { context.Character }
			local hit = Workspace:Raycast(origin, context.Pose.Position - origin, params)
			if hit and hit.Instance ~= context.Platform and not hit.Instance:IsDescendantOf(context.Platform) then
				return false, "OBSTRUCTED"
			end
			if BaseStorageSystem:GetStorageForPlayer(player) ~= context.Storage then
				return false, "NOT_OWNER"
			end
			return data.Phase13.EligibilityRevision == context.EligibilityRevision, "STALE_PREVIEW"
		end,
		onRecovered = function(_result, canonicalData)
			return recoverStaging(canonicalData)
		end,
		onCommitted = function(_result, _revision)
			if recovered then
				return false
			end
			if not consumed then
				if carriedByUserId[player.UserId] ~= entry then
					return false
				end
				retireCommittedCarry(entry)
				consumed = true
			end
			return reconcileIncoming(true)
		end,
		onConfirmed = function(_result, detached)
			if recovered then
				return false
			end
			if detached then
				discardPrepared()
				comparisonPreparations[player] = nil
				comparisonPreviews[player] = nil
				comparisonRecoveries[player] = nil
				return consumed -- durable unassigned outgoing ownership is restored on rejoin
			end
			if not consumed or not reconcileIncoming(true) then
				return false
			end
			if action == "Swap" and not outgoingInstalled then
				local character, humanoid, root = livingCharacter(player)
				if character == context.Character and humanoid and root and carriedByUserId[player.UserId] == nil then
					local restoredEntry =
						newCarryEntry(player, character, root, outgoingRecord, visual, prepared, context.Pose)
					local installed = pcall(installCarryPresentation, restoredEntry, humanoid)
					if not installed then
						return false
					end
					carriedByUserId[player.UserId] = restoredEntry
					restoredEntry.Busy = false
					BrainrotDisplayMetadata.Apply(
						visual.Model,
						outgoingRecord,
						BrainrotDisplayConfig.States.Carried,
						player.UserId
					)
					player:SetAttribute("CarriedItemId", outgoingRecord.ItemId)
					visual, prepared = nil, nil
					carryChanged:Fire(player)
				else
					-- A dead/replaced avatar cannot receive a welded carry. The original is
					-- still owned; publish its staged secured owner-only sleeper at the base.
					local marker = context.FinalSlot.Marker
					local destination = if marker:IsA("Attachment") then marker.WorldCFrame else marker.CFrame
					local safePose = deps.World.FindSafeReleasePose(prepared, destination, {}, true)
					if not safePose then
						return false
					end
					prepared.Model:PivotTo(safePose)
					local model = deps.World.ActivatePreparedWorld(prepared)
					if not model then
						return false
					end
					prepared = nil
					if visual then
						visual.Model:Destroy()
						visual = nil
					end
				end
				outgoingInstalled = true
			end
			if not reconcileIncoming(false) then
				return false
			end
			comparisonPreparations[player] = nil
			comparisonPreviews[player] = nil
			comparisonRecoveries[player] = nil
			-- The confirmed critical receipt is the sole SwapOutcome producer.
			return true
		end,
	})
	if response.ok ~= true then
		entry.Busy = false
		comparisonPreparations[player] = nil
		comparisonRecoveries[player] = nil
		discardPrepared()
	end
	return response
end

local function validatePlacement(player: Player, platform: any, expectedId: any): (CarryEntry?, string?)
	local entry, sourceReason = validateCarriedSource(player, expectedId)
	if not entry then
		return nil, sourceReason
	end
	local slot, storage, reason = BaseStorageSystem:ResolvePlatform(player, platform)
	if not slot then
		return nil, reason
	end
	if storage:GetPlatformRecord(slot.Index) ~= nil then
		return nil, "OCCUPIED"
	end
	local position = if slot.Marker:IsA("Attachment") then slot.Marker.WorldPosition else slot.Marker.Position
	local reachable, reachReason = canReach(
		player,
		position,
		platform,
		InteractionConfig.PLACEMENT_INTERACT_RADIUS + InteractionConfig.PLACEMENT_SERVER_TOLERANCE
	)
	if not reachable then
		return nil, reachReason
	end
	return entry, nil
end

-- Consumes the exact carried individual without invoking the world-return path.
-- The optional commit callback runs while this carry entry is locked. A rejected
-- callback leaves the record, visual and return insurance untouched, which lets
-- a transaction owner make an external non-yielding mutation before consumption.
function BrainrotInteractionSystem.ConsumeCarriedBrainrot(
	player: Player,
	expectedIndividualId: any,
	reason: any,
	commit: ((any) -> (boolean, string?))?
): (any?, string?)
	if type(reason) ~= "string" or reason == "" then
		return nil, "INVALID_REASON"
	end
	local entry, sourceReason = validateCarriedSource(player, expectedIndividualId)
	if not entry then
		return nil, sourceReason
	end
	if entry.Busy then
		return nil, "BUSY"
	end
	entry.Busy = true
	if commit then
		local called, committed, commitReason = pcall(commit, entry.Record)
		if not called or committed ~= true then
			entry.Busy = false
			return nil, if called then (commitReason or "COMMIT_REJECTED") else tostring(committed)
		end
	end
	-- No yield occurs between exact-source validation, the optional authority
	-- commit and clearing the sole carry owner.
	if carriedByUserId[player.UserId] ~= entry then
		entry.Busy = false
		return nil, "SOURCE_CHANGED"
	end
	carriedByUserId[player.UserId] = nil
	entry.Busy = false
	retireCommittedCarry(entry)
	return entry.Record, nil
end

function BrainrotInteractionSystem.TryPlaceOnPlatform(
	player: Player,
	platform: any,
	expectedCarriedId: any
): (boolean, string?)
	local entry, reason = validatePlacement(player, platform, expectedCarriedId)
	if not entry then
		return false, reason
	end
	if entry.Busy then
		return false, "BUSY"
	end
	entry.Busy = true
	local token, committed = nil, false
	local ok, failure = xpcall(function()
		token, reason = BaseStorageSystem:PrepareStoreAtPlatform(player, platform, entry.Record)
		if not token then
			return
		end
		-- Preparation may yield. Repeat life, ownership, exact slot, reach and ID
		-- checks before the non-yielding destination/source commit boundary.
		local current
		current, reason = validatePlacement(player, platform, expectedCarriedId)
		if current ~= entry then
			return
		end
		committed, reason = BaseStorageSystem:CommitPlatformPlacement(token)
		if committed then
			carriedByUserId[player.UserId] = nil
		end
	end, debug.traceback)
	entry.Busy = false
	if committed then
		-- No world-release helper: placement does not wake, spawn or reward a new
		-- individual. Retire only this carry representation and dormant insurance.
		retireCommittedCarry(entry)
	end
	-- Income callbacks see the final destination and an already-empty source.
	if token then
		BaseStorageSystem:FinishPlatformPlacement(token)
	end
	if not ok then
		warn("[Place] Transfer error: " .. tostring(failure))
	end
	if committed then
		local bankedAt = Workspace:GetServerTimeNow()
		notifyCommitted(player, {
			kind = "BankedPlaced",
			mutationId = require(script.Parent.Parent.Data.Phase12Progress).MutationId(entry.Record),
			eventId = "banked:" .. entry.Record.ItemId .. ":" .. tostring(platform) .. ":" .. tostring(bankedAt),
			at = bankedAt,
			individualId = entry.Record.ItemId,
			speciesId = entry.Record.BrainrotId,
		})
	end
	return committed, if committed then nil else (reason or "PREPARATION_FAILED")
end

local function validateCargoPlacement(player: Player, cart: any, slotId: any, expectedId: any): (CarryEntry?, string?)
	local entry, reason = validateCarriedSource(player, expectedId)
	if not entry then
		return nil, reason
	end
	if not CartCargoService:CanPlayerHandleCargo(player, cart) then
		return nil, "NOT_OWNER"
	end
	local slot, attachment = CartCargoService:ResolveCargoSlot(cart, slotId)
	if not slot or not attachment then
		return nil, "INVALID_SLOT"
	end
	if CartCargoService:GetSlotRecord(cart, slotId) then
		return nil, "OCCUPIED"
	end
	local reachable, reachReason = canReachCargo(player, attachment.WorldPosition, cart)
	if not reachable then
		return nil, reachReason
	end
	return entry, nil
end

function BrainrotInteractionSystem.TryPlaceInCargo(
	player: Player,
	cart: any,
	slotId: any,
	expectedCarriedId: any
): (boolean, string?)
	local entry, reason = validateCargoPlacement(player, cart, slotId, expectedCarriedId)
	if not entry then
		return false, reason
	end
	if entry.Busy then
		return false, "BUSY"
	end
	entry.Busy = true
	local token, committed = nil, false
	local ok, failure = xpcall(function()
		token, reason = CartCargoService:PrepareInsertAtSlot(player, cart, slotId, entry.Record)
		if not token then
			return
		end
		local current
		current, reason = validateCargoPlacement(player, cart, slotId, expectedCarriedId)
		if current ~= entry then
			return
		end
		-- No yields between exact-slot commit and retiring the sole carried owner.
		committed, reason = CartCargoService:CommitInsertAtSlot(token)
		if committed then
			carriedByUserId[player.UserId] = nil
		end
	end, debug.traceback)
	entry.Busy = false
	if committed then
		-- Retire first: a presentation error in MarkFreshTransit must never leave CarriedItemId set
		-- on a player whose brainrot is already in cargo (Playtest Fixes 2, A4).
		retireCommittedCarry(entry)
		local world = (dependencies :: Dependencies).World
		if type(world.MarkFreshTransit) == "function" then
			local marked, markError = pcall(world.MarkFreshTransit, entry.Record, "Cargo")
			if not marked then
				warn("[Cargo] MarkFreshTransit: " .. tostring(markError))
			end
		end
	end
	if token then
		CartCargoService:FinishInsertAtSlot(token)
	end
	if not ok then
		warn("[Cargo] Carry transfer error: " .. tostring(failure))
	end
	if committed then
		local cargoAt = Workspace:GetServerTimeNow()
		notifyCommitted(player, {
			kind = "CargoPlaced",
			eventId = "cargo:" .. entry.Record.ItemId .. ":" .. tostring(slotId) .. ":" .. tostring(cargoAt),
			at = cargoAt,
			individualId = entry.Record.ItemId,
			speciesId = entry.Record.BrainrotId,
		})
	end
	return committed, if committed then nil else (reason or "PREPARATION_FAILED")
end

-- Drive-by haul (owner decision, 10 Nov 2026): a sleeping brainrot beside the
-- owner's driven cart goes straight into a free cargo slot, and cargo banks onto
-- free platforms on arrival at the owner's base. Both are server-decided; the
-- client never names a target. No carry entry is created, so the driver keeps
-- control. Existing ownership, region and cargo rules are reused unchanged.
-- `shape` (Drive-and-Hunt Part D, optional) measures reach from the cart's edge; the vertical limit stays `radius`.
local function validateScoop(player: Player, cart: any, model: any, radius: number, shape: any?): (any?, string?)
	local deps = dependencies
	if not deps then
		return nil, "NOT_STARTED"
	end
	local allowed, actionReason = canAct(player)
	if not allowed then
		return nil, actionReason or "DAZED"
	end
	if savedForOther(player, model) then
		return nil, "SAVED_FOR_OWNER"
	end
	local character = livingCharacter(player)
	if not character then
		return nil, "NOT_LIVING"
	end
	if carriedByUserId[player.UserId] then
		return nil, "ALREADY_CARRYING"
	end
	if not deps.IsDriving(player) or not CartCargoService:CanPlayerHandleCargo(player, cart) then
		return nil, "NOT_OWNER"
	end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil, "INVALID_TARGET"
	end
	local record, state = deps.World.GetWorldRecord(model)
	if not record or state ~= "WorldSleeping" then
		return nil, "NOT_SLEEPING_WORLD"
	end
	local durableOwner = record.Metadata.DurableOwnerUserId
	if type(durableOwner) == "number" then
		if durableOwner ~= player.UserId then
			return nil, "BANKED_PROTECTED"
		end
		if deps.Banked and deps.Banked:GetOwnedIndividual(player, record.ItemId) == nil then
			return nil, "OWNERSHIP_CHANGED"
		end
	end
	local body = model:FindFirstChild("Body", true)
	if not body or not body:IsA("BasePart") then
		return nil, "INVALID_TARGET"
	end
	local offset = body.Position - cart:GetPivot().Position
	local inReach
	if shape then
		local localPoint = cart:GetPivot():PointToObjectSpace(body.Position)
		inReach = require(ReplicatedStorage.Shared.Utility.DriveAndHuntRules).InScoopReach(shape, localPoint.X, localPoint.Z)
	else
		inReach = Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius
	end
	if not finitePosition(body.Position) or not inReach or math.abs(offset.Y) > radius then
		return nil, "OUT_OF_REACH"
	end
	if regionAccessValidator then
		local regionAllowed, accessReason = regionAccessValidator(player, model)
		if not regionAllowed then
			return nil, accessReason or "RegionAccessRequired"
		end
	end
	return record, nil
end

function BrainrotInteractionSystem.TryScoopIntoCargo(player: Player, cart: any, model: any, radius: number, shape: any?): (boolean, string?)
	local record, reason = validateScoop(player, cart, model, radius, shape)
	if not record then
		return false, reason
	end
	local deps = dependencies :: Dependencies
	if not CartCargoService:CanAcceptCargo(cart) then
		return false, "NO_SPACE"
	end
	local slotId: string? = nil
	for index = 1, CartCargoService:GetCargoCapacity(cart) do
		local candidate = "Slot" .. index
		if CartCargoService:ResolveCargoSlot(cart, candidate) and not CartCargoService:GetSlotRecord(cart, candidate) then
			slotId = candidate
			break
		end
	end
	if not slotId then
		return false, "NO_SPACE"
	end
	local phaseState = if deps.World.GetPhase12State then deps.World.GetPhase12State(record) else nil
	local fresh = type(record.Metadata.DurableOwnerUserId) ~= "number"
	local acquisitionKind = if phaseState
			and (
				(phaseState.LastSecuredByUserId ~= nil and phaseState.LastSecuredByUserId ~= player.UserId)
				or (phaseState.LastSecuredByUserId == player.UserId and phaseState.AcquisitionKind == "Theft")
				or (phaseState.LastReleaseKind == "Theft" and phaseState.LastTheftAttackerUserId == player.UserId)
			)
		then "Theft"
		else "Hunt"
	local controlled = record
	if type(deps.World.CreatePlayerControlledRecord) == "function" then
		local cleared, clearReason = deps.World.CreatePlayerControlledRecord(record)
		if cleared == nil then
			return false, clearReason or "PREPARATION_FAILED"
		end
		controlled = cleared
	end
	local sourcePose = model:GetPivot()
	local insurance: any? = nil
	local token
	token, reason = CartCargoService:PrepareInsertAtSlot(player, cart, slotId, controlled)
	if not token then
		return false, reason or "PREPARATION_FAILED"
	end
	local committed, taken = false, false
	local ok, failure = xpcall(function()
		-- Dormant same-record world copy: only used if the slot commit fails after
		-- the world source has been taken.
		insurance = deps.World.PrepareWorldRepresentation(controlled, sourcePose)
		if not insurance then
			reason = "PREPARATION_FAILED"
			return
		end
		local current
		current, reason = validateScoop(player, cart, model, radius, shape)
		if current ~= record then
			reason = reason or "SOURCE_CHANGED"
			return
		end
		-- No yields from here through the slot commit.
		local committedRecord
		taken, committedRecord = deps.World.TakeSleepingWorld(model, record, controlled)
		if not taken then
			reason = "SOURCE_CHANGED"
			return
		end
		record = committedRecord or controlled
		committed, reason = CartCargoService:CommitInsertAtSlot(token)
	end, debug.traceback)
	if committed then
		if type(deps.World.MarkFreshTransit) == "function" then
			deps.World.MarkFreshTransit(record, "Cargo")
		end
		model:Destroy()
	elseif taken and insurance then
		local restored = pcall(function()
			insurance.Model:PivotTo(sourcePose)
			assert(deps.World.ActivatePreparedWorld(insurance), "world restore rejected")
		end)
		if restored then
			insurance = nil
			model:Destroy()
		else
			warn("[Scoop] Could not restore " .. record.ItemId .. " after a failed cargo commit")
		end
	end
	CartCargoService:FinishInsertAtSlot(token)
	if insurance then
		deps.World.DiscardPreparedWorld(insurance)
	end
	if not ok then
		warn("[Scoop] Transfer error: " .. tostring(failure))
	end
	if not committed then
		return false, reason or "PREPARATION_FAILED"
	end
	pcall(Analytics.Record, Analytics, player, "AcquisitionAttempt", 1, {
		category = if fresh then acquisitionKind else "OwnedMove",
		result = "Success",
	})
	if phase12PickupObserver then
		pcall(phase12PickupObserver, player, record, nil)
	end
	local at = Workspace:GetServerTimeNow()
	local firstAcquisition = false
	if fresh then
		local previous = phaseState and phaseState.LastSecuredByUserId
		if deps.World.UpdatePhase12State then
			deps.World.UpdatePhase12State(
				record,
				{ LastSecuredByUserId = player.UserId, LastReleaseKind = "Secured", AcquisitionKind = acquisitionKind }
			)
		end
		if previous ~= player.UserId then
			pcall(Analytics.ObserveSecuredAcquisition, Analytics, player, acquisitionKind, record.ItemId)
			pcall(Analytics.Funnel, Analytics, player, "EarlyJourney", 2)
			pcall(Analytics.Funnel, Analytics, player, if acquisitionKind == "Theft" then "TheftBranch" else "HuntBranch", 3)
		end
		firstAcquisition = not Phase10.Enabled
			or type(deps.World.MarkFirstAcquisition) ~= "function"
			or deps.World.MarkFirstAcquisition(record)
	end
	notifyCommitted(player, {
		kind = if not fresh then "BankedAcquired" elseif firstAcquisition then "WildAcquired" else "LooseSecured",
		eventId = (if firstAcquisition then "wild-acquired:" else "loose-secured:") .. record.ItemId .. ":" .. tostring(at),
		at = at,
		individualId = record.ItemId,
		speciesId = record.BrainrotId,
	})
	notifyCommitted(player, {
		kind = "CargoPlaced",
		eventId = "cargo:" .. record.ItemId .. ":" .. slotId .. ":" .. tostring(at),
		at = at,
		individualId = record.ItemId,
		speciesId = record.BrainrotId,
	})
	return true, nil
end

-- Banks one cargo individual onto the owner's first free platform through the
-- existing reversible cargo-to-storage transfer (durable first-bank included).
function BrainrotInteractionSystem.TryBankCargoItem(player: Player, cart: any, itemId: string): (boolean, string?)
	if not dependencies or not CartCargoService:CanPlayerHandleCargo(player, cart) then
		return false, "NOT_OWNER"
	end
	local allowed, actionReason = canAct(player)
	if not allowed then
		return false, actionReason or "DAZED"
	end
	local item = CartCargoService:GetCargoItem(cart, itemId)
	local storage = BaseStorageSystem:GetStorageForPlayer(player)
	if not item or not storage then
		return false, if item then "INVALID_CONTEXT" else "NOT_IN_CARGO"
	end
	local result = BaseStorageSystem:TryDepositItem(player, cart, itemId, storage)
	if not result or result.ok ~= true then
		return false, result and result.code or "INTERNAL_ERROR"
	end
	local at = Workspace:GetServerTimeNow()
	notifyCommitted(player, {
		kind = "BankedPlaced",
		mutationId = require(script.Parent.Parent.Data.Phase12Progress).MutationId(item),
		eventId = "banked:" .. item.ItemId .. ":" .. tostring(result.slotIndex) .. ":" .. tostring(at),
		at = at,
		individualId = item.ItemId,
		speciesId = item.BrainrotId,
	})
	return true, nil
end

local function validateCargoReplacement(
	player: Player,
	cart: any,
	slotId: any,
	oldId: any,
	incomingId: any
): (CarryEntry?, any?, string?)
	local entry, reason = validateCarriedSource(player, incomingId)
	if not entry then
		return nil, nil, reason
	end
	if not CartCargoService:CanPlayerHandleCargo(player, cart) then
		return nil, nil, "NOT_OWNER"
	end
	local slot, attachment = CartCargoService:ResolveCargoSlot(cart, slotId)
	if not slot or not attachment then
		return nil, nil, "INVALID_SLOT"
	end
	local old = CartCargoService:GetSlotRecord(cart, slotId)
	if not old or type(oldId) ~= "string" or old.ItemId ~= oldId then
		return nil, nil, "STALE_ID"
	end
	if old.ItemId == entry.Record.ItemId then
		return nil, nil, "SAME_INDIVIDUAL"
	end
	local full, fullReason = CartCargoService:CanReplaceCargo(cart)
	if not full then
		return nil, nil, fullReason
	end
	local reachable, reachReason = canReachCargo(player, attachment.WorldPosition, cart)
	if not reachable then
		return nil, nil, reachReason
	end
	return entry, old, nil
end

function BrainrotInteractionSystem.TryReplaceCargo(
	player: Player,
	cart: any,
	slotId: any,
	expectedOldId: any,
	expectedCarriedId: any
): (boolean, string?)
	if player.Parent ~= Players then
		return false, "NOT_LIVING"
	end
	local now = os.clock()
	if now < (nextReplaceAt[player] or 0) then
		return false, "RATE_LIMITED"
	end
	nextReplaceAt[player] = now + 0.6 -- Completed requests only; a hold is not authorization.
	local entry, old, reason = validateCargoReplacement(player, cart, slotId, expectedOldId, expectedCarriedId)
	if not entry or not old then
		return false, reason
	end
	if entry.Busy then
		return false, "BUSY"
	end
	entry.Busy = true
	local deps = dependencies :: Dependencies
	local token, preparedWorld, committed = nil, nil, false
	local ok, failure = xpcall(function()
		token, reason = CartCargoService:PrepareReplaceAtSlot(player, cart, slotId, expectedOldId, entry.Record)
		if not token then
			return
		end
		preparedWorld, reason = deps.World.PrepareWorldRepresentation(old, cart:GetPivot())
		if not preparedWorld then
			return
		end
		local current, occupant
		current, occupant, reason = validateCargoReplacement(player, cart, slotId, expectedOldId, expectedCarriedId)
		if current ~= entry or occupant ~= old or dependencies ~= deps then
			return
		end
		local mounted
		mounted, reason = CartCargoService:MountPreparedReplacement(token)
		if not mounted then
			return
		end
		-- Recompute beside the current cart AFTER all clone preparation, never at
		-- the hold-start position. The cart is excluded from transit only, not ground
		-- support or destination overlap checks. No distant/void fallback is allowed.
		local cartPose = cart:GetPivot()
		local pose = deps.World.FindSafeReleasePose(preparedWorld, cartPose, {}, false, cart, cart)
		if not pose then
			reason = "NO_SAFE_POSE"
			return
		end
		preparedWorld.Model:PivotTo(pose)
		local released, releaseReason = deps.World.ActivatePreparedWorld(preparedWorld, function()
			local source, target, changed =
				validateCargoReplacement(player, cart, slotId, expectedOldId, expectedCarriedId)
			if source ~= entry or target ~= old or dependencies ~= deps or cart:GetPivot() ~= cartPose then
				reason = changed or "SOURCE_CHANGED"
				return false
			end
			-- This callback is table-only and MUST NOT yield. The world owner has
			-- already staged registration, but has not published it to observers.
			committed, reason = CartCargoService:CommitReplaceAtSlot(token)
			if committed then
				carriedByUserId[player.UserId] = nil
			end
			return committed
		end)
		if not released and not committed then
			reason = reason or releaseReason
		end
	end, debug.traceback)
	entry.Busy = false
	if committed then
		retireCommittedCarry(entry) -- first, see the cargo insert path above (A4)
		if type(deps.World.MarkFreshTransit) == "function" then
			local marked, markError = pcall(deps.World.MarkFreshTransit, entry.Record, "Cargo")
			if not marked then
				warn("[Cargo] MarkFreshTransit: " .. tostring(markError))
			end
		end
	elseif preparedWorld then
		deps.World.DiscardPreparedWorld(preparedWorld) -- Only unused staging, never a published individual.
	end
	if token then
		local finished, finishError = pcall(CartCargoService.FinishInsertAtSlot, CartCargoService, token)
		if not finished then
			finished, finishError = pcall(CartCargoService.FinishInsertAtSlot, CartCargoService, token)
		end
		if not finished then
			warn("[Replace] Committed=" .. tostring(committed) .. " presentation: " .. tostring(finishError))
		end
	end
	if not ok then
		warn("[Replace] Transfer error: " .. tostring(failure))
	end
	return committed, if committed then nil else (reason or "PREPARATION_FAILED")
end

local function guardedRequest(player, token, signature, expectedRevision, individualId, commit)
	return requestGate.Execute(player, token, signature, function()
		local replication = require(script.Parent.Parent.Services.CreatureReplicationService)
		if expectedRevision ~= nil and replication:GetPresentationRevision(individualId) ~= expectedRevision then
			return false, "STALE_REVISION"
		end
		local success, reason = commit()
		if success then
			replication:Step(false)
		end
		return success, reason
	end)
end

local function validRequestToken(token: any): boolean
	-- Correlation only, never authorization. Nil preserves existing callers.
	return token == nil or (type(token) == "string" and #token <= 96)
end

local function removePrompt(model: Model)
	local prompt = promptByModel[model]
	if prompt then
		promptByModel[model], targetByPrompt[prompt] = nil, nil
		prompt:Destroy()
	end
end

local function refreshPrompt(model: Model)
	local deps = dependencies :: Dependencies
	local record, state = deps.World.GetWorldRecord(model)
	if not record or state ~= "WorldSleeping" then
		removePrompt(model)
		return
	end
	if promptByModel[model] then
		return
	end
	local body = model:FindFirstChild("Body", true)
	if not body or not body:IsA("BasePart") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "BrainrotPickup", "Pick up", record.BrainrotId
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.HoldDuration, prompt.MaxActivationDistance = 0, REACH
	prompt.RequiresLineOfSight, prompt.ClickablePrompt = false, true
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt:SetAttribute("ItemId", record.ItemId)
	promptByModel[model], targetByPrompt[prompt] = prompt, { Model = model, ItemId = record.ItemId }
	CollectionService:AddTag(prompt, PROMPT_TAG)
	prompt.Parent = body
end

local function unbindCharacterPlayer(player: Player)
	local tracker = characterTrackers[player]
	if tracker then
		disconnectAll(tracker.Connections)
	end
	characterTrackers[player] = nil
	local playerConnections = characterPlayerConnections[player]
	if playerConnections then
		disconnectAll(playerConnections)
	end
	characterPlayerConnections[player] = nil
end

local function bindCharacter(player: Player, character: Model)
	local previous = characterTrackers[player]
	if previous and previous.Character == character then
		return
	end
	if previous then
		-- CharacterAdded may arrive before the old CharacterRemoving callback.
		-- Finish that exact old generation before a new haul can be acquired.
		BrainrotInteractionSystem.HandleCharacterRemoving(player, previous.Character)
		disconnectAll(previous.Connections)
	end
	local tracker: any = {
		Character = character,
		Generation = if previous then previous.Generation + 1 else 1,
		Connections = {},
		Pending = false,
		Humanoid = nil,
	}
	characterTrackers[player] = tracker
	table.insert(
		tracker.Connections,
		character.Destroying:Connect(function()
			if characterTrackers[player] == tracker then
				BrainrotInteractionSystem.HandleCharacterRemoving(player, character)
			end
		end)
	)
	local function attachHumanoid(humanoid: Humanoid)
		if tracker.Humanoid or characterTrackers[player] ~= tracker then
			return
		end
		tracker.Humanoid = humanoid
		table.insert(
			tracker.Connections,
			humanoid.Died:Connect(function()
				if characterTrackers[player] == tracker then
					BrainrotInteractionSystem.HandleCharacterRemoving(player, character)
				end
			end)
		)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		attachHumanoid(humanoid)
	else
		table.insert(
			tracker.Connections,
			character.ChildAdded:Connect(function(child)
				if child:IsA("Humanoid") then
					attachHumanoid(child)
				end
			end)
		)
	end
end

local function bindCharacterPlayer(player: Player)
	if characterPlayerConnections[player] then
		if player.Character then
			bindCharacter(player, player.Character)
		end
		return
	end
	local playerConnections = {}
	characterPlayerConnections[player] = playerConnections
	if player.CharacterAdded then
		table.insert(
			playerConnections,
			player.CharacterAdded:Connect(function(character)
				bindCharacter(player, character)
			end)
		)
	end
	table.insert(
		playerConnections,
		player.CharacterRemoving:Connect(function(character)
			local tracker = characterTrackers[player]
			if tracker and tracker.Character == character then
				BrainrotInteractionSystem.HandleCharacterRemoving(player, character)
			end
		end)
	)
	if player.Character then
		bindCharacter(player, player.Character)
	end
end

-- Disposable real-Humanoid fixture hook; no client/gameplay request calls it.
function BrainrotInteractionSystem._TrackCharacterForTesting(player: Player): boolean
	if not RunService:IsStudio() or game:GetAttribute("BrainrotTestDiagnosticsDisabled") ~= true then
		return false
	end
	bindCharacterPlayer(player)
	return true
end

function BrainrotInteractionSystem.Start(deps: Dependencies)
	if dependencies then
		return
	end
	dependencies = deps
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			if comparisonPreparations[player] then
				comparisonPreparations[player]()
				comparisonPreparations[player] = nil
			end
			comparisonPreviews[player] = nil
			pickupFailureTimes[player] = nil
		end)
	)
	if Phase10.Enabled then
		for _, player in Players:GetPlayers() do
			bindCharacterPlayer(player)
		end
		table.insert(connections, Players.PlayerAdded:Connect(bindCharacterPlayer))
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name, remotes.Parent = "Remotes", ReplicatedStorage
	end
	local compareRemote = remotes:FindFirstChild("Phase13PlatformCompare")
	if not compareRemote then
		compareRemote = Instance.new("RemoteFunction")
		compareRemote.Name = "Phase13PlatformCompare"
		compareRemote.Parent = remotes
	end
	assert(compareRemote:IsA("RemoteFunction"), "Phase13PlatformCompare must be a RemoteFunction")
	compareRemote.OnServerInvoke = function(player, verb, a, b, c)
		if verb == "Preview" then
			return BrainrotInteractionSystem.PreviewPlatformSwap(player, a, b)
		end
		if verb == "Commit" then
			return BrainrotInteractionSystem.CommitPlatformSwap(player, a, b, c)
		end
		if verb == "Status" and type(a) == "string" and #a <= 128 then
			return Phase13Service:GetOperation(player, a)
		end
		return { ok = false, code = "INVALID_REQUEST" }
	end
	local remote = remotes:FindFirstChild(RemoteNames.DropCarriedRequest)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name, remote.Parent = RemoteNames.DropCarriedRequest, remotes
	end
	assert(remote:IsA("RemoteEvent"), "DropCarriedRequest must be a RemoteEvent")
	local dropRemote = remote :: RemoteEvent
	local place = remotes:FindFirstChild(RemoteNames.PlaceCarriedRequest)
	if not place then
		place = Instance.new("RemoteEvent")
		place.Name, place.Parent = RemoteNames.PlaceCarriedRequest, remotes
	end
	assert(place:IsA("RemoteEvent"), "PlaceCarriedRequest must be a RemoteEvent")
	local placeRemote = place :: RemoteEvent
	local load = remotes:FindFirstChild(RemoteNames.LoadCarriedRequest)
	if not load then
		load = Instance.new("RemoteEvent")
		load.Name, load.Parent = RemoteNames.LoadCarriedRequest, remotes
	end
	assert(load:IsA("RemoteEvent"), "LoadCarriedRequest must be a RemoteEvent")
	local loadRemote = load :: RemoteEvent
	local replace = remotes:FindFirstChild(RemoteNames.ReplaceCargoRequest)
	if not replace then
		replace = Instance.new("RemoteEvent")
		replace.Name, replace.Parent = RemoteNames.ReplaceCargoRequest, remotes
	end
	assert(replace:IsA("RemoteEvent"), "ReplaceCargoRequest must be a RemoteEvent")
	local replaceRemote = replace :: RemoteEvent
	table.insert(
		connections,
		replaceRemote.OnServerEvent:Connect(function(player, cart, slotId, oldId, incomingId, token, expectedRevision)
			if not validRequestToken(token) then
				return
			end
			if
				type(slotId) ~= "string"
				or #slotId > 16
				or type(oldId) ~= "string"
				or #oldId > 128
				or type(incomingId) ~= "string"
				or #incomingId > 128
			then
				return
			end
			local success, reason = guardedRequest(
				player,
				token,
				{ "Replace", cart, slotId, oldId, incomingId },
				expectedRevision,
				incomingId,
				function()
					return BrainrotInteractionSystem.TryReplaceCargo(player, cart, slotId, oldId, incomingId)
				end
			)
			replaceRemote:FireClient(player, incomingId, success, reason, token)
		end)
	)
	local pickup = remotes:FindFirstChild(RemoteNames.PickupCargoRequest)
	if not pickup then
		pickup = Instance.new("RemoteEvent")
		pickup.Name, pickup.Parent = RemoteNames.PickupCargoRequest, remotes
	end
	assert(pickup:IsA("RemoteEvent"), "PickupCargoRequest must be a RemoteEvent")
	local pickupRemote = pickup :: RemoteEvent
	table.insert(
		connections,
		pickupRemote.OnServerEvent:Connect(function(player, cart, slotId, expectedId, token, expectedRevision)
			if not validRequestToken(token) then
				return
			end
			if type(expectedId) ~= "string" or #expectedId > 128 or type(slotId) ~= "string" or #slotId > 16 then
				return
			end
			local success, reason = guardedRequest(
				player,
				token,
				{ "Pickup", cart, slotId, expectedId },
				expectedRevision,
				expectedId,
				function()
					return BrainrotInteractionSystem.TryPickupCargo(player, cart, slotId, expectedId)
				end
			)
			pickupRemote:FireClient(player, expectedId, success, reason, token)
		end)
	)
	table.insert(
		connections,
		loadRemote.OnServerEvent:Connect(function(player, cart, slotId, expectedId, token, expectedRevision)
			if not validRequestToken(token) then
				return
			end
			if type(expectedId) ~= "string" or #expectedId > 128 or type(slotId) ~= "string" or #slotId > 16 then
				return
			end
			local success, reason = guardedRequest(
				player,
				token,
				{ "Load", cart, slotId, expectedId },
				expectedRevision,
				expectedId,
				function()
					return BrainrotInteractionSystem.TryPlaceInCargo(player, cart, slotId, expectedId)
				end
			)
			loadRemote:FireClient(player, expectedId, success, reason, token)
		end)
	)
	table.insert(
		connections,
		placeRemote.OnServerEvent:Connect(function(player, platform, expectedId, token, expectedRevision)
			if not validRequestToken(token) then
				return
			end
			if type(expectedId) ~= "string" or #expectedId > 128 then
				return
			end
			local success, reason = guardedRequest(
				player,
				token,
				{ "Base", platform, expectedId },
				expectedRevision,
				expectedId,
				function()
					if BrainrotInteractionSystem.GetCarriedRecord(player) then
						return BrainrotInteractionSystem.TryPlaceOnPlatform(player, platform, expectedId)
					end
					return BrainrotInteractionSystem.TryPickupPlatform(player, platform, expectedId)
				end
			)
			placeRemote:FireClient(player, expectedId, success, reason, token)
		end)
	)
	table.insert(
		connections,
		dropRemote.OnServerEvent:Connect(function(player, expectedId, token, expectedRevision)
			if not validRequestToken(token) then
				return
			end
			if type(expectedId) ~= "string" or #expectedId > 128 then
				return
			end
			local success, reason = guardedRequest(
				player,
				token,
				{ "Drop", expectedId },
				expectedRevision,
				expectedId,
				function()
					return BrainrotInteractionSystem.TryDropCarried(player, expectedId)
				end
			)
			dropRemote:FireClient(player, expectedId, success, reason, token)
		end)
	)
	table.insert(connections, deps.World.WorldChanged:Connect(refreshPrompt))
	for _, model in deps.World.GetWorldModels() do
		refreshPrompt(model)
	end
	-- Native prompt activation is the single request path; no extra client remote.
	table.insert(
		connections,
		ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
			local target = targetByPrompt[prompt]
			if not target or not prompt:IsDescendantOf(target.Model) then
				return
			end
			local ok, reason = BrainrotInteractionSystem.TryPickupWorld(player, target.Model, target.ItemId)
			pickupRemote:FireClient(player, target.ItemId, ok, reason, "native:" .. target.ItemId)
			if not ok then
				print("[Carry] Reject: " .. tostring(reason))
			end
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			nextReplaceAt[player] = nil
			unbindCharacterPlayer(player)
		end)
	)
	local elapsed = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.25 then
				return
			end
			elapsed = 0
			for player, tracker in characterTrackers do
				if tracker.Pending then
					BrainrotInteractionSystem.HandleCharacterRemoving(player, tracker.Character)
				end
			end
			local currentDeps = dependencies
			if
				currentDeps
				and currentDeps.Banked
				and type(currentDeps.Banked.ProcessConfirmedReleases) == "function"
			then
				currentDeps.Banked:ProcessConfirmedReleases()
			end
			for _, entry in carriedByUserId do
				if entry.Busy then
					continue
				end
				if entry.Returning then
					if os.clock() >= entry.RetryAt then
						returnToWorld(entry)
					end
				else
					local character, _, root = livingCharacter(entry.Player)
					local entryHumanoid = entry.Character:FindFirstChildOfClass("Humanoid")
					local visual = entry.Visual
					if
						entry.Player.Character ~= entry.Character
						or entry.Character.Parent == nil
						or not entryHumanoid
						or entryHumanoid.Health <= 0
					then
						-- Death/reset has an explicit policy and must win the race against
						-- presentation cleanup. Fresh records release locally; durable
						-- records retain their protected ownership/restoration policy.
						BrainrotInteractionSystem.HandleCharacterRemoving(entry.Player, entry.Character)
					elseif
						character ~= entry.Character
						or root ~= entry.Root
						or not visual
						or visual.Model.Parent ~= character
						or visual.Root.Parent == nil
						or visual.Weld.Parent == nil
						or not visual.Weld.Enabled
					then
						BrainrotInteractionSystem.HandleUnexpectedCarryCleanup(entry.Player, entry.Character)
					else
						pcall(updateReturnPose, entry)
					end
				end
			end
		end)
	)
end

-- Exact diagnostic-fixture cleanup; not connected to a client request or any
-- gameplay/departure path. A void fixture intentionally has no local destination.
function BrainrotInteractionSystem._DiscardCarryForTesting(player: Player): boolean
	if not RunService:IsStudio() then
		return false
	end
	local entry = carriedByUserId[player.UserId]
	if not entry or entry.Player ~= player then
		return false
	end
	for token, stage in table.clone(heldReleaseTokens) do
		if stage.Entry == entry then
			BrainrotInteractionSystem.DiscardHeldRelease(token)
		end
	end
	retireCommittedCarry(entry)
	return true
end

-- Reset retirement precedes character cleanup and never activates a release.
function BrainrotInteractionSystem:RetireForReset(player: Player, forfeit: boolean, cycleId: number): any
	if not forfeit or not dependencies then
		return { ok = true, retired = {} }
	end
	local entry = carriedByUserId[player.UserId]
	if not entry or entry.Player ~= player then
		return { ok = true, retired = {} }
	end
	if
		type(entry.Record.Metadata.DurableOwnerUserId) == "number"
		or (dependencies.World.IsPendingBank and dependencies.World.IsPendingBank(entry.Record.ItemId))
	then
		return { ok = true, retired = {} }
	end
	if
		dependencies.World.HasOrdinaryReservation and not dependencies.World.HasOrdinaryReservation(entry.Record.ItemId)
	then
		return { ok = true, retired = {} }
	end
	if entry.Busy then
		return { ok = false, code = "BUSY", retired = {} }
	end
	for token, stage in table.clone(heldReleaseTokens) do
		if stage.Entry == entry then
			BrainrotInteractionSystem.DiscardHeldRelease(token)
		end
	end
	local representations = {}
	if entry.Visual and entry.Visual.Model and entry.Visual.Model.Parent then
		local visual = entry.Visual.Model
		local ok, pose, size = pcall(function()
			local cf, sz = visual:GetBoundingBox()
			return cf, sz
		end)
		if ok then
			table.insert(representations, {
				ItemId = entry.Record.ItemId,
				BrainrotId = entry.Record.BrainrotId,
				MutationId = entry.Record.MutationId or entry.Record.Metadata.MutationId or "None",
				Pose = pose,
				Bounds = size,
				SourceGeneration = cycleId,
			})
		end
	end
	local retired, reason = dependencies.World.RetireFreshIndividual(entry.Record, "Phase12Reset:" .. cycleId)
	if not retired then
		return { ok = false, code = reason, retired = {} }
	end
	entry.Returning = true
	carriedByUserId[player.UserId] = nil
	retireCommittedCarry(entry)
	return { ok = true, retired = { entry.Record.ItemId }, Representations = representations }
end

function BrainrotInteractionSystem.Stop(): boolean
	for player, discard in comparisonPreparations do
		discard()
		comparisonPreparations[player] = nil
	end
	table.clear(comparisonPreviews)
	table.clear(pickupFailureTimes)
	for token in table.clone(heldReleaseTokens) do
		BrainrotInteractionSystem.DiscardHeldRelease(token)
	end
	for _, entry in carriedByUserId do
		returnToWorld(entry)
	end
	if next(carriedByUserId) then
		return false
	end -- Keep retrying; never abandon an item.
	disconnectAll(connections)
	for player in characterPlayerConnections do
		unbindCharacterPlayer(player)
	end
	table.clear(departedCargoCharacters)
	for model in promptByModel do
		removePrompt(model)
	end
	dependencies = nil
	table.clear(nextReplaceAt)
	return true
end

function BrainrotInteractionSystem.GetDiagnostics()
	local count, returning, listeners, prompts = 0, 0, 0, 0
	for _, entry in carriedByUserId do
		count += 1
		returning += if entry.Returning then 1 else 0
		listeners += #entry.Connections
	end
	for _ in targetByPrompt do
		prompts += 1
	end
	return table.freeze({
		Carried = count,
		Returning = returning,
		CarryConnections = listeners,
		Prompts = prompts,
		SharedConnections = #connections,
	})
end

return BrainrotInteractionSystem
