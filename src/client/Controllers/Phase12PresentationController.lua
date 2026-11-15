--!strict
-- One client coordinator owns timelines, deduplication, pools and critical UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TemplateProvider =
	require(game:GetService("ReplicatedStorage").Shared.Utility.CreatureTemplateProvider)
local CollectionService = game:GetService("CollectionService")
local SlotPresentation = require(ReplicatedStorage.Shared.Utility.BaseSlotPresentation)
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local ContentProvider = game:GetService("ContentProvider")
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local DisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local AppearanceCatalog = require(ReplicatedStorage.Shared.Config.BrainrotAppearanceCatalog)
local Appearance = require(ReplicatedStorage.Shared.Utility.BrainrotAppearance)
local Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local Config = require(ReplicatedStorage.Shared.Config.Phase12)
-- Core Loop V2 (J2): with the Rush part on, there is no world reset clock, collapse sky, build or
-- critical screen, substitute parts or reset warning SFX; the HUD shows only the RUSH chip.
local CoreLoopRushMode = require(ReplicatedStorage.Shared.Config.CoreLoopFlags).Part("Rush")
local Nametags = require(script.Parent.BrainrotNametagController)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local ApprovedEnvironment = require(ReplicatedStorage.Shared.Utility.ApprovedEnvironment)
local AdaptiveVFXPolicy = require(ReplicatedStorage.Shared.Utility.AdaptiveVFXPolicy)
local ResolvedQuality = require(ReplicatedStorage.Shared.Utility.ResolvedPresentationQuality)
local SpaceRift = require(ReplicatedStorage.Shared.Config.SpaceRift)
local SpaceRiftRenderer = require(script.Parent.Parent.Utility.SpaceRiftRenderer)
local PresentationRules = require(ReplicatedStorage.Shared.Utility.Phase13PresentationRules)
local Visibility = require(script.Parent.RegionVisibilityController)
local CombatStrings = require(ReplicatedStorage.Shared.Config.Phase13CombatStrings)
local Exact = require(ReplicatedStorage.Shared.Config.PlaytestExact)
local Hud = require(script.Parent.ExactHudController)
local Controller = {}
local player = Players.LocalPlayer
local started = false
local generation = 0
local connections: { RBXScriptConnection } = {}
local models: { [Model]: any } = {}
local seen: { [string]: boolean } = {}
local seenOrder: { string } = {}
local queue: { any } = {}
local spawnBurst: { any } = {}
local spawnFlushScheduled = false
local spawnBurstGeneration = 0
local spawnReceiptCycle: any = nil
local spawnCycleSynchronized = false
local pendingBanks: { [number]: any } = {}
local celebrations: { any } = {}
local voices: { any } = {}
local scheduledJobs: { any } = {}
local activeParticles: { any } = {}
local particleCount = 0
local current: any = nil
local outgoing: any = nil
local sky: any = nil
local visualFolder: Folder? = nil
local gui: ScreenGui? = nil
local criticalGui: ScreenGui? = nil
local lastLayoutSize = Vector2.zero
local bannerHeight = 108
local bannerTop = 54
local compactLandscape = false
local clockLabel: TextLabel? = nil
local criticalLabel: TextLabel? = nil
local escapeLabel: TextLabel? = nil
local haulLabel: TextButton? = nil
local cueLabel: TextLabel? = nil
local anchorPool: { BasePart } = {}
local resetPhase = 0
local lastCycle: any = nil
local exactEscapeAt = -math.huge
local landingCue: any = nil
local announceScheduled = false
local previewGeneration = 0
local previewSerial = 0
local haulIsPreview = false
local haulGeneration = 0
local haulListConnection: RBXScriptConnection? = nil
local latestProgress: any = nil
local audioMissing: { [string]: boolean } = {}
local ducked: { [SoundGroup]: number } = {}
local pendingShakeCleanups: { any } = {}
local shakeCleanupConnection: RBXScriptConnection? = nil
local rebirth: any = nil
local rebirthSeen: { [string]: boolean } = {}
local rebirthPreparations = PresentationRules.PreparationFence(
	function(expectedGeneration: number): boolean
		return started and generation == expectedGeneration
	end
)
-- No extra connection or spawned waiter: the existing coordinator pumps one
-- bounded subject repair after CharacterRemoving until the new Humanoid exists.
local cameraRestores = PresentationRules.CameraRestoreFence(
	function(expectedGeneration: number): boolean
		return started and generation == expectedGeneration
	end,
	function(subject: any): boolean
		return typeof(subject) == "Instance" and subject:IsDescendantOf(Workspace)
	end,
	function(subject: any, character: any): boolean
		return typeof(subject) == "Instance"
			and typeof(character) == "Instance"
			and (subject == character or subject:IsDescendantOf(character))
	end
)
local cameraRestoreLastStatus = "Idle"
local function cameraRestoreContext(): any
	local camera = Workspace.CurrentCamera
	local character = player.Character
	return {
		now = Workspace:GetServerTimeNow(),
		camera = camera,
		cameraType = camera and camera.CameraType,
		subject = camera and camera.CameraSubject,
		character = character,
		humanoid = character and character:FindFirstChildOfClass("Humanoid"),
	}
end
local resetSubstitutes: { any } = {}
local resetSubstitutePool: { BasePart } = {}
local resetSubstituteSeen: { [string]: boolean } = {}
local resetSubstituteGeneration: any = nil
local resetSubstituteCount = 0
local rifts: any = nil
local adaptive = AdaptiveVFXPolicy.new()
local detailQualityOwner: any = nil
local lastPublishedDetailTier: string? = nil
local lastExactReduced = nil
local focusKnown: boolean? = nil
local sessionPreferences: any = {}
local settingsBusy = false
local settingsMessage = ""
local settingsPendingPatch: any = {}
local settingsWorkerId = 0
local settingsRetryBudget = 0
local meteorPool: { any } = {}
local measurements: any = { lastRead = -math.huge, errors = {} }
-- An observation timeout never cancels a preload worker or frees its slot.
local primaryPreload: any =
	{ busy = false, attempts = 0, status = "NotRequested", callbacks = {}, resident = false }
local riftPreviews: { [ImageLabel]: any } = {}
local riftAssetObservations: { [string]: boolean } = {}
local function reportRiftAsset(reason: string)
	if riftAssetObservations[reason] then
		return
	end
	riftAssetObservations[reason] = true
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local observation = remotes and remotes:FindFirstChild("Phase13ClientObservation")
	if observation and observation:IsA("RemoteEvent") then
		observation:FireServer({ kind = "CinematicAsset", category = reason })
	end
end
local function observeRiftPreviews()
	for image, entry in riftPreviews do
		if not image.Parent then
			riftPreviews[image] = nil
			continue
		end
		local visible = image.Visible and image.AbsoluteSize.X > 0 and image.AbsoluteSize.Y > 0
		local ancestor: Instance? = image.Parent
		while ancestor and ancestor ~= player.PlayerGui do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then
				visible = false
			end
			if ancestor:IsA("LayerCollector") and not ancestor.Enabled then
				visible = false
			end
			ancestor = ancestor.Parent
		end
		visible = visible and ancestor == player.PlayerGui
		if visible and image.IsLoaded then
			entry.frames += 1
			if entry.frames < 2 then
				continue
			end
			if entry.primary then
				primaryPreload.resident = true
				primaryPreload.lastResidentAt = Workspace:GetServerTimeNow()
				primaryPreload.renderReadiness = "VisibleNativeFrameObserved"
			end
		end
		entry.label.Text = if image.IsLoaded
			then entry.title
			elseif not entry.primary then if os.clock() - entry.startedAt >= 10
				then "Singularity preview unavailable"
				else "Loading Singularity preview…"
			elseif
				primaryPreload.status == "Error" or primaryPreload.status == "UnknownOrFailed"
			then "Rift preview unavailable"
			else "Loading approved rift preview…"
	end
end

local function now(): number
	return Workspace:GetServerTimeNow()
end
-- Cosmetic deadlines are pumped by the persistent coordinator connection.
-- A temporary caller's LocalScript lifetime cannot cancel or latch this queue.
local function schedule(seconds: number, callback: () -> ())
	if #scheduledJobs >= 512 then
		return false
	end
	table.insert(
		scheduledJobs,
		{ deadline = now() + math.max(0, seconds), callback = callback, generation = generation }
	)
	return true
end
local function pumpScheduled(serverTime: number)
	for index = #scheduledJobs, 1, -1 do
		local job = scheduledJobs[index]
		if job.generation ~= generation then
			table.remove(scheduledJobs, index)
		elseif serverTime >= job.deadline then
			table.remove(scheduledJobs, index)
			local ok, reason = xpcall(job.callback, debug.traceback)
			if not ok then
				warn("[Phase12Presentation] Cosmetic timeline: " .. tostring(reason))
			end
		end
	end
end
local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function reducedMotion(): boolean
	return if sessionPreferences.ReducedMotion ~= nil
		then sessionPreferences.ReducedMotion
		else player:GetAttribute("ReducedMotion") == true
end
local function quality(): string
	return adaptive.GetTier()
end
local function selectedQuality(): string
	local configured = sessionPreferences.VFXQuality or player:GetAttribute("VFXQuality")
	return if configured == "Low"
			or configured == "Medium"
			or configured == "High"
		then configured
		else "Auto"
end
local function renderSample(dt: number)
	observeRiftPreviews()
	local at = os.clock()
	if at - measurements.lastRead >= 1 then
		measurements.lastRead = at
		for key, property in { cpuMs = "RenderCPUFrameTime", gpuMs = "RenderGPUFrameTime" } do
			local ok, seconds = pcall(function()
				return Stats[property]
			end)
			measurements[key] = if ok
					and finite(seconds)
					and seconds > 0
					and seconds < 10
				then seconds * 1000
				else nil
			if not ok then
				measurements.errors[property] = tostring(seconds)
			end
		end
		local ok, memory = pcall(Stats.GetTotalMemoryUsageMb, Stats)
		measurements.memoryMb = if ok and finite(memory) and memory > 0 then memory else nil
		local got, saved = pcall(function()
			return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
		end)
		measurements.savedQuality = if got
				and finite(saved)
				and saved >= 1
				and saved <= 10
			then saved
			else nil
	end
	adaptive.Step(at, {
		ready = game:IsLoaded() and player:GetAttribute("PlayerDataStatus") == "Ready",
		focused = focusKnown,
		mode = selectedQuality(),
		savedQuality = measurements.savedQuality,
		cpuMs = measurements.cpuMs,
		gpuMs = measurements.gpuMs,
		memoryMb = measurements.memoryMb,
	})
	local tier = adaptive.GetTier()
	if detailQualityOwner and tier ~= lastPublishedDetailTier then
		if ResolvedQuality.Publish(detailQualityOwner, tier) then
			lastPublishedDetailTier = tier
			ApprovedEnvironment.SetReducedEffects(tier == "Low" or reducedMotion())
		end
	end
	local reduced = tier == "Low" or reducedMotion()
	if lastExactReduced ~= reduced then
		lastExactReduced = reduced
		ApprovedEnvironment.SetReducedEffects(reduced)
	end
	adaptive.RecordFrame(at, dt)
end
local function warmPrimary()
	if
		primaryPreload.busy
		or primaryPreload.status == "Success"
		or primaryPreload.attempts >= 1
	then
		return
	end
	primaryPreload.busy, primaryPreload.status = true, "Pending"
	primaryPreload.attempts += 1
	local image = Instance.new("ImageLabel")
	image.Name, image.BackgroundTransparency, image.Visible, image.Size =
		"RiftPrimaryWarmup", 1, false, UDim2.fromOffset(0, 0)
	image.Image, image.Parent = SpaceRift.PrimaryImage, gui
	local began = os.clock()
	schedule(30, function()
		if primaryPreload.busy then
			primaryPreload.status = "TimedOutWorkerStillPending"
			reportRiftAsset("RIFT_PRELOAD_TIMEOUT")
		end
	end)
	task.spawn(function()
		local callbacks = {}
		local ok, reason = pcall(function()
			ContentProvider:PreloadAsync({ image }, function(uri, status)
				if #callbacks < 8 then
					table.insert(callbacks, { uri = uri, status = status.Name })
				end
			end)
		end)
		primaryPreload.busy = false
		primaryPreload.elapsedSeconds = os.clock() - began
		primaryPreload.callbacks = callbacks
		primaryPreload.error = if not ok then tostring(reason) else nil
		local fetched = #callbacks > 0
		for _, result in callbacks do
			fetched = fetched and result.status == "Success"
		end
		primaryPreload.imageIsLoadedAtSettlement = image.IsLoaded
		primaryPreload.status = if not ok
			then "Error"
			elseif fetched then "Success"
			else "UnknownOrFailed"
		primaryPreload.renderReadiness = if primaryPreload.resident
			then "VisibleNativeFrameObserved"
			else "FetchedAwaitingVisiblePreview"
		if primaryPreload.status == "Error" or primaryPreload.status == "UnknownOrFailed" then
			reportRiftAsset("RIFT_FETCH_FAILED")
		end
		image:Destroy()
	end)
