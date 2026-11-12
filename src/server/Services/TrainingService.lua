--!strict
-- Camp Rework, Part E (owner-approved 12 Nov 2026): Training replaces the cart Speed upgrades.
-- Behind TrainingV1Enabled (Config/CampReworkFlags). Server-authoritative:
--   * A player trains while their OWN driven cart sits on the Training stall rollers: both
--     WheelContact hubs inside the roller trigger box, the cart (nearly) stationary, the owner seated.
--   * 1 Hz: XP += 1 × roller multiplier × 2 (2× Training pass). Levels follow Config/Training.
--   * One bay per stall: the first eligible cart holds it; the prompt shows "Bay busy" to others.
--   * AFK: 10 minutes without client input frees the bay (driver unseated, cart moved off the rollers).
-- XP ticks use the profile's ordinary mutation path; roller purchases use the critical transaction.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local CampFlags = require(RS.Shared.Config.CampReworkFlags)
local Training = require(RS.Shared.Config.Training)
local Rules = require(RS.Shared.Utility.Phase13Rules)
local CommerceRules = require(RS.Shared.Utility.Phase13CommerceRules)

local Service = {}

type Bay = {
	stall: Model,
	trigger: BasePart,
	prompt: ProximityPrompt,
	occupant: Player?,
}

local bays: { Bay } = {}
local lastInput: { [Player]: number } = {}
local started = false
local deps: any = nil

-- Pure: is a world point inside the (lenient) roller trigger box?
-- The trigger's local X runs along the rollers. A full-size cart's wheel track (~8 studs) is wider
-- than the rollers and carts slide along them, so X gets +6 studs of slack and Z +4 (min 10 x 8).
function Service.InsideTrigger(trigger: CFrame, size: Vector3, point: Vector3): boolean
	local alongRollers = math.max(size.X + 6, 10)
	local acrossRollers = math.max(size.Z + 4, 8)
	local local3 = trigger:PointToObjectSpace(point)
	return math.abs(local3.X) <= alongRollers / 2 and math.abs(local3.Z) <= acrossRollers / 2
		and math.abs(local3.Y) <= size.Y / 2
end

local function deps_()
	if deps then
		return deps
	end
	deps = {
		Profiles = require(script.Parent.PlayerDataService),
		Transactions = require(script.Parent.Phase13Service),
		Carts = require(script.Parent.CartService),
	}
	return deps
end

local function publish(player: Player, active: boolean?)
	local data = deps_().Profiles:GetReadableData(player)
	local p = data and data.Phase13
	if type(p) ~= "table" or type(p.TrainingLevel) ~= "number" then
		return
	end
	player:SetAttribute("TrainingLevel", p.TrainingLevel)
	player:SetAttribute("TrainingXp", p.TrainingXp)
	player:SetAttribute("TrainingXpToNext", if p.TrainingLevel < Training.MaxLevel then Training.XpToNext(p.TrainingLevel) else 0)
	player:SetAttribute("TrainingRoller", p.SelectedRoller)
	if active ~= nil then
		player:SetAttribute("TrainingActive", active)
	end
end

-- Is this player's own cart sitting still on this bay's rollers with them in the driver seat?
local function onRollers(player: Player, bay: Bay): boolean
	local cart = deps_().Carts:GetCart(player)
	if not cart or not cart.Parent then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seated = false
	for _, d in cart:GetDescendants() do
		if (d:IsA("VehicleSeat") or d:IsA("Seat")) and d.Name == "DriverSeat" then
			seated = humanoid ~= nil and d.Occupant == humanoid
			break
		end
	end
	if not seated then
		return false
	end
	local contacts = 0
	local trigger = bay.trigger
	for _, d in cart:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 12) == "WheelContact" then
			if not Service.InsideTrigger(trigger.CFrame, trigger.Size, d.Position) then
				return false
			end
			contacts += 1
		end
	end
	if contacts == 0 then
		return false
	end
	local root = cart.PrimaryPart
	return root ~= nil and root.AssemblyLinearVelocity.Magnitude <= Training.StationarySpeed
end

local function eject(player: Player, bay: Bay)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
		humanoid.Jump = true
	end
	local cart = deps_().Carts:GetCart(player)
	if cart then
		-- off the front of the ramp, facing away from the stall
		local front = bay.stall:GetPivot()
		task.delay(0.3, function()
			if cart.Parent then
				cart:PivotTo(front * CFrame.new(0, 3, -16))
			end
		end)
	end
	player:SetAttribute("TrainingAfk", true)
end

