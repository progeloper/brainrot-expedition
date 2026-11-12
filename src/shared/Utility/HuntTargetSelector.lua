--!strict
-- Drive-and-Hunt auto-lock target selection (Part C1). Pure: no Roblox service calls, no
-- Instances. The client feeds it candidates at 10 Hz and shows the result; the server never
-- trusts it (every shot is still validated by BrainrotSleepSystem).
local Selector = {}

export type Candidate = {
	id: string,
	distance: number, -- from the muzzle (mounted) or character (on foot)
	facingAngle: number, -- radians from cart heading (mounted) or camera look (on foot)
	alreadyHit: boolean, -- this player has hit it and it is still awake
	rarityRank: number, -- 1 = Common ... maxRank
	lineOfSight: boolean,
	-- Optional presentation inputs for the pickers below.
	screen: Vector2?,
	pointerAngle: number?, -- radians from the mouse ray
}

export type Weights = { distance: number, facing: number, alreadyHit: number, rarity: number }

export type Config = {
	Weights: Weights,
	MaxCandidates: number,
	StickyBonus: number,
	HoldAfterShotSeconds: number,
	LostSightGraceSeconds: number,
	NotHitFactor: number,
	RarityFloor: number,
	MaxRarityRank: number,
	MountedArcDegrees: number,
}

export type Context = {
	range: number,
	mounted: boolean,
	fireHeld: boolean,
	now: number,
}

export type State = {
	targetId: string?,
	lastShotAt: number,
	sightLostAt: number?,
	manualId: string?, -- tap / pointer choice, consumed by the next Select
}

function Selector.NewState(): State
	return { targetId = nil, lastShotAt = -math.huge, sightLostAt = nil, manualId = nil }
end

function Selector.NoteShot(state: State, now: number)
	state.lastShotAt = now
end

function Selector.Clear(state: State)
	state.targetId, state.sightLostAt, state.manualId = nil, nil, nil
end

local function term(value: number, weight: number): number
	return math.clamp(value, 0.02, 1) ^ weight
end

-- 0..1 product of the weighted terms. Sticky bonus is applied by Select, not here.
function Selector.Score(candidate: Candidate, context: Context, config: Config): number
	local weights = config.Weights
	local distance = 1 - candidate.distance / math.max(context.range, 1e-3)
	local facing = 1 - candidate.facingAngle / math.pi
	local hit = if candidate.alreadyHit then 1 else config.NotHitFactor
	local span = math.max(config.MaxRarityRank - 1, 1)
	local rarity = config.RarityFloor
		+ (1 - config.RarityFloor) * math.clamp((candidate.rarityRank - 1) / span, 0, 1)
	return term(distance, weights.distance)
		* term(facing, weights.facing)
		* term(hit, weights.alreadyHit)
		* term(rarity, weights.rarity)
end

-- In range, and inside the mounted firing arc. Line of sight is handled separately so the
-- current target can keep its lock through a brief occlusion.
function Selector.InReach(candidate: Candidate, context: Context, config: Config): boolean
	if candidate.distance > context.range or candidate.distance <= 0 then
		return false
	end
	if context.mounted and math.deg(candidate.facingAngle) > config.MountedArcDegrees then
		return false
	end
	return true
end

local function better(aScore: number, a: Candidate, bScore: number, b: Candidate): boolean
	if aScore ~= bScore then
		return aScore > bScore
	end
	if a.distance ~= b.distance then
		return a.distance < b.distance
	end
	return a.id < b.id
end

-- Chooses the lock for this sample and updates the state. Candidates beyond MaxCandidates
-- (nearest first) are not scored.
function Selector.Select(
	candidates: { Candidate },
	state: State,
	context: Context,
	config: Config
): Candidate?
	local reachable: { Candidate } = {}
	for _, candidate in candidates do
		if Selector.InReach(candidate, context, config) then
			table.insert(reachable, candidate)
		end
	end
	if #reachable > config.MaxCandidates then
		table.sort(reachable, function(a, b)
			if a.distance ~= b.distance then
				return a.distance < b.distance
			end
			return a.id < b.id
		end)
		for index = #reachable, config.MaxCandidates + 1, -1 do
			reachable[index] = nil
		end
	end

	local current: Candidate? = nil
	local manual: Candidate? = nil
	for _, candidate in reachable do
		if candidate.id == state.targetId then
			current = candidate
		end
		if candidate.id == state.manualId and candidate.lineOfSight then
			manual = candidate
		end
	end
	state.manualId = nil

	-- The current target survives a short loss of sight, then is dropped.
	if current then
		if current.lineOfSight then
			state.sightLostAt = nil
		else
			local lostAt = state.sightLostAt or context.now
			state.sightLostAt = lostAt
			if context.now - lostAt > config.LostSightGraceSeconds then
				current = nil
			end
		end
	end
	if not current then
		state.targetId, state.sightLostAt = nil, nil
	end

	-- A deliberate tap or pointer choice always wins.
	if manual then
		state.targetId, state.sightLostAt = manual.id, nil
		return manual
	end

	-- While FIRE is down, and briefly after a shot, nothing can take the lock.
	if
		current
		and (context.fireHeld or context.now - state.lastShotAt < config.HoldAfterShotSeconds)
	then
		return current
	end

	local best: Candidate? = current
	local bestScore = if current
		then Selector.Score(current, context, config) * config.StickyBonus
		else -1
	for _, candidate in reachable do
		if candidate ~= current and candidate.lineOfSight then
			local score = Selector.Score(candidate, context, config)
			if best == nil or better(score, candidate, bestScore, best) then
				best, bestScore = candidate, score
			end
		end
	end
	state.targetId = if best then best.id else nil
	if best ~= current then
		state.sightLostAt = nil
	end
	return best
end

-- Touch: the candidate nearest the tap within `radius` pixels (nearest wins).
function Selector.PickByScreen(candidates: { Candidate }, tap: Vector2, radius: number): Candidate?
	local best: Candidate? = nil
	local bestDistance = radius
	for _, candidate in candidates do
		local screen = candidate.screen
		if screen and candidate.lineOfSight then
			local distance = (screen - tap).Magnitude
			if
				distance <= bestDistance
				and (best == nil or distance < bestDistance or candidate.id < best.id)
			then
				best, bestDistance = candidate, distance
			end
		end
	end
	return best
end

-- PC: the candidate nearest the mouse ray inside the cone, or nil to fall back to Select.
function Selector.PickByPointer(candidates: { Candidate }, coneDegrees: number): Candidate?
	local best: Candidate? = nil
	local bestAngle = math.rad(coneDegrees)
	for _, candidate in candidates do
		local angle = candidate.pointerAngle
		if angle and candidate.lineOfSight and angle <= bestAngle then
			if best == nil or angle < bestAngle or candidate.id < best.id then
				best, bestAngle = candidate, angle
			end
		end
	end
	return best
end

return table.freeze(Selector)
