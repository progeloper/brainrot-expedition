--!nocheck
-- Explicitly installed temporary Development diagnostic. No Bootstrap/storage;
-- uses the production factory, registry and heartbeat movement, one target only.
assert(game:GetService("RunService"):IsStudio() and game.PlaceId == 91958083796436)
local S = game.ServerScriptService.Server.Systems
local W, N, R, C =
	require(S.DevelopmentBrainrotSpawner),
	require(S.NaturalTerritory),
	require(S.DevelopmentBrainrotRoaming),
	require(S.RegionSpawnCatalog)
local Http = game:GetService("HttpService")
local m, state, trace
local original = N.SelectReturnStep
N.SelectReturnStep = function(...)
	local a = table.pack(...)
	local observed = m and (a[1] - m:GetPivot().Position).Magnitude < 0.01
	local candidates = {}
	if observed then
		local safe = a[5]
		a[5] = function(p)
			local result = table.pack(safe(p))
			local frame, size = R._TestCampReturnRouteEnvelope(m, a[1], p, a[1].Y)
			local blocked, _, owner = C.IsProtectedForCampReturn(frame, size)
			table.insert(candidates, {
				position = tostring(p),
				distance = (p - a[1]).Magnitude,
				accepted = result[1],
				protected = blocked,
				owner = owner,
				reason = result[2],
			})
			return table.unpack(result, 1, result.n)
		end
	end
	local result = original(table.unpack(a, 1, a.n))
	if observed then
		state = a[6]
		local recent = {}
		for _, p in state.RecentPositions do
			table.insert(recent, { p.X, p.Y, p.Z })
		end
		local row = {
			decision = state.DecisionCount,
			position = { a[1].X, a[1].Y, a[1].Z },
			home = { a[2].X, a[2].Y, a[2].Z },
			distance = state.LastHomeDistance,
			side = state.EscapeSide,
			turns = state.EscapeTurns,
			forward = state.EscapeForward and { state.EscapeForward.X, 0, state.EscapeForward.Z },
			noProgress = state.NoProgressDecisions,
			stuck = state.ReturnStuck,
			recent = recent,
			candidates = candidates,
			selected = result and tostring(result),
			blocker = state.Blocker and tostring(state.Blocker),
			flips = state.BlockerSideFlips,
		}
		table.insert(trace, row)
		if #trace > 180 then
			table.remove(trace, 1)
		end
		script:SetAttribute("Latest", Http:JSONEncode(row))
		if state.ReturnStuck then
			print("[BRT016_ROOT_TERMINAL] " .. Http:JSONEncode(row))
		end
	end
	return result
end
local ok, err = xpcall(function()
	R.Start()
	local pose =
		CFrame.new(script:GetAttribute("StartX") or 0, 3, script:GetAttribute("StartZ") or -30)
	local record = assert(W.CreateWorldRecord("BRT_016", "BRT016_RootDiagnostic", pose))
	local prepared = assert(W.PrepareWorldRepresentation(record, pose))
	local safe = assert(W.FindSafeReleasePose(prepared, pose, {}, true))
	prepared.Model:PivotTo(safe)
	trace = {}
	m = assert(W.ActivatePreparedWorld(prepared))
	script:SetAttribute("ItemId", record.ItemId)
	local start = os.clock()
	repeat
		task.wait(0.5)
		script:SetAttribute("Position", tostring(m:GetPivot().Position))
	until m:GetAttribute("CampReturnRegionId") == nil
		or (state and state.ReturnStuck)
		or os.clock() - start > 360
	local p = m:GetPivot().Position
	local region = C.GetRegionAtPosition(p)
	local result = {
		elapsed = os.clock() - start,
		position = tostring(p),
		region = region and region.id,
		sameId = m:GetAttribute("ItemId") == record.ItemId,
		cleared = m:GetAttribute("CampReturnRegionId") == nil,
		decisions = state and state.DecisionCount,
		stuck = state and state.ReturnStuck,
		population = W.GetPopulationSnapshot(),
	}
	script:SetAttribute("Result", Http:JSONEncode(result))
	-- Bounded trace retained only on this explicit diagnostic Script.
	for i, row in trace do
		local v = Instance.new("StringValue")
		v.Name = string.format("Decision%03d", i)
		v.Value = Http:JSONEncode(row)
		v.Parent = script
	end
	print("[BRT016_ROOT_RESULT] " .. Http:JSONEncode(result))
end, debug.traceback)
N.SelectReturnStep = original
script:SetAttribute("Done", true)
script:SetAttribute("Error", not ok and tostring(err) or nil)
