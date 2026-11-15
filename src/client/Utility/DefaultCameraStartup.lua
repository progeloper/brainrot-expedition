--!strict
-- One bounded cold-start handoff to PlayerModule. Never owns camera transforms.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Startup = {}
local timeoutSeconds = 8
local stableSeconds = 0.1

function Startup.Start(player: any, options: any?): any
	options = options or {}
	local world = options.Workspace or Workspace
	local players = options.Players or Players
	local heartbeat = options.Heartbeat or RunService.Heartbeat
	local clock = options.Clock or os.clock
	local started = clock()
	local state = { Status = "Waiting", Reason = "WAITING_FOR_SELF_CAMERA", Observations = 0 }
	local connection: RBXScriptConnection? = nil
	local candidateCamera, candidateHumanoid, candidateSince, candidateCount = nil, nil, 0, 0
	local function finish(status, reason)
		state.Status, state.Reason = status, reason
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
	function state.Cancel()
		if state.Status == "Waiting" then
			finish("Cancelled", "STARTUP_CANCELLED")
		end
	end
	function state.IsConnected()
		return connection ~= nil and connection.Connected
	end
	local function step()
		if state.Status ~= "Waiting" then
			return
		end
		state.Observations += 1
		if player.Parent ~= players then
			finish("Unavailable", "PLAYER_REMOVED")
			return
		end
		if clock() - started >= timeoutSeconds then
			finish("Unavailable", "SELF_CAMERA_TIMEOUT")
			return
		end
		local camera = world.CurrentCamera
		if camera and camera.Parent then
			if camera.CameraType ~= Enum.CameraType.Fixed and camera.CameraType ~= Enum.CameraType.Custom then
				finish("Owned", "EXISTING_CAMERA_MODE")
				return
			end
		end
		if
			player:GetAttribute("Phase13CinematicActive") == true
			or player:GetAttribute("ChariotTeamMenuOpen") == true
		then
			finish("Owned", "EXISTING_CAMERA_FLOW")
			return
		end
		local character = player.Character
		local humanoid = character and character.Parent and character:FindFirstChildOfClass("Humanoid")
		if humanoid and (humanoid.Sit or humanoid.SeatPart ~= nil) then
			finish("Owned", "SEATED_CAMERA_CONTEXT")
			return
		end
		if
			not camera
			or not camera.Parent
			or not humanoid
			or humanoid.Health <= 0
			or camera.CameraSubject ~= humanoid
		then
			candidateCamera, candidateHumanoid, candidateCount = nil, nil, 0
			return
		end
		if candidateCamera ~= camera or candidateHumanoid ~= humanoid then
			candidateCamera, candidateHumanoid = camera, humanoid
			candidateSince, candidateCount = clock(), 1
			return
		end
		candidateCount += 1
		if candidateCount < 2 or clock() - candidateSince < stableSeconds then
			return
		end
		if camera.CameraType == Enum.CameraType.Fixed then
			-- Only the observed engine cold-start default is normalized. Core camera
			-- scripts choose the view; cart/cinematic controllers retain their claims.
			camera.CameraType = Enum.CameraType.Custom
			finish("Repaired", "DEFAULT_FIXED_CAMERA")
		else
			finish("Ready", "DEFAULT_CAMERA_READY")
		end
	end
	connection = heartbeat:Connect(step)
	step()
	return state
end

return Startup
