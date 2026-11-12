--!strict
-- Drive-and-Hunt gates. Live servers read FeatureFlags.DriveAndHuntV1Enabled only (false until the
-- owner flips it). In Studio the feature stays OFF too, unless the ReplicatedStorage attribute
-- DriveAndHuntV1Preview = true is set before Play (opt-in, so ordinary Studio sessions are
-- unchanged). Values latch once per session so server and client never disagree mid-session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FeatureFlags = require(script.Parent.FeatureFlags)
local Config = require(script.Parent.DriveAndHunt)

export type Part = "GateLaunch" | "SwitchButton" | "AutoLock" | "ScoopFx" | "Hints"

local Flags = {}

-- Pure helper for tests.
function Flags.Resolve(flagValue: boolean, isStudio: boolean, previewAttribute: any): boolean
	if flagValue then
		return true
	end
	return isStudio and previewAttribute == true
end

local enabled = Flags.Resolve(
	FeatureFlags.DriveAndHuntV1Enabled,
	RunService:IsStudio(),
	ReplicatedStorage:GetAttribute("DriveAndHuntV1Preview")
)

function Flags.Enabled(): boolean
	return enabled
end

function Flags.Part(name: Part): boolean
	return enabled and (Config :: any)[name] == true
end

return table.freeze(Flags)
