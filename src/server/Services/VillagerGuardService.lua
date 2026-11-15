--!strict
-- Villager guards + Escape Ring (server-authoritative).
-- Villagers notice accepted shots ("?"), switch to "!" when the catch is loaded onto a cart,
-- chase the cart and give up at the Escape Ring. They can only slow the cart briefly;
-- they never touch cargo, carry state, seats, health or persistence.
--
-- All world access goes through adapters (see Service.Configure) so the state machine runs
-- headless in tests. Gated by FeatureFlags.VillagerGuardsEnabled in Bootstrap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.VillagerGuards)
local Rules = require(ReplicatedStorage.Shared.Utility.VillagerChaseRules)
local CharacterMotion = require(ReplicatedStorage.Shared.Config.CharacterMotion)
local MotionTuning = CharacterMotion.Villager
local VillageLife = require(script.Parent.VillageLife)

export type State = "Idle" | "Suspicious" | "WindUp" | "Chase" | "GiveUp" | "Return"

export type Villager = {
	id: string,
	name: string,
	type: string,
	kit: string,
	regionId: string,
	home: Vector3,
	idleRadius: number,
	position: Vector3,
	facing: Vector3,
	state: State,
	stateAt: number,
	targetUserId: number?,
	noticePoint: Vector3?,
	cooldownUntil: { [number]: number },
	tagged: boolean,
	awake: boolean,
	idleTarget: Vector3?,
	idleNextAt: number,
	definition: any,
	-- Natural movement (CharacterMotion); unused while the feature is off.
	speedNow: number,
	motion: string?,
	motionAt: number?,
	seed: number?,
	-- Village life (VillageLife, C.6); nil while the feature is off.
	life: any?,
	lifeMotion: string?,
}

export type Chase = {
	id: number,
	userId: number,
	player: Player,
	cart: Model,
	center: Vector3,
	radius: number,
	rarity: string,
	colour: string,
	startedAt: number,
	firstStartedAt: number,
	assisted: boolean,
	tags: number,
	minimumGap: number,
	regionId: string?,
	participants: { [string]: boolean },
	lastCartPosition: Vector3?,
	lastCartAt: number?,
	cartVelocity: Vector3?,
}

export type Adapters = {
	now: () -> number,
	getCart: (Player) -> Model?,
	cartPosition: (Model) -> Vector3?,
	cartTopSpeed: (Model) -> number,
	-- Rarity + display colour of the loaded catch (largest rarity in the cart wins).
	cargoProfile: (Model) -> (string, string),
	playerPosition: (Player) -> Vector3?,
	isSafePosition: (Vector3) -> boolean,
	canEnter: (Player, Vector3) -> boolean,
	regionAt: (Vector3) -> string?,
	groundY: (Vector3) -> number?,
	applySlow: (Model, number, number) -> (),
	recipients: (Player, Model) -> { Player },
	fire: (Player, any) -> (),
	publish: (Villager) -> (),
	record: (Player, string, number, string?, string?) -> (),
	players: () -> { Player },
	-- Optional, presentation only: audio cue to every client (AudioCue remote).
	broadcast: ((any) -> ())?,
}

local Service = {}
Service.__index = Service

-- Single hook for a future Clean Escape payout/collection track (owner decision pending).
-- Called with (player, chaseSummary). Nothing is wired to it.
Service.onCleanEscape = nil :: ((Player, any) -> ())?
-- Core Loop V2 (C1): extra subscribers for the Lucky Meter (+12 clean escape, +8 SNEAKY load).
-- The single onCleanEscape slot above (SpecialWeaponService) is unchanged.
local coreLoopCleanEscape: { (Player) -> () } = {}
local coreLoopSneaky: { (Player) -> () } = {}
function Service.AddCleanEscapeSubscriber(fn: (Player) -> ())
	table.insert(coreLoopCleanEscape, fn)
end
function Service.AddSneakySubscriber(fn: (Player) -> ())
	table.insert(coreLoopSneaky, fn)
end

local villagers: { Villager } = {}
local villagersById: { [string]: Villager } = {}
local chases: { [number]: Chase } = {}
local taggedStreak: { [number]: number } = {}
local lastHitAt: { [number]: number } = {} -- village life: no wave for active hunters
local adapters: Adapters? = nil
local nextChaseId = 0
local accumulator = 0

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local motionFor: (Villager, number) -> string

