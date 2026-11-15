--!strict
-- Core Loop V2 gate. Live servers read FeatureFlags.CoreLoopV2Enabled only (default false). In Studio
-- the loop previews only when ReplicatedStorage attribute CoreLoopV2Preview is explicitly true (the
-- CampReworkFlags rule). Each Part is additionally gated by CoreLoop.Flags.<Part>. Values latch once
-- per session so server and client never disagree mid-session. With the master gate off every caller
-- keeps today's behaviour byte for byte (F-0).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FeatureFlags = require(script.Parent.FeatureFlags)
local CoreLoop = require(script.Parent.CoreLoop)

local function resolve(): boolean
	if (FeatureFlags :: any).CoreLoopV2Enabled == true then
		return true
	end
	return RunService:IsStudio() and ReplicatedStorage:GetAttribute("CoreLoopV2Preview") == true
end

local enabled = resolve()
local overrides: { [string]: boolean } = {}

local Flags = {}

function Flags.Enabled(): boolean
	return enabled
end

-- True when the master gate is on and the named CoreLoop.Flags part is on.
function Flags.Part(name: string): boolean
	if not enabled then
		return false
	end
	local override = overrides[name]
	if override ~= nil then
		return override
	end
	return (CoreLoop.Flags :: any)[name] == true
end

-- Pure helper for tests.
function Flags.Resolve(flagValue: boolean, isStudio: boolean, previewAttribute: any): boolean
	return flagValue or (isStudio and previewAttribute == true)
end

-- Studio-only test pin (returns the previous master value).
function Flags._SetForTests(value: boolean, parts: { [string]: boolean }?): boolean
	assert(RunService:IsStudio(), "CoreLoopFlags._SetForTests is Studio-only")
	local previous = enabled
	enabled = value
	table.clear(overrides)
	for name, partValue in parts or {} do
		overrides[name] = partValue
	end
	return previous
end

return table.freeze(Flags)
