--!strict
-- Core Loop V2, Part E: temperaments for director-owned brainrots (CoreLoopFlags.Part("Temperaments")).
-- Calm herd life (walk/pause rhythm, cohesion, drifting centre), noticing (head turn), the 0.4 s "!"
-- telegraph, temperament reactions (Docile scatter only, Curious approach-or-bolt, Sprinter burst +
-- pant, Zigzag sweeps, Show-off dash/zigzag/burst), rest, exhaustion, herd scatter, stagger on hit,
-- groggy + wary after waking, and the E6 clamps. Camouflage / DecoySplit keep their existing updaters.
-- Movement goes through the roaming owner's own moveToward + safe-step check (territory, ground, Camp).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CoreLoop = require(ReplicatedStorage.Shared.Config.CoreLoop)
local FleePlanner = require(ReplicatedStorage.Shared.CoreLoop.FleePlanner)
local BrainrotCatalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)

local B = CoreLoop.Behaviour
local H = B.Herd

export type Helpers = {
	moveToward: (
		Model,
		any,
		Vector3,
		number,
		number,
		number,
		number,
		string,
		number?,
		((Vector3, Vector3) -> boolean)?
	) -> (boolean, boolean),
	canAdvance: ((Vector3, Vector3) -> boolean)?,
	setMotion: (Model, any, string) -> (),
}

type Mode =
	"Calm"
	| "Notice"
	| "Telegraph"
	| "Approach"
	| "Flee"
	| "Rest"
	| "Exhausted"
	| "Scatter"
	| "ScatterPause"
	| "Groggy"

type State = {
	Temperament: FleePlanner.Temperament,
	Mode: Mode,
	ModeUntil: number,
	Walking: boolean,
	PhaseUntil: number,
	Pauses: number,
	Goal: Vector3?,
	Bolts: number,
	FleeSeconds: number,
	EncounterSeenAt: number,
	EncounterDone: boolean, -- exhausted: no more fleeing until the encounter resets
	Bolt: FleePlanner.Bolt?,
	BoltStartedAt: number,
	BoltOrigin: Vector3,
	BoltDir: Vector3,
	ThreatUserId: number?,
	ThreatPos: Vector3?,
	NoticedThisEncounter: boolean,
	WaryUntil: number,
	LastScatterSeen: number,
	OffscreenSince: number?,
	LastTauntAt: number,
	SignatureEvery: number,
	Random: Random,
	-- QA measurement (checks E-1..E-5); session-only, never read by gameplay.
	SpottedAt: number?,
	ScatterStartedAt: number?,
	LastFleePos: Vector3?,
	LastFleeAt: number?,
}

local Temperament = {}

local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local RegionSpawnCatalog = require(script.Parent.Parent.RegionSpawnCatalog)

-- QA counters for E-1..E-5 (read by CoreLoopQA "TempStats"). Cheap, session-only, no gameplay effect.
local qa: any = nil
local function resetQa()
	qa = {
		ModeEntries = {},
		Flee = { Steps = 0, MaxRatio = 0, OverSpeed = 0, InCamp = 0 },
		Telegraph = { Total = 0, Behind = 0 },
		Scatter = { Count = 0, Regroups = {} },
		Catch = {},
	}
end
resetQa()

local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

-- Herd centres: start at the members' mean, drift slowly (wander circle), stay near home.
type Herd = {
	Centre: Vector3,
	Home: Vector3,
	WanderYaw: number,
	UpdatedAt: number,
	Members: { [Model]: Vector3 },
}
local herds: { [string]: Herd } = {}

-- Hunter speed estimate from successive threat positions.
local lastThreat: { [number]: { Position: Vector3, At: number, Speed: number } } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	local f = flat(v)
	return if f.Magnitude > 1e-3 then f.Unit else fallback
end

local function rotate(dir: Vector3, degrees: number): Vector3
	local r = math.rad(degrees)
	local c, s = math.cos(r), math.sin(r)
	return Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
end

