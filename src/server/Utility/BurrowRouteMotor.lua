--!nocheck
-- One independently seeded journey in the existing server wild-movement owner.
local RS = game:GetService("ReplicatedStorage")
local Rules = require(RS.Shared.Utility.BrainrotRouteRules)
local Navigation = require(script.Parent.WildNavigation)
local C = require(RS.Shared.Config.AfternoonRepair).Roaming
local Motion = require(RS.Shared.Config.CharacterMotion)
local B = Motion.Brainrot
local Motor = {}
local sequence = 0
local fixed = if game:GetService("RunService"):IsStudio()
	then workspace:GetAttribute("AfternoonRoamingSeed")
	else nil
local sessionSeed = if type(fixed) == "number"
	then math.floor(fixed) % C.SeedModulus
	else Random.new():NextInteger(1, C.SeedModulus - 1)
local reservations = setmetatable({}, { __mode = "k" })
local streams = {}
local function ground(m)
	return m.Model:GetPivot().Position - Vector3.yAxis * m.GroundOffset
end
local function state(m)
	return m.Context.GetState()
end
local function eligible(m)
	return not m.Destroyed
		and m.Model.Parent ~= nil
		and m.Model:GetAttribute("Captured") ~= true
		and state(m) ~= nil
end
local function commit(m)
	local s = state(m)
	if not s or not s.Route then
		return false
	end
	local route = table.clone(s.Route)
	route.Wandering = true
	route.WanderSeed = m.Seed
	route.WanderQuota = m.Quota
	route.WanderDuration = m.Duration
	route.WanderActiveSeconds = m.ActiveSeconds
	route.WanderArrivals = m.Arrivals
	route.WanderPhase = m.Phase
	route.DestinationBurrowId = m.Exit and m.Exit.Id or nil
	if m.Phase ~= "Entering" then
		route.EntryStartedAt = nil
	end
	local accepted = m.Context.Commit(route)
	if accepted then
		m.Sequence += 1
	end
	return accepted
end
local function trace(m, kind, extra)
	if not m.TraceEnabled then
		return
	end
	local row = { kind = kind, active = m.ActiveSeconds, phase = m.Phase, seed = m.Seed }
	for k, v in extra or {} do
		row[k] = v
	end
	table.insert(m.Trace, row)
end
function Motor.Create(model, route, context, fixture)
	local s = context.GetState()
	local previous = s and s.Route or {}
	if not previous.WanderSeed then
		sequence += 1
	end
	local seed = previous.WanderSeed or (sessionSeed + sequence * C.SeedStride) % C.SeedModulus
	local key = model:GetAttribute("ItemId")
	local stream = key and streams[key]
	local random = if stream then stream.random else Random.new(seed)
	local quota = previous.WanderQuota or random:NextInteger(C.QuotaMin, C.QuotaMax)
	local duration = previous.WanderDuration or random:NextNumber(C.DurationMin, C.DurationMax)
	if not stream then
		stream = { random = random }
		if key then
			streams[key] = stream
		end
	end
	local m = {
		Model = model,
		Route = route,
		Context = context,
		Geometry = fixture and fixture.Geometry or Navigation,
		Random = random,
		Stream = stream,
		StreamKey = key,
		Heading = stream.heading,
		Seed = seed,
		Quota = previous.WanderQuota or quota,
		Duration = previous.WanderDuration or duration,
		ActiveSeconds = previous.WanderActiveSeconds or 0,
		Arrivals = previous.WanderArrivals or 0,
		EntranceId = previous.EntranceBurrowId or route.EntranceId,
		Phase = "Wander",
		Generation = 0,
		Departed = false,
		Destroyed = false,
		Sequence = 0,
		NextAt = 0,
		Empty = 0,
		Pending = false,
		Trace = {},
		TraceEnabled = fixture ~= nil,
		GroundOffset = fixture and fixture.GroundOffset or nil,
		-- Natural travel (CharacterMotion). Unused while the feature is off.
		Speed = 0,
		Steered = fixture == nil and Motion.BrainrotsEnabled(),
	}
	if fixture then
		m.BodySize = fixture.BodySize or Vector3.one
	else
		m.Geometry.Prepare(m)
		local hit = m.Geometry.Project(m, model:GetPivot().Position)
		if not hit then
			return nil, "ROUTE_GROUND_UNAVAILABLE"
		end
		m.GroundOffset = model:GetPivot().Position.Y - hit.Y
	end
	if not commit(m) then
		return nil, "ROUTE_STATE_UNAVAILABLE"
	end
	return m
