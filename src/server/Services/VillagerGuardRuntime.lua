--!strict
-- Binds VillagerGuardService to the live game. Started from Bootstrap only when
-- FeatureFlags.VillagerGuardsEnabled is true; with the flag off nothing here runs.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.VillagerGuards)
local Roster = require(ReplicatedStorage.Shared.Config.VillagerRoster)
local Carts = require(ReplicatedStorage.Shared.Config.Carts)
local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
local Palette = require(ReplicatedStorage.Shared.Config.VoxelCreaturePalette)
local RegionFootprints = require(ReplicatedStorage.Shared.Config.RegionFootprints)
local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local FeatureFlagsForAudio = require(ReplicatedStorage.Shared.Config.FeatureFlags)
local StormGeometry = require(ReplicatedStorage.Shared.Utility.StormGeometry)
local Service = require(script.Parent.VillagerGuardService)
local Progress = require(script.Parent.Parent.Data.Phase12Progress)

local Runtime = {}
local started = false
local connections: { any } = {}
local roots: { [string]: Model } = {}
local folder: Folder? = nil
local remote: RemoteEvent? = nil
local baseBounds: { { min: Vector2, max: Vector2 } } = {}
local groundParams = RaycastParams.new()

local FOOTPRINT_KEY_BY_REGION: { [string]: string } = {
	REGION_CAMP = "Camp",
	REGION_FOREST = "Forest",
	REGION_BEACH = "Beach",
	REGION_SWAMP = "Swamp",
	REGION_JUNGLE = "Jungle",
	REGION_ARCTIC = "Arctic",
	REGION_VOLCANO = "Volcano",
	REGION_GLITCH = "GlitchZone",
}

local function regionAt(position: Vector3): string?
	for regionId, key in FOOTPRINT_KEY_BY_REGION do
		local points = RegionFootprints[key]
		if points and StormGeometry.Contains(points, position.X, position.Z) then
			return regionId
		end
	end
	return nil
end

local function isSafePosition(position: Vector3): boolean
	if regionAt(position) == Regions.CampId then
		return true
	end
	for _, bounds in baseBounds do
		if
			position.X >= bounds.min.X
			and position.X <= bounds.max.X
			and position.Z >= bounds.min.Y
			and position.Z <= bounds.max.Y
		then
			return true
		end
	end
	return false
end

local function groundY(position: Vector3): number?
	local result = Workspace:Raycast(
		Vector3.new(position.X, position.Y + 10, position.Z),
		Vector3.new(0, -80, 0),
		groundParams
	)
	return if result then result.Position.Y else nil
end

local function cartPosition(cart: Model): Vector3?
	if cart.Parent == nil then
		return nil
	end
	local ok, pivot = pcall(cart.GetPivot, cart)
	return if ok then pivot.Position else nil
end

local function cartTopSpeed(cart: Model): number
	local normal = cart:GetAttribute("NormalMaxTravelSpeed")
	if type(normal) == "number" and normal > 0 then
		return normal
	end
	local definition = Carts[cart:GetAttribute("CartId") :: any]
	return if definition then definition.MaxTravelSpeed else Config.FallbackCartTopSpeed
end

local function hexFor(rarity: string, mutationId: string?): string
	local mutation = if mutationId then Palette.MutationTag[mutationId] else nil
	if mutation then
		return mutation
	end
	local tier = Palette.RarityTiers[rarity]
	return if tier then (tier.glow or tier.primary) else "#FFFFFF"
end

local function recipients(player: Player, cart: Model): { Player }
	local out = { player }
	for _, seat in cart:GetDescendants() do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			local humanoid = (seat :: Seat).Occupant
			local passenger = if humanoid
				then Players:GetPlayerFromCharacter(humanoid.Parent)
				else nil
			if passenger and passenger ~= player then
				table.insert(out, passenger)
			end
		end
	end
	return out
end

