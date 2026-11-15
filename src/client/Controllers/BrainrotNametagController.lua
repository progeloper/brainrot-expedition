--!strict

local CreaturePresentation = require(script.Parent.CreaturePresentationController)
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BrainrotBehaviours = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local BrainrotDisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local AppearanceCatalog = require(ReplicatedStorage.Shared.Config.BrainrotAppearanceCatalog)
local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local CamouflageTiming = require(ReplicatedStorage.Shared.Behaviours.CamouflageTiming)
local DecoySplitTiming = require(ReplicatedStorage.Shared.Behaviours.DecoySplitTiming)
local CombatUiRules = require(ReplicatedStorage.Shared.Utility.Phase13CombatUiRules)
local Visibility = require(script.Parent.RegionVisibilityController)
local WeaponStats = require(ReplicatedStorage.Shared.Utility.WeaponStats)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local BrainrotNametagView = require(ReplicatedStorage.Shared.UI.BrainrotNametagView)
local BrainrotCamouflagePresentation = require(ReplicatedStorage.Shared.Utility.BrainrotCamouflagePresentation)
local BrainrotDecoyCuePresentation = require(ReplicatedStorage.Shared.Utility.BrainrotDecoyCuePresentation)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)
local coreLoopOn = require(ReplicatedStorage.Shared.Config.CoreLoopFlags).Enabled()

type Entry = {
	Model: Model,
	View: BrainrotNametagView.View?,
	Connections: { RBXScriptConnection },
	WarnedMissingId: boolean,
	WarnedMissingPart: boolean,
	WarnedCatalogueIds: { [string]: boolean },
	CamouflageSpecies: boolean,
	CamouflageBinding: BrainrotCamouflagePresentation.Binding?,
	DecoySplitSpecies: boolean,
	DecoyCueBinding: BrainrotDecoyCuePresentation.Binding?,
	LastDecoyActive: boolean?,
	LastIdentifyingMetadata: boolean?,
	CombatReadabilityContext: any?,
}

type SnapshotCache = {
	Raw: any,
	Current: CamouflageTiming.Snapshot?,
	HighestRevision: number?,
}

local Exact=require(ReplicatedStorage.Shared.Config.PlaytestExact).Hud
local FirstSessionVisuals=require(ReplicatedStorage.Shared.Config.FirstSessionVisuals)
local FirstSessionRules=require(ReplicatedStorage.Shared.Utility.FirstSessionVisualRules)
local BrainrotNametagController = {}
local log = Logger.new("BrainrotNametagController")
local started = false
local playerGui: PlayerGui? = nil
local entries: { [Model]: Entry } = {}
-- Only active visual schedules need a render update; ordinary world/cargo/base
-- labels remain driven by their existing metadata and lifecycle signals.
local healthEntries: { [Model]: Entry } = {}
local lastHealthRefresh = 0
local animatedEntries: { [Model]: Entry } = {}
local controllerConnections: { RBXScriptConnection } = {}
local focusedModel: Model? = nil
local camouflageSnapshotCache: { [Model]: SnapshotCache } = setmetatable({}, { __mode = "k" }) :: any
local decoySnapshotCache: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any
local supportedStates = {
	[BrainrotDisplayConfig.States.Awake] = true,
	[BrainrotDisplayConfig.States.Sleeping] = true,
	[BrainrotDisplayConfig.States.Carried] = true,
	[BrainrotDisplayConfig.States.Cart] = true,
	[BrainrotDisplayConfig.States.Deposited] = true,
}

local function resolveDisplayState(model: Model): string?
	local displayState = model:GetAttribute(BrainrotDisplayConfig.Attributes.DisplayState)
	if type(displayState) ~= "string" or not supportedStates[displayState] then
		return nil
	end
	-- World sleep ownership also replicates through Captured. Using it for the two
	-- world presentation states closes the brief attribute-replication window in
	-- which an authoritative sleeper could still render as Awake (or vice versa).
	if displayState == BrainrotDisplayConfig.States.Awake or displayState == BrainrotDisplayConfig.States.Sleeping then
		return if model:GetAttribute("Captured") == true
			then BrainrotDisplayConfig.States.Sleeping
			else BrainrotDisplayConfig.States.Awake
	end
	return displayState
end

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function destroyView(entry: Entry)
	if entry.View then
		BrainrotNametagView.destroy(entry.View)
		entry.View = nil
	end
end

local function releaseCamouflageBinding(entry: Entry)
	if entry.CamouflageBinding then
		BrainrotCamouflagePresentation.Unbind(entry.CamouflageBinding)
		entry.CamouflageBinding = nil
	end
	entry.LastIdentifyingMetadata = nil
end