end
local function clearGoal(m)
	reservations[m] = nil
	m.Points = nil
	m.Goal = nil
	m.PointIndex = nil
	m.WanderMute = nil
	m.Straight = nil
	m.LegBest = nil
	m.LegBestAt = nil
end
function Motor.Interrupt(m, reason)
	m.Generation += 1
	m.Geometry.Cancel(m)
	m.Pending = false
	clearGoal(m)
	m.Exit = nil
	m.Exits = nil
	m.ExitCandidates = nil
	m.ExitIndex = nil
	m.Reachable = nil
	m.PathCandidate = nil
	m.NeedsLeg = true
	m.Speed = 0
	m.TurnUntil = nil
	m.PauseKind = nil
	if m.Rhythm then
		m.Rhythm.pauseUntil = nil
	end
	if not m.Departed then
		m.Phase = "Wander"
	end
	trace(m, "interrupted", { reason = reason })
end
function Motor.Destroy(m)
	local current = state(m)
	if m.StreamKey and (m.Departed or not current or current.Retired) then
		streams[m.StreamKey] = nil
	end
	Motor.Interrupt(m, "Removed")
	m.Destroyed = true
end
function Motor.RecordExcursion(m, _from, _to)
	if m.Goal or m.Pending or m.Exit then
		Motor.Interrupt(m, "Reactive")
	end
	return true -- never reject a separately validated reactive movement
end
local function reserve(m, goal, points)
	m.Goal = goal
	m.Points = points or { goal }
	m.PointIndex = 1
	reservations[m] = goal
end
local function separated(m, goal)
	for other, point in reservations do
		if other ~= m and (point - goal).Magnitude < C.GoalSeparation then
			return false
		end
	end
	return true
end
local function request(m, goal, callback)
	m.Pending = true
	local generation = m.Generation
	local accepted = m.Geometry.Request(m, ground(m), goal, function(points, reason)
		if m.Generation ~= generation or not eligible(m) then
			return
		end
		m.Pending = false
		if reason == "STALE_PATH" then
			clearGoal(m)
			return
		end
		callback(points, reason)
	end)
	if not accepted then
		m.Pending = false
	end
	return accepted
end
local function angle(m)
	if not m.Heading then
		return m.Random:NextNumber(0, 2 * math.pi), nil
	end
	local wide = m.Random:NextNumber() < C.WideTurnChance
	local degrees = m.Random:NextNumber(
		if wide then C.WideTurnMin else C.SmallTurnMin,
		if wide then C.WideTurnMax else C.SmallTurnMax
	)
	local signed = degrees * (if m.Random:NextInteger(0, 1) == 0 then -1 else 1)
	return m.Heading + math.rad(signed), signed
end
local function selectGoal(m, now)
	local short = m.Empty >= C.EmptyBatches
	local low = if short then C.ShortDistanceMin else C.DistanceMin
	local high = if short then C.ShortDistanceMax else C.DistanceMax
	local fallback = nil
	for _ = 1, C.Candidates do
		local heading, turn = angle(m)
		local distance = math.sqrt(m.Random:NextNumber(low * low, high * high))
		local goal = m.Geometry.Project(
			m,
			ground(m) + Vector3.new(math.sin(heading), 0, -math.cos(heading)) * distance
		)
		if goal and (not m.Geometry.ValidateGoal or m.Geometry.ValidateGoal(m, goal)) then
			local clear = m.Geometry.ValidateSegment(m, ground(m), goal)
			local option = { goal = goal, heading = heading, turn = turn, distance = distance }
			if clear then
				if separated(m, goal) then
					fallback = option
					break
				end
				fallback = fallback or option
			elseif not m.PathCandidate then
				m.PathCandidate = option
			end
		end
	end
	if fallback then
		m.Empty = 0
		m.Heading = fallback.heading
		m.Stream.heading = m.Heading
		reserve(m, fallback.goal)
		trace(m, "waypoint", {
			position = fallback.goal,
			turn = fallback.turn,
			distance = fallback.distance,
			short = short,
		})
		m.PathCandidate = nil
		return
	end
	local candidate = m.PathCandidate
	m.PathCandidate = nil
	if candidate then
		if
			not request(m, candidate.goal, function(points)
				if points then
					m.Empty = 0
					m.Heading = candidate.heading
					m.Stream.heading = m.Heading
					reserve(m, candidate.goal, points)
					trace(m, "routed-waypoint", {
						position = candidate.goal,
						turn = candidate.turn,
						distance = candidate.distance,
					})
				else
					m.Empty += 1
					m.NextAt = now + C.EmptyBackoff
				end
			end)
		then
			m.NextAt = now + C.EmptyBackoff
		end
	else
		m.Empty = if short then 0 else m.Empty + 1
		m.NextAt = now + C.EmptyBackoff
	end
