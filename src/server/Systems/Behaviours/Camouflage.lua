--!strict

local ReactiveRunner = require(script.Parent.ReactiveRunner)

export type ThreatCandidate = ReactiveRunner.ThreatCandidate

export type Config = {
	AwarenessRadius: number,
	DisengageRadius: number,
	DisengageGraceSeconds: number,
	SenseIntervalSeconds: number,
}

export type State = {
	active: boolean,
	cycleStart: number?,
	revision: number,
	noThreatSince: number?,
}

export type Context = {
	Authorized: boolean,
	LifecycleEligible: boolean,
	Position: Vector3,
	Candidates: { ThreatCandidate },
	Sensing: boolean,
	CanSeeCandidate: (ThreatCandidate) -> boolean,
}

export type Result = {
	Activated: boolean?,
	Deactivated: boolean?,
	ActivatingUserId: number?,
	ActivatingDistance: number?,
	Reason: string?,
}

local Camouflage = {}

local function nearestVisibleWithin(
	position: Vector3,
	candidates: { ThreatCandidate },
	radius: number,
	canSeeCandidate: (ThreatCandidate) -> boolean
): (ThreatCandidate?, number?)
	local selected = ReactiveRunner.SelectThreat(
		position,
		candidates,
		canSeeCandidate,
		{ AwarenessRadius = radius }
	)
	if selected == nil then
		return nil, nil
	end
	return selected, (selected.Position - position).Magnitude
end

function Camouflage.CreateState(_now: number): State
	return {
		active = false,
		cycleStart = nil,
		revision = 0,
		noThreatSince = nil,
	}
end

function Camouflage.GetSnapshot(state: State, runtimeId: string)
	return {
		runtimeId = runtimeId,
		revision = state.revision,
		active = state.active,
		cycleStart = state.cycleStart,
	}
end

function Camouflage.TryActivate(state: State, context: Context, now: number, config: Config): Result
	if
		state.active
		or not context.Authorized
		or not context.LifecycleEligible
		or not context.Sensing
	then
		return {}
	end
	local candidate, distance = nearestVisibleWithin(
		context.Position,
		context.Candidates,
		config.AwarenessRadius,
		context.CanSeeCandidate
	)
	if candidate == nil then
		return {}
	end
	state.active = true
	state.cycleStart = now
	state.revision += 1
	state.noThreatSince = nil
	return {
		Activated = true,
		ActivatingUserId = candidate.UserId,
		ActivatingDistance = distance,
	}
end

function Camouflage.Interrupt(state: State, _now: number, _reason: string): boolean
	if not state.active and state.cycleStart == nil and state.noThreatSince == nil then
		return false
	end
	state.active = false
	state.cycleStart = nil
	state.noThreatSince = nil
	state.revision += 1
	return true
end

function Camouflage.Step(state: State, context: Context, now: number, config: Config): Result
	if not context.Authorized or not context.LifecycleEligible then
		if Camouflage.Interrupt(state, now, "Lifecycle") then
			return { Deactivated = true, Reason = "Lifecycle" }
		end
		return {}
	end
	if not state.active then
		return Camouflage.TryActivate(state, context, now, config)
	end
	if not context.Sensing then
		return {}
	end

	local candidate = nearestVisibleWithin(
		context.Position,
		context.Candidates,
		config.DisengageRadius,
		context.CanSeeCandidate
	)
	if candidate ~= nil then
		state.noThreatSince = nil
		return {}
	end
	state.noThreatSince = state.noThreatSince or now
	if now - (state.noThreatSince :: number) < config.DisengageGraceSeconds then
		return {}
	end
	Camouflage.Interrupt(state, now, "Disengaged")
	return { Deactivated = true, Reason = "Disengaged" }
end

return table.freeze(Camouflage)
