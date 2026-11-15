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
-- Playtest Fixes Part D (flag-gated): one SHARED bay. Any number of carts train at once (they sit in the
-- TrainingCarts collision group, which does not collide with itself), XP ticks per player exactly as
-- before, there is no "Bay busy" and no idle ejection. With the flag off everything below is unchanged.
local PlaytestFlags = require(RS.Shared.Config.PlaytestFixesFlags)
local PlaytestFixes = require(RS.Shared.Config.PlaytestFixes)
local PhysicsService = game:GetService("PhysicsService")
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
local GROUP = PlaytestFixes.TrainPlace.CollisionGroup
local grouped: { [Model]: { [BasePart]: string } } = setmetatable({}, { __mode = "k" }) :: any
local trainers: { [Bay]: { [Player]: boolean } } = {}

local function shared(): boolean
	return PlaytestFlags.Part("TrainPlace")
end
local started = false
local deps: any = nil

-- Pure: is a world point inside the (lenient) roller trigger box?
-- The trigger's local X runs along the rollers. A full-size cart's wheel track (~8 studs) is wider
-- than the rollers and carts slide along them, so X gets +6 studs of slack and Z +4 (min 10 x 8).
function Service.InsideTrigger(trigger: CFrame, size: Vector3, point: Vector3): boolean
	local alongRollers = math.max(size.X + 6, 10)
	local acrossRollers = math.max(size.Z + 4, 8)
	local local3 = trigger:PointToObjectSpace(point)
	return math.abs(local3.X) <= alongRollers / 2
		and math.abs(local3.Z) <= acrossRollers / 2
		and math.abs(local3.Y) <= size.Y / 2
end

-- Pure: does a bay hold any number of trainers (shared) or one (legacy)?
function Service.SharedBay(): boolean
	return shared()
end

-- Groups are registered when the stall binds (before CollisionService has set the Carts rules), and
-- CONFIGURED later, on the first Training tick or TrainPlace, once every other group's rules exist.
local ROLLER_GROUP = "TrainingRollers"
local function register(name: string)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end