end
-- A displayed near-use preview establishes residency; fetch success alone never does.
function Controller.GetRiftReadiness(): any
	return {
		fetchStatus = primaryPreload.status,
		resident = primaryPreload.resident == true,
		reason = if primaryPreload.resident
			then nil
			elseif
				primaryPreload.status == "Error" or primaryPreload.status == "UnknownOrFailed"
			then "RIFT_FETCH_FAILED"
			else "RIFT_NOT_RESIDENT",
		assetReference = SpaceRift.PrimaryImage,
		lastResidentAt = primaryPreload.lastResidentAt,
	}
end
function Controller.PrepareRiftPreview(parent: Instance, options: any?): any
	assert(
		typeof(parent) == "Instance" and parent:IsA("GuiObject"),
		"Rift preview GUI parent required"
	)
	-- One shop preview and one transition preview, with no private frame connection.
	local count = 0
	for _ in riftPreviews do
		count += 1
	end
	if count >= 2 then
		return { Destroy = function() end }
	end
	local descriptor = options and options.asset
	local imageReference = if type(descriptor) == "table"
			and type(descriptor.PrimaryImage) == "string"
			and descriptor.PrimaryImage:match("^rbxassetid://%d+$")
		then descriptor.PrimaryImage
		else SpaceRift.PrimaryImage
	local primary = imageReference == SpaceRift.PrimaryImage
	if primary then
		warmPrimary()
	end
	local image = Instance.new("ImageLabel")
	image.Name, image.BackgroundTransparency = "ApprovedRiftPreview", 1
	image.ImageColor3 = if options and options.vip == true
		then Color3.fromRGB(255, 200, 70)
		else Color3.new(1, 1, 1)
	image.Image, image.ScaleType = imageReference, Enum.ScaleType.Fit
	image.Size, image.Position = UDim2.new(1, 0, 1, -26), UDim2.fromOffset(0, 0)
	image.Parent = parent
	local label = Instance.new("TextLabel")
	label.Name, label.BackgroundTransparency = "RiftReadiness", 1
	label.Size, label.Position = UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 1, -26)
	label.Text, label.TextColor3 = "Loading approved rift preview…", Color3.new(1, 1, 1)
	label.Font, label.TextSize, label.TextWrapped = Enum.Font.Gotham, 12, true
	label.Parent = parent
	riftPreviews[image] = {
		frames = 0,
		label = label,
		primary = primary,
		title = if primary then "Approved rift preview" else "Singularity DEV preview",
		startedAt = os.clock(),
	}
	local destroyed = false
	return {
		Destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			riftPreviews[image] = nil
			image:Destroy()
			label:Destroy()
		end,
	}
end
local function cap(): number
	return Config.Presentation.ParticleCaps[quality()]
end
local function colours(event: any): any
	local mutation = Rules.NormalizeMutation(event.mutationId) or "None"
	local preset = AppearanceCatalog.Mutations[mutation]
	return if preset
		then preset.palette
		else (AppearanceCatalog.Rarities[event.rarity] or AppearanceCatalog.Rarities.Common)
end
-- Readability is a text treatment only; authored body/material palettes stay exact.
local function readableTextStop(color: Color3, highlight: Color3): Color3
	local mixed = color:Lerp(highlight, 0.38)
	local hue, saturation, value = mixed:ToHSV()
	return Color3.fromHSV(hue, math.min(saturation, 0.76), math.max(value, 0.94))
end
local function rank(event: any): number
	return Rules.SpectacleRank(event.rarity or "Common", event.mutationId)
end
local function stronger(a: any, b: any): boolean
	if rank(a) ~= rank(b) then
		return rank(a) > rank(b)
	end
	if (a.cashPerSecond or 0) ~= (b.cashPerSecond or 0) then
		return (a.cashPerSecond or 0) > (b.cashPerSecond or 0)
	end
	if (a.sellValue or 0) ~= (b.sellValue or 0) then
		return (a.sellValue or 0) > (b.sellValue or 0)
	end
	return tostring(a.instanceId or a.eventId) > tostring(b.instanceId or b.eventId)
end
local function cleanText(value: any): string
	local text = tostring(value or "")
	return string.sub(text, 1, 180)
end
local function richEscape(value: string): string
	return (
		value
			:gsub("&", "&amp;")
			:gsub("<", "&lt;")
			:gsub(">", "&gt;")
			:gsub('"', "&quot;")
			:gsub("'", "&apos;")
	)
end
local function identity(event: any): string
	if
		Rules.NormalizeMutation(event.mutationId) == "Astral"
		and event.identified ~= true
		and event.kind == "Spawn"
	then
		return "ASTRAL " .. string.upper(event.rarity or "")
	end
	local mutation = Rules.NormalizeMutation(event.mutationId) or "None"
	return (if mutation ~= "None" then string.upper(mutation) .. " " else "")
		.. cleanText(event.name)
end
local function headline(event: any): (string, string, string)
	if event.qaPreview == true then
		return "QA PREVIEW · " .. (if event.kind == "Bank"
			then "HAUL CELEBRATION"
			else string.upper(event.kind) .. " PRESENTATION"),
			identity(event) .. " · " .. string.upper(event.rarity or ""),
			cleanText(event.location)
	end
	local who = if event.username then "@" .. cleanText(event.username) else ""
	local name = identity(event)
	local rarity = string.upper(event.rarity or "")
	if event.kind == "Spawn" then
		return rarity .. " SPAWN", name, cleanText(event.location)
	end
	if event.kind == "Catch" then
		return who .. " CAUGHT " .. name, rarity, cleanText(event.location)
	end
	if event.kind == "Bank" or event.kind == "BankReceipt" then
		return "BANKED! " .. who .. " SECURED " .. name,
			"+"
				.. CurrencyFormatter.FormatCompactCash(event.cashPerSecond or 0)
				.. " CASH/SEC · "
				.. rarity,
			cleanText(event.location)
	end
	return cleanText(event.name or event.kind), "", cleanText(event.location)
