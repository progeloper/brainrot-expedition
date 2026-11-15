--!strict
-- Pure union/shared-boundary extraction and whole-thickness aperture subtraction.
local B = {}
local EPS = 1e-9
local function pair(a, b)
	return if a < b then { a, b } else { b, a }
end
local function unique(values)
	table.sort(values)
	local out = {}
	for _, v in ipairs(values) do
		if #out == 0 or math.abs(v - out[#out]) > EPS then
			table.insert(out, v)
		end
	end
	return out
end
local function merge(lines, prefix)
	table.sort(lines, function(a, b)
		if a.key ~= b.key then
			return a.key < b.key
		end
		if a.fixed ~= b.fixed then
			return a.fixed < b.fixed
		end
		return a.first < b.first
	end)
	local runs = {}
	for _, line in ipairs(lines) do
		local last = runs[#runs]
		if
			last
			and last.key == line.key
			and math.abs(last.fixed - line.fixed) <= EPS
			and line.first <= last.last + EPS
		then
			last.last = math.max(last.last, line.last)
		else
			table.insert(
				runs,
				{
					key = line.key,
					axis = line.axis,
					fixed = line.fixed,
					first = line.first,
					last = line.last,
					regionPair = line.regionPair,
					regionId = line.regionId,
				}
			)
		end
	end
	for i, r in ipairs(runs) do
		r.id = string.format("%s%02d", prefix, i)
	end
	return runs
end
function B.Extract(rectangles)
	assert(#rectangles > 0, "Floor union missing")
	local xs, zs = {}, {}
	for _, r in ipairs(rectangles) do
		assert(
			type(r.regionId) == "string" and r.x0 < r.x1 and r.z0 < r.z1,
			"Floor identity/bounds invalid"
		)
		table.insert(xs, r.x0)
		table.insert(xs, r.x1)
		table.insert(zs, r.z0)
		table.insert(zs, r.z1)
	end
	xs, zs = unique(xs), unique(zs)
	local cells, area = {}, {}
	for i = 1, #xs - 1 do
		cells[i] = {}
		for j = 1, #zs - 1 do
			local x, z = (xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
			local owner = nil
			for _, r in ipairs(rectangles) do
				if x > r.x0 and x < r.x1 and z > r.z0 and z < r.z1 then
					assert(
						owner == nil or owner == r.regionId,
						"Different-region floor interiors overlap"
					)
					owner = r.regionId
				end
			end
			cells[i][j] = owner
			if owner then
				area[owner] = (area[owner] or 0) + (xs[i + 1] - xs[i]) * (zs[j + 1] - zs[j])
			end
		end
	end
	local shared, outer = {}, {}
	local function owner(i, j)
		return if cells[i] then cells[i][j] else nil
	end
	local function add(a, b, axis, fixed, first, last)
		if not a or a == b then
			return
		end
		if b then
			local p = pair(a, b)
			table.insert(
				shared,
				{
					axis = axis,
					fixed = fixed,
					first = first,
					last = last,
					regionPair = p,
					key = p[1] .. "/" .. p[2] .. "/" .. axis,
				}
			)
		else
			table.insert(
				outer,
				{ axis = axis, fixed = fixed, first = first, last = last, regionId = a, key = a
					.. "/"
					.. axis }
			)
		end
	end
	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			local a = owner(i, j)
			if a then
				local right, back = owner(i + 1, j), owner(i, j + 1)
				add(a, right, "Z", xs[i + 1], zs[j], zs[j + 1])
				add(a, back, "X", zs[j + 1], xs[i], xs[i + 1])
				if not owner(i - 1, j) then
					add(a, nil, "Z", xs[i], zs[j], zs[j + 1])
				end
				if not owner(i, j - 1) then
					add(a, nil, "X", zs[j], xs[i], xs[i + 1])
				end
			end
		end
	end
	return { sharedRuns = merge(shared, "R"), outerRuns = merge(outer, "O"), regionAreas = area }
end
function B.MapRuns(runs, c, T)
	local out = {}
	for _, r in ipairs(runs) do
		local a = if r.axis == "X" then { r.first, 0, r.fixed } else { r.fixed, 0, r.first }
		local b = if r.axis == "X" then { r.last, 0, r.fixed } else { r.fixed, 0, r.last }
		a, b = T.Point(a, c), T.Point(b, c)
		local row = {
			id = r.id,
			key = r.key,
			axis = r.axis,
			regionPair = r.regionPair,
			regionId = r.regionId,
			source = { fixed = r.fixed, first = r.first, last = r.last },
		}
		row.fixed = if r.axis == "X" then a[3] else a[1]
		row.first = if r.axis == "X" then a[1] else a[3]
		row.last = if r.axis == "X" then b[1] else b[3]
		table.insert(out, row)
	end
	return out
end
local function clip(poly, axis, bound, keepGreater)
	local out = {}
	if #poly == 0 then
		return out
	end
	local previous = poly[#poly]
	local pv = previous[axis] - bound
	local previousInside = if keepGreater then pv >= -EPS else pv <= EPS
	for _, current in ipairs(poly) do
		local cv = current[axis] - bound
		local inside = if keepGreater then cv >= -EPS else cv <= EPS
		if inside ~= previousInside then
			local t = pv / (pv - cv)
			table.insert(
				out,
				{ previous[1] + (current[1] - previous[1]) * t, previous[2] + (current[2] - previous[2]) * t }
			)
		end
		if inside then
			table.insert(out, { current[1], current[2] })
		end
		previous, pv, previousInside = current, cv, inside
	end
	return out
end
function B.PrismInterval(run, polygon, thickness)
	assert(thickness > 0 and #polygon >= 3, "Positive wall thickness/protected polygon required")
	local normalAxis = if run.axis == "X" then 2 else 1
	local alongAxis = if run.axis == "X" then 1 else 2
	local clipped = clip(
		clip(polygon, normalAxis, run.fixed - thickness / 2, true),
		normalAxis,
		run.fixed + thickness / 2,
		false
	)
	if #clipped < 3 then
		return nil
	end
	local twiceArea = 0
	for i, p in ipairs(clipped) do
		local q = clipped[i % #clipped + 1]
		twiceArea += p[1] * q[2] - q[1] * p[2]
	end
	if math.abs(twiceArea) <= EPS then
		return nil
	end
	local first, last = math.huge, -math.huge
	for _, p in ipairs(clipped) do
		first = math.min(first, p[alongAxis])
		last = math.max(last, p[alongAxis])
	end
	first, last = math.max(run.first, first), math.min(run.last, last)
	if last - first <= EPS then
		return nil
	end
	return { first = first, last = last }
end
function B.Subtract(runs, openings, thickness)
	assert(thickness > 0, "Wall thickness invalid")
	local spans, cuts = {}, {}
	for _, run in ipairs(runs) do
		local intervals = {}
		for _, opening in ipairs(openings) do
			assert(
				type(opening.id) == "string" and type(opening.polygons) == "table",
				"Explicit crossing evidence required"
			)
			for _, polygon in ipairs(opening.polygons) do
				local hit = B.PrismInterval(run, polygon, thickness)
				if hit then
					hit.crossingId = opening.id
					hit.runId = run.id
					hit.regionPair = run.regionPair
					hit.fullWallThickness = thickness
					table.insert(cuts, hit)
					table.insert(intervals, hit)
				end
			end
		end
		table.sort(intervals, function(a, b)
			return a.first < b.first
		end)
		local cursor = run.first
		for _, cut in ipairs(intervals) do
			if cut.first > cursor + EPS then
				table.insert(
					spans,
					{
						runId = run.id,
						axis = run.axis,
						fixed = run.fixed,
						first = cursor,
						last = cut.first,
						regionPair = run.regionPair,
					}
				)
			end
			cursor = math.max(cursor, cut.last)
		end
		if cursor < run.last - EPS then
			table.insert(
				spans,
				{
					runId = run.id,
					axis = run.axis,
					fixed = run.fixed,
					first = cursor,
					last = run.last,
					regionPair = run.regionPair,
				}
			)
		end
	end
	return { spans = spans, cuts = cuts }
end
-- Resolve perpendicular collider junctions once before chunking. The lower run ID
-- owns the junction square; the higher run abuts its outer face. Cuts remain bound
-- to their approved opening IDs. A needed extension that hits an aperture fails.
function B.Junctions(spans, openings, thickness)
	local working, removals, junctions, failures, points = {}, {}, {}, {}, {}
	for i, s in ipairs(spans) do
		local copy = table.clone(s)
		working[i] = copy
		removals[i] = {}
	end
	for i = 1, #spans do
		for j = i + 1, #spans do
			local a, b = spans[i], spans[j]
			if a.axis ~= b.axis then
				local x = if a.axis == "X" then b.fixed else a.fixed
				local z = if a.axis == "X" then a.fixed else b.fixed
				local av = if a.axis == "X" then x else z
				local bv = if b.axis == "X" then x else z
				if
					av >= a.first - EPS
					and av <= a.last + EPS
					and bv >= b.first - EPS
					and bv <= b.last + EPS
				then
					local key = string.format("%.17g/%.17g", x, z)
					points[key] = { x, z }
				end
			end
		end
	end
	local ordered = {}
	for _, p in pairs(points) do
		table.insert(ordered, p)
	end
	table.sort(ordered, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		return a[2] < b[2]
	end)
	for _, point in ipairs(ordered) do
		local incident = {}
		for i, s in ipairs(spans) do
			local fixed = if s.axis == "X" then point[2] else point[1]
			local along = if s.axis == "X" then point[1] else point[2]
			if
				math.abs(s.fixed - fixed) <= EPS
				and along >= s.first - EPS
				and along <= s.last + EPS
			then
				table.insert(incident, i)
			end
		end
		table.sort(incident, function(a, b)
			if spans[a].runId ~= spans[b].runId then
				return spans[a].runId < spans[b].runId
			end
			return a < b
		end)
		local li = incident[1]
		local lower = working[li]
		local lv = if lower.axis == "X" then point[1] else point[2]
		local first, last =
			math.min(lower.first, lv - thickness / 2), math.max(lower.last, lv + thickness / 2)
		local blockers = {}
		for _, extension in ipairs({ { first, lower.first }, { lower.last, last } }) do
			if extension[2] - extension[1] > EPS then
				local fake = {
					axis = lower.axis,
					fixed = lower.fixed,
					first = extension[1],
					last = extension[2],
				}
				for _, o in ipairs(openings) do
					for _, poly in ipairs(o.polygons) do
						if B.PrismInterval(fake, poly, thickness) then
							table.insert(blockers, o.id)
						end
					end
				end
			end
		end
		local row = {
			point = point,
			ownerRunId = lower.runId,
			abuttingRunIds = {},
			extensionFirst = lower.first - first,
			extensionLast = last - lower.last,
		}
		if #blockers > 0 then
			row.status = "Conflict"
			row.apertureIds = blockers
			table.insert(failures, row)
		else
			lower.first, lower.last = first, last
			for k = 2, #incident do
				local hi = incident[k]
				local higher = working[hi]
				local hv = if higher.axis == "X" then point[1] else point[2]
				table.insert(
					removals[hi],
					{ first = hv - thickness / 2, last = hv + thickness / 2 }
				)
				table.insert(row.abuttingRunIds, higher.runId)
			end
			row.status = "Resolved"
			table.insert(junctions, row)
		end
	end
	local out = {}
	for i, s in ipairs(working) do
		table.sort(removals[i], function(a, b)
			return a.first < b.first
		end)
		local cursor = s.first
		for _, cut in ipairs(removals[i]) do
			if cut.first > cursor + EPS then
				local copy = table.clone(s)
				copy.first = cursor
				copy.last = math.min(cut.first, s.last)
				table.insert(out, copy)
			end
			cursor = math.max(cursor, cut.last)
		end
		if cursor < s.last - EPS then
			local copy = table.clone(s)
			copy.first = cursor
			copy.last = s.last
			table.insert(out, copy)
		end
	end
	table.sort(out, function(a, b)
		if a.runId ~= b.runId then
			return a.runId < b.runId
		end
		return a.first < b.first
	end)
	return { spans = out, junctions = junctions, failures = failures }
end
function B.Chunk(spans, maxLength, ground, thickness)
	assert(maxLength > 0 and thickness > 0, "Positive chunk/thickness required")
	local out = {}
	local counters = {}
	for _, span in ipairs(spans) do
		local cursor = span.first
		while cursor < span.last - EPS do
			local last = math.min(span.last, cursor + maxLength)
			local n = (counters[span.runId] or 0) + 1
			counters[span.runId] = n
			local mid = (cursor + last) / 2
			table.insert(
				out,
				{
					id = "RW_"
						.. span.regionPair[1]
						.. "_"
						.. span.regionPair[2]
						.. "_"
						.. span.runId
						.. "_"
						.. string.format("%03d", n),
					runId = span.runId,
					regionPair = span.regionPair,
					axis = span.axis,
					fixed = span.fixed,
					first = cursor,
					last = last,
					cframe = if span.axis == "X"
						then { mid, ground + 11, span.fixed, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
						else { span.fixed, ground + 11, mid, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
					size = if span.axis == "X"
						then { last - cursor, 26, thickness }
						else { thickness, 26, last - cursor },
					bottom = ground - 2,
					top = ground + 24,
				}
			)
			cursor = last
		end
	end
	return out
end
function B.ClassifyExisting(rows, source)
	local classified = {}
	for _, row in ipairs(rows) do
		local portions = {}
		local covered = {}
		for _, category in ipairs({
			{ "InterRegion", source.sharedRuns },
			{ "OuterContainment", source.outerRuns },
		}) do
			for _, run in ipairs(category[2]) do
				if row.axis == run.axis and math.abs(row.fixed - run.fixed) < 0.01 then
					local first, last = math.max(row.first, run.first), math.min(row.last, run.last)
					if last - first > EPS then
						table.insert(
							portions,
							{
								kind = category[1],
								runId = run.id,
								first = first,
								last = last,
								regionPair = run.regionPair,
								regionId = run.regionId,
							}
						)
						table.insert(covered, { first = first, last = last })
					end
				end
			end
		end
		table.sort(covered, function(a, b)
			return a.first < b.first
		end)
		local cursor = row.first
		for _, p in ipairs(covered) do
			assert(p.first <= cursor + 0.01, "Existing separator has unclassified gap")
			cursor = math.max(cursor, p.last)
		end
		assert(
			cursor >= row.last - 0.01,
			"Existing separator does not bind actual shared/outer boundary"
		)
		table.insert(
			classified,
			{
				id = row.id,
				path = row.path,
				regionId = row.regionId,
				source = row,
				portions = portions,
				outerPolicy = "Retain only captured outer portions; do not generate new containment",
			}
		)
	end
	return classified
end
return B