local function releaseDecoyCueBinding(entry: Entry)
	if entry.DecoyCueBinding then
		BrainrotDecoyCuePresentation.Unbind(entry.DecoyCueBinding)
		entry.DecoyCueBinding = nil
	end
end

local function clearFocusedEntry(entry: Entry, retainSleepContext: boolean?)
	if not retainSleepContext then entry.CombatReadabilityContext = nil end
	if focusedModel ~= entry.Model then
		return
	end
	if entry.View then
		BrainrotNametagView.setFocused(entry.View, false)
	end
	focusedModel = nil
end

local function unregisterModel(model: Model)
	healthEntries[model] = nil
	local entry = entries[model]
	if not entry then
		return
	end
	clearFocusedEntry(entry)
	entries[model] = nil
	animatedEntries[model] = nil
	disconnectAll(entry.Connections)
	releaseCamouflageBinding(entry)
	releaseDecoyCueBinding(entry)
	destroyView(entry)
	camouflageSnapshotCache[model] = nil
	decoySnapshotCache[model] = nil
end

local function resolveDisplayPart(model: Model): BasePart?
	local primaryPart = model.PrimaryPart
	if primaryPart and primaryPart:IsDescendantOf(model) then
		return primaryPart
	end
	local body = model:FindFirstChild("Body", true)
	if body and body:IsA("BasePart") then
		return body
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function isAwakeWorldRepresentation(model: Model, displayState: string?): boolean
	if displayState ~= BrainrotDisplayConfig.States.Awake or model:GetAttribute("Captured") == true then
		return false
	end
	local runtime = Workspace:FindFirstChild("Runtime")
	local brainrots = if runtime then runtime:FindFirstChild("Brainrots") else nil
	return (
		model:GetAttribute("CreatureLocalVisual") == true
		and (
			model:GetAttribute("CreatureProtocolState") == "Awake"
			or model:GetAttribute("CreatureProtocolState") == "Sleeping"
		)
	) or (brainrots ~= nil and model.Parent == brainrots)
end

local function resolveCamouflageSnapshot(model: Model): CamouflageTiming.Snapshot?
	local raw = model:GetAttribute(BrainrotDisplayConfig.Attributes.CamouflageSnapshot)
	local cached = camouflageSnapshotCache[model]
	if cached and cached.Raw == raw then
		return cached.Current
	end
	if cached == nil then
		cached = { Raw = nil, Current = nil, HighestRevision = nil }
		camouflageSnapshotCache[model] = cached
	end
	cached.Raw = raw
	local decoded = CamouflageTiming.DecodeSnapshot(raw)
	local itemId = model:GetAttribute("ItemId")
	if decoded == nil or type(itemId) ~= "string" or decoded.runtimeId ~= itemId then
		cached.Current = nil
		return nil
	end
	local highest = cached.HighestRevision
	if highest ~= nil and decoded.revision <= highest then
		return cached.Current
	end
	cached.HighestRevision = decoded.revision
	cached.Current = CamouflageTiming.AcceptNewerSnapshot(cached.Current, decoded)
	return decoded
end

function BrainrotNametagController.getCamouflageSample(
	model: Model,
	nowValue: number?
): (CamouflageTiming.Sample, boolean)
	local definition = BrainrotCatalog.Get(model:GetAttribute(BrainrotDisplayConfig.Attributes.BrainrotId))
	if definition == nil or definition.behaviourId ~= "Camouflage" then
		return CamouflageTiming.Sample({
			runtimeId = "not-camouflage",
			revision = 0,
			active = false,
			cycleStart = nil,
		}, nowValue or 0, BrainrotBehaviours.Camouflage),
			false
	end
	local displayState = resolveDisplayState(model)
	if not isAwakeWorldRepresentation(model, displayState) then
		return CamouflageTiming.Sample({
			runtimeId = "non-wild",
			revision = 0,
			active = false,
			cycleStart = nil,
		}, nowValue or 0, BrainrotBehaviours.Camouflage),
			true
	end
	local snapshot = resolveCamouflageSnapshot(model)
	local currentTime = nowValue or Workspace:GetServerTimeNow()
	return CamouflageTiming.Sample(snapshot, currentTime, BrainrotBehaviours.Camouflage), true
end

local function resolveDecoySplitSnapshot(model: Model): DecoySplitTiming.Snapshot?
	local raw = model:GetAttribute(BrainrotDisplayConfig.Attributes.DecoySplitSnapshot)
	local cached = decoySnapshotCache[model]
	if cached and cached.Raw == raw then
		return cached.Current
	end
	if cached == nil then
		cached = { Raw = nil, Current = nil, HighestRevision = nil }
		decoySnapshotCache[model] = cached
	end
	cached.Raw = raw
	local decoded = DecoySplitTiming.DecodeSnapshot(raw)
	local itemId = model:GetAttribute("ItemId")
	if decoded == nil or type(itemId) ~= "string" or decoded.runtimeId ~= itemId then
		cached.Current = nil
		return nil
	end
	local highest = cached.HighestRevision
	if highest ~= nil and decoded.revision <= highest then
		return cached.Current
	end
	cached.HighestRevision = decoded.revision
	cached.Current = DecoySplitTiming.AcceptNewerSnapshot(cached.Current, decoded)
	return decoded
