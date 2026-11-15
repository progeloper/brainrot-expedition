--!strict
-- Playtest Fixes 2, Part G (LegsTrainingV1Enabled): Legs treadmill presentation. The server owns
-- presence, XP, levels, WalkSpeed and trails (LegsTrainingService); this only draws:
--   * the run in place: every character the server marks LegsRunning plays its OWN Animate "run"
--     animation locally (no humanoid movement, no new asset, nothing replicated): the cheapest look;
--   * the belt: its slats scroll (engine tweens on the shared ≤ 10 Hz scheduler, culled at 120 studs);
--   * Training's "+XP" pops and level-up burst over the belt, the level toast ("+1 LEGS LV") + chime,
--     a "NEW TRAIL!" toast, and the console dial needle following the Legs level;
--   * Low quality halves every visible LegsTrail Lifetime (per viewer).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Legs = require(ReplicatedStorage.Shared.Config.LegsTraining)
local LegsFlags = require(ReplicatedStorage.Shared.Config.LegsTrainingFlags)
local Quality = require(ReplicatedStorage.Shared.Utility.ResolvedPresentationQuality)
local Scheduler = require(script.Parent.Parent.Utility.CampAnimationScheduler)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)

local player = Players.LocalPlayer
local Controller = {}
local started = false

local tracks: { [Model]: AnimationTrack } = {}
local belt: BasePart? = nil
local slats: { { part: BasePart, base: CFrame, z: number } } = {}
local needle: BasePart? = nil
local needleBase: CFrame? = nil
local anyRunning = 0

local function camp(): any
	return require(script.Parent.CampStallController)
end

local function lowQuality(): boolean
	return Quality.GetTier(player:GetAttribute("VFXQuality")) == "Low"
end

-- Pure: the console dial angle (degrees) for a Legs level: -110 at 0 -> +110 at max.
function Controller.DialDegrees(level: number): number
	local l = math.clamp(level, 0, Legs.MaxLevel)
	return -110 + 220 * l / Legs.MaxLevel
end

local function runAnimationId(character: Model): string?
	local animate = character:FindFirstChild("Animate")
	local run = animate and animate:FindFirstChild("run")
	local anim = run and run:FindFirstChildOfClass("Animation")
	return if anim and anim.AnimationId ~= "" then anim.AnimationId else nil
end

local function setRunning(character: Model?, running: boolean)
	if not character then
		return
	end
	local track = tracks[character]
	if running then
		if not track then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
			local id = runAnimationId(character)
			if not animator or not id then
				return
			end
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local ok, loaded = pcall(function()
				return (animator :: Animator):LoadAnimation(animation)
			end)
			if not ok or not loaded then
				return
			end
			loaded.Looped = true
			loaded.Priority = Enum.AnimationPriority.Movement
			tracks[character] = loaded
			character.Destroying:Once(function()
				tracks[character] = nil
			end)
			track = loaded
		end
		if track and not track.IsPlaying then
			track:Play(0.2, 1, 1.25)
		end
	elseif track and track.IsPlaying then
		track:Stop(0.2)
	end
end

local function halveTrail(trail: Instance)
	if trail:IsA("Trail") and trail.Name == "LegsTrail" and lowQuality() then
		trail.Lifetime = Legs.TrailLifetime * Legs.TrailLowLifetimeScale
	end
end

local function bindCharacter(other: Player, character: Model)
	setRunning(character, other:GetAttribute("LegsRunning") == true)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		for _, d in root:GetChildren() do
			halveTrail(d)
		end
		root.ChildAdded:Connect(halveTrail)
	end
end

local function bindPlayer(other: Player)
	other:GetAttributeChangedSignal("LegsRunning"):Connect(function()
		local running = other:GetAttribute("LegsRunning") == true
		anyRunning += if running then 1 else -1
		anyRunning = math.max(0, anyRunning)
		setRunning(other.Character, running)
	end)
	if other:GetAttribute("LegsRunning") == true then
		anyRunning += 1
	end
	if other.Character then
		task.spawn(bindCharacter, other, other.Character)
	end
	other.CharacterAdded:Connect(function(character)
		bindCharacter(other, character)
	end)
end

