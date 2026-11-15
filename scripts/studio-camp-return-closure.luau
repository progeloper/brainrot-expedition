--!nocheck
-- Temporary Development server Script; deliberately outside the Rojo tree.
-- Controlled route evidence, not normal spawning or progression pacing.
assert(game:GetService("RunService"):IsStudio(), "Studio only")
assert(
	require(game.ReplicatedStorage.Shared.Config.Environment).Name == "Development",
	"Development only"
)
local S = game.ServerScriptService.Server.Systems
local W = require(S.DevelopmentBrainrotSpawner)
local N = require(S.NaturalTerritory)
local Regions = require(S.RegionSpawnCatalog)
local Http = game:GetService("HttpService")
script:SetAttribute("CampReturnClosureHarness", true)
local preserveOnFailure = script:GetAttribute("PreserveOnFailure") == true
local definitions = if script:GetAttribute("ForestOnly") == true
	then { { "REGION_FOREST", "BRT_010" } }
	else {
		{ "REGION_FOREST", "BRT_010" },
		{ "REGION_GLITCH", "BRT_023" },
		{ "REGION_JUNGLE", "BRT_011" },
		{ "REGION_SWAMP", "BRT_014" },
		{ "REGION_ARCTIC", "BRT_008" },
		{ "REGION_VOLCANO", "BRT_007" },
		{ "REGION_BEACH", "BRT_015" },
	}
-- Resume only an interrupted diagnostic sequence, without replaying completed
-- routes or changing the production controller/spawning configuration.
local startRegion = script:GetAttribute("StartRegionId")
if startRegion ~= nil then
	local startIndex = nil
	for index, definition in definitions do
		if definition[1] == startRegion then
			startIndex = index
			break
		end
	end
	assert(startIndex, "Unknown diagnostic start region")
	for _ = 1, startIndex - 1 do
		table.remove(definitions, 1)
	end