end

function BrainrotNametagController.getDecoySplitSample(
	model: Model,
	nowValue: number?
): (DecoySplitTiming.Sample, boolean)
	local definition = BrainrotCatalog.Get(model:GetAttribute(BrainrotDisplayConfig.Attributes.BrainrotId))
	if definition == nil or definition.behaviourId ~= "DecoySplit" then
		return DecoySplitTiming.Sample(nil, nowValue or 0, BrainrotBehaviours.DecoySplit), false
	end
	local displayState = resolveDisplayState(model)
	if not isAwakeWorldRepresentation(model, displayState) then
		return DecoySplitTiming.Sample({
			runtimeId = "non-wild",
			revision = 0,
			active = false,
			encounterId = nil,
			startedAt = nil,
			expiresAt = nil,
			decoyCount = 0,
		}, nowValue or 0, BrainrotBehaviours.DecoySplit),
			true
	end
	local snapshot = resolveDecoySplitSnapshot(model)
	return DecoySplitTiming.Sample(snapshot, nowValue or Workspace:GetServerTimeNow(), BrainrotBehaviours.DecoySplit),
		true
end

function BrainrotNametagController.isAimAssistEligible(model: Model, nowValue: number?): boolean
	local definition = BrainrotCatalog.Get(model:GetAttribute(BrainrotDisplayConfig.Attributes.BrainrotId))
	if definition == nil or definition.behaviourId ~= "Camouflage" then
		return true
	end
	local sampled = BrainrotNametagController.getCamouflageSample(model, nowValue)
	return sampled.fullReveal
end

function BrainrotNametagController.isIdentifyingMetadataPermitted(model: Model, nowValue: number?): boolean
	local definition = BrainrotCatalog.Get(model:GetAttribute(BrainrotDisplayConfig.Attributes.BrainrotId))
	if definition and definition.behaviourId == "Camouflage" then
		local camouflage = BrainrotNametagController.getCamouflageSample(model, nowValue)
		return camouflage.fullReveal
	elseif definition and definition.behaviourId == "DecoySplit" then
		local decoySplit = BrainrotNametagController.getDecoySplitSample(model, nowValue)
		return not decoySplit.active
	end
	return true
end

function BrainrotNametagController.getAimResetToken(model: Model, nowValue: number?): string
	local definition = BrainrotCatalog.Get(model:GetAttribute(BrainrotDisplayConfig.Attributes.BrainrotId))
	if definition == nil or definition.behaviourId ~= "DecoySplit" then
		return ""
	end
	local sampled = BrainrotNametagController.getDecoySplitSample(model, nowValue)
	return if sampled.active then sampled.encounterId or "" else ""
end

local function updateViewEnabled(entry: Entry, identifyingMetadata: boolean)
	local view = entry.View
	if view == nil then
		return
	end
	local displayState = resolveDisplayState(entry.Model)
	local carrierValue = entry.Model:GetAttribute(BrainrotDisplayConfig.Attributes.CarrierUserId)
	local carrierUserId = if typeof(carrierValue) == "number" then carrierValue else nil
	local localPlayer = Players.LocalPlayer
	local locallyCarried = displayState == BrainrotDisplayConfig.States.Carried
		and localPlayer ~= nil
		and carrierUserId == localPlayer.UserId
	-- Core Loop V2 (L4.5): an awake director Star shows the WorldTag instead of the creature tag.
	local starTagged = coreLoopOn and entry.Model:GetAttribute("CoreLoopStar") == true
		and entry.Model:GetAttribute("BrainrotDisplayState") ~= "Sleeping"
	view.Gui.Enabled = entry.PlateAdmitted==true and identifyingMetadata and not locallyCarried and Visibility.IsVisible(entry.Model)
		and not starTagged
end

