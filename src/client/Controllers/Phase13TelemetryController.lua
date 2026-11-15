--!strict
-- A sampled window, one small report per minute. No device/hardware inference.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Input = game:GetService("UserInputService")
local Rules = require(RS.Shared.Utility.Phase13TelemetryRules)
local Visibility = require(script.Parent.RegionVisibilityController)
local CreaturePresentation = require(script.Parent.CreaturePresentationController)
local Controller = {}
local player = Players.LocalPlayer
local connections = {}
local running = false
local focused: boolean? = nil
local window: any = nil
local lastSample = 0
local remote: RemoteEvent? = nil
local previousEntries, previousExits = 0, 0
local function reset(at: number)
	window = { at = at, lastAt = at, samples = {}, pauseSeconds = 0, pauseKnown = false, focusKnown = true }
	lastSample = at
end
local function report(at: number)
	local sample = Rules.Summarize(window.samples)
	if not sample or not remote then
		reset(at)
		return
	end
	local v = Visibility.GetDiagnostics()
	sample.visibility = {
		visible = v.visible,
		detailed = v.detailed,
		reduced = v.reduced,
		hidden = v.hidden,
		interestSubscriptions = v.interestSubscriptions,
		renderDistance = v.renderDistance,
	}
	local gotProtocol, protocol = pcall(CreaturePresentation.GetDiagnostics)
	if gotProtocol and type(protocol) == "table" then
		local entries, exits = protocol.interestEntries, protocol.interestExits
		if type(entries) == "number" and type(exits) == "number" then
			sample.visibility.interestEntries =
				math.clamp(if entries >= previousEntries then entries - previousEntries else entries, 0, 1000000)
			sample.visibility.interestExits =
				math.clamp(if exits >= previousExits then exits - previousExits else exits, 0, 1000000)
			previousEntries, previousExits = entries, exits
		end
		sample.visibility.authorityProxies = protocol.authorityProxies
		sample.visibility.localFullModels = protocol.localFullModels
		sample.visibility.localReducedModels = protocol.localReducedModels
		sample.visibility.cacheParts = protocol.cache and protocol.cache.cachedParts
	end
	sample.focusKnown = window.focusKnown
	sample.focused = if window.focusKnown then true else nil
	sample.windowSeconds = at - window.at
	local ok, memory = pcall(Stats.GetTotalMemoryUsageMb, Stats)
	if ok and type(memory) == "number" and memory > 0 then
		sample.memoryMB = memory
	end
	if window.pauseKnown then
		sample.streamPauseSeconds = window.pauseSeconds
	end
	local got, quality = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if got and type(quality) == "number" and quality >= 0 and quality <= 10 then
		sample.graphicsTier = quality
	end
	local clean = Rules.Validate(sample)
	if clean then
		remote:FireServer(clean)
	end
	reset(at)
end
function Controller.Start(): boolean
	if running then
		return false
	end
	running = true
	focused = nil
	previousEntries, previousExits = 0, 0
	local folder = RS:WaitForChild("Remotes", 15)
	local found = folder and folder:WaitForChild("Phase13ClientObservation", 15)
	if not running or not found or not found:IsA("RemoteEvent") then
		running = false
		return false
	end
	remote = found
	table.insert(
		connections,
		Input.WindowFocused:Connect(function()
			focused = true
		end)
	)
	table.insert(
		connections,
		Input.WindowFocusReleased:Connect(function()
			focused = false
		end)
	)
	table.insert(
		connections,
		Run.RenderStepped:Connect(function(dt)
			local at = os.clock()
			if
				player:GetAttribute("PlayerDataStatus") ~= "Ready"
				or player:GetAttribute("PlayerWorldStatus") ~= "Ready"
			then
				window = nil
				return
			end
			if not window then
				reset(at)
			end
			local gap = math.max(0, at - window.lastAt)
			window.lastAt = at
			local got, paused = pcall(function()
				return player.GameplayPaused
			end)
			if got and type(paused) == "boolean" then
				window.pauseKnown = true
				if paused then
					window.pauseSeconds += gap
				end
			end
			if focused ~= false and at - lastSample >= 0.1 and #window.samples < 600 then
				lastSample = at
				if dt > 0 and dt <= 2 then
					if focused == nil then
						window.focusKnown = false
					end
					table.insert(window.samples, dt * 1000)
				end
			end
			if at - window.at >= 60 then
				report(at)
			end
		end)
	)
	return true
end
function Controller.Stop()
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	window = nil
	remote = nil
end
return Controller