local function publish(villager: any)
	local model = roots[villager.id]
	if not model then
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(2, 0.2, 2)
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.CastShadow = false
		model = Instance.new("Model")
		local built = model :: Model
		built.Name = "Villager_" .. villager.id
		built.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		root.Parent = built
		built.PrimaryPart = root
		built:SetAttribute("VillagerId", villager.id)
		built:SetAttribute("VillagerName", villager.name)
		built:SetAttribute("VillagerType", villager.type)
		built:SetAttribute("VillagerKit", villager.kit)
		built:SetAttribute("RegionId", villager.regionId)
		built.Parent = folder
		roots[villager.id] = built
	end
	local built = model :: Model
	local facing = villager.facing
	local position = villager.position + Vector3.new(0, 0.1, 0)
	built:PivotTo(CFrame.lookAt(position, position + facing))
	if
		built:GetAttribute("State") ~= villager.state
		or built:GetAttribute("StateAt") ~= villager.stateAt
	then
		built:SetAttribute("TargetUserId", villager.targetUserId)
		built:SetAttribute("StateAt", villager.stateAt)
		built:SetAttribute("State", villager.state)
	end
	-- Presentation-only motion state (nil unless natural villager motion is on).
	if villager.motion ~= nil and built:GetAttribute("MotionAt") ~= villager.motionAt then
		if built:GetAttribute("Seed") == nil then
			built:SetAttribute("Seed", villager.seed)
		end
		built:SetAttribute("MotionAt", villager.motionAt)
		built:SetAttribute("Motion", villager.motion)
	end
end

local function computeBaseBounds(playerBaseSystem: any)
	table.clear(baseBounds)
	local ok, bases = pcall(function()
		return playerBaseSystem:GetRegisteredBases()
	end)
	if not ok or type(bases) ~= "table" then
		return
	end
	for _, base in bases do
		local cf, size = base:GetBoundingBox()
		local half = Vector2.new(size.X, size.Z) / 2 + Vector2.new(6, 6)
		local center = Vector2.new(cf.Position.X, cf.Position.Z)
		-- Axis-aligned envelope of the (possibly rotated) base footprint.
		local radius = half.Magnitude
		table.insert(baseBounds, {
			min = center - Vector2.new(radius, radius),
			max = center + Vector2.new(radius, radius),
		})
	end
end

export type Options = {
	CartService: any,
	CartCargoService: any,
	Interaction: any,
	SleepSystem: any,
	PlayerBaseSystem: any,
	Analytics: any?,
	AccessReader: ((Player, string) -> boolean)?,
}