local function updateCamouflageEntry(entry: Entry, nowValue: number)
	local displayState = resolveDisplayState(entry.Model)
	if not entry.CamouflageSpecies or not isAwakeWorldRepresentation(entry.Model, displayState) then
		releaseCamouflageBinding(entry)
		updateViewEnabled(entry, BrainrotNametagController.isIdentifyingMetadataPermitted(entry.Model, nowValue))
		return
	end
	local sampled = BrainrotNametagController.getCamouflageSample(entry.Model, nowValue)
	if sampled.active then
		if entry.CamouflageBinding == nil then
			entry.CamouflageBinding = BrainrotCamouflagePresentation.Bind(entry.Model)
		end
	else
		releaseCamouflageBinding(entry)
	end
	local presentationFullyVisible = not sampled.resolved or sampled.fullReveal
	local cueTransparency = if sampled.resolved
		then CamouflageTiming.GetRevealCueTransparency(sampled, BrainrotBehaviours.Camouflage)
		else nil
	if entry.CamouflageBinding then
		BrainrotCamouflagePresentation.Apply(
			entry.CamouflageBinding,
			sampled.camouflageAmount,
			presentationFullyVisible,
			cueTransparency
		)
	end
	if entry.LastIdentifyingMetadata ~= sampled.fullReveal then
		entry.LastIdentifyingMetadata = sampled.fullReveal
		if not sampled.fullReveal then
			clearFocusedEntry(entry)
		end
		updateViewEnabled(entry, BrainrotNametagController.isIdentifyingMetadataPermitted(entry.Model, nowValue))
	end
end

local function updateDecoySplitEntry(entry: Entry, nowValue: number)
	local displayState = resolveDisplayState(entry.Model)
	if not entry.DecoySplitSpecies or not isAwakeWorldRepresentation(entry.Model, displayState) then
		releaseDecoyCueBinding(entry)
		entry.LastDecoyActive = false
		updateViewEnabled(entry, BrainrotNametagController.isIdentifyingMetadataPermitted(entry.Model, nowValue))
		return
	end
	local sampled = BrainrotNametagController.getDecoySplitSample(entry.Model, nowValue)
	if sampled.active then
		if entry.DecoyCueBinding == nil then
			entry.DecoyCueBinding = BrainrotDecoyCuePresentation.Bind(
				entry.Model,
				BrainrotBehaviours.DecoySplit.TrailLifetimeSeconds,
				BrainrotBehaviours.DecoySplit.TrailMaxLengthStuds,
				BrainrotBehaviours.DecoySplit.TrailWidthStuds
			)
		end
		if entry.DecoyCueBinding then
			BrainrotDecoyCuePresentation.Update(entry.DecoyCueBinding, sampled.pulseTransparency)
		end
	else
		releaseDecoyCueBinding(entry)
	end
	if entry.LastDecoyActive ~= sampled.active then
		if sampled.active then
			clearFocusedEntry(entry)
		end
		entry.LastDecoyActive = sampled.active
		updateViewEnabled(entry, BrainrotNametagController.isIdentifyingMetadataPermitted(entry.Model, nowValue))
	end
end

