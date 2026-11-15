--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tuning = require(ReplicatedStorage.Shared.Config.ChariotTeam).Burst

local CartBurstRuntime = {}

export type State = {
	Energy: number,
	Capacity: number,
	Active: boolean,
	LastUpdatedAt: number,
	RechargeEligibleAt: number,
	StopReason: string?,
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function CartBurstRuntime.Create(now: number): State
	assert(finite(now), "Burst clock must be finite")
	return {
		Energy = 0, Capacity = 0, Active = false,
		LastUpdatedAt = now, RechargeEligibleAt = now, StopReason = nil,
	}
end

local function stop(state: State, at: number, reason: string)
	if not state.Active then return end
	state.Active = false
	state.RechargeEligibleAt = at + Tuning.RechargeDelay
	state.StopReason = reason
end

-- Capacity changes happen AFTER elapsed time has been settled at the old
-- capacity. Equipping, buying and replacing cannot manufacture energy.
function CartBurstRuntime.Step(state: State, now: number, capacity: number, validDriver: boolean, braking: boolean): State
	assert(finite(now) and finite(capacity), "Burst time and capacity must be finite")
	now = math.max(now, state.LastUpdatedAt)
	local from = state.LastUpdatedAt
	if state.Active then
		local emptyAt = from + state.Energy / Tuning.DrainRate
		if emptyAt <= now then
			state.Energy = 0
			stop(state, emptyAt, "EMPTY")
			state.Energy = math.min(state.Capacity,
				math.max(0, now - state.RechargeEligibleAt) * Tuning.RechargeRate)
		else
			state.Energy = math.max(0, state.Energy - (now - from) * Tuning.DrainRate)
		end
	else
		local rechargeFrom = math.max(from, state.RechargeEligibleAt)
		state.Energy = math.min(state.Capacity,
			state.Energy + math.max(0, now - rechargeFrom) * Tuning.RechargeRate)
	end
	state.LastUpdatedAt = now
	state.Capacity = math.clamp(capacity, 0, 8)
	state.Energy = math.min(state.Energy, state.Capacity)
	if state.Capacity <= 0 then stop(state, now, "NO_PROVIDER")
	elseif state.Energy <= 0 then stop(state, now, "EMPTY")
	elseif braking then stop(state, now, "BRAKING")
	elseif not validDriver then stop(state, now, "INVALID_DRIVER") end
	return state
end

function CartBurstRuntime.Stop(state: State, now: number, reason: string)
	CartBurstRuntime.Step(state, now, state.Capacity, true, false)
	stop(state, math.max(now, state.LastUpdatedAt), reason)
end

function CartBurstRuntime.IsBound(ownerState: any, cart: any, driver: any, revision: number?): boolean
	return ownerState.Cart == cart and ownerState.Driver == driver and ownerState.DriverRevision == revision
end

function CartBurstRuntime.Bind(ownerState: any, cart: any, driver: any, revision: number?, now: number)
	if not CartBurstRuntime.IsBound(ownerState, cart, driver, revision) then
		CartBurstRuntime.Stop(ownerState.Runtime, now, "DRIVER_OR_CART_CHANGED")
	end
	ownerState.Cart = cart
	ownerState.Driver = driver
	ownerState.DriverRevision = revision
end

function CartBurstRuntime.Toggle(state: State, now: number, capacity: number, validDriver: boolean, braking: boolean): (boolean, string)
	CartBurstRuntime.Step(state, now, capacity, validDriver, braking)
	if not validDriver then return false, "INVALID_DRIVER" end
	if braking then return false, "BRAKING" end
	if state.Active then
		stop(state, now, "MANUAL")
		return true, "STOPPED"
	end
	if state.Capacity <= 0 then return false, "NO_PROVIDER" end
	if state.Energy + 1e-9 < Tuning.MinimumEnergy then return false, "LOW_ENERGY" end
	state.Active = true
	state.StopReason = nil
	return true, "STARTED"
end

function CartBurstRuntime.RechargeState(state: State, now: number): string
	if state.Capacity <= 0 then return "UNAVAILABLE" end
	if state.Active then return "ACTIVE" end
	if state.Energy >= state.Capacity then return "FULL" end
	if now < state.RechargeEligibleAt then return "COOLDOWN" end
	return "RECHARGING"
end

return table.freeze(CartBurstRuntime)