end
local function addStroke(label: TextLabel, pale: boolean?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = if pale then Color3.fromHex("F6F3FF") else Color3.fromHex("111522")
	stroke.Parent = label
end
local function label(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	fontSize: number
): TextLabel
	local result = Instance.new("TextLabel")
	result.Name, result.Position, result.Size = name, position, size
	result.BackgroundTransparency = 1
	result.TextColor3 = Color3.new(1, 1, 1)
	result.Font = DisplayConfig.Typography.Font
	result.TextSize, result.TextScaled, result.TextWrapped = fontSize, true, true
	result.RichText = false
	result.Text = ""
	result.Parent = parent
	local bounds = Instance.new("UITextSizeConstraint")
	bounds.MinTextSize, bounds.MaxTextSize = 13, fontSize
	bounds.Parent = result
	addStroke(result)
	return result
end
-- Views (SettingsScreen, Brainrots > Index) read the state through the getters below and listen here.
Controller.VfxSettingsChanged = Instance.new("BindableEvent")
Controller.CollectionProgressChanged = Instance.new("BindableEvent")
local function refreshSettings()
	Controller.VfxSettingsChanged:Fire()
end
local function setLatestProgress(progress: any)
	latestProgress = progress
	Controller.CollectionProgressChanged:Fire()
end
local function saveSettings(patch: any)
	if next(patch) ~= nil then
		settingsRetryBudget = 1
	end
	for key, value in patch do
		sessionPreferences[key] = value
		settingsPendingPatch[key] = value
	end
	if settingsBusy then
		settingsMessage = " · THIS SESSION · SAVE PENDING"
		refreshSettings()
		return
	end
	settingsMessage = " · SAVING…"
	refreshSettings()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = if remotes then remotes:FindFirstChild(RemoteNames.VFXSettingsRequest) else nil
	if not remote or not remote:IsA("RemoteFunction") then
		settingsMessage = " · THIS SESSION"
		refreshSettings()
		return
	end
	settingsBusy = true
	settingsWorkerId += 1
	local workerId = settingsWorkerId
	local token = generation
	local request = table.clone(settingsPendingPatch)
	table.clear(settingsPendingPatch)
	request.action = "Set"
	schedule(8, function()
		if settingsBusy and settingsWorkerId == workerId then
			settingsMessage = " · THIS SESSION · SAVE PENDING"
			refreshSettings()
		end
	end)
	task.spawn(function()
		local ok, result = pcall(remote.InvokeServer, remote, request)
		if workerId ~= settingsWorkerId then
			return
		end
		settingsBusy = false
		if
			ok
			and type(result) == "table"
			and result.code == "RATE_LIMITED"
			and settingsRetryBudget > 0
		then
			settingsRetryBudget -= 1
			for key, value in request do
				if key ~= "action" and settingsPendingPatch[key] == nil then
					settingsPendingPatch[key] = value
				end
			end
		end
		if token == generation and started then
			settingsMessage = if ok
					and type(result) == "table"
					and result.ok == true
				then " · PROFILE AUTOSAVE"
				else " · THIS SESSION"
			refreshSettings()
		end
		if started and next(settingsPendingPatch) ~= nil then
			schedule(0.25, function()
				saveSettings({})
			end)
		end
	end)
end
local VFX_MODES = { Auto = true, Low = true, Medium = true, High = true }
local SETTINGS_STATUS = {
	[""] = "",
	[" · SAVING…"] = "Saving…",
	[" · THIS SESSION"] = "This session only",
	[" · THIS SESSION · SAVE PENDING"] = "This session · save pending",
	[" · PROFILE AUTOSAVE"] = "Saved to your profile",
}
local function settingsStatus(): string
	return SETTINGS_STATUS[settingsMessage] or settingsMessage
end
-- Effects settings: same session preference + VFXSettingsRequest {action="Set", ...} save as the
-- retired "Collection & Effects" panel; the view is the Settings screen.
function Controller.GetVfxSettings(): { quality: string, reducedMotion: boolean, status: string, saving: boolean }
	return {
		quality = selectedQuality(),
		reducedMotion = reducedMotion(),
		status = settingsStatus(),
		saving = settingsBusy,
	}
end
function Controller.SetVfxQuality(mode: any): (boolean, string?)
	if type(mode) ~= "string" or not VFX_MODES[mode] then
		return false, "Pick Auto, Low, Medium or High"
	end
	if not started then
		return false, "Effects are still loading"
	end
	saveSettings({ VFXQuality = mode })
	return true, settingsStatus()
end
function Controller.SetReducedMotion(value: any): (boolean, string?)
	if type(value) ~= "boolean" then
		return false, "Reduced Motion is On or Off"
	end
	if not started then
		return false, "Effects are still loading"
	end
	saveSettings({ ReducedMotion = value })
	return true, settingsStatus()
end
-- Last Phase12 progress table ({ species, speciesMutations, personalBest, trackedUpgrade, ... }).
-- Cached from Progress/Bank events; otherwise (or with refresh = true) it is read with the same
-- Phase12ProgressRequest {action="Snapshot"} the retired panel sent. May yield; nil when unavailable.
local progressFetching = false
function Controller.GetCollectionProgress(refresh: boolean?): any
	if not started or (latestProgress ~= nil and refresh ~= true) then
		return latestProgress
	end
	local token = generation
	if progressFetching then
		local waited = 0
		while progressFetching and token == generation and waited < 12 do
			waited += task.wait(0.1)
		end
		return latestProgress
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = if remotes then remotes:FindFirstChild(RemoteNames.Phase12ProgressRequest) else nil
	if not remote or not remote:IsA("RemoteFunction") then
		return latestProgress
	end
	progressFetching = true
	local ok, result = pcall(remote.InvokeServer, remote, { action = "Snapshot" })
	progressFetching = false
	if token ~= generation then
		return nil
	end
	if ok and type(result) == "table" and result.ok == true and type(result.progress) == "table" then
		setLatestProgress(result.progress)
	end
	return latestProgress
end
local function createUI(playerGui: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name, screen.ResetOnSpawn, screen.IgnoreGuiInset, screen.DisplayOrder =
		"Phase12Presentation", false, false, 35
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	gui = screen
	local criticalScreen = Instance.new("ScreenGui")
	criticalScreen.Name, criticalScreen.ResetOnSpawn, criticalScreen.IgnoreGuiInset, criticalScreen.DisplayOrder =
		"Phase12CriticalWarnings", false, false, 90
	require(script.Parent.Parent.UI.StudPopUI).skin(criticalScreen, { windowDepth = 0 })
	criticalScreen.Parent = screen.Parent
	criticalGui = criticalScreen
	Hud.Start()
	clockLabel, criticalLabel, escapeLabel, haulLabel = nil, nil, nil, nil
	cueLabel = label(
		criticalScreen,
		"LastKnownLanding",
		UDim2.fromScale(0.27, 0.69),
		UDim2.fromScale(0.46, 0.05),
		24
	)
end
local function updateLayout()
	if not gui then
		return
	end
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		size = camera.ViewportSize
	end
	if size == lastLayoutSize then
		return
	end
	lastLayoutSize = size
	compactLandscape = size.Y < 480
	bannerHeight = if compactLandscape then 94 else 108
	bannerTop = 54
	if clockLabel then
		clockLabel.AnchorPoint = Vector2.new(0.5, 0)
		clockLabel.Position = UDim2.new(0.5, 0, 0, 8)
		clockLabel.Size = UDim2.fromOffset(if size.X < 600 then 140 else 240, 32)
	end
	if criticalLabel then
		criticalLabel.Position = UDim2.new(0.07, 0, 0, if compactLandscape then 54 else 170)
		criticalLabel.Size = UDim2.new(0.86, 0, 0, 56)
	end
	if escapeLabel then
		escapeLabel.AnchorPoint = Vector2.new(0.5, 1)
		escapeLabel.Position = UDim2.new(0.5, 0, 1, -74)
		escapeLabel.Size = UDim2.new(0.86, 0, 0, 54)
	end
	if cueLabel then
		cueLabel.AnchorPoint = Vector2.new(0.5, 1)
		cueLabel.Position = UDim2.new(0.5, 0, 1, -134)
		cueLabel.Size = UDim2.new(0.64, 0, 0, 32)
	end
	if haulLabel then
		haulLabel.Size = UDim2.new(0.8, 0, 0, if compactLandscape then 106 else 130)
		haulLabel.Position = UDim2.new(0.1, 0, 0, if compactLandscape then 160 else 240)
	end
	for _, banner in { current, outgoing } do
		if banner then
			banner.frame.Size = UDim2.new(0.86, 0, 0, bannerHeight)
			if not banner.exiting then
				banner.frame.Position = UDim2.new(0.07, 0, 0, bannerTop)
			end
		end
	end
end
local function mirrorChat(event: any)
	if event.global ~= true or event.suppressChat == true or event.qaPreview == true then
		return
	end
	local a, b, c = headline(event)
	local message = richEscape(a .. " · " .. b .. (if c ~= "" then " · " .. c else ""))
	local channels = TextChatService:FindFirstChild("TextChannels")
	local channel = if channels
		then channels:FindFirstChild("RBXGeneral") or channels:FindFirstChild("RBXSystem")
		else nil
	if channel and channel:IsA("TextChannel") then
		local p = colours(event).highlight
		local color = string.format(
			"#%02X%02X%02X",
			math.floor(p.R * 255),
			math.floor(p.G * 255),
			math.floor(p.B * 255)
		)
		channel:DisplaySystemMessage(
			'<font color="' .. color .. '">' .. message .. "</font>",
			"Phase12:" .. event.eventId
		)
	else
		-- Existing custom chat can consume the same local event without callbacks being overwritten.
		local integration = ReplicatedStorage:FindFirstChild("Phase12SystemMessage")
		if integration and integration:IsA("BindableEvent") then
			integration:Fire(message, event.eventId)
		end
	end
end
local function exitBanner()
	if current then
		current.frame:Destroy()
		current = nil
	end
	if outgoing then
		outgoing.frame:Destroy()
		outgoing = nil
	end
end
local function enqueue(event: any)
	-- Routine pickup/loading are acknowledged by their actual state/control owner.
	if event.kind == "Catch" or event.kind == "Load" then
		return
	end
	local rarityCatalog = require(ReplicatedStorage.Shared.Config.Rarities)
	local rareEvent = (rarityCatalog.GetDisplayRank(event.rarity) or 0)
		>= (rarityCatalog.GetDisplayRank("Epic") or math.huge)
	if not rareEvent then
		return
	end
	local a = event.displayName or event.name or identity(event)
	Hud.Message(
		event.operationId or event.eventId,
		a,
		true,
		tostring(event.rarity) .. " · " .. cleanText(event.location)
	)
end

local function borrowAnchor(position: Vector3): BasePart
	local part = table.remove(anchorPool)
	if not part then
		part = Instance.new("Part")
		part.Name, part.Size, part.Transparency =
			"Phase12CosmeticAnchor", Vector3.new(0.1, 0.1, 0.1), 1
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow =
			true, false, false, false, false
	end
	part.Position, part.Parent = position, visualFolder
	return part
end
local function returnAnchor(part: BasePart)
	for _, child in part:GetChildren() do
		child:Destroy()
	end
	part.Parent = nil
	if #anchorPool < 20 then
		table.insert(anchorPool, part)
	else
		part:Destroy()
	end
end
local function burst(
	position: Vector3,
	color: Color3,
	count: number,
	speed: number,
	lifetime: number,
	qaPreview: boolean?
)
	count = math.min(count, math.max(0, cap() - particleCount))
	if count <= 0 then
		return
	end
	local anchor = borrowAnchor(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name, emitter.Rate, emitter.Enabled = "CelebrationBurst", 0, false
	-- Roblox's default white sparkle texture is a real built-in, no invented asset ID.
	emitter.Lifetime, emitter.Speed, emitter.SpreadAngle =
		NumberRange.new(0.8, lifetime), NumberRange.new(speed * 0.5, speed), Vector2.new(180, 180)
	emitter.Color, emitter.LightEmission = ColorSequence.new(color), 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.3, 0.32),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Acceleration, emitter.Drag, emitter.Parent = Vector3.new(0, -8, 0), 2, anchor
	emitter:Emit(count)
	particleCount += count
	table.insert(activeParticles, {
		part = anchor,
		untilTime = now() + lifetime,
		count = count,
		qaPreview = qaPreview == true,
	})
end
local function restoreDucking()
	for group, volume in ducked do
		if group.Parent then
			TweenService:Create(
				group,
				TweenInfo.new(Config.Presentation.BannerExitSeconds),
				{ Volume = volume }
			):Play()
		end
	end
	table.clear(ducked)
end
local function duck()
	for _, item in SoundService:GetDescendants() do
		if
			item:IsA("SoundGroup")
			and (item.Name == "Music" or item.Name == "Ambience")
			and ducked[item] == nil
		then
			ducked[item] = item.Volume
			TweenService:Create(item, TweenInfo.new(0.15), { Volume = item.Volume * 0.630957 })
				:Play()
		end
	end
end
local function audio(
	name: string,
	category: string,
	position: Vector3?,
	owner: boolean?,
	qaPreview: boolean?
)
	local source = SoundService:FindFirstChild(name, true)
	local folder = ReplicatedStorage:FindFirstChild("Phase12Audio")
	if not source and folder then
		source = folder:FindFirstChild(name)
	end
	if not source then
		local assets = ReplicatedStorage:FindFirstChild("CodeAssets")
		local canonical = assets and assets:FindFirstChild("Phase12Audio")
		source = canonical and canonical:FindFirstChild(name)
	end
	if not source or not source:IsA("Sound") or source.SoundId == "" then
		if not audioMissing[name] then
			audioMissing[name] = true
			warn(
				"[Phase12] Audio uninstalled: "
					.. name
					.. "; original staged WAV exists in phase12/assets/audio"
			)
		end
		return
	end
	local groupCount = 0
	for index = #voices, 1, -1 do
		local voice = voices[index]
		if voice.category == category then
			groupCount += 1
			if category == "critical" or category == "global" then
				voice.sound:Stop()
				voice.sound:Destroy()
				if voice.anchor then
					returnAnchor(voice.anchor)
				end
				table.remove(voices, index)
				groupCount -= 1
			end
		elseif category == "critical" and voice.category == "transient" then
			voice.sound:Destroy()
			if voice.anchor then
				returnAnchor(voice.anchor)
			end
			table.remove(voices, index)
		end
	end
	if
		groupCount >= (if category == "bank" then 2 elseif category == "transient" then 8 else 1)
	then
		if category == "bank" and owner then
			local indexToRemove = nil
			for index, voice in voices do
				if voice.category == "bank" and not voice.owner then
					indexToRemove = index
					break
				end
			end
			if indexToRemove then
				local voice = table.remove(voices, indexToRemove)
				voice.sound:Destroy()
				if voice.anchor then
					returnAnchor(voice.anchor)
				end
			else
				return
			end
		else
			return
		end
	end
	local sound = source:Clone()
	local anchor = if position and not owner then borrowAnchor(position) else nil
	sound.Looped = false
	sound.Volume = math.min(1, source.Volume) * (if anchor then 0.35 else 1)
	sound.RollOffMinDistance, sound.RollOffMaxDistance = 16, 120
	sound.Parent = anchor or SoundService
	sound:Play()
	table.insert(voices, {
		sound = sound,
		anchor = anchor,
		category = category,
		owner = owner == true,
		qaPreview = qaPreview == true,
		untilTime = now() + math.max(sound.TimeLength + 0.5, 8),
	})
	if category ~= "transient" then
		duck()
	end
end
local function clearSky()
	if not sky then
		return
	end
	local previous = sky
	sky = nil
	if rifts and previous.riftHandle then
		rifts.Stop(previous.riftHandle)
	end
	for _, meteor in meteorPool do
		meteor.gui.Enabled = false
	end
	if previous.environmentToken then
		ApprovedEnvironment.EndEvent(previous.environmentToken)
	end
end
local function skyEnvironment(energy: number): any
	local atmosphere = ApprovedEnvironment.GetBaselineValues("Atmosphere")
	return ApprovedEnvironment.BeginEvent({
		Atmosphere = if atmosphere
			then {
				Density = math.min(0.10, atmosphere.Density + 0.03 * energy),
				Haze = math.min(0.25, atmosphere.Haze + 0.08 * energy),
				Glare = math.min(0.10, atmosphere.Glare + 0.02 * energy),
			}
			else nil,
		ColorCorrectionEffect = {
			Enabled = true,
			Brightness = 0,
			Saturation = 0.06,
			Contrast = 0.02,
			TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromHex("C7B7FF"), 0.04),
		},
	})
end
local function stepMeteors(t: number, offset: Vector3)
	if not sky then
		return
	end
	local detail = quality()
	local count = if sky.reset
		then (if sky.resetStage == 1 then 0 else 6)
		else (if sky.rank == 2
			then 0
			elseif sky.rank == 3 then 3
			elseif sky.rank == 4 then 4
			else 6)
	count = if reducedMotion() or detail == "Low"
		then 0
		else math.min(count, if detail == "Medium" then 4 else 6)
	local camera = Workspace.CurrentCamera
	for index = 1, 6 do
		local slot = meteorPool[index]
		if index <= count and camera then
			if not slot then
				local anchor = Instance.new("Attachment")
				anchor.Name, anchor.Visible, anchor.Parent =
					"Phase12MeteorAnchor_" .. index, false, Workspace.Terrain
				local billboard = Instance.new("BillboardGui")
				billboard.Name, billboard.Adornee, billboard.AlwaysOnTop, billboard.LightInfluence =
					"Phase12MeteorStreak", anchor, false, 0
				billboard.Size, billboard.MaxDistance, billboard.Parent =
					UDim2.fromScale(12, 12), 700, visualFolder
				local streak = Instance.new("Frame")
				streak.AnchorPoint, streak.Position, streak.Size =
					Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.018, 0.9)
				streak.BorderSizePixel, streak.BackgroundTransparency, streak.BackgroundColor3 =
					0, 0.15, Color3.fromHex("47D8FF")
				streak.Parent = billboard
				slot = { anchor = anchor, gui = billboard, streak = streak }
				meteorPool[index] = slot
			end
			local meteor = sky.meteors[index]
			local amount = ((t - sky.startedAt) * 0.65 + meteor.phase) % 1
			local pos = meteor.origin:Lerp(sky.centre, amount) + offset
			slot.anchor.WorldPosition, slot.gui.Enabled = pos, true
			local screen = camera:WorldToViewportPoint(pos)
			local destination = camera:WorldToViewportPoint(sky.centre + offset)
			slot.streak.Rotation = math.deg(
				math.atan2(destination.Y - screen.Y, destination.X - screen.X)
			) - 90
		elseif slot then
			slot.gui.Enabled = false
		end
	end