local function updateHealthEntry(entry: Entry, at: number)
	local view = entry.View
	if not view then
		return
	end
	local model = entry.Model
	local state = resolveDisplayState(model)
	local visible = Visibility.IsVisible(model) and model.Parent ~= nil and view.Gui.Enabled
	local camera = Workspace.CurrentCamera
	local part = view.Gui.Adornee
	local cameraDistance = if camera and part and part:IsA("BasePart")
		then (camera.CFrame.Position - part.Position).Magnitude else math.huge
	local localPlayer = Players.LocalPlayer
	local selected = localPlayer and localPlayer:GetAttribute("SelectedWeaponId") or Weapons.StarterWeaponId
	local profile = WeaponStats.Resolve(selected)
	local profileRange = if WeaponStats.IsReady(profile) then profile.rangeStuds else nil
	local sleeping = state == BrainrotDisplayConfig.States.Sleeping
	local body = model:FindFirstChild("Body", true)
	local character = localPlayer and localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = if root and root:IsA("BasePart") then root.Position else nil
	-- Use the same real native launcher muzzle as lock eligibility when held.
	-- A retained ground-sleep context may also be read while the tool is stowed.
	if character then
		for _, tool in character:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("BrainrotSleepLauncher") == true and tool.Enabled then
				local handle = tool:FindFirstChild("Handle")
				local muzzle = handle and handle:FindFirstChild("Muzzle")
				if muzzle and muzzle:IsA("Attachment") then origin = muzzle.WorldPosition; break end
			end
		end
	end
	local bodyPosition = if body and body:IsA("BasePart") then body.Position else nil
	local sleepUntil = if sleeping then model:GetAttribute("BrainrotSleepUntil") else nil
	entry.CombatReadabilityContext = CombatUiRules.UpdateReadabilityContext(entry.CombatReadabilityContext, {
		visible = visible, banked = model:GetAttribute("Phase10Banked") == true,
		interactionReady = model:GetAttribute("Phase12InteractionReady"), itemId = model:GetAttribute("ItemId"),
		resetToken = tostring(model:GetAttribute("Phase12ResetGeneration")) .. ":" .. tostring(model:GetAttribute("Phase12SourceGeneration")),
		focused = focusedModel == model, displayState = state, sleepUntil = sleepUntil,
		now = at, profileRange = profileRange, maximumLockRange = Phase12.HpUi.MaximumLockRangeStuds,
	})
	local readability = CombatUiRules.Readability({
		context = entry.CombatReadabilityContext, profileRange = profileRange,
		ordinaryRange = Phase12.HpUi.RangeStuds, maximumLockRange = Phase12.HpUi.MaximumLockRangeStuds,
		cameraDistance = cameraDistance,
		physicalDistance = if origin and bodyPosition then (origin - bodyPosition).Magnitude else nil,
		cameraOffset = if camera and origin then (camera.CFrame.Position - origin).Magnitude else nil,
		adorneeOffset = if bodyPosition and part and part:IsA("BasePart") then (bodyPosition - part.Position).Magnitude else nil,
	})
	local eligible = (state == BrainrotDisplayConfig.States.Awake or sleeping)
		and model:GetAttribute("Phase10Banked") ~= true
		and model:GetAttribute("Phase12InteractionReady") ~= false
		and visible and readability.eligible
	local maximum = model:GetAttribute("Phase12MaxHp")
	local hp = model:GetAttribute("Phase12RemainingHp")
	local untilTime = if sleeping then model:GetAttribute("BrainrotSleepUntil") else nil
	if
		not eligible
		or type(maximum) ~= "number"
		or type(hp) ~= "number"
		or (sleeping and type(untilTime) ~= "number")
	then
		BrainrotNametagView.updateCombat(view, nil, false)
		return
	end
	view.Gui.MaxDistance = math.min(readability.billboardRangeStuds,entry.PlateRange or Exact.WildPlateRange)
	local damageTime = model:GetAttribute("Phase13LastDamageAt")
	local showText = focusedModel == model or (sleeping and entry.CombatReadabilityContext ~= nil)
		or (type(damageTime) == "number" and at - damageTime < 5)
	BrainrotNametagView.updateCombat(
		view,
		if showText then CombatUiRules.Sample(hp, maximum, untilTime, at)else nil,
		showText,
		Players.LocalPlayer:GetAttribute("ReducedMotion") == true
	)
end