-- Studio-only QA hook (never in a live server): enabled only when RunService:IsStudio()
-- and ServerStorage has VillagerGuardsQA = true. It calls the REAL pickup/load/bank
-- functions so every receipt flows through the normal subscriptions, and moves a parked
-- cart at a given speed to stand in for driving input during automated Play checks.
local function installQaHook(options: Options)
	local ServerStorage = game:GetService("ServerStorage")
	if not RunService:IsStudio() or ServerStorage:GetAttribute("VillagerGuardsQA") ~= true then
		return
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "VillagerGuardsQA"
	local function firstPlayer(): Player?
		return Players:GetPlayers()[1]
	end
	local function standNear(player: Player, position: Vector3, offset: Vector3)
		local character = player.Character
		if character then
			character:PivotTo(
				CFrame.lookAt(position + offset, position + Vector3.new(0, offset.Y, 0))
			)
		end
	end
	fn.OnInvoke = function(command: string, arg: any, arg2: any, arg3: any): any
		local player = firstPlayer()
		if not player then
			return "no player"
		end
		local cart = options.CartService:GetCart(player)
		if command == "state" then
			local rows = {}
			for _, villager in Service.GetVillagers() do
				table.insert(rows, villager.id .. "=" .. villager.state)
			end
			local chase = Service.GetChase(player.UserId)
			return table.concat(rows, ",")
				.. (
					if chase
						then string.format(
							" | chase r=%.0f rarity=%s tags=%d",
							chase.radius,
							chase.rarity,
							chase.tags
						)
						else " | no chase"
				)
		elseif command == "hit" then
			-- Synthetic stand-in for an accepted shot at a position (regions without
			-- spawns for the test profile). Real shots go through SetHitObserver.
			Service.OnHit(player, arg :: Vector3)
			return "hit"
		elseif command == "chase" then
			-- Synthetic stand-in for a CargoPlaced receipt (no carried brainrot needed).
			Service.OnCargoLoaded(player)
			local chase = Service.GetChase(player.UserId)
			return if chase then string.format("chase r=%.0f", chase.radius) else "no chase"
		elseif command == "perf" then
			local awake, total = 0, 0
			for _, villager in Service.GetVillagers() do
				total += 1
				if villager.awake then
					awake += 1
				end
			end
			local perfStart = os.clock()
			local runs = tonumber(arg) or 20
			for _ = 1, runs do
				Service.Step(0.1)
			end
			return string.format(
				"villagers=%d awake=%d stepMs=%.3f",
				total,
				awake,
				(os.clock() - perfStart) * 1000 / runs
			)
		elseif command == "pickup" then
			local model = Workspace:FindFirstChild(arg, true)
			if not model then
				return "no model"
			end
			standNear(player, model:GetPivot().Position, Vector3.new(0, 3, -4))
			task.wait(0.3)
			return table.pack(
				options.Interaction.TryPickupWorld(player, model, model:GetAttribute("ItemId"))
			)
		elseif command == "load" then
			if not cart then
				return "no cart"
			end
			local carried = options.Interaction.GetCarriedRecord(player)
			if not carried then
				return "not carrying"
			end
			if typeof(arg) == "Vector3" then
				cart:PivotTo(CFrame.new(arg) * cart:GetPivot().Rotation)
				task.wait(0.5)
			end
			standNear(player, cart:GetPivot().Position, Vector3.new(0, 3, -6))
			task.wait(0.3)
			for _, slot in { "Slot1", "Slot2", "Slot3" } do
				local ok, reason =
					options.Interaction.TryPlaceInCargo(player, cart, slot, carried.ItemId)
				if ok then
					return "loaded " .. slot
				end
				arg2 = reason
			end
			return "load failed " .. tostring(arg2)
		elseif command == "drive" then
			if not cart then
				return "no cart"
			end
			local direction = (arg :: Vector3).Unit
			local seconds, speed = arg2 :: number, arg3 :: number
			task.spawn(function()
				local driveStart = os.clock()
				local origin = cart:GetPivot()
				while os.clock() - driveStart < seconds and cart.Parent do
					local t = os.clock() - driveStart
					local position = origin.Position + direction * speed * t
					local y = groundY(position + Vector3.new(0, 4, 0))
					cart:PivotTo(
						CFrame.lookAt(
							Vector3.new(position.X, (y or position.Y) + 2.5, position.Z),
							Vector3.new(position.X, (y or position.Y) + 2.5, position.Z) + direction
						)
					)
					local character = player.Character
					if character then
						character:PivotTo(cart:GetPivot() * CFrame.new(0, 3, 4))
					end
					RunService.Heartbeat:Wait()
				end
			end)
			return "driving"
		elseif command == "bank" then
			if not cart then
				return "no cart"
			end
			local entries = options.CartCargoService:GetCargoSnapshot(cart)
			local entry = entries[1]
			if not entry then
				return "empty cart"
			end
			local slotId = "Slot" .. tostring(entry.AttachmentIndex or 1)
			standNear(player, cart:GetPivot().Position, Vector3.new(0, 3, -6))
			task.wait(0.3)
			local ok, reason =
				options.Interaction.TryPickupCargo(player, cart, slotId, entry.ItemId)
			if not ok then
				return "cargo pickup failed " .. tostring(reason)
			end
			local base = options.PlayerBaseSystem:GetBase(player)
			if not base then
				return "no base"
			end
			for _, platform in base:GetDescendants() do
				if platform:IsA("BasePart") and platform:HasTag("BrainrotStoragePlatform") then
					standNear(player, platform.Position, Vector3.new(0, 3, -4))
					task.wait(0.3)
					local placed, why =
						options.Interaction.TryPlaceOnPlatform(player, platform, entry.ItemId)
					if placed then
						return "banked on " .. platform:GetFullName()
					end
					reason = why
				end
			end
			return "bank failed " .. tostring(reason)
		end
		return "unknown command"
	end
	fn.Parent = ServerStorage
end