end
local function beginSky(event: any, duration: number, reset: boolean?)
	local isReset, t = reset == true, now()
	if rebirth and not isReset then
		return
	end
	local impact = event.kind == "Reset"
	local deadline = if finite(event.resetDeadline)
		then event.resetDeadline
		else Workspace:GetAttribute("Phase12ResetDeadline")
	if not finite(event.startTime) then
		return
	end
	local startTime = event.startTime
	local untilTime = if isReset
			and not impact
			and finite(deadline)
		then deadline + 3
		else startTime + duration
	if t >= untilTime then
		return
	end
	if sky and t >= sky.untilTime then
		clearSky()
	end
	-- A single reset sequence owns its hero from T60 through the actual zero seal.
	if
		sky
		and sky.reset
		and isReset
		and not sky.impact
		and not impact
		and sky.resetDeadline == deadline
	then
		local stage = event.resetStage or sky.resetStage
		if stage ~= sky.resetStage then
			sky.resetStage = stage
			sky.environmentToken =
				skyEnvironment(if stage == 1 then 0.4 elseif stage == 2 then 0.7 else 1)
		end
		return
	end
	if sky and sky.reset and isReset and impact and (not sky.impact or sky.riftHandle) then
		if not sky.impact then
			if rifts and sky.riftHandle then
				rifts.Collapse(sky.riftHandle, startTime, duration)
			end
			sky.impact, sky.startedAt, sky.untilTime = true, startTime, untilTime
		end
		return
	end
	if sky and sky.reset and not isReset then
		return
	end
	if sky and not isReset and rank(event) <= sky.rank then
		return
	end
	clearSky()
	local camera = Workspace.CurrentCamera
	local anchorPosition = if isReset and camera
		then camera.CFrame.Position + camera.CFrame.LookVector * 120 + Vector3.new(0, 40, 0)
		elseif typeof(event.position) == "Vector3" then event.position + Vector3.new(0, 70, 0)
		else (if camera then camera.CFrame.Position else Vector3.zero) + Vector3.new(0, 70, 0)
	local r, detail = rank(event), quality()
	local stage = event.resetStage or 3
	local token = skyEnvironment(
		if isReset
			then (if stage == 1 then 0.4 elseif stage == 2 then 0.7 else 1)
			else math.clamp(r / 6, 0.25, 1)
	)
	local handle, reason
	if rifts then
		handle, reason = rifts.Start({
			eventId = if isReset and not impact
				then "reset:" .. tostring(deadline)
				else tostring(event.eventId or ("sky:" .. tostring(startTime))),
			mode = if impact then "Collapse" elseif isReset then "Reset" else "Spawn",
			startTime = startTime,
			deadline = untilTime,
			resetDeadline = deadline,
			position = anchorPosition,
			sourceAnchor = if not isReset then event.sourceAnchor else nil,
			seed = event.seed or 1,
			rank = r,
			requestedRifts = if isReset then 3 else math.clamp(r - 1, 1, 3),
			height = if isReset then 68 else 56,
		}, t, detail, reducedMotion())
	end
	sky = {
		environmentToken = token,
		event = event,
		quality = detail,
		objects = {},
		meteors = {},
		startedAt = startTime,
		untilTime = untilTime,
		reset = isReset,
		impact = impact,
		resetDeadline = deadline,
		resetStage = stage,
		qaPreview = event.qaPreview == true,
		rank = r,
		centre = anchorPosition,
		cameraFollowing = isReset,
		riftHandle = handle,
		riftReason = reason,
	}
	local rng = Random.new(event.seed or 1)
	for index = 1, 6 do
		sky.meteors[index] = {
			origin = anchorPosition + Vector3.new(
				rng:NextNumber(-70, 70),
				rng:NextNumber(20, 60),
				rng:NextNumber(-40, 40)
			),
			phase = index / 6,
		}
	end
	audio(
		if event.mutationId == "Glitched"
			then "SFX_GlitchSpawn"
			elseif isReset then "SFX_ResetWarning"
			else "SFX_RiftOpen",
		if isReset then "critical" else "global",
		nil,
		nil,
		event.qaPreview
	)
end
local function finishShakeCleanup(entry: any, shakeState: any)
	local current = entry.model.Parent ~= nil
		and entry.model:GetAttribute("BindGeneration") == shakeState.bindGeneration
		and entry.model:GetAttribute("PresentationRevision") == shakeState.presentationRevision
	if entry.model:GetAttribute("CreatureLocalVisual") == true then
		current = current
			and require(script.Parent.CreaturePresentationController).IsPresentationCurrent(
				entry.model,
				shakeState.presentationRevision,
				shakeState.bindGeneration
			)
	end
	-- Motor transforms run as a deferred engine batch before physics. Destroying
	-- a motor before its final identity batch can bake its old pose into a weld.
	-- This function runs after that batch, with the source internal welds disabled.
	for _, motor in shakeState.motors do
		motor:Destroy()
	end
	for _, resting in shakeState.restingParts do
		local root, part = resting.root, resting.part
		if current and root.Parent and part.Parent and part.Massless and not part.CanCollide then
			part.CFrame = root.CFrame * resting.relative
		end
	end
	for _, weld in shakeState.welds do
		if current and weld.instance.Parent then
			weld.instance.Enabled = weld.enabled
		end
	end
	if entry.shake == shakeState then
		entry.shake = nil
	end
end
local function stopShake(entry: any)
	local shakeState = entry.shake
	if not shakeState or shakeState.pendingCleanup then
		return
	end
	shakeState.pendingCleanup = true
	for _, motor in shakeState.motors do
		motor.Transform = CFrame.identity
	end
	table.insert(pendingShakeCleanups, { entry = entry, shake = shakeState })
	if not shakeCleanupConnection then
		-- One shared physics-boundary connection also completes teardown after Stop.
		-- It owns no gameplay timers and disconnects once every visual is restored.
		shakeCleanupConnection = RunService.PostSimulation:Connect(function()
			for _, pending in pendingShakeCleanups do
				finishShakeCleanup(pending.entry, pending.shake)
			end
			table.clear(pendingShakeCleanups)
			if shakeCleanupConnection then
				shakeCleanupConnection:Disconnect()
				shakeCleanupConnection = nil
			end
		end)
	end
end
local function shake(entry: any, remaining: number, warning: number, t: number)
	local model = entry.model
	if reducedMotion() then
		stopShake(entry)
		return
	end
	local root = model.PrimaryPart
	if not root then
		return
	end
	if entry.shake and entry.shake.pendingCleanup then
		return
	end
	if not entry.shake then
		local welds, motors, restingParts = {}, {}, {}
		for _, descendant in model:GetDescendants() do
			if
				descendant:IsA("WeldConstraint")
				and descendant.Part0 == root
				and descendant.Part1
				and descendant.Part1:IsDescendantOf(model)
				and descendant.Part1 ~= root
			then
				local part = descendant.Part1
				if part.Massless and not part.CanCollide then
					local motor = Instance.new("Motor6D")
					motor.Name, motor.Part0, motor.Part1, motor.C0 =
						"Phase12VisualWobble", root, part, root.CFrame:ToObjectSpace(part.CFrame)
					table.insert(welds, { instance = descendant, enabled = descendant.Enabled })
					descendant.Enabled = false
					motor.Parent = root
					table.insert(motors, motor)
					table.insert(restingParts, { root = root, part = part, relative = motor.C0 })
				end
			end
		end
		entry.shake = {
			welds = welds,
			motors = motors,
			restingParts = restingParts,
			bindGeneration = model:GetAttribute("BindGeneration"),
			presentationRevision = model:GetAttribute("PresentationRevision"),
		}
	end
	local amount = 1 - math.clamp(remaining / math.max(0.001, warning), 0, 1)
	local presentation = Config.Presentation
	local amplitude, angle =
		presentation.EscapeTranslationMin
			+ (presentation.EscapeTranslationMax - presentation.EscapeTranslationMin) * amount,
		math.rad(
			presentation.EscapeRotationMin
				+ (presentation.EscapeRotationMax - presentation.EscapeRotationMin) * amount
		)
	local wave = math.sin(t * math.pi * 2 * Config.Presentation.EscapeHz)
	local transform = CFrame.new(amplitude * wave, 0, 0) * CFrame.Angles(0, 0, angle * wave)
	for _, motor in entry.shake.motors do
		motor.Transform = motor.C0:Inverse() * transform * motor.C0
	end
end
local function unregister(model: Model)
	local entry = models[model]
	if not entry then
		return
	end
	stopShake(entry)
	Appearance.Restore(model)
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	models[model] = nil
	if model:GetAttribute("CarrierUserId") == player.UserId then
		Hud.Escape("", nil, false)
	end
end
local function register(instance: Instance)
	if
		not instance:IsA("Model")
		or models[instance]
		or instance:GetAttribute("CreatureProxy") == true
	then
		return
	end
	local entry = {
		model = instance,
		connections = {},
		signature = nil,
		geometryRevision = 0,
		distance = math.huge,
	}
	table.insert(
		entry.connections,
		instance.DescendantAdded:Connect(function(child)
			if child:IsA("BasePart") then
				entry.geometryRevision += 1
			end
		end)
	)
	table.insert(
		entry.connections,
		instance.DescendantRemoving:Connect(function(child)
			if child:IsA("BasePart") then
				entry.geometryRevision += 1
			end
		end)
	)
	models[instance] = entry
	table.insert(
		entry.connections,
		instance:GetAttributeChangedSignal("BrainrotDisplayState"):Connect(function()
			if
				instance:GetAttribute("BrainrotDisplayState") ~= "Carried"
				and instance:GetAttribute("CarrierUserId") == player.UserId
			then
				Hud.Escape("", nil, false)
			end
		end)
	)
	table.insert(
		entry.connections,
		instance.Destroying:Connect(function()
			unregister(instance)
		end)
	)
	table.insert(
		entry.connections,
		instance.AncestryChanged:Connect(function()
			if not instance:IsDescendantOf(Workspace) then
				unregister(instance)
			end
		end)
	)
end
local function presentationState(model: Model): string
	local state = model:GetAttribute("Phase12PresentationState")
		or model:GetAttribute(DisplayConfig.Attributes.DisplayState)
	if state == "EscapeWarning" then
		return "EscapeWarning"
	end
	if state == "Cart" then
		return "Cargo"
	elseif state == "Deposited" then
		return "Banked"
	elseif state == "Carried" then
		return "Carried"
	elseif state == "Equipped" then
		return "Equipped"
	end
	return if model:GetAttribute("Captured") == true
		then "Sleeping"
		else (if type(state) == "string" then state else "Awake")
end
local function updateModels(t: number, refreshAppearance: boolean)
	local camera = Workspace.CurrentCamera
	local candidates = {}
	local imminent = {}
	for model, entry in models do
		if not Visibility.IsVisible(model) then
			stopShake(entry)
			entry.signature = nil
			continue
		end
		if model.Parent == nil then
			unregister(model)
		else
			if refreshAppearance then
				local root = model.PrimaryPart
				entry.distance = if camera and root
					then (root.Position - camera.CFrame.Position).Magnitude
					else math.huge
				table.insert(candidates, { entry = entry, distance = entry.distance })
			end
			local deadline = model:GetAttribute("Phase12EscapeDeadline")
			local warning = model:GetAttribute("Phase12EscapeWarningSeconds")
			local state = presentationState(model)
			local isWarning = finite(deadline)
				and finite(warning)
				and warning > 0
				and deadline - t <= warning
				and (state == "Carried" or state == "Cargo" or state == "EscapeWarning")
				and model:GetAttribute("Phase10Banked") ~= true
			if entry.appearanceApplied then
				local visible = Nametags.isIdentifyingMetadataPermitted(model, t)
				local camouflageConcealed = not Nametags.isAimAssistEligible(model, t)
				local film = model:FindFirstChild("CartShieldCargoFilm")
				local aim = Workspace:FindFirstChild("SleepSelectedTarget")
				local semantic = (film and film:IsA("Highlight") and film.Enabled)
					or (aim and aim:IsA("Highlight") and aim.Enabled and aim.Adornee == model)
				Appearance.UpdateAppearanceState(
					model,
					if isWarning then "EscapeWarning" else state,
					{
						isVisible = visible,
						camouflageConcealed = camouflageConcealed,
						glowAdmitted = entry.detail == "Detailed",
						semanticOverlaysClear = not semantic,
						distanceStuds = entry.distance,
						detailLevel = quality(),
						warningProgress = if isWarning
							then math.clamp(1 - (deadline - t) / warning, 0, 1)
							else 0,
					}
				)
			end
			if
				finite(deadline)
				and finite(warning)
				and warning > 0
				and deadline - t <= warning
				and (state == "Carried" or state == "Cargo" or state == "EscapeWarning")
				and model:GetAttribute("Phase10Banked") ~= true
			then
				shake(entry, math.max(0, deadline - t), warning, t)
				local owner = model:GetAttribute("CarrierUserId")
					or model:GetAttribute("OwnerUserId")
				local container = model.Parent
				if
					owner == nil
					and container
					and container.Name == "CargoVisuals"
					and container.Parent
				then
					owner = container.Parent:GetAttribute("OwnerUserId")
				end
				if owner == player.UserId and state == "Carried" and deadline > t then
					table.insert(imminent, {
						model = model,
						deadline = deadline,
						id = tostring(model:GetAttribute("ItemId") or model.Name),
					})
				end
			else
				stopShake(entry)
			end
		end
	end
	table.sort(imminent, function(a, b)
		return if a.deadline ~= b.deadline then a.deadline < b.deadline else a.id < b.id
	end)
	local handWarning = imminent[1]
	local handDefinition = handWarning and Catalog.Get(handWarning.model:GetAttribute("BrainrotId"))
	if not handWarning or t - exactEscapeAt >= Exact.Transition.EscapeInterval then
		exactEscapeAt = t
		Hud.Escape(
			if handDefinition then handDefinition.displayName else "",
			handWarning and handWarning.deadline,
			handWarning ~= nil,
			handWarning and handWarning.model
		)
	end

	if not refreshAppearance then
		return
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	for index, candidate in candidates do
		local entry = candidate.entry
		local model = entry.model
		local definition = Catalog.Get(
			(model:GetAttribute("BrainrotId") or model:GetAttribute("CosmeticSpeciesId"))
		)
		if definition then
			local mutation = Rules.NormalizeMutation(
				model:GetAttribute("MutationId")
					or model:GetAttribute("CosmeticMutationId")
					or model:GetAttribute(DisplayConfig.Attributes.MutationId)
			) or "None"
			local state = presentationState(model)
			local detail = if index <= Config.Presentation.MaxDetailedGlows
					and candidate.distance < 100
					and Nametags.isIdentifyingMetadataPermitted(model, t)
				then "Detailed"
				else "Compact"
			local film = model:FindFirstChild("CartShieldCargoFilm", true)
			local aim = Workspace:FindFirstChild("SleepSelectedTarget")
			local semantic = (film and film:IsA("Highlight") and film.Enabled)
				or (aim and aim:IsA("Highlight") and aim.Enabled and aim.Adornee == model)
			local signature = mutation
				.. ":"
				.. definition.tier
				.. ":"
				.. state
				.. ":"
				.. detail
				.. ":"
				.. tostring(model:GetAttribute("BrainrotCamouflageSnapshot"))
				.. ":"
				.. tostring(entry.geometryRevision)
				.. ":"
				.. tostring(semantic)
			if signature ~= entry.signature then
				entry.signature = signature
				local camouflageConcealed = not Nametags.isAimAssistEligible(model, t)
				entry.detail, entry.appearanceApplied = detail, true
				local deadline, warning =
					model:GetAttribute("Phase12EscapeDeadline"),
					model:GetAttribute("Phase12EscapeWarningSeconds")
				local warningProgress = if finite(deadline)
						and finite(warning)
						and warning > 0
						and (state == "Carried" or state == "Cargo")
					then math.clamp(1 - (deadline - t) / warning, 0, 1)
					else 0
				Appearance.ApplyAppearance(
					model,
					definition.tier,
					mutation,
					if warningProgress > 0 then "EscapeWarning" else state,
					detail,
					{
						isVisible = Nametags.isIdentifyingMetadataPermitted(model, t),
						camouflageConcealed = camouflageConcealed,
						glowAdmitted = detail == "Detailed",
						semanticOverlaysClear = not semantic,
						distanceStuds = candidate.distance,
						detailLevel = quality(),
						warningProgress = warningProgress,
					}
				)
			end
		end
	end
