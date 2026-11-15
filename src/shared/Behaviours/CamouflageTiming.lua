--!strict

local HttpService = game:GetService("HttpService")

export type Config = {
	RevealPeriodSeconds: number,
	FullRevealSeconds: number,
	ConcealFadeSeconds: number,
	RevealFadeSeconds: number,
	ConcealAmount: number,
	RevealCueSeconds: number,
	RevealCueOutlineTransparency: number,
}

export type Snapshot = {
	runtimeId: string,
	revision: number,
	active: boolean,
	cycleStart: number?,
}

export type Phase = "Inactive" | "Unresolved" | "Revealed" | "Concealing" | "Hidden" | "Revealing"

export type Sample = {
	phase: Phase,
	concealBlend: number,
	camouflageAmount: number,
	fullReveal: boolean,
	resolved: boolean,
	active: boolean,
	cycleIndex: number,
	phaseTime: number,
}

local CamouflageTiming = {}
local BOUNDARY_EPSILON = 1e-7
local SNAPSHOT_VERSION = 1

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function validSnapshot(snapshot: any): boolean
	if
		type(snapshot) ~= "table"
		or type(snapshot.runtimeId) ~= "string"
		or snapshot.runtimeId == ""
		or not finiteNumber(snapshot.revision)
		or snapshot.revision < 0
		or snapshot.revision % 1 ~= 0
		or type(snapshot.active) ~= "boolean"
	then
		return false
	end
	return not snapshot.active or (finiteNumber(snapshot.cycleStart) and snapshot.cycleStart >= 0)
end

local function validConfig(config: Config): boolean
	return finiteNumber(config.RevealPeriodSeconds)
		and config.RevealPeriodSeconds > 0
		and finiteNumber(config.FullRevealSeconds)
		and config.FullRevealSeconds > 0
		and finiteNumber(config.ConcealFadeSeconds)
		and config.ConcealFadeSeconds > 0
		and finiteNumber(config.RevealFadeSeconds)
		and config.RevealFadeSeconds > 0
		and finiteNumber(config.ConcealAmount)
		and config.ConcealAmount > 0
		and config.ConcealAmount < 1
		and config.FullRevealSeconds + config.ConcealFadeSeconds + config.RevealFadeSeconds
			< config.RevealPeriodSeconds
end

local function sample(
	phase: Phase,
	concealBlend: number,
	fullReveal: boolean,
	resolved: boolean,
	active: boolean,
	cycleIndex: number,
	phaseTime: number,
	concealAmount: number
): Sample
	return {
		phase = phase,
		concealBlend = concealBlend,
		camouflageAmount = concealBlend * concealAmount,
		fullReveal = fullReveal,
		resolved = resolved,
		active = active,
		cycleIndex = cycleIndex,
		phaseTime = phaseTime,
	}
end

function CamouflageTiming.EncodeSnapshot(snapshot: Snapshot): string
	assert(validSnapshot(snapshot), "Invalid Camouflage snapshot")
	return HttpService:JSONEncode({
		v = SNAPSHOT_VERSION,
		runtimeId = snapshot.runtimeId,
		revision = snapshot.revision,
		active = snapshot.active,
		cycleStart = snapshot.cycleStart or 0,
	})
end

function CamouflageTiming.DecodeSnapshot(encoded: any): Snapshot?
	if type(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)
	if
		not ok
		or type(decoded) ~= "table"
		or decoded.v ~= SNAPSHOT_VERSION
		or not validSnapshot(decoded)
	then
		return nil
	end
	return {
		runtimeId = decoded.runtimeId,
		revision = decoded.revision,
		active = decoded.active,
		cycleStart = if decoded.active then decoded.cycleStart else nil,
	}
end

function CamouflageTiming.AcceptNewerSnapshot(current: Snapshot?, incoming: Snapshot): Snapshot
	if current ~= nil and incoming.revision <= current.revision then
		return current
	end
	return incoming
end

function CamouflageTiming.Sample(snapshot: Snapshot?, now: number, config: Config): Sample
	if not validConfig(config) or not finiteNumber(now) or not validSnapshot(snapshot) then
		return sample("Unresolved", 0, false, false, false, 0, 0, 0)
	end
	if not (snapshot :: Snapshot).active then
		return sample("Inactive", 0, true, true, false, 0, 0, config.ConcealAmount)
	end

	local cycleStart = (snapshot :: Snapshot).cycleStart :: number
	local elapsed = math.max(0, now - cycleStart)
	local cycleIndex = math.floor(elapsed / config.RevealPeriodSeconds)
	local phaseTime = elapsed % config.RevealPeriodSeconds
	local concealStart = config.FullRevealSeconds
	local hiddenStart = concealStart + config.ConcealFadeSeconds
	local revealStart = config.RevealPeriodSeconds - config.RevealFadeSeconds

	if phaseTime + BOUNDARY_EPSILON < concealStart then
		return sample("Revealed", 0, true, true, true, cycleIndex, phaseTime, config.ConcealAmount)
	elseif phaseTime + BOUNDARY_EPSILON < hiddenStart then
		local blend = math.clamp((phaseTime - concealStart) / config.ConcealFadeSeconds, 0, 1)
		return sample(
			"Concealing",
			blend,
			false,
			true,
			true,
			cycleIndex,
			phaseTime,
			config.ConcealAmount
		)
	elseif phaseTime + BOUNDARY_EPSILON < revealStart then
		return sample("Hidden", 1, false, true, true, cycleIndex, phaseTime, config.ConcealAmount)
	end
	local blend =
		math.clamp((config.RevealPeriodSeconds - phaseTime) / config.RevealFadeSeconds, 0, 1)
	return sample(
		"Revealing",
		blend,
		false,
		true,
		true,
		cycleIndex,
		phaseTime,
		config.ConcealAmount
	)
end

function CamouflageTiming.GetRevealCueTransparency(sampled: Sample, config: Config): number?
	if
		not sampled.active
		or sampled.phase ~= "Revealed"
		or sampled.phaseTime >= config.RevealCueSeconds
	then
		return nil
	end
	local alpha = math.clamp(sampled.phaseTime / config.RevealCueSeconds, 0, 1)
	return config.RevealCueOutlineTransparency + (1 - config.RevealCueOutlineTransparency) * alpha
end

return table.freeze(CamouflageTiming)
