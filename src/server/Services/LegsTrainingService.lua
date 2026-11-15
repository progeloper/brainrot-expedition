--!strict
-- Playtest Fixes 2, Part G (LegsTrainingV1Enabled): Legs training. Server-authoritative:
--   * A ≤ 5 Hz presence poll finds on-foot players standing on the treadmill belt (no input needed:
--     AFK-friendly; shared, the belt does not collide players with each other). Every TickSeconds on
--     the belt: +Legs XP through the profile's ordinary mutation path (Phase13Rules.ApplyLegsTick).
--   * WalkSpeed comes from the saved Legs level (never while dazed: PlayerCombatService owns that).
--   * One Trail per player, on foot only, from Phase13.EquippedTrail. Equip through the LegsRequest
--     RemoteFunction (owned trails only, rate limited). Gem trails are bought through the existing
--     GemShop transaction (receipts unchanged); Legs 5 / 10 / 15 grant the free ones.
--   * With the flag off the treadmill is moved out of the world at server start and nothing else runs.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Legs = require(ReplicatedStorage.Shared.Config.LegsTraining)
local LegsFlags = require(ReplicatedStorage.Shared.Config.LegsTrainingFlags)
local Rules = require(ReplicatedStorage.Shared.Utility.Phase13Rules)
local CommerceRules = require(ReplicatedStorage.Shared.Utility.Phase13CommerceRules)

local Service = {}
local started = false
local belt: BasePart? = nil
local profiles: any = nil

type PlayerState = {
	running: boolean,
	accumulator: number,
	trail: Trail?,
	trailId: string?,
	lastEquip: number,
}
local playerState: { [Player]: PlayerState } = {}

local function stateOf(player: Player): PlayerState
	local s = playerState[player]
	if not s then
		s = { running = false, accumulator = 0, trail = nil, trailId = nil, lastEquip = -math.huge }
		playerState[player] = s
	end
	return s
end

-- Pure: is a point standing on the belt (inside its footprint, within BeltStandHeight above its top)?
function Service.OnBelt(
	beltFrame: CFrame,
	beltSize: Vector3,
	point: Vector3,
	standHeight: number
): boolean
	local l = beltFrame:PointToObjectSpace(point)
	local top = beltSize.Y / 2
	return math.abs(l.X) <= beltSize.X / 2
		and math.abs(l.Z) <= beltSize.Z / 2
		and l.Y >= top - 0.5
		and l.Y <= top + standHeight
end

local function services(): Instance?
	local map = Workspace:FindFirstChild("MapBlockout")
	local art = map and map:FindFirstChild("MapArt")
	return art and art:FindFirstChild("Services")
end

local function legsData(player: Player): any?
	local data = profiles and profiles:GetReadableData(player)
	local p = data and data.Phase13
	if type(p) ~= "table" or type(p.LegsLevel) ~= "number" then
		return nil
	end
	return data
end

local function publish(player: Player)
	local data = legsData(player)
	if not data then
		return
	end
	local p = data.Phase13
	player:SetAttribute("LegsLevel", p.LegsLevel)
	player:SetAttribute("LegsXP", p.LegsXP)
	player:SetAttribute(
		"LegsXpToNext",
		if p.LegsLevel < Legs.MaxLevel then Legs.XpToNext(p.LegsLevel) else 0
	)
	local owned = {}
	for _, trail in Legs.Trails do
		if p.OwnedTrails[trail.id] == true then
			table.insert(owned, trail.id)
		end
	end
	player:SetAttribute("LegsOwnedTrails", table.concat(owned, ","))
	player:SetAttribute("LegsEquippedTrail", p.EquippedTrail)
end
Service.Publish = publish