local function refreshEntry(entry: Entry)
	if entries[entry.Model] ~= entry then
		return
	end
	animatedEntries[entry.Model] = nil
	healthEntries[entry.Model] = nil

	local displayState = resolveDisplayState(entry.Model)
	if displayState == nil then
		releaseCamouflageBinding(entry)
		releaseDecoyCueBinding(entry)
		clearFocusedEntry(entry)
		destroyView(entry)
		return
	end

	local brainrotId = entry.Model:GetAttribute(BrainrotDisplayConfig.Attributes.BrainrotId)
	if type(brainrotId) ~= "string" or brainrotId == "" then
		releaseCamouflageBinding(entry)
		releaseDecoyCueBinding(entry)
		clearFocusedEntry(entry)
		destroyView(entry)
		if not entry.WarnedMissingId then
			entry.WarnedMissingId = true
			log:Warn("Displayable model %s has no stable brainrot ID", entry.Model:GetFullName())
		end
		return
	end

	local definition, reason = BrainrotCatalog.GetDefinition(brainrotId)
	if definition == nil then
		releaseCamouflageBinding(entry)
		releaseDecoyCueBinding(entry)
		clearFocusedEntry(entry)
		destroyView(entry)
		if not entry.WarnedCatalogueIds[brainrotId] then
			entry.WarnedCatalogueIds[brainrotId] = true
			log:Warn(
				"Catalogue lookup failed for %s on %s: %s",
				brainrotId,
				entry.Model:GetFullName(),
				tostring(reason)
			)
		end
		return
	end
	entry.CamouflageSpecies = definition.behaviourId == "Camouflage"
	entry.DecoySplitSpecies = definition.behaviourId == "DecoySplit"

	local displayPart = resolveDisplayPart(entry.Model)
	if displayPart == nil then
		releaseCamouflageBinding(entry)
		releaseDecoyCueBinding(entry)
		clearFocusedEntry(entry)
		destroyView(entry)
		-- Streaming can replicate a tagged model shell before its visual descendants.
		-- The authoritative world owner only tags models after validating geometry,
		-- so an entirely empty shell remains pending until descendants arrive.
		if #entry.Model:GetDescendants() == 0 then
			return
		end
		if not entry.WarnedMissingPart then
			entry.WarnedMissingPart = true
			log:Warn("Displayable model %s has no usable BasePart", entry.Model:GetFullName())
		end
		return
	end

	local activePlayerGui = playerGui
	if activePlayerGui == nil then
		return
	end
	local mutationId = Phase12Rules.NormalizeMutation(
		entry.Model:GetAttribute("MutationId") or entry.Model:GetAttribute(BrainrotDisplayConfig.Attributes.MutationId)
	) or "None"
	local unidentifiedAstral = Phase12.Enabled
		and mutationId == "Astral"
		and entry.Model:GetAttribute("CapturedOnce") ~= true
		and entry.Model:GetAttribute("Phase12CapturedOnce") ~= true
		and displayState == BrainrotDisplayConfig.States.Awake
	local displayData: BrainrotNametagView.DisplayData = {
		displayName = if unidentifiedAstral then "ASTRAL" else definition.displayName,
		rarity = definition.tier,
		cashPerSecond = definition.cashPerSecond,
		effectiveCashPerSecond = definition.cashPerSecond * Phase12Rules.MutationMultiplier(mutationId),
	}
	local carrierValue = entry.Model:GetAttribute(BrainrotDisplayConfig.Attributes.CarrierUserId)
	local carrierUserId = if typeof(carrierValue) == "number" then carrierValue else nil
	local localPlayer = Players.LocalPlayer
	local locallyCarried = displayState == BrainrotDisplayConfig.States.Carried
		and localPlayer ~= nil
		and carrierUserId == localPlayer.UserId
	if focusedModel == entry.Model and (displayState ~= BrainrotDisplayConfig.States.Awake or locallyCarried) then
		clearFocusedEntry(entry, displayState == BrainrotDisplayConfig.States.Sleeping)
	end
	if entry.View == nil or entry.View.Gui.Adornee ~= displayPart then
		destroyView(entry)
		entry.View = BrainrotNametagView.create(activePlayerGui, entry.Model, displayPart, displayData, displayState)
	else
		BrainrotNametagView.updateData(entry.View, displayData)
	end
	local view = entry.View :: BrainrotNametagView.View
	BrainrotNametagView.updateState(view, displayState, carrierUserId)
	BrainrotNametagView.setSaving(view, entry.Model:GetAttribute("PendingBank") == true)
	local identifyingMetadata = BrainrotNametagController.isIdentifyingMetadataPermitted(entry.Model)
	updateViewEnabled(entry, identifyingMetadata)

	local preset = AppearanceCatalog.Mutations[mutationId]
	BrainrotNametagView.setMutation(
		view,
		if preset
			then {
				displayName = mutationId,
				backgroundColor = preset.palette.shadow,
				textColor = preset.palette.highlight,
			}
			else nil
	)
	BrainrotNametagView.setFocused(view, focusedModel == entry.Model)
	local nowValue = Workspace:GetServerTimeNow()
	updateCamouflageEntry(entry, nowValue)
	updateDecoySplitEntry(entry, nowValue)
	if displayState == BrainrotDisplayConfig.States.Awake or displayState == BrainrotDisplayConfig.States.Sleeping then
		healthEntries[entry.Model] = entry
		updateHealthEntry(entry, nowValue)
	end
	if entry.CamouflageBinding or entry.DecoyCueBinding then
		animatedEntries[entry.Model] = entry
	end
end

function BrainrotNametagController.setFocusedBrainrot(modelOrNil: Model?)
	modelOrNil = CreaturePresentation.ResolveVisual(modelOrNil)
	local oldModel = focusedModel
	if oldModel then
		local oldEntry = entries[oldModel]
		if oldEntry then
			clearFocusedEntry(oldEntry, resolveDisplayState(oldModel) == BrainrotDisplayConfig.States.Sleeping)
		end
	end
	focusedModel = nil

	if
		modelOrNil == nil
		or not modelOrNil:IsA("Model")
		or not CollectionService:HasTag(modelOrNil, BrainrotDisplayConfig.CollectionTag)
		or not BrainrotNametagController.isAimAssistEligible(modelOrNil)
	then
		return
	end
	local entry = entries[modelOrNil]
	if entry == nil or entry.View == nil or resolveDisplayState(modelOrNil) ~= BrainrotDisplayConfig.States.Awake then
		return
	end
	focusedModel = modelOrNil
	BrainrotNametagView.setFocused(entry.View, true)
	updateHealthEntry(entry, Workspace:GetServerTimeNow())
end

