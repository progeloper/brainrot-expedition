--!strict
-- TerrainRedesign (V5) client detail: traversal toys (bounce pads, slides), session-only POI
-- "DISCOVERED!" banners, per-region atmosphere crossfade and quality-tiered ambient detail.
-- Presentation/movement only; never touches economy, carry or access state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Atmosphere = require(ReplicatedStorage.Shared.Config.RegionAtmosphere)
local Footprints = require(ReplicatedStorage.Shared.Config.RegionFootprints)
local Geometry = require(ReplicatedStorage.Shared.Utility.StormGeometry)
local Rules = require(ReplicatedStorage.Shared.Utility.WorldPresentationRules)

local player = Players.LocalPlayer
local Controller = {}
local started = false
local tier = "Full"
local showBanner: ((string, Color3, number) -> ())? = nil

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local function characterParts(): (BasePart?, Humanoid?)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil, humanoid
end

local function isCarrying(): boolean
	return player:GetAttribute("CarriedItemId") ~= nil
end

local function notice(text: string)
	if showBanner then
		showBanner(text, Color3.new(1, 1, 1), 1.6)
	end
end

local function regionAt(x: number, z: number): string?
	for key, points in Footprints do
		if Geometry.Contains(points, x, z) then
			return key
		end
	end
	return nil
end

---------------------------------------------------------------- toys
local toyParts: { BasePart } = {}
local toyParams = RaycastParams.new()
toyParams.FilterType = Enum.RaycastFilterType.Include
local lastBounce = -math.huge
local lastToyNotice = -math.huge
local activeChute: BasePart? = nil

local function indexToys(world: Instance)
	table.clear(toyParts)
	for _, model in world:GetDescendants() do
		if model:IsA("Model") and model:HasTag("TraversalToy") then
			for _, part in model:GetChildren() do
				if
					part:IsA("BasePart")
					and (
						string.sub(part.Name, -4) == "_Pad"
						or string.sub(part.Name, -6) == "_Chute"
					)
				then
					table.insert(toyParts, part)
				end
			end
		end
	end
	toyParams.FilterDescendantsInstances = toyParts
end

local function toyStep()
	local rootPart, humanoid = characterParts()
	activeChute = nil
	if not rootPart or not humanoid or #toyParts == 0 then
		return
	end
	local hit = workspace:Raycast(
		rootPart.Position,
		Vector3.new(0, -(humanoid.HipHeight + rootPart.Size.Y / 2 + 1.5), 0),
		toyParams
	)
	if not hit then
		return
	end
	local part = hit.Instance
	local model = part.Parent
	local allowed = Rules.ToyAllowed(isCarrying(), humanoid.SeatPart ~= nil)
	local now = os.clock()
	if string.sub(part.Name, -4) == "_Pad" then
		if not allowed then
			if now - lastToyNotice > 2 and humanoid.SeatPart == nil then
				lastToyNotice = now
				notice(Atmosphere.Toys.CarryNotice)
			end
			return
		end
		if now - lastBounce >= Atmosphere.Toys.BounceCooldownSeconds then
			lastBounce = now
			local speed = (model and model:GetAttribute("LaunchSpeed")) or 72
			local v = rootPart.AssemblyLinearVelocity
			rootPart.AssemblyLinearVelocity = Vector3.new(v.X, speed :: number, v.Z)
		end
	elseif string.sub(part.Name, -6) == "_Chute" then
		if not allowed then
			if now - lastToyNotice > 2 and humanoid.SeatPart == nil then
				lastToyNotice = now
				notice(Atmosphere.Toys.CarrySlideNotice)
			end
			return
		end
		activeChute = part :: BasePart
	end
end

-- Per frame only while standing on a chute: accelerate downhill up to the slide cap.
local function slideStep(dt: number)
	local chute = activeChute
	local rootPart = characterParts()
	if not chute or not rootPart then
		return
	end
	local model = chute.Parent
	local boost = (model and model:GetAttribute("Boost")) or 36
	local down = -chute.CFrame.RightVector
	if down.Y > 0 then
		down = -down
	end
	local v = rootPart.AssemblyLinearVelocity
	local along = v:Dot(down)
	local target = math.min(Atmosphere.Toys.SlideMaxSpeed, along + (boost :: number) * dt * 2)
	rootPart.AssemblyLinearVelocity = v + down * (target - along)
end

---------------------------------------------------------------- POIs
local pois: { any } = {}
local seen: { [string]: boolean } = {}
local function loadPois()
	local regions = ReplicatedStorage.Shared.Config:FindFirstChild("TerrainRegions")
	for _, module in if regions then regions:GetChildren() else {} do
		if module:IsA("ModuleScript") then
			local ok, data = pcall(require, module)
			if ok and type(data) == "table" and type(data.pois) == "table" then
				local accent = data.palette and (data.palette.glow or data.palette.ground)
					or "#FFFFFF"
				for _, poi in data.pois do
					table.insert(pois, {
						name = poi.name,
						center = poi.center,
						radius = poi.radius,
						colour = accent,
					})
				end
			end
		end
	end
end

