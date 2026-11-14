--!strict
-- Village life (rig + animation brief v5, C.6): what a guard does while Idle. Walk to a point
-- of interest, do its activity, rest, move on; chat with a neighbour; wave at players who
-- aren't hunting. It never changes noticing or chasing: VillagerGuardService calls Step only
-- for Idle guards and Leave the moment a guard leaves Idle, so a "?" cancels it at once.
-- Gated by CharacterMotion.LifeEnabled() (FeatureFlags.VillagerLifeEnabled, off by default).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Life = require(ReplicatedStorage.Shared.Config.VillagerLife)

export type Context = {
	now: number,
	-- Walk toward a point at the idle walk speed (the service's steerMove).
	steer: (villager: any, target: Vector3, dt: number) -> (),
	groundY: (Vector3) -> number?,
	players: { { userId: number, position: Vector3 } },
	lastHitAt: { [number]: number },
	villagers: { any },
}

local VillageLife = {}

-- At most one chatting pair per region: regionId -> villager id of the pair's first member.
local chatting: { [string]: string } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function state(villager: any): any
	local life = villager.life
	if not life then
		life = {
			phase = "Start",
			poi = 0,
			untilAt = 0,
			lastTickAt = nil,
			partner = nil,
			waved = {},
			waveUntil = nil,
			angle = 0,
			rng = Random.new(villager.seed or 1),
		}
		villager.life = life
	end
	return life
end

local function stayFactor(villager: any): number
	return Life.StayFactor[villager.type] or 1
end

local function turnToward(villager: any, direction: Vector3, dt: number)
	local desired = flat(direction)
	if desired.Magnitude < 1e-3 then
		return
	end
	desired = desired.Unit
	local facing = villager.facing
	local angle = math.atan2(facing:Cross(desired).Y, facing:Dot(desired))
	local maxTurn = math.rad(Life.TurnRateDegrees) * dt
	villager.facing = (CFrame.Angles(0, math.clamp(angle, -maxTurn, maxTurn), 0) * facing).Unit
end

local function pois(villager: any): { any }
	return Life.Pois[villager.id] or {}
end

local function poiPoint(villager: any, poi: any): Vector3
	return Vector3.new(poi.x, villager.position.Y, poi.z)
end

-- Next point of interest, weighted: Plodders and Shouters favour their work spots, Sprinters
-- spread out. Never the same one twice in a row when there is a choice.
local function pickNext(villager: any, life: any): number
	local list = pois(villager)
	if #list == 0 then
		return 0
	end
	local workWeight = if villager.type == "Sprinter" then 1 else Life.WorkWeight
	local total, weights = 0, {}
	for index, poi in list do
		local weight = if index == life.poi and #list > 1
			then 0
			elseif poi.activity == "Lookout" or poi.activity == "Meet" then 1
			else workWeight
		weights[index] = weight
		total += weight
	end
	local roll = life.rng:NextNumber() * total
	for index, weight in weights do
		roll -= weight
		if roll <= 0 and weight > 0 then
			return index
		end
	end
	return #list
end

local function duration(life: any, low: number, high: number): number
	return low + life.rng:NextNumber() * (high - low)
end

local function setPhase(villager: any, life: any, phase: string, untilAt: number, motion: string?)
	life.phase = phase
	life.untilAt = untilAt
	villager.lifeMotion = motion
end

local function endChat(villager: any, life: any, now: number)
	local partner = life.partner
	life.partner = nil
	if
		chatting[villager.regionId] == villager.id
		or (partner and chatting[villager.regionId] == partner.id)
	then
		chatting[villager.regionId] = nil
	end
	if partner and partner.life and partner.life.partner == villager then
		partner.life.partner = nil
		setPhase(
			partner,
			partner.life,
			"Rest",
			now + duration(partner.life, Life.RestMin, Life.RestMax),
			nil
		)
	end
	setPhase(villager, life, "Rest", now + duration(life, Life.RestMin, Life.RestMax), nil)
end

-- Two idle neighbours within ChatDistance, about ChatChance, one pair per region.
local function tryChat(villager: any, life: any, ctx: Context): boolean
	if chatting[villager.regionId] then
		return false
	end
	for _, other in ctx.villagers do
		local otherLife = other.life
		if
			other ~= villager
			and other.regionId == villager.regionId
			and other.state == "Idle"
			and otherLife
			and (otherLife.phase == "Rest" or otherLife.phase == "Work")
			and not otherLife.partner
			and not otherLife.waveUntil
			and (flat(other.position - villager.position)).Magnitude <= Life.ChatDistance
		then
			if life.rng:NextNumber() < Life.ChatChance then
				local untilAt = ctx.now + duration(life, Life.ChatMin, Life.ChatMax)
				chatting[villager.regionId] = villager.id
				life.partner, otherLife.partner = other, villager
				setPhase(villager, life, "Chat", untilAt, "Chat")
				setPhase(other, otherLife, "Chat", untilAt, "Chat")
				return true
			end
			return false
		end
	end
	return false
end

local function startWork(villager: any, life: any, now: number, fraction: number?)
	local poi = pois(villager)[life.poi]
	if not poi then
		setPhase(villager, life, "Rest", now + duration(life, Life.RestMin, Life.RestMax), nil)
		return
	end
	local factor = if poi.activity == "Lookout" then 1 else stayFactor(villager)
	local length = duration(life, Life.WorkMin, Life.WorkMax) * factor
	if fraction then
		length *= fraction
	end
	local motion = if poi.activity == "Meet" then nil else poi.activity
	setPhase(villager, life, "Work", now + length, motion)
	life.angle = life.rng:NextNumber() * math.pi * 2
end

-- A village looks mid-routine when you arrive: a guard that wakes from sleep (or starts) is
-- placed at a seeded point of interest, part-way through its activity.
local function resume(villager: any, life: any, ctx: Context)
	local list = pois(villager)
	if #list == 0 then
		setPhase(villager, life, "Rest", ctx.now + duration(life, Life.RestMin, Life.RestMax), nil)
		return
	end
	life.poi = life.rng:NextInteger(1, #list)
	local point = poiPoint(villager, list[life.poi])
	local y = ctx.groundY(point)
	villager.position = Vector3.new(point.X, y or villager.position.Y, point.Z)
	villager.speedNow = 0
	local face = list[life.poi].face
	if face then
		villager.facing = flat(Vector3.new(face[1], 0, face[2])).Unit
	end
	startWork(villager, life, ctx.now, 0.2 + life.rng:NextNumber() * 0.8)
end

-- A friendly wave for a nearby player who hasn't hit a brainrot recently.
local function tryWave(villager: any, life: any, ctx: Context): boolean
	for _, entry in ctx.players do
		local gap = flat(entry.position - villager.position).Magnitude
		local lastHit = ctx.lastHitAt[entry.userId]
		local lastWave = life.waved[entry.userId]
		if
			gap <= Life.WaveDistance
			and (lastHit == nil or ctx.now - lastHit >= Life.WaveQuietSeconds)
			and (lastWave == nil or ctx.now - lastWave >= Life.WaveRepeatSeconds)
		then
			life.waved[entry.userId] = ctx.now
			life.waveUntil = ctx.now + Life.WaveSeconds
			life.waveFace = entry.position
			life.waveMotion = villager.lifeMotion
			villager.lifeMotion = "Wave"
			villager.speedNow = 0
			return true
		end
	end
	return false
end

-- One Idle tick. Returns true when the guard moved or changed what it is doing.
function VillageLife.Step(villager: any, dt: number, ctx: Context): boolean
	local life = state(villager)
	local now = ctx.now
	local before, motionBefore = villager.position, villager.lifeMotion
	if life.returned then
		-- Back from a chase: carry on from home, no jump.
		life.returned = nil
	elseif life.lastTickAt == nil or now - life.lastTickAt > Life.ResyncSeconds then
		resume(villager, life, ctx)
	end
	life.lastTickAt = now

	if life.waveUntil then
		if now < life.waveUntil then
			turnToward(villager, life.waveFace - villager.position, dt)
			return villager.lifeMotion ~= motionBefore
		end
		-- The wave paused the routine; give the time back.
		life.untilAt += Life.WaveSeconds
		villager.lifeMotion = life.waveMotion
		life.waveUntil, life.waveFace, life.waveMotion = nil, nil, nil
	elseif life.phase ~= "Chat" and tryWave(villager, life, ctx) then
		return true
	end

	local phase = life.phase
	if phase == "Walk" then
		local poi = pois(villager)[life.poi]
		if not poi then
			setPhase(villager, life, "Rest", now + duration(life, Life.RestMin, Life.RestMax), nil)
		else
			local point = poiPoint(villager, poi)
			if flat(point - villager.position).Magnitude <= Life.ArriveDistance then
				villager.speedNow = 0
				startWork(villager, life, now, nil)
			else
				ctx.steer(villager, point, dt)
			end
		end
	elseif phase == "Work" then
		local poi = pois(villager)[life.poi]
		if poi and poi.activity == "Skate" then
			-- Small circles around the spot at the idle walk speed.
			life.angle += Life.SkateSpeed / Life.SkateRadius * dt
			local centre = poiPoint(villager, poi)
			local point = centre
				+ Vector3.new(math.cos(life.angle), 0, math.sin(life.angle)) * Life.SkateRadius
			local y = ctx.groundY(point)
			local tangent = Vector3.new(-math.sin(life.angle), 0, math.cos(life.angle))
			villager.position = Vector3.new(point.X, y or villager.position.Y, point.Z)
			villager.facing = tangent
			villager.speedNow = Life.SkateSpeed
		else
			villager.speedNow = 0
			if poi and poi.face then
				turnToward(villager, Vector3.new(poi.face[1], 0, poi.face[2]), dt)
			end
			if poi and poi.activity == "Meet" then
				-- A meeting point: rest here and look for someone to talk to.
				if not life.rolledChat then
					life.rolledChat = true
					tryChat(villager, life, ctx)
				end
			end
		end
		if life.phase == "Work" and now >= life.untilAt then
			life.rolledChat = nil
			villager.speedNow = 0
			setPhase(villager, life, "Rest", now + duration(life, Life.RestMin, Life.RestMax), nil)
			tryChat(villager, life, ctx)
		end
	elseif phase == "Rest" then
		villager.speedNow = 0
		if now >= life.untilAt then
			life.poi = pickNext(villager, life)
			setPhase(villager, life, "Walk", 0, nil)
		end
	elseif phase == "Chat" then
		villager.speedNow = 0
		local partner = life.partner
		if
			not partner
			or partner.state ~= "Idle"
			or not partner.life
			or partner.life.partner ~= villager
		then
			endChat(villager, life, now)
		else
			turnToward(villager, partner.position - villager.position, dt)
			if now >= life.untilAt then
				endChat(villager, life, now)
			end
		end
	end
	return villager.position ~= before or villager.lifeMotion ~= motionBefore
end

-- The guard left Idle (noticing, a chase or a reset): drop the routine at once.
function VillageLife.Leave(villager: any, now: number)
	local life = villager.life
	if not life then
		return
	end
	if life.partner then
		endChat(villager, life, now)
	end
	life.waveUntil, life.waveFace, life.waveMotion, life.rolledChat = nil, nil, nil, nil
	-- Coming back from a chase walks to the next spot instead of resuming mid-activity.
	life.poi = pickNext(villager, life)
	life.phase = "Walk"
	life.untilAt = 0
	life.returned = true
	villager.lifeMotion = nil
end

-- Guards with no valid point of interest keep the plain idle wander.
function VillageLife.Has(villager: any): boolean
	local list = Life.Pois[villager.id]
	return list ~= nil and #list > 0
end

function VillageLife.Reset()
	table.clear(chatting)
end

-- Test/inspection helper.
function VillageLife.ChattingRegions(): { [string]: string }
	return chatting
end

return VillageLife
