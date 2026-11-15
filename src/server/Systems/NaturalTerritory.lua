--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Regions = require(ReplicatedStorage.Shared.Config.Regions)

local NaturalTerritory = {}

local function copyWithWorld(record: any, world: any): any
	local copy = table.clone(record)
	copy.World = table.freeze(world)
	return table.freeze(copy)
end

function NaturalTerritory.BindNaturalSpawn(record: any, rawRegionId: any): (any?, string?)
	if type(record) ~= "table" or type(record.World) ~= "table" then
		return nil, "INVALID_WORLD_RECORD"
	end
	local regionId = Regions.NormalizeId(rawRegionId)
	local region = if regionId then Regions.Get(regionId) else nil
	if region == nil or region.kind ~= "Hunting" or region.naturalSpawnAllowed ~= true then
		return nil, "REGION_NOT_SPAWNABLE"
	end
	local world = table.clone(record.World)
	world.SpawnRegionId = regionId
	world.TerritoryRegionId = regionId
	return copyWithWorld(record, world), nil
end

function NaturalTerritory.BindCampReturn(record: any, rawRegionId: any): (any?, string?)
	if type(record) ~= "table" or type(record.World) ~= "table" then
		return nil, "INVALID_WORLD_RECORD"
	end
	local regionId = Regions.NormalizeId(rawRegionId)
	local region = if regionId then Regions.Get(regionId) else nil
	if region == nil or region.kind ~= "Hunting" or region.naturalSpawnAllowed ~= true then
		return nil, "INVALID_HOME_REGION"
	end
	local world = table.clone(record.World)
	world.ReturnRegionId = regionId
	-- A dropped individual is not converted into a natural spawn and does not
	-- acquire a new natural territory. This field owns only its one-time Camp exit.
	world.TerritoryRegionId = nil
	return copyWithWorld(record, world), nil
end

function NaturalTerritory.ClearForPlayerControl(record: any): (any?, string?)
	if type(record) ~= "table" or type(record.World) ~= "table" then
		return nil, "INVALID_WORLD_RECORD"
	end
	if record.World.TerritoryRegionId == nil and record.World.ReturnRegionId == nil then
		return record, nil
	end
	local world = table.clone(record.World)
	world.TerritoryRegionId = nil
	world.ReturnRegionId = nil
	return copyWithWorld(record, world), nil
end

function NaturalTerritory.GetSpawnRegionId(record: any): string?
	local raw = if type(record) == "table" and type(record.World) == "table"
		then record.World.SpawnRegionId
		else nil
	return Regions.NormalizeId(raw)
end

function NaturalTerritory.GetTerritoryRegionId(record: any): string?
	local raw = if type(record) == "table" and type(record.World) == "table"
		then record.World.TerritoryRegionId
		else nil
	return Regions.NormalizeId(raw)
end

function NaturalTerritory.GetReturnRegionId(record: any): string?
	local raw = if type(record) == "table" and type(record.World) == "table"
		then record.World.ReturnRegionId
		else nil
	return Regions.NormalizeId(raw)
end

function NaturalTerritory.SelectRecoveryGoal(
	currentPosition: Vector3,
	candidates: { Vector3 },
	isInside: (Vector3) -> boolean,
	isRouteSafe: (Vector3) -> boolean
): Vector3?
	local ordered = table.clone(candidates)
	table.sort(ordered, function(left, right)
		local leftDistance = (left - currentPosition).Magnitude
		local rightDistance = (right - currentPosition).Magnitude
		if math.abs(leftDistance - rightDistance) > 1e-6 then
			return leftDistance < rightDistance
		end
		if left.X ~= right.X then
			return left.X < right.X
		elseif left.Z ~= right.Z then
			return left.Z < right.Z
		end
		return left.Y < right.Y
	end)
	for _, candidate in ordered do
		if isInside(candidate) and isRouteSafe(candidate) then
			return candidate
		end
	end
	return nil
end

-- Runtime-only memory belongs to one returning individual. Keeping an escape
-- frame prevents a fresh home vector from turning a lateral step back into the
-- same obstacle, or alternating between its two sides on every decision.
function NaturalTerritory.CreateReturnSteering(): any
	return {
		RecentPositions = {},
		DecisionCount = 0,
		NoProgressDecisions = 0,
		ReturnStuck = false,
	}
end

local function rememberReturnPosition(state: any, position: Vector3, remaining: number)
	state.DecisionCount += 1
	state.NoProgressDecisions += 1
	if state.BestHomeDistance == nil or remaining < state.BestHomeDistance - 2 then
		state.BestHomeDistance = remaining
		state.NoProgressDecisions = 0
	end
	state.LastHomeDistance = remaining
	state.EscapePeakDistance = math.max(state.EscapePeakDistance or remaining, remaining)
	local recent = state.RecentPositions
	if #recent == 0 or (recent[#recent] - position).Magnitude > 1 then
		table.insert(recent, position)
		if #recent > 10 then
			table.remove(recent, 1)
		end
	end
	-- Long enough to trace a large base perimeter using the existing bounded
	-- steps. The caller reports this state; it must not teleport or respawn it.
	state.ReturnStuck = state.NoProgressDecisions >= 128
end