local function registerModel(instance: Instance)
	if
		not started
		or not instance:IsA("Model")
		or entries[instance]
		or instance:GetAttribute("CreatureProxy") == true
	then
		return
	end

	local entry: Entry = {
		Model = instance,
		View = nil,
		Connections = {},
		WarnedMissingId = false,
		WarnedMissingPart = false,
		WarnedCatalogueIds = {},
		CamouflageSpecies = false,
		CamouflageBinding = nil,
		DecoySplitSpecies = false,
		DecoyCueBinding = nil,
		LastDecoyActive = nil,
		LastIdentifyingMetadata = nil,
	}
	entries[instance] = entry
	for _, attribute in
		{
			"ItemId",
			"Phase12ResetGeneration",
			"Phase12SourceGeneration",
			"MutationId",
			"CapturedOnce",
			"Phase12CapturedOnce",
			"Phase13RegionVisible",
			"PendingBank",
			"Phase12MaxHp",
			"Phase12RemainingHp",
			"BrainrotSleepUntil",
		}
	do
		table.insert(
			entry.Connections,
			instance:GetAttributeChangedSignal(attribute):Connect(function()
				refreshEntry(entry)
			end)
		)
	end

	table.insert(
		entry.Connections,
		instance:GetAttributeChangedSignal("Captured"):Connect(function()
			refreshEntry(entry)
		end)
	)
	table.insert(
		entry.Connections,
		instance:GetAttributeChangedSignal(BrainrotDisplayConfig.Attributes.BrainrotId):Connect(function()
			refreshEntry(entry)
		end)
	)
	table.insert(
		entry.Connections,
		instance:GetAttributeChangedSignal(BrainrotDisplayConfig.Attributes.CarrierUserId):Connect(function()
			refreshEntry(entry)
		end)
	)
	table.insert(
		entry.Connections,
		instance:GetAttributeChangedSignal(BrainrotDisplayConfig.Attributes.MutationId):Connect(function()
			refreshEntry(entry)
		end)
	)
	table.insert(
		entry.Connections,
		instance:GetAttributeChangedSignal(BrainrotDisplayConfig.Attributes.DisplayState):Connect(function()
			refreshEntry(entry)
		end)
	)
	table.insert(
		entry.Connections,
		instance:GetAttributeChangedSignal(BrainrotDisplayConfig.Attributes.CamouflageSnapshot):Connect(function()
			refreshEntry(entry)
		end)
	)
	table.insert(
		entry.Connections,
		instance:GetAttributeChangedSignal(BrainrotDisplayConfig.Attributes.DecoySplitSnapshot):Connect(function()
			refreshEntry(entry)
		end)
	)
	table.insert(
		entry.Connections,
		instance.DescendantAdded:Connect(function(descendant: Instance)
			if entry.View == nil and descendant:IsA("BasePart") then
				refreshEntry(entry)
			end
		end)
	)
	table.insert(
		entry.Connections,
		instance.Destroying:Connect(function()
			unregisterModel(instance)
		end)
	)
	table.insert(
		entry.Connections,
		instance.AncestryChanged:Connect(function()
			if not instance:IsDescendantOf(game) then
				unregisterModel(instance)
			else
				refreshEntry(entry)
			end
		end)
	)

	refreshEntry(entry)
end

