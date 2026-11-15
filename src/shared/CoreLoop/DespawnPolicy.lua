--!strict
-- A7 retirement decisions. Pure: the caller passes facts, this returns what to do.
-- Rule zero: never retire within ProtectRadius of any hunter, or while asleep, carried, in cargo,
-- pending bank, or hit in the last RecentHitSeconds. Nothing ever vanishes in view; Stars leave by
-- a visible LEAVING warning then a Dive.
local CoreLoop = require(script.Parent.Parent.Config.CoreLoop)

export type Role = "Snack" | "Loner" | "Star" | "Ambient"
export type Facts = {
	role: Role,
	now: number,
	nearestHunterDistance: number, -- math.huge with no hunters
	unseenSince: number?, -- when it last went beyond ProtectRadius of every hunter (nil = seen now)
	asleep: boolean?,
	carried: boolean?,
	inCargo: boolean?,
	pendingBank: boolean?,
	lastHitAt: number?,
	starFirstSeenAt: number?, -- owner first saw the Star
	leavingSince: number?, -- LEAVING warning started
}
export type Decision = "Keep" | "Retire" | "StartLeaving" | "Dive"

local Policy = {}

function Policy.Protected(f: Facts): boolean
	local d = CoreLoop.Despawn
	if f.asleep or f.carried or f.inCargo or f.pendingBank then
		return true
	end
	if f.lastHitAt and f.now - f.lastHitAt <= d.RecentHitSeconds then
		return true
	end
	return false
end

function Policy.Decide(f: Facts): Decision
	local d, s = CoreLoop.Despawn, CoreLoop.Star
	if Policy.Protected(f) then
		return "Keep"
	end
	if f.role == "Star" then
		if not f.starFirstSeenAt then
			-- Never seen by its owner: treat as an unseen ambient so it cannot linger forever.
			if
				f.unseenSince
				and f.now - f.unseenSince >= d.AmbientUnseenSeconds
				and f.nearestHunterDistance > d.ProtectRadius
			then
				return "Retire"
			end
			return "Keep"
		end
		local age = f.now - f.starFirstSeenAt
		if age >= s.LifeSeconds then
			return "Dive" -- visible exit; allowed in view by design
		end
		if age >= s.LifeSeconds - s.LeavingWarnSeconds and not f.leavingSince then
			return "StartLeaving"
		end
		return "Keep"
	end
	if f.nearestHunterDistance <= d.ProtectRadius or not f.unseenSince then
		return "Keep"
	end
	local wait = if f.role == "Ambient" then d.AmbientUnseenSeconds else d.UnseenSeconds
	if f.now - f.unseenSince >= wait then
		return "Retire"
	end
	return "Keep"
end

return table.freeze(Policy)
