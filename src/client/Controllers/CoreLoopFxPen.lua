--!strict
-- Core Loop V2 review pen (L6), client side: while ReplicatedStorage.CoreLoopFxPen is true (Studio QA), every
-- review group renders its full look. The pen itself (platform, plinths, looping dummies) is built by the
-- server (Services/CoreLoopFxPenServer) so it uses the real templates and the live attribute paths.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FxController = require(script.Parent.CoreLoopFxController)

local Pen = {}

function Pen.Start()
	if not RunService:IsStudio() then
		return
	end
	local function refresh()
		FxController.SetPen(ReplicatedStorage:GetAttribute("CoreLoopFxPen") == true)
	end
	ReplicatedStorage:GetAttributeChangedSignal("CoreLoopFxPen"):Connect(refresh)
	refresh()
	-- QA capture camera: while ReplicatedStorage.CoreLoopPenCamera holds a CFrame, keep the camera there.
	local camera = workspace.CurrentCamera
	RunService:BindToRenderStep("CoreLoopPenCamera", Enum.RenderPriority.Last.Value, function()
		local hold = ReplicatedStorage:GetAttribute("CoreLoopPenCamera")
		if typeof(hold) == "CFrame" then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = hold
		end
	end)
end

return Pen
