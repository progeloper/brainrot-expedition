--!strict
-- Core Loop V2 QA harness (§18.1). Studio-only and present only while ServerStorage.CoreLoopQA = true
-- (the DriveAndHuntQA pattern). Runs with the flag on or off (flag-off comparisons, F-0). Use a test
-- profile (ServerStorage.Phase8TestProfileNamespace).
-- Verbs:
--   "Stats"                         director stats (flag on), hunt-flow stats, RUSH snapshot, cycle id
--   "ResetStats"                    zero the director counters
--   "ForceRush", kind               "Rush" | "Mega" | "Warning" | "Idle"
--   "Access", on                    ignore region locks for the director (test profile has only Forest)
--   "SimHunter", player, region, minutes, mode, seed
--                                   mode "Cart" (43.2 studs/s) | "Foot" (16) | "Trip" (cart speed; drives over
--                                   its own KOs to load them, returns to Camp at 3 loads, records trip time)
--   "SimStop", player / "SimStatus", player
--   "VirtualHunters", count, minutes  virtual hunters (no character) on seeded loops across regions
--   "VirtualStop"
--   "Sample"                        one leak/budget sample (instances, wild, tracked, frame peak)
--   ForceMeter/ForcePity/ForceFirstSession/ForceRain/FxPen/HudGallery: CP-B/CP-C ("NOT_BUILT")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local CampExits = require(ReplicatedStorage.Shared.Config.CampExits)

local Service = {}

local LOCK_RANGE = 88 -- Bow T1 range 90, minus a margin
local LOCK_ARC_COS = math.cos(math.rad(60)) -- only targets ahead, like the auto-lock arc
local CART_SPEED = 43.2
local FOOT_SPEED = 16
local SCOOP_RADIUS = 13
local TRIP_CAPACITY = 3

type Sim = {
	Player: Player,
	Region: string,
	Mode: string,
	Speed: number,
	EndsAt: number,
	StartedAt: number,
	Waypoints: { Vector3 },
	Index: number,
	Shots: number,
	Accepted: number,
	KOs: number,
	KoTimes: { number },
	Reasons: { [string]: number },
	Connection: RBXScriptConnection?,
	LastShotAt: number,
	RequestId: number,
	PendingLoads: { [Model]: boolean },
	Loads: number,
	TripLoads: number,
	TripStartedAt: number?,
	Trips: { number },
	Returning: boolean,
	BankUntil: number,
}