local function tickBay(bay: Bay, now: number)
	local Profiles = deps_().Profiles
	local occupant = bay.occupant
	if occupant and (occupant.Parent ~= Players or not onRollers(occupant, bay)) then
		publish(occupant, false)
		occupant = nil
	end
	if not occupant then
		for _, player in Players:GetPlayers() do
			if Profiles:GetStatus(player) == "Ready" and player:GetAttribute("TrainingAfk") ~= true and onRollers(player, bay) then
				occupant = player
				lastInput[player] = lastInput[player] or now
				break
			end
		end
	end
	bay.occupant = occupant
	bay.prompt:SetAttribute("BayOccupantUserId", if occupant then occupant.UserId else 0)
	if not occupant then
		return
	end
	if now - (lastInput[occupant] or now) >= Training.AfkKickSeconds then
		bay.occupant = nil
		bay.prompt:SetAttribute("BayOccupantUserId", 0)
		publish(occupant, false)
		eject(occupant, bay)
		return
	end
	local data = Profiles:GetReadableData(occupant)
	if not data or type(data.Phase13) ~= "table" or type(data.Phase13.TrainingLevel) ~= "number" then
		return
	end
	local hasPass = CommerceRules.HasEntitlement(data, Training.PassId)
	local xp = Training.XpPerTick(data.Phase13.SelectedRoller, hasPass)
	local gained = 0
	local level = data.Phase13.TrainingLevel
	local result = Profiles:CommitMutation(occupant, function(current)
		local ok, out = Rules.ApplyTrainingTick(current, xp)
		if ok then
			gained, level = out.levels, out.level
		end
		return ok, out
	end)
	if type(result) == "table" and result.ok == false then
		return
	end
	publish(occupant, true)
	if gained > 0 then
		deps_().Carts:ReconcileOwnerPerformance(occupant.UserId, "TrainingLevel")
		local remotes = RS:FindFirstChild("Remotes")
		local event = remotes and remotes:FindFirstChild("CampReworkEvent")
		if event and event:IsA("RemoteEvent") then
			event:FireClient(occupant, { kind = "TrainingLevelUp", level = level, gained = gained })
		end
	end
end

function Service:BindPrompt(prompt: ProximityPrompt, stall: Model)
	prompt:SetAttribute("CampTrainingPrompt", true)
	prompt:SetAttribute("BayOccupantUserId", 0)
	local slots = stall:FindFirstChild("CampSlots")
	local trigger = slots and slots:FindFirstChild("RollerTrigger")
	if trigger and trigger:IsA("BasePart") then
		table.insert(bays, { stall = stall, trigger = trigger, prompt = prompt, occupant = nil })
	end
	self:Start()
end

-- Roller purchase/selection (critical transaction) — called from Phase13RuntimeService.
function Service:PurchaseRoller(player: Player, payload: any, validate: (boolean) -> (boolean, string?)): any
	if not CampFlags.Training() then
		return { ok = false, code = "UNAVAILABLE" }
	end
	if type(payload.rollerId) ~= "string" or Training.RollersById[payload.rollerId] == nil then
		return { ok = false, code = "INVALID_REQUEST" }
	end
	local allowed, why = validate(false)
	if not allowed then
		return { ok = false, code = why or "SHOP_REQUIRED" }
	end
	return deps_().Transactions:CommitCritical(player, payload.operationId, "TrainingRoller", function(data)
		return Rules.ApplyRollerPurchase(data, payload.rollerId)
	end, {
		validate = function()
			return validate(true)
		end,
		onConfirmed = function()
			publish(player, nil)
			return true
		end,
	})
end

-- Snapshot block for the Training menu (client display only).
function Service.Snapshot(data: any): any
	local p = data and data.Phase13
	if not CampFlags.Training() or type(p) ~= "table" or type(p.TrainingLevel) ~= "number" then
		return nil
	end
	local rollers = {}
	for _, roller in Training.Rollers do
		table.insert(rollers, {
			id = roller.id,
			name = roller.name,
			multiplier = roller.multiplier,
			price = roller.price,
			owned = p.OwnedRollers[roller.id] == true,
			selected = p.SelectedRoller == roller.id,
		})
	end
	return {
		level = p.TrainingLevel,
		maxLevel = Training.MaxLevel,
		xp = p.TrainingXp,
		xpToNext = if p.TrainingLevel < Training.MaxLevel then Training.XpToNext(p.TrainingLevel) else 0,
		speedMultiplier = Training.SpeedMultiplier(p.TrainingLevel),
		rollers = rollers,
		pass = CommerceRules.HasEntitlement(data, Training.PassId),
	}
end

function Service:Start()
	if started or not CampFlags.Training() then
		return
	end
	started = true
	local remotes = RS:WaitForChild("Remotes")
	local input = remotes:FindFirstChild("TrainingInput") or Instance.new("RemoteEvent")
	input.Name = "TrainingInput"
	input.Parent = remotes
	local inputEvent = input :: RemoteEvent
	inputEvent.OnServerEvent:Connect(function(player)
		-- rate-limited by the client to one ping per 20 s of real input; the server only stores a time
		lastInput[player] = os.clock()
		if player:GetAttribute("TrainingAfk") == true then
			player:SetAttribute("TrainingAfk", nil)
		end
	end)
	deps_().Profiles:SubscribeReady(function(player)
		publish(player, false)
	end)
	for _, player in Players:GetPlayers() do
		publish(player, false)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastInput[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Training.TickSeconds)
			local now = os.clock()
			for _, bay in bays do
				local ok, err = pcall(tickBay, bay, now)
				if not ok then
					warn("[TrainingService] tick failed:", err)
				end
			end
		end
	end)
end

return Service