local function stateFor(brainrot: Model): State
	local state = states[brainrot]
	if state then
		return state
	end
	local definition = BrainrotCatalog.Get(brainrot:GetAttribute("BrainrotId"))
	local tier = if definition then definition.tier else "Common"
	local temperament =
		FleePlanner.Temperament(if definition then definition.behaviourId else nil, tier)
	local legendaryPlus = tier == "Legendary" or tier == "Mythic" or tier == "Secret"
	state = {
		Temperament = temperament,
		Mode = "Calm",
		ModeUntil = 0,
		Walking = false,
		PhaseUntil = 0,
		Pauses = 0,
		Goal = nil,
		Bolts = 0,
		FleeSeconds = 0,
		EncounterSeenAt = -math.huge,
		EncounterDone = false,
		Bolt = nil,
		BoltStartedAt = 0,
		BoltOrigin = Vector3.zero,
		BoltDir = Vector3.zAxis,
		ThreatUserId = nil,
		ThreatPos = nil,
		NoticedThisEncounter = false,
		WaryUntil = 0,
		LastScatterSeen = Workspace:GetServerTimeNow(),
		OffscreenSince = nil,
		LastTauntAt = -math.huge,
		SignatureEvery = if legendaryPlus then 2 else 3,
		Random = Random.new(),
	}
	states[brainrot] = state
	brainrot:SetAttribute("CoreLoopTemperament", temperament)
	return state
end

-- Called by roaming when a brainrot wakes: groggy 1 s, then wary (awareness x1.5) for 10 s.
function Temperament.OnWake(brainrot: Model, now: number)
	local state = stateFor(brainrot)
	state.Mode = "Groggy"
	state.ModeUntil = now + B.GroggySeconds
	state.WaryUntil = now + B.GroggySeconds + B.WarySeconds
	brainrot:SetAttribute("CoreLoopGroggyUntil", Workspace:GetServerTimeNow() + B.GroggySeconds)
end

function Temperament.Forget(brainrot: Model)
	states[brainrot] = nil
	for _, herd in herds do
		herd.Members[brainrot] = nil
	end
end

function Temperament.Handles(brainrot: Model): boolean
	local role = brainrot:GetAttribute("CoreLoopRole")
	if role == nil then
		return false
	end
	local state = stateFor(brainrot)
	return state.Temperament ~= "Camouflage" and state.Temperament ~= "DecoySplit"
end

local function herdFor(brainrot: Model, position: Vector3, now: number): Herd?
	local herdId = brainrot:GetAttribute("CoreLoopHerdId")
	if type(herdId) ~= "string" then
		return nil
	end
	local herd = herds[herdId]
	if not herd then
		herd = {
			Centre = position,
			Home = position,
			WanderYaw = math.random() * 2 * math.pi,
			UpdatedAt = now,
			Members = {},
		}
		herds[herdId] = herd
	end
	herd.Members[brainrot] = position
	-- Drift the centre: wander circle (radius 1.5 ahead 4), turn <= 60 deg/s, speed CentreDrift.
	local dt = math.clamp(now - herd.UpdatedAt, 0, 0.5)
	if dt > 0 then
		herd.UpdatedAt = now
		herd.WanderYaw += math.rad(math.clamp((math.random() - 0.5) * 120, -60, 60)) * dt
		local step = Vector3.new(math.sin(herd.WanderYaw), 0, math.cos(herd.WanderYaw))
			* H.CentreDrift
			* dt
		local nextCentre = herd.Centre + step
		-- Keep the drifting centre near where the herd was placed (validated ground lives there).
		if flat(nextCentre - herd.Home).Magnitude <= H.Leash * 1.5 then
			herd.Centre = nextCentre
		else
			herd.WanderYaw += math.pi
		end
	end
	return herd
end

local function nearestThreat(
	position: Vector3,
	candidates: { any },
	now: number
): (any?, number, number)
	local best, bestD = nil, math.huge
	for _, c in candidates do
		local d = flat(c.Position - position).Magnitude
		if d < bestD then
			best, bestD = c, d
		end
	end
	local speed = 0
	if best then
		local previous = lastThreat[best.UserId]
		if previous and now - previous.At > 0.05 then
			local measured = flat(best.Position - previous.Position).Magnitude / (now - previous.At)
			speed = previous.Speed * 0.6 + measured * 0.4
			lastThreat[best.UserId] = { Position = best.Position, At = now, Speed = speed }
		elseif previous then
			speed = previous.Speed
		else
			lastThreat[best.UserId] = { Position = best.Position, At = now, Speed = 0 }
		end
	end
	return best, bestD, speed
