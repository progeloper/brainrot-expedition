--!strict
-- Every value here is explicitly untrusted and isolated from gameplay decisions.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Rules = require(RS.Shared.Utility.Phase13TelemetryRules)
local Analytics = require(script.Parent.Phase13AnalyticsService)
local Lifecycle = require(script.Parent.PlayerWorldLifecycle)
local Service = {}
local started = false
local acceptedAt = {}
local cinematicAt = {}
local assetReported = {}
local connection: RBXScriptConnection? = nil
local removingConnection: RBXScriptConnection? = nil
local metricCategories = {
	p50Ms = "FrameP50",
	p90Ms = "FrameP90",
	memoryMB = "MemoryMB",
	streamPauseSeconds = "StreamPauseSeconds",
	graphicsTier = "GraphicsTier",
}
local visibilityCategories = {
	interestEntries = "InterestEntries",
	interestExits = "InterestExits",
	authorityProxies = "AuthorityProxies",
	localFullModels = "LocalFullModels",
	localReducedModels = "LocalReducedModels",
	cacheParts = "TemplateCacheParts",
	visible = "VisibleModels",
	detailed = "DetailedModels",
	reduced = "ReducedModels",
	hidden = "HiddenModels",
	interestSubscriptions = "InterestSubscriptions",
	renderDistance = "RenderDistance",
}
function Service:Accept(player: Player, report: any, at: number?): boolean
	if player.Parent ~= Players then
		return false
	end
	if type(report) == "table" and report.kind == "CinematicAsset" then
		local category = Rules.ValidateAssetFailure(report)
		if not category or assetReported[player] then
			return false
		end
		assetReported[player] = true
		return Analytics:Record(player, "CinematicOutcome", 1, { category = category, result = "Unavailable" })
	end
	if type(report) == "table" and report.kind == "Cinematic" then
		local t = at or os.clock()
		if t - (cinematicAt[player] or -math.huge) < 1 then
			return false
		end
		cinematicAt[player] = t
		return Analytics:ObserveCinematicOutcome(player, report)
	end
	local timestamp = at or os.clock()
	if
		player.Parent ~= Players
		or not Lifecycle:IsReady(player)
		or timestamp - (acceptedAt[player] or -math.huge) < 55
	then
		return false
	end
	-- Rate limit invalid packets too; hostile clients cannot make an unbounded validator loop.
	acceptedAt[player] = timestamp
	local clean = Rules.Validate(report)
	if not clean then
		return false
	end
	pcall(
		Analytics.Record,
		Analytics,
		player,
		"PerformanceSummary",
		1,
		{ category = if clean.focusKnown then "FocusKnown" else "FocusUnknown", result = "Untrusted" }
	)
	for key, category in metricCategories do
		if clean[key] ~= nil then
			pcall(
				Analytics.Record,
				Analytics,
				player,
				"PerformanceSummary",
				clean[key],
				{ category = category, result = "Untrusted" }
			)
		end
	end
	for index, category in { "FrameUnder16", "Frame16To33", "Frame33To50", "FrameOver50" } do
		pcall(
			Analytics.Record,
			Analytics,
			player,
			"PerformanceSummary",
			clean.bands[index],
			{ category = category, result = "Untrusted" }
		)
	end
	for key, category in visibilityCategories do
		if clean.visibility[key] == nil then
			continue
		end
		pcall(
			Analytics.Record,
			Analytics,
			player,
			"VisibilitySummary",
			clean.visibility[key],
			{ category = category, result = "Untrusted" }
		)
	end
	return true
end
function Service:Start(): boolean
	if started then
		return false
	end
	started = true
	local folder = RS:WaitForChild("Remotes")
	local remote = folder:FindFirstChild("Phase13ClientObservation") or Instance.new("RemoteEvent")
	assert(remote:IsA("RemoteEvent"), "Phase13ClientObservation must be a RemoteEvent")
	remote.Name = "Phase13ClientObservation"
	remote.Parent = folder
	connection = remote.OnServerEvent:Connect(function(player, report)
		self:Accept(player, report)
	end)
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		acceptedAt[player] = nil
		cinematicAt[player] = nil
		assetReported[player] = nil
	end)
	return true
end
function Service:Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if removingConnection then
		removingConnection:Disconnect()
		removingConnection = nil
	end
	table.clear(acceptedAt)
	table.clear(cinematicAt)
	table.clear(assetReported)
	started = false
end

return Service
