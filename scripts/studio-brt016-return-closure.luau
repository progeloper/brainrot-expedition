--!nocheck
-- Temporary, explicitly installed Development mechanical gate, no persistence.
-- Reuses the production factory/lifecycle/movement. No piloting, teleport,
-- artificial speed or substitute collision model after initial staged release.
assert(game:GetService("RunService"):IsStudio() and game.PlaceId == 91958083796436)
local S = game.ServerScriptService.Server.Systems
local W, N, R, C =
	require(S.DevelopmentBrainrotSpawner),
	require(S.NaturalTerritory),
	require(S.DevelopmentBrainrotRoaming),
	require(S.RegionSpawnCatalog)
local Http = game:GetService("HttpService")
local model, state, current, rows = nil, nil, nil, {}
local original = N.SelectReturnStep
local function vec(p)
	return { p.X, p.Y, p.Z }
end
N.SelectReturnStep = function(...)
	local a = table.pack(...)
	local observed = model and (a[1] - model:GetPivot().Position).Magnitude < 0.01
	local tested = {}
	local previousSide = nil
	if observed then
		if current.seedHistory and not current.seeded then
			-- Exact dead episode captured in the failing single-returner live run.
			-- This is controlled state replay, never a normal gameplay path.
			local st = a[6]
			st.EscapeSide = 1
			st.EscapeTurns = 3
			st.EscapeForward = Vector3.new(-0.9990275502, 0, 0.04409054294)
			st.EscapePeakDistance = 270
			st.BestHomeDistance = 250
			st.RecentPositions = {}
			for _, p in
				{
					{ -15.5131493, 254.0393982 },
					{ -16.2221870, 255.2301636 },
					{ -23.8205242, 255.1249847 },
					{ -26.8225269, 255.0834351 },
					{ -29.8240185, 255.0418854 },
					{ -29.9867535, 237.8435059 },
					{ -29.6796951, 245.33802795 },
					{ -29.5566025, 248.34236145 },
					{ -29.4337788, 251.3401489 },
					{ -29.7725067, 252.8503418 },
				}
			do
				table.insert(st.RecentPositions, Vector3.new(p[1], a[1].Y, p[2]))
			end
			current.seeded = true
		end
		previousSide = a[6].EscapeSide
		local safe = a[5]
		a[5] = function(p)
			local accepted = safe(p)
			local f, sz = R._TestCampReturnRouteEnvelope(model, a[1], p, a[1].Y)
			local blocked, _, owner = C.IsProtectedForCampReturn(f, sz)
			if owner then
				current.blockers[owner] = true
			end
			table.insert(tested, {
				position = vec(p),
				distance = (p - a[1]).Magnitude,
				safe = accepted,
				protected = blocked,
				owner = owner,
			})
			return accepted
		end
	end
	local result = original(table.unpack(a, 1, a.n))
	if observed then
		state = a[6]
		if previousSide and state.EscapeSide and previousSide ~= state.EscapeSide then
			current.flips += 1
		end
		local row = {
			decision = state.DecisionCount,
			position = vec(a[1]),
			destination = vec(a[2]),
			distance = state.LastHomeDistance,
			side = state.EscapeSide,
			frame = state.EscapeForward and vec(state.EscapeForward),
			noProgress = state.NoProgressDecisions,
			stuck = state.ReturnStuck,
			selected = result and vec(result),
			candidates = tested,
		}
		current.last = row
		if #current.trace < 180 then
			table.insert(current.trace, row)
		end
		script:SetAttribute(
			"Latest",
			Http:JSONEncode({
				case = current.name,
				decision = row.decision,
				position = row.position,
				stuck = row.stuck,
				flips = current.flips,
			})
		)
	end
	return result
