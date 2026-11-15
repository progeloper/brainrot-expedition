--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local PlayerBaseSystem = require(script.Parent.PlayerBaseSystem)
local CartService = require(script.Parent.Parent.Services.CartService)
local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)

local log = Logger.new("PlayerSpawnSystem")
local READY_TIMEOUT_SECONDS = 15
local NO_BASE_MESSAGE = "No player base is available in this server. Please try another server."

type SpawnState = {
	Player: Player,
	Base: Model,
	Spawn: SpawnLocation,
	Character: Model?,
	CharacterConnection: RBXScriptConnection?,
	DeathConnection: RBXScriptConnection?,
	Loading: boolean,
	RespawnDue: boolean,
}

local PlayerSpawnSystem = {}
local started = false
local states: { [Player]: SpawnState } = {}
local readiness: any = nil

local function isCurrent(state: SpawnState): boolean
	return states[state.Player] == state
		and state.Player.Parent == Players
		and PlayerBaseSystem:GetBase(state.Player) == state.Base
		and state.Spawn.Parent == state.Base
		and state.Spawn:IsDescendantOf(Workspace)
end

local function isCurrentCharacter(state: SpawnState, character: Model): boolean
	return isCurrent(state) and state.Character == character and state.Player.Character == character
end

local function failCharacter(state: SpawnState, reason: string)
	if not isCurrent(state) then
		return
	end
	log:Warn("Character load failed for %s: %s", state.Player.Name, reason)
	state.Player:Kick("Unable to load your character. Please rejoin the server.")
end

local loadCharacter: (SpawnState, Model?) -> ()

local function onCharacterAdded(state: SpawnState, character: Model)
	if
		not isCurrent(state)
		or state.Player.Character ~= character
		or state.Character == character
	then
		return
	end
	if state.DeathConnection ~= nil then
		state.DeathConnection:Disconnect()
		state.DeathConnection = nil
	end
	state.Character = character
	state.RespawnDue = false

	local humanoid = character:WaitForChild("Humanoid", READY_TIMEOUT_SECONDS)
	if not isCurrentCharacter(state, character) then
		return
	end
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		failCharacter(state, "Humanoid was not ready within the timeout")
		return
	end

	local deathScheduled = false
	local function onDied()
		if deathScheduled or not isCurrentCharacter(state, character) then
			return
		end
		deathScheduled = true
		task.delay(Players.RespawnTime, function()
			if not isCurrentCharacter(state, character) then
				return
			end
			state.RespawnDue = true
			if not state.Loading then
				loadCharacter(state, character)
			end
		end)
	end
	state.DeathConnection = humanoid.Died:Connect(onDied)
	if humanoid.Health <= 0 then
		onDied()
		return
	end

	local root = character:WaitForChild("HumanoidRootPart", READY_TIMEOUT_SECONDS)
	if not isCurrentCharacter(state, character) then
		return
	end
	if root == nil or not root:IsA("BasePart") then
		failCharacter(state, "HumanoidRootPart was not ready within the timeout")
		return
	end

	-- CharacterAdded precedes native spawn placement. Position only after loading finishes.
	local deadline = os.clock() + READY_TIMEOUT_SECONDS
	while state.Loading or not character:IsDescendantOf(Workspace) do
		if os.clock() >= deadline then
			failCharacter(state, "Character did not finish loading into Workspace")
			return
		end
		task.wait(0.05)
		if not isCurrentCharacter(state, character) then
			return
		end
	end
	if humanoid.Health <= 0 then
		return
	end

	local standingHeight = root.Size.Y / 2 + humanoid.HipHeight
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		if leg == nil or not leg:IsA("BasePart") then
			failCharacter(state, "R6 character has no Left Leg for standing clearance")
			return
		end
		standingHeight += leg.Size.Y
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character, state.Spawn }
	rayParams.RespectCanCollide = true
	local floor = Workspace:Raycast(
		state.Spawn.Position + Vector3.new(0, 2, 0),
		Vector3.new(0, -12, 0),
		rayParams
	)
	if floor == nil or floor.Normal.Y < 0.7 then
		failCharacter(state, "PlayerSpawn has no walkable supporting floor")
		return
	end

	local rootFrame = CFrame.new(floor.Position + Vector3.new(0, standingHeight + 0.1, 0))
		* state.Spawn.CFrame.Rotation
	local rootToPivot = root.CFrame:ToObjectSpace(character:GetPivot())
	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	character:PivotTo(rootFrame * rootToPivot)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	log:Info("Spawned %s on foot at %s", state.Player.Name, state.Spawn:GetFullName())
