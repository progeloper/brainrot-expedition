--!strict
-- Drive-and-Hunt (owner prompt v1.0, 12 Nov 2026), Parts A and B.
--   Gate launch   walking out of camp seats the player in their own cart, outside.
--   HOP OUT       the driver steps out beside the cart (the only way out besides death/reset).
--   CART          the player's parked cart pops in beside them and they are seated.
--   LOAD & GO     same, but the carried brainrot is loaded first through the existing cargo path.
-- Everything here is decided on the server. The cart is only ever MOVED (never created) through
-- CartService:RelocateParkedCart, seating goes through CartOccupantService, and loading through
-- BrainrotInteractionSystem.TryPlaceInCargo. Clients send one small request and play effects.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.DriveAndHunt)
local Flags = require(Shared.Config.DriveAndHuntFlags)
local CampExits = require(Shared.Config.CampExits)
local RegionFootprints = require(Shared.Config.RegionFootprints)
local RemoteNames = require(Shared.Constants.RemoteNames)
local Rules = require(Shared.Utility.DriveAndHuntRules)
local StormGeometry = require(Shared.Utility.StormGeometry)
local CartGeometry = require(Shared.Utility.CartGeometry)
-- Playtest Fixes Part D (flag-gated): "Train!" puts the player's own cart on the Training rollers.
local PlaytestFlags = require(Shared.Config.PlaytestFixesFlags)
local CampFlags = require(Shared.Config.CampReworkFlags)
local TrainPlaceRules = require(Shared.Utility.TrainPlaceRules)
local PlaytestFixes = require(Shared.Config.PlaytestFixes)

type Dependencies = {
	CartService: any,
	Occupants: any,
	Cargo: any,
	Interaction: any,
	Combat: any,
	World: any,
	Placement: any,
	GetBase: (Player) -> Model?,
	AccessReader: ((Player, string) -> boolean)?,
	Feedback: ((Player, string) -> ())?,
}

type PlayerState = {
	gate: Rules.GateState,
	seatedSince: number,
	lastCallAt: number,
	lastRequestAt: number,
	lastPulseAt: number,
	busy: boolean, -- client-reported cinematic/dialog; only ever restricts this player
	working: boolean,
}

local REGION_BY_FOOTPRINT: { [string]: string } = {
	Camp = "REGION_CAMP",
	Forest = "REGION_FOREST",
	Beach = "REGION_BEACH",
	Swamp = "REGION_SWAMP",
	Jungle = "REGION_JUNGLE",
	Arctic = "REGION_ARCTIC",
	Volcano = "REGION_VOLCANO",
	GlitchZone = "REGION_GLITCH",
}

local Service = {}
local deps: Dependencies? = nil
local connections: { RBXScriptConnection } = {}
local states: { [Player]: PlayerState } = setmetatable({}, { __mode = "k" }) :: any
local requestRemote: RemoteEvent? = nil
local fxRemote: RemoteEvent? = nil
local campBounds = Rules.BoundsOf(RegionFootprints.Camp)
local gateElapsed, slowElapsed = 0, 0
local stats = {
	Launches = 0,
	LaunchBlocked = 0,
	Calls = 0,
	CallNoRoom = 0,
	HopOuts = 0,
	LoadAndGo = 0,
	LoadAndGoFailed = 0,
	BoundsQueriesPeak = 0,
	Pulses = 0,
	Scoops = 0,
	LastLaunchSeconds = 0,
	LastReason = "",
}

local function now(): number
	return os.clock()
end