end
local definitions = {
	{ "Base08_A", "REGION_JUNGLE", "BRT_016", -11.850422859, -10.629911423, false },
	{ "Base08_B", "REGION_JUNGLE", "BRT_016", 18.628704071, -59.906639099, false },
	{ "Base08_TerminalA", "REGION_JUNGLE", "BRT_016", -29.9266968, 254.5965576, true },
	{ "Base08_TerminalB", "REGION_JUNGLE", "BRT_016", -30.2432327, 254.7121735, true },
	{ "Base08_Reproduced", "REGION_JUNGLE", "BRT_016", -30.1413136, 253.5541992, true },
	{ "Beach", "REGION_BEACH", "BRT_015", 0, -30, false },
	{ "Forest", "REGION_FOREST", "BRT_010", 0, -30, false },
	{ "Swamp", "REGION_SWAMP", "BRT_014", 0, -30, false },
	{ "Jungle", "REGION_JUNGLE", "BRT_016", 0, -30, false },
	{ "Arctic", "REGION_ARCTIC", "BRT_008", 0, -30, false },
	{ "Volcano", "REGION_VOLCANO", "BRT_007", 0, -30, false },
	{ "Glitch", "REGION_GLITCH", "BRT_023", 0, -30, false },
}
local ok, err = xpcall(function()
	R.Start()
	for _, d in definitions do
		assert(W.GetWildCount() == 0, "One controlled returner only; never retire unrelated pilots")
		local pose = CFrame.new(d[4], 3, d[5])
		local record = assert(W.CreateWorldRecord(d[3], "RootClosure_" .. d[1], pose))
		local prepared = assert(W.PrepareWorldRepresentation(record, pose))
		local safe = assert(W.FindSafeReleasePose(prepared, pose, {}, true))
		prepared.Model:PivotTo(safe)
		current = { name = d[1], seedHistory = d[6], trace = {}, blockers = {}, flips = 0 }
		state = nil
		model = assert(W.ActivatePreparedWorld(prepared))
		local start = os.clock()
		local row = {
			name = d[1],
			region = d[2],
			species = d[3],
			id = record.ItemId,
			start = vec(safe.Position),
			seededDeadEpisode = d[6],
			started = model:GetAttribute("CampReturnRegionId") == d[2],
		}
		repeat
			task.wait(0.5)
		until model:GetAttribute("CampReturnRegionId") == nil
			or (state and state.ReturnStuck)
			or os.clock() - start >= 420
		row.seconds = os.clock() - start
		row.position = vec(model:GetPivot().Position)
		local region = C.GetRegionAtPosition(model:GetPivot().Position)
		row.finalRegion = region and region.id
		row.sameId = model:GetAttribute("ItemId") == record.ItemId
		row.sameSpecies = model:GetAttribute("BrainrotId") == d[3]
		row.cleared = model:GetAttribute("CampReturnRegionId") == nil
		row.decisions = state and state.DecisionCount
		row.stuck = state and state.ReturnStuck
		row.flips = current.flips
		row.blockers = current.blockers
		row.population = W.GetPopulationSnapshot()
		local endPosition = model:GetPivot().Position
		if row.cleared then
			task.wait(8)
		end
		row.roamed = row.cleared and (model:GetPivot().Position - endPosition).Magnitude > 0.1
		row.pass = row.started
			and row.sameId
			and row.sameSpecies
			and row.cleared
			and row.roamed
			and row.finalRegion == d[2]
			and row.population.Wild == 1
			and row.population.Reserved == 0
		table.insert(rows, row)
		script:SetAttribute("Results", Http:JSONEncode(rows))
		local folder = Instance.new("Folder")
		folder.Name = d[1]
		folder.Parent = script
		for i, decision in current.trace do
			local v = Instance.new("StringValue")
			v.Name = string.format("Decision%03d", i)
			v.Value = Http:JSONEncode(decision)
			v.Parent = folder
		end
		print("[BRT016_CLOSURE_ROUTE] " .. Http:JSONEncode(row))
		if not row.pass then
			script:SetAttribute("PreservedFailureItemId", record.ItemId)
			break
		end
		assert(W.DestroyWorldForTesting(record.ItemId))
		model = nil
	end
end, debug.traceback)
N.SelectReturnStep = original
script:SetAttribute("Done", true)
script:SetAttribute("Error", not ok and tostring(err) or nil)