local function setState(villager: Villager, state: State, now: number)
	villager.state = state
	villager.stateAt = now
	if state == "Idle" or state == "Return" then
		villager.targetUserId = nil
		villager.noticePoint = nil
		villager.tagged = false
	end
	if state ~= "Idle" and CharacterMotion.LifeEnabled() then
		VillageLife.Leave(villager, now)
	end
	if CharacterMotion.VillagersEnabled() then
		-- Publish the motion with the state, in the same tick.
		if state == "WindUp" or state == "GiveUp" then
			villager.speedNow = 0
		end
		local motion = motionFor(villager, now)
		if motion ~= villager.motion then
			villager.motion, villager.motionAt = motion, now
		end
	end
end

local function send(chase: Chase, payload: any)
	local a = adapters :: Adapters
	for _, recipient in a.recipients(chase.player, chase.cart) do
		a.fire(recipient, payload)
	end
end

function Service.Configure(nextAdapters: Adapters)
	adapters = nextAdapters
end

function Service.Reset()
	table.clear(villagers)
	table.clear(villagersById)
	table.clear(chases)
	table.clear(taggedStreak)
	table.clear(lastHitAt)
	VillageLife.Reset()
	nextChaseId = 0
	accumulator = 0
end

-- Register villagers from roster rows ({ regionId, villagers = {...} }).
function Service.LoadRoster(roster: { any })
	local a = adapters :: Adapters
	for _, region in roster do
		for _, row in region.villagers do
			local home2 = Vector3.new(row.home[1], 0, row.home[2])
			local y = a.groundY(home2) or 0
			local home = Vector3.new(home2.X, y, home2.Z)
			local villager: Villager = {
				id = row.id,
				name = row.name,
				type = row.type,
				kit = row.kit,
				regionId = region.regionId,
				home = home,
				idleRadius = row.idleRadius or 6,
				position = home,
				facing = Vector3.new(0, 0, -1),
				state = "Idle",
				stateAt = a.now(),
				targetUserId = nil,
				noticePoint = nil,
				cooldownUntil = {},
				tagged = false,
				awake = false,
				idleTarget = nil,
				idleNextAt = 0,
				definition = row,
				speedNow = 0,
				motion = nil,
				motionAt = nil,
				seed = if CharacterMotion.VillagersEnabled()
					then CharacterMotion.SeedFor(row.id)
					else nil,
			}
			table.insert(villagers, villager)
			villagersById[villager.id] = villager
			a.publish(villager)
		end
	end
end

function Service.GetVillager(id: string): Villager?
	return villagersById[id]
end

function Service.GetChase(userId: number): Chase?
	return chases[userId]
end

function Service.GetTaggedStreak(userId: number): number
	return taggedStreak[userId] or 0
end

local function canNotice(villager: Villager, userId: number, now: number): boolean
	if Rules.OnCooldown(villager.cooldownUntil[userId], now) then
		return false
	end
	return villager.state == "Idle" or villager.state == "Return"
end

local function makeSuspicious(villager: Villager, player: Player, point: Vector3, now: number)
	setState(villager, "Suspicious", now)
	villager.targetUserId = player.UserId
	villager.noticePoint = point
	villager.awake = true
	local a = adapters :: Adapters
	a.publish(villager)
end

-- Beat 1: an accepted shot on a wild brainrot.
function Service.OnHit(player: Player, hitPosition: Vector3)
	local a = adapters :: Adapters
	local now = a.now()
	lastHitAt[player.UserId] = now
	for _, villager in villagers do
		if
			villager.state == "Suspicious"
			and villager.targetUserId == player.UserId
			and Rules.FlatDistance(villager.position, hitPosition) <= Config.NoticeRadius
		then
			-- Another shot nearby keeps them curious (refreshes the "?" timer).
			villager.stateAt = now
			villager.noticePoint = hitPosition
		elseif
			canNotice(villager, player.UserId, now)
			and Rules.FlatDistance(villager.position, hitPosition) <= Config.NoticeRadius
		then
			makeSuspicious(villager, player, hitPosition, now)
		end
	end
end

local function enterWindUp(villager: Villager, chase: Chase, now: number)
	setState(villager, "WindUp", now)
	villager.targetUserId = chase.userId
	villager.tagged = false
	chase.participants[villager.id] = true
	local a = adapters :: Adapters
	a.publish(villager)
	if villager.type == "Shouter" then
		-- Alarm bell: everyone near the shouter who hasn't noticed goes straight to "?".
		for _, other in villagers do
			if
				other ~= villager
				and canNotice(other, chase.userId, now)
				and Rules.FlatDistance(other.position, villager.position)
					<= Config.ShouterAlarmRadius
			then
				makeSuspicious(other, chase.player, villager.position, now)
			end
		end
	end
