local fs = require("@lune/fs")
local serde = require("@lune/serde")
local M = require("./BurrowFitMath")
local cases = {}
local function expect(ok, text)
	assert(ok, text or "Burrow fit assertion failed")
end
local function case(name, fn)
	local ok, error = pcall(fn)
	table.insert(cases, { name = name, passed = ok, error = if ok then nil else tostring(error) })
	expect(ok, name .. ": " .. tostring(error))
end
local function box(x, y, z, sx, sy, sz, yaw)
	return M.Box(M.Frame({ x, y, z }, yaw or 0), { sx, sy, sz })
end
case("continuous swept SAT detects midpoint blocker missed by endpoints", function()
	local start = box(-10, 2, 0, 2, 2, 2)
	local wall = box(0, 2, 0, 2, 8, 8)
	expect(not M.Sweep(start, { 0, 0, 0 }, wall).intersects)
	expect(not M.Sweep(box(10, 2, 0, 2, 2, 2), { 0, 0, 0 }, wall).intersects)
	expect(M.Sweep(start, { 20, 0, 0 }, wall).intersects)
end)
case("positive all-path margin certifies separated parallel movement", function()
	local result = M.Sweep(box(0, 2, 0, 2, 2, 2), { 0, 0, 40 }, box(5, 2, 20, 2, 8, 80))
	expect(not result.intersects and math.abs(result.wholeSweepSeparatingGap - 3) < 1e-8)
end)
case("rotated obstacle cross-axis SAT preserves overlap", function()
	expect(
		M.Sweep(box(0, 0, 0, 4, 4, 4), { 0, 0, 0 }, box(2, 0, 0, 4, 4, 4, math.pi / 4)).intersects
	)
	expect(
		not M.Sweep(box(0, 0, 0, 4, 4, 4), { 0, 0, 0 }, box(12, 0, 0, 4, 4, 4, math.pi / 4)).intersects
	)
end)
case("roof separation uses the actual vertical box extents", function()
	local r = M.Sweep(box(0, 2, 0, 4, 4, 4), { 30, 0, 0 }, box(15, 25, 0, 100, 6, 100))
	expect(not r.intersects and math.abs(r.wholeSweepSeparatingGap - 18) < 1e-8)
end)
case("root-relative asymmetric radius is not centred bbox radius", function()
	local native = { min = { 0, -0.04, -1 }, max = { 8, 3, 1 } }
	expect(M.Radius(native) > 8)
	local turn = M.TurnBox(M.Frame({ 0, 0, 0 }, 0), native, 2, 0.05)
	expect(turn.half[1] > 10 and turn.half[3] > 10)
	expect(turn.centre[2] - turn.half[2] < -0.04)
end)
case("native below-pivot extent is retained without lift", function()
	local b = M.WildBox(
		M.Frame({ 0, 0.04, 0 }, 0),
		{ min = { -1, -0.03519326448440552, -1 }, max = { 1, 3, 1 } },
		0,
		0
	)
	expect(math.abs(b.centre[2] - b.half[2] - 0.00480673551559448) < 1e-12)
end)
case("tangent contact alone is not positive-volume overlap", function()
	expect(not M.Sweep(box(0, 0, 0, 2, 2, 2), { 0, 0, 0 }, box(2, 0, 0, 2, 2, 2)).intersects)
	expect(M.Sweep(box(0, 0, 0, 2, 2, 2), { 0, 0, 0 }, box(1.99, 0, 0, 2, 2, 2)).intersects)
end)
case("invalid and reflected frames cannot yield a false pass", function()
	expect(not pcall(M.Box, M.Frame({ 0, 0, 0 }, 0), { 0, 2, 2 }))
	expect(
		not pcall(
			M.WildBox,
			M.Frame({ 0, 0, 0 }, 0),
			{ min = { -1, 0, -1 }, max = { 1, math.huge, 1 } },
			2,
			0.05
		)
	)
	expect(not pcall(M.Box, { 0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, 1 }, { 2, 2, 2 }))
end)
case("all-yaw turn certificate rejects an actor too large for the room", function()
	local turn = M.TurnBox(
		M.Frame({ 0, 0.04, 36 }, 0),
		{ min = { -10, 0, -10 }, max = { 10, 4, 10 } },
		2,
		0.05
	)
	expect(M.Sweep(turn, { 0, 0, 0 }, box(-15, 13, 27, 6, 30, 54)).intersects)
end)
case("concave reservation notch is excluded by exact convex-cell SAT", function()
	local cells =
		{ { { 0, 0 }, { 8, 0 }, { 8, 2 }, { 0, 2 } }, { { 0, 2 }, { 2, 2 }, { 2, 8 }, { 0, 8 } } }
	local notch = box(6, 2, 6, 1, 2, 1)
	local arm = box(1, 2, 6, 1, 2, 1)
	local notchHit, armHit = false, false
	for _, cell in cells do
		notchHit = notchHit or M.ConvexPrismIntersectsBox(cell, 0, 4, notch)
		armHit = armHit or M.ConvexPrismIntersectsBox(cell, 0, 4, arm)
	end
	expect(not notchHit and armHit, "AABB notch false positive must be excluded")
end)
local expected =
	serde.decode("json", fs.readFile("tools/environment-v2/BurrowNativeFitExpected.json"))
