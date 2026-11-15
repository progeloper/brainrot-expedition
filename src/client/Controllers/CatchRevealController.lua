--!strict
-- Catch reveal card + coloured burst on the local player's server-confirmed sleep.
-- Presentation only: it observes the existing SleepRequest result and reads the
-- catalogue, mutation catalogue and region tier weights. It never fires a remote.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.FirstSessionVisuals)
local Rules = require(ReplicatedStorage.Shared.Utility.FirstSessionVisualRules)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local MutationCatalog = require(ReplicatedStorage.Shared.Config.MutationCatalog)
local AppearanceCatalog = require(ReplicatedStorage.Shared.Config.BrainrotAppearanceCatalog)
local DisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local Palette = require(ReplicatedStorage.Shared.Config.VoxelCreaturePalette)
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local RemoteBinding = require(script.Parent.Parent.Utility.RemoteDependencyBinding)

local R = Config.Reveal
local Controller = {}
local player = Players.LocalPlayer
local started = false

local function rarityColour(tier: string): Color3
	local appearance = AppearanceCatalog.Rarities[tier]
	if appearance and appearance.primary then
		return appearance.primary
	end
	return DisplayConfig.Colors.Rank[string.lower(tier)] or Color3.new(1, 1, 1)
end

local function mutationColour(id: string): Color3?
	local hex = Palette.MutationTag[id]
	return if type(hex) == "string" then Color3.fromHex(hex) else nil
end

local function findModels(itemId: string): (Model?, BasePart?)
	local runtime = Workspace:FindFirstChild("Runtime")
	local folder = runtime and runtime:FindFirstChild("Brainrots")
	local model: Model? = nil
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("ItemId") == itemId then
				model = child
				break
			end
		end
	end
	-- The visible proxy (when present) gives the true on-screen body position.
	local visuals = Workspace:FindFirstChild("Phase13CreatureVisuals")
	local proxy = visuals and visuals:FindFirstChild("Creature_" .. itemId)
	local body = (proxy and proxy:FindFirstChild("Body", true))
		or (model and model:FindFirstChild("Body", true))
	return model, if body and body:IsA("BasePart") then body else nil
end

export type RevealData = {
	SpeciesId: string?,
	Name: string,
	Tier: string,
	TierOdds: string?,
	RegionName: string?,
	MutationId: string,
	MutationName: string?,
	MutationOdds: string?,
	Income: number?,
}

-- Species id for an item (pure lookup; AudioController uses it for hit yelps).
function Controller.SpeciesOf(itemId: string): string?
	local model = findModels(itemId)
	local species = model and model:GetAttribute(DisplayConfig.Attributes.BrainrotId)
	return if type(species) == "string" then species else nil
end

function Controller.BuildData(model: Model, regionId: string?): RevealData?
	local definition = BrainrotCatalog.Get(model:GetAttribute(DisplayConfig.Attributes.BrainrotId))
	if not definition then
		return nil
	end
	local mutationId = Phase12Rules.NormalizeMutation(
		model:GetAttribute("MutationId") or model:GetAttribute(DisplayConfig.Attributes.MutationId)
	) or "None"
	local region = regionId and Regions.Get(regionId)
	local weights = region
		and (region.tierWeights or (region.spawnSelection and region.spawnSelection.tierWeights))
	local mutation = MutationCatalog.ById[mutationId]
	return {
		SpeciesId = definition.id,
		Name = definition.displayName,
		Tier = definition.tier,
		TierOdds = Rules.FormatOdds(Rules.TierProbability(weights, definition.tier)),
		RegionName = region and region.displayName or nil,
		MutationId = mutationId,
		MutationName = if mutationId ~= "None" and mutation then mutation.displayName else nil,
		MutationOdds = Rules.FormatOdds(Rules.MutationProbability(mutationId)),
		Income = Rules.EffectiveIncome(definition.cashPerSecond, mutationId),
	}
end

-- The card itself is the Plate view (UI/Screens/CatchRevealScreen): same data, same timing; this
-- controller still owns the burst and the remote. holdSeconds is an optional review override
-- (screen captures); gameplay omits it.
function Controller.ShowCard(data: RevealData, holdSeconds: number?)
	local view = table.clone(data) :: any
	view.MutationColour = mutationColour(data.MutationId)
	view.IncomeText = if data.Income then CurrencyFormatter.FormatCompactCash(data.Income) else nil
	local Screen = require(script.Parent.Parent.UI.Screens.CatchRevealScreen) :: any
	Screen.Show(view, holdSeconds or R.HoldSeconds, R.InSeconds, R.OutSeconds)
end

function Controller.Burst(position: Vector3, colour: Color3)
	local reduced = player:GetAttribute("ReducedMotion") == true
	local anchor = Instance.new("Part")
	anchor.Name = "CatchRevealBurst"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Lifetime = NumberRange.new(R.BurstLifetime * 0.6, R.BurstLifetime)
	emitter.Speed = NumberRange.new(R.BurstSpeed * 0.5, R.BurstSpeed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Color = ColorSequence.new(colour)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, R.BurstSize),
		NumberSequenceKeypoint.new(0.35, R.BurstSize * 1.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.75, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Drag = 3
	emitter.Acceleration = Vector3.new(0, -10, 0)
	emitter.Parent = anchor
	emitter:Emit(if reduced then R.ReducedBurstCount else R.BurstCount)
	task.delay(R.BurstLifetime + 0.5, function()
		anchor:Destroy()
	end)
end

local function onSleepResult(_origin: any, _endpoint: any, result: any)
	if type(result) ~= "table" or result.PlayerId ~= player.UserId or result.Slept ~= true then
		return
	end
	local itemId = result.ItemId
	if type(itemId) ~= "string" then
		return
	end
	local model, body = findModels(itemId)
	if not model then
		return
	end
	local data = Controller.BuildData(model, player:GetAttribute("Phase13RegionId"))
	if not data then
		return
	end
	Controller.ShowCard(data)
	-- Game audio (presentation only): tier jingle + mutation layer + region twist. No-op when the
	-- audio engine is absent or not started (FeatureFlags.GameAudioEnabled = false).
	local audioModule = script.Parent:FindFirstChild("AudioController")
	if audioModule then
		local ok, Audio = pcall(require, audioModule)
		if ok and type(Audio) == "table" and type(Audio.CatchReveal) == "function" then
			Audio.CatchReveal(data.Tier, data.MutationId, data.SpeciesId)
		end
	end
	if body then
		Controller.Burst(body.Position, mutationColour(data.MutationId) or rarityColour(data.Tier))
	end
end

function Controller.Start(): boolean
	if started then
		return false
	end
	started = true
	-- Held for the session; the binding re-attaches if the remote is replaced.
	Controller.Binding = RemoteBinding.new({
		Root = ReplicatedStorage,
		Name = "SleepRequest",
		OnRemote = function(remote)
			return if remote then remote.OnClientEvent:Connect(onSleepResult) else nil
		end,
	})
	return true
end

return Controller