end
local function mainCelebration(batch: any)
	local items = batch.items
	if #items == 0 then
		return
	end
	table.sort(items, function(a, b)
		return stronger(b, a)
	end)
	local strongest = items[#items]
	local owner = batch.userId == player.UserId
	local position = strongest.baseSignPosition or strongest.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local camera = Workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - position).Magnitude else math.huge
	local full = owner or distance < 120
	if full and #celebrations >= Config.Presentation.MaxBankCelebrations then
		if owner then
			local dropped = table.remove(celebrations, 1)
			dropped.untilTime = 0
		else
			full = false
		end
	end
	if not full then
		burst(
			position + Vector3.new(0, 16, 0),
			colours(strongest).highlight,
			6,
			4,
			1,
			strongest.qaPreview
		)
		return
	end
	local r = rank(strongest)
	local duration = ({
		[0] = 0.6,
		[1] = 1.5,
		[2] = 2.5,
		[3] = 3.5,
		[4] = 4.5,
		[5] = 5.5,
		[6] = 6.5,
	})[r]
	local bursts = ({ [0] = 1, [1] = 2, [2] = 3, [3] = 4, [4] = 5, [5] = 6, [6] = 8 })[r]
	local token = generation
	local previewToken = previewGeneration
	local celebration = {
		untilTime = now() + duration + 1.2,
		owner = owner,
		qaPreview = strongest.qaPreview == true,
	}
	table.insert(celebrations, celebration)
	local p = colours(strongest)
	local platform = strongest.platformPosition
	if typeof(platform) == "Vector3" then
		local sparklerCount = if quality() == "Low" then 2 else 4
		for index = 1, sparklerCount do
			local angle = index * math.pi * 0.5
			burst(
				platform + Vector3.new(math.cos(angle) * 2, 0.4, math.sin(angle) * 2),
				p.highlight,
				8,
				3,
				1,
				strongest.qaPreview
			)
		end
	end
	audio("SFX_BankFanfare", "bank", position, owner, strongest.qaPreview)
	for index = 1, bursts do
		schedule((index - 1) * duration / bursts, function()
			if
				not started
				or generation ~= token
				or celebration.untilTime <= now()
				or (strongest.qaPreview == true and previewToken ~= previewGeneration)
			then
				return
			end
			local offset = Vector3.new(
				math.sin(index * 2.4) * math.min(10, 4 + r),
				16 + (index % 2) * 3,
				math.cos(index * 2.4) * math.min(10, 4 + r)
			)
			local params = RaycastParams.new()
			params.FilterType, params.FilterDescendantsInstances =
				Enum.RaycastFilterType.Exclude, { visualFolder :: Folder }
			local roof = Workspace:Raycast(position, Vector3.new(0, offset.Y + 2, 0), params)
			if roof then
				offset = Vector3.new(offset.X * 0.3, math.max(2, roof.Distance - 2), offset.Z * 0.3)
			end
			local count = ({ High = 32, Medium = 20, Low = 12 })[quality()]
			if reducedMotion() then
				count = math.floor(count * 0.5)
			end
			burst(
				position + offset,
				if index % 2 == 0 then p.primary else p.highlight,
				count,
				8 + r * 1.6,
				1.2,
				strongest.qaPreview
			)
			audio("SFX_Fireworks", "transient", position, owner, strongest.qaPreview)
		end)
	end
end
local function pulsePlatform(event: any)
	local id = event.instanceId or event.individualId
	if type(id) ~= "string" then
		return
	end
	for _, platform in CollectionService:GetTagged("BrainrotStoragePlatform") do
		if
			platform:IsA("BasePart")
			and platform:GetAttribute("StorageItemId") == id
			and SlotPresentation.IsActive(platform) ~= false
		then
			local pulse = Instance.new("SelectionBox")
			pulse.Name, pulse.Adornee, pulse.Color3, pulse.LineThickness =
				"Phase12BankPulse", platform, colours(event).highlight, 0.05
			pulse.SurfaceTransparency, pulse.Parent = 1, visualFolder
			local base = platform.Parent
			if base then
				local connection = base:GetAttributeChangedSignal("BasePresentationState")
					:Connect(function()
						if SlotPresentation.IsActive(platform) == false then
							pulse:Destroy()
						end
					end)
				pulse.Destroying:Once(function()
					connection:Disconnect()
				end)
			end
			TweenService:Create(pulse, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			schedule(0.3, function()
				pulse:Destroy()
			end)
			break
		end
	end
end
local function bank(event: any)
	if event.firstBank ~= true then
		return
	end
	local userId = event.userId
	if not finite(userId) then
		return
	end
	local pending = pendingBanks[userId]
	if not pending then
		pending = { userId = userId, items = {}, ids = {}, startedAt = now() }
		pendingBanks[userId] = pending
		local token = generation
		schedule(Config.BankBatchSeconds, function()
			if token ~= generation or pendingBanks[userId] ~= pending then
				return
			end
			pendingBanks[userId] = nil
			mainCelebration(pending)
		end)
	end
	local receipts = if type(event.receipts) == "table" and #event.receipts > 0
		then event.receipts
		else { event }
	for _, receipt in receipts do
		local id = receipt.instanceId or receipt.ItemId
		if id and not pending.ids[id] then
			pending.ids[id] = true
			local item = table.clone(event)
			for key, value in receipt do
				item[key] = value
			end
			item.receipts = nil
			table.insert(pending.items, item)
		end
	end
end
local function queueSpawnFlush()
	if spawnFlushScheduled or #spawnBurst == 0 then
		return
	end
	spawnFlushScheduled = true
	local coordinatorToken, burstToken, cycleToken =
		generation, spawnBurstGeneration, spawnReceiptCycle
	schedule(Config.Presentation.SpawnBurstSeconds, function()
		-- Only the callback owning this burst latch may retire it.
		if coordinatorToken ~= generation or burstToken ~= spawnBurstGeneration then
			return
		end
		spawnFlushScheduled = false
		if cycleToken ~= Workspace:GetAttribute("Phase12CycleId") then
			return
		end
		local eligible = {}
		for index = #spawnBurst, 1, -1 do
			local item = spawnBurst[index]
			if item.receiptCycle == cycleToken then
				table.insert(eligible, item)
				table.remove(spawnBurst, index)
			end
		end
		if #eligible == 0 then
			return
		end
		table.sort(eligible, stronger)
		local strongest = eligible[1]
		enqueue(strongest)
		local r = rank(strongest)
		if r >= 2 then
			beginSky(strongest, ({ [2] = 1.2, [3] = 2.5, [4] = 3.5, [5] = 4.5, [6] = 5 })[r])
		end
	end)
end
local function synchronizeSpawnCycle(cycle: any)
	if spawnCycleSynchronized and spawnReceiptCycle == cycle then
		return
	end
	local precedingCycle = spawnReceiptCycle
	spawnCycleSynchronized, spawnReceiptCycle = true, cycle
	spawnBurstGeneration += 1
	spawnFlushScheduled = false
	for index = #spawnBurst, 1, -1 do
		local item = spawnBurst[index]
		-- At first synchronization, an unversioned legacy receipt belongs to the
		-- just-observed cycle. Versioned future receipts wait for matching sync.
		if item.receiptCycle == nil and precedingCycle == nil then
			item.receiptCycle = cycle
		end
		local future = cycle == nil
			or (finite(item.receiptCycle) and finite(cycle) and item.receiptCycle > cycle)
		if item.receiptCycle ~= cycle and not future then
			table.remove(spawnBurst, index)
		end
	end
	queueSpawnFlush()
end
local function finishRebirth(reason: string)
	local state = rebirth
	if not state then
		return
	end
	rebirth = nil
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local observation = remotes and remotes:FindFirstChild("Phase13ClientObservation")
	if observation and observation:IsA("RemoteEvent") then
		pcall(function()
			observation:FireServer({
				kind = "Cinematic",
				operationId = state.operationId,
				reason = reason,
				elapsed = math.clamp(now() - state.at, 0, 10),
			})
		end)
	end
	if rifts and state.rift then
		rifts.Stop(state.rift)
	end
	for _, connection in state.connections do
		connection:Disconnect()
	end
	for _, copy in state.copies do
		pcall(Appearance.Restore, copy.model)
		copy.model:Destroy()
	end
	if state.gui then
		state.gui:Destroy()
	end
	local camera = Workspace.CurrentCamera
	cameraRestores:Begin({
		generation = generation,
		camera = state.camera,
		cameraType = state.cameraType,
		subject = state.cameraSubject,
		character = state.character,
		departing = reason == "Respawn",
		deadline = now() + 10,
	})
	local subject, restoreStatus = cameraRestores:Step(cameraRestoreContext())
	cameraRestoreLastStatus = restoreStatus
	if camera == state.camera and (restoreStatus == "Ready" or restoreStatus == "Waiting") then
		camera.CameraType = state.cameraType
		if restoreStatus == "Ready" then
			camera.CameraSubject = subject
		end
		camera.CFrame = state.cameraFrame
		camera.FieldOfView = state.fieldOfView
	end
	player:SetAttribute("Phase13CinematicActive", state.previousInputFlag)
	if state.controls and state.controlsWereEnabled then
		pcall(function()
			-- A menu or daze opened during the cinematic retains the input lock.
			require(script.Parent.PlayerDazeController).ResumeDefaultControlsWhenAllowed(
				state.controls
			)
		end)
	end
	if state.onComplete then
		pcall(state.onComplete, reason)
	end
end
local function visibleResetSnapshot(snapshot: any): boolean
	local camera = Workspace.CurrentCamera
	if not camera or typeof(snapshot.Pose) ~= "CFrame" or typeof(snapshot.Bounds) ~= "Vector3" then
		return false
	end
	if snapshot.RegionId and not Visibility.IsRegionVisible(snapshot.RegionId) then
		return false
	end
	local point, onScreen = camera:WorldToViewportPoint(snapshot.Pose.Position)
	if not onScreen or point.Z <= 0 then
		return false
	end
	local delta = snapshot.Pose.Position - camera.CFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, visualFolder }
	local hit = Workspace:Raycast(camera.CFrame.Position, delta, params)
	return not hit or hit.Distance >= delta.Magnitude - snapshot.Bounds.Magnitude * 0.5
end
local function resetRetirement(event: any)
	if type(event.representations) ~= "table" then
		return
	end
	local cycle = event.cycleId or event.retiredGeneration
	if cycle ~= resetSubstituteGeneration then
		resetSubstituteGeneration = cycle
		resetSubstituteCount = 0
		table.clear(resetSubstituteSeen)
	end
	for _, snapshot in event.representations do
		if resetSubstituteCount >= 42 or #resetSubstitutes >= 42 then
			break
		end
		local id = snapshot.ItemId
		if
			type(id) ~= "string"
			or resetSubstituteSeen[id]
			or not visibleResetSnapshot(snapshot)
		then
			continue
		end
		-- Never select banked originals or committed cargo from a broad world scan.
		for model in models do
			if
				model:GetAttribute("ItemId") == id
				and model:GetAttribute("Phase10Banked") ~= true
				and Visibility.IsVisible(model)
			then
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = 1
					end
				end
			end
		end
		resetSubstituteSeen[id] = true
		resetSubstituteCount += 1
		local part = table.remove(resetSubstitutePool) or Instance.new("Part")
		part.Name = "ResetPhaseSubstitute"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(160, 247, 255)
		local size = snapshot.Bounds
		size = Vector3.new(
			math.clamp(size.X, 0.2, 40),
			math.clamp(size.Y, 0.2, 40),
			math.clamp(size.Z, 0.2, 40)
		)
		part.Size = size
		part.CFrame = snapshot.Pose
		part.Transparency = 0
		part.Parent = visualFolder
		table.insert(resetSubstitutes, { part = part, size = size, at = now() })
	end
