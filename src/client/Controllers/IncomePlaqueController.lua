--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)

local PLAQUE_TAG = "BrainrotIncomePlaque"
local ACTIVE_RANGE_STUDS = 80
local ACTIVE_RANGE_SQUARED = ACTIVE_RANGE_STUDS * ACTIVE_RANGE_STUDS
local ACTIVE_REFRESH_SECONDS = 1
local TEXT_UPDATE_SECONDS = 0.25
local CLAIM_REVISION_ATTRIBUTE = "ClaimRevision"
local CLAIM_COLOR = Color3.fromRGB(255, 241, 118)
local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)
local SNAPSHOT_ATTRIBUTES = {
	"UnclaimedCashSnapshot",
	"IncomeRatePerSecond",
	"IncomeSnapshotServerTime",
	"IncomeOccupied",
	"IncomeRevision",
	"IncomeSnapshotReady",
}

type Snapshot = {
	UnclaimedCash: number,
	RatePerSecond: number,
	ServerTime: number,
	Occupied: boolean,
	Revision: number,
	Ready: boolean,
}

type Entry = {
	Plaque: BasePart,
	Label: TextLabel?,
	Snapshot: Snapshot,
	PendingSnapshot: Snapshot?,
	Active: boolean,
	ClaimAnimating: boolean,
	ClaimGeneration: number,
	LastClaimRevision: number,
	Connections: { any },
}

type Dependencies = {
	CollectionService: any,
	Clock: () -> number,
	GetViewerPosition: () -> Vector3?,
	Spawn: (() -> ()) -> (),
	Wait: (number) -> (),
	DisableLoop: boolean,
}

local IncomePlaqueController = {}
local started = false
local generation = 0
local configuredDependencies: any? = nil
local dependencies: Dependencies? = nil
local entries: { [BasePart]: Entry } = {}
local controllerConnections: { any } = {}

local function finiteNonNegative(value: any): number
	if
		type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
		and value >= 0
	then
		return value
	end
	return 0
end

local function defaultViewerPosition(): Vector3?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function buildDependencies(overrides: any?): Dependencies
	local supplied = overrides or {}
	return {
		CollectionService = supplied.CollectionService or CollectionService,
		Clock = supplied.Clock or function()
			return Workspace:GetServerTimeNow()
		end,
		GetViewerPosition = supplied.GetViewerPosition or defaultViewerPosition,
		Spawn = supplied.Spawn or task.spawn,
		Wait = supplied.Wait or task.wait,
		DisableLoop = supplied.DisableLoop == true,
	}
end

local function disconnectAll(connections: { any })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function findLabel(plaque: BasePart): TextLabel?
	local surface = plaque:FindFirstChild("AmountSurfaceGui")
	if not surface or not surface:IsA("SurfaceGui") then
		return nil
	end
	local label = surface:FindFirstChild("AmountLabel")
	return if label and label:IsA("TextLabel") then label else nil
end

local function readSnapshot(plaque: BasePart): Snapshot
	return {
		UnclaimedCash = finiteNonNegative(plaque:GetAttribute("UnclaimedCashSnapshot")),
		RatePerSecond = finiteNonNegative(plaque:GetAttribute("IncomeRatePerSecond")),
		ServerTime = finiteNonNegative(plaque:GetAttribute("IncomeSnapshotServerTime")),
		Occupied = plaque:GetAttribute("IncomeOccupied") == true,
		Revision = math.floor(finiteNonNegative(plaque:GetAttribute("IncomeRevision"))),
		Ready = plaque:GetAttribute("IncomeSnapshotReady") == true,
	}
end

local function authoritativeWholeCash(snapshot: Snapshot): number
	return math.max(0, math.floor(snapshot.UnclaimedCash))
end

local function renderEntry(entry: Entry, _now: number)
	local label = entry.Label
	if not label or label.Parent == nil then
		label = findLabel(entry.Plaque)
		entry.Label = label
	end
	if not label then
		return
	end
	local surface = label.Parent
	if not surface or not surface:IsA("SurfaceGui") then
		return
	end
	local showAmount = entry.Snapshot.Ready and entry.Snapshot.Occupied
	local formatted = if showAmount
		then CurrencyFormatter.FormatCompactCash(authoritativeWholeCash(entry.Snapshot))
		else ""
	if label.Text ~= formatted then
		label.Text = formatted
	end
	if surface.Enabled ~= showAmount then
		surface.Enabled = showAmount
	end
