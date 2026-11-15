--!nocheck
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local BrainrotTerritory = require(ReplicatedStorage.Shared.Config.BrainrotTerritory)
	local NaturalTerritory = require(script.Parent.Parent.Systems.NaturalTerritory)
	local Roaming = require(script.Parent.Parent.Systems.DevelopmentBrainrotRoaming)
	local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)

	local function record(itemId)
		return {
			ItemId = itemId,
			BrainrotId = "BRT_007",
			Metadata = { Tier = "Common" },
			World = {
				Name = "Natural_" .. itemId,
				Scale = 1,
				SpawnPosition = { X = 0, Y = 0, Z = 0 },
			},
		}
	end

	local function pointArea(index)
		local marker = Instance.new("Part")
		marker.Name = "Point_" .. index
		marker.Anchored = true
		marker.Position = Vector3.new(index, 0, 0)
		return {
			Id = marker.Name,
			Kind = "Point",
			Enabled = true,
			UsableProbeCount = 1,
			Part = marker,
		}
	end

	local deterministicRandom = {
		NextInteger = function(_, _, upper)
			return upper
		end,
		NextNumber = function(_, lower, upper)
			return (lower + upper) * 0.5
		end,
	}

	-- Synthetic Camp/base geometry uses the production steering selector and
	-- segment-safe callback seam. The protected rectangle is expanded for the
	-- target footprint, just as live protection checks include its whole body.
	local function crossesRectangle(from, to, bounds)
		local enter, leave = 0, 1
		for _, axis in { "X", "Z" } do
			local delta = to[axis] - from[axis]
			local lower, upper = bounds[axis][1], bounds[axis][2]
			if math.abs(delta) < 1e-8 then
				if from[axis] < lower or from[axis] > upper then
					return false
				end
			else
				local first, last = (lower - from[axis]) / delta, (upper - from[axis]) / delta
				enter = math.max(enter, math.min(first, last))
				leave = math.min(leave, math.max(first, last))
				if enter > leave then
					return false
				end
			end
		end
		return true
	end

	local function runReturnRoute(start, destination, protectedBase, allowedSide, useMemory)
		local source = assert(NaturalTerritory.BindCampReturn(record("ROUTE_SAME_ID"), "Volcano"))
		local position = start
		local steering = if useMemory then NaturalTerritory.CreateReturnSteering() else nil
		local sideChanges = 0
		local previousSide = nil
		local stepCount = 0
		for step = 1, 160 do
			stepCount = step
			if (position - destination).Magnitude < 8 then
				return true, steering, stepCount, sideChanges, source
			end
			local nextPosition = NaturalTerritory.SelectReturnStep(
				position,
				destination,
				{ 18, 9, 4.5 },
				{ 0, 30, -30, 60, -60, 90, -90 },
				function(candidate)
					local withinCampConnection = allowedSide == nil
						or (candidate.Z - start.Z) * allowedSide >= -0.01
					return withinCampConnection
						and not crossesRectangle(position, candidate, protectedBase)
				end,
				steering
			)
			if nextPosition then
				local side = if steering then steering.EscapeSide else nil
				if side and previousSide and side ~= previousSide then
					sideChanges += 1
				end
				previousSide = side or previousSide
				position = nextPosition
			end
		end
		return false, steering, stepCount, sideChanges, source
	end

	describe("Phase 6F-2 natural territory metadata", function()
		it("extends Camp-return protection from the ground through an elevated Body", function()
			local model = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "Root"
			root.Size = Vector3.new(1, 1, 1)
			root.CFrame = CFrame.new(0, 0, 0)
			root.Parent = model
			model.PrimaryPart = root
			local body = Instance.new("Part")
			body.Name = "Body"
			body.Size = Vector3.new(2, 2, 3)
			body.CFrame = CFrame.new(0, 4, 0)
			body.Parent = model

			local frame, size =
				Roaming._TestCampReturnProtectionEnvelope(model, Vector3.new(10, 0, 20), 0)
			expect(frame).never.to.equal(nil)
			expect(size).never.to.equal(nil)
			expect((assert(frame).Position - Vector3.new(10, 2.5, 20)).Magnitude < 1e-6).to.equal(
				true
			)
			expect(
				(assert(size, "expected Camp-return envelope size") - Vector3.new(2, 5, 3)).Magnitude
					< 1e-6
			).to.equal(true)
			model:Destroy()
		end)

		it("segments long Camp-return blockcasts within the engine distance limit", function()
			local segments = Roaming._TestRouteSegmentLengths(1067.079102)
			expect(#segments).to.equal(2)
			expect(segments[1] < 1024).to.equal(true)
			expect(segments[2] < 1024).to.equal(true)
			expect(math.abs(segments[1] + segments[2] - 1067.079102) < 1e-6).to.equal(true)
		end)

		it("keeps immutable spawn provenance separate from the active AI constraint", function()
			local natural, reason = NaturalTerritory.BindNaturalSpawn(record("A"), "Forest")
			assert(natural, reason)
			expect(NaturalTerritory.GetSpawnRegionId(natural)).to.equal("REGION_FOREST")
			expect(NaturalTerritory.GetTerritoryRegionId(natural)).to.equal("REGION_FOREST")

			local controlled = assert(NaturalTerritory.ClearForPlayerControl(natural))
			expect(controlled.ItemId).to.equal(natural.ItemId)
			expect(controlled.BrainrotId).to.equal(natural.BrainrotId)
			expect(NaturalTerritory.GetSpawnRegionId(controlled)).to.equal("REGION_FOREST")
			expect(NaturalTerritory.GetTerritoryRegionId(controlled)).to.equal(nil)
			expect(NaturalTerritory.ClearForPlayerControl(controlled)).to.equal(controlled)
			expect(NaturalTerritory.GetTerritoryRegionId(natural)).to.equal("REGION_FOREST")
		end)

		it("tracks same-species individuals independently by runtime record", function()
			local first = assert(NaturalTerritory.BindNaturalSpawn(record("A"), "Forest"))
			local second = assert(NaturalTerritory.BindNaturalSpawn(record("B"), "Forest"))
			local controlled = assert(NaturalTerritory.ClearForPlayerControl(first))
			expect(NaturalTerritory.GetTerritoryRegionId(controlled)).to.equal(nil)
			expect(NaturalTerritory.GetTerritoryRegionId(second)).to.equal("REGION_FOREST")
			expect(controlled.ItemId).to.equal("A")
			expect(second.ItemId).to.equal("B")
		end)

		it(
			"marks a dropped individual for one-time Camp return without making it natural",
			function()
				local source = record("CampDrop")
				local returning, reason = NaturalTerritory.BindCampReturn(source, "Glitch Zone")
				assert(returning, reason)
				expect(returning.ItemId).to.equal("CampDrop")
				expect(returning.BrainrotId).to.equal("BRT_007")
				expect(NaturalTerritory.GetSpawnRegionId(returning)).to.equal(nil)
				expect(NaturalTerritory.GetTerritoryRegionId(returning)).to.equal(nil)
				expect(NaturalTerritory.GetReturnRegionId(returning)).to.equal("REGION_GLITCH")
				local controlled = assert(NaturalTerritory.ClearForPlayerControl(returning))
				expect(NaturalTerritory.GetReturnRegionId(controlled)).to.equal(nil)
				expect(NaturalTerritory.BindCampReturn(source, "Camp")).to.equal(nil)
			end
		)

		it("chooses the nearest safe inward recovery goal without mutating candidates", function()
			local candidates = {
				Vector3.new(12, 0, 0),
				Vector3.new(4, 0, 0),
				Vector3.new(8, 0, 0),
			}
			local selected = NaturalTerritory.SelectRecoveryGoal(
				Vector3.zero,
				candidates,
				function(candidate)
					return candidate.X >= 4
				end,
				function(candidate)
					return candidate.X ~= 4
				end
			)
			expect(selected).to.equal(Vector3.new(8, 0, 0))
			expect(candidates[1]).to.equal(Vector3.new(12, 0, 0))
			expect(NaturalTerritory.SelectRecoveryGoal(Vector3.zero, candidates, function()
				return false
			end, function()
				return true
			end)).to.equal(nil)
		end)

		it("uses bounded local steering when the direct Camp-return step is blocked", function()
			local inspected = {}
			local selected = NaturalTerritory.SelectReturnStep(
				Vector3.zero,
				Vector3.new(100, 0, 0),
				{ 18, 9 },
				{ 0, 30, -30 },
				function(candidate)
					table.insert(inspected, candidate)
					return candidate.Z > 0
				end
			)
			expect(selected).never.to.equal(nil)
			expect(math.abs(selected.Magnitude - 18) < 1e-6).to.equal(true)
			expect(selected.Z > 0).to.equal(true)
			expect(#inspected).to.equal(2)
		end)

		it("does not invent a Camp-return step when every bounded retry is unsafe", function()
			local selected = NaturalTerritory.SelectReturnStep(
				Vector3.zero,
				Vector3.new(100, 0, 0),
				{ 18, 9, 4.5 },
				{ 0, 30, -30 },
				function()
					return false
				end
			)
			expect(selected).to.equal(nil)
		end)

		it("permits one bounded lateral Camp-return step around an obstacle", function()
			local selected = NaturalTerritory.SelectReturnStep(
				Vector3.zero,
				Vector3.new(100, 0, 0),
				{ 9 },
				{ 0, 90, 180 },
				function(candidate)
					return candidate.Z > 0
				end
			)
			expect(selected ~= nil).to.equal(true)
			local actual = assert(selected, "expected a bounded lateral Camp-return step")
			expect((actual - Vector3.new(0, 0, 9)).Magnitude < 1e-6).to.equal(true)
		end)

		for _, side in { 1, -1 } do
			it(
				"reaches home around a protected base using escape side " .. tostring(side),
				function()
					local completed, steering, steps, sideChanges, source = runReturnRoute(
						Vector3.zero,
						Vector3.new(300, 0, 0),
						{ X = { 24, 180 }, Z = { -90, 90 } },
						side,
						true
					)
					expect(completed).to.equal(true)
					expect(steps < 80).to.equal(true)
					expect(sideChanges).to.equal(0)
					expect(#steering.RecentPositions <= 10).to.equal(true)
					expect(steering.ReturnStuck).to.equal(false)
					expect(source.ItemId).to.equal("ROUTE_SAME_ID")
					expect(source.BrainrotId).to.equal("BRT_007")
				end
			)
		end

		it(
			"reproduces stateless Volcano oscillation and completes the same route with bounded memory",
			function()
				local start, destination = Vector3.new(280, 0, -56), Vector3.new(580, 0, -47)
				local obstacle = { X = { 290, 440 }, Z = { -150, 70 } }
				local statelessCompleted = runReturnRoute(start, destination, obstacle, nil, false)
				expect(statelessCompleted).to.equal(false)
				local completed, steering, steps =
					runReturnRoute(start, destination, obstacle, nil, true)
				expect(completed).to.equal(true)
				expect(steps < 80).to.equal(true)
				expect(steering.ReturnStuck).to.equal(false)
			end
		)

		it("reports bounded failure when every return direction remains blocked", function()
			local steering = NaturalTerritory.CreateReturnSteering()
			for _ = 1, 130 do
				expect(
					NaturalTerritory.SelectReturnStep(
						Vector3.zero,
						Vector3.new(100, 0, 0),
						{ 18, 9, 4.5 },
						{ 0, 30, -30, 60, -60, 90, -90 },
						function()
							return false
						end,
						steering
					)
				).to.equal(nil)
			end
			expect(steering.ReturnStuck).to.equal(true)
			expect(steering.LastHomeDistance).to.equal(100)
			expect(steering.DecisionCount).to.equal(130)
			expect(#steering.RecentPositions).to.equal(1)
		end)

		it("keeps the bounded lateral escape at the recorded Forest Float32 boundary", function()
			local position = Vector3.new(-5.9578857421875, 0.1499997079372406, -316.29583740234375)
			local destination = Vector3.new(-19, position.Y, -598)
			local steering = NaturalTerritory.CreateReturnSteering()
			steering.EscapeForward = Vector3.new(0.9989920854568481, 0, -0.04488738626241684)
			steering.EscapeSide, steering.EscapeTurns = 1, 3
			steering.BestHomeDistance, steering.EscapePeakDistance =
				250.87721252441407, 288.93743896484377
			-- Recorded actual decision positions; the player-world instance is not
			-- reused. Shorter safe choices revisit this lane, but the 18-stud escape
			-- must not vanish because of a redundant triangle-inequality check.
			for _, point in
				{
					{ -7.606248378753662, -344.4261169433594 },
					{ -6.48354959487915, -328.6612854003906 },
					{ -6.622819900512695, -331.658203125 },
					{ -6.763540267944336, -334.6863098144531 },
					{ -6.058391571044922, -318.9659423828125 },
					{ -6.197747707366943, -321.9706115722656 },
					{ -6.3404107093811035, -325.0466003417969 },
					{ -5.63731575012207, -309.3717346191406 },
					{ -5.777580261230469, -312.4013671875 },
					{ -5.920899868011475, -315.4969787597656 },
				}
			do
				table.insert(steering.RecentPositions, Vector3.new(point[1], position.Y, point[2]))
			end
			local goal = NaturalTerritory.SelectReturnStep(
				position,
				destination,
				{ 18, 9, 4.5, 2.25 },
				{ 0, 30, -30, 60, -60, 90, -90 },
				function()
					return true
				end,
				steering
			)
			assert(goal, "Valid bounded lateral step must survive Float32 map-coordinate rounding")
			expect(math.abs((goal - position).Magnitude - 18) < 1e-4).to.equal(true)
			expect(steering.EscapeSide).to.equal(1)
			expect(steering.LastSelectedAngle).to.equal(90)
			expect(#steering.RecentPositions <= 10).to.equal(true)
			-- Exhausted steering retains its side but must not keep walking away
			-- from home after the viable direct lane is excluded by recent memory.
			expect(steering.EscapeTurns).to.equal(0)
			expect((steering.EscapeForward - (destination - position).Unit).Magnitude < 1e-6).to.equal(
				true
			)
			local progress = position
			local completed = false
			for _ = 1, 100 do
				if (progress - destination).Magnitude < 8 then
					completed = true
					break
				end
				local nextGoal = NaturalTerritory.SelectReturnStep(
					progress,
					destination,
					{ 18, 9, 4.5, 2.25 },
					{ 0, 30, -30, 60, -60, 90, -90 },
					function(candidate)
						return not crossesRectangle(progress, candidate, {
							X = { -69, 31 },
							Z = { -416, -348 },
						})
					end,
					steering
				)
				if nextGoal then
					local delta = nextGoal - progress
					-- Production arrives within 1.5 studs, not exactly at its goal.
					progress += delta.Unit * math.max(0, delta.Magnitude - 1.4)
				end
			end
			expect(completed).to.equal(true)
			expect(steering.ReturnStuck).to.equal(false)
		end)
	end)

	it("escapes the recorded BRT_016 Base_08 dead-side history within bounded decisions", function()
		-- Synthetic geometry measured from the actual Development source after
		-- production canonical scaling; not a substitute species or point agent.
		local folder = Instance.new("Folder")
		folder.Name = "SPEC_BRT016_BASE08"
		folder.Parent = workspace
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.Size = Vector3.one
		root.CFrame = CFrame.identity
		root.Parent = model
		model.PrimaryPart = root
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Anchored = true
		body.CanCollide = false
		body.Size = Vector3.new(1.612658381, 1.325622320, 1.417188287)
		body.CFrame = CFrame.new(0.00002098, 1.48121405, 0.311508179)
		body.Parent = model
		local foundation = Instance.new("Part")
		foundation.Name = "Foundation"
		foundation.Anchored = true
		foundation.Size = Vector3.new(96, 1, 64)
		foundation.CFrame = CFrame.new(-19, 0.55, 290)
		foundation.Parent = folder
		local ramp = Instance.new("WedgePart")
		ramp.Name = "HouseRamp"
		ramp.Anchored = true
		ramp.Size = Vector3.new(20, 1, 12)
		ramp.CFrame = CFrame.new(-43, 0.55, 252)
		ramp.Parent = folder
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { folder }
		local ok, err = xpcall(function()
			local position = Vector3.new(-30.141313552856445, 0.15126726031303406, 253.55419921875)
			local destination = Vector3.new(-19, 0.15126726031303406, 506)
			local state = NaturalTerritory.CreateReturnSteering()
			state.EscapeSide = 1
			state.EscapeTurns = 3
			state.EscapeForward = Vector3.new(-0.9990275502204895, 0, 0.04409054294228554)
			state.EscapePeakDistance = 270
			state.BestHomeDistance = 250
			state.RecentPositions = {
				Vector3.new(-15.51314926147461, 0.15126726031303406, 254.03939819335938),
				Vector3.new(-16.222187042236328, 0.15126726031303406, 255.23016357421875),
				Vector3.new(-23.820524215698242, 0.15126726031303406, 255.12498474121094),
				Vector3.new(-26.822526931762695, 0.15126726031303406, 255.08343505859375),
				Vector3.new(-29.824018478393555, 0.15126726031303406, 255.04188537597656),
				Vector3.new(-29.986753463745117, 0.15126726031303406, 237.843505859375),
				Vector3.new(-29.67969512939453, 0.15126726031303406, 245.33802795410156),
				Vector3.new(-29.556602478027344, 0.15126726031303406, 248.3423614501953),
				Vector3.new(-29.433778762817383, 0.15126726031303406, 251.34014892578125),
				Vector3.new(-29.772506713867188, 0.15126726031303406, 252.850341796875),
			}
			local completed = false
			for _ = 1, 128 do
				local nextGoal = NaturalTerritory.SelectReturnStep(
					position,
					destination,
					{ 18, 9, 4.5, 2.25 },
					{ 0, 30, -30, 60, -60, 90, -90 },
					function(candidate)
						local cf, size = Roaming._TestCampReturnRouteEnvelope(
							model,
							position,
							candidate,
							position.Y
						)
						return #workspace:GetPartBoundsInBox(cf, size, params) == 0
					end,
					state
				)
				if nextGoal then
					local delta = nextGoal - position
					position += delta.Unit * math.max(0, delta.Magnitude - 1.4)
					local cf, size =
						Roaming._TestCampReturnRouteEnvelope(model, position, position, position.Y)
					expect(#workspace:GetPartBoundsInBox(cf, size, params)).to.equal(0)
				end
				if position.Z > 390 then
					completed = true
					break
				end
			end
			assert(
				completed,
				"BRT_016 did not escape Base_08; decisions="
					.. state.DecisionCount
					.. " stuck="
					.. tostring(state.ReturnStuck)
			)
			expect(state.ReturnStuck).to.equal(false)
			expect(state.DecisionCount < 80).to.equal(true)
			expect(#state.RecentPositions <= 10).to.equal(true)
		end, debug.traceback)
		model:Destroy()
		folder:Destroy()
		if not ok then
			error(err, 0)
		end
	end)

	it(
		"switches an exhausted escape side only after a safe opposite candidate is proven",
		function()
			local state = NaturalTerritory.CreateReturnSteering()
			state.EscapeSide, state.EscapeTurns = 1, 3
			state.EscapeForward = Vector3.xAxis
			state.EscapePeakDistance = 100
			local goal = NaturalTerritory.SelectReturnStep(
				Vector3.zero,
				Vector3.new(100, 0, 0),
				{ 18, 9, 4.5, 2.25 },
				{ 0, 30, -30, 60, -60, 90, -90 },
				function(p)
					return math.abs(p.X) < 0.01 and p.Z < -1
				end,
				state
			)
			expect(goal ~= nil).to.equal(true)
			expect(state.EscapeSide).to.equal(-1)
			expect(state.EscapeSideFlipped).to.equal(true)
			-- Same episode, opposite becomes blocked: do not alternate indefinitely.
			for _ = 1, 10 do
				NaturalTerritory.SelectReturnStep(
					Vector3.zero,
					Vector3.new(100, 0, 0),
					{ 18 },
					{ 0, 90, -90 },
					function()
						return false
					end,
					state
				)
			end
			expect(state.EscapeSide).to.equal(-1)
			expect(state.EscapeSideFlipped).to.equal(true)
		end
	)

	it("does not switch sides or erase history when opposite candidates are unsafe", function()
		local state = NaturalTerritory.CreateReturnSteering()
		state.EscapeSide, state.EscapeTurns = 1, 3
		state.EscapeForward = Vector3.xAxis
		state.EscapePeakDistance = 100
		state.RecentPositions = { Vector3.new(1, 0, 0) }
		local goal = NaturalTerritory.SelectReturnStep(
			Vector3.zero,
			Vector3.new(100, 0, 0),
			{ 18 },
			{ 0, 90, -90 },
			function()
				return false
			end,
			state
		)
		expect(goal).to.equal(nil)
		expect(state.EscapeSide).to.equal(1)
		expect(state.EscapeSideFlipped).to.equal(nil)
		expect(state.RecentPositions[1]).to.equal(Vector3.new(1, 0, 0))
	end)

	describe("Phase 6F-2 bounded natural placement", function()
		it("accepts the first valid point without changing the selected species", function()
			local areas = { pointArea(1), pointArea(2) }
			local calls = 0
			local pose, attempts, reason = World._TestFindNaturalPlacement(
				"BRT_007",
				"REGION_FOREST",
				areas,
				deterministicRandom,
				function(speciesId, regionId, areaId, candidate)
					calls += 1
					expect(speciesId).to.equal("BRT_007")
					expect(regionId).to.equal("REGION_FOREST")
					expect(areaId).to.equal("Point_1")
					return {
						valid = true,
						reasons = {},
						placementPivot = CFrame.new(candidate),
					}
				end
			)
			expect(pose).never.to.equal(nil)
			expect(attempts).to.equal(1)
			expect(calls).to.equal(1)
			expect(reason).to.equal(nil)
			for _, area in areas do
				area.Part:Destroy()
			end
		end)

		it("tests point markers without replacement and stops at the shared budget", function()
			local areas = {}
			for index = 1, 21 do
				table.insert(areas, pointArea(index))
			end
			local calls = 0
			local pose, attempts, reason = World._TestFindNaturalPlacement(
				"BRT_007",
				"Forest",
				areas,
				deterministicRandom,
				function(_, _, _, candidate)
					calls += 1
					if candidate.X == 21 then
						return { valid = true, reasons = {}, placementPivot = CFrame.new(candidate) }
					end
					return { valid = false, reasons = { "INSUFFICIENT_CLEARANCE" } }
				end
			)
			expect(pose).to.equal(nil)
			expect(attempts).to.equal(BrainrotTerritory.MaxPlacementAttemptsPerSpawn)
			expect(calls).to.equal(BrainrotTerritory.MaxPlacementAttemptsPerSpawn)
			expect(reason).to.equal("ATTEMPT_BUDGET_EXHAUSTED")
			for _, area in areas do
				area.Part:Destroy()
			end
		end)

		it("fails explicitly when a region has no usable area", function()
			local pose, attempts, reason = World._TestFindNaturalPlacement(
				"BRT_007",
				"Forest",
				{},
				deterministicRandom,
				function()
					error("validator must not run")
				end
			)
			expect(pose).to.equal(nil)
			expect(attempts).to.equal(0)
			expect(reason).to.equal("NO_SPAWN_AREAS")
		end)
	end)
end
