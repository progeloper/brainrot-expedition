--!strict
-- Camp Rework, Part E: Training (replaces the cart Speed upgrades). Behind TrainingV1Enabled.
-- Part B only binds the Training stall prompt; the bay, XP ticks and roller purchases land in Part E.
local Service = {}

function Service:BindPrompt(prompt: ProximityPrompt, _stall: Model)
	prompt:SetAttribute("CampTrainingPrompt", true)
	prompt:SetAttribute("BayOccupantUserId", 0)
end

return Service