end

local function suspiciousFor(userId: number): { Villager }
	local out = {}
	for _, villager in villagers do
		if villager.state == "Suspicious" and villager.targetUserId == userId then
			table.insert(out, villager)
		end
	end
	return out
end

-- Beat 3: the catch is loaded onto the cart.
function Service.OnCargoLoaded(player: Player)
	local a = adapters :: Adapters
	local cart = a.getCart(player)
	if not cart then
		return
	end
	local position = a.cartPosition(cart)
	if not position then
		return
	end
	local now = a.now()
	local rarity, colour = a.cargoProfile(cart)
	local regionId = a.regionAt(position)
	local live = chases[player.UserId]
	if live then
		-- Second load during a chase: re-centre the ring and refresh the timer.
		live.center = position
		live.radius = math.max(live.radius, Rules.RingRadius(rarity, live.assisted))
		if (Config.RarityRank[rarity] or 0) >= (Config.RarityRank[live.rarity] or 0) then
			live.rarity, live.colour = rarity, colour
		end
		live.startedAt = now
		for _, villager in suspiciousFor(player.UserId) do
			enterWindUp(villager, live, now)
		end
		send(live, {
			kind = "ChaseRecentred",
			chaseId = live.id,
			center = live.center,
			radius = live.radius,
			colour = live.colour,
			rarity = live.rarity,
			endsAt = now + Config.MaxChaseSeconds,
		})
		return
	end
	local noticed = suspiciousFor(player.UserId)
	if #noticed == 0 then
		a.fire(player, { kind = "Sneaky" })
		a.record(player, "SneakyLoad", 1, regionId, "Recorded")
		for _, fn in coreLoopSneaky do
			task.spawn(fn, player)
		end
		return
	end
	nextChaseId += 1
	local streak = taggedStreak[player.UserId] or 0
	local assisted = Rules.IsAssisted(streak)
	local chase: Chase = {
		id = nextChaseId,
		userId = player.UserId,
		player = player,
		cart = cart,
		center = position,
		radius = Rules.RingRadius(rarity, assisted),
		rarity = rarity,
		colour = colour,
		startedAt = now,
		firstStartedAt = now,
		assisted = assisted,
		tags = 0,
		minimumGap = math.huge,
		regionId = regionId,
		participants = {},
	}
	chases[player.UserId] = chase
	for _, villager in noticed do
		enterWindUp(villager, chase, now)
	end
	send(chase, {
		kind = "ChaseStarted",
		chaseId = chase.id,
		center = chase.center,
		radius = chase.radius,
		colour = chase.colour,
		rarity = chase.rarity,
		windUp = Config.WindUpSeconds,
		endsAt = now + Config.MaxChaseSeconds,
	})
	-- Audio only: a Legendary+ chase rings the region landmark for everyone nearby.
	if a.broadcast and (Config.RarityRank[rarity] or 0) >= Config.RarityRank.Legendary then
		a.broadcast({ kind = "BigChase", regionId = regionId, rarity = rarity })
	end
	local count = 0
	for _ in chase.participants do
		count += 1
	end
	a.record(player, "ChaseStarted", count, regionId, rarity)
end

local function giveUp(villager: Villager, chase: Chase?, now: number)
	setState(villager, "GiveUp", now)
	if chase then
		villager.cooldownUntil[chase.userId] = now + Config.GiveUpCooldownSeconds
	end
	local a = adapters :: Adapters
	a.publish(villager)
end