end
local function useExit(m, choice)
	m.Exit = choice
	reserve(m, choice.Position, choice.Points)
	m.Phase = "ApproachBurrow"
	commit(m)
	trace(m, "exit-selected", {
		entrance = m.EntranceId,
		destination = choice.Id,
		quota = m.Quota,
		duration = m.Duration,
		arrivals = m.Arrivals,
	})
end
local function chooseReachable(m, now)
	local choices = {}
	for _, row in m.Reachable do
		if row.Id ~= m.EntranceId then
			table.insert(choices, row)
		end
	end
	if #choices == 0 then
		choices = m.Reachable
	end
	if #choices == 0 then
		m.ExitCandidates = nil
		m.NextAt = now + C.ExitRetry
		return
	end
	for i = #choices, 2, -1 do
		local j = m.Random:NextInteger(1, i)
		choices[i], choices[j] = choices[j], choices[i]
	end
	m.Exits = choices
	m.ExitCandidates = nil
	useExit(m, table.remove(m.Exits))
end
local function selectExit(m, now)
	if not m.ExitCandidates then
		m.ExitCandidates = m.Geometry.Mouths(m)
		m.ExitIndex = 1
		m.Reachable = {}
	end
	while m.ExitIndex <= #m.ExitCandidates do
		local mouth = m.ExitCandidates[m.ExitIndex]
		m.ExitIndex += 1
		local direct = m.Geometry.ValidateSegment(m, ground(m), mouth.Position)
		local points = if direct
			then { mouth.Position }
			else m.Geometry.ConnectedExit(m, ground(m), mouth)
		if points then
			table.insert(m.Reachable, { Id = mouth.Id, Position = mouth.Position, Points = points })
		else
			if
				not request(m, mouth.Position, function(path)
					if path then
						table.insert(
							m.Reachable,
							{ Id = mouth.Id, Position = mouth.Position, Points = path }
						)
					end
				end)
			then
				m.ExitIndex -= 1
				m.NextAt = now + C.EmptyBackoff
			end
			return
		end
	end
	chooseReachable(m, now)
end
function Motor.CheckArrival(m, now)
	if m.Departed then
		return true
	end
	if not eligible(m) or not m.Exit or (m.Phase ~= "ApproachBurrow" and m.Phase ~= "Entering") then
		return false
	end
	local position = ground(m)
	local delta = position - m.Exit.Position
	if
		Vector3.new(delta.X, 0, delta.Z).Magnitude > C.ArrivalRadius
		or math.abs(delta.Y) > C.GroundTolerance
	then
		return false
	end
	if not m.Geometry.ValidateSegment(m, position, m.Exit.Position) then
		return false
	end
	clearGoal(m)
	m.Phase = "Entering"
	local s = state(m)
	local route, phase = Rules.Arrival(s.Route, now, s.LastAcceptedDamageTime)
	if not m.Context.Commit(route) then
		return false
	end
	if phase == "Depart" then
		-- OnDepart unregisters this motor synchronously and clears its exit.
		local destinationId = m.Exit.Id
		m.Departed = m.Context.OnDepart() == true
		if m.Departed then
			trace(m, "departed", { destination = destinationId, entrance = m.EntranceId })
			Motor.Destroy(m)
		end
	end
	return true
end
local function blocked(m, now, why, current, goal)
	clearGoal(m)
	m.Generation += 1
	m.BlockedReason = why
	m.Speed = 0
	m.NextAt = now + m.Random:NextNumber(C.BlockedMin, C.BlockedMax)
	trace(m, "blocked", { reason = why, position = current, target = goal })
	if m.Exit then
		m.Exit = nil
		if m.Exits and #m.Exits > 0 then
			useExit(m, table.remove(m.Exits))
		else
			m.ExitCandidates = nil
			m.NextAt = now + C.ExitRetry
		end
	end
end
-- Natural travel. Goal picking, exits and every segment check are the existing ones; this
-- only decides how the body gets to the current point: turn-rate-limited heading with a
-- small wander offset, eased speed, smoothed ground height and a walk/pause rhythm.
local function wrap(radians)
	return (radians + math.pi) % (2 * math.pi) - math.pi
