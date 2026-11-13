--!strict
-- Animation review pen (rig + animation brief v5, E.3). Studio only, off by default.
-- To open it: set ReplicatedStorage.AnimationReviewPen = true (attribute) before Play.
-- Nothing here runs in a live server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationReview = {
	AnimationReviewPen = false,
	Origin = Vector3.new(-159, 260, -104), -- a platform high above the Camp
	SourcesName = "AnimationReviewSources",
}

function AnimationReview.IsOn(): boolean
	return RunService:IsStudio()
		and (
			AnimationReview.AnimationReviewPen
			or ReplicatedStorage:GetAttribute("AnimationReviewPen") == true
		)
end

return table.freeze(AnimationReview)