local function humanoidOf(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function dazed(player: Player): boolean
	local deadline = player:GetAttribute("Phase10DazeEnd")
	return type(deadline) == "number" and deadline > Workspace:GetServerTimeNow()
end

-- WalkSpeed from the saved level. Daze (WalkSpeed 0) is left alone; it restores its own value.
local function applySpeed(player: Player)
	local data = legsData(player)
	local humanoid = humanoidOf(player)
	if not data or not humanoid or dazed(player) or humanoid.WalkSpeed <= 0 then
		return
	end
	local target = Legs.WalkSpeed(data.Phase13.LegsLevel)
	if math.abs(humanoid.WalkSpeed - target) > 1e-3 then
		humanoid.WalkSpeed = target
	end
end

local function clearTrail(s: PlayerState)
	if s.trail then
		local a0, a1 = s.trail.Attachment0, s.trail.Attachment1
		s.trail:Destroy()
		if a0 then
			a0:Destroy()
		end
		if a1 then
			a1:Destroy()
		end
	end
	s.trail, s.trailId = nil, nil
end

-- One Trail per player, built from the equipped id, enabled on foot only.
local function applyTrail(player: Player)
	local s = stateOf(player)
	local data = legsData(player)
	local id = data and data.Phase13.EquippedTrail or ""
	local humanoid, root = humanoidOf(player)
	local spec = Legs.TrailsById[id]
	if not spec or not humanoid or not root then
		clearTrail(s)
		return
	end
	if s.trail and s.trailId == id and s.trail.Parent == root then
		s.trail.Enabled = humanoid.SeatPart == nil
		return
	end
	clearTrail(s)
	local a0 = Instance.new("Attachment")
	a0.Name = "LegsTrailTop"
	a0.Position = Vector3.new(0, 0.9, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "LegsTrailBottom"
	a1.Position = Vector3.new(0, -1.6, 0.4)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "LegsTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	local keys = {}
	for i, c in spec.colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #spec.colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, spec.colors[1]))
	end
	trail.Color = ColorSequence.new(keys)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Lifetime = Legs.TrailLifetime
	trail.MinLength = 0.1
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail:SetAttribute("LegsTrailId", id)
	trail.Enabled = humanoid.SeatPart == nil
	trail.Parent = root
	s.trail, s.trailId = trail, id
end

local function campEvent(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("CampReworkEvent")
	return if event and event:IsA("RemoteEvent") then event else nil
end

local function tick(player: Player)
	local data = legsData(player)
	if not data then
		return
	end
	local hasPass = CommerceRules.HasEntitlement(data, Legs.PassId)
	local xp = Legs.XpPerTick(hasPass)
	local gained, level, unlocked = 0, data.Phase13.LegsLevel, {}
	local result = profiles:CommitMutation(player, function(current)
		local ok, out = Rules.ApplyLegsTick(current, xp)
		if ok then
			gained, level, unlocked = out.levels, out.level, out.unlocked
		end
		return ok, out
	end)
	if type(result) == "table" and result.ok == false then
		return
	end
	publish(player)
	player:SetAttribute("LegsXpGain", xp)
	if gained > 0 then
		applySpeed(player)
		local event = campEvent()
		if event then
			event:FireClient(
				player,
				{ kind = "LegsLevelUp", level = level, gained = gained, unlocked = unlocked }
			)
		end
	end
end

local function poll(dt: number)
	local beltPart = belt
	if not beltPart or not beltPart.Parent then
		return
	end
	local frame, size = beltPart.CFrame, beltPart.Size
	for _, player in Players:GetPlayers() do
		local s = stateOf(player)
		local humanoid, root = humanoidOf(player)
		local running = humanoid ~= nil
			and root ~= nil
			and humanoid.SeatPart == nil
			and player:GetAttribute("CarriedItemId") == nil
			and legsData(player) ~= nil
			and Service.OnBelt(frame, size, (root :: BasePart).Position, Legs.BeltStandHeight)
		if running ~= s.running then
			s.running = running
			s.accumulator = 0
			player:SetAttribute("LegsRunning", if running then true else nil)
		end
		if running then
			s.accumulator += dt
			if s.accumulator >= Legs.TickSeconds then
				s.accumulator -= Legs.TickSeconds
				task.spawn(tick, player)
			end
		end
		applySpeed(player)
		if s.trail and humanoid then
			local onFoot = humanoid.SeatPart == nil
			if s.trail.Enabled ~= onFoot then
				s.trail.Enabled = onFoot
			end
		end
	end
end

local function onReady(player: Player)
	publish(player)
	applySpeed(player)
	applyTrail(player)
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		local s = stateOf(player)
		s.trail, s.trailId = nil, nil
		applySpeed(player)
		applyTrail(player)
	end)
end

local function handleRequest(player: Player, payload: any): any
	if type(payload) ~= "table" or payload.action ~= "EquipTrail" then
		return { ok = false, code = "INVALID_REQUEST" }
	end
	for key in payload do
		if key ~= "action" and key ~= "trailId" then
			return { ok = false, code = "INVALID_REQUEST" }
		end
	end
	local trailId = payload.trailId
	if type(trailId) ~= "string" or #trailId > 40 then
		return { ok = false, code = "INVALID_REQUEST" }
	end
	local s = stateOf(player)
	local now = os.clock()
	if now - s.lastEquip < Legs.EquipCooldownSeconds then
		return { ok = false, code = "BUSY" }
	end
	s.lastEquip = now
	local result = profiles:CommitMutation(player, function(data)
		return Rules.ApplyTrailEquip(data, trailId)
	end)
	if type(result) == "table" and result.ok == false then
		return { ok = false, code = result.code or "REJECTED" }
	end
	publish(player)
	applyTrail(player)
	return { ok = true, equipped = trailId }
end

function Service.Start(): boolean
	if started then
		return false
	end
	started = true
	local folder = services()
	local model = folder and folder:FindFirstChild(Legs.ModelName)
	if not LegsFlags.Enabled() then
		-- Flag off: the world is exactly as before.
		if model then
			local holder = ServerStorage:FindFirstChild("_PlaytestFixesHidden")
				or Instance.new("Folder")
			holder.Name = "_PlaytestFixesHidden"
			holder.Parent = ServerStorage
			model.Parent = holder
		end
		return false
	end
	local beltPart = model and model:FindFirstChild("Belt")
	if not beltPart or not beltPart:IsA("BasePart") then
		warn("[LegsTraining] treadmill belt missing; Legs training disabled")
		return false
	end
	belt = beltPart
	profiles = require(script.Parent.PlayerDataService)
	profiles:SubscribeReady(onReady)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
		task.spawn(onReady, player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local s = playerState[player]
		if s then
			clearTrail(s)
		end
		playerState[player] = nil
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local request = remotes:FindFirstChild("LegsRequest") or Instance.new("RemoteFunction")
	request.Name = "LegsRequest"
	(request :: RemoteFunction).OnServerInvoke = handleRequest
	request.Parent = remotes
	-- Studio QA only (ServerStorage.LegsQA = true before Play): drive levels / Gems on the isolated
	-- Studio test profile. Never present on a live server.
	if RunService:IsStudio() and ServerStorage:GetAttribute("LegsQA") == true then
		local qa = Instance.new("BindableFunction")
		qa.Name = "LegsQA"
		qa.OnInvoke = function(command: string, target: Player, amount: number)
			if command == "AddXp" then
				local result = profiles:CommitMutation(target, function(data)
					return Rules.ApplyLegsTick(data, math.clamp(amount, 1, 10_000))
				end)
				publish(target)
				applySpeed(target)
				return result
			elseif command == "GrantGems" then
				local GemRules = require(ReplicatedStorage.Shared.Utility.GemRules)
				local result = profiles:CommitMutation(target, function(data)
					return true, GemRules.Grant(data, math.clamp(amount, 1, 10_000), false)
				end)
				target:SetAttribute("Gems", GemRules.Balance(profiles:GetReadableData(target)))
				return result
			end
			return "UNKNOWN"
		end
		qa.Parent = ServerStorage
	end
	local interval = 1 / Legs.PollHz
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= interval then
			local step = accumulator
			accumulator = 0
			poll(step)
		end
	end)
	return true
end

return Service