end
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local function yawDirection(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end
local function rhythmOf(m, now)
	local r = m.Rhythm
	if not r then
		local rng = Random.new((m.Seed * 31 + 7) % C.SeedModulus)
		r = {
			rng = rng,
			pauses = 0,
			wander = rng:NextNumber(0, 2 * math.pi),
			-- Seeded phase: every creature starts somewhere else in its walk.
			walkUntil = now + rng:NextNumber(0, B.WalkMax),
		}
		r.nextSignature = m.SignatureEvery
			or rng:NextInteger(B.SignatureEveryMin, B.SignatureEveryMax)
		m.Rhythm = r
	end
	return r
end
local function face(m, footing, yaw)
	local target = footing + Vector3.yAxis * m.GroundOffset
	m.Model:PivotTo(CFrame.lookAt(target, target + yawDirection(yaw)))
end
-- Returns true only when the step was blocked (the caller then stops, as before).
local function steer(m, dt, top, now)
	local r = rhythmOf(m, now)
	local current = ground(m)
	local look = m.Model:GetPivot().LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	if r.pauseUntil then
		if now < r.pauseUntil then
			m.Speed = 0
			return
		end
		r.pauseUntil = nil
		m.PauseKind = nil
		r.walkUntil = now
			+ B.WalkMin
			+ (B.WalkMax - B.WalkMin) * r.rng:NextNumber() ^ B.WalkSkew
	end
	if m.TurnUntil then
		local alpha = math.clamp(1 - (m.TurnUntil - now) / B.StopTurnSeconds, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		face(m, current, m.TurnFrom + wrap(m.TurnTo - m.TurnFrom) * eased)
		m.Speed = 0
		if alpha >= 1 then
			m.TurnUntil = nil
		end
		return
	end
	local points = m.Points
	local index = m.PointIndex
	while index < #points and flat(points[index] - current).Magnitude <= B.CornerRadius do
		index += 1
	end
	m.PointIndex = index
	local goal = points[index]
	local final = index == #points
	local toGoal = flat(goal - current)
	local distance = toGoal.Magnitude
	if final and distance <= B.ArriveRadius then
		m.PointIndex = #points + 1
		m.Speed = 0
		return
	end
	if distance <= 1e-4 then
		m.PointIndex = index + 1
		return
	end
	-- A leg that stops making progress is finished in a straight line (the old travel).
	if not m.LegBest or distance < m.LegBest - 0.25 then
		m.LegBest, m.LegBestAt = distance, now
	elseif now - m.LegBestAt > B.LegStallSeconds then
		m.Straight = true
	end
	local seek = toGoal / distance
	local fade = if m.WanderMute or m.Straight or not final
		then 0
		else math.clamp((distance - 3) / 6, 0, 1)
	r.wander += r.rng:NextNumber(-1, 1) * B.WanderJitter * dt
	local desired = seek * B.WanderDistance
		+ Vector3.new(math.cos(r.wander), 0, math.sin(r.wander)) * (B.WanderRadius * fade)
	local desiredYaw = math.atan2(-desired.X, -desired.Z)
	local err = wrap(desiredYaw - yaw)
	if math.abs(err) > math.rad(B.StopTurnDegrees) then
		m.TurnFrom, m.TurnTo = yaw, math.atan2(-seek.X, -seek.Z)
		m.TurnUntil = now + B.StopTurnSeconds
		m.Speed = 0
		return
	end
	local maxTurn = math.rad(B.TurnRateDegrees) * dt
	yaw += math.clamp(err, -maxTurn, maxTurn)
	local remainingError = math.deg(math.abs(wrap(desiredYaw - yaw)))
	local target = top * math.clamp(1 - math.max(0, remainingError - 20) / 80, 0.3, 1)
	if final then
		target = math.min(target, top * math.clamp(distance / B.EaseOutDistance, 0.2, 1))
	end
	local braking = now >= r.walkUntil
	if braking then
		target = 0
	end
	if m.Speed < target then
		m.Speed = math.min(target, m.Speed + top / B.EaseInSeconds * dt)
	else
		m.Speed = math.max(target, m.Speed - top / B.BrakeSeconds * dt)
	end
	if braking and m.Speed <= 0.05 then
		r.pauses += 1
		if r.pauses >= r.nextSignature then
			m.PauseKind = "Signature"
			r.nextSignature = r.pauses
				+ (m.SignatureEvery or r.rng:NextInteger(B.SignatureEveryMin, B.SignatureEveryMax))
		else
			m.PauseKind = "Idle"
		end
		r.pauseUntil = now
			+ B.PauseMax
			- (B.PauseMax - B.PauseMin) * r.rng:NextNumber() ^ B.PauseSkew
		m.Speed = 0
		face(m, current, yaw)
		return
	end
	local step = m.Speed * dt
	if final then
		step = math.min(step, distance)
	end
	if step <= 1e-4 then
		face(m, current, yaw)
		return
	end
	local nextPosition, clear, why = nil, false, "UNSUPPORTED_FOOTPRINT"
	if not m.Straight then
		local hit = m.Geometry.Project(m, current + yawDirection(yaw) * step)
		if hit then
			local y = current.Y + (hit.Y - current.Y) * (1 - math.exp(-dt / B.GroundSmoothSeconds))
			y = math.clamp(y, hit.Y - B.GroundMaxLag, hit.Y + B.GroundMaxLag)
			nextPosition = Vector3.new(hit.X, y, hit.Z)
			clear, why = m.Geometry.ValidateSegment(m, current, nextPosition)
		end
	end
	if not clear then
		-- The curved step left validated space: take the old straight step instead and
		-- stop wandering off the line for the rest of this leg.
		m.WanderMute = true
		local delta = goal - current
		nextPosition = current + delta.Unit * math.min(step, delta.Magnitude)
		clear, why = m.Geometry.ValidateSegment(m, current, nextPosition)
		if not clear then
			blocked(m, now, why, current, goal)
			return true
		end
	end
	face(m, nextPosition, yaw)
	m.BlockedReason = nil
end
function Motor.Step(m, dt, speed, now)
	if not eligible(m) or Motor.CheckArrival(m, now) then
		return
	end
	if m.Phase == "Wander" then
		m.ActiveSeconds += math.max(0, dt)
	end
	if m.Pending or now < m.NextAt then
		return
	end
	if not m.Goal then
		if not m.NeedsLeg and m.Arrivals >= m.Quota and m.ActiveSeconds >= m.Duration then
			selectExit(m, now)
		else
			selectGoal(m, now)
		end
		if not m.Pending then
			commit(m)
		end
	end
	if m.Pending or not m.Goal then
		return
	end
	if m.Steered and m.Geometry.Project then
		if steer(m, math.max(0, dt), speed, now) then
			return -- blocked: same early exit as the straight travel below
		end
	end
	local current = ground(m)
	local remaining = if m.Steered and m.Geometry.Project then 0 else math.max(0, dt) * speed
	while remaining > 1e-6 and m.Points and m.PointIndex <= #m.Points do
		local goal = m.Points[m.PointIndex]
		local delta = goal - current
		if delta.Magnitude <= 1e-6 then
			m.PointIndex += 1
			continue
		end
		local step = math.min(remaining, delta.Magnitude)
		local nextPosition = current + delta.Unit * step
		local clear, why = m.Geometry.ValidateSegment(m, current, nextPosition)
		if not clear then
			blocked(m, now, why, current, goal)
			return
		end
		local facing = Vector3.new(delta.X, 0, delta.Z).Unit
		local target = nextPosition + Vector3.yAxis * m.GroundOffset
		m.Model:PivotTo(CFrame.lookAt(target, target + facing))
		m.BlockedReason = nil
		current = nextPosition
		remaining -= step
		if step >= delta.Magnitude - 1e-6 then
			m.PointIndex += 1
		end
	end
	if m.Points and m.PointIndex > #m.Points then
		clearGoal(m)
		if m.Exit then
			Motor.CheckArrival(m, now)
		else
			m.Arrivals += 1
			m.NeedsLeg = false
			trace(m, "arrived", { arrivals = m.Arrivals })
			if m.Random:NextNumber() < C.PauseChance then
				m.NextAt = now + m.Random:NextNumber(C.PauseMin, C.PauseMax)
			end
		end
	end
	if not m.Departed then
		commit(m)
	end
end
function Motor.GetGround(m)
	return ground(m)
end
function Motor.Pump(now)
	Navigation.Pump(now)
end
function Motor.GetDiagnostics()
	return {
		sessionSeed = sessionSeed,
		spawnSequence = sequence,
		navigation = Navigation.GetDiagnostics(),
	}
end
return Motor