end

loadCharacter = function(state: SpawnState, previousCharacter: Model?)
	if not isCurrent(state) or state.Loading then
		return
	end
	if previousCharacter ~= nil then
		if not isCurrentCharacter(state, previousCharacter) then
			return
		end
	elseif state.Player.Character ~= nil then
		onCharacterAdded(state, state.Player.Character)
		return
	end

	state.Loading = true
	state.RespawnDue = false
	state.Spawn.Enabled = true
	state.Player.RespawnLocation = state.Spawn
	local success, failure = pcall(function()
		state.Player:LoadCharacterAsync()
	end)
	if not isCurrent(state) then
		return
	end
	state.Loading = false
	if not success then
		failCharacter(state, tostring(failure))
		return
	end
	-- A death during loading must not be lost if its respawn delay already elapsed.
	local character = state.Character
	if state.RespawnDue and character ~= nil and isCurrentCharacter(state, character) then
		task.defer(loadCharacter, state, character)
	end
end

local function addPlayer(player: Player)
	if player.Parent ~= Players or states[player] ~= nil then
		return
	end
	if readiness and not readiness:IsReady(player) then
		return
	end
	local base = PlayerBaseSystem:GetBase(player)
	local reason: string? = nil
	if base == nil then
		base, reason = PlayerBaseSystem:AssignBase(player)
	end
	local spawn = if base ~= nil then base:FindFirstChild("PlayerSpawn") else nil
	if base == nil or spawn == nil or not spawn:IsA("SpawnLocation") then
		log:Warn(
			"Cannot spawn %s: %s",
			player.Name,
			reason or "Assigned base has no PlayerSpawn SpawnLocation"
		)
		player:Kick(NO_BASE_MESSAGE)
		return
	end

	local state: SpawnState = {
		Player = player,
		Base = base,
		Spawn = spawn,
		Character = nil,
		CharacterConnection = nil,
		DeathConnection = nil,
		Loading = false,
		RespawnDue = false,
	}
	states[player] = state
	spawn.Enabled = true
	player.RespawnLocation = spawn
	state.CharacterConnection = player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(state, character)
	end)
	task.spawn(function()
		if not isCurrent(state) then
			return
		end
		-- The world lifecycle normally constructs the cart before publishing Ready.
		-- Keep this idempotent fallback for legacy/non-profile bootstraps.
		if FeatureFlags.CartEnabled then
			local success, result = pcall(function()
				return CartService:SpawnCart(player)
			end)
			if not isCurrent(state) then
				return
			end
			if not success then
				log:Warn("Initial home cart failed for %s: %s", player.Name, tostring(result))
			end
		end
		local character = player.Character
		if character ~= nil then
			onCharacterAdded(state, character)
		else
			loadCharacter(state, nil)
		end
	end)
end

function PlayerSpawnSystem:Start(options: any?)
	if started then
		return
	end
	assert(
		not Players.CharacterAutoLoads,
		"Disable CharacterAutoLoads before starting PlayerSpawnSystem"
	)
	started = true
	readiness = if options then options.Readiness else nil
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = states[player]
		if state == nil then
			return
		end
		states[player] = nil -- Invalidates pending character/respawn callbacks before cleanup.
		if state.CharacterConnection ~= nil then
			state.CharacterConnection:Disconnect()
		end
		if state.DeathConnection ~= nil then
			state.DeathConnection:Disconnect()
		end
		if player.RespawnLocation == state.Spawn then
			player.RespawnLocation = nil
		end
		-- Ownership and disabling PlayerSpawn remain PlayerBaseSystem's responsibility.
	end)
	Players.PlayerAdded:Connect(addPlayer)
	if readiness and readiness.SubscribeReady then
		readiness:SubscribeReady(addPlayer)
	end
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	log:Info("Controlled home character spawning ready")
end

return PlayerSpawnSystem