end
local function stepPhase13(t: number)
	if cameraRestores:Pending() then
		local subject, status = cameraRestores:Step(cameraRestoreContext())
		cameraRestoreLastStatus = status
		if status == "Ready" then
			Workspace.CurrentCamera.CameraSubject = subject
		end
	end
	for i = #resetSubstitutes, 1, -1 do
		local entry = resetSubstitutes[i]
		local sample = PresentationRules.Reset(t - entry.at, reducedMotion())
		if sample.done then
			entry.part.Parent = nil
			table.insert(resetSubstitutePool, entry.part)
			table.remove(resetSubstitutes, i)
		else
			entry.part.Size = entry.size * sample.scale
			entry.part.Transparency = sample.transparency
		end
	end
	local state = rebirth
	if not state then
		return
	end
	if
		(sky and sky.reset)
		or player.Character ~= state.character
		or not state.plot
		or not state.plot:IsDescendantOf(Workspace)
		or not state.humanoid.Parent
		or state.humanoid.Health <= 0
	then
		finishRebirth("Interrupted")
		return
	end
	if state.rift and t - state.at >= 1 then
		local diagnostics = rifts and rifts.GetDiagnostics()
		if diagnostics and diagnostics.pendingImages > 0 then
			reportRiftAsset("RIFT_NOT_RESIDENT")
			rifts.Stop(state.rift)
			state.rift = nil
			state.reducedMotion, state.presentationFallback = true, true
			for _, copy in state.copies do
				Appearance.Restore(copy.model)
				copy.model:Destroy()
			end
			table.clear(state.copies)
			if state.camera == Workspace.CurrentCamera then
				state.camera.CameraType, state.camera.CameraSubject =
					state.cameraType, state.cameraSubject
				state.camera.CFrame, state.camera.FieldOfView = state.cameraFrame, state.fieldOfView
			end
		end
	end
	local motionReduced = state.reducedMotion or reducedMotion()
	local sample = PresentationRules.Rebirth(t - state.at, motionReduced)
	if sample.done then
		finishRebirth("Completed")
		return
	end
	state.skip.Active = sample.canSkip
	state.skip.Text = if sample.canSkip then CombatStrings.Skip else CombatStrings.SkipWait
	if state.fade then
		state.fade.BackgroundTransparency = 1 - sample.fade * 0.7
	end
	if not motionReduced and state.camera == Workspace.CurrentCamera then
		local camera = state.camera
		local framing = CFrame.lookAt(
			state.centre + Vector3.new(16, 13, 25),
			state.centre + Vector3.new(0, 5, 0)
		)
		local zoom = CFrame.lookAt(
			state.centre + Vector3.new(13, 11, 22),
			state.centre + Vector3.new(0, 6, 0)
		)
		camera.CFrame = state.cameraFrame
			:Lerp(framing, math.clamp((t - state.at), 0, 1))
			:Lerp(zoom, sample.intake * 0.2)
		camera.FieldOfView = state.fieldOfView
	end
	if rifts and state.rift then
		if sample.phase == "Contract" and not state.collapsed then
			rifts.Collapse(state.rift, state.at + 4.5, 1)
			state.collapsed = true
		end
		rifts.Step(t, Vector3.zero, quality(), motionReduced)
	end
	state.title.Text = if sample.phase == "Reveal"
		then CombatStrings.RebirthComplete
		else CombatStrings.Rebirth
	local window =
		PresentationRules.CopyWindow(t - state.at, state.descriptorCount, quality(), state.cash)
	if motionReduced then
		if #state.copies > 0 then
			for _, copy in state.copies do
				pcall(Appearance.Restore, copy.model)
				copy.model:Destroy()
			end
			table.clear(state.copies)
		end
		state.copyGroup = -1
	elseif state.copyGroup ~= window.group or state.copyCap ~= window.cap then
		state.loadGroup(window)
	end
	if not state.cash then
		local remaining = if motionReduced
			then 0
			else math.max(0, state.totalSacrificed - window.last)
		state.summary.Text = string.format(
			CombatStrings.CollectionRebirth,
			state.totalSacrificed,
			if remaining > 0 then string.format(CombatStrings.More, remaining) else ""
		)
	end
	for _, copy in state.copies do
		local a = PresentationRules.CopyProgress(window.progress, copy.index, #state.copies)
		local start = copy.origin
		local position = start:Lerp(state.riftPosition, a)
			+ Vector3.new(
				0,
				if motionReduced then 0 else math.sin(a * math.pi) * (3 + copy.index * 0.25),
				0
			)
		local size = math.max(
			0.02,
			1 - (if sample.phase == "Contract" or sample.phase == "Reveal" then 1 else a * 0.9)
		)
		copy.model:PivotTo(
			CFrame.new(position) * CFrame.Angles(0, if motionReduced then 0 else a * math.pi * 2, 0)
		)
		copy.model:ScaleTo(copy.scale * size)
		for _, part in copy.parts do
			part.Transparency = if motionReduced
				then math.max(copy.transparency[part], sample.intake)
				else copy.transparency[part]
		end
	end
end
function Controller.StartRebirthPresentation(receipt: any, options: any?): (boolean, string?)
	options = options or {}
	local cinematicReduced = options.reducedMotion == true or reducedMotion()
	local presentationFallback = false
	if
		not started
		or type(receipt) ~= "table"
		or (receipt.state ~= "Confirmed" and options.confirmed ~= true)
	then
		return false, "DURABLE_CONFIRMATION_REQUIRED"
	end
	local operationId = receipt.operationId or (receipt.receipt and receipt.receipt.OperationId)
	if type(operationId) ~= "string" or rebirthSeen[operationId] then
		return false, "ALREADY_PRESENTED"
	end
	if sky and sky.reset then
		return false, "RESET_HAS_PRIORITY"
	end
	local preparedCharacter = player.Character
	local preparedHumanoid = preparedCharacter
		and preparedCharacter:FindFirstChildOfClass("Humanoid")
	local preparedCamera, preparedPlot = Workspace.CurrentCamera, options.plot
	local preparation = rebirthPreparations:Begin(generation, function(): boolean
		return player.Character == preparedCharacter
			and preparedCharacter ~= nil
			and preparedCharacter:IsDescendantOf(Workspace)
			and preparedHumanoid ~= nil
			and preparedHumanoid.Parent == preparedCharacter
			and preparedHumanoid.Health > 0
			and Workspace.CurrentCamera == preparedCamera
			and preparedCamera ~= nil
			and typeof(preparedPlot) == "Instance"
			and preparedPlot:IsA("Model")
			and preparedPlot:IsDescendantOf(Workspace)
			and not (sky and sky.reset)
	end)
	-- Rewards are already durable. Template preparation delays only the local
	-- presentation, with no control lock and a bounded fallback for unavailable art.
	if ReplicatedStorage:GetAttribute("Phase13CreatureProtocolEnabled") == true then
		rebirthSeen[operationId] = true
		local samples = options.sacrificedIndividuals or {}
		local untilTime = os.clock() + 2
		local originalCharacter = player.Character
		repeat
			local missing = false
			for index, item in samples do
				if index > 48 then
					break
				end
				if not TemplateProvider.Get(item.speciesId or item.BrainrotId or "", "Full") then
					missing = true
				end
			end
			if not missing then
				break
			end
			RunService.Heartbeat:Wait()
		until os.clock() >= untilTime
			or player.Character ~= originalCharacter
			or sky and sky.reset
			or not rebirthPreparations:IsCurrent(preparation)
		if
			not rebirthPreparations:IsCurrent(preparation)
			or player.Character ~= originalCharacter
			or sky and sky.reset
		then
			return false, "PRESENTATION_CONTEXT_UNAVAILABLE"
		end
	end
	local plot = options.plot
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = Workspace.CurrentCamera
	if
		typeof(plot) ~= "Instance"
		or not plot:IsA("Model")
		or not plot:IsDescendantOf(Workspace)
		or not camera
		or not humanoid
		or humanoid.Health <= 0
	then
		return false, "PRESENTATION_CONTEXT_UNAVAILABLE"
	end
	if not rebirthPreparations:IsCurrent(preparation) then
		return false, "PRESENTATION_CONTEXT_UNAVAILABLE"
	end
	finishRebirth("Superseded")
	-- Completion callbacks may yield; a Stop or newer confirmation still wins.
	if not rebirthPreparations:Commit(preparation) then
		return false, "PRESENTATION_CONTEXT_UNAVAILABLE"
	end
	cameraRestores:Cancel()
	cameraRestoreLastStatus = "Superseded"
	clearSky()
	rebirthSeen[operationId] = true
	local centre = plot:GetPivot().Position
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		centre = Vector3.new(centre.X, root.Position.Y - 3, centre.Z)
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "Phase13RebirthPresentation"
	screen.ResetOnSpawn = false
	-- Global reset/escape warnings and aggregate headlines retain layer90.
	screen.DisplayOrder = 89
	screen.IgnoreGuiInset = true
	screen.Parent = player.PlayerGui
	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.fromRGB(12, 9, 25)
	fade.BackgroundTransparency = 1
	fade.Parent = screen
	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.12)
	title.Size = UDim2.new(0.9, 0, 0, 80)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 32
	title.TextColor3 = Color3.fromRGB(227, 242, 255)
	title.Text = CombatStrings.Rebirth
	title.Parent = screen
	local summary = Instance.new("TextLabel")
	summary.AnchorPoint = Vector2.new(0.5, 0)
	summary.Position = UDim2.fromScale(0.5, 0.24)
	summary.Size = UDim2.new(0.9, 0, 0, 50)
	summary.BackgroundTransparency = 1
	summary.TextWrapped = true
	summary.Font = Enum.Font.Gotham
	summary.TextSize = 18
	summary.TextColor3 = Color3.fromRGB(218, 235, 255)
	summary.Parent = screen
	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -24, 1, -24)
	skip.Size = UDim2.fromOffset(180, 48)
	skip.BackgroundColor3 = Color3.fromRGB(35, 52, 75)
	skip.TextColor3 = Color3.new(1, 1, 1)
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 18
	skip.Active = false
	skip.Text = CombatStrings.SkipWait
	skip.Parent = screen
	local state = {
		operationId = operationId,
		at = now(),
		plot = plot,
		character = character,
		humanoid = humanoid,
		camera = camera,
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		cameraFrame = camera.CFrame,
		fieldOfView = camera.FieldOfView,
		previousInputFlag = player:GetAttribute("Phase13CinematicActive"),
		reducedMotion = cinematicReduced,
		presentationFallback = presentationFallback,
		presentationStartedAt = now(),
		centre = centre,
		riftPosition = centre + Vector3.new(0, 12, -4),
		gui = screen,
		title = title,
		summary = summary,
		fade = fade,
		skip = skip,
		copies = {},
		connections = {},
		onComplete = options.onComplete,
	}
	rebirth = state
	player:SetAttribute("Phase13CinematicActive", true)
	local ok, controls = pcall(function()
		return require(assert(player.PlayerScripts:FindFirstChild("PlayerModule"))):GetControls()
	end)
	if ok and controls then
		state.controls = controls
		state.controlsWereEnabled = controls.controlsEnabled ~= false
		controls:Disable()
	end
	if not cinematicReduced then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	table.insert(
		state.connections,
		skip.Activated:Connect(function()
			if now() - state.at >= 1 then
				finishRebirth("Skipped")
			end
		end)
	)
	table.insert(
		state.connections,
		humanoid.Died:Connect(function()
			finishRebirth("Death")
		end)
	)
	table.insert(
		state.connections,
		player.CharacterRemoving:Connect(function()
			finishRebirth("Respawn")
		end)
	)
	table.insert(
		state.connections,
		plot.Destroying:Connect(function()
			finishRebirth("PlotRemoved")
		end)
	)
	table.insert(
		state.connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if
				not processed
				and (input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape)
				and now() - state.at >= 1
			then
				finishRebirth("Skipped")
			end
		end)
	)
	local descriptors = options.sacrificedIndividuals
		or (receipt.result and receipt.result.sacrificedIndividuals)
		or {}
	if type(descriptors) ~= "table" then
		descriptors = {}
	end
	local cash = options.branch == "Cash"
	local sacrificedCount = receipt.result and receipt.result.sacrificedIndividuals
	local total = if cash
		then 12
		elseif finite(sacrificedCount) and sacrificedCount >= 0 then math.floor(
			sacrificedCount
		)
		else #descriptors
	local copies = PresentationRules.CopyCount(total, quality())
	summary.Text = if cash
		then CombatStrings.CashRebirth
		else string.format(
			CombatStrings.CollectionRebirth,
			total,
			if total > copies then string.format(CombatStrings.More, total - copies) else ""
		)
	state.cash, state.totalSacrificed = cash, total
	state.descriptorCount = math.min(48, #descriptors)
	state.copyGroup, state.copyCap = -1, 0
	state.loadGroup = function(window)
		for _, copy in state.copies do
			pcall(Appearance.Restore, copy.model)
			copy.model:Destroy()
		end
		table.clear(state.copies)
		state.copyGroup, state.copyCap = window.group, window.cap
		for descriptorIndex = window.first, window.last do
			local index = descriptorIndex - window.first + 1
			local item = descriptors[descriptorIndex]
			local model = not cash
				and item
				and TemplateProvider.Get(item.speciesId or item.BrainrotId or "", "Full")
			local clone
			if model and model:IsA("Model") then
				clone = model:Clone()
				local speciesId = item.speciesId or item.BrainrotId
				local definition = Catalog.Get(speciesId)
				local mutationId = Rules.NormalizeMutation(item.mutationId or item.MutationId)
					or "None"
				clone:SetAttribute("BrainrotId", speciesId)
				clone:SetAttribute("MutationId", mutationId)
				clone:SetAttribute("IndividualId", item.individualId)
				clone:SetAttribute(
					"DisplayName",
					if definition then definition.displayName else speciesId
				)
				require(ReplicatedStorage.Shared.Utility.WorldStudPolicy).ApplyModel(
					clone,
					"Creature"
				)
				pcall(
					Appearance.ApplyAppearance,
					clone,
					if definition then definition.tier else "Common",
					mutationId,
					"Banked",
					"Detailed",
					{
						isVisible = true,
						glowAdmitted = false,
						detailLevel = quality(),
						semanticOverlaysClear = true,
					}
				)
			elseif cash then
				clone = Instance.new("Model")
				local coin = Instance.new("Part")
				coin.Name = "CashIcon"
				coin.Size = Vector3.new(1.4, 1.4, 0.12)
				coin.Color = Color3.fromRGB(70, 225, 125)
				coin.Material = Enum.Material.Neon
				coin.Parent = clone
				clone.PrimaryPart = coin
				local face = Instance.new("SurfaceGui")
				face.Face = Enum.NormalId.Front
				face.Parent = coin
				local dollar = Instance.new("TextLabel")
				dollar.Size = UDim2.fromScale(1, 1)
				dollar.Text = "$"
				dollar.TextScaled = true
				dollar.BackgroundTransparency = 1
				dollar.TextColor3 = Color3.fromRGB(14, 65, 35)
				dollar.Font = Enum.Font.GothamBold
				dollar.Parent = face
			end
			if clone then
				local parts, transparency = {}, {}
				for _, child in clone:GetDescendants() do
					if child:IsA("BasePart") then
						child.Anchored = true
						child.CanCollide = false
						child.CanQuery = false
						child.CanTouch = false
						child.CastShadow = false
						table.insert(parts, child)
						transparency[child] = child.Transparency
					elseif
						child:IsA("LuaSourceContainer")
						or child:IsA("Constraint")
						or child:IsA("JointInstance")
						or child:IsA("Humanoid")
						or child:IsA("ParticleEmitter")
						or child:IsA("Light")
						or child:IsA("BillboardGui")
						or child:IsA("ProximityPrompt")
					then
						child:Destroy()
					end
				end
				for _, tagged in { clone, table.unpack(clone:GetDescendants()) } do
					for _, tag in CollectionService:GetTags(tagged) do
						CollectionService:RemoveTag(tagged, tag)
					end
				end
				local angle = (index - 1) / math.max(1, window.count) * math.pi * 2
				local origin = centre
					+ Vector3.new(math.cos(angle) * 7, 2 + index % 3, math.sin(angle) * 7)
				clone.Name = "RebirthPresentationCopy"
				clone:PivotTo(CFrame.new(origin))
				clone.Parent = visualFolder
				table.insert(state.copies, {
					model = clone,
					parts = parts,
					transparency = transparency,
					origin = origin,
					scale = clone:GetScale(),
					index = index,
				})
			end
		end
	end
	if not cinematicReduced then
		state.loadGroup(PresentationRules.CopyWindow(0, state.descriptorCount, quality(), cash))
	end
	if rifts and not presentationFallback then
		local appearanceRules = require(ReplicatedStorage.Shared.Utility.Phase13AppearanceRules)
		local selectedAsset, selectedVariant = appearanceRules.ResolveRift({
			Commerce = {
				Appearance = { RiftVariant = player:GetAttribute("Appearance_RiftVariant") },
				Entitlements = {
					VIP = options.vip == true,
					FIN_SINGULARITY = player:GetAttribute("Entitlement_FIN_SINGULARITY") == true,
				},
			},
		}, SpaceRift)
		state.rift = rifts.Start({
			variantAsset = selectedAsset,
			eventId = "rebirth:" .. operationId,
			mode = "Spawn",
			tint = if selectedVariant == "Riftgold"
				then Color3.fromRGB(255, 200, 70)
				else Color3.new(1, 1, 1),
			startTime = state.at + 0.3,
			deadline = state.at + 5.5,
			position = state.riftPosition,
			seed = 1,
			rank = 5,
			requestedRifts = 1,
			height = 17,
		}, state.at, quality(), cinematicReduced)
	end
	return true, nil
end

local function received(event: any)
	if
		type(event) ~= "table"
		or type(event.eventId) ~= "string"
		or type(event.kind) ~= "string"
		or seen[event.eventId]
	then
		return
	end
	event = table.clone(event)
	event.instanceId = event.instanceId or event.individualId
	event.name = event.name or event.displayName
	event.startTime = event.startTime or event.at
	event.baseSignPosition = event.baseSignPosition or event.signPosition
	local observedCycle = Workspace:GetAttribute("Phase12CycleId")
	if
		event.kind == "Spawn"
		and finite(event.cycleId)
		and finite(observedCycle)
		and event.cycleId < observedCycle
	then
		return
	end

	if event.cycleId and lastCycle and event.cycleId < lastCycle then
		return
	end
	seen[event.eventId] = true
	table.insert(seenOrder, event.eventId)
	if #seenOrder > 512 then
		seen[table.remove(seenOrder, 1)] = nil
	end
	if event.kind == "Bank" and event.firstBank ~= true then
		return
	end
	if event.kind == "BankAcknowledgement" then
		if event.userId == player.UserId then
			local rarityCatalog = require(ReplicatedStorage.Shared.Config.Rarities)
			local rare = (rarityCatalog.GetDisplayRank(event.rarity) or 0)
				>= (rarityCatalog.GetDisplayRank("Epic") or math.huge)
			Hud.Message(
				event.eventId,
				(if rare then "" else "Banked ") .. tostring(event.displayName or event.name),
				rare,
				tostring(event.rarity) .. " · @" .. player.Name .. "'s base"
			)
		end
		return
	end
	mirrorChat(event)
	if event.chatOnly == true then
		return
	end
	if event.kind == "BankReceipt" then
		pulsePlatform(event)
		return
	end
	if event.kind == "Progress" then
		if not event.qaPreview then
			setLatestProgress(event.progress)
		end
		if haulLabel and haulLabel.Visible and latestProgress and latestProgress.trackedUpgrade then
			local tracked = latestProgress.trackedUpgrade
			if finite(tracked.shortfall) then
				haulLabel.Text = cleanText(tracked.displayName or tracked.offerId)
					.. " · "
					.. CurrencyFormatter.FormatCompactCash(tracked.shortfall)
					.. " WALLET SHORTFALL"
			end
		end
		return
	end
	if event.kind == "Bank" and event.batchReady == true and type(event.records) == "table" then
		if not event.qaPreview then
			setLatestProgress(event.progress)
		end
		local batch = { userId = event.userId, items = {} }
		for _, receipt in event.records do
			local item = table.clone(event)
			for key, value in receipt do
				item[key] = value
			end
			item.kind, item.name, item.instanceId =
				"Bank", item.name or item.displayName, item.instanceId or item.individualId
			item.records, item.main = nil, nil
			item.baseSignPosition = event.baseSignPosition
			item.discovery = {
				species = receipt.firstSpecies == true,
				mutation = receipt.firstSpeciesMutation == true,
			}
			item.recordImproved = false
			for _, improved in receipt.recordImprovements or {} do
				if improved == true then
					item.recordImproved = true
				end
			end
			item.upgrade = if event.progress then event.progress.trackedUpgrade else nil
			table.insert(batch.items, item)
		end
		mainCelebration(batch)
		if event.qaPreview then
			local rarityCatalog = require(ReplicatedStorage.Shared.Config.Rarities)
			local rare = (rarityCatalog.GetDisplayRank(event.rarity) or 0)
				>= (rarityCatalog.GetDisplayRank("Epic") or math.huge)
			Hud.Message(
				event.eventId,
				(if rare then "" else "Banked ") .. tostring(event.displayName or event.name),
				rare,
				tostring(event.rarity) .. " · " .. tostring(event.location)
			)
		end

		if event.global and event.userId ~= player.UserId then
			local main = table.clone(event.main or event)
			main.kind, main.name, main.instanceId =
				"Bank", main.name or main.displayName, main.instanceId or main.individualId
			enqueue(main)
		end
		return
	end
	if event.kind == "Bank" then
		bank(event)
		if event.global and event.userId ~= player.UserId then
			enqueue(event)
		end
		return
	end
	if event.kind == "Load" then
		if event.userId == player.UserId then
			audio("SFX_LoadAccent", "transient", nil)
			Hud.LoadCommitted(
				require(script.Parent.Parent.State.LocalCartState).GetCart(),
				event.individualId,
				event.eventId
			)
		end
		return
	end
	if event.kind == "Escape" then
		if
			event.userId == player.UserId
			and typeof(event.landingPosition or event.position) == "Vector3"
		then
			landingCue = {
				position = event.landingPosition or event.position,
				expiresAt = now() + Config.Presentation.EscapeCueSeconds,
			}
		end
		return
	end
	if event.kind == "ResetRetire" then
		resetRetirement(event)
		return
	end
	if event.kind == "Reset" then
		finishRebirth("Reset")
		resetRetirement(event)
		beginSky(event, 3, true)
		for _, entry in models do
			stopShake(entry)
			entry.signature = nil
		end
		for _, instance in CollectionService:GetTagged("Phase12Burrow") do
			local position = if instance:IsA("BasePart")
				then instance.Position
				elseif instance:IsA("Model") then instance:GetPivot().Position
				else nil
			if position and Visibility.IsVisible(instance) then
				burst(position, Color3.fromHex("47D8FF"), 5, 4, 1, event.qaPreview)
			end
		end
		return
	end
	if event.kind == "ResetWarning" then
		return
	end -- synchronized workspace deadline owns stages
	if event.kind == "Catch" then
		if event.global or event.userId == player.UserId then
			enqueue(event)
		end
		if event.userId == player.UserId then
			audio("SFX_CaptureComplete", "transient", nil)
		end
		return
	end
	if event.kind == "Spawn" then
		local camera = Workspace.CurrentCamera
		local nearby = typeof(event.position) == "Vector3"
			and camera ~= nil
			and (event.position - camera.CFrame.Position).Magnitude <= 100
		if not event.global and not nearby then
			return
		end
		synchronizeSpawnCycle(observedCycle)
		event.receiptCycle = event.cycleId or observedCycle
		table.insert(spawnBurst, event)
		if #spawnBurst > 64 then
			table.sort(spawnBurst, stronger)
			table.remove(spawnBurst)
		end
		queueSpawnFlush()
	end
end
local function updateClock(t: number)
	if CoreLoopRushMode then
		if clockLabel then
			clockLabel.Visible = false
		end
		return
	end
	local deadline = Workspace:GetAttribute("Phase12ResetDeadline")
	local cycle = Workspace:GetAttribute("Phase12CycleId")
	synchronizeSpawnCycle(cycle)
	if cycle ~= lastCycle then
		lastCycle = cycle
		resetPhase = 0
		landingCue = nil
	end
	if not finite(deadline) then
		if clockLabel then
			clockLabel.Text = "WORLD RESET · SYNCING"
		end
		return
	end
	local remaining = math.max(0, deadline - t)
	if clockLabel then
		clockLabel.Text = string.format(
			if lastLayoutSize.X < 600 then "RESET %d:%02d" else "WORLD RESET %d:%02d",
			math.floor(remaining / 60),
			math.floor(remaining % 60)
		)
	end

	local phase = if remaining <= Config.ResetCriticalSeconds
		then 3
		elseif remaining <= Config.ResetBuildSeconds then 2
		elseif remaining <= Config.ResetWarningSeconds then 1
		else 0
	if phase > resetPhase and remaining > 0 then
		resetPhase = phase
		beginSky({
			rarity = "Epic",
			mutationId = "Normal",
			seed = cycle or 1,
			startTime = deadline - Config.ResetWarningSeconds,
			resetStage = phase,
			resetDeadline = deadline,
		}, remaining + 0.15, true)
	end
	if remaining > Config.ResetWarningSeconds and sky and sky.reset and sky.untilTime > t + 3.2 then
		clearSky()
	end
end
local function frame(dt: number, elapsed: number)
	local t = now()
	stepPhase13(t)
	updateLayout()
	updateClock(t)
	pumpScheduled(t)
	updateModels(t, elapsed % 0.5 < dt)
	Appearance.Step(t, reducedMotion())
	if sky then
		if t >= sky.untilTime then
			clearSky()
		else
			if
				sky.reset
				and not sky.impact
				and finite(sky.resetDeadline)
				and t >= sky.resetDeadline
			then
				if rifts and sky.riftHandle then
					rifts.Collapse(sky.riftHandle, sky.resetDeadline, 3)
				end
				sky.impact, sky.startedAt, sky.untilTime =
					true, sky.resetDeadline, sky.resetDeadline + 3
			end
			-- Reconcile optional pooled images in place; the primary and absolute timeline survive.
			sky.quality = quality()
			local offset = Vector3.zero
			if sky.cameraFollowing and Workspace.CurrentCamera then
				local camera = Workspace.CurrentCamera
				offset = camera.CFrame.Position
					+ camera.CFrame.LookVector * 120
					+ Vector3.new(0, 40, 0)
					- sky.centre
			end
			if rifts then
				rifts.Step(t, offset, sky.quality, reducedMotion())
			end
			stepMeteors(t, offset)
		end
	end

	for index = #activeParticles, 1, -1 do
		local item = activeParticles[index]
		if t >= item.untilTime then
			particleCount = math.max(0, particleCount - item.count)
			returnAnchor(item.part)
			table.remove(activeParticles, index)
		end
	end
	for index = #voices, 1, -1 do
		local voice = voices[index]
		if t >= voice.untilTime or (voice.sound.IsLoaded and not voice.sound.IsPlaying) then
			voice.sound:Destroy()
			if voice.anchor then
				returnAnchor(voice.anchor)
			end
			table.remove(voices, index)
		end
	end
	if #voices == 0 and next(ducked) then
		restoreDucking()
	end
	for index = #celebrations, 1, -1 do
		if t >= celebrations[index].untilTime then
			table.remove(celebrations, index)
		end
	end
	if cueLabel then
		cueLabel.Visible = landingCue ~= nil and t < landingCue.expiresAt
		if cueLabel.Visible and Workspace.CurrentCamera then
			local camera = Workspace.CurrentCamera
			local origin = camera.CFrame.Position
			local delta = landingCue.position - origin
			local params = RaycastParams.new()
			params.FilterType, params.FilterDescendantsInstances =
				Enum.RaycastFilterType.Exclude,
				{ player.Character :: Model, visualFolder :: Folder }
			local obstruction = Workspace:Raycast(origin, delta, params)
			if obstruction and obstruction.Distance < delta.Magnitude - 1 then
				cueLabel.Visible = false
			else
				local relative = camera.CFrame:VectorToObjectSpace(delta)
				cueLabel.Text = (
					if relative.X < -2 then "←" elseif relative.X > 2 then "→" else "↓"
				) .. " LAST-KNOWN LANDING"
			end
		end
		if landingCue and t >= landingCue.expiresAt then
			landingCue = nil
		end
	end
end
function Controller.Start(): boolean
	if started or not Config.Enabled then
		return false
	end
	started = true
	generation += 1
	local startupGeneration = generation
	resetPhase, lastCycle = 0, nil
	spawnCycleSynchronized, spawnReceiptCycle = false, nil
	ApprovedEnvironment.ApplyBaseline()

	local playerGui = player:WaitForChild("PlayerGui", 15)
	if not started or generation ~= startupGeneration then
		return false
	end
	if not playerGui or not playerGui:IsA("PlayerGui") then
		Controller.Stop()
		return false
	end
	visualFolder = Instance.new("Folder")
	visualFolder.Name, visualFolder.Parent = "Phase12ClientEffects", Workspace
	adaptive = AdaptiveVFXPolicy.new()
	lastPublishedDetailTier = adaptive.GetTier()
	detailQualityOwner = ResolvedQuality.Begin(lastPublishedDetailTier)
	ApprovedEnvironment.SetReducedEffects(lastPublishedDetailTier == "Low" or reducedMotion())
	focusKnown = nil
	measurements = { lastRead = -math.huge, errors = {} }
	createUI(playerGui)
	rifts = SpaceRiftRenderer.Create(visualFolder, SpaceRift)
	warmPrimary()
	table.insert(
		connections,
		UserInputService.WindowFocused:Connect(function()
			focusKnown = true
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			focusKnown = false
		end)
	)
	-- Render pacing is measured here; the existing PreSimulation coordinator still
	-- owns all presentation timelines and pre-physics motor cleanup.
	table.insert(connections, RunService.RenderStepped:Connect(renderSample))
	for _, model in CollectionService:GetTagged(DisplayConfig.CollectionTag) do
		register(model)
	end
	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal(DisplayConfig.CollectionTag):Connect(register)
	)
	for _, model in CollectionService:GetTagged("FrontTeamCosmetic") do
		register(model)
	end
	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal("FrontTeamCosmetic"):Connect(register)
	)

	table.insert(
		connections,
		CollectionService:GetInstanceRemovedSignal(DisplayConfig.CollectionTag)
			:Connect(function(instance)
				if instance:IsA("Model") then
					unregister(instance)
				end
			end)
	)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not started or generation ~= startupGeneration then
		return false
	end
	local remote = if remotes then remotes:WaitForChild(RemoteNames.Phase12Event, 15) else nil
	if not started or generation ~= startupGeneration then
		return false
	end
	if remote and remote:IsA("RemoteEvent") then
		table.insert(connections, remote.OnClientEvent:Connect(received))
	else
		warn("[Phase12] Presentation event remote unavailable")
	end
	local elapsed = 0
	table.insert(
		connections,
		RunService.PreSimulation:Connect(function(dt)
			elapsed += dt
			frame(dt, elapsed)
		end)
	)
	return true