end

local claimNote = 0
local function playClaimFeedback(entry: Entry)
	local revision =
		math.floor(finiteNonNegative(entry.Plaque:GetAttribute(CLAIM_REVISION_ATTRIBUTE)))
	if revision <= entry.LastClaimRevision then
		return
	end
	entry.LastClaimRevision = revision
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil or entry.Plaque:GetAttribute("LastClaimUserId") ~= localPlayer.UserId then
		return
	end
	-- Playtest Fixes 2 C3: with CashPads on, the coin ticks play as the coins land instead.
	if
		finiteNonNegative(entry.Plaque:GetAttribute("LastClaimAmount")) > 0
		and not require(game:GetService("ReplicatedStorage").Shared.Config.PlaytestFixes2Flags).Part(
			"CashPads"
		)
	then
		-- three coin notes in turn, so collecting along a row of plaques plays a little run
		claimNote = claimNote % 3 + 1
		require(script.Parent.Parent.Utility.AudioCue).Play("E1_" .. claimNote, { bus = "UI", cooldown = 0.08 })
	end

	local label = entry.Label
	if not label or label.Parent == nil then
		label = findLabel(entry.Plaque)
		entry.Label = label
	end
	if not label then
		return
	end
	local surface = label.Parent
	if not surface or not surface:IsA("SurfaceGui") then
		return
	end
	local activeDependencies = dependencies
	if not activeDependencies then
		return
	end

	local resetAmount = finiteNonNegative(entry.Plaque:GetAttribute("ClaimResetAmount"))
	local showAmount = entry.Snapshot.Ready and (entry.Snapshot.Occupied or resetAmount > 0)
	if not showAmount then
		entry.ClaimGeneration += 1
		entry.ClaimAnimating = false
		surface.Enabled = false
		label.Text = ""
		label.TextColor3 = DEFAULT_COLOR
		return
	end
	entry.ClaimGeneration += 1
	local claimGeneration = entry.ClaimGeneration
	entry.ClaimAnimating = true
	label.TextColor3 = CLAIM_COLOR
	label.Text = CurrencyFormatter.FormatCompactCash(math.floor(resetAmount))
	surface.Enabled = true

	activeDependencies.Spawn(function()
		local colorReturn = TweenService:Create(
			label,
			TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ TextColor3 = DEFAULT_COLOR }
		)
		colorReturn:Play()
		colorReturn.Completed:Wait()
		if entries[entry.Plaque] == entry and entry.ClaimGeneration == claimGeneration then
			entry.ClaimAnimating = false
			label.TextColor3 = DEFAULT_COLOR
			renderEntry(entry, activeDependencies.Clock())
		end
	end)
end

local function unregisterPlaque(plaque: BasePart)
	local entry = entries[plaque]
	if not entry then
		return
	end
	entries[plaque] = nil
	disconnectAll(entry.Connections)
end

local function refreshSnapshot(entry: Entry, attributeName: string)
	if entries[entry.Plaque] ~= entry then
		return
	end

	local nextSnapshot = readSnapshot(entry.Plaque)
	if attributeName == "IncomeRevision" then
		entry.Snapshot = nextSnapshot
		entry.PendingSnapshot = nil
		local activeDependencies = dependencies
		if activeDependencies then
			renderEntry(entry, activeDependencies.Clock())
		end
	else
		-- Attribute replication can arrive one field at a time. Read every field now,
		-- but keep the last complete revision until the authoritative revision signal
		-- commits the complete set.
		entry.PendingSnapshot = nextSnapshot
		if nextSnapshot.Revision ~= entry.Snapshot.Revision then
			entry.Snapshot = nextSnapshot
			entry.PendingSnapshot = nil
			if entry.Active then
				local activeDependencies = dependencies
				if activeDependencies then
					renderEntry(entry, activeDependencies.Clock())
				end
			end
		end
	end
end