end

local function inCart(candidate: any): boolean
	local character = candidate and candidate.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- E6: the pursuing hunter's current top speed (cart top speed or character WalkSpeed).
local CART_TOP_SPEED = 43.2
local function hunterTopSpeed(candidate: any): number
	if inCart(candidate) then
		return CART_TOP_SPEED
	end
	local humanoid = candidate
		and candidate.Character
		and candidate.Character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.WalkSpeed else 16
end

local function enter(state: State, mode: Mode, until_: number)
	if state.Mode ~= mode then
		local key = state.Temperament .. ":" .. mode
		qa.ModeEntries[key] = (qa.ModeEntries[key] or 0) + 1
	end
	if mode ~= "Flee" and mode ~= "Scatter" then
		state.LastFleePos, state.LastFleeAt = nil, nil
	end
	state.Mode = mode
	state.ModeUntil = until_
end

local function startBolt(
	brainrot: Model,
	state: State,
	now: number,
	threatPos: Vector3?,
	herd: Herd?
)
	state.Bolts += 1
	local bolt = FleePlanner.Bolt(state.Temperament, state.Bolts, state.Random)
	if bolt == nil then
		-- Curious: hop toward the hunter and show off instead.
		enter(state, "Approach", now + 0.8)
		local position = brainrot:GetPivot().Position
		local toward = unitOr((threatPos or position) - position, brainrot:GetPivot().LookVector)
		state.Goal = position + toward * B.Curious.ApproachStuds
		return
	end
	local position = brainrot:GetPivot().Position
	local away = unitOr(position - (threatPos or position), -brainrot:GetPivot().LookVector)
	if state.Temperament == "Curious" then
		away = rotate(away, state.Random:NextNumber(-B.Curious.ArcDeg, B.Curious.ArcDeg))
	end
	-- Keep bolts within MaxFromCentre of the herd centre: bend back toward it when far out.
	if herd then
		local fromCentre = flat(position - herd.Centre)
		if fromCentre.Magnitude > B.MaxFromCentre - bolt.studs then
			away = unitOr(away - fromCentre.Unit, away)
		end
	end
	state.Bolt = bolt
	state.BoltStartedAt = now
	state.BoltOrigin = position
	state.BoltDir = away
	enter(state, "Flee", now + bolt.seconds)
end

local function calmGoal(brainrot: Model, state: State, herd: Herd?, position: Vector3): Vector3
	local isStar = brainrot:GetAttribute("CoreLoopStar") == true
	local centre = if herd then herd.Centre else position
	local radius = if isStar then H.StarFromCentre else H.Leash * 0.6
	local angle = state.Random:NextNumber(0, 2 * math.pi)
	local goal = centre
		+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * state.Random:NextNumber(0, radius)
	-- Separation: step away from a herdmate closer than SeparationRadius.
	if herd then
		for other, otherPos in herd.Members do
			if other ~= brainrot then
				local offset = flat(position - otherPos)
				if offset.Magnitude > 1e-3 and offset.Magnitude < H.SeparationRadius then
					goal += offset.Unit * (H.SeparationRadius - offset.Magnitude) * H.SeparationWeight
				end
			end
		end
	end
	return goal
end