local configured = false
-- TrainingCarts copies the Carts rules (except itself); TrainingRollers copies Default's, except that
-- plain Carts pass over the rollers and TrainingCarts ride on them.
local function configureGroups()
	if configured then
		return
	end
	configured = true
	for _, name in { "Carts", GROUP, ROLLER_GROUP } do
		register(name)
	end
	for _, info in PhysicsService:GetRegisteredCollisionGroups() do
		local other = info.name
		if other ~= GROUP then
			PhysicsService:CollisionGroupSetCollidable(
				GROUP,
				other,
				PhysicsService:CollisionGroupsAreCollidable("Carts", other)
			)
		end
		if other ~= ROLLER_GROUP then
			PhysicsService:CollisionGroupSetCollidable(
				ROLLER_GROUP,
				other,
				PhysicsService:CollisionGroupsAreCollidable("Default", other)
			)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(ROLLER_GROUP, "Carts", false)
	PhysicsService:CollisionGroupSetCollidable(ROLLER_GROUP, GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(ROLLER_GROUP, ROLLER_GROUP, true)
end

function Service.ConfigureGroups()
	configureGroups()
end

-- A cart joins the shared bay: its Carts-group parts move to TrainingCarts (restored on leave).
function Service.JoinGroup(cart: Model)
	if grouped[cart] then
		return
	end
	configureGroups()
	-- Flag first: CartAssemblyValidator accepts TrainingCarts only on a flagged cart.
	cart:SetAttribute("PlaytestTrainingBay", true)
	local saved = {}
	for _, d in cart:GetDescendants() do
		if d:IsA("BasePart") and d.CollisionGroup == "Carts" then
			saved[d] = d.CollisionGroup
			d.CollisionGroup = GROUP
		end
	end
	grouped[cart] = saved
end

function Service.LeaveGroup(cart: Model)
	local saved = grouped[cart]
	if not saved then
		return
	end
	grouped[cart] = nil
	for part, group in saved do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	cart:SetAttribute("PlaytestTrainingBay", nil)
end

function Service.InGroup(cart: Model): boolean
	return grouped[cart] ~= nil
end

-- The Training bay nearest a point, with its prompt distance (for TrainPlace validation).
function Service.NearestBay(position: Vector3): (any, number)
	local best, bestDistance = nil, math.huge
	for _, bay in bays do
		local parent = bay.prompt.Parent
		local at = if parent and parent:IsA("Attachment")
			then parent.WorldPosition
			elseif parent and parent:IsA("BasePart") then parent.Position
			else bay.trigger.Position
		local d = (Vector3.new(at.X, position.Y, at.Z) - position).Magnitude
		if d < bestDistance then
			best, bestDistance = bay, d
		end
	end
	return best, bestDistance
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
	player:SetAttribute(
		"TrainingXpToNext",
		if p.TrainingLevel < Training.MaxLevel then Training.XpToNext(p.TrainingLevel) else 0
	)
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

-- One XP tick for one trainer (unchanged rules; shared from the legacy single-occupant path).
local function tickTrainer(player: Player)
	local Profiles = deps_().Profiles
	local data = Profiles:GetReadableData(player)
	if
		not data
		or type(data.Phase13) ~= "table"
		or type(data.Phase13.TrainingLevel) ~= "number"
	then
		return
	end
	local hasPass = CommerceRules.HasEntitlement(data, Training.PassId)
	local xp = Training.XpPerTick(data.Phase13.SelectedRoller, hasPass)
	local gained = 0
	local level = data.Phase13.TrainingLevel
	local result = Profiles:CommitMutation(player, function(current)
		local ok, out = Rules.ApplyTrainingTick(current, xp)
		if ok then
			gained, level = out.levels, out.level
		end
		return ok, out
	end)
	if type(result) == "table" and result.ok == false then
		return
	end
	publish(player, true)
	player:SetAttribute("TrainingXpGain", xp)
	if gained > 0 then
		deps_().Carts:ReconcileOwnerPerformance(player.UserId, "TrainingLevel")
		local remotes = RS:FindFirstChild("Remotes")
		local event = remotes and remotes:FindFirstChild("CampReworkEvent")
		if event and event:IsA("RemoteEvent") then
			event:FireClient(player, { kind = "TrainingLevelUp", level = level, gained = gained })
		end
	end
end

-- Shared bay (Playtest Fixes D4): every eligible cart on the rollers trains; nobody is ejected for
-- being idle; carts leave the TrainingCarts group once they are off the trigger volume.
local function tickSharedBay(bay: Bay)
	local Profiles = deps_().Profiles
	local current = trainers[bay] or {}
	local now = {}
	for _, player in Players:GetPlayers() do
		local cart = deps_().Carts:GetCart(player)
		-- Driving on counts too: a cart with a wheel on the deck joins the non-colliding group.
		if cart and cart.Parent and not grouped[cart] then
			for _, d in cart:GetDescendants() do
				if
					d:IsA("BasePart")
					and string.sub(d.Name, 1, 12) == "WheelContact"
					and Service.InsideTrigger(bay.trigger.CFrame, bay.trigger.Size, d.Position)
				then
					Service.JoinGroup(cart)
					break
				end
			end
		end
		if Profiles:GetStatus(player) == "Ready" and onRollers(player, bay) then
			now[player] = true
		end
	end
	for player in current do
		if not now[player] and player.Parent == Players then
			publish(player, false)
		end
	end
	trainers[bay] = now
	local count = 0
	for player in now do
		count += 1
		tickTrainer(player)
	end
	bay.prompt:SetAttribute("BayOccupantUserId", 0)
	bay.prompt:SetAttribute("BayTrainingCount", count)
end

-- A grouped cart stays in TrainingCarts while any wheel contact is inside any bay's trigger.
local function releaseDepartedCarts()
	for cart in grouped do
		local inside = false
		if cart.Parent then
			for _, d in cart:GetDescendants() do
				if d:IsA("BasePart") and string.sub(d.Name, 1, 12) == "WheelContact" then
					for _, bay in bays do
						if
							Service.InsideTrigger(bay.trigger.CFrame, bay.trigger.Size, d.Position)
						then
							inside = true
						end
					end
				end
			end
		end
		if not inside then
			Service.LeaveGroup(cart)
		end
	end
end

local function tickBay(bay: Bay, now: number)
	if shared() then
		tickSharedBay(bay)
		return
	end
	local Profiles = deps_().Profiles
	local occupant = bay.occupant
	if occupant and (occupant.Parent ~= Players or not onRollers(occupant, bay)) then
		publish(occupant, false)
		occupant = nil
	end
	if not occupant then
		for _, player in Players:GetPlayers() do
			if
				Profiles:GetStatus(player) == "Ready"
				and player:GetAttribute("TrainingAfk") ~= true
				and onRollers(player, bay)
			then
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
	if
		not data
		or type(data.Phase13) ~= "table"
		or type(data.Phase13.TrainingLevel) ~= "number"
	then
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

-- Playtest Fixes D3: the roller deck, rollers and ramp count as cart ground, so the server can
-- relocate a cart onto the rollers (CartLocalPlacement's drivable-support rule). Runtime only.
-- World-space top of a part, whatever its rotation (cylinder rollers lie on their side).
local function topOf(part: BasePart): number
	local cf, size = part.CFrame, part.Size
	return part.Position.Y
		+ (
				math.abs(cf.RightVector.Y) * size.X
				+ math.abs(cf.UpVector.Y) * size.Y
				+ math.abs(cf.LookVector.Y) * size.Z
			)
			/ 2
end

function Service.MarkDrivableDeck(stall: Model): number
	local slots = stall:FindFirstChild("CampSlots")
	local trigger = slots and slots:FindFirstChild("RollerTrigger")
	if not trigger or not trigger:IsA("BasePart") then
		return 0
	end
	-- Every collidable stall piece whose top sits at deck level (deck, rollers, bands, pit rails, ramp).
	local deckTop = trigger.Position.Y - trigger.Size.Y / 2 + 0.6
	local marked = 0
	for _, d in stall:GetDescendants() do
		if
			d:IsA("BasePart")
			and d.CanCollide
			and d.Anchored
			and (topOf(d) <= deckTop or d.Name == "Ramp")
		then
			d:SetAttribute("CartDrivableGround", true)
			marked += 1
		end
	end
	-- Raised roller pieces (rollers, bands, pit rails: above the flat deck) join TrainingRollers. Carts
	-- in the bay (TrainingCarts) still ride on them; the placement proof (which queries as "Carts")
	-- sees the flat deck, so the server can set a cart down on the rollers.
	local flat = math.huge
	for _, d in stall:GetDescendants() do
		if
			d:IsA("BasePart")
			and d:GetAttribute("CartDrivableGround") == true
			and d.Name ~= "Ramp"
		then
			flat = math.min(flat, topOf(d))
		end
	end
	register(ROLLER_GROUP)
	for _, d in stall:GetDescendants() do
		if
			d:IsA("BasePart")
			and d:GetAttribute("CartDrivableGround") == true
			and d.Name ~= "Ramp"
			and topOf(d) > flat + 0.05
			and Service.InsideTrigger(
				trigger.CFrame,
				trigger.Size + Vector3.new(0, 20, 0),
				d.Position
			)
		then
			if d:GetAttribute("PlaytestOriginalCollisionGroup") == nil then
				d:SetAttribute("PlaytestOriginalCollisionGroup", d.CollisionGroup)
			end
			d.CollisionGroup = ROLLER_GROUP
		end
	end
	return marked
end

-- Highest deck-level surface inside a bay's trigger box (where a placed cart must clear).
function Service.DeckTop(bay: any): number
	local trigger = bay.trigger :: BasePart
	local top = -math.huge
	for _, d in bay.stall:GetDescendants() do
		if
			d:IsA("BasePart")
			and d:GetAttribute("CartDrivableGround") == true
			and d.Name ~= "Ramp"
		then
			if
				Service.InsideTrigger(
					trigger.CFrame,
					trigger.Size + Vector3.new(0, 20, 0),
					d.Position
				)
			then
				top = math.max(top, topOf(d))
			end
		end
	end
	return top
end

function Service:BindPrompt(prompt: ProximityPrompt, stall: Model)
	prompt:SetAttribute("CampTrainingPrompt", true)
	prompt:SetAttribute("BayOccupantUserId", 0)
	local slots = stall:FindFirstChild("CampSlots")
	local trigger = slots and slots:FindFirstChild("RollerTrigger")
	if trigger and trigger:IsA("BasePart") then
		table.insert(bays, { stall = stall, trigger = trigger, prompt = prompt, occupant = nil })
	end
	if shared() then
		-- Presentation/placement aid only: never allowed to stop the stall (or bootstrap) binding.
		local ok, err = pcall(Service.MarkDrivableDeck, stall)
		if not ok then
			warn("[TrainingService] deck marking failed:", err)
		end
	end
	self:Start()
end

-- Roller purchase/selection (critical transaction) — called from Phase13RuntimeService.
function Service:PurchaseRoller(
	player: Player,
	payload: any,
	validate: (boolean) -> (boolean, string?)
): any
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
	return deps_().Transactions:CommitCritical(
		player,
		payload.operationId,
		"TrainingRoller",
		function(data)
			return Rules.ApplyRollerPurchase(data, payload.rollerId)
		end,
		{
			validate = function()
				return validate(true)
			end,
			onConfirmed = function()
				publish(player, nil)
				return true
			end,
		}
	)
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
		xpToNext = if p.TrainingLevel < Training.MaxLevel
			then Training.XpToNext(p.TrainingLevel)
			else 0,
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
			if shared() then
				pcall(configureGroups)
				local ok, err = pcall(releaseDepartedCarts)
				if not ok then
					warn("[TrainingService] group release failed:", err)
				end
			end
		end
	end)
end

return Service