local function area(ring)
	local out = 0
	for i, p in ring do
		local q = ring[i % #ring + 1]
		out += p[1] * q[2] - q[1] * p[2]
	end
	return math.abs(out / 2)
end
case("every frozen concave or rectangular reservation has equal-area convex cells", function()
	local polygons = {}
	for _, room in expected.rooms do
		for _, polygon in room.apronPolygons do
			table.insert(polygons, polygon)
		end
	end
	for _, row in expected.externalReservations do
		table.insert(polygons, row.polygon)
	end
	expect(#polygons == 49, "All 49 query reservations required")
	for _, polygon in polygons do
		local sum = 0
		for _, cell in polygon.convexCells do
			expect(#cell == 3, "Exact triangle cells expected")
			sum += area(cell)
		end
		expect(
			math.abs(sum - area(polygon.exterior)) < 1e-6,
			"Reservation polygon union area must match"
		)
	end
end)
local checks = 0
case("all 35 captured native envelopes fit all 14 planned continuous L routes", function()
	for _, room in expected.rooms do
		local path = {}
		for _, name in expected.pathOrder do
			local marker = room.markers[name]
			table.insert(path, { marker[1], marker[2], marker[3] })
		end
		for id, species in expected.wild do
			local native = { min = species.min, max = species.max }
			for leg = 1, 3 do
				local a, b = path[leg], path[leg + 1]
				local actor = M.WildBox(M.Frame(a, M.Heading(a, b)), native, 2, 0.05)
				for _, mask in room.colliders do
					expect(
						not M.Sweep(actor, M.Sub(b, a), M.Box(mask.cframe, mask.size)).intersects,
						room.id .. "/" .. id .. "/leg" .. leg
					)
					checks += 1
				end
			end
			local turn = M.TurnBox(room.markers.Art_Turn, native, 2, 0.05)
			for _, mask in room.colliders do
				expect(
					not M.Sweep(turn, { 0, 0, 0 }, M.Box(mask.cframe, mask.size)).intersects,
					room.id .. "/" .. id .. "/turn"
				)
				checks += 1
			end
		end
	end
	expect(checks == 13720)
end)
local result = {
	status = "PureMathAndCapturedPlanPassed_NativeInstalledRunPending",
	passed = #cases,
	failed = 0,
	cases = cases,
	sourceSHA256 = expected.sourceSHA256,
	planSHA256 = expected.planSHA256,
	continuousPaddedColliderChecks = checks,
	actualStudioCalls = 0,
	actualInstalledNativeQA = "NotRun",
}
fs.writeFile(
	"docs/environment-v2/BurrowNativeFitSourceTests.json",
	serde.encode("json", result, true)
)
print(
	"BURROW_NATIVE_FIT_SOURCE_TESTS "
		.. #cases
		.. " passed; "
		.. checks
		.. " padded continuous checks; native installed QA NOT RUN"
)
return result