local function endChase(chase: Chase, result: string, now: number)
	local a = adapters :: Adapters
	chases[chase.userId] = nil
	for id in chase.participants do
		local villager = villagersById[id]
		if
			villager
			and villager.targetUserId == chase.userId
			and (villager.state == "WindUp" or villager.state == "Chase")
		then
			giveUp(villager, chase, now)
		elseif villager then
			villager.cooldownUntil[chase.userId] = now + Config.GiveUpCooldownSeconds
		end
	end
	-- Anyone still "?" for this player calms down too (no lingering re-acquire).
	for _, villager in suspiciousFor(chase.userId) do
		villager.cooldownUntil[chase.userId] = now + Config.GiveUpCooldownSeconds
		setState(villager, "Return", now)
		a.publish(villager)
	end
	if result == "Cancelled" then
		return
	end
	local clean = chase.tags == 0
	local closeCall = Rules.IsCloseCall(chase.minimumGap, chase.tags)
	taggedStreak[chase.userId] =
		Rules.NextTaggedStreak(taggedStreak[chase.userId] or 0, chase.tags > 0, clean)
	send(chase, {
		kind = "ChaseEnded",
		chaseId = chase.id,
		result = result,
		clean = clean,
		closeCall = closeCall,
		colour = chase.colour,
		rarity = chase.rarity,
	})
	a.record(
		chase.player,
		"ChaseEnded",
		math.floor((now - chase.firstStartedAt) * 10 + 0.5) / 10,
		chase.regionId,
		result
	)
	a.record(
		chase.player,
		"ChaseTags",
		chase.tags,
		chase.regionId,
		if clean then "Clean" else "Tagged"
	)
	if clean then
		for _, fn in coreLoopCleanEscape do
			task.spawn(fn, chase.player)
		end
	end
	if clean and Service.onCleanEscape then
		task.spawn(Service.onCleanEscape :: any, chase.player, {
			chaseId = chase.id,
			rarity = chase.rarity,
			result = result,
			closeCall = closeCall,
		})
	end
end

local function stepAllowed(nextPosition: Vector3, player: Player?, chase: Chase?): boolean
	local a = adapters :: Adapters
	if a.isSafePosition(nextPosition) then
		return false
	end
	if player and not a.canEnter(player, nextPosition) then
		return false
	end
	if chase and Rules.OutsideRing(nextPosition, chase.center, chase.radius) then
		return false
	end
	return true
end

-- Natural travel: the same destination, speed cap and step checks as the straight step,
-- but the body turns at a limited rate, eases in and out, and follows smoothed ground.
-- `checked` is false for the walks that never had step checks (idle wander, walking home).
local function steerMove(
	villager: Villager,
	target: Vector3,
	speed: number,
	dt: number,
	standoff: number,
	player: Player?,
	chase: Chase?,
	turnRateDegrees: number,
	easeInSeconds: number,
	push: Vector3?,
	checked: boolean
): boolean
	local a = adapters :: Adapters
	local delta = flat(target - villager.position)
	local distance = delta.Magnitude
	local remaining = math.max(distance - standoff, 0)
	if remaining <= 1e-3 or distance <= 1e-3 then
		villager.speedNow = 0
		return true
	end
	local desired = delta / distance
	if push then
		local pushed = desired + push
		if pushed.Magnitude > 1e-3 then
			desired = pushed.Unit
		end
	end
	local facing = villager.facing
	local angle = math.atan2(facing:Cross(desired).Y, facing:Dot(desired))
	local maxTurn = math.rad(turnRateDegrees) * dt
	local turn = math.clamp(angle, -maxTurn, maxTurn)
	facing = (CFrame.Angles(0, turn, 0) * facing).Unit
	villager.facing = facing
	-- Slow down while turning hard (no orbiting) and ease out at the destination.
	local alignment =
		math.clamp(math.cos(math.abs(angle - turn)), MotionTuning.MinAlignedSpeedFactor, 1)
	local targetSpeed =
		math.min(speed * alignment, math.max(remaining / MotionTuning.EaseOutSeconds, 0.6))
	if villager.speedNow < targetSpeed then
		villager.speedNow =
			math.min(targetSpeed, villager.speedNow + speed / math.max(easeInSeconds, 1e-3) * dt)
	else
		villager.speedNow = targetSpeed
	end
	local travel = math.min(villager.speedNow * dt, remaining)
	if travel <= 1e-4 then
		return true
	end
	local nextPosition = villager.position + facing * travel
	if checked and not stepAllowed(nextPosition, player, chase) then
		-- Judge the old straight step before giving up, so the outcome rules are unchanged.
		nextPosition = Rules.StepToward(villager.position, target, speed, dt, standoff)
		if nextPosition == villager.position then
			return true
		end
		if not stepAllowed(nextPosition, player, chase) then
			villager.speedNow = 0
			return false
		end
	end
	local y = a.groundY(nextPosition)
	local currentY = villager.position.Y
	if y then
		currentY += (y - currentY) * (1 - math.exp(-dt / MotionTuning.GroundSmoothSeconds))
	end
	villager.position = Vector3.new(nextPosition.X, currentY, nextPosition.Z)
	return true
