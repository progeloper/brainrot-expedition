--!strict

local HttpService = game:GetService("HttpService")

export type Config = {
	CuePulsePeriodSeconds: number,
	CuePulseDurationSeconds: number,
}

export type Snapshot = {
	runtimeId: string,
	revision: number,
	active: boolean,
	encounterId: string?,
	startedAt: number?,
	expiresAt: number?,
	decoyCount: number,
}

export type Sample = {
	resolved: boolean,
	active: boolean,
	encounterId: string?,
	decoyCount: number,
	pulseTransparency: number?,
}

local DecoySplitTiming = {}
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
		or not finiteNumber(snapshot.decoyCount)
		or snapshot.decoyCount < 0
		or snapshot.decoyCount % 1 ~= 0
	then
		return false
	end
	if not snapshot.active then
		return snapshot.decoyCount == 0
	end
	return type(snapshot.encounterId) == "string"
		and snapshot.encounterId ~= ""
		and finiteNumber(snapshot.startedAt)
		and finiteNumber(snapshot.expiresAt)
		and snapshot.startedAt >= 0
		and snapshot.expiresAt > snapshot.startedAt
		and snapshot.decoyCount > 0
end

local function smoothstep01(value: number): number
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end

function DecoySplitTiming.EncodeSnapshot(snapshot: Snapshot): string
	assert(validSnapshot(snapshot), "Invalid Decoy Split snapshot")
	return HttpService:JSONEncode({
		v = SNAPSHOT_VERSION,
		runtimeId = snapshot.runtimeId,
		revision = snapshot.revision,
		active = snapshot.active,
		encounterId = snapshot.encounterId or "",
		startedAt = snapshot.startedAt or 0,
		expiresAt = snapshot.expiresAt or 0,
		decoyCount = snapshot.decoyCount,
	})
end

function DecoySplitTiming.DecodeSnapshot(encoded: any): Snapshot?
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
		encounterId = if decoded.active then decoded.encounterId else nil,
		startedAt = if decoded.active then decoded.startedAt else nil,
		expiresAt = if decoded.active then decoded.expiresAt else nil,
		decoyCount = decoded.decoyCount,
	}
end

function DecoySplitTiming.AcceptNewerSnapshot(current: Snapshot?, incoming: Snapshot): Snapshot
	if current ~= nil and incoming.revision <= current.revision then
		return current
	end
	return incoming
end

function DecoySplitTiming.Sample(snapshot: Snapshot?, now: number, config: Config): Sample
	if
		not validSnapshot(snapshot)
		or not finiteNumber(now)
		or not finiteNumber(config.CuePulsePeriodSeconds)
		or config.CuePulsePeriodSeconds <= 0
		or not finiteNumber(config.CuePulseDurationSeconds)
		or config.CuePulseDurationSeconds <= 0
		or config.CuePulseDurationSeconds > config.CuePulsePeriodSeconds
	then
		return {
			resolved = false,
			active = false,
			encounterId = nil,
			decoyCount = 0,
			pulseTransparency = nil,
		}
	end
	local resolved = snapshot :: Snapshot
	if not resolved.active or now >= (resolved.expiresAt :: number) then
		return {
			resolved = true,
			active = false,
			encounterId = nil,
			decoyCount = 0,
			pulseTransparency = nil,
		}
	end

	local phaseTime = math.max(0, now - (resolved.startedAt :: number))
		% config.CuePulsePeriodSeconds
	local pulseTransparency: number? = nil
	if phaseTime < config.CuePulseDurationSeconds then
		local half = config.CuePulseDurationSeconds * 0.5
		local strength = if phaseTime <= half
			then smoothstep01(phaseTime / half)
			else smoothstep01((config.CuePulseDurationSeconds - phaseTime) / half)
		pulseTransparency = 1 - 0.85 * strength
	end
	return {
		resolved = true,
		active = true,
		encounterId = resolved.encounterId,
		decoyCount = resolved.decoyCount,
		pulseTransparency = pulseTransparency,
	}
end

return table.freeze(DecoySplitTiming)