end
function Controller.Stop()
	rebirthPreparations:Cancel()
	if not started then
		return
	end
	finishRebirth("Stopped")
	cameraRestores:Cancel()
	cameraRestoreLastStatus = "Stopped"
	for image, entry in riftPreviews do
		image:Destroy()
		entry.label:Destroy()
	end
	table.clear(riftPreviews)
	for _, entry in resetSubstitutes do
		entry.part:Destroy()
	end
	for _, part in resetSubstitutePool do
		part:Destroy()
	end
	table.clear(resetSubstitutes)
	table.clear(resetSubstitutePool)
	table.clear(resetSubstituteSeen)
	table.clear(rebirthSeen)
	resetSubstituteGeneration = nil
	resetSubstituteCount = 0
	started = false
	if detailQualityOwner then
		ResolvedQuality.Release(detailQualityOwner)
		detailQualityOwner, lastPublishedDetailTier = nil, nil
	end
	generation += 1
	previewGeneration += 1
	haulGeneration += 1
	if haulListConnection then
		haulListConnection:Disconnect()
		haulListConnection = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local retiring = {}
	for model in models do
		table.insert(retiring, model)
	end
	for _, model in retiring do
		unregister(model)
	end
	clearSky()
	if rifts then
		rifts.Destroy()
		rifts = nil
	end
	for _, meteor in meteorPool do
		meteor.gui:Destroy()
		meteor.anchor:Destroy()
	end
	table.clear(meteorPool)
	restoreDucking()
	for _, voice in voices do
		voice.sound:Destroy()
	end
	table.clear(voices)
	for _, anchor in anchorPool do
		anchor:Destroy()
	end
	table.clear(anchorPool)
	if visualFolder then
		visualFolder:Destroy()
		visualFolder = nil
	end
	if criticalGui then
		criticalGui:Destroy()
		criticalGui = nil
	end
	lastLayoutSize = Vector2.zero
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(activeParticles)
	table.clear(scheduledJobs)
	announceScheduled, spawnFlushScheduled = false, false
	table.clear(celebrations)
	table.clear(queue)
	table.clear(spawnBurst)
	table.clear(pendingBanks)
	table.clear(seen)
	table.clear(seenOrder)
	particleCount, current, outgoing, landingCue = 0, nil, nil, nil