local function stateFor(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = {
			gate = Rules.NewGateState(),
			seatedSince = -math.huge,
			lastCallAt = -math.huge,
			lastRequestAt = -math.huge,
			lastPulseAt = -math.huge,
			busy = false,
			working = false,
		}
		states[player] = state
	end
	return state
end

local function body(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

local function fire(player: Player, payload: any)
	local remote = fxRemote
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function tell(player: Player, text: string)
	local d = deps
	if d and d.Feedback then
		pcall(d.Feedback, player, text)
	end
end

local function regionAt(position: Vector3): string?
	for key, regionId in REGION_BY_FOOTPRINT do
		local points = (RegionFootprints :: any)[key]
		if points and StormGeometry.Contains(points, position.X, position.Z) then
			return regionId
		end
	end
	return nil
end

-- Camp is always open; any other region needs the player's own access (never Storm-locked).
local function allowedAt(player: Player, position: Vector3): boolean
	local regionId = regionAt(position)
	if regionId == nil then
		return false
	end
	if regionId == "REGION_CAMP" then
		return true
	end
	local d = deps :: Dependencies
	if d.AccessReader then
		local ok, allowed = pcall(d.AccessReader, player, regionId)
		return ok and allowed == true
	end
	return true
end

local function inAnotherBase(player: Player, position: Vector3): boolean
	local d = deps :: Dependencies
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local base = d.GetBase(other)
			if base then
				local frame, size = base:GetBoundingBox()
				local point = frame:PointToObjectSpace(position)
				if
					math.abs(point.X) <= size.X * 0.5 + 6
					and math.abs(point.Z) <= size.Z * 0.5 + 6
				then
					return true
				end
			end
		end
	end
	return false
end

local function isLiveObstacle(part: BasePart): boolean
	-- Other carts, brainrots and villagers live under Workspace.Runtime; players are characters.
	local runtime = Workspace:FindFirstChild("Runtime")
	if runtime and part:IsDescendantOf(runtime) then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

type Query = { count: number }

-- The cart's full visual envelope in its pivot space. Wheels, fenders and flair reach
-- past the collider plate and still push characters, so "beside the cart" and "is the
-- lane occupied" are measured from what the player sees, not from the collider alone.
local function visualExtents(cart: Model): (Vector3, Vector3)
	local frame, size = cart:GetBoundingBox()
	local centre = cart:GetPivot():PointToObjectSpace(frame.Position)
	return centre - size / 2, centre + size / 2
end

-- Ground under a point: a walkable, non-water surface within the slope limit.
local function groundAt(
	position: Vector3,
	ignore: { Instance },
	maximumSlope: number?
): (Vector3?, string?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	params.IgnoreWater = false
	local hit = Workspace:Raycast(position + Vector3.yAxis * 40, -Vector3.yAxis * 120, params)
	if not hit then
		return nil, "NoGround"
	end
	if hit.Material == Enum.Material.Water then
		return nil, "Water"
	end
	if maximumSlope then
		local slope = math.deg(math.acos(math.clamp(hit.Normal.Y, -1, 1)))
		if slope > maximumSlope then
			return nil, "Slope"
		end
	end
	return hit.Position, nil
end

-- The exact frame the cart would take at a ground point, or the reason it cannot.
local function cartFrameAt(
	player: Player,
	cart: Model,
	measure: any,
	position: Vector3,
	heading: Vector3,
	query: Query
): (CFrame?, string?)
	if not allowedAt(player, position) then
		return nil, "RegionLocked"
	end
	if inAnotherBase(player, position) then
		return nil, "OtherBase"
	end
	local ignore: { Instance } = { cart }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local ground, reason = groundAt(position, ignore, Config.Lanes.MaxSlopeDegrees)
	if not ground then
		return nil, reason
	end
	local frame = CFrame.lookAt(ground, ground + heading, Vector3.yAxis)
		* CartGeometry.SpawnOffset(cart)
	-- Corners must also be allowed (never straddle a locked edge).
	for _, x in { measure.minimum.X, measure.maximum.X } do
		for _, z in { measure.minimum.Z, measure.maximum.Z } do
			if not allowedAt(player, frame:PointToWorldSpace(Vector3.new(x, 0, z))) then
				return nil, "RegionLocked"
			end
		end
	end
	-- Players, other carts, villagers and brainrots block the lane even where their parts
	-- do not collide with the cart group. Static world clearance is proved by the executor.
	if query.count >= Config.Call.MaxBoundsQueries then
		return nil, "QueryBudget"
	end
	query.count += 1
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	local margin = Vector3.one * Config.Lanes.ClearMargin * 2
	local low, high = visualExtents(cart)
	for _, part in
		Workspace:GetPartBoundsInBox(
			frame * CFrame.new((low + high) / 2),
			high - low + margin,
			overlap
		)
	do
		if isLiveObstacle(part) then
			return nil, "Occupied:" .. part.Name
		end
	end
	return frame, nil
end

-- Tries each world point in order and moves the cart to the first one that is proved clear.
local function placeCart(
	player: Player,
	cart: Model,
	points: { { position: Vector3, heading: Vector3 } }
): (boolean, string?)
	local d = deps :: Dependencies
	local measure = d.Placement.Measure(cart)
	if not measure then
		return false, "CartUnavailable"
	end
	local query: Query = { count = 0 }
	local lastReason = "NoCandidate"
	for _, point in points do
		local frame, reason =
			cartFrameAt(player, cart, measure, point.position, point.heading, query)
		if frame then
			local moved, moveReason = d.CartService:RelocateParkedCart(player, cart, frame)
			if moved then
				stats.BoundsQueriesPeak = math.max(stats.BoundsQueriesPeak, query.count)
				return true, nil
			end
			lastReason = tostring(moveReason)
		else
			lastReason = tostring(reason)
		end
	end
	stats.BoundsQueriesPeak = math.max(stats.BoundsQueriesPeak, query.count)
	return false, lastReason
end

local function ownParkedCart(player: Player): (Model?, string?)
	local d = deps :: Dependencies
	local cart = d.CartService:GetCart(player)
	if not cart or cart.Parent == nil then
		return nil, "NoCart"
	end
	if d.Occupants:GetDriver(cart) ~= nil or #d.Occupants:GetOccupants(cart) > 0 then
		return nil, "CartOccupied"
	end
	return cart, nil
end

local function flairColor(cart: Model): Color3?
	local value = cart:GetAttribute("FlairPrimaryColor")
	return if typeof(value) == "Color3" then value else nil
end

local function broadcastPuff(position: Vector3, cart: Model)
	local remote = fxRemote
	if not remote then
		return
	end
	for _, other in Players:GetPlayers() do
		local _, _, root = body(other)
		if root and (root.Position - position).Magnitude <= Config.Fx.BystanderRadius then
			remote:FireClient(other, { kind = "Puff", at = position, color = flairColor(cart) })
		end
	end
end

local function seatAfterMove(
	player: Player,
	cart: Model,
	state: PlayerState,
	kind: string,
	from: Vector3?
): (boolean, string?)
	local d = deps :: Dependencies
	local seated, reason = d.Occupants:SeatOwner(player, cart)
	if not seated then
		return false, reason
	end
	local at = now()
	state.seatedSince = at
	Rules.NoteMoved(state.gate, at)
	if from then
		broadcastPuff(from, cart)
	end
	broadcastPuff(cart:GetPivot().Position, cart)
	fire(player, { kind = kind, cart = cart, at = cart:GetPivot().Position })
	return true, nil
end

local function lanePoints(lanes: { any }): { { position: Vector3, heading: Vector3 } }
	local points = {}
	for _, lane in lanes do
		for _, position in lane.points do
			table.insert(points, { position = position, heading = lane.normal })
		end
	end
	return points
end

--------------------------------------------------------------------------------
-- Part A: gate launch
--------------------------------------------------------------------------------

local function launch(player: Player, state: PlayerState, crossing: Vector3): (boolean, string?)
	local cart, reason = ownParkedCart(player)
	if not cart then
		return false, reason
	end
	local lanes = Rules.NearestLanes(CampExits.Lanes :: any, crossing, Config.Lanes.LanesTried)
	local placed, placeReason = placeCart(player, cart, lanePoints(lanes))
	if not placed then
		return false, placeReason
	end
	return seatAfterMove(player, cart, state, "Launch", nil)
end

local function gateInput(player: Player, state: PlayerState): (Rules.GateInput?, Vector3?)
	local d = deps :: Dependencies
	local _, humanoid, root = body(player)
	if not humanoid or not root then
		return nil, nil
	end
	local position = root.Position
	local canAct = d.Combat:CanAct(player)
	return {
		edgeDistance = Rules.EdgeDistance(campBounds, position.X, position.Z),
		seated = humanoid.SeatPart ~= nil,
		alive = humanoid.Health > 0,
		canAct = canAct == true,
		busy = state.busy,
		carrying = d.Interaction.IsCarrying(player),
	},
		position
end

local function gateStep()
	for _, player in Players:GetPlayers() do
		local state = stateFor(player)
		local input, position = gateInput(player, state)
		if not input or not position then
			state.gate.inside = nil
			continue
		end
		if input.seated and not state.gate.seated then
			state.seatedSince = math.max(state.seatedSince, now() - 0.1)
		end
		-- Far from the edge the answer cannot change; skip the crossing logic.
		if math.abs(input.edgeDistance) > Config.Gate.EdgeBand then
			state.gate.inside = input.edgeDistance <= 0
			if state.gate.seated and not input.seated then
				state.gate.lastSeatExitAt = now()
			end
			state.gate.seated = input.seated
			continue
		end
		local shouldLaunch, refused = Rules.GateStep(state.gate, input, Config.Gate, now())
		if shouldLaunch and not state.working and Flags.Part("GateLaunch") then
			state.working = true
			local startedAt = now()
			local ok, launched, reason = pcall(launch, player, state, position)
			state.working = false
			stats.LastLaunchSeconds = now() - startedAt
			if ok and launched then
				stats.Launches += 1
			else
				stats.LaunchBlocked += 1
				stats.LastReason = tostring(reason or launched)
				-- Never spawn into something: nudge the player to the CART button instead.
				fire(player, { kind = "Pulse", button = "Cart" })
			end
		elseif refused then
			stats.LastReason = refused
		end
	end
end

--------------------------------------------------------------------------------
-- Part B: switch button
--------------------------------------------------------------------------------

local function hopOutSpot(player: Player, cart: Model, target: Vector3?): CFrame?
	local d = deps :: Dependencies
	local measure = d.Placement.Measure(cart)
	local character = player.Character
	if not measure or not character then
		return nil
	end
	local pivot = cart:GetPivot()
	local targetLocalX = if target then pivot:PointToObjectSpace(target).X else nil
	local low, high = visualExtents(cart)
	local gap = Config.HopOut.SideDistance + Config.HopOut.BodySize.X / 2
	local midZ = (low.Z + high.Z) / 2
	local offsets = {
		Left = Vector3.new(low.X - gap, 0, midZ),
		Right = Vector3.new(high.X + gap, 0, midZ),
		Back = Vector3.new(0, 0, high.Z + gap),
	}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { cart, character }
	overlap.RespectCanCollide = true
	local size = Config.HopOut.BodySize
	for _, side in Rules.HopOutSides(targetLocalX) do
		local world = pivot:PointToWorldSpace(offsets[side])
		if not allowedAt(player, world) then
			continue
		end
		local ground = groundAt(world, { cart, character }, 45)
		if not ground or math.abs(ground.Y - (pivot.Position.Y + measure.minimum.Y)) > 6 then
			continue
		end
		local centre = ground + Vector3.yAxis * (size.Y / 2 + 0.6)
		if #Workspace:GetPartBoundsInBox(CFrame.new(centre), size, overlap) > 0 then
			continue
		end
		local face = target or (centre + pivot.LookVector * 10)
		local look = Vector3.new(face.X, centre.Y, face.Z)
		if (look - centre).Magnitude < 0.1 then
			look = centre + pivot.LookVector
		end
		return CFrame.lookAt(centre, look)
	end
	return nil
end

local function equipLauncher(player: Player)
	local character, humanoid = body(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character or not humanoid then
		return
	end
	for _, container in { character :: Instance, backpack :: Instance } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("BrainrotSleepLauncher") == true then
					if tool.Parent ~= character then
						humanoid:EquipTool(tool)
					end
					return
				end
			end
		end
	end
end

local function targetPosition(target: any): Vector3?
	local d = deps :: Dependencies
	if typeof(target) ~= "Instance" or not target:IsA("Model") or target.Parent == nil then
		return nil
	end
	local record = d.World.GetWorldRecord(target)
	return if record then target:GetPivot().Position else nil
end

local function hopOut(player: Player, state: PlayerState, payload: any): (boolean, string?)
	local d = deps :: Dependencies
	local cart = d.CartService:GetCart(player)
	local character, humanoid, root = body(player)
	if not cart or not character or not humanoid or not root then
		return false, "NotDriving"
	end
	local seat = cart:FindFirstChild("DriverSeat")
	if not seat or not seat:IsA("VehicleSeat") or seat.Occupant ~= humanoid then
		return false, "NotDriving"
	end
	if now() - state.seatedSince < Config.HopOut.SeatedGraceSeconds then
		return false, "JustSeated"
	end
	local target = targetPosition(if type(payload) == "table" then payload.target else nil)
	if target and (target - cart:GetPivot().Position).Magnitude > 400 then
		target = nil
	end
	local spot = hopOutSpot(player, cart, target)
	local ok, reason = d.Occupants:UnseatOwner(player, cart)
	if not ok then
		return false, reason
	end
	stats.HopOuts += 1
	task.spawn(function()
		local deadline = now() + 0.5
		while humanoid.SeatPart ~= nil and now() < deadline do
			task.wait()
		end
		if character.Parent == nil or humanoid.Health <= 0 then
			return
		end
		-- With no clear side the ordinary dismount position (on the cart) stands.
		if spot and humanoid.SeatPart == nil then
			character:PivotTo(spot)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		equipLauncher(player)
		fire(player, { kind = "HopOut", cart = cart, at = root.Position })
	end)
	return true, nil
end

local function callAllowed(player: Player, state: PlayerState, cart: Model): (boolean, string?)
	local d = deps :: Dependencies
	local _, humanoid = body(player)
	if not humanoid or humanoid.Health <= 0 then
		return false, "NotLiving"
	end
	if humanoid.SeatPart ~= nil then
		return false, "Seated"
	end
	if not d.Combat:CanAct(player) then
		return false, "Dazed"
	end
	if state.busy then
		return false, "Busy"
	end
	local slowUntil = cart:GetAttribute("VillagerSlowUntil")
	if type(slowUntil) == "number" and slowUntil > Workspace:GetServerTimeNow() then
		return false, "TagSlow"
	end
	local remaining = Config.Call.CooldownSeconds - (now() - state.lastCallAt)
	if remaining > 0 then
		return false, "Cooldown"
	end
	return true, nil
end

local function callPoints(player: Player, cart: Model): { { position: Vector3, heading: Vector3 } }
	local d = deps :: Dependencies
	local _, _, root = body(player)
	local measure = d.Placement.Measure(cart)
	local points = {}
	if not root or not measure then
		return points
	end
	local origin = root.Position
	local facing = root.CFrame.LookVector
	local low, high = visualExtents(cart)
	local halfWidth = (high.X - low.X) / 2
	local halfLength = (high.Z - low.Z) / 2
	local forward = Vector3.new(facing.X, 0, facing.Z)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis)
	for _, candidate in
		Rules.CallCandidates(facing, Config.Call.Directions, Config.Call.Distances :: any)
	do
		-- Distances are measured from the player to the cart's edge, never its centre.
		local direction = candidate.offset.Unit
		local extent = math.abs(direction:Dot(right)) * halfWidth
			+ math.abs(direction:Dot(forward)) * halfLength
		table.insert(points, {
			position = origin + direction * (candidate.offset.Magnitude + extent),
			heading = candidate.heading,
		})
	end
	-- Fallback: measured launch lanes close to the player.
	local nearby = {}
	for _, lane in Rules.NearestLanes(CampExits.Lanes :: any, origin, 1) do
		local first = lane.points[1]
		if
			(Vector3.new(first.X, origin.Y, first.Z) - origin).Magnitude
			<= Config.Call.FallbackRadius
		then
			table.insert(nearby, lane)
		end
	end
	for _, point in lanePoints(nearby) do
		table.insert(points, point)
	end
	return points
end

local function publishCooldown(player: Player, state: PlayerState)
	state.lastCallAt = now()
	player:SetAttribute(
		"DriveAndHuntCallReadyAt",
		Workspace:GetServerTimeNow() + Config.Call.CooldownSeconds
	)
end

local function callCart(player: Player, state: PlayerState): (boolean, string?)
	local d = deps :: Dependencies
	if d.Interaction.IsCarrying(player) then
		return false, "Carrying"
	end
	local cart, reason = ownParkedCart(player)
	if not cart then
		return false, reason
	end
	local allowed, blocked = callAllowed(player, state, cart)
	if not allowed then
		return false, blocked
	end
	local from = cart:GetPivot().Position
	local placed, placeReason = placeCart(player, cart, callPoints(player, cart))
	if not placed then
		stats.CallNoRoom += 1
		stats.LastReason = tostring(placeReason)
		tell(player, Config.Call.NoRoomText)
		return false, "NoRoom"
	end
	publishCooldown(player, state)
	local seated, seatReason = seatAfterMove(player, cart, state, "Call", from)
	if seated then
		stats.Calls += 1
	end
	return seated, seatReason
end

local LOAD_REASONS: { [string]: string } = {
	NO_SPACE = "Cargo full",
	BUSY = "Busy - try again",
	OUT_OF_REACH = "Too far from your cart",
	DAZED = "Dazed",
}

local function freeSlot(cart: Model): string?
	local d = deps :: Dependencies
	for index = 1, d.Cargo:GetCargoCapacity(cart) do
		local slotId = "Slot" .. index
		if d.Cargo:ResolveCargoSlot(cart, slotId) and not d.Cargo:GetSlotRecord(cart, slotId) then
			return slotId
		end
	end
	return nil
end

local function loadAndGo(player: Player, state: PlayerState): (boolean, string?)
	local d = deps :: Dependencies
	if not d.Interaction.IsCarrying(player) then
		return false, "NotCarrying"
	end
	local carriedId = player:GetAttribute("CarriedItemId")
	if type(carriedId) ~= "string" then
		return false, "NotCarrying"
	end
	local cart, reason = ownParkedCart(player)
	if not cart then
		return false, reason
	end
	local allowed, blocked = callAllowed(player, state, cart)
	if not allowed then
		return false, blocked
	end
	-- Check space before moving anything, so a full cart never teleports for nothing.
	if not d.Cargo:CanAcceptCargo(cart) or not freeSlot(cart) then
		stats.LoadAndGoFailed += 1
		tell(player, LOAD_REASONS.NO_SPACE)
		return false, "NO_SPACE"
	end
	local from = cart:GetPivot().Position
	local placed, placeReason = placeCart(player, cart, callPoints(player, cart))
	if not placed then
		stats.CallNoRoom += 1
		stats.LastReason = tostring(placeReason)
		tell(player, Config.Call.NoRoomText)
		return false, "NoRoom"
	end
	publishCooldown(player, state)
	broadcastPuff(from, cart)
	-- Existing validated cargo path (same checks as the LoadCarriedRequest remote). Its
	-- CargoPlaced receipt starts the villager chase exactly as a manual load does.
	local slotId = freeSlot(cart)
	local loaded, loadReason = false, "NO_SPACE"
	if slotId then
		loaded, loadReason = d.Interaction.TryPlaceInCargo(player, cart, slotId, carriedId)
	end
	if not loaded then
		stats.LoadAndGoFailed += 1
		stats.LastReason = tostring(loadReason)
		tell(player, LOAD_REASONS[tostring(loadReason)] or "Could not load - try again")
		return false, tostring(loadReason)
	end
	-- Carrying is over, so the ordinary driver eligibility now passes.
	local seated, seatReason = seatAfterMove(player, cart, state, "LoadAndGo", nil)
	if seated then
		stats.LoadAndGo += 1
	end
	return seated, seatReason
end

--------------------------------------------------------------------------------
-- Playtest Fixes D1-D3: TrainPlace (server decides everything; one bounds query; one FX event)
--------------------------------------------------------------------------------

local function trainPlace(player: Player, state: PlayerState): (boolean, string?)
	local d = deps :: Dependencies
	local Training = require(script.Parent.TrainingService)
	local _, humanoid, root = body(player)
	local bay, distance = nil, math.huge
	if root then
		bay, distance = Training.NearestBay(root.Position)
	end
	local cart = d.CartService:GetCart(player)
	local reason = TrainPlaceRules.Check({
		trainingOn = CampFlags.Training(),
		alreadyTraining = player:GetAttribute("TrainingActive") == true,
		alive = humanoid ~= nil and humanoid.Health > 0,
		distance = distance,
		promptDistance = if bay then bay.prompt.MaxActivationDistance else 0,
		canAct = d.Combat:CanAct(player),
		busy = state.busy,
		carrying = d.Interaction.IsCarrying(player),
		hasCart = cart ~= nil and cart.Parent ~= nil,
	})
	if not reason and not bay then
		reason = "NoBay"
	end
	if reason then
		local text = TrainPlaceRules.Message(reason)
		if text then
			tell(player, text)
		end
		return false, reason
	end
	local liveCart = cart :: Model
	-- Already driving it elsewhere: step out first (the cart must be parked to be moved).
	if humanoid and d.Occupants:GetDriver(liveCart) == player then
		d.Occupants:UnseatOwner(player, liveCart)
		local deadline = now() + 0.3
		while humanoid.SeatPart ~= nil and now() < deadline do
			task.wait()
		end
	end
	local parked, parkedReason = ownParkedCart(player)
	if not parked then
		tell(player, TrainPlaceRules.Message("CartOccupied") or "")
		return false, parkedReason
	end
	-- Deck height under the trigger, ignoring every cart (others may already be training there).
	local ignore: { Instance } = { liveCart }
	local runtime = Workspace:FindFirstChild("Runtime")
	if runtime then
		table.insert(ignore, runtime)
	end
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local trigger = bay.trigger :: BasePart
	-- Deck height = the highest deck-level surface under the cart's footprint (roller tops, pit rails),
	-- plus a small lift, so the strict placement overlap check never touches the rails.
	local probe = TrainPlaceRules.BayFrame(trigger.CFrame, trigger.Position.Y, CFrame.identity)
	local low, high = visualExtents(liveCart)
	local groundY = -math.huge
	for _, x in { low.X, 0, high.X } do
		for _, z in { low.Z, 0, high.Z } do
			local hit = groundAt(probe:PointToWorldSpace(Vector3.new(x, 0, z)), ignore, nil)
			if hit and hit.Y <= trigger.Position.Y then
				groundY = math.max(groundY, hit.Y)
			end
		end
	end
	-- Thin roller bands can slip between probe rays: clear the tallest deck piece in the bay too.
	groundY = math.max(groundY, Training.DeckTop(bay))
	if groundY == -math.huge then
		return false, "NoGround"
	end
	local frame = TrainPlaceRules.BayFrame(
		trigger.CFrame,
		groundY + PlaytestFixes.TrainPlace.DeckLift,
		CartGeometry.SpawnOffset(liveCart)
	)
	-- One placement check: nobody standing where the cart lands (other training carts are fine).
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	for _, part in
		Workspace:GetPartBoundsInBox(frame * CFrame.new((low + high) / 2), high - low, overlap)
	do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			tell(player, TrainPlaceRules.Message("DeckBlocked") or "")
			return false, "DeckBlocked"
		end
	end
	local from = liveCart:GetPivot().Position
	Training.JoinGroup(liveCart) -- shared bay: never collide with carts already training
	local moved, moveReason = d.CartService:RelocateParkedCart(player, liveCart, frame)
	if not moved then
		Training.LeaveGroup(liveCart)
		return false, moveReason
	end
	return seatAfterMove(player, liveCart, state, "TrainPlace", from)
end

local function onRequest(player: Player, action: any, payload: any)
	if type(action) ~= "string" or #action > 16 then
		return
	end
	local state = stateFor(player)
	if action == "Busy" then
		state.busy = payload == true
		return
	end
	local trainVerb = (action == "TrainPlace" or action == "TrainStop")
		and PlaytestFlags.Part("TrainPlace")
	if not Flags.Part("SwitchButton") and not trainVerb then
		return
	end
	local at = now()
	if at - state.lastRequestAt < Config.Request.MinimumIntervalSeconds or state.working then
		return
	end
	state.lastRequestAt = at
	local handler = if action == "HopOut"
		then hopOut
		elseif action == "CallCart" then callCart
		elseif action == "LoadAndGo" then loadAndGo
		elseif action == "TrainPlace" and trainVerb then function(p: Player, s: PlayerState)
			return trainPlace(p, s)
		end -- STOP while training: the ordinary HOP OUT (unseat beside the cart on clear deck).

		elseif action == "TrainStop" and trainVerb then hopOut
		else nil
	if not handler then
		return
	end
	state.working = true
	local ok, accepted, reason = pcall(handler :: any, player, state, payload)
	state.working = false
	if not ok then
		warn("[DriveAndHunt] " .. action .. " error: " .. tostring(accepted))
		accepted, reason = false, "Error"
	end
	fire(player, { kind = "Result", action = action, ok = accepted == true, reason = reason })
end

--------------------------------------------------------------------------------
-- B6 "get out here" pulse and A5 post-bank pulse
--------------------------------------------------------------------------------

local function unreachableStep()
	local d = deps :: Dependencies
	local settings = Config.Unreachable
	for _, player in Players:GetPlayers() do
		local state = stateFor(player)
		if
			now() - state.lastPulseAt < settings.PulseEverySeconds
			or not d.Occupants:IsDriving(player)
		then
			continue
		end
		local cart = d.CartService:GetCart(player)
		if not cart then
			continue
		end
		local origin = cart:GetPivot().Position
		local nearest, nearestDistance = nil, settings.Radius
		for _, model in d.World.GetWorldModels() do
			local position = model:GetPivot().Position
			local distance = (position - origin).Magnitude
			if distance < nearestDistance then
				local _, worldState = d.World.GetWorldRecord(model)
				if worldState == "WorldAwake" then
					nearest, nearestDistance = model, distance
				end
			end
		end
		if not nearest then
			continue
		end
		local position = nearest:GetPivot().Position
		local unreachable = position.Y - origin.Y > settings.HeightAboveCart
		if not unreachable then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { nearest, cart }
			params.RespectCanCollide = true
			unreachable = Workspace:Raycast(
				position + Vector3.yAxis * 2,
				Vector3.yAxis * settings.RoofProbe,
				params
			) ~= nil
		end
		if unreachable then
			state.lastPulseAt = now()
			stats.Pulses += 1
			fire(
				player,
				{ kind = "Pulse", button = "HopOut", hint = "Unreachable", target = nearest }
			)
		end
	end
end

local function onCommitted(player: Player, receipt: any)
	if
		type(receipt) ~= "table"
		or (receipt.kind ~= "BankedPlaced" and receipt.kind ~= "CargoPlaced")
	then
		return
	end
	local d = deps
	if not d or not d.Occupants:IsDriving(player) then
		return
	end
	local cart = d.CartService:GetCart(player)
	if receipt.kind == "CargoPlaced" then
		-- Drive-by scoop (the only cargo load that happens while driving): Part D3 feedback.
		if Flags.Part("ScoopFx") and type(receipt.individualId) == "string" then
			stats.Scoops += 1
			fire(player, { kind = "Scoop", itemId = receipt.individualId })
		end
		return
	end
	if cart and #d.Cargo:GetCargoSnapshot(cart) == 0 then
		stats.Pulses += 1
		fire(player, { kind = "Pulse", button = "HopOut" })
	end
end

--------------------------------------------------------------------------------
-- Studio-only measurement and stress hook (present only while ServerStorage.DriveAndHuntQA is set)
--------------------------------------------------------------------------------

local function measureLanes(player: Player): any
	local d = deps :: Dependencies
	local cart = d.CartService:GetCart(player)
	assert(cart, "player needs a cart to measure lanes")
	local measure = d.Placement.Measure(cart)
	local lanes, rejected = {}, {}
	local seeds = Rules.LaneSeeds(
		campBounds,
		Config.Lanes.Spacing,
		Config.Lanes.EdgeInset,
		Config.Lanes.Distances :: any
	)
	for index, seed in seeds do
		local good = {}
		for _, point in seed.points do
			local regionId = regionAt(point)
			local ground, reason = nil, "NoRegion"
			if regionId and regionId ~= "REGION_CAMP" then
				ground, reason = groundAt(point, { cart }, Config.Lanes.MaxSlopeDegrees)
			end
			if ground then
				local frame = CFrame.lookAt(ground, ground + seed.normal, Vector3.yAxis)
					* CartGeometry.SpawnOffset(cart)
				d.Placement.ResetQueryBudgetForTesting()
				local clear, clearReason = d.Placement.ValidateAssignedSpawn(cart, frame, nil)
				if clear then
					table.insert(
						good,
						{ x = ground.X, y = ground.Y, z = ground.Z, region = regionId }
					)
				else
					reason = clearReason
					ground = nil
				end
			end
			if not ground then
				table.insert(
					rejected,
					string.format("%s@%d,%d:%s", seed.exit, point.X, point.Z, tostring(reason))
				)
			end
		end
		if #good > 0 then
			table.insert(
				lanes,
				{ exit = seed.exit, normal = { seed.normal.X, seed.normal.Z }, points = good }
			)
		end
		if index % 6 == 0 then
			task.wait()
		end
	end
	return {
		lanes = lanes,
		rejected = rejected,
		measure = { min = measure.minimum, max = measure.maximum },
	}
end

local function installQaHook()
	if not RunService:IsStudio() or ServerStorage:GetAttribute("DriveAndHuntQA") ~= true then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "DriveAndHuntQA"
	hook.OnInvoke = function(verb: string, player: Player, a: any, b: any)
		local state = stateFor(player)
		if verb == "Stats" then
			return table.clone(stats)
		elseif verb == "MeasureLanes" then
			return measureLanes(player)
		elseif verb == "Launch" then
			return { launch(player, state, a) }
		elseif verb == "Request" then
			state.lastRequestAt = -math.huge
			if a == "CallCart" or a == "LoadAndGo" then
				state.lastCallAt = if b == "KeepCooldown" then state.lastCallAt else -math.huge
			end
			local handler = if a == "HopOut"
				then hopOut
				elseif a == "CallCart" then callCart
				else loadAndGo
			return { (handler :: any)(player, state, b) }
		elseif verb == "CarryNearest" then
			-- Sleep the nearest awake wild brainrot beside the player and hand-carry it
			-- through the real pickup path (input automation cannot press the prompt).
			local d = deps :: Dependencies
			local _, _, root = body(player)
			if not root then
				return "NO_CHARACTER"
			end
			local best, bestDistance = nil, math.huge
			for _, model in d.World.GetWorldModels() do
				local _, worldState = d.World.GetWorldRecord(model)
				local distance = (model:GetPivot().Position - root.Position).Magnitude
				if worldState == "WorldAwake" and distance < bestDistance then
					best, bestDistance = model, distance
				end
			end
			if not best then
				return "NO_TARGET"
			end
			best:PivotTo(best:GetPivot().Rotation + (root.CFrame * CFrame.new(0, 0, -5)).Position)
			local slept, sleepReason = d.World.TrySleep(best)
			if not slept then
				return "SLEEP_FAILED:" .. tostring(sleepReason)
			end
			local record = d.World.GetWorldRecord(best)
			local picked, pickReason =
				d.Interaction.TryPickupWorld(player, best, record and record.ItemId)
			return if picked
				then "CARRYING:" .. best.Name
				else "PICKUP_FAILED:" .. tostring(pickReason)
		elseif verb == "StressLaunch" then
			-- G2: scripted launches across every lane, optionally with dummies parked in lanes.
			local count, withDummies = a :: number, b == true
			task.spawn(function()
				local d = deps :: Dependencies
				local lanes = CampExits.Lanes :: any
				local result = { done = 0, launched = 0, blocked = 0, overlaps = 0, detail = "" }
				local function publish(final: boolean)
					ServerStorage:SetAttribute(
						"DriveAndHuntStress",
						string.format(
							"%sdone=%d launched=%d blocked=%d overlaps=%d %s",
							if final then "FINAL " else "",
							result.done,
							result.launched,
							result.blocked,
							result.overlaps,
							result.detail
						)
					)
				end
				for index = 1, count do
					local character, humanoid = body(player)
					local cart = d.CartService:GetCart(player)
					if not character or not humanoid or not cart or #lanes == 0 then
						result.detail = "aborted: no character, cart or lanes"
						break
					end
					if humanoid.SeatPart then
						d.Occupants:UnseatOwner(player, cart)
						local deadline = now() + 1
						while
							(humanoid.SeatPart or #d.Occupants:GetOccupants(cart) > 0)
							and now() < deadline
						do
							task.wait()
						end
						task.wait(0.1)
					end
					local lane = lanes[(index - 1) % #lanes + 1]
					local first = lane.points[1]
					local crossing = first - lane.normal * (Config.Lanes.Distances[1] - 1)
					character:PivotTo(CFrame.new(crossing - lane.normal * 4 + Vector3.yAxis * 5))
					local dummies = {}
					if withDummies then
						for slot, point in lane.points do
							if (index + slot) % 3 == 0 then
								local dummy = Instance.new("Part")
								dummy.Name = "DriveAndHuntDummy"
								dummy.Anchored, dummy.Size = true, Vector3.new(6, 8, 6)
								dummy.Position = point + Vector3.yAxis * 4
								dummy.Parent = Workspace
								table.insert(dummies, dummy)
							end
						end
					end
					d.Placement.ResetQueryBudgetForTesting()
					state.gate.lastMoveAt = -math.huge
					local ok, launched = pcall(launch, player, state, crossing)
					if ok and launched then
						result.launched += 1
						task.wait(0.05)
						local measure = d.Placement.Measure(cart)
						local frame = cart:GetPivot()
						local overlap = OverlapParams.new()
						overlap.FilterType = Enum.RaycastFilterType.Exclude
						overlap.FilterDescendantsInstances = { cart, character }
						local centre = (measure.minimum + measure.maximum) / 2
						local hit = false
						for _, part in
							Workspace:GetPartBoundsInBox(
								frame * CFrame.new(centre),
								measure.maximum - measure.minimum,
								overlap
							)
						do
							if
								part.CanCollide
								or isLiveObstacle(part)
								or part.Name == "DriveAndHuntDummy"
							then
								for _, shape in measure.shapes do
									if
										d.Placement.Intersects(
											frame * shape.frame,
											shape.size,
											part.CFrame,
											part.Size
										)
									then
										-- Resting on the floor is contact, not overlap: ignore support under the cart.
										local top = part.Position.Y + part.Size.Y / 2
										if
											top > frame.Position.Y + measure.minimum.Y + 0.6
											or part.Name == "DriveAndHuntDummy"
										then
											hit = true
											result.detail = lane.exit .. ":" .. part:GetFullName()
										end
										break
									end
								end
							end
						end
						if hit then
							result.overlaps += 1
						end
					else
						result.blocked += 1
					end
					for _, dummy in dummies do
						dummy:Destroy()
					end
					result.done = index
					if index % 20 == 0 then
						publish(false)
					end
				end
				publish(true)
			end)
			return "STARTED"
		elseif verb == "State" then
			return {
				inside = state.gate.inside,
				seated = state.gate.seated,
				sinceSeatExit = now() - state.gate.lastSeatExitAt,
				sinceMove = now() - state.gate.lastMoveAt,
				busy = state.busy,
			}
		end
		return "UNKNOWN_VERB"
	end
	hook.Parent = ServerStorage
end

--------------------------------------------------------------------------------

local function ensureRemote(name: string): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name, remote.Parent = name, remotes
	return remote
end

function Service.Start(dependencies: Dependencies)
	if deps or not Flags.Enabled() then
		return
	end
	deps = dependencies
	requestRemote = ensureRemote(RemoteNames.DriveAndHuntRequest)
	fxRemote = ensureRemote(RemoteNames.DriveAndHuntFx)
	table.insert(connections, (requestRemote :: RemoteEvent).OnServerEvent:Connect(onRequest))
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			gateElapsed += dt
			slowElapsed += dt
			if gateElapsed >= 1 / Config.Gate.CheckHz then
				gateElapsed = 0
				local ok, failure = pcall(gateStep)
				if not ok then
					warn("[DriveAndHunt] Gate error: " .. tostring(failure))
				end
			end
			if slowElapsed >= 1 / Config.Unreachable.CheckHz then
				slowElapsed = 0
				if Flags.Part("SwitchButton") then
					local ok, failure = pcall(unreachableStep)
					if not ok then
						warn("[DriveAndHunt] Pulse error: " .. tostring(failure))
					end
				end
			end
		end)
	)
	if type(dependencies.Interaction.SubscribeCommitted) == "function" then
		dependencies.Interaction.SubscribeCommitted(onCommitted)
	end
	installQaHook()
end

function Service.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	deps = nil
end

function Service.GetDiagnostics(): any
	return table.clone(stats)
end

return Service