local function applyDial()
	if not needle or not needleBase then
		return
	end
	local level = tonumber(player:GetAttribute("LegsLevel")) or 0
	local target = (needleBase :: CFrame)
		* CFrame.Angles(0, 0, math.rad(-Controller.DialDegrees(level) - 35))
	TweenService:Create(needle, TweenInfo.new(0.6, Enum.EasingStyle.Back), { CFrame = target })
		:Play()
end

local function bindTreadmill(model: Model)
	local b = model:FindFirstChild("Belt")
	if not b or not b:IsA("BasePart") then
		return
	end
	belt = b
	table.clear(slats)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name:match("^Slat%d") then
			table.insert(slats, { part = d, base = d.CFrame, z = 0 })
		end
	end
	local n = model:FindFirstChild("DialNeedle")
	if n and n:IsA("BasePart") then
		needle = n
		-- the authored needle points at -35°: measure from there
		needleBase = n.CFrame * CFrame.Angles(0, 0, math.rad(35))
		applyDial()
	end
	-- belt scroll: each slat moves one pitch along the belt per tick, wrapping (10 Hz scheduler)
	local length = b.Size.Z
	local pitch = length / (#slats + 1)
	local offset = 0
	Scheduler.Register(model, {
		position = function()
			return if b.Parent then b.Position else nil
		end,
		radius = 120,
		always = false,
		step = function(_now, dt)
			if anyRunning <= 0 then
				return
			end
			offset = (offset + dt * 6) % pitch -- 6 studs/s belt speed
			for i, slat in slats do
				local z = ((i * pitch + offset) % length) - length / 2
				local rel = b.CFrame:ToObjectSpace(slat.base)
				local cf = b.CFrame * CFrame.new(rel.X, rel.Y, z)
				if z < slat.z then
					slat.part.CFrame = cf -- wrapped to the far end: jump, never tween backwards
				else
					TweenService
						:Create(
							slat.part,
							TweenInfo.new(0.1, Enum.EasingStyle.Linear),
							{ CFrame = cf }
						)
						:Play()
				end
				slat.z = z
			end
		end,
	})
end

local function toast(text: string)
	local ok, StudPop = pcall(require, ReplicatedStorage.Shared.UI.StudPop)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local screen = gui and gui:FindFirstChild("CampTrainingToast")
	if ok and screen and screen:IsA("ScreenGui") then
		StudPop.Toast(screen, text, "gem")
	end
end

function Controller.Start()
	if started or not LegsFlags.Enabled() then
		return
	end
	started = true
	local map = Workspace:WaitForChild("MapBlockout", 30)
	local art = map and map:WaitForChild("MapArt", 30)
	local folder = art and art:WaitForChild("Services", 30)
	if folder then
		local function consider(child: Instance)
			if child.Name == Legs.ModelName and child:IsA("Model") then
				bindTreadmill(child)
			end
		end
		for _, child in folder:GetChildren() do
			consider(child)
		end
		folder.ChildAdded:Connect(consider) -- StreamingEnabled: the treadmill may stream in later
	end
	for _, other in Players:GetPlayers() do
		bindPlayer(other)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	-- "+XP" pops while the local player runs (Training's pool and look)
	local lastXp = tonumber(player:GetAttribute("LegsXP")) or 0
	player:GetAttributeChangedSignal("LegsXP"):Connect(function()
		local xp = tonumber(player:GetAttribute("LegsXP")) or 0
		local gain = tonumber(player:GetAttribute("LegsXpGain")) or (xp - lastXp)
		lastXp = xp
		if belt and player:GetAttribute("LegsRunning") == true and gain > 0 then
			pcall(function()
				camp().PopXp(belt, gain)
			end)
		end
	end)
	player:GetAttributeChangedSignal("LegsLevel"):Connect(applyDial)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local event = remotes and remotes:WaitForChild("CampReworkEvent", 30)
	if event and event:IsA("RemoteEvent") then
		event.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" or payload.kind ~= "LegsLevelUp" then
				return
			end
			pcall(function()
				camp().ShowLevelToast(tonumber(payload.gained) or 1, "LEGS LV")
				if belt then
					camp().LevelBurst(belt)
				end
			end)
			if type(payload.unlocked) == "table" and #payload.unlocked > 0 then
				task.delay(1.2, function()
					toast("NEW TRAIL!")
					AudioCue.Play("U8", { bus = "UI", cooldown = 1 })
				end)
			end
		end)
	end
end

return Controller
