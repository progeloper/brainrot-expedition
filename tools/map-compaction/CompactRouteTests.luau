--!strict
-- Tests invoke actual pure planner modules. Literal Appendix fixtures, independent
-- SAT/coverage checks and captured restrictive walls prevent self-derived passes.
return function(T, B, R, input)
	local results = { passed = 0, failed = 0, cases = {} }
	local currentName = "Pure planner test"
	local function check(condition, message)
		assert(condition, message or currentName)
	end
	local function test(name, fn)
		currentName = name
		local ok, err = pcall(fn)
		table.insert(
			results.cases,
			{ name = name, passed = ok, error = if ok then nil else tostring(err) }
		)
		if ok then
			results.passed += 1
		else
			results.failed += 1
		end
	end
	local function near(a, b, e)
		check(math.abs(a - b) <= (e or 1e-8), tostring(a) .. " differs from " .. tostring(b))
	end
	local c = T.Candidate(0.75, 0.75)
	test("Preferred literal candidate knots", function()
		check(c.t == 80 and c.r == 168 and c.h == 224)
		near(T.MapAxis(136, c), 80)
		near(T.MapAxis(313, c), 168)
		near(T.MapAxis(420, c), 212)
		near(T.MapAxis(432, c), 224)
	end)
	test("All ladder rows are monotone, odd and invertible", function()
		for _, b in ipairs({ 0.75, 0.8, 0.85, 0.9, 0.95, 1 }) do
			for _, outer in ipairs({ 0.75, 0.8, 0.85 }) do
				local row = T.Candidate(b, outer)
				local last = -math.huge
				for i = -2000, 2000, 7 do
					local y = T.MapAxis(i, row)
					check(y > last)
					last = y
					near(T.MapAxis(-i, row), -y)
					near(T.InverseAxis(y, row), i, 1e-9)
				end
			end
		end
	end)
	test("Final twelve-stud protected band remains full size", function()
		for _, b in ipairs({ 0.75, 0.8, 0.85, 0.9, 0.95, 1 }) do
			local row = T.Candidate(b, 0.75)
			near(T.MapAxis(432, row) - T.MapAxis(420, row), 12)
			near(T.MapAxis(429, row) - T.MapAxis(423, row), 6)
		end
	end)
	test("Invalid/nonfinite factors reject", function()
		for _, b in ipairs({ 0, -1, math.huge, 0 / 0 }) do
			check(not pcall(T.Candidate, b, 0.75))
		end
	end)
	test("XYZ roundtrip preserves exact Y", function()
		for _, p in ipairs({
			{ -1091, 17.25, -958 },
			{ -19, -55, -46 },
			{ 1053, 3.5, 866 },
			{ -451, 0.04999995231628418, 386 },
		}) do
			local q = T.Point(p, c)
			check(q[2] == p[2])
			local r = T.InversePoint(q, c)
			for i = 1, 3 do
				near(r[i], p[i], 1e-9)
			end
		end
	end)
	test("Rigid rotated frame changes position only", function()
		local cf = { -500, 22, -700, 0, 0, 1, 0, 1, 0, -1, 0, 0 }
		local r = T.RigidFrame(cf, c)
		for i = 4, 12 do
			check(r[i] == cf[i])
		end
		check(r[2] == 22)
	end)
	test("Long diagonal includes every crossed X/Z band plane", function()
		local a, b = { -600, 5, -500 }, { 800, 25, 600 }
		local split = T.SubdivideSegment(a, b, c)
		check(#split.sourcePoints > 10)
		for _, axis in ipairs({ 1, 3 }) do
			for _, k in ipairs({ 136, 313, 420, 432 }) do
				for _, sign in ipairs({ -1, 1 }) do
					local plane = c.origin[axis] + sign * k
					if plane > a[axis] and plane < b[axis] then
						local found = false
						for _, p in ipairs(split.sourcePoints) do
							if math.abs(p[axis] - plane) < 1e-8 then
								found = true
							end
						end
						check(found, "Missing band plane")
					end
				end
			end
		end
		for i = 1, #split.sourcePoints - 1 do
			local p, q = split.sourcePoints[i], split.sourcePoints[i + 1]
			local mid = T.Point({ (p[1] + q[1]) / 2, (p[2] + q[2]) / 2, (p[3] + q[3]) / 2 }, c)
			for axis = 1, 3 do
				near(mid[axis], (split.targetPoints[i][axis] + split.targetPoints[i + 1][axis]) / 2)
			end
		end
		local endpointMid = {
			(split.targetPoints[1][1] + split.targetPoints[#split.targetPoints][1]) / 2,
			15,
			(split.targetPoints[1][3] + split.targetPoints[#split.targetPoints][3]) / 2,
		}
		local trueMid = T.Point({ 100, 15, 50 }, c)
		check(
			math.abs(endpointMid[1] - trueMid[1]) + math.abs(endpointMid[3] - trueMid[3]) > 1,
			"Endpoint-only mapping accidentally accepted"
		)
	end)
	test("Camp floor edges preserve height/thickness", function()
		local cf, size = T.Floor(
			{ -19, -1.9500000476837158, -46, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
			{ 864, 4, 864 },
			c
		)
		check(size[1] == 448 and size[3] == 448 and size[2] == 4 and cf[2] == -1.9500000476837158)
		check(
			not pcall(T.Floor, { -19, -1.95, -46, 0, 0, 1, 0, 1, 0, -1, 0, 0 }, { 864, 4, 864 }, c)
		)
	end)
	test("Same-region union cancels internal/duplicate floor seams", function()
		local e = B.Extract({
			{ regionId = "A", x0 = 0, x1 = 10, z0 = 0, z1 = 10 },
			{ regionId = "A", x0 = 10, x1 = 20, z0 = 0, z1 = 10 },
			{ regionId = "A", x0 = 0, x1 = 10, z0 = 0, z1 = 10 },
		})
		check(#e.sharedRuns == 0 and #e.outerRuns == 4 and e.regionAreas.A == 200)
	end)
	test("Unequal opposite spans split neighbor pairs; corners do not create runs", function()
		local e = B.Extract({
			{ regionId = "A", x0 = 0, x1 = 10, z0 = 0, z1 = 20 },
			{ regionId = "B", x0 = 10, x1 = 20, z0 = 0, z1 = 7 },
			{ regionId = "C", x0 = 10, x1 = 20, z0 = 7, z1 = 20 },
			{ regionId = "D", x0 = 20, x1 = 30, z0 = 20, z1 = 30 },
		})
		check(#e.sharedRuns == 3)
		check(e.regionAreas.A == 200)
		for _, r in ipairs(e.sharedRuns) do
			check(r.last > r.first and r.regionPair[1] ~= "D" and r.regionPair[2] ~= "D")
		end
	end)
	test("Concave actual union differs from AABB", function()
		local e = B.Extract({
			{ regionId = "A", x0 = 0, x1 = 20, z0 = 0, z1 = 10 },
			{ regionId = "A", x0 = 0, x1 = 10, z0 = 10, z1 = 20 },
			{ regionId = "B", x0 = 10, x1 = 20, z0 = 10, z1 = 20 },
		})
		check(e.regionAreas.A == 300 and #e.sharedRuns == 2)
		check(#e.outerRuns == 6)
	end)
	test("Distinct small intended gaps stay distinct", function()
		local e = B.Extract({
			{ regionId = "A", x0 = 0, x1 = 10, z0 = 0, z1 = 10 },
			{ regionId = "B", x0 = 10.005, x1 = 20, z0 = 0, z1 = 10 },
		})
		check(#e.sharedRuns == 0 and #e.outerRuns == 8)
	end)
	test("Overlapping different-region interiors reject", function()
		check(
			not pcall(
				B.Extract,
				{ { regionId = "A", x0 = 0, x1 = 10, z0 = 0, z1 = 10 }, {
					regionId = "B",
					x0 = 9,
					x1 = 20,
					z0 = 0,
					z1 = 10,
				} }
			)
		)
	end)
	test("Whole wall thickness catches a protected prism missing the seam centre", function()
		local run = { axis = "X", fixed = 0, first = 0, last = 100 }
		local p = { { 30, 1 }, { 40, 1 }, { 40, 2 }, { 30, 2 } }
		local hit = B.PrismInterval(run, p, 6)
		check(hit and hit.first == 30 and hit.last == 40)
		check(B.PrismInterval(run, { { 30, 3 }, { 40, 3 }, { 40, 4 }, { 30, 4 } }, 6) == nil)
	end)
	test("Overlapping apertures subtract once without leaking a gap", function()
		local runs = { { id = "R", axis = "X", fixed = 0, first = 0, last = 100, regionPair = {
			"A",
			"B",
		} } }
		local s = B.Subtract(
			runs,
			{
				{ id = "X1", polygons = { { { 20, -5 }, { 40, -5 }, { 40, 5 }, { 20, 5 } } } },
				{ id = "X2", polygons = { { { 30, -5 }, { 60, -5 }, { 60, 5 }, { 30, 5 } } } },
			},
			6
		)
		check(#s.spans == 2 and s.spans[1].last == 20 and s.spans[2].first == 60)
	end)
	test("Global junction lower-ID owner resolves three-region volume once", function()
		local spans = {
			{ runId = "R01", axis = "X", fixed = 0, first = -20, last = 0, regionPair = { "A", "B" } },
			{ runId = "R02", axis = "X", fixed = 0, first = 0, last = 20, regionPair = { "A", "C" } },
			{ runId = "R03", axis = "Z", fixed = 0, first = 0, last = 20, regionPair = { "B", "C" } },
		}
		local j = B.Junctions(spans, {}, 6)
		check(#j.junctions == 1 and #j.failures == 0 and j.junctions[1].ownerRunId == "R01")
		check(j.spans[1].last == 3 and j.spans[2].first == 3 and j.spans[3].first == 3)
	end)
	test("Junction extension cannot encroach an approved opening", function()
		local spans = {
			{ runId = "R01", axis = "X", fixed = 0, first = -20, last = 0, regionPair = { "A", "B" } },
			{ runId = "R02", axis = "Z", fixed = 0, first = 0, last = 20, regionPair = { "A", "C" } },
		}
		local j = B.Junctions(
			spans,
			{ { id = "Gate", polygons = { { { 1, -1 }, { 4, -1 }, { 4, 1 }, { 1, 1 } } } } },
			6
		)
		check(#j.failures == 1 and j.spans[1].last == 0 and j.spans[2].first == 0)
	end)
	test("Chunk lengths start lexically, meet exactly and preserve foundation", function()
		local w = B.Chunk(
			{ { runId = "R", axis = "X", fixed = 10, first = -10, last = 300, regionPair = {
				"A",
				"B",
			} } },
			128,
			0.05,
			6
		)
		check(
			#w == 3
				and w[1].first == -10
				and w[1].last == 118
				and w[2].first == 118
				and w[3].last == 300
		)
		for _, v in ipairs(w) do
			check(v.last - v.first <= 128)
			near(v.bottom, -1.95)
			near(v.top, 24.05)
			near(v.cframe[2], 11.05)
		end
	end)
	local source = B.Extract(input.floors)
	local runs = B.MapRuns(source.sharedRuns, c, T)
	local routes = R.Build(input.routes, c, T, input.connectivityCaps)
	local aprons = R.GateAprons(input.gates, routes, input.gateRouteOwners, c, T)
	local x =
		R.Crossings(input.routes, source.sharedRuns, runs, aprons, input.legacySeparators, c, T)
	local s = B.Subtract(runs, x.openings, 6)
	local j = B.Junctions(s.spans, x.openings, 6)
	local walls = B.Chunk(j.spans, 128, input.floors[1].ground, 6)
	test("Fresh complete capture binds 25 floors,85 routes,6 gates,27 native roads", function()
		check(
			#input.floors == 25
				and #input.routes == 85
				and #input.gates == 6
				and #input.actualRoads == 27
		)
		for _, road in ipairs(input.actualRoads) do
			check(
				type(road.meshId) == "string"
					and string.find(road.meshId, "rbxassetid://", 1, true) == 1
			)
		end
	end)
	test("All eighteen shared runs match independent literal Appendix endpoints", function()
		local expect = {
			{ "Z", 205, -630, -270 },
			{ "X", -450, 445, 685 },
			{ "X", -270, 205, 445 },
			{ "Z", 445, -450, -270 },
			{ "X", -450, -483, -243 },
			{ "Z", -483, -450, 178 },
			{ "Z", -243, -630, -450 },
			{ "X", 178, -723, -483 },
			{ "X", -270, -243, 205 },
			{ "Z", -243, -270, 178 },
			{ "X", 178, -243, 205 },
			{ "Z", 205, -270, 178 },
			{ "X", 178, -483, -243 },
			{ "Z", 205, 178, 538 },
			{ "X", 178, 205, 685 },
			{ "X", 358, -483, -243 },
			{ "Z", -483, 358, 538 },
			{ "Z", -243, 178, 358 },
		}
		check(#runs == 18)
		for i, v in ipairs(expect) do
			local r = runs[i]
			check(r.id == string.format("R%02d", i) and r.axis == v[1])
			near(r.fixed, v[2])
			near(r.first, v[3])
			near(r.last, v[4])
		end
	end)
	test("Independent literal region areas and full floor envelope", function()
		local targetFloors = {}
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, floor in ipairs(input.floors) do
			local v = T.Rectangle(floor, c)
			table.insert(targetFloors, v)
			x0 = math.min(x0, v.x0)
			x1 = math.max(x1, v.x1)
			z0 = math.min(z0, v.z0)
			z1 = math.max(z1, v.z1)
		end
		local areas = B.Extract(targetFloors).regionAreas
		local expected = {
			REGION_ARCTIC = 129600,
			REGION_BEACH = 237120,
			REGION_CAMP = 200704,
			REGION_FOREST = 312000,
			REGION_GLITCH = 172800,
			REGION_JUNGLE = 204480,
			REGION_SWAMP = 129600,
			REGION_VOLCANO = 258240,
		}
		for id, area in pairs(expected) do
			near(areas[id], area)
		end
		near(x0, -723)
		near(x1, 685)
		near(z0, -630)
		near(z1, 538)
	end)
	test("Eight-stud interior grid keeps all logical region owners", function()
		local targets = {}
		for _, floor in ipairs(input.floors) do
			table.insert(targets, T.Rectangle(floor, c))
		end
		local samples = 0
		for _, floor in ipairs(input.floors) do
			local px = floor.x0 + 4
			while px < floor.x1 do
				local pz = floor.z0 + 4
				while pz < floor.z1 do
					local point = T.Point({ px, floor.ground, pz }, c)
					local owner = nil
					for _, target in ipairs(targets) do
						if
							point[1] > target.x0
							and point[1] < target.x1
							and point[3] > target.z0
							and point[3] < target.z1
						then
							check(
								owner == nil or owner == target.regionId,
								"Transformed floor interiors overlap"
							)
							owner = target.regionId
						end
					end
					check(owner == floor.regionId, "Interior region membership changed")
					samples += 1
					pz += 8
				end
				px += 8
			end
		end
		check(samples == 61104, "Complete8-stud sample count differs")
	end)
	test("All41 original separators classify; outer containment preserved separately", function()
		local rows = B.ClassifyExisting(input.legacySeparators, source)
		local n, o = 0, 0
		for _, row in ipairs(rows) do
			for _, p in ipairs(row.portions) do
				if p.kind == "InterRegion" then
					n += 1
				else
					o += 1
				end
			end
		end
		check(#rows == 41 and n == 32 and o == 10)
	end)
	test("Five closed alternate crossings retain physical restriction", function()
		local n = 0
		for _, row in ipairs(x.records) do
			if row.accessPolicy == "ExistingEquivalentRestriction" then
				n += 1
				check(row.apertureWidth == 0 and #row.legacyRestrictionIds > 0)
			end
		end
		check(n == 5)
	end)
	test("Exactly six paid owners and one40stud CampForest free exit", function()
		local paid, free = 0, 0
		for _, row in ipairs(x.records) do
			if row.owningGate then
				paid += 1
				check(row.apertureWidth == 36)
			elseif row.accessPolicy == "ExistingFreeCampForestRoad" then
				free += 1
				check(row.apertureWidth == 40)
			end
		end
		check(paid == 6 and free == 1 and #x.openings == 7)
	end)
	test("Route IDs/control vertices/widths and26 contact caps preserved", function()
		check(#routes.routes == 85 and #routes.caps == 26)
		for i, src in ipairs(input.routes) do
			local row = routes.routes[i]
			check(
				row.id == src.id
					and row.width == src.requiredWidth
					and #row.controlPoints == #src.points
			)
			for k, p in ipairs(src.points) do
				local q = T.Point(p, c)
				for axis = 1, 3 do
					near(row.controlPoints[k][axis], q[axis])
				end
			end
		end
	end)
	test("Complete465 convex route primitives remain one surface component", function()
		local connectivity = R.ConnectedComponents(routes.primitives)
		check(connectivity.primitiveCount == 465 and connectivity.count == 1)
		local n = 0
		for _ in pairs(connectivity.components[1].routeIds) do
			n += 1
		end
		check(n == 85)
	end)
	test("Disconnected numeric corridors report two components", function()
		local a = { id = "A", routeId = "A", polygon = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } }
		local b = { id = "B", routeId = "B", polygon = { { 2, 0 }, { 3, 0 }, { 3, 1 }, { 2, 1 } } }
		check(R.ConnectedComponents({ a, b }).count == 2)
	end)
	test("Seam-parallel route is a fit conflict rather than thousands of crossings", function()
		local src = {
			{
				id = "Along",
				role = "Main",
				footprintType = "polyline",
				requiredWidth = 28,
				points = { { 0, 0, -10 }, { 0, 0, 10 } },
			},
		}
		local sr = { { id = "R", axis = "Z", fixed = 0, first = -20, last = 20, regionPair = {
			"A",
			"B",
		} } }
		local tr = B.MapRuns(sr, c, T)
		local v = R.Crossings(src, sr, tr, {}, {}, c, T)
		check(
			#v.records == 0
				and #v.openings == 0
				and #v.parallelConflicts == 1
				and v.parallelConflicts[1].shortfall == 17
		)
	end)
	test("Gate return and prompt local offsets remain physical24/10stud distances", function()
		for _, gate in ipairs(aprons) do
			local cart = gate.descriptorFrames.safeCartCFrame
			local prompt = gate.descriptorFrames.interactionCFrame
			near(
				math.abs(
					(cart[1] - gate.ground[1]) * gate.normal[1]
						+ (cart[3] - gate.ground[3]) * gate.normal[3]
				),
				24
			)
			near(
				math.abs(
					(prompt[1] - gate.ground[1]) * gate.normal[1]
						+ (prompt[3] - gate.ground[3]) * gate.normal[3]
				),
				10
			)
			check(cart[2] > 5 and prompt[2] > 3 and gate.taperEachSide == 16)
		end
	end)
	test("Volcano uses actualz−462; gate and road offset both transform", function()
		local volcano
		for _, v in ipairs(aprons) do
			if v.name == "Volcano" then
				volcano = v
			end
		end
		check(volcano)
		near(volcano.ground[1], 205)
		near(volcano.ground[3], -256.3551401869159)
		near(volcano.intersection[3], -248.13084112149534)
		near(volcano.lateralRouteOffset, -8.224299065420568)
		local touched = {}
		for _, cut in ipairs(s.cuts) do
			if cut.crossingId == "Gate_Volcano" then
				touched[cut.runId] = true
			end
		end
		check(touched.R01 and touched.R03 and touched.R09 and touched.R12)
	end)
	local function box(w)
		local h = w.size[1] / 2
		local d = w.size[3] / 2
		return {
			{ w.cframe[1] - h, w.cframe[3] - d },
			{ w.cframe[1] + h, w.cframe[3] - d },
			{ w.cframe[1] + h, w.cframe[3] + d },
			{ w.cframe[1] - h, w.cframe[3] + d },
		}
	end
	local function overlaps(a, b)
		local axes = { { 1, 0 }, { 0, 1 } }
		for _, poly in ipairs({ a, b }) do
			for i, p in ipairs(poly) do
				local q = poly[i % #poly + 1]
				table.insert(axes, { -(q[2] - p[2]), q[1] - p[1] })
			end
		end
		for _, axis in ipairs(axes) do
			if math.abs(axis[1]) + math.abs(axis[2]) > 1e-12 then
				local alo, ahi, blo, bhi = math.huge, -math.huge, math.huge, -math.huge
				for _, p in ipairs(a) do
					local v = p[1] * axis[1] + p[2] * axis[2]
					alo = math.min(alo, v)
					ahi = math.max(ahi, v)
				end
				for _, p in ipairs(b) do
					local v = p[1] * axis[1] + p[2] * axis[2]
					blo = math.min(blo, v)
					bhi = math.max(bhi, v)
				end
				if math.min(ahi, bhi) - math.max(alo, blo) <= 1e-8 then
					return false
				end
			end
		end
		return true
	end
	test("Independent SAT: no final6thick wall volume intersects any aperture", function()
		check(#j.failures == 0)
		for _, w in ipairs(walls) do
			for _, opening in ipairs(x.openings) do
				for _, poly in ipairs(opening.polygons) do
					check(not overlaps(box(w), poly), w.id .. " encroaches " .. opening.id)
				end
			end
		end
	end)
	test("Independent SAT: no duplicate wall collider volume at junctions", function()
		for i = 1, #walls do
			for k = i + 1, #walls do
				check(
					not overlaps(box(walls[i]), box(walls[k])),
					walls[i].id .. " overlaps " .. walls[k].id
				)
			end
		end
	end)
	test("Independent interval probes: all non-aperture boundary points covered", function()
		local function covered(px, pz)
			for _, w in ipairs(walls) do
				if
					math.abs(px - w.cframe[1]) <= w.size[1] / 2 + 1e-8
					and math.abs(pz - w.cframe[3]) <= w.size[3] / 2 + 1e-8
				then
					return true
				end
			end
			return false
		end
		for _, run in ipairs(runs) do
			local stations = { run.first, run.last }
			local d = run.first + 0.5
			while d < run.last do
				table.insert(stations, d)
				d += 0.5
			end
			for _, a in ipairs(stations) do
				local px, pz =
					if run.axis == "X" then a else run.fixed,
					if run.axis == "X" then run.fixed else a
				local sample = if run.axis == "X"
					then {
						{ a - 0.00001, run.fixed - 3 },
						{ a + 0.00001, run.fixed - 3 },
						{ a + 0.00001, run.fixed + 3 },
						{ a - 0.00001, run.fixed + 3 },
					}
					else {
						{ run.fixed - 3, a - 0.00001 },
						{ run.fixed + 3, a - 0.00001 },
						{ run.fixed + 3, a + 0.00001 },
						{ run.fixed - 3, a + 0.00001 },
					}
				local excluded = false
				for _, opening in ipairs(x.openings) do
					for _, poly in ipairs(opening.polygons) do
						if overlaps(sample, poly) then
							excluded = true
						end
					end
				end
				if not excluded then
					check(covered(px, pz), run.id .. " uncovered at " .. a)
				end
			end
		end
	end)
	test("Candidate count is54 but apply/fit remains unassessed", function()
		check(
			#walls == 54
				and #x.parallelConflicts == 0
				and input.applyEligible == false
				and input.fitStatus == "NotRun"
		)
	end)
	return results
end
