--!strict
-- Core Loop V2 trip-measurement bot (Studio QA only; A-4). Drives the player's REAL cart with the same
-- W/A/S/D intents a keyboard produces (CartPCInputController._BotInput), shoots through the real SleepRequest
-- remote in assist-lock mode (like holding FIRE with auto-lock), and relies on the real drive-by scoop and
-- auto-bank. Active while ReplicatedStorage.CoreLoopTripBot = true and CoreLoopBotHome (Vector3) is set.
-- Bot limits (stated in the report): straight-line steering with stuck recovery, no route planning,
-- instant target choice. It is closer to a player than the teleporting sim, not a substitute for one.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CampExits = require(ReplicatedStorage.Shared.Config.CampExits)
local RegionFootprints = require(ReplicatedStorage.Shared.Config.RegionFootprints)

-- The bot hunts only inside the Forest footprint (the test profile has no other region unlocked; the
-- Storm boundary pushes carts out of locked regions).
local FOREST: { Vector2 } = RegionFootprints.Forest
local function insideForest(position: Vector3, margin: number): boolean
	local x, z = position.X, position.Z
	local inside = false
	local j = #FOREST
	for i = 1, #FOREST do
		local a, b = FOREST[i], FOREST[j]
		if (a.Y > z) ~= (b.Y > z) and x < (b.X - a.X) * (z - a.Y) / (b.Y - a.Y) + a.X then
			inside = not inside
		end
		j = i
	end
	if not inside then
		return false
	end
	for i = 1, #FOREST do
		local a, b = FOREST[i], FOREST[i % #FOREST + 1]
		local ab = b - a
		local t = math.clamp(((Vector2.new(x, z) - a):Dot(ab)) / ab:Dot(ab), 0, 1)
		if (a + ab * t - Vector2.new(x, z)).Magnitude < margin then
			return false
		end
	end
	return true
end
local function randomForestPoint(): Vector3
	for _ = 1, 50 do
		local p = Vector3.new(math.random(-507, 229), 0, math.random(-654, 202))
		if insideForest(p, 30) then
			return p
		end
	end
	return Vector3.new(-387, 0, -100)
end
local CartInput = require(script.Parent.CartPCInputController)

local Bot = {}

local player = Players.LocalPlayer
local held: { [string]: boolean } = { W = false, A = false, S = false, D = false }
local requestId = math.floor(os.clock() * 1000) + 500000
local lastShotAt = 0
local phase = "Out"
local waypoint: Vector3? = nil
local waypointAt = 0
local stuckSince: number? = nil
local reverseUntil = 0
local reverseSteer = "A"
local stats = { Shots = 0, Reverses = 0, Phases = 0 }
local ignoreNear: Vector3? = nil -- after getting stuck, avoid the spot we were steering at for a while
local ignoreUntil = 0
local route: { Vector3 } = {} -- Return legs: lane outside -> lane inside Camp -> home

-- Camp rectangle from the measured launch lanes (lane positions sit 12 studs outside each edge).
local function inCampRect(p: Vector3): boolean
	return p.X > -267 and p.X < 229 and p.Z > -294 and p.Z < 202
end

local function press(key: string, on: boolean)
	if held[key] ~= on then
		held[key] = on
		CartInput._BotInput(key :: any, on)
	end
end

local function releaseAll()
	for key in held do
		press(key, false)
	end
end

local function myCart(): Model?
	local runtime = Workspace:FindFirstChild("Runtime")
	local carts = runtime and runtime:FindFirstChild("Carts")
	local cart = carts and carts:FindFirstChild("Cart_" .. player.UserId)
	return if cart and cart:IsA("Model") then cart else nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function signedAngle(look: Vector3, desired: Vector3): number
	local a, b = flat(look), flat(desired)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then
		return 0
	end
	a, b = a.Unit, b.Unit
	local angle = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
	return if a:Cross(b).Y > 0 then -angle else angle -- negative = target to the left
end

local forestLanes: { { point: Vector3, normal: Vector3 } } = {}
for _, lane in CampExits.Lanes do
	if lane.region == "REGION_FOREST" then
		table.insert(forestLanes, { point = lane.points[1], normal = lane.normal })
	end
end

local function nearestLane(position: Vector3)
	local best, bestD = forestLanes[1], math.huge
	for _, lane in forestLanes do
		local d = (lane.point - position).Magnitude
		if d < bestD then
			best, bestD = lane, d
		end
	end
	return best
end

local function brainrots(): { Model }
	local runtime = Workspace:FindFirstChild("Runtime")
	local folder = runtime and runtime:FindFirstChild("Brainrots")
	local list = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function asleep(model: Model): boolean
	return model:GetAttribute("Captured") == true
		and model:GetAttribute("BrainrotDisplayState") == "Sleeping"
end

local function shoot(cartPos: Vector3, look: Vector3)
	if os.clock() - lastShotAt < 0.76 then
		return
	end
	local best, bestD = nil, 85
	for _, model in brainrots() do
		if not asleep(model) and model:GetAttribute("Phase12InteractionReady") ~= false then
			local offset = model:GetPivot().Position - cartPos
			local d = offset.Magnitude
			if d < bestD and math.abs(signedAngle(look, offset)) <= 45 then
				best, bestD = model, d
			end
		end
	end
	local itemId = best and best:GetAttribute("ItemId")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("SleepRequest")
	if not best or type(itemId) ~= "string" or not remote then
		return
	end
	lastShotAt = os.clock()
	requestId += 1
	stats.Shots += 1
	local camera = Workspace.CurrentCamera
	local aimPoint = (best :: Model):GetPivot().Position + Vector3.new(0, 1.5, 0)
	local direction = (aimPoint - camera.CFrame.Position).Unit
	local sleepRemote = remote :: RemoteEvent
	sleepRemote:FireServer({
		RequestId = requestId,
		CameraOrigin = camera.CFrame.Position,
		CameraDirection = direction,
		CrosshairDirection = direction,
		ShotMode = "ASSIST_LOCK",
		LockedTargetId = itemId,
		LockedTargetKind = "Brainrot",
	})
end

local function chooseTarget(cartPos: Vector3): Vector3?
	if phase == "Return" then
		while #route > 1 and flat(route[1] - cartPos).Magnitude < 14 do
			table.remove(route, 1)
		end
		return route[1]
	end
	-- Own sleepers first (drive over them to scoop), then awake targets ahead, then explore the Forest.
	local bestSleep, sleepD = nil, 140
	local bestAwake, awakeD = nil, 160
	for _, model in brainrots() do
		local p = model:GetPivot().Position
		local d = flat(p - cartPos).Magnitude
		if not insideForest(p, 30) then
			continue
		end
		if
			ignoreNear
			and os.clock() < ignoreUntil
			and flat(p - (ignoreNear :: Vector3)).Magnitude < 25
		then
			continue
		end
		if asleep(model) then
			if d < sleepD then
				bestSleep, sleepD = p, d
			end
		elseif d < awakeD then
			bestAwake, awakeD = p, d
		end
	end
	if bestSleep then
		return bestSleep
	end
	if bestAwake then
		-- Close to shooting range and keep it ahead (the mounted lock arc is ahead of the cart).
		return bestAwake
	end
	if
		not waypoint
		or os.clock() - waypointAt > 20
		or flat((waypoint :: Vector3) - cartPos).Magnitude < 15
	then
		-- First leg out of Camp: the nearest Forest launch lane; after that, random points in the Forest.
		if not insideForest(cartPos, 0) then
			local lane = nearestLane(cartPos)
			waypoint = lane.point + lane.normal * 40
		else
			waypoint = randomForestPoint()
		end
		waypointAt = os.clock()
	end
	return waypoint
end

local function step()
	local cart = myCart()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if
		not cart
		or not humanoid
		or not humanoid.SeatPart
		or not cart:IsAncestorOf(humanoid.SeatPart)
	then
		releaseAll()
		return
	end
	local pivot = cart:GetPivot()
	local cartPos, look = pivot.Position, pivot.LookVector
	local root = cart.PrimaryPart
	local speed = if root then flat(root.AssemblyLinearVelocity).Magnitude else 0
	local count = cart:GetAttribute("CargoCount") or 0
	local capacity = cart:GetAttribute("CargoCapacity") or 3
	if phase == "Out" and count >= capacity then
		phase = "Return"
		stats.Phases += 1
		local home = ReplicatedStorage:GetAttribute("CoreLoopBotHome")
		route = {}
		if not inCampRect(cartPos) then
			-- Enter Camp only through a measured Forest launch lane (the West edge is cliffs).
			local lane = nearestLane(cartPos)
			table.insert(route, lane.point + lane.normal * 35)
			table.insert(route, lane.point - lane.normal * 30)
		end
		if typeof(home) == "Vector3" then
			table.insert(route, home)
		end
	elseif phase == "Return" and count == 0 then
		phase = "Out"
		waypoint = nil
		stats.Phases += 1
	end
	if phase == "Out" then
		shoot(cartPos, look)
	end
	ReplicatedStorage:SetAttribute(
		"CoreLoopBotState",
		string.format("%s legs=%d shots=%d rev=%d", phase, #route, stats.Shots, stats.Reverses)
	)
	local target = chooseTarget(cartPos)
	if not target then
		releaseAll()
		return
	end
	local offset = target - cartPos
	local angle = signedAngle(look, offset)
	local distance = flat(offset).Magnitude
	-- Stuck recovery: throttle held, no speed for 2.5 s -> reverse while steering away for 1.2 s.
	local t = os.clock()
	if t < reverseUntil then
		press("W", false)
		press("S", true)
		press("A", reverseSteer == "A")
		press("D", reverseSteer == "D")
		return
	end
	if held.W and speed < 3 then
		stuckSince = stuckSince or t
		if t - (stuckSince :: number) > 2.5 then
			reverseUntil = t + 1.6
			reverseSteer = if angle > 0 then "A" else "D"
			stuckSince = nil
			stats.Reverses += 1
			-- Give up on whatever we were driving at for 8 s and pick a fresh waypoint.
			ignoreNear, ignoreUntil = target, t + 8
			waypoint = nil
			return
		end
	else
		stuckSince = nil
	end
	press("S", false)
	-- Arrived at home: idle on the base and let the auto-bank run.
	if phase == "Return" and #route <= 1 and distance < 8 then
		press("W", false)
		press("A", false)
		press("D", false)
		return
	end
	press("W", true)
	press("D", angle > 6)
	press("A", angle < -6)
end

function Bot.Start()
	if not RunService:IsStudio() then
		return
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		if ReplicatedStorage:GetAttribute("CoreLoopTripBot") ~= true then
			if next(held) and (held.W or held.A or held.S or held.D) then
				releaseAll()
			end
			return
		end
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local ok, err = pcall(step)
		if not ok then
			warn("[CoreLoopTripBot] " .. tostring(err))
		end
	end)
end

function Bot.Stats(): any
	return { Shots = stats.Shots, Reverses = stats.Reverses, Phases = stats.Phases, Phase = phase }
end

return Bot