end
-- Local-only fixture seam. It cannot send remotes or mutate profiles/gameplay.
-- Explicitly labelled, chat-silent and restricted to this Development Studio place.
function Controller._PreviewForTesting(snapshot: any)
	if
		not started
		or not RunService:IsStudio()
		or game.PlaceId ~= 91958083796436
		or not Config.Enabled
	then
		return false, "DEVELOPMENT_STUDIO_ONLY"
	end
	if type(snapshot) ~= "table" then
		return false, "INVALID_FIXTURE"
	end
	local definition = Catalog.Get(snapshot.speciesId)
	local mutation = Rules.NormalizeMutation(snapshot.mutationId)
	if not definition or not mutation then
		return false, "REAL_CATALOGUE_REFERENCE_REQUIRED"
	end
	local values = Rules.EffectiveValues(definition.id, mutation)
	previewSerial += 1
	local event = table.clone(snapshot)
	event.eventId = "qa-preview:" .. tostring(previewSerial)
	event.kind = if snapshot.kind == "Bank"
		then "Bank"
		elseif snapshot.kind == "Catch" then "Catch"
		elseif snapshot.kind == "Reset" then "Reset"
		else "Spawn"
	event.instanceId = event.eventId
	event.speciesId, event.name, event.displayName, event.rarity =
		definition.id, definition.displayName, definition.displayName, definition.tier
	event.mutationId, event.cashPerSecond, event.sellValue =
		mutation, values.cashPerSecond, values.sellValue
	event.startTime, event.at, event.seed = now(), now(), previewSerial
	event.userId, event.username = player.UserId, player.Name
	event.qaPreview, event.suppressChat, event.global, event.identified =
		true, true, true, snapshot.identified == true
	event.location = "QA PREVIEW · "
		.. cleanText(snapshot.location or "LOCAL PRESENTATION FIXTURE")
	event.position = if typeof(snapshot.position) == "Vector3"
		then snapshot.position
		else (if Workspace.CurrentCamera
			then Workspace.CurrentCamera.CFrame.Position
				+ Workspace.CurrentCamera.CFrame.LookVector * 120
				- Vector3.new(0, 30, 0)
			else Vector3.zero)
	if event.kind == "Reset" and sky and sky.reset and not sky.qaPreview then
		return false, "CRITICAL_RESET_HAS_PRIORITY"
	end
	if event.kind == "Bank" then
		event.firstBank, event.batchReady = true, true
		event.platformPosition, event.baseSignPosition = event.position, event.position
		event.discovery, event.recordImproved, event.progress = nil, false, nil
		event.records = { table.clone(event) }
		event.main = event.records[1]
	end
	received(event)
	return true, event.eventId
end
function Controller._ClearPreviewForTesting()
	if not RunService:IsStudio() or game.PlaceId ~= 91958083796436 or not Config.Enabled then
		return false
	end
	previewGeneration += 1
	if current and current.event.qaPreview then
		current.frame:Destroy()
		current = nil
	end
	if outgoing and outgoing.event.qaPreview then
		outgoing.frame:Destroy()
		outgoing = nil
	end
	for index = #queue, 1, -1 do
		if queue[index].qaPreview then
			table.remove(queue, index)
		end
	end
	for index = #spawnBurst, 1, -1 do
		if spawnBurst[index].qaPreview then
			table.remove(spawnBurst, index)
		end
	end
	if sky and sky.qaPreview then
		clearSky()
	end
	for index = #celebrations, 1, -1 do
		if celebrations[index].qaPreview then
			celebrations[index].untilTime = 0
			table.remove(celebrations, index)
		end
	end
	for index = #activeParticles, 1, -1 do
		local effect = activeParticles[index]
		if effect.qaPreview then
			particleCount = math.max(0, particleCount - effect.count)
			returnAnchor(effect.part)
			table.remove(activeParticles, index)
		end
	end
	for index = #voices, 1, -1 do
		local voice = voices[index]
		if voice.qaPreview then
			voice.sound:Destroy()
			if voice.anchor then
				returnAnchor(voice.anchor)
			end
			table.remove(voices, index)
		end
	end
	if #voices == 0 then
		restoreDucking()
	end
	if haulIsPreview and haulLabel then
		haulGeneration += 1
		if haulListConnection then
			haulListConnection:Disconnect()
			haulListConnection = nil
		end
		haulLabel.Visible = false
		haulIsPreview = false
	end
	updateClock(now())
	return true
end
function Controller.GetDiagnostics()
	return {
		running = started,
		queuedHeadlines = #queue,
		scheduledCosmeticJobs = #scheduledJobs,
		seenEvents = #seenOrder,
		liveParticles = particleCount,
		particleCap = cap(),
		voices = #voices,
		celebrations = #celebrations,
		sky = sky ~= nil,
		pooledAnchors = #anchorPool,
		pendingWarningCleanups = #pendingShakeCleanups,
		pendingCameraRestores = if cameraRestores:Pending() then 1 else 0,
		cameraRestoreLastStatus = cameraRestoreLastStatus,
		connections = #connections,
		appearance = Appearance.GetDiagnostics(),
		approvedEnvironment = ApprovedEnvironment.GetDiagnostics(),
		adaptiveVFX = adaptive.GetDiagnostics(),
		resolvedPresentationQuality = ResolvedQuality.GetDiagnostics(
			if player then player:GetAttribute("VFXQuality") else nil
		),
		rifts = if rifts then rifts.GetDiagnostics() else nil,
		primaryPreload = table.clone(primaryPreload),
		riftReadiness = Controller.GetRiftReadiness(),
		activeRiftPreviews = (function()
			local n = 0
			for _ in riftPreviews do
				n += 1
			end
			return n
		end)(),
		measurementErrors = table.clone(measurements.errors),
		focusKnown = focusKnown,
		missingAudio = table.clone(audioMissing),
	}
end
return Controller