local lastNearCheck=0
local function refreshRelevance()
 local camera=Workspace.CurrentCamera;if not camera then return end
 local currentId=Players.LocalPlayer:GetAttribute("ExactSelectedIndividualId")
 local selected=focusedModel
 if not selected and currentId then for model in pairs(entries)do if model:GetAttribute("ItemId")==currentId then selected=model;break end end end
 local candidates={}
 -- trend audio: nearest awake wild brainrot within 30 studs of the player (reuses this pass)
 local character=Players.LocalPlayer.Character
 local nearClock=os.clock()
 local playerPosition=if character and nearClock-lastNearCheck>=0.25 then character:GetPivot().Position else nil
 if playerPosition then lastNearCheck=nearClock end
 local nearSpecies,nearPosition,nearDistance=nil,nil,30
 for model,entry in pairs(entries)do
  entry.PlateAdmitted=false
  local state=resolveDisplayState(model)
  if playerPosition and isAwakeWorldRepresentation(model,state)then
   local position=model:GetPivot().Position
   local near=(position-playerPosition).Magnitude
   if near<=nearDistance then
    local species=model:GetAttribute(BrainrotDisplayConfig.Attributes.BrainrotId)
    if type(species)=="string"then nearSpecies,nearPosition,nearDistance=species,position,near end
   end
  end
  if entry.View and state and (model==selected or (state~="Carried"and state~="Cart"))then
   local distance=(model:GetPivot().Position-camera.CFrame.Position).Magnitude
   local isSelected=model==selected
   local range=if state=="Deposited"then Exact.BankedPlateRange else Exact.WildPlateRange
   if isSelected then
    local profile=WeaponStats.Resolve(Players.LocalPlayer:GetAttribute("SelectedWeaponId")or Weapons.StarterWeaponId)
    local currentRange=if selected==focusedModel and WeaponStats.IsReady(profile)then profile.rangeStuds else require(ReplicatedStorage.Shared.Config.BrainrotInteraction).PLACEMENT_INTERACT_RADIUS
    range=math.min(Exact.SelectedPlateRange,currentRange)
   end
   if distance<=range and Visibility.IsVisible(model)then table.insert(candidates,{entry=entry,distance=distance,id=tostring(model:GetAttribute("ItemId")),selected=isSelected,range=range})end
  end
 end
 if nearSpecies and nearPosition then AudioCue.Near(nearSpecies,nearPosition)end
 table.sort(candidates,function(a,b)return if a.selected~=b.selected then a.selected elseif a.distance~=b.distance then a.distance<b.distance else a.id<b.id end)
 local ordinary,extra=0,0
 for _,v in ipairs(candidates)do
  if v.selected and extra<Exact.SelectedPlateCap then extra+=1;v.entry.PlateAdmitted=true
  elseif not v.selected and ordinary<Exact.UnselectedPlateCap then ordinary+=1;v.entry.PlateAdmitted=true end
  v.entry.PlateRange=v.range
  v.entry.View.Gui.MaxDistance=v.range
 end
 -- Declutter (first-session visuals): in priority order, a plate whose screen box
 -- overlaps an already admitted plate is withheld until it separates.
 local admitted,rects={}, {}
 for _,v in ipairs(candidates)do
  if v.entry.PlateAdmitted then
   local gui=v.entry.View.Gui
   local adornee=gui.Adornee
   local origin=if adornee and adornee:IsA("BasePart")then adornee.Position elseif adornee and adornee:IsA("Attachment")then adornee.WorldPosition else nil
   if origin then
    local point,onScreen=camera:WorldToViewportPoint(origin+gui.StudsOffsetWorldSpace)
    local size=if gui.AbsoluteSize.X>0 then gui.AbsoluteSize else Vector2.new(gui.Size.X.Offset,gui.Size.Y.Offset)
    if onScreen and point.Z>0 then
     table.insert(admitted,v.entry)
     table.insert(rects,{MinX=point.X-size.X/2,MaxX=point.X+size.X/2,MinY=point.Y-size.Y/2,MaxY=point.Y+size.Y/2})
    end
   end
  end
 end
 local keep=FirstSessionRules.Declutter(rects,FirstSessionVisuals.Nametag.OverlapFraction)
 for i,entry in ipairs(admitted)do if not keep[i]then entry.PlateAdmitted=false end end
 for model,entry in pairs(entries)do if entry.View then
  BrainrotNametagView.compact(entry.View)
  updateViewEnabled(entry,BrainrotNametagController.isIdentifyingMetadataPermitted(model))
 end end
end

function BrainrotNametagController.Start(): boolean
	if started then
		return false
	end
	started = true
	local localPlayer = Players.LocalPlayer
	assert(localPlayer ~= nil, "LocalPlayer was unavailable")
	playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	table.insert(
		controllerConnections,
		CollectionService:GetInstanceAddedSignal(BrainrotDisplayConfig.CollectionTag):Connect(registerModel)
	)
	table.insert(
		controllerConnections,
		CollectionService:GetInstanceRemovedSignal(BrainrotDisplayConfig.CollectionTag)
			:Connect(function(instance: Instance)
				if instance:IsA("Model") then
					unregisterModel(instance)
				end
			end)
	)

	local taggedModels = CollectionService:GetTagged(BrainrotDisplayConfig.CollectionTag)
	for _, instance in taggedModels do
		registerModel(instance)
	end
	table.insert(
		controllerConnections,
		RunService.RenderStepped:Connect(function()
			local nowValue = Workspace:GetServerTimeNow()
			if nowValue - lastHealthRefresh >= Exact.RelevanceInterval then
                refreshRelevance()
				lastHealthRefresh = nowValue
				for _, healthEntry in healthEntries do
					updateHealthEntry(healthEntry, nowValue)
				end
			end
			for model, entry in animatedEntries do
				if entry.CamouflageBinding ~= nil then
					updateCamouflageEntry(entry, nowValue)
				end
				if entry.DecoyCueBinding ~= nil then
					updateDecoySplitEntry(entry, nowValue)
				end
				if not entry.CamouflageBinding and not entry.DecoyCueBinding then
					animatedEntries[model] = nil
				end
			end
		end)
	)
	return true
end

function BrainrotNametagController.Stop()
	if not started then
		return
	end
	started = false
	BrainrotNametagController.setFocusedBrainrot(nil)
	disconnectAll(controllerConnections)
	local models = {}
	for model in entries do
		table.insert(models, model)
	end
	for _, model in models do
		unregisterModel(model)
	end
	playerGui = nil
end

return BrainrotNametagController