function Runtime.Start(options: Options)
	if started then
		return
	end
	started = true

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	local existing = (remotes :: Instance):FindFirstChild(RemoteNames.VillagerGuardEvent)
	if not existing then
		existing = Instance.new("RemoteEvent")
		existing.Name = RemoteNames.VillagerGuardEvent
		existing.Parent = remotes
	end
	assert(existing and existing:IsA("RemoteEvent"), "VillagerGuardEvent must be a RemoteEvent")
	remote = existing :: RemoteEvent

	-- Presentation-only audio cue remote (only when game audio is on).
	local audioCue: RemoteEvent? = nil
	if (FeatureFlagsForAudio :: any).GameAudioEnabled then
		local cue = (remotes :: Instance):FindFirstChild(RemoteNames.AudioCue)
		if not cue then
			cue = Instance.new("RemoteEvent")
			cue.Name = RemoteNames.AudioCue
			cue.Parent = remotes
		end
		if cue and cue:IsA("RemoteEvent") then
			audioCue = cue
		end
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = "Villagers"
	newFolder.Parent = Workspace
	folder = newFolder

	local include = { Workspace.Terrain }
	local map = Workspace:FindFirstChild("MapBlockout")
	if map then
		table.insert(include, map)
	end
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = include

	computeBaseBounds(options.PlayerBaseSystem)

	Service.Configure({
		now = function()
			return Workspace:GetServerTimeNow()
		end,
		getCart = function(player)
			return options.CartService:GetCart(player)
		end,
		cartPosition = cartPosition,
		cartTopSpeed = cartTopSpeed,
		cargoProfile = function(cart)
			local best, bestRank, mutation = "Common", 0, nil
			local ok, entries = pcall(function()
				return options.CartCargoService:GetCargoSnapshot(cart)
			end)
			if ok and type(entries) == "table" then
				for _, entry in entries do
					local rarity = Catalog.GetRarity(entry.BrainrotId) or "Common"
					local rank = Config.RarityRank[rarity] or 0
					if rank > bestRank then
						best, bestRank = rarity, rank
						local okMutation, id = pcall(Progress.MutationId, entry)
						mutation = if okMutation
								and id ~= "None"
								and id ~= "Normal"
							then id
							else nil
					end
				end
			end
			return best, hexFor(best, mutation)
		end,
		playerPosition = function(player)
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			return if root and root:IsA("BasePart") then root.Position else nil
		end,
		isSafePosition = isSafePosition,
		canEnter = function(player, position)
			local regionId = regionAt(position)
			if regionId == nil or regionId == Regions.CampId then
				return regionId ~= nil
			end
			if options.AccessReader then
				local ok, allowed = pcall(options.AccessReader, player, regionId)
				return ok and allowed == true
			end
			return true
		end,
		regionAt = regionAt,
		groundY = groundY,
		applySlow = function(cart, factor, untilTime)
			cart:SetAttribute("VillagerSlowFactor", factor)
			cart:SetAttribute("VillagerSlowUntil", untilTime)
		end,
		recipients = recipients,
		fire = function(player, payload)
			(remote :: RemoteEvent):FireClient(player, payload)
		end,
		broadcast = function(payload)
			if audioCue then
				audioCue:FireAllClients(payload)
			end
		end,
		publish = publish,
		record = function(player, name, value, category, result)
			if options.Analytics then
				pcall(function()
					options.Analytics:Record(
						player,
						name,
						value,
						{ category = category or "Session", result = result or "Recorded" }
					)
				end)
			end
		end,
		players = function()
			return Players:GetPlayers()
		end,
	})
	Service.LoadRoster(Roster)

	options.SleepSystem.SetHitObserver(function(player: Player, model: Model)
		if player.Parent == nil or model.Parent == nil then
			return
		end
		local ok, pivot = pcall(model.GetPivot, model)
		if ok then
			Service.OnHit(player, pivot.Position)
		end
	end)
	table.insert(
		connections,
		options.Interaction.SubscribeCommitted(function(player: Player, receipt: any)
			if receipt.kind == "CargoPlaced" then
				Service.OnCargoLoaded(player)
			end
		end)
	)
	table.insert(connections, RunService.Heartbeat:Connect(Service.Heartbeat))
	installQaHook(options)
end

function Runtime.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return Runtime
