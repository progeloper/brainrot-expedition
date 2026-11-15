--!strict
-- Legs training gate (Playtest Fixes 2, Part G). Live servers read FeatureFlags.LegsTrainingV1Enabled
-- only (false until the owner flips it). In Studio it stays OFF unless ReplicatedStorage
-- LegsTrainingV1Preview = true is set before Play (opt-in). Latched once per session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FeatureFlags = require(script.Parent.FeatureFlags)

local Flags = {}

function Flags.Resolve(flagValue: boolean, isStudio: boolean, previewAttribute: any): boolean
	if flagValue then
		return true
	end
	return isStudio and previewAttribute == true
end

local enabled = Flags.Resolve(
	(FeatureFlags :: any).LegsTrainingV1Enabled == true,
	RunService:IsStudio(),
	ReplicatedStorage:GetAttribute("LegsTrainingV1Preview")
)

function Flags.Enabled(): boolean
	return enabled
end

-- Test-only override (Studio only).
function Flags._SetForTests(value: boolean): boolean
	assert(RunService:IsStudio(), "LegsTrainingFlags._SetForTests is Studio-only")
	local previous = enabled
	enabled = value
	return previous
end

return table.freeze(Flags)
