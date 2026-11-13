--!strict
-- Studio-only: hands the draft KeyframeSequences (ServerStorage.AnimationSources) to the
-- client review pen. Drafts are previewed with Studio-local ids; nothing is uploaded.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config.AnimationReview)

local Service = {}

function Service.Start()
	if not Config.IsOn() or ReplicatedStorage:FindFirstChild(Config.SourcesName) then
		return
	end
	local sources = ServerStorage:FindFirstChild("AnimationSources")
	if not sources then
		warn("[AnimationReview] ServerStorage.AnimationSources is missing; bake the drafts first")
		return
	end
	local copy = sources:Clone()
	copy.Name = Config.SourcesName
	copy.Parent = ReplicatedStorage
end

return Service