end

-- Move a villager one step; returns false (and stays put) when the step would enter a
-- safe zone, a region the chased player hasn't unlocked, or leave the ring.
local function tryMove(
	villager: Villager,
	target: Vector3,
	speed: number,
	dt: number,
	standoff: number,
	player: Player?,
	chase: Chase?,
	push: Vector3?
): boolean
	local a = adapters :: Adapters
	if CharacterMotion.VillagersEnabled() then
		local chasing = villager.state == "Chase"
		return steerMove(
			villager,
			target,
			speed,
			dt,
			standoff,
			player,
			chase,
			if chasing then MotionTuning.ChaseTurnRateDegrees else MotionTuning.TurnRateDegrees,
			if chasing then MotionTuning.WindUpBurstSeconds else MotionTuning.EaseInSeconds,
			push,
			true
		)
	end
	local nextPosition = Rules.StepToward(villager.position, target, speed, dt, standoff)
	if nextPosition == villager.position then
		return true
	end
	if a.isSafePosition(nextPosition) then
		return false
	end
	if player and not a.canEnter(player, nextPosition) then
		return false
	end
	if chase and Rules.OutsideRing(nextPosition, chase.center, chase.radius) then
		return false
	end
	local y = a.groundY(nextPosition)
	local direction = flat(nextPosition - villager.position)
	if direction.Magnitude > 1e-3 then
		villager.facing = direction.Unit
	end
	villager.position = Vector3.new(nextPosition.X, y or villager.position.Y, nextPosition.Z)
	return true
end

-- Chase steering: aim at where the cart will be (capped lead) and keep chasers apart.
-- Speed is untouched; tags are still judged against the cart's real position.
local function chaseAim(
	villager: Villager,
	chase: Chase,
	cartPosition: Vector3,
	speed: number
): (Vector3, Vector3?)
	local aim = cartPosition
	local velocity = chase.cartVelocity
	if velocity and speed > 1e-3 then
		local gap = Rules.FlatDistance(villager.position, cartPosition)
		aim = cartPosition + velocity * math.min(MotionTuning.LeadSeconds, gap / speed)
	end
	local push = Vector3.zero
	for id in chase.participants do
		local other = villagersById[id]
		if other and other ~= villager and other.state == "Chase" then
			local away = flat(villager.position - other.position)
			local distance = away.Magnitude
			if distance > 1e-3 and distance < MotionTuning.SeparationDistance then
				push += away.Unit * ((MotionTuning.SeparationDistance - distance) / MotionTuning.SeparationDistance)
			end
		end
	end
	return aim, if push.Magnitude > 1e-3 then push else nil
end

function motionFor(villager: Villager, now: number): string
	local state = villager.state
	if state == "Suspicious" then
		return "Curious"
	elseif state == "WindUp" then
		return "Shout"
	elseif state == "Chase" then
		local tuning = Config.Types[villager.type]
		if not tuning or not tuning.chases then
			return "Alarm"
		end
		return if now - villager.stateAt >= tuning.burstSeconds and tuning.burstSeconds > 0
			then "Tired"
			else "Run"
	elseif state == "GiveUp" then
		return if villager.tagged
				and now - villager.stateAt < MotionTuning.TagMotionSeconds
			then "Tag"
			else "Tantrum"
	end
	if state == "Idle" and villager.lifeMotion then
		return villager.lifeMotion
	end
	return if villager.speedNow > MotionTuning.MovingSpeed then "Walk" else "Idle"
end

local function playersById(): { [number]: Player }
	local out = {}
	for _, player in (adapters :: Adapters).players() do
		out[player.UserId] = player
	end
	return out
end

local function updateAwake(byId: { [number]: Player })
	local a = adapters :: Adapters
	local positions = {}
	for _, player in byId do
		local position = a.playerPosition(player)
		if position then
			table.insert(positions, position)
		end
		local cart = a.getCart(player)
		local cartPosition = if cart then a.cartPosition(cart) else nil
		if cartPosition then
			table.insert(positions, cartPosition)
		end
	end
	local candidates = {}
	for _, villager in villagers do
		local nearest = math.huge
		for _, position in positions do
			nearest = math.min(nearest, Rules.FlatDistance(villager.position, position))
		end
		local busy = villager.state ~= "Idle"
		villager.awake = false
		if busy or nearest <= Config.WakeRadius then
			table.insert(
				candidates,
				{ villager = villager, distance = if busy then -1 else nearest }
			)
		end
	end
	table.sort(candidates, function(x, y)
		return x.distance < y.distance
	end)
	for index, entry in candidates do
		if index > Config.MaxAwakeVillagers then
			break
		end
		entry.villager.awake = true
	end