local sims: { [Player]: Sim } = {}
local botReseats = 0
local deps: any = nil

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	return sorted[math.ceil(#sorted / 2)]
end

local function summary(sim: Sim): any
	local gaps = {}
	for i = 2, #sim.KoTimes do
		table.insert(gaps, sim.KoTimes[i] - sim.KoTimes[i - 1])
	end
	local elapsed = math.max(1, os.clock() - sim.StartedAt)
	return {
		Region = sim.Region,
		Mode = sim.Mode,
		Seconds = math.floor(elapsed),
		Shots = sim.Shots,
		Accepted = sim.Accepted,
		KOs = sim.KOs,
		KoPerMinute = sim.KOs / elapsed * 60,
		KoGapMedian = median(gaps),
		Loads = sim.Loads,
		Trips = #sim.Trips,
		TripMedian = median(sim.Trips),
		TripSeconds = table.clone(sim.Trips),
		Reasons = table.clone(sim.Reasons),
		Running = sim.Connection ~= nil,
		Chase = (sim :: any).Chase, -- E-3: per temperament, seconds from lock-on to KO
	}
end

local function inCamp(position: Vector3): boolean
	local RegionSpawnCatalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
	return RegionSpawnCatalog.ContainsPosition(Regions.CampId, position, math.huge)
end

-- Seeded loop of waypoints inside the region's spawn volumes.
local function waypoints(regionId: string, seed: number): { Vector3 }
	local RegionSpawnCatalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
	local rng = Random.new(seed)
	local volumes = {}
	for _, area in RegionSpawnCatalog.GetSpawnAreas(regionId) do
		if type(area) == "table" and area.Enabled == true and area.Kind == "Volume" then
			table.insert(volumes, area)
		end
	end
	local points = {}
	for _ = 1, 12 do
		if #volumes == 0 then
			break
		end
		local area = volumes[rng:NextInteger(1, #volumes)]
		local part = area.Part
		table.insert(
			points,
			part.CFrame:PointToWorldSpace(
				Vector3.new(
					rng:NextNumber(-0.4, 0.4) * part.Size.X,
					0,
					rng:NextNumber(-0.4, 0.4) * part.Size.Z
				)
			)
		)
	end
	return points
end

-- A point 40 studs inside Camp behind the nearest launch lane (lane points sit just outside Camp).
local function nearestLane(position: Vector3): Vector3?
	local best, bestD = nil, math.huge
	for _, lane in CampExits.Lanes do
		local point = lane.points[1] - lane.normal * 40
		local d = (point - position).Magnitude
		if d < bestD then
			best, bestD = point, d
		end
	end
	return best
end

local function stopSim(sim: Sim)
	if sim.Connection then
		sim.Connection:Disconnect()
		sim.Connection = nil
	end
	sim.Player:SetAttribute("CoreLoopSimVelocity", nil)
	local root = sim.Player.Character and sim.Player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = false
	end
end

local function fire(sim: Sim, root: BasePart, heading: Vector3)
	local World = deps.Spawner
	local best, bestDistance = nil, LOCK_RANGE
	for _, model in World.GetWorldModels() do
		local record, state = World.GetWorldRecord(model)
		if
			record
			and state == "WorldAwake"
			and model:GetAttribute("Phase12InteractionReady") == true
		then
			local offset = model:GetPivot().Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local d = offset.Magnitude
			if
				d < bestDistance
				and flat.Magnitude > 0.5
				and flat.Unit:Dot(heading) >= LOCK_ARC_COS
			then
				best, bestDistance = model, d
			end
		end
	end
	if not best then
		return
	end
	local record = World.GetWorldRecord(best)
	local origin = root.Position + Vector3.new(0, 2.5, 0)
	local direction = (best:GetPivot().Position + Vector3.new(0, 1.5, 0) - origin).Unit
	sim.RequestId += 1
	sim.Shots += 1
	local SleepSystem = require(script.Parent.Parent.Systems.BrainrotSleepSystem)
	local ok, shot, reason = pcall(SleepSystem.HandleFireRequest, sim.Player, {
		CameraOrigin = origin,
		CameraDirection = direction,
		CrosshairDirection = direction,
		ShotMode = "ASSIST_LOCK",
		LockedTargetId = record.ItemId,
		LockedTargetKind = "Brainrot",
		RequestId = sim.RequestId,
	})
	if ok and shot then
		sim.Accepted += 1
		task.defer(function()
			local _, after = World.GetWorldRecord(best)
			if after == "WorldSleeping" then
				sim.KOs += 1
				table.insert(sim.KoTimes, os.clock())
				if sim.Mode == "Trip" then
					sim.PendingLoads[best] = true
				end
			end
		end)
	else
		local key = if ok then tostring(reason) else "ERROR"
		sim.Reasons[key] = (sim.Reasons[key] or 0) + 1
	end
end

-- Trip mode target: the nearest pending sleeper while cargo has room, else Camp, else the loop.
local function tripTarget(sim: Sim, position: Vector3): Vector3?
	if sim.Returning then
		return nearestLane(position)
	end
	local best, bestD = nil, math.huge
	for model in sim.PendingLoads do
		local _, state = deps.Spawner.GetWorldRecord(model)
		if model.Parent == nil or state ~= "WorldSleeping" then
			sim.PendingLoads[model] = nil
		else
			local d = (model:GetPivot().Position - position).Magnitude
			if d < bestD then
				best, bestD = model, d
			end
		end
	end
	if best then
		if bestD <= SCOOP_RADIUS then
			-- Stand-in for the drive-by scoop: the individual leaves the wild exactly as a load does.
			local record = deps.Spawner.GetWorldRecord(best)
			sim.PendingLoads[best] = nil
			if record and deps.Spawner.RetireFreshIndividual(record, "QA_SimLoad") then
				sim.Loads += 1
				sim.TripLoads += 1
				if sim.TripLoads >= TRIP_CAPACITY then
					sim.Returning = true
				end
			end
			return nil
		end
		return best:GetPivot().Position
	end
	return nil
end

local function startSim(
	player: Player,
	regionId: string,
	minutes: number,
	mode: string,
	seed: number?
): any
	local existing = sims[player]
	if existing then
		stopSim(existing)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		return "NO_CHARACTER"
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local launcher = backpack and backpack:FindFirstChild("SleepLauncher")
	if launcher and launcher:IsA("Tool") then
		humanoid:EquipTool(launcher)
	end
	local points = waypoints(regionId, seed or 20261114)
	if #points < 2 then
		return "NO_WAYPOINTS"
	end
	local sim: Sim = {
		Player = player,
		Region = regionId,
		Mode = mode,
		Speed = if mode == "Foot" or mode == "Chase" then FOOT_SPEED else CART_SPEED,
		EndsAt = os.clock() + minutes * 60,
		StartedAt = os.clock(),
		Waypoints = points,
		Index = 1,
		Shots = 0,
		Accepted = 0,
		KOs = 0,
		KoTimes = {},
		Reasons = {},
		Connection = nil,
		LastShotAt = 0,
		RequestId = math.floor(os.clock() * 1000), -- above any id the validator already accepted
		PendingLoads = {},
		Loads = 0,
		TripLoads = 0,
		TripStartedAt = nil,
		Trips = {},
		Returning = false,
		BankUntil = 0,
	}
	sims[player] = sim
	root.Anchored = true
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances =
		{ character :: Instance, Workspace:FindFirstChild("Runtime") :: Instance }
	local start = if mode == "Trip" then (nearestLane(points[1]) or points[1]) else points[1] -- Trip starts in Camp
	root:PivotTo(CFrame.new(start + Vector3.new(0, 4, 0)))
	sim.Connection = RunService.Heartbeat:Connect(function(dt)
		if os.clock() >= sim.EndsAt or player.Parent ~= Players or not root.Parent then
			stopSim(sim)
			return
		end
		local here = root.Position
		local target: Vector3 = sim.Waypoints[sim.Index]
		if mode == "Trip" then
			local camp = inCamp(here)
			if camp and sim.Returning then
				-- Trip ends at Camp entry, then a short bank pause, then out again.
				if sim.TripStartedAt then
					table.insert(sim.Trips, os.clock() - sim.TripStartedAt)
				end
				sim.TripStartedAt, sim.Returning, sim.TripLoads = nil, false, 0
				sim.BankUntil = os.clock() + 2
			end
			if os.clock() < sim.BankUntil then
				player:SetAttribute("CoreLoopSimVelocity", Vector3.zero)
				return
			end
			if not camp and sim.TripStartedAt == nil then
				sim.TripStartedAt = os.clock()
			end
			target = tripTarget(sim, here) or target
		end
		if mode == "Chase" then
			local simAny: any = sim
			-- E-3 catchability: lock onto the nearest awake brainrot and pursue it on foot until it sleeps.
			local focus = simAny.Focus
			if focus then
				local _, focusState = deps.Spawner.GetWorldRecord(focus)
				if focusState ~= "WorldAwake" or not focus.Parent then
					-- Close the trial: KO (asleep) or lost (despawned / left).
					local chase = simAny.Chase or {}
					simAny.Chase = chase
					local temp = simAny.FocusTemp or "?"
					local row = chase[temp] or { KO = {}, Lost = 0 }
					chase[temp] = row
					if focusState == "WorldSleeping" then
						table.insert(row.KO, math.floor((os.clock() - simAny.FocusAt) * 10) / 10)
					else
						row.Lost += 1
					end
					focus = nil
				end
			end
			if not focus then
				local bestD = 250
				for _, model in deps.Spawner.GetWorldModels() do
					local _, st = deps.Spawner.GetWorldRecord(model)
					if
						st == "WorldAwake"
						and model:GetAttribute("Phase12InteractionReady") == true
					then
						local dist = (model:GetPivot().Position - here).Magnitude
						if dist < bestD then
							focus, bestD = model, dist
						end
					end
				end
				simAny.Focus = focus
				if focus then
					simAny.FocusAt = os.clock()
					simAny.FocusTemp = focus:GetAttribute("CoreLoopTemperament") or "?"
				end
			end
			if focus then
				local fp = focus:GetPivot().Position
				local off = Vector3.new(fp.X - here.X, 0, fp.Z - here.Z)
				if off.Magnitude < 18 and off.Magnitude > 0.5 then
					local facing = off.Unit
					root.CFrame = CFrame.lookAt(here, here + facing)
					player:SetAttribute("CoreLoopSimVelocity", Vector3.zero)
					if os.clock() - sim.LastShotAt >= 0.76 then
						sim.LastShotAt = os.clock()
						fire(sim, root, facing)
					end
					return
				end
				target = fp
			end
		end
		local flat = Vector3.new(target.X - here.X, 0, target.Z - here.Z)
		if flat.Magnitude < 6 then
			if target == sim.Waypoints[sim.Index] then
				sim.Index = sim.Index % #sim.Waypoints + 1
			end
			return
		end
		local heading = flat.Unit
		local nextPosition = here + heading * math.min(flat.Magnitude, sim.Speed * dt)
		local hit =
			Workspace:Raycast(nextPosition + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
		local y = if hit then hit.Position.Y + 3 else nextPosition.Y
		local placed = Vector3.new(nextPosition.X, y, nextPosition.Z)
		root.CFrame = CFrame.lookAt(placed, placed + heading)
		player:SetAttribute("CoreLoopSimVelocity", heading * sim.Speed)
		-- Bow T1 cadence 0.75 s; the server validator enforces the real cadence anyway.
		if os.clock() - sim.LastShotAt >= 0.76 and not (mode == "Trip" and sim.Returning) then
			sim.LastShotAt = os.clock()
			fire(sim, root, heading)
		end
	end)
	return "STARTED"
end

------------------------------------------------------------------ virtual hunters (A-5, P-1, B-3)
type Virtual = {
	Key: any,
	UserId: number,
	Position: Vector3,
	Velocity: Vector3,
	Look: Vector3,
	Points: { Vector3 },
	Index: number,
}
local virtuals: { Virtual } = {}
local virtualConnection: RBXScriptConnection? = nil
local virtualEndsAt = 0

local function stopVirtuals()
	if virtualConnection then
		virtualConnection:Disconnect()
		virtualConnection = nil
	end
	table.clear(virtuals)
	if deps.Director then
		deps.Director._SetVirtualHuntersForQA(nil)
	end
end

local function startVirtuals(count: number, minutes: number): any
	if not deps.Director then
		return "DIRECTOR_OFF"
	end
	stopVirtuals()
	local regions = {
		"REGION_FOREST",
		"REGION_BEACH",
		"REGION_SWAMP",
		"REGION_JUNGLE",
		"REGION_ARCTIC",
		"REGION_VOLCANO",
		"REGION_GLITCH",
	}
	for i = 1, count do
		local region = regions[(i - 1) % #regions + 1]
		local points = waypoints(region, 9000 + i)
		if #points >= 2 then
			table.insert(virtuals, {
				Key = { Name = "VirtualHunter" .. i },
				UserId = -1000 - i,
				Position = points[1],
				Velocity = Vector3.zero,
				Look = Vector3.zAxis,
				Points = points,
				Index = 2,
			})
		end
	end
	virtualEndsAt = os.clock() + minutes * 60
	deps.Director._SetVirtualHuntersForQA(function()
		local rows = {}
		for _, v in virtuals do
			table.insert(rows, {
				Player = v.Key,
				UserId = v.UserId,
				Position = v.Position,
				Velocity = v.Velocity,
				Look = v.Look,
			})
		end
		return rows
	end)
	virtualConnection = RunService.Heartbeat:Connect(function(dt)
		if os.clock() >= virtualEndsAt then
			stopVirtuals()
			return
		end
		for _, v in virtuals do
			local target = v.Points[v.Index]
			local flat = Vector3.new(target.X - v.Position.X, 0, target.Z - v.Position.Z)
			if flat.Magnitude < 6 then
				v.Index = v.Index % #v.Points + 1
			else
				v.Look = flat.Unit
				v.Velocity = flat.Unit * CART_SPEED
				v.Position += flat.Unit * math.min(flat.Magnitude, CART_SPEED * dt)
			end
		end
	end)
	return #virtuals
end

function Service.Start(options: any)
	if not RunService:IsStudio() or ServerStorage:GetAttribute("CoreLoopQA") ~= true then
		return
	end
	deps = options
	local hook = Instance.new("BindableFunction")
	hook.Name = "CoreLoopQA"
	hook.OnInvoke = function(verb: string, a: any, b: any, c: any, d: any, e: any)
		if verb == "Stats" then
			local stats = if deps.Director then deps.Director.GetStats() else {}
			stats.DirectorOn = deps.Director ~= nil
			stats.CycleId = Workspace:GetAttribute("Phase12CycleId")
			stats.RushState = Workspace:GetAttribute("RushState")
			stats.ResetDeadline = Workspace:GetAttribute("Phase12ResetDeadline")
			stats.HuntFlow = deps.Spawner.GetHuntFlowDiagnostics()
			stats.WildCount = deps.Spawner.GetWildCount()
			return stats
		elseif verb == "ResetStats" then
			if deps.Director then
				deps.Director._ResetStatsForQA()
			end
			return true
		elseif verb == "ForceRush" then
			if not deps.Director then
				return false
			end
			deps.Director._SetRushOverrideForQA(if a == "Rush" or a == "Mega" then a else nil)
			return deps.WorldService._ForceRushForQA and deps.WorldService:_ForceRushForQA(a)
				or false
		elseif verb == "Access" then
			if deps.Director then
				deps.Director._SetAccessOverrideForQA(a == true)
			end
			if deps.Spawner._SetDirectedAccessOverrideForQA then
				deps.Spawner._SetDirectedAccessOverrideForQA(a == true)
			end
			return a == true
		elseif verb == "SimHunter" then
			return startSim(a, b or "REGION_FOREST", c or 10, d or "Cart", e)
		elseif verb == "SimStop" then
			local sim = sims[a]
			if not sim then
				return nil
			end
			stopSim(sim)
			return summary(sim)
		elseif verb == "SimStatus" then
			local sim = sims[a]
			return if sim then summary(sim) else nil
		elseif verb == "VirtualHunters" then
			return startVirtuals(a or 8, b or 30)
		elseif verb == "VirtualStop" then
			stopVirtuals()
			return true
		elseif verb == "FxPen" then
			-- L6 review pen (client-local; Studio only).
			game:GetService("ReplicatedStorage")
				:SetAttribute("CoreLoopFxPen", if a == true then true else nil)
			require(script.Parent.CoreLoopFxPenServer).SetActive(a == true)
			return a == true
		elseif verb == "FxTier" then
			game:GetService("ReplicatedStorage"):SetAttribute("CoreLoopFxTier", a)
			return a
		elseif verb == "ForceMeter" then
			require(script.Parent.CoreLoopProgress)._ForceMeterForQA(a, b or 0)
			return true
		elseif verb == "ForcePity" then
			require(script.Parent.CoreLoopProgress)._ForcePityForQA(a, b)
			return true
		elseif verb == "Progress" then
			return require(script.Parent.CoreLoopProgress).GetState(a)
		elseif verb == "StockBase" then
			-- K4 test setup (test profile only): put up to `b` brainrots on the player's base through the real
			-- paths: sleep shot (validator) -> on-foot pickup -> platform placement. Returns per-step results.
			local player: Player = a
			local wanted = b or 3
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (root and root:IsA("BasePart") and humanoid) then
				return "NO_CHARACTER"
			end
			humanoid.Sit = false
			task.wait(0.2)
			local launcher = player.Backpack:FindFirstChild("SleepLauncher")
			if launcher then
				humanoid:EquipTool(launcher)
			end
			local Interaction = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
			local Storage = require(script.Parent.Parent.Systems.BaseStorageSystem)
			local SleepSystem = require(script.Parent.Parent.Systems.BrainrotSleepSystem)
			local log = {}
			local placed = 0
			for _ = 1, wanted * 3 do
				if placed >= wanted then
					break
				end
				local best, bestD = nil, math.huge
				for _, model in deps.Spawner.GetWorldModels() do
					local _, state = deps.Spawner.GetWorldRecord(model)
					if
						state == "WorldAwake"
						and (
							model:GetAttribute("CoreLoopOwnerUserId") == nil
							or model:GetAttribute("CoreLoopOwnerUserId") == player.UserId
						)
					then
						local dist = (model:GetPivot().Position - root.Position).Magnitude
						if dist < bestD then
							best, bestD = model, dist
						end
					end
				end
				if not best then
					table.insert(log, "NO_TARGET")
					task.wait(2)
					continue
				end
				local record = deps.Spawner.GetWorldRecord(best)
				root.Anchored = true
				for shot = 1, 6 do
					local target = best:GetPivot().Position
					root.CFrame = CFrame.lookAt(target + Vector3.new(0, 3, -20), target)
					local origin = root.Position + Vector3.new(0, 2.5, 0)
					local direction = (target + Vector3.new(0, 1.5, 0) - origin).Unit
					pcall(SleepSystem.HandleFireRequest, player, {
						CameraOrigin = origin,
						CameraDirection = direction,
						CrosshairDirection = direction,
						ShotMode = "ASSIST_LOCK",
						LockedTargetId = record.ItemId,
						LockedTargetKind = "Brainrot",
						RequestId = math.floor(os.clock() * 1000) + shot,
					})
					task.wait(0.85)
					local _, state = deps.Spawner.GetWorldRecord(best)
					if state == "WorldSleeping" then
						break
					end
				end
				local target = best:GetPivot().Position
				root.CFrame = CFrame.new(target + Vector3.new(0, 3, -4), target)
				task.wait(0.3)
				local picked, why = Interaction.TryPickupWorld(player, best, record.ItemId)
				if not picked then
					table.insert(log, "PICKUP:" .. tostring(why))
					root.Anchored = false
					continue
				end
				local storage = Storage:GetStorageForPlayer(player)
				local done = false
				for index, descriptor in (storage :: any)._slots do
					if
						storage:IsValidPlatformId(index)
						and storage:GetPlatformRecord(index) == nil
					then
						local marker = descriptor.Marker
						local at = if marker:IsA("Attachment")
							then marker.WorldPosition
							else marker.Position
						root.CFrame = CFrame.new(at + Vector3.new(0, 3, -3), at)
						task.wait(0.3)
						local ok, placeWhy = Interaction.TryPlaceOnPlatform(
							player,
							descriptor.Platform,
							record.ItemId
						)
						table.insert(
							log,
							"PLACE:" .. tostring(index) .. ":" .. tostring(ok and "OK" or placeWhy)
						)
						done = ok
						break
					end
				end
				if done then
					placed += 1
				end
				root.Anchored = false
				task.wait(0.5)
			end
			root.Anchored = false
			return { Placed = placed, Log = log }
		elseif verb == "TempStats" then
			return require(script.Parent.Parent.Systems.Behaviours.CoreLoopTemperament)._QAStats()
		elseif verb == "TempReset" then
			require(script.Parent.Parent.Systems.Behaviours.CoreLoopTemperament)._QAReset()
			return true
		elseif verb == "RainNow" then
			-- K4: strike the player's base now (b = optional MEGA key; reuse a key to test idempotency).
			return require(script.Parent.CoreLoopMutationRain)._StrikeNowForQA(a, b)
		elseif verb == "RainPresent" then
			require(script.Parent.CoreLoopMutationRain)._SetPresentForQA(a)
			return a
		elseif verb == "RainStats" then
			local Rain = require(script.Parent.CoreLoopMutationRain)
			return {
				Stats = Rain.GetStats(),
				LastActive = if a then Rain._LastActiveForQA(a) else nil,
				Slots = if a then Rain._SlotsForQA(a) else nil,
			}
		elseif verb == "Trips" then
			local trips = require(script.Parent.CoreLoopTripTracker).GetTrips(a.UserId)
			return {
				Trips = trips,
				Active = require(script.Parent.CoreLoopTripTracker).Active(a),
				Reseats = botReseats,
			}
		elseif verb == "TripReset" then
			require(script.Parent.CoreLoopTripTracker).Reset(a.UserId)
			return true
		elseif verb == "SeatInCart" then
			-- Studio: sit the player in their own cart's driver seat (the bot then drives with real inputs).
			local CartService = require(script.Parent.CartService)
			local record = CartService:GetCartRecord(a)
			local cart = record and record.Model
			local seat = cart and cart:FindFirstChild("DriverSeat", true)
			local humanoid = a.Character and a.Character:FindFirstChildOfClass("Humanoid")
			if not (seat and seat:IsA("VehicleSeat") and humanoid) then
				return "NO_CART_OR_SEAT"
			end
			local root = a.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.Anchored = false
				root.CFrame = seat.CFrame + Vector3.new(0, 3, 0)
			end
			task.wait(0.2)
			seat:Sit(humanoid)
			task.wait(0.3)
			return if humanoid.SeatPart == seat then "SEATED" else "SIT_FAILED"
		elseif verb == "BotHome" then
			-- Where the bot drives to bank: the player's base pivot (published for the client bot).
			local PlayerBaseSystem = require(script.Parent.Parent.Systems.PlayerBaseSystem)
			local base = PlayerBaseSystem:GetBase(a)
			if not base then
				return "NO_BASE"
			end
			game:GetService("ReplicatedStorage")
				:SetAttribute("CoreLoopBotHome", base:GetPivot().Position)
			return base:GetPivot().Position
		elseif verb == "FullCartOverride" then
			if deps.Director then
				deps.Director._SetFullCartOverrideForQA(a == true)
			end
			return a == true
		elseif verb == "KoNear" then
			-- A7 Saved probe: stand 20 studs from the nearest awake member of this player's own herd and
			-- shoot it to sleep through the real validator. Returns its Saved attributes.
			local player: Player = a
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (root and root:IsA("BasePart") and humanoid) then
				return "NO_CHARACTER"
			end
			local launcher = player.Backpack:FindFirstChild("SleepLauncher")
			if launcher then
				humanoid:EquipTool(launcher)
			end
			local sim = sims[player]
			if sim then
				stopSim(sim)
			end
			local best, bestD = nil, math.huge
			for _, model in deps.Spawner.GetWorldModels() do
				local _, state = deps.Spawner.GetWorldRecord(model)
				local role = model:GetAttribute("CoreLoopRole")
				if
					state == "WorldAwake"
					and model:GetAttribute("CoreLoopOwnerUserId") == player.UserId
					and role ~= "Ambient"
					and role ~= nil
					and (b == nil or role == b)
				then
					local distance = (model:GetPivot().Position - root.Position).Magnitude
					if distance < bestD then
						best, bestD = model, distance
					end
				end
			end
			if not best then
				return "NO_OWN_TARGET"
			end
			local record = deps.Spawner.GetWorldRecord(best)
			local SleepSystem = require(script.Parent.Parent.Systems.BrainrotSleepSystem)
			root.Anchored = true
			for shot = 1, 5 do
				local target = best:GetPivot().Position
				root.CFrame = CFrame.lookAt(target + Vector3.new(0, 3, -20), target)
				local origin = root.Position + Vector3.new(0, 2.5, 0)
				local direction = (target + Vector3.new(0, 1.5, 0) - origin).Unit
				pcall(SleepSystem.HandleFireRequest, player, {
					CameraOrigin = origin,
					CameraDirection = direction,
					CrosshairDirection = direction,
					ShotMode = "ASSIST_LOCK",
					LockedTargetId = record.ItemId,
					LockedTargetKind = "Brainrot",
					RequestId = math.floor(os.clock() * 1000) + shot,
				})
				task.wait(0.15)
				local _, state = deps.Spawner.GetWorldRecord(best)
				if state == "WorldSleeping" then
					break
				end
				task.wait(0.7)
			end
			root.Anchored = false
			local _, finalState = deps.Spawner.GetWorldRecord(best)
			return {
				Role = best:GetAttribute("CoreLoopRole"),
				State = finalState,
				SavedOwnerUserId = best:GetAttribute("SavedOwnerUserId"),
				SavedSecondsLeft = (best:GetAttribute("SavedUntil") or 0)
					- Workspace:GetServerTimeNow(),
				SleepUntil = best:GetAttribute("BrainrotSleepUntil"),
			}
		elseif verb == "ShootForeignStar" then
			-- B-3: fire one validated shot at the nearest Star owned by someone else (e.g. a virtual hunter).
			local player: Player = a
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (root and root:IsA("BasePart") and humanoid) then
				return "NO_CHARACTER"
			end
			local launcher = player.Backpack:FindFirstChild("SleepLauncher")
			if launcher then
				humanoid:EquipTool(launcher)
			end
			local best, bestD = nil, math.huge
			for _, model in deps.Spawner.GetWorldModels() do
				local owner = model:GetAttribute("StarOwnerUserId")
				local _, state = deps.Spawner.GetWorldRecord(model)
				if
					model:GetAttribute("CoreLoopStar") == true
					and owner ~= player.UserId
					and state == "WorldAwake"
				then
					local distance = (model:GetPivot().Position - root.Position).Magnitude
					if distance < bestD then
						best, bestD = model, distance
					end
				end
			end
			if not best then
				return "NO_FOREIGN_STAR"
			end
			local target = best:GetPivot().Position
			root.Anchored = true
			root.CFrame = CFrame.lookAt(target + Vector3.new(0, 4, -30), target)
			task.wait(0.2)
			local exclusiveLeft = (best:GetAttribute("StarExclusiveUntil") or 0)
				- Workspace:GetServerTimeNow()
			local record = deps.Spawner.GetWorldRecord(best)
			local before = deps.Spawner.GetPhase12State(record)
			local hpBefore = before and before.RemainingHp
			local origin = root.Position + Vector3.new(0, 2.5, 0)
			local direction = (target + Vector3.new(0, 1.5, 0) - origin).Unit
			local SleepSystem = require(script.Parent.Parent.Systems.BrainrotSleepSystem)
			local ok, shot, reason = pcall(SleepSystem.HandleFireRequest, player, {
				CameraOrigin = origin,
				CameraDirection = direction,
				CrosshairDirection = direction,
				ShotMode = "ASSIST_LOCK",
				LockedTargetId = record.ItemId,
				LockedTargetKind = "Brainrot",
				RequestId = math.floor(os.clock() * 1000) + 7,
			})
			local after = deps.Spawner.GetPhase12State(record)
			root.Anchored = false
			return {
				ExclusiveSecondsLeft = exclusiveLeft,
				Owner = best:GetAttribute("StarOwnerUserId"),
				Accepted = ok and shot ~= nil,
				Reason = if ok then reason else tostring(shot),
				HpBefore = hpBefore,
				HpAfter = after and after.RemainingHp,
			}
		elseif verb == "Sample" then
			local runtime = Workspace:FindFirstChild("Runtime")
			local stats = if deps.Director then deps.Director.GetStats() else nil
			return {
				At = os.clock(),
				WorkspaceDescendants = #Workspace:GetDescendants(),
				RuntimeDescendants = if runtime then #runtime:GetDescendants() else 0,
				Wild = deps.Spawner.GetWildCount(),
				Tracked = if stats then stats.Tracked else nil,
				FrameMsPeak = if stats then stats.FrameMsPeak else nil,
				TickMsAverage = if stats then stats.TickMsAverage else nil,
				Virtuals = #virtuals,
			}
		end
		return "NOT_BUILT"
	end
	hook.Parent = ServerStorage
	-- Trip bot support: while ReplicatedStorage.CoreLoopTripBot is on, re-seat a player who left the cart.
	task.spawn(function()
		while true do
			task.wait(2)
			if game:GetService("ReplicatedStorage"):GetAttribute("CoreLoopTripBot") == true then
				for _, player in Players:GetPlayers() do
					local humanoid = player.Character
						and player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 and humanoid.SeatPart == nil then
						botReseats += 1
						pcall(hook.Invoke, hook, "SeatInCart", player)
					end
				end
			end
		end
	end)
end

return Service
