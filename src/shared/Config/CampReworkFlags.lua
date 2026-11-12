--!strict
-- Camp Rework (owner-approved 11–12 Nov 2026) feature gates.
--   CampReworkV1Enabled  stalls, camp layout, floor, special weapons, weapon/cart sell-back
--   TrainingV1Enabled    Training stall + levels; removes the cart Speed upgrades
--   RebirthUiV2Enabled   "Rebirth" naming, YOU LOSE / YOU GET window, payback line, READY glow
-- Live servers read FeatureFlags only (all false until the owner flips them). In Studio each gate
-- defaults ON for preview (same pattern as WeaponTiersV2Preview): the ReplicatedStorage attribute
-- <Name>Preview = false turns a preview off. Values latch once per session so server and client
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
	return preview ~= false
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

-- Pure helper for tests: what a gate resolves to for given inputs.
function Flags.Resolve(flagValue: boolean, isStudio: boolean, previewAttribute: any): boolean
	if flagValue then
		return true
	end
	return isStudio and previewAttribute ~= false
end

return table.freeze(Flags)
