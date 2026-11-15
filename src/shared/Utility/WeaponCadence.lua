--!strict

-- Pure, session-local cadence arithmetic shared by every capture weapon. The
-- state is intentionally not persisted and does not depend on a Tool instance.

local WeaponCadence = {}

local function finiteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and math.abs(value) < math.huge
end

local function finitePositive(value: any): boolean
	return finiteNonNegative(value) and value > 0
end

function WeaponCadence.EarliestNextShot(state: any?, selectedIntervalSeconds: number): number?
	if not finitePositive(selectedIntervalSeconds) then
		return nil
	end
	if state == nil then
		return 0
	end
	if type(state) ~= "table" then
		return nil
	end
	local last = state.lastAcceptedShotAt
	local nextFire = state.nextFireAt
	if not finiteNonNegative(last) or not finiteNonNegative(nextFire) then
		return nil
	end
	return math.max(nextFire, last + selectedIntervalSeconds)
end

function WeaponCadence.CanAccept(
	state: any?,
	now: number,
	selectedIntervalSeconds: number
): (boolean, number?)
	if not finiteNonNegative(now) then
		return false, nil
	end
	local earliest = WeaponCadence.EarliestNextShot(state, selectedIntervalSeconds)
	if earliest == nil then
		return false, nil
	end
	return now >= earliest, earliest
end

function WeaponCadence.Accept(now: number, shotIntervalSeconds: number): any?
	if not finiteNonNegative(now) or not finitePositive(shotIntervalSeconds) then
		return nil
	end
	return table.freeze({
		lastAcceptedShotAt = now,
		nextFireAt = now + shotIntervalSeconds,
	})
end

return table.freeze(WeaponCadence)
