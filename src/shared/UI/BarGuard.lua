--!strict
-- Playtest Fixes 2 Part F (StableBars): pure decisions for progress bars, so a bar only moves when
-- its value changes. Used by StudPop.ProgressBar and Plate.StripedProgress.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BarGuard = {}

local config: any = nil
local flags: any = nil
local function load()
	if not config then
		config = require(ReplicatedStorage.Shared.Config.PlaytestFixes2).StableBars
		flags = require(ReplicatedStorage.Shared.Config.PlaytestFixes2Flags)
	end
end

function BarGuard.Enabled(): boolean
	load()
	return flags.Part("StableBars")
end

-- Skip a set() whose fraction moved less than `minDelta` and whose label did not change.
function BarGuard.ShouldUpdate(
	previous: number?,
	nextFrac: number,
	previousLabel: string?,
	nextLabel: string?,
	minDelta: number?
): boolean
	load()
	if previous == nil then
		return true
	end
	if nextLabel ~= nil and nextLabel ~= previousLabel then
		return true
	end
	return math.abs(nextFrac - previous) >= (minDelta or config.MinDelta)
end

-- Pop only when the bar crosses to full (not on every set while it is full).
function BarGuard.CrossedFull(previous: number?, nextFrac: number): boolean
	return nextFrac >= 1 and (previous == nil or previous < 1)
end

-- Tiny fills render as blobs: hide them.
function BarGuard.FillVisible(frac: number, hideBelow: number?): boolean
	load()
	return frac >= (hideBelow or config.HideBelow)
end

-- Phase (0..1) of a looping animation of `period` seconds at `now`, so a rebuilt bar continues its
-- stripe scroll where the old one was instead of restarting it.
function BarGuard.Phase(now: number, period: number): number
	return (now % period) / period
end

return table.freeze(BarGuard)