end

function Service.Step(dt: number)
	local a = adapters :: Adapters
	if not a then
		return
	end
	local now = a.now()
	local byId = playersById()
	updateAwake(byId)
	local lifeContext: VillageLife.Context? = nil
	local function life(): VillageLife.Context
		if not lifeContext then
			local positions = {}
			for userId, player in byId do
				local position = a.playerPosition(player)
				if position then
					table.insert(positions, { userId = userId, position = position })
				end
			end
			lifeContext = {
				now = now,
				steer = function(villager: any, target: Vector3, stepDt: number)
					steerMove(
						villager,
						target,
						Config.IdleWalkSpeed,
						stepDt,
						0,
						nil,
						nil,
						MotionTuning.TurnRateDegrees,
						MotionTuning.EaseInSeconds,
						nil,
						false
					)
				end,
				groundY = a.groundY,
				players = positions,
				lastHitAt = lastHitAt,
				villagers = villagers,
			}
		end
		return lifeContext :: VillageLife.Context
	end

	-- Chases first: decide ends before villagers move.
	for userId, chase in chases do
		local player = byId[userId]
		local cartPosition = if player and chase.cart.Parent
			then a.cartPosition(chase.cart)
			else nil
		if
			cartPosition
			and chase.lastCartPosition
			and chase.lastCartAt
			and now > chase.lastCartAt
		then
			chase.cartVelocity = flat(cartPosition - chase.lastCartPosition)
				/ (now - chase.lastCartAt)
		end
		chase.lastCartPosition, chase.lastCartAt = cartPosition, now
		if not player or not cartPosition or a.getCart(player) ~= chase.cart then
			endChase(chase, "Cancelled", now)
		else
			local outcome = Rules.ChaseOutcome(
				cartPosition,
				chase.center,
				chase.radius,
				now - chase.startedAt,
				a.isSafePosition(cartPosition)
			)
			if outcome then
				endChase(chase, outcome, now)
			end
		end
	end

	for _, villager in villagers do
		if villager.awake then
			local elapsed = now - villager.stateAt
			local player = if villager.targetUserId then byId[villager.targetUserId] else nil
			local chase = if villager.targetUserId then chases[villager.targetUserId] else nil
			local moved = false
			if villager.state == "Suspicious" then
				if not player then
					setState(villager, "Return", now)
					moved = true
				elseif chase and elapsed >= Config.WindUpSeconds then
					-- Alarmed (or late) noticer joins a live chase after a readable "?".
					enterWindUp(villager, chase, now)
				elseif elapsed >= Config.SuspiciousTimeoutSeconds then
					villager.cooldownUntil[player.UserId] = now + Config.GiveUpCooldownSeconds
					setState(villager, "Return", now)
					moved = true
				else
					local target = a.playerPosition(player) or villager.noticePoint
					if target then
						moved = tryMove(
							villager,
							target,
							Config.SuspiciousWalkSpeed,
							dt,
							Config.SuspiciousStandoff,
							player,
							nil
						)
					end
				end
			elseif villager.state == "WindUp" then
				if not chase then
					giveUp(villager, nil, now)
				elseif elapsed >= Config.WindUpSeconds then
					setState(villager, "Chase", now)
					moved = true
				end
			elseif villager.state == "Chase" then
				if not chase or not player then
					giveUp(villager, nil, now)
				elseif villager.type ~= "Shouter" then
					if Rules.GivesUpByTime(villager.type, elapsed) then
						giveUp(villager, chase, now)
					else
						local cartPosition = a.cartPosition(chase.cart) :: Vector3
						local boarding = now - chase.startedAt < Config.Tag.GraceSeconds
						local speed = Rules.ChaseSpeed(
							villager.type,
							elapsed,
							a.cartTopSpeed(chase.cart),
							chase.assisted
						)
						local aim, push = cartPosition, nil
						if CharacterMotion.VillagersEnabled() then
							aim, push = chaseAim(villager, chase, cartPosition, speed)
						end
						local ok = tryMove(
							villager,
							aim,
							speed,
							dt,
							if boarding then Config.Tag.Reach + 3 else Config.Tag.Reach * 0.5,
							player,
							chase,
							push
						)
						moved = true
						if not ok then
							-- Reached the ring edge, a safe zone or a locked region: tantrum.
							giveUp(villager, chase, now)
						else
							local gap = Rules.FlatDistance(villager.position, cartPosition)
							if not boarding then
								chase.minimumGap = math.min(chase.minimumGap, gap)
							end
							if not boarding and Rules.CanTag(gap, villager.tagged) then
								villager.tagged = true
								chase.tags += 1
								a.applySlow(
									chase.cart,
									Config.Tag.SpeedMultiplier,
									now + Config.Tag.SlowSeconds
								)
								send(chase, {
									kind = "ChaseTag",
									chaseId = chase.id,
									villagerId = villager.id,
								})
								giveUp(villager, chase, now)
							end
						end
					end
				end
			elseif villager.state == "GiveUp" then
				if elapsed >= Config.TantrumSeconds then
					setState(villager, "Return", now)
					moved = true
				end
			elseif villager.state == "Return" then
				if Rules.FlatDistance(villager.position, villager.home) <= 1 then
					setState(villager, "Idle", now)
				else
					-- Walking home ignores locks; homes are always inside their own region.
					if CharacterMotion.VillagersEnabled() then
						steerMove(
							villager,
							villager.home,
							Config.ReturnWalkSpeed,
							dt,
							0,
							nil,
							nil,
							MotionTuning.TurnRateDegrees,
							MotionTuning.EaseInSeconds,
							nil,
							false
						)
					else
						local nextPosition = Rules.StepToward(
							villager.position,
							villager.home,
							Config.ReturnWalkSpeed,
							dt,
							0
						)
						local direction = flat(nextPosition - villager.position)
						if direction.Magnitude > 1e-3 then
							villager.facing = direction.Unit
						end
						villager.position = Vector3.new(
							nextPosition.X,
							a.groundY(nextPosition) or villager.position.Y,
							nextPosition.Z
						)
					end
				end
				moved = true
			elseif
				villager.state == "Idle"
				and CharacterMotion.LifeEnabled()
				and VillageLife.Has(villager)
			then
				moved = VillageLife.Step(villager, dt, life())
			elseif villager.state == "Idle" then
				if now >= villager.idleNextAt then
					local angle = math.random() * math.pi * 2
					local radius = math.random() * villager.idleRadius
					villager.idleTarget = villager.home
						+ Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
					villager.idleNextAt = now + 5 + math.random() * 5
				end
				if villager.idleTarget and CharacterMotion.VillagersEnabled() then
					local before = villager.position
					steerMove(
						villager,
						villager.idleTarget,
						Config.IdleWalkSpeed,
						dt,
						0,
						nil,
						nil,
						MotionTuning.TurnRateDegrees,
						MotionTuning.EaseInSeconds,
						nil,
						false
					)
					moved = villager.position ~= before
				elseif villager.idleTarget then
					local nextPosition = Rules.StepToward(
						villager.position,
						villager.idleTarget,
						Config.IdleWalkSpeed,
						dt,
						0
					)
					if nextPosition ~= villager.position then
						villager.facing = flat(nextPosition - villager.position).Unit
						villager.position = Vector3.new(
							nextPosition.X,
							a.groundY(nextPosition) or villager.position.Y,
							nextPosition.Z
						)
						moved = true
					end
				end
			end
			if CharacterMotion.VillagersEnabled() then
				if
					villager.state ~= "Idle"
					and villager.state ~= "Return"
					and villager.state ~= "Chase"
					and villager.state ~= "Suspicious"
				then
					villager.speedNow = 0
				end
				local motion = motionFor(villager, now)
				if motion ~= villager.motion then
					villager.motion, villager.motionAt = motion, now
					moved = true
				end
			end
			if moved then
				a.publish(villager)
			end
		end
	end
end

-- Heartbeat driver at Config.TickHz.
function Service.Heartbeat(dt: number)
	accumulator += dt
	local interval = 1 / Config.TickHz
	if accumulator < interval then
		return
	end
	local step = math.min(accumulator, interval * 3)
	accumulator = 0
	Service.Step(step)
end

-- Test/inspection helper.
function Service.GetVillagers(): { Villager }
	return villagers
end

return Service
