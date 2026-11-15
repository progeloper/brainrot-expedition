--!strict
-- Playtest Fixes v1 gates. Live servers read FeatureFlags.PlaytestFixesV1Enabled only (false until the
-- owner flips it). In Studio it stays OFF too unless the ReplicatedStorage attribute
-- PlaytestFixesV1Preview = true is set before Play (opt-in, so ordinary Studio sessions are unchanged).
-- Values latch once per session so server and client never disagree mid-session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FeatureFlags = require(script.Parent.FeatureFlags)
local Config = require(script.Parent.PlaytestFixes)

export type Part =
	"MapStuds"
	| "StallPoses"
	| "WeaponFx"
	| "TrainPlace"
	| "SizeLadder"
	| "GemsStall"

local Flags = {}

-- Pure helper for tests.
function Flags.Resolve(flagValue: boolean, isStudio: boolean, previewAttribute: any): boolean
	if flagValue then
		return true
	end
	return isStudio and previewAttribute == true
end

local enabled = Flags.Resolve(
	(FeatureFlags :: any).PlaytestFixesV1Enabled == true,
	RunService:IsStudio(),
	ReplicatedStorage:GetAttribute("PlaytestFixesV1Preview")
)

function Flags.Enabled(): boolean
	return enabled
end

function Flags.Part(name: Part): boolean
	return enabled and (Config.Parts :: any)[name] == true
end

return table.freeze(Flags)