local function registerPlaque(instance: Instance)
	if not started or not instance:IsA("BasePart") or entries[instance] then
		return
	end
	local entry: Entry = {
		Plaque = instance,
		Label = findLabel(instance),
		Snapshot = readSnapshot(instance),
		PendingSnapshot = nil,
		Active = false,
		ClaimAnimating = false,
		ClaimGeneration = 0,
		LastClaimRevision = math.floor(
			finiteNonNegative(instance:GetAttribute(CLAIM_REVISION_ATTRIBUTE))
		),
		Connections = {},
	}
	entries[instance] = entry

	for _, attributeName in SNAPSHOT_ATTRIBUTES do
		table.insert(
			entry.Connections,
			instance:GetAttributeChangedSignal(attributeName):Connect(function()
				refreshSnapshot(entry, attributeName)
			end)
		)
	end
	table.insert(
		entry.Connections,
		instance:GetAttributeChangedSignal(CLAIM_REVISION_ATTRIBUTE):Connect(function()
			playClaimFeedback(entry)
		end)
	)
	table.insert(
		entry.Connections,
		instance.Destroying:Connect(function()
			unregisterPlaque(instance)
		end)
	)

	local activeDependencies = dependencies
	if activeDependencies then
		renderEntry(entry, activeDependencies.Clock())
	end
end

local function refreshActiveSet()
	local activeDependencies = dependencies
	if not activeDependencies then
		return
	end
	local viewerPosition = activeDependencies.GetViewerPosition()
	for _, entry in entries do
		local offset = if viewerPosition then entry.Plaque.Position - viewerPosition else nil
		entry.Active = offset ~= nil and offset:Dot(offset) <= ACTIVE_RANGE_SQUARED
	end
end

local function renderActive(now: number)
	for _, entry in entries do
		if entry.Active then
			renderEntry(entry, now)
		end
	end
end

local function runLoop(version: number)
	local activeDependencies = dependencies
	if not activeDependencies then
		return
	end
	local lastActiveRefresh = -math.huge
	while started and generation == version do
		local now = activeDependencies.Clock()
		if now - lastActiveRefresh >= ACTIVE_REFRESH_SECONDS then
			refreshActiveSet()
			lastActiveRefresh = now
		end
		renderActive(now)
		activeDependencies.Wait(TEXT_UPDATE_SECONDS)
	end
end

function IncomePlaqueController.Init(nextDependencies: any?): boolean
	if started then
		return false
	end
	configuredDependencies = nextDependencies
	return true
end

function IncomePlaqueController.Start(): boolean
	if started then
		return false
	end
	started = true
	generation += 1
	dependencies = buildDependencies(configuredDependencies)
	local activeDependencies = dependencies :: Dependencies

	table.insert(
		controllerConnections,
		activeDependencies.CollectionService
			:GetInstanceAddedSignal(PLAQUE_TAG)
			:Connect(registerPlaque)
	)
	table.insert(
		controllerConnections,
		activeDependencies.CollectionService
			:GetInstanceRemovedSignal(PLAQUE_TAG)
			:Connect(function(instance: Instance)
				if instance:IsA("BasePart") then
					unregisterPlaque(instance)
				end
			end)
	)
	for _, instance in activeDependencies.CollectionService:GetTagged(PLAQUE_TAG) do
		registerPlaque(instance)
	end

	refreshActiveSet()
	renderActive(activeDependencies.Clock())
	if not activeDependencies.DisableLoop then
		local version = generation
		activeDependencies.Spawn(function()
			runLoop(version)
		end)
	end
	return true
end

function IncomePlaqueController.Stop()
	if not started then
		return
	end
	started = false
	generation += 1
	disconnectAll(controllerConnections)
	local plaques = {}
	for plaque in entries do
		table.insert(plaques, plaque)
	end
	for _, plaque in plaques do
		unregisterPlaque(plaque)
	end
	dependencies = nil
end

function IncomePlaqueController._TestStep(now: number, rebuildActive: boolean?)
	if rebuildActive then
		refreshActiveSet()
	end
	renderActive(now)
end

function IncomePlaqueController._TestRegistrySize(): number
	local count = 0
	for _ in entries do
		count += 1
	end
	return count
end

function IncomePlaqueController._TestIsActive(plaque: BasePart): boolean
	local entry = entries[plaque]
	return entry ~= nil and entry.Active
end

return IncomePlaqueController