local function poiStep(rootPart: BasePart)
	for _, name in Rules.Discover(pois, seen, rootPart.Position.X, rootPart.Position.Z) do
		local colour = Color3.new(1, 1, 1)
		for _, poi in pois do
			if poi.name == name then
				colour = hex(poi.colour)
			end
		end
		if showBanner then
			showBanner("DISCOVERED!  " .. string.upper(name), colour, 3)
		end
		local s = Instance.new("Sound")
		s.SoundId = Atmosphere.Storm.Sounds.Discovered
		s.Volume = 0.6
		s.Parent = workspace.CurrentCamera
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
end

---------------------------------------------------------------- atmosphere + detail
local grade: ColorCorrectionEffect? = nil
local currentRegion: string? = "__none"
local fireflies: ParticleEmitter? = nil
local fireflyHost: Part? = nil
local baseDensity: number? = nil

local function applyProfile(key: string?)
	local profile = (key and Atmosphere.Profiles[key]) or Atmosphere.Profiles.Default
	local info = TweenInfo.new(Atmosphere.CrossfadeSeconds, Enum.EasingStyle.Sine)
	if not grade or not grade.Parent then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "RegionAtmosphereGrade"
		effect.Parent = Lighting
		grade = effect
	end
	TweenService:Create(grade :: ColorCorrectionEffect, info, {
		TintColor = hex(profile.TintColor),
		Saturation = profile.Saturation,
		Contrast = profile.Contrast,
	}):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		if baseDensity == nil then
			baseDensity = atmosphere.Density
		end
		TweenService:Create(atmosphere, info, {
			Color = hex(profile.AtmosphereColor),
			Haze = profile.Haze,
			Density = profile.Density or baseDensity,
		}):Play()
	end
	if fireflies then
		local look = key and (Atmosphere.Particles :: any)[key]
		fireflies.Enabled = look ~= nil and Atmosphere.Quality.Tiers[tier].particles
		if look then
			fireflies.Name = look.name
			fireflies.Color = ColorSequence.new(hex(look.colours[1]), hex(look.colours[2]))
			fireflies.Rate = look.rate
			fireflies.Speed = NumberRange.new(look.speed[1], look.speed[2])
			fireflies.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, look.size),
				NumberSequenceKeypoint.new(1, 0),
			})
			-- Mist drifts as soft, dim puffs; the others are glowing specks.
			fireflies.LightEmission = if look.mist then 0 else 1
			fireflies.Transparency = NumberSequence.new(if look.mist then 0.75 else 0)
			fireflies.Lifetime = if look.mist then NumberRange.new(6, 9) else NumberRange.new(3, 5)
			-- Snow drifts down, embers rise; the rest float.
			local fall = look.fall or 0
			fireflies.Acceleration = Vector3.new(0, -fall, 0)
		end
	end
end

local function ensureDetail()
	if fireflyHost or tier == "Minimal" then
		return
	end
	local host = Instance.new("Part")
	host.Name = "WorldDetailHost"
	host.Anchored, host.CanCollide, host.CanQuery, host.CanTouch = true, false, false, false
	host.Transparency = 1
	host.Size = Vector3.new(80, 12, 80)
	-- Follows the player into every region; RegionVisibilityController must not toggle its emitter.
	host:SetAttribute("GlobalNavigationFacade", true)
	host.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Fireflies"
	emitter.Color = ColorSequence.new(hex("#C8FF6A"), hex("#2EE9FF"))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Enabled = false
	emitter.Parent = host
	fireflyHost, fireflies = host, emitter
end

local function chooseTier()
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	local samples = {}
	local deadline = os.clock() + Atmosphere.Quality.ProbeSeconds
	while os.clock() < deadline do
		table.insert(samples, RunService.Heartbeat:Wait() * 1000)
	end
	tier = Rules.SelectTier(
		if ok and type(level) == "number" then level else 0,
		Rules.Median(samples),
		Atmosphere.Quality.DropMedianFrameMs
	)
	player:SetAttribute("WorldDetailTier", tier)
end

function Controller.Start(options: { ShowBanner: (string, Color3, number) -> () }?)
	if started then
		return
	end
	started = true
	showBanner = options and options.ShowBanner
	local deadline = os.clock() + 15
	while workspace:GetAttribute("TerrainRedesignActive") ~= true and os.clock() < deadline do
		task.wait(0.25)
	end
	if workspace:GetAttribute("TerrainRedesignActive") ~= true then
		return
	end
	loadPois()
	chooseTier()
	ensureDetail()
	local world = workspace:WaitForChild("World", 30)
	if world then
		indexToys(world)
		local pending = false
		world.DescendantAdded:Connect(function(item)
			-- Streaming adds toy parts later; re-index once per burst.
			if not pending and (item:IsA("BasePart") or item:IsA("Model")) then
				pending = true
				task.delay(1, function()
					pending = false
					indexToys(world)
				end)
			end
		end)
	end
	local toyClock, regionClock = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		toyClock += dt
		regionClock += dt
		if toyClock >= 0.1 then -- 10 Hz scripted effects
			toyClock = 0
			toyStep()
		end
		slideStep(dt)
		if regionClock >= 1 / Atmosphere.RegionPollHz then
			regionClock = 0
			local rootPart = characterParts()
			if rootPart then
				local key = regionAt(rootPart.Position.X, rootPart.Position.Z)
				if key ~= currentRegion then
					currentRegion = key
					applyProfile(key)
				end
				poiStep(rootPart)
				if fireflyHost then
					fireflyHost.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 4, 0))
				end
			end
		end
	end)
end

return Controller
