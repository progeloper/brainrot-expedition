--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Safety = require(ReplicatedStorage.Shared.Config.CartMovementSafety)
local Config = require(ReplicatedStorage.Shared.Config.ChariotTeam)

local CartTeamPerformance = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Always start from the purchased-upgrade resolver's clean result. Neither a
-- previous team result nor the current Burst ceiling is an input baseline.
function CartTeamPerformance.Resolve(base: any, stats: any?, burstActive: boolean): any
	if base.status ~= "Ready" then return base end
	local result = table.clone(base)
	local speedMultiplier = if stats and finite(stats.speedMultiplier)
		then math.clamp(stats.speedMultiplier, 1, 1.10) else 1
	result.baseResolvedSpeed = math.min(base.resolvedSpeed, Safety.MaximumTravelSpeed)
	result.normalResolvedSpeed = math.min(base.resolvedSpeed * speedMultiplier, Safety.MaximumTravelSpeed)
	result.teamSpeedRatio = result.normalResolvedSpeed / result.baseResolvedSpeed
	result.hitMultiplier = if stats and finite(stats.hitMultiplier)
		then math.clamp(stats.hitMultiplier, 1, 5) else 1
	result.burstCapacity = if stats and finite(stats.burstCapacity)
		then math.clamp(stats.burstCapacity, 0, 8) else 0
	result.burstActive = burstActive and result.burstCapacity > 0
	result.resolvedSpeed = math.min(
		result.normalResolvedSpeed * (if result.burstActive then Config.Burst.SpeedMultiplier else 1),
		Safety.MaximumTravelSpeed
	)
	return table.freeze(result)
end

return table.freeze(CartTeamPerformance)