-- The optional state preserves the old stateless diagnostic API. Production
-- Camp return passes one state through consecutive movement decisions.
function NaturalTerritory.SelectReturnStep(
	currentPosition: Vector3,
	destination: Vector3,
	stepDistances: { number },
	retryAnglesDegrees: { number },
	isStepSafe: (Vector3) -> boolean,
	steering: any?
): Vector3?
	local delta =
		Vector3.new(destination.X - currentPosition.X, 0, destination.Z - currentPosition.Z)
	local remaining = delta.Magnitude
	if remaining <= 1e-6 then
		return nil
	end
	local forward = delta / remaining
	if steering then
		rememberReturnPosition(steering, currentPosition, remaining)
		if steering.ReturnStuck then
			return nil
		end
	end
	local bestCandidate = nil
	local bestScore = -math.huge
	local bestAngle = 0
	local directAvailable = false
	local directRouteSafe = false
	local function evaluateCandidates(escapeForward: Vector3?, escapeSide: number?)
		for _, rawDistance in stepDistances do
			local distance = math.min(remaining, math.max(0, rawDistance))
			if distance > 1e-6 then
				for _, angleDegrees in retryAnglesDegrees do
					local angle = math.rad(angleDegrees)
					local cosAngle, sinAngle = math.cos(angle), math.sin(angle)
					local heading = if escapeForward and angleDegrees ~= 0
						then escapeForward
						else forward
					local direction = Vector3.new(
						heading.X * cosAngle - heading.Z * sinAngle,
						0,
						heading.X * sinAngle + heading.Z * cosAngle
					)
					local candidate = currentPosition + direction * distance
					local candidateRemaining = Vector3.new(
						candidate.X - destination.X,
						0,
						candidate.Z - destination.Z
					).Magnitude
					local makesProgress = candidateRemaining < remaining - 1e-6
					local isBoundedLateralStep = math.abs(angleDegrees) >= 89.999
						and math.abs(angleDegrees) <= 90.001
					-- Candidate construction already bounds the step. Rechecking the
					-- triangle inequality using Float32 Vector3 magnitudes can reject a
					-- valid lateral heading at ordinary map coordinates due to roundoff.
					local followsEscape = steering == nil
						or escapeSide == nil
						or angleDegrees == 0
						or math.sign(angleDegrees) == escapeSide
					if
						followsEscape
						and (makesProgress or isBoundedLateralStep)
						and isStepSafe(candidate)
					then
						if steering == nil then
							bestCandidate = candidate
							return
						end
						if angleDegrees == 0 then
							directRouteSafe = true
						end
						local revisits = false
						for _, previous in steering.RecentPositions do
							if (candidate - previous).Magnitude < math.min(3, distance * 0.4) then
								revisits = true
								break
							end
						end
						if not revisits then
							if angleDegrees == 0 then
								directAvailable = true
							end
							local score = 8 * (remaining - candidateRemaining) / distance
								+ distance * 0.1
							if score > bestScore + 1e-6 then
								bestCandidate, bestScore, bestAngle = candidate, score, angleDegrees
							end
						end
					end
				end
			end
		end
	end
	evaluateCandidates(steering and steering.EscapeForward, steering and steering.EscapeSide)
	if steering then
		if
			bestCandidate == nil
			and steering.EscapeSide
			and (steering.EscapeTurns or 0) >= 3
			and not steering.EscapeSideFlipped
		then
			-- The committed side has exhausted all three existing frame turns.
			-- At a concave base/ramp corner it can keep rebasing into that same
			-- dead side while recent-position rejection correctly excludes retreat.
			-- Prove the opposite side usable with the SAME bounded candidates,
			-- route/protection and history checks before changing the commitment.
			-- At most one switch per escape episode; never flip on each frame.
			local oppositeSide = -steering.EscapeSide
			evaluateCandidates(forward, oppositeSide)
			if bestCandidate then
				steering.EscapeSide = oppositeSide
				steering.EscapeForward = forward
				steering.EscapeTurns = 0
				steering.EscapeSideFlipped = true
			end
		end
		if
			steering.EscapeSide
			and (steering.EscapeTurns or 0) >= 3
			and directRouteSafe
			and not directAvailable
		then
			-- The exhausted frame can point its lateral heading directly away from
			-- home while every safe direct goal revisits the retreat lane. Rebase
			-- that frame, retaining the committed side and actual-position history;
			-- otherwise bounded candidates repeatedly retreat or all disappear.
			steering.EscapeForward = forward
			steering.EscapeTurns = 0
		end
		if
			steering.EscapeSide
			and directAvailable
			and remaining <= steering.EscapePeakDistance - 9
		then
			steering.EscapeSide, steering.EscapeForward, steering.EscapePeakDistance = nil, nil, nil
			steering.EscapeTurns = nil
			steering.EscapeSideFlipped = nil
		end
		if bestCandidate and bestAngle ~= 0 and steering.EscapeSide == nil then
			steering.EscapeSide = math.sign(bestAngle)
			steering.EscapeForward = forward
			steering.EscapePeakDistance = remaining
			steering.EscapeTurns = 0
		elseif bestCandidate == nil and steering.EscapeSide and (steering.EscapeTurns or 0) < 3 then
			-- A remembered lateral bearing can meet an oblique obstacle face.
			-- Turn the same candidate frame farther around the committed side on
			-- the next decision, using the smallest already configured angle.
			-- This adds no candidates, lookahead nodes or map search.
			local turnDegrees = math.huge
			for _, angleDegrees in retryAnglesDegrees do
				if math.abs(angleDegrees) > 1e-6 then
					turnDegrees = math.min(turnDegrees, math.abs(angleDegrees))
				end
			end
			if turnDegrees < math.huge then
				local turn = math.rad(turnDegrees * steering.EscapeSide)
				local previous = steering.EscapeForward
				steering.EscapeForward = Vector3.new(
					previous.X * math.cos(turn) - previous.Z * math.sin(turn),
					0,
					previous.X * math.sin(turn) + previous.Z * math.cos(turn)
				)
				steering.EscapeTurns = (steering.EscapeTurns or 0) + 1
			end
		end
		steering.LastSelectedAngle = if bestCandidate then bestAngle else nil
	end
	return bestCandidate
end

return NaturalTerritory
