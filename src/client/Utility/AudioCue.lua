--!strict
-- Presentation-only bridge to AudioController for other client controllers.
-- A no-op when the audio engine is absent or not started (FeatureFlags.GameAudioEnabled = false).
local AudioCue = {}

local controller: any = nil
local resolved = false

local function resolve()
	if not resolved then
		resolved = true
		local controllers = script.Parent.Parent:FindFirstChild("Controllers")
		local module = controllers and controllers:FindFirstChild("AudioController")
		if module and module:IsA("ModuleScript") then
			local ok, value = pcall(require, module)
			if ok and type(value) == "table" then
				controller = value
			end
		end
	end
end

function AudioCue.Play(id: string, options: any?)
	resolve()
	if controller and type(controller.Play) == "function" then
		controller.Play(id, options)
	end
end

-- Trend test: a wild awake brainrot is close to the player (the controller rate-limits the chant).
function AudioCue.Near(speciesId: string, position: Vector3)
	resolve()
	if controller and type(controller.NearBrainrot) == "function" then
		controller.NearBrainrot(speciesId, position)
	end
end

return AudioCue
