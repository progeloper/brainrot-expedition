--!strict

-- Reuse BrainrotInteractionController's compact chase feedback renderer.
local Players = game:GetService("Players")
local Feedback = {}

function Feedback.GetEvent(): BindableEvent
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = gui:FindFirstChild("Phase10Feedback")
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local event = Instance.new("BindableEvent")
	event.Name, event.Parent = "Phase10Feedback", gui
	return event
end

function Feedback.Show(message: any)
	if type(message) == "string" and message ~= "" then
		Feedback.GetEvent():Fire(message)
	end
end

return table.freeze(Feedback)