end
local rows, currentModel, sample, recentDecisions = {}, nil, {}, {}
local previousDecisionPosition, previousDecisionAt = nil, nil
local originalSelect = N.SelectReturnStep
N.SelectReturnStep = function(...)
	local args = table.pack(...)
	local observed = currentModel and (args[1] - currentModel:GetPivot().Position).Magnitude < 0.01
	local tested, rejected, lastRejectedCandidate, lastRejectedReason = 0, 0, nil, nil
	if observed then
		local originalSafe = args[5]
		args[5] = function(candidate)
			local result = table.pack(originalSafe(candidate))
			tested += 1
			if not result[1] then
				rejected += 1
				lastRejectedCandidate = tostring(candidate)
				lastRejectedReason = string.sub(
					tostring(result[3] or result[2] or "NOT_EXPOSED_BY_SAFETY_CALLBACK"),
					1,
					512
				)
			end
			return table.unpack(result, 1, result.n)
		end
	end
	local result = originalSelect(table.unpack(args, 1, args.n))
	if observed then
		local state = args[6]
		local now = os.clock()
		local recentPositions = {}
		for index = math.max(1, #(state and state.RecentPositions or {}) - 9), #(state and state.RecentPositions or {}) do
			table.insert(recentPositions, tostring(state.RecentPositions[index]))
		end
		sample = {
			decisions = state and state.DecisionCount or 0,
			noProgress = state and state.NoProgressDecisions or 0,
			stuck = state and state.ReturnStuck or false,
			distance = state and state.LastHomeDistance,
			escapeForward = state and state.EscapeForward and tostring(state.EscapeForward)
				or false,
			escapeSide = state and state.EscapeSide or false,
			escapeTurns = state and state.EscapeTurns or false,
			bestHomeDistance = state and state.BestHomeDistance or false,
			escapePeakDistance = state and state.EscapePeakDistance or false,
			lastSelectedAngle = state and state.LastSelectedAngle or false,
			recentPositions = recentPositions,
			decisionPosition = tostring(args[1]),
			destination = tostring(args[2]),
			selectedGoal = result and tostring(result) or false,
			selectedDistance = result and (result - args[1]).Magnitude or false,
			selectorReturnedNil = result == nil,
			actualDistanceSinceDecision = previousDecisionPosition and (
				args[1] - previousDecisionPosition
			).Magnitude or false,
			decisionGapSeconds = previousDecisionAt and now - previousDecisionAt or false,
			testedCandidates = tested,
			rejectedCandidates = rejected,
			lastRejectedCandidate = lastRejectedCandidate or false,
			lastRejectedReason = state and state.LastRejectedReason or lastRejectedReason or false,
		}
		previousDecisionPosition, previousDecisionAt = args[1], now
		table.insert(recentDecisions, sample)
		if #recentDecisions > 32 then
			table.remove(recentDecisions, 1)
		end
		script:SetAttribute("DecisionTrace", Http:JSONEncode(recentDecisions))
	end
	return result
end

local ok, failure = xpcall(function()
	-- Retire only startup diagnostic pilots, never natural or player-released members.
	for _, model in W.GetWorldModels() do
		if string.match(model.Name, "_Pilot_%d+$") then
			W.DestroyWorldForTesting(model:GetAttribute("ItemId"))
		end
	end
	for _, definition in definitions do
		local pose = CFrame.new(0, 3, -30)
		local record =
			assert(W.CreateWorldRecord(definition[2], "ClosureRoute_" .. definition[1], pose))
		local prepared = assert(W.PrepareWorldRepresentation(record, pose))
		local safe = W.FindSafeReleasePose(prepared, pose, {}, true)
		assert(safe, "No safe private initial release pose")
		prepared.Model:PivotTo(safe)
		currentModel = assert(W.ActivatePreparedWorld(prepared))
		sample, recentDecisions = {}, {}
		previousDecisionPosition, previousDecisionAt = nil, nil
		local started = os.clock()
		local row = {
			id = record.ItemId,
			species = definition[2],
			home = definition[1],
			start = tostring(safe.Position),
			started = currentModel:GetAttribute("CampReturnRegionId") == definition[1],
		}
		repeat
			task.wait(0.5)
			row.elapsed = os.clock() - started
			row.position = tostring(currentModel:GetPivot().Position)
			for key, value in sample do
				row[key] = value
			end
			script:SetAttribute("Current", Http:JSONEncode(row))
		until currentModel:GetAttribute("CampReturnRegionId") == nil
			or sample.stuck
			or row.elapsed >= 600
		local region = Regions.GetRegionAtPosition(currentModel:GetPivot().Position)
		row.region = region and region.id
		row.sameId = currentModel:GetAttribute("ItemId") == record.ItemId
		row.cleared = currentModel:GetAttribute("CampReturnRegionId") == nil
		local ending = currentModel:GetPivot().Position
		if row.cleared then
			task.wait(6)
		end
		row.roamed = row.cleared and (currentModel:GetPivot().Position - ending).Magnitude > 0.1
		row.pass = row.started
			and row.sameId
			and row.cleared
			and row.region == row.home
			and row.roamed
		table.insert(rows, row)
		script:SetAttribute("Results", Http:JSONEncode(rows))
		print("[CAMP_RETURN_CLOSURE] " .. Http:JSONEncode(row))
		if preserveOnFailure and not row.pass then
			-- Keep the exact failed runtime controller/model available for inspection.
			-- Its identity is explicitly recorded for later owner-coordinated cleanup.
			script:SetAttribute("PreservedFailureModel", currentModel:GetFullName())
			script:SetAttribute("PreservedFailureItemId", record.ItemId)
			break
		end
		W.DestroyWorldForTesting(record.ItemId)
		currentModel = nil
	end
end, debug.traceback)
N.SelectReturnStep = originalSelect
if currentModel then
	if preserveOnFailure then
		script:SetAttribute("PreservedFailureModel", currentModel:GetFullName())
		script:SetAttribute("PreservedFailureItemId", currentModel:GetAttribute("ItemId"))
	else
		W.DestroyWorldForTesting(currentModel:GetAttribute("ItemId"))
	end
end
script:SetAttribute("Done", true)
script:SetAttribute("Error", if ok then nil else tostring(failure))
assert(ok, failure)
