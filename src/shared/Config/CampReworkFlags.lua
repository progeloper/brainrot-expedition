--!strict
-- Camp Rework (owner-approved 11–12 Nov 2026) feature gates.
--   CampReworkV1Enabled  stalls, camp layout, floor, special weapons, weapon/cart sell-back
--   TrainingV1Enabled    Training stall + levels; removes the cart Speed upgrades
--   RebirthUiV2Enabled   "Rebirth" naming, YOU LOSE / YOU GET window, payback line, READY glow
-- Live servers read FeatureFlags only (all false until the owner flips them). In Studio a gate
-- previews only when the ReplicatedStorage attribute <Name>Preview is explicitly true (opt-in, the
-- same rule as DriveAndHuntFlags and WeaponTiersV2Preview; Playtest Fixes 2 Part E, 14 Nov 2026), so
-- an ordinary Studio Play matches a device. Values latch once per session so server and client
-- never disagree mid-session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FeatureFlags = require(script.Parent.FeatureFlags)

export type Gate = "CampReworkV1Enabled" | "TrainingV1Enabled" | "RebirthUiV2Enabled"

local GATES: { Gate } = { "CampReworkV1Enabled", "TrainingV1Enabled", "RebirthUiV2Enabled" }

local function resolve(name: Gate): boolean
	if (FeatureFlags :: any)[name] == true then
		return true
	end
	if not RunService:IsStudio() then
		return false
	end
	local preview = ReplicatedStorage:GetAttribute((string.gsub(name, "Enabled$", "Preview")))
	return preview == true
end

local latched: { [string]: boolean } = {}
for _, name in GATES do
	latched[name] = resolve(name)
end

local Flags = {}

function Flags.CampRework(): boolean
	return latched.CampReworkV1Enabled
end

function Flags.Training(): boolean
	return latched.TrainingV1Enabled
end

function Flags.RebirthUi(): boolean
	return latched.RebirthUiV2Enabled
end

-- Test-only: pin a gate for the duration of a legacy spec (Studio only; returns the previous value).
-- Live servers never call this, and it refuses outside Studio.
function Flags._SetForTests(name: Gate, value: boolean): boolean
	assert(RunService:IsStudio(), "CampReworkFlags._SetForTests is Studio-only")
	assert(latched[name] ~= nil, "unknown gate")
	local previous = latched[name]
	latched[name] = value
	return previous
end

-- Pure helper for tests: what a gate resolves to for given inputs.
function Flags.Resolve(flagValue: boolean, isStudio: boolean, previewAttribute: any): boolean
	if flagValue then
		return true
	end
	return isStudio and previewAttribute == true
end

return table.freeze(Flags)