-- One update. Returns true when this module owned the brainrot this step.
function Temperament.Update(
	brainrot: Model,
	controller: any,
	now: number,
	dt: number,
	candidates: { any },
	helpers: Helpers
): boolean
	local state = stateFor(brainrot)
	if brainrot:GetAttribute("StarDiving") then
		helpers.setMotion(brainrot, controller, "Celebrate")
		return true
	end
	local serverNow = Workspace:GetServerTimeNow()
	local position = brainrot:GetPivot().Position
	local herd = herdFor(brainrot, position, now)
	local threat, threatDistance, threatSpeed = nearestThreat(position, candidates, now)
	local threatPos = if threat then threat.Position else nil
	local staggered = serverNow < (brainrot:GetAttribute("CoreLoopStaggerUntil") or 0)
	local speedFactor = if staggered then B.StaggerFactor else 1
	local wary = now < state.WaryUntil
	local mutatedShimmer = brainrot:GetAttribute("CoreLoopShimmer") == true
	local behind = threat ~= nil
		and FleePlanner.IsBehind(brainrot:GetPivot().LookVector, threat.Position - position)
	local cartSpeed = if threat and inCart(threat) then threatSpeed else nil
	local awareness = FleePlanner.Awareness(state.Temperament, {
		hunterCartSpeed = cartSpeed,
		hunterFootSpeed = if cartSpeed then nil else threatSpeed,
		behind = behind,
		wary = wary,
		star = brainrot:GetAttribute("CoreLoopStar") == true,
		mutated = mutatedShimmer,
	})
	local disengage = math.max(awareness * 1.25, 30)
	if threat and state.SpottedAt == nil and threatDistance <= math.max(awareness, 40) then
		state.SpottedAt = serverNow -- E-3: "first spotting" = hunter within max(awareness, 40) studs
	end

	-- Encounter bookkeeping: resets after EncounterResetSeconds with nobody within the disengage radius.
	if threat and threatDistance <= disengage then
		state.EncounterSeenAt = now
	elseif now - state.EncounterSeenAt >= B.EncounterResetSeconds then
		state.Bolts, state.FleeSeconds, state.EncounterDone, state.NoticedThisEncounter =
			0, 0, false, false
	end

	-- Herd scatter (E5): the director stamps the time and source of the first hit on a herdmate.
	local scatterAt = brainrot:GetAttribute("CoreLoopScatterAt")
	if type(scatterAt) == "number" and scatterAt > state.LastScatterSeen then
		state.LastScatterSeen = scatterAt
		local from = brainrot:GetAttribute("CoreLoopScatterFrom")
		local origin = brainrot:GetAttribute("CoreLoopScatterOrigin")
		local centreOfHit = if typeof(origin) == "Vector3" then origin else from
		if
			typeof(from) == "Vector3"
			and typeof(centreOfHit) == "Vector3"
			and flat(position - centreOfHit).Magnitude <= H.ScatterRadius
			and state.Mode ~= "Groggy"
		then
			local speed = if state.Temperament == "Docile"
				then H.DocileScatterSpeed
				else B.Curious.Flee
			state.Bolt = {
				speed = speed,
				seconds = H.ScatterSeconds,
				studs = H.ScatterStuds,
				rest = H.ScatterPause,
			}
			state.BoltStartedAt, state.BoltOrigin = now, position
			state.BoltDir = unitOr(position - from, -brainrot:GetPivot().LookVector)
			state.ThreatPos = from
			enter(state, "Scatter", now + H.ScatterSeconds)
			state.ScatterStartedAt = now
			qa.Scatter.Count += 1
		end
	end

	local mode = state.Mode
	if mode == "Groggy" then
		helpers.setMotion(brainrot, controller, "Hit")
		brainrot:SetAttribute("MotionRate", 0.5)
		if now >= state.ModeUntil then
			brainrot:SetAttribute("MotionRate", nil)
			enter(state, "Calm", 0)
		end
		return true
	end

	if mode == "Flee" or mode == "Scatter" then
		local bolt = state.Bolt :: FleePlanner.Bolt
		local s = now - state.BoltStartedAt
		local dir = state.BoltDir
		if mode == "Flee" and state.Temperament == "Zigzag" then
			dir = rotate(dir, FleePlanner.ZigzagOffset(s))
		end
		local speed = if mode == "Flee"
			then FleePlanner.SpeedAt(state.Temperament, bolt, s)
			else bolt.speed
		speed = FleePlanner.ClampSpeed(speed, if threat then hunterTopSpeed(threat) else 16)
			* speedFactor
		local travelled = flat(position - state.BoltOrigin).Magnitude
		-- QA (E-2): the speed actually achieved since the last step vs the pursuer's top speed, and Camp.
		if state.LastFleePos and state.LastFleeAt and now - state.LastFleeAt > 0.05 then
			local achieved = flat(position - state.LastFleePos).Magnitude / (now - state.LastFleeAt)
			local ratio = achieved / (if threat then hunterTopSpeed(threat) else 16)
			qa.Flee.Steps += 1
			qa.Flee.MaxRatio = math.max(qa.Flee.MaxRatio, ratio)
			if ratio > CoreLoop.Behaviour.FleeClampOfHunter + 0.02 then
				qa.Flee.OverSpeed += 1
			end
			if RegionSpawnCatalog.ContainsPosition(Regions.CampId, position, math.huge) then
				qa.Flee.InCamp += 1
			end
		end
		state.LastFleePos, state.LastFleeAt = position, now
		local target = position + dir * math.max(2, speed * 0.25)
		local _, blocked = helpers.moveToward(
			brainrot,
			controller,
			target,
			dt,
			now,
			0.1,
			0,
			"Escape",
			speed,
			helpers.canAdvance
		)
		if mode == "Flee" then
			state.FleeSeconds += dt
		end
		helpers.setMotion(brainrot, controller, "Run")
		-- E6: a fleeing brainrot far from (or behind) every hunter for OffscreenStopSeconds calms down.
		local offscreen = not threat or threatDistance > CoreLoop.Despawn.ProtectRadius
		state.OffscreenSince = if offscreen then (state.OffscreenSince or now) else nil
		if
			blocked
			or now >= state.ModeUntil
			or travelled >= bolt.studs
			or (state.OffscreenSince and now - state.OffscreenSince >= B.OffscreenStopSeconds)
		then
			if mode == "Scatter" then
				enter(state, "ScatterPause", now + H.ScatterPause)
			elseif FleePlanner.IsExhausted(state.Temperament, state.Bolts, state.FleeSeconds) then
				state.EncounterDone = true
				enter(state, "Exhausted", now + B.ExhaustedSeconds)
				brainrot:SetAttribute("CoreLoopExhaustedUntil", serverNow + B.ExhaustedSeconds)
			else
				enter(state, "Rest", now + math.max(0.5, bolt.rest))
			end
		end
		return true
	end

	if mode == "Approach" then
		if state.Goal then
			helpers.moveToward(
				brainrot,
				controller,
				state.Goal,
				dt,
				now,
				0.5,
				0,
				"Roaming",
				B.CalmSpeed * speedFactor,
				helpers.canAdvance
			)
		end
		helpers.setMotion(brainrot, controller, "Signature")
		if now >= state.ModeUntil then
			enter(state, "Rest", now + B.Curious.RestMin)
		end
		return true
	end

	if mode == "Telegraph" then
		-- The "!" beat: face the hunter, play Alert, then react. No flee without this telegraph.
		if threatPos then
			local face = unitOr(threatPos - position, brainrot:GetPivot().LookVector)
			brainrot:PivotTo(CFrame.lookAt(position, position + face, Vector3.yAxis))
		end
		helpers.setMotion(brainrot, controller, "Alert")
		if now >= state.ModeUntil then
			startBolt(brainrot, state, now, threatPos or state.ThreatPos, herd)
		end
		return true
	end

	if mode == "Notice" or mode == "ScatterPause" or mode == "Rest" or mode == "Exhausted" then
		local face = if threatPos
			then unitOr(threatPos - position, brainrot:GetPivot().LookVector)
			else nil
		if face and mode ~= "Exhausted" then
			brainrot:PivotTo(CFrame.lookAt(position, position + face, Vector3.yAxis))
		end
		if mode == "Exhausted" then
			helpers.setMotion(brainrot, controller, "IdleWild2")
			brainrot:SetAttribute("MotionRate", 0.6)
		elseif
			mode == "Rest"
			and state.Temperament == "Showoff"
			and threat
			and threatDistance <= B.Showoff.TauntRadius
			and now - state.LastTauntAt >= B.Showoff.TauntCooldown
		then
			state.LastTauntAt = now
			brainrot:SetAttribute("CoreLoopTauntAt", serverNow)
			helpers.setMotion(brainrot, controller, "Signature")
		else
			helpers.setMotion(brainrot, controller, "Idle")
		end
		if now >= state.ModeUntil then
			brainrot:SetAttribute("MotionRate", nil)
			if
				mode == "Rest"
				and threat
				and threatDistance <= awareness
				and not state.EncounterDone
				and state.Temperament ~= "Docile"
			then
				startBolt(brainrot, state, now, threatPos, herd) -- still hunted: next bolt
			else
				if mode == "ScatterPause" and state.ScatterStartedAt then
					-- E-4: scatter -> pause -> back to calm; also how far from the herd centre it stands.
					local fromCentre = if herd then flat(position - herd.Centre).Magnitude else 0
					table.insert(
						qa.Scatter.Regroups,
						{ Seconds = now - state.ScatterStartedAt, FromCentre = fromCentre }
					)
					state.ScatterStartedAt = nil
				end
				enter(state, "Calm", 0)
			end
		end
		return true
	end

	-- Calm. Notice beat at NoticeFactor x awareness (not from behind), then the telegraph at awareness.
	if threat and state.Temperament ~= "Docile" and not state.EncounterDone then
		if threatDistance <= awareness then
			state.ThreatUserId, state.ThreatPos = threat.UserId, threatPos
			brainrot:SetAttribute("CoreLoopAlertAt", serverNow)
			qa.Telegraph.Total += 1
			if behind then
				qa.Telegraph.Behind += 1 -- E-5: "!" while the hunter was outside the front cone
			end
			enter(state, "Telegraph", now + B.TelegraphSeconds)
			return true
		elseif
			not state.NoticedThisEncounter
			and not behind
			and threatDistance <= FleePlanner.NoticeRadius(awareness, behind)
		then
			state.NoticedThisEncounter = true
			brainrot:SetAttribute("CoreLoopNoticeAt", serverNow)
			enter(state, "Notice", now + B.NoticeTurnSeconds)
			return true
		end
	end

	-- Calm rhythm: walk 2-5 s, pause 1.5-4 s; Signature every 3rd-4th pause (2nd for Legendary+),
	-- IdleWild2 on 1 in 5 pauses.
	if now >= state.PhaseUntil then
		state.Walking = not state.Walking
		if state.Walking then
			state.PhaseUntil = now + state.Random:NextNumber(2, 5)
			state.Goal = calmGoal(brainrot, state, herd, position)
		else
			state.Pauses += 1
			state.PhaseUntil = now + state.Random:NextNumber(1.5, 4)
			state.Goal = nil
			if
				state.Pauses
					% (state.SignatureEvery + (if state.SignatureEvery == 3
						then state.Random:NextInteger(0, 1)
						else 0))
				== 0
			then
				helpers.setMotion(brainrot, controller, "Signature")
			elseif state.Random:NextInteger(1, 5) == 1 then
				helpers.setMotion(brainrot, controller, "IdleWild2")
			else
				helpers.setMotion(brainrot, controller, "Idle")
			end
		end
	end
	if state.Walking and state.Goal then
		local arrived, blocked = helpers.moveToward(
			brainrot,
			controller,
			state.Goal,
			dt,
			now,
			0.6,
			0,
			"Roaming",
			B.CalmSpeed * speedFactor,
			helpers.canAdvance
		)
		helpers.setMotion(brainrot, controller, "Walk")
		if arrived or blocked then
			state.PhaseUntil = now -- switch to a pause next step
		end
	end
	return true
end

-- QA (E-3): a KO closes the catchability trial that started when the hunter first came within range.
function Temperament.OnKO(brainrot: Model)
	local state = states[brainrot]
	if not state then
		return
	end
	local row = qa.Catch[state.Temperament]
	if not row then
		row = { Trials = 0, Within20 = 0, NeverSpotted = 0, Seconds = {} }
		qa.Catch[state.Temperament] = row
	end
	if state.SpottedAt == nil then
		row.NeverSpotted += 1
		return
	end
	local seconds = Workspace:GetServerTimeNow() - state.SpottedAt
	row.Trials += 1
	if seconds <= 20 then
		row.Within20 += 1
	end
	table.insert(row.Seconds, math.floor(seconds * 10) / 10)
	state.SpottedAt = nil
end

function Temperament._QAStats(): any
	return qa
end

function Temperament._QAReset()
	resetQa()
end

-- QA / diagnostics.
function Temperament.Snapshot(brainrot: Model): any
	local state = states[brainrot]
	return if state
		then {
			Temperament = state.Temperament,
			Mode = state.Mode,
			Bolts = state.Bolts,
			FleeSeconds = state.FleeSeconds,
		}
		else nil
end

return Temperament
