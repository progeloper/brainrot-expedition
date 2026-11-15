--!strict
-- Playtest Fixes 2 gates. Live servers read FeatureFlags.PlaytestFixesV2Enabled only (false until the
-- owner flips it). In Studio it stays OFF unless the ReplicatedStorage attribute
-- PlaytestFixesV2Preview = true is set before Play (opt-in, so Studio matches devices by default).
-- Values latch once per session so server and client never disagree mid-session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FeatureFlags = require(script.Parent.FeatureFlags)
local Config = require(script.Parent.PlaytestFixes2)

export type Part = "InputUnstick" | "JumpHopOut" | "CashPads" | "StableBars"

local Flags = {}

-- Pure helper for tests.
function Flags.Resolve(flagValue: boolean, isStudio: boolean, previewAttribute: any): boolean
	if flagValue then
		return true
	end
	return isStudio and previewAttribute == true
end

local enabled = Flags.Resolve(
	(FeatureFlags :: any).PlaytestFixesV2Enabled == true,
	RunService:IsStudio(),
	ReplicatedStorage:GetAttribute("PlaytestFixesV2Preview")
)

function Flags.Enabled(): boolean
	return enabled
end

function Flags.Part(name: Part): boolean
	return enabled and (Config.Parts :: any)[name] == true
end

-- Test-only override (Studio only).
function Flags._SetForTests(value: boolean): boolean
	assert(RunService:IsStudio(), "PlaytestFixes2Flags._SetForTests is Studio-only")
	local previous = enabled
	enabled = value
	return previous
end

return table.freeze(Flags)
